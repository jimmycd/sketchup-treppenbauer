import json, math
import numpy as np
d=json.load(open('pk.json')); r=5.0
def inpoly(x,y,P):
    c=False; n=len(P)
    for i in range(n):
        x1,y1=P[i]; x2,y2=P[(i+1)%n]
        if (y1>y)!=(y2>y) and x < x1+(y-y1)*(x2-x1)/(y2-y1): c=not c
    return c
def segd(p,a,b):
    ax,ay=a;bx,by=b;px,py=p; dx,dy=bx-ax,by-ay; L=dx*dx+dy*dy
    t=0 if L==0 else max(0,min(1,((px-ax)*dx+(py-ay)*dy)/L))
    return math.hypot(px-ax-t*dx,py-ay-t*dy)
for v,ps in d.items():
  for pt in ps:
    P=pt['pockets'][0]
    segs=[(pa[i],pa[i+1]) for pa in pt['paths'] for i in range(len(pa)-1)]
    S=np.array([[a[0],a[1],b[0],b[1]] for a,b in segs])
    xs=[q[0] for q in P]; ys=[q[1] for q in P]
    bad=0; tot=0; mx=0
    for x in np.arange(min(xs),max(xs),2.0):
      for y in np.arange(min(ys),max(ys),2.0):
        if not inpoly(x,y,P): continue
        tot+=1
        ax,ay,bx,by=S.T; dx=bx-ax; dy=by-ay; L=dx*dx+dy*dy; L[L==0]=1e-12
        t=np.clip(((x-ax)*dx+(y-ay)*dy)/L,0,1); dd=np.hypot(x-ax-t*dx,y-ay-t*dy).min()
        if dd>r+0.01:
          cd=min(math.hypot(x-q[0],y-q[1]) for q in P)
          if cd>r*1.5: bad+=1; mx=max(mx,dd)
    print(v,pt['label'],'pts',tot,'uncovered(not corner)',bad,'max',round(mx,2))
pt=d['l_wendel'][3]; P=pt['pockets'][0]
segs=[(pa[i],pa[i+1]) for pa in pt['paths'] for i in range(len(pa)-1)]
S=np.array([[a[0],a[1],b[0],b[1]] for a,b in segs]); ax,ay,bx,by=S.T; dx=bx-ax; dy=by-ay; L=dx*dx+dy*dy; L[L==0]=1e-12
xs=[q[0] for q in P]; ys=[q[1] for q in P]
for x in np.arange(min(xs),max(xs),1.0):
  for y in np.arange(min(ys),max(ys),1.0):
    if not inpoly(x,y,P): continue
    t=np.clip(((x-ax)*dx+(y-ay)*dy)/L,0,1); dd=np.hypot(x-ax-t*dx,y-ay-t*dy).min()
    if dd>5.3: print(round(x,1),round(y,1),round(dd,2), 'nearest vtx', min((round(math.hypot(x-q[0],y-q[1]),1),q) for q in P))
