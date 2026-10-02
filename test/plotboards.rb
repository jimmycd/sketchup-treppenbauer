require_relative 'su_mock'
$LOAD_PATH.unshift File.expand_path('../src', __dir__)
%w[params geometry fit stringers builder parts].each { |f| require "jt_treppenbau/#{f}" }
require 'json'
include JTools::Treppenbau
out = {}
ARGV.each_slice(2) do |name, js|
  p = Params.normalize(Params.defaults.merge(JSON.parse(js)))
  plan = Layout.compute(p)
  parts, w = Parts.collect(plan, p, treads: false, risers: false, stringers: true, posts: false, rail: false, einstand: 15)
  out[name] = parts.select { |x| x.kind == :stringer }.map { |x| { l: x.label, poly: x.poly, pk: x.pockets } }
  puts "#{name}: #{w.join(' | ')}"
end
File.write('boards.json', JSON.generate(out))
