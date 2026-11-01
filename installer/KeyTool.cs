// Adds / removes the keyboard shortcuts the ChasePlane Deck profiles need in ChasePlane's user_settings.json.
// Rules (same as build\Apply-ChasePlaneKeys.ps1): only commands without a binding are added, existing bindings are never changed,
// a key combination that another command already uses is skipped, a timestamped backup is written first, the JSON is validated.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Web.Script.Serialization;

namespace ChasePlaneDeckSetup
{
    internal interface ILog { void Line(string text); }

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

        // validate, back up, write
        static string Write(string path, Mapping mp, string newBody, ILog log)
        {
            string newText = mp.Text.Substring(0, mp.M.Groups[2].Index) + newBody + mp.Text.Substring(mp.M.Groups[2].Index + mp.M.Groups[2].Length);
            JavaScriptSerializer js = new JavaScriptSerializer(); js.MaxJsonLength = int.MaxValue;
            js.DeserializeObject(newText);   // must still be valid JSON
            string backup = Unique(path + ".bak-" + DateTime.Now.ToString("yyyyMMdd-HHmmss"));
            File.Copy(path, backup, false);
            string tmp = path + ".tmp-setup";
            File.WriteAllText(tmp, newText, new UTF8Encoding(mp.Bom));
            File.Copy(tmp, path, true);
            File.Delete(tmp);
            return backup;
        }

        const string NoMappings = "  ERROR: no control_mappings in this file. Start ChasePlane once so it creates its key list, then run Setup again.";
        const string NoMappingsNl = "  FOUT: geen control_mappings in dit bestand. Start ChasePlane één keer zodat het zijn toetsenlijst aanmaakt en start Setup opnieuw.";

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
