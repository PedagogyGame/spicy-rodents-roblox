"""Branch junctions as wood grows them: one skin for a parent limb and the children leaving it.

numpy only (no bpy, no treegen import). Units: studs; axes: whatever the caller uses (the demo uses
Roblox axes, +Y up). Arrays as in treegen.Mesh.add: V (n,3), F (m,3) outward triangles, UV (n,2),
N (n,3) unit normals; a vertex is repeated where its bark coordinates differ (seams).

    V, F, UV, N, info = junction_mesh((P, Rp), [(C1, R1), ...], sides=10, child_sides=6)

Approach (direct construction on an implicit shape): the topology is built by hand - the parent tube's
quads are cut open round each child and bridged to the child's first ring through collar rings - and
every collar vertex is then put on a smooth union of the limbs (tapered capsules, polynomial smooth
minimum with a compact blend), with the child swollen toward its base and a low ridge of bark in the
axil. Away from the blend the union IS the limbs, so ordinary tube rings join it exactly and the skin
never lies below a limb's own radius.

Two cases are made right (see junction_demo.py):
  side    a child leaving the side of its parent (a bough on a trunk): its first point is on the
          parent's centre line, strictly between the parent's ends.
  fork    the parent ends in exactly two children (both start at the parent's last point).
Not done: three-way forks, two children whose collars overlap, a child as thick as its parent (the
cut may not wrap more than the whole ring), children of children near a collar.
"""
import math

import numpy as np


def _norm(v):
    v = np.asarray(v, float)
    return v / np.maximum(np.linalg.norm(v, axis=-1, keepdims=True), 1e-12)


def _ss(x):
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3 - 2 * x)


def _smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b + (a - b) * h - k * h * (1.0 - h)


def _wrap(a):
    return (np.asarray(a) + math.pi) % (2 * math.pi) - math.pi


class Axis:
    """A limb's centre line with a radius at every point and rotation-minimising frames."""

    def __init__(self, C, R, start_normal=None, end_normal=None):
        self.C, self.R = np.asarray(C, float), np.asarray(R, float)
        n = len(self.C)
        seg = np.linalg.norm(np.diff(self.C, axis=0), axis=1)
        self.s = np.concatenate([[0.0], np.cumsum(seg)])
        self.L = float(self.s[-1])
        T = np.zeros_like(self.C)
        T[1:-1] = self.C[2:] - self.C[:-2]
        T[0], T[-1] = self.C[1] - self.C[0], self.C[-1] - self.C[-2]
        self.T = T = _norm(T)
        if start_normal is None:
            start_normal = np.array([0.0, 1.0, 0.0]) if abs(T[0][1]) < 0.9 else np.array([1.0, 0.0, 0.0])
        Ns = [_norm(start_normal - T[0] * np.dot(start_normal, T[0]))]
        for i in range(1, n):
            Ns.append(_norm(Ns[-1] - T[i] * np.dot(Ns[-1], T[i])))
        N = np.array(Ns)
        B = np.cross(T, N)
        if end_normal is not None:  # turn every frame by one angle so the last normal is the asked one
            e = end_normal - T[-1] * np.dot(end_normal, T[-1])
            a = math.atan2(float(np.dot(e, B[-1])), float(np.dot(e, N[-1])))
            N, B = N * math.cos(a) + B * math.sin(a), B * math.cos(a) - N * math.sin(a)
        self.N, self.B = N, B

    def at(self, s):
        """-> centre, radius, T, N, B at arc lengths s (array)."""
        s = np.atleast_1d(np.asarray(s, float))
        i = np.clip(np.searchsorted(self.s, s, side="right") - 1, 0, len(self.s) - 2)
        t = np.clip((s - self.s[i]) / np.maximum(self.s[i + 1] - self.s[i], 1e-12), 0, 1)[:, None]
        c = self.C[i] * (1 - t) + self.C[i + 1] * t
        r = self.R[i] * (1 - t[:, 0]) + self.R[i + 1] * t[:, 0]
        T = _norm(self.T[i] * (1 - t) + self.T[i + 1] * t)
        N = self.N[i] * (1 - t) + self.N[i + 1] * t
        N = _norm(N - T * (N * T).sum(1, keepdims=True))
        return c, r, T, N, np.cross(T, N)

    def ring(self, s, n):
        """n points round the limb at arc length s (the first on the frame's normal) and their normals."""
        c, r, T, N, B = self.at(s)
        a = np.arange(n) * (2 * math.pi / n)
        d = np.cos(a)[:, None] * N + np.sin(a)[:, None] * B
        return c + d * r[0], d

    def dist(self, P, R=None):
        """Distance from points P to the surface of the chain of tapered capsules (negative inside)."""
        R = self.R if R is None else R
        A, AB = self.C[:-1], self.C[1:] - self.C[:-1]
        AP = P[:, None, :] - A[None]
        t = np.clip((AP * AB[None]).sum(2) / np.maximum((AB * AB).sum(1), 1e-12)[None], 0, 1)
        d = np.linalg.norm(AP - t[..., None] * AB[None], axis=2) - (R[:-1][None] + t * (R[1:] - R[:-1])[None])
        return d.min(1)

    def project(self, P):
        """-> (arc length of the nearest centre-line point, running on past the ends; angle round)."""
        A, AB = self.C[:-1], self.C[1:] - self.C[:-1]
        AP = P[:, None, :] - A[None]
        l2 = np.maximum((AB * AB).sum(1), 1e-12)
        t = np.clip((AP * AB[None]).sum(2) / l2[None], 0, 1)
        i = np.linalg.norm(AP - t[..., None] * AB[None], axis=2).argmin(1)
        s = self.s[i] + t[np.arange(len(P)), i] * np.sqrt(l2[i])
        c, _, T, N, B = self.at(s)
        rel = P - c
        over = np.where((s <= 0) | (s >= self.L), (rel * T).sum(1), 0.0)
        return s + over, np.arctan2((rel * B).sum(1), (rel * N).sum(1))


class _Field:
    """The smooth union the collar vertices live on."""

    def __init__(self, par, kids, mode, ridge):
        self.par, self.kids, self.mode, self.ridge = par, kids, mode, ridge

    def dkid(self, i, P):
        k = self.kids[i]
        back = np.maximum(0.0, -((P - k["B"]) * k["c0"]).sum(1))  # no wood behind the child's start
        return k["ax"].dist(P, k["Rsw"]) + 2.0 * back

    def kof(self, i, P):
        """Blend radius at P: tight in the axil, wide under the child (the wood runs out along the
        parent below a bough)."""
        k = self.kids[i]
        if self.mode == "fork":
            return k["k"]
        under = _ss(0.5 - ((P - k["X0"]) * k["tp"]).sum(1) / (2.0 * k["rc"]))
        return k["k"] * (0.75 + (k["flare"] - 0.75) * under)

    def others(self, i, P):
        d = self.par.dist(P)
        for j in range(len(self.kids)):
            if j != i:
                d = np.minimum(d, self.dkid(j, P))
        return d

    def __call__(self, P):
        dp = self.par.dist(P)
        dc = [self.dkid(i, P) for i in range(len(self.kids))]
        f = dp
        for i in range(len(self.kids)):
            f = _smin(f, dc[i], self.kof(i, P))
        if self.ridge > 0:
            if self.mode == "fork":
                k = min(self.kids[0]["k"], self.kids[1]["k"])
                rc = min(self.kids[0]["rc"], self.kids[1]["rc"])
                bump = np.clip(1 - ((dc[0] - dc[1]) / (0.5 * k)) ** 2, 0, 1) ** 2
                f = f - self.ridge * rc * bump * _ss(0.5 + (dp - np.maximum(dc[0], dc[1])) / (0.5 * k))
            else:
                for i, k in enumerate(self.kids):
                    bump = np.clip(1 - ((dp - dc[i]) / (0.5 * k["k"])) ** 2, 0, 1) ** 2
                    axil = _ss(0.5 + ((P - k["X0"]) * k["tp"]).sum(1) / (1.5 * k["rc"]))
                    f = f - self.ridge * k["rc"] * bump * axil
        return f

    def grad(self, P, fn=None, eps=0.01):
        fn = fn or self
        g = np.zeros_like(P)
        for a in range(3):
            e = np.zeros(3)
            e[a] = eps
            g[:, a] = fn(P + e) - fn(P - e)
        return _norm(g)

    def cast(self, P, d, tmax):
        """Walk from P (inside or on the skin) along d to the skin."""
        n = len(P)
        lo, hi, done = np.zeros(n), np.full(n, float(tmax)), np.zeros(n, bool)
        for t in np.linspace(0.0, float(tmax), 25):  # the FIRST way out (a child may overhang the ray)
            out = (self(P + t * d) >= 0) & ~done
            hi = np.where(out, t, hi)
            lo = np.where(done | out, lo, t)
            done |= out
        lo = np.minimum(lo, hi)
        for _ in range(26):
            mid = 0.5 * (lo + hi)
            inside = self(P + mid[:, None] * d) < 0
            lo, hi = np.where(inside, mid, lo), np.where(inside, hi, mid)
        return P + hi[:, None] * d


class _Build:
    def __init__(self):
        self.P, self.Nrm, self.tri, self.uv = [], [], [], []
        self.n = 0
        self.tips = []

    def pts(self, P, N):
        P = np.atleast_2d(P)
        self.P.append(P)
        self.Nrm.append(np.atleast_2d(N))
        idx = np.arange(self.n, self.n + len(P))
        self.n += len(P)
        return idx

    def add(self, a, b, c, ua, ub, uc):
        self.tri.append((a, b, c))
        self.uv.append((ua, ub, uc))

    def strip_uv(self, ia, ib, uva, uvb):
        """Quads between two closed rings of equal count, each vertex with its own bark coordinates."""
        n = len(ia)
        for j in range(n):
            j1 = (j + 1) % n
            self.add(ia[j], ia[j1], ib[j1], tuple(uva[j]), tuple(uva[j1]), tuple(uvb[j1]))
            self.add(ia[j], ib[j1], ib[j], tuple(uva[j]), tuple(uvb[j1]), tuple(uvb[j]))

    def strip(self, ia, ib, n, cols, urep, va, vb):
        """Quads between two rings of n vertices for the columns `cols` (may run past n: u goes on)."""
        for j in cols:
            j0, j1 = j % n, (j + 1) % n
            u0, u1 = j / n * urep, (j + 1) / n * urep
            A, Bq, Cq, D = (u0, va[j0]), (u1, va[j1]), (u1, vb[j1]), (u0, vb[j0])
            self.add(ia[j0], ia[j1], ib[j1], A, Bq, Cq)
            self.add(ia[j0], ib[j1], ib[j0], A, Cq, D)

    def stitch(self, A, Bl, angle):
        """Triangles between two closed loops, matched by angle(points (n,3)) -> radians round a
        centre both loops go round. A, Bl: lists of (index, point, uv)."""
        def ang(L):
            return angle(np.array([p for _, p, _ in L]))

        aA = ang(A)
        if np.sum(_wrap(np.diff(np.append(aA, aA[0])))) < 0:
            A = A[::-1]
            aA = aA[::-1]
        aA = np.maximum.accumulate(aA[0] + np.concatenate([[0], np.cumsum(_wrap(np.diff(aA)))]))
        aB = ang(Bl)
        j0 = int(np.argmin(np.abs(_wrap(aB - aA[0]))))
        Bl = Bl[j0:] + Bl[:j0]
        aB = np.roll(aB, -j0)
        aB = aA[0] + _wrap(aB[0] - aA[0]) + np.concatenate([[0], np.cumsum(_wrap(np.diff(aB)) % (2 * math.pi))])
        nA, nB = len(A), len(Bl)
        aA = np.append(aA, aA[0] + 2 * math.pi)
        aB = np.append(aB, aB[0] + 2 * math.pi)
        i = j = 0
        while i < nA or j < nB:
            if j >= nB or (i < nA and aA[i + 1] <= aB[j + 1]):
                p, q, r = A[i], A[(i + 1) % nA], Bl[j % nB]
                i += 1
            else:
                p, q, r = A[i % nA], Bl[(j + 1) % nB], Bl[j]
                j += 1
            self.add(p[0], q[0], r[0], p[2], q[2], r[2])

    def finish(self):
        P, Nrm = np.concatenate(self.P), _norm(np.concatenate(self.Nrm))
        T = np.array(self.tri, np.int64)
        U = np.array(self.uv, float)
        fn = np.cross(P[T[:, 1]] - P[T[:, 0]], P[T[:, 2]] - P[T[:, 0]])
        flip = (fn * Nrm[T].sum(1)).sum(1) < 0
        T[flip] = T[flip][:, [0, 2, 1]]
        U[flip] = U[flip][:, [0, 2, 1]]
        key = np.concatenate([T.reshape(-1, 1).astype(float), np.round(U.reshape(-1, 2), 5)], axis=1)
        uniq, inv = np.unique(key, axis=0, return_inverse=True)
        vid = uniq[:, 0].astype(np.int64)
        return P[vid], inv.reshape(-1, 3), uniq[:, 1:], Nrm[vid], T


def _kid(par, C, R, swell, fillet, sB, flare=1.0):
    """A child ready for the field: densely sampled near its base, swollen toward the parent."""
    C, R = np.asarray(C, float), np.asarray(R, float)
    raw = Axis(C, R)
    rc = float(R[0])
    rp = float(par.at(sB)[1][0])
    k = min(fillet * rc, 0.7 * rp)
    span = min(raw.L, rp + 12 * rc + 2 * k)
    hs = np.unique(np.concatenate([raw.s, np.linspace(0, span, 33)]))
    c, r, _, _, _ = raw.at(hs)
    ax = Axis(c, r)
    out = par.dist(c) > 0
    hx = float(hs[int(np.argmax(out))]) if out.any() else span
    Rsw = r * (1 + swell * (1 - _ss((hs - hx) / (1.6 * rc))))
    return {"ax": ax, "Rsw": Rsw, "rc": rc, "k": k, "flare": max(flare, 0.75), "hx": hx, "span": span, "B": C[0], "c0": ax.T[0],
            "X0": ax.at(hx)[0][0], "tp": par.at(sB)[2][0]}


def _collar(F, i, nc, fracs, margin):
    """The child's rings from the valley (fraction 0) to its first plain ring (fraction 1)."""
    k = F.kids[i]
    ax = k["ax"]
    hA = k["span"]
    for h in np.linspace(min(k["hx"] + 1.6 * k["rc"], k["span"]), k["span"], 40):  # first ring clear of the blend
        if F(ax.ring(h, nc)[0]).min() >= -1e-4:
            hA = float(h)
            break
    ang = np.arange(nc) * (2 * math.pi / nc)

    def S(h):
        c, _, _, N, B = ax.at(h)
        e = np.cos(ang)[:, None] * N + np.sin(ang)[:, None] * B
        return c + e * np.interp(h, ax.s, k["Rsw"])[:, None], e

    lo, hi = np.zeros(nc), np.full(nc, hA)
    for _ in range(32):  # where each meridian of the swollen child comes out of the other wood
        mid = 0.5 * (lo + hi)
        inside = F.others(i, S(mid)[0]) < margin
        lo, hi = np.where(inside, mid, lo), np.where(inside, hi, mid)
    rings = []
    for t in fracs:
        if t >= 1:
            P, e = ax.ring(hA, nc)
            rings.append((P, e))
            continue
        P, e = S(hi + t * (hA - hi))
        no = F.grad(P, lambda Q: F.others(i, Q))
        P = F.cast(P, _norm(e + (1 - t) ** 2 * no), 2.5 * k["k"] * k["flare"])
        rings.append((P, F.grad(P)))
    return rings, hA


def _child_skin(b, F, i, rings, hA, nc, urep, vtile, kid_raw_s, cap=True):
    """Collar bands and the plain tube of child i. Returns the valley ring's indices."""
    k = F.kids[i]
    ax = k["ax"]
    idx = [b.pts(P, N) for P, N in rings]
    vs = [None] * len(rings)
    vs[-1] = np.full(nc, hA / vtile)
    for r in range(len(rings) - 2, -1, -1):  # v runs down the collar by the length of the bark
        vs[r] = vs[r + 1] - np.linalg.norm(rings[r + 1][0] - rings[r][0], axis=1) / vtile
    for r in range(len(rings) - 1):
        b.strip(idx[r], idx[r + 1], nc, range(nc), urep, vs[r], vs[r + 1])
    prev, vprev = idx[-1], vs[-1]
    for s in [s for s in kid_raw_s if s > hA + 0.4 * k["rc"]]:
        P, e = ax.ring(s, nc)
        cur = b.pts(P, e)
        b.strip(prev, cur, nc, range(nc), urep, vprev, np.full(nc, s / vtile))
        prev, vprev = cur, np.full(nc, s / vtile)
    if cap:
        c, r, T, _, _ = ax.at(ax.L)
        tip = b.pts(c + T * r[0] * 0.6, T)[0]
        b.tips.append(tip)
        for j in range(nc):
            b.add(prev[j], prev[(j + 1) % nc], tip, (j / nc * urep, vprev[j]), ((j + 1) / nc * urep, vprev[j]),
                  ((j + 0.5) / nc * urep, vprev[j] + 0.1))
    return idx[0]


def top_line_cover(V, F, limbs, step=0.2):
    """The ray test for the squirrel's feet. For each limb (C, R) rays are shot at the centre line
    from outside, along the limb's top line (the frame normal: world up made perpendicular to the
    limb; +X for a vertical limb), every `step` studs. Returns per limb the lowest value of
    (height of the skin above the centre line - the limb's own radius there): >= 0 means the skin
    never falls below the radius between vertices."""
    A, E1, E2 = V[F[:, 0]], V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]]
    out = []
    for C, R in limbs:
        ax = Axis(C, R)
        c, r, _, N, _ = ax.at(np.arange(0.0, ax.L, step))
        O, d = c + N * (r[:, None] + 3.0), -N
        free = np.ones(len(c), bool)  # only where the top line and the ray's start are in the open air
        for C2, R2 in limbs:
            if C2 is not C:
                a2 = Axis(C2, R2)
                free &= (a2.dist(c + N * r[:, None]) > 0) & (a2.dist(O) > 0)
        O, d, r = O[free], d[free], r[free]
        worst = np.inf
        with np.errstate(divide="ignore", invalid="ignore"):
            for o, dd, rr in zip(O, d, r):
                pv = np.cross(dd[None], E2)
                inv = 1.0 / (E1 * pv).sum(1)
                tv = o[None] - A
                u = (tv * pv).sum(1) * inv
                qv = np.cross(tv, E1)
                v = (qv @ dd) * inv
                t = (E2 * qv).sum(1) * inv
                hit = (u >= -1e-9) & (v >= -1e-9) & (u + v <= 1 + 1e-9) & (t > 0)
                if hit.any():
                    worst = min(worst, 3.0 - float(t[hit].min()))
        out.append(worst)
    return out


def junction_mesh(parent, children, sides=10, child_sides=6, fillet=1.0, swell=0.16, ridge=0.10, collar_rings=2,
                  u_rep=2, child_u_rep=1, v_tile=4.0, child_v_tile=None, saddle=9, fork_margin=0.22, flare=1.7, start_normal=None,
                  cap_ends=True):
    """One skin for a parent limb and the children that leave it.

    parent        (P, R): centre line (n,3) and radius at each point (n,), studs, base first.
    children      [(C, R), ...]: each child's centre line and radii; C[0] lies on the parent's centre
                  line - between its ends (a side branch) or at its last point (a fork: exactly two).
    sides         vertices round the parent (even); child_sides: round each child (int or one per child).
    fillet        blend radius as a fraction of the child's base radius (capped at 0.7 parent radii).
    flare         side branch only: the blend radius under the child (the side toward the parent's base)
                  as a multiple of fillet; in the axil it is 0.75 of fillet. A flare ring on the parent
                  (child_sides vertices) carries the shape.
    swell         how much thicker the child is at its base (fraction of its radius), gone 1.6 radii out.
    ridge         height of the bark ridge in the axil, fraction of the child's radius (0 = none).
    collar_rings  rings between the valley ring and the child's first plain ring (cost: 2 x child_sides
                  triangles each).
    u_rep, v_tile bark tiles round the parent / studs of limb per tile; child_u_rep, child_v_tile likewise.
    saddle        fork only: points across the crotch (odd); fork_margin: how far each child's valley
                  ring stays from the crotch line, in child radii.
    Returns V, F, UV, N and info = {"tris", "junction_tris" (per child: everything between the parent's
    two cut rings / last ring and the child's first plain ring, minus the plain quads those rings would
    have had), "open_edges", "min_cover" (lowest collar vertex above the plain limbs, >= 0), "ports"}.
    """
    P, Rp = np.asarray(parent[0], float), np.asarray(parent[1], float)
    nk = len(children)
    ncs = [child_sides] * nk if np.isscalar(child_sides) else list(child_sides)
    cvt = child_v_tile or v_tile
    fork = all(np.linalg.norm(np.asarray(c[0], float)[0] - P[-1]) < 0.5 * Rp[-1] for c in children)
    b = _Build()
    fracs = [0.0] + [(r + 1) / (collar_rings + 1) * 0.8 for r in range(collar_rings)] + [1.0]
    info = {"junction_tris": [], "ports": []}
    ntri0 = 0

    if fork:
        if nk != 2:
            raise ValueError("a fork takes exactly two children")
        kd = [np.asarray(c[0], float) for c in children]
        m = _norm(_norm(kd[0][1] - kd[0][0]) - _norm(kd[1][1] - kd[1][0]))
        tp = _norm(P[-1] - P[-2])
        # the parent keeps its own frame (a vertex column on its top line); the wood splits along the
        # two columns nearest the plane between the children
        par = Axis(P, Rp, start_normal)
        want = np.cross(m, tp)
        ja = int(round(math.atan2(float(want @ par.B[-1]), float(want @ par.N[-1])) / (2 * math.pi / sides))) % sides
        N_e = par.N[-1] * math.cos(ja * 2 * math.pi / sides) + par.B[-1] * math.sin(ja * 2 * math.pi / sides)
        kids = [_kid(par, c[0], c[1], swell, fillet, par.L) for c in children]
        F = _Field(par, kids, "fork", ridge)
        E, rp = P[-1], float(Rp[-1])
        s_lo = par.L - 0.3 * rp
        for off in np.arange(0.3 * rp, 6 * rp, 0.1 * rp):  # the parent's last plain ring
            s_lo = par.L - off
            Q = par.ring(s_lo, sides)[0]
            if F(Q).min() >= -1e-4:
                break
        s_lo = max(s_lo, 0.0)
        st = [s for s in par.s if s < s_lo - 0.35 * rp] + [s_lo]
        ridx = [b.pts(*par.ring(s, sides)) for s in st]
        for r in range(len(st) - 1):
            b.strip(ridx[r], ridx[r + 1], sides, range(sides), u_rep, np.full(sides, st[r] / v_tile),
                    np.full(sides, st[r + 1] / v_tile))
        ntri0 = len(b.tri)
        last = ridx[-1]
        Pl = par.ring(s_lo, sides)[0]
        T_e = par.T[-1]
        th_e = math.pi - math.atan2(float(par.at(s_lo)[1][0]), par.L - s_lo)
        # across the crotch: always a point level with the parent's end on each side (so the parent's
        # own line stays a mesh edge right to its end), one below it if there is room, the rest above
        low = [0.5 * (th_e + math.pi / 2)] if th_e - math.pi / 2 > math.radians(30) and saddle >= 7 else []
        inner = np.linspace(-math.pi / 2, math.pi / 2, saddle - 2 * len(low))
        th = np.concatenate([[-t for t in low], inner, low])
        th[np.abs(th) < 1e-9] = 0.0
        saddle = len(th)
        d = np.cos(th)[:, None] * T_e + np.sin(th)[:, None] * N_e
        Sp = F.cast(np.repeat(E[None], saddle, 0), d, par.L - s_lo + 8 * rp)
        sidx = b.pts(Sp, F.grad(Sp))
        sv = (par.L + (Sp - E) @ T_e) / v_tile
        h = sides // 2
        # the valley between the children is the saddle line itself: each child's first ring sits a
        # little way up its own bark, so the stitch to the saddle is made of broad triangles
        ffr = list(np.linspace(0.3, 1.0, collar_rings + 1))
        for i in range(2):
            rings, hA = _collar(F, i, ncs[i], ffr, fork_margin * kids[i]["rc"])
            t0 = len(b.tri)
            c0 = _child_skin(b, F, i, rings, hA, ncs[i], child_u_rep, cvt, Axis(*children[i]).s, cap_ends)
            body = 2 * ncs[i] * (len(ffr) - 1)
            cols = range(ja, ja + h + 1) if i == 0 else range(ja + h, ja + sides + 1)
            A = [(last[j % sides], Pl[j % sides], (j / sides * u_rep, s_lo / v_tile)) for j in cols]
            order = range(saddle) if i == 0 else range(saddle - 1, -1, -1)  # child 0: from -N round to +N
            for q in order:
                if abs(th[q]) < 1e-9:
                    u = (ja + (0.5 if i == 0 else 1.5) * h) / sides * u_rep
                elif th[q] > 0:
                    u = (ja + (0 if i == 0 else sides)) / sides * u_rep
                else:
                    u = (ja + h) / sides * u_rep
                A.append((sidx[q], Sp[q], (u, sv[q])))
            sp, ph = par.project(rings[0][0])
            cen = (ja + (0.5 if i == 0 else 1.5) * h) * 2 * math.pi / sides
            ph = cen + _wrap(ph - cen)
            Bl = [(c0[j], rings[0][0][j], (ph[j] / (2 * math.pi) * u_rep, sp[j] / v_tile)) for j in range(ncs[i])]
            ax = kids[i]["ax"]
            b.stitch(A, Bl, lambda X, ax=ax: np.arctan2((X - E) @ ax.B[0], (X - E) @ ax.N[0]))
            info["junction_tris"].append(len(A) + len(Bl) + body)
            info["ports"].append({"child": i, "first_plain_ring": hA, "parent_last_ring": s_lo})
            del t0
    else:
        par = Axis(P, Rp, start_normal)
        sB = [float(par.project(np.asarray(c[0], float)[:1])[0][0]) for c in children]
        belts = []
        for i in range(nk):
            kid = _kid(par, children[i][0], children[i][1], swell, fillet, sB[i], flare)
            F = _Field(par, [kid], "side", ridge)
            rings, hA = _collar(F, 0, ncs[i], fracs, 0.05 * kid["rc"])
            # the flare ring: from each valley vertex out along the parent's bark, away from the child,
            # about half way to where the blend ends (further below the child than above it)
            sC, phC = par.project(rings[0][0])
            cQ, rQ, _, NQ, BQ = par.at(sC)
            nQ = np.cos(phC)[:, None] * NQ + np.sin(phC)[:, None] * BQ
            Q = cQ + nQ * rQ[:, None]
            g = F.grad(Q, lambda X: F.dkid(0, X))
            gt = _norm(g - nQ * (g * nQ).sum(1, keepdims=True))
            sD, phD = par.project(Q + gt * (0.55 * F.kof(0, Q))[:, None])
            sD = np.clip(sD, 0.0, par.L)
            cD, rD, _, ND, BD = par.at(sD)
            nD = np.cos(phD)[:, None] * ND + np.sin(phD)[:, None] * BD
            Dp = F.cast(cD + nD * rD[:, None], nD, 2.5 * kid["k"] * kid["flare"])
            sp, ph = par.project(Dp)
            lim = []
            for sgn, edge in ((-1, sp.min() - 0.5 * kid["rc"]), (1, sp.max() + 0.5 * kid["rc"])):
                s = sB[i]
                for off in np.arange(0.3 * kid["rc"], 14 * kid["rc"], 0.1 * kid["rc"]):
                    s = sB[i] + sgn * off
                    if (s - edge) * sgn >= 0 and F(par.ring(np.clip(s, 0, par.L), sides)[0]).min() >= -1e-4:
                        break
                lim.append(float(np.clip(s, 0.0, par.L)))
            belts.append({"lo": lim[0], "hi": lim[1], "F": F, "rings": rings, "hA": hA, "sp": sp, "ph": ph, "i": i,
                          "D": Dp, "sC": sC, "phC": phC})
        belts.sort(key=lambda q: q["lo"])
        for q0, q1 in zip(belts[:-1], belts[1:]):
            if q1["lo"] < q0["hi"] - 1e-9:
                raise ValueError("two children's collars overlap along the parent (not handled)")
        rp0 = float(Rp.mean())
        st = [(float(s), None) for s in par.s if all(s < q["lo"] - 0.35 * rp0 or s > q["hi"] + 0.35 * rp0 for q in belts)]
        for q in belts:
            st += [(q["lo"], None), (q["hi"], q)]
        st.sort(key=lambda x: x[0])
        ridx = [b.pts(*par.ring(s, sides)) for s, _ in st]
        for r in range(len(st) - 1):
            s0, s1, q = st[r][0], st[r + 1][0], st[r + 1][1]
            va, vb = np.full(sides, s0 / v_tile), np.full(sides, s1 / v_tile)
            if q is None:
                b.strip(ridx[r], ridx[r + 1], sides, range(sides), u_rep, va, vb)
                continue
            i, F, rings = q["i"], q["F"], q["rings"]
            kid = F.kids[0]
            t0 = len(b.tri)
            c0 = _child_skin(b, F, 0, rings, q["hA"], ncs[i], child_u_rep, cvt, Axis(*children[i]).s, cap_ends)
            body = 2 * ncs[i] * (len(fracs) - 1)
            ph0 = float(par.project(kid["X0"][None])[1][0]) % (2 * math.pi)
            ph = ph0 + _wrap(q["ph"] - ph0)
            dphi = 2 * math.pi / sides
            j_lo = int(math.floor((ph.min() - 0.15 * dphi) / dphi))
            j_hi = int(math.ceil((ph.max() + 0.15 * dphi) / dphi))
            j_hi = min(j_hi, j_lo + sides - 1)
            b.strip(ridx[r], ridx[r + 1], sides, range(j_hi, j_lo + sides), u_rep, va, vb)
            Plo, Phi = par.ring(s0, sides)[0], par.ring(s1, sides)[0]
            A = [(ridx[r][j % sides], Plo[j % sides], (j / sides * u_rep, s0 / v_tile)) for j in range(j_lo, j_hi + 1)]
            A += [(ridx[r + 1][j % sides], Phi[j % sides], (j / sides * u_rep, s1 / v_tile)) for j in range(j_hi, j_lo - 1, -1)]
            Dp = q["D"]
            didx = b.pts(Dp, F.grad(Dp))
            phC = ph0 + _wrap(q["phC"] - ph0)
            uvD = np.stack([ph / (2 * math.pi) * u_rep, q["sp"] / v_tile], axis=1)
            uvC = np.stack([phC / (2 * math.pi) * u_rep, q["sC"] / v_tile], axis=1)
            b.strip_uv(didx, c0, uvD, uvC)  # the parent's bark runs up the flare to the valley
            Bl = [(didx[j], Dp[j], tuple(uvD[j])) for j in range(ncs[i])]
            s_c, ph_c, r_c = float(q["sp"].mean()), float(ph.mean()), float(par.at(q["sp"].mean())[1][0])

            def unrolled(X):  # angle round the middle of the cut, on the parent's bark laid flat
                sx, px = par.project(X)
                return np.arctan2(sx - s_c, r_c * (ph0 + _wrap(px - ph0) - ph_c))

            b.stitch(A, Bl, unrolled)
            info["junction_tris"].append(len(A) + len(Bl) + body + 2 * ncs[i] - 2 * (j_hi - j_lo))
            info["ports"].append({"child": i, "first_plain_ring": q["hA"], "parent_rings": (s0, s1)})
            del t0
        if cap_ends:
            c, r, T, _, _ = par.at(par.L)
            tip = b.pts(c + T * r[0] * 0.6, T)[0]
            b.tips.append(tip)
            for j in range(sides):
                b.add(ridx[-1][j], ridx[-1][(j + 1) % sides], tip, (j / sides * u_rep, par.L / v_tile),
                      ((j + 1) / sides * u_rep, par.L / v_tile), ((j + 0.5) / sides * u_rep, par.L / v_tile + 0.1))

    V, Fo, UV, N, T = b.finish()
    # checks: every edge of the skin is shared by two triangles (but the parent's open base), and no
    # vertex lies below the plain limbs
    e = np.sort(np.concatenate([T[:, [0, 1]], T[:, [1, 2]], T[:, [2, 0]]]), axis=1)
    _, cnt = np.unique(e, axis=0, return_counts=True)
    info["open_edges"] = int((cnt == 1).sum())
    info["bad_edges"] = int((cnt > 2).sum())
    allP = np.concatenate(b.P)
    bare = Axis(P, Rp).dist(allP)
    for c in children:
        bare = np.minimum(bare, Axis(np.asarray(c[0], float), np.asarray(c[1], float)).dist(allP))
    bare[b.tips] = 0.0  # the cone tips that close the ends sit inside the capsules' round ends
    info["min_cover"] = float(bare.min())
    info["tris"] = int(len(Fo))
    return V, Fo, UV, N, info
