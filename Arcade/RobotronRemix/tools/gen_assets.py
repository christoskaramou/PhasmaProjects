# Procedural assets for Robotron Remix: deep-space HDR skybox (IBL), tileable nebula textures, WAV sfx.
import numpy as np, os, wave
from PIL import Image
A = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'project', 'Assets')
rng = np.random.default_rng(7)

def fbm_tile(h, w, octaves=6, base=4, seed=0):
    """tileable fractal noise via spectral synthesis (wraps in both axes)"""
    r = np.random.default_rng(seed)
    fy = np.fft.fftfreq(h)[:, None] * h; fx = np.fft.fftfreq(w)[None, :] * w
    f = np.sqrt(fx ** 2 + fy ** 2); f[0, 0] = 1
    spec = (r.normal(size=(h, w)) + 1j * r.normal(size=(h, w))) / f ** 1.9
    spec[f < base * 0.5] *= 0.5
    n = np.real(np.fft.ifft2(spec)); n = (n - n.min()) / (n.max() - n.min()); return n

# ---------- skybox: very dark space with faint violet/teal glows (reflections on glossy hulls)
W, H = 512, 256
v = (np.arange(H) + .5) / H; u = (np.arange(W) + .5) / W
EL, AZ = np.meshgrid((0.5 - v) * np.pi, (u - 0.5) * 2 * np.pi, indexing='ij')
x = np.cos(EL) * np.cos(AZ); z = np.cos(EL) * np.sin(AZ); y = np.sin(EL)
img = np.zeros((H, W, 3)) + np.array([0.002, 0.002, 0.006])
def blob(d, size, col):
    global img
    d = np.array(d, float); d /= np.linalg.norm(d)
    ang = np.arccos(np.clip(x * d[0] + y * d[1] + z * d[2], -1, 1))
    img += np.exp(-(ang / size) ** 2)[..., None] * np.array(col)
blob((0, 0.8, 0.6), 0.5, (0.9, 0.85, 1.1)); blob((-0.9, 0.2, 0.3), 0.4, (0.05, 0.5, 0.9)); blob((0.9, 0.1, 0.3), 0.4, (0.9, 0.15, 0.7))
blob((0, -0.3, 1), 1.0, (0.02, 0.01, 0.05))
def rgbe(a):
    m = a.max(-1); e = np.ceil(np.log2(np.maximum(m, 1e-32))); sc = np.where(m > 1e-32, 256.0 / 2 ** e, 0)
    out = np.zeros(a.shape[:2] + (4,), np.uint8)
    out[..., :3] = np.clip(a * sc[..., None], 0, 255).astype(np.uint8); out[..., 3] = np.where(m > 1e-32, e + 128, 0).astype(np.uint8); return out
with open(f'{A}/Skybox/space.hdr', 'wb') as f:
    f.write(b"#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y %d +X %d\n" % (H, W)); f.write(rgbe(img.astype(np.float32)).tobytes())

# ---------- arena floor: dark brushed panels with thin seams (base) + emissive circuit glow map
TH = 512
yy, xx = np.mgrid[0:TH, 0:TH] / TH
n = fbm_tile(TH, TH, seed=5)
cell = 1 / 4
fx, fy = (xx % cell) / cell, (yy % cell) / cell
seam = np.minimum(np.minimum(fx, 1 - fx), np.minimum(fy, 1 - fy))
base = 0.22 + 0.08 * n + 0.02 * np.sin(xx * 900) * 0.3
base = np.where(seam < 0.012, 0.03, base)
Image.fromarray((np.clip(np.stack([base * 0.9, base * 0.95, base * 1.15], -1), 0, 1) * 255).astype(np.uint8)).save(f'{A}/Textures/floor.png')
glow = np.exp(-(seam / 0.008) ** 2) * 0.9
ctr = np.exp(-(((fx - 0.5) ** 2 + (fy - 0.5) ** 2) / 0.0009)) * 0.6
traces = (np.abs(fbm_tile(TH, TH, seed=8) - 0.5) < 0.006) * 0.5
g = np.clip(glow + ctr + traces, 0, 1)
Image.fromarray((np.stack([g * 0.25, g * 0.7, g * 1.0], -1) * 255).astype(np.uint8)).save(f'{A}/Textures/floor_glow.png')
# ---------- sfx
SR = 44100
def save(name, s, vol=0.8):
    s = np.asarray(s, float); s = s / (np.abs(s).max() + 1e-9) * vol
    d = (np.clip(s, -1, 1) * 32000).astype(np.int16)
    with wave.open(f'{A}/Audio/{name}.wav', 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(d.tobytes())
def t(d): return np.arange(int(SR * d)) / SR
def env(n, a=0.005, r=None):
    e = np.ones(n); ai = max(1, int(a * SR)); e[:ai] = np.linspace(0, 1, ai)
    if r: ri = min(n, int(r * SR)); e[-ri:] *= np.linspace(1, 0, ri) ** 2
    return e
def sq(ph): return np.sign(np.sin(ph))
def sweep(f0, f1, d, wave_=np.sin):
    tt = t(d); f = f0 * (f1 / f0) ** (tt / d); return wave_(2 * np.pi * np.cumsum(f) / SR)
def noise(d): return rng.uniform(-1, 1, int(SR * d))
def lp(x, a=0.2):
    y = np.zeros_like(x); acc = 0
    for i, v in enumerate(x): acc += a * (v - acc); y[i] = acc
    return y
def tune(mel, wav=lambda p: sq(p) * 0.4 + np.sin(p) * 0.4):
    out = []
    for f_, dd in mel:
        tt = t(dd); out.append(wav(2 * np.pi * f_ * tt) * env(len(tt), 0.005, dd * 0.4) if f_ else np.zeros(len(tt)))
    return np.concatenate(out)
s = sweep(1800, 700, 0.09, lambda p: 0.5 * sq(p) + 0.5 * np.sin(p)) * np.exp(-t(0.09) * 25); save('shoot', s, 0.3)
d = 0.35; s = lp(noise(d), 0.35) * np.exp(-t(d) * 12) + sweep(900, 80, d) * np.exp(-t(d) * 10) * 0.6; save('hit', s, 0.55)
d = 0.8; s = lp(noise(d), 0.15) * np.exp(-t(d) * 5) + sweep(300, 30, d) * np.exp(-t(d) * 4) * 0.8; save('boom', s, 0.8)
d = 1.6; s = lp(noise(d), 0.1) * np.exp(-t(d) * 2.2) + sweep(600, 40, d, sq) * 0.4 * np.exp(-t(d) * 2.5); save('death', s, 0.85)
d = 0.12; s = sq(2 * np.pi * 90 * t(d)) * np.exp(-t(d) * 20) + lp(noise(d), 0.2) * np.exp(-t(d) * 30); save('thud', s, 0.4)
d = 0.12; s = sweep(300, 900, d, sq) * np.exp(-t(d) * 20); save('eshot', s, 0.25)
save('rescue', tune([(784, .07), (988, .07), (1175, .07), (1568, .16)]), 0.45)
save('lost', tune([(600, .08), (450, .08), (300, .2)], np.sin), 0.4)
save('start', tune([(392, .1), (523, .1), (659, .1), (784, .1), (1047, .3), (0, .05), (784, .1), (1047, .4)]), 0.5)
save('wave', tune([(659, .08), (784, .08), (988, .08), (1319, .25)]), 0.45)
save('extra', tune([(1568, .08), (2093, .08), (1568, .08), (2093, .2)]), 0.45)
save('click', np.sin(2 * np.pi * 1200 * t(0.04)) * np.exp(-t(0.04) * 60), 0.4)
save('gameover', tune([(523, .3), (494, .3), (466, .3), (440, .9)], lambda p: np.sin(p) * 0.6 + sq(p) * 0.2), 0.5)
d = 0.4; tt = t(d); s = np.sin(2 * np.pi * np.cumsum(200 + 1600 * tt / d) / SR) * env(len(tt), 0.01, 0.1) * 0.5; save('spawn', s, 0.3)
print('assets ok')
