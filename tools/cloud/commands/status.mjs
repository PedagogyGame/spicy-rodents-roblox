import { bucketStatus, readTasks } from "../lib/lock.mjs";
import { stateDir } from "../lib/config.mjs";
import { out } from "../lib/cli.mjs";

export default async function status() {
	out({ stateDir: stateDir(), buckets: bucketStatus(), tasks: readTasks().slice(-20) });
	return 0;
}
