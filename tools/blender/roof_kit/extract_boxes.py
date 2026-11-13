"""The owner's roof and rafter kit -> data/art/roof_rafter_kit.json: every piece of the files the alley's yard uses,
as the plain box it is (stdlib + bpy).

  /root/.cache/spicy-rodents/venv/bin/python -I tools/blender/roof_kit/extract_boxes.py

Inputs (his delivery, used as delivered): docs/reference/store_roofs/roof_rafter_kit/GLB/03_Ridge_Eave_Route_Perches.glb
(the ridge perches and grips, eave landings, slope footholds, 65 meshes) and 05_Gutter_Fascia_Details.glb (gutter,
brackets, downpipes, 30 meshes): the pieces of his kit that fit the yard house at the game's scale (see
tools/bake/alley/RoofKit). Every mesh in both is a box of 12 triangles coloured by vertex (one colour per mesh);
the run checks that and stops if one is not. A box needs no mesh upload: the game draws his boxes as Parts (as
Server/Assets/ShopArt does with his roof on the Neighbourhood Shop, where all 90 meshes come back from the upload
as plain boxes), so this writes each one's centre, size, axes and colour and the alley bake builds them.

The frame is his file's own (glTF): metres, x across the roof's span (the eaves at about +-5.6), y up (the
ground datum 0, eave 4.15, ridge 7.45 under his full roof), z along the ridge. right/up/back are the box's axes in that frame
(right nearest x, up nearest y), size is along them. Colours are sRGB 0..255 (his vertex colours are linear).
"""
import hashlib
import json
import os

import bpy  # noqa: I001
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
KIT = os.path.join(ROOT, "docs", "reference", "store_roofs", "roof_rafter_kit")
FILES = [("perches", "GLB/03_Ridge_Eave_Route_Perches.glb"), ("gutters", "GLB/05_Gutter_Fascia_Details.glb")]
OUT = os.path.join(ROOT, "data", "art", "roof_rafter_kit.json")


def r4(v):
    return round(v + 0.0, 4)


def sha(path):
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def srgb(c):
    def one(x):
        x = max(0.0, min(1.0, x))
        return x * 12.92 if x <= 0.0031308 else 1.055 * x ** (1 / 2.4) - 0.055

    return [int(round(one(c[i]) * 255)) for i in range(3)]


def to_gltf(v):
    """Blender (x, y, z) after the glTF import -> glTF (x, z, -y)."""
    return Vector((v[0], v[2], -v[1]))


def box(o):
    """A box mesh -> centre, size and axes in his frame. The axes are the face normals (a triangulated box has
    diagonal edges); each size is the spread of the corners along its axis."""
    me = o.data
    me.calc_loop_triangles()
    assert len(me.loop_triangles) == 12, (o.name, len(me.loop_triangles))
    mw = o.matrix_world
    rot = mw.to_3x3()
    axes = []
    for t in me.loop_triangles:
        n = to_gltf((rot @ t.normal).normalized()).normalized()
        if all(abs(n.dot(a)) < 0.99 for a in axes):
            axes.append(n)
    assert len(axes) == 3, (o.name, len(axes))
    pts = [to_gltf(mw @ v.co) for v in me.vertices]
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
    a = me.color_attributes[0]
    n = len(a.data)
    lin = [sum(d.color[i] for d in a.data) / n for i in range(3)]
    return {
        "name": o.name,
        "centre": [r4(centre.x), r4(centre.y), r4(centre.z)],
        "size": size,
        "right": [r4(X.x), r4(X.y), r4(X.z)],
        "up": [r4(Y.x), r4(Y.y), r4(Y.z)],
        "back": [r4(Z.x), r4(Z.y), r4(Z.z)],
        "color": srgb(lin),
    }


def main():
    out = {
        "format": "spicy-roof-kit/1",
        "note": "Written by tools/blender/roof_kit/extract_boxes.py from the owner's kit; do not edit by hand.",
        "frame": "his glTF: metres; x across the span, y up from the ground datum, z along the ridge",
        "sources": {},
        "pieces": {},
    }
    for key, rel in FILES:
        path = os.path.join(KIT, rel)
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=path)
        objs = sorted((o for o in bpy.context.scene.objects if o.type == "MESH"), key=lambda o: o.name)
        out["sources"][key] = {"file": "docs/reference/store_roofs/roof_rafter_kit/" + rel, "sha256": sha(path)}
        out["pieces"][key] = [box(o) for o in objs]
        print(f"roof kit: {rel}: {len(objs)} boxes")
    with open(OUT, "w") as fh:
        json.dump(out, fh, indent=1)
        fh.write("\n")
    print(f"roof kit: -> {os.path.relpath(OUT, ROOT)}")


main()
