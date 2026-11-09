"""Route-true tree meshes for the 95 harvested trees (pure numpy geometry; bpy only in to_blender).

Every tree is rebuilt from its harvested climbing routes (data/harvest: routes, route_samples, forks,
trees). Units: studs (HTML units x 2.5), Roblox axes (+Y up), local to the tree's root (pivot) =
trees.json `root` x 2.5. Conversion to Blender happens only when objects are made:
Blender (x, y, z) = (-X, Z, Y), so the FBX export (axis_forward Z, axis_up Y, FBX_SCALE_ALL)
lands back on Roblox (X, Y, Z) with 1 Blender unit = 1 stud.

Gameplay contract (src/shared/Routes/Motion.luau visualPose):
  * trunk bark radius at route parameter t equals the squirrel's tapered radius
      r(1 - 0.48 t) (min 0.8 st), giants r/0.95 - 2.625 t (min 1.125 st); r = surfaceRadius x 2.5,
    so the bark surface is surfaceRadius at the foot and the squirrel (offset tapered + 0.7 st) rides it.
  * branch / bridge / lookout bark: the TOP of the bough is the squirrel's feet, rail + lift
    (0.5 u = 1.25 st, apples 0.75 st, lookouts 1.525 st); the bough's centre sits lift - r(s) above
    the rail and its radius never drops below lift / 2, so the rail stays inside the bark.
  * no leaf clump comes within a tunnel of every walkable rail (and of any foreign route passing
    through the crown), so a squirrel on a bough stays visible.
"""
import json
import math
import os

import numpy as np

SPU = 2.5
REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))


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


LEAF_SHAPE = {"oak": "oak", "elm": "elm", "sycamore": "palmate", "maple": "palmate", "willow": "willow", "apple": "apple"}
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


def arclen(P):
    d = np.linalg.norm(np.diff(P, axis=0), axis=1)
    return np.concatenate([[0.0], np.cumsum(d)])


def resample(P, step, min_n=2):
    """Resample a dense polyline at ~`step` spacing (keeps both ends); returns (points, s, s/L)."""
    s = arclen(P)
    L = s[-1]
    n = max(min_n, int(math.ceil(L / step)) + 1)
    ss = np.linspace(0, L, n)
    out = np.stack([np.interp(ss, s, P[:, k]) for k in range(3)], axis=1)
    return out, ss, ss / max(L, 1e-9)


def seg_dist(p, A, B):
    """Distance from points p (n,3) to segments A,B (m,3) -> (n, m)."""
    p = np.atleast_2d(p)
    AB = B - A
    l2 = np.maximum((AB * AB).sum(1), 1e-12)
    AP = p[:, None, :] - A[None, :, :]
    t = np.clip((AP * AB[None]).sum(2) / l2[None], 0, 1)
    C = A[None] + t[..., None] * AB[None]
    return np.linalg.norm(p[:, None, :] - C, axis=2)


# ---- mesh buffers -------------------------------------------------------------------------------

class Mesh:
    def __init__(self):
        self.V, self.F, self.UV, self.N = [], [], [], []
        self.n = 0

    def add(self, V, F, UV, N):
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


def tube(centers, radius_fn, sides, u_rep, v_tile, start_normal=None, cap_end=False, cap_start=False, v0=0.0):
    """Sweep a ring along `centers` (n,3). radius_fn(i, angles) -> radii (sides+1,) for ring i.
    Rotation-minimising frames; seam duplicated; u in [0, u_rep], v = arc length / v_tile + v0.
    Returns V, F (tris, outward), UV, N."""
    C = np.asarray(centers, float)
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
    Bs = np.cross(T, Ns)
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
    F = []
    m = sides + 1
    for i in range(n - 1):
        for j in range(sides):
            a, b, c, d = i * m + j, i * m + j + 1, (i + 1) * m + j + 1, (i + 1) * m + j
            F.append((a, b, c))
            F.append((a, c, d))
    F = np.array(F, np.int64)
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


def triplanar_split(V, F, N, tile, rot=0.0, offset=(0.0, 0.0)):
    """Per-face dominant-axis projection UVs; vertices are duplicated only where faces sharing them
    use different axes. Returns V2, F2, UV2, N2."""
    _, fn = vertex_normals(V, F)
    axis = np.argmax(np.abs(fn), axis=1)
    sign = np.sign(fn[np.arange(len(F)), axis])
    key = axis * 2 + (sign > 0)
    remap = {}
    V2, N2, UV2, K = [], [], [], []
    F2 = np.zeros_like(F)
    cr, sr = math.cos(rot), math.sin(rot)
    for fi in range(len(F)):
        for c in range(3):
            vi = F[fi, c]
            k = (vi, key[fi])
            if k not in remap:
                remap[k] = len(V2)
                p = V[vi]
                a = axis[fi]
                if a == 0:
                    uv = (p[2] * sign[fi], p[1])
                elif a == 1:
                    uv = (p[0], p[2] * sign[fi])
                else:
                    uv = (-p[0] * sign[fi], p[1])
                u, v = uv[0] / tile, uv[1] / tile
                UV2.append((u * cr - v * sr + offset[0], u * sr + v * cr + offset[1]))
                V2.append(p)
                N2.append(N[vi])
            F2[fi, c] = remap[k]
    return np.array(V2), F2, np.array(UV2), np.array(N2)


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
        self.bark = Mesh()
        self.leaf = {"shade": Mesh(), "sun": Mesh()}
        self.fruit = Mesh()
        self.rails = []  # (polyline studs local, lift, kind, name, route id)
        self.boughs = []
        self.tunnels = []  # (A, B, r) capsule segments
        self.log = {}

    # -- coordinates --
    def local(self, P):
        return (np.asarray(P, float) * SPU) - self.root[None]

    def samples(self, rid):
        return self.local(self.data["samples"][rid])

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
        if len(A) == 0:
            return np.full(len(P), 1e9)
        d = seg_dist(P, A, B) - r[None]
        return d.min(axis=1)

    # -- build --
    def build(self):
        rec = self.rec
        trunk = rec["trunk"]
        self.Rt = trunk_radius_fn(trunk)
        self.build_trunk(trunk)
        for m in rec["members"]:
            self.build_bough(m)
        self.collect_foreign_tunnels()
        self._tun = self.tunnel_arrays()
        self.build_roots()
        self.build_twigs_and_leaves()
        return self

    # .. trunk ..
    def build_trunk(self, trunk):
        P = self.samples(trunk["id"])
        self.trunkP = P
        L = arclen(P)[-1]
        self.trunkL = L
        self.rails.append((P, 0.0, "trunk", trunk["name"], trunk["id"]))
        Q, s, t = resample(P, 1.8)
        # carry the trunk down into the ground (pivot y = 0 is the ground at the root)
        foot = Q[0]
        below = [np.array([foot[0], y, foot[2]]) for y in (-3.0, -1.6, -0.6) if y < foot[1] - 0.2]
        # leader: continue above the trunk route into the crown, away from routes leaving the top
        top, ttan = Q[-1], norm(Q[-1] - Q[-2])
        away = np.zeros(3)
        for m in self.rec["members"]:
            mp = self.samples(m["id"])
            if np.linalg.norm(mp[0] - top) < 3.0:
                away -= norm(mp[min(len(mp) - 1, 6)] - mp[0]) * np.array([1, 0, 1])
        Rtop = float(self.Rt(1.0))
        crown_top = self.H * (0.82 if self.cat != "giant" else 0.86)
        lead_len = max(0.0, crown_top - top[1]) * (0.55 if self.cat == "giant" else 0.8)
        leader = []
        if lead_len > Rtop * 1.5:
            d = norm(ttan * 0.4 + np.array([0, 1.0, 0]) + 0.35 * norm(away + 1e-9) * (np.linalg.norm(away) > 0.1))
            k = max(3, int(lead_len / 2.5))
            for j in range(1, k + 1):
                f = j / k
                bend = np.array([math.sin(f * 2.1 + self.rec["seed"]) * 0.08, 0, math.cos(f * 1.7 + self.rec["seed"]) * 0.08]) * lead_len
                leader.append(top + d * lead_len * f + bend * f)
        C = np.concatenate([np.array(below).reshape(-1, 3), Q, np.array(leader).reshape(-1, 3)])
        nb, nq, nl = len(below), len(Q), len(leader)
        # route parameter per ring (below: 0, leader: >1)
        tt = np.concatenate([np.zeros(nb), t, 1.0 + np.linspace(0, 1, nl + 1)[1:] if nl else np.zeros(0)])
        rng = self.rng
        lobes = 5 + int(rng.integers(0, 3))
        lobe_ang = rng.random(lobes) * 2 * math.pi
        lobe_amp = 0.55 + 0.45 * rng.random(lobes)
        flute_ph = rng.random() * 6.28
        R0 = float(self.Rt(0.0))
        Rleader_end = max(0.35, Rtop * 0.18)

        def radius(i, ang):
            y = C[i][1]
            if tt[i] <= 1.0:
                base = float(self.Rt(min(tt[i], 1.0)))
            else:
                f = tt[i] - 1.0
                base = Rtop + (Rleader_end - Rtop) * f ** 0.8
            # buttress lobes near the ground (decay over ~1.1 R0 of height)
            fall = math.exp(-max(0.0, y) / (0.55 * R0)) if y > 0 else 1.0
            lob = np.zeros_like(ang)
            for a0, amp in zip(lobe_ang, lobe_amp):
                da = np.angle(np.exp(1j * (ang - a0)))
                lob += amp * np.exp(-(da / 0.38) ** 2)
            # gentle fluting and bark relief: |dr| <= 0.12 st on the climbable trunk
            flute = 0.06 * np.sin(ang * 7 + flute_ph + y * 0.15) + 0.04 * np.sin(ang * 3 - y * 0.31)
            r = base * (1 + 0.95 * fall * lob) + flute * min(1.0, base / 2.0)
            return np.maximum(r, 0.2)

        circ = 2 * math.pi * R0
        u_rep = max(2, int(round(circ / 4.5)))
        v_tile = circ / u_rep * 1.3
        sides = 16 if R0 > 2.4 else (14 if R0 > 1.6 else 12)
        V, F, UV, N = tube(C, radius, sides, u_rep, v_tile, start_normal=[1.0, 0.0, 0.0], cap_end=True, v0=0.0)
        self.bark.add(V, F, UV, N)
        self.trunk_rings = (C, tt)
        # trunk tunnel: the squirrel orbits the bark (tapered + 0.7 st) -> keep leaves 2.6 st beyond
        for a, b, ta, tb in zip(Q[:-1], Q[1:], t[:-1], t[1:]):
            self.tunnels.append((a, b, float(self.Rt((ta + tb) / 2)) + 0.7 + 2.6))
        self.log["trunk_rings"] = len(C)

    def trunk_r_at_y(self, y):
        P = self.trunkP
        tt = arclen(P) / max(arclen(P)[-1], 1e-9)
        return float(self.Rt(np.interp(y, P[:, 1], tt)))

    # .. boughs, bridges, lookouts ..
    def build_bough(self, route):
        P = self.samples(route["id"])
        kind = route["kind"]
        lift = lift_of(route)
        self.rails.append((P, lift, kind, route["name"], route["id"]))
        name = route["name"]
        if name.endswith("OPEN SKY LOOKOUT"):
            self.build_lookout_pad(P, lift)
            return
        L = arclen(P)[-1]
        start = P[0]
        dtrunk = seg_dist(start[None], self.trunkP[:-1], self.trunkP[1:]).min()
        on_trunk = dtrunk < 3.5
        rt = self.trunk_r_at_y(start[1]) if on_trunk else 1.2
        cat = self.cat
        r_base = {"named": 1.45, "outer": 1.05, "giant": 2.1, "apple": 0.78, "estate": 1.55}[cat]
        if kind == "bridge":
            r_base *= 0.85
        if kind == "lookout":
            r_base = 1.05
        if on_trunk:
            r_base = min(r_base, 0.78 * rt)
        r_tip = max(0.5 * lift + 0.08, 0.32)
        r_base = max(r_base, r_tip * 1.15)
        step = 1.6 if L < 30 else 2.2
        Q, s, u = resample(P, step)
        # rounded tip: extend a little past the rail end along the last tangent
        tan_end = norm(Q[-1] - Q[-2])
        coll = 0.9 * rt if on_trunk else 0.6
        prof = r_tip + (r_base - r_tip) * (1 - u) ** 1.25
        collar = 1 + (0.55 * np.exp(-s / max(coll, 0.3)) if on_trunk else 0.0)
        radii = prof * collar
        centers = Q + np.array([0.0, 1.0, 0.0])[None] * (lift - radii)[:, None]
        rng = self.rng
        wob_ph = rng.random() * 6.28

        def radius(i, ang):
            r = radii[i]
            return r * (1 + 0.05 * np.sin(ang * 3 + wob_ph + i * 0.4))

        sides = 10 if r_base > 1.3 else 8
        circ = 2 * math.pi * r_base
        u_rep = max(1, int(round(circ / 4.0)))
        v_tile = circ / u_rep * 1.3
        V, F, UV, N = tube(centers, radius, sides, u_rep, v_tile, cap_end=True)
        self.bark.add(V, F, UV, N)
        # tunnel above the rail where the squirrel's body is (feet = rail + lift)
        self.add_tunnel_polyline(P, 2.5, lift_up=lift + 0.9)
        self.boughs = getattr(self, "boughs", [])
        self.boughs.append({"route": route, "P": P, "Q": centers, "radii": radii, "L": L, "lift": lift, "kind": kind,
                            "on_trunk": on_trunk})

    def build_lookout_pad(self, P, lift):
        mid = P.mean(axis=0)
        feet = mid[1] + lift
        hr, vr = 3.6, 1.4
        V0, F0 = icosphere(2)
        rng = self.rng
        k = rng.random(4) * 6.28
        d = V0
        bump = 1 + 0.08 * np.sin(d[:, 0] * 5 + k[0]) * np.sin(d[:, 2] * 4 + k[1])
        V = d * np.array([hr, vr, hr])[None] * bump[:, None]
        V[:, 1] = np.minimum(V[:, 1], vr * 0.55)  # flat top where the squirrel stands
        V = V + np.array([mid[0], feet - vr * 0.55, mid[2]])[None]
        N, _ = vertex_normals(V, F0)
        V2, F2, UV2, N2 = triplanar_split(V, F0, N, 4.5)
        self.bark.add(V2, F2, UV2, N2)
        # open sky over the perch
        self.add_tunnel_polyline(np.array([mid - [0, 0, 0], mid + [0, 12, 0]]), 9.0)

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
        base = self.root[1]
        for h in hs["houses"]:
            peak = h["cfg"].get("peak", 10) * 0.82
            w = max(h["w"], h["d"]) / 2
            self._add_box(h["x"], h["z"], w, w, None, peak, base)
        for c in hs["commercialBounds"]:
            self._add_box(c["x"], c["z"], c["w"] / 2, c["d"] / 2, None, c["roof"], base)
        for b in hs["riverBuildings"]:
            w = max(b["w"], b["d"]) / 2
            self._add_box(b["x"], b["z"], w, w, b["base"], b["base"] + b["h"] + b["rise"], base)
        self.log["foreign_routes_in_crown"] = n

    def _add_box(self, x, z, hx, hz, y0, y1, base):
        c = np.array([x * SPU, 0, z * SPU]) - self.root
        if abs(c[0]) > 120 or abs(c[2]) > 120:
            return
        ylo = (y0 * SPU - self.root[1]) if y0 is not None else -5.0
        yhi = (y1 * SPU - self.root[1]) if y0 is not None else (y1 * SPU + (base - self.root[1]))
        if y0 is None:
            yhi = y1 * SPU + 1.0 - (self.root[1] - 0.0) * 0  # roofs are absolute heights in v5.4
            yhi = y1 * SPU - self.root[1] + 1.0
        self.boxes.append((np.array([c[0] - hx * SPU, ylo, c[2] - hz * SPU]), np.array([c[0] + hx * SPU, yhi, c[2] + hz * SPU])))

    def box_clear(self, P):
        if not self.boxes:
            return np.full(len(P), 1e9)
        out = np.full(len(P), 1e9)
        for lo, hi in self.boxes:
            d = np.maximum(np.maximum(lo[None] - P, P - hi[None]), 0)
            out = np.minimum(out, np.linalg.norm(d, axis=1))
        return out

    # .. roots ..
    def build_roots(self):
        rng = self.rng
        R0 = float(self.Rt(0.0))
        n = 5 + int(rng.integers(0, 3))
        if self.cat == "apple":
            n = 5
        base_ang = rng.random() * 6.28
        for k in range(n):
            a = base_ang + k * 2 * math.pi / n + rng.normal(0, 0.25)
            d = np.array([math.cos(a), 0.0, math.sin(a)])
            Lr = R0 * (1.6 + 1.2 * rng.random())
            m = 7
            pts = []
            for j in range(m):
                f = j / (m - 1)
                rad = R0 * 0.35 + Lr * f
                y = 0.35 * R0 * (1 - f) ** 1.5 + 0.15 * R0 * math.sin(f * math.pi) - 1.2 * f ** 2
                side = np.array([-d[2], 0, d[0]]) * math.sin(f * 3 + k) * 0.25 * R0 * f
                pts.append(d * rad + np.array([0, y, 0]) + side)
            pts = np.array(pts)
            r0 = R0 * (0.42 + 0.12 * rng.random())

            def radius(i, ang, r0=r0):
                f = i / (m - 1)
                return np.full_like(ang, max(0.12, r0 * (1 - f) ** 1.1 + 0.1))

            V, F, UV, N = tube(pts, radius, 6, 1, 3.0, cap_end=True)
            self.bark.add(V, F, UV, N)

    # .. twigs and leaves ..
    def crown_frame(self):
        """Crown centre and radii from the bough ends."""
        ends = [b["P"][-1] for b in self.boughs if b["kind"] in ("branch", "lookout")]
        if not ends:
            ends = [self.trunkP[-1]]
        E = np.array(ends)
        top = self.trunkP[-1]
        c = np.array([E[:, 0].mean() * 0.6 + top[0] * 0.4, 0, E[:, 2].mean() * 0.6 + top[2] * 0.4])
        rh = max(np.max(np.hypot(E[:, 0] - c[0], E[:, 2] - c[2])), self.H * 0.18)
        ylo = min(E[:, 1].min(), top[1])
        yhi = max(E[:, 1].max(), top[1])
        c[1] = (ylo + yhi) / 2
        return c, rh, ylo, yhi

    def build_twigs_and_leaves(self):
        rng = self.rng
        sp = self.sp
        c, rh, ylo, yhi = self.crown_frame()
        self.crown = (c, rh, ylo, yhi)
        scale = {"named": 1.0, "outer": 0.8, "giant": 1.35, "apple": 0.45, "estate": 1.0}[self.cat]
        if sp == "willow":
            scale = 0.75
        rho0 = 6.0 * scale  # nominal clump radius (studs)
        clumps = []  # (centre, radius, squash, priority)
        twig_tris = 0

        def try_clump(p, rho, pri, squash=0.82):
            # shrink / push until clear of every tunnel and building; returns accepted (p, rho) or None
            p = np.array(p, float)
            for _ in range(6):
                cl = self.clearance(p[None])[0]
                need = rho * 1.12
                if cl >= need and self.box_clear(p[None])[0] >= rho * 0.55 and p[1] - rho * squash > self.min_leaf_y:
                    clumps.append((p, rho, squash, pri))
                    return True
                if cl > need * 0.62:
                    rho = cl / 1.12
                    if rho >= rho0 * 0.38:
                        continue
                # push away from the nearest tunnel
                A, B, r = self._tun
                d = seg_dist(p[None], A, B)[0] - r
                j = int(np.argmin(d))
                ab = B[j] - A[j]
                tt = np.clip(np.dot(p - A[j], ab) / max(np.dot(ab, ab), 1e-9), 0, 1)
                q = A[j] + ab * tt
                away = norm(p - q + np.array([0, 0.3, 0]))
                p = p + away * (need - cl + 0.5)
            return False

        self.min_leaf_y = {"apple": 3.2, "willow": 9.0}.get(sp, max(6.0, self.H * 0.22))
        # 1. twigs from the boughs, with a clump on each twig end
        twigs = []
        for b in self.boughs:
            if b["kind"] == "lookout" and b["L"] < 4:
                continue
            P, L = b["P"], b["L"]
            nt = max(2, int(L / (rho0 * 1.15)))
            if b["kind"] == "bridge":
                nt = max(2, int(L / (rho0 * 1.6)))
            ss = np.linspace(0.32 if b["kind"] != "bridge" else 0.12, 0.97, nt) * L
            sP = arclen(P)
            for si, sv in enumerate(ss):
                k = int(np.searchsorted(sP, sv).clip(1, len(P) - 1))
                p = P[k]
                tan = norm(P[k] - P[k - 1])
                side = norm(np.cross(tan, [0, 1, 0]) + 1e-9)
                best = None
                for attempt in range(8):
                    sg = 1 if (si + attempt) % 2 == 0 else -1
                    ang = rng.uniform(0.5, 1.25)
                    up = rng.uniform(0.25, 0.85)
                    d = norm(tan * math.cos(ang) + side * sg * math.sin(ang) + np.array([0, up, 0]))
                    tl = rho0 * rng.uniform(0.9, 1.5)
                    e = p + d * tl + np.array([0, b["lift"] - 0.6, 0])
                    cl = self.clearance(e[None])[0]
                    if best is None or cl > best[0]:
                        best = (cl, e, d, tl)
                    if cl > rho0 * 1.2:
                        break
                cl, e, d, tl = best
                base = p + np.array([0, b["lift"] - 0.5, 0])
                twigs.append((base, e, 0.42 if self.cat != "giant" else 0.6))
                try_clump(e + d * rho0 * 0.35 + np.array([0, rho0 * 0.25, 0]), rho0 * rng.uniform(0.85, 1.15), 1)
            # tip burst: around and beyond the end of the rail (the tip itself stays visible)
            if b["kind"] in ("branch",):
                e = P[-1]
                tan = norm(P[-1] - P[-4] if len(P) > 4 else P[-1] - P[0])
                for k in range(3):
                    a = k * 2.1 + rng.random()
                    off = norm(tan * 0.8 + np.array([math.cos(a), 0.6 + 0.3 * rng.random(), math.sin(a)]))
                    try_clump(e + off * rho0 * 1.6, rho0 * rng.uniform(0.9, 1.2), 0)
        # 2. crown dome (silhouette) and a lower skirt
        nd = int(np.clip((rh / rho0) ** 2 * 2.4, 8, 60))
        golden = math.pi * (3 - math.sqrt(5))
        rv = max((yhi - ylo) / 2 + rho0 * 0.8, rh * 0.45)
        cy = (ylo + yhi) / 2 + rho0 * 0.6
        shape_y = {"elm": 0.9, "oak": 0.72, "maple": 1.0, "sycamore": 0.85, "willow": 0.75, "apple": 0.85}[sp]
        for k in range(nd):
            yy = 1 - (k + 0.5) / nd * 1.45
            rr = math.sqrt(max(0.0, 1 - yy * yy))
            a = golden * k + rng.random() * 0.2
            f = 0.92 + 0.12 * rng.random()
            wide = 1.0 + (0.18 * yy if sp == "elm" else 0.0)
            p = np.array([c[0] + math.cos(a) * rr * rh * f * wide, cy + yy * rv * shape_y * f, c[2] + math.sin(a) * rr * rh * f * wide])
            try_clump(p, rho0 * rng.uniform(0.95, 1.3), 2)
        # 3. inner fill (shade layer)
        for k in range(int(nd * 0.5)):
            a = rng.random() * 6.28
            rr = math.sqrt(rng.random()) * rh * 0.7
            p = np.array([c[0] + math.cos(a) * rr, cy + rng.uniform(-0.6, 0.5) * rv * shape_y, c[2] + math.sin(a) * rr])
            try_clump(p, rho0 * rng.uniform(1.0, 1.3), 3)

        # accept: drop clumps mostly inside others (biggest first keeps volume)
        order = sorted(range(len(clumps)), key=lambda i: (clumps[i][3], -clumps[i][1]))
        kept = []
        for i in order:
            p, r, sq, pri = clumps[i]
            ok = True
            for q, rq, _, _ in kept:
                if np.linalg.norm(p - q) + r * 0.55 < rq:
                    ok = False
                    break
            if ok:
                kept.append(clumps[i])
        budget = self.opts.get("max_clumps", {"giant": 70, "apple": 26}.get(self.cat, 48))
        kept = kept[:budget]
        self.clumps = kept
        # twig meshes (only twigs whose clump survived is not tracked; all twigs are drawn)
        for base, e, r0 in twigs:
            pts = np.array([base, base * 0.55 + e * 0.45 + np.array([0, 0.4, 0]), e])
            V, F, UV, N = tube(pts, lambda i, ang, r0=r0: np.full_like(ang, max(0.14, r0 * (1 - i / 2.6))), 5, 1, 3.0, cap_end=True)
            self.bark.add(V, F, UV, N)
            twig_tris += len(F)
        self.log["twig_tris"] = twig_tris
        self.build_clump_meshes(kept)
        if sp == "willow":
            self.build_willow_fronds(kept)
        if sp == "apple":
            self.build_apples(kept)

    def build_clump_meshes(self, kept):
        rng = self.rng
        if not kept:
            return
        Cs = np.array([k[0] for k in kept])
        Rs = np.array([k[1] for k in kept])
        cc = (Cs * Rs[:, None] ** 2).sum(0) / (Rs ** 2).sum()
        ext = np.maximum(np.abs(Cs - cc[None]).max(0) + Rs.max(), 1.0)
        ext[1] = max(ext[1], ext[0] * 0.5)
        self.canopy_centre, self.canopy_ext = cc, ext
        tile = float(np.clip(self.H * 0.1, 4.0, 9.0))
        self.leaf_tile = tile
        yl, yh = Cs[:, 1].min(), Cs[:, 1].max()
        for (p, rho, sq, pri) in kept:
            big = rho > 4.5
            V0, F0 = icosphere(2 if big else 1)
            nl = 7 if big else 5
            dirs = norm(rng.normal(size=(nl, 3)))
            amps = rng.uniform(0.12, 0.26, nl)
            disp = np.ones(len(V0))
            for dv, am in zip(dirs, amps):
                disp += am * np.maximum(0, V0 @ dv) ** 5
            disp += 0.05 * np.sin(V0[:, 0] * 7 + rng.random() * 6) * np.sin(V0[:, 2] * 6 + rng.random() * 6)
            flat = np.where(V0[:, 1] < -0.2, 1 - 0.22 * (-V0[:, 1] - 0.2), 1.0)
            V = V0 * disp[:, None] * flat[:, None] * rho
            V[:, 1] *= sq
            V = V + p[None]
            ng, _ = vertex_normals(V, F0)
            # soft volume normals: blend toward the canopy ellipsoid normal
            nc = norm((V - cc[None]) / (ext[None] ** 2))
            nclump = norm(V - p[None])
            N = norm(ng * 0.35 + nclump * 0.25 + nc * 0.40)
            h = (p[1] - yl) / max(yh - yl, 1e-6)
            radial = np.hypot(p[0] - cc[0], p[2] - cc[2]) / max(ext[0], ext[2])
            sunny = (pri in (0, 2) and h > 0.25) or h > 0.72 or radial > 0.8
            if pri == 3:
                sunny = False
            V2, F2, UV2, N2 = triplanar_split(V, F0, N, tile, rot=rng.random() * 6.28, offset=tuple(rng.random(2)))
            self.leaf["sun" if sunny else "shade"].add(V2, F2, UV2, N2)

    def build_willow_fronds(self, kept):
        rng = self.rng
        cc = self.canopy_centre
        n = 0
        for (p, rho, sq, pri) in kept:
            dxz = np.array([p[0] - cc[0], 0, p[2] - cc[2]])
            dist = np.linalg.norm(dxz)
            if dist < self.canopy_ext[0] * 0.35 and p[1] > cc[1]:
                continue
            m = 3 if rho > 3 else 2
            for k in range(m):
                a = rng.random() * 6.28
                out = norm(dxz + 1e-6) if dist > 0.5 else np.array([math.cos(a), 0, math.sin(a)])
                spread = np.array([math.cos(a), 0, math.sin(a)]) * 0.5 + out * 0.8
                top = p + norm(spread) * rho * 0.75 + np.array([0, -rho * 0.25, 0])
                length = rng.uniform(10, 18) * (0.7 + 0.6 * min(1, dist / max(self.canopy_ext[0], 1)))
                bottom_y = max(3.5, top[1] - length)
                if top[1] - bottom_y < 4:
                    continue
                drift = out * rng.uniform(0.5, 2.0)
                pts = np.array([top, top + np.array([0, -(top[1] - bottom_y) * 0.5, 0]) + drift * 0.6, np.array([top[0], bottom_y, top[2]]) + drift])
                if self.clearance(pts).min() < 0.8:
                    continue
                w = rng.uniform(1.0, 1.6)

                def radius(i, ang, w=w):
                    f = i / 2
                    r = w * (1.0 - 0.55 * f)
                    return r * (1 + 0.35 * np.cos(2 * ang))  # flattened ribbon-ish curtain

                V, F, UV, N = tube(pts, radius, 6, 1, self.leaf_tile * 0.8, cap_end=True, cap_start=True)
                self.leaf["sun"].add(V, F, UV, N)
                n += 1
        self.log["willow_fronds"] = n

    def build_apples(self, kept):
        rng = self.rng
        n = 0
        cc = self.canopy_centre
        for (p, rho, sq, pri) in kept:
            for k in range(2):
                if n >= 36:
                    break
                d = norm(rng.normal(size=3) * np.array([1, 0.4, 1]) + np.array([0, -0.35, 0]))
                if np.dot(d, norm(p - cc + 1e-6)) < -0.2:
                    continue
                c = p + d * rho * np.array([0.97, sq * 0.97, 0.97])
                if self.clearance(c[None])[0] < 0.6:
                    continue
                r = 0.62
                lat, lon = 5, 7
                V, UV, N = [], [], []
                red = n % 3 != 2
                for i in range(lat + 1):
                    th = math.pi * i / lat
                    for j in range(lon + 1):
                        ph = 2 * math.pi * j / lon
                        nrm = np.array([math.sin(th) * math.cos(ph), math.cos(th), math.sin(th) * math.sin(ph)])
                        squash = 1 - 0.12 * (1 - abs(math.cos(th)))
                        V.append(c + nrm * r * np.array([1, 0.92, 1]) * (1 - 0.15 * math.exp(-(th / 0.35) ** 2)))
                        N.append(nrm)
                        UV.append(((j / lon) * 0.5 + (0.0 if red else 0.5), 1 - i / lat))
                F = []
                for i in range(lat):
                    for j in range(lon):
                        a, b, c2, d2 = i * (lon + 1) + j, i * (lon + 1) + j + 1, (i + 1) * (lon + 1) + j + 1, (i + 1) * (lon + 1) + j
                        F += [(a, c2, b), (a, d2, c2)]
                self.fruit.add(np.array(V), np.array(F), np.array(UV), np.array(N))
                n += 1
        self.log["apples"] = n

    # -- reports --
    def tri_counts(self):
        return {"bark": self.bark.tris, "leaves_shade": self.leaf["shade"].tris, "leaves_sun": self.leaf["sun"].tris,
                "fruit": self.fruit.tris}


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
