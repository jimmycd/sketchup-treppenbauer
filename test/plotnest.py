import json,sys
import matplotlib; matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import Polygon, Rectangle
d=json.load(open('cnc.json'))[sys.argv[1]]
S=d['sheets']; L,W=d['plate']
fig,axs=plt.subplots(len(S),1,figsize=(12,5*len(S)))
if len(S)==1: axs=[axs]
col={'tread':'#ead4ae','landing':'#cfe0ef','riser':'#e0c890','stringer':'#b98a5a','post':'#999','newel':'#888','rail':'#777'}
for ax,s in zip(axs,S):
    ax.add_patch(Rectangle((0,0),L,W,fc='#f4f4f4',ec='k'))
    for p in s['parts']:
        ax.add_patch(Polygon(p['poly'],closed=True,fc=col.get(p['kind'],'#ccc'),ec='k',lw=0.6))
        for pk in p['pockets']: ax.add_patch(Polygon(pk,closed=True,fc='#5a3',ec='none',alpha=0.6))
        xs=[q[0] for q in p['poly']]; ys=[q[1] for q in p['poly']]
        ax.text(sum(xs)/len(xs),sum(ys)/len(ys),p['label'],fontsize=7,ha='center')
    ax.set_xlim(-20,L+20); ax.set_ylim(-20,W+20); ax.set_aspect('equal')
    ax.set_title(f"{s['thickness']} mm  Platte {s['index']}/{s['count']}  util {s['util']}%  used {s['used']}")
plt.tight_layout(); plt.savefig(sys.argv[2],dpi=55)
