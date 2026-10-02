require_relative 'su_mock'
$LOAD_PATH.unshift File.expand_path('../src', __dir__)
%w[params geometry fit stringers builder parts nesting tcn cnc].each { |f| require "jt_treppenbau/#{f}" }
require 'json'
include JTools::Treppenbau
out = {}
%w[gerade l_wendel].each do |v|
  p = Params.normalize(Params.defaults.merge('variant'=>v,'construction'=>'wange','risers'=>true,'rail'=>'aussen'))
  plan = Layout.compute(p)
  parts, = Parts.collect(plan, p, stringers: true, einstand: 15.0, pocket_d: 10.0)
  out[v] = parts.select { |x| x.kind == :stringer }.map { |x| { label: x.label, poly: x.poly, pockets: x.pockets, paths: x.pocket_paths } }
end
File.write('pk.json', JSON.generate(out))
