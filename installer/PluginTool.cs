// The Stream Deck plugin and its profiles: install (same as a double-click on the .streamDeckPlugin: the Stream Deck app asks the user
// to confirm), compare what is installed with what this Setup carries, remove (plugin, ChasePlane profiles), and a few health checks.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Web.Script.Serialization;
using Microsoft.Win32;

namespace ChasePlaneDeckSetup
{
    internal sealed class ProfileInfo
    {
        public string Dir, Name, Model;
        public string Title { get { return Name + "  (" + Model + ")"; } }
    }

    internal static class PluginTool
    {
        public const string PluginFolder = "com.chaseplanexl.deck.sdPlugin";

        public static string StreamDeckExe()
        {
            string pf = Environment.GetEnvironmentVariable("ProgramFiles") ?? @"C:\Program Files";
            string pf86 = Environment.GetEnvironmentVariable("ProgramFiles(x86)") ?? @"C:\Program Files (x86)";
            foreach (string p in new[] { Path.Combine(pf, @"Elgato\StreamDeck\StreamDeck.exe"), Path.Combine(pf86, @"Elgato\StreamDeck\StreamDeck.exe") })
                if (File.Exists(p)) return p;
            // not in a default folder: ask Windows which program opens .streamDeckPlugin files
            try
            {
                using (RegistryKey ext = Registry.ClassesRoot.OpenSubKey(".streamDeckPlugin"))
                {
                    string prog = ext == null ? null : ext.GetValue(null) as string;
                    if (!string.IsNullOrEmpty(prog))
                        using (RegistryKey cmd = Registry.ClassesRoot.OpenSubKey(prog + @"\shell\open\command"))
                        {
                            string c = cmd == null ? null : cmd.GetValue(null) as string;
                            Match m = c == null ? null : Regex.Match(c, "^\\s*\"([^\"]+)\"");
                            if (m != null && m.Success && File.Exists(m.Groups[1].Value)) return m.Groups[1].Value;
                        }
                }
            }
            catch (Exception) { }
            return null;
        }

        public static string StreamDeckVersion(string exe)
        {
            try { return FileVersionInfo.GetVersionInfo(exe).FileVersion; } catch (Exception) { return "?"; }
        }

        public static bool StreamDeckRunning() { return Process.GetProcessesByName("StreamDeck").Length > 0; }

        // CPDECK_PLUGINS_DIR lets the tests work on a scratch folder instead of the real Stream Deck folders
        public static string PluginsDir()
        {
            string o = Environment.GetEnvironmentVariable("CPDECK_PLUGINS_DIR");
            if (!string.IsNullOrEmpty(o)) return o;
            return Path.Combine(Environment.GetEnvironmentVariable("APPDATA") ?? "", @"Elgato\StreamDeck\Plugins");
        }

        // the Stream Deck app keeps every profile as a folder <id>.sdProfile in ProfilesV3 (next to the Plugins folder)
        public static string ProfilesDir() { return Path.Combine(Path.GetDirectoryName(PluginsDir().TrimEnd('\\')), "ProfilesV3"); }

        public static string InstalledDir() { return Path.Combine(PluginsDir(), PluginFolder); }
        public static string InstalledManifest() { return Path.Combine(InstalledDir(), "manifest.json"); }
        public static bool IsInstalled() { return File.Exists(InstalledManifest()); }
        public static string LogFile() { return Path.Combine(InstalledDir(), @"logs\plugin.log"); }

        static Version ParseVersion(string json)
        {
            Match m = Regex.Match(json ?? "", "\"Version\"\\s*:\\s*\"([0-9][0-9.]*)\"");
            Version v;
            if (m.Success && Version.TryParse(m.Groups[1].Value, out v)) return v;
            return null;
        }

        public static Version InstalledVersion()
        {
            try { return IsInstalled() ? ParseVersion(File.ReadAllText(InstalledManifest())) : null; } catch (Exception) { return null; }
        }

        static ZipArchive OpenBundled() { return new ZipArchive(typeof(PluginTool).Assembly.GetManifestResourceStream("plugin.streamDeckPlugin"), ZipArchiveMode.Read); }

        public static Version BundledVersion()
        {
            using (ZipArchive za = OpenBundled())
            {
                ZipArchiveEntry e = za.GetEntry(PluginFolder + "/manifest.json");
                if (e == null) return null;
                using (StreamReader r = new StreamReader(e.Open())) return ParseVersion(r.ReadToEnd());
            }
        }

        // files of the bundled plugin that are missing or different in the installed folder (profiles are stored elsewhere by the Stream Deck app)
        public static List<string> Damaged()
        {
            List<string> bad = new List<string>();
            using (ZipArchive za = OpenBundled())
            using (SHA256 sha = SHA256.Create())
            {
                foreach (ZipArchiveEntry e in za.Entries)
                {
                    if (e.FullName.EndsWith("/") || e.FullName.IndexOf("/Profiles/", StringComparison.Ordinal) >= 0) continue;
                    string target = Path.Combine(PluginsDir(), e.FullName.Replace('/', '\\'));
                    if (!File.Exists(target)) { bad.Add(e.FullName + " (missing)"); continue; }
                    byte[] a;
                    using (Stream s = e.Open()) a = sha.ComputeHash(s);
                    byte[] b = sha.ComputeHash(File.ReadAllBytes(target));
                    if (!a.SequenceEqual(b)) bad.Add(e.FullName + " (changed)");
                }
            }
            return bad;
        }

        public static string Extract()
        {
            string dir = Path.Combine(Path.GetTempPath(), "ChasePlaneDeckSetup");
            Directory.CreateDirectory(dir);
            string file = Path.Combine(dir, "ChasePlane Deck.streamDeckPlugin");
            using (Stream s = typeof(PluginTool).Assembly.GetManifestResourceStream("plugin.streamDeckPlugin"))
            using (FileStream o = File.Create(file))
            {
                s.CopyTo(o);
            }
            return file;
        }

        // hands a .streamDeckPlugin / .streamDeckProfile to the Stream Deck app (the app asks the user to confirm)
        public static void Launch(string file)
        {
            ProcessStartInfo psi = new ProcessStartInfo(file);
            psi.UseShellExecute = true;
            Process.Start(psi);
        }

        // ---- the ChasePlane profiles in the Stream Deck app (found by their exact names, listed in profile-names.txt)
        static HashSet<string> OurProfileNames()
        {
            HashSet<string> names = new HashSet<string>(StringComparer.Ordinal);
            using (Stream s = typeof(PluginTool).Assembly.GetManifestResourceStream("profile-names.txt"))
            using (StreamReader r = new StreamReader(s, Encoding.UTF8))
            {
                string l;
                while ((l = r.ReadLine()) != null) { l = l.Trim(); if (l.Length > 0 && l[0] != '#') names.Add(l); }
            }
            return names;
        }

        public static List<ProfileInfo> FindProfiles()
        {
            List<ProfileInfo> list = new List<ProfileInfo>();
            string root = ProfilesDir();
            if (!Directory.Exists(root)) return list;
            HashSet<string> ours = OurProfileNames();
            JavaScriptSerializer js = new JavaScriptSerializer();
            foreach (string d in Directory.GetDirectories(root, "*.sdProfile"))
            {
                try
                {
                    string m = Path.Combine(d, "manifest.json");
                    if (!File.Exists(m)) continue;
                    Dictionary<string, object> o = js.DeserializeObject(File.ReadAllText(m)) as Dictionary<string, object>;
                    if (o == null || !o.ContainsKey("Name")) continue;
                    string name = o["Name"] as string;
                    if (name == null || !ours.Contains(name)) continue;
                    string model = "?";
                    Dictionary<string, object> dev = o.ContainsKey("Device") ? o["Device"] as Dictionary<string, object> : null;
                    if (dev != null && dev.ContainsKey("Model")) model = Convert.ToString(dev["Model"]);
                    list.Add(new ProfileInfo { Dir = d, Name = name, Model = model });
                }
                catch (Exception) { }
            }
            return list.OrderBy(delegate(ProfileInfo p) { return p.Name; }).ToList();
        }

        // ---- remove: close the Stream Deck app (it keeps plugin and profiles loaded), delete the plugin folder,
        // move the chosen profiles to a backup folder (not deleted), and start the app again unless restart is false
        public static bool Cleanup(ILog log, bool removePlugin, List<ProfileInfo> profiles, bool handleStreamDeck, bool restart)
        {
            string pluginDir = InstalledDir();
            bool pluginThere = removePlugin && Directory.Exists(pluginDir);
            bool anyProfiles = profiles != null && profiles.Count > 0;
            if (removePlugin && !pluginThere) log.Line(Loc.T("  The plugin is not installed.", "  De plugin is niet ge\u00efnstalleerd."));
            if (!pluginThere && !anyProfiles) return true;

            string exe = StreamDeckExe();
            bool wasRunning = handleStreamDeck && StreamDeckRunning();
            bool ok = true;
            try
            {
                if (wasRunning)
                {
                    log.Line(Loc.T("  Closing the Stream Deck app...", "  De Stream Deck-app wordt afgesloten..."));
                    foreach (Process p in Process.GetProcessesByName("StreamDeck")) { try { p.CloseMainWindow(); } catch (Exception) { } }
                    for (int i = 0; i < 16 && StreamDeckRunning(); i++) Thread.Sleep(250);
                    foreach (Process p in Process.GetProcessesByName("StreamDeck")) { try { p.Kill(); } catch (Exception) { } }
                    Thread.Sleep(800);
                }
                if (pluginThere)
                {
                    Exception last = null;
                    for (int i = 0; i < 8; i++)
                    {
                        try { Directory.Delete(pluginDir, true); last = null; break; }
                        catch (Exception ex) { last = ex; Thread.Sleep(500); }
                    }
                    if (last != null) { log.Line(Loc.T("  Could not remove the plugin folder: {0}", "  De pluginmap kon niet worden verwijderd: {0}", last.Message)); ok = false; }
                    else log.Line(Loc.T("  Plugin removed.", "  Plugin verwijderd."));
                }
                if (anyProfiles)
                {
                    string backup = Path.Combine(Path.GetDirectoryName(ProfilesDir()), "ChasePlaneDeck-removed-profiles-" + DateTime.Now.ToString("yyyyMMdd-HHmmss"));
                    int moved = 0;
                    foreach (ProfileInfo p in profiles)
                    {
                        try
                        {
                            Directory.CreateDirectory(backup);
                            Directory.Move(p.Dir, Path.Combine(backup, Path.GetFileName(p.Dir)));
                            moved++;
                        }
                        catch (Exception ex) { log.Line(Loc.T("  Could not move profile '{0}': {1}", "  Het profiel '{0}' kon niet worden verplaatst: {1}", p.Name, ex.Message)); ok = false; }
                    }
                    if (moved > 0) log.Line(Loc.T("  {0} profile(s) moved to {1} (move a folder back into ProfilesV3 to restore it).", "  {0} profiel(en) verplaatst naar {1} (zet een map terug in ProfilesV3 om het te herstellen).", moved, backup));
                }
                return ok;
            }
            finally
            {
                if (wasRunning && restart && exe != null)
                {
                    try { Process.Start(exe); log.Line(Loc.T("  Stream Deck app started again.", "  De Stream Deck-app is weer gestart.")); } catch (Exception) { }
                }
                try { string tmp = Path.Combine(Path.GetTempPath(), "ChasePlaneDeckSetup"); if (Directory.Exists(tmp)) Directory.Delete(tmp, true); } catch (Exception) { }
            }
        }

        // ---- health checks
        public static bool BridgeReachable()
        {
            try
            {
                using (TcpClient c = new TcpClient())
                {
                    IAsyncResult r = c.BeginConnect("127.0.0.1", 8652, null, null);
                    if (!r.AsyncWaitHandle.WaitOne(1000, false)) return false;
                    c.EndConnect(r);
                    return true;
                }
            }
            catch (Exception) { return false; }
        }

        public static List<string> RecentLogProblems(int max)
        {
            List<string> found = new List<string>();
            try
            {
                if (!File.Exists(LogFile())) return found;
                foreach (string l in File.ReadAllLines(LogFile()).Reverse())
                {
                    string low = l.ToLowerInvariant();
                    if (low.Contains("error") || low.Contains("failed") || low.Contains("exception")) { found.Add(l.Length > 160 ? l.Substring(0, 160) : l); if (found.Count >= max) break; }
                }
            }
            catch (Exception) { }
            return found;
        }
    }
}
