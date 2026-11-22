--!strict
-- Minigames/Bowling/BallPath (brief v2 §13a "choose your angle and power, bowl"; owner D32 "no way to put any
-- angle or twist"): the ball's line from the hand to the pin deck: speed from power, the angle, the hook as real
-- bowling has it (it skids on the oil, hooks on the dry back end, then rolls straight on; more spin and a slower
-- ball bend more; the direction of the spin is the direction of the hook; a straight ball stays straight), gutters
-- that keep the ball, the sweet band of the power meter, and the samples (with the spin) playback reads.
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
			t.truthy(e.t > expect and e.t < expect * 1.2, `power {power}: {e.t} s against {expect}`)
			-- (it skids until its spin catches up, then rolls: it loses a fifth of its speed or so, never a third)
			t.truthy(e.vd < speed and e.vd > speed * 0.67, `power {power}: {e.vd} at the deck from {speed}`)
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

	t.test("hook: it skids on the oil, hooks on the dry back end, then rolls straight on", function()
		local straight = throw(0.6, 0, 0.7, 0)
		local hooked = throw(0.6, 0, 0.7, -1)
		-- on the oil the hook ball barely leaves the straight line (a skid: a few boards at most)
		local tOil = (BallPath.HOOK_START - BallPath.RELEASE_D) / BallPath.speedOf(0.7)
		for i = 0, 10 do
			local tt = tOil * i / 10
			local xa = BallPath.at(straight, tt)
			local xb = BallPath.at(hooked, tt)
			t.truthy(xa - xb >= -1e-9 and xa - xb < 0.35, `on the oil at {tt}: {xa - xb} studs apart`)
		end
		local e0 = straight.entry :: BallPath.Entry
		local e1 = hooked.entry :: BallPath.Entry
		-- most of the break comes on the back end: more in the last third than in the first two
		local xOil = BallPath.at(hooked, tOil)
		t.truthy((e0.x - e1.x) - (BallPath.at(straight, tOil) - xOil) > 2 * (BallPath.at(straight, tOil) - xOil))
		t.truthy(e0.x - e1.x > 1 and e0.x - e1.x < 2.5, `full hook breaks {e0.x - e1.x} studs`)
		-- full hook at medium power comes into the pins at five to eight degrees
		local deg = math.deg(math.atan2(-e1.vx, e1.vd))
		t.truthy(deg >= 5 and deg <= 8, `entry angle {deg}`)
		-- it stopped skidding on the back end, and from there it rolls: its spin goes the way it goes
		local rollD = hooked.rollD :: number
		t.truthy(rollD ~= nil and rollD > BallPath.OIL_D and rollD < AlleyLayout.DECK_START, `rolls from {rollD}`)
		t.near(e1.rx, e1.vx, 0.002)
		t.near(e1.rd, e1.vd, 0.002)
		-- once rolling it goes straight on: the last samples lie on one line
		local s = hooked.samples
		local n = #s // 3
		local slopes = {}
		for k = n - 3, n - 1 do
			if s[3 * k] > rollD + 1 then
				table.insert(slopes, (s[3 * k + 2] - s[3 * k - 1]) / (s[3 * k + 3] - s[3 * k]))
			end
		end
		t.truthy(#slopes >= 2)
		for _, sl in slopes do
			t.near(sl, slopes[1], 0.004, "rolling straight after the hook")
		end
		-- more spin bends more; a slower ball bends more, a harder one less
		local half = throw(0.6, 0, 0.7, -0.5).entry :: BallPath.Entry
		t.truthy(e1.x < half.x and half.x < e0.x, "hook left moves left, more with more spin")
		local soft = throw(1, 0, 0.35, -1).entry :: BallPath.Entry
		local hard = throw(1, 0, 1, -1).entry :: BallPath.Entry
		local mid = throw(1, 0, 0.7, -1).entry :: BallPath.Entry
		t.truthy(soft.x < mid.x - 0.5 and mid.x < hard.x - 0.2, `breaks {soft.x} {mid.x} {hard.x}`)
		-- and however soft, never more than about fourteen degrees across the lane
		local softest = throw(1, 0, 0.1, -1)
		local sx = softest.samples
		local worst = 0
		for k = 3, #sx // 3 do
			local dx = sx[3 * k - 1] - sx[3 * k - 4]
			local dd = sx[3 * k] - sx[3 * k - 3]
			if dd > 0.01 and (softest.gutterT == nil or sx[3 * k - 2] < softest.gutterT) then
				worst = math.max(worst, math.abs(math.deg(math.atan2(dx, dd))))
			end
		end
		t.truthy(worst < 14, `the softest full hook turns {worst} degrees`)
		-- spin direction honoured: hook right is the mirror, bending right
		local r = throw(-0.6, 0, 0.7, 1).entry :: BallPath.Entry
		t.near(r.x, -e1.x, 1e-9)
		t.near(r.vx, -e1.vx, 1e-9)
		t.truthy(r.vx > 0 and r.x > (throw(-0.6, 0, 0.7, 0).entry :: BallPath.Entry).x + 1)
	end)

	t.test("a straight ball is still possible: no spin, no bend, from anywhere on the line at any angle", function()
		for _, c in { { 0, 0, 0.7 }, { 0.8, -0.05, 0.4 }, { -0.5, 0.03, 1 }, { 0.3, 0, 0 } } do
			local path = throw(c[1], c[2], c[3], 0)
			local e = path.entry :: BallPath.Entry
			t.truthy(e ~= nil)
			-- the angle it left the hand at is the angle it arrives at
			t.near(math.atan2(e.vx, e.vd), c[2], 1e-3, `throw {c[1]} {c[2]} {c[3]}`)
			t.near(e.x, BallPath.releaseX(c[1]) + math.tan(c[2]) * (AlleyLayout.DECK_START - BallPath.RELEASE_D), 0.02)
			-- its spin rolls it the way it goes all the way
			for i = 1, #path.spin, 2 do
				t.near(path.spin[i], c[2], 2e-3)
			end
		end
	end)

	t.test("the spin is drawn: its axis starts turned toward the hook and comes round to the line", function()
		local path = throw(0.6, 0.02, 0.7, -1)
		local w = path.spin
		t.eq(#w, 2 * (#path.samples // 3))
		t.near(w[1], 0.02 - BallPath.AXIS_MAX, 1e-3, "at the release the spin is turned toward the hook's side")
		local e = path.entry :: BallPath.Entry
		t.near(w[#w - 1], math.atan2(e.vx, e.vd), 2e-3, "by the pins it rolls the way it goes")
		for i = 4, #w, 2 do
			t.truthy(w[i] > w[i - 2], "the ball keeps turning")
		end
		local _, _, _, turn, heading = BallPath.at(path, 1)
		t.truthy(turn > 10 and heading < 0.02, `{turn} radians turned, heading {heading}`)
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
