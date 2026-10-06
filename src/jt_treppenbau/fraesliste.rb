# encoding: UTF-8
# Treppenbau – Fräsliste für TpaCAD (Sammelliste .xmlst) zu den TCN-Dateien
# eines Exports. Aufbau wie in csv2tcn (Liste_<Name>.xmlst): UTF-8 mit BOM,
# CRLF, je TCN-Datei eine <Row> mit vollem Windows-Pfad.
#
# Die Werte je Zeile kommen nur aus den geschriebenen TCN-Dateien selbst
# (Kopfzeile: Feld s<n>, ::UNm DL/DH/DS), damit die Liste unabhängig davon
# bleibt, welche Teile der Export als TCN schreibt. (ohne SketchUp-API)

module JTools
  module Treppenbau
    module Fraesliste
      module_function

      # FIELD in der Liste je Feld aus der TCN-Kopfzeile (…:r0w0h0s<n>).
      # s1 (Standard) → 9 wie in csv2tcn (Liste_Regalbad.xmlst).
      # s3 (Feld N1, Lauf A) und s6 (Feld N, Lauf B): vorerst dieselbe Nummer –
      # in TpaCAD noch ungeprüft.
      FIELD_BY_HEADER = { 1 => 9, 3 => 3, 6 => 6 }.freeze
      FIELD_DEFAULT = 9

      # Schreibt dir/Liste_<base>.xmlst für alle .tcn in files (Reihenfolge
      # bleibt). Liefert den Pfad oder nil, wenn keine TCN dabei ist.
      # sep: Pfadtrenner in der Liste (Windows: '\'; nil = Pfad unverändert)
      def write(dir, base, files, sep = File::ALT_SEPARATOR)
        tcns = files.select { |f| f.to_s.downcase.end_with?('.tcn') }
        return nil if tcns.empty?
        name = "Liste_#{base}.xmlst"
        path = File.join(dir, name)
        rows = tcns.each_with_index.map do |f, i|
          full = File.expand_path(f)
          full = full.tr('/', sep) if sep
          row(i + 1, full, header(f))
        end
        File.binwrite(path, build(name, rows).encode('UTF-8').b)
        path
      end

      # Feld und Maße aus der TCN-Kopfzeile: { field:, l:, w:, t: }
      def header(path)
        text = File.binread(path).force_encoding('Windows-1252').encode('UTF-8', invalid: :replace, undef: :replace)
        lines = text.lines.first(5)
        s = lines.first.to_s[/:r\d+w\d+h\d+s(\d+)\s*\z/, 1]
        un = lines.find { |l| l.start_with?('::UN') }.to_s
        val = ->(k) { un[/\b#{k}=(-?[\d.]+)/, 1] }
        { field: s && s.to_i, l: val.('DL'), w: val.('DH'), t: val.('DS') }
      end

      def field_for(s)
        FIELD_BY_HEADER.fetch(s, FIELD_DEFAULT)
      end

      def build(name, rows)
        out = "﻿<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
        out << "<List>\n"
        out << "  <Rows Name=\"#{escape_attr(name)}\" Repetitions=\"1\" TL=\"0\" TH=\"0\" TS=\"0\" Criterion=\"\">\n"
        rows.each { |r| out << r }
        out << "  </Rows>\n"
        out << "</List>\n"
        out.gsub("\n", "\r\n")
      end

      def row(index, file_path, hd)
        q = "\"#{file_path}\""
        cells = [
          ['DRAW', 281, '1'],
          ['ESEC', 165, '1'],
          ['NAME', 161, escape_text(q)],
          ['REPETITIONS', 164, '1'],
          ['EXECUTED', 288, '0'],
          ['FIELD', 171, field_for(hd[:field]).to_s],
          ['ROTATION', 286, '1'],
          ['MIRROR', 284, '0'],
          ['HOOKOPTI', 600, '0'],
          ['LENGTH', 168, num(hd[:l])],
          ['HEIGHT', 169, num(hd[:w])],
          ['THICKNESS', 170, num(hd[:t])],
          ['COMMENT', 162, ''],
          ['UNIT', 163, '1'],
          ['HOOK', 282, '0'],
          ['TIME', 223, '00:00:00'],
          ['OFFSET X', 277, '0'],
          ['OFFSET Y', 278, '0'],
          ['OFFSET Z', 279, '0']
        ]
        out = "    <Row Index=\"#{index}\" SavedID=\"1\" FileName=\"#{escape_attr(q)}\">\n"
        cells.each { |n, t, v| out << "      <Cell Name=\"#{n}\" DataType=\"#{t}\">#{v}</Cell>\n" }
        out << "    </Row>\n"
      end

      # Maß wie in der TCN, ohne überflüssige Nachkommastellen
      def num(s)
        return '0' if s.nil? || s.empty?
        v = s.to_f
        v == v.round ? v.round.to_s : s
      end

      def escape_text(s)
        s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
      end

      def escape_attr(s)
        escape_text(s).gsub('"', '&quot;')
      end
    end
  end
end
