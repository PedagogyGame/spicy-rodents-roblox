"""Upload the tree FBXs as Roblox Models and write data/art/trees.json (stdlib only).

  python3 -I tools/blender/trees/upload_trees.py --build build/art/trees [--ids all|0,1,2] [--dry-run]

For each build/art/trees/tree_NNN.fbx (made by build_trees.py --fbx) this runs
  node tools/cloud/cloud.mjs upload_asset tree_NNN.fbx --type Model --name "SR tree NNN <LABEL>"
(the CLI holds the shared cloud write lock and token buckets, creator = the universe owner), polls
moderation until Approved (Assets API GET, then the operation), and on a rejection retries once
with a neutral name ("SR tree NNN"). State is kept in <build>/upload_state.json so a rerun resumes.
Finally writes data/art/trees.json from the per-tree build JSON + the asset IDs.
"""
import argparse
import json
import os
import subprocess
import sys
import time

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
CLOUD = os.path.join(REPO, "tools", "cloud", "cloud.mjs")


def display_name(idx, label):
    name = f"SR tree {idx:03d} {label}".strip()
    return name[:50]


def run_upload(fbx, name, out_json):
    cmd = ["node", CLOUD, "upload_asset", fbx, "--type", "Model", "--name", name,
           "--description", "Spicy Rodents procedural tree (tools/blender/trees)", "--out", out_json]
    t0 = time.time()
    p = subprocess.run(cmd, cwd=REPO, capture_output=True, text=True, timeout=900)
    dt = time.time() - t0
    res = None
    if os.path.exists(out_json):
        with open(out_json) as fh:
            res = json.load(fh)
    return p.returncode, res, dt, (p.stderr or "")[-1500:]


def get_moderation(asset_id):
    """Read the asset's moderation state through the Assets API (node + the proxy)."""
    js = (
        "import {request} from './tools/cloud/lib/http.mjs';"
        f"const r = await request('GET', 'https://apis.roblox.com/assets/v1/assets/{asset_id}?readMask=moderationResult,displayName', {{bucket: 'reads'}});"
        "process.stdout.write(JSON.stringify(r.json || {text: r.text}));"
    )
    env = dict(os.environ, NODE_USE_ENV_PROXY="1", NODE_NO_WARNINGS="1")
    p = subprocess.run(["node", "--input-type=module", "-e", js], cwd=REPO, capture_output=True, text=True, timeout=120, env=env)
    try:
        j = json.loads(p.stdout)
    except Exception:
        return None, p.stdout[-300:] + p.stderr[-300:]
    return (j.get("moderationResult") or {}).get("moderationState"), j


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--build", default="build/art/trees")
    ap.add_argument("--ids", default="all")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--write-only", action="store_true", help="only (re)write data/art/trees.json")
    ap.add_argument("--poll-s", type=int, default=600)
    a = ap.parse_args()
    build = os.path.abspath(a.build)
    state_path = os.path.join(build, "upload_state.json")
    state = {}
    if os.path.exists(state_path):
        with open(state_path) as fh:
            state = json.load(fh)
    infos = {}
    for fn in sorted(os.listdir(build)):
        if fn.startswith("tree_") and fn.endswith(".json"):
            with open(os.path.join(build, fn)) as fh:
                d = json.load(fh)
            infos[d["index"]] = d
    ids = sorted(infos) if a.ids == "all" else [int(x) for x in a.ids.split(",")]

    def save():
        with open(state_path, "w") as fh:
            json.dump(state, fh, indent=1)

    if not a.write_only:
        for i in ids:
            info = infos[i]
            key = str(i)
            st = state.get(key, {})
            if st.get("moderation") == "Approved" and st.get("fbxBytes") == info.get("fbxBytes"):
                continue
            fbx = info.get("fbx")
            if not fbx or not os.path.exists(fbx):
                print(f"[{i:03d}] no FBX, skipped", flush=True)
                continue
            names = [display_name(i, info["label"]), display_name(i, "")]
            attempt = st.get("attempt", 0)
            if st.get("moderation") == "Rejected":
                attempt = 1
            for tryno in range(attempt, 2):
                name = names[tryno]
                if a.dry_run:
                    print(f"[{i:03d}] would upload {os.path.basename(fbx)} as {name!r}")
                    break
                out_json = os.path.join(build, f"upload_{i:03d}.json")
                if os.path.exists(out_json):
                    os.remove(out_json)
                code, res, dt, err = run_upload(fbx, name, out_json)
                if code != 0 or not res or not res.get("assetId"):
                    # one transport retry
                    time.sleep(5)
                    code, res, dt, err = run_upload(fbx, name, out_json)
                if code != 0 or not res or not res.get("assetId"):
                    st = {"error": err, "name": name, "attempt": tryno}
                    state[key] = st
                    save()
                    print(f"[{i:03d}] upload FAILED: {err[-300:]}", flush=True)
                    break
                mod = res.get("moderationState")
                st = {"assetId": res["assetId"], "name": name, "moderation": mod, "uploadS": round(dt, 1),
                      "fbxBytes": info.get("fbxBytes"), "attempt": tryno, "operation": res.get("operation")}
                t0 = time.time()
                while mod not in ("Approved", "Rejected") and time.time() - t0 < a.poll_s:
                    time.sleep(10)
                    m2, raw = get_moderation(res["assetId"])
                    if m2:
                        mod = m2
                    st["moderation"] = mod
                st["moderationS"] = round(time.time() - t0, 1)
                state[key] = st
                save()
                print(f"[{i:03d}] {name!r} -> {st['assetId']} {mod} ({dt:.1f}s)", flush=True)
                if mod == "Rejected" and tryno == 0:
                    st["rejectedName"] = name
                    continue
                break
    # data/art/trees.json
    out = {
        "$schema": "art/trees v1",
        "src": "tools/blender/trees (build_trees.py geometry + textures, upload_trees.py upload). Procedural Blender only.",
        "units": "studs, Roblox axes (+Y up). pivot = the tree's root on the ground (data/harvest/trees.json root x 2.5).",
        "placement": ("model = InsertService:LoadAsset(assetId):GetChildren()[1] (a Model named displayName). Its pivot is "
                      "the FBX origin = the tree root, so model:PivotTo(CFrame.new(pivot[1], pivot[2], pivot[3])) puts every "
                      "MeshPart at pivot + parts[name].center (verified by tools/cloud/tasks/tree_load.luau: sizes and centres "
                      "exact). Anchor all parts. Bark carries the climbing surfaces (trunk radius = the squirrel's tapered "
                      "radius r(1 - 0.48 t), giants r/0.95 - 2.625 t; bough tops = rail + lift) and keeps collision; set "
                      "CanCollide/CanQuery false and CastShadow true on Leaves*/Apples. Pivot y is the harvested ground "
                      "height at the root; the trunk carries 3 studs of bark below it for terrain mismatch."),
        "partRoles": {"Bark": "trunk, roots, boughs, bridges, side branches, twigs, lookout pads: one skin at the junctions",
                      "LeavesShade": "leaf sprays under the canopy (alpha cards: doubleSided, alphaMode Transparency; no collide)",
                      "LeavesMid": "leaf sprays in half light (alpha cards; no collide)",
                      "LeavesSun": "leaf sprays that see the sky (alpha cards; no collide)", "Apples": "fruit (no collide)"},
        "count": 0,
        "trees": [],
    }
    for i in sorted(infos):
        info = infos[i]
        st = state.get(str(i), {})
        out["trees"].append({
            "index": i, "label": info["label"], "species": info["species"], "category": info["category"],
            "assetId": st.get("assetId"), "displayName": st.get("name"), "moderation": st.get("moderation"),
            "trunkRoute": info["trunkRoute"], "routes": info["routes"], "pivot": info["pivot"],
            "heightStuds": info.get("heightStuds"), "parts": info["parts"], "tris": info["tris"],
            "checks": {
                "trunkRadiusMaxAbsErr": info.get("checks", {}).get("trunk", {}).get("bark_minus_gameplay_radius_st", {}).get("max_abs"),
                "boughFeetToBarkP95": info.get("checks", {}).get("boughs", {}).get("feet_to_bark_surface_st", {}).get("p95_abs"),
                "leafTunnelMinMargin": info.get("checks", {}).get("leaves", {}).get("min_tunnel_margin_st"),
            },
        })
    out["count"] = len(out["trees"])
    dst = os.path.join(REPO, "data", "art", "trees.json")
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    with open(dst, "w") as fh:
        json.dump(out, fh, indent=1)
    ok = sum(1 for t in out["trees"] if t["moderation"] == "Approved")
    print(f"wrote {dst}: {out['count']} trees, {ok} approved", flush=True)


if __name__ == "__main__":
    main()
