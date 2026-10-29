# World campaign backdrop: Equal Earth (lon0 = 10) parchment world from Natural Earth 1:50m admin-0 (public domain).
import sys, os, numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from geo import EqualEarth, polys, DATA, _load
from PIL import Image, ImageDraw, ImageFilter
H = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(H, '..', 'project', 'Assets', 'Textures', 'ui', 'worldmap.png')
EE = EqualEarth(10.0)
XM = EE(190.0, 0.0)[0]; Y0 = EE(0, -58.0)[1]; Y1 = EE(0, 84.0)[1]
W = 2048; Hh = int(W * (Y1 - Y0) / (2 * XM))
print('size', W, Hh, 'XM', XM, 'Y0', Y0, 'Y1', Y1)
tp = lambda xs, ys: list(zip((np.asarray(xs) + XM) / (2 * XM) * W, (Y1 - np.asarray(ys)) / (Y1 - Y0) * Hh))
TINT = {'Europe': (236, 214, 170), 'Asia': (226, 206, 160), 'Africa': (238, 200, 140), 'North America': (214, 214, 168),
        'South America': (206, 220, 160), 'Oceania': (232, 196, 160), 'Antarctica': (240, 240, 236), 'Seven seas (open ocean)': (230, 210, 170)}
yy, xx = np.mgrid[0:Hh, 0:W]
# sea: deep blue with soft vignette + noise
rg = np.random.default_rng(3)
nz = np.asarray(Image.fromarray((rg.random((Hh // 16, W // 16)) * 255).astype(np.uint8)).resize((W, Hh), Image.BICUBIC)) / 255
v = np.hypot((xx - W / 2) / (W / 2), (yy - Hh / 2) / (Hh / 2))
sea = np.array([0.16, 0.38, 0.52])[None, None] * (1.05 - 0.25 * v[..., None]) * (0.95 + 0.1 * nz[..., None])
img = Image.fromarray((np.clip(sea, 0, 1) * 255).astype(np.uint8))
land = Image.new('L', (W, Hh), 0); dl = ImageDraw.Draw(land)
col = Image.new('RGB', (W, Hh), (0, 0, 0)); dc = ImageDraw.Draw(col)
lines = Image.new('L', (W, Hh), 0); dli = ImageDraw.Draw(lines)
for d, g in _load(os.path.join(DATA, 'ne_50m_admin_0_countries/ne_50m_admin_0_countries.shp'), 'ADMIN'):
    if d['CONTINENT'] == 'Antarctica': continue
    c = TINT.get(d['CONTINENT'], (230, 210, 170)); j = (hash(d['ADMIN']) % 13 - 6)
    for p in polys(g):
        x, y = EE(*np.array(p.exterior.coords).T)
        pts = tp(x, y)
        if len(pts) < 3: continue
        dl.polygon(pts, fill=255); dc.polygon(pts, fill=tuple(int(np.clip(k + j, 0, 255)) for k in c))
        dli.line(pts + [pts[0]], fill=255, width=1)
L = np.asarray(land) > 0
# shallow-water halo
halo = np.asarray(land.filter(ImageFilter.GaussianBlur(10))) / 255.0
a = np.asarray(img).astype(float) / 255
a = a + (np.array([0.45, 0.72, 0.74]) - a) * np.clip(halo * 1.6, 0, 1)[..., None] * 0.55
c = np.asarray(col).astype(float) / 255 * (0.94 + 0.08 * nz[..., None])
ln = np.asarray(lines.filter(ImageFilter.GaussianBlur(0.6))) / 255.0
c = c * (1 - 0.25 * ln[..., None])
a[L] = c[L]
# coast line + graticule
edge = np.asarray(land.filter(ImageFilter.FIND_EDGES)) > 0
a[edge] = a[edge] * 0.55
out = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8)).convert('RGBA')
gr = ImageDraw.Draw(out, 'RGBA')
for lat in range(-45, 85, 15):
    lo = np.linspace(-170, 190, 200); x, y = EE(lo, np.full_like(lo, lat)); gr.line(tp(x, y), fill=(255, 255, 255, 34), width=1)
for lon in range(-165, 195, 30):
    la = np.linspace(-58, 84, 120); x, y = EE(np.full_like(la, lon), la); gr.line(tp(x, y), fill=(255, 255, 255, 34), width=1)
out.save(OUT)
print('saved', OUT)
