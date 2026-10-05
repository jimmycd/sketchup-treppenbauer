# CNC-Export der aufgesattelten Wangen (je Wange ein 3D-Programm):
#  * Ausräumen: Fräser (Mitte) nie näher als r an der Wange (Umriss mit dem meisten Material)
#  * Schrägen (Aggregat): Fräser nie im Material, Keil vollständig entfernt,
#    max. 1 mm unter die Unterseite, Tiefe <= nutzbare Länge
#  * Optionen fräsen/markieren × wenden; TCN wird geschrieben
require_relative 'su_mock'
$LOAD_PATH.unshift File.expand_path('../src', __dir__)
%w[params geometry fit stringers builder parts nesting tcn wange3d cnc].each { |f| require "jt_treppenbau/#{f}" }
include JTools::Treppenbau
require 'tmpdir'

def seg_dist(pt, a, b)
  d = Geo.sub(b, a); l2 = Geo.dot(d, d)
  f = l2 < 1e-12 ? 0 : [[Geo.dot(Geo.sub(pt, a), d) / l2, 0].max, 1].min
  Geo.dist(pt, Geo.add(a, Geo.mul(d, f)))
end

def path_poly_dist(path, poly)
  best = 1e9
  path.each_cons(2) do |a, b|
    poly.each_with_index do |p, i|
      q = poly[(i + 1) % poly.size]
      best = [best, seg_dist(p, a, b), seg_dist(q, a, b), seg_dist(a, p, q), seg_dist(b, p, q)].min
      # Schnitt
      d1 = Geo.cross(Geo.sub(b, a), Geo.sub(p, a)); d2 = Geo.cross(Geo.sub(b, a), Geo.sub(q, a))
      d3 = Geo.cross(Geo.sub(q, p), Geo.sub(a, p)); d4 = Geo.cross(Geo.sub(q, p), Geo.sub(b, p))
      best = 0.0 if d1 * d2 < 0 && d3 * d4 < 0
    end
  end
  best
end

def pip(pt, poly)
  c = false; j = poly.size - 1
  poly.each_with_index do |a, i|
    b = poly[j]
    c = !c if (a[1] > pt[1]) != (b[1] > pt[1]) && pt[0] < (b[0] - a[0]) * (pt[1] - a[1]) / (b[1] - a[1]) + a[0]
    j = i
  end
  c
end

fails = 0; n = 0; nb = 0; nw = 0
o0 = Cnc.normalize({})
dir = Dir.mktmpdir
(ARGV[0] ? [ARGV[0]] : Params::NOSPIRAL).each do |v|
  [{}, { 'fit_mode' => 'raum', 'space_l' => 400, 'space_w' => 300, 'angle_left' => 100, 'angle_right' => 80 }].each do |extra|
    %w[rechts links].each do |dr|
      [%w[fraesen false], %w[fraesen true], %w[markieren false], %w[markieren true]].each do |mode, wend|
        p = Params.normalize(Params.defaults.merge('variant' => v, 'direction' => dr, 'risers' => true,
                                                   'side_left' => 'sattel', 'side_right' => 'sattel').merge(extra))
        begin; plan = Layout.compute(p); rescue PlanError; next; end
        o = o0.merge('sat_mode' => mode, 'sat_wenden' => wend == 'true', 'p_treads' => false, 'p_risers' => false, 'p_rail' => false, 'p_posts' => false)
        res = Cnc.compute(plan, p, o)
        n += 1
        errs = []
        res.boards.each do |jb|
          nb += 1
          r = Cnc.outer_tool(o, jb.t)[:d] / 2.0
          jb.programs.each do |pg|
            outline = Wange3d.outline_on(jb.sb_ctx, jb.outline, pg.side == 2)
            pg.ops.each do |kind, pts|
              next unless kind == :clear
              d = path_poly_dist(pts, outline)
              errs << "#{jb.label} S#{pg.side} Ausräumen #{d.round(2)} mm an der Wange" if d < r - 0.05
              errs << "#{jb.label} S#{pg.side} Ausräumen im Teil" if pts.any? { |q| pip(q, outline) }
            end
            pg.faces.each do |fc|
              nw += 1
              xb = fc[:xb]; xt = fc[:xt]; t = fc[:t]; rr = fc[:r]
              line_a = [xb, 0.0]; line_b = [xt, t]
              fc[:paths].each do |seq, depth|
                errs << "#{jb.label} Tiefe #{-depth} > Werkzeug" if -depth > o['agg_len'] + 1e-6
                seq.each_cons(2) do |a, b|
                  # Abstand der Bahn zur Wandgeraden (Luftseite) >= r
                  nn = Geo.norm([-(t), xt - xb]); nn = Geo.mul(nn, -1) if nn[0] * fc[:msign] > 0
                  [a, b].each do |q|
                    sd = Geo.dot(Geo.sub(q, line_a), nn)
                    errs << "#{jb.label} Aggregat im Material (#{sd.round(2)})" if sd < rr - 0.01
                    errs << "#{jb.label} Aggregat #{(rr - q[1]).round(1)} mm unter Brett" if q[1] < rr - 1.01
                  end
                end
              end
              # Keil (zwischen senkrechtem Schnitt bei xb und der Wand) abgedeckt?
              seq = fc[:paths][-1][0]
              20.times do |i|
                20.times do |k|
                  z = t * (i + 0.5) / 20; fr = (k + 0.5) / 20
                  xw = xb + (xt - xb) * z / t
                  x = xb + (xw - xb) * fr
                  next if z < 5.0   # Spitze des Keils an der Unterseite (Fräser max. 1 mm tiefer)
                  ok = seq.each_cons(2).any? { |a, b| seg_dist([x, z], a, b) <= rr + 0.01 }
                  (errs << "#{jb.label} Keilrest bei (#{x.round(1)}, #{z.round(1)})"; break) unless ok
                end
              end
            end
          end
        end
        files = Cnc.export(dir, "t", res, o)
        errs << 'keine TCN' if res.boards.any? && files.none? { |f| f.include?('_Wange_') }
        fails += 1 unless errs.empty?
        puts format('%-14s %-5s %-6s %-9s wenden=%-5s Wangen %2d Programme %2d Schrägen %3d %s', v, extra.empty? ? 'frei' : 'raum', dr, mode, wend,
                    res.boards.size, res.boards.sum { |b| b.programs.size }, res.boards.sum { |b| b.programs.sum { |pg| pg.faces.size } },
                    errs.empty? ? 'ok' : 'FEHLER ' + errs.uniq.first(3).join(' | '))
      end
    end
  end
end
puts "#{n} Fälle, #{nb} Wangen, #{nw} Schrägen, #{fails} Fehler"
