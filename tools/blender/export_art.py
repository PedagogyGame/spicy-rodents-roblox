"""S7/S8 art export (headless bpy 5.2.x): one clip as JSON for tools/anim, a textured rigid prop as FBX.

  /root/.cache/spicy-rodents/venv/bin/python -I tools/blender/export_art.py --out build/art

Writes into --out:
  squirrel_Run.clip.json   per-bone local CFrames per keyframe (format "spicy-clip/1", below)
  squirrel_Run.fbx         the S12 test rig with its Run action (D11 keeps the FBX as the fallback)
  hollow_log.fbx           S8a prop: hollow-log blockout, < 2k tris, colour + normal + roughness PNGs embedded
  hollow_log_{color,normal,roughness}.png
  export_art.json          report (tris, sizes, bones, keyframes)

Axes (D21). Blender: +Z up, model front -Y. Roblox: +Y up, front -Z (LookVector). The proper rotation
M maps Blender (x, y, z) to Roblox (-x, z, y); FBX export uses the same mapping (axis_forward="Z",
axis_up="Y" sends Blender +Y to +Z), so clips and meshes agree. 1 Blender unit = 1 stud.

Clip convention ("spicy-clip/1"). For every bone and keyframe, `poses[bone]` is the 12 numbers of a
Roblox CFrame (x, y, z, R00..R22, row-major) giving the joint's local delta from its rest pose,
expressed in a joint frame that is axis-aligned with the model (Roblox axes) and sits at the bone
head. That is exactly Pose.CFrame / Motor6D.Transform for a puppet whose C0/C1 have identity
rotation (our placeholders). A skinned rig whose Roblox Bones carry a rotated rest frame needs the
conjugation by that rest rotation; `bones[i].restRotation` (Roblox axes) is kept for that.
"""
import argparse
import json
import math
import os
import sys

import bpy  # noqa: E402
import bmesh  # noqa: E402,F401
from mathutils import Matrix, Vector  # noqa: E402

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import squirrel_test_rig  # noqa: E402

M = Matrix(((-1, 0, 0), (0, 0, 1), (0, 1, 0)))  # Blender -> Roblox axes (det +1)
MT = M.transposed()


def r6(v):
    return round(float(v), 6) + 0.0  # + 0.0 turns -0.0 into 0.0


def cframe12(rot3, loc):
    return [r6(loc[0]), r6(loc[1]), r6(loc[2])] + [r6(rot3[i][j]) for i in range(3) for j in range(3)]


def export_clip(arm, action_name, out_dir, rig_id="squirrel", markers=()):
    scene = bpy.context.scene
    act = bpy.data.actions[action_name]
    arm.animation_data.action = act
    f0, f1 = (int(round(x)) for x in act.frame_range)
    fps = scene.render.fps
    bones = []
    for b in arm.data.bones:
        rest = b.matrix_local.to_3x3()
        bones.append({
            "name": b.name,
            "parent": b.parent.name if b.parent else None,
            "deform": bool(b.use_deform),
            "head": [r6(c) for c in (M @ b.head_local)],
            "restRotation": [r6(x) for row in (M @ rest @ MT) for x in row],
        })

    def sample(frame):
        scene.frame_set(frame)
        poses = {}
        for pb in arm.pose.bones:
            rest = pb.bone.matrix_local.to_3x3()
            basis = pb.matrix_basis
            rot_al = rest @ basis.to_3x3() @ rest.transposed()
            loc_al = rest @ basis.to_translation()
            poses[pb.name] = cframe12(M @ rot_al @ MT, M @ loc_al)
        return poses

    keyframes = [{"time": r6((f - f0) / fps), "frame": f, "poses": sample(f)} for f in range(f0, f1 + 1)]
    # Loop closure: the cycle is (f1 - f0 + 1) frames long, so repeat the first pose one frame later.
    keyframes.append({"time": r6((f1 + 1 - f0) / fps), "frame": f1 + 1, "poses": keyframes[0]["poses"]})
    clip = {
        "format": "spicy-clip/1",
        "rig": rig_id,
        "clip": action_name,
        "fps": fps,
        "loop": True,
        "priority": "Movement",
        "rootPart": "RootPart",
        "frameConvention": "joint-local delta, axis-aligned joint frame at the bone head, Roblox axes (-Z forward, +Y up), studs",
        "bones": bones,
        "keyframes": keyframes,
        "markers": [{"time": r6(t), "name": n, "value": v} for t, n, v in markers],
    }
    path = os.path.join(out_dir, f"{rig_id}_{action_name}.clip.json")
    with open(path, "w") as fh:
        json.dump(clip, fh, separators=(",", ":"))
    return path, clip


def fbx_export(path, objects, **kw):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.fbx(
        filepath=path,
        use_selection=True,
        axis_forward="Z",
        axis_up="Y",
        apply_unit_scale=True,
        apply_scale_options="FBX_SCALE_ALL",
        **kw,
    )


# ---- S8a prop -----------------------------------------------------------------------------------

def noise(i, j, seed=0.0):
    return math.sin(i * 1.7 + seed) * 0.5 + math.sin(j * 2.3 + i * 0.7 + seed * 2.0) * 0.3 + math.sin(i * 5.1 - j * 3.3) * 0.2


def build_log(length=4.0, r_out=0.8, r_in=0.55, segs=32, rings=9):
    """A hollow log along the model's forward axis (Blender Y): a bark tube with an inner bore and
    two end annuli. UV seam duplicated. Returns the object (about 32*(2*(rings-1)+2)*2 tris)."""
    verts, uvs_per_vert, faces = [], [], []

    def ring(radius, y, v, jitter, j):
        idx = []
        for i in range(segs + 1):
            a = 2 * math.pi * (i % segs) / segs
            r = radius * (1.0 + jitter * noise(i % segs, j))
            verts.append((r * math.cos(a), y, r * math.sin(a) + r_out))  # sits on the ground (z = 0)
            uvs_per_vert.append((i / segs, v))
            idx.append(len(verts) - 1)
        return idx

    outer = [ring(r_out, -length / 2 + length * j / (rings - 1), j / (rings - 1) * 0.5, 0.05, j) for j in range(rings)]
    inner = [ring(r_in, -length / 2 + length * j / (rings - 1), 0.5 + j / (rings - 1) * 0.5, 0.02, j + 50) for j in range(rings)]
    for strip in range(rings - 1):
        a, b = outer[strip], outer[strip + 1]
        c, d = inner[strip], inner[strip + 1]
        for i in range(segs):
            faces.append((a[i], a[i + 1], b[i + 1], b[i]))  # bark, outward
            faces.append((c[i], d[i], d[i + 1], c[i + 1]))  # bore, inward
    for o, n in ((outer[0], inner[0]), (outer[-1], inner[-1])):
        for i in range(segs):
            faces.append((o[i], n[i], n[i + 1], o[i + 1]))
    me = bpy.data.meshes.new("HollowLog")
    me.from_pydata(verts, [], faces)
    me.update()
    # End caps face -Y at y=-L/2 and +Y at y=+L/2: make all normals point outward.
    import bmesh as _bm
    bm = _bm.new()
    bm.from_mesh(me)
    _bm.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    uv = me.uv_layers.new(name="UVMap")
    for loop in me.loops:
        uv.data[loop.index].uv = uvs_per_vert[loop.vertex_index]
    for p in me.polygons:
        p.use_smooth = True
    obj = bpy.data.objects.new("HollowLog", me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def make_image(name, size, fn, out_dir, non_color=False):
    img = bpy.data.images.new(name, size, size, alpha=False)
    px = [0.0] * (size * size * 4)
    for y in range(size):
        for x in range(size):
            r, g, b = fn(x / size, y / size)
            k = (y * size + x) * 4
            px[k : k + 4] = (r, g, b, 1.0)
    img.pixels = px
    if non_color:
        img.colorspace_settings.name = "Non-Color"
    path = os.path.join(out_dir, f"{name}.png")
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    return img, path


def bark_height(u, v):
    return 0.5 + 0.5 * math.sin(u * 2 * math.pi * 12 + math.sin(v * 2 * math.pi * 3) * 1.5)


def texture_log(obj, out_dir, size=256):
    color_img, cpath = make_image(
        "hollow_log_color", size,
        lambda u, v: ((0.20 + 0.12 * bark_height(u, v), 0.12 + 0.07 * bark_height(u, v), 0.06)) if v < 0.5
        else (0.55 + 0.1 * math.sin(v * 80), 0.40 + 0.08 * math.sin(v * 80), 0.25),
        out_dir,
    )

    def nrm(u, v):
        e = 1.0 / size
        dx = (bark_height(u + e, v) - bark_height(u - e, v)) * 0.15 / (2 * e) / 12
        return (0.5 - 0.5 * dx, 0.5, 0.5 + 0.5 * max(0.0, 1 - abs(dx)))

    normal_img, npath = make_image("hollow_log_normal", size, nrm, out_dir, non_color=True)
    rough_img, rpath = make_image("hollow_log_roughness", size, lambda u, v: (0.6 + 0.35 * bark_height(u, v),) * 3, out_dir, non_color=True)
    mat = bpy.data.materials.new("LogBark")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    tc = nt.nodes.new("ShaderNodeTexImage")
    tc.image = color_img
    nt.links.new(tc.outputs["Color"], bsdf.inputs["Base Color"])
    tr = nt.nodes.new("ShaderNodeTexImage")
    tr.image = rough_img
    nt.links.new(tr.outputs["Color"], bsdf.inputs["Roughness"])
    tn = nt.nodes.new("ShaderNodeTexImage")
    tn.image = normal_img
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    obj.data.materials.append(mat)
    return [cpath, npath, rpath]


def main(out_dir):
    os.makedirs(out_dir, exist_ok=True)
    arm, body, rig_report = squirrel_test_rig.build(None)
    clip_path, clip = export_clip(arm, "Run", out_dir, markers=((0.0, "Commit", "stride"), (10 / 30, "Recover", "stride")))
    run_fbx = os.path.join(out_dir, "squirrel_Run.fbx")
    fbx_export(run_fbx, [arm, body], object_types={"ARMATURE", "MESH"}, add_leaf_bones=False, bake_anim=True,
               bake_anim_use_all_actions=False, bake_anim_use_nla_strips=False)

    # The prop goes into its own empty scene so nothing of the rig leaks into the FBX.
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = "NONE"
    log = build_log()
    pngs = texture_log(log, out_dir)
    log_fbx = os.path.join(out_dir, "hollow_log.fbx")
    fbx_export(log_fbx, [log], object_types={"MESH"}, path_mode="COPY", embed_textures=True)
    tris = sum(len(p.vertices) - 2 for p in log.data.polygons)
    dims = M @ Vector(log.dimensions)
    report = {
        "blender_version": bpy.app.version_string,
        "clip": {"path": clip_path, "bones": len(clip["bones"]), "keyframes": len(clip["keyframes"]),
                 "duration": clip["keyframes"][-1]["time"], "markers": len(clip["markers"]),
                 "pose_names": [b["name"] for b in clip["bones"]]},
        "rig": {"bones": rig_report["bone_count"], "tris": rig_report["mesh_triangles"], "fbx": run_fbx,
                "fbx_bytes": os.path.getsize(run_fbx)},
        "hollow_log": {"fbx": log_fbx, "fbx_bytes": os.path.getsize(log_fbx), "tris": tris,
                       "size_roblox_axes": [r6(abs(c)) for c in dims], "textures": pngs},
    }
    with open(os.path.join(out_dir, "export_art.json"), "w") as fh:
        json.dump(report, fh, indent=2)
    return report


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="build/art")
    args = ap.parse_args(sys.argv[1:] if "--" not in sys.argv else sys.argv[sys.argv.index("--") + 1 :])
    print(json.dumps(main(args.out), indent=2))
