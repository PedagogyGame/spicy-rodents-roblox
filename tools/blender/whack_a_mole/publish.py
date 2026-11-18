"""Upload the whack-a-mole cabinet's FBX as a Roblox Model and write what the game reads (stdlib only).

  python3 -I tools/blender/whack_a_mole/publish.py [--build build/art/whack_a_mole] [--skip-upload]

Run tools/blender/whack_a_mole/export.py first. Without --skip-upload this runs
  node tools/cloud/cloud.mjs upload_asset build/art/whack_a_mole/whack.fbx --type Model --name <name>
(the CLI holds the shared cloud write lock and token buckets; the proxy injects the key, nothing here handles one)
and keeps the result in <build>/uploads/whack.json with a digest of what the Model holds (content_digest), so a
rerun uploads only what changed; with no cache (a fresh clone) it reuses the id data/art/whack_a_mole.json
records for the same content. With --skip-upload nothing is uploaded and the id stays empty (the game then keeps
its baked cabinet). Either way it writes:
  data/art/whack_a_mole.json                     the record: the asset, its moderation state, the manifest
  src/shared/Minigames/WhackAMole/Art.luau       what the loader (src/server/Assets/WhackArt) reads: the asset id
                                                 ("" = none yet) and each piece's group, mole, material and centre
                                                 (formatted with stylua when it is on the PATH)
"""
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
OUT = os.path.join(ROOT, "data", "art", "whack_a_mole.json")
LUAU = os.path.join(ROOT, "src", "shared", "Minigames", "WhackAMole", "Art.luau")
TAG, FBX = "whack", "whack.fbx"
NAME = "SR Whack-a-Mole cabinet"
DESC = ("Spicy Rodent: the owner's whack-a-mole cabinet, game version (about 12,000 triangles, the moles and the "
        "mallet separate), 1/0.28 studs per metre. tools/blender/whack_a_mole")


def content_digest(manifest):
    """What the Model holds, as the manifest records it (the FBX bytes carry export timestamps)."""
    blob = json.dumps({"pieces": manifest["pieces"], "sources": manifest["sources"], "scale": manifest["scale"]},
                      sort_keys=True)
    return hashlib.sha256(blob.encode()).hexdigest()[:16]


def committed(digest):
    if not os.path.exists(OUT):
        return None
    with open(OUT) as fh:
        a = json.load(fh).get("assets", {}).get(TAG)
    if a and a.get("sha") == digest and a.get("assetId"):
        return {"assetId": a["assetId"], "moderationState": a.get("moderation"), "sourceSha": digest}
    return None


def upload(build, skip, digest):
    rec_path = os.path.join(build, "uploads", f"{TAG}.json")
    if os.path.exists(rec_path):
        with open(rec_path) as fh:
            old = json.load(fh)
        if old.get("sourceSha") == digest and old.get("assetId"):
            return old
    seeded = committed(digest)
    if seeded:
        os.makedirs(os.path.dirname(rec_path), exist_ok=True)
        with open(rec_path, "w") as fh:
            json.dump(seeded, fh, indent=2)
        return seeded
    if skip:
        return {"assetId": None, "moderationState": "not uploaded", "sourceSha": digest}
    os.makedirs(os.path.dirname(rec_path), exist_ok=True)
    t0 = time.time()
    r = subprocess.run(["node", "tools/cloud/cloud.mjs", "upload_asset", os.path.join(build, FBX), "--type", "Model",
                        "--name", NAME, "--description", DESC, "--out", rec_path], cwd=ROOT, capture_output=True,
                       text=True, timeout=1200)
    if r.returncode != 0 or not os.path.exists(rec_path):
        sys.exit(f"upload {TAG} failed:\n{r.stderr[-2000:]}")
    with open(rec_path) as fh:
        res = json.load(fh)
    res["sourceSha"] = digest
    res["uploadSeconds"] = round(time.time() - t0, 1)
    res.pop("raw", None)
    with open(rec_path, "w") as fh:
        json.dump(res, fh, indent=2)
    print(f"  uploaded {TAG}: {res.get('assetId')} ({res.get('moderationState')}) in {res['uploadSeconds']} s")
    return res


def num(v):
    return repr(round(v, 4)) if isinstance(v, float) else str(v)


def write_luau(asset_id, manifest):
    lines = [
        "--!strict",
        "-- ReplicatedStorage.Shared.Minigames.WhackAMole.Art",
        "-- WRITTEN BY tools/blender/whack_a_mole/publish.py (do not edit by hand): the whack-a-mole cabinet's meshes",
        "-- from the owner's Blender file (tools/blender/whack_a_mole/export.py), as the art loader reads them",
        "-- (src/server/Assets/WhackArt). assetId \"\" means not uploaded yet: the game keeps its baked cabinet.",
        "-- Each piece: its group (shell, mole, mallet), the mole it belongs to, its material (Layout.COLORS' name),",
        "-- the Roblox material it is drawn in, and its centre in the cabinet frame (Layout: u, v, w studs).",
        "-- Pure data. Interface: assetId; total (triangles); pieces { [name]: Piece }",
        "",
        "export type Piece = {",
        "\tgroup: string,",
        "\tmole: number?,",
        "\tmaterial: string,",
        "\trobloxMaterial: string,",
        "\tcentre: { number },",
        "\ttris: number,",
        "}",
        "",
        "return {",
        f"\tassetId = \"{asset_id or ''}\",",
        f"\ttotal = {manifest['total']},",
        "\tpieces = {",
    ]
    for p in manifest["pieces"]:
        c = ", ".join(num(x) for x in p["centre"])
        mole = f" mole = {p['mole']}," if "mole" in p else ""
        lines.append(f"\t\t{p['name']} = {{ group = \"{p['group']}\",{mole} material = \"{p['material']}\", "
                     f"robloxMaterial = \"{p['robloxMaterial']}\", centre = {{ {c} }}, tris = {p['tris']} }},")
    lines += ["\t} :: { [string]: Piece },", "}", ""]
    with open(LUAU, "w") as fh:
        fh.write("\n".join(lines))
    stylua = shutil.which("stylua")
    if stylua:
        subprocess.run([stylua, LUAU], cwd=ROOT, check=True)
    else:
        print("publish: stylua is not on the PATH: format src/shared/Minigames/WhackAMole/Art.luau before committing")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--build", default=os.path.join(ROOT, "build", "art", "whack_a_mole"))
    ap.add_argument("--skip-upload", action="store_true")
    a = ap.parse_args()
    build = os.path.abspath(a.build)
    with open(os.path.join(build, "manifest.json")) as fh:
        manifest = json.load(fh)
    digest = content_digest(manifest)
    res = upload(build, a.skip_upload, digest)
    asset = {
        "assetId": res.get("assetId"),
        "moderation": res.get("moderationState"),
        "displayName": NAME,
        "fbxBytes": os.path.getsize(os.path.join(build, FBX)),
        "sha": res.get("sourceSha"),
    }
    doc = {
        "$schema": "art/whack_a_mole v1",
        "src": "tools/blender/whack_a_mole (export.py: the owner's .blend as one FBX in studs; publish.py: the upload).",
        "placement": "InsertService:LoadAsset(assetId):GetChildren()[1] is a Model of MeshParts named as `pieces`; "
                     "each MeshPart is unrotated in the alley's site frame (the bake's: X across, Y up, -D) and is put at its "
                     "`centre` (cabinet frame, studs: Shared/Minigames/WhackAMole/Layout.toSite) by "
                     "Server/Assets/WhackArt, which paints it Layout.COLORS[material] (a mole's fur its own) and "
                     "parents a mole's pieces to its Mole model and the mallet's to the Mallet.",
        "assets": {TAG: asset},
    }
    for k, v in manifest.items():
        if k not in ("fbx", "format"):
            doc[k] = v
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as fh:
        json.dump(doc, fh, indent=1)
        fh.write("\n")
    write_luau(asset["assetId"], manifest)
    print(f"wrote {os.path.relpath(OUT, ROOT)} and {os.path.relpath(LUAU, ROOT)}: {TAG} "
          f"{asset['assetId']} ({asset['moderation']}), {manifest['total']} triangles in {len(manifest['pieces'])} pieces")


if __name__ == "__main__":
    main()
