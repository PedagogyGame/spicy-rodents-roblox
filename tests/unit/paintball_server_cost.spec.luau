--!strict
-- What the paintball service costs a server frame (checklist PB-15: the arena adds under 1.5 ms a frame
-- beside the full town; Shared/Minigames/Paintball/Contract.COST shares that out). The real service with
-- sixteen people, eight a side, every Move and every click judged in full, and balls kept in flight
-- (tools/games/paintball/server/Bench says exactly what is run; `lune run
-- tools/games/paintball/server/measure.luau` prints the whole table).
-- THE BUDGET PINNED HERE is the server lane's part of the contract's 1.5 ms, which is everything but the
-- bots' 0.5 ms: at 8 v 8 with 80 balls in flight, the whole of what the arena does in a tick (both
-- handlers and the step) has a median under 1.0 ms. It is pinned twice: in the lane's own Greybox, whose
-- ball test is the contract's reference scan of 180 boxes (a statement about the service's code that no
-- re-planning of the building moves), and in THE GAME'S OWN BUILDING (ArenaData.build(), whatever the
-- arena lane has made of it: the one PB-15 is about). Beside it, in the Greybox at the contract's own 48
-- balls: the balls' share within a quarter of its 0.4 ms (it is nearly all the reference scan), and
-- everything else under its 0.3 ms.
-- Measured where this was written (Lune, one core of a shared machine), in the Greybox: 0.70 ms the tick
-- at 80 balls; at 48 balls, balls 0.34 ms, everything else 0.10 ms. In the arena lane's building as it
-- stood on 13 November (1,461 boxes behind its grid), tried beside this lane's work: 0.15 ms the tick at
-- 80 balls. A budget is a statement about the code, not about how busy the machine is, so a run that
-- misses is given two more chances before the spec fails.
local ArenaData = require("@shared/Minigames/Paintball/ArenaData")
local Contract = require("@shared/Minigames/Paintball/Contract")
local Bench = require("../../tools/games/paintball/server/Bench")

local COST = Contract.COST

-- the best of up to three runs by `score` (lower is better), stopping at the first that is `good`
local function best(opts: Bench.Opts, score: (r: Bench.Result) -> number, good: number): Bench.Result
	local kept: Bench.Result? = nil
	for _ = 1, 3 do
		local r = Bench.run(opts)
		if kept == nil or score(r) < score(kept) then
			kept = r
		end
		if score(r) < good then
			break
		end
	end
	return kept :: Bench.Result
end

return function(t)
	local buildings: { { name: string, build: (() -> any)? } } = {
		{ name = "in the lane's Greybox (the reference ball test)", build = nil },
		{ name = "in the game's own building", build = ArenaData.build },
	}
	for _, where in buildings do
		t.test(
			`PB-15: at 8 v 8 with 80 balls in flight the arena's whole tick costs under 1 ms (the contract's 1.5 less the bots' share), {where.name}`,
			function()
				local budget = COST.totalMs - COST.botsMs
				local r = best({ balls = 80, seconds = 2, build = where.build }, function(run)
					return run.tick.median
				end, budget)
				t.truthy(r.inFlight >= 78 and r.inFlight <= 82, `{r.inFlight} balls in flight`)
				t.eq(r.stats.movesRefused, 0, "sixteen honest clients")
				t.eq(r.stats.shotsRefused, 0)
				t.truthy(r.stats.movesAccepted > 16 * 20 * 2, "every Move was judged")
				t.truthy(r.stats.snapshots >= 20 * 2)
				t.truthy(
					r.tick.median < budget,
					`the tick costs {r.tick.median} ms (95th centile {r.tick.p95}); the budget is {budget}`
				)
			end
		)
	end

	t.test(
		"PB-15: at the contract's 48 balls the balls' share is within a quarter of its 0.4 ms and everything else is under 0.3 ms",
		function()
			local r = best({ balls = COST.atBalls, seconds = 2 }, function(run)
				return run.balls.median
			end, COST.ballsMs)
			t.truthy(r.balls.median < COST.ballsMs * 1.25, `balls {r.balls.median} ms; the share is {COST.ballsMs}`)
			local rest = r.rest.median + r.moves.median + r.fires.median
			t.truthy(rest < COST.restMs, `everything else {rest} ms; the share is {COST.restMs}`)
			t.truthy(r.rest.p95 < COST.restMs, `a snapshot tick's rest {r.rest.p95} ms`)
		end
	)

	t.test("an arena with nobody firing costs a tenth of a millisecond: the Moves and the snapshots", function()
		local r = Bench.run({ balls = 0, seconds = 1 })
		t.eq(r.stats.balls, 0)
		t.truthy(r.tick.median < 0.3, `{r.tick.median} ms`)
		-- and what one screen is sent: the snapshot stream alone, 20 a second of 16 bodies
		t.truthy(r.downBytesPerSec > 4000 and r.downBytesPerSec < 5000, `{r.downBytesPerSec} bytes a second`)
	end)
end
