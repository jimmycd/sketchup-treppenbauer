# encoding: UTF-8
# Treppenbau – Umschalten zwischen „Treppe aus den Parametern berechnen“ und
# „Treppe in verfügbaren Raum einpassen“ ohne Änderung der Treppe (fehler.md Nr. 6).
#
# raum -> aus: die beim Einpassen gefundenen Werte (Steigungen, Auftritt, Laufbreite,
#   Gehlinie, Aufteilung der Läufe, Lage der Wendelung, Podestverlängerungen,
#   Austrittspodest) werden in die Parameter übernommen.
# aus -> raum: Raum (Länge, Breite, fester Antritt, ggf. Treppenloch) wird aus dem
#   Umriss der Treppe abgeleitet; die Treppe liegt mit dem Spiel an den Wänden.
# In beiden Richtungen wird geprüft, ob die neue Treppe exakt der alten entspricht.
# Werte, die vorher „automatisch“ (0) waren, bleiben automatisch, wenn das am
# Ergebnis nichts ändert.

module JTools
  module Treppenbau
    module Transfer
      module_function

      TOL = 0.01 # cm
      SAMPLES = 32

      # Rückgabe: { ok:, params:, exact:, dev:, shift: [dx, dy], message:, notes: [] }
      def switch(p, to_mode)
        p = Params.normalize(p)
        to_mode = to_mode == 'raum' ? 'raum' : 'aus'
        target = p.merge('fit_mode' => to_mode)
        return result(target, true, 0.0, [0.0, 0.0], 'Ermittlung unverändert.', []) if p['fit_mode'] == to_mode
        begin
          plan = Layout.compute(p)
        rescue PlanError => e
          return result(target, false, nil, nil,
                        "Umgeschaltet – die bisherige Treppe war ungültig (#{e.message}), Werte wurden nicht übernommen.", [])
        end
        notes = []
        q = to_mode == 'aus' ? to_free(p, plan, notes) : to_room(p, plan, notes)
        cmp = compare_params(plan, q)
        exact = cmp && cmp[0] <= TOL
        msg = if exact
                to_mode == 'aus' ? 'Werte aus dem Raum übernommen – Treppe unverändert, jetzt frei anpassbar.'
                                 : 'Raum aus der Treppe abgeleitet – Treppe unverändert.'
              elsif cmp
                format('Umgeschaltet – Treppe weicht um bis zu %.1f cm ab.', cmp[0])
              else
                'Umgeschaltet – die Treppe lässt sich in diesem Modus nicht berechnen.'
              end
        msg += ' ' + notes.uniq.join(' ') unless notes.empty? || exact
        result(q, exact, cmp && cmp[0], cmp && cmp[1], msg, notes)
      end

      def result(q, exact, dev, shift, msg, notes)
        { ok: true, params: q, exact: exact, dev: dev, shift: shift, message: msg, notes: notes.uniq }
      end

      def r4(x)
        x.to_f.round(4)
      end

      # ------------------------------------------------------------------
      # Vergleich zweier Pläne (bis auf eine Verschiebung im Grundriss).
      # Rückgabe: [max. Abweichung in cm, Verschiebung alt -> neu] oder nil
      def compare(pa, pb)
        return [Float::INFINITY, nil] if pa.n != pb.n || pa.nlines != pb.nlines || (pa.h - pb.h).abs > 1e-6
        return [Float::INFINITY, nil] if !pa.spiral != !pb.spiral || pa.kinds != pb.kinds
        sa = signature(pa); sb = signature(pb)
        return [Float::INFINITY, nil] if sa.size != sb.size
        shift = Geo.sub(sb[0], sa[0])
        dev = sa.each_with_index.map { |q, i| Geo.dist(Geo.add(q, shift), sb[i]) }.max
        [dev, shift]
      end

      def compare_params(plan, q)
        compare(plan, Layout.compute(q))
      rescue PlanError
        nil
      end

      def same?(plan, q)
        c = compare_params(plan, q)
        c && c[0] <= TOL
      end

      def signature(plan)
        pts = []
        lw = plan.lines_w
        lw.each_with_index do |w, i|
          l = plan.line(w)
          pts << l[:in] << l[:out]
          next if i.zero?
          m = plan.line(lw[i - 1] + 0.37 * (w - lw[i - 1])) # nicht genau Podestmitte (Seitenwahl in Plan#line)
          pts << m[:in] << m[:out]
        end
        [plan.inner, plan.outer, plan.walk].each do |pl|
          len = pl.length
          (0..SAMPLES).each { |k| pts << pl.at(len * k / SAMPLES) }
        end
        pts
      end

      # ------------------------------------------------------------------
      # Podestverlängerungen vor/nach den Ecken und Austrittspodest aus dem Plan
      def landing_ext(plan)
        exts = []
        exit_land = 0.0
        plan.zones.each do |z|
          next unless z[:kind] == :landing
          cs = plan.corners.select { |c| c[:w0] && c[:w0] > z[:w0] - 1e-6 && c[:w1] < z[:w1] + 1e-6 }
          if cs.empty?
            exit_land = z[:w1] - z[:w0] if (z[:w1] - plan.wtot).abs < 1e-6 && plan.nlines > plan.n
            next
          end
          exts << [[cs.first[:w0] - z[:w0], 0.0].max, [z[:w1] - cs.last[:w1], 0.0].max]
        end
        [exts, exit_land]
      end

      # Lage der Wendelung (m1, m2) aus den Drachenstufen
      def winder_m(plan)
        ks = Layout.kite_steps(plan).map { |k| k - 1 }.sort
        case plan.variant
        when 'l_wendel' then { 'm1' => ks[0] }
        when 'u_wendel'
          return {} unless ks.size == 2
          { 'm1' => (ks[1] - ks[0]).even? ? (ks[0] + ks[1]) / 2 : (ks[0] + ks[1] + 1) / 2 }
        when 'z_wendel'
          return {} unless ks.size == 2
          { 'm1' => ks[0], 'm2' => ks[1] - ks[0] }
        else {}
        end
      end

      # ------------------------------------------------------------------
      # Raum -> Parameter
      def to_free(p, plan, notes)
        v = p['variant']
        base = p.merge('fit_mode' => 'aus', 'total_w' => 0.0, 'total_l' => 0.0)
        if Params::SPIRAL.include?(v)
          return base.merge('D_out' => r4(plan.spiral[:ro] * 2.0))
        end
        q = base.merge('n_steps' => plan.n.to_f, 'a_user' => r4(plan.a), 'b' => r4(plan.b),
                       'pod1_vor' => 0.0, 'pod1_nach' => 0.0, 'pod2_vor' => 0.0, 'pod2_nach' => 0.0, 'exit_land' => 0.0)
        q['gl'] = r4(plan.instance_variable_get(:@gl)) if Params::TURNING.include?(v)
        fl = plan.flights || []
        if Params::PODEST.include?(v)
          q['r1'] = fl[0].to_f
          q['r2'] = fl[1].to_f if v == 'z_podest'
        end
        if v == 'gerade_podest'
          r1 = fl[0]
          q['landing_len'] = r4(plan.lines_w[r1] - plan.lines_w[r1 - 1])
        end
        winder_m(plan).each { |k, x| q[k] = x.to_f }
        exts, xl = landing_ext(plan)
        if %w[l_podest u_podest z_podest].include?(v)
          q['pod1_vor'], q['pod1_nach'] = exts[0].map { |e| r4(e) } if exts[0]
          q['pod2_vor'], q['pod2_nach'] = exts[1].map { |e| r4(e) } if exts[1] && v == 'z_podest'
        end
        q['exit_land'] = r4(xl)
        q = Params.normalize(q)
        if (p['angle_left'].to_f - 90).abs > 0.01 || (p['angle_right'].to_f - 90).abs > 0.01
          notes << 'Schräge Wände lassen sich ohne Raum nicht nachbilden (Treppe wird rechtwinklig).'
        end
        relax(plan, q, p, %w[nv gl r1 r2 m1 m2 landing_len b a_user n_steps])
      end

      # Werte, die vorher automatisch waren, wieder auf automatisch setzen,
      # wenn sich die Treppe dadurch nicht ändert
      def relax(plan, q, orig, keys)
        return q unless same?(plan, q)
        keys.each do |k|
          next if orig[k] == q[k]
          t = q.merge(k => orig[k])
          q = t if same?(plan, t)
        end
        q
      end

      # ------------------------------------------------------------------
      # Parameter -> Raum
      def to_room(p, plan, notes)
        v = p['variant']
        g = p['wall_gap'].to_f
        gl_ = p['wall_left'] ? g : 0.0
        gr_ = p['wall_right'] ? g : 0.0
        gb_ = p['wall_back'] ? g : 0.0
        base = p.merge('fit_mode' => 'raum', 'angle_left' => 90.0, 'angle_right' => 90.0)
        if Params::SPIRAL.include?(v)
          d = plan.spiral[:ro] * 2.0
          notes << 'Der Außendurchmesser wird beim Einpassen auf ganze cm gerundet.' if (d - d.round).abs > 1e-6
          return base.merge('space_w' => r4(d + gl_ + gr_), 'space_l' => r4(d + gb_), 'antritt_l' => 0.0)
        end
        x0, y0, x1, y1 = Fit.footprint(plan, p)
        w = x1 - x0 + gl_ + gr_
        l = y1 - y0 + gb_
        tr = ->(q) { [q[0] - x0 + gl_, q[1] - y0] }
        l0 = plan.line(0.0)
        y_ant = [tr.(l0[:in])[1], tr.(l0[:out])[1]].min
        q = base.merge('space_w' => r4(w), 'space_l' => r4(l), 'antritt_l' => r4(l - y_ant), 'eye_z' => 0.0)
        exts, xl = landing_ext(plan)
        need_loch = p['loch'] || xl > 1e-6 ||
                    (%w[u_podest z_podest].include?(v) && exts[-1] && exts[-1][1] > 1e-6)
        if need_loch
          q = q.merge(loch_for(p, plan, tr, w, l, xl))
          notes << 'Treppenloch wurde an den Austritt gelegt.' unless p['loch']
        else
          q['loch'] = false
        end
        if v == 'z_podest' && exts.size == 2 && (exts[0][1] - exts[1][0]).abs > 0.05
          notes << 'Beim Einpassen werden die Podestverlängerungen zwischen den Wendungen gleichmäßig verteilt.'
        end
        q = Params.normalize(q)
        full = q.merge('n_steps' => plan.n.to_f, 'a_user' => r4(plan.a), 'b' => r4(plan.b))
        full['gl'] = r4(plan.instance_variable_get(:@gl)) if Params::TURNING.include?(v)
        fl = plan.flights || []
        if Params::PODEST.include?(v)
          full['r1'] = fl[0].to_f
          full['r2'] = fl[1].to_f if v == 'z_podest'
        end
        full['landing_len'] = r4(plan.lines_w[fl[0]] - plan.lines_w[fl[0] - 1]) if v == 'gerade_podest'
        winder_m(plan).each { |k, x| full[k] = x.to_f }
        full = Params.normalize(full)
        return q if same?(plan, q)
        return full unless same?(plan, full)
        relax(plan, full, p, %w[nv m2 m1 r2 r1 landing_len gl b a_user n_steps])
      end

      # Treppenloch so legen, dass seine Kante genau am Austritt (bzw. am Ende des
      # Austrittspodests) liegt. Maße des vorhandenen Treppenlochs bleiben soweit möglich.
      def loch_for(p, plan, tr, w, l, xl)
        le = plan.line(plan.wtot)
        a = tr.(le[:in]); b = tr.(le[:out])
        dir = plan.walk.tangent(plan.wtot)
        along_x = dir[0].abs > dir[1].abs
        xs = [a[0], b[0]]; ys = [a[1], b[1]]
        if along_x
          edge = dir[0] > 0 ? xs.max : xs.min
          room = dir[0] > 0 ? edge : w - edge
          len = [[p['loch_w'].to_f, xl + 20.0].max, room].min
          lat = [[p['loch_l'].to_f, ys.max - ys.min].max, l].min
          lx = dir[0] > 0 ? edge - len : edge
          ly0 = [[ys.min, l - lat].min, 0.0].max
          { 'loch' => true, 'loch_x' => r4(lx), 'loch_w' => r4(len), 'loch_l' => r4(lat),
            'loch_y' => r4(l - ly0 - lat), 'loch_gap' => r4(xl) }
        else
          edge = dir[1] > 0 ? ys.max : ys.min
          room = dir[1] > 0 ? edge : l - edge
          len = [[p['loch_l'].to_f, xl + 20.0].max, room].min
          lat = [[p['loch_w'].to_f, xs.max - xs.min].max, w].min
          lx = p['loch_x'].to_f
          lx = xs.min if lx > xs.min + 1e-6 || lx + lat < xs.max - 1e-6
          lx = [[lx, w - lat].min, 0.0].max
          ly1 = dir[1] > 0 ? edge : edge + len # obere Kante (Richtung hintere Wand)
          { 'loch' => true, 'loch_x' => r4(lx), 'loch_w' => r4(lat), 'loch_l' => r4(len),
            'loch_y' => r4(l - ly1), 'loch_gap' => r4(xl) }
        end
      end
    end
  end
end
