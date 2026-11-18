"""The owner's sewer modules -> FBX for Roblox, plus the manifest the bake and the art loader read.

  /root/.cache/spicy-rodents/venv/bin/python -I tools/blender/sewers/export_modules.py [--out build/art/sewers]

Inputs (the owner's delivery, brief addendum D12; used as delivered, at one stud a metre as data/sewers.json says):
  docs/reference/store_roofs/art_pack/GLB/01_Brick_Sewer_Passage.glb        12 m of arched brick passage
  docs/reference/store_roofs/art_pack/GLB/02_Four_Way_Sewer_Junction.glb    the four-way junction (12 x 12 m)
  docs/reference/store_roofs/art_pack/GLB/03_Concrete_Maintenance_Tunnel.glb 12 m of dry maintenance tunnel
  docs/reference/store_roofs/art_pack/GLB/Additions/Dry_Side_Marker.glb     the "Dry Side / Mind Your Paws" plaque

Variants (what each upload holds; every mesh keeps its name, geometry, UVs and material):
  brick        01 without its channel handrails and their footplates (they stand at 0.99 m off the axis, inside the
               squirrel's lane on either walkway: listed as left out)
  brickPlain   brick without the footbridge, the valve and the "S-01" label: the passage repeats every 12 studs
               under Bowl Lane, and a footbridge every 12 studs reads as a pattern; the bake puts `brick` every
               fourth module and `brickPlain` between
  junction     02 as delivered
  dry          03 as delivered (pump set, service door, panel, valve, the plaque)
  dryPlain     03 without the pump set, door, panel, valve, sign and plaque: 30 modules under the river, the full one
               every fifth
  marker       the standalone plaque (the bake hangs one at the foot of each culvert ladder)

Frames. glTF (gx, gy, gz) -> Blender (gx, -gz, gy) on import; the FBX export (axis_forward Z, axis_up Y, 1 Blender
unit = 1 stud: HANDOFF rule 9) gives Roblox (-bx, bz, by) = (-gx, gy, -gz). That is the module's own frame:
X across, Y up from the walkway top, Z along the passage, origin at the module's centre on the walkway top. Every
number in the manifest is in that frame, in studs.

The lane check. For each module and each lane the squirrel can run (Shared/Routes/Enclosure.BODY: 1.6 wide, 1.7
high, its feet 0.15 over the walkway, the route `routeOffset` off the axis: data/sewers.json), every triangle of
every mesh is tested against the lane's box (exact triangle-box separating axes). A lane with no triangle in it is
"clear"; the bake turns each module so the route runs a clear lane and tests/unit/sewers_bake.spec.luau holds it
to that.

Outputs in --out: <variant>.fbx (embedded textures), manifest.json (meshes: name, centre, size, tris, material;
lanes: clear or the meshes in them; lights and ports from his metadata; the left-out meshes and why; checksums).
"""
import argparse
import hashlib
import json
import os
import sys

import bpy  # noqa: I001 (bpy first: it provides mathutils)
import numpy as np
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
PACK = os.path.join(ROOT, "docs", "reference", "store_roofs", "art_pack")
GLB = {
    "01": os.path.join(PACK, "GLB", "01_Brick_Sewer_Passage.glb"),
    "02": os.path.join(PACK, "GLB", "02_Four_Way_Sewer_Junction.glb"),
    "03": os.path.join(PACK, "GLB", "03_Concrete_Maintenance_Tunnel.glb"),
    "marker": os.path.join(PACK, "GLB", "Additions", "Dry_Side_Marker.glb"),
}
META = {
    "01": os.path.join(PACK, "Metadata", "01_Brick_Sewer_Passage.json"),
    "02": os.path.join(PACK, "Metadata", "02_Four_Way_Sewer_Junction.json"),
    "03": os.path.join(PACK, "Metadata", "03_Concrete_Maintenance_Tunnel.json"),
}
SECTIONS = os.path.join(ROOT, "data", "sewers.json")

HANDRAILS = ("Safety_Handrails", "Safety_Rail_Footplates")
VARIANTS = {
    "brick": {"src": "01", "drop": HANDRAILS,
              "why": "the channel handrails and footplates stand 0.99 off the axis, in the squirrel's lane (0.8..2.4)"},
    "brickPlain": {"src": "01", "drop": HANDRAILS + ("Bridge_", "Valve_", "Sign_"),
                   "why": "the plain repeat: no footbridge, valve or label (a footbridge every 12 studs reads as a "
                          "pattern), and no handrails (in the lane)"},
    "junction": {"src": "02", "drop": (), "why": ""},
    "dry": {"src": "03", "drop": (), "why": ""},
    "dryPlain": {"src": "03", "drop": ("Pump_", "Service_Door_", "Electric_Panel", "Valve_", "Sign_SERVICE", "SEWER_"),
                 "why": "the plain repeat under the river: no pump set, service door, panel, valve, sign or plaque"},
    "marker": {"src": "marker", "drop": (), "why": ""},
}
FBX_KW = dict(
    use_selection=True,
    object_types={"MESH"},
    axis_forward="Z",
    axis_up="Y",
    apply_unit_scale=True,
    apply_scale_options="FBX_SCALE_ALL",
    mesh_smooth_type="FACE",
    use_mesh_modifiers=False,
    use_tspace=False,
    path_mode="COPY",
    embed_textures=True,
)
LIFT, BODY_W, BODY_H = 0.15, 1.6, 1.7  # Enclosure.BODY and BakedWorld.clearance's lift
REACH = 6.0  # half a module's length


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        h.update(fh.read())
    return h.hexdigest()


def r4(v):
    return round(v + 0.0, 4)


def to_roblox(v):
    """Blender (x, y, z) -> the module frame (-x, z, y)."""
    return [r4(-v[0]), r4(v[2]), r4(v[1])]


def gltf_to_roblox(p):
    return [r4(-p[0]), r4(p[1]), r4(-p[2])]


def srgb(c):
    def one(x):
        x = max(0.0, min(1.0, x))
        return x * 12.92 if x <= 0.0031308 else 1.055 * x ** (1 / 2.4) - 0.055

    return [int(round(one(c[i]) * 255)) for i in range(3)]


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = "NONE"


def bake_transforms(objs):
    """World transforms into the vertices: every mesh at the origin, unparented, single-user."""
    for o in objs:
        if o.data.users > 1:
            o.data = o.data.copy()
    for o in objs:
        mw = o.matrix_world.copy()
        o.data.transform(mw)
        if mw.determinant() < 0:
            o.data.flip_normals()
        o.data.update()
    for o in objs:
        o.parent = None
        o.matrix_world = Matrix.Identity(4)
        o.data.name = o.name
    for o in list(bpy.context.scene.objects):
        if o.type != "MESH":
            bpy.data.objects.remove(o, do_unlink=True)


def save_images(tmp):
    """The GLB's packed images as files beside the FBX, so the exporter can embed them."""
    os.makedirs(tmp, exist_ok=True)
    for i, img in enumerate(bpy.data.images):
        if img.packed_file is None:
            continue
        ext = {"PNG": ".png", "JPEG": ".jpg"}.get(img.file_format, ".png")
        safe = "".join(ch if ch.isalnum() or ch in "-_" else "_" for ch in img.name)
        path = os.path.join(tmp, f"{i:02d}_{safe}{ext}")
        with open(path, "wb") as fh:
            fh.write(img.packed_file.data)
        img.unpack(method="REMOVE")
        img.filepath = path
        img.reload()


def material_info(mat):
    info = {"material": mat.name if mat else None, "colour": [163, 162, 165], "texture": None}
    if not mat or not mat.node_tree:
        return info
    bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if not bsdf:
        return info
    info["colour"] = srgb(bsdf.inputs["Base Color"].default_value)
    s = bsdf.inputs["Base Color"]
    if s.is_linked and getattr(s.links[0].from_node, "image", None):
        info["texture"] = s.links[0].from_node.image.name
    return info


def triangles(o):
    """The mesh's triangles in the module frame, (N, 3, 3)."""
    me = o.data
    me.calc_loop_triangles()
    co = np.array([to_roblox(v.co) for v in me.vertices], dtype=np.float64).reshape(-1, 3)
    idx = np.array([t.vertices[:] for t in me.loop_triangles], dtype=np.int64).reshape(-1, 3)
    return co[idx]


def tri_box(tris, lo, hi):
    """Which triangles overlap the axis-aligned box [lo, hi] (separating axes: Akenine-Moller)."""
    if len(tris) == 0:
        return np.zeros(0, dtype=bool)
    c = (np.array(lo) + np.array(hi)) / 2
    h = (np.array(hi) - np.array(lo)) / 2
    v = tris - c
    hit = np.ones(len(v), dtype=bool)
    for k in range(3):
        hit &= (v[:, :, k].min(axis=1) <= h[k]) & (v[:, :, k].max(axis=1) >= -h[k])
    e = [v[:, 1] - v[:, 0], v[:, 2] - v[:, 1], v[:, 0] - v[:, 2]]
    n = np.cross(e[0], e[1])
    d = np.einsum("ij,ij->i", n, v[:, 0])
    r = np.abs(n) @ h
    hit &= np.abs(d) <= r + 1e-9
    axes = np.eye(3)
    for ei in e:
        for a in axes:
            ax = np.cross(ei, a)
            p = np.einsum("ij,ikj->ik", ax, v)
            rad = np.abs(ax) @ h
            hit &= ~((p.min(axis=1) > rad + 1e-9) | (p.max(axis=1) < -rad - 1e-9))
    return hit


def lanes_for(variant, sections):
    """The boxes the squirrel's body sweeps through a module (module frame)."""
    if variant == "marker":
        return {}
    y = (LIFT, BODY_H)
    if variant.startswith("dry"):
        off = sections["dry"]["routeOffset"]
        return {"centre": [(off - BODY_W / 2, y[0], -REACH), (off + BODY_W / 2, y[1], REACH)]}
    off = sections["brick"]["routeOffset"]
    a, b = off - BODY_W / 2, off + BODY_W / 2
    lanes = {"+x": [(a, y[0], -REACH), (b, y[1], REACH)], "-x": [(-b, y[0], -REACH), (-a, y[1], REACH)]}
    if variant == "junction":
        lanes["+z"] = [(-REACH, y[0], a), (REACH, y[1], b)]
        lanes["-z"] = [(-REACH, y[0], -b), (REACH, y[1], -a)]
    return lanes


def export(path, objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.fbx(filepath=path, **FBX_KW)
    return os.path.getsize(path)


def build(variant, spec, out, sections):
    reset()
    bpy.ops.import_scene.gltf(filepath=GLB[spec["src"]])
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    dropped = sorted(o.name for o in objs if o.name.startswith(spec["drop"])) if spec["drop"] else []
    for o in list(objs):
        if o.name in dropped:
            bpy.data.objects.remove(o, do_unlink=True)
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    bake_transforms(objs)
    save_images(os.path.join(out, "textures", variant))
    meshes, tris_by = [], {}
    for o in sorted(objs, key=lambda o: o.name):
        t = triangles(o)
        tris_by[o.name] = t
        lo, hi = t.reshape(-1, 3).min(axis=0), t.reshape(-1, 3).max(axis=0)
        mats = [m for m in o.data.materials if m]
        info = material_info(mats[0] if mats else None)
        rec = {
            "name": o.name,
            "centre": [r4(x) for x in (lo + hi) / 2],
            "size": [r4(x) for x in hi - lo],
            "tris": int(len(t)),
            "material": info["material"],
            "colour": info["colour"],
        }
        if info["texture"]:
            rec["texture"] = info["texture"]
        meshes.append(rec)
    lanes = {}
    for name, (lo, hi) in lanes_for(variant, sections).items():
        blockers = sorted(n for n, t in tris_by.items() if tri_box(t, lo, hi).any())
        lanes[name] = {"box": [list(lo), list(hi)], "clear": not blockers, "blockers": blockers}
    fbx = os.path.join(out, f"{variant}.fbx")
    nbytes = export(fbx, objs)
    return {
        "source": spec["src"],
        "fbx": f"{variant}.fbx",
        "fbxBytes": nbytes,
        "tris": int(sum(m["tris"] for m in meshes)),
        "leftOut": dropped,
        "why": spec["why"],
        "lanes": lanes,
        "meshes": meshes,
    }


def metadata(src):
    with open(META[src]) as fh:
        m = json.load(fh)
    return {
        "footprint": m["footprint_m"],
        "ports": [{"name": c["name"], "at": gltf_to_roblox(c["position_m"]), "outward": gltf_to_roblox(c["outward"]),
                   "spring": c["spring_height_m"], "crown": c["crown_height_m"]} for c in m["connectors"]],
        "lights": [{"name": L["name"], "at": gltf_to_roblox(L["position_m"]), "colour": L["color_hex"],
                    "range": L["suggested_range_m"]} for L in m["suggested_lights"]],
        "colliders": [{"name": c["name"], "centre": gltf_to_roblox(c["center_m"]), "size": c["size_m"],
                       "yaw": r4(c["rotation_y_radians"]), "purpose": c["purpose"]} for c in m["collision_boxes"]],
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(ROOT, "build", "art", "sewers"))
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else sys.argv[1:]
    a = ap.parse_args(argv)
    out = os.path.abspath(a.out)
    os.makedirs(out, exist_ok=True)
    with open(SECTIONS) as fh:
        sections = json.load(fh)["sections"]
    modules = {}
    for variant, spec in VARIANTS.items():
        modules[variant] = build(variant, spec, out, sections)
        m = modules[variant]
        lanes = ", ".join(f"{k} {'clear' if v['clear'] else 'BLOCKED by ' + '/'.join(v['blockers'])}"
                          for k, v in m["lanes"].items())
        print(f"{variant}: {len(m['meshes'])} meshes, {m['tris']} tris, {m['fbxBytes']} B; left out {len(m['leftOut'])}; {lanes}",
              flush=True)
    manifest = {
        "format": "spicy-sewer-art/1",
        "units": "studs (one per metre of the art); the module frame: X across, Y up from the walkway top, Z along",
        "studsPerMetre": 1.0,
        "modules": modules,
        "metadata": {k: metadata(k) for k in ("01", "02", "03")},
        "sources": {k: {"file": os.path.relpath(p, ROOT), "sha256": sha(p)} for k, p in GLB.items()},
    }
    with open(os.path.join(out, "manifest.json"), "w") as fh:
        json.dump(manifest, fh, indent=1)


if __name__ == "__main__":
    main()
