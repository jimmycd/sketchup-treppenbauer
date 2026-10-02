$LOAD_PATH.unshift File.expand_path('../src', __dir__)
require 'jt_treppenbau/params'
require 'jt_treppenbau/geometry'
require 'jt_treppenbau/fit'
require 'jt_treppenbau/stringers'
require_relative 'su_mock'
require 'jt_treppenbau/builder'
include JTools::Treppenbau

out = ARGV[0] || '/home/claude/tb/test/out'
Dir.mkdir(out) unless Dir.exist?(out)

def svg_for(plan)
  d = plan.preview_data
  pts = d[:outer] + d[:inner]
  d[:treads].each { |t| pts += t[:pts] }
  xs = pts.map { |p| p[0] }; ys = pts.map { |p| p[1] }
  x0 = xs.min - 20; x1 = xs.max + 20; y0 = ys.min - 20; y1 = ys.max + 20
  tr = ->(p) { "#{(p[0] - x0).round(2)},#{(y1 - p[1]).round(2)}" }
  s = +"<svg xmlns='http://www.w3.org/2000/svg' width='#{((x1 - x0) * 2).round}' height='#{((y1 - y0) * 2).round}' viewBox='0 0 #{(x1 - x0).round(2)} #{(y1 - y0).round(2)}'>"
  s << "<rect width='100%' height='100%' fill='white'/>"
  d[:treads].each do |t|
    col = t[:kind] == 'landing' ? '#cde' : '#eed9b5'
    s << "<polygon points='#{t[:pts].map(&tr).join(' ')}' fill='#{col}' stroke='#333' stroke-width='0.6'/>"
    s << "<text x='#{tr.(t[:label]).split(',')[0]}' y='#{tr.(t[:label]).split(',')[1]}' font-size='7' text-anchor='middle'>#{t[:nr]}</text>"
  end
  s << "<polyline points='#{d[:walk].map(&tr).join(' ')}' fill='none' stroke='red' stroke-width='0.5' stroke-dasharray='3,2'/>"
  s << '</svg>'
  s
end

base = Params.defaults
Params::ALL.each do |v|
  %w[links rechts].each do |dir|
    p = Params.normalize(base.merge('variant' => v, 'direction' => dir))
    begin
      plan = Layout.compute(p)
      File.write(File.join(out, "#{v}_#{dir}.svg"), svg_for(plan))
      # Konsistenzprüfungen
      (0...plan.treads).each do |k|
        r = plan.region(plan.lines_w[k], plan.lines_w[k + 1])
        ar = Geo.signed_area(r.map(&:first)).abs
        raise "Fläche 0 bei Stufe #{k}" if ar < 1
      end
      puts "#{v.ljust(14)} #{dir.ljust(6)} OK  n=#{plan.n} h=#{plan.h.round(2)} a=#{plan.a.round(2)} W=#{plan.wtot.round(1)}  warn=#{plan.warnings.size}"
      plan.info.each { |i| puts "      #{i[0]}: #{i[1]}" } if dir == 'rechts'
      plan.warnings.each { |w| puts "      ! #{w}" } if dir == 'rechts'
    rescue PlanError => e
      puts "#{v.ljust(14)} #{dir.ljust(6)} PlanError: #{e.message}"
    end
  end
end
