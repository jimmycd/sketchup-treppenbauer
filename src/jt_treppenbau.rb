# encoding: UTF-8
# Treppenbau – parametrische Treppen für SketchUp
# Gerade, viertel-/halbgewendelte, dreiläufige Treppen und Wendeltreppen,
# jederzeit über die gespeicherten Parameter änderbar.
#
# Ab 2.0.0 ohne Neustart aktualisierbar:
#   Erweiterungs-Manager → „Erweiterung installieren“ (neue .rbz drüber, ohne Deinstallation)
#   → Erweiterungen › Treppenbau › „Treppenbau neu laden“.
# Diese Datei darf mehrfach ausgeführt werden (Neuladen, Installation über die alte Version).

require 'sketchup.rb'
require 'extensions.rb'

module JTools
  module Treppenbau
    reg_file = File.expand_path(__FILE__)

    # Läuft schon eine Treppenbau-Instanz aus einem anderen Ordner (z. B. der
    # Entwickler-Loader jt_aa_treppenbau_dev.rb lädt aus E:\sketchup-treppe\src),
    # wird diese Kopie übersprungen – erste geladene gewinnt.
    if @registrar && @registrar.casecmp(reg_file) != 0
      puts "Treppenbau: #{reg_file} übersprungen – aktiv ist #{@registrar}"
    else
      @old_version = EXT_VERSION if @extension && !@reloading && defined?(EXT_VERSION)
      verbose = $VERBOSE
      $VERBOSE = nil # „already initialized constant“ beim erneuten Ausführen unterdrücken
      EXT_VERSION = '2.9.0'.freeze
      $VERBOSE = verbose

      desc = 'Parametrische Treppen: gerade Läufe, Podest- und Wendelstufen-Treppen (L/U/dreiläufig) ' \
             'sowie Wendeltreppen mit Spindel oder Auge. Raumeinpassung ohne Luft (Wände, Wandwinkel, Treppenloch), ' \
             'je Seite Wange / aufgesattelt / frei. Parameterdialog mit Grundrissvorschau, CNC-Export (TCN für TpaCAD, wie dxf4tcn), ' \
             'Prüfung nach DIN-18065-Richtwerten und nachträglicher Änderung. Update ohne Neustart: „Treppenbau neu laden“.'

      if @extension
        # Erneut ausgeführt (Neuladen oder Installation über die laufende Version):
        # nur Angaben aktualisieren, nicht ein zweites Mal registrieren.
        @extension.version = EXT_VERSION
        @extension.description = desc
        # Ruft SketchUp diese Datei nach „Erweiterung installieren“ selbst erneut auf,
        # wird der neue Code gleich nachgeladen (sonst: Menü „Treppenbau neu laden“).
        if !@reloading && @extension.loaded? && respond_to?(:reload)
          UI.start_timer(0, false) { Treppenbau.reload(quiet: false) }
        end
      else
        @registrar = reg_file
        ext = SketchupExtension.new('Treppenbau', File.join(File.dirname(reg_file), 'jt_treppenbau', 'main'))
        ext.description = desc
        ext.version = EXT_VERSION
        ext.creator = 'JTools'
        ext.copyright = '2026'
        @extension = ext
        Sketchup.register_extension(ext, true)
      end
    end

    class << self
      attr_reader :registrar, :extension
    end
  end
end
