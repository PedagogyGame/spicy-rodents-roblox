"""Leaf canopies made of sprays (numpy only; no bpy). Species done: oak, elm.

Units are studs, Roblox axes (+Y up), in whatever frame the caller's points are in (the generator
uses the tree's pivot). The module knows nothing about the generator: it takes twig tips and the
small branches they sit on and returns plain arrays.

    res = build_canopy(tips, branches, "oak", budget=14000, routes=[(polyline, radius), ...], seed=7)
    for part in ("LeavesShade", "LeavesMid", "LeavesSun"):
        V, F, UV, N = res["parts"][part]          # treegen.Mesh().add(V, F, UV, N) takes them as they are

How a canopy is made
  1. Every twig tip gets a share of the spray budget (more at the outside and the top of the crown,
     a little along the outer part of the small branches). From the tip a few generations of
     twiglets grow (they fork, kink, turn up for the oak, arch over and hang for the elm); the
     twiglets carry no mesh of their own: each spray card has its twig painted down its middle
     (the polylines are returned as res["twigs"] in case the bark wants to mesh the thickest).
  2. A spray is a bent card (3 rows, 4 triangles) lying like a shingle on the crown, plus up to
     three smaller cards (2 triangles each) that stand out of its plane along the twig, so a spray
     has depth from every side. Cards face out of the crown (winding), and their normals are bent
     toward the direction out of the crown's centre and out of their own clump, so the mass shades
     softly while every clump still reads as a volume.
  3. No vertex of a card (nor the probes between them) comes within a route's clearance radius: a
     spray that would is first made smaller, then left out. The tunnels stay open.
  4. Sprays are sorted by how much foliage lies above and outside them into LeavesSun (outer),
     LeavesMid and LeavesShade (inner, simpler cards), and the most buried ones are dropped until
     the triangle budget holds.

UVs: the species' atlas (canopy_textures.py) is 2 x 2 cells; each cell holds one spray whose twig
rises from the middle of the cell's lower edge. v = 0 is the bottom of the image.
"""
import math

import numpy as np

Y = np.array([0.0, 1.0, 0.0])
PARTS = ("LeavesShade", "LeavesMid", "LeavesSun")
LEAF_BUDGET = 14000

# card      spray card (length, width), studs, for a crown of about 25 studs radius (x scale)
# droop     how far the tip of a card falls below its plane, as a fraction of its length
# up/out    how hard twiglets turn up / away from the crown's axis per node
# sag       how hard twiglets hang, growing with every generation (the elm's pendulous tips)
# fork      angle between a twiglet and its children, degrees
# flat      0 = children fork all round the parent, 1 = they fork in a level fan (layered foliage)
# per_tip   most sprays one twig tip may carry             step  node spacing / card length
# side      share of the budget spent along the small branches (inside the crown)
# sun/shade share of the sprays that go to LeavesSun / LeavesShade
SPECIES = {
    "oak": dict(card=(6.6, 6.4), droop=0.14, up=0.20, out=0.10, sag=0.00, fork=(38, 66), flat=0.30, per_tip=48,
                step=0.50, side=0.16, sun=0.42, shade=0.24, jitter=0.26),
    "elm": dict(card=(5.7, 5.3), droop=0.34, up=0.05, out=0.16, sag=0.11, fork=(26, 46), flat=0.65, per_tip=48,
                step=0.56, side=0.12, sun=0.40, shade=0.24, jitter=0.18),
}


def _norm(v):
    v = np.asarray(v, float)
    return v / np.maximum(np.linalg.norm(v, axis=-1, keepdims=True), 1e-12)


def _rotate(v, axis, ang):
    axis = _norm(axis)
    c, s = math.cos(ang), math.sin(ang)
    return v * c + np.cross(axis, v) * s + axis * np.dot(axis, v) * (1 - c)


def _seg_dist(p, A, B):
    AB = B - A
    l2 = np.maximum((AB * AB).sum(1), 1e-12)
    AP = p[:, None, :] - A[None, :, :]
    t = np.clip((AP * AB[None]).sum(2) / l2[None], 0, 1)
    C = A[None] + t[..., None] * AB[None]
    return np.linalg.norm(p[:, None, :] - C, axis=2)


class Tunnels:
    """The routes' keep-out capsules: clearance(P) = min over routes of (distance - radius)."""

    def __init__(self, routes):
        A, B, r = [], [], []
        for line, rad in routes or ():
            P = np.asarray(line, float)
            if len(P) == 1:
                P = np.concatenate([P, P])
            A.append(P[:-1])
            B.append(P[1:])
            r.append(np.full(len(P) - 1, float(rad)))
        self.A = np.concatenate(A) if A else np.zeros((0, 3))
        self.B = np.concatenate(B) if B else np.zeros((0, 3))
        self.r = np.concatenate(r) if r else np.zeros(0)

    def clearance(self, P):
        P = np.atleast_2d(np.asarray(P, float))
        if not len(self.A):
            return np.full(len(P), 1e9)
        out = np.empty(len(P))
        for i in range(0, len(P), 4096):
            out[i : i + 4096] = (_seg_dist(P[i : i + 4096], self.A, self.B) - self.r[None]).min(1)
        return out


def _parse_tips(tips):
    P, D, R = [], [], []
    for t in tips:
        if isinstance(t, dict):
            p, d, r = t["pos"], t["dir"], t.get("thickness", 0.2)
        elif len(t) == 3 and np.ndim(t[0]) == 1:
            p, d, r = t
        else:
            t = np.asarray(t, float)
            p, d, r = t[0:3], t[3:6], (t[6] if len(t) > 6 else 0.2)
        P.append(np.asarray(p, float))
        D.append(_norm(d))
        R.append(float(r))
    return np.array(P).reshape(-1, 3), np.array(D).reshape(-1, 3), np.array(R)


def _branch_pts(b):
    if isinstance(b, dict):
        b = b["pts"]
    return np.asarray(b, float)[:, :3]


def crown_frame(P):
    """Centre (low in the crown, on its axis), horizontal radius, bottom and top of the tip cloud."""
    lo, hi = P[:, 1].min(), P[:, 1].max()
    cx, cz = P[:, 0].mean(), P[:, 2].mean()
    rh = float(np.percentile(np.hypot(P[:, 0] - cx, P[:, 2] - cz), 92)) + 1e-6
    return np.array([cx, lo + 0.25 * (hi - lo), cz]), rh, float(lo), float(hi)


def build_canopy(tips, branches, species, budget=LEAF_BUDGET, routes=(), seed=0, scale=None, floor_y=None,
                 crown=None, blocked=None, margin=0.3):
    """Leaf sprays for one tree.

    tips      twig tips: a sequence of (pos (3,), dir (3,), thickness) tuples, {"pos", "dir", "thickness"}
              dicts, or rows [x, y, z, dx, dy, dz, thickness]. Studs; dir need not be unit.
    branches  the small branches the tips sit on: a sequence of polylines (k, 3) (or (k, 4) with the
              radius last, or {"pts": ...}), root first. Sparse inner sprays hang along their outer half.
              May be empty.
    species   "oak" | "elm"
    budget    most triangles for the three leaf parts together (default 14000)
    routes    climbing routes as [(polyline (m, 3), clearance radius in studs), ...]: capsules no
              leaf may enter. Pass the line the squirrel's BODY follows (rail + lift + ~0.9 on a
              bough) with ~2.6 st, and the trunk's axis with bark radius + ~3.3 st (Trees.luau: 1.6 st
              round the body on a bough, 2.2 st off the trunk's climbing surface).
    seed      int; the same inputs and seed give the same canopy
    scale     spray size factor; default crown radius / 25 clipped to 0.55..1.3
    floor_y   no leaf below this height (default: none)
    crown     (centre (3,), horizontal radius) if the caller knows better than the tip cloud
    blocked   optional callable (points (n, 3)) -> bool (n,): True where no leaf may be (buildings)
    margin    extra studs kept from every tunnel (default 0.3)

    Returns a dict:
      "parts"  {"LeavesShade" | "LeavesMid" | "LeavesSun": (V (n,3) float, F (m,3) int, UV (n,2), N (n,3) unit)}
               (empty arrays for a part without sprays); F indexes that part's V; faces wind so
               that their front looks out of the crown. Draw double-sided with the atlas alpha.
      "twigs"  [polyline (k, 3)]: the painted twiglets grown from the tips (no mesh)
      "stats"  {"tris": {part: n, "total": n}, "sprays", "sprays_wanted", "dropped_tunnel",
                "dropped_budget", "min_clearance" (studs between any leaf vertex and a tunnel wall; >= margin),
                "crown": {"centre", "radius"}}
    """
    par = SPECIES[species]
    rng = np.random.default_rng(seed)
    TP, TD, TR = _parse_tips(tips)
    BR = [_branch_pts(b) for b in (branches or ())]
    if not len(TP):
        z = (np.zeros((0, 3)), np.zeros((0, 3), np.int64), np.zeros((0, 2)), np.zeros((0, 3)))
        return {"parts": {p: z for p in PARTS}, "twigs": [], "stats": {"tris": {"total": 0}, "sprays": 0}}
    ctr, rh, ylo, yhi = crown_frame(TP)
    if crown is not None:
        ctr, rh = np.asarray(crown[0], float), float(crown[1])
    if scale is None:
        scale = float(np.clip(rh / 25.0, 0.55, 1.3))
    cl, cw = par["card"][0] * scale, par["card"][1] * scale
    span = max(yhi - ctr[1], 4.0)
    tun = Tunnels(routes)

    def outward(p):
        rel = p - ctr
        o = np.array([rel[0], 0.0, rel[2]])
        return _norm(o + 1e-6), min(float(np.hypot(rel[0], rel[2])) / rh, 1.4), float(np.clip(rel[1] / span, -0.5, 1.2))

    # ---- 1. sprays per anchor -------------------------------------------------------------------
    n_total = int(budget / 7.1)
    w = np.empty(len(TP))
    for i, p in enumerate(TP):
        _, rho, h = outward(p)
        w[i] = 0.55 + 0.9 * rho + 0.5 * max(h, 0.0)  # denser at the outside and on top
    n_side = int(n_total * par["side"]) if BR else 0
    share = w / w.sum() * (n_total - n_side)
    share = np.minimum(share, par["per_tip"])
    counts = np.floor(share).astype(int) + (rng.random(len(TP)) < (share - np.floor(share)))

    sprays = []  # dicts: base, d, size, anchor (clump centre), gen
    twigs = []

    def add_spray(base, d, size, anchor, gen):
        sprays.append({"base": np.asarray(base, float), "d": _norm(d), "size": size, "anchor": anchor, "gen": gen})

    def fan(p, d, n, anchor, gen):
        """n sprays round a twiglet's end: one straight on, the others to the sides."""
        sv = _norm(np.cross(d, Y) + 1e-9)
        for q in range(n):
            a = 0.0 if q == 0 else (1 if q % 2 else -1) * rng.uniform(0.75, 1.15) * (1 + 0.5 * ((q - 1) // 2))
            dd = _norm(d * math.cos(a) + sv * math.sin(a) + Y * rng.uniform(-0.12, 0.28) + rng.normal(0, 0.08, 3))
            add_spray(p + rng.normal(0, 0.12 * scale, 3), dd, rng.uniform(0.86, 1.14), anchor, gen)

    def grow(p, d, n, anchor, gen):
        if n <= 0:
            return
        if n <= 3:
            fan(p, d, n, anchor, gen)
            return
        out, rho, h = outward(p)
        nodes = 2 if n < 14 else 3
        step = par["step"] * cl * rng.uniform(0.85, 1.2)
        pts = [p]
        cur, dr = p, d
        used = 0
        sgn = 1 if rng.random() < 0.5 else -1
        for _ in range(nodes):
            dr = _norm(dr + Y * (par["up"] - par["sag"] * (gen + 1) * (0.5 + rho)) + out * par["out"] + rng.normal(0, par["jitter"], 3))
            cur = cur + dr * step
            pts.append(cur)
            if used < n - 3:
                sv = _norm(np.cross(dr, Y) + 1e-9)
                dd = _norm(dr * 0.45 + sv * sgn * 0.9 + Y * rng.uniform(-0.15, 0.3))
                add_spray(cur + rng.normal(0, 0.1 * scale, 3), dd, rng.uniform(0.82, 1.05), anchor, gen)
                used += 1
                sgn = -sgn
        twigs.append(np.array(pts))
        rest = n - used
        kids = 2 if rest < 9 else 3
        cut = np.sort(rng.uniform(0.25, 0.75, kids - 1))
        parts = np.diff(np.concatenate([[0.0], cut, [1.0]]))
        ns = np.maximum(1, np.round(parts * rest).astype(int))
        ns[0] += rest - ns.sum()
        base_ax = _norm(np.cross(dr, Y) + 1e-9)
        roll0 = rng.uniform(0, 2 * math.pi)
        for k in range(kids):
            if ns[k] <= 0:
                continue
            ang = math.radians(rng.uniform(*par["fork"])) * (0.35 if k == 0 and kids == 3 else 1.0)
            roll = roll0 + k * 2 * math.pi / kids + rng.normal(0, 0.3)
            ax = _rotate(base_ax, dr, roll)
            # flat: fork about the vertical axis instead (a level fan)
            ax = _norm(ax * (1 - par["flat"]) + Y * par["flat"] * (1 if math.cos(roll) >= 0 else -1))
            grow(cur, _rotate(dr, ax, ang), int(ns[k]), anchor, gen + 1)

    for i in np.argsort(-w):
        if counts[i] > 0:
            grow(TP[i], TD[i], int(counts[i]), TP[i] + TD[i] * 1.2 * cl, 0)
    # sparse inner sprays along the outer half of the small branches
    if n_side:
        cand = []
        for b in BR:
            if len(b) < 2:
                continue
            seg = np.linalg.norm(np.diff(b, axis=0), axis=1)
            s = np.concatenate([[0.0], np.cumsum(seg)])
            for sv_ in np.arange(0.45 * s[-1], 0.95 * s[-1], max(0.5 * cl, 1.0)):
                p = np.array([np.interp(sv_, s, b[:, k]) for k in range(3)])
                j = min(int(np.searchsorted(s, sv_)), len(b) - 1)
                cand.append((p, _norm(b[j] - b[j - 1])))
        rng.shuffle(cand)
        sgn = 1
        for p, t in cand[:n_side]:
            sv = _norm(np.cross(t, Y) + 1e-9)
            add_spray(p, t * 0.5 + sv * sgn * 0.9 + Y * rng.uniform(-0.1, 0.35), rng.uniform(0.85, 1.1), p, 0)
            sgn = -sgn
    wanted = len(sprays)

    # ---- 2. cards ---------------------------------------------------------------------------------
    def make(sp, size_k=1.0):
        base, d = sp["base"], sp["d"]
        out, rho, h = outward(base)
        ks = float(np.clip(0.10 + 1.15 * rho - 0.55 * max(h, 0), 0.05, 1.25))
        nt = _norm(out * ks + Y * (1.0 - 0.3 * rho) + rng.normal(0, 0.22, 3))
        # the spray leans down the outside of the crown like a shingle
        d = _norm(d * 0.8 + (out * 0.5 - Y * 0.5) * rho * (0.5 + par["droop"]))
        nt = nt - d * np.dot(nt, d)
        if np.linalg.norm(nt) < 1e-3:
            nt = np.cross(d, [0.3, 0.1, 0.9])
        nt = _norm(nt)
        side = np.cross(d, nt)
        # sun leaves are smaller, shade leaves larger
        size = sp["size"] * size_k * (1.10 - 0.22 * np.clip(0.6 * rho + 0.4 * max(h, 0), 0, 1))
        L, W = cl * size, cw * size * rng.uniform(0.9, 1.1)
        droop = par["droop"] * rng.uniform(0.5, 1.5) + 0.10 * rho
        tw = rng.normal(0, 0.28)
        base = base - d * 0.04 * L
        V, UV = [], []
        ctrs = []
        for k in range(3):
            t = k / 2
            c = base + d * L * t - nt * droop * L * t * t + nt * 0.06 * L * math.sin(t * math.pi)
            sd = _rotate(side, d, tw * (t - 0.4))
            V += [c - sd * W * 0.5, c + sd * W * 0.5]
            UV += [(0.0, t), (1.0, t)]
            ctrs.append(c)
        cards = [{"V": np.array(V), "UV": np.array(UV), "F": np.array([(0, 1, 3), (0, 3, 2), (2, 3, 5), (2, 5, 4)]), "n": nt,
                  "cell": int(rng.integers(0, 4))}]
        tufts = []
        for j, t in enumerate((0.30, 0.55, 0.80)):
            c = base + d * L * t - nt * droop * L * t * t
            sg = 1 if (j + sp["gen"]) % 2 == 0 else -1
            dt = _norm(d * rng.uniform(0.3, 0.6) + nt * rng.uniform(0.55, 0.95) + side * sg * rng.uniform(0.25, 0.8))
            w2 = _norm(np.cross(dt, d))
            Lt, Wt = 0.5 * L * rng.uniform(0.85, 1.05), W * rng.uniform(0.8, 0.95)
            c = c - dt * 0.06 * Lt
            Vt = np.array([c - w2 * Wt * 0.5, c + w2 * Wt * 0.5, c + dt * Lt - w2 * Wt * 0.5, c + dt * Lt + w2 * Wt * 0.5])
            tufts.append({"V": Vt, "UV": np.array([(0.0, 0.5), (1.0, 0.5), (0.0, 1.0), (1.0, 1.0)]),
                          "F": np.array([(0, 1, 3), (0, 3, 2)]), "n": _norm(np.cross(w2, dt)), "cell": int(rng.integers(0, 4))})
        return {"cards": cards, "tufts": tufts, "c": np.array(ctrs).mean(0), "ctrs": np.array(ctrs), "anchor": sp["anchor"]}

    def probes(s):
        P = [c["V"] for c in s["cards"] + s["tufts"]]
        main = s["cards"][0]["V"]
        P += [s["ctrs"], (main[:-2] + main[2:]) / 2, (main[0::2][:-1] + main[1::2][1:]) / 2]
        return np.concatenate(P)

    def bad(s):
        P = probes(s)
        if tun.clearance(P).min() < margin:
            return True
        if floor_y is not None and P[:, 1].min() < floor_y:
            return True
        return blocked is not None and bool(np.any(blocked(P)))

    built, dropped_tunnel = [], 0
    for sp in sprays:
        s = make(sp)
        if bad(s):
            s = make(sp, 0.6)
            if bad(s):
                dropped_tunnel += 1
                continue
        built.append(s)

    # ---- 3. light layers and the budget -------------------------------------------------------------
    empty = (np.zeros((0, 3)), np.zeros((0, 3), np.int64), np.zeros((0, 2)), np.zeros((0, 3)))
    stats = {"sprays_wanted": wanted, "dropped_tunnel": dropped_tunnel, "dropped_budget": 0,
             "crown": {"centre": [round(float(x), 2) for x in ctr], "radius": round(rh, 2)}, "scale": round(scale, 3)}
    if not built:
        stats.update(sprays=0, tris={"total": 0}, min_clearance=None)
        return {"parts": {p: empty for p in PARTS}, "twigs": twigs, "stats": stats}
    C = np.array([s["c"] for s in built])
    rel = C - ctr[None]
    radial = _norm(rel * np.array([1.0, 1.2, 1.0]) + Y * 0.08 * rh)
    cover = np.zeros(len(C))
    for i in range(0, len(C), 512):
        dv = C[None, :, :] - C[i : i + 512, None, :]
        dist = np.linalg.norm(dv, axis=2)
        ahead = (dv * (radial[i : i + 512, None, :] * 0.6 + Y * 0.4)).sum(2)
        cover[i : i + 512] = ((ahead > 0.25 * cl) & (dist < 2.2 * cl) & (ahead > 0.6 * dist)).sum(1)
    hrel = (C[:, 1] - C[:, 1].min()) / max(float(np.ptp(C[:, 1])), 1e-6)
    score = cover - 2.0 * hrel + rng.normal(0, 0.7, len(C))
    order = np.argsort(score)  # most exposed first
    n_sun, n_shade = int(par["sun"] * len(C)), int(par["shade"] * len(C))
    layer = np.full(len(C), 1)
    layer[order[:n_sun]] = 2
    layer[order[len(C) - n_shade :]] = 0
    ntuft = np.where(layer == 2, 3, np.where(layer == 1, 2, 0))
    tris = 4 + 2 * ntuft
    keep = np.ones(len(C), bool)
    total = int(tris.sum())
    for i in order[::-1]:  # the most buried go first
        if total <= budget:
            break
        keep[i] = False
        total -= int(tris[i])
        stats["dropped_budget"] += 1

    acc = {p: {"V": [], "F": [], "UV": [], "N": [], "n": 0} for p in PARTS}
    for i, s in enumerate(built):
        if not keep[i]:
            continue
        a = acc[PARTS[layer[i]]]
        clump = _norm(s["c"] - s["anchor"] + radial[i] * 0.5 * cl)
        soft = _norm(radial[i] * 0.45 + clump * 0.30 + Y * 0.10)
        for cd in s["cards"] + s["tufts"][: ntuft[i]]:
            V, F = cd["V"], cd["F"]
            n = cd["n"]
            if np.dot(n, radial[i] + Y * 0.3) < 0:  # the front of every card looks out of the crown
                n = -n
            g = np.cross(V[F[0][1]] - V[F[0][0]], V[F[0][2]] - V[F[0][0]])
            if np.dot(g, n) < 0:
                F = F[:, ::-1]
            N = _norm(soft[None] * 0.8 + n[None] * 0.2 + 0.22 * _norm(V - s["c"][None]))
            q = cd["cell"]
            u0, v0 = (q % 2) * 0.5 + 0.004, (q // 2) * 0.5 + 0.004
            UV = np.stack([u0 + 0.492 * cd["UV"][:, 0], v0 + 0.492 * cd["UV"][:, 1]], axis=1)
            a["V"].append(V)
            a["F"].append(F + a["n"])
            a["UV"].append(UV)
            a["N"].append(N)
            a["n"] += len(V)
    parts, tri_stats, allv = {}, {}, []
    for p in PARTS:
        a = acc[p]
        if a["V"]:
            parts[p] = (np.concatenate(a["V"]), np.concatenate(a["F"]).astype(np.int64), np.concatenate(a["UV"]), _norm(np.concatenate(a["N"])))
            allv.append(parts[p][0])
        else:
            parts[p] = empty
        tri_stats[p] = int(len(parts[p][1]))
    tri_stats["total"] = int(sum(tri_stats.values()))
    stats["tris"] = tri_stats
    stats["sprays"] = int(keep.sum())
    mc = float(tun.clearance(np.concatenate(allv)).min()) if allv and len(tun.A) else None
    stats["min_clearance"] = None if mc is None else round(mc, 3)
    return {"parts": parts, "twigs": twigs, "stats": stats}
