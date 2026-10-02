require_relative 'su_mock'
$LOAD_PATH.unshift File.expand_path('../src', __dir__)
%w[params geometry fit stringers builder].each { |f| require "jt_treppenbau/#{f}" }
require 'benchmark'; require 'json'
include JTools::Treppenbau
cases = [
  ['gerade', 420, 100, {}],
  ['gerade', 420, 100, {'antritt_l'=>400}],
  ['gerade', 420, 100, {'angle_left'=>85}],
  ['gerade', 420, 100, {'wall_right'=>false}],
  ['gerade_podest', 520, 100, {}],
  ['gerade_podest', 520, 100, {'antritt_l'=>500}],
  ['l_podest', 300, 280, {}],
  ['l_podest', 300, 280, {'antritt_l'=>290}],
  ['l_wendel', 260, 250, {}],
  ['l_wendel', 270, 250, {'antritt_l'=>260, 'angle_left'=>95}],
  ['u_podest', 290, 210, {}],
  ['u_podest', 290, 210, {'loch'=>true,'loch_l'=>250,'loch_w'=>210}],
  ['u_wendel', 220, 210, {}],
  ['u_wendel', 240, 210, {'angle_left'=>80,'angle_right'=>95}],
  ['z_podest', 220, 300, {}],
  ['z_wendel', 200, 260, {}],
  ['z_wendel', 220, 260, {'eye'=>30, 'loch'=>true,'loch_l'=>220,'loch_w'=>260}],
  ['spindel', 180, 180, {}],
]
out = {}
cases.each_with_index do |(v,l,w,ex), ci|
  %w[rechts links].each do |dir|
    p = Params.normalize(Params.defaults.merge('variant'=>v,'fit_mode'=>'raum','space_l'=>l,'space_w'=>w,'wall_gap'=>1,'direction'=>dir).merge(ex))
    plan=nil
    t = Benchmark.realtime { begin; plan = Layout.compute(p); rescue PlanError => e; puts "#{v} #{dir} #{ex}: PlanError #{e.message}"; end }
    next unless plan
    get = ->(k) { (plan.info.find { |a,_| a.start_with?(k) } || [nil,'-'])[1] }
    puts format('%-14s %-6s %-40s n=%d h=%.2f a=%.2f b=%.1f  Antritt %s | Luft %s | t=%.2fs', v, dir, ex.to_s[0,40], plan.n, plan.h, plan.a, plan.b,
       get.('Antritt'), get.('Luft'), t)
    plan.warnings.each{|x| puts "     ! #{x}"}
    out["#{ci}_#{v}_#{dir}"] = plan.preview_data
  end
end
File.write('fit.json', JSON.generate(out))
