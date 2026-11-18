--!strict
-- Minigames/Pool/Cloth: one ball alone on the cloth (checklist POOL-P2 sliding then rolling, POOL-P6 the cloth):
-- sliding turns into rolling at 5/7 of the speed, follow and draw are the same rule, a ball slows smoothly and
-- stops for good, energy only ever falls, and advance() is exact for any time step.
local Cloth = require("@shared/Minigames/Pool/Cloth")

return function(t)
	local function ball(vx: number, vz: number, qx: number, qz: number, s: number?): Cloth.Ball
		local b = Cloth.new(1, 0, 0)
		b.vx, b.vz, b.qx, b.qz, b.s = vx, vz, qx, qz, s or 0
		b.mode = Cloth.CLOTH
		return b
	end

	t.test("POOL-P2 a stunned ball slides, then rolls at 5/7 of its speed", function()
		local b = ball(0, 7, 0, 0)
		local tau = 7 / (3.5 * Cloth.A_SLIDE)
		Cloth.advance(b, tau * 0.5)
		t.truthy(b.vz < 7 and b.qz > 0 and b.qz < b.vz, "half way: slowing down, spinning up, still sliding")
		Cloth.advance(b, tau * 0.5 + 1e-9)
		t.near(b.vz, 5, 1e-6, "5/7 of 7")
		t.near(b.qz, b.vz, 1e-9, "rolling: the roll matches the motion")
		t.eq(b.vx, 0)
	end)

	t.test("POOL-P2 follow speeds a slow ball up, draw brings a ball back", function()
		-- more roll than motion (the cue ball just after a full hit with follow): the cloth pushes it forward
		local f = ball(0, 0.5, 0, 6)
		Cloth.advance(f, 1)
		t.truthy(f.vz > 0.5, "follow rolls on")
		-- backspin and hardly any motion (after a full hit with draw): it comes back
		local d = ball(0, 0.5, 0, -6)
		Cloth.advance(d, 1)
		t.truthy(d.vz < 0, "draw comes back")
		t.truthy(d.z < 0)
		-- a ball with no roll and no motion to speak of stays put
		local s = ball(0, 0.02, 0, 0)
		Cloth.advance(s, 5)
		t.eq(s.mode, Cloth.REST)
		t.truthy(math.abs(s.z) < 0.001, "stun: it stops dead")
	end)

	t.test("POOL-P2 a cue ball with roll across its path curves (the cloth pushes against the slip)", function()
		local b = ball(4, 0, 4, 3)
		Cloth.advance(b, 2)
		t.truthy(b.z > 0.1, "it has moved sideways toward its roll")
	end)

	t.test("POOL-P6 a rolling ball slows smoothly, stops, and stays stopped", function()
		local b = ball(0, 3, 0, 3)
		local last = 3
		local time = 0
		while b.mode == Cloth.CLOTH and time < 20 do
			Cloth.advance(b, 1 / 60)
			time += 1 / 60
			t.truthy(b.vz <= last and b.vz >= 0, "never speeds up, never reverses")
			t.truthy(last - b.vz <= Cloth.A_ROLL / 60 + 1e-9, "never stops dead: it loses the same little each frame")
			last = b.vz
		end
		t.eq(b.mode, Cloth.REST)
		t.near(time, 3 / Cloth.A_ROLL, 0.02, "v / a seconds")
		t.near(b.z, Cloth.rollDistance(3), 1e-6)
		local z = b.z
		Cloth.advance(b, 10)
		t.eq(b.z, z, "never creeps")
		t.eq(b.vz, 0)
	end)

	t.test("POOL-P6 a soft shot the length of the table rolls four to six seconds", function()
		local v = Cloth.speedFor(10.8 - 0.34)
		local seconds = v / Cloth.A_ROLL
		t.truthy(seconds >= 4 and seconds <= 6, `{seconds} s`)
		t.near(Cloth.rollDistance(v), 10.8 - 0.34, 1e-9)
	end)

	t.test("advance is exact for any step: in pieces and in one go agree", function()
		for _, case in { { 3, 5, -2, 1, 4 }, { 0, 9, 0, -9, -3 }, { 2, 2, 2, 2, 0 }, { -6, 1, 3, 3, 9 } } do
			local whole = ball(case[1], case[2], case[3], case[4], case[5])
			local parts = ball(case[1], case[2], case[3], case[4], case[5])
			Cloth.advance(whole, 1.7)
			local left = 1.7
			local dt = 0.013
			while left > 0 do
				local h = math.min(dt, left)
				Cloth.advance(parts, h)
				left -= h
				dt *= 1.31
			end
			t.near(parts.x, whole.x, 1e-9)
			t.near(parts.z, whole.z, 1e-9)
			t.near(parts.vx, whole.vx, 1e-9)
			t.near(parts.vz, whole.vz, 1e-9)
			t.near(parts.qx, whole.qx, 1e-9)
			t.near(parts.s, whole.s, 1e-9)
		end
	end)

	t.test("energy only ever falls on the cloth, whatever the spin", function()
		for _, case in { { 3, 5, -2, 1, 4 }, { 0, 9, 0, -9, -3 }, { 0, 1, 0, 12, 0 }, { -6, 1, 3, 3, 9 } } do
			local b = ball(case[1], case[2], case[3], case[4], case[5])
			local e = Cloth.energy(b)
			for _ = 1, 2000 do
				Cloth.advance(b, 1 / 240)
				local now = Cloth.energy(b)
				t.truthy(now <= e + 1e-9, "energy grew")
				e = now
			end
			t.eq(b.mode, Cloth.REST, "and it comes to rest")
			t.eq(Cloth.energy(b), 0)
		end
	end)

	t.test("side spin dies on its own and never turns a ball on the open cloth", function()
		local b = ball(0, 4, 0, 4, 6)
		Cloth.advance(b, 1)
		t.near(b.s, 6 - Cloth.A_SPIN, 1e-9)
		t.eq(b.x, 0, "no swerve from side alone")
		Cloth.advance(b, 5)
		t.eq(b.s, 0)
	end)

	t.test("a ball over a hole falls; a ball at rest, down or off the table does not move", function()
		local b = ball(1, 0, 1, 0)
		b.mode = Cloth.AIR
		Cloth.advance(b, 0.05)
		t.near(b.x, 0.05, 1e-12)
		t.near(b.y, -0.5 * Cloth.G * 0.05 * 0.05, 1e-9)
		Cloth.advance(b, 0.05)
		t.near(b.y, -0.5 * Cloth.G * 0.1 * 0.1, 1e-9, "free fall carries on from where it was")
		for _, mode in { Cloth.REST, Cloth.DOWN, Cloth.OFF } do
			local r = ball(3, 3, 3, 3)
			r.mode = mode
			Cloth.advance(r, 1)
			t.eq(r.x, 0)
			t.eq(Cloth.energy(r), 0)
		end
	end)
end
