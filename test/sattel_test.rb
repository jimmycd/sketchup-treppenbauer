# Aufgesattelte Wangen: Restbreite, Anschluss der Unterkante an Ecken,
# keine Durchdringung der Bretter im Grundriss.
require_relative 'su_mock'
$LOAD_PATH.unshift File.expand_path('../src', __dir__)
%w[params geometry fit stringers builder parts].each { |f| require "jt_treppenbau/#{f}" }
include JTools::Treppenbau

def rect(b)
  n = Geo.right(b[:dir]); h = b[:t] / 2.0
  e = Geo.add(b[:origin], Geo.mul(b[:dir], b[:len]))
  [Geo.add(b[:origin], Geo.mul(n, -h)), Geo.add(e, Geo.mul(n, -h)), Geo.add(e, Geo.mul(n, h)), Geo.add(b[:origin], Geo.mul(n, h))]
end

# Eindringtiefe zweier konvexer Vierecke (SAT), <= 0: keine Überlappung
def overlap(p, q)
  depth = 1e9
  [p, q].each do |poly|
    poly.each_with_index do |a, i|
      b = poly[(i + 1) % poly.size]
      ax = Geo.norm([-(b[1] - a[1]), b[0] - a[0]])
      pp = p.map { |x| Geo.dot(x, ax) }; qq = q.map { |x| Geo.dot(x, ax) }
      depth = [depth, [pp.max, qq.max].min - [pp.min, qq.min].max].min
    end
  end
  depth
end

def seg_dist(pt, a, b)
  d = Geo.sub(b, a); l2 = Geo.dot(d, d)
  f = l2 < 1e-12 ? 0 : [[Geo.dot(Geo.sub(pt, a), d) / l2, 0].max, 1].min
  Geo.dist(pt, Geo.add(a, Geo.mul(d, f)))
end

def bottom_at(b, u)
  bot = b[:poly].each_cons(2).select { |(u1, z1), (u2, z2)| u2 < u1 - 1e-9 } # Unterkante läuft rückwärts
  bot.each { |(u1, z1), (u2, z2)| return z1 + (z2 - z1) * (u - u1) / (u2 - u1) if u <= u1 + 1e-6 && u >= u2 - 1e-6 }
  nil
end

fails = 0; n = 0
Params::NOSPIRAL.each do |v|
  [{}, { 'fit_mode' => 'raum', 'space_l' => 350, 'space_w' => 260, 'angle_left' => 84 },
   { 'fit_mode' => 'raum', 'space_l' => 400, 'space_w' => 300, 'angle_left' => 100, 'angle_right' => 80 }].each do |extra|
    %w[rechts links].each do |dir|
      [true, false].each do |ris|
        p = Params.normalize(Params.defaults.merge('variant' => v, 'direction' => dir, 'risers' => ris,
                                                   'side_left' => 'sattel', 'side_right' => 'sattel').merge(extra))
        begin; plan = Layout.compute(p); rescue PlanError => e; next; end
        r = Stringers.compute(plan, p)
        rest = p['sat_rest'].to_f
        minrest = 1e9; jmax = 0.0; ov = 0.0
        r[:sattel].each do |b|
          poly = b[:poly]
          botsegs = poly.each_cons(2).select { |(u1, z1), (u2, z2)| u2 < u1 - 1e-9 && [z1, z2].min > 0.01 }
          poly.each_cons(2) do |(u1, z1), (u2, z2)|
            next unless (u2 - u1).abs < 1e-6 && z2 > z1 + 1e-6 # innere Ecke der Ausklinkung
            botsegs.each { |a, c| minrest = [minrest, seg_dist([u1, z1], a, c)].min }
          end
        end
        r[:sattel].each_cons(2) do |a, b|
          next unless a[:which] == b[:which]
          ov = [ov, overlap(rect(a), rect(b))].max
          next if Geo.cross(a[:dir], b[:dir]).abs < 0.02
          za = bottom_at(a, a[:len]); zb = bottom_at(b, 0.0)
          jmax = [jmax, (za - zb).abs].max if za && zb && za > 0.01 && zb > 0.01
        end
        ok = minrest >= rest - 1e-3 && jmax < 0.05 && ov < 0.01
        n += 1
        fails += 1 unless ok
        puts format('%-14s %-5s %-6s ris=%-5s boards=%2d rest min %.2f fuge %.3f überlappung %.3f %s', v,
                    extra.empty? ? 'frei' : "raum#{extra['angle_left']}", dir, ris, r[:sattel].size, minrest == 1e9 ? 0 : minrest, jmax, ov, ok ? 'ok' : 'FEHLER')
      end
    end
  end
end
puts "#{n} Fälle, #{fails} Fehler"
