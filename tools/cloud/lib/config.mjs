// Fixed project facts (docs/spec/PROJECT_IDS.md) and the rate-limit table (BUILD_PLAN §4.3 item 2).
// No secrets live here or anywhere in this tree: the API key is injected by the egress proxy
// for apis.roblox.com. Never add an x-api-key header.
import os from "node:os";
import path from "node:path";

export const API = "https://apis.roblox.com";

export const UNIVERSE_ID = "10775476638"; // experience "Spicy Rodent"

export const PLACES = Object.freeze({
	ci: "118507593202954", // automated test runs (Luau Execution); the ONLY place tooling writes to by default
	main: "106044514609985", // the real game; owner builds only, behind --allow-main-place
	art_inbox: "126198571623370", // owner's Studio imports; read-only for tooling (harvest_ids)
});

// The duplicate experience the owner created by mistake. Every command refuses these IDs.
export const FORBIDDEN_IDS = Object.freeze(["10775476357", "71294450489810"]);

// Sliding-window limits, per key owner unless noted (docs/spec/roblox_feasibility.md B.d; BUILD_PLAN §4.3).
export const BUCKETS = Object.freeze({
	luau_create: { cap: 5, windowMs: 60_000 }, // Luau Execution task creates per minute
	assets: { cap: 120, windowMs: 60_000 }, // Assets API create/update (uploads and Assets-API place saves)
	legacy_publish: { cap: 30, windowMs: 60_000 }, // universes/v1 publish (place saves with versionType=Saved)
	reads: { cap: 240, windowMs: 60_000 }, // polite cap on polling GETs
});

export const MAX_INCOMPLETE_TASKS_PER_PLACE = 10;

export function stateDir() {
	if (process.env.SPICY_CLOUD_STATE_DIR) return process.env.SPICY_CLOUD_STATE_DIR;
	const cache = process.env.XDG_CACHE_HOME || path.join(os.homedir(), ".cache");
	return path.join(cache, "spicy-rodents", "cloud");
}

export function resolvePlace(nameOrId) {
	if (!nameOrId) return { name: "ci", id: PLACES.ci };
	const key = String(nameOrId).toLowerCase().replace(/-/g, "_");
	if (PLACES[key]) return { name: key, id: PLACES[key] };
	if (/^\d+$/.test(nameOrId)) {
		const name = Object.keys(PLACES).find((k) => PLACES[k] === nameOrId) || "custom";
		return { name, id: nameOrId };
	}
	throw new Error(`unknown place "${nameOrId}" (use ci, main, art_inbox or a numeric place id)`);
}

export function assertAllowedId(id) {
	if (FORBIDDEN_IDS.includes(String(id))) {
		throw new Error(`refusing to touch ${id}: that is the duplicate "Spicy Rodents" experience (PROJECT_IDS.md)`);
	}
}
