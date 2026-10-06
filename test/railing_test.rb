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
                                                 'side_left' => sl, 'side_right' => sr, 'risers' => true))
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
        posts.each_cons(2) do |pa, pb|
          ua = pa[:u] + pa[:s] / 2; ub = pb[:u] - pb[:s] / 2
          bs = sd[:bars].select { |b| b[:u] > ua && b[:u] < ub }.sort_by { |b| b[:u] }
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
        errs << "#{sd[:which]}: Stab über Handlauf" if sd[:bars].any? { |b| b[:ztop] <= b[:zbot] }
        errs << "#{sd[:which]}: kein Handlauf" if sd[:rails].empty?
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
