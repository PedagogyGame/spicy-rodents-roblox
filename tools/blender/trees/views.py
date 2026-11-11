"""Review cameras for a tree, defined from its climbing routes only (numpy; no bpy).

The routes never move, so the same view can be rendered before and after the art changes. All points
are studs in Roblox axes (+Y up), local to the tree's pivot. Each camera is (location, target, lens mm).

  street      a person on the pavement looking at the whole tree
  fork        the squirrel on the trunk below the first fork, looking up into it
  junction    the squirrel standing on a bough just past the junction, looking back at the fork
  junction2   the same from a second bough (another fork level when the tree has one)
  collar      level with the first fork from a neighbouring perch: the junction side-on
  bough       from inside the crown, along a bough toward its tip
  crown       from the pavement side, a closer look at one side of the canopy
"""
import math

import numpy as np

EYE = 1.5  # the squirrel's eyes above its feet, studs
SENSOR = 36.0


def _norm(v):
    v = np.asarray(v, float)
    return v / max(np.linalg.norm(v), 1e-9)


def _arclen(P):
    return np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(P, axis=0), axis=1))])


def _at(P, s):
    L = _arclen(P)
    s = float(np.clip(s, 0, L[-1]))
    return np.array([np.interp(s, L, P[:, k]) for k in range(3)])


def _boughs(rails):
    """Walkable boughs that start on the trunk: [(P, lift, name, rid, fork height)] sorted by fork height."""
    trunk = next(r for r in rails if r[2] == "trunk")[0]
    out = []
    for P, lift, kind, name, rid in rails:
        if kind != "branch":
            continue
        d = np.linalg.norm(trunk - P[0][None], axis=1).min()
        if d > 4.0 or _arclen(P)[-1] < 10:
            continue
        out.append((P, lift, name, rid, float(P[0][1])))
    out.sort(key=lambda b: (round(b[4], 1), b[3]))
    return trunk, out


def frame(rails, H):
    """Centre (x, z), width and top of the crown, from the routes."""
    trunk, boughs = _boughs(rails)
    ends = np.array([b[0][-1] for b in boughs] + [trunk[-1]])
    cx, cz = float(ends[:, 0].mean()), float(ends[:, 2].mean())
    rad = float(np.hypot(ends[:, 0] - cx, ends[:, 2] - cz).max())
    top = max(float(H) * 0.98, float(ends[:, 1].max()) + 8.0)
    return cx, cz, rad * 2 + 18.0, top


def cameras(rails, H, aspect=16 / 9):
    trunk, boughs = _boughs(rails)
    cams = {}
    cx, cz, width, top = frame(rails, H)
    lens = 28.0
    half_v = math.atan(0.5 * SENSOR / aspect / lens)
    half_h = math.atan(0.5 * SENSOR / lens)
    dist = max(top * 0.56 / math.tan(half_v), width * 0.5 / math.tan(half_h)) + width * 0.32
    ang = math.radians(200)
    # Blender-style azimuth kept from the first review sheet: the camera stands south-west of the tree
    loc = np.array([cx - math.sin(ang) * dist, 5.0, cz - math.cos(ang) * dist])
    cams["street"] = (loc, np.array([cx, top * 0.5, cz]), lens)
    loc2 = np.array([cx - math.sin(ang + 0.5) * dist * 0.5, 5.0, cz - math.cos(ang + 0.5) * dist * 0.5])
    cams["crown"] = (loc2, np.array([cx, top * 0.66, cz]), 24.0)
    if not boughs:
        return cams
    # the first fork: the lowest height at which boughs leave the trunk
    y0 = boughs[0][4]
    first = [b for b in boughs if abs(b[4] - y0) < 0.5]
    fork = first[0][0][0]
    dirs = [_norm((b[0][min(len(b[0]) - 1, 8)] - b[0][0]) * np.array([1, 0, 1])) for b in first]
    # look up the trunk from the side where the widest gap between the first boughs is
    az = sorted(math.atan2(d[2], d[0]) for d in dirs)
    gaps = [((az[(i + 1) % len(az)] - az[i]) % (2 * math.pi) or 2 * math.pi, az[i]) for i in range(len(az))]
    g, a0 = max(gaps)
    a = a0 + g / 2
    out = np.array([math.cos(a), 0.0, math.sin(a)])
    R = 3.2 if H > 40 else 1.8
    drop = 11.0 if H > 40 else 5.5
    base = np.array([fork[0], max(fork[1] - drop, 1.2), fork[2]])  # (an apple tree forks 5 studs up: stay above ground)
    cams["fork"] = (base + out * (R + 2.4), fork + np.array([0, 3.5 if H > 40 else 2.0, 0]), 17.0)
    # level with the fork, from a neighbouring perch a little round from the gap: the collars side-on
    a2 = a + 0.55
    out2 = np.array([math.cos(a2), 0.0, math.sin(a2)])
    far = 10.5 if H > 40 else 5.5
    cams["collar"] = (fork + out2 * far + np.array([0, 2.0 if H > 40 else 1.0, 0]), fork + np.array([0, 3.0 if H > 40 else 1.6, 0]), 20.0)

    def on_bough(b, s_cam, side, look_up):
        P, lift = b[0], b[1]
        L = _arclen(P)[-1]
        s_cam = min(s_cam, 0.5 * L)
        p = _at(P, s_cam)
        t = _norm(_at(P, s_cam + 0.5) - _at(P, s_cam - 0.5))
        sd = _norm(np.cross(t, [0, 1, 0]))
        loc = p + np.array([0, lift + EYE, 0]) + sd * side
        return loc, P[0] + np.array([0, look_up, 0])

    # the junction, seen by a squirrel standing on the most level bough of the first fork
    level = sorted(first, key=lambda b: -float(np.linalg.norm((b[0][min(len(b[0]) - 1, 8)] - b[0][0])[[0, 2]])))
    b1 = level[0]
    s1 = 11.0 if H > 40 else 6.0
    loc, tgt = on_bough(b1, s1, 1.1, 4.0 if H > 40 else 2.0)
    cams["junction"] = (loc, tgt, 17.0)
    upper = [b for b in boughs if b[4] > y0 + 0.5]
    b2 = upper[0] if upper else level[-1]
    loc, tgt = on_bough(b2, s1, -1.1, 4.0 if H > 40 else 2.0)
    cams["junction2"] = (loc, tgt, 17.0)
    # along a bough from inside the crown (third-person height, a little behind the squirrel)
    b3 = max(boughs, key=lambda b: _arclen(b[0])[-1])
    P, lift = b3[0], b3[1]
    L = _arclen(P)[-1]
    p = _at(P, 0.36 * L)
    t = _norm(_at(P, 0.36 * L + 1) - _at(P, 0.36 * L - 1))
    loc = p + np.array([0, lift + 2.6, 0]) - t * 1.5 + _norm(np.cross(t, [0, 1, 0])) * 0.8
    cams["bough"] = (loc, _at(P, 0.8 * L) + np.array([0, lift + 1.0, 0]), 18.0)
    return cams
