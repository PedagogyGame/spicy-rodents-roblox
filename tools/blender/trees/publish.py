"""Upload the route-true trees (the new generator) as Roblox Models and write data/art/trees_v2.json (stdlib only).

  python3 -I tools/blender/trees/publish.py --build build/art/trees_new --promises build/art/trees_new/promises.json \
      --hollows build/art/trees_new/hollows_check.json [--skip-upload] [--ids 0,1,2]

Run first (headless Blender, tools/blender/trees):
  build_trees.py --ids all --fbx --out <build>            tree_NNN.fbx + tree_NNN.json (with the mesh digest "sha")
  check_promises.py --dir <build> --clearance-warn --json <build>/promises.json     the routes on the bark
  check_hollows.py --dir <build> --json <build>/hollows_check.json                   the hollow trees' boards
A tree with a broken promise is held back: listed with its checks, never uploaded, so the game keeps its live tree.
For every other tree this runs
  node tools/cloud/cloud.mjs upload_asset tree_NNN.fbx --type Model --name "SR tree v2 NNN <LABEL>"
(the CLI holds the shared cloud write lock and token buckets; the proxy injects the key, nothing here handles one)
and keeps each result in <build>/uploads/tree_NNN.json with the tree's mesh digest, so a rerun only uploads what
changed; with no cache (a fresh clone) it reuses the id data/art/trees_v2.json records for the same digest.
--skip-upload writes the data with the ids it already has (none before the first upload).

data/art/trees_v2.json -> tools/compile (lib/TreeArtNext) -> generated/TreeArtNext.luau: Server/Assets/TreeArt
swaps a baked tree's meshes for its v2 Model once that Model has an id. The live trees stay data/art/trees.json.
"""
import argparse
import json
import os
import subprocess
import sys
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
OUT = os.path.join(ROOT, "data", "art", "trees_v2.json")
DESCRIPTION = "Spicy Rodent: a town tree built round the squirrel's climbing routes (tools/blender/trees, v2)."
PART_ROLES = {
    "Bark": "trunk, roots, boughs, bridges, side branches and twigs: one skin, the climbing surfaces (visual only in "
            "the game: the baked proxies collide)",
    "LeavesShade": "leaf sprays under the canopy (alpha cards: DoubleSided, AlphaMode Transparency)",
    "LeavesMid": "leaf sprays in half light (alpha cards)",
    "LeavesSun": "leaf sprays that see the sky (alpha cards)",
    "Apples": "fruit",
}


def display_name(idx, label):
    return f"SR tree v2 {idx:03d} {label}".strip()[:50]


def committed(index, digest):
    """The upload data/art/trees_v2.json already records for this tree, if it holds the same meshes."""
    if not os.path.exists(OUT):
        return None
    with open(OUT) as fh:
        for t in json.load(fh).get("trees", []):
            if t["index"] == index and t.get("sha") == digest and t.get("assetId"):
                return {"assetId": t["assetId"], "moderationState": t.get("moderation"), "sourceSha": digest,
                        "name": t.get("displayName")}
    return None


def upload(build, info, skip):
    i, digest = info["index"], info["sha"]
    rec_path = os.path.join(build, "uploads", f"tree_{i:03d}.json")
    if os.path.exists(rec_path):
        with open(rec_path) as fh:
            old = json.load(fh)
        if old.get("sourceSha") == digest and old.get("assetId"):
            return old
    seeded = committed(i, digest)
    if seeded:
        os.makedirs(os.path.dirname(rec_path), exist_ok=True)
        with open(rec_path, "w") as fh:
            json.dump(seeded, fh, indent=2)
        return seeded
    if skip:
        return {"assetId": None, "moderationState": "not uploaded", "sourceSha": digest}
    name = display_name(i, info["label"])
    os.makedirs(os.path.dirname(rec_path), exist_ok=True)
    t0 = time.time()
    r = subprocess.run(["node", "tools/cloud/cloud.mjs", "upload_asset", info["fbx"], "--type", "Model", "--name", name,
                        "--description", DESCRIPTION, "--out", rec_path], cwd=ROOT, capture_output=True, text=True,
                       timeout=1200)
    if r.returncode != 0 or not os.path.exists(rec_path):
        sys.exit(f"upload tree {i:03d} failed:\n{r.stderr[-2000:]}")
    with open(rec_path) as fh:
        res = json.load(fh)
    res["sourceSha"] = digest
    res["name"] = name
    res["uploadSeconds"] = round(time.time() - t0, 1)
    res.pop("raw", None)
    with open(rec_path, "w") as fh:
        json.dump(res, fh, indent=2)
    print(f"  uploaded tree {i:03d}: {res.get('assetId')} ({res.get('moderationState')}) in {res['uploadSeconds']} s",
          flush=True)
    return res


def load_reports(path, key):
    if not path:
        return {}
    with open(path) as fh:
        return {r[key]: r for r in json.load(fh)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--build", default=os.path.join(ROOT, "build", "art", "trees_new"))
    ap.add_argument("--promises", required=True, help="check_promises.py --clearance-warn --json output")
    ap.add_argument("--hollows", default="", help="check_hollows.py --json output")
    ap.add_argument("--ids", default="all", help="upload only these (the data always lists every tree built)")
    ap.add_argument("--skip-upload", action="store_true")
    ap.add_argument("--merge", action="store_true",
                    help="change only the trees built in --build (the D32 reshaped trees: build_trees.py --shapes "
                         "--ids shapes); without an id a rebuilt tree waits as its record's \"pending\" Model")
    a = ap.parse_args()
    build = os.path.abspath(a.build)
    infos = []
    for fn in sorted(os.listdir(build)):
        if fn.startswith("tree_") and fn.endswith(".json") and fn[5:8].isdigit():
            with open(os.path.join(build, fn)) as fh:
                infos.append(json.load(fh))
    promises = load_reports(a.promises, "index")
    hollows = {}
    for r in load_reports(a.hollows, "hollow").values():
        hollows[r["tree"]] = r
    missing = [i["index"] for i in infos if i["index"] not in promises]
    if missing:
        sys.exit(f"not published: trees {missing} have not been checked")
    held = {i["index"] for i in infos if promises[i["index"]]["fail"]} | {t for t, r in hollows.items() if r["fail"]}
    if held:
        print(f"held back (a broken promise: never uploaded, the live tree stays): {sorted(held)}")
    wanted = None if a.ids == "all" else {int(x) for x in a.ids.split(",") if x.strip()}
    trees, totals = [], {"bark": 0, "leaves": 0, "fruit": 0, "total": 0, "fbxBytes": 0}
    for info in infos:
        i = info["index"]
        skip = a.skip_upload or (wanted is not None and i not in wanted)
        if i in held:
            res = {"assetId": None, "moderationState": "held: broken promise"}
        else:
            res = upload(build, info, skip)
        tris = info["tris"]
        leaves = tris["leaves_shade"] + tris["leaves_mid"] + tris["leaves_sun"]
        rep = promises[i]
        rec = {
            "index": i, "label": info["label"], "species": info["species"], "category": info["category"],
            "trunkRoute": info["trunkRoute"], "routes": info["routes"], "pivot": info["pivot"],
            "heightStuds": info["heightStuds"],
            "assetId": res.get("assetId"), "displayName": res.get("name") or display_name(i, info["label"]),
            "moderation": res.get("moderationState"), "sha": info["sha"], "fbxBytes": info["fbxBytes"],
            "tris": {"bark": tris["bark"], "leaves": leaves, "fruit": tris["fruit"], "total": tris["total"]},
            "parts": info["parts"],
            "checks": {"promisesBroken": len(rep["fail"]), "promiseWarnings": len(rep["warn"])},
        }
        if i in hollows:
            rec["checks"]["hollow"] = hollows[i]["hollow"]
            rec["checks"]["hollowBoardMargin"] = hollows[i]["min_margin"]
        trees.append(rec)
    if a.merge:
        # only the trees in --build change; every other record stays as data/art/trees_v2.json has it. A rebuilt
        # tree that has no id yet keeps its live Model and carries the rebuilt one as "pending" (sha, fbx, routes,
        # parts, tris) until it is uploaded (then the record is the new Model's, and tools/compile lib/TreeShapes
        # lists the grown boughs it covers)
        with open(OUT) as fh:
            by = {t["index"]: t for t in json.load(fh)["trees"]}
        for rec in trees:
            prev = by.get(rec["index"])
            if rec["assetId"] or prev is None:
                by[rec["index"]] = rec
            else:
                keep = {k: v for k, v in prev.items() if k != "pending"}
                keep["pending"] = {k: rec[k] for k in ("sha", "fbxBytes", "tris", "routes", "parts", "checks")}
                keep["pending"]["fbx"] = os.path.relpath(os.path.join(build, f"tree_{rec['index']:03d}.fbx"), ROOT)
                keep["pending"]["state"] = rec["moderation"]
                by[rec["index"]] = keep
        trees = [by[k] for k in sorted(by)]
    for rec in trees:
        for k in ("bark", "leaves", "fruit", "total"):
            totals[k] += rec["tris"][k]
        totals["fbxBytes"] += rec["fbxBytes"]
    doc = {
        "$schema": "art/trees v2",
        "src": "tools/blender/trees (build_trees.py: treegen.py geometry, textures.py maps; check_promises.py, "
               "check_hollows.py; publish.py: the upload). Procedural Blender only.",
        "units": "studs, Roblox axes (+Y up). pivot = the tree's root on the ground (data/harvest/trees.json root x 2.5).",
        "placement": "model = InsertService:LoadAsset(assetId):GetChildren()[1]; its pivot is the FBX origin = the tree "
                     "root, so model:PivotTo(CFrame.new(pivot)) puts every MeshPart at pivot + parts[name].center, "
                     "unrotated. The trunk carries 3 studs of bark below the pivot. To ship: after the upload, run "
                     "tools/cloud/tasks/tree_load.luau on one Model (do the leaves take DoubleSided and AlphaMode "
                     "Transparency?), then rebake from these (harvest_meshes.py --art data/art/trees_v2.json, then "
                     "the bake: Lune writes DoubleSided and Box collision fidelity). Server/Assets/TreeArt's swap is "
                     "the fallback: it lays these over a baked tree's meshes at runtime (visual only: the baked "
                     "proxies keep colliding; Default fidelity, which a script cannot change) only where the leaves "
                     "read both writes back, and otherwise keeps the baked tree.",
        "partRoles": {k: v for k, v in PART_ROLES.items()},
        "count": len(trees),
        "totals": totals,
        "trees": trees,
    }
    with open(OUT, "w") as fh:
        json.dump(doc, fh, indent=1)
        fh.write("\n")
    up = sum(1 for t in trees if t["assetId"])
    print(f"wrote {os.path.relpath(OUT, ROOT)}: {len(trees)} trees, {up} with an id; {totals['total']:,} triangles, "
          f"{totals['fbxBytes'] / 1e6:.1f} MB of FBX")


if __name__ == "__main__":
    main()
