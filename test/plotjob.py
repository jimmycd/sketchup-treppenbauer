import json, sys, os
import matplotlib; matplotlib.use('Agg')
import matplotlib.pyplot as plt
jobs = json.load(open(os.path.expanduser('~/job.json')))
out = sys.argv[1]
rows = sum(len(j['progs']) for j in jobs)
fig, axs = plt.subplots(rows, 1, figsize=(12, 3.2 * rows))
k = 0
for j in jobs:
    L, W = j['blank']
    for pg in j['progs']:
        ax = axs[k]; k += 1
        ax.plot([0, L, L, 0, 0], [0, 0, W, W, 0], 'k-', lw=0.6)
        ol = j['outline'] if pg['side'] == 1 else [[L - x, y] for x, y in j['outline']]
        ax.fill([q[0] for q in ol], [q[1] for q in ol], color='#d9b38c', alpha=0.6)
        for kind, pts in pg['ops']:
            xs = [q[0] for q in pts]; ys = [q[1] for q in pts]
            c = {'clear': '#4a90d9', 'mark': '#c0392b', 'contour': '#1f4e79'}[kind]
            ax.plot(xs, ys, color=c, lw=0.4 if kind == 'clear' else 1.2)
        for a in pg['aggs']:
            (bx, by), (nx, ny) = a['axis']
            ax.plot([bx, bx - nx * 160], [by, by - ny * 160], color='#27ae60', lw=2.5)
        ax.set_aspect('equal'); ax.set_title(f"{j['label']} Seite {pg['side']}", fontsize=8)
fig.savefig(out, dpi=90, bbox_inches='tight')
