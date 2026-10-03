# Testprogramme Seitenaggregat (Schräge Ausklinkung) – Stand 03.10.2026

Eigenständige Test-TCNs, **nicht** Teil des Plugins. Erzeugt mit `ruby gen_tests.rb`,
geprüft und gezeichnet mit `python check_tests.py` (→ `*.png`, Draufsicht).

Werkzeuge: von oben **1000** (Ø12, wie Plugin-Vorgabe), Aggregat **15001** (Ø16, nutzbar 167 mm),
Gravur **r0 = 1400**, Tiefe **r1 = −1 mm**. Brettdicke immer 40 mm. Aggregatbahnen ohne
Fräserkorrektur (#40=0) – die Mittelpunktsbahn ist direkt programmiert.

Prinzip: Von oben wird die Ausklinkung senkrecht bis zur **materialseitigen** Lage ausgeräumt
(kein loses Abfallstück). Danach fährt das Aggregat (Spindel waagerecht, zeigt entlang der
„Treppen-Senkrechten“) in die freie Ausklinkung bis aufs Auflager und fräst den Keil in
3 parallelen Bahnen weg (letzte Bahn = Schräge 45°). Unter die Brettunterseite max. 1 mm.

| Datei | Rohling | Inhalt | Erwartung |
|---|---|---|---|
| `A_seite5.tcn` | 400 × 250 | Ausklinkung oben links (Auflager y = 150, Stoß x = 150 unten / 190 oben). Schräge auf **Fläche 5** (hinten, y = 250), Spindel zeigt in −Y | Aggregatbahn (Fräsermitte) liegt bei **x ≈ 112…189** (links vom Zahn), Tiefe 100 mm ab Fläche 5 bis aufs Auflager |
| `B_gside_30grad.tcn` | 400 × 260 | gleiche Schräge, aber Treppen-Senkrechte um **30°** gedreht → **Hilfsfläche 7** (`GEO`/`GSIDE`), C-Achse 30° | Aggregat dreht 30°, Bahn an der schrägen Stoßkante (grün in `B_gside_30grad.png`), Tiefe 150 |
| `C_markierung.tcn` | 400 × 250 | wie A, ohne Aggregat; **Markierung** (Gravur 1 mm): Linie x = 190 (Oberkante der Schräge) + Querstrich 20 mm über dem Auflager | Linien für Handnacharbeit sichtbar |
| `D1_wenden_seite1.tcn` | 500 × 250 | 2 Ausklinkungen mit **entgegengesetzter** Schräge. Seite 1: beide ausräumen, Schräge 1 mit Aggregat, Markierung x = 340 („Schräge 2 unten bis hier“) | |
| `D2_wenden_seite2.tcn` | 500 × 250 | Brett **um die Y-Achse wenden** (links ↔ rechts, Anschlag an den Rohlingskanten, gleiche Nullecke). Schräge 2 mit Aggregat, Tiefe 75 | Fräsermitte bei x′ ≈ 161…238 (nach dem Wenden), rechts von der Stoßkante |

## Bitte in dieser Reihenfolge testen
1. **Nur TpaCAD (Simulation/3D-Ansicht)** – öffnet die Datei ohne Fehler? Wird 15001 als
   Aggregat erkannt? Liegt die Aggregatbahn **links vom hohen Zahn** (A: Fräsermitte bei x ≈ 112–189)?
   ⚠ Liegt sie bei A stattdessen bei x ≈ 211–288 (gespiegelt), ist die X-Richtung von Fläche 5
   andersherum als angenommen → **nicht fräsen**, Rückmeldung genügt.
2. B: wird die Hilfsfläche 7 angenommen, steht die C-Achse auf 30° (bzw. 120°/−60° je nach
   Zählweise) und zeigt die Spindel schräg nach unten-links in die Ausklinkung?
3. Luftlauf (Z-Versatz / ohne Werkstück), dann **Restholz 40 mm**.
4. Rückmeldung: Fehlermeldungen von TpaCAD, Screenshot der 3D-Ansicht, Ergebnis im Holz
   (Schräge sauber? Auflager? Unterseite angefräst?), und bei D: Wenden praktikabel?

## Bewusste Annahmen (werden durch den Test geklärt)
- Fläche 5: Ursprung (0; DH; 0), X = +X, Y = Dicke nach oben, Tiefe negativ ins Teil
  (laut TpaCAD-Formatbeschreibung; die Spiegelung ist nicht eindeutig dokumentiert).
- Hilfsfläche: `GEO{ ::NF=1 GSIDE#7{ #1 #2 #3 #Z }GSIDE }GEO` vor den SIDE-Blöcken,
  rechtshändig (X × Y = Normale nach außen), `#Z=300`.
- `#201=1 #203=1 #1001=100` wie bei den Fräsungen von oben.
