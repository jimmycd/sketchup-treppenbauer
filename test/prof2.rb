require_relative 'su_mock'
$LOAD_PATH.unshift File.expand_path('../src', __dir__)
%w[params geometry builder parts nesting tcn wange3d cnc].each { |f| require "jt_treppenbau/#{f}" }
require 'benchmark'
include JTools::Treppenbau
p = Params.normalize(Params.defaults.merge('variant'=>'z_wendel','risers'=>true))
plan = Layout.compute(p)
parts,_ = Parts.collect(plan,p,treads:true,risers:true,stringers:true,posts:true,rail:true,einstand:15)
l = parts.select{|x| x.thickness==40.0}
n = Nester.new(length:2800,width:2070,margin:10,gap:16,grid:5,grain:true)
prep = l.map{|x| [x, n.send(:variants,x)]}
[:left,:bottom].each do |st|
  $calls=0
  t=Benchmark.realtime{ n.send(:run, prep.sort_by{|x,_| -x.area}, st) }
  puts "#{st} #{t.round(2)}"
end
l.each{|x| puts "#{x.label} #{x.size.map(&:round)} #{x.poly.size}"}
