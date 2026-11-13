--!strict
-- The owner's own checks of his air hockey simulation (docs/reference/air_hockey/physics_tests.cpp), ported one
-- for one against Shared/Minigames/AirHockey/Sim: fast rail shots, end rails, a goal scored exactly once, the
-- rounded goal posts, the goal slot's side walls, still and moving mallets, pause, match reset, mallet bounds
-- and 120 seconds of play that stays finite, on the table and under the speed limit. Then what the port adds
-- for itself: determinism, the serve, what the last contact was, and the one rule that is not his (the rails
-- hold a puck that a mallet presses into them).
local Sim = require("@shared/Minigames/AirHockey/Sim")

-- (his `active`: no countdown, no drag)
local function active(): Sim.State
	local g = Sim.new()
	g.countdown = 0
	g.drag = 0
	return g
end

return function(t)
	t.test("his check 1: a fast shot at a side rail comes back inside it", function()
		local g = active()
		g.px, g.py, g.vx, g.vy = 0.58, 0, 7, 0
		Sim.tick(g, 0.02, 0, false)
		t.truthy(g.vx < 0 and g.px < Sim.HALF_WIDTH - Sim.PUCK_RADIUS)
	end)

	t.test("his check 2: the end rail beside the goal turns the puck and scores nothing", function()
		local g = active()
		g.px, g.py, g.vx, g.vy = 0.40, 1.10, 0, 7.5
		Sim.tick(g, 0.04, 0, false)
		t.truthy(g.vy < 0 and g.score0 == 0)
	end)

	t.test("his check 3: a goal is one point, once, and the countdown starts", function()
		local g = active()
		g.px, g.py, g.vx, g.vy = 0, 1.10, 0, 7.5
		Sim.tick(g, 0.04, 0, false)
		t.truthy(g.score0 == 1 and g.score1 == 0 and g.countdown > 0)
		for _ = 1, 50 do
			Sim.tick(g)
		end
		t.eq(g.score0, 1)
	end)

	t.test("his check 4: a rounded goal post is a hit, not a goal", function()
		local g = active()
		g.px, g.py, g.vx, g.vy = 0.203, 1.08, 0, 7.5
		Sim.tick(g, 0.03, 0, false)
		t.truthy(g.hitSerial > 0 and g.score0 == 0)
	end)

	t.test("his check 5: inside the slot the side walls keep the puck in the goal's width", function()
		local g = active()
		g.px, g.py, g.vx, g.vy = 0, 1.20, 7.4, 0.10
		Sim.tick(g, 0.05, 0, false)
		t.truthy(math.abs(g.px) <= Sim.GOAL - Sim.PUCK_RADIUS + 0.001 and g.score0 == 0)
	end)

	t.test("his check 6: a still mallet blocks a full-speed shot", function()
		local g = active()
		g.px, g.py, g.vx, g.vy = 0, -0.60, 0, -7.5
		Sim.tick(g, 0.03, 0, false)
		t.truthy(g.vy > 0 and g.hitSerial > 0)
	end)

	t.test("his check 7: a mallet moved through a resting puck strikes it", function()
		local g = active()
		g.px, g.py, g.vx, g.vy = 0, -0.61, 0, 0
		Sim.setTarget(g, 0, 0, -0.40)
		for _ = 1, 25 do
			Sim.tick(g, Sim.STEP, 0, false)
		end
		t.truthy(g.vy > 1 and g.py > -0.61)
	end)

	t.test("his check 8: paused, nothing moves", function()
		local g = active()
		g.paused = true
		g.vx, g.vy = 4, 3
		local x, y = g.px, g.py
		Sim.tick(g)
		t.truthy(g.px == x and g.py == y)
	end)

	t.test("his check 9: the seventh goal wins, and reset clears the match", function()
		local g = active()
		g.score0 = 6
		g.px, g.py, g.vx, g.vy = 0, 1.26, 0, 5
		Sim.tick(g, 0.01, 0, false)
		t.truthy(g.winner == 0 and g.score0 == 7)
		Sim.reset(g)
		t.truthy(g.winner == -1 and g.score0 == 0)
	end)

	t.test("his check 10: a mallet's target is kept on the table and in its own half", function()
		local g = Sim.new()
		Sim.setTarget(g, 0, 9, 9)
		t.truthy(g.t0x < 0.56 and g.t0y < 0)
		Sim.setTarget(g, 1, -9, -9)
		t.truthy(g.t1y > 0)
	end)

	t.test("his check 11: 120 seconds of play stays finite, on the table and under the speed limit", function()
		local g = Sim.new()
		local matches = 0
		for _ = 1, 240 * 120 do
			Sim.ai(g, 0)
			Sim.tick(g, Sim.STEP, 1, true)
			assert(
				g.px == g.px and g.py == g.py and math.abs(g.px) ~= math.huge and math.abs(g.py) ~= math.huge,
				"the puck is finite"
			)
			assert(Sim.hypot(g.vx, g.vy) <= g.maxSpeed + 0.001, "under the speed limit")
			assert(math.abs(g.px) < 0.621, "inside the side rails")
			if g.winner >= 0 then
				matches += 1
				Sim.reset(g)
			end
		end
		t.truthy(g.hitSerial > 50, `{g.hitSerial} contacts in two minutes`)
		t.truthy(matches >= 1, "the computer wins against a mallet that never moves")
	end)

	t.test("the same inputs give the same game twice, and a copy carries on exactly", function()
		local function play(n: number, fork: number?): (Sim.State, Sim.State?)
			local g = Sim.new()
			g.difficulty = Sim.DIFFICULTY.hard
			local other: Sim.State? = nil
			for i = 1, n do
				if i % 4 == 0 then
					Sim.setTarget(g, 0, math.sin(i * 0.013) * 0.5, -0.6 + math.sin(i * 0.031) * 0.45)
				end
				Sim.tick(g, Sim.STEP, 0, true)
				if other then
					if i % 4 == 0 then
						Sim.setTarget(other, 0, math.sin(i * 0.013) * 0.5, -0.6 + math.sin(i * 0.031) * 0.45)
					end
					Sim.tick(other, Sim.STEP, 0, true)
				end
				if i == fork then
					other = Sim.copy(Sim.new(), g)
				end
			end
			return g, other
		end
		local a, fork = play(240 * 30, 2000)
		local b = play(240 * 30)
		for _, k in Sim.FIELDS do
			t.eq((a :: any)[k], (b :: any)[k], k)
			t.eq((fork :: any)[k], (a :: any)[k], `copied at tick 2000: {k}`)
		end
		t.truthy(a.hitSerial > 0 and a.goalSerial > 0, `{a.hitSerial} contacts, {a.goalSerial} goals`)
	end)

	t.test("the serve: from the side that conceded, toward the side that scored, alternating left and right", function()
		local g = Sim.new()
		t.eq(g.py, -0.3)
		for _ = 1, 301 do
			Sim.tick(g, Sim.STEP, 0, false)
		end
		t.eq(g.countdown, 0)
		t.truthy(g.vy > 0 and g.vx > 0, "the first serve leaves Glacier's half to the right")
		-- Ember scores: Glacier conceded, so the puck is served from Glacier's half again
		g.px, g.py, g.vx, g.vy = 0, -1.2, 0, -5
		g.p0x, g.t0x = 0.5, 0.5
		Sim.tick(g, 0.05, 0, false)
		t.eq(g.score1, 1)
		t.eq(g.serveSide, 0)
		t.eq(g.py, -0.3)
		Sim.serve(g)
		t.truthy(g.vy == 1.25 and g.vx == -0.34, "after one goal the serve goes left")
		-- Glacier scores: served from Ember's half toward Glacier
		g.px, g.py, g.vx, g.vy = 0, 1.2, 0, 5
		g.p1x, g.t1x = 0.5, 0.5
		Sim.tick(g, 0.05, 0, false)
		t.eq(g.score0, 1)
		t.eq(g.py, 0.3)
		Sim.serve(g)
		t.truthy(g.vy == -1.25 and g.vx == 0.34)
	end)

	t.test("the last contact says what it was and how hard (for sound; the simulation never reads it)", function()
		local g = active()
		g.px, g.py, g.vx, g.vy = 0.5, 0, 6, 0
		Sim.tick(g, 0.05, 0, false)
		t.eq(g.hitWhat, Sim.HIT_RAIL)
		t.near(g.hitSpeed, 6, 1e-9)
		g = active()
		g.px, g.py, g.vx, g.vy = 0.203, 1.08, 0, 7.5
		Sim.tick(g, 0.03, 0, false)
		t.eq(g.hitWhat, Sim.HIT_POST)
		g = active()
		g.px, g.py, g.vx, g.vy = 0, 0.60, 0, 7.5
		Sim.tick(g, 0.03, 0, false)
		t.eq(g.hitWhat, Sim.HIT_MALLET + 1)
	end)

	t.test("not his: the rails hold. A puck his step lets out is put back on the rail and the rally goes on", function()
		-- (the golden case "flaw": his own simulation lets this puck out)
		local function pinned(): Sim.State
			local g = Sim.new()
			g.countdown = 0
			g.px, g.py, g.vx, g.vy = 0.58, -0.5, 0, 0
			g.p0x, g.p0y, g.t0x, g.t0y = 0.3, -0.5, 0.3, -0.5
			Sim.setTarget(g, 0, 0.556, -0.5)
			return g
		end
		local his = pinned()
		for _ = 1, 120 do
			Sim.tick(his, Sim.STEP, 0, false)
		end
		t.truthy(his.px > 1, `his step alone: the puck is {his.px} m out and gone`)
		local g = pinned()
		local held = 0
		for _ = 1, 40 do
			local hits = g.hitSerial
			local before = Sim.clone(g)
			Sim.tick(before, Sim.STEP, 0, false)
			t.eq(Sim.play(g, 0, false), false, "nothing is put back for a serve")
			if g.px ~= before.px or g.py ~= before.py then
				held += 1
				t.truthy(g.hitSerial > hits, "a rail that held is a contact (it is heard)")
			end
			t.truthy(math.abs(g.px) <= 0.588 + 1e-7 and math.abs(g.py) <= 1.138 + 1e-7, "on the bed at every tick")
			t.eq(Sim.offTable(g), false)
			t.eq(g.countdown <= 0, true, "no countdown: the rally goes on")
			t.truthy(Sim.hypot(g.vx, g.vy) <= g.maxSpeed + 1e-9)
		end
		t.truthy(held >= 1, "the rail held at least once")
		t.eq(g.heldSerial, held, "each time the rails held is counted (the players' screens say PINCHED)")
		t.eq(g.score0 + g.score1, 0, "nobody scores by it")
		-- the puck is clear of the mallet that pressed it
		t.truthy(Sim.hypot(g.px - g.p0x, g.py - g.p0y) >= Sim.PUCK_RADIUS + Sim.PADDLE_RADIUS - 1e-6)
		-- on the table play() is his tick and nothing else: whole matches agree
		local a, b = Sim.new(), Sim.new()
		for i = 1, 240 * 60 do
			if i % 5 == 0 then
				Sim.setTarget(a, 0, math.sin(i * 0.02) * 0.3, -0.7)
				Sim.setTarget(b, 0, math.sin(i * 0.02) * 0.3, -0.7)
			end
			Sim.tick(a, Sim.STEP, 0, true)
			t.eq(Sim.play(b, 0, true), false)
		end
		for _, k in Sim.FIELDS do
			t.eq((a :: any)[k], (b :: any)[k], k)
		end
		-- where a puck may be, and may not
		local s = Sim.new()
		for _, p in { { 0.588, 0 }, { 0, 1.138 }, { 0.188, 1.27 }, { 0.2, 1.19 }, { -0.588, -1.138 } } do
			s.px, s.py = p[1], p[2]
			t.eq(Sim.offTable(s), false, `{p[1]}, {p[2]} is on the table`)
		end
		for _, p in { { 0.588, 0 }, { 0, 1.138 }, { 0.188, 1.27 }, { 0.1, 1.2 }, { -0.588, -1.138 }, { 0.17, 1.15 } } do
			s.px, s.py = p[1], p[2]
			t.eq(Sim.contain(s), false, `{p[1]}, {p[2]} is left where it is`)
		end
		for _, p in { { 0.63, 0 }, { -0.7, 0.4 }, { 0.4, 1.18 }, { 0, 1.31 }, { -0.3, -1.2 } } do
			s.px, s.py = p[1], p[2]
			t.eq(Sim.offTable(s), true, `{p[1]}, {p[2]} is off the table`)
		end
		-- each face puts a puck back on itself, turned inward: side rails, end rails beside the goal, the walls
		-- of the goal slot and the posts
		for _, c in
			{
				{ 0.60, 0.2, 3, 1, 0.588, 0.2 },
				{ -0.61, -0.4, -2, 0, -0.588, -0.4 },
				{ 0.4, 1.16, 0, 5, 0.4, 1.138 },
				{ -0.3, -1.15, 1, -4, -0.3, -1.138 },
				{ 0.2, 1.22, 2, 1, 0.188, 1.22 },
			}
		do
			s = Sim.new()
			s.countdown = 0
			s.px, s.py, s.vx, s.vy = c[1], c[2], c[3], c[4]
			t.eq(Sim.contain(s), true)
			t.near(s.px, c[5], 1e-12)
			t.near(s.py, c[6], 1e-12)
			t.truthy(s.vx * s.px <= 0 or math.abs(s.px) < 0.18, "not back into a side rail or a slot wall")
			t.truthy(s.vy * s.py <= 0 or math.abs(s.py) < 1.13 or math.abs(s.px) < 0.22, "nor an end rail")
			t.eq(Sim.offTable(s), false)
		end
		s = Sim.new()
		s.countdown = 0
		s.px, s.py, s.vx, s.vy = 0.2, 1.15, 1, 1 -- (inside the post at 0.22, 1.17)
		t.eq(Sim.contain(s), true)
		t.near(Sim.hypot(s.px - 0.22, s.py - 1.17), 0.044, 1e-9)
	end)

	t.test("a mallet held on a resting puck at each rail and corner for three seconds never takes it off", function()
		-- (the most natural move in air hockey; his step alone loses most of these pucks)
		local lost = 0
		local cases: { { any } } = {
			{ "own end rail", 0.40, -1.138, 0.40, -1.12 },
			{ "own end rail, the pointer on the puck", 0.40, -1.138, 0.40, -1.138 },
			{ "own end rail, the other side", -0.45, -1.138, -0.45, -1.138 },
			{ "side rail", 0.588, -0.60, 0.57, -0.60 },
			{ "side rail, the pointer on the puck", 0.588, -0.60, 0.588, -0.60 },
			{ "the other side rail", -0.588, -0.30, -0.588, -0.30 },
			{ "corner", 0.588, -1.138, 0.55, -1.10 },
			{ "the other corner", -0.588, -1.138, -0.588, -1.138 },
			{ "side rail at the centre line", 0.588, -0.05, 0.588, -0.05 },
		}
		for _, c in cases do
			local his = Sim.new()
			his.countdown = 0
			his.px, his.py = c[2], c[3]
			for _ = 1, 240 * 3 do
				Sim.setTarget(his, 0, c[4], c[5])
				Sim.tick(his, Sim.STEP, 0, true)
				if Sim.offTable(his) then
					lost += 1
					break
				end
			end
			local g = Sim.new()
			g.countdown = 0
			g.px, g.py = c[2], c[3]
			local serves = 0
			for tick = 1, 240 * 3 do
				Sim.setTarget(g, 0, c[4], c[5])
				local goals, bx, by = g.goalSerial, g.px, g.py
				if Sim.play(g, 0, true) then
					serves += 1
				end
				t.eq(Sim.offTable(g), false, `{c[1]}: on the table at tick {tick}`)
				if g.goalSerial == goals then
					t.truthy(
						Sim.hypot(g.px - bx, g.py - by) < 0.2,
						`{c[1]}: the puck is not thrown across the table (tick {tick})`
					)
				end
			end
			t.eq(serves, 0, `{c[1]}: never re-served`)
		end
		t.truthy(lost >= 5, `his step alone loses most of them ({lost} of {#cases}): the case that needed the rule`)
	end)

	t.test("fold and hypot are JavaScript's", function()
		t.near(Sim.fold(0.7, 0.588), 0.476, 1e-12)
		t.near(Sim.fold(-0.7, 0.588), -0.476, 1e-12)
		t.near(Sim.fold(2.5, 0.588), Sim.fold(2.5 - 4 * 0.588, 0.588), 1e-12)
		t.eq(Sim.hypot(3, 4), 5)
		t.eq(Sim.hypot(0, 0), 0)
		t.eq(Sim.hypot(-0.3, 0), 0.3)
	end)
end
