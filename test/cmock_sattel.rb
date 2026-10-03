require File.expand_path('su_mock', __dir__)
$LOAD_PATH.unshift File.expand_path('../src', __dir__)
%w[params geometry fit stringers builder parts nesting tcn wange3d cnc].each { |f| require "jt_treppenbau/#{f}" }
include JTools::Treppenbau
require 'json'
p = Params.normalize(Params.defaults.merge('variant' => 'l_wendel', 'direction' => 'rechts', 'risers' => true, 'side_left' => 'sattel', 'side_right' => 'sattel'))
plan = Layout.compute(p)
o = Cnc.normalize('sat_wenden' => true)
res = Cnc.compute(plan, p, o)
d = Cnc.preview(res, o)
init = { opts: o, tools: Cnc::OUTER_TOOLS.map { |n, nr, dd| { name: n, nr: nr, d: dd } }, stair: 'L viertelgewendelt – aufgesattelt', construction: 'wange', risers: true, rail: 'aussen', sattel: true, tpacad: '' }
puts "window.R=#{JSON.generate(d.merge(ok: true))};window.I=#{JSON.generate(init)};window.CNC_MOCK={ready:function(){CNC.init(I)},compute:function(){setTimeout(function(){CNC.onResult(R)},10)}};"
