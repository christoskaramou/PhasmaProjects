# Extra dungeon textures for the later floors (wall4/5, floor4/5): dressed ashlar blocks and rough cave stone,
# plus the trap and stun floor tiles. Same 128px style as gen_assets.py; no sound is touched here.
import numpy as np, os
from PIL import Image, ImageFilter
H = os.path.dirname(os.path.abspath(__file__))
T = os.path.join(H, '..', 'project', 'Assets', 'Textures'); os.makedirs(T, exist_ok=True)
N = 128
yy, xx = np.mgrid[0:N, 0:N]
def noise(f, seed):
    r = np.random.default_rng(seed).random((f, f)); im = Image.fromarray((r * 255).astype(np.uint8)).resize((N, N), Image.BICUBIC)
    return np.asarray(im) / 255.0
def save(a, nm): Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.5)).save(os.path.join(T, nm + '.png'))
# wall4: big dressed ashlar blocks, grey-tan; wall5: rough cave stone, blotchy
b = np.ones((N, N, 3)) * np.array((138, 128, 112), float)
row = yy // 43; off = (row % 2) * 32; bu = (xx + off) % 64; bv = yy % 43
b *= (0.85 + 0.25 * noise(20, 41))[..., None]
b *= (0.9 + 0.2 * np.random.default_rng(42).random((4, 3))[row, ((xx + off) // 64) % 3])[..., None]
b[(bu < 2) | (bv < 2)] = np.array((138, 128, 112)) * 0.4
b[(bu == 2) | (bv == 2)] *= 1.15
save(b, 'wall4')
c = np.ones((N, N, 3)) * np.array((112, 104, 96), float)
c *= (0.65 + 0.45 * noise(6, 51) * 0.6 + 0.4 * noise(18, 52) * 0.5)[..., None]
cr = noise(10, 53); c[np.abs(cr - 0.5) < 0.015] *= 0.45
save(c, 'wall5')
# floor4: herringbone-ish small pavers; floor5: packed earth with pebbles
a = np.ones((N, N, 3)) * np.array((86, 80, 74), float)
a *= (0.85 + 0.3 * noise(16, 61))[..., None]
u, v = xx % 32, yy % 16; sh = ((yy // 16) % 2) * 16; u = (xx + sh) % 32
a[(u < 2) | (v < 2)] *= 0.55
save(a, 'floor4')
e = np.ones((N, N, 3)) * np.array((92, 80, 64), float)
e *= (0.8 + 0.35 * noise(12, 71))[..., None]
pb = np.random.default_rng(72).random((N, N)) > 0.985; e[pb] *= 1.5
save(e, 'floor5')
# trap tile: bronze plate with a rim and a skull-less rune ring; stun tile: dark plate with a lightning zig-zag inlay
r = np.hypot(xx - 63.5, yy - 63.5)
t = np.ones((N, N, 3)) * np.array((120, 92, 52), float)
t *= (0.85 + 0.2 * noise(16, 81))[..., None]
t[(xx < 8) | (xx > 119) | (yy < 8) | (yy > 119)] *= 0.55
t[(np.abs(r - 40) < 3)] = (190, 150, 80)
t[(np.abs(r - 22) < 2)] = (170, 130, 70)
save(t, 'trap_tile')
s = np.ones((N, N, 3)) * np.array((60, 62, 70), float)
s *= (0.85 + 0.2 * noise(16, 91))[..., None]
s[(xx < 8) | (xx > 119) | (yy < 8) | (yy > 119)] *= 0.6
zz = 64 + 22 * np.sign(np.sin((yy - 64) / 18.0 * np.pi)) * np.minimum(1, np.abs(((yy - 10) % 36) - 18) / 9.0)
s[(np.abs(xx - zz) < 5) & (yy > 14) & (yy < 114)] = (200, 190, 120)
save(s, 'stun_tile')
print('tex2 ok')
