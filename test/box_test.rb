# Test: freie Planung mit Grundmaß (Gesamtbreite / Gesamttiefe) – Fehler 3
require_relative 'su_mock'
$LOAD_PATH.unshift File.expand_path('../src', __dir__)
%w[params geometry fit stringers builder].each { |f| require "jt_treppenbau/#{f}" }
include JTools::Treppenbau
errs = 0; n = 0
fp = ->(plan, p) { x0, y0, x1, y1 = Fit.footprint(plan, p); [x1 - x0, y1 - y0, x0, y0] }
cases = [
  ['gerade', 110, 400], ['gerade', 0, 420], ['gerade', 120, 0], ['gerade_podest', 100, 520], ['gerade_podest', 0, 560],
  ['l_podest', 300, 280], ['l_podest', 0, 300], ['l_podest', 260, 0],
  ['l_wendel', 250, 260], ['l_wendel', 0, 280], ['l_wendel', 240, 0],
  ['u_podest', 210, 290], ['u_podest', 0, 300], ['u_podest', 220, 0],
  ['u_wendel', 210, 230], ['u_wendel', 0, 240],
  ['z_podest', 300, 220], ['z_wendel', 260, 200], ['z_wendel', 0, 220], ['z_podest', 300, 0]
]
sides = [%w[wange wange], %w[sattel frei], %w[wange frei]]
cases.each do |v, tw, tl|
  %w[rechts links].each do |dir|
    sides.each do |sl, sr|
      n += 1
      p = Params.normalize(Params.defaults.merge('variant' => v, 'direction' => dir, 'total_w' => tw, 'total_l' => tl,
                                                 'side_left' => sl, 'side_right' => sr))
      tag = format('%-14s %-6s %-6s/%-6s B=%-4s T=%-4s', v, dir, sl, sr, tw, tl)
      begin
        plan = Layout.compute(p)
      rescue PlanError => e
        puts "#{tag}: PlanError #{e.message}"; errs += 1; next
      end
      w, d, x0, y0 = fp.(plan, p)
      bad = []
      bad << format('Breite %.2f', w) if tw > 0 && (w - tw).abs > 0.1
      short = plan.warnings.any? { |x| x.start_with?('Gesamttiefe wird um') }
      if short # Drachenstufen nicht vereinbar: Treppe liegt hinten an, vorn bleibt Platz (Warnung)
        bad << format('Tiefe %.2f > %.2f', d, tl) if d > tl + 0.1
        bad << format('Ursprung %.2f/%.2f', x0, y0) if x0.abs > 0.1 || (y0 + d - tl).abs > 0.1
      else
        bad << format('Tiefe %.2f', d) if tl > 0 && (d - tl).abs > 0.1
        bad << format('Ursprung %.2f/%.2f', x0, y0) if x0.abs > 0.1 || y0.abs > 0.1
      end
      bad << 'Text Antritt verschoben' if plan.warnings.any? { |x| x.start_with?('Antritt um') }
      bad << 'kein Grundmaß' unless plan.space && plan.space[:box]
      bad << 'Raum-Text' if plan.info.any? { |k, _| k =~ /Wand|Raum/ }
      if tw <= 0 # Breite aus Parametern: wie freie Planung
        nat = Layout.compute(p.merge('total_w' => 0, 'total_l' => 0))
        nw, = fp.(nat, p)
        bad << format('Breite %.2f statt %.2f', w, nw) if (w - nw).abs > 0.1
      end
      errs += 1 unless bad.empty?
      line = format('%s n=%d a=%.2f b=%.1f  %.1f x %.1f', tag, plan.n, plan.a, plan.b, w, d)
      puts bad.empty? ? line : "#{line}  FEHLER: #{bad.join(', ')}"
      plan.warnings.each { |x| puts "     ! #{x}" } if ENV['W']
    end
  end
end
# ohne Grundmaß unverändert, Raum-Modus ignoriert total_*
p0 = Params.normalize(Params.defaults.merge('variant' => 'l_wendel'))
a = Layout.compute(p0); b = Layout.compute(p0.merge('fit_mode' => 'raum', 'space_l' => 300, 'space_w' => 260))
c = Layout.compute(p0.merge('fit_mode' => 'raum', 'space_l' => 300, 'space_w' => 260, 'total_w' => 150, 'total_l' => 150))
(errs += 1; puts 'FEHLER: freie Planung ohne Grundmaß hat space') if a.space
(errs += 1; puts 'FEHLER: Raum-Modus durch total_* verändert') if b.preview_data.to_s != c.preview_data.to_s
s = Layout.compute(p0.merge('variant' => 'spindel', 'total_w' => 150, 'total_l' => 150))
(errs += 1; puts 'FEHLER: Wendeltreppe mit Grundmaß') if s.space
# zu klein -> verständliche Meldung
%w[gerade l_podest u_wendel].each do |v|
  begin
    pl = Layout.compute(p0.merge('variant' => v, 'total_l' => 120, 'total_w' => 120))
    if pl.warnings.empty?
      errs += 1; puts "FEHLER: #{v} zu kleines Grundmaß ohne Warnung"
    else
      puts "#{v} zu klein: Warnung #{pl.warnings.first}"
    end
  rescue PlanError => e
    puts "#{v} zu klein: #{e.message}"
    (errs += 1; puts 'FEHLER: Raum im Text') if e.message =~ /Raum/
  end
end
puts "#{n} Fälle, #{errs} Fehler"
