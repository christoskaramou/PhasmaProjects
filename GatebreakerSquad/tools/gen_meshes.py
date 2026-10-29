# Gatebreaker Squad meshes. World: Y up, models face +Z, lane along +Z. Smooth rounded shapes
# (superellipsoids / tubes / balls) coloured by UVs into the shared palette atlas (palette.py).
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from meshlib import *
from palette import uv
import numpy as np
rng = np.random.default_rng(7)

def C(m, name):
    u = uv(name); m.UV = [u] * len(m.V); return m

def sq(c, r, e=0.5, nu=None, nv=None, R=None, col=None):
    """superellipsoid: e=1 ellipsoid, e->0.2 rounded box"""
    mr = max(r)
    if nu is None: nu, nv = (10, 8) if mr < 0.1 else (16, 12) if mr < 0.5 else (20, 14)
    m = M(); V, N, UV, F = [], [], [], []; r = np.array(r, float); p2 = 2.0 / e
    for j in range(nv + 1):
        th = PI * j / nv
        for i in range(nu + 1):
            ph = 2 * PI * i / nu
            d = np.array([np.sin(th) * np.cos(ph), np.cos(th), np.sin(th) * np.sin(ph)])
            p = np.sign(d) * np.abs(d) ** e * r
            g = np.sign(p) * np.abs(p / r) ** (p2 - 1) / r
            ln = np.linalg.norm(g); n = g / ln if ln > 1e-9 else d
            V.append(p); N.append(n); UV.append((i / nu, j / nv))
    for j in range(nv):
        for i in range(nu):
            a = j * (nu + 1) + i; b = a + 1; cc = a + nu + 1; d = cc + 1
            F += [(a, b, d), (a, d, cc)]
    m.add(V, N, UV, F); m = xform(m, c, R)
    return C(m, col) if col else m

def B(c, r, col, nu=16, nv=10): return C(ellipsoid(c, (r, r, r) if np.isscalar(r) else r, nu, nv), col)
def S(p0, p1, r0, r1, col, n=14): return C(seg(p0, p1, r0, r1, n), col)
def cone(p0, p1, r, col, n=12): return C(seg(p0, p1, r, 0.001, n), col)
def T(R0, r, col, c=(0, 0, 0), Rm=None, nu=28, nv=8): return C(torus(R0, r, nu, nv, c, Rm), col)
def limb(pts, r, col):  # chain of capsules
    o = M()
    for a, b in zip(pts[:-1], pts[1:]): o += S(a, b, r, r, col)
    for p in pts[1:-1]: o += B(p, r, col, 12, 8)
    return o
def mir(m): return xform(m, mirror_x=True)
def sym(m): return U(m, mir(m))
RXp = lambda a: rotm(rx=a)
RY = lambda a: rotm(ry=a)
ZT = rotm(rx=PI / 2)  # +Y -> +Z for tubes

# ------------------------------------------------------------------ guns (in soldier body space, aim line y~0.63)
def gun(kind):
    g = M()
    if kind == 'rifle':
        g += sq((0, 0.63, 0.2), (0.035, 0.055, 0.08), 0.5, col='gun')
        g += sq((0, 0.645, 0.36), (0.042, 0.06, 0.15), 0.4, col='gun')
        g += sq((0, 0.57, 0.39), (0.026, 0.06, 0.032), 0.5, col='gun_l')
        g += sq((0, 0.7, 0.36), (0.022, 0.018, 0.09), 0.5, col='gun_l')
        g += S((0, 0.645, 0.5), (0, 0.645, 0.73), 0.019, 0.017, 'gun')
    elif kind == 'shotgun':
        g += sq((0, 0.62, 0.2), (0.04, 0.06, 0.1), 0.5, col='wood')
        g += sq((0, 0.645, 0.36), (0.05, 0.055, 0.1), 0.4, col='gun')
        for x in (-0.024, 0.024): g += S((x, 0.655, 0.4), (x, 0.655, 0.72), 0.024, 0.024, 'gun_l')
        g += sq((0, 0.615, 0.52), (0.04, 0.03, 0.08), 0.5, col='wood')
    elif kind == 'minigun':
        g += sq((0, 0.62, 0.3), (0.085, 0.085, 0.13), 0.45, col='gun')
        for i in range(6):
            a = 2 * PI * i / 6; x, y = np.cos(a) * 0.04, 0.63 + np.sin(a) * 0.04
            g += S((x, y, 0.4), (x, y, 0.82), 0.014, 0.014, 'gun_l', 8)
        g += T(0.05, 0.012, 'gun', (0, 0.63, 0.62), ZT); g += T(0.05, 0.012, 'gun', (0, 0.63, 0.8), ZT)
        g += sq((0.13, 0.58, 0.26), (0.07, 0.08, 0.08), 0.5, col='olive')
        g += sq((0, 0.72, 0.3), (0.025, 0.035, 0.08), 0.5, col='yellow')
    elif kind == 'rocket':
        g += S((0.12, 0.84, -0.25), (0.12, 0.84, 0.55), 0.075, 0.075, 'olive', 16)
        g += T(0.078, 0.014, 'hazard', (0.12, 0.84, 0.5), ZT); g += T(0.078, 0.014, 'hazard', (0.12, 0.84, -0.2), ZT)
        g += B((0.12, 0.84, 0.56), (0.05, 0.05, 0.02), 'black', 12, 6)
        g += sq((0.12, 0.74, 0.18), (0.025, 0.07, 0.03), 0.5, col='gun')
        g += sq((0.06, 0.9, 0.15), (0.03, 0.04, 0.05), 0.5, col='gun_l')
    elif kind == 'laser':
        g += sq((0, 0.645, 0.3), (0.05, 0.065, 0.2), 0.35, col='white')
        g += sq((0, 0.6, 0.2), (0.03, 0.05, 0.05), 0.5, col='gun')
        for z in (0.36, 0.44, 0.52): g += T(0.05, 0.012, 'cyan_g', (0, 0.645, z), ZT)
        g += S((0, 0.645, 0.5), (0, 0.645, 0.7), 0.03, 0.02, 'white')
        g += B((0, 0.645, 0.71), 0.024, 'cyan_g', 10, 6)
        g += sq((0, 0.72, 0.3), (0.012, 0.012, 0.12), 0.5, col='cyan_g')
    elif kind == 'sniper':
        g += sq((0, 0.63, 0.18), (0.035, 0.06, 0.1), 0.5, col='wood')
        g += sq((0, 0.645, 0.36), (0.035, 0.05, 0.14), 0.4, col='gun')
        g += S((0, 0.645, 0.48), (0, 0.645, 0.98), 0.016, 0.014, 'gun')
        g += S((0, 0.72, 0.26), (0, 0.72, 0.46), 0.03, 0.03, 'gun_l'); g += B((0, 0.72, 0.465), (0.03, 0.03, 0.006), 'glass', 10, 4)
    elif kind == 'cannon':   # heavy's arm cannon (bigger)
        g += sq((0.25, 0.9, 0.35), (0.14, 0.14, 0.22), 0.45, col='gun')
        for i in range(6):
            a = 2 * PI * i / 6; x, y = 0.25 + np.cos(a) * 0.07, 0.9 + np.sin(a) * 0.07
            g += S((x, y, 0.5), (x, y, 1.05), 0.025, 0.025, 'gun_l', 8)
        g += T(0.09, 0.02, 'blue_g', (0.25, 0.9, 0.8), ZT)
    return g

# ------------------------------------------------------------------ soldiers
PAL_SOL = dict(uni='blue', vest='blue_d', helm='helm', pack='blue_d', trim='navy')
PAL_VET = dict(uni='gold_c', vest='gold', helm='gold', pack='gold_c', trim='crim_d')
def scl(m, k, piv):
    o = M(); V = (np.array(m.V, float) - np.array(piv)) * k + np.array(piv)
    o.V, o.N, o.UV, o.F = list(V), list(m.N), list(m.UV), list(m.F); return o
GX, GY = 0.15, 0.1  # gun carried on the right side so the barrel reads past the body from the rear camera
def soldier(p, weapon, hero=None):
    m = M()
    m += sq((0, 0.66, 0), (0.2, 0.22, 0.15), 0.55, col=p['uni'])
    m += sq((0, 0.69, 0.005), (0.215, 0.15, 0.162), 0.45, col=p['vest'])
    m += sq((0, 0.5, 0), (0.205, 0.035, 0.152), 0.35, col='belt')
    m += sq((0.1, 0.5, 0.14), (0.04, 0.03, 0.02), 0.5, col='gold' if hero else 'gun_l')
    m += sq((0, 0.45, 0), (0.17, 0.08, 0.13), 0.6, col=p['trim'])
    # backpack: big tan pack + rolled bedroll on top + pouches (the rear camera's main read)
    pk = 'tan' if not hero else p['pack']
    m += sq((0, 0.7, -0.19), (0.17, 0.18, 0.1), 0.4, col=pk)
    m += sq((0, 0.62, -0.29), (0.12, 0.07, 0.03), 0.5, col='belt' if not hero else pk)
    m += S((-0.17, 0.93, -0.2), (0.17, 0.93, -0.2), 0.07, 0.07, 'bone' if not hero else 'belt', 14)
    for x in (-0.17, 0.17): m += B((x, 0.93, -0.2), (0.012, 0.072, 0.072), 'belt', 8, 6)
    for x in (-0.09, 0.09): m += B((x, 0.93, -0.2), (0.02, 0.075, 0.075), 'belt', 8, 6)
    for x in (-0.11, 0.11): m += S((x, 0.86, -0.08), (x, 0.55, -0.1), 0.022, 0.022, 'belt', 6)
    # head
    m += B((0, 1.0, 0.02), 0.19, 'skin', 20, 14)
    for x in (-0.068, 0.068): m += B((x, 1.0, 0.19), (0.026, 0.036, 0.014), 'black', 10, 6)
    m += B((0, 0.955, 0.205), (0.025, 0.02, 0.02), 'skin_d', 8, 6)
    m += B((0, 0.9, 0.16), (0.05, 0.012, 0.02), 'skin_d', 8, 4)
    for x in (-0.19, 0.19): m += B((x, 0.99, 0.0), (0.03, 0.05, 0.035), 'skin', 8, 6)
    if hero is None:
        m += B((0, 1.08, -0.01), (0.215, 0.165, 0.225), p['helm'], 24, 14)
        m += sq((0, 1.0, -0.005), (0.23, 0.03, 0.238), 0.5, col=p['helm'])
        stripe = 'white' if p is PAL_SOL else 'crim_d'
        m += B((0, 1.12, -0.01), (0.07, 0.135, 0.23), stripe, 14, 10)        # crest stripe: reads from above/behind
        m += T(0.216, 0.016, 'black', (0, 1.06, -0.01), rotm(rx=PI / 2))     # goggle strap around the helmet
        for x in (-0.075, 0.075): m += B((x, 1.12, 0.185), (0.058, 0.045, 0.035), 'glass', 12, 8)
    else:
        hc, hair = hero
        m += B((0, 1.1, -0.02), (0.2, 0.1, 0.21), hc, 20, 10)          # beret / cap
        m += B((0.08, 1.15, 0.02), (0.08, 0.04, 0.09), hc, 10, 6)
        m += sq((0, 1.03, -0.02), (0.205, 0.04, 0.215), 0.5, col=hair)
        m += sq((0, 1.0, 0.03), (0.21, 0.025, 0.21), 0.6, col='red' if hc != 'red' else 'black')
    # arms holding the (bigger, right-side) gun forward
    m += limb([(0.21, 0.78, 0.0), (0.27, 0.66, 0.1), (0.07 + GX, 0.6 + GY, 0.27)], 0.06, p['uni'])
    m += limb([(-0.21, 0.78, 0.0), (-0.15, 0.7, 0.24), (-0.03 + GX, 0.63 + GY, 0.5)], 0.06, p['uni'])
    for x in (0.21, -0.21): m += sq((x, 0.8, 0), (0.095, 0.07, 0.095), 0.5, col=p['vest'])
    m += B((0.07 + GX, 0.6 + GY, 0.27), 0.055, 'skin', 10, 8); m += B((-0.03 + GX, 0.63 + GY, 0.5), 0.055, 'skin', 10, 8)
    m += xform(scl(gun(weapon), 1.3, (0, 0.63, 0.2)), (GX, GY, 0))
    return m

def leg(trim, boot='boot', s=1.0):
    m = M()
    m += S((0, 0, 0), (0, -0.2 * s, 0.01), 0.078 * s, 0.07 * s, trim)
    m += B((0, -0.2 * s, 0.01), 0.07 * s, trim, 10, 8)
    m += S((0, -0.2 * s, 0.01), (0, -0.36 * s, 0), 0.068 * s, 0.062 * s, trim)
    m += sq((0, -0.4 * s, 0.04 * s), (0.078 * s, 0.06 * s, 0.115 * s), 0.5, col=boot)
    return m

for w in ('rifle', 'shotgun', 'minigun', 'rocket', 'laser'):
    save('sol_' + w, soldier(PAL_SOL, w))
    save('vet_' + w, soldier(PAL_VET, w))
save('sol_leg', leg('navy')); save('vet_leg', leg('crim_d'))
HEROES = {'rook': ('olive', 'hair'), 'juno': ('white', 'hair'), 'bruno': ('orange', 'black'),
          'vex': ('black', 'hazard'), 'hawke': ('green_d', 'hair'), 'nova': ('gold', 'white')}
HW = {'rook': 'rifle', 'juno': 'laser', 'bruno': 'minigun', 'vex': 'rocket', 'hawke': 'sniper', 'nova': 'shotgun'}
for h, (hc, hair) in HEROES.items():
    P = dict(uni={'rook': 'olive', 'juno': 'white', 'bruno': 'orange', 'vex': 'dkgrey', 'hawke': 'green_d', 'nova': 'white'}[h],
             vest={'rook': 'green_d', 'juno': 'red', 'bruno': 'crim_d', 'vex': 'hazard', 'hawke': 'olive', 'nova': 'gold'}[h],
             helm=hc, pack='belt', trim='navy')
    save('hero_' + h, soldier(P, HW[h], (hc, hair)))
save('sniper', soldier(dict(uni='green_d', vest='olive', helm='olive', pack='olive', trim='navy'), 'sniper'))

# heavy trooper (merge tier 2): power armour with arm cannon
def heavy():
    m = M()
    m += sq((0, 0.95, 0), (0.36, 0.34, 0.26), 0.5, col='mech')
    m += sq((0, 1.0, 0.03), (0.33, 0.22, 0.26), 0.45, col='blue')
    m += sq((0, 1.02, 0.27), (0.12, 0.08, 0.02), 0.5, col='blue_g')
    m += sq((0, 0.62, 0), (0.26, 0.1, 0.2), 0.5, col='dkgrey')
    m += sq((0, 1.05, -0.3), (0.25, 0.26, 0.12), 0.4, col='mech')
    for x in (-0.12, 0.12): m += S((x, 1.25, -0.36), (x, 1.45, -0.36), 0.05, 0.04, 'gun_l')
    m += B((0, 1.42, 0.03), (0.21, 0.2, 0.22), 'blue', 18, 12)
    m += sq((0, 1.42, 0.17), (0.15, 0.06, 0.08), 0.5, col='cyan_g')
    for s in (1, -1):
        m += B((0.42 * s, 1.18, 0), (0.17, 0.14, 0.17), 'mech', 14, 10)
        m += sq((0.42 * s, 1.26, 0), (0.15, 0.04, 0.15), 0.5, col='gold')
    m += limb([(-0.42, 1.12, 0), (-0.4, 0.88, 0.15), (-0.18, 0.86, 0.4)], 0.09, 'mech')
    m += B((-0.18, 0.86, 0.42), 0.08, 'dkgrey', 10, 8)
    m += limb([(0.42, 1.12, 0), (0.3, 0.92, 0.15)], 0.1, 'mech')
    m += gun('cannon')
    return m
save('heavy', heavy()); save('hvy_leg', leg('mech', 'dkgrey', 1.45))

# ------------------------------------------------------------------ enemies (mutant horde)
def runner(shield=False, armored=False):
    # chibi mutant: big head, glowing eyes, toothy grin, bone spikes, claws raised -> reads at horde scale
    m = M(); skin = 'mutant'
    m += sq((0, 0.66, -0.03), (0.23, 0.21, 0.17), 0.7, col=skin)
    m += B((0, 0.64, 0.1), (0.17, 0.15, 0.1), 'pink', 14, 10)
    m += sq((0, 0.46, 0), (0.18, 0.08, 0.14), 0.6, col='crim_d')
    hz = 0.15
    m += B((0, 0.98, hz), (0.21, 0.19, 0.2), skin, 20, 14)
    m += B((0, 0.89, hz + 0.13), (0.13, 0.055, 0.08), 'crim_d', 12, 8)                    # open mouth
    for x in (-0.07, -0.024, 0.024, 0.07): m += cone((x, 0.935, hz + 0.19), (x, 0.885, hz + 0.2), 0.016, 'bone', 6)
    for x in (-0.075, 0.075): m += B((x, 1.03, hz + 0.17), (0.055, 0.045, 0.03), 'eye', 12, 8)
    m += sq((0, 1.075, hz + 0.16), (0.14, 0.022, 0.04), 0.5, col='crim_d')                 # angry brow
    for x in (-0.17, 0.17): m += cone((x, 1.1, hz), (x * 1.7, 1.32, hz - 0.08), 0.05, 'bone')
    for i, y in enumerate((0.92, 0.78, 0.64)): m += cone((0, y, -0.17), (0, y + 0.1, -0.36), 0.055, 'bone')
    for s in (1, -1):
        m += limb([(0.23 * s, 0.78, 0), (0.3 * s, 0.82, 0.16), (0.24 * s, 0.98, 0.32)], 0.07, skin)
        for k in (-1, 0, 1): m += cone((0.24 * s + 0.035 * k, 0.99, 0.35), (0.25 * s + 0.05 * k, 1.08, 0.42), 0.02, 'bone', 6)
    if armored:
        m += sq((0, 0.74, 0.02), (0.235, 0.17, 0.18), 0.4, col='dkgrey')
        m += B((0, 1.02, hz - 0.01), (0.18, 0.13, 0.18), 'rust', 16, 10)
        m += sq((0, 1.0, hz + 0.16), (0.11, 0.025, 0.02), 0.5, col='red_g')
        for s in (1, -1): m += sq((0.24 * s, 0.84, 0), (0.1, 0.06, 0.1), 0.5, col='rust')
    if shield:
        sh = M()
        sh += sq((0.02, 0.75, 0.55), (0.4, 0.52, 0.035), 0.3, col='hazard')
        for k in range(-2, 3): sh += sq((0.02 + k * 0.16, 0.75, 0.58), (0.035, 0.48, 0.01), 0.5, R=rotm(rz=0.5), col='black')
        sh += sq((0.02, 0.98, 0.585), (0.18, 0.06, 0.012), 0.4, col='glass')
        sh += T(0.05, 0.015, 'steel', (0.02, 0.75, 0.6), ZT)
        m += sh
    return m
save('run_body', runner()); save('shd_body', runner(True, True)); save('shd_body_ns', runner(False, True))
save('run_leg', U(S((0, 0, 0), (0, -0.22, 0.03), 0.075, 0.065, 'crim_d'), S((0, -0.22, 0.03), (0, -0.38, -0.02), 0.065, 0.055, 'mutant'),
                  sq((0, -0.41, 0.06), (0.07, 0.045, 0.11), 0.6, col='mutant')))

def brute(scale=1.0, boss=False):
    m = M(); s = scale
    m += sq((0, 1.45 * s, -0.05 * s), (0.62 * s, 0.6 * s, 0.46 * s), 0.7, col='mutant', nu=26, nv=18)
    m += B((0, 1.3 * s, 0.28 * s), (0.42 * s, 0.38 * s, 0.22 * s), 'pink', 18, 12)
    m += sq((0, 0.92 * s, 0), (0.45 * s, 0.14 * s, 0.34 * s), 0.6, col='crim_d')
    m += sq((0, 0.98 * s, 0.02 * s), (0.47 * s, 0.05 * s, 0.36 * s), 0.4, col='belt')
    m += B((0, 2.02 * s, 0.3 * s), (0.27 * s, 0.25 * s, 0.27 * s), 'mutant', 18, 12)
    m += sq((0, 1.9 * s, 0.48 * s), (0.2 * s, 0.08 * s, 0.1 * s), 0.6, col='crim_d')
    for x in (-0.12, -0.04, 0.04, 0.12): m += cone((x * s, 1.94 * s, 0.56 * s), (x * s, 2.02 * s, 0.6 * s), 0.025 * s, 'bone', 6)
    for x in (-0.1, 0.1): m += B((x * s, 2.08 * s, 0.53 * s), (0.085 * s, 0.06 * s, 0.035 * s), 'eye', 10, 6)
    m += B((0, 2.13 * s, 0.5 * s), (0.17 * s, 0.035 * s, 0.06 * s), 'crim_d', 12, 6)
    for sg in (1, -1):
        m += cone((0.2 * sg * s, 2.18 * s, 0.25 * s), (0.42 * sg * s, 2.55 * s, 0.15 * s), 0.07 * s, 'bone')
        m += sq((0.68 * sg * s, 1.88 * s, 0), (0.3 * s, 0.2 * s, 0.32 * s), 0.5, col='rust')
        for k in range(3): m += cone(((0.6 + 0.1 * k) * sg * s, 2.0 * s, (-0.15 + 0.15 * k) * s), ((0.65 + 0.12 * k) * sg * s, 2.35 * s, (-0.15 + 0.15 * k) * s), 0.05 * s, 'bone', 8)
        m += limb([(0.72 * sg * s, 1.72 * s, 0), (0.85 * sg * s, 1.2 * s, 0.15 * s), (0.75 * sg * s, 0.75 * s, 0.38 * s)], 0.17 * s, 'mutant')
        m += B((0.75 * sg * s, 0.68 * s, 0.42 * s), 0.25 * s, 'crim_d', 14, 10)
        m += T(0.2 * s, 0.05 * s, 'steel', (0.8 * sg * s, 1.02 * s, 0.28 * s), rotm(rx=1.3))
    if boss:
        m += sq((0, 1.55 * s, 0.38 * s), (0.36 * s, 0.32 * s, 0.1 * s), 0.35, col='steel')
        m += B((0, 1.55 * s, 0.47 * s), (0.13 * s, 0.13 * s, 0.05 * s), 'lava_g', 14, 8)
        m += B((0, 2.24 * s, 0.28 * s), (0.25 * s, 0.1 * s, 0.25 * s), 'gold', 16, 6)
        for k in range(5):
            a = PI * (0.15 + 0.7 * k / 4); m += cone((np.cos(a) * 0.2 * s, 2.3 * s, 0.28 * s + np.sin(a) * 0.02), (np.cos(a) * 0.26 * s, 2.5 * s, 0.28 * s), 0.04 * s, 'gold', 8)
        for k in range(4): m += cone((0, (1.3 + 0.25 * k) * s, -0.45 * s), (0, (1.45 + 0.25 * k) * s, -0.8 * s), 0.09 * s, 'bone')
    return m
save('brute_body', brute()); save('gol_body', brute(1.0, True))
def bleg(s=1.0, col='crim_d'):
    return U(S((0, 0, 0), (0, -0.45 * s, 0.05 * s), 0.2 * s, 0.17 * s, col), B((0, -0.45 * s, 0.05 * s), 0.17 * s, col, 12, 8),
             S((0, -0.45 * s, 0.05 * s), (0, -0.8 * s, 0), 0.16 * s, 0.14 * s, 'mutant'), sq((0, -0.86 * s, 0.1 * s), (0.17 * s, 0.1 * s, 0.24 * s), 0.6, col='mutant'))
save('brute_leg', bleg()); save('gol_leg', bleg(1.0, 'rust'))

def drone(ally=False):
    m = M(); body = 'white' if ally else 'crimson'
    m += sq((0, 0, 0), (0.32, 0.16, 0.32), 0.55, col=body)
    m += sq((0, 0.06, 0), (0.22, 0.1, 0.22), 0.5, col='blue' if ally else 'dkgrey')
    m += B((0, -0.02, 0.3), (0.09, 0.07, 0.04), 'cyan_g' if ally else 'red_g', 10, 6)
    for i in range(4):
        a = PI / 4 + i * PI / 2; x, z = np.cos(a) * 0.5, np.sin(a) * 0.5
        m += S((0, 0, 0), (x, 0.05, z), 0.04, 0.035, 'dkgrey'); m += S((x, 0.0, z), (x, 0.12, z), 0.05, 0.05, 'black')
    if not ally:
        m += B((0, -0.25, 0), (0.15, 0.18, 0.15), 'black', 14, 10); m += T(0.13, 0.025, 'hazard', (0, -0.22, 0), rotm(rx=PI / 2))
        m += B((0, -0.42, 0), 0.04, 'red_g', 8, 6)
    else:
        m += S((0, -0.15, 0.05), (0, -0.15, 0.35), 0.03, 0.025, 'gun')
    return m
save('fly_body', drone()); save('ally_drone', drone(True))
def rotor(rad=0.5, n=4, blade=0.2):
    m = M()
    for i in range(4):
        a = PI / 4 + i * PI / 2; x, z = np.cos(a) * rad, np.sin(a) * rad
        for k in range(2): m += sq((x, 0.14, z), (blade, 0.008, 0.025), 0.5, R=RY(k * PI / 2 + i), col='black')
    return m
save('fly_rotor', rotor())

# boss 2: Ironclad mech walker
def mech_body(enemy=True, s=1.0):
    m = M(); a, b, g = ('mech', 'crimson', 'red_g') if enemy else ('white', 'blue', 'cyan_g')
    m += sq((0, 1.7 * s, 0), (0.8 * s, 0.55 * s, 0.7 * s), 0.4, col=a, nu=24, nv=16)
    m += sq((0, 1.85 * s, 0.1 * s), (0.65 * s, 0.4 * s, 0.68 * s), 0.35, col=b)
    m += sq((0, 1.95 * s, 0.68 * s), (0.4 * s, 0.12 * s, 0.1 * s), 0.4, col=g if enemy else 'glass')
    m += sq((0, 1.2 * s, 0), (0.45 * s, 0.15 * s, 0.4 * s), 0.5, col='dkgrey')
    for sg in (1, -1):
        m += B((0.9 * sg * s, 1.85 * s, 0), (0.3 * s, 0.28 * s, 0.3 * s), a, 14, 10)
        m += sq((1.05 * sg * s, 1.55 * s, 0.4 * s), (0.2 * s, 0.2 * s, 0.55 * s), 0.4, col='dkgrey')
        for k in (-1, 1): m += S((1.05 * sg * s + 0.08 * k * s, 1.55 * s, 0.8 * s), (1.05 * sg * s + 0.08 * k * s, 1.55 * s, 1.3 * s), 0.06 * s, 0.06 * s, 'gun_l')
        m += sq((0.55 * sg * s, 2.4 * s, -0.25 * s), (0.25 * s, 0.22 * s, 0.3 * s), 0.4, col=b)
        for i in range(2):
            for j in range(2): m += B(((0.47 + 0.16 * i) * sg * s, (2.32 + 0.16 * j) * s, 0.06 * s), 0.055 * s, 'black', 8, 6)
    m += S((0, 2.2 * s, -0.5 * s), (0, 2.9 * s, -0.6 * s), 0.03 * s, 0.02 * s, 'gun_l'); m += B((0, 2.92 * s, -0.6 * s), 0.05 * s, g, 8, 6)
    return m
def mech_leg(enemy=True, s=1.0):
    a = 'mech' if enemy else 'white'
    return U(S((0, 0, 0), (0, -0.55 * s, 0.25 * s), 0.18 * s, 0.15 * s, a), B((0, -0.55 * s, 0.25 * s), 0.17 * s, 'dkgrey', 12, 8),
             S((0, -0.55 * s, 0.25 * s), (0, -1.05 * s, -0.05 * s), 0.14 * s, 0.12 * s, 'dkgrey'), S((0.1 * s, -0.3 * s, 0.25 * s), (0.1 * s, -0.9 * s, 0.05 * s), 0.04 * s, 0.04 * s, 'steel'),
             sq((0, -1.1 * s, 0.1 * s), (0.25 * s, 0.08 * s, 0.38 * s), 0.4, col=a))
save('mech_body', mech_body()); save('mech_leg', mech_leg()); save('amech_body', mech_body(False, 0.62)); save('amech_leg', mech_leg(False, 0.62))

# boss 3: Wasp Queen
def wasp():
    m = M()
    m += B((0, 0, -1.1), (0.75, 0.68, 1.15), 'crimson', 22, 16)
    for z in (-0.6, -1.1, -1.6): m += T(0.68 * (1 - abs(z + 1.1) * 0.35), 0.08, 'hazard', (0, 0, z), None, 28, 8)
    m += cone((0, 0, -2.15), (0, -0.1, -2.75), 0.18, 'bone')
    m += B((0, 0.1, 0.25), (0.48, 0.45, 0.55), 'crim_d', 18, 12)
    m += B((0, 0.15, 0.95), (0.42, 0.38, 0.4), 'crimson', 18, 12)
    for x in (-0.22, 0.22): m += B((x, 0.25, 1.22), (0.17, 0.2, 0.13), 'eye', 12, 8)
    for x in (-0.12, 0.12): m += cone((x, -0.05, 1.25), (x * 0.4, -0.2, 1.55), 0.06, 'bone')
    for x in (-0.15, 0.15): m += S((x, 0.45, 1.05), (x * 2.5, 1.0, 1.5), 0.025, 0.02, 'black')
    for s in (1, -1):
        for k in range(3): m += limb([(0.35 * s, -0.25, 0.4 - 0.25 * k), (0.8 * s, -0.4, 0.5 - 0.3 * k), (0.95 * s, -1.0, 0.6 - 0.3 * k)], 0.05, 'black')
    m += B((0, 0.55, 0.25), (0.3, 0.1, 0.35), 'gold', 14, 8)
    return m
save('wasp_body', wasp())
def wing():
    m = M()
    m += sq((0.9, 0, 0), (0.9, 0.02, 0.4), 0.8, col='glass', R=RY(0.25))
    m += S((0, 0, 0), (1.7, 0, -0.3), 0.025, 0.012, 'black')
    return m
save('wasp_wing', wing())

# ------------------------------------------------------------------ allies & air support
def container(col):
    m = M(); L, W, H = 5.6, 2.3, 2.4
    m += sq((0, H / 2, 0), (W / 2, H / 2, L / 2), 0.12, col=col, nu=28, nv=20)
    for k in range(-12, 13):
        for s in (1, -1): m += sq((s * W / 2, H / 2, k * 0.21), (0.03, H * 0.42, 0.045), 0.5, col=col)
    for z in (-L / 2, L / 2):
        for x in (-W / 2, W / 2):
            m += sq((x, H / 2, z), (0.09, H / 2 + 0.01, 0.09), 0.4, col='dkgrey')
        for y in (0.05, H - 0.05): m += sq((0, y, z), (W / 2, 0.08, 0.09), 0.4, col='dkgrey')
    for x in (-0.35, 0.35): m += S((x, 0.2, L / 2 + 0.06), (x, H - 0.2, L / 2 + 0.06), 0.03, 0.03, 'steel')
    m += sq((0, H * 0.62, L / 2 + 0.02), (0.6, 0.18, 0.02), 0.5, col='white')
    for k in range(-1, 2): m += sq((W / 2 + 0.02, H * 0.55, k * 1.6), (0.012, 0.3, 0.45), 0.6, col='white')
    return m
save('container', container('teal')); save('container_o', container('orange'))
def turret():
    b = M()
    b += sq((0, 0.25, 0), (0.6, 0.25, 0.6), 0.6, col='sandbag')
    for i in range(8):
        a = 2 * PI * i / 8; b += sq((np.cos(a) * 0.62, 0.32, np.sin(a) * 0.62), (0.18, 0.12, 0.26), 0.7, R=RY(-a), col='sandbag')
    b += S((0, 0.4, 0), (0, 0.95, 0), 0.08, 0.07, 'dkgrey')
    save('tur_base', b)
    g = M()
    g += sq((0, 0, 0), (0.3, 0.2, 0.35), 0.45, col='olive')
    g += sq((0, 0.12, 0.32), (0.45, 0.3, 0.03), 0.3, col='olive', R=RXp(-0.15))
    g += sq((0, 0.3, 0.33), (0.2, 0.04, 0.02), 0.5, col='blue')
    for x in (-0.12, 0.12):
        g += S((x, 0.0, 0.2), (x, 0.0, 1.2), 0.055, 0.05, 'gun'); g += S((x, 0, 0.9), (x, 0, 1.25), 0.07, 0.07, 'gun_l')
    g += sq((0.38, -0.05, 0), (0.12, 0.14, 0.18), 0.5, col='hazard')
    save('tur_gun', g)
turret()
def heli():
    m = M()
    m += sq((0, 0, 0.2), (0.75, 0.7, 1.35), 0.75, col='blue', nu=26, nv=18)
    m += B((0, 0.12, 1.05), (0.55, 0.45, 0.6), 'glass', 18, 12)
    m += sq((0, 0.45, -0.1), (0.45, 0.25, 0.7), 0.5, col='blue_d')
    m += S((0, 0.15, -0.9), (0, 0.4, -3.4), 0.3, 0.1, 'blue', 16)
    m += sq((0, 0.75, -3.3), (0.06, 0.55, 0.3), 0.5, col='blue_d')
    m += sq((0, 0.3, -3.3), (0.9, 0.05, 0.25), 0.5, col='blue')
    m += B((0.14, 0.75, -3.3), (0.03, 0.5, 0.06), 'black', 8, 6)
    for s in (1, -1):
        m += S((0.55 * s, -0.75, 1.0), (0.55 * s, -0.75, -0.8), 0.05, 0.05, 'dkgrey')
        for z in (0.6, -0.4): m += S((0.4 * s, -0.45, z), (0.55 * s, -0.75, z), 0.04, 0.04, 'dkgrey')
        m += sq((0.95 * s, -0.05, 0.1), (0.4, 0.05, 0.25), 0.5, col='blue_d')
        m += S((1.2 * s, -0.25, -0.3), (1.2 * s, -0.25, 0.8), 0.14, 0.14, 'olive', 12); m += B((1.2 * s, -0.25, 0.8), (0.13, 0.13, 0.05), 'black', 10, 6)
    m += S((0, 0.65, 0), (0, 0.95, 0), 0.08, 0.06, 'dkgrey')
    m += sq((0, -0.55, 1.2), (0.12, 0.12, 0.2), 0.5, col='gun'); m += S((0, -0.62, 1.3), (0, -0.62, 1.8), 0.035, 0.03, 'gun_l')
    m += sq((0, 0.0, 0.2), (0.76, 0.06, 0.6), 0.5, col='white')
    return m
save('heli', heli())
def hrotor():
    m = M()
    for k in range(4): m += sq((0, 0.97, 0), (2.6, 0.015, 0.11), 0.5, R=RY(k * PI / 4 * 2 + 0.3), col='black')
    m += B((0, 0.98, 0), (0.15, 0.06, 0.15), 'dkgrey', 12, 6)
    return m
save('heli_rotor', hrotor())
def jet():
    m = M()
    m += S((0, 0, -3.2), (0, 0, 3.6), 0.4, 0.15, 'white', 20)
    m += B((0, 0, 3.6), (0.15, 0.15, 0.6), 'white', 12, 8)
    m += B((0, 0.28, 1.8), (0.25, 0.25, 0.85), 'glass', 14, 10)
    m += slab([(0.3, 0.8), (3.2, -1.2), (3.2, -1.8), (0.3, -1.4)], -0.06, 0.06, 0.2) and C(xform(slab([(0.3, 0.8), (3.2, -1.2), (3.2, -1.8), (0.3, -1.4)], -0.06, 0.06, 0.2), R=rotm(rx=PI / 2)), 'blue')
    m += C(xform(slab([(-0.3, 0.8), (-0.3, -1.4), (-3.2, -1.8), (-3.2, -1.2)], -0.06, 0.06, 0.2), R=rotm(rx=PI / 2)), 'blue')
    m += C(xform(slab([(0.05, -2.2), (1.4, -3.4), (1.4, -3.8), (0.05, -3.4)], -0.05, 0.05, 0.2), R=rotm(rx=PI / 2)), 'blue_d')
    m += C(xform(slab([(-0.05, -2.2), (-0.05, -3.4), (-1.4, -3.8), (-1.4, -3.4)], -0.05, 0.05, 0.2), R=rotm(rx=PI / 2)), 'blue_d')
    m += C(xform(slab([(0, 0.0), (1.4, 0.0), (1.7, -1.0), (0, -1.0)], -0.05, 0.05, 0.2), c=(0, 0.2, -2.2), R=rotm(ry=-PI / 2) @ rotm(rx=0)), 'blue')
    m += B((0, 0, -3.25), (0.3, 0.3, 0.05), 'lava_g', 12, 6)
    for s in (1, -1): m += S((1.6 * s, -0.25, -1.2), (1.6 * s, -0.25, 0.4), 0.1, 0.1, 'dkgrey')
    return m
save('jet', jet())
save('bomb', U(B((0, 0, 0), (0.22, 0.22, 0.6), 'dkgrey', 14, 10), T(0.22, 0.03, 'yellow', (0, 0, 0.2), ZT),
               *[sq((0, 0, -0.6), (0.3, 0.015, 0.15), 0.5, R=rotm(rz=k * PI / 2), col='dkgrey') for k in range(2)]))
save('rocket', U(S((0, 0, -0.3), (0, 0, 0.25), 0.06, 0.06, 'white', 12), cone((0, 0, 0.25), (0, 0, 0.42), 0.06, 'red'),
                 *[sq((0, 0, -0.25), (0.13, 0.01, 0.06), 0.5, R=rotm(rz=k * PI / 2), col='hazard') for k in range(2)]))

# ------------------------------------------------------------------ gates & lane props
def gate_frame(W=4.7, H=3.1):
    m = M(); hx = W / 2
    for s in (1, -1):
        x = hx * s
        m += sq((x, 0.2, 0), (0.32, 0.2, 0.32), 0.4, col='dkgrey')
        m += sq((x, H / 2 + 0.2, 0), (0.17, H / 2, 0.17), 0.45, col='white', nu=16, nv=12)
        for y in (0.9, 1.7, 2.5): m += T(0.19, 0.03, 'steel', (x, y, 0), rotm(rx=PI / 2), 18, 6)
        m += B((x, H + 0.45, 0), 0.2, 'white_g', 14, 10)
    m += sq((0, H + 0.25, 0), (hx, 0.12, 0.13), 0.4, col='white', nu=24, nv=10)
    m += sq((0, H + 0.25, 0.12), (hx - 0.3, 0.05, 0.02), 0.5, col='blue_g')
    return m
save('gate_frame', gate_frame())
def panel():
    # z-fight fix: the panel edges used to end exactly on the post inner faces (x 2.18) and 6 cm under the top bar;
    # now it is tucked 8 cm into each post and 5 cm up into the bar, so no two surfaces meet in the same plane
    m = sq((0, 1.80, 0), (2.26, 1.47, 0.07), 0.22, nu=24, nv=16)
    m.UV = [((v[0] + 2.26) / 4.52, (v[1] - 0.33) / 2.94) for v in m.V]   # planar: gate_grad spans the panel
    return m
for c in ('blue', 'red', 'gold', 'grey', 'orange', 'green'): save('gpanel_' + c, panel())
def crate():
    m = M()
    m += sq((0, 0.5, 0), (0.6, 0.5, 0.6), 0.25, col='olive')
    for s in (-1, 1):
        m += sq((0, 0.5, s * 0.6), (0.62, 0.08, 0.03), 0.4, col='steel')
        m += sq((s * 0.6, 0.5, 0), (0.03, 0.08, 0.62), 0.4, col='steel')
    m += sq((0, 1.0, 0), (0.35, 0.03, 0.35), 0.4, col='yellow')
    m += sq((0, 0.5, 0.62), (0.2, 0.2, 0.01), 0.3, col='white')
    return m
save('crate', crate())
def barrel(c, band):
    m = M()
    m += C(tube((0, 0, 0), 0.42, 0.42, 1.2, 22), c)
    for y in (0.1, 0.6, 1.1): m += T(0.43, 0.035, band, (0, y, 0), rotm(rx=PI / 2), 24, 6)
    m += C(tube((0, 1.2, 0), 0.38, 0.3, 0.04, 22), 'dkgrey')
    m += S((0.18, 1.2, 0.1), (0.18, 1.28, 0.1), 0.06, 0.06, 'steel')
    return m
save('barrel_red', barrel('red', 'yellow')); save('barrel_blue', barrel('blue', 'white'))
def barricade():
    m = M()
    for i, y in enumerate((0.35, 0.85, 1.35)):
        m += C(seg((-2.2, y, 0), (2.2, y, 0), 0.22, 0.22, 16), 'trunk')
    for s in (-2.0, 0, 2.0): m += S((s, 0, -0.1), (s, 1.8, -0.1), 0.12, 0.1, 'trunk')
    for i in range(9):
        x = -2.0 + i * 0.5
        for y in (0.6, 1.1): m += cone((x, y, 0.1), (x, y + 0.2, 0.75), 0.06, 'steel', 8)
    for i in range(6): m += sq((-1.9 + i * 0.76, 0.18, 0.35), (0.38, 0.18, 0.22), 0.6, col='sandbag')
    m += sq((0, 1.8, 0), (0.6, 0.18, 0.04), 0.4, col='hazard')
    return m
save('barricade', barricade())
save('mflash', U(B((0, 0, 0), (0.07, 0.07, 0.07), 'mflash', 10, 8), cone((0, 0, 0), (0, 0, 0.42), 0.09, 'mflash', 10),
                  cone((0, 0, 0), (0.2, 0, 0.12), 0.05, 'mflash', 8), cone((0, 0, 0), (-0.2, 0, 0.12), 0.05, 'mflash', 8),
                  cone((0, 0, 0), (0, 0.2, 0.12), 0.05, 'mflash', 8), cone((0, 0, 0), (0, -0.2, 0.12), 0.05, 'mflash', 8)))
save('tracer', U(B((0, 0, 0), (0.05, 0.05, 0.55), 'white_g', 10, 6)))
save('pellet', B((0, 0, 0), (0.05, 0.05, 0.22), 'white_g', 8, 6))
save('orb', B((0, 0, 0), 0.5, 'lava_g', 16, 10))
save('ring', T(1.0, 0.06, 'red_g', (0, 0, 0), rotm(rx=PI / 2), 40, 6))
save('coin', U(C(tube((0, -0.04, 0), 0.25, 0.25, 0.08, 20), 'gold'), T(0.25, 0.03, 'gold', (0, 0, 0), rotm(rx=PI / 2), 20, 6)))
save('aimdash', sq((0, 0, 0), (0.045, 0.006, 0.34), 0.3, col='white_g'))   # faint fire-strip guide dash on the deck
save('beam', sq((0, 0, 0.5), (0.06, 0.06, 0.5), 0.5, col='cyan_g'))   # laser beam, scaled along z
save('blob', C(tube((0, 0, 0), 1.0, 1.0, 0.01, 24), 'black'))

# ------------------------------------------------------------------ bridge (one long wrap-scrolled strip, 30 x 20 m bays)
NB, BL, HW = 2, 20.0, 5.5
def deck():
    m = M(); L = 64 * BL; z0 = -40.0
    V = [(-HW, 0, z0), (HW, 0, z0), (HW, 0, z0 + L), (-HW, 0, z0 + L)]
    m.add([np.array(v) for v in V], [np.array((0, 1.0, 0))] * 4, [(0, 0), (1, 0), (1, L / 10), (0, L / 10)], [(0, 2, 1), (0, 3, 2)])
    return m
save('deck', deck())
def bridge(theme):
    m = M(); z0 = 0.0
    rail = {'harbor': 'red', 'canyon': 'rust', 'forest': 'olive', 'frost': 'blue', 'volcano': 'dkgrey'}[theme]
    for b in range(NB):
        z = z0 + b * BL
        for s in (1, -1):
            cg = 0.006 * (b % 2)   # curbs overlap the next bay by 2 cm: alternate bays are 6 mm fatter so the overlap never shares a plane
            m += sq((s * (HW + 0.25), 0.15, z + BL / 2), (0.35 + cg, 0.3 + cg, BL / 2 + 0.02), 0.25, col='concrete', nu=12, nv=8)
            for k in range(5): m += S((s * (HW + 0.3), 0.4, z + k * 4), (s * (HW + 0.3), 1.25, z + k * 4), 0.06, 0.05, 'steel', 8)
            m += C(seg((s * (HW + 0.3), 1.25, z), (s * (HW + 0.3), 1.25, z + BL), 0.07, 0.07, 10), rail)
            m += C(seg((s * (HW + 0.3), 0.85, z), (s * (HW + 0.3), 0.85, z + BL), 0.045, 0.045, 8), rail)
            m += S((s * (HW + 0.3), 0.4, z), (s * (HW + 0.3), 3.6, z), 0.08, 0.06, 'dkgrey', 10)
            m += S((s * (HW + 0.3), 3.6, z), (s * (HW - 0.4), 3.75, z), 0.05, 0.05, 'dkgrey', 8)
            m += sq((s * (HW - 0.45), 3.68, z), (0.22, 0.06, 0.12), 0.5, col='dkgrey'); m += sq((s * (HW - 0.45), 3.62, z), (0.16, 0.025, 0.08), 0.5, col='white_g')
        m += sq((0, -0.49, z + BL / 2), (HW + 0.4, 0.45, BL / 2), 0.2, col='concrete', nu=12, nv=8)   # top at y -0.04: was coplanar with the deck (y 0)
        for s in (1, -1): m += sq((s * 3.0, -1.2, z + BL / 2), (0.35, 0.5, BL / 2), 0.3, col='steel' if theme != 'forest' else 'concrete', nu=10, nv=8)
        if b % 2 == 0:
            for s in (1, -1):
                m += C(tube((s * 3.2, -40, z + BL / 2), 1.0, 0.85, 39.2, 18, caps=False), 'concrete')
            m += sq((0, -1.6, z + BL / 2), (HW + 0.2, 0.5, 1.3), 0.3, col='concrete')
    return m
for th in ('harbor', 'canyon', 'forest', 'frost', 'volcano'): save('bridge_' + th, bridge(th))
def plane(n=1.0, tile=1.0):
    m = M(); h = n / 2
    m.add([np.array(v) for v in [(-h, 0, -h), (h, 0, -h), (h, 0, h), (-h, 0, h)]], [np.array((0, 1.0, 0))] * 4,
          [(0, 0), (tile, 0), (tile, tile), (0, tile)], [(0, 2, 1), (0, 3, 2)]); return m
save('sea', plane(2400, 2400 / 12.0))     # wrap-scrolled by 12 m (texture period)
save('floor', plane(2400, 2400 / 16.0))

# ------------------------------------------------------------------ scenery
def noise_rock(c, r, col, k=0.22, seed=0, nu=14, nv=10):
    m = ellipsoid((0, 0, 0), r, nu, nv); rg = np.random.default_rng(seed)
    V = np.array(m.V); ph = rg.random(3) * 6
    f = 1 + k * (np.sin(V[:, 0] * 3.1 / r[0] + ph[0]) * np.sin(V[:, 1] * 2.7 / r[1] + ph[1]) + 0.5 * np.sin(V[:, 2] * 4.3 / r[2] + ph[2]))
    m.V = list(V * f[:, None] + np.array(c)); return C(m, col)
def pine(col='pine', snow=False, h=7.0):
    m = M(); m += S((0, 0, 0), (0, h * 0.4, 0), h * 0.06, h * 0.04, 'trunk')
    for i in range(4):
        y = h * (0.22 + i * 0.18); r = h * (0.36 - i * 0.075)
        m += C(seg((0, y, 0), (0, y + h * 0.32, 0), r, 0.02, 16), col)
        if snow: m += C(seg((0, y + h * 0.14, 0), (0, y + h * 0.32, 0), r * 0.58, 0.02, 16), 'snow')
    return m
def round_tree(col='leaf', h=6.0, seed=1):
    m = M(); m += S((0, 0, 0), (0, h * 0.55, 0), h * 0.06, h * 0.04, 'trunk'); rg = np.random.default_rng(seed)
    for i in range(5):
        a = rg.random() * 6.28; rr = h * 0.18 if i else 0
        m += B((np.cos(a) * rr, h * (0.62 + 0.1 * rg.random()), np.sin(a) * rr), h * (0.3 - 0.03 * (i > 0)), col, 14, 10)
    return m
def palm(h=7.0):
    m = M(); pts = [(0.25 * np.sin(t * 1.5) * h * 0.1, t * h, 0) for t in np.linspace(0, 1, 6)]
    for a, b in zip(pts[:-1], pts[1:]): m += S(a, b, h * 0.05, h * 0.045, 'trunk', 10)
    top = np.array(pts[-1])
    for i in range(7):
        a = 2 * PI * i / 7; d = np.array([np.cos(a), 0, np.sin(a)])
        p1 = top + d * h * 0.3 + np.array([0, h * 0.06, 0]); p2 = top + d * h * 0.55 - np.array([0, h * 0.18, 0])
        m += C(seg(top, p1, h * 0.07, h * 0.06, 6), 'palm'); m += C(seg(p1, p2, h * 0.06, 0.02, 6), 'palm')
    m += B(tuple(top), h * 0.07, 'trunk', 10, 6)
    return m
save('pine', pine()); save('pine_snow', pine('pine', True)); save('tree', round_tree()); save('tree_autumn', round_tree('autumn', 6, 3))
save('tree_autumn2', round_tree('autumn2', 5, 5)); save('palm', palm())
save('rock', U(noise_rock((0, 0.3, 0), (2.0, 1.4, 1.7), 'rock', 0.2, 5, 20, 12), noise_rock((1.6, 0.0, 0.8), (1.0, 0.8, 0.9), 'sand', 0.2, 6, 16, 10)))
save('rock_lava', U(noise_rock((0, 0.3, 0), (2.0, 1.6, 1.7), 'lavarock', seed=3), C(xform(ellipsoid((0, 0, 0), (0.3, 0.6, 0.3), 8, 6), (1.2, 1.0, 1.0)), 'lava_g')))
save('island', U(noise_rock((0, -1.0, 0), (14, 3.5, 11), 'sand', 0.12, 4, 24, 12), noise_rock((2, 1.0, 1), (6, 3.5, 5), 'rock', 0.2, 5),
                 *[xform(palm(6 + 2 * rng.random()), (np.cos(a) * 7, 1.5, np.sin(a) * 5)) for a in (0.3, 1.9, 3.6, 5.0)]))
save('iceberg', U(noise_rock((0, 0, 0), (9, 6, 7), 'ice', 0.25, 6, 18, 12), noise_rock((3, 4, 1), (4, 5, 3), 'snow', 0.2, 7)))
def butte(rx, rz, h, seed, nu=40):
    # smooth, organic butte: flared base, steep layered walls, rounded flat top (lathe with noise)
    rg = np.random.default_rng(seed); ph = rg.random(4) * 6.28
    prof = [(0.0, 1.32), (0.08, 1.18), (0.2, 1.05), (0.35, 1.0), (0.5, 0.97), (0.62, 0.99), (0.75, 0.95), (0.88, 0.93), (0.96, 0.88), (1.0, 0.7), (1.015, 0.0)]
    V, UVs, F = [], [], []
    for j, (t, k) in enumerate(prof):
        for i in range(nu):
            a = 2 * PI * i / nu
            w = 1 + 0.07 * np.sin(3 * a + ph[0]) + 0.04 * np.sin(7 * a + ph[1]) + 0.025 * np.sin(13 * a + ph[2] + t * 9) + (0.035 if (j in (3, 6)) else 0)
            V.append((np.cos(a) * rx * k * w, t * h, np.sin(a) * rz * k * w))
    nr = len(prof)
    for j in range(nr - 1):
        for i in range(nu):
            a0 = j * nu + i; a1 = j * nu + (i + 1) % nu; b0 = a0 + nu; b1 = a1 + nu
            F += [(a0, b0, a1), (a1, b0, b1)]
    V = np.array(V)
    # smooth vertex normals from faces
    N = np.zeros_like(V)
    for a, b, c in F:
        n = np.cross(V[b] - V[a], V[c] - V[a]); N[a] += n; N[b] += n; N[c] += n
    N /= np.linalg.norm(N, axis=1)[:, None] + 1e-9
    m = M(); m.add([tuple(v) for v in V], [tuple(n) for n in N], [(0, 0)] * len(V), F)
    return m
def butte_mesh():
    body = C(butte(14, 11, 20, 11), 'mesa')
    cap = noise_rock((0, 20.0, 0), (9.6, 0.9, 7.5), 'sand', 0.06, 12, 30, 8)
    band = C(butte(14.6, 11.6, 3.2, 14), 'sand')
    return U(body, cap, band, noise_rock((12, 1.5, 7), (5, 3.5, 4.5), 'rock', 0.2, 8, 20, 12))
save('mesa', butte_mesh())
save('buoy', U(C(tube((0, -0.5, 0), 0.6, 0.45, 1.4, 16), 'red'), T(0.5, 0.06, 'white', (0, 0.4, 0), rotm(rx=PI / 2)), S((0, 0.9, 0), (0, 2.2, 0), 0.05, 0.05, 'dkgrey'), B((0, 2.25, 0), 0.14, 'white_g')))
def boat():
    m = M(); m += sq((0, 0.4, 0), (1.6, 0.7, 4.5), 0.55, col='white', nu=24, nv=12); m += sq((0, 0.95, 0), (1.62, 0.12, 4.52), 0.4, col='red')
    m += sq((0, 1.7, -0.8), (1.1, 0.8, 1.6), 0.35, col='white'); m += sq((0, 1.95, 0.75), (1.0, 0.25, 0.08), 0.4, col='glass')
    m += S((0, 2.4, -1.2), (0, 4.2, -1.2), 0.06, 0.05, 'steel'); return m
save('boat', boat())
def mountain(cols, seed, H=160, R=240, snow=None):
    m = ellipsoid((0, 0, 0), (R, H, R * 0.8), 48, 24); V = np.array(m.V); rg = np.random.default_rng(seed); ph = rg.random(6) * 6
    th = np.arctan2(V[:, 2], V[:, 0]); y = V[:, 1] / H
    f = 1 + 0.18 * np.sin(th * 5 + ph[0]) + 0.1 * np.sin(th * 11 + ph[1]) + 0.06 * np.sin(th * 23 + ph[2])
    V[:, 1] = np.where(V[:, 1] > 0, V[:, 1] * (0.75 + 0.45 * (np.sin(th * 3 + ph[3]) * 0.5 + 0.5)) ** 1.0, V[:, 1])
    V[:, 0] *= f; V[:, 2] *= f; m.V = list(V)
    u0, u1 = uv(cols[0]), uv(cols[1]); us = uv(snow) if snow else None
    m.UV = [(us if (snow and v[1] > H * 0.62) else (u1 if v[1] > H * 0.3 else u0)) for v in V]
    return m
save('mtn_green', mountain(('leaf', 'rock'), 1, snow='snow')); save('mtn_desert', mountain(('mesa', 'sand'), 2, 120))
save('mtn_snow', mountain(('snow', 'ice'), 3, 190, snow='snow')); save('mtn_volcano', mountain(('lavarock', 'lavarock'), 4, 180, snow='lava_g'))
save('mtn_autumn', mountain(('autumn', 'rock'), 5, 140, snow='autumn2'))
