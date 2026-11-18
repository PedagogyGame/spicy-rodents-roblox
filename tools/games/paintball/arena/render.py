"""tools/games/paintball/arena/render.py: tools/review/render.py for the paintball arena's views (views.luau).

  /root/.cache/spicy-rodents/venv/bin/python -I tools/games/paintball/arena/render.py \
      --scene build/review/scene.json --views build/review/paintball_views.json --out build/review/paintball

The same arguments as tools/review/render.py, and the same renderer: this file only imports it and puts back
four facts of the engine that matter INDOORS and that the stock review render leaves out (it was written for the
town in sunlight). Without the first three a sealed building renders black, which the game's is not.
  1. A light baked with Shadows = false passes through everything in the engine. Every light of the arena is one
     (tools/bake/games/Paintball), and each sits INSIDE its own fitting: Cycles would shut it in its box. Here the
     lights inside the views file's "indoor" box cast no shadow.
  2. An engine light stops at its Range. Cycles' lights fall off with the square of the distance and never stop,
     so two hundred of them would add up through the floors. Here each light fades to nothing at its Range
     (inverse square times 1 - (d / Range)^2).
  3. Lighting.Ambient (LightingPreset.GOLDEN.ambient) is added to every surface in the engine, sunlit or not.
     Here it is six shadowless suns along the axes whose strengths add up to the views file's "ambient".
  4. A label's background is drawn. The stock review draws a SurfaceGui's words only; the arena's paint (the
     plates behind its door names, and its marks: tape, cables lying on a floor, stains, papers) is labels with a
     background colour. Here each is a rectangle of that colour on its face, lit like the face.
It remains an approximation of the engine's light, for reading the place: what is where, what colour, what
can be seen from an eye point. It says nothing certain about how bright the game is.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.normpath(os.path.join(HERE, "..", "..", "..", "review")))

import bpy  # noqa: E402
import render as review  # noqa: E402


def _views_path(argv):
    for i, a in enumerate(argv):
        if a == "--views" and i + 1 < len(argv):
            return argv[i + 1]
    return None


def _ranged(light, rng):
    """Inverse-square light that fades to nothing at `rng` studs."""
    light.use_nodes = True
    nt = light.node_tree
    nodes, links = nt.nodes, nt.links
    for n in list(nodes):
        nodes.remove(n)
    out = nodes.new("ShaderNodeOutputLight")
    em = nodes.new("ShaderNodeEmission")
    path = nodes.new("ShaderNodeLightPath")
    ratio = nodes.new("ShaderNodeMath")
    ratio.operation = "DIVIDE"
    ratio.inputs[1].default_value = rng
    square = nodes.new("ShaderNodeMath")
    square.operation = "POWER"
    square.inputs[1].default_value = 2.0
    fade = nodes.new("ShaderNodeMath")
    fade.operation = "SUBTRACT"
    fade.use_clamp = True
    fade.inputs[0].default_value = 1.0
    links.new(path.outputs["Ray Length"], ratio.inputs[0])
    links.new(ratio.outputs[0], square.inputs[0])
    links.new(square.outputs[0], fade.inputs[1])
    links.new(fade.outputs[0], em.inputs["Strength"])
    links.new(em.outputs["Emission"], out.inputs["Surface"])


def _indoors(cfg, scene_lights):
    box = cfg.get("indoor")
    if not box:
        return 0
    lo, hi = box["min"], box["max"]
    done = 0
    for i, L in enumerate(scene_lights):
        p = L["pos"]
        if not all(lo[k] <= p[k] <= hi[k] for k in range(3)):
            continue
        for kind in ("point", "spot", "area"):
            ob = bpy.data.objects.get(f"att_{kind}_{i}")
            if ob is not None and ob.type == "LIGHT":
                ob.data.use_shadow = False
                _ranged(ob.data, max(2.0, float(L.get("range", 10))))
                done += 1
    return done


def _lin(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _grounds(texts):
    """Every label's background, as a rectangle on its face just under the words."""
    mats = {}
    done = 0
    for i, T in enumerate(texts):
        bg = T.get("bg")
        w, h = float(T.get("w", 0)), float(T.get("h", 0))
        if not bg or w <= 0 or h <= 0:
            continue
        key = tuple(bg)
        mat = mats.get(key)
        if mat is None:
            mat = bpy.data.materials.new(f"pb_ground_{len(mats)}")
            mat.use_nodes = True
            bsdf = mat.node_tree.nodes.get("Principled BSDF")
            bsdf.inputs["Base Color"].default_value = (_lin(bg[0]), _lin(bg[1]), _lin(bg[2]), 1.0)
            bsdf.inputs["Roughness"].default_value = 0.75
            mats[key] = mat
        r = review.rb_to_bl(T["right"]).normalized()
        u = review.rb_to_bl(T["up"]).normalized()
        n = review.rb_to_bl(T["normal"]).normalized()
        c = review.rb_to_bl(T["pos"]) - n * 0.003  # the words lie 0.006 off the face
        verts = [c - r * (w / 2) - u * (h / 2), c + r * (w / 2) - u * (h / 2), c + r * (w / 2) + u * (h / 2), c - r * (w / 2) + u * (h / 2)]
        me = bpy.data.meshes.new(f"pb_ground_{i}")
        me.from_pydata([tuple(v) for v in verts], [], [(0, 1, 2, 3)])
        me.materials.append(mat)
        ob = bpy.data.objects.new(me.name, me)
        bpy.context.scene.collection.objects.link(ob)
        ob.visible_shadow = False
        ob["review_group"] = "attractions"
        done += 1
    return done


def _ambient(cfg):
    amb = cfg.get("ambient")
    if not amb:
        return
    axes = [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)]
    for i, d in enumerate(axes):
        ld = bpy.data.lights.new(f"Ambient{i}", "SUN")
        # a surface facing an axis gets one sun in full; one at 45 degrees gets two at 0.7: near enough flat
        ld.energy = float(amb.get("strength", 0.4))
        ld.color = amb.get("color", [1.0, 1.0, 1.0])
        ld.use_shadow = False
        ob = bpy.data.objects.new(ld.name, ld)
        bpy.context.scene.collection.objects.link(ob)
        to_light = review.Vector(d)
        ob.rotation_euler = (-to_light).to_track_quat("-Z", "Y").to_euler()
        ob["review_group"] = "attractions"


def main(argv):
    path = _views_path(argv)
    if path is None:
        print("render.py: --views <file> is required (lune run tools/games/paintball/arena/views.luau)")
        return 2
    with open(path) as fh:
        cfg = json.load(fh)
    stock = review.setup_render
    scene_lights = []
    scene_texts = []
    load = json.load

    def loading(fh):
        data = load(fh)
        if isinstance(data, dict) and "attractions" in data:
            scene_lights.extend(data["attractions"].get("lights", []))
            scene_texts.extend(data["attractions"].get("texts", []))
        return data

    def setup_render(res, samples, threads):
        cam = stock(res, samples, threads)
        n = _indoors(cfg, scene_lights)
        _ambient(cfg)
        g = _grounds(scene_texts)
        print(
            f"review: paintball arena: {n} indoor lights without shadows, ranged; ambient added; {g} painted grounds",
            flush=True,
        )
        return cam

    review.setup_render = setup_render
    review.json.load = loading
    try:
        return review.main(argv)
    finally:
        review.json.load = load


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else sys.argv[1:]
    sys.exit(main(args))
