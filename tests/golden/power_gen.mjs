// tests/golden/power_gen.mjs: golden vectors for Shared/Rodent/PowerRules (brief v2 §15 "Power, verbatim
// from v5.4"; squirrel_abilities §12). Runs v5.4's own updatePowerAndHeat (reference/v5_4_game.js
// L5506-5516, extracted verbatim and pinned by sha256) and the bite/hit lines it pairs with
// (L6527-6530 bite, L8113/8117 officer, L8964-8965 convert, L8021 baton, L11614 cat, L5468 stage)
// over seeded random event streams drawn with v5.4's rng (L80-89).
// Usage: node tests/golden/power_gen.mjs > tests/golden/power.json
import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";

const src = readFileSync(new URL("../../docs/reference/v5_4_game.js", import.meta.url), "utf8").split("\n");
const lines = (a, b) => src.slice(a - 1, b).join("\n");
const fade = lines(5506, 5516) + "\n}"; // the decay half of updatePowerAndHeat (chili rush and HUD dropped)
const rngSrc = lines(80, 89);
const sha = (s) => createHash("sha256").update(s).digest("hex");

const player = { points: 0, inactiveSeconds: 0 };
const flash = () => {};
const fx = () => {};
const POWER_DECAY_INTERVAL = 600;
const POWER_DECAY_RATE = 0.15;
const updatePowerAndHeat = new Function("player", "flash", "fx", "POWER_DECAY_INTERVAL", "POWER_DECAY_RATE",
	fade + "\nreturn updatePowerAndHeat;")(player, flash, fx, POWER_DECAY_INTERVAL, POWER_DECAY_RATE);
const rng = new Function(rngSrc + "\nreturn rng;")();
const stage = (p) => (p >= 1500 ? "SUPER" : p >= 600 ? "RABID" : "FERAL"); // L5468

const KINDS = ["bitePerson", "bitePerson", "biteOfficer", "convertSquirrel", "baton", "pedestrianKick", "cat",
	"tick", "tick", "tick", "tick", "chili", "coin", "climb", "missedPounce"];
const streams = [];
for (let s = 0; s < 40; s++) {
	const seed = 9100 + s;
	const r = rng(seed);
	player.points = 0;
	player.inactiveSeconds = 0;
	const converted = new Set();
	const rows = [];
	for (let i = 0; i < 120; i++) {
		const kind = KINDS[Math.floor(r() * KINDS.length)];
		const ev = { kind };
		if (kind === "bitePerson") {
			ev.y = Math.round(r() * 80) / 10; // world Y in HTML units, 0..8
			const pts = ev.y > 4 ? 150 : 100; // L6527
			player.points += pts;
			player.inactiveSeconds = 0;
		} else if (kind === "biteOfficer") {
			player.points += 130; // L8113
			player.inactiveSeconds = 0; // L8117
		} else if (kind === "convertSquirrel") {
			ev.id = Math.floor(r() * 12);
			if (!converted.has(ev.id)) { // L8958: `if (normal.infected ...) continue;`
				converted.add(ev.id);
				player.points += 90; // L8964
				player.inactiveSeconds = 0;
			}
		} else if (kind === "baton" || kind === "pedestrianKick") {
			player.points = Math.max(0, player.points - 19); // L8021 (officerBatonContact; Q23)
		} else if (kind === "cat") {
			player.points = Math.max(0, player.points - 12); // L11614
		} else if (kind === "tick") {
			ev.dt = Math.round(r() * 4000) / 10; // real active seconds, 0..400
			updatePowerAndHeat(ev.dt);
		}
		rows.push([ev, player.points, player.inactiveSeconds, stage(player.points)]);
	}
	streams.push({ seed, rows });
}
process.stdout.write(JSON.stringify({
	$schema: "golden/power v1",
	source: "reference/v5_4_game.js updatePowerAndHeat L5506-5516 (verbatim), bite/hit lines 6527, 8113, 8964, 8021, 11614, stage 5468",
	sha256: { updatePowerAndHeat: sha(fade), rng: sha(rngSrc) },
	columns: ["event", "points", "inactiveSeconds", "stage"],
	streams,
}) + "\n");
