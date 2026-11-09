// upload_asset: Assets API create (Image/Decal, Model, Animation) with operation polling.
// The creator is read from the universe (same user or group as the experience) unless overridden.
// Moderation state is printed; a pending or rejected asset must fall back to the placeholder (D12).
import fs from "node:fs";
import path from "node:path";
import { createAsset, creatorFromUniverse } from "../lib/openCloud.mjs";
import { appendLog } from "../lib/lock.mjs";
import { parseArgs, out, die, fmtMs } from "../lib/cli.mjs";

const TYPES = ["Image", "Decal", "Model", "Animation"];

export default async function uploadAsset(argv) {
	const { flags, positional } = parseArgs(argv);
	const file = positional[0];
	if (!file || !flags.type || !flags.name) {
		die(`usage: upload_asset <file> --type ${TYPES.join("|")} --name <displayName> [--description <text>] [--creator-user <id> | --creator-group <id>] [--out file.json]`, 2);
	}
	if (!fs.existsSync(file)) die(`no such file: ${file}`, 2);
	if (!TYPES.includes(flags.type)) die(`--type must be one of ${TYPES.join(", ")} (audio and video are deliberately not exposed: upload caps, D24)`, 2);

	let creator;
	if (flags["creator-user"]) creator = { userId: String(flags["creator-user"]) };
	else if (flags["creator-group"]) creator = { groupId: String(flags["creator-group"]) };
	else creator = await creatorFromUniverse();

	process.stderr.write(`[upload_asset] ${flags.type} "${flags.name}" from ${path.basename(file)} as ${JSON.stringify(creator)}\n`);
	const result = await createAsset({
		assetType: flags.type,
		filePath: file,
		displayName: String(flags.name),
		description: String(flags.description || ""),
		creator,
	});
	appendLog("assets", `${result.assetType} ${result.assetId} ${result.moderationState} ${result.bytes}B ${result.totalMs}ms ${file}`);
	process.stderr.write(`[upload_asset] asset ${result.assetId} (${result.moderationState}) in ${fmtMs(result.totalMs)}\n`);
	if (flags.out) fs.writeFileSync(flags.out, JSON.stringify(result, null, 2));
	out(result);
	return 0;
}
