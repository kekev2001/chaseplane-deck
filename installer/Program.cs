// ChasePlane Deck Setup: one installer for the Stream Deck plugin + profiles and the ChasePlane key shortcuts.
// Command line (for testing and for automation):
//   /silent             run without a window (exit code 0 = ok)
//   /repair             (with /silent) check everything and fix what is wrong
//   /remove /yes        (with /silent) remove the keys Setup added and the plugin
//   /undo               (with /silent) restore the newest backup of user_settings.json
//   /restorekeys        (with /silent) put the user's shortcut list back from the backup that has the most shortcuts ChasePlane lacks now,
//                       then add the deck keys again; /backup:<file> chooses the backup
//   /checkupdate       (with /silent) print whether a newer version is announced
//   /noplugin /nokeys   skip the plugin step / the key step
//   /allkeys            also handle the keys that only the hotkeys-only profiles use
//   /settings:<file>    use this user_settings.json instead of looking for it
//   /dryrun             show what would change, write nothing
//   /ignoreprocesses    do not refuse to run while MSFS / ChasePlane is open
//   /nostreamdeck       do not close / restart the Stream Deck app while removing the plugin
//   /lang:nl|en         language (default: the Windows display language)
//   /log:<file>         also write the log to this file
//   /screenshot:<png>   render the window to a picture and exit (for checking the layout)
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Windows.Forms;

namespace ChasePlaneDeckSetup
{
    internal sealed class Options
    {
        public bool Silent, NoPlugin, NoKeys, NoProfiles, AllKeys, DryRun, IgnoreProcesses, Undo, RestoreKeys, Repair, Remove, Yes, NoStreamDeck, CheckUpdate;
        public string Settings, LogFile, Screenshot, Lang, ExportHk, Dialog, Backup;

        public static Options Parse(string[] args)
        {
            Options o = new Options();
            foreach (string a in args)
            {
                string l = a.ToLowerInvariant();
                if (l == "/silent") o.Silent = true;
                else if (l == "/noplugin") o.NoPlugin = true;
                else if (l == "/nokeys") o.NoKeys = true;
                else if (l == "/noprofiles") o.NoProfiles = true;
                else if (l.StartsWith("/exporthk:")) o.ExportHk = a.Substring(10).Trim('"');
                else if (l.StartsWith("/dialog:")) o.Dialog = a.Substring(8).Trim('"');
                else if (l == "/allkeys") o.AllKeys = true;
                else if (l == "/dryrun") o.DryRun = true;
                else if (l == "/ignoreprocesses") o.IgnoreProcesses = true;
                else if (l == "/undo") o.Undo = true;
                else if (l == "/restorekeys") o.RestoreKeys = true;
                else if (l.StartsWith("/backup:")) o.Backup = a.Substring(8).Trim('"');
                else if (l == "/repair") o.Repair = true;
                else if (l == "/remove") o.Remove = true;
                else if (l == "/yes") o.Yes = true;
                else if (l == "/nostreamdeck") o.NoStreamDeck = true;
                else if (l == "/checkupdate") o.CheckUpdate = true;
                else if (l.StartsWith("/lang:")) o.Lang = a.Substring(6).Trim('"');
                else if (l.StartsWith("/settings:")) o.Settings = a.Substring(10).Trim('"');
                else if (l.StartsWith("/log:")) o.LogFile = a.Substring(5).Trim('"');
                else if (l.StartsWith("/screenshot:")) o.Screenshot = a.Substring(12).Trim('"');
            }
            return o;
        }
    }

    internal sealed class FileLog : ILog
    {
        readonly string file;
        public FileLog(string file) { this.file = file; }
        public void Line(string text)
        {
            if (string.IsNullOrEmpty(file)) return;
            try { File.AppendAllText(file, text + Environment.NewLine, Encoding.UTF8); } catch (Exception) { }
        }
    }

    internal static class Program
    {
        [STAThread]
        static int Main(string[] args)
        {
            Options o = Options.Parse(args);
            Loc.Detect();
            if (o.Lang != null) Loc.Set(o.Lang);
            if (o.Silent) return RunSilent(o);
            Application.EnableVisualStyles();
            Ui.Init();
            Application.SetCompatibleTextRenderingDefault(false);
            MainForm f = new MainForm(o);
            if (o.Screenshot != null)
            {
                Form shown = f;
                if (o.Dialog == "help") shown = new HelpForm();
                else if (o.Dialog == "remove") shown = new RemoveForm(PluginTool.FindProfiles(), true);
                else if (o.Dialog == "hk") shown = new HotkeyForm();
                else if (o.Dialog == "backup")
                {
                    List<BackupInfo> sample = new List<BackupInfo>();
                    sample.Add(new BackupInfo { Path = "user_settings.json.bak-20261101-181500", Time = new DateTime(2026, 11, 1, 18, 15, 0), Shortcuts = 12, Missing = 0 });
                    sample.Add(new BackupInfo { Path = "user_settings.json.bak-20261101-174000", Time = new DateTime(2026, 11, 1, 17, 40, 0), Shortcuts = 34, Missing = 22 });
                    sample.Add(new BackupInfo { Path = "user_settings.json.bak-20261030-210500", Time = new DateTime(2026, 10, 30, 21, 5, 0), Shortcuts = 34, Missing = 22, Own = true });
                    shown = new BackupForm(sample);
                }
                shown.Show();
                Application.DoEvents();
                Ui.SaveScreenshot(shown, o.Screenshot);
                return 0;
            }
            Application.Run(f);
            return 0;
        }

        static int RunSilent(Options o)
        {
            FileLog log = new FileLog(o.LogFile);
            bool ok = true;
            List<KeyDef> keys = KeyTool.LoadKeys();
            List<string> files = new List<string>();
            if (!string.IsNullOrEmpty(o.Settings)) files.Add(o.Settings);
            else foreach (SettingsFile s in KeyTool.FindSettingsFiles()) files.Add(s.Path);

            if (o.ExportHk != null)
            {
                HotkeyProfiles.ExportAll(o.ExportHk);
                log.Line("exported " + HotkeyProfiles.List().Count + " profiles to " + o.ExportHk);
                return 0;
            }
            if (o.CheckUpdate)
            {
                UpdateInfo u = Updater.Check();
                log.Line(u == null ? "no update (" + Updater.LastStatus + ")" : "update " + u.Version + " " + u.Url + " | " + u.Notes);
                return 0;
            }
            if (o.Undo)
            {
                foreach (string f in files)
                {
                    string b = KeyTool.LatestBackup(f);
                    log.Line(f);
                    if (b == null) { log.Line(Loc.T("  no backup found.", "  geen back-up gevonden.")); continue; }
                    ok &= KeyTool.Restore(f, b, log);
                }
                return ok ? 0 : 1;
            }
            if (o.RestoreKeys)
            {
                if (!o.IgnoreProcesses && !o.DryRun && KeyTool.RunningSimProcesses().Count > 0) { log.Line(Loc.T("Close MSFS / ChasePlane first: ", "Sluit eerst MSFS / ChasePlane: ") + string.Join(", ", KeyTool.RunningSimProcesses().ToArray())); return 1; }
                foreach (string f in files)
                {
                    log.Line(f);
                    List<BackupInfo> list = KeyTool.ListBackups(f, keys);
                    BackupInfo pick = KeyTool.BestBackup(list);
                    if (!string.IsNullOrEmpty(o.Backup))
                    {
                        pick = list.Find(delegate(BackupInfo b) { return string.Equals(b.Path, o.Backup, StringComparison.OrdinalIgnoreCase) || string.Equals(Path.GetFileName(b.Path), o.Backup, StringComparison.OrdinalIgnoreCase); });
                        if (pick == null) { log.Line(Loc.T("  that backup was not found for this file.", "  die back-up is voor dit bestand niet gevonden.")); ok = false; continue; }
                    }
                    else if (pick == null || pick.Missing == 0) { log.Line(Loc.T("  nothing to restore: no backup has shortcuts that ChasePlane lacks now.", "  niets terug te zetten: geen enkele back-up heeft sneltoetsen die ChasePlane nu mist.")); continue; }
                    log.Line(Loc.T("  backup {0}: {1} shortcuts, {2} not in ChasePlane now.", "  back-up {0}: {1} sneltoetsen, {2} nu niet in ChasePlane.", Path.GetFileName(pick.Path), pick.Shortcuts, pick.Missing));
                    if (o.DryRun) { log.Line(Loc.T("  dry run: nothing written.", "  proefrun: er is niets geschreven.")); continue; }
                    if (KeyTool.RestoreShortcuts(f, pick.Path, log)) { if (!o.NoKeys) ok &= KeyTool.Apply(f, keys, o.AllKeys, false, log).Ok; }
                    else ok = false;
                }
                return ok ? 0 : 1;
            }
            if (o.Repair)
            {
                Diag d = Actions.Diagnose(log, files, keys, o.AllKeys);
                if (d.KeysUnusable) ok = false;
                if (o.DryRun) return d.AnyProblem ? 1 : 0;
                if (d.NeedsPlugin && !o.NoPlugin) { log.Line(Loc.T("Reinstalling the plugin (confirm in the Stream Deck app).", "De plugin wordt opnieuw geïnstalleerd (bevestig in de Stream Deck-app).")); PluginTool.Launch(PluginTool.Extract()); }
                if (d.NeedsKeys && !o.NoKeys)
                {
                    if (!o.IgnoreProcesses && KeyTool.RunningSimProcesses().Count > 0) { log.Line(Loc.T("Close MSFS / ChasePlane first: ", "Sluit eerst MSFS / ChasePlane: ") + string.Join(", ", KeyTool.RunningSimProcesses().ToArray())); return 1; }
                    foreach (string f in files) { log.Line(f); ok &= KeyTool.Apply(f, keys, o.AllKeys, false, log).Ok; }
                }
                return ok ? 0 : 1;
            }
            if (o.Remove)
            {
                if (!o.Yes) { log.Line("/remove needs /yes"); return 1; }
                if (!o.NoKeys)
                {
                    if (!o.IgnoreProcesses && !o.DryRun && KeyTool.RunningSimProcesses().Count > 0) { log.Line(Loc.T("Close MSFS / ChasePlane first: ", "Sluit eerst MSFS / ChasePlane: ") + string.Join(", ", KeyTool.RunningSimProcesses().ToArray())); return 1; }
                    foreach (string f in files) { log.Line(f); ok &= KeyTool.RemoveKeys(f, keys, o.DryRun, log).Ok; }
                }
                List<ProfileInfo> profs = o.NoProfiles ? new List<ProfileInfo>() : PluginTool.FindProfiles();
                foreach (ProfileInfo p in profs) log.Line("  profile: " + p.Title);
                if (!o.DryRun) ok &= PluginTool.Cleanup(log, !o.NoPlugin, profs, !o.NoStreamDeck, true);
                return ok ? 0 : 1;
            }

            // default: install
            if (!o.NoPlugin)
            {
                string exe = PluginTool.StreamDeckExe();
                if (exe == null) { log.Line(Loc.T("Stream Deck app not found.", "Stream Deck-app niet gevonden.")); ok = false; }
                else { log.Line(Loc.T("Starting plugin install in the Stream Deck app (confirm there).", "De plugininstallatie wordt gestart in de Stream Deck-app (bevestig daar).")); PluginTool.Launch(PluginTool.Extract()); }
            }
            if (!o.NoKeys)
            {
                if (files.Count == 0) { log.Line(Loc.T("No ChasePlane settings file found.", "Geen ChasePlane-instellingenbestand gevonden.")); ok = false; }
                if (!o.IgnoreProcesses && !o.DryRun)
                {
                    List<string> running = KeyTool.RunningSimProcesses();
                    if (running.Count > 0 && files.Count > 0) { log.Line(Loc.T("Close first: ", "Sluit eerst: ") + string.Join(", ", running.ToArray())); return 1; }
                }
                foreach (string f in files) { log.Line(f); ok &= KeyTool.Apply(f, keys, o.AllKeys, o.DryRun, log).Ok; }
            }
            return ok ? 0 : 1;
        }
    }
}
