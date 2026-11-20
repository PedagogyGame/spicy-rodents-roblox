// upload_asset: Assets API create (Image/Decal, Model, Animation, and Audio behind its budget flag) with operation
// polling. The creator is read from the universe (same user or group as the experience) unless overridden.
// Moderation state is printed; a pending or rejected asset must fall back to the placeholder (D12).
// Audio counts against the monthly cap (docs/AUDIO_BUDGET.md; BRIEF_ADDENDUM B3): it needs
// --i-am-within-audio-budget, takes only Ogg Vorbis (.ogg, audio/ogg), and lib/audioBudget refuses it past the
// working budget, at the ceiling, or for a take already uploaded. Video stays unexposed.
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { createAsset, creatorFromUniverse } from "../lib/openCloud.mjs";
import { appendLog } from "../lib/lock.mjs";
import { stateDir } from "../lib/config.mjs";
import { parseArgs, out, die, fmtMs } from "../lib/cli.mjs";
import * as audioBudget from "../lib/audioBudget.mjs";

const TYPES = ["Image", "Decal", "Model", "Animation", "Audio"];

export default async function uploadAsset(argv) {
	const { flags, positional } = parseArgs(argv);
	const file = positional[0];
	if (!file || !flags.type || !flags.name) {
		die(`usage: upload_asset <file> --type ${TYPES.join("|")} --name <displayName> [--description <text>] [--creator-user <id> | --creator-group <id>] [--out file.json]\n  audio: --type Audio --i-am-within-audio-budget [--beyond-working-budget] [--reupload] (an .ogg; docs/AUDIO_BUDGET.md)`, 2);
	}
	if (!fs.existsSync(file)) die(`no such file: ${file}`, 2);
	if (!TYPES.includes(flags.type)) die(`--type must be one of ${TYPES.join(", ")} (video is deliberately not exposed: upload caps, D24)`, 2);

	let sha = null;
	if (flags.type === "Audio") {
		// the cap is the owner's, shared with his other games: an explicit flag, the file type, then the budget
		if (flags["i-am-within-audio-budget"] !== true) {
			die("audio uploads spend the owner's monthly cap: check docs/AUDIO_BUDGET.md's tally, then pass --i-am-within-audio-budget", 3);
		}
		if (path.extname(file).toLowerCase() !== ".ogg") die("--type Audio takes an Ogg Vorbis file (.ogg, audio/ogg): tools/audio/make_candidates.py writes them", 2);
		sha = crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex").slice(0, 16);
		const verdict = audioBudget.check(audioBudget.readLog(path.join(stateDir(), "assets.log")), new Date(), sha, {
			beyondWorking: flags["beyond-working-budget"] === true,
			reupload: flags.reupload === true,
		});
		if (!verdict.ok) die(`audio refused: ${verdict.reason}`, 3);
		process.stderr.write(`[upload_asset] audio ${verdict.used + 1} in the last ${audioBudget.WINDOW_DAYS} days (working budget ${audioBudget.WORKING}, ceiling ${audioBudget.CEILING}); add it to docs/AUDIO_BUDGET.md's tally\n`);
	}

	let creator;
	if (flags["creator-user"]) creator = { userId: String(flags["creator-user"]) };
	else if (flags["creator-group"]) creator = { groupId: String(flags["creator-group"]) };
	else creator = await creatorFromUniverse();

	process.stderr.write(`[upload_asset] ${flags.type} "${flags.name}" from ${path.basename(file)} as ${JSON.stringify(creator)}\n`);
	// counted before the request, so an upload that fails or is cut off part-way still counts against the cap
	if (sha) appendLog("assets", `${audioBudget.ATTEMPT} sha ${sha} ${file}`);
	const result = await createAsset({
		assetType: flags.type,
		filePath: file,
		displayName: String(flags.name).slice(0, 50), // Assets API caps displayName at 50 chars
		description: String(flags.description || ""),
		creator,
	});
	appendLog("assets", `${result.assetType} ${result.assetId} ${result.moderationState} ${result.bytes}B ${result.totalMs}ms ${file}${sha ? ` sha ${sha}` : ""}`);
	process.stderr.write(`[upload_asset] asset ${result.assetId} (${result.moderationState}) in ${fmtMs(result.totalMs)}\n`);
	if (flags.out) fs.writeFileSync(flags.out, JSON.stringify(result, null, 2));
	out(result);
	return 0;
}
