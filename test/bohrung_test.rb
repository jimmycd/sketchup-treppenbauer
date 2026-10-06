# Geländerstäbe rund/quadratisch: Bohrungen in Trittstufen (Stäbe auf den
# Stufen) und eingestemmten Wangen (Oberkante, schräg zur Kante) bis in die
# TCN-Datei. Prüft: Ø = Stabmaß, jede Bohrung genau einmal im TCN, Bohrungen
# von oben im Teil, Wangenbohrung setzt an der Teilkante an und läuft hinein.
require_relative 'su_mock'
$LOAD_PATH.unshift File.expand_path('../src', __dir__)
%w[params geometry fit stringers railing builder parts nesting tcn lauf wange3d cnc].each { |f| require "jt_treppenbau/#{f}" }
include JTools::Treppenbau
Dir.mkdir('out') unless Dir.exist?('out')

def inside?(poly, q)
  c = false
  poly.each_with_index do |a, i|
    b = poly[i - 1]
    c = !c if (a[1] > q[1]) != (b[1] > q[1]) && q[0] < (b[0] - a[0]) * (q[1] - a[1]) / (b[1] - a[1]) + a[0]
  end
  c
end

def edge_dist(poly, q)
  poly.each_with_index.map do |a, i|
    b = poly[i - 1]
    ab = Geo.sub(b, a); l2 = Geo.dot(ab, ab)
    t = l2 < 1e-12 ? 0.0 : [[Geo.dot(Geo.sub(q, a), ab) / l2, 0.0].max, 1.0].min
    Geo.dist(q, Geo.add(a, Geo.mul(ab, t)))
  end.min
end

fails = 0
cases = 0
%w[gerade l_wendel u_podest z_wendel].each do |v|
  [%w[wange wange], %w[sattel sattel], %w[wange sattel]].each do |sl, sr|
    [['quadrat', 2.5], ['rund', 3.0]].each do |shape, dd|
      %w[bohren markieren].each do |mode|
        cases += 1
        p = Params.normalize(Params.defaults.merge('variant' => v, 'construction' => 'wange', 'rail' => 'beide',
                                                   'side_left' => sl, 'side_right' => sr, 'risers' => true,
                                                   'bal_shape' => shape, 'bal_d' => dd, 'bal_dia' => dd))
        plan = Layout.compute(p)
        o = Cnc.normalize('drill_wange' => mode, 'plate_l' => 5200)
        res = Cnc.compute(plan, p, o)
        errs = []
        bars = Railing.compute(plan, p)[:sides].flat_map { |sd| sd[:bars] }
        errs << 'keine Stäbe' if bars.empty?
        errs << 'Stabform falsch' unless bars.all? { |b| b[:shape] == shape && (b[:d] - dd).abs < 1e-9 }
        nb = 0
        # Wangen und Handläufe: eigener Rohling (Teilkoordinaten), ggf. zwei Läufe
        own = res.longs.map { |lp| Struct.new(:part, :poly, :drills).new(lp.part, lp.part.poly, lp.part.drills) }
        res.longs.each do |lp|
          tcn = lp.split[:runs].flat_map { |rn| Tcn.build_prog(rn.prog) }
          nd = (lp.part.drills || []).size
          nh = (lp.part.drills || []).count { |h| h[:ang] }
          w81 = tcn.count { |l| l.start_with?('W#81{') }
          exp = mode == 'markieren' ? nd - nh : nd
          errs << "#{lp.label}: #{w81} Bohrblöcke statt #{exp}" if w81 != exp
          gs = tcn.count { |l| l.start_with?('GSIDE#') }
          errs << "#{lp.label}: Hilfsflächen #{gs} statt #{mode == 'bohren' ? nh : 0}" if gs != (mode == 'bohren' ? nh : 0)
        end
        ([Struct.new(:placements).new(own)] + res.sheets).each_with_index do |sh, si|
          sh.placements.each do |pl|
            (pl.drills || []).each do |h|
              nb += 1
              errs << "#{pl.part.label}: Ø #{h[:d]}" if (h[:d] - dd * 10).abs > 1e-6
              if h[:ang]
                errs << "#{pl.part.label}: Ansatz nicht an der Kante (#{edge_dist(pl.poly, [h[:x], h[:y]]).round(2)} mm)" if edge_dist(pl.poly, [h[:x], h[:y]]) > 0.5
                dv = Tcn.drill_dir(h)
                m = Geo.add([h[:x], h[:y]], Geo.mul(dv, h[:depth] / 2.0))
                errs << "#{pl.part.label}: Bohrung läuft nicht ins Teil" unless inside?(pl.poly, m)
              else
                errs << "#{pl.part.label}: Bohrung außerhalb" unless inside?(pl.poly, [h[:x], h[:y]])
              end
            end
          end
          next if si.zero?
          tcn = Tcn.build(sh.placements, length: o['plate_l'], width: o['plate_w'], thickness: sh.thickness,
                                         tool_outer: sh.tool[:nr], overcut: 1, climb: true, deco_tool: 1400, deco_depth: 2,
                                         engrave: false, text_h: 30, pocket_tool: 1400, pocket_d: 10,
                                         drill_tool: 0, hdrill_tool: 0, drill_wange: mode, drill_clear: 5)
          nd = sh.placements.sum { |pl| (pl.drills || []).size }
          nh = sh.placements.sum { |pl| (pl.drills || []).count { |h| h[:ang] } }
          w81 = tcn.count { |l| l.start_with?('W#81{') }
          exp = mode == 'markieren' ? nd - nh : nd
          errs << "#{sh.thickness} mm: #{w81} Bohrblöcke statt #{exp}" if w81 != exp
          gs = tcn.count { |l| l.start_with?('GSIDE#') }
          errs << "Hilfsflächen #{gs} statt #{mode == 'bohren' ? nh : 0}" if gs != (mode == 'bohren' ? nh : 0)
          ws = tcn.join("\n").scan(/WS=(\d+)/).flatten.map(&:to_i)
          errs << 'WS nicht fortlaufend' unless ws.sort == (1..ws.size).to_a
        end
        # je Stab genau eine Bohrung (Stufe bzw. Wange), sofern ein Teil existiert
        want = bars.count { |b| b[:drill] && b[:ztop] - b[:zbot] >= 2 }
        errs << "Bohrungen #{nb}, Stäbe mit Bohrung #{want}" if nb > want || nb < want * 0.9
        round_w = res.warnings.any? { |w| w.start_with?('Runde Geländerstäbe') }
        errs << 'Hinweis runde Stäbe fehlt' if shape == 'rund' && !round_w
        errs << 'runde Stäbe als Plattenteil' if shape == 'rund' && res.parts.any? { |pt| pt.kind == :bar }
        unless errs.empty?
          fails += 1
          puts "#{v} #{sl}/#{sr} #{shape} #{mode}: #{errs.uniq.first(4).join('; ')}"
        end
      end
    end
  end
end
puts "Bohrungen: #{cases} Fälle, #{fails} fehlerhaft"
