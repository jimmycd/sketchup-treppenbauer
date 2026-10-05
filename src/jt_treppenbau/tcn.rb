# encoding: UTF-8
# Treppenbau – TCN-Ausgabe für TpaCAD (TPA\ALBATROS\EDICAD 02.00).
# Format, Kopf und Bearbeitungsblöcke wie dxf4tcn (TcnWriter):
#   * Gravur Teilenummern – Werkzeug r0 ("werkzeug"), Tiefe r1 ("zkontur")
#   * Nuten (Einstand)    – Nutfräser, exakte Ausstemmungskontur, konzentrisch
#                           ausgeräumt (innen -> außen, letzte Bahn = Kontur)
#   * Außenkonturen       – gewählter Fräser, durchgefräst, Korrektur außen,
#                           kleine Teile zuerst, immer zuletzt

module JTools
  module Treppenbau
    module Tcn
      module_function

      # Einstrich-Schrift (Raster 4 x 6), Linienzüge
      FONT = {
        '0' => [[[0, 0], [4, 0], [4, 6], [0, 6], [0, 0], [4, 6]]],
        '1' => [[[1, 5], [2, 6], [2, 0]], [[1, 0], [3, 0]]],
        '2' => [[[0, 6], [4, 6], [4, 3], [0, 3], [0, 0], [4, 0]]],
        '3' => [[[0, 6], [4, 6], [4, 0], [0, 0]], [[1, 3], [4, 3]]],
        '4' => [[[0, 6], [0, 3], [4, 3]], [[3, 6], [3, 0]]],
        '5' => [[[4, 6], [0, 6], [0, 3], [4, 3], [4, 0], [0, 0]]],
        '6' => [[[4, 6], [0, 6], [0, 0], [4, 0], [4, 3], [0, 3]]],
        '7' => [[[0, 6], [4, 6], [1, 0]]],
        '8' => [[[0, 0], [4, 0], [4, 6], [0, 6], [0, 0]], [[0, 3], [4, 3]]],
        '9' => [[[4, 3], [0, 3], [0, 6], [4, 6], [4, 0], [0, 0]]],
        'A' => [[[0, 0], [0, 4], [2, 6], [4, 4], [4, 0]], [[0, 3], [4, 3]]],
        'F' => [[[4, 6], [0, 6], [0, 0]], [[0, 3], [3, 3]]],
        'G' => [[[4, 6], [0, 6], [0, 0], [4, 0], [4, 3], [2, 3]]],
        'H' => [[[0, 0], [0, 6]], [[4, 0], [4, 6]], [[0, 3], [4, 3]]],
        'I' => [[[2, 0], [2, 6]], [[1, 0], [3, 0]], [[1, 6], [3, 6]]],
        'N' => [[[0, 0], [0, 6], [4, 0], [4, 6]]],
        'P' => [[[0, 0], [0, 6], [4, 6], [4, 3], [0, 3]]],
        'R' => [[[0, 0], [0, 6], [4, 6], [4, 3], [0, 3], [4, 0]]],
        'T' => [[[0, 6], [4, 6]], [[2, 6], [2, 0]]],
        'W' => [[[0, 6], [1, 0], [2, 3], [3, 0], [4, 6]]],
        '-' => [[[1, 3], [3, 3]]]
      }.freeze

      # opts: :length, :width, :thickness, :tool_outer, :overcut, :climb,
      #       :deco_tool, :deco_depth, :engrave, :text_h,
      #       :pocket_tool, :pocket_d, :comment
      def write(path, placements, opts)
        File.open(path, 'wb') do |io|
          text = build(placements, opts).join("\r\n") + "\r\n"
          io.write(text.encode('Windows-1252', invalid: :replace, undef: :replace, replace: '_'))
        end
        path
      end

      def build(placements, opts)
        ds = opts[:thickness].to_f
        out = []
        out << 'TPA\\ALBATROS\\EDICAD\\02.00:1224:r0w0h0s1'
        out << '::SIDE=1;'
        out << "::UNm DL=#{n(opts[:length])} DH=#{n(opts[:width])} DS=#{n(ds)}"
        out << "'tcn version=2.6.14"
        out << "'code=ansi"
        out << 'EXE{' << '#0=0' << '#1=0' << '#2=0' << '#3=0' << '#4=0' << '}EXE'
        out << 'OFFS{' << '#0=0|0' << '#1=0|0' << '#2=0|0' << '}OFFS'
        out << 'VARV{'
        ['1|1', '2|2', '3|3', '4|4', '0|0', '0|0', '0|0', '0|0'].each_with_index { |v, i| out << "##{i}=#{v}" }
        out << '}VARV'
        out << 'VAR{'
        out << "#0=#{n(opts[:deco_tool])}||r|f|werkzeug"
        out << "#1=#{n(-opts[:deco_depth].to_f.abs)}||r|f|zkontur"
        out << '}VAR'
        out << 'SPEC{' << '}SPEC' << 'INFO{' << '}INFO'
        out << 'OPTI{'
        out << ':: OPTDEF=1 OPTIMIZE=%;0 OPTMIN=0 OPT3=0 OPT0=0 OPTTOOL=0 OPT2=0 OPTX=0 OPTY=0 OPTR=0 ' \
               'OPT4=0 OPT6=0 OPT7=0 LSTCOD=0%1%2%3 LTOOLFR=0 LTOOLPN=0 OPTF1=0 OOO=0.5'
        out << '}OPTI' << 'LINK{' << '}LINK' << 'SIDE#0{' << '}SIDE'
        out << 'SIDE#1{'

        ws = 0
        # 1) Gravur
        if opts[:engrave]
          placements.each do |pl|
            label_strokes(pl, opts[:text_h].to_f).each do |stroke|
              ws += 1
              out << setup(ws, stroke.first, 'r1', 'r0', 0)
              lines(stroke).each { |l| out << l }
            end
          end
        end
        # 2) Nuten
        placements.each do |pl|
          next if pl.pockets.empty? || pl.part.pocket_depth <= 0
          paths = if pl.respond_to?(:paths) && pl.paths && !pl.paths.empty?
                    pl.paths
                  else
                    pl.pockets.map { |pk| pocket_path(pk, opts[:pocket_d].to_f) }
                  end
          paths.each do |path|
            next if path.size < 2
            ws += 1
            out << setup(ws, path.first, n(-pl.part.pocket_depth), n(opts[:pocket_tool]), 0)
            lines(path).each { |l| out << l }
          end
        end
        # 3) Außenkonturen – kleine Teile zuerst
        placements.sort_by { |pl| pl.part.area }.each do |pl|
          loop = orient(pl.poly, opts[:climb] ? :cw : :ccw)
          ws += 1
          out << setup(ws, loop.first, n(-(ds + opts[:overcut].to_f)), n(opts[:tool_outer]), opts[:climb] ? 1 : 2)
          lines(loop + [loop.first]).each { |l| out << l }
        end

        out << '}SIDE'
        (3..6).each { |s| out << "SIDE##{s}{" << '}SIDE' }
        out
      end

      # Ein Programm einer aufgesattelten Wange (Wange3d::Prog) – Rohling je Wange.
      # Reihenfolge (WS): Gravur/Markierung, Ausräumen, Schrägen (Hilfsflächen
      # GSIDE#7…, Seitenaggregat), Außenkontur zuletzt.
      def write_job(path, job, prog, opts)
        File.open(path, 'wb') do |io|
          text = build_job(job, prog, opts).join("\r\n") + "\r\n"
          io.write(text.encode('Windows-1252', invalid: :replace, undef: :replace, replace: '_'))
        end
        path
      end

      def build_job(job, prog, opts)
        t = job.t
        l, w = job.blank
        nf = prog.faces.size
        sides = [1] + (0...nf).map { |i| 7 + i }
        out = []
        out << 'TPA\\ALBATROS\\EDICAD\\02.00:1224:r0w0h0s1'
        out << "::SIDE=#{sides.map { |x| "#{x};" }.join}"
        out << "::UNm DL=#{n(l)} DH=#{n(w)} DS=#{n(t)}"
        out << "'tcn version=2.6.14"
        out << "'code=ansi"
        out << "'Treppenbau #{job.label} Seite #{prog.side}"
        out << 'EXE{' << '#0=0' << '#1=0' << '#2=0' << '#3=0' << '#4=0' << '}EXE'
        out << 'OFFS{' << '#0=0|0' << '#1=0|0' << '#2=0|0' << '}OFFS'
        out << 'VARV{'
        ['1|1', '2|2', '3|3', '4|4', '0|0', '0|0', '0|0', '0|0'].each_with_index { |v, i| out << "##{i}=#{v}" }
        out << '}VARV'
        out << 'VAR{'
        out << "#0=#{n(opts[:deco_tool])}||r|f|werkzeug"
        out << "#1=#{n(-opts[:deco_depth].to_f.abs)}||r|f|zkontur"
        out << '}VAR'
        out << 'SPEC{' << '}SPEC' << 'INFO{' << '}INFO'
        out << 'OPTI{'
        out << ':: OPTDEF=1 OPTIMIZE=%;0 OPTMIN=0 OPT3=0 OPT0=0 OPTTOOL=0 OPT2=0 OPTX=0 OPTY=0 OPTR=0 ' \
               'OPT4=0 OPT6=0 OPT7=0 LSTCOD=0%1%2%3 LTOOLFR=0 LTOOLPN=0 OPTF1=0 OOO=0.5'
        out << '}OPTI' << 'LINK{' << '}LINK'
        unless nf.zero?
          out << 'GEO{' << "::NF=#{nf}"
          prog.faces.each_with_index do |fc, i|
            out << "GSIDE##{7 + i}{"
            fc[:corners].each_with_index { |c, k| out << "##{k + 1}=#{n(c[0])}|#{n(c[1])}|#{n(c[2])}" }
            out << "#Z=#{n(fc[:depth_z])}" << '}GSIDE'
          end
          out << '}GEO'
        end
        out << 'SIDE#0{' << '}SIDE'
        ws = 0
        side1 = []
        contour = nil
        prog.ops.each do |kind, pts|
          next if pts.nil? || pts.size < 2
          case kind
          when :mark
            ws += 1
            side1 << setup(ws, pts.first, 'r1', 'r0', 0)
            side1.concat(lines(pts))
          when :clear
            [-(t / 2.0), -(t + opts[:overcut].to_f)].each do |z|
              ws += 1
              side1 << setup(ws, pts.first, n(z), n(opts[:tool_outer]), 0)
              side1.concat(lines(pts))
            end
          when :contour
            contour = pts
          end
        end
        agg = prog.faces.each_with_index.map do |fc, i|
          blk = ["SIDE##{7 + i}{", "$=Schraege Aggregat #{fc[:tool]}"]
          fc[:paths].each do |seq, depth|
            ws += 1
            blk << setup(ws, seq.first, n(depth), n(fc[:tool]), 0)
            blk.concat(lines(seq))
          end
          blk << '}SIDE'
        end
        if contour
          loop_ = orient(contour, opts[:climb] ? :cw : :ccw)
          ws += 1
          side1 << setup(ws, loop_.first, n(-(t + opts[:overcut].to_f)), n(opts[:tool_outer]), opts[:climb] ? 1 : 2)
          side1.concat(lines(loop_ + [loop_.first]))
        end
        out << 'SIDE#1{' << "$=#{job.label} Seite #{prog.side}"
        out.concat(side1)
        out << '}SIDE'
        (3..6).each { |sd| out << "SIDE##{sd}{" << '}SIDE' }
        agg.each { |blk| out.concat(blk) }
        out
      end

      def setup(ws, start, z, tool, comp)
        "W#89{ ::WTs WS=#{ws}  #8015=0 #1=#{n(start[0])} #2=#{n(start[1])} #3=#{z} " \
          "#201=1 #203=1 #205=#{tool} #1001=100 #8101=0 #8096=0 #40=#{comp} #46=1 " \
          '#8135=0 #8136=0 #8180=0 #8181=0 #8185=0 #8186=0 #9511=0 #9512=0 #9513=0 }W'
      end

      # relative Linien, kollineare Stücke zusammengefasst
      def lines(seq)
        vecs = []
        seq.each_cons(2) do |a, b|
          dx = b[0] - a[0]
          dy = b[1] - a[1]
          next if dx.abs < 1e-9 && dy.abs < 1e-9
          if (last = vecs.last)
            cross = last[0] * dy - last[1] * dx
            dot = last[0] * dx + last[1] * dy
            l1 = Math.hypot(*last)
            l2 = Math.hypot(dx, dy)
            if dot > 0 && (cross / (l1 * l2)).abs < 1e-7
              last[0] += dx
              last[1] += dy
              next
            end
          end
          vecs << [dx, dy]
        end
        # Rundung auf 0,01 mm mit Fehlerausgleich, damit Konturen exakt schließen
        acc = [0.0, 0.0]; done = [0.0, 0.0]
        vecs.map do |dx, dy|
          acc[0] += dx; acc[1] += dy
          rx = acc[0].round(2) - done[0]; ry = acc[1].round(2) - done[1]
          done[0] += rx; done[1] += ry
          "W#2201{ ::WTl  #8015=1 #1=#{n(rx)} #2=#{n(ry)} }W"
        end
      end

      # Kontur im/gegen den Uhrzeigersinn, Start in der Mitte der längsten Kante
      def orient(poly, dir)
        l = poly.dup
        ccw = Geo.signed_area(l) > 0
        l.reverse! if (dir == :cw && ccw) || (dir == :ccw && !ccw)
        i = (0...l.size).max_by { |k| Geo.dist(l[k], l[(k + 1) % l.size]) }
        a = l[i]; b = l[(i + 1) % l.size]
        mid = Geo.lerp(a, b, 0.5)
        [mid] + l.rotate(i + 1)
      end

      # Ausräumen einer (rechteckigen) Nut: Zickzack + Randbahn, ohne Korrektur
      def pocket_path(pk, d)
        xs = pk.map(&:first); ys = pk.map(&:last)
        x0 = xs.min; x1 = xs.max; y0 = ys.min; y1 = ys.max
        r = d / 2.0
        ix0 = x0 + r; ix1 = x1 - r; iy0 = y0 + r; iy1 = y1 - r
        if ix1 < ix0 && iy1 < iy0
          c = [(x0 + x1) / 2.0, (y0 + y1) / 2.0]
          return [c, [c[0] + 0.01, c[1]]]
        end
        if ix1 - ix0 < 0.01 || ix1 < ix0
          xm = (x0 + x1) / 2.0
          return [[xm, [iy0, iy1].min], [xm, [iy0, iy1].max]]
        end
        if iy1 - iy0 < 0.01 || iy1 < iy0
          ym = (y0 + y1) / 2.0
          return [[[ix0, ix1].min, ym], [[ix0, ix1].max, ym]]
        end
        step = d * 0.6
        path = []
        horiz = (ix1 - ix0) >= (iy1 - iy0)
        if horiz
          k = ((iy1 - iy0) / step).ceil
          (0..k).each do |i|
            y = iy0 + (iy1 - iy0) * i / [k, 1].max
            path.concat(i.even? ? [[ix0, y], [ix1, y]] : [[ix1, y], [ix0, y]])
          end
        else
          k = ((ix1 - ix0) / step).ceil
          (0..k).each do |i|
            x = ix0 + (ix1 - ix0) * i / [k, 1].max
            path.concat(i.even? ? [[x, iy0], [x, iy1]] : [[x, iy1], [x, iy0]])
          end
        end
        last = path[-1]
        ring = [[ix0, iy0], [ix1, iy0], [ix1, iy1], [ix0, iy1]]
        j = (0...4).min_by { |q| Geo.dist(ring[q], last) }
        ring = ring.rotate(j)
        path + ring + [ring[0]]
      end

      # Gravur-Linienzüge für die Teilenummer (zentriert auf dem Teil)
      def label_strokes(pl, text_h)
        txt = pl.part.label.to_s.upcase.chars.select { |c| FONT.key?(c) }
        return [] if txt.empty? || text_h <= 0
        xs = pl.poly.map(&:first); ys = pl.poly.map(&:last)
        bw = xs.max - xs.min; bh = ys.max - ys.min
        hgt = [text_h, bh * 0.35].min
        sc = hgt / 6.0
        adv = 6 * sc
        tw = txt.size * adv - 2 * sc
        hgt = 0 if tw > bw * 0.8
        return [] if hgt < 4
        c = inner_point(pl.poly)
        ox = c[0] - tw / 2.0; oy = c[1] - hgt / 2.0
        strokes = []
        txt.each_with_index do |ch, i|
          FONT[ch].each do |st|
            strokes << st.map { |gx, gy| [ox + i * adv + gx * sc, oy + gy * sc] }
          end
        end
        strokes
      end

      # Punkt im Inneren: Mitte der breitesten waagerechten Sehne auf Höhe des Schwerpunkts
      def inner_point(poly)
        a = 0.0; cx = 0.0; cy = 0.0
        poly.each_with_index do |p, i|
          q = poly[(i + 1) % poly.size]
          f = p[0] * q[1] - q[0] * p[1]
          a += f; cx += (p[0] + q[0]) * f; cy += (p[1] + q[1]) * f
        end
        return poly[0] if a.abs < 1e-9
        c = [cx / (3 * a), cy / (3 * a)]
        xs = []
        poly.each_with_index do |p, i|
          q = poly[(i + 1) % poly.size]
          next if (p[1] - c[1]) * (q[1] - c[1]) > 0 || p[1] == q[1]
          xs << p[0] + (c[1] - p[1]) / (q[1] - p[1]) * (q[0] - p[0])
        end
        xs.sort!
        return c if xs.size < 2
        best = xs.each_slice(2).select { |s| s.size == 2 }.max_by { |s0, s1| s1 - s0 }
        [(best[0] + best[1]) / 2.0, c[1]]
      end

      def n(v)
        v = v.to_f
        v = 0.0 if v.abs < 0.00005
        s = format('%.4f', v).sub(/\.?0+\z/, '')
        s == '-0' ? '0' : s
      end
    end
  end
end
