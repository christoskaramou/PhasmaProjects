# Textures (planet, ring) and sound for Galaxian Remix. All sounds and music are original recreations in the arcade's
# spirit (the swarm hum, dive whistle, shot and explosions); no audio is taken from the arcade.
import numpy as np, os
from PIL import Image, ImageFilter
from audiolib import *
rng = np.random.default_rng(11)
T = os.path.join(R, 'Textures'); os.makedirs(T, exist_ok=True)
N = 512
yy, xx = np.mgrid[0:N, 0:N] / N
def noise(f, seed, n=N):
    r = np.random.default_rng(seed).random((f, f)); return np.asarray(Image.fromarray((r * 255).astype(np.uint8)).resize((n, n), Image.BICUBIC)) / 255.0
def img(a, nm, blur=0.5): Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(blur)).save(os.path.join(T, nm + '.png'))
# gas giant: soft latitude bands (V runs pole to pole), warped by noise; muted ochre / slate tones
v = yy + 0.03 * (noise(8, 1) - 0.5) + 0.012 * (noise(32, 2) - 0.5)
band = 0.5 + 0.5 * np.sin(v * 2 * np.pi * 7.0) * (0.6 + 0.4 * np.sin(v * 2 * np.pi * 2.3))
c0, c1 = np.array([150, 112, 78.]), np.array([196, 168, 128.])
p = c0 + (c1 - c0) * band[..., None]
p *= (0.9 + 0.2 * noise(64, 3))[..., None]
storm = np.exp(-(((xx - 0.3) / 0.05) ** 2 + ((yy - 0.62) / 0.025) ** 2)); p = p * (1 - 0.4 * storm[..., None]) + np.array([170, 90, 60.]) * 0.4 * storm[..., None]
img(p, 'planet', 0.8)
# ring bands run across the torus tube (V), so they read as concentric rings once it is flattened
rv = np.arange(256) / 256
r = np.ones((256, 64, 3)) * np.array([180, 165, 140.]) * (0.35 + 0.65 * np.sin(rv * np.pi * 11) ** 2 * (0.6 + 0.4 * np.sin(rv * np.pi * 3) ** 2))[:, None, None]
img(r, 'ring', 0.6)
# ------------------------------------------------------------------ audio
def nz(d, k): return rng.standard_normal(int(SR * d)) * np.exp(-tt(d) * k)
def ping(f, d=0.12, k=30): return np.sin(2 * np.pi * f * tt(d)) * np.exp(-tt(d) * k)
def sweep(f0, f1, d, shape=None):
    f = np.linspace(f0, f1, int(SR * d)) if shape is None else f0 + (f1 - f0) * shape(np.linspace(0, 1, int(SR * d)))
    return np.sin(2 * np.pi * np.cumsum(f) / SR)
save('shot.wav', env(sweep(1800, 500, 0.22) * np.exp(-tt(0.22) * 8) + sq(900, 0.22, 0.3) * 0.15 * np.exp(-tt(0.22) * 20)), 0.22)
# the dive: a falling whistle with a little vibrato
d = 1.1; t = tt(d); f = 1500 - 1000 * (t / d) ** 0.8 + 25 * np.sin(2 * np.pi * 9 * t)
save('dive.wav', env(np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 1.2), 0.02, 0.15), 0.16)
save('hit.wav', env(nz(0.25, 14) * 0.7 + sweep(700, 120, 0.25) * 0.4, 0.002, 0.05), 0.3)
save('hit_flag.wav', env(nz(0.6, 5) * 0.6 + sweep(500, 60, 0.6) * 0.5 + ping(880, 0.6, 4) * 0.3, 0.002, 0.1), 0.35)
save('pdie.wav', env(nz(1.6, 2.2) * 0.8 + sweep(400, 40, 1.6) * 0.4, 0.002, 0.3), 0.42)
save('bomb.wav', env(sweep(600, 900, 0.08) * 0.5), 0.08)
save('move.wav', env(nz(0.08, 30) * 0.25 + sweep(260, 200, 0.08) * 0.2), 0.08)
save('click.wav', env(sq(1200, 0.04, 0.3) * np.exp(-tt(0.04) * 60)), 0.25)
save('extra.wav', mix(melody([('C5', 0.25), ('E5', 0.25), ('G5', 0.25), ('C6', 0.25), ('E6', 0.25), ('G6', 0.75)], 420, 'sq', 0.25)), 0.25)
save('wave.wav', mix(melody([('G5', 0.25), ('C6', 0.25), ('E6', 0.25), ('G6', 0.5), ('E6', 0.25), ('G6', 1)], 360, 'sq', 0.3)), 0.25)
save('gameover.wav', mix(melody([('C5', 1), ('B4', 1), ('A#4', 1), ('A4', 3)], 170, 'sq', 0.5)), 0.3)
# an original start fanfare (not Namco's)
save('start.wav', mix(melody([('C5', 0.5), ('G4', 0.5), ('C5', 0.5), ('E5', 0.5), ('D5', 0.5), ('G4', 0.5), ('B4', 0.5), ('D5', 0.5), ('C5', 2)], 300, 'sq', 0.4),
                      melody([('C3', 2), ('G2', 2), ('C3', 2)], 300, 'tri')), 0.3)
# the swarm: a slow rising and falling hum that plays under the action, like the arcade's background drone
d = 4.0; t = tt(d); f = 150 + 45 * (0.5 - 0.5 * np.cos(2 * np.pi * t / d)) ** 1.5
hum = np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.6 + np.sin(2 * np.pi * np.cumsum(f * 2.01) / SR) * 0.2
save('swarm.wav', hum, 0.07)
def loop(bass, lead, bpm, nm, vol=0.2):
    save(nm, mix(melody(bass, bpm, 'tri'), melody(lead, bpm, 'sq', 0.3) * 0.35), vol)
loop([('A2', 1), ('F2', 1), ('C3', 1), ('G2', 1)] * 2, [('E5', 1), ('A5', 1), ('C6', 1.5), ('B5', 0.5), ('A5', 1), ('G5', 1), ('E5', 2)], 112, 'title.wav')
print('assets ok')
