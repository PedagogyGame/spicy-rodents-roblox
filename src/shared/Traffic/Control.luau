--!strict
-- ReplicatedStorage.Shared.Traffic.Control
-- Traffic control at the existing sign sites and the stop-line FSM (BUILD_PLAN §3.6, §4.4 W1 #9; A2).
-- Interface: DEFAULT (control data); resolve(control, lanes) -> { [laneId] = { StopLine } };
--            step(state, lines, s, dir, speed, decel, dt, clear, roll) -> cap, event?
--
-- v5.4 has no junction control (traffic.md §3, §4): the two stop signs at (324, 31) and (371, -34) around
-- the x = 347 boulevard crossing are decorative. Under drive-on-the-right (owner decision 9) each sign sits
-- on the kerb of exactly one approach: (324, 31) faces eastbound traffic (z > 0 after unify) and
-- (371, -34) faces westbound traffic (z < 0), so the existing sites become a two-way stop on the
-- boulevard; the stop lines sit just outside the zebra crossings at x = 325 and x = 369 (traffic.md §4).
-- The full `town/traffic_control.json` (signals with phases, speed limits, parking) is authored data that
-- lands with TrafficLaw (W4); `DEFAULT` has its shape and these two sites, and a data file replaces it.
--
-- FSM per vehicle (`State`): free -> braking (a braking-profile speed cap to the line) -> waiting
-- (stopped `stopSecs`, then until the junction box is clear) -> go (until the line is behind) -> free.
-- A rolling stop (A2 violation; `violationRates.rollingStop`) skips waiting at half speed and emits
-- "rollingStop" as it crosses the line. Lengths and speeds in studs.

local LaneMath = require("./LaneMath")
local Units = require("../Config/Units")

local st = Units.st

export type StopLineData = { lane: string, x: number?, z: number?, dir: number? }
export type Junction = {
	id: string,
	at: { number },
	radius: number,
	control: string,
	stopLines: { StopLineData },
	src: string?,
}
export type ControlData = {
	junctions: { Junction },
	violationRates: { rollingStop: number },
	stopSecs: number,
}
export type StopLine = { s: number, dir: number, junction: string, at: { number }, radius: number }
export type State = { phase: string, line: StopLine?, timer: number }

local Control = {}

-- stylua: ignore
Control.DEFAULT = {
	junctions = {
		{
			id = "j_blvd_347", at = { st(347), 0 }, radius = st(13), control = "stop2",
			src = "traffic.md §4: stop signs (324, 31) and (371, -34) (L3261-3262), zebras x = 325 and 369",
			stopLines = {
				{ lane = "blvd_eastbound", x = st(322) },
				{ lane = "blvd_westbound", x = st(372) },
				{ lane = "patrol_beat", x = st(322), dir = 1 },
				{ lane = "patrol_beat", x = st(372), dir = -1 },
			},
		},
	},
	violationRates = { rollingStop = 0.08 }, -- §3.6 traffic_control.json violationRates
	stopSecs = 1.2,
} :: ControlData

-- resolve(control, lanes): stop lines as arc distances on their lanes (both directions of a ping-pong
-- lane carry their own line).
function Control.resolve(control: ControlData, lanes: { [string]: LaneMath.Lane }): { [string]: { StopLine } }
	local out: { [string]: { StopLine } } = {}
	for _, j in control.junctions do
		for _, sl in j.stopLines do
			local lane = lanes[sl.lane]
			if lane then
				local dir = sl.dir or (if lane.dir == 0 then 1 else lane.dir)
				local probe = LaneMath.pointAt(lane, 0, dir)
				local x = sl.x or probe.x
				local z = sl.z or probe.z
				local s = LaneMath.arcOf(lane, x, z, dir)
				local list = out[sl.lane] or {}
				table.insert(list, { s = s, dir = dir, junction = j.id, at = j.at, radius = j.radius })
				out[sl.lane] = list
			end
		end
	end
	for _, list in out do
		table.sort(list, function(a, b)
			return a.s < b.s
		end)
	end
	return out
end

function Control.newState(): State
	return { phase = "free", line = nil, timer = 0 }
end

-- The next line ahead in the travel direction within `look` studs.
local function nextLine(lines: { StopLine }?, s: number, dir: number, look: number): (StopLine?, number)
	if not lines then
		return nil, math.huge
	end
	local best, gap = nil, math.huge
	for _, l in lines do
		if l.dir == dir then
			local g = l.s - s
			if g > -0.01 and g < look and g < gap then
				best, gap = l, g
			end
		end
	end
	return best, gap
end

-- step: the speed cap the stop control imposes this tick, and an event ("stopped", "rollingStop", "go").
-- `clear` says whether the junction box is free of other moving vehicles and people (caller's test);
-- `roll` is a 0-1 draw used once per approach for the rolling-stop violation.
function Control.step(
	state: State,
	lines: { StopLine }?,
	s: number,
	dir: number,
	speed: number,
	decel: number,
	dt: number,
	clear: boolean,
	roll: number,
	rates: { rollingStop: number }?
): (number, string?)
	local look = math.max(st(4), speed * speed / (2 * decel) + st(4))
	if state.phase == "free" then
		local line, gap = nextLine(lines, s, dir, look)
		if not line then
			return math.huge, nil
		end
		state.line = line
		if roll < ((rates and rates.rollingStop) or 0) then
			state.phase = "rolling"
		else
			state.phase = "braking"
		end
		if gap < 0 then
			state.phase, state.line = "free", nil
			return math.huge, nil
		end
	end
	local line = state.line :: StopLine
	local gap = line.s - s
	if gap > look + st(40) or (gap < -st(1) and state.phase ~= "rolling") then
		state.phase, state.line = "free", nil -- wrapped, reversed or already past: re-arm
		return math.huge, nil
	end
	if state.phase == "rolling" then
		if gap <= 0 then
			state.phase, state.line = "free", nil
			return math.huge, "rollingStop"
		end
		return math.max(speed * 0.5, st(1.5)), nil
	elseif state.phase == "braking" then
		if gap <= st(0.4) or (gap <= st(1.2) and speed < st(0.3)) then
			state.phase, state.timer = "waiting", 0
			return 0, "stopped"
		end
		return math.sqrt(2 * decel * math.max(0, gap - st(0.3))), nil
	elseif state.phase == "waiting" then
		state.timer += dt
		if state.timer >= Control.DEFAULT.stopSecs and clear then
			state.phase = "go"
			return math.huge, "go"
		end
		return 0, nil
	end
	-- "go": through the junction; re-armed once the line is behind (above)
	return math.huge, nil
end

return Control
