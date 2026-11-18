--!strict
-- Minigames/Bowling/PinModel: the server's pinfall. Statistical tests on fixed seeds (so they never flake):
-- strikes need the pocket, a dead-centre hit leaves splits, a thin hit never strikes, an edge ball takes a
-- corner, a ball past every pin takes none; second balls respect the pins that stand; spares convert on the
-- right line and the 7-10 does not; the same throw is always the same result; the recorded motion is
-- continuous (what playback draws is what was decided); and it is cheap.
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local PinModel = require("@shared/Minigames/Bowling/PinModel")

local N = 300

local function entry(x: number, degrees: number, speed: number): PinModel.Entry
	local a = math.rad(degrees)
	return { x = x, vx = speed * math.sin(a), vd = speed * math.cos(a) }
end

type Stats = { strike: number, mean: number, split: number, headUp: number, leaves: { [string]: number } }

local function run(e: PinModel.Entry, mask: { boolean }?, n: number?): Stats
	local count = n or N
	local strikes, total, splits, headUp = 0, 0, 0, 0
	local leaves: { [string]: number } = {}
	for seed = 1, count do
		local r = PinModel.roll(e, mask or PinModel.fullRack(), seed)
		total += r.down
		if PinModel.count(r.standing) == 0 then
			strikes += 1
		end
		if PinModel.isSplit(r.standing) then
			splits += 1
		end
		if r.standing[1] then
			headUp += 1
		end
		local name = {}
		for i = 1, 10 do
			if r.standing[i] then
				table.insert(name, tostring(i))
			end
		end
		local key = table.concat(name, "-")
		leaves[key] = (leaves[key] or 0) + 1
	end
	return {
		strike = strikes / count,
		mean = total / count,
		split = splits / count,
		headUp = headUp / count,
		leaves = leaves,
	}
end

local function maskOf(list: { number }): { boolean }
	local m = table.create(10, false)
	for _, n in list do
		m[n] = true
	end
	return m
end

return function(t)
	t.test("the pocket strikes: a ball between the 1 and the 3 (or the 1 and the 2) carries the rack", function()
		for _, speed in { 20, 26, 32 } do
			local right = run(entry(0.25, 0, speed))
			local left = run(entry(-0.25, 0, speed))
			t.truthy(right.strike >= 0.6, `speed {speed}: 1-3 pocket strikes {right.strike}`)
			t.truthy(right.mean >= 9.5, `speed {speed}: 1-3 pocket mean {right.mean}`)
			t.truthy(left.strike >= 0.6, `speed {speed}: 1-2 pocket strikes {left.strike}`)
			t.truthy(left.mean >= 9.5, `speed {speed}: 1-2 pocket mean {left.mean}`)
			t.truthy(math.abs(right.strike - left.strike) <= 0.12, "left and right pockets agree")
		end
		-- a hooked ball coming in at an angle carries too, and forgives a wider line than a straight one
		local angled = run(entry(0.33, -4, 26))
		t.truthy(angled.strike >= 0.6 and angled.mean >= 9.5, `angled pocket {angled.strike} / {angled.mean}`)
		local function window(degrees: number): number
			local area = 0
			for i = 0, 12 do
				local xHead = i * 0.05
				local x = xHead - (AlleyLayout.HEAD_D - AlleyLayout.DECK_START) * math.tan(math.rad(degrees))
				area += run(entry(x, degrees, 26), nil, 80).strike * 0.05
			end
			return area
		end
		local flat, steep = window(0), window(-5)
		t.truthy(steep > flat * 1.2, `the strike window: {flat} studs straight, {steep} at five degrees`)
	end)

	t.test("dead centre is not a strike ball: few strikes, many splits", function()
		local pocket = run(entry(0.25, 0, 26))
		for _, speed in { 20, 26, 32 } do
			local head = run(entry(0, 0, speed))
			t.truthy(head.strike <= 0.25, `speed {speed}: head-on strikes {head.strike}`)
			t.truthy(head.strike < pocket.strike / 2, "well under the pocket's rate")
			t.truthy(head.split >= 0.15, `speed {speed}: head-on splits {head.split}`)
			t.truthy(head.mean >= 7 and head.mean <= 9.2, `speed {speed}: head-on mean {head.mean}`)
			t.eq(head.headUp, 0, "the head pin always goes")
		end
	end)

	t.test(
		"thin, edge and wide: a light hit never strikes, an edge ball takes a corner, a wide ball nothing",
		function()
			for _, side in { 1, -1 } do
				local thin = run(entry(0.75 * side, 0, 26))
				t.truthy(thin.strike <= 0.03, `thin strikes {thin.strike}`)
				t.truthy(thin.mean >= 5 and thin.mean <= 8.5, `thin mean {thin.mean}`)
				local edge = run(entry(1.5 * side, 0, 26))
				t.truthy(edge.mean >= 2 and edge.mean <= 5, `edge mean {edge.mean}`)
				t.truthy(edge.headUp >= 0.95, `edge: head pin stands {edge.headUp}`)
				t.eq(edge.strike, 0)
				local wide = run(entry(2.45 * side, 0, 26), nil, 40)
				t.eq(wide.mean, 0, "past the corner pin: nothing")
			end
			-- mirrored lines agree
			local a, b = run(entry(0.75, 0, 26)), run(entry(-0.75, 0, 26))
			t.truthy(math.abs(a.mean - b.mean) <= 0.6, `thin left {b.mean} right {a.mean}`)
		end
	)

	t.test("power matters: over a spread of lines a feeble ball knocks down fewer than a firm one", function()
		local function spread(speed: number): number
			local total = 0
			for i = -6, 6 do
				total += run(entry(i * 0.15, 0, speed), nil, 60).mean
			end
			return total / 13
		end
		local slow, firm = spread(16), spread(28)
		t.truthy(slow < firm, `slow {slow} against firm {firm}`)
	end)

	t.test("deterministic and seeded: same throw same result; different seeds differ; counts are honest", function()
		local e = entry(0.1, -1, 24)
		t.deepEq(PinModel.roll(e, PinModel.fullRack(), 77), PinModel.roll(e, PinModel.fullRack(), 77))
		local leaves = 0
		for _ in run(entry(0, 0, 26), nil, 50).leaves do
			leaves += 1
		end
		t.truthy(leaves >= 2, `{leaves} different leaves from 50 dead-centre balls`)
		for seed = 1, 60 do
			local x = (seed % 13 - 6) * 0.2
			local r = PinModel.roll(entry(x, (seed % 5 - 2) * 2, 18 + seed % 16), PinModel.fullRack(), seed)
			t.eq(r.down, 10 - PinModel.count(r.standing))
			t.truthy(r.down >= 0 and r.down <= 10)
			t.truthy(r.tEnd <= PinModel.MAX_T + 0.01 and r.tEnd > 0)
			for n = 1, 10 do
				if r.standing[n] then
					t.eq(#r.pins[n], 0, "a standing pin never moved")
					t.eq(r.hitT[n], -1)
				else
					t.truthy(#r.pins[n] >= 10 and #r.pins[n] % 5 == 0, "a fallen pin has its motion")
					t.truthy(r.hitT[n] >= 0)
				end
			end
		end
	end)

	t.test("second balls: only pins that stand can fall; a pin never stands back up", function()
		local mask = maskOf({ 4, 7, 10 })
		for seed = 1, 60 do
			local r = PinModel.roll(entry(-1.3, 0, 24), mask, seed)
			t.truthy(r.down <= 3)
			for n = 1, 10 do
				if not mask[n] then
					t.eq(r.standing[n], false, `pin {n} was not there`)
					t.eq(#r.pins[n], 0)
				end
			end
			t.eq(r.down, 3 - PinModel.count(r.standing))
		end
		local none = PinModel.roll(entry(0, 0, 24), table.create(10, false), 3)
		t.eq(none.down, 0)
		t.eq(none.firstHit, nil)
		t.eq(PinModel.count(none.standing), 0)
	end)

	t.test("spares: the 10-pin, the 3-10 and the bucket convert on the right line; the 7-10 does not", function()
		local tenX = AlleyLayout.pinSpots()[10][1]
		local ten = maskOf({ 10 })
		t.eq(run(entry(tenX - 0.5, 0, 24), ten, 100).mean, 1, "half a stud inside the 10-pin takes it")
		t.eq(run(entry(tenX, 0, 24), ten, 100).mean, 1)
		t.eq(run(entry(tenX - 0.8, 0, 24), ten, 100).mean, 0, "0.8 inside misses it")
		-- the 7-10: no straight line takes both
		local best = 0
		for i = -12, 12 do
			local s = run(entry(i * 0.2, 0, 26), maskOf({ 7, 10 }), 40)
			best = math.max(best, s.strike)
			t.truthy(s.mean <= 1.05, `line {i * 0.2}: {s.mean}`)
		end
		t.truthy(best <= 0.02, `7-10 converted {best}`)
		-- the 3-10 baby split: clip the 3 on its right side and it takes the 10 (or the ball does)
		local threeX = AlleyLayout.pinSpots()[3][1]
		local baby, bestBaby = maskOf({ 3, 10 }), 0
		for i = 0, 8 do
			bestBaby = math.max(bestBaby, run(entry(threeX + 0.2 + i * 0.05, 0, 24), baby, 60).strike)
		end
		t.truthy(bestBaby >= 0.8, `3-10 converts {bestBaby} on its best line`)
		-- the 2-4-5 bucket: hit the 2 a little left of centre
		local bucket, bestBucket = maskOf({ 2, 4, 5 }), 0
		for i = -4, 4 do
			bestBucket =
				math.max(bestBucket, run(entry(AlleyLayout.pinSpots()[2][1] + i * 0.06, 0, 24), bucket, 60).strike)
		end
		t.truthy(bestBucket >= 0.8, `2-4-5 converts {bestBucket} on its best line`)
	end)

	t.test("splits are named by the columns left standing", function()
		local function split(list: { number }): (boolean, string?)
			return PinModel.isSplit(maskOf(list))
		end
		local yes, name = split({ 7, 10 })
		t.truthy(yes)
		t.eq(name, "7-10")
		t.truthy(split({ 4, 6 }))
		t.truthy(split({ 3, 10 }))
		t.truthy(split({ 5, 7 }))
		t.truthy(split({ 4, 6, 7, 10 }))
		t.truthy(split({ 5, 6 }))
		t.falsy(split({ 2, 8 }), "one pin hiding behind another is not a split")
		t.falsy(split({ 2, 4, 5 }))
		t.falsy(split({ 10 }))
		t.falsy(split({}))
		t.falsy(split({ 1, 7, 10 }), "never with the head pin standing")
		t.falsy(split({ 6, 10 }))
		t.falsy(split({ 3, 6, 9, 10 }))
	end)

	t.test(
		"the recorded motion is what was simulated: continuous key points, rest where it ended, pit times",
		function()
			local F = PinModel.FRICTION
			local sawPit, sawRest, sawWall = false, false, false
			for seed = 1, 40 do
				local r = PinModel.roll(
					entry((seed % 9 - 4) * 0.15, (seed % 3 - 1) * 3, 20 + seed % 13),
					PinModel.fullRack(),
					seed
				)
				-- the ball: straight between key points, starting at the deck's edge
				t.eq(r.ball[1], 0)
				t.near(r.ball[3], AlleyLayout.DECK_START, 1e-9)
				t.truthy(#r.ball % 5 == 0 and #r.ball >= 10)
				for i = 6, #r.ball, 5 do
					local x, d = PinModel.segAt(r.ball, r.ball[i] - 1e-6, 0)
					t.near(x, r.ball[i + 1], 0.02, "ball x across a key point")
					t.near(d, r.ball[i + 2], 0.02, "ball d across a key point")
				end
				t.near(r.ball[#r.ball - 4], r.ballEnd, 1e-9)
				for n = 1, 10 do
					local keys = r.pins[n]
					if #keys > 0 then
						local sx, sd = PinModel.spot(n)
						t.near(keys[2], sx, PinModel.SPOT_JITTER + 0.01, "it starts on its spot")
						t.near(keys[3], sd, PinModel.SPOT_JITTER + 0.01)
						t.near(keys[1], r.hitT[n], 1e-9, "its first key point is when it was hit")
						for i = 6, #keys, 5 do
							t.truthy(keys[i] >= keys[i - 5], "time")
							local x, d = PinModel.segAt(keys, keys[i] - 1e-6, F)
							-- a pin stopped by a kickback is put back on the wall's face: allow that one step
							local atWall = math.abs(keys[i + 1]) >= PinModel.WALL_X - PinModel.REACH - 0.002
							local tol = if atWall then 0.1 else 0.006
							t.near(x, keys[i + 1], tol, `pin {n} x across a key point (seed {seed})`)
							t.near(d, keys[i + 2], tol, `pin {n} d across a key point (seed {seed})`)
							sawWall = sawWall or atWall
						end
						-- before it was hit it is on its spot; long after, it has stopped
						local x0, d0, m0 = PinModel.segAt(keys, 0, F)
						t.eq(x0, keys[2])
						t.eq(d0, keys[3])
						t.falsy(m0)
						local _, dEnd, mEnd = PinModel.segAt(keys, 60, F)
						t.falsy(mEnd)
						if r.pitT[n] >= 0 then
							sawPit = true
							t.truthy(dEnd > AlleyLayout.DECK_END, "a pin in the pit went over the edge")
						else
							sawRest = true
							t.truthy(dEnd <= AlleyLayout.DECK_END + 0.31, "a pin left on the deck is on the deck")
							t.truthy(math.abs(keys[#keys - 3]) <= PinModel.WALL_X, "inside the kickbacks")
						end
					end
				end
			end
			t.truthy(sawPit and sawRest and sawWall, "pins went to the pit, stayed as deadwood and hit the kickbacks")
		end
	)

	t.test("what the ball met first: the pocket, the nose, or nothing", function()
		local r = PinModel.roll(entry(0.25, 0, 26), PinModel.fullRack(), 1)
		t.eq(r.firstPin, 1)
		t.truthy((r.hitX :: number) > 0.15 and (r.hitX :: number) < 0.35)
		t.truthy((r.firstHit :: number) > 0.01 and (r.firstHit :: number) < 0.1)
		local wide = PinModel.roll(entry(2.2, 0, 26), PinModel.fullRack(), 1)
		t.eq(wide.firstPin, 10)
		local miss = PinModel.roll(entry(2.45, 0, 26), PinModel.fullRack(), 1)
		t.eq(miss.firstPin, nil)
		t.eq(miss.down, 0)
		t.truthy(miss.ballEnd > 0.15 and miss.ballEnd < 0.4, "the ball still runs off the deck")
		t.eq(#miss.ball, 10)
	end)

	t.test("regression: five golden throws keep their exact leaves", function()
		local golden: { { any } } = {
			{ 0.25, 0, 26, 1, "8" },
			{ 0, 0, 26, 2, "4-6-7-10" },
			{ 0.75, 0, 26, 3, "1-2-4-8" },
			{ 1.5, 0, 24, 4, "1-2-3-4-5-7-8" },
			{ -0.3, 4, 30, 5, "" },
		}
		for _, g in golden do
			local r = PinModel.roll(entry(g[1], g[2], g[3]), PinModel.fullRack(), g[4])
			local name = {}
			for n = 1, 10 do
				if r.standing[n] then
					table.insert(name, tostring(n))
				end
			end
			t.eq(table.concat(name, "-"), g[5], `seed {g[4]}`)
		end
	end)

	t.test("cheap: a full-rack roll costs well under five milliseconds", function()
		local started = os.clock()
		for seed = 1, 50 do
			PinModel.roll(entry(0.2, -2, 26), PinModel.fullRack(), seed)
		end
		local ms = (os.clock() - started) / 50 * 1000
		t.truthy(ms < 5, `{ms} ms a roll`)
	end)
end
