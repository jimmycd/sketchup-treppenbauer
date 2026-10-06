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
        'plate_w'     => 2070.0,  # Rohplatte Breite (mm)
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
        'drill_clear' => 5.0      # Anfahrabstand vor der Wangenkante (mm)
      }.freeze

      Result = Struct.new(:sheets, :unplaced, :warnings, :parts, :boards)
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

      def gap(o, d = o['tool_d'])
        o['gap'].to_f > 0 ? o['gap'].to_f : d.to_f + 4.0
      end

      def depth_warning(what, tl)
        return nil unless tl[:max] && tl[:depth] > tl[:max] + 1e-6
        "#{what}: Frästiefe #{fmt(tl[:depth])} mm größer als max. Schnitttiefe von Fräser #{tl[:nr]} " \
          "(#{fmt(tl[:max], 0)} mm)#{tl[:auto] ? ' – kein passender Fräser vorhanden' : ''}."
      end

      def compute(plan, params, o)
        parts, warnings = Parts.collect(plan, params,
                                        treads: o['p_treads'], risers: o['p_risers'],
                                        stringers: o['p_stringers'], posts: o['p_posts'],
                                        rail: o['p_rail'], einstand: o['einstand'], pocket_d: o['pocket_d'])
        warnings = warnings.dup
        # aufgesattelte Wangen mit 3D-Daten: eigenes Programm je Wange
        boards = []
        if o['p_stringers'] && params['construction'] == 'wange'
          boards = Wange3d.jobs(plan, params, o)
          lbls = boards.map(&:label)
          parts = parts.reject { |pt| pt.kind == :stringer && lbls.include?(pt.label) }
          boards.each { |b| warnings << b.summary if b.summary }
          long = boards.select { |b| b.raw_blank[0] > o['plate_l'] || b.raw_blank[1] > o['plate_w'] }
          unless long.empty?
            warnings << "Wangen-Rohling größer als Rohplatte/Tisch (#{o['plate_l'].round} × #{o['plate_w'].round} mm): " +
                        long.map { |b| "#{b.label} (#{b.raw_blank.map(&:round).join('×')} mm)" }.join(', ')
          end
          warnings << 'Einzelheiten zur Nacharbeit: Datei …_Wangen_Nacharbeit.txt beim Export.' if boards.any? { |b| !b.notes.empty? }
          o['sat_mode'] = 'fraesen' unless %w[fraesen markieren].include?(o['sat_mode'])
        end
        o['drill_wange'] = 'bohren' unless %w[bohren markieren].include?(o['drill_wange'])
        nh = parts.sum { |pt| pt.drills.count { |h| h[:ang] } }
        if nh > 0 && o['drill_wange'] == 'bohren'
          warnings << "#{nh} Bohrungen für Geländerstäbe in der Wangenoberkante (Bohraggregat, nach der Außenkontur): " \
                      'vor der Oberkante muss Platz für das Aggregat sein – Teileabstand prüfen oder „nur markieren“ wählen.'
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
        parts.group_by(&:thickness).sort.each do |th, list|
          tl = outer_tool(o, th)
          w = depth_warning("Platten #{fmt(th)} mm", tl)
          warnings << w if w
          g = gap(o, tl[:d])
          nester = Nester.new(length: o['plate_l'], width: o['plate_w'], margin: o['margin'],
                              gap: g, grid: o['grid'], grain: o['grain'])
          unless nester.usable?
            unplaced.concat(list)
            next
          end
          nester.nest(list)
          unplaced.concat(nester.unplaced)
          nester.plates.each_with_index do |sh, i|
            area = sh.placements.map { |pl| pl.part.area }.sum
            util = area / (o['plate_l'] * o['plate_w'])
            sheets << SheetInfo.new(th, i + 1, nester.plates.size, sh.placements, sh.maxx, util, tl)
          end
        end
        unless unplaced.empty?
          warnings << "#{unplaced.size} Teil(e) passen nicht auf die Rohplatte: " +
                      unplaced.map { |p| "#{p.label} (#{p.size.map { |v| v.round }.join('×')} mm)" }.first(8).join(', ')
        end
        Result.new(sheets, unplaced, warnings, parts, boards)
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
                    length: o['plate_l'], width: o['plate_w'], thickness: sh.thickness,
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
            path = File.join(dir, "#{base}_Wange_#{jb.label}_Seite#{pg.side}.tcn")
            Tcn.write_job(path, jb, pg,
                          tool_outer: outer_tool(o, jb.t)[:nr], overcut: o['overcut'], climb: o['climb'],
                          zstep: o['sat_zstep'],
                          deco_tool: o['deco_tool'], deco_depth: o['deco_depth'])
            files << path
            (bfiles[jb.label] ||= []) << File.basename(path)
          end
        end
        notes = (res.boards || []).flat_map(&:notes)
        unless notes.empty?
          txt = File.join(dir, "#{base}_Wangen_Nacharbeit.txt")
          File.open(txt, 'wb') do |io|
            io.write((["Aufgesattelte Wangen – Hinweise (#{res.boards.size} Wangen)", ''] + notes).join("\r\n").encode('Windows-1252', invalid: :replace, undef: :replace, replace: '_') + "\r\n")
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
          res.unplaced.each do |p|
            l, w = p.size
            rows << [p.id, p.label, p.info, fmt(p.thickness), fmt(l), fmt(w), fmt(p.area / 1e6, 3), 'NICHT PLATZIERT', '', '', '']
          end
          text = rows.map { |r| r.join(';') }.join("\r\n") + "\r\n"
          io.write(text.encode('Windows-1252', invalid: :replace, undef: :replace, replace: '_'))
        end
        files << csv
        files
      end

      def fmt(v, dec = 1)
        format("%.#{dec}f", v.to_f).tr('.', ',')
      end

      # Daten für die Vorschau im Dialog
      def preview(res, o)
        {
          plate: [o['plate_l'], o['plate_w']],
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
            {
              label: jb.label, info: jb.info, thickness: jb.t, blank: jb.blank.map(&:round),
              outline: jb.outline.map { |q| q.map { |v| v.round(1) } },
              sides: jb.programs.size,
              walls: jb.walls.map do |w|
                { how: w[:how].to_s, rest: (w[:rest] || 0).round,
                  line: pv_line(jb, w[:u_top][0], w), line2: pv_line(jb, w[:u_top][1], w) }
              end
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
          ["Platten #{fmt(t)} mm", ss.size, format('%.0f %% Ausnutzung', 100.0 * area / (ss.size * o['plate_l'] * o['plate_w']))]
        end
        dr = res.parts.flat_map(&:drills)
        unless dr.empty?
          rows << ['Bohrungen Geländerstäbe', dr.size,
                   dr.map { |h| "Ø #{fmt(h[:d])}" }.uniq.join(' / ') + ' mm' +
                   (dr.any? { |h| h[:ang] } ? (o['drill_wange'] == 'markieren' ? ', Wange markiert' : ', Wange mit Aggregat') : '')]
        end
        bs = res.boards || []
        unless bs.empty?
          rows << ['Aufgesattelte Wangen (3D, je ein Programm)', bs.size,
                   bs.sum { |b| b.programs.size }.to_s + ' TCN' + (bs.any? { |b| b.programs.size > 1 } ? ' (mit Wenden)' : '')]
        end
        tools = res.sheets.map { |sh| [sh.thickness, sh.tool] } + bs.map { |b| [b.t, outer_tool(o, b.t)] }
        tr = tools.uniq { |th, _| th }.sort_by(&:first).map do |th, tl|
          ["Außenkontur #{fmt(th)} mm", "Fräser #{tl[:nr]}", "Ø #{fmt(tl[:d], 2)} mm, Tiefe #{fmt(tl[:depth])} mm"]
        end
        rows + by_t + tr
      end
    end
  end
end
