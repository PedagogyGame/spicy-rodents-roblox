--!strict
-- tools/games/paintball/server/measure.luau: print what the paintball service costs a server frame at
-- 8 v 8 (checklist PB-15), beside the shares the contract gives it (Shared/Minigames/Paintball/Contract.COST).
-- Bench (beside this file) says what is run and how. Each line is a count of balls kept in flight.
-- Usage, from the repo root: lune run tools/games/paintball/server/measure.luau [seconds per line, default 6]
-- Interface: a script (prints a report); nothing is written.
local process = require("@lune/process")
local Contract = require("@shared/Minigames/Paintball/Contract")
local Bench = require("./Bench")

local seconds = tonumber(process.args[1]) or 6
local COST = Contract.COST

local function ms(v: number): string
	return string.format("%.3f", v)
end

print("Paintball service, 16 people (8 v 8) in the stand-in building, ms per 60 Hz tick: median (95th centile)")
print(`Contract.COST: balls {COST.ballsMs} at {COST.atBalls} in flight, rest {COST.restMs}, total {COST.totalMs}`)
print("(the bots' share, " .. COST.botsMs .. " ms, is the match-and-bots lane's: there are none in this run)")
for _, balls in { 0, COST.atBalls, 80, 120 } do
	local r = Bench.run({ balls = balls, seconds = seconds })
	local counted = Bench.run({ balls = balls, seconds = math.min(seconds, 2), countSweeps = true })
	print(
		string.format(
			"%3d balls (%.0f in flight, %.0f shots/s): balls %s (%s)  rest %s (%s)  step %s (%s)  moves %s  clicks %s  the whole tick %s (%s)",
			balls,
			r.inFlight,
			r.shotsPerSec,
			ms(r.balls.median),
			ms(r.balls.p95),
			ms(r.rest.median),
			ms(r.rest.p95),
			ms(r.step.median),
			ms(r.step.p95),
			ms(r.moves.median),
			ms(r.fires.median),
			ms(r.tick.median),
			ms(r.tick.p95)
		)
	)
	print(
		string.format(
			"          of which the building's own ball test (the reference scan of %d boxes): %.0f calls, %s ms a tick; down to one screen %.1f kB/s",
			#require("@shared/Minigames/Paintball/ArenaData").build().boxes // 6,
			counted.sweepsPerTick,
			ms(counted.sweepMs),
			r.downBytesPerSec / 1000
		)
	)
end
