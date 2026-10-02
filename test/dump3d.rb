require_relative 'su_mock'
$LOAD_PATH.unshift File.expand_path('../src', __dir__)
%w[params geometry fit stringers builder].each { |f| require "jt_treppenbau/#{f}" }
require 'json'
include JTools::Treppenbau
def leaf(ents, path = [], acc = [])
  ents.items.grep(Sketchup::Group).each do |g|
    if g.entities.items.grep(Sketchup::Group).empty? then acc << [path + [g.name], g] else leaf(g.entities, path + [g.name], acc) end
  end
  acc
end
name, json = ARGV
p = Params.normalize(Params.defaults.merge(JSON.parse(json)))
model = Sketchup::Model.new; defn = Sketchup::ComponentDefinition.new(model)
plan = Builder.build(defn, p)
tris = []
leaf(defn.entities).each do |path, g|
  next if path[0] == 'Gehlinie' || path[0] == 'Verfügbarer Raum'
  g.entities.items.grep(Sketchup::Face).each do |fc|
    p0 = fc.pts[0]
    (1...fc.pts.size - 1).each { |i| tris << [p0, fc.pts[i], fc.pts[i + 1]].map { |q| q.to_a.map { |x| (x * 2.54).round(2) } } + [path[0]] }
  end
end
File.write("out/#{name}.json", JSON.generate(tris))
puts "#{name}: n=#{plan.n} a=#{plan.a.round(2)} b=#{plan.b.round(1)}"
plan.info.each { |k, v| puts "   #{k}: #{v}" if k =~ /Wange|Kopf|Luft|Antritt/ }
plan.warnings.each { |w| puts "   ! #{w}" }
