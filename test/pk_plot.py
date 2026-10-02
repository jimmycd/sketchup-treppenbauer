import json, matplotlib; matplotlib.use('Agg'); import matplotlib.pyplot as plt
d=json.load(open('pk.json'))
for v,parts in d.items():
    fig,axs=plt.subplots(len(parts),1,figsize=(16,4.5*len(parts)))
    if len(parts)==1: axs=[axs]
    for ax,pt in zip(axs,parts):
        P=pt['poly']+[pt['poly'][0]]; ax.plot(*zip(*P),'k-')
        for pk in pt['pockets']:
            Q=pk+[pk[0]]; ax.fill(*zip(*Q),color='#6a9d4f',alpha=0.4); ax.plot(*zip(*Q),'g-',lw=1)
        for pa in pt['paths']: ax.plot(*zip(*pa),'r-',lw=0.5)
        ax.set_aspect('equal'); ax.set_title(v+' '+pt['label'])
    plt.tight_layout(); plt.savefig('pk_%s.png'%v,dpi=70)
