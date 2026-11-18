"""The owner's finished pinball models (ChatGPT's 21 GLBs, docs/reference/pinball_art) -> FBX in studs for Roblox,
plus the manifest the loader (Server/Assets/PinballArt, through data/art/pinball.json) reads.

  python3 -I tools/blender/pinball/boards.py; python3 -I tools/blender/pinball/backglass.py   (the textures first)
  /root/.cache/spicy-rodents/venv/bin/python -I tools/blender/pinball/export_pinball.py [--out build/art/pinball]

Eight Models: the shared parts once each (flipper, bumper, plunger, gate, cabinet: the game places and colours
them per machine) and one per machine (acorn, rodent, space: its playfield, guides, slingshots, targets,
spinner, ramps and pod hoods, plus "BackglassArt", a quad carrying the machine's backglass picture).

What changes on the way, and nothing else: every object keeps its name, geometry, UVs and material; its world
transform goes into the vertices; the whole is scaled to studs (1 / 0.28 studs per metre, the game's own); the
Board's texture is the corrected board (tools/blender/pinball/boards.py, the painted words moved clear); the
cabinet's plain "Backglass" box is left out (the game's own Backglass part carries the live text, and the
machine's picture sits on the BackglassArt quad behind it).

Frames. glTF (gx, gy, gz) -> Blender (gx, -gz, gy) on import; a half turn about Blender's Z here; the FBX export
(axis_forward Z, axis_up Y, the shop's settings: tools/blender/neighbourhood_shop/export_shop.py) gives Roblox
(-x, z, y) = (gx, gy, gz) / 0.28. So a MeshPart arrives unrotated in the GLB's own frame, in studs, centred on
its bounding box, and the manifest gives that centre in the frame the loader places it in:
  "playfield"  the playfield's frame (the game's: Shared/Minigames/Pinball/Cabinet; origin the front-left
               corner on the surface, X to the player's right, Y the normal, Z down the table toward the player)
  "cabinet"    the floor under the machine's middle, X to the player's right, Y up, Z toward the player
  "flipper"    on the pivot pin half way up, X along the bat, Y the normal (the bake's Hub part)
  "bumper"     the centre of the bumper's base (made at radius BUMPER_R; scaled across per machine)
  "plunger"    the knob's centre, the rod up the table (-Z)
  "gate"       on the hinge at the top of the flap, X along the flap
Each mesh also records its "pivot": the GLB node's origin in that frame (where the game moves it about).

Outputs in --out: <tag>.fbx for flipper, bumper, plunger, gate, cabinet, acorn, rodent, space (textures embedded);
textures/ (the images the FBXs embed); manifest.json (models: fbx, frame, meshes: name, frame, centre, size,
pivot, tris, material, colour, theme (the THEMES key a recolourable material takes), texture, fallback, alpha;
sources and textures with checksums).
"""
import argparse
import hashlib
import json
import math
import os
import sys

import bpy  # noqa: I001 (bpy first: it provides mathutils)
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
REF = os.path.join(ROOT, "docs", "reference", "pinball_art")
DATA = os.path.join(ROOT, "docs", "owner", "pinball_blender", "chatgpt_pack", "pinball_data.json")
METRES_PER_STUD = 0.28
SCALE = 1 / METRES_PER_STUD
# the cabinet's materials the game recolours per machine: material name -> the bake's THEMES key
RECOLOUR = {
    "Cabinet lacquer | recolourable": "body",
    "Cabinet trim | recolourable": "trim",
    "Cabinet legs | recolourable": "legs",
    "Light strip | recolourable": "glow",
    "Bumper body | recolourable": "bumper",
    "Bumper cap | recolourable": "cap",
}
SHARED = [
    ("flipper", "flipper", ["Pinball_Flipper.glb"]),
    ("bumper", "bumper", ["Pinball_PopBumper.glb"]),
    ("plunger", "plunger", ["Pinball_Plunger.glb"]),
    ("gate", "gate", ["Pinball_Gate.glb"]),
    ("cabinet", "cabinet", ["Pinball_Cabinet.glb"]),
]
MACHINES = {
    "acorn": ("Acorn", ["Playfield", "Guides", "Slingshots", "Targets", "Spinner"]),
    "rodent": ("Rodent", ["Playfield", "Guides", "Slingshots", "Targets", "Wire"]),
    "space": ("Space", ["Playfield", "Guides", "Slingshots", "Targets", "Ramps", "PodHoods"]),
}
LEFT_OUT = {"cabinet": {"Backglass"}}  # the game's own Backglass part stays (it carries the live text)
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


def srgb(c):
    def one(x):
        x = max(0.0, min(1.0, x))
        return x * 12.92 if x <= 0.0031308 else 1.055 * x ** (1 / 2.4) - 0.055

    return [int(round(one(c[i]) * 255)) for i in range(3)]


def linear(x):
    return x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = "NONE"


# glTF metres -> Blender, then the half turn and the scale: Roblox (-x, z, y) of the result is the glTF frame in studs
EXTRA = Matrix.Scale(SCALE, 4) @ Matrix.Rotation(math.pi, 4, "Z")


def import_glbs(paths):
    objs = []
    for path in paths:
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=path)
        objs += [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
    return objs


def bake(objs):
    """Each object's world transform and EXTRA into its vertices; its node origin kept (Roblox studs)."""
    pivots = {}
    for o in objs:
        if o.data.users > 1:
            o.data = o.data.copy()
    for o in objs:
        mw = EXTRA @ o.matrix_world
        pivots[o.name] = to_roblox(mw.translation)
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
    return pivots


def bounds(o):
    xs = [v.co for v in o.data.vertices]
    lo = Vector((min(v.x for v in xs), min(v.y for v in xs), min(v.z for v in xs)))
    hi = Vector((max(v.x for v in xs), max(v.y for v in xs), max(v.z for v in xs)))
    return lo, hi


def image_of(mat):
    if not mat or not mat.node_tree:
        return None, None
    bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        return None, None
    s = bsdf.inputs["Base Color"]
    if s.is_linked and getattr(s.links[0].from_node, "image", None):
        return bsdf, s.links[0].from_node
    return bsdf, None


def mean_srgb(path):
    """The mean colour of a texture file (what a textured mesh shows from afar; the loader's fallback)."""
    img = bpy.data.images.load(path, check_existing=True)
    px = list(img.pixels[:])
    n = len(px) // 4
    step = max(1, n // 65536)
    acc, k = [0.0, 0.0, 0.0], 0
    for i in range(0, n, step):
        for c in range(3):
            acc[c] += linear(px[i * 4 + c])  # (a colour map's pixels are stored as authored: sRGB)
        k += 1
    return srgb([acc[c] / k for c in range(3)])


def save_images(tmp):
    """The GLB's packed images as files beside the FBX, so the exporter can embed them."""
    os.makedirs(tmp, exist_ok=True)
    for img in bpy.data.images:
        if img.packed_file is None:
            continue
        safe = "".join(ch if ch.isalnum() or ch in "-_" else "_" for ch in img.name)
        path = os.path.join(tmp, f"{safe}.png")
        with open(path, "wb") as fh:
            fh.write(img.packed_file.data)
        img.unpack(method="REMOVE")
        img.filepath = path
        img.reload()


def use_texture(obj, path):
    """Points the object's material's base-colour image at a file (the corrected board)."""
    _, node = image_of(obj.active_material)
    assert node is not None, f"{obj.name} has no texture to replace"
    node.image = bpy.data.images.load(path, check_existing=True)


def backglass_quad(prefix, data, picture):
    """A quad the size of the backglass face, in the cabinet frame just behind the game's Backglass front face."""
    bg = data["cabinet"]["parts_as_8_corners"]["Backglass"]
    xs = [c[0] for c in bg]
    ys = [c[1] for c in bg]
    zs = [c[2] for c in bg]
    front = max(zs) - 0.001  # metres: a hair behind the face the live text is drawn on
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    me = bpy.data.meshes.new("BackglassArt")
    # glTF metres (x right, y up, z toward the player), faced toward +z
    verts = [(x0, y0, front), (x1, y0, front), (x1, y1, front), (x0, y1, front)]
    me.from_pydata(verts, [], [(0, 1, 2, 3)])
    uv = me.uv_layers.new(name="UVMap")
    for loop, (u, v) in zip(me.loops, [(0, 0), (1, 0), (1, 1), (0, 1)]):
        uv.data[loop.index].uv = (u, v)
    mat = bpy.data.materials.new(f"{prefix}_Backglass_Printed")
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(picture, check_existing=True)
    mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    me.materials.append(mat)
    obj = bpy.data.objects.new("BackglassArt", me)
    bpy.context.scene.collection.objects.link(obj)
    # glTF (x, y, z) -> Blender (x, -z, y), as the importer does, so bake() treats it like the rest
    obj.matrix_world = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
    return obj


def records(objs, pivots, frame, textures):
    recs = []
    for o in sorted(objs, key=lambda o: o.name):
        lo, hi = bounds(o)
        o.data.calc_loop_triangles()
        mats = [m for m in o.data.materials if m]
        assert len(mats) == 1, f"{o.name}: {len(mats)} materials (the brief: one per object)"
        mat = mats[0]
        bsdf, node = image_of(mat)
        rec = {
            "name": o.name,
            "frame": frame,
            "centre": to_roblox((lo + hi) / 2),
            "size": [r4(hi.x - lo.x), r4(hi.z - lo.z), r4(hi.y - lo.y)],
            "pivot": pivots[o.name],
            "tris": len(o.data.loop_triangles),
            "material": mat.name.split(".")[0],
            "colour": srgb(bsdf.inputs["Base Color"].default_value) if bsdf else [163, 162, 165],
        }
        if rec["material"] in RECOLOUR:
            rec["theme"] = RECOLOUR[rec["material"]]
        if node is not None:
            path = bpy.path.abspath(node.image.filepath)
            rec["texture"] = os.path.basename(path)
            rec["fallback"] = mean_srgb(path)
            textures[rec["texture"]] = sha(path)
        alpha = bsdf.inputs["Alpha"].default_value if bsdf else 1.0
        if alpha < 0.99:
            rec["alpha"] = round(alpha, 3)
        recs.append(rec)
    return recs


def export(path, objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.fbx(filepath=path, **FBX_KW)
    return os.path.getsize(path)


def build(out, tag, frame, files, textures_dir, data, textures, extra=None):
    reset()
    objs = import_glbs([os.path.join(REF, f) for f in files])
    names = [o.name for o in objs]
    assert len(set(names)) == len(names) and not any("." in n for n in names), f"{tag}: names clash: {names}"
    for o in [o for o in objs if o.name in LEFT_OUT.get(tag, ())]:
        objs.remove(o)
        bpy.data.objects.remove(o, do_unlink=True)
    save_images(os.path.join(out, "textures", "packed"))
    if extra:
        objs += extra(objs)
    pivots = bake(objs)
    meshes = records(objs, pivots, frame, textures)
    size = export(os.path.join(out, f"{tag}.fbx"), objs)
    tris = sum(m["tris"] for m in meshes)
    print(f"{tag}: {len(meshes)} meshes, {tris} triangles, {size} bytes")
    return {"fbx": f"{tag}.fbx", "frame": frame, "fbxBytes": size, "tris": tris, "meshes": meshes,
            "sources": {f: sha(os.path.join(REF, f)) for f in files}}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(ROOT, "build", "art", "pinball"))
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else sys.argv[1:]
    a = ap.parse_args(argv)
    out = os.path.abspath(a.out)
    tex = os.path.join(out, "textures")
    for prefix, _ in MACHINES.values():
        for kind in ("Board", "Backglass"):
            p = os.path.join(tex, f"{prefix}_{kind}.png")
            if not os.path.exists(p):
                sys.exit(f"missing {p}: run tools/blender/pinball/boards.py and backglass.py first")
    with open(DATA) as fh:
        data = json.load(fh)
    textures = {}
    models = {}
    for tag, frame, files in SHARED:
        models[tag] = build(out, tag, frame, files, tex, data, textures)
    for tag, (prefix, kinds) in MACHINES.items():
        files = [f"{prefix}_{k}.glb" for k in kinds]

        def extra(objs, prefix=prefix):
            board = next(o for o in objs if o.name == "Board")
            use_texture(board, os.path.join(tex, f"{prefix}_Board.png"))
            return [backglass_quad(prefix, data, os.path.join(tex, f"{prefix}_Backglass.png"))]

        m = build(out, tag, "playfield", files, tex, data, textures, extra)
        for rec in m["meshes"]:
            if rec["name"] == "BackglassArt":
                rec["frame"] = "cabinet"
        models[tag] = m
    shared = data["shared"]
    manifest = {
        "format": "spicy-pinball-art/1",
        "units": "studs (1 / 0.28 per metre); each mesh's centre and pivot in its frame (see export_pinball.py)",
        "scale": r4(SCALE),
        "bumperRadius": r4(shared["PopBumper"]["made_at_radius"] * SCALE),
        "gateHinge": r4(shared["Gate"]["flap_top"] * SCALE),
        "models": models,
        "textures": textures,
        "data": {"file": os.path.relpath(DATA, ROOT), "sha256": sha(DATA)},
    }
    with open(os.path.join(out, "manifest.json"), "w") as fh:
        json.dump(manifest, fh, indent=1)
    total = sum(m["tris"] for t, m in models.items() if t in MACHINES)
    print(f"manifest: {len(models)} models; machine files {total} triangles in all")


if __name__ == "__main__":
    main()
