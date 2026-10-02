# encoding: UTF-8
# fehler.md Nr. 4: fester Antritt darf vor dem Raumende / außerhalb des
# Treppenlochs liegen (antritt_l > Raumlänge), der Austritt nicht.
require_relative 'su_mock'
$LOAD_PATH.unshift File.expand_path('../src', __dir__)
%w[params geometry fit stringers builder].each { |f| require "jt_treppenbau/#{f}" }
include JTools::Treppenbau
TOL = 0.1
cases = [
  ['gerade', 250, 100, {}], ['gerade', 250, 100, { 'loch' => true, 'loch_l' => 150, 'loch_w' => 100, 'loch_y' => 20 }],
  ['gerade', 250, 100, { 'angle_left' => 85 }],
  ['gerade_podest', 450, 100, {}],
  ['l_podest', 200, 280, {}], ['l_podest', 250, 280, { 'loch' => true, 'loch_l' => 100, 'loch_w' => 200, 'loch_x' => 40 }],
  ['l_wendel', 180, 250, {}],
  ['u_podest', 290, 210, {}], ['u_wendel', 220, 210, {}],
  ['u_podest', 290, 210, { 'loch' => true, 'loch_l' => 250, 'loch_w' => 210 }],
  ['z_podest', 200, 300, {}], ['z_wendel', 180, 260, {}]
]
err = 0; ok = 0; rej = 0
cases.each do |v, l, w, ex|
  %w[rechts links].each do |dir|
    [5, 20, 60].each do |over|
      ant = l + over
      p = Params.normalize(Params.defaults.merge('variant' => v, 'fit_mode' => 'raum', 'space_l' => l, 'space_w' => w,
                                                 'wall_gap' => 1, 'direction' => dir, 'antritt_l' => ant).merge(ex))
      begin
        plan = Layout.compute(p)
      rescue PlanError => e
        rej += 1
        puts format('  (nicht lösbar) %-13s %-6s L=%d Antritt=%d %s: %s', v, dir, l, ant, ex.keys.join(','), e.message)
        next
      end
      l0 = plan.line(0.0)
      y_ant = [l0[:in][1], l0[:out][1]].min
      le = plan.line(plan.wtot)
      y_ex = [le[:in][1], le[:out][1]].min
      msgs = []
      msgs << format('Antritt %.2f statt %.2f', l - y_ant, ant) if (l - y_ant - ant).abs > TOL && plan.warnings.none? { |x| x.include?('Antritt um') }
      msgs << format('Austritt außerhalb (y=%.2f)', y_ex) if y_ex < -TOL
      if msgs.empty? then ok += 1 else err += 1; puts "FEHLER #{v} #{dir} #{ant} #{ex}: #{msgs.join('; ')}" end
    end
  end
end
# Ohne festen Antritt bleibt alles im Raum (unverändert)
p = Params.normalize(Params.defaults.merge('variant' => 'gerade', 'fit_mode' => 'raum', 'space_l' => 150, 'space_w' => 100))
begin
  Layout.compute(p); err += 1; puts 'FEHLER: freier Antritt ragt aus dem Raum'
rescue PlanError
  ok += 1
end
puts "ok=#{ok} nicht lösbar=#{rej} Fehler=#{err}"
