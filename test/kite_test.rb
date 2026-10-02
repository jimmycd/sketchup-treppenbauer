$LOAD_PATH.unshift File.expand_path('../src', __dir__)
%w[params geometry fit].each { |f| require "jt_treppenbau/#{f}" }
require_relative 'kite_check'
include JTools::Treppenbau
fails = 0; total = 0; perr = 0
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
verbose = ARGV.include?('-v')
(cfgs + rooms).each do |c|
  p = Params.normalize(base.merge(c))
  total += 1
  begin
    plan = Layout.compute(p)
  rescue PlanError => e
    perr += 1
    puts "PlanError #{c}: #{e.message}" if verbose
    next
  end
  e = KiteCheck.errors(plan)
  next if e.empty?
  fails += 1
  puts "#{c}: #{e.uniq.first(3).join('; ')}" if verbose || fails < 25
end
puts "#{total} Fälle, #{perr} PlanError, #{fails} mit Drachenstufen-Fehlern"
