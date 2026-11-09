"""tools/review/attractions_render.py: the attraction additions to tools/review/render.py (imported by it; bpy only).

  build(scene, g)   after render.py's build_scene: the attraction lights (Roblox PointLight -> point light,
                    SpotLight -> spot, SurfaceLight -> area light over the part face; power from Brightness and
                    Range) and the SurfaceGui text (Blender's font, emissive, sized to the label's box and laid on
                    the part face) from scene.attractions (tools/review/attractions_export.luau). Everything is in
                    review group "attractions", so views that do not list it hide it.
Lighting only approximates the engine (Future lighting, exposure); it is for reading the layout and the look.
"""
import math

import bpy
from mathutils import Matrix, Vector


def _bl(v):
    return Vector((v[0], -v[2], v[1]))


def _lin(c):
    out = []
    for x in c[:3]:
        x = x / 255.0
        out.append(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4)
    return out


def _track(ob, direction):
    """Point the object's -Z along `direction` (Blender axes)."""
    ob.rotation_euler = direction.normalized().to_track_quat("-Z", "Y").to_euler()


def _lights(lights):
    for i, L in enumerate(lights):
        kind = L["kind"]
        b = max(0.05, float(L.get("brightness", 1)))
        rng = max(2.0, float(L.get("range", 10)))
        col = [min(1.0, c / 255.0) for c in L["color"]]
        if kind == "point":
            ld = bpy.data.lights.new(f"att_point_{i}", "POINT")
            ld.energy = b * rng * rng * 1.6
            ld.shadow_soft_size = 0.25
        elif kind == "spot":
            ld = bpy.data.lights.new(f"att_spot_{i}", "SPOT")
            ld.energy = b * rng * rng * 2.4
            ld.spot_size = math.radians(max(10.0, min(170.0, float(L.get("angle", 90)))))
            ld.spot_blend = 0.4
            ld.shadow_soft_size = 0.2
        else:
            ld = bpy.data.lights.new(f"att_area_{i}", "AREA")
            ld.shape = "RECTANGLE"
            ld.size = max(0.2, float(L["size"][0]))
            ld.size_y = max(0.2, float(L["size"][1]))
            ld.energy = b * rng * rng * 2.0
        ld.color = col
        ob = bpy.data.objects.new(ld.name, ld)
        bpy.context.scene.collection.objects.link(ob)
        ob.location = _bl(L["pos"]) + _bl(L["dir"]) * 0.05
        if kind != "point":
            _track(ob, _bl(L["dir"]))
        ob["review_group"] = "attractions"


def _text_material(name, rgb):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nodes, links = nt.nodes, nt.links
    for n in list(nodes):
        nodes.remove(n)
    out = nodes.new("ShaderNodeOutputMaterial")
    em = nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*_lin(rgb), 1.0)
    em.inputs["Strength"].default_value = 2.2
    links.new(em.outputs["Emission"], out.inputs["Surface"])
    return mat


def _texts(texts):
    cache = {}
    for i, T in enumerate(texts):
        text = T["text"]
        lines = text.split("\n")
        longest = max(len(s) for s in lines) or 1
        w, h = float(T["w"]), float(T["h"])
        if w <= 0 or h <= 0:
            continue
        size = min(h * 0.78 / len(lines), w / (longest * 0.62))
        if size < 0.01:
            continue
        cu = bpy.data.curves.new(f"att_text_{i}", "FONT")
        cu.body = text
        cu.align_x = "CENTER"
        cu.align_y = "CENTER"
        cu.size = size
        key = tuple(T["color"])
        mat = cache.get(key)
        if mat is None:
            mat = _text_material(f"att_text_mat_{len(cache)}", T["color"])
            cache[key] = mat
        tmp = bpy.data.objects.new(cu.name, cu)
        tmp.data.materials.append(mat)
        bpy.context.scene.collection.objects.link(tmp)
        # as a mesh: render.py's setup_render turns every FONT object toward the camera (the lineup labels)
        dg = bpy.context.evaluated_depsgraph_get()
        me = bpy.data.meshes.new_from_object(tmp.evaluated_get(dg))
        bpy.data.objects.remove(tmp, do_unlink=True)
        ob = bpy.data.objects.new(f"att_text_{i}", me)
        if not me.materials:
            me.materials.append(mat)
        bpy.context.scene.collection.objects.link(ob)
        r, u, n = _bl(T["right"]).normalized(), _bl(T["up"]).normalized(), _bl(T["normal"]).normalized()
        m = Matrix(((r.x, u.x, n.x), (r.y, u.y, n.y), (r.z, u.z, n.z))).to_4x4()
        ob.matrix_world = Matrix.Translation(_bl(T["pos"])) @ m
        ob["review_group"] = "attractions"


def build(scene, g):
    att = scene.get("attractions")
    if not att:
        return
    _lights(att.get("lights", []))
    _texts(att.get("texts", []))
