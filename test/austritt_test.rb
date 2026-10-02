# encoding: UTF-8
# fehler.md Nr. 5: Abstand des Austritts vom Rand des Treppenlochs -> Austrittspodest.
# Prüft: letzte Steigung endet genau loch_gap vor der Lochkante, Podest auf Höhe H
# reicht bis an die Lochkante, Podestbreite = Laufbreite, Körper geschlossen.
require_relative 'su_mock'
$LOAD_PATH.unshift File.expand_path('../src', __dir__)
%w[params geometry fit stringers builder parts].each { |f| require "jt_treppenbau/#{f}" }
include JTools::Treppenbau
TOL = 0.05
LOCH = {
  'gerade' => [440, 100, { 'loch_l' => 280, 'loch_w' => 100, 'loch_y' => 20 }],
  'gerade_podest' => [580, 100, { 'loch_l' => 300, 'loch_w' => 100, 'loch_y' => 20 }],
  'l_podest' => [300, 280, { 'loch_l' => 100, 'loch_w' => 200, 'loch_x' => 40 }],
  'l_wendel' => [270, 250, { 'loch_l' => 100, 'loch_w' => 200, 'loch_x' => 20 }],
  'u_podest' => [290, 210, { 'loch_l' => 250, 'loch_w' => 210 }],
  'u_wendel' => [260, 210, { 'loch_l' => 230, 'loch_w' => 210 }],
  'z_podest' => [240, 300, { 'loch_l' => 220, 'loch_w' => 300 }],
  'z_wendel' => [240, 260, { 'loch_l' => 220, 'loch_w' => 260 }]
}
def edge_of(v, loch, gap)
  xs = loch.map(&:first); ys = loch.map(&:last)
  case v
  when 'gerade', 'gerade_podest' then [1, ys.max - gap, ys.max]
  when 'l_podest', 'l_wendel' then [0, nil, nil] # x-Kante, abhängig von Spiegelung
  else [1, ys.min + gap, ys.min]
  end
end
def leaf_groups(ents, path = [], acc = [])
  ents.items.grep(Sketchup::Group).each do |g|
    if g.entities.items.grep(Sketchup::Group).empty? then acc << [path + [g.name], g]
    else leaf_groups(g.entities, path + [g.name], acc) end
  end
  acc
end
def closed_errors(defn)
  leaf_groups(defn.entities).filter_map do |path, g|
    faces = g.entities.items.grep(Sketchup::Face)
    next if faces.empty?
    nonman = g.entities.items.grep(Sketchup::Edge).count { |e| e.faces.size != 2 }
    "#{path.join('/')} offen (#{nonman})" if nonman > 0
  end
end
CONS = [['wange', 'gerade', 'wange', 'sattel'], ['wange', 'kurve', 'wange', 'wange'], ['wange', 'kurve', 'sattel', 'frei'], ['holm', 'gerade', 'wange', 'wange'], ['massiv', 'gerade', 'wange', 'wange']]
err = 0; ok = 0; rej = 0; ci = 0
LOCH.each do |v, (l, w, ex)|
  %w[rechts links].each do |dir|
    [0, 15, 40].each do |gap|
      [{}, { 'antritt_l' => l + 20 }, { 'angle_left' => 86 }].each do |more|
        p = Params.normalize(Params.defaults.merge('variant' => v, 'fit_mode' => 'raum', 'space_l' => l, 'space_w' => w, 'loch' => true,
                                                   'direction' => dir, 'loch_gap' => gap, 'risers' => true, 'rail' => 'beide',
                                                   'construction' => CONS[ci % CONS.size][0], 'str_form' => CONS[ci % CONS.size][1],
                                                   'side_left' => CONS[ci % CONS.size][2], 'side_right' => CONS[ci % CONS.size][3]).merge(ex).merge(more))
        ci += 1
        begin
          plan = Layout.compute(p)
        rescue PlanError => e
          rej += 1
          puts format('  (nicht lösbar) %-13s %-6s gap=%-3d %s: %s', v, dir, gap, more.keys.join(','), e.message)
          next
        end
        msgs = []
        loch = plan.space[:loch]
        xs = loch.map(&:first); ys = loch.map(&:last)
        le = plan.line(plan.lines_w[plan.n - 1]) # Austrittskante (letzte Steigung)
        lf = plan.line(plan.wtot)                 # Ende (Lochkante)
        ax, pos, full = edge_of(v, loch, gap)
        if %w[l_podest l_wendel].include?(v)
          mirror = dir == 'links'
          full = mirror ? xs.min : xs.max
          pos = mirror ? full + gap : full - gap
          ax = 0
        end
        [le[:in], le[:out]].each { |q| msgs << format('Austrittskante %.2f statt %.2f', q[ax], pos) if (q[ax] - pos).abs > TOL }
        [lf[:in], lf[:out]].each { |q| msgs << format('Podestende %.2f statt %.2f', q[ax], full) if (q[ax] - full).abs > TOL }
        nl = plan.lines_w.size
        if gap > 0
          msgs << "Podest fehlt (#{nl} Linien)" unless nl == plan.n + 1 && plan.kinds[-1] == :landing
          msgs << 'Podesthöhe' unless (plan.nose_z(plan.treads - 1) - plan.H).abs < 1e-6
        else
          msgs << "unerwartetes Podest (#{nl} Linien)" unless nl == plan.n
        end
        hd = Fit.headroom(plan, p, loch)
        # Volumenkörper bauen
        model = Sketchup::Model.new
        defn = Sketchup::ComponentDefinition.new(model)
        begin
          Builder.build(defn, p)
          msgs.concat(closed_errors(defn))
          if gap > 0
            pod = leaf_groups(defn.entities).find { |pth, _| pth[-1] == "Podest #{plan.treads}" }
            if pod
              zmax = pod[1].entities.items.grep(Sketchup::Face).flat_map { |fc| fc.pts.map { |q| q.z * 2.54 } }.max
              msgs << format('Austrittspodest Oberkante %.2f statt %.2f', zmax, plan.H) if (zmax - plan.H).abs > 0.01
            else
              msgs << 'Austrittspodest nicht gebaut'
            end
          end
        rescue StandardError => e
          msgs << "Build: #{e.class} #{e.message} #{e.backtrace.first}"
        end
        if p['construction'] == 'wange'
          r = Stringers.compute(plan, p)
          msgs << "Wange: #{r[:warnings].join}" unless r[:warnings].empty?
        end
        msgs << format('Kopffreiheit %.1f', hd[0]) if hd && hd[0] < 0
        if msgs.empty? then ok += 1
        else err += 1; puts "FEHLER #{v} #{dir} gap=#{gap} #{more}: #{msgs.first(4).join('; ')}" end
      end
    end
  end
end
puts "ok=#{ok} nicht lösbar=#{rej} Fehler=#{err}"
