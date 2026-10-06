# encoding: UTF-8
# Treppenbau – überlange Wangen: ein Programm in zwei Läufe teilen
# (ohne SketchUp-API, testbar).
#
# Die Maschine bearbeitet nur mach_l (3200 mm) in X, längere Wangen ragen
# rechts über den Tisch. Strategie „Drehen am selben Anschlag“:
#   Lauf A:  Programm-Ursprungsende am linken X-Anschlag, Kante 1 (y = 0)
#            am vorderen Y-Anschlag; bearbeitet x <= x_T (+ Überlauf).
#   Drehen:  Wange 180° in der Tischebene drehen (Oberseite bleibt oben).
#   Lauf B:  anderes Ende am selben linken Anschlag, Kante 1 jetzt am
#            hinteren Y-Anschlag; bearbeitet x >= x_T (− Überlauf).
#            Koordinaten x_B = L − x, y_B = W − y (DH = W). Lauf A läuft im
#            Feld N1 (vorne, Kopfzeile s3), Lauf B im Feld N (hinten, s6):
#            die Rohbreite kürzt sich dann heraus.
# Die Teilung x_T liegt in der Überlappungszone an der Stelle mit dem größten
# Abstand zu allen unteilbaren Bearbeitungen (Nuten, Bohrungen, Gravur,
# Schrägen); nur Außenkonturen werden geteilt und überlappend gefräst.
# Durchgefräste Konturen des zuerst gefrästen Laufs bekommen Haltestege,
# damit der Abfallrahmen beim Drehen am Teil hängt (von Hand trennen).
#
# Allgemeine Programmform (Tisch-Koordinaten in mm, z negativ = Tiefe):
#   { l:, w:, t:, comments: [...], title:, ops: [...], faces: [...] }
#   op:   { k: :mill, pts:, z:, tool:, comp:, cut: (teilbar), tab: (durch),
#           soft: (Nut – nur geteilt, wenn es keine Lücke gibt) }
#         { k: :vdrill, pt:, depth:, d:, tool: }
#   face: { corners:, depth_z:, title:, xr: [x0, x1], body: [...] }
#         body: [:drill, pt, depth, d, tool] | [:mill, seq, z, tool]
#         (Flächen-Koordinaten, ändern sich beim Drehen nicht)

module JTools
  module Treppenbau
    module Lauf
      module_function

      SAFE = 5.0   # Sicherheitsabstand zum Ende des Verfahrwegs (mm)
      FIELD_N1 = 3 # TpaCAD-Feld N1 (vorne): Kopfzeile …:r0w0h0s3
      FIELD_N = 6  # TpaCAD-Feld N (hinten): Kopfzeile …:r0w0h0s6

      # Lauf: name 'A'/'B' (welches Ende am Anschlag), rot (gedreht), prog
      Run = Struct.new(:name, :rot, :prog, :x_t)

      # Teilt ein Programm in Läufe. Rückgabe: { runs: [Run], x_t:, warnings: [] }
      # o: Cnc-Optionen (mach_l, long_overlap, tab_n, tab_w, tab_h); r = Fräserradius
      # ends: Namen der Enden [Ursprungsende, anderes Ende]
      # tabs_on: Lauf mit Haltestegen (der zuerst gefräste): 0 = ungedreht, 1 = gedreht
      def split(prog, o, r, ends = %w[A B], tabs_on = 0)
        mach = o['mach_l'].to_f
        l = prog[:l].to_f
        return { runs: [Run.new(ends[0], false, prog, nil)], x_t: nil, warnings: [] } if l <= mach + 1e-6
        ov = [o['long_overlap'].to_f, 0.0].max
        warn = []
        lo = l - mach + ov + r + SAFE
        hi = mach - ov - r - SAFE
        return { runs: nil, x_t: nil, warnings: ["Rohling #{l.round} mm zu lang für zwei Läufe (höchstens #{max_len(o, r).round} mm)"] } if lo > hi
        hard = atomic_ranges(prog)
        soft = prog[:ops].select { |op| op[:soft] }.map { |op| op_range(op) }
        hit = ->(x, rs) { rs.any? { |a, b| x > a - 1e-6 && x < b + 1e-6 } }
        x_t = best_split(lo, hi, hard + soft, l)
        # durchgehende Nuten (z. B. Tritt- und Setzstufen in einem Zug) dürfen
        # geteilt werden, Bohrungen, Gravur und Schrägen nicht
        x_t = best_split(lo, hi, hard, l) if hit.(x_t, hard + soft)
        if hit.(x_t, hard)
          warn << 'keine Lücke zwischen den Bearbeitungen in der Überlappungszone – Teilung schneidet eine Bearbeitung'
        end
        pa = { l: [l, mach].min, w: prog[:w], t: prog[:t], title: prog[:title], comments: prog[:comments], ops: [], faces: [] }
        pb = pa.merge(ops: [], faces: [])
        prog[:ops].each do |op|
          a0, b0 = op_range(op)
          if op[:k] == :mill && (op[:cut] || (op[:soft] && x_t > a0 && x_t < b0))
            [[pa, -1, x_t + ov, 0], [pb, 1, x_t - ov, 1]].each do |pr, dir, c, idx|
              clip(op[:pts], c, dir).each do |ch|
                pr[:ops].concat(op[:tab] && idx == tabs_on ? with_tabs(op.merge(pts: ch), prog[:t], o) : [op.merge(pts: ch)])
              end
            end
          else
            a, b = op_range(op)
            if (a + b) / 2.0 < x_t
              warn << "Bearbeitung bei x = #{a.round}–#{b.round} mm in Lauf #{ends[0]} nicht erreichbar" if b > mach + 1e-6
              pa[:ops] << op
            else
              warn << "Bearbeitung bei x = #{a.round}–#{b.round} mm in Lauf #{ends[1]} nicht erreichbar" if a < l - mach - 1e-6
              pb[:ops] << op
            end
          end
        end
        prog[:faces].each do |fc|
          a, b = fc[:xr]
          if (a + b) / 2.0 < x_t
            warn << "Aggregat bei x = #{a.round}–#{b.round} mm in Lauf #{ends[0]} nicht erreichbar" if b > mach + 1e-6
            pa[:faces] << fc
          else
            warn << "Aggregat bei x = #{a.round}–#{b.round} mm in Lauf #{ends[1]} nicht erreichbar" if a < l - mach - 1e-6
            pb[:faces] << fc
          end
        end
        pb = rotate(pb, l, prog[:w], mach)
        { runs: [Run.new(ends[0], false, pa, x_t), Run.new(ends[1], true, pb, x_t)], x_t: x_t, warnings: warn.uniq }
      end

      # größte Rohlänge für zwei Läufe
      def max_len(o, r)
        2.0 * (o['mach_l'].to_f - r - SAFE) - 2.0 * [o['long_overlap'].to_f, 0.0].max
      end

      # x-Bereiche der unteilbaren Bearbeitungen
      def atomic_ranges(prog)
        prog[:ops].reject { |op| op[:k] == :mill && (op[:cut] || op[:soft]) }.map { |op| op_range(op) } +
          prog[:faces].map { |fc| fc[:xr] }
      end

      def op_range(op)
        xs = op[:k] == :vdrill ? [op[:pt][0] - op[:d] / 2.0, op[:pt][0] + op[:d] / 2.0] : op[:pts].map(&:first)
        xs.minmax
      end

      # Teilung im Raster 1 mm: größter Abstand zur nächsten Bearbeitung,
      # bei Gleichstand möglichst mittig
      def best_split(lo, hi, atoms, l)
        best = nil
        x = lo
        while x <= hi + 1e-9
          d = atoms.map { |a, b| x < a ? a - x : (x > b ? x - b : 0.0) }.min || Float::INFINITY
          sc = [[d, 200.0].min, -(x - l / 2.0).abs]
          best = [sc, x] if best.nil? || (sc <=> best[0]) > 0
          x += 1.0
        end
        best[1]
      end

      # Polylinie auf x <= c (dir −1) bzw. x >= c (dir +1) beschneiden;
      # Rückgabe: offene Teilstücke in Laufrichtung. Geschlossene Züge
      # (erster = letzter Punkt) werden über den Startpunkt verbunden.
      def clip(pts, c, dir)
        ins = ->(q) { (q[0] - c) * dir >= -1e-9 }
        chains = []
        cur = nil
        pts.each_cons(2) do |a, b|
          ia = ins.(a); ib = ins.(b)
          if ia
            cur ||= [a]
            if ib
              cur << b
            else
              cur << cut_at(a, b, c)
              chains << cur
              cur = nil
            end
          elsif ib
            cur = [cut_at(a, b, c), b]
          end
        end
        chains << cur if cur
        closed = pts.size > 2 && Geo.dist(pts.first, pts.last) < 1e-6
        if closed && chains.size > 1 && Geo.dist(chains.last.last, chains.first.first) < 1e-6
          first = chains.shift
          chains[-1] = chains[-1] + first[1..-1]
        end
        chains.map { |ch| dedup(ch) }.select { |ch| ch.size >= 2 && path_len(ch) > 0.5 }
      end

      def cut_at(a, b, c)
        f = (c - a[0]) / (b[0] - a[0])
        [c, a[1] + f * (b[1] - a[1])]
      end

      def dedup(ch)
        ch.each_with_object([]) { |q, o| o << q if o.empty? || Geo.dist(o[-1], q) > 1e-6 }
      end

      def path_len(ch)
        ch.each_cons(2).sum { |a, b| Geo.dist(a, b) }
      end

      # Haltestege: Stücke der Kontur mit geringerer Tiefe (t − tab_h).
      # Lage nur aus der Geometrie, damit alle Zustellungen gleich liegen.
      def with_tabs(op, t, o)
        n = o['tab_n'].to_i
        tw = o['tab_w'].to_f
        zt = -(t - o['tab_h'].to_f)
        return [op] if n <= 0 || tw <= 0 || o['tab_h'].to_f <= 0 || op[:z] >= zt
        len = path_len(op[:pts])
        k = [n, (len / (4.0 * tw)).floor].min
        return [op] if k <= 0
        cuts = []
        (1..k).each do |i|
          s = len * i / (k + 1).to_f
          cuts << [s - tw / 2.0, s + tw / 2.0]
        end
        res = []
        pos = 0.0
        cuts.each do |s0, s1|
          res << op.merge(pts: sub_path(op[:pts], pos, s0)) if s0 > pos + 0.5
          res << op.merge(pts: sub_path(op[:pts], s0, s1), z: zt, tabbed: true)
          pos = s1
        end
        res << op.merge(pts: sub_path(op[:pts], pos, len)) if len > pos + 0.5
        res
      end

      # Teilstück einer Polylinie zwischen den Bogenlängen s0 und s1
      def sub_path(pts, s0, s1)
        out = []
        acc = 0.0
        pts.each_cons(2) do |a, b|
          sl = Geo.dist(a, b)
          e = acc + sl
          if e >= s0 && acc <= s1 && sl > 1e-12
            out << Geo.lerp(a, b, [(s0 - acc) / sl, 0.0].max) if out.empty?
            out << (e <= s1 ? b : Geo.lerp(a, b, (s1 - acc) / sl))
          end
          acc = e
        end
        dedup(out)
      end

      # Lauf B: 180° um die Senkrechte gedreht, Ursprung am anderen Ende
      def rotate(prog, l, w, mach)
        tr = ->(q) { [l - q[0], w - q[1]] }
        ops = prog[:ops].map do |op|
          op[:k] == :vdrill ? op.merge(pt: tr.(op[:pt])) : op.merge(pts: op[:pts].map(&tr))
        end
        faces = prog[:faces].map do |fc|
          fc.merge(corners: fc[:corners].map { |c| tr.(c) + [c[2]] }, xr: [l - fc[:xr][1], l - fc[:xr][0]])
        end
        prog.merge(l: [l, mach].min, ops: ops, faces: faces)
      end

      # Lauf mit Einrichthinweis im Kopf und in der Überschrift
      def labeled(run)
        pg = run.prog
        info = "Lauf #{run.name}: Feld #{run.rot ? 'N' : 'N1'} – Ende #{run.name} am linken X-Anschlag, " \
               "Kante 1 am #{run.rot ? 'HINTEREN' : 'VORDEREN'} Y-Anschlag"
        info += ' (180 Grad gedreht)' if run.rot
        pg.merge(title: "#{pg[:title]} Lauf #{run.name}", comments: (pg[:comments] || []) + ["'#{info}"],
                 field: run.rot ? FIELD_N : FIELD_N1)
      end

      # --- Programme aufbauen ------------------------------------------------

      # Hilfsfläche einer waagerechten Wangenbohrung als allgemeine Fläche
      def drill_face(h, t, clr, tool)
        fc = Tcn.drill_face(h, t, clr)
        x0 = h[:x]; x1 = h[:x] + Tcn.drill_dir(h)[0] * h[:depth]
        { corners: fc[:corners], depth_z: fc[:depth_z], title: "#{h[:what] || 'Bohrung Gelaenderstab'} (Aggregat)",
          xr: [[x0, x1].min - h[:d] / 2.0, [x0, x1].max + h[:d] / 2.0],
          body: [[:drill, fc[:pt], fc[:depth], fc[:d], tool]] }
      end

      # Eingestemmte Wange (Part) als eigenes Programm auf rechteckigem Rohling
      # (Zugabe blank_margin ringsum). Reihenfolge wie Tcn.build.
      def from_part(part, o, tool_outer)
        m = o['blank_margin'].to_f
        xs = part.poly.map(&:first); ys = part.poly.map(&:last)
        dx = m - xs.min; dy = m - ys.min
        sh = ->(q) { [q[0] + dx, q[1] + dy] }
        poly = part.poly.map(&sh)
        l = xs.max - xs.min + 2 * m; w = ys.max - ys.min + 2 * m
        ds = part.thickness.to_f
        ops = []
        if o['engrave']
          pl = Struct.new(:part, :poly).new(part, poly)
          Tcn.label_strokes(pl, o['text_h'].to_f).each do |st|
            ops << { k: :mill, pts: st, z: -o['deco_depth'].to_f.abs, tool: o['deco_tool'], comp: 0 }
          end
        end
        if !part.pockets.empty? && part.pocket_depth > 0
          paths = if part.pocket_paths && !part.pocket_paths.empty?
                    part.pocket_paths.map { |pa| pa.map(&sh) }
                  else
                    part.pockets.map { |pk| Tcn.pocket_path(pk.map(&sh), o['pocket_d'].to_f) }
                  end
          paths.each do |pa|
            next if pa.size < 2
            ops << { k: :mill, pts: pa, z: -part.pocket_depth, tool: o['pocket_tool'], comp: 0, soft: true }
          end
        end
        drills = (part.drills || []).map { |h| h.merge(x: h[:x] + dx, y: h[:y] + dy) }
        hdr = drills.select { |h| h[:ang] }
        vdr = drills.reject { |h| h[:ang] }
        mark_h = o['drill_wange'].to_s == 'markieren'
        if mark_h
          hdr.each do |h|
            a = [h[:x], h[:y]]
            ops << { k: :mill, pts: [a, Geo.add(a, Geo.mul(Tcn.drill_dir(h), h[:depth]))],
                     z: -o['deco_depth'].to_f.abs, tool: o['deco_tool'], comp: 0 }
          end
        end
        vdr.each { |h| ops << { k: :vdrill, pt: [h[:x], h[:y]], depth: h[:depth], d: h[:d], tool: o['drill_tool'] } }
        loop_ = Tcn.orient(poly, o['climb'] ? :cw : :ccw)
        ops << { k: :mill, pts: loop_ + [loop_.first], z: -(ds + o['overcut'].to_f), tool: tool_outer,
                 comp: o['climb'] ? 1 : 2, cut: true, tab: true }
        faces = mark_h ? [] : hdr.map { |h| drill_face(h, ds, o['drill_clear'].to_f, o['hdrill_tool']) }
        { l: l, w: w, t: ds, title: part.kind == :stringer ? "#{part.label} (eingestemmt)" : part.label, comments: ["'Treppenbau #{part.label}"],
          ops: ops, faces: faces, outline: poly }
      end

      # Aufgesattelte Wange: Programm einer Seite (Wange3d::Prog) in allgemeiner
      # Form – gleiche Reihenfolge und Werte wie bisher Tcn.build_job.
      def from_job(job, prog, opts)
        t = job.t
        l, w = prog.side == 1 ? job.raw_blank : job.blank
        off = prog.side == 1 ? job.raw_off : 0.0
        shift = ->(q) { [q[0] + off, q[1] + off] }
        ops = []
        prog.ops.each do |kind, pts, mode|
          next if pts.nil? || pts.size < 2
          pts = pts.map(&shift)
          case kind
          when :mark
            ops << { k: :mill, pts: pts, z: -opts[:deco_depth].to_f.abs, tool: opts[:deco_tool], comp: 0 }
          when :clear
            [-(t / 2.0), -(t + opts[:overcut].to_f)].each do |z|
              ops << { k: :mill, pts: pts, z: z, tool: opts[:tool_outer], comp: 0 }
            end
          when :contour, :format
            final = case mode
                    when :leave_rest then [t - Wange3d::REST_T, 1.0].max
                    when :finish_rest then [Wange3d::REST_T, t].min + opts[:overcut].to_f
                    else t + opts[:overcut].to_f
                    end
            dir = opts[:climb] ? :cw : :ccw
            if mode.is_a?(Hash)
              seq = mode[:idx].map { |i| pts[i] }
              ccw = Geo.signed_area(pts) > 0
              seq.reverse! if (dir == :cw) == ccw
            else
              lp = Tcn.orient(pts, dir)
              seq = lp + [lp.first]
            end
            through = mode != :leave_rest && final >= t
            Tcn.step_depths(final, opts[:zstep]).each do |z|
              ops << { k: :mill, pts: seq, z: -z, tool: opts[:tool_outer], comp: opts[:climb] ? 1 : 2,
                       cut: true, tab: through }
            end
          end
        end
        faces = prog.faces.map do |fc|
          corners = fc[:corners].map { |c| [c[0] + off, c[1] + off, c[2]] }
          { corners: corners, depth_z: fc[:depth_z], title: "Schraege Aggregat #{fc[:tool]}",
            xr: face_range(corners, fc[:paths], fc[:r] || 0.0),
            body: fc[:paths].map { |seq, depth| [:mill, seq, depth, fc[:tool]] } }
        end
        { l: l, w: w, t: t, title: "#{job.label} Seite #{prog.side}",
          comments: ["'Treppenbau #{job.label} Seite #{prog.side}"], ops: ops, faces: faces }
      end

      # x-Bereich einer Aggregat-Bearbeitung im Tisch: Bahnpunkte (fx) auf der
      # Fläche und in voller Tiefe entlang der Flächennormalen
      def face_range(corners, paths, r)
        c1 = corners[0]
        xv = Geo.norm([corners[1][0] - c1[0], corners[1][1] - c1[1]])
        nv = [xv[1], -xv[0]]
        xs = []
        paths.each do |seq, depth|
          seq.each do |fx, _|
            px = c1[0] + xv[0] * fx
            xs << px << px + nv[0] * depth
          end
        end
        xs.empty? ? [c1[0], c1[0]] : [xs.min - r, xs.max + r]
      end
    end
  end
end
