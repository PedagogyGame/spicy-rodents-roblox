"""Review renders for a built hero (.blend from build_hero.py): Cycles CPU, 2 threads.

  taskset -c 2,3 /root/.cache/spicy-rodents/venv/bin/python -I tools/blender/heroes/render_hero.py \
      --blend build/heroes/squirrel/squirrel.blend --out docs/renders/heroes/squirrel \
      [--turntable 12] [--poses] [--still] [--res 960x540] [--samples 48]

The materials are switched to what the engine shows: Body/Pattern colour x lerp(1, tint, alpha)
(SurfaceAppearance TintMask with the stock Color), FurCards x tint with alpha, the rodent's eyes glow.
Turntable: the Idle clip's first frame (or the rest pose), the camera orbits 360 degrees.
Pose sheet: each clip's key poses side by side (frames listed in the clip report), one row per clip.
"""
import argparse
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Vector  # noqa: E402

import bl  # noqa: E402


def lin(hexs):
    return tuple(bl.srgb_to_lin(bl.hexrgb(hexs)).tolist()) + (1.0,)


def tint_materials(tints, glow):
    for name, hexs in tints.items():
        mat = bpy.data.materials.get(name)
        if mat is None or not mat.use_nodes:
            continue
        nt = mat.node_tree
        bsdf = nt.nodes.get("Principled BSDF")
        link = next((l for l in nt.links if l.to_node == bsdf and l.to_socket.name == "Base Color"), None)
        if link is None:
            continue
        img = link.from_node
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs["B"].default_value = lin(hexs)
        nt.links.new(img.outputs["Color"], mix.inputs["A"])
        if name in ("Body", "Pattern"):
            nt.links.new(img.outputs["Alpha"], mix.inputs["Factor"])
        else:
            mix.inputs["Factor"].default_value = 1.0
        nt.links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
    eyes = bpy.data.materials.get("Eyes")
    if eyes is not None and glow:
        nt = eyes.node_tree
        bsdf = nt.nodes.get("Principled BSDF")
        img = next(l.from_node for l in nt.links if l.to_node == bsdf and l.to_socket.name == "Base Color")
        sep = nt.nodes.new("ShaderNodeSeparateColor")
        nt.links.new(img.outputs["Color"], sep.inputs["Color"])
        sub = nt.nodes.new("ShaderNodeMath")
        sub.operation = "SUBTRACT"
        sub.use_clamp = True
        nt.links.new(sep.outputs["Red"], sub.inputs[0])
        nt.links.new(sep.outputs["Green"], sub.inputs[1])
        mul = nt.nodes.new("ShaderNodeMath")
        mul.operation = "MULTIPLY"
        mul.inputs[1].default_value = 6.0
        nt.links.new(sub.outputs["Value"], mul.inputs[0])
        nt.links.new(img.outputs["Color"], bsdf.inputs["Emission Color"])
        nt.links.new(mul.outputs["Value"], bsdf.inputs["Emission Strength"])


def studio(scene, size, center):
    world = bpy.data.worlds.new("Studio")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.52, 0.56, 0.62, 1)
    bg.inputs["Strength"].default_value = 0.55
    bpy.ops.mesh.primitive_circle_add(vertices=96, radius=size * 6, fill_type="NGON", location=(0, 0, 0))
    ground = bpy.context.active_object
    ground.name = "Ground"
    gm = bpy.data.materials.new("GroundMat")
    gm.use_nodes = True
    p = gm.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (0.20, 0.19, 0.17, 1)
    p.inputs["Roughness"].default_value = 0.9
    ground.data.materials.append(gm)

    def lamp(name, loc, energy, sz, color):
        ld = bpy.data.lights.new(name, "AREA")
        ld.energy = energy * size * size
        ld.size = sz * size
        ld.color = color
        lo = bpy.data.objects.new(name, ld)
        scene.collection.objects.link(lo)
        lo.location = Vector(loc) * size + Vector(center)
        lo.rotation_euler = (Vector(center) - lo.location).to_track_quat("-Z", "Y").to_euler()
        return lo

    lamp("Key", (2.6, -2.4, 3.0), 110, 1.6, (1.0, 0.93, 0.84))
    lamp("Fill", (-3.0, -1.6, 1.4), 28, 2.5, (0.80, 0.86, 1.0))
    lamp("Rim", (-0.8, 3.2, 2.2), 120, 1.0, (1.0, 0.96, 0.9))
    lamp("Rim2", (2.8, 2.4, 1.0), 45, 1.0, (1.0, 0.95, 0.9))


def camera(scene, lens=50):
    cd = bpy.data.cameras.new("Cam")
    cd.lens = lens
    cam = bpy.data.objects.new("Cam", cd)
    scene.collection.objects.link(cam)
    scene.camera = cam
    return cam


def place(cam, center, dist, az, el):
    a, e = math.radians(az), math.radians(el)
    cam.location = Vector(center) + Vector((math.cos(e) * math.cos(a), math.cos(e) * math.sin(a), math.sin(e))) * dist
    cam.rotation_euler = (Vector(center) - cam.location).to_track_quat("-Z", "Y").to_euler()


def setup_render(scene, res, samples, threads=2):
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.cycles.use_adaptive_sampling = True
    scene.cycles.adaptive_threshold = 0.03
    scene.cycles.max_bounces = 6
    scene.cycles.transparent_max_bounces = 24
    scene.render.threads_mode = "FIXED"
    scene.render.threads = threads
    scene.render.resolution_x, scene.render.resolution_y = res
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"


def set_action(arm, name, frame):
    act = bpy.data.actions.get(name)
    if act is None:
        return False
    arm.animation_data.action = act
    bpy.context.scene.frame_set(frame)
    return True


def rest(arm):
    if arm.animation_data:
        arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.matrix_basis.identity()


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--blend", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--turntable", type=int, default=0)
    ap.add_argument("--poses", action="store_true")
    ap.add_argument("--still", action="store_true")
    ap.add_argument("--res", default="960x540")
    ap.add_argument("--samples", type=int, default=48)
    ap.add_argument("--pose-res", default="480x300")
    ap.add_argument("--clips", default="")
    ap.add_argument("--hide-cards", action="store_true")
    ap.add_argument("--workbench", action="store_true", help="fast shape-only pose check")
    opts = ap.parse_args(argv)
    bpy.ops.wm.open_mainfile(filepath=opts.blend)
    scene = bpy.context.scene
    os.makedirs(opts.out, exist_ok=True)
    meta = json.loads(scene.get("hero_meta", "{}"))
    size = meta.get("size", 1.0)
    center = Vector(meta.get("center", (0, 0.3, 0.85)))
    tint_materials(meta.get("tints", {}), meta.get("glow", False))
    if opts.hide_cards and bpy.data.objects.get("FurCards"):
        bpy.data.objects["FurCards"].hide_render = True
    studio(scene, size, center)
    cam = camera(scene)
    arm = bpy.data.objects.get("Rig")
    res = tuple(int(x) for x in opts.res.split("x"))
    setup_render(scene, res, opts.samples)
    if opts.workbench:
        scene.render.engine = "BLENDER_WORKBENCH"
        sh = scene.display.shading
        sh.light = "STUDIO"
        sh.color_type = "TEXTURE"
        sh.show_cavity = True
        sh.show_shadows = False  # shadow volumes streak on the open region meshes
    tag = meta.get("variant", "hero")
    written = []
    hero_pose = meta.get("turntable_pose")
    if hero_pose and not set_action(arm, hero_pose[0], hero_pose[1]):
        rest(arm)
    if opts.still:
        for i, (az, el) in enumerate(((-58, 12), (-150, 18), (0, 4))):
            place(cam, center + Vector((0, 0, 0.15 * size)), size * 5.6, az, el)
            scene.render.filepath = os.path.join(opts.out, f"{tag}_still_{i}.png")
            bpy.ops.render.render(write_still=True)
            written.append(scene.render.filepath)
    if opts.turntable:
        for i in range(opts.turntable):
            place(cam, center + Vector((0, 0, 0.22 * size)), size * 6.3, -90 + 360.0 * i / opts.turntable, 12)
            scene.render.filepath = os.path.join(opts.out, f"{tag}_turntable_{i:02d}.png")
            bpy.ops.render.render(write_still=True)
            written.append(scene.render.filepath)
            print(f"turntable {i}", flush=True)
    if opts.poses:
        pres = tuple(int(x) for x in opts.pose_res.split("x"))
        scene.render.resolution_x, scene.render.resolution_y = pres
        clips = meta.get("clips", {})
        only = [c for c in opts.clips.split(",") if c]
        for clip, info in clips.items():
            if only and clip not in only:
                continue
            view = info.get("view", [-14, 6])
            for k, f in enumerate(info["key_frames"]):
                set_action(arm, f"{clip}", f)
                c = Vector(info.get("center", list(center + Vector((0, 0, 0.12)))))
                place(cam, c, size * info.get("dist", 5.2), view[0], view[1])
                scene.render.filepath = os.path.join(opts.out, f"{tag}_pose_{clip}_{k}.png")
                bpy.ops.render.render(write_still=True)
                written.append(scene.render.filepath)
            print(f"poses {clip}", flush=True)
    with open(os.path.join(opts.out, f"{tag}_renders.json"), "w") as fh:
        json.dump({"written": written, "samples": opts.samples, "res": opts.res}, fh, indent=1)
    return 0


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else sys.argv[1:]
    sys.exit(main(argv))
