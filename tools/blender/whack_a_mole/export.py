"""The owner's whack-a-mole cabinet -> a game version for Roblox: one FBX in studs and the manifest the loader reads.

  /root/.cache/spicy-rodents/venv/bin/python -I tools/blender/whack_a_mole/export.py [--out build/art/whack_a_mole]

Input: docs/reference/whack_a_mole/Whack_A_Mole.blend (his editable project, Blender 4.3; read only, scripts in it
are text and never run). His GLB is 232,092 triangles in 246 pieces; this makes about 12,000 in 42 pieces, with
his look kept (docs/owner/DELIVERY_2026-11-18.md):
  * the moving parts at rest and his demonstration animation dropped: every mole down (root z 0), the mallet in
    its bracket (his rest: location (1.12, -0.25, 0.42) m, rotation (0, -16, -12) deg);
  * left out: every FONT object (his lettering is 133,000 triangles; the game writes WHACK, A MOLE, MIDNIGHT,
    the headings, the hole numbers and the live SCORE, TIME and status as SurfaceGui text, which costs no
    triangles and stays sharp), the coin slot, its plate and the coin return and their label (the coin door's
    frame and face stay: the game's FREE PLAY plate is written on them; no coins, ever), the hidden interior
    floor, the studio, lights and camera;
  * every piece's modifiers (his bevels) applied, then each piece decimated (collapse) to its share of its
    group's triangle budget (BUDGET), never below MIN_TRIS; a plain box stays as it is;
  * merged: the fixed cabinet into one mesh per material (Shell_<material>), each mole into one mesh per
    material (Mole<i>_<material>), the mallet likewise (Mallet_<material>). A MeshPart has one colour, so a
    material is a piece; the loader paints each with its colour;
  * in studs: 1 / 0.28 per metre (the pinball cabinets' scale), applied to the vertices.
Frames. Blender (x, y, z) metres is the cabinet frame (Shared/Minigames/WhackAMole/Layout: u = x, v = z, w = y)
times SCALE. The FBX export (axis_forward Z, axis_up Y, as the shop's: tools/blender/neighbourhood_shop) gives
Roblox (-x, z, y): the alley's site frame turned with the cabinet (X = AT.x - u, Y = v, D = AT.d - w), so each
MeshPart arrives unrotated in the site frame (Kit's frame), centred on its own bounding box. The manifest gives
each piece's centre in the cabinet frame (u, v, w, studs); the loader puts it there. A mole's pieces are at rest
(the client lifts the whole Mole model); the mallet's are in their rest pose about its pivot.
Outputs in --out: whack.fbx (every piece), manifest.json ({ scale, sources, total, groups: { name: tris },
pieces: [{ name, group, mole?, material, colour, tris, from (the source tris), centre, size }] }).
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
REF = os.path.join(ROOT, "docs", "reference", "whack_a_mole")
BLEND = os.path.join(REF, "Whack_A_Mole.blend")
SCALE = 1 / 0.28  # studs per metre
MIN_TRIS = 8
CUBE_THIN = 0.03  # metres: a bevelled box thinner than this is drawn as a plain box
CUBE_SMALL = 0.15  # metres: and one no longer than this

# his materials (the build script's names) -> the game's
MATERIALS = {
    "Oxblood lacquered timber": "wood",
    "Ebony lacquer": "black",
    "Warm brushed brass": "brass",
    "Champagne trim": "gold",
    "Warm ivory enamel": "cream",
    "Deep petrol leather deck": "felt",
    "Hole interiors": "dark",
    "Warm marquee lamps": "bulb",
    "Mole warm cocoa": "fur",
    "Mole soft taupe": "fur",
    "Mole charcoal fur": "fur",
    "Mole muzzle velvet": "muzzle",
    "Mole rosy nose": "nose",
    "Mole glossy eyes": "eye",
    "Eye catchlights": "glint",
    "Mallet padded burgundy": "rubber",
}
# the Roblox material each is drawn in
ROBLOX_MATERIAL = {
    "wood": "SmoothPlastic",
    "black": "SmoothPlastic",
    "brass": "Metal",
    "gold": "Metal",
    "cream": "SmoothPlastic",
    "felt": "Fabric",
    "dark": "SmoothPlastic",
    "bulb": "Neon",
    "fur": "SmoothPlastic",
    "muzzle": "SmoothPlastic",
    "nose": "SmoothPlastic",
    "eye": "Glass",
    "glint": "SmoothPlastic",
    "rubber": "SmoothPlastic",
}
# triangles for the decimated pieces of each merged piece (a mole's are each mole's; the mallet's its own); his
# bevelled boxes come on top of it, as they are or as plain boxes (cube_size)
BUDGET = {
    "Shell_wood": 800,  # the deck's timber with its five holes
    "Shell_felt": 700,  # the leather with its five holes
    "Shell_brass": 1900,  # the five hole lips (the most of it), the bulb sockets
    "Shell_black": 500,  # the feet, the inner lips of the holes
    "Shell_dark": 300,  # the floors of the wells
    "Shell_gold": 150,
    "Shell_bulb": 600,
    "Mole_fur": 420,
    "Mole_muzzle": 260,
    "Mole_nose": 60,
    "Mole_eye": 80,
    "Mole_glint": 24,
    "Mole_cream": 100,
    "Mallet_wood": 80,
    "Mallet_brass": 200,
    "Mallet_rubber": 200,
    "Mallet_cream": 120,
    "Mallet_black": 150,
}
# left out (see the docstring); FONT objects are left out by type
LEAVE_OUT = ("Coin slot plate", "Coin slot opening", "Coin return", "Interior floor")
MOLE_ROOTS = [f"Mole_{i:02d}_ROOT" for i in range(1, 6)]
MALLET_ROOT = "Mallet_ROOT"
MALLET_REST = ((1.12, -0.25, 0.42), (0.0, math.radians(-16), math.radians(-12)))


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        h.update(fh.read())
    return h.hexdigest()


def r4(v):
    return round(v + 0.0, 4)


def srgb(lin):
    def one(x):
        x = max(0.0, min(1.0, x))
        return 12.92 * x if x <= 0.0031308 else 1.055 * x ** (1 / 2.4) - 0.055

    return [int(round(one(c) * 255)) for c in lin[:3]]


def tris_of(me):
    return sum(len(p.vertices) - 2 for p in me.polygons)


def material_key(o):
    for slot in o.material_slots:
        if slot.material and slot.material.name.split(".")[0] in MATERIALS:
            return MATERIALS[slot.material.name.split(".")[0]], slot.material
    return None, None


def owner_of(o):
    """'shell', ('mole', i) or 'mallet': which moving part (if any) an object belongs to."""
    p = o
    while p is not None:
        if p.name in MOLE_ROOTS:
            return ("mole", MOLE_ROOTS.index(p.name) + 1)
        if p.name == MALLET_ROOT:
            return ("mallet", 0)
        p = p.parent
    return ("shell", 0)


def is_box(me):
    return len(me.vertices) == 8 and len(me.polygons) == 6


def at_rest():
    """Every mole down, the mallet in its bracket; his demonstration animation dropped."""
    objs = bpy.data.objects
    for name in MOLE_ROOTS:
        root = objs[name]
        root.animation_data_clear()
        root.location.z = 0.0
    m = objs[MALLET_ROOT]
    m.animation_data_clear()
    m.location = MALLET_REST[0]
    m.rotation_mode = "XYZ"
    m.rotation_euler = MALLET_REST[1]
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()


def cube_size(o):
    """His cube() pieces are an 8-vertex box with a bevel modifier: their size (metres, world), else None."""
    me = o.data
    if len(me.vertices) != 8 or len(me.polygons) != 6:
        return None
    pts = [o.matrix_world @ v.co for v in me.vertices]
    return [max(p[i] for p in pts) - min(p[i] for p in pts) for i in range(3)]


def plain(o):
    """A cube piece without its bevel: the 8-vertex box itself, in world space (12 triangles)."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bm.transform(o.matrix_world)
    return bm


def evaluated(o, dg):
    """The object's mesh with its modifiers applied, in world space (metres), as a bmesh."""
    ev = o.evaluated_get(dg)
    me = ev.to_mesh()
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.transform(o.matrix_world)
    ev.to_mesh_clear()
    return bm


def decimate(bm, target):
    """Collapse a bmesh to about `target` triangles (a plain box, or anything already under, is left)."""
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    n = len(bm.faces)
    if n <= target or (len(bm.verts) == 8 and n == 12):
        return bm
    me = bpy.data.meshes.new("tmp_decimate")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("tmp_decimate", me)
    bpy.context.scene.collection.objects.link(ob)
    mod = ob.modifiers.new("decimate", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = max(0.0, min(1.0, target / n))
    mod.use_collapse_triangulate = True
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    out = bmesh.new()
    em = ev.to_mesh()
    out.from_mesh(em)
    ev.to_mesh_clear()
    bpy.data.objects.remove(ob)
    bpy.data.meshes.remove(me)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(ROOT, "build", "art", "whack_a_mole"))
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else sys.argv[1:]
    a = ap.parse_args(argv)
    out = os.path.abspath(a.out)
    os.makedirs(out, exist_ok=True)

    # his project, as delivered; nothing in it runs (bpy does not auto-run scripts in a file)
    bpy.ops.wm.open_mainfile(filepath=BLEND, load_ui=False)
    at_rest()
    dg = bpy.context.evaluated_depsgraph_get()

    # what each piece is made of: (piece name, budget key) -> [(source object, bmesh, tris)]
    groups = {}
    sources_tris = 0
    left_out = {"lettering": 0, "coin": 0, "hidden": 0}
    for o in list(bpy.context.scene.objects):
        if o.type == "FONT":
            if o.users_collection and o.users_collection[0].name != "05_Studio":
                tm = o.evaluated_get(dg).to_mesh()
                left_out["lettering"] += tris_of(tm)
                o.evaluated_get(dg).to_mesh_clear()
            continue
        if o.type != "MESH":
            continue
        coll = o.users_collection[0].name if o.users_collection else ""
        if coll not in ("01_Cabinet", "02_Moles", "03_Mallet"):
            continue
        base = o.name.split(".")[0]
        bm = evaluated(o, dg)
        bmesh.ops.triangulate(bm, faces=bm.faces[:])
        n = len(bm.faces)
        sources_tris += n
        # his bevelled boxes: a thin or small one is drawn as a plain box (its bevel is not seen at the size the
        # game shows it), a large one keeps its rounded edges; neither is decimated (a box collapsed by the
        # decimator caves into a pyramid)
        fixed = False
        size = cube_size(o)
        if size is not None:
            fixed = True
            if min(size) < CUBE_THIN or max(size) < CUBE_SMALL:
                bm.free()
                bm = plain(o)
                bmesh.ops.triangulate(bm, faces=bm.faces[:])
        if base in LEAVE_OUT:
            left_out["hidden" if base == "Interior floor" else "coin"] += n
            bm.free()
            continue
        key, _mat = material_key(o)
        if key is None:
            bm.free()
            raise SystemExit(f"export: {o.name} has a material this script does not know")
        who, i = owner_of(o)
        if who == "mole":
            # the claws and teeth are his warm ivory; on a mole they are "cream"
            piece, budget = f"Mole{i}_{key}", f"Mole_{key}"
        elif who == "mallet":
            # his mallet's handle is the cabinet's timber and its grips the cabinet's ebony
            piece, budget = f"Mallet_{key}", f"Mallet_{key}"
        else:
            piece, budget = f"Shell_{key}", f"Shell_{key}"
        groups.setdefault((piece, budget, who, i, key), []).append((o.name, bm, n, fixed))

    # decimate each source to its share of the piece's budget, then merge the piece and put it in studs
    to_studs = Matrix.Scale(SCALE, 4)
    pieces = []
    made = []
    for (piece, budget, who, i, key), items in sorted(groups.items()):
        total = sum(n for _, _, n, _ in items)
        cap = BUDGET.get(budget)
        if cap is None:
            raise SystemExit(f"export: no budget for {budget} ({piece})")
        # the budget is shared by the pieces that are decimated, after a planar clean-up, by their size
        loose = 0
        for _name, bm, _n, fixed in items:
            if not fixed:
                bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(0.5), verts=bm.verts[:], edges=bm.edges[:])
                bmesh.ops.triangulate(bm, faces=bm.faces[:])
                loose += len(bm.faces)
        merged = bmesh.new()
        for _name, bm, _n, fixed in items:
            n = len(bm.faces)
            share = n if fixed or loose <= cap else max(MIN_TRIS, int(cap * n / loose))
            small = decimate(bm, share)
            me = bpy.data.meshes.new("tmp_merge")
            small.to_mesh(me)
            small.free()
            merged.from_mesh(me)
            bpy.data.meshes.remove(me)
        merged.transform(to_studs)
        bmesh.ops.triangulate(merged, faces=merged.faces[:])
        mesh = bpy.data.meshes.new(piece)
        merged.to_mesh(mesh)
        merged.free()
        for p in mesh.polygons:
            p.use_smooth = key not in ("wood", "black", "felt", "dark", "gold")
        mat = bpy.data.materials.new(f"WAM_{key}")
        mesh.materials.append(mat)
        ob = bpy.data.objects.new(piece, mesh)
        bpy.context.scene.collection.objects.link(ob)
        # the origin at the bounding box's centre (the engine centres a MeshPart on it anyway)
        lo = Vector((min(v.co.x for v in mesh.vertices), min(v.co.y for v in mesh.vertices), min(v.co.z for v in mesh.vertices)))
        hi = Vector((max(v.co.x for v in mesh.vertices), max(v.co.y for v in mesh.vertices), max(v.co.z for v in mesh.vertices)))
        c = (lo + hi) / 2
        mesh.transform(Matrix.Translation(-c))
        ob.location = c
        tris = tris_of(mesh)
        src_mat = None
        for name, _bm, _n, _f in items:
            src = bpy.data.objects.get(name)
            if src is not None:
                _k, src_mat = material_key(src)
                break
        colour = None
        if src_mat is not None:
            colour = srgb(list(src_mat.diffuse_color))
        rec = {
            "name": piece,
            "group": who,
            "material": key,
            "robloxMaterial": ROBLOX_MATERIAL.get(key, "SmoothPlastic"),
            "colour": colour,
            "tris": tris,
            "from": total,
            "sources": len(items),
            # cabinet frame (Layout: u across, v up, w into the cabinet), studs
            "centre": [r4(c.x), r4(c.z), r4(c.y)],
            "size": [r4(hi.x - lo.x), r4(hi.z - lo.z), r4(hi.y - lo.y)],
        }
        if who == "mole":
            rec["mole"] = i
        pieces.append(rec)
        made.append(ob)

    # the FBX: only the pieces
    bpy.ops.object.select_all(action="DESELECT")
    for ob in made:
        ob.select_set(True)
    fbx = os.path.join(out, "whack.fbx")
    bpy.ops.export_scene.fbx(
        filepath=fbx,
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
        embed_textures=False,
    )
    groups_tris = {}
    for p in pieces:
        k = "moles" if p["group"] == "mole" else p["group"]
        groups_tris[k] = groups_tris.get(k, 0) + p["tris"]
    manifest = {
        "format": "whack_a_mole art v1",
        "fbx": "whack.fbx",
        "scale": SCALE,
        "sources": {
            "Whack_A_Mole.blend": sha(BLEND),
            "Whack_A_Mole.glb": sha(os.path.join(REF, "Whack_A_Mole.glb")),
        },
        "sourceTris": sources_tris,
        "leftOut": left_out,
        "total": sum(p["tris"] for p in pieces),
        "groups": groups_tris,
        "pieces": pieces,
    }
    with open(os.path.join(out, "manifest.json"), "w") as fh:
        json.dump(manifest, fh, indent=1)
        fh.write("\n")
    print(f"WHACK_EXPORT {len(pieces)} pieces, {manifest['total']} triangles (from {sources_tris} meshed, "
          f"{left_out['lettering']} lettering left out); {groups_tris}; {os.path.getsize(fbx)} bytes", flush=True)
    for p in pieces:
        print(f"  {p['name']:18s} {p['tris']:6d} tris (from {p['from']:6d}, {p['sources']} pieces)", flush=True)


main()
