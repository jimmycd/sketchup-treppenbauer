import json,sys
import matplotlib; matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import Polygon
d=json.load(open(sys.argv[1])); side=sys.argv[2]
keys=[k for k in d if k.endswith(side)]
fig,axs=plt.subplots(2,5,figsize=(25,10))
for ax,k in zip(axs.flat,keys):
    v=d[k]; ax.set_title(k); ax.set_aspect('equal')
    if 'error' in v: ax.text(0,0,v['error'][:60]); continue
    for t in v['treads']:
        ax.add_patch(Polygon(t['pts'],closed=True,fc='#cde' if t['kind']=='landing' else '#eed9b5',ec='k',lw=0.6))
        ax.text(*t['label'],str(t['nr']),fontsize=7,ha='center',va='center')
    w=v['walk']; ax.plot([p[0] for p in w],[p[1] for p in w],'r--',lw=0.7)
    ax.autoscale_view()
plt.tight_layout(); plt.savefig(sys.argv[3],dpi=60)
