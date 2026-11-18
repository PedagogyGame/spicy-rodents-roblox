#!/usr/bin/env python3
"""check_glb.py: checks finished pinball GLB files against the reference blockouts and pinball_data.json in this pack.

Usage:   python3 check_glb.py <folder with your finished .glb/.png files>
Needs:   pip install trimesh scipy networkx pillow   (if missing)
It prints PASS or FAIL for each file, with every problem found. Fix every FAIL before handing the files over.

What it holds each file to:
  * every object (node) the reference has, by exactly the same name (extra decorative objects are allowed when
    their names start with Deco_);
  * each object's origin (its node position) where the reference has it, within 1 mm: the game moves and lights
    parts by their origins;
  * the outline seen from above of every part the ball touches (guides, posts, slingshots, targets, flippers,
    ramps, the board): it must cover the reference's outline and not spill more than 3 mm outside it (8 mm for
    ramps, which may carry side walls), and be no lower than the reference minus 2 mm (taller is fine, up to the glass);
  * free-design parts (cabinet, bumpers, plunger, gate, apron) within looser bounds;
  * metres (a file 100 times too big or too small fails), Y up;
  * triangle budgets, so the alley stays smooth on phones; textures at most 1024 x 1024.
"""
import json, os, sys

import numpy as np
import trimesh

HERE = os.path.dirname(os.path.abspath(__file__))
REF = os.path.join(HERE, "reference")
DATA = json.load(open(os.path.join(HERE, "pinball_data.json")))
GLASS_Y = 0.14  # the glass above the playfield, metres: nothing on a playfield may reach it

# file -> (tolerance class, triangle budget for the whole file)
FILES = {
    "Pinball_Flipper.glb": ("exact", 600),
    "Pinball_PopBumper.glb": ("bumper", 1500),
    "Pinball_Plunger.glb": ("loose", 400),
    "Pinball_Gate.glb": ("loose", 200),
    "Pinball_Cabinet.glb": ("cabinet", 5000),
}
for pre in ("Acorn", "Rodent", "Space"):
    FILES.update({f"{pre}_Playfield.glb": ("board", 300), f"{pre}_Guides.glb": ("exact", 6000),
                  f"{pre}_Slingshots.glb": ("exact", 800), f"{pre}_Targets.glb": ("exact", 1200)})
FILES.update({"Acorn_Spinner.glb": ("exact", 300), "Rodent_Wire.glb": ("ramp", 3000), "Space_Ramps.glb": ("ramp", 5000),
              "Space_PodHoods.glb": ("hoods", 600)})
PNGS = ("Acorn_Backglass.png", "Rodent_Backglass.png", "Space_Backglass.png")


CELL = 0.001  # the footprint grid: 1 mm


def raster(tris_xz, lo, shape):
    """top-down occupancy of triangles (n x 3 x 2, metres) on a grid of CELL from lo"""
    g = np.zeros(shape, dtype=bool)
    ys, xs = np.mgrid[0:shape[0], 0:shape[1]]
    for t in tris_xz:
        a, b, c = t
        d = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(d) < 1e-14:
            continue
        i0, i1 = max(int((t[:, 0].min() - lo[0]) / CELL), 0), min(int((t[:, 0].max() - lo[0]) / CELL) + 2, shape[1])
        j0, j1 = max(int((t[:, 1].min() - lo[1]) / CELL), 0), min(int((t[:, 1].max() - lo[1]) / CELL) + 2, shape[0])
        if i0 >= i1 or j0 >= j1:
            continue
        px = lo[0] + (xs[j0:j1, i0:i1] + 0.5) * CELL
        pz = lo[1] + (ys[j0:j1, i0:i1] + 0.5) * CELL
        l1 = ((b[1] - c[1]) * (px - c[0]) + (c[0] - b[0]) * (pz - c[1])) / d
        l2 = ((c[1] - a[1]) * (px - c[0]) + (a[0] - c[0]) * (pz - c[1])) / d
        g[j0:j1, i0:i1] |= (l1 >= -1e-9) & (l2 >= -1e-9) & (l1 + l2 <= 1 + 1e-9)
    return g


def grow(g, n):
    out = g.copy()
    for _ in range(n):
        o = out.copy()
        o[1:, :] |= out[:-1, :]
        o[:-1, :] |= out[1:, :]
        o[:, 1:] |= out[:, :-1]
        o[:, :-1] |= out[:, 1:]
        out = o
    return out


def footprint(ref_tris, got_tris, slack_mm):
    """(share of the reference's outline the file covers, share of the file's outline outside the reference + slack)"""
    allp = np.concatenate([ref_tris.reshape(-1, 2), got_tris.reshape(-1, 2)])
    lo = allp.min(0) - 0.01
    shape = (int((allp[:, 1].max() - lo[1]) / CELL) + 12, int((allp[:, 0].max() - lo[0]) / CELL) + 12)
    if shape[0] * shape[1] > 6_000_000:
        return None, None
    r, g = raster(ref_tris, lo, shape), raster(got_tris, lo, shape)
    covered = (r & grow(g, 2)).sum() / max(r.sum(), 1)
    stray = (g & ~grow(r, slack_mm)).sum() / max(g.sum(), 1)
    return covered, stray


FACES = {}


def nodes(path):
    """name -> (origin xyz, world-space bounds 2x3, triangles, textures) for every node that carries a mesh"""
    sc = trimesh.load(path, force="scene")
    out = {}
    for name in sc.graph.nodes_geometry:
        T, gname = sc.graph[name]
        g = sc.geometry[gname]
        v = trimesh.transform_points(g.vertices, T)
        tex = []
        mat = getattr(g.visual, "material", None)
        for attr in ("baseColorTexture", "image"):
            im = getattr(mat, attr, None) if mat is not None else None
            if im is not None and hasattr(im, "size"):
                tex.append(im.size)
        out[name] = (T[:3, 3].copy(), np.array([v.min(0), v.max(0)]), len(g.faces), tex)
        FACES[(path, name)] = v[g.faces][:, :, [0, 2]]
    return out


def check(name, path):
    errs = []
    cls, budget = FILES[name]
    got = nodes(path)
    if not got:
        return ["no mesh objects in the file"]
    allb = np.array([[min(b[0][i] for _, b, _, _ in got.values()) for i in range(3)], [max(b[1][i] for _, b, _, _ in got.values()) for i in range(3)]])
    size = (allb[1] - allb[0]).max()
    if size > 5 or size < 0.005:
        errs.append(f"the file is {size:.3f} across at its widest: it must be in metres (1 stud = 0.28 m)")
    tris = sum(t for _, _, t, _ in got.values())
    if tris > budget:
        errs.append(f"{tris} triangles; the budget for this file is {budget}")
    for n, (_, _, _, tex) in got.items():
        for s in tex:
            if max(s) > 1024:
                errs.append(f"{n}: texture {s[0]} x {s[1]} is larger than 1024")
    if cls == "hoods":
        holes = {h["id"]: h for h in DATA["machines"]["space"]["holes"]}
        for i, hid in ((1, "pod_1"), (2, "pod_2")):
            n = f"PodHood{i}"
            if n not in got:
                errs.append(f"missing object {n}")
                continue
            h = holes[hid]
            _, b, _, _ = got[n]
            cx, cz, r = h["centre"][0], h["centre"][1], h["radius"]
            if b[0][0] < cx - r - 0.006 or b[1][0] > cx + r + 0.006 or b[0][2] < cz - r - 0.006 or b[1][2] > cz + 0.006:
                errs.append(f"{n}: must sit on the upper half of the hole's rim (centre {cx}, {cz}, radius {r}), within 6 mm")
            if b[1][1] > 0.006 or b[0][1] < -0.001:
                errs.append(f"{n}: must stand between 0 and 6 mm above the board, so a ball coming down rolls over it")
        return errs
    ref = nodes(os.path.join(REF, name))
    for n, (o, b, _, _) in ref.items():
        if n not in got:
            errs.append(f"missing object {n}")
            continue
        go, gb, _, _ = got[n]
        if np.abs(go - o).max() > 0.001:
            errs.append(f"{n}: origin at {np.round(go, 4).tolist()}, must be at {np.round(o, 4).tolist()}")
        if cls in ("exact", "ramp", "board") and not (cls == "board" and n == "Apron"):
            slack = 8 if cls == "ramp" else 3  # a ramp may carry side walls of its own
            cov, stray = footprint(FACES[(os.path.join(REF, name), n)], FACES[(path, n)], slack)
            if cov is None:
                errs.append(f"{n}: spread far too wide to measure: bounds {np.round(gb, 3).tolist()}")
            elif cov < 0.97 or stray > 0.01:
                errs.append(f"{n}: outline seen from above does not match: it covers {cov * 100:.0f}% of the required outline "
                            f"(needs 97%) and {stray * 100:.1f}% of it lies more than {slack} mm outside it (allowed 1%). "
                            f"Required bounds x {np.round(b[:, 0], 4).tolist()} z {np.round(b[:, 2], 4).tolist()}")
            if gb[1][1] < b[1][1] - 0.002:
                errs.append(f"{n}: top at {gb[1][1]:.4f}, must be at least {b[1][1] - 0.002:.4f} high")
            if cls != "board" and gb[1][1] > GLASS_Y - 0.004 and not n.startswith("Ramp"):
                errs.append(f"{n}: top at {gb[1][1]:.4f} reaches the glass ({GLASS_Y})")
        else:
            grow = {"bumper": 0.03, "loose": 0.02, "cabinet": 0.03, "board": 0.01}[cls]
            if (gb[0] < b[0] - grow).any() or (gb[1] > b[1] + grow).any():
                errs.append(f"{n}: bounds {np.round(gb, 3).tolist()} stray more than {grow * 1000:.0f} mm outside {np.round(b, 3).tolist()}")
            if (gb[1] - gb[0] < (b[1] - b[0]) * 0.5).any():
                errs.append(f"{n}: much smaller than the reference {np.round(b[1] - b[0], 3).tolist()}")
    for n in got:
        if n not in ref and not n.startswith("Deco_"):
            errs.append(f"unexpected object {n} (name extra decorative objects Deco_<something>)")
    return errs


def check_png(path):
    from PIL import Image
    im = Image.open(path)
    w, h = im.size
    want = DATA["cabinet"]["backglass_face_size"]
    errs = []
    if max(w, h) > 1024:
        errs.append(f"{w} x {h} is larger than 1024")
    if abs(w / h - want[0] / want[1]) > 0.02:
        errs.append(f"{w} x {h} is the wrong shape: it must be {want[0]} wide by {want[1]} tall (for example 854 x 1024)")
    return errs


def main(folder):
    bad = 0
    for name in list(FILES) + list(PNGS):
        path = os.path.join(folder, name)
        if not os.path.exists(path):
            print(f"MISSING {name}")
            bad += 1
            continue
        errs = check_png(path) if name.endswith(".png") else check(name, path)
        print(("PASS " if not errs else "FAIL ") + name)
        for e in errs:
            print("   - " + e)
        bad += bool(errs)
    print(f"\n{len(FILES) + len(PNGS) - bad} of {len(FILES) + len(PNGS)} files pass")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "."))
