// Adds / removes the keyboard shortcuts the ChasePlane Deck profiles need in ChasePlane's user_settings.json.
// Rules (same as build\Apply-ChasePlaneKeys.ps1): only commands without a binding are added, existing bindings are never changed,
// a key combination that another command already uses is skipped, a timestamped backup is written first, the JSON is validated.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Web.Script.Serialization;

namespace ChasePlaneDeckSetup
{
    internal interface ILog { void Line(string text); }

    internal sealed class NullLog : ILog { public void Line(string text) { } }

    internal sealed class KeyDef
    {
        public string Command;
        public string Keys;      // e.g. Ctrl+Alt+F16
        public string Status;    // existing (ChasePlane default) | new (needs assigning)
        public bool InHybrid;    // needed by the plugin profiles (false = only the hotkeys-only profiles)
        public string Label;     // deck button text
        public bool IsNew { get { return Status == "new"; } }
    }

    internal sealed class SettingsFile
    {
        public string Path;
        public string Label;
    }

    // one saved copy of the settings file (made by Setup before it changed something)
    internal sealed class BackupInfo
    {
        public string Path;
        public DateTime Time;
        public int Shortcuts;    // the user's own bindings in it (Setup's deck keys not counted)
        public int Missing;      // of those, how many ChasePlane does not have now
        public bool Own;         // Setup's own copy outside ChasePlane's folder
    }

    internal sealed class ApplyResult
    {
        public bool Ok = true;
        public int Added, Present, Skipped, Notes, Removed;
        public bool Wrote;
    }

    internal static class KeyTool
    {
        static readonly Regex MappingRx = new Regex(@"(""control_mappings""\s*:\s*"")((?:[^""\\]|\\.)*)("")", RegexOptions.Singleline);
        static readonly Regex LineRx = new Regex(@"^(?<cmd>[A-Z0-9_]+)(?:\\u0026|&)(?<rest>.*)$");

        public static List<KeyDef> LoadKeys()
        {
            List<KeyDef> list = new List<KeyDef>();
            using (Stream s = typeof(KeyTool).Assembly.GetManifestResourceStream("keys.txt"))
            using (StreamReader r = new StreamReader(s, Encoding.UTF8))
            {
                string line;
                while ((line = r.ReadLine()) != null)
                {
                    line = line.Trim();
                    if (line.Length == 0 || line[0] == '#') continue;
                    string[] f = line.Split('|');
                    if (f.Length < 5) continue;
                    list.Add(new KeyDef { Command = f[0], Keys = f[1], Status = f[2], InHybrid = f[3] == "yes", Label = f[4] });
                }
            }
            return list;
        }

        // ---- where ChasePlane keeps its settings (Parallel 42 wiki: "ChasePlane, where are the files?")
        public static List<SettingsFile> FindSettingsFiles()
        {
            string app = Environment.GetEnvironmentVariable("APPDATA") ?? "";
            string local = Environment.GetEnvironmentVariable("LOCALAPPDATA") ?? "";
            List<SettingsFile> all = new List<SettingsFile>();
            all.Add(new SettingsFile { Label = "MSFS 2024 (Steam)", Path = System.IO.Path.Combine(app, @"Microsoft Flight Simulator 2024\WASM\MSFS2024\p42-util-chaseplane\work\user_settings.json") });
            all.Add(new SettingsFile { Label = "MSFS 2024 (Microsoft Store)", Path = System.IO.Path.Combine(local, @"Packages\Microsoft.Limitless_8wekyb3d8bbwe\LocalState\WASM\MSFS2024\p42-util-chaseplane\work\user_settings.json") });
            all.Add(new SettingsFile { Label = "MSFS 2020 (Steam)", Path = System.IO.Path.Combine(app, @"Microsoft Flight Simulator\Packages\p42-util-chaseplane\work\user_settings.json") });
            all.Add(new SettingsFile { Label = "MSFS 2020 (Microsoft Store)", Path = System.IO.Path.Combine(local, @"Packages\Microsoft.FlightSimulator_8wekyb3d8bbwe\LocalState\packages\p42-util-chaseplane\work\user_settings.json") });
            return all.Where(delegate(SettingsFile f) { return File.Exists(f.Path); }).ToList();
        }

        public static List<string> RunningSimProcesses()
        {
            List<string> names = new List<string>();
            int self = Process.GetCurrentProcess().Id;
            foreach (Process p in Process.GetProcesses())
            {
                string n;
                try { n = p.ProcessName; } catch (Exception) { continue; }
                if (p.Id == self) continue;                                          // this installer itself has "ChasePlane" in its name
                string l = n.ToLowerInvariant();
                if (l.StartsWith("chaseplane-deck")) continue;
                if (l.Contains("flightsimulator") || l.Contains("chaseplane") || l.StartsWith("cp msfs")) { if (!names.Contains(n)) names.Add(n); }
            }
            return names;
        }

        // ---- key combos -> ChasePlane's "1|Keyboard|<virtual key>|2|0;" entries
        static int Vk(string key)
        {
            int n;
            if (key.Length == 1 && char.IsLetterOrDigit(key[0])) return char.ToUpperInvariant(key[0]);
            if (key.Length >= 2 && key[0] == 'F' && int.TryParse(key.Substring(1), out n)) return 111 + n;
            switch (key)
            {
                case "Shift": return 160;
                case "Ctrl": return 162;
                case "Alt": return 164;
                case "End": return 35;
                case "PageUp": return 33;
                case "Space": return 32;
            }
            throw new InvalidOperationException("Unknown key " + key);
        }

        static string EntryFor(string combo)
        {
            string[] parts = combo.Split('+');
            StringBuilder sb = new StringBuilder();
            foreach (string m in new[] { "Shift", "Ctrl", "Alt" })
                if (Array.IndexOf(parts, m) >= 0) sb.Append("1|Keyboard|" + Vk(m) + "|2|0;");
            sb.Append("1|Keyboard|" + Vk(parts[parts.Length - 1]) + "|2|0;");
            return sb.ToString();
        }

        // order-independent signature of a binding, used to find two commands on the same keys
        static string Canon(string entries)
        {
            List<string> parts = new List<string>();
            foreach (string e in entries.Split(new[] { ';' }, StringSplitOptions.RemoveEmptyEntries))
            {
                string[] f = e.Split('|');
                if (f.Length >= 3) parts.Add(f[1] + ":" + f[2]);
            }
            parts.Sort(StringComparer.Ordinal);
            return string.Join("+", parts.ToArray());
        }

        static string OneLine(string s) { return s.Replace("\\n", " ").Replace("\n", " "); }

        // ---- reading the settings file
        sealed class Mapping
        {
            public Match M;
            public string Text, Body, Sep;
            public bool Bom;
            public Dictionary<string, List<string>> ByCmd = new Dictionary<string, List<string>>();
            public Dictionary<string, string> ByCanon = new Dictionary<string, string>();
        }

        static Mapping Read(string path)
        {
            byte[] bytes = File.ReadAllBytes(path);
            Mapping mp = new Mapping();
            mp.Bom = bytes.Length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF;
            string text = Encoding.UTF8.GetString(bytes);
            if (mp.Bom) text = text.Substring(1);
            mp.Text = text;
            mp.M = MappingRx.Match(text);
            if (!mp.M.Success) return null;
            mp.Body = mp.M.Groups[2].Value;
            mp.Sep = (mp.Body.Contains("\\u0026") || mp.Body.Length == 0) ? "\\u0026" : "&";
            foreach (string raw in mp.Body.Split(new[] { "\\n" }, StringSplitOptions.RemoveEmptyEntries))
            {
                Match lm = LineRx.Match(raw);
                if (!lm.Success) continue;
                string cmd = lm.Groups["cmd"].Value, rest = lm.Groups["rest"].Value;
                if (!mp.ByCmd.ContainsKey(cmd)) mp.ByCmd[cmd] = new List<string>();
                mp.ByCmd[cmd].Add(rest);
                string c = Canon(rest);
                if (c.Length > 0 && !mp.ByCanon.ContainsKey(c)) mp.ByCanon[c] = cmd;
            }
            return mp;
        }

        // two changes in the same second must not overwrite each other's backup
        static string Unique(string basePath)
        {
            string p = basePath;
            for (int i = 2; File.Exists(p); i++) p = basePath + "-" + i;
            return p;
        }

        // Setup's own copy of every settings file it changes, kept OUTSIDE ChasePlane's folder: if that folder is reset,
        // the .bak next to the settings file goes with it
        static string OwnDir(string settingsPath)
        {
            string root = Environment.GetEnvironmentVariable("CPDECK_BACKUP_DIR");
            if (string.IsNullOrEmpty(root))
            {
                string app = Environment.GetEnvironmentVariable("APPDATA");
                if (string.IsNullOrEmpty(app)) return null;
                root = System.IO.Path.Combine(app, @"ChasePlane Deck\Backups");
            }
            string id;
            using (SHA1 sha = SHA1.Create())
                id = BitConverter.ToString(sha.ComputeHash(Encoding.UTF8.GetBytes(System.IO.Path.GetFullPath(settingsPath).ToLowerInvariant()))).Replace("-", "").Substring(0, 10);
            return System.IO.Path.Combine(root, id);
        }

        static void SaveOwnCopy(string path, string stamp, ILog log)
        {
            try
            {
                string dir = OwnDir(path);
                if (dir == null) return;
                Directory.CreateDirectory(dir);
                File.WriteAllText(System.IO.Path.Combine(dir, "source.txt"), path, Encoding.UTF8);
                File.Copy(path, Unique(System.IO.Path.Combine(dir, System.IO.Path.GetFileName(path) + ".bak-" + stamp)), false);
            }
            catch (Exception ex)
            {
                log.Line(Loc.T("  note: Setup's own extra copy could not be made ({0}); the backup next to the file was.", "  let op: de extra kopie van Setup zelf kon niet worden gemaakt ({0}); de back-up naast het bestand is wel gemaakt.", ex.Message));
            }
        }

        // validate, back up (next to the file and in Setup's own folder), write, read it back; a result that is not exactly the intended one is rolled back
        static string Write(string path, Mapping mp, string newBody, ILog log)
        {
            string newText = mp.Text.Substring(0, mp.M.Groups[2].Index) + newBody + mp.Text.Substring(mp.M.Groups[2].Index + mp.M.Groups[2].Length);
            JavaScriptSerializer js = new JavaScriptSerializer(); js.MaxJsonLength = int.MaxValue;
            js.DeserializeObject(newText);   // must still be valid JSON
            string stamp = DateTime.Now.ToString("yyyyMMdd-HHmmss");
            string backup = Unique(path + ".bak-" + stamp);
            File.Copy(path, backup, false);
            SaveOwnCopy(path, stamp, log);
            string tmp = path + ".tmp-setup";
            File.WriteAllText(tmp, newText, new UTF8Encoding(mp.Bom));
            File.Copy(tmp, path, true);
            File.Delete(tmp);

            Mapping after = Read(path);
            bool good = after != null && after.Body == newBody
                && after.Text.Substring(0, after.M.Groups[2].Index) == mp.Text.Substring(0, mp.M.Groups[2].Index)
                && after.Text.Substring(after.M.Groups[2].Index + after.M.Groups[2].Length) == mp.Text.Substring(mp.M.Groups[2].Index + mp.M.Groups[2].Length);
            if (!good)
            {
                File.Copy(backup, path, true);
                throw new InvalidOperationException(Loc.T("The file did not come out as intended, so your original was put back. Nothing was changed.", "Het bestand kwam er niet uit zoals bedoeld, dus je origineel is teruggezet. Er is niets gewijzigd."));
            }
            return backup;
        }

        const string NoMappings = "  ERROR: no control_mappings in this file. Start ChasePlane once so it creates its key list, then run Setup again.";
        const string NoMappingsNl = "  FOUT: geen control_mappings in dit bestand. Start ChasePlane één keer zodat het zijn toetsenlijst aanmaakt en start Setup opnieuw.";

        const string NotReady = "  ERROR: none of ChasePlane's own default shortcuts is in this file, so ChasePlane has not saved its shortcut list yet. Nothing was changed (ChasePlane keeps its built-in shortcuts). Start ChasePlane once, close it again and run Setup again. If this stays, assign the deck keys by hand: see 'Key list...'.";
        const string NotReadyNl = "  FOUT: geen enkele standaard sneltoets van ChasePlane staat in dit bestand, dus ChasePlane heeft zijn sneltoetsenlijst nog niet bewaard. Er is niets gewijzigd (ChasePlane houdt zijn ingebouwde sneltoetsen). Start ChasePlane één keer, sluit het weer af en start Setup opnieuw. Blijft dit staan, wijs de deck-toetsen dan zelf toe: zie 'Toetsenlijst...'.";

        // ---- add the keys
        // quiet = only the summary line (used by the check)
        public static ApplyResult Apply(string path, List<KeyDef> keys, bool allKeys, bool dryRun, ILog log, bool quiet = false)
        {
            ApplyResult res = new ApplyResult();
            try
            {
                Mapping mp = Read(path);
                if (mp == null) { log.Line(Loc.T(NoMappings, NoMappingsNl)); res.Ok = false; return res; }
                Dictionary<string, List<string>> byCmd = mp.ByCmd;
                Dictionary<string, string> byCanon = mp.ByCanon;

                // if none of ChasePlane's own default shortcuts is in the file, ChasePlane has not saved its list yet; adding our few keys to an
                // empty list could make them the whole list (the user's default shortcuts gone), so do not write anything
                int defaultsTotal = 0, defaultsPresent = 0;
                foreach (KeyDef k in keys)
                {
                    if (k.IsNew || !(allKeys || k.InHybrid)) continue;
                    defaultsTotal++;
                    if (byCmd.ContainsKey(k.Command)) defaultsPresent++;
                }
                if (defaultsTotal > 0 && defaultsPresent == 0)
                {
                    log.Line(Loc.T(NotReady, NotReadyNl));
                    res.Ok = false;
                    return res;
                }

                StringBuilder add = new StringBuilder();
                foreach (KeyDef k in keys)
                {
                    if (!(allKeys || k.InHybrid)) continue;
                    string expected = EntryFor(k.Keys), canon = Canon(expected);
                    List<string> have;
                    byCmd.TryGetValue(k.Command, out have);
                    if (!k.IsNew)
                    {
                        // a ChasePlane default that the deck relies on: only check, never change
                        if (have == null)
                        {
                            log.Line(Loc.T("  note: {0} has no key in ChasePlane (deck key '{1}' will do nothing); default is {2}.", "  let op: {0} heeft geen toets in ChasePlane (deck-toets '{1}' doet niets); standaard is {2}.", k.Command, OneLine(k.Label), k.Keys));
                            res.Notes++;
                        }
                        else if (!have.Any(delegate(string r) { return Canon(r) == canon; }))
                        {
                            log.Line(Loc.T("  note: {0} uses a different key than the default {2} (deck key '{1}' will not work).", "  let op: {0} gebruikt een andere toets dan de standaard {2} (deck-toets '{1}' werkt niet).", k.Command, OneLine(k.Label), k.Keys));
                            res.Notes++;
                        }
                        continue;
                    }
                    if (have != null)
                    {
                        if (have.Any(delegate(string r) { return Canon(r) == canon; })) res.Present++;
                        else
                        {
                            log.Line(Loc.T("  skipped {0}: already has its own key in ChasePlane (left alone).", "  overgeslagen {0}: heeft al een eigen toets in ChasePlane (ongemoeid gelaten).", k.Command));
                            res.Skipped++;
                        }
                        continue;
                    }
                    string owner;
                    if (byCanon.TryGetValue(canon, out owner))
                    {
                        log.Line(Loc.T("  skipped {0}: {1} is already used by {2}.", "  overgeslagen {0}: {1} wordt al gebruikt door {2}.", k.Command, k.Keys, owner));
                        res.Skipped++;
                        continue;
                    }
                    add.Append(k.Command).Append(mp.Sep).Append(expected).Append("\\n");
                    byCanon[canon] = k.Command;
                    byCmd[k.Command] = new List<string> { expected };
                    res.Added++;
                    if (!quiet) log.Line("  + " + k.Command.PadRight(28) + k.Keys + "   (" + OneLine(k.Label) + ")");
                }

                log.Line(Loc.T("  {0} to add, {1} already there, {2} skipped, {3} notes.", "  {0} toe te voegen, {1} stonden er al, {2} overgeslagen, {3} opmerkingen.", res.Added, res.Present, res.Skipped, res.Notes));
                if (res.Added == 0) return res;
                if (dryRun) { if (!quiet) log.Line(Loc.T("  dry run: nothing written.", "  proefrun: er is niets geschreven.")); return res; }

                string newBody = mp.Body;
                if (newBody.Length > 0 && !newBody.EndsWith("\\n")) newBody += "\\n";
                newBody += add.ToString();
                string backup = Write(path, mp, newBody, log);
                res.Wrote = true;
                log.Line(Loc.T("  written. Backup: {0}", "  geschreven. Back-up: {0}", backup));
                return res;
            }
            catch (Exception ex)
            {
                log.Line(Loc.T("  ERROR: {0}", "  FOUT: {0}", ex.Message));
                res.Ok = false;
                return res;
            }
        }

        // ---- remove exactly the lines Setup adds (a command that has a different binding is left alone)
        public static ApplyResult RemoveKeys(string path, List<KeyDef> keys, bool dryRun, ILog log)
        {
            ApplyResult res = new ApplyResult();
            try
            {
                Mapping mp = Read(path);
                if (mp == null) { log.Line(Loc.T(NoMappings, NoMappingsNl)); res.Ok = false; return res; }
                Dictionary<string, string> ours = new Dictionary<string, string>();
                foreach (KeyDef k in keys) if (k.IsNew) ours[k.Command] = Canon(EntryFor(k.Keys));
                List<string> kept = new List<string>();
                foreach (string raw in mp.Body.Split(new[] { "\\n" }, StringSplitOptions.None))
                {
                    Match lm = LineRx.Match(raw);
                    string canon;
                    if (lm.Success && ours.TryGetValue(lm.Groups["cmd"].Value, out canon) && Canon(lm.Groups["rest"].Value) == canon)
                    {
                        res.Removed++;
                        log.Line("  - " + lm.Groups["cmd"].Value);
                        continue;
                    }
                    kept.Add(raw);
                }
                log.Line(Loc.T("  {0} keys to remove.", "  {0} toetsen te verwijderen.", res.Removed));
                if (res.Removed == 0) return res;
                if (dryRun) { log.Line(Loc.T("  dry run: nothing written.", "  proefrun: er is niets geschreven.")); return res; }
                string backup = Write(path, mp, string.Join("\\n", kept.ToArray()), log);
                res.Wrote = true;
                log.Line(Loc.T("  removed. Backup: {0}", "  verwijderd. Back-up: {0}", backup));
                return res;
            }
            catch (Exception ex)
            {
                log.Line(Loc.T("  ERROR: {0}", "  FOUT: {0}", ex.Message));
                res.Ok = false;
                return res;
            }
        }

        // ---- the saved copies of a settings file, and what ChasePlane lacks of them now
        static readonly Regex StampRx = new Regex(@"(\d{8})-(\d{6})(?:-\d+)?$");

        static DateTime BackupTime(string file)
        {
            Match m = StampRx.Match(System.IO.Path.GetFileName(file));
            DateTime t;
            if (m.Success && DateTime.TryParseExact(m.Groups[1].Value + m.Groups[2].Value, "yyyyMMddHHmmss", CultureInfo.InvariantCulture, DateTimeStyles.None, out t)) return t;
            return File.GetLastWriteTime(file);
        }

        static HashSet<string> OurLines(List<KeyDef> keys)
        {
            HashSet<string> s = new HashSet<string>();
            foreach (KeyDef k in keys) if (k.IsNew) s.Add(k.Command + "|" + Canon(EntryFor(k.Keys)));
            return s;
        }

        // the user's own bindings as "COMMAND|keys", Setup's deck keys left out
        static List<string> UserLines(Mapping mp, HashSet<string> ours)
        {
            List<string> r = new List<string>();
            foreach (KeyValuePair<string, List<string>> kv in mp.ByCmd)
                foreach (string rest in kv.Value)
                {
                    string id = kv.Key + "|" + Canon(rest);
                    if (!ours.Contains(id)) r.Add(id);
                }
            return r;
        }

        // newest first; the same copy stored next to the settings file and in Setup's own folder shows once
        public static List<BackupInfo> ListBackups(string path, List<KeyDef> keys)
        {
            HashSet<string> ours = OurLines(keys), have = new HashSet<string>();
            try { Mapping now = Read(path); if (now != null) foreach (string id in UserLines(now, ours)) have.Add(id); } catch (Exception) { }

            List<BackupInfo> list = new List<BackupInfo>();
            HashSet<string> seen = new HashSet<string>();
            string name = System.IO.Path.GetFileName(path);
            string[] dirs = new string[] { System.IO.Path.GetDirectoryName(path), OwnDir(path) };
            for (int d = 0; d < dirs.Length; d++)
            {
                if (dirs[d] == null || !Directory.Exists(dirs[d])) continue;
                foreach (string pattern in new string[] { name + ".bak-*", name + ".before-restore-*" })
                    foreach (FileInfo fi in new DirectoryInfo(dirs[d]).GetFiles(pattern))
                    {
                        DateTime t = BackupTime(fi.FullName);
                        Mapping mp;
                        try
                        {
                            string id;
                            using (SHA1 sha = SHA1.Create()) id = BitConverter.ToString(sha.ComputeHash(File.ReadAllBytes(fi.FullName)));
                            if (!seen.Add(t.ToString("s") + "|" + id)) continue;
                            mp = Read(fi.FullName);
                        }
                        catch (Exception) { continue; }
                        if (mp == null) continue;
                        List<string> mine = UserLines(mp, ours);
                        list.Add(new BackupInfo { Path = fi.FullName, Time = t, Own = d == 1, Shortcuts = mine.Count, Missing = mine.Count(delegate(string x) { return !have.Contains(x); }) });
                    }
            }
            return list.OrderByDescending(delegate(BackupInfo b) { return b.Time; }).ToList();
        }

        // the copy that has the most shortcuts ChasePlane lacks now (the newest one when equal); a copy made after the loss has none to give
        public static BackupInfo BestBackup(List<BackupInfo> list)
        {
            BackupInfo best = null;
            foreach (BackupInfo b in list) if (best == null || b.Missing > best.Missing) best = b;
            return best;
        }

        // put the shortcut list of a backup back into the current file; every other setting stays as it is now
        public static bool RestoreShortcuts(string path, string backup, ILog log)
        {
            try
            {
                Mapping cur = Read(path), old = Read(backup);
                if (cur == null || old == null) { log.Line(Loc.T(NoMappings, NoMappingsNl)); return false; }
                string saved = Write(path, cur, old.Body, log);
                log.Line(Loc.T("  your shortcuts are back (from {0}). The file as it was is kept as {1}.", "  je sneltoetsen zijn terug (uit {0}). Het bestand zoals het was blijft bewaard als {1}.", System.IO.Path.GetFileName(backup), System.IO.Path.GetFileName(saved)));
                return true;
            }
            catch (Exception ex)
            {
                log.Line(Loc.T("  ERROR: {0}", "  FOUT: {0}", ex.Message));
                return false;
            }
        }

        // ---- restore a backup
        public static string LatestBackup(string path)
        {
            string dir = System.IO.Path.GetDirectoryName(path), name = System.IO.Path.GetFileName(path);
            FileInfo[] f = new DirectoryInfo(dir).GetFiles(name + ".bak-*");
            if (f.Length == 0) return null;
            return f.OrderByDescending(delegate(FileInfo x) { return x.Name; }).First().FullName;
        }

        public static bool Restore(string path, string backup, ILog log)
        {
            try
            {
                string before = Unique(path + ".before-restore-" + DateTime.Now.ToString("yyyyMMdd-HHmmss"));
                File.Copy(path, before, false);
                File.Copy(backup, path, true);
                log.Line(Loc.T("  restored {0} (the file as it was before is kept as {1}).", "  teruggezet: {0} (het bestand van daarvoor blijft bewaard als {1}).", System.IO.Path.GetFileName(backup), System.IO.Path.GetFileName(before)));
                return true;
            }
            catch (Exception ex)
            {
                log.Line(Loc.T("  ERROR: {0}", "  FOUT: {0}", ex.Message));
                return false;
            }
        }
    }
}
