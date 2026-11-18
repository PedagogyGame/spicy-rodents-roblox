"""Write the townspeople's upload set from a build (headless bpy 5.2.x):

  nice -n 10 taskset -c 2,3 /root/.cache/spicy-rodents/venv/bin/python -I tools/blender/people/export_people.py \
      --out build/people

Reads <out>/people.blend and <out>/manifest.json (build_people.py) and writes <out>/upload/:
  body_slim.fbx    the slim build: the fourteen R15 body parts and every extra (coat tails, V neck, stethoscope)
  body_broad.fbx   the broad build, the same eighteen meshes
  head.fbx         one Head
  headwear.fbx     Hair_<style> and Hat_<name>, on their two atlases
  looks.fbx        one small square per texture set: Outfit_<outfit> (seven) and Face_<face>_<expression> (six)
  upload.json      what each file holds (objects, triangles) and a digest of its content
Every mesh in the body, head and headwear files wears ONE texture set (the shirt, the calm plain face); the game
dresses a person in another outfit or face by cloning the SurfaceAppearance off the matching looks square
(Server/Assets/PeopleArt). Both builds share every UV layout, so seven outfits cost seven texture sets and one
mesh per part, where an FBX per outfit and build would upload (and make every phone hold) each mesh fourteen times.
"""
import argparse
import hashlib
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "heroes"))

import bpy  # noqa: E402
import numpy as np  # noqa: E402

import bl  # noqa: E402
import build_people as bp  # noqa: E402
import spec  # noqa: E402

BODY_NAMES = [n for n in spec.PARTS if n != "Head"]
EXTRA_NAMES = list(spec.EXTRAS)
SQUARE = 0.5  # studs: the side of a looks square
FILES = ["body_slim", "body_broad", "head", "headwear", "looks"]


def sha_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        h.update(fh.read())
    return h.hexdigest()


def square(name, x):
    """A two-triangle square at (x, 0, 0) facing -Y with UVs over the whole atlas."""
    s = SQUARE / 2
    V = np.array([[-s, 0, -s], [s, 0, -s], [s, 0, s], [-s, 0, s]], dtype=np.float32)
    obj = bl.mesh_from_arrays(name, V, np.array([[0, 1, 2], [0, 2, 3]], dtype=np.int32))
    layer = obj.data.uv_layers.new(name="UVMap")
    layer.data.foreach_set("uv", np.array([0, 0, 1, 0, 1, 1, 0, 0, 1, 1, 0, 1], dtype=np.float32))
    obj.location = (x, 0, 0)
    return obj


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="build/people")
    opts = ap.parse_args(argv)
    out = os.path.abspath(opts.out)
    with open(os.path.join(out, "manifest.json")) as fh:
        manifest = json.load(fh)
    bpy.ops.wm.open_mainfile(filepath=os.path.join(out, "people.blend"))
    up = os.path.join(out, "upload")
    os.makedirs(up, exist_ok=True)
    mats = bpy.data.materials
    objs = bpy.data.objects
    files = {}

    def record(key, named, tris):
        path = os.path.join(up, key + ".fbx")
        size = bp.export_fbx(path, named)
        files[key] = {"path": os.path.relpath(path, out), "bytes": size, "objects": [n for _o, n in named], "tris": tris}

    shirt = mats["body_shirt"]
    for build in spec.BUILD_ORDER:
        named = []
        for n in BODY_NAMES + EXTRA_NAMES:
            o = objs[f"{build}.{n}"]
            bp.set_material(o, shirt)
            named.append((o, n))
        record("body_" + build, named, {n: int(o["tris"]) for o, n in named})
    head = objs["Head"]
    bp.set_material(head, mats["head_plain_calm"])
    record("head", [(head, "Head")], {"Head": int(head["tris"])})
    wear = [(objs[n], n) for n in manifest["headwear"]["hair"] + manifest["headwear"]["hats"]]
    record("headwear", wear, {n: int(o["tris"]) for o, n in wear})
    squares = []
    keys = [("Outfit_" + o, "body_" + o) for o in spec.OUTFIT_ORDER]
    keys += [(f"Face_{f}_{e}", f"head_{f}_{e}") for f in spec.FACES for e in spec.EXPRESSIONS]
    for i, (name, mat) in enumerate(keys):
        o = square(name, i * SQUARE * 1.5)
        bp.set_material(o, mats[mat])
        squares.append((o, name))
    record("looks", squares, {n: 2 for _o, n in squares})

    # what each upload holds: the manifest's geometry for its meshes and the bytes of every texture it carries
    textures = {}
    for o in manifest["outfits"].values():
        textures.update(o["textures"])
    tex_sha = {}
    for root, _dirs, names in os.walk(os.path.join(out, "tex")):
        for n in sorted(names):
            tex_sha[n] = sha_file(os.path.join(root, n))
    geometry = {
        "body_slim": manifest["builds"]["slim"]["parts"] | manifest["builds"]["slim"]["extras"],
        "body_broad": manifest["builds"]["broad"]["parts"] | manifest["builds"]["broad"]["extras"],
        "head": {"Head": manifest["builds"]["slim"]["parts"]["Head"]},
        "headwear": {k: {kk: vv for kk, vv in v.items() if kk != "textures"} for k, v in manifest["headwear"]["items"].items()},
        "looks": {"square": SQUARE, "names": [n for n, _m in keys]},
    }
    uses = {
        "body_slim": ["body_shirt"], "body_broad": ["body_shirt"], "head": ["head_plain_calm", "head_normal", "head_roughness"],
        "headwear": ["headwear_a", "headwear_b"], "looks": [m for _n, m in keys] + ["head_normal", "head_roughness"],
    }
    for key in FILES:
        blob = {"geometry": geometry[key], "objects": files[key]["objects"],
                "textures": {n: s for n, s in tex_sha.items() if any(n.startswith(u) for u in uses[key])}}
        files[key]["content"] = hashlib.sha256(json.dumps(blob, sort_keys=True).encode()).hexdigest()[:16]
    doc = {"format": "spicy-people-upload/1", "manifest": "manifest.json", "files": files}
    with open(os.path.join(up, "upload.json"), "w") as fh:
        json.dump(doc, fh, indent=1)
    for key in FILES:
        f = files[key]
        print(f"[export] {key}: {len(f['objects'])} objects, {sum(f['tris'].values())} triangles, {f['bytes']} bytes, {f['content']}",
              flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]))
