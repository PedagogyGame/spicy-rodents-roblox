--!strict
-- Minigames/Pool/Cue: what a player gives and the strike it makes (checklist POOL-P2 the tip, POOL-P8 the aim
-- preview from the same model, POOL-P9 delivery error only above the meter's band, decision D5 a hold that
-- rises once so soft shots are chosen on purpose).
local Cue = require("@shared/Minigames/Pool/Cue")
local Shot = require("@shared/Minigames/Pool/Shot")
local Tables = require("@shared/Minigames/Pool/Tables")

return function(t)
	local pool = Tables.eightBall()
	local bumper = Tables.bumper()
	local R = Tables.BALL_R

	t.test("D5 power: rises all the way from a touch to the break, with room at the soft end", function()
		t.eq(Cue.speed(0), Cue.MIN_SPEED)
		t.eq(Cue.speed(1), Cue.MAX_SPEED)
		t.eq(Cue.speed(7), Cue.MAX_SPEED, "clamped")
		t.eq(Cue.speed(-1), Cue.MIN_SPEED)
		local last = 0
		for i = 0, 20 do
			local v = Cue.speed(i / 20)
			t.truthy(v > last)
			last = v
			t.near(Cue.powerFor(v), i / 20, 1e-9, "powerFor undoes speed")
		end
		t.truthy(Cue.speed(0.5) < 0.4 * Cue.MAX_SPEED, "half the hold is well under half the speed")
		t.truthy(Cue.speed(0.15) < 5, "the bottom of the hold is a gentle roll")
	end)

	t.test("POOL-P2 the tip: centre is stun, high is a natural roll, low is draw, the side is side spin", function()
		local c = Cue.strike(0, 0, 0.5, 0, 0, nil)
		t.eq(c.vx, 0)
		t.near(c.vz, Cue.speed(0.5), 1e-9, "angle 0 is straight up the table")
		t.eq(c.qz, 0)
		t.eq(c.s, 0)
		local hi = Cue.strike(0, 0, 0.5, 0, 0.8, nil)
		t.near(hi.qz, hi.vz, 1e-9, "0.8 up the ball leaves it rolling naturally")
		local lo = Cue.strike(0, 0, 0.5, 0, -0.8, nil)
		t.near(lo.qz, -lo.vz, 1e-9, "the same below centre: backspin")
		local right = Cue.strike(0, 0, 0.5, 0.6, 0, nil)
		local left = Cue.strike(0, 0, 0.5, -0.6, 0, nil)
		t.truthy(right.s > 0 and left.s == -right.s)
		local side = Cue.strike(0, math.pi / 2, 0.5, 0, 0, nil)
		t.near(side.vx, Cue.speed(0.5), 1e-9, "a quarter turn is toward +x")
		t.near(side.vz, 0, 1e-9)
		t.near(Cue.angleOf(Cue.dirOf(0.7)), 0.7, 1e-12)
		-- the tip cannot leave the ball
		local x, y = Cue.clampTip(3, 4)
		t.near(x * x + y * y, 1, 1e-12)
		t.eq((Cue.clampTip(0 / 0, 1)), 0)
		local far = Cue.strike(0, 0, 0.5, 30, 0, nil)
		t.near(far.s, Cue.strike(0, 0, 0.5, 1, 0, nil).s, 1e-9)
	end)

	t.test("POOL-P9 delivery: exact inside the meter's band, a small seeded error only above 90 %", function()
		for _, power in { 0.1, 0.5, 0.9 } do
			local a = Cue.strike(0, 0.3, power, 0.2, -0.4, 1)
			local b = Cue.strike(0, 0.3, power, 0.2, -0.4, 999)
			t.deepEq(a, b, `at {power} the seed changes nothing`)
			t.deepEq(a, Cue.strike(0, 0.3, power, 0.2, -0.4, nil))
		end
		local differs = false
		local worst = 0
		for seed = 1, 200 do
			local s = Cue.strike(0, 0.3, 1, 0, 0, seed)
			t.deepEq(s, Cue.strike(0, 0.3, 1, 0, 0, seed), "seeded: the same seed is the same strike")
			local err = math.abs(Cue.angleOf(s.vx, s.vz) - 0.3)
			worst = math.max(worst, err)
			if err > 1e-6 then
				differs = true
			end
			t.near(math.sqrt(s.vx * s.vx + s.vz * s.vz), Cue.MAX_SPEED, 1e-9, "the speed is what was asked")
		end
		t.truthy(differs, "a smash wanders")
		t.truthy(worst <= Cue.WILD_ANGLE + 1e-9, "but never by more than WILD_ANGLE")
		t.truthy(Cue.WILD_ANGLE < math.rad(1), "which is small")
		-- half way into the wild band the error is half as wide
		local mid = 0
		for seed = 1, 200 do
			local s = Cue.strike(0, 0.3, 0.95, 0, 0, seed)
			mid = math.max(mid, math.abs(Cue.angleOf(s.vx, s.vz) - 0.3))
		end
		t.truthy(mid <= Cue.WILD_ANGLE * 0.5 + 1e-9)
	end)

	t.test("POOL-P8 the preview is the shot: the ghost ball, the object ball's line and the cue ball's line", function()
		local spots = { { id = 0, x = -0.6, z = -2 }, { id = 4, x = 0.5, z = 1 }, { id = 9, x = -2, z = 4 } }
		for _, angle in { 0.3, 0.33, 0.37 } do
			local p = Cue.preview(pool, spots, 0, angle, 0.35, 0, 0)
			t.eq(p.kind, "ball")
			t.eq(p.target, 4)
			local s = Shot.run(pool, spots, { Cue.strike(0, angle, 0.35, 0, 0, nil) })
			t.near(p.t, s.firstT, 1e-9, "the same moment")
			local gx, gz = Shot.pose(s, 1, s.firstT)
			t.near(p.gx, gx, 1e-6, "the ghost ball is where the cue ball really meets it")
			t.near(p.gz, gz, 1e-6)
			t.near(math.sqrt((p.gx - 0.5) ^ 2 + (p.gz - 1) ^ 2), 2 * R, 1e-4, "touching the object ball")
			-- the object ball's line is the way it really goes
			local ox, oz = Shot.pose(s, 2, s.firstT + 0.05)
			local dx, dz = ox - 0.5, oz - 1
			local d = math.sqrt(dx * dx + dz * dz)
			t.near(p.ox, dx / d, 0.01)
			t.near(p.oz, dz / d, 0.01)
			t.truthy(p.speed > 0)
			-- and the cue ball's line is the way it really goes
			t.eq(#p.path, Cue.PREVIEW_POINTS * 2)
			local cx, cz = Shot.pose(s, 1, s.firstT + Cue.PREVIEW_AFTER)
			t.near(p.path[#p.path - 1], cx, 0.03)
			t.near(p.path[#p.path], cz, 0.03)
		end
		t.eq(spots[1].x, -0.6, "the preview leaves the table alone")
		t.eq(#spots, 3)
	end)

	t.test("POOL-P8 the cue ball's line moves as the tip moves; the lines are short", function()
		local spots = { { id = 0, x = 0, z = -1 }, { id = 4, x = 0.05, z = 0 } }
		local function after(tipY: number): number
			local p = Cue.preview(pool, spots, 0, 0, 0.3, 0, tipY)
			t.eq(p.target, 4)
			return p.path[#p.path] - p.gz
		end
		local follow, stun, draw = after(0.8), after(-0.25), after(-0.9)
		t.truthy(follow > stun + 0.2, `follow runs on ({follow} against {stun})`)
		t.truthy(draw < stun - 0.1, `draw comes back ({draw})`)
		-- short: a third of a second of the cue ball's travel, never the whole shot
		local p = Cue.preview(pool, spots, 0, 0, 0.3, 0, 0.8)
		local len = math.sqrt((p.path[#p.path - 1] - p.gx) ^ 2 + (p.path[#p.path] - p.gz) ^ 2)
		t.truthy(len < 2.5, `{len} studs`)
		t.truthy(Cue.PREVIEW_AFTER <= 0.5)
	end)

	t.test(
		"the preview of a ball that meets a cushion, a bumper or nothing first (bumper pool's one-bounce line)",
		function()
			local spots = Tables.bumperStart()
			local bank = Cue.preview(bumper, spots, 1, math.rad(40), 0.2, 0, 0.8)
			t.eq(bank.kind, "cushion")
			t.near(bank.gx, bumper.halfW - R, 1e-6, "the first bounce is on the side cushion")
			t.eq(bank.target, -1)
			t.truthy(#bank.path >= 2)
			t.truthy(bank.path[1] < bank.gx, "and the line leaves the cushion back toward the table")
			local post = Cue.preview(bumper, spots, 1, 0, 0.2, 0, 0.8)
			t.eq(post.kind, "post", "straight up the middle is the cross")
			local nothing = Cue.preview(pool, { { id = 0, x = 0, z = 0 } }, 0, 0, 0.05, 0, 0.8)
			t.eq(nothing.kind, "none", "a touch that stops short of everything")
			t.truthy(nothing.gz > 0 and nothing.gz < pool.halfL)
			-- above the sure band the preview shows the shot as aimed (the wander is not foreseeable)
			local a = Cue.preview(pool, Tables.rack(1), 0, 0, 1, 0, 0)
			local b = Cue.preview(pool, Tables.rack(1), 0, 0, 1, 0, 0)
			t.deepEq(a, b)
			t.eq(a.kind, "ball")
		end
	)
end
