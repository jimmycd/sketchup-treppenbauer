import json,sys,numpy as np
import matplotlib; matplotlib.use('Agg')
import matplotlib.pyplot as plt
from mpl_toolkits.mplot3d.art3d import Poly3DCollection
n=sys.argv[2]; elev=float(sys.argv[3]) if len(sys.argv)>3 else 25; az=float(sys.argv[4]) if len(sys.argv)>4 else -60
cols={'Stufen':(0.88,0.72,0.5),'Wangen':(0.55,0.33,0.2),'Holm':(0.3,0.3,0.33),'Geländer':(0.25,0.25,0.3),'Deckenkante':(0.75,0.85,0.75)}
tris=json.load(open(f'out/{n}.json'))
fig=plt.figure(figsize=(10,10)); ax=fig.add_subplot(111,projection='3d')
P=[np.array(t[:3]) for t in tris]; fc=[]
L=np.array([0.4,-0.6,0.7]); L/=np.linalg.norm(L)
for t in tris:
    a,b,c=map(np.array,t[:3]); nrm=np.cross(b-a,c-a); l=np.linalg.norm(nrm)
    s=0.35+0.65*abs(np.dot(nrm/l if l>0 else nrm,L))
    base=cols.get(t[3],(0.7,0.7,0.7)); fc.append(tuple(min(1,x*s) for x in base))
ax.add_collection3d(Poly3DCollection(P,facecolors=fc,edgecolors=(0,0,0,0.15),linewidths=0.2))
allp=np.concatenate(P); mn=allp.min(0); mx=allp.max(0); c=(mn+mx)/2; r=(mx-mn).max()/2
ax.set_xlim(c[0]-r,c[0]+r); ax.set_ylim(c[1]-r,c[1]+r); ax.set_zlim(c[2]-r,c[2]+r)
ax.view_init(elev=elev,azim=az); ax.set_axis_off(); plt.tight_layout(); plt.savefig(sys.argv[1],dpi=80)
