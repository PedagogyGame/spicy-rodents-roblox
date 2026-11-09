import { pollOperation, getOperation } from "../lib/openCloud.mjs";
import { parseArgs, out, die } from "../lib/cli.mjs";

export default async function operation(argv) {
	const { flags, positional } = parseArgs(argv);
	let opPath = positional[0];
	if (!opPath) die("usage: operation <operations/id> [--wait]", 2);
	opPath = opPath.replace(/^https?:\/\/[^/]+\/assets\/v1\//, "");
	const op = flags.wait ? await pollOperation(opPath) : await getOperation(opPath);
	out(op);
	return 0;
}
