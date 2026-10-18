# Textures (grass field checker, bricks, concrete, power-up icons), skybox and chip SFX/music for Bomberman Remix
import numpy as np, os, math
from PIL import Image, ImageDraw, ImageFilter, ImageFont
from audiolib import *
T = os.path.join(R, 'Textures'); SK = os.path.join(R, 'Skybox'); os.makedirs(T, exist_ok=True); os.makedirs(SK, exist_ok=True)
rg = np.random.default_rng(5)
def noise(n, oct=5, seed=0):
    r = np.random.default_rng(seed); g = np.zeros((n, n))
    for o in range(oct):
        f = 4 * 2 ** o; s = r.random((f, f)); g += np.asarray(Image.fromarray((s * 255).astype(np.uint8)).resize((n, n), Image.BICUBIC)) / 255 / 2 ** o
    return g / g.max()
def to_img(a): return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
# field: 31 x 13 cells, 64 px per cell, alternating two greens with blade noise and soft cell borders
C, NC, NR = 64, 31, 13
g = noise(2048, 6, 1)[:NR * C, :NC * C]
a = np.zeros((NR * C, NC * C, 3))
for r in range(NR):
    for c in range(NC):
        col = np.array((70, 132, 52)) if (r + c) % 2 == 0 else np.array((62, 120, 46))
        a[r * C:(r + 1) * C, c * C:(c + 1) * C] = col
a *= (0.82 + 0.3 * g)[..., None]
a[::C, :] *= 0.85; a[:, ::C] *= 0.85
to_img(a).save(os.path.join(T, 'field.png'))
# bricks (soft blocks): warm terracotta courses with mortar
n = 256; b = np.ones((n, n, 3)) * np.array((168, 88, 56)); gg = noise(n, 5, 2)
b *= (0.8 + 0.35 * gg)[..., None]
for row in range(8):
    y0 = row * 32; off = 0 if row % 2 == 0 else 32
    b[y0:y0 + 4, :] = (196, 186, 170)
    for x in range(-off, n, 64): b[y0:y0 + 32, max(0, x):max(0, x) + 4] = (196, 186, 170)
    b[y0 + 4:y0 + 32] *= rg.uniform(0.88, 1.08)
to_img(b).save(os.path.join(T, 'brick.png'))
# concrete (hard pillars + border)
c = np.ones((n, n, 3)) * np.array((150, 152, 158)); gc = noise(n, 6, 3)
c *= (0.75 + 0.4 * gc)[..., None]; c[:6] *= 1.15; c[-6:] *= 0.8; c[:, :6] *= 1.1; c[:, -6:] *= 0.82
to_img(c).save(os.path.join(T, 'concrete.png'))
s = np.ones((n, n, 3)) * np.array((92, 88, 96)); s *= (0.7 + 0.45 * noise(n, 6, 4))[..., None]; s[::64, :] *= 0.6; s[:, ::128] *= 0.6
to_img(s).save(os.path.join(T, 'stone.png'))
# power-up icons
F = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
def panel():
    im = Image.new('RGB', (256, 256), (24, 40, 92)); d = ImageDraw.Draw(im)
    d.rounded_rectangle((6, 6, 250, 250), 26, fill=(36, 66, 150), outline=(230, 230, 240), width=8)
    return im, d
def flame(d, cx, cy, s, c1=(255, 120, 20), c2=(255, 230, 90)):
    d.polygon([(cx, cy - 90 * s), (cx + 55 * s, cy), (cx + 40 * s, cy + 55 * s), (cx, cy + 70 * s), (cx - 40 * s, cy + 55 * s), (cx - 55 * s, cy)], fill=c1)
    d.polygon([(cx, cy - 40 * s), (cx + 28 * s, cy + 18 * s), (cx, cy + 55 * s), (cx - 28 * s, cy + 18 * s)], fill=c2)
def bombi(d, cx, cy, r):
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(20, 20, 26)); d.ellipse((cx - r * .55, cy - r * .6, cx - r * .2, cy - r * .3), fill=(200, 200, 210))
    d.rectangle((cx + r * .45, cy - r * 1.05, cx + r * .8, cy - r * .7), fill=(90, 90, 100)); d.line((cx + r * .65, cy - r * 1.05, cx + r * .9, cy - r * 1.35), fill=(240, 200, 120), width=7)
def bricks(d, x0, y0, x1, y1):
    d.rectangle((x0, y0, x1, y1), fill=(176, 92, 58))
    for k, y in enumerate(range(y0, y1, 26)):
        d.line((x0, y, x1, y), fill=(220, 210, 190), width=4)
        for x in range(x0 + (0 if k % 2 else 26), x1, 52): d.line((x, y, x, min(y1, y + 26)), fill=(220, 210, 190), width=4)
icons = {}
im, d = panel(); bombi(d, 128, 140, 70); icons['bombs'] = im
im, d = panel(); flame(d, 128, 140, 1.2); icons['fire'] = im
im, d = panel()
d.polygon([(60, 70), (120, 70), (125, 140), (200, 150), (205, 180), (55, 180)], fill=(230, 60, 60)); d.rectangle((55, 180, 205, 192), fill=(240, 240, 240))
for x in (80, 180): d.ellipse((x - 18, 190, x + 18, 226), fill=(30, 30, 30))
icons['speed'] = im
im, d = panel(); bricks(d, 60, 70, 196, 200); d.polygon([(40, 135), (150, 95), (150, 115), (216, 115), (216, 155), (150, 155), (150, 175)], fill=(250, 250, 255)); icons['wallpass'] = im
im, d = panel(); d.rounded_rectangle((80, 90, 176, 220), 14, fill=(60, 60, 70)); d.ellipse((104, 120, 152, 168), fill=(230, 40, 40))
d.line((150, 92, 180, 40), fill=(200, 200, 210), width=8); d.ellipse((172, 30, 192, 50), fill=(230, 40, 40)); icons['detonator'] = im
im, d = panel(); bombi(d, 140, 140, 55); d.polygon([(30, 130), (180, 130), (180, 105), (230, 145), (180, 185), (180, 160), (30, 160)], fill=(250, 250, 255)); icons['bombpass'] = im
im, d = panel(); flame(d, 128, 135, 1.0); d.arc((40, 40, 216, 230), 200, 340, fill=(140, 220, 255), width=12); d.arc((40, 60, 216, 250), 20, 160, fill=(140, 220, 255), width=12); icons['flamepass'] = im
im, d = panel(); d.text((128, 132), '?', fill=(255, 230, 90), font=ImageFont.truetype(F, 170), anchor='mm'); icons['mystery'] = im
for k, im in icons.items(): im.save(os.path.join(T, 'pu_' + k + '.png'))
# daylight skybox
HW, HH = 512, 256
v = (np.arange(HH) + 0.5) / HH
y = np.sin((0.5 - v) * np.pi)[:, None] * np.ones((1, HW))
t = np.clip(y, 0, 1)[..., None]
sky = np.array([0.95, 0.92, 0.86]) * (1 - t) + np.array([0.4, 0.58, 0.9]) * t
sky[y < 0] = np.array([0.32, 0.36, 0.26])
def rgbe(a):
    m = a.max(-1); e = np.ceil(np.log2(np.maximum(m, 1e-32))); sc = np.where(m > 1e-32, 256.0 / 2 ** e, 0)
    o = np.zeros(a.shape[:2] + (4,), np.uint8); o[..., :3] = np.clip(a * sc[..., None], 0, 255).astype(np.uint8)
    o[..., 3] = np.where(m > 1e-32, e + 128, 0).astype(np.uint8); return o
with open(os.path.join(SK, 'day.hdr'), 'wb') as f:
    f.write(b"#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y %d +X %d\n" % (HH, HW)); f.write(rgbe(sky.astype(np.float32)).tobytes())

# ------------------------------------------------------------------ audio
def sweep(f0, f1, d, duty=0.5):
    f = f0 + (f1 - f0) * tt(d) / d; return np.where((np.cumsum(f) / SR) % 1 < duty, 1.0, -1.0)
def nz(d, k): return rng.standard_normal(int(SR * d)) * np.exp(-tt(d) * k)
def lowp(x, a=0.08):
    y = np.zeros_like(x); s = 0
    for i, v in enumerate(x): s += a * (v - s); y[i] = s
    return y
save('place.wav', env(tri(220, 0.09) * np.exp(-tt(0.09) * 40) + sq(110, 0.09, 0.5) * 0.4 * np.exp(-tt(0.09) * 50)), 0.3)
save('boom.wav', env(lowp(nz(0.9, 4.5), 0.06) * 3 + sq(55, 0.9, 0.5) * 0.25 * np.exp(-tt(0.9) * 6)), 0.5)
save('walk.wav', env(tri(160, 0.035) * np.exp(-tt(0.035) * 70) + nz(0.035, 90) * 0.15), 0.14)
save('walk2.wav', env(tri(140, 0.035) * np.exp(-tt(0.035) * 70) + nz(0.035, 90) * 0.15), 0.14)
save('item.wav', melody([('C6', 0.25), ('E6', 0.25), ('G6', 0.25), ('C7', 0.25), ('E7', 0.5)], 520, 'sq', 0.25), 0.3)
save('kill.wav', env(sweep(900, 200, 0.3, 0.35) * np.exp(-tt(0.3) * 6)), 0.28)
save('brick.wav', env(lowp(nz(0.25, 14), 0.25) * 2), 0.3)
save('death.wav', mix(melody([('C6', 0.25), ('G5', 0.25), ('E5', 0.25), ('C5', 0.25), ('G4', 0.25), ('E4', 0.25), ('C4', 1)], 300, 'sq', 0.5)), 0.3)
save('clear.wav', mix(melody([('C5', 0.5), ('E5', 0.5), ('G5', 0.5), ('C6', 0.5), ('E6', 0.5), ('G6', 1), ('E6', 0.5), ('G6', 2)], 300, 'sq', 0.25),
                      melody([('C3', 1), ('G3', 1), ('C4', 1), ('G3', 1), ('C4', 2)], 300, 'tri')), 0.3)
save('ready.wav', mix(melody([('G4', 0.5), ('C5', 0.5), ('E5', 0.5), ('G5', 0.5), ('E5', 0.5), ('G5', 1.5)], 280, 'sq', 0.25),
                      melody([('C3', 1), ('E3', 1), ('G3', 2)], 280, 'tri')), 0.3)
save('gameover.wav', mix(melody([('E5', 1), ('D5', 1), ('C5', 1), ('B4', 1), ('A4', 1), ('G#4', 1), ('A4', 3)], 200, 'sq', 0.5)), 0.3)
save('click.wav', env(sq(1200, 0.04, 0.3) * np.exp(-tt(0.04) * 60)), 0.25)
save('warn.wav', env(sq(880, 0.12, 0.5)), 0.22)
save('door.wav', melody([('G5', 0.25), ('B5', 0.25), ('D6', 0.25), ('G6', 0.75)], 400, 'sq', 0.25), 0.28)
save('spawn.wav', env(sweep(200, 700, 0.5, 0.5) * np.exp(-tt(0.5) * 3)), 0.28)
save('detonate.wav', env(sq(1400, 0.06, 0.25) * np.exp(-tt(0.06) * 40)), 0.22)
save('fuse.wav', env(nz(0.25, 3) * 0.4), 0.1)
def loop(bass, lead, bpm, nm, vol=0.26):
    b = melody(bass, bpm, 'tri'); l = melody(lead, bpm, 'sq', 0.25) if lead else np.zeros(1)
    save(nm, mix(b, l * 0.45), vol)
# a jaunty stage loop in the spirit of the NES theme (original composition)
loop(([('C3', 0.5), ('C4', 0.5)] * 2 + [('F3', 0.5), ('F4', 0.5)] * 2 + [('G3', 0.5), ('G4', 0.5)] * 2 + [('C3', 0.5), ('C4', 0.5)] * 2) * 2,
     [('E5', 0.5), ('G5', 0.5), ('C6', 0.5), ('G5', 0.5), ('A5', 0.5), ('F5', 0.5), ('A5', 1), ('B5', 0.5), ('G5', 0.5), ('D6', 0.5), ('B5', 0.5), ('C6', 2),
      ('E5', 0.5), ('D5', 0.5), ('C5', 0.5), ('D5', 0.5), ('F5', 0.5), ('E5', 0.5), ('D5', 1), ('G5', 0.5), ('F5', 0.5), ('E5', 0.5), ('D5', 0.5), ('C5', 2)], 240, 'bgm1.wav')
loop(([('A2', 0.5), ('A3', 0.5)] * 2 + [('D3', 0.5), ('D4', 0.5)] * 2 + [('E3', 0.5), ('E4', 0.5)] * 2 + [('A2', 0.5), ('A3', 0.5)] * 2) * 2,
     [('A4', 0.5), ('C5', 0.5), ('E5', 1), ('D5', 0.5), ('F5', 0.5), ('A5', 1), ('G#5', 0.5), ('E5', 0.5), ('B5', 1), ('A5', 2),
      ('C6', 0.5), ('B5', 0.5), ('A5', 1), ('F5', 0.5), ('D5', 0.5), ('E5', 1), ('B4', 0.5), ('D5', 0.5), ('C5', 0.5), ('B4', 0.5), ('A4', 2)], 250, 'bgm2.wav')
loop([('C3', 1), ('A2', 1), ('F2', 1), ('G2', 1)] * 2, [('E5', 1), ('C5', 1), ('A4', 1), ('B4', 1), ('C5', 1), ('E5', 1), ('D5', 2)], 170, 'title.wav')
loop([('C3', 0.25), ('C4', 0.25)] * 16, [('C6', 0.25), ('B5', 0.25)] * 16, 320, 'hurry.wav')
print('assets ok')
