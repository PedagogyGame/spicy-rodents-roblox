--!strict
-- tools/games/air_hockey/netcode.luau: how far what an air hockey player is shown is from what the server
-- decided, measured. Whole matches are played over a made-up network (tools/games/air_hockey/Line: the real
-- referee, the real Seats and Replicas, every message delivered late) at 0, 80 and 150 ms each way, against the
-- computer and between two people, and the distances are printed in millimetres on the 2.34 m bed.
-- Run: lune run tools/games/air_hockey/netcode.luau [seconds of play per case, default 90]
local process = require("@lune/process")
local Seat = require("../../../src/shared/Minigames/AirHockey/Seat")
local Sim = require("../../../src/shared/Minigames/AirHockey/Sim")
local Line = require("./Line")

local seconds = tonumber(process.args[1]) or 90

local function mm(v: number): string
	return string.format("%7.1f", v * 1000)
end

local function row(label: string, e: any)
	print(
		string.format(
			"  %-34s near half %s /%s /%s   far half %s /%s /%s   own mallet %s   far mallet %s /%s   corrections %d",
			label,
			mm(e.near.mean),
			mm(e.near.p95),
			mm(e.near.max),
			mm(e.far.mean),
			mm(e.far.p95),
			mm(e.far.max),
			mm(e.own.max),
			mm(e.other.mean),
			mm(e.other.p95),
			e.resims
		)
	)
end

print(`air hockey netcode: {seconds} s of play per case; distances in mm (mean / 95th / worst), ease {Seat.EASE} s`)
print("against the computer (hard), the player at the Glacier end:")
for _, ms in { 0, 80, 150 } do
	local frames = math.floor(ms / 1000 * 60 + 0.5)
	local line = Line.new({
		humans = { [0] = true, [1] = false },
		lag = { [0] = frames, [1] = frames },
		hands = { [0] = Line.hands.chaser(1) },
		difficulty = Sim.DIFFICULTY.hard,
	})
	Line.run(line, seconds)
	row(`{ms} ms each way`, Line.errors(line, 0))
end
print("two people (each line: one player's screen):")
for _, ms in { 0, 80, 150 } do
	local frames = math.floor(ms / 1000 * 60 + 0.5)
	local line = Line.new({
		humans = { [0] = true, [1] = true },
		lag = { [0] = frames, [1] = frames },
		hands = { [0] = Line.hands.chaser(1), [1] = Line.hands.chaser(2) },
	})
	Line.run(line, seconds)
	for side = 0, 1 do
		row(`{ms} ms each way, {if side == 0 then "Glacier" else "Ember"}`, Line.errors(line, side))
	end
	print(
		`    referee: {line.ref.n} ticks, {line.ref.sim.hitSerial} contacts, {line.ref.sim.score0}-{line.ref.sim.score1}, {line.ref.cuts} ticks played without a late hand, {#line.refused} refusals`
	)
end
