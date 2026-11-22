"""The D32 tree shapes for the Blender trees (stdlib only; numpy only when given treegen's data).

dump_shapes.luau writes build/tree_shapes/shapes.json from generated/TreeShapes.luau (Shared/World/TreeShapes): the
grown boughs of the reshaped trees in the harvest's own JSON shapes (HTML units), and per reshaped trunk the boughs it
gains. build_trees.py --shapes and check_promises.py --shapes merge them in, so a reshaped tree is built (and checked)
round its harvested routes and its grown boughs alike; every other tree is built exactly as before.
"""
import json


def load(path):
    with open(path) as fh:
        return json.load(fh)


def merge_routes(routes, shapes):
    """routes: {id: harvest route record}; adds the grown boughs (in place) and returns it."""
    for r in shapes["routes"]:
        routes[r["id"]] = r
    return routes


def merge_data(data, shapes):
    """treegen.load_data()'s dict: routes, their samples and the reshaped trunks' forks gain the grown boughs."""
    import numpy as np

    merge_routes(data["routes"], shapes)
    data["grown"] = {r["id"] for r in shapes["routes"]}
    for rid, pts in shapes["samples"]:
        data["samples"][rid] = np.array(pts, dtype=float)
    for f in shapes["forks"]:
        fk = data["forks"][f["trunk"]]
        have = {x["branch"] for x in fk["forks"]}
        for b in f["branches"]:
            if b not in have:
                fk["forks"].append({"branch": b})
    return data


def trunks(shapes):
    """The reshaped trunks' route ids."""
    return [f["trunk"] for f in shapes["forks"]]
