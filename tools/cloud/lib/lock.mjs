// Shared on-disk lock and token buckets for every Open Cloud call (BUILD_PLAN §4.1 "Cloud
// concurrency", D15, S-13). Two shells saving at once are serialised by the write lock; every
// create/upload/publish takes a token from its bucket first, sleeping until one is free.
import fs from "node:fs";
import path from "node:path";
import { BUCKETS, stateDir } from "./config.mjs";

const STALE_LOCK_MS = 15 * 60_000;

export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function pidAlive(pid) {
	try {
		process.kill(pid, 0);
		return true;
	} catch (err) {
		return err.code === "EPERM";
	}
}

function lockPath(name) {
	return path.join(stateDir(), "locks", `${name}.lock`);
}

async function acquireLock(name, { timeoutMs = 20 * 60_000, pollMs = 150, label = "" } = {}) {
	const dir = lockPath(name);
	fs.mkdirSync(path.dirname(dir), { recursive: true });
	const started = Date.now();
	let announced = false;
	for (;;) {
		try {
			fs.mkdirSync(dir);
			fs.writeFileSync(
				path.join(dir, "owner.json"),
				JSON.stringify({ pid: process.pid, startedAt: new Date().toISOString(), label }),
			);
			return () => {
				try {
					fs.rmSync(dir, { recursive: true, force: true });
				} catch {
					/* already gone */
				}
			};
		} catch (err) {
			if (err.code !== "EEXIST") throw err;
		}
		// Somebody holds it. Break stale locks (dead pid or too old).
		let owner = null;
		try {
			owner = JSON.parse(fs.readFileSync(path.join(dir, "owner.json"), "utf8"));
		} catch {
			/* owner file not written yet or unreadable */
		}
		const ageMs = owner?.startedAt ? Date.now() - Date.parse(owner.startedAt) : 0;
		if ((owner && !pidAlive(owner.pid)) || ageMs > STALE_LOCK_MS) {
			process.stderr.write(`[lock] breaking stale lock ${name} held by pid ${owner?.pid ?? "?"}\n`);
			fs.rmSync(dir, { recursive: true, force: true });
			continue;
		}
		if (!announced) {
			process.stderr.write(`[lock] waiting for ${name} (held by pid ${owner?.pid ?? "?"}${owner?.label ? `, ${owner.label}` : ""})\n`);
			announced = true;
		}
		if (Date.now() - started > timeoutMs) {
			throw new Error(`timed out after ${timeoutMs} ms waiting for lock ${name}`);
		}
		await sleep(pollMs);
	}
}

export async function withLock(name, fn, opts = {}) {
	const release = await acquireLock(name, opts);
	const t0 = Date.now();
	try {
		return await fn();
	} finally {
		release();
		if (opts.label) process.stderr.write(`[lock] released ${name} after ${Date.now() - t0} ms\n`);
	}
}

// The single write lock: held across a whole place save, a task create or an asset upload.
export function withCloudWriteLock(label, fn) {
	return withLock("cloud-write", fn, { label });
}

function bucketsFile() {
	return path.join(stateDir(), "buckets.json");
}

function readBuckets() {
	try {
		return JSON.parse(fs.readFileSync(bucketsFile(), "utf8"));
	} catch {
		return {};
	}
}

function writeBuckets(data) {
	fs.mkdirSync(path.dirname(bucketsFile()), { recursive: true });
	const tmp = `${bucketsFile()}.${process.pid}.tmp`;
	fs.writeFileSync(tmp, JSON.stringify(data));
	fs.renameSync(tmp, bucketsFile());
}

// Take one token from `bucket`, waiting while the sliding window is full. Returns the wait in ms.
export async function takeToken(bucket) {
	const spec = BUCKETS[bucket];
	if (!spec) throw new Error(`unknown bucket ${bucket}`);
	let waited = 0;
	for (;;) {
		const waitMs = await withLock("buckets", async () => {
			const all = readBuckets();
			const now = Date.now();
			const recent = (all[bucket] || []).filter((t) => now - t < spec.windowMs);
			if (recent.length < spec.cap) {
				recent.push(now);
				all[bucket] = recent;
				writeBuckets(all);
				return 0;
			}
			all[bucket] = recent;
			writeBuckets(all);
			return recent[0] + spec.windowMs - now + 50;
		});
		if (waitMs <= 0) return waited;
		process.stderr.write(`[bucket:${bucket}] ${spec.cap}/${spec.windowMs / 1000}s window full; waiting ${waitMs} ms\n`);
		await sleep(waitMs);
		waited += waitMs;
	}
}

export function bucketStatus() {
	const all = readBuckets();
	const now = Date.now();
	const out = {};
	for (const [name, spec] of Object.entries(BUCKETS)) {
		const recent = (all[name] || []).filter((t) => now - t < spec.windowMs);
		out[name] = { used: recent.length, cap: spec.cap, windowSeconds: spec.windowMs / 1000 };
	}
	return out;
}

// Local registry of Luau Execution tasks, so the "10 incomplete per place" rule can be honoured.
function tasksFile() {
	return path.join(stateDir(), "tasks.json");
}

export function readTasks() {
	try {
		return JSON.parse(fs.readFileSync(tasksFile(), "utf8"));
	} catch {
		return [];
	}
}

export function writeTasks(tasks) {
	fs.mkdirSync(path.dirname(tasksFile()), { recursive: true });
	const tmp = `${tasksFile()}.${process.pid}.tmp`;
	fs.writeFileSync(tmp, JSON.stringify(tasks, null, 1));
	fs.renameSync(tmp, tasksFile());
}

export function appendLog(name, line) {
	fs.mkdirSync(stateDir(), { recursive: true });
	fs.appendFileSync(path.join(stateDir(), `${name}.log`), `${new Date().toISOString()} ${line}\n`);
}
