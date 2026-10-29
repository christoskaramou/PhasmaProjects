# Generate per-map meshes (region tiles, land base, context countries, sea), sea textures and Lua map data.
# usage: python3 gen_maps.py [map ...]
import sys, os, json, numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from geo import *
import mapspecs
from shapely.geometry.polygon import orient
from shapely.ops import polylabel
from shapely import affinity
import mapbox_earcut as earcut
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage
from partition import partition, name_regions
H = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.join(H, '..')
MS = os.path.join(ROOT, 'meshsrc'); TEX = os.path.join(ROOT, 'project', 'Assets', 'Textures'); os.makedirs(MS, exist_ok=True)
PREV = os.path.join(ROOT, '_preview'); os.makedirs(PREV, exist_ok=True)
SHORT = dict(greece='gr', balkans='bk', italy='it', iberia='ib', europe='eu', usa='us', india='in', china='cn', japan='jp', asia='as',
             africa='af', westafrica='wa', southafrica='sa', australia='au', nz='nz', brazil='br', southamerica='sm', mexico='mx', world='wo')
TARGET = 6.4          # median sqrt(region area) in world units
GAP = 0.075           # inset per side -> border line width ~0.15
CELL = 0.25
CLOSE = 0.32          # closing radius (fills coastal slots narrower than ~0.6 units)
MINSEG = 0.14        # min outline segment (keeps the combined GPU geometry buffer small)

def lakes():
    out = []
    r = shapefile.Reader(os.path.join(DATA, 'ne_10m_lakes/ne_10m_lakes.shp')); f = [x[0] for x in r.fields[1:]]
    for sr, rec in zip(r.shapes(), r.records()):
        d = dict(zip(f, rec))
        if d['scalerank'] <= 3:
            try: out.append(make_valid(shape(sr.__geo_interface__)))
            except Exception: pass
    return unary_union(out)

# ------------------------------------------------------------------ mesh writing
class Mesh:
    def __init__(s): s.V, s.N, s.UV, s.F = [], [], [], []
    def add(s, v, n, uv): s.V.append(v); s.N.append(n); s.UV.append(uv); return len(s.V) - 1
    def save(s, name):
        V = np.array(s.V); N = np.array(s.N)
        with open(os.path.join(MS, name + '.obj'), 'w') as fo:
            fo.write(f'o {name}\n')
            fo.write(''.join('v %.4f %.4f %.4f\n' % tuple(p) for p in V))
            fo.write(''.join('vt %.5f %.5f\n' % tuple(t) for t in s.UV))
            fo.write(''.join('vn %.4f %.4f %.4f\n' % tuple(n) for n in N))
            for a, b, c in s.F:
                fn = np.cross(V[b] - V[a], V[c] - V[a])
                if np.linalg.norm(fn) < 1e-7: continue
                if np.dot(fn, N[a] + N[b] + N[c]) < 0: b, c = c, b
                fo.write(f'f {a+1}/{a+1}/{a+1} {b+1}/{b+1}/{b+1} {c+1}/{c+1}/{c+1}\n')
        print(' ', name, len(V), 'v', len(s.F), 't')

def ring_pts(r):
    P = np.array(r.coords)[:-1]
    keep = [0]
    for i in range(1, len(P)):
        if np.linalg.norm(P[i] - P[keep[-1]]) > MINSEG: keep.append(i)
    P = P[keep]
    if len(P) > 3 and np.linalg.norm(P[0] - P[-1]) < 1e-4: P = P[:-1]
    return P

def miter(P):
    """inward (left side for CCW exterior / CW hole) unit miter directions + scale"""
    e = np.roll(P, -1, 0) - P; L = np.linalg.norm(e, axis=1, keepdims=True); e = e / np.maximum(L, 1e-9)
    nl = np.stack([-e[:, 1], e[:, 0]], 1)            # left normal of edge i (P[i]->P[i+1])
    n1 = np.roll(nl, 1, 0); n2 = nl                  # prev edge, next edge at vertex i
    m = n1 + n2; ml = np.linalg.norm(m, axis=1, keepdims=True)
    m = np.where(ml > 1e-6, m / np.maximum(ml, 1e-9), n2)
    k = 1.0 / np.maximum((m * n2).sum(1), 0.45)
    return m, k

def tile(mesh, geom, h, bevel, ybot, uvf, steps=3):
    """extrude polygon(s) (2D e,n) into a soft-bevelled tile: top at h, walls down to ybot. world X = -e."""
    for p in polys(geom):
        p = orient(p, 1.0)
        rings = [ring_pts(p.exterior)] + [ring_pts(r) for r in p.interiors]
        rings = [r for r in rings if len(r) >= 3]
        if not rings: continue
        caps = []
        for R in rings:
            m, k = miter(R); n = len(R)
            idx = []
            for s in range(steps + 1):
                th = s / steps * np.pi / 2
                Q = R + m * (k[:, None] * bevel * (1 - np.cos(th)))
                y = h - bevel + bevel * np.sin(th)
                row = []
                for i in range(n):
                    nx, nz = -m[i] * np.cos(th)
                    nv = np.array([-nx, np.sin(th), nz]); nv /= np.linalg.norm(nv)
                    row.append(mesh.add((-Q[i, 0], y, Q[i, 1]), nv, uvf(Q[i])))
                idx.append(row)
                if s == steps: caps.append(Q)
            # wall
            row = []
            for i in range(n):
                nx, nz = -m[i]; row.append(mesh.add((-R[i, 0], ybot, R[i, 1]), (-nx, 0, nz), uvf(R[i])))
            idx.insert(0, row)
            for a in range(len(idx) - 1):
                A, B = idx[a], idx[a + 1]
                for i in range(n):
                    j = (i + 1) % n
                    mesh.F += [(A[i], A[j], B[j]), (A[i], B[j], B[i])]
        # cap
        flat = np.concatenate(caps); ends = np.cumsum([len(c) for c in caps]).astype(np.uint32)
        tri = earcut.triangulate_float64(flat, ends).reshape(-1, 3)
        base = [mesh.add((-q[0], h, q[1]), (0, 1, 0), uvf(q)) for q in flat]
        mesh.F += [(base[a], base[b], base[c]) for a, b, c in tri]

def quad(mesh, e0, n0, e1, n1, y, uv=True):
    a = mesh.add((-e0, y, n0), (0, 1, 0), (0, 0)); b = mesh.add((-e1, y, n0), (0, 1, 0), (1, 0))
    c = mesh.add((-e1, y, n1), (0, 1, 0), (1, 1)); d = mesh.add((-e0, y, n1), (0, 1, 0), (0, 1))
    mesh.F += [(a, b, c), (a, c, d)]

# ------------------------------------------------------------------ map build
def opening(g, r):
    try: return make_valid(g.buffer(-r, join_style=1).buffer(r, join_style=1))
    except Exception: return g

def build(key, LAKES):
    spec = mapspecs.MAPS[key](); sh = SHORT[key]
    lon0, lat0, lon1, lat1 = spec['bbox']
    pj = spec.get('proj') or ((lon0 + lon1) / 2, (lat0 + lat1) / 2, lat0 + (lat1 - lat0) / 6, lat1 - (lat1 - lat0) / 6)
    A = EqualEarth(spec.get('lon0', 0.0)) if spec.get('proj') == 'ee' else Albers(*pj)
    P = lambda g: transform(lambda x, y, z=None: A(x, y), g)
    hills = set(spec.get('hills', set()))
    if 'outline' in spec:          # gameplay partition of an accurate outline
        og = P(make_valid(spec['outline'].difference(LAKES)))
        s = np.sqrt(spec['k'] * (TARGET * 1.06) ** 2 / og.area)
        og = affinity.scale(og, s, s, origin=(0, 0))
        xy = lambda lo, la: tuple(np.array(A(lo, la)) * s)
        cells = partition(og, spec['k'], [xy(*q) for q in spec.get('seeds', ())], seed=spec.get('seed', 7), island_keep=spec.get('islands', 0.45))
        names = name_regions(cells, spec.get('labels', []), xy)
        regs = list(zip(names, cells))
        for lo, la in spec.get('hills_ll', ()):
            for n, g in regs:
                if g.buffer(0.5).contains(Point(xy(lo, la))): hills.add(n)
    else:
        regs = [(n, P(make_valid(g.difference(LAKES)))) for n, g in spec['regions']]
        med = np.median([np.sqrt(g.area) for n, g in regs]); s = TARGET / med
        regs = [(n, affinity.scale(g, s, s, origin=(0, 0))) for n, g in regs]
    # play extent (projected bbox corners + region bounds)
    allr = unary_union([g for n, g in regs]); bx = allr.bounds
    cx, cy = (bx[0] + bx[2]) / 2, (bx[1] + bx[3]) / 2
    regs = [(n, affinity.translate(g, -cx, -cy)) for n, g in regs]
    allr = affinity.translate(allr, -cx, -cy); bx = allr.bounds
    W, Hh = bx[2] - bx[0], bx[3] - bx[1]
    pad = max(W, Hh) * spec.get('pad', 0.3) + 10
    PE = (bx[0] - pad, bx[1] - pad, bx[2] + pad, bx[3] + pad)   # padded (sea / land base) extent
    # land base: every country intersecting a generous lon/lat box
    dl = max(lon1 - lon0, lat1 - lat0) * 1.2 + 8
    llbox = box(lon0 - dl, max(lat0 - dl, spec.get('minlat', -80)), lon1 + dl, min(lat1 + dl, 84))
    T = lambda g: affinity.translate(affinity.scale(P(g), s, s, origin=(0, 0)), -cx, -cy)
    pbox = box(*PE)
    land_c = []
    for d, g in a0():
        b = g.bounds
        if d['ADMIN'] == 'Antarctica': continue
        if b[2] < llbox.bounds[0] or b[0] > llbox.bounds[2] or b[3] < llbox.bounds[1] or b[1] > llbox.bounds[3]: continue
        gg = make_valid(g.intersection(llbox).difference(LAKES))
        if gg.is_empty: continue
        try: tg = make_valid(T(gg)).intersection(pbox)
        except Exception: continue
        if not tg.is_empty: land_c.append((d['ADMIN'], tg))
    land = unary_union([g for n, g in land_c] + [g for n, g in regs])
    tol = spec.get('tol', 0.08)
    land_s = make_valid(opening(land, 0.05).simplify(tol)).buffer(0.1, join_style=1)
    land_s = make_valid(land_s.buffer(CLOSE, join_style=1).buffer(-CLOSE, join_style=1)).simplify(tol)
    land_s = unary_union([p for p in polys(land_s) if p.area > 0.25])
    # regions: smooth, simplify, drop specks, inset
    R = []
    # closing fills narrow coastal notches: their deep, unlit slot walls read as black jagged patches at map zoom
    allfull = [make_valid(g) for n, g in regs]
    for ri, (n, g) in enumerate(regs):
        g = make_valid(opening(g, 0.06))
        try:
            cl = make_valid(g.buffer(CLOSE, join_style=1).buffer(-CLOSE, join_style=1))
            others = unary_union([q for k, q in enumerate(allfull) if k != ri and q.distance(g) < 2 * CLOSE])
            g = make_valid(unary_union([g, make_valid(cl.difference(others.buffer(0.01)))])) if not others.is_empty else cl
        except Exception: pass
        g = make_valid(g.simplify(tol))
        ps = sorted(polys(g), key=lambda p: -p.area)
        ps = [p for i, p in enumerate(ps) if i == 0 or p.area > 0.35]
        full = unary_union(ps)
        ins = unary_union([q for q in polys(make_valid(full.buffer(-GAP, join_style=2).simplify(0.02))) if q.area > 0.12])
        R.append(dict(name=n, full=full, ins=ins))
    ru = unary_union([r['full'] for r in R])
    ctx = []
    for n, g in land_c:
        cg = make_valid(g.difference(ru.buffer(0.02)))
        cg = make_valid(opening(cg, 0.1).simplify(tol * 2))
        ci = unary_union([q for q in polys(make_valid(cg.buffer(-GAP, join_style=2).simplify(tol))) if q.area > 0.8])
        if not ci.is_empty: ctx.append(ci)
    ctx = unary_union(ctx)
    # ---------------- meshes
    E0, N0, E1, N1 = bx[0] - 2, bx[1] - 2, bx[2] + 2, bx[3] + 2
    uvf = lambda q: ((q[0] - E0) / (E1 - E0), (q[1] - N0) / (N1 - N0))
    rng = np.random.default_rng(len(key))
    out = []
    for i, r in enumerate(R):
        hill = r['name'] in hills
        h = (0.86 if hill else 0.5) + rng.random() * 0.1
        m = Mesh(); tile(m, r['ins'], h, 0.13, 0.08, uvf, 2); m.save(f'r_{sh}_{i:02d}')
        big = max(polys(r['ins']), key=lambda p: p.area)
        an = polylabel(big, 0.02)
        r.update(h=h, hill=hill, ax=an.x, az=an.y)
        out.append(r)
    m = Mesh(); tile(m, land_s, 0.22, 0.16, -0.5, lambda q: ((q[0] - PE[0]) / (PE[2] - PE[0]), (q[1] - PE[1]) / (PE[3] - PE[1])), 1)
    m.save(f'land_{sh}')
    m = Mesh(); tile(m, ctx, 0.36, 0.1, 0.1, uvf, 1); (m.save(f'ctx_{sh}') if m.V else None)   # no context land (e.g. New Zealand): skip the empty mesh
    m = Mesh(); quad(m, PE[0], PE[1], PE[2], PE[3], 0.0); m.save(f'sea_{sh}')
    return dict(key=key, sh=sh, spec=spec, R=out, land=land_s, ctx=ctx, bx=bx, PE=PE, ext=(E0, N0, E1, N1), scale=s, pj=pj, cxy=(cx, cy), A=A)

# ------------------------------------------------------------------ raster / texture / lua
def raster(geoms_vals, E0, N0, W, Hh, ppu, fill0=0):
    im = Image.new('L', (W, Hh), fill0); dr = ImageDraw.Draw(im)
    tp = lambda c: [((x - E0) * ppu, (N0 + Hh / ppu - y) * ppu) for x, y in c]
    for g, v in geoms_vals:
        for p in polys(g):
            dr.polygon(tp(p.exterior.coords), fill=v)
            for h in p.interiors: dr.polygon(tp(h.coords), fill=fill0)
    return np.asarray(im)

def fbm2(h, w, seed, base=6, octv=5):
    rg = np.random.default_rng(seed); o = np.zeros((h, w)); a = 1; tot = 0
    for k in range(octv):
        f = base * 2 ** k; r = rg.random((f, max(2, int(f * w / h))))
        o += np.asarray(Image.fromarray((r * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)) / 255 * a; tot += a; a *= 0.5
    return o / tot

def sea_texture(M):
    PE = M['PE']; Wu, Hu = PE[2] - PE[0], PE[3] - PE[1]
    ppu = min(1024 / Wu, 1024 / Hu); W, Hh = int(Wu * ppu), int(Hu * ppu)
    mask = raster([(M['land'], 255)], PE[0], PE[1], W, Hh, ppu) > 0
    d = ndimage.distance_transform_edt(~mask) / ppu
    nz = fbm2(Hh, W, 5, 8); nz2 = fbm2(Hh, W, 9, 30, 4)
    deep = np.array([0.075, 0.25, 0.43]); mid = np.array([0.12, 0.42, 0.6]); shal = np.array([0.32, 0.72, 0.74])
    t1 = np.exp(-d / 1.1)[..., None]; t2 = np.exp(-d / 5.0)[..., None]
    c = deep + (mid - deep) * t2 + (shal - mid) * t1 * (0.85 + 0.3 * nz[..., None])
    c *= (0.94 + 0.12 * nz2)[..., None]
    for ring, wdt in ((0.55, 0.07), (1.15, 0.06), (1.9, 0.05)):
        dd = d + (nz - 0.5) * 0.5
        band = np.exp(-((dd - ring) / wdt) ** 2) * (nz2 > 0.42) * np.exp(-ring / 1.6)
        c = c + (np.array([0.85, 0.95, 0.95]) - c) * band[..., None] * 0.55
    foam = np.clip(1 - d / 0.2, 0, 1) ** 1.5 * (d > 0)
    c = c + (np.array([0.93, 0.97, 0.96]) - c) * foam[..., None] * 0.9
    c[mask] = shal * 0.9
    # fade into exact deep colour at the texture border
    yy, xx = np.mgrid[0:Hh, 0:W]; edge = np.minimum.reduce([xx, yy, W - 1 - xx, Hh - 1 - yy]) / (0.1 * min(W, Hh))
    e = np.clip(edge, 0, 1)[..., None] ** 1.5
    c = deep + (c - deep) * e
    Image.fromarray((np.clip(c, 0, 1) * 255).astype(np.uint8)).save(os.path.join(TEX, f"sea_{M['sh']}.png"))
    return deep

def lua_out(M):
    E0, N0, E1, N1 = M['ext']; gw, gh = int(np.ceil((E1 - E0) / CELL)), int(np.ceil((N1 - N0) / CELL))
    ppu = 1 / CELL
    vals = [(M['land'], 1), (M['ctx'], 1)] + [(r['full'], 48 + i) for i, r in enumerate(M['R'])]
    g = raster(vals, E0, N0, gw, gh, ppu, 0)[::-1]       # row 0 = south
    ch = np.where(g == 0, ord('.'), np.where(g == 1, ord(','), g)).astype(np.uint8)
    grid = ''.join(bytes(row).decode('latin1') for row in ch)
    sea = make_valid(box(*M['PE']).difference(M['land']))
    rng = np.random.default_rng(11)
    L = ["BB_MAPS = BB_MAPS or {}", f"BB_MAPS.{M['key']} = {{ sh = \"{M['sh']}\", cell = {CELL}, gw = {gw}, gh = {gh}, e0 = {E0:.3f}, n0 = {N0:.3f}, e1 = {E1:.3f}, n1 = {N1:.3f},",
         f"  pe = {{ {M['PE'][0]:.2f}, {M['PE'][1]:.2f}, {M['PE'][2]:.2f}, {M['PE'][3]:.2f} }}, land_h = 0.22, ctx_h = 0.36,",
         "  regions = {"]
    NB = [[j + 1 for j, q in enumerate(M['R']) if j != i and r['full'].distance(q['full']) < 0.35] for i, r in enumerate(M['R'])]
    CO = [r['full'].buffer(0.35).intersects(sea) for r in M['R']]
    info = auto_info(M, NB, CO)
    for i, r in enumerate(M['R']):
        nb, coast = NB[i], CO[i]
        area = r['full'].area
        # decoration slots
        inner = r['ins'].buffer(-0.38); slots = []
        if not inner.is_empty:
            mnx, mny, mxx, mxy = inner.bounds; want = int(np.clip(area / 4.5, 2, 10)); tries = 0
            while len(slots) < want and tries < 600:
                tries += 1; px, py = rng.uniform(mnx, mxx), rng.uniform(mny, mxy)
                if not inner.contains(Point(px, py)): continue
                if np.hypot(px - r['ax'], py - r['az']) < 1.35: continue
                if any(np.hypot(px - a, py - b) < 0.9 for a, b in slots): continue
                slots.append((px, py))
        dz = ', '.join(f'{-a:.2f}, {b:.2f}' for a, b in slots)
        L.append(f"    {{ name = \"{r['name']}\", x = {-r['ax']:.3f}, z = {r['az']:.3f}, h = {r['h']:.3f}, hill = {str(r['hill']).lower()}, "
                 f"area = {area:.2f}, coast = {str(coast).lower()}, nb = {{ {', '.join(map(str, nb))} }}, deco = {{ {dz} }} }},")
    L.append("  },")
    sp = M['spec']; bb = sp['bbox']
    L.append(f"  title = \"{sp.get('title', M['key'].title())}\", ll = {{ {(bb[0] + bb[2]) / 2:.2f}, {(bb[1] + bb[3]) / 2:.2f} }},")
    L.append("  info = { " + ', '.join(f"{k} = {{ {', '.join(str(v) for v in info[k])} }}" for k in ('ports', 'mines', 'forts')) + " },")
    sea = sp.get('sea_labels')
    if sea:   # ocean / neighbour captions drawn by the HUD (world x is mirrored like the regions)
        s_, (cx_, cy_) = M['scale'], M['cxy']
        def wxz(lo, la):
            ax, ay = M['A'](lo, la); return -(ax * s_ - cx_), ay * s_ - cy_
        L.append("  sea = { " + ', '.join('{ t = "%s", x = %.2f, z = %.2f, k = %.2f }' % ((t,) + wxz(lo, la) + (k,)) for t, lo, la, k in sea) + " },")
    L.append(f"  grid = [==[{grid}]==] }}")
    return '\n'.join(L) + '\n'

def auto_info(M, NB, CO):
    """auto region roles: ports spread along coasts, forts on hills/crossroads, mines inland (1-based)."""
    R = M['R']; n = len(R); rng = np.random.default_rng(n * 7 + len(M['key']))
    xy = np.array([(r['ax'], r['az']) for r in R])
    def spread(cands, want, taken):
        out = []
        for _ in range(want):
            c = [i for i in cands if i not in out and i not in taken]
            if not c: break
            if not out: out.append(c[int(rng.integers(len(c)))]); continue
            out.append(max(c, key=lambda i: min(np.hypot(*(xy[i] - xy[j])) for j in out)))
        return out
    island = [i for i in range(n) if CO[i] and len(NB[i]) <= 1]
    ports = spread(island + [i for i in range(n) if CO[i] and i not in island], max(2, round(n / 5)), set())
    forts = spread(sorted([i for i in range(n) if R[i]['hill']], key=lambda i: -len(NB[i])) or sorted(range(n), key=lambda i: -len(NB[i]))[:n // 3],
                   max(2, round(n / 7)), set(ports))
    mines = spread([i for i in range(n) if not CO[i]] or list(range(n)), max(2, round(n / 9)), set(ports) | set(forts))
    return dict(ports=[i + 1 for i in ports], mines=[i + 1 for i in mines], forts=[i + 1 for i in forts])

def preview(M):
    E0, N0, E1, N1 = M['PE']; ppu = 900 / max(E1 - E0, N1 - N0); W, Hh = int((E1 - E0) * ppu), int((N1 - N0) * ppu)
    im = Image.open(os.path.join(TEX, f"sea_{M['sh']}.png")).convert('RGB').resize((W, Hh))
    dr = ImageDraw.Draw(im)
    tp = lambda c: [((x - E0) * ppu, (N1 - y) * ppu) for x, y in c]
    for p in polys(M['land']): dr.polygon(tp(p.exterior.coords), fill=(232, 217, 176))
    for p in polys(M['ctx']): dr.polygon(tp(p.exterior.coords), fill=(160, 175, 145))
    for i, r in enumerate(M['R']):
        col = tuple(int(c) for c in np.random.default_rng(i).integers(80, 230, 3))
        for p in polys(r['ins']): dr.polygon(tp(p.exterior.coords), fill=col)
        x, y = tp([(r['ax'], r['az'])])[0]; dr.ellipse((x - 3, y - 3, x + 3, y + 3), fill=(0, 0, 0)); dr.text((x + 4, y - 6), r['name'], fill=(0, 0, 0))
    im.save(os.path.join(PREV, M['key'] + '.png'))

if __name__ == '__main__':
    keys = sys.argv[1:] or list(mapspecs.MAPS)
    LAKES = lakes()
    os.makedirs(os.path.join(ROOT, 'src'), exist_ok=True)
    for k in keys:
        print('==', k)
        M = build(k, LAKES); sea_texture(M)
        open(os.path.join(ROOT, 'src', f'03m_{k}.lua'), 'w').write(lua_out(M)); preview(M)
        E0, N0, E1, N1 = M['ext']; print('  extent', round(E1 - E0, 1), 'x', round(N1 - N0, 1), 'regions', len(M['R']))
