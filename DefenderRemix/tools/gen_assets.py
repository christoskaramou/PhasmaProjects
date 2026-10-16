# Procedural assets for Defender Remix: dusk-planet HDR skybox, tileable sky backdrop, WAV sfx.
import numpy as np, os, wave
from PIL import Image
A = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'project', 'Assets')
rng = np.random.default_rng(11)
def fbm_tile(h, w, seed=0, p=1.9):
    r = np.random.default_rng(seed)
    fy = np.fft.fftfreq(h)[:, None] * h; fx = np.fft.fftfreq(w)[None, :] * w
    f = np.sqrt(fx ** 2 + fy ** 2); f[0, 0] = 1
    spec = (r.normal(size=(h, w)) + 1j * r.normal(size=(h, w))) / f ** p
    n = np.real(np.fft.ifft2(spec)); return (n - n.min()) / (n.max() - n.min())
def ramp(n, lo, hi): return np.clip((n - lo) / (hi - lo), 0, 1)
# skybox (IBL): dark violet zenith, warm horizon glow
W, H = 512, 256
v = (np.arange(H) + .5) / H
EL = np.repeat(((0.5 - v) * np.pi)[:, None], W, 1)
y = np.sin(EL)
img = np.zeros((H, W, 3))
img += np.clip(1 - np.abs(y) * 3, 0, 1)[..., None] ** 2 * np.array([0.5, 0.18, 0.12])
img += np.clip(y, 0, 1)[..., None] * np.array([0.03, 0.03, 0.12]) + np.array([0.01, 0.008, 0.02])
def rgbe(a):
    m = a.max(-1); e = np.ceil(np.log2(np.maximum(m, 1e-32))); sc = np.where(m > 1e-32, 256.0 / 2 ** e, 0)
    out = np.zeros(a.shape[:2] + (4,), np.uint8)
    out[..., :3] = np.clip(a * sc[..., None], 0, 255).astype(np.uint8); out[..., 3] = np.where(m > 1e-32, e + 128, 0).astype(np.uint8); return out
with open(f'{A}/Skybox/dusk.hdr', 'wb') as f:
    f.write(b"#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y %d +X %d\n" % (H, W)); f.write(rgbe(img.astype(np.float32)).tobytes())
# sky backdrop (horizontally tileable 2048x1024): starfield top, aurora bands, warm horizon haze at bottom
TH, TW = 1024, 2048
yy = np.linspace(0, 1, TH)[:, None] * np.ones((1, TW))
n1 = fbm_tile(TH, TW, 1); n2 = fbm_tile(TH, TW, 2, 2.2); n3 = fbm_tile(TH, TW, 3)
sky = (1 - yy)[..., None] * np.array([0.01, 0.01, 0.04]) + (yy ** 3)[..., None] * np.array([0.32, 0.09, 0.16])
sky += (yy ** 8)[..., None] * np.array([0.6, 0.25, 0.1])
xx = np.linspace(0, 2 * np.pi, TW)[None, :]
band = np.exp(-((yy - 0.42 - 0.08 * np.sin(xx * 3 + n2 * 4)) / 0.07) ** 2) * ramp(n1, 0.35, 0.9)
sky += band[..., None] * np.array([0.05, 0.5, 0.38]) * 0.8
band2 = np.exp(-((yy - 0.3 - 0.06 * np.sin(xx * 2 + 1 + n3 * 3)) / 0.05) ** 2) * ramp(n3, 0.45, 0.95)
sky += band2[..., None] * np.array([0.35, 0.1, 0.5]) * 0.8
stars = np.zeros((TH, TW))
for k in range(6000):
    a, b = rng.integers(0, TH), rng.integers(0, TW); stars[a, b] = rng.random() ** 3 * 1.1 + 0.06
for k in range(250):
    a, b = rng.integers(1, int(TH * 0.7)), rng.integers(1, TW - 1); s = rng.random() * 0.6 + 0.6
    stars[a, b] = 2 * s; stars[a - 1:a + 2, b] += 0.3 * s; stars[a, b - 1:b + 2] += 0.3 * s
sky += (stars * (1 - yy) ** 1.5)[..., None]
Image.fromarray((np.clip(sky, 0, 1) * 255).astype(np.uint8)).save(f'{A}/Textures/sky.png')
# rock texture for terrain (tileable)
n = fbm_tile(512, 512, 7, 1.6); n2 = fbm_tile(512, 512, 8, 2.4)
rock = (0.25 + 0.6 * n)[..., None] * np.array([0.42, 0.3, 0.32]) + ramp(n2, 0.6, 0.9)[..., None] * np.array([0.15, 0.08, 0.05])
Image.fromarray((np.clip(rock, 0, 1) * 255).astype(np.uint8)).save(f'{A}/Textures/rock.png')
# planet texture
pw, ph = 512, 256; pn = fbm_tile(ph, pw, 9, 2.0); bands = np.sin(np.linspace(0, 18, ph))[:, None] * 0.5 + 0.5
pl = (0.3 + 0.5 * bands * pn)[..., None] * np.array([0.9, 0.55, 0.8]) + ramp(pn, 0.6, 1)[..., None] * np.array([0.3, 0.6, 0.7])
Image.fromarray((np.clip(pl, 0, 1) * 255).astype(np.uint8)).save(f'{A}/Textures/planet.png')
# sfx
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
def lp(x, a):
    y = np.zeros_like(x); acc = 0.0
    for i in range(len(x)): acc += a * (x[i] - acc); y[i] = acc
    return y
def env(n, a=0.005, r=0.05):
    e = np.ones(n); ai = max(1, int(a * SR)); e[:ai] = np.linspace(0, 1, ai); ri = min(n, int(r * SR)); e[-ri:] *= np.linspace(1, 0, ri) ** 2; return e
save('laser', sweep(3200, 700, 0.14, lambda p: 0.5 * sq(p) + 0.5 * np.sin(p)) * np.exp(-t(0.14) * 14), 0.35)
d = 0.4; save('hit', lp(noise(d), 0.35) * np.exp(-t(d) * 10) + sweep(700, 60, d) * np.exp(-t(d) * 8) * 0.7, 0.6)
d = 1.0; save('boom', lp(noise(d), 0.12) * np.exp(-t(d) * 4) + sweep(260, 25, d) * np.exp(-t(d) * 3.5) * 0.9, 0.85)
d = 1.8; save('death', lp(noise(d), 0.08) * np.exp(-t(d) * 1.8) + sweep(500, 30, d, sq) * 0.35 * np.exp(-t(d) * 2), 0.9)
d = 1.4; save('smartbomb', lp(noise(d), 0.2) * np.exp(-t(d) * 2.5) + sweep(80, 1600, d) * 0.6 * np.exp(-t(d) * 2), 0.85)
d = 0.6; save('hyper', sweep(200, 3000, d) * env(int(d * SR), 0.01, 0.2) + 0.3 * sweep(400, 6000, d, sq) * env(int(d * SR), 0.01, 0.2), 0.45)
d = 0.12; save('eshot', sweep(500, 1400, d, sq) * np.exp(-t(d) * 18), 0.25)
d = 1.2; tt = t(d); f = 300 + 500 * tt / d; save('abduct', np.sin(2 * np.pi * np.cumsum(f + 60 * np.sin(2 * np.pi * 10 * tt)) / SR) * env(len(tt), 0.05, 0.2), 0.4)
d = 0.9; tt = t(d); save('mutate', (sq(2 * np.pi * np.cumsum(900 - 700 * tt / d + 120 * np.sin(2 * np.pi * 25 * tt)) / SR)) * env(len(tt), 0.01, 0.3), 0.4)
def tune(mel, w=lambda p: sq(p) * 0.35 + np.sin(p) * 0.45):
    out = []
    for f_, dd in mel:
        tt = t(dd); out.append(w(2 * np.pi * f_ * tt) * env(len(tt), 0.005, dd * 0.4) if f_ else np.zeros(len(tt)))
    return np.concatenate(out)
save('catch', tune([(784, .07), (1047, .07), (1319, .12)]), 0.45)
save('rescue', tune([(523, .09), (659, .09), (784, .09), (1047, .25)]), 0.5)
save('extra', tune([(1568, .08), (2093, .08), (1568, .08), (2093, .2)]), 0.45)
save('start', tune([(392, .12), (523, .12), (659, .12), (784, .24), (0, .06), (659, .12), (784, .45)]), 0.5)
save('wave', tune([(659, .1), (784, .1), (988, .1), (1319, .35)]), 0.5)
save('gameover', tune([(523, .3), (494, .3), (466, .3), (440, .9)], lambda p: np.sin(p) * 0.6 + sq(p) * 0.2), 0.5)
save('click', np.sin(2 * np.pi * 1200 * t(0.04)) * np.exp(-t(0.04) * 60), 0.4)
d = 2.0; tt = t(d); save('thrust', lp(noise(d), 0.05) * (0.8 + 0.2 * np.sin(2 * np.pi * 7 * tt)), 0.25)
d = 1.6; save('planetboom', lp(noise(d), 0.06) * np.exp(-t(d) * 1.5) + sweep(120, 20, d) * np.exp(-t(d) * 1.2), 0.9)
print('ok')
