# encoding: UTF-8
require "json"
$LOAD_PATH.unshift "../src"; require_relative "su_mock"; %w[params geometry fit stringers builder].each{|f| require "jt_treppenbau/#{f}"}
include JTools::Treppenbau
p = Params.normalize(Params.defaults.merge(JSON.parse(ARGV[0])))
pl = Layout.compute(p)
r = {ok: true, plan: pl.preview_data, info: pl.info, warnings: pl.warnings, derived: {'n_steps'=>pl.n,'a_user'=>pl.a.round(2),'h'=>pl.h.round(2)}}
init = {schema: Params::SCHEMA, defaults: Params.defaults, params: p, mode: 'new'}
puts "window.R=#{JSON.generate(r)};window.TB_MOCK={ready:function(){TB.init(#{JSON.generate(init)})},preview:function(){setTimeout(function(){TB.onPreview(R)},10)}};"
