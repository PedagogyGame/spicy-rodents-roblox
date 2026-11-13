--!strict
-- Minigames/Pool/BumperPool: the bumper pool rules, line by line against the checklist (BP-R2 .. BP-R7), the
-- simultaneous opening (BP-R3, BP-P5) and the "shoot" input driving the real table model.
local BumperPool = require("@shared/Minigames/Pool/BumperPool")
local Cue = require("@shared/Minigames/Pool/Cue")
local Minigame = require("@shared/Minigames/Minigame")
local Physics = require("@shared/Minigames/Pool/Physics")
local Shot = require("@shared/Minigames/Pool/Shot")
local Tables = require("@shared/Minigames/Pool/Tables")

return function(t)
	local bumper = Tables.bumper()

	local function pot(ball: number, hole: number, cushions: number?): BumperPool.PotAt
		return { ball = ball, hole = hole, cushions = cushions or 0 }
	end
	local function by(seat: number): (number) -> number
		return function(_ball: number): number
			return seat
		end
	end
	-- a game past its opening, seat 1 to shoot
	local function inPlay(): BumperPool.State
		local s = BumperPool.init(2, 1)
		s.phase = "play"
		s.seat = 1
		return s
	end
	local function onTable(s: BumperPool.State, ball: number): boolean
		for _, sp in s.spots do
			if sp.id == ball then
				return true
			end
		end
		return false
	end
	-- the first opening bank (angle, at power 0.2) that sinks seat 1's marked ball off the side cushion and
	-- touches no other ball on the way (so it is the same bank whatever the other marked ball is doing)
	local function sinkingAngle(): number
		for i = 0, 120 do
			local angle = math.rad(30 + i * 0.125)
			local s = Shot.run(bumper, Tables.bumperStart(), { Cue.strike(1, angle, 0.2, 0, 0.8, nil) })
			local pots = Shot.pots(s)
			if #pots == 1 and pots[1].ball == 1 and pots[1].hole == 2 and s.first[1] == 0 then
				return angle
			end
		end
		error("no opening bank sinks the marked ball")
	end

	t.test("contract and BP-R2: two seats, no money; five each, one marked, each shooting at the far cup", function()
		t.truthy(Minigame.check(BumperPool))
		t.eq(BumperPool.def.game, "bumper_pool")
		t.eq(BumperPool.def.seats, 2)
		t.eq(BumperPool.def.money, "none")
		local s = BumperPool.init(2, 1)
		t.eq(#s.spots, 10)
		t.deepEq(BumperPool.mine(s, 1), { 1, 2, 3, 4, 5 })
		t.deepEq(BumperPool.mine(s, 2), { 6, 7, 8, 9, 10 })
		t.eq(BumperPool.markedOf(1), 1)
		t.eq(BumperPool.markedOf(2), 6)
		t.eq(BumperPool.sideOf(5), 1)
		t.eq(BumperPool.sideOf(6), 2)
		-- seat 1 starts at the head end and shoots at the foot cup (hole 2); seat 2 the other way
		t.eq(BumperPool.cupOf(1), 2)
		t.eq(BumperPool.cupOf(2), 1)
		for _, sp in s.spots do
			local own = bumper.holes[BumperPool.cupOf(BumperPool.sideOf(sp.id))]
			t.truthy(math.abs(sp.z - own.z) > bumper.halfL, "its own cup is at the far end")
		end
		t.eq(BumperPool.result(s), nil)
	end)

	t.test("BP-R3 BP-P5 the opening: both strike their marked ball, and the table plays them together", function()
		local s = BumperPool.init(2, 4)
		t.eq(s.phase, "opening")
		t.deepEq(BumperPool.waiting(s), { 1, 2 }, "both may strike")
		t.eq(BumperPool.turn(s), 1)
		t.falsy(BumperPool.input(s, 1, "shoot", { 2, 0.6, 0.2 }), "the opening is played with the marked ball")
		t.falsy(BumperPool.input(s, 1, "shoot", { 6, 0.6, 0.2 }), "and with your own")
		t.truthy(BumperPool.input(s, 2, "shoot", { 6, math.rad(218), 0.2 }), "either may go first")
		t.eq(BumperPool.script(s), nil, "nothing moves until both are in")
		t.eq(s.shotNo, 0)
		t.deepEq(BumperPool.waiting(s), { 1 })
		t.eq(BumperPool.turn(s), 1)
		t.falsy(BumperPool.input(s, 2, "shoot", { 6, 1, 0.2 }), "one strike each")
		t.truthy(BumperPool.input(s, 1, "shoot", { 1, math.rad(38), 0.2 }))
		local script = BumperPool.script(s) :: Shot.Script
		t.eq(script.table, "bumper")
		t.eq(#script.strikes, 12, "two strikes in one model run")
		t.eq(#script.first, 2)
		t.deepEq((s.last :: BumperPool.Last).shooters, { 1, 2 })
		t.eq(s.shots[1], 1)
		t.eq(s.shots[2], 1)
		t.eq(s.shotNo, 1)
	end)

	t.test("BP-R3 whoever sinks the marked ball in the opening shoots next", function()
		local angle = sinkingAngle()
		local s = BumperPool.init(2, 4)
		BumperPool.input(s, 1, "shoot", { 1, angle, 0.2, 0, 0.8 })
		-- seat 2 rolls its marked ball a little way up the table and no further
		BumperPool.input(s, 2, "shoot", { 6, math.rad(200), 0.05, 0, 0.8 })
		t.eq(s.phase, "play")
		t.eq(s.sunk[1], 1)
		t.truthy(s.markedDown[1])
		t.falsy(s.markedDown[2])
		t.eq(s.seat, 1)
		t.eq((s.last :: BumperPool.Last).event, "opening")
		t.deepEq((s.last :: BumperPool.Last).pots, { 1 })
		t.falsy(onTable(s, 1))
		t.eq(s.banks[1], 1, "and it was a bank")
	end)

	t.test("BP-R3 if neither sinks, the ball lying nearer its cup shoots next", function()
		local s = BumperPool.init(2, 4)
		-- seat 1 barely moves; seat 2 banks well up the table toward its cup
		BumperPool.input(s, 1, "shoot", { 1, math.rad(90), 0, 0, 0.8 })
		BumperPool.input(s, 2, "shoot", { 6, math.rad(180 + 38), 0.2, 0, 0.8 })
		t.eq(s.phase, "play")
		t.eq(s.sunk[1] + s.sunk[2], 0)
		local function dist(seat: number, ball: number): number
			local cup = bumper.holes[BumperPool.cupOf(seat)]
			for _, sp in s.spots do
				if sp.id == ball then
					return math.sqrt((sp.x - cup.x) ^ 2 + (sp.z - cup.z) ^ 2)
				end
			end
			return math.huge
		end
		t.truthy(dist(2, 6) < dist(1, 1), "seat 2's ball lies nearer")
		t.eq(s.seat, 2)
		t.eq(BumperPool.turn(s), 2)
		t.deepEq(BumperPool.waiting(s), { 2 })
	end)

	t.test("BP-R3 if both sink, each side's next ball goes on the marked spot and they open again", function()
		local angle = sinkingAngle()
		local s = BumperPool.init(2, 4)
		BumperPool.input(s, 1, "shoot", { 1, angle, 0.2, 0, 0.8 })
		-- the mirror image of the same bank, from the other end
		BumperPool.input(s, 2, "shoot", { 6, angle + math.pi, 0.2, 0, 0.8 })
		t.deepEq(s.sunk, { 1, 1 })
		t.eq(s.phase, "opening", "they open again")
		t.deepEq(s.openers, { 2, 7 })
		t.deepEq(BumperPool.waiting(s), { 1, 2 })
		for _, sp in s.spots do
			if sp.id == 2 then
				t.eq(sp.x, 0)
				t.near(sp.z, -Tables.CUP_Z + Tables.MARKED_OFF, 1e-9, "on the marked ball's spot")
			elseif sp.id == 7 then
				t.eq(sp.x, 0)
				t.near(sp.z, Tables.CUP_Z - Tables.MARKED_OFF, 1e-9)
			end
		end
		t.falsy(BumperPool.input(s, 1, "shoot", { 3, 1, 0.2 }), "with the ball that was put there")
		t.truthy(BumperPool.input(s, 1, "shoot", { 2, 1, 0.1 }))
	end)

	t.test("BP-R4 the marked ball first: another of your own before it and the opponent drops two", function()
		local s = inPlay()
		local again = BumperPool.settle(s, { pot(3, 2) }, by(1))
		t.truthy(again[1], "it still went down, and gives another shot")
		t.eq(s.sunk[1], 1)
		t.eq(s.sunk[2], 2, "the opponent drops two of their own")
		local last = s.last :: BumperPool.Last
		t.eq(last.awarded, 2)
		-- the table picks as a player would: the marked ball while it is still up, then the farthest from the cup
		t.deepEq(last.dropped, { 6, 9 }, "their marked ball, then the farthest (the lower of two equally far)")
		t.falsy(onTable(s, 6))
		t.falsy(onTable(s, 9))
		t.truthy(onTable(s, 10))
		t.truthy(s.markedDown[2], "with the marked ball down, their other balls are free")
		-- with the marked ball already down, the two lying farthest from the cup go
		local far = inPlay()
		far.markedDown[2] = true
		for i = #far.spots, 1, -1 do
			local sp = far.spots[i]
			if sp.id == 6 then
				table.remove(far.spots, i)
			elseif sp.id == 10 then
				sp.x, sp.z = 0.3, -1.6 -- well up the table, near its cup
			end
		end
		far.sunk[2] = 1
		BumperPool.settle(far, { pot(3, 2) }, by(1))
		t.deepEq((far.last :: BumperPool.Last).dropped, { 9, 7 }, "the ball near the cup is left to be played")
		t.truthy(onTable(far, 10))
		-- once the marked ball is down there is no penalty
		local ok = inPlay()
		BumperPool.settle(ok, { pot(1, 2) }, by(1))
		BumperPool.settle(ok, { pot(3, 2) }, by(1))
		t.eq(ok.sunk[1], 2)
		t.eq(ok.sunk[2], 0)
		t.eq((ok.last :: BumperPool.Last).awarded, 0)
		-- the marked ball and another in the SAME shot, marked first: no penalty
		local same = inPlay()
		BumperPool.settle(same, { pot(1, 2), pot(4, 2) }, by(1))
		t.eq(same.sunk[2], 0)
		t.eq(same.sunk[1], 2)
	end)

	t.test("BP-R5 your own ball gives another shot; an opponent's ball counts for them, with no penalty", function()
		local s = inPlay()
		local again = BumperPool.settle(s, { pot(1, 2, 2) }, by(1))
		t.truthy(again[1])
		t.eq(s.banks[1], 1, "off two cushions: a bank")
		t.truthy(s.markedDown[1])
		-- seat 1 knocks seat 2's ball into seat 2's cup
		local gift = BumperPool.settle(s, { pot(8, 1) }, by(1))
		t.falsy(gift[1], "no extra shot for sinking theirs")
		t.falsy(gift[2])
		t.eq(s.sunk[2], 1, "it counts for the opponent")
		t.eq((s.last :: BumperPool.Last).awarded, 0, "no penalty")
		t.eq(s.sunk[1], 1)
		-- seat 1 knocks seat 2's ball into the WRONG cup for it: it still counts for seat 2, still no penalty
		BumperPool.settle(s, { pot(9, 2) }, by(1))
		t.eq(s.sunk[2], 2)
		t.eq((s.last :: BumperPool.Last).awarded, 0)
		-- their marked ball going down by your hand counts as their marked ball down
		BumperPool.settle(s, { pot(6, 1) }, by(1))
		t.truthy(s.markedDown[2])
	end)

	t.test("BP-R5 your own ball in the opponent's cup: it is down, and the opponent drops two", function()
		local s = inPlay()
		BumperPool.settle(s, { pot(1, 2) }, by(1))
		local again = BumperPool.settle(s, { pot(4, 1) }, by(1))
		t.falsy(again[1], "no extra shot for that")
		t.eq(s.sunk[1], 2)
		t.eq(s.sunk[2], 2)
		t.eq((s.last :: BumperPool.Last).awarded, 2)
		t.falsy(s.done)
	end)

	t.test("BP-R5 your LAST ball in the opponent's cup loses the game", function()
		local s = inPlay()
		BumperPool.settle(s, { pot(1, 2), pot(2, 2), pot(3, 2), pot(4, 2) }, by(1))
		t.eq(s.sunk[1], 4)
		t.falsy(s.done)
		BumperPool.settle(s, { pot(5, 1) }, by(1))
		t.truthy(s.done)
		t.eq(s.winner, 2)
		t.eq(s.how, "last_ball_wrong_cup")
		t.eq(BumperPool.HOW_TEXT[s.how :: string], "sank the last ball in the wrong cup")
	end)

	t.test("BP-R6 the first to have all five down wins, by their own shots or by the balls they are given", function()
		local s = inPlay()
		BumperPool.settle(s, { pot(1, 2), pot(2, 2), pot(3, 2), pot(4, 2) }, by(1))
		BumperPool.settle(s, { pot(5, 2) }, by(1))
		t.truthy(s.done)
		t.eq(s.winner, 1)
		t.eq(s.how, "five")
		local r = BumperPool.result(s) :: any
		t.deepEq(r.scores, { 5, 0 })
		t.eq(r.winner, 1)
		-- the penalty award can finish a game: seat 2 has four down and seat 1 breaks BP-R4
		local p = inPlay()
		BumperPool.settle(p, { pot(6, 1), pot(7, 1), pot(8, 1), pot(9, 1) }, by(2))
		t.eq(p.sunk[2], 4)
		BumperPool.settle(p, { pot(3, 2) }, by(1))
		t.truthy(p.done)
		t.eq(p.winner, 2)
		t.eq(p.sunk[2], 5)
		t.deepEq((p.last :: BumperPool.Last).dropped, { 10 }, "there was only one left to drop")
		-- nothing more is judged after the end
		BumperPool.settle(p, { pot(1, 2) }, by(1))
		t.eq(p.sunk[1], 1)
	end)

	t.test("BP-R7 an idle turn passes the shot; an idle opener's ball is simply not struck", function()
		local s = inPlay()
		BumperPool.skipTurn(s)
		t.eq(s.seat, 2)
		t.eq((s.last :: BumperPool.Last).event, "idle")
		BumperPool.skipTurn(s)
		t.eq(s.seat, 1)
		-- the opening: seat 1 strikes, seat 2 idles
		-- (a soft one that stays in its own half, so nothing of seat 1's can reach seat 2's ball)
		local o = BumperPool.init(2, 2)
		BumperPool.input(o, 1, "shoot", { 1, math.rad(38), 0.05 })
		t.eq(BumperPool.turn(o), 2)
		BumperPool.skipTurn(o)
		t.eq(o.phase, "play")
		t.eq(#(BumperPool.script(o) :: Shot.Script).strikes, 6, "one strike in the run")
		t.eq(o.shots[2], 0)
		for _, sp in o.spots do
			if sp.id == 6 then
				t.near(sp.z, Tables.CUP_Z - Tables.MARKED_OFF, 1e-9, "seat 2's marked ball never moved")
			end
		end
		-- the fallback for decision D2: no opening at all, in turn from seat 1
		local alt = BumperPool.init(2, 2, false)
		t.eq(alt.phase, "play")
		t.deepEq(BumperPool.waiting(alt), { 1 })
		t.falsy(BumperPool.input(alt, 2, "shoot", { 6, 0, 0.2 }), "not seat 2's turn")
		t.truthy(BumperPool.input(alt, 1, "shoot", { 1, math.rad(38), 0.2 }))
		-- both idle: ordinary play from seat 1, nothing moved
		local n = BumperPool.init(2, 2)
		BumperPool.skipTurn(n)
		BumperPool.skipTurn(n)
		t.eq(n.phase, "play")
		t.eq(n.seat, 1)
		t.eq(BumperPool.script(n), nil)
	end)

	t.test("practice: one seat, your five alone on the table, every one down in the fewest shots", function()
		local s = BumperPool.init(1, 3)
		t.eq(#s.spots, 5)
		t.eq(s.phase, "play", "no opening against no one")
		t.eq(BumperPool.turn(s), 1)
		BumperPool.settle(s, { pot(3, 2) }, by(1))
		t.eq(s.sunk[1], 1)
		t.eq((s.last :: BumperPool.Last).awarded, 0, "nobody to be given balls")
		BumperPool.skipTurn(s)
		t.eq(s.seat, 1)
		BumperPool.settle(s, { pot(1, 2), pot(2, 2), pot(4, 2), pot(5, 2) }, by(1))
		t.truthy(s.done)
		t.eq(s.winner, 1)
		local r = BumperPool.result(s) :: any
		t.eq(r.scores[1], 5)
		t.truthy(r.shots ~= nil)
	end)

	-- move a ball of the state to a place of the spec's choosing
	local function put(s: BumperPool.State, ball: number, x: number, z: number)
		for _, sp in s.spots do
			if sp.id == ball then
				sp.x, sp.z = x, z
			end
		end
	end
	local function spotOf(s: BumperPool.State, ball: number): Tables.Spot?
		for _, sp in s.spots do
			if sp.id == ball then
				return sp
			end
		end
		return nil
	end

	t.test("BP-R3 BP-R5 the opening: a ball the OTHER side's strike knocks in is not its owner's shot", function()
		-- Seat 1's marked ball is sent into seat 2's resting ball 9, which drops in the foot cup (seat 1's cup,
		-- the wrong one for seat 2). It counts for seat 2 with no penalty. It used to be charged to seat 2 as
		-- "your own ball in the opponent's cup", and seat 1 was handed two free balls for doing it
		-- (seat 2's marked ball is moved out of the lane in front of the cup; seat 1 plays a stop shot)
		local s = BumperPool.init(2, 1)
		put(s, 6, 1.2, 1)
		put(s, 1, 0, 1.2)
		put(s, 9, 0, 1.9)
		t.truthy(BumperPool.input(s, 1, "shoot", { 1, 0, Cue.powerFor(3.4), 0, -0.2 }))
		BumperPool.skipTurn(s) -- seat 2 does not strike at all
		local last = s.last :: BumperPool.Last
		t.deepEq(last.pots, { 9 }, "ball 9 went down")
		t.deepEq(last.holes, { 2 }, "in the foot cup")
		t.eq(last.awarded, 0, "nobody is given balls")
		t.deepEq(last.dropped, {})
		t.deepEq(s.sunk, { 0, 1 }, "it counts for its owner, and that is all")
		t.eq(#BumperPool.mine(s, 1), 5, "none of seat 1's were dropped in for it")
		t.eq(#BumperPool.mine(s, 2), 4)
		-- the same with seat 2 striking its own marked ball at the same moment
		local both = BumperPool.init(2, 1)
		put(both, 6, 1.2, 1)
		put(both, 1, 0, 1.2)
		put(both, 9, 0, 1.9)
		BumperPool.input(both, 2, "shoot", { 6, math.pi, 0.05, 0, 0.8 })
		BumperPool.input(both, 1, "shoot", { 1, 0, Cue.powerFor(3.4), 0, -0.2 })
		t.deepEq((both.last :: BumperPool.Last).pots, { 9 })
		t.eq((both.last :: BumperPool.Last).awarded, 0)
		t.deepEq(both.sunk, { 0, 1 })
		-- Seat 1's strike knocks seat 2's resting ball 7 into seat 2's OWN cup while seat 2's marked ball is
		-- still up. It counts for seat 2; it is not seat 2 sinking a ball before its marked one (BP-R4), and it
		-- does not win seat 2 the next shot
		local own = BumperPool.init(2, 1)
		put(own, 1, 0, -1.2)
		put(own, 7, 0, -1.9)
		BumperPool.input(own, 1, "shoot", { 1, math.pi, Cue.powerFor(3.4), 0, -0.2 })
		BumperPool.skipTurn(own)
		local ol = own.last :: BumperPool.Last
		t.deepEq(ol.pots, { 7 }, "ball 7 went down")
		t.deepEq(ol.holes, { 1 }, "in the head cup, its own")
		t.eq(ol.awarded, 0, "no penalty for a ball someone else sank")
		t.deepEq(own.sunk, { 0, 1 })
		t.eq(#BumperPool.mine(own, 1), 5)
		t.falsy(own.markedDown[2])
		t.eq(own.seat, 1, "and it does not win seat 2 the shot: seat 2 never struck")
		-- the referee alone: a ball that is nobody's shot (shooterOf answers 0) counts and nothing else happens
		local r = BumperPool.init(2, 1)
		local again = BumperPool.settle(r, { pot(9, 2), pot(3, 2), pot(8, 1) }, function(_ball: number): number
			return 0
		end)
		t.falsy(again[1])
		t.falsy(again[2])
		t.deepEq(r.sunk, { 1, 2 })
		t.eq((r.last :: BumperPool.Last).awarded, 0)
		-- the two struck balls meet (seat 1 plays straight up the table at seat 2's marked ball, which has been
		-- rolled a little way to meet it) and seat 2's goes down in the cup behind it, the wrong one for it.
		-- Both strikes had a hand in that: it counts for seat 2 and nobody is given anything
		local clash = BumperPool.init(2, 1)
		put(clash, 1, 0, 0.9)
		BumperPool.input(clash, 2, "shoot", { 6, math.pi, 0, 0, 0.8 })
		BumperPool.input(clash, 1, "shoot", { 1, 0, Cue.powerFor(4), 0, -0.2 })
		local cl = clash.last :: BumperPool.Last
		t.eq(Shot.firstHit(BumperPool.script(clash) :: Shot.Script, 1), 6, "they met")
		t.deepEq(cl.pots, { 6 })
		t.deepEq(cl.holes, { 2 })
		t.eq(cl.awarded, 0)
		t.deepEq(clash.sunk, { 0, 1 })
		t.truthy(clash.markedDown[2])
		t.deepEq(cl.offside, { 1, 2 }, "neither was a bank")
		-- a struck ball that nothing else touched answers to its striker: seat 1's opener into the head cup
		-- (the wrong one) gives
		-- seat 2 two balls
		local wrong = BumperPool.init(2, 1)
		BumperPool.input(wrong, 1, "shoot", { 1, math.pi, Cue.powerFor(3.2), 0, 0.8 })
		BumperPool.skipTurn(wrong)
		local wl = wrong.last :: BumperPool.Last
		t.deepEq(wl.pots, { 1 })
		t.deepEq(wl.holes, { 1 })
		t.eq(wl.awarded, 2)
		t.eq(#wl.dropped, 2)
		t.eq(wrong.sunk[2], 2)
	end)

	t.test(
		"BP-R3 the opening is banked off the cushion on your own right: anything else cannot win the shot",
		function()
			t.eq(BumperPool.rightCushion(1), 2)
			t.eq(BumperPool.rightCushion(2), 1)
			t.truthy(bumper.segs[2].x1 > 0, "seat 1 shoots up the table: its right is +x")
			t.truthy(bumper.segs[1].x1 < 0, "seat 2 shoots down it: its right is -x")
			local angle = sinkingAngle()
			-- both off their right: fair, and the two balls never meet
			local fair = BumperPool.init(2, 4)
			BumperPool.input(fair, 1, "shoot", { 1, angle, 0.2, 0, 0.8 })
			BumperPool.input(fair, 2, "shoot", { 6, angle + math.pi, 0.2, 0, 0.8 })
			t.deepEq((fair.last :: BumperPool.Last).offside, {})
			local script = BumperPool.script(fair) :: Shot.Script
			t.eq(Shot.firstHit(script, 1), 0, "the marked balls cross without touching")
			t.eq(Shot.firstHit(script, 6), 0)
			-- seat 1 sinks straight in from in front of its cup (no cushion); seat 2 banks off its right and
			-- misses. The ball is down, but the next shot is seat 2's (it was seat 1's before)
			local s = BumperPool.init(2, 4)
			put(s, 1, 0, 1.3)
			put(s, 6, -0.6, 1.5)
			BumperPool.input(s, 1, "shoot", { 1, 0, Cue.powerFor(3.2), 0, 0.8 })
			BumperPool.input(s, 2, "shoot", { 6, math.rad(180 + 38), 0.1, 0, 0.8 })
			t.eq((Shot.firstTouch(BumperPool.script(s) :: Shot.Script, 6)), Physics.EV.cushion)
			local last = s.last :: BumperPool.Last
			t.deepEq(last.pots, { 1 })
			t.eq(s.sunk[1], 1, "it still counts")
			t.truthy(s.markedDown[1])
			t.deepEq(last.offside, { 1 })
			t.eq(s.phase, "play")
			t.eq(s.seat, 2, "the fair opener shoots next")
			-- the mirror image of the good bank, off seat 1's LEFT (the line seat 2's ball is coming down): it
			-- sinks alone, and it is offside. Seat 2 only taps its ball (no cushion either): both offside, so the
			-- ball lying nearer its cup has the shot, which is seat 2's, since seat 1's is down
			local left = BumperPool.init(2, 4)
			BumperPool.input(left, 1, "shoot", { 1, -angle, 0.2, 0, 0.8 })
			BumperPool.input(left, 2, "shoot", { 6, math.rad(90), 0, 0, 0.8 })
			local ll = left.last :: BumperPool.Last
			t.deepEq(ll.pots, { 1 }, "the table is the same left to right")
			t.deepEq(ll.offside, { 1, 2 })
			t.eq(left.seat, 2)
			-- an opener that is not struck at all cannot win the shot from a fair one that missed
			local idle = BumperPool.init(2, 4)
			BumperPool.input(idle, 1, "shoot", { 1, math.rad(38), 0.1, 0, 0.8 })
			BumperPool.skipTurn(idle)
			t.deepEq((idle.last :: BumperPool.Last).offside, {}, "only a struck ball can be offside")
			t.eq(idle.seat, 1)
		end
	)

	t.test("BP-R2 practice: only the far cup counts; a ball in the near cup goes back on its spot", function()
		-- the referee alone
		local s = BumperPool.init(1, 3)
		local again = BumperPool.settle(s, { pot(2, 1) }, by(1))
		t.falsy(again[1], "no extra shot for it")
		t.eq(s.sunk[1], 0, "the cup beside the starting spots is not a sink")
		t.deepEq((s.last :: BumperPool.Last).respotted, { 2 })
		t.deepEq((s.last :: BumperPool.Last).pots, { 2 }, "it did go down, and the client shows it")
		local back = spotOf(s, 2) :: Tables.Spot
		t.eq(back.x, -Tables.SPOT_X[1])
		t.eq(back.z, -Tables.CUP_Z, "back on its own spot")
		t.eq(#s.spots, 5)
		-- its spot taken: the nearest free place up the table from it
		local taken = BumperPool.init(1, 3)
		put(taken, 3, -Tables.SPOT_X[1] + 0.05, -Tables.CUP_Z + 0.02)
		BumperPool.settle(taken, { pot(2, 1) }, by(1))
		local near = spotOf(taken, 2) :: Tables.Spot
		t.truthy(Tables.canPlace(bumper, near.x, near.z, taken.spots, 2), "touching nothing")
		t.truthy(near.z > -Tables.CUP_Z and near.z < -Tables.CUP_Z + 0.6)
		-- on the real table: a ball rolled into the cup at its own end
		local real = BumperPool.init(1, 1)
		put(real, 1, 1.2, 0.5)
		put(real, 2, 0, -1.4)
		t.truthy(BumperPool.input(real, 1, "shoot", { 2, math.pi, Cue.powerFor(3.2), 0, 0.8 }))
		local last = real.last :: BumperPool.Last
		t.deepEq(last.pots, { 2 })
		t.deepEq(last.holes, { 1 }, "the head cup, beside where it started")
		t.deepEq(last.respotted, { 2 })
		t.eq(last.event, "pass", "no sink: the shot is counted and nothing more")
		t.eq(real.sunk[1], 0)
		t.eq(real.shots[1], 1)
		t.falsy(real.done)
		local again2 = spotOf(real, 2) :: Tables.Spot
		t.eq(again2.x, -Tables.SPOT_X[1])
		t.eq(again2.z, -Tables.CUP_Z)
		t.eq(#real.spots, 5)
		-- against an opponent nothing has changed: your own ball in their cup is down, and they drop two
		local two = inPlay()
		BumperPool.settle(two, { pot(1, 2) }, by(1))
		BumperPool.settle(two, { pot(2, 1) }, by(1))
		t.eq(two.sunk[1], 2)
		t.deepEq((two.last :: BumperPool.Last).respotted, {})
		t.eq((two.last :: BumperPool.Last).awarded, 2)
	end)

	t.test("banks made: a cushion touched before the cup's rim, not the one behind the cup on the way down", function()
		-- straight at the cup from the front, firmly enough to reach the cushion behind it while dropping
		local sank, touched = 0, 0
		for _, speed in { 5, 6, 7, 8 } do
			local s = BumperPool.init(1, 1)
			put(s, 1, 0, Tables.CUP_Z - 1.26)
			BumperPool.input(s, 1, "shoot", { 1, 0, Cue.powerFor(speed), 0, 0.8 })
			if s.sunk[1] == 1 then
				sank += 1
				t.eq(s.banks[1], 0, `straight in at {speed} studs/s is not a bank`)
				local script = BumperPool.script(s) :: Shot.Script
				if script.rails[Shot.indexOf(script, 1) :: number] > 0 then
					touched += 1
				end
			end
		end
		t.truthy(sank >= 3, "most of them drop")
		t.truthy(touched >= 1, "and at least one touched the end cushion on its way down")
		-- the opening bank off the side cushion is one
		local s = BumperPool.init(1, 1)
		BumperPool.input(s, 1, "shoot", { 1, sinkingAngle(), 0.2, 0, 0.8 })
		t.eq(s.sunk[1], 1)
		t.eq(s.banks[1], 1)
	end)

	t.test("shoot: your own ball, on the table, on your turn; the table plays it and the turn follows", function()
		local s = inPlay()
		t.falsy(BumperPool.input(s, 2, "shoot", { 6, 0, 0.2 }), "not your turn")
		t.falsy(BumperPool.input(s, 1, "shoot", { 6, 0, 0.2 }), "not your ball")
		t.falsy(BumperPool.input(s, 1, "shoot", { 11, 0, 0.2 }), "no such ball")
		t.falsy(BumperPool.input(s, 1, "shoot", { 1, "left", 0.2 }))
		t.falsy(BumperPool.input(s, 1, "shoot", { 1, 0, 0 / 0 }))
		t.falsy(BumperPool.input(s, 1, "strike", { 1, 0, 0.2 }), "one verb")
		t.truthy(BumperPool.input(s, 1, "shoot", { 2, math.rad(10), 0.1, 0, 0.8 }), "any of your own may be struck")
		local script = BumperPool.script(s) :: Shot.Script
		t.truthy(Shot.check(script) ~= nil)
		t.eq(script.strikes[1], 2)
		t.eq(s.shots[1], 1)
		t.eq(s.seat, 2, "nothing sunk: the shot passes")
		t.eq((s.last :: BumperPool.Last).event, "pass")
		t.deepEq(s.spots, Shot.rest(script), "the balls lie where the shot left them")
		-- a sunk ball is off the table and cannot be struck again
		BumperPool.settle(s, { pot(7, 1) }, by(2))
		t.falsy(BumperPool.input(s, 2, "shoot", { 7, 0, 0.2 }))
	end)

	t.test(
		"determinism and the view: the same seed and inputs are the same game; the scoreboard is plain data",
		function()
			local function play(): BumperPool.State
				local s = BumperPool.init(2, 11)
				BumperPool.input(s, 1, "shoot", { 1, math.rad(37), 0.21, 0.2, 0.5 })
				BumperPool.input(s, 2, "shoot", { 6, math.rad(215), 0.19, 0, 0.8 })
				for k = 1, 6 do
					local seat = BumperPool.turn(s)
					if seat == nil then
						break
					end
					local ball = BumperPool.mine(s, seat)[1]
					BumperPool.input(s, seat, "shoot", { ball, 0.4 * k + (seat - 1) * math.pi, 0.2 + 0.03 * k, 0, 0.8 })
				end
				return s
			end
			local a, b = play(), play()
			t.deepEq(BumperPool.view(a), BumperPool.view(b))
			t.deepEq(BumperPool.script(a), BumperPool.script(b))
			local v = BumperPool.view(a)
			t.eq(v.kind, "bumper_pool")
			t.eq(v.phase, "play")
			t.eq(#v.balls, #a.spots * 3)
			t.eq(#v.sunk, 2)
			t.eq(#v.markedDown, 2)
			t.truthy(v.turn == 1 or v.turn == 2)
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
		end
	)
end
