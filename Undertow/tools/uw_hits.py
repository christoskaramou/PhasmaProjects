"""Hit shapes for the rules, cut from the same meshes the game draws (.concepts/next/undertow/layers/pieces/*.obj, the
files gen_assets.py cooks). numpy only.

The float is a sphere of radius FLOAT_R moving in the plane y = 0. A piece placed at (ox, oy, oz) can only touch it with
geometry whose world |y| < FLOAT_R. Every mesh triangle is sampled densely; samples inside that slab are binned into an
x-z grid (HIT_CELL) relative to the piece origin, keeping the smallest |y| per cell. The rules hit test is then exact to a
cell: the float at (x, z) touches cell (cx, cz, y) when (cx - x)^2 + (cz - z)^2 < FLOAT_R^2 - y^2.

PLACEMENTS: how each kind stands relative to the play plane (y offset, yaw) - the same numbers the course and the view
use. Buoy grids are in the buoy's untilted frame (the rules undo its pitch, as the view applies it).
"""
import math
import os

import numpy as np

import uw_common as U

HERE = os.path.dirname(os.path.abspath(__file__))
PCS = os.path.normpath(os.path.join(HERE, "..", "..", ".concepts", "next", "undertow", "layers", "pieces"))

PLACEMENTS = {
    "buoy_red": ("buoy_red", U.BUOY_BACK, 0),
    "buoy_white": ("buoy_white", U.BUOY_BACK, 0),
    "pier": ("pier", U.PIER_Y, 0),
    "boat_0": ("boat", U.BOAT_IN_Y, 0),
    "boat_180": ("boat", U.BOAT_IN_Y, 180),
    "bw_gap": ("bw_gap", U.GAP_IN_Y, 0),
}
STEP = 0.02               # sample spacing on the triangles (units)


def read_obj(name):
    """Vertices in Blender local axes (x, y, z) and triangles of a piece OBJ (written in engine axes)."""
    V, F = [], []
    with open(os.path.join(PCS, name + ".obj")) as fi:
        for line in fi:
            if line.startswith("v "):
                X, Y, Z = map(float, line.split()[1:4])
                V.append((X, -Z, Y))
            elif line.startswith("f "):
                idx = [int(t.split("/")[0]) - 1 for t in line.split()[1:]]
                for k in range(1, len(idx) - 1):
                    F.append((idx[0], idx[k], idx[k + 1]))
    return np.array(V, float), np.array(F, int)


def placed(V, oy, yaw):
    """Piece-local vertices -> offsets from the piece origin in world axes (yaw 0 or 180 about z)."""
    W = V.copy()
    if yaw == 180:
        W[:, 0], W[:, 1] = -V[:, 0], -V[:, 1]
    W[:, 1] += oy
    return W


def samples(W, F):
    """Dense samples on every triangle that reaches the slab |y| < FLOAT_R."""
    R = U.FLOAT_R
    out = []
    for a, b, c in F:
        P = W[[a, b, c]]
        if P[:, 1].min() >= R or P[:, 1].max() <= -R:
            continue
        L = max(np.linalg.norm(P[0] - P[1]), np.linalg.norm(P[1] - P[2]), np.linalg.norm(P[2] - P[0]))
        n = max(1, int(math.ceil(L / STEP)))
        i, j = np.mgrid[0:n + 1, 0:n + 1]
        keep = i + j <= n
        u, v = i[keep] / n, j[keep] / n
        pts = P[0] + np.outer(u, P[1] - P[0]) + np.outer(v, P[2] - P[0])
        out.append(pts[np.abs(pts[:, 1]) < R])
    return np.concatenate(out) if out else np.zeros((0, 3))


def grid(kind):
    """{(ix, iz): min |y|} for a placement, plus the samples it came from."""
    name, oy, yaw = PLACEMENTS[kind]
    V, F = read_obj(name)
    S = samples(placed(V, oy, yaw), F)
    cell = U.HIT_CELL
    cells = {}
    ix = np.floor(S[:, 0] / cell).astype(int)
    iz = np.floor(S[:, 2] / cell).astype(int)
    ay = np.abs(S[:, 1])
    order = np.lexsort((ay, iz, ix))
    for k in order:
        key = (int(ix[k]), int(iz[k]))
        if key not in cells:
            cells[key] = float(ay[k])
    return cells, S


def all_grids():
    """Lua-ready data: per kind a flat list ix, iz, y_mm (cell centres at (ix + 0.5) * cell), probes on the meshes."""
    rng = np.random.default_rng(5)
    out = {}
    for kind in PLACEMENTS:
        cells, S = grid(kind)
        flat = []
        for (ix, iz), y in sorted(cells.items()):
            flat += [ix, iz, int(round(y * 1000))]
        # probes: mesh samples well inside the slab (the rules must report a hit for a float centred on them) and
        # their extent (for the course to keep hooks clear of hazards)
        ay = np.abs(S[:, 1])
        pick = S[ay < max(U.FLOAT_R * 0.6, ay.min() + 0.08)] if len(S) else S
        pr = pick[rng.choice(len(pick), size=min(24, len(pick)), replace=False)] if len(pick) else np.zeros((0, 3))
        xs = [k[0] for k in cells]
        zs = [k[1] for k in cells]
        out[kind] = {
            "cells": flat,
            "probes": [[round(float(p[0]), 4), round(float(p[1]), 4), round(float(p[2]), 4)] for p in pr],
            "box": [min(xs) * U.HIT_CELL, (max(xs) + 1) * U.HIT_CELL, min(zs) * U.HIT_CELL, (max(zs) + 1) * U.HIT_CELL]
            if cells else [0, 0, 0, 0],
        }
        print("hit %-10s %6d cells, x %.2f..%.2f z %.2f..%.2f" % (kind, len(cells), *out[kind]["box"]))
    return out
