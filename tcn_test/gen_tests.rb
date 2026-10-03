# encoding: UTF-8
# Erzeugt Beispiel-TCNs zum Test des Seitenaggregats (Doppelspindel waagerecht,
# 15001 = Ø16 / 167 mm) in TpaCAD. Eigenständig – KEIN Teil des Plugins.
# Aufruf: ruby gen_tests.rb   (schreibt *.tcn in diesen Ordner)

T_AGG   = 15001   # Aggregat Werkzeug 1 (Ø16, nutzbar 167 mm)
R_AGG   = 8.0
T_MILL  = 1000    # Fräser von oben (wie Plugin-Vorgabe, Ø12)
R_MILL  = 6.0
T_DECO  = 1400    # Gravur (wie Plugin-Vorgabe)
DS      = 40.0    # Brettdicke

def n(v)
  s = format('%.3f', v.to_f).sub(/\.?0+$/, '')
  s == '-0' ? '0' : s
end

def header(l, w, sides, geo = nil)
  o = []
  o << 'TPA\\ALBATROS\\EDICAD\\02.00:1224:r0w0h0s1'
  o << "::SIDE=#{sides.map { |s| "#{s};" }.join}"
  o << "::UNm DL=#{n(l)} DH=#{n(w)} DS=#{n(DS)}"
  o << "'tcn version=2.6.14" << "'code=ansi"
  o << 'EXE{' << '#0=0' << '#1=0' << '#2=0' << '#3=0' << '#4=0' << '}EXE'
  o << 'OFFS{' << '#0=0|0' << '#1=0|0' << '#2=0|0' << '}OFFS'
  o << 'VARV{'
  ['1|1', '2|2', '3|3', '4|4', '0|0', '0|0', '0|0', '0|0'].each_with_index { |v, i| o << "##{i}=#{v}" }
  o << '}VARV'
  o << 'VAR{' << "#0=#{T_DECO}||r|f|werkzeug" << '#1=-1||r|f|zkontur' << '}VAR'
  o << 'SPEC{' << '}SPEC' << 'INFO{' << '}INFO'
  o << 'OPTI{'
  o << ':: OPTDEF=1 OPTIMIZE=%;0 OPTMIN=0 OPT3=0 OPT0=0 OPTTOOL=0 OPT2=0 OPTX=0 OPTY=0 OPTR=0 ' \
       'OPT4=0 OPT6=0 OPT7=0 LSTCOD=0%1%2%3 LTOOLFR=0 LTOOLPN=0 OPTF1=0 OOO=0.5'
  o << '}OPTI' << 'LINK{' << '}LINK'
  o.concat(geo) if geo
  o << 'SIDE#0{' << '}SIDE'
  o
end

def setup(ws, start, z, tool, comp = 0)
  "W#89{ ::WTs WS=#{ws}  #8015=0 #1=#{n(start[0])} #2=#{n(start[1])} #3=#{z} " \
    "#201=1 #203=1 #205=#{tool} #1001=100 #8101=0 #8096=0 #40=#{comp} #46=1 " \
    '#8135=0 #8136=0 #8180=0 #8181=0 #8185=0 #8186=0 #9511=0 #9512=0 #9513=0 }W'
end

def lines(seq)
  acc = [0.0, 0.0]; done = [0.0, 0.0]
  seq.each_cons(2).map do |a, b|
    acc[0] += b[0] - a[0]; acc[1] += b[1] - a[1]
    rx = acc[0].round(2) - done[0]; ry = acc[1].round(2) - done[1]
    done[0] += rx; done[1] += ry
    "W#2201{ ::WTl  #8015=1 #1=#{n(rx)} #2=#{n(ry)} }W"
  end
end

class Prog
  attr_reader :ws
  def initialize; @ws = 0; @out = []; end
  def path(pts, z, tool, comp = 0)
    @ws += 1
    @out << setup(@ws, pts.first, z, tool, comp)
    @out.concat(lines(pts))
  end
  def to_a; @out; end
end

def add(a, b) = [a[0] + b[0], a[1] + b[1]]
def mul(a, s) = [a[0] * s, a[1] * s]
def dot(a, b) = a[0] * b[0] + a[1] * b[1]

# Ausräumen des Ausklinkungsbereichs {(p-q)·u < 0, (p-q)·s > 0} im Rohling
# (l × w) von oben, Zickzack parallel zum Auflager, durchgefräst.
# Der Bereich ist zur Rohlingskante hin offen -> kein loses Abfallstück.
def clear_notch(prog, q, u, s, l, w, s_max, depths)
  m = R_MILL + 2
  lo = [-m, -m]; hi = [l + m, w + m]
  rows = []
  sv = R_MILL
  while sv < s_max + R_MILL
    a = add(q, add(mul(u, -R_MILL), mul(s, sv)))       # an der Wand
    d = mul(u, -1.0)
    # Strahl a + t·d (t >= 0) auf das um r + 2 erweiterte Rechteck kürzen
    t0 = 0.0; t1 = 1e9
    2.times do |ax|
      if d[ax].abs < 1e-12
        t1 = -1 if a[ax] < lo[ax] || a[ax] > hi[ax]
      else
        ta = (lo[ax] - a[ax]) / d[ax]; tb = (hi[ax] - a[ax]) / d[ax]
        ta, tb = tb, ta if ta > tb
        t0 = [t0, ta].max; t1 = [t1, tb].min
      end
    end
    rows << [add(a, mul(d, t0)), add(a, mul(d, t1))] if t1 > t0 + 1.0
    sv += 2 * R_MILL - 2.0
  end
  seq = []
  rows.each_with_index { |(a, b), i| seq.concat(i.even? ? [b, a] : [a, b]) }
  # Schlichtbahn: Auflager (von außen bis zur Ecke) und Stoß (bis über den Rohling)
  top = rows.map { |a, _| a }.max_by { |p| dot(p, s) }
  fin = [rows[0][1], rows[0][0], add(q, add(mul(u, -R_MILL), mul(s, dot(add(top, mul(q, -1.0)), s) + 2)))]
  depths.each { |z| prog.path(seq, n(z), T_MILL); prog.path(fin, n(z), T_MILL) }
end

# Schräge Stoßfläche: unten (Z=0) durch q, oben (Z=DS) um off entlang u
# versetzt (off > 0: Keil liegt oben, mit Aggregat von oben erreichbar).
# Rückgabe: Mittelpunktsbahn des Aggregatfräsers in (u, Z) relativ zu q –
# mehrere parallele Bahnen (außen beginnend, letzte Bahn = Wand), Zickzack.
# Start jeder Bahn so, dass der Fräser höchstens 1 mm unter die Unterseite reicht.
def wedge_path(off)
  len = Math.hypot(off, DS)
  dir = [off / len, DS / len]
  nrm = [-dir[1], dir[0]]                  # zur Luftseite (−u, +Z)
  far = off.abs * DS / len                 # größter Abstand Keil – Wand
  step = 2 * R_AGG - 4.0
  dists = (0..20).map { |i| R_AGG + step * i }.take_while { |d| d < far + R_AGG }
  seq = []
  dists.reverse.each_with_index do |dd, i|
    c = mul(nrm, dd)
    a = add(c, mul(dir, (R_AGG - 1.0 - c[1]) / dir[1]))
    b = add(c, mul(dir, (DS + 10.0 - c[1]) / dir[1]))   # 10 mm über die Oberfläche
    seq.concat(i.even? ? [b, a] : [a, b])
  end
  seq
end

def write(name, lines_)
  File.binwrite(name, (lines_.join("\r\n") + "\r\n").encode('Windows-1252'))
  puts "#{name}: #{lines_.size} Zeilen"
end

side_empty = ->(nr) { ["SIDE##{nr}{", '}SIDE'] }

# ---------------------------------------------------------------- A
# Rohling 400 × 250 × 40. Ausklinkung oben links: Auflager y = 150, Stoß bei
# x = 150 (unten) bzw. 190 (oben) -> 45° schräg durch die Dicke.
# Aggregat auf Fläche 5 (hinten, y = 250), Spindel zeigt in −Y.
l = 400.0; w = 250.0
q = [150.0, 150.0]; u = [1.0, 0.0]; s = [0.0, 1.0]
p1 = Prog.new
clear_notch(p1, q, u, s, l, w, w - q[1], [-20, -41])
p5 = Prog.new
wp = wedge_path(40.0)
# Fläche 5 – Annahme laut Doku: Ursprung (0; DH; 0), X = +X, Y = +Z (Dicke)
f5 = ->(uz) { [q[0] + uz[0], uz[1]] }
p5.path(wp.map { |v| f5.(v) }, n(-(w - q[1])), T_AGG)
out = header(l, w, [1, 5])
out << 'SIDE#1{' << "$=Ausklinkung von oben" ; out.concat(p1.to_a); out << '}SIDE'
out.concat(side_empty.(3)) << 'SIDE#4{' << '}SIDE'
out << 'SIDE#5{' << '$=Schraege Aggregat 15001'; out.concat(p5.to_a); out << '}SIDE'
out.concat(side_empty.(6))
write('A_seite5.tcn', out)

# ---------------------------------------------------------------- B
# wie A, aber Treppen-Senkrechte um 30° gedreht (C-Achse) -> Hilfsfläche 7.
l = 400.0; w = 260.0
a30 = 30 * Math::PI / 180
s = [Math.sin(a30), Math.cos(a30)]       # Fräserachse zeigt in −s
u = [s[1], -s[0]]
q = [200.0, 150.0]
smax = (w - q[1]) / s[1] + 5             # Wandhöhe bis Rohlingskante
p1 = Prog.new
clear_notch(p1, q, u, s, l, w, smax, [-20, -41])
sf = 150.0                               # Lage der Hilfsfläche über dem Auflager
xf = [-u[0], -u[1]]                      # Flächen-X (rechtshändig: X × Z = +s)
o = add(q, add(mul(s, sf), mul(u, 100.0)))
geo = ['GEO{', '::NF=1', 'GSIDE#7{',
       "#1=#{n(o[0])}|#{n(o[1])}|0",
       "#2=#{n(o[0] + xf[0] * 300)}|#{n(o[1] + xf[1] * 300)}|0",
       "#3=#{n(o[0])}|#{n(o[1])}|#{n(DS)}",
       '#Z=300', '}GSIDE', '}GEO']
wp = wedge_path(40.0)
f7 = ->(uz) { [100.0 - uz[0], uz[1]] }   # x = (P−O)·X, y = Z
p7 = Prog.new
p7.path(wp.map { |v| f7.(v) }, n(-sf), T_AGG)
out = header(l, w, [1, 7], geo)
out << 'SIDE#1{' << '$=Ausklinkung von oben'; out.concat(p1.to_a); out << '}SIDE'
(3..6).each { |k| out.concat(side_empty.(k)) }
out << 'SIDE#7{' << '$=Schraege Aggregat 15001 (C 30 Grad)'; out.concat(p7.to_a); out << '}SIDE'
write('B_gside_30grad.tcn', out)

# ---------------------------------------------------------------- C
# wie A, aber statt Aggregat nur Markierung (Gravur r0/r1, 1 mm) für Handarbeit:
# Linie = Oberkante der Schräge (x = 190), Querstrich 20 mm über dem Auflager
# (= Grenze, bis zu der das Aggregat bei 183 mm Steigung nicht kommt).
l = 400.0; w = 250.0
q = [150.0, 150.0]; u = [1.0, 0.0]; s = [0.0, 1.0]
p1 = Prog.new
p1.path([[190.0, 150.0], [190.0, 250.0]], 'r1', 'r0')
p1.path([[180.0, 170.0], [200.0, 170.0]], 'r1', 'r0')
clear_notch(p1, q, u, s, l, w, w - q[1], [-20, -41])
out = header(l, w, [1])
out << 'SIDE#1{' << '$=Markierung + Ausklinkung'; out.concat(p1.to_a); out << '}SIDE'
(3..6).each { |k| out.concat(side_empty.(k)) }
write('C_markierung.tcn', out)

# ---------------------------------------------------------------- D (Wenden)
# Rohling 500 × 250 × 40, zwei Ausklinkungen mit entgegengesetzter Neigung:
#   1: Auflager y = 100, Stoß x = 150 unten / 190 oben  (Keil oben  -> Seite 1)
#   2: Auflager y = 175, Stoß x = 340 unten / 300 oben  (Keil unten -> Seite 2)
# Seite 1: beide Ausklinkungen von oben (Stoß 2 an der oberen Lage x = 300),
#          Schräge 1 mit Aggregat, Markierung „Schräge 2 unten bis x = 340“.
# Seite 2: Brett um die Y-Achse wenden (links <-> rechts, gleiche Nullecke,
#          Anschlag an den Rohlingskanten), Schräge 2 mit Aggregat.
l = 500.0; w = 250.0
p1 = Prog.new
p1.path([[340.0, 175.0], [340.0, 250.0]], 'r1', 'r0')
clear_notch(p1, [300.0, 175.0], [1.0, 0.0], [0.0, 1.0], l, w, 75, [-20, -41])
clear_notch(p1, [150.0, 100.0], [1.0, 0.0], [0.0, 1.0], 300.0 + R_MILL, w, 150, [-20, -41])
p5 = Prog.new
wp = wedge_path(40.0)
p5.path(wp.map { |v| [150.0 + v[0], v[1]] }, n(-150), T_AGG)
out = header(l, w, [1, 5])
out << 'SIDE#1{' << '$=Seite 1 von oben'; out.concat(p1.to_a); out << '}SIDE'
out.concat(side_empty.(3)) << 'SIDE#4{' << '}SIDE'
out << 'SIDE#5{' << '$=Seite 1 Schraege 1'; out.concat(p5.to_a); out << '}SIDE'
out.concat(side_empty.(6))
write('D1_wenden_seite1.tcn', out)

# Seite 2: x' = 500 − x. Stoß 2 jetzt oben bei x' = 160, unten bei x' = 200,
# Luft auf der +x'-Seite -> Spiegelbild von wedge_path.
p5 = Prog.new
wp = wedge_path(40.0)
mir = ->(uz) { [200.0 - uz[0], uz[1]] }
p5.path(wp.map { |v| mir.(v) }, n(-75), T_AGG)
out = header(l, w, [5])
out << 'SIDE#1{' << '}SIDE'
out.concat(side_empty.(3)) << 'SIDE#4{' << '}SIDE'
out << 'SIDE#5{' << '$=Seite 2 Schraege 2'; out.concat(p5.to_a); out << '}SIDE'
out.concat(side_empty.(6))
write('D2_wenden_seite2.tcn', out)
