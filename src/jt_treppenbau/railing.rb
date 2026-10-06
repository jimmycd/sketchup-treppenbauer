# encoding: UTF-8
# Treppenbau – Geländerplanung (ohne SketchUp-API, testbar).
#
# Regeln (erster Entwurf):
#   * Pfosten am Antritt, am Austritt und an jedem Laufwechsel: an jeder Ecke
#     der Begrenzung (L: eine Ecke, U mit Treppenauge innen: zwei Ecken mit
#     Querstück) bzw. bei geraden Zwischenpodesten an der Podestvorderkante.
#   * Der Handlauf läuft von Pfosten zu Pfosten (stößt an die Pfosten).
#   * Stäbe zwischen den Pfosten, lichter Abstand höchstens bal_gap:
#       eingestemmte Wange – jeder Stab steht lotrecht auf der Wangenoberkante
#         und ist um bal_depth eingelassen (lotrechte Bohrung, d. h. schräg zur
#         Wangenkante); gleichmäßig zwischen den Pfosten verteilt.
#       aufgesattelte Wange, freitragend, Holm, Massiv – die Stäbe stehen auf
#         den Stufen. Je Stufe wird die Stufentiefe (auf der Stabachse, von
#         Vorderkante zu Vorderkante der nächsten Stufe) in m gleiche Felder
#         geteilt, der Stab steht in Feldmitte. Bei gleich tiefen Stufen
#         ergibt das einen durchgehend gleichen Stababstand, und jeder Stab
#         hält mindestens bal_edge Abstand zu beiden Stufenkanten.
# Koordinaten: u = Parameter (cm) entlang der Begrenzung (plan.inner bzw.
# plan.outer), z = Höhe (cm). Die Achse von Pfosten/Stäben/Handlauf liegt
# auf der Wangenmitte bzw. um rail_inset nach innen versetzt.

module JTools
  module Treppenbau
    module Railing
      module_function

      CORNER_MIN = 20.0 * Math::PI / 180.0 # Richtungsänderung ab der eine Ecke einen Pfosten bekommt
      POST_CAP = 6.0                        # Pfosten ragt so weit über die Handlaufoberkante

      def sides(plan, p)
        return [] if p['rail'] == 'keins'
        s = case p['rail']
            when 'aussen' then [:outer]
            when 'innen'  then [:inner]
            else [:outer, :inner]
            end
        s.delete(:inner) if plan.spiral && plan.spiral[:ri] < 10
        s
      end

      # Ergebnis (im Plan zwischengespeichert):
      #   { sides: [ { which:, side:, mount: :wange | :stufe, off:, posts: [...],
      #                bars: [...], rails: [[[x, y, z], ...], ...] } ], warnings: [] }
      #   Pfosten: { u:, pt:, tg:, s:, zbot:, ztop:, role: :antritt | :austritt | :ecke | :podest }
      #   Stab:    { u:, pt:, tg:, d:, zbot:, ztop:, tread: k | nil,
      #              drill: { u:, z:, depth:, d: } }   (Bohrung in Wange bzw. Stufe)
      def compute(plan, p)
        cache = plan.instance_variable_get(:@railing)
        return cache if cache
        res = { sides: [], warnings: [] }
        sides(plan, p).each { |which| res[:sides] << side_plan(plan, p, which, res[:warnings]) }
        plan.instance_variable_set(:@railing, res)
        res
      end

      def side_plan(plan, p, which, warnings)
        side = which == :outer ? plan.outer_side : -plan.outer_side
        mount = Params.side_kind(p, which, plan.outer_side, !plan.spiral.nil?) == 'wange' ? :wange : :stufe
        off = mount == :wange ? p['str_t'] / 2.0 : -p['rail_inset']
        poly = plan.send(which)
        keys = plan.keys_for(which)
        # Wendeltreppe: Begrenzung kann sich überlappen (> 360°), der Strahlschnitt
        # liefert dann für Antritt/Austritt den falschen Umlauf -> proportional
        if plan.spiral
          keys = plan.lines_w.map { |w| poly.length * w / [plan.wtot, 1e-9].max }
        end
        zs = (0...plan.nlines).map { |k| plan.nose_z(k) + p['rail_h'] }
        sd = { which: which, side: side, mount: mount, off: off, poly: poly, keys: keys, zs: zs,
               posts: [], bars: [], rails: [] }
        sd[:posts] = posts(plan, p, sd)
        sd[:bars] = bars(plan, p, sd, warnings)
        sd[:rails] = rails(plan, p, sd)
        sd
      end

      # --- Hilfsfunktionen ---------------------------------------------------

      # Normale (zur Seite side) an Parameter u; an Ecken die Gehrungsnormale
      def normal_at(poly, u, side)
        pts = poly.pts
        c = poly.cum
        i = (1...pts.size - 1).find { |j| (c[j] - u).abs < 1e-6 }
        if i
          Geo.miter_normals([pts[i - 1], pts[i], pts[i + 1]], side)[1]
        else
          tg = poly.tangent(u)
          side > 0 ? Geo.right(tg) : Geo.left(tg)
        end
      end

      # Punkt auf der Achse; vor dem Anfang bzw. hinter dem Ende der Begrenzung
      # geradlinig verlängert (Pfosten vor dem Antritt / hinter dem Austritt)
      def axis_pt(sd, u)
        poly = sd[:poly]
        l = poly.length
        uc = [[u, 0.0].max, l].min
        q = Geo.add(poly.at(uc), Geo.mul(poly.tangent(uc), u - uc))
        Geo.add(q, Geo.mul(normal_at(poly, uc, sd[:side]), sd[:off]))
      end

      # Handlaufhöhe (Achse) an u: linear zwischen den Stufenlinien; an
      # Innenecken (mehrere Linien am selben Punkt) der höchste Wert;
      # außerhalb mit dem Endwert fortgesetzt
      def rail_z(sd, u)
        keys = sd[:keys]; zs = sd[:zs]
        return zs[0] if u <= keys[0]
        return zs[-1] if u >= keys[-1]
        best = nil
        (0...keys.size - 1).each do |k|
          a = keys[k]; b = keys[k + 1]
          next unless u >= a - 1e-6 && u <= b + 1e-6
          z = b - a < 1e-6 ? [zs[k], zs[k + 1]].max : zs[k] + (u - a) / (b - a) * (zs[k + 1] - zs[k])
          best = z if best.nil? || z > best
        end
        best || zs[-1]
      end

      # Ecken (Parameter) der Begrenzung mit Richtungsänderung > CORNER_MIN
      def corners(poly)
        pts = poly.pts
        c = poly.cum
        res = []
        (1...pts.size - 1).each do |i|
          d0 = Geo.norm(Geo.sub(pts[i], pts[i - 1])); d1 = Geo.norm(Geo.sub(pts[i + 1], pts[i]))
          ang = Math.atan2(Geo.cross(d0, d1).abs, Geo.dot(d0, d1))
          res << c[i] if ang > CORNER_MIN
        end
        res
      end

      # Oberfläche der Stufe bzw. des Podests unter Parameter u (niedrigste Stufe)
      def tread_top(plan, keys, u)
        (0...plan.treads).each do |k|
          return (k + 1) * plan.h if keys[k] <= u + 1e-6 && keys[k + 1] >= u - 1e-6 && keys[k + 1] - keys[k] > 0.05
        end
        u <= keys[0] ? 0.0 : plan.H
      end

      def wange_bot(plan, p, which, u)
        r = Stringers.compute(plan, p)
        bs = r[:wange].select { |x| x[:which] == which }
        return nil if bs.empty?
        dist = ->(b) { u < b[:u0] ? b[:u0] - u : (u > b[:u1] ? u - b[:u1] : 0.0) }
        dm = bs.map(&dist).min
        # nächstgelegene Bretter (an Pfosten: beide angrenzenden)
        bs.select { |b| dist.(b) <= dm + [p['newel_s'], 1.0].max }.map do |b|
          Stringers.bot(b, [[u, b[:u0]].max, b[:u1]].min)
        end.min
      end

      def wange_top(plan, p, which, u)
        Stringers.top_at(plan, p, which, u)
      end

      # --- Pfosten ----------------------------------------------------------

      # Lage der Pfosten einer Seite (nur u und Rolle, ohne Höhen) – wird auch
      # von Stringers benutzt (Pfosten als Zwischenstück zwischen den Wangen).
      # u = Mitte des Pfostens als Parameter der Begrenzung (an Ecken: Ecke
      # der Begrenzung).
      def post_positions(plan, p, which, keys = nil, wange = nil)
        s = p['newel_s']
        poly = plan.send(which)
        keys ||= plan.keys_for(which)
        wange = Params.side_kind(p, which, plan.outer_side, !plan.spiral.nil?) == 'wange' if wange.nil?
        u0 = keys[0]; u1 = keys[-1]
        list = []
        # Antritt / Austritt: bei Wangen innerhalb der Wange (Wange stößt an den
        # Pfosten), sonst vor der ersten bzw. hinter der letzten Stufenkante
        list << { u: wange ? u0 + s / 2.0 : u0 - s / 2.0, role: :antritt }
        list << { u: wange ? u1 - s / 2.0 : u1 + s / 2.0, role: :austritt }
        unless plan.spiral
          corners(poly).each { |c| list << { u: c, role: :ecke } if c > u0 + s && c < u1 - s }
          # gerade Zwischenpodeste (ohne Ecke): Pfosten an der Podestvorderkante
          (0...plan.treads - 1).each do |k|
            next unless plan.kinds[k] == :landing
            a = keys[k]; b = keys[k + 1]
            next if list.any? { |q| q[:role] == :ecke && q[:u] > a - s && q[:u] < b + s }
            list << { u: a + s / 2.0, role: :podest }
          end
        end
        list.sort_by! { |q| q[:u] }
      end

      def posts(plan, p, sd)
        s = p['newel_s']
        r = p['rail_d'] / 2.0
        keys = sd[:keys]; poly = sd[:poly]
        wange = sd[:mount] == :wange
        list = post_positions(plan, p, sd[:which], keys, wange)
        list.each do |q|
          u = q[:u]
          q[:s] = s
          q[:pt] = axis_pt(sd, u)
          q[:tg] = poly.tangent([[u, 0.01].max, poly.length - 0.01].min)
          if q[:role] == :ecke
            # an der Ecke nach dem ankommenden Lauf ausgerichtet
            q[:tg] = poly.tangent(u - 0.01)
          end
          q[:ztop] = rail_z(sd, u) + r + POST_CAP
          q[:zbot] = if wange
                       q[:role] == :antritt ? 0.0 : [(wange_bot(plan, p, sd[:which], u) || 0.0), 0.0].max
                     elsif q[:role] == :antritt
                       0.0
                     elsif q[:role] == :austritt
                       plan.H
                     else
                       tread_top(plan, keys, u)
                     end
        end
        list
      end

      # --- Stäbe ------------------------------------------------------------

      def bars(plan, p, sd, warnings)
        d = p['bal_d']; gap = p['bal_gap']
        return [] if d <= 0 || gap <= 0
        r = p['rail_d'] / 2.0
        posts = sd[:posts]
        out = []
        maxgap = 0.0
        posts.each_cons(2) do |pa, pb|
          ua = pa[:u] + pa[:s] / 2.0
          ub = pb[:u] - pb[:s] / 2.0
          next if ub - ua < 0.5
          us = if sd[:mount] == :wange
                 span_even(ua, ub, d, gap)
               else
                 span_treads(plan, p, sd, ua, ub)
               end
          # größter lichter Abstand in diesem Feld (Pfosten – Stäbe – Pfosten)
          edges = [ua] + us.flat_map { |u, _k| [u - d / 2.0, u + d / 2.0] } + [ub]
          edges.each_slice(2) { |a, b| maxgap = [maxgap, b - a].max if b }
          us.each do |u, k|
            bar = { u: u, pt: axis_pt(sd, u), tg: sd[:poly].tangent(u), d: d, tread: k, ztop: rail_z(sd, u) - r }
            if sd[:mount] == :wange
              zt = wange_top(plan, p, sd[:which], u) || (rail_z(sd, u) - p['rail_h'] + p['str_over'])
              bar[:zbot] = zt - p['bal_depth']
              bar[:drill] = { u: u, z: zt, depth: p['bal_depth'], d: d }
            else
              zt = (k + 1) * plan.h
              dep = [p['bal_depth'], [p['tread_t'] - 1.0, 0.0].max].min
              dep = 0.0 if p['construction'] == 'massiv'
              bar[:zbot] = zt - dep
              bar[:drill] = { u: u, z: zt, depth: dep, d: d } if dep > 0
            end
            next if bar[:ztop] - zt < 5.0
            out << bar
          end
        end
        if maxgap > gap + 0.05
          warnings << format('Geländer %s: lichter Abstand bis %.1f cm (höchstens %.1f cm) – Stufen für weitere Stäbe zu schmal ' \
                             '(Mindestabstand zum Stufenrand bzw. Stabquerschnitt verkleinern).',
                             sd[:which] == :outer ? 'außen' : 'innen', maxgap, gap)
        end
        out
      end

      # Gleichmäßige Teilung zwischen ua und ub: lichter Abstand <= gap
      def span_even(ua, ub, d, gap)
        len = ub - ua
        m = ((len - gap) / (gap + d)).ceil
        m = 0 if m < 0
        return [] if m.zero?
        g = (len - m * d) / (m + 1)
        (0...m).map { |j| [ua + g + d / 2.0 + j * (g + d), nil] }
      end

      # Parameter der Stabachse, an dem die Stufenlinie w die Achse schneidet
      # (Achse um |off| nach innen versetzt; schräge Stufenlinien verschieben u)
      def axis_u(plan, sd, w)
        w = [[w, 0.0].max, plan.wtot].min
        # Wendeltreppe: Stufenlinien radial -> kein Versatz
        return sd[:poly].length * w / [plan.wtot, 1e-9].max if plan.spiral
        l = plan.line(w)
        outer = sd[:which] == :outer
        uf = outer ? l[:t] : l[:s]
        dl = outer ? Geo.sub(l[:in], l[:out]) : Geo.sub(l[:out], l[:in]) # nach innen
        return uf if Geo.len(dl) < 1e-9
        dl = Geo.norm(dl)
        tg = sd[:poly].tangent(uf)
        nin = sd[:side] > 0 ? Geo.left(tg) : Geo.right(tg)
        c = Geo.dot(dl, nin)
        return uf if c < 0.2
        uf + (-sd[:off]) * Geo.dot(dl, tg) / c
      end

      # Stäbe auf den Stufen: je Stufe m gleiche Felder, Stab in Feldmitte.
      # Rückgabe [[u, stufe], ...]
      def span_treads(plan, p, sd, ua, ub)
        d = p['bal_d']; gap = p['bal_gap']; e = p['bal_edge']
        lw = plan.lines_w
        res = []
        (0...plan.treads).each do |k|
          a = axis_u(plan, sd, lw[k]); b = axis_u(plan, sd, lw[k + 1])
          len = b - a
          next if len < 2 * e + d
          m = (len / (gap + d)).ceil
          m = [m, (len / (2 * e + d)).floor].min # Mindestabstand zum Stufenrand geht vor
          m = 1 if m < 1
          pitch = len / m
          (0...m).each do |j|
            u = a + (j + 0.5) * pitch
            next if u - d / 2.0 < ua + 0.5 || u + d / 2.0 > ub - 0.5 # nicht in den Pfosten
            res << [u, k]
          end
        end
        res
      end

      # --- Handlauf ---------------------------------------------------------

      # Handlaufstücke von Pfosten zu Pfosten (3D-Polylinien auf der Achse)
      def rails(plan, p, sd)
        out = []
        sd[:posts].each_cons(2) do |pa, pb|
          ua = pa[:u] + pa[:s] / 2.0
          ub = pb[:u] - pb[:s] / 2.0
          next if ub - ua < 1.0
          us = [ua]
          sd[:poly].cum.each { |c| us << c if c > ua + 0.01 && c < ub - 0.01 }
          sd[:keys].each { |c| us << c if c > ua + 0.01 && c < ub - 0.01 }
          us << ub
          us = us.sort.uniq { |u| (u * 100).round }
          path = us.map { |u| q = axis_pt(sd, u); [q[0], q[1], rail_z(sd, u)] }
          out << path
        end
        out
      end
    end
  end
end
