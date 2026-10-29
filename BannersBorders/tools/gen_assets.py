# Textures (palette atlas, land grain, table wood), skybox and original synthesized audio for Banners & Borders.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image, ImageFilter
from audiolib import *
import palette as P
T = os.path.join(R, 'Textures'); os.makedirs(T, exist_ok=True)
def save_img(a, nm, blur=0.0):
    im = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
    if blur: im = im.filter(ImageFilter.GaussianBlur(blur))
    im.save(os.path.join(T, nm + '.png'))
S = P.SIZE; base = np.zeros((S, S, 3)); mr = np.zeros((S, S, 3)); em = np.zeros((S, S, 3)); mr[..., 0] = 255
for nm, (i, rgb, rough, metal, e) in P.SW.items():
    gx, gy = i % P.G, i // P.G; ys, xs = slice(gy * P.PX, (gy + 1) * P.PX), slice(gx * P.PX, (gx + 1) * P.PX)
    base[ys, xs] = np.array(rgb) * 255; mr[ys, xs, 1] = rough * 255; mr[ys, xs, 2] = metal * 255
    if e: em[ys, xs] = np.array(e) * 255
save_img(base[::-1], 'pal'); save_img(mr[::-1], 'pal_mr'); save_img(em[::-1], 'pal_em')
def fbm(n, oct=5, seed=0, base_f=4):
    rg = np.random.default_rng(seed); o = np.zeros((n, n)); a = 1.0; tot = 0
    for k in range(oct):
        f = base_f * 2 ** k; r = rg.random((f, f))
        r = np.tile(r, (3, 3)); im = Image.fromarray((r * 255).astype(np.uint8)).resize((n * 3, n * 3), Image.BICUBIC)
        o += np.asarray(im)[n:2 * n, n:2 * n] / 255.0 * a; tot += a; a *= 0.5
    return o / tot
def normal_from(h, k=4.0):
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * k; gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * k
    n = np.dstack([-gx, -gy, np.ones_like(h)]); n /= np.linalg.norm(n, axis=2, keepdims=True)
    return (n * 0.5 + 0.5) * 255
N = 1024
# land grain: near-white, soft paper/felt variation (multiplied by the region tint in the material)
g = fbm(N, 6, 3, 16); grit = np.random.default_rng(4).random((N, N))
a = np.ones((N, N, 3)) * 255 * (0.86 + 0.14 * g + 0.03 * grit)[..., None]
save_img(a, 'grain', 0.6); save_img(normal_from(g * 0.5 + grit * 0.04, 2.0), 'grain_n', 0.8)
# table wood (planks along u)
n = 512; yy, xx = np.mgrid[0:n, 0:n] / n
w = fbm(n, 5, 7, 4); ring = np.sin((xx * 3 + w * 2.5) * 40) * 0.5 + 0.5
plank = (np.floor(yy * 6) % 2) * 0.06
c = np.array([120, 74, 40.]) * (0.8 + 0.15 * ring + plank)[..., None]
c[(yy * 6 % 1) < 0.012] *= 0.55
save_img(c, 'wood', 0.5); save_img(normal_from(ring * 0.3 + (yy * 6 % 1 < 0.012) * 1.0, 2.0), 'wood_n', 0.6)
# skybox: soft pastel daylight (tabletop)
SK = os.path.join(R, 'Skybox'); os.makedirs(SK, exist_ok=True)
def rgbe(a):
    m = a.max(-1); e = np.ceil(np.log2(np.maximum(m, 1e-32))); sc = np.where(m > 1e-32, 256.0 / 2 ** e, 0)
    o = np.zeros(a.shape[:2] + (4,), np.uint8); o[..., :3] = np.clip(a * sc[..., None], 0, 255).astype(np.uint8)
    o[..., 3] = np.where(m > 1e-32, e + 128, 0).astype(np.uint8); return o
W_, H_ = 1024, 512
v = (np.arange(H_) + 0.5) / H_; u = (np.arange(W_) + 0.5) / W_
EL, AZ = np.meshgrid((0.5 - v) * np.pi, u * 2 * np.pi, indexing='ij'); y = np.sin(EL); t = np.clip(y, 0, 1)
zen, hor = np.array([0.32, 0.55, 0.95]), np.array([0.95, 0.93, 0.9])
sky = hor * (1 - t[..., None] ** 0.45) + zen * t[..., None] ** 0.45
sd = np.array([np.cos(0.9) * np.cos(2.3), np.sin(0.9), np.cos(0.9) * np.sin(2.3)])
D = np.stack([np.cos(EL) * np.cos(AZ), np.sin(EL), np.cos(EL) * np.sin(AZ)], -1); cs = np.clip((D * sd).sum(-1), -1, 1)
sky += np.array([1.0, 0.92, 0.78]) * (np.exp((cs - 1) * 1500) * 30 + np.exp((cs - 1) * 30) * 0.4)[..., None]
sky = np.where(y[..., None] < 0, np.array([0.55, 0.5, 0.45]), sky)
with open(os.path.join(SK, 'table.hdr'), 'wb') as f:
    f.write(b"#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y %d +X %d\n" % (H_, W_)); f.write(rgbe(sky.astype(np.float32)).tobytes())

# ------------------------------------------------------------------ audio (all original synthesis)
rg = np.random.default_rng(11)
def nz(d): return rg.standard_normal(int(SR * d))
def lp(x, k):
    y = np.zeros_like(x); acc = 0.0
    for i in range(len(x)): acc += k * (x[i] - acc); y[i] = acc
    return y
def ex(d, k): return np.exp(-tt(d) * k)
def sine(f0, f1, d): return np.sin(2 * np.pi * np.cumsum(np.geomspace(f0, f1, int(SR * d))) / SR)
def sv(nm, x, vol=0.5): save(nm, env(x, 0.002, 0.01), vol)
def pluck(f, d, k=6): t = tt(d); return (np.sin(2 * np.pi * f * t) + 0.4 * np.sin(4 * np.pi * f * t) + 0.15 * np.sin(6 * np.pi * f * t)) * np.exp(-t * k)
def horn(f, d): t = tt(d); x = sum(np.sin(2 * np.pi * f * h * t) / h ** 1.3 for h in range(1, 7)); return x * np.clip(t * 18, 0, 1) * np.clip((d - t) * 10, 0, 1)
def arp(notes, d=0.08, k=8, fn=pluck): return np.concatenate([fn(hz(n), d, k) if fn is pluck else fn(hz(n), d) for n in notes])
snare_n = lp(nz(0.12), 0.7)
def snare(v=1.0): return (snare_n - lp(snare_n, 0.05)) * ex(0.12, 28) * 0.7 * v + np.sin(2 * np.pi * 210 * tt(0.12)) * ex(0.12, 40) * 0.25 * v
def kick(): return sine(130, 45, 0.2) * ex(0.2, 14)
sv('click.wav', np.sin(2 * np.pi * 1100 * tt(0.05)) * ex(0.05, 60) + lp(nz(0.05), 0.6) * ex(0.05, 120) * 0.3, 0.3)
sv('hover.wav', np.sin(2 * np.pi * 2000 * tt(0.03)) * ex(0.03, 120), 0.1)
sv('select.wav', pluck(hz('E5'), 0.15, 18) + pluck(hz('B5'), 0.15, 22) * 0.5, 0.25)
sv('send.wav', np.concatenate([snare(0.8), snare(0.6), snare(0.9)]) + 0.0, 0.3)
sv('march.wav', np.concatenate([snare(1.0)[:int(SR * 0.1)], snare(0.5)[:int(SR * 0.1)]]), 0.2)
sv('clash.wav', lp(nz(0.18), 0.5) * ex(0.18, 25) + np.sin(2 * np.pi * 2400 * tt(0.18)) * ex(0.18, 30) * 0.4 + np.sin(2 * np.pi * 3100 * tt(0.18)) * ex(0.18, 35) * 0.3, 0.25)
sv('capture.wav', np.concatenate([arp(['G4', 'C5'], 0.1, 0, horn), horn(hz('E5'), 0.35)]) * 0.6, 0.38)
sv('lost.wav', np.concatenate([horn(hz('E4'), 0.18), horn(hz('C4'), 0.4)]) * 0.6, 0.32)
sv('neutral.wav', arp(['C5', 'G5'], 0.09, 10), 0.28)
sv('airdrop.wav', mix(sine(300, 900, 0.6) * ex(0.6, 3) * 0.3, lp(nz(0.6), 0.1) * np.sin(np.pi * tt(0.6) / 0.6) * 1.5), 0.35)
sv('march_horn.wav', np.concatenate([horn(hz('C5'), 0.15), horn(hz('C5'), 0.15), horn(hz('G5'), 0.45)]), 0.32)
sv('frost.wav', mix(*[pluck(hz(n), 0.8, 4) * (0.6 ** i) for i, n in enumerate(['E6', 'B6', 'G#6', 'E7'])]) + lp(nz(0.8), 0.9) * ex(0.8, 5) * 0.2, 0.3)
def boom(d, f, k): return lp(nz(d), 0.08) * ex(d, k) * 2.5 + sine(f, f * 0.35, d) * ex(d, k * 0.8)
sv('boom.wav', boom(1.0, 90, 4.5), 0.5); sv('whistle.wav', sine(1700, 600, 0.6) * np.clip(tt(0.6) * 4, 0, 1) * 0.4, 0.2)
sv('coin.wav', np.sin(2 * np.pi * 1975 * tt(0.25)) * ex(0.25, 14) + np.sin(2 * np.pi * 2637 * tt(0.25)) * ex(0.25, 10) * (tt(0.25) > 0.06), 0.25)
sv('star.wav', arp(['C6', 'E6', 'G6'], 0.07, 10), 0.3)
sv('warn.wav', np.concatenate([horn(hz('A4'), 0.12), np.zeros(int(SR * 0.05)), horn(hz('A4'), 0.12)]), 0.25)
sv('win.wav', np.concatenate([horn(hz('C5'), 0.14), horn(hz('E5'), 0.14), horn(hz('G5'), 0.14), horn(hz('C6'), 0.7)]), 0.4)
sv('lose.wav', np.concatenate([horn(hz('G4'), 0.3), horn(hz('F#4'), 0.3), horn(hz('F4'), 0.3), horn(hz('E4'), 0.9)]), 0.35)
sv('upgrade.wav', arp(['C5', 'E5', 'G5', 'C6', 'E6'], 0.05, 9), 0.32)
# ---- music: original marching-band loops (snare rolls, bass, plucked melody), 8 bars
def song(chords, mel, bpm, bars, drive=1.0, minor=False):
    beat = 60 / bpm; L = int(SR * beat * 4 * bars); o = np.zeros(L + SR)
    def put(x, t): i = int(t * SR); o[i:i + len(x)] += x[:max(0, len(o) - i)]
    for b in range(bars):
        root = chords[b % len(chords)]; t0 = b * 4 * beat
        third = 3 if minor else 4
        for k in range(4):
            put(kick() * 0.8 * drive, t0 + k * beat)
            put(np.tanh(2.5 * np.sin(2 * np.pi * hz(root) / 2 * tt(beat * 0.8))) * ex(beat * 0.8, 3) * 0.3, t0 + k * beat)
            put(np.tanh(2.5 * np.sin(2 * np.pi * hz(root) / 2 * 1.5 * tt(beat * 0.3))) * ex(beat * 0.3, 6) * 0.15, t0 + k * beat + beat / 2)
            put(snare(0.5), t0 + k * beat + beat / 2)
            if k % 2: put(snare(0.9 * drive), t0 + k * beat)
        if b % 2 == 1:
            for r in range(4): put(snare(0.35 + r * 0.12), t0 + 3 * beat + r * beat / 4)
        for k in range(8):
            n = mel[(b * 8 + k) % len(mel)]
            if n != '-': put(pluck(hz(n), beat * 0.6, 5) * 0.22, t0 + k * beat / 2)
        for k, iv in enumerate((0, third, 7)):
            put(np.sin(2 * np.pi * hz(root) * 2 ** (iv / 12) * tt(beat * 4)) * ex(beat * 4, 0.8) * 0.05, t0)
    return o[:L]
save('music_title.wav', song(['C4', 'F4', 'G4', 'C4', 'A3', 'F4', 'G4', 'C4'],
     ['E5', 'G5', 'C6', 'G5', 'A5', 'G5', 'E5', '-', 'F5', 'A5', 'C6', 'A5', 'G5', 'F5', 'D5', '-',
      'E5', 'G5', 'E5', 'C5', 'D5', 'E5', 'F5', 'D5', 'C5', 'E5', 'G5', 'E5', 'D5', 'B4', 'C5', '-'], 100, 8, 0.7), 0.24)
save('music_battle.wav', song(['A3', 'A3', 'F3', 'G3', 'A3', 'C4', 'D4', 'E4'],
     ['A4', 'C5', 'E5', 'A5', 'G5', 'E5', 'C5', 'E5', 'F5', 'E5', 'D5', 'C5', 'B4', 'D5', 'G5', 'D5',
      'A4', 'C5', 'E5', 'C5', 'D5', 'F5', 'A5', 'F5', 'E5', 'D5', 'C5', 'B4', 'A4', 'B4', 'C5', 'E5'], 122, 8, 1.0, True), 0.27)
save('music_boss.wav', song(['D3', 'D3', 'A#2', 'C3', 'D3', 'F3', 'G3', 'A3'],
     ['D5', 'F5', 'A5', 'D6', 'C6', 'A5', 'F5', 'A5', 'A#5', 'A5', 'G5', 'F5', 'E5', 'G5', 'A5', '-'], 138, 8, 1.3, True), 0.29)
print('assets ok')
