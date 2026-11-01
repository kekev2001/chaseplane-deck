# ChasePlane Deck voor Stream Deck

Een gratis, onofficiële Stream Deck-plugin met een kant-en-klaar profiel voor **elk Stream Deck-model** (Mini, 15 toetsen / MK.2, Neo, +, XL, + XL, Studio) om **ChasePlane** (Parallel 42) in Microsoft Flight Simulator 2020 en 2024 te besturen.

- Cockpit-, External- en World-camera, **de views van je geladen vliegtuig op de toetsen (live namen, de actieve view licht op)**, cinematic, zaklamp, dichtstbijzijnde tower / runway / parking / spotting, drone, flyby, traffic.
- Fly cam, rondkijken, rollen, zoom, peek, night vision, binoculars, depth of field, exposure, head tracking.
- Pagina's (tabs) in plaats van één volle deck. Kleine decks (Mini, Neo, +) krijgen een "volgende pagina"-toets.


## Downloaden

**[ChasePlane-Deck-Setup.exe](https://github.com/kekev2001/chaseplane-deck/releases/latest/download/ChasePlane-Deck-Setup.exe)** (ongeveer 13 MB, Windows 10/11; nieuwste versie: [laatste release](https://github.com/kekev2001/chaseplane-deck/releases/latest), oudere versies staan op de [Releases-pagina](https://github.com/kekev2001/chaseplane-deck/releases)). Alles zit in dit ene bestand. SHA-256: zie [download/SHA256.txt](download/SHA256.txt). Engelse uitleg: [README.md](README.md). Ontwikkelaarsnotities: [docs/ONTWIKKELEN.md](docs/ONTWIKKELEN.md).

## Installeren (2 minuten)

1. Installeer de **Stream Deck-app** (versie 6.4 of nieuwer) en sluit je deck aan.
2. Start **`ChasePlane-Deck-Setup.exe`**. Het venster staat in het Nederlands op een Nederlandse Windows (rechtsboven kun je wisselen naar English). Klik op **Installeren / bijwerken**.
   - Windows kan "Windows heeft uw pc beschermd" tonen omdat het programma niet digitaal is ondertekend: klik op *Meer info* > *Toch uitvoeren*.
   - De Stream Deck-app toont een installatievenster voor de plugin. Klik daar op de installatieknop.
   - Sluit MSFS en ChasePlane eerst als Setup de extra sneltoetsen moet toevoegen (zie hieronder).
3. Kies in de Stream Deck-app het **ChasePlane**-profiel voor je deck.
4. Start MSFS en ChasePlane. De status-toets wordt groen als de plugin verbonden is.

## Bijwerken, herstellen, verwijderen

- **Bijwerken:** download de nieuwe exe, start de nieuwe `ChasePlane-Deck-Setup.exe` en klik op *Installeren / bijwerken*. Setup laat bovenin zien welke pluginversie er staat en welke in deze Setup zit. Toetsen die al staan worden niet dubbel toegevoegd. Is er een updateadres ingebouwd, dan meldt Setup zelf dat er een nieuwere versie is (alleen een link; er wordt niets automatisch gedownload of uitgevoerd).
- **Check & herstel:** controleert de Stream Deck-app, of de plugin er staat en heel is, of alle toetsen in ChasePlane staan, of de ChasePlane Bridge reageert, en wat het pluginlogboek laatst meldde. Wat Setup zelf kan oplossen (plugin opnieuw installeren, ontbrekende toetsen toevoegen) doet het na jouw bevestiging.
- **Verwijderen...:** je kiest wat weg moet: de toetsen die Setup aan ChasePlane heeft toegevoegd (alleen precies die sneltoetsen, met een back-up), de plugin en de ChasePlane-profielen in de Stream Deck-app (verplaatst naar een back-upmap naast ProfilesV3, niet gewist). Vink *Daarna opnieuw installeren* aan voor een schone herinstallatie. Daarvoor wordt de Stream Deck-app afgesloten en weer gestart.
- **Herstel back-up...:** zijn sneltoetsen van jou weg uit ChasePlane, kies dan een van de bewaarde kopieën (de kopie met de meeste sneltoetsen die ChasePlane nu mist is al gekozen). *Alleen mijn sneltoetsen* zet je sneltoetsenlijst terug en laat alle andere instellingen zoals ze nu zijn; Setup voegt daarna zijn deck-toetsen opnieuw toe zonder de jouwe aan te raken. *Het hele instellingenbestand* zet `user_settings.json` terug zoals het in die kopie was. Het bestand zoals het nu is wordt eerst bewaard. Setup werkt alleen op een ChasePlane dat zijn eigen sneltoetsenlijst al heeft bewaard; is die lijst nog leeg, dan wijzigt het niets.

## De extra ChasePlane-toetsen

De meeste toetsen praten rechtstreeks met ChasePlane en hebben niets nodig. Een paar (peek omhoog/omlaag/achter, roll, snelheid, binoculars, night vision, exposure, depth of field, head tracking) hebben een sneltoets in ChasePlane nodig. Setup zet ze (`Ctrl+Alt` + een F-toets, cijfer of letter) in ChasePlane's `user_settings.json`:

- *Installeren / bijwerken* vraagt eerst en zegt hoeveel er bij komen; antwoord **Nee** (of gebruik *Alleen plugin*) en de instellingen van ChasePlane blijven helemaal ongemoeid;
- eerst wordt een back-up naast het bestand gezet, plus een tweede kopie in `%APPDATA%\ChasePlane Deck\Backups` (buiten de ChasePlane-map); na het schrijven leest Setup het bestand terug en zet het origineel terug als het niet precies is zoals bedoeld;
- een commando dat al een toets heeft blijft ongemoeid, en een sneltoets die een ander commando al gebruikt wordt overgeslagen;
- *Toetsenlijst...* toont alle sneltoetsen, zodat je ze liever zelf kunt toewijzen via ChasePlane > Preferences > Control Assignments;
- met ChasePlane cloud sync aan kan ChasePlane zijn cloudkopie van de instellingen terugzetten; wijs de toetsen dan met de hand toe.

Sommige toetsen (bewegen, kijken, zoomen, peek links/rechts, boost) gebruiken ChasePlane's **standaard**sneltoetsen. Heb je die in ChasePlane veranderd, dan meldt Setup welke afwijken.

## Welk profiel krijg ik

| Deck | Toetsen | Pagina's |
|---|---|---|
| Stream Deck Mini | 6 | 8 (laatste toets = volgende pagina) |
| Stream Deck 15 toetsen / MK.2 | 15 | 5 tabs |
| Stream Deck Neo, Stream Deck + | 8 | 8 (laatste toets = volgende pagina) |
| Stream Deck XL | 32 | 4 tabs + 4 vaste toetsen |
| Stream Deck + XL | 36 | zoals XL plus een extra kolom |
| Stream Deck Studio | 32 | zoals XL, op twee lange rijen |

Draaiknoppen en touch-strips worden niet gebruikt. De knop *Hotkeys-only profiel...* in Setup importeert hetzelfde profiel zonder plugin (elke toets stuurt een sneltoets; geen live view-namen). Die profielen zitten in de exe; je hebt geen losse bestanden nodig.

## Problemen

- **Status-toets blijft rood / "BRIDGE OFFLINE":** start MSFS en ChasePlane; de plugin verbindt binnen enkele seconden zelf opnieuw.
- **Toetsen doen niets:** gebruik *Check & herstel*, en controleer in ChasePlane (Control Assignments) of het commando de juiste toets heeft. Draait MSFS/ChasePlane als administrator, start dan ook de Stream Deck-app als administrator.
- **Pluginlogboek:** `%APPDATA%\Elgato\StreamDeck\Plugins\com.chaseplanexl.deck.sdPlugin\logs\plugin.log`
- **Een tab opent de verkeerde pagina:** meld het graag, met je deckmodel.

## Let op

- Dit is een eerste versie. De plugin is getest tegen een nagemaakte ChasePlane Bridge en een nagemaakte Stream Deck, en de profielbestanden zijn structureel gecontroleerd. Meldingen van echte decks (vooral Mini, Neo, +, + XL en Studio) zijn zeer welkom.
- De plugin gebruikt ChasePlane's lokale Bridge (`ws://127.0.0.1:8652`). Die interface is niet officieel gedocumenteerd, dus een ChasePlane-update kan hem veranderen. De `hotkeys-only`-profielen zijn de terugvaloptie.
- Onafhankelijk project. Niet verbonden aan, goedgekeurd door of ondersteund door Parallel 42, Elgato of Microsoft. ChasePlane, Stream Deck en Microsoft Flight Simulator zijn merken van hun eigenaren.
- Setup installeert niets buiten de Stream Deck-pluginmap (via de Stream Deck-app), een tijdelijk bestand in `%TEMP%\ChasePlaneDeckSetup`, kopieën van ChasePlane's `user_settings.json` in `%APPDATA%\ChasePlane Deck\Backups`, en de back-up en wijziging van ChasePlane's `user_settings.json` die je goedkeurt door op Installeren te klikken. Zonder ingebouwd updateadres gebruikt Setup het netwerk niet.
