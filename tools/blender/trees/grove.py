"""The D34 woods: giants, pines and nut trees built round their climbing routes (headless bpy 5.2.x, numpy).

  PY=/root/.cache/spicy-rodents/venv/bin/python
  lune run tools/blender/trees/dump_woods.luau                      (build/woods/templates.json)
  flock /tmp/spicy-heavy.lock nice -n 10 $PY -I tools/blender/trees/grove.py --kinds all --fbx --out build/art/woods \
      [--render street,climb] [--lineup]

One Model per kind (data/woods.json `kinds`); every woods tree in the town wears its kind's Model, turned and scaled
(Server/Assets/WoodsArt). The Model is built round the kind's climbing template (Shared/World/TreeShapes.grow, dumped
by dump_woods.luau), so the squirrel runs on its bark exactly as on the route-true town trees (treegen.py):
  * the trunk is a tube whose radius at route parameter t is the squirrel's own trunk radius, max(0.8, r(1 - 0.48 t))
    (Routes/Motion visualPose), all the way round, from 3 studs under the ground to the route's top; above it the
    leader carries on to the model's height (a pine's spire, a broadleaf's crown limbs);
  * every bough route is a tube whose top edge is the squirrel's feet line (the rail + its feet lift, visualOffset):
    each ring is hung under that line (centre = feet - radius x the ring's up), so nothing of the bough stands over
    the feet and the feet stand on its bark; past the route's end the bough carries on as twigs;
  * nothing else (side branches, twigs, leaves, needles, nuts, cones) comes into a walk's tunnel (the body over the
    feet line) or within 2.2 studs of the trunk's climbing surface, so a climbing squirrel stays seen;
  * pines grow in whorls: branches round the trunk every few studs, shorter toward the top (a cone; the white pine in
    tiers, the red pine's crown high on a bare trunk), their needles in layered alpha cards; a pine's bough routes are
    short level boughs among the whorls (the ladder's rungs);
  * broadleaves (the giants, the nut trees) grow side branches off every bough and crown limbs off the leader, twigs
    off those, and leaf sprays (alpha cards) at the twigs, inside a crown envelope; the hazel is a shrub of stems;
  * nuts and cones (acorns, walnuts, chestnut burrs, hazelnuts, hickory nuts; pine, spruce and fir cones) hang under
    the sprays, coloured from a swatch painted into the leaf atlas (so a tree is two MeshParts: Bark, Leaves).
Leaf cards are two-faced in the mesh (no DoubleSided needed); the Leaves part's colour map carries the alpha (its
AlphaMode must be Transparency, or its colour map on TextureID: WoodsArt does either). Per kind into --out:
  <kind>.fbx    MeshParts Bark (tiling bark texture) and Leaves (spray atlas + fruit swatch), textures embedded
  <kind>.json   pivot (the ground under the foot), part bounds (Roblox axes, from the pivot), tris, checks, mesh digest
  renders/<kind>_<view>.png, renders/lineup.png
Budgets (phones; ~300 trees in the town, the same few meshes instanced): pines and nut trees 2,600 bark + 2,800 leaves
(the hazel 1,600 + 2,000), the giants 7,000 + 8,000 (each stands once).
"""
import argparse
import hashlib
import json
import math
import os
import sys
import time

import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Vector  # noqa: E402
from mathutils.bvhtree import BVHTree  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_trees as bt  # noqa: E402
import textures as tx  # noqa: E402
import treegen as tg  # noqa: E402

Y = np.array([0.0, 1.0, 0.0])
MIN_R = 0.8  # the squirrel's trunk radius never goes under 0.32 u
TRUNK_CLEAR = 2.2  # leaves and needles stay this far off the trunk's climbing surface
TUNNEL_R = 1.6  # a walk's tunnel: round the line 0.9 over the feet
TUNNEL_UP = 0.9

# style: "pine" | "broad" | "shrub"; bark: (textures family, tint); leaf: spray shape; pal: leaf greens (no autumn);
# fruit: nut or cone; budgets: bark and leaf triangles; sides: the trunk's ring; card: spray card length, width
SPECIES = {
    "oak": dict(style="broad", bark=("oak", None), leaf="oak", pal=["#5e8a3a", "#6f9a44", "#4f7a33", "#86a856"],
                fruit="acorn", bark_tris=7000, leaf_tris=8000, sides=14, card=(11.0, 9.8), boughR=(2.8, 1.0)),
    "elm": dict(style="broad", bark=("elm", None), leaf="elm", pal=["#5d8b45", "#6e9a4f", "#4d7a3c", "#7ba556"],
                fruit=None, bark_tris=7000, leaf_tris=8000, sides=14, card=(10.5, 9.2), boughR=(2.6, 0.9)),
    "beech": dict(style="broad", bark=("maple", "#c9c6bd"), leaf="apple", pal=["#6a9a3e", "#7fae4a", "#5b8a37"],
                  fruit=None, bark_tris=7000, leaf_tris=8000, sides=14, card=(10.5, 9.2), boughR=(2.8, 1.0)),
    "white_oak": dict(style="broad", bark=("oak", "#b8b2a6"), leaf="oak", pal=["#5e8a3a", "#73a046", "#527d34"],
                      fruit="acorn", bark_tris=2600, leaf_tris=2800, sides=9, card=(9.0, 8.0), boughR=(1.25, 0.5)),
    "pin_oak": dict(style="broad", bark=("maple", "#8a8a80"), leaf="oak", pal=["#4f7f3a", "#5f8e40", "#456f33"],
                    fruit="acorn", bark_tris=2600, leaf_tris=2800, sides=8, card=(8.4, 7.4), boughR=(1.0, 0.45)),
    "walnut": dict(style="broad", bark=("oak", "#5a4a3c"), leaf="pinnate", pal=["#6b9640", "#7ea64a", "#5a8536"],
                   fruit="walnut", bark_tris=2600, leaf_tris=2800, sides=9, card=(9.0, 8.0), boughR=(1.15, 0.5)),
    "hickory": dict(style="broad", bark=("elm", "#9a948a"), leaf="pinnate", pal=["#5e8c3c", "#73a047", "#527d34"],
                    fruit="hickory", bark_tris=2600, leaf_tris=2800, sides=8, card=(8.4, 7.4), boughR=(1.0, 0.45)),
    "chestnut": dict(style="broad", bark=("elm", "#8a6e55"), leaf="elm", pal=["#58873a", "#6b9a44", "#4b7632"],
                     fruit="burr", bark_tris=2600, leaf_tris=2800, sides=9, card=(9.0, 8.0), boughR=(1.25, 0.5)),
    "hazel": dict(style="shrub", bark=("maple", "#9a7a5a"), leaf="apple", pal=["#6c9a44", "#80ab50", "#5d8a3c"],
                  fruit="hazelnut", bark_tris=1600, leaf_tris=2000, sides=7, card=(4.6, 4.0), boughR=(0.6, 0.3)),
    "white_pine": dict(style="pine", bark=("apple", "#7a6a5a"), leaf="longneedle", pal=["#4e7d5a", "#5f8f68", "#3f6a4c"],
                       fruit="pinecone", bark_tris=2600, leaf_tris=2800, sides=8, card=(4.6, 3.4), boughR=(0.55, 0.25),
                       whorl=6.5, per=5, base=0.16, shape="tiers", tilt=0.10),
    "spruce": dict(style="pine", bark=("apple", "#8a7060"), leaf="needle", pal=["#2e5639", "#3b6644", "#24482f"],
                   fruit="sprucecone", bark_tris=2600, leaf_tris=2800, sides=8, card=(3.8, 3.0), boughR=(0.5, 0.22),
                   whorl=4.2, per=5, base=0.10, shape="cone", tilt=-0.28),
    "fir": dict(style="pine", bark=("maple", "#8f8a80"), leaf="needle", pal=["#305c3f", "#3e6b4a", "#284e35"],
                fruit="fircone", bark_tris=2400, leaf_tris=2600, sides=7, card=(3.2, 2.6), boughR=(0.45, 0.2),
                whorl=3.6, per=5, base=0.10, shape="spire", tilt=-0.05),
    "red_pine": dict(style="pine", bark=("apple", "#b0603a"), leaf="longneedle", pal=["#3f6b3a", "#4f7c45", "#355c31"],
                     fruit="pinecone", bark_tris=2600, leaf_tris=2800, sides=8, card=(4.6, 3.4), boughR=(0.55, 0.25),
                     whorl=5.0, per=4, base=0.52, shape="round", tilt=0.18),
}
# fruit: (colour A, colour B (a cap or husk, the upper part), length, width, how many)
FRUIT = {
    "acorn": ("#8a6a3a", "#5d4a30", 0.55, 0.38, 46),
    "walnut": ("#7f9b45", "#6f8a3c", 0.62, 0.6, 40),
    "burr": ("#a3b14e", "#8c9a40", 0.7, 0.7, 36),
    "hazelnut": ("#9a7a4a", "#8fae5a", 0.38, 0.34, 30),
    "hickory": ("#7e9a4c", "#6b853f", 0.55, 0.52, 36),
    "pinecone": ("#7a5530", "#5c3f24", 1.3, 0.48, 26),
    "sprucecone": ("#6e4a2a", "#553820", 1.2, 0.36, 30),
    "fircone": ("#5a4a5a", "#463a48", 0.9, 0.36, 24),
}
SWATCH = 40  # px of the leaf atlas (512) given to the fruit's two colours


# ---- textures -----------------------------------------------------------------------------------

class Tex:
    def __init__(self, out):
        self.dir = os.path.join(out, "tex")
        os.makedirs(self.dir, exist_ok=True)

    def path(self, name):
        return os.path.join(self.dir, name)

    def bark(self, sp):
        fam, tint = SPECIES[sp]["bark"]
        names = [self.path(f"bark_{sp}_{k}.png") for k in ("color", "normal", "roughness")]
        if not all(os.path.exists(n) for n in names):
            c, n, r = tx.bark_maps(fam, seed=101 + sorted(SPECIES).index(sp), tint=tint)
            for p, a in zip(names, (c, n, r)):
                tx.write_png(p, a)
        return names

    def leaves(self, sp):
        """The spray atlas in the species' greens with the fruit swatch painted where the sprays leave the most room;
        returns (paths, swatch uv rect (u0, v0, u1, v1))."""
        S = SPECIES[sp]
        names = [self.path(f"leaves_{sp}_{k}.png") for k in ("color", "normal", "roughness")]
        meta = self.path(f"leaves_{sp}.json")
        if all(os.path.exists(n) for n in names) and os.path.exists(meta):
            with open(meta) as fh:
                return names, tuple(json.load(fh)["swatch"])
        shape = S["leaf"]
        lay = tx.spray_layout(shape, seed=31 + tx.SPRAY_SHAPES.index(shape))
        col = tx.down(tx.spray_colour(lay, S["pal"], "mid"))
        nrm, rough = tx.spray_normal_rough(lay)
        nrm, rough = tx.down(nrm, normal=True), tx.down(rough)
        n = col.shape[0]
        # the emptiest SWATCH square (lowest alpha), on an 8 px grid away from the edges
        a = col[..., 3]
        best, at = 1e9, (8, 8)
        for y in range(8, n - SWATCH - 8, 8):
            for x in range(8, n - SWATCH - 8, 8):
                s = float(a[y : y + SWATCH, x : x + SWATCH].sum())
                if s < best:
                    best, at = s, (x, y)
        x0, y0 = at
        fr = S.get("fruit")
        if fr:
            ca, cb = (tx.srgb_to_lin(tx.hex_rgb(h)) for h in FRUIT[fr][:2])
            rng = np.random.default_rng(7)
            for half, c in ((0, ca), (1, cb)):
                xs = slice(x0 + half * SWATCH // 2, x0 + (half + 1) * SWATCH // 2)
                patch = c[None, None, :] * (0.85 + 0.3 * rng.random((SWATCH, SWATCH // 2, 1)))
                col[y0 : y0 + SWATCH, xs, :3] = tx.lin_to_srgb(np.clip(patch, 0, 1))
                col[y0 : y0 + SWATCH, xs, 3] = 1.0
            nrm[y0 : y0 + SWATCH, x0 : x0 + SWATCH] = np.array([0.5, 0.5, 1.0])
            rough[y0 : y0 + SWATCH, x0 : x0 + SWATCH] = 0.6
        for p, arr in zip(names, (col, nrm, rough)):
            tx.write_png(p, arr)
        # uv: rows are top-down in the image; v up
        sw = ((x0 + 4) / n, 1 - (y0 + SWATCH - 4) / n, (x0 + SWATCH - 4) / n, 1 - (y0 + 4) / n)
        mean = col[..., :3][col[..., 3] > 0.5].mean(0) if (col[..., 3] > 0.5).any() else np.array([0.4, 0.55, 0.3])
        with open(meta, "w") as fh:
            json.dump({"swatch": sw, "mean": [float(x) for x in mean]}, fh)
        return names, sw

    def leaf_mean(self, sp):
        with open(self.path(f"leaves_{sp}.json")) as fh:
            return json.load(fh)["mean"]


# ---- geometry helpers ---------------------------------------------------------------------------

def rot_y(v, a):
    c, s = math.cos(a), math.sin(a)
    return np.array([v[0] * c + v[2] * s, v[1], -v[0] * s + v[2] * c])


def dir_of(az, elev):
    """Unit vector: azimuth clockwise from +z seen from above (x = sin), elevation up from level."""
    return np.array([math.sin(az) * math.cos(elev), math.sin(elev), math.cos(az) * math.cos(elev)])


class Tree:
    def __init__(self, kind, opts):
        self.kind = kind
        self.sp = kind["species"]
        self.S = SPECIES[self.sp]
        self.H = float(kind["height"])
        self.crown = float(kind["crown"])
        self.rng = np.random.default_rng(1000 + sum(ord(c) for c in kind["id"]))
        self.bark = tg.Mesh()
        self.leaf = tg.Mesh()
        self.tunnels = []  # (A, B, r)
        self.cards = 0
        self.fruit_spots = []
        self.log = {}
        routes = {r["k"]: r for r in kind["routes"]}
        self.trunk = routes[0]
        self.boughs = [routes[k] for k in sorted(routes) if k != 0]
        self.opts = opts

    # -- the trunk's climbing radius and axis --
    def trunk_line(self):
        P = tg.Curve(np.asarray(self.trunk["points"], float)).dense(0.5)
        self.trunkP = P
        self.trunkS = tg.arclen(P)
        self.trunkL = self.trunkS[-1]
        return P

    def r_at(self, t):
        R = self.trunk["surfaceRadius"]
        return np.maximum(MIN_R, R * (1 - 0.48 * np.asarray(t)))

    def axis_at_y(self, y):
        P = self.trunkP
        if y >= P[-1][1]:
            return self.leader_at_y(y)
        x = np.interp(y, P[:, 1], P[:, 0])
        z = np.interp(y, P[:, 1], P[:, 2])
        return np.array([x, y, z])

    def leader_at_y(self, y):
        top = self.trunkP[-1]
        d = self.leader_dir
        return top + d * ((y - top[1]) / max(d[1], 0.3))

    # -- tunnels: the walks' bodies and the trunk's climbing column --
    def add_tunnels(self):
        for b in self.boughs:
            P = tg.Curve(np.asarray(b["points"], float)).dense(1.0)
            lift = b.get("visualOffset") or 1.25
            Q = P + Y * (lift + TUNNEL_UP)
            for a, c in zip(Q[:-1], Q[1:]):
                self.tunnels.append((a, c, TUNNEL_R))
        A = np.array([t[0] for t in self.tunnels]) if self.tunnels else np.zeros((0, 3))
        B = np.array([t[1] for t in self.tunnels]) if self.tunnels else np.zeros((0, 3))
        R = np.array([t[2] for t in self.tunnels]) if self.tunnels else np.zeros(0)
        self._tun = (A, B, R)

    def clearance(self, P):
        """Distance past the walks' tunnels and the trunk's column (negative: inside)."""
        P = np.atleast_2d(np.asarray(P, float))
        A, B, R = self._tun
        out = np.full(len(P), 1e9)
        if len(A):
            out = (tg.seg_dist(P, A, B) - R[None]).min(1)
        # the trunk's column, up to the trunk route's top
        top = self.trunkP[-1][1]
        ys = np.clip(P[:, 1], self.trunkP[0][1], top)
        ax = np.stack([np.interp(ys, self.trunkP[:, 1], self.trunkP[:, 0]), ys, np.interp(ys, self.trunkP[:, 1], self.trunkP[:, 2])], 1)
        t = np.interp(ys, self.trunkP[:, 1], self.trunkS / self.trunkL)
        d = np.hypot(P[:, 0] - ax[:, 0], P[:, 2] - ax[:, 2]) - self.r_at(t) - TRUNK_CLEAR
        d = np.where(P[:, 1] <= top + 1.0, d, 1e9)
        return np.minimum(out, d)

    # -- bark --
    def add_tube(self, C, radii, sides, start_normal=None, cap=True, v_tile=6.0):
        C = np.asarray(C, float)
        radii = np.asarray(radii, float)
        u_rep = max(1, int(round(2 * math.pi * float(radii.max()) / 5.0)))
        V, F, UV, N = tg.tube(C, lambda i, ang: np.full(len(ang), radii[i]), sides, u_rep, v_tile, start_normal,
                              cap_end=cap)
        self.bark.add(V, F, UV, N)

    def build_trunk(self):
        P = self.trunk_line()
        H = self.H
        S = self.S
        top = P[-1]
        # the leader: a pine's spire straight on to the top, a broadleaf's into the crown
        if S["style"] == "pine":
            self.leader_dir = tg.norm(np.array([top[0] * -0.02, 1.0, top[2] * -0.02]))
            lead_h = H - top[1]
        else:
            self.leader_dir = tg.norm(tg.norm(P[-1] - P[-8]) + Y * 0.6)
            lead_h = max(H * 0.86 - top[1], 4.0)
        # rings: under the ground, along the route every ~3 studs (tighter low down), the leader
        idx = tg.adaptive_s(P, tol=0.15, max_step=3.0)
        Q = tg.at_s(P, self.trunkS, idx)
        t = idx / self.trunkL
        r = self.r_at(t)
        below = [np.array([P[0][0], -3.0, P[0][2]]), np.array([P[0][0], -1.0, P[0][2]])]
        rb = [float(r[0]) * 1.22, float(r[0]) * 1.08]
        nl = max(2, int(math.ceil(lead_h / 4.0)))
        lead = [top + self.leader_dir * lead_h * (k / nl) for k in range(1, nl + 1)]
        r1 = float(r[-1])
        tip = 0.12 if S["style"] == "pine" else 0.35 * r1
        rl = [r1 + (tip - r1) * (k / nl) for k in range(1, nl + 1)]
        C = np.array(below + list(Q) + lead)
        R = np.array(rb + list(r) + rl)
        self.add_tube(C, R, S["sides"], start_normal=np.array([1.0, 0, 0]), cap=True, v_tile=8.0)
        self.leaderTop = C[-1]
        self.log["trunk"] = {"routeHeight": round(float(top[1]), 2), "modelHeight": round(float(C[-1][1]), 2),
                             "radiusFoot": round(float(r[0]), 3), "radiusTop": round(r1, 3)}

    def build_boughs(self):
        """Each bough route: a tube hung under its feet line; past its end, the bough tapers on as a twig."""
        S = self.S
        self.bough_tips = []
        for b in self.boughs:
            pts = np.asarray(b["points"], float)
            P = tg.Curve(pts).dense(0.5)
            s = tg.arclen(P)
            L = s[-1]
            lift = b.get("visualOffset") or 1.25
            idx = tg.adaptive_s(P, tol=0.08, max_step=2.5, upright=True)
            Q = tg.at_s(P, s, idx)
            u = idx / L
            y0 = Q[0][1]
            base = min(S["boughR"][0], 0.85 * float(self.r_at((y0 - self.trunkP[0][1]) / max(self.trunkP[-1][1] - self.trunkP[0][1], 1))))
            base = min(base, lift * 0.95) if S["style"] == "pine" else base
            tipR = S["boughR"][1]
            rb = base + (tipR - base) * u
            T, _, _ = tg.frames(Q)
            ups = np.array([tg.perp_up(T[i]) for i in range(len(Q))])
            feet = Q + Y * lift
            C = feet - ups * rb[:, None]
            # past the end: two more rings, thinner, a little up
            d = tg.norm(Q[-1] - Q[-2])
            ext = max(2.0, 0.18 * L)
            e1 = C[-1] + tg.norm(d + Y * 0.15) * ext * 0.5
            e2 = C[-1] + tg.norm(d + Y * 0.25) * ext
            C = np.concatenate([C, [e1, e2]])
            R = np.concatenate([rb, [tipR * 0.7, tipR * 0.35]])
            self.add_tube(C, R, 6 if S["style"] != "pine" else 5, start_normal=ups[0], cap=True)
            self.bough_tips.append((e2, tg.norm(e2 - e1), L, b))
            b["_feet"] = feet
            b["_Q"] = Q
            b["_r"] = rb

    # -- side wood (not walked on) --
    def grow(self, origin, d, length, r0, nodes, kink, up):
        """A branch as nodes: kinks and turns up (or droops), stops before a tunnel. Returns points, radii."""
        pts = [np.asarray(origin, float)]
        dd = tg.norm(d)
        seg = length / nodes
        for i in range(nodes):
            dd = tg.norm(dd + self.rng.normal(0, kink, 3) * np.array([1, 0.5, 1]) + Y * up)
            q = pts[-1] + dd * seg
            if i >= 1 and self.clearance([q])[0] < 0.25:
                break
            pts.append(q)
        if len(pts) < 2:
            return None, None
        f = np.linspace(0, 1, len(pts))
        radii = r0 * (1 - 0.75 * f) + 0.04
        return np.array(pts), radii

    def wood(self, pts, radii, sides=4):
        if pts is not None and len(pts) >= 2:
            self.add_tube(pts, radii, sides, cap=True, v_tile=4.0)

    # -- leaves --
    def card(self, base, d, up, length, width):
        """A flat two-faced spray card from `base` along d, facing `up`, mapped to one of the atlas's four sprays."""
        if self.cards >= self.max_cards:
            return False
        d = tg.norm(d - up * np.dot(d, up))
        side = tg.norm(np.cross(d, up))
        tip = base + d * length
        mid = base + d * (length * 0.5)
        # nothing of it in a tunnel
        h = side * width * 0.5
        cl = self.clearance(np.array([base, mid, tip, base + h, base - h, tip + h, tip - h, mid + h, mid - h]))
        if cl.min() < 0.1:
            return False
        v = int(self.rng.integers(0, 4))
        u0, v0 = (v % 2) * 0.5, (v // 2) * 0.5
        V = np.array([base - side * width / 2, base + side * width / 2, tip + side * width / 2, tip - side * width / 2])
        UV = np.array([[u0 + 0.02, v0 + 0.01], [u0 + 0.48, v0 + 0.01], [u0 + 0.48, v0 + 0.49], [u0 + 0.02, v0 + 0.49]])
        n = np.cross(V[1] - V[0], V[3] - V[0])
        n = tg.norm(n)
        F = np.array([[0, 1, 2], [0, 2, 3]])
        self.leaf.add(V, F, UV, np.repeat(n[None], 4, 0))
        self.leaf.add(V, F[:, ::-1], UV, np.repeat(-n[None], 4, 0))
        self.cards += 1
        self.fruit_spots.append(base + d * length * 0.35 - up * 0.6)
        return True

    # -- the crown, by style --
    def broad_crown(self):
        S, rng = self.S, self.rng
        H, crown = self.H, self.crown
        cl, cw = S["card"]
        ylo = min([float(b["_Q"][0][1]) for b in self.boughs] + [self.trunkP[-1][1]])
        self.env_c = np.array([0.0, (ylo + H) / 2 + 0.05 * H, 0.0])
        self.env_r = np.array([crown, max((H - ylo) / 2, 6.0), crown])

        def inside(p, slack=1.0):
            q = (p - self.env_c) / self.env_r
            return float((q * q).sum()) <= slack

        twigs = []
        # side branches off every bough's outer two thirds, both sides, and the bough's tip twigs
        for b in self.boughs:
            Q, rb = b["_Q"], b["_r"]
            n = len(Q)
            L = tg.arclen(Q)[-1]
            step = max(3.0, L / 6)
            s = L * 0.3
            side = 1
            sQ = tg.arclen(Q)
            while s < L:
                p = tg.at_s(Q, sQ, np.array([s]))[0]
                i = int(np.searchsorted(sQ, s).clip(1, n - 1))
                t = tg.norm(Q[i] - Q[i - 1])
                r = float(rb[i])
                lat = tg.norm(np.cross(t, Y)) * side
                start = p + lat * r * 0.8 - Y * r * 0.5
                d = tg.norm(t * 0.5 + lat * 0.8 + Y * rng.uniform(0.0, 0.5))
                ln = (L - s) * 0.45 + crown * 0.25
                pts, radii = self.grow(start, d, ln, max(0.2, r * 0.45), 3, 0.18, 0.12)
                if pts is not None:
                    self.wood(pts, radii)
                    twigs.append((pts, 1))
                side = -side
                s += step * rng.uniform(0.8, 1.2)
        for tip, d, L, b in self.bough_tips:
            for k in range(2):
                a = (1 if k == 0 else -1) * rng.uniform(0.4, 0.8)
                dd = tg.norm(rot_y(d, a) + Y * 0.3)
                pts, radii = self.grow(tip, dd, crown * 0.3, S["boughR"][1] * 0.6, 3, 0.2, 0.1)
                if pts is not None:
                    self.wood(pts, radii)
                    twigs.append((pts, 1))
        # crown limbs off the leader, filling the top of the envelope
        LT = self.leaderTop
        top = self.trunkP[-1]
        nlim = 8 if self.kind["family"] == "giant" else 5
        a0 = rng.uniform(0, 6.28)
        for q in range(nlim):
            f = (q + 0.5) / nlim
            p = top + (LT - top) * (0.15 + 0.7 * f)
            az = a0 + q * 2.39996
            elev = math.radians(rng.uniform(25, 55) + 20 * f)
            d = dir_of(az, elev)
            ln = crown * (0.75 - 0.35 * f) * rng.uniform(0.85, 1.1)
            r0 = max(0.25, float(self.r_at(1.0)) * (0.55 - 0.2 * f))
            pts, radii = self.grow(p, d, ln, r0, 4, 0.15, 0.06)
            if pts is not None:
                self.wood(pts, radii, 5)
                twigs.append((pts, 1))
                # side twigs off the crown limbs
                for i in range(1, len(pts) - 1):
                    dd = tg.norm(rot_y(d, rng.choice([-1, 1]) * rng.uniform(0.6, 1.2)) + Y * 0.2)
                    p2, r2 = self.grow(pts[i], dd, ln * 0.4, float(radii[i]) * 0.5, 2, 0.2, 0.1)
                    if p2 is not None:
                        self.wood(p2, r2, 3)
                        twigs.append((p2, 2))
        # second-order twigs off the side branches
        more = []
        for pts, lv in twigs:
            if lv == 1:
                for i in range(1, len(pts)):
                    d = tg.norm(pts[i] - pts[i - 1])
                    dd = tg.norm(rot_y(d, rng.choice([-1, 1]) * rng.uniform(0.5, 1.0)) + Y * 0.25)
                    p2, r2 = self.grow(pts[i], dd, crown * 0.22, 0.12, 2, 0.25, 0.1)
                    if p2 is not None:
                        if self.bark.tris < S["bark_tris"] - 400:
                            self.wood(p2, r2, 3)
                        more.append((p2, 2))
        twigs += more
        # sprays: along every twig and at its tip, facing out of the crown, inside the envelope
        spots = []
        for pts, lv in twigs:
            for i in range(1, len(pts)):
                spots.append((pts[i], tg.norm(pts[i] - pts[i - 1])))
        rng.shuffle(spots)
        # fill evenly: two passes, the second fills what the first left
        for pass_ in range(3):
            for p, d in spots:
                if self.cards >= self.max_cards:
                    break
                if not inside(p, 1.15):
                    continue
                out = tg.norm(p - self.env_c + Y * 2.0)
                for _ in range(1 if pass_ else 2):
                    az = rng.uniform(-1.2, 1.2)
                    dd = tg.norm(rot_y(d, az) + Y * rng.uniform(-0.1, 0.5))
                    up = tg.norm(out * 0.6 + Y * 0.8 + rng.normal(0, 0.25, 3))
                    s = rng.uniform(0.75, 1.15)
                    base = p + rng.normal(0, 0.6, 3)
                    self.card(base, dd, up, cl * s, cw * s)

    def shrub_crown(self):
        """The hazel: the main stem (its climbing trunk) and a clump of stems from the stool."""
        S, rng = self.S, self.rng
        H = self.H
        base = self.trunkP[0]
        stems = []
        for q in range(5):
            az = q * 2.39996 + rng.uniform(-0.3, 0.3)
            d = dir_of(az, math.radians(rng.uniform(62, 76)))
            ln = H * rng.uniform(0.7, 0.95)
            start = base + np.array([math.sin(az), 0, math.cos(az)]) * 0.9 + Y * 0.1
            pts, radii = self.grow(start, d, ln, 0.45, 5, 0.08, 0.04)
            if pts is not None:
                self.wood(pts, radii, 5)
                stems.append(pts)
        top = self.leaderTop
        stems.append(np.array([self.trunkP[len(self.trunkP) // 2], self.trunkP[-1], top]))
        self.env_c = np.array([0.0, H * 0.6, 0.0])
        self.env_r = np.array([self.crown, H * 0.45, self.crown])
        cl, cw = S["card"]
        for _ in range(4):
            for pts in stems:
                for i in range(1, len(pts)):
                    for f in (0.0, 0.5):
                        p = pts[i - 1] + (pts[i] - pts[i - 1]) * (0.5 + f)
                        if p[1] < 3.0:
                            continue
                        d = tg.norm(pts[i] - pts[i - 1])
                        for _k in range(3):
                            dd = tg.norm(rot_y(np.array([d[0], 0.3, d[2]]) + rng.normal(0, 0.4, 3), rng.uniform(-3, 3)))
                            up = tg.norm(Y + rng.normal(0, 0.35, 3))
                            self.card(p + rng.normal(0, 1.0, 3), dd, up, cl * rng.uniform(0.8, 1.2), cw)
        for b in self.boughs:
            Q = b["_Q"]
            for i in range(1, len(Q)):
                d = tg.norm(Q[i] - Q[i - 1])
                for side in (-1, 1):
                    lat = tg.norm(np.cross(d, Y)) * side
                    self.card(Q[i] + lat * 1.8 - Y * 0.4, tg.norm(lat + d * 0.3), Y, cl, cw)

    def pine_crown(self):
        S, rng = self.S, self.rng
        H, crown = self.H, self.crown
        cl, cw = S["card"]
        y0 = max(4.0, S["base"] * H)
        dy = S["whorl"]
        k = 0
        y = y0
        branches = []
        self.whorl_heights = []
        while y < H - 2.0:
            rel = (y - y0) / max(H - y0, 1)
            if S["shape"] == "cone":
                f = (1 - rel) ** 0.9
            elif S["shape"] == "spire":
                f = (1 - rel) ** 1.05
            elif S["shape"] == "tiers":
                f = (1 - rel) ** 0.65 * (0.72 + 0.28 * math.sin(k * 2.1) ** 2)
            else:  # round: a crown high on the trunk, widest a third of the way up it
                f = max(0.15, math.sin(math.pi * min(1.0, 0.25 + rel * 0.85)))
            ln = max(1.5, crown * f * rng.uniform(0.85, 1.1))
            ax = self.axis_at_y(y)
            tr = float(self.r_at(min(1.0, (y - self.trunkP[0][1]) / max(self.trunkP[-1][1] - self.trunkP[0][1], 1)))) if y < self.trunkP[-1][1] else 0.3
            for q in range(S["per"]):
                az = k * 2.39996 + q * 2 * math.pi / S["per"] + rng.uniform(-0.25, 0.25)
                d = dir_of(az, S["tilt"] + rng.uniform(-0.06, 0.06))
                start = ax + np.array([math.sin(az), 0, math.cos(az)]) * tr * 0.7
                pts, radii = self.grow(start, d, ln, max(0.14, 0.05 * ln + 0.1), 3, 0.06, -0.06 if S["tilt"] < 0 else 0.02)
                if pts is not None:
                    branches.append((pts, ln, y))
                    self.whorl_heights.append(y)
            k += 1
            y += dy * rng.uniform(0.85, 1.15) * (0.85 if rel > 0.6 else 1.0)
        # the wood: the longer branches drawn, every branch carries needles
        branches.sort(key=lambda b: -b[1])
        for pts, ln, yb in branches:
            if self.bark.tris < S["bark_tris"] - 300 and ln > 2.5:
                radii = np.linspace(max(0.14, 0.05 * ln + 0.1), 0.05, len(pts))
                self.wood(pts, radii, 3)
        # rungs carry needles too, kept off their tunnels by the card test
        for b in self.boughs:
            Q = b["_Q"]
            branches.append((Q, float(tg.arclen(Q)[-1]), float(Q[0][1])))
        rng.shuffle(branches)
        for pass_ in range(4):
            for pts, ln, yb in branches:
                if self.cards >= self.max_cards:
                    break
                P = pts
                sP = tg.arclen(P)
                L = sP[-1]
                n = max(1, int(L / (cl * 0.55)))
                for j in range(n):
                    if pass_ >= 2 and rng.random() < 0.5:
                        continue
                    s = L * (0.25 + 0.75 * (j + rng.uniform(0.2, 0.8)) / n)
                    p = tg.at_s(P, sP, np.array([min(s, L)]))[0]
                    d = tg.norm(P[-1] - P[0])
                    for side in (-1, 1):
                        a = side * rng.uniform(0.35, 0.9)
                        dd = tg.norm(rot_y(d, a) + Y * (S["tilt"] * 0.6 + rng.uniform(-0.1, 0.1)))
                        up = tg.norm(Y + rng.normal(0, 0.2, 3))
                        sc = rng.uniform(0.8, 1.15) * (0.75 + 0.25 * min(1.0, ln / 8))
                        self.card(p + Y * rng.uniform(-0.3, 0.3), dd, up, cl * sc, cw * sc)
        # a tuft at the spire
        for q in range(6):
            az = q * 1.05
            self.card(self.leaderTop - Y * 1.5, dir_of(az, 0.9), tg.norm(dir_of(az, -0.4) + Y), cl * 0.8, cw * 0.8)

    # -- fruit --
    def build_fruit(self, swatch):
        fr = self.S.get("fruit")
        if not fr:
            return 0
        ca, cb, ln, wd, n = FRUIT[fr]
        rng = self.rng
        spots = list(self.fruit_spots)
        rng.shuffle(spots)
        u0, v0, u1, v1 = swatch
        um = (u0 + u1) / 2
        put = 0
        cone = fr.endswith("cone")
        for p in spots:
            if put >= n:
                break
            if self.clearance([p])[0] < 0.25 + max(ln, wd) or p[1] < 6.0:
                continue
            # a bipyramid: six sides round the middle, a point at each end
            k = 6
            axis = tg.norm(np.array([0, -1.0, 0]) + rng.normal(0, 0.25, 3)) if fr != "fircone" else Y
            if fr == "fircone":
                p = p + Y * 1.2
            side = tg.norm(np.cross(axis, [0.3, 0.2, 0.9]))
            side2 = np.cross(axis, side)
            half = ln / 2
            ring = [p + (side * math.cos(a) + side2 * math.sin(a)) * wd / 2 for a in np.linspace(0, 2 * math.pi, k, endpoint=False)]
            top = p - axis * half  # (the stalk end: the cap or husk colour)
            bot = p + axis * half * (1.2 if cone else 1.0)
            V = np.array([top, bot] + ring)
            F = []
            for j in range(k):
                a, b = 2 + j, 2 + (j + 1) % k
                F.append((0, b, a))
                F.append((1, a, b))
            F = np.array(F, np.int64)
            UV = np.zeros((len(V), 2))
            UV[0] = [(um + u1) / 2, (v0 + v1) / 2]
            UV[1] = [(u0 + um) / 2, (v0 + v1) / 2]
            UV[2:] = [(u0 + um) / 2, (v0 + v1) / 2]
            N = tg.norm(V - p[None])
            self.leaf.add(V, F, UV, N)
            put += 1
        return put

    def build(self, swatch):
        S = self.S
        self.max_cards = S["leaf_tris"] // 4 - FRUIT.get(S.get("fruit") or "", (0, 0, 0, 0, 0))[4] * 3
        self.trunk_line()
        self.add_tunnels()
        self.build_trunk()
        self.build_boughs()
        if S["style"] == "pine":
            self.pine_crown()
        elif S["style"] == "shrub":
            self.shrub_crown()
        else:
            self.broad_crown()
        self.log["fruit"] = self.build_fruit(swatch)
        self.log["cards"] = self.cards
        return self


# ---- checks ---------------------------------------------------------------------------------------

def bvh_of(mesh):
    V, F, _, _ = mesh.arrays()
    Vb = tg.to_blender_coords(V)
    return BVHTree.FromPolygons([Vector(v) for v in Vb], [tuple(int(i) for i in f) for f in F])


def to_b(p):
    return Vector((-p[0], p[2], p[1]))


def checks(tree):
    """The promises, measured on the finished bark (as check_promises.py measures the town trees'):
    trunk   rays level from the route's axis in 8 directions at every sample: the first bark met minus the squirrel's
            radius (the stretches where a bough or a whorl branch leaves are reported apart);
    feet    on every bough past its first fifth: the bark under the feet (a ray down from 0.5 over them) and over them
            (a ray up from the feet: nothing of the bark within 2 studs);
    leaves  the least clearance of any leaf or fruit vertex to the walks' tunnels and the trunk's column."""
    bvh = bvh_of(tree.bark)
    P = tree.trunkP
    t = tree.trunkS / tree.trunkL
    starts = [float(b["_Q"][0][1]) for b in tree.boughs] + list(getattr(tree, "whorl_heights", []))
    clean, near = [], []
    for p, tt in zip(P[::2], t[::2]):
        want = float(tree.r_at(tt))
        for k in range(8):
            a = k * math.pi / 4
            d = np.array([math.cos(a), 0, math.sin(a)])
            hit = bvh.ray_cast(to_b(p), Vector((-d[0], d[2], d[1])), want + 6.0)
            if hit[0] is None:
                continue
            err = hit[3] - want
            (near if any(abs(p[1] - y) < 4.0 for y in starts) else clean).append(err)
    under, over, n = [], 0, 0
    for b in tree.boughs:
        feet = b["_feet"]
        s = tg.arclen(feet)
        for q, sq in zip(feet, s):
            if sq < 0.2 * s[-1]:
                continue
            n += 1
            hit = bvh.ray_cast(to_b(q + Y * 0.5), Vector((0, 0, -1)), 2.0)
            if hit[0] is not None:
                under.append(hit[3] - 0.5)
            up = bvh.ray_cast(to_b(q + Y * 0.04), Vector((0, 0, 1)), 2.0)
            if up[0] is not None:
                over += 1
    LV = tree.leaf.arrays()[0]
    lm = float(tree.clearance(LV).min()) if len(LV) else None
    st = bt.stats
    return {"trunk_bark_minus_radius_st": st(clean), "trunk_near_boughs": st(near),
            "feet_to_bark_under_st": st(under), "feet_samples": n, "feet_with_bark_over": over,
            "leaf_min_clearance_st": None if lm is None else round(lm, 3)}


# ---- scene, export, render ------------------------------------------------------------------------

def bounds(obj):
    return bt.bounds_roblox(obj)


def build_kind(kind, tex, args):
    t0 = time.time()
    sp = kind["species"]
    leaf_maps, swatch = tex.leaves(sp)
    tree = Tree(kind, {}).build(swatch)
    mats = {"Bark": bt.make_material(f"Bark_{kind['id']}", tex.bark(sp), 1.0),
            "Leaves": bt.make_material(f"Leaves_{kind['id']}", leaf_maps, 0.8, alpha=True)}
    objs = {"Bark": tg.make_object("Bark", tree.bark, mats["Bark"]),
            "Leaves": tg.make_object("Leaves", tree.leaf, mats["Leaves"])}
    tree.log["build_s"] = round(time.time() - t0, 2)
    return tree, objs, mats


def render(kind, tree, objs, view, out, args, offset=None):
    H, crown = kind["height"], kind["crown"]
    if view == "street":
        dist = max(1.45 * H, 3.4 * crown)
        loc = np.array([dist * 0.62, H * 0.28 + 4, -dist * 0.78])
        tgt = np.array([0, H * 0.48, 0])
        lens = 24
    else:  # climb: the lowest bough from beside the trunk, a squirrel-sized marker on it
        b = tree.boughs[0]
        Q = b["_feet"]
        mid = Q[len(Q) // 2]
        loc = mid + np.array([9.0, 3.5, -12.0])
        tgt = mid + np.array([-1.0, 0.5, 0.0])
        lens = 28
    cam = bt.add_camera("Cam" + view, to_b(loc), to_b(tgt), lens)
    bpy.context.scene.camera = cam
    path = os.path.join(out, "renders", f"{kind['id']}_{view}.png")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return path


def squirrel_marker(tree):
    """An orange body 1.7 studs long on the lowest bough's feet line (the squirrel's size, for the renders)."""
    b = tree.boughs[0]
    Q = b["_feet"]
    p = Q[len(Q) // 2]
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.45, location=to_b(p + Y * 0.45))
    o = bpy.context.active_object
    o.scale = (1.9, 1.0, 1.0)
    d = tg.norm(Q[-1] - Q[0])
    o.rotation_euler = (0, 0, math.atan2(d[2], -d[0]))
    m = bpy.data.materials.new("Squirrel")
    m.use_nodes = True
    m.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value = (0.75, 0.32, 0.08, 1)
    o.data.materials.append(m)
    return o


def mesh_digest(objs, mats):
    return bt.mesh_digest(objs, mats)


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--kinds", default="all")
    ap.add_argument("--templates", default="build/woods/templates.json")
    ap.add_argument("--out", default="build/art/woods")
    ap.add_argument("--fbx", action="store_true")
    ap.add_argument("--render", default="")
    ap.add_argument("--lineup", action="store_true")
    ap.add_argument("--samples", type=int, default=40)
    ap.add_argument("--threads", type=int, default=2)
    ap.add_argument("--res", default="960x540")
    args = ap.parse_args(argv)
    out = os.path.abspath(args.out)
    os.makedirs(out, exist_ok=True)
    with open(args.templates) as fh:
        kinds = json.load(fh)["kinds"]
    if args.kinds != "all":
        want = set(args.kinds.split(","))
        kinds = [k for k in kinds if k["id"] in want]
    tex = Tex(out)
    views = [v for v in args.render.split(",") if v]
    summary = []
    for kind in kinds:
        bt.reset_scene()
        tree, objs, mats = build_kind(kind, tex, args)
        tris = {"bark": tree.bark.tris, "leaves": tree.leaf.tris}
        tris["total"] = tris["bark"] + tris["leaves"]
        parts = {k: bounds(o) for k, o in objs.items()}
        parts["Bark"].update({"doubleSided": False, "alphaMode": "Overlay"})
        mean = tex.leaf_mean(kind["species"])
        parts["Leaves"].update({"doubleSided": False, "alphaMode": "Transparency",
                                "color": [int(round(float(x) * 255)) for x in mean]})
        info = {"kind": kind["id"], "label": kind["label"], "species": kind["species"], "family": kind["family"],
                "pivot": [0, 0, 0],
                "heightStuds": round(max(p["center"][1] + p["size"][1] / 2 for p in parts.values()), 2), "crownStuds": kind["crown"],
                "tris": tris, "parts": parts, "log": tree.log, "checks": checks(tree), "sha": mesh_digest(objs, mats)}
        lv = parts["Leaves"]
        info["crownMeasured"] = round(max(abs(lv["center"][0]) + lv["size"][0] / 2, abs(lv["center"][2]) + lv["size"][2] / 2), 2)
        if views:
            bt.setup_render(args)
            for v in views:
                if v == "climb":
                    mk = squirrel_marker(tree)
                info.setdefault("renders", {})[v] = render(kind, tree, objs, v, out, args)
                if v == "climb":
                    bpy.data.objects.remove(mk, do_unlink=True)
        if args.fbx:
            p = os.path.join(out, f"{kind['id']}.fbx")
            bt.export_fbx(p, objs)
            info["fbx"] = p
            info["fbxBytes"] = os.path.getsize(p)
        with open(os.path.join(out, f"{kind['id']}.json"), "w") as fh:
            json.dump(info, fh, indent=1)
        c = info["checks"]
        print(json.dumps({"kind": kind["id"], "tris": tris, "h": info["heightStuds"], "crown": info["crownMeasured"],
                          "trunk": c["trunk_bark_minus_radius_st"].get("max_abs"),
                          "feet": c["feet_to_bark_under_st"].get("max_abs"), "over": c["feet_with_bark_over"],
                          "leafClear": c["leaf_min_clearance_st"], "cards": tree.cards, "fruit": tree.log["fruit"],
                          "s": tree.log["build_s"]}), flush=True)
        summary.append(info)
    if args.lineup:
        lineup(kinds, tex, out, args)
    with open(os.path.join(out, "summary.json"), "w") as fh:
        json.dump(summary, fh, indent=1)


def lineup(kinds, tex, out, args):
    """Every kind in a row (giants at the back), with a pole as tall as the town's tallest tree today (175 studs)."""
    bt.reset_scene()
    x = 0.0
    order = sorted(kinds, key=lambda k: (k["family"] == "giant", k["height"]))
    front, back = [k for k in order if k["family"] != "giant"], [k for k in order if k["family"] == "giant"]
    placed = []
    for row, ks, z in ((0, front, 0.0), (1, back, 140.0)):
        x = 0.0
        for k in ks:
            x += k["crown"] * (0.9 if row == 0 else 1.0)
            tree, objs, _ = build_kind(k, tex, args)
            for o in objs.values():
                o.location = to_b(np.array([-x, 0, z]))
            placed.append((k, x, z))
            x += k["crown"] * (0.9 if row == 0 else 1.0) + 4
    width = max(p[1] for p in placed) + 40
    # the pole: 175 studs, the HIGHLAND ELM today
    bpy.ops.mesh.primitive_cylinder_add(radius=1.2, depth=175, location=to_b(np.array([-width + 10, 87.5, 140.0])))
    pole = bpy.context.active_object
    m = bpy.data.materials.new("Pole")
    m.use_nodes = True
    m.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value = (0.8, 0.15, 0.1, 1)
    pole.data.materials.append(m)
    bt.setup_render(args)
    rx, ry = (int(v) for v in args.res.split("x"))
    bpy.context.scene.render.resolution_x, bpy.context.scene.render.resolution_y = rx * 2, ry * 2
    cx = -width / 2
    cam = bt.add_camera("CamLineup", to_b(np.array([cx, 95, -width * 0.62])), to_b(np.array([cx, 85, 70])), 30)
    bpy.context.scene.camera = cam
    path = os.path.join(out, "renders", "lineup.png")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print(f"lineup -> {path}", flush=True)


if __name__ == "__main__":
    main(sys.argv[1:] if "--" not in sys.argv else sys.argv[sys.argv.index("--") + 1 :])
