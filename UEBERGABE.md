# Übergabe: SketchUp-Plugin „Treppenbau“ (Stand 2.4.0, 02.10.2026)

## Was es ist
SketchUp-Erweiterung (Ruby, ab SU 2017) für parametrische Treppen mit CNC-Export nach TCN (TpaCAD), angelehnt an Jürgens Plugin **dxf4tcn**.

## Dateien in diesem Ordner (E:\sketchup-treppe)
- `treppenbau_2.4.0.rbz` – aktuelle installierbare Version 2.4.0 (2.3.0 nur noch in der Git-Historie; ab 2.3.0 Versionsnummer im Dateinamen; `_9` = 2.0.0, `_8` = 1.5.3, `_1` = 1.1.0 … `_4` = 1.4.0, `_5` = 1.5.0, `_6` = 1.5.1, `_7` = 1.5.2)
- `src/` + `test/` – **Arbeitskopie** der Quellen (Stand 2.4.0), wird vom Entwickler-Loader direkt geladen
- `jt_aa_treppenbau_dev.rb` – Entwickler-Loader (in den SketchUp-Plugins-Ordner kopieren, lädt aus `E:\sketchup-treppe\src`)
- `treppenbau_quellen_tests_9.zip` – Quellcode + Tests Stand 2.0.0 (`_8` = 1.5.3, `_7` = 1.5.2, `_6` = 1.5.1, `_5` = 1.5.0, ohne Nummer = 1.4.0)
- `_to_delete/` – Debug-Plots, kann gelöscht werden
- Referenz dxf4tcn: `E:\sketchup-dxf2tcn\dxf4tcn_1.rbz` (TCN-Format, Werkzeuge), Beispiel `Kirmes 26 Leuchtturm.tcn`
- Verwandt: `E:\cvs2tcn` (csv2tcn, OpenCutList-Integration)

## Aufbau (src/jt_treppenbau.rb + src/jt_treppenbau/)
| Datei | Inhalt |
|---|---|
| `jt_treppenbau.rb` | Loader, `EXT_VERSION` |
| `main.rb` | Menü/Symbolleiste/Kontextmenü, Attribute (`JT_Treppenbau` → `params` als JSON an der Definition) |
| `params.rb` | **Schema aller Parameter** (Dialog wird daraus generiert), Varianten, `normalize`, `side_kind` (Seite → wange/sattel/frei) |
| `geometry.rb` | Reine Geometrie (ohne SU-API): `Plan`, `Polyline`, `Turtle` (Ecken mit beliebigem Winkel, schräger Endschnitt), `Layout.compute`, `finish_flights`, Drachenstufen |
| `fit.rb` | Raum einpassen (`fit_mode = 'raum'`), Klasse `Fit::Room`; Kopffreiheit |
| `stringers.rb` | **neu**: Wangen aus geraden Brettern (eingestemmt + aufgesattelt), gemeinsam für 3D und CNC |
| `builder.rb` | SketchUp-Geometrie (Stufen, Setzstufen, Wangen, Sattelwangen, Holm, Massiv, Geländer, Spindel, Gehlinie, Decke/Treppenloch, Raumumriss) |
| `dialog.rb` + `ui/dialog.html` | Parameterdialog (HtmlDialog) mit SVG-Grundriss (Raum, Wände, Treppenloch), Live-Update |
| `parts.rb` | Zerlegung in flache Frästeile (mm), Wangen abgewickelt mit Nuten (exakte Ausstemmung), Sattelwangen; Modul `Pockets` (Vereinigung, Ausräumbahnen) |
| `nesting.rb` | Raster-Nesting mit Bitmasken je Zeile, 0/180° (Faser) oder 0/90/180/270° |
| `tcn.rb` | TCN-Writer (Kopf identisch dxf4tcn), Gravur r0/r1, Nuten (Bahnen aus `parts.rb`), Außenkontur zuletzt |
| `cnc.rb` + `cnc_dialog.rb` + `ui/cnc.html` | CNC-Dialog, Plattenvorschau, Export TCN je Platte + Teileliste.csv |

## Kernprinzip Geometrie
Grundriss = drei Polylinien in Laufrichtung: `inner`, `walk` (Gehlinie), `outer`. Stufenkante bei Gehlinienposition w: von `inner.at(s(w))` durch `walk.at(w)` bis Schnitt mit `outer`. `s(w)` stückweise linear → steuert Verziehen. Podeste: parallel verschobene Linien (`translated`). Wendeltreppen: Bögen, radial.

## Version 2.4.0 (treppenbau_2.4.0.rbz) – Antritt außerhalb des Raums (fehler.md Nr. 4)
- `antritt_l` „Antritt: Abstand von der hinteren Wand“ darf jetzt **größer als die Raumlänge** sein: die ersten Stufen liegen dann vor dem Raumende bzw. außerhalb des Treppenlochs. Die Meldung „Antritt liegt außerhalb der Raumlänge“ gibt es nur noch beim Grundmaß (`_box`).
- Der **Austritt** muss weiterhin im Raum bzw. am Treppenloch liegen: neue Prüfung in `Room#check_room` (bei festem Antritt: Austrittslinie nicht vor dem Raumende; betrifft v. a. U/dreiläufig, deren Austrittslauf nach vorn läuft) → Meldung „Austritt liegt außerhalb der Raumlänge.“
- Wendeltreppen: Verschiebt die Drachenstufen-Lage den Antritt nach vorn, war das bisher nur bis zum Raumende erlaubt; liegt der feste Antritt schon vor dem Raumende, ist die Verschiebung jetzt frei (Warnung wie bisher).
- Info neu: „Treppe ragt über das Raumende (Antritt) hinaus: … cm“. Hilfetext des Parameters ergänzt. Seitenwände gelten vor dem Raumende als verlängert (Treppe muss auch dort zwischen den Wandlinien bleiben).
- Test neu: `test/antritt_test.rb` (73 Fälle, alle Formen, rechts/links, mit/ohne Treppenloch, Antritt 5–60 cm vor dem Raumende: Antritt exakt, Austritt im Raum; freier Antritt bleibt im Raum) – 0 Fehler. `build_test.rb` zusätzlich mit Antritt 20 cm vor dem Raumende – 0 Fehler; fit/box/kite/stringer/sattel/reload/cnc unverändert.

## Version 2.3.0 (treppenbau_2.3.0.rbz)
- Enthält fehler.md Nr. 1 (Wangenform geschwungen auch für aufgesattelte Wangen), Nr. 2 und Nr. 3. Update ohne Deinstallation: Erweiterungs-Manager → „Erweiterung installieren“ → .rbz, ggf. „Treppenbau neu laden“.
- `test/reload_test.rb` liest die Version jetzt aus `src/jt_treppenbau.rb` (vorher fest 2.0.0).

## Neu in 2.3.0 – Grundmaß bei freier Planung (fehler.md Nr. 3)
- Neue Parameter `total_w` „Gesamtbreite der Treppe“ und `total_l` „Gesamttiefe der Treppe“ (Gruppe jetzt „Platzvorgabe (Grundmaß / Raum)“), nur bei „Treppe aus den Parametern berechnen“ sichtbar (`freeonly`), nicht bei Wendeltreppen. 0 = wie bisher aus den Parametern.
- Umsetzung (`fit.rb`: `box_active?`, `solve_box`, `box_room`, `box_report`, `box_msg`): Einpassen wie in einen Raum mit drei Wänden, Spiel 0, rechte Winkel, ohne Treppenloch. Breite = über alles inkl. eingestemmter Wangen; Tiefe = fester Antritt (vorderste Stufenkante) bis Rückseite. Fehlt die Breite → natürliche Breite aus der freien Planung; fehlt die Tiefe → erst freier Antritt, dann exakt neu gerechnet. Ursprung = vordere linke Ecke des Grundmaßes.
- Flag `_box` in `Room#check_room`: auch bei festem Antritt darf nichts vorn überstehen (U/dreiläufig: Austrittslauf).
- Info „Grundmaß Breite × Tiefe“ (vorgegeben / aus Parametern), ggf. „Tatsächlicher Umriss“; Raumtexte (Wand, Luft, Antritt) entfallen bzw. werden umformuliert. L gewendelt: lassen sich Drachenstufen und Tiefe nicht vereinbaren, liegt die Treppe hinten an und vorn bleibt Platz (Warnung „Gesamttiefe wird um … nicht ausgefüllt“).
- Vorschau: Grundmaß gestrichelt mit Beschriftung „Grundmaß“ (`space[:box]`, `space[:label]`); im 3D-Modell keine Hilfslinien dafür.
- Test neu: `test/box_test.rb` (120 Fälle: Breite/Tiefe exakt, Ursprung, Breite aus Parametern = freie Planung, Raum-Modus unverändert, zu kleines Grundmaß → Meldung ohne „Raum“) – 0 Fehler; `build_test.rb` zusätzlich mit Grundmaß – 0 Fehler; fit/stringer/sattel/kite/reload unverändert.

## Neu in 2.3.0 – Stöße der eingestemmten Wange bündig (fehler.md Nr. 2)
- **Fehler behoben:** Bei Form „gerade“ (konstante Breite) hatte jedes Brett seine eigene Oberkanten-Gerade → an Gehrungsfugen (Wendelbereich) und Podesten Versatz oben und unten (bis > 50 cm).
- Jetzt je Profilstück **stetige Oberkante**: Läufe aus mehreren Brettern bekommen gemeinsame Fugenhöhen (LP `joint_heights`/`lp_min`: Summe der größten Überstände je Brett minimal, danach kleinste Fläche; je Brett weiter gerade). An Podesten knickt die Oberkante im Podestbrett in die Steigung des Laufs ein (Kröpfung, `straight_piece`); sonst wird das niedrigere Brettende angehoben.
- **Unterkante = Parallele** im Abstand der Brettbreite (`offset_down`, Gehrung an Knicken) → Ober- und Unterkante an jedem Stoß bündig, Breite rechtwinklig überall = `str_h`. Dadurch kleiner Knick der Unterkante kurz hinter dem Stoß.
- Brettbreite automatisch: `straight_need` (Bisektion, auf 0,5 cm). Bretter haben jetzt `:tp`/`:bp` (Polylinien) wie die geschwungene Form → 3D/CNC über `curve_outline`/`curve_band`.
- Test: `stringer_test.rb` prüft bei „gerade“ zusätzlich Fuge = 0 (auch an Podesten) und Mindestbreite – 0 Fehler; build/sattel/kite/cnc/pk_check/reload ohne Fehler. Enthalten in 2.3.0.

## Neu in 2.0.0 – Update ohne Deinstallation/Neustart
- **Ursache vorher:** `main.rb` lud die Untermodule mit `require` → Ruby lädt eine Datei pro Sitzung nur einmal; nach Installation einer neuen .rbz lief bis zum Neustart der alte Code. (Signieren ändert daran nichts.)
- `main.rb`: Untermodule per `load` (`module_files`, `load_modules`); neue Methode `Treppenbau.reload(quiet:)` lädt Registrierungsdatei + `main.rb` + alle Module neu, schließt offene Dialoge, unterdrückt Konstanten-Warnungen, meldet „alt → neu“ bzw. Fehler (Syntaxfehler → Meldung statt Absturz). Menüs/Toolbar nur einmal angelegt (`file_loaded?` + `@ui_created`).
- Menü **Erweiterungen › Treppenbau › „Treppenbau neu laden“**.
- `jt_treppenbau.rb` darf mehrfach laufen: registriert nur einmal, aktualisiert sonst Version/Beschreibung im Erweiterungs-Manager. Führt SketchUp die Datei nach „Erweiterung installieren“ selbst erneut aus, wird automatisch neu geladen (per `UI.start_timer`). Eine zweite Kopie aus anderem Ordner wird übersprungen (erste gewinnt).
- **Update-Ablauf ab 2.0.0:** Erweiterungs-Manager → „Erweiterung installieren“ → neue .rbz (über die alte, ohne Deinstallation) → ggf. „Treppenbau neu laden“. Einmalig nötig: Installation von 2.0.0 selbst mit Neustart.
- **Entwicklung:** `jt_aa_treppenbau_dev.rb` in den Plugins-Ordner (`%APPDATA%\SketchUp\SketchUp 20xx\SketchUp\Plugins`) → lädt aus `E:\sketchup-treppe\src` vor der installierten Version; nach Änderungen nur „neu laden“.
- **Grenzen:** neue Menüpunkte/Buttons/Kontextmenü erst nach Neustart; gelöschte Methoden bleiben bis Neustart im Speicher; Änderung der Oberklasse einer Klasse → Neustart.
- Test neu: `test/reload_test.rb` (Registrierung, Neuladen, Auto-Neuladen nach Installation, Syntaxfehler, zweite Kopie) – 0 Fehler; build/stringer/sattel/kite/cnc/fit unverändert ohne Fehler.
- Hinweis: Der Code nutzt `Array#sum` (Ruby 2.4) → tatsächlich SketchUp 2018+, nicht 2017.

## Neu in 1.5.3 – aufgesattelte Wange an Ecken (fehler.md)
- **Fehler behoben:** Bei gewendelten Treppen (und Podestecken) lagen die Sattelwangen an der Ecke ineinander (beide Bretter bis zur Mittellinienecke, rechtwinklig abgeschnitten) und die Unterkante des oberen Bretts setzte tiefer an als die des unteren.
- Ecke jetzt **stumpf gestoßen ohne Durchdringung**: unteres Brett läuft bis zur Außenfläche des oberen durch (+ t/2/sin θ), oberes stößt an die Seitenfläche des unteren (Mittellinien-Schnittpunkt, auch wenn ein sehr kurzes Stück dazwischen wegfällt). Bei 90° exakt, bei schrägen Ecken (Raum-Modus) kleine Fuge statt Überlappung.
- **Unterkante gleich:** das obere Brett beginnt auf der Höhe der Unterkante des unteren Bretts (an dessen Stirnseite). Von dort läuft die Unterkante als Gerade (steilste zulässige) bis zur eigenen Ausgleichsgeraden → ggf. ein Knick in der Unterkante des oberen Bretts. Restbreite `sat_rest` bleibt überall eingehalten. Ist die Höhe für das obere Brett zu hoch, wird das untere Brett am Ende abgesenkt.
- Code: `stringers.rb` (`sattel`, neu `sat_bottom`, `sat_slope`). Test neu: `test/sattel_test.rb` (88 Fälle: Restbreite, Fuge Unterkante, Überlappung im Grundriss) – 0 Fehler; build/stringer/kite/cnc/fit ohne Fehler.

## Neu in 1.5.2 – Nuten der eingestemmten Wangen exakt (TCN)
- **Fehler behoben:** Die Ausfräsungen in den Wangen waren im TCN nur achsparallele Rechtecke (Umriss-Box der gedrehten Nut, Tritt- und Setzstufe getrennt) – passte nicht zur Ausstemmung.
- Jetzt: Nut = **exakte Ausstemmung** je Brett: Vereinigung der Querschnitte von Trittstufe (inkl. Unterschneidung) und Setzstufe, zusammenhängend zu einer Kontur (Treppenprofil). Im Wendelbereich treffen die Stufenkanten schräg auf die Wange → Kante verschiebt sich mit der Nuttiefe; die Nut deckt Fläche und Nutgrund ab (`Parts.cross_u`).
- Stufen, die nur über die Ecke laufen und ganz unter dem Brett liegen (Eckpfosten), bekommen keine Nut mehr.
- **Ausräumen:** neue Bahnen für beliebige Konturen (`Pockets.clearing_paths`): konzentrisch von innen nach außen, Abstand ½ Ø, letzte Bahn = Kontur im Abstand Fräserradius (Innenecken mit Fräserradius). Offene Enden (Brettende, Boden) werden um r + 0,5 mm überfahren. Bahnen werden in `parts.rb` im Brettsystem berechnet (`Part#pocket_paths`), beim Nesting mitgedreht (`Placement#paths`), `tcn.rb` schreibt sie je Bahn als eigenen Block (Tiefe = Einstand, Nutfräser).
- `cnc.rb` gibt `pocket_d` an `Parts.collect` weiter.
- Tests: neu `test/pk_check.rb` (240 Bretter: Bahn nie näher als r an der Nutkontur), `pk_dump.rb` + `pk_plot.py` + `pk_cov.py` (Abdeckung: kein Restmaterial außer Fräserradius in den Ecken), `tcnplot.py` (TCN-Datei plotten). build/stringer/kite/cnc/tcncheck ohne Fehler.

## Neu in 1.5.1 – Drachenstufen immer mittig auf der Ecke
- **Regel:** Jede Ecke einer gewendelten Treppe (L/U/dreiläufig, frei und Raum-Modus) liegt genau in der Mitte einer Stufe (Drachenstufe). Die beiden Kanten der Drachenstufe sind spiegelgleich zur Eckdiagonale (Innenecke → Außenecke).
- **Keine kleinen Haken:** Die Kanten der Drachenstufe treffen die Innenkante bei s_Ecke ∓ q. q ist entweder 0 (Spitze genau in der Innenecke = klassischer Drachen) oder mindestens 5 cm bzw. `min_inner`/2 (`Layout::KITE_HOOK_MIN`). Keine andere Stufe läuft über eine Ecke.
- Zuordnung s(w) je Wendelzone mit eigenen Stützpunkten bei w_Ecke ± a/2 (`Layout.kite_breakpoints`), Turtle-Ecken merken sich ihre Gehlinienmitte (`corners[:w]`). Die frühere Suche nach einem Versatz („Stufenkante nahe an Ecke“) entfällt.
- **U-Treppe:** Abstand der beiden Eckmitten auf der Gehlinie (lc + Auge) muss k·a sein → Gehlinienabstand wird innerhalb des Gehbereichs angepasst (`Layout.gl_for_corners`, Info „Gehlinie angepasst …“). In geraden Läufen wirkt der Gehlinienabstand nicht.
- **Raum-Modus** (`Fit::Room#kite_layout`): Freiheitsgrade Gehlinienabstand, Auftritt, Lage. Antritt+Austritt fest und nicht vereinbar → Antritt wird minimal verschoben (Warnung mit cm-Angabe). Schräge Austrittswand: Gehlinienlänge bis zum Austritt hängt von gl ab (`glast_lin`).
- **Behobener Fehler (Raum, L gewendelt):** Die Wendelung wurde doppelt gerechnet (zwei Eckwinkel statt einem) → Auftritte auf der Gehlinie still um ca. 5 cm zu klein. Jetzt exakt a.
- Wangen: Stützpunkte der geschwungenen Wange behalten die Kurvenknoten exakt; Kontrolle des Mindestabstands an der tatsächlich gezeichneten Unterkante. 3D: Zwischenpunkte gerader Bretter (Bodenschnitt) mit interpolierten Gehrungsnormalen (sonst Körper ungültig bei kurzen Brettern, z. B. am Treppenauge).
- Tests: neu `test/kite_test.rb` + `kite_check.rb` (3336 Fälle frei/Raum: Ecke mittig, symmetrisch, keine Haken, Auftritt = a) – 0 Fehler; build/stringer/fit/cnc/plan ohne Fehler.
- Hinweis: Bei schmalem Treppenauge liegen bei U-Treppen 2 Drachenhälften + (k−1) Stufen auf der Augenseite → innere Wange dort sehr steil.

## Neu in 1.5.0 – geschwungene Wange (variable Breite)
- Neuer Parameter `str_form` „Wangenform (Seitenansicht)“: `gerade` (wie 1.4, konstante Breite `str_h`) oder `kurve` (geschwungen). Bei `kurve` ist `str_h` ausgeblendet.
- Ober- und Unterkante sind je Laufabschnitt (zwischen Podesten bzw. Eckpfosten) **eine durchgehende, knickfreie Kurve** (monotone kubische Hermite-Interpolation, Fritsch–Carlson), stetig über die Gehrungsfugen der geraden Bretter.
- Oberkante: exakt `str_over` über jeder Stufenvorderkante; monoton steigend ⇒ jede Trittstufe liegt auf ganzer Tiefe mind. `str_over` unter der Oberkante. Gerade Läufe bleiben exakt gerade.
- Unterkante: durch die hinteren Enden der Einstände minus `str_under` (ungekürzt am Austritt, damit gerade Läufe gerade bleiben); monoton ⇒ an keiner Stelle einer Stufe weniger als `str_under`. Sicherheitsprüfung senkt sonst den Abschnitt ab.
- Podeste: weiter eigenes waagerechtes Brett mit Höhensprung am Podestende; Unterkante schließt an den vorigen Lauf an und läuft kubisch in die Waagerechte über.
- Bretter bleiben im Grundriss gerade. 3D: Band mit Stützpunkten alle 2 cm, Normalen zwischen den Gehrungen linear verteilt. CNC: Umriss als Polylinie, Teil an der Sehne der Oberkante ausgerichtet.
- Dialog-Info: „Wangenbreite (geschwungen) min – max“ bzw. „Wangenbreite (konstant)“.
- Code: `stringers.rb` (`curve_piece`, `pchip`, `curve_outline`, `curve_band`; `top`/`bot` interpolieren `b[:tp]`/`b[:bp]`), `builder.rb` (`band` mit optionalen Normalen), `params.rb`, `dialog.rb` (`wange_info`), `ui/dialog.html`.
- Tests: `stringer_test.rb` prüft beide Formen (Überstand exakt, Mindestabstand dicht abgetastet, Fugen stetig), `build_test.rb` und `cnc_test.rb` zusätzlich mit `kurve` – alle ohne Fehler.

## Neu in 1.4.0
### Raum einpassen ohne Luft
- Raum: Länge (ab hinterer Wand), Breite (entlang hinterer Wand), Wände links/rechts/hinten, **Innenwinkel hintere Wand–Seitenwand** links/rechts (45–135°), Spiel (Standard 1 cm).
- An jeder vorhandenen Wand liegt die Treppe genau mit dem Spiel an (Info „Luft zu den Wänden“, Warnung wenn > 0,5 cm). Grenzen ohne Wand = Platzgrenze (Abstand 0).
- gerade: zwischen zwei Wänden füllt die Laufbreite (bei schrägen Wänden konisch); sonst Laufbreite = Höchstwert an der vorhandenen Wand.
- L: Lauf 1 an der Außenwand, Lauf 2 an der hinteren Wand, Austritt an der Seitenwand bzw. Treppenlochkante.
- U: Laufbreite aus Raumbreite und **Treppenauge** (Vorgabe). Dreiläufig: Laufbreite vorgegeben, oder Treppenauge `eye_z` > 0 → Laufbreite folgt.
- **Antritt** `antritt_l`: 0 = frei (ideales Steigungsverhältnis, höchstens bis Raumende), > 0 = fest (Abstand vorderste Stufenkante – hintere Wand; Auftritt wird angepasst).
- Podesttreppen: Restmaß geht als Podestverlängerung ins Podest (Info). Wendeltreppen: bei festem Antritt+Austritt a = Gehlinienlänge/(n−1); Drachenstufen werden über die Bewertung gesucht.
- **Treppenloch** (Länge, Breite, Abstand linke/hintere Wand): Austritt an der passenden Lochkante (gerade: hintere, L: seitliche, U/dreiläufig: vordere), Kopffreiheitsprüfung (Mindestmaß einstellbar, Standard 200 cm; Deckendicke = `floor_t`), Decke um das Loch wird gezeichnet.
- Linksgewendelt: kanonisch als rechtsgewendelt gerechnet und gespiegelt.
- Wendeltreppe: wie bisher Kreis in den Raum (schräge Wände nicht berücksichtigt → Warnung).

### Bauart je Seite
- Bauart „Holztreppe“: links und rechts einzeln **Wange (eingestemmt) / aufgesattelte Wange / frei** (freitragend, Wandverankerung). Holm und Massiv unverändert.
- „Keine gebogenen Konstruktionen“: alle Wangen sind gerade Bretter; Wendeltreppen bekommen keine Wangen mehr (Info).

### Eingestemmte Wange
- Je Brett gerade Oberkante; überragt die Linie der Stufenvorderkanten um `str_over` – auf geraden Läufen exakt konstant, in Wendelbereichen mindestens (gerade Bretter!).
- Podeste: eigenes waagerechtes Brett (Podest + Überstand) → am Podestende Höhensprung zum nächsten Lauf (Eckpfosten/Kröpfung).
- **Konstante Brettbreite** für alle Wangen (`str_h`, rechtwinklig gemessen; 0 = automatisch kleinste passende). Unterkante mind. `str_under` unter jeder Stufenunterkante (hinteres Ende des Einstands), darf variieren. An Innenecken trägt der Eckpfosten die über die Ecke laufende Stufe.
- Wangenenden an Antritt/Austritt parallel zur (ggf. schrägen) Stufenlinie, Gehrung zwischen Brettern.
- **Alte gespeicherte Treppen**: `str_h` wird beim Laden auf automatisch gesetzt (früher lotrecht).

### Aufgesattelte Wange
- Unter den Stufen, um `sat_inset` eingerückt, Dicke `sat_t`; Sägezahn-Oberkante (Auflager, senkrechte Ausklinkung hinter Setzstufe/Unterschneidung); gerade Unterkante `sat_rest` rechtwinklig unter den inneren Ecken; an Podesten eigenes Brett. CNC-Export als Wangenteil `SA…/SI…` (ohne Nuten).

## Tests (ohne SketchUp, Ruby 3.x)
In `test/`: `su_mock.rb`, `build_test.rb` (alle Formen × Seiten-Kombinationen × frei/Raum mit schrägen Wänden, prüft geschlossene Körper), `plan_test.rb`, `fit_test.rb` (Raumfälle inkl. Winkel, Antritt fest, Treppenloch), `stringer_test.rb` (Überstand ≥ Vorgabe, konstante Breite, Mindestabstand unten), `kite_test.rb` (Drachenstufen), `cnc_test.rb`, `tcncheck.rb`, Plots `plotfit2.py`, `plotboards.rb/.py`, `dump3d.rb` + `render1.py`, Dialog-Screenshots `fmock2.rb` + `shotx.js` (Playwright).
Paket bauen: im Ordner `src`: `zip -r treppenbau.rbz jt_treppenbau.rb jt_treppenbau`

## Noch nicht in SketchUp/TpaCAD getestet
Alles wurde nur außerhalb von SketchUp geprüft. Erster echter Test steht aus.

## Offene Punkte / Ideen
- Geschwungene Wange: Rückmeldung zur Optik in Wendelbereichen (Krümmung der Unterkante an Innenecken kann stark sein)
- Test in SketchUp + TpaCAD, Rückmeldung Fräser-Ø und Nutseite der Wangen
- Gemischte Treppe (Podest + Wendelstufen) fehlt
- Wangenenden an schräger Austrittswand: im Grundriss schräg, im CNC-Teil rechtwinklig (Gehrung von Hand)
- Sattelwangen an Ecken stumpf gestoßen (keine Gehrung); Unterkante des oberen Bretts kann an der Ecke einen Knick haben
- Raum: Treppenloch nur rechteckig/achsparallel; dreiläufig mit nur einer Wand nutzt die Raumgrenze als Anschlag
- Neue Treppe wird im Ursprung eingefügt (Raum-Modus: Ursprung = vordere linke Raumecke)
