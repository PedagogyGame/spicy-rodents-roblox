"""Build one hero animal end to end (headless bpy 5.2.3, 2 CPU threads):

  taskset -c 2,3 /root/.cache/spicy-rodents/venv/bin/python -I tools/blender/heroes/build_hero.py \
      --species squirrel [--variant rodent] --out build/heroes/squirrel [--quick] [--stages all]

Stages: geometry (SDF sculpt -> high-poly for baking, decimated low-poly, claws/teeth, UVs),
rig (exported armature + proxy heat weights, <= 4 influences, no Root weights), textures (Cycles
bake of the high-poly detail + procedural fur painting into 1024 px colour/normal/roughness maps,
TintMask-friendly colour), parts (eyes, fur cards, blood, RootPart), clips (keyframed actions ->
spicy-clip/1 JSON), export (FBX for Open Cloud Model upload) and a report. Writes into --out:
  <name>.blend, <name>.fbx, tex/*.png, clips/<rig>_<Clip>.clip.json, report.json
"""
import argparse
import importlib
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.dirname(HERE))

import bpy  # noqa: E402
import numpy as np  # noqa: E402

import bl  # noqa: E402
import geometry  # noqa: E402
import rig  # noqa: E402
import sdf  # noqa: E402

SPECIES_MODULES = {"squirrel": "species_squirrel", "rodent": "species_squirrel", "fox": "species_fox", "deer": "species_deer"}


class Log:
    def __init__(self):
        self.t0 = time.time()
        self.steps = []

    def __call__(self, msg):
        dt = time.time() - self.t0
        self.steps.append([round(dt, 1), msg])
        print(f"[hero {dt:7.1f}s] {msg}", flush=True)


def build_geometry(sp, variant, opts, log):
    prims = sp.sculpt(variant)
    body = sdf.Body(prims)
    hi = geometry.sculpt_mesh(body, opts.h_hi, "HighPoly")
    log(f"high-poly {len(hi.data.vertices)} verts, {bl.tri_count(hi.data)} tris (h={opts.h_hi})")
    lo = geometry.sculpt_mesh(body, opts.h_lo, "LowPoly")
    n0 = bl.tri_count(lo.data)
    tris = geometry.decimate_to(lo, sp.BUDGET["body_tris"])
    log(f"low-poly {n0} -> {tris} tris")
    return body, hi, lo


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--species", required=True, choices=["squirrel", "rodent", "fox", "deer"])
    ap.add_argument("--variant", default=None)
    ap.add_argument("--out", required=True)
    ap.add_argument("--quick", action="store_true", help="coarse grids, 512 px maps, fewer samples")
    ap.add_argument("--stages", default="all")
    opts = ap.parse_args(argv)
    variant = opts.variant or opts.species
    sp = importlib.import_module(SPECIES_MODULES[opts.species])
    opts.out = os.path.abspath(opts.out)
    os.makedirs(opts.out, exist_ok=True)
    log = Log()
    scale = getattr(sp, "SCALE", 1.0)
    opts.h_hi = (0.009 if opts.quick else 0.0055) * scale
    opts.h_lo = (0.014 if opts.quick else 0.011) * scale
    opts.tex = 512 if opts.quick else 1024
    bl.reset_scene()
    skel = sp.skeleton()
    bone_names = [b[0] for b in skel]

    body, hi, lo = build_geometry(sp, variant, opts, log)
    import hero  # noqa: E402  (the rest of the pipeline)

    report = hero.finish(sp, variant, skel, bone_names, body, hi, lo, opts, log)
    report["log"] = log.steps
    with open(os.path.join(opts.out, "report.json"), "w") as fh:
        json.dump(report, fh, indent=2)
    log("done")
    return 0


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else sys.argv[1:]
    sys.exit(main(argv))
