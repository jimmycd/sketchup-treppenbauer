require_relative 'su_mock'
$LOAD_PATH.unshift File.expand_path('../src', __dir__)
%w[params geometry fit stringers builder parts nesting tcn cnc].each { |f| require "jt_treppenbau/#{f}" }
include JTools::Treppenbau
p = Params.normalize(Params.defaults.merge('variant'=>'l_podest','construction'=>'wange','risers'=>false))
plan = Layout.compute(p)
r = Stringers.compute(plan, p)
r[:wange].select{|b| b[:which]==:inner}.each{|b| puts "u0=#{b[:u0].round(3)} u1=#{b[:u1].round(3)} landing=#{b[:landing].inspect} side=#{b[:side]}"}
lw = plan.lines_w
(0...plan.treads).each{|k| puts "k=#{k} #{plan.kinds[k]} s=#{Stringers.prm(plan,:inner,lw[k]).round(3)}..#{Stringers.prm(plan,:inner,[lw[k+1]+p['nosing'],plan.wtot].min).round(3)}"}
parts, = Parts.collect(plan, p, stringers: true, einstand: 15.0, pocket_d: 10.0)
pt = parts.find{|x| x.label=='WI2'}
puts pt.poly.map{|q| q.map{|v| v.round(2)}}.inspect
pt.pockets.each{|pk| puts pk.map{|q| q.map{|v| v.round(2)}}.inspect}
puts '---'
d = p['tread_t']; u = p['nosing']; ext = u
r[:wange].select{|b| b[:which]==:inner}.each do |b|
  nrm = b[:side] > 0 ? Geo.right(b[:dir]) : Geo.left(b[:dir])
  (0...plan.treads).each do |k|
    cu = [lw[k], [lw[k+1]+ext, plan.wtot].min].map { |w| Parts.cross_u(plan, b, w, 1.5, nrm) }
    puts "b#{b[:u0].round} k=#{k} #{cu.map{|c| c.map{|v| v.round(2)}}.inspect} z=#{((k+1)*plan.h-d).round(1)}"
  end
  puts "bot at u0 #{Stringers.bot(b,b[:u0]).round(1)} u1 #{Stringers.bot(b,b[:u1]).round(1)} top #{Stringers.top(b,b[:u0]).round(1)} #{Stringers.top(b,b[:u1]).round(1)}"
end
