import json, sys, matplotlib; matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import Polygon
d = json.load(open('boards.json'))
rows = sum(len(v) for v in d.values())
fig, axs = plt.subplots(rows, 1, figsize=(14, 2.2*rows))
i = 0
for name, bs in d.items():
    for b in bs:
        ax = axs[i] if rows > 1 else axs; i += 1
        ax.add_patch(Polygon(b['poly'], closed=True, fc='#c8a070', ec='k', lw=0.8))
        for pk in b['pk']: ax.add_patch(Polygon(pk, closed=True, fc='#555', ec='none', alpha=0.6))
        ax.set_aspect('equal'); ax.autoscale_view(); ax.set_title(f"{name} {b['l']}", fontsize=8); ax.tick_params(labelsize=6)
plt.tight_layout(); plt.savefig(sys.argv[1], dpi=70)
