"""Upload the pinball FBXs as Roblox Models and write data/art/pinball.json (stdlib only).

  python3 -I tools/blender/pinball/publish.py [--build build/art/pinball] [--skip-upload]

Run tools/blender/pinball/export_pinball.py first (after boards.py and backglass.py). For each of the eight
Models (the shared flipper, bumper, plunger, gate and cabinet; the acorn, rodent and space machines) this runs
  node tools/cloud/cloud.mjs upload_asset <fbx> --type Model --name <name>
(the CLI holds the shared cloud write lock and token buckets; the proxy injects the key, nothing here handles
one) and keeps each result in <build>/uploads/<tag>.json with a digest of what the Model holds (content_digest),
so a rerun only uploads what changed; with no cache (a fresh clone) it reuses the ids data/art/pinball.json
records for the same content. With --skip-upload nothing is uploaded and a Model not uploaded before keeps an
empty id (the loader then leaves the baked machines as they are). Then it writes data/art/pinball.json: the
asset ids and moderation states and the manifest the loader (Server/Assets/PinballArt, through
generated/PinballArt from tools/compile) reads.
"""
import argparse
import hashlib
import json
import os
import subprocess
import sys
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
OUT = os.path.join(ROOT, "data", "art", "pinball.json")
UPLOADS = [
    ("flipper", "SR pinball flipper", "Spicy Rodent: the pinball flipper (bat, tip, pin), shared by the three machines."),
    ("bumper", "SR pinball pop bumper", "Spicy Rodent: the pinball pop bumper (body, cap, ring), scaled per machine."),
    ("plunger", "SR pinball plunger", "Spicy Rodent: the pinball plunger (rod and knob)."),
    ("gate", "SR pinball gate", "Spicy Rodent: the pinball one-way wire gate."),
    ("cabinet", "SR pinball cabinet", "Spicy Rodent: the pinball cabinet, recoloured per machine. FREE PLAY, no coins."),
    ("acorn", "SR pinball Acorn Attack playfield", "Spicy Rodent: ACORN ATTACK's playfield, guides, slingshots, targets, spinner, backglass."),
    ("rodent", "SR pinball Spicy Rodent playfield", "Spicy Rodent: SPICY RODENT's playfield, guides, slingshots, targets, the wire, backglass."),
    ("space", "SR pinball Space Squirrel playfield", "Spicy Rodent: SPACE SQUIRREL's playfield, guides, slingshots, targets, ramps, pod hoods, backglass."),
]


def content_digest(manifest, tag):
    """What a Model holds, as the manifest records it (the FBX bytes carry export timestamps, so the file's own
    hash changes on every export): its meshes, its sources' and its textures' checksums, the scale."""
    m = manifest["models"][tag]
    textures = sorted({r["texture"] for r in m["meshes"] if r.get("texture")})
    blob = json.dumps({"meshes": m["meshes"], "sources": m["sources"], "scale": manifest["scale"],
                       "textures": {t: manifest["textures"][t] for t in textures}}, sort_keys=True)
    return hashlib.sha256(blob.encode()).hexdigest()[:16]


def committed(tag, digest):
    """The upload data/art/pinball.json already records for this tag, if it holds the same content."""
    if not os.path.exists(OUT):
        return None
    with open(OUT) as fh:
        a = json.load(fh).get("assets", {}).get(tag)
    if a and a.get("sha") == digest and a.get("assetId"):
        return {"assetId": a["assetId"], "moderationState": a.get("moderation"), "sourceSha": digest}
    return None


def upload(build, tag, name, desc, skip, digest):
    rec_path = os.path.join(build, "uploads", f"{tag}.json")
    path = os.path.join(build, f"{tag}.fbx")
    if os.path.exists(rec_path):
        with open(rec_path) as fh:
            old = json.load(fh)
        if old.get("sourceSha") == digest and old.get("assetId"):
            return old
    seeded = committed(tag, digest)
    if seeded:
        os.makedirs(os.path.dirname(rec_path), exist_ok=True)
        with open(rec_path, "w") as fh:
            json.dump(seeded, fh, indent=2)
        return seeded
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
    ap.add_argument("--build", default=os.path.join(ROOT, "build", "art", "pinball"))
    ap.add_argument("--skip-upload", action="store_true")
    a = ap.parse_args()
    build = os.path.abspath(a.build)
    with open(os.path.join(build, "manifest.json")) as fh:
        manifest = json.load(fh)
    assets = {}
    for tag, name, desc in UPLOADS:
        m = manifest["models"][tag]
        res = upload(build, tag, name, desc, a.skip_upload, content_digest(manifest, tag))
        assets[tag] = {
            "assetId": res.get("assetId"),
            "moderation": res.get("moderationState"),
            "displayName": name,
            "fbxBytes": os.path.getsize(os.path.join(build, m["fbx"])),
            "tris": m["tris"],
            "sha": res.get("sourceSha"),
        }
    doc = {
        "$schema": "art/pinball v1",
        "src": "tools/blender/pinball (boards.py, backglass.py: the textures; export_pinball.py: ChatGPT's GLBs as FBX in "
               "studs; publish.py: the upload).",
        "placement": "InsertService:LoadAsset(assetId) holds a Model of unrotated MeshParts, each centred on its bounding box "
                     "in its frame (export_pinball.py's header); Server/Assets/PinballArt puts each at frame * centre, "
                     "colours it (its `colour`, or the machine's THEMES colour for a `theme`), and keeps a textured one's "
                     "map (`fallback` if the importer drops it); `alpha` < 1 is see-through.",
        "assets": assets,
        "scale": manifest["scale"],
        "bumperRadius": manifest["bumperRadius"],
        "gateHinge": manifest["gateHinge"],
        "data": manifest["data"],
        "textures": manifest["textures"],
        "models": {tag: {"frame": m["frame"], "meshes": m["meshes"], "sources": m["sources"]}
                   for tag, m in manifest["models"].items()},
    }
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as fh:
        json.dump(doc, fh, indent=1)
        fh.write("\n")
    print(f"wrote {os.path.relpath(OUT, ROOT)}: " + ", ".join(f"{k} {v['assetId']} ({v['moderation']})" for k, v in assets.items()))


if __name__ == "__main__":
    main()
