$LOAD_PATH.unshift File.expand_path('../src', __dir__)
%w[params geometry fit].each { |f| require "jt_treppenbau/#{f}" }
require_relative 'kite_check'
include JTools::Treppenbau
fails = 0; total = 0; perr = 0; inval = 0; asym = 0
base = Params.defaults
cfgs = []
%w[l_wendel u_wendel z_wendel].each do |v|
  [70, 80, 90, 100, 120].each do |b|
    [0, 2, 3, 4, 6, 8].each do |nv|
      [0, 3, 5].each do |m1|
        [0, b * 0.4, b * 0.6].each do |gl|
          [0, 10, 20, 35].each do |eye|
            next if v != 'u_wendel' && eye > 0
            [270, 290].each do |hh|
              cfgs << { 'variant' => v, 'b' => b, 'nv' => nv, 'm1' => m1, 'gl' => gl.round, 'eye' => eye, 'H' => hh }
            end
          end
        end
      end
    end
  end
end
# Raum-Modus
rooms = []
[['l_wendel', 260, 250], ['l_wendel', 280, 240], ['u_wendel', 220, 210], ['u_wendel', 240, 200], ['z_wendel', 200, 260], ['z_wendel', 230, 280]].each do |v, l, w|
  [{}, { 'antritt_l' => l - 10 }, { 'angle_left' => 95 }, { 'angle_left' => 80, 'angle_right' => 97 },
   { 'loch' => true, 'loch_l' => 200, 'loch_w' => w - 10 }, { 'loch' => true, 'loch_l' => 200, 'loch_w' => w - 10, 'antritt_l' => l - 5 },
   { 'eye' => 30 }, { 'eye' => 5 }].each do |ex|
    %w[rechts links].each do |dir|
      rooms << { 'variant' => v, 'fit_mode' => 'raum', 'space_l' => l, 'space_w' => w, 'wall_gap' => 1, 'direction' => dir }.merge(ex)
    end
  end
end
# Lage der Ecke vorgegeben (kite_pos, kite_pos2)
kpos = []
%w[l_wendel u_wendel z_wendel].each do |v|
  [80, 100].each do |b|
    [0, 4].each do |nv|
      [20, 35, 50, 65, 80].each do |kp|
        [0, 20].each do |eye|
          next if v != 'u_wendel' && eye > 0
          [270, 290].each do |hh|
            c = { 'variant' => v, 'b' => b, 'nv' => nv, 'eye' => eye, 'H' => hh, 'kite_pos' => kp }
            c['kite_pos2'] = 100 - kp if v == 'z_wendel'
            kpos << c
          end
        end
      end
    end
  end
end
verbose = ARGV.include?('-v')
(cfgs + rooms + kpos).each do |c|
  p = Params.normalize(base.merge(c))
  total += 1
  begin
    plan = Layout.compute(p)
  rescue PlanError => e
    perr += 1
    puts "PlanError #{c}: #{e.message}" if verbose
    next
  end
  # Innenauftritt <= 0 (z. B. U-Treppe ohne Treppenauge): Geometrie ohnehin ungültig
  if plan.warnings.any? { |w| w.include?('Geometrie ungültig') }
    inval += 1
    next
  end
  fr = Layout.kite_fracs(plan).map(&:last)
  asym += 1 if fr.any? { |f| (f - 0.5).abs > 0.005 }
  # frei, ohne Vorgabe: L und dreiläufig mittig (U: Gehlinie bleibt, Ecken ggf. außermittig)
  mid = c['fit_mode'].nil? && c['variant'] != 'u_wendel' && !c['kite_pos']
  e = KiteCheck.errors(plan, mid: mid)
  if c['kite_pos']
    want = [c['kite_pos'] / 100.0]
    want << c['kite_pos2'] / 100.0 if c['kite_pos2']
    want.each_with_index { |f, i| e << format('Ecke %d bei %.3f statt %.3f', i + 1, fr[i], f) if fr[i].nil? || (fr[i] - f).abs > 1e-6 }
  end
  next if e.empty?
  fails += 1
  puts "#{c}: #{e.uniq.first(3).join('; ')}" if verbose || fails < 25
end
puts "#{total} Fälle, #{perr} PlanError, #{inval} ungültig (Innenauftritt ≤ 0), #{asym} außermittig, #{fails} mit Drachenstufen-Fehlern"
