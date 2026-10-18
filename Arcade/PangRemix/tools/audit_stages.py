#!/usr/bin/env python3
"""Pang Remix stage audit: a faithful port of the player + balloon rules in src/04_sim.lua.
usage: audit_stages.py <stages_dump.json>   (dump written by the game: Save/stages_dump.json, see README/test notes)
For every stage it checks
  * player reachability (walk / fall / ladders, exact 60 Hz step rules) from the spawn point
  * every floor stretch and block top the player should be able to stand on is reachable
  * glass the wire can break (fixpoint), then whether EVERY balloon and all of its children can be hit by the wire
    from some reachable standing spot (exact balloon physics; searches pop moments so the children stay poppable)
"""
import json, sys, math, os
FR = 1 / 60
GRAV, BVX, POPV = 34, 4.8, 9.5
RAD = [None, 0.38, 0.72, 1.35, 2.1]
APEX = [None, 6.5, 10, 14.5, 18.5]
BV = [None] + [math.sqrt(2 * GRAV * (APEX[s] - RAD[s])) for s in range(1, 5)]
PW, PCLIMB, PHW, PH = 9.2, 6.2, 0.5, 2.6
X0, X1, CEIL = -24, 24, 26
ROPE = 0.12
def clamp(v, a, b): return a if v < a else (b if v > b else v)

class Stage:
    def __init__(s, d, broken=()):
        s.n = d['n']; s.lay = d['lay']
        s.blocks = [dict(x0=b[0], y0=b[1], x1=b[0] + b[2], y1=b[1] + b[3], kind=b[4], i=i) for i, b in enumerate(d['b']) if i not in broken]
        s.ladders = [dict(x=l[0], y0=l[1], y1=l[2]) for l in d['l']]
        s.balls = d['balls']
    def support_at(s, x, y, hw, up, down):
        best = 0 if (y <= up and y >= -down) else None
        for b in s.blocks:
            if x + hw > b['x0'] and x - hw < b['x1'] and b['y1'] >= y - down and b['y1'] <= y + up:
                if best is None or abs(b['y1'] - y) < abs(best - y): best = b['y1']
        return best
    def ladder_near(s, x, y, top):
        for l in s.ladders:
            if abs(x - l['x']) < 0.75:
                if top and abs(y - l['y1']) < 0.35: return l
                if not top and abs(y - l['y0']) < 0.35: return l
    # one macro move from a standing state -> standing state (or None)
    def settle(s, x, y):
        s_ = s.support_at(x, y, PHW * 0.5, 0.3, 0.3)
        if s_ is not None: return x, s_
        vy = 0
        for _ in range(2000):
            y0 = y; vy -= 40 * FR; y += vy * FR
            sp = s.support_at(x, (y0 + y) / 2, PHW * 0.5, (y0 - y) / 2 + 0.05, (y0 - y) / 2 + 0.05)
            if sp is not None and sp <= y0 + 0.01 and sp >= y - 0.01: return x, sp
            if y < 0: return x, 0.0
        return x, 0.0
    def walk(s, x, y, h):
        nx = x + h * PW * FR
        for k in s.blocks:
            if k['y0'] < y + PH - 0.2 and k['y1'] > y + 0.15:
                if h > 0 and x + PHW <= k['x0'] + 0.01 and nx + PHW > k['x0']: nx = k['x0'] - PHW
                if h < 0 and x - PHW >= k['x1'] - 0.01 and nx - PHW < k['x1']: nx = k['x1'] + PHW
        nx = clamp(nx, X0 + PHW, X1 - PHW)
        return s.settle(nx, y)
    def climb(s, x, y, v):
        l = s.ladder_near(x, y, v < 0) if True else None
        if not l: return None
        x = l['x']
        for _ in range(4000):
            y += v * PCLIMB * FR
            if y >= l['y1']: return s.settle(x, l['y1'])
            if y <= l['y0']: return s.settle(x, l['y0'])
        return None
    def spawn(s):
        sx = 0.0                                  # same rule as stage_reset in src/04_sim.lua
        if os.environ.get('AUDIT_OLD_SPAWN'): return 0.0, 0.0   # pre-fix rule: always the centre
        for k in s.blocks:
            if k['y0'] < PH - 0.2 and sx + PHW > k['x0'] and sx - PHW < k['x1']: sx = k['x1'] + PHW + 0.6
        return sx, 0.0
    def graph(s, start=None):
        """standing spots reachable from the spawn and the moves between them (directed: drops are one-way)"""
        x, y = s.settle(*(start or s.spawn()))
        key = lambda p: (round(p[0], 3), round(p[1], 3))
        k0 = key((x, y)); pos = {k0: (x, y)}; E = {k0: set()}; todo = [k0]
        while todo:
            k = todo.pop(); x, y = pos[k]
            for p in (s.walk(x, y, 1), s.walk(x, y, -1), s.climb(x, y, 1), s.climb(x, y, -1)):
                if p is None: continue
                kk = key(p)
                if kk != k: E[k].add(kk)
                if kk not in pos: pos[kk] = p; E[kk] = set(); todo.append(kk)
        return k0, pos, E
    def regions(s, start=None):
        """the closed regions the player can end up locked into (sink SCCs of the move graph)"""
        k0, pos, E = s.graph(start)
        idx, low, on, st, comp, out = {}, {}, set(), [], {}, []
        sys.setrecursionlimit(100000)
        def tarjan(v):
            idx[v] = low[v] = len(idx); st.append(v); on.add(v)
            for w in E[v]:
                if w not in idx: tarjan(w); low[v] = min(low[v], low[w])
                elif w in on: low[v] = min(low[v], idx[w])
            if low[v] == idx[v]:
                c = []
                while True:
                    w = st.pop(); on.discard(w); comp[w] = len(out); c.append(w)
                    if w == v: break
                out.append(c)
        for v in pos:
            if v not in idx: tarjan(v)
        sinks = []
        for ci, c in enumerate(out):
            if all(comp[w] == ci for v in c for w in E[v]): sinks.append([pos[v] for v in c])
        return sinks, list(pos.values())
    def reach(s, start=None):
        x, y = s.settle(*(start or s.spawn()))
        key = lambda p: (round(p[0], 3), round(p[1], 3))
        seen = {key((x, y)): (x, y)}; todo = [(x, y)]
        while todo:
            x, y = todo.pop()
            nxt = [s.walk(x, y, 1), s.walk(x, y, -1), s.climb(x, y, 1), s.climb(x, y, -1)]
            for p in nxt:
                if p is None: continue
                k = key(p)
                if k not in seen: seen[k] = p; todo.append(p)
        return list(seen.values())
    def rope_stop(s, x, y):
        stop, hit = CEIL, None
        for k in s.blocks:
            if x > k['x0'] - 0.05 and x < k['x1'] + 0.05 and y < k['y0'] and k['y0'] < stop: stop, hit = k['y0'], k
        return stop, hit
    def ball_step(s, b):
        b[3] -= GRAV * FR
        b[1] += b[2] * FR; b[0] = b[0]
        x, y, vx, vy, sz = b[0] + b[2] * FR, b[1], b[2], b[3], b[4]
        # note: keep the same order as the Lua (x then y integrate, walls, ceiling, floor, blocks)
        return
def sim_ball(st, sz, x, y, vx, vy):
    """yields (x, y) after each 60 Hz step, exact port of ball_step"""
    r = RAD[sz]
    while True:
        vy -= GRAV * FR
        x += vx * FR; y += vy * FR
        if x - r < X0: x = X0 + r; vx = abs(vx)
        if x + r > X1: x = X1 - r; vx = -abs(vx)
        if y + r > CEIL: y = CEIL - r; vy = -abs(vy)
        if y - r < 0: y = r; vy = BV[sz]
        for k in st.blocks:
            px, py = clamp(x, k['x0'], k['x1']), clamp(y, k['y0'], k['y1'])
            dx, dy = x - px, y - py
            if dx * dx + dy * dy < r * r:
                if abs(dy) >= abs(dx):
                    if dy > 0 or (dy == 0 and y > (k['y0'] + k['y1']) / 2): y = k['y1'] + r; vy = BV[sz]
                    else: y = k['y0'] - r; vy = -abs(vy)
                else:
                    if dx > 0: x = k['x1'] + r; vx = abs(vx)
                    else: x = k['x0'] - r; vx = -abs(vx)
        yield x, y, vx, vy

class Hitter:
    def __init__(s, st, spots):
        s.ints = []                     # (px, py, stop)
        for px, py in spots: s.ints.append((px, py, st.rope_stop(px, py)[0]))
        s.ints.sort()
        s.xs = [i[0] for i in s.ints]
    def can_hit(s, bx, by, r):
        import bisect
        rad = r + ROPE
        lo = bisect.bisect_left(s.xs, bx - rad); hi = bisect.bisect_right(s.xs, bx + rad)
        for px, py, stop in s.ints[lo:hi]:
            cy = clamp(by, py, stop); dx, dy = bx - px, by - cy
            if dx * dx + dy * dy < rad * rad: return True
        return False

def can_clear(st, H, sz, x, y, vx, vy, memo, tmax=30.0, tries=10):
    k = (sz, round(x, 1), round(y, 1), round(vx, 1), round(vy, 1))
    if k in memo: return memo[k]
    memo[k] = False
    g = sim_ball(st, sz, x, y, vx, vy); last = -999; n = 0
    for f in range(int(tmax / FR)):
        bx, by, bvx, bvy = next(g)
        if f - last < 20 or not H.can_hit(bx, by, RAD[sz]): continue
        last = f; n += 1
        if sz == 1: memo[k] = True; return True
        c = sz - 1; cy = max(by, RAD[c] + 0.05)
        if can_clear(st, H, c, bx - RAD[c] * 0.5, cy, -BVX, POPV, memo) and can_clear(st, H, c, bx + RAD[c] * 0.5, cy, BVX, POPV, memo):
            memo[k] = True; return True
        if n >= tries: break
    return False

def floor_and_tops(st):
    """standing surfaces the player should be able to use: free floor stretches and block tops (x-intervals)"""
    surf = []
    xs = sorted({X0 + PHW, X1 - PHW} | {k['x0'] - PHW for k in st.blocks if k['y0'] < PH - 0.2} | {k['x1'] + PHW for k in st.blocks if k['y0'] < PH - 0.2})
    # free floor: split by blocks that stand on/near the floor and block walking
    walls = sorted([(k['x0'], k['x1']) for k in st.blocks if k['y0'] < PH - 0.2 and k['y1'] > 0.15])
    a = X0 + PHW
    for w0, w1 in walls:
        if w0 - PHW > a: surf.append(('floor', a, w0 - PHW, 0.0))
        a = max(a, w1 + PHW)
    if X1 - PHW > a: surf.append(('floor', a, X1 - PHW, 0.0))
    for k in st.blocks:
        covered = any(o is not k and o['y0'] <= k['y1'] + 0.01 and o['y0'] >= k['y1'] - 0.01 and o['x0'] <= k['x0'] and o['x1'] >= k['x1'] for o in st.blocks)
        if not covered and k['y1'] + PH < CEIL: surf.append(('top#%d%s' % (k['i'], k['kind']), k['x0'], k['x1'], k['y1']))
    return surf

def audit(d):
    st0 = Stage(d)
    res = {'n': d['n'], 'lay': d['lay'], 'issues': []}
    sinks, allr = st0.regions()
    big = [r for r in sinks if len(r) > 3]
    if len(big) > 1:
        res['issues'].append('player can get locked into %d separate regions: %s' % (len(big), '; '.join(
            'x[%.1f..%.1f]' % (min(p[0] for p in r), max(p[0] for p in r)) for r in big)))
    # glass the wire can break from a reachable spot (fixpoint)
    broken = set()
    while True:
        st = Stage(d, broken); R = st.reach() + allr
        new = {st.rope_stop(px, py)[1]['i'] for px, py in R if st.rope_stop(px, py)[1] and st.rope_stop(px, py)[1]['kind'] != 's'}
        if not new - broken: break
        broken |= new
    stB = Stage(d, broken)
    # surfaces the player must be able to use: every free floor stretch + every block top a ladder leads to
    lad_tops = {(l['x'], l['y1']) for l in st0.ladders}
    for name, a, b, h in floor_and_tops(st0):
        if b - a < 0.3: continue
        if name != 'floor' and not any(a <= lx <= b and abs(ly - h) < 0.36 for lx, ly in lad_tops):
            continue                                  # decorative / balloon-only block (no ladder meant to reach it)
        for r in (big or sinks):
            hit = [x for x, y in r if abs(y - h) < 0.05 and a - 0.05 <= x <= b + 0.05]
            cov = (max(hit) - min(hit)) / max(b - a, 1e-6) if hit else 0
            if cov < 0.8:
                res['issues'].append('%s x[%.1f..%.1f] y=%.0f %s' % (name, a, b, h, 'UNREACHABLE' if not hit else 'only %.0f%% reachable' % (cov * 100)))
                break
    for l in st0.ladders:
        if not any(abs(x - l['x']) < 0.01 and abs(y - l['y1']) < 0.01 for x, y in allr):
            res['issues'].append('ladder x=%g: cannot step off at its top y=%g' % (l['x'], l['y1']))
    # balloons: must be clearable from EVERY region the player can end up locked into
    per = []
    for sz, bx, dirn in d['balls']:
        y = 18 if sz == 4 else 16
        for k in st0.blocks:
            px, py = clamp(bx, k['x0'], k['x1']), clamp(y, k['y0'], k['y1'])
            if (bx - px) ** 2 + (y - py) ** 2 < (RAD[sz] + 0.3) ** 2: y = 22.5
        good = True
        for r in (big or sinks):
            ok = False
            for stg in (stB, st0):
                if can_clear(stg, Hitter(stg, r), sz, bx, y, dirn * BVX, 0, {}): ok = True; break
            if not ok: good = False
        per.append('size%d@%g:%s' % (sz, bx, 'ok' if good else 'TRAPPED'))
        if not good: res['issues'].append('balloon size %d from x=%g (or its children) cannot all be hit from every region' % (sz, bx))
    # robustness: a balloon of ANY size, anywhere it can end up (sweep of start points and directions), must become
    # hittable within 20 s from every region; otherwise an unlucky pop could leave it trapped (soft-lock)
    traps = []
    for r in (big or sinks):
        H = Hitter(st0, r)
        for sz in (1, 2, 3, 4):
            for x0 in range(-23, 24):
                for y0 in (RAD[sz] + 0.05, 4.0, 9.0, 15.0):
                    if y0 + RAD[sz] > CEIL: continue
                    if any(k['x0'] - RAD[sz] < x0 < k['x1'] + RAD[sz] and k['y0'] - RAD[sz] < y0 < k['y1'] + RAD[sz] for k in st0.blocks): continue
                    for dirn in (-1, 1):
                        g = sim_ball(st0, sz, x0, y0, dirn * BVX, POPV); hit = False
                        for f in range(int(20 / FR)):
                            bx, by, _, _ = next(g)
                            if H.can_hit(bx, by, RAD[sz]): hit = True; break
                        if not hit: traps.append((sz, x0, y0))
    if traps:
        ex = sorted({(t[0], t[1]) for t in traps})
        res['issues'].append('%d balloon start states never become hittable, e.g. %s' % (len(traps), ', '.join('size%d@x%d' % e for e in ex[:6])))
    res['balls'] = per; res['broken_glass'] = sorted(broken); res['regions'] = len(big)
    res['pass'] = not res['issues']
    return res

if __name__ == '__main__':
    D = json.load(open(sys.argv[1]))
    only = set(int(a) for a in sys.argv[2:])
    npass = 0
    for d in D:
        if only and d['n'] not in only: continue
        r = audit(d); npass += r['pass']
        print('stage %2d  layout %2d  %s  %s%s' % (r['n'], r['lay'], 'PASS' if r['pass'] else 'FAIL', ' '.join(r['balls']),
              ('\n      - ' + '\n      - '.join(r['issues'])) if r['issues'] else ''))
    print('%d/%d stages pass' % (npass, len(D) if not only else len(only)))
