// The "Check & fix" diagnosis, shared by the window and by the /repair command line.
using System;
using System.Collections.Generic;

namespace ChasePlaneDeckSetup
{
    internal sealed class Diag
    {
        public bool StreamDeckFound, PluginInstalled, PluginOutdated, PluginNewer, BridgeUp;
        public Version Installed, Bundled;
        public List<string> Damaged = new List<string>();
        public int KeysMissing;
        public bool KeysUnusable;    // a settings file Setup cannot work with (no key list yet, unreadable)
        public int ShortcutsLost;    // the user's own shortcuts from a backup that ChasePlane does not have now (information only)
        public bool NeedsPlugin { get { return StreamDeckFound && (!PluginInstalled || PluginOutdated || Damaged.Count > 0); } }
        public bool NeedsKeys { get { return KeysMissing > 0; } }
        public bool AnyProblem { get { return !StreamDeckFound || NeedsPlugin || NeedsKeys || KeysUnusable; } }
    }

    internal static class Actions
    {
        const string Ok = "  ok  ";
        const string Bad = "  !!  ";

        public static Diag Diagnose(ILog log, List<string> targets, List<KeyDef> keys, bool allKeys)
        {
            Diag d = new Diag();

            // 1. Stream Deck app
            string exe = PluginTool.StreamDeckExe();
            d.StreamDeckFound = exe != null;
            if (exe == null)
                log.Line(Bad + Loc.T("Stream Deck app not found. Install it from https://www.elgato.com/downloads first.", "Stream Deck-app niet gevonden. Installeer die eerst via https://www.elgato.com/downloads."));
            else
                log.Line(Ok + Loc.T("Stream Deck app {0} ({1}).", "Stream Deck-app {0} ({1}).", PluginTool.StreamDeckVersion(exe),
                    PluginTool.StreamDeckRunning() ? Loc.T("running", "actief") : Loc.T("not running", "niet actief")));

            // 2. plugin: installed, version, files intact
            d.Bundled = PluginTool.BundledVersion();
            d.Installed = PluginTool.InstalledVersion();
            d.PluginInstalled = PluginTool.IsInstalled();
            if (!d.PluginInstalled)
                log.Line(Bad + Loc.T("The plugin is not installed.", "De plugin is niet geïnstalleerd."));
            else if (d.Installed != null && d.Bundled != null && d.Installed < d.Bundled)
            {
                d.PluginOutdated = true;
                log.Line(Bad + Loc.T("The plugin is out of date: installed {0}, this Setup has {1}.", "De plugin is verouderd: geïnstalleerd {0}, deze Setup heeft {1}.", d.Installed, d.Bundled));
            }
            else
            {
                if (d.Installed != null && d.Bundled != null && d.Installed > d.Bundled) { d.PluginNewer = true; log.Line(Ok + Loc.T("A newer plugin ({0}) than this Setup ({1}) is installed; leaving it.", "Er staat een nieuwere plugin ({0}) dan in deze Setup ({1}); die blijft staan.", d.Installed, d.Bundled)); }
                else
                {
                    d.Damaged = PluginTool.Damaged();
                    if (d.Damaged.Count == 0) log.Line(Ok + Loc.T("The plugin is installed ({0}) and its files are intact.", "De plugin is geïnstalleerd ({0}) en de bestanden zijn heel.", d.Installed));
                    else
                    {
                        log.Line(Bad + Loc.T("The plugin is damaged ({0} files differ or are missing):", "De plugin is beschadigd ({0} bestanden wijken af of ontbreken):", d.Damaged.Count));
                        for (int i = 0; i < d.Damaged.Count && i < 4; i++) log.Line("        " + d.Damaged[i]);
                    }
                }
            }

            // 3. ChasePlane keys
            if (targets.Count == 0)
                log.Line(Bad + Loc.T("No ChasePlane settings file found (start ChasePlane once, or choose the file).", "Geen ChasePlane-instellingenbestand gevonden (start ChasePlane één keer, of kies het bestand)."));
            foreach (string t in targets)
            {
                log.Line("  " + t);
                ApplyResult r = KeyTool.Apply(t, keys, allKeys, true, log, true);
                d.KeysMissing += r.Added;
                if (!r.Ok) { d.KeysUnusable = true; continue; }
                if (r.Added == 0) log.Line(Ok + Loc.T("All deck keys are set in ChasePlane.", "Alle deck-toetsen staan in ChasePlane."));
                else log.Line(Bad + Loc.T("{0} keys are missing in ChasePlane.", "{0} toetsen ontbreken in ChasePlane.", r.Added));

                // the user's own shortcuts: are they still what the backups say? (a deliberate change in ChasePlane shows up here too, so information only)
                List<BackupInfo> backups = KeyTool.ListBackups(t, keys);
                BackupInfo best = KeyTool.BestBackup(backups);
                if (backups.Count == 0)
                    log.Line("  --  " + Loc.T("No backup of this file yet (Setup makes one before it changes anything).", "Nog geen back-up van dit bestand (Setup maakt er een voordat het iets wijzigt)."));
                else if (best.Missing > 0)
                {
                    d.ShortcutsLost += best.Missing;
                    log.Line("  --  " + Loc.T("{0} of your shortcuts in the backup of {1} are not in ChasePlane now. If that is not on purpose, click 'Restore backup' and choose 'shortcuts only'.", "{0} van je sneltoetsen uit de back-up van {1} staan nu niet in ChasePlane. Is dat niet de bedoeling, klik dan op 'Herstel back-up' en kies 'alleen sneltoetsen'.", best.Missing, best.Time.ToString("g")));
                }
                else
                    log.Line(Ok + Loc.T("{0} backups kept; every shortcut in them is still in ChasePlane.", "{0} back-ups bewaard; elke sneltoets daarin staat nog in ChasePlane.", backups.Count));
            }

            // 4. ChasePlane Bridge (only reachable while MSFS + ChasePlane run)
            d.BridgeUp = PluginTool.BridgeReachable();
            log.Line((d.BridgeUp ? Ok : "  --  ") + (d.BridgeUp
                ? Loc.T("The ChasePlane Bridge answers (live view names will work).", "De ChasePlane Bridge reageert (live view-namen werken).")
                : Loc.T("The ChasePlane Bridge does not answer. That is normal while MSFS / ChasePlane are not running.", "De ChasePlane Bridge reageert niet. Dat is normaal zolang MSFS / ChasePlane niet draaien.")));

            // 5. what the plugin itself last complained about
            List<string> problems = PluginTool.RecentLogProblems(3);
            if (problems.Count > 0)
            {
                log.Line("  --  " + Loc.T("Last problems in the plugin log:", "Laatste problemen in het pluginlogboek:"));
                foreach (string p in problems) log.Line("        " + p);
            }
            return d;
        }
    }
}
