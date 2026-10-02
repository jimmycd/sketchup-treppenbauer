# Test: Registrierung, Neuladen ohne Neustart, Installation über laufende Version,
# Entwickler-Loader. SketchUp-UI-API gemockt.
require 'fileutils'
require 'tmpdir'
require_relative 'su_mock'

$log = Hash.new(0)
$timers = []
$loaded = []
module Sketchup
  def self.register_extension(ext, load_now); $log[:register] += 1; ext.load! if load_now; true; end
  def self.require(p); f = p.end_with?('.rb') ? p : "#{p}.rb"; return false if $loaded.include?(f); $loaded << f; load f; true; end
  def self.platform; :platform_win; end
  def self.version; '24.0'; end
  def self.active_model; nil; end
end
class SketchupExtension
  attr_accessor :description, :version, :creator, :copyright
  def initialize(name, path); @name = name; @path = path; @loaded = false; end
  def load!; @loaded = true; Sketchup.require(@path); end
  def loaded?; @loaded; end
end
module UI
  class Menu
    def add_submenu(_n); $log[:submenu] += 1; self; end
    def add_item(*_a, &_b); $log[:menu_item] += 1; $menu_blocks << _b if _b; 1; end
    def add_separator; end
  end
  class Command
    attr_accessor :tooltip, :status_bar_text, :small_icon, :large_icon
    def initialize(_n, &b); @b = b; end
    def set_validation_proc(&_b); end
    def call; @b.call; end
  end
  class Toolbar
    def initialize(_n); $log[:toolbar] += 1; end
    def add_item(_c); end
    def restore; end
  end
  class HtmlDialog; STYLE_DIALOG = 0; end
  def self.menu(_n); Menu.new; end
  def self.add_context_menu_handler; $log[:ctx] += 1; end
  def self.messagebox(m); $log[:msg] += 1; $last_msg = m; end
  def self.start_timer(_t, _r, &b); $timers << b; end
end
MF_ENABLED = 0; MF_GRAYED = 1
$menu_blocks = []
$file_loaded = []
def file_loaded?(f); $file_loaded.include?(f); end
def file_loaded(f); $file_loaded << f; end
module Kernel
  alias_method :orig_require, :require
  def require(n); %w[sketchup.rb extensions.rb].include?(n) ? true : orig_require(n); end
end

$err = 0
def check(c, m); unless c; $err += 1; puts "FEHLER: #{m}"; end; end

src = File.expand_path('../src', __dir__)
plugins = Dir.mktmpdir('plugins')
inst = File.join(plugins, 'jt_treppenbau.rb')
FileUtils.cp_r(Dir[File.join(src, 'jt_treppenbau*')], plugins)

# 1) Start mit installierter Version
load inst
T = JTools::Treppenbau
check $log[:register] == 1, 'einmal registriert'
check T.respond_to?(:cmd_new), 'main geladen'
check $log[:submenu] == 1 && $log[:toolbar] == 1, 'Menü/Toolbar einmal'
check T::EXT_VERSION == '2.0.0', 'Version'

# 2) Neue Version auf Platte (Installation drüber), Code ändert sich
File.write(inst, File.read(inst).sub("'2.0.0'", "'2.0.1'"))
pf = File.join(plugins, 'jt_treppenbau', 'params.rb')
File.write(pf, File.read(pf).sub(/(module Params\n)/, "\\1      def self.reload_marker; 42; end\n"))
check !T::Params.respond_to?(:reload_marker), 'vorher alt'
$menu_blocks.last.call # Menü „Treppenbau neu laden“
check T::EXT_VERSION == '2.0.1', "Version nach Neuladen (#{T::EXT_VERSION})"
check T::Params.respond_to?(:reload_marker) && T::Params.reload_marker == 42, 'neuer Code aktiv'
check T.extension.version == '2.0.1', 'Erweiterungs-Manager zeigt neue Version'
check $log[:register] == 1, 'nicht doppelt registriert'
check $log[:submenu] == 1 && $log[:toolbar] == 1 && $log[:ctx] == 1, 'keine doppelten Menüs/Toolbars'
check $last_msg.include?('2.0.0 → 2.0.1'), "Meldung: #{$last_msg}"

# 3) SketchUp führt die Registrierungsdatei nach Installation selbst erneut aus → Auto-Neuladen
File.write(inst, File.read(inst).sub("'2.0.1'", "'2.0.2'"))
load inst
check $timers.size == 1, 'Auto-Neuladen geplant'
$timers.shift.call
check T::EXT_VERSION == '2.0.2' && $last_msg.include?('2.0.1 → 2.0.2'), "Auto-Neuladen: #{$last_msg}"
check $timers.empty?, 'keine Schleife'

# 4) Fehler im neuen Code → Meldung, kein Absturz
File.write(pf, File.read(pf) + "\n def kaputt(\n")
r = T.reload(quiet: true)
check r == false, 'Syntaxfehler wird gemeldet'
File.write(pf, File.read(pf).sub("\n def kaputt(\n", ''))
check T.reload(quiet: true) == true, 'danach wieder ok'

# 5) Zweite Kopie (Entwickler-Loader zuerst geladen, installierte danach) wird übersprungen
other = Dir.mktmpdir('other')
FileUtils.cp_r(Dir[File.join(src, 'jt_treppenbau*')], other)
File.write(File.join(other, 'jt_treppenbau.rb'), File.read(File.join(other, 'jt_treppenbau.rb')).sub("'2.0.0'", "'9.9.9'"))
load File.join(other, 'jt_treppenbau.rb')
check T::EXT_VERSION == '2.0.2' && $log[:register] == 1, 'fremde Kopie übersprungen'

puts "reload_test: #{$err} Fehler"
exit($err.zero? ? 0 : 1)
