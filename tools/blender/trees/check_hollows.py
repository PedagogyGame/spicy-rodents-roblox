"""Do the hollow trees' insides still fit inside the new bark? (headless bpy; reads what build_trees.py --fbx wrote)

  PY=/root/.cache/spicy-rodents/venv/bin/python
  lune run tools/blender/trees/dump_hollows.luau generated/HollowTrees.luau build/hollows/hollows.json
  nice -n 10 $PY -I tools/blender/trees/check_hollows.py --dir build/art/trees --hollows build/hollows/hollows.json

The hollows (src/shared/World/HollowLayout.luau, on the hollow trees' branch) line each cavity with boards sized to
the trunk's bark radius, the squirrel's tapered radius r(1 - 0.48 t) (giants r/0.95 - 1.05 u t), less the depth of
the old bark's 14 flats, about the trunk route's own centre line (its lean). Here every corner of every piece is
measured against the new Bark mesh instead: a level ray from the trunk route's axis at the corner's height, out
through the corner, to the first bark it meets.
  inside pieces (liner, floor, roof, tread, post, shelf): margin = bark distance - corner distance; < 0 pokes through.
  knotholes (the dark oval on the bark, seen from outside): its centre's distance - the bark's under it; < -0.06
    (half the disc's 0.12 thickness) buries it in the bark.
Exit status 1 when a board pokes through or a knothole is buried. --json PATH writes the numbers.
"""
import argparse
import json
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import check_promises as cp  # noqa: E402

INSIDE = ("liner", "floor", "roof", "tread", "post", "shelf")
KNOT_BURY = -0.06


def corners(pc):
    """HollowLayout.corners: a block's 8 corners; a cylinder's two end rings (24 points each, axis along xv)."""
    p, xv, yv = (np.asarray(pc[k], float) for k in ("p", "xv", "yv"))
    zv = np.cross(xv, yv)
    hx, hy, hz = (s / 2 for s in pc["size"])
    out = []
    for sx in (-1, 1):
        if pc["shape"] == "Cylinder":
            for k in range(24):
                a = k * math.pi / 12
                out.append(p + xv * hx * sx + yv * math.cos(a) * hy + zv * math.sin(a) * hy)
        else:
            for sy in (-1, 1):
                for sz in (-1, 1):
                    out.append(p + xv * hx * sx + yv * hy * sy + zv * hz * sz)
    return out


class Axis:
    """The trunk route's centre line by height (HollowLayout.trunk axisAt: the arc-length t whose point has y)."""

    def __init__(self, route):
        c = cp.Curve(np.asarray(route["points"], float) * cp.SPU)
        u = np.linspace(0, 1, 801)
        self.P = np.array([c.at(x) for x in u])
        self.foot = self.P[0]

    def at(self, y):
        P = self.P
        if y <= P[0, 1]:
            return P[0]
        if y >= P[-1, 1]:
            return P[-1]
        i = int(np.searchsorted(P[:, 1], y))
        a, b = P[i - 1], P[i]
        f = (y - a[1]) / max(b[1] - a[1], 1e-9)
        return a + (b - a) * f


def bark_distance(tree, axis_pt, q):
    """Level distance from the axis to the first bark along the bearing of q (None: no bark that way)."""
    d = np.array([q[0] - axis_pt[0], 0.0, q[2] - axis_pt[2]])
    n = float(np.linalg.norm(d))
    if n < 1e-6:
        return None, n
    d /= n
    o = np.array([axis_pt[0], q[1], axis_pt[2]])
    hit = tree.ray_cast(tuple(o), tuple(d), 40.0)
    return (None if hit[0] is None else float(hit[3])), n


def check(info, parts, routes, hollow):
    V, F = parts["Bark"]
    tree = cp.bvh(V, F)
    axis = Axis(routes[hollow["trunk"]])
    rep = {"hollow": hollow["id"], "tree": info["index"], "label": info["label"], "fail": [], "pieces": 0}
    inside, knots = [], []
    for pc in hollow["parts"]:
        role = pc["role"]
        if role == "knothole":
            q = np.asarray(pc["p"], float)
            b, n = bark_distance(tree, axis.at(q[1]), q)
            knots.append(n - b if b is not None else 9.0)
            continue
        if role not in INSIDE:
            continue
        rep["pieces"] += 1
        worst = None
        for q in corners(pc):
            if q[1] < axis.foot[1]:
                continue  # (under the trunk's foot: the floor's underside, in the ground)
            b, n = bark_distance(tree, axis.at(q[1]), q)
            m = (b - n) if b is not None else -9.0
            if worst is None or m < worst[0]:
                worst = (m, role, [round(float(x), 2) for x in q])
        if worst:
            inside.append(worst)
    inside.sort(key=lambda w: w[0])
    rep["min_margin"] = round(inside[0][0], 3) if inside else None
    rep["worst"] = [{"margin": round(w[0], 3), "role": w[1], "at": w[2]} for w in inside[:3]]
    rep["knot_offsets"] = [round(k, 3) for k in knots]
    poke = [w for w in inside if w[0] < 0]
    if poke:
        rep["fail"].append(f"{len(poke)} pieces poke through the bark (worst {poke[0][0]:.3f} st, {poke[0][1]})")
    buried = [k for k in knots if k < KNOT_BURY]
    if buried:
        rep["fail"].append(f"{len(buried)} knotholes buried in the bark (worst {min(buried):.3f} st)")
    return rep


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=os.path.join(cp.REPO, "build", "art", "trees"))
    ap.add_argument("--hollows", default=os.path.join(cp.REPO, "build", "hollows", "hollows.json"))
    ap.add_argument("--json", default="")
    a = ap.parse_args(argv)
    routes = cp.load_routes()
    with open(a.hollows) as fh:
        hollows = json.load(fh)["hollows"]
    by_trunk = {}
    for f in sorted(os.listdir(a.dir)):
        if f.startswith("tree_") and f.endswith(".json") and f[5:8].isdigit():
            with open(os.path.join(a.dir, f)) as fh:
                info = json.load(fh)
            by_trunk[info["trunkRoute"]] = info
    reps, bad = [], 0
    for h in hollows:
        info = by_trunk.get(h["trunk"])
        if info is None:
            print(f"{h['id']}: no tree built round trunk {h['trunk']}")
            bad += 1
            continue
        fbx = os.path.join(a.dir, f"tree_{info['index']:03d}.fbx")
        rep = check(info, cp.load_fbx(fbx, info["pivot"]), routes, h)
        reps.append(rep)
        bad += 1 if rep["fail"] else 0
        print(f"{h['id']:>4} tree {info['index']:03d} {info['label']:<22} {rep['pieces']:>3} pieces  min margin "
              f"{rep['min_margin']} st  knotholes {rep['knot_offsets']}  {'; '.join(rep['fail']) or 'ok'}", flush=True)
    print(f"\n{len(reps)} hollows checked, {bad} broken")
    if a.json:
        with open(a.json, "w") as fh:
            json.dump(reps, fh, indent=1)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:] if "--" not in sys.argv else sys.argv[sys.argv.index("--") + 1:]))
