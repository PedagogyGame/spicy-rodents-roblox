--!strict
-- Minigames/Pinball/Physics: "real flipper physics" (checklist PIN-P1, PIN-P2), measured, not asserted:
--   P1 the flipper is a rotating body: it moves in the tick the button goes down, takes 40 to 50 ms over its
--      stroke and falls back slower; the ball takes its speed from the flipper's surface where they meet, so
--      a ball far out on the flipper is hit harder than one near the pivot, and WHERE the ball is when you
--      flip sets the angle: near the pivot back up the same side, near the tip across the table, rising
--      steadily between (the calibrate tool prints the same table);
--   P2 a held flipper is a solid slope: a ball rolls into the cradle and comes to rest there; letting go lets
--      it roll down the flipper for an aimed shot; a flip timed so the flipper reaches its stop as a falling
--      ball lands deadens the ball (a live catch).
-- Nothing here is scripted in the model: it all falls out of the collision with a moving surface.
local Layout = require("@shared/Minigames/Pinball/Layout")
local Machine = require("@shared/Minigames/Pinball/Machine")
local Physics = require("@shared/Minigames/Pinball/Physics")
local Tables = require("@shared/Minigames/Pinball/Tables")
local Test = require("../lib/Test")

local tbl = Tables.need("pinball_acorn")
local c = tbl.c
local LEFT, RIGHT = 1, 2

local function clone(s: Physics.State): Physics.State
	local m = Machine.new(tbl, 1, 1)
	m.phys = s
	return Machine.clone(m).phys
end

-- along the resting flipper i: 0 at the pivot, 1 at the tip
local function alongOf(i: number, b: Physics.Ball): number
	local a = c.frest[i]
	return ((b.x - c.fpx[i]) * c.fmir[i] * math.cos(a) + (b.y - c.fpy[i]) * math.sin(a)) / c.flen[i]
end

-- a ball rolled down the inlane into the cradle of flipper i, held up; returns the state once it is at rest
local function cradle(i: number): (Physics.State, number)
	local s = Physics.new(c, 1)
	local ev: { number } = {}
	local lane = tbl.def.sensors[if i == LEFT then tbl.ix.sensor.inlane_l else tbl.ix.sensor.inlane_r]
	Physics.addBall(s, (lane.x1 + lane.x2) / 2, lane.y1 + 0.2, 0, 0)
	for tick = 1, 240 * 8 do
		Physics.step(c, s, i == LEFT, i == RIGHT, ev)
		if s.balls[1].asleep then
			return s, tick
		end
	end
	return s, -1
end

type Shot = { along: number, angle: number, speed: number }

-- let the cradled ball go, wait `delay` ticks, flip: where on the flipper it was, and how it left
-- (angle in degrees from straight up the table, + toward the far side of the table)
local function shot(base: Physics.State, i: number, delay: number): Shot?
	local s = clone(base)
	local ev: { number } = {}
	local b = s.balls[1]
	for _ = 1, delay do
		Physics.step(c, s, false, false, ev)
	end
	local along = alongOf(i, b)
	for _ = 1, 200 do
		Physics.step(c, s, i == LEFT, i == RIGHT, ev)
		if b.mode ~= Physics.FREE then
			return nil
		end
		if b.y > c.fpy[i] + 0.4 and b.vy > 0 then
			return {
				along = along,
				angle = math.deg(math.atan2(b.vx * c.fmir[i], b.vy)),
				speed = math.sqrt(b.vx * b.vx + b.vy * b.vy),
			}
		end
	end
	return nil
end

return function(t: Test.T)
	t.test(
		"PIN-P1: the flipper moves in the tick the button goes down and takes 40 to 50 ms over its stroke",
		function()
			local s = Physics.new(c, 1)
			local ev: { number } = {}
			Physics.step(c, s, true, false, ev)
			t.truthy(s.fa[LEFT] > c.frest[LEFT], "the left flipper has moved after one tick")
			t.eq(s.fa[RIGHT], c.frest[RIGHT], "the right one has not")
			t.eq(ev[1], Physics.EV.FLIP_UP)
			local ticks = 1
			while s.fa[LEFT] < c.fup[LEFT] and ticks < 100 do
				Physics.step(c, s, true, false, ev)
				ticks += 1
			end
			local ms = ticks / Physics.HZ * 1000
			t.truthy(ms >= 40 and ms <= 50, `stroke {ms} ms`)
			-- it bounces a little off its stop and settles there
			for _ = 1, 60 do
				Physics.step(c, s, true, false, ev)
			end
			t.eq(s.fa[LEFT], c.fup[LEFT])
			t.eq(s.fw[LEFT], 0)
			-- and falls back slower, under its spring
			local down = 0
			while s.fa[LEFT] > c.frest[LEFT] and down < 200 do
				Physics.step(c, s, false, false, ev)
				down += 1
			end
			t.truthy(down >= ticks * 1.5, `fall {down} ticks against a stroke of {ticks}`)
			t.truthy(down / Physics.HZ < 0.15, "but is back within 150 ms")
		end
	)

	t.test(
		"PIN-P1: the two flippers are a mirrored pair, each on its own button; a tilted machine's are dead",
		function()
			local s = Physics.new(c, 1)
			local ev: { number } = {}
			for _ = 1, 30 do
				Physics.step(c, s, false, true, ev)
			end
			t.eq(s.fa[LEFT], c.frest[LEFT])
			t.eq(s.fa[RIGHT], c.fup[RIGHT])
			local lx, ly = Physics.flipperTip(c, s, LEFT)
			local rx, ry = Physics.flipperTip(c, s, RIGHT)
			t.truthy(ry > ly + 0.2, "the right tip is up")
			t.truthy(rx > lx, "and they point at each other")
			s.dead = true
			for _ = 1, 60 do
				Physics.step(c, s, true, true, ev)
			end
			t.eq(s.fa[LEFT], c.frest[LEFT], "dead: the left stays down")
			t.eq(s.fa[RIGHT], c.frest[RIGHT], "dead: the right falls")
		end
	)

	t.test(
		"PIN-P1: the flipper never leaves its stops, however the button is worked; a short tap is a short flick",
		function()
			local s = Physics.new(c, 1)
			local ev: { number } = {}
			local seed = 9
			local pressed = false
			for _ = 1, 20000 do
				seed = (seed * 69069 + 1) % 4294967296
				if seed % 9 < 2 then
					pressed = not pressed
				end
				Physics.step(c, s, pressed, not pressed, ev)
				for i = 1, 2 do
					t.truthy(s.fa[i] >= c.frest[i] and s.fa[i] <= c.fup[i], `flipper {i} at {s.fa[i]}`)
				end
			end
			-- a tap of 20 ms: the flipper flicks part of the way and falls back
			local tap = Physics.new(c, 1)
			local top = c.frest[LEFT]
			for tick = 1, 80 do
				Physics.step(c, tap, tick <= 5, false, ev)
				top = math.max(top, tap.fa[LEFT])
			end
			local share = (top - c.frest[LEFT]) / (c.fup[LEFT] - c.frest[LEFT])
			t.truthy(share > 0.25 and share < 0.75, `a tap lifts it {share} of the way`)
			t.eq(tap.fa[LEFT], c.frest[LEFT], "and it is back down")
		end
	)

	t.test("PIN-P2: a held flipper is a solid slope: a ball rolls into the cradle, comes to rest and stays", function()
		for _, i in { LEFT, RIGHT } do
			local s, tick = cradle(i)
			t.truthy(tick > 0, "the ball came to rest")
			t.truthy(tick < 240 * 5, `within five seconds ({tick / 240})`)
			local b = s.balls[1]
			-- at the low end of the raised flipper, by the pivot
			local along = alongOf(i, b)
			t.truthy(along > -0.3 and along < 0.35, `cradled near the pivot ({along})`)
			t.truthy(b.y > c.fpy[i], "above the pivot")
			local ev: { number } = {}
			local x, y = b.x, b.y
			for _ = 1, 240 * 5 do
				Physics.step(c, s, i == LEFT, i == RIGHT, ev)
			end
			t.eq(b.x, x, "it does not creep")
			t.eq(b.y, y)
		end
	end)

	t.test("PIN-P2: letting go of a cradled ball lets it roll down the flipper to the tip and off", function()
		local base = cradle(LEFT)
		local s = clone(base)
		local ev: { number } = {}
		local b = s.balls[1]
		local last = alongOf(LEFT, b)
		local reached = 0
		for tick = 1, 400 do
			Physics.step(c, s, false, false, ev)
			if b.mode ~= Physics.FREE then
				break
			end
			local along = alongOf(LEFT, b)
			if tick > 40 and along < 1 then
				t.truthy(along >= last - 1e-6, "it rolls toward the tip")
			end
			last = along
			if along >= 1 and reached == 0 then
				reached = tick
			end
		end
		t.truthy(reached > 120 and reached < 360, `it takes a moment to roll down ({reached} ticks): time to choose`)
		t.eq(b.mode, Physics.GONE, "and not flipped, it drains")
	end)

	t.test(
		"PIN-P1: where the ball is on the flipper when you flip sets the angle, steadily: pivot same side, tip across",
		function()
			for _, i in { LEFT, RIGHT } do
				local base = cradle(i)
				local shots: { Shot } = {}
				for delay = 40, 240, 4 do
					local sh = shot(base, i, delay)
					if sh and sh.along > 0.05 and sh.along < 1.0 then
						table.insert(shots, sh)
					end
				end
				t.truthy(#shots >= 20, `enough shots ({#shots})`)
				-- steadily: the angle never falls back by more than a couple of degrees as the ball rolls out
				local high = -180
				for _, sh in shots do
					t.truthy(sh.angle > high - 2.5, `at {sh.along} the angle {sh.angle} fell back from {high}`)
					high = math.max(high, sh.angle)
				end
				local first, last = shots[1], shots[#shots]
				t.truthy(first.angle < -8, `near the pivot the ball goes back up its own side ({first.angle})`)
				t.truthy(last.angle > 8, `near the tip it goes across the table ({last.angle})`)
				t.truthy(last.angle - first.angle > 25, "a real spread of shots")
				-- timing aims: one frame (4 ticks) sooner or later is a different shot out at the tip
				local a, b = shots[#shots - 1], shots[#shots]
				t.truthy(math.abs(a.angle - b.angle) > 0.5, "the last two differ")
			end
		end
	)

	t.test(
		"PIN-P1: timing aims finely: tick by tick the angle moves on smoothly, never in jumps and never back",
		function()
			-- every tick of delay from the pivot to the tip: one tick later is at most a couple of degrees on,
			-- so any spot on the table that a flipper can reach at all can be reached by timing alone
			local base = cradle(LEFT)
			local shots: { Shot } = {}
			for delay = 40, 260 do
				local sh = shot(base, LEFT, delay)
				if sh and sh.along > 0.02 and sh.along < 0.97 then
					table.insert(shots, sh)
				end
			end
			t.truthy(#shots > 80, `a shot for every tick ({#shots})`)
			local worst = 0
			for k = 2, #shots do
				local step = shots[k].angle - shots[k - 1].angle
				t.truthy(step > -0.3, `at {shots[k].along} the angle fell back by {-step} degrees`)
				worst = math.max(worst, step)
			end
			t.truthy(worst < 3, `the largest step from one tick to the next is {worst} degrees`)
			t.truthy(shots[#shots].angle - shots[1].angle > 35, "over a spread of more than 35 degrees")
		end
	)

	t.test(
		"PIN-P1: a ball lying on the flipper is pushed, not hit: it leaves with the surface, without a rattle",
		function()
			local base = cradle(LEFT)
			local s = clone(base)
			local ev: { number } = {}
			for _ = 1, 150 do
				Physics.step(c, s, false, false, ev)
			end
			table.clear(ev)
			local b = s.balls[1]
			for _ = 1, 14 do
				Physics.step(c, s, true, false, ev)
			end
			local hits = 0
			for k = 1, #ev, 4 do
				if ev[k] == Physics.EV.FLIPPER then
					hits += 1
				end
			end
			t.eq(hits, 0, "no impact is heard: the flipper carried the ball")
			t.truthy(b.vy > 8, `and threw it up the table ({b.vy})`)
		end
	)

	t.test(
		"PIN-P1: the ball's speed comes from the flipper's surface: further out is harder, and never more than the tip can give",
		function()
			local base = cradle(LEFT)
			local near: Shot?, far: Shot? = nil, nil
			for delay = 40, 240, 4 do
				local sh = shot(base, LEFT, delay)
				if sh then
					if near == nil and sh.along > 0.05 then
						near = sh
					end
					if sh.along < 0.55 then
						far = sh
					end
				end
			end
			assert(near and far, "both shots left the flipper")
			t.truthy(far.along > near.along + 0.3)
			t.truthy(far.speed > near.speed * 1.5, `{far.speed} out on the flipper against {near.speed} by the pivot`)
			-- the surface out at the tip moves at reach * top angular speed; a ball cannot leave faster than
			-- that surface plus its own bounce off it
			local tip = Physics.FLIP_W_MAX * (c.flen[LEFT] + c.frt[LEFT])
			t.truthy(far.speed < tip * (1 + Physics.FLIP_E), `{far.speed} is within what a {tip} studs/s tip can give`)
			t.truthy(far.speed > 8, "and is a proper shot: enough to reach the top of the table")
			t.truthy(far.speed * far.speed / (2 * c.gravity) > Layout.LENGTH - 1)
		end
	)

	t.test("PIN-P1: left and right flippers shoot mirror images of each other", function()
		local l, r = cradle(LEFT), cradle(RIGHT)
		for _, delay in { 70, 95, 120, 145 } do
			local a, b = shot(l, LEFT, delay), shot(r, RIGHT, delay)
			assert(a and b, "both shots left the flipper")
			t.near(a.along, b.along, 0.01)
			t.near(a.angle, b.angle, 1.0, `delay {delay}`)
			t.near(a.speed, b.speed, 0.3)
		end
	end)

	t.test(
		"PIN-P2: a live catch: a flip timed so the flipper reaches its stop as the ball lands deadens the ball",
		function()
			-- a ball falls from up the table onto the middle of the left flipper; how far does it hop off the
			-- raised flipper's face afterwards?
			local up = c.fup[LEFT]
			local nx, ny = -math.sin(up), math.cos(up)
			local function hop(flipAt: number): (number, number)
				local s = Physics.new(c, 1)
				local ev: { number } = {}
				local i = Physics.addBall(s, c.fpx[LEFT] + 0.2, 2.2, 0, 0)
				local b = s.balls[i]
				local landed, high = 0, 0
				for tick = 1, 420 do
					local vy = b.vy
					Physics.step(c, s, tick >= flipAt, false, ev)
					if landed == 0 then
						if b.vy > vy + 0.5 then
							landed = tick
						end
					elseif tick <= landed + 60 and b.mode == Physics.FREE then
						local off = (b.x - c.fpx[LEFT]) * nx + (b.y - c.fpy[LEFT]) * ny - Layout.BALL_R - c.frb[LEFT]
						high = math.max(high, off)
					end
				end
				return high, landed
			end
			-- on a flipper held up all along it bounces
			local held, landsAt = hop(1)
			t.truthy(held > 0.1, `it hops off a held flipper ({held})`)
			-- flipped so the stroke ends as it lands, the flipper is on the recoil and takes the bounce out
			local best, window = math.huge, 0
			for flipAt = landsAt - 24, landsAt - 6 do
				local high = hop(flipAt)
				best = math.min(best, high)
				if high < held * 0.5 then
					window += 1
				end
			end
			t.truthy(best < held * 0.35, `the best catch leaves under a third of the hop ({best} of {held})`)
			t.truthy(window >= 2, `the window is at least two ticks wide ({window})`)
			t.truthy(window <= 8, `and it takes timing ({window})`)
			-- flipped late, into the falling ball, it is a hit, not a catch
			local late = hop(landsAt - 3)
			t.truthy(late > held * 2, "a late flip bats it away")
		end
	)
end
