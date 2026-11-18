"""Harvest the uploaded tree Models' MeshPart properties into data/art/tree_meshes.json.

Runs tools/cloud/tasks/tree_harvest.luau on the CI place in batches (Luau Execution, InsertService:LoadAsset)
and merges the results. The bake (src/worldgen/Builders/Trees) writes the same MeshParts into Town.rbxm.

  python3 -I tools/blender/trees/harvest_meshes.py --version <ciPlaceVersion> [--batch 24] [--art data/art/trees_v2.json]

--art names the uploaded set (default the live trees, data/art/trees.json; data/art/trees_v2.json is the new
generator's, tools/blender/trees/publish.py). Only its trees with an asset id are harvested; every other tree keeps
its record in tree_meshes.json, so the next bake draws each tree from the newest Model it has.
"""
import argparse
import json
import os
import subprocess
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--version", required=True)
    ap.add_argument("--batch", type=int, default=24)
    ap.add_argument("--art", default=os.path.join("data", "art", "trees.json"))
    a = ap.parse_args()
    with open(os.path.join(REPO, a.art)) as fh:
        art = json.load(fh)
    with open(os.path.join(REPO, "tools", "cloud", "tasks", "tree_harvest.luau")) as fh:
        src = fh.read()
    stem = os.path.splitext(os.path.basename(a.art))[0]
    work = os.path.join(REPO, "build", "art", "trees", "harvest" if stem == "trees" else f"harvest_{stem}")
    os.makedirs(work, exist_ok=True)
    rows = [(t["index"], int(t["assetId"])) for t in art["trees"] if t.get("assetId")]
    got = {}
    for b in range(0, len(rows), a.batch):
        chunk = rows[b : b + a.batch]
        table = "{ " + ", ".join(f"{{ index = {i}, assetId = {aid} }}" for i, aid in chunk) + " }"
        task = os.path.join(work, f"task_{b:03d}.luau")
        out = os.path.join(work, f"out_{b:03d}.json")
        with open(task, "w") as fh:
            fh.write(src.replace("= {} -- @@TREES@@", "= " + table))
        if not os.path.exists(out):
            subprocess.run(
                ["node", "tools/cloud/cloud.mjs", "run_engine_tests", task, "--version", a.version, "--place", "ci", "--timeout", "300s", "--out", out],
                cwd=REPO, check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        with open(out) as fh:
            doc = json.load(fh)
        if "result" not in doc or doc["result"] is None:
            os.remove(out)
            sys.exit(f"batch {b}: {doc.get('error')}")
        res = doc["result"]
        for t in res["trees"]:
            if "error" in t:
                print(f"tree {t['index']}: {t['error']}", file=sys.stderr)
                os.remove(out)
                sys.exit(1)
            got[t["index"]] = t
    by = {t["index"]: t for t in art["trees"]}
    trees = []
    for i in sorted(got):
        t, src_t = got[i], by[i]
        # What the importer cannot know and the build does (tree_NNN.json -> data/art/trees.json parts):
        # leaf sprays are alpha cards, drawn from both sides, cut by the colour map's alpha; their part
        # colour is a leaf green, which is what shows if the SurfaceAppearance never arrives.
        for p in t["parts"]:
            want = (src_t.get("parts") or {}).get(p["name"]) or {}
            if want.get("doubleSided") is not None:
                p["doubleSided"] = bool(want["doubleSided"])
            if want.get("alphaMode") and p.get("surface"):
                p["surface"]["alphaMode"] = want["alphaMode"]
            if want.get("color"):
                p["color"] = want["color"]
        trees.append({
            "index": i,
            "trunkRoute": src_t["trunkRoute"],
            "label": src_t["label"],
            "assetId": src_t["assetId"],
            "pivot": src_t["pivot"],
            "parts": t["parts"],
        })
    meshes = os.path.join(REPO, "data", "art", "tree_meshes.json")
    if os.path.exists(meshes):
        with open(meshes) as fh:
            kept = [t for t in json.load(fh)["trees"] if t["index"] not in got]
        trees = sorted(trees + kept, key=lambda t: t["index"])
    doc = {"schema": "art/tree_meshes v1",
           "note": "MeshPart properties read from the uploaded tree Models (tools/blender/trees/harvest_meshes.py). offset = part centre relative to the tree pivot, studs.",
           "trees": trees}
    with open(meshes, "w") as fh:
        json.dump(doc, fh, indent=1)
        fh.write("\n")
    print(f"{len(trees)} trees, {sum(len(t['parts']) for t in trees)} mesh parts -> data/art/tree_meshes.json")


if __name__ == "__main__":
    main()
