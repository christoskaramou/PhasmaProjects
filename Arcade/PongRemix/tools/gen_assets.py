# Procedural assets for Pong Remix: HDR skybox, arena textures, WAV sfx.
import numpy as np, os, wave
from PIL import Image, ImageDraw, ImageFilter
A = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'project', 'Assets')
os.makedirs(f'{A}/Skybox', exist_ok=True)
os.makedirs(f'{A}/Textures', exist_ok=True)
os.makedirs(f'{A}/Audio', exist_ok=True)
rng = np.random.default_rng(42)

# ---------- skybox: soft studio (cool key + warm fill) — elegant, not neon hype
W, H = 512, 256
v = (np.arange(H) + .5) / H; u = (np.arange(W) + .5) / W
EL, AZ = np.meshgrid((0.5 - v) * np.pi, (u - 0.5) * 2 * np.pi, indexing='ij')
x = np.cos(EL) * np.cos(AZ); z = np.cos(EL) * np.sin(AZ); y = np.sin(EL)
img = np.zeros((H, W, 3)) + np.array([0.012, 0.014, 0.022])
img += np.clip(-y, 0, 1)[..., None] * np.array([0.02, 0.018, 0.03])
img += np.clip(y, 0, 1)[..., None] * np.array([0.04, 0.05, 0.07])
def panel(dirv, size, col, soft=0.03):
    d = np.array(dirv, float); d /= np.linalg.norm(d)
    dot = x * d[0] + y * d[1] + z * d[2]; ang = np.arccos(np.clip(dot, -1, 1))
    global img
    img += (np.clip((size - ang) / soft, 0, 1))[..., None] * np.array(col)
    img += np.exp(-ang / (size * 2.2))[..., None] * np.array(col) * 0.04
panel((0.1, 0.85, 0.35), 0.40, (1.4, 1.35, 1.5))       # soft key overhead
panel((-0.85, 0.25, 0.4), 0.20, (0.25, 0.75, 1.3))     # cool strip left
panel((0.85, 0.25, 0.4), 0.20, (1.2, 0.45, 0.35))      # warm strip right
panel((0, -0.15, 1.0), 0.85, (0.02, 0.03, 0.05), soft=0.7)
def rgbe(a):
    m = a.max(-1); e = np.ceil(np.log2(np.maximum(m, 1e-32))); sc = np.where(m > 1e-32, 256.0 / 2 ** e, 0)
    out = np.zeros(a.shape[:2] + (4,), np.uint8)
    out[..., :3] = np.clip(a * sc[..., None], 0, 255).astype(np.uint8)
    out[..., 3] = np.where(m > 1e-32, e + 128, 0).astype(np.uint8); return out
with open(f'{A}/Skybox/studio.hdr', 'wb') as f:
    f.write(b"#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y %d +X %d\n" % (H, W))
    f.write(rgbe(img.astype(np.float32)).tobytes())
print('skybox ok')

# ---------- backdrop: deep charcoal gradient + subtle grid + soft vignette
BW, BH = 1600, 1000
yy, xx = np.mgrid[0:BH, 0:BW] / np.array([BH, BW])[:, None, None]
bg = np.zeros((BH, BW, 3))
bg += (1 - yy)[..., None] * np.array([0.04, 0.05, 0.09]) + yy[..., None] * np.array([0.08, 0.06, 0.10])
for cx, cy, r, c in ((0.2, 0.35, 0.4, (0.04, 0.10, 0.22)), (0.8, 0.4, 0.35, (0.22, 0.06, 0.05)),
                     (0.5, 0.7, 0.45, (0.06, 0.05, 0.12))):
    d2 = ((xx - cx) ** 2 + (yy - cy) ** 2) / r ** 2
    bg += np.exp(-d2 * 2.2)[..., None] * np.array(c)
n = rng.random((BH // 32, BW // 32))
n = np.array(Image.fromarray((n * 255).astype(np.uint8)).resize((BW, BH), Image.BICUBIC).filter(ImageFilter.GaussianBlur(24)), float)
n = (n - n.min()) / (n.max() - n.min() + 1e-6)
bg *= (0.75 + 0.45 * n)[..., None]
im = Image.fromarray((np.clip(bg, 0, 1) ** (1 / 1.15) * 255).astype(np.uint8))
g = Image.new('RGB', (BW, BH)); dg = ImageDraw.Draw(g)
# subtle perspective floor grid (muted)
hor = int(BH * 0.58)
for i in range(-24, 25):
    dg.line([(BW / 2 + i * 22, hor), (BW / 2 + i * 280, BH)], fill=(50, 90, 140), width=1)
k = 0
while True:
    yv = hor + (BH - hor) * (k / 12) ** 2.0; k += 1
    if yv > BH: break
    dg.line([(0, yv), (BW, yv)], fill=(55, 80, 130), width=1)
dg.line([(0, hor), (BW, hor)], fill=(80, 120, 170), width=2)
for i in range(0, BW, 72): dg.line([(i, 0), (i, hor)], fill=(30, 45, 80), width=1)
for j in range(0, hor, 72): dg.line([(0, j), (BW, j)], fill=(30, 45, 80), width=1)
glow = g.filter(ImageFilter.GaussianBlur(5))
im = Image.fromarray(np.clip(np.array(im, float) + np.array(g, float) * 0.35 + np.array(glow, float) * 0.9, 0, 255).astype(np.uint8))
d = ImageDraw.Draw(im)
for _ in range(350):
    sx, sy = int(rng.integers(0, BW)), int(rng.integers(0, max(1, hor - 8)))
    b = int(rng.power(0.25) * 160) + 30
    d.point((sx, sy), fill=(b, b, min(255, b + 30)))
im.save(f'{A}/Textures/backdrop.png')
print('backdrop ok')

# ---------- playfield: dark glass with soft centre glow + dashed centre line hint
PW, PH = 1024, 1024
pf = Image.new('RGB', (PW, PH), (8, 10, 18)); dp = ImageDraw.Draw(pf)
# faint hex
R = 36; hh = R * np.sqrt(3)
for j in range(-1, int(PH / hh) + 2):
    for i in range(-1, int(PW / (1.5 * R)) + 2):
        cx = i * 1.5 * R; cy = j * hh + (hh / 2 if i % 2 else 0)
        pts = [(cx + R * np.cos(a), cy + R * np.sin(a)) for a in np.linspace(0, 2 * np.pi, 7)]
        dp.line(pts, fill=(35, 55, 95), width=1)
yy2, xx2 = np.mgrid[0:PH, 0:PW] / PH
glow2 = np.exp(-((xx2 - 0.5) ** 2 + (yy2 - 0.5) ** 2) * 3.5)[..., None]
arr = np.array(pf, float) * (0.4 + 0.85 * glow2) + glow2 * np.array([12, 18, 40])
arr += np.array(pf.filter(ImageFilter.GaussianBlur(5)), float) * 0.5 * glow2
# centre dashed line
for y in range(40, PH - 40, 48):
    dp2 = ImageDraw.Draw(Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)))
Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)).save(f'{A}/Textures/playfield.png')
# redraw dashed centre on saved
pf2 = Image.open(f'{A}/Textures/playfield.png'); d2 = ImageDraw.Draw(pf2)
for y in range(48, PH - 48, 56):
    d2.rectangle([PW // 2 - 4, y, PW // 2 + 4, y + 28], fill=(90, 140, 200))
pf2 = Image.blend(pf2, pf2.filter(ImageFilter.GaussianBlur(2)), 0.35)
pf2.save(f'{A}/Textures/playfield.png')
print('playfield ok')

# ---------- sfx
SR = 44100
def wav(name, s):
    s = np.clip(s, -1, 1); w = wave.open(f'{A}/Audio/{name}.wav', 'wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((s * 32000).astype(np.int16).tobytes()); w.close()
def tt(d): return np.arange(int(SR * d)) / SR
def env(t, a, d): return np.minimum(t / max(a, 1e-4), 1) * np.exp(-t / max(d, 1e-4))
def tone(f, d, dec, shape='sine', a=0.002):
    t = tt(d); ph = 2 * np.pi * np.cumsum(np.broadcast_to(f(t) if callable(f) else f, t.shape)) / SR
    w = np.sin(ph) if shape == 'sine' else (np.sign(np.sin(ph)) * 0.55 if shape == 'sq' else 2 * (ph / (2 * np.pi) % 1) - 1)
    return w * env(t, a, dec)
# paddle hit — soft blip, pitch varies slightly by callers in game via different files
for i, f in enumerate((220, 260, 300, 340, 380, 420)):
    wav(f'hit{i}', tone(f, 0.12, 0.04, 'sine') * 0.45 + tone(f * 2, 0.10, 0.03) * 0.25)
wav('wall', tone(160, 0.10, 0.03, 'sq') * 0.22 + tone(320, 0.08, 0.025) * 0.15)
wav('score', tone(lambda t: 440 + 220 * t, 0.35, 0.18, 'sine') * 0.35 + tone(lambda t: 660 + 330 * t, 0.35, 0.15) * 0.2)
wav('score2', tone(lambda t: 330 - 80 * t, 0.4, 0.2, 'sine') * 0.3 + tone(220, 0.4, 0.25) * 0.2)
wav('serve', tone(lambda t: 280 + 400 * t, 0.22, 0.12, 'sine') * 0.28)
wav('win', np.concatenate([tone(f, 0.14, 0.1) * 0.3 for f in (523, 659, 784, 1047)]))
wav('lose', np.concatenate([tone(f, 0.22, 0.18, 'sine') * 0.28 for f in (392, 330, 262, 196)]))
wav('click', tone(1100, 0.045, 0.012) * 0.4)
wav('start', tone(lambda t: 200 + 600 * t, 0.35, 0.2) * 0.25 + tone(lambda t: 400 + 800 * t, 0.35, 0.15) * 0.15)
wav('bounce', tone(lambda t: 500 * np.exp(-t * 8) + 80, 0.15, 0.05, 'sine') * 0.3)
print('sfx ok')
