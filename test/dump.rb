$LOAD_PATH.unshift File.expand_path('../src', __dir__)
require 'json'
require 'jt_treppenbau/params'
require 'jt_treppenbau/geometry'
require 'jt_treppenbau/fit'
require 'jt_treppenbau/stringers'
require_relative 'su_mock'
require 'jt_treppenbau/builder'
include JTools::Treppenbau
over = ARGV[0] ? JSON.parse(ARGV[0]) : {}
res = {}
Params::ALL.each do |v|
  %w[links rechts].each do |d|
    p = Params.normalize(Params.defaults.merge('variant'=>v,'direction'=>d).merge(over))
    begin
      res["#{v}_#{d}"] = Layout.compute(p).preview_data
    rescue PlanError => e
      res["#{v}_#{d}"] = {error: e.message}
    end
  end
end
puts JSON.generate(res)
