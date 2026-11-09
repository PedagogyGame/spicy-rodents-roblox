// publish: make a place version PUBLISHED (live). Implemented, deliberately hard to run:
// requires --i-really-mean-it and --place main, and is never part of CI. Until W7 (§4.12) the
// only published content is the S11 spike town, and the lead runs that by hand.
import fs from "node:fs";
import { savePlaceViaAssets } from "../lib/openCloud.mjs";
import { resolvePlace } from "../lib/config.mjs";
import { appendLog } from "../lib/lock.mjs";
import { parseArgs, out, die, fmtMs } from "../lib/cli.mjs";

export default async function publish(argv) {
	const { flags, positional } = parseArgs(argv);
	const file = positional[0];
	if (!file) die("usage: publish <file.rbxl|rbxlx> --place main --i-really-mean-it [--out file.json]", 2);
	if (!flags["i-really-mean-it"]) {
		die("publish refuses to run without --i-really-mean-it. Publishing makes the version live for players and " +
			"breaks SLIM transcoding assumptions if the place contains SurfaceAppearance/unions (BUILD_PLAN §6.4). " +
			"Save an unpublished version with save_place instead.", 3);
	}
	if (!flags.place) die("publish requires an explicit --place (main); there is no default", 2);
	if (!fs.existsSync(file)) die(`no such file: ${file}`, 2);
	const place = resolvePlace(flags.place);
	if (place.name === "art_inbox" || place.name === "ci") die(`refusing to publish the ${place.name} place`, 3);

	process.stderr.write(`[publish] PUBLISHING ${file} to ${place.name} (${place.id}) in 5 s; Ctrl-C to abort\n`);
	await new Promise((r) => setTimeout(r, 5000));
	const result = await savePlaceViaAssets(place.id, file, { published: true, label: "publish" });
	result.place = place.name;
	result.file = file;
	appendLog("publishes", `${place.name} ${place.id} v${result.versionNumber} ${result.bytes}B ${result.totalMs}ms ${file}`);
	process.stderr.write(`[publish] version ${result.versionNumber} published in ${fmtMs(result.totalMs)}\n`);
	if (flags.out) fs.writeFileSync(flags.out, JSON.stringify(result, null, 2));
	out(result);
	return 0;
}
