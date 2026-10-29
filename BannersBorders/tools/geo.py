# Natural Earth loading + Albers projection + region assembly for Banners & Borders maps.
# Data: Natural Earth 1:10m Admin-0 countries / Admin-1 states-provinces (public domain, naturalearthdata.com).
import os, numpy as np, shapefile
from shapely.geometry import shape, box, Polygon, MultiPolygon, Point
from shapely.ops import unary_union, transform
from shapely import make_valid
# Natural Earth data folder: $BB_DATA, else <game>/data (tools/fetch_natural_earth.py fills it), else the box path.
_HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.environ.get('BB_DATA') or next((d for d in (os.path.join(_HERE, '..', 'data'), '/workspace/games/banners_data')
                                          if os.path.isdir(d)), os.path.join(_HERE, '..', 'data'))
_A0 = _A1 = None
def _load(path, key):
    r = shapefile.Reader(path); f = [x[0] for x in r.fields[1:]]; out = []
    for sr, rec in zip(r.shapes(), r.records()):
        d = dict(zip(f, rec))
        try: g = make_valid(shape(sr.__geo_interface__))
        except Exception: continue
        out.append((d, g))
    return out
def a0():
    global _A0
    if _A0 is None: _A0 = _load(os.path.join(DATA, 'ne_10m_admin_0_countries/ne_10m_admin_0_countries.shp'), 'ADMIN')
    return _A0
def a1():
    global _A1
    if _A1 is None: _A1 = _load(os.path.join(DATA, 'ne_10m_admin_1_states_provinces/ne_10m_admin_1_states_provinces.shp'), 'name')
    return _A1
def polys(g):
    if g is None or g.is_empty: return []
    if isinstance(g, Polygon): return [g]
    if isinstance(g, MultiPolygon): return list(g.geoms)
    if hasattr(g, 'geoms'): return [p for x in g.geoms for p in polys(x)]
    return []
def country(name):
    for d, g in a0():
        if d['ADMIN'] == name or d['NAME'] == name: return g
    raise KeyError(name)
def adm1(admin, pred=None):
    return [(d, g) for d, g in a1() if d['admin'] == admin and (pred is None or pred(d))]

class Albers:
    def __init__(s, lon0, lat0, lat1, lat2):
        s.l0 = np.radians(lon0); p0, p1, p2 = np.radians([lat0, lat1, lat2])
        s.n = (np.sin(p1) + np.sin(p2)) / 2; s.C = np.cos(p1) ** 2 + 2 * s.n * np.sin(p1)
        s.r0 = np.sqrt(s.C - 2 * s.n * np.sin(p0)) / s.n
    def __call__(s, lon, lat, z=None):
        lon = np.radians(np.asarray(lon)); lat = np.radians(np.asarray(lat))
        r = np.sqrt(s.C - 2 * s.n * np.sin(lat)) / s.n; th = s.n * (lon - s.l0)
        return r * np.sin(th) * 6371.0, (s.r0 - r * np.cos(th)) * 6371.0   # km east, km north

def kmeans_split(items, k, seed=3):
    """items: [(d, geom)] admin-1 units -> k unions grouped by area-weighted k-means on centroids"""
    P = np.array([[g.centroid.x, g.centroid.y] for _, g in items]); W = np.array([max(g.area, 1e-6) for _, g in items])
    rg = np.random.default_rng(seed); best = None
    for trial in range(12):
        C = P[rg.choice(len(P), k, replace=False)]
        for it in range(60):
            lab = np.argmin(((P[:, None] - C[None]) ** 2).sum(-1), 1)
            for j in range(k):
                if (lab == j).any(): C[j] = (P[lab == j] * W[lab == j, None]).sum(0) / W[lab == j].sum()
        A = np.array([W[lab == j].sum() for j in range(k)])
        score = A.std() / A.mean() + 0.0 * ((P - C[lab]) ** 2).sum()
        if (A > 0).all() and (best is None or score < best[0]): best = (score, lab.copy())
    lab = best[1]
    return [unary_union([g for (d, g), l in zip(items, lab) if l == j]) for j in range(k)]

def compass(g, ref):
    c, r = g.centroid, ref.centroid; dx, dy = c.x - r.x, c.y - r.y
    if abs(dx) < 1e-9 and abs(dy) < 1e-9: return ''
    a = np.degrees(np.arctan2(dy, dx)) % 360
    names = ['East', 'NE', 'North', 'NW', 'West', 'SW', 'South', 'SE']
    return names[int(((a + 22.5) % 360) // 45)]

class EqualEarth:
    """Equal Earth projection (Savric et al. 2018), km; used for the whole-world map."""
    A1, A2, A3, A4 = 1.340264, -0.081106, 0.000893, 0.003796
    def __init__(s, lon0=0.0): s.l0 = np.radians(lon0); s.M = np.sqrt(3) / 2
    def __call__(s, lon, lat, z=None):
        lam = np.radians(np.asarray(lon)) - s.l0; phi = np.radians(np.asarray(lat))
        th = np.arcsin(s.M * np.sin(phi)); t2 = th * th; t6 = t2 * t2 * t2
        x = 2 * np.sqrt(3) * lam * np.cos(th) / (3 * (9 * s.A4 * t6 * t2 + 7 * s.A3 * t6 + 3 * s.A2 * t2 + s.A1))
        y = th * (s.A4 * t6 * t2 + s.A3 * t6 + s.A2 * t2 + s.A1)
        return x * 6371.0, y * 6371.0

def outline(names=None, continent=None, clip=None, exclude=()):
    """Union of Natural Earth admin-0 countries (by ADMIN/NAME list or CONTINENT), optionally clipped to a lon/lat box."""
    gs = []
    for d, g in a0():
        if d['ADMIN'] in exclude: continue
        ok = (names and (d['ADMIN'] in names or d['NAME'] in names)) or (continent and d['CONTINENT'] in ([continent] if isinstance(continent, str) else continent))
        if not ok: continue
        if clip is not None: g = make_valid(g.intersection(box(*clip)))
        if not g.is_empty: gs.append(g)
    assert gs, (names, continent)
    return make_valid(unary_union(gs))

def label_points(level, admins=None, continent=None, clip=None):
    """[(name, lon, lat, rank)] candidate region names: admin-1 units of the given countries, or admin-0 countries."""
    out = []
    if level == 1:
        for d, g in a1():
            if admins and d['admin'] not in admins: continue
            n = d.get('name_en') or d['name']
            lon, lat = d.get('longitude'), d.get('latitude')
            if not lon and not lat: c = g.representative_point(); lon, lat = c.x, c.y
            out.append((n, float(lon), float(lat), float(d.get('labelrank') or 5)))
    else:
        for d, g in a0():
            if continent and d['CONTINENT'] not in ([continent] if isinstance(continent, str) else continent): continue
            if admins and d['ADMIN'] not in admins: continue
            lon, lat = d.get('LABEL_X'), d.get('LABEL_Y')
            if lon is None: c = g.representative_point(); lon, lat = c.x, c.y
            if float(d.get('POP_EST') or 0) < 1.5e6: continue      # skip micro-territories as region names
            out.append((d['NAME'], float(lon), float(lat), -np.log10(max(float(d.get('POP_EST') or 1), 1.0))))
    if clip is not None: out = [o for o in out if clip[0] <= o[1] <= clip[2] and clip[1] <= o[2] <= clip[3]]
    return out
