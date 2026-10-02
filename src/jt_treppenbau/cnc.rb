# encoding: UTF-8
# Treppenbau – CNC-Export: Teile ermitteln, je Materialstärke verschachteln,
# TCN-Dateien und Teileliste schreiben. (ohne SketchUp-API)

module JTools
  module Treppenbau
    module Cnc
      module_function

      # Fräser Außenkontur wie in dxf4tcn (Werkzeugnummer => Name, Ø-Vorschlag)
      OUTER_TOOLS = [
        ['Diamant (1000)', 1000, 12.0],
        ['Wendeplatte (1300)', 1300, 12.0],
        ['8mm Diamant (2200)', 2200, 8.0]
      ].freeze

      DEFAULTS = {
        'plate_l'     => 2800.0,  # Rohplatte Länge (mm, X = Faserrichtung)
        'plate_w'     => 2070.0,  # Rohplatte Breite (mm)
        'margin'      => 10.0,    # Randabstand (mm)
        'tool_outer'  => 1000,    # Fräser Außenkontur (dxf4tcn)
        'tool_d'      => 12.0,    # Fräserdurchmesser (mm)
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
        'open_tpa'    => true     # erste TCN in TpaCAD öffnen (dxf4tcn)
      }.freeze

      Result = Struct.new(:sheets, :unplaced, :warnings, :parts)
      SheetInfo = Struct.new(:thickness, :index, :count, :placements, :used_len, :util)

      def normalize(h)
        o = DEFAULTS.dup
        (h || {}).each do |k, v|
          next unless o.key?(k)
          d = DEFAULTS[k]
          o[k] = if d == true || d == false
                   v == true || v.to_s == 'true'
                 elsif d.is_a?(Integer)
                   v.to_i
                 else
                   v.to_s.tr(',', '.').to_f
                 end
        end
        o
      end

      def gap(o)
        o['gap'].to_f > 0 ? o['gap'].to_f : o['tool_d'].to_f + 4.0
      end

      def compute(plan, params, o)
        parts, warnings = Parts.collect(plan, params,
                                        treads: o['p_treads'], risers: o['p_risers'],
                                        stringers: o['p_stringers'], posts: o['p_posts'],
                                        rail: o['p_rail'], einstand: o['einstand'], pocket_d: o['pocket_d'])
        warnings = warnings.dup
        g = gap(o)
        if o['margin'] < o['tool_d'] / 2.0
          warnings << 'Randabstand ist kleiner als der Fräserradius – Konturen am Rand werden angeschnitten.'
        end
        if o['einstand'] > 0 && params['construction'] == 'wange' && o['einstand'] >= params['str_t'] * 10 - 5
          warnings << 'Einstand (Nuttiefe) ist fast so groß wie die Wangendicke.'
        end
        sheets = []
        unplaced = []
        parts.group_by(&:thickness).sort.each do |th, list|
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
            sheets << SheetInfo.new(th, i + 1, nester.plates.size, sh.placements, sh.maxx, util)
          end
        end
        unless unplaced.empty?
          warnings << "#{unplaced.size} Teil(e) passen nicht auf die Rohplatte: " +
                      unplaced.map { |p| "#{p.label} (#{p.size.map { |v| v.round }.join('×')} mm)" }.first(8).join(', ')
        end
        Result.new(sheets, unplaced, warnings, parts)
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
                    tool_outer: o['tool_outer'], overcut: o['overcut'], climb: o['climb'],
                    deco_tool: o['deco_tool'], deco_depth: o['deco_depth'],
                    engrave: o['engrave'], text_h: o['text_h'],
                    pocket_tool: o['pocket_tool'], pocket_d: o['pocket_d'])
          files << path
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
                  pockets: pl.pockets.map { |pc| pc.map { |q| q.map { |v| v.round(1) } } } }
              end
            }
          end,
          unplaced: res.unplaced.map { |p| { label: p.label, size: p.size.map(&:round), thickness: p.thickness } },
          warnings: res.warnings,
          summary: summary(res, o)
        }
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
        rows + by_t
      end
    end
  end
end
