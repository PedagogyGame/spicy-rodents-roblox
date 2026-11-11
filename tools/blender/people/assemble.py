"""Sculpt components -> one triangle mesh per part (numpy only), and the texture atlas layout.

mesh_part() casts every component's grid, measures or reuses its UV metrics, orients the triangles,
leaves out the triangles that lie wholly inside a sibling component (the base of an ear, a thumb or a
ponytail) and returns arrays; mirror() makes the right-hand limb. pack() lays the charts' rectangles
out on shelves at one texel density.
"""
import numpy as np

import mesher
import sdf

F32 = np.float32


def mesh_part(comps, metrics=None, hidden_margin=0.012):
    """comps: [sculpt.Comp]. metrics: {chart name: (S, T, size)} from the reference build, or None to
    measure this one. Returns dict(V, N, tris, uv (per-corner, chart-local), chart (per tri), charts)."""
    Vs, Ns, Ts, UVs, Cs = [], [], [], [], []
    off = 0
    for ci, comp in enumerate(comps):
        ch = comp.chart
        V = ch.vertices(comp.lo)
        if comp.fix is not None:
            V = comp.fix(V)
        N = mesher.gradient(comp.lo, V)
        if metrics is not None and ch.name in metrics:
            ch.S, ch.T, ch.size = metrics[ch.name]
        else:
            ch.measure(V)
        tris, uvs = ch.faces()
        if mesher.orient(V, tris, N):
            tris, uvs = tris[:, [0, 2, 1]], uvs[:, [0, 2, 1]]
        if comp.cull and len(comps) > 1:
            f = np.full(len(V), 1e9, dtype=F32)
            for other in comps:
                if other is not comp:
                    f = np.minimum(f, mesher.field(other.lo, V))
            hidden = (f[tris] < -hidden_margin).all(axis=1)
            tris, uvs = tris[~hidden], uvs[~hidden]
        Vs.append(V)
        Ns.append(N)
        Ts.append(tris + off)
        UVs.append(uvs)
        Cs.append(np.full(len(tris), ci, dtype=np.int32))
        off += len(V)
    V, N, tris = np.concatenate(Vs), np.concatenate(Ns), np.concatenate(Ts)
    uv, tc = np.concatenate(UVs), np.concatenate(Cs)
    used = np.zeros(len(V), dtype=bool)
    used[tris.reshape(-1)] = True
    remap = np.cumsum(used) - 1
    return {"V": V[used], "N": N[used], "tris": remap[tris], "uv": uv, "chart": tc,
            "charts": [c.chart.name for c in comps]}


def metrics_of(comps):
    return {c.chart.name: (c.chart.S.copy(), c.chart.T.copy(), c.chart.size) for c in comps}


def mirror(m):
    """The right-hand copy of a left-hand part: x -> -x, winding flipped, the same UVs."""
    out = dict(m)
    out["V"] = m["V"] * np.array([-1, 1, 1], dtype=F32)
    out["N"] = m["N"] * np.array([-1, 1, 1], dtype=F32)
    out["tris"] = m["tris"][:, [0, 2, 1]]
    out["uv"] = m["uv"][:, [0, 2, 1]]
    return out


def detail_body(comps, blend=0.045):
    """One sculpt for the whole part (each component's finer sculpt, later components blended in):
    what the normal map is baked from."""
    prims = []
    for i, comp in enumerate(comps):
        first = True
        for p in comp.hi.prims:
            if i > 0 and first and p.op == "add":
                q = type(p).__new__(type(p))
                q.__dict__.update(p.__dict__)
                q.k = max(p.k, blend)
                p = q
            first = False
            prims.append(p)
    return sdf.Body(prims, band=0.05)


def pack(sizes, res, gutter=6, density=None, order=None):
    """Shelf-pack rectangles (name -> (width, height) in studs) into a res x res atlas at one texel
    density (texels per stud; the largest that fits when None). Returns ({name: (u0, v0, u1, v1)},
    density). Rects are in UV (v up)."""
    names = order or sorted(sizes, key=lambda n: -sizes[n][1])

    def layout(d):
        x = y = gutter
        row_h = 0
        rects = {}
        for n in names:
            w, h = int(round(sizes[n][0] * d)), int(round(sizes[n][1] * d))
            w, h = max(w, 4), max(h, 4)
            if x + w + gutter > res:
                x = gutter
                y += row_h + gutter
                row_h = 0
            if x + w + gutter > res or y + h + gutter > res:
                return None
            rects[n] = (x, y, x + w, y + h)
            x += w + gutter
            row_h = max(row_h, h)
        return rects

    if density is None:
        lo, hi = 1.0, 4000.0
        for _ in range(40):
            mid = (lo + hi) / 2
            if layout(mid) is None:
                hi = mid
            else:
                lo = mid
        density = lo
    rects = layout(density)
    if rects is None:
        raise ValueError("atlas does not fit")
    out = {n: (x0 / res, 1 - y1 / res, x1 / res, 1 - y0 / res) for n, (x0, y0, x1, y1) in rects.items()}
    return out, density


def atlas_uv(m, rects):
    """Chart-local corner UVs -> atlas UVs."""
    uv = np.empty_like(m["uv"])
    for ci, name in enumerate(m["charts"]):
        sel = m["chart"] == ci
        u0, v0, u1, v1 = rects[name]
        uv[sel, :, 0] = u0 + m["uv"][sel, :, 0] * (u1 - u0)
        uv[sel, :, 1] = v0 + m["uv"][sel, :, 1] * (v1 - v0)
    return uv
