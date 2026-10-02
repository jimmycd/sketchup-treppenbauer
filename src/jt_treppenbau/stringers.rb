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

      # Gehrungs-Normale zwischen zwei Richtungen (side +1 rechts)
      def miter(d0, d1, side)
        n0 = side > 0 ? Geo.right(d0) : Geo.left(d0)
        n1 = side > 0 ? Geo.right(d1) : Geo.left(d1)
        m = Geo.norm(Geo.add(n0, n1))
        c = Geo.dot(m, n1)
        c = 0.3 if c < 0.3
        Geo.mul(m, 1.0 / c)
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
            # Splitter (< 3 cm, z. B. minimale Podestverlängerung) weglassen
            list = list.reject { |b| b[:u1] - b[:u0] < 3.0 } if list.size > 1
            # Endnormalen: Gehrung zwischen Brettern, sonst entlang der Stufenlinie
            list.each_with_index do |b, i|
              b[:n0] = if i > 0 then miter(list[i - 1][:dir], b[:dir], side)
                       elsif b[:idx0] then line_normal(plan, b[:idx0], b[:dir], side)
                       end
              b[:n1] = if i < list.size - 1 then miter(b[:dir], list[i + 1][:dir], side)
                       elsif b[:idx1] then line_normal(plan, b[:idx1], b[:dir], side)
                       end
            end
            if curve
              curve_piece(list, landings, plan)
            else
              straight_piece(list)
              lists << list
            end
            piece_boards << list
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
        res[:wange] = boards
        res[:width] = width
        res[:need] = need
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
        b = r[:wange].find { |x| x[:which] == which && u >= x[:u0] - 1e-6 && u <= x[:u1] + 1e-6 }
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
          zt = (0...plan.treads).map { |k| (k + 1) * plan.h - d }
          corners = (0...plan.treads - 1).map { |k| [cuts[k + 1], zt[k]] } + [[v_end, zt[-1]]]
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
            recs << { v0: v0, v1: v1, a: v0, b: v1, cs: cs, f: [c, s], ops: [], landing: lk,
                      dir: Geo.norm(Geo.sub(sp.at(v1), sp.at(v0))) }
          end
          # Ecken (Knick zwischen zwei Brettern): stumpfer Stoß ohne
          # Durchdringung – das untere Brett läuft bis zur Außenfläche des
          # oberen durch, das obere stößt an die Seitenfläche des unteren.
          # Unterkante des oberen Bretts beginnt auf Höhe der Unterkante des
          # unteren Bretts.
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
            ra[:b] = ra[:v1] + xa + t / 2.0 / sn
            rb[:a] = rb[:v0] + yb + t / 2.0 * (1.0 + cs_) / sn
            rb[:joint] = ra
          end
          sat_curve(recs, corners, rest) if curve
          recs.each do |r|
            ra = r[:joint]
            next unless ra && !curve
            vp = r[:a]
            zp = sat_bottom(ra, ra[:b])
            fz = r[:f][0] + r[:f][1] * vp
            next if (zp - fz).abs < 1e-6
            sl = zp > fz ? sat_slope(r[:cs], vp, zp, rest, 1) : nil
            if zp > fz && sl.nil?
              # zu hoch für das obere Brett: höchste mögliche Höhe, unteres
              # Brett am Ende entsprechend absenken
              lo = fz; hi = zp
              40.times do
                m = (lo + hi) / 2.0
                sat_slope(r[:cs], vp, m, rest, 1) ? lo = m : hi = m
              end
              zp = lo
              sa = sat_slope(ra[:cs], ra[:b], zp, rest, -1)
              ra[:ops] << [:min, [zp - sa * ra[:b], sa]] if sa
            end
            sl = sat_slope(r[:cs], vp, zp, rest, 1)
            next unless sl
            r[:ops] << [zp > fz ? :max : :min, [zp - sl * vp, sl]]
          end
          no = 0
          recs.each do |r|
            v0 = r[:a]; v1 = r[:b]
            ztop_at = lambda do |v, after|
              k = cuts.rindex { |cv| after ? cv <= v + 1e-9 : cv < v - 1e-9 }
              k ? zt[k] : 0.0
            end
            top = [[v0, ztop_at.(v0, true)]]
            cuts.each_with_index do |cv, k|
              next unless cv > v0 + 1e-6 && cv < r[:v1] - 1e-6
              top << [cv, k > 0 ? zt[k - 1] : 0.0] << [cv, zt[k]]
            end
            top << [r[:v1], ztop_at.(r[:v1], false)] if v1 > r[:v1] + 1e-6
            top << [v1, ztop_at.(r[:v1], false)]
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
            sb = { which: which, side: side, origin: o, dir: r[:dir], len: v1 - v0,
                   poly: poly, t: t, nr: no }
            # Faserrichtung entlang der Sehne der Unterkante (geschwungen)
            sb[:grain] = [v1 - v0, r[:bf].(v1) - r[:bf].(v0)] if r[:bf]
            res[:sattel] << sb
          end
        end
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
