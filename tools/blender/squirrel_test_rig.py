"""Build the S12 test squirrel: a 13-bone rig (a subset of the FINAL RigSpec names) skinned to a
procedural ellipsoid mesh, two materials (Body fur, Pattern accents) and a Run action.

Headless, bpy wheel (Blender 5.2.x LTS). Pure function of its inputs: no files are read.
Run on its own to save the .blend and a report:
  /root/.cache/spicy-rodents/venv/bin/python -I tools/blender/squirrel_test_rig.py --out build/blender

Bone names follow src/shared/Actors/RigSpec.luau (squirrel): Root (non-deform, origin), Hips, Spine1,
Chest, Neck, Head, Tail1..Tail3 (the final rig has Tail1..Tail8), FrontL_Upper, FrontR_Upper,
BackL_Upper, BackR_Upper (the final rig adds _Lower/_Foot/_Toe). 1 Blender unit = 1 stud
(Unit System None, FBX unit scale), body along -Y (Blender front), +Z up, shoulder about 1.2 studs.
"""
import argparse
import json
import math
import os
import sys

import bpy  # noqa: E402  (must come first: the wheel registers bmesh/mathutils on import)
import bmesh  # noqa: E402
from mathutils import Vector  # noqa: E402

# name, head, tail, parent, deform
BONES = [
    ("Root", (0, 0, 0), (0, 0, 0.3), None, False),
    ("Hips", (0, 0.45, 0.9), (0, 0.15, 1.0), "Root", True),
    ("Spine1", (0, 0.15, 1.0), (0, -0.2, 1.1), "Hips", True),
    ("Chest", (0, -0.2, 1.1), (0, -0.5, 1.2), "Spine1", True),
    ("Neck", (0, -0.5, 1.2), (0, -0.65, 1.4), "Chest", True),
    ("Head", (0, -0.65, 1.4), (0, -0.95, 1.45), "Neck", True),
    ("Tail1", (0, 0.45, 0.9), (0, 0.75, 1.2), "Hips", True),
    ("Tail2", (0, 0.75, 1.2), (0, 0.9, 1.7), "Tail1", True),
    ("Tail3", (0, 0.9, 1.7), (0, 0.8, 2.2), "Tail2", True),
    ("FrontL_Upper", (0.2, -0.45, 1.0), (0.2, -0.5, 0.0), "Chest", True),
    ("FrontR_Upper", (-0.2, -0.45, 1.0), (-0.2, -0.5, 0.0), "Chest", True),
    ("BackL_Upper", (0.22, 0.35, 0.9), (0.22, 0.3, 0.0), "Hips", True),
    ("BackR_Upper", (-0.22, 0.35, 0.9), (-0.22, 0.3, 0.0), "Hips", True),
]

def srgb(hexstr):
    """sRGB hex -> linear RGBA for Principled Base Color."""
    c = [int(hexstr[i : i + 2], 16) / 255.0 for i in (1, 3, 5)]
    return tuple(((v + 0.055) / 1.055) ** 2.4 if v > 0.04045 else v / 12.92 for v in c) + (1.0,)


FUR = srgb("#b78453")  # stock fur 0 (wildlife_foraging 2.1)
PATTERN = srgb("#e8dcc4")  # belly / tail tip accent
EYE = srgb("#29302f")


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "NONE"
    scene.render.fps = 30
    return scene


def build_armature(scene):
    arm_data = bpy.data.armatures.new("SquirrelRig")
    arm_obj = bpy.data.objects.new("SquirrelRig", arm_data)
    scene.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")
    for name, head, tail, parent, deform in BONES:
        eb = arm_data.edit_bones.new(name)
        eb.head = head
        eb.tail = tail
        eb.use_deform = deform
        if parent:
            eb.parent = arm_data.edit_bones[parent]
            eb.use_connect = tuple(arm_data.edit_bones[parent].tail) == tuple(head)
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm_obj


def build_mesh(scene):
    bm = bmesh.new()
    pattern_faces = []

    def add_ellipsoid(center, radii, segs=24, rings=12, material=0):
        geom = bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0)
        for v in geom["verts"]:
            v.co = Vector((v.co.x * radii[0] + center[0], v.co.y * radii[1] + center[1], v.co.z * radii[2] + center[2]))
        if material:
            for v in geom["verts"]:
                for f in v.link_faces:
                    f.material_index = material

    add_ellipsoid((0, 0.0, 1.05), (0.28, 0.6, 0.3))  # torso
    add_ellipsoid((0, -0.8, 1.42), (0.17, 0.22, 0.17))  # head
    add_ellipsoid((0, -1.0, 1.36), (0.08, 0.12, 0.07))  # snout
    add_ellipsoid((0.09, -0.78, 1.6), (0.045, 0.03, 0.06), segs=10, rings=6)  # ear L
    add_ellipsoid((-0.09, -0.78, 1.6), (0.045, 0.03, 0.06), segs=10, rings=6)  # ear R
    add_ellipsoid((0.11, -0.95, 1.47), (0.03, 0.03, 0.03), segs=8, rings=6, material=2)  # eye L
    add_ellipsoid((-0.11, -0.95, 1.47), (0.03, 0.03, 0.03), segs=8, rings=6, material=2)  # eye R
    add_ellipsoid((0, 0.72, 1.12), (0.16, 0.22, 0.2), segs=16, rings=12)  # tail base
    add_ellipsoid((0, 0.86, 1.5), (0.19, 0.22, 0.32), segs=16, rings=12)  # tail mid
    add_ellipsoid((0, 0.84, 2.0), (0.17, 0.2, 0.32), segs=16, rings=12, material=1)  # tail tip (pattern)
    add_ellipsoid((0, 0.0, 0.86), (0.2, 0.45, 0.14), segs=16, rings=8, material=1)  # belly (pattern)
    for x, y in ((0.2, -0.47), (-0.2, -0.47), (0.22, 0.32), (-0.22, 0.32)):
        add_ellipsoid((x, y, 0.5), (0.07, 0.07, 0.5), segs=10, rings=8)  # legs

    me = bpy.data.meshes.new("SquirrelBody")
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new("SquirrelBody", me)
    scene.collection.objects.link(obj)
    for name, rgba in (("Body", FUR), ("Pattern", PATTERN), ("Eyes", EYE)):
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = rgba
        bsdf.inputs["Roughness"].default_value = 0.35 if name == "Eyes" else 0.9
        me.materials.append(mat)
    # smooth shading
    for p in me.polygons:
        p.use_smooth = True
    return obj


def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (p - (a + ab * t)).length


def skin(mesh_obj, arm_obj):
    deform = [(n, Vector(h), Vector(t)) for n, h, t, _p, d in BONES if d]
    groups = {n: mesh_obj.vertex_groups.new(name=n) for n, _h, _t in deform}
    for v in mesh_obj.data.vertices:
        dists = sorted(((seg_dist(v.co, h, t), n) for n, h, t in deform))[:2]
        inv = [1.0 / max(d, 1e-4) ** 2 for d, _n in dists]
        s = sum(inv)
        for (d, n), w in zip(dists, inv):
            groups[n].add([v.index], w / s, "REPLACE")
    mod = mesh_obj.modifiers.new("Armature", "ARMATURE")
    mod.object = arm_obj
    mesh_obj.parent = arm_obj


def key_action(arm_obj, name, frames, pose_fn):
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    if arm_obj.animation_data is None:
        arm_obj.animation_data_create()
    arm_obj.animation_data.action = act
    for f in frames:
        for pb in arm_obj.pose.bones:
            pb.rotation_mode = "XYZ"
            pb.rotation_euler = (0, 0, 0)
            pb.location = (0, 0, 0)
        pose_fn(arm_obj.pose.bones, f)
        for pb in arm_obj.pose.bones:
            pb.keyframe_insert("rotation_euler", frame=f)
            pb.keyframe_insert("location", frame=f)
    return act


def run_pose(pbs, f):
    ph = 2 * math.pi * (f - 1) / 20.0
    pbs["Spine1"].rotation_euler.x = 0.15 * math.sin(ph)
    pbs["Tail1"].rotation_euler.x = 0.25 * math.sin(ph - 0.6)
    pbs["Tail2"].rotation_euler.x = 0.3 * math.sin(ph - 1.2)
    pbs["Tail3"].rotation_euler.x = 0.35 * math.sin(ph - 1.8)
    for leg, off in (("FrontL_Upper", 0), ("FrontR_Upper", 0.3), ("BackL_Upper", math.pi), ("BackR_Upper", math.pi + 0.3)):
        pbs[leg].rotation_euler.x = 0.6 * math.sin(ph + off)


def build(out_dir):
    scene = reset_scene()
    arm = build_armature(scene)
    body = build_mesh(scene)
    skin(body, arm)
    run = key_action(arm, "Run", range(1, 21), run_pose)
    arm.animation_data.action = run
    scene.frame_start, scene.frame_end = 1, 20
    tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
    report = {
        "blender_version": bpy.app.version_string,
        "bones": [b.name for b in arm.data.bones],
        "bone_count": len(arm.data.bones),
        "mesh_triangles": tris,
        "materials": [m.name for m in body.data.materials],
        "actions": {a.name: list(a.frame_range) for a in bpy.data.actions},
    }
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out_dir, "squirrel_test.blend"))
        with open(os.path.join(out_dir, "squirrel_test_rig.json"), "w") as fh:
            json.dump(report, fh, indent=2)
    return arm, body, report


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="build/blender")
    args = ap.parse_args(sys.argv[1:] if "--" not in sys.argv else sys.argv[sys.argv.index("--") + 1 :])
    _arm, _body, rep = build(args.out)
    print(json.dumps(rep, indent=2))
