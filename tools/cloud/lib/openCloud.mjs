// Open Cloud calls used by the commands. Endpoints and shapes come from the official OpenAPI
// spec and guides (Roblox/creator-docs: cloud/guides/usage-place-publishing.md,
// cloud/guides/usage-assets.md, reference/cloud/openapi.json), checked 2026-11-09.
import fs from "node:fs";
import path from "node:path";
import { API, UNIVERSE_ID, MAX_INCOMPLETE_TASKS_PER_PLACE, assertAllowedId } from "./config.mjs";
import { getJson, postJson, request, multipart } from "./http.mjs";
import { takeToken, withCloudWriteLock, readTasks, writeTasks, sleep } from "./lock.mjs";

export async function getUniverse(universeId = UNIVERSE_ID) {
	return getJson(`${API}/cloud/v2/universes/${universeId}`);
}

export async function getPlace(placeId, universeId = UNIVERSE_ID) {
	assertAllowedId(placeId);
	return getJson(`${API}/cloud/v2/universes/${universeId}/places/${placeId}`);
}

// Creator for uploads: the same user or group that owns the experience (feas B.c ownership).
export async function creatorFromUniverse(universeId = UNIVERSE_ID) {
	const u = await getUniverse(universeId);
	if (u.user) return { userId: u.user.replace(/^users\//, "") };
	if (u.group) return { groupId: u.group.replace(/^groups\//, "") };
	throw new Error(`universe ${universeId} has neither user nor group owner in ${JSON.stringify(u)}`);
}

const CONTENT_TYPES = {
	".rbxl": "application/octet-stream",
	".rbxlx": "application/xml",
	".rbxm": "model/x-rbxm",
	".rbxmx": "model/x-rbxm",
	".fbx": "model/fbx",
	".gltf": "model/gltf+json",
	".glb": "model/gltf-binary",
	".png": "image/png",
	".jpg": "image/jpeg",
	".jpeg": "image/jpeg",
	".bmp": "image/bmp",
	".tga": "image/tga",
	".mp3": "audio/mpeg",
	".ogg": "audio/ogg",
	".wav": "audio/wav",
	".flac": "audio/flac",
};

export function contentTypeFor(file) {
	const ct = CONTENT_TYPES[path.extname(file).toLowerCase()];
	if (!ct) throw new Error(`no content type known for ${file}`);
	return ct;
}

// ---- Operations (Assets API) -------------------------------------------------------------------

export async function getOperation(operationPath) {
	// operationPath looks like "operations/<id>"
	return getJson(`${API}/assets/v1/${operationPath}`);
}

export async function pollOperation(operationPath, { pollMs = 1500, timeoutMs = 10 * 60_000, onPoll } = {}) {
	const t0 = Date.now();
	let delay = pollMs;
	for (;;) {
		const op = await getOperation(operationPath);
		if (onPoll) onPoll(op);
		if (op.done) {
			if (op.error) {
				throw new Error(`operation ${operationPath} failed: ${JSON.stringify(op.error)}`);
			}
			return op;
		}
		if (Date.now() - t0 > timeoutMs) throw new Error(`operation ${operationPath} still running after ${timeoutMs} ms`);
		await sleep(delay);
		delay = Math.min(delay * 1.5, 8000);
	}
}

// ---- Place versions -----------------------------------------------------------------------------

// Assets API route (current docs): PATCH /assets/v1/assets/{placeId} with assetType Place.
// `published: false` saves a new unpublished version. Returns { versionNumber, isPublished, ... }.
export async function savePlaceViaAssets(placeId, filePath, { published = false, label = "save_place" } = {}) {
	assertAllowedId(placeId);
	const bytes = fs.readFileSync(filePath);
	const ct = contentTypeFor(filePath);
	return withCloudWriteLock(`${label} ${placeId} (assets)`, async () => {
		const t0 = Date.now();
		const form = multipart({ assetId: String(placeId), assetType: "Place", published }, bytes, ct, path.basename(filePath));
		const r = await request("PATCH", `${API}/assets/v1/assets/${placeId}`, { body: form, bucket: "assets", timeoutMs: 10 * 60_000 });
		const started = r.json;
		if (!started?.path) throw new Error(`unexpected PATCH response: ${r.text.slice(0, 400)}`);
		const uploadMs = Date.now() - t0;
		const op = await pollOperation(started.path);
		const resp = op.response || {};
		return {
			method: "assets",
			placeId: String(placeId),
			versionNumber: Number(resp.revisionId),
			isPublished: Boolean(resp.isPublished),
			operation: started.path,
			bytes: bytes.length,
			uploadMs,
			totalMs: Date.now() - t0,
		};
	});
}

// Legacy route: POST /universes/v1/{universeId}/places/{placeId}/versions?versionType=Saved|Published.
// Returns { versionNumber } synchronously. Scope universe-places:write.
export async function savePlaceViaUniversesV1(placeId, filePath, { versionType = "Saved", universeId = UNIVERSE_ID, label = "save_place" } = {}) {
	assertAllowedId(placeId);
	if (!["Saved", "Published"].includes(versionType)) throw new Error(`versionType must be Saved or Published`);
	const bytes = fs.readFileSync(filePath);
	const ct = contentTypeFor(filePath);
	return withCloudWriteLock(`${label} ${placeId} (universes v1)`, async () => {
		const t0 = Date.now();
		const r = await request("POST", `${API}/universes/v1/${universeId}/places/${placeId}/versions?versionType=${versionType}`, {
			headers: { "content-type": ct },
			body: bytes,
			bucket: "legacy_publish",
			timeoutMs: 10 * 60_000,
		});
		const json = r.json;
		if (!json || json.versionNumber === undefined) throw new Error(`unexpected response: ${r.text.slice(0, 400)}`);
		return {
			method: "universes-v1",
			placeId: String(placeId),
			versionNumber: Number(json.versionNumber),
			isPublished: versionType === "Published",
			bytes: bytes.length,
			uploadMs: Date.now() - t0,
			totalMs: Date.now() - t0,
		};
	});
}

// ---- Luau Execution -----------------------------------------------------------------------------

const TERMINAL = new Set(["COMPLETE", "FAILED", "CANCELLED"]);

async function refreshIncompleteTasks(placeId) {
	const tasks = readTasks();
	let changed = false;
	for (const t of tasks) {
		if (t.placeId === String(placeId) && !TERMINAL.has(t.state)) {
			try {
				const fresh = await getTask(t.path);
				if (fresh.state !== t.state) {
					t.state = fresh.state;
					changed = true;
				}
			} catch (err) {
				// A 404 means the task is gone (expired); treat as complete.
				if (err.status === 404) {
					t.state = "EXPIRED";
					changed = true;
				}
			}
		}
	}
	if (changed) writeTasks(tasks);
	return tasks.filter((t) => t.placeId === String(placeId) && !TERMINAL.has(t.state) && t.state !== "EXPIRED");
}

export async function createTask({ placeId, version, script, timeout, universeId = UNIVERSE_ID, label = "run_engine_tests" }) {
	assertAllowedId(placeId);
	if (version === undefined || version === null || version === "") {
		throw new Error("a place version is required: every engine-test task is pinned to the version its save returned (S-13)");
	}
	return withCloudWriteLock(`${label} ${placeId} v${version}`, async () => {
		// Honour "10 incomplete per place" using the local registry.
		for (let i = 0; i < 60; i += 1) {
			const incomplete = await refreshIncompleteTasks(placeId);
			if (incomplete.length < MAX_INCOMPLETE_TASKS_PER_PLACE) break;
			process.stderr.write(`[luau] ${incomplete.length} incomplete tasks on place ${placeId}; waiting 10 s\n`);
			await sleep(10_000);
		}
		const url = `${API}/cloud/v2/universes/${universeId}/places/${placeId}/versions/${version}/luau-execution-session-tasks`;
		const payload = { script };
		if (timeout) payload.timeout = timeout; // e.g. "300s" (max 5 min)
		const t0 = Date.now();
		const task = await postJson(url, payload, { bucket: "luau_create" });
		const tasks = readTasks();
		tasks.push({ path: task.path, placeId: String(placeId), version: String(version), state: task.state, createdAt: new Date().toISOString() });
		// Keep the registry small.
		writeTasks(tasks.slice(-200));
		return { task, createMs: Date.now() - t0 };
	});
}

export async function getTask(taskPath) {
	return getJson(`${API}/cloud/v2/${taskPath}`);
}

export async function getTaskLogs(taskPath, { view = "FLAT" } = {}) {
	const messages = [];
	let pageToken;
	do {
		const url = new URL(`${API}/cloud/v2/${taskPath}/logs`);
		url.searchParams.set("view", view);
		url.searchParams.set("maxPageSize", "10000");
		if (pageToken) url.searchParams.set("pageToken", pageToken);
		const page = await getJson(url.toString());
		for (const log of page.luauExecutionSessionTaskLogs || []) {
			if (view === "STRUCTURED") messages.push(...(log.structuredMessages || []));
			else messages.push(...(log.messages || []));
		}
		pageToken = page.nextPageToken;
	} while (pageToken);
	return messages;
}

export async function waitForTask(taskPath, { pollMs = 2000, timeoutMs = 6 * 60_000, onPoll } = {}) {
	const t0 = Date.now();
	for (;;) {
		const task = await getTask(taskPath);
		if (onPoll) onPoll(task);
		if (TERMINAL.has(task.state)) {
			const tasks = readTasks();
			const entry = tasks.find((t) => t.path === taskPath);
			if (entry) {
				entry.state = task.state;
				writeTasks(tasks);
			}
			return task;
		}
		if (Date.now() - t0 > timeoutMs) throw new Error(`task ${taskPath} still ${task.state} after ${timeoutMs} ms`);
		await sleep(pollMs);
	}
}

// ---- Assets -------------------------------------------------------------------------------------

export async function createAsset({ assetType, filePath, displayName, description = "", creator, label = "upload_asset" }) {
	if (!["Image", "Decal", "Model", "Animation", "Audio", "Video"].includes(assetType)) {
		throw new Error(`unsupported assetType ${assetType}`);
	}
	const bytes = fs.readFileSync(filePath);
	const ct = contentTypeFor(filePath);
	if (bytes.length > 20 * 1024 * 1024) throw new Error("Assets API accepts at most 20 MB per file");
	return withCloudWriteLock(`${label} ${assetType} ${path.basename(filePath)}`, async () => {
		const t0 = Date.now();
		const req = {
			assetType: assetType === "Image" ? "Decal" : assetType,
			displayName,
			description,
			creationContext: { creator },
		};
		const form = multipart(req, bytes, ct, path.basename(filePath));
		const r = await request("POST", `${API}/assets/v1/assets`, { body: form, bucket: "assets", timeoutMs: 10 * 60_000 });
		const started = r.json;
		if (!started?.path) throw new Error(`unexpected POST response: ${r.text.slice(0, 400)}`);
		const uploadMs = Date.now() - t0;
		const op = await pollOperation(started.path);
		const resp = op.response || {};
		return {
			assetType: req.assetType,
			assetId: resp.assetId,
			displayName: resp.displayName,
			moderationState: resp.moderationResult?.moderationState,
			revisionId: resp.revisionId,
			operation: started.path,
			bytes: bytes.length,
			uploadMs,
			totalMs: Date.now() - t0,
			raw: resp,
		};
	});
}

export { takeToken };
