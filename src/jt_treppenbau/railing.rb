# encoding: UTF-8
# Treppenbau – Geländerplanung (ohne SketchUp-API, testbar).
#
# Regeln (erster Entwurf):
#   * Pfosten am Antritt, am Austritt und an jedem Laufwechsel: an jeder Ecke
#     der Begrenzung (L: eine Ecke, U mit Treppenauge innen: zwei Ecken mit
#     Querstück) bzw. bei geraden Zwischenpodesten an der Podestvorderkante.
#   * Der Handlauf läuft von Pfosten zu Pfosten (stößt an die Pfosten).
#     Querschnitt rechteckig: Breite = Wangendicke (eingestemmt str_t,
#     aufgesattelt sat_t, sonst rail_d), Höhe rail_hh; Oberkante rail_h über
#     den Stufenvorderkanten. Wangenform „gerade“: je Feld eine Gerade (die
#     niedrigste über allen Stufenkanten), „geschwungen“: knickfreie Kurve
#     durch die Stufenkanten (wie die Wange) – dann wird der Handlauf als
#     Platte aus dem Vollen gefräst (Teil mit gekrümmtem Umriss).
#     An Eckpfosten endet der Handlauf an der Pfostenfläche (die Achse ist
#     gegen die Begrenzung versetzt, daher nicht einfach u ± newel_s/2).
#   * Pfosten am Antritt/Austritt: bei eingestemmter und aufgesattelter Wange
#     innerhalb der Treppe (Wange stößt an den Pfosten), sonst davor/dahinter.
#   * Zwischenpfosten: Feld zwischen zwei Pfosten im Grundriss länger als
#     rail_mid -> Pfosten in der Mitte (an der Stelle des mittleren Stabs),
#     UNTER dem Handlauf (Handlauf läuft durch); steht auf der Wange bzw. Stufe.
#   * Stäbe zwischen den Pfosten, lichter Abstand höchstens bal_gap; quadratisch
#     (Kantenlänge bal_d) oder rund (Durchmesser bal_dia), Bohrung Ø = Stabmaß.
#     Lage im Stufenraster: je Stufe wird die Stufentiefe (auf der Stabachse,
#     von Vorderkante zu Vorderkante der nächsten Stufe) in m gleiche Felder
#     geteilt, der Stab steht in Feldmitte – bei gleich tiefen Stufen ein
#     durchgehend gleicher Stababstand, jede Stufe gleich besetzt.
#       eingestemmte Wange – jeder Stab steht lotrecht auf der Wangenoberkante
#         und ist um bal_depth eingelassen (lotrechte Bohrung, d. h. schräg zur
#         Wangenkante).
#       aufgesattelte Wange, freitragend, Holm, Massiv – die Stäbe stehen auf
#         den Stufen, jeder Stab hält mindestens bal_edge Abstand zu beiden
#         Stufenkanten.
#     Oben sind die Stäbe lotrecht in den Handlauf gebohrt (Tiefe bal_depth,
#     höchstens Handlaufhöhe − 1 cm, gemessen ab Unterkante in Stabmitte).
#     Wo neben Pfosten eine Lücke > bal_gap bleibt, wird sie aufgefüllt.
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
      #                bars: [...], rails: [...] } ], warnings: [] }
      #   Handlauf (je Feld zwischen zwei Pfosten):
      #     { ua:, ub:, w:, h:, curved:, us: [...], pts: [[x, y], ...] (Achse),
      #       tops: [...], bots: [...] }
      #     drills: [{ u:, pt:, z:, depth:, d: }] (lotrecht von unten, z = Unterkante)
      #   Pfosten: { u:, pt:, tg:, s:, zbot:, ztop:, role: :antritt | :austritt | :ecke | :podest }
      #   Zwischenpfosten (mids): wie Pfosten, role: :mitte
      #   Stab:    { u:, pt:, tg:, d:, shape: 'rund' | 'quadrat', zbot:, ztop:, tread: k | nil,
      #              drill: { u:, z:, depth:, d: } }   (Bohrung in Wange bzw. Stufe,
      #              Ø = Durchmesser bzw. Kantenlänge)
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
        sd[:rw] = case Params.side_kind(p, which, plan.outer_side, !plan.spiral.nil?)
                  when 'wange' then p['str_t']
                  when 'sattel' then p['sat_t']
                  else p['rail_d']
                  end
        inside = %w[wange sattel].include?(Params.side_kind(p, which, plan.outer_side, !plan.spiral.nil?))
        sd[:posts] = post_positions(plan, p, which, keys, inside)
        sd[:posts].each { |q| frame(sd, q, p['newel_s']) }
        sd[:spans] = spans(plan, p, sd)
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

      # Handlauf-Oberkante je Feld zwischen zwei Pfosten (Lambda u -> z)
      def spans(plan, p, sd)
        curved = p['str_form'] == 'kurve'
        sd[:posts].each_cons(2).map do |pa, pb|
          ua = face_u(sd, pa, 1)
          ub = face_u(sd, pb, -1)
          pts = [[ua, rail_z(sd, ua)]]
          sd[:keys].each_with_index { |k, i| pts << [k, sd[:zs][i]] if k > ua + 0.01 && k < ub - 0.01 }
          pts << [ub, rail_z(sd, ub)]
          # gleiche u (Innenecke): höchster Wert
          pts = pts.group_by { |u, _| (u * 100).round }.map { |_, g| [g[0][0], g.map(&:last).max] }.sort_by(&:first)
          f = if pts.size < 2
                z0 = pts[0][1]
                ->(_u) { z0 }
              elsif curved
                Stringers.pchip(pts)
              else
                c, sl = Stringers.top_line(pts)
                ->(u) { c + sl * u }
              end
          { ua: ua, ub: ub, f: f, pts: pts, pa: pa, pb: pb }
        end
      end

      # Lage (Mittelpunkt, Ausrichtung) eines Pfostens
      def frame(sd, q, s)
        poly = sd[:poly]
        u = q[:u]
        q[:s] = s
        q[:pt] = axis_pt(sd, u)
        # an der Ecke nach dem ankommenden Lauf ausgerichtet
        q[:tg] = q[:role] == :ecke ? poly.tangent(u - 0.01) : poly.tangent([[u, 0.01].max, poly.length - 0.01].min)
      end

      # Achse eines Laufs (Schenkel) an einer Ecke, geradlinig über die Ecke
      # hinaus verlängert: dir = -1 ankommender, +1 abgehender Lauf
      def leg_pt(sd, q, u, dir)
        poly = sd[:poly]
        tg = poly.tangent(q[:u] + dir * 0.01)
        nrm = sd[:side] > 0 ? Geo.right(tg) : Geo.left(tg)
        c = Geo.add(poly.at(q[:u]), Geo.mul(nrm, sd[:off]))
        Geo.add(c, Geo.mul(tg, u - q[:u]))
      end

      # Parameter u, an dem die Achse die Pfostenfläche erreicht (dir = +1
      # Fläche zum folgenden Feld, -1 zum vorigen). An Ecken liegt die
      # Pfostenmitte im Schnitt der versetzten Achsen – der Wert kann dann auf
      # der verlängerten Achse des Schenkels hinter der Ecke liegen (leg_pt).
      def face_u(sd, q, dir)
        u = q[:u]; hs = q[:s] / 2.0
        return u + dir * hs unless q[:role] == :ecke
        tg = sd[:poly].tangent(u + dir * 0.01)
        ax = q[:tg]; ay = Geo.left(ax)
        dface = hs / [Geo.dot(tg, ax).abs, Geo.dot(tg, ay).abs, 0.3].max
        u + dir * dface - Geo.dot(Geo.sub(leg_pt(sd, q, u, dir), q[:pt]), tg)
      end

      # Achsenpunkt eines Felds (an Eckpfosten auf dem verlängerten Schenkel)
      def span_pt(sd, sp, u)
        pa = sp[:pa]; pb = sp[:pb]
        return leg_pt(sd, pa, u, 1) if pa && pa[:role] == :ecke && u <= pa[:u] + 0.01
        return leg_pt(sd, pb, u, -1) if pb && pb[:role] == :ecke && u >= pb[:u] - 0.01
        axis_pt(sd, u)
      end

      # liegt der Punkt (mit Abstand clr) im Querschnitt eines Pfostens?
      def in_post?(list, pt, clr)
        list.any? do |q|
          d = Geo.sub(pt, q[:pt]); ax = q[:tg]; ay = Geo.left(ax); h = q[:s] / 2.0 + clr
          Geo.dot(d, ax).abs < h && Geo.dot(d, ay).abs < h
        end
      end

      # Handlauf-Unterkante an u (höchster Wert im Bereich u ± r)
      def rail_bot_max(sd, p, u, r)
        [u - r, u, u + r].map { |x| rail_top(sd, x) }.max - p['rail_hh']
      end

      # Oberkante Handlauf an u (Feld, in dem u liegt; sonst Stufenkanten)
      def rail_top(sd, u)
        sp = (sd[:spans] || []).find { |x| u >= x[:ua] - 1e-6 && u <= x[:ub] + 1e-6 }
        sp ? sp[:f].(u) : rail_z(sd, u)
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

      # Unterkante der aufgesattelten Wange am Austritt (Ende des letzten
      # Bretts, dort stößt sie an den Austrittspfosten)
      def sattel_bot_end(plan, p, which)
        b = Stringers.compute(plan, p)[:sattel].select { |x| x[:which] == which }.max_by { |x| x[:nr] }
        return nil unless b
        zs = b[:poly].select { |x, _| x >= b[:len] - 0.01 }.map(&:last)
        zs.empty? ? nil : [zs.min, 0.0].max
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
        wange = %w[wange sattel].include?(Params.side_kind(p, which, plan.outer_side, !plan.spiral.nil?)) if wange.nil?
        u0 = keys[0]; u1 = keys[-1]
        list = []
        # Antritt / Austritt: bei Wangen (eingestemmt, aufgesattelt) innerhalb
        # der Treppe (Wange stößt an den Pfosten), sonst vor der ersten bzw.
        # hinter der letzten Stufenkante
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
        keys = sd[:keys]
        wange = sd[:mount] == :wange
        list = sd[:posts]
        sattel = Params.side_kind(p, sd[:which], plan.outer_side, !plan.spiral.nil?) == 'sattel'
        list.each_with_index do |q, i|
          u = q[:u]
          # über die Oberkante der anschließenden Handläufe
          zr = []
          zr << sd[:spans][i - 1][:f].(sd[:spans][i - 1][:ub]) if i > 0 && sd[:spans][i - 1]
          zr << sd[:spans][i][:f].(sd[:spans][i][:ua]) if sd[:spans][i]
          q[:ztop] = (zr.max || rail_z(sd, u)) + POST_CAP
          q[:zbot] = if wange
                       q[:role] == :antritt ? 0.0 : [(wange_bot(plan, p, sd[:which], u) || 0.0), 0.0].max
                     elsif q[:role] == :antritt
                       0.0
                     elsif q[:role] == :austritt
                       sattel ? (sattel_bot_end(plan, p, sd[:which]) || plan.H) : plan.H
                     else
                       tread_top(plan, keys, u)
                     end
        end
        list
      end

      # --- Stäbe ------------------------------------------------------------

      def bars(plan, p, sd, warnings)
        shape, d = Params.bar_size(p)
        gap = p['bal_gap']
        d = 0.0 if gap <= 0
        s = p['newel_s']
        mid_len = p['rail_mid'].to_f
        lw = plan.lines_w
        sd[:tb] = (0..plan.treads).map { |k| axis_u(plan, sd, lw[k]) }
        sd[:mids] = []
        out = []
        maxgap = 0.0
        sd[:spans].each do |sp|
          ua = sp[:ua]; ub = sp[:ub]
          next if ub - ua < 0.5
          us = d > 0 ? span_treads(plan, p, sd, ua, ub) : []
          us.reject! { |u, _k| in_post?(sd[:posts], axis_pt(sd, u), d / 2.0 + 0.5) }
          # Zwischenpfosten in der Mitte (an der Stelle des mittleren Stabs)
          if mid_len > 0 && ub - ua > mid_len + 1e-6
            um = (ua + ub) / 2.0
            c = us.min_by { |u, _k| (u - um).abs }
            c = nil if c && (c[0] - um).abs > [ub - ua, 0.0].max / 4.0
            mu = c ? c[0] : um
            mk = c ? c[1] : tread_at(sd, mu)
            sd[:mids] << mid_post(plan, p, sd, mu, mk, s)
            us.reject! { |u, _k| (u - mu).abs < s / 2.0 + d / 2.0 + 0.5 }
          end
          # Lücken neben Pfosten über bal_gap auffüllen
          if d > 0
            blocks = lambda do
              ([[ua - 1.0, ua]] + sd[:mids].select { |q| q[:u] > ua && q[:u] < ub }.map { |q| [q[:u] - s / 2.0, q[:u] + s / 2.0] } +
               us.map { |u, _k| [u - d / 2.0, u + d / 2.0] } + [[ub, ub + 1.0]]).sort_by(&:first)
            end
            blocks.().each_cons(2) do |(_, ha), (lb, _)|
              free = lb - ha
              next unless free > gap + 0.05
              span_even(ha, lb, d, gap).each do |u, _|
                k = tread_at(sd, u)
                ok = if sd[:mount] == :wange
                       wange_top(plan, p, sd[:which], u)
                     else
                       e = p['bal_edge']
                       k && u - d / 2.0 - sd[:tb][k] >= e - 1e-6 && sd[:tb][k + 1] - u - d / 2.0 >= e - 1e-6
                     end
                us << [u, k] if ok && !in_post?(sd[:posts], axis_pt(sd, u), d / 2.0 + 0.5)
              end
            end
            us.sort_by!(&:first)
            # größter lichter Abstand in diesem Feld (Pfosten – Stäbe – Pfosten)
            blocks.().each_cons(2) { |(_, ha), (lb, _)| maxgap = [maxgap, lb - ha].max }
          end
          us.each do |u, k|
            bar = { u: u, pt: axis_pt(sd, u), tg: sd[:poly].tangent(u), d: d, shape: shape, tread: k }
            if sd[:mount] == :wange
              zt = wange_top(plan, p, sd[:which], u) || (rail_z(sd, u) - p['rail_h'] + p['str_over'])
              bar[:zbot] = zt - p['bal_depth']
              bar[:drill] = { u: u, z: zt, depth: p['bal_depth'], d: d }
            else
              next unless k
              zt = (k + 1) * plan.h
              dep = [p['bal_depth'], [p['tread_t'] - 1.0, 0.0].max].min
              dep = 0.0 if p['construction'] == 'massiv'
              bar[:zbot] = zt - dep
              bar[:drill] = { u: u, z: zt, depth: dep, d: d } if dep > 0
            end
            # oben lotrecht in den Handlauf gebohrt
            zr = rail_top(sd, u) - p['rail_hh']
            rd = [p['bal_depth'], p['rail_hh'] - 1.0].min
            rd = 0.0 if rd < 0
            bar[:ztop] = zr + rd
            bar[:rdrill] = { u: u, z: zr, depth: rd, d: d } if rd > 0
            next if zr - zt < 5.0
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

      # Stufe (Index), auf der die Stelle u der Achse liegt (nil = keine)
      def tread_at(sd, u)
        tb = sd[:tb]
        (0...tb.size - 1).find { |k| u >= tb[k] - 1e-6 && u <= tb[k + 1] + 1e-6 && tb[k + 1] - tb[k] > 0.05 }
      end

      # Zwischenpfosten an u: steht auf der Wangenoberkante (eingestemmt) bzw.
      # auf der Stufe, endet an der Handlauf-Unterkante (Handlauf läuft durch).
      # Pfostenenden schräg nach der Neigung – hier bis zur höchsten Stelle.
      def mid_post(plan, p, sd, u, k, s)
        q = { u: u, role: :mitte }
        frame(sd, q, s)
        q[:zbot] = if sd[:mount] == :wange
                     [u - s / 2.0, u, u + s / 2.0].map { |x| wange_top(plan, p, sd[:which], x) }.compact.min ||
                       (rail_z(sd, u) - p['rail_h'] + p['str_over'])
                   else
                     k ? (k + 1) * plan.h : tread_top(plan, sd[:keys], u)
                   end
        q[:ztop] = rail_bot_max(sd, p, u, s / 2.0)
        q
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

      # Stäbe im Stufenraster: je Stufe m gleiche Felder, Stab in Feldmitte.
      # Rückgabe [[u, stufe], ...]
      def span_treads(plan, p, sd, ua, ub)
        d = Params.bar_size(p)[1]; gap = p['bal_gap']
        e = sd[:mount] == :wange ? 0.0 : p['bal_edge'] # auf der Wange: kein Stufenrand
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

      # Handlaufstücke von Pfosten zu Pfosten; Bohrungen für die Stäbe
      # (lotrecht von unten, Ansatz an der Unterkante in Stabmitte)
      def rails(plan, p, sd)
        curved = p['str_form'] == 'kurve'
        h = p['rail_hh']
        sd[:spans].map do |sp|
          ua = sp[:ua]; ub = sp[:ub]
          next nil if ub - ua < 1.0
          # Zwischenpunkte nur zwischen den Pfosten (nicht im Eckpfosten)
          lo = [ua, sp[:pa][:u]].max + 0.01; hi = [ub, sp[:pb][:u]].min - 0.01
          us = [ua]
          sd[:poly].cum.each { |c| us << c if c > lo && c < hi }
          sd[:keys].each { |c| us << c if c > lo && c < hi }
          if curved
            n = [((ub - ua) / 5.0).ceil, 2].max
            (1...n).each { |i| u = ua + (ub - ua) * i / n; us << u if u > lo && u < hi }
          end
          us << ub
          us = us.sort.uniq { |u| (u * 100).round }
          tops = us.map { |u| sp[:f].(u) }
          drills = sd[:bars].select { |b| b[:rdrill] && b[:u] > ua && b[:u] < ub }
                            .map { |b| b[:rdrill].merge(pt: b[:pt]) }
          { ua: ua, ub: ub, w: sd[:rw], h: h, curved: curved, us: us,
            pts: us.map { |u| span_pt(sd, sp, u) }, tops: tops, bots: tops.map { |z| z - h }, drills: drills }
        end.compact
      end
    end
  end
end
