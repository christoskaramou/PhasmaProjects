# Procedural assets for Galaga Remix: deep-space HDR skybox (IBL), tileable nebula textures, WAV sfx.
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

# ---------- nebula tile (vertically + horizontally tileable): gas clouds, dust lanes, dense faint star dust
TH, TW = 1024, 1024
n1 = fbm_tile(TH, TW, seed=1); n2 = fbm_tile(TH, TW, seed=2); n3 = fbm_tile(TH, TW, seed=3); n4 = fbm_tile(TH, TW, seed=4)
def ramp(n, lo, hi): return np.clip((n - lo) / (hi - lo), 0, 1)
gas_a = ramp(n1, 0.45, 0.9) ** 1.6; gas_b = ramp(n2, 0.5, 0.92) ** 1.8; dust = ramp(n3, 0.35, 0.75)
neb = gas_a[..., None] * np.array([0.35, 0.08, 0.55]) + gas_b[..., None] * np.array([0.04, 0.32, 0.55])
neb += (gas_a * gas_b)[..., None] * np.array([0.9, 0.4, 0.8])
neb += ramp(n4, 0.6, 0.95)[..., None] ** 2 * np.array([0.5, 0.1, 0.25])
neb *= (1 - 0.75 * dust)[..., None]
neb += np.array([0.006, 0.004, 0.018])
stars = np.zeros((TH, TW))
for k in range(5000):
    yy, xx = rng.integers(0, TH), rng.integers(0, TW); stars[yy, xx] = rng.random() ** 3 * 1.2 + 0.08
for k in range(220):
    yy, xx = rng.integers(1, TH - 1), rng.integers(1, TW - 1); b = rng.random() * 0.6 + 0.6
    stars[yy, xx] = b * 2; stars[yy - 1:yy + 2, xx] += b * 0.35; stars[yy, xx - 1:xx + 2] += b * 0.35
tint = np.stack([np.ones_like(stars), 0.9 + 0.1 * n2, 0.85 + 0.3 * n1], -1)
neb = neb + stars[..., None] * tint * (0.6 + 0.4 * (1 - dust))[..., None]
Image.fromarray((np.clip(neb, 0, 1) ** (1 / 1.0) * 255).astype(np.uint8)).save(f'{A}/Textures/nebula.png')
# second, sparser parallax layer: wispy foreground gas only (blended additively via emissive on a dim quad)
wisp = ramp(fbm_tile(TH, TW, seed=9), 0.62, 0.95) ** 2
wl = wisp[..., None] * np.array([0.25, 0.12, 0.4]) + ramp(fbm_tile(TH, TW, seed=11), 0.7, 0.98)[..., None] ** 2 * np.array([0.05, 0.3, 0.35])
Image.fromarray((np.clip(wl, 0, 1) * 255).astype(np.uint8)).save(f'{A}/Textures/wisps.png')

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
# player shot: bright descending zap
s = sweep(2400, 500, 0.16, lambda p: 0.6 * sq(p) + 0.4 * np.sin(p)) * np.exp(-t(0.16) * 18); save('shoot', s, 0.45)
# enemy hit / explosion small
d = 0.35; s = lp(noise(d), 0.35) * np.exp(-t(d) * 12) + sweep(900, 80, d) * np.exp(-t(d) * 10) * 0.6; save('hit', s, 0.6)
d = 0.8; s = lp(noise(d), 0.15) * np.exp(-t(d) * 5) + sweep(300, 30, d) * np.exp(-t(d) * 4) * 0.8; save('boom', s, 0.8)
d = 0.22; s = sq(2 * np.pi * 660 * t(d)) * 0.5 * np.exp(-t(d) * 14) + sq(2 * np.pi * 990 * t(d)) * 0.3 * np.exp(-t(d) * 20); save('bosshit', s, 0.5)
d = 1.6; s = lp(noise(d), 0.1) * np.exp(-t(d) * 2.2) + sweep(600, 40, d, sq) * 0.4 * np.exp(-t(d) * 2.5); save('death', s, 0.85)
# dive whistle (classic descending warble)
d = 0.9; tt = t(d); f = 1400 - 900 * tt / d + 80 * np.sin(2 * np.pi * 9 * tt); s = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(len(tt), 0.02, 0.2); save('dive', s, 0.35)
# tractor beam: pulsing hum with rising sweep
d = 2.6; tt = t(d); f = 220 + 140 * (tt / d) + 40 * np.sin(2 * np.pi * 7 * tt)
s = (np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.5 * np.sin(4 * np.pi * np.cumsum(f) / SR)) * (0.6 + 0.4 * np.sin(2 * np.pi * 12 * tt)) * env(len(tt), 0.1, 0.3); save('beam', s, 0.5)
# captured: falling arpeggio
notes = [880, 740, 622, 523, 440, 370]; s = np.concatenate([sq(2 * np.pi * f_ * t(0.12)) * np.exp(-t(0.12) * 8) for f_ in notes]); save('captured', s, 0.45)
# rescue / dual fighter fanfare
notes = [523, 659, 784, 1047, 784, 1047]; s = np.concatenate([(sq(2 * np.pi * f_ * t(0.1)) * 0.5 + np.sin(2 * np.pi * f_ * 2 * t(0.1)) * 0.3) * env(int(0.1 * SR), 0.005, 0.03) for f_ in notes]); save('rescue', s, 0.5)
# stage start jingle (original-inspired, not copied)
mel = [(523, .12), (659, .12), (784, .12), (659, .12), (784, .12), (988, .12), (1047, .36), (0, .08), (784, .12), (1047, .5)]
def tune(mel, wav=lambda p: sq(p) * 0.4 + np.sin(p) * 0.4):
    out = []
    for f_, dd in mel:
        tt = t(dd); out.append(wav(2 * np.pi * f_ * tt) * env(len(tt), 0.005, dd * 0.4) if f_ else np.zeros(len(tt)))
    return np.concatenate(out)
bass = tune([(262, .36), (330, .36), (392, .44), (523, .62)], np.sin)
m = tune(mel); bb = np.zeros_like(m); bb[:len(bass)] = bass[:len(m)]; save('start', m + 0.5 * bb, 0.55)
save('challenge', tune([(784, .1), (988, .1), (1175, .1), (1568, .25), (0, .05), (1175, .1), (1568, .4)]), 0.5)
save('perfect', tune([(1047, .1), (1319, .1), (1568, .1), (2093, .3), (1568, .1), (2093, .6)]), 0.5)
save('extra', tune([(1568, .08), (2093, .08), (1568, .08), (2093, .2)]), 0.45)
save('badge', np.sin(2 * np.pi * 1760 * t(0.06)) * np.exp(-t(0.06) * 40), 0.35)
save('click', np.sin(2 * np.pi * 1200 * t(0.04)) * np.exp(-t(0.04) * 60), 0.4)
save('gameover', tune([(523, .3), (494, .3), (466, .3), (440, .9)], lambda p: np.sin(p) * 0.6 + sq(p) * 0.2), 0.5)
d = 0.5; s = lp(noise(d), 0.5) * np.exp(-t(d) * 9) * 0.6 + sweep(200, 1800, d) * np.exp(-t(d) * 4) * 0.5; save('release', s, 0.5)
d = 0.12; s = sweep(300, 900, d, sq) * np.exp(-t(d) * 20); save('eshot', s, 0.25)
print('assets ok')
# ---------- gas giant texture (equirect bands + storms)
PW, PH = 1024, 512
yy = (np.arange(PH) + .5) / PH
nz = fbm_tile(PH, PW, seed=21)
lat = yy[:, None] + 0.04 * (nz - 0.5) + 0.01 * np.sin(np.arange(PW)[None, :] / PW * 2 * np.pi * 3)
band = 0.5 + 0.5 * np.sin(lat * 38) * np.sin(lat * 7 + 1)
c1, c2, c3 = np.array([0.55, 0.32, 0.62]), np.array([0.2, 0.35, 0.7]), np.array([0.9, 0.6, 0.75])
pl = c1 * band[..., None] + c2 * (1 - band[..., None]) + c3 * (ramp(nz, 0.7, 0.95) ** 2)[..., None] * 0.6
Image.fromarray((np.clip(pl, 0, 1) * 255).astype(np.uint8)).save(f'{A}/Textures/planet.png')
print('planet ok')
