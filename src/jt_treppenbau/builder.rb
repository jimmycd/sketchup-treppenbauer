# encoding: UTF-8
# Treppenbau – Erzeugung der SketchUp-Geometrie aus einem Plan.

require 'json'

module JTools
  module Treppenbau
    module Builder
      module_function

      SOFT_ANGLE = 25.0 * Math::PI / 180.0

      MATERIALS = {
        holz:   ['Treppe Holz',   [196, 150, 98], nil],
        wange:  ['Treppe Wange',  [150, 102, 60], nil],
        beton:  ['Treppe Beton',  [185, 185, 180], nil],
        metall: ['Treppe Metall', [70, 72, 78], nil],
        decke:  ['Treppe Decke',  [205, 205, 205], 0.45]
      }.freeze

      TAGS = {
        stufen:   'Treppe – Stufen',
        trag:     'Treppe – Tragkonstruktion',
        gelaender: 'Treppe – Geländer',
        hilfs:    'Treppe – Hilfslinien'
      }.freeze

      # Baut die komplette Treppe in die Komponentendefinition.
      # Liefert den Plan (für Infos / Warnungen).
      def build(defn, params)
        plan = Layout.compute(params)
        model = defn.model
        @model = model
        ents = defn.entities
        ents.clear!
        p = params
        cons = p['construction']
        h = plan.h
        n = plan.n
        lw = plan.lines_w

        steps = sub(ents, 'Stufen', :stufen)
        if cons == 'massiv'
          build_massive(steps, plan, p)
        else
          build_treads(steps, plan, p)
        end

        if cons == 'wange'
          build_stringers(sub(ents, 'Wangen', :trag), plan, p)
        elsif cons == 'holm'
          build_holm(sub(ents, 'Holm', :trag), plan, p)
        end

        if plan.variant == 'spindel'
          top = plan.H + (p['rail'] != 'keins' ? p['rail_h'] : 10.0)
          g = sub(ents, 'Spindel', :trag)
          prism(g.entities, circle([0.0, 0.0], plan.spiral[:ri], 36), top, 0.0, mat(:metall))
        end

        build_rails(sub(ents, 'Geländer', :gelaender), plan, p) if p['rail'] != 'keins'
        build_walkline(sub(ents, 'Gehlinie', :hilfs), plan) if p['show_walkline']
        build_floor(sub(ents, 'Deckenkante', :hilfs), plan, p) if p['show_floor'] && p['floor_t'] > 0

        build_space(sub(ents, 'Verfügbarer Raum', :hilfs), plan) if plan.space

        lbl = Params::VARIANTS.find { |v| v[0] == plan.variant }
        defn.description = "#{lbl ? lbl[1] : plan.variant}: #{n} × #{h.round(2)} / #{plan.a.round(2)} cm"
        plan
      end

      # --- Stufen ------------------------------------------------------------

      def build_treads(grp, plan, p)
        h = plan.h; lw = plan.lines_w
        d = p['tread_t']; u = p['nosing']
        risers = p['risers']; ts = p['riser_t']
        ext = u + (risers ? ts : 0.0)
        m = mat(:holz)
        (0...plan.treads).each do |k|
          reg = plan.region(lw[k], lw[k + 1] + ext).map(&:first)
          top = (k + 1) * h
          g = prism(grp.entities, reg, top, top - d, m)
          g.name = plan.kinds[k] == :landing ? "Podest #{k + 1}" : "Stufe #{k + 1}" if g
        end
        return unless risers
        (0...plan.treads).each do |k|
          wa = lw[k] + u
          reg = plan.region(wa, wa + ts).map(&:first)
          z0 = k * h
          z1 = (k + 1) * h - d
          next if z1 - z0 < 0.5
          g = prism(grp.entities, reg, z1, z0, m)
          g.name = "Setzstufe #{k + 1}" if g
        end
      end

      def build_massive(grp, plan, p)
        h = plan.h; lw = plan.lines_w
        t = p['slab_t']
        tv = t * Math.sqrt(plan.a**2 + h**2) / plan.a
        m = mat(:beton)
        (0...plan.treads).each do |k|
          reg = plan.region(lw[k], lw[k + 1])
          top = (k + 1) * h
          zb = reg.map do |_pt, w|
            z = if plan.kinds[k] == :landing
                  top - t
                else
                  f = (w - lw[k]) / (lw[k + 1] - lw[k])
                  k * h - tv + f * h
                end
            [[z, 0.0].max, top - 1.0].min
          end
          g = prism(grp.entities, reg.map(&:first), top, zb, m)
          g.name = plan.kinds[k] == :landing ? "Podest #{k + 1}" : "Stufe #{k + 1}" if g
        end
      end

      # --- Tragkonstruktion -----------------------------------------------

      # Seiten mit eingestemmter Wange (außerhalb der Laufbreite)
      def stringer_sides(plan, p)
        %i[outer inner].select { |w| Params.side_kind(p, w, plan.outer_side, !plan.spiral.nil?) == 'wange' }
      end

      def build_stringers(grp, plan, p)
        r = Stringers.compute(plan, p)
        plan.warnings.concat(r[:warnings]) unless r[:warnings].empty? || plan.warnings.include?(r[:warnings][0])
        m = mat(:wange)
        st = p['str_t']
        cnt = Hash.new(0)
        r[:wange].each do |b|
          base, tops, bots = Stringers.wange_band(b)
          nrm = nil
          if b[:tp] || base.size > 2
            # Zwischenpunkte auf geradem Brett (geschwungen bzw. Bodenschnitt) –
            # Normalen zwischen den Endnormalen (Gehrung) linear verteilen, damit
            # die Rückseite nicht in die Gehrung zurückläuft
            pn = b[:side] > 0 ? Geo.right(b[:dir]) : Geo.left(b[:dir])
            e0 = b[:n0] || pn; e1 = b[:n1] || pn
            l = Geo.dist(base[0], base[-1])
            nrm = base.map do |q|
              t = l < 1e-9 ? 0.0 : Geo.dist(base[0], q) / l
              Geo.add(Geo.mul(e0, 1 - t), Geo.mul(e1, t))
            end
          end
          g = band(grp.entities, base, tops, bots, b[:side], 0.0, st, m, [b[:n0], b[:n1]], nrm)
          cnt[b[:which]] += 1
          g.name = "Wange #{b[:which] == :outer ? 'außen' : 'innen'} #{cnt[b[:which]]}" if g
        end
        r[:newels].each do |nw|
          c = nw[:pt]
          sq = [c, Geo.add(c, Geo.mul(nw[:na], st)),
                Geo.add(Geo.add(c, Geo.mul(nw[:na], st)), Geo.mul(nw[:nb], st)),
                Geo.add(c, Geo.mul(nw[:nb], st))]
          which = nw[:which]
          rail_here = p['rail'] == 'beide' || (p['rail'] == 'innen' && which == :inner) || (p['rail'] == 'aussen' && which == :outer)
          z1 = nw[:ztop] + (rail_here ? p['rail_h'] - p['str_over'] : 10.0)
          g = prism(grp.entities, sq, z1, nw[:zbot], m)
          g.name = 'Pfosten' if g
        end
        r[:sattel].each do |sb|
          g = hprism(grp.entities, sb[:origin], sb[:dir], sb[:poly], sb[:t], m)
          g.name = "Aufgesattelte Wange #{sb[:which] == :outer ? 'außen' : 'innen'} #{sb[:nr]}" if g
        end
      end

      # Senkrecht stehendes Brett: Umriss poly [[x, z], ...] in der Ebene durch
      # origin entlang dir, Dicke t mittig.
      def hprism(ents, origin, dir, poly, t, material = nil)
        pts = Geo.clean_ring(poly, 0.02)
        return nil if pts.size < 3
        pts.reverse! if Geo.signed_area(pts) < 0
        nrm = Geo.right(dir)
        mk = lambda do |off|
          pts.map do |x, z|
            q = Geo.add(Geo.add(origin, Geo.mul(dir, x)), Geo.mul(nrm, off))
            pt3(q[0], q[1], z)
          end
        end
        a = mk.(-t / 2.0); b = mk.(t / 2.0)
        g = ents.add_group
        e = g.entities
        face(e, a, vec(-nrm[0], -nrm[1], 0))
        face(e, b, vec(nrm[0], nrm[1], 0))
        n = pts.size
        n.times do |i|
          j = (i + 1) % n
          ex = pts[j][0] - pts[i][0]; ez = pts[j][1] - pts[i][1]
          # Außennormale der Kante im (x, z)-System (Umriss gegen Uhrzeigersinn)
          ox = ez; oz = -ex
          hint = vec(dir[0] * ox, dir[1] * ox, oz)
          face(e, [a[i], a[j], b[j], b[i]], hint)
        end
        soften(e)
        g.material = material if material
        g
      end

      def build_holm(grp, plan, p)
        d = p['tread_t']; hw = p['holm_w']; hh = p['holm_h']
        h = plan.h
        zs = (0...plan.n).map { |k| [k * h - d, 0.5 * (h - d)].max }
        m = mat(:metall)
        plan.profile(:walk, zs).each do |pc|
          base = pc.map(&:first)
          tops = pc.map { |it| it[1] }
          bots = tops.map { |z| z - hh }
          g = band(grp.entities, base, tops, bots, 1, -hw / 2.0, hw / 2.0, m)
          g.name = 'Holm' if g
        end
      end

      # --- Geländer -----------------------------------------------------------

      def build_rails(grp, plan, p)
        sides = case p['rail']
                when 'aussen' then [:outer]
                when 'innen'  then [:inner]
                else [:outer, :inner]
                end
        sides.delete(:inner) if plan.spiral && plan.spiral[:ri] < 10
        rh = p['rail_h']; r = p['rail_d'] / 2.0; ps = p['post_s']
        every = [p['post_every'].to_i, 1].max
        m = mat(:metall)
        sides.each do |which|
          side = which == :outer ? plan.outer_side : -plan.outer_side
          on_str = stringer_sides(plan, p).include?(which)
          over = on_str ? p['str_over'] : 0.0
          off = on_str ? p['str_t'] / 2.0 : -p['rail_inset']
          zs = (0...plan.n).map { |k| plan.nose_z(k) + rh }
          poly = plan.send(which)
          keys = plan.keys_for(which)
          plan.profile(which, zs).each do |pc|
            base = pc.map(&:first)
            mn = Geo.miter_normals(base, side)
            path = pc.each_with_index.map do |it, i|
              q = Geo.add(it[0], Geo.mul(mn[i], off))
              [q[0], q[1], it[1]]
            end
            tube(grp.entities, path, r, 12, m)

            # Pfosten: Anfang, Ende, Stufenmitten
            posts = []
            [pc[0], pc[-1]].each do |it|
              next unless it[3]
              zb = on_str ? (Stringers.top_at(plan, p, which, it[2]) || plan.nose_z(it[3]) + over) : plan.nose_z(it[3])
              posts << [it[0], poly.tangent(it[2] + (it.equal?(pc[0]) ? 0.01 : -0.01)), zb, it[1]]
            end
            p0 = pc[0][2]; p1 = pc[-1][2]
            (0...plan.treads).each do |k|
              next unless (k + 1) % every == 0
              a = keys[k]; b = keys[k + 1]
              next if b - a < 1.0
              pm = (a + b) / 2.0
              next if pm <= p0 + 1.0 || pm >= p1 - 1.0
              z_rail = interp_piece(pc, pm)
              base_z = on_str ? (Stringers.top_at(plan, p, which, pm) || z_rail - rh + over) : (k + 1) * plan.h
              posts << [poly.at(pm), poly.tangent(pm), base_z, z_rail]
            end
            posts.each do |pt, tg, zb, zr|
              nrm = side > 0 ? Geo.right(tg) : Geo.left(tg)
              c = Geo.add(pt, Geo.mul(nrm, off))
              sq = square(c, tg, ps)
              top = zr - r
              next if top - zb < 2
              prism(grp.entities, sq, top, zb, m)
            end
          end
        end
      end

      def interp_piece(pc, prm)
        pc.each_cons(2) do |a, b|
          next unless prm >= a[2] && prm <= b[2]
          f = (b[2] - a[2]).abs < 1e-9 ? 0.0 : (prm - a[2]) / (b[2] - a[2])
          return a[1] + f * (b[1] - a[1])
        end
        pc[-1][1]
      end

      # --- Hilfsgeometrie -------------------------------------------------

      def build_walkline(grp, plan)
        zs = (0...plan.n).map { |k| plan.nose_z(k) }
        plan.profile(:walk, zs).each do |pc|
          pts = pc.map { |it| pt3(it[0][0], it[0][1], it[1] + 0.2) }
          grp.entities.add_edges(pts) if pts.size >= 2
        end
        # Kreis am Antritt (Laufrichtung beginnt hier)
        c = plan.walk.at(0.0)
        pts = circle(c, 4.0, 16).map { |q| pt3(q[0], q[1], plan.h + 0.2) }
        grp.entities.add_edges(pts + [pts[0]])
      end

      # Umriss des vorgegebenen Raums (Platzvorgabe) als Hilfslinien am Boden
      def build_space(grp, plan)
        sp = plan.space
        pts = sp[:poly].map { |q| pt3(q[0], q[1], 0.0) }
        grp.entities.add_edges(pts + [pts[0]])
        return unless sp[:loch]
        z = plan.H + 0.2
        lp = sp[:loch].map { |q| pt3(q[0], q[1], z) }
        grp.entities.add_edges(lp + [lp[0]])
      end

      def build_floor(grp, plan, p)
        if plan.space && plan.space[:loch]
          xs = plan.space[:loch].map(&:first); ys = plan.space[:loch].map(&:last)
          x0, x1, y0, y1 = xs.min, xs.max, ys.min, ys.max
          rx = plan.space[:poly].map(&:first); ry = plan.space[:poly].map(&:last)
          d = 60.0
          bx0 = [rx.min, x0 - d].max; bx1 = [rx.max, x1 + d].min
          by0 = [ry.min, y0 - d].max; by1 = [ry.max, y1 + d].min
          rects = [[bx0, by0, bx1, y0], [bx0, y1, bx1, by1], [bx0, y0, x0, y1], [x1, y0, bx1, y1]]
          rects.each do |a, b, c, e|
            next if c - a < 0.5 || e - b < 0.5
            g = prism(grp.entities, [[a, b], [c, b], [c, e], [a, e]], plan.H, plan.H - p['floor_t'], mat(:decke))
            g.name = 'Decke am Treppenloch' if g
          end
          return
        end
        l = plan.line(plan.wtot)
        dir = Geo.norm(Geo.sub(l[:out], l[:in]))
        fwd = plan.outer_side > 0 ? Geo.left(dir) : Geo.right(dir)
        depth = 60.0
        quad = [l[:in], l[:out], Geo.add(l[:out], Geo.mul(fwd, depth)), Geo.add(l[:in], Geo.mul(fwd, depth))]
        g = prism(grp.entities, quad, plan.H, plan.H - p['floor_t'], mat(:decke))
        g.name = 'Deckenkante (Austritt)' if g
      end

      # --- Geometrie-Grundfunktionen -----------------------------------------

      def pt3(x, y, z)
        Geom::Point3d.new(x.to_f.cm, y.to_f.cm, z.to_f.cm)
      end

      def vec(x, y, z)
        Geom::Vector3d.new(x.to_f, y.to_f, z.to_f)
      end

      def circle(c, r, segs)
        (0...segs).map do |i|
          a = 2.0 * Math::PI * i / segs
          [c[0] + r * Math.cos(a), c[1] + r * Math.sin(a)]
        end
      end

      def square(c, tg, s)
        nrm = Geo.left(tg)
        hs = s / 2.0
        [[-1, -1], [1, -1], [1, 1], [-1, 1]].map do |a, b|
          Geo.add(c, Geo.add(Geo.mul(tg, a * hs), Geo.mul(nrm, b * hs)))
        end
      end

      def sub(ents, name, tag)
        g = ents.add_group
        g.name = name
        g.layer = layer(tag)
        g
      end

      def layer(sym)
        name = TAGS[sym]
        @model.layers[name] || @model.layers.add(name)
      end

      def mat(sym)
        name, rgb, alpha = MATERIALS[sym]
        m = @model.materials[name]
        unless m
          m = @model.materials.add(name)
          m.color = Sketchup::Color.new(*rgb)
          m.alpha = alpha if alpha
        end
        m
      end

      # Fläche hinzufügen und nach Hinweisvektor ausrichten.
      def face(ents, pts, hint)
        q = []
        pts.each { |x| q << x if q.empty? || q[-1].distance(x) > 0.0005 }
        q.pop while q.size > 1 && q[0].distance(q[-1]) <= 0.0005
        return nil if q.size < 3
        f = begin
          ents.add_face(q)
        rescue ArgumentError, RuntimeError
          nil
        end
        return nil unless f.is_a?(Sketchup::Face)
        f.reverse! if hint && f.normal.dot(hint) < 0
        f
      end

      # Senkrechtes Prisma über einem Grundrisspolygon (cm).
      # ztop / zbot: Zahl oder Array je Punkt.
      def prism(ents, poly, ztop, zbot, material = nil)
        pts = Geo.clean_ring(poly, 0.02)
        return nil if pts.size < 3
        zt = ztop.is_a?(Array) ? ztop.dup : Array.new(pts.size, ztop.to_f)
        zb = zbot.is_a?(Array) ? zbot.dup : Array.new(pts.size, zbot.to_f)
        if zt.size != pts.size || zb.size != pts.size
          zt = Array.new(pts.size, zt.max); zb = Array.new(pts.size, zb.min)
        end
        if Geo.signed_area(pts) < 0
          pts.reverse!; zt.reverse!; zb.reverse!
        end
        return nil if Geo.signed_area(pts).abs < 0.5
        g = ents.add_group
        e = g.entities
        top = pts.each_with_index.map { |q, i| pt3(q[0], q[1], zt[i]) }
        bot = pts.each_with_index.map { |q, i| pt3(q[0], q[1], zb[i]) }
        up = vec(0, 0, 1); down = vec(0, 0, -1)
        cap(e, pts, top, zt, up)
        cap(e, pts, bot, zb, down)
        n = pts.size
        n.times do |i|
          j = (i + 1) % n
          ed = Geo.sub(pts[j], pts[i])
          o = Geo.right(ed)
          face(e, [bot[i], bot[j], top[j], top[i]], vec(o[0], o[1], 0))
        end
        soften(e)
        g.material = material if material
        g
      end

      def cap(e, pts, p3, zs, hint)
        if zs.max - zs.min < 1e-6
          return if face(e, p3, hint)
        end
        Geo.triangulate(pts).each { |a, b, c| face(e, [p3[a], p3[b], p3[c]], hint) }
      end

      # Band entlang einer Polylinie (Wange, Holm).
      # side: +1 rechts / -1 links; oa/ob: Abstände der beiden Seitenflächen
      def band(ents, base, tops, bots, side, oa, ob, material = nil, ends = nil, normals = nil)
        return nil if base.size < 2
        mn = normals || Geo.miter_normals(base, side)
        if ends && !normals
          mn[0] = ends[0] if ends[0]
          mn[-1] = ends[1] if ends[1]
        end
        n = base.size
        bots = bots.map { |z| [z, 0.0].max }
        tops = tops.each_with_index.map { |z, i| [z, bots[i] + 0.5].max }
        a = (0...n).map { |i| Geo.add(base[i], Geo.mul(mn[i], oa)) }
        b = (0...n).map { |i| Geo.add(base[i], Geo.mul(mn[i], ob)) }
        g = ents.add_group
        e = g.entities
        up = vec(0, 0, 1); down = vec(0, 0, -1)
        sa = oa < ob ? -1.0 : 1.0
        at = ->(i) { pt3(a[i][0], a[i][1], tops[i]) }
        ab = ->(i) { pt3(a[i][0], a[i][1], bots[i]) }
        bt = ->(i) { pt3(b[i][0], b[i][1], tops[i]) }
        bb = ->(i) { pt3(b[i][0], b[i][1], bots[i]) }
        (0...n - 1).each do |i|
          j = i + 1
          d = Geo.norm(Geo.sub(base[j], base[i]))
          nr = side > 0 ? Geo.right(d) : Geo.left(d)
          face(e, [ab.(i), ab.(j), at.(j), at.(i)], vec(nr[0] * sa, nr[1] * sa, 0))
          face(e, [bb.(i), bb.(j), bt.(j), bt.(i)], vec(-nr[0] * sa, -nr[1] * sa, 0))
          face(e, [at.(i), bt.(i), bt.(j)], up)
          face(e, [at.(i), bt.(j), at.(j)], up)
          face(e, [ab.(i), bb.(i), bb.(j)], down)
          face(e, [ab.(i), bb.(j), ab.(j)], down)
        end
        d0 = Geo.norm(Geo.sub(base[1], base[0]))
        d1 = Geo.norm(Geo.sub(base[-1], base[-2]))
        face(e, [ab.(0), bb.(0), bt.(0), at.(0)], vec(-d0[0], -d0[1], 0))
        face(e, [ab.(n - 1), bb.(n - 1), bt.(n - 1), at.(n - 1)], vec(d1[0], d1[1], 0))
        soften(e)
        g.material = material if material
        g
      end

      # Rohr entlang eines 3D-Pfads (cm), Querschnitt in der Lotebene.
      def tube(ents, path, r, segs, material = nil)
        clean = []
        path.each do |q|
          clean << q if clean.empty? || Math.sqrt((q[0] - clean[-1][0])**2 + (q[1] - clean[-1][1])**2 + (q[2] - clean[-1][2])**2) > 0.05
        end
        return nil if clean.size < 2
        tg = Geo.tangents(clean.map { |q| [q[0], q[1]] })
        rings = clean.each_with_index.map do |q, i|
          nr = Geo.right(tg[i])
          (0...segs).map do |k|
            an = 2.0 * Math::PI * k / segs
            [q[0] + nr[0] * r * Math.cos(an), q[1] + nr[1] * r * Math.cos(an), q[2] + r * Math.sin(an)]
          end
        end
        g = ents.add_group
        e = g.entities
        p3 = ->(v) { pt3(v[0], v[1], v[2]) }
        (0...clean.size - 1).each do |i|
          c0 = clean[i]; c1 = clean[i + 1]
          cm = [(c0[0] + c1[0]) / 2.0, (c0[1] + c1[1]) / 2.0, (c0[2] + c1[2]) / 2.0]
          segs.times do |k|
            k2 = (k + 1) % segs
            q = [rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]]
            [[q[0], q[1], q[2]], [q[0], q[2], q[3]]].each do |tri|
              mx = tri.map { |v| v[0] }.sum / 3.0 - cm[0]
              my = tri.map { |v| v[1] }.sum / 3.0 - cm[1]
              mz = tri.map { |v| v[2] }.sum / 3.0 - cm[2]
              face(e, tri.map(&p3), vec(mx, my, mz))
            end
          end
        end
        t0 = [clean[1][0] - clean[0][0], clean[1][1] - clean[0][1], clean[1][2] - clean[0][2]]
        t1 = [clean[-1][0] - clean[-2][0], clean[-1][1] - clean[-2][1], clean[-1][2] - clean[-2][2]]
        face(e, rings[0].map(&p3), vec(-t0[0], -t0[1], -t0[2]))
        face(e, rings[-1].map(&p3), vec(t1[0], t1[1], t1[2]))
        soften(e, 50.0 * Math::PI / 180.0)
        g.material = material if material
        g
      end

      def soften(e, max_angle = SOFT_ANGLE)
        e.grep(Sketchup::Edge).each do |ed|
          fs = ed.faces
          next unless fs.size == 2
          ang = fs[0].normal.angle_between(fs[1].normal)
          if ang < max_angle
            ed.soft = true
            ed.smooth = true
          end
        end
      end
    end
  end
end
