--!strict
-- Minigames/Bowling/LaneCycle and Intruders: the lane's cycle (ready, rolling, counted, the pinsetter, ready
-- again) with its timing, the result taken exactly once, what stands for the next ball, the poses the server
-- writes onto the parts; and the rule for a squirrel on the lane (bowled into the gutter, the throw counts).
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local BallPath = require("@shared/Minigames/Bowling/BallPath")
local Intruders = require("@shared/Minigames/Bowling/Intruders")
local LaneCycle = require("@shared/Minigames/Bowling/LaneCycle")
local PinModel = require("@shared/Minigames/Bowling/PinModel")
local RollScript = require("@shared/Minigames/Bowling/RollScript")

local THIN = { offset = 0.5, angle = 0, power = 0.7, spin = 0 } -- leaves pins standing
local CENTRE = { offset = 0, angle = 0, power = 0.7, spin = 0 }

-- step until an event (or a limit); returns the events seen and the seconds it took
local function runUntil(c: LaneCycle.Cycle, want: string, dt: number, limit: number?): ({ string }, number)
	local seen: { string } = {}
	local t = 0
	while t < (limit or 30) do
		t += dt
		for _, e in LaneCycle.step(c, dt) do
			table.insert(seen, e)
			if e == want then
				return seen, t
			end
		end
	end
	return seen, t
end

return function(t)
	t.test("a whole cycle: release, impact, counted, the pinsetter, ready; the result is taken once", function()
		local c = LaneCycle.new()
		t.truthy(LaneCycle.ready(c))
		t.eq(LaneCycle.standingCount(c), 10)
		t.eq(LaneCycle.take(c), nil)
		local script = RollScript.build(THIN, LaneCycle.mask(c), 4)
		t.truthy(script.down > 0 and script.down < 10, `the thin ball took {script.down}`)
		t.truthy(LaneCycle.release(c, script, 2))
		t.falsy(LaneCycle.ready(c))
		t.eq(c.phase, "rolling")
		-- nothing can be released, taken or (without instant) set while it rolls
		local again, why = LaneCycle.release(c, script, 2)
		t.falsy(again)
		t.truthy(type(why) == "string" and #(why :: string) > 10, "a refusal says why")
		t.eq(LaneCycle.take(c), nil)
		t.falsy(LaneCycle.set(c, "keep"))
		local seen, took = runUntil(c, "counted", 1 / 60)
		t.deepEq(seen, { "impact", "counted" })
		t.near(took, script.tEnd + LaneCycle.SETTLE, 0.03)
		t.eq(c.phase, "counted")
		local r = LaneCycle.take(c) :: LaneCycle.Result
		t.eq(r.pins, script.down)
		t.eq(r.seat, 2)
		t.deepEq(r.standing, script.standing)
		t.eq(r.flags.gutter, false)
		t.eq(LaneCycle.take(c), nil, "only once")
		-- waiting for the rack order: nothing moves on by itself
		t.eq(#LaneCycle.step(c, 5), 0)
		t.eq(c.phase, "counted")
		t.truthy(LaneCycle.set(c, "keep"))
		t.eq(c.phase, "setting")
		t.falsy(LaneCycle.release(c, script, 2), "not during the pinsetter")
		local seen2, took2 = runUntil(c, "ready", 1 / 60)
		t.deepEq(seen2, { "ready" })
		t.near(took2, LaneCycle.TURNAROUND, 0.03)
		t.truthy(LaneCycle.ready(c))
		t.deepEq(LaneCycle.mask(c), script.standing, "keep: exactly what was left")
		t.eq(LaneCycle.standingCount(c), 10 - script.down)
		-- the whole turnaround, ball in hand to ball in hand, stays brisk
		t.truthy(took + took2 < 9, `a throw and its reset take {took + took2} s`)
		-- the second ball must be built for what stands
		local wrong = RollScript.build(CENTRE, PinModel.fullRack(), 1)
		local bad, badWhy = LaneCycle.release(c, wrong, 2)
		t.falsy(bad)
		t.truthy(string.find(badWhy :: string, "rack", 1, true) ~= nil)
		local second = RollScript.build(CENTRE, LaneCycle.mask(c), 5)
		t.truthy(LaneCycle.release(c, second, 2))
		runUntil(c, "counted", 0.1)
		t.truthy(LaneCycle.take(c) ~= nil)
		t.truthy(LaneCycle.set(c, "full"))
		runUntil(c, "ready", 0.1)
		t.eq(LaneCycle.standingCount(c), 10, "full: ten fresh pins")
	end)

	t.test("coarse steps never lose an event; reset abandons a throw in flight", function()
		for _, dt in { 0.1, 0.2, 0.5 } do
			local c = LaneCycle.new()
			local script = RollScript.build(CENTRE, LaneCycle.mask(c), 7)
			LaneCycle.release(c, script, 1)
			local seen = runUntil(c, "counted", dt)
			t.deepEq(seen, { "impact", "counted" }, `dt {dt}`)
			t.eq((LaneCycle.take(c) :: LaneCycle.Result).pins, script.down)
			LaneCycle.set(c, "full")
			t.deepEq((runUntil(c, "ready", dt)), { "ready" })
		end
		local c = LaneCycle.new()
		LaneCycle.release(c, RollScript.build(CENTRE, LaneCycle.mask(c), 7), 1)
		LaneCycle.step(c, 1.0)
		LaneCycle.reset(c)
		t.truthy(LaneCycle.ready(c))
		t.eq(LaneCycle.standingCount(c), 10)
		t.eq(LaneCycle.take(c), nil)
		t.eq(#LaneCycle.step(c, 10), 0, "no stale result turns up later")
		t.eq(LaneCycle.scriptTime(c), nil)
		-- an instant rack order (the session ended mid-throw) also leaves a clean lane
		LaneCycle.release(c, RollScript.build(THIN, LaneCycle.mask(c), 4), 1)
		runUntil(c, "counted", 0.1)
		t.truthy(LaneCycle.set(c, "keep", true))
		t.truthy(LaneCycle.ready(c))
		t.truthy(LaneCycle.standingCount(c) < 10)
		LaneCycle.reset(c)
		t.eq(LaneCycle.standingCount(c), 10)
	end)

	t.test(
		"poses while rolling: the ball leaves the rack, runs the lane, ends in the pit; pins follow the script",
		function()
			local c = LaneCycle.new()
			local idle = LaneCycle.pose(c)
			t.eq(idle.ball.where, "rack")
			t.eq(#idle.pins, 10)
			for n = 1, 10 do
				local sx, sd = PinModel.spot(n)
				t.truthy(idle.pins[n].x == sx and idle.pins[n].d == sd and not idle.pins[n].hidden)
			end
			t.near(idle.sweep.y, LaneCycle.SWEEP_REST, 1e-9)
			local script = RollScript.build(THIN, LaneCycle.mask(c), 4)
			LaneCycle.release(c, script, 1)
			local p0 = LaneCycle.pose(c)
			t.eq(p0.ball.where, "hand")
			t.near(p0.ball.d, BallPath.RELEASE_D, 0.001)
			LaneCycle.step(c, 1.0)
			t.near(LaneCycle.scriptTime(c) :: number, 1.0, 1e-9)
			local p1 = LaneCycle.pose(c)
			t.eq(p1.ball.where, "lane")
			t.truthy(p1.ball.d > 20 and p1.ball.d < 35)
			runUntil(c, "counted", 1 / 30)
			local p2 = LaneCycle.pose(c)
			t.eq(p2.ball.where, "pit")
			local lying, upright = 0, 0
			for n = 1, 10 do
				if script.standing[n] then
					upright += 1
					t.eq(p2.pins[n].tilt, 0)
				else
					lying += 1
					t.near(p2.pins[n].tilt, math.pi / 2, 1e-9)
				end
			end
			t.eq(lying, script.down)
			t.eq(upright, 10 - script.down)
		end
	)

	t.test(
		"the pinsetter: a pause, the bar comes down and through, kept pins are lifted and set back, deadwood goes",
		function()
			local c = LaneCycle.new()
			local script = RollScript.build(THIN, LaneCycle.mask(c), 4)
			LaneCycle.release(c, script, 1)
			runUntil(c, "counted", 1 / 30)
			LaneCycle.take(c)
			local before = LaneCycle.pose(c)
			LaneCycle.set(c, "keep")
			-- the pause: everything exactly as it lay, the bar still up
			LaneCycle.step(c, LaneCycle.PAUSE * 0.5)
			local paused = LaneCycle.pose(c)
			for n = 1, 10 do
				t.near(paused.pins[n].x, before.pins[n].x, 1e-9)
				t.near(paused.pins[n].d, before.pins[n].d, 1e-9)
				t.eq(paused.pins[n].hidden, before.pins[n].hidden)
			end
			t.near(paused.sweep.y, LaneCycle.SWEEP_REST, 1e-9)
			-- through the cycle
			local lowSeen, farSeen, liftSeen = false, false, 0
			local lastSweepD = paused.sweep.d
			local ballU = -1
			local returned = false
			local tt = LaneCycle.PAUSE * 0.5
			while c.phase == "setting" do
				LaneCycle.step(c, 1 / 60)
				tt += 1 / 60
				if c.phase ~= "setting" then
					break
				end
				local p = LaneCycle.pose(c)
				t.truthy(math.abs(p.sweep.d - lastSweepD) < 0.6, "the bar does not teleport")
				lastSweepD = p.sweep.d
				lowSeen = lowSeen or p.sweep.y <= LaneCycle.SWEEP_LOW + 1e-6
				farSeen = farSeen or p.sweep.d >= LaneCycle.SWEEP_D1 - 0.05
				for n = 1, 10 do
					local pin = p.pins[n]
					if script.standing[n] then
						t.eq(pin.hidden, false, "a kept pin is never hidden")
						t.eq(pin.tilt, 0)
						liftSeen = math.max(liftSeen, pin.y)
						-- the bar never passes through a kept pin: when it is under the pin's spot the pin is up
						if p.sweep.y < 1.5 and math.abs(p.sweep.d - pin.d) < 0.3 then
							t.truthy(pin.y > 1.5, `pin {n} is clear of the bar ({pin.y})`)
						end
					elseif not pin.hidden then
						t.truthy(pin.d >= before.pins[n].d - 1e-9, "deadwood is only ever pushed toward the pit")
					end
				end
				if p.ball.where == "return" then
					t.truthy(p.ball.u >= ballU, "the ball only runs homeward")
					ballU = p.ball.u
				elseif ballU >= 0 then
					returned = true
					t.eq(p.ball.where, "rack")
				end
			end
			t.truthy(lowSeen and farSeen, "the bar came down and went all the way through")
			t.near(liftSeen, LaneCycle.LIFT, 0.01)
			t.truthy(ballU > 0.95 and returned, "the ball ran home and sits on the rack")
			t.truthy(LaneCycle.ready(c))
			local after = LaneCycle.pose(c)
			for n = 1, 10 do
				t.eq(after.pins[n].hidden, not script.standing[n])
				t.eq(after.pins[n].y, 0)
				t.eq(after.pins[n].tilt, 0)
			end
			t.near(after.sweep.y, LaneCycle.SWEEP_REST, 1e-9)
			-- the bar's own schedule
			local y0, d0, low0 = LaneCycle.sweepAt(0)
			t.truthy(y0 == LaneCycle.SWEEP_REST and d0 == LaneCycle.SWEEP_D0 and not low0)
			local _, dMid, lowMid = LaneCycle.sweepAt(0.9)
			t.truthy(lowMid and dMid > LaneCycle.SWEEP_D0 + 1 and dMid < LaneCycle.SWEEP_D1 - 1)
			local yEnd = LaneCycle.sweepAt(LaneCycle.SET_TIME)
			t.near(yEnd, LaneCycle.SWEEP_REST, 1e-9)
		end
	)

	t.test("a fresh rack: everything left is swept, ten pins come down onto their spots", function()
		local c = LaneCycle.new()
		local script = RollScript.build(THIN, LaneCycle.mask(c), 4)
		LaneCycle.release(c, script, 1)
		runUntil(c, "counted", 1 / 30)
		LaneCycle.set(c, "full")
		LaneCycle.step(c, LaneCycle.PAUSE + 1.35)
		local mid = LaneCycle.pose(c)
		for n = 1, 10 do
			t.truthy(mid.pins[n].hidden, `pin {n} is gone once the bar has been through`)
		end
		LaneCycle.step(c, 0.4)
		local lowering = LaneCycle.pose(c)
		for n = 1, 10 do
			t.falsy(lowering.pins[n].hidden)
			t.truthy(lowering.pins[n].y > 0.2 and lowering.pins[n].y < LaneCycle.LIFT)
			t.eq(lowering.pins[n].tilt, 0)
		end
		runUntil(c, "ready", 1 / 30)
		t.eq(LaneCycle.standingCount(c), 10)
		-- re-racking a ready lane that still shows a leave (a skipped frame): the same cycle, no ball to fetch
		local c2 = LaneCycle.new()
		LaneCycle.release(c2, RollScript.build(THIN, LaneCycle.mask(c2), 4), 1)
		runUntil(c2, "counted", 0.1)
		LaneCycle.set(c2, "keep")
		runUntil(c2, "ready", 0.1)
		t.truthy(LaneCycle.standingCount(c2) < 10)
		t.truthy(LaneCycle.set(c2, "full"))
		t.eq(c2.phase, "setting")
		LaneCycle.step(c2, 1.0)
		t.eq(LaneCycle.pose(c2).ball.where, "rack")
		runUntil(c2, "ready", 0.1)
		t.eq(LaneCycle.standingCount(c2), 10)
	end)

	t.test("a scripted pinfall runs the same cycle with the ball left on its rack", function()
		local c = LaneCycle.new()
		t.truthy(LaneCycle.release(c, RollScript.fake(LaneCycle.mask(c), 9), 3))
		local seen = runUntil(c, "counted", 0.1)
		t.deepEq(seen, { "impact", "counted" })
		t.eq(LaneCycle.pose(c).ball.where, "rack")
		local r = LaneCycle.take(c) :: LaneCycle.Result
		t.eq(r.pins, 9)
		t.eq(r.seat, 3)
		LaneCycle.set(c, "keep")
		LaneCycle.step(c, 1.0)
		t.eq(LaneCycle.pose(c).ball.where, "rack")
		runUntil(c, "ready", 0.1)
		t.eq(LaneCycle.standingCount(c), 1)
	end)

	t.test(
		"a squirrel on the lane is bowled into the gutter; the next lane and the duct below are left alone",
		function()
			t.truthy(Intruders.onLane(0, 0.5, 30))
			t.truthy(Intruders.onLane(2.4, -0.2, 30), "the gutter counts")
			t.truthy(Intruders.onLane(0.5, 0.6, 57), "so does the pin deck")
			t.falsy(Intruders.onLane(0, 0.5, -3), "the approach is not the lane")
			t.falsy(Intruders.onLane(AlleyLayout.PITCH, 0.5, 30), "the next lane is its own")
			t.falsy(Intruders.onLane(0, -2, 30), "the ball-return duct under the floor is not the lane")
			t.falsy(Intruders.onLane(0, 5, 57), "nor is the top of the machine")
			local script = RollScript.build(CENTRE, PinModel.fullRack(), 3)
			local animals = {
				{ id = "on", x = 0.3, y = 0.5, d = 30 },
				{ id = "wide", x = 1.8, y = 0.5, d = 30 },
				{ id = "next", x = AlleyLayout.PITCH, y = 0.5, d = 30 },
				{ id = "duct", x = 0, y = -2, d = 30 },
				{ id = "approach", x = 0, y = 0.5, d = -3 },
			}
			local knocks = Intruders.struck(script, 0, script.tEnd, animals)
			t.eq(#knocks, 1, "only the one in the ball's way")
			t.eq(knocks[1].id, "on")
			t.near(knocks[1].x, Intruders.GUTTER_X, 1e-9, "into the gutter on its own side of the ball")
			t.truthy(knocks[1].d < 30 and knocks[1].d > AlleyLayout.FOUL_D)
			t.truthy(math.abs(knocks[1].x) > AlleyLayout.LANE_W / 2, "off the bed")
			-- only in the slice of time the ball is there, and found even with a coarse server step
			local tAt = 0
			for i = 0, 300 do
				local _, _, d = RollScript.ball(script, i / 100)
				if d >= 30 then
					tAt = i / 100
					break
				end
			end
			t.eq(#Intruders.struck(script, 0, tAt - 0.3, animals), 0)
			t.eq(#Intruders.struck(script, tAt - 0.1, tAt + 0.1, animals), 1)
			t.eq(#Intruders.struck(script, tAt + 0.3, script.tEnd, animals), 0)
			-- one on the left goes left; one among the pins is put back short of them
			local left = Intruders.struck(script, 0, script.tEnd, { { id = "l", x = -0.4, y = 0.5, d = 20 } })
			t.near(left[1].x, -Intruders.GUTTER_X, 1e-9)
			local deck = Intruders.struck(script, 0, script.tEnd, { { id = "p", x = 0.2, y = 0.5, d = 55.5 } })
			t.eq(#deck, 1)
			t.truthy(deck[1].d <= AlleyLayout.DECK_START - 2.5 + 1e-9)
			-- a gutter ball takes one sitting in the channel; a scripted pinfall has no ball to hit anything
			local gutter = RollScript.build({ offset = 1, angle = 0.1, power = 0.7, spin = 0 }, PinModel.fullRack(), 1)
			t.eq(
				#Intruders.struck(gutter, 0, gutter.tEnd, { { id = "g", x = Intruders.GUTTER_X, y = -0.1, d = 40 } }),
				1
			)
			t.eq(#Intruders.struck(RollScript.fake(PinModel.fullRack(), 5), 0, 1, animals), 0)
			-- the sweep bar clears the deck of anything at floor level it passes
			local onDeck = {
				{ id = "d", x = -0.5, y = 0.5, d = 57 },
				{ id = "far", x = 0, y = 0.5, d = 30 },
				{ id = "high", x = 0, y = 2.5, d = 57 },
			}
			local swept = Intruders.swept(56.5, 57.4, onDeck)
			t.eq(#swept, 1)
			t.eq(swept[1].id, "d")
			t.near(swept[1].x, -Intruders.GUTTER_X, 1e-9)
			t.truthy(swept[1].d < AlleyLayout.DECK_START - 2)
			t.eq(#Intruders.swept(60, 61, onDeck), 0)
			-- every knock lands off the bed, short of the deck and past the foul line
			for i = 1, 40 do
				local x, d = Intruders.knockTo((i % 9 - 4) * 0.6, i * 1.6, (i % 5 - 2) * 0.5)
				t.truthy(
					math.abs(x) > AlleyLayout.LANE_W / 2 and math.abs(x) < AlleyLayout.LANE_W / 2 + AlleyLayout.GUTTER_W
				)
				t.truthy(d >= AlleyLayout.FOUL_D + 2 and d <= AlleyLayout.DECK_START - 2.5)
			end
			t.truthy(#Intruders.TEXT.bowlers > 20 and #Intruders.TEXT.animal > 10)
		end
	)
end
