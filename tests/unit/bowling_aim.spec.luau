--!strict
-- Minigames/Bowling/AimModel and Shots: the bowler's aiming state (where you stand, the target arrow and the angle
-- through the two, keys, mouse, stick, hook notches, the power meter, a refused throw handing the controls straight
-- back) with the words on screen; and the camera's shots
-- (behind the bowler, behind the ball, one cut to the pins timed from the throw, then done) always inside
-- the room.
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local AimModel = require("@shared/Minigames/Bowling/AimModel")
local BallPath = require("@shared/Minigames/Bowling/BallPath")
local PinModel = require("@shared/Minigames/Bowling/PinModel")
local RollScript = require("@shared/Minigames/Bowling/RollScript")
local Shots = require("@shared/Minigames/Bowling/Shots")

return function(t)
	t.test("stepping and aiming: keys, mouse (locked or free) and stick move the target; all clamped", function()
		local aim = AimModel.new()
		t.truthy(AimModel.canAim(aim))
		AimModel.step(aim, { right = true }, 0.5)
		t.near(aim.offset, 0.45, 1e-9)
		AimModel.step(aim, { left = true }, 10)
		t.eq(aim.offset, -1)
		AimModel.step(aim, { stickStep = 1 }, 1)
		t.near(aim.offset, -0.1, 1e-9)
		AimModel.step(aim, { aimR = true }, 0.5)
		t.near(aim.target, 0.5 * AimModel.TARGET_RATE, 1e-9)
		AimModel.step(aim, { aimL = true }, 100)
		t.eq(aim.target, -AimModel.MAX_TARGET)
		-- a free cursor: its place across the screen is the target
		AimModel.step(aim, { mouseX01 = 0.75 }, 0.016)
		t.near(aim.target, AimModel.MAX_TARGET * 0.5, 1e-9)
		AimModel.step(aim, { mouseX01 = 0.5 }, 0.016)
		t.near(aim.target, 0, 1e-9)
		-- a locked cursor (first person): its travel moves the target
		AimModel.step(aim, { mouseDx = 100 }, 0.016)
		t.near(aim.target, 100 * AimModel.MOUSE_SENS, 1e-9)
		AimModel.step(aim, { mouseDx = -1e6 }, 0.016)
		t.eq(aim.target, -AimModel.MAX_TARGET)
		AimModel.step(aim, { stickAim = 1 }, 1)
		t.near(aim.target, -AimModel.MAX_TARGET + AimModel.STICK_RATE, 1e-9)
		-- no input, no drift
		local before = { aim.offset, aim.target, aim.angle }
		AimModel.step(aim, {}, 5)
		t.deepEq({ aim.offset, aim.target, aim.angle }, before)
	end)

	t.test("a press is one board: at the feet and at the target; nothing moves once the ball is away", function()
		local aim = AimModel.new()
		local board = AimModel.BOARD
		AimModel.nudge(aim, "stand", 1)
		t.near(AimModel.standX(aim), board, 1e-9)
		t.eq(AimModel.standText(aim), "board 19")
		AimModel.nudge(aim, "target", -1)
		AimModel.nudge(aim, "target", -1)
		t.near(aim.target, -2 * board, 1e-9)
		t.eq(AimModel.board(aim.target), 22)
		t.near(aim.angle, AimModel.angleOf(aim.offset, aim.target), 1e-12)
		-- clamped at the edges
		for _ = 1, 60 do
			AimModel.nudge(aim, "stand", -1)
			AimModel.nudge(aim, "target", 1)
		end
		t.eq(aim.offset, -1)
		t.eq(aim.target, AimModel.MAX_TARGET)
		AimModel.charge(aim, true)
		AimModel.charge(aim, false)
		local was = { aim.offset, aim.target }
		AimModel.nudge(aim, "stand", 1)
		AimModel.nudge(aim, "target", -1)
		t.deepEq({ aim.offset, aim.target }, was)
	end)

	t.test("the line: where you stand and the arrow you aim at make the angle, as on a real lane", function()
		-- stand in the middle, aim at the middle arrow: straight down the lane
		t.eq(AimModel.angleOf(0, 0), 0)
		-- the arrows are where the bake draws them, and the middle one is board 20
		local mx = AlleyLayout.arrow(4)
		t.near(mx, 0, 1e-9)
		t.eq(AimModel.board(mx), 20)
		for k = 1, 7 do
			local ax, ad = AlleyLayout.arrow(k)
			t.eq(AimModel.board(ax), 40 - 5 * k, `arrow {k} is on board {40 - 5 * k}`)
			t.near(AlleyLayout.arrowsD(ax), ad, 1e-9, "the arrows' V runs through every tip")
		end
		-- stand right, aim at the 2nd arrow from the right
		local aim = AimModel.new()
		AimModel.step(aim, { right = true }, 0.6)
		local ax = AlleyLayout.arrow(6)
		AimModel.step(aim, { mouseDx = (ax - aim.target) / AimModel.MOUSE_SENS }, 0.01)
		t.eq(AimModel.targetText(aim), "2nd arrow from the right")
		local p = AimModel.params(aim)
		local path = BallPath.trace({ offset = p.offset, angle = p.angle, power = 0.7, spin = 0 })
		-- a straight ball really rolls over the arrow it was aimed at
		local s = path.samples
		local _, ad = AimModel.targetPoint(aim)
		for k = 4, #s, 3 do
			if s[k + 2] >= ad then
				local f = (ad - s[k - 1]) / (s[k + 2] - s[k - 1])
				t.near(s[k - 2] + (s[k + 1] - s[k - 2]) * f, ax, 0.01, "over the target arrow")
				break
			end
		end
		-- moving your feet with the target kept changes the angle (move left: the line points further right)
		local a0 = aim.angle
		AimModel.step(aim, { left = true }, 0.4)
		t.truthy(aim.angle > a0 + 0.01, `angle {a0} -> {aim.angle}`)
		-- the angle is wide enough to cross the lane from edge to far arrow, and never more than the range
		t.truthy(math.abs(AimModel.angleOf(1, -AimModel.MAX_TARGET)) <= BallPath.RANGES.angle + 1e-9)
		t.truthy(math.abs(AimModel.angleOf(-1, (AlleyLayout.arrow(7)))) > 0.15)
		-- the words
		t.eq(AimModel.targetText(AimModel.new()), "the middle arrow")
		local left = AimModel.new()
		AimModel.step(left, { mouseDx = (AlleyLayout.arrow(1)) / AimModel.MOUSE_SENS }, 0.01)
		t.eq(AimModel.targetText(left), "1st arrow from the left")
		AimModel.step(left, { aimR = true }, 0.12)
		t.truthy(string.find(AimModel.targetText(left), "board ", 1, true) ~= nil)
		t.eq(AimModel.standText(AimModel.new()), "board 20")
	end)

	t.test("hook notches: four each way, shown in words; the spin is the notch", function()
		local aim = AimModel.new()
		t.eq(AimModel.spinText(aim), "straight")
		AimModel.hook(aim, -1)
		t.eq(aim.notch, -1)
		t.eq(AimModel.spinText(aim), "a touch of hook left")
		t.eq(AimModel.params(aim).spin, -0.25)
		AimModel.hook(aim, -1)
		t.eq(AimModel.spinText(aim), "some hook left")
		AimModel.hook(aim, -1)
		t.eq(AimModel.spinText(aim), "strong hook left")
		for _ = 1, 4 do
			AimModel.hook(aim, -1)
		end
		t.eq(aim.notch, -AimModel.NOTCHES)
		t.eq(AimModel.spinText(aim), "full hook left")
		t.eq(AimModel.params(aim).spin, -1)
		for _ = 1, 12 do
			AimModel.hook(aim, 1)
		end
		t.eq(aim.notch, AimModel.NOTCHES)
		t.eq(AimModel.spinText(aim), "full hook right")
		t.eq(AimModel.params(aim).spin, 1)
	end)

	t.test("the power meter: a triangle wave; let go to bowl; the throw is what was aimed", function()
		local aim = AimModel.new()
		t.eq(AimModel.charge(aim, false), nil, "letting go without holding is nothing")
		AimModel.step(aim, { right = true }, 0.2)
		AimModel.hook(aim, 1)
		t.eq(AimModel.charge(aim, true), nil)
		t.truthy(aim.charging)
		t.eq(AimModel.power(aim), 0)
		AimModel.step(aim, {}, AimModel.POWER_PERIOD * 0.5)
		t.near(AimModel.power(aim), 0.5, 1e-9)
		AimModel.step(aim, {}, AimModel.POWER_PERIOD * 0.5)
		t.near(AimModel.power(aim), 1, 1e-9)
		AimModel.step(aim, {}, AimModel.POWER_PERIOD * 0.3)
		t.near(AimModel.power(aim), 0.7, 1e-9)
		for i = 1, 200 do
			AimModel.step(aim, {}, 0.013)
			local p = AimModel.power(aim)
			t.truthy(p >= 0 and p <= 1, `power {p} at step {i}`)
		end
		-- holding again while already charging does not restart the needle
		local was = aim.chargeT
		AimModel.charge(aim, true)
		t.eq(aim.chargeT, was)
		local p = AimModel.charge(aim, false) :: BallPath.Params
		t.truthy(p ~= nil)
		t.near(p.offset, 0.18, 1e-9)
		t.eq(p.spin, 0.25)
		t.eq(p.power, AimModel.power(aim))
		t.eq(aim.phase, "sent")
		t.falsy(AimModel.canAim(aim))
		-- nothing moves and nothing more is thrown while the ball is on its way
		AimModel.step(aim, { left = true, aimL = true }, 1)
		t.near(aim.offset, 0.18, 1e-9)
		AimModel.hook(aim, -1)
		t.eq(aim.notch, 1)
		AimModel.charge(aim, true)
		t.eq(AimModel.charge(aim, false), nil)
		AimModel.sent(aim)
		t.eq(aim.phase, "watch")
		AimModel.nextBall(aim)
		t.truthy(AimModel.canAim(aim))
		t.near(aim.offset, 0.18, 1e-9, "the line is kept for the next ball")
	end)

	t.test("a refused throw hands the controls straight back", function()
		local aim = AimModel.new()
		AimModel.charge(aim, true)
		AimModel.step(aim, {}, 0.9)
		t.truthy(AimModel.charge(aim, false) ~= nil)
		t.eq(aim.phase, "sent")
		AimModel.refused(aim)
		t.eq(aim.phase, "aim")
		-- and the next hold-and-release throws again
		AimModel.charge(aim, true)
		AimModel.step(aim, {}, 0.6)
		local again = AimModel.charge(aim, false)
		t.truthy(again ~= nil, "a second throw goes out")
		t.near((again :: BallPath.Params).power, 0.4, 1e-9)
		-- a refusal that arrives when nothing is pending changes nothing
		AimModel.sent(aim)
		AimModel.refused(aim)
		t.eq(aim.phase, "watch")
	end)

	t.test("the aim line is the real path over the arrows to where the back end bites, a hook bending there", function()
		local aim = AimModel.new()
		AimModel.step(aim, { right = true }, 0.4)
		AimModel.step(aim, { mouseDx = AlleyLayout.arrow(6) / AimModel.MOUSE_SENS }, 0.01) -- 2nd arrow from the right
		local dots = AimModel.preview(aim)
		t.truthy(#dots >= 12 and #dots <= 30, `{#dots} dots`)
		local p = AimModel.params(aim)
		local path = BallPath.trace({ offset = p.offset, angle = p.angle, power = AimModel.PREVIEW_POWER, spin = 0 })
		for i, dot in dots do
			t.truthy(dot.d <= AimModel.PREVIEW_D + 0.5, "the line stops short of the pins")
			if i > 1 then
				t.truthy(dot.d > dots[i - 1].d)
			end
			t.falsy(dot.hooked)
			-- on the true path: find the path's x at this d
			local s = path.samples
			for k = 4, #s, 3 do
				if s[k + 2] >= dot.d then
					local f = (dot.d - s[k - 1]) / (s[k + 2] - s[k - 1])
					t.near(dot.x, s[k - 2] + (s[k + 1] - s[k - 2]) * f, 0.02)
					break
				end
			end
		end
		t.truthy(dots[#dots].d > BallPath.HOOK_START, "the line reaches the back end")
		for _ = 1, AimModel.NOTCHES do
			AimModel.hook(aim, -1)
		end
		local hooked = AimModel.preview(aim)
		local bent = 0
		for i, dot in hooked do
			if dot.hooked then
				bent += 1
				t.truthy(dot.d > BallPath.HOOK_START)
				t.truthy(dot.x <= dots[i].x + 1e-9, "a hook left never bends right")
			else
				-- on the oil a hook only skids: within a few boards of the straight line
				t.truthy(math.abs(dot.x - dots[i].x) < 0.35, "only a skid on the oil")
			end
		end
		t.truthy(bent >= 2)
		t.truthy(hooked[#hooked].x < dots[#hooked].x - 0.2, "by the end of the line the bend shows")
		-- a line that runs off the lane stops at the gutter
		local wide = AimModel.new()
		AimModel.step(wide, { right = true, aimR = true }, 5)
		AimModel.step(wide, { left = true }, 1.8)
		t.truthy(wide.angle > 0.05)
		local w = AimModel.preview(wide)
		t.truthy(#w < #dots)
		for _, dot in w do
			t.truthy(math.abs(dot.x) <= AlleyLayout.LANE_W / 2 + 0.05)
		end
	end)

	t.test("the words: one help card and one status line that agree; a countdown warning", function()
		local keys = table.concat(AimModel.HELP.keys, " | ")
		for _, word in { "A / D", "Mouse", "Left / Right", "arrow", "Z / X", "wheel", "Space", "green", "Gamepad", "Q" } do
			t.truthy(string.find(keys, word, 1, true) ~= nil, `the help card names {word}`)
		end
		t.truthy(#AimModel.HELP.how >= 3)
		local aim = AimModel.new()
		local status = AimModel.statusText(aim, false)
		for _, word in { "Your turn", "stand board 20", "the middle arrow", "A/D", "mouse", "Z/X", "Space", "straight" } do
			t.truthy(string.find(status, word, 1, true) ~= nil, `the status line names {word}`)
		end
		local touch = AimModel.statusText(aim, true)
		t.truthy(string.find(touch, "BOWL", 1, true) ~= nil and string.find(touch, "Hook", 1, true) ~= nil)
		t.truthy(string.find(touch, "Step", 1, true) ~= nil and string.find(touch, "Aim", 1, true) ~= nil)
		t.truthy(
			string.find(table.concat(AimModel.HELP.how, " "), "HOOK", 1, true) ~= nil,
			"the card explains the hook"
		)
		t.falsy(string.find(touch, "Space", 1, true), "no keyboard words on a phone")
		AimModel.hook(aim, 1)
		t.truthy(string.find(AimModel.statusText(aim, false), "a touch of hook right", 1, true) ~= nil)
		AimModel.charge(aim, true)
		t.truthy(string.find(AimModel.statusText(aim, false), "green", 1, true) ~= nil)
		AimModel.charge(aim, false)
		t.eq(AimModel.statusText(aim, false), "Bowling...")
		t.truthy(string.find(AimModel.SWEET_TEXT, "green", 1, true) ~= nil)
		t.truthy(string.find(AimModel.SWEET_TEXT, "wild", 1, true) ~= nil)
		t.deepEq(AimModel.SWEET, BallPath.RANGES.sweet)
		-- the turn clock
		t.eq(AimModel.warning(nil), nil)
		t.eq(AimModel.warning(40), nil)
		t.eq(AimModel.warning(15), "Bowl within 15 seconds or your turn is skipped")
		t.eq(AimModel.warning(4.2), "Bowl within 5 seconds or your turn is skipped")
		t.eq(AimModel.warning(1), "Bowl within 1 second or your turn is skipped")
		t.eq(AimModel.warning(0), "Bowl within 0 seconds or your turn is skipped")
	end)

	t.test(
		"camera: behind the ball, one cut to the pins before impact, held, then handed back; always in the room",
		function()
			local throws: { { any } } = {
				{ { offset = 0.165, angle = 0, power = 0.7, spin = 0 }, 3 }, -- pocket
				{ { offset = 0, angle = 0, power = 0.7, spin = 0 }, 2 }, -- dead centre (a split)
				{ { offset = 1, angle = 0.1, power = 0.7, spin = 0 }, 1 }, -- gutter
				{ { offset = -1, angle = -0.1, power = 0, spin = 0 }, 1 }, -- slow gutter
				{ { offset = 0.6, angle = 0.012, power = 1, spin = -1 }, 5 }, -- fast hook
				{ { offset = -0.9, angle = 0.03, power = 0.1, spin = 1 }, 6 }, -- slow hook
			}
			for i, th in throws do
				local s = RollScript.build(th[1], PinModel.fullRack(), th[2])
				local cut, done = Shots.cutTime(s), Shots.doneTime(s)
				t.truthy(cut <= s.tImpact - 0.25, `throw {i}: the cut comes before the ball arrives`)
				t.truthy(done >= s.tEnd + 0.5 and done < 12, `throw {i}: handed back at {done}`)
				local phases: { string } = {}
				local prev: Shots.Shot? = nil
				local speed = BallPath.speedOf((th[1] :: any).power)
				local tt = 0
				while tt <= done + 0.2 do
					local shot = Shots.roll(s, tt)
					if phases[#phases] ~= shot.phase then
						table.insert(phases, shot.phase)
					end
					-- inside the room: over the lanes, off the floor, under the ceiling, short of the machine
					t.truthy(math.abs(shot.ex) <= AlleyLayout.LANE_W / 2 + AlleyLayout.GUTTER_W, `eye x {shot.ex}`)
					t.truthy(shot.ey >= 1 and shot.ey <= AlleyLayout.CEILING_Y - 0.5, `eye y {shot.ey}`)
					t.truthy(
						shot.ed >= AlleyLayout.APPROACH_D and shot.ed <= AlleyLayout.MACHINE_D0 - 1,
						`eye d {shot.ed}`
					)
					t.truthy(shot.ld > shot.ed + 3, "always looking down the lane")
					t.truthy(shot.fov >= 35 and shot.fov <= 70)
					if shot.phase == "follow" then
						local _, _, bd = RollScript.ball(s, tt)
						t.truthy(shot.ed < bd - 2, "behind the ball")
						if prev and prev.phase == "follow" then
							local move =
								math.sqrt((shot.ex - prev.ex) ^ 2 + (shot.ey - prev.ey) ^ 2 + (shot.ed - prev.ed) ^ 2)
							t.truthy(move <= speed / 60 * 1.2 + 0.05, `follow moved {move} at {tt}`)
						end
					elseif prev and prev.phase == shot.phase then
						t.truthy(shot.ex == prev.ex and shot.ed == prev.ed, "the pin shot holds still")
					end
					prev = shot
					tt += 1 / 60
				end
				t.deepEq(phases, { "follow", "pins", "done" }, `throw {i}`)
				-- the pin shot is up through the whole pinfall
				t.eq(Shots.roll(s, s.tImpact).phase, "pins")
				t.eq(Shots.roll(s, s.tEnd).phase, "pins")
				t.eq(Shots.roll(s, 99).phase, "done")
			end
			-- a scripted pinfall with no ball: the pin shot from the start, then done
			local fake = RollScript.fake(PinModel.fullRack(), 5)
			t.eq(Shots.roll(fake, 0).phase, "pins")
			t.eq(Shots.roll(fake, Shots.doneTime(fake)).phase, "done")
			-- the aiming shot follows where you stand and looks along the angle
			local a = Shots.aim(1, 0.05)
			t.truthy(a.ex > 0.5 and a.lx > 1 and a.ed < AlleyLayout.FOUL_D - 5)
			t.truthy(a.ed >= AlleyLayout.APPROACH_D and a.ey < AlleyLayout.CEILING_Y)
			local b = Shots.between()
			t.truthy(b.ld > 45 and b.ed == a.ed)
		end
	)
end
