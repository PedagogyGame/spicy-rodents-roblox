"""The small region meshes that are not sculpted grids (numpy only): the bare-skin patch in the V of
the scrubs and the doctor's stethoscope. Both are laid on the torso's sculpt, so each build has its own."""
import math

import numpy as np

import mesher

F32 = np.float32


def v_neck(torso, lift=0.014):
    """A patch of skin in the scrubs' V: rows across the chest narrowing to the point of the V. Its
    edges are the straight sides of the V, so the neckline is crisp at any distance."""
    zs = [4.05, 3.98, 3.90, 3.82, 3.74, 3.67]
    z_tip, half, cols = 3.60, 0.30, 5
    pts = []
    for z in zs:
        w = min(half, half * (z - z_tip) / 0.40)
        pts += [(w * (j / (cols - 1) * 2 - 1), z) for j in range(cols)]
    pts.append((0.0, z_tip))
    pts = np.array(pts)
    O = np.stack([pts[:, 0], np.full(len(pts), 0.05), pts[:, 1]], axis=1)
    D = np.tile(np.array([[0.0, -1.0, 0.0]]), (len(pts), 1))
    t = mesher.cast(torso, O, D, 1.2)
    V = (O + D * t[:, None]).astype(F32)
    N = mesher.gradient(torso, V)
    V = V + N * F32(lift)
    tris, uvs = [], []

    def uv(i):
        return ((pts[i, 0] + half) / (2 * half), (pts[i, 1] - z_tip) / (zs[0] - z_tip))

    for r in range(len(zs) - 1):
        for j in range(cols - 1):
            a, b = r * cols + j, r * cols + j + 1
            c, d = a + cols, b + cols
            tris += [(a, c, d), (a, d, b)]
            uvs += [(uv(a), uv(c), uv(d)), (uv(a), uv(d), uv(b))]
    last, tip = (len(zs) - 1) * cols, len(pts) - 1
    for j in range(cols - 1):
        tris.append((last + j, tip, last + j + 1))
        uvs.append((uv(last + j), uv(tip), uv(last + j + 1)))
    tris, uvs = np.array(tris), np.array(uvs)
    if mesher.orient(V, tris, N):
        tris, uvs = tris[:, [0, 2, 1]], uvs[:, [0, 2, 1]]
    return {"V": V, "N": N, "tris": tris, "uv": uvs, "chart": np.zeros(len(tris), dtype=np.int32), "charts": ["VNeck"],
            "sizes": {"VNeck": (2 * half, zs[0] - z_tip)}}


def stethoscope(torso, radius=0.022, sides=5):
    """A tube round the back of the neck and down both sides of the chest to a steel chest piece."""
    top = np.array([0.0, 0.02, 3.84])

    def on_collar(phi, alpha):
        a, p = math.radians(alpha), math.radians(phi)
        d = np.array([math.sin(p) * math.sin(a), -math.cos(p) * math.sin(a), math.cos(a)])
        return top, d

    def on_chest(phi, z):
        p = math.radians(phi)
        return np.array([0.0, 0.0, z]), np.array([math.sin(p), -math.cos(p), 0.0])

    def place(rays, off):
        O = np.array([r[0] for r in rays])
        D = np.array([r[1] for r in rays])
        t = mesher.cast(torso, O, D, 1.6)
        P = (O + D * t[:, None]).astype(F32)
        n = mesher.gradient(torso, P)
        return P + n * F32(off), n

    half = [on_chest(1.5, 3.46), on_chest(6, 3.56), on_chest(12, 3.68), on_chest(17, 3.80), on_collar(36, 60),
            on_collar(72, 57), on_collar(120, 55), on_collar(160, 53)]
    mirror = [(o, d * np.array([-1, 1, 1])) for o, d in reversed(half)]
    loop, _n = place(half + [on_collar(180, 53)] + mirror, radius + 0.004)
    stem, n_stem = place([on_chest(0, 3.47), on_chest(2, 3.38), on_chest(5, 3.29), on_chest(7, 3.22)], radius + 0.004)
    disc_c, disc_n = stem[-1] + np.array([0.004, 0, -0.05], dtype=F32), n_stem[-1]
    parts = []
    for path, r, sd, chart in ((loop, radius, sides, 0), (stem, radius, sides, 0),
                               (np.stack([disc_c - disc_n * 0.01, disc_c + disc_n * 0.03]), 0.078, 10, 1)):
        V, tris, uvs = mesher.tube(path, r, sides=sd, up=(0, -1, 0.2))
        n = len(path)
        centres = np.concatenate([np.repeat(np.asarray(path, dtype=F32), sd, axis=0), np.asarray(path, dtype=F32)[[0, -1]]])
        N = V - centres
        N[n * sd] = path[0] - path[1]
        N[n * sd + 1] = path[-1] - path[-2]
        N = N / np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-9)
        parts.append((V, N.astype(F32), tris, uvs, chart))
    off = 0
    Vs, Ns, Ts, Us, Cs = [], [], [], [], []
    for V, N, tris, uvs, chart in parts:
        if mesher.orient(V, tris, N):
            tris, uvs = tris[:, [0, 2, 1]], uvs[:, [0, 2, 1]]
        Vs.append(V)
        Ns.append(N)
        Ts.append(tris + off)
        Us.append(uvs)
        Cs.append(np.full(len(tris), chart, dtype=np.int32))
        off += len(V)
    return {"V": np.concatenate(Vs), "N": np.concatenate(Ns), "tris": np.concatenate(Ts), "uv": np.concatenate(Us),
            "chart": np.concatenate(Cs), "charts": ["StethoTube", "StethoDisc"],
            "sizes": {"StethoTube": (0.16, 0.3), "StethoDisc": (0.16, 0.16)}}
