"""Judge the canopy without the generator: a synthetic skeleton per species (a trunk, a leader,
five boughs, a few dozen twig tips), canopy.build_canopy on it, and two Cycles pictures: from the
street, and from inside the crown at a squirrel's height on a bough (a rust-coloured stand-in
squirrel sits further along the bough, inside its clear tunnel).

  PY=/root/.cache/spicy-rodents/venv/bin/python
  nice -n 10 $PY -I tools/blender/trees/canopy_demo.py --species oak,elm --out build/art/trees/canopy_demo
  ... --stats        only build and print the triangle counts and the tunnel clearance (no bpy)

Writes canopy_<species>_street.png and canopy_<species>_inside.png into --out. The materials are
the review materials of build_trees.py (colour + a flat ambient term, the atlas alpha cuts the cards).
"""
import argparse
import json
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import canopy  # noqa: E402

Y = np.array([0.0, 1.0, 0.0])
AMBIENT = 0.28
LIFT = 0.9  # the squirrel's body above the top of the bark
TUNNEL = 2.6


def _norm(v):
    v = np.asarray(v, float)
    return v / max(np.linalg.norm(v), 1e-9)


def skeleton(species, seed=3):
    """-> limbs [(polyline, r0, r1)], boughs [polyline], tips [(pos, dir, thickness)], small branches."""
    rng = np.random.default_rng(seed)
    oak = species == "oak"
    H0 = 24.0 if oak else 28.0  # the fork
    trunk = np.array([[0, 0, 0], [0.3, H0 * 0.5, 0.2], [0, H0, 0]], float)
    limbs = [(trunk, 2.6, 2.0)]
    boughs, tips, small = [], [], []

    def curve(p0, d0, length, n, up, sag_end=0.0, kink=0.06):
        pts, d, p = [p0], _norm(d0), np.array(p0, float)
        for i in range(n):
            t = (i + 1) / n
            d = _norm(d + Y * (up * (1 - t) - sag_end * t * t) + rng.normal(0, kink, 3))
            p = p + d * length / n
            pts.append(p)
        return np.array(pts)

    def twigs_on(P, r, first=0.35, count=6, length=(8.0, 12.0)):
        seg = np.linalg.norm(np.diff(P, axis=0), axis=1)
        s = np.concatenate([[0.0], np.cumsum(seg)])
        sgn = 1
        for f in np.linspace(first, 0.93, count):
            p = np.array([np.interp(f * s[-1], s, P[:, k]) for k in range(3)])
            j = min(int(np.searchsorted(s, f * s[-1])), len(P) - 1)
            t = _norm(P[j] - P[j - 1])
            sv = _norm(np.cross(t, Y))
            d = _norm(t * (0.75 if not oak else 0.5) + sv * sgn * 0.8 + Y * rng.uniform(0.0, 0.5))
            b = curve(p, d, rng.uniform(*length) * (1.1 - 0.4 * f), 4, 0.14 if oak else 0.02, 0.0 if oak else 0.10, 0.12)
            small.append(b)
            limbs.append((b, 0.42 * r, 0.12))
            tips.append((b[-1], b[-1] - b[-2], 0.12))
            sgn = -sgn
        tips.append((P[-1], P[-1] - P[-2], 0.2))

    for k in range(5):
        az = 2 * math.pi * k / 5 + rng.normal(0, 0.15)
        h = np.array([math.cos(az), 0.0, math.sin(az)])
        p0 = np.array([0, H0 - 2.5 + 1.6 * (k % 3), 0]) + h * 1.0
        if oak:  # broad: the boughs leave low and wide and turn up at the ends
            P = curve(p0, h * 1.0 + Y * 0.30, rng.uniform(27, 32), 9, 0.03, -0.05)
        else:  # vase: they rise steeply, arch over and hang at the tips
            P = curve(p0, h * 0.42 + Y * 1.0, rng.uniform(36, 41), 10, -0.05, 0.16)
            P = P + h[None] * np.linspace(0, 1, len(P))[:, None] ** 2 * 6.0
        boughs.append(P)
        limbs.append((P, 1.35, 0.5))
        twigs_on(P, 0.9)
    # the leader above the fork
    L = curve(trunk[-1], Y + rng.normal(0, 0.1, 3), 22.0 if oak else 24.0, 6, 0.25)
    limbs.append((L, 1.9, 0.4))
    twigs_on(L, 0.9, first=0.25, count=7, length=(10.0, 15.0))
    return {"limbs": limbs, "boughs": boughs, "tips": tips, "small": small, "trunk": trunk}


def routes_of(sk):
    """The squirrel's body line on each bough (bark top + LIFT) and round the trunk."""
    routes = []
    for P in sk["boughs"]:
        r = np.linspace(1.35, 0.5, len(P))
        routes.append((P + Y[None] * (r + LIFT)[:, None], TUNNEL))
    routes.append((sk["trunk"], 2.6 + 3.3))
    return routes


def build(species, budget, seed=3):
    sk = skeleton(species, seed)
    res = canopy.build_canopy(sk["tips"], sk["small"], species, budget=budget, routes=routes_of(sk), seed=seed, floor_y=8.0)
    return sk, res


# ---- Blender ----------------------------------------------------------------------------------------

def to_b(p):
    return (-float(p[0]), float(p[2]), float(p[1]))


def tube_mesh(P, r0, r1, sides=8):
    P = np.asarray(P, float)
    n = len(P)
    V, F = [], []
    T = np.gradient(P, axis=0)
    for i in range(n):
        t = _norm(T[i])
        a = _norm(np.cross(t, [0.31, 0.12, 0.94]))
        b = np.cross(t, a)
        r = r0 + (r1 - r0) * i / (n - 1)
        for j in range(sides):
            ang = 2 * math.pi * j / sides
            V.append(P[i] + (a * math.cos(ang) + b * math.sin(ang)) * r)
    for i in range(n - 1):
        for j in range(sides):
            a_, b_ = i * sides + j, i * sides + (j + 1) % sides
            F.append((a_, b_, b_ + sides, a_ + sides))
    return V, F


def render(species, sk, res, tex, out, args):
    import bpy
    from mathutils import Vector

    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = args.samples
    scene.cycles.use_adaptive_sampling = True
    scene.cycles.adaptive_threshold = 0.04
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 5
    scene.cycles.diffuse_bounces = 2
    scene.cycles.transparent_max_bounces = 40
    scene.render.threads_mode = "FIXED"
    scene.render.threads = args.threads
    scene.render.resolution_x, scene.render.resolution_y = (int(v) for v in args.res.split("x"))
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "AgX"
    try:
        scene.view_settings.look = "AgX - Medium High Contrast"
    except TypeError:
        pass
    world = bpy.data.worlds.new("Sky")
    scene.world = world
    world.use_nodes = True
    nt = world.node_tree
    bg = nt.nodes.get("Background")
    sky = nt.nodes.new("ShaderNodeTexSky")
    sun_el, sun_az = math.radians(42), math.radians(215)
    for attr, val in (("sun_elevation", sun_el), ("sun_rotation", sun_az), ("sun_disc", False)):
        try:
            setattr(sky, attr, val)
        except Exception:
            pass
    nt.links.new(sky.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = 0.32
    sd = bpy.data.lights.new("Sun", "SUN")
    sd.energy, sd.angle, sd.color = 4.2, math.radians(2.5), (1.0, 0.93, 0.80)
    so = bpy.data.objects.new("Sun", sd)
    scene.collection.objects.link(so)
    d = Vector((math.cos(sun_el) * math.sin(sun_az), -math.cos(sun_el) * math.cos(sun_az), math.sin(sun_el)))
    so.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()

    def flat_mat(name, rgb, rough=0.9):
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        b = m.node_tree.nodes.get("Principled BSDF")
        b.inputs["Base Color"].default_value = (*rgb, 1)
        b.inputs["Emission Color"].default_value = (*rgb, 1)
        b.inputs["Emission Strength"].default_value = AMBIENT
        b.inputs["Roughness"].default_value = rough
        return m

    bpy.ops.mesh.primitive_plane_add(size=900, location=(0, 0, 0))
    bpy.context.active_object.data.materials.append(flat_mat("Grass", (0.22, 0.31, 0.10)))
    # bark
    bark = flat_mat("Bark", (0.16, 0.115, 0.08))
    V, F = [], []
    for P, r0, r1 in sk["limbs"]:
        v, f = tube_mesh(P, r0, r1)
        F += [tuple(i + len(V) for i in q) for q in f]
        V += v
    me = bpy.data.meshes.new("Bark")
    me.from_pydata([to_b(p) for p in V], [], F)
    me.polygons.foreach_set("use_smooth", np.ones(len(F), bool))
    me.materials.append(bark)
    scene.collection.objects.link(bpy.data.objects.new("Bark", me))
    # leaves
    for part in canopy.PARTS:
        Vp, Fp, UV, N = res["parts"][part]
        if not len(Fp):
            continue
        mat = bpy.data.materials.new(part)
        mat.use_nodes = True
        nt = mat.node_tree
        b = nt.nodes.get("Principled BSDF")
        tc = nt.nodes.new("ShaderNodeTexImage")
        tc.image = bpy.data.images.load(tex[part])
        tc.image.alpha_mode = "CHANNEL_PACKED"
        nt.links.new(tc.outputs["Color"], b.inputs["Base Color"])
        nt.links.new(tc.outputs["Color"], b.inputs["Emission Color"])
        nt.links.new(tc.outputs["Alpha"], b.inputs["Alpha"])
        b.inputs["Emission Strength"].default_value = AMBIENT
        b.inputs["Roughness"].default_value = 0.6
        b.inputs["Specular IOR Level"].default_value = 0.3
        me = bpy.data.meshes.new(part)
        me.from_pydata([to_b(p) for p in Vp], [], Fp.tolist())
        uv = me.uv_layers.new(name="UVMap")
        uv.data.foreach_set("uv", UV[Fp.ravel()].astype(np.float32).ravel())
        me.polygons.foreach_set("use_smooth", np.ones(len(Fp), bool))
        me.normals_split_custom_set_from_vertices([to_b(n) for n in N])
        me.materials.append(mat)
        scene.collection.objects.link(bpy.data.objects.new(part, me))
    # the stand-in squirrel on the longest bough
    B = max(sk["boughs"], key=lambda P: np.linalg.norm(np.diff(P, axis=0), axis=1).sum())
    seg = np.linalg.norm(np.diff(B, axis=0), axis=1)
    s = np.concatenate([[0.0], np.cumsum(seg)])
    at = lambda f: np.array([np.interp(f * s[-1], s, B[:, k]) for k in range(3)])  # noqa: E731
    rb = lambda f: 1.35 + (0.5 - 1.35) * f  # noqa: E731
    f_sq = 0.62
    t = _norm(at(f_sq + 0.02) - at(f_sq - 0.02))
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=10, radius=1.0, location=to_b(at(f_sq) + Y * (rb(f_sq) + 0.75)))
    sq = bpy.context.active_object
    sq.scale = (1.7, 0.7, 0.75)
    tb_ = Vector(to_b(t))
    sq.rotation_euler = tb_.to_track_quat("X", "Z").to_euler()
    sq.data.materials.append(flat_mat("Squirrel", (0.55, 0.20, 0.07), 0.7))

    def cam(name, loc, tgt, lens):
        cd = bpy.data.cameras.new(name)
        cd.lens, cd.clip_start, cd.clip_end = lens, 0.05, 3000
        co = bpy.data.objects.new(name, cd)
        scene.collection.objects.link(co)
        co.location = to_b(loc)
        co.rotation_euler = (Vector(to_b(tgt)) - Vector(to_b(loc))).to_track_quat("-Z", "Y").to_euler()
        return co

    c = res["stats"]["crown"]
    allv = np.concatenate([res["parts"][p][0] for p in canopy.PARTS if len(res["parts"][p][0])])
    top = float(allv[:, 1].max())
    width = float(np.ptp(allv[:, 0]).max() + np.ptp(allv[:, 2])) / 2 + 10
    dist = max(top * 0.56 / math.tan(math.atan(18 / (16 / 9) / 28)), width * 0.5 / math.tan(math.atan(18 / 28))) + width * 0.3
    ang = math.radians(200)
    views = {
        "street": (np.array([c["centre"][0] - math.sin(ang) * dist, 5.0, c["centre"][2] - math.cos(ang) * dist]),
                   np.array([c["centre"][0], top * 0.5, c["centre"][2]]), 28.0),
    }
    f0 = 0.30
    t0 = _norm(at(f0 + 0.02) - at(f0 - 0.02))
    loc = at(f0) + Y * (rb(f0) + 2.6) - t0 * 1.5 + _norm(np.cross(t0, Y)) * 0.8
    views["inside"] = (loc, at(0.8) + Y * (rb(0.8) + 1.0), 18.0)
    for name in args.views.split(","):
        loc, tgt, lens = views[name]
        scene.camera = cam(name, loc, tgt, lens)
        scene.render.filepath = os.path.join(out, f"canopy_{species}_{name}.png")
        bpy.ops.render.render(write_still=True)
        print("rendered", scene.render.filepath, flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--species", default="oak,elm")
    ap.add_argument("--out", default="build/art/trees/canopy_demo")
    ap.add_argument("--budget", type=int, default=canopy.LEAF_BUDGET)
    ap.add_argument("--views", default="street,inside")
    ap.add_argument("--res", default="960x540")
    ap.add_argument("--samples", type=int, default=32)
    ap.add_argument("--threads", type=int, default=2)
    ap.add_argument("--stats", action="store_true")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    for sp in a.species.split(","):
        sk, res = build(sp, a.budget)
        print(sp, "tips", len(sk["tips"]), json.dumps(res["stats"]), flush=True)
        if a.stats:
            continue
        import canopy_textures as ct

        tex = ct.write_atlases(os.path.join(a.out, "tex"), sp)
        render(sp, sk, res, tex, a.out, a)


if __name__ == "__main__":
    main()
