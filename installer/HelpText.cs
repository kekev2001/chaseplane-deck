// The built-in help: everything a person needs when they only got the exe.
using System;
using System.Text;

namespace ChasePlaneDeckSetup
{
    internal static class HelpText
    {
        static void Section(StringBuilder sb, string title, string body)
        {
            sb.AppendLine(title);
            sb.AppendLine(body);
            sb.AppendLine();
        }

        public static string Get()
        {
            StringBuilder sb = new StringBuilder();
            Section(sb, Loc.T("WHAT THIS DOES", "WAT DIT DOET"),
                Loc.T("Installs the ChasePlane Deck plugin in the Stream Deck app, with a ready-made profile for every Stream Deck model (Mini, 15-key / MK.2, Neo, +, XL, + XL, Studio), and adds the few keyboard shortcuts that some deck keys need in ChasePlane. Everything is inside this one file.",
                      "Installeert de ChasePlane Deck-plugin in de Stream Deck-app, met een kant-en-klaar profiel voor elk Stream Deck-model (Mini, 15 toetsen / MK.2, Neo, +, XL, + XL, Studio), en voegt de paar sneltoetsen toe die sommige deck-toetsen in ChasePlane nodig hebben. Alles zit in dit ene bestand."));
            Section(sb, Loc.T("INSTALL / UPDATE", "INSTALLEREN / BIJWERKEN"),
                Loc.T("1. Install the Stream Deck app (version 6.4 or newer) and connect your deck.\r\n2. Close MSFS and ChasePlane, then click 'Install / update'. Click the install button in the window the Stream Deck app shows.\r\n3. In the Stream Deck app choose the ChasePlane profile for your deck. Start MSFS and ChasePlane: the status key turns green.\r\nA newer Setup updates the plugin. Keys that are already set are not added twice.",
                      "1. Installeer de Stream Deck-app (versie 6.4 of nieuwer) en sluit je deck aan.\r\n2. Sluit MSFS en ChasePlane en klik op 'Installeren / bijwerken'. Klik op de installatieknop in het venster dat de Stream Deck-app toont.\r\n3. Kies in de Stream Deck-app het ChasePlane-profiel voor je deck. Start MSFS en ChasePlane: de status-toets wordt groen.\r\nEen nieuwere Setup werkt de plugin bij. Toetsen die al staan worden niet dubbel toegevoegd."));
            Section(sb, Loc.T("CHECK & FIX", "CHECK & HERSTEL"),
                Loc.T("Checks the Stream Deck app, the plugin and its files, the keys in ChasePlane, the ChasePlane Bridge and the plugin log. What Setup can fix itself (reinstall the plugin, add missing keys) it does after you confirm.",
                      "Controleert de Stream Deck-app, de plugin en zijn bestanden, de toetsen in ChasePlane, de ChasePlane Bridge en het pluginlogboek. Wat Setup zelf kan oplossen (plugin opnieuw installeren, ontbrekende toetsen toevoegen) doet het na jouw bevestiging."));
            Section(sb, Loc.T("REMOVE / CLEAN REINSTALL", "VERWIJDEREN / SCHOON OPNIEUW INSTALLEREN"),
                Loc.T("'Remove...' lets you choose what goes: the keys Setup added to ChasePlane (only those exact shortcuts, with a backup), the plugin, and the ChasePlane profiles in the Stream Deck app (moved to a backup folder next to ProfilesV3, not deleted). Tick 'Install again afterwards' for a clean reinstall. For this the Stream Deck app is closed and started again.",
                      "Met 'Verwijderen...' kies je wat er weggaat: de toetsen die Setup aan ChasePlane heeft toegevoegd (alleen precies die sneltoetsen, met een back-up), de plugin en de ChasePlane-profielen in de Stream Deck-app (verplaatst naar een back-upmap naast ProfilesV3, niet gewist). Vink 'Daarna opnieuw installeren' aan voor een schone herinstallatie. Daarvoor wordt de Stream Deck-app afgesloten en weer gestart."));
            Section(sb, Loc.T("HOTKEYS-ONLY PROFILES", "HOTKEYS-ONLY PROFIELEN"),
                Loc.T("Prefer no plugin? 'Hotkeys-only profile...' imports a profile in which every key sends a keyboard shortcut (no live view names). Tick 'Also handle the keys that only the hotkeys-only profiles use' and click 'Keys only', so ChasePlane has all the shortcuts.",
                      "Liever geen plugin? 'Hotkeys-only profiel...' importeert een profiel waarin elke toets een sneltoets stuurt (geen live view-namen). Vink 'Neem ook de toetsen mee die alleen de hotkeys-only-profielen gebruiken' aan en klik op 'Alleen toetsen', zodat ChasePlane alle sneltoetsen heeft."));
            Section(sb, Loc.T("THE KEYS IN CHASEPLANE", "DE TOETSEN IN CHASEPLANE"),
                Loc.T("Install asks you before it adds anything to ChasePlane: answer No (or use 'Plugin only') and ChasePlane's settings stay completely untouched. Setup adds Ctrl+Alt+<key> shortcuts for commands that have none. A command that already has a key is left alone; if the wanted combination is taken, Setup picks a free one. Your deck keys press the shortcut you have set in ChasePlane for each command, so changed shortcuts keep working; a key whose command has no shortcut flashes. The deck presses keys only while the flight simulator window is in front. 'Key list...' shows them all. If ChasePlane has not saved its own shortcut list yet, Setup changes nothing. Before every change Setup saves a copy of the settings file, next to the file and in %APPDATA%\\ChasePlane Deck\\Backups. If shortcuts of yours are gone, click 'Restore backup...', pick a copy and keep 'Only my shortcuts': they come back and nothing else changes. With ChasePlane cloud sync on, ChasePlane may bring back its cloud copy: then assign the keys by hand (ChasePlane > Preferences > Control Assignments). The hotkeys-only profiles send fixed shortcuts: if you changed ChasePlane's default shortcuts (move, look, zoom, peek, boost), Setup tells you which of those keys will not work.",
                      "Installeren vraagt je eerst of er iets aan ChasePlane mag worden toegevoegd: antwoord Nee (of gebruik 'Alleen plugin') en de instellingen van ChasePlane blijven helemaal ongemoeid. Setup voegt Ctrl+Alt+<toets>-sneltoetsen toe voor commando's die er geen hebben. Een commando dat al een toets heeft blijft ongemoeid; is de gewenste combinatie al bezet, dan kiest Setup een vrije. Je deck-toetsen drukken de sneltoets die je in ChasePlane voor elk commando hebt ingesteld, dus veranderde sneltoetsen blijven werken; een toets waarvan het commando geen sneltoets heeft knippert. De deck drukt alleen toetsen als het venster van de flight simulator vooraan staat. 'Toetsenlijst...' toont ze allemaal. Heeft ChasePlane zijn eigen sneltoetsenlijst nog niet bewaard, dan wijzigt Setup niets. Voor elke wijziging bewaart Setup een kopie van het instellingenbestand, naast het bestand en in %APPDATA%\\ChasePlane Deck\\Backups. Zijn sneltoetsen van jou weg, klik dan op 'Herstel back-up...', kies een kopie en laat 'Alleen mijn sneltoetsen' staan: ze komen terug en verder verandert er niets. Met ChasePlane cloud sync aan kan ChasePlane zijn cloudkopie terugzetten: wijs de toetsen dan met de hand toe (ChasePlane > Preferences > Control Assignments). De hotkeys-only-profielen sturen vaste sneltoetsen: heb je de standaardsneltoetsen van ChasePlane veranderd (bewegen, kijken, zoomen, peek, boost), dan meldt Setup welke van die toetsen niet werken."));
            Section(sb, Loc.T("PROBLEMS", "PROBLEMEN"),
                Loc.T("- Status key red / BRIDGE OFFLINE: start MSFS and ChasePlane; the plugin reconnects by itself.\r\n- Keys do nothing: use 'Check & fix'. If MSFS or ChasePlane runs as administrator, run the Stream Deck app as administrator too.\r\n- Plugin log: %APPDATA%\\Elgato\\StreamDeck\\Plugins\\com.chaseplanexl.deck.sdPlugin\\logs\\plugin.log",
                      "- Status-toets rood / BRIDGE OFFLINE: start MSFS en ChasePlane; de plugin verbindt zelf opnieuw.\r\n- Toetsen doen niets: gebruik 'Check & herstel'. Draait MSFS of ChasePlane als administrator, start dan ook de Stream Deck-app als administrator.\r\n- Pluginlogboek: %APPDATA%\\Elgato\\StreamDeck\\Plugins\\com.chaseplanexl.deck.sdPlugin\\logs\\plugin.log"));
            Section(sb, Loc.T("ABOUT", "OVER"),
                Loc.T("Free and independent; not affiliated with Parallel 42, Elgato or Microsoft. The plugin uses ChasePlane's local Bridge, which is not officially documented, so a ChasePlane update can change it. This program is not code-signed, so Windows may warn the first time you run it (More info > Run anyway). Version {0}.",
                      "Gratis en onafhankelijk; niet verbonden aan Parallel 42, Elgato of Microsoft. De plugin gebruikt ChasePlane's lokale Bridge, die niet officieel gedocumenteerd is, dus een ChasePlane-update kan hem veranderen. Dit programma is niet digitaal ondertekend, dus Windows kan de eerste keer waarschuwen (Meer info > Toch uitvoeren). Versie {0}.", Updater.Current));
            return sb.ToString();
        }
    }
}
