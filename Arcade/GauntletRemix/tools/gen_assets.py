# Textures (stone floors, brick walls) and sound for Gauntlet Remix. The music is original (not Atari's score).
import numpy as np, os
from PIL import Image, ImageFilter
from audiolib import *
rng = np.random.default_rng(11)
T = os.path.join(R, 'Textures'); os.makedirs(T, exist_ok=True)
N = 128
yy, xx = np.mgrid[0:N, 0:N]
def noise(f, seed):
    r = np.random.default_rng(seed).random((f, f)); im = Image.fromarray((r * 255).astype(np.uint8)).resize((N, N), Image.BICUBIC)
    return np.asarray(im) / 255.0
def save(a, nm): Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.5)).save(os.path.join(T, nm + '.png'))
FLOORS = [(92, 84, 72), (70, 78, 90), (96, 78, 66), (74, 86, 70)]
WALLS = [(150, 110, 70), (120, 120, 135), (160, 80, 60), (100, 130, 95)]
for k in range(4):
    # floor: worn flagstones, 2x2 per cell
    a = np.ones((N, N, 3)) * np.array(FLOORS[k], float)
    u, v = (xx % 64), (yy % 64)
    a *= (0.85 + 0.3 * noise(16, k))[..., None]
    a *= (0.92 + 0.16 * np.random.default_rng(k).random((2, 2))[(yy // 64), (xx // 64)])[..., None]
    a[(u < 2) | (v < 2)] *= 0.55
    save(a, f'floor{k}')
    # wall: brick courses
    b = np.ones((N, N, 3)) * np.array(WALLS[k], float)
    row = yy // 32; off = (row % 2) * 32
    bu = (xx + off) % 64; bv = yy % 32
    b *= (0.82 + 0.3 * noise(24, 10 + k))[..., None]
    b *= (0.9 + 0.2 * np.random.default_rng(20 + k).random((4, 3))[row, ((xx + off) // 64) % 3])[..., None]
    b[(bu < 3) | (bv < 3)] = np.array(WALLS[k]) * 0.35
    save(b, f'wall{k}')
# ------------------------------------------------------------------ audio
def nz(d, k): return rng.standard_normal(int(SR * d)) * np.exp(-tt(d) * k)
def ping(f, d=0.12, k=30): return np.sin(2 * np.pi * f * tt(d)) * np.exp(-tt(d) * k)
def sweep(f0, f1, d): return np.sin(2 * np.pi * np.cumsum(np.linspace(f0, f1, int(SR * d))) / SR)
from audiolib import save as wsave
wsave('shot.wav', env(nz(0.14, 25) * 0.6 + sweep(900, 300, 0.14) * 0.4), 0.25)
wsave('magic.wav', env(sweep(400, 1400, 0.18) * 0.6 + nz(0.18, 15) * 0.3), 0.22)
wsave('hit.wav', env(ping(200, 0.1, 40) + nz(0.1, 50) * 0.5), 0.3)
wsave('kill.wav', env(sweep(600, 120, 0.2) * 0.6 + nz(0.2, 20) * 0.4), 0.28)
wsave('gen.wav', env(nz(0.4, 8) * 0.8 + ping(90, 0.4, 8)), 0.4)
wsave('key.wav', env(ping(1800, 0.2, 14) + ping(2400, 0.2, 18) * 0.5), 0.25)
wsave('food.wav', mix(melody([('C5', 0.25), ('G5', 0.25), ('C6', 0.5)], 420, 'sq', 0.3)), 0.22)
wsave('treasure.wav', mix(melody([('E6', 0.2), ('G6', 0.2), ('C7', 0.4)], 480, 'sq', 0.25)), 0.2)
wsave('potion.wav', env(sweep(300, 900, 0.3)), 0.22)
wsave('bomb.wav', env(nz(1.0, 3) * 0.8 + sweep(200, 40, 1.0) * 0.5, 0.005, 0.2), 0.45)
wsave('door.wav', env(nz(0.5, 6) * 0.3 + sweep(120, 60, 0.5) * 0.5), 0.35)
wsave('exit.wav', env(sweep(200, 1200, 0.9) * 0.5 + nz(0.9, 3) * 0.2), 0.3)
wsave('hurt.wav', env(sweep(400, 200, 0.12) * sq(80, 0.12, 0.5) * 0.5), 0.25)
wsave('drain.wav', env(sweep(300, 120, 0.6) * 0.6 * np.sin(2 * np.pi * 9 * tt(0.6))), 0.3)
wsave('step.wav', env(nz(0.05, 60) * 0.5 + ping(120, 0.05, 50)), 0.1)
wsave('warn.wav', mix(melody([('A5', 0.3), ('F5', 0.3), ('A5', 0.3), ('F5', 0.6)], 300, 'sq', 0.4)), 0.25)
wsave('click.wav', env(sq(1200, 0.04, 0.3) * np.exp(-tt(0.04) * 60)), 0.25)
wsave('die.wav', env(sweep(500, 60, 1.4) * 0.6 + nz(1.4, 2) * 0.3, 0.01, 0.3), 0.3)
wsave('start.wav', mix(melody([('D4', 0.5), ('A4', 0.5), ('D5', 1), ('C5', 0.5), ('A4', 0.5), ('D5', 2)], 220, 'sq', 0.3),
                       melody([('D3', 2), ('A2', 2), ('D3', 2)], 220, 'tri')), 0.3)
def loop(bass, lead, bpm, nm, vol=0.2):
    wsave(nm, mix(melody(bass, bpm, 'tri'), melody(lead, bpm, 'sq', 0.3) * 0.35), vol)
loop([('D2', 1), ('D3', 1), ('C3', 1), ('A2', 1), ('Bb2' if False else 'A#2', 1), ('F2', 1), ('A2', 2)] * 2,
     [('D5', 1), ('F5', 1), ('A5', 1), ('G5', 1), ('F5', 1), ('E5', 1), ('D5', 2), ('A4', 1), ('C5', 1), ('D5', 1), ('E5', 1), ('F5', 1), ('E5', 1), ('D5', 2)], 130, 'title.wav')
loop([('D2', 0.5), ('A2', 0.5)] * 4 + [('C2', 0.5), ('G2', 0.5)] * 2 + [('A#1', 0.5), ('F2', 0.5)] * 2, [('D4', 4), ('F4', 2), ('E4', 2)], 140, 'level.wav', 0.16)
wsave('gameover.wav', mix(melody([('D4', 1), ('C#4', 1), ('C4', 1), ('A3', 3)], 160, 'sq', 0.5)), 0.3)
print('assets ok')
