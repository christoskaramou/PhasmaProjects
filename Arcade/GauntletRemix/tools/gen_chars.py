# Detailed rigged heroes and monsters for Gauntlet Remix -> meshsrc/ch_<kind>_<seg>_<mat>.obj + src/02b_rigs.lua
# Each character = segments (body, legs, arms, wings...) with a pivot; each segment holds one mesh per material.
# Lua builds a node per segment (child of the character root) and animates the joints (walk, attack, flap, float).
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from meshlib import *
from charlib import *
H = os.path.dirname(os.path.abspath(__file__))
CH = {}
class Char:
    def __init__(s, name): s.name, s.piv, s.parts, s.order = name, {}, {}, []; CH[name] = s
    def seg(s, seg, pivot): s.piv[seg] = np.array(pivot, float); s.order.append(seg); return s
    def add(s, seg, mat, *ms):
        k = (seg, mat)
        if k not in s.parts: s.parts[k] = M()
        for m in ms: s.parts[k] += m
        return s
# ---------------------------------------------------------------- materials {base, emissive, rough, metal}
MATS = {
    'skin': ((.86, .62, .48), (.02, .01, .0), .55, 0), 'skin_dk': ((.66, .44, .32), (0, 0, 0), .6, 0),
    'steel': ((.78, .79, .84), (.05, .05, .06), .3, .3), 'steel_dk': ((.42, .43, .47), (.01, .01, .01), .38, .3),
    'gold': ((1.0, .78, .34), (.12, .08, .02), .3, .45), 'bronze': ((.78, .52, .3), (.04, .02, 0), .35, .35),
    'leather': ((.42, .26, .14), (0, 0, 0), .7, 0), 'leather_dk': ((.24, .15, .09), (0, 0, 0), .75, 0),
    'fur': ((.55, .4, .26), (0, 0, 0), .95, 0), 'wood': ((.5, .33, .18), (0, 0, 0), .75, 0), 'ivory': ((.93, .9, .8), (.03, .03, .02), .5, 0),
    'war_red': ((.72, .12, .08), (.03, 0, 0), .65, 0), 'war_hair': ((.55, .22, .08), (0, 0, 0), .8, 0),
    'val_blue': ((.16, .3, .82), (0, .01, .04), .55, 0), 'val_armor': ((.68, .76, .95), (.03, .04, .07), .3, .3),
    'val_hair': ((1.0, .82, .38), (.05, .04, .01), .6, 0), 'white': ((.92, .92, .9), (.03, .03, .03), .6, 0),
    'wiz_robe': ((.9, .72, .16), (.04, .03, 0), .7, 0), 'wiz_trim': ((.6, .2, .1), (0, 0, 0), .6, 0), 'beard': ((.93, .93, .93), (.05, .05, .05), .8, 0),
    'orb': ((.6, .8, 1.0), (1.2, 1.6, 2.4), .2, 0),
    'elf_green': ((.2, .58, .22), (0, .015, 0), .65, 0), 'elf_dkgreen': ((.1, .32, .14), (0, 0, 0), .7, 0), 'elf_hair': ((.85, .6, .25), (.02, .01, 0), .7, 0),
    'feather': ((.85, .15, .1), (.04, 0, 0), .6, 0),
    'ghost': ((.78, .8, .88), (.10, .11, .14), .6, 0), 'void': ((.02, .02, .03), (0, 0, 0), .9, 0),
    'grunt_skin': ((.45, .52, .3), (0, 0, 0), .7, 0), 'grunt_cloth': ((.45, .3, .18), (0, 0, 0), .85, 0),
    'demon_skin': ((.62, .18, .12), (.03, 0, 0), .55, 0), 'demon_wing': ((.3, .1, .09), (.01, 0, 0), .7, 0), 'horn': ((.3, .26, .22), (0, 0, 0), .45, .1),
    'claw': ((.9, .86, .74), (0, 0, 0), .4, 0),
    'lob_skin': ((.66, .56, .36), (0, 0, 0), .7, 0), 'sack': ((.58, .48, .32), (0, 0, 0), .95, 0), 'rock': ((.5, .48, .45), (0, 0, 0), .9, 0),
    'sorc_robe': ((.42, .14, .5), (.02, 0, .03), .65, 0), 'sorc_dk': ((.16, .05, .2), (0, 0, 0), .8, 0),
    'death_robe': ((.07, .07, .09), (0, 0, 0), .85, 0), 'bone': ((.86, .84, .74), (.04, .04, .03), .55, 0),
    'eye_red': ((1, .3, .2), (2.2, .5, .25), .5, 0), 'eye_yel': ((1, .9, .3), (2.0, 1.6, .3), .5, 0), 'eye_green': ((.5, 1, .4), (.8, 2.0, .5), .5, 0),
    'magic': ((.9, .5, 1.0), (1.6, .7, 2.2), .3, 0),
}
# ---------------------------------------------------------------- shared humanoid parts (hero height ~0.86 before the 1.25 game scale)
HIP, SH_Y, HEAD_Y = 0.30, 0.555, 0.69
def leg_geo(x, thick=1.0):
    th = sweep([(x, HIP + 0.02, 0), (x * 1.02, 0.17, 0.012), (x, 0.06, -0.004)], [0.056 * thick, 0.046 * thick, 0.038 * thick], 12)
    return th
def boot_geo(x, h=0.10, cuff=0.0):
    b = U(boxr((x, 0.03, 0.022), (0.082, 0.062, 0.14), 0.35), cyl((x, 0.04, -0.002), 0.045, h, 12, 0.047))
    if cuff: b += lathe([(h + 0.0, 0.05), (h + 0.02, 0.06 * cuff + 0.02), (h + 0.05, 0.058 * cuff + 0.02), (h + 0.06, 0.048)], 12, (x, 0.0, -0.002))
    return b
def arm_geo(s, thick=1.0, bare=True):
    x = 0.205 * s
    return sweep([(x, SH_Y, 0), (x + 0.025 * s, 0.43, -0.01), (x + 0.03 * s, 0.32, 0.045)], [0.047 * thick, 0.039 * thick, 0.033 * thick], 12)
def hand_geo(s, z=0.065, y=0.295):
    x = 0.237 * s
    return U(ell((x, y, z), (0.036, 0.04, 0.036), 12, 8), ell((x - 0.025 * s, y + 0.012, z + 0.01), (0.014, 0.022, 0.014), 8, 6))
HAND = lambda s: np.array([0.237 * s, 0.295, 0.065])
def torso_geo(prof, sz=0.68, n=24, zoff=None): return lathe(prof, n, (0, 0, 0), 1.0, sz, zoff=zoff)
def head_geo(r=1.0, y=HEAD_Y):
    h = ell((0, y, 0.005), (0.083 * r, 0.094 * r, 0.088 * r), 20, 12)
    nose = ell((0, y - 0.005, 0.088 * r), (0.016, 0.022, 0.02), 8, 6)
    ears = U(ell((0.08 * r, y, 0), (0.014, 0.026, 0.02), 8, 6), ell((-0.08 * r, y, 0), (0.014, 0.026, 0.02), 8, 6))
    neck = cyl((0, 0.57, 0), 0.045, 0.06, 12)
    return U(h, nose, ears, neck)
def eyes_geo(y=HEAD_Y + 0.012, z=0.078, dx=0.032, r=0.012):
    return U(ell((dx, y, z), (r, r * 0.8, r * 0.6), 8, 6), ell((-dx, y, z), (r, r * 0.8, r * 0.6), 8, 6))
def belt_geo(y=0.335, r=0.152, sz=0.7, h=0.04): return lathe([(y, r), (y + h * 0.15, r + 0.012), (y + h * 0.85, r + 0.012), (y + h, r)], 24, (0, 0, 0), 1.0, sz)
def hero_frame(c):
    c.seg('body', (0, 0, 0)).seg('leg_l', (0.085, HIP, 0)).seg('leg_r', (-0.085, HIP, 0)).seg('arm_l', (0.205, SH_Y, 0)).seg('arm_r', (-0.205, SH_Y, 0))
def shell(prof, a0, a1, thick=0.015, sz=0.7, n=12, wob=None):
    """open curved sheet (capes, hoods, wings of cloth) as a thin closed solid: arc a0..a1 around Y, for each (y, r)."""
    rings = []
    for y, r in prof:
        outer = [np.array([np.cos(a) * r, y, np.sin(a) * r * sz]) * 1 for a in np.linspace(a0, a1, n)]
        if wob: outer = [p + np.array([0, 0, 0]) * 0 + (p - np.array([0, y, 0])) * (wob(y, a) - 1) for p, a in zip(outer, np.linspace(a0, a1, n))]
        inner = [np.array([p[0], y, p[2]]) * 1 for p in outer]
        inner = [np.array([0, y, 0]) + (q - np.array([0, y, 0])) * (1 - thick / max(r, 1e-3)) for q in inner]
        rings.append(outer + inner[::-1])
    return grid(rings, True, True, True)
BACK = (PI * 1.12, PI * 1.88)          # angles that wrap the back (-Z)
def kilt_geo(y0, y1, r0, r1, pleats=10, amp=0.08, sz=0.72):
    return lathe([(y1, r1), (y0 + (y1 - y0) * 0.5, (r0 + r1) / 2 + 0.005), (y0, r0)][::-1], 30, (0, 0, 0), 1.0, sz,
                 wob=lambda y, a: 1 + amp * np.cos(a * pleats) * (y1 - y) / (y1 - y0), cap0=False, cap1=False)
# ================================================================ WARRIOR (Thor): bare-chested barbarian, horned helm, red kilt, battle axe
c = Char('war'); hero_frame(c)
c.add('body', 'skin', torso_geo([(0.3, 0.13), (0.36, 0.145), (0.42, 0.15), (0.48, 0.175), (0.535, 0.19), (0.565, 0.16), (0.6, 0.07)], 0.66),
      ell((0.06, 0.49, 0.085), (0.07, 0.05, 0.035), 12, 8), ell((-0.06, 0.49, 0.085), (0.07, 0.05, 0.035), 12, 8),   # pecs
      *[ell((sx * 0.032, y, 0.088), (0.03, 0.022, 0.018), 8, 6) for sx in (1, -1) for y in (0.43, 0.395)],            # abs
      head_geo(1.05))
c.add('body', 'void', eyes_geo(r=0.011))
c.add('body', 'leather', sweep([(0.15, 0.56, 0.08), (0.0, 0.47, 0.115), (-0.13, 0.36, 0.09)], 0.016, 8, 0.4),
      sweep([(0.15, 0.56, -0.08), (0.0, 0.47, -0.115), (-0.13, 0.36, -0.09)], 0.016, 8, 0.4), belt_geo(0.325, 0.152, 0.7, 0.05))
c.add('body', 'gold', ell((0, 0.35, 0.115), (0.04, 0.032, 0.014), 10, 6), ell((0.13, 0.56, 0.08), (0.02, 0.02, 0.01), 8, 6))
c.add('body', 'war_red', kilt_geo(0.19, 0.33, 0.175, 0.155, 9, 0.07), shell([(0.58, 0.16), (0.45, 0.19), (0.3, 0.22), (0.16, 0.25)], *BACK, 0.014, 0.75, 14))
c.add('body', 'fur', shell([(0.62, 0.09), (0.6, 0.15), (0.56, 0.19), (0.53, 0.19)], PI * 1.05, PI * 1.95, 0.03, 0.8, 14, wob=lambda y, a: 1 + 0.07 * np.sin(a * 13)))
c.add('body', 'steel', lathe([(HEAD_Y + 0.02, 0.098), (HEAD_Y + 0.055, 0.097), (HEAD_Y + 0.09, 0.08), (HEAD_Y + 0.115, 0.045), (HEAD_Y + 0.125, 0.0)], 20, (0, 0, 0.0), 1.0, 1.0),
      boxr((0, HEAD_Y - 0.005, 0.1), (0.018, 0.07, 0.016), 0.4))   # helm dome + nose guard
c.add('body', 'gold', lathe([(HEAD_Y + 0.015, 0.1), (HEAD_Y + 0.03, 0.104), (HEAD_Y + 0.045, 0.1)], 20, (0, 0, 0), cap0=False, cap1=False),
      ball((0, HEAD_Y + 0.128, 0), 0.016, 8, 6))
c.add('body', 'ivory', horn((0.085, HEAD_Y + 0.06, 0), (1, 0.25, 0.15), 0.17, 0.028, 0.9), horn((-0.085, HEAD_Y + 0.06, 0), (-1, 0.25, 0.15), 0.17, 0.028, 0.9))
c.add('body', 'war_hair', ell((0, HEAD_Y - 0.06, 0.06), (0.07, 0.06, 0.045), 12, 8),
      sweep([(0.03, HEAD_Y - 0.03, 0.085), (0.0, HEAD_Y - 0.035, 0.095), (-0.03, HEAD_Y - 0.03, 0.085)], 0.012, 6),
      sweep([(0.06, HEAD_Y, -0.06), (0.07, 0.6, -0.08), (0.07, 0.52, -0.09)], [0.022, 0.018, 0.012], 8),
      sweep([(-0.06, HEAD_Y, -0.06), (-0.07, 0.6, -0.08), (-0.07, 0.52, -0.09)], [0.022, 0.018, 0.012], 8))
for s, seg in ((1, 'leg_l'), (-1, 'leg_r')):
    x = 0.085 * s
    c.add(seg, 'leather_dk', leg_geo(x, 1.1)); c.add(seg, 'leather', boot_geo(x, 0.1)); c.add(seg, 'fur', lathe([(0.09, 0.05), (0.11, 0.066), (0.15, 0.062), (0.165, 0.048)], 14, (x, 0, 0), wob=lambda y, a: 1 + 0.08 * np.sin(a * 9)))
for s, seg in ((1, 'arm_l'), (-1, 'arm_r')):
    c.add(seg, 'skin', arm_geo(s, 1.2), hand_geo(s), ell((0.2 * s, 0.505, 0), (0.06, 0.055, 0.055), 12, 8))   # deltoid
    c.add(seg, 'leather', cyl((0.235 * s, 0.315, 0.04), 0.04, 0.08, 12, 0.044, R=rotm(rx=-0.35)))
    c.add(seg, 'war_red', lathe([(0.0, 0.043), (0.018, 0.045)], 12, (0.232 * s, 0.39, 0.02), cap0=False, cap1=False))
c.add('arm_l', 'steel', ell((0.215, 0.565, 0), (0.075, 0.05, 0.075), 14, 8), lathe([(0.52, 0.07), (0.54, 0.074)], 14, (0.215, 0, 0), cap0=False, cap1=False))
c.add('arm_l', 'gold', ball((0.215, 0.615, 0), 0.014, 8, 6))
# battle axe in the right fist: haft through the hand, double bit at the top
hx, hy, hz = HAND(-1)
c.add('arm_r', 'wood', cyl((hx, hy - 0.16, hz), 0.016, 0.52, 10, 0.015))
c.add('arm_r', 'leather', cyl((hx, hy - 0.04, hz), 0.02, 0.08, 10))
blade = [(0.0, 0.05), (0.06, 0.07), (0.13, 0.115), (0.15, 0.04), (0.155, -0.04), (0.13, -0.115), (0.06, -0.07), (0.0, -0.05)]
c.add('arm_r', 'steel', plate(blade, 0.022, (hx, hy + 0.3, hz), rotm(ry=PI / 2)), plate([(-p[0], p[1]) for p in blade][::-1], 0.022, (hx, hy + 0.3, hz), rotm(ry=PI / 2)),
      cone((hx, hy + 0.36, hz), 0.02, 0.07, 8))
c.add('arm_r', 'gold', cyl((hx, hy + 0.26, hz), 0.024, 0.08, 10))
# ================================================================ VALKYRIE (Thyra): winged helm, blonde braids, breastplate, blue skirt, sword + round shield
c = Char('val'); hero_frame(c)
c.add('body', 'val_blue', torso_geo([(0.29, 0.12), (0.34, 0.125), (0.4, 0.12), (0.47, 0.145), (0.53, 0.16), (0.565, 0.135), (0.6, 0.06)], 0.66),
      kilt_geo(0.17, 0.33, 0.17, 0.13, 12, 0.06))
c.add('body', 'val_armor', lathe([(0.36, 0.128), (0.42, 0.13), (0.47, 0.155), (0.52, 0.168), (0.555, 0.15)], 22, (0, 0, 0.004), 1.0, 0.7, cap0=False, cap1=False),
      ell((0.05, 0.485, 0.09), (0.055, 0.045, 0.035), 12, 8), ell((-0.05, 0.485, 0.09), (0.055, 0.045, 0.035), 12, 8))
c.add('body', 'gold', belt_geo(0.335, 0.132, 0.7, 0.032), ell((0, 0.35, 0.098), (0.03, 0.026, 0.012), 10, 6),
      lathe([(0.555, 0.15), (0.565, 0.152)], 22, (0, 0, 0.004), 1.0, 0.7, cap0=False, cap1=False))
c.add('body', 'skin', head_geo(0.98))
c.add('body', 'void', eyes_geo(r=0.012))
c.add('body', 'val_hair', ell((0, HEAD_Y + 0.03, -0.012), (0.09, 0.08, 0.092), 16, 10),
      sweep([(0.065, HEAD_Y - 0.02, -0.04), (0.08, 0.6, -0.04), (0.075, 0.5, -0.02), (0.07, 0.42, 0.0)], [0.026, 0.024, 0.02, 0.012], 10),
      sweep([(-0.065, HEAD_Y - 0.02, -0.04), (-0.08, 0.6, -0.04), (-0.075, 0.5, -0.02), (-0.07, 0.42, 0.0)], [0.026, 0.024, 0.02, 0.012], 10))
c.add('body', 'steel', lathe([(HEAD_Y + 0.035, 0.095), (HEAD_Y + 0.07, 0.09), (HEAD_Y + 0.1, 0.065), (HEAD_Y + 0.118, 0.025), (HEAD_Y + 0.122, 0.0)], 20),
      boxr((0, HEAD_Y + 0.02, 0.095), (0.016, 0.06, 0.014), 0.4))
c.add('body', 'gold', lathe([(HEAD_Y + 0.03, 0.097), (HEAD_Y + 0.045, 0.1), (HEAD_Y + 0.058, 0.096)], 20, cap0=False, cap1=False))
wing = [(0.0, 0.0), (0.05, 0.03), (0.1, 0.075), (0.14, 0.13), (0.12, 0.09), (0.11, 0.06), (0.08, 0.035), (0.09, 0.02), (0.05, -0.01)]
c.add('body', 'white', plate(wing, 0.012, (0.09, HEAD_Y + 0.07, -0.01), rotm(ry=-0.5)), plate([(-p[0], p[1]) for p in wing][::-1], 0.012, (-0.09, HEAD_Y + 0.07, -0.01), rotm(ry=0.5)))
for s, seg in ((1, 'leg_l'), (-1, 'leg_r')):
    x = 0.08 * s
    c.add(seg, 'skin', leg_geo(x, 0.92)); c.add(seg, 'leather', boot_geo(x, 0.11))
    c.add(seg, 'steel', lathe([(0.06, 0.047), (0.1, 0.05), (0.15, 0.046)], 12, (x, 0, 0.006), 1.0, 1.0, cap0=False, cap1=False), ell((x, 0.17, 0.035), (0.03, 0.03, 0.02), 8, 6))
for s, seg in ((1, 'arm_l'), (-1, 'arm_r')):
    c.add(seg, 'skin', arm_geo(s, 0.92), hand_geo(s))
    c.add(seg, 'val_armor', ell((0.205 * s, 0.545, 0), (0.06, 0.045, 0.06), 12, 8), cyl((0.233 * s, 0.315, 0.04), 0.036, 0.075, 12, 0.04, R=rotm(rx=-0.35)))
hx, hy, hz = HAND(-1)
c.add('arm_r', 'steel', plate([(-0.018, 0.0), (0.018, 0.0), (0.014, 0.3), (0.0, 0.34), (-0.014, 0.3)], 0.01, (hx, hy + 0.02, hz + 0.02), rotm(rx=-0.25)))
c.add('arm_r', 'gold', boxr((hx, hy + 0.025, hz + 0.02), (0.11, 0.02, 0.03), 0.4), ball((hx, hy - 0.05, hz - 0.005), 0.018, 8, 6))
c.add('arm_r', 'leather', cyl((hx, hy - 0.04, hz), 0.014, 0.06, 8))
lx, ly, lz = HAND(1)
c.add('arm_l', 'val_blue', xform(lathe([(-0.012, 0.0), (-0.012, 0.15), (0.012, 0.15), (0.012, 0.0)], 26, cap0=False, cap1=False), (lx + 0.03, ly + 0.04, lz + 0.02), rotm(rz=PI / 2)))
c.add('arm_l', 'gold', xform(lathe([(-0.016, 0.15), (0.016, 0.16)], 26, cap0=False, cap1=False), (lx + 0.03, ly + 0.04, lz + 0.02), rotm(rz=PI / 2)),
      ell((lx + 0.048, ly + 0.04, lz + 0.02), (0.012, 0.04, 0.04), 10, 6))
# ================================================================ WIZARD (Merlin): long yellow robe, tall pointed hat, white beard, staff with a glowing orb
c = Char('wiz'); hero_frame(c)
c.add('body', 'wiz_robe', lathe([(0.0, 0.2), (0.08, 0.185), (0.2, 0.16), (0.32, 0.14), (0.42, 0.15), (0.5, 0.17), (0.555, 0.16), (0.6, 0.06)], 26, (0, 0, 0), 1.0, 0.8,
                                  wob=lambda y, a: 1 + 0.05 * np.cos(a * 7) * max(0, 0.3 - y) / 0.3, cap0=False))
c.add('body', 'wiz_trim', lathe([(0.0, 0.205), (0.03, 0.2)], 26, (0, 0, 0), 1.0, 0.8, cap0=False, cap1=False), belt_geo(0.33, 0.145, 0.8, 0.03),
      boxr((0, 0.33, 0.11), (0.04, 0.12, 0.02), 0.3))
c.add('body', 'gold', ell((0, 0.345, 0.12), (0.022, 0.022, 0.01), 8, 6))
c.add('body', 'skin', head_geo(0.95))
c.add('body', 'void', eyes_geo(r=0.011))
c.add('body', 'beard', lathe([(0.4, 0.0), (0.45, 0.03), (0.52, 0.055), (0.6, 0.07), (HEAD_Y - 0.02, 0.07)], 16, (0, 0, 0), 1.0, 0.6, zoff=lambda y: 0.07 + (y - 0.6) * 0.3),
      sweep([(0.05, HEAD_Y - 0.025, 0.08), (0.0, HEAD_Y - 0.035, 0.092), (-0.05, HEAD_Y - 0.025, 0.08)], 0.013, 6),
      ell((0.03, HEAD_Y + 0.04, 0.078), (0.025, 0.008, 0.01), 6, 4), ell((-0.03, HEAD_Y + 0.04, 0.078), (0.025, 0.008, 0.01), 6, 4))
c.add('body', 'wiz_robe', lathe([(HEAD_Y + 0.04, 0.22), (HEAD_Y + 0.055, 0.215), (HEAD_Y + 0.06, 0.1), (HEAD_Y + 0.14, 0.07), (HEAD_Y + 0.24, 0.035), (HEAD_Y + 0.33, 0.0)], 22,
                                  (0, 0, 0), zoff=lambda y: -max(0, y - HEAD_Y - 0.1) ** 1.6 * 0.9))
c.add('body', 'wiz_trim', lathe([(HEAD_Y + 0.06, 0.103), (HEAD_Y + 0.085, 0.097)], 22, cap0=False, cap1=False))
for s, seg in ((1, 'leg_l'), (-1, 'leg_r')):
    c.add(seg, 'wiz_trim', boxr((0.075 * s, 0.025, 0.06), (0.07, 0.05, 0.12), 0.4))
for s, seg in ((1, 'arm_l'), (-1, 'arm_r')):
    x = 0.205 * s
    c.add(seg, 'wiz_robe', sweep([(x, SH_Y, 0), (x + 0.03 * s, 0.43, -0.01), (x + 0.035 * s, 0.34, 0.045)], [0.055, 0.06, 0.075], 14))
    c.add(seg, 'wiz_trim', lathe([(0.0, 0.074), (0.02, 0.078)], 14, (x + 0.035 * s, 0.325, 0.05), cap0=False, cap1=False))
    c.add(seg, 'skin', hand_geo(s))
hx, hy, hz = HAND(-1)
c.add('arm_r', 'wood', sweep([(hx, hy - 0.29, hz), (hx, hy, hz), (hx + 0.01, hy + 0.3, hz), (hx - 0.01, hy + 0.42, hz), (hx + 0.02, hy + 0.47, hz)], [0.015, 0.017, 0.018, 0.022, 0.01], 8))
c.add('arm_r', 'orb', ball((hx, hy + 0.47, hz), 0.04, 12, 8))
c.add('arm_r', 'gold', lathe([(0.0, 0.025), (0.02, 0.03), (0.03, 0.02)], 10, (hx, hy + 0.41, hz), cap0=False, cap1=False))
# ================================================================ ELF (Questor): green tunic and hood, feather, pointed ears, bow, quiver
c = Char('elf'); hero_frame(c)
c.add('body', 'elf_green', torso_geo([(0.27, 0.12), (0.34, 0.12), (0.4, 0.115), (0.47, 0.135), (0.53, 0.15), (0.565, 0.125), (0.6, 0.05)], 0.66),
      kilt_geo(0.2, 0.33, 0.15, 0.124, 7, 0.1))
c.add('body', 'leather', belt_geo(0.32, 0.128, 0.7, 0.03), sweep([(0.13, 0.555, 0.06), (0.0, 0.46, 0.1), (-0.12, 0.33, 0.07)], 0.013, 8, 0.4),
      lathe([(0.3, 0.04), (0.5, 0.045), (0.52, 0.05)], 12, (0.05, 0.08, -0.12), R=rotm(rz=-0.35)))      # quiver
c.add('body', 'gold', ell((0, 0.335, 0.093), (0.022, 0.02, 0.01), 8, 6))
c.add('body', 'feather', *[cone((0.05 + 0.13 * np.sin(-0.35) * 0 + dx, 0.62, -0.12 + dz), 0.008, 0.06, 6) for dx, dz in ((-0.03, 0.0), (-0.01, 0.015), (0.0, -0.012))])
c.add('body', 'wood', *[cyl((0.05 + dx - 0.12 * 0.35, 0.5, -0.12 + dz), 0.005, 0.12, 5) for dx, dz in ((-0.0, 0.0), (0.02, 0.015), (0.03, -0.012))])
c.add('body', 'skin', head_geo(0.94), cone((0.075, HEAD_Y + 0.01, -0.005), 0.016, 0.07, 8, R=rotm(rz=-1.15)), cone((-0.075, HEAD_Y + 0.01, -0.005), 0.016, 0.07, 8, R=rotm(rz=1.15)))
c.add('body', 'void', eyes_geo(r=0.011))
c.add('body', 'elf_hair', ell((0, HEAD_Y + 0.0, -0.03), (0.085, 0.075, 0.075), 14, 8))
c.add('body', 'elf_dkgreen', lathe([(HEAD_Y + 0.02, 0.095), (HEAD_Y + 0.07, 0.092), (HEAD_Y + 0.11, 0.06), (HEAD_Y + 0.16, 0.02), (HEAD_Y + 0.2, 0.0)], 18, (0, 0, -0.01),
                                    zoff=lambda y: -max(0, y - HEAD_Y - 0.06) * 1.3),
      shell([(0.6, 0.12), (0.5, 0.16), (0.35, 0.19), (0.2, 0.2)], *BACK, 0.014, 0.75, 14))   # cap + cloak
c.add('body', 'feather', sweep([(0.07, HEAD_Y + 0.08, -0.03), (0.12, HEAD_Y + 0.14, -0.08), (0.14, HEAD_Y + 0.2, -0.15)], [0.012, 0.016, 0.004], 6, 0.3))
for s, seg in ((1, 'leg_l'), (-1, 'leg_r')):
    x = 0.075 * s
    c.add(seg, 'leather', leg_geo(x, 0.88)); c.add(seg, 'leather_dk', boot_geo(x, 0.13))
    c.add(seg, 'leather_dk', cone((x, 0.17, -0.004), 0.05, 0.05, 10, R=rotm(rx=PI)))
for s, seg in ((1, 'arm_l'), (-1, 'arm_r')):
    c.add(seg, 'elf_green', arm_geo(s, 0.95)); c.add(seg, 'skin', hand_geo(s))
    c.add(seg, 'leather', cyl((0.233 * s, 0.315, 0.04), 0.036, 0.07, 12, 0.039, R=rotm(rx=-0.35)))
lx, ly, lz = HAND(1)
bow = [(lx, ly + 0.24 * np.sin(a), lz + 0.02 + 0.09 * np.cos(a)) for a in np.linspace(-1.35, 1.35, 11)]
c.add('arm_l', 'wood', sweep(bow, [0.008 + 0.01 * np.cos(a) for a in np.linspace(-1.35, 1.35, 11)], 7))
c.add('arm_l', 'white', sweep([bow[0], (lx, ly, lz - 0.01), bow[-1]], 0.003, 4))
c.add('arm_l', 'leather', cyl((lx, ly - 0.025, lz + 0.11), 0.014, 0.05, 8))
# ================================================================ GHOST: hooded sheet floating, hollow eyes, ragged hem, reaching sleeves
c = Char('ghost'); c.seg('body', (0, 0, 0)).seg('arm_l', (0.16, 0.5, 0.02)).seg('arm_r', (-0.16, 0.5, 0.02))
c.add('body', 'ghost', lathe([(0.12, 0.22), (0.2, 0.2), (0.32, 0.17), (0.44, 0.17), (0.54, 0.18), (0.62, 0.16), (0.7, 0.11), (0.745, 0.05), (0.76, 0.0)], 26, (0, 0, 0), 1.0, 0.92,
                                wob=lambda y, a: 1 + (0.16 * np.sin(a * 7) + 0.07 * np.sin(a * 13 + 1)) * max(0, 0.3 - y) / 0.18, cap0=False))
c.add('body', 'void', ell((0.055, 0.6, 0.142), (0.04, 0.052, 0.03), 10, 8), ell((-0.055, 0.6, 0.142), (0.04, 0.052, 0.03), 10, 8),
      ell((0, 0.49, 0.152), (0.045, 0.03, 0.02), 10, 6))
c.add('body', 'eye_green', ell((0.055, 0.6, 0.165), (0.013, 0.016, 0.01), 8, 6), ell((-0.055, 0.6, 0.165), (0.013, 0.016, 0.01), 8, 6))
for s, seg in ((1, 'arm_l'), (-1, 'arm_r')):
    x = 0.16 * s
    c.add(seg, 'ghost', sweep([(x, 0.5, 0.02), (x + 0.04 * s, 0.44, 0.1), (x + 0.04 * s, 0.4, 0.2), (x + 0.03 * s, 0.37, 0.25)], [0.05, 0.05, 0.055, 0.035], 12),
          *[cone((x + 0.03 * s + d, 0.36, 0.26), 0.012, 0.05, 6, R=rotm(rx=1.3)) for d in (-0.02, 0.0, 0.02)])
# ================================================================ GRUNT: squat green brute, tusks, horns, leather loincloth, spiked club
c = Char('grunt'); c.seg('body', (0, 0, 0)).seg('leg_l', (0.1, 0.24, 0)).seg('leg_r', (-0.1, 0.24, 0)).seg('arm_l', (0.22, 0.48, 0.02)).seg('arm_r', (-0.22, 0.48, 0.02))
c.add('body', 'grunt_skin', lathe([(0.22, 0.15), (0.3, 0.19), (0.38, 0.21), (0.45, 0.22), (0.5, 0.2), (0.53, 0.14), (0.55, 0.05)], 24, (0, 0, 0), 1.0, 0.8, zoff=lambda y: (y - 0.22) * 0.12),
      ell((0, 0.56, 0.1), (0.105, 0.095, 0.1), 16, 10), ell((0, 0.52, 0.17), (0.07, 0.04, 0.05), 10, 6))    # head forward + jaw
c.add('body', 'grunt_cloth', kilt_geo(0.14, 0.27, 0.19, 0.17, 6, 0.12), belt_geo(0.25, 0.168, 0.82, 0.04))
c.add('body', 'bronze', ell((0, 0.27, 0.15), (0.03, 0.03, 0.012), 8, 6))
c.add('body', 'ivory', cone((0.04, 0.52, 0.21), 0.012, 0.05, 6), cone((-0.04, 0.52, 0.21), 0.012, 0.05, 6))
c.add('body', 'horn', horn((0.07, 0.63, 0.08), (1, 0.6, 0.2), 0.09, 0.022, 0.8), horn((-0.07, 0.63, 0.08), (-1, 0.6, 0.2), 0.09, 0.022, 0.8))
c.add('body', 'eye_red', ell((0.04, 0.585, 0.19), (0.016, 0.012, 0.008), 8, 6), ell((-0.04, 0.585, 0.19), (0.016, 0.012, 0.008), 8, 6))
for s, seg in ((1, 'leg_l'), (-1, 'leg_r')):
    x = 0.1 * s
    c.add(seg, 'grunt_skin', sweep([(x, 0.25, 0), (x * 1.1, 0.13, 0.02), (x, 0.05, 0)], [0.07, 0.06, 0.05], 12), boxr((x, 0.03, 0.03), (0.1, 0.06, 0.14), 0.35))
    c.add(seg, 'claw', *[cone((x + d, 0.015, 0.1), 0.01, 0.03, 5, R=rotm(rx=PI / 2)) for d in (-0.03, 0.0, 0.03)])
for s, seg in ((1, 'arm_l'), (-1, 'arm_r')):
    x = 0.22 * s
    c.add(seg, 'grunt_skin', ell((x, 0.48, 0.02), (0.07, 0.065, 0.065), 12, 8), sweep([(x, 0.47, 0.02), (x + 0.04 * s, 0.34, 0.03), (x + 0.04 * s, 0.24, 0.1)], [0.06, 0.052, 0.048], 12),
          ell((x + 0.04 * s, 0.22, 0.11), (0.045, 0.045, 0.045), 10, 8))
    c.add(seg, 'leather', cyl((x + 0.04 * s, 0.25, 0.08), 0.052, 0.06, 12, R=rotm(rx=-0.5)))
cx, cy, cz = -0.26, 0.22, 0.11
c.add('arm_r', 'wood', lathe([(-0.06, 0.02), (0.05, 0.024), (0.2, 0.04), (0.33, 0.055), (0.36, 0.0)], 12, (cx, cy, cz), R=rotm(rx=0.5)))
c.add('arm_r', 'steel_dk', *[cone((cx, cy, cz) + rotm(rx=0.5) @ np.array([np.cos(a) * 0.045, yy, np.sin(a) * 0.045]), 0.012, 0.04, 5,
                              R=rotm(rx=0.5) @ rotm(rz=-np.cos(a) * PI / 2, rx=np.sin(a) * PI / 2)) for yy in (0.22, 0.3) for a in np.linspace(0, 2 * PI, 6)[:-1] + yy * 9])
# ================================================================ DEMON: red horned fiend with bat wings, tail, claws, glowing yellow eyes
c = Char('demon'); c.seg('body', (0, 0, 0)).seg('leg_l', (0.09, 0.27, 0)).seg('leg_r', (-0.09, 0.27, 0)).seg('arm_l', (0.19, 0.53, 0)).seg('arm_r', (-0.19, 0.53, 0))
c.seg('wing_l', (0.07, 0.52, -0.09)).seg('wing_r', (-0.07, 0.52, -0.09))
c.add('body', 'demon_skin', torso_geo([(0.26, 0.12), (0.33, 0.13), (0.4, 0.13), (0.47, 0.17), (0.53, 0.18), (0.56, 0.14), (0.6, 0.05)], 0.68),
      ell((0.055, 0.48, 0.09), (0.06, 0.045, 0.03), 10, 6), ell((-0.055, 0.48, 0.09), (0.06, 0.045, 0.03), 10, 6),
      head_geo(1.0, 0.68), cone((0.07, 0.69, 0), 0.018, 0.06, 6, R=rotm(rz=-1.3)), cone((-0.07, 0.69, 0), 0.018, 0.06, 6, R=rotm(rz=1.3)),
      sweep([(0, 0.27, -0.1), (0, 0.18, -0.2), (0.03, 0.08, -0.28), (0.08, 0.05, -0.36), (0.12, 0.08, -0.4)], [0.03, 0.025, 0.02, 0.014, 0.008], 8))
c.add('body', 'horn', horn((0.05, 0.75, 0.02), (0.6, 0.6, -0.4), 0.13, 0.024, 0.7), horn((-0.05, 0.75, 0.02), (-0.6, 0.6, -0.4), 0.13, 0.024, 0.7),
      cone((0.12, 0.08, -0.4), 0.02, 0.06, 6, R=rotm(rz=-1.0)), lathe([(0.27, 0.13), (0.33, 0.135), (0.34, 0.13)], 22, (0, 0, 0), 1.0, 0.7, cap0=False, cap1=False))
c.add('body', 'eye_yel', ell((0.032, 0.695, 0.078), (0.016, 0.01, 0.008), 8, 6), ell((-0.032, 0.695, 0.078), (0.016, 0.01, 0.008), 8, 6))
c.add('body', 'void', ell((0, 0.645, 0.085), (0.03, 0.01, 0.01), 8, 4))
for s, seg in ((1, 'leg_l'), (-1, 'leg_r')):
    x = 0.09 * s
    c.add(seg, 'demon_skin', sweep([(x, 0.28, 0), (x, 0.17, 0.05), (x, 0.09, -0.02), (x, 0.03, 0.02)], [0.06, 0.05, 0.04, 0.035], 12))   # digitigrade leg
    c.add(seg, 'claw', *[cone((x + d, 0.02, 0.04), 0.012, 0.05, 5, R=rotm(rx=PI / 2)) for d in (-0.025, 0.0, 0.025)])
for s, seg in ((1, 'arm_l'), (-1, 'arm_r')):
    x = 0.19 * s
    c.add(seg, 'demon_skin', ell((x, 0.52, 0), (0.055, 0.05, 0.05), 10, 8), sweep([(x, 0.53, 0), (x + 0.03 * s, 0.41, 0.0), (x + 0.03 * s, 0.31, 0.07)], [0.045, 0.037, 0.03], 12),
          ell((x + 0.03 * s, 0.29, 0.085), (0.032, 0.035, 0.032), 10, 8))
    c.add(seg, 'claw', *[cone((x + 0.03 * s + d, 0.27, 0.1), 0.007, 0.04, 5, R=rotm(rx=PI * 0.75)) for d in (-0.015, 0.0, 0.015)])
for s, seg in ((1, 'wing_l'), (-1, 'wing_r')):
    bx, by, bz = 0.07 * s, 0.52, -0.09
    bones = [(bx, by, bz), (bx + 0.16 * s, by + 0.14, bz - 0.06), (bx + 0.33 * s, by + 0.1, bz - 0.08)]
    c.add(seg, 'horn', sweep(bones, [0.02, 0.016, 0.006], 8), sweep([bones[1], (bx + 0.28 * s, by - 0.06, bz - 0.1)], [0.012, 0.004], 6),
          sweep([bones[1], (bx + 0.16 * s, by - 0.14, bz - 0.09)], [0.012, 0.004], 6))
    mem = [(0.0, 0.0), (0.16, 0.14), (0.33, 0.1), (0.3, 0.0), (0.28, -0.06), (0.22, -0.05), (0.16, -0.14), (0.1, -0.1), (0.03, -0.08)]
    c.add(seg, 'demon_wing', plate([(p[0] * s, p[1]) for p in mem][::s], 0.01, (bx, by, bz - 0.07), rotm(ry=0)))
# ================================================================ LOBBER: hunched little goblin with big ears and a sack of rocks
c = Char('lobber'); c.seg('body', (0, 0, 0)).seg('leg_l', (0.07, 0.17, 0)).seg('leg_r', (-0.07, 0.17, 0)).seg('arm_l', (0.15, 0.36, 0.05)).seg('arm_r', (-0.15, 0.36, 0.05))
c.add('body', 'lob_skin', lathe([(0.15, 0.1), (0.22, 0.13), (0.3, 0.14), (0.36, 0.12), (0.4, 0.06)], 20, (0, 0, 0), 1.0, 0.85, zoff=lambda y: (y - 0.15) * 0.4),
      ell((0, 0.44, 0.14), (0.085, 0.075, 0.08), 14, 10), ell((0, 0.42, 0.22), (0.02, 0.03, 0.04), 8, 6),
      plate([(0, 0), (0.09, 0.04), (0.13, 0.07), (0.07, -0.02)], 0.01, (0.07, 0.46, 0.12), rotm(ry=-0.3)),
      plate([(0, 0), (-0.07, -0.02), (-0.13, 0.07), (-0.09, 0.04)], 0.01, (-0.07, 0.46, 0.12), rotm(ry=0.3)))
c.add('body', 'grunt_cloth', kilt_geo(0.1, 0.2, 0.13, 0.11, 5, 0.12))
c.add('body', 'sack', ell((0.0, 0.38, -0.1), (0.11, 0.12, 0.09), 14, 9), cone((0.0, 0.48, -0.1), 0.04, 0.05, 8))
c.add('body', 'leather', sweep([(0.1, 0.4, 0.06), (0.03, 0.33, 0.12), (-0.09, 0.22, 0.08)], 0.01, 6, 0.4))
c.add('body', 'eye_yel', ell((0.032, 0.455, 0.205), (0.016, 0.014, 0.008), 8, 6), ell((-0.032, 0.455, 0.205), (0.016, 0.014, 0.008), 8, 6))
for s, seg in ((1, 'leg_l'), (-1, 'leg_r')):
    x = 0.07 * s
    c.add(seg, 'lob_skin', sweep([(x, 0.17, 0), (x, 0.09, 0.04), (x, 0.03, 0)], [0.045, 0.038, 0.032], 10), boxr((x, 0.02, 0.04), (0.07, 0.04, 0.12), 0.4))
for s, seg in ((1, 'arm_l'), (-1, 'arm_r')):
    x = 0.15 * s
    c.add(seg, 'lob_skin', sweep([(x, 0.36, 0.05), (x + 0.03 * s, 0.27, 0.08), (x + 0.03 * s, 0.19, 0.13)], [0.035, 0.03, 0.026], 10), ell((x + 0.03 * s, 0.175, 0.14), (0.03, 0.03, 0.03), 8, 6))
c.add('arm_r', 'rock', ell((-0.18, 0.16, 0.18), (0.045, 0.04, 0.045), 9, 6))
# ================================================================ SORCERER: hooded purple robe, gold trim, raised glowing hands
c = Char('sorc'); c.seg('body', (0, 0, 0)).seg('arm_l', (0.18, 0.55, 0)).seg('arm_r', (-0.18, 0.55, 0))
c.add('body', 'sorc_robe', lathe([(0.0, 0.21), (0.1, 0.19), (0.25, 0.16), (0.38, 0.15), (0.48, 0.165), (0.55, 0.16), (0.6, 0.08)], 26, (0, 0, 0), 1.0, 0.82,
                                   wob=lambda y, a: 1 + 0.06 * np.cos(a * 8) * max(0, 0.25 - y) / 0.25, cap0=False),
      lathe([(0.55, 0.12), (0.6, 0.125), (0.68, 0.12), (0.75, 0.09), (0.8, 0.04), (0.84, 0.0)], 20, (0, 0, -0.02), 1.0, 1.0, zoff=lambda y: -max(0, y - 0.72) * 0.8))
c.add('body', 'sorc_dk', ell((0, 0.66, 0.06), (0.085, 0.085, 0.07), 14, 9))
c.add('body', 'gold', lathe([(0.0, 0.215), (0.025, 0.21)], 26, (0, 0, 0), 1.0, 0.82, cap0=False, cap1=False),
      sweep([(0.1, 0.58, 0.09), (0.12, 0.66, 0.1), (0.1, 0.76, 0.07)], 0.012, 6), sweep([(-0.1, 0.58, 0.09), (-0.12, 0.66, 0.1), (-0.1, 0.76, 0.07)], 0.012, 6),
      boxr((0, 0.36, 0.125), (0.04, 0.3, 0.02), 0.3), ell((0, 0.5, 0.13), (0.03, 0.03, 0.015), 8, 6))
c.add('body', 'eye_red', ell((0.03, 0.66, 0.12), (0.016, 0.01, 0.008), 8, 6), ell((-0.03, 0.66, 0.12), (0.016, 0.01, 0.008), 8, 6))
for s, seg in ((1, 'arm_l'), (-1, 'arm_r')):
    x = 0.18 * s
    c.add(seg, 'sorc_robe', sweep([(x, 0.55, 0), (x + 0.03 * s, 0.44, 0.0), (x + 0.04 * s, 0.35, 0.05)], [0.05, 0.055, 0.075], 12))
    c.add(seg, 'gold', lathe([(0.0, 0.074), (0.02, 0.078)], 14, (x + 0.04 * s, 0.335, 0.055), cap0=False, cap1=False))
    c.add(seg, 'skin_dk', hand_geo(s * 0.92, 0.07, 0.31))
    c.add(seg, 'magic', ball((x + 0.05 * s, 0.27, 0.09), 0.03, 10, 7))
# ================================================================ DEATH: black tattered robe, skull in the hood, bony hands, scythe
c = Char('death'); c.seg('body', (0, 0, 0)).seg('arm_l', (0.2, 0.6, 0)).seg('arm_r', (-0.2, 0.6, 0))
c.add('body', 'death_robe', lathe([(0.0, 0.25), (0.12, 0.21), (0.3, 0.17), (0.45, 0.17), (0.56, 0.19), (0.62, 0.17), (0.66, 0.09)], 28, (0, 0, 0), 1.0, 0.82,
                                    wob=lambda y, a: 1 + (0.14 * np.sin(a * 9) + 0.06 * np.sin(a * 17)) * max(0, 0.22 - y) / 0.22, cap0=False),
      lathe([(0.6, 0.13), (0.66, 0.14), (0.76, 0.13), (0.84, 0.1), (0.9, 0.05), (0.93, 0.0)], 20, (0, 0, -0.03), zoff=lambda y: -max(0, y - 0.8) * 0.9))
c.add('body', 'void', ell((0, 0.73, 0.06), (0.1, 0.1, 0.08), 14, 9))
c.add('body', 'bone', ell((0, 0.735, 0.09), (0.062, 0.07, 0.065), 14, 10), boxr((0, 0.68, 0.115), (0.06, 0.035, 0.04), 0.4))
c.add('body', 'eye_red', ell((0.024, 0.745, 0.15), (0.014, 0.012, 0.006), 8, 6), ell((-0.024, 0.745, 0.15), (0.014, 0.012, 0.006), 8, 6))
for s, seg in ((1, 'arm_l'), (-1, 'arm_r')):
    x = 0.2 * s
    c.add(seg, 'death_robe', sweep([(x, 0.6, 0), (x + 0.03 * s, 0.48, 0.0), (x + 0.04 * s, 0.38, 0.06)], [0.055, 0.06, 0.08], 12,))
    c.add(seg, 'bone', *[sweep([(x + 0.045 * s, 0.35, 0.07), (x + 0.045 * s + d, 0.3, 0.11)], 0.007, 5) for d in (-0.02, 0.0, 0.02)],
          ell((x + 0.045 * s, 0.355, 0.07), (0.025, 0.02, 0.02), 8, 6))
sx_, sy_, sz_ = -0.245, 0.33, 0.1
c.add('arm_r', 'wood', sweep([(sx_, sy_ - 0.3, sz_), (sx_, sy_, sz_), (sx_ - 0.01, sy_ + 0.35, sz_ - 0.02), (sx_ - 0.02, sy_ + 0.55, sz_ - 0.05)], [0.016, 0.017, 0.016, 0.014], 8))
c.add('arm_r', 'steel', plate([(0, 0.02), (0.1, 0.05), (0.22, 0.03), (0.32, -0.04), (0.2, -0.0), (0.08, -0.02), (0.0, -0.02)], 0.012, (sx_ - 0.02, sy_ + 0.54, sz_ - 0.05), rotm(ry=PI / 2 + 0.15)))

# ---------------------------------------------------------------- write meshes + Lua rig table
if '--nosave' not in sys.argv:
    import glob
    for f in glob.glob(os.path.join(OUT, 'ch_*.obj')): os.remove(f)
    L = ['------------------------------------------------------------------ rigs (generated by tools/gen_chars.py, do not edit)',
         '-- RIG[kind] = list of segments {name, pivot, meshes}; each mesh has its own material in PAL', 'local RIG = {']
    used = set(); total = 0
    for kind, ch in CH.items():
        L.append('    %s = {' % kind)
        for seg in ch.order:
            pv = ch.piv[seg]; names = []
            for (sg, mat), m in ch.parts.items():
                if sg != seg: continue
                nm = 'ch_%s_%s_%s' % (kind, seg, mat)
                save(nm, xform(m, -pv)); names.append(nm); used.add((nm, mat)); total += len(m.F)
            L.append('        { name = "%s", piv = { %.4f, %.4f, %.4f }, meshes = { %s } },' % (seg, pv[0], pv[1], pv[2], ', '.join('"%s"' % n for n in names)))
        L.append('    },')
    L.append('}')
    L.append('local RMAT = {')
    for k, (b, e, r, mt) in MATS.items():
        L.append('    %s = { { %.3f, %.3f, %.3f }, { %.3f, %.3f, %.3f }, %.2f, %.2f },' % (k, *b, *e, r, mt))
    L.append('}')
    L.append('for _, kv in ipairs({' + ', '.join('{ "%s", "%s" }' % u for u in sorted(used)) + '}) do PAL[kv[1]] = RMAT[kv[2]] end')
    L.append('G.RIG = RIG')
    open(os.path.join(H, '..', 'src', '02b_rigs.lua'), 'w').write('\n'.join(L) + '\n')
    print(len(used), 'rig meshes', total, 'tris')
