# encoding: UTF-8
# Treppenbau – reine Geometrie (ohne SketchUp-API, dadurch testbar).
#
# Prinzip: Jede Treppe wird im Grundriss durch drei Polylinien beschrieben,
# die alle in Laufrichtung (aufwärts) orientiert sind:
#   inner  – innere Begrenzung der Laufbreite (Treppenauge / Spindel)
#   walk   – Gehlinie
#   outer  – äußere Begrenzung der Laufbreite
# Eine Stufenvorderkante ("Linie") ist durch eine Position w auf der Gehlinie
# festgelegt: Sie verläuft vom Innenpunkt inner(s(w)) durch walk(w) bis zum
# Schnitt mit outer. Über die Zuordnung s(w) (stückweise linear) wird das
# Verziehen der Stufen in Wendelbereichen gesteuert. Auf der Gehlinie sind
# alle Auftritte damit exakt gleich groß.

module JTools
  module Treppenbau

    class PlanError < StandardError; end

    module Geo
      EPS = 1e-6
      module_function

      def add(a, b);  [a[0] + b[0], a[1] + b[1]]; end
      def sub(a, b);  [a[0] - b[0], a[1] - b[1]]; end
      def mul(a, s);  [a[0] * s, a[1] * s]; end
      def dot(a, b);  a[0] * b[0] + a[1] * b[1]; end
      def cross(a, b); a[0] * b[1] - a[1] * b[0]; end
      def len(a);     Math.sqrt(dot(a, a)); end
      def dist(a, b); len(sub(a, b)); end
      def right(a);   [a[1], -a[0]]; end
      def left(a);    [-a[1], a[0]]; end
      def lerp(a, b, t); [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t]; end

      def norm(a)
        l = len(a)
        l < 1e-12 ? [0.0, 0.0] : [a[0] / l, a[1] / l]
      end

      def rot(a, ang)
        c = Math.cos(ang); s = Math.sin(ang)
        [a[0] * c - a[1] * s, a[0] * s + a[1] * c]
      end

      def signed_area(pts)
        s = 0.0
        pts.each_with_index do |p, i|
          q = pts[(i + 1) % pts.size]
          s += p[0] * q[1] - q[0] * p[1]
        end
        s / 2.0
      end

      # Entfernt doppelte, aufeinanderfolgende Punkte (auch Anfang = Ende).
      # items: Array von Punkten ODER Array von [Punkt, Daten]-Paaren.
      def clean_ring(items, tol = 0.01, paired = false)
        pt = ->(it) { paired ? it[0] : it }
        out = []
        items.each { |it| out << it if out.empty? || dist(pt.(out[-1]), pt.(it)) > tol }
        out.pop while out.size > 1 && dist(pt.(out[0]), pt.(out[-1])) <= tol
        out
      end

      # Ear-Clipping-Triangulierung. Liefert Index-Tripel (gegen den Uhrzeigersinn).
      def triangulate(pts)
        n = pts.size
        return [] if n < 3
        idx = (0...n).to_a
        idx.reverse! if signed_area(pts) < 0
        tris = []
        guard = 0
        while idx.size > 3 && guard < 10_000
          guard += 1
          ear = false
          idx.size.times do |i|
            ia = idx[(i - 1) % idx.size]; ib = idx[i]; ic = idx[(i + 1) % idx.size]
            a = pts[ia]; b = pts[ib]; c = pts[ic]
            next if cross(sub(b, a), sub(c, b)) <= 1e-12 # reflex / kollinear
            inside = idx.any? do |j|
              next false if j == ia || j == ib || j == ic
              point_in_tri?(pts[j], a, b, c)
            end
            next if inside
            tris << [ia, ib, ic]
            idx.delete_at(i)
            ear = true
            break
          end
          unless ear
            # Fallback (degenerierte Polygone): Fächer
            (1...idx.size - 1).each { |k| tris << [idx[0], idx[k], idx[k + 1]] }
            return tris
          end
        end
        tris << idx if idx.size == 3
        tris
      end

      def point_in_tri?(p, a, b, c)
        d1 = cross(sub(b, a), sub(p, a))
        d2 = cross(sub(c, b), sub(p, b))
        d3 = cross(sub(a, c), sub(p, c))
        d1 > 1e-12 && d2 > 1e-12 && d3 > 1e-12
      end

      # Gehrungs-Normalen einer offenen Polylinie (side +1 = rechts, -1 = links).
      def miter_normals(pts, side)
        n = pts.size
        segn = (0...n - 1).map do |i|
          d = norm(sub(pts[i + 1], pts[i]))
          side > 0 ? right(d) : left(d)
        end
        (0...n).map do |i|
          if i == 0 then segn[0]
          elsif i == n - 1 then segn[-1]
          else
            m = norm(add(segn[i - 1], segn[i]))
            m = segn[i] if len(m) < 1e-9
            c = dot(m, segn[i])
            c = 0.3 if c < 0.3
            mul(m, 1.0 / c)
          end
        end
      end

      def tangents(pts)
        n = pts.size
        (0...n).map do |i|
          a = pts[[i - 1, 0].max]; b = pts[[i + 1, n - 1].min]
          norm(sub(b, a))
        end
      end

      # Liegt q streng innerhalb des konvexen Polygons c (gegen den Uhrzeigersinn)?
      def in_convex?(c, q, eps = 1e-7)
        c.each_index.all? { |i| cross(sub(c[(i + 1) % c.size], c[i]), sub(q, c[i])) > eps }
      end

      # Bereich [t_in, t_out] der Strecke a–b innerhalb des konvexen Polygons c
      # (gegen den Uhrzeigersinn); nil = berührt es nicht
      def clip_convex(c, a, b)
        t0 = 0.0; t1 = 1.0
        d = sub(b, a)
        c.each_index do |k|
          e = sub(c[(k + 1) % c.size], c[k])
          ni = left(e)
          num = dot(ni, sub(a, c[k]))
          den = dot(ni, d)
          if den.abs < 1e-12
            return nil if num <= 1e-9
            next
          end
          t = -num / den
          den > 0 ? (t0 = t if t > t0) : (t1 = t if t < t1)
          return nil if t1 - t0 < 1e-9
        end
        [t0, t1]
      end

      # Polygon poly ohne das konvexe Polygon cv (z. B. Pfostenquerschnitt).
      # Ergebnis gegen den Uhrzeigersinn. Liegt cv ganz innerhalb von poly
      # (Loch) oder berührt es nicht, bleibt poly unverändert; liegt poly ganz
      # in cv, ist das Ergebnis leer. Zerfällt poly in mehrere Stücke, wird das
      # größte geliefert (Splitter an der Spitze entfallen).
      def subtract_convex(poly, cv)
        pts = clean_ring(poly.map { |q| [q[0].to_f, q[1].to_f] }, 1e-6)
        return poly if pts.size < 3
        pts = pts.reverse if signed_area(pts) < 0
        c = cv.map { |q| [q[0].to_f, q[1].to_f] }
        c = c.reverse if signed_area(c) < 0
        n = pts.size
        # Knoten: [:v, Punkt, innen?] bzw. [:in / :out, Punkt]
        nodes = []
        n.times do |i|
          a = pts[i]; b = pts[(i + 1) % n]
          nodes << [:v, a, in_convex?(c, a)]
          r = clip_convex(c, a, b)
          next unless r
          nodes << [:in, lerp(a, b, r[0])] if r[0] > 1e-9
          nodes << [:out, lerp(a, b, r[1])] if r[1] < 1 - 1e-9
        end
        return [] if nodes.all? { |k, _, ins| k == :v && ins }
        ins_i = nodes.each_index.select { |i| nodes[i][0] == :in }
        outs_i = nodes.each_index.select { |i| nodes[i][0] == :out }
        return pts if ins_i.empty?
        return pts if ins_i.size != outs_i.size
        # Randlage auf cv (Bogenlänge gegen den Uhrzeigersinn)
        per = (0...c.size).map { |j| dist(c[j], c[(j + 1) % c.size]) }
        tot = per.sum
        pos = lambda do |q|
          best = (0...c.size).map do |j|
            a = c[j]; d = sub(c[(j + 1) % c.size], a)
            l2 = dot(d, d)
            t = l2 < 1e-12 ? 0.0 : [[dot(sub(q, a), d) / l2, 0.0].max, 1.0].min
            [dist(q, add(a, mul(d, t))), j, t]
          end.min_by(&:first)
          per[0, best[1]].sum + best[2] * per[best[1]]
        end
        # Partner je Eintritt: der im Uhrzeigersinn nächste Austritt auf cv
        partner = {}
        ins_i.each do |i|
          pe = pos.(nodes[i][1])
          partner[i] = outs_i.min_by { |o| d = (pe - pos.(nodes[o][1])) % tot; d < 1e-9 ? tot : d }
        end
        m = nodes.size
        seen = {}
        loops = []
        nodes.each_index do |st|
          next if seen[st] || nodes[st][0] != :v || nodes[st][2]
          out = []
          i = st
          guard = 0
          loop do
            guard += 1
            return pts if guard > 4 * m + 8
            seen[i] = true
            k, q, ins = nodes[i]
            if k == :v
              out << q unless ins
            elsif k == :in
              x = partner[i]
              out << q
              out.concat(convex_arc_cw(c, q, nodes[x][1]))
              out << nodes[x][1]
              seen[x] = true
              i = x
            end
            i = (i + 1) % m
            break if i == st
          end
          loops << clean_ring(out, 1e-4)
        end
        loops.select! { |l| l.size >= 3 && signed_area(l) > 0 }
        res = loops.max_by { |l| signed_area(l) }
        return pts if res.nil? || signed_area(res) > signed_area(pts) + 1e-6
        res
      end

      # Ecken des konvexen Polygons c (gegen den Uhrzeigersinn) zwischen den
      # Randpunkten e und x, im Uhrzeigersinn von e nach x
      def convex_arc_cw(c, e, x)
        n = c.size
        pos = lambda do |q|
          (0...n).map do |j|
            a = c[j]; d = sub(c[(j + 1) % n], a)
            l2 = dot(d, d)
            t = l2 < 1e-12 ? 0.0 : [[dot(sub(q, a), d) / l2, 0.0].max, 1.0].min
            [dist(q, add(a, mul(d, t))), j, t]
          end.min_by(&:first)[1, 2]
        end
        je, te = pos.(e)
        jx, tx = pos.(x)
        res = []
        j = je; t = te
        (n + 1).times do
          break if j == jx && tx <= t + 1e-9
          res << c[j]
          j = (j - 1) % n
          t = 1.0
        end
        res
      end
    end

    # ------------------------------------------------------------------------
    class Polyline
      attr_reader :pts

      def initialize(pts = [])
        @pts = []
        pts.each { |p| push(p) }
      end

      def push(p)
        return if !@pts.empty? && Geo.dist(@pts[-1], p) < 1e-7
        @pts << [p[0].to_f, p[1].to_f]
        @cum = nil
      end

      def cum
        @cum ||= begin
          c = [0.0]
          (1...@pts.size).each { |i| c << c[-1] + Geo.dist(@pts[i - 1], @pts[i]) }
          c
        end
      end

      def length
        cum[-1]
      end

      def at(s)
        c = cum
        return @pts[0].dup if @pts.size == 1 || s <= 0
        return @pts[-1].dup if s >= c[-1]
        i = c.bsearch_index { |x| x >= s } || c.size - 1
        i = 1 if i < 1
        seg = c[i] - c[i - 1]
        t = seg < 1e-12 ? 0.0 : (s - c[i - 1]) / seg
        Geo.lerp(@pts[i - 1], @pts[i], t)
      end

      def tangent(s)
        return [0.0, 1.0] if @pts.size < 2
        c = cum
        i = c.bsearch_index { |x| x >= s } || c.size - 1
        i = 1 if i < 1
        Geo.norm(Geo.sub(@pts[i], @pts[i - 1]))
      end

      # Stützpunkte mit Parameter strikt zwischen s0 und s1 -> [[pt, param], ...]
      def between(s0, s1, tol = 1e-4)
        res = []
        cum.each_with_index do |c, i|
          res << [@pts[i], c] if c > s0 + tol && c < s1 - tol
        end
        res
      end

      # Strahlschnitt: liefert [punkt, parameter] des nächsten Schnitts in Richtung dir.
      def ray_hit(origin, dir)
        best = nil
        (0...@pts.size - 1).each do |i|
          p = @pts[i]; q = @pts[i + 1]
          e = Geo.sub(q, p)
          den = Geo.cross(dir, e)
          next if den.abs < 1e-12
          w = Geo.sub(p, origin)
          t = Geo.cross(w, e) / den
          u = Geo.cross(w, dir) / den
          next if u < -1e-7 || u > 1 + 1e-7 || t <= 1e-9
          if best.nil? || t < best[0]
            u = [[u, 0.0].max, 1.0].min
            best = [t, Geo.lerp(p, q, u), cum[i] + u * Geo.len(e)]
          end
        end
        best && [best[1], best[2]]
      end
    end

    # ------------------------------------------------------------------------
    class Plan
      attr_accessor :inner, :outer, :walk, :bps, :lines_w, :kinds, :zones,
                    :n, :h, :a, :H, :b, :outer_side, :variant, :spiral,
                    :info, :warnings, :params, :space, :corners, :flights

      def initialize
        @zones = []
        @corners = []
        @info = []
        @warnings = []
        @line_cache = {}
      end

      def wtot
        @lines_w[-1]
      end

      # Anzahl Trittflächen (Stufen + Podeste). Ein Austrittspodest (fehler.md Nr. 5)
      # liegt als zusätzliche Fläche auf Höhe H hinter der letzten Steigung.
      def treads
        @lines_w ? @lines_w.size - 1 : @n - 1
      end

      # Anzahl Stufenlinien (= n, mit Austrittspodest n + 1)
      def nlines
        @lines_w ? @lines_w.size : @n
      end

      # Zuordnung Gehlinie -> Innenkante (stückweise linear)
      def s_of(w)
        b = @bps
        return b[0][1] if w <= b[0][0]
        return b[-1][1] + (w - b[-1][0]) if w >= b[-1][0]
        i = b.bsearch_index { |x| x[0] >= w } || b.size - 1
        i = 1 if i < 1
        w0, s0 = b[i - 1]; w1, s1 = b[i]
        return s1 if (w1 - w0).abs < 1e-12
        s0 + (s1 - s0) * (w - w0) / (w1 - w0)
      end

      # Stufenlinie an Gehlinienposition w: {in:, out:, s:, t:, w:}
      def line(w)
        key = (w * 1e6).round
        @line_cache[key] ||= begin
          z = @zones.find { |zn| zn[:kind] == :landing && w > zn[:w0] + 1e-6 && w < zn[:w1] - 1e-6 }
          if z
            if w - z[:w0] <= z[:w1] - w
              translated(raw_line(z[:w0]), w - z[:w0], w)
            else
              translated(raw_line(z[:w1]), w - z[:w1], w)
            end
          else
            raw_line(w)
          end
        end
      end

      def raw_line(w)
        w = [[w, 0.0].max, wtot].min
        s = s_of(w)
        a = @inner.at(s)
        b = @walk.at(w)
        dir = Geo.sub(b, a)
        if Geo.len(dir) < 1e-9
          t = @walk.tangent(w)
          dir = @outer_side > 0 ? Geo.right(t) : Geo.left(t)
        end
        hit = @outer.ray_hit(a, dir)
        unless hit
          pt = Geo.add(b, Geo.mul(Geo.norm(dir), [@b - Geo.dist(a, b), 1.0].max))
          hit = [pt, @outer.length * w / [wtot, 1e-9].max]
        end
        { in: a, out: hit[0], s: s, t: hit[1], w: w }
      end

      # Parallel verschobene Linie (für Podeste: Überstände/Setzstufen rechtwinklig)
      def translated(base, delta, w)
        l = Geo.norm(Geo.sub(base[:out], base[:in]))
        fwd = @outer_side > 0 ? Geo.left(l) : Geo.right(l)
        mv = Geo.mul(fwd, delta)
        { in: Geo.add(base[:in], mv), out: Geo.add(base[:out], mv),
          s: base[:s] + delta, t: base[:t] + delta, w: w }
      end

      # Grundrissfläche zwischen zwei Gehlinienpositionen.
      # Rückgabe: [[pt, w], ...] (w = interpolierte Gehlinienposition je Punkt)
      def region(wa, wb)
        wb = [wb, wtot].min
        la = line(wa); lb = line(wb)
        items = []
        items << [la[:in], wa] << [la[:out], wa]
        dt = lb[:t] - la[:t]
        @outer.between(la[:t], lb[:t]).each do |pt, prm|
          f = dt.abs < 1e-9 ? 0.5 : (prm - la[:t]) / dt
          items << [pt, wa + f * (wb - wa)]
        end
        items << [lb[:out], wb] << [lb[:in], wb]
        ds = lb[:s] - la[:s]
        @inner.between(la[:s], lb[:s]).reverse.each do |pt, prm|
          f = ds.abs < 1e-9 ? 0.5 : (prm - la[:s]) / ds
          items << [pt, wa + f * (wb - wa)]
        end
        Geo.clean_ring(items, 0.01, true)
      end

      def nose_z(k)
        [(k + 1) * @h, @H].min
      end

      # Parameter der Stufenlinien auf einer Begrenzung
      def keys_for(which)
        @lines_w.map do |w|
          l = line(w)
          case which
          when :inner then l[:s]
          when :outer then l[:t]
          else w
          end
        end
      end

      # Höhenprofil entlang einer Begrenzung.
      # which: :inner, :outer, :walk ; zs: Höhe je Stufenlinie k (0..n-1)
      # Rückgabe: Liste von Stücken, je Stück [[pt, z, param, linienindex|nil], ...]
      def profile(which, zs)
        poly = send(which)
        keys = keys_for(which)
        pieces = []
        cur = [[poly.at(keys[0]), zs[0], keys[0], 0]]
        (0...keys.size - 1).each do |k|
          p0 = keys[k]; p1 = keys[k + 1]
          if p1 - p0 < 0.05
            pieces << cur if cur.size >= 2
            cur = [[poly.at(p1), zs[k + 1], p1, k + 1]]
            next
          end
          poly.between(p0, p1).each do |pt, prm|
            f = (prm - p0) / (p1 - p0)
            cur << [pt, zs[k] + f * (zs[k + 1] - zs[k]), prm, nil]
          end
          cur << [poly.at(p1), zs[k + 1], p1, k + 1]
        end
        pieces << cur if cur.size >= 2
        pieces.map { |pc| dedupe_piece(pc) }.select { |pc| pc.size >= 2 }
      end

      def dedupe_piece(pc)
        out = []
        pc.each { |it| out << it if out.empty? || Geo.dist(out[-1][0], it[0]) > 0.01 }
        out
      end

      def bbox
        pts = @outer.pts + @inner.pts
        xs = pts.map { |p| p[0] }; ys = pts.map { |p| p[1] }
        [xs.min, ys.min, xs.max, ys.max]
      end

      # Daten für die 2D-Vorschau im Dialog
      def preview_data
        tr = (0...treads).map do |k|
          poly = region(@lines_w[k], @lines_w[k + 1]).map { |it| it[0].map { |v| v.round(2) } }
          mid = @walk.at((@lines_w[k] + @lines_w[k + 1]) / 2.0)
          { pts: poly, kind: @kinds[k].to_s, label: mid.map { |v| v.round(2) }, nr: k + 1 }
        end
        lines = @lines_w.map { |w| l = line(w); [l[:in].map { |v| v.round(2) }, l[:out].map { |v| v.round(2) }] }
        {
          treads: tr,
          lines: lines,
          inner: @inner.pts.map { |p| p.map { |v| v.round(2) } },
          outer: @outer.pts.map { |p| p.map { |v| v.round(2) } },
          walk: @walk.pts.map { |p| p.map { |v| v.round(2) } },
          spiral: @spiral ? { r_in: @spiral[:ri], r_out: @spiral[:ro], spindle: @variant == 'spindel' } : nil,
          space: @space
        }
      end
    end

    # ------------------------------------------------------------------------
    # Turtle zum Aufbau der Polylinien bei geraden / gewinkelten Läufen.
    class Turtle
      attr_reader :inner, :walk, :outer, :zones, :dir, :p

      CORNER_SEGS = 16

      # start: Innenpunkt am Antritt, dir: Laufrichtung (Standard: Ursprung, +Y)
      def initialize(b, gl, outer_side, start = nil, dir = nil)
        @b = b; @gl = gl; @sg = outer_side
        @dir = dir ? Geo.norm(dir) : [0.0, 1.0]
        @p = start ? [start[0].to_f, start[1].to_f] : (outer_side > 0 ? [0.0, 0.0] : [b.to_f, 0.0])
        @inner = Polyline.new([@p])
        @walk = Polyline.new([Geo.add(@p, Geo.mul(nO, gl))])
        @outer = Polyline.new([Geo.add(@p, Geo.mul(nO, b))])
        @zones = []
      end

      def nO
        @sg > 0 ? Geo.right(@dir) : Geo.left(@dir)
      end

      def straight(l)
        return if l <= 1e-9
        @p = Geo.add(@p, Geo.mul(@dir, l))
        @inner.push(@p)
        @walk.push(Geo.add(@p, Geo.mul(nO, @gl)))
        @outer.push(Geo.add(@p, Geo.mul(nO, @b)))
      end

      def self.segs_for(delta)
        [(CORNER_SEGS * delta / (Math::PI / 2.0)).ceil, 4].max
      end

      # Länge der (polygonal angenäherten) Gehlinie in einer Ecke mit Richtungsänderung delta
      def self.corner_len(gl, delta = Math::PI / 2.0)
        sg = segs_for(delta)
        sg * 2.0 * gl * Math.sin(delta / 2.0 / sg)
      end

      def corners
        @corners ||= []
      end

      # Ecke zur Innenseite hin; delta = Richtungsänderung (90° = rechtwinklig)
      def corner(delta = Math::PI / 2.0)
        c = @p
        no = nO
        corners << { s: @inner.length, pt_in: c.dup, w0: @walk.length, delta: delta }
        segs = Turtle.segs_for(delta)
        (1..segs).each do |i|
          ang = @sg * delta * i / segs
          @walk.push(Geo.add(c, Geo.mul(Geo.rot(no, ang), @gl)))
        end
        oc = Geo.add(Geo.add(c, Geo.mul(no, @b)), Geo.mul(@dir, @b * Math.tan(delta / 2.0)))
        @outer.push(oc)
        corners[-1][:t] = @outer.length
        corners[-1][:pt_out] = oc
        corners[-1][:w1] = @walk.length
        corners[-1][:w] = (corners[-1][:w0] + corners[-1][:w1]) / 2.0
        @dir = Geo.rot(@dir, @sg * delta)
        @outer.push(Geo.add(c, Geo.mul(nO, @b)))
      end

      def turn(kind)
        w0 = @walk.length; s0 = @inner.length
        yield
        z = { kind: kind, w0: w0, w1: @walk.length, s0: s0, s1: @inner.length }
        @zones << z
        z
      end

      # Abstand (in Laufrichtung) der drei Linien bis zur Schnittlinie [pt, richtung]
      def cut_dists(pt, cdir)
        [@inner.pts[-1], @walk.pts[-1], @outer.pts[-1]].map do |q|
          den = Geo.cross(@dir, cdir)
          raise PlanError, 'Austrittskante verläuft parallel zum Lauf.' if den.abs < 1e-9
          Geo.cross(Geo.sub(pt, q), cdir) / den
        end
      end

      # Lauf bis zur (ggf. schrägen) Schnittlinie verlängern; Ende liegt genau auf der Linie.
      def straight_to_cut(pt, cdir)
        d = cut_dists(pt, cdir)
        raise PlanError, 'Austrittskante liegt hinter dem Lauf.' if d.min < -1e-6
        straight(d.min)
        d = cut_dists(pt, cdir)
        [@inner, @walk, @outer].each_with_index do |pl, i|
          pl.push(Geo.add(pl.pts[-1], Geo.mul(@dir, d[i]))) if d[i] > 1e-7
        end
        @p = @inner.pts[-1]
      end

      # Alle drei Linien einzeln in Laufrichtung bis zur Schnittlinie verlängern
      # (Enden dürfen schon gestaffelt sein, z. B. nach straight_to_cut).
      def extend_to_cut(pt, cdir)
        d = cut_dists(pt, cdir)
        raise PlanError, 'Austrittskante liegt hinter dem Lauf.' if d.min < -1e-6
        [@inner, @walk, @outer].each_with_index do |pl, i|
          pl.push(Geo.add(pl.pts[-1], Geo.mul(@dir, d[i]))) if d[i] > 1e-7
        end
        @p = @inner.pts[-1]
      end
    end

    # ------------------------------------------------------------------------
    module Layout
      module_function

      LIMITS = {
        'efh'   => { b: 80,  h: [14, 20], a: [23, 37] },
        'sonst' => { b: 100, h: [14, 19], a: [26, 37] },
        'neben' => { b: 50,  h: [14, 21], a: [21, 37] }
      }.freeze

      def compute(p)
        return Fit.solve(p) if Fit.active?(p)
        return Fit.solve_box(p) if Fit.box_active?(p)
        plan = Plan.new
        plan.params = p
        v = p['variant']
        plan.variant = v
        hh = p['H'].to_f
        raise PlanError, 'Geschosshöhe muss größer als 50 cm sein.' if hh < 50
        n = p['n_steps'].to_i
        n = (hh / p['h_target'].to_f).round if n <= 0
        n = 2 if n < 2
        h = hh / n
        plan.n = n; plan.h = h; plan.H = hh
        a = p['a_user'].to_f > 0 ? p['a_user'].to_f : p['schritt'].to_f - 2.0 * h
        raise PlanError, "Auftritt #{a.round(1)} cm ist zu klein." if a < 10

        if Params::SPIRAL.include?(v)
          a = build_spiral(plan, p, n, a)
        elsif Params::WENDEL.include?(v)
          plan = build_winder(p, n, h, hh, a)
        else
          build_flights(plan, p, n, a)
        end
        plan.a = a
        check(plan, p)
        plan
      end

      # Gewendelte Läufe: In jeder Ecke liegt eine Drachenstufe (Ecke innerhalb einer
      # Stufe). Standard: Ecke mittig in der Stufe (spiegelgleich zur Eckdiagonale);
      # die Teilung darf abweichen (kite_pos bzw. automatisch, wo mittig nicht passt).
      def build_winder(p, n, h, hh, a)
        plan = nil
        err = nil
        begin
          plan = build_winder1(p, n, h, hh, a, false)
        rescue PlanError => e
          err = e
        end
        # U-Treppe: Gehlinie bleibt, Ecken außermittig – passt das nicht (Drachenstufe
        # nicht sauber, kein Platz), wie bisher mit angepasster Gehlinie und mittigen Ecken
        if p['variant'] == 'u_wendel' && p['kite_pos'].to_f <= 0 && KITE_KEEP_GL && (plan.nil? || kite_bad?(plan))
          alt = begin
            build_winder1(p, n, h, hh, a, true)
          rescue PlanError
            nil
          end
          plan = alt if alt && (plan.nil? || !kite_bad?(alt))
        end
        raise err if plan.nil?
        plan
      end

      def build_winder1(p, n, h, hh, a, kite_mid)
        plan = Plan.new
        plan.params = p; plan.variant = p['variant']; plan.n = n; plan.h = h; plan.H = hh
        build_flights(plan, p, n, a, kite_mid)
        report_kites(plan)
        plan
      end

      # Drachenstufe nicht sauber oder Innenauftritt <= 0
      def kite_bad?(plan)
        !kite_errors(plan).empty? || plan.warnings.any? { |w| w.start_with?('Innenauftritt ≤ 0') }
      end

      # Drachenstufen prüfen und als Info ausgeben
      def report_kites(plan, hint = '(Lage der Wendelung oder Anzahl verzogener Stufen ändern)')
        errs = kite_errors(plan)
        plan.warnings << "Drachenstufe nicht sauber: #{errs.first} #{hint}." unless errs.empty?
        fr = kite_fracs(plan)
        return if fr.empty?
        mid = fr.all? { |_k, f| (f - 0.5).abs < 0.005 }
        txt = fr.map { |k, f| mid ? "Nr. #{k}" : format('Nr. %d (Ecke bei %.0f %%)', k, f * 100.0) }.join(', ')
        plan.info << [mid ? 'Drachenstufe(n) (mittig auf der Ecke)' : 'Drachenstufe(n) (Lage der Ecke im Auftritt)', txt]
      end

      # Nummern der Drachenstufen (Stufe, in der die Ecke liegt)
      def kite_steps(plan)
        plan.corners.map do |c|
          k = (0...plan.treads).find { |j| plan.line(plan.lines_w[j])[:t] < c[:t] && plan.line(plan.lines_w[j + 1])[:t] > c[:t] }
          k ? k + 1 : nil
        end.compact.uniq
      end

      # Drachenstufen mit Lage der Ecke im Auftritt (Gehlinie, 0..1):
      # [[Nr., Anteil vor der Ecke], ...]
      def kite_fracs(plan)
        return [] if plan.corners.nil? || plan.spiral
        lw = plan.lines_w
        plan.corners.map do |c|
          next unless c[:w] && plan.zones.any? { |z| z[:kind] == :winder && c[:w] > z[:w0] - 1e-6 && c[:w] < z[:w1] + 1e-6 }
          k = (0...plan.treads).find { |j| lw[j] < c[:w] - 1e-9 && lw[j + 1] > c[:w] + 1e-9 }
          k && [k + 1, (c[:w] - lw[k]) / (lw[k + 1] - lw[k])]
        end.compact
      end

      # Prüfung der Drachenstufen: Ecke innerhalb einer Stufe, an Innen- und
      # Außenecke beide Schenkel mindestens KITE_HOOK_MIN. Rückgabe: Fehlertexte.
      def kite_errors(plan)
        errs = []
        return errs if plan.corners.nil? || plan.corners.empty? || plan.spiral
        lw = plan.lines_w
        hook = KITE_HOOK_MIN - 0.01
        plan.corners.each_with_index do |c, ci|
          next unless c[:w]
          next unless plan.zones.any? { |z| z[:kind] == :winder && c[:w] > z[:w0] - 1e-6 && c[:w] < z[:w1] + 1e-6 }
          k = (0...plan.treads).find { |j| plan.line(lw[j])[:t] < c[:t] - 1e-6 && plan.line(lw[j + 1])[:t] > c[:t] + 1e-6 }
          unless k
            errs << "Stufenkante läuft durch die Ecke #{ci + 1}"
            next
          end
          l0 = plan.line(lw[k]); l1 = plan.line(lw[k + 1])
          q0 = c[:s] - l0[:s]; q1 = l1[:s] - c[:s]
          o0 = c[:t] - l0[:t]; o1 = l1[:t] - c[:t]
          if q0 < -0.05 || q1 < -0.05
            errs << "Innenecke liegt nicht in der Drachenstufe Nr. #{k + 1}"
          elsif [q0, q1].min < hook
            errs << format('Drachenstufe Nr. %d: kleiner Schenkel an der Innenecke nur %.1f cm (mind. %.0f cm)', k + 1, [q0, q1].min, KITE_HOOK_MIN)
          end
          errs << format('Drachenstufe Nr. %d: kleiner Schenkel an der Außenecke nur %.1f cm', k + 1, [o0, o1].min) if [o0, o1].min < hook
        end
        errs
      end

      # Zwei Ecken im Abstand d (Gehlinie): Lage f der ersten Ecke in ihrer Stufe (0..1),
      # bei der beide Ecken möglichst weit von den Stufenkanten entfernt liegen.
      def kite_pair_frac(d, a)
        dl = (d / a) % 1.0
        (1.0 - dl) / 2.0 >= dl / 2.0 ? (1.0 - dl) / 2.0 : 1.0 - dl / 2.0
      end

      # Abstand der Ecke von der näheren Stufenkante (Anteil des Auftritts)
      def kite_centrality(w, a)
        f = (w / a) % 1.0
        [f, 1.0 - f].min
      end

      # Zulässiger Bereich für die Gehlinie (Abstand von der Innenkante):
      # [hart_min, hart_max, Gehbereich_min, Gehbereich_max] (Gehbereich nach DIN 18065:
      # mittlere 2/10 der Laufbreite, höchstens 20 cm breit)
      def gl_range(b, target)
        hw = [0.1 * b, 10.0].min
        dlo = b / 2.0 - hw; dhi = b / 2.0 + hw
        [[0.25 * b, target - hw].min, [0.75 * b, target + hw].max, [dlo, target].min, [dhi, target].max]
      end

      # Gehlinie so wählen, dass der Abstand zweier Eckmitten auf der Gehlinie
      # (gl·lfak + gmid) ein ganzzahliges Vielfaches k des Auftritts ist.
      # Rückgabe: [gl, k] (nächstliegend zum Zielwert) oder nil
      def gl_for_corners(a, lfak, gmid, b, target)
        lo, hi = gl_range(b, target)
        best = nil
        k0 = ((target * lfak + gmid) / a).round
        ((k0 - 3)..(k0 + 3)).each do |k|
          next if k < 1
          g = (k * a - gmid) / lfak
          next if g < lo - 1e-9 || g > hi + 1e-9 || g <= 1.0 || g >= b - 1.0
          best = [g, k] if best.nil? || (g - target).abs < (best[0] - target).abs
        end
        best
      end

      # --- Wendeltreppen --------------------------------------------------
      def build_spiral(plan, p, n, a)
        v = p['variant']
        ro = p['D_out'].to_f / 2.0
        d_in = p['d_in'].to_f
        d_in = (v == 'spindel' ? 12.0 : 50.0) if d_in <= 0
        ri = d_in / 2.0
        raise PlanError, 'Spindel/Auge ist zu groß für den Außendurchmesser.' if ro - ri < 40
        rg = p['rg'].to_f
        rg = ri + (ro - ri) / 2.0 if rg <= 0
        raise PlanError, 'Gehlinienradius muss zwischen Innen- und Außenradius liegen.' if rg <= ri + 1 || rg >= ro - 1
        if p['angle'].to_f > 0
          theta = p['angle'].to_f * Math::PI / 180.0
          a = theta * rg / (n - 1)
        end
        theta = (n - 1) * a / rg
        sg = p['direction'] == 'links' ? 1 : -1
        segs = [(theta / (2.0 * Math::PI / 180.0)).ceil, 8].max
        mk = lambda do |r|
          pts = (0..segs).map do |i|
            ph = theta * i / segs
            ang = sg > 0 ? ph : Math::PI - ph
            [r * Math.cos(ang), r * Math.sin(ang)]
          end
          Polyline.new(pts)
        end
        plan.outer_side = sg
        plan.inner = mk.(ri)
        plan.walk = mk.(rg)
        plan.outer = mk.(ro)
        plan.b = ro - ri
        plan.spiral = { ri: ri, ro: ro, rg: rg, theta: theta }
        wt = plan.walk.length
        plan.lines_w = (0...n).map { |k| wt * k / (n - 1) }
        plan.kinds = Array.new(n - 1, :step)
        plan.bps = [[0.0, 0.0], [wt, plan.inner.length]]
        a_real = wt / (n - 1)
        deg = theta * 180.0 / Math::PI
        step_deg = deg / (n - 1)
        per_turn = 360.0 / step_deg
        head = per_turn * plan.h - p['tread_t'].to_f
        plan.info << ['Gesamtdrehwinkel', format('%.1f°', deg)]
        plan.info << ['Stufenwinkel', format('%.2f°', step_deg)]
        plan.info << ['Radien innen / Gehlinie / außen', format('%.1f / %.1f / %.1f cm', ri, rg, ro)]
        plan.info << ['Nutzbare Laufbreite', format('%.1f cm', ro - ri)]
        plan.info << ['Auftritt Innen- / Außenkante', format('%.1f / %.1f cm', a_real * ri / rg, a_real * ro / rg)]
        plan.info << ['Lichte Durchgangshöhe (ca.)', format('%.1f cm', head)]
        plan.warnings << "Durchgangshöhe ca. #{head.round} cm < 200 cm – Drehwinkel/Auftritt vergrößern." if head < 200
        a_real
      end

      # --- Gerade und gewinkelte Läufe -------------------------------------
      # kite_mid: U-Treppe – Gehlinie anpassen, damit beide Ecken mittig liegen (wie bis 2.7.1)
      def build_flights(plan, p, n, a, kite_mid = false)
        v = p['variant']
        b = p['b'].to_f
        gl = p['gl'].to_f
        gl = b / 2.0 if gl <= 0 || !Params::TURNING.include?(v)
        raise PlanError, 'Gehlinienabstand muss kleiner als die Laufbreite sein.' if gl >= b
        e = p['eye'].to_f
        # Lage der Ecke in der Drachenstufe (Anteil des Auftritts vor der Ecke), 0 = mittig
        kp1 = p['kite_pos'].to_f / 100.0
        kp2 = p['kite_pos2'].to_f / 100.0
        [kp1, kp2].each do |kp|
          raise PlanError, 'Lage der Ecke in der Drachenstufe muss zwischen 0 und 100 % liegen.' if kp.negative? || kp >= 1.0
        end
        off = kp1 > 0 ? kp1 * a : 0.5 * a # Lage der (ersten) Ecke in ihrer Stufe
        if v == 'u_wendel'
          # off = Lage der Wendelmitte in ihrer Stufe; Ecken im Abstand lc + Auge
          if kp1 > 0
            off = (kp1 * a + (Turtle.corner_len(gl) + e) / 2.0) % a
          else
            # beide Ecken mittig in einer Stufe: Abstand der Eckmitten (lc + Auge) = k·a
            gl0 = gl
            sol = gl_for_corners(a, Turtle.corner_len(1.0), e, b, gl0)
            sol = nil if sol && KITE_KEEP_GL && !kite_mid && (sol[0] - gl0).abs >= 0.05
            if sol
              gl, kk = sol
              off = kk.even? ? 0.5 * a : 0.0
              if (gl - gl0).abs > 0.05
                plan.info << ['Gehlinie angepasst (Drachenstufen mittig auf den Ecken)', format('%.1f cm statt %.1f cm', gl, gl0)]
                _l, _h, dlo, dhi = gl_range(b, gl0)
                plan.warnings << format('Gehlinie (%.1f cm) liegt außerhalb des Gehbereichs.', gl) if gl < dlo - 1e-6 || gl > dhi + 1e-6
              end
            else
              # mittig nicht ohne Verschieben der Gehlinie: Gehlinie bleibt, Ecken so mittig wie möglich
              d = Turtle.corner_len(gl) + e
              off = (kite_pair_frac(d, a) * a + d / 2.0) % a
            end
          end
        end
        sg = p['direction'] == 'links' ? 1 : -1
        plan.outer_side = sg
        plan.b = b
        t = Turtle.new(b, gl, sg)
        lc = Turtle.corner_len(gl)
        ntr = n - 1
        depths = nil
        kinds = Array.new(ntr, :step)
        flights = nil
        winder_centers = []

        case v
        when 'gerade'
          t.straight(ntr * a)
          depths = [a] * ntr
          flights = [n]
        when 'gerade_podest'
          r1 = pick(p['r1'], (n / 2.0).round, 1, n - 1, 'Steigungen im 1. Lauf')
          pl = p['landing_len'].to_f
          pl = b if pl <= 0
          depths = [a] * (r1 - 1) + [pl] + [a] * (n - r1 - 1)
          kinds[r1 - 1] = :landing
          t.straight(depths.inject(0.0, :+))
          flights = [r1, n - r1]
          plan.warnings << "Podestlänge #{pl.round} cm ist kleiner als die Laufbreite." if pl < b - 0.01
        when 'l_podest', 'u_podest'
          r1 = pick(p['r1'], (n / 2.0).round, 1, n - 1, 'Steigungen im 1. Lauf')
          t.straight((r1 - 1) * a)
          z = t.turn(:landing) do
            t.straight(p['pod1_vor'].to_f)
            t.corner
            if v == 'u_podest'
              t.straight(e)
              t.corner
            end
            t.straight(p['pod1_nach'].to_f)
          end
          t.straight((n - r1 - 1) * a)
          depths = [a] * (r1 - 1) + [z[:w1] - z[:w0]] + [a] * (n - r1 - 1)
          kinds[r1 - 1] = :landing
          flights = [r1, n - r1]
        when 'z_podest'
          r1 = pick(p['r1'], (n / 3.0).round, 1, n - 2, 'Steigungen im 1. Lauf')
          r2 = pick(p['r2'], ((n - r1) / 2.0).round, 1, n - r1 - 1, 'Steigungen im 2. Lauf')
          r3 = n - r1 - r2
          t.straight((r1 - 1) * a)
          z1 = t.turn(:landing) { t.straight(p['pod1_vor'].to_f); t.corner; t.straight(p['pod1_nach'].to_f) }
          t.straight((r2 - 1) * a)
          z2 = t.turn(:landing) { t.straight(p['pod2_vor'].to_f); t.corner; t.straight(p['pod2_nach'].to_f) }
          t.straight((r3 - 1) * a)
          depths = [a] * (r1 - 1) + [z1[:w1] - z1[:w0]] + [a] * (r2 - 1) + [z2[:w1] - z2[:w0]] + [a] * (r3 - 1)
          kinds[r1 - 1] = :landing
          kinds[r1 + r2 - 1] = :landing
          flights = [r1, r2, r3]
        when 'l_wendel', 'u_wendel'
          lw = v == 'l_wendel' ? lc : 2 * lc + e
          # Wendelmitte liegt bei m·a + off (L: off = Lage der Ecke in der Drachenstufe, Standard ½a)
          m_min = [((lw / 2.0 - off) / a).ceil, 0].max
          m_max = ((ntr * a - off - lw / 2.0) / a).floor
          m = pick(p['m1'], ((ntr - 1) / 2.0).round, m_min, m_max, 'Stufen vor der Drachenstufe')
          t.straight(m * a + off - lw / 2.0)
          t.turn(:winder) do
            t.corner
            if v == 'u_wendel'
              t.straight(e)
              t.corner
            end
          end
          t.straight(ntr * a - m * a - off - lw / 2.0)
          depths = [a] * ntr
          flights = [n]
        when 'z_wendel'
          off2 = kp2 > 0 ? kp2 * a : 0.5 * a
          m_min = [((lc / 2.0 - off) / a).ceil, 0].max
          gap_min = [((lc - off2 + off) / a).ceil, 0].max
          m1 = pick(p['m1'], (ntr / 3.0 - 0.5).round, m_min, ((ntr * a - off2 - lc / 2.0) / a).floor - gap_min, 'Stufen vor der 1. Drachenstufe')
          c1 = m1 * a + off
          m2 = pick(p['m2'], ((ntr * a - c1) / a / 2.0).round, gap_min, ((ntr * a - off2 - lc / 2.0) / a).floor - m1, 'Stufen zwischen den Drachenstufen')
          c2 = (m1 + m2) * a + off2
          t.straight(c1 - lc / 2.0)
          t.turn(:winder) { t.corner }
          t.straight(c2 - c1 - lc)
          t.turn(:winder) { t.corner }
          t.straight(ntr * a - c2 - lc / 2.0)
          depths = [a] * ntr
          flights = [n]
        else
          raise PlanError, "Unbekannte Treppenform: #{v}"
        end

        # Austrittspodest auf Höhe H hinter der letzten Steigung (fehler.md Nr. 6:
        # Gegenstück zu loch_gap beim Einpassen)
        xl = p['exit_land'].to_f
        if xl > 1e-6
          z = t.turn(:landing) { t.straight(xl) }
          depths += [z[:w1] - z[:w0]]
          kinds += [:landing]
        end

        finish_flights(plan, p, t, n, a, depths, kinds, flights, gl)
      end

      # Gemeinsamer Abschluss für Läufe: Stufenlinien, Zuordnung s(w), Infos.
      def finish_flights(plan, p, t, n, a, depths, kinds, flights, gl)
        v = p['variant']
        ntr = n - 1
        plan.inner = t.inner
        plan.walk = t.walk
        plan.outer = t.outer
        plan.zones = t.zones
        plan.corners = t.respond_to?(:corners) ? t.corners : []
        plan.kinds = kinds
        plan.flights = flights
        lw = [0.0]
        depths.each { |d| lw << lw[-1] + d }
        # numerische Feinkorrektur auf tatsächliche Gehlinienlänge
        wt = plan.walk.length
        if (lw[-1] - wt).abs > 1e-6 && lw[-1] > 0
          f = wt / lw[-1]
          lw.map! { |x| x * f }
        end
        plan.lines_w = lw

        # Zuordnung s(w)
        bps = [[0.0, 0.0]]
        nv = p['nv'].to_i
        plan.zones.each_with_index do |z, zi|
          if z[:kind] == :landing
            bps << [z[:w0], z[:s0]] << [z[:w1], z[:s1]]
          else
            lwz = z[:w1] - z[:w0]
            lin = z[:s1] - z[:s0]
            wc = (z[:w0] + z[:w1]) / 2.0
            cs = plan.corners.select { |c| c[:w] && c[:w] > z[:w0] - 1e-6 && c[:w] < z[:w1] + 1e-6 }.sort_by { |c| c[:w] }
            # Drachenstufen (Stufenkanten um die Ecken) müssen ganz in der Wendelung liegen
            ed = cs.map { |c| kite_edges(c, lw, a) }
            reach = ed.empty? ? 0.0 : [wc - ed[0][0], ed[-1][1] - wc].max
            d_min = [lwz / 2.0 + 0.2 * a, reach + 0.2 * a].max
            zp = zi > 0 ? plan.zones[zi - 1] : nil
            zn = zi < plan.zones.size - 1 ? plan.zones[zi + 1] : nil
            # Nachbar-Podest (z. B. Austrittspodest): Wendelung darf bis an das Podest reichen
            lo = if zp.nil? then 0.0
                 elsif zp[:kind] == :landing then zp[:w1]
                 else (wc + (zp[:w0] + zp[:w1]) / 2.0) / 2.0
                 end
            hi = if zn.nil? then wt
                 elsif zn[:kind] == :landing then zn[:w0]
                 else (wc + (zn[:w0] + zn[:w1]) / 2.0) / 2.0
                 end
            d_max = [wc - lo, hi - wc].min
            auto = (v == 'u_wendel' ? 10 : 6)
            d_target = (nv > 0 ? nv : auto) * a / 2.0
            d = [[d_target, d_max].min, d_min].max
            if d > d_max + 1e-9
              raise PlanError, 'Wendelung passt nicht: zu wenige Stufen vor bzw. nach der Wendelung ' \
                               '(Lage der Wendelung oder Anzahl Steigungen ändern).'
            end
            plan.warnings << 'Anzahl verzogener Stufen wurde auf den verfügbaren Platz begrenzt.' if nv > 0 && d_target > d_max + 1e-6
            plan.warnings << 'Anzahl verzogener Stufen wurde erhöht (Platz für die Drachenstufe).' if nv > 0 && d_target < d_min - 1e-6
            wa = wc - d; wb = wc + d
            sa = z[:s0] - (z[:w0] - wa)
            sb = z[:s1] + (wb - z[:w1])
            bps << [wa, sa]
            kite_breakpoints(cs, a, wa, sa, wb, sb, p['min_inner'].to_f, lw).each { |x| bps << x }
            bps << [wb, sb]
            z[:d] = d
          end
        end
        bps << [wt, plan.inner.length]
        bps.sort_by! { |x| x[0] }
        clean = []
        bps.each { |x| clean << x if clean.empty? || x[0] - clean[-1][0] > 1e-7 }
        plan.bps = clean

        # Infos
        x0, y0, x1, y1 = plan.bbox
        plan.info << ['Grundriss (Laufbreite ohne Wangen)', format('%.1f × %.1f cm', x1 - x0, y1 - y0)]
        plan.info << ['Steigungen je Lauf', flights.join(' / ')]
        plan.info << ['Gehlinie: Abstand Innenkante', format('%.1f cm', gl)] if Params::TURNING.include?(v)
        plan.instance_variable_set(:@gl, gl)
        if Params::WENDEL.include?(v)
          mins = (0...ntr).map { |k| plan.line(plan.lines_w[k + 1])[:s] - plan.line(plan.lines_w[k])[:s] }
          maxo = (0...ntr).map { |k| plan.line(plan.lines_w[k + 1])[:t] - plan.line(plan.lines_w[k])[:t] }
          mi = mins.min
          plan.info << ['Auftritt Innenkante (min.)', format('%.1f cm', mi)]
          plan.info << ['Auftritt Außenkante (max.)', format('%.1f cm', maxo.max)]
          plan.warnings << "Schmalster Innenauftritt #{mi.round(1)} cm < #{p['min_inner']} cm – mehr Stufen verziehen oder Gehlinie verschieben." if mi < p['min_inner'].to_f
          plan.warnings << 'Innenauftritt ≤ 0 – Geometrie ungültig.' if mi <= 0
        end
        flights.each_with_index do |r, i|
          plan.warnings << "Lauf #{i + 1}: #{r} Steigungen – nach max. 18 Stufen ist ein Zwischenpodest vorzusehen." if r > 18
        end
        plan
      end

      KITE_HOOK_MIN = 2.0  # cm – kleinster zulässiger Schenkel einer Drachenstufe an Innen- und Außenecke
      KITE_HOOK_PREF = 5.0 # cm – bevorzugter Schenkel innen (wie bis 2.7.1, solange das passt)
      KITE_F_AUTO = 0.25   # automatisch außermittig: Ecke mind. 25 % des Auftritts vom Stufenrand
      KITE_KEEP_GL = true  # Gehlinie halten und Ecke außermittig, statt die Gehlinie für eine mittige Ecke zu verschieben

      # Stufenkanten (Gehlinie) vor und nach einer Ecke: [w0, w1]
      def kite_edges(c, lw, a)
        k = (0...lw.size - 1).find { |j| lw[j] < c[:w] - 1e-6 && lw[j + 1] > c[:w] + 1e-6 }
        k ? [lw[k], lw[k + 1]] : [c[:w] - a / 2.0, c[:w] + a / 2.0]
      end

      # Stützpunkte der Zuordnung s(w) für die Drachenstufen einer Wendelzone.
      # Jede Ecke liegt in einer Stufe (Kanten e0 < w_ecke < e1, Anteil f = (w_ecke − e0)/a).
      # Die Kanten der Drachenstufe treffen die Innenkante bei s_ecke − Q·f und
      # s_ecke + Q·(1 − f): bei mittiger Ecke (f = ½) spiegelgleich zur Eckdiagonale,
      # sonst im selben Verhältnis geteilt wie auf der Gehlinie. Q (Breite der
      # Drachenstufe an der Innenkante) wird so gewählt, dass der kleinere Schenkel
      # mindestens KITE_HOOK_MIN lang ist – bevorzugt wie bisher KITE_HOOK_PREF bzw.
      # min_inner/2; nur wenn gar nichts passt, Q = 0 (Spitze in der Innenecke, Warnung).
      def kite_breakpoints(cs, a, wa, sa, wb, sb, min_inner, lw)
        return [] if cs.empty?
        ks = cs.map do |c|
          e0, e1 = kite_edges(c, lw, a)
          { s: c[:s], w: c[:w], e0: e0, e1: e1, f: (c[:w] - e0) / (e1 - e0) }
        end
        qn = (sb - sa) / (wb - wa) * a
        (0...ks.size - 1).each do |i|
          kk = (ks[i + 1][:w] - ks[i][:w]) / a # Abstand der Ecken in Auftritten (mittig: ganzzahlig)
          kk = kk.round if kk.round >= 1 && (kk - kk.round).abs < 1e-3
          qn = [qn, (ks[i + 1][:s] - ks[i][:s]) / kk].min if kk > 1e-9
        end
        ok = lambda do |qq|
          return false if qq < -1e-9
          l1 = ks[0][:e0] - wa
          r1 = wb - ks[-1][:e1]
          return false if l1 < -1e-6 || r1 < -1e-6
          sl = qq / a
          return false if ks[0][:s] - qq * ks[0][:f] - sa < (l1 > 1e-6 ? 0.25 * sl * l1 - 1e-6 : -1e-6)
          return false if sb - (ks[-1][:s] + qq * (1.0 - ks[-1][:f])) < (r1 > 1e-6 ? 0.25 * sl * r1 - 1e-6 : -1e-6)
          (0...ks.size - 1).each do |i|
            lm = ks[i + 1][:e0] - ks[i][:e1]
            gm = (ks[i + 1][:s] - qq * ks[i + 1][:f]) - (ks[i][:s] + qq * (1.0 - ks[i][:f]))
            return false if gm < -1e-6 || (lm < 1e-6 && gm.abs > 1e-3)
          end
          true
        end
        cen = ks.map { |k| [k[:f], 1.0 - k[:f]].min }.min
        need = KITE_HOOK_MIN / [cen, 1e-6].max
        bp = ->(qq) { ks.flat_map { |k| [[k[:e0], k[:s] - qq * k[:f]], [k[:e1], k[:s] + qq * (1.0 - k[:f])]] } }
        if cen < 0.5 - 1e-3
          # außermittig: Q so, dass der schmalste Innenauftritt der Wendelung möglichst breit wird
          hi = [qn, need].max
          cands = (0..40).map { |i| need + (hi - need) * i / 40.0 }.select { |qq| ok.(qq) }
          unless cands.empty?
            steps = lw.each_cons(2).select { |w0, w1| w0 >= wa - 1e-6 && w1 <= wb + 1e-6 }
            return bp.(cands.max_by { |qq| [kite_min_inner([[wa, sa]] + bp.(qq) + [[wb, sb]], steps).round(2), -(qq - qn).abs] })
          end
          return bp.(0.0)
        end
        pref = [2.0 * [KITE_HOOK_PREF, min_inner / 2.0].max, need].max
        q = if qn >= pref - 1e-9 && ok.(qn) then qn
            elsif qn >= pref / 2.0 && ok.(pref) then pref
            elsif qn >= need - 1e-9 && ok.(qn) then qn
            elsif qn >= need / 2.0 && ok.(need) then need
            else 0.0
            end
        bp.(q)
      end

      # Schmalster Innenauftritt der Stufen [w0, w1] bei Stützpunkten pts der Zuordnung s(w)
      def kite_min_inner(pts, steps)
        pts = pts.sort_by(&:first)
        sw = lambda do |w|
          i = pts.index { |x| x[0] >= w - 1e-9 } || pts.size - 1
          return pts[0][1] if i.zero?
          (w0, s0), (w1, s1) = pts[i - 1], pts[i]
          (w1 - w0).abs < 1e-12 ? s1 : s0 + (s1 - s0) * (w - w0) / (w1 - w0)
        end
        steps.map { |w0, w1| sw.(w1) - sw.(w0) }.min || 0.0
      end

      def pick(val, auto, lo, hi, label)
        x = val.to_i
        x = auto if x <= 0
        if hi < lo
          raise PlanError, "Zu wenige Steigungen für diese Treppenform (#{label})."
        end
        if x < lo || x > hi
          raise PlanError, "#{label} muss zwischen #{lo} und #{hi} liegen (ist #{x})."
        end
        x
      end

      def check(plan, p)
        lim = LIMITS[p['building']] || LIMITS['efh']
        h = plan.h; a = plan.a
        sm = 2 * h + a
        ang = Math.atan2(h, a) * 180.0 / Math::PI
        plan.info.unshift(['Lauflänge auf der Gehlinie', format('%.1f cm', plan.lines_w[plan.n - 1] || plan.wtot)])
        plan.info.unshift(['Steigungswinkel', format('%.1f°', ang)])
        plan.info.unshift(['Schrittmaß 2h + a', format('%.1f cm', sm)])
        plan.info.unshift(['Auftritt a (Gehlinie)', format('%.2f cm', a)])
        plan.info.unshift(['Steigungshöhe h', format('%.2f cm', h)])
        plan.info.unshift(['Steigungen / Auftritte', "#{plan.n} / #{plan.n - 1}"])
        w = plan.warnings
        w << "Steigung #{h.round(1)} cm außerhalb #{lim[:h][0]}–#{lim[:h][1]} cm." if h < lim[:h][0] || h > lim[:h][1]
        w << "Auftritt #{a.round(1)} cm außerhalb #{lim[:a][0]}–#{lim[:a][1]} cm." if a < lim[:a][0] || a > lim[:a][1]
        w << "Schrittmaß #{sm.round(1)} cm außerhalb 59–65 cm." if sm < 59 || sm > 65
        w << "Laufbreite #{plan.b.round} cm < #{lim[:b]} cm." if plan.b < lim[:b]
        if Params::EYE_TYPES.include?(plan.variant) && Params.side_kind(p, :inner, plan.outer_side) == 'wange'
            eye = Params::U_TYPES.include?(plan.variant) ? p['eye'].to_f : (Fit.active?(p) ? p['eye_z'].to_f : nil)
          if eye && eye > 0 && eye < 2 * p['str_t'].to_f + 1
            w << 'Treppenauge ist schmaler als zwei Wangendicken – die inneren Wangen stoßen zusammen.'
          end
        end
        if p['construction'] == 'wange' && plan.spiral
          plan.info << ['Wangen', 'keine (gebogene Wangen werden nicht erzeugt) – Stufen freitragend']
        end
        if p['construction'] == 'massiv' && plan.spiral && plan.spiral[:ri] < 5
          w << 'Massive Wendeltreppe ohne Auge/Spindel: Laufplatte in der Mitte sehr schmal.'
        end
      end
    end
  end
end
