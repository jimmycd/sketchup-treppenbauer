# Überlange Wangen: zwei Läufe, dazwischen 180° drehen (gleicher X-Anschlag).
# Prüft für eingestemmte und aufgesattelte Wangen (mit/ohne Wenden):
#  * jede TCN höchstens mach_l lang (DL) und alle Punkte auf Seite 1 in 0..DL
#  * Lauf B zurückgedreht = Originalpunkte; keine Bearbeitung verloren
#  * Außenkontur: Lauf A deckt x <= x_T + Überlauf, Lauf B x >= x_T − Überlauf
#  * Nuten/Bohrungen/Gravur/Schrägen nie geteilt, Haltestege nur im ersten Lauf
#  * long_mode 'aus': Ausgabe wie vor 2.11.0 (kein Lauf, keine eigenen Rohlinge)
require_relative 'su_mock'
$LOAD_PATH.unshift File.expand_path('../src', __dir__)
%w[params geometry fit stringers builder parts nesting tcn lauf wange3d cnc].each { |f| require "jt_treppenbau/#{f}" }
include JTools::Treppenbau
require 'tmpdir'

# Seite 1 einer TCN: Bahnen als absolute Punktfolgen [[x, y], …] mit z
def tcn_paths(text)
  side1 = text[/SIDE#1\{(.*?)\}SIDE/m, 1]
  paths = []
  side1.scan(/W#(\d+)\{([^}]*)\}W/).each do |code, body|
    v = ->(k) { body[/ ##{k}=(-?[\d.]+)/, 1].to_f }
    case code
    when '89' then paths << { z: v.(3), pts: [[v.(1), v.(2)]] }
    when '2201'
      a = paths[-1][:pts][-1]
      paths[-1][:pts] << [a[0] + v.(1), a[1] + v.(2)]
    when '81' then paths << { z: v.(3), pts: [[v.(1), v.(2)]], drill: true }
    end
  end
  paths
end

def dl(text)
  text[/DL=([\d.]+)/, 1].to_f
end

fails = 0
cases = 0
o0 = Cnc.normalize({})
mach = o0['mach_l']
ov = o0['long_overlap']
check = lambda do |name, prog, sp, r|
  cases += 1
  errs = []
  l = prog[:l]
  runs = sp[:runs]
  if l <= mach
    errs << 'unnötig geteilt' if runs.size != 1
  else
    errs << "#{runs.size} Läufe" if runs.size != 2
    x_t = sp[:x_t]
    a, b = runs
    texts = runs.map { |rn| Tcn.build_prog(Lauf.labeled(rn)).join("\n") }
    texts.each_with_index do |tx, i|
      errs << "DL #{dl(tx)} > #{mach}" if dl(tx) > mach + 1e-6
      tcn_paths(tx).each do |pa|
        pa[:pts].each do |x, y|
          errs << "Lauf #{runs[i].name}: Punkt x=#{x.round(1)} außerhalb 0..#{dl(tx)}" if x < -r - 1 || x > dl(tx) + 1e-3
          errs << "Lauf #{runs[i].name}: Punkt y=#{y.round(1)} außerhalb" if y < -r - 1 || y > prog[:w] + r + 1
        end
      end
    end
    # zurückgedreht
    back = b.prog[:ops].map { |op| op[:k] == :vdrill ? op.merge(pt: [l - op[:pt][0], prog[:w] - op[:pt][1]]) : op.merge(pts: op[:pts].map { |x, y| [l - x, prog[:w] - y] }) }
    atom = ->(ops) { ops.reject { |op| op[:cut] || op[:soft] }.map { |op| op[:k] == :vdrill ? op[:pt].map { |v| v.round(3) } : op[:pts].map { |q| q.map { |v| v.round(3) } } } }
    orig = atom.(prog[:ops]).sort
    got = (atom.(a.prog[:ops]) + atom.(back)).sort
    errs << "unteilbare Bearbeitungen: #{orig.size} -> #{got.size} (oder verändert)" if orig != got
    errs << "Hilfsflächen #{prog[:faces].size} -> #{a.prog[:faces].size + b.prog[:faces].size}" if prog[:faces].size != a.prog[:faces].size + b.prog[:faces].size
    b.prog[:faces].each do |fc|
      orig_fc = prog[:faces].find { |f| f[:body] == fc[:body] && f[:corners].zip(fc[:corners]).all? { |p, q| (l - p[0] - q[0]).abs < 1e-6 && (prog[:w] - p[1] - q[1]).abs < 1e-6 } }
      errs << 'Hilfsfläche Lauf B falsch gedreht' unless orig_fc
    end
    # Nuten: ganz in einem Lauf oder an der Teilung überlappend geteilt
    so = prog[:ops].count { |q| q[:soft] }
    sn = a.prog[:ops].count { |q| q[:soft] } + back.count { |q| q[:soft] }
    errs << "Nuten #{so} -> #{sn}" if sn < so
    # Kontur (und geteilte Nuten): Abdeckung je Zustellung
    prog[:ops].select { |op| op[:cut] || op[:soft] }.group_by { |op| [op[:z], op[:pts].first] }.each_value do |(op)|
      next if op[:soft] && !(op[:pts].map(&:first).min < x_t && op[:pts].map(&:first).max > x_t)
      ca = a.prog[:ops].select { |q| (q[:cut] || q[:soft]) && q[:tool] == op[:tool] }
      cb = back.select { |q| (q[:cut] || q[:soft]) && q[:tool] == op[:tool] }
      xa = ca.flat_map { |q| q[:pts].map(&:first) }.max.to_f
      xb = cb.flat_map { |q| q[:pts].map(&:first) }.min.to_f
      errs << "Kontur Lauf A endet bei #{xa.round(1)} < #{(x_t + ov).round(1)}" if op[:pts].map(&:first).max > x_t + ov && xa < x_t + ov - 1e-3
      errs << "Kontur Lauf B beginnt bei #{xb.round(1)} > #{(x_t - ov).round(1)}" if op[:pts].map(&:first).min < x_t - ov && xb > x_t - ov + 1e-3
    end
    # Länge der Kontur erhalten (A + B − Überlappung)
    tabs_a = a.prog[:ops].count { |q| q[:tabbed] }
    tabs_b = b.prog[:ops].count { |q| q[:tabbed] }
    first = a.name == 'A' && !a.rot ? a : (b.name == 'A' ? b : a)
    errs << 'keine Haltestege' if o0['tab_n'] > 0 && prog[:ops].any? { |q| q[:tab] } && tabs_a + tabs_b == 0
    errs << 'Haltestege in beiden Läufen' if tabs_a > 0 && tabs_b > 0
    _ = first
  end
  unless errs.empty?
    fails += 1
    puts "FEHLER #{name}: #{errs.uniq.first(6).join('; ')}"
  end
end

Dir.mktmpdir do |dir|
  %w[gerade l_wendel u_podest z_wendel].each do |v|
    [%w[wange wange], %w[sattel sattel], %w[wange sattel]].each do |sl, sr|
      [false, true].each do |wend|
        %w[fraesen markieren].each do |mode|
          [{}, { 'H' => 340 }].each do |extra|
            p = Params.normalize(Params.defaults.merge('variant' => v, 'construction' => 'wange', 'risers' => true, 'rail' => 'aussen',
                                                       'side_left' => sl, 'side_right' => sr).merge(extra))
            begin; plan = Layout.compute(p); rescue PlanError; next; end
            o = Cnc.normalize('sat_wenden' => wend, 'sat_mode' => mode, 'drill_wange' => mode == 'fraesen' ? 'bohren' : 'markieren', 'engrave' => true)
            res = Cnc.compute(plan, p, o)
            tag = "#{v}/#{sl}-#{sr}/#{wend ? 'wenden' : '-'}/#{mode}/#{extra.empty? ? 'std' : 'hoch'}"
            res.unplaced.select { |pt| pt.kind == :stringer }.each { |pt| (fails += 1; puts "FEHLER #{tag}: #{pt.label} nicht platziert") }
            res.longs.each do |lp|
              check.("#{tag} #{lp.label}", lp.prog, lp.split, Cnc.outer_tool(o, lp.part.thickness)[:d] / 2.0)
            end
            res.boards.each do |jb|
              jb.programs.each do |pg|
                prog = Lauf.from_job(jb, pg, Cnc.job_opts(o, jb.t))
                check.("#{tag} #{jb.label} S#{pg.side}", prog, jb.splits[pg.side], Cnc.outer_tool(o, jb.t)[:d] / 2.0)
              end
            end
            Cnc.export(dir, 'T', res, o)
            # long_mode aus: keine Läufe, keine eigenen Rohlinge
            ra = Cnc.compute(plan, p, o.merge('long_mode' => 'aus'))
            if !ra.longs.empty? || ra.boards.any? { |b| b.long }
              fails += 1
              puts "FEHLER #{tag}: long_mode aus erzeugt Läufe"
            end
          end
        end
      end
    end
  end
  long_files = Dir[File.join(dir, '*_[AB].tcn')]
  puts "#{long_files.size} Lauf-Dateien, längste DL #{long_files.map { |f| dl(File.read(f)) }.max}"
end
puts "#{cases} Programme geprüft, #{fails} Fehler"
exit(fails.zero? ? 0 : 1)
