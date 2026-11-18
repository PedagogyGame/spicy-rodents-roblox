--!strict
-- tools/games/paintball/client/feel.luau: the paintball feel sheet, for the playtest. For one feel table (the
-- match's: Contract.FEEL with any numbers given on the command line, held to their ranges exactly as the
-- service's debug("tune", key, value) holds them) it prints what the hands will meet, worked out from the same
-- shared modules the client and the server run: how long a ball takes and how far it drops at each range, how
-- far to lead a walker and a sprinter, the rhythm of the magazine (measured by running the client's own seat
-- with a trigger mashed at several rates), what a sprint costs before the first ball, how long a peek over a
-- rail lasts, and the client's own tuning table beside it. Nothing is written.
-- Usage, from the repo root: lune run tools/games/paintball/client/feel.luau [key=value ...]
--   for example: lune run tools/games/paintball/client/feel.luau ballSpeed=140 reloadSecs=1.2
-- Interface: a script (prints a report)

local process = require("@lune/process")
local Ballistics = require("../../../../src/shared/Paintball/Ballistics")
local Arena = require("../../../../src/shared/Minigames/Paintball/Arena")
local Body = require("../../../../src/shared/Minigames/Paintball/Body")
local Contract = require("../../../../src/shared/Minigames/Paintball/Contract")
local SeatCore = require("../../../../src/client/Minigames/Paintball/SeatCore")
local ShowCore = require("../../../../src/client/Minigames/Paintball/ShowCore")
local Tuning = require("../../../../src/client/Minigames/Paintball/Tuning")
local Wire = require("../../../../src/shared/Minigames/Paintball/Wire")

local over: { [string]: number } = {}
for _, arg in process.args do
	local key, value = string.match(arg, "^(%w+)=([%d%.%-]+)$")
	if key and tonumber(value) then
		local ok, why = Contract.tuned(Contract.feel(), key, tonumber(value))
		if ok == nil then
			print(`ignored {arg}: {why}`)
		else
			over[key] = tonumber(value) :: number
		end
	else
		print(`ignored {arg}: write key=value`)
	end
end
local feel = Contract.feel(over)

local function f(v: number, places: number?): string
	return string.format(`%.{places or 2}f`, v)
end

print("PAINTBALL FEEL SHEET")
print("the match's feel (Contract.FEEL; turn one with the service's debug(\"tune\", key, value)):")
for _, key in Contract.FEEL_KEYS do
	local range = Contract.FEEL_RANGE[key]
	local value = (feel :: any)[key] :: number
	local mark = if over[key] ~= nil then "  <- given" else ""
	print(`  {key} = {value}   (may be {range[1]} to {range[2]}){mark}`)
end

print("")
print("THE BALL  (level shot from a standing eye; lead = how far a target moves while it flies)")
print("  range   flight    drop   lead a walker   lead a sprinter   still in the air?")
for _, range in { 15, 30, 45, 60, 90, 120 } do
	local t = range / feel.ballSpeed
	local _, y = Ballistics.position(0, 0, 0, 0, 0, -feel.ballSpeed, feel.ballDrop, t)
	local alive = if t <= Contract.Rules.ballTtl
		then "yes"
		else "NO: gone at " .. f(Contract.Rules.ballTtl * feel.ballSpeed, 0)
	print(
		`  {string.format("%4d", range)}   {f(t)} s   {f(-y)}   {f(Body.WALK * t)} studs      {f(
			Body.speed(0, true, feel) * t
		)} studs        {alive}`
	)
end
local railClear = math.sqrt(2 * (Body.STAND_EYE - Arena.RAIL_HEIGHT) / math.max(feel.ballDrop, 1e-6)) * feel.ballSpeed
print(`  a level ball from a standing eye drops to rail height ({Arena.RAIL_HEIGHT}) after {f(railClear, 0)} studs`)

-- The client's own seat, mashed: how many balls a second really leave at each clicking rate.
local function mash(clicksPerSecond: number, seconds: number): (number, number)
	local frames = 0
	local function now(): number
		return 1000 + frames / 60
	end
	local arena = Arena.finish({
		boxes = { -60, -1, -60, 60, 0, 60 },
		kinds = { Arena.KIND.slab },
		ramps = {},
		spawns = { {}, {} },
		spawnRooms = {},
		curtains = { {}, {} },
		exits = {},
		lobby = { x = 0, y = 0, z = 0, yaw = 0 },
		nodes = {},
		links = {},
		cover = {},
	})
	local show = ShowCore.new({ arena = arena, now = now })
	local fired: { number } = {}
	local ctx: any = {
		send = function() end,
		camera = function() end,
		releaseCamera = function() end,
		controls = function() end,
		pace = function() end,
		setButtons = function() end,
		toast = function() end,
		sound = function(): boolean
			return false
		end,
	}
	local seat = SeatCore.new(ctx, {
		now = now,
		arena = arena,
		show = function(): ShowCore.Show?
			return show
		end,
		link = {
			send = function(remote: string)
				if remote == "Paintball.Fire" then
					table.insert(fired, now())
				end
			end,
			listen = function(): () -> ()
				return function() end
			end,
		},
		port = {
			pose = function(): (number?, number, number, number, number, number, boolean)
				return 0, 0, 0, 0, 0, -1, false
			end,
		},
	})
	seat:onState({
		you = 1,
		feel = feel,
		view = {
			phase = "playing",
			seats = {},
			game = {
				phase = "live",
				endsAt = now() + 1e6,
				scores = { 0, 0 },
				slots = { { id = 1, team = 1, on = true, tags = 0, outs = 0, shots = 0, hits = 0 } },
			},
		},
	})
	seat:onMessage({ kind = "paintball_respawn", id = 1, x = 0, y = 0, z = 0, yaw = 0, at = now() - 1, place = 1 }, nil)
	local every = 60 / clicksPerSecond
	local next = 0
	for frame = 0, math.floor(seconds * 60) - 1 do
		if frame >= next then
			next += every
			seat:input("fire", true)
			seat:input("fire", false)
		end
		frames += 1
		show:step(1 / 60)
		seat:step(1 / 60)
	end
	local first = 0
	for _, at in fired do
		if at < 1001 then
			first += 1
		end
	end
	return #fired / seconds, first
end

print("")
print("THE MARKER  (the client's own seat with the trigger mashed for 20 s)")
print(
	`  five balls {feel.fireInterval} s apart, then {feel.reloadSecs} s of reload: a full cycle is {f(
		4 * feel.fireInterval + feel.reloadSecs
	)} s`
)
print("  clicks a second   balls in the first second   balls a second over 20 s")
for _, rate in { 2, 4, 6, 10 } do
	local perSecond, first = mash(rate, 20)
	print(`  {string.format("%8d", rate)}          {first}                         {f(perSecond)}`)
end
print(`  a click up to {Contract.MARGIN.click} s early is held and leaves the instant the marker allows`)

print("")
print("SPRINT AND CROUCH")
print(
	`  walk {Body.WALK} studs/s; sprint {f(Body.speed(0, true, feel), 1)} after {Body.SPRINT_RAMP_SECS} s of ramp; crouched {Body.CROUCH_SPEED}`
)
print(
	`  THE COST OF A SPRINT: the marker is down; a click ends the sprint and the ball leaves {Body.SPRINT_FIRE_DELAY} s later ({f(
		Body.speed(0, true, feel) * Body.SPRINT_FIRE_DELAY,
		1
	)} studs further on); steps are heard at volume {Tuning.stepLoud} against {Tuning.stepQuiet} walking and 0 crouched`
)
print(
	`  with Shift held through the click the sprint picks up {Tuning.sprintAfterShot} s after the ball and is at full pace {f(
		Body.SPRINT_FIRE_DELAY + Tuning.sprintAfterShot + Body.SPRINT_RAMP_SECS
	)} s after the click`
)
print(
	`  crouch: the eye goes from {Body.STAND_EYE} to {f(Body.CROUCH_EYE, 1)} in {feel.crouchSecs} s; a rail is {Arena.RAIL_HEIGHT}: a peek up and back down is {f(
		2 * feel.crouchSecs
	)} s`
)
local c = 0
local t = 0
while Body.eye(c) > Arena.RAIL_HEIGHT do
	c = Body.crouchStep(c, true, 1 / 240, feel)
	t += 1 / 240
end
print(`  the eye is under the rail {f(t)} s after the key goes down; the hit shape's top is under it too`)
print(`  tagged out for {feel.respawnSecs} s, then {feel.protectSecs} s protected (cannot be hit, cannot fire)`)

print("")
print("THE WIRE  (what the feel does to the traffic: Wire.budget(16), bytes a second)")
local budget = Wire.budget(16)
print(
	`  down {f(budget.down, 0)}   up {f(budget.up, 0)}   (at the DEFAULT feel: the budget is not re-costed for a tuned one)`
)

print("")
print("THE CLIENT'S OWN TUNING  (src/client/Minigames/Paintball/Tuning.luau: each number has its comment there)")
local keys: { string } = {}
for key, value in Tuning :: { [string]: any } do
	if type(value) == "number" or type(value) == "boolean" then
		table.insert(keys, key)
	end
end
table.sort(keys)
local line = "  "
for _, key in keys do
	local item = `{key}={tostring((Tuning :: any)[key])}  `
	if #line + #item > 110 then
		print(line)
		line = "  "
	end
	line ..= item
end
print(line)
