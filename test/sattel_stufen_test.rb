# Aufgesattelte Wangen: keine Durchdringung von Wange und Tritt-/Setzstufen
# (auch im Wendelbereich, wo die Stufenkanten schräg über das Brett laufen),
# und volles Auflager: unter jeder Trittstufe liegt die Wange an (Abstand 0).
# Das Brett ist ein Körper aus zwei Flächenumrissen (b[:faces]); geprüft wird
# an 5 Schnitten über die Dicke.
require_relative 'su_mock'
$LOAD_PATH.unshift File.expand_path('../src', __dir__)
%w[params geometry fit stringers builder parts].each { |f| require "jt_treppenbau/#{f}" }
include JTools::Treppenbau

def pip(pt, poly)
  c = false; j = poly.size - 1
  poly.each_with_index do |a, i|
    b = poly[j]
    if (a[1] > pt[1]) != (b[1] > pt[1]) && pt[0] < (b[0] - a[0]) * (pt[1] - a[1]) / (b[1] - a[1]) + a[0]
      c = !c
    end
    j = i
  end
  c
end

# Oberkante des Umrisses an der Stelle u (größte Höhe)
def top_at(poly, u)
  zs = []
  poly.each_with_index do |a, i|
    b = poly[(i + 1) % poly.size]
    next if (a[0] - b[0]).abs < 1e-9
    next unless u >= [a[0], b[0]].min && u <= [a[0], b[0]].max
    zs << a[1] + (b[1] - a[1]) * (u - a[0]) / (b[0] - a[0])
  end
  zs.max
end

def section(b, f)
  return b[:poly] unless b[:faces]
  w = f + 0.5
  b[:faces][0].each_with_index.map { |q, i| r = b[:faces][1][i]; [q[0] + (r[0] - q[0]) * w, q[1] + (r[1] - q[1]) * w] }
end

def check(plan, p, r)
  lw = plan.lines_w; h = plan.h; d = p['tread_t'].to_f
  ext = p['nosing'].to_f + (p['risers'] ? p['riser_t'].to_f : 0.0)
  bodies = (0...plan.treads).map { |k| [plan.region(lw[k], lw[k + 1] + ext).map(&:first), (k + 1) * h - d, "T#{k + 1}"] }
  if p['risers']
    (0...plan.treads).each do |k|
      wa = lw[k] + p['nosing'].to_f
      bodies << [plan.region(wa, wa + p['riser_t'].to_f).map(&:first), k * h, "R#{k + 1}"]
    end
  end
  worst = [0.0, nil]
  nofaces = r[:sattel].count { |b| b[:faces].nil? }
  r[:sattel].each do |b|
    nrm = Geo.right(b[:dir])
    [-0.499, -0.25, 0.0, 0.25, 0.499].each do |f|
      sec = section(b, f)
      us = sec.map(&:first)
      u0, u1 = us.minmax
      nu = ((u1 - u0) / 0.2).ceil
      (0..nu).each do |i|
        u = u0 + (u1 - u0) * (i + 0.5) / (nu + 1)
        zt = top_at(sec, u) or next
        q = Geo.add(Geo.add(b[:origin], Geo.mul(b[:dir], u)), Geo.mul(nrm, f * b[:t]))
        bodies.each do |poly, zb, name|
          next unless zt > zb + 0.02 && pip(q, poly) && [-0.03, 0.03].all? { |e| pip(Geo.add(q, Geo.mul(b[:dir], e)), poly) }
          worst = [zt - zb, "#{b[:which]} #{b[:nr]} / #{name} u=#{u.round(1)} f=#{f}"] if zt - zb > worst[0]
        end
      end
    end
  end
  [worst, nofaces]
end

fails = 0; n = 0; falz = 0
(ARGV[0] ? [ARGV[0]] : %w[gerade kurve]).each do |form|
  (ARGV[1] ? [ARGV[1]] : %w[stumpf]).each do |joint|
    Params::NOSPIRAL.each do |v|
      [{}, { 'fit_mode' => 'raum', 'space_l' => 350, 'space_w' => 260, 'angle_left' => 84 },
       { 'fit_mode' => 'raum', 'space_l' => 400, 'space_w' => 300, 'angle_left' => 100, 'angle_right' => 80 }].each do |extra|
        %w[rechts links].each do |dir|
          [true, false].each do |ris|
            p = Params.normalize(Params.defaults.merge('variant' => v, 'direction' => dir, 'risers' => ris, 'sat_joint' => joint,
                                                       'side_left' => 'sattel', 'side_right' => 'sattel', 'str_form' => form).merge(extra))
            begin; plan = Layout.compute(p); rescue PlanError; next; end
            r = Stringers.compute(plan, p)
            (dep, where), nof = check(plan, p, r)
            ok = dep < 0.05 && nof == 0
            n += 1; fails += 1 unless ok
            puts format('%-6s %-7s %-14s %-5s %-6s ris=%-5s Eindringen %.2f ohne Flächen %d %s %s', form, joint, v,
                        extra.empty? ? 'frei' : "raum#{extra['angle_left']}", dir, ris, dep, nof, ok ? 'ok' : 'FEHLER', ok ? '' : where)
          end
        end
      end
    end
  end
end
puts "#{n} Fälle, #{fails} Fehler"
