# Textures (palette atlas, deck, water/lava/floors + normal maps) and audio for Gatebreaker Squad.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image, ImageFilter
from audiolib import *
import palette as P
T = os.path.join(R, 'Textures'); os.makedirs(T, exist_ok=True)
def save_img(a, nm, blur=0.0, mode='RGB'):
    im = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
    if blur: im = im.filter(ImageFilter.GaussianBlur(blur))
    im.save(os.path.join(T, nm + '.png'))
# ---- palette atlas
S = P.SIZE; base = np.zeros((S, S, 3)); mr = np.zeros((S, S, 3)); em = np.zeros((S, S, 3))
mr[..., 0] = 255
for nm, (i, rgb, rough, metal, e) in P.SW.items():
    gx, gy = i % P.G, i // P.G; ys, xs = slice(gy * P.PX, (gy + 1) * P.PX), slice(gx * P.PX, (gx + 1) * P.PX)
    base[ys, xs] = np.array(rgb) * 255; mr[ys, xs, 1] = rough * 255; mr[ys, xs, 2] = metal * 255
    if e: em[ys, xs] = np.array(e) * 255
# engine samples OBJ v bottom-up: store the atlas flipped so uv() rows match
save_img(base[::-1], 'pal'); save_img(mr[::-1], 'pal_mr'); save_img(em[::-1], 'pal_em')
# ---- noise helpers
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
N = 512; yy, xx = np.mgrid[0:N, 0:N] / N
# ---- deck: u across (0..1 = 11 m), v along (1 = 10 m)
h = fbm(N, 6, 1, 8); d = np.ones((N, N, 3)) * np.array([92, 96, 104.]) * (0.82 + 0.3 * h)[..., None]
grit = np.random.default_rng(2).random((N, N)); d *= (0.93 + 0.12 * grit)[..., None]
for c in (0.045, 0.955): d[np.abs(xx - c) < 0.012] = [236, 236, 230]
dash = (np.abs(xx - 0.5) < 0.009) & ((yy * 10) % 5 < 2.6); d[dash] = [250, 205, 60]
d[(xx < 0.02) | (xx > 0.98)] = [150, 150, 150]
for k in range(1, 4): d[np.abs(yy - k / 4) < 0.0025] *= 0.82   # expansion joints
save_img(d, 'deck', 0.4); save_img(normal_from(h * 0.6 + grit * 0.08, 3.0), 'deck_n', 0.6)
# ---- water (tile = 12 m): base tint + bright caustic web, shared normal map
w = fbm(N, 5, 3, 4); c1 = fbm(N, 4, 4, 6); caus = np.clip(1 - np.abs(c1 - 0.5) * 9, 0, 1) ** 2
def water(col, hi, nm):
    a = np.ones((N, N, 3)) * np.array(col) * (0.85 + 0.3 * w)[..., None] + (caus * 0.5)[..., None] * np.array(hi)
    save_img(a, nm, 0.6)
water([28, 110, 140.], [90, 160, 150], 'water_harbor'); water([30, 70, 110.], [150, 190, 220], 'water_frost')
# smooth low-frequency swell only: high-frequency normals on a near-mirror sea sparkle/speckle under TAA
save_img(normal_from(fbm(N, 4, 5, 4) + 0.3 * fbm(N, 3, 6, 8), 3.5), 'water_n', 1.5)
# ---- lava: dark crust + glowing cracks (separate emissive)
lv = fbm(N, 6, 7, 5); cr = np.clip(1 - np.abs(fbm(N, 4, 8, 5) - 0.5) * 7, 0, 1) ** 1.5
a = np.ones((N, N, 3)) * np.array([45, 30, 26.]) * (0.7 + 0.5 * lv)[..., None]; a = a * (1 - cr[..., None]) + cr[..., None] * np.array([255, 120, 30.])
save_img(a, 'lava', 0.5); save_img(cr[..., None] * np.array([255, 110, 25.]) + 0 * a, 'lava_em', 0.8); save_img(normal_from(lv, 4.0), 'lava_n', 0.6)
# ---- floors (tile = 16 m)
g = fbm(N, 6, 9, 6)
def floor(col, var, nm, spots=None):
    a = np.ones((N, N, 3)) * np.array(col) * (0.75 + 0.45 * g)[..., None]
    if spots is not None:
        s = np.random.default_rng(10).random((N, N)) > 0.997; a[s] = spots
    save_img(a, nm, 0.8)
floor([82, 140, 58.], 0, 'grass', [250, 240, 120]); floor([205, 160, 105.], 0, 'canyon'); floor([150, 110, 60.], 0, 'autumn_floor', [220, 110, 30])
save_img(normal_from(g, 3.0), 'floor_n', 0.8)
# ---- gate panel gradient (v up the panel): bright rim, soft centre
yy, xx = np.mgrid[0:256, 0:256] / 255.0
rim = np.clip(np.maximum(np.abs(xx - 0.5), np.abs(yy - 0.5)) * 2 - 0.86, 0, 1) / 0.14
shine = np.exp(-((xx * 0.8 + yy * 0.6 - 0.55) / 0.07) ** 2) * 0.22 + np.exp(-((xx * 0.8 + yy * 0.6 - 0.75) / 0.03) ** 2) * 0.12
gp = np.ones((256, 256, 3)) * 255 * np.clip(0.5 + 0.18 * yy + 0.5 * rim ** 2 + shine, 0, 1)[..., None]
save_img(gp, 'gate_grad', 1.0)

# ---- skyboxes (equirect RGBE .hdr): per-world gradient, sun disc + halo, layered cumulus with lit tops
SK = os.path.join(R, 'Skybox'); os.makedirs(SK, exist_ok=True)
def fbm2(w, h, oct, seed, f0=4):
    rg_ = np.random.default_rng(seed); o = np.zeros((h, w)); a = 1.0; tot = 0
    for k in range(oct):
        fx, fy = f0 * 2 ** k * 2, f0 * 2 ** k
        r = rg_.random((fy + 1, fx)); r = np.concatenate([r, r[:, :1]], 1)
        im = Image.fromarray((r * 255).astype(np.uint8)).resize((w + w // fx, h + h // fy), Image.BICUBIC)
        o += np.asarray(im)[:h, :w] / 255.0 * a; tot += a; a *= 0.5
    return o / tot
def rgbe(a):
    m = a.max(-1); e = np.ceil(np.log2(np.maximum(m, 1e-32))); sc = np.where(m > 1e-32, 256.0 / 2 ** e, 0)
    o = np.zeros(a.shape[:2] + (4,), np.uint8); o[..., :3] = np.clip(a * sc[..., None], 0, 255).astype(np.uint8)
    o[..., 3] = np.where(m > 1e-32, e + 128, 0).astype(np.uint8); return o
def make_sky(name, zen, hor, sunc, sun_el, sun_az, cloud_lit, cloud_sh, below, seed, cover=0.5, haze=None):
    W_, H_ = 1024, 512
    v = (np.arange(H_) + 0.5) / H_; u = (np.arange(W_) + 0.5) / W_
    EL, AZ = np.meshgrid((0.5 - v) * np.pi, u * 2 * np.pi, indexing='ij')
    y = np.sin(EL); t = np.clip(y, 0, 1)
    sky = np.array(hor) * (1 - t[..., None] ** 0.5) + np.array(zen) * (t[..., None] ** 0.5)
    if haze is not None: sky += np.array(haze) * np.exp(-t * 14)[..., None]
    sd = np.array([np.cos(sun_el) * np.cos(sun_az), np.sin(sun_el), np.cos(sun_el) * np.sin(sun_az)])
    D = np.stack([np.cos(EL) * np.cos(AZ), np.sin(EL), np.cos(EL) * np.sin(AZ)], -1)
    cs = np.clip((D * sd).sum(-1), -1, 1)
    sky += np.array(sunc) * (np.exp((cs - 1) * 1500) * 40 + np.exp((cs - 1) * 40) * 0.5 + np.exp((cs - 1) * 4) * 0.12)[..., None]
    n1 = fbm2(W_, H_, 6, seed, 3); n2 = fbm2(W_, H_, 5, seed + 1, 6)
    band = np.clip(y * 8, 0, 1) * np.clip(1.3 - y * 1.6, 0, 1)
    dens = np.clip((n1 * 0.65 + n2 * 0.35 - cover + 0.04) * 7.0, 0, 1) ** 0.8 * band
    lit = np.clip((np.roll(n1, 3, 0) - n1) * 18 + 0.55, 0, 1)   # tops brighter than bellies
    cc = np.array(cloud_sh) * (1 - lit[..., None]) + np.array(cloud_lit) * lit[..., None]
    cc += np.array(sunc) * (np.exp((cs - 1) * 8) * 0.5)[..., None] * lit[..., None]
    sky = sky * (1 - dens[..., None]) + cc * dens[..., None]
    fade = np.clip(-y * 6, 0, 1)[..., None]
    sky = sky * (1 - fade) + np.array(below) * fade
    with open(os.path.join(SK, name + '.hdr'), 'wb') as f:
        f.write(b"#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y %d +X %d\n" % (H_, W_)); f.write(rgbe(sky.astype(np.float32)).tobytes())
    Image.fromarray(np.clip(sky / (1 + sky) * 255 * 1.6, 0, 255).astype(np.uint8)).save('/tmp/gb_sky_%s.png' % name)
make_sky('harbor', [0.16, 0.4, 0.95], [0.75, 0.88, 1.05], [1.0, 0.92, 0.75], 0.8, 2.2, [1.25, 1.25, 1.25], [0.62, 0.68, 0.8], [0.3, 0.5, 0.62], 21, 0.5)
make_sky('canyon', [0.2, 0.42, 0.85], [1.05, 0.85, 0.62], [1.0, 0.82, 0.55], 0.62, 2.0, [1.3, 1.15, 1.0], [0.72, 0.6, 0.55], [0.55, 0.45, 0.35], 31, 0.58)
make_sky('forest', [0.22, 0.45, 0.88], [0.95, 0.85, 0.7], [1.1, 0.85, 0.55], 0.5, 2.3, [1.3, 1.15, 1.0], [0.62, 0.58, 0.62], [0.3, 0.4, 0.3], 41, 0.5)
make_sky('frost', [0.3, 0.5, 0.88], [0.86, 0.93, 1.05], [0.95, 0.95, 1.0], 0.55, 2.1, [1.2, 1.22, 1.3], [0.66, 0.72, 0.85], [0.4, 0.52, 0.65], 51, 0.44)
make_sky('volcano', [0.18, 0.16, 0.38], [1.2, 0.6, 0.38], [1.3, 0.62, 0.3], 0.3, 2.2, [1.1, 0.7, 0.55], [0.35, 0.25, 0.3], [0.3, 0.18, 0.15], 61, 0.42, [0.5, 0.15, 0.05])

# ------------------------------------------------------------------ audio
rg = np.random.default_rng(11)
def nz(d): return rg.standard_normal(int(SR * d))
def lp(x, k): # one-pole low-pass, k in (0,1): smaller = darker
    y = np.zeros_like(x); acc = 0.0
    for i in range(len(x)): acc += k * (x[i] - acc); y[i] = acc
    return y
def ex(d, k): return np.exp(-tt(d) * k)
def sine(f0, f1, d): return np.sin(2 * np.pi * np.cumsum(np.geomspace(f0, f1, int(SR * d))) / SR)
def sv(nm, x, vol=0.5): save(nm, env(x, 0.002, 0.01), vol)
sv('shot_rifle.wav', lp(nz(0.09), 0.5) * ex(0.09, 45) + sine(900, 200, 0.09) * ex(0.09, 60) * 0.5, 0.32)
sv('shot_shotgun.wav', lp(nz(0.22), 0.35) * ex(0.22, 18) + sine(220, 60, 0.22) * ex(0.22, 20) * 0.8, 0.42)
sv('shot_minigun.wav', lp(nz(0.05), 0.6) * ex(0.05, 70) + sine(700, 300, 0.05) * ex(0.05, 80) * 0.4, 0.25)
sv('shot_rocket.wav', lp(nz(0.45), 0.2) * ex(0.45, 6) + sine(160, 500, 0.45) * ex(0.45, 7) * 0.4, 0.38)
sv('shot_laser.wav', sine(2400, 300, 0.18) * ex(0.18, 16) + sine(1200, 150, 0.18) * ex(0.18, 18) * 0.5, 0.25)
sv('shot_sniper.wav', lp(nz(0.3), 0.4) * ex(0.3, 14) + sine(400, 70, 0.3) * ex(0.3, 12), 0.4)
sv('hit.wav', lp(nz(0.05), 0.7) * ex(0.05, 80) + sine(1800, 900, 0.05) * ex(0.05, 90) * 0.4, 0.18)
for i in range(6):   # gate tick: rising pitch with value
    f = 520 * 2 ** (i / 6); sv(f'tick{i}.wav', np.sin(2 * np.pi * f * tt(0.08)) * ex(0.08, 35) + np.sin(2 * np.pi * f * 2 * tt(0.08)) * ex(0.08, 50) * 0.3, 0.22)
def arp(notes, d=0.07, k=10, h=0.3):
    return np.concatenate([np.sin(2 * np.pi * hz(n) * tt(d)) * ex(d, k) + np.sin(2 * np.pi * hz(n) * 2 * tt(d)) * h * ex(d, k * 1.5) for n in notes])
sv('gate_good.wav', arp(['C5', 'E5', 'G5', 'C6'], 0.06, 12), 0.35)
sv('gate_bad.wav', arp(['G4', 'D#4', 'C4'], 0.09, 8) * 0.8 + 0.1 * sq(110, 0.27, 0.3) * ex(0.27, 6), 0.35)
sv('gate_mult.wav', arp(['C5', 'G5', 'C6', 'E6', 'G6'], 0.055, 10), 0.38)
sv('unlock.wav', arp(['E5', 'B5', 'E6'], 0.07, 10) + 0.0, 0.35)
sv('flip.wav', sine(900, 120, 0.4) * ex(0.4, 5) + lp(nz(0.4), 0.3) * ex(0.4, 8) * 0.5, 0.35)
def boom(d, f, k): return lp(nz(d), 0.08) * ex(d, k) * 2.5 + sine(f, f * 0.35, d) * ex(d, k * 0.8) + lp(nz(d), 0.5) * ex(d, k * 4) * 0.5
sv('boom.wav', boom(1.0, 90, 4.5), 0.55); sv('boom_small.wav', boom(0.45, 140, 9), 0.45); sv('boom_big.wav', boom(1.8, 60, 2.4), 0.6)
sv('crate.wav', mix(lp(nz(0.25), 0.4) * ex(0.25, 14), arp(['G5', 'C6', 'E6', 'G6'], 0.06, 10) * 0.6), 0.4)
sv('ally.wav', np.concatenate([arp(['C5', 'E5', 'G5'], 0.08, 6), arp(['C6'], 0.3, 4)]), 0.4)
sv('merge.wav', mix(sine(200, 1600, 0.5) * ex(0.5, 3), arp(['C6', 'G6'], 0.1, 6) * 0.5), 0.35)
sv('die.wav', sine(700, 180, 0.12) * ex(0.12, 25), 0.25)
sv('splat.wav', lp(nz(0.12), 0.25) * ex(0.12, 30) + sine(300, 90, 0.12) * ex(0.12, 25), 0.3)
sv('roar.wav', lp(nz(1.4), 0.06) * (0.6 + 0.4 * np.sin(2 * np.pi * 9 * tt(1.4))) * ex(1.4, 1.5) * 3 + sine(90, 55, 1.4) * ex(1.4, 1.6) * (0.6 + 0.4 * sq(30, 1.4, 0.5)), 0.55)
sv('warn.wav', np.concatenate([sq(880, 0.12, 0.5) * 0.4, np.zeros(int(SR * 0.06)), sq(660, 0.16, 0.5) * 0.4]), 0.22)
sv('coin.wav', np.sin(2 * np.pi * 1975 * tt(0.25)) * ex(0.25, 14) + np.sin(2 * np.pi * 2637 * tt(0.25)) * ex(0.25, 10) * (tt(0.25) > 0.06), 0.25)
sv('click.wav', np.sin(2 * np.pi * 1300 * tt(0.05)) * ex(0.05, 60) + lp(nz(0.05), 0.7) * ex(0.05, 120) * 0.3, 0.3)
sv('hover.wav', np.sin(2 * np.pi * 2200 * tt(0.03)) * ex(0.03, 120), 0.12)
sv('jet.wav', lp(nz(2.0), 0.15) * np.sin(np.pi * tt(2.0) / 2.0) ** 2 * 2 + sine(500, 160, 2.0) * np.sin(np.pi * tt(2.0) / 2.0) ** 3 * 0.3, 0.45)
sv('whistle.wav', sine(1800, 500, 0.7) * np.clip(tt(0.7) * 4, 0, 1) * 0.5, 0.25)
heli = lp(nz(1.0), 0.12) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 14 * tt(1.0)))) * 2.2
sv('heli.wav', heli, 0.3)
sv('airstrike.wav', np.concatenate([sq(440, 0.1, 0.3), sq(587, 0.1, 0.3), sq(880, 0.25, 0.3) * ex(0.25, 6)]) * 0.5, 0.28)
sv('hurt.wav', lp(nz(0.2), 0.3) * ex(0.2, 16) + sine(300, 80, 0.2) * ex(0.2, 14), 0.35)
sv('win.wav', np.concatenate([arp(['C5', 'E5', 'G5', 'C6'], 0.11, 5), arp(['G5'], 0.11, 5), arp(['C6'], 0.6, 2.5)]), 0.4)
sv('lose.wav', np.concatenate([arp(['G4'], 0.3, 3), arp(['F#4'], 0.3, 3), arp(['F4'], 0.3, 3), arp(['E4'], 0.9, 1.5)]), 0.35)
sv('levelup.wav', arp(['C5', 'E5', 'G5', 'C6', 'E6', 'G6', 'C7'], 0.05, 8), 0.35)
# ---- music: original loops (punchy bass + arps + kick/snare), 2 bars repeated
def kick(): return sine(150, 45, 0.18) * ex(0.18, 16)
def snare(): return lp(nz(0.15), 0.6) * ex(0.15, 22) * 0.6 + np.sin(2 * np.pi * 190 * tt(0.15)) * ex(0.15, 30) * 0.3
def hat(): return (nz(0.04) - lp(nz(0.04), 0.3)) * ex(0.04, 90) * 0.25
def song(prog, bpm, bars, lead=True, drive=1.0, minor=True):
    beat = 60 / bpm; L = int(SR * beat * 4 * bars); o = np.zeros(L + SR)
    def put(x, t): i = int(t * SR); o[i:i + len(x)] += x[:len(o) - i]
    for b in range(bars):
        root = prog[b % len(prog)]; t0 = b * 4 * beat
        for k in range(8):
            t = t0 + k * beat / 2; f = hz(root) / 2
            put(np.tanh(3 * np.sin(2 * np.pi * f * tt(beat / 2 * 0.9))) * ex(beat / 2 * 0.9, 4) * 0.35 * drive, t)
            put(hat(), t + beat / 4)
        for k in range(4):
            put(kick() * 0.9, t0 + k * beat)
            if k % 2: put(snare(), t0 + k * beat)
        if lead:
            third = 3 if minor else 4
            ch = [hz(root) * 2, hz(root) * 2 * 2 ** (third / 12), hz(root) * 2 * 2 ** (7 / 12), hz(root) * 4]
            for k in range(16):
                f = ch[(k * 3 + b) % 4] if k % 4 != 3 else ch[3]
                put(sq(f, beat / 4 * 0.8, 0.25) * ex(beat / 4 * 0.8, 9) * 0.07, t0 + k * beat / 4)
    return o[:L]
save('music_battle.wav', song(['A3', 'A3', 'F3', 'G3', 'A3', 'A3', 'C4', 'G3'], 128, 8), 0.3)
save('music_boss.wav', song(['D3', 'D3', 'A#2', 'C3', 'D3', 'F3', 'A#2', 'A2'], 148, 8, drive=1.3), 0.32)
save('music_title.wav', song(['C4', 'G3', 'A3', 'F3'], 112, 8, minor=False, drive=0.8), 0.26)
print('assets ok')
