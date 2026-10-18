# Gauntlet Remix levels: 20 fixed dungeon floors (fixed seeds, so every level plays the same each time, like the arcade),
# written as src/03_levels.lua plus merged wall/floor (and trap-wall) meshes per level. After level 20 the dungeon loops
# with tougher monsters ("Round 2", "Round 3", ...).
# Six layout styles so floors read differently: braided maze, halls (rooms + corridors), pillar halls, concentric rings,
# mirrored (symmetric) maze, diagonal walls; every fifth floor is a timed Treasure Room.
# Legend: # wall . floor D door k key f food p potion t treasure E exit X exit to level+N (per-level 'jump')
#         S start T trap tile (makes every w wall vanish) w trap wall z stun tile
#         g ghost r grunt d demon l lobber s sorcerer generators
# Every floor is validated: the exit (and any jump exit) is reachable from the start with all doors, trap walls and
# generators treated as solid, so a level can always be finished without keys or traps.
import sys, os, random
from collections import deque
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from meshlib import *
H = os.path.dirname(os.path.abspath(__file__))
DIRS = ((1, 0), (-1, 0), (0, 1), (0, -1))
# name, style, seed, (W, H), generator kinds, start anchor (fx, fy of the map), jump N (0 = none), wall tex, floor tex, wall tint, floor tint
SPEC = [
    ('Level 1', 'maze', 101, (29, 21), 'g', (0, 1), 0, 0, 0, (1.0, 1.0, 1.0), (.9, .9, .9)),
    ('Level 2', 'halls', 202, (33, 25), 'gr', (0, 0), 0, 1, 1, (1.0, 1.0, 1.0), (.9, .9, .9)),
    ('Level 3', 'pillars', 303, (31, 23), 'gr', (.5, 1), 0, 4, 4, (1.0, .97, .92), (.9, .9, .9)),
    ('Level 4', 'rings', 404, (33, 25), 'rd', (.5, .5), 4, 2, 2, (1.0, 1.0, 1.0), (.9, .9, .9)),
    ('Treasure Room', 'treasure', 505, (27, 19), '', (0, .5), 0, 5, 5, (.95, .9, .8), (.9, .85, .8)),
    ('Level 6', 'mirror', 606, (35, 25), 'gl', (.5, 0), 0, 3, 3, (1.0, 1.0, 1.0), (.9, .9, .9)),
    ('Level 7', 'diag', 707, (33, 25), 'gds', (1, 0), 0, 0, 4, (.85, .8, .75), (.85, .85, .85)),
    ('Level 8', 'maze', 808, (37, 27), 'grd', (1, 1), 0, 1, 0, (.8, .8, .9), (.85, .85, .9)),
    ('Level 9', 'halls', 909, (39, 27), 'dls', (0, .5), 3, 4, 2, (.85, .85, .85), (.85, .85, .85)),
    ('Treasure Room', 'treasure', 1010, (29, 21), '', (.5, 0), 0, 5, 1, (.9, .95, 1.0), (.85, .88, .9)),
    ('Level 11', 'pillars', 1111, (37, 27), 'gls', (0, 0), 0, 2, 5, (.9, .85, .8), (.85, .85, .85)),
    ('Level 12', 'rings', 1212, (37, 29), 'gdr', (0, 1), 2, 3, 0, (.85, .95, .85), (.85, .85, .85)),
    ('Level 13', 'mirror', 1313, (39, 27), 'rdl', (.5, 1), 0, 0, 1, (.75, .72, .7), (.8, .8, .8)),
    ('Level 14', 'diag', 1414, (37, 27), 'gsl', (0, .5), 0, 4, 3, (.95, .85, .8), (.85, .85, .85)),
    ('Treasure Room', 'treasure', 1515, (31, 21), '', (1, .5), 0, 5, 2, (.9, .8, .7), (.85, .8, .75)),
    ('Level 16', 'maze', 1616, (41, 29), 'gdls', (.5, .5), 3, 2, 4, (.75, .7, .7), (.8, .8, .8)),
    ('Level 17', 'halls', 1717, (41, 29), 'grds', (1, 1), 0, 1, 5, (.7, .7, .78), (.8, .8, .85)),
    ('Level 18', 'pillars', 1818, (39, 29), 'dlsg', (1, 0), 0, 3, 2, (.8, .9, .8), (.8, .8, .8)),
    ('Level 19', 'rings', 1919, (41, 29), 'gdls', (0, 0), 0, 4, 0, (.7, .7, .7), (.75, .75, .75)),
    ('Treasure Room', 'treasure', 2020, (33, 23), '', (.5, .5), 0, 5, 3, (.85, .8, .75), (.8, .78, .75)),
]

def grid(W, Hh, ch='#'): return [[ch] * W for _ in range(Hh)]
def border(g):
    W, Hh = len(g[0]), len(g)
    for x in range(W): g[0][x] = g[Hh - 1][x] = '#'
    for y in range(Hh): g[y][0] = g[y][W - 1] = '#'

def carve_maze(R, g, x0=1, x1=None, braid=0.45):
    W, Hh = len(g[0]), len(g); x1 = x1 or W - 2
    st = [(x0, 1)]; g[1][x0] = '.'
    while st:
        x, y = st[-1]
        nb = [(x + dx, y + dy, dx, dy) for dx, dy in ((2, 0), (-2, 0), (0, 2), (0, -2)) if x0 <= x + dx <= x1 and 0 < y + dy < Hh - 1 and g[y + dy][x + dx] == '#']
        if not nb: st.pop(); continue
        nx, ny, dx, dy = R.choice(nb); g[y + dy // 2][x + dx // 2] = '.'; g[ny][nx] = '.'; st.append((nx, ny))
    for y in range(1, Hh - 1):
        for x in range(max(1, x0), min(W - 1, x1 + 1)):
            if g[y][x] == '#' and (x + y) % 2 == 1 and R.random() < braid:
                if (g[y][x - 1] == '.' and g[y][x + 1] == '.') or (g[y - 1][x] == '.' and g[y + 1][x] == '.'): g[y][x] = '.'

def room(g, x0, y0, w, h, ch='.'):
    for y in range(y0, y0 + h):
        for x in range(x0, x0 + w):
            if 0 < x < len(g[0]) - 1 and 0 < y < len(g) - 1: g[y][x] = ch

def st_maze(R, W, Hh):
    g = grid(W, Hh); carve_maze(R, g, braid=0.5)
    for _ in range(3 + W // 12):
        w, h = R.choice((3, 5, 5, 7)), R.choice((3, 5))
        room(g, R.randrange(1, W - w - 1, 2), R.randrange(1, Hh - h - 1, 2), w, h)
    return g

def st_halls(R, W, Hh):
    # rooms with 1-thick walls, joined by corridors (some two wide), plus a few extra loops
    g = grid(W, Hh); rooms = []
    for _ in range(400):
        w, h = R.randrange(4, 10), R.randrange(3, 7)
        x, y = R.randrange(1, W - w - 1), R.randrange(1, Hh - h - 1)
        if any(x < a + c + 2 and a < x + w + 2 and y < b + d + 2 and b < y + h + 2 for a, b, c, d in rooms): continue
        rooms.append((x, y, w, h)); room(g, x, y, w, h)
        if len(rooms) >= 6 + (W * Hh) // 160: break
    cen = [(x + w // 2, y + h // 2) for x, y, w, h in rooms]
    order = list(range(len(cen))); done = [order.pop(0)]
    def corridor(a, b, wide):
        (x0, y0), (x1, y1) = a, b
        if R.random() < 0.5:
            for x in range(min(x0, x1), max(x0, x1) + 1): g[y0][x] = '.'; wide and 0 < y0 + 1 < Hh - 1 and g[y0 + 1].__setitem__(x, '.')
            for y in range(min(y0, y1), max(y0, y1) + 1): g[y][x1] = '.'; wide and 0 < x1 + 1 < W - 1 and g[y].__setitem__(x1 + 1, '.')
        else:
            for y in range(min(y0, y1), max(y0, y1) + 1): g[y][x0] = '.'; wide and 0 < x0 + 1 < W - 1 and g[y].__setitem__(x0 + 1, '.')
            for x in range(min(x0, x1), max(x0, x1) + 1): g[y1][x] = '.'; wide and 0 < y1 + 1 < Hh - 1 and g[y1 + 1].__setitem__(x, '.')
    while order:   # Prim-style: connect the nearest unconnected room
        best = min(((abs(cen[i][0] - cen[j][0]) + abs(cen[i][1] - cen[j][1]), i, j) for i in order for j in done))
        corridor(cen[best[2]], cen[best[1]], R.random() < 0.35); done.append(best[1]); order.remove(best[1])
    for _ in range(2 + len(rooms) // 4): corridor(R.choice(cen), R.choice(cen), False)
    # pillars inside big rooms
    for x, y, w, h in rooms:
        if w >= 7 and h >= 5 and R.random() < 0.6:
            for px in range(x + 2, x + w - 2, 3): g[y + 1][px] = '#'; g[y + h - 2][px] = '#'
    border(g); return g

def st_pillars(R, W, Hh):
    # open pillared halls cut by long walls with gaps (Gauntlet's colonnade floors)
    g = grid(W, Hh, '.'); border(g)
    sp = R.choice((2, 3))
    for y in range(2, Hh - 2, sp):
        for x in range(2, W - 2, sp):
            if R.random() < 0.8: g[y][x] = '#'
    for _ in range(4 + W // 8):
        if R.random() < 0.5:
            y = R.randrange(3, Hh - 3); a = R.randrange(1, W - 8); b = a + R.randrange(5, 12)
            for x in range(a, min(b, W - 1)): g[y][x] = '#'
            for _ in range(2): g[y][R.randrange(a, min(b, W - 1))] = '.'
        else:
            x = R.randrange(3, W - 3); a = R.randrange(1, Hh - 6); b = a + R.randrange(4, 9)
            for y in range(a, min(b, Hh - 1)): g[y][x] = '#'
            g[R.randrange(a, min(b, Hh - 1))][x] = '.'
    return g

def st_rings(R, W, Hh):
    # concentric walled rings with offset gaps, joined by short spokes: the spiral floors of the arcade
    g = grid(W, Hh, '.'); border(g)
    k = 2
    while k < min(W, Hh) // 2 - 1:
        x0, y0, x1, y1 = k, k, W - 1 - k, Hh - 1 - k
        cells = [(x, y0) for x in range(x0, x1 + 1)] + [(x1, y) for y in range(y0 + 1, y1 + 1)] + \
                [(x, y1) for x in range(x1 - 1, x0 - 1, -1)] + [(x0, y) for y in range(y1 - 1, y0, -1)]
        for x, y in cells: g[y][x] = '#'
        n = len(cells)
        for _ in range(R.choice((1, 2, 2, 3))):
            i = R.randrange(n); x, y = cells[i]
            if (x, y) not in ((x0, y0), (x1, y0), (x0, y1), (x1, y1)): g[y][x] = '.'
            j = (i + 1) % n; x, y = cells[j]
            if (x, y) not in ((x0, y0), (x1, y0), (x0, y1), (x1, y1)): g[y][x] = '.'
        # a few spokes (short wall stubs) inside the corridor make it a chase, not a loop
        for _ in range(R.randrange(1, 4)):
            x, y = R.choice(cells)
            if x == x0 and x0 > 2: g[y][x - 1] = '#'
            elif y == y0 and y0 > 2: g[y - 1][x] = '#'
        k += R.choice((2, 3))
    return g

def st_mirror(R, W, Hh):
    g = grid(W, Hh); half = W // 2
    carve_maze(R, g, 1, half - (1 if half % 2 == 0 else 0), braid=0.5)
    for y in range(Hh):
        for x in range(half + 1, W): g[y][x] = g[y][W - 1 - x]
    # open the spine so both halves join, and a central hall
    for y in range(1, Hh - 1, 2): g[y][half] = '.'
    room(g, half - 3, Hh // 2 - 2, 7, 5)
    border(g); return g

def st_diag(R, W, Hh):
    # open floor crossed by thick diagonal walls (Gauntlet's slanted walls), with gaps
    g = grid(W, Hh, '.'); border(g)
    for _ in range(7 + (W * Hh) // 140):
        x, y = R.randrange(2, W - 2), R.randrange(2, Hh - 2); sx, sy = R.choice((1, -1)), R.choice((1, -1))
        L = R.randrange(4, 10); gap = R.randrange(1, L)
        for i in range(L):
            if i == gap: continue
            a, b = x + i * sx, y + i * sy
            if 0 < a < W - 1 and 0 < b < Hh - 1: g[b][a] = '#'
            if 0 < a + sx < W - 1 and 0 < b < Hh - 1: g[b][a + sx] = '#'   # 2-thick so it reads as a wall
    for _ in range(3):
        w, h = R.choice((3, 4, 5)), R.choice((3, 4))
        x, y = R.randrange(2, W - w - 2), R.randrange(2, Hh - h - 2)
        for xx in range(x, x + w): g[y][xx] = '#'; g[y + h][xx] = '#'
        for yy in range(y, y + h + 1): g[yy][x] = '#'; g[yy][x + w] = '#'
        g[y + h // 2][x + (w if R.random() < 0.5 else 0)] = '.'
    return g

def st_treasure(R, W, Hh):
    # a vault: inner chambers full of treasure, no generators; grab what you can before the timer runs out
    g = grid(W, Hh, '.'); border(g)
    cx, cy = W // 2, Hh // 2
    for k, (w, h) in enumerate(((W - 8, Hh - 6), (W - 16, Hh - 12))):
        if w < 5 or h < 3: continue
        x0, y0 = cx - w // 2, cy - h // 2
        for x in range(x0, x0 + w + 1): g[y0][x] = '#'; g[y0 + h][x] = '#'
        for y in range(y0, y0 + h + 1): g[y][x0] = '#'; g[y][x0 + w] = '#'
        for _ in range(2 + k):
            side = R.randrange(4)
            if side == 0: g[y0][R.randrange(x0 + 1, x0 + w)] = '.'
            elif side == 1: g[y0 + h][R.randrange(x0 + 1, x0 + w)] = '.'
            elif side == 2: g[R.randrange(y0 + 1, y0 + h)][x0] = '.'
            else: g[R.randrange(y0 + 1, y0 + h)][x0 + w] = '.'
    for _ in range(6):
        x, y = R.randrange(2, W - 2), R.randrange(2, Hh - 2)
        if g[y][x] == '.' and abs(x - cx) + abs(y - cy) > 3: g[y][x] = '#'
    return g

STYLES = dict(maze=st_maze, halls=st_halls, pillars=st_pillars, rings=st_rings, mirror=st_mirror, diag=st_diag, treasure=st_treasure)

def bfs(g, s, block='#DwGgrdls'):
    d = {s: 0}; q = deque([s])
    while q:
        x, y = q.popleft()
        for dx, dy in DIRS:
            n = (x + dx, y + dy)
            if g[n[1]][n[0]] not in block and n not in d: d[n] = d[(x, y)] + 1; q.append(n)
    return d

def connect(g, s):
    # carve straight corridors until every open cell is reachable from s
    W, Hh = len(g[0]), len(g)
    while True:
        D = bfs(g, s, '#')
        rest = [(x, y) for y in range(1, Hh - 1) for x in range(1, W - 1) if g[y][x] != '#' and (x, y) not in D]
        if not rest: return
        a = rest[0]; b = min(D, key=lambda c: abs(c[0] - a[0]) + abs(c[1] - a[1]))
        x, y = a
        while x != b[0]: x += 1 if b[0] > x else -1; g[y][x] = '.' if g[y][x] == '#' else g[y][x]
        while y != b[1]: y += 1 if b[1] > y else -1; g[y][x] = '.' if g[y][x] == '#' else g[y][x]

def make(spec, lvl):
    name, style, seed, (W, Hh), kinds, anchor, jump = spec[:7]
    R = random.Random(seed)
    g = STYLES[style](R, W, Hh)
    border(g)
    # start: open floor nearest the anchor, with a small clearing around it
    ax, ay = 1 + anchor[0] * (W - 3), 1 + (1 - anchor[1]) * (Hh - 3)   # anchor y=1 is the top (north) edge
    open_ = [(x, y) for y in range(1, Hh - 1) for x in range(1, W - 1) if g[y][x] == '.']
    sx, sy = min(open_, key=lambda c: (c[0] - ax) ** 2 + (c[1] - ay) ** 2)
    for y in range(sy - 1, sy + 2):
        for x in range(sx - 1, sx + 2):
            if 0 < x < W - 1 and 0 < y < Hh - 1: g[y][x] = '.'
    connect(g, (sx, sy))
    D = bfs(g, (sx, sy))
    far = sorted(D, key=D.get); mx = D[far[-1]]
    cand = [c for c in far if D[c] >= 0.8 * mx]
    ex = R.choice(cand); g[ex[1]][ex[0]] = 'E'
    jx = None
    if jump:
        cj = [c for c in far if 0.45 * mx <= D[c] <= 0.7 * mx and abs(c[0] - ex[0]) + abs(c[1] - ex[1]) > 8]
        if cj: jx = R.choice(cj); g[jx[1]][jx[0]] = 'X'
    reserved = {(sx, sy), ex} | ({jx} if jx else set())
    def ok_route():
        d = bfs(g, (sx, sy)); return ex in d and (jx is None or jx in d)
    def nb_open(c): return sum(g[c[1] + dy][c[0] + dx] not in '#' for dx, dy in DIRS)
    D = bfs(g, (sx, sy))
    free = lambda: [c for c in D if g[c[1]][c[0]] == '.' and D[c] > 4 and c not in reserved]
    nd = 0; ntw = 0
    treasure = style == 'treasure'
    # treasure alcoves: dead ends guarded by a door (or, on some floors, sealed by trap walls)
    dead = [c for c in free() if nb_open(c) == 1]
    R.shuffle(dead)
    trapw = []
    for c in dead[:8]:
        x, y = c
        for dx, dy in DIRS:
            n = (x + dx, y + dy)
            if g[n[1]][n[0]] == '.' and n not in reserved:
                use_trap = (lvl >= 3 and len(trapw) < 3 and R.random() < 0.35)
                g[n[1]][n[0]] = 'w' if use_trap else 'D'
                if not ok_route() or len(bfs(g, (sx, sy))) < len(D) - 4: g[n[1]][n[0]] = '.'
                else:
                    g[y][x] = 't'
                    if use_trap: trapw.append(n)
                    else: nd += 1
                break
    # trap shortcuts: wall cells between two open cells become trap walls (they vanish when a trap tile is stepped on)
    if lvl >= 3 and not treasure:
        walls = [(x, y) for y in range(2, Hh - 2) for x in range(2, W - 2) if g[y][x] == '#' and
                 ((g[y][x - 1] == '.' and g[y][x + 1] == '.' and g[y - 1][x] == '#' and g[y + 1][x] == '#') or
                  (g[y - 1][x] == '.' and g[y + 1][x] == '.' and g[y][x - 1] == '#' and g[y][x + 1] == '#'))]
        R.shuffle(walls)
        for c in walls[:4 + lvl // 4]: g[c[1]][c[0]] = 'w'; trapw.append(c)
    D = bfs(g, (sx, sy))
    F = free(); R.shuffle(F)
    def take(ch, n, cond=lambda c: True):
        k = 0
        for c in list(F):
            if k >= n: break
            if g[c[1]][c[0]] == '.' and cond(c): g[c[1]][c[0]] = ch; F.remove(c); k += 1
    if trapw:
        take('T', 1 + (lvl >= 10), lambda c: D[c] > 8)
    if treasure:
        take('t', 26 + lvl // 2); take('f', 2); take('p', 1); take('k', nd)
    else:
        take('k', max(2, nd)); take('f', 3 + W // 12); take('p', 2); take('t', 3 + lvl // 4)
        if lvl >= 4: take('z', 2 + lvl // 4, lambda c: nb_open(c) == 2 and D[c] > 6)
        # generators, spaced apart; never allowed to cut the exit route
        gens = []
        for c in list(F):
            if len(gens) >= 4 + lvl // 2 + (W * Hh) // 300: break
            if D[c] < 8 or any(abs(c[0] - a) + abs(c[1] - b) < 5 for a, b in gens) or g[c[1]][c[0]] != '.': continue
            g[c[1]][c[0]] = kinds[len(gens) % len(kinds)]
            if not ok_route(): g[c[1]][c[0]] = '.'; continue
            gens.append(c); F.remove(c)
    g[sy][sx] = 'S'
    assert ok_route(), name
    return g

def emit_meshes(n, g):
    W, Hh = len(g[0]), len(g)
    wall, flo, tw = M(), M(), M()
    def q(m, p, nrm):
        m.add([np.array(v, float) for v in p], [np.array(nrm, float)] * 4, [(0, 0), (1, 0), (1, 1), (0, 1)], [(0, 1, 2), (0, 2, 3)])
    for r, row in enumerate(g):
        y = Hh - 1 - r
        for x, ch in enumerate(row):
            cx, cz = -(x + 0.5), y + 0.5     # world X is mirrored (camera looks +Z)
            if ch in '#w':
                m = wall if ch == '#' else tw
                q(m, [(cx - .5, 1, cz - .5), (cx + .5, 1, cz - .5), (cx + .5, 1, cz + .5), (cx - .5, 1, cz + .5)], (0, 1, 0))
                for dx, dz, nrm in ((1, 0, (-1, 0, 0)), (-1, 0, (1, 0, 0)), (0, 1, (0, 0, 1)), (0, -1, (0, 0, -1))):
                    nx, nr = x + dx, r - dz
                    if 0 <= nx < W and 0 <= nr < Hh:
                        o = g[nr][nx]
                        # solid walls keep faces toward trap walls (exposed once those vanish); trap walls hide faces toward any wall
                        if o == '#' or (ch == 'w' and o == 'w'): continue
                        if ch == 'w' and o == '#': continue
                    else: continue
                    if dz == 0:
                        X = cx - dx * 0.5
                        q(m, [(X, 0, cz - .5), (X, 0, cz + .5), (X, 1, cz + .5), (X, 1, cz - .5)], nrm)
                    else:
                        Z = cz + dz * 0.5
                        q(m, [(cx - .5, 0, Z), (cx + .5, 0, Z), (cx + .5, 1, Z), (cx - .5, 1, Z)], nrm)
            if ch != '#':
                q(flo, [(cx - .5, 0, cz - .5), (cx + .5, 0, cz - .5), (cx + .5, 0, cz + .5), (cx - .5, 0, cz + .5)], (0, 1, 0))
    save(f'lv{n}_wall', wall); save(f'lv{n}_floor', flo)
    has_tw = any('w' in row for row in g)
    if has_tw: save(f'lv{n}_trapw', tw)
    return has_tw

if __name__ == '__main__':
    import glob
    for f in glob.glob(os.path.join(H, '..', 'meshsrc', 'lv*_*.obj')): os.remove(f)
    L = ['------------------------------------------------------------------ levels (generated by tools/levels.py, do not edit)',
         '-- rows: top row = north (highest y). See tools/levels.py for the legend.', 'local LEVELS = {']
    for n, spec in enumerate(SPEC, 1):
        g = make(spec, n)
        name, style, seed, (W, Hh), kinds, anchor, jump, wt, ft, wc, fc = spec
        has_tw = any('w' in row for row in g)
        emit_meshes(n, g)
        L.append('    { name = "%s", style = "%s", w = %d, h = %d, jump = %d, wt = %d, ft = %d, wc = { %.2f, %.2f, %.2f }, fc = { %.2f, %.2f, %.2f }, trapw = %s,%s rows = {'
                 % (name, style, W, Hh, jump, wt, ft, *wc, *fc, 'true' if has_tw else 'false', ' treasure = 30,' if style == 'treasure' else ''))
        for row in g: L.append('        "%s",' % ''.join(row))
        L.append('    } },')
        if '-v' in sys.argv:
            print(name, style, W, Hh, 'gens', sum(c in 'grdls' for r in g for c in r), 'doors', sum(r.count('D') for r in g), 'trapw', sum(r.count('w') for r in g),
                  'stun', sum(r.count('z') for r in g), 'jump', jump)
            print('\n'.join(''.join(r) for r in g))
    L.append('}')
    L.append('G.LEVELS = LEVELS')
    open(os.path.join(H, '..', 'src', '03_levels.lua'), 'w').write('\n'.join(L) + '\n')
    print('levels ok', len(SPEC))
