"""Upload the D34 woods kinds (grove.py's Models) and write data/art/woods.json (stdlib only).

  python3 -I tools/blender/trees/publish_woods.py --build build/art/woods [--kinds white_pine,hazel] \
      [--skip-upload | --dry-run]

Run first (headless Blender): grove.py --kinds all --fbx --out <build>   (<kind>.fbx + <kind>.json with its mesh digest)
A kind whose checks fail (wood over a walk's feet, bark off the trunk's climbing radius by more than TRUNK_TOL, a leaf
in a tunnel, over its triangle budget) is held back: listed, never uploaded, so its trees keep their stand-ins. For
every other kind this runs
  node tools/cloud/cloud.mjs upload_asset <kind>.fbx --type Model --name "SR woods <LABEL>" --description ...
(the CLI holds the shared cloud write lock and token buckets; the proxy injects the key, nothing here handles one) and
keeps the result in <build>/uploads/<kind>.json with the kind's mesh digest, so a rerun uploads only what changed; with
no cache it reuses the id data/art/woods.json already records for the same digest.
--skip-upload writes the data with the ids it has (none before the first upload); --dry-run prints every command it
would run and writes nothing.

data/art/woods.json -> tools/compile (lib/TreeShapes: the woods' `art`) -> generated/TreeShapes -> Server/Assets/WoodsArt
loads each kind's Model once and stands it at every woods tree of the kind.
"""
import argparse
import json
import os
import subprocess
import sys
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
OUT = os.path.join(ROOT, "data", "art", "woods.json")
DESCRIPTION = "Spicy Rodent: a climbable tree of the town's woods (tools/blender/trees/grove.py, D34)."
BUDGET = {"giant": (7600, 8000), "hazel": (1600, 2000), "other": (2600, 2800)}
TRUNK_TOL = 0.35  # studs: the bark against the squirrel's trunk radius, away from where boughs and whorls leave


def display_name(info):
    return f"SR woods {info['label']}".strip()[:50]


def verdict(info):
    c = info["checks"]
    fam = "giant" if info["family"] == "giant" else ("hazel" if info["kind"] == "hazel" else "other")
    bark_max, leaf_max = BUDGET[fam]
    fail = []
    if c["feet_with_bark_over"]:
        fail.append(f"wood over the feet at {c['feet_with_bark_over']} samples")
    if (c["trunk_bark_minus_radius_st"].get("max_abs") or 0) > TRUNK_TOL:
        fail.append(f"trunk bark {c['trunk_bark_minus_radius_st']['max_abs']} off the climbing radius")
    if (c["feet_to_bark_under_st"].get("max_abs") or 0) > TRUNK_TOL:
        fail.append(f"feet {c['feet_to_bark_under_st']['max_abs']} off the bark")
    if c["leaf_min_clearance_st"] is not None and c["leaf_min_clearance_st"] < 0:
        fail.append(f"a leaf {c['leaf_min_clearance_st']} into a tunnel")
    if info["tris"]["bark"] > bark_max or info["tris"]["leaves"] > leaf_max:
        fail.append(f"over budget ({info['tris']})")
    return fail


def committed(kind, digest):
    if not os.path.exists(OUT):
        return None
    with open(OUT) as fh:
        for k in json.load(fh).get("kinds", []):
            if k["kind"] == kind and k.get("sha") == digest and k.get("assetId"):
                return {"assetId": k["assetId"], "moderationState": k.get("moderation"), "sourceSha": digest,
                        "name": k.get("displayName")}
    return None


def upload(build, info, skip, dry):
    kind, digest = info["kind"], info["sha"]
    rec_path = os.path.join(build, "uploads", f"{kind}.json")
    if os.path.exists(rec_path):
        with open(rec_path) as fh:
            old = json.load(fh)
        if old.get("sourceSha") == digest and old.get("assetId"):
            return old
    seeded = committed(kind, digest)
    if seeded:
        return seeded
    cmd = ["node", "tools/cloud/cloud.mjs", "upload_asset", info["fbx"], "--type", "Model", "--name", display_name(info),
           "--description", DESCRIPTION, "--out", rec_path]
    if dry:
        print("  " + " ".join(f'"{c}"' if " " in c else c for c in cmd))
        return {"assetId": None, "moderationState": "dry run", "sourceSha": digest}
    if skip:
        return {"assetId": None, "moderationState": "not uploaded", "sourceSha": digest}
    os.makedirs(os.path.dirname(rec_path), exist_ok=True)
    t0 = time.time()
    r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=1200)
    if r.returncode != 0 or not os.path.exists(rec_path):
        sys.exit(f"upload {kind} failed:\n{r.stderr[-2000:]}")
    with open(rec_path) as fh:
        rec = json.load(fh)
    rec["sourceSha"] = digest
    with open(rec_path, "w") as fh:
        json.dump(rec, fh, indent=2)
    print(f"  uploaded {kind}: {rec.get('assetId')} ({rec.get('moderationState')}) in {time.time() - t0:.1f} s")
    return rec


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--build", default="build/art/woods")
    ap.add_argument("--kinds", default="all")
    ap.add_argument("--skip-upload", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    build = os.path.abspath(a.build)
    infos = []
    for fn in sorted(os.listdir(build)):
        if fn.endswith(".json") and fn not in ("summary.json",) and os.path.exists(os.path.join(build, fn[:-5] + ".fbx")):
            with open(os.path.join(build, fn)) as fh:
                infos.append(json.load(fh))
    if a.kinds != "all":
        want = set(a.kinds.split(","))
        infos = [i for i in infos if i["kind"] in want]
    kinds, held = [], []
    totals = {"bark": 0, "leaves": 0, "total": 0, "fbxBytes": 0}
    if a.dry_run:
        print("publish_woods: the commands an upload runs (from the repo root):")
    for info in infos:
        fail = verdict(info)
        rec = {"assetId": None, "moderationState": "held back"} if fail else upload(build, info, a.skip_upload, a.dry_run)
        if fail:
            held.append(info["kind"])
            print(f"  held back {info['kind']}: {'; '.join(fail)}")
        checks = dict(info["checks"])
        checks["ok"] = not fail
        checks["fail"] = fail
        kinds.append({
            "kind": info["kind"], "label": info["label"], "species": info["species"], "family": info["family"],
            "assetId": rec.get("assetId"), "displayName": display_name(info), "moderation": rec.get("moderationState"),
            "sha": info["sha"], "fbxBytes": info.get("fbxBytes"), "tris": info["tris"], "heightStuds": info["heightStuds"],
            "crownMeasured": info["crownMeasured"], "parts": info["parts"], "checks": checks,
        })
        for k in ("bark", "leaves", "total"):
            totals[k] += info["tris"][k]
        totals["fbxBytes"] += info.get("fbxBytes") or 0
    doc = {
        "$schema": "woods art v1 (tools/blender/trees/publish_woods.py; tools/compile lib/TreeShapes reads it)",
        "src": "BRIEF_ADDENDUM D34/D35: the woods' kinds built round their climbing templates by tools/blender/trees/grove.py "
               "(data/woods.json kinds). One Model per kind, parts Bark (tiling bark) and Leaves (two-faced spray cards, the "
               "fruit in a swatch of the atlas; AlphaMode Transparency or the colour map on TextureID). pivot = the ground "
               "under the trunk's foot; WoodsArt turns, scales and stands it at every woods tree of the kind. Ids empty until "
               "the lead uploads (assetId null).",
        "count": len(kinds), "held": held, "totals": totals, "kinds": kinds,
    }
    if a.dry_run:
        print(f"publish_woods: {len(kinds)} kinds, {len(held)} held; {totals['total']:,} triangles, "
              f"{totals['fbxBytes'] / 1e6:.1f} MB of FBX (dry run: nothing written)")
        return
    with open(OUT, "w") as fh:
        json.dump(doc, fh, indent=1)
        fh.write("\n")
    print(f"wrote data/art/woods.json: {len(kinds)} kinds, {sum(1 for k in kinds if k['assetId'])} with an id, "
          f"{len(held)} held; {totals['total']:,} triangles, {totals['fbxBytes'] / 1e6:.1f} MB of FBX")


if __name__ == "__main__":
    main()
