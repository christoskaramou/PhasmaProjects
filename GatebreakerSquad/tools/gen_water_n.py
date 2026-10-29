# Regenerate only Textures/water_n.png (same recipe as gen_assets.py) without rebuilding the other assets/audio.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image, ImageFilter
T = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'project', 'Assets', 'Textures'); N = 512
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
a = normal_from(fbm(N, 4, 5, 4) + 0.3 * fbm(N, 3, 6, 8), 3.5)
Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.5)).save(os.path.join(T, 'water_n.png'))
print('water_n ok')
