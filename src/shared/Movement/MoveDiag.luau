--!strict
-- ReplicatedStorage.Shared.Movement.MoveDiag
-- The movement diagnostics the owner reads on screen (Client/UI/MoveDiagPanel, F8) and the server prints every
-- LOG_EVERY seconds: what Server/Movement/MovementService counted (its stats()), as rates over the time since the last
-- sample, in plain words. Numbers only: nothing here decides anything.
--   * the server samples its counters every SEND_EVERY seconds (sample) and sends the Report to the place's owner
--     (Net "Move.Diag"; Boot/Game);
--   * lines(report, client?) is the panel's text and the log's: the mode (SAFE: log-only, the client believed; or
--     ENFORCING), packets received and accepted a second, packets flagged a second, the violations by code (the TOP
--     most counted), snaps, pins and holds, the validator's errors (and the first one's text), what judging a packet
--     costs (average and worst, milliseconds), and from the client: its frames a second, the packets it sent a second,
--     its motor step's errors (and the first one's text).
-- Interface: SEND_EVERY; LOG_EVERY; TOP; KEY (the panel's key, an Enum.KeyCode name); HELP (the menu's help line);
--   new() -> Meter; sample(meter, stats, now, enforcing) -> Report; top(codes, n) -> { { code, n } };
--   lines(report?, client?) -> { string }
-- Pure. No side effects on require.

local MoveDiag = {}

MoveDiag.SEND_EVERY = 1
MoveDiag.LOG_EVERY = 30
MoveDiag.TOP = 5
MoveDiag.KEY = "F8"
MoveDiag.HELP = "F8: movement diagnostics (owner)"

export type Top = { { code: string, n: number } }

export type Report = {
	enforcing: boolean,
	seconds: number, -- the stretch the rates are over
	received: number, -- packets a second
	accepted: number, -- ... taken as the body's place
	flagged: number, -- ... the validator flagged
	stale: number, -- ... dropped (an old epoch, a ride, overtaken)
	top: Top, -- violations by code since the server started, the most counted first
	snaps: number, -- totals since the server started:
	pins: number,
	holds: number,
	errors: number,
	firstError: string?,
	benched: number,
	unjudged: number,
	believed: number,
	judgeAvgMs: number, -- over the stretch (0 when nothing was judged)
	judgeMaxMs: number, -- the worst since the server started
}

-- What the client adds for its own side (Client/Controllers/MotorHealth).
export type Client = {
	fps: number,
	sent: number, -- packets a second
	errors: number,
	firstError: string?,
}

export type Meter = {
	at: number?,
	packets: number,
	accepted: number,
	flagged: number,
	stale: number,
	judged: number,
	judgeMs: number,
}

function MoveDiag.new(): Meter
	return { at = nil, packets = 0, accepted = 0, flagged = 0, stale = 0, judged = 0, judgeMs = 0 }
end

local function num(v: any): number
	return if type(v) == "number" and v == v then v else 0
end

-- top(codes, n): the n most counted codes, the most first (ties by name, so two samples list them alike)
function MoveDiag.top(codes: any, n: number): Top
	local out: Top = {}
	if type(codes) == "table" then
		for code, count in codes do
			if type(count) == "number" and count > 0 then
				table.insert(out, { code = tostring(code), n = count })
			end
		end
	end
	table.sort(out, function(a, b)
		if a.n ~= b.n then
			return a.n > b.n
		end
		return a.code < b.code
	end)
	for i = #out, n + 1, -1 do
		out[i] = nil
	end
	return out
end

-- sample(meter, stats, now, enforcing) -> Report: MovementService's counters since the last sample, as rates
function MoveDiag.sample(meter: Meter, stats: any, now: number, enforcing: boolean): Report
	local seconds = if meter.at then math.max(1e-3, now - meter.at) else 0
	local function rate(key: string, was: number): number
		return if seconds > 0 then math.max(0, num(stats[key]) - was) / seconds else 0
	end
	local judged = math.max(0, num(stats.judged) - meter.judged)
	local report: Report = {
		enforcing = enforcing,
		seconds = seconds,
		received = rate("packets", meter.packets),
		accepted = rate("accepted", meter.accepted),
		flagged = rate("flagged", meter.flagged),
		stale = rate("stale", meter.stale),
		top = MoveDiag.top(stats.codes, MoveDiag.TOP),
		snaps = num(stats.snaps),
		pins = num(stats.pins),
		holds = num(stats.holds),
		errors = num(stats.errors),
		firstError = if type(stats.firstError) == "string" then stats.firstError else nil,
		benched = num(stats.benched),
		unjudged = num(stats.unjudged),
		believed = num(stats.believed),
		judgeAvgMs = if judged > 0 then math.max(0, num(stats.judgeMs) - meter.judgeMs) / judged else 0,
		judgeMaxMs = num(stats.judgeMaxMs),
	}
	meter.at = now
	meter.packets, meter.accepted = num(stats.packets), num(stats.accepted)
	meter.flagged, meter.stale = num(stats.flagged), num(stats.stale)
	meter.judged, meter.judgeMs = num(stats.judged), num(stats.judgeMs)
	return report
end

local function one(v: number): string
	return string.format("%.1f", v)
end

-- lines(report?, client?) -> the panel's lines (and the log's): short, plain, no colours
function MoveDiag.lines(report: any, client: any): { string }
	local out: { string } = {}
	if type(report) == "table" then
		table.insert(
			out,
			if report.enforcing then "MOVEMENT: ENFORCING (the server snaps back)" else "MOVEMENT: SAFE MODE (log-only)"
		)
		table.insert(
			out,
			`server packets/s: {one(num(report.received))} in, {one(num(report.accepted))} taken, {one(
				num(report.stale)
			)} dropped`
		)
		local codes = {}
		if type(report.top) == "table" then
			for _, t in report.top do
				if type(t) == "table" then
					table.insert(codes, `{tostring(t.code)} {num(t.n)}`)
				end
			end
		end
		table.insert(
			out,
			`flagged/s: {one(num(report.flagged))}   codes: {if #codes > 0 then table.concat(codes, ", ") else "none"}`
		)
		table.insert(
			out,
			`snaps {num(report.snaps)}   pins {num(report.pins)}   holds {num(report.holds)}   old-epoch taken {num(
				report.believed
			)}`
		)
		table.insert(
			out,
			`judge ms: avg {string.format("%.2f", num(report.judgeAvgMs))}, max {string.format(
				"%.2f",
				num(report.judgeMaxMs)
			)}   over budget {num(report.benched)}   unjudged {num(report.unjudged)}`
		)
		table.insert(
			out,
			`validator errors: {num(report.errors)}{if type(report.firstError) == "string"
				then "   first: " .. report.firstError
				else ""}`
		)
	else
		table.insert(out, "MOVEMENT: no word from the server yet")
	end
	if type(client) == "table" then
		table.insert(out, `client: {math.floor(num(client.fps) + 0.5)} fps   packets sent/s: {one(num(client.sent))}`)
		table.insert(
			out,
			`client motor errors: {num(client.errors)}{if type(client.firstError) == "string"
				then "   first: " .. client.firstError
				else ""}`
		)
	end
	return out
end

return MoveDiag
