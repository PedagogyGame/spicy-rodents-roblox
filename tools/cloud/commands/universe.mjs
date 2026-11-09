import { getUniverse, creatorFromUniverse, getPlace } from "../lib/openCloud.mjs";
import { PLACES } from "../lib/config.mjs";
import { parseArgs, out } from "../lib/cli.mjs";

export default async function universe(argv) {
	const { flags } = parseArgs(argv);
	const t0 = Date.now();
	const u = await getUniverse();
	const creator = await creatorFromUniverse();
	const result = { universe: u, creator, ms: Date.now() - t0 };
	if (flags.places) {
		result.places = {};
		for (const [name, id] of Object.entries(PLACES)) {
			try {
				result.places[name] = await getPlace(id);
			} catch (err) {
				result.places[name] = { error: err.message };
			}
		}
	}
	out(result);
	return 0;
}
