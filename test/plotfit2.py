import json, sys, math
import matplotlib; matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import Polygon
d = json.load(open(sys.argv[1]))
keys = sorted(d.keys(), key=lambda k: int(k.split('_')[0])*10 + (0 if k.endswith('rechts') else 1))
if len(sys.argv) > 3: keys = [k for k in keys if sys.argv[3] in k]
n = len(keys); cols = 6; rows = math.ceil(n/cols)
fig, axs = plt.subplots(rows, cols, figsize=(cols*4, rows*4.4))
for ax in axs.flat: ax.axis('off')
for ax, k in zip(axs.flat, keys):
    p = d[k]
    for t in p['treads']:
        ax.add_patch(Polygon(t['pts'], closed=True, fc='#cfe0ef' if t['kind']=='landing' else '#ead4ae', ec='#6b4a1e', lw=0.6))
        ax.text(t['label'][0], t['label'][1], 'P' if t['kind']=='landing' else str(t['nr']), fontsize=5, ha='center', va='center')
    w = p['walk']; ax.plot([q[0] for q in w], [q[1] for q in w], 'r--', lw=0.6)
    sp = p.get('space')
    if sp:
        poly = sp['poly']; ax.add_patch(Polygon(poly, closed=True, fill=False, ec='b', lw=1.0, ls='--'))
        if sp.get('loch'): ax.add_patch(Polygon(sp['loch'], closed=True, fc=(0,0.6,0,0.12), ec='g', lw=0.8))
    ax.set_aspect('equal'); ax.autoscale_view(); ax.set_title(k, fontsize=8)
plt.tight_layout(); plt.savefig(sys.argv[2], dpi=110)
