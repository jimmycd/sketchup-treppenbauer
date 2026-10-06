# 3D-Körper der aufgesattelten Wangen (Loft aus zwei Flächenumrissen):
# geschlossen (jede Kante an genau 2 Flächen), Volumen > 0 – alle Nicht-
# Wendelformen, beide Seiten aufgesattelt, Gehrung/stumpf, frei/Raum.
require_relative 'su_mock'
$LOAD_PATH.unshift File.expand_path('../src', __dir__)
%w[params geometry fit stringers builder].each { |f| require "jt_treppenbau/#{f}" }
include JTools::Treppenbau
src = File.read(File.join(__dir__, 'build_test.rb'))
eval(src[/def leaf_groups.*?\nend\n/m]); eval(src[/def volume.*?\nend\n/m])
fails = 0; total = 0; n = 0
%w[gerade kurve].each do |form|
  %w[stumpf].each do |joint|
    Params::NOSPIRAL.each do |v|
      [{}, { 'fit_mode' => 'raum', 'space_l' => 350, 'space_w' => 260, 'angle_left' => 84 },
       { 'fit_mode' => 'raum', 'space_l' => 400, 'space_w' => 300, 'angle_left' => 100, 'angle_right' => 80 }].each do |extra|
        %w[rechts links].each do |dir|
          [true, false].each do |ris|
            p = Params.normalize(Params.defaults.merge('variant' => v, 'direction' => dir, 'risers' => ris, 'sat_joint' => joint, 'rail' => 'keins',
                                                       'side_left' => 'sattel', 'side_right' => 'sattel', 'str_form' => form).merge(extra))
            model = Sketchup::Model.new
            defn = Sketchup::ComponentDefinition.new(model)
            begin; Builder.build(defn, p); rescue PlanError; next; end
            n += 1
            leaf_groups(defn.entities).each do |path, g|
              next unless path.last.to_s.start_with?('Aufgesattelte')
              total += 1
              edges = g.entities.items.grep(Sketchup::Edge)
              nonman = edges.count { |e| e.faces.size != 2 }
              vol = volume(g)
              next unless nonman > 0 || vol <= 0
              fails += 1
              puts "#{form} #{joint} #{v} #{extra.empty? ? 'frei' : 'raum'} #{dir} ris=#{ris}: #{path.last} nonmanifold=#{nonman} vol=#{vol.round(1)}"
            end
          end
        end
      end
    end
  end
end
puts "#{n} Treppen, #{total} Sattelwangen-Körper, #{fails} Fehler"
