# encoding: UTF-8
# Treppenbau – Treppe in einen vorgegebenen Raum einpassen (ohne Luft).
#
# Raum (Draufsicht, x quer, y in Laufrichtung des Antritts):
#   hintere Wand  y = L (Raumlänge), von x = 0 (Ecke links) bis x = W (Raumbreite)
#   linke Wand    durch (0, L), Innenwinkel zur hinteren Wand = angle_left
#   rechte Wand   durch (W, L), Innenwinkel = angle_right
#   vorn          y = 0 (offen, Ende des verfügbaren Platzes)
# Die Treppe liegt an jeder vorhandenen Wand genau mit dem Spiel (wall_gap) an,
# ohne weitere Luft. Grenzen ohne Wand gelten als Platzgrenze (Abstand 0).
#   gerade        zwischen zwei Wänden: Laufbreite füllt (ggf. konisch)
#   L             Lauf 1 an der Außenwand, Lauf 2 an der hinteren Wand
#   U / dreiläufig Läufe an linker und rechter Wand, Wendelung/Podest an der hinteren;
#                 Laufbreite aus Raumbreite und Treppenauge
# Austritt: an der Wand (gerade: hinten, L: Seitenwand) bzw. an der Kante des
# Treppenlochs. Antritt: frei (aus Schrittmaß) oder fest (Abstand von hinten).
# Gerechnet wird in einem kanonischen Rahmen (Außenseite links = rechtsgewendelt);
# linksgewendelte Treppen werden gespiegelt.

module JTools
  module Treppenbau
    module Fit
      module_function

      TOL = 0.05

      def active?(p)
        p['fit_mode'] == 'raum'
      end

      # Breite einer Seite außerhalb der Laufbreite (nur eingestemmte Wange)
      def side_t(p, which, outer_side, spiral = false)
        Params.side_kind(p, which, outer_side, spiral) == 'wange' ? p['str_t'].to_f : 0.0
      end

      # Grundrisspunkte inkl. Wangen
      def footprint_pts(plan, p)
        pts = []
        [[:outer, plan.outer_side], [:inner, -plan.outer_side]].each do |which, side|
          pl = plan.send(which).pts
          pts.concat(pl)
          t = side_t(p, which, plan.outer_side, !plan.spiral.nil?)
          next unless t > 0 && pl.size >= 2
          mn = Geo.miter_normals(pl, side)
          pl.each_with_index { |q, i| pts << Geo.add(q, Geo.mul(mn[i], t)) }
        end
        pts
      end

      def footprint(plan, p)
        if plan.spiral
          r = plan.spiral[:ro]
          return [-r, -r, r, r]
        end
        pts = footprint_pts(plan, p)
        xs = pts.map(&:first); ys = pts.map(&:last)
        [xs.min, ys.min, xs.max, ys.max]
      end

      def solve(p)
        sw = p['space_w'].to_f
        sl = p['space_l'].to_f
        raise PlanError, 'Bitte Raumlänge und Raumbreite angeben.' if sw <= 0 || sl <= 0
        base = p.merge('fit_mode' => 'aus', '_fast' => true)
        plan = if Params::SPIRAL.include?(p['variant'])
                 solve_spiral(base, p, sw, sl)
               else
                 Room.new(p).solve
               end
        plan.params = p
        plan
      end

      # --- Wendeltreppe -------------------------------------------------------
      def solve_spiral(base, p, sw, sl)
        g = ->(k) { p["wall_#{k}"] ? p['wall_gap'].to_f : 0.0 }
        d = [sw - g.('left') - g.('right'), sl - g.('back')].min.floor
        raise PlanError, "Raum zu klein für eine Wendeltreppe (Durchmesser nur #{d} cm)." if d < 100
        plan = Layout.compute(base.merge('D_out' => d.to_f))
        r = d / 2.0
        # Kreis an die hintere Wand (bzw. Grenze) und mittig zwischen die Seiten
        cx = g.('left') + (sw - g.('left') - g.('right')) / 2.0
        cy = sl - g.('back') - r
        poly = [[-cx, -cy], [-cx, sl - cy], [sw - cx, sl - cy], [sw - cx, -cy]]
        plan.space = { poly: poly, loch: nil, walls: walls(p) }
        plan.info.unshift(['Eingepasst: Außendurchmesser', format('%.0f cm', d)])
        if (p['angle_left'].to_f - 90).abs > 0.01 || (p['angle_right'].to_f - 90).abs > 0.01
          plan.warnings << 'Wendeltreppe: schräge Wände werden beim Einpassen nicht berücksichtigt (rechteckiger Raum angenommen).'
        end
        plan
      end

      def walls(p)
        { left: p['wall_left'], right: p['wall_right'], back: p['wall_back'] }
      end

      # --- Freie Planung mit Grundmaß (Gesamtbreite / Gesamttiefe) -------------
      # Die Treppe wird wie in einen Raum mit drei Wänden ohne Spiel eingepasst:
      # Breite = Abstand linke–rechte Wand, Tiefe = fester Antritt (vorderste
      # Stufenkante bis Rückseite). Fehlt ein Maß, ergibt es sich wie bisher aus
      # den Parametern. Ursprung = vordere linke Ecke des Grundmaßes.
      BOX_FREE_L = 5000.0

      def box_active?(p)
        p['fit_mode'] != 'raum' && !Params::SPIRAL.include?(p['variant']) &&
          (p['total_w'].to_f > 0 || p['total_l'].to_f > 0)
      end

      def solve_box(p)
        tw = p['total_w'].to_f
        tl = p['total_l'].to_f
        if tw <= 0
          nat = Layout.compute(p.merge('total_w' => 0.0, 'total_l' => 0.0))
          x0, _y0, x1, _y1 = footprint(nat, p)
          tw = x1 - x0
        end
        q = p.merge('fit_mode' => 'raum', 'space_w' => tw, 'wall_left' => true, 'wall_right' => true,
                    'wall_back' => true, 'wall_gap' => 0.0, 'angle_left' => 90.0, 'angle_right' => 90.0,
                    'loch' => false, 'eye_z' => 0.0, '_box' => true)
        if tl <= 0
          # Tiefe frei: Antritt aus dem Steigungsverhältnis, danach mit dem
          # gefundenen Antritt und der tatsächlichen Tiefe exakt neu rechnen
          pl = box_room(q.merge('space_l' => BOX_FREE_L, 'antritt_l' => 0.0))
          l0 = pl.line(0.0)
          y_ant = [l0[:in][1], l0[:out][1]].min
          y_min = [footprint(pl, p)[1], y_ant].min
          tl = BOX_FREE_L - y_min
          plan = box_room(q.merge('space_l' => tl, 'antritt_l' => BOX_FREE_L - y_ant))
        else
          plan = box_room(q.merge('space_l' => tl, 'antritt_l' => tl))
        end
        box_report(plan, p, tw, tl)
        plan.space = { poly: [[0.0, 0.0], [0.0, tl], [tw, tl], [tw, 0.0]], loch: nil,
                       walls: { left: false, right: false, back: false }, box: true, label: 'Grundmaß' }
        plan.params = p
        plan
      end

      def box_room(q)
        Room.new(q).solve
      rescue PlanError => e
        raise PlanError, box_msg(e.message)
      end

      def box_msg(m)
        m.gsub('nicht in den Raum', 'nicht in das Grundmaß (Gesamtbreite × Gesamttiefe)')
         .gsub('Raumlänge', 'Gesamttiefe').gsub('Raumbreite', 'Gesamtbreite')
         .gsub('über eine Wand bzw. Raumgrenze', 'über das Grundmaß hinaus')
         .gsub('Raum zu schmal', 'Gesamtbreite zu schmal').gsub('Treppenloch bzw. Raum', 'Grundmaß')
         .gsub('Raumgeometrie', 'Geometrie').gsub('dem Raum', 'dem Grundmaß').gsub('den Raum', 'das Grundmaß')
      end

      # Raumbezogene Angaben durch Grundmaß-Angaben ersetzen
      def box_report(plan, p, tw, tl)
        drop = ['Antritt: Abstand von hinterer Wand', 'Platzbedarf in der Länge', 'Luft zu den Wänden', 'Austritt an', 'Wandwinkel']
        info = plan.info.reject { |k, _| drop.any? { |d| k.start_with?(d) } }
        info = info.map do |k, v|
          if k == 'Eingepasst: Laufbreite' then ['Laufbreite', v]
          elsif k.start_with?('Podest verlängert um') then ['Podest verlängert um (Grundmaß ausgenutzt)', v]
          else [k, v]
          end
        end
        x0, y0, x1, y1 = footprint(plan, p)
        src = ->(k) { p[k].to_f > 0 ? 'vorgegeben' : 'aus Parametern' }
        info.unshift(['Grundmaß Breite × Tiefe', format('%.1f × %.1f cm (Breite %s, Tiefe %s)', tw, tl, src.('total_w'), src.('total_l'))])
        if (x1 - x0 - tw).abs > 0.1 || (y1 - y0 - tl).abs > 0.1
          info.insert(1, ['Tatsächlicher Umriss inkl. Wangen', format('%.1f × %.1f cm', x1 - x0, y1 - y0)])
        end
        plan.info = info
        plan.warnings.map! do |w|
          w.sub(/\AZwischen Treppe und Wand (\w+) bleiben ([\d.]+) cm Luft\.\z/) do
            "Grundmaß #{$1}: die Treppe füllt #{$2} cm nicht aus."
          end.sub(/\AAntritt um ([\d.]+) cm nach hinten verschoben, (.*) \(fester Antritt und Austritt.*\z/) do
            "Gesamttiefe wird um #{$1} cm nicht ausgefüllt (Antritt liegt weiter hinten), #{$2} – Steigungsanzahl, Auftritt oder Gesamttiefe ändern."
          end.sub(/\AAntritt um ([\d.]+) cm nach vorn verschoben, (.*) \(fester Antritt und Austritt.*\z/) do
            "Gesamttiefe wird um #{$1} cm überschritten (Antritt liegt weiter vorn), #{$2} – Steigungsanzahl, Auftritt oder Gesamttiefe ändern."
          end
        end
      end

      # ======================================================================
      class Room
        include Geo

        def initialize(p)
          @p = p
          @v = p['variant']
          @sg = p['direction'] == 'links' ? 1 : -1 # endgültige Außenseite
          @mirror = @sg > 0
          @W = p['space_w'].to_f
          @L = p['space_l'].to_f
          @lim = Layout::LIMITS[p['building']] || Layout::LIMITS['efh']
          @gap = p['wall_gap'].to_f
          # kanonisch: Außenseite links -> bei Spiegelung links/rechts tauschen
          lft, rgt = @mirror ? %w[right left] : %w[left right]
          @wall = { l: p["wall_#{lft}"], r: p["wall_#{rgt}"], b: p['wall_back'] }
          @ang = { l: p["angle_#{lft}"].to_f * Math::PI / 180.0, r: p["angle_#{rgt}"].to_f * Math::PI / 180.0 }
          @t_out = Fit.side_t(p, :outer, @sg)
          @t_in = Fit.side_t(p, :inner, @sg)
          setup_room
        end

        def g(k)
          @wall[k] ? @gap : 0.0
        end

        # Begrenzungslinien (kanonisch): [Punkt, Richtung nach vorn bzw. rechts, Innennormale]
        def setup_room
          al = @ang[:l]; ar = @ang[:r]
          @bnd = {
            l: [[0.0, @L], [Math.cos(al), -Math.sin(al)], [Math.sin(al), Math.cos(al)]],
            r: [[@W, @L], [-Math.cos(ar), -Math.sin(ar)], [-Math.sin(ar), Math.cos(ar)]],
            b: [[0.0, @L], [1.0, 0.0], [0.0, -1.0]]
          }
          xl = Math.cos(al) * @L / Math.sin(al)
          xr = @W - Math.cos(ar) * @L / Math.sin(ar)
          @poly_c = [[xl, 0.0], [0.0, @L], [@W, @L], [xr, 0.0]]
          raise PlanError, 'Raum: die Seitenwände schneiden sich innerhalb der Raumlänge.' if xr - xl < 30
          @loch_c = nil
          return unless @p['loch']
          lw = @p['loch_w'].to_f; ll = @p['loch_l'].to_f
          lx = @p['loch_x'].to_f; ly = @p['loch_y'].to_f
          lx = @W - lx - lw if @mirror
          @loch_c = [lx, @L - ly - ll, lx + lw, @L - ly] # x0, y0, x1, y1
        end

        # Linie der Begrenzung k, um o nach innen versetzt: [Punkt, Richtung]
        def off_line(k, o)
          pt, d, n = @bnd[k]
          [add(pt, mul(n, o)), d]
        end

        def isect(l1, l2)
          p1, d1 = l1; p2, d2 = l2
          den = cross(d1, d2)
          raise PlanError, 'Raumgeometrie: parallele Linien.' if den.abs < 1e-9
          t = cross(sub(p2, p1), d2) / den
          add(p1, mul(d1, t))
        end

        def shift(line, v)
          [add(line[0], v), line[1]]
        end

        def flip(line)
          [line[0], mul(line[1], -1)]
        end

        # --------------------------------------------------------------------
        def solve
          raise PlanError, 'Antritt liegt außerhalb der Raumlänge.' if @p['antritt_l'].to_f > @L + 1e-6
          @y_fix = @p['antritt_l'].to_f > 0 ? @L - @p['antritt_l'].to_f : nil
          hh = @p['H'].to_f
          @n_list = if @p['n_steps'].to_i > 0
                      [@p['n_steps'].to_i]
                    else
                      lo = (hh / @lim[:h][1]).ceil
                      hi = (hh / @lim[:h][0]).floor
                      l = (lo..hi).to_a
                      l = [(hh / @p['h_target'].to_f).round] if l.empty?
                      l
                    end
          @a_fixed = @p['a_user'].to_f > 0 ? @p['a_user'].to_f : nil
          @a_lo = @lim[:a][0].to_f
          @a_hi = @lim[:a][1].to_f
          @b_user = @p['b'].to_f
          best = search(@b_user)
          if best.nil? && @b_adjustable
            # Laufbreite ist Höchstwert: schrittweise verkleinern, dann auf 1 cm genau
            ok_b = nil
            b = @b_user - 5.0
            while b >= 60.0 - 1e-6
              r = search(b)
              if r
                ok_b = b; best = r
                break
              end
              b -= 5.0
            end
            if ok_b
              (1..4).each do |i|
                r = search(ok_b + i)
                break unless r
                best = r
              end
            end
          end
          unless best
            msg = 'Die Treppe passt mit diesen Vorgaben nicht in den Raum.'
            msg += " (#{@fails.uniq.first(2).join(' ')})" unless @fails.empty?
            raise PlanError, msg
          end
          finalize(best[1])
        end

        def search(b)
          @fails ||= []
          @b = b
          @b_adjustable = false
          setup_legs
          best = nil
          candidates.each do |n, a, opt|
            plan = build(n, a, opt)
            next unless plan
            sc = score(plan)
            best = [sc, plan] if best.nil? || sc < best[0]
          end
          best
        rescue PlanError => e
          @fails << e.message
          nil
        end

        # --- Läufe vorbereiten ------------------------------------------------
        def setup_legs
          @gl_user = @p['gl'].to_f
          case @v
          when 'gerade', 'gerade_podest' then setup_straight
          else setup_turning
          end
        end

        def exit_line
          if @loch_c
            x0, y0, x1, y1 = @loch_c
            case @v
            when 'gerade', 'gerade_podest' then [[0.0, y1], [1.0, 0.0]]
            when 'l_podest', 'l_wendel' then [[x1, 0.0], [0.0, 1.0]]
            else [[0.0, y0], [1.0, 0.0]]
            end
          else
            case @v
            when 'gerade', 'gerade_podest' then off_line(:b, g(:b))
            when 'l_podest', 'l_wendel' then off_line(:r, g(:r))
            end
          end
        end

        def setup_straight
          ex = exit_line
          dl = @bnd[:l][1]; dr = @bnd[:r][1]
          if @wall[:l] && @wall[:r]
            @o_line = flip(off_line(:l, g(:l) + @t_out))
            @i_line = flip(off_line(:r, g(:r) + @t_in))
            @fill = true
          elsif @wall[:r]
            @i_line = flip(off_line(:r, g(:r) + @t_in))
            @o_line = shift(@i_line, mul(left(@i_line[1]), @b))
          else
            @o_line = flip(off_line(:l, g(:l) + @t_out))
            @i_line = shift(@o_line, mul(right(@o_line[1]), @b))
          end
          @b_adjustable = !@fill
          @u = norm(add(@o_line[1], @i_line[1]))
          @I1 = isect(@i_line, ex)
          @O1 = isect(@o_line, ex)
          @M1 = lerp(@I1, @O1, 0.5)
          raise PlanError, 'Treppe zu schmal für den Raum.' if dist(@I1, @O1) < 40
        end

        # Startkante senkrecht zu @u im Abstand t (entlang -@u von M1)
        def straight_edge(t)
          c = sub(@M1, mul(@u, t))
          e = [c, right(@u)]
          i0 = isect(@i_line, e); o0 = isect(@o_line, e)
          [i0, o0, lerp(i0, o0, 0.5)]
        end

        # t so, dass f(t) = ziel (f stetig, fast linear) – Sekantenverfahren
        def secant(t0, ziel)
          f = ->(t) { yield(t) - ziel }
          a = t0; b = t0 + 10.0
          fa = f.(a); fb = f.(b)
          12.times do
            break if (fb - fa).abs < 1e-12
            c = b - fb * (b - a) / (fb - fa)
            a, fa = b, fb
            b, fb = c, f.(c)
            break if fb.abs < 1e-7
          end
          b
        end

        def straight_by_len(lw)
          t = secant(lw, lw) { |x| dist(@M1, straight_edge(x)[2]) }
          straight_edge(t)
        end

        def straight_fixed_len
          t = secant(@M1[1] - @y_fix, @y_fix) { |x| e = straight_edge(x); [e[0][1], e[1][1]].min }
          dist(@M1, straight_edge(t)[2])
        end

        def setup_turning
          l_type = %w[l_podest l_wendel].include?(@v)
          d1 = mul(@bnd[:l][1], -1)
          d2 = [1.0, 0.0]
          d3 = @bnd[:r][1]
          @delta = [Math::PI - @ang[:l], Math::PI - @ang[:r]]
          o1 = [off_line(:l, g(:l) + @t_out)[0], d1]
          o2 = [off_line(:b, g(:b) + @t_out)[0], d2]
          o3 = [off_line(:r, g(:r) + @t_out)[0], d3]
          @dirs = l_type ? [d1, d2] : [d1, d2, d3]
          @olines = l_type ? [o1, o2] : [o1, o2, o3]
          eye = Params::U_TYPES.include?(@v) ? @p['eye'].to_f : @p['eye_z'].to_f
          if Params::U_TYPES.include?(@v) || eye > 0
            # Laufbreite so, dass der Abstand der Innenkanten (an der Wendelung) = Treppenauge
            f = ->(b) { c = corners_for(b); dot(sub(c[1], c[0]), d2) }
            f0 = f.(0.0); f1 = f.(100.0)
            raise PlanError, 'Raumgeometrie für U-Treppe ungültig.' if (f1 - f0).abs < 1e-9
            @b = (eye - f0) / ((f1 - f0) / 100.0)
            @fill = true
            raise PlanError, format('Raum zu schmal für Treppenauge %.0f cm (Laufbreite wäre %.0f cm).', eye, @b) if @b < 40
          end
          @b_adjustable = !@fill
          @gl = @gl_user > 0 ? @gl_user : @b / 2.0
          raise PlanError, 'Gehlinienabstand muss kleiner als die Laufbreite sein.' if @gl >= @b
          @c = corners_for(@b)
          @ilines = @olines.each_with_index.map { |ol, i| shift(ol, mul(right(@dirs[i]), @b)) }
          @wlines = @olines.each_with_index.map { |ol, i| shift(ol, mul(right(@dirs[i]), @b - @gl)) }
          @lc = @delta.map { |dl| Turtle.corner_len(@gl, dl) }
          if l_type
            @Gmid = nil
          else
            @Gmid = dot(sub(@c[1], @c[0]), d2)
            raise PlanError, 'Raum zu schmal: die Läufe überschneiden sich.' if @Gmid < -1e-6
          end
          # Austritt
          ex = exit_line
          if ex
            last = @wlines[-1]
            we = isect(last, ex)
            st = add(@c[-1], mul(left(@dirs[-1]), @gl)) # Gehlinie nach der letzten Ecke
            @Glast = dot(sub(we, st), @dirs[-1])
            @exit = ex
            raise PlanError, 'Austritt liegt vor der Wendelung – Treppenloch bzw. Raum prüfen.' if @Glast < -1e-6
          end
          # Antritt
          if @y_fix
            no = left(d1)
            @Gfirst = (@c[0][1] + [0.0, no[1] * @b].min - @y_fix) / d1[1]
            raise PlanError, 'Antritt liegt hinter der Wendelung.' if @Gfirst < -1e-6
          end
        end

        def corners_for(b)
          il = @olines.each_with_index.map { |ol, i| shift(ol, mul(right(@dirs[i]), b)) }
          (0...il.size - 1).map { |i| isect(il[i], il[i + 1]) }
        end

        # --- Kandidaten -------------------------------------------------------
        def a_ideal(n)
          h = @p['H'].to_f / n
          [[@p['schritt'].to_f - 2 * h, @a_lo].max, @a_hi].min
        end

        def a_grid(n)
          return [@a_fixed] if @a_fixed
          ai = a_ideal(n)
          l = []
          coarse, fine = both_free? ? [1.0, 3] : [0.5, 15]
          x = @a_lo
          while x <= @a_hi + 1e-9
            l << x.round(2)
            x += coarse
          end
          (-fine..fine).each { |i| l << (ai + i * (both_free? ? 0.5 : 0.1)).round(2) }
          l.select { |a| a >= @a_lo - 1e-9 && a <= @a_hi + 1e-9 }.uniq
        end

        def winder?
          Params::WENDEL.include?(@v)
        end

        def both_free?
          @y_fix.nil? && @Glast.nil? && !%w[gerade gerade_podest].include?(@v)
        end

        def candidates
          out = []
          start_fixed = !@y_fix.nil?
          end_fixed = !@Glast.nil? || %w[gerade gerade_podest].include?(@v)
          if %w[gerade gerade_podest].include?(@v)
            @lw_fixed = start_fixed ? straight_fixed_len : nil
          end
          @n_list.each do |n|
            if winder? && start_fixed && end_fixed
              # Auftritt ergibt sich aus Lage der Ecken (kite_layout)
              out << [n, @a_fixed || a_ideal(n), {}]
            elsif @v == 'gerade' && start_fixed && end_fixed
              out << [n, @lw_fixed / (n - 1), {}]
            else
              a_grid(n).each { |a| out << [n, a, {}] }
              # exakte Auftritte, bei denen die Gehlinie unverändert bleibt
              if winder? && !@a_fixed
                lf = @delta.map { |dl| Turtle.corner_len(1.0, dl) }
                gfix = start_fixed ? @Gfirst : @Glast
                if @v == 'l_wendel' && gfix
                  (0...n).each { |m| out << [n, (gfix + @gl * lf[0] / 2.0) / (m + 0.5), {}] }
                elsif @v != 'l_wendel' && !gfix
                  (1...n).each { |k| out << [n, (@gl * (lf[0] + lf[1]) / 2.0 + @Gmid.to_f) / k, {}] }
                end
                out.reject! { |_n, a, _o| a < @a_lo - 1e-9 || a > @a_hi + 1e-9 }
              end
              # exakte Auftritte für Podestläufe (ohne Podestverlängerung)
              if !@a_fixed && Params::PODEST.include?(@v) && @v != 'gerade_podest'
                [@Glast, @Gfirst, @Gmid].compact.each do |gg|
                  (1..20).each do |k|
                    a = gg / k
                    out << [n, a, {}] if a >= @a_lo && a <= @a_hi
                  end
                end
              end
            end
          end
          # beide Enden frei: Aufteilung der Läufe durchprobieren
          if both_free?
            key = winder? ? 'm1' : 'r1'
            if @p[key].to_i <= 0
              out = out.flat_map do |n, a, o|
                hi = winder? ? n - 2 : n - 1
                (0..hi).map { |k| [n, a, o.merge(key => k)] }
              end
            end
          end
          if @a_fixed && start_fixed && end_fixed && @v == 'gerade'
            out = out.select { |_n, a, _o| (a - @a_fixed).abs < 0.05 }
            if out.empty?
              raise PlanError, 'Fester Auftritt und fester Antritt passen nicht zusammen – Auftritt auf 0 (automatisch) ' \
                               'oder Antritt frei (0) setzen.'
            end
          end
          out
        end

        # Lage der Wendelung so, dass jede Ecke genau mittig in einer Stufe liegt
        # (Drachenstufe). Freiheitsgrade: Gehlinienabstand gl (wirkt nur in den
        # Ecken) und – wo ein Ende frei ist – der Auftritt bzw. die Lage.
        # Sind Antritt und Austritt fest und lässt sich das nicht vereinbaren, wird
        # der Antritt so wenig wie möglich verschoben (Warnung).
        # Rückgabe: [gl, a, g1, g3, Antrittsverschiebung] oder nil
        def kite_layout(n, a)
          ntr = n - 1
          two = @v != 'l_wendel'
          lf = @delta.map { |dl| Turtle.corner_len(1.0, dl) }
          lf = lf.first(1) unless two
          lsum = lf.sum
          gmid = two ? @Gmid.to_f : 0.0
          tgt = @gl
          lo, hi, dlo, dhi = Layout.gl_range(@b, tgt)
          inb = ->(g) { g >= lo - 1e-9 && g <= hi + 1e-9 && g > 1.0 && g < @b - 1.0 }
          g1f = @Gfirst
          g30, g3k = @Glast ? glast_lin : [nil, nil]
          len = ->(gl) { gl * lsum + gmid } # Gehlinie in der Wendelung (Ecke 1 Anfang bis letzte Ecke Ende)
          sols = []
          shifted = false
          if g1f && g30
            unless two
              # a = (g1 + g3(gl) + gl·L)/ntr  und  g1 + gl·L/2 = (m + ½)·a
              l0 = lf[0]
              (0...ntr).each do |m|
                c = (m + 0.5) / ntr
                coef = l0 / 2.0 - c * (l0 + g3k)
                next if coef.abs < 1e-9
                gl = (c * (g1f + g30) - g1f) / coef
                next unless inb.(gl)
                g3 = g30 + g3k * gl
                sols << [gl, (g1f + g3 + l0 * gl) / ntr, g1f, g3, 0.0]
              end
            end
            if sols.empty?
              shifted = true
              sols = one_end(ntr, a, lf, gmid, g30, g3k, false, inb, [dlo, dhi])
              sols.each { |x| x[2] = ntr * x[1] - x[3] - len.(x[0]); x[4] = x[2] - g1f }
            end
          elsif g1f
            sols = one_end(ntr, a, lf, gmid, g1f, 0.0, true, inb)
            sols.each { |x| x[3] = ntr * x[1] - x[2] - len.(x[0]) }
          elsif g30
            sols = one_end(ntr, a, lf, gmid, g30, g3k, false, inb)
            sols.each { |x| x[2] = ntr * x[1] - x[3] - len.(x[0]) }
          else
            gl = tgt
            if two
              sg = Layout.gl_for_corners(a, (lf[0] + lf[1]) / 2.0, gmid, @b, tgt)
              return nil unless sg
              gl = sg[0]
            end
            m1 = @p['m1'].to_i > 0 ? @p['m1'].to_i : (@opt['m1'] || ((ntr - 1) / (@v == 'z_wendel' ? 3.0 : 2.0)).round)
            g1 = (m1 + 0.5) * a - gl * lf[0] / 2.0
            sols << [gl, a, g1, ntr * a - g1 - len.(gl), 0.0]
          end
          sols.select! { |_gl, aa, g1, g3, _s| g1 > -1e-6 && g3 > -1e-6 && aa >= 10 }
          sols.select! { |_gl, aa, *_r| (aa - @a_fixed).abs < 0.05 } if @a_fixed
          return nil if sols.empty?
          if shifted
            sols.min_by { |gl, aa, _g1, _g3, sh| sh.abs + 0.5 * (aa - a).abs + 0.3 * (gl - tgt).abs }
          else
            sols.min_by { |gl, aa, *_r| [(aa - a).abs.round(3), (gl - tgt).abs] }
          end
        end

        # Gehlinienlänge vom Austritt bis zur letzten Ecke als lineare Funktion von gl
        # (bei schräger Austrittskante hängt sie vom Gehlinienabstand ab)
        def glast_lin
          f = lambda do |gl|
            wl = shift(@olines[-1], mul(right(@dirs[-1]), @b - gl))
            we = isect(wl, @exit)
            st = add(@c[-1], mul(left(@dirs[-1]), gl))
            dot(sub(we, st), @dirs[-1])
          end
          g0 = f.(0.0)
          [g0, (f.(100.0) - g0) / 100.0]
        end

        # Ein Ende fest: Gehlinienlänge vom festen Ende bis zur nächsten Ecke = g0 + gk·gl.
        # Rückgabe: [[gl, a, g1|nil, g3|nil, 0.0], ...]
        # free_gl: [min, max] -> zusätzlich gl im Bereich abtasten und a daraus bestimmen
        def one_end(ntr, a, lf, gmid, g0, gk, from_start, inb, free_gl = nil)
          res = []
          la = from_start ? lf[0] : lf[-1]
          if lf.size == 2
            lavg = (lf[0] + lf[1]) / 2.0
            # g0 + gk·gl + gl·la/2 = (m + ½)·a  und  gl·lavg + gmid = k·a
            (0...ntr).each do |m|
              (1...ntr).each do |k|
                coef = gk + la / 2.0 - (m + 0.5) * lavg / k
                next if coef.abs < 1e-9
                gl = ((m + 0.5) * gmid / k - g0) / coef
                next unless inb.(gl)
                aa = (gl * lavg + gmid) / k
                next if aa < @a_lo - 1e-9 || aa > @a_hi + 1e-9
                res << [gl, aa]
              end
            end
          else
            (0...ntr).each do |m|
              gl = ((m + 0.5) * a - g0) / (gk + la / 2.0)
              res << [gl, a] if inb.(gl)
            end
            if free_gl
              gl = free_gl[0]
              while gl <= free_gl[1] + 1e-9
                (0...ntr).each do |m|
                  aa = (g0 + gk * gl + gl * la / 2.0) / (m + 0.5)
                  res << [gl, aa] if aa >= @a_lo - 1e-9 && aa <= @a_hi + 1e-9
                end
                gl += 0.5
              end
            end
          end
          res.map do |gl, aa|
            gf = g0 + gk * gl
            from_start ? [gl, aa, gf, nil, 0.0] : [gl, aa, nil, gf, 0.0]
          end
        end

        # Gesamtlänge der Gehlinie bei gewendelten Läufen
        def winder_total(g1, g3)
          case @v
          when 'l_wendel' then g1 + @lc[0] + g3
          when 'u_wendel' then g1 + @lc[0] + @Gmid + @lc[1] + g3
          when 'z_wendel' then g1 + @lc[0] + @Gmid + @lc[1] + g3
          end
        end

        # --- Aufbau -----------------------------------------------------------
        def build(n, a, opt)
          return nil if a < 10
          @opt = opt || {}
          case @v
          when 'gerade', 'gerade_podest' then build_straight(n, a)
          else build_turning(n, a)
          end
        rescue PlanError => e
          @fails << e.message
          nil
        end

        def new_plan(n, a)
          pl = Plan.new
          pl.params = @p
          pl.variant = @v
          pl.n = n
          pl.H = @p['H'].to_f
          pl.h = pl.H / n
          pl.a = a
          pl
        end

        TurtleLike = Struct.new(:inner, :walk, :outer, :zones, :corners)

        def build_straight(n, a)
          ntr = n - 1
          podest = @v == 'gerade_podest'
          if podest
            r1 = @p['r1'].to_i > 0 ? @p['r1'].to_i : (n / 2.0).round
            return fail!('Steigungen im 1. Lauf passen nicht.') if r1 < 2 || r1 > n - 2
          end
          b_exit = dist(@I1, @O1)
          if @lw_fixed
            lw = @lw_fixed
            if podest
              lp = lw - (ntr - 1) * a
              lp_min = @p['landing_len'].to_f > 0 ? @p['landing_len'].to_f : b_exit
              return fail!('Podest zu kurz.') if lp < lp_min - 0.01
              return fail!('Podest zu lang.') if lp > lp_min + 2 * a
            else
              return fail!('Auftritt passt nicht.') if (lw - ntr * a).abs > 0.01
            end
          else
            lp = podest ? (@p['landing_len'].to_f > 0 ? @p['landing_len'].to_f : b_exit) : 0.0
            lw = podest ? (ntr - 1) * a + lp : ntr * a
          end
          i0, o0, m0 = straight_by_len(lw)
          depths = podest ? [a] * (r1 - 1) + [lp] + [a] * (n - r1 - 1) : [a] * ntr
          kinds = Array.new(ntr, :step)
          kinds[r1 - 1] = :landing if podest
          flights = podest ? [r1, n - r1] : [n]
          t = TurtleLike.new(Polyline.new([i0, @I1]), Polyline.new([m0, @M1]), Polyline.new([o0, @O1]), [], [])
          plan = new_plan(n, a)
          plan.b = (dist(i0, o0) + b_exit) / 2.0
          finish(plan, t, n, a, depths, kinds, flights, plan.b / 2.0)
          @lp = lp
          plan.info << ['Podestlänge (Gehlinie)', format('%.1f cm', lp)] if podest
          if (dist(i0, o0) - b_exit).abs > 0.5
            plan.info << ['Laufbreite Antritt / Austritt', format('%.1f / %.1f cm', dist(i0, o0), b_exit)]
          end
          check_room(plan) ? plan : nil
        end

        def fail!(msg)
          @fails << msg
          nil
        end

        def build_turning(n, a)
          @ext = nil
          @kite_shift = nil
          gl = nil
          ntr = n - 1
          d1 = @dirs[0]
          case @v
          when 'l_podest', 'u_podest', 'z_podest'
            ext = [0.0, 0.0, 0.0, 0.0] # vor/nach Ecke 1, vor/nach Ecke 2
            rmid = nil
            if @v == 'z_podest'
              rmid = (@Gmid / a + 1e-6).floor + 1
              em = @Gmid - (rmid - 1) * a
              ext[1] = em / 2.0; ext[2] = em / 2.0
            end
            r_used = rmid || 0
            if @Glast
              rl = (@Glast / a + 1e-6).floor + 1
              ext[@v == 'l_podest' ? 1 : (@v == 'u_podest' ? 1 : 3)] += @Glast - (rl - 1) * a
            end
            if @Gfirst
              rf = (@Gfirst / a + 1e-6).floor + 1
              ext[0] += @Gfirst - (rf - 1) * a
            end
            if rf && rl
              return fail!('Stufenzahl ergibt sich aus dem Raum.') if rf + rl + r_used != n
            elsif rf
              rl = n - rf - r_used
            elsif rl
              rf = n - rl - r_used
            else
              rest = n - r_used
              rf = @p['r1'].to_i > 0 ? @p['r1'].to_i : (@opt['r1'] || (rest / 2.0).round)
              rl = rest - rf
            end
            return fail!('Zu wenige Steigungen für die Läufe.') if rf < 1 || rl < 1 || (rmid && rmid < 1)
            g1 = (rf - 1) * a + ext[0]
            t = Turtle.new(@b, @gl, -1, sub(@c[0], mul(d1, g1)), d1)
            t.straight((rf - 1) * a)
            z1 = t.turn(:landing) do
              t.straight(ext[0])
              t.corner(@delta[0])
              if @v == 'u_podest'
                t.straight(@Gmid)
                t.corner(@delta[1])
              end
              t.straight(ext[1])
            end
            depths = [a] * (rf - 1)
            kinds = Array.new(ntr, :step)
            if @v == 'z_podest'
              t.straight((rmid - 1) * a)
              z2 = t.turn(:landing) do
                t.straight(ext[2])
                t.corner(@delta[1])
                t.straight(ext[3])
              end
              depths += [z1[:w1] - z1[:w0]] + [a] * (rmid - 1) + [z2[:w1] - z2[:w0]]
              kinds[rf - 1] = :landing
              kinds[rf + rmid - 1] = :landing
              flights = [rf, rmid, rl]
            else
              depths += [z1[:w1] - z1[:w0]]
              kinds[rf - 1] = :landing
              flights = [rf, rl]
            end
            if @exit
              t.straight_to_cut(*@exit)
            else
              t.straight((rl - 1) * a)
            end
            depths += [a] * (rl - 1)
            @ext = ext
          else # Wendelstufen
            sol = kite_layout(n, a)
            return fail!('Drachenstufen lassen sich nicht mittig auf die Ecken legen.') unless sol
            gl, a, g1, g3, @kite_shift = sol
            g1 = [g1, 0.0].max
            t = Turtle.new(@b, gl, -1, sub(@c[0], mul(d1, g1)), d1)
            t.straight(g1)
            if @v == 'u_wendel'
              t.turn(:winder) do
                t.corner(@delta[0])
                t.straight(@Gmid)
                t.corner(@delta[1])
              end
            else
              t.turn(:winder) { t.corner(@delta[0]) }
              if @v == 'z_wendel'
                t.straight(@Gmid)
                t.turn(:winder) { t.corner(@delta[1]) }
              end
            end
            if @exit
              t.straight_to_cut(*@exit)
            else
              t.straight(g3)
            end
            depths = [a] * ntr
            kinds = Array.new(ntr, :step)
            flights = [n]
          end
          plan = new_plan(n, a)
          plan.b = @b
          finish(plan, t, n, a, depths, kinds, flights, gl || @gl)
          plan.instance_variable_set(:@kite_shift, @kite_shift)
          if winder? && @kite_shift && @kite_shift.abs > 0.05
            ys = Fit.footprint_pts(plan, @p).map(&:last)
            return fail!('Treppe ist zu lang für die Raumlänge.') if ys.min < -TOL
          end
          check_room(plan) ? plan : nil
        end

        # spiegeln (linksgewendelt) und Plan fertigstellen
        def finish(plan, t, n, a, depths, kinds, flights, gl)
          if @mirror
            m = ->(q) { [@W - q[0], q[1]] }
            t = TurtleLike.new(Polyline.new(t.inner.pts.map(&m)), Polyline.new(t.walk.pts.map(&m)),
                               Polyline.new(t.outer.pts.map(&m)), t.zones,
                               (t.respond_to?(:corners) ? t.corners : []).map { |c| c.merge(pt_in: m.(c[:pt_in]), pt_out: m.(c[:pt_out])) })
          end
          plan.outer_side = @sg
          q = @p.merge('gl' => gl)
          Layout.finish_flights(plan, q, t, n, a, depths, kinds, flights, gl)
          plan
        end

        # Raum in Benutzerkoordinaten (ungespiegelt)
        def mirror_pt(q)
          @mirror ? [@W - q[0], q[1]] : q
        end

        def room_poly
          pts = @poly_c.map { |q| mirror_pt(q) }
          @mirror ? pts.reverse : pts
        end

        def loch_poly
          return nil unless @loch_c
          x0, y0, x1, y1 = @loch_c
          [[x0, y0], [x1, y0], [x1, y1], [x0, y1]].map { |q| mirror_pt(q) }
        end

        # Liegt die Treppe im Raum? (Wände mit Spiel, Grenzen ohne Wand mit 0)
        def exit_bnd
          return nil if @loch_c
          case @v
          when 'gerade', 'gerade_podest' then :b
          when 'l_podest', 'l_wendel' then :r
          end
        end

        def check_room(plan)
          mp = ->(q) { @mirror ? [@W - q[0], q[1]] : q }
          pts = Fit.footprint_pts(plan, @p).map(&mp)
          bare = (plan.inner.pts + plan.outer.pts).map(&mp)
          @luft = {}
          %i[l r b].each do |k|
            pt, _d, nn = @bnd[k]
            # Austrittswand: Wangenenden werden parallel zur Wand geschnitten
            dmin = (k == exit_bnd ? bare : pts).map { |q| dot(sub(q, pt), nn) }.min
            if dmin < g(k) - TOL
              @fails << 'Treppe ragt über eine Wand bzw. Raumgrenze.'
              return false
            end
            @luft[k] = dmin - g(k)
          end
          # Grundmaß (_box): auch bei festem Antritt darf nichts vorn überstehen (U/dreiläufig: Austrittslauf)
          if pts.map(&:last).min < -TOL && (@y_fix.nil? || @p['_box'])
            @fails << 'Treppe ist zu lang für die Raumlänge.'
            return false
          end
          plan.instance_variable_set(:@luft, @luft.dup)
          true
        end

        def score(plan)
          h = plan.h; a = plan.a
          sm = 2 * h + a
          s = 3.0 * (sm - @p['schritt'].to_f).abs + (h - @p['h_target'].to_f).abs
          s += 1000 if h < @lim[:h][0] - 1e-6 || h > @lim[:h][1] + 1e-6
          s += 1000 if a < @lim[:a][0] - 1e-6 || a > @lim[:a][1] + 1e-6
          s += 1000 if sm < 59 - 1e-6 || sm > 65 + 1e-6
          if plan.flights
            parts = plan.flights
            s += 0.15 * (parts.max - parts.min) if parts.size > 1
          end
          s += 0.05 * @ext.sum if @ext && Params::PODEST.include?(@v)
          if winder?
            s += 500 unless Layout.kite_errors(plan).empty?
            glu = plan.instance_variable_get(:@gl).to_f
            s += 0.3 * (glu - @gl).abs
            _l, _h, dlo, dhi = Layout.gl_range(@b, @gl)
            s += 30 if glu < dlo - 1e-6 || glu > dhi + 1e-6
            s += 100 + 2.0 * @kite_shift.abs if @kite_shift && @kite_shift.abs > 0.05
            inner = plan.info.find { |k, _| k.start_with?('Auftritt Innenkante') }
            s += 50 + (@p['min_inner'].to_f - inner[1].to_f) * 5 if inner && inner[1].to_f < @p['min_inner'].to_f
          end
          if @loch_c
            hd = Fit.headroom(plan, @p, loch_poly)
            s += 200 + 5 * (@p['head_min'].to_f - hd[0]) if hd && hd[0] < @p['head_min'].to_f
          end
          s
        end

        def finalize(plan)
          plan.space = { poly: room_poly, loch: loch_poly, walls: Fit.walls(@p) }
          luft = plan.instance_variable_get(:@luft) || {}
          names = { l: 'links', r: 'rechts', b: 'hinten' }
          touch = case @v
                  when 'gerade', 'gerade_podest' then (@fill ? %i[l r] : [@wall[:r] && !@wall[:l] ? :r : :l]) + (@loch_c ? [] : [:b])
                  when 'l_podest', 'l_wendel' then %i[l b] + (@loch_c ? [] : [:r])
                  else %i[l b r]
                  end
          txt = []
          %i[l r b].each do |k|
            next unless @wall[k]
            nm = names[@mirror && k != :b ? (k == :l ? :r : :l) : k]
            txt << format('%s %.1f', nm, luft[k].to_f.abs < 0.05 ? 0.0 : luft[k].to_f)
            if touch.include?(k) && luft[k].to_f > 0.5
              plan.warnings << format('Zwischen Treppe und Wand %s bleiben %.1f cm Luft.', nm, luft[k])
            end
          end
          info = []
          info << ['Eingepasst: Laufbreite', format('%.1f cm', plan.b)]
          ys = Fit.footprint_pts(plan, @p).map(&:last)
          l0 = plan.line(0.0)
          y_ant = [l0[:in][1], l0[:out][1]].min
          info << ['Antritt: Abstand von hinterer Wand', format('%.1f cm%s', @L - y_ant, @y_fix ? ' (fest)' : '')]
          info << ['Platzbedarf in der Länge (inkl. Wangen)', format('%.1f cm von %.0f cm', @L - ys.min, @L)]
          info << ['Luft zu den Wänden (über Spiel hinaus)', txt.join(' / ') + ' cm'] unless txt.empty?
          info << ['Austritt an', @loch_c ? 'Kante Treppenloch' : (@v =~ /^[uz]_/ ? 'frei (kein Treppenloch)' : 'Wand / Raumgrenze')]
          plan.info = info + plan.info
          if winder?
            glu = plan.instance_variable_get(:@gl).to_f
            if (glu - @gl).abs > 0.05
              plan.info << ['Gehlinie angepasst (Drachenstufen mittig auf den Ecken)', format('%.1f cm statt %.1f cm', glu, @gl)]
              _l, _h, dlo, dhi = Layout.gl_range(@b, @gl)
              plan.warnings << format('Gehlinie (%.1f cm) liegt außerhalb des Gehbereichs.', glu) if glu < dlo - 1e-6 || glu > dhi + 1e-6
            end
            sh = plan.instance_variable_get(:@kite_shift).to_f
            if sh.abs > 0.05
              plan.warnings << format('Antritt um %.1f cm %s verschoben, damit die Drachenstufen mittig auf den Ecken liegen ' \
                                      '(fester Antritt und Austritt lassen sich sonst nicht vereinbaren).', sh.abs, sh > 0 ? 'nach vorn' : 'nach hinten')
            end
            Layout.report_kites(plan, '(Steigungsanzahl, Auftritt oder Antritt ändern)')
          end
          if @ext && Params::PODEST.include?(@v) && @ext.sum > 0.05
            plan.info << ['Podest verlängert um (Raum ausgenutzt)', @ext.select { |e| e > 0.05 }.map { |e| format('%.1f', e) }.join(' / ') + ' cm']
          end
          if (@ang[:l] - Math::PI / 2).abs > 1e-4 || (@ang[:r] - Math::PI / 2).abs > 1e-4
            plan.info << ['Wandwinkel links / rechts', format('%.1f° / %.1f°', @p['angle_left'], @p['angle_right'])]
          end
          Fit.headroom_report(plan, @p, loch_poly) if @loch_c
          Layout.check(plan, @p)
          plan
        end
      end

      # ---------------------------------------------------------------------
      # Kopffreiheit unter der Decke (außerhalb des Treppenlochs).
      # Rückgabe: [min. lichte Höhe, Gehlinienposition] oder nil
      def headroom(plan, p, loch)
        return nil unless loch
        zc = plan.H - p['floor_t'].to_f
        best = nil
        lw = plan.lines_w
        (0...plan.treads).each do |k|
          top = (k + 1) * plan.h
          [0.02, 0.5, 0.98].each do |f|
            w = lw[k] + f * (lw[k + 1] - lw[k])
            l = plan.line(w)
            [0.0, 0.25, 0.5, 0.75, 1.0].each do |g|
              q = Geo.lerp(l[:in], l[:out], g)
              next if inside_rect?(q, loch)
              hd = zc - top
              best = [hd, w] if best.nil? || hd < best[0]
            end
          end
        end
        best || [Float::INFINITY, 0.0]
      end

      def inside_rect?(q, r)
        xs = r.map(&:first); ys = r.map(&:last)
        q[0] > xs.min + 1e-6 && q[0] < xs.max - 1e-6 && q[1] > ys.min + 1e-6 && q[1] < ys.max - 1e-6
      end

      def headroom_report(plan, p, loch)
        hd = headroom(plan, p, loch)
        return unless hd
        if hd[0].infinite?
          plan.info << ['Kopffreiheit', 'ganze Treppe unter dem Treppenloch']
        else
          plan.info << ['Kopffreiheit (min., lotrecht über Stufe)', format('%.1f cm', hd[0])]
          if hd[0] < p['head_min'].to_f
            plan.warnings << format('Kopffreiheit nur %.0f cm < %.0f cm – Treppenloch länger machen oder Treppe anders legen.', hd[0], p['head_min'].to_f)
          end
        end
        # Austritt muss innerhalb/an der Kante des Lochs liegen
        l = plan.line(plan.wtot)
        mid = Geo.lerp(l[:in], l[:out], 0.5)
        xs = loch.map(&:first); ys = loch.map(&:last)
        if mid[0] < xs.min - 1 || mid[0] > xs.max + 1 || mid[1] < ys.min - 1 || mid[1] > ys.max + 1
          plan.warnings << 'Der Austritt liegt nicht am Treppenloch – Lage des Treppenlochs prüfen.'
        end
      end
    end
  end
end
