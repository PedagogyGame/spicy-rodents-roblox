"""Hero art -> Roblox: KeyframeSequences (Lune), Open Cloud uploads, data/art/heroes.json.

  python3 -I tools/blender/heroes/publish.py [--skip-upload] [--only squirrel,fox,...]

For every built variant (build/heroes/<variant>/report.json from build_hero.py):
  1. each clip JSON -> `lune run tools/anim/build_clip.luau` -> build/heroes/anim/<rig>_<Clip>.rbxm
  2. `node tools/cloud/cloud.mjs upload_asset <fbx> --type Model` (one model per variant) and
     `--type Animation` for each clip (clips are per rig: the rodent shares the squirrel's, the buck the
     doe's), each result kept in build/heroes/uploads/<name>.json (re-runs reuse an upload whose source
     file hash is unchanged)
  3. data/art/heroes.json: asset ids, moderation states, tints (SurfaceAppearance.Color, TintMask),
     regions and their tris, socket offsets (Attachments to parent under the Bones), clip timing.
Display names stay under the Assets API's 50 characters.
"""
import argparse
import hashlib
import importlib
import json
import os
import subprocess
import sys
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

VARIANTS = {
    "squirrel": {"species": "squirrel", "module": "species_squirrel", "rig": "squirrel", "clips_from": "squirrel"},
    "rodent": {"species": "rodent", "module": "species_squirrel", "rig": "squirrel", "clips_from": "squirrel"},
    "fox": {"species": "fox", "module": "species_fox", "rig": "fox", "clips_from": "fox"},
    "doe": {"species": "deer", "module": "species_deer", "rig": "deer", "clips_from": "doe"},
    "buck": {"species": "deer", "module": "species_deer", "rig": "deer", "clips_from": "doe"},
}
REGION_MODE = {"Body": "TintMask", "Pattern": "TintMask", "FurCards": "Transparency", "Blood": "Transparency", "Eyes": "Overlay", "Antlers": "Overlay"}
M = ((-1, 0, 0), (0, 0, 1), (0, 1, 0))


def to_roblox(v):
    return [round(sum(M[i][j] * v[j] for j in range(3)), 4) + 0.0 for i in range(3)]


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        h.update(fh.read())
    return h.hexdigest()[:16]


def run(cmd, **kw):
    r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, **kw)
    if r.returncode != 0:
        raise SystemExit(f"failed: {' '.join(cmd)}\n{r.stdout[-2000:]}\n{r.stderr[-2000:]}")
    return r


def upload(path, kind, name, desc, tag, skip):
    os.makedirs(os.path.join(ROOT, "build/heroes/uploads"), exist_ok=True)
    rec = os.path.join(ROOT, "build/heroes/uploads", f"{tag}.json")
    digest = sha(path)
    if os.path.exists(rec):
        with open(rec) as fh:
            old = json.load(fh)
        if old.get("sourceSha") == digest and old.get("assetId"):
            return old
    if skip:
        return {"assetId": None, "moderationState": "not uploaded", "sourceSha": digest}
    assert len(name) <= 50, name
    t0 = time.time()
    run(["node", "tools/cloud/cloud.mjs", "upload_asset", path, "--type", kind, "--name", name, "--description", desc, "--out", rec])
    with open(rec) as fh:
        res = json.load(fh)
    res["sourceSha"] = digest
    res["uploadSeconds"] = round(time.time() - t0, 1)
    with open(rec, "w") as fh:
        json.dump(res, fh, indent=2)
    print(f"  uploaded {kind} {name}: {res.get('assetId')} ({res.get('moderationState')})", flush=True)
    return res


def rigspec_bones(rig):
    """The bone lists exactly as src/shared/Actors/RigSpec.luau builds them."""
    legs = [f"{l}_{s}" for l in ("FrontL", "FrontR", "BackL", "BackR") for s in ("Upper", "Lower", "Foot", "Toe")]
    base = ["Root", "Hips", "Spine1", "Spine2", "Spine3", "Chest", "Neck", "Head", "Jaw", "EarL", "EarR"]
    if rig == "squirrel":
        return base + [f"Tail{i}" for i in range(1, 9)] + legs
    if rig == "fox":
        return base + [f"Tail{i}" for i in range(1, 7)] + legs
    return ["Root", "Hips", "Spine1", "Spine2", "Spine3", "Chest", "Neck1", "Neck2", "Neck3", "Head", "Jaw", "EarL", "EarR",
            "Tail1", "Tail2"] + legs


def sockets(mod):
    skel = {b[0]: b for b in mod.skeleton()}
    out = {}
    for name, (bone, point) in mod.SOCKETS.items():
        head = skel[bone][1]
        out[name] = {"bone": bone, "offset": to_roblox([point[i] - head[i] for i in range(3)])}
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--skip-upload", action="store_true")
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    only = [v for v in a.only.split(",") if v]
    anim_dir = os.path.join(ROOT, "build/heroes/anim")
    os.makedirs(anim_dir, exist_ok=True)
    out_path = os.path.join(ROOT, "data/art/heroes.json")
    doc = {"format": "spicy-heroes/1", "species": {}}
    if os.path.exists(out_path):
        with open(out_path) as fh:
            doc = json.load(fh)
    doc["generated"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    doc["notes"] = [
        "Models: Open Cloud Model uploads of the FBX (tools/blender/heroes). InsertService:LoadAsset gives a Model with a Part named RootPart (transparent, at the origin = the ground under the body centre) carrying the Bone tree (Root > Hips > ...), one skinned MeshPart per region joined to RootPart by a Motor6D, and an AnimationController.",
        "Every Bone arrives with an identity rest rotation, so the clips (spicy-clip/1: Pose.CFrame = local delta in an axis-aligned joint frame) play unchanged on these rigs and on the part-built puppets.",
        "Regions: set SurfaceAppearance.AlphaMode per region (alphaMode below) and SurfaceAppearance.Color to the tint at load; Body and Pattern colour maps are greyscale where the avatar tint applies (alpha = the tint mask); the 30 % avatar blend is Color = lerp(tint, avatarColour, 0.3).",
        "Sockets are not in the FBX: create an Attachment per socket under the named Bone at `offset` (studs, bone frame = model axes at rest).",
        "The rodent shares the squirrel's skeleton and clips; the buck is the doe with an Antlers MeshPart (scale it 1.1 with Model:ScaleTo, RigSpec scaleVariants).",
    ]
    clip_ids = {}
    for variant, cfg in VARIANTS.items():
        if only and variant not in only:
            continue
        rep_path = os.path.join(ROOT, "build/heroes", variant, "report.json")
        if not os.path.exists(rep_path):
            print(f"skip {variant}: no build", flush=True)
            continue
        with open(rep_path) as fh:
            rep = json.load(fh)
        mod = importlib.import_module(cfg["module"])
        print(f"== {variant}", flush=True)
        names = [b[0] for b in mod.skeleton()]
        want = rigspec_bones(cfg["rig"])
        if sorted(names) != sorted(want):
            raise SystemExit(f"{variant}: bones differ from RigSpec: {set(names) ^ set(want)}")
        fbx = rep["fbx"]["path"]
        model = upload(fbx, "Model", f"Spicy Rodents hero {variant}",
                       f"Hero {variant} for Spicy Rodents: skinned rig (RigSpec {cfg['rig']} bone names), regions {', '.join(rep['regions'])}. Built by tools/blender/heroes.",
                       f"model_{variant}", a.skip_upload)
        clips = {}
        src = VARIANTS[cfg["clips_from"]]
        src_rep_path = os.path.join(ROOT, "build/heroes", cfg["clips_from"], "report.json")
        with open(src_rep_path) as fh:
            src_rep = json.load(fh)
        for clip, info in src_rep["clips"].items():
            if not isinstance(info, dict) or "path" not in info:
                continue
            key = (cfg["rig"], clip)
            if key not in clip_ids:
                rbxm = os.path.join(anim_dir, f"{cfg['rig']}_{clip}.rbxm")
                r = run(["lune", "run", "tools/anim/build_clip.luau", info["path"], rbxm])
                summary = json.loads(r.stdout.strip().splitlines()[-1])
                up = upload(rbxm, "Animation", f"Spicy Rodents {cfg['rig']} {clip}",
                            f"{cfg['rig']} clip {clip} ({info.get('brief', clip)}), spicy-clip/1, {summary['keyframes']} keyframes. tools/blender/heroes.",
                            f"anim_{cfg['rig']}_{clip}", a.skip_upload)
                clip_ids[key] = {
                    "assetId": up.get("assetId"),
                    "moderation": up.get("moderationState"),
                    "brief": info.get("brief", clip),
                    "duration": info["duration"],
                    "loop": info["loop"],
                    "keyframes": summary["keyframes"],
                    "poseCount": len(summary["poseNames"]),
                    "nominalSpeed": info.get("nominalSpeed"),
                    "markers": [{"time": m[0], "name": m[1], "value": m[2]} for m in info.get("markers", [])],
                    "rbxmBytes": summary["bytes"],
                }
            clips[clip] = clip_ids[key]
        regions = {}
        for name, tris in rep["regions"].items():
            mode = REGION_MODE.get(name, "Overlay")
            if mode == "TintMask" and rep.get("textures", {}).get("baked"):
                mode = "Overlay"  # the tint is baked into the colour map: the region shows as imported
            regions[name] = {"tris": tris, "alphaMode": mode}
            tint = rep.get("textures", {}).get("tint", {}).get(name)
            if tint:
                regions[name]["tint"] = tint
        if variant == "rodent":
            regions.setdefault("Eyes", {})["glow"] = {"material": "Neon", "color": "#ff2a1a",
                                                     "note": "the eyes glow: remove the Eyes SurfaceAppearance or add a PointLight; red eyes survive the avatar blend"}
        entry = {
            "rig": cfg["rig"],
            "model": {"assetId": model.get("assetId"), "moderation": model.get("moderationState"), "fbxBytes": os.path.getsize(fbx), "sha": sha(fbx)},
            "bones": rep.get("bones"),
            "bonesMatchRigSpec": True,
            "weights": {k: {"maxInfluences": v["max_influences"], "unweighted": v["unweighted"], "rootWeighted": v["root_group"]} for k, v in rep.get("weights", {}).items()},
            "tris": {"total": sum(rep["regions"].values()), **rep["regions"]},
            "regions": regions,
            "sockets": sockets(mod),
            "hipHeight": getattr(mod, "HIP_HEIGHT", None),
            "clips": clips,
            "clipsShared": cfg["clips_from"] != variant,
        }
        if variant == "buck":
            entry["scale"] = 1.1
        doc["species"][variant] = entry
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w") as fh:
        json.dump(doc, fh, indent=2)
    print(out_path)


if __name__ == "__main__":
    main()
