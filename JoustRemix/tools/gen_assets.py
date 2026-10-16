# Procedural assets for Joust Remix: dusk-planet HDR skybox, tileable sky backdrop, WAV sfx.
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

# skybox (IBL): smoky volcanic cavern, warm low glow from lava below, cool blue above
W, H = 512, 256
v = (np.arange(H) + .5) / H
y = np.sin(np.repeat(((0.5 - v) * np.pi)[:, None], W, 1))
img = np.zeros((H, W, 3)) + np.array([0.02, 0.02, 0.035])
img += np.clip(-y, 0, 1)[..., None] ** 0.7 * np.array([0.9, 0.3, 0.08])
img += np.clip(1 - np.abs(y) * 4, 0, 1)[..., None] ** 2 * np.array([0.35, 0.14, 0.08])
img += np.clip(y, 0, 1)[..., None] * np.array([0.05, 0.08, 0.16])
def rgbe(a):
    m = a.max(-1); e = np.ceil(np.log2(np.maximum(m, 1e-32))); sc = np.where(m > 1e-32, 256.0 / 2 ** e, 0)
    out = np.zeros(a.shape[:2] + (4,), np.uint8)
    out[..., :3] = np.clip(a * sc[..., None], 0, 255).astype(np.uint8); out[..., 3] = np.where(m > 1e-32, e + 128, 0).astype(np.uint8); return out
with open(f'{A}/Skybox/cavern.hdr', 'wb') as f:
    f.write(b"#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y %d +X %d\n" % (H, W)); f.write(rgbe(img.astype(np.float32)).tobytes())
# backdrop (2048x1024): deep twilight sky with drifting ash clouds, a big moon glow, ember haze at bottom
TH, TW = 1024, 2048
yy = np.linspace(0, 1, TH)[:, None] * np.ones((1, TW)); xx = np.linspace(0, 1, TW)[None, :] * np.ones((TH, 1))
n1 = fbm_tile(TH, TW, 1); n2 = fbm_tile(TH, TW, 2, 2.3); n3 = fbm_tile(TH, TW, 3, 1.7)
sky = (1 - yy)[..., None] * np.array([0.02, 0.025, 0.07]) + (yy ** 2.5)[..., None] * np.array([0.35, 0.1, 0.06]) + (yy ** 7)[..., None] * np.array([0.7, 0.25, 0.05])
moon = np.exp(-(((xx - 0.68) * 2) ** 2 + (yy - 0.22) ** 2) / 0.004); halo = np.exp(-(((xx - 0.68) * 2) ** 2 + (yy - 0.22) ** 2) / 0.05)
sky += moon[..., None] * np.array([0.9, 0.85, 0.75]) + halo[..., None] * np.array([0.12, 0.13, 0.2])
cloud = ramp(n1 * 0.6 + n2 * 0.4, 0.45, 0.85) * np.exp(-((yy - 0.45) / 0.3) ** 2)
sky = sky * (1 - 0.6 * cloud[..., None]) + cloud[..., None] * (np.array([0.12, 0.07, 0.09]) + (yy ** 2)[..., None] * np.array([0.35, 0.12, 0.04]))
stars = np.zeros((TH, TW))
for k in range(4000):
    a, b = rng.integers(0, TH), rng.integers(0, TW); stars[a, b] = rng.random() ** 3 * 0.9 + 0.05
sky += (stars * (1 - yy) ** 2 * (1 - cloud))[..., None]
Image.fromarray((np.clip(sky, 0, 1) * 255).astype(np.uint8)).save(f'{A}/Textures/sky.png')
n = fbm_tile(512, 512, 7, 1.6); n2 = fbm_tile(512, 512, 8, 2.4); n3 = fbm_tile(512, 512, 9, 1.2)
rock = (0.22 + 0.65 * n)[..., None] * np.array([0.42, 0.36, 0.34]) + ramp(n2, 0.62, 0.9)[..., None] * np.array([0.12, 0.09, 0.05]) - ramp(n3, 0.7, 0.9)[..., None] * 0.08
Image.fromarray((np.clip(rock, 0, 1) * 255).astype(np.uint8)).save(f'{A}/Textures/rock.png')
ln = fbm_tile(512, 512, 12, 1.5); ln2 = fbm_tile(512, 512, 13, 2.2)
cr = ramp(np.abs(ln - 0.5), 0.0, 0.08)
lava = (1 - cr)[..., None] * np.array([1.0, 0.55, 0.12]) * (0.7 + 0.5 * ln2[..., None]) + cr[..., None] * np.array([0.25, 0.04, 0.01]) * (0.5 + ln2[..., None])
Image.fromarray((np.clip(lava, 0, 1) * 255).astype(np.uint8)).save(f'{A}/Textures/lava.png')
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
def tune(mel, w=lambda p: sq(p) * 0.35 + np.sin(p) * 0.45):
    out = []
    for f_, dd in mel:
        tt = t(dd); out.append(w(2 * np.pi * f_ * tt) * env(len(tt), 0.005, dd * 0.4) if f_ else np.zeros(len(tt)))
    return np.concatenate(out)

d = 0.16; tt = t(d); save('flap', lp(noise(d), 0.25) * np.sin(np.pi * tt / d) ** 2 + 0.3 * np.sin(2 * np.pi * 140 * tt) * np.exp(-tt * 30), 0.35)
d = 0.35; save('clash', (noise(d) * 0.4 + np.sin(2 * np.pi * 2400 * t(d)) * 0.5 + np.sin(2 * np.pi * 3170 * t(d)) * 0.4) * np.exp(-t(d) * 14), 0.6)
d = 0.25; save('bounce', sweep(900, 300, d, sq) * 0.4 * np.exp(-t(d) * 12) + lp(noise(d), 0.3) * np.exp(-t(d) * 20), 0.45)
d = 0.9; save('boom', lp(noise(d), 0.12) * np.exp(-t(d) * 4.5) + sweep(260, 30, d) * np.exp(-t(d) * 4) * 0.9, 0.8)
d = 1.8; save('death', lp(noise(d), 0.08) * np.exp(-t(d) * 1.8) + sweep(500, 30, d, sq) * 0.35 * np.exp(-t(d) * 2), 0.85)
d = 0.5; save('lava', lp(noise(d), 0.06) * np.exp(-t(d) * 4) + sweep(200, 50, d) * 0.5 * np.exp(-t(d) * 5), 0.7)
d = 1.0; tt = t(d); save('grab', np.sin(2 * np.pi * np.cumsum(120 - 60 * tt / d + 20 * np.sin(2 * np.pi * 8 * tt)) / SR) * env(len(tt), 0.02, 0.3), 0.6)
d = 0.4; save('hatch', lp(noise(d), 0.5) * np.exp(-t(d) * 25) + tune([(880, .08), (1175, .08), (1568, .14)]).tolist()[:int(d * SR)] + [0] * 0 if False else np.concatenate([lp(noise(0.08), 0.5) * np.exp(-t(0.08) * 30), tune([(988, .07), (784, .07), (1175, .14)])]), 0.45)
d = 0.1; save('step', lp(noise(d), 0.3) * np.exp(-t(d) * 50), 0.18)
d = 0.35; save('skid', lp(noise(d), 0.5) * env(int(d * SR), 0.01, 0.15), 0.25)
save('egg', tune([(1047, .06), (1319, .06), (1568, .06), (2093, .12)]), 0.45)
save('extra', tune([(1568, .08), (2093, .08), (1568, .08), (2093, .2)]), 0.45)
save('start', tune([(392, .12), (523, .12), (659, .12), (784, .24), (0, .06), (659, .12), (784, .45)]), 0.5)
save('wave', tune([(523, .1), (659, .1), (784, .1), (1047, .35)]), 0.5)
save('gameover', tune([(523, .3), (494, .3), (466, .3), (440, .9)], lambda p: np.sin(p) * 0.6 + sq(p) * 0.2), 0.5)
save('click', np.sin(2 * np.pi * 1200 * t(0.04)) * np.exp(-t(0.04) * 60), 0.4)
save('spawn', sweep(200, 1400, 0.5) * env(int(0.5 * SR), 0.02, 0.2), 0.35)
print('ok')
