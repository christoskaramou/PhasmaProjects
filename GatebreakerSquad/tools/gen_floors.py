# Richer ground textures (run after gen_assets.py): forest grass+leaf litter, canyon sand with dune ripples.
import numpy as np, os
from PIL import Image
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'project', 'Assets', 'Textures')
N = 512
def fbm(n, oct=5, seed=0, base_f=4):
    rg = np.random.default_rng(seed); o = np.zeros((n, n)); a = 1.0; tot = 0
    for k in range(oct):
        f = base_f * 2 ** k; r = np.tile(rg.random((f, f)), (3, 3))
        im = Image.fromarray((r * 255).astype(np.uint8)).resize((n * 3, n * 3), Image.BICUBIC)
        o += np.asarray(im)[n:2 * n, n:2 * n] / 255.0 * a; tot += a; a *= 0.5
    return o / tot
def save(a, nm): Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).save(os.path.join(OUT, nm + '.png'))
yy, xx = np.mgrid[0:N, 0:N] / N
grit = np.random.default_rng(3).random((N, N))
# forest: lush green meadow with warm leaf-litter patches and tiny flowers
g = fbm(N, 6, 21, 4); m = np.clip((fbm(N, 5, 22, 2) - 0.55) * 3.2, 0, 0.85)
grass = np.array([92, 146, 70.]) * (0.78 + 0.4 * g)[..., None]
leaf = np.array([214, 118, 40.]) * (0.8 + 0.35 * fbm(N, 5, 23, 12))[..., None]
a = grass * (1 - m[..., None]) + leaf * m[..., None]
a *= (0.92 + 0.14 * grit)[..., None]
fl = np.random.default_rng(24).random((N, N)); a[fl > 0.9985] = [250, 236, 120]; a[(fl > 0.9978) & (fl <= 0.9985)] = [240, 90, 70]
save(a, 'autumn_floor')
# canyon: warm terracotta sand, soft dune ripples, darker patches
d = fbm(N, 6, 31, 4); rip = 0.5 + 0.5 * np.sin((yy * 22 + d * 3.0) * 2 * np.pi)
a = np.array([214, 150, 96.]) * (0.8 + 0.3 * d)[..., None] * (0.93 + 0.1 * rip)[..., None]
p = np.clip((fbm(N, 5, 32, 3) - 0.55) * 5, 0, 1); a = a * (1 - 0.25 * p[..., None]) + p[..., None] * np.array([40, 10, 0.]) * 0.25
a *= (0.95 + 0.08 * grit)[..., None]
save(a, 'canyon')
