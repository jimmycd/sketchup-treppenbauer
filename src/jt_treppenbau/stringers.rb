# encoding: UTF-8
# Treppenbau – Wangen aus geraden Brettern (ohne SketchUp-API, testbar).
#
# Eingestemmte Wange:
#   * je Brett (im Grundriss gerade) ist die Oberkante eine Gerade, die die
#     Verbindungslinie der Stufenvorderkanten um str_over (lotrecht) überragt –
#     auf geraden Läufen exakt konstant, in Wendelbereichen mindestens;
#   * alle Bretter haben dieselbe Breite (rechtwinklig zur Kante gemessen);
#   * die Unterkante liegt an jeder Stufe mindestens str_under unter der
#     Stufenunterkante (hinteres Ende des Einstands) – darf variieren.
#   Brettbreite: str_h > 0 fest (mit Prüfung), 0 = kleinster passender Wert.
#   Stöße (Gehrung zwischen Brettern, Podeste): Ober- und Unterkante bündig –
#   Oberkante je Profilstück stetig (Fugenhöhen gemeinsam, an Podesten
#   Kröpfung im Podestbrett), Unterkante = Parallele im Abstand der Brettbreite.
#   Form „geschwungen“ (str_form = 'kurve'): Ober- und Unterkante sind – von
#   der Seite gesehen – stetige, knickfreie Kurven (monotone kubische
#   Hermite-Interpolation) je Laufabschnitt zwischen Podesten/Eckpfosten:
#     oben exakt str_over über jeder Stufenvorderkante (gerade Läufe: Gerade),
#     da monoton steigend liegt jede Trittstufe auf ganzer Tiefe mind. str_over
#     unter der Oberkante;
#     unten exakt str_under unter dem hinteren Ende jedes Einstands, monoton
#     steigend -> an keiner Stelle einer Stufe weniger als str_under.
#   Die Brettbreite ist dadurch variabel; Podeste bleiben eigene waagerechte
#   Bretter, die Bretter bleiben im Grundriss gerade (keine Biegung).
# Aufgesattelte Wange:
#   * liegt unter den Stufen, um sat_inset von der Laufkante nach innen versetzt;
#   * Oberkante sägezahnförmig (Auflager je Stufe, senkrechte Ausklinkung hinter
#     der Setzstufe bzw. unter der Unterschneidung);
#   * Unterkante je Brett gerade, sat_rest rechtwinklig unter den inneren Ecken.
#   Form „geschwungen“ (str_form = 'kurve'): Unterkante je Lauf (zwischen
#   Podesten) als knickfreie Kurve (monotone kubische Hermite-Interpolation)
#   durch die inneren Ecken minus sat_rest (rechtwinklig) – gerade Läufe
#   bleiben gerade, in Wendelbereichen variiert die Breite. An keiner inneren
#   Ecke weniger als sat_rest; Podestbretter bleiben waagerecht.
# Koordinaten im abgewickelten Brett: u = Parameter entlang der Begrenzungslinie
# (cm), z = Höhe (cm).

require_relative 'railing' unless defined?(JTools::Treppenbau::Railing)

module JTools
  module Treppenbau
    module Stringers
      module_function

      KINK = 0.0175 # ~1°

      def compute(plan, p)
        cache = plan.instance_variable_get(:@stringers)
        return cache if cache
        res = { wange: [], sattel: [], newels: [], width: 0.0, need: 0.0, warnings: [] }
        if p['construction'] == 'wange' && !plan.spiral
          wange(plan, p, res)
          sattel(plan, p, res)
        end
        plan.instance_variable_set(:@stringers, res)
        res
      end

      def kind(plan, p, which)
        Params.side_kind(p, which, plan.outer_side, !plan.spiral.nil?)
      end

      def side_of(plan, which)
        which == :outer ? plan.outer_side : -plan.outer_side
      end

      # Parameter einer Stufenlinie auf der Begrenzung
      def prm(plan, which, w)
        l = plan.line([[w, 0.0].max, plan.wtot].min)
        which == :outer ? l[:t] : l[:s]
      end

      # Zerlegt ein Profilstück an Knickstellen (und an den Linien mit Index
      # in split) in gerade Bretter.
      def boards(pc, split = [])
        out = []
        cur = [pc[0]]
        dir = nil
        (1...pc.size).each do |i|
          d = Geo.norm(Geo.sub(pc[i][0], pc[i - 1][0]))
          if (dir && Geo.cross(dir, d).abs > KINK) || (i > 1 && pc[i - 1][3] && split.include?(pc[i - 1][3]))
            out << cur
            cur = [pc[i - 1]]
          end
          cur << pc[i]
          dir = d
        end
        out << cur
        out.select { |b| b.size >= 2 && Geo.dist(b[0][0], b[-1][0]) > 0.05 }
      end

      # Niedrigste Gerade z = c + s·u oberhalb aller Punkte (kleinster
      # größter Abstand). Kollineare Punkte -> exakt durch die Punkte.
      def top_line(pts)
        pts = pts.sort_by(&:first)
        return [pts[0][1], 0.0] if pts.size == 1 || (pts[-1][0] - pts[0][0]).abs < 1e-9
        hull = []
        pts.each do |q|
          while hull.size >= 2
            a = hull[-2]; b = hull[-1]
            cr = (b[0] - a[0]) * (q[1] - a[1]) - (b[1] - a[1]) * (q[0] - a[0])
            break if cr < -1e-9
            hull.pop
          end
          hull << q
        end
        best = nil
        hull.each_cons(2) do |a, b|
          next if (b[0] - a[0]).abs < 1e-9
          s = (b[1] - a[1]) / (b[0] - a[0])
          c = a[1] - s * a[0]
          ex = pts.map { |u, z| c + s * u - z }
          next if ex.min < -1e-6
          best = [ex.max, c, s] if best.nil? || ex.max < best[0]
        end
        unless best
          s = (pts[-1][1] - pts[0][1]) / (pts[-1][0] - pts[0][0])
          c = pts.map { |u, z| z - s * u }.max
          return [c, s]
        end
        [best[1], best[2]]
      end

      # Höchste Gerade unterhalb aller Punkte
      def bottom_line(pts)
        c, s = top_line(pts.map { |u, z| [u, -z] })
        [-c, -s]
      end

      # Endnormale entlang einer (schrägen) Stufenlinie, so skaliert, dass der
      # rechtwinklige Versatz 1 beträgt.
      def along_line(lvec, seg_dir, side)
        n = side > 0 ? Geo.right(seg_dir) : Geo.left(seg_dir)
        l = Geo.norm(lvec)
        l = Geo.mul(l, -1) if Geo.dot(l, n) < 0
        c = Geo.dot(l, n)
        return n if c < 0.3
        Geo.mul(l, 1.0 / c)
      end

      # --- eingestemmte Wangen -------------------------------------------
      def wange(plan, p, res)
        over = p['str_over'].to_f
        under = p['str_under'].to_f
        d = p['tread_t'].to_f
        ext = p['nosing'].to_f + (p['risers'] ? p['riser_t'].to_f : 0.0)
        lw = plan.lines_w
        curve = p['str_form'] == 'kurve'
        zs = (0...plan.nlines).map { |k| plan.nose_z(k) + over }
        boards = []
        lists = []
        piece_lists = []
        side_lists = Hash.new { |h, k| h[k] = [] }
        need = 0.0
        %i[outer inner].each do |which|
          next unless kind(plan, p, which) == 'wange'
          side = side_of(plan, which)
          pieces = plan.profile(which, zs)
          piece_boards = []
          keys = plan.keys_for(which)
          landings = (0...plan.treads).select { |k| plan.kinds[k] == :landing }
          split = landings.flat_map { |k| [k, k + 1] }
          pieces.each_with_index do |pc, pi|
            bds = boards(pc, split)
            list = []
            bds.each_with_index do |bd, bi|
              u0 = bd[0][2]; u1 = bd[-1][2]
              # Podest: waagerechtes Brett (Podestoberfläche + Überstand)
              lk = landings.find { |k| u0 >= keys[k] - 1e-6 && u1 <= keys[k + 1] + 1e-6 }
              rq = if lk
                     [[u0, (lk + 1) * plan.h + over], [u1, (lk + 1) * plan.h + over]]
                   else
                     bd.map { |it| [it[2], it[1]] }
                   end
              c, s = top_line(rq)
              # Anforderungen unten: hinteres/vorderes Ende jeder Stufe minus Mindestabstand
              req = []
              steps = []
              (0...plan.treads).each do |k|
                ua = prm(plan, which, lw[k]); ub = prm(plan, which, [lw[k + 1] + ext, plan.wtot].min)
                a = [ua, u0].max; b = [ub, u1].min
                next if b - a < 0.01
                # an Innenecken trägt der Eckpfosten die über die Ecke laufende Stufe
                next if bi.zero? && pi > 0 && ua < u0 - 0.01
                next if bi == bds.size - 1 && pi < pieces.size - 1 && ub > u1 + 0.01
                zr = (k + 1) * plan.h - d - under
                req << [a, zr] << [b, zr]
                # hinteres Ende ohne Kappung am Austritt (für die Kurvenstützpunkte)
                ue = ub + [lw[k + 1] + ext - plan.wtot, 0.0].max
                steps << [k, a, b, zr, ue]
              end
              k1 = Math.sqrt(1.0 + s * s)
              nd = req.map { |u, zr| (c + s * u - zr) / k1 }.max || 0.0
              need = [need, nd].max
              base = bd.map(&:first)
              dir = Geo.norm(Geo.sub(base[-1], base[0]))
              list << { which: which, side: side, base: base, us: bd.map { |it| it[2] }, u0: u0, u1: u1, req: rq, req_bot: req, steps: steps,
                        keyed: bd.select { |it| it[3] }.map { |it| [it[2], it[1]] }, landing: lk,
                        c: c, s: s, dir: dir, piece: pi, idx0: bd[0][3], idx1: bd[-1][3] }
            end
            # Sehr kurze Bretter (z. B. kleine Podestverlängerung hinter einer Ecke)
            # mit dem in der Flucht liegenden Nachbarbrett vereinigen – sonst
            # überschneiden sich Gehrung und Brettende (fehler.md Nr. 6)
            list = merge_short(list, 1.5 * p['str_t'].to_f + 1.0)
            # Splitter (< 3 cm, z. B. minimale Podestverlängerung) weglassen
            list = list.reject { |b| b[:u1] - b[:u0] < 3.0 } if list.size > 1
            # Endnormalen: am Antritt/Austritt entlang der Stufenlinie, zwischen
            # Brettern rechtwinklig (Ecken: stumpfer Stoß, siehe butt_joints)
            list.each_with_index do |b, i|
              b[:n0] = line_normal(plan, b[:idx0], b[:dir], side) if i.zero? && b[:idx0]
              b[:n1] = line_normal(plan, b[:idx1], b[:dir], side) if i == list.size - 1 && b[:idx1]
            end
            if curve
              curve_piece(list, landings, plan)
            else
              straight_piece(list)
              lists << list
            end
            piece_boards << list
            piece_lists << list
            side_lists[which] << list
            boards.concat(list)
          end
          # Pfosten an Innenecken (zwischen den Profilstücken)
          piece_boards.each_cons(2) do |pa, pb|
            next if pa.empty? || pb.empty?
            ba = pa[-1]; bb = pb[0]
            res[:newels] << { which: which, side: side, pt: ba[:base][-1], na: Geo.norm(ba[:n1] || seg_n(ba, side)),
                              nb: Geo.norm(bb[:n0] || seg_n(bb, side)),
                              ztop: [top(ba, ba[:u1]), top(bb, bb[:u0])].max, a: ba, b: bb }
          end
        end
        need = (need * 2.0).ceil / 2.0
        if curve
          ws = boards.flat_map { |b| perp_widths(b) }
          res[:wange] = boards
          res[:width] = ws.max || 0.0
          res[:wmin] = ws.min || 0.0
          res[:need] = res[:width]
          res[:newels].each { |nw| nw[:zbot] = [[bot(nw[:a], nw[:a][:u1]), bot(nw[:b], nw[:b][:u0])].min, 0.0].max }
          joints(plan, p, res, side_lists)
          return
        end
        # gerade Wange: Unterkante = Parallele im Abstand der Brettbreite zur
        # (stetigen) Oberkante -> Stöße oben und unten bündig
        need = straight_need(lists)
        width = p['str_h'].to_f > 0 ? p['str_h'].to_f : need
        if p['str_h'].to_f > 0 && need > p['str_h'].to_f + 0.01
          res[:warnings] << format('Wangenhöhe %.1f cm zu gering – mindestens %.1f cm nötig (Mindestabstand unter den Stufen).', p['str_h'].to_f, need)
        end
        lists.each { |list| straight_bottom(list, width) }
        boards.each { |b| b[:w] = width }
        res[:newels].each { |nw| nw[:zbot] = [[bot(nw[:a], nw[:a][:u1]), bot(nw[:b], nw[:b][:u0])].min, 0.0].max }
        joints(plan, p, res, side_lists)
        res[:wange] = boards
        res[:width] = width
        res[:need] = need
      end

      # Kurzes Brett (Länge < lmin) mit kollinearem Nachbarn (gleiche Richtung im
      # Grundriss) zu einem Brett zusammenfassen. Das Ergebnis ist ein Laufbrett
      # (kein Podestbrett); seine Oberkante liegt über allen Anforderungen.
      def merge_short(list, lmin)
        loop do
          i = (0...list.size).find do |j|
            b = list[j]
            next false unless b[:u1] - b[:u0] < lmin
            [j - 1, j + 1].any? { |k| k >= 0 && k < list.size && Geo.dot(list[k][:dir], b[:dir]) > 1 - 1e-6 }
          end
          return list unless i
          b = list[i]
          k = [i + 1, i - 1].find { |j| j >= 0 && j < list.size && Geo.dot(list[j][:dir], b[:dir]) > 1 - 1e-6 }
          a, c = [i, k].min == i ? [b, list[k]] : [list[k], b]
          keep = a.equal?(b) ? c : a
          m = keep.dup
          m[:base] = a[:base] + c[:base][1..-1]
          m[:us] = a[:us] + c[:us][1..-1]
          m[:u0] = a[:u0]; m[:u1] = c[:u1]
          m[:req] = (a[:req] + c[:req]).sort_by(&:first)
          m[:req_bot] = a[:req_bot] + c[:req_bot]
          m[:steps] = a[:steps] + c[:steps]
          m[:keyed] = a[:keyed] + c[:keyed]
          m[:idx0] = a[:idx0]; m[:idx1] = c[:idx1]
          m[:c], m[:s] = top_line(m[:req])
          m[:dir] = Geo.norm(Geo.sub(m[:base][-1], m[:base][0]))
          lo = [i, k].min
          list = list[0...lo] + [m] + list[lo + 2..-1]
        end
      end

      # --- gerade Wange: bündige Stöße ------------------------------------
      #
      # Oberkante je Profilstück stetig (Polylinie b[:tv] je Brett):
      #   * Läufe aus mehreren Brettern (Wendelbereiche): gemeinsame Höhe an
      #     jeder Gehrungsfuge, je Brett gerade; Höhen so, dass die Fläche
      #     über den Stufenvorderkanten (+ Überstand) am kleinsten ist (LP).
      #   * Stöße an Podesten: die Oberkante knickt im Nachbarbrett in die
      #     Gerade des anderen Bretts ein (obere Hüllkurve, Kröpfung); sonst
      #     wird das niedrigere Brettende angehoben.
      # Die Unterkante ist die Parallele im Abstand der Brettbreite (Gehrung
      # an den Knicken) -> Ober- und Unterkante an jedem Stoß bündig.
      def straight_piece(list)
        runs = []
        list.each do |b|
          if b[:landing] || runs.empty? || runs[-1][-1][:landing] || b[:u0] > runs[-1][-1][:u1] + 0.01
            runs << [b]
          else
            runs[-1] << b
          end
        end
        list.each { |b| b[:tv] = [[b[:u0], b[:c] + b[:s] * b[:u0]], [b[:u1], b[:c] + b[:s] * b[:u1]]] }
        runs.each do |run|
          next if run.size < 2
          zs = joint_heights(run)
          next unless zs
          run.each_with_index { |b, i| b[:tv] = [[b[:u0], zs[i]], [b[:u1], zs[i + 1]]] }
        end
        list.each_cons(2) do |a, b|
          next if (b[:u0] - a[:u1]).abs > 0.01
          uj = a[:u1]
          za = a[:tv][-1][1]; zb = b[:tv][0][1]
          next if (za - zb).abs < 1e-6
          pa = a[:tv][-2]; qb = b[:tv][1]
          sa = (za - pa[1]) / (uj - pa[0])
          sb = (qb[1] - zb) / (qb[0] - b[:u0])
          if sb > sa + 1e-9
            ux = uj + (za - zb) / (sb - sa)
            if za < zb && ux > pa[0] + 0.01
              a[:tv] = a[:tv].select { |u, _| u < ux - 1e-6 } + [[ux, za + sa * (ux - uj)], [uj, zb]]
              next
            elsif za > zb && ux < qb[0] - 0.01
              b[:tv] = [[b[:u0], za], [ux, zb + sb * (ux - b[:u0])]] + b[:tv].select { |u, _| u > ux + 1e-6 }
              next
            end
          end
          if za < zb
            a[:tv][-1] = [uj, zb]
          else
            b[:tv][0] = [b[:u0], za]
          end
        end
      end

      # Höhen an den Fugen eines Laufs aus mehreren geraden Brettern:
      # Summe der größten Überstände je Brett möglichst klein (danach kleinste
      # Fläche), als lineares Programm in den Fugenhöhen z_j und je Brett
      # einem Überschuss E_i >= Oberkante - Anforderung.
      def joint_heights(run)
        k = run.size
        nv = 2 * k + 1
        rows = []
        run.each_with_index do |b, i|
          l = [b[:u1] - b[:u0], 1e-9].max
          b[:req].each do |u, z|
            t = [[(u - b[:u0]) / l, 0.0].max, 1.0].min
            co = Array.new(nv, 0.0)
            co[i] = 1.0 - t
            co[i + 1] = t
            rows << [co, z, i]
          end
        end
        return nil if rows.empty?
        lo = rows.map { |r| r[1] }.min - 1.0
        cons = []
        rows.each do |co, z, i|
          cons << [co, z - lo]
          ce = co.map { |v| -v }
          ce[k + 1 + i] = 1.0
          cons << [ce, lo - z]
        end
        len = run.map { |b| b[:u1] - b[:u0] }
        tot = len.sum
        wt = (0..k).map { |j| ((j > 0 ? len[j - 1] : 0.0) + (j < k ? len[j] : 0.0)) / 2.0 / tot * 0.01 + 1e-6 }
        y = lp_min(wt + Array.new(k, 1.0), cons)
        y && y[0..k].map { |v| v + lo }
      end

      # min c·y  mit  co·y >= r (alle Zeilen), y >= 0, c > 0.
      # Gelöst über das duale Problem (Simplex, Bland-Regel).
      def lp_min(c, rows)
        n = c.size; m = rows.size
        tab = (0...n).map do |j|
          rows.map { |co, _| co[j] } + Array.new(n) { |i| i == j ? 1.0 : 0.0 } + [c[j]]
        end
        obj = rows.map { |_, r| -r } + Array.new(n + 1, 0.0)
        basis = (0...n).map { |j| m + j }
        5000.times do
          e = (0...m + n).find { |q| obj[q] < -1e-10 }
          unless e
            return (0...n).map { |j| obj[m + j] }
          end
          best = nil
          (0...n).each do |i|
            a = tab[i][e]
            next if a <= 1e-12
            rt = tab[i][-1] / a
            best = [rt, basis[i], i] if best.nil? || rt < best[0] - 1e-12 || (rt < best[0] + 1e-12 && basis[i] < best[1])
          end
          return nil unless best
          r = best[2]
          pv = tab[r][e]
          tab[r] = tab[r].map { |v| v / pv }
          (0...n).each do |i|
            next if i == r || tab[i][e].abs < 1e-15
            f = tab[i][e]
            tab[i] = tab[i].each_with_index.map { |v, q| v - f * tab[r][q] }
          end
          f = obj[e]
          obj = obj.each_with_index.map { |v, q| v - f * tab[r][q] }
          basis[r] = e
        end
        nil
      end

      # Oberkante eines Profilstücks als zusammenhängende Polylinien
      def straight_chains(list)
        chains = []
        list.each do |b|
          if chains.empty? || (b[:u0] - chains[-1][-1][:u1]).abs > 0.01
            chains << [b]
          else
            chains[-1] << b
          end
        end
        chains.map do |ch|
          pts = ch.flat_map { |b| b[:tv] }
          pts = pts.each_with_object([]) { |q, o| o << q if o.empty? || q[0] - o[-1][0] > 1e-6 }
          [ch, pts]
        end
      end

      # Parallele im Abstand w unter der Polylinie pts (Gehrung an Knicken,
      # zu kurze Stücke an Innenknicken entfallen)
      def offset_down(pts, w)
        segs = pts.each_cons(2).map do |(u0, z0), (u1, z1)|
          s = (z1 - z0) / (u1 - u0)
          [s, z0 - s * u0 - w * Math.sqrt(1.0 + s * s)]
        end
        # kollineare Stücke zusammenfassen
        segs = segs.each_with_object([]) { |q, o| o << q unless o[-1] && (o[-1][0] - q[0]).abs < 1e-12 && (o[-1][1] - q[1]).abs < 1e-9 }
        ua = pts[0][0]; ub = pts[-1][0]
        loop do
          vs = [ua]
          segs.each_cons(2) do |(s1, c1), (s2, c2)|
            vs << ((s1 - s2).abs < 1e-12 ? vs[-1] : (c2 - c1) / (s1 - s2))
          end
          vs << ub
          bad = (0...segs.size).find { |j| vs[j + 1] < vs[j] - 1e-9 }
          if bad && segs.size > 1
            segs.delete_at(bad)
            next
          end
          return vs.each_with_index.map do |u, i|
            s, c = segs[[i, segs.size - 1].min]
            s, c = segs[i - 1] if i == segs.size
            [u, c + s * u]
          end
        end
      end

      def straight_bottom(list, w)
        straight_chains(list).each do |ch, pts|
          bl = offset_down(pts, w)
          ch.each do |b|
            inr = ->(u) { u > b[:u0] + 0.005 && u < b[:u1] - 0.005 }
            us = [b[:u0]] + (b[:tv].map(&:first) + bl.map(&:first)).select(&inr) + [b[:u1]]
            us = us.sort.each_with_object([]) { |u, o| o << u if o.empty? || u - o[-1] > 0.005 }
            us[-1] = b[:u1]
            b[:tp] = us.map { |u| [u, interp(b[:tv], u)] }
            b[:bp] = us.map { |u| [u, interp(bl, u)] }
            b[:s] = (b[:tp][-1][1] - b[:tp][0][1]) / [b[:u1] - b[:u0], 1e-9].max
            b[:c] = b[:tp][0][1] - b[:s] * b[:u0]
          end
        end
      end

      # kleinste Brettbreite (auf 0,5 cm gerundet), bei der die Unterkante an
      # jeder Stufe mindestens den Mindestabstand einhält
      def straight_need(lists)
        chains = lists.flat_map { |l| straight_chains(l) }
        ok = lambda do |w|
          chains.all? do |ch, pts|
            bl = offset_down(pts, w)
            ch.all? do |b|
              b[:steps].all? do |_k, a, e, zr|
                us = [a, e] + bl.map(&:first).select { |u| u > a && u < e }
                us.all? { |u| interp(bl, u) <= zr + 1e-9 }
              end
            end
          end
        end
        return 0.0 if ok.(0.0)
        lo = 0.0; hi = 50.0
        hi *= 2 until ok.(hi) || hi > 1000
        40.times do
          mid = (lo + hi) / 2
          ok.(mid) ? hi = mid : lo = mid
        end
        (hi * 2.0 - 1e-6).ceil / 2.0
      end

      def seg_n(b, side)
        side > 0 ? Geo.right(b[:dir]) : Geo.left(b[:dir])
      end

      def line_normal(plan, idx, dir, side)
        l = plan.line(plan.lines_w[idx])
        along_line(Geo.sub(l[:out], l[:in]), dir, side)
      end

      def top(b, u)
        return interp(b[:tp], u) if b[:tp]
        b[:c] + b[:s] * u
      end

      def bot(b, u)
        return interp(b[:bp], u) if b[:bp]
        top(b, u) - b[:w] * Math.sqrt(1.0 + b[:s]**2)
      end

      # lineare Interpolation in einer Stützpunktliste [[u, z], ...]
      def interp(pts, u)
        return pts[0][1] if u <= pts[0][0]
        return pts[-1][1] if u >= pts[-1][0]
        i = pts.bsearch_index { |q| q[0] >= u } || pts.size - 1
        i = 1 if i < 1
        a = pts[i - 1]; b = pts[i]
        du = b[0] - a[0]
        du.abs < 1e-12 ? b[1] : a[1] + (b[1] - a[1]) * (u - a[0]) / du
      end

      # --- geschwungene Wange (variable Breite) ---------------------------

      # Monotone kubische Hermite-Interpolation (Fritsch–Carlson).
      # Liefert Lambda u -> z; außerhalb linear mit Endsteigung fortgesetzt.
      # Kollineare Punkte ergeben exakt eine Gerade.
      def pchip(pts)
        x = pts.map(&:first); y = pts.map(&:last)
        n = x.size
        return ->(_u) { y[0] } if n == 1
        h = (0...n - 1).map { |i| x[i + 1] - x[i] }
        d = (0...n - 1).map { |i| (y[i + 1] - y[i]) / h[i] }
        m = Array.new(n, 0.0)
        m[0] = d[0]; m[-1] = d[-1]
        (1...n - 1).each do |i|
          if d[i - 1] * d[i] <= 0
            m[i] = 0.0
          else
            w1 = 2 * h[i] + h[i - 1]; w2 = h[i] + 2 * h[i - 1]
            m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])
          end
        end
        # Endsteigungen begrenzen (Monotonie)
        if n > 2
          [[0, 0], [n - 1, n - 2]].each do |i, j|
            m[i] = 0.0 if m[i] * d[j] <= 0
            m[i] = 3 * d[j] if d[j].abs > 1e-12 && m[i] / d[j] > 3
          end
        end
        # außerhalb: Steigung höchstens die mittlere Steigung (keine steilen Ausläufer)
        avg = (y[-1] - y[0]) / (x[-1] - x[0])
        e0 = avg >= 0 ? [m[0], avg].min : [m[0], avg].max
        e1 = avg >= 0 ? [m[-1], avg].min : [m[-1], avg].max
        lambda do |u|
          return y[0] + e0 * (u - x[0]) if u <= x[0]
          return y[-1] + e1 * (u - x[-1]) if u >= x[-1]
          i = x.bsearch_index { |q| q > u } - 1
          i = [[i, 0].max, n - 2].min
          t = (u - x[i]) / h[i]
          t2 = t * t; t3 = t2 * t
          (2 * t3 - 3 * t2 + 1) * y[i] + (t3 - 2 * t2 + t) * h[i] * m[i] +
            (-2 * t3 + 3 * t2) * y[i + 1] + (t3 - t2) * h[i] * m[i + 1]
        end
      end

      # Stützpunkte je u zusammenfassen (oben: höchster, unten: niedrigster Wert)
      def merge_nodes(pts, top)
        out = []
        pts.sort_by(&:first).each do |u, z|
          if out.empty? || u - out[-1][0] > 1e-3
            out << [u, z]
          else
            out[-1][1] = top ? [out[-1][1], z].max : [out[-1][1], z].min
          end
        end
        out
      end

      SAMPLE = 2.0 # cm Stützpunktabstand der Kurven

      # Kurven für alle Bretter eines Profilstücks. Läufe zwischen Podesten
      # bekommen je eine durchgehende Ober- und Unterkante (stetig über die
      # Gehrungsfugen), Podestbretter bleiben waagerecht.
      def curve_piece(list, _landings, _plan)
        runs = []
        list.each do |b|
          if b[:landing] || runs.empty? || runs[-1][-1][:landing] || b[:u0] > runs[-1][-1][:u1] + 0.01
            runs << [b]
          else
            runs[-1] << b
          end
        end
        prev_fb = nil
        runs.each do |run|
          u0 = run[0][:u0]; u1 = run[-1][:u1]
          # Oberkante: durch Stufenvorderkanten + Überstand
          tn = run.flat_map { |b| b[:landing] ? b[:req] : b[:keyed] }
          tn += [[u0, run[0][:req].min_by { |u, _| (u - u0).abs }[1]], [u1, run[-1][:req].min_by { |u, _| (u - u1).abs }[1]]] unless run[0][:landing]
          tn = merge_nodes(tn, true)
          ft = run[0][:landing] ? ->(_u) { tn.map(&:last).max } : pchip(tn)
          # Unterkante: hinteres Ende jedes Einstands minus Mindestabstand
          st = {}
          run.each do |b|
            b[:steps].each do |k, a, e, zr, ue|
              cur = st[k]
              st[k] = cur ? [[cur[0], a].min, [cur[1], e].max, zr, ue] : [a, e, zr, ue]
            end
          end
          land_fb = nil
          if run[0][:landing]
            # Podest: Unterkante schließt an die des vorangehenden Laufs an und
            # läuft knickfrei (kubisch, monoton) in die Waagerechte über.
            z1 = st.values.map { |v| v[2] }.min
            if prev_fb
              z0 = prev_fb.(u0)
              s0 = (z0 - prev_fb.(u0 - 0.5)) / 0.5
              z1 ||= z0
              if z1 > z0 + 1e-6 && s0 > 1e-6
                len = [u1 - u0, 2.0 * (z1 - z0) / s0].min
                land_fb = lambda do |u|
                  next z1 if u >= u0 + len
                  t = [(u - u0) / len, 0.0].max
                  t2 = t * t; t3 = t2 * t
                  (2 * t3 - 3 * t2 + 1) * z0 + (t3 - 2 * t2 + t) * len * s0 + (-2 * t3 + 3 * t2) * z1
                end
              else
                zc = [z0, z1].min
                land_fb = ->(_u) { zc }
              end
            elsif z1
              land_fb = ->(_u) { z1 }
            end
          end
          bn = if run[0][:landing]
                 []
               else
                 # ungekürztes hinteres Ende (auch jenseits des Laufendes) -> gerade
                 # Läufe bleiben exakt gerade
                 merge_nodes(st.values.map { |_a, _e, zr, ue| [ue, zr] }, false)
               end
          # z nicht fallend erzwingen (Monotonie => Mindestabstand überall)
          (bn.size - 2).downto(0) { |i| bn[i][1] = [bn[i][1], bn[i + 1][1]].min }
          fb = if land_fb
                 land_fb
               elsif bn.empty?
                 ->(u) { ft.(u) - 30.0 }
               elsif run[0][:landing] || bn.size == 1
                 zc = bn.map(&:last).min
                 ->(_u) { zc }
               else
                 pchip(bn)
               end
          # Kontrolle: an keiner Stelle einer Stufe weniger als der Mindestabstand
          # (Sicherheitsnetz: sonst ganze Unterkante des Abschnitts absenken)
          drop = 0.0
          st.each_value do |a, e, zr, _ue|
            n = [((e - a) / 1.0).ceil, 1].max
            (0..n).each { |i| drop = [drop, fb.(a + (e - a) * i / n) - zr].max }
          end
          fb0 = fb
          fb = ->(u) { fb0.(u) - drop } if drop > 1e-6
          prev_fb = fb
          run.each do |b|
            # Stützpunkte: Brettenden und Kurvenknoten exakt, dazwischen alle SAMPLE cm
            inr = ->(u) { u > b[:u0] + 0.005 && u < b[:u1] - 0.005 }
            keys = (tn.map(&:first) + bn.map(&:first)).select(&inr).sort
            keys = keys.each_with_object([]) { |u, o| o << u if o.empty? || u - o[-1] > 0.005 }
            n = [((b[:u1] - b[:u0]) / SAMPLE).ceil, 1].max
            smp = (1...n).map { |i| b[:u0] + (b[:u1] - b[:u0]) * i / n }.select(&inr)
            smp.reject! { |u| keys.any? { |k| (k - u).abs <= 0.02 } }
            us = [b[:u0]] + (keys + smp).sort + [b[:u1]]
            b[:tp] = us.map { |u| [u, ft.(u)] }
            b[:bp] = us.map { |u| [u, [fb.(u), ft.(u) - 1.0].min] }
            b[:s] = (b[:tp][-1][1] - b[:tp][0][1]) / [b[:u1] - b[:u0], 1e-9].max
            b[:c] = b[:tp][0][1] - b[:s] * b[:u0]
          end
          # Kontrolle mit der tatsächlich gezeichneten (linear interpolierten) Unterkante
          drop2 = 0.0
          run.each do |b|
            b[:steps].each do |_k, a, e, zr|
              (0..20).each { |i| drop2 = [drop2, bot(b, a + (e - a) * i / 20.0) - zr].max }
            end
          end
          if drop2 > 1e-9
            run.each { |b| b[:bp].each { |q| q[1] -= drop2 + 1e-7 } }
            fb1 = prev_fb
            prev_fb = ->(u) { fb1.(u) - drop2 - 1e-7 }
          end
          run.each do |b|
            ws = perp_widths(b)
            b[:w] = ws.max
          end
        end
      end

      # Brettbreite rechtwinklig zur Oberkante an den Stützpunkten
      def perp_widths(b)
        return [b[:w]] unless b[:tp]
        tp = b[:tp]
        tp.each_index.map do |i|
          j0 = [i - 1, 0].max; j1 = [i + 1, tp.size - 1].min
          du = tp[j1][0] - tp[j0][0]
          s = du.abs < 1e-9 ? 0.0 : (tp[j1][1] - tp[j0][1]) / du
          (tp[i][1] - b[:bp][i][1]) / Math.sqrt(1 + s * s)
        end
      end

      # Oberkante der Wange an Parameter u einer Seite (für Geländerpfosten)
      def top_at(plan, p, which, u)
        r = compute(plan, p)
        b = r[:wange].find { |x| x[:which] == which && u >= (x[:ru0] || x[:u0]) - 1e-6 && u <= (x[:ru1] || x[:u1]) + 1e-6 }
        b ? top(b, u) : nil
      end

      # Abgewickeltes Brett (u relativ zu u0, z) als Polygon, Unterkante am Boden gekappt
      def wange_outline(b)
        return curve_outline(b) if b[:tp]
        u0 = b[:u0]; u1 = b[:u1]
        poly = [[0.0, top(b, u0)], [u1 - u0, top(b, u1)]]
        b0 = bot(b, u0); b1 = bot(b, u1)
        poly << [u1 - u0, [b1, 0.0].max]
        if (b0 < 0) != (b1 < 0)
          f = (0 - b1) / (b0 - b1)
          poly << [(u1 - u0) * (1 - f), 0.0]
        end
        poly << [0.0, [b0, 0.0].max]
        Geo.clean_ring(poly, 0.01)
      end

      # Unterkante je Basispunkt inkl. Bodenschnitt (für 3D-Band)
      # Unterkante als Polylinie, am Boden (z = 0) gekappt, mit Schnittpunkten
      def clipped_bottom(b)
        out = []
        b[:bp].each_with_index do |(u, z), i|
          if i > 0
            pu, pz = b[:bp][i - 1]
            if (pz < 0) != (z < 0)
              f = pz / (pz - z)
              out << [pu + f * (u - pu), 0.0]
            end
          end
          out << [u, [z, 0.0].max]
        end
        out
      end

      def curve_outline(b)
        u0 = b[:u0]
        poly = b[:tp].map { |u, z| [u - u0, z] } + clipped_bottom(b).reverse.map { |u, z| [u - u0, z] }
        Geo.clean_ring(poly, 0.01)
      end

      def wange_band(b)
        return curve_band(b) if b[:tp]
        base = []; tops = []; bots = []
        us = [b[:u0], b[:u1]]
        b0 = bot(b, b[:u0]); b1 = bot(b, b[:u1])
        if (b0 < 0) != (b1 < 0)
          f = (0 - b0) / (b1 - b0)
          us = [b[:u0], b[:u0] + f * (b[:u1] - b[:u0]), b[:u1]]
        end
        us.each do |u|
          base << Geo.add(b[:base][0], Geo.mul(b[:dir], (u - b[:u0]) * Geo.dist(b[:base][0], b[:base][-1]) / (b[:u1] - b[:u0])))
          tops << top(b, u)
          bots << [bot(b, u), 0.0].max
        end
        [base, tops, bots]
      end

      def curve_band(b)
        bb = clipped_bottom(b)
        us = (b[:tp].map(&:first) + bb.map(&:first)).sort
        us = us.each_with_object([]) { |u, o| o << u if o.empty? || u - o[-1] > 0.02 }
        us[-1] = b[:u1]
        len = Geo.dist(b[:base][0], b[:base][-1])
        base = us.map { |u| Geo.add(b[:base][0], Geo.mul(b[:dir], (u - b[:u0]) * len / (b[:u1] - b[:u0]))) }
        [base, us.map { |u| top(b, u) }, us.map { |u| [bot(b, u), 0.0].max }]
      end

      # Stöße aller Wangenseiten: auf Geländerseiten sitzen die Pfosten
      # (Antritt, Austritt, Laufwechsel) als Zwischenstücke zwischen den
      # Brettern (post_joints), sonst stumpfer Stoß an den Ecken (butt_joints).
      # Die Eckpfosten an Innenecken entfallen auf Geländerseiten.
      def joints(plan, p, res, side_lists)
        t = p['str_t'].to_f
        posts = p['rail'] == 'keins' ? [] : Railing.sides(plan, p)
        side_lists.each do |which, lists|
          if posts.include?(which)
            post_joints(plan, p, which, lists.flatten(1), t)
          else
            lists.each { |list| butt_joints(list, t) }
          end
        end
        res[:newels].reject! { |nw| posts.include?(nw[:which]) }
      end

      # --- Pfosten als Zwischenstück ---------------------------------------
      #
      # bl: alle Bretter einer Seite in Laufrichtung. Lage der Pfosten aus
      # Railing.post_positions (u = Pfostenmitte auf der Begrenzung, Kante
      # newel_s). Bretter enden rechtwinklig an der Pfostenfläche:
      #   Antritt/Austritt – erstes Brett beginnt hinter, letztes endet vor dem Pfosten;
      #   Ecke   – Pfostenmitte im Schnitt der Wangenmittellinien, beide
      #            Bretter um je die halbe Pfostenkante zurückgesetzt;
      #   Podest – (gerades Zwischenpodest) Pfosten an der Podestvorderkante.
      # Ecken ohne Pfosten bleiben stumpf gestoßen.
      def post_joints(plan, p, which, bl, t)
        return if bl.empty?
        s = p['newel_s'].to_f
        bl.each { |b| b[:ru0] ||= b[:u0]; b[:ru1] ||= b[:u1] }
        done = {}
        Railing.post_positions(plan, p, which).each do |q|
          u = q[:u]
          case q[:role]
          when :antritt
            b = bl[0]
            sh = u + s / 2.0 - b[:u0]
            if sh > 0 && b[:u1] - b[:u0] - sh > 2.0
              shift_start(b, sh)
              b[:n0] = nil
            end
          when :austritt
            b = bl[-1]
            sh = u - s / 2.0 - b[:u1]
            if sh < 0 && b[:u1] - b[:u0] + sh > 2.0
              shift_end(b, sh)
              b[:n1] = nil
            end
          when :ecke, :podest
            corner = q[:role] == :ecke
            i = (0...bl.size - 1).select do |j|
              kink = Geo.cross(bl[j][:dir], bl[j + 1][:dir]).abs > KINK || Geo.dot(bl[j][:dir], bl[j + 1][:dir]) < 0
              kink == corner && !done[j]
            end.min_by { |j| (bl[j][:ru1] - (corner ? u : u - s / 2.0)).abs }
            next unless i
            ok = corner ? post_corner(bl[i], bl[i + 1], t, s) : post_inline(bl[i], bl[i + 1], u, s)
            done[i] = true if ok
          end
        end
        # verbleibende Ecken (ohne Pfosten): stumpf, unteres Brett gewinnt
        (0...bl.size - 1).each do |j|
          next if done[j]
          corner_joint(bl[j], bl[j + 1], t, :a)
        end
      end

      # Pfosten an einer Ecke zwischen Brett a (unten) und b (oben)
      def post_corner(a, b, t, s)
        da = a[:dir]; db = b[:dir]; side = a[:side]
        cr = Geo.cross(da, db)
        return false if cr.abs <= KINK
        # Schnitt der Wangenmittellinien = Pfostenmitte
        pa = Geo.add(a[:base][-1], Geo.mul(seg_n(a, side), t / 2.0))
        pb = Geo.add(b[:base][0], Geo.mul(seg_n(b, side), t / 2.0))
        dq = Geo.sub(pb, pa)
        x = Geo.cross(dq, db) / cr
        y = Geo.cross(dq, da) / cr
        sa = x - s / 2.0 # Ende von a (+ = länger)
        sb = y + s / 2.0 # Anfang von b (+ = kürzer)
        return false if a[:u1] + sa - a[:u0] < 2.0 || b[:u1] - b[:u0] - sb < 2.0
        shift_end(a, sa)
        shift_start(b, sb)
        a[:n1] = nil
        b[:n0] = nil
        true
      end

      # Pfosten in der Flucht (gerades Zwischenpodest): a endet vor, b beginnt
      # hinter dem Pfosten
      def post_inline(a, b, u, s)
        sa = u - s / 2.0 - a[:u1]
        sb = u + s / 2.0 - b[:u0]
        return false if a[:u1] + sa - a[:u0] < 2.0 || b[:u1] - b[:u0] - sb < 2.0
        shift_end(a, sa)
        shift_start(b, sb)
        a[:n1] = nil
        b[:n0] = nil
        true
      end

      # --- Stöße zwischen Brettern (stumpf, keine Gehrung) ----------------
      #
      # An jeder Ecke läuft ein Brett durch („gewinnt“), das andere stößt
      # rechtwinklig dagegen und ist um die Brettdicke gekürzt:
      #   * L-förmiger Verlauf: das von unten kommende Brett gewinnt;
      #   * U-förmiger Verlauf (Seite zwischen zwei Ecken, Nachbarseiten
      #     gegenläufig): die Bretter der Läufe gewinnen, der Querverbinder
      #     ist um beide Wangendicken gekürzt.
      # Stöße in gleicher Flucht (Podeste) bleiben rechtwinklig wie sie sind.
      # Das gewinnende Brett wird über die Ecke hinaus verlängert, Ober- und
      # Unterkante dort waagerecht (bündig mit dem Ende des anderen Bretts).
      def butt_joints(list, t)
        return if list.size < 2 || t <= 0
        # Seiten = Folgen von Brettern in gleicher Richtung (zusammenhängend)
        sides = [[list[0]]]
        list.each_cons(2) do |a, b|
          if Geo.cross(a[:dir], b[:dir]).abs > KINK || Geo.dot(a[:dir], b[:dir]) < 0
            sides << [b]
          else
            sides[-1] << b
          end
        end
        return if sides.size < 2
        quer = sides.each_index.map do |i|
          i > 0 && i < sides.size - 1 && Geo.dot(sides[i - 1][-1][:dir], sides[i + 1][0][:dir]) < -0.5
        end
        list.each { |b| b[:ru0] ||= b[:u0]; b[:ru1] ||= b[:u1] }
        sides.each_cons(2).with_index do |(sa, sb), i|
          winner = quer[i] && !quer[i + 1] ? :b : :a
          corner_joint(sa[-1], sb[0], t, winner)
        end
      end

      # Stumpfer Stoß an einer Ecke zwischen Brett a (unten) und b (oben);
      # winner :a / :b. Gilt für beliebige Winkel: das verlierende Brett liegt
      # mit seinem Ende an der Fläche des gewinnenden, dessen Ende bündig mit
      # der Fläche des verlierenden abschließt (bei 90° beide rechtwinklig).
      # gap: Abstand zwischen den Brettern (z. B. für ein späteres Zwischenstück).
      def corner_joint(a, b, t, winner, gap = 0.0, again = true)
        da = a[:dir]; db = b[:dir]; side = a[:side]
        cr = Geo.cross(da, db)
        return if cr.abs <= KINK
        # Eckpunkt = Schnitt der beiden Innenflächen
        pa = a[:base][-1]; pb = b[:base][0]
        dq = Geo.sub(pb, pa)
        x = Geo.cross(dq, db) / cr
        y = Geo.cross(dq, da) / cr
        na = seg_n(a, side); nb = seg_n(b, side)
        dan = [Geo.dot(da, nb).abs, 0.3].max
        dbn = [Geo.dot(db, na).abs, 0.3].max
        convex = cr * side > 0 # Wange außen um die Ecke
        ea, eb = if winner == :a
                   convex ? [t / dan, 0.0] : [0.0, t / dbn]
                 else
                   convex ? [0.0, -t / dbn] : [-t / dan, 0.0]
                 end
        if gap > 0
          ea -= gap / 2.0
          eb += gap / 2.0
        end
        sa = x + ea      # Ende von a verschieben (+ = länger)
        sb = eb + y      # Anfang von b verschieben (+ = kürzer)
        # zu kurzes Brett: Stoß tauschen (sonst rechtwinklig lassen)
        if a[:u1] + sa - a[:u0] < 2.0 || b[:u1] - b[:u0] - sb < 2.0
          return again ? corner_joint(a, b, t, winner == :a ? :b : :a, gap, false) : nil
        end
        shift_end(a, sa)
        shift_start(b, sb)
        a[:n1] = along_line(db, da, side)
        b[:n0] = along_line(da, db, side)
      end

      # Brettende um s verschieben (s > 0 verlängern, Kanten waagerecht)
      def shift_end(b, s)
        return if s.abs < 1e-6
        u1 = b[:u1] + s
        e = Geo.add(b[:base][-1], Geo.mul(b[:dir], s))
        keep = b[:us].each_index.select { |i| i.positive? && b[:us][i] < u1 - 1e-6 && i < b[:us].size - 1 }
        b[:base] = [b[:base][0]] + keep.map { |i| b[:base][i] } + [e]
        b[:us] = [b[:us][0]] + keep.map { |i| b[:us][i] } + [u1]
        %i[tp bp].each do |k|
          pts = b[k]
          b[k] = if s > 0
                   pts + [[u1, pts[-1][1]]]
                 else
                   pts.select { |u, _| u < u1 - 1e-6 } + [[u1, interp(pts, u1)]]
                 end
        end
        b[:ext1] = [s, 0.0].max
        b[:u1] = u1
      end

      # Brettanfang um s verschieben (s > 0 kürzen, s < 0 verlängern)
      def shift_start(b, s)
        return if s.abs < 1e-6
        u0 = b[:u0] + s
        st = Geo.add(b[:base][0], Geo.mul(b[:dir], s))
        keep = b[:us].each_index.select { |i| i.positive? && i < b[:us].size - 1 && b[:us][i] > u0 + 1e-6 }
        b[:base] = [st] + keep.map { |i| b[:base][i] } + [b[:base][-1]]
        b[:us] = [u0] + keep.map { |i| b[:us][i] } + [b[:us][-1]]
        %i[tp bp].each do |k|
          pts = b[k]
          b[k] = if s < 0
                   [[u0, pts[0][1]]] + pts
                 else
                   [[u0, interp(pts, u0)]] + pts.select { |u, _| u > u0 + 1e-6 }
                 end
        end
        b[:ext0] = [-s, 0.0].max
        b[:u0] = u0
      end

      # Brett als Körper aus zwei Flächenumrissen (für Builder#lprism):
      # Innenfläche auf der Begrenzungslinie, Außenfläche um t rechtwinklig
      # versetzt. Ober- und Unterkante hängen nur von der Lage entlang des
      # Bretts ab -> Ober- und Unterseite stehen rechtwinklig zur Brettfläche
      # (keine verwundenen Flächen, mit 3-/4-Achs-CNC fräsbar); die Enden
      # sind senkrechte Ebenen (Stoß, Stufenlinie am Antritt/Austritt).
      # Liefert [origin (Mittelfläche bei x = 0), dir, pa (−t/2), pb (+t/2)].
      def wange_faces(b, t)
        dir = b[:dir]; u0 = b[:u0]
        len = b[:u1] - u0
        pn = seg_n(b, b[:side])
        dx = ->(n) { n ? Geo.dot(n, dir) / Geo.dot(n, pn) * t : 0.0 }
        xin = [0.0, len]
        xout = [dx.(b[:n0]), len + dx.(b[:n1])]
        lo = [xin[0], xout[0]].max + 0.01
        hi = [xin[1], xout[1]].min - 0.01
        xs = (b[:tp].map(&:first) + clipped_bottom(b).map(&:first)).map { |u| u - u0 }.select { |v| v > lo && v < hi }.sort
        xs = xs.each_with_object([]) { |v, o| o << v if o.empty? || v - o[-1] > 0.005 }
        face = lambda do |x0, x1|
          xx = [x0] + xs + [x1]
          bo = xx.map { |v| [bot(b, u0 + v), 0.0].max }
          tp = xx.each_with_index.map { |v, i| [v, [top(b, u0 + v), bo[i] + 0.5].max] }
          tp + xx.each_with_index.map { |v, i| [v, bo[i]] }.reverse
        end
        fin = face.(*xin); fout = face.(*xout)
        origin = Geo.add(b[:base][0], Geo.mul(pn, t / 2.0))
        # Innenfläche liegt bei −t/2 entlang Geo.right(dir), wenn die Wange rechts liegt
        pa, pb = b[:side] > 0 ? [fin, fout] : [fout, fin]
        [origin, dir, pa, pb]
      end

      # --- aufgesattelte Wangen ------------------------------------------
      def sattel(plan, p, res)
        t = p['sat_t'].to_f; rest = p['sat_rest'].to_f; inset = p['sat_inset'].to_f
        d = p['tread_t'].to_f
        cut_ext = p['nosing'].to_f + (p['risers'] ? p['riser_t'].to_f : 0.0)
        lw = plan.lines_w
        curve = p['str_form'] == 'kurve'
        %i[outer inner].each do |which|
          next unless kind(plan, p, which) == 'sattel'
          side = side_of(plan, which)
          src = []
          plan.send(which).pts.each { |q| src << q if src.empty? || Geo.dist(src[-1], q) > 0.01 }
          next if src.size < 2
          mn = Geo.miter_normals(src, side)
          off = inset + t / 2.0
          sp = Polyline.new(src.each_with_index.map { |q, i| Geo.add(q, Geo.mul(mn[i], -off)) })
          last = 0.0
          vat = lambda do |w|
            l = plan.line([[w, 0.0].max, plan.wtot].min)
            hit = which == :outer ? sp.ray_hit(l[:in], Geo.sub(l[:out], l[:in])) : sp.ray_hit(l[:out], Geo.sub(l[:in], l[:out]))
            last = [hit ? hit[1] : last, last].max
          end
          cuts = (0...plan.treads).map { |k| vat.(lw[k] + cut_ext) }
          v_end = vat.(plan.wtot)
          # Stufenlinien der Ausklinkungen (Grundriss) und Austrittslinie –
          # für die Lage auf den beiden Brettflächen (schräge Stöße)
          clines = (0...plan.treads).map { |k| plan.line([lw[k] + cut_ext, plan.wtot].min) }
          # Tritt- und Setzstufen als Hindernisse (Grundriss, Unterseite)
          obst = (0...plan.treads).map { |k| [plan.region(lw[k], [lw[k + 1] + cut_ext, plan.wtot].min).map(&:first), (k + 1) * plan.h - d] }
          if p['risers']
            (0...plan.treads).each do |k|
              wa = lw[k] + p['nosing'].to_f
              obst << [plan.region(wa, wa + p['riser_t'].to_f).map(&:first), k * plan.h]
            end
          end
          eline = plan.line(plan.wtot)
          zt = (0...plan.treads).map { |k| (k + 1) * plan.h - d }
          # innere Ecken für die Restbreite an der hinteren der beiden
          # Flächenlagen (Unterkante steigt -> dort ist der Abstand kleiner)
          fpl = [-1, 1].map { |g| src.each_with_index.map { |q, i| Geo.add(q, Geo.mul(mn[i], -(off + g * t / 2.0))) } }
          # vordere Lage zusätzlich, wo die Unterkante fällt (Stoß an der Ecke,
          # kurzer Schenkel einer Drachenstufe dicht dahinter)
          chl = (0...plan.treads).map do |k|
            l = clines[k]
            o_, dv = which == :outer ? [l[:in], Geo.sub(l[:out], l[:in])] : [l[:out], Geo.sub(l[:in], l[:out])]
            ([cuts[k]] + fpl.map { |fp| face_hit(fp, sp, o_, dv) }.compact).minmax
          end
          chi = chl.map(&:last)
          corners = (0...plan.treads - 1).map { |k| [chi[k + 1], zt[k]] } + [[v_end, zt[-1]]]
          # zusätzliche Bedingungen für den Anschluss an Ecken (sat_slope), nicht für die Ausgleichsgerade
          corners_r = (0...plan.treads - 1).flat_map { |k| [[chl[k + 1][0], zt[k]], [chi[k + 1], zt[k]]].uniq } + [[v_end, zt[-1]]]
          # gerade Abschnitte der Mittellinie
          segs = []
          pts = sp.pts; cum = sp.cum
          start = 0
          (1...pts.size - 1).each do |i|
            d0 = Geo.norm(Geo.sub(pts[i], pts[i - 1])); d1 = Geo.norm(Geo.sub(pts[i + 1], pts[i]))
            if Geo.cross(d0, d1).abs > KINK
              segs << [cum[start], cum[i]]
              start = i
            end
          end
          segs << [cum[start], cum[-1]]
          # an Podesten teilen (Podest = eigenes waagerechtes Brett)
          lks = (0...plan.treads).select { |k| plan.kinds[k] == :landing }
          lks.flat_map { |k| [cuts[k], k + 1 < cuts.size ? cuts[k + 1] : v_end] }.each do |sv|
            segs = segs.flat_map { |a, b| sv > a + 0.5 && sv < b - 0.5 ? [[a, sv], [sv, b]] : [[a, b]] }
          end
          # Bretter (Mittellinie v0..v1) mit Unterkanten-Gerade F
          recs = []
          segs.each do |va, vb|
            v0 = [va, cuts[0]].max; v1 = [vb, v_end].min
            next if v1 - v0 < 1.0
            lk = lks.find { |k| v0 >= cuts[k] - 0.01 && v1 <= (k + 1 < cuts.size ? cuts[k + 1] : v_end) + 0.01 }
            cs = if lk
                   [[v0, zt[lk]], [v1, zt[lk]]]
                 else
                   corners.select { |v, _| v >= v0 - 0.01 && v <= v1 + 0.01 }
                 end
            if cs.size < 2
              before = corners.select { |v, _| v < v0 - 0.01 }.last
              after = corners.find { |v, _| v > v1 + 0.01 }
              cs = ([before] + cs + [after]).compact
            end
            next if cs.empty?
            c, s = cs.size == 1 ? [cs[0][1], 0.0] : bottom_line(cs)
            c -= rest * Math.sqrt(1 + s * s)
            cr = lk ? cs : (cs + corners_r.select { |v, _| v >= v0 - 0.01 && v <= v1 + 0.01 }).uniq
            recs << { v0: v0, v1: v1, a: v0, b: v1, cs: cs, cr: cr, f: [c, s], ops: [], landing: lk,
                      dir: Geo.norm(Geo.sub(sp.at(v1), sp.at(v0))) }
          end
          # Ecken (Knick zwischen zwei Brettern): immer stumpfer Stoß ohne
          # Durchdringung, keine Gehrung. Unterkante des oberen Bretts beginnt
          # auf Höhe der Unterkante des unteren Bretts.
          # Gewinner je Ecke wie bei der eingestemmten Wange (butt_joints):
          # L-förmig das untere Brett, U-förmig die Läufe (Querverbinder um
          # beide Dicken gekürzt).
          sides = [[recs[0]]]
          recs.each_cons(2) do |ra, rb|
            kink = Geo.cross(ra[:dir], rb[:dir]).abs > KINK || Geo.dot(ra[:dir], rb[:dir]) < 0
            kink ? sides << [rb] : sides[-1] << rb
          end
          quer = sides.each_index.map do |i|
            i > 0 && i < sides.size - 1 && Geo.dot(sides[i - 1][-1][:dir], sides[i + 1][0][:dir]) < -0.5
          end
          side_of_rec = {}
          sides.each_with_index { |sd, i| sd.each { |r| side_of_rec[r.object_id] = i } }
          recs.each_cons(2) do |ra, rb|
            # (ein sehr kurzes, weggelassenes Stück dazwischen ist erlaubt)
            next unless rb[:v0] - ra[:v1] < 1.5
            cr = Geo.cross(ra[:dir], rb[:dir])
            next if cr.abs <= KINK
            sn = [cr.abs, 0.3].max
            cs_ = Geo.dot(ra[:dir], rb[:dir]).abs
            # Schnittpunkt der beiden Mittellinien
            pa = sp.at(ra[:v1]); pb = sp.at(rb[:v0]); dq = Geo.sub(pb, pa)
            xa = Geo.cross(dq, rb[:dir]) / cr
            yb = Geo.cross(dq, ra[:dir]) / cr
            i = side_of_rec[ra.object_id]
            if quer[i] && !quer[i + 1]
              # oberes Brett läuft durch, unteres stößt an
              ra[:b] = ra[:v1] + xa - t / 2.0 * (1.0 + cs_) / sn
              rb[:a] = rb[:v0] + yb - t / 2.0 / sn
              ra[:end_f] = [-1, 1].map { |f| [-1, 1].map { |g| board_cross(sp, ra, f * t / 2.0, board_face(sp, rb, g * t / 2.0)) }.compact.min }
              rb[:start_f] = [-1, 1].map { |f| [-1, 1].map { |g| board_cross(sp, rb, f * t / 2.0, board_face(sp, ra, g * t / 2.0)) }.compact.min }
            else
              # unteres Brett läuft bis zur Außenfläche des oberen durch, das
              # obere stößt an die Seitenfläche des unteren (schräge Enden, passgenau)
              ra[:b] = ra[:v1] + xa + t / 2.0 / sn
              rb[:a] = rb[:v0] + yb + t / 2.0 * (1.0 + cs_) / sn
              ra[:end_f] = [-1, 1].map { |f| [-1, 1].map { |g| board_cross(sp, ra, f * t / 2.0, board_face(sp, rb, g * t / 2.0)) }.compact.max }
              rb[:start_f] = [-1, 1].map { |f| [-1, 1].map { |g| board_cross(sp, rb, f * t / 2.0, board_face(sp, ra, g * t / 2.0)) }.compact.max }
            end
            rb[:joint] = ra
          end
          # über die Ecke verlängertes Brett (oberes gewinnt): Ausklinkungen im
          # verlängerten Bereich gehören auch zu den Restbreiten-Ecken
          recs.each do |r|
            next unless r[:a] < r[:v0] - 0.01 || r[:b] > r[:v1] + 0.01
            ext = (corners + corners_r).select do |v, _|
              (v >= r[:a] - 0.01 && v < r[:v0] - 0.01) || (v > r[:v1] + 0.01 && v <= r[:b] + 0.01)
            end
            r[:cr] = (r[:cr] + ext).uniq
          end
          # verlierendes Brett so kurz, dass es entfällt (z. B. Podeststück
          # am Querverbinder): Unterkante an das davor liegende Brett anschließen
          recs.each do |r|
            ra = r[:joint]
            next unless ra && ra[:b] - ra[:a] < 1.0
            i = recs.index { |x| x.equal?(ra) }
            prev = i && i > 0 ? recs[i - 1] : nil
            next unless prev && ra[:v0] - prev[:v1] < 1.5
            r[:joint] = prev
            # das davor liegende Brett endet dann an derselben Stelle
            if ra[:b] < prev[:b]
              prev[:b] = ra[:b]
              prev[:end_f] = ra[:end_f] if ra[:end_f]
            end
          end
          sat_curve(recs, corners, rest) if curve
          recs.each do |r|
            ra = r[:joint]
            next unless ra && !curve
            vp = r[:a]
            zp = sat_bottom(ra, ra[:b])
            fz = r[:f][0] + r[:f][1] * vp
            next if (zp - fz).abs < 1e-6
            sl = zp > fz ? sat_slope(r[:cr], vp, zp, rest, 1) : nil
            if zp > fz && sl.nil?
              # zu hoch für das obere Brett: höchste mögliche Höhe, unteres
              # Brett am Ende entsprechend absenken
              lo = fz; hi = zp
              40.times do
                m = (lo + hi) / 2.0
                sat_slope(r[:cr], vp, m, rest, 1) ? lo = m : hi = m
              end
              zp = lo
              sa = sat_slope(ra[:cr], ra[:b], zp, rest, -1)
              ra[:ops] << [:min, [zp - sa * ra[:b], sa]] if sa
            end
            sl = sat_slope(r[:cr], vp, zp, rest, 1)
            next unless sl
            r[:ops] << [zp > fz ? :max : :min, [zp - sl * vp, sl]]
          end
          # Geländerseite: Antritts- und Austrittspfosten stehen in der Treppe
          # (wie bei der eingestemmten Wange), die Wange stößt an den Pfosten
          if !recs.empty? && p['rail'] != 'keins' && Railing.sides(plan, p).include?(which)
            va, vb = sat_post_cut(plan, p, which, sp, side)
            recs[0][:a] = [recs[0][:a], va].max if va && va < recs[0][:b] - 2.0
            recs[-1][:b] = [recs[-1][:b], vb].min if vb && vb > recs[-1][:a] + 2.0
          end
          no = 0
          recs.each do |r|
            v0 = r[:a]; v1 = r[:b]
            next if v1 - v0 < 1.0 # durch den Stoß entfallenes Reststück
            ztop_at = lambda do |v, after|
              k = cuts.rindex { |cv| after ? cv <= v + 1e-9 : cv < v - 1e-9 }
              k ? zt[k] : 0.0
            end
            top = [[v0, ztop_at.(v0, true)]]
            cuts.each_with_index do |cv, k|
              # (gekürztes Brett, Querverbinder: nur bis zum Brettende v1)
              next unless cv > v0 + 1e-6 && cv < [r[:v1], v1].min - 1e-6
              top << [cv, k > 0 ? zt[k - 1] : 0.0] << [cv, zt[k]]
            end
            top << [r[:v1], ztop_at.(r[:v1], false)] if v1 > r[:v1] + 1e-6
            top << [v1, ztop_at.([r[:v1], v1].min, false)]
            if r[:bf]
              bp = sat_samples(r).map { |v| [v, r[:bf].(v)] }
            else
              lines = [r[:f]] + r[:ops].map { |o| o[1] }
              us = [v0, v1]
              lines.combination(2) do |(c1, s1), (c2, s2)|
                next if (s1 - s2).abs < 1e-12
                x = (c2 - c1) / (s1 - s2)
                us << x if x > v0 + 1e-6 && x < v1 - 1e-6
              end
              us = us.sort
              bp = us.map { |v| [v, sat_bottom(r, v)] }
            end
            bc = [bp[0]]
            bp.each_cons(2) do |(ua, za), (ub, zb)|
              bc << [ua + (ub - ua) * za / (za - zb), 0.0] if (za < 0) != (zb < 0)
              bc << [ub, zb]
            end
            bot = bc.map { |v, z| [v, [z, 0.0].max] }.reverse
            poly = Geo.clean_ring((top + bot).map { |v, z| [v - v0, z] }, 0.01)
            next if poly.size < 3 || Geo.signed_area(poly).abs < 1.0
            no += 1
            o = Geo.add(sp.at(r[:v0]), Geo.mul(r[:dir], v0 - r[:v0]))
            faces = sat_face_polys(sp, r, top, bot, cuts, clines, eline, v_end, t, obst)
            sb = { which: which, side: side, origin: o, dir: r[:dir], len: v1 - v0,
                   poly: poly, t: t, nr: no }
            if faces
              sb[:ntop] = faces.pop
              sb[:faces] = faces.map { |fp| fp.map { |v, z| [v - v0, z] } }
            else
              res[:warnings] << 'Aufgesattelte Wange: schräge Stöße an einem Brett nicht darstellbar – senkrecht an der hinteren Lage geschnitten.' unless res[:warnings].any? { |w| w.start_with?('Aufgesattelte Wange: schräge') }
            end
            # Faserrichtung entlang der Sehne der Unterkante (geschwungen)
            sb[:grain] = [v1 - v0, r[:bf].(v1) - r[:bf].(v0)] if r[:bf]
            res[:sattel] << sb
          end
        end
      end

      # Mittellinie der aufgesattelten Wange (Parameter v) an der Rückseite
      # des Antrittspfostens und der Vorderseite des Austrittspfostens
      # (Pfostenflächen rechtwinklig zur Begrenzung)
      def sat_post_cut(plan, p, which, sp, side)
        poly = plan.send(which)
        s = p['newel_s'].to_f
        qs = Railing.post_positions(plan, p, which)
        hit = lambda do |u|
          uc = [[u, 0.0].max, poly.length].min
          n = Railing.normal_at(poly, uc, side)
          h = sp.ray_hit(Geo.add(poly.at(uc), Geo.mul(poly.tangent(uc), u - uc)), Geo.mul(n, -1.0))
          h && h[1]
        end
        a = qs.find { |q| q[:role] == :antritt }
        b = qs.find { |q| q[:role] == :austritt }
        [a && hit.(a[:u] + s / 2.0), b && hit.(b[:u] - s / 2.0)]
      end

      # --- schräge Stöße der aufgesattelten Wange --------------------------

      # Brettfläche als Gerade: Punkt und Richtung (Versatz off entlang
      # Geo.right(dir) von der Mittellinie).
      def board_face(sp, r, off)
        [Geo.add(sp.at(r[:v0]), Geo.mul(Geo.right(r[:dir]), off)), r[:dir]]
      end

      # Lage (Koordinate v der Mittellinie) des Schnitts der Brettfläche (off)
      # mit einer Geraden [Punkt, Richtung]; nil wenn parallel.
      def board_cross(sp, r, off, line)
        o, d = board_face(sp, r, off)
        q, e = line
        den = Geo.cross(d, e)
        return nil if den.abs < 1e-9
        r[:v0] + Geo.cross(Geo.sub(q, o), e) / den
      end

      # Lage auf der Brettfläche off für eine Stufenlinie {in:, out:}; nil wenn
      # parallel oder der Schnitt weit außerhalb der Linie liegt.
      def line_cross(sp, r, off, l)
        e = Geo.sub(l[:out], l[:in])
        o, d = board_face(sp, r, off)
        den = Geo.cross(d, e)
        return nil if den.abs < 1e-9 * Geo.len(e)
        q = Geo.cross(Geo.sub(l[:in], o), d) / den
        return nil if q < -0.5 || q > 1.5
        r[:v0] + Geo.cross(Geo.sub(l[:in], o), e) / den
      end

      # Umrisse auf den beiden Brettflächen (−t/2, +t/2 entlang Geo.right(dir))
      # aus dem Umriss der Mittelebene: senkrechte Stöße an Stufenlinien,
      # Brettenden an Antritt/Austritt/Podest und Ecken werden auf die Lage der
      # jeweiligen Fläche verschoben. Gleiche Punktzahl wie der Mittelumriss
      # (Seitenflächen eben). nil, wenn ein Flächenumriss ungültig würde.
      def sat_face_polys(sp, r, top, bot, cuts, clines, eline, v_end, t, obst)
        a = r[:a]; b = r[:b]
        eps = 1e-6
        offs = [-t / 2.0, t / 2.0]
        delta = lambda do |l, off|
          c = line_cross(sp, r, 0.0, l)
          f = line_cross(sp, r, off, l)
          c && f ? f - c : 0.0
        end
        kat = ->(v) { cuts.index { |cv| (cv - v).abs < 1e-4 } }
        lo = offs.each_with_index.map do |off, i|
          a + if r[:start_f] then r[:start_f][i].to_f - a
              elsif (k = kat.(a)) then delta.(clines[k], off)
              else 0.0
              end
        end
        hi = offs.each_with_index.map do |off, i|
          b + if r[:end_f] then r[:end_f][i].to_f - b
              elsif (k = kat.(b)) then delta.(clines[k], off)
              elsif (b - v_end).abs < 1e-4 then delta.(eline, off)
              else 0.0
              end
        end
        top = top.dup
        # Ausklinkungen im Mittelumriss mit ihrer Lage auf beiden Flächen
        steps = lambda do
          (0...top.size - 1).select { |i| (top[i][0] - top[i + 1][0]).abs < 1e-9 && top[i + 1][1] > top[i][1] + 1e-9 && kat.(top[i][0]) }
                            .map { |i| [i, offs.map { |off| top[i][0] + delta.(clines[kat.(top[i][0])], off) }] }
        end
        # Ausklinkung im Bereich eines schrägen Brettanfangs (liegt auf einer
        # Fläche vor dem Anfang): der niedrige Teil davor entfällt
        st = steps.().select { |_, pos| pos.each_with_index.any? { |q, j| q <= lo[j] + eps } }.last
        if st
          i, pos = st
          top = [[a, top[i + 1][1]]] + top[(i + 2)..-1]
          lo = lo.each_with_index.map { |q, j| [q, pos[j]].max }
        end
        # Stufen/Setzstufen, deren Unterseite tiefer als der Brettanfang liegt
        # und in die eine Fläche am Anfang hineinragt (z. B. Eckstück am Podest
        # neben der Ecke der vorigen Stufe): Fläche beginnt erst dahinter
        z0 = top[0][1]
        offs.each_with_index do |off, j|
          6.times do
            moved = false
            obst.each do |poly, zb|
              next unless zb < z0 - 1e-6
              face_intervals(sp, r, off, poly).each do |s0, s1|
                next unless s0 <= lo[j] + 1e-4 && s1 > lo[j] + 1e-4 && s1 <= (lo[j] + hi[j]) / 2.0
                lo[j] = s1
                moved = true
              end
            end
            break unless moved
          end
        end
        # Ecken solcher Hindernisse innerhalb der Brettdicke: Anfangskante
        # (Gerade zwischen den Flächen) parallel nach hinten schieben
        o0, = board_face(sp, r, 0.0)
        nr = Geo.right(r[:dir])
        mid = (lo.sum + hi.sum) / 4.0
        push = 0.0
        obst.each do |poly, zb|
          next unless zb < z0 - 1e-6
          poly.each do |q|
            w = Geo.dot(Geo.sub(q, o0), nr)
            next unless w.abs < t / 2.0 - 1e-6
            u = r[:v0] + Geo.dot(Geo.sub(q, o0), r[:dir])
            fr = (w + t / 2.0) / t
            ul = lo[0] + (lo[1] - lo[0]) * fr
            next unless u > ul + 1e-6 && u <= mid
            # nur, wenn die Ecke wirklich im Hindernis vor dem Brett liegt
            push = [push, u - ul].max
          end
        end
        lo = lo.map { |x| x + push } if push > 0
        # Anfang über das Brettende hinaus verschoben (Hindernis überdeckt das
        # ganze Brett, z. B. Podestbrett am U-Stoß): nicht darstellbar
        return nil if lo.any? { |x| x > b + 1e-3 }
        # Ausklinkung im Bereich eines schrägen Brettendes (Gehrung): liegt sie
        # auf einer Fläche hinter dem Ende, endet das Brett an der Ausklinkung
        st = steps.().find { |_, pos| pos.each_with_index.any? { |q, j| q >= hi[j] - eps } }
        if st
          i, pos = st
          top = top[0..i] + [[b, top[i][1]]]
          hi = hi.each_with_index.map { |q, j| [q, pos[j]].min }
        end
        hi = hi.each_with_index.map { |q, j| [q, lo[j]].max }   # höchstens zur Linie entartet
        fs = offs.each_with_index.map do |off, j|
          mv = lambda do |v, z|
            u = if (v - a).abs < eps then lo[j]
                elsif (v - b).abs < eps then hi[j]
                elsif (k = kat.(v)) then v + delta.(clines[k], off)
                else v
                end
            [[[u, lo[j]].max, hi[j]].min, z]
          end
          tp = top.map { |v, z| mv.(v, z) }
          bp = bot.map { |v, z| mv.(v, z) }
          # Ausklinkung, die auf dieser Fläche hinter einem folgenden Punkt der
          # Oberkante liegt (kurzer Schenkel einer Drachenstufe nahe der Ecke):
          # die Punkte dazwischen fallen auf die Ausklinkung zusammen
          (1...tp.size).each { |i| tp[i] = [tp[i - 1][0], tp[i][1]] if tp[i][0] < tp[i - 1][0] && kat.(top[i - 1][0]) }
          # Reihenfolge erhalten: Oberkante steigend, Unterkante fallend
          return nil unless tp.each_cons(2).all? { |p0, p1| p1[0] >= p0[0] - 1e-6 }
          return nil unless bp.each_cons(2).all? { |p0, p1| p1[0] <= p0[0] + 1e-6 }
          pl = tp + bp
          # Umlaufsinn wie der Mittelumriss (eine Fläche darf zur Linie entarten)
          return nil if Geo.signed_area(pl) * Geo.signed_area(top + bot) < -1e-6
          pl
        end
        return nil unless fs[0].size == fs[1].size && fs.map { |pl| Geo.signed_area(pl).abs }.max >= 1.0
        fs << top.size   # Anzahl Punkte der Oberkante (Rest = Unterkante)
        fs
      end

      # Abschnitte (Koordinate v) der Brettfläche off, die im Polygon liegen
      def face_intervals(sp, r, off, poly)
        o, d = board_face(sp, r, off)
        ts = []
        n = poly.size
        n.times do |i|
          p0 = poly[i]; p1 = poly[(i + 1) % n]
          e = Geo.sub(p1, p0)
          den = Geo.cross(d, e)
          next if den.abs < 1e-12
          w = Geo.sub(p0, o)
          q = Geo.cross(w, d) / den
          next if q < 0 || q >= 1
          ts << Geo.cross(w, e) / den
        end
        ts.sort!
        ts.each_slice(2).select { |x| x.size == 2 && x[1] - x[0] > 1e-6 }.map { |s0, s1| [r[:v0] + s0, r[:v0] + s1] }
      end

      # Schnitt eines Strahls mit einer Brettfläche (Polylinie fp, gleiche
      # Stützpunkte wie die Mittellinie sp), umgerechnet in die Koordinate v
      # der Mittellinie (Lot auf die Gerade des zugehörigen Bretts).
      def face_hit(fp, sp, origin, dir)
        best = nil
        cum = sp.cum; cp = sp.pts
        (0...fp.size - 1).each do |i|
          p = fp[i]; q = fp[i + 1]
          e = Geo.sub(q, p)
          den = Geo.cross(dir, e)
          next if den.abs < 1e-12
          w = Geo.sub(p, origin)
          tt = Geo.cross(w, e) / den
          u = Geo.cross(w, dir) / den
          next if u < -1e-7 || u > 1 + 1e-7 || tt <= 1e-9
          next if best && tt >= best[0]
          pt = Geo.add(origin, Geo.mul(dir, tt))
          cd = Geo.norm(Geo.sub(cp[i + 1], cp[i]))
          best = [tt, cum[i] + Geo.dot(Geo.sub(pt, cp[i]), cd)]
        end
        best && best[1]
      end

      def seg_x?(p1, p2, q1, q2)
        d1 = Geo.cross(Geo.sub(p2, p1), Geo.sub(q1, p1))
        d2 = Geo.cross(Geo.sub(p2, p1), Geo.sub(q2, p1))
        d3 = Geo.cross(Geo.sub(q2, q1), Geo.sub(p1, q1))
        d4 = Geo.cross(Geo.sub(q2, q1), Geo.sub(p2, q1))
        ((d1 > 1e-9 && d2 < -1e-9) || (d1 < -1e-9 && d2 > 1e-9)) &&
          ((d3 > 1e-9 && d4 < -1e-9) || (d3 < -1e-9 && d4 > 1e-9))
      end


      # --- geschwungene aufgesattelte Wange -------------------------------

      # Unterkanten-Funktionen r[:bf] (v -> z) für alle Bretter einer Seite.
      def sat_curve(recs, corners, rest)
        runs = []
        recs.each do |r|
          if r[:landing] || runs.empty? || runs[-1][-1][:landing] || r[:v0] - runs[-1][-1][:v1] > 1.5
            runs << [r]
          else
            runs[-1] << r
          end
        end
        runs.each do |run|
          cs = merge_nodes(corners.select { |v, _| v >= run[0][:v0] - 0.01 && v <= run[-1][:v1] + 0.01 }, false)
          if run[0][:landing] || cs.size < 2
            run.each do |r|
              c, s = r[:f]
              r[:bf] = ->(v) { c + s * v }
              r[:knots] = []
            end
            next
          end
          # Knoten: Ecke minus Restbreite (rechtwinklig zur örtlichen Eckenlinie)
          nodes = cs.each_index.map do |i|
            a = cs[[i - 1, 0].max]; b = cs[[i + 1, cs.size - 1].min]
            s = (b[1] - a[1]) / [b[0] - a[0], 1e-9].max
            [cs[i][0], cs[i][1] - rest * Math.sqrt(1 + s * s)]
          end
          # z nicht fallend (Monotonie)
          (nodes.size - 2).downto(0) { |i| nodes[i][1] = [nodes[i][1], nodes[i + 1][1]].min }
          f0 = pchip(nodes)
          drop = 0.0
          # absenken, bis an jeder Ecke die Restbreite erreicht ist (an steilen
          # Stellen wächst der rechtwinklige Abstand langsamer als die Absenkung)
          60.times do
            f = ->(v) { f0.(v) - drop }
            dfc = cs.map { |u, z| rest - curve_dist([u, z], f, rest) }.max
            break if dfc <= 1e-6
            drop += 1.5 * dfc + 1e-5
          end
          fb = ->(v) { f0.(v) - drop }
          run.each do |r|
            r[:bf] = fb
            r[:knots] = nodes.map(&:first)
          end
        end
        # Ecken: Unterkanten an der Stoßstelle angleichen (nur absenken, damit
        # die Restbreite erhalten bleibt), knickfrei ausgeblendet
        smooth = ->(t) { t = [[t, 0.0].max, 1.0].min; t * t * (3 - 2 * t) }
        recs.each do |rb|
          ra = rb[:joint]
          next unless ra
          dz = ra[:bf].(ra[:b]) - rb[:bf].(rb[:a])
          next if dz.abs < 1e-6
          if dz > 0
            f = ra[:bf]; e = ra[:b]; len = [25.0, 0.5 * (ra[:b] - ra[:a])].min
            ra[:bf] = ->(v) { f.(v) - dz * smooth.((v - e + len) / len) }
            ra[:knots] += [e - len]
          else
            f = rb[:bf]; e = rb[:a]; len = [25.0, 0.5 * (rb[:b] - rb[:a])].min
            rb[:bf] = ->(v) { f.(v) + dz * (1.0 - smooth.((v - e) / len)) }
            rb[:knots] += [e + len]
          end
        end
        # Kontrolle mit der tatsächlich gezeichneten Polylinie (Sicherheitsnetz:
        # sonst alle Unterkanten dieser Seite gleichmäßig absenken)
        drop = 0.0
        base = recs.map { |r| r[:bf] }
        60.times do
          dfc = 0.0
          recs.each_with_index do |r, i|
            f = base[i]
            pl = sat_samples(r).map { |v| [v, f.(v) - drop] }
            corners.each do |u, z|
              next if u < r[:a] - 0.01 || u > r[:b] + 0.01
              dfc = [dfc, rest - poly_dist([u, z], pl)].max
            end
          end
          break if dfc <= 1e-9
          drop += 1.5 * dfc + 1e-7
        end
        return unless drop > 0
        recs.each_with_index do |r, i|
          f = base[i]
          r[:bf] = ->(v) { f.(v) - drop }
        end
      end

      # Stützstellen einer geschwungenen Unterkante (Brettenden, Knoten, alle SAMPLE cm)
      def sat_samples(r)
        a = r[:a]; b = r[:b]
        n = [((b - a) / SAMPLE).ceil, 1].max
        us = (0..n).map { |i| a + (b - a) * i / n } + r[:knots].select { |u| u > a + 0.005 && u < b - 0.005 }
        us.sort.each_with_object([]) { |u, o| o << u if o.empty? || u - o[-1] > 0.005 }.tap { |o| o[-1] = b }
      end

      # kleinster Abstand eines Punkts zur Kurve z = f(v) (fein abgetastet)
      def curve_dist(pt, f, rest)
        u = pt[0]; w = 4.0 * rest
        n = [(2 * w / 0.25).ceil, 2].max
        poly_dist(pt, (0..n).map { |i| v = u - w + 2 * w * i / n; [v, f.(v)] })
      end

      def poly_dist(pt, pl)
        best = 1e9
        pl.each_cons(2) do |a, b|
          d = Geo.sub(b, a); l2 = Geo.dot(d, d)
          t = l2 < 1e-12 ? 0.0 : [[Geo.dot(Geo.sub(pt, a), d) / l2, 0.0].max, 1.0].min
          best = [best, Geo.dist(pt, Geo.add(a, Geo.mul(d, t)))].min
        end
        best
      end

      # Unterkante einer aufgesattelten Wange an der Stelle v
      def sat_bottom(r, v)
        z = r[:f][0] + r[:f][1] * v
        r[:ops].each do |op, (c, s)|
          l = c + s * v
          z = op == :max ? [z, l].max : [z, l].min
        end
        z
      end

      # Gerade durch (vp, zp), die von allen Ecken cs rechtwinklig mind. rest
      # Abstand nach unten hält; dir > 0: größte, dir < 0: kleinste Steigung.
      # nil, wenn keine solche Gerade existiert.
      def sat_slope(cs, vp, zp, rest, dir)
        ok = lambda do |s|
          q = rest * Math.sqrt(1 + s * s)
          cs.all? { |u, z| zp + s * (u - vp) + q <= z + 1e-7 }
        end
        n = 1700
        angs = (0..n).map { |i| -85.0 + 170.0 * i / n }
        angs.reverse! if dir > 0
        prev = nil
        angs.each do |a|
          s = Math.tan(a * Math::PI / 180.0)
          if ok.(s)
            return s unless prev
            lo = s; hi = prev
            50.times do
              m = (lo + hi) / 2.0
              ok.(m) ? lo = m : hi = m
            end
            return lo
          end
          prev = s
        end
        nil
      end
    end
  end
end
