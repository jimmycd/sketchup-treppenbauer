require_relative 'su_mock'
$LOAD_PATH.unshift File.expand_path('../src', __dir__)
require 'jt_treppenbau/params'
require 'jt_treppenbau/geometry'
require 'jt_treppenbau/fit'
require 'jt_treppenbau/stringers'
require 'jt_treppenbau/builder'
require 'json'
include JTools::Treppenbau

def leaf_groups(ents, path = [], acc = [])
  ents.items.grep(Sketchup::Group).each do |g|
    if g.entities.items.grep(Sketchup::Group).empty?
      acc << [path + [g.name], g]
    else
      leaf_groups(g.entities, path + [g.name], acc)
    end
  end
  acc
end

def volume(g)
  v = 0.0
  g.entities.items.grep(Sketchup::Face).each do |f|
    p0 = f.pts[0]
    (1...f.pts.size - 1).each do |i|
      a = f.pts[i]; b = f.pts[i + 1]
      v += (p0.x * (a.y * b.z - a.z * b.y) - p0.y * (a.x * b.z - a.z * b.x) + p0.z * (a.x * b.y - a.y * b.x)) / 6.0
    end
  end
  v * 2.54**3
end

obj_dump = ARGV.include?('--obj')
fails = 0; total = 0
ROOMS = { 'gerade'=>[420,100], 'gerade_podest'=>[520,100], 'l_podest'=>[300,280], 'l_wendel'=>[270,250],
  'u_podest'=>[290,210], 'u_wendel'=>[240,210], 'z_podest'=>[220,300], 'z_wendel'=>[220,260], 'spindel'=>[180,180], 'auge'=>[200,200] }
Params::ALL.each do |v|
 [{}, {'fit_mode'=>'raum','space_l'=>ROOMS[v][0],'space_w'=>ROOMS[v][1],'angle_left'=>86,'angle_right'=>93, 'show_floor'=>true},
  {'total_l'=>ROOMS[v][0],'total_w'=>ROOMS[v][1]}].each do |room|
  [['wange', 'wange', 'wange'], ['wangeK', 'wange', 'wange'], ['wange', 'sattel', 'frei'], ['wange', 'wange', 'sattel'], ['holm', nil, nil], ['massiv', nil, nil]].each do |c, sl, sr|
    [['rechts', true, 'beide'], ['links', false, 'aussen']].each do |dir, ris, rail|
      form = c == 'wangeK' ? 'kurve' : 'gerade'
      p = Params.normalize(Params.defaults.merge('variant' => v, 'construction' => c.sub('K', ''), 'str_form' => form, 'direction' => dir, 'risers' => ris, 'rail' => rail,
                                                 'side_left' => sl || 'wange', 'side_right' => sr || 'wange').merge(room))
      model = Sketchup::Model.new
      defn = Sketchup::ComponentDefinition.new(model)
      begin
        Builder.build(defn, p)
      rescue PlanError => e
        puts "#{v}/#{c}/#{dir}: PlanError #{e.message}"; next
      end
      groups = leaf_groups(defn.entities)
      bad = []
      groups.each do |path, g|
        total += 1
        faces = g.entities.items.grep(Sketchup::Face)
        edges = g.entities.items.grep(Sketchup::Edge)
        next if faces.empty? # Gehlinie
        nonman = edges.count { |e| e.faces.size != 2 }
        vol = volume(g)
        bad << "#{path.join('/')}: nonmanifold=#{nonman} vol=#{vol.round(1)}" if nonman > 0 || vol <= 0
      end
      fails += bad.size
      puts "#{room.empty? ? 'frei' : 'raum'} #{v.ljust(14)} #{(c + (sl ? "/#{sl}/#{sr}" : '')).ljust(20)} #{dir.ljust(6)} groups=#{groups.size} #{bad.empty? ? 'OK' : 'FEHLER'}"
      bad.first(5).each { |b| puts "    #{b}" }
      if obj_dump && dir == 'rechts'
        File.open("/home/claude/tb/test/out/#{v}_#{c}#{sl}#{sr}.json", 'w') do |f|
          tris = []
          groups.each do |path, g|
            g.entities.items.grep(Sketchup::Face).each do |fc|
              p0 = fc.pts[0]
              (1...fc.pts.size - 1).each { |i| tris << [p0, fc.pts[i], fc.pts[i + 1]].map { |q| q.to_a.map { |x| (x * 2.54).round(2) } } + [path[0]] }
            end
          end
          f.write(JSON.generate(tris))
        end
      end
    end
  end
end
end
puts "Gruppen: #{total}, Fehler: #{fails}"
