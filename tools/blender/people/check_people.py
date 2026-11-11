"""Check a people build: re-import every FBX and compare it with the manifest and the brief's limits.

  nice -n 10 taskset -c 2,3 /root/.cache/spicy-rodents/venv/bin/python -I tools/blender/people/check_people.py --out build/people

Per FBX: the object names (the fifteen R15 names across body + heads), each mesh's triangle count,
bounding-box centre and size against the manifest (so the rest pose and the stud scale survive the
export), one material with colour, normal and roughness images per mesh, textures at most 1024 px.
Per build: the joints sit on spec.py's skeleton, both sides of every joint enclose the pivot, the
worst-case person stays under 6,000 triangles, and no joint opens in a pose: the re-imported parts are
posed as Motor6D joints pose them (pose.py: both walk phases, both passing phases, the run and the sit)
and every joint is looked at from 1,500 directions. Looking at a pivot, the first thing seen must be the
outside of a part (never the inside of a mesh through an open end; pinholes under 0.02 studs are not
counted), and no deeper than the joint is in the rest pose less SEAM_TOL: a part that pulled away from its neighbour would let the eye in.
Exits non-zero on any failure; writes <out>/check.json.
"""
import argparse
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "heroes"))

import bpy  # noqa: E402
import numpy as np  # noqa: E402

import bl  # noqa: E402

import pose as posing  # noqa: E402
import spec  # noqa: E402

TRI_LIMIT = 6000
PART_LIMIT = 20000
SEAM_TOL = 0.035  # studs a joint may be deeper in a pose than at rest (one ball sits inside the other)
GAP_POSES = ["rest", "walk", "walk2", "pass", "pass2", "run", "sit"]
GAP_DIRS = 1500
FAR = 9.0  # studs from a pivot: outside the whole person
PINHOLE = 0.012  # studs: openings narrower than about twice this are not counted


def import_fbx(path):
    bl.reset_scene()
    bpy.ops.import_scene.fbx(filepath=path)
    out = {}
    for o in bpy.context.scene.objects:
        if o.type != "MESH":
            continue
        me = o.data
        v = np.array([(o.matrix_world @ x.co)[:] for x in me.vertices])
        lo, hi = v.min(axis=0), v.max(axis=0)
        images = []
        for slot in o.material_slots:
            if slot.material and slot.material.use_nodes:
                images += [n.image for n in slot.material.node_tree.nodes if n.type == "TEX_IMAGE" and n.image]
        me.calc_loop_triangles()
        out[o.name] = {
            "verts": v,
            "faces": np.array([t.vertices[:] for t in me.loop_triangles], dtype=np.int64),
            "tris": int(sum(len(p.vertices) - 2 for p in me.polygons)),
            "center": spec.to_roblox(((lo + hi) / 2).tolist()),
            "size": [float(hi[0] - lo[0]), float(hi[2] - lo[2]), float(hi[1] - lo[1])],
            "materials": len(o.material_slots),
            "images": sorted({(i.size[0], i.size[1]) for i in images}),
            "image_count": len({os.path.basename(i.filepath) for i in images}),  # (the importer loads the colour map twice)
            "uv": len(me.uv_layers),
        }
    return out


def sphere_dirs(n):
    i = np.arange(n) + 0.5
    z = 1 - 2 * i / n
    r = np.sqrt(1 - z * z)
    a = i * math.pi * (3 - math.sqrt(5))
    return np.stack([r * np.cos(a), r * np.sin(a), z], axis=1)


def joint_gaps(meshes, build):
    """meshes: {R15 part: (verts, faces)} in the rest pose (Blender frame, ground at z = 0).
    Returns ({pose: {joint: stats}}, [failures])."""
    from mathutils import Vector
    from mathutils.bvhtree import BVHTree

    dirs = sphere_dirs(GAP_DIRS)
    centre = {n: np.array(spec.to_blender(build["parts"][n]["center"])) for n in meshes}
    stats, fails, rest = {}, [], {}

    def tree_of(posed, names):
        V, F, off = [], [], 0
        for n in names:
            V.append(posed[n])
            F.append(meshes[n][1] + off)
            off += len(posed[n])
        V, F = np.concatenate(V), np.concatenate(F)
        fn = np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]])
        return BVHTree.FromPolygons([Vector(x) for x in V.tolist()], F.tolist()), fn

    for pname in GAP_POSES:
        world = posing.fk(build["joints"], posing.POSES[pname])
        posed = {}
        for n, (v, _f) in meshes.items():
            m = posing.to_blender(world[n])
            posed[n] = (v - centre[n]) @ m[:3, :3].T + m[:3, 3]
        whole, whole_fn = tree_of(posed, list(meshes))
        stats[pname] = {}
        for jname, p0, p1, pos in spec.JOINTS:
            if p0 == "HumanoidRootPart":
                continue
            c1 = np.array(build["joints"][jname]["c1"])
            piv = posing.to_blender(world[p1] @ posing.translation(c1))[:3, 3]
            pair, pair_fn = tree_of(posed, [p0, p1])
            depth, inside = [], 0
            for d in dirs:
                # the whole person, seen from outside it: the first surface must face the eye
                loc, _nrm, idx, _dist = whole.ray_cast(Vector(piv + d * FAR), Vector(-d), FAR)
                if loc is not None and float(whole_fn[idx] @ d) < 0:
                    # a ray can slip between two triangles' shared edge, or past a rim that pokes a
                    # hair through the ball round it: an opening counts when it is PINHOLE wide
                    u = np.cross(d, [0.0, 0.0, 1.0] if abs(d[2]) < 0.9 else [1.0, 0.0, 0.0])
                    u /= np.linalg.norm(u)
                    w = np.cross(d, u)
                    back = 0
                    for a in np.arange(6) * (math.pi / 3):
                        o = piv + d * FAR + (u * math.cos(a) + w * math.sin(a)) * PINHOLE
                        loc2, _n2, idx2, _d2 = whole.ray_cast(Vector(o), Vector(-d), FAR)
                        back += loc2 is not None and float(whole_fn[idx2] @ d) < 0
                    inside += back >= 3
                # the joint's two parts alone: how deep the eye gets
                loc, _nrm, idx, dist = pair.ray_cast(Vector(piv + d * FAR), Vector(-d), FAR)
                if loc is None:
                    depth.append(0.0)
                elif float(pair_fn[idx] @ d) > 0:
                    depth.append(FAR - dist)
            low = float(min(depth))
            st = {"min": round(low, 4), "inside": inside}
            if pname == "rest":
                rest[jname] = low
            else:
                st["rest"] = round(rest[jname], 4)
                if low < rest[jname] - SEAM_TOL:
                    fails.append(f"{pname}/{jname}: opens {rest[jname] - low:.3f} studs deeper than at rest")
            if inside:
                fails.append(f"{pname}/{jname}: the inside of a mesh shows from {inside} of {len(dirs)} directions")
            stats[pname][jname] = st
    return stats, fails


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="build/people")
    a = ap.parse_args(argv)
    out = os.path.abspath(a.out)
    with open(os.path.join(out, "manifest.json")) as fh:
        man = json.load(fh)
    fails, report = [], {"files": {}}

    def expect(cond, msg):
        if not cond:
            fails.append(msg)

    body_names = [n for n in spec.PARTS if n != "Head"]
    rest_meshes = {b: {} for b in man["builds"]}
    for key, f in man["files"].items():
        got = import_fbx(os.path.join(out, f["path"]))
        if key.startswith("body_"):
            for n in body_names:
                if n in got:
                    rest_meshes[key.split("_", 2)[1]].setdefault(n, (got[n]["verts"], got[n]["faces"]))
        elif key == "heads":
            for b in rest_meshes:
                rest_meshes[b]["Head"] = next((g["verts"], g["faces"]) for g in got.values())
        report["files"][key] = {"objects": len(got), "tris": sum(g["tris"] for g in got.values()), "bytes": f["bytes"]}
        expect(sorted(got) == sorted(f["objects"]), f"{key}: objects {sorted(got)} != {sorted(f['objects'])}")
        if key.startswith("body_"):
            _b, build, outfit = key.split("_", 2)
            expect(all(n in got for n in body_names), f"{key}: missing R15 parts")
            ref = dict(man["builds"][build]["parts"])
            ref.update(man["builds"][build]["extras"])
        elif key == "heads":
            ref = {n: man["builds"]["slim"]["parts"]["Head"] for n in got}
        else:
            ref = man["headwear"]["items"]
        for name, g in got.items():
            r = ref.get(name)
            if r is None:
                fails.append(f"{key}: {name} is not in the manifest")
                continue
            expect(g["tris"] == r["tris"], f"{key}/{name}: {g['tris']} tris, manifest {r['tris']}")
            expect(g["tris"] <= PART_LIMIT, f"{key}/{name}: over the MeshPart limit")
            expect(np.allclose(g["center"], r["center"], atol=2e-3), f"{key}/{name}: centre {np.round(g['center'], 3)} != {r['center']}")
            expect(np.allclose(g["size"], r["size"], atol=2e-3), f"{key}/{name}: size {np.round(g['size'], 3)} != {r['size']}")
            expect(g["materials"] == 1 and g["image_count"] == 3, f"{key}/{name}: {g['materials']} materials, {g['image_count']} images")
            expect(all(max(s) <= 1024 for s in g["images"]), f"{key}/{name}: texture over 1024 px {g['images']}")
            expect(g["uv"] == 1, f"{key}/{name}: {g['uv']} UV layers")
    # the skeleton and the joints
    for build, b in man["builds"].items():
        for jname, p0, p1, pos in spec.JOINTS:
            j = b["joints"][jname]
            c0 = np.zeros(3) if p0 == "HumanoidRootPart" else np.array(b["parts"][p0]["center"])
            c1 = np.array(b["parts"][p1]["center"])
            expect(np.allclose(c0 + j["c0"], pos, atol=1e-3) and np.allclose(c1 + j["c1"], pos, atol=1e-3), f"{build}/{jname}: C0/C1 off the pivot")
            for part, c in ((p0, c0), (p1, c1)):
                if part == "HumanoidRootPart":
                    continue
                half = np.array(b["parts"][part]["size"]) / 2
                expect(bool((np.abs(np.array(pos) - c) <= half + 1e-3).all()), f"{build}/{jname}: the pivot is outside {part}'s bounds")
        t = b["triangles"]
        expect(t["worstCase"] <= TRI_LIMIT, f"{build}: worst case {t['worstCase']} triangles")
        feet = min(b["parts"][f]["center"][1] - b["parts"][f]["size"][1] / 2 for f in ("LeftFoot", "RightFoot"))
        expect(abs(feet + spec.ROOT_HEIGHT) < 0.02, f"{build}: soles at {feet}")
        top = b["parts"]["Head"]["center"][1] + b["parts"]["Head"]["size"][1] / 2 + spec.ROOT_HEIGHT
        hair_top = max(i["center"][1] + i["size"][1] / 2 for i in man["headwear"]["items"].values() if i["kind"] == "hair") + spec.ROOT_HEIGHT
        report[build] = {"triangles": t, "scalp": round(top, 3), "tallest_hair": round(hair_top, 3)}
        if len(rest_meshes[build]) == len(spec.PARTS):
            gaps, gap_fails = joint_gaps(rest_meshes[build], b)
            report[build]["joints"] = gaps
            worst = max(((s["rest"] - s["min"], f"{p}/{j}") for p, js in gaps.items() if p != "rest" for j, s in js.items()))
            report[build]["deepest_seam"] = {"where": worst[1], "studs": round(worst[0], 4)}
            fails += [f"{build}: {x}" for x in gap_fails]
        else:
            fails.append(f"{build}: only {len(rest_meshes[build])} of {len(spec.PARTS)} parts re-imported, the joints were not posed")
        expect(5.35 <= top <= 5.6, f"{build}: the scalp is {top} studs up")
    report["ok"] = not fails
    report["failures"] = fails
    with open(os.path.join(out, "check.json"), "w") as fh:
        json.dump(report, fh, indent=1)
    brief = {k: ({a: b for a, b in v.items() if a != "joints"} if isinstance(v, dict) else v) for k, v in report.items() if k != "files"}
    print(json.dumps(brief, indent=1))
    print(f"{len(report['files'])} FBX files, {sum(f['bytes'] for f in report['files'].values()) / 1e6:.1f} MB")
    for f in fails:
        print("FAIL", f)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]))
