# Geländer: Pfosten (Antritt, Austritt, Laufwechsel), Stäbe (lichter Abstand,
# Lage auf den Stufen bzw. Bohrung in der Wange), Handlauf von Pfosten zu Pfosten.
require_relative 'su_mock'
$LOAD_PATH.unshift File.expand_path('../src', __dir__)
%w[params geometry fit stringers railing builder parts].each { |f| require "jt_treppenbau/#{f}" }
include JTools::Treppenbau
fails = 0
verbose = ARGV.include?('-v')
Params::ALL.each do |v|
  [%w[wange wange], %w[sattel sattel], %w[frei frei], %w[wange sattel]].each do |sl, sr|
    %w[rechts links].each do |dir|
      p = Params.normalize(Params.defaults.merge('variant' => v, 'direction' => dir, 'rail' => 'beide',
                                                 'side_left' => sl, 'side_right' => sr, 'risers' => true,
                                                 'str_form' => ENV['FORM'] || 'gerade'))
      begin
        plan = Layout.compute(p)
      rescue PlanError => e
        puts "#{v} #{sl}/#{sr} #{dir}: #{e.message}"
        next
      end
      rr = Railing.compute(plan, p)
      errs = []
      rr[:sides].each do |sd|
        posts = sd[:posts]
        roles = posts.map { |q| q[:role] }
        errs << "#{sd[:which]}: Antritt/Austritt fehlt" unless roles.first == :antritt && roles.last == :austritt
        nturn = Railing.corners(sd[:poly]).size
        errs << "#{sd[:which]}: Ecken #{nturn}, Eckpfosten #{roles.count(:ecke)}" if !plan.spiral && roles.count(:ecke) != nturn
        # lichter Abstand
        sd[:spans].each do |sp|
          ua = sp[:ua]; ub = sp[:ub]
          bs = (sd[:bars] + sd[:mids].map { |q| q.merge(d: q[:s]) }).select { |b| b[:u] > ua && b[:u] < ub }.sort_by { |b| b[:u] }
          e = [ua] + bs.flat_map { |b| [b[:u] - b[:d] / 2, b[:u] + b[:d] / 2] } + [ub]
          g = e.each_slice(2).map { |a, b| b - a }.max
          errs << format('%s: Lücke %.1f', sd[:which], g) if g > p['bal_gap'] + 0.05 && sd[:mount] == :wange
        end
        # Stäbe auf Stufen: Mindestabstand zu den Stufenkanten
        if sd[:mount] == :stufe
          sd[:bars].each do |b|
            k = b[:tread]
            a = Railing.axis_u(plan, sd, plan.lines_w[k]); c = Railing.axis_u(plan, sd, plan.lines_w[k + 1])
            m = [b[:u] - b[:d] / 2 - a, c - b[:u] - b[:d] / 2].min
            errs << format('%s: Stab Stufe %d Randabstand %.2f', sd[:which], k + 1, m) if m < p['bal_edge'] - 1e-6
            errs << format('%s: Stab Stufe %d Höhe', sd[:which], k + 1) if (b[:zbot] + b[:drill].to_h.fetch(:depth, 0) - (k + 1) * plan.h).abs > 1e-6
          end
        else
          sd[:bars].each do |b|
            zt = Stringers.top_at(plan, p, sd[:which], b[:u])
            errs << format('%s: Stab ohne Wange bei u=%.1f', sd[:which], b[:u]) unless zt
          end
        end
        # Pfosten als Zwischenstück: Wangenbretter enden an den Pfostenflächen,
        # kein Brett ragt in einen Pfosten
        if sd[:mount] == :wange
          t = p['str_t']
          bds = Stringers.compute(plan, p)[:wange].select { |b| b[:which] == sd[:which] }
          sd[:posts].each do |q|
            ax = q[:tg]; ay = Geo.left(ax); hs = q[:s] / 2.0
            inside = lambda do |pt|
              d = Geo.sub(pt, q[:pt])
              Geo.dot(d, ax).abs < hs - 0.05 && Geo.dot(d, ay).abs < hs - 0.05
            end
            touch = 0
            bds.each do |b|
              n = Stringers.seg_n(b, b[:side])
              [0.02, 0.25, 0.5, 0.75, 0.98].each do |f|
                [0.1, 0.5, 0.9].each do |g|
                  pt = Geo.add(Geo.add(b[:base][0], Geo.mul(b[:dir], f * (b[:u1] - b[:u0]))), Geo.mul(n, g * t))
                  errs << format('%s: Brett ragt in Pfosten %s', sd[:which], q[:role]) if inside.(pt)
                end
              end
              [[b[:u0], b[:base][0]], [b[:u1], b[:base][-1]]].each do |_u, e|
                c = Geo.add(e, Geo.mul(n, t / 2.0))
                d = Geo.sub(c, q[:pt])
                touch += 1 if (Geo.dot(d, ax).abs - hs).abs < 0.05 && Geo.dot(d, ay).abs < hs + 0.05 ||
                              (Geo.dot(d, ay).abs - hs).abs < 0.05 && Geo.dot(d, ax).abs < hs + 0.05
              end
            end
            need = %i[antritt austritt].include?(q[:role]) ? 1 : 2
            errs << format('%s: an Pfosten %s enden %d Bretter (erwartet %d)', sd[:which], q[:role], touch, need) if touch != need
          end
        end
        errs << "#{sd[:which]}: Stab über Handlauf" if sd[:bars].any? { |b| b[:ztop] <= b[:zbot] }
        errs << "#{sd[:which]}: kein Handlauf" if sd[:rails].empty?
        # Handlauf: Oberkante nie unter Handlaufhöhe über den Stufenkanten,
        # Breite = Wangendicke, Stäbe enden an der Unterkante
        sd[:rails].each do |rl|
          sd[:keys].each_with_index do |k, i|
            next unless k > rl[:ua] + 0.01 && k < rl[:ub] - 0.01
            zt = Railing.rail_top(sd, k)
            errs << format('%s: Handlauf %.2f unter Sollhöhe', sd[:which], sd[:zs][i] - zt) if zt < sd[:zs][i] - 1e-3
          end
          errs << "#{sd[:which]}: Handlaufbreite" if sd[:mount] == :wange && (rl[:w] - p['str_t']).abs > 1e-6
        end
        # Stäbe oben in den Handlauf gebohrt
        rd = [p['bal_depth'], p['rail_hh'] - 1.0].min
        sd[:bars].each do |b|
          errs << "#{sd[:which]}: Stab nicht im Handlauf" if (b[:ztop] - (Railing.rail_top(sd, b[:u]) - p['rail_hh'] + rd)).abs > 1e-6
          errs << "#{sd[:which]}: Handlaufbohrung fehlt" unless b[:rdrill] && sd[:rails].any? { |rl| rl[:drills].any? { |h| h[:u] == b[:u] } }
        end
        # Handlauf endet an den Pfostenflächen (auch an Ecken, Achse versetzt)
        sd[:rails].each_with_index do |rl, i|
          [[rl[:pts][0], sd[:posts][i]], [rl[:pts][-1], sd[:posts][i + 1]]].each do |pt, q|
            ax = q[:tg]; ay = Geo.left(ax); dd = Geo.sub(pt, q[:pt])
            x = Geo.dot(dd, ax).abs; y = Geo.dot(dd, ay).abs; hs = q[:s] / 2
            ok = ((x - hs).abs < 0.05 && y <= hs + 0.05) || ((y - hs).abs < 0.05 && x <= hs + 0.05)
            errs << format('%s: Handlauf endet nicht am Pfosten %s (%.1f/%.1f)', sd[:which], q[:role], x, y) unless ok
          end
        end
        # Zwischenpfosten: in jedem Feld länger als rail_mid, unter dem Handlauf,
        # kein Stab im Pfosten
        sd[:spans].each do |sp|
          n = sd[:mids].count { |q| q[:u] > sp[:ua] && q[:u] < sp[:ub] }
          errs << "#{sd[:which]}: Zwischenpfosten #{n}" if n != (sp[:ub] - sp[:ua] > p['rail_mid'] ? 1 : 0)
        end
        sd[:mids].each do |q|
          errs << "#{sd[:which]}: Zwischenpfosten über Handlauf" if q[:ztop] > Railing.rail_top(sd, q[:u] + q[:s] / 2) - p['rail_hh'] + 1e-6 &&
                                                                     q[:ztop] > Railing.rail_top(sd, q[:u] - q[:s] / 2) - p['rail_hh'] + 1e-6
          errs << "#{sd[:which]}: Zwischenpfosten zu kurz" if q[:ztop] - q[:zbot] < 20
          errs << "#{sd[:which]}: Stab im Zwischenpfosten" if sd[:bars].any? { |b| (b[:u] - q[:u]).abs < (q[:s] + b[:d]) / 2 }
        end
        # aufgesattelte Wange: Antritts-/Austrittspfosten in der Treppe, Wange
        # beginnt bzw. endet an der Pfostenfläche
        if Params.side_kind(p, sd[:which], plan.outer_side, !plan.spiral.nil?) == 'sattel'
          a = sd[:posts][0]; e = sd[:posts][-1]
          errs << "#{sd[:which]}: Antrittspfosten nicht in der Treppe" if (a[:u] - (sd[:keys][0] + a[:s] / 2)).abs > 1e-6
          errs << "#{sd[:which]}: Austrittspfosten nicht in der Treppe" if (e[:u] - (sd[:keys][-1] - e[:s] / 2)).abs > 1e-6
          sb = Stringers.compute(plan, p)[:sattel].select { |b| b[:which] == sd[:which] }
          unless sb.empty?
            first = sb.min_by { |b| b[:nr] }
            dpt = Geo.sub(first[:origin], a[:pt])
            errs << format('%s: aufgesattelte Wange beginnt nicht am Pfosten (%.2f)', sd[:which], Geo.dot(dpt, a[:tg]) - a[:s] / 2) if (Geo.dot(dpt, a[:tg]) - a[:s] / 2).abs > 0.05
            errs << "#{sd[:which]}: Austrittspfosten über der Wangenunterkante" if e[:zbot] > Railing.sattel_bot_end(plan, p, sd[:which]) + 1e-6
          end
        end
      end
      tag = "#{v} #{sl}/#{sr} #{dir}"
      info = rr[:sides].map { |sd| "#{sd[:which]}(#{sd[:mount]}): #{sd[:posts].size} Pf, #{sd[:bars].size} St" }.join('; ')
      if errs.empty?
        puts "ok   #{tag}  #{info}" if verbose
      else
        fails += 1
        puts "FEHL #{tag}  #{info}\n     #{errs.uniq.first(4).join("\n     ")}"
      end
      puts "     Warnung: #{rr[:warnings].join(' | ')}" if verbose && !rr[:warnings].empty?
    end
  end
end
puts fails.zero? ? 'Geländer: alles ok' : "Geländer: #{fails} Fehler"
exit(fails.zero? ? 0 : 1)
