# Procedural assets for Bubble Bobble Remix: HDR skybox, backdrop, block textures, WAV sfx.
import numpy as np, os, wave
from PIL import Image
A = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'project', 'Assets')
rng = np.random.default_rng(7)
def fbm_tile(h, w, seed=0, p=1.9):
    r = np.random.default_rng(seed)
    fy = np.fft.fftfreq(h)[:, None] * h; fx = np.fft.fftfreq(w)[None, :] * w
    f = np.sqrt(fx ** 2 + fy ** 2); f[0, 0] = 1
    spec = (r.normal(size=(h, w)) + 1j * r.normal(size=(h, w))) / f ** p
    n = np.real(np.fft.ifft2(spec)); return (n - n.min()) / (n.max() - n.min())
def ramp(n, lo, hi): return np.clip((n - lo) / (hi - lo), 0, 1)
W, H = 512, 256
v = (np.arange(H) + .5) / H
y = np.sin(np.repeat(((0.5 - v) * np.pi)[:, None], W, 1))
img = np.zeros((H, W, 3)) + np.array([0.03, 0.03, 0.06])
img += np.clip(y, 0, 1)[..., None] * np.array([0.10, 0.14, 0.30])
img += np.clip(1 - np.abs(y) * 3, 0, 1)[..., None] ** 2 * np.array([0.25, 0.12, 0.3])
def rgbe(a):
    m = a.max(-1); e = np.ceil(np.log2(np.maximum(m, 1e-32))); sc = np.where(m > 1e-32, 256.0 / 2 ** e, 0)
    out = np.zeros(a.shape[:2] + (4,), np.uint8)
    out[..., :3] = np.clip(a * sc[..., None], 0, 255).astype(np.uint8); out[..., 3] = np.where(m > 1e-32, e + 128, 0).astype(np.uint8); return out
with open(f'{A}/Skybox/bubbles.hdr', 'wb') as f:
    f.write(b"#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y %d +X %d\n" % (H, W)); f.write(rgbe(img.astype(np.float32)).tobytes())
# backdrop: deep indigo night with soft bokeh bubbles and faint grid of distant cave
TH, TW = 1024, 1536
yy = np.linspace(0, 1, TH)[:, None] * np.ones((1, TW)); xx = np.linspace(0, 1, TW)[None, :] * np.ones((TH, 1))
n1 = fbm_tile(TH, TW, 1, 2.2)
sky = (1 - yy)[..., None] * np.array([0.03, 0.04, 0.12]) + yy[..., None] * np.array([0.10, 0.03, 0.14]) + (n1 ** 2)[..., None] * np.array([0.05, 0.04, 0.10])
for k in range(90):
    cx, cy, r = rng.random(), rng.random(), rng.uniform(0.01, 0.06)
    col = np.array([[0.3, 0.8, 1.0], [0.6, 1.0, 0.6], [1.0, 0.5, 0.9]][rng.integers(0, 3)]) * rng.uniform(0.05, 0.22)
    d = np.sqrt(((xx - cx) * TW / TH) ** 2 + (yy - cy) ** 2) / r
    sky += (np.clip(1 - d, 0, 1) ** 0.5 * 0.4 + np.exp(-((d - 0.92) / 0.06) ** 2))[..., None] * col
for k in range(1500):
    a, b = rng.integers(0, TH), rng.integers(0, TW); sky[a, b] += rng.random() ** 3 * 0.6
Image.fromarray((np.clip(sky, 0, 1) * 255).astype(np.uint8)).save(f'{A}/Textures/backdrop.png')
# block texture: rounded tiles with bevel highlight (tinted per level in-game)
T = 256; u = (np.arange(T) + .5) / T * 4 % 1
U_, V_ = np.meshgrid(u, u)
e = np.minimum(np.minimum(U_, 1 - U_), np.minimum(V_, 1 - V_))
tile = 0.55 + 0.45 * ramp(e, 0.0, 0.12) - 0.25 * ramp(0.04 - e, 0, 0.04)
hl = ramp(0.2 - np.hypot(U_ - 0.3, V_ - 0.3), 0, 0.2) * 0.25
n = fbm_tile(T, T, 5, 1.4)
tex = np.clip(tile + hl + (n - 0.5) * 0.12, 0, 1)
Image.fromarray((np.stack([tex] * 3, -1) * 255).astype(np.uint8)).save(f'{A}/Textures/block.png')
SR = 44100
def save(name, s, vol=0.8):
    s = np.asarray(s, float); s = s / (np.abs(s).max() + 1e-9) * vol
    with wave.open(f'{A}/Audio/{name}.wav', 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes((np.clip(s, -1, 1) * 32000).astype(np.int16).tobytes())
def t(d): return np.arange(int(SR * d)) / SR
def sq(p): return np.sign(np.sin(p))
def sweep(f0, f1, d, w=np.sin):
    tt = t(d); f = f0 * (f1 / f0) ** (tt / d); return w(2 * np.pi * np.cumsum(f) / SR)
def noise(d): return rng.uniform(-1, 1, int(SR * d))
def env(n, a=0.005, r=0.05):
    e = np.ones(n); ai = max(1, int(a * SR)); e[:ai] = np.linspace(0, 1, ai); ri = min(n, int(r * SR)); e[-ri:] *= np.linspace(1, 0, ri) ** 2; return e
def tune(mel, w=lambda p: sq(p) * 0.3 + np.sin(p) * 0.5):
    out = []
    for f_, dd in mel:
        tt = t(dd); out.append(w(2 * np.pi * f_ * tt) * env(len(tt), 0.005, dd * 0.4) if f_ else np.zeros(len(tt)))
    return np.concatenate(out)
d = 0.18; save('blow', sweep(500, 1500, d) * np.exp(-t(d) * 10) + 0.2 * noise(d) * np.exp(-t(d) * 30), 0.35)
d = 0.12; save('pop', sweep(1800, 400, d) * np.exp(-t(d) * 35) + 0.3 * noise(d) * np.exp(-t(d) * 60), 0.5)
d = 0.4; save('trap', sweep(300, 900, d) * (0.6 + 0.4 * np.sin(2 * np.pi * 18 * t(d))) * env(int(d * SR), 0.01, 0.2), 0.45)
d = 0.6; save('kill', sweep(1200, 200, d, sq) * 0.4 * np.exp(-t(d) * 4) + 0.3 * noise(d) * np.exp(-t(d) * 10), 0.5)
save('fruit', tune([(1319, .05), (1760, .05), (2637, .1)]), 0.4)
d = 0.2; save('jump', sweep(300, 800, d, sq) * 0.3 * env(int(d * SR), 0.005, 0.1), 0.3)
d = 0.08; save('land', noise(d) * np.exp(-t(d) * 60), 0.15)
d = 1.4; save('death', sweep(900, 80, d, sq) * 0.4 * (0.6 + 0.4 * np.sin(2 * np.pi * 12 * t(d))) * env(int(d * SR), 0.01, 0.4), 0.55)
save('letter', tune([(1568, .06), (2093, .06), (2637, .12)]), 0.45)
save('extend', tune([(523, .1), (659, .1), (784, .1), (1047, .1), (784, .1), (1047, .4)]), 0.5)
save('hurry', tune([(988, .08), (0, .04), (988, .08), (0, .04), (988, .08), (0, .04), (1319, .25)]), 0.5)
d = 1.0; tt = t(d); save('baron', np.sin(2 * np.pi * np.cumsum(90 + 30 * np.sin(2 * np.pi * 3 * tt)) / SR) * env(len(tt), 0.05, 0.3) + 0.3 * sq(2 * np.pi * 45 * tt) * env(len(tt), 0.05, 0.3), 0.5)
save('start', tune([(523, .12), (659, .12), (784, .12), (1047, .24), (0, .06), (880, .12), (1047, .45)]), 0.5)
save('level', tune([(784, .1), (988, .1), (1175, .1), (1568, .35)]), 0.5)
save('gameover', tune([(659, .3), (587, .3), (523, .3), (440, .9)], lambda p: np.sin(p) * 0.6 + sq(p) * 0.2), 0.5)
save('click', np.sin(2 * np.pi * 1200 * t(0.04)) * np.exp(-t(0.04) * 60), 0.4)
d = 0.25; save('bounce', sweep(400, 1000, d) * np.exp(-t(d) * 12), 0.35)
print('assets ok')
