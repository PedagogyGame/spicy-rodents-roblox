--!strict
-- Minigames/Bowling/BallPath (brief v2 §13a "choose your angle and power, bowl"): the ball's line from the hand
-- to the pin deck: speed from power, the angle, a hook that only bends on the back end and bends more when
-- slow, gutters that keep the ball, the sweet band of the power meter, and the samples playback reads.
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local BallPath = require("@shared/Minigames/Bowling/BallPath")
local Rng = require("@shared/Util/Rng")

local function throw(offset: number, angle: number, power: number, spin: number): BallPath.Path
	return BallPath.trace({ offset = offset, angle = angle, power = power, spin = spin })
end

return function(t)
	t.test("a straight centre ball reaches the deck dead centre in about distance / speed seconds", function()
		for _, power in { 0, 0.5, 1 } do
			local path = throw(0, 0, power, 0)
			local e = path.entry :: BallPath.Entry
			t.truthy(e ~= nil, "it reaches the deck")
			t.near(e.x, 0, 0.001)
			t.near(e.vx, 0, 0.001)
			local speed = BallPath.speedOf(power)
			local expect = (AlleyLayout.DECK_START - BallPath.RELEASE_D) / speed
			t.truthy(e.t > expect and e.t < expect * 1.12, `power {power}: {e.t} s against {expect}`)
			t.truthy(e.vd < speed and e.vd > speed - 6, "it slows a little, never much")
			t.eq(path.gutterT, nil)
			t.eq(path.tEnd, e.t)
		end
		t.eq(BallPath.speedOf(0), BallPath.RANGES.speedMin)
		t.eq(BallPath.speedOf(1), BallPath.RANGES.speedMax)
		t.truthy(throw(0, 0, 1, 0).tEnd < throw(0, 0, 0, 0).tEnd, "more power is a faster ball")
	end)

	t.test("the angle and the offset put the ball where the geometry says", function()
		local right = throw(0, 0.02, 0.7, 0).entry :: BallPath.Entry
		t.near(right.x, math.tan(0.02) * (AlleyLayout.DECK_START - BallPath.RELEASE_D), 0.02)
		t.truthy(right.vx > 0)
		local left = throw(0, -0.02, 0.7, 0).entry :: BallPath.Entry
		t.near(left.x, -right.x, 1e-9)
		local off = throw(0.5, 0, 0.7, 0).entry :: BallPath.Entry
		t.near(off.x, BallPath.releaseX(0.5), 0.001)
		t.near(BallPath.releaseX(1), AlleyLayout.LANE_W / 2 - AlleyLayout.BALL_D / 2 - 0.05, 1e-9)
		t.eq(BallPath.releaseX(5), BallPath.releaseX(1))
	end)

	t.test("hook: nothing on the oil, a bend on the back end, more with more spin and at low speed", function()
		local straight = throw(0.3, 0, 0.7, 0)
		local hooked = throw(0.3, 0, 0.7, -1)
		-- identical until the oil ends
		local tOil = (BallPath.HOOK_START - BallPath.RELEASE_D) / BallPath.speedOf(0.7) - 0.05
		for i = 0, 10 do
			local tt = tOil * i / 10
			local xa = BallPath.at(straight, tt)
			local xb = BallPath.at(hooked, tt)
			t.near(xa, xb, 1e-9, `on the oil at {tt}`)
		end
		local e0 = straight.entry :: BallPath.Entry
		local e1 = hooked.entry :: BallPath.Entry
		local half = throw(0.3, 0, 0.7, -0.5).entry :: BallPath.Entry
		t.truthy(e1.x < half.x and half.x < e0.x, "hook left moves left, more with more spin")
		t.truthy(e0.x - e1.x > 0.8 and e0.x - e1.x < 2.5, `full hook breaks {e0.x - e1.x} studs`)
		-- full hook at medium power comes into the pins at four to six degrees
		local deg = math.deg(math.atan2(-e1.vx, e1.vd))
		t.truthy(deg >= 4 and deg <= 6, `entry angle {deg}`)
		-- slower ball, bigger break
		local soft = throw(1, 0, 0.35, -1).entry :: BallPath.Entry
		local hard = throw(1, 0, 1, -1).entry :: BallPath.Entry
		local mid = throw(1, 0, 0.7, -1).entry :: BallPath.Entry
		t.truthy(soft.x < mid.x - 0.5 and mid.x < hard.x - 0.2, `breaks {soft.x} {mid.x} {hard.x}`)
		-- but a ball is never turned more than about seven degrees, however soft
		local softest = throw(1, 0, 0, -1).entry :: BallPath.Entry
		t.truthy(-softest.vx / softest.vd <= BallPath.HOOK_MAX_TURN + 0.005, "the turn is capped")
		-- hook right is the mirror
		local r = throw(-0.3, 0, 0.7, 1).entry :: BallPath.Entry
		t.near(r.x, -e1.x, 1e-9)
		t.near(r.vx, -e1.vx, 1e-9)
	end)

	t.test("mirror: negating offset, angle and spin mirrors every sample exactly", function()
		local a = throw(0.4, 0.03, 0.62, -0.7)
		local b = throw(-0.4, -0.03, 0.62, 0.7)
		t.eq(#a.samples, #b.samples)
		for i = 1, #a.samples, 3 do
			t.eq(a.samples[i], b.samples[i])
			t.eq(a.samples[i + 1], -b.samples[i + 1])
			t.eq(a.samples[i + 2], b.samples[i + 2])
		end
	end)

	t.test(
		"gutter: a ball that leaves the bed stays in the channel, never reaches the pins, ends in the pit",
		function()
			local path = throw(1, 0.1, 0.7, 0)
			t.eq(path.entry, nil)
			t.truthy(path.gutterT ~= nil and (path.gutterD :: number) < 30, `guttered at {path.gutterD}`)
			t.eq(path.gutterSide, 1)
			local last = #path.samples
			t.truthy(path.samples[last] >= BallPath.PIT_D, "it runs to the pit")
			-- once in, the centre settles on the channel's middle and stays off the bed
			local seenIn = false
			for i = 1, last, 3 do
				local tt, x = path.samples[i], path.samples[i + 1]
				if tt > (path.gutterT :: number) + 0.3 then
					seenIn = true
					t.near(x, BallPath.GUTTER_X, 0.05, `in the channel at {tt}`)
				end
				t.truthy(math.abs(x) < AlleyLayout.LANE_W / 2 + AlleyLayout.GUTTER_W, "inside the kickbacks")
			end
			t.truthy(seenIn)
			-- it sits lower in the channel than on the bed
			local _, y0 = BallPath.at(path, 0)
			local _, y1 = BallPath.at(path, path.tEnd)
			t.near(y0, BallPath.BALL_Y, 1e-9)
			t.near(y1, BallPath.BALL_Y - BallPath.GUTTER_DROP, 1e-9)
			-- the left gutter too, and a hook can put it there
			t.eq(throw(-1, -0.1, 0.7, 0).gutterSide, -1)
			local hooked = throw(-0.8, 0, 0.3, -1)
			t.eq(hooked.entry, nil)
			t.eq(hooked.gutterSide, -1)
			-- a straight ball down the edge stays on the bed
			t.truthy(throw(1, 0, 0.7, 0).entry ~= nil)
		end
	)

	t.test("samples: time only goes forward, the ball only goes down-lane, playback is smooth", function()
		for _, p in
			{
				{ 0, 0, 0.7, 0 },
				{ 0.6, 0.01, 0.7, -1 },
				{ -1, -0.1, 1, 0 },
				{ 0.2, -0.05, 0, 1 },
			}
		do
			local path = throw(p[1], p[2], p[3], p[4])
			local s = path.samples
			t.eq(#s % 3, 0)
			t.truthy(#s <= 3 * 90, `{#s // 3} samples`)
			for i = 4, #s, 3 do
				t.truthy(s[i] >= s[i - 3], "time")
				t.truthy(s[i + 2] > s[i - 1], "down-lane")
			end
			t.eq(s[1], 0)
			t.near(s[3], BallPath.RELEASE_D, 1e-9)
			t.eq(s[#s - 2], path.tEnd)
			-- at 60 frames a second nothing jumps
			local speed = BallPath.speedOf(p[3])
			local px, _, pd = BallPath.at(path, 0)
			local tt = 0
			while tt < path.tEnd do
				tt += 1 / 60
				local x, _, d, turn = BallPath.at(path, tt)
				local step = math.sqrt((x - px) ^ 2 + (d - pd) ^ 2)
				t.truthy(step <= speed / 60 * 1.05 + 0.12, `step {step} at {tt}`)
				t.truthy(turn >= 0)
				px, pd = x, d
			end
			-- clamped at both ends
			local xe, _, de = BallPath.at(path, path.tEnd + 5)
			t.eq(xe, s[#s - 1])
			t.eq(de, s[#s])
			local xs = BallPath.at(path, -1)
			t.eq(xs, s[2])
		end
	end)

	t.test("the same throw is the same path; junk becomes a legal throw", function()
		t.deepEq(throw(0.3, 0.02, 0.66, -0.5), throw(0.3, 0.02, 0.66, -0.5))
		local c = BallPath.clamp({ offset = 9, angle = -4, power = 0 / 0, spin = "x" })
		t.eq(c.offset, 1)
		t.eq(c.angle, -BallPath.RANGES.angle)
		t.eq(c.power, 0.6)
		t.eq(c.spin, 0)
		local none = BallPath.clamp(nil)
		t.deepEq(none, { offset = 0, angle = 0, power = 0.6, spin = 0 })
		t.eq(BallPath.clamp({ power = math.huge }).power, 0.6)
	end)

	t.test("the sweet band: no release error inside it, a bounded one outside, seeded", function()
		local lo, hi = BallPath.RANGES.sweet[1], BallPath.RANGES.sweet[2]
		t.eq(BallPath.wildness(lo), 0)
		t.eq(BallPath.wildness(hi), 0)
		t.eq(BallPath.wildness(1), 1)
		t.truthy(BallPath.wildness(0) > 0 and BallPath.wildness(0) < 1)
		local rng = Rng.new(5)
		for i = 0, 20 do
			local power = lo + (hi - lo) * i / 20
			local p = { offset = 0.3, angle = 0.02, power = power, spin = -0.5 }
			t.deepEq(BallPath.noise(rng, p), p, `power {power}`)
		end
		local worst, moved = 0, 0
		for _ = 1, 200 do
			local q = BallPath.noise(rng, { offset = 0, angle = 0, power = 1, spin = 0 })
			worst = math.max(worst, math.abs(q.angle))
			t.truthy(math.abs(q.angle) <= BallPath.NOISE_ANGLE + 1e-12)
			t.truthy(math.abs(q.offset) <= BallPath.NOISE_OFFSET + 1e-12)
			t.eq(q.power, 1)
			if q.angle ~= 0 then
				moved += 1
			end
		end
		t.truthy(moved > 190 and worst > BallPath.NOISE_ANGLE * 0.8, "full power really is wild")
		-- a feeble throw is a little wild too, less than a full-power one
		local feeble = 0
		for _ = 1, 200 do
			feeble =
				math.max(feeble, math.abs(BallPath.noise(rng, { offset = 0, angle = 0, power = 0, spin = 0 }).angle))
		end
		t.truthy(feeble > 0 and feeble < worst)
		-- seeded: the same stream gives the same error, and a sweet throw still uses up its two numbers
		local a, b = Rng.new(9), Rng.new(9)
		t.deepEq(
			BallPath.noise(a, { offset = 0, angle = 0, power = 1, spin = 0 }),
			BallPath.noise(b, { offset = 0, angle = 0, power = 1, spin = 0 })
		)
		BallPath.noise(a, { offset = 0, angle = 0, power = 0.7, spin = 0 })
		b.next()
		b.next()
		t.eq(a.next(), b.next())
	end)
end
