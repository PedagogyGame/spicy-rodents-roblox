"""tools/review/backdrop_render.py: the backdrop additions to tools/review/render.py (imported by it; bpy only).

  install(g)            g = render.py's globals: adds the "Ellipsoid" shape (a sphere scaled per axis, for the
                        backdrop's SpecialMesh Sphere tree clumps)
  build(scene, g)       after render.py's build_scene: the fog cards (unlit colour with the card's UIGradient
                        alpha, top to bottom), the boot terrain beyond the world clamp and along the north coast
                        (scene.terrain.backdrop, group "backdrop_terrain") with its sea water sheet, and a distance
                        haze on every opaque material (an emission mix by camera distance: Roblox's Atmosphere,
                        roughly; off unless a view asks for it)
  before_view(v, vcfg)  per-view light: optional "light" = {
                          "sun": [x, y, z] (Roblox axes, toward the sun), "sunColor": [r, g, b], "sunStrength": s,
                          "sky": {"zenith", "mid", "horizon", "ground": [r, g, b], "strength": s},
                          "haze": {"color": [r, g, b], "start": studs, "half": studs (distance to half haze),
                                   "max": 0..1, "strength": emission strength},
                          "neon": emission strength of Neon parts (night), "cardStrength": s, "cardTint": [r, g, b] }
                        Views without "light" get render.py's defaults back (the golden-hour sun and sky).
"""
import math

import bpy
import numpy as np
from mathutils import Vector

_state = {"defaults": None, "haze": [], "cards": [], "neon": []}


def _rb_to_bl(v):
    return Vector((v[0], -v[2], v[1]))


def install(g):
    orig = g["make_templates"]

    def make_templates(*a, **k):
        t = orig(*a, **k)
        t["Ellipsoid"] = t["Ball"]  # parts_mesh only forces uniform size for "Ball"
        return t

    g["make_templates"] = make_templates


# ----------------------------------------------------------------------------------------------- cards
def _card_material(name, keys):
    """Unlit card: emission(col) over transparent, alpha = 1 - transparency(gradient position from the top)."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nodes, links = nt.nodes, nt.links
    for n in list(nodes):
        nodes.remove(n)
    out = nodes.new("ShaderNodeOutputMaterial")
    mix = nodes.new("ShaderNodeMixShader")
    tr = nodes.new("ShaderNodeBsdfTransparent")
    em = nodes.new("ShaderNodeEmission")
    col = nodes.new("ShaderNodeAttribute")
    col.attribute_type = "GEOMETRY"
    col.attribute_name = "col"
    uv = nodes.new("ShaderNodeUVMap")
    sep = nodes.new("ShaderNodeSeparateXYZ")
    ramp = nodes.new("ShaderNodeValToRGB")
    links.new(uv.outputs["UV"], sep.inputs["Vector"])
    links.new(sep.outputs["Y"], ramp.inputs["Fac"])  # UV v: 0 bottom, 1 top
    els = ramp.color_ramp.elements
    # gradient position p (0 top, 1 bottom) -> v = 1 - p; ramp value = opacity
    pts = sorted(((1.0 - p, 1.0 - t) for p, t in keys), key=lambda x: x[0])
    els[0].position, els[0].color = pts[0][0], (pts[0][1],) * 3 + (1.0,)
    els[1].position, els[1].color = pts[-1][0], (pts[-1][1],) * 3 + (1.0,)
    for pos, a in pts[1:-1]:
        e = els.new(pos)
        e.color = (a, a, a, 1.0)
    tint = nodes.new("ShaderNodeMix")
    tint.data_type = "RGBA"
    tint.blend_type = "MULTIPLY"
    tint.inputs["Factor"].default_value = 1.0
    links.new(col.outputs["Color"], tint.inputs["A"])
    tint.inputs["B"].default_value = (1.0, 1.0, 1.0, 1.0)
    links.new(tint.outputs["Result"], em.inputs["Color"])
    em.inputs["Strength"].default_value = 1.0
    links.new(ramp.outputs["Color"], mix.inputs["Fac"])
    links.new(tr.outputs["BSDF"], mix.inputs[1])
    links.new(em.outputs["Emission"], mix.inputs[2])
    links.new(mix.outputs["Shader"], out.inputs["Surface"])
    _state["cards"].append((em, tint.inputs["B"]))
    return mat


def _cards(scene, g):
    by_keys = {}
    for c in scene.get("cards", []):
        by_keys.setdefault(tuple(tuple(k) for k in c["keys"]), []).append(c)
    for n, (keys, cards) in enumerate(by_keys.items()):
        verts, loops, uvs, cols = [], [], [], []
        for c in cards:
            pos = np.array(c["pos"])
            rot = np.array(c["rot"]).reshape(3, 3)
            sx, sy = c["size"][0] / 2, c["size"][1] / 2
            base = len(verts)
            for lx, ly, u, v in ((-sx, -sy, 0, 0), (sx, -sy, 1, 0), (sx, sy, 1, 1), (-sx, sy, 0, 1)):
                w = pos + rot @ np.array([lx, ly, 0.0])
                verts.append(list(_rb_to_bl(w)))
                uvs.append((u, v))
            loops += [base, base + 1, base + 2, base + 3]
            lin = g["srgb_to_linear"](np.array(c["c"]) / 255.0)
            cols.append(list(lin) + [1.0])
        me = g["build_mesh"](
            f"fogcards_{n}",
            np.array(verts),
            np.array(loops),
            np.full(len(cards), 4),
            {"col": ("FLOAT_COLOR", np.array(cols))},
            np.zeros(len(cards), dtype=bool),
        )
        uvl = me.uv_layers.new(name="UVMap")
        uvl.data.foreach_set("uv", np.array(uvs, dtype=np.float32).ravel())
        g["link_object"](f"fogcards_{n}", me, "backdrop", _card_material(f"fogcard_{n}", keys))


# ----------------------------------------------------------------------------------------------- terrain
def _terrain(scene, g):
    t = scene.get("terrain") or {}
    bd = t.get("backdrop")
    if not bd:
        return
    minx, maxx, minz, maxz = bd["clamp"]
    north = bd["northFrom"]

    st = bd["step"]

    def keep(x, z):
        # one cell of overlap with the town's coarse grid (drawn 0.3 st lower) so no seam opens at the clamp edge
        return (x < minx + st) | (x > maxx - st) | (z < minz + st) | (z > north - st)

    tmat = bpy.data.materials.get("terrain") or g["material_terrain"]("terrain")
    g["link_object"]("terrain_backdrop", g["grid_mesh"]("terrain_backdrop", bd, t["colors"], keep=keep), "backdrop_terrain", tmat)
    me = g["water_mesh"]("sea_water", bd, bd["seaY"])
    if me:
        wmat = g["material_simple"]("sea_water", (0.05, 0.17, 0.19), rough=0.16, alpha=0.86)
        g["link_object"]("sea_water", me, "backdrop_terrain", wmat)


# ----------------------------------------------------------------------------------------------- haze
def _install_haze():
    """Mix every opaque material with an emission of the haze colour by camera distance (off by default)."""
    for mat in bpy.data.materials:
        if not mat.use_nodes or mat.name.startswith(("fogcard", "parts_transparent", "water", "sea_water", "label")):
            continue
        nt = mat.node_tree
        out = next((n for n in nt.nodes if n.type == "OUTPUT_MATERIAL"), None)
        if out is None or not out.inputs["Surface"].is_linked:
            continue
        src = out.inputs["Surface"].links[0].from_socket
        cam = nt.nodes.new("ShaderNodeCameraData")
        sub = nt.nodes.new("ShaderNodeMath")
        sub.operation = "SUBTRACT"
        sub.use_clamp = False
        mx = nt.nodes.new("ShaderNodeMath")
        mx.operation = "MAXIMUM"
        mx.inputs[1].default_value = 0.0
        mul = nt.nodes.new("ShaderNodeMath")
        mul.operation = "MULTIPLY"
        ex = nt.nodes.new("ShaderNodeMath")
        ex.operation = "EXPONENT"
        one = nt.nodes.new("ShaderNodeMath")
        one.operation = "SUBTRACT"
        one.inputs[0].default_value = 1.0
        cap = nt.nodes.new("ShaderNodeMath")
        cap.operation = "MULTIPLY"
        em = nt.nodes.new("ShaderNodeEmission")
        mix = nt.nodes.new("ShaderNodeMixShader")
        nt.links.new(cam.outputs["View Distance"], sub.inputs[0])
        nt.links.new(sub.outputs[0], mx.inputs[0])
        nt.links.new(mx.outputs[0], mul.inputs[0])
        nt.links.new(mul.outputs[0], ex.inputs[0])
        nt.links.new(ex.outputs[0], one.inputs[1])
        nt.links.new(one.outputs[0], cap.inputs[0])
        nt.links.new(cap.outputs[0], mix.inputs["Fac"])
        nt.links.new(src, mix.inputs[1])
        nt.links.new(em.outputs["Emission"], mix.inputs[2])
        nt.links.new(mix.outputs["Shader"], out.inputs["Surface"])
        _state["haze"].append({"start": sub.inputs[1], "rate": mul.inputs[1], "max": cap.inputs[1], "em": em})
        if mat.name == "parts_neon":
            for n in nt.nodes:
                if n.type == "BSDF_PRINCIPLED":
                    _state["neon"].append(n.inputs["Emission Strength"])
    _set_haze(None)


def _set_haze(h):
    for e in _state["haze"]:
        if not h:
            e["start"].default_value = 1e9
            e["rate"].default_value = 0.0
            e["max"].default_value = 0.0
            continue
        e["start"].default_value = h.get("start", 600.0)
        e["rate"].default_value = -math.log(2.0) / max(1.0, h.get("half", 4000.0))
        e["max"].default_value = h.get("max", 0.9)
        c = h["color"]
        e["em"].inputs["Color"].default_value = (c[0], c[1], c[2], 1.0)
        e["em"].inputs["Strength"].default_value = h.get("strength", 1.0)


def build(scene, g):
    _cards(scene, g)
    _terrain(scene, g)
    _install_haze()


# ----------------------------------------------------------------------------------------------- per view
def _world_parts():
    w = bpy.context.scene.world
    ramp = next(n for n in w.node_tree.nodes if n.type == "VALTORGB")
    bg = next(n for n in w.node_tree.nodes if n.type == "BACKGROUND")
    sun = bpy.data.objects.get("Sun")
    return ramp, bg, sun


def _snapshot():
    ramp, bg, sun = _world_parts()
    return {
        "ramp": [(e.position, tuple(e.color)) for e in ramp.color_ramp.elements],
        "bg": bg.inputs["Strength"].default_value,
        "sun_rot": tuple(sun.rotation_euler),
        "sun_energy": sun.data.energy,
        "sun_color": tuple(sun.data.color),
        "neon": [s.default_value for s in _state["neon"]],
    }


def _restore(d):
    ramp, bg, sun = _world_parts()
    for e, (pos, col) in zip(ramp.color_ramp.elements, d["ramp"]):
        e.position, e.color = pos, col
    bg.inputs["Strength"].default_value = d["bg"]
    sun.rotation_euler = d["sun_rot"]
    sun.data.energy = d["sun_energy"]
    sun.data.color = d["sun_color"]
    for s, v in zip(_state["neon"], d["neon"]):
        s.default_value = v
    for em, tint in _state["cards"]:
        em.inputs["Strength"].default_value = 1.0
        tint.default_value = (1.0, 1.0, 1.0, 1.0)
    _set_haze(None)


def before_view(view, vcfg):
    if _state["defaults"] is None:
        _state["defaults"] = _snapshot()
    _restore(_state["defaults"])
    light = view.get("light")
    if not light:
        return
    ramp, bg, sun = _world_parts()
    if "sun" in light:
        to_sun = _rb_to_bl(light["sun"]).normalized()
        sun.rotation_euler = (-to_sun).to_track_quat("-Z", "Y").to_euler()
    if "sunStrength" in light:
        sun.data.energy = light["sunStrength"]
    if "sunColor" in light:
        sun.data.color = light["sunColor"]
    sky = light.get("sky")
    if sky:
        # render.py's ramp: ground at 0, horizon at 0.03, mid at 0.35, zenith at 1
        by_pos = sorted(ramp.color_ramp.elements, key=lambda e: e.position)
        for e, key in zip(by_pos, ("ground", "horizon", "mid", "zenith")):
            if key in sky:
                e.color = tuple(sky[key]) + (1.0,)
        bg.inputs["Strength"].default_value = sky.get("strength", bg.inputs["Strength"].default_value)
    if "neon" in light:
        for s in _state["neon"]:
            s.default_value = light["neon"]
    for em, tint in _state["cards"]:
        if "cardStrength" in light:
            em.inputs["Strength"].default_value = light["cardStrength"]
        if "cardTint" in light:
            tint.default_value = tuple(light["cardTint"]) + (1.0,)
    _set_haze(light.get("haze"))
