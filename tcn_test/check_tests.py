# Prüft und zeichnet die Beispiel-TCNs (Draufsicht + Schnitt der Schräge).
import re, math, sys
from shapely.geometry import Polygon, LineString, Point, box
from shapely.ops import unary_union
import matplotlib; matplotlib.use('Agg')
import matplotlib.pyplot as plt

R = {1000: 6.0, 15001: 8.0, 'r0': 0.5}

def parse(fn):
    sides = {}; cur = None
    for ln in open(fn, encoding='cp1252'):
        m = re.match(r'SIDE#(\d+)\{', ln)
        if m: cur = int(m.group(1)); sides.setdefault(cur, []); continue
        if ln.startswith('}SIDE'): cur = None; continue
        if cur is None: continue
        m = re.search(r'W#89\{.*?#1=(\S+) #2=(\S+) #3=(\S+) .*#205=(\S+)', ln)
        if m:
            tool = m.group(4); tool = int(tool) if tool.isdigit() else tool
            sides[cur].append({'tool': tool, 'z': m.group(3), 'pts': [(float(m.group(1)), float(m.group(2)))]})
            continue
        m = re.search(r'W#2201\{.*#1=(\S+) #2=(\S+)', ln)
        if m:
            x, y = sides[cur][-1]['pts'][-1]
            sides[cur][-1]['pts'].append((x + float(m.group(1)), y + float(m.group(2))))
    return sides

def swept(paths):
    return unary_union([LineString(p['pts']).buffer(R[p['tool']]) if len(p['pts']) > 1 else Point(p['pts'][0]).buffer(R[p['tool']]) for p in paths])

def rot(q, u, s, pts):  # (u, s)-Koordinaten -> Tisch
    return [(q[0] + u[0]*a + s[0]*b, q[1] + u[1]*a + s[1]*b) for a, b in pts]

ok = True
def report(name, cond, msg):
    global ok
    print(f"  {'ok    ' if cond else 'FEHLER'} {msg}")
    ok &= cond

# Schräge prüfen: Mittelpunktsbahn (u,Z) relativ zur Wand unten (0,0), oben (off, DS)
def check_wedge(pts, off, ds=40.0, r=8.0):
    seg = LineString(pts); c0, c1 = pts[0], pts[-1]
    wall = LineString([(0, 0), (off, ds)])
    # Material: rechts der Wand (u > Wand(Z)), 0 <= Z <= ds
    mat = Polygon([(0, 0), (500, 0), (500, ds), (off, ds)]) if off > 0 else Polygon([(off, ds), (0, 0), (500, 0), (500, ds)])
    tool = seg.buffer(r, quad_segs=64)
    cut_into = tool.intersection(mat).area
    wedge = Polygon([(0, 0), (off, ds), (0, ds)]) if off > 0 else None
    rest = wedge.difference(tool).area if wedge else 0
    under = r - min(p[1] for p in pts)
    return cut_into, rest, under

def plot(name, sides, blank, mat_bottom, mat_top, notes):
    fig, ax = plt.subplots(figsize=(9, 6))
    bx = box(0, 0, *blank)
    ax.plot(*bx.exterior.xy, 'k-', lw=0.8)
    ax.fill(*Polygon(mat_bottom).exterior.xy, color='#d9b38c', alpha=0.6, label='Material Unterseite')
    ax.plot(*Polygon(mat_top).exterior.xy, color='#8b5a2b', lw=1.2, ls='--', label='Material Oberseite')
    sw = swept([p for p in sides.get(1, []) if p['tool'] == 1000])
    for g in getattr(sw, 'geoms', [sw]):
        if not g.is_empty: ax.fill(*g.exterior.xy, color='#4a90d9', alpha=0.25)
    for p in sides.get(1, []):
        xs, ys = zip(*p['pts'])
        ax.plot(xs, ys, color='#c0392b' if p['tool'] == 'r0' else '#1f4e79', lw=1.4 if p['tool'] == 'r0' else 0.5)
    for t in notes: ax.plot(*zip(*t[0]), color='#27ae60', lw=3, label=t[1])
    ax.set_aspect('equal'); ax.legend(loc='lower right', fontsize=7); ax.set_title(name)
    fig.savefig(name.replace('.tcn', '.png'), dpi=110, bbox_inches='tight'); plt.close(fig)

def common(name, blank, mat_bottom, mat_top, notes):
    sides = parse(name)
    print(name)
    sw = swept([p for p in sides.get(1, []) if p['tool'] == 1000])
    bot = Polygon(mat_bottom)
    report(name, sw.intersection(bot).area < 0.5, f"Ausräumen verletzt Teil: {sw.intersection(bot).area:.2f} mm²")
    notch = box(0, 0, *blank).difference(bot)
    rest = notch.difference(sw).area
    report(name, rest < 0.3 * 6 * 6 * 4, f"Rest im Ausklinkungsbereich (Fräserradius-Ecken): {rest:.1f} mm²")
    plot(name, sides, blank, mat_bottom, mat_top, notes)
    return sides

# A
sides = common('A_seite5.tcn', (400, 250),
               [(0,0),(400,0),(400,250),(150,250),(150,150),(0,150)],
               [(0,0),(400,0),(400,250),(190,250),(190,150),(0,150)],
               [([(150, 150), (150, 250)], 'Achse Aggregat (−Y)')])
p = sides[5][0]; pts = [(x - 150, y) for x, y in p['pts']]
ci, rest, under = check_wedge(pts, 40)
report('A', ci < 0.01 and rest < 1.0, f"Schräge: in Material {ci:.3f} mm², Rest Keil {rest:.2f} mm², unter Brett {under:.1f} mm, Tiefe {p['z']} (Soll -100)")

# B
a = math.radians(30); s = (math.sin(a), math.cos(a)); u = (s[1], -s[0]); q = (200, 150)
L, W = 400, 260
def region_poly(q, u, s, off):
    big = 2000
    notch = Polygon(rot(q, u, s, [(-big, 0), (off, 0), (off, big), (-big, big)]))
    return box(0, 0, L, W).difference(notch)
mb = region_poly(q, u, s, 0); mt = region_poly(q, u, s, 40)
sides = parse('B_gside_30grad.tcn')
print('B_gside_30grad.tcn')
sw = swept([p for p in sides[1] if p['tool'] == 1000])
report('B', sw.intersection(mb).area < 0.5, f"Ausräumen verletzt Teil: {sw.intersection(mb).area:.2f} mm²")
rest = box(0, 0, L, W).difference(mb).difference(sw).area
report('B', rest < 0.3 * 6 * 6 * 4, f"Rest im Ausklinkungsbereich: {rest:.1f} mm²")
p = sides[7][0]
pts = [(100 - x, y) for x, y in p['pts']]
ci, rest, under = check_wedge(pts, 40)
report('B', ci < 0.01 and rest < 1.0, f"Schräge: in Material {ci:.3f} mm², Rest Keil {rest:.2f} mm², unter Brett {under:.1f} mm, Tiefe {p['z']} (Soll -150)")
fig, ax = plt.subplots(figsize=(9, 6))
ax.fill(*mb.exterior.xy, color='#d9b38c', alpha=0.6, label='Material Unterseite')
ax.plot(*mt.exterior.xy, color='#8b5a2b', lw=1.2, ls='--', label='Material Oberseite')
ax.plot(*box(0,0,L,W).exterior.xy, 'k-', lw=0.8)
for g in getattr(sw, 'geoms', [sw]): ax.fill(*g.exterior.xy, color='#4a90d9', alpha=0.25)
for pp in sides[1]: ax.plot(*zip(*pp['pts']), color='#1f4e79', lw=0.5)
ax.plot(*zip(*rot(q, u, s, [(-5.7, 0), (-5.7, 150)])), color='#27ae60', lw=3, label='Achse Aggregat (C 30°)')
ax.plot(*zip(*rot(q, u, s, [(-120, 150), (120, 150)])), color='#8e44ad', lw=1.5, label='Hilfsfläche 7')
ax.set_aspect('equal'); ax.legend(loc='lower right', fontsize=7); ax.set_title('B_gside_30grad.tcn')
fig.savefig('B_gside_30grad.png', dpi=110, bbox_inches='tight'); plt.close(fig)

# C
sides = common('C_markierung.tcn', (400, 250),
               [(0,0),(400,0),(400,250),(150,250),(150,150),(0,150)],
               [(0,0),(400,0),(400,250),(190,250),(190,150),(0,150)], [])
report('C', any(p['tool'] == 'r0' for p in sides[1]), 'Markierungslinien vorhanden')

# D
mbot = [(0,0),(500,0),(500,250),(340,250),(340,175),(150,175),(150,100),(0,100)]
mtop = [(0,0),(500,0),(500,250),(300,250),(300,175),(190,175),(190,100),(0,100)]
sides = parse('D1_wenden_seite1.tcn')
print('D1_wenden_seite1.tcn')
sw = swept([p for p in sides[1] if p['tool'] == 1000])
# von oben darf nur bis zur jeweils materialseitigen Lage geräumt werden:
inner = Polygon([(0,0),(500,0),(500,250),(340,250),(340,175),(150,175),(150,100),(0,100)]).union(
        Polygon([(300,175),(340,175),(340,250),(300,250)]))  # Keil 2 (unten) bleibt bis Seite 2
viol = sw.intersection(Polygon([(0,0),(500,0),(500,250),(300,250),(300,175),(150,175),(150,100),(0,100)])).area
report('D1', viol < 0.5, f"Ausräumen verletzt Teil (inkl. Keil 2): {viol:.2f} mm²")
p = sides[5][0]; pts = [(x - 150, y) for x, y in p['pts']]
ci, rest, under = check_wedge(pts, 40)
report('D1', ci < 0.01 and rest < 1.0, f"Schräge 1: in Material {ci:.3f} mm², Rest {rest:.2f} mm², unter Brett {under:.1f} mm, Tiefe {p['z']} (Soll -150)")
plot('D1_wenden_seite1.tcn', sides, (500, 250), mbot, mtop, [([(150,100),(150,250)], 'Achse Aggregat Schräge 1')])
sides = parse('D2_wenden_seite2.tcn')
print('D2_wenden_seite2.tcn')
p = sides[5][0]; pts = [(200 - x, y) for x, y in p['pts']]   # gespiegelt: u = 200 − x'
ci, rest, under = check_wedge(pts, 40)
report('D2', ci < 0.01 and rest < 1.0, f"Schräge 2: in Material {ci:.3f} mm², Rest {rest:.2f} mm², unter Brett {under:.1f} mm, Tiefe {p['z']} (Soll -75)")

# D2: Außenkontur zuletzt (gespiegelt), Teil darf nicht angeschnitten werden
import numpy as np
xs = np.linspace(10, 490, 25)
part = [(x, 20 + 25 * ((x - 250) / 240) ** 2) for x in xs] + [(490, 245), (300, 245), (300, 175), (150, 175), (150, 100), (10, 100)]
pm = Polygon([(500 - x, y) for x, y in part])
cont = [p for p in sides[1] if p['tool'] == 1000]
ring = Polygon(cont[0]['pts'])
report('D2', abs(ring.symmetric_difference(pm).area) < 1.0 and cont[0]['z'] == '-41',
       f"Außenkontur = gespiegeltes Teil (Abweichung {ring.symmetric_difference(pm).area:.2f} mm²), Tiefe {cont[0]['z']}, Korrektur links")
fig, ax = plt.subplots(figsize=(9, 6))
ax.plot(*box(0, 0, 500, 250).exterior.xy, 'k-', lw=0.8)
ax.fill(*pm.exterior.xy, color='#d9b38c', alpha=0.6, label='Teil (nach dem Wenden)')
ax.plot(*pm.buffer(6).exterior.xy, color='#1f4e79', lw=1, label='Fräsermitte Außenkontur (zuletzt)')
for p in sides[5]:
    pass
ax.plot([200, 200], [175, 250], color='#27ae60', lw=3, label='Achse Aggregat Schräge 2')
ax.set_aspect('equal'); ax.legend(loc='lower right', fontsize=7); ax.set_title('D2_wenden_seite2.tcn')
fig.savefig('D2_wenden_seite2.png', dpi=110, bbox_inches='tight'); plt.close(fig)
print('GESAMT', 'ok' if ok else 'FEHLER')
