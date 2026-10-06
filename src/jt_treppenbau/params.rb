# encoding: UTF-8
# Treppenbau – Parameterschema, Standardwerte und Normalisierung.
# Alle Längen in cm, Winkel in Grad.

module JTools
  module Treppenbau
    module Params

      VARIANTS = [
        ['gerade',        'Gerade Treppe (einläufig)'],
        ['gerade_podest', 'Gerade, zweiläufig mit Zwischenpodest'],
        ['l_podest',      'Viertelgewendelt mit Podest (L / Winkelpodest)'],
        ['l_wendel',      'Viertelgewendelt mit Wendelstufen (L)'],
        ['u_podest',      'Halbgewendelt mit Podest (U / gegenläufig)'],
        ['u_wendel',      'Halbgewendelt mit Wendelstufen (U)'],
        ['z_podest',      'Zweimal viertelgewendelt, 2 Podeste (dreiläufig)'],
        ['z_wendel',      'Zweimal viertelgewendelt mit Wendelstufen (dreiläufig)'],
        ['spindel',       'Wendeltreppe mit Spindel (Spindeltreppe)'],
        ['auge',          'Wendeltreppe mit Treppenauge']
      ].freeze

      SPIRAL   = %w[spindel auge].freeze
      PODEST   = %w[gerade_podest l_podest u_podest z_podest].freeze
      WENDEL   = %w[l_wendel u_wendel z_wendel].freeze
      TURNING  = %w[l_podest l_wendel u_podest u_wendel z_podest z_wendel].freeze
      U_TYPES  = %w[u_podest u_wendel].freeze
      ALL      = VARIANTS.map(&:first).freeze
      NOSPIRAL = (ALL - SPIRAL).freeze
      EYE_TYPES = %w[u_podest u_wendel z_podest z_wendel].freeze

      SIDE_OPTS = [['wange', 'Wange (eingestemmt)'], ['sattel', 'aufgesattelte Wange'],
                   ['frei', 'nichts – freitragend / Wandverankerung']].freeze

      # key, label, type, default, unit, group, extra
      #   extra: :options, :variants (Sichtbarkeit), :constr (Sichtbarkeit), :min, :max, :step, :help
      SCHEMA = [
        # --- Treppentyp ---------------------------------------------------
        { key: 'variant', label: 'Treppenform', type: 'select', default: 'gerade',
          group: 'Treppentyp', options: VARIANTS },
        { key: 'direction', label: 'Drehrichtung (aufwärts)', type: 'select', default: 'rechts',
          group: 'Treppentyp', options: [['links', 'linksgewendelt / Innenseite links'], ['rechts', 'rechtsgewendelt / Innenseite rechts']],
          help: 'Bei geraden Treppen: Seite, die als „innen“ gilt (für Geländerseite).' },
        { key: 'construction', label: 'Bauart', type: 'select', default: 'wange',
          group: 'Treppentyp', options: [['wange', 'Holztreppe – jede Seite einzeln (Wange / aufgesattelt / frei)'],
                                         ['holm', 'Holmtreppe (Mittelholm, aufgesattelt)'], ['massiv', 'Massivtreppe (Beton-Laufplatte)']] },
        { key: 'side_left', label: 'Seite links (vom Antritt aus)', type: 'select', default: 'wange', group: 'Treppentyp',
          options: SIDE_OPTS, constr: ['wange'], variants: NOSPIRAL },
        { key: 'side_right', label: 'Seite rechts', type: 'select', default: 'wange', group: 'Treppentyp',
          options: SIDE_OPTS, constr: ['wange'], variants: NOSPIRAL,
          help: 'Wange = Stufen in die Wange eingestemmt; aufgesattelt = Stufen liegen auf einer ausgeklinkten Wange; ' \
                'frei = keine Wange (Stufen freitragend bzw. in der Wand verankert). Alle Wangen bestehen aus geraden Brettern.' },
        { key: 'building', label: 'Gebäudeart (Prüfwerte)', type: 'select', default: 'efh',
          group: 'Treppentyp', options: [['efh', 'Wohngebäude ≤ 2 Wohnungen'], ['sonst', 'Sonstige Gebäude'], ['neben', 'Baurechtlich nicht notwendige Treppe']],
          help: 'Nur für die Plausibilitätsprüfung (Richtwerte nach DIN 18065).' },

        # --- Platzvorgabe (freie Planung: Grundmaß, sonst Raum) ---------------
        { key: 'fit_mode', label: 'Ermittlung', type: 'select', default: 'aus', group: 'Platzvorgabe (Grundmaß / Raum)',
          options: [['aus', 'Treppe aus den Parametern berechnen'], ['raum', 'Treppe in verfügbaren Raum einpassen']],
          help: 'Die Treppe wird an die Wände (abzüglich Spiel) und an den Austritt gelegt – ohne Luft. Zwischen zwei Wänden ' \
                'ergibt sich die Laufbreite aus dem Raum (U-Treppe: aus Raumbreite und Treppenauge). Gesucht werden Steigungsanzahl, ' \
                'Auftritt und Aufteilung der Läufe; der Antritt ist frei oder fest vorgegeben. ' \
                'Beim Umschalten bleibt die Treppe unverändert: Raum → Parameter übernimmt die gefundenen Werte (Feinjustierung), ' \
                'Parameter → Raum leitet Raum, Antritt und ggf. Treppenloch aus der Treppe ab.' },
        { key: 'total_w', label: 'Gesamtbreite der Treppe (Grundmaß quer)', type: 'number', default: 0, unit: 'cm', group: 'Platzvorgabe (Grundmaß / Raum)', min: 0, step: 0.5,
          freeonly: true, variants: NOSPIRAL,
          help: '0 = ergibt sich aus Laufbreite (und Treppenauge). > 0 = die Treppe wird genau auf diese Breite gebracht, gemessen über alles ' \
                'inkl. eingestemmter Wangen (gerade Treppe: Laufbreite folgt; U: Laufbreite aus Breite und Treppenauge; dreiläufig: Treppenauge folgt; ' \
                'L: Aufteilung der Läufe folgt). Auftritt, Steigungen und Lauflängen werden wie beim Einpassen in einen Raum gesucht.' },
        { key: 'total_l', label: 'Gesamttiefe der Treppe (Grundmaß in Laufrichtung)', type: 'number', default: 0, unit: 'cm', group: 'Platzvorgabe (Grundmaß / Raum)', min: 0, step: 0.5,
          freeonly: true, variants: NOSPIRAL,
          help: '0 = ergibt sich aus dem Steigungsverhältnis. > 0 = von der vordersten Stufenkante (Antritt) bis zur Rückseite der Treppe ' \
                '(gerade: Austrittskante, sonst Außenkante inkl. Wange); der Auftritt bzw. die Podestlänge wird angepasst.' },
        { key: 'space_l', label: 'Raumlänge (von hinterer Wand bis Raumende am Antritt)', type: 'number', default: 400.0, unit: 'cm', group: 'Platzvorgabe (Grundmaß / Raum)', min: 0, step: 1, fitonly: true },
        { key: 'space_w', label: 'Raumbreite (entlang der hinteren Wand)', type: 'number', default: 250.0, unit: 'cm', group: 'Platzvorgabe (Grundmaß / Raum)', min: 0, step: 1, fitonly: true },
        { key: 'wall_gap', label: 'Spiel Wand – Treppe', type: 'number', default: 1.0, unit: 'cm', group: 'Platzvorgabe (Grundmaß / Raum)', min: 0, step: 0.5, fitonly: true,
          help: 'Fuge zwischen Wange bzw. Stufe und Wand. An jeder vorhandenen Wand liegt die Treppe genau mit diesem Abstand an.' },
        { key: 'wall_left', label: 'Wand links (vom Antritt aus gesehen)', type: 'bool', default: true, group: 'Platzvorgabe (Grundmaß / Raum)', fitonly: true },
        { key: 'wall_right', label: 'Wand rechts', type: 'bool', default: true, group: 'Platzvorgabe (Grundmaß / Raum)', fitonly: true },
        { key: 'wall_back', label: 'Wand gegenüber dem Antritt (hinten)', type: 'bool', default: true, group: 'Platzvorgabe (Grundmaß / Raum)', fitonly: true },
        { key: 'angle_left', label: 'Winkel hintere Wand – linke Wand', type: 'number', default: 90.0, unit: '°', group: 'Platzvorgabe (Grundmaß / Raum)', min: 45, max: 135, step: 0.5, fitonly: true,
          help: 'Innenwinkel der Raumecke hinten links. < 90° = Raum wird nach vorn schmaler, > 90° = breiter.' },
        { key: 'angle_right', label: 'Winkel hintere Wand – rechte Wand', type: 'number', default: 90.0, unit: '°', group: 'Platzvorgabe (Grundmaß / Raum)', min: 45, max: 135, step: 0.5, fitonly: true },
        { key: 'antritt_l', label: 'Antritt: Abstand von der hinteren Wand', type: 'number', default: 0, unit: 'cm', group: 'Platzvorgabe (Grundmaß / Raum)', min: 0, step: 0.5, fitonly: true,
          help: '0 = frei: der Antritt ergibt sich aus dem idealen Steigungsverhältnis (höchstens bis Raumende). ' \
                '> 0 = fest: die vorderste Stufenkante liegt genau so weit von der hinteren Wand entfernt (Auftritt wird angepasst). ' \
                'Der Wert darf größer als die Raumlänge sein – die ersten Stufen liegen dann vor dem Raumende bzw. außerhalb des Treppenlochs; ' \
                'der Austritt bleibt immer im Raum.' },
        { key: 'loch', label: 'Treppenloch (Deckenöffnung) vorgeben', type: 'bool', default: false, group: 'Platzvorgabe (Grundmaß / Raum)', fitonly: true,
          help: 'Der Austritt liegt dann an der Kante des Treppenlochs (sonst an der Wand bzw. Raumgrenze). Zusätzlich wird die Kopffreiheit geprüft.' },
        { key: 'loch_l', label: 'Treppenloch: Länge (in Richtung hintere Wand)', type: 'number', default: 280.0, unit: 'cm', group: 'Platzvorgabe (Grundmaß / Raum)', min: 10, step: 1, fitonly: true, lochonly: true },
        { key: 'loch_w', label: 'Treppenloch: Breite (entlang hinterer Wand)', type: 'number', default: 100.0, unit: 'cm', group: 'Platzvorgabe (Grundmaß / Raum)', min: 10, step: 1, fitonly: true, lochonly: true },
        { key: 'loch_x', label: 'Treppenloch: Abstand von linker Wand', type: 'number', default: 0, unit: 'cm', group: 'Platzvorgabe (Grundmaß / Raum)', min: 0, step: 1, fitonly: true, lochonly: true,
          help: 'Gemessen an der hinteren Wand von der linken Raumecke.' },
        { key: 'loch_y', label: 'Treppenloch: Abstand von hinterer Wand', type: 'number', default: 0, unit: 'cm', group: 'Platzvorgabe (Grundmaß / Raum)', min: 0, step: 1, fitonly: true, lochonly: true },
        { key: 'loch_gap', label: 'Austritt: Abstand vom Rand des Treppenlochs (Austrittspodest)', type: 'number', default: 0, unit: 'cm', group: 'Platzvorgabe (Grundmaß / Raum)', min: 0, step: 0.5, fitonly: true, lochonly: true, variants: NOSPIRAL,
          help: '0 = die Austrittskante (letzte Steigung) liegt genau an der Kante des Treppenlochs. > 0 = die letzte Steigung endet um dieses Maß ' \
                'vor der Lochkante (im Treppenloch, rechtwinklig zur Kante gemessen); dazwischen wird ein Austrittspodest auf Höhe der oberen Decke ' \
                'konstruiert (Podestplatte, Wangen, Geländer, CNC-Teile).' },
        { key: 'head_min', label: 'Mindest-Kopfhöhe (lichte Durchgangshöhe)', type: 'number', default: 200.0, unit: 'cm', group: 'Platzvorgabe (Grundmaß / Raum)', min: 150, step: 1, fitonly: true, lochonly: true },

        # --- Höhe & Steigung ------------------------------------------------
        { key: 'H', label: 'Geschosshöhe (OKFF bis OKFF)', type: 'number', default: 275.0, unit: 'cm', group: 'Höhe & Steigungsverhältnis', min: 50, step: 0.5 },
        { key: 'n_steps', label: 'Anzahl Steigungen', type: 'number', default: 0, unit: 'Stk', group: 'Höhe & Steigungsverhältnis', min: 0, step: 1,
          help: '0 = automatisch aus Ziel-Steigungshöhe' },
        { key: 'h_target', label: 'Ziel-Steigungshöhe', type: 'number', default: 18.0, unit: 'cm', group: 'Höhe & Steigungsverhältnis', min: 10, max: 25, step: 0.5 },
        { key: 'schritt', label: 'Schrittmaß 2h + a', type: 'number', default: 63.0, unit: 'cm', group: 'Höhe & Steigungsverhältnis', min: 55, max: 70, step: 0.5 },
        { key: 'a_user', label: 'Auftritt (Gehlinie)', type: 'number', default: 0, unit: 'cm', group: 'Höhe & Steigungsverhältnis', min: 0, step: 0.5,
          help: '0 = automatisch aus Schrittmaß (a = Schrittmaß − 2h)' },

        # --- Grundriss -----------------------------------------------------
        { key: 'b', label: 'Laufbreite', type: 'number', default: 90.0, unit: 'cm', group: 'Grundriss', min: 40, step: 1, variants: NOSPIRAL,
          help: 'Beim Einpassen in einen Raum: gilt nur, wo die Breite nicht durch zwei Wände (bzw. Wand und Treppenauge) bestimmt ist.' },
        { key: 'gl', label: 'Gehlinie: Abstand von Innenkante', type: 'number', default: 0, unit: 'cm', group: 'Grundriss', min: 0, step: 1, variants: TURNING,
          help: '0 = Mitte der Laufbreite. Bei U-Treppen (und beim Einpassen) wird der Abstand innerhalb des Gehbereichs angepasst, damit jede Drachenstufe mittig auf ihrer Ecke liegt.' },
        { key: 'landing_len', label: 'Podestlänge', type: 'number', default: 0, unit: 'cm', group: 'Grundriss', min: 0, step: 1, variants: ['gerade_podest'],
          help: '0 = Laufbreite' },
        { key: 'eye', label: 'Treppenauge (lichter Abstand der Läufe)', type: 'number', default: 20.0, unit: 'cm', group: 'Grundriss', min: 0, step: 1, variants: U_TYPES,
          help: 'Abstand zwischen den Innenkanten der beiden Läufe (ohne Wangen). Beim Einpassen ergibt sich daraus die Laufbreite.' },
        { key: 'eye_z', label: 'Treppenauge (Abstand Lauf 1 – Lauf 3)', type: 'number', default: 0, unit: 'cm', group: 'Grundriss', min: 0, step: 1, variants: %w[z_podest z_wendel], fitonly: true,
          help: '0 = ergibt sich aus Raumbreite und Laufbreite. > 0 = vorgegeben, die Laufbreite folgt daraus.' },
        { key: 'pod1_vor', label: 'Podest 1: Verlängerung vor der Wendung (Lauf 1)', type: 'number', default: 0, unit: 'cm', group: 'Grundriss', min: 0, step: 0.5,
          variants: %w[l_podest u_podest z_podest], freeonly: true,
          help: '0 = Podest genau so tief wie die Laufbreite. > 0 = Podest wird vor der Wendung in Laufrichtung um dieses Maß verlängert ' \
                '(wird beim Umschalten von „Raum einpassen“ übernommen).' },
        { key: 'pod1_nach', label: 'Podest 1: Verlängerung nach der Wendung', type: 'number', default: 0, unit: 'cm', group: 'Grundriss', min: 0, step: 0.5,
          variants: %w[l_podest u_podest z_podest], freeonly: true },
        { key: 'pod2_vor', label: 'Podest 2: Verlängerung vor der Wendung', type: 'number', default: 0, unit: 'cm', group: 'Grundriss', min: 0, step: 0.5,
          variants: %w[z_podest], freeonly: true },
        { key: 'pod2_nach', label: 'Podest 2: Verlängerung nach der Wendung', type: 'number', default: 0, unit: 'cm', group: 'Grundriss', min: 0, step: 0.5,
          variants: %w[z_podest], freeonly: true },
        { key: 'exit_land', label: 'Austrittspodest (Tiefe hinter der letzten Steigung)', type: 'number', default: 0, unit: 'cm', group: 'Grundriss', min: 0, step: 0.5,
          variants: NOSPIRAL, freeonly: true,
          help: '0 = kein Austrittspodest. > 0 = hinter der letzten Steigung folgt ein Podest auf Höhe der oberen Decke ' \
                '(entspricht beim Einpassen „Abstand vom Rand des Treppenlochs“).' },
        { key: 'r1', label: 'Steigungen im 1. Lauf', type: 'number', default: 0, unit: 'Stk', group: 'Grundriss', min: 0, step: 1, variants: PODEST,
          help: '0 = automatisch (gleichmäßig verteilt). Beim Einpassen mit festem Antritt bzw. Austritt ergibt sich die Aufteilung aus dem Raum.' },
        { key: 'r2', label: 'Steigungen im 2. Lauf', type: 'number', default: 0, unit: 'Stk', group: 'Grundriss', min: 0, step: 1, variants: ['z_podest'],
          help: '0 = automatisch' },
        { key: 'm1', label: 'Stufen vor der Drachenstufe (Lage der Wendelung)', type: 'number', default: 0, unit: 'Stk', group: 'Grundriss', min: 0, step: 1, variants: WENDEL,
          help: '0 = automatisch (mittig). In jeder Ecke liegt eine Drachenstufe (Teilung siehe „Lage der Ecke im Auftritt“); klein = Wendelung unten (Antritt), groß = oben (Austritt). ' \
                'Beim Einpassen mit festem Antritt bzw. Austritt ergibt sich die Lage aus dem Raum.' },
        { key: 'kite_pos', label: 'Drachenstufe: Lage der Ecke im Auftritt', type: 'number', default: 0, unit: '%', group: 'Grundriss', min: 0, max: 99.9, step: 0.5,
          variants: WENDEL, freeonly: true,
          help: '0 = automatisch (mittig, 50 %). Anteil des Auftritts auf der Gehlinie vor der Ecke: unter 50 % liegt die Ecke näher an der unteren ' \
                'Stufenkante. Die Drachenstufe wird an der Innenkante im selben Verhältnis geteilt; der kleinere Schenkel muss mindestens 2 cm lang sein. ' \
                'U-Treppe: gilt für die erste Ecke (die zweite folgt aus Treppenauge und Gehlinie, die Gehlinie wird dann nicht angepasst).' },
        { key: 'kite_pos2', label: 'Drachenstufe 2: Lage der Ecke im Auftritt', type: 'number', default: 0, unit: '%', group: 'Grundriss', min: 0, max: 99.9, step: 0.5,
          variants: ['z_wendel'], freeonly: true,
          help: '0 = automatisch (mittig, 50 %). Wie oben, für die zweite Ecke.' },
        { key: 'm2', label: 'Stufen zwischen den Drachenstufen', type: 'number', default: 0, unit: 'Stk', group: 'Grundriss', min: 0, step: 1, variants: ['z_wendel'],
          help: '0 = automatisch' },
        { key: 'nv', label: 'Verzogene Stufen je Wendelung', type: 'number', default: 0, unit: 'Stk', group: 'Grundriss', min: 0, step: 1, variants: WENDEL,
          help: '0 = automatisch. Mehr verzogene Stufen = gleichmäßigere, breitere Innenauftritte.' },
        { key: 'min_inner', label: 'Mindestauftritt an der Innenkante (Prüfwert)', type: 'number', default: 10.0, unit: 'cm', group: 'Grundriss', min: 0, step: 0.5, variants: WENDEL },

        # --- Wendeltreppe ----------------------------------------------------
        { key: 'D_out', label: 'Außendurchmesser', type: 'number', default: 180.0, unit: 'cm', group: 'Wendeltreppe', min: 80, step: 1, variants: SPIRAL,
          help: 'Beim Einpassen in einen Raum wird der Durchmesser aus dem Raum ermittelt.' },
        { key: 'd_in', label: 'Spindel- bzw. Augendurchmesser', type: 'number', default: 0, unit: 'cm', group: 'Wendeltreppe', min: 0, step: 1, variants: SPIRAL,
          help: '0 = automatisch (Spindel 12 cm, Auge 50 cm)' },
        { key: 'rg', label: 'Radius der Gehlinie', type: 'number', default: 0, unit: 'cm', group: 'Wendeltreppe', min: 0, step: 1, variants: SPIRAL,
          help: '0 = Mitte der Laufbreite' },
        { key: 'angle', label: 'Gesamtdrehwinkel', type: 'number', default: 0, unit: '°', group: 'Wendeltreppe', min: 0, step: 1, variants: SPIRAL,
          help: '0 = automatisch aus Auftritt. Wird ein Winkel vorgegeben, ergibt sich der Auftritt daraus.' },

        # --- Stufen ----------------------------------------------------------
        { key: 'tread_t', label: 'Trittstufendicke', type: 'number', default: 4.0, unit: 'cm', group: 'Stufen', min: 1, step: 0.5, constr: %w[wange holm] },
        { key: 'nosing', label: 'Unterschneidung (Überstand)', type: 'number', default: 3.0, unit: 'cm', group: 'Stufen', min: 0, step: 0.5, constr: %w[wange holm] },
        { key: 'risers', label: 'Setzstufen', type: 'bool', default: false, group: 'Stufen', constr: %w[wange holm] },
        { key: 'riser_t', label: 'Setzstufendicke', type: 'number', default: 2.0, unit: 'cm', group: 'Stufen', min: 0.5, step: 0.5, constr: %w[wange holm] },

        # --- Tragkonstruktion -----------------------------------------------
        { key: 'str_t', label: 'Wangendicke', type: 'number', default: 5.0, unit: 'cm', group: 'Tragkonstruktion', min: 1, step: 0.5, constr: ['wange'], side: 'wange' },
        { key: 'str_over', label: 'Wange über Stufenvorderkante (konstant)', type: 'number', default: 5.0, unit: 'cm', group: 'Tragkonstruktion', min: 0, step: 0.5, constr: ['wange'], side: 'wange',
          help: 'Lotrechter Überstand der Wangenoberkante über der Verbindungslinie der Stufenvorderkanten.' },
        { key: 'str_under', label: 'Wange unter Stufenunterkante (mindestens)', type: 'number', default: 4.0, unit: 'cm', group: 'Tragkonstruktion', min: 0, step: 0.5, constr: ['wange'], side: 'wange',
          help: 'Lotrechter Mindestabstand der Wangenunterkante unter der Unterkante jeder Stufe (hinteres Ende des Einstands). Darf größer werden, nie kleiner.' },
        { key: 'str_form', label: 'Wangenform (Seitenansicht)', type: 'select', default: 'gerade', group: 'Tragkonstruktion', constr: ['wange'], side: %w[wange sattel],
          options: [['gerade', 'gerade Kanten, konstante Breite'], ['kurve', 'geschwungen – Kanten als Kurve, Breite variabel']],
          help: 'Geschwungen: Oberkante exakt um den Überstand über jeder Stufenvorderkante, Unterkante exakt um den Mindestabstand unter jeder Stufe, ' \
                'beide als knickfreie Kurve je Lauf (gerade Läufe bleiben gerade). Aufgesattelte Wangen: Unterkante als knickfreie Kurve je Lauf, ' \
                'an jeder Ausklinkung mindestens die Restbreite. Bretter bleiben im Grundriss gerade, Podeste waagerecht.' },
        { key: 'str_h', label: 'Wangenhöhe (Brettbreite, konstant)', type: 'number', default: 0, unit: 'cm', group: 'Tragkonstruktion', min: 0, step: 0.5, constr: ['wange'], side: 'wange',
          help: '0 = automatisch: kleinste für alle Wangen gleiche Brettbreite, die Überstand oben und Mindestabstand unten einhält. ' \
                'Gemessen rechtwinklig zur Wangenkante.' },
        { key: 'sat_t', label: 'Dicke aufgesattelte Wange', type: 'number', default: 6.0, unit: 'cm', group: 'Tragkonstruktion', min: 2, step: 0.5, constr: ['wange'], side: 'sattel' },
        { key: 'sat_rest', label: 'Restbreite unter der Ausklinkung', type: 'number', default: 12.0, unit: 'cm', group: 'Tragkonstruktion', min: 4, step: 0.5, constr: ['wange'], side: 'sattel',
          help: 'Rechtwinklig gemessen vom inneren Eckpunkt der Ausklinkungen bis zur Wangenunterkante.' },
        { key: 'sat_inset', label: 'Stufenüberstand seitlich über aufgesattelter Wange', type: 'number', default: 3.0, unit: 'cm', group: 'Tragkonstruktion', min: 0, step: 0.5, constr: ['wange'], side: 'sattel' },
        { key: 'holm_w', label: 'Holmbreite', type: 'number', default: 12.0, unit: 'cm', group: 'Tragkonstruktion', min: 4, step: 1, constr: ['holm'] },
        { key: 'holm_h', label: 'Holmhöhe (lotrecht)', type: 'number', default: 24.0, unit: 'cm', group: 'Tragkonstruktion', min: 8, step: 1, constr: ['holm'] },
        { key: 'slab_t', label: 'Laufplattendicke', type: 'number', default: 16.0, unit: 'cm', group: 'Tragkonstruktion', min: 8, step: 1, constr: ['massiv'] },

        # --- Geländer --------------------------------------------------------
        { key: 'rail', label: 'Geländer / Handlauf', type: 'select', default: 'aussen', group: 'Geländer',
          options: [['keins', 'kein Geländer'], ['aussen', 'außen'], ['innen', 'innen'], ['beide', 'beidseitig']] },
        { key: 'rail_h', label: 'Handlaufhöhe (Oberkante über Stufenvorderkante)', type: 'number', default: 90.0, unit: 'cm', group: 'Geländer', min: 60, step: 1 },
        { key: 'rail_hh', label: 'Handlauf: Querschnittshöhe', type: 'number', default: 8.0, unit: 'cm', group: 'Geländer', min: 2, step: 0.5,
          help: 'Rechteckiger Handlauf von Pfosten zu Pfosten. Breite = Wangendicke (eingestemmte bzw. aufgesattelte Wange). ' \
                'Bei geschwungener Wangenform verläuft auch der Handlauf geschwungen und wird als Platte aus dem Vollen gefräst.' },
        { key: 'rail_d', label: 'Handlaufbreite (Seiten ohne Wange)', type: 'number', default: 4.5, unit: 'cm', group: 'Geländer', min: 2, step: 0.5 },
        { key: 'newel_s', label: 'Pfostenquerschnitt (Antritt, Austritt, Laufwechsel)', type: 'number', default: 9.0, unit: 'cm', group: 'Geländer', min: 2, step: 0.5,
          help: 'Pfosten stehen am Antritt, am Austritt und an jedem Laufwechsel (Ecke bzw. Zwischenpodest). Der Handlauf läuft von Pfosten zu Pfosten. ' \
                'Bei eingestemmter und aufgesattelter Wange stehen Antritts- und Austrittspfosten in der Treppe, die Wange stößt an den Pfosten.' },
        { key: 'rail_mid', label: 'Zwischenpfosten ab Lauflänge', type: 'number', default: 200.0, unit: 'cm', group: 'Geländer', min: 0, step: 10,
          help: 'Ist ein Feld zwischen zwei Pfosten (im Grundriss) länger, kommt in die Mitte ein Zwischenpfosten. Er steht auf der Wange bzw. Stufe ' \
                'und endet unter dem Handlauf (der Handlauf läuft durch). 0 = keine Zwischenpfosten.' },
        { key: 'bal_shape', label: 'Stabform', type: 'select', default: 'quadrat', group: 'Geländer',
          options: [['quadrat', 'quadratisch'], ['rund', 'rund']],
          help: 'Bohrung für die Stäbe (Wange bzw. Trittstufe): Ø = Durchmesser bzw. Kantenlänge – quadratische Stäbe brauchen am Ende einen runden Zapfen.' },
        { key: 'bal_d', label: 'Stab: Kantenlänge', type: 'number', default: 2.5, unit: 'cm', group: 'Geländer', min: 0, step: 0.5,
          help: 'Quadratische Stäbe. 0 = keine Stäbe.' },
        { key: 'bal_dia', label: 'Stab: Durchmesser', type: 'number', default: 2.5, unit: 'cm', group: 'Geländer', min: 0, step: 0.5,
          help: 'Runde Stäbe. 0 = keine Stäbe.' },
        { key: 'bal_gap', label: 'Lichter Stababstand (höchstens)', type: 'number', default: 12.0, unit: 'cm', group: 'Geländer', min: 4, step: 0.5,
          help: 'DIN 18065: höchstens 12 cm. Die Stäbe stehen im Stufenraster: jede Stufe wird in gleiche Felder geteilt, der Stab steht in Feldmitte ' \
                '(bei gleich tiefen Stufen überall gleicher Abstand). Lücken an den Pfosten werden aufgefüllt.' },
        { key: 'bal_edge', label: 'Stab: Mindestabstand zum Stufenrand', type: 'number', default: 3.0, unit: 'cm', group: 'Geländer', min: 0, step: 0.5,
          help: 'Nur wo die Stäbe auf den Stufen stehen (aufgesattelte Wange, freitragend): Abstand Stabkante – Stufenvorderkante bzw. ' \
                'Vorderkante der nächsten Stufe. Je Stufe wird die Tiefe in gleiche Felder geteilt, der Stab steht in Feldmitte.' },
        { key: 'bal_depth', label: 'Stab: Einlasstiefe (Bohrung)', type: 'number', default: 3.0, unit: 'cm', group: 'Geländer', min: 0, step: 0.5,
          help: 'Eingestemmte Wange: lotrechte Bohrung in die Wangenoberkante (schräg zur Wangenkante). Auf Stufen: Bohrung in die Trittstufe (höchstens Stufendicke − 1 cm). ' \
                'Oben: lotrechte Bohrung in die Handlauf-Unterkante (höchstens Handlaufhöhe − 1 cm).' },
        { key: 'rail_inset', label: 'Geländerabstand von der Laufkante', type: 'number', default: 5.0, unit: 'cm', group: 'Geländer', min: 0, step: 0.5,
          help: 'Lage der Pfosten- und Stabachse auf den Stufen (aufgesattelt, freitragend). Bei eingestemmten Wangen steht das Geländer mittig auf der Wange.' },

        # --- Darstellung ----------------------------------------------------
        { key: 'show_walkline', label: 'Gehlinie einzeichnen', type: 'bool', default: true, group: 'Darstellung' },
        { key: 'show_floor', label: 'Austrittskante (obere Decke) andeuten', type: 'bool', default: true, group: 'Darstellung' },
        { key: 'floor_t', label: 'Deckendicke (für Darstellung)', type: 'number', default: 20.0, unit: 'cm', group: 'Darstellung', min: 0, step: 1 }
      ].freeze

      def self.defaults
        h = {}
        SCHEMA.each { |f| h[f[:key]] = f[:default] }
        h
      end

      # Wandelt beliebigen Input (JSON-Hash) in typsichere Parameter um.
      def self.normalize(input)
        input ||= {}
        out = defaults
        # Ältere Versionen (< 1.4): Wangenhöhe war lotrecht und fest – jetzt automatisch
        if input.key?('str_h') && !input.key?('str_under')
          input = input.dup
          input['str_h'] = 0
        end
        SCHEMA.each do |f|
          k = f[:key]
          next unless input.key?(k)
          v = input[k]
          case f[:type]
          when 'number'
            x = v.is_a?(Numeric) ? v.to_f : v.to_s.tr(',', '.').to_f
            x = f[:min].to_f if f[:min] && x < f[:min]
            x = f[:max].to_f if f[:max] && x > f[:max]
            out[k] = x
          when 'bool'
            out[k] = (v == true || v.to_s == 'true' || v.to_s == '1')
          when 'select'
            vals = f[:options].map(&:first)
            out[k] = vals.include?(v.to_s) ? v.to_s : f[:default]
          end
        end
        out
      end

      # Ausführung einer Treppenseite: 'wange', 'sattel', 'frei' oder nil (Holm/Massiv).
      # which: :outer / :inner; outer_side < 0 => Außenseite liegt links.
      def self.side_kind(p, which, outer_side, spiral = false)
        return nil unless p['construction'] == 'wange'
        return 'frei' if spiral
        left_is_outer = outer_side < 0
        left = (which == :outer) == left_is_outer
        p[left ? 'side_left' : 'side_right']
      end

      # Geländerstab: [Form ('rund' | 'quadrat'), Durchmesser bzw. Kantenlänge (cm)]
      def self.bar_size(p)
        p['bal_shape'] == 'rund' ? ['rund', p['bal_dia'].to_f] : ['quadrat', p['bal_d'].to_f]
      end
    end
  end
end
