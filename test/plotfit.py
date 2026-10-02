import json
import matplotlib; matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import Polygon, Rectangle
d=json.load(open('fit.json')); ks=list(d)
fig,axs=plt.subplots(2,5,figsize=(25,10))
for ax,k in zip(axs.flat,ks):
    v=d[k]
    for t in v['treads']: ax.add_patch(Polygon(t['pts'],fc='#eed9b5',ec='k',lw=.5))
    s=v['space']; ax.add_patch(Rectangle((s['x'],s['y']),s['w'],s['l'],fill=False,ec='b',ls='--'))
    ax.set_title(k); ax.set_aspect('equal'); ax.autoscale_view()
plt.tight_layout(); plt.savefig('fit.png',dpi=50)
