"""The near sea tile, shared by the Blender target (scene.py) and the engine mesh (gen_assets.py).

One tile covers pattern x in [0, SEA_P] and y in SEA_NEAR_Y; its vertices are the Gerstner pattern (uw_common.sea_point)
and its vertex colours paint the troughs dark, the backs lighter and the crests with foam. They belong to the pattern,
so they ride with the swells when the tile slides along x. Plain Python (Blender imports it too).
Coordinates here are Blender's (x along the harbour, y depth, z up).
"""
import math

import uw_common as U

NX = 192                  # columns per tile (0.25 units)

# Display-space (sRGB) colours: the engine multiplies the vertex colour into the base colour as sRGB.
TROUGH = (0.030, 0.062, 0.058)
BACK = (0.105, 0.190, 0.170)
FOAM = (0.80, 0.86, 0.86)
FAR = (0.040, 0.075, 0.070)       # the flat far plane, and what the tile fades to at its far edge


def rows():
    """Row y positions: dense near the camera, coarser with distance."""
    out, y = [], U.SEA_NEAR_Y[0]
    while y < U.SEA_NEAR_Y[1]:
        out.append(y)
        y += 0.16 + 0.03 * max(0.0, y + 6)
    out.append(U.SEA_NEAR_Y[1])
    return out


def _smooth(e0, e1, v):
    t = min(1.0, max(0.0, (v - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def colour(h, jac, y):
    hn = h / U.AMP
    b = _smooth(-0.55, 0.65, hn)
    c = [TROUGH[i] + (BACK[i] - TROUGH[i]) * b for i in range(3)]
    foam = _smooth(0.16, 0.50, hn) * _smooth(1.05, 0.55, jac)
    c = [c[i] + (FOAM[i] - c[i]) * foam for i in range(3)]
    far = _smooth(U.SEA_FADE_Y[0] - 6, U.SEA_NEAR_Y[1], y)
    return tuple(c[i] + (FAR[i] - c[i]) * far for i in range(3))


NEAR_TILT, NEAR_TILT_Y = 0.09, (0.0, 16.0)     # slope toward the camera, full up to y 0, none from y 16 (8-28 dimmed B's mid sea, 21:5x)


def tile(world_uv=True):
    """Returns (verts, normals, colours, uvs, quads) for one tile with its origin at pattern x = 0. world_uv: v from
    uw_common.ripple_v (the game's depth-mapped ripple maps); False: v repeats every RIPPLE_P (the Blender target)."""
    R = rows()
    V, C, T = [], [], []
    for y in R:
        for i in range(NX + 1):
            x = U.SEA_P * i / NX
            px, py, pz, jac = U.sea_point(x, y)
            V.append((px, py, pz))
            C.append(colour(pz, jac, y))
            T.append((x / U.RIPPLE_P, U.ripple_v(y) if world_uv else (y - U.SEA_NEAR_Y[0]) / U.RIPPLE_P))
    Q = []
    for j in range(len(R) - 1):
        for i in range(NX):
            a = j * (NX + 1) + i
            Q.append((a, a + 1, a + NX + 2, a + NX + 1))
    # smooth normals; the first and last columns share the neighbour across the seam (tile is periodic in x)
    N = [[0.0, 0.0, 0.0] for _ in V]
    for a, b, c, d in Q:
        for (p, q, r) in ((a, b, c), (a, c, d)):
            u = [V[q][k] - V[p][k] for k in range(3)]
            w = [V[r][k] - V[p][k] for k in range(3)]
            n = (u[1] * w[2] - u[2] * w[1], u[2] * w[0] - u[0] * w[2], u[0] * w[1] - u[1] * w[0])
            for idx in (p, q, r):
                for k in range(3):
                    N[idx][k] += n[k]
    for j in range(len(R)):
        a, b = j * (NX + 1), j * (NX + 1) + NX
        s = [N[a][k] + N[b][k] for k in range(3)]
        N[a], N[b] = list(s), list(s)
    for i, n in enumerate(N):
        L = math.sqrt(sum(v * v for v in n)) or 1.0
        for k in range(3):
            n[k] /= L
        # Tilt the near water's normals toward the camera (-y): flat water's mirror moves off the bright horizon band
        # onto darker sky (dark water, warm dashes where ripples face away). Faded out by mid sea, where the ripples
        # average out in the mipmaps and the tilt alone darkened the glitter (it was in the normal maps: 21:5x, live).
        w = min(1.0, max(0.0, (NEAR_TILT_Y[1] - V[i][1]) / (NEAR_TILT_Y[1] - NEAR_TILT_Y[0])))
        n[1] -= NEAR_TILT * w * n[2]
        L = math.sqrt(sum(v * v for v in n)) or 1.0
        for k in range(3):
            n[k] /= L
    return V, N, C, T, Q
