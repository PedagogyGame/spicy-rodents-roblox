--!strict
-- Minigames/Pool/EightBall: the eight-ball rules, line by line against the checklist (POOL-R1 .. POOL-R7), and
-- the inputs a player gives (place, call, shoot) driving the real table model.
local Cue = require("@shared/Minigames/Pool/Cue")
local EightBall = require("@shared/Minigames/Pool/EightBall")
local Minigame = require("@shared/Minigames/Minigame")
local Shot = require("@shared/Minigames/Pool/Shot")
local Tables = require("@shared/Minigames/Pool/Tables")

return function(t)
	local pool = Tables.eightBall()

	local function pot(ball: number, hole: number?): EightBall.PotAt
		return { ball = ball, hole = hole or 1 }
	end
	local function shot(firstHit: number, pots: { EightBall.PotAt }?, rail: boolean?): EightBall.Outcome
		return { firstHit = firstHit, pots = pots or {}, railAfter = rail ~= false }
	end
	local function hasSpot(s: EightBall.State, id: number): boolean
		for _, sp in s.spots do
			if sp.id == id then
				return true
			end
		end
		return false
	end
	-- a game in which seat 1 has broken dry, seat 2 has taken solids and cleared them, and is on the 8
	local function onTheEight(): EightBall.State
		local s = EightBall.init(2, 1)
		EightBall.apply(s, shot(1))
		EightBall.apply(s, shot(1, { pot(1) }))
		EightBall.apply(s, shot(2, { pot(2), pot(3), pot(4), pot(5), pot(6), pot(7) }))
		return s
	end

	t.test("contract: a Minigame.Rules module, two seats, no money; a fresh game is racked for the break", function()
		t.truthy(Minigame.check(EightBall))
		t.eq(EightBall.def.game, "pool")
		t.eq(EightBall.def.seats, 2)
		t.eq(EightBall.def.money, "none")
		t.eq(EightBall.def.authority, "server")
		t.truthy(EightBall.verbs.place and EightBall.verbs.call and EightBall.verbs.shoot)
		t.eq(EightBall.groupOf(3), "solids")
		t.eq(EightBall.groupOf(12), "stripes")
		t.eq(EightBall.groupOf(8), "eight")
		t.eq(EightBall.groupOf(0), "cue")
		local g = Minigame.start(EightBall :: any, 2, 5)
		local s = g.state :: EightBall.State
		t.eq(#s.spots, 16)
		t.eq(EightBall.turn(s), 1)
		t.eq(s.inHand, "kitchen", "the break is from behind the head string")
		t.falsy(s.broken)
		t.eq(EightBall.result(s), nil)
		t.eq(#EightBall.legal(s, 1), 15, "anything may be hit on the break")
		t.eq(EightBall.turn(EightBall.init(2, 5, 2)), 2, "the winner breaks next: the framework names the breaker")
		t.falsy(Minigame.input(g, 1, "roll", {}), "not a pool verb")
		t.falsy(Minigame.input(g, 3, "shoot", { 0, 1 }), "no such seat")
	end)

	t.test("POOL-R1 any break keeps the table open; a pot on the break keeps the shooter on", function()
		local s = EightBall.init(2, 1)
		t.eq(EightBall.apply(s, shot(1, { pot(3), pot(12) })), "continue")
		t.eq(s.group[1], nil, "open after the break, whatever went down")
		t.eq(s.group[2], nil)
		t.eq(s.seat, 1)
		t.falsy(s.onTable[3])
		t.falsy(hasSpot(s, 3))
		t.eq(s.inHand, "none")
		t.truthy(s.broken)
		local dry = EightBall.init(2, 1)
		t.eq(EightBall.apply(dry, shot(1)), "pass", "a dry break passes the table")
		t.eq(dry.seat, 2)
		t.eq(dry.inHand, "none")
		-- a soft break that reaches no cushion is still a break, not a foul
		local softBreak = EightBall.init(2, 1)
		t.eq(EightBall.apply(softBreak, shot(1, {}, false)), "pass")
	end)

	t.test("POOL-R1 the first legal pot after the break gives solids or stripes", function()
		local s = EightBall.init(2, 1)
		EightBall.apply(s, shot(1))
		t.eq(#EightBall.legal(s, 2), 14, "open table: anything but the 8")
		t.eq(EightBall.apply(s, shot(11, { pot(11) })), "continue")
		t.eq(s.group[2], "stripes")
		t.eq(s.group[1], "solids")
		t.eq(EightBall.left(s, 2), 6)
		t.eq(EightBall.left(s, 1), 7)
		t.deepEq(EightBall.legal(s, 2), { 9, 10, 12, 13, 14, 15 })
		-- a foul pot does not give a group
		local f = EightBall.init(2, 1)
		EightBall.apply(f, shot(1))
		t.eq(EightBall.apply(f, shot(2, { pot(2), pot(0) })), "foul")
		t.eq(f.group[2], nil)
		t.falsy(f.onTable[2], "the ball stays down all the same")
	end)

	t.test("POOL-R1 a legal pot of your own ball keeps the turn; a miss or the other group's ball passes it", function()
		local s = EightBall.init(2, 1)
		EightBall.apply(s, shot(1))
		EightBall.apply(s, shot(11, { pot(11) }))
		t.eq(EightBall.apply(s, shot(12, { pot(12) })), "continue")
		t.eq(s.seat, 2)
		t.eq(s.run[2], 2)
		t.eq(EightBall.apply(s, shot(13)), "pass")
		t.eq(s.seat, 1)
		t.eq(s.run[2], 0)
		t.eq(s.bestRun[2], 2)
		-- seat 1 (solids) hits a solid first but only a stripe drops: legal, the stripe stays down, turn passes
		t.eq(EightBall.apply(s, shot(1, { pot(13) })), "pass")
		t.falsy(s.onTable[13])
		t.eq(s.seat, 2)
		-- own ball and the other group's together: still your table
		t.eq(EightBall.apply(s, shot(9, { pot(4), pot(9) })), "continue")
		t.eq(s.seat, 2)
	end)

	t.test("POOL-R1 the four fouls, each giving the other player the cue ball in hand", function()
		local function after(): EightBall.State
			local s = EightBall.init(2, 1)
			EightBall.apply(s, shot(1))
			EightBall.apply(s, shot(11, { pot(11) })) -- seat 2 stripes, still at the table
			return s
		end
		local scratch = after()
		t.eq(EightBall.apply(scratch, shot(12, { pot(12), pot(0, 4) })), "foul")
		t.eq((scratch.last :: EightBall.Last).foul, "scratch")
		t.eq(scratch.seat, 1)
		t.eq(scratch.inHand, "anywhere")
		t.truthy(hasSpot(scratch, 0), "the cue ball is back on the table for the incoming player")
		t.falsy(scratch.onTable[12], "a ball potted on a foul stays down")
		local nothing = after()
		t.eq(EightBall.apply(nothing, shot(0)), "foul")
		t.eq((nothing.last :: EightBall.Last).foul, "no_hit")
		t.eq(nothing.inHand, "anywhere")
		local wrong = after()
		t.eq(EightBall.apply(wrong, shot(3, { pot(12) })), "foul")
		t.eq((wrong.last :: EightBall.Last).foul, "wrong_ball")
		local eightFirst = after()
		t.eq(EightBall.apply(eightFirst, shot(8)), "foul", "the 8 first while your group is up")
		local noRail = after()
		t.eq(EightBall.apply(noRail, shot(12, {}, false)), "foul")
		t.eq((noRail.last :: EightBall.Last).foul, "no_rail")
		t.eq(noRail.fouls[2], 1)
		-- a pot stands in for the cushion
		local potted = after()
		t.eq(EightBall.apply(potted, shot(12, { pot(12) }, false)), "continue")
		-- on an open table the 8 may not be hit first
		local open = EightBall.init(2, 1)
		EightBall.apply(open, shot(1))
		t.eq(EightBall.apply(open, shot(8)), "foul")
		for _, key in { "scratch", "no_hit", "wrong_ball", "no_rail", "idle" } do
			t.truthy(#EightBall.FOUL_TEXT[key] > 5, "plain words for the HUD")
		end
	end)

	t.test("POOL-R1 the 8 potted on the break comes back on the foot spot", function()
		local s = EightBall.init(2, 1)
		t.eq(EightBall.apply(s, shot(1, { pot(8, 5) })), "continue")
		t.falsy(s.done)
		t.truthy(s.onTable[8])
		local eight: Tables.Spot? = nil
		for _, sp in s.spots do
			if sp.id == 8 then
				t.eq(eight, nil, "once")
				eight = sp
			end
		end
		local e = eight :: Tables.Spot
		t.eq(e.x, 0)
		t.truthy(e.z >= pool.footZ, "on the foot spot or the nearest free place behind it")
		t.truthy(Tables.canPlace(pool, e.x, e.z, s.spots, 8), "touching nothing")
		-- with a scratch as well it is a foul, behind the head string (POOL-R3), and still no loss
		local f = EightBall.init(2, 1)
		t.eq(EightBall.apply(f, shot(1, { pot(8), pot(0) })), "foul")
		t.falsy(f.done)
		t.truthy(f.onTable[8])
	end)

	t.test("POOL-R1 POOL-R2 the 8 in the called pocket after clearing your group wins", function()
		local s = onTheEight()
		t.eq(s.seat, 2)
		t.truthy(EightBall.onEight(s, 2))
		t.deepEq(EightBall.legal(s, 2), { 8 })
		t.falsy(EightBall.input(s, 2, "shoot", { 0, 0.3 }), "the 8 needs a called pocket")
		t.truthy(EightBall.input(s, 2, "call", { 5 }))
		t.eq(s.called, 5)
		t.eq(EightBall.apply(s, shot(8, { pot(8, 5) })), "win")
		t.truthy(s.done)
		t.eq(s.winner, 2)
		t.eq(s.how, "eight")
		t.eq(EightBall.turn(s), nil)
		local r = EightBall.result(s) :: any
		t.eq(r.winner, 2)
		t.eq(r.scores[2], 7)
		t.eq(r.scores[1], 0)
		t.eq(r.left[1], 7)
		t.eq(r.bestRun[2], 8, "the run counts the 8")
		t.eq(EightBall.HOW_TEXT[r.how], "potted the 8 in the called pocket")
		t.falsy(EightBall.input(s, 1, "shoot", { 0, 0.3 }), "game over")
	end)

	t.test("POOL-R2 the 8 in any other pocket loses; only the 8 is called", function()
		local s = onTheEight()
		EightBall.input(s, 2, "call", { 5 })
		t.eq(EightBall.apply(s, shot(8, { pot(8, 6) })), "lose")
		t.eq(s.winner, 1)
		t.eq(s.how, "eight_wrong_pocket")
		-- a call cannot be made for any other ball, and not for a pocket that is not there
		local g = EightBall.init(2, 1)
		t.falsy(EightBall.input(g, 1, "call", { 2 }), "only the 8 is called")
		local e = onTheEight()
		t.falsy(EightBall.input(e, 2, "call", { 7 }))
		t.falsy(EightBall.input(e, 2, "call", { 2.5 }))
		t.falsy(EightBall.input(e, 1, "call", { 2 }), "not your turn")
		-- the call lasts one shot
		EightBall.input(e, 2, "call", { 3 })
		EightBall.apply(e, shot(8))
		t.eq(e.called, 0)
	end)

	t.test("POOL-R1 the 8 early, or with a foul, loses", function()
		local s = EightBall.init(2, 1)
		EightBall.apply(s, shot(1))
		EightBall.apply(s, shot(2, { pot(2) }))
		t.eq(EightBall.apply(s, shot(3, { pot(3), pot(8) })), "lose")
		t.eq(s.winner, 1)
		t.eq(s.how, "eight_early")
		-- the last ball of the group and the 8 in one shot: the group was not cleared BEFORE the shot
		local both = EightBall.init(2, 1)
		EightBall.apply(both, shot(1))
		EightBall.apply(both, shot(1, { pot(1) }))
		EightBall.apply(both, shot(2, { pot(2), pot(3), pot(4), pot(5), pot(6) }))
		t.eq(EightBall.apply(both, shot(7, { pot(7), pot(8) })), "lose")
		t.eq(both.how, "eight_early")
		-- on the 8, in the called pocket, but the cue ball follows it in
		local foul = onTheEight()
		EightBall.input(foul, 2, "call", { 1 })
		t.eq(EightBall.apply(foul, shot(8, { pot(8, 1), pot(0, 1) })), "lose")
		t.eq(foul.winner, 1)
		t.eq(foul.how, "eight_foul")
		-- on the 8, a foul WITHOUT potting it is only a foul
		local miss = onTheEight()
		EightBall.input(miss, 2, "call", { 1 })
		t.eq(EightBall.apply(miss, shot(9)), "foul")
		t.falsy(miss.done)
		t.eq(miss.seat, 1)
	end)

	t.test(
		"POOL-R3 a scratch on the break: ball in hand behind the head string only; any other foul, anywhere",
		function()
			local s = EightBall.init(2, 1)
			t.eq(EightBall.apply(s, shot(1, { pot(0, 2) })), "foul")
			t.eq(s.seat, 2)
			t.eq(s.inHand, "kitchen")
			t.falsy(EightBall.canPlace(s, 0, 0), "past the head string")
			t.falsy(EightBall.input(s, 2, "place", { 0, 0 }))
			t.truthy(EightBall.input(s, 2, "place", { 1.2, -4 }))
			for _, sp in s.spots do
				if sp.id == 0 then
					t.eq(sp.x, 1.2)
					t.eq(sp.z, -4)
				end
			end
			t.truthy(EightBall.input(s, 2, "place", { -1, pool.headZ }), "it can be moved again before the shot")
			-- an ordinary foul: anywhere on the bed that is free
			EightBall.apply(s, shot(0))
			t.eq(s.seat, 1)
			t.eq(s.inHand, "anywhere")
			t.truthy(EightBall.input(s, 1, "place", { 1.5, 1 }))
			t.falsy(EightBall.input(s, 1, "place", { 0, pool.footZ }), "not on another ball")
			t.falsy(EightBall.input(s, 1, "place", { 9, 0 }), "not off the table")
			t.falsy(EightBall.input(s, 1, "place", { 0 / 0, 0 }), "not nowhere")
			t.falsy(EightBall.input(s, 1, "place", { "a", 0 }))
			t.falsy(EightBall.input(s, 2, "place", { 0, 0 }), "not by the other player")
			-- once the shot is played the ball is no longer in hand
			EightBall.apply(s, shot(1, { pot(1) }))
			t.eq(s.inHand, "none")
			t.falsy(EightBall.input(s, 1, "place", { 0, 0 }))
		end
	)

	t.test("POOL-R4 a solid and a stripe in one shot leave the table open, in the order they dropped", function()
		local s = EightBall.init(2, 1)
		EightBall.apply(s, shot(1))
		t.eq(EightBall.apply(s, shot(2, { pot(10, 3), pot(2, 6) })), "continue")
		t.eq(s.group[1], nil)
		t.eq(s.group[2], nil, "still open")
		t.eq(s.seat, 2, "and the shooter stays on")
		t.deepEq((s.last :: EightBall.Last).pots, { 10, 2 })
		t.deepEq((s.last :: EightBall.Last).holes, { 3, 6 })
		t.deepEq(s.down, { 10, 2 }, "the rack window shows them in order")
		-- two of one group and none of the other decide it
		t.eq(EightBall.apply(s, shot(3, { pot(3), pot(4) })), "continue")
		t.eq(s.group[2], "solids")
		t.eq(s.group[1], "stripes")
	end)

	t.test("POOL-R5 no ball ever leaves the table: after the hardest shots every ball is at rest or potted", function()
		for seed = 1, 12 do
			local spots = Tables.rack(seed)
			local s = Shot.run(pool, spots, { Cue.strike(0, 0.02 * seed, 1, 0, 1, seed) })
			t.eq(#Shot.rest(s) + #Shot.pots(s), 16)
			for _, r in Shot.rest(s) do
				t.truthy(Tables.onBed(pool, r.x, r.z, -0.3), "on the cloth (or hanging in a pocket's jaws)")
			end
		end
	end)

	t.test("POOL-R6 practice: one seat, the same rules against no one; shots taken and best run", function()
		local s = EightBall.init(1, 3)
		t.eq(EightBall.apply(s, shot(1)), "pass")
		t.eq(s.seat, 1, "it is always your table")
		EightBall.apply(s, shot(9, { pot(9) }))
		t.eq(s.group[1], "stripes")
		t.eq(EightBall.apply(s, shot(0)), "foul")
		t.eq(s.seat, 1)
		t.eq(s.inHand, "anywhere", "a foul still gives the ball in hand")
		EightBall.apply(s, shot(10, { pot(10), pot(11), pot(12), pot(13), pot(14), pot(15) }))
		t.truthy(EightBall.input(s, 1, "call", { 2 }))
		t.eq(EightBall.apply(s, shot(8, { pot(8, 2) })), "win")
		local r = EightBall.result(s) :: any
		t.eq(r.winner, 1)
		t.eq(r.shots[1], 5)
		t.eq(r.bestRun[1], 7)
		t.eq(r.fouls[1], 1)
		-- losing a practice game has no winner
		local l = EightBall.init(1, 3)
		EightBall.apply(l, shot(1))
		t.eq(EightBall.apply(l, shot(8, { pot(8) })), "lose")
		t.eq(l.winner, nil)
		t.truthy(l.done)
	end)

	t.test(
		"POOL-R1 the break is the shot that first touches the rack: a tap or a miss leaves it to be broken",
		function()
			local function racked(s: EightBall.State, seed: number)
				t.eq(#s.spots, 16)
				local rack = Tables.rack(seed)
				for _, r in rack do
					if r.id ~= 0 then
						for _, sp in s.spots do
							if sp.id == r.id then
								t.eq(sp.x, r.x, "the rack has not moved")
								t.eq(sp.z, r.z)
							end
						end
					end
				end
			end
			-- a tap on the hold-to-shoot control: the cue ball stops short of everything
			local s = EightBall.init(2, 11)
			t.truthy(EightBall.input(s, 1, "shoot", { 0, 0.05 }))
			local last = s.last :: EightBall.Last
			t.eq(last.event, "foul")
			t.eq(last.foul, "no_hit")
			t.truthy(last.breakShot)
			t.falsy(s.broken, "the rack is still to be broken")
			t.eq(s.seat, 2, "by the other player")
			t.eq(s.inHand, "kitchen", "from behind the head string, not from anywhere")
			t.falsy(EightBall.canPlace(s, 0, 2), "not up against the rack")
			t.truthy(EightBall.canPlace(s, 1, pool.headZ))
			t.eq(#EightBall.legal(s, 2), 15, "anything may be hit on the break")
			racked(s, 11)
			for _, sp in s.spots do
				if sp.id == 0 then
					-- it had rolled past the head string: it may not be played from there
					t.eq(sp.x, 0)
					t.eq(sp.z, pool.headZ, "the cue ball is back on the head spot")
				end
			end
			-- seat 2's shot IS the break: a soft one into the rack that reaches no cushion stands (it was a no_rail
			-- foul when the tap had already "broken" the table)
			t.truthy(EightBall.input(s, 2, "shoot", { 0, 0.2 }))
			last = s.last :: EightBall.Last
			t.truthy(last.breakShot)
			t.truthy(last.firstHit ~= 0)
			t.truthy(
				last.event ~= "foul" or last.foul == "scratch",
				`a soft break is not a foul for want of a cushion ({last.foul})`
			)
			t.truthy(s.broken)
			-- the cue ball goes in without touching the rack (off the head spot into a head corner)
			local sc = EightBall.init(2, 11)
			local corner = pool.holes[2]
			local aim = Cue.angleOf(corner.x + corner.mx * 0.35, corner.z + corner.mz * 0.35 - pool.headZ)
			t.truthy(EightBall.input(sc, 1, "shoot", { aim, 0.25 }))
			last = sc.last :: EightBall.Last
			t.eq(last.foul, "scratch")
			t.deepEq(last.pots, { 0 })
			t.eq(last.firstHit, 0)
			t.falsy(sc.broken)
			t.eq(sc.seat, 2)
			t.eq(sc.inHand, "kitchen")
			racked(sc, 11)
			-- the 8 going down on the re-break comes back on the foot spot: it is a break, not "the 8 too early"
			-- (smashing the rack after a tap ended the game at once in 5 racks of 300)
			local e = EightBall.init(2, 11)
			t.eq(EightBall.apply(e, { firstHit = 0, pots = {}, railAfter = false }), "foul")
			t.falsy(e.broken)
			t.eq(EightBall.apply(e, { firstHit = 1, pots = { pot(8, 5), pot(3, 6) }, railAfter = true }), "continue")
			t.falsy(e.done, "not a loss")
			t.truthy(e.onTable[8])
			t.truthy(hasSpot(e, 8), "the 8 is back on the table")
			t.truthy((e.last :: EightBall.Last).breakShot)
			t.eq(e.group[2], nil, "and the table is open, as after any break")
			t.eq(e.seat, 2)
			t.truthy(e.broken)
			-- an idle turn and then a miss: still nobody has broken
			local idle = EightBall.init(2, 11)
			EightBall.skipTurn(idle)
			t.truthy((idle.last :: EightBall.Last).breakShot)
			t.eq(EightBall.apply(idle, { firstHit = 0, pots = { pot(0, 3) }, railAfter = false }), "foul")
			t.falsy(idle.broken)
			t.eq(idle.seat, 1)
			t.eq(idle.inHand, "kitchen")
			-- once broken, a miss is an ordinary foul: ball in hand anywhere
			EightBall.apply(idle, shot(1))
			t.eq(EightBall.apply(idle, shot(0)), "foul")
			t.eq(idle.inHand, "anywhere")
			-- practice: the same player breaks again
			local solo = EightBall.init(1, 11)
			t.truthy(EightBall.input(solo, 1, "shoot", { 0, 0.05 }))
			t.falsy(solo.broken)
			t.eq(solo.seat, 1)
			t.eq(solo.inHand, "kitchen")
		end
	)

	t.test(
		"POOL-R1 two balls met at the same instant: the hit is legal if either is, whatever the table's order",
		function()
			-- the referee alone: seat 2 has stripes; the cue ball meets the 9 and the 1 together
			local function stripes(): EightBall.State
				local s = EightBall.init(2, 1)
				EightBall.apply(s, shot(1))
				EightBall.apply(s, shot(11, { pot(11) }))
				t.eq(s.seat, 2)
				t.eq(s.group[2], "stripes")
				return s
			end
			for _, all in { { 9, 1 }, { 1, 9 } } do
				local s = stripes()
				t.eq(EightBall.apply(s, { firstHit = all[1], firstAll = all, pots = {}, railAfter = true }), "pass")
				t.eq((s.last :: EightBall.Last).foul, nil)
				t.eq((s.last :: EightBall.Last).firstHit, 9, "judged to have hit the legal one")
			end
			-- neither is legal: a foul still
			local bad = stripes()
			t.eq(EightBall.apply(bad, { firstHit = 1, firstAll = { 1, 2 }, pots = {}, railAfter = true }), "foul")
			t.eq((bad.last :: EightBall.Last).foul, "wrong_ball")
			t.eq((bad.last :: EightBall.Last).firstHit, 1)
			-- on the 8, the 8 and another together is a hit on the 8
			local eight = onTheEight()
			EightBall.input(eight, 2, "call", { 1 })
			t.eq(EightBall.apply(eight, { firstHit = 12, firstAll = { 12, 8 }, pots = {}, railAfter = true }), "pass")
			-- on the real table, in both orders of the table's list (it was a legal hit in one and a wrong-ball
			-- foul with ball in hand in the other)
			local R = Tables.BALL_R
			local a = math.rad(60)
			local gz = 1 - 2 * R
			local place = {
				[9] = { x = 0, z = 1 },
				[1] = { x = (2 * R + 0.003) * math.sin(a), z = gz + (2 * R + 0.003) * math.cos(a) },
			}
			for _, order in { { 9, 1 }, { 1, 9 } } do
				local s = stripes()
				local spots: { Tables.Spot } = { { id = 0, x = 0, z = gz - 1 } }
				for _, id in order do
					table.insert(spots, { id = id, x = place[id].x, z = place[id].z })
				end
				table.insert(spots, { id = 8, x = -2, z = -4 })
				s.spots = spots
				t.truthy(EightBall.input(s, 2, "shoot", { 0, 0.3, 0, 0.8 }))
				local script = EightBall.script(s) :: Shot.Script
				local both = Shot.firstHits(script, 0)
				table.sort(both)
				t.deepEq(both, { 1, 9 }, "the cue ball did meet both at once")
				local last = s.last :: EightBall.Last
				t.truthy(last.foul ~= "wrong_ball", `order {order[1]}, {order[2]}: {last.foul}`)
				t.eq(last.firstHit, 9)
			end
		end
	)

	t.test("POOL-R6 a run is the shooter's own balls: the other player's going down do not lengthen it", function()
		local s = EightBall.init(2, 1)
		-- the break: everything that drops is the breaker's
		t.eq(EightBall.apply(s, shot(1, { pot(3), pot(12) })), "continue")
		t.eq(s.run[1], 2)
		-- open table, one of each: still open, both count
		t.eq(EightBall.apply(s, shot(2, { pot(2), pot(13) })), "continue")
		t.eq(s.group[1], nil)
		t.eq(s.run[1], 4)
		-- a clean solid takes solids
		t.eq(EightBall.apply(s, shot(4, { pot(4) })), "continue")
		t.eq(s.group[1], "solids")
		t.eq(s.run[1], 5)
		-- a solid with two stripes going down as well: one for the run, not three
		t.eq(EightBall.apply(s, shot(5, { pot(5), pot(14), pot(15) })), "continue")
		t.eq(s.run[1], 6)
		t.eq(s.bestRun[1], 6)
		t.eq(EightBall.apply(s, shot(6)), "pass")
		t.eq(s.run[1], 0)
		t.eq(s.bestRun[1], 6)
		-- the stripes player: a stripe with two solids is a run of one
		t.eq(EightBall.apply(s, shot(10, { pot(10), pot(6), pot(7) })), "continue")
		t.eq(s.run[2], 1)
		t.eq(s.bestRun[2], 1)
		-- and the winning 8 counts
		t.eq(EightBall.apply(s, shot(11, { pot(11) })), "continue")
		t.eq(EightBall.apply(s, shot(9, { pot(9) })), "continue")
		t.truthy(EightBall.onEight(s, 2))
		EightBall.input(s, 2, "call", { 3 })
		t.eq(EightBall.apply(s, shot(8, { pot(8, 3) })), "win")
		t.eq((EightBall.result(s) :: any).bestRun[2], 4)
		t.eq((EightBall.result(s) :: any).bestRun[1], 6)
	end)

	t.test("POOL-R7 an idle turn is a foul: the other player has the ball in hand", function()
		local s = EightBall.init(2, 1)
		EightBall.skipTurn(s)
		t.eq(s.seat, 2, "an idle break hands the break over")
		t.eq(s.inHand, "kitchen")
		t.falsy(s.broken)
		EightBall.apply(s, shot(1))
		t.eq(s.seat, 1)
		EightBall.skipTurn(s)
		t.eq(s.seat, 2)
		t.eq(s.inHand, "anywhere")
		t.eq((s.last :: EightBall.Last).foul, "idle")
		t.eq(s.fouls[1], 2)
		t.eq(EightBall.script(s), nil, "there is no shot to play back")
		local done = onTheEight()
		EightBall.input(done, 2, "call", { 1 })
		EightBall.apply(done, shot(8, { pot(8, 1) }))
		EightBall.skipTurn(done)
		t.eq(done.winner, 2, "nothing changes after the end")
	end)

	t.test("shoot runs the table: the balls move, the script is kept, the turn follows the rules", function()
		local s = EightBall.init(2, 21)
		t.falsy(EightBall.input(s, 2, "shoot", { 0, 1 }), "not your turn")
		t.falsy(EightBall.input(s, 1, "shoot", { "north", 1 }), "an angle is a number")
		t.falsy(EightBall.input(s, 1, "shoot", { 0, 0 / 0 }))
		t.falsy(EightBall.input(s, 1, "shoot", nil))
		t.truthy(EightBall.input(s, 1, "shoot", { 0, 1, 0, 0.3 }))
		local script = EightBall.script(s) :: Shot.Script
		t.truthy(Shot.check(script) ~= nil)
		t.eq(script.table, "eightball")
		t.truthy(script.first[1] >= 1, "a square break hits the rack")
		t.truthy(s.broken)
		t.eq(s.shots[1], 1)
		-- the state's balls are where the script left them
		local rest = Shot.rest(script)
		for _, r in rest do
			if r.id ~= 0 or not (s.last :: EightBall.Last).foul then
				local found = false
				for _, sp in s.spots do
					if sp.id == r.id and sp.x == r.x and sp.z == r.z then
						found = true
					end
				end
				t.truthy(found, `ball {r.id}`)
			end
		end
		local up = 0
		for b = 1, 15 do
			if s.onTable[b] then
				up += 1
				t.truthy(hasSpot(s, b))
			else
				t.falsy(hasSpot(s, b))
			end
		end
		t.eq(up + #s.down, 15)
		t.truthy(hasSpot(s, 0), "the cue ball is always on the table between shots")
		-- power is clamped, not refused
		local seat = s.seat
		t.truthy(EightBall.input(s, seat, "shoot", { 1, 99 }))
	end)

	t.test("determinism: the same seed and the same inputs are the same game, byte for byte", function()
		local function play(): EightBall.State
			local s = EightBall.init(2, 77)
			local angles = { 0, 0.4, -1.2, 2.2, 3, -2.5, 0.9, 1.7 }
			for i, a in angles do
				if s.done then
					break
				end
				local seat = s.seat
				if s.inHand ~= "none" and i > 1 then
					EightBall.input(s, seat, "place", { 0.3, -3.5 })
				end
				EightBall.input(s, seat, "shoot", { a, if i == 1 then 1 else 0.45, 0.1, -0.2, 3 })
			end
			return s
		end
		local a, b = play(), play()
		t.deepEq(EightBall.view(a), EightBall.view(b))
		t.deepEq(a.spots, b.spots)
		t.deepEq(EightBall.script(a), EightBall.script(b))
		t.truthy(a.shotNo >= 5)
	end)

	t.test(
		"the view is a plain scoreboard: whose turn, groups, what is up, what is down, where every ball lies",
		function()
			local s = EightBall.init(2, 9)
			EightBall.apply(s, shot(1, { pot(14, 2) }))
			EightBall.apply(s, shot(5, { pot(5, 1) }))
			local v = EightBall.view(s)
			t.eq(v.kind, "pool")
			t.eq(v.turn, 1)
			t.deepEq(v.groups, { "solids", "stripes" })
			t.falsy(v.open)
			t.eq(#v.onTable, 13)
			t.eq(#v.balls, 14 * 3, "id, x, z for the cue ball and the thirteen")
			t.deepEq(v.left, { 6, 6 })
			t.deepEq(v.down, { 14, 5 })
			t.eq(v.inHand, "none")
			t.falsy(v.onEight)
			t.eq(v.last.event, "continue")
			t.deepEq(v.last.pots, { 5 })
			t.falsy(v.done)
			local function plain(x: any, depth: number)
				assert(depth < 5, "too deep")
				if type(x) == "table" then
					for k, y in x do
						t.truthy(type(k) == "string" or type(k) == "number")
						plain(y, depth + 1)
					end
				else
					t.truthy(type(x) == "number" or type(x) == "string" or type(x) == "boolean")
				end
			end
			plain(v, 0)
			t.eq(v.lastScript, nil, "the script travels on its own, once")
		end
	)
end
