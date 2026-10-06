# encoding: UTF-8
# Treppenbau – Verschachtelung (Nesting) von Freiformteilen auf Rohplatten.
#
# Raster-Verfahren: Jedes Teil wird (um den halben Teileabstand vergrößert)
# auf ein Zellraster gelegt. Die Plattenbelegung wird zeilenweise als Bitmaske
# (Ruby-Integer) gehalten; zulässige X-Positionen einer Zeile ergeben sich
# per Bit-"Verschmieren" in O(log Breite). Platziert wird links-unten
# (Platte wird von links nach rechts gefüllt, Reststück bleibt am Stück).
# Mehrere Sortierungen/Strategien werden probiert, das beste Ergebnis gewinnt.

module JTools
  module Treppenbau
    class Nester
      Placement = Struct.new(:part, :rot, :x, :y, :poly, :pockets, :paths, :drills)
      Sheet = Struct.new(:rows, :placements, :maxx, :free, :fails)

      attr_reader :plates, :unplaced, :grid

      # opts: :length, :width, :margin, :gap, :grid, :grain (true = nur 0°/180°)
      def initialize(opts)
        @len = opts[:length].to_f
        @wid = opts[:width].to_f
        @margin = opts[:margin].to_f
        @gap = opts[:gap].to_f
        @grid = [opts[:grid].to_f, 1.0].max
        @grain = opts[:grain]
        @nx = ((@len - 2 * @margin + @gap) / @grid).floor
        @ny = ((@wid - 2 * @margin + @gap) / @grid).floor
      end

      def nest(parts)
        best = nil
        prepared = parts.map { |p| [p, variants(p)] }
        orders = [
          prepared.sort_by { |p, _| -p.area },
          prepared.sort_by { |p, _| -p.size.max },
          prepared.sort_by { |p, _| [-p.size.min, -p.size.max] }
        ]
        orders.each do |ord|
          [:left, :bottom].each do |strategy|
            res = run(ord, strategy)
            sc = score(res)
            best = [sc, res] if best.nil? || (sc <=> best[0]) < 0
          end
        end
        @plates, @unplaced = best[1]
        self
      end

      def usable?
        @nx > 0 && @ny > 0
      end

      private

      def score(res)
        plates, unplaced = res
        last = plates.last
        [unplaced.size, plates.size, last ? last.maxx : 0, plates.map(&:maxx).sum]
      end

      def run(ordered, strategy)
        sheets = []
        unplaced = []
        ordered.each do |part, vars|
          if vars.empty?
            unplaced << part
            next
          end
          done = false
          sheets.each do |sh|
            break if (done = place(sh, part, vars, strategy))
          end
          next if done
          sh = Sheet.new(Array.new(@ny, 0), [], 0.0, @nx * @ny, {})
          if place(sh, part, vars, strategy)
            sheets << sh
          else
            unplaced << part
          end
        end
        [sheets, unplaced]
      end

      # Drehvarianten mit Rastermasken
      def variants(part)
        angles = @grain ? [0, 180] : [0, 90, 180, 270]
        out = []
        seen = {}
        angles.each do |deg|
          rad = deg * Math::PI / 180.0
          poly = part.poly.map { |q| Geo.rot(q, rad) }
          pk = part.pockets.map { |pc| pc.map { |q| Geo.rot(q, rad) } }
          pth = (part.pocket_paths || []).map { |pc| pc.map { |q| Geo.rot(q, rad) } }
          drl = (part.drills || []).map do |h|
            q = Geo.rot([h[:x], h[:y]], rad)
            h.merge(x: q[0], y: q[1], ang: h[:ang] && ((h[:ang] + deg + 180.0) % 360.0 - 180.0).round(2))
          end
          minx = poly.map(&:first).min; miny = poly.map(&:last).min
          poly = poly.map { |q| [q[0] - minx, q[1] - miny] }
          pk = pk.map { |pc| pc.map { |q| [q[0] - minx, q[1] - miny] } }
          pth = pth.map { |pc| pc.map { |q| [q[0] - minx, q[1] - miny] } }
          drl = drl.map { |h| h.merge(x: h[:x] - minx, y: h[:y] - miny) }
          mask = rasterize(poly)
          next if mask.nil?
          key = mask[:rows].hash
          next if seen[key]
          seen[key] = true
          out << { deg: deg, poly: poly, pockets: pk, paths: pth, drills: drl, mask: mask }
        end
        out
      end

      # Liefert {rows: [[a, b], ...] (Zellspannen je Zeile), w:, h:}
      def rasterize(poly)
        w = poly.map(&:first).max
        h = poly.map(&:last).max
        mw = ((w + @gap) / @grid).ceil
        mh = ((h + @gap) / @grid).ceil
        return nil if mw > @nx || mh > @ny
        g = @grid; hg = @gap / 2.0
        rows = (0...mh).map do |j|
          y0 = j * g - @gap
          y1 = (j + 1) * g
          xr = band_extent(poly, y0, y1)
          next nil unless xr
          a = (xr[0] / g).floor
          b = ((xr[1] + @gap) / g).ceil - 1
          a = 0 if a < 0
          b = mw - 1 if b > mw - 1
          [a, b]
        end
        _ = hg
        cells = rows.compact.map { |a, b| b - a + 1 }.sum
        { rows: rows, w: mw, h: mh, cells: cells, key: rows.hash }
      end

      # x-Ausdehnung des Polygons innerhalb des Streifens y0..y1
      def band_extent(poly, y0, y1)
        pts = clip(clip(poly, y0, 1), y1, -1)
        return nil if pts.size < 1
        xs = pts.map(&:first)
        [xs.min, xs.max]
      end

      # Sutherland-Hodgman an y = c (dir 1: behalte y >= c, -1: y <= c)
      def clip(poly, c, dir)
        return [] if poly.empty?
        out = []
        n = poly.size
        n.times do |i|
          p = poly[i]; q = poly[(i + 1) % n]
          pin = (p[1] - c) * dir >= 0
          qin = (q[1] - c) * dir >= 0
          out << p if pin
          if pin != qin
            t = (c - p[1]) / (q[1] - p[1])
            out << [p[0] + t * (q[0] - p[0]), c]
          end
        end
        out
      end

      def place(sheet, part, vars, strategy)
        best = nil
        vars.each do |v|
          m = v[:mask]
          next if m[:cells] > sheet.free || sheet.fails[m[:key]]
          pos = find(sheet, m, strategy)
          sheet.fails[m[:key]] = true unless pos
          next unless pos
          x, y = pos
          sc = strategy == :left ? [x + v[:mask][:w], y] : [y + v[:mask][:h], x]
          best = [sc, v, x, y] if best.nil? || (sc <=> best[0]) < 0
        end
        return false unless best
        _, v, cx, cy = best
        occupy(sheet, v[:mask], cx, cy)
        ox = @margin + cx * @grid
        oy = @margin + cy * @grid
        poly = v[:poly].map { |q| [q[0] + ox, q[1] + oy] }
        pk = v[:pockets].map { |pc| pc.map { |q| [q[0] + ox, q[1] + oy] } }
        pth = v[:paths].map { |pc| pc.map { |q| [q[0] + ox, q[1] + oy] } }
        drl = v[:drills].map { |h| h.merge(x: h[:x] + ox, y: h[:y] + oy) }
        sheet.placements << Placement.new(part, v[:deg], ox, oy, poly, pk, pth, drl)
        sheet.maxx = [sheet.maxx, poly.map(&:first).max + @margin].max
        true
      end

      def find(sheet, mask, strategy)
        rows = mask[:rows]
        mh = mask[:h]; mw = mask[:w]
        maxx = @nx - mw
        return nil if maxx < 0 || mh > @ny
        full = (1 << (maxx + 1)) - 1
        best = nil
        lim = full
        (0..(@ny - mh)).each do |y|
          forb = 0
          rows.each_with_index do |span, j|
            next unless span
            row = sheet.rows[y + j]
            next if row.zero?
            a, b = span
            forb |= smear(row >> a, b - a + 1)
            break if (forb & lim) == lim
          end
          free = lim & ~forb
          next if free.zero?
          x = lowest_bit(free)
          sc = strategy == :left ? [x, y] : [y, x]
          best = [sc, x, y] if best.nil? || (sc <=> best[0]) < 0
          break if strategy == :bottom # erste freie Zeile ist die unterste
          break if x.zero?
          lim = (1 << x) - 1 # weiter oben nur noch Positionen links davon interessant
        end
        best && [best[1], best[2]]
      end

      def smear(m, w)
        r = m
        cur = 1
        while cur < w
          step = [cur, w - cur].min
          r |= r >> step
          cur += step
        end
        r
      end

      def lowest_bit(v)
        (v & -v).bit_length - 1
      end

      def occupy(sheet, mask, cx, cy)
        mask[:rows].each_with_index do |span, j|
          next unless span
          a, b = span
          bits = ((1 << (b - a + 1)) - 1) << (cx + a)
          sheet.free -= (bits & ~sheet.rows[cy + j]).to_s(2).count('1')
          sheet.rows[cy + j] |= bits
        end
      end
    end
  end
end
