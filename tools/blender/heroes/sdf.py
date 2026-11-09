"""Signed-distance sculpting for the hero animals (numpy only, no bpy).

A body is a list of primitives combined in order with smooth union / smooth subtraction, evaluated on
a regular grid in 3-D blocks (each block only sees the primitives whose bounds reach it) and turned
into a quad mesh by surface nets (one vertex per sign-changing cell at the mean of its edge
crossings, one quad per sign-changing grid edge), then each vertex is pulled onto the zero level by
a few Newton steps on the field. Units are Blender units (= studs), +Z up, the animal faces -Y.

Primitives (all distances in studs):
  Ellipsoid(c, r, axes=None, k=0.0, op="add")      r = (rx, ry, rz) along the axes (columns), default world
  RoundCone(a, b, ra, rb, k=0.0, op="add")         a tapered capsule from a (radius ra) to b (radius rb)
  Box(c, half, axes=None, round=0.0, k, op)        rounded box
`k` is the smooth-union (or smooth-subtraction) blend radius with everything before it; op is
"add" or "sub". `scale` on a primitive list is applied by Body.scaled().
"""
import math

import numpy as np

F32 = np.float32


def _norm(v):
    v = np.asarray(v, dtype=np.float64)
    n = np.linalg.norm(v)
    return v / n if n > 0 else v


def frame_from(forward, up=(0, 0, 1)):
    """Orthonormal axes (columns x, y, z) with y along `forward` and z as close to `up` as possible."""
    y = _norm(forward)
    up = np.asarray(up, dtype=np.float64)
    if abs(np.dot(y, _norm(up))) > 0.98:
        up = np.array([1.0, 0, 0]) if abs(y[0]) < 0.9 else np.array([0, 0, 1.0])
    x = _norm(np.cross(y, up))
    z = np.cross(x, y)
    return np.stack([x, y, z], axis=1)


def rot_x(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]], dtype=np.float64)


def rot_y(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]], dtype=np.float64)


def rot_z(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]], dtype=np.float64)


class Prim:
    op = "add"
    k = 0.0
    tag = ""

    def bounds(self):
        raise NotImplementedError

    def dist(self, p):
        raise NotImplementedError

    def mirrored(self):
        raise NotImplementedError


class Ellipsoid(Prim):
    def __init__(self, c, r, axes=None, k=0.0, op="add", tag=""):
        self.c = np.asarray(c, dtype=np.float64)
        self.r = np.maximum(np.asarray(r, dtype=np.float64), 1e-4)
        self.axes = np.eye(3) if axes is None else np.asarray(axes, dtype=np.float64)
        self.k, self.op, self.tag = k, op, tag

    def bounds(self):
        ext = np.abs(self.axes) @ self.r
        return self.c - ext, self.c + ext

    def dist(self, p):
        q = (p - self.c.astype(F32)) @ self.axes.astype(F32)
        r = self.r.astype(F32)
        k0 = np.linalg.norm(q / r, axis=-1)
        k1 = np.linalg.norm(q / (r * r), axis=-1)
        return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)

    def mirrored(self):
        ax = self.axes.copy()
        ax[0, :] *= -1  # reflect the axes' x components
        ax[:, 0] *= -1  # keep a right-handed frame (flip the local x axis)
        return Ellipsoid(self.c * [-1, 1, 1], self.r, ax, self.k, self.op, self.tag)


class RoundCone(Prim):
    """IQ's exact round cone: spheres of radius ra at a and rb at b joined by their tangent cone."""

    def __init__(self, a, b, ra, rb, k=0.0, op="add", tag=""):
        self.a = np.asarray(a, dtype=np.float64)
        self.b = np.asarray(b, dtype=np.float64)
        self.ra, self.rb = float(ra), float(rb)
        self.k, self.op, self.tag = k, op, tag

    def bounds(self):
        lo = np.minimum(self.a - self.ra, self.b - self.rb)
        hi = np.maximum(self.a + self.ra, self.b + self.rb)
        return lo, hi

    def dist(self, p):
        a, b = self.a.astype(F32), self.b.astype(F32)
        r1, r2 = F32(self.ra), F32(self.rb)
        ba = b - a
        l2 = F32(np.dot(ba, ba))
        if l2 < 1e-12:
            return np.linalg.norm(p - a, axis=-1) - r1
        rr = r1 - r2
        a2 = l2 - rr * rr
        il2 = F32(1.0) / l2
        pa = p - a
        y = pa @ ba
        z = y - l2
        xv = pa * l2 - y[..., None] * ba
        x2 = np.einsum("...i,...i->...", xv, xv)
        y2 = y * y * l2
        z2 = z * z * l2
        k = np.sign(rr) * rr * rr * x2
        out = np.empty_like(y)
        c1 = np.sign(z) * a2 * z2 > k
        c2 = np.sign(y) * a2 * y2 < k
        out[c1] = np.sqrt(x2[c1] + z2[c1]) * il2 - r2
        m2 = c2 & ~c1
        out[m2] = np.sqrt(x2[m2] + y2[m2]) * il2 - r1
        m3 = ~(c1 | c2)
        out[m3] = (np.sqrt(x2[m3] * a2 * il2) + y[m3] * rr) * il2 - r1
        return out

    def mirrored(self):
        return RoundCone(self.a * [-1, 1, 1], self.b * [-1, 1, 1], self.ra, self.rb, self.k, self.op, self.tag)


class Box(Prim):
    def __init__(self, c, half, axes=None, round=0.0, k=0.0, op="add", tag=""):
        self.c = np.asarray(c, dtype=np.float64)
        self.h = np.asarray(half, dtype=np.float64)
        self.axes = np.eye(3) if axes is None else np.asarray(axes, dtype=np.float64)
        self.round, self.k, self.op, self.tag = round, k, op, tag

    def bounds(self):
        ext = np.abs(self.axes) @ (self.h + self.round)
        return self.c - ext, self.c + ext

    def dist(self, p):
        q = np.abs((p - self.c.astype(F32)) @ self.axes.astype(F32)) - self.h.astype(F32)
        outside = np.linalg.norm(np.maximum(q, 0), axis=-1)
        inside = np.minimum(np.max(q, axis=-1), 0)
        return outside + inside - F32(self.round)

    def mirrored(self):
        ax = self.axes.copy()
        ax[0, :] *= -1
        ax[:, 0] *= -1
        return Box(self.c * [-1, 1, 1], self.h, ax, self.round, self.k, self.op, self.tag)


def smin(a, b, k):
    if k <= 0:
        return np.minimum(a, b)
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b + (a - b) * h - k * h * (1.0 - h)


def smax(a, b, k):
    return -smin(-a, -b, k)


def mirror_pair(prims):
    """Each primitive plus its mirror image across x = 0 (left and right of the animal)."""
    out = []
    for p in prims:
        out.append(p)
        out.append(p.mirrored())
    return out


class Body:
    def __init__(self, prims, band=0.06):
        self.prims = list(prims)
        self.band = band
        b = [p.bounds() for p in self.prims if p.op == "add"]
        self.lo = np.min([x[0] for x in b], axis=0) - band
        self.hi = np.max([x[1] for x in b], axis=0) + band
        self._bounds = [(np.asarray(lo) - p.k, np.asarray(hi) + p.k) for p, (lo, hi) in ((p, p.bounds()) for p in self.prims)]

    def eval_points(self, pts, lo=None, hi=None):
        """Field at an (N, 3) float32 array. lo/hi: optional bounds of the points for culling."""
        if lo is None:
            lo, hi = pts.min(axis=0), pts.max(axis=0)
        far = F32(self.band * 4 + 1.0)
        d = np.full(pts.shape[0], far, dtype=F32)
        any_add = False
        for p, (plo, phi) in zip(self.prims, self._bounds):
            # cull: the gap between the boxes exceeds the band plus the blend radius
            gap = np.maximum(np.maximum(plo - hi, lo - phi), 0.0)
            if np.linalg.norm(gap) > self.band + p.k:
                continue
            di = p.dist(pts)
            if p.op == "add":
                d = smin(d, di, p.k) if any_add else di.astype(F32)
                any_add = True
            else:
                d = smax(d, -di, p.k)
        return d

    def grid(self, h, block=40):
        """Evaluate on a grid of spacing h covering the bounds; symmetric about x = 0."""
        hx = max(abs(self.lo[0]), abs(self.hi[0]))
        nx = int(math.ceil(hx / h)) + 2
        xs = (np.arange(-nx, nx + 1) * h).astype(F32)
        y0, z0 = self.lo[1] - 2 * h, self.lo[2] - 2 * h
        ny = int(math.ceil((self.hi[1] + 2 * h - y0) / h)) + 1
        nz = int(math.ceil((self.hi[2] + 2 * h - z0) / h)) + 1
        ys = (y0 + np.arange(ny) * h).astype(F32)
        zs = (z0 + np.arange(nz) * h).astype(F32)
        F = np.empty((len(xs), ny, nz), dtype=F32)
        for i0 in range(0, len(xs), block):
            for j0 in range(0, ny, block):
                for k0 in range(0, nz, block):
                    bx, by, bz = xs[i0 : i0 + block], ys[j0 : j0 + block], zs[k0 : k0 + block]
                    P = np.stack(np.meshgrid(bx, by, bz, indexing="ij"), axis=-1).reshape(-1, 3)
                    lo = np.array([bx[0], by[0], bz[0]])
                    hi = np.array([bx[-1], by[-1], bz[-1]])
                    F[i0 : i0 + block, j0 : j0 + block, k0 : k0 + block] = self.eval_points(P, lo, hi).reshape(
                        len(bx), len(by), len(bz)
                    )
        return F, (xs[0], ys[0], zs[0]), h

    def gradient(self, pts, eps=1e-3):
        e = F32(eps)
        g = np.empty_like(pts)
        for i in range(3):
            o = np.zeros(3, dtype=F32)
            o[i] = e
            g[:, i] = (self.eval_points(pts + o) - self.eval_points(pts - o)) / (2 * e)
        return g

    def project(self, pts, steps=3, eps=1e-3, chunk=200000):
        """Newton steps onto the zero level (in chunks, with culling per chunk)."""
        pts = pts.astype(F32).copy()
        for s0 in range(0, len(pts), chunk):
            p = pts[s0 : s0 + chunk]
            for _ in range(steps):
                lo, hi = p.min(axis=0) - 0.01, p.max(axis=0) + 0.01
                d = self.eval_points(p, lo, hi)
                g = np.empty_like(p)
                for i in range(3):
                    o = np.zeros(3, dtype=F32)
                    o[i] = eps
                    g[:, i] = (self.eval_points(p + o, lo, hi) - self.eval_points(p - o, lo, hi)) / (2 * eps)
                gn = np.maximum(np.einsum("ij,ij->i", g, g), 1e-6)
                step = (d / gn)[:, None] * g
                # never move further than half a cell's worth in one step (thin features)
                lim = 0.5 * np.linalg.norm(step, axis=1, keepdims=True)
                step = np.where(lim > 0.01, step * (0.01 / np.maximum(lim, 1e-9)), step)
                p -= step
            pts[s0 : s0 + chunk] = p
        return pts


# ---- surface nets ---------------------------------------------------------------------------------

_CORNERS = np.array([[i, j, k] for i in (0, 1) for j in (0, 1) for k in (0, 1)])
_EDGES = [(a, b) for a in range(8) for b in range(a + 1, 8) if np.abs(_CORNERS[a] - _CORNERS[b]).sum() == 1]


def surface_nets(F, origin, h):
    """Quad mesh of the zero level of F (negative inside). Returns verts (N, 3) float32, quads (M, 4)."""
    inside = F < 0
    nx, ny, nz = F.shape
    cs = (nx - 1, ny - 1, nz - 1)
    count = np.zeros(cs, dtype=np.int8)
    for c in _CORNERS:
        count += inside[c[0] : c[0] + cs[0], c[1] : c[1] + cs[1], c[2] : c[2] + cs[2]]
    active = (count > 0) & (count < 8)
    ci = np.argwhere(active)
    idx = np.full(cs, -1, dtype=np.int64)
    idx[active] = np.arange(len(ci))
    acc = np.zeros((len(ci), 3), dtype=np.float64)
    cnt = np.zeros(len(ci), dtype=np.float64)
    for a, b in _EDGES:
        pa, pb = ci + _CORNERS[a], ci + _CORNERS[b]
        fa = F[pa[:, 0], pa[:, 1], pa[:, 2]].astype(np.float64)
        fb = F[pb[:, 0], pb[:, 1], pb[:, 2]].astype(np.float64)
        m = (fa < 0) != (fb < 0)
        t = np.where(m, fa / np.where(m, fa - fb, 1.0), 0.0)
        pos = pa + (pb - pa) * t[:, None]
        acc[m] += pos[m]
        cnt[m] += 1
    verts = (acc / np.maximum(cnt, 1)[:, None]) * h + np.asarray(origin, dtype=np.float64)
    quads = []
    # x edges: (i,j,k)-(i+1,j,k); cells (i,j-1,k-1) (i,j,k-1) (i,j,k) (i,j-1,k)
    s0 = inside[:-1, 1:-1, 1:-1]
    s1 = inside[1:, 1:-1, 1:-1]
    e = np.argwhere(s0 != s1)
    if len(e):
        i, j, k = e[:, 0], e[:, 1] + 1, e[:, 2] + 1
        q = np.stack([idx[i, j - 1, k - 1], idx[i, j, k - 1], idx[i, j, k], idx[i, j - 1, k]], axis=1)
        flip = ~s0[e[:, 0], e[:, 1], e[:, 2]]
        q[flip] = q[flip][:, ::-1]
        quads.append(q)
    # y edges: cells (i-1,j,k-1) (i-1,j,k) (i,j,k) (i,j,k-1)
    s0 = inside[1:-1, :-1, 1:-1]
    s1 = inside[1:-1, 1:, 1:-1]
    e = np.argwhere(s0 != s1)
    if len(e):
        i, j, k = e[:, 0] + 1, e[:, 1], e[:, 2] + 1
        q = np.stack([idx[i - 1, j, k - 1], idx[i - 1, j, k], idx[i, j, k], idx[i, j, k - 1]], axis=1)
        flip = ~s0[e[:, 0], e[:, 1], e[:, 2]]
        q[flip] = q[flip][:, ::-1]
        quads.append(q)
    # z edges: cells (i-1,j-1,k) (i,j-1,k) (i,j,k) (i-1,j,k)
    s0 = inside[1:-1, 1:-1, :-1]
    s1 = inside[1:-1, 1:-1, 1:]
    e = np.argwhere(s0 != s1)
    if len(e):
        i, j, k = e[:, 0] + 1, e[:, 1] + 1, e[:, 2]
        q = np.stack([idx[i - 1, j - 1, k], idx[i, j - 1, k], idx[i, j, k], idx[i - 1, j, k]], axis=1)
        flip = ~s0[e[:, 0], e[:, 1], e[:, 2]]
        q[flip] = q[flip][:, ::-1]
        quads.append(q)
    quads = np.concatenate(quads, axis=0) if quads else np.zeros((0, 4), dtype=np.int64)
    quads = quads[(quads >= 0).all(axis=1)]
    return verts.astype(F32), quads
