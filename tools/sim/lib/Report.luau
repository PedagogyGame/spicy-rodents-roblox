--!strict
-- tools/sim/lib/Report: a replay's result as the printed summary, the JSON report and the trace CSV.
-- Interface: summary(result, top?, command?) -> string; json(result, command?) -> table;
--            worst(result, n, perKind?) -> { Incident }; kinds(result) -> rows; csv(rows) -> string;
--            describe(settings) -> string
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
		net ..= `, {num(n.reorder * 100, 1)} % held back`
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
	if s.clockStep ~= 0 then
		extra ..= `; client clock steps {ms(s.clockStep)} at {num(s.clockStepAt, 1)} s`
	end
	if s.joinAt > 0 then
		extra ..= `; client joins at {num(s.joinAt, 1)} s`
	end
	return `{net}\n  {pace(`server {s.serverName}`, sv, "Hz")}; {pace(`client {s.clientName}`, c, "fps")}{extra}`
end

-- worst(result, n, perKind?): the n incidents furthest over their limits, at most `perKind` of one kind
-- (default 2), so that one repeating event (every wrap of every car) does not fill the list.
function Report.worst(result: any, n: number, perKind: number?): { Detect.Incident }
	local list = table.clone(result.incidents) :: { Detect.Incident }
	table.sort(list, function(a: Detect.Incident, b: Detect.Incident): boolean
		if a.severity ~= b.severity then
			return a.severity > b.severity
		end
		return a.t < b.t
	end)
	local out = {}
	local taken: { [string]: number } = {}
	local cap = perKind or 2
	for _, inc in list do
		if #out >= n then
			break
		end
		if (taken[inc.kind] or 0) < cap then
			taken[inc.kind] = (taken[inc.kind] or 0) + 1
			table.insert(out, inc)
		end
	end
	return out
end

export type KindRow = {
	kind: string,
	what: string,
	detector: string,
	count: number,
	moments: number, -- distinct moments: runs of incidents of this kind starting within half a second
	sim: number,
	stream: number,
	vehicles: { { id: number, n: number } }, -- most incidents first
	worst: Detect.Incident?,
}

-- kinds(result): one row per incident kind every detector of the run can report, most frequent first.
function Report.kinds(result: any): { KindRow }
	local rows: { KindRow } = {}
	local byKind: { [string]: KindRow } = {}
	local last: { [string]: number } = {}
	local perVehicle: { [string]: { [number]: number } } = {}
	for _, def in result.detectors :: { Detect.Def } do
		for kind, what in def.kinds do
			local row: KindRow = {
				kind = kind,
				what = what,
				detector = def.name,
				count = 0,
				moments = 0,
				sim = 0,
				stream = 0,
				vehicles = {},
				worst = nil,
			}
			byKind[kind] = row
			perVehicle[kind] = {}
			table.insert(rows, row)
		end
	end
	for kind, n in result.counts :: { [string]: number } do
		byKind[kind].count = n
	end
	-- the incidents are in time order
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
		if inc.t - (last[inc.kind] or -math.huge) > 0.5 then
			row.moments += 1
		end
		last[inc.kind] = inc.t
		perVehicle[inc.kind][inc.vehicle] = (perVehicle[inc.kind][inc.vehicle] or 0) + 1
	end
	for _, row in rows do
		for id, n in perVehicle[row.kind] do
			table.insert(row.vehicles, { id = id, n = n })
		end
		table.sort(row.vehicles, function(a, b): boolean
			if a.n ~= b.n then
				return a.n > b.n
			end
			return a.id < b.id
		end)
	end
	table.sort(rows, function(a: KindRow, b: KindRow): boolean
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
		string.format(
			"  server: %d frames (longest %s), %d ticks, %d sends, %d lost, %d held back, %d handled out of order",
			st.serverFrames,
			ms(st.serverLongestFrame),
			st.ticks,
			st.sends,
			st.lost,
			st.reordered,
			st.deliveredOutOfOrder
		)
	)
	add(
		string.format(
			"  client: %d frames (longest %s), %d starved (%.1f %%: drawing past the newest snapshot)",
			st.clientFrames,
			ms(st.clientLongestFrame),
			st.starvedFrames,
			if st.clientFrames > 0 then st.starvedFrames / st.clientFrames * 100 else 0
		)
	)
	local lag, lagMs, recon = st.lagStuds, st.lagMs, st.reconStuds
	add(
		string.format(
			"  drawn pose behind the server's pose at that instant: median %.2f st, 95 %% %.2f, 99 %% %.2f (as time, moving cars: median %.0f ms, 95 %% %.0f, 99 %% %.0f)",
			lag.p50,
			lag.p95,
			lag.p99,
			lagMs.p50,
			lagMs.p95,
			lagMs.p99
		)
	)
	add(
		string.format(
			"  drawn pose off the true pose of the instant being drawn: median %.2f st, 95 %% %.2f, 99 %% %.2f, max %.2f",
			recon.p50,
			recon.p95,
			recon.p99,
			recon.max
		)
	)
	-- the detectors' own numbers (ctx.stats), one line each
	local names = {}
	for name in st.detectors :: { [string]: any } do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in names do
		local fields = {}
		for key, value in st.detectors[name] :: { [string]: any } do
			local shown = if type(value) == "number" and value % 1 ~= 0 then num(value) else tostring(value)
			table.insert(fields, `{key} {shown}`)
		end
		if #fields > 0 then
			table.sort(fields)
			add(`  {name}: {table.concat(fields, ", ")}`)
		end
	end
	local total = 0
	for _, n in result.counts :: { [string]: number } do
		total += n
	end
	add("")
	add(`incidents by kind ({total} in all; sim = the server's own state did it, stream = only the replication did):`)
	local layout = "  %-22s %6s %7s %5s %6s  %-26s %s"
	add(
		string.format(
			layout,
			"kind",
			"count",
			"moments",
			"sim",
			"stream",
			"worst",
			"what the player sees / which vehicles"
		)
	)
	local quiet = {}
	for _, row in Report.kinds(result) do
		local worst = row.worst
		if row.count == 0 or worst == nil then
			table.insert(quiet, row.kind)
			continue
		end
		add(
			string.format(
				layout,
				row.kind,
				tostring(row.count),
				tostring(row.moments),
				tostring(row.sim),
				tostring(row.stream),
				string.format("%.2f %s (x%.1f)", worst.magnitude, worst.unit, worst.severity),
				row.what
			)
		)
		local who = {}
		for i, item in row.vehicles do
			if i > 6 then
				table.insert(who, `and {#row.vehicles - 6} more`)
				break
			end
			local info = result.vehicles[item.id]
			table.insert(who, `#{item.id} {if info then info.name else "?"} x{item.n}`)
		end
		add(string.format(layout, "", "", "", "", "", "", "  " .. table.concat(who, ", ")))
	end
	if #quiet > 0 then
		table.sort(quiet)
		add(`  none of: {table.concat(quiet, ", ")}`)
	end
	for kind, n in result.dropped :: { [string]: number } do
		add(`  ({n} more {kind} incidents were counted but not kept: over --max-per-kind)`)
	end
	local worst = Report.worst(result, top or 10)
	if #worst > 0 then
		add("")
		add(`the {#worst} worst (by times over the limit; at most 2 of a kind):`)
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
-- and reasons, the counts per kind, every incident kept (in time order) and the worst ten.
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
	for _, row in Report.kinds(result) do
		table.insert(kinds, {
			kind = row.kind,
			detector = row.detector,
			count = row.count,
			moments = row.moments,
			sim = row.sim,
			stream = row.stream,
			vehicles = row.vehicles,
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
