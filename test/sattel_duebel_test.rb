# Dübel Stufe – aufgesattelte Wange:
#  * je Auflager sat_dowels Dübel, Punkt im Grundriss auf der Stufe und auf der
#    Wangenmitte (sat_inset + sat_t/2 von der Laufkante)
#  * Bohrung im Wangenprogramm: Ansatz auf der Auflagerkante, Richtung ins Material
#  * keine Überschneidung mit Stabbohrungen in derselben Stufe
#  * TCN enthält die Bohrungen (Hilfsfläche), Nacharbeit die Bohrliste
require_relative 'su_mock'
$LOAD_PATH.unshift File.expand_path('../src', __dir__)
%w[params geometry fit stringers builder parts nesting tcn wange3d fraesliste cnc].each { |f| require "jt_treppenbau/#{f}" }
include JTools::Treppenbau
require 'tmpdir'

def pip(pt, poly)
  c = false; j = poly.size - 1
  poly.each_with_index do |a, i|
    b = poly[j]
    c = !c if (a[1] > pt[1]) != (b[1] > pt[1]) && pt[0] < (b[0] - a[0]) * (pt[1] - a[1]) / (b[1] - a[1]) + a[0]
    j = i
  end
  c
end

def seg_dist(pt, a, b)
  d = Geo.sub(b, a); l2 = Geo.dot(d, d)
  f = l2 < 1e-12 ? 0 : [[Geo.dot(Geo.sub(pt, a), d) / l2, 0].max, 1].min
  Geo.dist(pt, Geo.add(a, Geo.mul(d, f)))
end

fails = 0; n = 0; ndw = 0; nmoved = 0
o0 = Cnc.normalize({})
dir = Dir.mktmpdir
(ARGV[0] ? [ARGV[0]] : Params::NOSPIRAL).each do |v|
  %w[rechts links].each do |dr|
    [%w[beide bohren], %w[aussen markieren], %w[keins bohren]].each do |rail, dw|
      p = Params.normalize(Params.defaults.merge('variant' => v, 'direction' => dr, 'risers' => true, 'rail' => rail,
                                                 'side_left' => 'sattel', 'side_right' => 'sattel'))
      begin; plan = Layout.compute(p); rescue PlanError; next; end
      o = o0.merge('p_treads' => false, 'p_risers' => false, 'p_rail' => false, 'p_posts' => false, 'drill_wange' => dw)
      res = Cnc.compute(plan, p, o)
      n += 1
      errs = []
      bars = rail == 'keins' ? [] : Railing.compute(plan, p)[:sides]
      lw = plan.lines_w
      ext = p['nosing'] + p['riser_t']
      seen = Hash.new(0)
      res.boards.each do |jb|
        dws = jb.dowels || []
        ndw += dws.size
        dws.each do |d|
          seen[[jb.sb[:which], d[:k]]] += 1
          reg = plan.region(lw[d[:k]], [lw[d[:k] + 1] + ext, plan.wtot].min).map(&:first)
          errs << "#{jb.label} Dübel Stufe #{d[:k] + 1} nicht unter der Stufe" unless pip(d[:pt], reg)
          bd = plan.send(jb.sb[:which])
          e = bd.pts.each_cons(2).map { |a, b| seg_dist(d[:pt], a, b) }.min
          nom = p['sat_inset'] + p['sat_t'] / 2.0
          errs << "#{jb.label} Dübel Stufe #{d[:k] + 1}: #{e.round(2)} cm von der Laufkante statt #{d[:side].round(2)}" if (e - d[:side]).abs > 0.05
          errs << "#{jb.label} Dübel Stufe #{d[:k] + 1}: #{e.round(2)} cm von der Laufkante (Wangenmitte #{nom})" if e < nom - 0.3
          errs << "#{jb.label} Dübel Stufe #{d[:k] + 1} zu tief (#{d[:depth_t]})" if d[:depth_t] > p['tread_t'] - 0.99
          bars.select { |sd| sd[:which] == jb.sb[:which] }.flat_map { |sd| sd[:bars] }.each do |b|
            next unless b[:tread] == d[:k] && b[:drill]
            next unless Geo.dist(b[:pt], d[:pt]) < (b[:drill][:d] + d[:d]) / 2.0
            errs << "#{jb.label} Dübel Stufe #{d[:k] + 1} trifft Stabbohrung" if b[:drill][:depth] + d[:depth_t] > p['tread_t'] - 0.01
          end
        end
        dr_ = jb.programs[0].drills
        errs << "#{jb.label} #{dr_.size} Bohrungen statt #{dws.size}" if dr_.size != dws.size
        dr_.each do |h|
          ol = jb.outline
          e = ol.each_index.map { |i| seg_dist([h[:x], h[:y]], ol[i], ol[(i + 1) % ol.size]) }.min
          errs << "#{jb.label} Dübelbohrung #{e.round(2)} mm neben der Kante" if e > 0.05
          q = Geo.add([h[:x], h[:y]], Geo.mul(Tcn.drill_dir(h), h[:depth] / 2.0))
          errs << "#{jb.label} Dübelbohrung nicht ins Material" unless pip(q, ol)
        end
      end
      # je Stufe mit aufgesattelter Wange (Auflager vorhanden) die volle Anzahl
      seen.each { |(w, k), c| errs << "Stufe #{k + 1} #{w}: #{c} Dübel" if c < p['sat_dowels'] }
      errs << 'keine Dübel' if res.boards.any? && seen.empty?
      files = Cnc.export(dir, 't', res, o)
      tcn = files.select { |f| f.include?('_Wange_') }.map { |f| File.binread(f) }.join
      if dw == 'bohren'
        errs << 'TCN ohne Dübelbohrung' if ndw > 0 && !tcn.include?('Duebel Stufe')
      else
        errs << 'TCN mit Dübel-Hilfsfläche trotz markieren' if tcn.include?('Duebel Stufe')
      end
      na = files.find { |f| f.end_with?('_Nacharbeit.txt') }
      errs << 'Bohrliste fehlt' if seen.any? && !(na && File.binread(na).force_encoding('Windows-1252').encode('UTF-8').include?('Dübel Trittstufen'))
      fails += 1 unless errs.empty?
      puts format('%-14s %-6s %-6s %-9s Wangen %2d Dübel %3d %s', v, dr, rail, dw, res.boards.size,
                  res.boards.sum { |b| (b.dowels || []).size }, errs.empty? ? 'ok' : 'FEHLER ' + errs.uniq.first(3).join(' | '))
    end
  end
end
puts "#{n} Fälle, #{ndw} Dübel, #{fails} Fehler"
