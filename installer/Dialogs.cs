using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

namespace ChasePlaneDeckSetup
{
    internal sealed class HelpForm : Form
    {
        public HelpForm()
        {
            Text = Loc.T("ChasePlane Deck Setup - help", "ChasePlane Deck Setup - hulp");
            AutoScaleMode = AutoScaleMode.None;
            ClientSize = new Size(Ui.S(660), Ui.S(560));
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false; MinimizeBox = false;
            StartPosition = FormStartPosition.CenterParent;
            Font = new Font("Segoe UI", 9F);
            TextBox t = new TextBox { Left = Ui.S(14), Top = Ui.S(14), Width = Ui.S(632), Height = Ui.S(490), Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical, BackColor = Color.White, Font = new Font("Segoe UI", 9.5F), Text = HelpText.Get().Replace("\r\n", "\n").Replace("\n", "\r\n") };
            t.Select(0, 0);
            Controls.Add(t);
            Button c = new Button { Text = Loc.T("Close", "Sluiten"), Left = Ui.S(546), Top = Ui.S(514), Width = Ui.S(100), Height = Ui.S(30), DialogResult = DialogResult.OK };
            Controls.Add(c);
            AcceptButton = c;
        }
    }

    // what to remove, and whether to install again afterwards (= clean reinstall)
    internal sealed class RemoveForm : Form
    {
        readonly CheckBox chkKeys, chkPlugin, chkProfiles, chkReinstall;
        readonly CheckedListBox lst;
        public bool RemoveKeys { get { return chkKeys.Checked; } }
        public bool RemovePlugin { get { return chkPlugin.Checked; } }
        public bool Reinstall { get { return chkReinstall.Checked; } }
        public List<ProfileInfo> SelectedProfiles { get; private set; }
        readonly List<ProfileInfo> profiles;

        public RemoveForm(List<ProfileInfo> profs, bool preview)
        {
            profiles = profs;
            SelectedProfiles = new List<ProfileInfo>();
            Text = Loc.T("Remove / clean reinstall", "Verwijderen / schoon opnieuw installeren");
            AutoScaleMode = AutoScaleMode.None;
            ClientSize = new Size(Ui.S(580), Ui.S(470));
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false; MinimizeBox = false;
            StartPosition = FormStartPosition.CenterParent;
            Font = new Font("Segoe UI", 9F);
            Controls.Add(Ui.Text(Loc.T("Choose what to remove. Nothing is removed until you click Continue.", "Kies wat er weg moet. Er wordt niets verwijderd voordat je op Doorgaan klikt."), 16, 14, 548, 22, Color.Black));
            chkKeys = Check(Loc.T("The keys Setup added to ChasePlane (only those exact shortcuts; a backup is made first)", "De toetsen die Setup aan ChasePlane heeft toegevoegd (alleen precies die sneltoetsen; eerst wordt een back-up gemaakt)"), 44, 44);
            chkPlugin = Check(Loc.T("The ChasePlane Deck plugin in the Stream Deck app", "De ChasePlane Deck-plugin in de Stream Deck-app"), 96, 24);
            chkProfiles = Check(profiles.Count > 0
                ? Loc.T("These ChasePlane profiles in the Stream Deck app (moved to a backup folder, not deleted):", "Deze ChasePlane-profielen in de Stream Deck-app (verplaatst naar een back-upmap, niet gewist):")
                : Loc.T("ChasePlane profiles in the Stream Deck app: none found", "ChasePlane-profielen in de Stream Deck-app: geen gevonden"), 130, 24);
            lst = new CheckedListBox { Left = Ui.S(40), Top = Ui.S(158), Width = Ui.S(520), Height = Ui.S(120), CheckOnClick = true };
            foreach (ProfileInfo p in profiles) lst.Items.Add(p.Title, true);
            Controls.Add(lst);
            if (profiles.Count == 0) { chkProfiles.Checked = false; chkProfiles.Enabled = false; lst.Enabled = false; }
            chkProfiles.CheckedChanged += delegate { lst.Enabled = chkProfiles.Checked; };
            Controls.Add(Ui.Text(Loc.T("The Stream Deck app is closed and started again for this.", "Daarvoor wordt de Stream Deck-app afgesloten en weer gestart."), 40, 284, 520, 22, ColorTranslator.FromHtml("#6A7280")));
            chkReinstall = Check(Loc.T("Install again afterwards (clean reinstall)", "Daarna opnieuw installeren (schone herinstallatie)"), 318, 24);
            chkReinstall.Checked = false; chkReinstall.Font = new Font("Segoe UI", 9F, FontStyle.Bold);
            Controls.Add(Ui.Text(Loc.T("Close MSFS and ChasePlane first if you remove or reinstall the keys.", "Sluit MSFS en ChasePlane eerst als je de toetsen verwijdert of opnieuw installeert."), 40, 346, 520, 22, ColorTranslator.FromHtml("#6A7280")));
            Button ok = new Button { Text = Loc.T("Continue", "Doorgaan"), Left = Ui.S(350), Top = Ui.S(416), Width = Ui.S(100), Height = Ui.S(32), DialogResult = DialogResult.OK };
            ok.Click += delegate
            {
                SelectedProfiles = new List<ProfileInfo>();
                if (chkProfiles.Checked) for (int i = 0; i < lst.Items.Count; i++) if (lst.GetItemChecked(i)) SelectedProfiles.Add(profiles[i]);
            };
            Button cancel = new Button { Text = Loc.T("Cancel", "Annuleren"), Left = Ui.S(460), Top = Ui.S(416), Width = Ui.S(100), Height = Ui.S(32), DialogResult = DialogResult.Cancel };
            Controls.Add(ok); Controls.Add(cancel);
            AcceptButton = ok; CancelButton = cancel;
        }

        CheckBox Check(string text, int top, int height)
        {
            CheckBox c = new CheckBox { Text = text, Left = Ui.S(16), Top = Ui.S(top), Width = Ui.S(548), Height = Ui.S(height), Checked = true };
            Controls.Add(c);
            return c;
        }
    }

    // pick the Stream Deck model whose hotkeys-only profile should be imported
    internal sealed class HotkeyForm : Form
    {
        readonly ComboBox cmb;
        readonly List<HkProfile> list = HotkeyProfiles.List();
        public HkProfile Chosen { get; private set; }

        public HotkeyForm()
        {
            Text = Loc.T("Hotkeys-only profile", "Hotkeys-only profiel");
            AutoScaleMode = AutoScaleMode.None;
            ClientSize = new Size(Ui.S(520), Ui.S(260));
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false; MinimizeBox = false;
            StartPosition = FormStartPosition.CenterParent;
            Font = new Font("Segoe UI", 9F);
            Controls.Add(Ui.Text(Loc.T("This profile needs no plugin: every key sends a keyboard shortcut to ChasePlane (so there are no live view names). The Stream Deck app asks you to confirm the import.", "Dit profiel heeft geen plugin nodig: elke toets stuurt een sneltoets naar ChasePlane (dus geen live view-namen). De Stream Deck-app vraagt je de import te bevestigen."), 16, 14, 488, 62, Color.Black));
            Controls.Add(Ui.Text(Loc.T("Which Stream Deck do you have?", "Welke Stream Deck heb je?"), 16, 84, 488, 20, Color.Black));
            cmb = new ComboBox { Left = Ui.S(16), Top = Ui.S(108), Width = Ui.S(488), DropDownStyle = ComboBoxStyle.DropDownList };
            foreach (HkProfile p in list) cmb.Items.Add(p.Title);
            if (cmb.Items.Count > 0) cmb.SelectedIndex = list.FindIndex(delegate(HkProfile p) { return p.File == "XL"; }) >= 0 ? list.FindIndex(delegate(HkProfile p) { return p.File == "XL"; }) : 0;
            Controls.Add(cmb);
            Controls.Add(Ui.Text(Loc.T("Tip: tick 'Also handle the keys that only the hotkeys-only profiles use' in the main window and click 'Keys only', so ChasePlane has every shortcut.", "Tip: vink in het hoofdvenster 'Neem ook de toetsen mee die alleen de hotkeys-only-profielen gebruiken' aan en klik op 'Alleen toetsen', zodat ChasePlane alle sneltoetsen heeft."), 16, 150, 488, 44, ColorTranslator.FromHtml("#6A7280")));
            Button ok = new Button { Text = Loc.T("Import", "Importeren"), Left = Ui.S(300), Top = Ui.S(210), Width = Ui.S(100), Height = Ui.S(32), DialogResult = DialogResult.OK };
            ok.Click += delegate { Chosen = cmb.SelectedIndex >= 0 ? list[cmb.SelectedIndex] : null; };
            Button cancel = new Button { Text = Loc.T("Cancel", "Annuleren"), Left = Ui.S(410), Top = Ui.S(210), Width = Ui.S(100), Height = Ui.S(32), DialogResult = DialogResult.Cancel };
            Controls.Add(ok); Controls.Add(cancel);
            AcceptButton = ok; CancelButton = cancel;
        }
    }
}
