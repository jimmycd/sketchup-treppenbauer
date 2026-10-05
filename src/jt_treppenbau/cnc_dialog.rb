# encoding: UTF-8
# Treppenbau – Dialog „CNC-Export (TCN)“ – verknüpft mit dxf4tcn:
# Fräser, Durchfräsen, Fräsrichtung, Gravurwerkzeug/-tiefe, TpaCAD-Pfad und
# letzter Ordner werden mit den dxf4tcn-Einstellungen geteilt.

require 'json'

module JTools
  module Treppenbau
    class CncDialog
      PREF = 'JT_Treppenbau_CNC'.freeze
      DXF4TCN = 'dxf4tcn'.freeze
      SHARED = %w[tool_outer overcut climb deco_tool deco_depth open_tpa].freeze

      @current = nil
      class << self
        attr_accessor :current
      end

      def self.open(instance)
        current.close if current && current.visible?
        self.current = new(instance)
        current.show
      end

      def initialize(instance)
        @instance = instance
      end

      def visible?
        @dlg && @dlg.visible?
      end

      def close
        @dlg.close if @dlg
      end

      # --- Einstellungen ----------------------------------------------------

      def self.load_opts
        o = {}
        Cnc::DEFAULTS.each do |k, d|
          ns = SHARED.include?(k) ? DXF4TCN : PREF
          o[k] = Sketchup.read_default(ns, k, d)
        end
        tool = o['tool_outer'].to_i
        o['tool_d'] = Sketchup.read_default(PREF, "tool_d_#{tool}", default_d(tool))
        Cnc.normalize(o)
      end

      def self.save_opts(o)
        o.each do |k, v|
          next unless Cnc::DEFAULTS.key?(k)
          ns = SHARED.include?(k) ? DXF4TCN : PREF
          Sketchup.write_default(ns, k, v)
        end
        Sketchup.write_default(PREF, "tool_d_#{o['tool_outer'].to_i}", o['tool_d'])
      end

      def self.default_d(tool)
        t = Cnc::OUTER_TOOLS.find { |_, nr, _| nr == tool }
        t ? t[2] : 12.0
      end

      # --- Dialog -----------------------------------------------------------

      def show
        @dlg = UI::HtmlDialog.new(
          dialog_title: 'Treppenbau – CNC-Export (TCN für TpaCAD)',
          preferences_key: 'JT_Treppenbau_CNC_Dialog',
          scrollable: false, resizable: true,
          width: 1280, height: 880, min_width: 900, min_height: 600,
          style: UI::HtmlDialog::STYLE_DIALOG
        )
        @dlg.set_file(File.join(Treppenbau::PATH_UI, 'cnc.html'))
        @dlg.add_action_callback('ready') { |_c| send_init }
        @dlg.add_action_callback('compute') { |_c, json| on_compute(json) }
        @dlg.add_action_callback('export') { |_c, json| on_export(json) }
        @dlg.add_action_callback('tooldia') { |_c, tool| js("CNC.setToolDia(#{Sketchup.read_default(PREF, "tool_d_#{tool.to_i}", CncDialog.default_d(tool.to_i)).to_f})") }
        @dlg.add_action_callback('tpacad') { |_c| choose_tpacad }
        @dlg.add_action_callback('close') { |_c| @dlg.close }
        @dlg.set_on_closed { CncDialog.current = nil if CncDialog.current == self }
        @dlg.show
      end

      def stair_params
        Treppenbau.read_params(@instance.definition)
      end

      def send_init
        p = stair_params
        cons = Params::SCHEMA.find { |f| f[:key] == 'construction' }[:options].find { |o| o[0] == p['construction'] }
        var = Params::VARIANTS.find { |v| v[0] == p['variant'] }
        data = {
          opts: CncDialog.load_opts,
          tools: Cnc::OUTER_TOOLS.map { |n, nr, d| { name: n, nr: nr, d: d } },
          stair: "#{var ? var[1] : p['variant']} – #{cons ? cons[1] : p['construction']}",
          construction: p['construction'],
          risers: p['risers'],
          rail: p['rail'],
          sattel: p['construction'] == 'wange' && [p['side_left'], p['side_right']].include?('sattel'),
          tpacad: Sketchup.read_default(DXF4TCN, 'tpacad_exe', '').to_s
        }
        js("CNC.init(#{JSON.generate(data)})")
      end

      def compute(json)
        o = Cnc.normalize(JSON.parse(json.to_s))
        p = stair_params
        plan = Layout.compute(p)
        [o, Cnc.compute(plan, p, o)]
      end

      def on_compute(json)
        unless @instance && @instance.valid?
          js("CNC.onResult(#{JSON.generate(ok: false, error: 'Die Treppe existiert nicht mehr.')})")
          return
        end
        o, res = compute(json)
        js("CNC.onResult(#{JSON.generate({ ok: true }.merge(Cnc.preview(res, o)))})")
      rescue PlanError => e
        js("CNC.onResult(#{JSON.generate(ok: false, error: e.message)})")
      rescue StandardError => e
        puts "[Treppenbau CNC] #{e.class}: #{e.message}\n#{e.backtrace.first(8).join("\n")}"
        js("CNC.onResult(#{JSON.generate(ok: false, error: "Interner Fehler: #{e.message}")})")
      end

      def on_export(json)
        o, res = compute(json)
        if res.sheets.empty? && (res.boards || []).empty?
          UI.messagebox('Keine Teile zum Exportieren.')
          return
        end
        CncDialog.save_opts(o)
        dir = Sketchup.read_default(DXF4TCN, 'last_dir', nil)
        model = Sketchup.active_model
        dir = File.dirname(model.path) if (dir.nil? || !File.directory?(dir)) && !model.path.to_s.empty?
        dir = File.join(ENV['USERPROFILE'] || ENV['HOME'] || '.', 'Desktop') if dir.nil? || !File.directory?(dir)
        target = UI.select_directory(title: 'Zielordner für die TCN-Dateien wählen', directory: dir)
        return if target.nil? || target.empty?
        Sketchup.write_default(DXF4TCN, 'last_dir', target)
        base = base_name
        files = Cnc.export(target, base, res, o)
        tcns = files.select { |f| f.end_with?('.tcn') }
        msg = "#{tcns.size} TCN-Datei(en) + Teileliste in #{target} gespeichert."
        js("CNC.status(#{JSON.generate(msg)}, 'ok')")
        Sketchup.status_text = "Treppenbau: #{msg}"
        open_in_tpacad(tcns.first) if o['open_tpa'] && tcns.first
      rescue StandardError => e
        puts "[Treppenbau CNC] #{e.class}: #{e.message}\n#{e.backtrace.first(8).join("\n")}"
        UI.messagebox("TCN-Export fehlgeschlagen:\n#{e.message}")
      end

      def base_name
        title = Sketchup.active_model.title.to_s.strip
        name = @instance.definition.name.to_s
        b = [title, name].reject(&:empty?).join('_')
        b = 'Treppe' if b.empty?
        b.gsub(/[\\\/:*?"<>|#]+/, '_').gsub(/\s+/, '_')
      end

      def open_in_tpacad(path)
        exe = Sketchup.read_default(DXF4TCN, 'tpacad_exe', '').to_s
        win = path.tr('/', '\\')
        if !exe.empty? && File.exist?(exe)
          pid = Process.spawn(exe, win)
          Process.detach(pid)
        else
          UI.openURL('file:///' + path.tr('\\', '/'))
        end
      rescue StandardError => e
        UI.messagebox("TpaCAD konnte nicht gestartet werden:\n#{e.message}")
      end

      def choose_tpacad
        exe = UI.openpanel('TpaCAD-Programm auswählen', 'C:\\', 'Programme|*.exe||')
        return unless exe
        Sketchup.write_default(DXF4TCN, 'tpacad_exe', exe.to_s)
        js("CNC.setTpacad(#{JSON.generate(exe.to_s)})")
      end

      def js(code)
        @dlg.execute_script(code) if @dlg
      end
    end
  end
end
