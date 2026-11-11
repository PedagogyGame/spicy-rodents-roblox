--!strict
-- tools/sim/traffic_replay: the headless replay of the vehicle pose stream and its glitch detectors.
-- Runs the game's own fleet, send loop, wire format and client reconstruction (lib/Replay) under a seeded
-- network and frame-time model, records what a player would see next to what the server knows, and
-- reports every incident the detectors (tools/sim/detectors) find.
--
-- Usage (repo root):
--   lune run tools/sim/traffic_replay.luau --minutes 10 --net typical --fps 60 --seed 1 --report build/sim/traffic.json
--   lune run tools/sim/traffic_replay.luau --help      every option
--   lune run tools/sim/traffic_replay.luau --list      scenarios, profiles, detectors with their thresholds
--
-- To add a scenario: a file tools/sim/scenarios/<name>.luau returning a lib/Replay.Scenario (copy
-- scenarios/sedan_wrap.luau); run it with --scenario <name>. To add a detector: a file
-- tools/sim/detectors/<name>.luau returning a lib/Detect.Def (copy detectors/jumps.luau); it is picked
-- up by every run. Neither needs a registry edit.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Detect = require("./lib/Detect")
local NetModel = require("./lib/NetModel")
local Replay = require("./lib/Replay")
local Report = require("./lib/Report")

local HELP = [[
lune run tools/sim/traffic_replay.luau [options]

what to run
  --scenario NAME        a file in tools/sim/scenarios (default: fleet, the game's 25 vehicles)
  --minutes N            simulated minutes (or --seconds N); default: the scenario's own
  --seed N               seed of the network and frame-time models (default 1)
  --traffic-seed N       seed of the fleet (default 7, the game's)
  --uptime-hours H       the server clock has already run this long (stamps are 32-bit floats)
  --warmup S             seconds at the start the detectors ignore (default 1)

the network (each send gets a delay or is lost)
  --net NAME             ideal | good | typical | wifi | mobile (default ideal)
  --latency-ms N         base one-way delay
  --jitter-ms N          extra delay per packet: exponential with this mean, capped at 5 x
  --loss P               probability a packet is lost (0.01 = 1 %)
  --burst-every S        mean seconds between bursts;  --burst-ms N  how long one lasts
  --burst-loss P         loss inside a burst;          --burst-delay-ms N  extra delay inside a burst
  --reorder P            probability a packet is held back;  --reorder-ms N  by how long
  --duplicate P          probability a packet arrives twice

frame times
  --server NAME          steady | live | strained (default steady: an exact 60 Hz Heartbeat)
  --client NAME          steady | live (default steady)
  --fps N                client frame rate (default 60)
  --hitch-every S        a client hitch every S seconds on average;  --hitch-ms N  its length
  --server-stall-every S a server stall every S seconds on average;  --server-stall-ms N  its length
  --net.KEY V  --server.KEY V  --client.KEY V     any single field of a profile (see --list)
  --clock-skew-ms N      the client clock's constant error;  --clock-drift-ppm N  its drift
  --phase F              where in a server frame the client's first frame falls, 0..1 (default 0.37)

detectors and output
  --detectors a,b        run only these (default: every file in tools/sim/detectors)
  --th DETECTOR.KEY=V    override a threshold (repeatable)
  --report PATH          write the JSON report (settings, statistics, thresholds, every incident)
  --top N                how many of the worst incidents to print (default 10)
  --trace FROM:TO        record every frame between two times (seconds); with
  --vehicle 1,5          only these vehicle ids; written to
  --trace-out PATH       a CSV (default build/sim/trace.csv)
  --check                exit 1 when the scenario's `expect` does not hold
  --quiet                print nothing but failures
  --list                 list scenarios, profiles and detectors, then exit
]]

local args = process.args
local opts: { [string]: any } = { netSet = {}, serverSet = {}, clientSet = {}, thresholds = {} }
local reportPath: string? = nil
local traceOut = "build/sim/trace.csv"
local top = 10
local check, quiet, list = false, false, false
local traceRange: string? = nil
local traceVehicles: { number }? = nil

local function fail(message: string): never
	print(`traffic_replay: {message}`)
	print("  (--help lists the options)")
	return process.exit(2)
end

local function numberOf(flag: string, value: string?): number
	local n = tonumber(value)
	if n == nil then
		fail(`{flag} needs a number, got {value}`)
	end
	return n :: number
end

local function listOf(value: string): { string }
	local out = {}
	for item in string.gmatch(value, "[^,]+") do
		table.insert(out, item)
	end
	return out
end

-- flags that set one number, scaled, into a place in opts
local SIMPLE: { [string]: { any } } = {
	["--seed"] = { opts, "seed", 1 },
	["--traffic-seed"] = { opts, "trafficSeed", 1 },
	["--seconds"] = { opts, "seconds", 1 },
	["--minutes"] = { opts, "seconds", 60 },
	["--uptime-hours"] = { opts, "uptime", 3600 },
	["--warmup"] = { opts, "warmup", 1 },
	["--phase"] = { opts, "phase", 1 },
	["--fps"] = { opts, "fps", 1 },
	["--clock-skew-ms"] = { opts, "clockSkew", 0.001 },
	["--clock-drift-ppm"] = { opts, "clockDrift", 1e-6 },
	["--max-per-kind"] = { opts, "maxPerKind", 1 },
	["--latency-ms"] = { opts.netSet, "latency", 0.001 },
	["--jitter-ms"] = { opts.netSet, "jitter", 0.001 },
	["--loss"] = { opts.netSet, "loss", 1 },
	["--burst-every"] = { opts.netSet, "burstEvery", 1 },
	["--burst-ms"] = { opts.netSet, "burstLength", 0.001 },
	["--burst-loss"] = { opts.netSet, "burstLoss", 1 },
	["--burst-delay-ms"] = { opts.netSet, "burstDelay", 0.001 },
	["--reorder"] = { opts.netSet, "reorder", 1 },
	["--reorder-ms"] = { opts.netSet, "reorderDelay", 0.001 },
	["--duplicate"] = { opts.netSet, "duplicate", 1 },
	["--hitch-every"] = { opts.clientSet, "stallEvery", 1 },
	["--server-stall-every"] = { opts.serverSet, "stallEvery", 1 },
}

local i = 1
while i <= #args do
	local a = args[i]
	local value = args[i + 1]
	local simple = SIMPLE[a]
	if a == "--help" or a == "-h" then
		print(HELP)
		process.exit(0)
	elseif a == "--list" then
		list = true
		i -= 1
	elseif a == "--check" then
		check = true
		i -= 1
	elseif a == "--quiet" then
		quiet = true
		i -= 1
	elseif simple then
		simple[1][simple[2]] = numberOf(a, value) * simple[3]
	elseif a == "--scenario" then
		opts.scenario = value
	elseif a == "--net" or a == "--server" or a == "--client" then
		opts[string.sub(a, 3)] = value
	elseif a == "--hitch-ms" then
		opts.clientSet.stallMin = numberOf(a, value) * 0.001
		opts.clientSet.stallMax = opts.clientSet.stallMin
	elseif a == "--server-stall-ms" then
		opts.serverSet.stallMin = numberOf(a, value) * 0.001
		opts.serverSet.stallMax = opts.serverSet.stallMin
	elseif string.match(a, "^%-%-net%.") or string.match(a, "^%-%-server%.") or string.match(a, "^%-%-client%.") then
		local kind, key = string.match(a, "^%-%-(%a+)%.(%a+)$")
		if not kind then
			fail(`cannot read {a}`)
		end
		opts[(kind :: string) .. "Set"][key :: string] = numberOf(a, value)
	elseif a == "--detectors" then
		opts.detectors = listOf(value or "")
	elseif a == "--th" then
		local key, v = string.match(value or "", "^([%w_]+%.[%w_]+)=(.+)$")
		if not key then
			fail(`--th needs DETECTOR.KEY=VALUE, got {value}`)
		end
		opts.thresholds[key :: string] = numberOf(a, v :: string)
	elseif a == "--report" then
		reportPath = value
	elseif a == "--top" then
		top = numberOf(a, value)
	elseif a == "--trace" then
		traceRange = value
	elseif a == "--vehicle" or a == "--vehicles" then
		traceVehicles = {}
		for _, item in listOf(value or "") do
			table.insert(traceVehicles :: { number }, numberOf(a, item))
		end
	elseif a == "--trace-out" then
		traceOut = value
	else
		fail(`unknown option {a}`)
	end
	i += 2
end

if list then
	print("scenarios (tools/sim/scenarios):")
	for _, name in Replay.scenarios() do
		local sc = Replay.scenario(name)
		print(string.format("  %-18s %s", name, sc.about))
	end
	local function profiles(title: string, set: { [string]: any })
		print(`\n{title}:`)
		local names = {}
		for name in set do
			table.insert(names, name)
		end
		table.sort(names)
		for _, name in names do
			local fields = {}
			for key, v in set[name] :: { [string]: number } do
				table.insert(fields, `{key}={v}`)
			end
			table.sort(fields)
			print(string.format("  %-9s %s", name, table.concat(fields, " ")))
		end
	end
	profiles("--net profiles (seconds, probabilities)", NetModel.NET)
	profiles("--server profiles", NetModel.SERVER)
	profiles("--client profiles", NetModel.CLIENT)
	print("\ndetectors (tools/sim/detectors), their kinds and thresholds (--th name.key=value):")
	for _, def in Detect.load() do
		print(`  {def.name}`)
		local kinds = {}
		for kind in def.kinds do
			table.insert(kinds, kind)
		end
		table.sort(kinds)
		for _, kind in kinds do
			print(string.format("    %-22s %s", kind, def.kinds[kind]))
		end
		for _, item in def.thresholds do
			print(
				string.format("    --th %s.%s=%s %s: %s", def.name, item.key, tostring(item.value), item.unit, item.why)
			)
		end
	end
	process.exit(0)
end

if traceRange then
	local from, to = string.match(traceRange, "^([%d%.]+):([%d%.]+)$")
	if not from then
		fail(`--trace needs FROM:TO in seconds, got {traceRange}`)
	end
	opts.trace = { from = tonumber(from) :: number, to = tonumber(to) :: number, vehicles = traceVehicles }
end

-- the command that repeats this run (without the output options), for the report and the trace hints
local repeatable = {}
do
	local skipOne = { ["--check"] = true, ["--quiet"] = true }
	local skipTwo = {
		["--report"] = true,
		["--top"] = true,
		["--trace"] = true,
		["--vehicle"] = true,
		["--vehicles"] = true,
		["--trace-out"] = true,
	}
	local j = 1
	while j <= #args do
		if skipOne[args[j]] then
			j += 1
		elseif skipTwo[args[j]] then
			j += 2
		else
			table.insert(repeatable, args[j])
			j += 1
		end
	end
end
local command = "lune run tools/sim/traffic_replay.luau " .. table.concat(repeatable, " ")

local started = os.clock()
local ok, result = pcall(Replay.run, opts)
if not ok then
	fail(tostring(result))
end
local elapsed = os.clock() - started

local function writeFile(path: string, contents: string)
	local dir = string.match(path, "^(.*)/[^/]+$")
	if dir and not fs.isDir(dir) then
		fs.writeDir(dir)
	end
	fs.writeFile(path, contents)
end

if not quiet then
	print(Report.summary(result, top, command))
	print(string.format("\n(%.1f s of computing for %.0f s of traffic)", elapsed, result.settings.seconds))
end
if reportPath then
	writeFile(reportPath, serde.encode("json", Report.json(result, command), true))
	if not quiet then
		print(`report: {reportPath} ({#result.incidents} incidents)`)
	end
end
if result.trace then
	writeFile(traceOut, Report.csv(result.trace))
	if not quiet then
		print(`trace: {traceOut} ({#result.trace} rows)`)
	end
end
if check then
	local failures = Replay.check(result)
	for _, f in failures do
		print(`CHECK FAILED  {f}`)
	end
	if #failures > 0 then
		process.exit(1)
	end
	if not quiet then
		print("check: the scenario's expectations hold")
	end
end
