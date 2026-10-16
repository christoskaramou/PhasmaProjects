# Level layouts: 32x26 tile grid, x = col-16 (left edge), y = row (bottom edge). Spans: (row, c0, c1) inclusive.
COLS, ROWS = 32, 26
GAP = (13, 18)   # wrap-through hole in floor and ceiling
def sym(row, c0, c1): return [(row, c0, c1), (row, 31 - c1, 31 - c0)]
L = []
# 1: classic ledges
s = []
for r in (5, 9, 13, 17, 21): s += sym(r, 2, 5) + [(r, 10, 21)]
L.append(dict(name='Bubble Cave', spans=s, col=(0.95, 0.45, 0.75), enemies=['zen'] * 3 + ['zen'] * 0, spawn=[(-6, 22.5), (0, 22.5), (6, 22.5)]))
# 2: staircase
s = []
for i, r in enumerate((5, 9, 13, 17, 21)):
    s += sym(r, 2 + i * 2, 7 + i * 2)
s += [(3, 14, 17)]
L.append(dict(name='Twin Stairs', spans=s, col=(0.3, 0.75, 1.0), enemies=['zen'] * 4, spawn=[(-8, 22.5), (-3, 22.5), (3, 22.5), (8, 22.5)]))
# 3: cross-shaped tower
s = []
for r in (5, 9, 13, 17, 21): s += sym(r, 2, 4)
s += [(5, 8, 23), (9, 12, 19), (13, 7, 24), (17, 12, 19), (21, 9, 22)]
L.append(dict(name='Crystal Tower', spans=s, col=(0.45, 1.0, 0.55), enemies=['zen', 'zen', 'monsta', 'zen', 'monsta'], spawn=[(-9, 22.5), (-4, 22.5), (0, 22.5), (4, 22.5), (9, 22.5)]))
# 4: zig-zag
s = []
s += [(5, 2, 12), (5, 19, 29), (9, 8, 23), (13, 2, 10), (13, 21, 29), (17, 8, 23), (21, 2, 12), (21, 19, 29)]
L.append(dict(name='Zig Zag', spans=s, col=(1.0, 0.7, 0.25), enemies=['monsta', 'zen', 'zen', 'monsta', 'zen'], spawn=[(-10, 22.5), (-5, 22.5), (0, 22.5), (5, 22.5), (10, 22.5)]))
# 5: islands
s = []
for r, cs in ((5, [(4, 8), (13, 18), (23, 27)]), (9, [(2, 4), (9, 12), (19, 22), (27, 29)]), (13, [(5, 9), (14, 17), (22, 26)]),
              (17, [(2, 5), (10, 13), (18, 21), (26, 29)]), (21, [(6, 11), (20, 25)])):
    s += [(r, a, b) for a, b in cs]
L.append(dict(name='Floating Isles', spans=s, col=(0.7, 0.5, 1.0), enemies=['monsta'] * 3 + ['zen'] * 3, spawn=[(-11, 22.5), (-6, 22.5), (-2, 22.5), (2, 22.5), (6, 22.5), (11, 22.5)]))
def solids(lv):
    """all solid boxes (x0,y0,x1,y1) in world units incl. walls/floor/ceiling"""
    b = [(-16, 0, -14, 26), (14, 0, 16, 26)]
    for r in (0, 25):
        b += [(-14, r, GAP[0] - 16, r + 1), (GAP[1] + 1 - 16, r, 14, r + 1)]
    for r, c0, c1 in lv['spans']: b.append((c0 - 16, r, c1 + 1 - 16, r + 1))
    return b
