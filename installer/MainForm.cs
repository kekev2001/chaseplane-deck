using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;
using System.Windows.Forms;

namespace ChasePlaneDeckSetup
{
    // Layout is written in 96-dpi units and multiplied by the real screen scale (the manifest makes the process DPI aware; fonts scale themselves).
    internal static class Ui
    {
        public static float Scale = 1f;
        public static void Init()
        {
            try { using (Graphics g = Graphics.FromHwnd(IntPtr.Zero)) Scale = g.DpiX / 96f; } catch (Exception) { Scale = 1f; }
            if (Scale < 1f) Scale = 1f;
        }
        public static int S(int v) { return (int)Math.Round(v * Scale); }
        public static Label Text(string text, int x, int y, int w, int h, Color color)
        {
            return new Label { Text = text, AutoSize = false, Left = S(x), Top = S(y), Width = S(w), Height = S(h), ForeColor = color };
        }
        public static void SaveScreenshot(Form f, string path)
        {
            f.Refresh();
            using (Bitmap bmp = new Bitmap(f.Width, f.Height))
            {
                f.DrawToBitmap(bmp, new Rectangle(0, 0, f.Width, f.Height));
                bmp.Save(path, ImageFormat.Png);
            }
        }
    }

    internal sealed class MainForm : Form, ILog
    {
        readonly Options opt;
        readonly List<KeyDef> keys = KeyTool.LoadKeys();
        readonly FileLog fileLog;
        List<SettingsFile> found = new List<SettingsFile>();
        string chosenFile;
        UpdateInfo update;

        Label lblSub, lblIntro, lblFoot, lblDeck, lblCP, lblPlugin;
        LinkLabel lblUpdate;
        ComboBox cmbLang;
        Button btnHelp, btnInstall, btnFix, btnRemove, btnPlugin, btnKeys, btnUndo, btnList, btnChoose, btnHk, btnClose;
        CheckBox chkAll;
        TextBox txtLog;
        System.Windows.Forms.Timer poll;
        int pollTicks, extraKeys;
        bool pluginExisted;
        DateTime pluginStart;

        static readonly Color Accent = ColorTranslator.FromHtml("#2F7BEA");
        static readonly Color Green = ColorTranslator.FromHtml("#1B7F3B");
        static readonly Color Red = ColorTranslator.FromHtml("#B3261E");
        static readonly Color Amber = ColorTranslator.FromHtml("#9A5B00");

        public MainForm(Options o)
        {
            opt = o;
            fileLog = new FileLog(o.LogFile);
            Text = "ChasePlane Deck Setup";
            AutoScaleMode = AutoScaleMode.None;
            ClientSize = new Size(Ui.S(620), Ui.S(600));
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            Font = new Font("Segoe UI", 9F);
            BackColor = Color.White;
            try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch (Exception) { }
            Build();
            cmbLang.SelectedIndex = Loc.IsNl ? 1 : 0;
            ApplyLanguage();
            cmbLang.SelectedIndexChanged += delegate { Loc.Set(cmbLang.SelectedIndex == 1 ? "nl" : "en"); ApplyLanguage(); };
            Log(Loc.T("Ready. Close MSFS and ChasePlane before you click Install, so the keys can be added.", "Klaar. Sluit MSFS en ChasePlane voordat je op Installeren klikt, zodat de toetsen kunnen worden toegevoegd."));
            if (o.Screenshot != null)
            {
                Log("");
                Log(Loc.T("Example log:", "Voorbeeld van het logboek:"));
                Log("  + CAM_QUICK_VIEW_BEHIND       Ctrl+Alt+F16   (PEEK BACK)");
                Log("  + CAM_RESET_ZOOM              Ctrl+Alt+7     (RESET ZOOM)");
                Log(Loc.T("  21 to add, 0 already there, 0 skipped, 0 notes.", "  21 toe te voegen, 0 stonden er al, 0 overgeslagen, 0 opmerkingen."));
                if (Environment.GetEnvironmentVariable("CPDECK_DEMO_UPDATE") == "1") { update = new UpdateInfo { Version = new Version(1, 1, 0, 0), Url = "https://example.com/", Notes = "demo" }; ShowUpdate(update); }
            }
            else Shown += delegate { StartUpdateCheck(); };
        }

        // ---- layout
        void Build()
        {
            Panel header = new Panel { Left = 0, Top = 0, Width = Ui.S(620), Height = Ui.S(84), BackColor = ColorTranslator.FromHtml("#14171C") };
            Label title = Ui.Text("ChasePlane Deck", 20, 8, 360, 40, Color.White);
            title.Font = new Font("Segoe UI", 20F, FontStyle.Bold);
            header.Controls.Add(title);
            lblSub = Ui.Text("", 22, 52, 580, 22, ColorTranslator.FromHtml("#AAB2C0"));
            header.Controls.Add(lblSub);
            btnHelp = new Button { Left = Ui.S(388), Top = Ui.S(13), Width = Ui.S(84), Height = Ui.S(26), FlatStyle = FlatStyle.Flat, ForeColor = Color.White, BackColor = ColorTranslator.FromHtml("#2A303B") };
            btnHelp.FlatAppearance.BorderColor = ColorTranslator.FromHtml("#4A5262");
            btnHelp.Click += delegate { using (HelpForm h = new HelpForm()) h.ShowDialog(this); };
            header.Controls.Add(btnHelp);
            cmbLang = new ComboBox { Left = Ui.S(482), Top = Ui.S(14), Width = Ui.S(118), DropDownStyle = ComboBoxStyle.DropDownList };
            cmbLang.Items.Add("English"); cmbLang.Items.Add("Nederlands");
            header.Controls.Add(cmbLang);
            Controls.Add(header);

            lblIntro = Ui.Text("", 20, 96, 580, 44, ColorTranslator.FromHtml("#333B47"));
            Controls.Add(lblIntro);
            lblDeck = Ui.Text("", 20, 144, 580, 20, Color.Black);
            lblCP = Ui.Text("", 20, 166, 580, 20, Color.Black);
            lblPlugin = Ui.Text("", 20, 188, 580, 20, Color.Black);
            lblUpdate = new LinkLabel { AutoSize = false, Left = Ui.S(20), Top = Ui.S(210), Width = Ui.S(580), Height = Ui.S(20), Visible = false, LinkColor = Accent };
            lblUpdate.LinkClicked += delegate { OpenUpdate(); };
            Controls.Add(lblDeck); Controls.Add(lblCP); Controls.Add(lblPlugin); Controls.Add(lblUpdate);

            btnInstall = new Button { Left = Ui.S(20), Top = Ui.S(238), Width = Ui.S(280), Height = Ui.S(46), FlatStyle = FlatStyle.Flat, BackColor = Accent, ForeColor = Color.White, Font = new Font("Segoe UI", 12F, FontStyle.Bold) };
            btnInstall.FlatAppearance.BorderSize = 0;
            btnInstall.Click += delegate { RunInstall(); };
            btnFix = new Button { Left = Ui.S(310), Top = Ui.S(238), Width = Ui.S(135), Height = Ui.S(46), Font = new Font("Segoe UI", 10F) };
            btnFix.Click += delegate { Log(""); Log(Loc.T("== Check & fix ==", "== Controleren & herstellen ==")); DoFix(); };
            btnRemove = new Button { Left = Ui.S(455), Top = Ui.S(238), Width = Ui.S(145), Height = Ui.S(46), Font = new Font("Segoe UI", 10F), ForeColor = Red };
            btnRemove.Click += delegate { DoRemove(); };
            Controls.Add(btnInstall); Controls.Add(btnFix); Controls.Add(btnRemove);

            btnPlugin = Small(20, 294); btnPlugin.Click += delegate { Log(""); Log("== Plugin =="); DoPlugin(); };
            btnKeys = Small(137, 294); btnKeys.Click += delegate { Log(""); Log(Loc.T("== ChasePlane keys ==", "== ChasePlane-toetsen ==")); DoKeys(); };
            btnUndo = Small(254, 294); btnUndo.Click += delegate { Log(""); Log(Loc.T("== Restore backup ==", "== Back-up terugzetten ==")); DoUndo(); };
            btnList = Small(371, 294); btnList.Click += delegate { using (KeyListForm k = new KeyListForm(keys)) k.ShowDialog(this); };
            btnChoose = Small(488, 294); btnChoose.Click += delegate { ChooseFile(); };
            btnHk = Small(20, 330); btnHk.Width = Ui.S(230); btnHk.Click += delegate { DoHotkeyProfile(); };

            extraKeys = keys.Count(delegate(KeyDef k) { return k.IsNew && !k.InHybrid; });
            chkAll = new CheckBox { Left = Ui.S(20), Top = Ui.S(368), Width = Ui.S(580), Height = Ui.S(24) };
            Controls.Add(chkAll);

            txtLog = new TextBox { Left = Ui.S(20), Top = Ui.S(398), Width = Ui.S(580), Height = Ui.S(142), Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical, Font = new Font("Consolas", 9F), BackColor = ColorTranslator.FromHtml("#F4F5F7"), WordWrap = true };
            Controls.Add(txtLog);

            lblFoot = Ui.Text("", 20, 554, 460, 34, ColorTranslator.FromHtml("#6A7280"));
            Controls.Add(lblFoot);
            btnClose = new Button { Left = Ui.S(500), Top = Ui.S(556), Width = Ui.S(100), Height = Ui.S(30) };
            btnClose.Click += delegate { Close(); };
            Controls.Add(btnClose);
        }

        Button Small(int left, int top)
        {
            Button b = new Button { Left = Ui.S(left), Top = Ui.S(top), Width = Ui.S(112), Height = Ui.S(30), Font = new Font("Segoe UI", 8.5F) };
            Controls.Add(b);
            return b;
        }

        void ApplyLanguage()
        {
            lblSub.Text = Loc.T("Stream Deck profiles for ChasePlane  -  Mini, 15-key, Neo, +, XL, + XL, Studio", "Stream Deck-profielen voor ChasePlane  -  Mini, 15 toetsen, Neo, +, XL, + XL, Studio");
            lblIntro.Text = Loc.T("Installs the ChasePlane Deck plugin with a profile for every Stream Deck model, and adds the few keyboard shortcuts some deck keys need in ChasePlane (with a backup).",
                                  "Installeert de ChasePlane Deck-plugin met een profiel voor elk Stream Deck-model en voegt de paar sneltoetsen toe die sommige toetsen in ChasePlane nodig hebben (met back-up).");
            btnHelp.Text = Loc.T("Help", "Hulp");
            btnInstall.Text = Loc.T("Install / update", "Installeren / bijwerken");
            btnFix.Text = Loc.T("Check && fix", "Check && herstel");
            btnRemove.Text = Loc.T("Remove...", "Verwijderen...");
            btnPlugin.Text = Loc.T("Plugin only", "Alleen plugin");
            btnKeys.Text = Loc.T("Keys only", "Alleen toetsen");
            btnUndo.Text = Loc.T("Restore backup...", "Herstel back-up...");
            btnList.Text = Loc.T("Key list...", "Toetsenlijst...");
            btnChoose.Text = Loc.T("Choose file...", "Kies bestand...");
            btnHk.Text = Loc.T("Hotkeys-only profile (no plugin)...", "Hotkeys-only profiel (zonder plugin)...");
            btnClose.Text = Loc.T("Close", "Sluiten");
            chkAll.Text = Loc.T("Also handle the keys that only the hotkeys-only profiles use ({0} more)", "Neem ook de toetsen mee die alleen de hotkeys-only-profielen gebruiken ({0} extra)", extraKeys);
            lblFoot.Text = Loc.T("Free and independent. Not affiliated with Parallel 42, Elgato or Microsoft.", "Gratis en onafhankelijk. Niet verbonden aan Parallel 42, Elgato of Microsoft.");
            RefreshStatus();
            if (update != null) ShowUpdate(update);
        }

        // ---- status
        void RefreshStatus()
        {
            string exe = PluginTool.StreamDeckExe();
            if (exe == null)
            {
                lblDeck.Text = Loc.T("Stream Deck app:   not found. Install it from elgato.com first, then run this again.", "Stream Deck-app:   niet gevonden. Installeer die eerst via elgato.com en start dit opnieuw.");
                lblDeck.ForeColor = Red;
            }
            else
            {
                lblDeck.Text = Loc.T("Stream Deck app:   found (version {0}).", "Stream Deck-app:   gevonden (versie {0}).", PluginTool.StreamDeckVersion(exe));
                lblDeck.ForeColor = Green;
            }

            found = KeyTool.FindSettingsFiles();
            if (!string.IsNullOrEmpty(opt.Settings)) chosenFile = opt.Settings;
            if (chosenFile != null) { lblCP.Text = Loc.T("ChasePlane settings:   {0}", "ChasePlane-instellingen:   {0}", chosenFile); lblCP.ForeColor = Green; }
            else if (found.Count > 0)
            {
                lblCP.Text = Loc.T("ChasePlane settings:   found for {0}.", "ChasePlane-instellingen:   gevonden voor {0}.", string.Join(", ", found.Select(delegate(SettingsFile s) { return s.Label; }).ToArray()));
                lblCP.ForeColor = Green;
            }
            else
            {
                lblCP.Text = Loc.T("ChasePlane settings:   not found yet. Start ChasePlane once, or use 'Choose file...'.", "ChasePlane-instellingen:   nog niet gevonden. Start ChasePlane één keer, of gebruik 'Kies bestand...'.");
                lblCP.ForeColor = Red;
            }

            Version bundled = PluginTool.BundledVersion(), inst = PluginTool.InstalledVersion();
            if (inst == null) { lblPlugin.Text = Loc.T("Plugin:   not installed yet (this Setup has version {0}).", "Plugin:   nog niet geïnstalleerd (deze Setup heeft versie {0}).", bundled); lblPlugin.ForeColor = Amber; }
            else if (bundled != null && inst < bundled) { lblPlugin.Text = Loc.T("Plugin:   version {0} installed; this Setup has {1}. Click Install / update.", "Plugin:   versie {0} geïnstalleerd; deze Setup heeft {1}. Klik op Installeren / bijwerken.", inst, bundled); lblPlugin.ForeColor = Amber; }
            else if (bundled != null && inst > bundled) { lblPlugin.Text = Loc.T("Plugin:   version {0} installed (newer than this Setup, {1}).", "Plugin:   versie {0} geïnstalleerd (nieuwer dan deze Setup, {1}).", inst, bundled); lblPlugin.ForeColor = Green; }
            else { lblPlugin.Text = Loc.T("Plugin:   version {0} installed (up to date).", "Plugin:   versie {0} geïnstalleerd (up-to-date).", inst); lblPlugin.ForeColor = Green; }
        }

        List<string> Targets()
        {
            if (chosenFile != null) return new List<string> { chosenFile };
            return found.Select(delegate(SettingsFile s) { return s.Path; }).ToList();
        }

        void ChooseFile()
        {
            using (OpenFileDialog d = new OpenFileDialog())
            {
                d.Title = Loc.T("Choose ChasePlane's user_settings.json", "Kies user_settings.json van ChasePlane");
                d.Filter = "user_settings.json|user_settings.json|JSON|*.json";
                if (d.ShowDialog(this) == DialogResult.OK) { chosenFile = d.FileName; RefreshStatus(); }
            }
        }

        // ---- update check (only when an address is built in; see Updater.cs)
        void StartUpdateCheck()
        {
            if (Updater.ConfiguredUrl() == null) return;
            ThreadPool.QueueUserWorkItem(delegate
            {
                UpdateInfo u = Updater.Check();
                if (u == null) return;
                try { BeginInvoke((MethodInvoker)delegate { update = u; ShowUpdate(u); }); } catch (Exception) { }
            });
        }

        void ShowUpdate(UpdateInfo u)
        {
            string text = Loc.T("Update available: version {0} (you have {1}). Click here to open the download page.", "Update beschikbaar: versie {0} (jij hebt {1}). Klik hier om de downloadpagina te openen.", u.Version, Updater.Current);
            lblUpdate.Text = text;
            lblUpdate.Links.Clear();
            lblUpdate.Links.Add(0, text.Length);
            lblUpdate.Tag = u;
            lblUpdate.Visible = true;
        }

        void OpenUpdate()
        {
            UpdateInfo u = lblUpdate.Tag as UpdateInfo;
            if (u == null || !Updater.IsSafeDownload(u.Url)) return;
            try { Process.Start(u.Url); } catch (Exception ex) { Log(ex.Message); }
        }

        // ---- logging
        public void Line(string text) { Log(text); }
        void Log(string text)
        {
            txtLog.AppendText(text + Environment.NewLine);
            fileLog.Line(text);
        }

        // ---- steps
        void RunInstall()
        {
            Log(""); Log(Loc.T("== Install ==", "== Installeren =="));
            btnInstall.Enabled = false;
            try
            {
                bool pluginOk = DoPlugin();
                Log("");
                Log(Loc.T("== ChasePlane keys ==", "== ChasePlane-toetsen =="));
                bool keysOk = DoKeysAsk();
                Log("");
                if (pluginOk && keysOk) Log(Loc.T("All done. Open the Stream Deck app and pick the ChasePlane profile for your deck.", "Klaar. Open de Stream Deck-app en kies het ChasePlane-profiel voor je deck."));
                else Log(Loc.T("Finished with notes above. You can run any step again.", "Klaar, met opmerkingen hierboven. Je kunt elke stap opnieuw uitvoeren."));
            }
            finally { btnInstall.Enabled = true; }
        }

        bool DoPlugin()
        {
            string exe = PluginTool.StreamDeckExe();
            if (exe == null)
            {
                Log(Loc.T("  The Stream Deck app was not found. Install it from https://www.elgato.com/downloads and run Setup again.", "  De Stream Deck-app is niet gevonden. Installeer die via https://www.elgato.com/downloads en start Setup opnieuw."));
                return false;
            }
            try
            {
                pluginExisted = PluginTool.IsInstalled();
                pluginStart = DateTime.UtcNow;
                string file = PluginTool.Extract();
                PluginTool.Launch(file);
                Log(Loc.T("  Sent the plugin to the Stream Deck app. Click the install button in the window it shows.", "  Plugin naar de Stream Deck-app gestuurd. Klik op de installatieknop in het venster dat die toont."));
                StartPoll();
                return true;
            }
            catch (Exception ex)
            {
                Log(Loc.T("  ERROR: {0}", "  FOUT: {0}", ex.Message));
                return false;
            }
        }

        void StartPoll()
        {
            if (poll != null) poll.Stop();
            pollTicks = 0;
            poll = new System.Windows.Forms.Timer { Interval = 1500 };
            poll.Tick += delegate
            {
                pollTicks++;
                string m = PluginTool.InstalledManifest();
                if (File.Exists(m) && File.GetLastWriteTimeUtc(m) >= pluginStart.AddSeconds(-10))
                {
                    poll.Stop();
                    RefreshStatus();
                    Log(pluginExisted
                        ? Loc.T("  Plugin updated. In the Stream Deck app, choose the ChasePlane profile for your deck.", "  Plugin bijgewerkt. Kies in de Stream Deck-app het ChasePlane-profiel voor je deck.")
                        : Loc.T("  Plugin installed. In the Stream Deck app, choose the ChasePlane profile for your deck (it was added to the profile list).", "  Plugin geïnstalleerd. Kies in de Stream Deck-app het ChasePlane-profiel voor je deck (het staat nu in de profielenlijst)."));
                }
                else if (pollTicks > 120)
                {
                    poll.Stop();
                    Log(Loc.T("  Still waiting for the Stream Deck app. If it showed no install window, double-click this file yourself: {0}", "  Nog steeds wachten op de Stream Deck-app. Toonde die geen installatievenster, dubbelklik dan zelf op dit bestand: {0}", Path.Combine(Path.GetTempPath(), @"ChasePlaneDeckSetup\ChasePlane Deck.streamDeckPlugin")));
                }
            };
            poll.Start();
        }

        bool WaitForSimClosed()
        {
            while (true)
            {
                List<string> running = KeyTool.RunningSimProcesses();
                if (running.Count == 0 || opt.IgnoreProcesses) return true;
                DialogResult r = MessageBox.Show(this,
                    Loc.T("Please close MSFS and ChasePlane first (running: {0}). ChasePlane rewrites its settings file while it runs.\n\nClose it, then click the retry button.", "Sluit eerst MSFS en ChasePlane (actief: {0}). ChasePlane herschrijft zijn instellingenbestand zolang het draait.\n\nSluit het af en klik daarna op de knop om opnieuw te proberen.", string.Join(", ", running.ToArray())),
                    "ChasePlane Deck Setup", MessageBoxButtons.RetryCancel, MessageBoxIcon.Information);
                if (r != DialogResult.Retry) return false;
            }
        }

        // used by Install: say how many shortcuts would be added and let the user keep ChasePlane's settings file completely untouched
        bool DoKeysAsk()
        {
            List<string> t = Targets();
            if (t.Count == 0 || opt.DryRun) return DoKeys();
            int toAdd = 0;
            foreach (string f in t)
            {
                ApplyResult r = KeyTool.Apply(f, keys, chkAll.Checked, true, new NullLog(), true);
                if (r.Ok) toAdd += r.Added;
            }
            if (toAdd == 0) return DoKeys();
            DialogResult a = MessageBox.Show(this,
                Loc.T("Setup can add {0} keyboard shortcuts (Ctrl+Alt + a key) to ChasePlane for the deck keys that need them.\n\nYour own shortcuts are not changed or removed, and a backup of the settings file is made first.\n\nYes = add them.\nNo = leave ChasePlane's settings completely alone (those deck keys then do nothing until you assign them yourself; see 'Key list...').",
                      "Setup kan {0} sneltoetsen (Ctrl+Alt + een toets) aan ChasePlane toevoegen voor de deck-toetsen die ze nodig hebben.\n\nJe eigen sneltoetsen worden niet gewijzigd of verwijderd, en eerst wordt een back-up van het instellingenbestand gemaakt.\n\nJa = toevoegen.\nNee = ChasePlane's instellingen helemaal met rust laten (die deck-toetsen doen dan niets totdat je ze zelf toewijst; zie 'Toetsenlijst...').", toAdd),
                "ChasePlane Deck Setup", MessageBoxButtons.YesNo, MessageBoxIcon.Question);
            if (a != DialogResult.Yes)
            {
                Log(Loc.T("  ChasePlane's settings were left untouched. Click 'Keys only' later to add the {0} shortcuts, or assign them by hand ('Key list...').", "  ChasePlane's instellingen zijn niet aangeraakt. Klik later op 'Alleen toetsen' om de {0} sneltoetsen toe te voegen, of wijs ze zelf toe ('Toetsenlijst...').", toAdd));
                return true;
            }
            return DoKeys();
        }

        bool DoKeys()
        {
            List<string> t = Targets();
            if (t.Count == 0)
            {
                Log(Loc.T("  No ChasePlane settings file found. Start ChasePlane once (it creates the file), then run Setup again, or use 'Choose file...'.", "  Geen ChasePlane-instellingenbestand gevonden. Start ChasePlane één keer (dan wordt het gemaakt) en start Setup opnieuw, of gebruik 'Kies bestand...'."));
                return false;
            }
            if (!WaitForSimClosed()) { Log(Loc.T("  Skipped: MSFS / ChasePlane was still running. Close it and click 'Keys only'.", "  Overgeslagen: MSFS / ChasePlane draaide nog. Sluit het af en klik op 'Alleen toetsen'.")); return false; }
            bool ok = true;
            foreach (string f in t)
            {
                Log("  " + f);
                ok &= KeyTool.Apply(f, keys, chkAll.Checked, opt.DryRun, this).Ok;
            }
            Log(Loc.T("  Note: with ChasePlane cloud sync on, ChasePlane may bring back its cloud copy of the settings. If the keys are gone after starting ChasePlane, use 'Key list...' and assign them in ChasePlane > Preferences > Control Assignments.",
                      "  Let op: met ChasePlane cloud sync aan kan ChasePlane zijn cloudkopie van de instellingen terugzetten. Zijn de toetsen weg na het starten van ChasePlane, gebruik dan 'Toetsenlijst...' en wijs ze toe in ChasePlane > Preferences > Control Assignments."));
            return ok;
        }

        void DoUndo()
        {
            List<string> t = Targets();
            if (t.Count == 0) { Log(Loc.T("  No ChasePlane settings file found.", "  Geen ChasePlane-instellingenbestand gevonden.")); return; }
            if (!WaitForSimClosed()) { Log(Loc.T("  Skipped: close MSFS / ChasePlane first.", "  Overgeslagen: sluit eerst MSFS / ChasePlane.")); return; }
            foreach (string f in t)
            {
                Log("  " + f);
                List<BackupInfo> list = KeyTool.ListBackups(f, keys);
                if (list.Count == 0) { Log(Loc.T("  no backup found.", "  geen back-up gevonden.")); continue; }
                using (BackupForm bf = new BackupForm(list))
                {
                    if (bf.ShowDialog(this) != DialogResult.OK || bf.Chosen == null) { Log(Loc.T("  cancelled.", "  geannuleerd.")); continue; }
                    if (bf.WholeFile) KeyTool.Restore(f, bf.Chosen.Path, this);
                    else if (KeyTool.RestoreShortcuts(f, bf.Chosen.Path, this))
                    {
                        Log(Loc.T("  Adding the deck keys again (your own shortcuts are not touched):", "  De deck-toetsen worden opnieuw toegevoegd (je eigen sneltoetsen blijven ongemoeid):"));
                        KeyTool.Apply(f, keys, chkAll.Checked, opt.DryRun, this);
                    }
                }
            }
        }

        // ---- check & fix
        void DoFix()
        {
            Diag d = Actions.Diagnose(this, Targets(), keys, chkAll.Checked);
            RefreshStatus();
            if (!d.AnyProblem) { Log(Loc.T("Everything looks fine.", "Alles ziet er goed uit.")); return; }
            List<string> todo = new List<string>();
            if (d.NeedsPlugin) todo.Add(Loc.T("- reinstall the Stream Deck plugin (you confirm in the Stream Deck app)", "- de Stream Deck-plugin opnieuw installeren (je bevestigt in de Stream Deck-app)"));
            if (d.NeedsKeys) todo.Add(Loc.T("- add the {0} missing keys to ChasePlane (a backup is made first)", "- de {0} ontbrekende toetsen aan ChasePlane toevoegen (eerst wordt een back-up gemaakt)", d.KeysMissing));
            if (todo.Count == 0) { Log(Loc.T("Nothing Setup can fix by itself; see the lines marked !! above.", "Hier kan Setup zelf niets aan doen; zie de regels met !! hierboven.")); return; }
            DialogResult r = MessageBox.Show(this, Loc.T("Fix this now?", "Dit nu herstellen?") + "\n\n" + string.Join("\n", todo.ToArray()), "ChasePlane Deck Setup", MessageBoxButtons.YesNo, MessageBoxIcon.Question);
            if (r != DialogResult.Yes) return;
            Log("");
            if (d.NeedsPlugin) DoPlugin();
            if (d.NeedsKeys) { Log(Loc.T("== ChasePlane keys ==", "== ChasePlane-toetsen ==")); DoKeys(); }
        }

        // ---- remove / clean reinstall
        void DoRemove()
        {
            List<ProfileInfo> profs = PluginTool.FindProfiles();
            bool removeKeys, removePlugin, reinstall;
            List<ProfileInfo> chosen;
            using (RemoveForm f = new RemoveForm(profs, false))
            {
                if (f.ShowDialog(this) != DialogResult.OK) return;
                removeKeys = f.RemoveKeys; removePlugin = f.RemovePlugin; reinstall = f.Reinstall; chosen = f.SelectedProfiles;
            }
            if (!removeKeys && !removePlugin && chosen.Count == 0 && !reinstall) return;
            Log(""); Log(Loc.T("== Remove ==", "== Verwijderen =="));
            if (removeKeys)
            {
                List<string> t = Targets();
                if (t.Count == 0) Log(Loc.T("  No ChasePlane settings file found; skipping the keys.", "  Geen ChasePlane-instellingenbestand gevonden; de toetsen worden overgeslagen."));
                else if (!WaitForSimClosed()) Log(Loc.T("  Skipped the keys: MSFS / ChasePlane was still running (use 'Remove...' again later).", "  Toetsen overgeslagen: MSFS / ChasePlane draaide nog (gebruik later opnieuw 'Verwijderen...')."));
                else foreach (string file in t) { Log("  " + file); KeyTool.RemoveKeys(file, keys, opt.DryRun, this); }
            }
            if (!opt.DryRun) PluginTool.Cleanup(this, removePlugin, chosen, !opt.NoStreamDeck, !reinstall);
            RefreshStatus();
            if (reinstall)
            {
                Log(""); Log(Loc.T("== Install again ==", "== Opnieuw installeren =="));
                DoPlugin();
                Log(Loc.T("== ChasePlane keys ==", "== ChasePlane-toetsen =="));
                DoKeysAsk();
                Log(Loc.T("Clean reinstall started. Confirm the install in the Stream Deck app, then choose the ChasePlane profile for your deck.", "Schone herinstallatie gestart. Bevestig de installatie in de Stream Deck-app en kies daarna het ChasePlane-profiel voor je deck."));
            }
            else if (chosen.Count == 0)
                Log(Loc.T("Done. Any ChasePlane profiles are still listed in the Stream Deck app; delete them there (right-click the profile > Delete) or run 'Remove...' again with the profiles ticked.", "Klaar. Eventuele ChasePlane-profielen staan nog in de Stream Deck-app; verwijder ze daar (rechtsklik op het profiel > Delete) of gebruik 'Verwijderen...' opnieuw met de profielen aangevinkt."));
            else Log(Loc.T("Done. Setup itself installed nothing else, so there is nothing more to uninstall.", "Klaar. Setup zelf heeft verder niets geïnstalleerd, dus er is niets meer te verwijderen."));
        }

        // ---- hotkeys-only profile (inside this exe)
        void DoHotkeyProfile()
        {
            if (PluginTool.StreamDeckExe() == null) { Log(Loc.T("The Stream Deck app was not found. Install it from https://www.elgato.com/downloads first.", "De Stream Deck-app is niet gevonden. Installeer die eerst via https://www.elgato.com/downloads.")); return; }
            HkProfile p;
            using (HotkeyForm f = new HotkeyForm())
            {
                if (f.ShowDialog(this) != DialogResult.OK || f.Chosen == null) return;
                p = f.Chosen;
            }
            try
            {
                string file = HotkeyProfiles.Extract(p, Path.Combine(Path.GetTempPath(), "ChasePlaneDeckSetup"));
                PluginTool.Launch(file);
                Log(""); Log(Loc.T("== Hotkeys-only profile ==", "== Hotkeys-only profiel =="));
                Log(Loc.T("  Sent the profile for {0} to the Stream Deck app. Confirm the import there.", "  Het profiel voor {0} naar de Stream Deck-app gestuurd. Bevestig daar de import.", p.Title));
                Log(Loc.T("  Tip: tick 'Also handle the keys that only the hotkeys-only profiles use' and click 'Keys only' so ChasePlane has every shortcut.", "  Tip: vink 'Neem ook de toetsen mee die alleen de hotkeys-only-profielen gebruiken' aan en klik op 'Alleen toetsen', zodat ChasePlane alle sneltoetsen heeft."));
            }
            catch (Exception ex) { Log(Loc.T("  ERROR: {0}", "  FOUT: {0}", ex.Message)); }
        }
    }

    internal sealed class KeyListForm : Form
    {
        public KeyListForm(List<KeyDef> keys)
        {
            Text = Loc.T("Keys the deck needs in ChasePlane", "Toetsen die de deck nodig heeft in ChasePlane");
            AutoScaleMode = AutoScaleMode.None;
            ClientSize = new Size(Ui.S(640), Ui.S(470));
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false; MinimizeBox = false;
            StartPosition = FormStartPosition.CenterParent;
            Font = new Font("Segoe UI", 9F);
            Controls.Add(Ui.Text(Loc.T("These commands have no key in ChasePlane by default. Setup adds them for you. To do it by hand: ChasePlane > Preferences > Control Assignments.", "Deze commando's hebben standaard geen toets in ChasePlane. Setup voegt ze voor je toe. Zelf doen kan via ChasePlane > Preferences > Control Assignments."), 14, 10, 612, 38, Color.Black));
            ListView lv = new ListView { Left = Ui.S(14), Top = Ui.S(52), Width = Ui.S(612), Height = Ui.S(360), View = View.Details, FullRowSelect = true, GridLines = true };
            lv.Columns.Add(Loc.T("Deck button", "Deck-toets"), Ui.S(170)); lv.Columns.Add(Loc.T("ChasePlane command", "ChasePlane-commando"), Ui.S(230)); lv.Columns.Add(Loc.T("Key", "Toets"), Ui.S(110)); lv.Columns.Add(Loc.T("Used by", "Gebruikt door"), Ui.S(90));
            StringBuilder copy = new StringBuilder();
            foreach (KeyDef k in keys.Where(delegate(KeyDef x) { return x.IsNew; }).OrderByDescending(delegate(KeyDef x) { return x.InHybrid; }).ThenBy(delegate(KeyDef x) { return x.Label; }))
            {
                string used = k.InHybrid ? Loc.T("all profiles", "alle profielen") : "hotkeys-only";
                lv.Items.Add(new ListViewItem(new[] { k.Label, k.Command, k.Keys, used }));
                copy.AppendLine(k.Command + "\t" + k.Keys + "\t" + k.Label);
            }
            Controls.Add(lv);
            string text = copy.ToString();
            Button b = new Button { Text = Loc.T("Copy list", "Lijst kopiëren"), Left = Ui.S(14), Top = Ui.S(424), Width = Ui.S(110), Height = Ui.S(30) };
            b.Click += delegate { try { Clipboard.SetText(text); } catch (Exception) { } };
            Controls.Add(b);
            Button c = new Button { Text = Loc.T("Close", "Sluiten"), Left = Ui.S(526), Top = Ui.S(424), Width = Ui.S(100), Height = Ui.S(30), DialogResult = DialogResult.OK };
            Controls.Add(c);
            AcceptButton = c;
        }
    }
}
