"""S12: render a turntable of the test squirrel headlessly and time every frame.

  /root/.cache/spicy-rodents/venv/bin/python -I tools/blender/render_turntable.py \
      --engine CYCLES --samples 24 --frames 36 --res 512 --threads 2 --out build/blender/cycles

Writes <out>/frame_NN.png and <out>/timing.json ({engine, samples, res, frames: [seconds...],
mean_s, failed, error}). Engines: CYCLES (CPU), EEVEE (BLENDER_EEVEE_NEXT or BLENDER_EEVEE, whichever
this build has; expected to fail without a GPU/display, which is recorded, not fatal), WORKBENCH.
The camera orbits the squirrel (10 degrees per frame for 36 frames); the rig holds Run frame 5.
"""
import argparse
import json
import math
import os
import sys
import time
import traceback

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import squirrel_test_rig  # noqa: E402


def setup_scene(arm, res, threads):
    scene = bpy.context.scene
    scene.render.resolution_x = res
    scene.render.resolution_y = res
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.compression = 60
    scene.render.film_transparent = False
    scene.render.threads_mode = "FIXED"
    scene.render.threads = threads
    scene.frame_set(5)  # mid-stride of the Run action
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"

    # World: neutral grey studio
    world = bpy.data.worlds.new("Studio")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.42, 0.44, 0.47, 1.0)
    bg.inputs["Strength"].default_value = 0.5

    # Ground disc
    bpy.ops.mesh.primitive_circle_add(vertices=64, radius=3.5, fill_type="NGON", location=(0, 0, 0))
    ground = bpy.context.active_object
    ground.name = "Ground"
    gmat = bpy.data.materials.new("GroundMat")
    gmat.use_nodes = True
    gmat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.30, 0.36, 0.26, 1)
    gmat.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 1.0
    ground.data.materials.append(gmat)

    # Three-point lighting
    def lamp(name, kind, loc, energy, size=None):
        ldata = bpy.data.lights.new(name, kind)
        ldata.energy = energy
        if size is not None and kind == "AREA":
            ldata.size = size
        lobj = bpy.data.objects.new(name, ldata)
        scene.collection.objects.link(lobj)
        lobj.location = loc
        direction = Vector((0, 0, 1.0)) - Vector(loc)
        lobj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        return lobj

    lamp("Key", "AREA", (3.0, -3.0, 4.0), 90, size=2.0)
    lamp("Fill", "AREA", (-3.5, -2.0, 2.5), 30, size=3.0)
    lamp("Rim", "AREA", (0.5, 3.5, 3.5), 60, size=1.5)

    # Camera on an empty pivot at the squirrel's centre
    pivot = bpy.data.objects.new("Pivot", None)
    scene.collection.objects.link(pivot)
    pivot.location = (0, 0, 1.05)
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.lens = 50
    cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam)
    cam.parent = pivot
    cam.location = (0, -4.2, 1.0)
    look = Vector((0, 0, 1.05)) - (Vector(pivot.location) + Vector(cam.location))
    cam.rotation_euler = look.to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    return scene, pivot


def pick_engine(name):
    name = name.upper()
    if name == "CYCLES":
        return "CYCLES"
    if name == "WORKBENCH":
        return "BLENDER_WORKBENCH"
    if name == "EEVEE":
        ids = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
        for cand in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
            if cand in ids:
                return cand
        raise RuntimeError(f"no EEVEE engine in this build; engines: {ids}")
    return name


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--engine", default="CYCLES")
    ap.add_argument("--samples", type=int, default=24)
    ap.add_argument("--frames", type=int, default=36)
    ap.add_argument("--res", type=int, default=512)
    ap.add_argument("--threads", type=int, default=2)
    ap.add_argument("--denoise", action="store_true")
    ap.add_argument("--out", required=True)
    args = ap.parse_args(argv)
    os.makedirs(args.out, exist_ok=True)
    timing = {
        "engine_requested": args.engine,
        "engine": None,
        "samples": args.samples,
        "res": args.res,
        "threads": args.threads,
        "frames": [],
        "failed": False,
        "error": None,
        "blender": bpy.app.version_string,
    }
    t_setup = time.time()
    arm, _body, rig_report = squirrel_test_rig.build(None)
    scene, pivot = setup_scene(arm, args.res, args.threads)
    try:
        engine = pick_engine(args.engine)
        timing["engine"] = engine
        scene.render.engine = engine
        if engine == "CYCLES":
            scene.cycles.device = "CPU"
            scene.cycles.samples = args.samples
            scene.cycles.use_denoising = args.denoise
            scene.cycles.use_adaptive_sampling = True
            scene.cycles.adaptive_threshold = 0.05
            scene.cycles.max_bounces = 4
        elif engine.startswith("BLENDER_EEVEE"):
            scene.eevee.taa_render_samples = args.samples
        timing["setup_s"] = round(time.time() - t_setup, 3)
        for i in range(args.frames):
            pivot.rotation_euler = (0, 0, math.radians(360.0 * i / args.frames))
            scene.render.filepath = os.path.join(args.out, f"frame_{i:02d}.png")
            t0 = time.time()
            bpy.ops.render.render(write_still=True)
            dt = time.time() - t0
            timing["frames"].append(round(dt, 3))
            print(f"[{engine}] frame {i:02d} {dt:.2f}s", flush=True)
            with open(os.path.join(args.out, "timing.json"), "w") as fh:
                json.dump(timing, fh, indent=2)
    except Exception as exc:  # noqa: BLE001  (record every failure mode: EEVEE without a GPU is expected)
        timing["failed"] = True
        timing["error"] = f"{type(exc).__name__}: {exc}"
        timing["traceback"] = traceback.format_exc()[-2000:]
        print(f"[{args.engine}] FAILED: {timing['error']}", flush=True)
    if timing["frames"]:
        timing["mean_s"] = round(sum(timing["frames"]) / len(timing["frames"]), 3)
        timing["max_s"] = max(timing["frames"])
        timing["minutes_per_frame"] = round(timing["mean_s"] / 60.0, 4)
    timing["rig"] = rig_report
    with open(os.path.join(args.out, "timing.json"), "w") as fh:
        json.dump(timing, fh, indent=2)
    return 0


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else sys.argv[1:]
    sys.exit(main(argv))
