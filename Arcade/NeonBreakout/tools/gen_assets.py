# Procedural assets for Neon Breakout: HDR skybox (IBL reflections), backdrop texture, WAV sfx.
import numpy as np, os, wave
from PIL import Image, ImageDraw, ImageFilter
A = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'project', 'Assets')
rng = np.random.default_rng(11)

# ---------- skybox: dark synthwave studio (soft neon panels give glossy bricks nice highlights)
W, H = 512, 256
v = (np.arange(H) + .5) / H; u = (np.arange(W) + .5) / W
EL, AZ = np.meshgrid((0.5 - v) * np.pi, (u - 0.5) * 2 * np.pi, indexing='ij')
x = np.cos(EL) * np.cos(AZ); z = np.cos(EL) * np.sin(AZ); y = np.sin(EL)
img = np.zeros((H, W, 3)) + np.array([0.004, 0.004, 0.012])
img += np.clip(-y, 0, 1)[..., None] * np.array([0.01, 0.002, 0.02])
def panel(dirv, size, col, soft=0.02):
    d = np.array(dirv, float); d /= np.linalg.norm(d)
    dot = x * d[0] + y * d[1] + z * d[2]; ang = np.arccos(np.clip(dot, -1, 1))
    global img
    img += (np.clip((size - ang) / soft, 0, 1))[..., None] * np.array(col)
    img += np.exp(-ang / (size * 2))[..., None] * np.array(col) * 0.03
panel((0, 0.9, 0.4), 0.35, (1.2, 1.1, 1.3))        # big soft key overhead/front
panel((-0.9, 0.3, 0.3), 0.22, (0.1, 0.8, 1.6))     # cyan strip left
panel((0.9, 0.3, 0.3), 0.22, (1.6, 0.2, 1.0))      # magenta strip right
panel((0, -0.2, 1.0), 0.9, (0.012, 0.006, 0.03), soft=0.8)  # very soft violet fill behind camera
def rgbe(a):
    m = a.max(-1); e = np.ceil(np.log2(np.maximum(m, 1e-32))); sc = np.where(m > 1e-32, 256.0 / 2 ** e, 0)
    out = np.zeros(a.shape[:2] + (4,), np.uint8)
    out[..., :3] = np.clip(a * sc[..., None], 0, 255).astype(np.uint8); out[..., 3] = np.where(m > 1e-32, e + 128, 0).astype(np.uint8); return out
with open(f'{A}/Skybox/neon.hdr', 'wb') as f:
    f.write(b"#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y %d +X %d\n" % (H, W)); f.write(rgbe(img.astype(np.float32)).tobytes())

# ---------- backdrop: deep gradient + perspective neon grid + soft nebula + stars
BW, BH = 1600, 1000
yy, xx = np.mgrid[0:BH, 0:BW] / np.array([BH, BW])[:, None, None]
bg = np.zeros((BH, BW, 3))
bg += (1 - yy)[..., None] * np.array([0.02, 0.01, 0.07]) + yy[..., None] * np.array([0.09, 0.01, 0.10])
for cx, cy, r, c in ((0.25, 0.3, 0.35, (0.05, 0.12, 0.30)), (0.75, 0.35, 0.3, (0.30, 0.04, 0.22)), (0.5, 0.9, 0.4, (0.25, 0.05, 0.3))):
    d2 = ((xx - cx) ** 2 + (yy - cy) ** 2) / r ** 2
    bg += np.exp(-d2 * 2)[..., None] * np.array(c)
n = rng.random((BH // 40, BW // 40)); n = np.array(Image.fromarray((n * 255).astype(np.uint8)).resize((BW, BH), Image.BICUBIC).filter(ImageFilter.GaussianBlur(30)), float); n = (n - n.min()) / (n.max() - n.min() + 1e-6)
bg *= (0.7 + 0.6 * n)[..., None]
im = Image.fromarray((np.clip(bg, 0, 1) ** (1 / 1.2) * 255).astype(np.uint8))
g = Image.new('RGB', (BW, BH)); dg = ImageDraw.Draw(g)
hor = int(BH * 0.62)
for i in range(-30, 31):        # converging floor lines
    dg.line([(BW / 2 + i * 18, hor), (BW / 2 + i * 260, BH)], fill=(200, 40, 255), width=2)
k = 0
while True:                     # horizontal floor lines, denser toward horizon
    yv = hor + (BH - hor) * (k / 14) ** 2.2; k += 1
    if yv > BH: break
    dg.line([(0, yv), (BW, yv)], fill=(255, 50, 200), width=2)
dg.line([(0, hor), (BW, hor)], fill=(255, 120, 255), width=3)
for i in range(0, BW, 64): dg.line([(i, 0), (i, hor)], fill=(25, 40, 110), width=1)
for j in range(0, hor, 64): dg.line([(0, j), (BW, j)], fill=(25, 40, 110), width=1)
glow = g.filter(ImageFilter.GaussianBlur(6))
im = Image.fromarray(np.clip(np.array(im, float) + np.array(g, float) * 0.55 + np.array(glow, float) * 1.4, 0, 255).astype(np.uint8))
d = ImageDraw.Draw(im)
for _ in range(500):
    sx, sy = rng.integers(0, BW), rng.integers(0, hor - 10); b = int(rng.power(0.2) * 200) + 40
    d.point((sx, sy), fill=(b, b, min(255, b + 40)))
# sun disc on the horizon
sun = Image.new('L', (BW, BH)); ds = ImageDraw.Draw(sun); ds.ellipse([BW/2-170, hor-300, BW/2+170, hor+40], fill=255)
for j in range(8): ds.rectangle([0, hor - 120 + j * 16, BW, hor - 120 + j * 16 + 3 + j], fill=0)
ds.rectangle([0, hor, BW, BH], fill=0)
sunc = np.zeros((BH, BW, 3)); t = np.clip((yy - (hor - 300) / BH) / (300 / BH), 0, 1)
sunc[:] = (1 - t)[..., None] * np.array([255, 220, 90]) + t[..., None] * np.array([255, 40, 160])
a = np.array(sun.filter(ImageFilter.GaussianBlur(1.5)), float)[..., None] / 255 * 0.55
im = Image.fromarray(np.clip(np.array(im, float) * (1 - a) + sunc * a, 0, 255).astype(np.uint8))
im.save(f'{A}/Textures/backdrop.png')

# ---------- sfx
SR = 44100
def wav(name, s):
    s = np.clip(s, -1, 1); w = wave.open(f'{A}/Audio/{name}.wav', 'wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((s * 32000).astype(np.int16).tobytes()); w.close()
def tt(d): return np.arange(int(SR * d)) / SR
def env(t, a, d): return np.minimum(t / a, 1) * np.exp(-t / d)
def tone(f, d, dec, shape='sine', a=0.002):
    t = tt(d); ph = 2 * np.pi * np.cumsum(np.broadcast_to(f(t) if callable(f) else f, t.shape)) / SR
    w = np.sin(ph) if shape == 'sine' else (np.sign(np.sin(ph)) * 0.6 if shape == 'sq' else 2 * (ph / (2 * np.pi) % 1) - 1)
    return w * env(t, a, dec)
NOTES = [523.25, 587.33, 659.25, 783.99, 880.0, 1046.5, 1174.7, 1318.5]
for i, f in enumerate(NOTES):   # brick hit, pitched per row (low rows low)
    s = tone(f, 0.25, 0.06, 'sq') * 0.35 + tone(f * 2, 0.25, 0.04) * 0.3 + tone(f * 1.5, 0.25, 0.08) * 0.2
    wav(f'brick{i}', s)
wav('paddle', tone(lambda t: 220 + 200 * np.exp(-t * 40), 0.18, 0.05, 'sq') * 0.4 + tone(110, 0.18, 0.06) * 0.5)
wav('wall', tone(lambda t: 330 + 0 * t, 0.1, 0.025, 'sq') * 0.25)
nz = rng.standard_normal(int(SR * 0.6))
t = tt(0.6); wav('shatter', nz * env(t, 0.001, 0.08) * 0.5 + tone(lambda t: 900 * np.exp(-t * 6) + 80, 0.6, 0.12, 'saw') * 0.25)
t = tt(1.2); wav('lose', tone(lambda t: 440 * np.exp(-t * 1.6), 1.2, 0.5, 'saw') * 0.4 + np.random.default_rng(2).standard_normal(len(t)) * env(t, 0.01, 0.3) * 0.2)
wav('powerup', np.concatenate([tone(f, 0.07, 0.05, 'sq') * 0.3 for f in (523, 659, 784, 1047, 1319)]))
wav('laser', tone(lambda t: 1800 * np.exp(-t * 18) + 200, 0.15, 0.06, 'saw') * 0.3)
wav('steel', tone(1500, 0.3, 0.08) * 0.3 + tone(2250, 0.3, 0.05) * 0.2 + tone(3370, 0.3, 0.03) * 0.15)
wav('clear', np.concatenate([tone(f, 0.12, 0.1, 'sq') * 0.3 + tone(f / 2, 0.12, 0.1) * 0.3 for f in (523, 659, 784, 1047, 784, 1047, 1319, 1568)]))
wav('launch', tone(lambda t: 300 + 900 * t, 0.25, 0.15, 'sq') * 0.25)
wav('click', tone(1200, 0.05, 0.012) * 0.4)
wav('speedup', tone(lambda t: 600 + 1200 * t, 0.3, 0.2, 'saw') * 0.2)
wav('shrink', tone(lambda t: 900 - 1300 * t, 0.4, 0.25, 'sq') * 0.25)
wav('gameover', np.concatenate([tone(f, 0.3, 0.25, 'sq') * 0.3 for f in (392, 330, 262, 196)]))
print('assets ok')

# ---------- playfield back plate: dark glass with a faint hex grid and soft centre glow
PW, PH = 1024, 1024
pf = Image.new('RGB', (PW, PH), (0, 0, 0)); dp = ImageDraw.Draw(pf)
R = 34; hh = R * np.sqrt(3)
for j in range(-1, int(PH / hh) + 2):
    for i in range(-1, int(PW / (1.5 * R)) + 2):
        cx = i * 1.5 * R; cy = j * hh + (hh / 2 if i % 2 else 0)
        pts = [(cx + R * np.cos(a), cy + R * np.sin(a)) for a in np.linspace(0, 2 * np.pi, 7)]
        dp.line(pts, fill=(40, 60, 140), width=2)
yy2, xx2 = np.mgrid[0:PH, 0:PW] / PH
glow2 = np.exp(-((xx2 - 0.5) ** 2 + (yy2 - 0.45) ** 2) * 4)[..., None]
arr = np.array(pf, float) * (0.35 + 0.9 * glow2) + glow2 * np.array([10, 6, 30])
arr += np.array(pf.filter(ImageFilter.GaussianBlur(4)), float) * 0.6 * glow2
Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)).save(f'{A}/Textures/playfield.png')
print('playfield ok')
