# encoding: UTF-8
# Treppenbau – aufgesattelte Wangen als 3D-Bearbeitung, je Wange ein eigenes
# Programm (ohne SketchUp-API, testbar).
#
# Die Wange ist ein Körper aus zwei Flächenumrissen (Stringers: sb[:faces]);
# sie unterscheiden sich nur an senkrechten Stößen („Wänden“): Ausklinkungen,
# schräge Brettenden, Gehrungen. Jede Wand ist eine Ebene, die in der Treppe
# senkrecht steht und schräg durch die Brettdicke läuft.
#
# Fertigung aus einem rechteckigen Rohling (Brett liegt flach, Faser in X):
#   Seite 1:  Gravur, Markierungen, Außenkontur (in Stufen zu je sat_zstep
#             bis Dicke + Durchfräsen, ohne Ausräumen), danach Schrägen mit dem
#             Seitenaggregat (waagerechte Spindel, Achse in Richtung der
#             Treppen-Senkrechten, C-Achse gedreht; Hilfsfläche GSIDE je Wand).
#   Wenden:   Seite 1 beginnt mit dem Formatieren des Rohlings (Rohteil je
#             Seite FORMAT_OFF größer) – die formatierten Kanten sind der
#             Bezug für Seite 2. Außenkontur auf Seite 1: Stufenseite und
#             Enden durchgefräst, der Rücken bleibt stehen (hält das Teil);
#             Seite 2 (um die Y-Achse gewendet): Rücken fräsen, dann Schrägen
#             mit umgekehrter Neigung. (Ohne erkennbaren Rücken: Seite 1 bis
#             Reststärke REST_T, Seite 2 durch die Reststärke.)
#   Optionen: sat_mode 'fraesen' | 'markieren', sat_wenden true/false.
#   Nicht erreichbare Teile (Werkzeuglänge) und nicht gefräste Schrägen werden
#   mit dem Gravurwerkzeug markiert (Nacharbeit von Hand).
#
# Koordinaten: Brett (u längs, z = Treppen-Senkrechte) in mm; Tisch (x, y)
# in mm, Tisch-Z = Dicke (0 = Unterseite, t = Oberseite).

module JTools
  module Treppenbau
    module Wange3d
      module_function

      MM = 10.0

      FORMAT_OFF = 5.0   # Rohteil je Seite größer als das Formatmaß (nur Wenden)
      REST_T = 10.0      # Reststärke der Außenkontur auf Seite 1 (nur Wenden)

      Job = Struct.new(:label, :info, :t, :blank, :programs, :notes, :outline, :walls, :sb, :sb_ctx) do
        def wenden?
          programs.size > 1
        end

        # Versatz Rohteil -> Formatmaß auf Seite 1 (nur Wenden)
        def raw_off
          wenden? ? FORMAT_OFF : 0.0
        end

        # Rohteilmaß (vor dem Formatieren)
        def raw_blank
          blank.map { |v| v + 2 * raw_off }
        end

        # eine Zeile für die Hinweisliste im Dialog
        def summary
          c = Hash.new(0); walls.each { |w| c[w[:how]] += 1 }
          rest = walls.select { |w| (w[:rest] || 0) > 0.5 }
          parts = []
          parts << "#{c[:mill1]} Schräge(n) Aggregat Seite 1" if c[:mill1] > 0
          parts << "#{c[:mill2]} Seite 2 (wenden)" if c[:mill2] > 0
          parts << "#{c[:mark] + c[:mark2]} nur markiert" if c[:mark] + c[:mark2] > 0
          parts << "#{rest.size} Rest(e) unten von Hand (#{rest.map { |w| w[:rest].round }.minmax.uniq.join('–')} mm)" unless rest.empty?
          parts.empty? ? nil : "#{label}: " + parts.join(', ')
        end
      end
      Prog = Struct.new(:side, :name, :ops, :faces, :preview)

      # --- Wände ------------------------------------------------------------

      # Senkrechte Stöße, an denen sich die beiden Flächenumrisse unterscheiden.
      # Rückgabe: [{ i: [Indizes], ua:, ub:, z0:, z1:, mat: +1/−1 }]
      def walls(fa, fb)
        n = fa.size
        ccw = Geo.signed_area(Geo.signed_area(fa).abs > Geo.signed_area(fb).abs ? fa : fb) > 0
        res = []
        n.times do |i|
          j = (i + 1) % n
          next unless (fa[i][0] - fa[j][0]).abs < 1e-6 && (fb[i][0] - fb[j][0]).abs < 1e-6
          next if (fa[i][1] - fa[j][1]).abs < 1e-6
          next if (fa[i][0] - fb[i][0]).abs < 0.05
          up = fa[j][1] > fa[i][1]
          mat = ccw ? (up ? -1 : 1) : (up ? 1 : -1)
          last = res[-1]
          if last && last[:i][-1] == i && (last[:ua] - fa[i][0]).abs < 1e-6 && (last[:ub] - fb[i][0]).abs < 1e-6
            last[:i] << j
            last[:z0] = [last[:z0], fa[j][1]].min; last[:z1] = [last[:z1], fa[j][1]].max
          else
            res << { i: [i, j], ua: fa[i][0], ub: fb[i][0], z0: [fa[i][1], fa[j][1]].min, z1: [fa[i][1], fa[j][1]].max, mat: mat }
          end
        end
        res
      end

      # Umriss mit dem meisten Material (Vereinigung beider Flächen): an jeder
      # Wand die Lage, die auf der Materialseite weiter außen liegt.
      def union_ring(fa, fb, ws)
        pick = {}
        ws.each { |w| w[:i].each { |i| pick[i] = w } }
        fa.each_index.map do |i|
          w = pick[i]
          next fa[i] unless w
          u = w[:mat] > 0 ? [fa[i][0], fb[i][0]].min : [fa[i][0], fb[i][0]].max
          [u, fa[i][1]]
        end
      end

      # --- Jobs -------------------------------------------------------------

      def jobs(plan, p, o)
        r = Stringers.compute(plan, p)
        out = []
        r[:sattel].each do |sb|
          next if sb[:len] < 10.0 || sb[:faces].nil?
          out << job(sb, o)
        end
        out.compact
      end

      def job(sb, o)
        t = sb[:t] * MM
        fa, fb = sb[:faces].map { |pl| pl.map { |u, z| [u * MM, z * MM] } }
        ntop = sb[:ntop] || fa.size / 2
        ws = walls(fa, fb)
        # Seite 1 oben: Fläche mit dem meisten von oben erreichbaren Keil
        score = ->(up) { ws.sum { |w| u_up, u_dn = up == :b ? [w[:ub], w[:ua]] : [w[:ua], w[:ub]]; d = w[:mat] * (u_up - u_dn); d > 0 ? d * (w[:z1] - w[:z0]) : 0.0 } }
        up = score.(:b) >= score.(:a) ? :b : :a
        ring = union_ring(fa, fb, ws)
        # Tisch-Transformation: Fläche b oben = Brettansicht ungespiegelt
        mir = up == :b ? 1.0 : -1.0
        axis = grain_axis(sb, ring, ntop)
        axis = [axis[0] * mir, axis[1]]
        ang = -Math.atan2(axis[1], axis[0])
        rot = ->(q) { Geo.rot([q[0] * mir, q[1]], ang) }
        pts = ring.map(&rot)
        m = o['blank_margin'].to_f
        minx = pts.map(&:first).min - m; miny = pts.map(&:last).min - m
        tr = ->(q) { r_ = rot.(q); [r_[0] - minx, r_[1] - miny] }
        outline = ring.map(&tr)
        bl = outline.map(&:first).max + m; bw = outline.map(&:last).max + m
        s_tab = Geo.norm(Geo.sub(tr.([0.0, 1.0]), tr.([0.0, 0.0])))
        jb = Job.new(sb_label(sb), "Aufgesattelte Wange #{sb[:which] == :outer ? 'außen' : 'innen'} #{sb[:nr]}",
                     t, [bl, bw], [], [], outline, [], sb)
        ctx = { t: t, tr: tr, s: s_tab, ring: ring, ntop: ntop, blank: [bl, bw], o: o, up: up,
                face_up: { 1 => (up == :b ? fb : fa), 2 => (up == :b ? fa : fb) } }
        jb.sb_ctx = ctx
        # Wände klassifizieren
        ws.each do |w|
          u_up, u_dn = up == :b ? [w[:ub], w[:ua]] : [w[:ua], w[:ub]]
          w[:side] = w[:mat] * (u_up - u_dn) > 0 ? 1 : 2      # von oben erreichbar auf Seite 1 / 2
          w[:u_top] = [u_up, u_dn]                             # Lage oben/unten auf Seite 1
        end
        wenden = o['sat_wenden'] && ws.any? { |w| w[:side] == 2 }
        mode = o['sat_mode'].to_s == 'markieren' ? :mark : :mill
        s1 = Prog.new(1, nil, [], [], {})
        s2 = wenden ? Prog.new(2, nil, [], [], {}) : nil
        # Gravur Teilenummer
        if o['engrave']
          pl = Struct.new(:part, :poly).new(Struct.new(:label).new(jb.label), outline)
          Tcn.label_strokes(pl, o['text_h'].to_f).each { |st| s1.ops << [:mark, st] }
        end
        # Außenkontur auf Seite 1 vor den Schrägen (kein Ausräumen mehr)
        s1.ops << [:contour, outline_on(ctx, outline, false)]
        ws.each do |w|
          prog = w[:side] == 1 || !wenden ? s1 : s2
          flip = prog.side == 2
          if w[:side] == 2 && !wenden
            # nicht von oben erreichbar, kein Wenden: Markierung „unten bis hier“
            mark_lines(ctx, w[:u_top][1], w[:z0], w[:z1], false, 1).each { |ml| prog.ops << [:mark, ml] }
            jb.notes << "#{jb.label}: Schräge bei Höhe #{(w[:z0] / 10).round(1)}–#{(w[:z1] / 10).round(1)} cm unten, " \
                        "Breite #{((w[:u_top][0] - w[:u_top][1]).abs).round(1)} mm – von Hand (Markierung = Kante unten)"
            w[:how] = :mark2
            jb.walls << w
            next
          end
          u_tgt = w[:side] == 1 ? w[:u_top][0] : w[:u_top][1]   # Kante auf der oberen Fläche dieses Programms
          if mode == :mark
            mark_lines(ctx, u_tgt, w[:z0], w[:z1], flip, prog.side).each { |ml| prog.ops << [:mark, ml] }
            jb.notes << "#{jb.label}: Schräge #{(w[:z0] / 10).round(1)}–#{(w[:z1] / 10).round(1)} cm von Hand (Markierung, Seite #{prog.side})"
            w[:how] = :mark
          else
            ag = aggregate(ctx, w, flip)
            prog.faces << ag[:face]
            if ag[:rest] > 0.5
              mark_lines(ctx, u_tgt, w[:z0], w[:z0] + ag[:rest], flip, prog.side).each { |ml| prog.ops << [:mark, ml] }
              tick = tick_line(ctx, u_tgt, w[:z0] + ag[:rest], w[:mat], flip)
              prog.ops << [:mark, tick] if tick
              jb.notes << "#{jb.label}: Schräge unten #{ag[:rest].round} mm nicht erreichbar (Werkzeuglänge) – von Hand (Markierung, Seite #{prog.side})"
            end
            w[:how] = prog.side == 1 ? :mill1 : :mill2
            w[:rest] = ag[:rest]
          end
          jb.walls << w
        end
        if s2
          # Seite 1: zuerst formatieren, Außenkontur nur bis Reststärke;
          # Seite 2: Außenkontur durch die Reststärke, vor den Schrägen
          s1.ops.unshift([:format, [[0.0, 0.0], [bl, 0.0], [bl, bw], [0.0, bw]]])
          bi = back_idx(ring, ntop)
          if bi
            fi = (bi.last...ring.size).to_a + (0..bi.first).to_a
            s1.ops.map! { |op| op[0] == :contour ? [:contour, op[1], { idx: fi }] : op }
            s2.ops.unshift([:contour, outline_on(ctx, outline, true), { idx: bi }])
          else
            s1.ops.map! { |op| op[0] == :contour ? [:contour, op[1], :leave_rest] : op }
            s2.ops.unshift([:contour, outline_on(ctx, outline, true), :finish_rest])
          end
        end
        jb.programs << s1
        jb.programs << s2 if s2
        if s2
          jb.notes << "#{jb.label}: Rohteil #{(bl + 2 * FORMAT_OFF).round} × #{(bw + 2 * FORMAT_OFF).round} mm, " \
                      "Seite 1 formatiert auf #{bl.round} × #{bw.round} mm; " +
                      (bi ? 'Stufenseite und Enden durchgefräst, Rücken bleibt stehen' : "Außenkontur bis #{REST_T.round} mm Reststärke")
          jb.notes << "#{jb.label}: wenden (um die Y-Achse), an den formatierten Kanten anlegen – Seite 2 (#{bi ? 'Rücken fräsen' : 'Kontur durchfräsen'}, Schrägen)"
        end
        jb
      end

      # Indizes des Rückens im Umriss (ring[ntop..], ohne waagerechten Boden-
      # schnitt am Ende); nil, wenn kein Rücken erkennbar
      def back_idx(ring, ntop)
        idx = (ntop...ring.size).to_a
        idx.pop while idx.size >= 2 && (ring[idx[-1]][1] - ring[idx[-2]][1]).abs < 1e-6
        idx.size >= 2 ? idx : nil
      end

      def sb_label(sb)
        "S#{sb[:which] == :outer ? 'A' : 'I'}#{sb[:nr]}"
      end

      # Faser entlang der Sehne der Unterkante (wie bisher für den Plattenexport)
      def grain_axis(sb, ring, ntop)
        bot = ring[ntop..-1]
        return [1.0, 0.0] if bot.nil? || bot.size < 2
        a = bot[-1]; b = bot[0]
        d = Geo.sub(b, a)
        d = Geo.mul(d, -1) if d[0] < 0
        Geo.len(d) < 1 ? [1.0, 0.0] : d
      end

      # Punkt (Brett) -> Tisch, auf Seite 2 um die Y-Achse gewendet
      def tab(ctx, q, flip = false)
        x, y = ctx[:tr].(q)
        flip ? [ctx[:blank][0] - x, y] : [x, y]
      end

      def outline_on(ctx, outline, flip)
        flip ? outline.map { |x, y| [ctx[:blank][0] - x, y] } : outline
      end

      def mark_line(ctx, u, z0, z1, flip = false)
        [tab(ctx, [u, z0], flip), tab(ctx, [u, z1], flip)]
      end

      # Markierungslinie bei u von z0 bis z1, beschnitten auf das Material nach
      # dem Ausräumen (Umriss mit dem meisten Material) – sonst Gravur in der Luft
      def mark_lines(ctx, u, z0, z1, flip, _side)
        poly = ctx[:ring]
        zs = []
        poly.each_with_index do |a, i|
          b = poly[(i + 1) % poly.size]
          next if (a[0] - b[0]).abs < 1e-9
          next unless (a[0] - u) * (b[0] - u) <= 0 && [a[0], b[0]].max > u - 1e-9
          zs << a[1] + (b[1] - a[1]) * (u - a[0]) / (b[0] - a[0])
        end
        zs = zs.sort.each_with_object([]) { |z, o_| o_ << z if o_.empty? || z - o_[-1] > 1e-6 }
        segs = []
        zs.each_slice(2) do |a, b|
          next unless b
          lo = [a, z0].max + 1.0; hi = [b, z1].min - 1.0
          segs << mark_line(ctx, u, lo, hi, flip) if hi > lo + 2.0
        end
        segs
      end

      # Querstrich (10 mm) an der Reichweitengrenze, zur Luftseite hin
      def tick_line(ctx, u, z, mat, flip)
        [tab(ctx, [u, z], flip), tab(ctx, [u - mat * 10.0, z], flip)]
      end

      # --- Ausräumen aus dem Vollen (derzeit nicht verwendet) --------------
      # Bereich: Rohling ohne (Wange ∪ Bereich unter der Wange), d. h. alles
      # oberhalb der Auflager und hinter den Brettenden. Zeilen parallel zu den
      # Auflagern (Brett-u), Fräsermitte mindestens r von der Wange entfernt.
      def clearing(ctx)
        o = ctx[:o]
        r = Cnc.outer_tool(o, ctx[:t])[:d] / 2.0
        ring = ctx[:ring]; ntop = ctx[:ntop]
        top = ring[0...ntop]
        pieces = []
        top.each_cons(2) do |a, b|
          next unless (a[1] - b[1]).abs < 1e-6 && b[0] > a[0] + 1e-6
          pieces << [a[0], b[0], a[1]]
        end
        lo = top.map(&:first).min; hi = top.map(&:first).max
        # Rohling im Brettsystem
        inv = inverse(ctx)
        bl, bw = ctx[:blank]
        corners = [[0, 0], [bl, 0], [bl, bw], [0, bw]].map(&inv)
        zmax = corners.map(&:last).max
        zmin = corners.map(&:last).min
        step = [2 * r - 2.0, r].max
        levels = []
        zs = zmin - r
        while zs < zmax + r
          levels << zs
          zs += step
        end
        levels += pieces.map { |_, _, z| z + r }
        levels = levels.sort.each_with_object([]) { |v, a| a << v if a.empty? || v - a[-1] > 0.05 }
        rows = []
        levels.reverse_each do |zl|
          b0, b1 = scan_rect(corners, zl)
          next unless b0
          b0 -= r + 2.0; b1 += r + 2.0
          forb = pieces.select { |_, _, z| z > zl - r + 1e-6 }.map { |u0, u1, _| [u0 - r, u1 + r] }
          forb << [lo - r, hi + r] if pieces.empty? || zl < pieces.map(&:last).min + r - 1e-6
          allowed = subtract([[b0, b1]], forb)
          allowed.each { |a, b| rows << [zl, a, b, a <= b0 + 1e-6, b >= b1 - 1e-6] if b - a > 0.5 }
        end
        # Ketten: aufeinanderfolgende Zeilen mit gemeinsamer Wand verbinden
        paths = []
        used = Array.new(rows.size, false)
        rows.each_index do |i|
          next if used[i]
          used[i] = true
          zl, a, b, ao, bo = rows[i]
          seq = bo || !ao ? [[b, zl], [a, zl]] : [[a, zl], [b, zl]]
          loop do
            cu = seq[-1][0]
            j = (i + 1...rows.size).find do |k|
              !used[k] && rows[k][0] < seq[-1][1] - 1e-6 && rows[k][0] > seq[-1][1] - step - 1e-6 &&
                ((rows[k][1] - cu).abs < 1e-4 || (rows[k][2] - cu).abs < 1e-4)
            end
            break unless j
            used[j] = true
            z2, a2, b2, = rows[j]
            seq.concat((a2 - cu).abs < 1e-4 ? [[a2, z2], [b2, z2]] : [[b2, z2], [a2, z2]])
          end
          paths << seq.map { |q| tab(ctx, q) }
        end
        paths
      end

      def inverse(ctx)
        a = ctx[:tr].([0.0, 0.0]); ex = Geo.sub(ctx[:tr].([1.0, 0.0]), a); ez = Geo.sub(ctx[:tr].([0.0, 1.0]), a)
        det = ex[0] * ez[1] - ex[1] * ez[0]
        lambda do |q|
          d = Geo.sub(q, a)
          [(d[0] * ez[1] - d[1] * ez[0]) / det, (ex[0] * d[1] - ex[1] * d[0]) / det]
        end
      end

      # Schnitt der Waagerechten z = zl (Brettsystem) mit dem Rohling (konvex)
      def scan_rect(corners, zl)
        us = []
        corners.each_with_index do |p0, i|
          p1 = corners[(i + 1) % 4]
          next if (p0[1] - zl) * (p1[1] - zl) > 0 || (p0[1] - p1[1]).abs < 1e-12
          us << p0[0] + (zl - p0[1]) / (p1[1] - p0[1]) * (p1[0] - p0[0])
        end
        us.size >= 2 ? us.minmax : nil
      end

      def subtract(ints, cuts)
        cuts.each do |c0, c1|
          ints = ints.flat_map do |a, b|
            next [[a, b]] if c1 <= a || c0 >= b
            r = []
            r << [a, c0] if c0 > a
            r << [c1, b] if c1 < b
            r
          end
        end
        ints
      end

      # --- Schräge mit dem Seitenaggregat ------------------------------------
      # Hilfsfläche senkrecht zur Treppen-Senkrechten s, knapp über dem höchsten
      # Material an der Wand (z1 + Freiraum); Normale = +s (Anfahrt von oben).
      # Bahnen in Flächen-Koordinaten (fx quer, fy = Tisch-Z), Tiefe = −Abstand.
      def aggregate(ctx, w, flip)
        o = ctx[:o]; t = ctx[:t]
        r = o['agg_d'].to_f / 2.0
        len = o['agg_len'].to_f; clr = o['agg_clear'].to_f
        zf = w[:z1] + clr
        ztip = [w[:z0], zf - len].max
        rest = ztip - w[:z0]
        # auf dieser Seite oben/unten
        u_top, u_bot = w[:side] == 1 ? w[:u_top] : w[:u_top].reverse
        pt = ->(u, z) { tab(ctx, [u, z], flip) }
        nvec = Geo.norm(Geo.sub(pt.(0.0, 1.0), pt.(0.0, 0.0)))     # +s im Tisch
        xvec = [-nvec[1], nvec[0]]                                   # rechtshändig: X × Z = N
        base = pt.(u_bot, zf)
        org = Geo.sub(base, Geo.mul(xvec, 200.0))
        fx = ->(u) { Geo.dot(Geo.sub(pt.(u, zf), org), xvec) }
        xb = fx.(u_bot); xt = fx.(u_top)
        # Materialseite in fx: Richtung von +u
        du = fx.(1.0) - fx.(0.0)
        msign = (w[:mat] * du) > 0 ? 1.0 : -1.0
        # Wandlinie (fx, Z) von unten (xb, 0) nach oben (xt, t)
        dvec = Geo.norm([xt - xb, t])
        nrm = [-dvec[1], dvec[0]]
        nrm = Geo.mul(nrm, -1) if nrm[0] * msign > 0                # zur Luftseite
        far = (xt - xb).abs * t / Math.hypot(xt - xb, t)
        stp = [2 * r - 4.0, 2.0].max
        dists = (0..40).map { |i| r + stp * i }.take_while { |d| d < far + r }
        dists = [r] if dists.empty?
        seq = []
        dists.reverse.each_with_index do |dd, i|
          c = Geo.add([xb, 0.0], Geo.mul(nrm, dd))
          a = Geo.add(c, Geo.mul(dvec, (r - 1.0 - c[1]) / dvec[1]))
          b = Geo.add(c, Geo.mul(dvec, (t + 10.0 - c[1]) / dvec[1]))
          seq.concat(i.even? ? [b, a] : [a, b])
        end
        full = zf - ztip
        zst = [o['agg_step'].to_f, 5.0].max
        depths = []
        d = zst
        while d < full - 1e-6
          depths << d
          d += zst
        end
        depths << full
        corners = [[org[0], org[1], 0.0], [org[0] + xvec[0] * 400, org[1] + xvec[1] * 400, 0.0], [org[0], org[1], t]]
        { face: { corners: corners, depth_z: len + 50, paths: depths.map { |dp| [seq, -dp] }, tool: o['agg_tool'].to_i,
                  axis: [base, nvec], wall: w, xb: xb, xt: xt, msign: msign, r: r, t: t }, rest: rest }
      end
    end
  end
end
