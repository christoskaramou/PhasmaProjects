# Textures (backdrops, capsule letters) and sound for Arkanoid Remix. The music is original (not Taito's score).
import numpy as np, os
from PIL import Image, ImageDraw, ImageFont, ImageFilter
from audiolib import *
rng = np.random.default_rng(7)
T = os.path.join(R, 'Textures'); os.makedirs(T, exist_ok=True)
F = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
# four backdrop patterns that cycle per round, like the arcade (deep blue tiles, green hex, red lattice, navy circuit)
N = 256
yy, xx = np.mgrid[0:N, 0:N] / N
def save_img(a, nm): Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.6)).save(os.path.join(T, nm + '.png'))
def bg(base, hi, kind, nm):
    a = np.ones((N, N, 3)) * np.array(base, float)
    if kind == 0:   # bevelled square tiles
        u, v = (xx * 4) % 1, (yy * 4) % 1
        e = np.minimum(np.minimum(u, 1 - u), np.minimum(v, 1 - v))
        a += (np.clip(0.08 - e, 0, 1) / 0.08)[..., None] * (np.array(hi) - base) * 0.8
        a[(u < 0.5) ^ (v < 0.5)] *= 0.92
    elif kind == 1:  # hexagon cells
        s = 6; px, py = xx * s, yy * s * 1.1547
        r = np.round(py); q = np.round(px - 0.5 * (r % 2))
        d = np.hypot(px - (q + 0.5 * (r % 2)), (py - r) * 0.866)
        a += (np.clip(d - 0.38, 0, 1) / 0.2)[..., None] * (np.array(hi) - base)
    elif kind == 2:  # diagonal lattice
        u, v = ((xx + yy) * 4) % 1, ((xx - yy) * 4) % 1
        l = np.minimum(np.minimum(u, 1 - u), np.minimum(v, 1 - v))
        a += (np.clip(0.06 - l, 0, 1) / 0.06)[..., None] * (np.array(hi) - base)
    else:            # circuit traces
        u, v = (xx * 8) % 1, (yy * 8) % 1
        m = ((np.abs(u - 0.5) < 0.06) & ((np.floor(yy * 8) + np.floor(xx * 8)) % 2 == 0)) | ((np.abs(v - 0.5) < 0.06) & ((np.floor(xx * 8)) % 3 != 0))
        a[m] = hi
        dots = np.hypot(u - 0.5, v - 0.5) < 0.12; a[dots] = np.array(hi) * 1.1
    a *= (0.92 + 0.08 * rng.random((N, N)))[..., None] ** 0.3
    save_img(a, nm)
bg((22, 34, 92), (70, 100, 190), 0, 'bg0'); bg((18, 70, 48), (60, 150, 100), 1, 'bg1')
bg((86, 24, 30), (170, 70, 70), 2, 'bg2'); bg((16, 22, 50), (60, 110, 170), 3, 'bg3')
for k in 'SCLEDBP':
    im = Image.new('RGB', (128, 64), (20, 20, 24)); d = ImageDraw.Draw(im)
    d.text((64, 33), k, fill=(250, 245, 230), font=ImageFont.truetype(F, 48), anchor='mm')
    im.save(os.path.join(T, 'lbl_' + k + '.png'))
# ------------------------------------------------------------------ audio
def nz(d, k): return rng.standard_normal(int(SR * d)) * np.exp(-tt(d) * k)
def ping(f, d=0.12, k=30): return np.sin(2 * np.pi * f * tt(d)) * np.exp(-tt(d) * k)
save('paddle.wav', env(ping(520, 0.12, 35) + 0.4 * ping(1040, 0.12, 50)), 0.35)
save('brick.wav', env(ping(880, 0.1, 45) + 0.3 * sq(880, 0.1, 0.5) * np.exp(-tt(0.1) * 60)), 0.3)
save('hard.wav', env(sum(ping(f, 0.3, k) for f, k in ((1250, 14), (1870, 18), (2650, 24)))), 0.3)
save('wall.wav', env(ping(330, 0.08, 50)), 0.25)
save('laser.wav', env(np.sin(2 * np.pi * np.cumsum(np.linspace(2200, 700, int(SR * 0.12))) / SR), 0.002, 0.02), 0.2)
save('capsule.wav', mix(melody([('C5', 0.25), ('E5', 0.25), ('G5', 0.25), ('C6', 0.5)], 400, 'sq', 0.25)), 0.25)
save('enlarge.wav', env(np.sin(2 * np.pi * np.cumsum(np.linspace(300, 900, int(SR * 0.35))) / SR)), 0.25)
save('split.wav', mix(melody([('G5', 0.25), ('C6', 0.25), ('G5', 0.25), ('C6', 0.25)], 480, 'sq', 0.25)), 0.25)
save('catch.wav', env(ping(260, 0.12, 30)), 0.3)
save('pop.wav', env(nz(0.25, 18) * 0.7 + ping(200, 0.25, 15)), 0.3)
save('die.wav', env(np.sin(2 * np.pi * np.cumsum(np.linspace(900, 80, int(SR * 1.2))) / SR) + nz(1.2, 3) * 0.3, 0.01, 0.2), 0.3)
save('extra.wav', mix(melody([('E5', 0.25), ('G5', 0.25), ('E6', 0.25), ('C6', 0.25), ('D6', 0.25), ('G6', 0.75)], 400, 'sq', 0.25)), 0.25)
save('warp.wav', env(np.sin(2 * np.pi * np.cumsum(np.linspace(200, 1600, int(SR * 0.8))) / SR) * 0.6 + nz(0.8, 2) * 0.2), 0.25)
save('doh_hit.wav', env(ping(140, 0.3, 10) + nz(0.3, 15) * 0.4), 0.4)
save('doh_die.wav', env(nz(2.0, 1.5) * 0.8 + ping(70, 2.0, 1.2)), 0.45)
save('doh_fire.wav', env(ping(220, 0.15, 25) * sq(110, 0.15, 0.5)), 0.2)
save('move.wav', env(nz(0.06, 40) * 0.4 + ping(160, 0.06, 40)), 0.12)
save('click.wav', env(sq(1200, 0.04, 0.3) * np.exp(-tt(0.04) * 60)), 0.25)
save('gameover.wav', mix(melody([('G4', 1), ('F#4', 1), ('F4', 1), ('E4', 3)], 170, 'sq', 0.5)), 0.3)
save('start.wav', mix(melody([('G4', 0.5), ('C5', 0.5), ('E5', 0.5), ('G5', 1), ('E5', 0.5), ('G5', 1), ('C6', 2)], 300, 'sq', 0.25),
                      melody([('C3', 1), ('E3', 1), ('G3', 1), ('C3', 3)], 300, 'tri')), 0.3)
def loop(bass, lead, bpm, nm, vol=0.22):
    save(nm, mix(melody(bass, bpm, 'tri'), melody(lead, bpm, 'sq', 0.25) * 0.4), vol)
loop([('A2', 1), ('E3', 1), ('F2', 1), ('C3', 1), ('D3', 1), ('A2', 1), ('E3', 2)] * 2,
     [('A4', 1), ('C5', 1), ('E5', 2), ('D5', 1), ('C5', 1), ('B4', 2), ('C5', 1), ('E5', 1), ('A5', 2), ('G#5', 2), ('E5', 2)], 120, 'title.wav')
loop([('C3', 2), ('A2', 2), ('F2', 2), ('G2', 2)], [('E5', 2), ('A5', 2), ('C6', 2), ('B5', 2)], 100, 'ending.wav')
loop([('D2', 0.5), ('D3', 0.5)] * 4 + [('C2', 0.5), ('C3', 0.5)] * 2 + [('A1', 0.5), ('A2', 0.5)] * 2, [('D5', 1), ('F5', 1), ('A5', 2), ('G5', 1), ('E5', 1), ('C#5', 2)], 150, 'doh.wav')
print('assets ok')
