# encoding: UTF-8
# Treppenbau – ENTWICKLER-LOADER (nicht Teil der .rbz)
#
# Diese Datei in den SketchUp-Plugins-Ordner kopieren, z. B.
#   %APPDATA%\SketchUp\SketchUp 20xx\SketchUp\Plugins\
# Dann lädt SketchUp den Treppenbau direkt aus dem Quellordner unten.
# Nach jeder Änderung an den Quellen: Erweiterungen › Treppenbau › „Treppenbau neu laden“
# – keine .rbz bauen, kein Neustart.
#
# Der Name beginnt mit „jt_aa_“, damit SketchUp ihn vor einer installierten
# jt_treppenbau.rb lädt; die installierte Kopie wird dann übersprungen.
# Zurück zur installierten Version: diese Datei aus dem Plugins-Ordner entfernen
# und SketchUp neu starten.

TREPPENBAU_SRC = 'E:/sketchup-treppe/src' unless defined?(TREPPENBAU_SRC)

registrar = File.join(TREPPENBAU_SRC, 'jt_treppenbau.rb')
if File.exist?(registrar)
  load registrar
  puts "Treppenbau: Entwicklerversion aus #{TREPPENBAU_SRC}"
else
  puts "Treppenbau-Entwickler-Loader: #{registrar} nicht gefunden – installierte Version wird verwendet."
end
