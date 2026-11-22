"""Independent check of the promises a built tree makes to the game (headless bpy, no treegen import).

  PY=/root/.cache/spicy-rodents/venv/bin/python
  nice -n 10 $PY -I tools/blender/trees/check_promises.py --dir build/art/trees --ids 0,40
  nice -n 10 $PY -I tools/blender/trees/check_promises.py --dir build/art/trees            (every tree_NNN.json there)

Input per tree: tree_NNN.json (pivot, routes, parts, tris: what build_trees.py writes) and tree_NNN.fbx
(build_trees.py --fbx). From Blender objects instead: check_tree(info, {name: (V_roblox_world, F)}, routes).
Exit status 1 when any promise is broken, 0 otherwise. --json PATH also writes the numbers.

What is measured, every STEP (0.25 stud) of arc length along every route of the tree. The centre line is
the game's own: centripetal Catmull-Rom through the harvested control points with three.js r160's
200-division arc-length table (src/shared/Routes/Curve.luau), t = arc-length fraction = railT, in studs
(data/harvest/routes.json is in HTML units, 1 u = 2.5 studs).

TRUNK (src/shared/Routes/Motion.luau visualPose, kind "trunk"; src/shared/Movement/SquirrelVisual.luau frame):
  tapered(t) = max(0.32 u, r (1 - 0.48 t))             r = surfaceRadius (1.3 u when 0)
  giants     = max(0.45 u, r / 0.95 - 1.05 u t)        name contains "giant trunk"
  visualPose puts the body at tapered + 0.28 u from the centre line along the horizontal bark normal;
  SquirrelVisual.frame pulls it back in by 0.28 u - barkGap (0.3 stud), so the paws are drawn at
  tapered + 0.3 stud. The bark is therefore expected at horizontal radius tapered(t) all the way round
  (the normal is whichever side the squirrel mounted from): 16 horizontal rays per sample,
  error = bark radius - tapered(t). + : the bark stands proud (the paws sink once it passes +0.3),
  - : the bark is thin (the squirrel floats). Rays that land on a bough's own bark (within JUNCTION of a
  bough centre line) are counted apart as junction rays; samples below the root-flare height
  max(2.5, 1.2 tapered(0)) studs are reported apart: there the squirrel climbs too, so a ray off by more than
  FLARE_FAIL (0.5 stud: the paws deep in a buttress) fails, and one off by more than 0.1 warns.
BOUGH (visualPose, kinds branch / bridge / lookout):
  feet = centre line + (0, lift, 0); lift = visualOffset, else 0.61 u on a lookout, else 0.5 u
  a branch with trunkClearance, while t < 0.2: feet also move horizontally along (pointAt(0.16) -
  pointAt(0)) by (trunkClearance + 0.31 u) (1 - t / 0.2)^2
  Every bark surface in the vertical column through the feet (6 studs up and down); the one the squirrel
  stands on is the upward-facing surface nearest the feet; error = feet height - that surface.
  + : floats above the bark, - : sinks into it. The stretch where a branch's feet are pushed off the centre
  line (t < 0.2, "clr" columns) is reported apart from the rest of the bough; both fail unless
  --clearance-warn. With --clearance-warn that stretch is measured on the bough's own top line instead
  (centre line + lift, where the game draws the squirrel: SquirrelVisual.junctionT), which fails like the rest
  of the bough. The game does so only on a branch whose centre line is trunkClearance out from its start (level)
  by collarMax (0.7) of the stretch; on a branch that gets clear later ("late collar": junctionT is nil) the game
  draws the squirrel at the pushed pose, and those pushed feet are reported apart, as a known game-side issue
  (warn only: the bark cannot be under both). Where two walks of the tree cross (another walk's top line within
  0.8 stud of the column and at most 0.8 over the feet, the wood found over them no higher than 0.15 above that
  line), wood over the feet is that walk's own bough: those samples are counted apart and only warn, as long as
  the wood is at most CROSS_DEEP (0.5) over the feet and for at most CROSS_RUN (4) samples in a row; deeper or
  longer, they fail like any other. Samples whose feet are still over the trunk (inside
  tapered(t) + 0.1 of the trunk centre line) stand on trunk bark and are counted apart.
TUNNEL (src/worldgen/Builders/Trees.luau header and clear()): no leaf geometry within 1.6 studs of the
  squirrel's body line on a bough (centre line + 2 studs up), nor within 2.2 studs of the trunk's climbing
  surface (distance to the trunk centre line < tapered + 2.2). Measured to the leaf triangles themselves
  (card geometry, not the alpha-cut texels: a card corner inside the tunnel counts even if transparent).
BUDGET: Bark <= 8,000 triangles (12,000 on the named and giant trees), all parts named Leaves* together <= 6,000.
PARTS: names within Bark / LeavesShade / LeavesMid / LeavesSun / Apples, Bark present, and the mesh
  bounds equal to the json's "parts" (centre and size relative to the pivot, Roblox axes) within 0.01.
"""
import argparse
import glob
import json
import math
import os
import re
import sys

import numpy as np

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
SPU = 2.5
STEP = 0.25
TOL = 0.1
RAYS = 16
JUNCTION = 2.2  # a trunk ray landing this near a bough centre line hit the bough, not the trunk
BARK_BUDGET = 8000  # treegen.py BARK_BUDGET (street, park, estate, apple trees)
BARK_BUDGET_BIG = 12000  # the named trees and the giants (treegen.py BARK_BUDGET_BIG)
BIG_CATEGORIES = ("named", "giant")
LEAF_BUDGET = 6000
PART_NAMES = ("Bark", "LeavesShade", "LeavesMid", "LeavesSun", "Apples")
# Motion.C / SquirrelVisual.params, in studs
TRUNK_MIN_R = 0.32 * SPU
TRUNK_TAPER = 0.48
GIANT_MIN_R = 0.45 * SPU
GIANT_TAPER = 1.05 * SPU
DEFAULT_R = 1.3 * SPU
BARK_GAP = 0.3
BRANCH_LIFT = 0.5 * SPU
LOOKOUT_LIFT = 0.61 * SPU
CLEARANCE_PAD = 0.31 * SPU
CLEARANCE_T = 0.2
CLEARANCE_SAMPLE_T = 0.16
BOUGH_TUNNEL = 1.6
BODY_UP = 2.0
TRUNK_TUNNEL = 2.2
CROSSING = 0.8  # studs, level: another walk's top line this near the column through the feet ...
CROSSING_UP = 0.8  # ... and no higher than this over them: the two walks cross there
CROSS_DEEP = 0.5  # studs: a crossing's wood over the feet no deeper than this ...
CROSS_RUN = 4  # ... for no more samples in a row (0.25 stud each) only warns
FLARE_FAIL = 0.5  # studs: a root-flare ray off by more than this fails (the squirrel climbs there too)
COLLAR_MAX = 0.7  # SquirrelVisual.params.collarMax


# ---- the game's curve (three.js r160 CatmullRomCurve3, centripetal; Curve.luau) --------------------

class Curve:
    def __init__(self, pts):
        self.p = np.asarray(pts, float)
        ts = np.linspace(0.0, 1.0, 201)
        P = np.array([self.raw(t) for t in ts])
        self.lengths = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(P, axis=0), axis=1))])
        self.length = float(self.lengths[-1])

    def raw(self, t):
        pts = self.p
        n = len(pts)
        p = (n - 1) * t
        i = int(math.floor(p))
        w = p - i
        if w == 0 and i == n - 1:
            i, w = n - 2, 1.0
        p0 = pts[i - 1] if i > 0 else pts[0] - pts[1] + pts[0]
        p1, p2 = pts[i], pts[i + 1]
        p3 = pts[i + 2] if i + 2 < n else pts[n - 1] - pts[n - 2] + pts[n - 1]
        dt0 = float(np.sum((p0 - p1) ** 2)) ** 0.25
        dt1 = float(np.sum((p1 - p2) ** 2)) ** 0.25
        dt2 = float(np.sum((p2 - p3) ** 2)) ** 0.25
        if dt1 < 1e-4:
            dt1 = 1.0
        if dt0 < 1e-4:
            dt0 = dt1
        if dt2 < 1e-4:
            dt2 = dt1
        t1 = ((p1 - p0) / dt0 - (p2 - p0) / (dt0 + dt1) + (p2 - p1) / dt1) * dt1
        t2 = ((p2 - p1) / dt1 - (p3 - p1) / (dt1 + dt2) + (p3 - p2) / dt2) * dt1
        c2 = -3 * p1 + 3 * p2 - 2 * t1 - t2
        c3 = 2 * p1 - 2 * p2 + t1 + t2
        return p1 + t1 * w + c2 * w * w + c3 * w * w * w

    def at(self, u):
        """Arc-length parameterised point (getPointAt: table lookup, linear inside the division)."""
        target = min(max(u, 0.0), 1.0) * self.length
        L = self.lengths
        i = int(np.searchsorted(L, target, side="right")) - 1
        i = min(max(i, 0), 199)
        seg = L[i + 1] - L[i]
        f = (target - L[i]) / seg if seg > 0 else 0.0
        return self.raw((i + f) / 200.0)


def load_routes(repo=REPO):
    with open(os.path.join(repo, "data", "harvest", "routes.json")) as fh:
        return {r["id"]: r for r in json.load(fh)["routes"]}


def trunk_radius(route, t):
    r = (route.get("surfaceRadius") or 0) * SPU
    if r <= 0:
        r = DEFAULT_R
    if "giant trunk" in route["name"].lower():
        return max(GIANT_MIN_R, r / 0.95 - GIANT_TAPER * t)
    return max(TRUNK_MIN_R, r * (1 - TRUNK_TAPER * t))


def bough_lift(route):
    if route.get("visualOffset") is not None:
        return route["visualOffset"] * SPU
    return LOOKOUT_LIFT if route["kind"] == "lookout" else BRANCH_LIFT


def bark_budget_of(info):
    return BARK_BUDGET_BIG if info.get("category") in BIG_CATEGORIES else BARK_BUDGET


def collar_t(c, need):
    """SquirrelVisual collarT: the t (within the first fifth) at which the centre line is `need` studs out from its
    start, level (20 steps, then 12 halvings; the fifth's end when it never is)."""
    s0 = c.at(0.0)

    def out(t):
        p = c.at(t)
        return math.hypot(p[0] - s0[0], p[2] - s0[2]) >= need
    lo, hi = 0.0, CLEARANCE_T
    for i in range(1, 21):
        if out(CLEARANCE_T * i / 20):
            lo, hi = CLEARANCE_T * (i - 1) / 20, CLEARANCE_T * i / 20
            for _ in range(12):
                mid = (lo + hi) / 2
                if out(mid):
                    hi = mid
                else:
                    lo = mid
            break
    return hi


def sample_ts(length):
    n = max(2, int(math.ceil(length / STEP)))
    return np.linspace(0.0, 1.0, n + 1)


def seg_dist(P, A):
    """Distance from each point of P to the polyline A (dense samples): nearest-segment distance."""
    best = np.full(len(P), np.inf)
    a, b = A[:-1], A[1:]
    ab = b - a
    l2 = np.maximum((ab * ab).sum(1), 1e-12)
    for k in range(len(P)):
        ap = P[k] - a
        f = np.clip((ap * ab).sum(1) / l2, 0, 1)
        d = np.linalg.norm(ap - ab * f[:, None], axis=1)
        best[k] = d.min()
    return best


# ---- geometry -------------------------------------------------------------------------------------

def bvh(V, F):
    from mathutils.bvhtree import BVHTree
    return BVHTree.FromPolygons([tuple(map(float, v)) for v in V], [tuple(int(i) for i in f) for f in F])


def crossings(tree, origin, direction, reach):
    """Every surface the ray crosses within reach: [(distance, face normal . direction)], near to far."""
    from mathutils import Vector
    o, d, out, gone = Vector(origin), Vector(direction), [], 0.0
    for _ in range(64):
        h = tree.ray_cast(o, d, reach - gone)
        if h[0] is None:
            break
        gone += h[3]
        out.append((gone, float(h[1].dot(d))))
        gone += 1e-4
        o = h[0] + d * 1e-4
    return out


def load_fbx(path, pivot):
    """{part name: (V in Roblox world studs, F triangles)}; Blender (x, y, z) -> Roblox (-x, z, y) + pivot."""
    import bpy
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=path)
    parts = {}
    for o in bpy.context.scene.objects:
        if o.type != "MESH":
            continue
        me = o.data
        me.calc_loop_triangles()
        M = np.array(o.matrix_world)
        V = np.array([v.co[:] for v in me.vertices], float)
        V = V @ M[:3, :3].T + M[:3, 3]
        R = np.stack([-V[:, 0], V[:, 2], V[:, 1]], axis=1) + np.asarray(pivot, float)
        F = np.array([t.vertices[:] for t in me.loop_triangles], np.int64).reshape(-1, 3)
        parts[o.name] = (R, F)
    return parts


def stats(e):
    e = np.asarray(e, float)
    if len(e) == 0:
        return {"n": 0, "min": 0.0, "max": 0.0, "p95_abs": 0.0, "bad": 0}
    return {"n": int(len(e)), "min": round(float(e.min()), 3), "max": round(float(e.max()), 3),
            "p95_abs": round(float(np.percentile(np.abs(e), 95)), 3), "bad": int((np.abs(e) > TOL).sum())}


def worst(rows, key, n=3):
    rows = sorted(rows, key=lambda r: -abs(r[key]))[:n]
    return [{k: (round(v, 2) if isinstance(v, float) else v) for k, v in r.items()} for r in rows]


def check_tree(info, parts, routes, clearance_warn=False):
    """info: the tree_NNN.json dict; parts: {name: (V Roblox world studs, F)}. Returns the report dict."""
    rep = {"index": info.get("index"), "label": info.get("label"), "fail": [], "warn": []}
    fail, warn = rep["fail"], rep["warn"]
    trunk = routes[info["trunkRoute"]]
    members = [routes[i] for i in info["routes"] if i != info["trunkRoute"]]
    tc = Curve(np.asarray(trunk["points"], float) * SPU)
    tts = sample_ts(tc.length)
    TP = np.array([tc.at(t) for t in tts])
    TR = np.array([trunk_radius(trunk, t) for t in tts])
    bough = []
    for m in members:
        c = Curve(np.asarray(m["points"], float) * SPU)
        ts = sample_ts(c.length)
        bough.append((m, c, ts, np.array([c.at(t) for t in ts])))

    # parts and budgets -----------------------------------------------------------------------------
    names = sorted(parts)
    unknown = [n for n in names if n not in PART_NAMES]
    if "Bark" not in parts:
        fail.append("no part named Bark")
    if unknown:
        fail.append(f"unexpected part names {unknown}")
    tris = {n: int(len(parts[n][1])) for n in names}
    bark_tris = tris.get("Bark", 0)
    leaf_tris = sum(v for n, v in tris.items() if n.startswith("Leaves"))
    rep["tris"] = dict(tris, bark=bark_tris, leaves=leaf_tris)
    bark_budget = bark_budget_of(info)
    rep["bark_budget"] = bark_budget
    if bark_tris > bark_budget:
        fail.append(f"bark {bark_tris} tris > {bark_budget}")
    if leaf_tris > LEAF_BUDGET:
        fail.append(f"leaves {leaf_tris} tris > {LEAF_BUDGET}")
    pivot = np.asarray(info["pivot"], float)
    bounds_err = 0.0
    for n in names:
        V = parts[n][0] - pivot
        lo, hi = V.min(0), V.max(0)
        want = (info.get("parts") or {}).get(n)
        if want is None:
            fail.append(f"part {n} is in the mesh but not in the json")
            continue
        bounds_err = max(bounds_err, float(np.abs((lo + hi) / 2 - want["center"]).max()),
                         float(np.abs((hi - lo) - want["size"]).max()))
    for n in (info.get("parts") or {}):
        if n not in parts:
            fail.append(f"part {n} is in the json but not in the mesh")
    rep["bounds_err"] = round(bounds_err, 4)
    if bounds_err > 0.01:
        fail.append(f"mesh bounds differ from the json by {bounds_err:.3f} st")
    if "Bark" not in parts:
        return rep
    from mathutils import Vector
    bark = bvh(*parts["Bark"])

    # trunk ------------------------------------------------------------------------------------------
    flare_top = TP[0][1] + max(2.5, 1.2 * TR[0])
    allB = np.concatenate([b[3] for b in bough]) if bough else np.zeros((0, 3))
    errs, flare, rows, frows, miss, junction = [], [], [], [], 0, 0
    for p, t, want in zip(TP, tts, TR):
        hits = []
        for k in range(RAYS):
            a = 2 * math.pi * k / RAYS
            d = np.array([math.cos(a), 0.0, math.sin(a)])
            out = [c for c in crossings(bark, p, d, want + 8.0) if c[1] > 0]
            for dy in (0.002, -0.002):
                # (a level ray at a ring's exact height can slip through the edge two faces share: nudged
                # a hair up or down, it meets the bark there is)
                if out:
                    break
                out = [c for c in crossings(bark, p + np.array([0.0, dy, 0.0]), d, want + 8.0) if c[1] > 0]
            hits.append((k, p + d * out[0][0] if out else None))
        got = [(k, hp) for k, hp in hits if hp is not None]
        if got and len(allB):
            near = seg_dist(np.array([hp for _, hp in got]), allB) if len(allB) > 1 else np.full(len(got), 9.0)
        else:
            near = []
        j = 0
        for k, hp in hits:
            if hp is None:
                a = 2 * math.pi * k / RAYS
                q = p + np.array([math.cos(a), 0.0, math.sin(a)]) * want
                if len(allB) > 1 and seg_dist(q[None], allB)[0] < JUNCTION:
                    junction += 1  # the ray runs on inside a level bough that leaves the trunk here
                    continue
                miss += 1
                rows.append({"y": float(p[1]), "t": float(t), "ray": k, "err": -float(want), "want": float(want)})
                continue
            e = float(np.hypot(hp[0] - p[0], hp[2] - p[2]) - want)
            is_j = len(near) and near[j] < JUNCTION
            j += 1
            if is_j:
                junction += 1
            elif p[1] < flare_top:
                flare.append(e)
                frows.append({"y": float(p[1] - TP[0][1]), "ray": k, "err": e})
            else:
                errs.append(e)
                rows.append({"y": float(p[1]), "t": float(t), "ray": k, "err": e, "want": float(want)})
    st = stats(errs)
    st.update(samples=len(TP), miss=miss, junction_rays=junction, flare=stats(flare),
              r_foot=round(float(TR[0]), 3), r_top=round(float(TR[-1]), 3), worst=worst(rows, "err"))
    rep["trunk"] = st
    if st["bad"] or miss:
        fail.append(f"trunk bark off the expected radius by > {TOL} st on {st['bad']} rays (min {st['min']}, "
                    f"max {st['max']}), {miss} rays found no bark")
    fl = st["flare"]
    fl["deep"] = int((np.abs(np.asarray(flare, float)) > FLARE_FAIL).sum()) if flare else 0
    fl["top"] = round(float(flare_top - TP[0][1]), 2)
    fl["worst"] = worst(frows, "err")
    if fl["deep"]:
        fail.append(f"root flare: {fl['deep']} rays off the climbing radius by > {FLARE_FAIL} st in the lowest "
                    f"{fl['top']} st of the climb (min {fl['min']}, max {fl['max']})")
    elif fl["bad"]:
        warn.append(f"root flare: {fl['bad']} rays off by > {TOL} st (max {fl['max']})")

    # boughs -----------------------------------------------------------------------------------------
    rep["boughs"] = []
    all_e, all_c, all_x, all_late, tot_miss, tot_cmiss = [], [], [], [], 0, 0
    walk_tops = [(mm["id"], PP + np.array([0.0, bough_lift(mm), 0.0])) for mm, _, _, PP in bough
                 if mm["kind"] in ("branch", "bridge", "lookout")]

    def crossing(m, f, err):
        """Wood over the feet where another walk's own top line passes over them (two walks crossing in a fork):
        the squirrel there is under the other walk's bark whatever the bark is, as long as that line stands
        within CROSSING_UP of the feet and CROSSING of the column. Such samples are counted apart (warn only)."""
        for rid, top in walk_tops:
            if rid == m["id"]:
                continue
            dy = top[:, 1] - f[1]
            near = (np.hypot(top[:, 0] - f[0], top[:, 2] - f[2]) < CROSSING) & (dy > -0.05) & (dy < CROSSING_UP)
            if near.any() and -err <= dy[near].max() + 0.15:
                return True
        return False
    for m, c, ts, P in bough:
        lift = bough_lift(m)
        top_line = P + np.array([0.0, lift, 0.0])
        feet = top_line.copy()
        cl = m.get("trunkClearance")
        if m["kind"] == "branch" and cl:
            d = c.at(CLEARANCE_SAMPLE_T) - c.at(0.0)
            l = math.hypot(d[0], d[2])
            if l > 0:
                k = (cl * SPU + CLEARANCE_PAD) * np.clip(1 - ts / CLEARANCE_T, 0, None) ** 2
                feet[:, 0] += d[0] / l * k
                feet[:, 2] += d[2] / l * k
        e, ec, rows, miss, cmiss, over, cand = [], [], [], 0, 0, 0, []
        pushed = m["kind"] == "branch" and bool(cl)
        late = pushed and collar_t(c, cl * SPU) / CLEARANCE_T > COLLAR_MAX

        def under(f):
            """Feet height minus the bark the squirrel stands on at f; "over" while the feet are still
            over the trunk, None when there is no bark in the column."""
            i = int(np.argmin(np.abs(TP[:, 1] - f[1])))
            if TP[0][1] <= f[1] <= TP[-1][1] + 0.5 and math.hypot(f[0] - TP[i][0], f[2] - TP[i][2]) < TR[i] + 0.1:
                return "over"
            tops = [f[1] + 6.0 - x[0] for x in crossings(bark, f + np.array([0, 6.0, 0]), (0, -1, 0), 12.0) if x[1] < 0]
            if not tops:
                return None
            return float(f[1] - min(tops, key=lambda y: abs(y - f[1])))

        for i, (f, f0, t) in enumerate(zip(feet, top_line, ts)):
            if pushed and t < CLEARANCE_T:
                # the pushed feet (visualPose) are reported apart; with --clearance-warn the game draws
                # the squirrel on the bough's own top line here, and that is what has to hold
                err = under(f)
                if err is None:
                    cmiss += 1
                elif err != "over":
                    ec.append(err)
                if not clearance_warn:
                    if err == "over":
                        over += 1
                    continue
                f = f0
            err = under(f)
            if err == "over":
                over += 1
            elif err is not None and -CROSS_DEEP <= err < -TOL and crossing(m, f, err):
                cand.append((i, err, {"s": float(t * c.length), "err": err}))
            elif err is None:
                miss += 1
                rows.append({"s": float(t * c.length), "err": 9.0})
            else:
                e.append(err)
                rows.append({"s": float(t * c.length), "err": err})
        # crossing samples warn only in short runs: a longer run is wood over the feet like any other
        cross, run = [], []
        for x in cand + [None]:
            if x is not None and run and x[0] == run[-1][0] + 1:
                run.append(x)
                continue
            if len(run) > CROSS_RUN:
                e += [r[1] for r in run]
                rows += [r[2] for r in run]
            else:
                cross += [r[1] for r in run]
            run = [x] if x is not None else []
        s = stats(e)
        s.update(route=m["id"], name=m["name"], kind=m["kind"], length=round(c.length, 1), lift=round(lift, 3),
                 samples=len(ts), over_trunk=over, miss=miss, worst=worst(rows, "err"), clearance=dict(stats(ec), miss=cmiss),
                 crossing=stats(cross), late_collar=bool(late))
        if late:
            all_late.append((m["id"], stats(ec), cmiss))
        all_x += cross
        rep["boughs"].append(s)
        all_e += e
        all_c += ec
        tot_miss += miss
        tot_cmiss += cmiss
    tot = stats(all_e)
    tot["miss"] = tot_miss
    rep["bough_total"] = tot
    rep["clearance_total"] = stats(all_c)
    if tot["bad"] or tot_miss:
        fail.append(f"bough bark off the feet by > {TOL} st at {tot['bad']} of {tot['n']} samples (min {tot['min']}, max "
                    f"{tot['max']}), {tot_miss} samples with no bark under the feet")
    xt = rep["crossing_total"] = stats(all_x)
    if xt["n"]:
        warn.append(f"crossing walks: {xt['n']} samples where another walk's top line passes just over the feet "
                    f"(wood over them, min {xt['min']} st)")
    ct = rep["clearance_total"]
    ct["miss"] = tot_cmiss
    if (ct["bad"] or tot_cmiss) and not clearance_warn:
        fail.append(
            f"trunk-clearance stretch (branch, t < {CLEARANCE_T}, feet pushed off the centre line): off the bark by > {TOL} st "
            f"at {ct['bad']} of {ct['n']} samples (min {ct['min']}, max {ct['max']}), {tot_cmiss} with no bark under them")
    # the branches the game still draws at the pushed pose (a known game-side issue: SquirrelVisual's collarMax)
    lc = rep["late_collar"] = {
        "branches": len(all_late), "routes": [r for r, _, _ in all_late],
        "bad": sum(x["bad"] for _, x, _ in all_late), "miss": sum(k for _, _, k in all_late),
        "n": sum(x["n"] for _, x, _ in all_late),
        "worst": max([max(abs(x["min"]), abs(x["max"])) for _, x, _ in all_late if x["n"]] or [0.0]),
    }
    if clearance_warn and (lc["bad"] or lc["miss"]):
        warn.append(f"late collar (game side, SquirrelVisual collarMax {COLLAR_MAX}): {lc['branches']} branches are drawn at "
                    f"the pushed pose over their first fifth; there the feet are off the bark by > {TOL} st at {lc['bad']} "
                    f"of {lc['n']} samples (worst {lc['worst']:.2f}), {lc['miss']} with no bark under them")

    # tunnel -----------------------------------------------------------------------------------------
    leaves = [(n, bvh(*parts[n])) for n in names if n.startswith("Leaves") or n == "Apples"]
    tun = {"bough_bad": 0, "bough_samples": 0, "bough_min": 99.0, "trunk_bad": 0, "trunk_samples": len(TP),
           "trunk_min_margin": 99.0, "worst": []}
    rows = []
    for m, c, ts, P in bough:
        for p, t in zip(P, ts):
            q = Vector((p[0], p[1] + BODY_UP, p[2]))
            dmin, who = 99.0, None
            for n, b in leaves:
                h = b.find_nearest(q, BOUGH_TUNNEL + 3.0)
                if h[0] is not None and h[3] < dmin:
                    dmin, who = h[3], n
            tun["bough_samples"] += 1
            tun["bough_min"] = min(tun["bough_min"], dmin)
            if dmin < BOUGH_TUNNEL:
                tun["bough_bad"] += 1
                rows.append({"route": m["id"], "s": float(t * c.length), "leaf_at": float(dmin), "part": who})
    for p, want in zip(TP, TR):
        q = Vector(p)
        dmin = 99.0
        for n, b in leaves:
            h = b.find_nearest(q, want + TRUNK_TUNNEL + 3.0)
            if h[0] is not None:
                dmin = min(dmin, h[3])
        margin = dmin - want
        tun["trunk_min_margin"] = min(tun["trunk_min_margin"], margin)
        if margin < TRUNK_TUNNEL:
            tun["trunk_bad"] += 1
            rows.append({"route": trunk["id"], "s": float(p[1] - TP[0][1]), "leaf_at": float(margin), "part": "trunk"})
    tun["bough_min"] = round(tun["bough_min"], 3)
    tun["trunk_min_margin"] = round(tun["trunk_min_margin"], 3)
    tun["worst"] = [{k: (round(v, 2) if isinstance(v, float) else v) for k, v in r.items()}
                    for r in sorted(rows, key=lambda r: r["leaf_at"])[:4]]
    rep["tunnel"] = tun
    if tun["bough_bad"] or tun["trunk_bad"]:
        fail.append(f"leaves in the clear tunnel: {tun['bough_bad']} bough samples (nearest leaf {tun['bough_min']} st from "
                    f"the body line, need {BOUGH_TUNNEL}), {tun['trunk_bad']} trunk samples (nearest {tun['trunk_min_margin']} "
                    f"st off the climbing surface, need {TRUNK_TUNNEL})")
    return rep


def print_report(rep):
    print(f"\n=== tree {rep['index']:03d} {rep['label']}: {'BROKEN' if rep['fail'] else 'ok'} ===")
    t = rep.get("tris", {})
    print(f"  tris   bark {t.get('bark', 0):>6} / {rep.get('bark_budget', BARK_BUDGET)}   leaves {t.get('leaves', 0):>6} / {LEAF_BUDGET}   parts "
          + ", ".join(f"{n} {v}" for n, v in t.items() if n not in ("bark", "leaves"))
          + f"   bounds vs json {rep.get('bounds_err', 0)} st")
    if "trunk" in rep:
        s = rep["trunk"]
        print(f"  {'route':<44}{'kind':<8}{'len':>6}{'n':>6}{'min':>8}{'max':>8}{'p95':>7}{'>0.1':>6}{'miss':>6}{'clr n':>7}{'clr min':>8}{'clr max':>8}{'clr>0.1':>8}  note")
        print(f"  {'trunk (bark radius - expected)':<44}{'trunk':<8}{'':>6}{s['n']:>6}{s['min']:>8.3f}{s['max']:>8.3f}"
              f"{s['p95_abs']:>7.3f}{s['bad']:>6}{s['miss']:>6}{'':>31}  r {s['r_foot']} -> {s['r_top']}, {s['junction_rays']} junction rays"
              + (f", worst at y={s['worst'][0]['y']} err {s['worst'][0]['err']}" if s["bad"] else ""))
        f = s["flare"]
        print(f"  {f'trunk root flare (fails > {FLARE_FAIL})':<44}{'trunk':<8}{'':>6}{f['n']:>6}{f['min']:>8.3f}{f['max']:>8.3f}"
              f"{f['p95_abs']:>7.3f}{f['bad']:>6}")
        for b in rep["boughs"]:
            label = f"{b['route']} {b['name']}"[:43]
            k = b["clearance"]
            print(f"  {label:<44}{b['kind']:<8}{b['length']:>6.1f}{b['n']:>6}{b['min']:>8.3f}{b['max']:>8.3f}"
                  f"{b['p95_abs']:>7.3f}{b['bad']:>6}{b['miss']:>6}{k['n']:>7}{k['min']:>8.3f}{k['max']:>8.3f}{k['bad']:>8}  lift {b['lift']}, {b['over_trunk']} over trunk"
                  + (f", worst at s={b['worst'][0]['s']}" if b["bad"] or b["miss"] else ""))
        u = rep["tunnel"]
        print(f"  tunnel boughs: {u['bough_bad']} of {u['bough_samples']} samples with a leaf within {BOUGH_TUNNEL} st of the body "
              f"line (nearest {u['bough_min']});  trunk: {u['trunk_bad']} of {u['trunk_samples']} with a leaf within "
              f"{TRUNK_TUNNEL} st of the climbing surface (nearest {u['trunk_min_margin']})")
        if u["worst"]:
            print(f"    worst: {u['worst']}")
    for w in rep["warn"]:
        print(f"  warn: {w}")
    for f in rep["fail"]:
        print(f"  BROKEN: {f}")


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=os.path.join(REPO, "build", "art", "trees"))
    ap.add_argument("--ids", default="")
    ap.add_argument("--json", default="")
    ap.add_argument("--clearance-warn", action="store_true",
                    help="the trunk-clearance stretch of a branch (t < 0.2) is checked on the bough's own top line, "
                         "where the game draws the squirrel (SquirrelVisual.junctionT); on a late-collar branch the "
                         "game draws it at the pushed pose, reported apart as a warning (a known game-side issue)")
    ap.add_argument("--shapes", default="", help="dump_shapes.luau's JSON: the D32 grown boughs are routes too")
    args = ap.parse_args(argv)
    routes = load_routes()
    if args.shapes:
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import shapes as sh  # noqa: E402  (a sibling module; only with --shapes)

        sh.merge_routes(routes, sh.load(args.shapes))
    if args.ids:
        files = [os.path.join(args.dir, f"tree_{int(i):03d}.json") for i in args.ids.split(",") if i.strip()]
    else:
        files = sorted(f for f in glob.glob(os.path.join(args.dir, "tree_*.json")) if re.search(r"tree_\d+\.json$", f))
    reports, broken = [], 0
    for f in files:
        with open(f) as fh:
            info = json.load(fh)
        fbx = f[:-5] + ".fbx"
        if not os.path.exists(fbx):
            rep = {"index": info.get("index"), "label": info.get("label"), "warn": [],
                   "fail": [f"no {os.path.basename(fbx)} (build with --fbx)"]}
        else:
            rep = check_tree(info, load_fbx(fbx, info["pivot"]), routes, args.clearance_warn)
        print_report(rep)
        reports.append(rep)
        broken += 1 if rep["fail"] else 0
    print(f"\n{len(reports)} trees checked, {broken} with a broken promise")
    if args.json:
        with open(args.json, "w") as fh:
            json.dump(reports, fh, indent=1)
    return 1 if broken or not reports else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:] if "--" not in sys.argv else sys.argv[sys.argv.index("--") + 1:]))
