"""Upload the townspeople's Models and write data/art/people.json and src/shared/Avatar/PeopleAssets.luau (stdlib only).

  python3 -I tools/blender/people/publish.py [--build build/people] [--skip-upload]
  python3 -I tools/blender/people/publish.py --luau-only      (rewrite PeopleAssets.luau from data/art/people.json)

Run build_people.py, check_people.py and export_people.py first. For each file export_people.py wrote into
<build>/upload (body_slim, body_broad, head, headwear, outfits, faces) this runs
  node tools/cloud/cloud.mjs upload_asset <fbx> --type Model --name <name>
(the CLI holds the shared cloud write lock and token buckets; the proxy injects the key, nothing here handles one)
and keeps each result in <build>/uploads/<tag>.json with the file's content digest (upload.json), so a rerun only
uploads what changed; with no cache (a fresh clone) it reuses the ids data/art/people.json records for the same
content. With --skip-upload nothing is uploaded and an id not already on record stays null: the game then keeps
its stock bodies (Server/Assets/PeopleArt does nothing without all six ids).
Then it writes data/art/people.json (the ids, moderation states and the rig the loader needs from the manifest)
and src/shared/Avatar/PeopleAssets.luau (the same as a Luau table; tests/unit/people_art.spec.luau fails when the
two disagree).
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
OUT = os.path.join(ROOT, "data", "art", "people.json")
LUAU = os.path.join(ROOT, "src", "shared", "Avatar", "PeopleAssets.luau")
UPLOADS = [
    ("bodySlim", "body_slim", "SR townspeople slim body",
     "Spicy Rodent: the slim townsperson, fourteen R15 parts and the outfit extras (rounded people). tools/blender/people"),
    ("bodyBroad", "body_broad", "SR townspeople broad body",
     "Spicy Rodent: the broad townsperson, fourteen R15 parts and the outfit extras (rounded people). tools/blender/people"),
    ("head", "head", "SR townspeople head",
     "Spicy Rodent: the townspeople's head (calm face). tools/blender/people"),
    ("headwear", "headwear", "SR townspeople hair and hats",
     "Spicy Rodent: eight hair styles, the peaked cap and the beret. tools/blender/people"),
    ("outfits", "outfits", "SR townspeople outfits",
     "Spicy Rodent: one square per outfit texture (the game clones their SurfaceAppearances). tools/blender/people"),
    ("faces", "faces", "SR townspeople faces",
     "Spicy Rodent: one square per face texture (the game clones their SurfaceAppearances). tools/blender/people"),
]
VEC_KEYS = ("center", "size", "c0", "c1", "position", "offset")


def committed(tag, digest):
    if not os.path.exists(OUT):
        return None
    with open(OUT) as fh:
        a = json.load(fh).get("assets", {}).get(tag)
    if a and a.get("sha") == digest and a.get("assetId"):
        return {"assetId": a["assetId"], "moderationState": a.get("moderation"), "sourceSha": digest}
    return None


def upload(build, tag, fbx, name, desc, skip, digest):
    rec_path = os.path.join(build, "uploads", f"{tag}.json")
    if os.path.exists(rec_path):
        with open(rec_path) as fh:
            old = json.load(fh)
        if old.get("sourceSha") == digest and old.get("assetId"):
            return old
    seeded = committed(tag, digest)
    if seeded:
        os.makedirs(os.path.dirname(rec_path), exist_ok=True)
        with open(rec_path, "w") as fh:
            json.dump(seeded, fh, indent=2)
        return seeded
    if skip:
        return {"assetId": None, "moderationState": "not uploaded", "sourceSha": digest}
    assert len(name) <= 50, name
    os.makedirs(os.path.dirname(rec_path), exist_ok=True)
    t0 = time.time()
    r = subprocess.run(["node", "tools/cloud/cloud.mjs", "upload_asset", fbx, "--type", "Model", "--name", name,
                        "--description", desc, "--out", rec_path], cwd=ROOT, capture_output=True, text=True, timeout=1200)
    if r.returncode != 0 or not os.path.exists(rec_path):
        sys.exit(f"upload {tag} failed:\n{r.stderr[-2000:]}")
    with open(rec_path) as fh:
        res = json.load(fh)
    res["sourceSha"] = digest
    res["uploadSeconds"] = round(time.time() - t0, 1)
    res.pop("raw", None)
    with open(rec_path, "w") as fh:
        json.dump(res, fh, indent=2)
    print(f"  uploaded {tag}: {res.get('assetId')} ({res.get('moderationState')}) in {res['uploadSeconds']} s", flush=True)
    return res


def rig_of(manifest):
    """What the loader needs from the build's manifest (positions in studs, Roblox axes, part-relative)."""
    builds = {}
    for b, d in manifest["builds"].items():
        builds[b] = {
            "parts": {n: {"center": p["center"], "size": p["size"], "tris": p["tris"]} for n, p in d["parts"].items()},
            "joints": {n: {"part0": j["part0"], "part1": j["part1"], "c0": j["c0"], "c1": j["c1"]} for n, j in d["joints"].items()},
            "attachments": {n: {"part": a["part"], "position": a["position"]} for n, a in d["attachments"].items()},
            "extras": {n: {"weldTo": e["weldTo"], "offset": e["offset"], "tint": e["tint"], "tris": e["tris"], "size": e["size"]}
                       for n, e in d["extras"].items()},
            "triangles": d["triangles"],
        }
    headwear = {n: {"kind": h["kind"], "offset": h["offset"], "size": h["size"], "tint": h["tint"], "tris": h["tris"],
                    **({"underCap": h["underCap"]} if "underCap" in h else {})}
                for n, h in manifest["headwear"]["items"].items()}
    outfits = {o: {"label": v["label"], "tints": v["tints"], "extras": v["extras"]} for o, v in manifest["outfits"].items()}
    roles = {r: {"outfits": v["outfits"], "face": v["face"], "hat": v["hat"], "hair": v["hair"]} for r, v in manifest["roles"].items()}
    return {
        "rootPart": manifest["rootPart"],
        "builds": builds,
        "outfits": outfits,
        "head": {"tint": manifest["heads"]["tint"], "faces": manifest["heads"]["faces"], "expressions": manifest["heads"]["expressions"]},
        "headwear": headwear,
        "roles": roles,
    }


# ---- Luau ----------------------------------------------------------------------------------------------

HEADER = """--!strict
-- ReplicatedStorage.Shared.Avatar.PeopleAssets
-- The rounded townspeople (tools/blender/people): the six uploaded Models and the rig the game puts them on.
-- WRITTEN BY tools/blender/people/publish.py FROM data/art/people.json; tests/unit/people_art.spec.luau fails
-- when the two disagree. An asset id of 0 is not uploaded: Server/Assets/PeopleArt then leaves every stock body
-- as it is.
-- Positions are studs in Roblox axes (+Y up, the person faces -Z): a part's `center` is relative to the
-- HumanoidRootPart's centre in the rest pose; a joint's c0 and c1 are its pivot relative to the centres of part0
-- and part1 (Motor6D C0 = CFrame.new(c0), C1 = CFrame.new(c1)); an attachment's `position` and an extra's or a
-- headwear item's `offset` are relative to the centre of the part it is on or welded to. A tint is a look key
-- (skin, shirt, pants, hair, cap) or a fixed "#rrggbb".
-- Interface: ASSETS; ROOT; BUILDS; OUTFITS; HEAD; HEADWEAR; ROLES.
-- Pure data. No side effects on require.

export type Vec = { number }
export type Part = { center: Vec, size: Vec, tris: number }
export type Joint = { part0: string, part1: string, c0: Vec, c1: Vec }
export type Attachment = { part: string, position: Vec }
export type Extra = { weldTo: string, offset: Vec, tint: string, tris: number, size: Vec }
export type Build = {
	parts: { [string]: Part },
	joints: { [string]: Joint },
	attachments: { [string]: Attachment },
	extras: { [string]: Extra },
	triangles: { [string]: number },
}
export type Outfit = { label: string, tints: { [string]: string }, extras: { string } }
export type Head = { tint: string, faces: { string }, expressions: { string } }
export type Headwear = { kind: string, offset: Vec, size: Vec, tint: string, tris: number, underCap: boolean? }
export type Role = { outfits: { string }, face: string, hat: string?, hair: { string } }
"""


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def lua_key(k):
    return k if k.isidentifier() else f"[{lua_str(k)}]"


def lua_num(x):
    if isinstance(x, bool):
        return "true" if x else "false"
    if isinstance(x, int):
        return str(x)
    s = f"{x:.4f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def lua(v, indent=1):
    pad = "\t" * indent
    if v is None:
        return "nil"
    if isinstance(v, bool) or isinstance(v, (int, float)):
        return lua_num(v)
    if isinstance(v, str):
        return lua_str(v)
    if isinstance(v, list):
        if all(isinstance(x, (int, float)) for x in v):
            return "{ " + ", ".join(lua_num(x) for x in v) + " }"
        return "{ " + ", ".join(lua(x, indent) for x in v) + " }"
    if isinstance(v, dict):
        if not v:
            return "{}"
        simple = all(not isinstance(x, (dict, list)) or (isinstance(x, list) and all(isinstance(y, (int, float)) for y in x))
                     for x in v.values())
        items = [f"{lua_key(k)} = {lua(v[k], indent + 1)}" for k in sorted(v) if v[k] is not None]
        line = "{ " + ", ".join(items) + " }"
        if simple and len(line) + len(pad) < 110:
            return line
        return "{\n" + "".join(f"{pad}\t{it},\n" for it in items) + pad + "}"
    raise TypeError(type(v))


def write_luau(doc):
    rig = doc["rig"]
    ids = {tag: int(a["assetId"]) if a.get("assetId") else 0 for tag, a in doc["assets"].items()}
    parts = [HEADER, "local PeopleAssets = {}\n"]
    parts.append(f"PeopleAssets.ASSETS = {lua(ids, 0)} :: {{ [string]: number }}\n")
    parts.append(f"PeopleAssets.ROOT = {lua(rig['rootPart'], 0)}\n")
    for key, name, typ in (("builds", "BUILDS", "{ [string]: Build }"), ("outfits", "OUTFITS", "{ [string]: Outfit }"),
                           ("head", "HEAD", "Head"), ("headwear", "HEADWEAR", "{ [string]: Headwear }"),
                           ("roles", "ROLES", "{ [string]: Role }")):
        parts.append(f"-- stylua: ignore\nPeopleAssets.{name} = {lua(rig[key], 0)} :: {typ}\n")
    parts.append("return PeopleAssets\n")
    with open(LUAU, "w") as fh:
        fh.write("\n".join(parts))
    # the repository's formatter, when it is installed (CI checks the file with it)
    stylua = shutil.which("stylua") or os.path.expanduser("~/.cargo/bin/stylua")
    if os.path.exists(stylua):
        subprocess.run([stylua, LUAU], cwd=ROOT, check=False)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--build", default=os.path.join(ROOT, "build", "people"))
    ap.add_argument("--skip-upload", action="store_true")
    ap.add_argument("--luau-only", action="store_true")
    a = ap.parse_args()
    if a.luau_only:
        with open(OUT) as fh:
            write_luau(json.load(fh))
        print(f"wrote {os.path.relpath(LUAU, ROOT)}")
        return
    build = os.path.abspath(a.build)
    with open(os.path.join(build, "manifest.json")) as fh:
        manifest = json.load(fh)
    with open(os.path.join(build, "upload", "upload.json")) as fh:
        files = json.load(fh)["files"]
    assets = {}
    for tag, key, name, desc in UPLOADS:
        f = files[key]
        res = upload(build, tag, os.path.join(build, f["path"]), name, desc, a.skip_upload, f["content"])
        assets[tag] = {
            "assetId": res.get("assetId"),
            "moderation": res.get("moderationState"),
            "displayName": name,
            "file": f"upload/{key}.fbx",
            "fbxBytes": f["bytes"],
            "objects": f["objects"],
            "triangles": sum(f["tris"].values()),
            "sha": res.get("sourceSha"),
        }
    doc = {
        "$schema": "art/people v1",
        "src": "tools/blender/people (build_people.py: sculpt, paint and the manifest; check_people.py; export_people.py: "
               "the six upload files; publish.py: the upload, this file and src/shared/Avatar/PeopleAssets.luau).",
        "placement": "InsertService:LoadAsset(assetId) holds MeshParts named as `objects`, each unrotated with a SurfaceAppearance. "
                     "Server/Assets/PeopleArt swaps a stock R15's fifteen parts for them (same names, the Motor6Ds and attachments "
                     "kept and moved to the rig below), welds the outfit's extras and the hair and hat, and dresses an outfit or "
                     "a face by cloning the SurfaceAppearance of the matching square in `outfits` (Outfit_<outfit>) or `faces` (Face_<face>_<expression>).",
        "generated": manifest["generated"],
        "assets": assets,
        "rig": rig_of(manifest),
    }
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as fh:
        json.dump(doc, fh, indent=1)
        fh.write("\n")
    write_luau(doc)
    print(f"wrote {os.path.relpath(OUT, ROOT)} and {os.path.relpath(LUAU, ROOT)}: "
          + ", ".join(f"{k} {v['assetId']} ({v['moderation']})" for k, v in assets.items()))


if __name__ == "__main__":
    main()
