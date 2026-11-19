--!strict
-- The duel's pounce stays a move the live validator accepts (brief v2 §8 wind-up; the owner's rule that honest play is
-- never snapped): the rodent's controller holds the motor's pounce back for pounce.windup after the click
-- (Controllers/Squirrel.windup) and then pounces exactly as before. On the rig (tests/lib/LiveRig: the client's motor,
-- a real link, the server's MovementService with enforcement on), a rodent clicking as fast as the duel lets it, with
-- feints' pauses and zig-zags between, across the town for a minute: 0 snaps, and the pounces really happen. (This
-- found the envelope snapping a ground pounce seen only by a late packet: SquirrelMotor's vertical check now allows a
-- launch off the ground inside the gap.) The server sees each pounce's launch (MovementService:motorOf's pounceAt,
-- which Combat/CombatService ties the bite to) when the click said, give or take the link's jitter (not through a
-- burst of packets held up or lost: a pounce in one does not bite).
local Tunables = require("@shared/Config/Tunables")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local Squirrel = require("@client/Controllers/Squirrel")
local Rng = require("@tests/cheat/Rng")
local LiveRig = require("@tests/lib/LiveRig")

type State = SquirrelMotor.State

return function(t)
	local town = LiveRig.town()

	for _, c in
		{
			{
				name = "80 ms, 150 ms jitter, 2 % loss",
				link = { latency = 0.08, jitter = 0.15, loss = 0.02 },
				seed = 11,
			},
			{
				name = "a slow phone at 300 ms",
				link = { latency = 0.3, jitter = 0.1, loss = 0.02 },
				fps = 20,
				seed = 12,
			},
			{
				name = "held-up bursts: 0.6 s every 4 s",
				link = { latency = 0.12, jitter = 0.1, loss = 0.02, holdEvery = 4, holdFor = 0.6 },
				seed = 13,
			},
			{
				name = "lost bursts: 0.8 s every 5 s",
				link = { latency = 0.12, jitter = 0.1, loss = 0.02, dropEvery = 5, dropFor = 0.8 },
				seed = 14,
			},
		}
	do
		t.test(`the duel's pounces, zig-zags and feint pauses on the open ground: {c.name}: 0 snaps`, function()
			local rng = Rng.new(c.seed)
			local rig = LiveRig.new({
				world = town.world,
				vworld = town.vworld,
				link = c.link :: any,
				fps = c.fps,
				seed = c.seed,
			})
			local windup = Tunables.get("pounce.windup")
			local pending: number? = nil
			local pounces, clicks = 0, 0
			local weave, weaveAt = 1, 0
			local clickTimes: { number } = {}
			local seenLaunches: { number } = {}
			local lastSeen: number? = nil
			local heading = rng.next() * math.pi * 2
			rig:possess(town.startAt(rng), function(tt: number, state: State, events: { any }): SquirrelMotor.Input
				for _, e in events do
					if e.kind == "pounce" then
						pounces += 1
					end
				end
				for _, sq in (rig.movement :: any).squirrels do
					local at = sq.pounceAt
					if at ~= nil and at ~= lastSeen then
						lastSeen = at
						table.insert(seenLaunches, at)
					end
				end
				local input = SquirrelMotor.idleInput(heading + math.pi)
				if state.routeId ~= nil then
					-- off whatever it landed on: drop to the ground and carry on
					input.drop = true
					return input
				end
				if tt >= weaveAt then
					weave = -weave
					weaveAt = tt + 0.25 + rng.next() * 0.2
					if rng.next() < 0.1 then
						heading = rng.next() * math.pi * 2
					end
				end
				input.fw = 1
				input.side = weave
				input.sprint = (tt % 6) < 2.5 -- (Shift held for a burst, then let go: as a player does)
				-- a click every frame it is allowed, but now and then a pause (a feint has no pounce)
				local pressed = (tt % 3) < 2.2
				local now, pend, tell = Squirrel.windup(pending, tt, pressed, windup, state.cooldown <= 0)
				pending = pend
				if tell then
					clicks += 1
					table.insert(clickTimes, tt)
				end
				input.pounce = now
				return input
			end)
			rig:run(60)
			local r = rig:result()
			print(`      {LiveRig.describe(c.name, r)}; {clicks} clicks, {pounces} pounces`)
			for _, v in r.violations do
				print(`      VIOLATION {v}`)
			end
			-- each launch the server saw, against the click before it: the link's one way, give or take its jitter
			local P = require("@shared/Combat/CombatRules").params()
			local worst, tied = 0, 0
			for _, at in seenLaunches do
				local click: number? = nil
				for _, ct in clickTimes do
					if ct <= at then
						click = ct
					end
				end
				if click then
					local off = at - (click :: number) - windup - (c.link :: any).latency
					worst = math.max(worst, math.abs(off))
					if math.abs(off) <= P.rewind + P.launchSlack then
						tied += 1
					end
				end
			end
			print(
				`      the server saw {#seenLaunches} launches; {tied} within {P.rewind + P.launchSlack} s of the click's (worst {string.format(
					"%.3f",
					worst
				)} s)`
			)
			-- (a burst held up or lost hides a pounce's launch, or shows it late: no bite on it, as no bite on a lag spike)
			local bursts = (c.link :: any).holdEvery ~= nil or (c.link :: any).dropEvery ~= nil
			if not bursts then
				t.truthy(#seenLaunches >= pounces - 3, "the server saw every pounce's launch")
				t.truthy(tied >= #seenLaunches - 3, "and each when the click said")
			end
			t.eq(r.snaps, 0, "snaps")
			t.truthy(pounces >= 40, `the pounces happened ({pounces})`)
			t.truthy(pounces >= clicks - 2, "every click became a pounce after the wind-up")
		end)
	end
end
