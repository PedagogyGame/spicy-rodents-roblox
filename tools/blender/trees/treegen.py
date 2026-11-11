"""Route-true trees that branch like wood and carry leaf sprays (numpy geometry; bpy only through the
`union` callback and to_blender).

Every tree is rebuilt from its harvested climbing routes (data/harvest: routes, forks, trees; a
route's centre line is the game's own curve, class Curve). Units: studs (HTML units x 2.5), Roblox axes
(+Y up), local to the tree's root (pivot) = trees.json `root` x 2.5. Conversion to Blender happens only
when objects are made: Blender (x, y, z) = (-X, Z, Y), so the FBX export (axis_forward Z, axis_up Y,
FBX_SCALE_ALL) lands back on Roblox (X, Y, Z) with 1 Blender unit = 1 stud.

How a tree is made
  1. The wood the squirrel runs on (trunk, walkable boughs, living bridges, root flare, the leader, the
     giants' decor limbs and lookout perches) is one skin: every limb is swept as a closed tube, the
     tubes are joined by a boolean union (opts["union"], Blender) and the vertices near a junction are
     then pulled out onto a smooth union of the limbs (a signed-distance blend), so the bark of two
     limbs meets in one rounded crease. A bough swells into a collar where it leaves the trunk and
     thins after every side branch (the cross-section areas it gives away add up to what it loses).
     The leader leaves the trunk's top to the side, as one more limb, and turns up into the crown.
  2. Side branches grow from the boughs, the leader and each other: they leave at the species' angle,
     sag, turn up toward the light, kink at every node and taper to twigs. Each one meets its parent
     in a skirt that lies on the parent's surface (no cylinder ends, no gaps). twig_tips(tb) lists
     where they end.
  3. Leaves are sprays: alpha-textured cards (4 triangles, bent and twisted) set on the twigs, in three
     parts by light (LeavesSun, LeavesMid, LeavesShade) so colour changes with height and depth.

Gameplay contract (src/shared/Routes/Motion.luau visualPose; tools/blender/trees/check_promises.py
measures it on the exported meshes, to 0.1 stud):
  * trunk bark radius at route parameter t equals the squirrel's tapered radius
      r(1 - 0.48 t) (min 0.8 st), giants r/0.95 - 2.625 t (min 1.125 st); r = surfaceRadius x 2.5,
    all the way round, from the top of the root flare to the top of the route. The only wood outside
    it is the boughs themselves: a bough with its collar stays within 2 studs of its route, so
    collars add no wood to the trunk and a steep bough (which hangs to one side of its route) is thin.
  * branch / bridge / lookout bark: the bough's top edge is the squirrel's feet line, rail + lift
    (0.5 u = 1.25 st, apples 0.75 st, lookouts 1.525 st), from the route's first point to its last:
    every ring of the tube has a corner on that line, and nothing else stands over it.
  * no leaf card comes within a tunnel of every walkable rail (and of any foreign route passing
    through the crown), so a squirrel on a bough stays visible.
"""
import json
import math
import os

import numpy as np

SPU = 2.5
REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
Y = np.array([0.0, 1.0, 0.0])

BARK_BUDGET = 12000
LEAF_BUDGET = 14000
COLLAR = 0.14  # how much a bough swells where it leaves the trunk


# ---- data ---------------------------------------------------------------------------------------

def load_data(repo=REPO):
    h = os.path.join(repo, "data", "harvest")
    with open(os.path.join(h, "routes.json")) as fh:
        routes = {r["id"]: r for r in json.load(fh)["routes"]}
    with open(os.path.join(h, "route_samples.json")) as fh:
        samples = {rid: np.array(pts, dtype=float) for rid, pts in json.load(fh)["samples"]}
    with open(os.path.join(h, "forks.json")) as fh:
        forks = {f["trunk"]: f for f in json.load(fh)["trunks"]}
    with open(os.path.join(h, "trees.json")) as fh:
        trees = json.load(fh)
    with open(os.path.join(h, "houses.json")) as fh:
        houses = json.load(fh)
    return {"routes": routes, "samples": samples, "forks": forks, "trees": trees, "houses": houses}


class Curve:
    """A route's centre line as the game runs it (src/shared/Routes/Curve.luau: three.js r160
    CatmullRomCurve3, centripetal, with its 200-division arc-length table); at(u) is the point at
    arc-length fraction u = railT."""

    def __init__(self, pts):
        self.p = np.asarray(pts, float)
        P = np.array([self.raw(t) for t in np.linspace(0.0, 1.0, 201)])
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
        return p1 + t1 * w + (-3 * p1 + 3 * p2 - 2 * t1 - t2) * w * w + (2 * p1 - 2 * p2 + t1 + t2) * w * w * w

    def at(self, u):
        target = min(max(u, 0.0), 1.0) * self.length
        L = self.lengths
        i = min(max(int(np.searchsorted(L, target, side="right")) - 1, 0), 199)
        seg = L[i + 1] - L[i]
        return self.raw((i + ((target - L[i]) / seg if seg > 0 else 0.0)) / 200.0)

    def dense(self, step=0.25):
        """Points every `step` of arc length (both ends kept)."""
        n = max(2, int(math.ceil(self.length / step)))
        return np.array([self.at(u) for u in np.linspace(0.0, 1.0, n + 1)])


# v5.4 palettes (trees.json spec.color where present; otherwise from v5_4_game.js)
OUTER_GREENS = ["#658d4e", "#789956", "#537d43", "#8fa568"]
GIANT = {"SENTINEL OAK": ("oak", ["#607e41", "#49753e", "#759c55"]),
         "HIGHLAND ELM": ("elm", ["#6c9551", "#49753e", "#759c55"]),
         "OLD WATCH SYCAMORE": ("sycamore", ["#81945b", "#49753e", "#759c55"])}
ESTATE = ["#557c43", "#698c4e", "#8ba85e"]
APPLE_GREENS = ["#617f3c", "#829e4d", "#4e7138"]


def _shade_hex(h, f, warm=0.0):
    c = [int(h[i : i + 2], 16) for i in (1, 3, 5)]
    c = [c[0] * f * (1 + warm), c[1] * f * (1 + warm * 0.5), c[2] * f * (1 - warm)]
    return "#" + "".join(f"{max(0, min(255, int(round(x)))):02x}" for x in c)


def classify(tree, trunk_route):
    """-> (species, palette, label, category)"""
    spec = tree.get("spec") or {}
    name = (spec.get("name") or "").strip()
    tname = trunk_route["name"]
    up = (name or tname).upper()
    if tname.startswith("outer "):
        idx = int(tname.split()[1])
        sp = ["oak", "elm", "sycamore", "maple", "oak"][idx % 5]
        g = OUTER_GREENS[(idx % 5) % 4]
        pal = [g, _shade_hex(g, 1.16, 0.05), _shade_hex(g, 0.84), _shade_hex(g, 1.05, -0.03)]
        label = ("PARK " if idx >= 90 else "STREET ") + {"oak": "OAK", "elm": "ELM", "sycamore": "SYCAMORE", "maple": "MAPLE"}[sp] + f" {idx}"
        return sp, pal, label, "outer"
    if "giant trunk" in tname:
        gname = tname.replace(" giant trunk", "")
        sp, pal = GIANT[gname]
        return sp, pal, gname, "giant"
    if tname == "estate oak trunk":
        return "oak", ESTATE, "ESTATE GATE OAK", "estate"
    if up.startswith("APPLE"):
        return "apple", APPLE_GREENS, name.upper(), "apple"
    pal = spec.get("color") or ["#6a8c3e", "#89ab55", "#a4bb66"]
    if "WILLOW" in up:
        sp = "willow"
    elif "SYCAMORE" in up:
        sp = "sycamore"
    elif "MAPLE" in up:
        sp = "maple"
    elif "ELM" in up:
        sp = "elm"
    else:
        sp = "oak"
    return sp, pal, name.upper(), "named"


# How each species grows. Lengths are studs for a 75-stud tree and scale with the tree's height.
#   spacing   studs of bough between side branches            angle   side branch off the bough, degrees
#   len1      side branch length (near the trunk, at the tip) len2    branchlet length
#   sag/up    how hard gravity bends a branch down early and light turns it up late (per level)
#   kink      random turn at each node (radians, per level)   node    studs between nodes (per level)
#   rise      azimuth of a side branch round its bough: 0 = straight up, 90 = level, >90 = hanging
#   card      spray card (length, width) in studs             droop   how far a spray's tip hangs
#   tip/side  sprays at a branchlet's tip / at each of its nodes
#   floor     lowest leaves, as a fraction of the height      top     crown top as a fraction of the height
#   crown     limbs the leader throws out above the boughs    flat    0 = round crown, 1 = spreading flat top
#   fill      how much of the leaf budget the crown is filled to (0.86 unless given)
SPECIES = {
    "oak": dict(spacing=7.0, angle=(52, 76), len1=(21.0, 16.0), len2=(8.0, 13.0), sag=(0.030, 0.020), up=(0.050, 0.060),
                kink=(0.20, 0.26), node=(3.6, 2.9), rise=(62, 112), card=(7.0, 6.2), droop=0.10, tip=3, side=1,
                floor=0.36, top=0.97, crown=6, flat=0.55, twist=0.30),
    "elm": dict(spacing=7.6, angle=(32, 50), len1=(22.0, 17.0), len2=(8.5, 13.0), sag=(0.060, 0.050), up=(0.012, 0.0),
                kink=(0.11, 0.16), node=(3.8, 3.0), rise=(48, 96), card=(6.6, 5.4), droop=0.30, tip=3, side=1,
                floor=0.46, top=0.98, crown=6, flat=0.25, twist=0.18),
    "sycamore": dict(spacing=8.4, angle=(48, 68), len1=(20.0, 15.0), len2=(7.5, 11.5), sag=(0.020, 0.012), up=(0.045, 0.050),
                     kink=(0.15, 0.20), node=(4.2, 3.2), rise=(56, 104), card=(7.6, 7.0), droop=0.12, tip=3, side=1,
                     floor=0.40, top=0.98, crown=5, flat=0.15, twist=0.25),
    "maple": dict(spacing=6.4, angle=(38, 56), len1=(18.0, 14.0), len2=(7.0, 11.0), sag=(0.015, 0.010), up=(0.060, 0.070),
                  kink=(0.12, 0.16), node=(3.4, 2.7), rise=(50, 100), card=(6.4, 6.2), droop=0.10, tip=3, side=1,
                  floor=0.33, top=0.98, crown=7, flat=0.0, twist=0.25),
    "willow": dict(spacing=6.0, angle=(40, 62), len1=(16.0, 12.0), len2=(6.0, 9.5), sag=(0.075, 0.110), up=(0.0, 0.0),
                   kink=(0.12, 0.14), node=(3.4, 2.4), rise=(50, 100), card=(11.5, 3.4), droop=0.0, tip=2, side=2,
                   floor=0.10, top=0.95, crown=6, flat=0.2, twist=0.2),
    "apple": dict(spacing=3.2, angle=(50, 74), len1=(7.5, 5.5), len2=(3.0, 5.0), sag=(0.030, 0.020), up=(0.090, 0.090),
                  kink=(0.26, 0.30), node=(1.7, 1.4), rise=(58, 110), card=(3.8, 3.5), droop=0.08, tip=3, side=1,
                  floor=0.26, top=0.98, crown=4, flat=0.3, twist=0.3, fill=0.5),
}

LEAF_SHAPE = {"oak": "oak", "elm": "elm", "sycamore": "palmate", "maple": "maple", "willow": "willow", "apple": "apple"}
BARK_FAMILY = {"oak": "oak", "elm": "elm", "sycamore": "sycamore", "maple": "maple", "willow": "willow", "apple": "apple"}


def tree_records(data):
    """One record per trees.json entry (95), matched to its fork trunk by foot position."""
    R, S, F = data["routes"], data["samples"], data["forks"]
    recs = []
    trunks = [R[t] for t in F]
    for i, t in enumerate(data["trees"]["trees"]):
        best = min(trunks, key=lambda tr: math.hypot(tr["points"][0][0] - t["x"], tr["points"][0][2] - t["z"]))
        fk = F[best["id"]]
        members = [R[f["branch"]] for f in fk["forks"]]
        if "giant trunk" in best["name"]:
            gname = best["name"].replace(" giant trunk", "")
            members += [r for r in R.values() if r["name"] == f"{gname} OPEN SKY LOOKOUT"]
        sp, pal, label, cat = classify(t, best)
        root = np.array(t["root"], dtype=float) * SPU
        recs.append({
            "index": i, "trunk": best, "members": members, "species": sp, "palette": pal, "label": label,
            "category": cat, "root": root, "H": float(t["H"]) * SPU, "spec": t.get("spec") or {},
            "seed": 1000 + best["id"],
        })
    return recs


# ---- small vector helpers -----------------------------------------------------------------------

def norm(v, axis=-1):
    v = np.asarray(v, dtype=float)
    l = np.linalg.norm(v, axis=axis, keepdims=True)
    return v / np.maximum(l, 1e-12)


def smoothstep(x):
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3 - 2 * x)


def arclen(P):
    d = np.linalg.norm(np.diff(P, axis=0), axis=1)
    return np.concatenate([[0.0], np.cumsum(d)])


def at_s(P, sP, s):
    """Points of the polyline P (arc lengths sP) at arc lengths s."""
    s = np.atleast_1d(s)
    return np.stack([np.interp(s, sP, P[:, k]) for k in range(3)], axis=1)


def resample(P, step, min_n=2):
    """Resample a dense polyline at ~`step` spacing (keeps both ends); returns (points, s, s/L)."""
    s = arclen(P)
    L = s[-1]
    n = max(min_n, int(math.ceil(L / step)) + 1)
    ss = np.linspace(0, L, n)
    return at_s(P, s, ss), ss, ss / max(L, 1e-9)


def adaptive_s(P, tol=0.1, max_step=4.0, upright=False):
    """Arc lengths of the fewest points of a dense polyline whose chords stay within `tol` of it, no
    chord longer than `max_step`. upright: `tol` is the error allowed straight up and down (what the
    game sees of a feet line), so a steep chord has to lie closer."""
    D, sd, _ = resample(P, 0.25)
    keep = [0]
    i = 0
    n = len(D)
    while i < n - 1:
        j = i + 1
        while j + 1 < n and sd[j + 1] - sd[i] <= max_step:
            a, b = D[i], D[j + 1]
            mids = D[i + 1 : j + 1]
            lv = math.hypot(b[0] - a[0], b[2] - a[2]) / max(float(np.linalg.norm(b - a)), 1e-9) if upright else 1.0
            if seg_dist(mids, a[None], b[None]).max() > tol * max(lv, 0.15):
                break
            j += 1
        keep.append(j)
        i = j
    return sd[keep]


def seg_dist(p, A, B):
    """Distance from points p (n,3) to segments A,B (m,3) -> (n, m)."""
    p = np.atleast_2d(p)
    AB = B - A
    l2 = np.maximum((AB * AB).sum(1), 1e-12)
    AP = p[:, None, :] - A[None, :, :]
    t = np.clip((AP * AB[None]).sum(2) / l2[None], 0, 1)
    C = A[None] + t[..., None] * AB[None]
    return np.linalg.norm(p[:, None, :] - C, axis=2)


def rotate(v, axis, ang):
    """Rodrigues: v turned by ang about the unit axis."""
    axis = norm(axis)
    c, s = math.cos(ang), math.sin(ang)
    return v * c + np.cross(axis, v) * s + axis * np.dot(axis, v) * (1 - c)


def perp_up(t, prev=None):
    """World up made perpendicular to the tangent t (continued through vertical stretches)."""
    u = Y - t * np.dot(Y, t)
    if np.linalg.norm(u) < 0.03:
        if prev is not None:
            u = prev - t * np.dot(prev, t)
        else:
            u = np.array([1.0, 0, 0]) - t * t[0]
    return norm(u)


# ---- mesh buffers -------------------------------------------------------------------------------

class Mesh:
    def __init__(self):
        self.V, self.F, self.UV, self.N = [], [], [], []
        self.n = 0

    def add(self, V, F, UV, N):
        if len(F) == 0:
            return
        self.V.append(np.asarray(V, float))
        self.F.append(np.asarray(F, np.int64) + self.n)
        self.UV.append(np.asarray(UV, float))
        self.N.append(np.asarray(N, float))
        self.n += len(V)

    def arrays(self):
        if not self.V:
            return np.zeros((0, 3)), np.zeros((0, 3), np.int64), np.zeros((0, 2)), np.zeros((0, 3))
        return np.concatenate(self.V), np.concatenate(self.F), np.concatenate(self.UV), norm(np.concatenate(self.N))

    @property
    def tris(self):
        return int(sum(len(f) for f in self.F))


def frames(C, start_normal=None):
    """Rotation-minimising frames along a polyline: tangents T, normals N, binormals B = T x N."""
    C = np.asarray(C, float)
    n = len(C)
    T = np.zeros_like(C)
    T[1:-1] = C[2:] - C[:-2]
    T[0] = C[1] - C[0]
    T[-1] = C[-1] - C[-2]
    T = norm(T)
    if start_normal is None:
        ref = np.array([0.0, -1.0, 0.0]) if abs(T[0][1]) < 0.9 else np.array([1.0, 0.0, 0.0])
    else:
        ref = np.asarray(start_normal, float)
    N0 = norm(ref - T[0] * np.dot(ref, T[0]))
    Ns = [N0]
    for i in range(1, n):
        prev = Ns[-1]
        v = prev - T[i] * np.dot(prev, T[i])
        if np.linalg.norm(v) < 1e-6:
            v = np.cross(T[i], [0.0, 0.0, 1.0])
        Ns.append(norm(v))
    Ns = np.array(Ns)
    return T, Ns, np.cross(T, Ns)


def tube(centers, radius_fn, sides, u_rep, v_tile, start_normal=None, cap_end=False, cap_start=False, v0=0.0):
    """Sweep a ring along `centers` (n,3). radius_fn(i, angles) -> radii (sides+1,) for ring i.
    Seam duplicated; u in [0, u_rep], v = arc length / v_tile + v0. Returns V, F (tris, outward), UV, N."""
    C = np.asarray(centers, float)
    n = len(C)
    T, Ns, Bs = frames(C, start_normal)
    ang = np.linspace(0, 2 * math.pi, sides + 1)
    ca, sa = np.cos(ang), np.sin(ang)
    s = arclen(C)
    V, UV, NN = [], [], []
    for i in range(n):
        r = radius_fn(i, ang)
        d = ca[:, None] * Ns[i][None] + sa[:, None] * Bs[i][None]
        V.append(C[i][None] + d * r[:, None])
        NN.append(d)
        UV.append(np.stack([ang / (2 * math.pi) * u_rep, np.full(sides + 1, s[i] / v_tile + v0)], axis=1))
    V = np.concatenate(V)
    UV = np.concatenate(UV)
    NN = np.concatenate(NN)
    m = sides + 1
    i, j = np.meshgrid(np.arange(n - 1), np.arange(sides), indexing="ij")
    a, b, c, d = i * m + j, i * m + j + 1, (i + 1) * m + j + 1, (i + 1) * m + j
    F = np.concatenate([np.stack([a, b, c], -1).reshape(-1, 3), np.stack([a, c, d], -1).reshape(-1, 3)])
    if cap_end:
        tip = C[-1] + T[-1] * float(np.mean(radius_fn(n - 1, ang))) * 0.6
        ti = len(V)
        V = np.concatenate([V, tip[None]])
        UV = np.concatenate([UV, [[u_rep * 0.5, s[-1] / v_tile + v0 + 0.1]]])
        NN = np.concatenate([NN, T[-1][None]])
        base = (n - 1) * m
        F = np.concatenate([F, np.array([(base + j, base + j + 1, ti) for j in range(sides)], np.int64)])
    if cap_start:
        tip = C[0] - T[0] * float(np.mean(radius_fn(0, ang))) * 0.4
        ti = len(V)
        V = np.concatenate([V, tip[None]])
        UV = np.concatenate([UV, [[u_rep * 0.5, v0 - 0.1]]])
        NN = np.concatenate([NN, -T[0][None]])
        F = np.concatenate([F, np.array([(j + 1, j, ti) for j in range(sides)], np.int64)])
    return V, F, UV, NN


def closed_tube(centers, radius_fn, sides, u_rep, v_tile, start_normal=None, fr=None, cap=(0.4, 0.6)):
    """A watertight tube for the boolean union: welded rings, a fan cap at both ends (cap: how far
    the two cap points stand off, in ring radii).
    Returns V (n*sides + 2, 3), faces (list of index tuples, outward) and one uv per face corner."""
    C = np.asarray(centers, float)
    n = len(C)
    T, Ns, Bs = fr if fr is not None else frames(C, start_normal)
    ang = np.arange(sides) * (2 * math.pi / sides)
    ca, sa = np.cos(ang), np.sin(ang)
    s = arclen(C)
    V = np.zeros((n * sides + 2, 3))
    for i in range(n):
        r = radius_fn(i, ang)
        d = ca[:, None] * Ns[i][None] + sa[:, None] * Bs[i][None]
        V[i * sides : (i + 1) * sides] = C[i][None] + d * r[:, None]
    r0 = float(np.mean(radius_fn(0, ang)))
    r1 = float(np.mean(radius_fn(n - 1, ang)))
    V[-2] = C[0] - T[0] * r0 * cap[0]
    V[-1] = C[-1] + T[-1] * r1 * cap[1]
    faces, uvs = [], []
    for i in range(n - 1):
        v0, v1 = s[i] / v_tile, s[i + 1] / v_tile
        for j in range(sides):
            j1 = (j + 1) % sides
            faces.append((i * sides + j, i * sides + j1, (i + 1) * sides + j1, (i + 1) * sides + j))
            u0, u1 = j / sides * u_rep, (j + 1) / sides * u_rep
            uvs.append([(u0, v0), (u1, v0), (u1, v1), (u0, v1)])
    a, b = len(V) - 2, len(V) - 1
    for j in range(sides):
        j1 = (j + 1) % sides
        u0, u1 = j / sides * u_rep, (j + 1) / sides * u_rep
        faces.append((j1, j, a))
        uvs.append([(u1, 0.0), (u0, 0.0), ((u0 + u1) / 2, -0.1)])
        base = (n - 1) * sides
        faces.append((base + j, base + j1, b))
        ve = s[-1] / v_tile
        uvs.append([(u0, ve), (u1, ve), ((u0 + u1) / 2, ve + 0.1)])
    return V, faces, uvs


_ICO = {}


def icosphere(sub):
    if sub in _ICO:
        return _ICO[sub]
    t = (1 + 5 ** 0.5) / 2
    V = [(-1, t, 0), (1, t, 0), (-1, -t, 0), (1, -t, 0), (0, -1, t), (0, 1, t), (0, -1, -t), (0, 1, -t),
         (t, 0, -1), (t, 0, 1), (-t, 0, -1), (-t, 0, 1)]
    F = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6),
         (7, 1, 8), (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9), (4, 9, 5), (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1)]
    V = [np.array(v, float) / np.linalg.norm(v) for v in V]
    for _ in range(sub):
        cache = {}
        nf = []

        def mid(a, b):
            k = (min(a, b), max(a, b))
            if k not in cache:
                m = V[a] + V[b]
                V.append(m / np.linalg.norm(m))
                cache[k] = len(V) - 1
            return cache[k]

        for a, b, c in F:
            ab, bc, ca = mid(a, b), mid(b, c), mid(c, a)
            nf += [(a, ab, ca), (b, bc, ab), (c, ca, bc), (ab, bc, ca)]
        F = nf
    _ICO[sub] = (np.array(V), np.array(F, np.int64))
    return _ICO[sub]


def vertex_normals(V, F):
    fn = np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]])
    vn = np.zeros_like(V)
    for k in range(3):
        np.add.at(vn, F[:, k], fn)
    return norm(vn), norm(fn)


# ---- signed distance: limbs as chains of tapered capsules ----------------------------------------

class Chain:
    """A limb as a polyline with a radius at every point; dist() is the distance to its surface
    (negative inside)."""

    def __init__(self, C, R):
        self.C = np.asarray(C, float)
        self.R = np.asarray(R, float)
        self.A, self.B = self.C[:-1], self.C[1:]
        self.ra, self.rb = self.R[:-1], self.R[1:]
        self.AB = self.B - self.A
        self.l2 = np.maximum((self.AB * self.AB).sum(1), 1e-12)
        self.lo = (self.C - self.R[:, None]).min(0)
        self.hi = (self.C + self.R[:, None]).max(0)
        self.s = arclen(self.C)

    def dist(self, P, pad=None, want_s=False):
        """Distance to the surface; with want_s also the arc length of the nearest point of the axis."""
        P = np.atleast_2d(P)
        out = np.full(len(P), 1e3)
        sout = np.zeros(len(P))
        if pad is not None:
            m = np.all((P >= self.lo - pad) & (P <= self.hi + pad), axis=1)
            if not m.any():
                return (out, sout) if want_s else out
        else:
            m = np.ones(len(P), bool)
        Q = P[m]
        best = np.full(len(Q), 1e3)
        bs = np.zeros(len(Q))
        seg = np.diff(self.s)
        for i0 in range(0, len(Q), 4096):
            q = Q[i0 : i0 + 4096]
            AP = q[:, None, :] - self.A[None]
            t = np.clip((AP * self.AB[None]).sum(2) / self.l2[None], 0, 1)
            d = np.linalg.norm(AP - t[..., None] * self.AB[None], axis=2) - (self.ra[None] + t * (self.rb - self.ra)[None])
            j = d.argmin(1)
            r = np.arange(len(q))
            best[i0 : i0 + 4096] = d[r, j]
            bs[i0 : i0 + 4096] = self.s[j] + t[r, j] * seg[j]
        out[m] = best
        sout[m] = bs
        return (out, sout) if want_s else out


def smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b + (a - b) * h - k * h * (1.0 - h)


class Blend:
    """The smooth union of the limbs: the surface the junction vertices are pulled onto."""

    def __init__(self):
        self.items = []  # (Chain, k, fade) - fade = (s0, s1): the blend dies out along the limb

    def add(self, chain, k, ktab=None, solid=True):
        """k: blend radius; ktab = (arc lengths, radii): the radius along the limb (it dies out past
        the junction); solid = False for collar wood that only shapes the blend."""
        self.items.append((chain, float(k), ktab, solid))

    def _each(self, P):
        for ch, k, ktab, solid in self.items:
            if ktab is None:
                yield ch.dist(P, pad=k + 0.5), k, solid
            else:
                d, s = ch.dist(P, pad=k + 0.5, want_s=True)
                yield d, np.interp(s, ktab[0], ktab[1]), solid

    def fields(self, P):
        """-> (hard union of the limbs, smooth union with the collars) at P."""
        hard = np.full(len(P), 1e3)
        soft = np.full(len(P), 1e3)
        for d, k, solid in self._each(P):
            if solid:
                hard = np.minimum(hard, d)
            soft = smin(soft, d, k)
        return hard, soft

    def soft(self, P):
        soft = np.full(len(P), 1e3)
        for d, k, _ in self._each(P):
            soft = smin(soft, d, k)
        return soft

    def grad(self, P, eps=0.02):
        tet = np.array([[1, -1, -1], [-1, -1, 1], [-1, 1, -1], [1, 1, 1]], float)
        vals = [self.soft(P + tet[i] * eps) for i in range(4)]
        d = sum(vals) / 4
        g = sum(vals[i][:, None] * tet[i] for i in range(4)) / (4 * eps)
        return d, g


# ---- the tree -----------------------------------------------------------------------------------

def trunk_radius_fn(trunk):
    r = trunk["surfaceRadius"] * SPU
    if "giant trunk" in trunk["name"]:
        return lambda t: np.maximum(0.45 * SPU, r / 0.95 - 1.05 * SPU * np.asarray(t))
    return lambda t: np.maximum(0.32 * SPU, r * (1 - 0.48 * np.asarray(t)))


def lift_of(route):
    if route.get("visualOffset") is not None:
        return route["visualOffset"] * SPU
    return 0.61 * SPU if route["kind"] == "lookout" else 0.5 * SPU


class Limb:
    """One tube of the main skin."""

    def __init__(self, name, kind, C, R, sides, k, radius_fn=None, start_normal=None, u_rep=1, v_tile=4.0, fr=None):
        self.name, self.kind = name, kind
        self.C, self.R = np.asarray(C, float), np.asarray(R, float)
        self.sides, self.k = sides, k
        self.radius_fn = radius_fn or (lambda i, ang, R=self.R: np.full_like(ang, R[i]))
        self.start_normal = start_normal
        self.u_rep, self.v_tile = u_rep, v_tile
        self.chain = Chain(self.C, self.R)
        self.fr = fr if fr is not None else frames(self.C, start_normal)
        self.s = arclen(self.C)

    def uv(self, P):
        """Bark coordinates of points near this limb: u round it (0..u_rep, the ring's own angle), v
        along it. The same numbers the tube's rings carry, for any point of the blended skin."""
        ch = self.chain
        T, Ns, Bs = self.fr
        AP = P[:, None, :] - ch.A[None]
        t = np.clip((AP * ch.AB[None]).sum(2) / ch.l2[None], 0, 1)
        d = np.linalg.norm(AP - t[..., None] * ch.AB[None], axis=2) - (ch.ra[None] + t * (ch.rb - ch.ra)[None])
        i = np.argmin(d, axis=1)
        ti = t[np.arange(len(P)), i]
        c = ch.A[i] + ti[:, None] * ch.AB[i]
        N = norm(Ns[i] * (1 - ti)[:, None] + Ns[i + 1] * ti[:, None])
        Tn = norm(T[i] * (1 - ti)[:, None] + T[i + 1] * ti[:, None])
        B = np.cross(Tn, N)
        rel = P - c
        phi = np.arctan2((rel * B).sum(1), (rel * N).sum(1)) % (2 * math.pi)
        seg = self.s[i + 1] - self.s[i]
        over = np.where((ti <= 0) | (ti >= 1), (rel * Tn).sum(1), 0.0)
        return np.stack([phi / (2 * math.pi) * self.u_rep, (self.s[i] + ti * seg + over) / self.v_tile], axis=1)


class TreeBuilder:
    def __init__(self, rec, data, opts=None):
        self.rec = rec
        self.data = data
        self.opts = opts or {}
        self.rng = np.random.default_rng(rec["seed"])
        self.root = rec["root"]
        self.H = rec["H"]
        self.cat = rec["category"]
        self.sp = rec["species"]
        self.par = SPECIES[self.sp]
        # everything that grows is sized to the tree
        self.scale = float(np.clip(self.H / 75.0, 0.8, 1.35)) if self.sp != "apple" else 1.0
        self.bark = Mesh()
        self.leaf = {"shade": Mesh(), "mid": Mesh(), "sun": Mesh()}
        self.fruit = Mesh()
        self.rails = []  # (polyline studs local, lift, kind, name, route id)
        self.limbs = []  # main skin tubes
        self.boughs = []  # walkable limbs and decor limbs: where side branches grow
        self.tunnels = []  # (A, B, r) capsule segments
        self.branches = []  # grown side branches (dicts)
        self.cards = []  # leaf sprays (dicts)
        self.zones = []  # (y0, y1) trunk heights where collars add wood
        self.log = {}

    # -- coordinates --
    def local(self, P):
        return (np.asarray(P, float) * SPU) - self.root[None]

    def samples(self, rid):
        """A route of this tree, every quarter stud along the game's curve, local to the pivot."""
        cache = self.data.setdefault("dense", {})
        if rid not in cache:
            cache[rid] = Curve(np.asarray(self.data["routes"][rid]["points"], float) * SPU).dense()
        return cache[rid] - self.root[None]

    # -- tunnels --
    def add_tunnel_polyline(self, P, r, lift_up=0.0, step=1.5):
        Q, _, _ = resample(P, step)
        Q = Q + np.array([0.0, lift_up, 0.0])
        for a, b in zip(Q[:-1], Q[1:]):
            self.tunnels.append((a, b, r))

    def tunnel_arrays(self):
        if not self.tunnels:
            z = np.zeros((0, 3))
            return z, z, np.zeros(0)
        A = np.array([t[0] for t in self.tunnels])
        B = np.array([t[1] for t in self.tunnels])
        r = np.array([t[2] for t in self.tunnels])
        return A, B, r

    def clearance(self, P):
        """For points P (n,3): min over tunnels of (distance - tunnel radius)."""
        A, B, r = self._tun
        P = np.atleast_2d(P)
        if len(A) == 0:
            return np.full(len(P), 1e9)
        out = np.empty(len(P))
        for i0 in range(0, len(P), 2048):
            out[i0 : i0 + 2048] = (seg_dist(P[i0 : i0 + 2048], A, B) - r[None]).min(axis=1)
        return out

    # -- build --
    def build(self):
        rec = self.rec
        trunk = rec["trunk"]
        self.Rt = trunk_radius_fn(trunk)
        self.plan_trunk(trunk)
        for m in rec["members"]:
            self.plan_bough(m)
        self.collect_foreign_tunnels()
        self._tun = self.tunnel_arrays()
        self.crown = self.crown_frame()
        self.relieve_crossings()
        if self.cat == "giant":
            self.plan_decor_limbs()
        self.plan_roots()
        self.build_skin()
        self.grow_all()
        self.fit_bark_budget()
        self.mesh_branches()
        self.build_leaves()
        if self.sp == "apple":
            self.build_apples()
        return self

    # .. trunk ..
    def plan_trunk(self, trunk):
        P = self.samples(trunk["id"])
        self.trunkP = P
        sP = arclen(P)
        L = sP[-1]
        self.trunkL = L
        self.trunk_s = sP
        self.rails.append((P, 0.0, "trunk", trunk["name"], trunk["id"]))
        giant = self.cat == "giant"
        # where boughs leave: rings close together there, so the collars have vertices to live on
        forks = {}
        for m in self.rec["members"]:
            mp = self.samples(m["id"])
            d = np.linalg.norm(P - mp[0][None], axis=1)
            j = int(np.argmin(d))
            if d[j] < 3.5:
                forks.setdefault(round(float(sP[j]), 1), []).append(m["id"])
        self.fork_s = sorted(forks)
        ss = list(np.linspace(0, L, max(2, int(math.ceil(L / (3.8 if giant else 3.0))) + 1)))
        for sf in self.fork_s:
            rt = float(self.Rt(sf / L))
            for k in (-1.4, -0.8, -0.3, 0.15, 0.6, 1.1, 1.7, 2.4):
                ss.append(sf + k * rt * 1.15)
            self.zones.append((float(np.interp(sf, sP, P[:, 1])) - 1.7 * rt, float(np.interp(sf, sP, P[:, 1])) + 3.8 * rt))
        ss += list(adaptive_s(P, tol=0.03, max_step=3.8 if giant else 3.0))  # (a bent trunk: within 0.03 of its route)
        ss = sorted(s for s in ss if 0 <= s <= L)
        keep = [ss[0]]
        for s in ss[1:]:
            if s - keep[-1] > 0.6:
                keep.append(s)
        if L - keep[-1] > 1e-6:
            keep[-1] = L
        s = np.array(keep)
        Q = at_s(P, sP, s)
        t = s / L
        # carry the trunk down into the ground (pivot y = 0 is the ground at the root)
        foot = Q[0]
        below = [np.array([foot[0], y, foot[2]]) for y in (-3.0, -1.6, -0.6) if y < foot[1] - 0.2]
        # leader: the trunk's wood goes on above its route into the crown as one more limb. It leaves the
        # top to the side and turns up, on whichever side keeps it clear of the walks: of those that start
        # at the top (a bridge's first step is on the trunk's axis: nothing may stand over it) and of the
        # boughs that climb past it
        top, ttan = Q[-1], norm(Q[-1] - Q[-2])
        Rtop = float(self.Rt(1.0))
        crown_top = self.H * (self.par["top"] - 0.10)
        lead_len = max(0.0, crown_top - top[1]) * (0.5 if giant else 0.78)
        rng = self.rng
        away = np.zeros(3)
        axis_walk = False  # an unpushed walk starts on the trunk's axis
        body = []  # the squirrel's body line on every walk near the top
        for m in self.rec["members"]:
            if m["name"].endswith("OPEN SKY LOOKOUT"):
                continue
            mp = self.samples(m["id"])
            sm = arclen(mp)
            pushed = m["kind"] == "branch" and m.get("trunkClearance")
            if np.linalg.norm(mp[0] - top) < 3.0:
                h = (mp[min(len(mp) - 1, 24)] - mp[0]) * np.array([1.0, 0.0, 1.0])
                if np.linalg.norm(h) > 1e-6:
                    away -= norm(h) * (1.0 if pushed else 3.0)
                axis_walk = axis_walk or not pushed
            pts = mp[sm >= (0.2 * sm[-1] if pushed else 0.0)] + Y[None] * (lift_of(m) + 1.0)
            pts = pts[np.linalg.norm(pts - top[None], axis=1) < lead_len + 8.0]
            if len(pts):
                body.append(pts[::2])
        body = np.concatenate(body) if body else np.zeros((0, 3))

        def leader_path(lean, length):
            if lean is None:  # straight on from the trunk
                return top - ttan * 0.5 * Rtop, top + ttan * length * 0.45, top + norm(ttan * 0.4 + Y) * length, 0.9 * Rtop
            p0 = top + lean * 0.5 * Rtop
            return p0, p0 + norm(Y * 0.67 + lean * 0.74) * length * 0.4, top + norm(Y + 0.45 * lean) * length, 0.66 * Rtop

        def leader_room(lean, length):
            p0, p1, p2, r0 = leader_path(lean, length)
            f = np.linspace(0, 1, 25)[:, None]
            path = (1 - f) ** 2 * p0 + 2 * (1 - f) * f * p1 + f * f * p2
            if not len(body):
                return 9.0
            rr = r0 + (max(0.3, Rtop * 0.2) - r0) * f[:-1, 0] ** 0.85
            return float((seg_dist(body, path[:-1], path[1:]) - rr[None]).min())

        self.leader = None
        if lead_len > Rtop * 1.5:
            leans = [np.array([math.cos(a0), 0.0, math.sin(a0)]) for a0 in np.arange(16) * (math.pi / 8)]
            pick = None
            for length in (lead_len, 0.6 * lead_len, 0.35 * lead_len):
                cands = []
                for ln in leans + ([] if axis_walk else [None]):
                    room = leader_room(ln, length)
                    if ln is None:
                        bonus = 0.6 if np.linalg.norm(away) < 0.1 else 0.0
                    else:
                        bonus = 0.4 * float(np.dot(ln, norm(away + 1e-9))) * (np.linalg.norm(away) > 0.1)
                    cands.append((room + bonus, room, ln))
                best = max(cands, key=lambda c: c[0])
                if best[1] >= 1.0 or pick is None or best[1] > pick[0] + 0.5:
                    pick = (best[1], best[2], length)
                if best[1] >= 1.0:
                    break
            room, lean, lead_len = pick
            self.log["leader_room"] = round(room, 2)
            if room > 0.2 and lead_len > Rtop * 1.5:
                k = max(4, int(lead_len / 2.4))
                p0, p1, p2, r0 = leader_path(lean, lead_len)
                side = norm(np.cross(p2 - p0, [0.3, 0.1, 0.9]))
                LP = []
                for j in range(k + 1):
                    f = j / k
                    wob = side * math.sin(f * 7.0 + rng.random() * 0.5) * 0.35 * f * (1 - f) * 4
                    LP.append((1 - f) ** 2 * p0 + 2 * (1 - f) * f * p1 + f * f * p2 + wob)
                LP = np.array(LP)
                LR = r0 + (max(0.3, Rtop * 0.2) - r0) * np.linspace(0, 1, k + 1) ** 0.85
                self.leader = (LP, LR)
        # (one ring just above the route's top, under a flat cap: the top of the climb is still trunk)
        C = np.concatenate([np.array(below).reshape(-1, 3), Q, (top + ttan * 0.3)[None]])
        nb = len(below)
        tt = np.concatenate([np.zeros(nb), t, [1.0]])
        R0 = float(self.Rt(0.0))
        base = self.Rt(tt)
        # root flare: buttress lobes that the roots continue (decaying over about one foot radius)
        self.root_n = 5 if self.sp == "apple" else 5 + int(rng.integers(0, 3))
        ra0 = rng.random() * 6.28
        self.root_ang = np.array([ra0 + k * 2 * math.pi / self.root_n + rng.normal(0, 0.22) for k in range(self.root_n)])
        lobe_amp = 0.5 + 0.4 * rng.random(self.root_n)
        flute_ph = rng.random() * 6.28
        start_normal = np.array([1.0, 0.0, 0.0])

        def radius(i, ang):
            y = C[i][1]
            fall = math.exp(-(max(0.0, y) / (0.5 * R0)) ** 2)  # gone by the height the climb starts at
            lob = np.zeros_like(ang)
            # the ring's angle 0 is +X (start_normal) and grows toward T x N = Y x X = -Z
            for a0, amp in zip(self.root_ang, lobe_amp):
                da = np.angle(np.exp(1j * (ang + a0)))
                lob += amp * np.exp(-(da / 0.42) ** 2)
            # (the game stands the squirrel at the tapered radius all the way round: the flutes are
            # shallow, and the ring's corners stand as far outside that radius as its flats lie inside)
            flute = 0.02 * np.sin(ang * 7 + flute_ph + y * 0.15) + 0.012 * np.sin(ang * 3 - y * 0.31)
            r = base[i] * (1 + 0.5 * facet) * (1 + 0.55 * fall * lob) + flute * min(1.0, base[i] / 2.0)
            return np.maximum(r, 0.2)

        circ = 2 * math.pi * R0
        u_rep = max(2, int(round(circ / 4.5)))
        v_tile = circ / u_rep * 1.3
        sides = 18 if R0 > 3.6 else (14 if R0 > 2.4 else (12 if R0 > 1.6 else 10))
        facet = 1 - math.cos(math.pi / sides)
        # (rings lie level, whatever the trunk's lean: the game measures its radius horizontally)
        level = (frames(C, start_normal)[0], np.tile(start_normal, (len(C), 1)), np.tile([0.0, 0.0, -1.0], (len(C), 1)))
        limb = Limb("trunk", "trunk", C, base, sides, 0.0, radius, start_normal, u_rep, v_tile, fr=level)
        limb.cap = (0.4, 0.3)
        self.limbs.append(limb)
        self.trunk_limb = limb
        if self.leader is not None:
            LP, LR = self.leader
            self.leader_limb = Limb("leader", "leader", LP, LR, 8 if LR[0] > 1.0 else 6, 0.45, None, None,
                                    max(1, int(round(2 * math.pi * LR[0] / 4.0))), 4.0)
            self.limbs.append(self.leader_limb)
        # trunk tunnel: the squirrel orbits the bark (tapered + 0.7 st) -> keep leaves 2.6 st beyond
        Qt, st_, tq = resample(P, 2.4)
        for a, b, ta, tb in zip(Qt[:-1], Qt[1:], tq[:-1], tq[1:]):
            self.tunnels.append((a, b, float(self.Rt((ta + tb) / 2)) + 0.7 + 2.6))
        self.log["trunk_rings"] = len(C)

    def trunk_r_at_y(self, y):
        P = self.trunkP
        tt = self.trunk_s / max(self.trunkL, 1e-9)
        return float(self.Rt(np.interp(y, P[:, 1], tt)))

    # .. boughs, bridges, lookouts ..
    def plan_bough(self, route):
        P = self.samples(route["id"])
        kind = route["kind"]
        lift = lift_of(route)
        self.rails.append((P, lift, kind, route["name"], route["id"]))
        name = route["name"]
        if name.endswith("OPEN SKY LOOKOUT"):
            self.plan_lookout_pad(P, lift)
            return
        sP = arclen(P)
        L = sP[-1]
        start = P[0]
        dtrunk = seg_dist(start[None], self.trunkP[:-1], self.trunkP[1:]).min()
        on_trunk = dtrunk < 3.5
        rt = self.trunk_r_at_y(start[1]) if on_trunk else 1.2
        cat = self.cat
        # (with its collar a bough stays within 2 studs of its route all round: what leaves the trunk
        # there is the bough the squirrel steps onto, not wood in the way of the trunk climb)
        cap = {"named": 1.4, "outer": 1.2, "giant": 1.4, "apple": 0.62, "estate": 1.4}[cat]
        cap = min(cap, (2.0 + lift) / 2 / (1 + COLLAR))
        r_tip = max(0.5 * lift + 0.08, 0.32)
        r_base = cap
        if kind == "bridge":
            r_base *= 0.85
        if kind == "lookout":
            r_base = 1.05
        if on_trunk:
            r_base = min(r_base, 0.64 * rt)
        r_base = max(r_base, r_tip * 1.22)
        par = self.par
        rng = self.rng
        # side branches: where they leave and how much wood each takes (the bough thins after each)
        # the junction reaches as far as the limb still touches the trunk (a steep limb hugs it for long)
        clear = s_exit = 0.0
        if on_trunk:
            sd, _, _ = resample(P, 0.5)
            ssd = arclen(sd)
            dt = self.trunk_limb.chain.dist(sd)
            out = dt > (r_base + 0.35)
            clear = float(ssd[int(np.argmax(out))]) if out.any() else float(ssd[-1])
            clear = min(clear, 0.3 * L)
            s_exit = min(float(ssd[int(np.argmax(dt > 0))]) if (dt > 0).any() else 0.0, clear)
        zone = max(2.4 * rt + 3.0, clear + 2.0) if on_trunk else 3.0  # no side branches inside it
        s0 = max(zone + 1.0, 0.2 * L)
        spacing = par["spacing"] * self.scale * (1.9 if kind == "bridge" else 1.0)
        s1 = L * (0.72 if kind == "bridge" else 0.97) - 1.0
        kids = []
        if s1 > s0 and kind != "lookout":
            n = int(np.clip(round((s1 - s0) / spacing), 1, 9))
            for k in range(n):
                kids.append(s0 + (s1 - s0) * (k + 0.5 + rng.uniform(-0.3, 0.3)) / n)
        kids = np.array(kids)
        w = rng.uniform(0.7, 1.3, len(kids)) * (1.25 - 0.5 * kids / max(L, 1e-9)) if len(kids) else np.zeros(0)
        area = r_base ** 2 - r_tip ** 2
        give = 0.62 * area * w / max(w.sum(), 1e-9) if len(kids) else np.zeros(0)
        # samples: few on the straight runs, close together through the junction
        ss = list(adaptive_s(P, tol=0.035, max_step=3.4 if L < 30 else 4.4, upright=True))
        if on_trunk:
            ss += list(np.arange(0.0, zone, 0.48 * rt + 0.1))
        ss = sorted(ss)
        keep = [ss[0]]
        for s in ss[1:]:
            if s - keep[-1] > 0.3:
                keep.append(s)
        keep[-1] = L
        s = np.array(keep)
        Q = at_s(P, sP, s)
        u = s / L
        a2 = r_tip ** 2 + 0.38 * area * (1 - u) ** 1.2
        for sk, g in zip(kids, give):
            a2 = a2 + g * (1 - smoothstep((s - sk) / 1.6 + 0.2))
        radii = np.sqrt(a2)
        if on_trunk:
            # the collar: the bough swells where it leaves the trunk
            radii = radii * (1 + COLLAR * (1 - smoothstep((s - s_exit) / (1.8 * r_base))))
            # the feet line is the tube's top edge, so a steep bough hangs to one side of its route: it
            # is kept thin enough to stay within 2 studs of the route all round (see cap) and does not
            # fatten again further out
            level = np.sqrt(np.clip(1 - norm(np.gradient(Q, axis=0))[:, 1] ** 2, 0, 1))
            rmax = (2.0 ** 2 - lift ** 2) / (2 * (2.0 - lift * level))
            radii = np.minimum.accumulate(np.minimum(radii, np.maximum(rmax, r_tip)))
        # the feet line (rail + lift) is the tube's top generator at any slope: centre = feet - r * up_perp
        T = norm(np.gradient(Q, axis=0))
        ups = []
        prev = None
        for t in T:
            prev = perp_up(t, prev)
            ups.append(prev)
        ups = np.array(ups)
        sides = 8 if r_base > 1.0 else 6
        circ = 2 * math.pi * r_base
        u_rep = max(1, int(round(circ / 4.0)))
        b = {"route": route, "P": P, "sP": sP, "s": s, "radii": radii, "L": L, "lift": lift, "kind": kind,
             "on_trunk": on_trunk, "rt": rt, "zone": zone, "clear": clear, "kids": kids, "give": give, "r_tip": r_tip,
             "rail": Q, "ups": ups, "sides": sides, "u_rep": u_rep, "v_tile": circ / u_rep * 1.3,
             "k": 0.5, "wob": rng.random() * 6.28}
        self.bough_limb(b)
        self.limbs.append(b["limb"])
        self.boughs.append(b)
        # tunnel above the rail where the squirrel's body is (feet = rail + lift)
        self.add_tunnel_polyline(P, 2.6 if self.sp != "apple" else 2.0, lift_up=lift + 0.9)

    def bough_limb(self, b):
        """(Re)build a bough's tube from its rail, radii and lift. The squirrel's feet line (rail + lift)
        is the tube's top edge: every ring has a corner on it, at any slope."""
        Q, radii, lift = b["rail"], b["radii"], b["lift"]
        # one more ring before the rail's start and one past its end, so the walk's first and last
        # steps still have bark under them
        t0, tend = norm(Q[1] - Q[0]), norm(Q[-1] - Q[-2])
        feet = np.concatenate([Q[:1] - t0 * 0.45, Q, Q[-1:] + tend * 0.45]) + Y[None] * lift
        R = np.concatenate([radii[:1], radii, radii[-1:]])
        # ring planes square to the feet line, except through a tight bend (a willow bough arching
        # over): there they turn no faster than the tube's far side can follow without folding
        T = frames(feet)[0]
        ds = np.linalg.norm(np.diff(feet, axis=0), axis=1)
        lim = ds / (2.3 * np.maximum(R[:-1], R[1:]))
        for _ in range(60):
            ang = np.arccos(np.clip((T[:-1] * T[1:]).sum(1), -1, 1))
            bad = ang > lim
            if not bad.any():
                break
            m = np.zeros(len(T), bool)
            m[:-1] |= bad
            m[1:] |= bad
            m[0] = m[-1] = False
            Tn = T.copy()
            Tn[1:-1] = norm(T[:-2] + 2 * T[1:-1] + T[2:])
            T = np.where(m[:, None], Tn, T)
        # (where the route stands plumb, as some do inside the trunk, "up" is taken from where it leans
        # next: back toward where it came from)
        back = (Q[0] - Q[-1]) * np.array([1.0, 0.0, 1.0])
        prev, ups = (norm(back) if np.linalg.norm(back) > 1e-6 else None), []
        for t in T:
            prev = perp_up(t, prev)
            ups.append(prev)
        U = np.array(ups)
        C = feet - U * R[:, None]
        N = -U
        wob = b["wob"]

        def radius(i, ang, R=R):
            # ring angle 0 is straight down, pi the top: the bark's unevenness dies out toward the top
            return R[i] * (1 + 0.035 * np.sin(ang * 3 + wob + i * 0.4) * (1 + np.cos(ang)) / 2)

        limb = Limb(f"route{b['route']['id']}", b["kind"], C, R, b["sides"], b["k"], radius, None, b["u_rep"], b["v_tile"],
                    fr=(T, N, np.cross(T, N)))
        # the blend belongs to the junction: past it, boughs that run side by side stay two round limbs
        zone, clear = b["zone"], b["clear"]
        limb.fade = (max(0.55 * zone, clear + 0.5), max(1.2 * zone, clear + 4.5))
        limb.feet, limb.U = feet, U
        b["limb"], b["Q"] = limb, C[1:-1]

    def relieve_crossings(self):
        """Routes of one tree cross each other. A bough's tube hangs under its own feet line, so where
        another walk passes close under that line the tube would swallow it: there the bough is waisted
        (down to a radius of 0.42 studs), and the other walk passes under clear wood."""
        walk = [b for b in self.boughs if b["kind"] in ("branch", "bridge")]
        marg, floor = 0.12, 0.42
        n = 0
        for b in walk:
            limb, s, R0 = b["limb"], b["s"], b["radii"]
            sd = np.minimum(np.arange(0.0, s[-1] + 0.5, 0.5), s[-1])
            Fd = at_s(limb.feet[1:-1], s, sd)
            Ud = norm(at_s(limb.U[1:-1], s, sd))
            rmax = np.full(len(sd), 1e3)
            for o in walk:
                if o is b:
                    continue
                pushed = o["kind"] == "branch" and o["route"].get("trunkClearance")
                m = o["sP"] >= (0.2 * o["L"] if pushed else 0.75)
                if m.sum() < 2:
                    continue
                Fo = o["P"][m] + Y[None] * o["lift"]
                if np.all(Fo.min(0) > Fd.max(0) + 4) or np.all(Fo.max(0) < Fd.min(0) - 4):
                    continue
                # a ring of radius r under the feet point f swallows q when |f - U r - q| < r + marg
                w = Fd[:, None, :] - Fo[None]
                ww = (w * w).sum(2)
                wu = (w * Ud[:, None, :]).sum(2) + marg
                cand = np.where(wu > 1e-6, (ww - marg ** 2) / (2 * np.maximum(wu, 1e-6)), 1e3)
                rmax = np.minimum(rmax, np.maximum(cand, 0.0).min(1))
            R = R0.copy()
            for i in range(len(s)):  # each ring answers for the stretch to its neighbours
                mm = (sd >= s[max(i - 1, 0)]) & (sd <= s[min(i + 1, len(s) - 1)])
                if mm.any():
                    R[i] = min(R[i], float(rmax[mm].min()))
            R = np.maximum(R, np.minimum(floor, R0))
            if (R < R0 - 0.02).any():
                # ease into the waist
                for _ in range(2):
                    R = np.minimum(R, np.concatenate([[R[0]], (R[:-2] + R[2:]) / 2 + 0.08, [R[-1]]]))
                R = np.maximum(np.minimum(R, R0), np.minimum(floor, R0))
                b["radii"] = R
                i = self.limbs.index(b["limb"])
                self.bough_limb(b)
                self.limbs[i] = b["limb"]
                n += 1
        self.log["boughs_relieved"] = n

    def plan_decor_limbs(self):
        """Giants: non-walkable limbs from the trunk top into the gaps between the lookout boughs,
        leaving level for 8+ studs (clear of the trunk climb) and then drooping, so the crown has depth."""
        top = self.trunkP[-1]
        walk = [b for b in self.boughs if b["kind"] == "branch"]
        if not walk:
            return
        az = sorted(math.atan2(b["P"][-1][2] - top[2], b["P"][-1][0] - top[0]) for b in walk)
        reach = float(np.mean([np.hypot(b["P"][-1][0] - top[0], b["P"][-1][2] - top[2]) for b in walk]))
        gaps = [(az[(i + 1) % len(az)] - az[i]) % (2 * math.pi) for i in range(len(az))]
        mids = [az[i] + gaps[i] / 2 for i in range(len(az))]
        for n, a0 in enumerate(mids):
            out = np.array([math.cos(a0), 0, math.sin(a0)])
            ctrl = np.array([top + np.array([0, 2.3, 0]), top + out * 9 + np.array([0, 3.2, 0]),
                             top + out * reach * 0.45 + np.array([0, -self.H * 0.06, 0]),
                             top + out * reach * 0.68 + np.array([0, -self.H * 0.13, 0])])
            pts = []
            for i in range(len(ctrl) - 1):
                p0 = ctrl[max(i - 1, 0)]
                p1, p2 = ctrl[i], ctrl[i + 1]
                p3 = ctrl[min(i + 2, len(ctrl) - 1)]
                for f in np.linspace(0, 1, 5)[:-1]:
                    pts.append(0.5 * ((2 * p1) + (-p0 + p2) * f + (2 * p0 - 5 * p1 + 4 * p2 - p3) * f * f + (-p0 + 3 * p1 - 3 * p2 + p3) * f ** 3))
            pts.append(ctrl[-1])
            P = np.array(pts)
            if self.clearance(P[3:]).min() < 0.5:
                continue
            s = arclen(P)
            L = s[-1]
            radii = 0.55 + (1.5 - 0.55) * (1 - s / L) ** 1.2
            limb = Limb(f"decor{n}", "decor", P, radii, 8, 0.5, None, None, 2, 6.0)
            limb.fade = (6.0, 12.0)
            self.limbs.append(limb)
            kids = np.linspace(0.3 * L, 0.92 * L, 5)
            self.boughs.append({"route": {"name": "decor", "id": -1 - n, "kind": "decor"}, "P": P, "sP": s, "Q": P, "s": s,
                                "radii": radii, "L": L, "lift": 0.0, "kind": "decor", "on_trunk": True, "rt": 2.0, "zone": 8.0,
                                "limb": limb, "kids": kids, "give": np.full(5, 0.3), "r_tip": 0.55, "clear": 8.0})

    def plan_lookout_pad(self, P, lift):
        """The giants' open-sky perch: a burl with a flat top at the squirrel's feet, small and thin
        enough that the bough ending under it keeps its own top clear, on a stub that leaves the
        bough's tip past the end of the walk."""
        mid = P.mean(axis=0)
        feet = mid[1] + lift
        self.pads = getattr(self, "pads", [])
        self.pads.append((mid, feet))
        self.add_tunnel_polyline(np.array([mid, mid + [0, 12, 0]]), 9.0)
        ends = [(float(np.linalg.norm(b["rail"][-1] - mid)), b) for b in self.boughs if b["kind"] == "branch"]
        if ends and min(ends, key=lambda e: e[0])[0] < 5.0:
            b = min(ends, key=lambda e: e[0])[1]
            E = b["Q"][-1]
            tend = norm(b["rail"][-1] - b["rail"][-2])
            fwd = norm(tend * np.array([1.0, 0.0, 1.0]) + 1e-9)
            under = np.array([mid[0], feet - 0.62, mid[2]]) + fwd * 1.0
            pts = np.array([E + tend * 0.2, E + fwd * 1.0 + Y * 0.1, (E + fwd * 1.0 + under) / 2 + fwd * 0.15, under])
            self.limbs.append(Limb(f"stub{len(self.pads)}", "decor", pts, np.array([0.5, 0.42, 0.4, 0.45]), 5, 0.3, None, None, 1, 3.0))

    def collect_foreign_tunnels(self):
        """Routes that are not this tree's (wires, roofs, gutters, the treehouse, other trees' boughs)
        but pass through the crown: keep leaves off them too."""
        mine = {self.rec["trunk"]["id"]} | {m["id"] for m in self.rec["members"]}
        lo = np.array([-60.0, -5.0, -60.0])
        hi = np.array([60.0, self.H * 1.15 + 10, 60.0])
        if self.cat == "giant":
            lo, hi = np.array([-90.0, -5.0, -90.0]), np.array([90.0, self.H * 1.15, 90.0])
        n = 0
        for rid, pts in self.data["samples"].items():
            if rid in mine:
                continue
            P = self.local(pts)
            inside = np.all((P >= lo) & (P <= hi), axis=1)
            if not inside.any():
                continue
            r = self.data["routes"][rid]
            k = r["kind"]
            lift = {"wire": 0.22 * SPU, "branch": 1.25, "bridge": 1.25, "lookout": 1.525}.get(k, 0.0)
            rad = 2.4 if k != "trunk" else r["surfaceRadius"] * SPU + 3.0
            idx = np.where(inside)[0]
            seg = P[max(0, idx[0] - 1) : idx[-1] + 2]
            if len(seg) >= 2:
                self.add_tunnel_polyline(seg, rad, lift_up=lift + (0.9 if k != "trunk" else 0.0))
                n += 1
        # buildings (approximate volumes from the harvest): leaves stay out
        self.boxes = []
        hs = self.data["houses"]
        for h in hs["houses"]:
            peak = h["cfg"].get("peak", 10) * 0.82
            w = max(h["w"], h["d"]) / 2
            self._add_box(h["x"], h["z"], w, w, None, peak)
        for c in hs["commercialBounds"]:
            self._add_box(c["x"], c["z"], c["w"] / 2, c["d"] / 2, None, c["roof"])
        for b in hs["riverBuildings"]:
            w = max(b["w"], b["d"]) / 2
            self._add_box(b["x"], b["z"], w, w, b["base"], b["base"] + b["h"] + b["rise"])
        self.log["foreign_routes_in_crown"] = n

    def _add_box(self, x, z, hx, hz, y0, y1):
        c = np.array([x * SPU, 0, z * SPU]) - self.root
        if abs(c[0]) > 120 or abs(c[2]) > 120:
            return
        ylo = (y0 * SPU - self.root[1]) if y0 is not None else -5.0
        yhi = (y1 * SPU - self.root[1]) + (1.0 if y0 is None else 0.0)  # roofs are absolute heights in v5.4
        self.boxes.append((np.array([c[0] - hx * SPU, ylo, c[2] - hz * SPU]), np.array([c[0] + hx * SPU, yhi, c[2] + hz * SPU])))

    def box_clear(self, P):
        """Distance from points to the nearest building volume."""
        P = np.atleast_2d(P)
        if not self.boxes:
            return np.full(len(P), 1e9)
        if getattr(self, "_boxes", None) is None:
            self._boxes = (np.array([b[0] for b in self.boxes]), np.array([b[1] for b in self.boxes]))
        lo, hi = self._boxes
        out = np.empty(len(P))
        for i0 in range(0, len(P), 4096):
            p = P[i0 : i0 + 4096, None, :]
            d = np.maximum(np.maximum(lo[None] - p, p - hi[None]), 0)
            out[i0 : i0 + 4096] = np.linalg.norm(d, axis=2).min(1)
        return out

    # .. roots ..
    def plan_roots(self):
        rng = self.rng
        R0 = float(self.Rt(0.0))
        for k, a in enumerate(self.root_ang):
            d = np.array([math.cos(a), 0.0, math.sin(a)])
            Lr = R0 * (1.7 + 1.2 * rng.random())
            m = 6
            pts = []
            for j in range(m):
                f = j / (m - 1)
                rad = R0 * 0.3 + Lr * f
                y = 0.5 * R0 * (1 - f) ** 1.6 + 0.12 * R0 * math.sin(f * math.pi) - 1.3 * f ** 2
                side = np.array([-d[2], 0, d[0]]) * math.sin(f * 3 + k) * 0.25 * R0 * f
                pts.append(d * rad + np.array([0, y, 0]) + side)
            pts = np.array(pts)
            r0 = R0 * (0.40 + 0.12 * rng.random())
            f = np.linspace(0, 1, m)
            radii = np.maximum(0.12, r0 * (1 - f) ** 1.1 + 0.1)
            self.limbs.append(Limb(f"root{k}", "root", pts, radii, 5, float(np.clip(0.9 * r0, 0.4, 1.6)), None, None, 1, 3.0))

    # .. the skin: union the tubes, then pull the junctions onto the smooth blend ..
    def build_skin(self):
        blend = Blend()
        for limb in self.limbs:
            k0 = max(limb.k, 0.05)
            ktab = None
            fade = getattr(limb, "fade", None)
            if fade is not None:
                kk = k0 * (1 - smoothstep((limb.s - fade[0]) / max(fade[1] - fade[0], 1e-6)))
                feet = getattr(limb, "feet", None)
                if feet is not None:
                    # the blend must not bury the squirrel's feet line: where that line has left the
                    # other limbs, the web between them stays thinner than the room under it
                    g = np.full(len(feet), 1e3)
                    for other in self.limbs:
                        if other is not limb and other.kind != "root":
                            g = np.minimum(g, other.chain.dist(feet, pad=6.0))
                    out = g > 0.02
                    if out.any():
                        j = int(np.argmax(out))
                        kk[j:] = np.minimum(kk[j:], np.clip(0.9 * g[j:], 0.03, k0))
                ktab = (limb.s, np.maximum(kk, 0.03))
            blend.add(limb.chain, k0, ktab)
        self.blend = blend
        parts = []
        for li, limb in enumerate(self.limbs):
            V, faces, uvs = closed_tube(limb.C, limb.radius_fn, limb.sides, limb.u_rep, limb.v_tile, limb.start_normal, limb.fr,
                                        getattr(limb, "cap", (0.4, 0.6)))
            parts.append({"V": V, "faces": faces, "uvs": uvs, "id": li})
        for pi, (mid, feet) in enumerate(getattr(self, "pads", [])):
            parts.append(self.pad_part(mid, feet, len(self.limbs) + pi))
        union = self.opts.get("union")
        res = union(parts) if union is not None else None
        if res is None:
            # no Blender: the tubes as they are (previews and tests of the numpy side only)
            Vs, Fs, UVs, own = [], [], [], []
            off = 0
            for p in parts:
                for f, uv in zip(p["faces"], p["uvs"]):
                    for k in range(1, len(f) - 1):
                        Fs.append((off + f[0], off + f[k], off + f[k + 1]))
                        UVs.append((uv[0], uv[k], uv[k + 1]))
                        own.append(p["id"])
                Vs.append(p["V"])
                off += len(p["V"])
            V, F, UVc, own = np.concatenate(Vs), np.array(Fs, np.int64), np.array(UVs, float), np.array(own)
            self.log["union"] = "none"
        else:
            V, F, UVc, own = res
            self.log["union"] = "ok"
        self.log["skin_tris_union"] = int(len(F))
        # pull junction vertices onto the smooth union, level for level with the tube they came from
        hard, soft = blend.fields(V)
        gap = hard - soft
        act = gap > 2e-3
        # the boughs' top edges are the squirrel's feet lines: the vertices on them stay where they are
        pin = np.zeros(len(V), bool)
        for limb in self.limbs:
            feet = getattr(limb, "feet", None)
            if feet is not None:
                m = np.all((V >= feet.min(0) - 0.1) & (V <= feet.max(0) + 0.1), axis=1)
                if m.any():
                    pin[np.nonzero(m)[0][seg_dist(V[m], feet[:-1], feet[1:]).min(1) < 0.02]] = True
        act &= ~pin
        V = V.copy()
        lvl = hard.copy()

        def reproject(Pm, tgt, steps):
            """Walk points along the blend's gradient to their level. In a tight crotch the gradient is
            short (the two limbs pull against each other), so the step is damped rather than divided
            by it: slower there, but it never jumps across."""
            for _ in range(steps):
                d, g = blend.grad(Pm)
                gl = np.linalg.norm(g, axis=1)
                ln = np.clip((tgt - d) / np.maximum(gl, 0.22), -0.3, 0.3)
                Pm = Pm + (g / np.maximum(gl, 1e-6)[:, None]) * ln[:, None]
            return Pm

        def relax(V, F, act, rounds):
            """Even the pulled triangles out: slide each vertex toward its neighbours, back onto the blend."""
            E = np.concatenate([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 0]]])
            E = np.concatenate([E, E[:, ::-1]])
            cnt = np.bincount(E[:, 0], minlength=len(V)).astype(float)
            for _ in range(rounds):
                acc = np.zeros_like(V)
                np.add.at(acc, E[:, 0], V[E[:, 1]])
                avg = acc / np.maximum(cnt, 1)[:, None]
                V[act] = V[act] + 0.5 * (avg[act] - V[act])
                V[act] = reproject(V[act], lvl[act], 4)

        def folded(V, F):
            """Faces that look into the wood: their normal against the blend's gradient at their middle."""
            fnn = np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]])
            _, g = blend.grad(V[F].mean(1))
            return (fnn * g).sum(1) < 0

        dbg = self.opts.get("debug")
        if dbg:
            print("folded after union", int(folded(V, F).sum()), "of", len(F), flush=True)
        added = 0
        if act.any():
            # give the junctions vertices to bend with: split the long edges where the blend acts
            for rnd in range(2):
                m = len(F)
                Es = np.sort(np.concatenate([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 0]]]), axis=1)
                uq, inv = np.unique(Es, axis=0, return_inverse=True)
                inv = inv.reshape(-1)
                a, b = uq[:, 0], uq[:, 1]
                ln = np.linalg.norm(V[a] - V[b], axis=1)
                g2 = np.maximum(gap[a], gap[b])
                split = (g2 > 0.035) & (ln > (1.0 if rnd == 0 else 1.25))
                room = self.opts.get("junction_tris", 1200) - added
                if split.sum() * 2 > room:
                    pr = g2 * ln
                    thr = np.sort(pr[split])[::-1][max(room // 2 - 1, 0)] if room > 2 else 1e9
                    split &= pr >= thr
                if not split.any():
                    break
                ns = int(split.sum())
                nid = np.full(len(uq), -1, np.int64)
                nid[split] = len(V) + np.arange(ns)
                mid = (V[a[split]] + V[b[split]]) / 2
                lm = (lvl[a[split]] + lvl[b[split]]) / 2
                V = np.concatenate([V, mid])
                lvl = np.concatenate([lvl, lm])
                pmid = pin[a[split]] & pin[b[split]]
                pin = np.concatenate([pin, pmid])
                act = np.concatenate([act, ~pmid])
                gap = np.concatenate([gap, np.maximum(lm - blend.soft(mid), (gap[a[split]] + gap[b[split]]) / 2)])
                e = np.stack([nid[inv[0:m]], nid[inv[m : 2 * m]], nid[inv[2 * m : 3 * m]]], axis=1)  # on edges 01, 12, 20
                nsp = (e >= 0).sum(1)
                newF, newO = [], []
                for fi in np.nonzero(nsp > 0)[0]:
                    v, ee = F[fi], e[fi]
                    k = int(nsp[fi])
                    if k == 3:
                        tris = [(v[0], ee[0], ee[2]), (ee[0], v[1], ee[1]), (ee[2], ee[1], v[2]), (ee[0], ee[1], ee[2])]
                    elif k == 1:
                        r = int(np.argmax(ee >= 0))
                        p, q, w = v[r], v[(r + 1) % 3], v[(r + 2) % 3]
                        tris = [(p, ee[r], w), (ee[r], q, w)]
                    else:
                        r = int(np.argmax(ee < 0))  # the unsplit edge runs from v[r] to v[r+1]
                        p, q, w = v[r], v[(r + 1) % 3], v[(r + 2) % 3]
                        eq, ew = ee[(r + 1) % 3], ee[(r + 2) % 3]  # on q-w and on w-p
                        tris = [(p, q, eq), (p, eq, ew), (ew, eq, w)]
                    newF += tris
                    newO += [own[fi]] * len(tris)
                    added += len(tris) - 1
                F = np.concatenate([F[nsp == 0], np.array(newF, np.int64).reshape(-1, 3)])
                own = np.concatenate([own[nsp == 0], np.array(newO, np.int64)])
            V0 = V.copy()
            V[act] = reproject(V[act], lvl[act], 18)
            if dbg:
                print("folded after pull", int(folded(V, F).sum()), "of", len(F), flush=True)
            relax(V, F, act, 3)
            if dbg:
                print("folded after relax", int(folded(V, F).sum()), flush=True)
            # weld the slivers the cut left along the junction curves (they fold and shade as specks)
            Es = np.unique(np.sort(np.concatenate([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 0]]]), axis=1), axis=0)
            short = (np.linalg.norm(V[Es[:, 0]] - V[Es[:, 1]], axis=1) < 0.07) & (act[Es[:, 0]] | act[Es[:, 1]])
            rep = np.arange(len(V))

            def find(i):
                while rep[i] != i:
                    rep[i] = rep[rep[i]]
                    i = rep[i]
                return i

            for a, b in Es[short]:
                ra, rb = find(int(a)), find(int(b))
                if ra != rb:
                    # keep the vertex that was not moved (the tube's own) when there is one
                    if act[ra] and not act[rb]:
                        ra, rb = rb, ra
                    rep[rb] = ra
            rep = np.array([find(i) for i in range(len(V))])
            F = rep[F]
            good = (F[:, 0] != F[:, 1]) & (F[:, 1] != F[:, 2]) & (F[:, 2] != F[:, 0])
            F, own = F[good], own[good]
            self.log["skin_welded"] = int(short.sum())
            # untangle what still faces into the wood: its corners go to the middle of their neighbours
            for _ in range(3):
                fo = folded(V, F)
                bad = np.zeros(len(V), bool)
                bad[F[fo].ravel()] = True
                bad &= act
                if not bad.any():
                    break
                relax(V, F, bad, 2)
            self.log["skin_blend_max_move"] = round(float(np.linalg.norm(V - V0, axis=1).max()), 3)
            if dbg:
                fo = folded(V, F)
                print("folded after weld", int(fo.sum()), "of", len(F), flush=True)
                names = [l.name for l in self.limbs]
                cen = V[F[fo]].mean(1)
                ar = np.linalg.norm(np.cross(V[F[fo, 1]] - V[F[fo, 0]], V[F[fo, 2]] - V[F[fo, 0]]), axis=1) / 2
                for o in np.unique(own[fo]):
                    mm = own[fo] == o
                    print("   ", names[o] if o < len(names) else "pad", int(mm.sum()), "area", round(float(ar[mm].sum()), 3),
                          "y", np.round(cen[mm][:, 1].min(), 1), np.round(cen[mm][:, 1].max(), 1), "act", int(act[F[fo][mm]].any(1).sum()), flush=True)
        UVc = np.zeros((len(F), 3, 2))
        self.log["skin_blend_verts"] = int(act.sum())
        self.log["skin_refine_tris"] = int(added)
        ok = np.linalg.norm(np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]]), axis=1) > 1e-7
        F, UVc, own = F[ok], UVc[ok], own[ok]
        Es = np.sort(np.concatenate([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 0]]]), axis=1)
        _, ecount = np.unique(Es, axis=0, return_counts=True)
        self.log["skin_open_edges"] = int((ecount == 1).sum())

        # bark coordinates from the limb each face belongs to: the grain runs along that limb and meets
        # its neighbour's along the ridge of the junction
        for li, limb in enumerate(self.limbs):
            m = own == li
            if not m.any():
                continue
            uv = limb.uv(V[F[m]].reshape(-1, 3)).reshape(-1, 3, 2)
            u = uv[:, :, 0]
            wrap = (u.max(1) - u.min(1)) > limb.u_rep / 2
            u[wrap] = np.where(u[wrap] < limb.u_rep / 2, u[wrap] + limb.u_rep, u[wrap])
            UVc[m] = uv
        padm = own >= len(self.limbs)
        if padm.any():
            UVc[padm] = V[F[padm]][:, :, [0, 2]] / 4.5
        # normals: the mesh's own away from junctions, the blend's gradient where the skin was pulled
        vn, fn = vertex_normals(V, F)
        w = np.clip(gap / 0.02, 0, 1)
        if act.any():
            _, g = blend.grad(V[act])
            vn[act] = norm(vn[act] * (1 - w[act])[:, None] + norm(g) * w[act][:, None])
        self.log["skin_folded_faces"] = int(((fn * (vn[F[:, 0]] + vn[F[:, 1]] + vn[F[:, 2]])).sum(1) < 0).sum())
        # one vertex per (position, uv): corners that share both stay welded
        key = np.concatenate([F.reshape(-1, 1).astype(float), np.round(UVc.reshape(-1, 2), 5)], axis=1)
        uniq, inv = np.unique(key, axis=0, return_inverse=True)
        vi = uniq[:, 0].astype(np.int64)
        self.bark.add(V[vi], inv.reshape(-1, 3), uniq[:, 1:3], vn[vi])
        self.skin = (V, F)
        self.log["skin_tris"] = int(len(F))

    def pad_part(self, mid, feet, pid):
        hr, vr = 1.7, 0.39
        V0, F0 = icosphere(2)
        k = self.rng.random(4) * 6.28
        bump = 1 + 0.08 * np.sin(V0[:, 0] * 5 + k[0]) * np.sin(V0[:, 2] * 4 + k[1])
        V = V0 * np.array([hr, vr, hr])[None] * bump[:, None]
        V[:, 1] = np.minimum(V[:, 1], vr * 0.55)  # flat top where the squirrel stands
        V = V + np.array([mid[0], feet - vr * 0.55, mid[2]])[None]
        faces = [tuple(int(i) for i in f) for f in F0]
        uvs = [[(V[i][0] / 4.5, V[i][2] / 4.5) for i in f] for f in faces]
        return {"V": V, "faces": faces, "uvs": uvs, "id": pid}

    # .. crown ..
    def crown_frame(self):
        ends = [b["P"][-1] for b in self.boughs if b["kind"] in ("branch", "lookout", "decor")]
        if not ends:
            ends = [self.trunkP[-1]]
        E = np.array(ends)
        top = self.trunkP[-1]
        c = np.array([E[:, 0].mean() * 0.6 + top[0] * 0.4, 0, E[:, 2].mean() * 0.6 + top[2] * 0.4])
        rh = max(float(np.max(np.hypot(E[:, 0] - c[0], E[:, 2] - c[2]))), self.H * 0.15)
        ylo = min(E[:, 1].min(), top[1])
        yhi = max(E[:, 1].max(), top[1])
        c[1] = (ylo + yhi) / 2
        self.min_leaf_y = max(5.0 if self.sp == "apple" else 8.0, self.H * (0.6 if self.cat == "giant" else self.par["floor"]))
        if self.sp == "willow":
            self.min_leaf_y = 4.5
        self.crown_top = self.H * self.par["top"]
        return c, rh, ylo, yhi

    def envelope(self, p):
        """> 0 outside the crown's soft envelope (studs, roughly): side branches turn back there."""
        c, rh, ylo, yhi = self.crown
        R = rh + 9.0 * self.scale
        top = self.crown_top
        yc = ylo + 0.25 * (yhi - ylo)
        h = max(top - yc, 6.0)
        dx, dz = p[0] - c[0], p[2] - c[2]
        dy = (p[1] - yc) / h
        e = 2.0 + 2.2 * self.par["flat"]
        k = (math.hypot(dx, dz) / R) ** 2 + max(dy, 0.0) ** e + (max(-dy, 0.0) * h / (0.9 * R)) ** 2
        return (math.sqrt(k) - 1.0) * R

    # .. growth: bending side branches ..
    def grow_path(self, origin, d0, length, level, first=None):
        """A branch as a list of nodes: it sags, turns up, kinks, keeps out of the walking tunnels and
        inside the crown. Returns (points, how many nodes were wanted)."""
        par, rng = self.par, self.rng
        lv = min(level, 2) - 1
        nseg = max(2, int(round(length / (par["node"][lv] * self.scale))))
        seg = length / nseg
        d = norm(d0)
        p = np.asarray(origin, float).copy()
        pts = [p.copy()]
        sag, up, kink = par["sag"][lv], par["up"][lv], par["kink"][lv]
        for i in range(nseg):
            f = (i + 1) / nseg
            step = seg * rng.uniform(0.85, 1.15) if i else (first if first is not None else seg)
            horiz = 1.0 - abs(d[1])
            d = d - Y * sag * step * (0.4 + 0.6 * horiz) * (1.2 - 0.6 * f) + Y * up * step * f ** 1.4
            if i:
                d = d + rng.normal(size=3) * kink * np.array([1.0, 0.55, 1.0])
            d = norm(d)
            q = p + d * step
            # stay in the crown, above the floor, out of the tunnels
            if self.envelope(q) > 0 and self.sp != "willow":
                c = self.crown[0]
                inward = norm(np.array([c[0] - q[0], 0.0, c[2] - q[2]]) + Y * (-0.6 if q[1] > self.crown_top - 4 else 0.25))
                d = norm(d + inward * 0.7)
                q = p + d * step
            floor = self.min_leaf_y + (0.0 if self.sp == "willow" else 1.5)
            if q[1] < floor and level >= 1 and d[1] < 0.1:
                d = norm(d + Y * (0.1 - d[1] + 0.25))
                q = p + d * step
            if i >= 1 or level > 1:
                cl = self.clearance(np.array([q, (p + q) / 2])).min()
                if cl < 0.5:
                    best, bq = cl, None
                    side = norm(np.cross(d, Y) + 1e-9)
                    for alt in (side, -side, -Y, Y, side - Y, -side - Y):
                        d2 = norm(d + norm(alt) * 0.9)
                        q2 = p + d2 * step
                        c2 = self.clearance(np.array([q2, (p + q2) / 2])).min()
                        if c2 > best:
                            best, bq, bd = c2, q2, d2
                    if bq is None or best < 0.15:
                        break
                    q, d = bq, bd
            p = q
            pts.append(p.copy())
        return np.array(pts), nseg

    def side_dir(self, tangent, up_ref, side, level, rise=None, angle=None):
        """Direction of a side branch: `angle` off the parent's axis, turned `rise` round it from up."""
        par, rng = self.par, self.rng
        a = math.radians(angle if angle is not None else rng.uniform(*par["angle"]))
        rz = math.radians(rise if rise is not None else rng.uniform(*par["rise"]))
        u = perp_up(tangent, up_ref)
        radial = rotate(u, tangent, side * rz)
        return norm(tangent * math.cos(a) + radial * math.sin(a))

    def add_branch(self, origin, d0, length, r0, level, parent_chain, parent_r, order, tip_r=None):
        if length < 1.2 or r0 < 0.05:
            return None
        pts, want = self.grow_path(origin, d0, length, level)
        if len(pts) < 3:
            return None
        s = arclen(pts)
        f = s / max(s[-1], 1e-9)
        r_end = tip_r if tip_r is not None else max(0.05, r0 * 0.22)
        radii = r_end + (r0 - r_end) * (1 - f) ** 1.15
        br = {"pts": pts, "radii": radii, "level": level, "parent_chain": parent_chain, "parent_r": parent_r, "order": order,
              "kids": [], "mesh": True, "cut": len(pts) < want + 1}
        self.branches.append(br)
        return br

    def grow_children(self, br, depth, big=False):
        """Branchlets along a branch: alternate sides, each a little shorter than the last. depth 1 =
        off a side branch, 2 = the twigs the sprays sit on; big = off one of the leader's crown limbs
        (those children are side branches in their own right). Returns the new branches."""
        par, rng = self.par, self.rng
        pts, radii = br["pts"], br["radii"]
        n = len(pts)
        lo, hi = par["len2"]
        side = 1 if rng.random() < 0.5 else -1
        chain = Chain(pts, radii)
        new = []
        last = n if depth >= 2 else n - 1  # a twig also forks at its tip
        for i in range(1, last):
            if depth == 1 and i == 1 and n > 5:
                continue  # the first node of a long side branch stays clean
            f = i / (n - 1)
            t = norm(pts[min(i + 1, n - 1)] - pts[i - 1])
            if big:
                ln = par["len1"][1] * self.scale * rng.uniform(0.8, 1.2) * (1.0 - 0.3 * f)
            else:
                ln = rng.uniform(lo, hi) * self.scale * (1.0 - 0.4 * f) * (0.66 if depth > 1 else 1.0)
            if self.sp == "willow":
                d = self.side_dir(t, None, side, 2, rise=rng.uniform(60, 110), angle=rng.uniform(45, 70))
            else:
                d = self.side_dir(t, None, side, 2, rise=rng.uniform(62, 100) if depth == 1 else rng.uniform(40, 120))
            r0 = float(radii[i]) * rng.uniform(0.55, 0.7)
            kid = self.add_branch(pts[i], d, ln, r0, br["level"] + 1, chain, float(radii[i]), br["order"] + 0.01 * i)
            if kid is not None:
                kid["bough"] = br.get("bough", -1)
                br["kids"].append(kid)
                new.append(kid)
            side = -side
        return new

    def grow_all(self):
        par, rng = self.par, self.rng
        sc = self.scale
        l_near, l_tip = par["len1"]
        firsts = []
        # side branches along every bough, alternate sides, longest in the middle of the crown
        for bi, b in enumerate(self.boughs):
            P, sP, L, kind = b["P"], b["sP"], b["L"], b["kind"]
            chain = b["limb"].chain
            side = 1 if rng.random() < 0.5 else -1
            sQ = b["s"]
            for sk, g in zip(b["kids"], b["give"]):
                pk = at_s(P, sP, sk)[0]
                t = norm(at_s(P, sP, min(sk + 0.6, L))[0] - at_s(P, sP, max(sk - 0.6, 0))[0])
                j = int(np.searchsorted(sQ, sk).clip(1, len(sQ) - 1))
                fq = (sk - sQ[j - 1]) / max(sQ[j] - sQ[j - 1], 1e-9)
                cpt = b["Q"][j - 1] + (b["Q"][j] - b["Q"][j - 1]) * fq
                rpar = float(b["radii"][j - 1] + (b["radii"][j] - b["radii"][j - 1]) * fq)
                u = sk / L
                ln = (l_near + (l_tip - l_near) * u) * sc * rng.uniform(0.82, 1.18)
                if kind == "bridge":
                    ln *= 0.55 * (1.0 - 0.5 * u)
                r0 = float(np.clip(math.sqrt(max(g, 0.01)), 0.16, 0.8 * rpar))
                d = self.side_dir(t, None, side, 1)
                br = self.add_branch(cpt, d, ln, r0, 1, chain, rpar, bi + u)
                if br is not None:
                    br["bough"] = bi
                    firsts.append(br)
                side = -side
            if kind in ("branch", "decor") and self.sp != "apple" or (self.sp == "apple" and kind == "branch"):
                # the bough ends in a fork: two or three leaders carry on past the rail's end
                t = norm(P[-1] - P[-3])
                tipc, rtip = b["Q"][-1], float(b["radii"][-1])
                # (they leave to the sides and a little below, so the feet line ends in the crotch)
                m = 3 if rng.random() < 0.4 else 2
                sidev = norm(np.cross(t, Y) + 1e-9)
                for q in range(m):
                    if q < 2:
                        a = (1 if q == 0 else -1) * rng.uniform(0.6, 0.85)
                        d = norm(t * math.cos(a) + sidev * math.sin(a) + Y * rng.uniform(-0.05, 0.12))
                    else:
                        d = norm(t + Y * rng.uniform(-0.45, -0.25) + sidev * rng.normal(0, 0.15))
                    ln = l_tip * sc * rng.uniform(0.75, 1.1)
                    br = self.add_branch(tipc - t * 0.4 * rtip - Y * 0.12 * rtip, d, ln, rtip * (0.7 if m == 2 else 0.6), 1, chain, rtip, bi + 1.0)
                    if br is not None:
                        br["bough"] = bi
                        firsts.append(br)
        # the leader's crown limbs: they arch up and out over the boughs and carry the top of the crown
        if self.leader is not None:
            LC, LR = self.leader
            chain = self.leader_limb.chain
            sL = arclen(LC)
            n = par["crown"] + (2 if self.cat == "giant" else 0)
            c, rh, ylo, yhi = self.crown
            a0 = rng.random() * 6.28
            for q in range(n):
                f = 0.18 + 0.78 * (q + 0.5) / n
                pk = at_s(LC, sL, f * sL[-1])[0]
                rpar = float(np.interp(f * sL[-1], sL, LR))
                a = a0 + q * 2.39996
                out = np.array([math.cos(a), 0.0, math.sin(a)])
                elev = math.radians(rng.uniform(18, 50) + 28 * f)
                d = norm(out * math.cos(elev) + Y * math.sin(elev))
                room = max(self.crown_top - pk[1], 6.0)
                ln = float(np.clip(0.42 * rh * (1.0 - 0.35 * f) + 0.4 * room, 8.0, 34.0)) * rng.uniform(0.85, 1.1)
                br = self.add_branch(pk, d, ln, float(np.clip(0.62 * rpar, 0.28, 1.0)), 1, chain, rpar, 100 + q)
                if br is not None:
                    br["bough"] = -1
                    br["crown"] = True
                    firsts.append(br)
            # and the leader's own tip
            tipd = norm(LC[-1] - LC[-2])
            br = self.add_branch(LC[-1] - tipd * 0.2, norm(tipd + rng.normal(0, 0.15, 3)), 7.0 * sc, float(LR[-1]) * 0.9, 1, chain, float(LR[-1]), 199)
            if br is not None:
                br["bough"] = -1
                firsts.append(br)
        for br in firsts:
            if br.get("crown"):
                # a crown limb is a small bough: side branches, their branchlets, the twigs
                for k1 in self.grow_children(br, 1, big=True):
                    for k2 in self.grow_children(k1, 1):
                        self.grow_children(k2, 2)
            else:
                for k1 in self.grow_children(br, 1):
                    if self.sp != "willow":
                        self.grow_children(k1, 2)
        self.log["branches"] = {f"level{k}": sum(1 for b in self.branches if min(b["level"], 3) == k) for k in (1, 2, 3)}

    # .. bark for the side branches: a skirt on the parent, then a tapering, bending tube ..
    def branch_tris(self, br):
        sides = self.branch_sides(br)
        return (len(br["pts"]) + 1) * sides * 2 + sides

    def branch_sides(self, br):
        r0 = float(br["radii"][0])
        if br["level"] == 1:
            return 6 if r0 > 0.8 else (5 if r0 > 0.5 else 4)
        return 3

    def fit_bark_budget(self):
        """Keep the bark under its triangle budget: the thinnest, farthest twigs become paint on the
        spray cards (their leaves stay)."""
        budget = self.opts.get("bark_budget", BARK_BUDGET) - 250
        used = self.bark.tris
        cost = [(self.branch_tris(b), b) for b in self.branches]
        total = used + sum(c for c, _ in cost)
        self.log["bark_tris_wanted"] = int(total)
        if total <= budget:
            return
        rails = np.concatenate([resample(r[0], 3.0)[0] for r in self.rails])
        drop = sorted((b for _, b in cost), key=lambda b: (-min(b["level"], 3), -float(np.linalg.norm(rails - b["pts"][0][None], axis=1).min())))
        for b in drop:
            if total <= budget:
                break
            b["mesh"] = False
            total -= self.branch_tris(b)
        self.log["twigs_painted_only"] = sum(1 for b in self.branches if not b["mesh"])

    def mesh_branches(self):
        for br in self.branches:
            if br["mesh"]:
                self.branch_tube(br)

    def branch_tube(self, br):
        pts, radii = br["pts"], br["radii"]
        chain, rpar = br["parent_chain"], br["parent_r"]
        sides = self.branch_sides(br)
        r0 = float(radii[0])
        d0 = norm(pts[1] - pts[0])
        seg0 = float(np.linalg.norm(pts[1] - pts[0]))
        T, Ns, Bs = frames(pts)
        ang = np.linspace(0, 2 * math.pi, sides + 1)
        E = np.cos(ang)[:, None] * Ns[0][None] + np.sin(ang)[:, None] * Bs[0][None]
        flare = min(1.5, max(1.02, 0.9 * rpar / max(r0, 1e-6)))
        # ring 0: where each generator of the flared base leaves the parent's surface (a little under it)
        depth = 0.09 * rpar + 0.02
        lo = np.zeros(sides + 1)
        hi = np.full(sides + 1, min(seg0 * 0.9, 2.6 * rpar + 1.0))
        g = lambda sv: pts[0][None] + d0[None] * sv[:, None] + E * (r0 * flare)
        inside_hi = chain.dist(g(hi)) < -depth
        for _ in range(14):
            mid = (lo + hi) / 2
            ins = chain.dist(g(mid)) < -depth
            lo = np.where(ins, mid, lo)
            hi = np.where(ins, hi, mid)
        sx = np.where(inside_hi, hi, (lo + hi) / 2)
        ring0 = g(sx)
        s_out = float(sx.max())
        # parent's surface normal there (for shading the skirt into the parent)
        eps = 0.03
        gn = np.stack([chain.dist(ring0 + np.eye(3)[k] * eps) - chain.dist(ring0 - np.eye(3)[k] * eps) for k in range(3)], axis=1)
        n0 = norm(norm(gn) * 0.75 + E * 0.25)
        s1 = min(s_out + 0.55 * r0 + 0.1, seg0 * 0.97)
        rings = [ring0, pts[0][None] + d0[None] * s1 + E * (r0 * (1 + (flare - 1) * 0.3))]
        nrm = [n0, norm(E + d0[None] * -0.25)]
        vs = [0.0, s1 - float(sx.mean())]
        sacc = vs[1]
        for i in range(1, len(pts)):
            d = np.cos(ang)[:, None] * Ns[i][None] + np.sin(ang)[:, None] * Bs[i][None]
            rings.append(pts[i][None] + d * radii[i])
            nrm.append(d)
            sacc += float(np.linalg.norm(pts[i] - (pts[i - 1] if i > 1 else pts[0] + d0 * s1)))
            vs.append(sacc)
        n = len(rings)
        m = sides + 1
        V = np.concatenate(rings)
        NN = np.concatenate(nrm)
        circ = 2 * math.pi * max(r0, 0.12)
        v_tile = max(1.2, circ * 1.3)
        UV = np.concatenate([np.stack([ang / (2 * math.pi), np.full(m, v / v_tile)], axis=1) for v in vs])
        i, j = np.meshgrid(np.arange(n - 1), np.arange(sides), indexing="ij")
        a, b, c, d = i * m + j, i * m + j + 1, (i + 1) * m + j + 1, (i + 1) * m + j
        F = np.concatenate([np.stack([a, b, c], -1).reshape(-1, 3), np.stack([a, c, d], -1).reshape(-1, 3)])
        tip = pts[-1] + T[-1] * float(radii[-1]) * 1.5
        ti = len(V)
        V = np.concatenate([V, tip[None]])
        UV = np.concatenate([UV, [[0.5, vs[-1] / v_tile + 0.1]]])
        NN = np.concatenate([NN, T[-1][None]])
        base = (n - 1) * m
        F = np.concatenate([F, np.array([(base + q, base + q + 1, ti) for q in range(sides)], np.int64)])
        self.bark.add(V, F, UV, NN)

    # .. leaves: sprays on the twigs ..
    def card(self, base, d, nt, length, width, droop, variant, kind="spray"):
        """A spray card: 2 x 3 vertices facing `nt`, running along `d` (made square to nt), bent so the
        tip falls away from nt (a shingle on the crown) and twisted a little."""
        rng = self.rng
        nt = norm(nt)
        d = d - nt * np.dot(d, nt)
        if np.linalg.norm(d) < 1e-3:
            d = np.cross(nt, [0.3, 0.1, 0.9])
        d = norm(d)
        side = np.cross(d, nt)
        rows = 3 if kind == "spray" else 4
        tw = rng.normal(0, self.par["twist"])
        V, UV = [], []
        for k in range(rows):
            t = k / (rows - 1)
            if kind == "strand":
                c = base + d * length * t + nt * (0.03 * length * math.sin(t * 5.0 + tw * 6))
            else:
                c = base + d * length * t - nt * droop * length * t * t + nt * 0.05 * length * math.sin(t * math.pi)
            sd = rotate(side, d, tw * (t - 0.4))
            V += [c - sd * width * 0.5, c + sd * width * 0.5]
            UV += [(0.0, t), (1.0, t)]
        V = np.array(V)
        F = []
        for k in range(rows - 1):
            a, b, c2, d2 = 2 * k, 2 * k + 1, 2 * k + 3, 2 * k + 2
            F += [(a, b, c2), (a, c2, d2)]
        return {"V": V, "UV": np.array(UV), "F": np.array(F, np.int64), "n": nt, "variant": variant, "c": V.mean(0)}

    def build_leaves(self):
        par, rng = self.par, self.rng
        sc = self.scale
        cl, cw = par["card"]
        cl, cw = cl * sc, cw * sc
        willow = self.sp == "willow"
        cards = []
        c, rh, ylo, yhi = self.crown
        ctr = np.array([c[0], ylo + 0.2 * (self.crown_top - ylo), c[2]])
        span = max(self.crown_top - ctr[1], 4.0)

        def facing(p):
            """Which way a spray at p faces: up on top of the crown, outward and up on its sides."""
            rel = p - ctr
            rho = min(math.hypot(rel[0], rel[2]) / (rh + 6.0), 1.3)
            out = norm(np.array([rel[0], 0.0, rel[2]]) + 1e-6)
            h = max(rel[1], 0.0) / span
            ks = float(np.clip(0.10 + 1.15 * rho - 0.55 * h, 0.05, 1.25))
            return norm(out * ks + Y * (1.0 - 0.3 * rho) + rng.normal(0, 0.24, 3)), out, rho

        def spray(base, d, size=1.0):
            d = norm(d)
            nt, out, rho = facing(base)
            if willow:
                # hanging strands: straight down, facing out of the curtain
                ln = cl * size * rng.uniform(0.9, 1.75)
                ln = min(ln, max(base[1] - self.min_leaf_y, 0.0))
                if ln < 3.0:
                    return
                nt = norm(out + rng.normal(0, 0.45, 3) * np.array([1.0, 0.15, 1.0]))
                dd = norm(-Y + out * 0.10 + rng.normal(0, 0.05, 3))
                cards.append(self.card(base, dd, nt, ln, cw * rng.uniform(0.85, 1.15), 0.0, int(rng.integers(0, 4)), "strand"))
                return
            # the spray follows its twig, leaning down the outside of the crown like a shingle
            dd = norm(d * 0.75 + (out * 0.55 - Y * 0.45) * rho * 0.8)
            dr = par["droop"] * rng.uniform(0.5, 1.6) + 0.10 * rho
            ln = cl * size * rng.uniform(0.85, 1.15)
            cards.append(self.card(base - dd * 0.04 * ln, dd, nt, ln, cw * size * rng.uniform(0.85, 1.15), dr, int(rng.integers(0, 4))))

        for br in self.branches:
            pts = br["pts"]
            n = len(pts)
            lvl = br["level"]
            tipd = norm(pts[-1] - pts[-2])
            sidev = norm(np.cross(tipd, Y) + 1e-9)
            # the tip: a fan of sprays
            m = par["tip"] + (1 if lvl == 1 else 0)
            for q in range(m):
                a = (q - (m - 1) / 2) * rng.uniform(0.8, 1.05) + rng.normal(0, 0.12)
                d = norm(tipd * math.cos(a) + sidev * math.sin(a) + Y * rng.uniform(-0.05, 0.3))
                spray(pts[-1] + rng.normal(0, 0.2, 3), d, 1.08 if lvl == 1 else 1.0)
            # along it: sprays to both sides at the nodes (the inner part of a side branch stays bare)
            first = 1 if lvl >= 2 else max(1, int(math.ceil(0.4 * (n - 1))))
            sgn = 1 if rng.random() < 0.5 else -1
            for i in range(first, n - 1):
                t = norm(pts[i + 1] - pts[i - 1])
                sv = norm(np.cross(t, Y) + 1e-9)
                reps = par["side"] + (1 if lvl <= 2 else 0)
                for _ in range(reps):
                    d = norm(t * 0.5 + sv * sgn * 0.9 + Y * rng.uniform(-0.1, 0.35))
                    spray(pts[i] + rng.normal(0, 0.3, 3), d, 0.92)
                    sgn = -sgn
        # fill: a crown that would leave much of its leaf budget unused gets more sprays, set loosely
        # round the nodes of its branches, more of them toward the outside and the top of the crown
        # (a small apple tree is full long before the budget is)
        per = 4 if not willow else 6
        room = (self.opts.get("leaf_budget", LEAF_BUDGET) - 60) // per
        self.log["cards_first_pass"] = len(cards)
        target = int(par.get("fill", 0.86) * room)
        if len(cards) < target and self.branches:
            nodes, wts = [], []
            for br in self.branches:
                pts = br["pts"]
                n = len(pts)
                first = 1 if br["level"] >= 2 else max(1, int(math.ceil(0.3 * (n - 1))))
                for i in range(first, n):
                    nodes.append((pts[i], norm(pts[min(i + 1, n - 1)] - pts[i - 1])))
                    rel = pts[i] - ctr
                    wts.append(0.45 + min(math.hypot(rel[0], rel[2]) / (rh + 6.0), 1.2) + 0.8 * max(rel[1], 0.0) / span)
            wts = np.array(wts)
            # (about a fifth of them will fall in a tunnel or below the floor)
            pick = rng.choice(len(nodes), size=int((target - len(cards)) * 1.25), p=wts / wts.sum())
            jit = (0.5 if self.sp == "apple" else 1.0) * sc
            for j in pick:
                p, t = nodes[j]
                sv = norm(np.cross(t, Y) + 1e-9)
                a = rng.uniform(0, 2 * math.pi)
                d = norm(t * 0.4 + sv * math.cos(a) * 0.9 + Y * (0.1 + 0.45 * math.sin(a)))
                spray(p + rng.normal(0, jit, 3) * np.array([1.0, 0.7, 1.0]), d, rng.uniform(0.84, 1.08))
        # keep the tunnels, the buildings and the floor clear
        kept = []
        floor = self.min_leaf_y

        def blocked(Vs):
            """Per card: does any of it touch a tunnel, a building or the floor? Probed over the whole
            card (a grid no coarser than 1.5 studs), not only at its corners."""
            probes, owner, low = [], [], []
            for ci, A in enumerate(Vs):
                Lf, Rt_ = A[0::2], A[1::2]
                na = max(2, int(math.ceil(np.linalg.norm(np.diff((Lf + Rt_) / 2, axis=0), axis=1).sum() / 1.5)) + 1)
                nw = max(2, int(math.ceil(np.linalg.norm(Rt_ - Lf, axis=1).max() / 1.5)) + 1)
                sa = np.linspace(0, len(Lf) - 1, na)
                i0 = np.minimum(sa.astype(int), len(Lf) - 2)
                fa = (sa - i0)[:, None]
                l = Lf[i0] * (1 - fa) + Lf[i0 + 1] * fa
                r = Rt_[i0] * (1 - fa) + Rt_[i0 + 1] * fa
                w = np.linspace(0, 1, nw)[None, :, None]
                g = (l[:, None, :] * (1 - w) + r[:, None, :] * w).reshape(-1, 3)
                probes.append(g)
                owner.append(np.full(len(g), ci))
                low.append(A[:, 1].min())
            flat = np.concatenate(probes)
            owner = np.concatenate(owner)
            n = len(Vs)
            cl = np.full(n, 1e9)
            bx = np.full(n, 1e9)
            np.minimum.at(cl, owner, self.clearance(flat))
            np.minimum.at(bx, owner, self.box_clear(flat))
            return (cl < 0.45) | (bx < 0.3) | (np.array(low) < floor)

        if cards:
            bad = blocked([cd["V"] for cd in cards])
            retry = [cd for cd, b in zip(cards, bad) if b]
            kept = [cd for cd, b in zip(cards, bad) if not b]
            if retry:
                # try a smaller spray before giving up on it
                small = [cd["V"][0:2].mean(0)[None] + (cd["V"] - cd["V"][0:2].mean(0)[None]) * 0.6 for cd in retry]
                for cd, V2, b in zip(retry, small, blocked(small)):
                    if not b:
                        cd["V"], cd["c"] = V2, V2.mean(0)
                        kept.append(cd)
        budget = self.opts.get("leaf_budget", LEAF_BUDGET) - 60
        self.log["cards_wanted"] = len(kept)
        C = np.array([k["c"] for k in kept]) if kept else np.zeros((0, 3))
        if len(kept) * per > budget:
            # thin where the sprays are thickest, so the silhouette and the top stay full
            near = np.zeros(len(C))
            for i0 in range(0, len(C), 512):
                near[i0 : i0 + 512] = (np.linalg.norm(C[i0 : i0 + 512, None] - C[None], axis=2) < cl * 0.8).sum(1)
            score = near + rng.random(len(C)) * 1.5 - 2.5 * np.hypot(C[:, 0] - c[0], C[:, 2] - c[2]) / rh
            keep = np.sort(np.argsort(score)[: budget // per])
            kept = [kept[i] for i in keep]
            C = C[keep]
        self.cards = kept
        self.log["cards"] = len(kept)
        if not kept:
            return
        # light: sprays that see the sky are LeavesSun, those under a few layers hang in the shade
        cover = np.zeros(len(C))
        cell = max(cl, 4.0) * 0.8
        for i0 in range(0, len(C), 512):
            Ci = C[i0 : i0 + 512]
            dxz = np.hypot(Ci[:, None, 0] - C[None, :, 0], Ci[:, None, 2] - C[None, :, 2])
            cover[i0 : i0 + 512] = ((C[None, :, 1] > Ci[:, None, 1] + 1.0) & (dxz < cell)).sum(1)
        ytop, ybot = C[:, 1].max(), C[:, 1].min()
        hrel = (C[:, 1] - ybot) / max(ytop - ybot, 1e-6)
        score = cover - 3.0 * hrel + rng.normal(0, 0.6, len(C))
        q_sun, q_shade = np.quantile(score, [0.42, 0.78])
        for cd, sc_ in zip(kept, score):
            layer = "sun" if sc_ <= q_sun else ("shade" if sc_ >= q_shade else "mid")
            V = cd["V"]
            radial = norm((cd["c"] - ctr) * np.array([1.0, 1.2, 1.0]) + Y * 0.08 * rh)
            nn = norm(cd["n"] * 0.55 + radial * 0.45)
            # corner normals lean away from the card's centre so a spray shades like a soft tuft
            N = norm(nn[None] + 0.3 * norm(V - cd["c"][None]))
            v = cd["variant"]
            if willow:
                u0, u1, v0, v1 = v * 0.25, (v + 1) * 0.25, 1.0, 0.0
            else:
                u0, u1 = (v % 2) * 0.5, (v % 2) * 0.5 + 0.5
                v0, v1 = (v // 2) * 0.5, (v // 2) * 0.5 + 0.5
            UV = np.stack([u0 + (u1 - u0) * cd["UV"][:, 0], v0 + (v1 - v0) * cd["UV"][:, 1]], axis=1)
            self.leaf[layer].add(V, cd["F"], UV, N)

    def build_apples(self):
        rng = self.rng
        n = 0
        # the apples hang where they are seen: from the tips of the outer sprays, on the outside of
        # the leaves, spread round the crown (no two within 2.5 studs)
        c = self.crown[0]
        tips = [cd["V"][-2:].mean(0) for cd in self.cards]
        if not tips:
            tips = [b["pts"][-1] for b in self.branches if b["level"] >= 2]
        tips.sort(key=lambda p: -(math.hypot(p[0] - c[0], p[2] - c[2]) - 0.5 * p[1] + rng.normal(0, 3.5)))
        hung = []
        for p in tips:
            if n >= 28:
                break
            out = norm(np.array([p[0] - c[0], 0.0, p[2] - c[2]]) + 1e-9)
            cpos = p + out * 0.15 + np.array([rng.normal(0, 0.15), -0.55 - 0.3 * rng.random(), rng.normal(0, 0.15)])
            if hung and np.linalg.norm(np.array(hung) - cpos[None], axis=1).min() < 2.5:
                continue
            if self.clearance(cpos[None])[0] < 0.7 or cpos[1] < 2.5:
                continue
            ra = 0.62
            lat, lon = 4, 6
            V, UV, N = [], [], []
            red = n % 3 != 2
            for i in range(lat + 1):
                th = math.pi * i / lat
                for j in range(lon + 1):
                    ph = 2 * math.pi * j / lon
                    nrm = np.array([math.sin(th) * math.cos(ph), math.cos(th), math.sin(th) * math.sin(ph)])
                    V.append(cpos + nrm * ra * np.array([1, 0.92, 1]) * (1 - 0.15 * math.exp(-(th / 0.35) ** 2)))
                    N.append(nrm)
                    UV.append(((j / lon) * 0.5 + (0.0 if red else 0.5), 1 - i / lat))
            F = []
            for i in range(lat):
                for j in range(lon):
                    a, b, c2, d2 = i * (lon + 1) + j, i * (lon + 1) + j + 1, (i + 1) * (lon + 1) + j + 1, (i + 1) * (lon + 1) + j
                    F += [(a, b, c2), (a, c2, d2)]
            self.fruit.add(np.array(V), np.array(F), np.array(UV), np.array(N))
            hung.append(cpos)
            n += 1
        self.log["apples"] = n

    # -- reports --
    def tri_counts(self):
        return {"bark": self.bark.tris, "leaves_shade": self.leaf["shade"].tris, "leaves_mid": self.leaf["mid"].tris,
                "leaves_sun": self.leaf["sun"].tris, "fruit": self.fruit.tris}

    def feet_path(self, P, lift, kind, route):
        """The squirrel's drawn feet along a rail (Motion.visualPose): rail + lift, pushed out of the
        trunk over the first fifth of a bough."""
        F = P + Y[None] * lift
        clr = route.get("trunkClearance")
        if kind == "branch" and clr:
            sP = arclen(P)
            t = sP / max(sP[-1], 1e-9)
            ahead = at_s(P, sP, 0.16 * sP[-1])[0] - P[0]
            h = np.array([ahead[0], 0.0, ahead[2]])
            if np.linalg.norm(h) > 1e-6:
                k = (clr + 0.31) * SPU * np.clip(1 - t / 0.2, 0, 1) ** 2
                F = F + norm(h)[None] * k[:, None]
        return F


def twig_tips(tb):
    """The twig tips of a built tree (TreeBuilder after .build()), for whoever hangs leaves on them:
    one dict per branch that carries no further branch, with
      pos     (3,) the tip, studs, Roblox axes (+Y up), local to the tree's pivot (rec["root"])
      dir     (3,) unit direction the twig points at its tip
      radius  wood radius at the tip, studs
      length  length of the twig, studs
      level   1 = side branch off a bough or the leader, 2 = branchlet, 3+ = twig
      bough   index into tb.boughs of the bough it grows from (tb.boughs[i]["route"]["id"] is the
              route id; negative ids are the giants' decor limbs), -1 for the leader's crown limbs
      route   that bough's route id, None for the leader
      meshed  False when the twig itself was left out of the bark for the triangle budget"""
    out = []
    for br in tb.branches:
        if br["kids"]:
            continue
        pts = br["pts"]
        bi = int(br.get("bough", -1))
        out.append({"pos": pts[-1].copy(), "dir": norm(pts[-1] - pts[-2]), "radius": float(br["radii"][-1]),
                    "length": float(arclen(pts)[-1]), "level": int(br["level"]), "bough": bi,
                    "route": tb.boughs[bi]["route"]["id"] if bi >= 0 else None, "meshed": bool(br["mesh"])})
    return out


# ---- Blender ------------------------------------------------------------------------------------

def to_blender_coords(V):
    V = np.asarray(V, float)
    return np.stack([-V[:, 0], V[:, 2], V[:, 1]], axis=1)


def make_object(name, mesh, material, collection=None):
    import bpy

    V, F, UV, N = mesh.arrays()
    me = bpy.data.meshes.new(name)
    Vb = to_blender_coords(V)
    me.from_pydata(Vb.tolist(), [], F.tolist())
    uv = me.uv_layers.new(name="UVMap")
    uv.data.foreach_set("uv", UV[F.ravel()].astype(np.float32).ravel())
    me.polygons.foreach_set("use_smooth", np.ones(len(F), bool))
    Nb = to_blender_coords(N)
    me.normals_split_custom_set_from_vertices(Nb.tolist())
    me.validate(clean_customdata=False)
    me.update()
    if material is not None:
        me.materials.append(material)
    obj = bpy.data.objects.new(name, me)
    (collection or bpy.context.scene.collection).objects.link(obj)
    return obj
