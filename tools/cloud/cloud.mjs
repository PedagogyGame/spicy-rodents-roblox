#!/usr/bin/env node
// Spicy Rodents Open Cloud CLI (BUILD_PLAN §4.3 item 2, D15, §6.5).
//   node tools/cloud/cloud.mjs <command> [options]
// Commands: universe, save_place, run_engine_tests, upload_asset, harvest_ids, publish,
//           operation, status, help.
//
// Proxy: this process re-executes itself with NODE_USE_ENV_PROXY=1 so Node's built-in fetch
// follows HTTPS_PROXY (the egress proxy that injects the owner's API key for apis.roblox.com and
// re-terminates TLS with the CA in NODE_EXTRA_CA_CERTS). Nothing here handles keys.
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";

if (process.env.HTTPS_PROXY && process.env.NODE_USE_ENV_PROXY !== "1") {
	const r = spawnSync(process.execPath, [...process.execArgv, ...process.argv.slice(1)], {
		stdio: "inherit",
		env: { ...process.env, NODE_USE_ENV_PROXY: "1", NODE_NO_WARNINGS: process.env.NODE_NO_WARNINGS ?? "1" },
	});
	process.exit(r.status ?? 1);
}

const here = path.dirname(fileURLToPath(import.meta.url));
const [, , command, ...rest] = process.argv;

const COMMANDS = {
	universe: "universe.mjs",
	save_place: "save_place.mjs",
	run_engine_tests: "run_engine_tests.mjs",
	upload_asset: "upload_asset.mjs",
	harvest_ids: "harvest_ids.mjs",
	publish: "publish.mjs",
	operation: "operation.mjs",
	status: "status.mjs",
	lock_test: "lock_test.mjs",
};

function help() {
	process.stdout.write(`spicy-cloud: Open Cloud tooling (no keys here; the proxy injects them)

  universe                         read the universe and its owner (a 200 proves the key path works)
  save_place <file.rbxl> [--place ci] [--legacy] [--allow-main-place] [--out file.json]
                                   upload a new SAVED (unpublished) version; prints the version id
  run_engine_tests <task.luau> --version <v> [--place ci] [--inject ci.project.json [--inject-exclude generated]]
                                   [--timeout 300s] [--out file.json]
                                   create a Luau Execution task pinned to /versions/<v>, poll, print logs,
                                   parse the JSON result; exit 1 on failure. Scripts are capped at 1 MiB by the API;
                                   --inject rebuilds the code tree in the task, --inject-exclude leaves $path dirs out
  upload_asset <file> --type Image|Model|Animation --name <n> [--description <d>] [--creator-user id|--creator-group id]
                                   Assets API create with operation polling (creator = universe owner)
  harvest_ids [--place art_inbox] --version <v>   stub (W0): reads asset IDs from a place version
  publish <file.rbxl> --place main --i-really-mean-it      publish a version (refuses without the flag)
  operation <operations/id>        poll an Assets API operation
  status                           show token buckets and the local task registry
  lock_test [--hold-ms 1500]       offline: hold the shared write lock (run from two shells to see serialisation)

Every call shares the on-disk lock and token buckets under ${"$"}{SPICY_CLOUD_STATE_DIR:-~/.cache/spicy-rodents/cloud}.
`);
}

if (!command || command === "help" || command === "--help" || command === "-h") {
	help();
	process.exit(command ? 0 : 2);
}
const file = COMMANDS[command];
if (!file) {
	process.stderr.write(`unknown command "${command}"\n\n`);
	help();
	process.exit(2);
}
const mod = await import(path.join(here, "commands", file));
try {
	const code = await mod.default(rest);
	process.exit(typeof code === "number" ? code : 0);
} catch (err) {
	process.stderr.write(`error: ${err.stack || err.message}\n`);
	process.exit(1);
}
