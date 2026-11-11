--!strict
-- tools/sim/lib/Report: a replay's result as the printed summary, the JSON report and the trace CSV.
-- Interface: summary(result, top?, command?) -> string; json(result, command?) -> table;
--            worst(result, n) -> { Incident }; csv(rows) -> string; describe(settings) -> string
-- Pure.

local Detect = require("./Detect")

local Report = {}

local function num(v: number, digits: number?): string
	return string.format(`%.{digits or 2}f`, v)
end

local function ms(v: number): string
	return string.format("%.0f ms", v * 1000)
end

-- describe(settings): the conditions of a run in two lines.
function Report.describe(s: any): string
	local n, sv, c = s.net, s.server, s.client
	local net = `net {s.netName} ({ms(n.latency)} + {ms(n.jitter)} jitter, {num(n.loss * 100, 1)} % loss`
	if n.burstEvery > 0 then
		net ..= `, a {ms(n.burstLength)} burst every {num(n.burstEvery, 0)} s`
	end
	if n.reorder > 0 then
		net ..= `, {num(n.reorder * 100, 1)} % reordered`
	end
	net ..= ")"
	local function pace(name: string, p: any, unit: string): string
		local out = `{name} {num(p.hz, 0)} {unit}`
		if p.jitter > 0 then
			out ..= ` +/- {num(p.jitter * 1000, 1)} ms`
		end
		if p.spike > 0 then
			out ..= `, spikes {num(p.spike * 100, 1)} %`
		end
		if p.stallEvery > 0 then
			out ..= `, a {ms(p.stallMin)}-{ms(p.stallMax)} stall every {num(p.stallEvery, 0)} s`
		end
		return out
	end
	local extra = ""
	if s.uptime > 0 then
		extra ..= `; server up {num(s.uptime / 3600, 1)} h`
	end
	if s.clockSkew ~= 0 or s.clockDrift ~= 0 then
		extra ..= `; client clock {ms(s.clockSkew)} off, drifting {num(s.clockDrift * 1e6, 0)} ppm`
	end
	return `{net}\n  {pace(`server {s.serverName}`, sv, "Hz")}; {pace(`client {s.clientName}`, c, "fps")}{extra}`
end

-- worst(result, n): the n incidents furthest over their limits.
function Report.worst(result: any, n: number): { Detect.Incident }
	local list = table.clone(result.incidents) :: { Detect.Incident }
	table.sort(list, function(a: Detect.Incident, b: Detect.Incident): boolean
		if a.severity ~= b.severity then
			return a.severity > b.severity
		end
		return a.t < b.t
	end)
	local out = {}
	for i = 1, math.min(n, #list) do
		out[i] = list[i]
	end
	return out
end

local function kindRows(result: any): { { [string]: any } }
	local rows = {}
	local byKind: { [string]: { [string]: any } } = {}
	for _, def in result.detectors :: { Detect.Def } do
		for kind, what in def.kinds do
			local row = { kind = kind, what = what, detector = def.name, count = 0, sim = 0, stream = 0, worst = nil }
			byKind[kind] = row
			table.insert(rows, row)
		end
	end
	for kind, n in result.counts :: { [string]: number } do
		byKind[kind].count = n
	end
	for _, inc in result.incidents :: { Detect.Incident } do
		local row = byKind[inc.kind]
		if inc.origin == "sim" then
			row.sim += 1
		elseif inc.origin == "stream" then
			row.stream += 1
		end
		if row.worst == nil or inc.severity > row.worst.severity then
			row.worst = inc
		end
	end
	table.sort(rows, function(a, b): boolean
		if a.count ~= b.count then
			return a.count > b.count
		end
		return a.kind < b.kind
	end)
	return rows
end

local function incidentLine(inc: Detect.Incident): string
	local who = `#{inc.vehicle} {inc.name or "?"} ({inc.class or "?"})`
	local origin = ""
	if inc.origin then
		origin = ` [{inc.origin}{if inc.detail and inc.detail.truth then ": " .. tostring(inc.detail.truth) else ""}]`
	end
	return string.format(
		"t=%8.3f s  %-28s %-20s %10.2f %-6s (limit %.2f, x%.1f)%s  %d frame(s), %.2f s",
		inc.t,
		who,
		inc.kind,
		inc.magnitude,
		inc.unit,
		inc.limit,
		inc.severity,
		origin,
		inc.frames,
		inc.duration
	)
end

-- summary(result, top?, command?): the text printed at the end of a run. `command` is the command line
-- that repeats the run; each of the worst incidents gets the line that traces it.
function Report.summary(result: any, top: number?, command: string?): string
	local s, st = result.settings, result.stats
	local out = {}
	local function add(line: string)
		table.insert(out, line)
	end
	add(`traffic replay: scenario {result.scenario.name} ({result.scenario.about})`)
	add(`  {num(s.seconds, 1)} s simulated, seed {s.seed}, traffic seed {s.trafficSeed}; {Report.describe(s)}`)
	add(
		`  server: {st.serverFrames} frames (longest {ms(st.serverLongestFrame)}), {st.ticks} ticks, {st.sends} sends, {st.lost} lost, {st.reordered} held back, {st.deliveredOutOfOrder} handled out of order`
	)
	local starvedPct = if st.clientFrames > 0 then st.starvedFrames / st.clientFrames * 100 else 0
	add(
		`  client: {st.clientFrames} frames (longest {ms(st.clientLongestFrame)}), {st.starvedFrames} starved ({num(
			starvedPct,
			1
		)} %: drawing past the newest snapshot)`
	)
	local lag, lagMs, recon = st.lagStuds, st.lagMs, st.reconStuds
	add(
		`  drawn pose behind the server's pose at that instant: median {num(lag.p50)} st, 95 % {num(lag.p95)}, max {num(
			lag.max
		)} (as time, moving cars: median {num(lagMs.p50, 0)} ms, 95 % {num(lagMs.p95, 0)}, max {num(lagMs.max, 0)})`
	)
	add(
		`  drawn pose off the true pose of the instant being drawn: median {num(recon.p50)} st, 95 % {num(recon.p95)}, 99 % {num(
			recon.p99
		)}, max {num(recon.max)}`
	)
	local total = 0
	for _, n in result.counts :: { [string]: number } do
		total += n
	end
	add("")
	add(`incidents by kind ({total} in all; sim = the server's own state did it, stream = only the replication did):`)
	add(
		string.format(
			"  %-22s %6s %6s %6s  %-26s %s",
			"kind",
			"count",
			"sim",
			"stream",
			"worst",
			"what the player sees"
		)
	)
	for _, row in kindRows(result) do
		local worst = "-"
		if row.worst then
			worst = string.format("%.2f %s (x%.1f)", row.worst.magnitude, row.worst.unit, row.worst.severity)
		end
		add(string.format("  %-22s %6d %6d %6d  %-26s %s", row.kind, row.count, row.sim, row.stream, worst, row.what))
	end
	for kind, n in result.dropped :: { [string]: number } do
		add(`  ({n} more {kind} incidents were counted but not kept: over --max-per-kind)`)
	end
	local n = top or 10
	local worst = Report.worst(result, n)
	if #worst > 0 then
		add("")
		add(`the {#worst} worst (by times over the limit):`)
		for i, inc in worst do
			add(string.format("  %2d. %s", i, incidentLine(inc)))
			if command then
				add(
					string.format(
						"      trace it: %s --trace %.2f:%.2f --vehicle %d",
						command,
						math.max(0, inc.t - 0.5),
						inc.t + math.max(0.5, inc.duration + 0.25),
						inc.vehicle
					)
				)
			end
		end
	end
	return table.concat(out, "\n")
end

-- JSON has no infinity or NaN: they become strings.
local function clean(value: any): any
	if type(value) == "number" then
		if value ~= value then
			return "nan"
		elseif value == math.huge then
			return "inf"
		elseif value == -math.huge then
			return "-inf"
		end
		return value
	elseif type(value) == "table" then
		local out = {}
		for k, v in value do
			out[k] = clean(v)
		end
		return out
	end
	return value
end

-- json(result, command?): the report file: settings, statistics, the detectors with their thresholds
-- and reasons, the counts, every incident kept (in time order) and the worst ten.
function Report.json(result: any, command: string?): { [string]: any }
	local detectors = {}
	for _, def in result.detectors :: { Detect.Def } do
		local thresholds = {}
		for _, item in def.thresholds do
			local override = result.settings.thresholds[`{def.name}.{item.key}`]
			table.insert(thresholds, {
				key = item.key,
				value = if override ~= nil then override else item.value,
				default = item.value,
				unit = item.unit,
				why = item.why,
			})
		end
		table.insert(detectors, { name = def.name, kinds = def.kinds, thresholds = thresholds })
	end
	local kinds = {}
	for _, row in kindRows(result) do
		table.insert(kinds, {
			kind = row.kind,
			detector = row.detector,
			count = row.count,
			sim = row.sim,
			stream = row.stream,
			what = row.what,
			worstSeverity = if row.worst then row.worst.severity else 0,
		})
	end
	local vehicles = {}
	for id, info in result.vehicles :: { [number]: any } do
		table.insert(
			vehicles,
			{ id = id, name = info.name, kind = info.kind, class = info.class, lane = info.entry.lane }
		)
	end
	table.sort(vehicles, function(a, b): boolean
		return a.id < b.id
	end)
	local settings = table.clone(result.settings)
	settings.trace = nil
	return clean({
		tool = "tools/sim/traffic_replay.luau",
		command = command,
		scenario = { name = result.scenario.name, about = result.scenario.about },
		settings = settings,
		stats = result.stats,
		vehicles = vehicles,
		detectors = detectors,
		kinds = kinds,
		counts = result.counts,
		dropped = result.dropped,
		worst = Report.worst(result, 10),
		incidents = result.incidents,
	})
end

local TRACE_COLUMNS = {
	"frame",
	"t",
	"dt",
	"packets",
	"snaps",
	"starved",
	"offset",
	"id",
	"vis",
	"x",
	"y",
	"z",
	"yaw",
	"pitch",
	"speed",
	"snap",
	"tvis",
	"tx",
	"tz",
	"tyaw",
	"tspeed",
	"phase",
	"s",
	"rvis",
	"rx",
	"rz",
	"ryaw",
}

-- csv(rows): the trace rows (lib/Replay, settings.trace) as CSV: per frame and vehicle the seen pose
-- (vis x y z yaw pitch speed snap), the true pose at that instant (t*), and the true pose of the instant
-- being drawn (r*).
function Report.csv(rows: { { [string]: any } }): string
	local out = { table.concat(TRACE_COLUMNS, ",") }
	for _, row in rows do
		local cells = table.create(#TRACE_COLUMNS)
		for i, col in TRACE_COLUMNS do
			local v = row[col]
			if type(v) == "number" then
				cells[i] = if v % 1 == 0 then string.format("%d", v) else string.format("%.4f", v)
			elseif type(v) == "boolean" then
				cells[i] = if v then "1" else "0"
			else
				cells[i] = tostring(v)
			end
		end
		table.insert(out, table.concat(cells, ","))
	end
	return table.concat(out, "\n") .. "\n"
end

return Report
