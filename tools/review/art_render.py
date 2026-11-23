"""tools/review/art_render.py: uploaded art in the review renders (imported by tools/review/render.py; bpy only).

  build(scene, g)   after render.py's build_scene: every entry of scene["art"] ({file, pos, rot, group}: an FBX
                    exported for Roblox with axis_forward Z, axis_up Y and 1 Blender unit = 1 stud, as uploaded,
                    and the CFrame the engine pivots its Model to) is imported and placed in the review frame.
                    Materials keep their colours and embedded textures; glass (a material named *Glass*) is drawn
                    see-through, as Server/Assets/ShopArt sets it in the engine. Optional per entry, as a loader
                    dresses the meshes in the engine (tools/games/pinball/art.luau writes them): "only" (the
                    object names to keep from the file), "colours" ({name: [r, g, b]}: an untextured mesh's
                    colour), "alpha" ({name: transparency}) and "glow" ([names]: Neon, drawn emissive).
The FBX import gives back the exporting scene's Blender frame B; the engine reads it as Roblox (-x, z, y); the
review scene maps Roblox (x, y, z) to Blender (x, -z, y). Lighting only approximates the engine.
"""
import bpy
from mathutils import Matrix

TO_ROBLOX = Matrix(((-1, 0, 0, 0), (0, 0, 1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
TO_REVIEW = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))


def _glass(mat):
    if not mat.use_nodes:
        return
    bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf:
        bsdf.inputs["Alpha"].default_value = 0.18
        bsdf.inputs["Roughness"].default_value = 0.05


def _lin(c):
    return [(x / 255) / 12.92 if x / 255 <= 0.04045 else ((x / 255 + 0.055) / 1.055) ** 2.4 for x in c[:3]]


def _dress(o, a):
    """The entry's colour, see-through and glow for this object (a material of its own)."""
    name = o.name.split(".")[0]
    colour, alpha, glow = a.get("colours", {}).get(name), a.get("alpha", {}).get(name), name in a.get("glow", [])
    if colour is None and alpha is None and not glow:
        return
    mat = bpy.data.materials.new(f"dressed_{len(bpy.data.materials)}")  # (no "Glass" in it: the alpha given stands)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    old = o.data.materials[0] if o.data.materials else None
    old_bsdf = next((n for n in old.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None) if old and old.use_nodes else None
    rgb = _lin(colour) if colour else list(old_bsdf.inputs["Base Color"].default_value[:3]) if old_bsdf else [0.6, 0.6, 0.6]
    bsdf.inputs["Base Color"].default_value = (*rgb, 1)
    if glow:
        bsdf.inputs["Emission Color"].default_value = (*rgb, 1)
        bsdf.inputs["Emission Strength"].default_value = 2.0
    if alpha:
        bsdf.inputs["Alpha"].default_value = max(0.05, 1 - alpha)
        bsdf.inputs["Roughness"].default_value = 0.05
    o.data.materials.clear()
    o.data.materials.append(mat)


def _instance(a, cached, m):
    """Another placement of a file already imported: linked copies of its meshes (no second import)."""
    for src, world in cached:
        o = bpy.data.objects.new(src.name, src.data)
        bpy.context.scene.collection.objects.link(o)
        o.matrix_world = m @ world
        o["review_group"] = a.get("group", "attractions")


def build(scene, g):
    cache = {}
    counts = {}
    for a in scene.get("art", []):
        r = a["rot"]
        p = a["pos"]
        pivot = Matrix(((r[0], r[1], r[2], p[0]), (r[3], r[4], r[5], p[1]), (r[6], r[7], r[8], p[2]), (0, 0, 0, 1)))
        m = TO_REVIEW @ pivot @ TO_ROBLOX
        plain = a.get("only") is None and not a.get("colours") and not a.get("alpha") and not a.get("glow")
        if plain and a["file"] in cache:
            _instance(a, cache[a["file"]], m)
            counts[a["file"]] += 1
            continue
        before = set(bpy.data.objects)
        bpy.ops.import_scene.fbx(filepath=a["file"], axis_forward="Z", axis_up="Y", use_image_search=False)
        new = [o for o in bpy.data.objects if o not in before]
        if plain:
            bpy.context.view_layer.update()
            cache[a["file"]] = [(o, o.matrix_world.copy()) for o in new if o.type == "MESH"]
            counts[a["file"]] = 1
        if a.get("only") is not None:
            keep = set(a["only"])
            for o in [o for o in new if o.type == "MESH" and o.name.split(".")[0] not in keep]:
                new.remove(o)
                bpy.data.objects.remove(o, do_unlink=True)
        for o in new:
            if o.parent is None:
                o.matrix_world = m @ o.matrix_world
            o["review_group"] = a.get("group", "attractions")
            if o.type == "MESH":
                if o.data.users > 1:
                    o.data = o.data.copy()
                _dress(o, a)
                for mat in o.data.materials:
                    if mat and "Glass" in mat.name:
                        _glass(mat)
        print(f"review: art {a['file']}: {len(new)} objects", flush=True)
    for f, n in counts.items():
        if n > 1:
            print(f"review: art {f}: placed {n} times (linked copies)", flush=True)
