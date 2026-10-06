# encoding: UTF-8
# Treppenbau – Hauptmodul: Menüs, Symbolleiste, Kontextmenü, Attribute.

require 'sketchup.rb'
require 'json'

module JTools
  module Treppenbau
    PATH    = File.dirname(__FILE__) unless defined?(PATH)
    PATH_UI = File.join(PATH, 'ui') unless defined?(PATH_UI)
    DICT    = 'JT_Treppenbau'.freeze unless defined?(DICT)

    # Untermodule in Ladereihenfolge. Mit `load` statt `require`, damit
    # „Treppenbau neu laden“ den geänderten Code ohne Neustart übernimmt.
    def self.module_files
      %w[params geometry fit transfer stringers railing builder dialog parts nesting tcn lauf wange3d cnc cnc_dialog]
    end

    def self.load_modules
      module_files.each { |f| load File.join(PATH, "#{f}.rb") }
    end

    verbose = $VERBOSE
    $VERBOSE = nil # Konstanten-Warnungen beim Neuladen unterdrücken
    begin
      load_modules
    ensure
      $VERBOSE = verbose
    end

    # --- Neu laden (Update ohne Neustart) ---------------------------------------
    #
    # Lädt Registrierungsdatei, main.rb und alle Untermodule von der Platte neu.
    # Offene Dialoge werden geschlossen (ihre Callbacks hängen am alten Code).
    # Grenzen: neue Menüpunkte/Buttons erscheinen erst nach Neustart; gelöschte
    # Methoden bleiben bis zum Neustart im Speicher.
    def self.reload(quiet: false)
      return if @reloading
      @reloading = true
      old = @old_version || (defined?(EXT_VERSION) ? EXT_VERSION : '?')
      @old_version = nil
      [(StairDialog.current if defined?(StairDialog)), (CncDialog.current if defined?(CncDialog))].each do |d|
        next unless d
        begin
          dlg = d.instance_variable_get(:@dlg)
          dlg.close if dlg
        rescue StandardError
          nil
        end
      end
      StairDialog.current = nil if defined?(StairDialog)
      CncDialog.current = nil if defined?(CncDialog)

      verbose = $VERBOSE
      $VERBOSE = nil
      count = 0
      begin
        load registrar if registrar && File.exist?(registrar)
        count += 1
        load File.join(PATH, 'main.rb') # lädt seinerseits alle Untermodule
        count += 1 + module_files.size
      ensure
        $VERBOSE = verbose
      end
      msg = "Treppenbau neu geladen: #{old} → #{EXT_VERSION} (#{count} Dateien aus #{PATH})"
      puts msg
      UI.messagebox(msg) unless quiet
      true
    rescue ScriptError, StandardError => e
      err = "Treppenbau: Fehler beim Neuladen – #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      puts err
      UI.messagebox("#{err}\n\nBitte SketchUp neu starten.") unless quiet
      false
    ensure
      @reloading = false
    end

    # --- Attribute ------------------------------------------------------------

    def self.stair?(ent)
      return false unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
      defn = ent.respond_to?(:definition) ? ent.definition : nil
      !defn.nil? && !defn.get_attribute(DICT, 'params').nil?
    end

    def self.read_params(defn)
      raw = defn.get_attribute(DICT, 'params')
      Params.normalize(raw ? JSON.parse(raw) : {})
    rescue JSON::ParserError
      Params.defaults
    end

    def self.write_params(defn, params)
      defn.set_attribute(DICT, 'params', JSON.generate(params))
      defn.set_attribute(DICT, 'version', EXT_VERSION)
    end

    def self.remember(params)
      @last = params.dup
      Sketchup.active_model.set_attribute(DICT, 'last', JSON.generate(params))
    end

    def self.last_params
      return Params.normalize(@last) if @last
      raw = Sketchup.active_model.get_attribute(DICT, 'last')
      raw ? Params.normalize(JSON.parse(raw)) : Params.defaults
    rescue StandardError
      Params.defaults
    end

    # Ausgewählte Treppe (auch wenn man sich in der Treppe befindet)
    def self.selected_stair
      model = Sketchup.active_model
      st = model.selection.find { |e| stair?(e) }
      return st if st
      path = model.active_path || []
      path.reverse.find { |e| stair?(e) }
    end

    # --- Befehle --------------------------------------------------------------

    def self.cmd_new
      StairDialog.open(nil)
    end

    def self.cmd_edit
      st = selected_stair
      if st
        StairDialog.open(st)
      else
        UI.messagebox('Bitte zuerst eine mit „Treppenbau“ erzeugte Treppe auswählen.')
      end
    end

    def self.cmd_cnc
      st = selected_stair
      if st
        CncDialog.open(st)
      else
        UI.messagebox('Bitte zuerst eine mit „Treppenbau“ erzeugte Treppe auswählen.')
      end
    end

    def self.icon(name, size)
      if Sketchup.platform == :platform_win && Sketchup.version.to_i >= 16
        File.join(PATH, 'icons', "#{name}.svg")
      else
        File.join(PATH, 'icons', "#{name}_#{size}.png")
      end
    end

    unless file_loaded?(__FILE__) || @ui_created
      @ui_created = true
      c_new = UI::Command.new('Neue Treppe…') { cmd_new }
      c_new.tooltip = 'Neue Treppe'
      c_new.status_bar_text = 'Erzeugt eine parametrische Treppe (gerade, gewendelt, Wendeltreppe).'
      c_new.small_icon = icon('treppe_neu', 16)
      c_new.large_icon = icon('treppe_neu', 24)

      c_edit = UI::Command.new('Treppe bearbeiten…') { cmd_edit }
      c_edit.tooltip = 'Treppe bearbeiten'
      c_edit.status_bar_text = 'Öffnet die Parameter der ausgewählten Treppe.'
      c_edit.small_icon = icon('treppe_bearbeiten', 16)
      c_edit.large_icon = icon('treppe_bearbeiten', 24)
      c_edit.set_validation_proc { selected_stair ? MF_ENABLED : MF_GRAYED }

      c_cnc = UI::Command.new('CNC-Export (TCN für TpaCAD)…') { cmd_cnc }
      c_cnc.tooltip = 'Treppe → TCN (dxf4tcn)'
      c_cnc.status_bar_text = 'Stufen, Wangen und Geländerteile auf Rohplatten verschachteln und als TCN für TpaCAD ausgeben.'
      c_cnc.small_icon = icon('treppe_tcn', 16)
      c_cnc.large_icon = icon('treppe_tcn', 24)
      c_cnc.set_validation_proc { selected_stair ? MF_ENABLED : MF_GRAYED }

      menu = UI.menu('Extensions').add_submenu('Treppenbau')
      menu.add_item(c_new)
      menu.add_item(c_edit)
      menu.add_separator
      menu.add_item(c_cnc)
      menu.add_separator
      menu.add_item('Treppenbau neu laden') { Treppenbau.reload }

      tb = UI::Toolbar.new('Treppenbau')
      tb.add_item(c_new)
      tb.add_item(c_edit)
      tb.add_item(c_cnc)
      tb.restore

      UI.add_context_menu_handler do |cm|
        if Sketchup.active_model.selection.any? { |e| stair?(e) }
          cm.add_separator
          cm.add_item(c_edit)
          cm.add_item(c_cnc)
        end
      end

      file_loaded(__FILE__)
    end
  end
end
