# ChasePlane voor Stream Deck: een profiel voor elk model (MSFS 2020/2024)

Voor elk Stream Deck-model is er een eigen profiel, met de indeling aangepast aan het aantal toetsen. Er zijn twee manieren om ChasePlane te besturen:

| | Bestand | Wat het doet |
|---|---|---|
| **A. Met plugin (aanbevolen)** | `ChasePlane XL.streamDeckPlugin` (bevat de plugin **en** een profiel voor elk model) | Praat rechtstreeks met ChasePlane's Bridge. De views van je vliegtuig staan automatisch op de toetsen, de actieve camera licht op, en camera-modus, cinematic, zaklamp en wereldcamera's werken zonder dat je iets in ChasePlane instelt. |
| **B. Alleen sneltoetsen** | knop *Hotkeys-only profiel...* in de installer (de bestanden staan ook in de map `hotkeys-only\`) | Geen plugin; elke toets stuurt een sneltoets. Handig als de plugin niet werkt, maar je moet alle toetsen in ChasePlane toewijzen en er is geen live feedback. |

De bestandsnaam van het pakket zegt nog "XL" omdat het zo begon; het bevat alle modellen.

## Welk profiel past bij welk model

| Model | Toetsen | Navigatie | Pagina's |
|---|---|---|---|
| Stream Deck Mini | 3×2 (6) | laatste toets = volgende pagina | 8 |
| Stream Deck (15 toetsen), MK.2, Scissor Keys | 5×3 (15) | bovenste rij = 5 tabs | 5 |
| Stream Deck Neo | 4×2 (8) | laatste toets = volgende pagina | 8 |
| Stream Deck + | 4×2 (8) | laatste toets = volgende pagina | 8 |
| Stream Deck XL | 8×4 (32) | bovenste rij = 4 tabs + 4 vaste toetsen | 4 |
| Stream Deck + XL | 9×4 (36) | zoals XL, plus een extra kolom met cockpit/external/world/cinematic | 4 |
| Stream Deck Studio | 16×2 (32) | zoals XL, op twee lange rijen | 4 |

De draaiknoppen en het touch-scherm van de +, + XL, Studio en Neo gebruik ik niet. Stream Deck Mobile en Pedal zijn niet gedaan (Mobile heeft een eigen, instelbaar aantal toetsen; de Pedal heeft maar 3 pedalen).

**Previews:** in de map `preview\` staat per model een plaatje met alle pagina's onder elkaar (`xl.png`, `neo.png`, `mini.png`, `std.png`, `plus.png`, `plusxl.png`, `studio.png`; met `_hotkeys` erachter voor variant B). De 16 view-toetsen tonen daar voorbeeldnamen; in het echt staan hier de namen van de views van je vliegtuig.

## Installeren met één installer (aanbevolen, ook om weg te geven)

`release\ChasePlane-Deck-Setup.exe` doet alles in één keer: de plugin met de profielen installeren (via de Stream Deck-app) en, als je dat wilt, de extra toetsen in ChasePlane zetten. Het venster heeft één grote knop **Install**, plus losse knoppen *Plugin only*, *Keys only*, *Undo keys* (zet de back-up terug), *Key list...* en *Choose file...* (als je `user_settings.json` ergens anders staat).

- Sluit MSFS en ChasePlane eerst, anders weigert de installer de toetsen te zetten (ChasePlane herschrijft het bestand zolang het draait).
- Hij zoekt `user_settings.json` op de vier plekken die Parallel 42 noemt (MSFS 2024 of 2020, Steam of Microsoft Store) en past alle gevonden bestanden aan. Een commando dat al een toets heeft blijft ongemoeid, en een sneltoets die een ander commando al gebruikt wordt overgeslagen. Wijkt een standaardtoets van jouw ChasePlane af, dan meldt hij dat.
- Hij is onondertekend: Windows kan "Windows heeft uw pc beschermd" tonen (*Meer info* > *Toch uitvoeren*) en sommige virusscanners kunnen hem onterecht aanhouden. Een code-handtekening (certificaat) kost geld; die heb ik niet, dus dit blijft zo tot je er een koopt.
- **Voor anderen: stuur alleen `release\ChasePlane-Deck-Setup.exe`.** Alles zit erin: de plugin, de profielen voor alle modellen, de hotkeys-only profielen, de toetsenlijst en een hulpvenster in het Nederlands en Engels (knop *Hulp*). De `SHA256`-som staat in `release\SHA256.txt`.
- De installer spreekt Nederlands en Engels: hij start in de taal van Windows en rechtsboven kun je wisselen.
- Knoppen: **Installeren / bijwerken**, **Check & herstel** (controleert Stream Deck-app, plugin en bestanden, toetsen in ChasePlane, Bridge en pluginlogboek en repareert wat kan), **Verwijderen...** (kies wat weg moet: de door Setup toegevoegde toetsen, met back-up; de plugin; de ChasePlane-profielen in de Stream Deck-app, die naar een back-upmap worden verplaatst en niet gewist; en vink *Daarna opnieuw installeren* aan voor een schone herinstallatie; de Stream Deck-app wordt daarvoor afgesloten en weer gestart), plus *Alleen plugin*, *Alleen toetsen*, *Herstel back-up*, *Toetsenlijst...*, *Kies bestand...*, *Hotkeys-only profiel (zonder plugin)...* en *Hulp*.

## Een update uitbrengen

1. Zet een hoger versienummer in het bestand `VERSION` (bijvoorbeeld `1.1.0.0`). Plugin, profielen en installer nemen dat over.
2. Draai `build\Build-ChasePlaneXL.ps1` en daarna `build\Build-Installer.ps1 -UpdateUrl https://raw.githubusercontent.com/kekev2001/chaseplane-deck/main/latest.json -DownloadUrl https://github.com/kekev2001/chaseplane-deck#download -Notes "wat er nieuw is" -Publish` (kopieert de exe naar `download\` en schrijft `latest.json`; commit en push beide).
3. Zet `release\ChasePlane-Deck-Setup.exe` op de downloadplek en `latest.json` (projectroot) op het `-UpdateUrl`-adres.
4. Wie Setup opent, ziet een link "Update beschikbaar". Er wordt niets automatisch gedownload of uitgevoerd; de gebruiker haalt de nieuwe exe op en klikt op *Installeren / bijwerken* (Stream Deck vervangt de plugin; reeds gezette toetsen blijven staan).

**Let op:** `-UpdateUrl` moet al in de **eerste** versie zitten die je weggeeft. Een versie zonder ingebouwd adres gebruikt het netwerk niet en kan dus nooit een update melden. Zonder `-UpdateUrl` is de update-controle uit. Het adres moet met `https://` beginnen.

## Installeren met de hand (A, plugin)

1. Laat de Stream Deck-app draaien (versie 6.4 of nieuwer) met je deck aangesloten.
2. Dubbelklik op `ChasePlane XL.streamDeckPlugin`. De app installeert de plugin **en** de bijbehorende profielen; het profiel voor jouw model staat daarna in de profielenlijst (*ChasePlane*, *ChasePlane Mini*, *ChasePlane XL*, *ChasePlane Plus*, *ChasePlane Neo*, *ChasePlane Plus XL* of *ChasePlane Studio*).
3. Kies in de app dat profiel. Start MSFS en ChasePlane; de plugin verbindt zelf (ook als je ze later start).

Heb je eerder het oude hotkeys-profiel *ChasePlane XL* geïmporteerd, dan kun je dat verwijderen of hernoemen; het nieuwe profiel heet ook zo.

## Installeren (B, alleen sneltoetsen)

Gebruik in de installer de knop *Hotkeys-only profiel (zonder plugin)...* en kies je model (of dubbelklik op het bestand uit `hotkeys-only\`). Daarna moeten alle toetsen een sneltoets in ChasePlane hebben: zie de tabellen verderop.

## De pagina's

**XL, + XL en Studio:** de bovenste rij is op elke pagina een tabbalk (tik om te wisselen; het actieve tabblad is gevuld met een witte streep), plus vier vaste toetsen: vorige view, volgende view, in/uit en reset camera.

| Tabblad | Inhoud |
|---|---|
| **VIEWS** | Cockpit, External, World, Cinematic, volgende cinematic, zaklamp · **status-toets** (groen = Bridge verbonden, toont modus en vliegtuig; rood = Bridge niet bereikbaar) · **16 view-toetsen** met de namen van de views van het geladen vliegtuig in de huidige camera-modus; de actieve view licht op |
| **WORLD** | Tower, Runway, Parking, Spotting (dichtstbijzijnde) · Drone, Flyby, Traffic · zoom · Peek (kijken terwijl je de toets vasthoudt) |
| **FLY CAM** | Bewegen, kijken, rollen, zoom, snelheid slow/normal/fast, boost, drag mode, resets |
| **FX** | Zaklamp, cinematic · binoculars, night vision, depth of field, autofocus, exposure, head tracking |

**15 toetsen:** vijf tabs (VIEWS, WORLD, FLY CAM, LOOK, FX) met 10 toetsen per pagina. Op VIEWS staan cockpit/external/world, vorige/volgende view, 4 view-toetsen en de status-toets; LOOK bevat kijken, rollen en peek. Er passen minder toetsen dan op de XL: snelheidsstanden, drag mode, autofocus, head tracking en de in/uit-toets ontbreken.

**Mini, Neo en +:** er is geen ruimte voor een tabbalk. De **laatste toets (rechtsonder)** springt naar de volgende pagina en toont de naam en kleur van die pagina; na de laatste pagina ben je weer terug bij de eerste. De volgorde is:

| Model | Volgorde |
|---|---|
| Neo, + | CAMERA (modi, vorige/volgende view, reset) → VIEWS (7 view-toetsen) → WORLD → LOOK (peek, zoom) → FLY CAM → ROTATE → FX → FX 2 |
| Mini | CAMERA → VIEWS (5 view-toetsen) → WORLD → LOOK → CINEMA → FLY CAM → FLY 2 → FX |

Een view-toets instellen: klik in de Stream Deck-app op de toets, kies **Camera mode** (volg ChasePlane, of vast cockpit/external/world) en het **slotnummer**. De app laat zien welke view daar nu staat.

## ChasePlane instellen (eenmalig, alleen voor de extra toetsen)

De Bridge-toetsen hebben **niets** nodig. Bewegen, kijken, zoomen, boost en peek links/rechts gebruiken toetsen die al in jouw ChasePlane staan (gelezen uit je `user_settings.json`): `CAM_QUICK_VIEW_LEFT`, `CAM_QUICK_VIEW_RIGHT`, `CAM_PREV_VIEW`, `CAM_FLASHLIGHT_TOGGLE`, `CAM_NEXT_VIEW`, `CAM_TOGGLE_IN_OUT`, `CAM_RESET`, `CAM_ZOOM_IN`, `CAM_ZOOM_OUT`, `CAM_MOVE_D`, `CAM_MOVE_L`, `CAM_MOVE_F`, `CAM_MOVE_B`, `CAM_MOVE_U`, `CAM_MOVE_R`, `CAM_ROT_L`, `CAM_BOOST_SET`, `CAM_ROT_U`, `CAM_ROT_D`, `CAM_ROT_R`.

Een aantal extra toetsen heeft een eigen sneltoets nodig (`Ctrl+Alt` + F-toets, cijfer of letter). **Voor het plugin-profiel zijn dat 21 toetsen:**

| Tabblad | Knop | ChasePlane-opdracht | Toets |
|---|---|---|---|
| World | PEEK BACK | `CAM_QUICK_VIEW_BEHIND` | `Ctrl+Alt+F16` |
| World | PEEK DOWN | `CAM_QUICK_VIEW_DOWN` | `Ctrl+Alt+F11` |
| World | PEEK UP | `CAM_QUICK_VIEW_UP` | `Ctrl+Alt+F7` |
| World | RESET ZOOM | `CAM_RESET_ZOOM` | `Ctrl+Alt+7` |
| Fly cam | SPEED FAST | `CAM_CONTROL_PROFILE_FAST` | `Ctrl+Alt+3` |
| Fly cam | SPEED NORMAL | `CAM_CONTROL_PROFILE_NORMAL` | `Ctrl+Alt+2` |
| Fly cam | SPEED SLOW | `CAM_CONTROL_PROFILE_SLOW` | `Ctrl+Alt+1` |
| Fly cam | DRAG MODE | `CAM_DRAG_TOGGLE` | `Ctrl+Alt+5` |
| Fly cam | RESET HORIZON | `CAM_RESET_ORIENT` | `Ctrl+Alt+8` |
| Fly cam | ROLL LEFT | `CAM_ROLL_L` | `Ctrl+Alt+4` |
| Fly cam | ROLL RIGHT | `CAM_ROLL_R` | `Ctrl+Alt+6` |
| FX | BINOCULARS | `CAM_BINOCULARS` | `Ctrl+Alt+F24` |
| FX | BINO (HOLD) | `CAM_BINOCULARS_HOLD` | `Ctrl+Alt+Z` |
| FX | EXPOSURE LESS | `CAM_EXPOSURE_LESS` | `Ctrl+Alt+V` |
| FX | EXPOSURE MORE | `CAM_EXPOSURE_MORE` | `Ctrl+Alt+N` |
| FX | HEAD TRACKING | `CAM_HEAD_TRACKING_TOGGLE` | `Ctrl+Alt+0` |
| FX | NVG LESS | `CAM_NVG_INTENSITY_LESS` | `Ctrl+Alt+B` |
| FX | NVG MORE | `CAM_NVG_INTENSITY_MORE` | `Ctrl+Alt+M` |
| FX | DEPTH OF FIELD | `CAM_TOGGLE_DOF` | `Ctrl+Alt+9` |
| FX | AUTO FOCUS | `CAM_TOGGLE_DOF_AUTOFOCUS` | `Ctrl+Alt+X` |
| FX | NIGHT VISION | `CAM_TOGGLE_NVG` | `Ctrl+Alt+C` |

Toewijzen kan met de installer (knop *Keys only*), of met het script (sluit eerst MSFS en ChasePlane); beide doen precies hetzelfde:

```powershell
powershell -ExecutionPolicy Bypass -File "build\Apply-ChasePlaneKeys.ps1" -HybridOnly
```

Het script voegt alleen die toetsen toe aan `user_settings.json`, maakt eerst een back-up (`user_settings.json.bak-…`) en doet niets dubbel als je het opnieuw draait. Met `-DryRun` zie je eerst wat er gebeurt; zonder `-HybridOnly` komen ook de 19 toetsen voor de hotkeys-versie erbij. Terugdraaien: kopieer de back-up terug. Zie je de toetsen na het starten van ChasePlane niet staan (cloud-sync staat aan), wijs ze dan met de hand toe: ChasePlane → Menu → Preferences → Control Assignments.

Toetsen die alleen de hotkeys-versie (B) gebruikt:

| Tabblad | Knop | ChasePlane-opdracht | Toets |
|---|---|---|---|
| Views | NEXT CINEMA | `CAM_NEXT_CINEMATIC` | `Ctrl+Alt+F21` |
| Views | NEXT GROUP | `CAM_NEXT_GROUP` | `Ctrl+Alt+F9` |
| Views | PREV GROUP | `CAM_PREV_GROUP` | `Ctrl+Alt+F5` |
| Views | CINEMATIC | `CAM_SET_CINEMATIC` | `Ctrl+Alt+F13` |
| Views | DRONE | `CAM_SET_DRONE` | `Ctrl+Alt+F17` |
| Views | FLYBY | `CAM_SET_FLYBY` | `Ctrl+Alt+F20` |
| Views | COCKPIT | `CAM_SET_ONBOARD` | `Ctrl+Alt+F2` |
| Views | EXTERNAL | `CAM_SET_OUTSIDE` | `Ctrl+Alt+F4` |
| Views | OVERVIEW | `CAM_SET_OVERVIEW` | `Ctrl+Alt+F23` |
| Views | WORLD | `CAM_SET_WORLD` | `Ctrl+Alt+F8` |
| Views | SMART VIEW | `CAM_SMART_VIEW` | `Ctrl+Alt+F14` |
| Views | SMART HOLD | `CAM_SMART_VIEW_HOLD` | `Ctrl+Alt+F18` |
| World | TRAFFIC TRACK | `CAM_CENTER_TRAFFIC_TRACK` | `Ctrl+Alt+F22` |
| World | TRAFFIC VIEW | `CAM_CENTER_TRAFFIC_VIEW` | `Ctrl+Alt+F19` |
| World | PARKING | `CAM_NEAR_PARKING` | `Ctrl+Alt+F6` |
| World | RUNWAY | `CAM_NEAR_RUNWAY` | `Ctrl+Alt+F3` |
| World | SPOTTING | `CAM_NEAR_SPOTTING` | `Ctrl+Alt+F10` |
| World | TOWER | `CAM_NEAR_TOWER` | `Ctrl+Alt+F1` |
| World | TRAFFIC | `CAM_NEAR_TRAFFIC` | `Ctrl+Alt+F15` |

## Hoe het werkt, en wat ik niet kon testen

ChasePlane's Bridge (`CP MSFS Bridge.exe`) draait een lokale WebSocket op `ws://127.0.0.1:8652`. De plugin meldt zich daar aan als client en stuurt commando's zoals `set_camera_mode`, `get_views`, `set_view_by_guid`, `cam_go_to_nearest`, `cam_cinematic_toggle` en `cam_flashlight_toggle`, en leest meldingen als `cam_mode_set` voor de live toetsen. Die berichten heb ik gelezen uit de web-UI die in de Bridge zelf zit (de ChasePlane-afstandsbediening). **De API is niet officieel gedocumenteerd**: een ChasePlane-update kan hem veranderen.

- De plugin is getest tegen een nagemaakte Bridge en een nagemaakte Stream Deck (32 controles, `test\plugin-test.js`), niet tegen echt ChasePlane, MSFS of de Stream Deck-app. De eerste echte test is bij jou.
- De profielen heb ik niet in de Stream Deck-app geïmporteerd. Ik heb de structuur nagebouwd naar profielen die Elgato zelf meelevert (Plus XL en andere standaardprofielen) en naar de GSX-plugin, en `test\Validate-Profiles.ps1` controleert alle 14 bestanden (toetsen binnen het raster van het model, afbeeldingen aanwezig, tab- en volgende-pagina-toetsen wijzen naar een bestaande pagina, plugin-acties bestaan, `DeviceType` klopt). Dat bewijst niet dat de app ze accepteert.
- Het modelnummer van de Stream Deck Studio (`20GBL9901`) is een aanname; de andere modelnummers komen uit Elgato's eigen bestanden. Bij de plugin-route bepaalt vooral het `DeviceType` welk profiel bij welk deck hoort. Werkt een profiel voor jouw model niet, zeg het dan: dan pas ik dat model aan.
- De paginanummers van de tab- en volgende-pagina-toetsen (1 = eerste pagina) heb ik afgeleid uit Elgato's eigen Plus XL-profiel: daar staat een mixer-toets met nummer 3, en de mixer-pagina is de derde pagina. Zeker weten doe ik het niet.
- Welke velden de Bridge precies stuurt voor "cinematic aan" of "zaklamp aan" weet ik niet zeker; die twee toetsen lichten daarom alleen op als de Bridge zo'n melding stuurt. Ze werken wel als knop.
- Een plugin-toets stuurt de Bridge een commando, niet een sneltoets; MSFS of ChasePlane hoeft dus niet het actieve venster te zijn.

## Problemen oplossen

- **Status-toets blijft rood ("BRIDGE OFFLINE").** MSFS en ChasePlane moeten draaien. Daarna verbindt de plugin binnen een paar seconden zelf.
- **Plugin doet niets of toetsen blijven leeg.** Open het logbestand `%APPDATA%\Elgato\StreamDeck\Plugins\com.chaseplanexl.deck.sdPlugin\logs\plugin.log`; daar staat of de verbinding lukt en welke commando's falen. Stuur me die regels, dan pas ik de plugin aan. Werkt het niet, gebruik dan tijdelijk variant B.
- **Een tabblad opent de verkeerde pagina.** Zet bovenin `build\Build-ChasePlaneXL.ps1` `$GotoBase = 0` en bouw opnieuw.
- **Peek/beweeg-toets doet niets.** Controleer in ChasePlane (Control Assignments) of de opdracht de juiste toets heeft. Draait MSFS of ChasePlane als administrator, start dan ook de Stream Deck-app als administrator.
- **Camera springt.** ChasePlane raadt aan alle camera-toewijzingen in MSFS zelf te verwijderen (behalve drone).

## Opnieuw bouwen

`build\Build-Installer.ps1` maakt daarna `release\ChasePlane-Deck-Setup.exe` (met de bij Windows meegeleverde compiler, broncode in `installer\`; testen kan met `/silent /noplugin /dryrun /settings:<bestand>`). `build\Build-ChasePlaneXL.ps1` maakt het plugin-pakket, alle profielen en `chaseplane-keymap.csv` opnieuw (de indeling per model staat in `$Devices`, de toetsen in `$Items`; met `CP_PREVIEW_DIR` erbij komen ook de preview-plaatjes). Daarna kun je `test\Validate-Profiles.ps1` draaien. De plugin zelf staat in `plugin\com.chaseplanexl.deck.sdPlugin` (alleen Node.js 20 van Stream Deck zelf, geen extra pakketten).

*Onafhankelijk project, niet verbonden aan Parallel 42, Elgato of Microsoft.*
