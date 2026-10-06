# Übergabe: SketchUp-Plugin „Treppenbau“ (Stand 2.9.0, 06.10.2026 – Branch `claude/gelaender-pfosten-e1r6fs`, PR #5 gegen `main`)

## Was es ist
SketchUp-Erweiterung (Ruby, ab SU 2017) für parametrische Treppen mit CNC-Export nach TCN (TpaCAD), angelehnt an Jürgens Plugin **dxf4tcn**.

## Dateien in diesem Ordner (E:\sketchup-treppe)
- `treppenbau_2.8.0.rbz` – **Version 2.8.0** (Branch `drachenstufe`: Drachenstufe außermittig, Schenkel ≥ 2 cm)
- `treppenbau_2.7.1.rbz` – Version 2.7.1 (Stand `main`, enthält 2.7.0 + Commit „schräge wangen“); `treppenbau_2.7.0.rbz` = 2.7.0 vor diesem Commit, `treppenbau_2.6.0.rbz` = 2.6.0 (2.5.0, 2.4.0 und 2.3.0 nur noch in der Git-Historie; ab 2.3.0 Versionsnummer im Dateinamen; `_9` = 2.0.0, `_8` = 1.5.3, `_1` = 1.1.0 … `_4` = 1.4.0, `_5` = 1.5.0, `_6` = 1.5.1, `_7` = 1.5.2)
- `src/` + `test/` – **Arbeitskopie** der Quellen (Stand 2.7.1, `main`), wird vom Entwickler-Loader direkt geladen
- `jt_aa_treppenbau_dev.rb` – Entwickler-Loader (in den SketchUp-Plugins-Ordner kopieren, lädt aus `E:\sketchup-treppe\src`)
- `treppenbau_quellen_tests_9.zip` – Quellcode + Tests Stand 2.0.0 (`_8` = 1.5.3, `_7` = 1.5.2, `_6` = 1.5.1, `_5` = 1.5.0, ohne Nummer = 1.4.0)
- `_to_delete/` – Debug-Plots, kann gelöscht werden
- `tcn_test/` – Testprogramme Seitenaggregat (A–D, `gen_tests.rb`, `check_tests.py`, README) und Beispiel-Export `E_beispiel_l_wendel/`
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
| `transfer.rb` | **neu 2.6.0**: Umschalten Raum ↔ Parameter ohne Änderung der Treppe (`Transfer.switch`, Planvergleich `compare`) |
| `stringers.rb` | **neu**: Wangen aus geraden Brettern (eingestemmt + aufgesattelt), gemeinsam für 3D und CNC |
| `builder.rb` | SketchUp-Geometrie (Stufen, Setzstufen, Wangen, Sattelwangen, Holm, Massiv, Geländer, Spindel, Gehlinie, Decke/Treppenloch, Raumumriss) |
| `dialog.rb` + `ui/dialog.html` | Parameterdialog (HtmlDialog) mit SVG-Grundriss (Raum, Wände, Treppenloch), Live-Update |
| `wange3d.rb` | **neu 2.7.0**: aufgesattelte Wangen als 3D-Bearbeitung, je Wange ein TCN-Programm (Ausräumen, Seitenaggregat, Markierungen, Wenden) |
| `parts.rb` | Zerlegung in flache Frästeile (mm), Wangen abgewickelt mit Nuten (exakte Ausstemmung), Sattelwangen; Modul `Pockets` (Vereinigung, Ausräumbahnen) |
| `nesting.rb` | Raster-Nesting mit Bitmasken je Zeile, 0/180° (Faser) oder 0/90/180/270° |
| `tcn.rb` | TCN-Writer (Kopf identisch dxf4tcn), Gravur r0/r1, Nuten (Bahnen aus `parts.rb`), Außenkontur zuletzt |
| `cnc.rb` + `cnc_dialog.rb` + `ui/cnc.html` | CNC-Dialog, Plattenvorschau, Export TCN je Platte + Teileliste.csv |

## Kernprinzip Geometrie
Grundriss = drei Polylinien in Laufrichtung: `inner`, `walk` (Gehlinie), `outer`. Stufenkante bei Gehlinienposition w: von `inner.at(s(w))` durch `walk.at(w)` bis Schnitt mit `outer`. `s(w)` stückweise linear → steuert Verziehen. Podeste: parallel verschobene Linien (`translated`). Wendeltreppen: Bögen, radial.

## Version 2.11.0 – überlange Wangen: zwei Läufe, dazwischen drehen
- **Maschine:** Verfahrweg X 3200 mm, TpaCAD nimmt keine TCN mit DL > 3200 mm an, Überstand nur nach rechts. Strategie (Doc „Lange Wangen auf 3-m-CNC – Wendestrategie“): Lauf A mit Ende A am linken X-Anschlag und Kante 1 am vorderen Y-Anschlag; Wange 180° in der Ebene drehen; Lauf B mit Ende B am selben Anschlag und Kante 1 am hinteren Y-Anschlag. Die Rohbreite kürzt sich heraus, nur die Rohlänge muss stimmen.
- **Neues Modul `lauf.rb`** (ohne SketchUp-API): allgemeine Programmform (Bahnen, Bohrungen, Hilfsflächen), `Lauf.split` teilt bei x_T in der Überlappungszone mit größtem Abstand zu Bohrungen, Gravur, Markierungen und Schrägen; Außenkonturen werden geteilt und je `long_overlap` überlappend gefräst, Nuten nur, wenn sie durchlaufen (Tritt- + Setzstufen). Lauf B: x' = L − x, y' = W − y, Hilfsflächen starr mitgedreht. Haltestege (`tab_n`/`tab_w`/`tab_h`) im zuerst gefrästen Lauf jeder Seite.
- `Tcn.build_job` läuft jetzt über `Lauf.from_job` + `Tcn.build_prog` (Ausgabe bytegleich wie 2.10.0).
- **Eingestemmte Wangen**, die nicht auf die Rohplatte passen, bekommen einen eigenen Rohling (`blank_margin` ringsum) statt „nicht platziert“: `…_Wange_WA1.tcn` bzw. `…_Wange_WA1_A.tcn` + `_B.tcn`.
- **Aufgesattelte Wangen** über 3200 mm: `…_Seite1_A/B.tcn` (mit Wenden auch `Seite2_A/B`, Reihenfolge = alphabetisch). Überlang wird nicht formatiert (`Job#long`, Bezug Rohkanten).
- Einrichtblatt in `…_Wangen_Nacharbeit.txt` (Rohlänge, Teilung, Anschläge, Reihenfolge, Haltestege); Vorschau zeigt die Teilung.
- Neue CNC-Optionen: `long_mode` (`drehen` | `aus` = Verhalten wie 2.10.0), `mach_l` 3200, `long_overlap` 10, `tab_n` 3, `tab_w` 20, `tab_h` 4.
- **Bezug Lauf B:** über das Feld in TpaCAD – Lauf A im Feld N1 (vorne), Lauf B im Feld N (hinten), steht in der Kommentarzeile und im Einrichtblatt (DH = Rohbreite, y' = W − y).
- **TpaCAD ungeprüft:** ob das Feld in der TCN gespeichert werden kann (derzeit nur Hinweis); Haltestege als eigene Bahnstücke mit geringerer Tiefe.
- Tests: neu `test/lauf_test.rb` (4 Formen × Seitenkombinationen × Wenden × fräsen/markieren × 2 Höhen).

## Version 2.10.0 (Branch `claude/gelaenderstaebe-rund-quadratisch-efegi4`) – Geländerstäbe rund oder quadratisch, Bohrungen im TCN
- **Neue Parameter:** `bal_shape` „Stabform“ (`quadrat` | `rund`, Standard `quadrat` → alte Treppen unverändert), `bal_d` heißt jetzt „Stab: Kantenlänge“ (nur quadratisch), neu `bal_dia` „Stab: Durchmesser“ (2,5 cm, nur rund). `Params.bar_size(p)` liefert Form und Maß; Stab-Hash in `Railing` hat `shape:`.
- **3D:** runde Stäbe als 16-Eck (`Builder#circle`), quadratische wie bisher.
- **Bohrung Ø = Durchmesser bzw. Kantenlänge** (quadratische Stäbe brauchen am Ende einen runden Zapfen). Runde Stäbe sind kein Plattenteil mehr, Hinweis mit Anzahl, Ø und Längen (Zuschnitt vom Rundstab).
- **TCN (`tcn.rb#build`):** Bohrungen werden beim Verschachteln mitgedreht (`Placement#drills`).
  - Trittstufen (aufgesattelte Wange, frei, Holm): Bohrung von oben `W#81` auf Seite 1 vor der Außenkontur.
  - Eingestemmte Wange: Bohrung in die Oberkante, in der Plattenebene schräg zur Kante. CNC-Option `drill_wange`: `bohren` = Bohraggregat nach der Außenkontur, je Bohrung eine Hilfsfläche `GSIDE#7…` (Konvention wie `Wange3d#aggregate`, Anfahrabstand `drill_clear`); `markieren` = Gravur der Bohrachse von der Kante bis zur Tiefe (Handbohrung). Hinweis im Dialog: vor der Oberkante muss Platz für das Aggregat sein.
  - Neue CNC-Optionen `drill_tool` (von oben), `hdrill_tool` (Aggregat), jeweils 0 = Werkzeug nach Durchmesser (`#205` entfällt).
- **Plattenvorschau:** Bohrungen rot (Kreis Ø; bei Wangen zusätzlich die Bohrachse).
- **TpaCAD ungeprüft:** Bohrmakro `W#81{ ::WT2 … #1002=Ø }W`, Bohrung auf Hilfsflächen, Platzbedarf des Aggregats auf der verschachtelten Platte.
- Tests: neu `test/bohrung_test.rb` (4 Formen × 3 Seitenkombinationen × rund/quadratisch × bohren/markieren: Ø, Anzahl der W#81-Blöcke und Hilfsflächen, Bohrung im Teil bzw. Ansatz an der Wangenkante); railing/cnc/tcncheck/build (auch mit runden Stäben)/sattel_cnc/reload ohne Fehler.

## Version 2.9.0 (Branch `claude/gelaender-pfosten-e1r6fs`, PR #5) – Geländer neu, Wangen stumpf gestoßen (erster Entwurf)
- **Wangenstöße ohne Gehrung** (`Stringers.butt_joints`/`corner_joint`): L-förmig läuft die von unten kommende Wange durch, die folgende ist um die Wangendicke gekürzt; U-förmig laufen die Wangen der Läufe durch, der Querverbinder ist um beide Dicken gekürzt. Gilt für eingestemmte und aufgesattelte Wangen (Parameter `sat_joint` entfällt).
- **Wangen als Körper aus zwei Flächenumrissen** (`Stringers.wange_faces` + `Builder#lprism`): Ober-/Unterseite stehen rechtwinklig zur Brettfläche, keine verwundenen Flächen – auch das geschwungene Mittelstück ist ohne 5-Achs-Bearbeitung fräsbar.
- **Geländer** (`railing.rb`, ohne SketchUp-API): Pfosten am Antritt, am Austritt und an jedem Laufwechsel (Ecke bzw. Vorderkante eines geraden Zwischenpodests), Handlauf von Pfosten zu Pfosten, Stäbe dazwischen (lichter Abstand ≤ `bal_gap`).
  - eingestemmte Wange: Stäbe lotrecht in die Wangenoberkante eingelassen (`bal_depth`), Bohrungen am Wangenteil (`Part#drills`, Winkel in der Teilebene = schräg zur Kante);
  - aufgesattelt/frei/Holm/Massiv: Stäbe auf den Stufen, je Stufe gleiche Felder, Stab in Feldmitte, Mindestabstand `bal_edge` zu beiden Stufenkanten (Vorrang vor `bal_gap`, sonst Warnung); Bohrungen an den Trittstufen.
- **Pfosten als Zwischenstücke** (`Stringers.post_joints`): auf Geländerseiten enden die eingestemmten Wangen rechtwinklig an den Pfostenflächen; Lage aus `Railing.post_positions` (gemeinsame Quelle). Ecken ohne Pfosten bleiben stumpf gestoßen.
- **Handlauf** rechteckig von Pfosten zu Pfosten: Breite = Wangendicke (`str_t` bzw. `sat_t`, ohne Wange `rail_d`), Höhe `rail_hh` (8 cm), Oberkante `rail_h` über den Stufenkanten. Wangenform „gerade“: je Feld die niedrigste Gerade über allen Stufenkanten; „geschwungen“: knickfreie Kurve (pchip) – CNC-Teil ist dann eine aus dem Vollen gefräste Platte mit gebogenem Umriss (Dicke = Handlaufbreite). Im Grundriss gebogene Handläufe (Wendeltreppe) werden nicht exportiert.
- Neue Parameter: `rail_hh` (8 cm), `newel_s` (9 cm), `bal_d` (2,5 cm), `bal_gap` (12 cm), `bal_edge` (3 cm), `bal_depth` (3 cm); `post_every`/`post_s` entfallen.
- Tests: `test/railing_test.rb` (neu), `stringer_test`/`sattel_*` auf stumpfe Stöße umgestellt.
- Offen: ~~Bohrungen noch nicht im TCN-Export/Plattenvorschau~~ (2.10.0); Stufen am Pfosten nicht ausgeklinkt; U mit Treppenauge innen zwei Eckpfosten; aufgesattelte Wange, dreiläufig mit Podest und Setzstufen: am inneren U-Stoß ragt das durchlaufende Podestbrett in die letzte Stufe des Querlaufs (`sattel_stufen_test`, 4 Fälle).

## Version 2.8.0 (Branch `drachenstufe`) – Drachenstufe darf außermittig liegen, Schenkel innen ≥ 2 cm
Vorgabe Jürgen (05.10.2026): Die Drachenstufe muss nicht halb/halb auf der Ecke liegen, aber an der Innenseite muss der kleinere Schenkel mindestens 2 cm lang sein.
- **Regel neu (`geometry.rb`):** In jeder Ecke liegt eine Drachenstufe, die Ecke liegt irgendwo innerhalb der Stufe (Anteil f des Auftritts auf der Gehlinie vor der Ecke). Die Kanten der Drachenstufe treffen die Innenkante bei s_Ecke − Q·f und s_Ecke + Q·(1 − f), die Innenseite wird also im selben Verhältnis geteilt wie die Gehlinie. Beide Schenkel innen und außen ≥ `KITE_HOOK_MIN` = 2 cm (vorher 5 cm bzw. `min_inner`/2, oder 0 = Spitze genau in der Innenecke).
  - Mittige Ecke (f = ½): Q wie bisher (bevorzugt `KITE_HOOK_PREF` = 5 cm bzw. `min_inner`/2 je Schenkel). Nur wo bisher Q = 0 herauskam (Spitze in der Innenecke, Innenauftritt der Drachenstufe 0), gibt es jetzt Schenkel ≥ 2 cm.
  - Außermittige Ecke: Q zwischen 2 cm/min(f, 1 − f) und dem natürlichen Wert so, dass der schmalste Innenauftritt der Wendelung möglichst breit wird (`kite_min_inner`).
  - `kite_breakpoints` nimmt die tatsächlichen Stufenkanten aus `lines_w` (`kite_edges`) statt w_Ecke ± a/2; `finish_flights` hält die ganze Drachenstufe in der Wendelzone (`reach`). Prüfung `kite_errors` ohne „mittig/symmetrisch“, Info „Drachenstufe(n) (Lage der Ecke im Auftritt): Nr. 6 (Ecke bei 28 %)“ (bei mittigen Ecken wie bisher).
- **Neue Parameter (nur „aus Parametern“):** `kite_pos` „Drachenstufe: Lage der Ecke im Auftritt“ (%, 0 = automatisch/mittig; U-Treppe: erste Ecke, die zweite folgt aus Auge und Gehlinie), `kite_pos2` (dreiläufig, zweite Ecke). Standard 0 → L- und dreiläufige Treppen unverändert mittig.
- **Gehlinie halten (`KITE_KEEP_GL = true`):** Bisher wurde die Gehlinie (U-Treppe; Raum-Modus) verschoben bzw. der Antritt verschoben, nur damit die Ecken mittig liegen. Jetzt bleibt die Gehlinie und die Ecke liegt außermittig, wenn mittig nicht ohne Verschieben geht:
  - U-Treppe frei: `kite_pair_frac` legt beide Ecken möglichst weit von den Stufenkanten (mind. 25 %). Wird die Drachenstufe dabei unsauber oder ein Innenauftritt ≤ 0, wie bisher mit angepasster Gehlinie (`build_winder`, Rückfall).
  - Raum (`fit.rb#kite_layout`): Reihenfolge mittig ohne Gehlinienänderung → außermittig mit Ziel-Gehlinie (Ecke mind. `KITE_F_AUTO` = 25 % vom Stufenrand) → mittig mit angepasster Gehlinie → Antritt verschieben (wie bisher). Rückfall auf mittig, wenn außermittig unsauber (`Room#build`). Die Meldung „Drachenstufen lassen sich nicht mittig auf die Ecken legen“ entfällt in den meisten Fällen.
  - Zum Umschalten auf das alte Verhalten (Gehlinie anpassen) genügt `KITE_KEEP_GL = false`.
- **Umschalten Raum ↔ Parameter (`transfer.rb`):** übernimmt `kite_pos`/`kite_pos2` (U: `m1` aus der Wendelmitte), beide werden beim Zurückschalten wieder automatisch, wenn sich nichts ändert.
- **Aufgesattelte Wange (`stringers.rb`):** zwei Folgefehler bei kurzen Schenkeln dicht an der Ecke behoben: (1) Stumpfer Stoß: Ausklinkung lag auf einer Fläche hinter dem Brettende → Flächenumriss fehlte (senkrechter Schnitt, Durchdringung); jetzt fällt der Punkt auf die Ausklinkung. (2) Restbreite: Anschluss der Unterkante an der Ecke (`sat_slope`) prüft jetzt auch die vordere Lage der Ausklinkung (`corners_r`, `r[:cr]`), wo die Unterkante fällt.
- **Tests:** `kite_check.rb` prüft Schenkel ≥ 2 cm innen/außen, Teilung innen = Gehlinie, mittig nur bei L/dreiläufig frei ohne Vorgabe; `kite_test.rb` zusätzlich 160 Fälle mit `kite_pos`/`kite_pos2` (Lage exakt), Fälle mit Innenauftritt ≤ 0 (U ohne Auge) werden gezählt statt geprüft. `switch_test.rb` + 4 freie, 2 Raum-Fälle mit außermittiger Drachenstufe.

## Version 2.7.1 (treppenbau_2.7.1.rbz, 05.10.2026) – Fräser Außenkontur automatisch, Wangen-Ablauf geändert
Inhalt = Commit `af8b154` „schräge wangen“ (Jürgen, per PR #2 in `main` gemergt) + Versionsnummer. Die .rbz 2.7.0 enthielt diesen Stand noch nicht.
- **Fräser Außenkonturen (`cnc.rb`):** neue Werkzeugliste `OUTER_TOOLS` = [Name, Nr, Ø, max. Schnitttiefe]: **1300** Ø 18,27 / 54 mm, **1004** Ø 20 / 107 mm, **2200** Ø 8,03 / 23 mm (1000 entfällt). `tool_outer = 0` = **automatisch je Materialstärke** (`Cnc.outer_tool`): 1300, wenn Stärke + Durchfräsen ≤ 54 mm, sonst 1004; 2200 nur bei expliziter Auswahl. Fräser wird je Plattenstärke bzw. Wangendicke gewählt (`SheetInfo#tool`), Teileabstand aus dessen Ø, Warnung bei Frästiefe > max. Schnitttiefe (`depth_warning`), Übersicht zeigt je Stärke „Außenkontur … mm – Fräser … – Ø/Tiefe“.
- **CNC-Dialog:** Gruppe „Aussenkonturen“, Auswahl „Automatisch (1300, bei zu großer Stärke 1004)“ (Ø-Feld dann gesperrt). Fräser **nicht mehr mit dxf4tcn geteilt** (eigene Einstellung, Ø je Werkzeug unter `tool_dia_<nr>`); Durchfräsen darf negativ sein (nie ganz durch).
- **TCN (`tcn.rb`):** Gravur mit Werkzeug/Tiefe direkt im Block, **keine r0/r1-Variablen** mehr (VAR-Block leer) – gilt für Platten und Wangen.
- **Aufgesattelte Wangen (`wange3d.rb`, `tcn.rb#write_job`):** **kein Ausräumen aus dem Vollen** mehr (`clearing` bleibt ungenutzt im Code). Seite 1: Markierungen, **Außenkontur in Stufen** (neue Option `sat_zstep` „Außenkontur: Schrittweite je Umlauf“, Standard 20 mm, 0 = ein Umlauf; letzter Umlauf Dicke + Durchfräsen), **danach** Schrägen mit dem Seitenaggregat.
  - **Mit Wenden:** Rohteil je Seite `FORMAT_OFF` = 5 mm größer; Seite 1 beginnt mit **Formatieren** auf das Rohlingsmaß (Bezugskanten für Seite 2), Außenkontur auf Seite 1 nur Stufenseite + Enden (offener Zug), der **Rücken bleibt stehen**; Seite 2: Rücken fräsen, dann Schrägen. Ohne erkennbaren Rücken: Seite 1 bis Reststärke `REST_T` = 10 mm, Seite 2 durch. Teileliste/Warnung „Rohling größer als Rohplatte“ mit Rohteilmaß (`Job#raw_blank`), Hinweise in `…_Wangen_Nacharbeit.txt`.
  - ⚠ Auf Seite 2 (und ohne Wenden auf Seite 1) laufen die Schrägen **nach** der Außenkontur → das Teil muss beim Aggregatfräsen vom Vakuum gehalten werden; in TpaCAD prüfen. `tcn_test/README.md` und `E_beispiel_l_wendel/` beschreiben noch den alten Ablauf (Ausräumen, Kontur zuletzt).
- **Verifikation 05.10.2026 (Ruby 3.3, ohne SketchUp):** build_test 31067 Gruppen 0 Fehler, sattel_build_test 2464 Körper 0 Fehler, sattel_cnc_test 120 Fälle / 784 Wangen / 835 Schrägen 0 Fehler, sattel_test 176 / stringer / kite (3336) / antritt (73) / austritt (144) / box (120) / fit / pk_check (240) / tcncheck / reload_test – alle 0 Fehler; cnc_test Export aller Formen ok; Export L-Wendel mit/ohne Wenden geprüft (Formatieren, Teilkontur Seite 1/Rücken Seite 2, Zustellung 20/40/60/61 mm, Fräser 1004 bei 60 mm Wange); CNC-Dialog per Playwright-Mock ohne JS-Fehler (Automatisch, Ø gesperrt). Hinweis: `cnc_test`/`plan_test` brauchen einen Ordner `test/out`, `reload_test` UTF-8-Locale (`LANG=C.UTF-8`).

## Version 2.7.0 (treppenbau_2.7.0.rbz, seit PR #1/#2 in `main`) – aufgesattelte Wangen: schräge Stöße, 3D-CNC (fehler.md Nr. 7)
- **Fehler:** Im Wendelbereich (und bei konischen Läufen / schräger Antrittswand) lagen Stufe und aufgesattelte Wange ineinander: die senkrechte Ausklinkung saß dort, wo die Stufenkante die **Brettmitte** kreuzt; die Kante läuft aber schräg über das Brett (Versatz t/2·cot α).
- **Lösung nach Standard:** Wange wird ausgeklinkt (Stufe unverändert), die Stoßfläche folgt der Stufenkante **schräg durch die Brettdicke**. Gleiches für schräge Brettenden (Antritt/Austritt) und Ecken.
- **Geometrie (`stringers.rb#sattel`):** je Brett zwei Flächenumrisse (`sb[:faces]` bei −t/2 / +t/2 entlang `Geo.right(dir)`, gleiche Punktzahl, `sb[:ntop]` = Punkte der Oberkante); Lage jeder Ausklinkung/jedes Endes auf beiden Flächen (`sat_face_polys`, `line_cross`, `board_cross`). Restbreite an der ungünstigeren (hinteren) Ecke (`face_hit`). Sonderfälle: Ausklinkung im Bereich eines schrägen Brettendes (Brett endet dort), Eckstück am Podest, das in die vorige Stufe/Setzstufe ragt (Hindernisse = Tritt-/Setzstufen-Grundrisse, `face_intervals`, Anfangskante wird verschoben) – vorher Durchdringung bis 2 cm bei Podest-Innenecken mit Setzstufen.
- **Neuer Parameter `sat_joint`** „Ecken der aufgesattelten Wange“: `gehrung` (Standard, Stoß auf der Winkelhalbierenden) / `stumpf` (wie bisher, jetzt mit schrägen, passgenauen Enden). Ältere Treppen bekommen beim Laden „Gehrung“.
- **3D (`builder.rb#lprism`):** Brett als Körper aus den zwei Umrissen (Seitenflächen eben bzw. trianguliert, entartete Fläche erlaubt).
- **CNC (`wange3d.rb`, `tcn.rb#write_job`, `cnc.rb`):** aufgesattelte Wangen mit Flächenumrissen werden **nicht mehr verschachtelt**, sondern je Wange ein Programm aus rechteckigem Rohling (`…_Wange_SA1_Seite1.tcn`, ggf. `_Seite2`). Ablauf: Gravur/Markierungen → **Auflager aus dem Vollen ausräumen** (alles oberhalb der Auflager und hinter den Brettenden, Zeilen parallel zu den Auflagern, kein loses Abfallstück) → **Schrägen mit dem Seitenaggregat** (waagerechte Spindel in Richtung der Treppen-Senkrechten, C-Achse; je Wand eine Hilfsfläche `GEO/GSIDE#7…`, Bahnen parallel zur Wand außen beginnend, max. 1 mm unter die Unterseite, Zustellung entlang der Achse) → **Außenkontur zuletzt** (auf der zuletzt bearbeiteten Seite).
  - Optionen im CNC-Dialog: „Schräge Stöße“ = *Aggregat fräsen* / *nur markieren*; „Wenden“ an/aus (Seite 2 = um die Y-Achse gewendet, Ausrichtung an den Rohlingskanten); Werkzeug 15001, Ø 16, nutzbare Länge 167, Freiraum 5, Zustellung 50, Rohling-Zugabe 15 mm.
  - Seite 1 oben = Fläche mit dem meisten von oben erreichbaren Keil; Schrägen mit umgekehrter Neigung → Seite 2 (Wenden) oder Markierung „unten bis hier“.
  - Reichweite: Fläche knapp über dem Material (z oben + Freiraum), Spitze höchstens bis Länge − Freiraum → bei 18,3 cm Steigung bleiben unten ca. 21 mm → **Markierung** (Gravur r0/r1, auf das Material beschnitten) + Querstrich an der Grenze; hohe Brettenden (Gehrung innen) entsprechend mehr. Liste in `…_Wangen_Nacharbeit.txt`, Kurzfassung in den Hinweisen; Rohling in der Teileliste; Warnung, wenn Rohling größer als Rohplatte.
  - Vorschau im Dialog: je Wange Rohling + Umriss, Schrägen grün (Seite 1), blau (Seite 2), rot (markiert).
- **TpaCAD noch ungeprüft:** Richtung von Fläche 5 / Hilfsflächen (rechtshändig X × Y = Normale), `GEO`-Block, Reihenfolge (WS) – siehe `tcn_test/README.md`; Ursprung der Hilfsflächen liegt teils außerhalb des Rohlings.
- Tests neu: `sattel_stufen_test.rb` (352 Fälle: gerade/kurve × Gehrung/stumpf, alle Nicht-Wendelformen, frei/Raum mit schrägen Wänden, mit/ohne Setzstufen: keine Durchdringung Wange ↔ Tritt-/Setzstufe an 5 Schnitten über die Dicke, alle Bretter mit Flächenumrissen; Aufruf je Form/Ecke `ruby sattel_stufen_test.rb gerade gehrung`), `sattel_build_test.rb` (2464 Körper geschlossen), `sattel_cnc_test.rb` (alle Formen × fräsen/markieren × wenden: Ausräumen nie näher als r an der Wange, Aggregat nie im Material, Keil entfernt, Tiefe ≤ Werkzeuglänge, Export). `sattel_test.rb` prüft Überlappung jetzt mit den Flächenumrissen. build/stringer/fit/box/antritt/austritt/switch/kite/pk_check/reload unverändert ohne Fehler; cnc_test: SI1 wird jetzt als eigenes Programm exportiert statt „passt nicht“. Vorschau-Mock `cmock_sattel.rb`, Plot `dumpjob.rb` + `plotjob.py`.
- **Offen:** Anfahrt der Schrägen von unten (hohe Brettenden), eingestemmte Wangen (Gehrungen, schräge Enden, Nutwände im Wendelbereich) noch nicht umgestellt; Test in TpaCAD.

## Version 2.6.0 (treppenbau_2.6.0.rbz) – Umschalten Raum ↔ Parameter ohne Änderung (fehler.md Nr. 6)
- Beim Umschalten von „Ermittlung“ bleibt die Treppe gleich; danach Feinjustierung im anderen Modus möglich. Dialog ruft `switch_mode` → `Transfer.switch(p, mode)` → `TB.onSwitched` (Werte, Meldung in der Statuszeile: „Treppe unverändert“ bzw. Abweichung in cm).
- **Raum → Parameter:** übernimmt Steigungen, Auftritt (4 Nachkommastellen), Laufbreite, Gehlinie, Steigungen je Lauf (r1/r2), Lage der Wendelung (m1/m2 aus den Drachenstufen), Podestlänge (gerade mit Podest), Podestverlängerungen, Austrittspodest; Grundmaß (`total_w/total_l`) wird 0. Wendeltreppe: nur `D_out`.
- **Parameter → Raum:** Raumlänge/-breite aus dem Umriss inkl. Wangen + Spiel an vorhandenen Wänden, Wandwinkel 90°, **fester Antritt**, `eye_z` = 0. Treppenloch: vorhandenes wird an den Austritt gelegt (Maße soweit möglich behalten); bei Austrittspodest bzw. U/dreiläufig mit Podestverlängerung nach der letzten Wendung wird automatisch eins angelegt (`loch_gap` = Austrittspodest).
- Werte, die vorher „automatisch“ (0) waren, bleiben automatisch, wenn sich die Treppe dadurch nicht ändert (`Transfer.relax`, prüft jeweils per Planvergleich). Wird ohne Änderung zurückgeschaltet, stellt der Dialog die vorherigen Werte exakt wieder her (`TB.lastSwitch`).
- **Neue Parameter (nur „aus Parametern“):** `pod1_vor`, `pod1_nach` (L/U/dreiläufig mit Podest), `pod2_vor`, `pod2_nach` (dreiläufig) = Podestverlängerung vor/nach der Wendung; `exit_land` = Austrittspodest hinter der letzten Steigung (Gegenstück zu `loch_gap`). Standard 0 → alte Treppen unverändert.
- **SketchUp:** Beim Übernehmen nach einem Moduswechsel wird die Instanz so verschoben, dass die Treppe im Modell stehen bleibt (`StairDialog#keep_position`, Bezug: Innenpunkt der Antrittskante; Raum-Ursprung = vordere linke Raumecke, freier Ursprung = Antritt).
- **Grenze:** schräge Wände (≠ 90°) lassen sich ohne Raum nicht nachbilden → Meldung mit Abweichung. Dreiläufig mit Podest: beim Einpassen werden die Verlängerungen zwischen den Wendungen gleichmäßig verteilt (sonst Meldung).
- **Wangen-Korrektur (`stringers.rb#merge_short`):** sehr kurze Bretter (< 1,5 · Wangendicke + 1 cm, z. B. kleine Podestverlängerung hinter einer Ecke) werden mit dem Brett in gleicher Flucht vereinigt – vorher überschnitten sich Gehrung und Brettende (Körper nicht geschlossen; trat auch beim Einpassen mit Treppenloch auf). Folge: dreiläufig mit Podest im Raum-Test Wangenbreite 42,5 → 40,0 cm.
- Test neu: `test/switch_test.rb` (492 Fälle: alle Formen, rechts/links, 3 Seitenkombinationen; Raum → Parameter → zurück und Parameter (inkl. Grundmaß, Podestverlängerungen, Austrittspodest, ohne rechte Wand, mit Treppenloch) → Raum → zurück; Vergleich aller Stufenlinien und Umrisse, Toleranz 0,01 cm) – 0 Fehler. `build_test.rb` zusätzlich mit Podestverlängerungen + Austrittspodest – 31067 Gruppen, 0 Fehler. fit/austritt/antritt/box/kite/sattel/cnc/pk_check/reload unverändert; stringer_test nur obige Wangenbreite.
- Dialog-Ablauf mit Playwright-Mock geprüft (Umschalten, Werte, Statusmeldung, Rückschalten stellt Werte her).

## Version 2.5.0 (treppenbau_2.5.0.rbz) – Austrittspodest am Treppenloch (fehler.md Nr. 5)
- Neuer Parameter `loch_gap` „Austritt: Abstand vom Rand des Treppenlochs (Austrittspodest)“ (Raum-Modus, nur mit Treppenloch, nicht Wendeltreppe). 0 = wie bisher (Austrittskante an der Lochkante).
- > 0: die letzte Steigung endet um `loch_gap` vor der Lochkante (rechtwinklig zur Kante, im Loch); dazwischen ein **Austrittspodest auf Höhe H** bis an die Lochkante. Lochkante wie bisher: gerade = hintere, L = seitliche, U/dreiläufig = vordere Kante. Muss ≥ 10 cm kleiner als das Loch in dieser Richtung sein (sonst Meldung).
- Umsetzung: `Room#exit_line(full)` (verschoben bzw. Lochkante), Einpassen/Suche gegen die verschobene Kante; danach hängt `exit_landing` (bzw. in `build_straight` direkt) eine Podestzone an (`Turtle#extend_to_cut` – verlängert gestaffelte Linienenden einzeln, nötig bei schrägen Wänden). Plan: zusätzliche Trittfläche `kinds[-1] = :landing`, `lines_w` hat dann **n + 1** Einträge.
- `Plan#treads` = `lines_w.size − 1`, neu `Plan#nlines`; `nose_z` auf H begrenzt → Profile (Wangen, Geländer, Holm, Gehlinie) nutzen `(0...plan.nlines)` statt `plan.n`. Dadurch bekommt das Podest automatisch Platte („Podest n“), Setzstufe darunter, waagerechtes Wangenbrett (eingestemmt/aufgesattelt), Geländer, Massiv-/Holmausführung und CNC-Teil.
- Wendelzone neben einem Podest darf bis an das Podest reichen (`finish_flights`: Grenze = Podestanfang statt Zonenmitte; betrifft nur Kombination Wendel + Austrittspodest).
- Kopffreiheit nur über echten Stufen (`0...n−1`); Info „Austritt an: … cm vor der Kante des Treppenlochs“, „Austrittspodest (auf Deckenhöhe): Tiefe/Breite“; „Lauflänge auf der Gehlinie“ ohne Podest.
- Test neu: `test/austritt_test.rb` (144 Fälle: alle Nicht-Wendelformen, rechts/links, Abstand 0/15/40, fester Antritt, schräge Wand, 5 Bauarten): Austrittskante exakt `loch_gap` vor der Lochkante, Podestende auf der Lochkante, Podest-Oberkante = H, alle Körper geschlossen – 0 Fehler. Ohne `loch_gap` alle bisherigen Tests unverändert (build/fit/antritt/box/kite/stringer/sattel/cnc/pk_check/reload identische Ausgabe).

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

## Neu in 1.5.1 – Drachenstufen immer mittig auf der Ecke (ab 2.8.0 gelockert, siehe oben)
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
In `test/` (vorher `mkdir out`, Locale UTF-8): `su_mock.rb`, `sattel_stufen_test.rb`, `sattel_build_test.rb`, `sattel_cnc_test.rb` (aufgesattelte Wangen 2.7.0), `switch_test.rb` (Umschalten Raum ↔ Parameter), `austritt_test.rb` (Austrittspodest), `build_test.rb` (alle Formen × Seiten-Kombinationen × frei/Raum mit schrägen Wänden, prüft geschlossene Körper), `plan_test.rb`, `fit_test.rb` (Raumfälle inkl. Winkel, Antritt fest, Treppenloch), `stringer_test.rb` (Überstand ≥ Vorgabe, konstante Breite, Mindestabstand unten), `kite_test.rb` (Drachenstufen), `cnc_test.rb`, `tcncheck.rb`, Plots `plotfit2.py`, `plotboards.rb/.py`, `dump3d.rb` + `render1.py`, Dialog-Screenshots `fmock2.rb` + `shotx.js` (Playwright).
Paket bauen: im Ordner `src`: `zip -r treppenbau.rbz jt_treppenbau.rb jt_treppenbau`

## Noch nicht in SketchUp/TpaCAD getestet
Alles wurde nur außerhalb von SketchUp geprüft. Erster echter Test steht aus.

## Offene Punkte / Ideen
- Geschwungene Wange: Rückmeldung zur Optik in Wendelbereichen (Krümmung der Unterkante an Innenecken kann stark sein)
- Test in SketchUp + TpaCAD, Rückmeldung Fräser-Ø und Nutseite der Wangen
- Gemischte Treppe (Podest + Wendelstufen) fehlt
- Wangenenden an schräger Austrittswand: im Grundriss schräg, im CNC-Teil rechtwinklig (Gehrung von Hand)
- Sattelwangen: Unterkante des oberen Bretts kann an der Ecke einen Knick haben (Gehrung ist seit 2.7.0 Standard)
- Raum: Treppenloch nur rechteckig/achsparallel; dreiläufig mit nur einer Wand nutzt die Raumgrenze als Anschlag
- Neue Treppe wird im Ursprung eingefügt (Raum-Modus: Ursprung = vordere linke Raumecke)
