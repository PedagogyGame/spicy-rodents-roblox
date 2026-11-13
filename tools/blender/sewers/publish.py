"""Upload the sewer modules' FBXs as Roblox Models and write data/art/sewer_modules.json (stdlib only).

  python3 -I tools/blender/sewers/publish.py [--build build/art/sewers] [--skip-upload]

Run tools/blender/sewers/export_modules.py first. For each variant in its manifest this runs
  node tools/cloud/cloud.mjs upload_asset <variant>.fbx --type Model --name <name>
(the CLI holds the shared cloud write lock and token buckets; the proxy injects the key, nothing here handles one)
and keeps each result in <build>/uploads/<variant>.json with a digest of what the Model holds (the FBX bytes carry
export timestamps, so the file's own hash changes on every export), so a rerun only uploads what changed. Then it
writes data/art/sewer_modules.json: the asset ids and moderation states, and the manifest the bake
(tools/bake/sewers.luau) and the art loader read (the meshes, the lanes the squirrel may run, his metadata).
"""
import argparse
import hashlib
import json
import os
import subprocess
import sys
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
OUT = os.path.join(ROOT, "data", "art", "sewer_modules.json")
NAMES = {
    "brick": ("SR sewer brick passage", "the owner's 12 m brick sewer passage (01), handrails left out"),
    "brickPlain": ("SR sewer brick passage plain", "the owner's brick passage (01) without footbridge, valve, label"),
    "junction": ("SR sewer four-way junction", "the owner's four-way sewer junction (02)"),
    "dry": ("SR sewer dry maintenance tunnel", "the owner's 12 m concrete maintenance tunnel (03)"),
    "dryPlain": ("SR sewer dry tunnel plain", "the owner's maintenance tunnel (03) without pump, door, panel, plaque"),
    "marker": ("SR sewer Dry Side plaque", "the owner's Dry Side / Mind Your Paws plaque"),
}


def content_digest(manifest, variant):
    m = manifest["modules"][variant]
    blob = json.dumps({"meshes": m["meshes"], "leftOut": m["leftOut"], "source": manifest["sources"][m["source"]],
                       "scale": manifest["studsPerMetre"]}, sort_keys=True)
    return hashlib.sha256(blob.encode()).hexdigest()[:16]


def upload(build, variant, name, desc, skip, digest):
    rec_path = os.path.join(build, "uploads", f"{variant}.json")
    path = os.path.join(build, f"{variant}.fbx")
    if os.path.exists(rec_path):
        with open(rec_path) as fh:
            old = json.load(fh)
        if old.get("sourceSha") == digest and old.get("assetId"):
            return old
    if skip:
        return {"assetId": None, "moderationState": "not uploaded", "sourceSha": digest}
    assert len(name) <= 50, name
    os.makedirs(os.path.dirname(rec_path), exist_ok=True)
    t0 = time.time()
    r = subprocess.run(["node", "tools/cloud/cloud.mjs", "upload_asset", path, "--type", "Model", "--name", name,
                        "--description", desc, "--out", rec_path], cwd=ROOT, capture_output=True, text=True, timeout=1200)
    if r.returncode != 0 or not os.path.exists(rec_path):
        sys.exit(f"upload {variant} failed:\n{r.stderr[-2000:]}")
    with open(rec_path) as fh:
        res = json.load(fh)
    res["sourceSha"] = digest
    res["uploadSeconds"] = round(time.time() - t0, 1)
    res.pop("raw", None)
    with open(rec_path, "w") as fh:
        json.dump(res, fh, indent=2)
    print(f"  uploaded {variant}: {res.get('assetId')} ({res.get('moderationState')}) in {res['uploadSeconds']} s", flush=True)
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--build", default=os.path.join(ROOT, "build", "art", "sewers"))
    ap.add_argument("--skip-upload", action="store_true")
    a = ap.parse_args()
    build = os.path.abspath(a.build)
    with open(os.path.join(build, "manifest.json")) as fh:
        manifest = json.load(fh)
    modules = {}
    for variant, m in manifest["modules"].items():
        name, what = NAMES[variant]
        desc = f"Spicy Rodent: {what}, one stud per metre. tools/blender/sewers"
        res = upload(build, variant, name, desc, a.skip_upload, content_digest(manifest, variant))
        entry = {
            "assetId": res.get("assetId"),
            "moderation": res.get("moderationState"),
            "displayName": name,
            "sha": res.get("sourceSha"),
        }
        entry.update({k: v for k, v in m.items() if k not in ("fbx",)})
        modules[variant] = entry
    doc = {
        "$schema": "art/sewer_modules v1",
        "src": "tools/blender/sewers (export_modules.py: the owner's sewer GLBs as FBX in studs, one per metre, and "
               "the lane check; publish.py: the upload).",
        "placement": "InsertService:LoadAsset(assetId):GetChildren()[1] is a Model whose pivot is the FBX origin: the "
                     "module's centre on its walkway top (junction: the centre of its floor). Pivot it to a slot's "
                     "ArtPivot (Workspace.Sewers.<pipe>.Art.<slot>); each MeshPart arrives unrotated at its `centre` "
                     "in the module frame (X across, Y up, Z along). Make every part visual only: the bake's Lining "
                     "parts carry the collision, the camera and the light backing; once a pipe's slots are filled, "
                     "set its Lining parts' Transparency to 1 (keep their collision).",
        "studsPerMetre": manifest["studsPerMetre"],
        "modules": modules,
        "metadata": manifest["metadata"],
        "sources": manifest["sources"],
    }
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as fh:
        json.dump(doc, fh, indent=1)
        fh.write("\n")
    print(f"wrote {os.path.relpath(OUT, ROOT)}: "
          + ", ".join(f"{k} {v['assetId']} ({v['moderation']})" for k, v in modules.items()))


if __name__ == "__main__":
    main()
