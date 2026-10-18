# Backdrops (17 world locations, painted procedurally), skybox, textures and chip SFX/music for Pang Remix
import numpy as np, os, math
from PIL import Image, ImageDraw, ImageFilter
from audiolib import *
T = os.path.join(R, 'Textures'); SK = os.path.join(R, 'Skybox'); os.makedirs(T, exist_ok=True); os.makedirs(SK, exist_ok=True)
W, H = 1280, 720
rg = np.random.default_rng(3)
def grad(top, bot, horizon=1.0):
    y = np.linspace(0, 1, H)[:, None, None] / horizon
    y = np.clip(y, 0, 1)
    return (np.array(top) * (1 - y) + np.array(bot) * y) * np.ones((H, W, 3))
def to_img(a): return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
def ridge(base, amp, rough, seed, n=64):
    r = np.random.default_rng(seed); xs = np.linspace(0, W, n); ys = np.zeros(n)
    f = 1.0
    for o in range(5): ys += np.interp(np.arange(n), np.linspace(0, n - 1, 4 * 2 ** o + 1), r.uniform(-1, 1, 4 * 2 ** o + 1)) * amp * f; f *= rough
    return [(x, base - y) for x, y in zip(xs, ys)] + [(W, H), (0, H)]
def layer(img, poly, col, blur=0):
    L = Image.new('RGBA', (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(L); d.polygon(poly, fill=tuple(col) + (255,))
    if blur: L = L.filter(ImageFilter.GaussianBlur(blur))
    img.alpha_composite(L)
def shapes(img, fn, blur=0):
    L = Image.new('RGBA', (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(L); fn(d)
    if blur: L = L.filter(ImageFilter.GaussianBlur(blur))
    img.alpha_composite(L)
def sun(img, x, y, r, col, glow=3.0):
    def f(d):
        for k in range(12, 0, -1):
            rr = r * (1 + k * glow / 12); a = int(255 * 0.05 * (13 - k) / 12)
            d.ellipse((x - rr, y - rr, x + rr, y + rr), fill=tuple(col) + (a,))
        d.ellipse((x - r, y - r, x + r, y + r), fill=tuple(col) + (255,))
    shapes(img, f, 2)
def water(img, y0, col):
    a = np.array(img).astype(float)
    refl = a[max(0, 2 * y0 - H):y0][::-1]
    h = min(H - y0, len(refl))
    a[y0:y0 + h, :, :3] = a[y0:y0 + h, :, :3] * 0.15 + refl[:h, :, :3] * 0.55 + np.array(col) * 0.3
    for k in range(0, h, 6): a[y0 + k, :, :3] *= 1.06
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), 'RGBA')
def base(top, bot, hz=0.75): return to_img(grad(top, bot, hz)).convert('RGBA')
def stars(img, n, a=200):
    def f(d):
        for _ in range(n):
            x, y = rg.uniform(0, W), rg.uniform(0, H * 0.55); s = rg.uniform(0.6, 1.8)
            d.ellipse((x - s, y - s, x + s, y + s), fill=(255, 255, 240, int(a * rg.uniform(0.3, 1))))
    shapes(img, f)
P = {}
def fuji():
    im = base((250, 170, 140), (255, 225, 190)); sun(im, 980, 210, 50, (255, 240, 210))
    layer(im, ridge(470, 30, 0.5, 1), (150, 120, 150), 3)
    layer(im, [(250, 520), (560, 200), (600, 190), (640, 200), (960, 520)], (95, 95, 140), 1)
    layer(im, [(470, 290), (560, 200), (600, 190), (640, 200), (730, 290), (690, 275), (650, 300), (610, 270), (575, 300), (530, 275)], (250, 248, 255), 1)
    layer(im, ridge(560, 20, 0.5, 2), (70, 90, 80), 1)
    im = water(im, 560, (120, 130, 170))
    def trees(d):
        for x in (60, 170, 1110, 1220):
            d.rectangle((x - 6, 420, x + 6, 600), fill=(70, 40, 40, 255))
            for _ in range(40):
                a, r = rg.uniform(0, 2 * math.pi), rg.uniform(0, 90); px, py = x + r * math.cos(a) * 1.3, 380 + r * math.sin(a) * 0.7
                d.ellipse((px - 18, py - 14, px + 18, py + 14), fill=(250, 180, 200, 230))
    shapes(im, trees, 1); return im
def guilin():
    im = base((170, 200, 205), (225, 235, 225))
    for k, (col, base_y, sc) in enumerate([((150, 175, 165), 470, 0.7), ((100, 140, 120), 520, 0.85), ((50, 90, 70), 580, 1.0)]):
        def f(d, col=col, by=base_y, sc=sc, k=k):
            r = np.random.default_rng(10 + k)
            for _ in range(7):
                x = r.uniform(0, W); w = r.uniform(70, 150) * sc; h = r.uniform(180, 330) * sc
                d.ellipse((x - w / 2, by - h, x + w / 2, by + h * 0.3), fill=tuple(col) + (255,))
        shapes(im, f, 3 - k)
    im = water(im, 590, (110, 150, 140)); return im
def emerald():
    im = base((80, 140, 220), (200, 225, 245)); sun(im, 200, 150, 40, (255, 250, 230))
    def f(d):
        for x, h, w in ((640, 380, 120), (440, 280, 90), (840, 280, 90), (300, 200, 70), (980, 200, 70)):
            d.polygon([(x - w, 600), (x - w * 0.6, 600 - h * 0.45), (x - w * 0.15, 600 - h * 0.9), (x, 600 - h - 80), (x + w * 0.15, 600 - h * 0.9), (x + w * 0.6, 600 - h * 0.45), (x + w, 600)], fill=(225, 180, 60, 255))
            for k in range(6): yy = 600 - h * k / 7; d.line((x - w * (1 - k / 7), yy, x + w * (1 - k / 7), yy), fill=(170, 120, 30, 255), width=4)
        d.rectangle((0, 600, W, H), fill=(120, 60, 45, 255))
        for x in range(0, W, 80): d.rectangle((x, 590, x + 60, 610), fill=(60, 140, 90, 255))
    shapes(im, f, 1); return im
def angkor():
    im = base((240, 120, 80), (255, 200, 120)); sun(im, 640, 420, 70, (255, 230, 160))
    def f(d):
        for x, h, w in ((640, 330, 70), (480, 250, 55), (800, 250, 55), (340, 190, 45), (940, 190, 45)):
            pts = []
            for k in range(9):
                yy = 520 - h * k / 8; ww = w * (1 - (k / 9) ** 1.6)
                pts.append((x - ww, yy))
            pts += [(x, 520 - h - 40)] + [(2 * x - p[0], p[1]) for p in reversed(pts)]
            d.polygon(pts, fill=(80, 55, 60, 255))
        d.rectangle((150, 470, 1130, 520), fill=(70, 48, 52, 255))
    shapes(im, f, 1)
    layer(im, ridge(540, 10, 0.5, 4), (40, 60, 40), 1)
    im = water(im, 560, (200, 120, 90)); return im
def ayers():
    im = base((40, 90, 190), (240, 170, 110), 0.8)
    def f(d):
        d.pieslice((260, 300, 1020, 760), 180, 360, fill=(190, 75, 35, 255))
        for k in range(10): x = 320 + k * 70; d.line((x, 520, x + 30, 380 + abs(k - 5) * 15), fill=(150, 55, 25, 255), width=6)
        d.rectangle((0, 530, W, H), fill=(210, 120, 60, 255))
        for _ in range(60): x, y = rg.uniform(0, W), rg.uniform(560, H); d.ellipse((x - 14, y - 6, x + 14, y + 6), fill=(110, 120, 50, 255))
    shapes(im, f, 1); return im
def taj():
    im = base((175, 200, 230), (245, 230, 215)); sun(im, 1050, 160, 35, (255, 255, 240))
    def f(d):
        c = (245, 243, 238, 255)
        d.rectangle((420, 330, 860, 560), fill=c); d.ellipse((520, 170, 760, 400), fill=c); d.polygon([(640, 120), (625, 190), (655, 190)], fill=c)
        for x in (480, 800): d.ellipse((x - 40, 270, x + 40, 350), fill=c)
        for x in (330, 950):
            d.rectangle((x - 14, 220, x + 14, 560), fill=c); d.ellipse((x - 24, 195, x + 24, 240), fill=c)
        d.rectangle((560, 410, 720, 560), fill=(205, 205, 215, 255)); d.ellipse((560, 360, 720, 470), fill=(205, 205, 215, 255))
        d.rectangle((0, 560, W, H), fill=(110, 140, 90, 255))
    shapes(im, f, 1)
    im = water(im, 600, (150, 175, 200)); return im
def leningrad():
    im = base((140, 160, 190), (215, 220, 230))
    def f(d):
        for x, h, col in ((640, 360, (60, 140, 90)), (500, 260, (200, 60, 60)), (780, 260, (230, 180, 60)), (380, 200, (60, 90, 170)), (900, 200, (60, 140, 90))):
            d.rectangle((x - 45, 600 - h, x + 45, 600), fill=(225, 205, 180, 255))
            d.ellipse((x - 70, 600 - h - 110, x + 70, 600 - h + 20), fill=tuple(col) + (255,))
            d.polygon([(x - 40, 600 - h - 90), (x, 600 - h - 190), (x + 40, 600 - h - 90)], fill=tuple(col) + (255,))
            for k in range(-2, 3): d.line((x + k * 25, 600 - h - 100, x + k * 22, 600 - h + 10), fill=(250, 250, 250, 255), width=5)
        d.rectangle((0, 600, W, H), fill=(235, 238, 245, 255))
        for _ in range(250): x, y = rg.uniform(0, W), rg.uniform(0, H); d.ellipse((x - 2, y - 2, x + 2, y + 2), fill=(255, 255, 255, 200))
    shapes(im, f, 1); return im
def paris():
    im = base((60, 70, 130), (240, 160, 130)); stars(im, 60)
    def f(d):
        c = (55, 45, 60, 255)
        d.polygon([(470, 640), (590, 330), (620, 120), (640, 40), (660, 120), (690, 330), (810, 640), (740, 640), (640, 470), (540, 640)], fill=c)
        d.rectangle((540, 330, 740, 345), fill=c); d.rectangle((600, 200, 680, 210), fill=c)
        d.rectangle((0, 610, W, H), fill=(45, 40, 55, 255))
        for _ in range(30): x = rg.uniform(0, W); hh = rg.uniform(40, 110); d.rectangle((x, 640 - hh, x + 70, 640), fill=(70, 60, 80, 255))
    shapes(im, f, 1); return im
def london():
    im = base((120, 125, 140), (200, 195, 190))
    def f(d):
        c = (75, 70, 75, 255)
        d.rectangle((560, 150, 640, 620), fill=c); d.polygon([(560, 150), (600, 40), (640, 150)], fill=c)
        d.ellipse((568, 180, 632, 244), fill=(240, 230, 190, 255)); d.line((600, 212, 600, 188), fill=c, width=4); d.line((600, 212, 618, 212), fill=c, width=4)
        d.rectangle((640, 400, 1150, 620), fill=c)
        for x in range(660, 1150, 40): d.polygon([(x, 400), (x + 10, 360), (x + 20, 400)], fill=c)
        d.rectangle((0, 620, W, H), fill=(80, 90, 110, 255))
    shapes(im, f, 1)
    im = water(im, 640, (90, 100, 120)); return im
def barcelona():
    im = base((90, 160, 230), (250, 215, 170)); sun(im, 1080, 180, 40, (255, 245, 210))
    def f(d):
        c = (180, 140, 100, 255)
        for x, h in ((470, 380), (540, 450), (610, 480), (680, 480), (750, 450), (820, 380)):
            d.polygon([(x - 30, 620), (x - 22, 620 - h * 0.7), (x, 620 - h), (x + 22, 620 - h * 0.7), (x + 30, 620)], fill=c)
            for k in range(8): d.ellipse((x - 6, 620 - h * 0.7 + k * 30, x + 6, 632 - h * 0.7 + k * 30), fill=(140, 100, 70, 255))
        d.rectangle((420, 520, 870, 620), fill=c)
        d.rectangle((0, 620, W, H), fill=(200, 170, 130, 255))
    shapes(im, f, 1); return im
def athens():
    im = base((80, 150, 220), (225, 230, 240))
    def f(d):
        d.polygon([(0, 560), (300, 470), (980, 470), (W, 560), (W, H), (0, H)], fill=(170, 150, 120, 255))
        c = (235, 225, 205, 255)
        d.rectangle((380, 455, 900, 475), fill=c); d.polygon([(370, 300), (640, 230), (910, 300)], fill=c); d.rectangle((370, 300, 910, 320), fill=c)
        for k in range(10): x = 400 + k * 53; d.rectangle((x, 320, x + 26, 455), fill=c)
    shapes(im, f, 1); return im
def egypt():
    im = base((240, 180, 110), (255, 230, 170)); sun(im, 300, 220, 55, (255, 245, 200))
    def f(d):
        for x, h, w, col in ((780, 330, 330, (215, 165, 95)), (470, 250, 250, (200, 150, 85)), (1060, 190, 190, (205, 155, 90))):
            d.polygon([(x - w, 580), (x, 580 - h), (x + w, 580)], fill=tuple(col) + (255,))
            d.polygon([(x, 580 - h), (x + w, 580), (x + w * 0.4, 580)], fill=tuple(int(v * 0.8) for v in col) + (255,))
        d.rectangle((0, 575, W, H), fill=(230, 190, 120, 255))
        d.rectangle((140, 520, 330, 580), fill=(190, 145, 85, 255)); d.ellipse((120, 470, 200, 545), fill=(190, 145, 85, 255))
    shapes(im, f, 1); return im
def kenya():
    im = base((250, 140, 70), (255, 210, 120)); sun(im, 640, 400, 90, (255, 235, 150), 2)
    layer(im, [(300, 420), (560, 270), (720, 270), (980, 420)], (150, 110, 120), 2)
    layer(im, [(520, 300), (560, 270), (720, 270), (760, 300)], (245, 240, 240), 1)
    def f(d):
        d.rectangle((0, 470, W, H), fill=(170, 120, 50, 255))
        for x, s in ((200, 1.2), (950, 1.0), (1150, 0.7)):
            d.line((x, 470, x, 470 - 120 * s), fill=(50, 35, 30, 255), width=int(10 * s))
            d.ellipse((x - 120 * s, 470 - 160 * s, x + 120 * s, 470 - 110 * s), fill=(55, 45, 30, 255))
        for x in (420, 470, 760): d.rectangle((x, 400, x + 10, 470), fill=(60, 45, 30, 255)); d.ellipse((x - 20, 380, x + 40, 410), fill=(60, 45, 30, 255))
    shapes(im, f, 1); return im
def newyork():
    im = base((20, 25, 60), (90, 70, 110)); stars(im, 150)
    def f(d):
        r = np.random.default_rng(14)
        for x in range(0, W, 46):
            h = r.uniform(120, 330); d.rectangle((x, 620 - h, x + 42, 620), fill=(35, 35, 55, 255))
            for yy in range(int(630 - h), 610, 14):
                for xx in range(x + 5, x + 38, 10):
                    if r.random() < 0.35: d.rectangle((xx, yy, xx + 5, yy + 7), fill=(255, 210, 140, 255))
        d.rectangle((610, 160, 670, 620), fill=(45, 45, 65, 255)); d.rectangle((625, 90, 655, 160), fill=(45, 45, 65, 255)); d.line((640, 30, 640, 90), fill=(45, 45, 65, 255), width=6)
    shapes(im, f, 0)
    im = water(im, 640, (30, 30, 60)); return im
def maya():
    im = base((110, 170, 210), (220, 235, 220))
    layer(im, ridge(500, 40, 0.5, 9), (40, 110, 60), 2)
    def f(d):
        c = (165, 160, 140, 255)
        for k in range(8):
            w = 420 - k * 45; y = 600 - k * 45; d.rectangle((640 - w, y - 45, 640 + w, y), fill=(165 - k * 4, 160 - k * 4, 140 - k * 4, 255))
        d.rectangle((590, 200, 690, 240), fill=(150, 140, 120, 255)); d.rectangle((610, 450, 670, 600), fill=(130, 125, 110, 255))
        d.rectangle((0, 600, W, H), fill=(60, 120, 60, 255))
    shapes(im, f, 1); return im
def antarctica():
    im = base((120, 160, 210), (230, 240, 250))
    def f(d):
        d.polygon([(100, 600), (260, 360), (380, 400), (520, 600)], fill=(235, 245, 255, 255)); d.polygon([(260, 360), (380, 400), (420, 600), (300, 600)], fill=(190, 215, 240, 255))
        d.polygon([(760, 600), (900, 300), (1080, 380), (1200, 600)], fill=(240, 248, 255, 255)); d.polygon([(900, 300), (1080, 380), (1050, 600), (950, 600)], fill=(185, 210, 238, 255))
        for x in (560, 600, 640):
            d.ellipse((x, 560, x + 30, 620), fill=(30, 30, 40, 255)); d.ellipse((x + 6, 572, x + 24, 615), fill=(250, 250, 250, 255)); d.ellipse((x + 5, 540, x + 25, 565), fill=(30, 30, 40, 255))
    shapes(im, f, 1)
    im = water(im, 610, (60, 100, 150)); return im
def easter():
    im = base((240, 150, 120), (255, 215, 170)); sun(im, 1000, 380, 60, (255, 230, 170))
    im = water(im, 470, (150, 110, 140))
    def f(d):
        d.polygon([(0, 520), (300, 470), (900, 480), (W, 530), (W, H), (0, H)], fill=(70, 100, 60, 255))
        for x, s in ((260, 1.0), (430, 1.15), (620, 1.25), (820, 1.1), (990, 0.95)):
            c = (85, 75, 70, 255)
            d.rectangle((x - 45 * s, 520 - 240 * s, x + 45 * s, 520), fill=c)
            d.rectangle((x - 55 * s, 520 - 270 * s, x + 30 * s, 520 - 200 * s), fill=c)
            d.polygon([(x + 30 * s, 520 - 200 * s), (x + 62 * s, 520 - 150 * s), (x + 40 * s, 520 - 130 * s)], fill=c)
            d.rectangle((x - 30 * s, 520 - 285 * s, x + 25 * s, 520 - 268 * s), fill=(150, 70, 50, 255))
    shapes(im, f, 1); return im
LOCS = [('fuji', fuji), ('guilin', guilin), ('emerald', emerald), ('angkor', angkor), ('ayers', ayers), ('taj', taj), ('leningrad', leningrad),
        ('paris', paris), ('london', london), ('barcelona', barcelona), ('athens', athens), ('egypt', egypt), ('kenya', kenya), ('newyork', newyork),
        ('maya', maya), ('antarctica', antarctica), ('easter', easter)]
for nm, fn in LOCS:
    im = fn().convert('RGB')
    a = np.asarray(im).astype(float) + rg.normal(0, 2.5, (H, W, 3))       # subtle painted grain
    to_img(a).save(os.path.join(T, 'bg_' + nm + '.png'))
# stone frame + floor textures
n = 256; g = np.zeros((n, n))
for o in range(5):
    f = 4 * 2 ** o; s = rg.random((f, f)); g += np.asarray(Image.fromarray((s * 255).astype(np.uint8)).resize((n, n), Image.BICUBIC)) / 255 / 2 ** o
g /= g.max()
st = np.stack([150 + 90 * g] * 3, -1); st[::32, :] *= 0.55; st[:, ::64] *= 0.55
to_img(st).save(os.path.join(T, 'stone.png'))
# soft daylight skybox (IBL)
HW, HH = 512, 256
v = (np.arange(HH) + 0.5) / HH
y = np.sin((0.5 - v) * np.pi)[:, None] * np.ones((1, HW))
t = np.clip(y, 0, 1)[..., None]
sky = np.array([0.9, 0.85, 0.8]) * (1 - t) + np.array([0.35, 0.5, 0.8]) * t
sky[y < 0] = np.array([0.3, 0.27, 0.24])
def rgbe(a):
    m = a.max(-1); e = np.ceil(np.log2(np.maximum(m, 1e-32))); sc = np.where(m > 1e-32, 256.0 / 2 ** e, 0)
    o = np.zeros(a.shape[:2] + (4,), np.uint8); o[..., :3] = np.clip(a * sc[..., None], 0, 255).astype(np.uint8)
    o[..., 3] = np.where(m > 1e-32, e + 128, 0).astype(np.uint8); return o
with open(os.path.join(SK, 'day.hdr'), 'wb') as f:
    f.write(b"#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y %d +X %d\n" % (HH, HW)); f.write(rgbe(sky.astype(np.float32)).tobytes())

# ------------------------------------------------------------------ audio
def sweep(f0, f1, d, duty=0.5):
    f = f0 + (f1 - f0) * tt(d) / d; return np.where((np.cumsum(f) / SR) % 1 < duty, 1.0, -1.0)
save('shoot.wav', env(sweep(400, 1400, 0.16, 0.3) * np.exp(-tt(0.16) * 8)), 0.3)
save('vulcan.wav', env(sq(900, 0.05, 0.3) * np.exp(-tt(0.05) * 50)), 0.22)
for i, (f, d) in enumerate(((900, 0.12), (650, 0.16), (450, 0.2), (300, 0.26)), 1):
    nz = rng.standard_normal(int(SR * d)); save(f'pop{i}.wav', env(sweep(f, f * 0.4, d) * 0.6 + nz * 0.5) * np.exp(-tt(d) * 10), 0.42)
save('walk.wav', env(tri(180, 0.04) * np.exp(-tt(0.04) * 60) + rng.standard_normal(int(SR * 0.04)) * 0.2 * np.exp(-tt(0.04) * 90)), 0.2)
save('climb.wav', env(sq(500, 0.035, 0.25) * np.exp(-tt(0.035) * 60)), 0.16)
save('item.wav', melody([('E6', 0.25), ('G6', 0.25), ('C7', 0.5)], 420, 'sq', 0.25), 0.3)
save('weapon.wav', melody([('C5', 0.25), ('G5', 0.25), ('C6', 0.25), ('E6', 0.25), ('G6', 0.5)], 480, 'sq', 0.25), 0.3)
save('freeze.wav', mix(*[env(sq(hz(n), 0.5, 0.25)) * np.exp(-tt(0.5) * 4) for n in ('C6', 'G6')]), 0.25)
nz = rng.standard_normal(int(SR * 0.8)); save('boom.wav', np.convolve(nz, np.ones(40) / 40, 'same') * np.exp(-tt(0.8) * 4) + tri(50, 0.8) * np.exp(-tt(0.8) * 5), 0.6)
nz = rng.standard_normal(int(SR * 0.25)); save('break.wav', (nz * 0.6 + sq(1800, 0.25, 0.3) * 0.3) * np.exp(-tt(0.25) * 14), 0.4)
save('death.wav', mix(melody([('G5', 0.5), ('F#5', 0.5), ('F5', 0.5), ('E5', 0.5), ('D#5', 0.5), ('D5', 1), ('-', 0.5), ('C4', 0.5), ('C3', 1.5)], 300, 'sq', 0.5)), 0.32)
save('clear.wav', mix(melody([('C5', 0.5), ('E5', 0.5), ('G5', 0.5), ('C6', 1), ('G5', 0.5), ('C6', 2)], 260, 'sq', 0.25),
                      melody([('C3', 1), ('G3', 1), ('F3', 1), ('C3', 2)], 260, 'tri')), 0.32)
save('ready.wav', melody([('G5', 0.5), ('C6', 0.5), ('E6', 0.5), ('G6', 1)], 300, 'sq', 0.25), 0.3)
save('gameover.wav', mix(melody([('C5', 1), ('G4', 1), ('E4', 1), ('A4', 0.7), ('B4', 0.7), ('A4', 0.7), ('G#4', 1), ('A#4', 1), ('G#4', 1), ('G4', 3)], 220, 'sq', 0.5)), 0.3)
save('click.wav', env(sq(1200, 0.04, 0.3) * np.exp(-tt(0.04) * 60)), 0.25)
save('life.wav', melody([('G5', 0.25), ('C6', 0.25), ('E6', 0.25), ('G6', 0.25), ('C7', 1)], 360, 'sq', 0.25), 0.3)
save('warn.wav', env(sq(880, 0.12, 0.5)), 0.22)
save('animal.wav', env(sweep(1200, 300, 0.25, 0.4) * np.exp(-tt(0.25) * 6)), 0.3)
# body hitting the floor after the death arc (separate from the walk sound)
save('thud.wav', env(sweep(160, 50, 0.18, 0.5) * np.exp(-tt(0.18) * 18) + 0.3 * np.random.default_rng(3).uniform(-1, 1, len(tt(0.18))) * np.exp(-tt(0.18) * 40)), 0.35)
save('shield.wav', env(sweep(300, 900, 0.3, 0.5) * np.exp(-tt(0.3) * 5)), 0.3)
def loop(bass, lead, bpm, nm, vol=0.26):
    b = melody(bass, bpm, 'tri'); l = melody(lead, bpm, 'sq', 0.25) if lead else np.zeros(1)
    save(nm, mix(b, l * 0.45), vol)
loop([('C3', 0.5), ('G3', 0.5), ('E3', 0.5), ('G3', 0.5)] * 4, [('E5', 0.5), ('G5', 0.5), ('A5', 1), ('G5', 0.5), ('E5', 0.5), ('D5', 1), ('C5', 0.5), ('D5', 0.5), ('E5', 1), ('D5', 2)], 200, 'bgm1.wav')
loop([('A2', 0.5), ('E3', 0.5), ('A2', 0.5), ('E3', 0.5), ('F2', 0.5), ('C3', 0.5), ('G2', 0.5), ('D3', 0.5)] * 2, [('A4', 1), ('C5', 1), ('E5', 1), ('D5', 1), ('C5', 1), ('B4', 1), ('C5', 2)], 210, 'bgm2.wav')
loop([('D3', 0.5), ('A3', 0.5), ('F3', 0.5), ('A3', 0.5)] * 2 + [('G2', 0.5), ('D3', 0.5), ('A#2', 0.5), ('D3', 0.5)] * 2, [('D5', 0.5), ('F5', 0.5), ('A5', 1), ('G5', 1), ('F5', 0.5), ('E5', 0.5), ('D5', 2), ('A#4', 1), ('C5', 1)], 220, 'bgm3.wav')
loop([('E3', 0.5), ('B3', 0.5), ('G3', 0.5), ('B3', 0.5)] * 2 + [('C3', 0.5), ('G3', 0.5), ('D3', 0.5), ('A3', 0.5)] * 2, [('B4', 0.5), ('E5', 0.5), ('G5', 1), ('F#5', 1), ('E5', 1), ('D5', 0.5), ('E5', 0.5), ('B4', 2)], 230, 'bgm4.wav')
loop([('C3', 1), ('A2', 1), ('F2', 1), ('G2', 1)] * 2, [('E5', 1), ('C5', 1), ('A4', 1), ('B4', 1), ('C5', 1), ('E5', 1), ('D5', 2)], 160, 'title.wav')
print('assets ok')
