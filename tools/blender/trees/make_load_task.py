"""Fill tools/cloud/tasks/tree_load.luau's TREES table from data/art/trees.json; prints the task.

  python3 -I tools/blender/trees/make_load_task.py --ids 0,40,85 > build/art/trees/tree_load_task.luau
"""
import argparse
import json
import os

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))


def lua(v):
    if isinstance(v, dict):
        return "{ " + ", ".join(f'["{k}"] = {lua(x)}' for k, x in v.items()) + " }"
    if isinstance(v, (list, tuple)):
        return "{ " + ", ".join(lua(x) for x in v) + " }"
    if isinstance(v, str):
        return json.dumps(v)
    if isinstance(v, bool):
        return "true" if v else "false"
    return repr(v)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ids", default="0,40,85")
    a = ap.parse_args()
    with open(os.path.join(REPO, "data", "art", "trees.json")) as fh:
        d = json.load(fh)
    by = {t["index"]: t for t in d["trees"]}
    rows = []
    for i in [int(x) for x in a.ids.split(",")]:
        t = by[i]
        parts = {k: {"center": v["center"], "size": v["size"]} for k, v in t["parts"].items()}
        rows.append({"index": i, "label": t["label"], "assetId": int(t["assetId"]), "pivot": t["pivot"], "parts": parts})
    with open(os.path.join(REPO, "tools", "cloud", "tasks", "tree_load.luau")) as fh:
        src = fh.read()
    src = src.replace("local TREES: { TreeSpec } = {} -- @@TREES@@", "local TREES: { TreeSpec } = " + lua(rows))
    print(src)


if __name__ == "__main__":
    main()
