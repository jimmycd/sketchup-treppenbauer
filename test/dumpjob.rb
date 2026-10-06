require File.expand_path('su_mock', __dir__)
$LOAD_PATH.unshift File.expand_path('../src', __dir__)
%w[params geometry fit stringers builder parts nesting tcn wange3d fraesliste cnc].each { |f| require "jt_treppenbau/#{f}" }
include JTools::Treppenbau
require 'json'
p = Params.normalize(Params.defaults.merge('variant' => ARGV[0], 'direction' => 'rechts', 'risers' => true, 'side_left' => 'sattel', 'side_right' => 'sattel'))
plan = Layout.compute(p)
o = Cnc.normalize('sat_mode' => 'fraesen', 'sat_wenden' => true, 'engrave' => true)
res = Cnc.compute(plan, p, o)
out = res.boards.map do |jb|
  { label: jb.label, blank: jb.blank, outline: jb.outline, notes: jb.notes,
    progs: jb.programs.map { |pg| { side: pg.side, ops: pg.ops.map { |k, pts| [k, pts] },
      aggs: pg.faces.map { |fc| { axis: fc[:axis], corners: fc[:corners] } } } } }
end
File.write(File.expand_path('~/job.json'), JSON.generate(out))
Cnc.export(File.expand_path('../tcn_test', __dir__), 'probe_' + ARGV[0], res, o)
puts res.boards.map { |b| "#{b.label} #{b.blank.map(&:round)} progs=#{b.programs.size} walls=#{b.walls.map { |w| w[:how] }.tally}" }
