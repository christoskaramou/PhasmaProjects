# Particle textures shared by the arcade remakes -> <project>/Assets/Textures/fx/*.png
# usage: python3 gen_fx_textures.py <project Assets dir>
# All RGBA, white-ish (tinted at runtime by color_start/color_end), soft alpha falloff. Flipbooks are 4x4 frames.
import numpy as np, os, sys
from PIL import Image, ImageFilter
out = os.path.join(sys.argv[1] if len(sys.argv) > 1 else '.', 'Textures', 'fx'); os.makedirs(out, exist_ok=True)
rng = np.random.default_rng(3)
def noise(n, f, seed):
    r = np.random.default_rng(seed).random((f, f))
    return np.asarray(Image.fromarray((r * 255).astype(np.uint8)).resize((n, n), Image.BICUBIC)) / 255.0
def fbm(n, seed, oct=4):
    a = np.zeros((n, n)); amp = 1; tot = 0
    for o in range(oct): a += amp * noise(n, 4 * 2 ** o, seed + o); tot += amp; amp *= 0.5
    return a / tot
def save(a, nm, rgb=None):
    a = np.clip(a, 0, 1)
    if rgb is None: rgb = np.ones(a.shape + (3,))
    im = np.concatenate([np.clip(rgb, 0, 1), a[..., None]], -1)
    Image.fromarray((im * 255).astype(np.uint8), 'RGBA').save(os.path.join(out, nm + '.png'))
def grid(n):
    y, x = np.mgrid[0:n, 0:n] / (n - 1) * 2 - 1; return x, y, np.sqrt(x * x + y * y)
N = 64
x, y, r = grid(N)
save(np.clip(1 - r, 0, 1) ** 2.2, 'soft')                       # round soft glow
save(np.clip(1 - r, 0, 1) ** 6 + 0.25 * np.clip(1 - r, 0, 1) ** 1.5, 'ember')   # hot core + halo
# spark streak: long thin glow (stretched along velocity when the emitter orients particles)
xs, ys, _ = grid(N)
save(np.exp(-(xs / 0.12) ** 2) * np.clip(1 - np.abs(ys), 0, 1) ** 1.5, 'spark')
# shock ring
save(np.exp(-((r - 0.78) / 0.09) ** 2) * (r < 1), 'ring')
# flipbooks: 4x4 frames of 128px
F = 128
def book(frame_fn, nm):
    big = np.zeros((F * 4, F * 4)); rgbb = np.zeros((F * 4, F * 4, 3))
    for i in range(16):
        a, rgb = frame_fn(i / 15.0, i)
        cy, cx = (i // 4) * F, (i % 4) * F
        big[cy:cy + F, cx:cx + F] = a; rgbb[cy:cy + F, cx:cx + F] = rgb
    save(big, nm, rgbb)
fx, fy, fr = grid(F)
NA, NB, NC = fbm(F, 101, 5), fbm(F, 202, 5), fbm(F, 303, 5)
def evolve(t):   # coherent noise across frames: blend three fields so neighbouring frames stay similar
    return (NA * (1 - t) + NB * t) if t < 0.5 else (NB * (1.5 - t) + NC * (t - 0.5)) if False else NA * (1 - t) + NB * t * 0.6 + NC * t * 0.4
def fire_frame(t, i):
    # turbulent billowing fireball: noisy edge that grows and breaks up; brightness falls off toward the rim
    n = evolve(t)
    edge = 0.55 + 0.35 * t
    d = fr + (n - 0.5) * (0.55 + 0.4 * t)
    a = np.clip((edge - d) / 0.25, 0, 1) * (1 - 0.65 * t) ** 0.8
    core = np.clip(1 - fr / (0.7 - 0.3 * t), 0, 1)
    rgb = np.stack([np.ones_like(fr), 0.55 + 0.45 * core, 0.25 + 0.75 * core ** 2], -1)   # white-yellow core, orange rim
    return a, rgb
book(fire_frame, 'fire')
def smoke_frame(t, i):
    n = evolve(1 - t) * 0.5 + evolve(t) * 0.5
    d = fr + (n - 0.5) * 0.7
    a = np.clip((0.75 - d) / 0.45, 0, 1) ** 1.5 * np.clip(n * 1.6 - 0.35, 0, 1) * (1 - 0.5 * t)
    return a, np.ones((F, F, 3)) * (0.75 + 0.25 * n[..., None])
book(smoke_frame, 'smoke')
# debris: four angular chips (2x2 atlas, 64px each) with a lit edge
D = 64; atlas = np.zeros((128, 128)); argb = np.zeros((128, 128, 3))
dx, dy, _ = grid(D)
for k in range(4):
    pts = rng.uniform(0, 2 * np.pi, 5 + k); pts.sort(); rad = rng.uniform(0.45, 0.9, len(pts))
    ang = np.arctan2(dy, dx) % (2 * np.pi); dist = np.sqrt(dx * dx + dy * dy)
    lim = np.interp(ang, np.concatenate([pts, pts[:1] + 2 * np.pi]), np.concatenate([rad, rad[:1]]), period=2 * np.pi)
    a = np.clip((lim - dist) / 0.06, 0, 1)
    shade = 0.55 + 0.45 * np.clip(-dx * 0.7 - dy * 0.7, -1, 1)
    cy, cx = (k // 2) * D, (k % 2) * D
    atlas[cy:cy + D, cx:cx + D] = a; argb[cy:cy + D, cx:cx + D] = shade[..., None]
save(atlas, 'debris', argb)
print('fx textures ->', out)
