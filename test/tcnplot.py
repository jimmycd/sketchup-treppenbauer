import re,sys, matplotlib; matplotlib.use('Agg'); import matplotlib.pyplot as plt
f=sys.argv[1]; t=open(f,encoding='cp1252').read()
fig,ax=plt.subplots(figsize=(18,9)); cur=None
for l in t.splitlines():
    m=re.search(r'W#89\{.*#1=(\S+) #2=(\S+) #3=(\S+).*#205=(\S+)',l)
    if m:
        if cur: ax.plot(*zip(*cur[0]),cur[1],lw=cur[2])
        z=float(m.group(3)) if m.group(3)[0] in '-0123456789' else 0.0; col='k-' if z< -30 else ('r-' if z>-5 else 'g-')
        cur=([(float(m.group(1)),float(m.group(2)))],col,1 if col=='k-' else 0.5); continue
    m=re.search(r'W#2201\{.*#1=(\S+) #2=(\S+)',l)
    if m and cur: x,y=cur[0][-1]; cur[0].append((x+float(m.group(1)),y+float(m.group(2))))
if cur: ax.plot(*zip(*cur[0]),cur[1],lw=cur[2])
ax.set_aspect('equal'); plt.tight_layout(); plt.savefig(sys.argv[2],dpi=80)
