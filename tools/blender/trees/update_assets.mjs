#!/usr/bin/env node
// Push rebuilt tree FBXs as NEW VERSIONS of the already uploaded Model assets (asset IDs stay stable,
// so data/art/trees.json and any placed references keep working; LoadAsset serves the latest version).
//   node tools/blender/trees/update_assets.mjs --build build/art/trees [--ids all|0,1,2]
// Reads <build>/upload_state.json (written by upload_trees.py), PATCHes assets/v1/assets/{id} with the
// FBX (same multipart shape as tools/cloud save_place), polls the operation and the moderation state,
// and records revisionId / fbxBytes back into upload_state.json. Run upload_trees.py --write-only after.
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

if (process.env.HTTPS_PROXY && process.env.NODE_USE_ENV_PROXY !== "1") {
	const r = spawnSync(process.execPath, [...process.execArgv, ...process.argv.slice(1)], {
		stdio: "inherit",
		env: { ...process.env, NODE_USE_ENV_PROXY: "1", NODE_NO_WARNINGS: "1" },
	});
	process.exit(r.status ?? 1);
}

const here = path.dirname(fileURLToPath(import.meta.url));
const lib = path.join(here, "..", "..", "cloud", "lib");
const { request, multipart } = await import(path.join(lib, "http.mjs"));
const { withCloudWriteLock } = await import(path.join(lib, "lock.mjs"));
const { pollOperation } = await import(path.join(lib, "openCloud.mjs"));
const API = "https://apis.roblox.com";

const args = process.argv.slice(2);
const flag = (k, d) => {
	const i = args.indexOf(`--${k}`);
	return i >= 0 ? args[i + 1] : d;
};
const build = path.resolve(flag("build", "build/art/trees"));
const statePath = path.join(build, "upload_state.json");
const state = JSON.parse(fs.readFileSync(statePath, "utf8"));
const idsArg = flag("ids", "all");
const ids = idsArg === "all" ? Object.keys(state).map(Number).sort((a, b) => a - b) : idsArg.split(",").map(Number);

let ok = 0;
let failed = 0;
for (const i of ids) {
	const st = state[String(i)];
	const fbx = path.join(build, `tree_${String(i).padStart(3, "0")}.fbx`);
	if (!st?.assetId || !fs.existsSync(fbx)) {
		process.stdout.write(`[${i}] skipped (no asset or no FBX)\n`);
		continue;
	}
	const bytes = fs.readFileSync(fbx);
	if (st.fbxBytes === bytes.length && st.updated) {
		ok += 1;
		continue;
	}
	const t0 = Date.now();
	try {
		const res = await withCloudWriteLock(`update tree ${i} ${st.assetId}`, async () => {
			const form = multipart({ assetId: String(st.assetId), assetType: "Model" }, bytes, "model/fbx", path.basename(fbx));
			const r = await request("PATCH", `${API}/assets/v1/assets/${st.assetId}`, { body: form, bucket: "assets", timeoutMs: 10 * 60_000 });
			if (!r.json?.path) throw new Error(`unexpected PATCH response: ${r.text.slice(0, 300)}`);
			const op = await pollOperation(r.json.path);
			return op.response || {};
		});
		let mod = res.moderationResult?.moderationState;
		const tm = Date.now();
		while (mod && mod !== "Approved" && mod !== "Rejected" && Date.now() - tm < 600_000) {
			await new Promise((r) => setTimeout(r, 10_000));
			const g = await request("GET", `${API}/assets/v1/assets/${st.assetId}?readMask=moderationResult`, { bucket: "reads" });
			mod = g.json?.moderationResult?.moderationState || mod;
		}
		st.revisionId = res.revisionId;
		st.moderation = mod || st.moderation;
		st.fbxBytes = bytes.length;
		st.updated = new Date().toISOString();
		st.updateS = Math.round((Date.now() - t0) / 100) / 10;
		fs.writeFileSync(statePath, JSON.stringify(state, null, 1));
		process.stdout.write(`[${String(i).padStart(3, "0")}] ${st.assetId} -> revision ${res.revisionId} ${st.moderation} (${st.updateS}s)\n`);
		if (st.moderation === "Approved") ok += 1;
		else failed += 1;
	} catch (err) {
		failed += 1;
		process.stdout.write(`[${i}] update FAILED: ${String(err.message || err).slice(0, 400)}\n`);
	}
}
process.stdout.write(`done: ${ok} approved, ${failed} not\n`);
process.exit(failed ? 1 : 0);
