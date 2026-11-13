--!strict
-- The owner's own checks of his air hockey simulation (docs/reference/air_hockey/physics_tests.cpp), ported one
-- for one against Shared/Minigames/AirHockey/Sim: fast rail shots, end rails, a goal scored exactly once, the
-- rounded goal posts, the goal slot's side walls, still and moving mallets, pause, match reset, mallet bounds
-- and 120 seconds of play that stays finite, on the table and under the speed limit. Then what the port adds
-- for itself: determinism, the serve, what the last contact was.
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

	t.test("not his: a puck pressed out of the table is put back for a serve, outside his step", function()
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
		local back = 0
		for _ = 1, 120 do
			if Sim.play(g, 0, false) then
				back += 1
				t.eq(g.py, -0.3)
				t.eq(g.countdown, Sim.COUNTDOWN)
			end
			assert(math.abs(g.px) <= Sim.HALF_WIDTH + 0.04, "never drawn far off the table")
		end
		t.eq(back, 1)
		t.eq(g.score0 + g.score1, 0, "nobody scores by it")
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
		for _, p in { { 0.63, 0 }, { -0.7, 0.4 }, { 0.4, 1.18 }, { 0, 1.31 }, { -0.3, -1.2 } } do
			s.px, s.py = p[1], p[2]
			t.eq(Sim.offTable(s), true, `{p[1]}, {p[2]} is off the table`)
		end
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
