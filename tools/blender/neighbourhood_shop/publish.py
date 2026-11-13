"""Upload the Neighbourhood Shop's FBXs as Roblox Models and write data/art/neighbourhood_shop.json (stdlib only).

  python3 -I tools/blender/neighbourhood_shop/publish.py [--build build/art/neighbourhood_shop] [--skip-upload]

Run tools/blender/neighbourhood_shop/export_shop.py first. For proof.fbx (the five cafe stools: the upload is
proved on a small piece first), shop.fbx and roof.fbx this runs
  node tools/cloud/cloud.mjs upload_asset <fbx> --type Model --name <name>
(the CLI holds the shared cloud write lock and token buckets; the proxy injects the key, nothing here handles
one) and keeps each result in <build>/uploads/<tag>.json with the FBX's hash, so a rerun only uploads what
changed. Then it writes data/art/neighbourhood_shop.json: the asset ids and moderation states, and the
manifest the bake (tools/bake/neighbourhood_shop.luau) and the loader (Server/Assets/ShopArt) read.
"""
import argparse
import hashlib
import json
import os
import subprocess
import sys
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
OUT = os.path.join(ROOT, "data", "art", "neighbourhood_shop.json")
UPLOADS = [
    ("proof", "proof.fbx", "SR shop proof cafe stools",
     "Spicy Rodent: the Neighbourhood Shop's five cafe stools (owner's art, upload proof). tools/blender/neighbourhood_shop"),
    ("shop", "shop.fbx", "SR The Neighbourhood Shop interior",
     "Spicy Rodent: the owner's Neighbourhood Shop (retail, cafe, back office), 355 meshes, 3 studs per metre. tools/blender/neighbourhood_shop"),
    ("roof", "roof.fbx", "SR Neighbourhood Shop gable roof",
     "Spicy Rodent: the owner's 14 m gable roof kit, fitted to the Neighbourhood Shop. tools/blender/neighbourhood_shop"),
]


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        h.update(fh.read())
    return h.hexdigest()[:16]


def upload(build, tag, fbx, name, desc, skip):
    rec_path = os.path.join(build, "uploads", f"{tag}.json")
    path = os.path.join(build, fbx)
    digest = sha(path)
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
        sys.exit(f"upload {tag} failed:\n{r.stderr[-2000:]}")
    with open(rec_path) as fh:
        res = json.load(fh)
    res["sourceSha"] = digest
    res["uploadSeconds"] = round(time.time() - t0, 1)
    res.pop("raw", None)
    with open(rec_path, "w") as fh:
        json.dump(res, fh, indent=2)
    print(f"  uploaded {tag}: {res.get('assetId')} ({res.get('moderationState')}) in {res['uploadSeconds']} s", flush=True)
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--build", default=os.path.join(ROOT, "build", "art", "neighbourhood_shop"))
    ap.add_argument("--skip-upload", action="store_true")
    a = ap.parse_args()
    build = os.path.abspath(a.build)
    with open(os.path.join(build, "manifest.json")) as fh:
        manifest = json.load(fh)
    assets = {}
    for tag, fbx, name, desc in UPLOADS:
        res = upload(build, tag, fbx, name, desc, a.skip_upload)
        assets[tag] = {
            "assetId": res.get("assetId"),
            "moderation": res.get("moderationState"),
            "displayName": name,
            "fbxBytes": os.path.getsize(os.path.join(build, fbx)),
            "sha": res.get("sourceSha"),
        }
    doc = {
        "$schema": "art/neighbourhood_shop v1",
        "src": "tools/blender/neighbourhood_shop (export_shop.py: the owner's GLBs as FBX in studs; publish.py: the upload).",
        "placement": "InsertService:LoadAsset(assetId):GetChildren()[1] is a Model whose pivot is the FBX origin = the centre "
                     "of the shop floor; PivotTo(the venue's pivot) puts every MeshPart at its `centre` (venue frame at yaw 0). "
                     "Each MeshPart is unrotated. Untextured materials may arrive grey: Server/Assets/ShopArt paints a MeshPart "
                     "without a SurfaceAppearance with its `colour`; `alpha` < 1 is glass.",
        "assets": assets,
    }
    for k, v in manifest.items():
        if k not in ("fbx", "format"):
            doc[k] = v
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as fh:
        json.dump(doc, fh, indent=1)
        fh.write("\n")
    print(f"wrote {os.path.relpath(OUT, ROOT)}: " + ", ".join(f"{k} {v['assetId']} ({v['moderation']})" for k, v in assets.items()))


if __name__ == "__main__":
    main()
