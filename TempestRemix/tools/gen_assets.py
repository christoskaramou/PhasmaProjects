# Procedural assets for Tempest Remix: dark void HDR, rail glow texture, WAV sfx
import numpy as np, os, wave
from PIL import Image
A = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'project', 'Assets')
for sub in ('Skybox', 'Textures', 'Audio', 'Save'):
    os.makedirs(f'{A}/{sub}', exist_ok=True)
rng = np.random.default_rng(42)

def rgbe(a):
    m = a.max(-1); e = np.ceil(np.log2(np.maximum(m, 1e-32))); sc = np.where(m > 1e-32, 256.0 / 2 ** e, 0)
    out = np.zeros(a.shape[:2] + (4,), np.uint8)
    out[..., :3] = np.clip(a * sc[..., None], 0, 255).astype(np.uint8)
    out[..., 3] = np.where(m > 1e-32, e + 128, 0).astype(np.uint8); return out

# ---------- skybox: deep void with teal/amber horizon glows
W, H = 512, 256
v = (np.arange(H) + .5) / H; u = (np.arange(W) + .5) / W
EL, AZ = np.meshgrid((0.5 - v) * np.pi, (u - 0.5) * 2 * np.pi, indexing='ij')
x = np.cos(EL) * np.cos(AZ); z = np.cos(EL) * np.sin(AZ); y = np.sin(EL)
img = np.zeros((H, W, 3)) + np.array([0.0015, 0.002, 0.004])
def blob(d, size, col):
    global img
    d = np.array(d, float); d /= np.linalg.norm(d)
    ang = np.arccos(np.clip(x * d[0] + y * d[1] + z * d[2], -1, 1))
    img += np.exp(-(ang / size) ** 2)[..., None] * np.array(col)
blob((0, 0.2, 1), 0.55, (0.04, 0.35, 0.55))
blob((0.9, -0.1, 0.3), 0.4, (0.55, 0.2, 0.05))
blob((-0.8, 0.3, 0.4), 0.45, (0.15, 0.08, 0.45))
blob((0, -1, 0), 0.8, (0.01, 0.02, 0.04))
# sparse stars
for _ in range(800):
    i, j = rng.integers(0, H), rng.integers(0, W)
    b = rng.random() ** 2 * 0.9 + 0.05
    img[i, j] += b * np.array([0.9, 0.95, 1.1])
with open(f'{A}/Skybox/void.hdr', 'wb') as f:
    f.write(b"#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y %d +X %d\n" % (H, W))
    f.write(rgbe(img.astype(np.float32)).tobytes())
print('skybox ok')

# ---------- subtle grid / energy texture for rails
TH, TW = 512, 512
yy, xx = np.mgrid[0:TH, 0:TW]
g = np.zeros((TH, TW, 3))
# soft scanlines
g[..., 0] = 0.15 + 0.1 * np.sin(yy / TH * 40 * np.pi)
g[..., 1] = 0.45 + 0.15 * np.sin(yy / TH * 40 * np.pi)
g[..., 2] = 0.7 + 0.2 * np.sin(yy / TH * 40 * np.pi)
edge = ((xx < 8) | (xx > TW - 9) | (yy < 8) | (yy > TH - 9)).astype(float)
g += edge[..., None] * np.array([0.4, 0.9, 1.2])
Image.fromarray((np.clip(g, 0, 1) * 255).astype(np.uint8)).save(f'{A}/Textures/energy.png')
# particle soft disc
P = 64
cy, cx = np.mgrid[0:P, 0:P]
r = np.sqrt((cx - P/2)**2 + (cy - P/2)**2) / (P/2)
disc = np.clip(1 - r, 0, 1) ** 2
Image.fromarray((disc * 255).astype(np.uint8)).save(f'{A}/Textures/soft.png')
print('textures ok')

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
        tt = t(dd)
        out.append(wav(2 * np.pi * f_ * tt) * env(len(tt), 0.005, dd * 0.4) if f_ else np.zeros(len(tt)))
    return np.concatenate(out)

# zapper shot: bright rising chirp
s = sweep(400, 2800, 0.12, lambda p: 0.5 * sq(p) + 0.5 * np.sin(p)) * np.exp(-t(0.12) * 14); save('shoot', s, 0.4)
# hit
d = 0.28; s = lp(noise(d), 0.4) * np.exp(-t(d) * 14) + sweep(1200, 200, d) * np.exp(-t(d) * 12) * 0.7; save('hit', s, 0.55)
# boom
d = 0.7; s = lp(noise(d), 0.12) * np.exp(-t(d) * 5) + sweep(400, 40, d) * np.exp(-t(d) * 4) * 0.8; save('boom', s, 0.75)
# death
d = 1.4; s = lp(noise(d), 0.1) * np.exp(-t(d) * 2.5) + sweep(500, 50, d, sq) * 0.45 * np.exp(-t(d) * 2.8); save('death', s, 0.8)
# superzapper
d = 1.0; tt = t(d); f = 200 + 1800 * (tt / d) + 80 * np.sin(2 * np.pi * 30 * tt)
s = (np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.4 * sq(2 * np.pi * np.cumsum(f * 0.5) / SR)) * env(len(tt), 0.02, 0.25); save('zap', s, 0.7)
# flipper flip
d = 0.18; s = sweep(600, 1400, d, sq) * np.exp(-t(d) * 16); save('flip', s, 0.35)
# level clear
save('clear', tune([(523, .1), (659, .1), (784, .1), (1047, .35), (784, .1), (1047, .45)]), 0.5)
# start / extra
save('start', tune([(392, .12), (523, .12), (659, .12), (784, .28), (0, .06), (659, .12), (1047, .4)]), 0.5)
save('extra', tune([(1047, .08), (1319, .08), (1568, .08), (2093, .22)]), 0.45)
save('click', np.sin(2 * np.pi * 1400 * t(0.035)) * np.exp(-t(0.035) * 55), 0.4)
save('gameover', tune([(392, .28), (370, .28), (349, .28), (330, .85)], lambda p: np.sin(p) * 0.6 + sq(p) * 0.2), 0.5)
# enemy spawn blip
d = 0.1; s = sweep(200, 900, d) * np.exp(-t(d) * 18); save('spawn', s, 0.3)
# spike plant
d = 0.2; s = sweep(800, 200, d, sq) * np.exp(-t(d) * 12); save('spike', s, 0.35)
print('sfx ok')
