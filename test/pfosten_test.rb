# Stufen im Pfosten (Tasche) und Dübel Wange – Pfosten.
# Prüft: kein Stufenrest tiefer als die Taschentiefe im Pfosten (nur an den
# Flächen, durch die die Stufe hineinläuft), jede eingelassene Stufe hat eine
# Tasche im Pfosten, Taschentiefe 0 = nichts im Pfosten; Dübel in der
# Wangenstirn setzen an der Brettkante an, liegen im Brett und nicht in den
# Nuten, und jeder Wangendübel hat sein Gegenstück im Pfosten.
require_relative 'su_mock'
$LOAD_PATH.unshift File.expand_path('../src', __dir__)
%w[params geometry fit stringers railing builder parts nesting tcn lauf wange3d cnc].each { |f| require "jt_treppenbau/#{f}" }
include JTools::Treppenbau

def edge_dist(poly, q)
  poly.each_with_index.map do |a, i|
    b = poly[i - 1]
    ab = Geo.sub(b, a); l2 = Geo.dot(ab, ab)
    t = l2 < 1e-12 ? 0.0 : [[Geo.dot(Geo.sub(q, a), ab) / l2, 0.0].max, 1.0].min
    Geo.dist(q, Geo.add(a, Geo.mul(ab, t)))
  end.min
end

# größte Eindringtiefe der Fläche poly in den Pfosten q (Raster), gemessen
# von der nächsten Pfostenfläche
def depth_in(poly, q)
  h = q[:s] / 2.0; ax = q[:tg]; ay = Geo.left(ax)
  best = 0.0
  n = 36
  (0..n).each do |i|
    (0..n).each do |j|
      x = -h + q[:s] * i / n; y = -h + q[:s] * j / n
      pt = Geo.add(q[:pt], Geo.add(Geo.mul(ax, x), Geo.mul(ay, y)))
      next unless Railing.inside_poly?(poly, pt) && edge_dist(poly, pt) > 0.02
      best = [best, h - [x.abs, y.abs].max].max
    end
  end
  best
end

fails = 0
cases = 0
%w[gerade gerade_podest l_wendel l_podest u_wendel u_podest z_wendel spindel].each do |v|
  [%w[wange wange], %w[sattel sattel], %w[frei frei], %w[wange sattel]].each do |sl, sr|
    [1.5, 0.0].each do |e|
      cases += 1
      p = Params.normalize(Params.defaults.merge('variant' => v, 'rail' => 'beide', 'side_left' => sl, 'side_right' => sr,
                                                 'risers' => true, 'post_pocket' => e))
      begin
        plan = Layout.compute(p)
      rescue PlanError
        next
      end
      errs = []
      lw = plan.lines_w
      ext = p['nosing'] + p['riser_t']
      posts = Railing.pocket_posts(plan, p)
      st = Builder.stringer_sides(plan, p)
      (0...plan.treads).each do |k|
        top = (k + 1) * plan.h
        raw = plan.region(lw[k], lw[k + 1] + ext).map(&:first)
        cl = Railing.clip_at_posts(plan, p, raw, top - p['tread_t'], top)
        posts.each do |q, _|
          next if [top, q[:ztop]].min - [top - p['tread_t'], q[:zbot]].max < 0.1
          next if Railing.post_square(q).all? { |c| Railing.inside_poly?(raw, c) } # Durchbruch
          dp = depth_in(cl, q)
          errs << format('Stufe %d im Pfosten %s %.2f tief', k + 1, q[:role], dp) if dp > e + 0.15
        end
      end
      parts, = Parts.collect(plan, p, treads: true, risers: true, stringers: true, posts: true, rail: true, einstand: 15.0)
      jn = Parts.post_joinery(plan, p, st, 15.0)
      posts.each do |q, _|
        hit = (0...plan.treads).any? do |k|
          top = (k + 1) * plan.h
          next false if [top, q[:ztop]].min - [top - p['tread_t'], q[:zbot]].max < 0.1
          raw = plan.region(lw[k], lw[k + 1] + ext).map(&:first)
          next false if Railing.post_square(q).all? { |c| Railing.inside_poly?(raw, c) }
          Railing.post_faces(q).any? { |f| Railing.face_intervals(f, raw).any? { |a0, a1| a1 - a0 >= 0.3 } }
        end
        j = jn[q.object_id]
        errs << "Pfosten #{q[:role]}: Stufe ohne Tasche" if hit && (j.nil? || j[:pockets].none? { |t| t[:name].start_with?('Stufe', 'Podest') })
        next unless j
        j[:pockets].each do |t|
          errs << "Pfosten #{q[:role]}: Tasche außerhalb" if t[:a0] < -0.01 || t[:a1] > q[:s] + 0.01 || t[:z0] < -0.01
          errs << "Pfosten #{q[:role]}: Taschentiefe #{t[:depth]}" if (t[:depth] - e).abs > 1e-9
        end
        j[:holes].each do |h|
          errs << "Pfosten #{q[:role]}: Bohrung außerhalb (a=#{h[:a].round(2)})" if h[:a] < 0 || h[:a] > q[:s] || h[:z] < 0 || h[:z] > q[:ztop] - q[:zbot]
        end
      end
      # Dübel in den eingestemmten Wangen
      nd_w = 0
      parts.select { |x| x.kind == :stringer }.each do |x|
        (x.drills || []).select { |h| h[:what] }.each do |h|
          nd_w += 1
          a = [h[:x], h[:y]]
          dv = Tcn.drill_dir(h)
          b = Geo.add(a, Geo.mul(dv, h[:depth]))
          errs << "#{x.label}: Dübel setzt nicht an der Kante an (#{edge_dist(x.poly, a).round(2)} mm)" if edge_dist(x.poly, a) > 0.5
          errs << "#{x.label}: Dübel endet außerhalb" unless Railing.inside_poly?(x.poly, b)
          [0.25, 0.5, 0.75, 1.0].each do |f|
            m = Geo.add(a, Geo.mul(dv, h[:depth] * f))
            errs << "#{x.label}: Dübel in der Nut" if x.pockets.any? { |pk| Railing.inside_poly?(pk, m) }
          end
        end
      end
      # Gegenstücke im Pfosten (sehr kurze Wangenstücke < 25 cm werden nicht exportiert)
      nd_p = Stringers.compute(plan, p)[:wange].select { |b| b[:u1] - b[:u0] >= 25.0 }.sum do |b|
        [[:post0, false], [:post1, true]].sum { |key, ae| b[key] ? Railing.wange_dowels(plan, p, b, ae).size : 0 }
      end
      nd_j = jn.values.sum { |j| j[:holes].count { |h| h[:what].start_with?('Dübel Wange') } }
      nd_all = Stringers.compute(plan, p)[:wange].sum do |b|
        [[:post0, false], [:post1, true]].sum { |key, ae| b[key] ? Railing.wange_dowels(plan, p, b, ae).size : 0 }
      end
      errs << "Dübel im Pfosten #{nd_j}, an den Wangenenden #{nd_all}" if nd_j != nd_all
      errs << "Dübel Wange #{nd_w}, im Pfosten #{nd_p}" if nd_w != nd_p
      p0 = Params.normalize(p.merge('dowel_d' => 0.0))
      plan0 = Layout.compute(p0)
      parts0, = Parts.collect(plan0, p0, treads: true, risers: true, stringers: true, posts: true, rail: true, einstand: 15.0)
      errs << 'Dübel trotz Ø 0' if parts0.any? { |x| (x.drills || []).any? { |h| h[:what] } }
      puts format('%-14s %-6s/%-6s Tasche %.1f: Pfosten %d, Taschen %d, Wangendübel %d %s', v, sl, sr, e, posts.size,
                  jn.values.sum { |j| j[:pockets].size }, nd_w, errs.empty? ? 'ok' : errs.uniq.first(4).join('; '))
      fails += 1 unless errs.empty?
    end
  end
end
puts "#{cases} Fälle, #{fails} Fehler"
exit(fails.zero? ? 0 : 1)
