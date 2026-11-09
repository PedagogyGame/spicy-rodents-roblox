// save_place: upload a .rbxl/.rbxlx as a new SAVED, unpublished version of a place and print the
// version number (BUILD_PLAN D15, §6.5 runner step 2). Default target is the CI place. The main
// place needs --allow-main-place (owner builds, §4.1). Never publishes: see publish.mjs.
import fs from "node:fs";
import { savePlaceViaAssets, savePlaceViaUniversesV1 } from "../lib/openCloud.mjs";
import { resolvePlace } from "../lib/config.mjs";
import { appendLog } from "../lib/lock.mjs";
import { parseArgs, out, die, fmtMs } from "../lib/cli.mjs";

export default async function savePlace(argv) {
	const { flags, positional } = parseArgs(argv);
	const file = positional[0];
	if (!file) die("usage: save_place <file.rbxl|rbxlx> [--place ci|main|<id>] [--legacy] [--allow-main-place] [--out file.json]", 2);
	if (!fs.existsSync(file)) die(`no such file: ${file}`, 2);
	if (flags.published || flags.publish) die("save_place never publishes; use `publish --i-really-mean-it` (and read BUILD_PLAN §4.12 first)", 2);

	const place = resolvePlace(flags.place);
	if (place.name === "main" && !flags["allow-main-place"]) {
		die("refusing to write to the main place without --allow-main-place (W0 rule: CI place only)", 3);
	}
	if (place.name === "art_inbox") die("the Art Inbox is owner-only; tooling never writes to it", 3);

	process.stderr.write(`[save_place] ${file} -> place ${place.name} (${place.id}) via ${flags.legacy ? "universes v1 (versionType=Saved)" : "Assets API (published=false)"}\n`);
	const result = flags.legacy
		? await savePlaceViaUniversesV1(place.id, file, { versionType: "Saved" })
		: await savePlaceViaAssets(place.id, file, { published: false });
	result.place = place.name;
	result.file = file;
	appendLog("saves", `${place.name} ${place.id} v${result.versionNumber} ${result.method} ${result.bytes}B ${result.totalMs}ms ${file}`);
	process.stderr.write(`[save_place] version ${result.versionNumber} saved in ${fmtMs(result.totalMs)} (upload ${fmtMs(result.uploadMs)})\n`);
	if (flags.out) fs.writeFileSync(flags.out, JSON.stringify(result, null, 2));
	out(result);
	return 0;
}
