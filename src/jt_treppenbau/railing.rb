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

      # --- Stufen im Pfosten, Verbindungen ------------------------------------
      #
      # Die Stufen (auch Wendel-/Drachenstufen) und Setzstufen laufen um
      # post_pocket in eine gefräste Tasche im Pfosten: der Stufenumriss wird
      # am um post_pocket verkleinerten Pfostenquerschnitt beschnitten
      # (post_pocket = 0: Stufe endet stumpf an der Pfostenfläche). Je Tasche
      # wird die Stufe zusätzlich durch den Pfosten befestigt (tread_fix:
      # Schraube bzw. Dübel von der Gegenseite bis in die Stufenstirn).
      # Wangen und Pfosten werden verdübelt (dowel_d, dowel_depth je Teil).
      # Pfostenflächen: Querschnitt gegen den Uhrzeigersinn, Fläche i von
      # Ecke i nach Ecke i+1; Lage a = Abstand von der linken Kante beim Blick
      # auf die Fläche, z ab Pfostenunterkante.

      # Querschnitt eines Pfostens (gegen den Uhrzeigersinn) mit Kante s
      def post_square(q, s = q[:s])
        ax = q[:tg]; ay = Geo.left(ax); h = s / 2.0
        [[-1, -1], [1, -1], [1, 1], [-1, 1]].map { |i, j| Geo.add(q[:pt], Geo.add(Geo.mul(ax, i * h), Geo.mul(ay, j * h))) }
      end

      # Flächen eines Pfostens: [{ a:, b:, dir:, n: (Außennormale) }]
      def post_faces(q)
        c = post_square(q)
        (0..3).map do |i|
          a = c[i]; b = c[(i + 1) % 4]; d = Geo.norm(Geo.sub(b, a))
          { a: a, b: b, dir: d, n: Geo.right(d) }
        end
      end

      def face_name(sd, q, i)
        n = post_faces(q)[i][:n]
        out = sd[:side] > 0 ? Geo.right(q[:tg]) : Geo.left(q[:tg])
        nm = [[q[:tg], 'aufwärts'], [Geo.mul(q[:tg], -1.0), 'abwärts'], [out, 'außen'], [Geo.mul(out, -1.0), 'zur Treppe']]
             .max_by { |v, _| Geo.dot(v, n) }[1]
        "Fläche #{i + 1} (#{nm})"
      end

      # Pfosten, in die Stufen eingelassen werden (Antritt, Austritt,
      # Laufwechsel; Zwischenpfosten stehen auf Wange bzw. Stufe): [[q, sd]]
      def pocket_posts(plan, p)
        return [] if p['rail'] == 'keins'
        compute(plan, p)[:sides].flat_map { |sd| sd[:posts].map { |q| [q, sd] } }
      end

      # Stufen- bzw. Setzstufenumriss (Grundriss, cm) im Höhenbereich z0..z1 an
      # den Pfosten beschnitten: die Stufe ragt nur durch die Flächen, durch
      # die sie in den Pfosten läuft, um post_pocket hinein (Tasche); an
      # Flächen, mit denen sie bündig abschließt, bleibt nichts im Pfosten.
      def clip_at_posts(plan, p, poly, z0, z1)
        e = [p['post_pocket'].to_f, 0.0].max
        pocket_posts(plan, p).each do |q, _sd|
          next if [z1, q[:ztop]].min - [z0, q[:zbot]].max < 0.1
          faces = post_faces(q)
          ent = (0..3).select { |i| face_intervals(faces[i], poly).any? { |a0, a1| a1 - a0 >= 0.3 } }
          next if ent.empty?
          cut = cut_rect(q, ent, e)
          next unless cut
          if ent.size == 4 && post_square(q).all? { |c| inside_poly?(poly, c) }
            # Pfosten mitten in der Stufe bzw. im Podest: Durchbruch, kein Umriss
            w = format('Geländerpfosten (%s) durchdringt %s bei Höhe %.1f cm – Ausschnitt %.1f × %.1f cm von Hand.',
                       q[:role], z1 - z0 > p['tread_t'] + 0.5 ? 'eine Setzstufe' : 'eine Stufe bzw. ein Podest', z1, q[:s], q[:s])
            ws = compute(plan, p)[:warnings]
            ws << w unless ws.include?(w)
            next
          end
          r = Geo.subtract_convex(poly, cut)
          return r if r.size < 3
          poly = r if Geo.signed_area(r).abs < Geo.signed_area(poly).abs - 1e-6
        end
        poly
      end

      # Pfostenquerschnitt ohne die Taschen (an den Flächen ent um e
      # zurückgesetzt) – das wird aus der Stufe ausgeschnitten
      def cut_rect(q, ent, e)
        h = q[:s] / 2.0
        # übrige Flächen minimal überstehend (bündige Stufenkanten sauber schneiden)
        g = 0.05
        y0 = ent.include?(0) ? -h + e : -h - g
        x1 = ent.include?(1) ? h - e : h + g
        y1 = ent.include?(2) ? h - e : h + g
        x0 = ent.include?(3) ? -h + e : -h - g
        return nil if x1 - x0 < 0.1 || y1 - y0 < 0.1
        ax = q[:tg]; ay = Geo.left(ax)
        [[x0, y0], [x1, y0], [x1, y1], [x0, y1]].map { |x, y| Geo.add(q[:pt], Geo.add(Geo.mul(ax, x), Geo.mul(ay, y))) }
      end

      def inside_poly?(poly, q)
        c = false
        poly.each_with_index do |a, i|
          b = poly[i - 1]
          c = !c if (a[1] > q[1]) != (b[1] > q[1]) && q[0] < (b[0] - a[0]) * (q[1] - a[1]) / (b[1] - a[1]) + a[0]
        end
        c
      end

      # Abschnitte [a0, a1] einer Pfostenfläche, durch die der Umriss poly in
      # den Pfosten läuft (Prüfung knapp vor der Fläche)
      def face_intervals(f, poly, off = 0.05)
        a = Geo.add(f[:a], Geo.mul(f[:n], off)); b = Geo.add(f[:b], Geo.mul(f[:n], off))
        d = Geo.sub(b, a); l = Geo.len(d)
        ts = [0.0, 1.0]
        poly.each_with_index do |p1, i|
          e = Geo.sub(poly[(i + 1) % poly.size], p1)
          den = Geo.cross(d, e)
          next if den.abs < 1e-12
          w = Geo.sub(p1, a)
          t = Geo.cross(w, e) / den
          v = Geo.cross(w, d) / den
          ts << t if t > 0 && t < 1 && v >= -1e-9 && v <= 1 + 1e-9
        end
        res = []
        ts.sort.each_cons(2) do |t0, t1|
          next if t1 - t0 < 1e-6 || !inside_poly?(poly, Geo.lerp(a, b, (t0 + t1) / 2.0))
          if res.any? && (res[-1][1] - t0 * l).abs < 1e-6
            res[-1][1] = t1 * l
          else
            res << [t0 * l, t1 * l]
          end
        end
        res
      end

      # Taschen und Befestigungsbohrungen der Pfosten.
      # items: [[Umriss (beschnitten, Grundriss cm), z0, z1, Name]] (Tritt- und
      # Setzstufen). Liefert { q.object_id => { q:, sd:, pockets: [], holes: [] } }
      #   Tasche:  { face:, a0:, a1:, z0:, z1:, depth:, name: }
      #   Bohrung: { face:, a:, z:, d:, depth:, what: } (depth bis Taschengrund
      #            bzw. Bohrtiefe; rechtwinklig zur Fläche)
      def post_joinery(plan, p, items)
        e = [p['post_pocket'].to_f, 0.0].max
        res = {}
        pocket_posts(plan, p).each do |q, sd|
          ent = res[q.object_id] = { q: q, sd: sd, pockets: [], holes: [] }
          s = q[:s]
          faces = post_faces(q)
          items.each do |poly, z0, z1, name|
            next if poly.size < 3 || [z1, q[:ztop]].min - [z0, q[:zbot]].max < 0.1
            next if post_square(q).all? { |c| inside_poly?(poly, c) } # Durchbruch (Warnung)
            zb = [z0, q[:zbot]].max - q[:zbot]; zt = [z1, q[:ztop]].min - q[:zbot]
            mine = []
            faces.each_with_index do |f, i|
              face_intervals(f, poly).each do |a0, a1|
                next if a1 - a0 < 0.3
                mine << { face: i, a0: a0, a1: a1, z0: zb, z1: zt, depth: e, name: name }
              end
            end
            ent[:pockets].concat(mine)
            fix = tread_fix(p)
            next unless fix && e > 0 && name.start_with?('Stufe', 'Podest') && zt - zb >= fix[:d] + 1.0
            # eine Befestigung je Stufe und Pfosten: an der breitesten Tasche,
            # von der Gegenfläche durch den Pfosten bis in die Stufenstirn
            t = mine.max_by { |x| x[:a1] - x[:a0] }
            next unless t && t[:a1] - t[:a0] >= 2.0 * fix[:d]
            ent[:holes] << { face: (t[:face] + 2) % 4, a: s - (t[:a0] + t[:a1]) / 2.0, z: (zb + zt) / 2.0, d: fix[:d],
                             depth: s - e, what: "#{fix[:what]} #{name}", into: fix[:into] }
          end
        end
        Stringers.compute(plan, p)[:wange].each do |b|
          [[:post0, false], [:post1, true]].each do |key, at_end|
            ref = b[key]
            next unless ref
            ent = res.values.find { |x| x[:sd][:which] == b[:which] && x[:q][:role] == ref[:role] && (x[:q][:u] - ref[:u]).abs < 0.05 }
            next unless ent
            add_dowel_holes(ent, wange_end_pt(b, at_end, p['str_t'].to_f), at_end ? b[:dir] : Geo.mul(b[:dir], -1.0),
                            wange_dowels(plan, p, b, at_end), p, "Wange #{b[:which] == :outer ? 'außen' : 'innen'}")
          end
        end
        Stringers.compute(plan, p)[:sattel].each do |sb|
          [[:post0, false], [:post1, true]].each do |key, at_end|
            ref = sb[key]
            next unless ref
            ent = res.values.find { |x| x[:sd][:which] == sb[:which] && x[:q][:role] == ref }
            next unless ent
            pt = at_end ? Geo.add(sb[:origin], Geo.mul(sb[:dir], sb[:len])) : sb[:origin]
            add_dowel_holes(ent, pt, at_end ? sb[:dir] : Geo.mul(sb[:dir], -1.0), sattel_dowels(p, sb, at_end), p,
                            "aufgesattelte Wange #{sb[:which] == :outer ? 'außen' : 'innen'} #{sb[:nr]}")
          end
        end
        res
      end

      # Befestigung der Stufe am Pfosten: { d:, what:, into: (Tiefe in die Stufe) } | nil
      def tread_fix(p)
        case p['tread_fix']
        when 'schraube' then { d: p['tread_fix_d'].to_f, what: 'Schraube', into: 0.0 }
        when 'duebel' then p['dowel_d'].to_f > 0 ? { d: p['dowel_d'].to_f, what: 'Dübel', into: p['dowel_depth'].to_f } : nil
        end
      end

      # Dübelbohrungen im Pfosten gegenüber einem Wangenende (pt: Wangenmitte
      # am Ende, dir: Richtung in den Pfosten)
      def add_dowel_holes(ent, pt, dir, zs, p, name)
        return if zs.empty?
        q = ent[:q]
        faces = post_faces(q)
        i = (0..3).min_by { |j| Geo.dot(faces[j][:n], dir) }
        a = Geo.dot(Geo.sub(pt, faces[i][:a]), faces[i][:dir])
        zs.each do |z|
          ent[:holes] << { face: i, a: a, z: z - q[:zbot], d: p['dowel_d'].to_f, depth: p['dowel_depth'].to_f,
                           what: "Dübel #{name}" }
        end
      end

      # Mitte der eingestemmten Wange am Brettanfang bzw. -ende (Grundriss)
      def wange_end_pt(b, at_end, t)
        base = at_end ? b[:base][-1] : b[:base][0]
        Geo.add(base, Geo.mul(Stringers.seg_n(b, b[:side]), t / 2.0))
      end

      # Höhen der Dübel (absolut, cm) zwischen lo und hi, außerhalb der Zonen bad
      def dowel_zs(lo, hi, bad, d)
        return [] if hi < lo
        ok = ->(z) { z >= lo - 1e-6 && z <= hi + 1e-6 && bad.none? { |a, c| z > a && z < c } }
        n = hi - lo < 3.0 * d ? 1 : [[((hi - lo) / 12.0).floor + 1, 2].max, 4].min
        want = n == 1 ? [(lo + hi) / 2.0] : (0...n).map { |i| lo + (hi - lo) * i / (n - 1) }
        cand = (0..((hi - lo) / 0.5).floor).map { |j| lo + j * 0.5 } + [hi]
        zs = []
        want.each do |z|
          c = cand.select(&ok).min_by { |x| (x - z).abs }
          zs << c if c && zs.none? { |x| (x - c).abs < 3.0 * d }
        end
        zs.sort
      end

      # Dübel am Ende eines eingestemmten Wangenbretts (Höhen absolut, cm):
      # ganz im Brett (Rand max(2 Ø, 3 cm) auf der ganzen Bohrtiefe), nicht in
      # den Nuten der Tritt- und Setzstufen
      def wange_dowels(plan, p, b, at_end)
        d = p['dowel_d'].to_f; dep = p['dowel_depth'].to_f
        return [] if d <= 0 || dep <= 0
        u = at_end ? b[:u1] : b[:u0]
        u2 = at_end ? [u - dep, b[:u0]].max : [u + dep, b[:u1]].min
        mrg = [2.0 * d, 3.0].max
        lo = [u, u2].map { |x| [Stringers.bot(b, x), 0.0].max }.max + mrg
        hi = [u, u2].map { |x| Stringers.top(b, x) }.min - mrg
        bad = groove_zones(plan, p, b[:which], [u, u2].min - 1.0, [u, u2].max + 1.0)
              .map { |z0, z1| [z0 - d / 2.0 - 0.5, z1 + d / 2.0 + 0.5] }
        dowel_zs(lo, hi, bad, d)
      end

      # Dübel am Ende einer aufgesattelten Wange (Höhen absolut, cm)
      def sattel_dowels(p, sb, at_end)
        d = p['dowel_d'].to_f; dep = p['dowel_depth'].to_f
        return [] if d <= 0 || dep <= 0
        x = at_end ? sb[:len] : 0.0
        x2 = at_end ? [sb[:len] - dep, 0.0].max : [dep, sb[:len]].min
        zr = [x, x2].map do |xx|
          zs = []
          sb[:poly].each_with_index do |a, i|
            c = sb[:poly][i - 1]
            if (a[0] - c[0]).abs < 1e-9
              zs.push(a[1], c[1]) if (a[0] - xx).abs < 1e-6
            elsif (a[0] - xx) * (c[0] - xx) <= 0
              zs << a[1] + (xx - a[0]) / (c[0] - a[0]) * (c[1] - a[1])
            end
          end
          zs.minmax
        end
        return [] if zr.any? { |lo, _| lo.nil? }
        mrg = [2.0 * d, 3.0].max
        dowel_zs(zr.map(&:first).max + mrg, zr.map(&:last).min - mrg, [], d)
      end

      # Höhenbereiche der Stufennuten einer Wangenseite im Bereich ua..ub (u)
      def groove_zones(plan, p, which, ua, ub)
        keys = plan.keys_for(which)
        d = p['tread_t']; nos = p['nosing']; ts = p['riser_t']
        ext = nos + (p['risers'] ? ts : 0.0)
        res = []
        (0...plan.treads).each do |k|
          top = (k + 1) * plan.h
          res << [top - d, top] if keys[k] - 0.01 < ub && keys[k + 1] + ext + 0.01 > ua
          res << [k * plan.h, top - d] if p['risers'] && keys[k] + nos < ub && keys[k] + nos + ts > ua
        end
        res
      end
    end
  end
end
