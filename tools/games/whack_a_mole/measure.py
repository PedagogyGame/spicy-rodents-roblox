"""Measure the owner's whack-a-mole GLB (docs/reference/whack_a_mole/Whack_A_Mole.glb).

Run (headless, isolated):
    /root/.cache/spicy-rodents/venv/bin/python -I tools/games/whack_a_mole/measure.py -- \
        docs/reference/whack_a_mole/Whack_A_Mole.glb build/whack_a_mole/measure.json

Imports the GLB into an empty scene and writes every object's world bounds (metres, Blender Z up, front is -Y),
its triangle count and materials, plus the triangle total. The numbers the game uses (the deck height, the hole
centres and radius, the mole size, the sign and its windows) are read from this file into
src/shared/Minigames/WhackAMole/Layout.luau, converted to studs at 1 / 0.28 per metre (Layout says which).
Nothing is written anywhere but the output path; the GLB is only read.
"""

import json
import sys

import bpy
from mathutils import Vector


def main():
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if len(args) != 2:
        raise SystemExit("usage: measure.py -- <in.glb> <out.json>")
    glb, out_path = args
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb)
    scene = bpy.context.scene
    scene.frame_set(1)
    # the demonstration animation moves the moles and the mallet: measure them at rest (frame 1 is all down)
    out = {}
    total = 0
    for o in bpy.data.objects:
        if o.type != "MESH":
            out[o.name] = {"type": o.type, "loc": list(o.matrix_world.translation)}
            continue
        pts = [o.matrix_world @ Vector(c) for c in o.bound_box]
        mn = [min(p[i] for p in pts) for i in range(3)]
        mx = [max(p[i] for p in pts) for i in range(3)]
        tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
        total += tris
        out[o.name] = {
            "min": [round(v, 4) for v in mn],
            "max": [round(v, 4) for v in mx],
            "tris": tris,
            "mat": [m.name for m in o.data.materials if m],
            "parent": o.parent.name if o.parent else None,
        }
    doc = {"total_tris": total, "objects": out}
    with open(out_path, "w") as f:
        json.dump(doc, f, indent=1, sort_keys=True)
    print("WHACK_MEASURE", total, len(out))


main()
