# Fräsliste (.xmlst) beim TCN-Export:
#  * je geschriebener TCN genau eine <Row>, Reihenfolge wie im Export
#  * UTF-8 mit BOM, CRLF, wohlgeformtes XML, Aufbau wie Liste_Regalbad.xmlst (csv2tcn)
#  * LENGTH/HEIGHT/THICKNESS = DL/DH/DS der TCN, FIELD aus der Kopfzeile (s1 → 9)
#  * Pfad mit Windows-Trenner in NAME und FileName
#  * Überlange Wange: Lauf A und B als eigene Zeilen
require_relative 'su_mock'
$LOAD_PATH.unshift File.expand_path('../src', __dir__)
%w[params geometry fit stringers builder parts nesting tcn lauf wange3d fraesliste cnc].each { |f| require "jt_treppenbau/#{f}" }
include JTools::Treppenbau
require 'tmpdir'
require 'rexml/document'

$fail = 0
def check(cond, msg)
  puts "#{cond ? 'ok  ' : 'FEHL'} #{msg}"
  $fail += 1 unless cond
end

def rows_of(xml)
  doc = REXML::Document.new(xml.sub("﻿", ''))
  doc.elements.to_a('List/Rows/Row').map do |r|
    h = { 'FileName' => r.attributes['FileName'] }
    r.elements.each('Cell') { |c| h[c.attributes['Name']] = c.text.to_s }
    h
  end
end

# 1) Einfache TCN-Dateien direkt
Dir.mktmpdir do |dir|
  a = File.join(dir, 'T_Stufe.tcn')
  b = File.join(dir, 'T_Wange_A.tcn')
  File.binwrite(a, "TPA\\ALBATROS\\EDICAD\\02.00:1224:r0w0h0s1\r\n::SIDE=1;\r\n::UNm DL=2800 DH=2070 DS=40\r\n")
  File.binwrite(b, "TPA\\ALBATROS\\EDICAD\\02.00:1224:r0w0h0s3\r\n::SIDE=1;\r\n::UNm DL=3200.5 DH=330 DS=52\r\n")
  path = Fraesliste.write(dir, 'Treppe Ä', [a, File.join(dir, 'x.csv'), b], '\\')
  check(File.basename(path) == 'Liste_Treppe Ä.xmlst', 'Dateiname Liste_<base>.xmlst')
  raw = File.binread(path)
  check(raw.start_with?("\xEF\xBB\xBF".b), 'BOM')
  check(!raw.gsub("\r\n", '').include?("\n"), 'nur CRLF')
  xml = raw.force_encoding('UTF-8')
  rows = rows_of(xml)
  check(rows.size == 2, '2 Zeilen (CSV ignoriert)')
  check(rows[0]['FIELD'] == '9' && rows[1]['FIELD'] == '3', "FIELD s1→9, s3→3 (#{rows.map { |r| r['FIELD'] }})")
  check(rows[0]['LENGTH'] == '2800' && rows[0]['HEIGHT'] == '2070' && rows[0]['THICKNESS'] == '40', 'Maße Zeile 1')
  check(rows[1]['LENGTH'] == '3200.5', 'Dezimalmaß bleibt')
  win = File.expand_path(a).tr('/', '\\')
  check(rows[0]['NAME'] == "\"#{win}\"" && rows[0]['FileName'] == "\"#{win}\"", 'Pfad in Anführungszeichen mit \\')
  check(xml.include?('<Rows Name="Liste_Treppe Ä.xmlst" Repetitions="1"'), 'Rows-Kopf')
  check(Fraesliste.write(dir, 'leer', [File.join(dir, 'x.csv')]).nil?, 'ohne TCN keine Liste')
end

# 2) Kompletter Export inkl. überlanger Wangen
p = Params.normalize(Params.defaults.merge('variant' => 'gerade', 'construction' => 'wange', 'risers' => true,
                                           'height' => 4200.0, 'rail' => 'aussen'))
plan = Layout.compute(p)
o = Cnc.normalize({})
res = Cnc.compute(plan, p, o)
Dir.mktmpdir do |dir|
  files = Cnc.export(dir, 'T', res, o)
  tcns = files.select { |f| f.end_with?('.tcn') }
  liste = files.find { |f| f.end_with?('.xmlst') }
  check(liste && File.exist?(liste), 'Export liefert Liste_T.xmlst')
  rows = rows_of(File.binread(liste).force_encoding('UTF-8'))
  check(rows.size == tcns.size, "eine Zeile je TCN (#{rows.size}/#{tcns.size})")
  check(rows.map { |r| File.basename(r['NAME'].delete('"').tr('\\', '/')) } == tcns.map { |f| File.basename(f) }, 'Reihenfolge wie Export')
  tcns.each_with_index do |f, i|
    hd = Fraesliste.header(f)
    ok = rows[i]['LENGTH'].to_f == hd[:l].to_f && rows[i]['HEIGHT'].to_f == hd[:w].to_f && rows[i]['THICKNESS'].to_f == hd[:t].to_f
    check(ok && rows[i]['FIELD'] == Fraesliste.field_for(hd[:field]).to_s, "#{File.basename(f)}: Maße/Feld (s#{hd[:field]} → #{rows[i]['FIELD']})")
  end
  fields = rows.map { |r| r['FIELD'] }
  check(fields.include?('3') && fields.include?('6'), "Läufe A (s3) und B (s6) als eigene Zeilen (#{fields.uniq})")
end

puts $fail.zero? ? 'ALLE OK' : "#{$fail} FEHLER"
exit($fail.zero? ? 0 : 1)
