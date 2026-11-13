"""Review renders of the storm drains: tools/review/render.py over a pipe's scene, with the owner's modules drawn.

  /root/.cache/spicy-rodents/venv/bin/python -I tools/bake/sewers/review.py --pipe P1 \
      [--views tools/review/views_sewers.json] [--out build/review/sewers] [--only a,b] [--threads 2]

Make the scene first (lune run tools/review/export.luau; lune run tools/bake/sewers.luau;
lune run tools/bake/sewers/review.luau --pipe P1). This runs render.py's own main() on build/review/sewers_<pipe>.json
with the views of tools/review/views_sewers.json whose "pipe" is that pipe, leaves the shaft columns ("holes") out of
the terrain mesh, and adds, after its scene is built:
  the attraction lights and text (tools/review/attractions_render.py: every lamp lit, as the client lights a space
  while a squirrel is in it)
  the owner's modules: each art slot's FBX (the very file that was uploaded: tools/blender/sewers/export_modules.py,
  axis_forward Z, axis_up Y, 1 Blender unit = 1 stud) placed where the engine pivots its Model (ArtPivot), in review
  group "art"
The FBX import gives back the exporting scene's Blender frame B; the engine reads it as Roblox (-x, z, y); the review
scene maps Roblox (x, y, z) to Blender (x, -z, y). Lighting only approximates the engine's.
"""
import argparse
import json
import os
import sys

import bpy  # noqa: I001 (bpy first: it provides mathutils)
from mathutils import Matrix

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "review"))
import render  # noqa: E402

TO_ROBLOX = Matrix(((-1, 0, 0, 0), (0, 0, 1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
TO_REVIEW = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))


def place_art(scene):
    cache = {}
    for a in scene.get("art", []):
        path = os.path.join(ROOT, a["file"])
        if path in cache:
            new = []
            for o, mw in cache[path]:
                c = o.copy()
                bpy.context.scene.collection.objects.link(c)
                new.append((c, mw))
        else:
            before = set(bpy.data.objects)
            bpy.ops.import_scene.fbx(filepath=path, axis_forward="Z", axis_up="Y", use_image_search=False)
            new = [(o, o.matrix_world.copy()) for o in bpy.data.objects if o not in before]
            cache[path] = new
        r, p = a["rot"], a["pos"]
        pivot = Matrix(((r[0], r[1], r[2], p[0]), (r[3], r[4], r[5], p[1]), (r[6], r[7], r[8], p[2]), (0, 0, 0, 1)))
        m = TO_REVIEW @ pivot @ TO_ROBLOX
        for o, mw in new:
            if o.parent is None:
                o.matrix_world = m @ mw
            o["review_group"] = a.get("group", "art")
    print(f"sewers review: {len(scene.get('art', []))} art slots from {len(cache)} files", flush=True)


def cut_holes(holes):
    """render.py's terrain mesh without the quads over the shaft columns (the carve opens them to the street)."""
    inner = render.grid_mesh

    def grid_mesh(name, g, colors, keep=None, drop=0.0):
        if name != "terrain_fine" or not holes:
            return inner(name, g, colors, keep, drop)

        def keep_out(x, z):
            m = keep(x, z) if keep is not None else (x == x)
            for h in holes:
                m = m & ~((x > h[0]) & (x < h[1]) & (z > h[2]) & (z < h[3]))
            return m

        return inner(name, g, colors, keep_out, drop)

    render.grid_mesh = grid_mesh


class Shim:
    """Stands in for render.py's attractions module: its lights and text, then the art."""

    def __init__(self, inner):
        self.inner = inner

    def build(self, scene, g):
        if self.inner:
            self.inner.build(scene, g)
        place_art(scene)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pipe", required=True)
    ap.add_argument("--views", default=os.path.join(ROOT, "tools", "review", "views_sewers.json"))
    ap.add_argument("--out", default=os.path.join(ROOT, "build", "review", "sewers"))
    ap.add_argument("--only", default="")
    ap.add_argument("--threads", type=int, default=2)
    ap.add_argument("--samples", type=int, default=0)
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else sys.argv[1:]
    a = ap.parse_args(argv)
    with open(a.views) as fh:
        views = json.load(fh)
    names = [v["name"] for v in views["views"] if v.get("pipe") == a.pipe]
    if a.only:
        wanted = set(a.only.split(","))
        names = [n for n in names if n in wanted]
    inner = render._attractions_module()
    render._attractions_module = lambda: Shim(inner)
    scene = os.path.join(ROOT, "build", "review", f"sewers_{a.pipe}.json")
    with open(scene) as fh:
        cut_holes(json.load(fh).get("holes", []))
    args = ["--scene", scene, "--views", a.views, "--out", a.out, "--only", ",".join(names), "--threads", str(a.threads)]
    if a.samples:
        args += ["--samples", str(a.samples)]
    return render.main(args)


if __name__ == "__main__":
    sys.exit(main())
