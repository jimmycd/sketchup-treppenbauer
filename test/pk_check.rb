require_relative 'su_mock'
$LOAD_PATH.unshift File.expand_path('../src', __dir__)
%w[params geometry fit stringers builder parts nesting tcn cnc].each { |f| require "jt_treppenbau/#{f}" }
include JTools::Treppenbau
def segd(p, a, b)
  dx = b[0]-a[0]; dy = b[1]-a[1]; l = dx*dx+dy*dy
  t = l < 1e-12 ? 0 : [[((p[0]-a[0])*dx+(p[1]-a[1])*dy)/l, 0].max, 1].min
  Math.hypot(p[0]-a[0]-t*dx, p[1]-a[1]-t*dy)
end
def bdist(p, poly) = poly.each_index.map { |i| segd(p, poly[i], poly[(i+1)%poly.size]) }.min
bad = 0; n = 0
%w[gerade l_wendel u_podest u_wendel z_wendel l_podest].each do |v|
  [true, false].each do |ris|
  %w[gerade kurve].each do |f|
  [10.0, 16.0].each do |pd|
    p = Params.normalize(Params.defaults.merge('variant'=>v,'construction'=>'wange','risers'=>ris,'str_form'=>f)) rescue next
    plan = Layout.compute(p)
    parts, = Parts.collect(plan, p, stringers: true, einstand: 15.0, pocket_d: pd)
    r = pd / 2
    parts.select { |x| x.kind == :stringer && !x.pockets.empty? }.each do |pt|
      n += 1
      edges = []
      pt.pockets.each { |pk| pk.each_index { |i| a = pk[i]; b = pk[(i+1)%pk.size]; m = [(a[0]+b[0])/2.0, (a[1]+b[1])/2.0]; edges << [a, b, bdist(a, pt.poly) < 0.05 && bdist(b, pt.poly) < 0.05 && bdist(m, pt.poly) < 0.05] } }
      closed = edges.reject { |e| e[2] }
      (puts "ALLOPEN #{v} #{pt.label} #{pt.pockets.map(&:size)}"; next) if closed.empty?
      worst = r
      pt.pocket_paths.each do |pa|
        pa.each_cons(2) do |a, b|
          5.times do |k|
            q = [a[0]+(b[0]-a[0])*k/5.0, a[1]+(b[1]-a[1])*k/5.0]
            dd = closed.map { |e| segd(q, e[0], e[1]) }.min
            worst = [worst, dd].min
          end
        end
      end
      if worst < r - 0.02
        bad += 1; puts "GOUGE #{v} ris=#{ris} #{f} d=#{pd} #{pt.label}: #{worst.round(3)}"
      end
    end
  end; end; end
end
puts "checked #{n} boards, gouge=#{bad}"
