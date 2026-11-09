// lock_test: offline check that the shared write lock serialises callers. Hold the lock for
// --hold-ms (default 1500) and print when it was acquired and released. Run it from two shells
// at once: the second one starts only after the first has released.
import { withCloudWriteLock } from "../lib/lock.mjs";
import { parseArgs, out } from "../lib/cli.mjs";

export default async function lockTest(argv) {
	const { flags } = parseArgs(argv);
	const holdMs = Number(flags["hold-ms"] || 1500);
	const label = String(flags.label || `lock_test pid ${process.pid}`);
	const requested = Date.now();
	const result = await withCloudWriteLock(label, async () => {
		const acquired = Date.now();
		await new Promise((r) => setTimeout(r, holdMs));
		return { label, requestedAt: new Date(requested).toISOString(), acquiredAt: new Date(acquired).toISOString(), waitedMs: acquired - requested, heldMs: holdMs };
	});
	result.releasedAt = new Date().toISOString();
	out(result);
	return 0;
}
