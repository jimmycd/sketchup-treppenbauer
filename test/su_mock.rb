# Minimaler SketchUp-API-Mock zum Testen des Builders außerhalb von SketchUp.
class Numeric
  def cm; self / 2.54; end
end

module Geom
  class Vector3d
    attr_reader :x, :y, :z
    def initialize(x = 0, y = 0, z = 0); @x = x.to_f; @y = y.to_f; @z = z.to_f; end
    def dot(o); x * o.x + y * o.y + z * o.z; end
    alias % dot
    def length; Math.sqrt(dot(self)); end
    def angle_between(o)
      c = dot(o) / (length * o.length)
      Math.acos([[c, -1.0].max, 1.0].min)
    end
    def reverse; Vector3d.new(-x, -y, -z); end
  end

  class Point3d
    attr_reader :x, :y, :z
    def initialize(x = 0, y = 0, z = 0); @x = x.to_f; @y = y.to_f; @z = z.to_f; end
    def distance(o); Math.sqrt((x - o.x)**2 + (y - o.y)**2 + (z - o.z)**2); end
    def to_a; [x, y, z]; end
  end

  class Transformation; end
end

module Sketchup
  class Color
    def initialize(*a); @a = a; end
  end

  class Material
    attr_accessor :color, :alpha, :name
    def initialize(n); @name = n; end
  end

  class Collection < Array
    def [](k)
      k.is_a?(String) ? find { |e| e.name == k } : super
    end
  end

  class Layer
    attr_reader :name
    def initialize(n); @name = n; end
  end

  class Layers < Collection
    def add(n); l = Layer.new(n); self << l; l; end
  end

  class Materials < Collection
    def add(n); m = Material.new(n); self << m; m; end
  end

  class Edge
    attr_accessor :soft, :smooth
    attr_reader :faces, :a, :b
    def initialize(a, b); @a = a; @b = b; @faces = []; end
  end

  class Face
    attr_reader :pts, :edges
    def initialize(pts, edges); @pts = pts; @edges = edges; end
    def normal
      nx = ny = nz = 0.0
      @pts.each_with_index do |p, i|
        q = @pts[(i + 1) % @pts.size]
        nx += (p.y - q.y) * (p.z + q.z)
        ny += (p.z - q.z) * (p.x + q.x)
        nz += (p.x - q.x) * (p.y + q.y)
      end
      l = Math.sqrt(nx * nx + ny * ny + nz * nz)
      Geom::Vector3d.new(nx / l, ny / l, nz / l)
    end
    def reverse!; @pts.reverse!; self; end
    def area_vec
      n = normal
      n
    end
  end

  class Group
    attr_accessor :name, :layer, :material, :description
    attr_reader :entities
    def initialize; @entities = Entities.new; end
  end

  class Entities
    include Enumerable
    attr_reader :items
    def initialize; @items = []; @edges = {}; end
    def each(&b); @items.each(&b); end
    def clear!; @items.clear; @edges.clear; end
    def add_group; g = Group.new; @items << g; g; end
    def key(p); p.to_a.map { |v| (v * 1000).round }; end
    def edge(a, b)
      k = [key(a), key(b)].sort
      @edges[k] ||= begin e = Edge.new(a, b); @items << e; e end
    end
    def add_face(pts)
      raise ArgumentError, 'zu wenige Punkte' if pts.size < 3
      ks = pts.map { |p| key(p) }
      raise ArgumentError, 'doppelte Punkte' if ks.uniq.size != ks.size
      f = Face.new(pts.dup, [])
      n = f.normal
      raise ArgumentError, 'degeneriert' if n.x.nan?
      p0 = pts[0]
      pts.each do |p|
        d = (p.x - p0.x) * n.x + (p.y - p0.y) * n.y + (p.z - p0.z) * n.z
        raise ArgumentError, "nicht planar (#{d})" if d.abs > 1e-3
      end
      pts.each_with_index do |p, i|
        e = edge(p, pts[(i + 1) % pts.size])
        e.faces << f
        f.edges << e
      end
      @items << f
      f
    end
    def add_edges(pts); pts.each_cons(2) { |a, b| edge(a, b) }; end
    def add_instance(d, t); d; end
  end

  class ComponentDefinition
    attr_accessor :name, :description, :model
    attr_reader :entities
    def initialize(m); @model = m; @entities = Entities.new; end
  end

  class Model
    attr_reader :layers, :materials
    def initialize; @layers = Layers.new; @materials = Materials.new; end
  end
end
