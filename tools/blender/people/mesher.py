"""Structured meshing of a signed-distance sculpt (numpy only, no bpy).

The heroes pipeline meshes its sculpts with surface nets and decimates. A townsperson's part has a few
hundred triangles, where a decimated mesh goes lumpy, so here every component is a regular grid instead:
rays are cast from an axis inside the sculpt (a point per ring, a polar angle per ring, an azimuth per
column) and each grid vertex is where its ray leaves the surface. A limb segment is a capsule grid (rays
fan out of the joint at each end, so the ends are true balls about the joints), a head is a globe.
The grid gives clean silhouettes, exact left/right symmetry, a rectangular UV chart with one seam, and
the same topology and UVs for every build (the builds only move the vertices).

A Chart is described by
  frame   (d, e1, e2): the axis direction from pole A to pole B and the azimuth reference (column 0)
  rings   [(origin, alpha_deg)]: alpha is the polar angle from -d; the first ring must be alpha = 0
          (pole A, one vertex) and the last alpha = 180 (pole B)
  phis    column azimuths in degrees, increasing, in [0, 360)
"""
import math

import numpy as np

F32 = np.float32


def unit(v):
    v = np.asarray(v, dtype=np.float64)
    return v / max(np.linalg.norm(v), 1e-12)


def frame(d, e1):
    d = unit(d)
    e1 = np.asarray(e1, dtype=np.float64)
    e1 = unit(e1 - d * np.dot(d, e1))
    e2 = np.cross(d, e1)
    return d, e1, e2


def field(body, pts):
    """The body's field at (N, 3) points, evaluated per spatial block so its primitive culling works."""
    pts = np.asarray(pts, dtype=F32)
    out = np.empty(len(pts), dtype=F32)
    if len(pts) <= 4096:
        out[:] = body.eval_points(pts)
        return out
    key = np.floor(pts / 0.25).astype(np.int64)
    key = (key[:, 0] + 512) * 1_048_576 + (key[:, 1] + 512) * 1024 + (key[:, 2] + 512)
    order = np.argsort(key, kind="stable")
    cuts = np.flatnonzero(np.diff(key[order])) + 1
    for g in np.split(order, cuts):
        p = pts[g]
        out[g] = body.eval_points(p, p.min(axis=0), p.max(axis=0))
    return out


def gradient(body, pts, eps=2e-3):
    """Unit gradient of the field (the outward normal on the surface): tetrahedral differences."""
    pts = np.asarray(pts, dtype=F32)
    tet = np.array([[1, -1, -1], [-1, -1, 1], [-1, 1, -1], [1, 1, 1]], dtype=F32)
    g = np.zeros((len(pts), 3), dtype=np.float64)
    for t in tet:
        g += field(body, pts + t * F32(eps))[:, None].astype(np.float64) * t
    n = np.linalg.norm(g, axis=1, keepdims=True)
    return (g / np.maximum(n, 1e-12)).astype(F32)


def project(body, pts, steps=6, eps=2e-3, max_step=0.03):
    """Newton steps onto the zero level."""
    p = np.asarray(pts, dtype=F32).copy()
    tet = np.array([[1, -1, -1], [-1, -1, 1], [-1, 1, -1], [1, 1, 1]], dtype=F32)
    for _ in range(steps):
        vals = [field(body, p + t * F32(eps)) for t in tet]
        d = sum(vals) / 4
        grad = sum(v[:, None] * t for v, t in zip(vals, tet)) / (4 * eps)
        gn = np.maximum(np.einsum("ij,ij->i", grad, grad), 1e-6)
        step = (d / gn)[:, None] * grad
        ln = np.linalg.norm(step, axis=1, keepdims=True)
        step = np.where(ln > max_step, step * (max_step / np.maximum(ln, 1e-9)), step)
        p = p - step
    return p


def cast(body, origins, dirs, tmax=1.6, step=0.008):
    """Distance along each ray to the OUTERMOST point of the surface (the last inside sample going out)."""
    origins = np.asarray(origins, dtype=np.float64)
    dirs = np.asarray(dirs, dtype=np.float64)
    n = len(origins)
    ts = np.arange(0.0, tmax + step, step)
    P = origins[:, None, :] + dirs[:, None, :] * ts[None, :, None]
    F = field(body, P.reshape(-1, 3)).reshape(n, len(ts))
    inside = F < 0
    if not inside.any(axis=1).all():
        bad = np.flatnonzero(~inside.any(axis=1))
        raise ValueError(f"{len(bad)} rays never enter the sculpt (first: origin {origins[bad[0]]}, dir {dirs[bad[0]]})")
    last = len(ts) - 1 - np.argmax(inside[:, ::-1], axis=1)
    lo = ts[last]
    hi = lo + step
    for _ in range(18):
        mid = (lo + hi) / 2
        f = field(body, origins + dirs * mid[:, None])
        ins = f < 0
        lo = np.where(ins, mid, lo)
        hi = np.where(ins, hi, mid)
    return (lo + hi) / 2


class Chart:
    def __init__(self, name, frame_, rings, phis, tmax=1.6, emphasis=None):
        self.name = name
        self.drop_a = self.drop_b = 0  # ring bands left out at each pole (set by the component)
        self.d, self.e1, self.e2 = frame_
        self.phis = np.asarray(phis, dtype=np.float64)
        # a ring's polar angle is one number or one per column (a hairline that dips over the ears)
        self.rings = [(np.asarray(o, dtype=np.float64), np.broadcast_to(np.asarray(a, dtype=np.float64), (len(self.phis),)))
                      for o, a in rings]
        assert abs(self.rings[0][1]).max() < 1e-9 and abs(self.rings[-1][1] - 180).max() < 1e-9, name
        self.col_on = None  # optional bool per column: faces between two columns need both on
        self.tmax = tmax
        self.emphasis = emphasis  # fn(phi_mid_deg) -> relative UV width of a column
        self.C = len(self.phis)
        self.R = len(self.rings) - 2  # rings between the poles
        self.S = None  # column u positions (C + 1), 0..1
        self.T = None  # ring v positions (R + 2), 0..1
        self.size = None  # (width, height) of the chart on the surface, studs

    # ---- vertices -------------------------------------------------------------------------------
    def rays(self):
        O, D = [], []
        ph = np.radians(self.phis)
        radial = np.cos(ph)[:, None] * self.e1 + np.sin(ph)[:, None] * self.e2
        for i, (o, a) in enumerate(self.rings):
            ar = np.radians(a)
            if i == 0 or i == len(self.rings) - 1:
                O.append(o[None])
                D.append((-self.d * math.cos(ar[0]))[None])
            else:
                O.append(np.repeat(o[None], self.C, axis=0))
                D.append(-self.d[None] * np.cos(ar)[:, None] + radial * np.sin(ar)[:, None])
        return np.concatenate(O), np.concatenate(D)

    def ring_ids(self, r):
        """Vertex ids of ring r (1..R)."""
        return np.arange(1 + (r - 1) * self.C, 1 + r * self.C)

    def vertices(self, body):
        O, D = self.rays()
        t = cast(body, O, D, self.tmax)
        return (O + D * t[:, None]).astype(F32)

    def vid(self, r, c):
        """Vertex index of ring r (0 = pole A, R + 1 = pole B), column c."""
        if r == 0:
            return 0
        if r == self.R + 1:
            return 1 + self.R * self.C
        return 1 + (r - 1) * self.C + (c % self.C)

    # ---- UV metrics (from one build, reused by the others) ------------------------------------------
    def measure(self, V):
        C, R = self.C, self.R
        grid = V[1:1 + R * C].reshape(R, C, 3).astype(np.float64)
        colw = np.linalg.norm(np.roll(grid, -1, axis=1) - grid, axis=2)  # (R, C): column c -> c + 1
        w = np.sort(colw, axis=0)[R // 2:].mean(axis=0)  # the wider half of the rings (poles pinch)
        if self.emphasis is not None:
            mid = (self.phis + np.roll(self.phis, -1)) / 2
            mid[-1] = (self.phis[-1] + self.phis[0] + 360) / 2
            w = w * np.array([self.emphasis(m % 360) for m in mid])
        rows = [np.linalg.norm(grid[0] - V[0], axis=1).mean()]
        rows += [np.linalg.norm(grid[i + 1] - grid[i], axis=1).mean() for i in range(R - 1)]
        rows += [np.linalg.norm(grid[-1] - V[-1], axis=1).mean()]
        rows = np.array(rows)
        if self.drop_a:
            rows[: self.drop_a] = 1e-4  # no texture space for bands that are not meshed
        if self.drop_b:
            rows[len(rows) - self.drop_b:] = 1e-4
        self.S = np.concatenate([[0], np.cumsum(w)]) / w.sum()
        self.T = np.concatenate([[0], np.cumsum(rows)]) / rows.sum()
        self.size = (float(w.sum()), float(rows.sum()))
        return self.size

    # ---- faces ----------------------------------------------------------------------------------
    def faces(self):
        """Triangles (vertex ids) and their corner UVs in the chart's unit square (u, v), v = 1 at pole A.
        Bands dropped at the poles (drop_a, drop_b) are left out."""
        C, R, S, T = self.C, self.R, self.S, self.T
        tris, uvs = [], []
        keep = lambda band: self.drop_a <= band <= R - self.drop_b  # noqa: E731  (band 0 = pole A's fan, R = pole B's)
        for c in range(C):
            if self.col_on is not None and not (self.col_on[c] and self.col_on[(c + 1) % C]):
                continue
            s0, s1 = S[c], S[c + 1]
            sm = (s0 + s1) / 2
            if keep(0):
                tris.append((self.vid(0, 0), self.vid(1, c), self.vid(1, c + 1)))
                uvs.append(((sm, 1 - T[0]), (s0, 1 - T[1]), (s1, 1 - T[1])))
            for r in range(1, R):
                if not keep(r):
                    continue
                a, b = self.vid(r, c), self.vid(r, c + 1)
                d_, e = self.vid(r + 1, c), self.vid(r + 1, c + 1)
                ta, tb = 1 - T[r], 1 - T[r + 1]
                tris.append((a, d_, e))
                uvs.append(((s0, ta), (s0, tb), (s1, tb)))
                tris.append((a, e, b))
                uvs.append(((s0, ta), (s1, tb), (s1, ta)))
            if keep(R):
                tris.append((self.vid(R, c), self.vid(R + 1, 0), self.vid(R, c + 1)))
                uvs.append(((s0, 1 - T[R]), (sm, 1 - T[R + 1]), (s1, 1 - T[R])))
        return np.array(tris, dtype=np.int64), np.array(uvs, dtype=np.float64)


def capsule(name, a, b, seam, ncols, caps_a, mids, caps_b, phis=None, **kw):
    """A capsule grid from joint a to joint b: caps_a / caps_b are the polar angles (deg, from the pole)
    of the rings fanned out of each end, mids the fractions along the axis of the rings in between."""
    a, b = np.asarray(a, float), np.asarray(b, float)
    fr = frame(b - a, seam)
    rings = [(a, 0.0)] + [(a, al) for al in caps_a]
    rings += [(a + (b - a) * s, 90.0) for s in mids]
    rings += [(b, 180.0 - al) for al in reversed(caps_b)] + [(b, 180.0)]
    if phis is None:
        phis = np.arange(ncols) * 360.0 / ncols
    return Chart(name, fr, rings, phis, **kw)


def globe(name, centre, pole, seam, thetas, phis, **kw):
    """A globe grid about one centre: thetas are the polar angles (deg) from the pole direction."""
    fr = frame(-np.asarray(pole, float), seam)
    rings = [(centre, 0.0)] + [(centre, th) for th in thetas] + [(centre, 180.0)]
    return Chart(name, fr, rings, phis, **kw)


def ring_stack(name, rings, seam, phis, axis=(0, 0, -1), **kw):
    """General: explicit [(origin, alpha_deg)] from the top pole down."""
    return Chart(name, frame(axis, seam), rings, phis, **kw)


def orient(V, tris, normals):
    """Flip the winding where it disagrees with the surface normals (all or nothing per chart)."""
    a, b, c = V[tris[:, 0]], V[tris[:, 1]], V[tris[:, 2]]
    fn = np.cross(b - a, c - a)
    s = np.einsum("ij,ij->i", fn, normals[tris[:, 0]] + normals[tris[:, 1]] + normals[tris[:, 2]])
    return s.sum() < 0


def tube(path, radius, sides=6, up=(0, 0, 1), cap=True):
    """A swept tube along a polyline (hoses, straps): returns (V, tris, corner uvs in the unit square)."""
    path = np.asarray(path, dtype=np.float64)
    n = len(path)
    radius = np.broadcast_to(np.asarray(radius, dtype=np.float64), (n,))
    tang = np.gradient(path, axis=0)
    tang /= np.linalg.norm(tang, axis=1, keepdims=True)
    ref = unit(up)
    V = []
    x = None
    for i in range(n):
        t = tang[i]
        x0 = ref - t * np.dot(ref, t) if x is None else x - t * np.dot(x, t)
        if np.linalg.norm(x0) < 1e-6:
            x0 = np.cross(t, [1.0, 0, 0])
        x = unit(x0)
        y = np.cross(t, x)
        for s in range(sides):
            a = 2 * math.pi * s / sides
            V.append(path[i] + (x * math.cos(a) + y * math.sin(a)) * radius[i])
    lens = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(path, axis=0), axis=1))])
    lens /= max(lens[-1], 1e-9)
    tris, uvs = [], []
    for i in range(n - 1):
        for s in range(sides):
            a, b = i * sides + s, i * sides + (s + 1) % sides
            c, d = a + sides, b + sides
            u0, u1 = s / sides, (s + 1) / sides
            tris += [(a, b, d), (a, d, c)]
            uvs += [((u0, lens[i]), (u1, lens[i]), (u1, lens[i + 1])), ((u0, lens[i]), (u1, lens[i + 1]), (u0, lens[i + 1]))]
    if cap:
        for end, i in ((0, 0), (1, n - 1)):
            V.append(path[i])
            ci = len(V) - 1
            for s in range(sides):
                a, b = i * sides + s, i * sides + (s + 1) % sides
                tris.append((ci, b, a) if end == 0 else (ci, a, b))
                uvs.append(((0.5, lens[i]),) * 3)
    return np.array(V, dtype=F32), np.array(tris, dtype=np.int64), np.array(uvs, dtype=np.float64)
