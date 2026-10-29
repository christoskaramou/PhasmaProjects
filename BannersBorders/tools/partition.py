import re
# Gameplay partition: split an accurate outline into ~k compact regions (k-means/Lloyd on area samples ->
# Voronoi cells clipped to the outline), then clean up (contiguous cells, small islands merged, big islands kept).
import numpy as np, unicodedata
import shapely
from shapely.geometry import MultiPoint, Point, box
from shapely.ops import unary_union, nearest_points
from shapely import make_valid
from geo import polys

def _lloyd(pts, init, n, rg, iters=40):
    C = list(init[:n])
    while len(C) < n:                                   # k-means++ for the rest
        if not C: C.append(pts[rg.integers(len(pts))]); continue
        d = np.min(((pts[:, None] - np.array(C)[None]) ** 2).sum(-1), 1)
        C.append(pts[rg.choice(len(pts), p=d / d.sum())])
    C = np.array(C, float); fixed = min(len(init), n)
    for _ in range(iters):
        lab = np.argmin(((pts[:, None] - C[None]) ** 2).sum(-1), 1)
        for j in range(n):
            m = lab == j
            if m.any(): C[j] = C[j] * (0.5 if j < fixed else 0.0) + pts[m].mean(0) * (0.5 if j < fixed else 1.0)
    return C

def partition(outline, k, seeds=(), seed=7, island_keep=0.45, island_drop=0.04):
    """outline: projected polygon(s). seeds: projected (x, y) hints. returns list of geoms (~k)."""
    rg = np.random.default_rng(seed)
    parts = sorted(polys(outline), key=lambda p: -p.area)
    A = sum(p.area for p in parts); mean = A / k
    big = [p for p in parts if p.area >= island_keep * mean]
    small = [p for p in parts if island_drop * mean <= p.area < island_keep * mean]
    # seeds per big part, proportional to area, total = k
    raw = np.array([p.area / mean for p in big]); cnt = np.maximum(1, np.round(raw)).astype(int)
    while cnt.sum() > k and (cnt > 1).any(): j = np.argmax(np.where(cnt > 1, cnt - raw, -9)); cnt[j] -= 1
    while cnt.sum() < k: j = np.argmax(raw - cnt); cnt[j] += 1
    cells = []
    for p, n in zip(big, cnt):
        if n == 1: cells.append(p); continue
        x0, y0, x1, y1 = p.bounds; step = np.sqrt(p.area / (n * 220))
        gx, gy = np.meshgrid(np.arange(x0, x1, step), np.arange(y0, y1, step))
        P = np.stack([gx.ravel(), gy.ravel()], 1); P = P[shapely.contains_xy(p, P[:, 0], P[:, 1])]
        init = [np.array(s) for s in seeds if p.contains(Point(s))]
        C = _lloyd(P, init, n, rg)
        vor = shapely.voronoi_polygons(MultiPoint([tuple(c) for c in C]), extend_to=p.buffer(10))
        for v in polys(vor):
            c = make_valid(v.intersection(p))
            if not c.is_empty: cells.append(c)
    # contiguous cells: keep the biggest piece, hand the rest to the touching cell with the longest shared edge
    main, orphans = [], []
    for c in cells:
        ps = sorted(polys(c), key=lambda q: -q.area)
        if not ps: continue
        main.append(ps[0]); orphans += ps[1:]
    main = [[m] for m in main]
    def attach(o, near_only=False):
        best, bj = -1, None
        for j, ms in enumerate(main):
            u = ms[0]
            s = o.buffer(0.05).intersection(u).area
            if s > best: best, bj = s, j
        if best <= 1e-9:
            if near_only: return
            bj = min(range(len(main)), key=lambda j: main[j][0].distance(o))
        main[bj].append(o)
    for o in orphans:
        if o.area > 1e-4: attach(o)
    for o in small: attach(o)
    out = [make_valid(unary_union(ms)) for ms in main]
    # merge slivers (< 30% of mean) into their best neighbour
    changed = True
    while changed and len(out) > 2:
        changed = False
        ar = [g.area for g in out]; i = int(np.argmin(ar))
        if ar[i] < 0.3 * mean:
            g = out.pop(i)
            j = max(range(len(out)), key=lambda j: g.buffer(0.1).intersection(out[j]).area - 1e-3 * out[j].distance(g))
            out[j] = make_valid(unary_union([out[j], g])); changed = True
    return out

def ascii_name(s):
    s = unicodedata.normalize('NFKD', s).encode('ascii', 'ignore').decode()
    s = {'United States of America': 'United States', 'Dem. Rep. Congo': 'Congo Basin', 'Central African Rep.': 'C. Africa'}.get(s, s)
    s = re.sub(r' (State|Region)$', '', s)
    s = s.replace(' Pradesh', '').replace('Province', '').replace('Prefecture', '').strip(' -')
    for a, b in (('North ', 'N. '), ('South ', 'S. '), ('East ', 'E. '), ('West ', 'W. '), ('Northern ', 'N. '), ('Southern ', 'S. '),
                 ('Central ', 'C. '), ('Western ', 'W. '), ('Eastern ', 'E. ')):
        if s.startswith(a) and len(s) > 12: s = b + s[len(a):]
    return s if len(s) <= 15 else s[:14].rstrip() + '.'

FLAVOUR = ['Marches', 'Reach', 'Heights', 'Vale', 'Downs', 'Fells', 'Steppe', 'Shore', 'Wilds', 'Plateau', 'Hollows', 'Ridge']
def name_regions(geoms, labels, xy):
    """labels: [(name, lon, lat, rank)]; xy: projector lon,lat -> plane. Greedy: biggest regions pick the best unused label inside them."""
    pts = [(ascii_name(n), xy(lo, la), r) for n, lo, la, r in labels]
    used, names = set(), [None] * len(geoms)
    order = sorted(range(len(geoms)), key=lambda i: -geoms[i].area)
    for i in order:
        g = geoms[i]; c = g.representative_point()
        inside = [(r, n) for n, p, r in pts if n not in used and g.contains(Point(p))]
        if inside: n = min(inside)[1]
        else:
            near = sorted(((Point(p).distance(g), n) for n, p, r in pts if n not in used))
            n = near[0][1] if near and near[0][0] < 3.0 else None
        if n is None: n = FLAVOUR[i % len(FLAVOUR)]
        used.add(n); names[i] = n
    return names
