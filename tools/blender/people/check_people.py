"""Check a people build: re-import every FBX and compare it with the manifest and the brief's limits.

  nice -n 10 taskset -c 2,3 /root/.cache/spicy-rodents/venv/bin/python -I tools/blender/people/check_people.py --out build/people

Per FBX: the object names (the fifteen R15 names across body + heads), each mesh's triangle count,
bounding-box centre and size against the manifest (so the rest pose and the stud scale survive the
export), one material with colour, normal and roughness images per mesh, textures at most 1024 px.
Per build: the joints sit on spec.py's skeleton, both sides of every joint enclose the pivot (a ball
about the joint, so it cannot open), and the worst-case person stays under 6,000 triangles.
Exits non-zero on any failure; writes <out>/check.json.
"""
import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "heroes"))

import bpy  # noqa: E402
import numpy as np  # noqa: E402

import bl  # noqa: E402

import spec  # noqa: E402

TRI_LIMIT = 6000
PART_LIMIT = 20000


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
        out[o.name] = {
            "tris": int(sum(len(p.vertices) - 2 for p in me.polygons)),
            "center": spec.to_roblox(((lo + hi) / 2).tolist()),
            "size": [float(hi[0] - lo[0]), float(hi[2] - lo[2]), float(hi[1] - lo[1])],
            "materials": len(o.material_slots),
            "images": sorted({(i.size[0], i.size[1]) for i in images}),
            "image_count": len({os.path.basename(i.filepath) for i in images}),  # (the importer loads the colour map twice)
            "uv": len(me.uv_layers),
        }
    return out


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
    for key, f in man["files"].items():
        got = import_fbx(os.path.join(out, f["path"]))
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
        expect(5.35 <= top <= 5.6, f"{build}: the scalp is {top} studs up")
    report["ok"] = not fails
    report["failures"] = fails
    with open(os.path.join(out, "check.json"), "w") as fh:
        json.dump(report, fh, indent=1)
    print(json.dumps({k: v for k, v in report.items() if k != "files"}, indent=1))
    print(f"{len(report['files'])} FBX files, {sum(f['bytes'] for f in report['files'].values()) / 1e6:.1f} MB")
    for f in fails:
        print("FAIL", f)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]))
