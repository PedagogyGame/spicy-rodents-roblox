"""tools/review/art_render.py: uploaded art in the review renders (imported by tools/review/render.py; bpy only).

  build(scene, g)   after render.py's build_scene: every entry of scene["art"] ({file, pos, rot, group}: an FBX
                    exported for Roblox with axis_forward Z, axis_up Y and 1 Blender unit = 1 stud, as uploaded,
                    and the CFrame the engine pivots its Model to) is imported and placed in the review frame.
                    Materials keep their colours and embedded textures; glass (a material named *Glass*) is drawn
                    see-through, as Server/Assets/ShopArt sets it in the engine.
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


def build(scene, g):
    for a in scene.get("art", []):
        before = set(bpy.data.objects)
        bpy.ops.import_scene.fbx(filepath=a["file"], axis_forward="Z", axis_up="Y", use_image_search=False)
        new = [o for o in bpy.data.objects if o not in before]
        r = a["rot"]
        p = a["pos"]
        pivot = Matrix(((r[0], r[1], r[2], p[0]), (r[3], r[4], r[5], p[1]), (r[6], r[7], r[8], p[2]), (0, 0, 0, 1)))
        m = TO_REVIEW @ pivot @ TO_ROBLOX
        for o in new:
            if o.parent is None:
                o.matrix_world = m @ o.matrix_world
            o["review_group"] = a.get("group", "attractions")
            if o.type == "MESH":
                for mat in o.data.materials:
                    if mat and "Glass" in mat.name:
                        _glass(mat)
        print(f"review: art {a['file']}: {len(new)} objects", flush=True)
