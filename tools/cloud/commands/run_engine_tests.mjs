// run_engine_tests: create a Luau Execution task pinned to a place version, poll to completion,
// print the logs, parse the JSON return value (BUILD_PLAN §6.5). Exit codes: 0 pass, 1 the task
// failed or the result reports ok=false, 2 usage.
import fs from "node:fs";
import { createTask, waitForTask, getTaskLogs } from "../lib/openCloud.mjs";
import { wrapScript } from "../lib/inject.mjs";
import { resolvePlace } from "../lib/config.mjs";
import { appendLog } from "../lib/lock.mjs";
import { parseArgs, out, die, fmtMs } from "../lib/cli.mjs";

export default async function runEngineTests(argv) {
	const { flags, positional } = parseArgs(argv);
	const scriptFile = positional[0];
	if (!scriptFile) die("usage: run_engine_tests <task.luau> --version <v> [--place ci] [--inject ci.project.json [--inject-exclude generated,...]] [--timeout 300s] [--poll-ms 2000] [--out file.json]", 2);
	if (!fs.existsSync(scriptFile)) die(`no such file: ${scriptFile}`, 2);
	if (!flags.version) die("--version <placeVersion> is required (pin every task to the version its save returned)", 2);
	const place = resolvePlace(flags.place);
	if (place.name === "main" && !flags["allow-main-place"]) {
		die("engine tests run on the CI place; pass --allow-main-place only for a deliberate read-only check of an owner build", 3);
	}
	let script = fs.readFileSync(scriptFile, "utf8");
	let injected = null;
	if (flags.inject) {
		// Save-free mode: rebuild the project's code tree inside the task before running the script.
		if (!fs.existsSync(flags.inject)) die(`no such project file: ${flags.inject}`, 2);
		// --inject-exclude generated,other: project-relative $path directories left out of the tree
		// (compiled data alone is 1.3 MB; the task script must stay under 1 MiB, see below).
		const exclude = typeof flags["inject-exclude"] === "string" ? flags["inject-exclude"].split(",").map((s) => s.trim()) : [];
		const wrapped = wrapScript(flags.inject, script, { exclude });
		script = wrapped.script;
		injected = {
			project: flags.inject,
			instances: wrapped.tree.instances.length,
			skippedContentFiles: wrapped.tree.skipped.length,
			excluded: wrapped.tree.excluded,
		};
		process.stderr.write(`[engine] inject mode: ${injected.instances} instances from ${flags.inject} (${(Buffer.byteLength(script) / 1024).toFixed(0)} KB script${wrapped.tree.excluded.length ? `; excluded ${wrapped.tree.excluded.join(", ")}` : ""})\n`);
	}
	// Measured 2026-11-09 against the live API: "Script too large: was 1502344 bytes, limit is 1048576 bytes".
	// (BUILD_PLAN/feasibility say 4 MB; that figure is wrong for the script body.)
	const MAX_SCRIPT_BYTES = 1024 * 1024;
	if (Buffer.byteLength(script) > MAX_SCRIPT_BYTES) {
		die(
			`task script is ${Buffer.byteLength(script)} bytes; Luau Execution accepts at most ${MAX_SCRIPT_BYTES} (1 MiB).` +
				(flags.inject ? " In inject mode pass --inject-exclude generated (compiled data is the bulk) or save a real version." : ""),
			2,
		);
	}

	const t0 = Date.now();
	process.stderr.write(`[engine] creating task on ${place.name} (${place.id}) version ${flags.version} from ${scriptFile}\n`);
	const { task, createMs } = await createTask({ placeId: place.id, version: flags.version, script, timeout: flags.timeout });
	process.stderr.write(`[engine] task ${task.path.split("/").pop()} ${task.state} (create ${fmtMs(createMs)})\n`);

	let lastState = task.state;
	const finished = await waitForTask(task.path, {
		pollMs: Number(flags["poll-ms"] || 2000),
		onPoll: (t) => {
			if (t.state !== lastState) {
				process.stderr.write(`[engine] ${t.state} after ${fmtMs(Date.now() - t0)}\n`);
				lastState = t.state;
			}
		},
	});
	const logs = await getTaskLogs(task.path);
	const totalMs = Date.now() - t0;

	process.stdout.write(`--- task logs (${logs.length} message(s)) ---\n`);
	for (const line of logs) process.stdout.write(`${line}\n`);
	process.stdout.write(`--- end logs ---\n`);

	const result = finished.output?.results?.[0];
	const summary = {
		taskPath: finished.path,
		state: finished.state,
		error: finished.error,
		placeId: place.id,
		version: String(flags.version),
		injected,
		createMs,
		totalMs,
		result,
	};
	if (flags.out) fs.writeFileSync(flags.out, JSON.stringify({ ...summary, logs }, null, 2));
	out(summary);

	const pass = finished.state === "COMPLETE" && !(result && typeof result === "object" && result.ok === false);
	appendLog("tasks", `${place.name} v${flags.version} ${finished.state} ${pass ? "PASS" : "FAIL"} ${totalMs}ms ${scriptFile}`);
	process.stderr.write(`[engine] ${pass ? "PASS" : "FAIL"} in ${fmtMs(totalMs)}\n`);
	return pass ? 0 : 1;
}
