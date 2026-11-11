"""Junction test pieces, rendered from a squirrel's height (headless bpy, Cycles CPU).

  nice -n 10 /root/.cache/spicy-rodents/venv/bin/python -I tools/blender/trees/junction_demo.py \
      [--cases bough,fork] [--out docs/renders/trees] [--res 1280x720] [--samples 48] [--check]

Cases: bough = a bough leaving a thick trunk; fork = a limb splitting in two. Each picture has the
squirrel's view on the left (a stud off the bark, three or four studs from the junction, looking along
the limb) and a view from further off on the right; low sun. --check only prints the mesh numbers.
Writes <out>/junction_<case>.jpg. Units studs, Roblox axes (+Y up); Blender (x, y, z) = (-X, Z, Y).
"""
import argparse
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import junction as jn  # noqa: E402

REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))


def curve(p0, d0, length, n, bend=(0.0, 0.0, 0.0)):
    pts, d, p = [np.array(p0, float)], jn._norm(np.array(d0, float)), np.array(p0, float)
    for _ in range(n):
        d = jn._norm(d + np.array(bend) * (length / n))
        p = p + d * (length / n)
        pts.append(p.copy())
    return np.array(pts)


def case(name):
    """-> parent, children, options, squirrel camera (eye, target), far camera (eye, target)"""
    if name == "bough":
        P = curve((0, 0, 0), (0, 1, 0), 24, 8)
        Rp = np.linspace(2.5, 2.1, len(P))
        base = np.array([0.0, 12.0, 0.0])
        C = curve(base, (1, 0.45, 0.15), 14, 8, bend=(0, 0.02, 0))
        Rc = np.linspace(1.3, 0.8, len(C))
        opts = dict(sides=10, child_sides=8, u_rep=4, child_u_rep=2, v_tile=4.0)
        return (P, Rp), [(C, Rc)], opts, ((1.6, 7.6, 3.4), (2.2, 12.6, 0.6)), ((7.5, 10.0, 9.5), (1.5, 12.5, 0.0))
    if name == "fork":
        P = curve((0, 0, 0), (0.1, 1, 0), 12, 5)
        Rp = np.linspace(1.7, 1.55, len(P))
        E = P[-1]
        C1 = curve(E, (0.55, 1, 0.05), 12, 6, bend=(0.01, 0.02, 0))
        C2 = curve(E, (-0.5, 1, -0.1), 12, 6, bend=(-0.01, 0.02, 0))
        opts = dict(sides=10, child_sides=8, u_rep=3, child_u_rep=2, v_tile=4.0)
        return (P, Rp), [(C1, np.linspace(1.2, 0.8, len(C1))), (C2, np.linspace(1.05, 0.7, len(C2)))], opts, \
            ((0.6, 7.6, 3.4), (1.1, 13.4, 0.0)), ((1.5, 11.0, 11.0), (1.0, 13.0, 0.0))
    raise SystemExit(f"unknown case {name}")


def render(name, V, F, UV, N, cams, args):
    import bpy
    from mathutils import Vector

    import textures as tx

    tex = os.path.join(REPO, "build", "art", "trees", "tex")
    os.makedirs(tex, exist_ok=True)
    maps = [os.path.join(tex, f"bark_oak_{k}.png") for k in ("color", "normal", "roughness")]
    if not all(os.path.exists(m) for m in maps):
        for m, a in zip(maps, tx.bark_maps("oak", seed=11 + tx.BARK_FAMILIES.index("oak"))):
            tx.write_png(m, a)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene

    def tb(p):
        return (-p[0], p[2], p[1])

    me = bpy.data.meshes.new(name)
    me.from_pydata([tb(v) for v in V], [], F.tolist())
    uv = me.uv_layers.new(name="UVMap")
    uv.data.foreach_set("uv", UV[F.ravel()].astype(np.float32).ravel())
    me.polygons.foreach_set("use_smooth", np.ones(len(F), bool))
    me.normals_split_custom_set_from_vertices([tb(n) for n in N])
    me.update()
    mat = bpy.data.materials.new("Bark")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")

    def img(path, data):
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = bpy.data.images.load(path)
        t.image.colorspace_settings.name = "Non-Color" if data else "sRGB"
        return t

    tc, tn, tr = img(maps[0], False), img(maps[1], True), img(maps[2], True)
    nt.links.new(tc.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(tc.outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = 0.2
    nt.links.new(tr.outputs["Color"], bsdf.inputs["Roughness"])
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    me.materials.append(mat)
    scene.collection.objects.link(bpy.data.objects.new(name, me))

    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = args.samples
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 4
    scene.render.threads_mode = "FIXED"
    scene.render.threads = 2
    rx, ry = (int(v) for v in args.res.split("x"))
    scene.render.resolution_x, scene.render.resolution_y = rx // 2, ry
    scene.render.image_settings.file_format = "PNG"
    world = bpy.data.worlds.new("Sky")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.68, 0.9, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.5
    sd = bpy.data.lights.new("Sun", "SUN")
    sd.energy, sd.angle, sd.color = 4.5, math.radians(2.5), (1.0, 0.92, 0.78)
    so = bpy.data.objects.new("Sun", sd)
    scene.collection.objects.link(so)
    el, az = math.radians(24), math.radians(150)  # a low sun, off to one side of the cameras
    d = Vector((math.cos(el) * math.sin(az), -math.cos(el) * math.cos(az), math.sin(el)))
    so.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    parts = []
    for k, (eye, target) in enumerate(cams):
        cd = bpy.data.cameras.new(f"cam{k}")
        cd.lens, cd.clip_start = (20 if k == 0 else 32), 0.05
        co = bpy.data.objects.new(f"cam{k}", cd)
        scene.collection.objects.link(co)
        co.location = tb(eye)
        co.rotation_euler = (Vector(tb(target)) - Vector(tb(eye))).to_track_quat("-Z", "Y").to_euler()
        scene.camera = co
        scene.render.filepath = os.path.join(args.tmp, f"junction_{name}_{k}.png")
        bpy.ops.render.render(write_still=True)
        parts.append(scene.render.filepath)
    # side by side, as one JPEG
    ims = [bpy.data.images.load(p) for p in parts]
    w, h = ims[0].size
    px = [np.array(im.pixels[:], np.float32).reshape(h, w, 4) for im in ims]
    out = bpy.data.images.new("sheet", w * 2, h)
    out.pixels = np.concatenate(px, axis=1).ravel()
    out.file_format = "JPEG"
    scene.render.image_settings.file_format = "JPEG"
    scene.render.image_settings.quality = 88
    scene.view_settings.view_transform = "Standard"
    path = os.path.join(args.out, f"junction_{name}.jpg")
    out.save_render(path, scene=scene)
    return path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cases", default="bough,fork")
    ap.add_argument("--out", default=os.path.join(REPO, "docs", "renders", "trees"))
    ap.add_argument("--tmp", default=os.path.join(REPO, "build", "art", "trees", "junction"))
    ap.add_argument("--res", default="1280x720")
    ap.add_argument("--samples", type=int, default=48)
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    os.makedirs(args.tmp, exist_ok=True)
    for name in args.cases.split(","):
        parent, kids, opts, sq, far = case(name)
        V, F, UV, N, info = jn.junction_mesh(parent, kids, **opts)
        print(name, {k: v for k, v in info.items() if k != "ports"}, info["ports"], flush=True)
        if not args.check:
            print("wrote", render(name, V, F, UV, N, (sq, far), args), flush=True)


if __name__ == "__main__":
    main()
