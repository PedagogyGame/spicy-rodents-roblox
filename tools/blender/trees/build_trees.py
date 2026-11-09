"""Build, check, render and export the 95 route-true trees (headless bpy 5.2.x).

  PY=/root/.cache/spicy-rodents/venv/bin/python
  taskset -c 2,3 $PY -I tools/blender/trees/build_trees.py --ids review --render street,below --out build/art/trees
  taskset -c 2,3 $PY -I tools/blender/trees/build_trees.py --ids all --fbx --out build/art/trees
  taskset -c 2,3 $PY -I tools/blender/trees/build_trees.py --ids 0 --render debug --out build/art/trees

--ids: comma-separated trees.json indices, "review" (BUR OAK, AMERICAN ELM, SYCAMORE, SENTINEL OAK,
APPLE 3, a QUAY WILLOW) or "all". Writes per tree into --out:
  tree_NNN.fbx                 MeshParts Bark, LeavesShade, LeavesSun (+ Apples), PBR textures embedded
  tree_NNN.json                pivot, part bounds (Roblox axes, relative to the pivot), tris, checks
  renders/tree_NNN_<view>.png  Cycles 960x540 (street, below, debug = bark see-through + red rails)
  tex/*.png                    shared procedural maps (512 px, tileable)
Threads: Cycles uses --threads (default 2); run under taskset to pin the process.
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
import textures as tx  # noqa: E402
import treegen as tg  # noqa: E402

REVIEW = [0, 1, 2, 40, 85, 77]


# ---- textures and materials ---------------------------------------------------------------------

class TexCache:
    def __init__(self, out):
        self.dir = os.path.join(out, "tex")
        os.makedirs(self.dir, exist_ok=True)
        self.layouts = {}

    def path(self, name):
        return os.path.join(self.dir, name)

    def bark(self, family):
        names = [self.path(f"bark_{family}_{k}.png") for k in ("color", "normal", "roughness")]
        if not all(os.path.exists(n) for n in names):
            c, n, r = tx.bark_maps(family, seed=11 + tx.BARK_FAMILIES.index(family))
            tx.write_png(names[0], c)
            tx.write_png(names[1], n)
            tx.write_png(names[2], r)
        return names

    def layout(self, shape):
        if shape not in self.layouts:
            self.layouts[shape] = tx.leaf_layout(shape, seed=21 + tx.LEAF_SHAPES.index(shape))
        return self.layouts[shape]

    def leaf(self, shape, palette, layer):
        key = hashlib.sha1(("|".join(palette)).encode()).hexdigest()[:8]
        cpath = self.path(f"leaf_{shape}_{key}_{layer}.png")
        npath = self.path(f"leaf_{shape}_normal.png")
        rpath = self.path(f"leaf_{shape}_roughness.png")
        if not (os.path.exists(npath) and os.path.exists(rpath)):
            n, r = tx.leaf_normal_rough(self.layout(shape))
            tx.write_png(npath, n)
            tx.write_png(rpath, r)
        if not os.path.exists(cpath):
            tx.write_png(cpath, tx.leaf_colour(self.layout(shape), palette, layer))
        return [cpath, npath, rpath]

    def apple(self):
        names = [self.path(f"apple_{k}.png") for k in ("color", "normal", "roughness")]
        if not all(os.path.exists(n) for n in names):
            c, n, r = tx.apple_maps()
            for p, a in zip(names, (c, n, r)):
                tx.write_png(p, a)
        return names


def load_image(path, non_color):
    name = os.path.basename(path)
    img = bpy.data.images.get(name)
    if img is None:
        img = bpy.data.images.load(path)
        img.name = name
    img.colorspace_settings.name = "Non-Color" if non_color else "sRGB"
    return img


def make_material(name, maps, normal_strength=1.0, debug_alpha=None):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    tc = nt.nodes.new("ShaderNodeTexImage")
    tc.image = load_image(maps[0], False)
    nt.links.new(tc.outputs["Color"], bsdf.inputs["Base Color"])
    tr = nt.nodes.new("ShaderNodeTexImage")
    tr.image = load_image(maps[2], True)
    nt.links.new(tr.outputs["Color"], bsdf.inputs["Roughness"])
    tn = nt.nodes.new("ShaderNodeTexImage")
    tn.image = load_image(maps[1], True)
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nm.inputs["Strength"].default_value = normal_strength
    nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.4
    if debug_alpha is not None:
        bsdf.inputs["Alpha"].default_value = debug_alpha
    return mat


# ---- scene --------------------------------------------------------------------------------------

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = "NONE"


def build_tree_objects(rec, data, cache, opts=None):
    t0 = time.time()
    tb = tg.TreeBuilder(rec, data, opts).build()
    sp = rec["species"]
    bark_maps = cache.bark(tg.BARK_FAMILY[sp])
    shape = tg.LEAF_SHAPE[sp]
    mats = {
        "Bark": make_material(f"Bark_{rec['index']:03d}", bark_maps, 1.0),
        "LeavesShade": make_material(f"LeavesShade_{rec['index']:03d}", cache.leaf(shape, rec["palette"], "shade"), 1.0),
        "LeavesSun": make_material(f"LeavesSun_{rec['index']:03d}", cache.leaf(shape, rec["palette"], "sun"), 1.0),
    }
    objs = {"Bark": tg.make_object("Bark", tb.bark, mats["Bark"])}
    if tb.leaf["shade"].tris:
        objs["LeavesShade"] = tg.make_object("LeavesShade", tb.leaf["shade"], mats["LeavesShade"])
    if tb.leaf["sun"].tris:
        objs["LeavesSun"] = tg.make_object("LeavesSun", tb.leaf["sun"], mats["LeavesSun"])
    if tb.fruit.tris:
        mats["Apples"] = make_material(f"Apples_{rec['index']:03d}", cache.apple(), 0.5)
        objs["Apples"] = tg.make_object("Apples", tb.fruit, mats["Apples"])
    tb.log["build_s"] = round(time.time() - t0, 2)
    return tb, objs, mats


# ---- checks -------------------------------------------------------------------------------------

def bvh_of(obj):
    dg = bpy.context.evaluated_depsgraph_get()
    return BVHTree.FromObject(obj, dg)


def to_b(p):
    return Vector((-p[0], p[2], p[1]))


def alignment_checks(tb, bark_obj):
    """Trunk: bark radius vs the squirrel's tapered radius at every route sample (8 directions).
    Boughs: bark top vs the squirrel's feet (rail + lift), by a downward ray at every sample."""
    bvh = bvh_of(bark_obj)
    out = {}
    trunk = tb.rec["trunk"]
    P = tb.trunkP
    s = tg.arclen(P)
    tt = s / s[-1]
    errs, errs_low = [], []
    for p, t in zip(P, tt):
        want = float(tb.Rt(t))
        for k in range(8):
            a = k * math.pi / 4
            d = np.array([math.cos(a), 0, math.sin(a)])
            origin = p + d * (want + 6.0)
            hit = bvh.ray_cast(to_b(origin), to_b(-d), 12.0)
            if hit[0] is None:
                continue
            hp = np.array([-hit[0][0], hit[0][2], hit[0][1]])
            got = np.linalg.norm((hp - p) * np.array([1, 0, 1]))
            (errs if p[1] > 2.5 else errs_low).append(got - want)
    errs = np.array(errs) if errs else np.zeros(1)
    out["trunk"] = {"samples": int(len(P)), "rays": int(len(errs)), "surfaceRadius_st": round(trunk["surfaceRadius"] * tg.SPU, 3),
                    "bark_minus_gameplay_radius_st": {"mean": round(float(errs.mean()), 3), "max_abs": round(float(np.abs(errs).max()), 3),
                                                      "p95_abs": round(float(np.percentile(np.abs(errs), 95)), 3)},
                    "root_flare_rays_below_2_5st": len(errs_low)}
    berrs, misses, n = [], 0, 0
    for (P, lift, kind, name, rid) in tb.rails:
        if kind == "trunk":
            continue
        L = tg.arclen(P)
        for p, sv in zip(P, L):
            if name.endswith("OPEN SKY LOOKOUT"):
                pass
            elif sv < 4.0:  # inside the trunk / collar
                continue
            feet = p + np.array([0, lift, 0])
            origin = feet + np.array([0, 1.5, 0])
            hit = bvh.ray_cast(to_b(origin), Vector((0, 0, -1)), 4.0)
            n += 1
            if hit[0] is None:
                misses += 1
                continue
            hy = hit[0][2]
            berrs.append(hy - feet[1])
    berrs = np.array(berrs) if berrs else np.zeros(1)
    out["boughs"] = {"samples": n, "misses": misses, "bark_top_minus_feet_st": {"mean": round(float(berrs.mean()), 3),
                     "max_abs": round(float(np.abs(berrs).max()), 3), "p95_abs": round(float(np.percentile(np.abs(berrs), 95)), 3)}}
    # leaves vs tunnels (clump centres): minimum clearance margin
    if tb.clumps:
        C = np.array([k[0] for k in tb.clumps])
        Rr = np.array([k[1] for k in tb.clumps])
        cl = tb.clearance(C) - Rr * 1.12
        out["leaves"] = {"clumps": len(tb.clumps), "min_tunnel_margin_st": round(float(cl.min()), 3)}
    return out


def bounds_roblox(obj):
    V = np.array([v.co[:] for v in obj.data.vertices])
    R = np.stack([-V[:, 0], V[:, 2], V[:, 1]], axis=1)
    lo, hi = R.min(0), R.max(0)
    return {"center": [round(float(x), 3) for x in (lo + hi) / 2], "size": [round(float(x), 3) for x in hi - lo]}


# ---- render -------------------------------------------------------------------------------------

def setup_render(args):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = args.samples
    scene.cycles.use_adaptive_sampling = True
    scene.cycles.adaptive_threshold = 0.03
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 6
    scene.cycles.diffuse_bounces = 3
    scene.cycles.glossy_bounces = 2
    scene.cycles.transparent_max_bounces = 16
    scene.render.threads_mode = "FIXED"
    scene.render.threads = args.threads
    scene.render.resolution_x = 960
    scene.render.resolution_y = 540
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    scene.view_settings.view_transform = "AgX"
    try:
        scene.view_settings.look = "AgX - Medium High Contrast"
    except TypeError:
        pass
    scene.view_settings.exposure = 0.0
    world = bpy.data.worlds.new("Sky")
    scene.world = world
    world.use_nodes = True
    nt = world.node_tree
    bg = nt.nodes.get("Background")
    sky = nt.nodes.new("ShaderNodeTexSky")
    try:
        sky.sky_type = "MULTIPLE_SCATTERING"
    except TypeError:
        try:
            sky.sky_type = "NISHITA"
        except TypeError:
            pass
    sun_el, sun_az = math.radians(42), math.radians(215)
    for attr, val in (("sun_elevation", sun_el), ("sun_rotation", sun_az), ("altitude", 50.0), ("air_density", 1.0),
                      ("dust_density", 1.5), ("sun_disc", False)):
        if hasattr(sky, attr):
            try:
                setattr(sky, attr, val)
            except Exception:
                pass
    nt.links.new(sky.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = 0.32
    # sun lamp matching the sky's sun
    sd = bpy.data.lights.new("Sun", "SUN")
    sd.energy = 4.2
    sd.angle = math.radians(2.5)
    sd.color = (1.0, 0.93, 0.80)
    so = bpy.data.objects.new("Sun", sd)
    scene.collection.objects.link(so)
    d = Vector((math.cos(sun_el) * math.sin(sun_az), -math.cos(sun_el) * math.cos(sun_az), math.sin(sun_el)))
    so.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    # ground: grass with soft variation
    bpy.ops.mesh.primitive_plane_add(size=900, location=(0, 0, 0))
    g = bpy.context.active_object
    g.name = "Ground"
    gm = bpy.data.materials.new("Grass")
    gm.use_nodes = True
    gnt = gm.node_tree
    gb = gnt.nodes.get("Principled BSDF")
    noise = gnt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 0.05
    ramp = gnt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (0.16, 0.25, 0.08, 1)
    ramp.color_ramp.elements[1].color = (0.30, 0.38, 0.13, 1)
    gnt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    gnt.links.new(ramp.outputs["Color"], gb.inputs["Base Color"])
    gb.inputs["Roughness"].default_value = 0.95
    g.data.materials.append(gm)
    return scene


def add_camera(name, loc, target, lens):
    cd = bpy.data.cameras.new(name)
    cd.lens = lens
    cd.clip_end = 3000
    co = bpy.data.objects.new(name, cd)
    bpy.context.scene.collection.objects.link(co)
    co.location = loc
    co.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    return co


def tree_extent(objs):
    lo = np.full(3, 1e9)
    hi = np.full(3, -1e9)
    for o in objs.values():
        V = np.array([v.co[:] for v in o.data.vertices])
        lo = np.minimum(lo, V.min(0))
        hi = np.maximum(hi, V.max(0))
    return lo, hi


def render_views(tb, objs, views, out, args, tag):
    scene = bpy.context.scene
    lo, hi = tree_extent(objs)
    top = hi[2]
    cx, cy = (lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2
    width = max(hi[0] - lo[0], hi[1] - lo[1])
    paths = {}
    for view in views:
        if view == "street":
            dist = max(top * 1.55, width * 1.1)
            ang = math.radians(200)
            loc = (cx + math.sin(ang) * dist, cy - math.cos(ang) * dist, 5.0)
            cam = add_camera("CamStreet", loc, (cx, cy, top * 0.47), 28)
        elif view == "below":
            c, rh, ylo, yhi = tb.crown
            off = max(4.0, rh * 0.32)
            ang = math.radians(30)
            loc = (-(0 + math.sin(ang) * off), math.cos(ang) * off * -1, 4.0)
            tgt = (-(c[0] * 0.5) + math.sin(ang) * off * 0.6, c[2] * 0.5 + math.cos(ang) * off * 0.6, (ylo + yhi) / 2 + 4)
            cam = add_camera("CamBelow", loc, tgt, 14)
        elif view == "debug":
            dist = max(top * 1.15, width * 0.9)
            ang = math.radians(160)
            loc = (cx + math.sin(ang) * dist, cy - math.cos(ang) * dist, top * 0.55)
            cam = add_camera("CamDebug", loc, (cx, cy, top * 0.5), 32)
        else:
            continue
        scene.camera = cam
        hidden = []
        added = []
        if view == "debug":
            for k in ("LeavesShade", "LeavesSun", "Apples"):
                if k in objs:
                    objs[k].hide_render = True
                    hidden.append(objs[k])
            added = add_debug_rails(tb, objs)
        path = os.path.join(out, "renders", f"tree_{tb.rec['index']:03d}_{view}.png")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        scene.render.filepath = path
        t0 = time.time()
        bpy.ops.render.render(write_still=True)
        paths[view] = {"path": path, "seconds": round(time.time() - t0, 1)}
        for o in hidden:
            o.hide_render = False
        for o in added:
            bpy.data.objects.remove(o, do_unlink=True)
        if view == "debug":
            objs["Bark"].data.materials[0] = tb._bark_mat_orig
    return paths


def add_debug_rails(tb, objs):
    """Red emissive rails (route centrelines) and yellow feet lines (rail + lift); bark see-through."""
    red = bpy.data.materials.new("Rail")
    red.use_nodes = True
    n = red.node_tree.nodes
    em = n.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (1.0, 0.04, 0.02, 1)
    em.inputs["Strength"].default_value = 6.0
    red.node_tree.links.new(em.outputs[0], n.get("Material Output").inputs["Surface"])
    yel = bpy.data.materials.new("Feet")
    yel.use_nodes = True
    n = yel.node_tree.nodes
    em = n.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (1.0, 0.85, 0.1, 1)
    em.inputs["Strength"].default_value = 4.0
    yel.node_tree.links.new(em.outputs[0], n.get("Material Output").inputs["Surface"])
    added = []
    for (P, lift, kind, name, rid) in tb.rails:
        for mat, off, depth in ((red, 0.0, 0.13), (yel, lift, 0.07)):
            if kind == "trunk" and mat is yel:
                continue
            cu = bpy.data.curves.new(f"rail{rid}", "CURVE")
            cu.dimensions = "3D"
            cu.bevel_depth = depth
            cu.bevel_resolution = 2
            sp = cu.splines.new("POLY")
            sp.points.add(len(P) - 1)
            for i, p in enumerate(P):
                b = to_b(p + np.array([0, off, 0]))
                sp.points[i].co = (b[0], b[1], b[2], 1)
            ob = bpy.data.objects.new(f"rail{rid}_{'f' if off else 'c'}", cu)
            ob.data.materials.append(mat)
            bpy.context.scene.collection.objects.link(ob)
            added.append(ob)
    # see-through bark
    bark = objs["Bark"]
    tb._bark_mat_orig = bark.data.materials[0]
    m = bark.data.materials[0].copy()
    m.name = "BarkGhost"
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    out = nt.nodes.get("Material Output")
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    mix.inputs["Fac"].default_value = 0.55
    nt.links.new(bsdf.outputs[0], mix.inputs[1])
    nt.links.new(tr.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs["Surface"])
    bark.data.materials[0] = m
    return added


# ---- export -------------------------------------------------------------------------------------

def export_fbx(path, objs):
    bpy.ops.object.select_all(action="DESELECT")
    ol = list(objs.values())
    for o in ol:
        o.select_set(True)
    bpy.context.view_layer.objects.active = ol[0]
    bpy.ops.export_scene.fbx(
        filepath=path,
        use_selection=True,
        object_types={"MESH"},
        axis_forward="Z",
        axis_up="Y",
        apply_unit_scale=True,
        apply_scale_options="FBX_SCALE_ALL",
        mesh_smooth_type="OFF",
        use_mesh_modifiers=True,
        use_tspace=False,
        path_mode="COPY",
        embed_textures=True,
    )


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--ids", default="review")
    ap.add_argument("--out", default="build/art/trees")
    ap.add_argument("--render", default="")
    ap.add_argument("--fbx", action="store_true")
    ap.add_argument("--samples", type=int, default=48)
    ap.add_argument("--threads", type=int, default=2)
    ap.add_argument("--no-checks", action="store_true")
    args = ap.parse_args(argv)
    out = os.path.abspath(args.out)
    os.makedirs(out, exist_ok=True)
    data = tg.load_data()
    recs = tg.tree_records(data)
    if args.ids == "all":
        ids = list(range(len(recs)))
    elif args.ids == "review":
        ids = REVIEW
    else:
        ids = [int(x) for x in args.ids.split(",") if x.strip()]
    cache = TexCache(out)
    views = [v for v in args.render.split(",") if v]
    summary = []
    for i in ids:
        rec = recs[i]
        reset_scene()
        tb, objs, mats = build_tree_objects(rec, data, cache)
        info = {
            "index": i, "label": rec["label"], "species": rec["species"], "category": rec["category"],
            "trunkRoute": rec["trunk"]["id"], "routes": [rec["trunk"]["id"]] + [m["id"] for m in rec["members"]],
            "pivot": [round(float(x), 3) for x in rec["root"]], "heightStuds": round(rec["H"], 2),
            "tris": tb.tri_counts(), "parts": {k: bounds_roblox(o) for k, o in objs.items()}, "log": tb.log,
        }
        info["tris"]["total"] = sum(info["tris"].values())
        if not args.no_checks:
            info["checks"] = alignment_checks(tb, objs["Bark"])
        if views:
            setup_render(args)
            info["renders"] = render_views(tb, objs, views, out, args, f"{i:03d}")
        if args.fbx:
            p = os.path.join(out, f"tree_{i:03d}.fbx")
            export_fbx(p, objs)
            info["fbx"] = p
            info["fbxBytes"] = os.path.getsize(p)
        with open(os.path.join(out, f"tree_{i:03d}.json"), "w") as fh:
            json.dump(info, fh, indent=1)
        line = {k: info[k] for k in ("index", "label", "tris")}
        if "checks" in info:
            line["trunkErr"] = info["checks"]["trunk"]["bark_minus_gameplay_radius_st"]["max_abs"]
            line["boughErr"] = info["checks"]["boughs"]["bark_top_minus_feet_st"]["p95_abs"]
            line["boughMiss"] = info["checks"]["boughs"]["misses"]
        print(json.dumps(line), flush=True)
        summary.append(info)
    with open(os.path.join(out, f"summary_{args.ids.replace(',', '_')[:40]}.json"), "w") as fh:
        json.dump(summary, fh, indent=1)


if __name__ == "__main__":
    main(sys.argv[1:] if "--" not in sys.argv else sys.argv[sys.argv.index("--") + 1 :])
