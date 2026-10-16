# Procedural assets for Dig Dug Remix: textures + WAV sfx
import numpy as np, os, wave
from PIL import Image
A = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'project', 'Assets')
rng = np.random.default_rng(3)
def fbm(h, w, seed=0, p=1.9):
    r = np.random.default_rng(seed)
    fy = np.fft.fftfreq(h)[:, None] * h; fx = np.fft.fftfreq(w)[None, :] * w
    f = np.sqrt(fx ** 2 + fy ** 2); f[0, 0] = 1
    n = np.real(np.fft.ifft2((r.normal(size=(h, w)) + 1j * r.normal(size=(h, w))) / f ** p)); return (n - n.min()) / (n.max() - n.min())
def ramp(n, a, b): return np.clip((n - a) / (b - a), 0, 1)
# tunnel back wall: dark packed earth, roots, faint stones (tileable)
H = W = 1024
n1, n2, n3 = fbm(H, W, 1), fbm(H, W, 2, 1.4), fbm(H, W, 3, 2.3)
col = np.array([0.10, 0.06, 0.04]) * (0.55 + 0.9 * n1)[..., None]
col += ramp(n2, 0.62, 0.8)[..., None] ** 2 * np.array([0.08, 0.06, 0.05])
roots = ramp(1 - np.abs(n3 - 0.5) * 2, 0.965, 1.0)
col = col * (1 - 0.6 * roots[..., None]) + roots[..., None] * np.array([0.05, 0.03, 0.02])
Image.fromarray((np.clip(col * 2.6, 0, 1) * 255).astype(np.uint8)).save(f'{A}/Textures/tunnel.png')
# sky: warm dawn gradient + soft clouds + layered distant hills (bottom of image = horizon)
H, W = 512, 1024
y = np.linspace(0, 1, H)[:, None, None]
sky = (1 - y) * np.array([0.10, 0.22, 0.55]) + y * np.array([1.0, 0.62, 0.38])
cl = ramp(fbm(H, W, 7, 2.1), 0.55, 0.85)[..., None] * np.clip(1.2 - y * 1.1, 0, 1)
sky = sky * (1 - 0.5 * cl) + cl * np.array([1.0, 0.85, 0.8]) * 0.6
x = np.linspace(0, 1, W)
for k, (base, amp, c) in enumerate([(0.72, 0.08, (0.32, 0.30, 0.48)), (0.8, 0.07, (0.18, 0.28, 0.3)), (0.88, 0.05, (0.1, 0.22, 0.14))]):
    hn = fbm(64, W, 20 + k, 2.2)[0]
    top = base - amp * (0.5 + 0.5 * np.sin(x * (5 + 3 * k) * np.pi + k)) - 0.06 * hn
    m = (np.linspace(0, 1, H)[:, None] > top[None, :])[..., None]
    sky = np.where(m, np.array(c), sky)
Image.fromarray((np.clip(sky, 0, 1) * 255).astype(np.uint8)).save(f'{A}/Textures/sky.png')
# sfx
SR = 44100
def save(name, s, vol=0.8):
    s = np.asarray(s, float); s = s / (np.abs(s).max() + 1e-9) * vol
    with wave.open(f'{A}/Audio/{name}.wav', 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes((np.clip(s, -1, 1) * 32000).astype(np.int16).tobytes())
def t(d): return np.arange(int(SR * d)) / SR
def sq(p): return np.sign(np.sin(p))
def sweep(f0, f1, d, wv=np.sin): tt = t(d); f = f0 * (f1 / f0) ** (tt / d); return wv(2 * np.pi * np.cumsum(f) / SR)
def noise(d): return rng.uniform(-1, 1, int(SR * d))
def lp(x, a):
    y = np.zeros_like(x); acc = 0
    for i, v in enumerate(x): acc += a * (v - acc); y[i] = acc
    return y
def env(n, a=0.005, r=None):
    e = np.ones(n); ai = max(1, int(a * SR)); e[:ai] = np.linspace(0, 1, ai)
    if r: ri = min(n, int(r * SR)); e[-ri:] *= np.linspace(1, 0, ri) ** 2
    return e
def tune(mel, wv=lambda p: sq(p) * 0.35 + np.sin(p) * 0.45):
    out = []
    for f_, dd in mel:
        tt = t(dd); out.append(wv(2 * np.pi * f_ * tt) * env(len(tt), 0.005, dd * 0.4) if f_ else np.zeros(len(tt)))
    return np.concatenate(out)
save('dig', lp(noise(0.09), 0.25) * np.exp(-t(0.09) * 30), 0.3)
save('pump', sweep(220, 520, 0.14, lambda p: 0.6 * sq(p) + 0.4 * np.sin(p)) * np.exp(-t(0.14) * 10), 0.4)
save('shoot', sweep(1200, 400, 0.16, np.sin) * np.exp(-t(0.16) * 12) + 0.3 * lp(noise(0.16), 0.5) * np.exp(-t(0.16) * 25), 0.4)
d = 0.4; save('pop', lp(noise(d), 0.6) * np.exp(-t(d) * 16) + sweep(900, 120, d) * np.exp(-t(d) * 9) * 0.7, 0.7)
d = 0.7; save('fire', lp(noise(d), 0.12) * env(int(SR * d), 0.05, 0.3) * (0.7 + 0.3 * np.sin(2 * np.pi * 18 * t(d))), 0.5)
d = 0.6; save('crush', lp(noise(d), 0.1) * np.exp(-t(d) * 6) + sweep(140, 40, d) * np.exp(-t(d) * 5), 0.8)
d = 0.5; save('wobble', np.sin(2 * np.pi * 90 * t(d)) * (0.5 + 0.5 * sq(2 * np.pi * 14 * t(d))) * env(int(SR * d), 0.01, 0.1) + 0.2 * lp(noise(d), 0.2), 0.45)
d = 0.4; save('break', lp(noise(d), 0.3) * np.exp(-t(d) * 10), 0.6)
save('death', np.concatenate([tune([(784, .1), (740, .1), (698, .1), (659, .1), (622, .1), (587, .1), (554, .1), (523, .3)]), lp(noise(0.3), 0.2) * np.exp(-t(0.3) * 10) * 0.5]), 0.55)
save('start', tune([(523, .12), (659, .12), (784, .12), (1047, .24), (0, .06), (880, .12), (1047, .12), (1319, .4)]), 0.5)
save('clear', tune([(784, .1), (988, .1), (1175, .1), (1568, .3), (1319, .1), (1568, .45)]), 0.5)
save('bonus', tune([(1319, .07), (1568, .07), (2093, .07), (2637, .2)]), 0.45)
save('extra', tune([(1568, .08), (2093, .08), (1568, .08), (2093, .2)]), 0.45)
save('gameover', tune([(523, .3), (494, .3), (466, .3), (440, .9)], lambda p: np.sin(p) * 0.6 + sq(p) * 0.2), 0.5)
save('ghost', sweep(300, 900, 0.35, np.sin) * (0.6 + 0.4 * np.sin(2 * np.pi * 25 * t(0.35))) * env(int(SR * 0.35), 0.02, 0.15), 0.3)
save('click', np.sin(2 * np.pi * 1200 * t(0.04)) * np.exp(-t(0.04) * 60), 0.4)
save('flee', tune([(988, .08), (880, .08), (988, .08), (1175, .16)]), 0.35)
print('assets ok')
