require_relative 'su_mock'
$LOAD_PATH.unshift File.expand_path('../src', __dir__)
%w[params geometry fit stringers builder parts nesting tcn cnc].each { |f| require "jt_treppenbau/#{f}" }
require 'json'; require 'benchmark'
include JTools::Treppenbau
o = Cnc.normalize({'engrave'=>true})
all = {}
%w[gerade l_wendel u_podest z_wendel auge].each do |v|
  %w[wange kurve].each do |c|
    p = Params.normalize(Params.defaults.merge('variant'=>v,'construction'=>'wange','str_form'=>(c == 'kurve' ? 'kurve' : 'gerade'),'risers'=>true,'rail'=>'aussen','side_right'=>'sattel'))
    plan = Layout.compute(p)
    res=nil
    t = Benchmark.realtime { res = Cnc.compute(plan, p, o) }
    puts "#{v}/#{c}: parts=#{res.parts.size} sheets=#{res.sheets.size} unplaced=#{res.unplaced.size} t=#{t.round(2)}s"
    res.sheets.each { |s| puts "   #{s.thickness}mm #{s.index}/#{s.count}: #{s.placements.size} Teile, used=#{s.used_len.round} util=#{(s.util*100).round(1)}%" }
    res.warnings.each { |w| puts "   ! #{w}" }
    dir="out/tcn_#{v}_#{c}"; Dir.mkdir(dir) unless Dir.exist?(dir)
    Cnc.export(dir, "Treppe_#{v}", res, o)
    all["#{v}_#{c}"] = Cnc.preview(res, o)
  end
end
File.write('cnc.json', JSON.generate(all))
