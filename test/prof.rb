require_relative 'su_mock'
$LOAD_PATH.unshift File.expand_path('../src', __dir__)
%w[params geometry builder parts nesting tcn wange3d cnc].each { |f| require "jt_treppenbau/#{f}" }
require 'benchmark'
include JTools::Treppenbau
o = Cnc.normalize({})
p = Params.normalize(Params.defaults.merge('variant'=>'z_wendel','risers'=>true))
plan = Layout.compute(p)
parts=nil
puts Benchmark.realtime { parts,_ = Parts.collect(plan,p,treads:true,risers:true,stringers:true,posts:true,rail:true,einstand:15) }
parts.group_by(&:thickness).each do |t,l|
  n = Nester.new(length:2800,width:2070,margin:10,gap:16,grid:5,grain:true)
  tv = Benchmark.realtime { l.each{|x| n.send(:variants,x)} }
  tn = Benchmark.realtime { n.nest(l) }
  puts "#{t}: #{l.size} variants=#{tv.round(2)} nest=#{tn.round(2)}"
end
