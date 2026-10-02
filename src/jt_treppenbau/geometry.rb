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

      # Gewendelte Läufe: Die Wendelung wird so gelegt, dass jede Ecke genau mittig
      # in einer Stufe liegt (Drachenstufe, spiegelgleich zur Eckdiagonale).
      def build_winder(p, n, h, hh, a)
        plan = Plan.new
        plan.params = p; plan.variant = p['variant']; plan.n = n; plan.h = h; plan.H = hh
        build_flights(plan, p, n, a)
        report_kites(plan)
        plan
      end

      # Drachenstufen prüfen und als Info ausgeben
      def report_kites(plan, hint = '(Lage der Wendelung oder Anzahl verzogener Stufen ändern)')
        errs = kite_errors(plan)
        plan.warnings << "Drachenstufe nicht sauber: #{errs.first} #{hint}." unless errs.empty?
        kites = kite_steps(plan)
        plan.info << ['Drachenstufe(n) (mittig auf der Ecke)', kites.map { |k| "Nr. #{k}" }.join(', ')] unless kites.empty?
      end

      # Nummern der Drachenstufen (Stufe, in der die Ecke liegt)
      def kite_steps(plan)
        plan.corners.map do |c|
          k = (0...plan.treads).find { |j| plan.line(plan.lines_w[j])[:t] < c[:t] && plan.line(plan.lines_w[j + 1])[:t] > c[:t] }
          k ? k + 1 : nil
        end.compact.uniq
      end

      # Prüfung der Drachenstufen: Ecke mittig in einer Stufe, Stufe symmetrisch,
      # keine kleinen Haken an Innen- oder Außenecke. Rückgabe: Fehlertexte.
      def kite_errors(plan)
        errs = []
        return errs if plan.corners.nil? || plan.corners.empty? || plan.spiral
        lw = plan.lines_w
        qmin = [KITE_HOOK_MIN, plan.params ? plan.params['min_inner'].to_f / 2.0 : 0.0].max - 0.01
        plan.corners.each_with_index do |c, ci|
          next unless c[:w]
          next unless plan.zones.any? { |z| z[:kind] == :winder && c[:w] > z[:w0] - 1e-6 && c[:w] < z[:w1] + 1e-6 }
          k = (0...plan.treads).find { |j| plan.line(lw[j])[:t] < c[:t] - 1e-6 && plan.line(lw[j + 1])[:t] > c[:t] + 1e-6 }
          unless k
            errs << "Stufenkante läuft durch die Ecke #{ci + 1}"
            next
          end
          if ((lw[k] + lw[k + 1]) / 2.0 - c[:w]).abs > 0.02
            errs << "Ecke #{ci + 1} liegt nicht mittig in der Drachenstufe"
            next
          end
          l0 = plan.line(lw[k]); l1 = plan.line(lw[k + 1])
          q0 = c[:s] - l0[:s]; q1 = l1[:s] - c[:s]
          o0 = c[:t] - l0[:t]; o1 = l1[:t] - c[:t]
          errs << "Drachenstufe Nr. #{k + 1} ist nicht symmetrisch" if (q0 - q1).abs > 0.05 || q0 < -0.05 || q1 < -0.05
          errs << "Drachenstufe Nr. #{k + 1} hat nur einen kleinen Haken an der Innenecke" if [q0, q1].any? { |q| q > 0.05 && q < qmin }
          errs << "Drachenstufe Nr. #{k + 1} hat nur einen kleinen Haken an der Außenecke" if [o0, o1].any? { |o| o < qmin }
        end
        errs
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
      def build_flights(plan, p, n, a)
        v = p['variant']
        b = p['b'].to_f
        gl = p['gl'].to_f
        gl = b / 2.0 if gl <= 0 || !Params::TURNING.include?(v)
        raise PlanError, 'Gehlinienabstand muss kleiner als die Laufbreite sein.' if gl >= b
        e = p['eye'].to_f
        off = 0.5 * a # Ecke (Mitte der Drachenstufe) liegt in Stufenmitte
        if v == 'u_wendel'
          # beide Ecken mittig in einer Stufe: Abstand der Eckmitten (lc + Auge) = k·a
          gl0 = gl
          sol = gl_for_corners(a, Turtle.corner_len(1.0), e, b, gl0)
          raise PlanError, 'Drachenstufen lassen sich nicht mittig auf die Ecken legen (Treppenauge, Laufbreite oder Auftritt ändern).' unless sol
          gl, kk = sol
          off = kk.even? ? 0.5 * a : 0.0
          if (gl - gl0).abs > 0.05
            plan.info << ['Gehlinie angepasst (Drachenstufen mittig auf den Ecken)', format('%.1f cm statt %.1f cm', gl, gl0)]
            _l, _h, dlo, dhi = gl_range(b, gl0)
            plan.warnings << format('Gehlinie (%.1f cm) liegt außerhalb des Gehbereichs.', gl) if gl < dlo - 1e-6 || gl > dhi + 1e-6
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
            t.corner
            if v == 'u_podest'
              t.straight(e)
              t.corner
            end
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
          z1 = t.turn(:landing) { t.corner }
          t.straight((r2 - 1) * a)
          z2 = t.turn(:landing) { t.corner }
          t.straight((r3 - 1) * a)
          depths = [a] * (r1 - 1) + [z1[:w1] - z1[:w0]] + [a] * (r2 - 1) + [z2[:w1] - z2[:w0]] + [a] * (r3 - 1)
          kinds[r1 - 1] = :landing
          kinds[r1 + r2 - 1] = :landing
          flights = [r1, r2, r3]
        when 'l_wendel', 'u_wendel'
          lw = v == 'l_wendel' ? lc : 2 * lc + e
          # Wendelmitte liegt bei m·a + off (off = ½a: mitten in der Drachenstufe)
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
          m_min = [((lc / 2.0 - off) / a).ceil, 0].max
          gap_min = (lc / a).ceil
          m1 = pick(p['m1'], (ntr / 3.0 - 0.5).round, m_min, ((ntr * a - off - lc / 2.0) / a).floor - gap_min, 'Stufen vor der 1. Drachenstufe')
          c1 = m1 * a + off
          m2 = pick(p['m2'], ((ntr * a - c1) / a / 2.0).round, gap_min, ((ntr * a - c1 - lc / 2.0) / a).floor, 'Stufen zwischen den Drachenstufen')
          c2 = c1 + m2 * a
          t.straight(c1 - lc / 2.0)
          t.turn(:winder) { t.corner }
          t.straight(m2 * a - lc)
          t.turn(:winder) { t.corner }
          t.straight(ntr * a - c2 - lc / 2.0)
          depths = [a] * ntr
          flights = [n]
        else
          raise PlanError, "Unbekannte Treppenform: #{v}"
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
            span = cs.empty? ? 0.0 : cs[-1][:w] - cs[0][:w]
            d_min = [lwz / 2.0 + 0.2 * a, span / 2.0 + a / 2.0 + 0.2 * a].max
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
            kite_breakpoints(cs, a, wa, sa, wb, sb, p['min_inner'].to_f).each { |x| bps << x }
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

      KITE_HOOK_MIN = 5.0 # cm – kleinster zulässiger "Haken" einer Drachenstufe an der Innenecke

      # Stützpunkte der Zuordnung s(w) für die Drachenstufen einer Wendelzone.
      # Jede Ecke liegt genau in der Mitte einer Stufe (Stufenkanten bei w_ecke ± a/2,
      # dafür sorgt die Lage der Wendelung). Die beiden Kanten der Drachenstufe treffen
      # die Innenkante symmetrisch bei s_ecke ∓ q -> die Stufe ist spiegelgleich zur
      # Eckdiagonale. q ist entweder 0 (Spitze genau in der Innenecke) oder mindestens
      # KITE_HOOK_MIN – nie ein kleiner Haken um die Ecke.
      def kite_breakpoints(cs, a, wa, sa, wb, sb, min_inner)
        return [] if cs.empty?
        qmin = [KITE_HOOK_MIN, min_inner / 2.0].max
        sig = (sb - sa) / (wb - wa)
        q = sig * a / 2.0
        caps = []
        (0...cs.size - 1).each do |i|
          lm = cs[i + 1][:w] - cs[i][:w]
          gm = cs[i + 1][:s] - cs[i][:s]
          kk = [(lm / a).round, 1].max
          caps << (kk == 1 ? gm / 2.0 : gm / (2.0 * kk))
        end
        q = [q, *caps].min
        ok = lambda do |qq|
          return false if qq < -1e-9
          l1 = cs[0][:w] - a / 2.0 - wa
          r1 = wb - (cs[-1][:w] + a / 2.0)
          return false if l1 < -1e-6 || r1 < -1e-6
          return false if cs[0][:s] - qq - sa < (l1 > 1e-6 ? 0.25 * qq * l1 / (a / 2.0) - 1e-6 : -1e-6)
          return false if sb - (cs[-1][:s] + qq) < (r1 > 1e-6 ? 0.25 * qq * r1 / (a / 2.0) - 1e-6 : -1e-6)
          (0...cs.size - 1).each do |i|
            lm = cs[i + 1][:w] - cs[i][:w] - a
            gm = cs[i + 1][:s] - cs[i][:s] - 2 * qq
            return false if gm < -1e-6 || (lm < 1e-6 && gm.abs > 1e-3)
          end
          true
        end
        q = if q >= qmin - 1e-9 && ok.(q)
              q
            elsif q >= qmin / 2.0 && ok.(qmin)
              qmin
            else
              0.0
            end
        cs.flat_map { |c| [[c[:w] - a / 2.0, c[:s] - q], [c[:w] + a / 2.0, c[:s] + q]] }
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
