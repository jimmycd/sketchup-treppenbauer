# encoding: UTF-8
# Treppenbau – Zerlegung der Treppe in flache, fräsbare Einzelteile (mm).
#
# Jedes Teil wird so gedreht, dass seine Faserrichtung entlang +X liegt,
# und auf den Ursprung (min X / min Y = 0) geschoben.
#   Trittstufen/Podeste  – Faser entlang der Stufenvorderkante
#   Setzstufen           – Faser entlang der Länge
#   Wangen               – abgewickelt, Faser entlang der Wange; mit Nuten
#                          (Einstand) für Tritt- und Setzstufen
#   Pfosten / Stäbe      – Zuschnitt (Länge × Querschnitt)
#   Handlauf             – nur gerade Stücke
#   Bohrungen (drills)   – Geländerstäbe: lotrecht in Wangenoberkante bzw.
#                          Trittstufe; je Bohrung { x:, y:, depth:, d:, ang: }
#                          in mm im Teilekoordinatensystem, ang = Winkel der
#                          Bohrrichtung in der Teilebene (Grad, nur Wangen –
#                          Bohrung von der Kante aus, schräg zur Kante);
#                          bei Trittstufen von oben (ang = nil)

module JTools
  module Treppenbau
    class Part
      attr_accessor :id, :label, :kind, :thickness, :poly, :pockets, :pocket_depth, :info, :pocket_paths, :drills

      def initialize(kind, label, thickness, poly, pockets = [], pocket_depth = 0.0, info = '')
        @kind = kind
        @label = label
        @thickness = thickness.round(1)
        @poly = poly
        @pockets = pockets
        @pocket_depth = pocket_depth
        @info = info
        @pocket_paths = []
        @drills = []
      end

      def area
        Geo.signed_area(@poly).abs
      end

      def size
        xs = @poly.map(&:first); ys = @poly.map(&:last)
        [xs.max - xs.min, ys.max - ys.min]
      end
    end

    module Parts
      module_function

      MM = 10.0
      KIND_NAMES = {
        tread: 'Trittstufe', landing: 'Podest', riser: 'Setzstufe', stringer: 'Wange',
        newel: 'Pfosten (Wange)', post: 'Geländerpfosten', bar: 'Geländerstab', rail: 'Handlauf'
      }.freeze

      # opts: :treads, :risers, :stringers, :posts, :rail (bool), :einstand (mm)
      def collect(plan, p, opts)
        parts = []
        warnings = []
        cons = p['construction']
        st_sides = Builder.stringer_sides(plan, p)
        einstand = st_sides.empty? ? 0.0 : opts[:einstand].to_f
        if cons == 'massiv'
          warnings << 'Massivtreppe: Stufen und Laufplatte sind Beton – es werden nur Geländerteile exportiert.'
        end

        if cons != 'massiv'
          parts.concat(treads(plan, p, st_sides, einstand)) if opts[:treads]
          parts.concat(risers(plan, p, st_sides, einstand)) if opts[:risers] && p['risers']
        end
        if cons == 'wange' && opts[:stringers]
          sp, sw = stringers(plan, p, einstand, (opts[:pocket_d] || 10.0).to_f)
          parts.concat(sp); warnings.concat(sw)
        end
        if p['rail'] != 'keins'
          if opts[:posts]
            parts.concat(posts(plan, p))
            rb = round_bars(plan, p)
            unless rb.empty?
              warnings << format('Runde Geländerstäbe werden nicht aus der Platte gefräst: %d Stück Ø %s mm, Längen %s mm (Zuschnitt vom Rundstab).',
                                 rb.size, format('%g', (rb[0][:d] * MM).round(1)).tr('.', ','), rb.map { |q| (q[:ztop] - q[:zbot]) * MM }.minmax.map(&:round).uniq.join('–'))
            end
          end
          if opts[:rail]
            rp, rw = rails(plan, p)
            parts.concat(rp); warnings.concat(rw)
          end
        end
        if cons == 'holm'
          warnings << 'Holm (Mittelholm) wird nicht exportiert (Stahl bzw. Kantholz).'
        end
        parts.each_with_index { |pt, i| pt.id = i + 1 }
        [parts, warnings]
      end

      # ---------------------------------------------------------------------
      # Trittstufen / Podeste

      def treads(plan, p, st_sides, einstand)
        lw = plan.lines_w
        ext = p['nosing'] + (p['risers'] ? p['riser_t'] : 0.0)
        res = []
        nr = 0
        (0...plan.treads).each do |k|
          poly = extended_region(plan, lw[k], [lw[k + 1] + ext, plan.wtot].min, st_sides, einstand)
          l = plan.line(lw[k])
          landing = plan.kinds[k] == :landing
          nr += 1 unless landing
          label = landing ? "P#{k + 1}" : "T#{k + 1}"
          axis = Geo.sub(l[:out], l[:in])
          axis = Geo.mul(axis, -1) if plan.outer_side < 0
          holes = tread_drills(plan, p, k)
          rot, = rotation_for(axis)
          pp, hp = transform_all(poly.map { |q| Geo.mul(q, MM) }, holes.map { |q| [Geo.mul(q[:pt], MM)] }, rot)
          part = Part.new(landing ? :landing : :tread, label, p['tread_t'] * MM, pp, [], 0.0,
                          landing ? 'Podest' : "Stufe #{k + 1}")
          part.drills = holes.each_with_index.map { |q, i| { x: hp[i][0][0], y: hp[i][0][1], depth: q[:depth] * MM, d: q[:d] * MM, ang: nil } }
          part.info += ", #{part.drills.size} Bohrungen (Geländerstäbe)" unless part.drills.empty?
          res << part
        end
        res
      end

      # Bohrungen für Geländerstäbe auf Stufe k (cm, Grundriss)
      def tread_drills(plan, p, k)
        return [] if p['rail'] == 'keins'
        Railing.compute(plan, p)[:sides].flat_map do |sd|
          next [] unless sd[:mount] == :stufe
          sd[:bars].select { |b| b[:tread] == k && b[:drill] }.map { |b| { pt: b[:pt], depth: b[:drill][:depth], d: b[:drill][:d] } }
        end
      end

      def risers(plan, p, st_sides, einstand)
        lw = plan.lines_w
        res = []
        (0...plan.treads).each do |k|
          l = plan.line(lw[k] + p['nosing'])
          len = Geo.dist(l[:in], l[:out]) * MM
          len += einstand if st_sides.include?(:outer)
          len += einstand if st_sides.include?(:inner) && plan.inner.length > 0
          hgt = (plan.h - p['tread_t']) * MM
          next if hgt < 5
          res << Part.new(:riser, "R#{k + 1}", p['riser_t'] * MM, rect(len, hgt), [], 0.0, "Setzstufe #{k + 1}")
        end
        res
      end

      # Stufenfläche, an den Wangenseiten um den Einstand verlängert (cm)
      def extended_region(plan, wa, wb, st_sides, einstand)
        la = plan.line(wa); lb = plan.line(wb)
        oc = [la[:out]] + plan.outer.between(la[:t], lb[:t]).map(&:first) + [lb[:out]]
        ic = [la[:in]] + plan.inner.between(la[:s], lb[:s]).map(&:first) + [lb[:in]]
        e = einstand / MM
        oc = offset_chain(oc, plan.outer_side, e) if e > 0 && st_sides.include?(:outer)
        ic = offset_chain(ic, -plan.outer_side, e) if e > 0 && st_sides.include?(:inner)
        Geo.clean_ring(oc + ic.reverse, 0.01)
      end

      def offset_chain(chain, side, d)
        c = []
        chain.each { |q| c << q if c.empty? || Geo.dist(c[-1], q) > 0.01 }
        return chain if c.size < 2
        mn = Geo.miter_normals(c, side)
        c.each_with_index.map { |q, i| Geo.add(q, Geo.mul(mn[i], d)) }
      end

      # ---------------------------------------------------------------------
      # Wangen (abgewickelt, nur gerade Abschnitte)

      def stringers(plan, p, einstand, pocket_d = 10.0)
        res = []
        warnings = []
        r = Stringers.compute(plan, p)
        warnings.concat(r[:warnings])
        st = p['str_t']
        lw = plan.lines_w
        d = p['tread_t']; u = p['nosing']; ts = p['riser_t']
        ext = u + (p['risers'] ? ts : 0.0)
        skipped = 0
        # Einstand je Stufe als Stufenlinien (Gehlinienpositionen) und Höhen:
        # Trittstufe (inkl. Unterschneidung) und Setzstufe darunter
        pockets = {}
        %i[outer inner].each do |which|
          pk = []
          (0...plan.treads).each do |k|
            top = (k + 1) * plan.h
            pk << [lw[k], [lw[k + 1] + ext, plan.wtot].min, top - d, top]
            pk << [lw[k] + u, lw[k] + u + ts, k * plan.h, top - d] if p['risers']
          end
          pockets[which] = pk
        end
        cnt = Hash.new(0)
        r[:wange].each do |b|
          if b[:u1] - b[:u0] < 25.0
            skipped += 1
            next
          end
          cnt[b[:which]] += 1
          lbl = "W#{b[:which] == :outer ? 'A' : 'I'}#{cnt[b[:which]]}"
          part = board_part(plan, b, b[:side] > 0, pockets[b[:which]], einstand, st * MM, lbl,
                            "Wange #{b[:which] == :outer ? 'außen' : 'innen'} #{cnt[b[:which]]}", pocket_d, wange_drills(plan, p, b))
          part.info += ", #{part.drills.size} Bohrungen (Geländerstäbe)" unless part.drills.empty?
          res << part
        end
        # Eckpfosten nur auf Seiten ohne Geländer (sonst Geländerpfosten)
        r[:newels].each do |nw|
          z1 = nw[:ztop] + 10.0
          res << Part.new(:newel, "N#{res.count { |x| x.kind == :newel } + 1}", st * MM,
                          rect((z1 - nw[:zbot]) * MM, st * MM), [], 0.0, 'Eckpfosten Wange')
        end
        r[:sattel].each do |sb|
          if sb[:len] < 10.0
            skipped += 1
            next
          end
          lbl = "S#{sb[:which] == :outer ? 'A' : 'I'}#{sb[:nr]}"
          poly = sb[:poly].map { |x, z| [x * MM, z * MM] }
          mirror = sb[:side] > 0
          poly = poly.map { |x, z| [sb[:len] * MM - x, z] } if mirror
          axis = [1.0, 0.0]
          # Faser entlang der Unterkante (längste Kante)
          best = nil
          poly.each_with_index do |q, i|
            q2 = poly[(i + 1) % poly.size]
            l = Geo.dist(q, q2)
            best = [l, Geo.sub(q2, q)] if best.nil? || l > best[0]
          end
          axis = best[1] if best
          axis = [mirror ? -sb[:grain][0] : sb[:grain][0], sb[:grain][1]] if sb[:grain]
          axis = Geo.mul(axis, -1) if axis[0] < 0
          rot, = rotation_for(axis)
          pp, = transform_all(poly, [], rot)
          res << Part.new(:stringer, lbl, sb[:t] * MM, pp, [], 0.0,
                          "Aufgesattelte Wange #{sb[:which] == :outer ? 'außen' : 'innen'} #{sb[:nr]}")
        end
        if skipped > 0
          warnings << "#{skipped} sehr kurze Wangenabschnitte (z. B. an Innenecken) fehlen im Export."
        end
        [res, warnings]
      end

      # Abgewickeltes Wangenbrett mit Nuten.
      # Die Nut ist die exakte Ausstemmung: Vereinigung der Querschnitte von
      # Trittstufe (mit Unterschneidung) und Setzstufe – über die ganze Nuttiefe
      # (bei schräg auf die Wange treffenden Stufenkanten im Wendelbereich
      # verschiebt sich die Kante mit der Tiefe; die Nut deckt beides ab).
      # Zusammenhängende Ausstemmungen werden zu einer Kontur vereinigt.
      def board_part(plan, b, mirror, steps, einstand, thick, label, info, pocket_d = 10.0, drills = [])
        p0 = b[:u0]; p1 = b[:u1]
        mapx = ->(s) { (mirror ? (p1 - s) : (s - p0)) * MM }
        poly = Stringers.wange_outline(b).map { |x, z| [mapx.(p0 + x), z * MM] }
        poly = Geo.clean_ring(poly, 0.05)
        len = (p1 - p0) * MM
        outl = []
        cuts = []
        if einstand > 0
          e = einstand / MM
          nrm = b[:side] > 0 ? Geo.right(b[:dir]) : Geo.left(b[:dir])
          ext = pocket_d / 2.0 + 0.5
          steps.each do |wa, wb, z0, z1|
            next if z1 - z0 < 0.005
            cu = [wa, wb].map { |w| cross_u(plan, b, w, e, nrm) }
            # nur Stufen, die die Wangenfläche dieses Bretts treffen
            fa, fb = cu.map(&:first).minmax
            # Prüfung im ursprünglichen Bereich (ohne Verlängerung über die Ecke)
            r0 = [p0, b[:ru0] || p0].max; r1 = [p1, b[:ru1] || p1].min
            next if [fb, r1].min - [fa, r0].max < 0.05
            a, bb = cu.flatten.minmax
            # über die Ecke verlängertes Brett: Nut nur bis zur Einstandstiefe
            # in die Verlängerung (dort liegt das andere Brett an)
            a = [a, p0 + b[:ext0] - e].max if b[:ext0].to_f > 0
            bb = [bb, p1 - b[:ext1] + e].min if b[:ext1].to_f > 0
            next if bb - a < 0.01
            # ganz unterhalb des Bretts (über die Ecke laufende Stufe am Eckpfosten)
            ua = [fa, r0].max; ub = [fb, r1].min
            next if z0 > 0.05 && z1 <= [Stringers.bot(b, ua), Stringers.bot(b, ub)].min + 0.05
            xa, xb = [mapx.(a), mapx.(bb)].minmax
            za = z0 * MM; zb = z1 * MM
            outl << [[xa, 0.0].max, za, [xb, len].min, zb]
            # offene Enden (Brettende, Boden) für die Fräsbahn überfahren
            cx0 = xa <= 0.5 ? -ext : xa
            cx1 = xb >= len - 0.5 ? len + ext : xb
            cz0 = za <= 0.5 ? za - ext : za
            cuts << [cx0, cz0, cx1, zb]
          end
        end
        pk = Pockets.union(outl)
        paths = Pockets.clearing_paths(cuts, pocket_d)
        # Faser entlang der Oberkante
        axis = [mapx.(p1) - mapx.(p0), (Stringers.top(b, p1) - Stringers.top(b, p0)) * MM]
        axis = Geo.mul(axis, -1) if axis[0] < 0
        rot, = rotation_for(axis)
        # Bohrungen: Ansatzpunkt auf der Oberkante, Richtung lotrecht nach unten
        holes = drills.map { |q| [[mapx.(q[:u]), q[:z] * MM]] }
        pp, all = transform_all(poly, pk + paths + holes, rot)
        part = Part.new(:stringer, label, thick, pp, all[0, pk.size], einstand, info)
        part.pocket_paths = all[pk.size, paths.size] || []
        dv = Geo.rot([0.0, -1.0], rot)
        ang = Math.atan2(dv[1], dv[0]) * 180.0 / Math::PI
        part.drills = drills.each_with_index.map do |q, i|
          h = all[pk.size + paths.size + i][0]
          { x: h[0], y: h[1], depth: q[:depth] * MM, d: q[:d] * MM, ang: ang.round(2) }
        end
        part
      end

      # Bohrungen der Geländerstäbe in einem Wangenbrett (cm, u/z)
      def wange_drills(plan, p, b)
        return [] if p['rail'] == 'keins'
        Railing.compute(plan, p)[:sides].flat_map do |sd|
          next [] unless sd[:mount] == :wange && sd[:which] == b[:which]
          sd[:bars].select { |q| q[:drill] && q[:u] >= b[:u0] + 0.01 && q[:u] <= b[:u1] - 0.01 }.map { |q| q[:drill] }
        end
      end

      # Parameter (u) des Schnitts einer Stufenlinie mit der Wangenfläche und
      # mit der um die Nuttiefe e (cm) versetzten Ebene
      def cross_u(plan, b, w, e, nrm)
        w = [[w, 0.0].max, plan.wtot].min
        l = plan.line(w)
        outer = b[:which] == :outer
        uf = outer ? l[:t] : l[:s]
        dl = outer ? Geo.sub(l[:out], l[:in]) : Geo.sub(l[:in], l[:out])
        return [uf] if Geo.len(dl) < 1e-9
        dl = Geo.norm(dl)
        c = Geo.dot(dl, nrm)
        return [uf] if c < 0.2
        [uf, uf + e * Geo.dot(dl, b[:dir]) / c]
      end

      # ---------------------------------------------------------------------
      # Geländer

      def rail_sides(plan, p)
        Railing.sides(plan, p)
      end

      # Geländerpfosten und -stäbe als Zuschnitt (Länge × Querschnitt)
      def posts(plan, p)
        res = []
        Railing.compute(plan, p)[:sides].each do |sd|
          nm = sd[:which] == :outer ? 'außen' : 'innen'
          sd[:posts].each do |q|
            ln = q[:ztop] - q[:zbot]
            next if ln < 2
            res << Part.new(:post, "G#{res.count { |x| x.kind == :post } + 1}", q[:s] * MM, rect(ln * MM, q[:s] * MM), [], 0.0,
                            "Geländerpfosten #{nm} (#{q[:role]})")
          end
          sd[:bars].each do |q|
            ln = q[:ztop] - q[:zbot]
            next if ln < 2 || q[:shape] == 'rund'
            res << Part.new(:bar, "ST#{res.count { |x| x.kind == :bar } + 1}", q[:d] * MM, rect(ln * MM, q[:d] * MM), [], 0.0,
                            "Geländerstab #{nm}")
          end
        end
        res
      end

      # Runde Geländerstäbe (kein Plattenteil, nur Zuschnittliste)
      def round_bars(plan, p)
        Railing.compute(plan, p)[:sides].flat_map do |sd|
          sd[:bars].select { |q| q[:shape] == 'rund' && q[:ztop] - q[:zbot] >= 2 }
        end
      end

      # Handlauf je Feld als Platte (Dicke = Handlaufbreite), Umriss in der
      # Seitenansicht abgewickelt: gerade = Parallelogramm, geschwungen = aus
      # dem Vollen gefräster Bogen. Im Grundriss gebogene Stücke (Wendeltreppe)
      # werden nicht exportiert.
      def rails(plan, p)
        res = []
        skipped = 0
        Railing.compute(plan, p)[:sides].each do |sd|
          sd[:rails].each do |rl|
            pts = rl[:pts]
            dir = Geo.norm(Geo.sub(pts[-1], pts[0]))
            bent = pts.any? { |q| Geo.cross(dir, Geo.sub(q, pts[0])).abs > 0.5 }
            if bent || rl[:ub] - rl[:ua] < 10.0
              skipped += 1
              next
            end
            xs = pts.map { |q| Geo.dot(Geo.sub(q, pts[0]), dir) }
            top = xs.each_with_index.map { |x, i| [x * MM, rl[:tops][i] * MM] }
            bot = xs.each_with_index.map { |x, i| [x * MM, rl[:bots][i] * MM] }.reverse
            poly = Geo.clean_ring(top + bot, 0.05)
            # Faser entlang der Sehne der Oberkante
            axis = Geo.sub(top[-1], top[0])
            rot, = rotation_for(axis)
            pp, = transform_all(poly, [], rot)
            info = rl[:curved] ? 'Handlauf geschwungen (aus dem Vollen gefräst)' : 'Handlauf'
            res << Part.new(:rail, "H#{res.size + 1}", rl[:w] * MM, pp, [], 0.0,
                            "#{info} #{sd[:which] == :outer ? 'außen' : 'innen'}")
          end
        end
        w = []
        w << "#{skipped} im Grundriss gebogene bzw. sehr kurze Handlaufstücke werden nicht exportiert." if skipped > 0
        [res, w]
      end

      # Gerade 3D-Abschnitte eines Pfads (Knick in Grundriss oder Steigung > 1°)
      def straight_runs(path)
        runs = []
        start = path[0]
        prev_dir = nil
        (1...path.size).each do |i|
          a = path[i - 1]; b = path[i]
          v = [b[0] - a[0], b[1] - a[1], b[2] - a[2]]
          l = Math.sqrt(v.map { |x| x * x }.sum)
          next if l < 1e-6
          v = v.map { |x| x / l }
          if prev_dir
            c = prev_dir.zip(v).map { |x, y| x * y }.sum
            if c < Math.cos(1.0 * Math::PI / 180.0)
              runs << [start, a]
              start = a
            end
          end
          prev_dir = v
        end
        runs << [start, path[-1]]
        runs
      end

      # ---------------------------------------------------------------------
      # Hilfsfunktionen

      def rect(l, w)
        [[0.0, 0.0], [l, 0.0], [l, w], [0.0, w]]
      end

      def rect_pts(x0, y0, x1, y1)
        [[x0, y0], [x1, y0], [x1, y1], [x0, y1]]
      end

      def rotation_for(axis)
        [-Math.atan2(axis[1], axis[0])]
      end

      # Dreht so, dass axis entlang +X liegt, und schiebt auf den Ursprung.
      def align(poly, axis)
        rot, = rotation_for(axis)
        transform_all(poly, [], rot)[0]
      end

      def transform_all(poly, pockets, rot)
        r = ->(q) { Geo.rot(q, rot) }
        pp = poly.map(&r)
        pk = pockets.map { |pc| pc.map(&r) }
        minx = pp.map(&:first).min; miny = pp.map(&:last).min
        sh = ->(q) { [q[0] - minx, q[1] - miny] }
        pp = pp.map(&sh)
        pp.reverse! if Geo.signed_area(pp) < 0
        [pp, pk.map { |pc| pc.map(&sh) }]
      end
    end
    # Nuten: Vereinigung achsparalleler Rechtecke und Ausräumbahnen (mm).
    # Arbeitet im Brettkoordinatensystem (vor der Drehung), dort sind alle
    # Ausstemmungen aus waagerechten/lotrechten Kanten zusammengesetzt.
    module Pockets
      module_function

      TOL = 1e-4

      def uniq(vals)
        vals.sort.each_with_object([]) { |v, o| o << v if o.empty? || v - o[-1] > TOL }
      end

      def index(xs, v)
        i = xs.bsearch_index { |x| x >= v - TOL }
        i || xs.size - 1
      end

      # rects [[x0, y0, x1, y1], ...] -> [xs, ys, inside[i][j]]
      def grid(rects)
        rects = rects.select { |r| r[2] - r[0] > TOL && r[3] - r[1] > TOL }
        return nil if rects.empty?
        xs = uniq(rects.flat_map { |r| [r[0], r[2]] })
        ys = uniq(rects.flat_map { |r| [r[1], r[3]] })
        ins = Array.new(xs.size - 1) { Array.new(ys.size - 1, false) }
        rects.each do |r|
          i0 = index(xs, r[0]); i1 = index(xs, r[2])
          j0 = index(ys, r[1]); j1 = index(ys, r[3])
          (i0...i1).each { |i| (j0...j1).each { |j| ins[i][j] = true } }
        end
        [xs, ys, ins]
      end

      # Umrisse (außen gegen den Uhrzeigersinn, Löcher im Uhrzeigersinn)
      def union(rects)
        g = grid(rects)
        g ? rings(*g) : []
      end

      def rings(xs, ys, ins)
        nx = xs.size - 1; ny = ys.size - 1
        cell = ->(i, j) { i >= 0 && j >= 0 && i < nx && j < ny && ins[i][j] }
        out = Hash.new { |h, k| h[k] = [] }
        nx.times do |i|
          ny.times do |j|
            next unless ins[i][j]
            out[[i, j]] << [i + 1, j] unless cell.(i, j - 1)
            out[[i + 1, j]] << [i + 1, j + 1] unless cell.(i + 1, j)
            out[[i + 1, j + 1]] << [i, j + 1] unless cell.(i, j + 1)
            out[[i, j + 1]] << [i, j] unless cell.(i - 1, j)
          end
        end
        res = []
        until out.empty?
          start = out.keys.first
          ring = [start]
          cur = start
          prev_d = nil
          loop do
            cands = out[cur]
            nxt = if cands.size > 1 && prev_d
                    # an Berührungsecken rechts abbiegen (Bereiche getrennt halten)
                    cands.min_by do |c|
                      d = [c[0] - cur[0], c[1] - cur[1]]
                      -(prev_d[0] * d[1] - prev_d[1] * d[0])
                    end
                  else
                    cands[0]
                  end
            cands.delete(nxt)
            out.delete(cur) if cands.empty?
            prev_d = [nxt[0] - cur[0], nxt[1] - cur[1]]
            cur = nxt
            break if cur == start
            ring << cur
          end
          pts = ring.map { |i, j| [xs[i], ys[j]] }
          res << simplify(pts) if pts.size >= 4
        end
        res.reject { |r| r.size < 4 }
      end

      def simplify(pts)
        n = pts.size
        pts.each_with_index.reject do |q, i|
          a = pts[(i - 1) % n]; b = pts[(i + 1) % n]
          ((q[0] - a[0]) * (b[1] - q[1]) - (q[1] - a[1]) * (b[0] - q[0])).abs < 1e-9
        end.map(&:first)
      end

      # Mittelpunktsbereich eines quadratischen Werkzeugs mit halber Kantenlänge s
      # (Erosion), als Raster
      def erode(xs, ys, ins, s)
        nx = xs.size - 1; ny = ys.size - 1
        ps = Array.new(nx + 1) { Array.new(ny + 1, 0) }
        nx.times do |i|
          ny.times do |j|
            ps[i + 1][j + 1] = ps[i][j + 1] + ps[i + 1][j] - ps[i][j] + (ins[i][j] ? 0 : 1)
          end
        end
        lo_x = xs[0] + s; hi_x = xs[-1] - s
        lo_y = ys[0] + s; hi_y = ys[-1] - s
        return nil if hi_x - lo_x < TOL || hi_y - lo_y < TOL
        fx = uniq((xs + xs.map { |x| x + s } + xs.map { |x| x - s }).select { |x| x >= lo_x - TOL && x <= hi_x + TOL })
        fy = uniq((ys + ys.map { |y| y + s } + ys.map { |y| y - s }).select { |y| y >= lo_y - TOL && y <= hi_y + TOL })
        return nil if fx.size < 2 || fy.size < 2
        any = false
        fin = Array.new(fx.size - 1) do |i|
          cx = (fx[i] + fx[i + 1]) / 2.0
          k0 = xs.bsearch_index { |x| x > cx - s } - 1
          k1 = (xs.bsearch_index { |x| x >= cx + s } || xs.size) - 1
          Array.new(fy.size - 1) do |j|
            cy = (fy[j] + fy[j + 1]) / 2.0
            l0 = ys.bsearch_index { |y| y > cy - s } - 1
            l1 = (ys.bsearch_index { |y| y >= cy + s } || ys.size) - 1
            a0 = [k0, 0].max; a1 = [k1, nx - 1].min + 1
            b0 = [l0, 0].max; b1 = [l1, ny - 1].min + 1
            q = ps[a1][b1] - ps[a0][b1] - ps[a1][b0] + ps[a0][b0]
            v = q.zero?
            any ||= v
            v
          end
        end
        any ? [fx, fy, fin] : nil
      end

      # Ausräumbahnen (geschlossene Linienzüge, Werkzeugmitte) für die
      # Vereinigung der Rechtecke: konzentrische Bahnen von innen nach außen,
      # die letzte Bahn fährt die Nutkontur im Abstand Fräserradius ab.
      def clearing_paths(rects, d)
        g = grid(rects)
        return [] unless g
        r = d / 2.0
        s0 = [r - 0.005, 0.01].max
        step = [0.5 * d, 0.5].max
        levels = []
        s = s0
        while (e = erode(*g, s)) && levels.size < 200
          levels << [s, rings(*e)]
          s += step
        end
        # Bereiche, die zur nächsten Bahn hin verschwinden, aber in der Mitte
        # weiter als der Fräserradius von ihrer Bahn entfernt sind: Zusatzbahn
        # mit kleinerem Abstand (kein Restmaterial)
        out = []
        levels.each_with_index do |(sk, rs), k|
          nxt = levels[k + 1] ? levels[k + 1][1] : []
          extra = []
          ee = erode(*g, sk + 0.7 * r)
          if ee
            rings(*ee).each do |re|
              next if Geo.signed_area(re) <= 0
              next if nxt.any? { |rn| inside?(rn[0], re) }
              extra << re
            end
          end
          out << [rs, extra]
        end
        paths = []
        out.reverse_each do |rs, extra|
          (extra + rs).each do |ring|
            ring = ring.reverse if Geo.signed_area(ring) < 0
            paths << ring + [ring[0]]
          end
        end
        paths
      end

      def inside?(pt, poly)
        x, y = pt
        c = false
        poly.each_with_index do |(x1, y1), i|
          x2, y2 = poly[(i + 1) % poly.size]
          next if (y1 > y) == (y2 > y)
          c = !c if x < x1 + (y - y1) * (x2 - x1) / (y2 - y1)
        end
        c
      end
    end
  end
end
