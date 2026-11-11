"""Build, check, render and export the 95 route-true trees (headless bpy 5.2.x).

  PY=/root/.cache/spicy-rodents/venv/bin/python
  nice -n 10 taskset -c 2,3 $PY -I tools/blender/trees/build_trees.py --ids all --fbx --out build/art/trees
  nice -n 10 taskset -c 2,3 $PY -I tools/blender/trees/build_trees.py --ids review --render street,fork,collar,junction,bough
  nice -n 10 taskset -c 2,3 $PY -I tools/blender/trees/build_trees.py --ids 0 --render debug

--ids: comma-separated trees.json indices, "review" (BUR OAK, AMERICAN ELM, SYCAMORE, a street elm, SENTINEL
OAK, a park maple, a QUAY WILLOW, APPLE 3) or "all". Writes per tree into --out:
  tree_NNN.fbx                 MeshParts Bark, LeavesShade, LeavesMid, LeavesSun (+ Apples), PBR textures embedded
  tree_NNN.json                pivot, part bounds (Roblox axes, relative to the pivot), tris, checks
  renders/tree_NNN_<view>.png  Cycles (views.py cameras: street, crown, fork, collar, junction, junction2,
                               bough; debug = bark see-through + red rails + yellow feet lines)
  tex/*.png                    procedural maps: tileable bark (512), leaf-spray atlases with alpha (1024)
Leaves are alpha cards: in the engine the Leaves* parts need DoubleSided = true and their
SurfaceAppearance AlphaMode = Transparency (tree_NNN.json says so per part).
Threads: Cycles uses --threads (default 2); run under taskset to pin the process.
"""
import argparse
import hashlib
import json
import math
import os
import sys
import time

import bpy  # noqa: E402  (first: bmesh and mathutils come with it)
import bmesh  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Vector  # noqa: E402
from mathutils.bvhtree import BVHTree  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import textures as tx  # noqa: E402
import treegen as tg  # noqa: E402
import views as vw  # noqa: E402

REVIEW = [0, 1, 2, 10, 40, 50, 77, 85]
LEAF_PARTS = (("shade", "LeavesShade"), ("mid", "LeavesMid"), ("sun", "LeavesSun"))
# The game lights everything with a flat ambient that shadows do not reach (LightingPreset.GOLDEN:
# OutdoorAmbient #a2a180 against a sun of Brightness 2.6). Cycles has no such term, so the review
# materials emit their own colour times this, or the underside of every leaf would render black.
AMBIENT = 0.28


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
            self.layouts[shape] = tx.spray_layout(shape, seed=31 + tx.SPRAY_SHAPES.index(shape))
        return self.layouts[shape]

    def spray(self, shape, palette, layer):
        key = hashlib.sha1(("|".join(palette)).encode()).hexdigest()[:8]
        cpath = self.path(f"spray_{shape}_{key}_{layer}.png")
        npath = self.path(f"spray_{shape}_normal.png")
        rpath = self.path(f"spray_{shape}_roughness.png")
        if not (os.path.exists(npath) and os.path.exists(rpath)):
            n, r = tx.spray_normal_rough(self.layout(shape))
            tx.write_png(npath, n)
            tx.write_png(rpath, r)
        if not os.path.exists(cpath):
            tx.write_png(cpath, tx.spray_colour(self.layout(shape), palette, layer))
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


def make_material(name, maps, normal_strength=1.0, alpha=False):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    tc = nt.nodes.new("ShaderNodeTexImage")
    tc.image = load_image(maps[0], False)
    nt.links.new(tc.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(tc.outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = AMBIENT
    if alpha:
        # the engine's SurfaceAppearance AlphaMode Transparency: the colour map's alpha cuts the card
        tc.image.alpha_mode = "CHANNEL_PACKED"
        nt.links.new(tc.outputs["Alpha"], bsdf.inputs["Alpha"])
        mat.use_backface_culling = False
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
        bsdf.inputs["Specular IOR Level"].default_value = 0.5 if not alpha else 0.3
    return mat


# ---- the bark's one skin: a boolean union of the closed limb tubes --------------------------------

def union_parts(parts, solver="MANIFOLD"):
    """parts: [{V (n,3), faces [tuples], uvs [per face, per corner], id}] -> V, F (tris), per-corner
    uvs (m,3,2) and the owning part of every triangle. None if the union fails."""
    scene = bpy.context.scene
    objs = []
    col = bpy.data.collections.new("_union")
    for p in parts:
        me = bpy.data.meshes.new(f"_u{p['id']}")
        me.from_pydata(np.asarray(p["V"]).tolist(), [], [tuple(int(i) for i in f) for f in p["faces"]])
        uv = me.uv_layers.new(name="UVMap")
        flat = np.array([c for face in p["uvs"] for corner in face for c in corner], dtype=np.float32)
        uv.data.foreach_set("uv", flat)
        own = me.uv_layers.new(name="Owner")
        tag = np.tile(np.array([(p["id"] + 0.5) / 256.0, 0.5], dtype=np.float32), len(me.loops))
        own.data.foreach_set("uv", tag)
        me.update()
        ob = bpy.data.objects.new(me.name, me)
        scene.collection.objects.link(ob)
        objs.append(ob)
    base = objs[0]
    for ob in objs[1:]:
        col.objects.link(ob)
    out = None
    for sv in (solver, "EXACT"):
        try:
            mod = base.modifiers.new("u", "BOOLEAN")
            mod.operation = "UNION"
            mod.operand_type = "COLLECTION"
            mod.collection = col
            mod.solver = sv
            dg = bpy.context.evaluated_depsgraph_get()
            ev = base.evaluated_get(dg)
            m2 = ev.to_mesh()
            bm = bmesh.new()
            bm.from_mesh(m2)
            ev.to_mesh_clear()
            base.modifiers.remove(mod)
            if len(bm.faces) < 0.3 * sum(len(p["faces"]) for p in parts) or len(bm.faces) == len(parts[0]["faces"]):
                bm.free()
                continue
            bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.012)
            bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=0.004)
            bmesh.ops.triangulate(bm, faces=bm.faces)
            bm.verts.index_update()
            luv = bm.loops.layers.uv["UVMap"]
            lown = bm.loops.layers.uv["Owner"]
            V = np.array([v.co[:] for v in bm.verts])
            F = np.array([[l.vert.index for l in f.loops] for f in bm.faces], np.int64)
            UVc = np.array([[l[luv].uv[:] for l in f.loops] for f in bm.faces], float)
            owner = np.array([int(f.loops[0][lown].uv[0] * 256.0) for f in bm.faces], np.int64)
            bm.free()
            out = (V, F, UVc, owner)
            break
        except Exception as exc:  # a solver that is not in this build, or a failed union
            print(f"union {sv}: {exc}", flush=True)
    for ob in objs:
        me = ob.data
        bpy.data.objects.remove(ob, do_unlink=True)
        bpy.data.meshes.remove(me)
    bpy.data.collections.remove(col)
    return out


# ---- scene --------------------------------------------------------------------------------------

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = "NONE"


def build_tree_objects(rec, data, cache, opts=None):
    t0 = time.time()
    opts = dict(opts or {})
    opts.setdefault("union", union_parts)
    tb = tg.TreeBuilder(rec, data, opts).build()
    sp = rec["species"]
    bark_maps = cache.bark(tg.BARK_FAMILY[sp])
    shape = tg.LEAF_SHAPE[sp]
    mats = {"Bark": make_material(f"Bark_{rec['index']:03d}", bark_maps, 1.0)}
    objs = {"Bark": tg.make_object("Bark", tb.bark, mats["Bark"])}
    for layer, part in LEAF_PARTS:
        if tb.leaf[layer].tris:
            mats[part] = make_material(f"{part}_{rec['index']:03d}", cache.spray(shape, rec["palette"], layer), 0.8, alpha=True)
            objs[part] = tg.make_object(part, tb.leaf[layer], mats[part])
    if tb.fruit.tris:
        mats["Apples"] = make_material(f"Apples_{rec['index']:03d}", cache.apple(), 0.5)
        objs["Apples"] = tg.make_object("Apples", tb.fruit, mats["Apples"])
    tb.log["build_s"] = round(time.time() - t0, 2)
    return tb, objs, mats


# ---- checks -------------------------------------------------------------------------------------

def to_b(p):
    return Vector((-p[0], p[2], p[1]))


def stats(a):
    a = np.asarray(a, float)
    if not len(a):
        return {"n": 0}
    return {"n": int(len(a)), "mean": round(float(a.mean()), 3), "p95_abs": round(float(np.percentile(np.abs(a), 95)), 3),
            "max_abs": round(float(np.abs(a).max()), 3), "min": round(float(a.min()), 3), "max": round(float(a.max()), 3)}


def alignment_checks(tb):
    """Against the finished bark (the one skin plus the side branches):
    trunk   bark radius minus the squirrel's tapered radius, by rays from the route outward in 8
            directions at every sample; the stretches where collars add wood are reported apart.
    boughs  the squirrel's feet (rail + lift) to the bark surface past the junction, signed
            (+ floats, - sinks); the junction stretch (the first fifth, where the game pushes the
            squirrel out of the trunk) is reported apart.
    leaves  the smallest distance of any leaf vertex to a walking tunnel, and the budgets."""
    V, F, _, _ = tb.bark.arrays()
    Vb = tg.to_blender_coords(V)
    bvh = BVHTree.FromPolygons([Vector(v) for v in Vb], [tuple(int(i) for i in f) for f in F])
    Vs, Fs = tb.skin
    skin = BVHTree.FromPolygons([Vector(v) for v in tg.to_blender_coords(Vs)], [tuple(int(i) for i in f) for f in Fs])
    out = {}
    trunk = tb.rec["trunk"]
    P = tb.trunkP
    tt = tb.trunk_s / tb.trunkL
    flare_top = max(2.5, 1.2 * float(tb.Rt(0.0)))
    climb, zone, low = [], [], []
    for p, t in zip(P, tt):
        want = float(tb.Rt(t))
        in_zone = any(y0 <= p[1] <= y1 for y0, y1 in tb.zones) or t > 0.985
        for k in range(8):
            a = k * math.pi / 4
            d = np.array([math.cos(a), 0, math.sin(a)])
            hit = skin.ray_cast(to_b(p), Vector((-d[0], d[2], d[1])), want + 14.0)
            if hit[0] is None:
                continue
            err = hit[3] - want
            (low if p[1] <= flare_top else (zone if in_zone else climb)).append(err)
    out["trunk"] = {"samples": int(len(P)), "surfaceRadius_st": round(trunk["surfaceRadius"] * tg.SPU, 3),
                    "climb_zone_from_st": round(flare_top, 2),
                    "bark_minus_gameplay_radius_st": stats(climb), "at_collars": stats(zone), "root_flare": stats(low)}
    routes = tb.data["routes"]
    past, junction, pads, miss = [], [], [], 0
    worst = (0.0, "", 0.0)
    for (Pr, lift, kind, name, rid) in tb.rails:
        if kind == "trunk":
            continue
        route = routes[rid]
        s = tg.arclen(Pr)
        t = s / max(s[-1], 1e-9)
        b = next((b for b in tb.boughs if b["route"]["id"] == rid), None)
        feet_line = Pr + tg.Y[None] * lift
        feet_drawn = tb.feet_path(Pr, lift, kind, route)
        pushed = kind == "branch" and route.get("trunkClearance")
        for i in range(len(Pr)):
            if name.endswith("OPEN SKY LOOKOUT"):
                bucket, q = pads, feet_line[i]
            elif b is not None and b["on_trunk"] and (t[i] < 0.2 if pushed else s[i] < b["zone"]):
                bucket, q = junction, feet_drawn[i]
            else:
                bucket, q = past, feet_line[i]
            near = bvh.find_nearest(to_b(q), 8.0)
            if near[0] is None:
                miss += 1
                continue
            dvec = to_b(q) - near[0]
            e = (1.0 if dvec.dot(near[1]) >= 0 else -1.0) * near[3]
            bucket.append(e)
            if bucket is past and abs(e) > abs(worst[0]):
                worst = (round(float(e), 3), name, round(float(s[i]), 1), round(float(s[-1]), 1))
    out["boughs"] = {"misses": miss, "feet_to_bark_surface_st": stats(past), "worst": worst,
                     "junction_feet_to_bark_st": stats(junction), "lookout_pads": stats(pads)}
    lv = []
    for layer, part in LEAF_PARTS:
        Vl = tb.leaf[layer].arrays()[0]
        if len(Vl):
            lv.append(Vl)
    tr = tb.tri_counts()
    leaves = tr["leaves_shade"] + tr["leaves_mid"] + tr["leaves_sun"]
    out["leaves"] = {"cards": len(tb.cards), "min_tunnel_margin_st": round(float(tb.clearance(np.concatenate(lv)).min()), 3) if lv else None}
    out["budget"] = {"bark": tr["bark"], "bark_max": tg.BARK_BUDGET, "leaves": leaves, "leaves_max": tg.LEAF_BUDGET,
                     "ok": bool(tr["bark"] <= tg.BARK_BUDGET and leaves <= tg.LEAF_BUDGET)}
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
    scene.cycles.transparent_max_bounces = 48
    scene.render.threads_mode = "FIXED"
    scene.render.threads = args.threads
    scene.render.resolution_x, scene.render.resolution_y = (int(v) for v in args.res.split("x"))
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
    gnt.links.new(ramp.outputs["Color"], gb.inputs["Emission Color"])
    gb.inputs["Emission Strength"].default_value = AMBIENT
    gb.inputs["Roughness"].default_value = 0.95
    g.data.materials.append(gm)
    return scene


def add_camera(name, loc, target, lens):
    cd = bpy.data.cameras.new(name)
    cd.lens = lens
    cd.clip_start = 0.05
    cd.clip_end = 3000
    co = bpy.data.objects.new(name, cd)
    bpy.context.scene.collection.objects.link(co)
    co.location = loc
    co.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    return co


def render_views(tb, objs, views, out, args):
    scene = bpy.context.scene
    paths = {}
    rx, ry = (int(v) for v in args.res.split("x"))
    route_cams = vw.cameras(tb.rails, tb.H, rx / ry)
    for view in views:
        key = view[2:] if view.startswith("r_") else view
        hidden, added = [], []
        if key in route_cams:
            # route-defined cameras (views.py): the same picture before and after an art change
            loc, tgt, lens = route_cams[key]
            cam = add_camera("Cam" + key, to_b(loc), to_b(tgt), lens)
        elif key == "debug":
            loc, tgt, lens = route_cams["street"]
            loc = np.array([loc[0], tb.H * 0.55, loc[2]])
            cam = add_camera("CamDebug", to_b(loc), to_b(tgt), 32)
            for k in ("LeavesShade", "LeavesMid", "LeavesSun", "Apples"):
                if k in objs:
                    objs[k].hide_render = True
                    hidden.append(objs[k])
            added = add_debug_rails(tb, objs)
        else:
            continue
        scene.camera = cam
        path = os.path.join(out, "renders", f"tree_{tb.rec['index']:03d}_{key}{('_' + args.tag) if args.tag else ''}.png")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        scene.render.filepath = path
        t0 = time.time()
        bpy.ops.render.render(write_still=True)
        paths[key] = {"path": path, "seconds": round(time.time() - t0, 1)}
        for o in hidden:
            o.hide_render = False
        for o in added:
            bpy.data.objects.remove(o, do_unlink=True)
        if key == "debug":
            objs["Bark"].data.materials[0] = tb._bark_mat_orig
    return paths


def add_debug_rails(tb, objs):
    """Red emissive rails (route centrelines) and yellow feet lines (the drawn feet); bark see-through."""
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
    routes = tb.data["routes"]
    for (P, lift, kind, name, rid) in tb.rails:
        for mat, depth in ((red, 0.13), (yel, 0.07)):
            if kind == "trunk" and mat is yel:
                continue
            line = P if mat is red else tb.feet_path(P, lift, kind, routes[rid])
            cu = bpy.data.curves.new(f"rail{rid}", "CURVE")
            cu.dimensions = "3D"
            cu.bevel_depth = depth
            cu.bevel_resolution = 2
            sp = cu.splines.new("POLY")
            sp.points.add(len(line) - 1)
            for i, p in enumerate(line):
                b = to_b(p)
                sp.points[i].co = (b[0], b[1], b[2], 1)
            ob = bpy.data.objects.new(f"rail{rid}_{'c' if mat is red else 'f'}", cu)
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
    ap.add_argument("--res", default="960x540")
    ap.add_argument("--tag", default="", help="suffix for the render file names (e.g. before)")
    ap.add_argument("--no-checks", action="store_true")
    ap.add_argument("--no-leaves", action="store_true", help="render the bark alone (junction close-ups)")
    ap.add_argument("--clay", action="store_true", help="render the bark untextured (to judge the forms)")
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
        parts = {k: bounds_roblox(o) for k, o in objs.items()}
        for k in parts:
            leaf = k.startswith("Leaves")
            parts[k]["doubleSided"] = leaf
            parts[k]["alphaMode"] = "Transparency" if leaf else "Overlay"
            if leaf:
                # the part's own colour: the palette's mean green (seen only if the textures never load)
                rgb = np.mean([[int(h[j : j + 2], 16) for j in (1, 3, 5)] for h in rec["palette"]], axis=0)
                parts[k]["color"] = [int(round(float(x))) for x in rgb]
        info = {
            "index": i, "label": rec["label"], "species": rec["species"], "category": rec["category"],
            "trunkRoute": rec["trunk"]["id"], "routes": [rec["trunk"]["id"]] + [m["id"] for m in rec["members"]],
            "pivot": [round(float(x), 3) for x in rec["root"]], "heightStuds": round(rec["H"], 2),
            "tris": tb.tri_counts(), "parts": parts, "log": tb.log,
        }
        info["tris"]["total"] = sum(info["tris"].values())
        if not args.no_checks:
            info["checks"] = alignment_checks(tb)
        if views:
            setup_render(args)
            if args.no_leaves:
                for k in ("LeavesShade", "LeavesMid", "LeavesSun", "Apples"):
                    if k in objs:
                        objs[k].hide_render = True
            if args.clay:
                clay = bpy.data.materials.new("Clay")
                clay.use_nodes = True
                b = clay.node_tree.nodes.get("Principled BSDF")
                b.inputs["Base Color"].default_value = (0.62, 0.58, 0.52, 1)
                b.inputs["Roughness"].default_value = 0.75
                objs["Bark"].data.materials[0] = clay
            info["renders"] = render_views(tb, objs, views, out, args)
        if args.fbx:
            p = os.path.join(out, f"tree_{i:03d}.fbx")
            export_fbx(p, objs)
            info["fbx"] = p
            info["fbxBytes"] = os.path.getsize(p)
        with open(os.path.join(out, f"tree_{i:03d}.json"), "w") as fh:
            json.dump(info, fh, indent=1)
        line = {k: info[k] for k in ("index", "label", "tris")}
        if "checks" in info:
            c = info["checks"]
            line["trunkErr"] = c["trunk"]["bark_minus_gameplay_radius_st"].get("max_abs")
            line["boughErr"] = c["boughs"]["feet_to_bark_surface_st"].get("p95_abs")
            line["leafMargin"] = c["leaves"]["min_tunnel_margin_st"]
            line["budgetOk"] = c["budget"]["ok"]
        line["s"] = tb.log.get("build_s")
        print(json.dumps(line), flush=True)
        summary.append(info)
    with open(os.path.join(out, f"summary_{args.ids.replace(',', '_')[:40]}.json"), "w") as fh:
        json.dump(summary, fh, indent=1)


if __name__ == "__main__":
    main(sys.argv[1:] if "--" not in sys.argv else sys.argv[sys.argv.index("--") + 1 :])
