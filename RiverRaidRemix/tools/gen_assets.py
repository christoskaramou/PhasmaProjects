# Procedural assets for River Raid Remix: textures, normal maps, night-city HDR sky, WAV sfx/music.
import numpy as np, os, wave, math
from PIL import Image, ImageDraw, ImageFilter
A = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'project', 'Assets')
T = f'{A}/Textures'; os.makedirs(T, exist_ok=True)
rng = np.random.default_rng(42)

def fbm(h, w, oct=5, base=8, seed=0, tile=True):
    """tileable value-noise fbm in [0,1]"""
    r = np.random.default_rng(seed); out = np.zeros((h, w)); amp = 1; tot = 0
    for o in range(oct):
        n = base * 2 ** o
        g = r.random((n, n))
        im = Image.fromarray((g * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC) if not tile else None
        if tile:
            g2 = np.tile(g, (3, 3)); im = Image.fromarray((g2 * 255).astype(np.uint8)).resize((w * 3, h * 3), Image.BICUBIC)
            a = np.asarray(im, float)[h:2 * h, w:2 * w] / 255
        else: a = np.asarray(im, float) / 255
        out += a * amp; tot += amp; amp *= 0.5
    return out / tot

def save(name, a):
    Image.fromarray(np.clip(a * 255, 0, 255).astype(np.uint8)).save(f'{T}/{name}')

def normal_from_height(hgt, strength):
    gy, gx = np.gradient(hgt)
    n = np.dstack([-gx * strength, -gy * strength, np.ones_like(hgt)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return n * 0.5 + 0.5

def rgbe(a):
    m = a.max(-1); e = np.ceil(np.log2(np.maximum(m, 1e-32))); sc = np.where(m > 1e-32, 256.0 / 2 ** e, 0)
    out = np.zeros(a.shape[:2] + (4,), np.uint8)
    out[..., :3] = np.clip(a * sc[..., None], 0, 255).astype(np.uint8); out[..., 3] = np.where(m > 1e-32, e + 128, 0).astype(np.uint8); return out
# ---------- audio
SR = 44100; os.makedirs(f'{A}/Audio', exist_ok=True)
def wav(name, s, sr=SR):
    s = np.clip(s, -1, 1); w = wave.open(f'{A}/Audio/{name}.wav', 'wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
    w.writeframes((s * 32000).astype(np.int16).tobytes()); w.close()
def tt(d): return np.arange(int(SR * d)) / SR
def env(t, a, d): return np.minimum(t / a, 1) * np.exp(-t / d)
def osc(f, t, shape='sine'):
    ph = np.cumsum(f(t) if callable(f) else np.full(len(t), f)) / SR * 2 * np.pi
    if shape == 'sq': return np.sign(np.sin(ph)) * 0.6
    if shape == 'tri': return 2 / np.pi * np.arcsin(np.sin(ph))
    if shape == 'saw': return ((ph / (2 * np.pi)) % 1) * 2 - 1
    return np.sin(ph)
NZ = np.random.default_rng(1).standard_normal(SR * 4)
def notes(seq, d, shape='sq', dec=0.12, vol=0.35):
    out = []
    for f in seq:
        t = tt(d); out.append((osc(f, t, shape) * env(t, 0.003, dec) * vol) if f else np.zeros(len(t)))
    return np.concatenate(out)
def lowpass(x, k): return np.convolve(x, np.ones(k) / k, 'same')

# ================= textures
# water normal (tileable, 8u tile)
S = 512
x = np.arange(S) / S; X, Y = np.meshgrid(x, x)
h = np.zeros((S, S)); r2 = np.random.default_rng(8)
for i in range(18):
    kx, ky = r2.integers(-7, 8), r2.integers(1, 10)
    h += np.sin(2 * np.pi * (kx * X + ky * Y) + r2.random() * 6.28) / (1 + 0.35 * math.hypot(kx, ky))
h += 0.7 * fbm(S, S, 4, 16, 9)
h = (h - h.min()) / (h.max() - h.min())
Image.fromarray((normal_from_height(h, 7) * 255).astype(np.uint8)).save(f'{T}/water_n.png')
c = fbm(S, S, 5, 4, 10)
save('water.png', np.dstack([0.06 + 0.05 * c, 0.30 + 0.12 * c + 0.08 * h, 0.38 + 0.12 * c + 0.08 * h]))
# grass: mottled
S = 512; n1 = fbm(S, S, 6, 8, 21); n2 = fbm(S, S, 3, 32, 22)
g = 0.75 + 0.35 * n1 + 0.15 * (n2 - 0.5)
save('grass.png', np.dstack([0.20 * g, 0.42 * g, 0.12 * g]))
Image.fromarray((normal_from_height(n2 * 0.6 + n1 * 0.4, 5) * 255).astype(np.uint8)).save(f'{T}/grass_n.png')
# rock / shore
n = fbm(S, S, 6, 6, 23); cr = fbm(S, S, 3, 24, 24)
rk = 0.45 + 0.4 * n - 0.25 * (cr > 0.62)
save('rock.png', np.dstack([0.52 * rk, 0.47 * rk, 0.40 * rk]))
Image.fromarray((normal_from_height(n + 0.5 * (cr > 0.62), 9) * 255).astype(np.uint8)).save(f'{T}/rock_n.png')
# sand
n = fbm(S, S, 6, 16, 25)
save('sand.png', np.dstack([0.78 + 0.15 * n, 0.68 + 0.13 * n, 0.48 + 0.1 * n]) * 0.9)
# asphalt with centre dashes (u along road)
W, H = 1024, 256; n = fbm(H, W, 5, 8, 26)
a = 0.1 + 0.06 * n
img = np.dstack([a, a, a * 1.05])
yy = np.arange(H)[:, None]; xx = np.arange(W)[None, :]
dash = (np.abs(yy - H / 2) < 5) & ((xx % 128) < 70)
edge = ((np.abs(yy - 14) < 4) | (np.abs(yy - (H - 14)) < 4)) & np.ones((1, W), bool)
img[dash] = [0.9, 0.75, 0.15]; img[edge] = [0.85, 0.85, 0.82]
save('asphalt.png', img)
# fuel depot stripes texture (u around, v up): red/white bands + FUEL lettering blocks
W, H = 512, 256; img = np.ones((H, W, 3)) * 0.92
band = ((np.arange(H) // 32) % 2 == 0)[:, None] & np.ones((1, W), bool)
img[band] = [0.85, 0.08, 0.06]
im = Image.fromarray((img * 255).astype(np.uint8)); d = ImageDraw.Draw(im)
from PIL import ImageFont
try: fnt = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 40)
except Exception: fnt = ImageFont.load_default()
for k in range(4):
    d.rectangle([k * 128 + 8, 92, k * 128 + 120, 164], fill=(245, 245, 240))
    d.text((k * 128 + 14, 104), "FUEL", fill=(200, 20, 15), font=fnt)
im.save(f'{T}/fuel.png')
# metal panels
S = 256; n = fbm(S, S, 5, 8, 27); a = 0.6 + 0.3 * n
pan = ((np.arange(S)[:, None] % 64) < 2) | ((np.arange(S)[None, :] % 64) < 2)
a = a * (1 - 0.4 * pan)
save('metal.png', np.dstack([a, a, a * 1.03]))
Image.fromarray((normal_from_height(1 - pan * 1.0 + 0.2 * n, 4) * 255).astype(np.uint8)).save(f'{T}/metal_n.png')
# concrete
n = fbm(S, S, 6, 8, 28); a = 0.55 + 0.25 * n
save('concrete.png', np.dstack([a, a * 0.98, a * 0.95]))
print('textures ok')

# ================= sky: golden-hour, warm horizon, soft clouds, sun
W, H = 1024, 512
v = (np.arange(H) + .5) / H; u = (np.arange(W) + .5) / W
EL, AZ = np.meshgrid((0.5 - v) * np.pi, (u - 0.5) * 2 * np.pi, indexing='ij')
x = np.cos(EL) * np.cos(AZ); z = np.cos(EL) * np.sin(AZ); y = np.sin(EL)
yy = np.maximum(y, 0)
img = np.zeros((H, W, 3))
zen = np.array([0.10, 0.28, 0.75]); hor = np.array([1.1, 0.75, 0.5])
t = np.exp(-yy / 0.22)[..., None]
img = zen * (1 - t) + hor * t
sd = np.array([0.55, 0.35, -0.76]); sd /= np.linalg.norm(sd)
ang = np.arccos(np.clip(x * sd[0] + y * sd[1] + z * sd[2], -1, 1))
img += (ang < 0.03)[..., None] * np.array([40.0, 34.0, 24.0]) + np.exp(-ang / 0.25)[..., None] * np.array([0.9, 0.6, 0.3])
cl = fbm(H, W, 6, 6, 31)
cm = np.clip((cl - 0.55) * 3.5, 0, 1) * (y > 0.02) * np.exp(-yy / 0.5)
img = img * (1 - cm[..., None] * 0.7) + cm[..., None] * np.array([1.3, 1.1, 0.95])
gr = np.array([0.18, 0.22, 0.12])
img[y < 0] = gr
with open(f'{A}/Skybox/golden.hdr', 'wb') as f:
    f.write(b"#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y %d +X %d\n" % (H, W)); f.write(rgbe(img.astype(np.float32)).tobytes())
print('sky ok')

# ================= audio
os.makedirs(f'{A}/Audio', exist_ok=True)
NZ = np.random.default_rng(1).standard_normal(SR * 6)
t = tt(0.22); wav('shoot', (osc(lambda t: 1400 * np.exp(-t * 9) + 200, t, 'sq') * 0.5 + NZ[:len(t)] * 0.3) * env(t, 0.002, 0.07) * 0.6)
t = tt(1.0); wav('explode', lowpass(NZ[:len(t)], 12) * 3 * env(t, 0.003, 0.25) + osc(lambda t: 90 * np.exp(-t * 3), t) * env(t, 0.002, 0.3) * 0.6)
t = tt(2.2); wav('bigboom', lowpass(NZ[:len(t)], 30) * 6 * env(t, 0.004, 0.6) + osc(lambda t: 55 * np.exp(-t * 1.5), t) * env(t, 0.003, 0.8) * 0.8)
t = tt(0.12); wav('refuel', osc(lambda t: 880 + 600 * t / 0.12, t, 'tri') * env(t, 0.004, 0.06) * 0.35)
wav('lowfuel', notes([1320, 0, 1320, 0], 0.11, 'sq', 0.06, 0.3))
wav('full', notes([988, 1319, 1760], 0.07, 'tri', 0.06, 0.35))
wav('click', notes([1500], 0.04, 'tri', 0.015, 0.3))
wav('start', notes([523, 659, 784, 1047, 0, 1047], 0.09, 'sq', 0.1, 0.3))
wav('bridge', notes([784, 988, 1175, 1568, 1976], 0.07, 'sq', 0.08, 0.3))
wav('over', notes([392, 370, 349, 330, 0, 262], 0.22, 'saw', 0.25, 0.3))
wav('extra', notes([784, 988, 1175, 1568, 0, 1568], 0.08, 'tri', 0.1, 0.4))
t = tt(1.6); wav('crash', lowpass(NZ[:len(t)], 8) * 3 * env(t, 0.002, 0.4) + osc(lambda t: 140 * np.exp(-t * 2), t, 'saw') * env(t, 0.002, 0.5) * 0.4)
t = tt(0.5); wav('splash', lowpass(NZ[:len(t)], 25) * 4 * env(t, 0.01, 0.15))
print('audio ok')
