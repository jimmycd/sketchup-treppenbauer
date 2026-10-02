# encoding: UTF-8
require "json"
d=JSON.parse(File.read("cnc.json"))["z_wendel"]
$LOAD_PATH.unshift "../src"; require_relative "su_mock"; %w[params geometry fit stringers builder parts nesting tcn cnc].each{|f| require "jt_treppenbau/#{f}"}
init={opts: JTools::Treppenbau::Cnc::DEFAULTS, tools: JTools::Treppenbau::Cnc::OUTER_TOOLS.map{|n,nr,dd|{name:n,nr:nr,d:dd}}, stair:"Zweimal viertelgewendelt mit Wendelstufen – Wangentreppe", construction:"wange", risers:true, rail:"aussen", tpacad:""}
puts "window.R=#{JSON.generate(d.merge("ok"=>true))};window.I=#{JSON.generate(init)};window.CNC_MOCK={ready:function(){CNC.init(I)},compute:function(){setTimeout(function(){CNC.onResult(R)},10)}};"
