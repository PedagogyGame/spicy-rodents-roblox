"""His whack-a-mole GLB beside the game version (tools/blender/whack_a_mole/export.py), rendered the same way.

  /root/.cache/spicy-rodents/venv/bin/python -I tools/blender/whack_a_mole/compare.py \
      [--build build/art/whack_a_mole] [--out build/art/whack_a_mole/compare] [--samples 32]
  python3 -I tools/blender/whack_a_mole/sheet.py   (labels the pictures: system python3 + Pillow)

His Whack_A_Mole.glb (232,092 triangles, as delivered, in studs: 1 / 0.28 a metre) and whack.fbx, placed through
tools/review/art_render.py exactly as the review renders place uploaded art (the FBX read as the engine reads it,
turned with the cabinet), each piece painted as the loader paints it (Shared/Minigames/WhackAMole/Layout.COLORS,
through the manifest's material names). Both stand in the same place, with the moles up (his 0.30 m pop) and the
mallet in its bracket, and each is rendered alone under the same lights from the same cameras: VIEWS (his
Preview.png's angle, the player's view, close on the moles).
Outputs in --out: <view>_his.png and <view>_game.png for each view (sheet.py puts each pair side by side).
"""
import argparse
import json
import math
import os
import sys

import bpy
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "review"))
import art_render  # noqa: E402

GLB = os.path.join(ROOT, "docs", "reference", "whack_a_mole", "Whack_A_Mole.glb")
SCALE = 1 / 0.28
POP = 0.30 * SCALE
GAP = 0.0  # (each is rendered on its own, in the same place: see main)
# Layout.COLORS (sRGB), by the manifest's material names; a mole's fur is its own
PAINT = {
    "wood": (132, 26, 32), "black": (28, 31, 34), "brass": (201, 154, 74), "gold": (226, 196, 136),
    "cream": (238, 222, 186), "felt": (44, 104, 98), "dark": (16, 14, 16), "bulb": (255, 196, 120),
    "muzzle": (222, 176, 140), "nose": (200, 112, 104), "eye": (10, 10, 12), "glint": (240, 232, 200),
    "rubber": (132, 28, 40),
}
FUR = {1: (150, 104, 74), 2: (156, 132, 114), 3: (96, 86, 82), 4: (156, 132, 114), 5: (150, 104, 74)}
HANDLE = (110, 24, 30)
METAL = {"brass", "gold"}
# (name, camera position, look at, field of view) in Blender units (studs), the cabinet's middle at the origin
VIEWS = [
    ("01_preview_angle", (11.1, -16.4, 10.9), (0.0, 0.0, 3.9), 34),
    ("02_player_view", (0.0, -6.6, 9.4), (0.0, 0.3, 4.9), 52),
    ("03_moles_close", (1.6, -4.6, 6.4), (0.0, 0.2, 4.2), 50),
]


def lin(c):
    def one(x):
        x = x / 255.0
        return x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4

    return (one(c[0]), one(c[1]), one(c[2]), 1.0)


def paint(ob, rgb, metal, neon):
    mat = bpy.data.materials.new(f"paint_{ob.name}")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = lin(rgb)
    bsdf.inputs["Metallic"].default_value = 0.8 if metal else 0.0
    bsdf.inputs["Roughness"].default_value = 0.3 if metal else 0.5
    if neon:
        bsdf.inputs["Emission Color"].default_value = lin(rgb)
        bsdf.inputs["Emission Strength"].default_value = 3.0
    ob.data.materials.clear()
    ob.data.materials.append(mat)


def area(name, loc, power, color, size, target):
    data = bpy.data.lights.new(name, "AREA")
    data.energy = power
    data.color = color
    data.size = size
    ob = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = loc
    ob.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--build", default=os.path.join(ROOT, "build", "art", "whack_a_mole"))
    ap.add_argument("--out", default=None)
    ap.add_argument("--samples", type=int, default=32)
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else sys.argv[1:]
    a = ap.parse_args(argv)
    build = os.path.abspath(a.build)
    out = os.path.abspath(a.out or os.path.join(build, "compare"))
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(build, "manifest.json")) as fh:
        manifest = json.load(fh)
    by_name = {p["name"]: p for p in manifest["pieces"]}

    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene

    # his GLB on the left, in studs, the moles up, the demonstration animation stopped
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=GLB)
    his = [o for o in bpy.data.objects if o not in before]
    for o in his:
        if o.animation_data:
            o.animation_data_clear()
    for o in his:
        if o.name.startswith("Mole_") and o.name.endswith("_ROOT"):
            o.location.z = 0.0
    root = next(o for o in his if o.name == "Whack_A_Mole_ASSET_ROOT")
    for o in his:
        if o.name.startswith("Mole_") and o.name.endswith("_ROOT"):
            o.location.z = 0.30
    mallet = next(o for o in his if o.name == "Mallet_ROOT")
    mallet.location = (1.12, -0.25, 0.42)
    mallet.rotation_mode = "XYZ"
    mallet.rotation_euler = (0.0, math.radians(-16), math.radians(-12))
    # (the importer may put a parent over his root: scale and move the topmost)
    top = root
    while top.parent is not None:
        top = top.parent
    top.scale = (SCALE, SCALE, SCALE)
    top.location = (-GAP / 2, 0.0, 0.0)

    # the game version on the right, through the review renders' own art placement (turned with the cabinet)
    before = set(bpy.data.objects)
    art_render.build({"art": [{"file": os.path.join(build, manifest["fbx"]), "pos": [GAP / 2, 0, 0],
                               "rot": [-1, 0, 0, 0, 1, 0, 0, 0, -1], "group": "art"}]}, None)
    mine = [o for o in bpy.data.objects if o not in before]
    for o in mine:
        if o.type != "MESH":
            continue
        base = o.name.split(".")[0]
        p = by_name.get(base)
        if p is None:
            continue
        key = p["material"]
        rgb = PAINT.get(key, (200, 200, 200))
        if key == "fur":
            rgb = FUR[p["mole"]]
        elif p["group"] == "mallet" and key == "wood":
            rgb = HANDLE
        paint(o, rgb, key in METAL, key == "bulb")
        if p["group"] == "mole":
            o.location.z += POP

    # the floor, the lights (his studio's, in studs), the world
    bpy.ops.mesh.primitive_plane_add(size=80, location=(0, 0, 0))
    floor = bpy.context.object
    paint(floor, (40, 44, 52), False, False)
    S = SCALE
    area("key", (1.3 * S, -3.7 * S, 4.5 * S), 650 * S * S, (1, 0.79, 0.55), 3.2 * S, (0, 0, 1.0 * S))
    area("fill", (-3 * S, -1.7 * S, 2.9 * S), 480 * S * S, (0.63, 0.76, 1), 3.6 * S, (0, 0, 1.0 * S))
    area("edge", (2.0 * S, 2.7 * S, 3.8 * S), 850 * S * S, (1, 0.47, 0.23), 2.6 * S, (0, 0, 1.0 * S))
    area("front", (0, -3.0 * S, 2.3 * S), 90 * S * S, (1, 0.9, 0.75), 2.4 * S, (0, 0, 1.0 * S))
    world = bpy.data.worlds.new("studio")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.055, 0.064, 0.085, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.3
    scene.world = world

    scene.render.engine = "CYCLES"
    scene.cycles.samples = a.samples
    scene.cycles.device = "CPU"
    try:
        scene.cycles.use_denoising = True
    except Exception:
        pass
    scene.render.threads_mode = "FIXED"
    scene.render.threads = 3
    scene.render.resolution_x = 900
    scene.render.resolution_y = 900
    scene.view_settings.view_transform = "AgX"
    cam_data = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    sides = {"his": his, "game": mine}
    for name, pos, look, fov in VIEWS:
        cam.location = pos
        cam.rotation_euler = (Vector(look) - Vector(pos)).to_track_quat("-Z", "Y").to_euler()
        cam_data.angle = math.radians(fov)
        for side in sides:
            for other, others in sides.items():
                for o in others:
                    o.hide_render = other != side
            scene.render.filepath = os.path.join(out, f"{name}_{side}.png")
            bpy.ops.render.render(write_still=True)
            print(f"COMPARE {name} {side} -> {scene.render.filepath}", flush=True)


main()
