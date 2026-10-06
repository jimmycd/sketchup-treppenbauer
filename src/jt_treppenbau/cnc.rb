# encoding: UTF-8
# Treppenbau – CNC-Export: Teile ermitteln, je Materialstärke verschachteln,
# TCN-Dateien und Teileliste schreiben. (ohne SketchUp-API)

module JTools
  module Treppenbau
    module Cnc
      module_function

      # Fräser Außenkonturen: [Name, Werkzeugnummer, Ø (mm), max. Schnitttiefe (mm)]
      OUTER_TOOLS = [
        ['1300 – Ø 18,27 mm, max. Tiefe 54 mm', 1300, 18.27, 54.0],
        ['1004 – Ø 20 mm, max. Tiefe 107 mm', 1004, 20.0, 107.0],
        ['2200 – Ø 8,03 mm, max. Tiefe 23 mm', 2200, 8.03, 23.0]
      ].freeze
      # tool_outer = 0: automatisch je Materialstärke – 1300, wenn die Frästiefe
      # (Stärke + Durchfräsen) reicht, sonst 1004. 2200 nur bei expliziter Auswahl.
      TOOL_AUTO = 0
      AUTO_ORDER = [1300, 1004].freeze

      DEFAULTS = {
        'plate_l'     => 2800.0,  # Rohplatte Länge (mm, X = Faserrichtung)
        'plate_w'     => 1300.0,  # Rohplatte Breite (mm, höchstens Maschinenbreite mach_w)
        'margin'      => 10.0,    # Randabstand (mm)
        'tool_outer'  => 0,       # Fräser Außenkonturen (0 = automatisch)
        'tool_d'      => 18.27,   # Fräserdurchmesser (mm, nur bei expliziter Auswahl)
        'gap'         => 0.0,     # Teileabstand (0 = Ø + 4 mm)
        'overcut'     => 1.0,     # Durchfräsen (dxf4tcn)
        'climb'       => true,    # Uhrzeigersinn / Korrektur links (dxf4tcn)
        'grain'       => true,    # Faserrichtung beachten
        'grid'        => 5.0,     # Rasterweite Verschachtelung (mm)
        'p_treads'    => true,
        'p_risers'    => true,
        'p_stringers' => true,
        'p_posts'     => true,
        'p_rail'      => true,
        'einstand'    => 15.0,    # Nuttiefe / Einstand der Stufen in die Wange (mm)
        'pocket_tool' => 1400,    # Nutfräser
        'pocket_d'    => 10.0,    # Ø Nutfräser (mm)
        'engrave'     => false,   # Teilenummern gravieren
        'deco_tool'   => 1400,    # Gravurwerkzeug (dxf4tcn Verzierungen)
        'deco_depth'  => 2.0,     # Gravurtiefe (dxf4tcn)
        'text_h'      => 30.0,    # Schrifthöhe (mm)
        'open_tpa'    => true,    # erste TCN in TpaCAD öffnen (dxf4tcn)
        # aufgesattelte Wangen: je Wange ein 3D-Programm (Rohling rechteckig)
        'sat_mode'    => 'fraesen', # Schrägen 'fraesen' (Seitenaggregat) oder nur 'markieren'
        'sat_wenden'  => false,   # Schrägen mit umgekehrter Neigung nach Wenden (Seite 2)
        'sat_zstep'   => 20.0,    # Außenkontur Wange: Zustellung je Umlauf (mm, 0 = ein Umlauf)
        'agg_tool'    => 15001,   # Seitenaggregat (waagerechte Spindel)
        'agg_d'       => 16.0,    # Ø Aggregatfräser (mm)
        'agg_len'     => 167.0,   # nutzbare Länge (mm)
        'agg_clear'   => 5.0,     # Freiraum Aggregat über dem Material (mm)
        'agg_step'    => 50.0,    # Zustellung entlang der Achse (mm)
        'blank_margin' => 15.0,   # Rohling: Zugabe ringsum (mm)
        # Bohrungen Geländerstäbe (Ø = Stabmaß)
        'drill_tool'  => 0,       # Bohrer von oben (Trittstufen), 0 = nach Durchmesser
        'drill_wange' => 'bohren', # eingestemmte Wange: 'bohren' (Aggregat) oder nur 'markieren'
        'hdrill_tool' => 0,       # Bohraggregat waagerecht, 0 = nach Durchmesser
        'drill_clear' => 5.0,     # Anfahrabstand vor der Wangenkante (mm)
        # überlange Wangen: zwei Läufe, dazwischen 180° drehen (gleicher X-Anschlag)
        'long_mode'   => 'drehen', # 'drehen' oder 'aus' (dann nur Warnung wie bisher)
        'mach_l'      => 3200.0,  # Verfahrweg X = größte TCN-Länge (mm)
        'mach_w'      => 1300.0,  # Maschinenbreite Y = größte TCN-Breite (mm)
        'long_overlap' => 10.0,   # Außenkontur: Überlauf über die Teilung je Lauf (mm)
        'tab_n'       => 3,       # Haltestege je Konturstück in Lauf A (0 = keine)
        'tab_w'       => 20.0,    # Breite Haltesteg (mm)
        'tab_h'       => 4.0      # Höhe Haltesteg (mm)
      }.freeze

      Result = Struct.new(:sheets, :unplaced, :warnings, :parts, :boards, :longs, :manual)
      # Teile mit eigenem Rohling statt Verschachtelung (eingestemmte Wangen,
      # Handläufe, Geländerpfosten): je Teil ein eigenes Programm, überlang in
      # zwei Läufen
      OWN_BLANK = %i[stringer rail post].freeze
      # steps: Geländerpfosten mit Taschen/Bohrungen – je Fläche ein Programm
      # [{ face:, rolls:, prog:, split: }] (das erste ist prog/split)
      LongPart = Struct.new(:part, :prog, :split, :notes, :steps) do
        def label; part.label; end
        def blank; [prog[:l], prog[:w]]; end
        def kind_name; Parts::KIND_NAMES[part.kind] || part.kind.to_s; end
        # Dateiname ohne Umlaute
        def tcn_count; (steps || [{ split: split }]).sum { |st| st[:split][:runs].size }; end
        def file_kind; kind_name.gsub('ä', 'ae').gsub('ö', 'oe').gsub('ü', 'ue').gsub('ß', 'ss').gsub(/[^A-Za-z0-9]+/, '_'); end
      end
      SheetInfo = Struct.new(:thickness, :index, :count, :placements, :used_len, :util, :tool)

      def normalize(h)
        o = DEFAULTS.dup
        (h || {}).each do |k, v|
          next unless o.key?(k)
          d = DEFAULTS[k]
          o[k] = if d == true || d == false
                   v == true || v.to_s == 'true'
                 elsif d.is_a?(String)
                   v.to_s
                 elsif d.is_a?(Integer)
                   v.to_i
                 else
                   v.to_s.tr(',', '.').to_f
                 end
        end
        o
      end

      def tool_info(nr)
        OUTER_TOOLS.find { |_, n, _, _| n == nr }
      end

      # Fräser für die Außenkontur bei Materialstärke th:
      # { nr:, d:, max:, depth:, auto: } (max = nil bei unbekanntem Werkzeug)
      def outer_tool(o, th)
        depth = th.to_f + o['overcut'].to_f
        if o['tool_outer'].to_i == TOOL_AUTO
          t = AUTO_ORDER.map { |nr| tool_info(nr) }.find { |x| depth <= x[3] + 1e-6 } || tool_info(AUTO_ORDER.last)
          { nr: t[1], d: t[2], max: t[3], depth: depth, auto: true }
        else
          nr = o['tool_outer'].to_i
          t = tool_info(nr)
          d = o['tool_d'].to_f > 0 ? o['tool_d'].to_f : (t ? t[2] : 12.0)
          { nr: nr, d: d, max: t && t[3], depth: depth, auto: false }
        end
      end

      # nutzbare Breite Y: Rohplatte, höchstens Maschinenbreite (keine TCN breiter)
      def table_w(o)
        mw = o['mach_w'].to_f
        mw > 0 ? [o['plate_w'].to_f, mw].min : o['plate_w'].to_f
      end

      def gap(o, d = o['tool_d'])
        o['gap'].to_f > 0 ? o['gap'].to_f : d.to_f + 4.0
      end

      def depth_warning(what, tl)
        return nil unless tl[:max] && tl[:depth] > tl[:max] + 1e-6
        "#{what}: Frästiefe #{fmt(tl[:depth])} mm größer als max. Schnitttiefe von Fräser #{tl[:nr]} " \
          "(#{fmt(tl[:max], 0)} mm)#{tl[:auto] ? ' – kein passender Fräser vorhanden' : ''}."
      end

      def compute(plan, params, o)
        o['long_mode'] = 'drehen' unless %w[drehen aus].include?(o['long_mode'])
        parts, warnings = Parts.collect(plan, params,
                                        treads: o['p_treads'], risers: o['p_risers'],
                                        stringers: o['p_stringers'], posts: o['p_posts'],
                                        rail: o['p_rail'], einstand: o['einstand'], pocket_d: o['pocket_d'])
        warnings = warnings.dup
        if o['mach_w'].to_f > 0 && o['plate_w'].to_f > o['mach_w'].to_f + 1e-6
          warnings << "Rohplatte #{o['plate_w'].round} mm breiter als die Maschine (Y höchstens #{o['mach_w'].round} mm): " \
                      "verschachtelt wird auf #{table_w(o).round} mm Breite."
        end
        # nicht gefräste Teile (Geländerstäbe, gerade Handläufe): nur Teileliste und Nacharbeit
        manual, parts = parts.partition(&:no_tcn)
        nrl = manual.count { |pt| pt.kind == :rail }
        warnings << "#{nrl} gerade Handlaufstücke werden klassisch gefertigt (keine TCN) – Maße und Bohrungen siehe Nacharbeit." if nrl > 0
        # aufgesattelte Wangen mit 3D-Daten: eigenes Programm je Wange
        boards = []
        if o['p_stringers'] && params['construction'] == 'wange'
          boards = Wange3d.jobs(plan, params, o)
          lbls = boards.map(&:label)
          parts = parts.reject { |pt| pt.kind == :stringer && lbls.include?(pt.label) }
          boards.each { |b| warnings << b.summary if b.summary }
          if o['long_mode'] == 'drehen'
            boards.each { |b| split_board(b, o, warnings) }
            long = boards.select { |b| b.raw_blank[1] > table_w(o) || b.splits.values.any? { |sp| sp[:runs].nil? } }
          else
            long = boards.select { |b| b.raw_blank[0] > o['plate_l'] || b.raw_blank[1] > table_w(o) }
          end
          unless long.empty?
            warnings << "Wangen-Rohling größer als Rohplatte/Tisch (#{o['plate_l'].round} × #{table_w(o).round} mm): " +
                        long.map { |b| "#{b.label} (#{b.raw_blank.map(&:round).join('×')} mm)" }.join(', ') +
                        (long.any? { |b| b.raw_blank[1] > table_w(o) + 1e-6 } ? ' – breiter als die Maschine: keine TCN' : '')
          end
          nd = boards.sum { |b| (b.dowels || []).size }
          if nd > 0
            warnings << "#{nd} Dübel Stufe – aufgesattelte Wange: Wange mit dem Bohraggregat in die Auflagerkante, " \
                        'Stufen von unten von Hand nach der Bohrliste in …_Nacharbeit.txt.'
          end
          warnings << 'Einzelheiten zur Nacharbeit: Datei …_Nacharbeit.txt beim Export.' if boards.any? { |b| !b.notes.empty? || !(b.dowels || []).empty? }
          o['sat_mode'] = 'fraesen' unless %w[fraesen markieren].include?(o['sat_mode'])
        end
        o['drill_wange'] = 'bohren' unless %w[bohren markieren].include?(o['drill_wange'])
        nh = parts.sum { |pt| pt.drills.count { |h| h[:ang] } }
        if nh > 0 && o['drill_wange'] == 'bohren'
          warnings << "#{nh} waagerechte Bohrungen in den Wangen (Geländerstäbe in der Oberkante, Dübel in der Stirn; Bohraggregat, nach der Außenkontur): " \
                      'je Wange ein eigener Rohling; vor der Oberkante muss Platz für das Aggregat sein – Rohling-Zugabe prüfen oder „nur markieren“ wählen.'
        end
        (boards || []).each do |b|
          w = depth_warning("Wange #{b.label} (#{fmt(b.t)} mm)", outer_tool(o, b.t))
          warnings << w if w
        end
        r_max = parts.map(&:thickness).uniq.map { |th| outer_tool(o, th)[:d] }.max.to_f / 2.0
        if o['margin'] < r_max
          warnings << 'Randabstand ist kleiner als der Fräserradius – Konturen am Rand werden angeschnitten.'
        end
        if o['einstand'] > 0 && params['construction'] == 'wange' && o['einstand'] >= params['str_t'] * 10 - 5
          warnings << 'Einstand (Nuttiefe) ist fast so groß wie die Wangendicke.'
        end
        sheets = []
        unplaced = []
        # Wangen und Handläufe nie verschachteln: je Teil ein eigener Rohling,
        # damit das Bohraggregat von der Seite an die Kanten kommt
        longs = []
        own, nest = parts.partition { |pt| OWN_BLANK.include?(pt.kind) }
        own.map(&:thickness).uniq.sort.each do |th|
          w = depth_warning("#{own.select { |pt| pt.thickness == th }.map(&:label).join(', ')} (#{fmt(th)} mm)", outer_tool(o, th))
          warnings << w if w
        end
        own.each do |pt|
          lp = long_part(pt, o, warnings)
          lp ? longs << lp : unplaced << pt
        end
        np = longs.select { |lp| lp.steps }
        unless np.empty?
          warnings << "#{np.size} Geländerpfosten mit Taschen (Stufen) bzw. Bohrungen (Dübel Wange, Befestigung): " \
                      "#{np.sum { |lp| lp.steps.size }} Programme, je bearbeitete Fläche eines von oben, dazwischen abrollen – " \
                      'Einrichtung siehe …_Nacharbeit.txt.'
        end
        nest.group_by(&:thickness).sort.each do |th, list|
          tl = outer_tool(o, th)
          w = depth_warning("Platten #{fmt(th)} mm", tl)
          warnings << w if w
          g = gap(o, tl[:d])
          nester = Nester.new(length: o['plate_l'], width: table_w(o), margin: o['margin'],
                              gap: g, grid: o['grid'], grain: o['grain'])
          unless nester.usable?
            unplaced.concat(list)
            next
          end
          nester.nest(list)
          unplaced.concat(nester.unplaced)
          nester.plates.each_with_index do |sh, i|
            area = sh.placements.map { |pl| pl.part.area }.sum
            util = area / (o['plate_l'] * table_w(o))
            sheets << SheetInfo.new(th, i + 1, nester.plates.size, sh.placements, sh.maxx, util, tl)
          end
        end
        unless unplaced.empty?
          warnings << "#{unplaced.size} Teil(e) passen nicht auf die Rohplatte: " +
                      unplaced.map { |p| "#{p.label} (#{p.size.map { |v| v.round }.join('×')} mm)" }.first(8).join(', ')
        end
        Result.new(sheets, unplaced, warnings, parts + manual, boards, longs, manual)
      end

      # Optionen für Lauf.from_job (wie Tcn.write_job)
      def job_opts(o, t)
        { tool_outer: outer_tool(o, t)[:nr], overcut: o['overcut'], climb: o['climb'],
          zstep: o['sat_zstep'], deco_tool: o['deco_tool'], deco_depth: o['deco_depth'],
          drill_wange: o['drill_wange'], drill_clear: o['drill_clear'], hdrill_tool: o['hdrill_tool'] }
      end

      # Aufgesattelte Wange: Programme je Seite in Läufe teilen (Job#splits)
      def split_board(jb, o, warnings)
        r = outer_tool(o, jb.t)[:d] / 2.0
        jb.splits = {}
        jb.programs.each do |pg|
          # Seite 2 ist um die Y-Achse gewendet: Ursprung am Ende B
          sp = Lauf.split(Lauf.from_job(jb, pg, job_opts(o, jb.t)), o, r, pg.side == 1 ? %w[A B] : %w[B A], pg.side == 1 ? 0 : 1)
          jb.splits[pg.side] = sp
          sp[:warnings].each { |w| warnings << "Wange #{jb.label} Seite #{pg.side}: #{w}" }
        end
        sp1 = jb.splits[1]
        return unless sp1 && sp1[:runs] && sp1[:runs].size > 1
        jb.notes.concat(long_notes(jb.label, jb.raw_blank, sp1[:x_t], o, jb.programs.size > 1))
      end

      # Eingestemmte Wange bzw. Handlauf: eigener Rohling (blank_margin ringsum)
      def long_part(pt, o, warnings)
        tl = outer_tool(o, pt.thickness)
        steps = pt.kind == :post ? Lauf.post_progs(pt, o, tl[:nr]) : []
        prog = steps.empty? ? Lauf.from_part(pt, o, tl[:nr]) : steps[0][:prog]
        name = Parts::KIND_NAMES[pt.kind] || pt.kind.to_s
        if prog[:w] > table_w(o) + 1e-6
          warnings << "#{name} #{pt.label}: Rohling #{prog[:w].round} mm breiter als der Tisch (#{table_w(o).round} mm)."
          return nil
        end
        if o['long_mode'] == 'drehen'
          sp = Lauf.split(prog, o, tl[:d] / 2.0)
        else
          sp = { runs: [Lauf::Run.new('A', false, prog, nil)], x_t: nil, warnings: [] }
          sp[:warnings] << "Rohling #{prog[:l].round} mm länger als der Verfahrweg (#{o['mach_l'].round} mm)" if prog[:l] > o['mach_l'] + 1e-6
        end
        sp[:warnings].each { |w| warnings << "#{name} #{pt.label}: #{w}" }
        return nil unless sp[:runs]
        notes = []
        if sp[:runs].size > 1
          notes.concat(long_notes(pt.label, [prog[:l], prog[:w]], sp[:x_t], o, false))
          warnings << "#{name} #{pt.label} überlang (Rohling #{prog[:l].round} × #{prog[:w].round} mm): 2 Läufe, " \
                      'dazwischen drehen – Einrichtung siehe …_Nacharbeit.txt.'
        end
        return LongPart.new(pt, prog, sp, notes) if steps.empty?
        steps[0][:split] = sp
        steps[1..-1].each do |st|
          st[:split] = o['long_mode'] == 'drehen' ? Lauf.split(st[:prog], o, o['pocket_d'].to_f / 2.0) :
                         { runs: [Lauf::Run.new('A', false, st[:prog], nil)], x_t: nil, warnings: [] }
          st[:split][:warnings].each { |w| warnings << "#{name} #{pt.label} #{st[:prog][:title]}: #{w}" }
          return nil unless st[:split][:runs]
        end
        notes.concat(post_notes(pt, steps))
        LongPart.new(pt, prog, sp, notes, steps)
      end

      # Einrichtblatt eines Geländerpfostens mit mehreren Programmen (Wenden)
      def post_notes(pt, steps)
        n = steps.size
        lines = ["#{pt.label}: #{n} Programm#{n > 1 ? 'e' : ''} (Taschen und Bohrungen je Fläche von oben, " \
                 'Unterende immer am linken X-Anschlag, Pfosten am vorderen Y-Anschlag).']
        steps.each_with_index do |st, i|
          fn = pt.ops.find { |x| x[:face] == st[:face] }[:face_name]
          front = "Fläche #{(st[:face] + 1) % 4 + 1}"
          lines << if i.zero?
                     "#{pt.label}: Schritt 1 – Rohling mit #{fn} oben, #{front} vorne; ausfräsen, danach Unterende und #{fn} anzeichnen."
                   else
                     "#{pt.label}: Schritt #{i + 1} – #{st[:rolls] == 1 ? '' : "#{st[:rolls]} × "}90° nach hinten abrollen " \
                       "(vordere Fläche nach oben): #{fn} oben, #{front} vorne."
                   end
        end
        if pt.ops.any? { |x| x[:kind] == :pocket }
          lines << "#{pt.label}: Taschenecken innen mit Fräserradius gerundet – Stufenecken passend brechen oder Taschenecken nachstemmen."
        end
        lines
      end

      # Einrichtblatt für zwei Läufe
      def long_notes(label, blank, x_t, o, wenden)
        l, w = blank
        tabs = if o['tab_n'].to_i > 0 && o['tab_h'].to_f > 0
                 "Im ersten Lauf jeder Seite bleiben bis zu #{o['tab_n'].to_i} Haltestege je Konturstück stehen " \
                 "(#{fmt(o['tab_w'], 0)} × #{fmt(o['tab_h'], 0)} mm) – nach dem zweiten Lauf von Hand trennen."
               else
                 'Ohne Haltestege.'
               end
        seq = wenden ? 'Seite1_A, Seite1_B, wenden um die Y-Achse (Ende A kommt nach links, Kante 1 bleibt hinten), Seite2_A, Seite2_B' : 'A, dann B'
        [
          "#{label}: ÜBERLANG – Rohling genau #{l.round} mm lang (Enden rechtwinklig), Breite #{w.round} mm; " \
          'eine Längskante gerade abrichten und als Kante 1 markieren.',
          "#{label}: Teilung bei #{x_t.round} mm von Ende A, Außenkontur überlappt je #{fmt(o['long_overlap'], 0)} mm. " \
          "Lauf A (Feld N1): Ende A an den linken X-Anschlag, Kante 1 am VORDEREN Y-Anschlag; Lauf B (Feld N): " \
          'Wange 180° drehen, Ende B an denselben linken Anschlag, Kante 1 am HINTEREN Y-Anschlag.',
          "#{label}: Reihenfolge #{seq}. #{tabs} Überstand rechts abstützen."
        ]
      end

      def sheet_name(base, sh)
        th = sh.thickness % 1 == 0 ? sh.thickness.to_i.to_s : sh.thickness.to_s.tr('.', ',')
        "#{base}_#{th}mm_Platte#{sh.index}"
      end

      # Schreibt alle TCN-Dateien + Teileliste; liefert Liste der Dateien
      def export(dir, base, res, o)
        files = []
        res.sheets.each do |sh|
          path = File.join(dir, sheet_name(base, sh) + '.tcn')
          Tcn.write(path, sh.placements,
                    length: o['plate_l'], width: table_w(o), thickness: sh.thickness,
                    tool_outer: sh.tool[:nr], overcut: o['overcut'], climb: o['climb'],
                    deco_tool: o['deco_tool'], deco_depth: o['deco_depth'],
                    engrave: o['engrave'], text_h: o['text_h'],
                    pocket_tool: o['pocket_tool'], pocket_d: o['pocket_d'],
                    drill_tool: o['drill_tool'], hdrill_tool: o['hdrill_tool'],
                    drill_wange: o['drill_wange'], drill_clear: o['drill_clear'])
          files << path
        end
        bfiles = {}
        (res.boards || []).each do |jb|
          jb.programs.each do |pg|
            # nie breiter als die Maschine (Y)
            if (pg.side == 1 ? jb.raw_blank[1] : jb.blank[1]) > table_w(o) + 1e-6
              (bfiles[jb.label] ||= []) << "Seite #{pg.side} NICHT EXPORTIERT (breiter als #{table_w(o).round} mm)"
              next
            end
            sp = jb.splits && jb.splits[pg.side]
            if sp && sp[:runs] && sp[:runs].size > 1
              sp[:runs].each do |run|
                path = File.join(dir, "#{base}_Wange_#{jb.label}_Seite#{pg.side}_#{run.name}.tcn")
                Tcn.write_prog(path, Lauf.labeled(run))
                files << path
                (bfiles[jb.label] ||= []) << File.basename(path)
              end
              next
            end
            path = File.join(dir, "#{base}_Wange_#{jb.label}_Seite#{pg.side}.tcn")
            Tcn.write_job(path, jb, pg, job_opts(o, jb.t))
            files << path
            (bfiles[jb.label] ||= []) << File.basename(path)
          end
        end
        (res.longs || []).each do |lp|
          steps = lp.steps || [{ split: lp.split }]
          steps.each_with_index do |st, i|
            runs = st[:split][:runs]
            stp = lp.steps && steps.size > 1 ? "_#{i + 1}_Flaeche#{st[:face] + 1}" : ''
            runs.each do |run|
              path = File.join(dir, "#{base}_#{lp.file_kind}_#{lp.label}#{stp}#{runs.size > 1 ? "_#{run.name}" : ''}.tcn")
              Tcn.write_prog(path, runs.size > 1 ? Lauf.labeled(run) : run.prog)
              files << path
              (bfiles[lp.label] ||= []) << File.basename(path)
            end
          end
        end
        notes = (res.boards || []).flat_map(&:notes) + (res.longs || []).flat_map(&:notes)
        man = manual_notes(res.manual || []) + dowel_notes(res.boards || [])
        unless notes.empty? && man.empty?
          txt = File.join(dir, "#{base}_Nacharbeit.txt")
          n_w = (res.boards || []).size + (res.longs || []).size
          lines = []
          unless notes.empty?
            lines << ((res.longs || []).empty? ? "Aufgesattelte Wangen – Hinweise (#{res.boards.size} Wangen)" : "Wangen, Handläufe und Pfosten – Hinweise (#{n_w} Teile mit eigenem Programm)")
            lines << ''
            lines.concat(notes)
            lines << ''
          end
          lines.concat(man)
          File.open(txt, 'wb') do |io|
            io.write(lines.join("\r\n").encode('Windows-1252', invalid: :replace, undef: :replace, replace: '_') + "\r\n")
          end
          files << txt
        end
        posts = res.parts.select { |pt| pt.ops && !pt.ops.empty? }
        unless posts.empty?
          txt = File.join(dir, "#{base}_Pfosten_Bearbeitung.txt")
          File.open(txt, 'wb') do |io|
            io.write(post_sheet(posts).join("\r\n").encode('Windows-1252', invalid: :replace, undef: :replace, replace: '_') + "\r\n")
          end
          files << txt
        end
        csv = File.join(dir, "#{base}_Teileliste.csv")
        File.open(csv, 'wb') do |io|
          rows = [%w[Nr Teil Bezeichnung Staerke_mm Laenge_mm Breite_mm Flaeche_m2 Datei X_mm Y_mm Drehung]]
          res.sheets.each do |sh|
            sh.placements.each do |pl|
              p = pl.part
              l, w = p.size
              rows << [p.id, p.label, p.info, fmt(p.thickness), fmt(l), fmt(w), fmt(p.area / 1e6, 3),
                       sheet_name(base, sh) + '.tcn', fmt(pl.x), fmt(pl.y), pl.rot]
            end
          end
          (res.boards || []).each do |jb|
            rows << ['', jb.label, jb.info + ' (Rohling)', fmt(jb.t), fmt(jb.raw_blank[0]), fmt(jb.raw_blank[1]),
                     fmt(jb.raw_blank[0] * jb.raw_blank[1] / 1e6, 3), bfiles.fetch(jb.label, []).join(' + '), '', '', '']
          end
          (res.longs || []).each do |lp|
            p = lp.part
            l, w = lp.blank
            rows << [p.id, p.label, p.info + ' (eigener Rohling)', fmt(p.thickness), fmt(l), fmt(w),
                     fmt(l * w / 1e6, 3), bfiles.fetch(p.label, []).join(' + '), '', '', '']
          end
          (res.manual || []).each do |p|
            l, w = p.size
            rows << [p.id, p.label, p.info, fmt(p.thickness), fmt(l), fmt(w), fmt(p.area / 1e6, 3), "keine TCN – #{p.no_tcn}", '', '', '']
          end
          res.unplaced.each do |p|
            l, w = p.size
            rows << [p.id, p.label, p.info, fmt(p.thickness), fmt(l), fmt(w), fmt(p.area / 1e6, 3), 'NICHT PLATZIERT', '', '', '']
          end
          text = rows.map { |r| r.join(';') }.join("\r\n") + "\r\n"
          io.write(text.encode('Windows-1252', invalid: :replace, undef: :replace, replace: '_'))
        end
        files << csv
        # Fräsliste für TpaCAD aus den tatsächlich geschriebenen TCN-Dateien
        xmlst = Fraesliste.write(dir, base, files)
        files << xmlst if xmlst
        files
      end

      # Nacharbeit der nicht gefrästen Teile: Geländerstäbe (Zuschnitt nach
      # Länge) und gerade Handläufe (klassisch, mit Bohrungen für die Stäbe)
      def manual_notes(parts)
        lines = []
        bars = parts.select { |pt| pt.kind == :bar }
        unless bars.empty?
          lines << "Geländerstäbe – nicht gefräst, Zuschnitt (#{bars.size} Stück)"
          bars.group_by { |pt| pt.info.sub(/^Geländerstab \S+ /, '') }.each do |sec, list|
            ls = list.map { |pt| pt.size[0] }
            lines << "  #{list.size} × #{sec}, Längen #{ls.min.round}–#{ls.max.round} mm (gesamt #{fmt(ls.sum / 1000.0, 2)} m):"
            list.each_slice(8) { |sl| lines << '    ' + sl.map { |pt| "#{pt.label} #{pt.size[0].round}" }.join(', ') }
          end
          lines << '  Enden rechtwinklig; unten in Stufe bzw. Wange, oben lotrecht in den Handlauf gesteckt.'
          lines << ''
        end
        rails = parts.select { |pt| pt.kind == :rail && pt.manual }
        unless rails.empty?
          lines << "Gerade Handläufe – klassisch gefertigt (#{rails.size} Stück)"
          rails.each do |pt|
            m = pt.manual
            lines << "  #{pt.label}: #{pt.info.sub(/, \d+ Bohrungen.*$/, '')} – Länge #{fmt(m[:len], 0)} mm (Oberkante), " \
                     "Querschnitt #{fmt(m[:w], 0)} × #{fmt(m[:h], 0)} mm, Neigung #{fmt(m[:slope])}°, Enden lotrecht"
            next if m[:holes].empty?
            lines << "    #{m[:holes].size} Bohrungen von unten lotrecht (#{fmt(90.0 - m[:slope])}° zur Unterkante), Ø #{fmt(m[:d])} mm, " \
                     "Tiefe #{fmt(m[:depth])} mm, mittig in der Breite"
            lines << "    Abstand entlang der Unterkante ab unterem Ende (mm): #{m[:holes].map { |x| fmt(x) }.join('; ')}"
          end
          lines << ''
        end
        lines
      end

      # Bohrliste der Dübel Stufe – aufgesattelte Wange (Stufe von unten, von
      # Hand; die Wange bohrt die CNC bzw. markiert sie)
      def dowel_notes(boards)
        list = boards.flat_map { |jb| (jb.dowels || []).map { |dw| [jb, dw] } }
        return [] if list.empty?
        lines = ["Dübel Trittstufen – aufgesattelte Wange (#{list.size} Stück): Stufen von unten bohren (von Hand)"]
        lines << '  Abstand von der Stufenvorderkante (rechtwinklig) und vom Stufenende (außen bzw. innen), mm.'
        lines << '  Gegenbohrung in der Auflagerkante der Wange: CNC (Bohraggregat) bzw. markiert.'
        list.group_by { |_, dw| dw[:k] }.sort.each do |k, l|
          l.sort_by! { |_, dw| dw[:front] }
          l.group_by { |jb, _| jb.sb[:which] }.sort_by { |w, _| w == :outer ? 0 : 1 }.each do |which, ll|
            dw0 = ll[0][1]
            lines << "  #{dw0[:label]} #{which == :outer ? 'außen' : 'innen'} (Wange #{ll.map { |jb, _| jb.label }.uniq.join(', ')}): " +
                     (ll.map { |_, dw| fmt(dw[:side] * 10.0, 0) }.uniq.size == 1 ?
                       ll.map { |_, dw| fmt(dw[:front] * 10.0, 0) }.join(' und ') + " von vorne, #{fmt(dw0[:side] * 10.0, 0)} vom Ende; " :
                       ll.map { |_, dw| "#{fmt(dw[:front] * 10.0, 0)}/#{fmt(dw[:side] * 10.0, 0)}" }.join(' und ') + ' (von vorne/vom Ende); ') +
                     "Ø #{fmt(dw0[:d] * 10.0)}, Tiefe #{ll.map { |_, dw| fmt(dw[:depth_t] * 10.0) }.uniq.join('/')} (Wange #{fmt(dw0[:depth_w] * 10.0)})"
          end
        end
        lines << ''
        lines
      end

      # Werkstattliste der Pfosten: Taschen (Stufen) und Bohrungen je Fläche
      def post_sheet(posts)
        lines = ['Geländerpfosten – Taschen und Bohrungen (mm, zur Kontrolle; gefräst in den Pfosten-TCN, je Fläche ein Programm)',
                 'Fläche 1–4: Pfostenquerschnitt gegen den Uhrzeigersinn (von oben), Richtung in Klammern.',
                 'a = Abstand von der linken Pfostenkante beim Blick auf die Fläche, z = Höhe ab Pfostenunterkante.',
                 'Richtungen bei Eckpfosten bezogen auf den ankommenden Lauf. Bohrungen rechtwinklig zur Fläche.', '']
        posts.each do |pt|
          l, s = pt.size
          lines << "#{pt.label}: #{pt.info} – Länge #{fmt(l, 0)} mm, Querschnitt #{fmt(s, 0)} × #{fmt(s, 0)} mm"
          pt.ops.group_by { |o| o[:face_name] }.each do |fn, list|
            lines << "  #{fn}"
            list.each do |o|
              lines << if o[:kind] == :pocket
                         "    Tasche #{o[:what]}: a #{fmt(o[:a0])}–#{fmt(o[:a1])}, z #{fmt(o[:z0])}–#{fmt(o[:z1])}, Tiefe #{fmt(o[:depth])}"
                       else
                         "    Bohrung #{o[:what]}: a #{fmt(o[:a])}, z #{fmt(o[:z])}, Ø #{fmt(o[:d])}, Tiefe #{fmt(o[:depth])}" +
                           (o[:into].to_f > 0 ? " (bis Taschengrund, in der Stufenstirn weiter #{fmt(o[:into])})" : '')
                       end
            end
          end
          lines << ''
        end
        lines
      end

      def fmt(v, dec = 1)
        format("%.#{dec}f", v.to_f).tr('.', ',')
      end

      # Daten für die Vorschau im Dialog
      def preview(res, o)
        {
          plate: [o['plate_l'], table_w(o)],
          margin: o['margin'],
          sheets: res.sheets.map do |sh|
            {
              thickness: sh.thickness, index: sh.index, count: sh.count,
              used: sh.used_len.round, util: (sh.util * 100).round(1),
              parts: sh.placements.map do |pl|
                { label: pl.part.label, kind: pl.part.kind.to_s, info: pl.part.info,
                  poly: pl.poly.map { |q| q.map { |v| v.round(1) } },
                  pockets: pl.pockets.map { |pc| pc.map { |q| q.map { |v| v.round(1) } } },
                  drills: (pl.drills || []).map { |h| [h[:x].round(1), h[:y].round(1), h[:d].round(1), h[:depth].round(1), h[:ang]] } }
              end
            }
          end,
          boards: (res.boards || []).map do |jb|
            sp = jb.splits && jb.splits[1]
            {
              label: jb.label, info: jb.info, thickness: jb.t, blank: jb.blank.map(&:round),
              outline: jb.outline.map { |q| q.map { |v| v.round(1) } },
              sides: jb.programs.size,
              runs: sp && sp[:runs] ? sp[:runs].size : 1, split: sp && sp[:x_t] ? sp[:x_t].round(1) : nil,
              walls: jb.walls.map do |w|
                { how: w[:how].to_s, rest: (w[:rest] || 0).round,
                  line: pv_line(jb, w[:u_top][0], w), line2: pv_line(jb, w[:u_top][1], w) }
              end,
              drills: jb.programs.flat_map { |pg| pg.drills || [] }.map { |h| [h[:x].round(1), h[:y].round(1), h[:d].round(1), h[:depth].round(1), h[:ang]] }
            }
          end + (res.longs || []).map do |lp|
            pg = lp.prog
            {
              label: lp.label, info: lp.part.info, thickness: lp.part.thickness, blank: lp.blank.map(&:round),
              outline: pg[:outline].map { |q| q.map { |v| v.round(1) } }, sides: 1, walls: [],
              runs: lp.split[:runs].size, split: lp.split[:x_t] ? lp.split[:x_t].round(1) : nil,
              paths: pg[:ops].reject { |op| op[:cut] || op[:k] != :mill }.map { |op| op[:pts].map { |q| q.map { |v| v.round(1) } } },
              drills: (pg[:drills] || []).map { |h| [h[:x].round(1), h[:y].round(1), h[:d].round(1), h[:depth].round(1), h[:ang]] }
            }
          end,
          unplaced: res.unplaced.map { |p| { label: p.label, size: p.size.map(&:round), thickness: p.thickness } },
          warnings: res.warnings,
          summary: summary(res, o)
        }
      end

      # Wandlinie für die Vorschau (auf das Material beschnitten)
      def pv_line(jb, u, w)
        seg = Wange3d.mark_lines(jb.sb_ctx, u, w[:z0], w[:z1], false, 1).max_by { |a, b| Geo.dist(a, b) }
        seg ||= Wange3d.mark_line(jb.sb_ctx, u, w[:z0], w[:z1])
        seg.map { |q| q.map { |v| v.round(1) } }
      end

      def summary(res, o)
        rows = []
        res.parts.group_by(&:kind).each do |k, list|
          rows << [Parts::KIND_NAMES[k] || k.to_s, list.size, list.map(&:thickness).uniq.map { |t| fmt(t) }.join(' / ') + ' mm']
        end
        by_t = res.sheets.group_by(&:thickness).map do |t, ss|
          area = ss.map { |s| s.placements.map { |pl| pl.part.area }.sum }.sum
          ["Platten #{fmt(t)} mm", ss.size, format('%.0f %% Ausnutzung', 100.0 * area / (ss.size * o['plate_l'] * table_w(o)))]
        end
        dr = res.parts.flat_map(&:drills)
        unless dr.empty?
          rows << ['Bohrungen (Geländerstäbe, Dübel)', dr.size,
                   dr.map { |h| "Ø #{fmt(h[:d])}" }.uniq.join(' / ') + ' mm' +
                   (dr.any? { |h| h[:ang] } ? (o['drill_wange'] == 'markieren' ? ', Wange markiert' : ', Wange mit Aggregat') : '')]
        end
        po = res.parts.select { |pt| pt.ops && !pt.ops.empty? }
        unless po.empty?
          rows << ['Pfosten mit Taschen/Bohrungen', po.size,
                   "#{po.sum { |pt| pt.ops.count { |x| x[:kind] == :pocket } }} Taschen, " \
                   "#{po.sum { |pt| pt.ops.count { |x| x[:kind] == :hole } }} Bohrungen (TCN je Fläche, Liste …_Pfosten_Bearbeitung.txt)"]
        end
        bs = res.boards || []
        unless bs.empty?
          rows << ['Aufgesattelte Wangen (3D, je ein Programm)', bs.size,
                   bs.sum { |b| b.programs.sum { |pg| (sp = b.splits && b.splits[pg.side]) && sp[:runs] ? sp[:runs].size : 1 } }.to_s + ' TCN' + (bs.any? { |b| b.programs.size > 1 } ? ' (mit Wenden)' : '')]
        end
        ls = res.longs || []
        nrun = bs.count { |b| b.splits && b.splits.values.any? { |sp| sp[:runs] && sp[:runs].size > 1 } } +
               ls.count { |lp| lp.split[:runs].size > 1 }
        unless ls.empty?
          rows << ['Wangen, Handläufe und Pfosten mit eigenem Rohling', ls.size, ls.sum(&:tcn_count).to_s + ' TCN']
        end
        nd = bs.sum { |b| (b.dowels || []).size }
        rows << ['Dübel Stufe – aufgesattelte Wange', nd, (o['drill_wange'] == 'markieren' ? 'Wange markiert' : 'Wange mit Aggregat') + ', Stufen von Hand (…_Nacharbeit.txt)'] if nd > 0
        ma = res.manual || []
        rows << ['Nicht gefräst (Stäbe, gerade Handläufe)', ma.size, 'Teileliste und …_Nacharbeit.txt'] unless ma.empty?
        rows << ['Überlange Wangen (2 Läufe, drehen)', nrun, "Verfahrweg #{fmt(o['mach_l'], 0)} mm"] if nrun > 0
        tools = res.sheets.map { |sh| [sh.thickness, sh.tool] } + bs.map { |b| [b.t, outer_tool(o, b.t)] } +
                ls.map { |lp| [lp.part.thickness, outer_tool(o, lp.part.thickness)] }
        tr = tools.uniq { |th, _| th }.sort_by(&:first).map do |th, tl|
          ["Außenkontur #{fmt(th)} mm", "Fräser #{tl[:nr]}", "Ø #{fmt(tl[:d], 2)} mm, Tiefe #{fmt(tl[:depth])} mm"]
        end
        rows + by_t + tr
      end
    end
  end
end
