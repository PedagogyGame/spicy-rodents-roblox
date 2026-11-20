// audioBudget: the audio upload rule (docs/AUDIO_BUDGET.md; BRIEF_ADDENDUM B3), read from the assets log.
// The owner's verified cap is 100 audio uploads a month; this game works within 40, may go to 50 when genuinely
// needed, and always keeps at least 50 for his other games. docs/AUDIO_BUDGET.md's tally is the authority; this is
// the local backstop: every audio upload this tool starts is logged ("audio-attempt", before the request, so a
// failed or interrupted one still counts) and counted over a rolling 30 days (Roblox's window; stricter than the
// calendar month). Pure apart from reading the log file; no network.
import fs from "node:fs";

export const WORKING = 40; // the month's working budget
export const CEILING = 50; // genuinely needed, and only with --beyond-working-budget; never more
export const WINDOW_DAYS = 30;
export const ATTEMPT = "audio-attempt";

// The attempt lines of the log text within the window ending at `now` (a Date): [{ at, sha, file }]
export function attempts(logText, now) {
	const since = now.getTime() - WINDOW_DAYS * 24 * 3600 * 1000;
	const out = [];
	for (const line of String(logText || "").split("\n")) {
		const m = /^(\S+) audio-attempt sha (\S+) (.*)$/.exec(line);
		if (!m) continue;
		const at = Date.parse(m[1]);
		if (Number.isNaN(at) || at < since || at > now.getTime()) continue;
		out.push({ at: m[1], sha: m[2], file: m[3] });
	}
	return out;
}

// May one more audio upload of `sha` start? { ok, used, reason }
//   used: attempts in the window; refused at CEILING always, at WORKING unless beyondWorking, and for a sha already
//   attempted in the window unless reupload (the same take twice spends two of the cap for nothing).
export function check(logText, now, sha, { beyondWorking = false, reupload = false } = {}) {
	const list = attempts(logText, now);
	const used = list.length;
	if (used >= CEILING) {
		return { ok: false, used, reason: `${used} audio uploads in the last ${WINDOW_DAYS} days: ${CEILING} is this game's ceiling (the owner keeps at least 50 of his 100 for his other games)` };
	}
	if (used >= WORKING && !beyondWorking) {
		return { ok: false, used, reason: `${used} audio uploads in the last ${WINDOW_DAYS} days: the working budget is ${WORKING}; past it only when genuinely needed, with --beyond-working-budget (at most ${CEILING})` };
	}
	if (!reupload && list.some((a) => a.sha === sha)) {
		return { ok: false, used, reason: `this file (sha ${sha}) was already uploaded as audio in the last ${WINDOW_DAYS} days; pass --reupload only if that upload was lost` };
	}
	return { ok: true, used, reason: "" };
}

export function readLog(file) {
	try {
		return fs.readFileSync(file, "utf8");
	} catch {
		return "";
	}
}
