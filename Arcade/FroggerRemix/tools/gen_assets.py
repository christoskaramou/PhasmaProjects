# Procedural assets for Frogger Remix: textures, normal maps, night-city HDR sky, WAV sfx/music.
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

# ---- asphalt: 4u x 5u tile (256 px/u), 5 lanes, dashed dividers, solid edge lines
W, H = 1024, 1280
n1 = fbm(H, W, 6, 8, 1); n2 = fbm(H, W, 4, 64, 2)
spk = (rng.random((H, W)) > 0.985) * rng.random((H, W))
base = 0.09 + 0.07 * n1 + 0.05 * (n2 - 0.5) + 0.12 * spk
tracks = np.zeros(H)
for lane in range(5):  # tyre polish strips darker/smoother
    c = (lane + 0.5) * H / 5
    for off in (-0.28, 0.28): tracks += np.exp(-((np.arange(H) - c - off * 256) / 18) ** 2)
base = base * (1 - 0.25 * tracks[:, None])
img = np.dstack([base * 0.95, base * 0.97, base * 1.05])
mark = np.zeros((H, W))
yy = np.arange(H)[:, None]; xx = np.arange(W)[None, :]
for k in (1, 2, 3, 4):
    c = k * H / 5
    mark = np.maximum(mark, (np.abs(yy - c) < 6) * ((xx % 256) < 140))
edge = (np.abs(yy - 10) < 7) | (np.abs(yy - (H - 10)) < 7)
wear = fbm(H, W, 4, 16, 3)
mark = mark * (wear > 0.35)
img = img * (1 - mark[..., None]) + mark[..., None] * np.array([0.85, 0.85, 0.8]) * (0.8 + 0.2 * wear[..., None])
ye = edge * (wear > 0.3)
img = img * (1 - ye[..., None]) + ye[..., None] * np.array([0.95, 0.7, 0.1])
save('asphalt.png', img)
hgt = n2 * 0.6 + spk * 0.8 + mark * 0.3
Image.fromarray((normal_from_height(hgt, 1.6) * 255).astype(np.uint8)).save(f'{T}/asphalt_n.png')

# ---- pavement tiles (1u per tile, 256px): 2x2 slabs with grout
S = 256; n = fbm(S, S, 5, 8, 4)
p = 0.42 + 0.12 * n
g = np.zeros((S, S)); a = np.arange(S)
gr = (np.minimum(a % 128, 127 - a % 128) < 4)
g = np.maximum(gr[:, None], gr[None, :]).astype(float)
pav = p * (1 - 0.7 * g)
save('pavement.png', np.dstack([pav * 1.0, pav * 0.97, pav * 0.93]))
Image.fromarray((normal_from_height(n * 0.4 - g * 0.8, 5) * 255).astype(np.uint8)).save(f'{T}/pavement_n.png')

# ---- grass (tileable, 512)
S = 512; n = fbm(S, S, 6, 8, 5); bl = rng.random((S, S))
gcol = np.dstack([0.10 + 0.08 * n, 0.25 + 0.2 * n + 0.08 * bl, 0.07 + 0.05 * n])
save('grass.png', gcol)

# ---- water: tileable ripple height -> normal map + deep colour with caustic-ish streaks
S = 512
x = np.arange(S) / S; X, Y = np.meshgrid(x, x)
h = np.zeros((S, S))
r2 = np.random.default_rng(8)
for i in range(14):
    kx, ky = r2.integers(-6, 7), r2.integers(1, 9)
    h += np.sin(2 * np.pi * (kx * X + ky * Y) + r2.random() * 6.28) / (1 + 0.3 * math.hypot(kx, ky))
h += 0.6 * fbm(S, S, 4, 16, 9)
h = (h - h.min()) / (h.max() - h.min())
Image.fromarray((normal_from_height(h, 9) * 255).astype(np.uint8)).save(f'{T}/water_n.png')
c = fbm(S, S, 5, 4, 10)
wcol = np.dstack([0.02 + 0.03 * c, 0.10 + 0.08 * c + 0.05 * h, 0.16 + 0.1 * c + 0.06 * h])
save('water.png', wcol)

# ---- bark (log): wrap u=around, v=along
W, H = 512, 1024
n = fbm(H, W, 5, 8, 11); st = fbm(H, W, 3, 4, 12)
grooves = 0.5 + 0.5 * np.sin(np.arange(W)[None, :] / W * 2 * np.pi * 14 + 6 * st)
v = 0.5 * grooves + 0.5 * n
save('bark.png', np.dstack([0.22 + 0.25 * v, 0.13 + 0.16 * v, 0.07 + 0.08 * v]))
Image.fromarray((normal_from_height(grooves * 0.8 + n * 0.5, 7) * 255).astype(np.uint8)).save(f'{T}/bark_n.png')
# ---- log end rings (disc uv)
S = 256; yy, xx = np.mgrid[0:S, 0:S] / S - 0.5; rr = np.hypot(xx, yy) * 2
ring = 0.5 + 0.5 * np.sin(rr * 40 + 2 * fbm(S, S, 3, 4, 13))
e = 0.55 + 0.25 * ring; e = np.where(rr > 0.93, 0.35, e)
save('logend.png', np.dstack([e * 0.85, e * 0.62, e * 0.38]))

# ---- turtle shell: scute pattern (uv sphere: u=around, v=pole->pole)
W, H = 512, 256
u = np.arange(W)[None, :] / W; v = np.arange(H)[:, None] / H
cells = (np.abs(np.sin(u * np.pi * 6)) < 0.08) | (np.abs(np.sin(v * np.pi * 4)) < 0.05)
n = fbm(H, W, 4, 8, 14)
sh = np.dstack([0.25 + 0.2 * n, 0.32 + 0.2 * n, 0.12 + 0.08 * n]) * (1 - 0.6 * cells[..., None])
save('shell.png', sh)

# ---- frog skin (subtle mottling)
S = 256; n = fbm(S, S, 5, 8, 15)
save('frogskin.png', np.dstack([0.25 + 0.3 * n, 0.65 + 0.35 * n, 0.15 + 0.2 * n]))

# ---- stone wall
S = 256; n = fbm(S, S, 5, 8, 16)
save('stone.png', np.dstack([0.35 + 0.25 * n, 0.33 + 0.24 * n, 0.32 + 0.22 * n]))

# ---- city windows (emissive), for skyline buildings
W, H = 256, 512; win = np.zeros((H, W, 3))
for y in range(0, H, 16):
    for x in range(0, W, 16):
        if rng.random() < 0.45:
            col = [(1.0, 0.8, 0.45), (0.6, 0.85, 1.0), (1.0, 0.95, 0.8), (1.0, 0.4, 0.7)][rng.integers(0, 4)]
            win[y + 4:y + 12, x + 4:x + 11] = np.array(col) * (0.5 + 0.5 * rng.random())
save('windows.png', win)
print('textures ok')

# ---------- skybox: twilight city (violet zenith, magenta/orange horizon glow, stars, moon)
W, H = 1024, 512
v = (np.arange(H) + .5) / H; u = (np.arange(W) + .5) / W
EL, AZ = np.meshgrid((0.5 - v) * np.pi, (u - 0.5) * 2 * np.pi, indexing='ij')
x = np.cos(EL) * np.cos(AZ); z = np.cos(EL) * np.sin(AZ); y = np.sin(EL)
hz = np.exp(-np.maximum(y, 0) / 0.12)
img = np.zeros((H, W, 3))
img += np.array([0.05, 0.06, 0.2]) * (1 - hz[..., None]) + np.array([0.04,0.03,0.08])
img += hz[..., None] * np.array([0.45, 0.16, 0.28])
img += np.exp(-np.maximum(y, 0) / 0.035)[..., None] * np.array([0.9, 0.42, 0.18])
img[y < 0] = np.array([0.08, 0.07, 0.1])
stars = (np.random.default_rng(3).random((H, W)) > 0.9975) * (y > 0.12)
img += stars[..., None] * np.random.default_rng(4).random((H, W))[..., None] * 3.0
md = np.array([0.35, 0.45, -0.82]); md /= np.linalg.norm(md)
ang = np.arccos(np.clip(x * md[0] + y * md[1] + z * md[2], -1, 1))
img += (ang < 0.035)[..., None] * np.array([6.0, 6.0, 5.4]) + np.exp(-ang / 0.12)[..., None] * np.array([0.1, 0.12, 0.2])
def rgbe(a):
    m = a.max(-1); e = np.ceil(np.log2(np.maximum(m, 1e-32))); sc = np.where(m > 1e-32, 256.0 / 2 ** e, 0)
    out = np.zeros(a.shape[:2] + (4,), np.uint8)
    out[..., :3] = np.clip(a * sc[..., None], 0, 255).astype(np.uint8); out[..., 3] = np.where(m > 1e-32, e + 128, 0).astype(np.uint8); return out
with open(f'{A}/Skybox/twilight.hdr', 'wb') as f:
    f.write(b"#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y %d +X %d\n" % (H, W)); f.write(rgbe(img.astype(np.float32)).tobytes())

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
t = tt(0.12); wav('hop', osc(lambda t: 380 + 900 * t / 0.12, t, 'tri') * env(t, 0.003, 0.04) * 0.6)
t = tt(0.5); wav('squash', NZ[:len(t)] * env(t, 0.001, 0.07) * 0.8 + osc(lambda t: 160 * np.exp(-t * 5), t, 'sq') * env(t, 0.002, 0.15) * 0.5)
lp = np.convolve(NZ, np.ones(30) / 30, 'same')
t = tt(0.8); wav('splash', lp[:len(t)] * 4 * env(t, 0.01, 0.2) * (0.6 + 0.4 * np.sin(t * 60)) + osc(lambda t: 700 * np.exp(-t * 4), t) * env(t, 0.005, 0.1) * 0.2)
def notes(seq, d, shape='sq', dec=0.12, vol=0.35):
    out = []
    for f in seq:
        t = tt(d); out.append((osc(f, t, shape) * env(t, 0.003, dec) * vol) if f else np.zeros(len(t)))
    return np.concatenate(out)
wav('home', notes([523, 659, 784, 1047], 0.09, 'sq', 0.1))
wav('level', notes([523, 523, 659, 784, 659, 784, 1047, 0, 1047], 0.12, 'sq', 0.15))
wav('fly', notes([1200, 1600, 2000], 0.05, 'tri', 0.05, 0.4))
wav('extra', notes([784, 988, 1175, 1568], 0.08, 'tri', 0.1, 0.4))
wav('over', notes([392, 370, 349, 330, 0, 262], 0.22, 'saw', 0.25, 0.3))
wav('click', notes([1500], 0.04, 'tri', 0.015, 0.3))
wav('tick', notes([1800], 0.05, 'sq', 0.02, 0.25))
t = tt(0.5); wav('horn', (osc(415, t, 'saw') + osc(523, t, 'saw')) * env(t, 0.02, 0.4) * 0.25)
# music loop: 16 bars synthwave, 112 bpm
bpm = 112; beat = 60 / bpm; bars = 8; L = int(SR * beat * 4 * bars)
mus = np.zeros(L)
prog = [(55, [220, 277, 330]), (49, [196, 247, 294]), (41.2, [174.6, 220, 262]), (49, [196, 247, 311])]
mel = [659, 0, 587, 659, 784, 0, 659, 587, 523, 0, 587, 523, 494, 0, 440, 494]
for bar in range(bars):
    root, ch = prog[bar % 4]
    for e8 in range(8):
        s = int(SR * (bar * 4 + e8 * 0.5) * beat); t = tt(beat * 0.5)
        mus[s:s + len(t)] += osc(root * (2 if e8 % 2 else 1), t, 'saw') * env(t, 0.004, 0.12) * 0.22
        if e8 % 2 == 0:  # hats + kick
            mus[s:s + 2000] += NZ[s % 100000:s % 100000 + 2000] * env(tt(2000 / SR), 0.0005, 0.01) * 0.12
        if e8 % 4 == 0:
            tk = tt(0.25); mus[s:s + len(tk)] += osc(lambda t: 50 + 90 * np.exp(-t * 30), tk) * env(tk, 0.002, 0.12) * 0.5
    s = int(SR * bar * 4 * beat); t = tt(beat * 4)
    for f in ch: mus[s:s + len(t)] += osc(f, t, 'tri') * env(t, 0.3, 3.0) * 0.06
    for k in range(4):
        f = mel[(bar * 4 + k) % 16]
        if f and bar >= 2:
            s2 = s + int(SR * k * beat); t = tt(beat * 0.9); mus[s2:s2 + len(t)] += osc(f, t, 'sq') * env(t, 0.01, 0.25) * 0.08
wav('music', mus * 0.8)
print('audio ok')
