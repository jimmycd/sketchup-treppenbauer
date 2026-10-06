require_relative 'su_mock'
$LOAD_PATH.unshift File.expand_path('../src', __dir__)
%w[params geometry fit stringers builder parts].each { |f| require "jt_treppenbau/#{f}" }
include JTools::Treppenbau
fails = 0
%w[gerade kurve].each do |form|
Params::NOSPIRAL.each do |v|
  [{}, {'fit_mode'=>'raum','space_l'=>350,'space_w'=>260,'angle_left'=>84}].each do |extra|
    %w[rechts links].each do |dir|
      p = Params.normalize(Params.defaults.merge('variant'=>v,'direction'=>dir,'risers'=>true,'side_left'=>'wange','side_right'=>'wange','str_form'=>form).merge(extra))
      begin; plan = Layout.compute(p); rescue PlanError => e; puts "#{v} #{extra.size} #{dir}: #{e.message}"; next; end
      r = Stringers.compute(plan, p)
      over = p['str_over']; under = p['str_under']
      maxover = 0; minover = 1e9; minunder = 1e9; jump = 0.0; kink = 0.0
      r[:wange].each do |b|
        (form == 'kurve' && !b[:landing] ? b[:keyed] : b[:req]).each do |u, z|
          next if u < b[:u0] - 1e-6 || u > b[:u1] + 1e-6 # außerhalb des gekürzten Bretts (stumpfer Stoß)
          o = Stringers.top(b, u) - (z - over)
          maxover = [maxover, o].max; minover = [minover, o].min
        end
        # Mindestabstand unten: dicht abgetastet über jede Stufe
        b[:steps].each do |_k, a, e, zr|
          (0..20).each { |i| u = a + (e - a) * i / 20.0; minunder = [minunder, zr + under - Stringers.bot(b, u)].min }
        end
        # Trittstufe ganz bedeckt: Oberkante über Stufe k mind. nose_z(k)+over
        if form == 'kurve'
          tp = b[:tp]
          (1...tp.size - 1).each do |i|
            s0 = (tp[i][1] - tp[i - 1][1]) / (tp[i][0] - tp[i - 1][0]); s1 = (tp[i + 1][1] - tp[i][1]) / (tp[i + 1][0] - tp[i][0])
            kink = [kink, (Math.atan(s1) - Math.atan(s0)).abs * 180 / Math::PI].max
          end
        end
      end
      r[:wange].each_cons(2) do |a, b|
        next unless a[:which] == b[:which] && a[:piece] == b[:piece] && (form == 'gerade' || (!a[:landing] && !b[:landing])) && (b[:u0] - a[:u1]).abs < 0.01
        jump = [jump, (Stringers.top(a, a[:u1]) - Stringers.top(b, b[:u0])).abs, (Stringers.bot(a, a[:u1]) - Stringers.bot(b, b[:u0])).abs].max
      end
      ws = r[:wange].map { |b| b[:w] }.uniq
      # gerade: Brettbreite rechtwinklig nirgends kleiner als W (Unterkante dicht
      # abgetastet gegen die Oberkante des Bretts)
      wdev = 0.0
      if form == 'gerade'
        r[:wange].each do |b|
          tp = b[:tp]
          (0..100).each do |i|
            u = b[:u0] + (b[:u1] - b[:u0]) * i / 100.0
            q = [u, Stringers.bot(b, u)]
            next if q[1] < 0.01
            dmin = tp.each_cons(2).map do |p0, p1|
              d = [p1[0] - p0[0], p1[1] - p0[1]]; l2 = d[0]**2 + d[1]**2
              t = [[((q[0] - p0[0]) * d[0] + (q[1] - p0[1]) * d[1]) / l2, 0.0].max, 1.0].min
              Math.hypot(q[0] - p0[0] - t * d[0], q[1] - p0[1] - t * d[1])
            end.min
            # nur innerhalb des Bretts aussagekräftig (Endschnitt senkrecht)
            next if u - b[:u0] < b[:w] || b[:u1] - u < b[:w]
            wdev = [wdev, b[:w] - dmin].max
          end
        end
      end
      ok = minover >= over - 1e-6 && minunder >= under - 1e-6 && (form == 'kurve' ? (maxover - over).abs < 1e-6 && jump < 1e-6 : ws.size <= 1 && jump < 1e-6 && wdev < 1e-3)
      fails += 1 unless ok
      puts format('%-6s %-14s %-5s %-6s boards=%2d W=%.1f..%.1f over %.2f/%.2f under min %.2f fuge %.3f knick %.1f° %s', form, v, extra.empty? ? 'frei' : 'raum', dir,
                  r[:wange].size, r[:wmin] || r[:width], r[:width], minover, maxover, minunder, jump, kink, ok ? 'OK' : 'FEHLER')
    end
  end
end
end
puts "Fehler: #{fails}"
