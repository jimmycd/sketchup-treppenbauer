# encoding: UTF-8
# Treppenbau – Parameterdialog (UI::HtmlDialog)

require 'json'

module JTools
  module Treppenbau
    class StairDialog
      @current = nil
      class << self
        attr_accessor :current
      end

      def self.open(instance = nil)
        if current && current.visible?
          current.retarget(instance)
          return current
        end
        self.current = new(instance)
        current.show
        current
      end

      def initialize(instance)
        @instance = instance
        @live_op = false
      end

      def visible?
        @dlg && @dlg.visible?
      end

      def retarget(instance)
        @instance = instance
        @live_op = false
        send_init
        @dlg.bring_to_front
      end

      def show
        @dlg = UI::HtmlDialog.new(
          dialog_title: 'Treppenbau',
          preferences_key: 'JT_Treppenbau_Dialog',
          scrollable: false,
          resizable: true,
          width: 1220,
          height: 860,
          min_width: 900,
          min_height: 600,
          style: UI::HtmlDialog::STYLE_DIALOG
        )
        @dlg.set_file(File.join(Treppenbau::PATH_UI, 'dialog.html'))
        @dlg.add_action_callback('ready') { |_ctx| send_init }
        @dlg.add_action_callback('preview') { |_ctx, json, live| on_preview(json, live) }
        @dlg.add_action_callback('apply') { |_ctx, json, close| on_apply(json, close) }
        @dlg.add_action_callback('close') { |_ctx| @dlg.close }
        @dlg.set_on_closed { StairDialog.current = nil if StairDialog.current == self }
        @dlg.show
      end

      def editing?
        @instance && @instance.valid?
      end

      def send_init
        params = editing? ? Treppenbau.read_params(@instance.definition) : Treppenbau.last_params
        data = {
          schema: Params::SCHEMA,
          defaults: Params.defaults,
          params: params,
          mode: editing? ? 'edit' : 'new',
          name: editing? ? @instance.definition.name : nil
        }
        js("TB.init(#{JSON.generate(data)})")
      end

      def on_preview(json, live)
        p = Params.normalize(JSON.parse(json.to_s))
        res = analyse(p)
        if res[:ok] && live && editing?
          apply_params(p, true)
          res[:applied] = true
        end
        js("TB.onPreview(#{JSON.generate(res)})")
      rescue StandardError => e
        js("TB.onPreview(#{JSON.generate(ok: false, error: "Interner Fehler: #{e.message}")})")
      end

      def analyse(p)
        plan = Layout.compute(p)
        wange_info(plan, p)
        {
          ok: true,
          plan: plan.preview_data,
          info: plan.info,
          warnings: plan.warnings,
          derived: { 'n_steps' => plan.n, 'a_user' => plan.a.round(2), 'h' => plan.h.round(2) }
        }
      rescue PlanError => e
        { ok: false, error: e.message }
      end

      # Wangenbreite in der Vorschau anzeigen
      def wange_info(plan, p)
        r = Stringers.compute(plan, p)
        return if r[:wange].empty?
        if p['str_form'] == 'kurve'
          plan.info << ['Wangenbreite (geschwungen)', format('%.1f – %.1f cm', r[:wmin], r[:width])]
        else
          plan.info << ['Wangenbreite (konstant)', format('%.1f cm', r[:width])]
        end
        r[:warnings].each { |w| plan.warnings << w unless plan.warnings.include?(w) }
      rescue StandardError
        nil
      end

      def on_apply(json, close)
        p = Params.normalize(JSON.parse(json.to_s))
        res = apply_params(p, false)
        js("TB.onApplied(#{JSON.generate(res)})")
        @dlg.close if res[:ok] && (close == true || close.to_s == 'true')
      end

      def apply_params(p, live)
        model = Sketchup.active_model
        name = editing? ? 'Treppe ändern' : 'Treppe erstellen'
        # Live-Änderungen werden zu einem Undo-Schritt zusammengefasst
        model.start_operation(name, true, false, live && @live_op)
        begin
          if editing?
            @instance.make_unique if @instance.definition.count_instances > 1
            defn = @instance.definition
            plan = Builder.build(defn, p)
          else
            defn = model.definitions.add('Treppe')
            plan = Builder.build(defn, p)
            @instance = model.active_entities.add_instance(defn, Geom::Transformation.new)
            model.selection.clear
            model.selection.add(@instance)
          end
          Treppenbau.write_params(defn, p)
          Treppenbau.remember(p)
          model.commit_operation
          @live_op = live
          { ok: true, mode: 'edit', warnings: plan.warnings,
            message: live ? 'Modell aktualisiert.' : "#{name}: fertig (#{plan.n} Steigungen)." }
        rescue PlanError => e
          model.abort_operation
          { ok: false, error: e.message }
        rescue StandardError => e
          model.abort_operation
          puts "[Treppenbau] #{e.class}: #{e.message}\n#{e.backtrace.first(8).join("\n")}"
          { ok: false, error: "Fehler beim Erzeugen: #{e.message}" }
        end
      end

      def js(code)
        @dlg.execute_script(code) if @dlg
      end
    end
  end
end
