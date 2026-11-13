--!strict
-- tools/games/air_hockey/netcode.luau: how far what an air hockey player is shown is from what the server
-- decided, measured. Whole matches are played over a made-up network (tools/games/air_hockey/Line: the real
-- referee, the real Seats and Replicas, every message delivered late) at 0, 80 and 150 ms each way, against the
-- computer and between two people, and the distances are printed in millimetres on the 2.34 m bed. Between two
-- people the far end is drawn a moment ago (Shared/Minigames/AirHockey/Seat): the lines say how far the puck and
-- the far mallet drawn are from the referee's of the same instant, and from the referee's of the moment each
-- was drawn at, how late that moment was, and how smoothly they moved from frame to frame.
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
for _, ms in { 0, 40, 80, 150 } do
	local frames = math.floor(ms / 1000 * 60 + 0.5)
	local line = Line.new({
		humans = { [0] = true, [1] = true },
		lag = { [0] = frames, [1] = frames },
		hands = { [0] = Line.hands.chaser(1), [1] = Line.hands.chaser(2) },
	})
	Line.run(line, seconds)
	for side = 0, 1 do
		row(`{ms} ms each way, {if side == 0 then "Glacier" else "Ember"}`, Line.errors(line, side))
		local sm = Line.smooth(line, side)
		print(
			string.format(
				"      drawn puck faster than the table allows on %d of %d frames (fastest %.1f m/s), half a metre or more in one frame on %d (%d goals put it back on its spot; the rest are a puck hurried to the present); far mallet faster than a hand on %d (fastest %.1f m/s)",
				sm.puckOver,
				sm.frames,
				sm.puckMax,
				sm.jumps,
				#line.goals,
				sm.malletOver,
				sm.malletMax
			)
		)
		local f = Line.feel(line, side)
		print(
			string.format(
				"      the puck's moment: more than 1.5 times the table's top speed on %d frames, more than twice on %d (furthest in one frame %.2f m); under 60 %% of the clock on %.1f %% of the frames it was moving (longest %.0f ms), stopped on %d; coming to this player in their half it is the present puck on %.1f %% of frames; at this mallet's %d strikes it was %.0f ms late on average (95th %.0f, worst %.0f)",
				f.over15,
				f.over2,
				f.maxStep,
				f.crawl / math.max(f.moving, 1) * 100,
				f.longestCrawl * 1000,
				f.stopped,
				f.incomingLive / math.max(f.incoming, 1) * 100,
				f.strikes.n,
				f.strikes.mean * 1000,
				f.strikes.p95 * 1000,
				f.strikes.max * 1000
			)
		)
		local e = Line.errors(line, side)
		print(
			string.format(
				"      against the moment drawn: puck %s /%s /%s mm, drawn %3.0f ms late on average (95th %3.0f), in the player's own half it is the present puck on %4.1f%% of frames; far mallet %s /%s /%s mm, %3.0f ms late (95th %3.0f)",
				mm(e.puckShown.mean),
				mm(e.puckShown.p95),
				mm(e.puckShown.max),
				e.puckLate.mean * 1000,
				e.puckLate.p95 * 1000,
				e.nearLive * 100,
				mm(e.farShown.mean),
				mm(e.farShown.p95),
				mm(e.farShown.max),
				e.farLate.mean * 1000,
				e.farLate.p95 * 1000
			)
		)
	end
	print(
		`    referee: {line.ref.n} ticks, {line.ref.sim.hitSerial} contacts, {line.ref.sim.score0}-{line.ref.sim.score1}, {line.ref.cuts} ticks played without a late hand, {#line.refused} refusals`
	)
end
