# Procedural assets for Q*bert Remix: deep-space HDR skybox (IBL), tileable nebula textures, WAV sfx.
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
def rgbe(a):
    m = a.max(-1); e = np.ceil(np.log2(np.maximum(m, 1e-32))); sc = np.where(m > 1e-32, 256.0 / 2 ** e, 0)
    out = np.zeros(a.shape[:2] + (4,), np.uint8)
    out[..., :3] = np.clip(a * sc[..., None], 0, 255).astype(np.uint8); out[..., 3] = np.where(m > 1e-32, e + 128, 0).astype(np.uint8); return out
# ---------- skybox: deep indigo dusk with soft teal + magenta glows (reflections + IBL)
img = np.zeros((H, W, 3)) + np.array([0.004, 0.003, 0.012])
img += np.clip(1 - np.abs(EL) / 1.2, 0, 1)[..., None] ** 3 * np.array([0.03, 0.015, 0.06])
blob((0, 0.9, 0.3), 0.7, (1.0, 0.9, 1.3)); blob((-0.9, 0.1, 0.4), 0.6, (0.1, 0.8, 1.1)); blob((0.9, 0.1, 0.4), 0.6, (1.2, 0.3, 0.9))
blob((0.2, 0.2, 1.0), 0.35, (0.4, 0.25, 0.1))
with open(f'{A}/Skybox/dusk.hdr', 'wb') as f:
    f.write(b"#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y %d +X %d\n" % (H, W)); f.write(rgbe(img.astype(np.float32)).tobytes())
# ---------- backdrop texture: soft nebula haze + bokeh dots (used as emissive on a big far quad)
TH = TW = 1024
n1 = fbm_tile(TH, TW, seed=1); n2 = fbm_tile(TH, TW, seed=2); n3 = fbm_tile(TH, TW, seed=5)
def ramp(n, lo, hi): return np.clip((n - lo) / (hi - lo), 0, 1)
yy, xx = np.mgrid[0:TH, 0:TW] / TH
vign = np.clip(1.2 - 1.5 * np.hypot(xx - 0.5, yy - 0.45), 0, 1)
bg = (ramp(n1, 0.4, 0.95) ** 1.7)[..., None] * np.array([0.28, 0.08, 0.42]) + (ramp(n2, 0.5, 0.95) ** 1.8)[..., None] * np.array([0.03, 0.25, 0.4])
bg += (ramp(n3, 0.65, 0.98) ** 2)[..., None] * np.array([0.45, 0.2, 0.35])
bg = bg * (0.35 + 0.65 * vign[..., None]) + np.array([0.01, 0.008, 0.03])
for k in range(160):
    cy, cx, r = rng.random(), rng.random(), rng.uniform(0.002, 0.012); b = rng.random() ** 2 * 0.6 + 0.1
    col = np.array([[1, .6, .9], [.5, .8, 1], [1, .85, .5]][k % 3]) * b
    bg += np.exp(-((xx - cx) ** 2 + (yy - cy) ** 2) / (r * r))[..., None] * col
Image.fromarray((np.clip(bg, 0, 1) * 255).astype(np.uint8)).save(f'{A}/Textures/backdrop.png')
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
# hop: soft springy boing
d = 0.13; s = sweep(380, 760, d) * np.exp(-t(d) * 22) + 0.3 * sweep(760, 1500, d) * np.exp(-t(d) * 30); save('hop', s, 0.4)
d = 0.09; s = sweep(220, 120, d) * np.exp(-t(d) * 40) + lp(noise(d), 0.3) * np.exp(-t(d) * 60) * 0.4; save('land', s, 0.35)
d = 0.12; s = sweep(300, 180, d, sq) * np.exp(-t(d) * 28); save('ehop', s, 0.22)
d = 0.12; s = sweep(160, 90, d, lambda p: 0.6 * np.sin(p) + 0.4 * sq(p)) * np.exp(-t(d) * 25); save('coily', s, 0.35)
d = 1.3; s = sweep(1600, 120, d) * env(int(d * SR), 0.01, 0.3); save('fall', s, 0.45)
# Q*bert "curse": garbled synthetic babble
seg = [sweep(rng.uniform(300, 700), rng.uniform(200, 900), 0.07, lambda p: sq(p) * 0.5 + np.sin(p * 1.5) * 0.5) * env(int(0.07 * SR), 0.005, 0.02) for _ in range(9)]
save('curse', np.concatenate(seg) * np.repeat(rng.uniform(0.6, 1, 9), int(0.07 * SR)), 0.5)
d = 1.4; tt = t(d); f = 300 + 900 * tt / d + 60 * np.sin(2 * np.pi * 10 * tt); s = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(len(tt), 0.02, 0.3); save('disc', s, 0.4)
save('freeze', tune([(1568, .06), (1319, .06), (1047, .06), (784, .06), (1047, .06), (1319, .06), (1568, .2)], np.sin), 0.4)
save('catch', tune([(1047, .06), (1568, .12)]), 0.4)
save('bonus', tune([(784, .08), (988, .08), (1175, .08), (1568, .2)]), 0.45)
save('clear', tune([(523, .1), (659, .1), (784, .1), (1047, .1), (784, .1), (1047, .1), (1319, .1), (1568, .4)]), 0.5)
save('start', tune([(392, .12), (523, .12), (659, .12), (784, .24), (659, .12), (784, .4)]), 0.5)
save('gameover', tune([(523, .3), (494, .3), (466, .3), (440, .9)], lambda p: np.sin(p) * 0.6 + sq(p) * 0.2), 0.5)
save('click', np.sin(2 * np.pi * 1200 * t(0.04)) * np.exp(-t(0.04) * 60), 0.4)
save('extra', tune([(1568, .08), (2093, .08), (1568, .08), (2093, .2)]), 0.45)
d = 0.4; s = lp(noise(d), 0.3) * np.exp(-t(d) * 10) + sweep(700, 90, d) * np.exp(-t(d) * 8) * 0.5; save('pop', s, 0.5)
d = 0.25; s = sweep(900, 300, d, sq) * np.exp(-t(d) * 12); save('hatch', s, 0.35)
print('assets ok')
