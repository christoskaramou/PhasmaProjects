# Marble Madness Remix courses: a small DSL rasterised to per-cell corner heights.
# Writes meshsrc/c<n>_topA/topB/goal/wall.obj (tiled tops, cliff walls) and src/03_courses.lua (physics data).
# Grid: cell (i, j) covers x in [i, i+1], z in [j, j+1]. Courses run from far (high z, start) to near (low z, goal).
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from meshlib import *
H = os.path.dirname(os.path.abspath(__file__))

class Course:
    def __init__(s, name, nx, nz, time):
        s.name, s.nx, s.nz, s.time = name, nx, nz, time
        s.cells = {}          # (i, j) -> [h00, h10, h01, h11, colour]
        s.enemies, s.checks = [], []
        s.start = None; s.goal = None; s.gravity = 1
    def _rect(s, x0, z0, x1, z1):
        for j in range(int(z0), int(z1)):
            for i in range(int(x0), int(x1)):
                if 0 <= i < s.nx and 0 <= j < s.nz: yield i, j
    def put(s, x0, z0, x1, z1, fn, c):
        for i, j in s._rect(x0, z0, x1, z1):
            s.cells[(i, j)] = [round(fn(i, j), 3), round(fn(i + 1, j), 3), round(fn(i, j + 1), 3), round(fn(i + 1, j + 1), 3), c]
    def F(s, x0, z0, x1, z1, h, c='A'): s.put(x0, z0, x1, z1, lambda x, z: h, c)
    def R(s, x0, z0, x1, z1, h0, h1, axis='z', c='B', bump=0.0, per=4.0):
        def fn(x, z):
            if axis == 'z': t = (z1 - z) / (z1 - z0)
            elif axis == 'x+': t = (x - x0) / (x1 - x0)
            else: t = (x1 - x) / (x1 - x0)
            b = bump * math.sin(2 * math.pi * (z if axis == 'z' else x) / per) if bump else 0
            return h0 + (h1 - h0) * t + b
        s.put(x0, z0, x1, z1, fn, c)
    def Fn(s, x0, z0, x1, z1, hrim, hc, cx, cz, c='B'):
        rad = max(x1 - x0, z1 - z0) / 2
        s.put(x0, z0, x1, z1, lambda x, z: hc + (hrim - hc) * min(1.0, math.hypot(x - cx, z - cz) / rad), c)
    def W(s, x0, z0, x1, z1, h, amp, per=3.0, c='B'):
        s.put(x0, z0, x1, z1, lambda x, z: h + amp * math.sin(2 * math.pi * x / per) * math.sin(2 * math.pi * z / per), c)
    def V(s, x0, z0, x1, z1):
        for k in list(s._rect(x0, z0, x1, z1)): s.cells.pop(k, None)
    def Rail(s, x0, z0, x1, z1, dh):
        for k in s._rect(x0, z0, x1, z1):
            if k in s.cells:
                c = s.cells[k]; s.cells[k] = [c[0] + dh, c[1] + dh, c[2] + dh, c[3] + dh, 'W']
    def G(s, x0, z0, x1, z1):
        s.goal = (x0, z0, x1, z1)
        for k in s._rect(x0, z0, x1, z1):
            if k in s.cells: s.cells[k][4] = 'G'
    def h_at(s, x, z):
        c = s.cells.get((int(math.floor(x)), int(math.floor(z))))
        if not c: return None
        fx, fz = x - math.floor(x), z - math.floor(z)
        return (c[0] * (1 - fx) + c[1] * fx) * (1 - fz) + (c[2] * (1 - fx) + c[3] * fx) * fz

C = []
# ---------------------------------------------------------------- 1 Practice Race
c = Course('Practice Race', 24, 64, 60)
c.F(14, 54, 20, 62, 20, 'A'); c.start = (17, 59)
c.R(14, 44, 20, 54, 20, 15, 'z', 'B')
c.F(14, 38, 20, 44, 15, 'A'); c.Rail(14, 38, 20, 39, 0.8); c.Rail(19, 39, 20, 44, 0.8)
c.R(8, 38, 14, 44, 15, 12.5, 'x-', 'B')
c.F(2, 38, 8, 44, 12.5, 'A')
c.R(2, 26, 8, 38, 12.5, 8, 'z', 'B', 0.3, 4)
c.F(2, 20, 8, 26, 8, 'A')
c.R(8, 20, 14, 26, 8, 6, 'x+', 'B')
c.F(14, 20, 20, 26, 6, 'A')
c.R(14, 10, 20, 20, 6, 3, 'z', 'B')
c.F(14, 3, 20, 10, 3, 'A'); c.G(15, 3, 19, 7)
c.checks = [(17, 59), (17, 41), (5, 41), (5, 23), (17, 23), (17, 12)]
C.append(c)
# ---------------------------------------------------------------- 2 Beginner Race
c = Course('Beginner Race', 28, 72, 60)
c.F(11, 64, 17, 70, 25, 'A'); c.start = (14, 67)
c.Fn(4, 46, 24, 64, 24, 19.5, 14, 47, 'B')
c.R(12, 36, 16, 46, 19.5, 17, 'z', 'A')
c.F(5, 26, 23, 36, 17, 'B')
c.Rail(9, 30, 10, 32, 1.2); c.Rail(18, 29, 19, 31, 1.2)
c.F(5, 20, 23, 26, 15, 'A')
c.R(5, 10, 23, 20, 15, 10, 'z', 'B', 0.35, 5)
c.Fn(8, 2, 20, 10, 10, 8, 14, 3, 'A')
c.F(11, 0, 17, 3, 8, 'A'); c.G(11, 0, 17, 3)
c.enemies = [('steelie', 18.5, 32.0), ('steelie', 8.5, 15.0)]
c.checks = [(14, 67), (14, 41), (14, 31), (14, 23), (14, 13), (14, 5)]
C.append(c)
# ---------------------------------------------------------------- 3 Intermediate Race
c = Course('Intermediate Race', 28, 74, 40)
c.F(3, 66, 10, 72, 28, 'A'); c.start = (6.5, 69)
c.R(4, 56, 9, 66, 28, 24, 'z', 'B')
c.F(2, 44, 24, 56, 24, 'A')
c.R(18, 34, 24, 44, 24, 21, 'z', 'B')
c.F(12, 28, 26, 34, 21, 'A')
c.W(2, 28, 12, 34, 20, 0.5, 6, 'B'); c.R(2, 28, 12, 34, 21, 18.5, 'x-', 'B', 0.3, 3)
c.F(2, 16, 8, 28, 18.5, 'A')
c.R(8, 16, 22, 22, 18.5, 15, 'x+', 'B')
c.F(18, 10, 26, 16, 15, 'A'); c.F(18, 16, 26, 22, 15, 'A')
c.R(18, 4, 26, 10, 15, 13, 'z', 'B')
c.F(18, 0, 26, 4, 13, 'A'); c.G(19, 0, 25, 4)
c.enemies = [('acid', [(4, 50), (20, 50)], 2.2), ('acid', [(22, 46), (6, 54)], 1.8), ('muncher', 5.0, 21.0), ('muncher', 21.0, 13.0)]
c.checks = [(6.5, 69), (6.5, 52), (21, 40), (19, 31), (5, 22), (22, 18), (22, 6)]
C.append(c)
# ---------------------------------------------------------------- 4 Aerial Race
c = Course('Aerial Race', 28, 76, 40)
c.F(12, 68, 17, 74, 30, 'A'); c.start = (14.5, 71)
c.R(13, 58, 16, 68, 30, 27, 'z', 'B')
c.F(13, 54, 16, 58, 27, 'A')
c.R(5, 54, 13, 57, 27, 25, 'x-', 'B')
c.F(3, 50, 8, 57, 25, 'A')
c.R(4, 40, 7, 50, 25, 23, 'z', 'B')
c.F(4, 36, 7, 40, 21, 'A')
c.R(7, 36, 20, 39, 21, 19, 'x+', 'B')
c.F(20, 32, 24, 40, 19, 'A')
c.R(21, 22, 23, 32, 19, 17, 'z', 'B')
c.F(19, 18, 25, 22, 16, 'A')
c.R(9, 18, 19, 20, 16, 14, 'x-', 'B')
c.F(5, 12, 10, 20, 13, 'A')
c.R(6, 4, 9, 12, 13, 11, 'z', 'B')
c.F(4, 0, 11, 4, 11, 'A'); c.G(5, 0, 10, 4)
c.enemies = [('steelie', 22.0, 36.0), ('muncher', 7.0, 15.0)]
c.checks = [(14.5, 71), (14.5, 56), (5.5, 53), (5.5, 38), (22, 36), (22, 20), (7.5, 16), (7.5, 2)]
C.append(c)
# ---------------------------------------------------------------- 5 Silly Race: gravity is reversed, so the marble rolls uphill
c = Course('Silly Race', 26, 66, 35)
c.gravity = -1
c.F(9, 58, 16, 64, 6, 'A'); c.start = (12.5, 61)
c.R(9, 46, 16, 58, 6, 11, 'z', 'B')
c.F(9, 40, 16, 46, 11, 'A'); c.Rail(9, 40, 16, 41, 0.8); c.Rail(15, 41, 16, 46, 0.8)
c.R(3, 40, 9, 46, 11, 14, 'x-', 'B')
c.F(1, 32, 7, 46, 14, 'A'); c.F(1, 40, 3, 46, 14, 'A')
c.R(1, 22, 7, 32, 14, 18, 'z', 'B', 0.3, 4)
c.F(1, 16, 13, 22, 18, 'A')
c.R(13, 16, 19, 22, 18, 21, 'x+', 'B')
c.F(17, 10, 24, 22, 21, 'A')
c.R(17, 4, 24, 10, 21, 23, 'z', 'B')
c.F(17, 0, 24, 4, 23, 'A'); c.G(18, 0, 23, 4)
c.enemies = [('steelie', 4.0, 36.0), ('steelie', 20.0, 14.0)]
c.checks = [(12.5, 61), (12.5, 43), (4, 43), (4, 27), (8, 19), (20, 18), (20, 6)]
C.append(c)
# ---------------------------------------------------------------- 6 Ultimate Race
c = Course('Ultimate Race', 28, 80, 35)
c.F(11, 72, 17, 78, 34, 'A'); c.start = (14, 75)
c.R(12, 62, 16, 72, 34, 30, 'z', 'B')
c.F(10, 56, 18, 62, 30, 'A')
c.R(12, 46, 15, 56, 30, 27, 'z', 'B')
c.W(4, 36, 24, 46, 26, 0.6, 6, 'A')
c.R(18, 26, 21, 36, 26, 23, 'z', 'B')
c.F(16, 20, 23, 26, 23, 'A')
c.R(6, 21, 16, 24, 23, 21, 'x-', 'B')
c.F(3, 14, 8, 24, 21, 'A')
c.R(4, 6, 7, 14, 21, 18, 'z', 'B')
c.F(2, 0, 9, 6, 18, 'A'); c.G(3, 0, 8, 4)
c.enemies = [('hammer', 13.5, 51.0, 2.4, 0.0), ('hammer', 19.5, 31.0, 2.2, 1.1), ('acid', [(6, 41), (22, 41)], 2.6), ('muncher', 19.0, 23.0),
             ('muncher', 5.5, 18.0), ('steelie', 14.0, 59.0), ('hammer', 5.5, 10.0, 2.0, 0.5)]
c.checks = [(14, 75), (14, 59), (13.5, 41), (19.5, 23), (5.5, 19), (5.5, 3)]
C.append(c)

# ---------------------------------------------------------------- mesh + Lua export
def tile_quad(m, p, uv=((0, 0), (1, 0), (1, 1), (0, 1))):
    P = [np.array(q, float) for q in p]
    n = np.cross(P[2] - P[0], P[1] - P[0]); ln = np.linalg.norm(n)
    if ln < 1e-9: return
    n /= ln
    if n[1] < 0 and abs(n[1]) > 0.5: n = -n
    m.add(P, [n] * 4, list(uv), [(0, 1, 2), (0, 2, 3)])
def wall_quad(m, a, b, out):
    # a, b: (x, ytop, ybot, z) at the two ends of a cell edge; out: outward normal (x, z)
    (x0, t0, b0, z0), (x1, t1, b1, z1) = a, b
    n = np.array([out[0], 0.0, out[1]])
    P = [np.array([x0, b0, z0]), np.array([x1, b1, z1]), np.array([x1, t1, z1]), np.array([x0, t0, z0])]
    h = max(t0 - b0, t1 - b1, 0.01)
    uv = [(0, 0), (1, 0), (1, (t1 - b1) / 1.0), (0, (t0 - b0) / 1.0)]
    tris = []
    if t0 - b0 > 1e-4 or t1 - b1 > 1e-4:
        if t1 - b1 > 1e-4: tris.append((0, 1, 2))
        if t0 - b0 > 1e-4: tris.append((0, 2, 3))
        m.add(P, [n] * 4, uv, tris)
def build(ci, c):
    tops = {}
    wall = M()
    lo = min(min(v[:4]) for v in c.cells.values()) - 6
    for (i, j), v in c.cells.items():
        h00, h10, h01, h11, col = v
        # slope shading class (like the arcade's iso shading): 0 flat, 1 falls toward the camera (-z), 2 falls sideways, 3 falls away
        gx = ((h10 - h00) + (h11 - h01)) / 2; gz = ((h01 - h00) + (h11 - h10)) / 2
        if col == 'G' or abs(gx) + abs(gz) < 0.06: sc = ''
        elif abs(gz) >= abs(gx): sc = '1' if gz > 0 else '3'
        else: sc = '2'
        key = col + sc
        if key not in tops: tops[key] = M()
        tile_quad(tops[key], [(i, h00, j), (i + 1, h10, j), (i + 1, h11, j + 1), (i, h01, j + 1)])
        # edges: (neighbour offset, my two corner heights, neighbour's matching corner heights, endpoints, outward)
        E = [((0, -1), (h00, h10), (2, 3), ((i, j), (i + 1, j)), (0, -1)),
             ((0, 1), (h01, h11), (0, 1), ((i, j + 1), (i + 1, j + 1)), (0, 1)),
             ((-1, 0), (h00, h01), (1, 3), ((i, j), (i, j + 1)), (-1, 0)),
             ((1, 0), (h10, h11), (0, 2), ((i + 1, j), (i + 1, j + 1)), (1, 0))]
        for d, mine, nidx, ends, out in E:
            nb = c.cells.get((i + d[0], j + d[1]))
            b0 = nb[nidx[0]] if nb else lo; b1 = nb[nidx[1]] if nb else lo
            t0, t1 = mine
            if t0 > b0 + 1e-3 or t1 > b1 + 1e-3:
                (xa, za), (xb, zb) = ends
                wall_quad(wall, (xa, t0, min(b0, t0), za), (xb, t1, min(b1, t1), zb), out)
    names = []
    for k, m in tops.items():
        if m.V: save(f'c{ci}_top{k}', m); names.append(f'c{ci}_top{k}')
    save(f'c{ci}_wall', wall); names.append(f'c{ci}_wall')
    return names
def lua_export():
    L = ['------------------------------------------------------------------ courses (generated by tools/courses.py, do not edit)', 'local COURSES = {']
    for ci, c in enumerate(C, 1):
        rows = []
        for j in range(c.nz):
            cells = []
            for i in range(c.nx):
                v = c.cells.get((i, j))
                cells.append('x' if not v else '%g,%g,%g,%g' % tuple(v[:4]))
            rows.append('"' + ';'.join(cells) + '"')
        en = []
        for e in c.enemies:
            if e[0] == 'acid': en.append('{ k = "acid", path = { %s }, v = %g }' % (', '.join('{ %g, %g }' % p for p in e[1]), e[2]))
            elif e[0] == 'hammer': en.append('{ k = "hammer", x = %g, z = %g, per = %g, ph = %g }' % e[1:])
            else: en.append('{ k = "%s", x = %g, z = %g }' % e)
        L.append('    { name = "%s", nx = %d, nz = %d, time = %d, gravity = %d, start = { %g, %g }, goal = { %g, %g, %g, %g },' % (
            c.name, c.nx, c.nz, c.time, c.gravity, c.start[0], c.start[1], *c.goal))
        L.append('      checks = { %s },' % ', '.join('{ %g, %g }' % p for p in c.checks))
        L.append('      enemies = { %s },' % ', '.join(en))
        L.append('      meshes = { %s },' % ', '.join('"%s"' % n for n in c.meshes))
        L.append('      rows = {\n        ' + ',\n        '.join(rows) + ' } },')
    L.append('}')
    L.append('G.COURSES = COURSES')
    open(os.path.join(H, '..', 'src', '03_courses.lua'), 'w').write('\n'.join(L) + '\n')
for ci, c in enumerate(C, 1):
    c.meshes = build(ci, c)
    # sanity: start, checks and goal must be on solid ground
    for p in [c.start] + c.checks: assert c.h_at(*p) is not None, (c.name, p)
lua_export()
print('courses ok', [len(c.cells) for c in C])
