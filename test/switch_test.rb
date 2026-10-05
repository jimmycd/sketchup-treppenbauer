# Test fehler.md Nr. 6: Umschalten Raum <-> Parameter ohne Änderung der Treppe
require_relative 'su_mock'
$LOAD_PATH.unshift File.expand_path('../src', __dir__)
%w[params geometry fit transfer stringers].each { |f| require "jt_treppenbau/#{f}" }
require 'benchmark'
include JTools::Treppenbau

room_cases = [
  ['gerade', 420, 100, {}], ['gerade', 420, 100, { 'antritt_l' => 400 }], ['gerade', 420, 140, { 'wall_right' => false }],
  ['gerade', 420, 120, { 'loch' => true, 'loch_l' => 300, 'loch_w' => 120, 'loch_y' => 30, 'loch_gap' => 20 }],
  ['gerade_podest', 520, 100, {}], ['gerade_podest', 520, 100, { 'antritt_l' => 500 }],
  ['l_podest', 300, 280, {}], ['l_podest', 300, 280, { 'antritt_l' => 290 }],
  ['l_podest', 330, 300, { 'loch' => true, 'loch_l' => 110, 'loch_w' => 250, 'loch_x' => 0, 'loch_gap' => 30 }],
  ['l_wendel', 330, 300, { 'loch' => true, 'loch_l' => 110, 'loch_w' => 250, 'loch_x' => 0, 'loch_gap' => 25 }],
  ['u_wendel', 260, 220, { 'loch' => true, 'loch_l' => 240, 'loch_w' => 220, 'loch_gap' => 20 }],
  ['l_wendel', 260, 250, {}], ['l_wendel', 270, 250, { 'antritt_l' => 260 }],
  ['u_podest', 290, 210, {}], ['u_podest', 290, 210, { 'loch' => true, 'loch_l' => 250, 'loch_w' => 210 }],
  ['u_podest', 300, 210, { 'antritt_l' => 280 }],
  ['u_wendel', 220, 210, {}], ['u_wendel', 240, 210, { 'antritt_l' => 230 }],
  ['z_podest', 220, 300, {}], ['z_wendel', 200, 260, {}],
  ['z_wendel', 220, 260, { 'eye' => 30, 'loch' => true, 'loch_l' => 220, 'loch_w' => 260 }],
  ['spindel', 180, 180, {}], ['auge', 220, 220, {}],
  # Drachenstufe außermittig (fester Antritt, Gehlinie bleibt)
  ['l_wendel', 280, 240, { 'antritt_l' => 270 }], ['u_wendel', 230, 205, { 'antritt_l' => 225 }]
]
free_cases = [
  ['gerade', {}], ['gerade', { 'n_steps' => 16, 'a_user' => 27 }], ['gerade', { 'exit_land' => 25 }],
  ['gerade_podest', {}], ['gerade_podest', { 'landing_len' => 120 }],
  ['l_podest', {}], ['l_podest', { 'pod1_vor' => 12, 'pod1_nach' => 7 }], ['l_podest', { 'exit_land' => 30 }],
  ['l_wendel', {}], ['l_wendel', { 'gl' => 40, 'm1' => 3 }],
  ['u_podest', {}], ['u_podest', { 'pod1_nach' => 15 }], ['u_podest', { 'pod1_vor' => 10, 'exit_land' => 20 }],
  ['u_wendel', {}], ['z_podest', {}], ['z_podest', { 'pod1_nach' => 8, 'pod2_vor' => 8 }],
  ['z_wendel', {}], ['spindel', {}], ['auge', { 'D_out' => 200 }],
  ['gerade', { 'total_w' => 110, 'total_l' => 380 }],
  # Drachenstufe außermittig (Lage der Ecke vorgegeben bzw. U-Treppe mit fester Gehlinie)
  ['l_wendel', { 'kite_pos' => 35 }], ['u_wendel', { 'kite_pos' => 30 }], ['u_wendel', { 'gl' => 42 }],
  ['z_wendel', { 'kite_pos' => 40, 'kite_pos2' => 65 }]
]
sides = [%w[wange wange], %w[wange sattel], %w[frei wange]]
err = 0; cnt = 0; tmax = 0.0
check = lambda do |label, p0, to|
  cnt += 1
  plan = begin; Layout.compute(p0); rescue PlanError => e; puts "skip #{label}: #{e.message}"; cnt -= 1; next; end
  res = nil
  t = Benchmark.realtime { res = Transfer.switch(p0, to) }
  tmax = [tmax, t].max
  q = res[:params]
  unless res[:exact]
    err += 1
    puts "FEHLER #{label} -> #{to}: #{res[:message]}"
    next
  end
  # zurück: ohne Änderung muss wieder dieselbe Treppe entstehen
  back = Transfer.switch(q, p0['fit_mode'])
  c = Transfer.compare(plan, Layout.compute(back[:params])) rescue nil
  unless c && c[0] <= Transfer::TOL
    err += 1
    puts "FEHLER Rückweg #{label}: #{back[:message]}"
  end
  # Werte, die nicht nötig sind, dürfen automatisch bleiben – nur Info
  puts format('%-60s ok %.2fs  %s', label, t, q.select { |k, v| %w[n_steps a_user r1 m1 gl].include?(k) && v != p0[k] }.map { |k, v| "#{k}=#{v}" }.join(' '))
end

room_cases.each do |v, l, w, ex|
  %w[rechts links].each do |dir|
    sides.each do |sl, sr|
      p = Params.normalize(Params.defaults.merge('variant' => v, 'fit_mode' => 'raum', 'space_l' => l, 'space_w' => w,
                                                 'direction' => dir, 'side_left' => sl, 'side_right' => sr).merge(ex))
      check.("raum #{v} #{dir} #{sl}/#{sr} #{ex}", p, 'aus')
    end
  end
end
free_cases.each do |v, ex|
  %w[rechts links].each do |dir|
    sides.each do |sl, sr|
      [{}, { 'wall_right' => false }, { 'loch' => true }].each do |rm|
        p = Params.normalize(Params.defaults.merge('variant' => v, 'fit_mode' => 'aus', 'direction' => dir,
                                                   'side_left' => sl, 'side_right' => sr).merge(ex).merge(rm))
        check.("aus #{v} #{dir} #{sl}/#{sr} #{ex} #{rm}", p, 'raum')
      end
    end
  end
end
puts "#{cnt} Fälle, #{err} Fehler, max. #{tmax.round(2)} s"
