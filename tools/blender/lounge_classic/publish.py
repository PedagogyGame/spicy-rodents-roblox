"""Upload THE GILDED ACORN's hero pieces as one Roblox Model and write the data the loader reads (stdlib only).

  python3 -I tools/blender/lounge_classic/publish.py [--build build/art/lounge_classic] [--skip-upload]

Run tools/blender/lounge_classic/model.py first. Without --skip-upload this runs
  node tools/cloud/cloud.mjs upload_asset <build>/lounge.fbx --type Model --name "SR The Gilded Acorn hero pieces"
(the CLI holds the shared cloud write lock and token buckets; the proxy injects the key, nothing here handles one)
and keeps the result in <build>/uploads/lounge.json with a digest of what the Model holds (content_digest), so a
rerun only uploads what changed; with no cache (a fresh clone) it reuses the id data/art/lounge_classic.json
records for the same content. --skip-upload writes everything with the id left empty (as committed: the lead
uploads). Then it writes:
  data/art/lounge_classic.json            the asset id, its moderation state, and the manifest
  src/shared/Attractions/LoungeArt.luau   the same for the game (Server/Assets/LoungeArt): ASSET_ID ("" until
                                          uploaded), PIECES (name, material, colour, centre, size, tris), REPLACES
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
OUT = os.path.join(ROOT, "data", "art", "lounge_classic.json")
LUAU = os.path.join(ROOT, "src", "shared", "Attractions", "LoungeArt.luau")
NAME = "SR The Gilded Acorn hero pieces"
DESC = ("Spicy Rodent: THE GILDED ACORN lounge's bar, booths and wainscot, modelled procedurally "
        "(tools/blender/lounge_classic), in studs.")


def content_digest(manifest):
    blob = json.dumps({"pieces": manifest["pieces"], "scale": manifest["scale"]}, sort_keys=True)
    return hashlib.sha256(blob.encode()).hexdigest()[:16]


def committed(digest):
    if not os.path.exists(OUT):
        return None
    with open(OUT) as fh:
        a = json.load(fh).get("asset", {})
    if a.get("sha") == digest and a.get("assetId"):
        return {"assetId": a["assetId"], "moderationState": a.get("moderation"), "sourceSha": digest}
    return None


def upload(build, digest, skip):
    rec_path = os.path.join(build, "uploads", "lounge.json")
    if os.path.exists(rec_path):
        with open(rec_path) as fh:
            old = json.load(fh)
        if old.get("sourceSha") == digest and old.get("assetId"):
            return old
    seeded = committed(digest)
    if seeded:
        return seeded
    if skip:
        return {"assetId": None, "moderationState": "not uploaded", "sourceSha": digest}
    assert len(NAME) <= 50, NAME
    os.makedirs(os.path.dirname(rec_path), exist_ok=True)
    t0 = time.time()
    r = subprocess.run(["node", "tools/cloud/cloud.mjs", "upload_asset", os.path.join(build, "lounge.fbx"), "--type",
                        "Model", "--name", NAME, "--description", DESC, "--out", rec_path], cwd=ROOT,
                       capture_output=True, text=True, timeout=1200)
    if r.returncode != 0 or not os.path.exists(rec_path):
        sys.exit(f"upload failed:\n{r.stderr[-2000:]}")
    with open(rec_path) as fh:
        res = json.load(fh)
    res["sourceSha"] = digest
    res["uploadSeconds"] = round(time.time() - t0, 1)
    res.pop("raw", None)
    with open(rec_path, "w") as fh:
        json.dump(res, fh, indent=2)
    print(f"  uploaded: {res.get('assetId')} ({res.get('moderationState')}) in {res['uploadSeconds']} s", flush=True)
    return res


def lua_value(v, indent):
    pad = "\t" * indent
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        return json.dumps(v)
    if isinstance(v, list):
        if all(isinstance(x, (int, float)) for x in v):
            return "{ " + ", ".join(lua_value(x, 0) for x in v) + " }"
        return "{\n" + "".join(f"{pad}\t{lua_value(x, indent + 1)},\n" for x in v) + pad + "}"
    if isinstance(v, dict):
        return "{ " + ", ".join(f"{k} = {lua_value(x, indent + 1)}" for k, x in v.items()) + " }"
    raise TypeError(type(v))


def write_luau(asset_id, manifest):
    pieces = [{k: p[k] for k in ("name", "material", "robloxMaterial", "colour", "tris", "centre", "size")}
              for p in manifest["pieces"]]
    text = f"""--!strict
-- ReplicatedStorage.Shared.Attractions.LoungeArt
-- WRITTEN BY tools/blender/lounge_classic/publish.py: do not edit by hand.
-- THE GILDED ACORN's hero pieces (tools/blender/lounge_classic/model.py: the bar, the four booths, the side and back
-- walls' wainscot) as one uploaded Model, for Server/Assets/LoungeArt. ASSET_ID is "" until the lead uploads it
-- (publish.py without --skip-upload); while it is empty the loader does nothing and the baked parts are the look.
-- PIECES: each MeshPart's name, material (the game's), Roblox material, colour (sRGB), triangles, centre and size in
-- the venue frame (X across, Y up from the floor, D into the building; studs). REPLACES: the baked parts
-- (tools/bake/lounge_classic/Interior) the loader hides once the pieces are in (their collision kept).
-- Pure data. No side effects on require.

export type Piece = {{
	name: string,
	material: string,
	robloxMaterial: string,
	colour: {{ number }},
	tris: number,
	centre: {{ number }},
	size: {{ number }},
}}

local LoungeArt = {{}}

LoungeArt.ASSET_ID = {json.dumps(asset_id or "")}
LoungeArt.TOTAL_TRIS = {manifest["total"]}
LoungeArt.BUDGET = {manifest["budget"]}
LoungeArt.PIECES = {lua_value(pieces, 0)} :: {{ Piece }}
LoungeArt.REPLACES = {lua_value(manifest["replaces"], 0)} :: {{ string }}

return LoungeArt
"""
    with open(LUAU, "w") as fh:
        fh.write(text)
    stylua = shutil.which("stylua")
    if stylua:
        subprocess.run([stylua, LUAU], cwd=ROOT, check=True)
    else:
        print("publish: stylua is not on the PATH: format src/shared/Attractions/LoungeArt.luau before committing")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--build", default=os.path.join(ROOT, "build", "art", "lounge_classic"))
    ap.add_argument("--skip-upload", action="store_true")
    a = ap.parse_args()
    build = os.path.abspath(a.build)
    with open(os.path.join(build, "manifest.json")) as fh:
        manifest = json.load(fh)
    digest = content_digest(manifest)
    res = upload(build, digest, a.skip_upload)
    doc = {
        "$schema": "art/lounge_classic v1",
        "src": "tools/blender/lounge_classic (model.py: the hero pieces, procedural, in studs; publish.py: the upload).",
        "placement": "InsertService:LoadAsset(assetId):GetChildren()[1] is a Model of unrotated MeshParts, one per piece "
                     "(by name); Server/Assets/LoungeArt puts each at its `centre` in the venue frame, paints it its "
                     "`colour` in its `robloxMaterial`, and hides the baked parts named in `replaces`.",
        "asset": {
            "assetId": res.get("assetId"),
            "moderation": res.get("moderationState"),
            "displayName": NAME,
            "fbxBytes": os.path.getsize(os.path.join(build, "lounge.fbx")),
            "sha": digest,
        },
        "total": manifest["total"],
        "budget": manifest["budget"],
        "pieces": manifest["pieces"],
        "replaces": manifest["replaces"],
    }
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as fh:
        json.dump(doc, fh, indent=1)
        fh.write("\n")
    write_luau(res.get("assetId"), manifest)
    print(f"wrote {os.path.relpath(OUT, ROOT)} and {os.path.relpath(LUAU, ROOT)}: asset {res.get('assetId')} "
          f"({res.get('moderationState')}), {manifest['total']} triangles in {len(manifest['pieces'])} pieces")


if __name__ == "__main__":
    main()
