# Crowd Master textures, sky HDR and sound effects/music (all procedural)
import numpy as np, os
from PIL import Image, ImageDraw, ImageFilter
from audiolib import *
T = os.path.join(R, 'Textures'); SK = os.path.join(R, 'Skybox'); os.makedirs(T, exist_ok=True); os.makedirs(SK, exist_ok=True)
rg = np.random.default_rng(5)
def noise(w, h, oct=5, seed=0):
    r = np.random.default_rng(seed); g = np.zeros((h, w))
    for o in range(oct):
        f = 4 * 2 ** o; s = r.random((f, f)); g += np.asarray(Image.fromarray((s * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)) / 255 / 2 ** o
    g -= g.min(); return g / g.max()
def img(a): return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
def sv(a, n): img(a).save(os.path.join(T, n + '.png'))
N = 512
# track tiles: pale blue-white with soft tile seams + a faint lane centre stripe
def track(base, seed, chevron=False):
    a = np.ones((N, N, 3)) * np.array(base, float); a *= (0.95 + 0.07 * noise(N, N, 6, seed))[..., None]
    for k in range(0, N, N // 4): a[k:k + 3, :] *= 0.9; a[:, k:k + 3] *= 0.93
    im = img(a); d = ImageDraw.Draw(im)
    if chevron:
        for y in (90, 250, 410):
            d.line([(170, y + 40), (256, y), (342, y + 40)], fill=tuple(int(c * 0.86) for c in base), width=18)
    return im
track((226, 234, 245), 1).save(os.path.join(T, 'trk.png'))
track((214, 226, 242), 2, True).save(os.path.join(T, 'trk2.png'))
# oil: near-black glossy with iridescent swirls
n1, n2 = noise(N, N, 5, 3), noise(N, N, 5, 4)
ph = (n1 * 9 + n2 * 4)
a = np.stack([np.sin(ph) * 0.5 + 0.5, np.sin(ph + 2.1) * 0.5 + 0.5, np.sin(ph + 4.2) * 0.5 + 0.5], -1)
a = 18 + a * 50 * (n2[..., None] > 0.45) + 10 * n1[..., None]; sv(a, 'oil')
# mud: brown with darker wet puddles
n1 = noise(N, N, 6, 5); a = np.array((120, 82, 50)) * (0.8 + 0.35 * n1)[..., None]
a[noise(N, N, 4, 6) > 0.62] *= 0.62; sv(a, 'mud')
# gravel: grey pebbles
im = Image.new('RGB', (N, N), (128, 122, 112)); d = ImageDraw.Draw(im)
for i in range(1800):
    x, y = rg.integers(0, N, 2); r = rg.integers(4, 13); c = int(rg.integers(95, 200)); tint = rg.integers(-12, 12)
    d.ellipse((x - r, y - r * 0.8, x + r, y + r * 0.8), fill=(c + tint, c, c - tint), outline=(70, 66, 60))
im.filter(ImageFilter.GaussianBlur(0.6)).save(os.path.join(T, 'gravel.png'))
# thorns: dark soil with thorny bramble strokes
im = Image.new('RGB', (N, N), (86, 66, 44)); d = ImageDraw.Draw(im)
for i in range(260):
    x, y = rg.integers(0, N, 2); L = rg.integers(20, 60); a0 = rg.random() * 6.28
    x2, y2 = x + L * np.cos(a0), y + L * np.sin(a0); g = int(rg.integers(70, 120))
    d.line([(x, y), (x2, y2)], fill=(40, g, 30), width=4)
    for t in np.linspace(0.2, 0.9, 4):
        px, py = x + (x2 - x) * t, y + (y2 - y) * t; b = a0 + (1.2 if rg.random() > .5 else -1.2)
        d.line([(px, py), (px + 9 * np.cos(b), py + 9 * np.sin(b))], fill=(150, 140, 110), width=2)
sv(np.asarray(im) * (0.8 + 0.3 * noise(N, N, 5, 8))[..., None], 'thorn')
# ice: pale cyan with white cracks
a = np.array((190, 228, 245)) * (0.9 + 0.12 * noise(N, N, 6, 9))[..., None]
im = img(a); d = ImageDraw.Draw(im)
for i in range(40):
    x, y = rg.integers(0, N, 2); pts = [(x, y)]
    for k in range(6): x += rg.integers(-40, 40); y += rg.integers(-40, 40); pts.append((x, y))
    d.line(pts, fill=(245, 252, 255), width=2)
im.save(os.path.join(T, 'ice.png'))
# warning stripes (diagonal yellow / charcoal) and striped post bands
im = Image.new('RGB', (256, 256), (250, 200, 30)); d = ImageDraw.Draw(im)
for k in range(-256, 512, 64): d.polygon([(k, 0), (k + 32, 0), (k + 32 + 256, 256), (k + 256, 256)], fill=(40, 40, 46))
im.save(os.path.join(T, 'warn.png'))
im = Image.new('RGB', (64, 256), (250, 250, 250)); d = ImageDraw.Draw(im)
for k in range(0, 256, 64): d.rectangle((0, k, 63, k + 31), fill=(150, 60, 220))
im.save(os.path.join(T, 'post_warn.png'))
im = Image.new('RGB', (256, 256)); d = ImageDraw.Draw(im)
for i in range(8):
    for j in range(8): d.rectangle((i * 32, j * 32, i * 32 + 31, j * 32 + 31), fill=(30, 30, 36) if (i + j) % 2 else (250, 250, 250))
im.save(os.path.join(T, 'finish.png'))
sv(np.array((92, 170, 72)) * (0.8 + 0.3 * noise(N, N, 6, 10))[..., None], 'grass')
sv(np.array((236, 214, 160)) * (0.88 + 0.15 * noise(N, N, 6, 11))[..., None], 'sand')
sv(np.array((150, 146, 140)) * (0.8 + 0.3 * noise(N, N, 6, 12))[..., None], 'stone')
# sea: gentle wave noise
n1 = noise(N, N, 6, 13); sv(np.array((40, 135, 190)) * (0.85 + 0.25 * n1)[..., None], 'water')
# skyboxes per world: clean gradient, warm sun, soft clouds
def rgbe(a):
    m = a.max(-1); e = np.ceil(np.log2(np.maximum(m, 1e-32))); sc = np.where(m > 1e-32, 256.0 / 2 ** e, 0)
    o = np.zeros(a.shape[:2] + (4,), np.uint8); o[..., :3] = np.clip(a * sc[..., None], 0, 255).astype(np.uint8)
    o[..., 3] = np.where(m > 1e-32, e + 128, 0).astype(np.uint8); return o
def make_sky(name, zen, hor, sunc, sun_el, cloudc, below, seed, cover=0.47):
    SW_, SH_ = 1024, 512
    v = (np.arange(SH_) + 0.5) / SH_; u = (np.arange(SW_) + 0.5) / SW_
    EL, AZ = np.meshgrid((0.5 - v) * np.pi, u * 2 * np.pi, indexing='ij')
    y = np.sin(EL); t = np.clip(y, 0, 1)
    sky = np.array(hor) * (1 - t[..., None] ** 0.45) + np.array(zen) * (t[..., None] ** 0.45)
    sd = np.array([np.cos(sun_el) * np.cos(2.4), np.sin(sun_el), np.cos(sun_el) * np.sin(2.4)])
    D = np.stack([np.cos(EL) * np.cos(AZ), np.sin(EL), np.cos(EL) * np.sin(AZ)], -1)
    cs = np.clip((D * sd).sum(-1), -1, 1)
    sky += np.array(sunc)[None, None] * (np.exp((cs - 1) * 900) * 30 + np.exp((cs - 1) * 30) * 0.35)[..., None]
    cl = noise(SW_, SH_, 6, seed); cl2 = noise(SW_, SH_, 4, seed + 1)
    cm = np.clip((cl * 0.6 + cl2 * 0.4 - cover) * 3.5, 0, 1) * np.clip(y * 6, 0, 1) * np.clip(1.4 - y * 1.8, 0, 1)
    sky = sky * (1 - cm[..., None] * 0.85) + np.array(cloudc) * cm[..., None] * 0.85
    sky[y < 0] = np.array(below)
    with open(os.path.join(SK, name + '.hdr'), 'wb') as f:
        f.write(b"#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y %d +X %d\n" % (SH_, SW_)); f.write(rgbe(sky.astype(np.float32)).tobytes())
    img(np.clip(sky / (1 + sky), 0, 1) * 255 * 1.6).save('/tmp/cm_sky_%s.png' % name)
make_sky('day', [0.18, 0.42, 0.95], [0.78, 0.9, 1.05], [1.0, 0.9, 0.7], 0.75, [1.05, 1.05, 1.08], [0.25, 0.46, 0.6], 21)
make_sky('canyon', [0.22, 0.45, 0.85], [1.0, 0.86, 0.68], [1.0, 0.82, 0.55], 0.6, [1.1, 1.0, 0.92], [0.4, 0.45, 0.5], 31, 0.55)
make_sky('frost', [0.32, 0.5, 0.85], [0.88, 0.94, 1.05], [0.95, 0.95, 1.0], 0.55, [1.05, 1.07, 1.12], [0.35, 0.48, 0.6], 41, 0.42)
make_sky('ember', [0.25, 0.25, 0.6], [1.2, 0.68, 0.45], [1.3, 0.7, 0.35], 0.32, [1.15, 0.78, 0.7], [0.3, 0.28, 0.42], 51, 0.45)
# ------------------------------------------------------------------ audio
def sine(f, d): return np.sin(2 * np.pi * f * tt(d))
def nz(d, k): return rng.standard_normal(int(SR * d)) * np.exp(-tt(d) * k)
def lowp(x, a=0.08):
    y = np.zeros_like(x); s = 0
    for i, v_ in enumerate(x): s += a * (v_ - s); y[i] = s
    return y
def bell(f, d, k=6): return (sine(f, d) + 0.4 * sine(f * 2, d) + 0.2 * sine(f * 3.01, d)) * np.exp(-tt(d) * k)
def arp(fs, step, d, k=8):
    out = np.zeros(int(SR * (step * len(fs) + d)))
    for i, f in enumerate(fs):
        b = bell(f, d, k); s = int(SR * step * i); out[s:s + len(b)] += b
    return out
save('gate_good.wav', env(arp([523, 659, 784, 1047], 0.05, 0.35)), 0.4)
save('gate_bad.wav', env(arp([392, 330, 262, 196], 0.06, 0.35)), 0.4)
save('merge.wav', env(mix(arp([523, 784, 1047, 1568, 2093], 0.04, 0.5, 5), nz(0.3, 10) * 0.05)), 0.4)
save('pop.wav', env(sine(900, 0.07) * np.exp(-tt(0.07) * 40) + sine(1400, 0.07) * 0.4 * np.exp(-tt(0.07) * 50)), 0.25)
save('clash.wav', env(lowp(nz(0.35, 9), 0.25) * 2 + sine(90, 0.35) * np.exp(-tt(0.35) * 12)), 0.4)
save('hit.wav', env(lowp(nz(0.25, 14), 0.4) + sine(160, 0.25) * np.exp(-tt(0.25) * 18)), 0.4)
save('saw.wav', env((sq(220, 0.3, 0.3) * 0.3 + nz(0.3, 6) * 0.5) * np.exp(-tt(0.3) * 6)), 0.25)
save('splash.wav', env(lowp(nz(0.5, 6), 0.35)), 0.35)
save('coin.wav', env(bell(1568, 0.12, 20) + bell(2093, 0.25, 12) * np.concatenate([np.zeros(int(SR * 0.0)), np.ones(int(SR * 0.25))])[:int(SR * 0.25)] * 0.7 if False else np.concatenate([bell(1568, 0.07, 25), bell(2093, 0.3, 10)])), 0.3)
for i in range(10): save('step%d.wav' % i, env(bell(392 * 2 ** (i / 7), 0.25, 10)), 0.35)
save('thud.wav', env(sine(70, 0.5) * np.exp(-tt(0.5) * 8) + lowp(nz(0.5, 10), 0.2) * 1.5), 0.5)
save('slam.wav', env(sine(50, 0.9) * np.exp(-tt(0.9) * 4) + lowp(nz(0.9, 5), 0.15) * 2.5), 0.55)
save('shield.wav', env(mix(sine(440, 0.6) * sine(6, 0.6) * 0.5, arp([660, 880, 1320], 0.08, 0.4, 6))), 0.35)
save('buy.wav', env(arp([784, 988, 1175, 1568], 0.05, 0.3, 9)), 0.35)
save('click.wav', env(sine(1200, 0.04) * np.exp(-tt(0.04) * 60)), 0.25)
save('hover.wav', env(sine(1800, 0.03) * np.exp(-tt(0.03) * 80)), 0.12)
save('deny.wav', env(sq(180, 0.18, 0.5) * 0.5), 0.25)
save('win.wav', mix(melody([('C5', 0.5), ('E5', 0.5), ('G5', 0.5), ('C6', 1), ('G5', 0.5), ('C6', 2)], 200, 'tri'),
                    melody([('C3', 1), ('G3', 1), ('C4', 3)], 200, 'tri')), 0.4)
save('lose.wav', melody([('G4', 1), ('F#4', 1), ('F4', 1), ('E4', 3)], 170, 'tri'), 0.35)
save('trophy.wav', env(arp([1047, 1319, 1568, 2093, 2637], 0.06, 0.7, 4)), 0.4)
save('boss_roar.wav', env(lowp(nz(1.0, 2), 0.1) * 2 + sq(70, 1.0, 0.4) * 0.4 * np.exp(-tt(1.0) * 2)), 0.45)
def loop(bass, lead, bpm, nm, vol=0.22):
    b = melody(bass, bpm, 'tri'); l = melody(lead, bpm, 'tri') if lead else np.zeros(1)
    save(nm, mix(b, l * 0.5), vol)
loop([('C3', 1), ('G2', 1), ('A2', 1), ('F2', 1)] * 4,
     [('E5', 0.5), ('G5', 0.5), ('C6', 1), ('B5', 0.5), ('G5', 0.5), ('A5', 1), ('C6', 0.5), ('A5', 0.5), ('F5', 1), ('G5', 2),
      ('E5', 0.5), ('G5', 0.5), ('C6', 1), ('D6', 0.5), ('C6', 0.5), ('A5', 1), ('G5', 0.5), ('F5', 0.5), ('E5', 1), ('C5', 2)], 132, 'run.wav')
loop([('F2', 2), ('C3', 2), ('D3', 2), ('A#2', 2)] * 2, [('A4', 2), ('C5', 2), ('D5', 1), ('F5', 1), ('E5', 2), ('C5', 2), ('A4', 2), ('G4', 2), ('F4', 2)], 96, 'title.wav')
loop([('D2', 0.5), ('D3', 0.5)] * 8 + [('A#1', 0.5), ('A#2', 0.5)] * 4 + [('C2', 0.5), ('C3', 0.5)] * 4, [('D5', 1), ('F5', 1), ('A5', 1), ('G5', 1), ('F5', 1), ('E5', 1), ('D5', 2)], 150, 'boss.wav')
print('assets ok')
