$LOAD_PATH.unshift File.expand_path('../src', __dir__)
require 'json'
require 'jt_treppenbau/params'
require 'jt_treppenbau/geometry'
include JTools::Treppenbau
res = {}
Params::ALL.each do |v|
  p = Params.normalize(Params.defaults.merge('variant'=>v))
  begin
    plan = Layout.compute(p)
    res[v] = {ok: true, plan: plan.preview_data, info: plan.info, warnings: plan.warnings, derived: {'n_steps'=>plan.n,'a_user'=>plan.a.round(2),'h'=>plan.h.round(2)}}
  rescue PlanError => e
    res[v] = {ok: false, error: e.message}
  end
end
init = {schema: Params::SCHEMA, defaults: Params.defaults, params: Params.defaults.merge('variant'=>ARGV[0] || 'l_wendel'), mode: 'new'}
puts "window.TB_DATA=#{JSON.generate(res)};window.TB_INIT=#{JSON.generate(init)};"
puts "window.TB_MOCK={ready:function(){TB.init(TB_INIT)},preview:function(j){var v=JSON.parse(j).variant;setTimeout(function(){TB.onPreview(TB_DATA[v])},10)}};"
