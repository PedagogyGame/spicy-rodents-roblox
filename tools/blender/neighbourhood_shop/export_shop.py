"""The owner's Neighbourhood Shop and gable roof -> FBX for Roblox, plus the manifest the bake and the loader read.

  /root/.cache/spicy-rodents/venv/bin/python -I tools/blender/neighbourhood_shop/export_shop.py \
      [--out build/art/neighbourhood_shop]

Inputs (the owner's delivery, used as delivered; brief addendum D12):
  docs/reference/store_roofs/art_pack/GLB/04_Offbeat_Shop_Interior.glb      the shop: 355 meshes, metres, Y up, front -Z
  docs/reference/store_roofs/art_pack/Metadata/04_Offbeat_Shop_Interior.json its colliders and entrance node
  docs/reference/store_roofs/roof_rafter_kit/GLB/02_Full_Gable_Roof_14m.glb the finished 14 m gable roof (90 meshes)
  docs/reference/store_roofs/roof_rafter_kit/GLB/04_Roof_Collider_Proxies.glb its slope and perch proxies

What changes on the way, and nothing else: every mesh keeps its name, geometry, UVs and material; its world
transform is applied to the vertices (so each MeshPart arrives unrotated, centred on its own bounding box) and
the whole scene is scaled to studs, SCALE studs per metre. The roof is turned a quarter turn so its ridge runs
along the shop's 14 m width with the chimney on the back slope, and stretched ROOF_SPAN across its 10 m span
(and height, so the pitch is his) and ROOF_RUN along the ridge, to cover the shop's 12 m depth.

Frames. glTF (gx, gy, gz) -> Blender (gx, -gz, gy) on import; the FBX export (axis_forward Z, axis_up Y, 1 Blender
unit = 1 stud: HANDOFF rule 9) gives Roblox (-gx, gy, -gz) * SCALE. That is the venue's own frame at yaw 0
(Shared/Attractions/AlleyLayout: X across, Y up, D = -Z into the building): X = -gx, Y = gy, D = gz, with the
origin at the centre of the shop's floor. Every number in the manifest is in that frame, in studs.

Outputs in --out:
  shop.fbx    all 355 shop meshes (embedded textures)       proof.fbx  the five cafe stools only (the upload proof)
  roof.fbx    the 90 roof meshes                             manifest.json  meshes (name, centre, size, tris,
  material, colour, texture, glass), lamps, front openings, colliders (his metadata, plus two walls his metadata
  leaves out), roof slope colliders, the entrance node, scale and roof transform, source checksums.
"""
import argparse
import hashlib
import json
import math
import os
import sys

import bpy  # noqa: I001 (bpy first: it provides bmesh and mathutils)
import bmesh
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
REF = os.path.join(ROOT, "docs", "reference", "store_roofs")
SHOP_GLB = os.path.join(REF, "art_pack", "GLB", "04_Offbeat_Shop_Interior.glb")
SHOP_META = os.path.join(REF, "art_pack", "Metadata", "04_Offbeat_Shop_Interior.json")
ROOF_GLB = os.path.join(REF, "roof_rafter_kit", "GLB", "02_Full_Gable_Roof_14m.glb")
ROOF_COLLIDERS_GLB = os.path.join(REF, "roof_rafter_kit", "GLB", "04_Roof_Collider_Proxies.glb")

SCALE = 3.0  # studs per metre: a person (5.5 st) is 1.83 m; counters 3.5 st, bar stools 2.5, the door 9 high
ROOF_SPAN = 1.25  # his roof spans 10 m (11.5 with gutters); the shop is 12.5 m deep with its walls
ROOF_RUN = 1.04  # his roof runs 14.94 m; the shop is 14.5 m wide with its walls, 15.2 with the shell
PROOF_PREFIX = "CAFE_Stool_"
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


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        h.update(fh.read())
    return h.hexdigest()


def r4(v):
    return round(v + 0.0, 4)


def to_roblox(v):
    """Blender (x, y, z) -> Roblox (-x, z, y): the FBX export's own mapping."""
    return [r4(-v[0]), r4(v[2]), r4(v[1])]


def gltf_to_roblox(p):
    """A point in the owner's glTF metres -> the venue frame in studs (X = -gx, Y = gy, -D... as Roblox Z = -gz)."""
    return [r4(-p[0] * SCALE), r4(p[1] * SCALE), r4(-p[2] * SCALE)]


def srgb(c):
    def one(x):
        x = max(0.0, min(1.0, x))
        return x * 12.92 if x <= 0.0031308 else 1.055 * x ** (1 / 2.4) - 0.055

    return [int(round(one(c[i]) * 255)) for i in range(3)]


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = "NONE"


def import_glb(path):
    bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in bpy.context.scene.objects if o.type == "MESH"]


def bake_transforms(objs, extra):
    """World transform (and `extra`) into the vertices; every object at the origin, unparented, single-user."""
    for o in objs:
        if o.data.users > 1:
            o.data = o.data.copy()
    for o in objs:
        mw = extra @ o.matrix_world
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


def bounds(o):
    xs = [v.co for v in o.data.vertices]
    lo = Vector((min(v.x for v in xs), min(v.y for v in xs), min(v.z for v in xs)))
    hi = Vector((max(v.x for v in xs), max(v.y for v in xs), max(v.z for v in xs)))
    return lo, hi


def box_roblox(lo, hi):
    """A Blender AABB -> Roblox centre and size."""
    c = (lo + hi) / 2
    return to_roblox(c), [r4(hi.x - lo.x), r4(hi.z - lo.z), r4(hi.y - lo.y)]


def islands(o):
    """Connected pieces of a mesh, each as a Roblox AABB {centre, size}."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)  # flat shading splits every face apart
    bm.verts.ensure_lookup_table()
    seen = set()
    out = []
    for v in bm.verts:
        if v.index in seen:
            continue
        stack, comp = [v], []
        seen.add(v.index)
        while stack:
            a = stack.pop()
            comp.append(a.co.copy())
            for e in a.link_edges:
                b = e.other_vert(a)
                if b.index not in seen:
                    seen.add(b.index)
                    stack.append(b)
        lo = Vector((min(p.x for p in comp), min(p.y for p in comp), min(p.z for p in comp)))
        hi = Vector((max(p.x for p in comp), max(p.y for p in comp), max(p.z for p in comp)))
        c, s = box_roblox(lo, hi)
        out.append({"centre": c, "size": s})
    bm.free()
    out.sort(key=lambda b: (b["centre"][0], b["centre"][2], b["centre"][1]))
    return out


def material_info(mat):
    info = {"material": mat.name if mat else None, "colour": [163, 162, 165], "texture": None, "alpha": 1.0}
    if not mat or not mat.node_tree:
        return info
    bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if not bsdf:
        return info
    info["colour"] = srgb(bsdf.inputs["Base Color"].default_value)
    s = bsdf.inputs["Base Color"]
    if s.is_linked and getattr(s.links[0].from_node, "image", None):
        info["texture"] = s.links[0].from_node.image.name
    info["alpha"] = round(bsdf.inputs["Alpha"].default_value, 3)
    return info


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


def export(path, objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.fbx(filepath=path, **FBX_KW)
    return os.path.getsize(path)


def mesh_records(objs):
    recs = []
    for o in sorted(objs, key=lambda o: o.name):
        lo, hi = bounds(o)
        c, s = box_roblox(lo, hi)
        o.data.calc_loop_triangles()
        mats = [m for m in o.data.materials if m]
        info = material_info(mats[0] if mats else None)
        rec = {
            "name": o.name,
            "centre": c,
            "size": s,
            "tris": len(o.data.loop_triangles),
            "material": info["material"],
            "colour": info["colour"],
        }
        if info["texture"]:
            rec["texture"] = info["texture"]
        if info["alpha"] < 0.99:
            rec["alpha"] = info["alpha"]
        if len(mats) > 1:
            rec["materials"] = [m.name for m in mats]
        recs.append(rec)
    return recs


def oriented_box(o):
    """A box mesh -> Roblox centre, size and rotation columns (right = the run along X, up, back).

    The box's three axes are its face normals (a triangulated box has diagonal edges, so edges will not do);
    each size is the spread of the corners along its axis."""
    o.data.calc_loop_triangles()
    axes = []
    for t in o.data.loop_triangles:
        n = Vector(to_roblox(t.normal)).normalized()
        if all(abs(n.dot(a)) < 0.99 for a in axes):
            axes.append(n)
    assert len(axes) == 3, (o.name, len(axes))
    pts = [Vector(to_roblox(v.co)) for v in o.data.vertices]
    X = max(axes, key=lambda a: abs(a.x))
    rest = [a for a in axes if a is not X]
    Y = max(rest, key=lambda a: abs(a.y))
    X = X if X.x > 0 else -X
    Y = Y if Y.y > 0 else -Y
    Z = X.cross(Y)
    size, centre = [], Vector()
    for a in (X, Y, Z):
        ts = [p.dot(a) for p in pts]
        size.append(r4(max(ts) - min(ts)))
        centre += a * ((max(ts) + min(ts)) / 2)
    return {
        "name": o.name,
        "centre": [r4(centre.x), r4(centre.y), r4(centre.z)],
        "size": size,
        "right": [r4(X.x), r4(X.y), r4(X.z)],
        "up": [r4(Y.x), r4(Y.y), r4(Y.z)],
        "back": [r4(Z.x), r4(Z.y), r4(Z.z)],
    }


def roof_matrix():
    rot = Matrix.Rotation(-math.pi / 2, 4, "Z")  # run (Blender y) -> Blender x; the chimney onto the back slope
    s = SCALE
    stretch = Matrix.Diagonal((ROOF_RUN * s, ROOF_SPAN * s, ROOF_SPAN * s, 1.0))
    return stretch @ rot


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(ROOT, "build", "art", "neighbourhood_shop"))
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else sys.argv[1:]
    a = ap.parse_args(argv)
    out = os.path.abspath(a.out)
    os.makedirs(out, exist_ok=True)

    # ---- the shop
    reset()
    bpy.ops.import_scene.gltf(filepath=SHOP_GLB)
    empties = {o.name: o.matrix_world.translation.copy() for o in bpy.context.scene.objects if o.type == "EMPTY"}
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    bake_transforms(objs, Matrix.Scale(SCALE, 4))
    save_images(os.path.join(out, "textures"))
    shop_meshes = mesh_records(objs)
    by = {o.name: o for o in objs}
    lamps = []
    for name in ("LIGHT_Diffusers",):
        for b in islands(by[name]):
            lamps.append({"kind": "pendant", "at": b["centre"], "size": b["size"]})
    for b in islands(by["OFFICE_DeskLampShade"]):
        lamps.append({"kind": "desk", "at": b["centre"], "size": b["size"]})
    front = {}
    for name in ("FRONT_Piers", "FRONT_WindowSills", "FRONT_WindowHeader", "FRONT_LeftSill", "FRONT_LeftHeader",
                 "DOOR_OpenFrame", "WALL_OfficeSide", "TRIM_PassagePosts"):
        front[name] = islands(by[name])
    fbx_bytes = export(os.path.join(out, "shop.fbx"), objs)
    proof = [o for o in objs if o.name.startswith(PROOF_PREFIX)]
    proof_bytes = export(os.path.join(out, "proof.fbx"), proof)
    entrance = None
    if "PORT_ShopEntrance" in empties:
        p = empties["PORT_ShopEntrance"] * SCALE
        entrance = to_roblox(p)

    with open(SHOP_META) as fh:
        meta = json.load(fh)
    colliders = []
    for c in meta["colliders"]:
        size = [r4(c["size"][0] * SCALE), r4(c["size"][1] * SCALE), r4(c["size"][2] * SCALE)]
        colliders.append({"name": c["name"], "centre": gltf_to_roblox(c["center"]), "size": size, "from": "metadata"})

    # ---- the roof
    reset()
    roof = import_glb(ROOF_GLB)
    bake_transforms(roof, roof_matrix())
    roof_meshes = mesh_records(roof)
    lo = Vector((min(bounds(o)[0].x for o in roof), min(bounds(o)[0].y for o in roof), min(bounds(o)[0].z for o in roof)))
    hi = Vector((max(bounds(o)[1].x for o in roof), max(bounds(o)[1].y for o in roof), max(bounds(o)[1].z for o in roof)))
    roof_box = box_roblox(lo, hi)
    decks = {o.name: oriented_box(o) for o in roof if o.name.startswith("RoofDeck_")}
    roof_bytes = export(os.path.join(out, "roof.fbx"), roof)

    reset()
    proxies = import_glb(ROOF_COLLIDERS_GLB)
    bake_transforms(proxies, roof_matrix())
    roof_colliders = [oriented_box(o) for o in sorted(proxies, key=lambda o: o.name) if "RoofSlope" in o.name or "Ridge" in o.name]

    manifest = {
        "format": "spicy-shop-art/1",
        "units": "studs; the venue frame at yaw 0 (X across, Y up, Z = -D), origin at the centre of the shop floor",
        "scale": SCALE,
        "roof": {"span": ROOF_SPAN, "run": ROOF_RUN, "turn": "-90 degrees about the vertical (ridge along X, chimney at +Z)",
                 "box": {"centre": roof_box[0], "size": roof_box[1]}, "decks": decks},
        "sources": {
            "shop": {"file": os.path.relpath(SHOP_GLB, ROOT), "sha256": sha(SHOP_GLB)},
            "metadata": {"file": os.path.relpath(SHOP_META, ROOT), "sha256": sha(SHOP_META)},
            "roof": {"file": os.path.relpath(ROOF_GLB, ROOT), "sha256": sha(ROOF_GLB)},
            "roofColliders": {"file": os.path.relpath(ROOF_COLLIDERS_GLB, ROOT), "sha256": sha(ROOF_COLLIDERS_GLB)},
        },
        "fbx": {"shop": fbx_bytes, "proof": proof_bytes, "roof": roof_bytes},
        "entrance": {"node": "PORT_ShopEntrance", "at": entrance, "clearWidth": r4(meta["entrance"]["clear_width_m"] * SCALE)},
        "colliders": colliders,
        "front": front,
        "lamps": lamps,
        "roofColliders": roof_colliders,
        "shop": shop_meshes,
        "roofMeshes": roof_meshes,
    }
    with open(os.path.join(out, "manifest.json"), "w") as fh:
        json.dump(manifest, fh, indent=1)
    tris = sum(m["tris"] for m in shop_meshes)
    print(f"shop: {len(shop_meshes)} meshes, {tris} tris, fbx {fbx_bytes} B; proof {len(proof)} meshes {proof_bytes} B; "
          f"roof {len(roof_meshes)} meshes {roof_bytes} B; lamps {len(lamps)}; entrance {entrance}")


if __name__ == "__main__":
    main()
