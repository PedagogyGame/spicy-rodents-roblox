--!strict
-- Minigames/Bowling/RollScript: one throw as plain data that the server scores from and every client plays
-- back. The poses it gives are continuous from the hand to the pit, standing pins never move, the count is the
-- pins that changed, a gutter ball touches nothing, the table survives the wire and anything malformed is
-- refused before it could be played.
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local BallPath = require("@shared/Minigames/Bowling/BallPath")
local PinModel = require("@shared/Minigames/Bowling/PinModel")
local RollScript = require("@shared/Minigames/Bowling/RollScript")
local Rng = require("@shared/Util/Rng")

local POCKET = { offset = 0.165, angle = 0, power = 0.7, spin = 0 } -- 0.25 right of the head pin
local GUTTER = { offset = 1, angle = 0.1, power = 0.7, spin = 0 }
local HOOK = { offset = 0.6, angle = 0.012, power = 0.7, spin = -1 }

-- a deep copy through plain values only: what a RemoteEvent would deliver
local function wire(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = wire(x)
	end
	return out
end

local function maskOf(list: { number }): { boolean }
	local m = table.create(10, false)
	for _, n in list do
		m[n] = true
	end
	return m
end

return function(t)
	t.test(
		"a pocket ball: released from the hand, hits the head pin first, pins fall, the ball ends in the pit",
		function()
			local strikes = 0
			for seed = 1, 30 do
				local s = RollScript.build(POCKET, PinModel.fullRack(), seed)
				t.eq(s.flags.gutter, false)
				t.eq(s.flags.first, true)
				t.eq(s.flags.pocket, "1-3")
				t.truthy(s.down >= 7, `seed {seed}: {s.down} pins`)
				if s.down == 10 then
					strikes += 1
					t.eq(s.flags.split, false)
				end
				t.truthy(s.tEntry > 1.5 and s.tEntry < 2.5)
				t.truthy(s.tImpact > s.tEntry and s.tImpact < s.tEntry + 0.1)
				t.truthy(s.tBallEnd > s.tImpact and s.tEnd >= s.tBallEnd + RollScript.REST)
				t.truthy(s.tEnd < 6, `the whole throw takes {s.tEnd} s`)
				-- at the release
				local x, y, d, _, where = RollScript.ball(s, 0)
				t.near(x :: number, BallPath.releaseX(POCKET.offset), 0.001)
				t.near(y, BallPath.BALL_Y, 1e-9)
				t.near(d, BallPath.RELEASE_D, 0.001)
				t.eq(where, "hand")
				-- at the end: down in the pit, in front of the cushion, between the kickbacks
				local ex, ey, ed, _, ewhere = RollScript.ball(s, s.tEnd)
				t.eq(ewhere, "pit")
				t.truthy(ey < -0.5 and ey >= AlleyLayout.PIT_Y + AlleyLayout.BALL_D / 2 - 1e-9, `ball y {ey}`)
				t.truthy(ed > AlleyLayout.DECK_END and ed <= AlleyLayout.CUSHION_D)
				t.truthy(math.abs(ex :: number) < PinModel.WALL_X)
			end
			t.truthy(strikes >= 18, `{strikes} strikes in 30 pocket balls`)
		end
	)

	t.test("pins: on their spots before the hit, lying or gone after, standing pins never move", function()
		for seed = 1, 25 do
			local params = { offset = (seed % 7 - 3) * 0.2, angle = (seed % 5 - 2) * 0.01, power = 0.7, spin = 0 }
			local s = RollScript.build(params, PinModel.fullRack(), seed)
			local changed = 0
			for n = 1, 10 do
				local sx, sd = PinModel.spot(n)
				local x0, y0, d0, tilt0, _, hidden0 = RollScript.pin(s, n, 0)
				t.eq(x0, sx)
				t.eq(d0, sd)
				t.eq(y0, 0)
				t.eq(tilt0, 0)
				t.eq(hidden0, false)
				local x1, y1, d1, tilt1, _, hidden1 = RollScript.pin(s, n, s.tEnd)
				if s.standing[n] then
					t.eq(x1, sx, "a standing pin is exactly on its spot")
					t.eq(d1, sd)
					t.eq(tilt1, 0)
					t.eq(hidden1, false)
					-- and at every moment in between
					for i = 1, 20 do
						local xi, _, di, ti = RollScript.pin(s, n, s.tEnd * i / 20)
						t.truthy(xi == sx and di == sd and ti == 0)
					end
				else
					changed += 1
					t.near(tilt1, math.pi / 2, 1e-9, "a fallen pin lies flat")
					t.truthy(y1 <= -RollScript.LIE_DROP + 1e-9)
					local inPit = ((s.deck :: PinModel.Result).pitT[n] >= 0)
					t.eq(hidden1, inPit, "in the pit means out of sight; deadwood stays in view")
					if not inPit then
						t.truthy(d1 <= AlleyLayout.DECK_END + 0.31 and math.abs(x1) <= PinModel.WALL_X)
					end
				end
			end
			t.eq(changed, s.down)
			t.eq(s.down, 10 - PinModel.count(s.standing))
		end
	end)

	t.test("playback is continuous: at 60 frames a second nothing teleports, a pin only ever tips further", function()
		for _, case in
			{ { POCKET, 3 }, { HOOK, 4 }, { GUTTER, 5 }, { { offset = 0, angle = 0, power = 1, spin = 0 }, 6 } }
		do
			local s = RollScript.build(case[1], PinModel.fullRack(), case[2])
			local speed = BallPath.speedOf((case[1] :: any).power)
			local px, py, pd = RollScript.ball(s, 0)
			local pins: { { number } } = {}
			for n = 1, 10 do
				local x, y, d, tilt = RollScript.pin(s, n, 0)
				pins[n] = { x, y, d, tilt }
			end
			local tt = 0
			while tt < s.tEnd + 0.5 do
				tt += 1 / 60
				local x, y, d = RollScript.ball(s, tt)
				local step = math.sqrt(((x :: number) - (px :: number)) ^ 2 + (y - py) ^ 2 + (d - pd) ^ 2)
				t.truthy(step <= speed / 60 * 1.1 + 0.15, `ball step {step} at {tt}`)
				px, py, pd = x, y, d
				for n = 1, 10 do
					local qx, qy, qd, tilt, _, hidden = RollScript.pin(s, n, tt)
					local q = pins[n]
					if not hidden then
						local move = math.sqrt((qx - q[1]) ^ 2 + (qd - q[3]) ^ 2)
						-- a pin leaves the ball at up to (1 + e) M / (M + 1) times its speed
						t.truthy(move <= speed * 1.5 / 60 + 0.1, `pin {n} moved {move} at {tt}`)
						t.truthy(math.abs(qy - q[2]) <= 0.35, `pin {n} dropped {qy - q[2]} at {tt}`)
					end
					t.truthy(tilt >= q[4] - 1e-9, "tilt never goes back")
					t.truthy(tilt <= math.pi / 2 + 1e-9)
					pins[n] = { qx, qy, qd, tilt }
				end
			end
		end
	end)

	t.test("a gutter ball: no pin moves, nothing is scored, the flags and the cues say gutter", function()
		local s = RollScript.build(GUTTER, PinModel.fullRack(), 9)
		t.eq(s.flags.gutter, true)
		t.eq(s.down, 0)
		t.eq(s.deck, nil)
		t.eq(s.tEntry, -1)
		t.eq(PinModel.count(s.standing), 10)
		for n = 1, 10 do
			local x, _, d, tilt = RollScript.pin(s, n, s.tEnd)
			local sx, sd = PinModel.spot(n)
			t.truthy(x == sx and d == sd and tilt == 0)
		end
		local names = {}
		for _, c in RollScript.cues(s) do
			names[c[2]] = true
		end
		t.truthy(names.gutter and names.release and names.roll and names.pit)
		t.falsy(names.pin)
		-- the ball runs the channel and drops off its end
		local x, y, d, _, where = RollScript.ball(s, s.tEnd)
		t.eq(where, "pit")
		t.truthy(math.abs(x :: number) > AlleyLayout.LANE_W / 2 and d > AlleyLayout.DECK_END and y < 0)
		-- a hook that walks off the side is a gutter ball too
		local hooked = RollScript.build({ offset = -0.8, angle = 0, power = 0.3, spin = -1 }, PinModel.fullRack(), 2)
		t.eq(hooked.flags.gutter, true)
		t.eq(hooked.down, 0)
	end)

	t.test(
		"second balls and flags: the mask is respected; splits and head-on hits are flagged on a first ball only",
		function()
			local leave = maskOf({ 6, 10 })
			local tenX = AlleyLayout.pinSpots()[10][1]
			local s = RollScript.build(
				{ offset = (tenX - 0.3) / BallPath.releaseX(1), angle = 0, power = 0.7, spin = 0 },
				leave,
				4
			)
			t.eq(s.flags.first, false)
			t.eq(s.flags.split, false)
			t.eq(s.down, 2)
			for n = 1, 10 do
				if not leave[n] then
					local _, _, _, _, _, hidden = RollScript.pin(s, n, 0)
					t.truthy(hidden, `pin {n} is not in the rack`)
					t.eq(s.standing[n], false)
				end
			end
			-- dead centre: head-on, and sooner or later a split with its name
			local sawSplit = false
			for seed = 1, 40 do
				local c = RollScript.build({ offset = 0, angle = 0, power = 0.7, spin = 0 }, PinModel.fullRack(), seed)
				t.eq(c.flags.headOn, true)
				t.eq(c.flags.pocket, nil)
				if c.flags.split then
					sawSplit = true
					t.truthy(type(c.flags.splitName) == "string" and #(c.flags.splitName :: string) >= 3)
					t.eq(c.standing[1], false)
				end
			end
			t.truthy(sawSplit)
			t.eq(
				RollScript.build({ offset = -0.165, angle = 0, power = 0.7, spin = 0 }, PinModel.fullRack(), 1).flags.pocket,
				"1-2"
			)
		end
	)

	t.test("seeded: the same throw is the same script; power outside the sweet band changes the line", function()
		t.deepEq(RollScript.build(HOOK, PinModel.fullRack(), 12), RollScript.build(HOOK, PinModel.fullRack(), 12))
		local a = RollScript.build({ offset = 0, angle = 0, power = 0.7, spin = 0 }, PinModel.fullRack(), 1)
		t.deepEq(a.params, { offset = 0, angle = 0, power = 0.7, spin = 0 })
		local wild = 0
		for seed = 1, 20 do
			local b = RollScript.build({ offset = 0, angle = 0, power = 1, spin = 0 }, PinModel.fullRack(), seed)
			if b.params.angle ~= 0 then
				wild += 1
			end
		end
		t.truthy(wild >= 19, "full power is wild")
		-- junk in, legal throw out
		local j = RollScript.build({ offset = "left", angle = 99 }, PinModel.fullRack(), 1)
		t.eq(j.params.angle, BallPath.RANGES.angle)
	end)

	t.test("cues: release first, a clatter per pin contact in time order, the pit last", function()
		local s = RollScript.build(POCKET, PinModel.fullRack(), 3)
		local cues = RollScript.cues(s)
		t.eq(cues[1][2], "release")
		t.eq(cues[#cues][2], "pit")
		local pins = 0
		for i, c in cues do
			if i > 1 then
				t.truthy(c[1] >= cues[i - 1][1], "time order")
			end
			t.truthy(c[3] > 0 and c[3] <= 1)
			if c[2] == "pin" then
				pins += 1
				t.truthy(c[1] >= s.tImpact - 1e-9)
			end
		end
		t.truthy(pins >= 2 and pins <= 10, `{pins} clatters`)
	end)

	t.test("the wire: a script survives the trip, stays small, and a damaged one is refused", function()
		local biggest = 0
		for seed = 1, 40 do
			local params = {
				offset = (seed % 9 - 4) * 0.12,
				angle = (seed % 5 - 2) * 0.008,
				power = (seed % 10) / 10,
				spin = (seed % 3 - 1),
			}
			local s = RollScript.build(params, PinModel.fullRack(), seed)
			local w = wire(s)
			local got, why = RollScript.check(w)
			t.truthy(got ~= nil, `seed {seed}: {why}`)
			t.deepEq(got, s)
			biggest = math.max(biggest, RollScript.size(s))
		end
		t.truthy(biggest < 700, `the largest script carries {biggest} numbers`)
		local fake = RollScript.fake(PinModel.fullRack(), 4)
		t.truthy(RollScript.check(wire(fake)) ~= nil, "a scripted pinfall is playable too")

		local function broken(change: (w: any) -> ()): string?
			local w = wire(RollScript.build(POCKET, PinModel.fullRack(), 3))
			change(w)
			local got, why = RollScript.check(w)
			t.eq(got, nil)
			return why
		end
		t.eq(RollScript.check(nil), nil)
		t.eq(RollScript.check("roll"), nil)
		t.eq(
			broken(function(w)
				w.v = 2
			end),
			"version"
		)
		t.eq(
			broken(function(w)
				table.remove(w.mask)
			end),
			"masks"
		)
		t.eq(
			broken(function(w)
				w.down = 3.5
			end),
			"count"
		)
		t.eq(
			broken(function(w)
				w.mask[2] = false
				w.standing[2] = true
			end),
			"a pin stood up"
		)
		t.eq(
			broken(function(w)
				w.path.samples[5] = 0 / 0
			end),
			"path sample"
		)
		t.eq(
			broken(function(w)
				table.remove(w.path.samples)
			end),
			"path"
		)
		t.eq(
			broken(function(w)
				w.path.samples[4] = -1
			end),
			"path sample"
		)
		t.eq(
			broken(function(w)
				w.deck.ball[2] = 900
			end),
			"deck ball"
		)
		t.eq(
			broken(function(w)
				w.deck.pins[1] = { 0, 0, 56, 1 }
			end),
			"deck pin"
		)
		t.eq(
			broken(function(w)
				w.deck.pins[1] = "x"
			end),
			"deck pin"
		)
		t.eq(
			broken(function(w)
				w.deck.hitT[1] = -1
			end),
			"deck pin motion"
		)
		t.eq(
			broken(function(w)
				w.tEnd = math.huge
			end),
			"times"
		)
		t.eq(
			broken(function(w)
				w.params.power = 7
			end),
			"params"
		)
		t.eq(
			broken(function(w)
				w.flags = nil
			end),
			"flags"
		)
		t.eq(
			broken(function(w)
				w.path = nil
				w.deck = nil
			end),
			"nothing to play"
		)
		local huge = {}
		for i = 1, 3 * 131 do
			huge[i] = i
		end
		t.eq(
			broken(function(w)
				w.path.samples = huge
			end),
			"path"
		)
	end)

	t.test(
		"every throw the server can build passes the clients' check: slow balls that push a pin along included",
		function()
			-- a quick tap of Space is a throw at almost no power. A slow ball stays against a pin for many steps
			-- of the model and writes a key point on each; the check once allowed 80 a piece and refused those
			-- throws on every client although the server had scored them
			local rng = Rng.new(77)
			local longest, biggest, long = 0, 0, 0
			for i = 1, 3000 do
				local band = if i % 3 == 0 then 0.4 else 0.15
				local params = {
					offset = rng.range(-1, 1),
					angle = rng.range(-0.05, 0.05),
					power = rng.range(0, band),
					spin = rng.range(-1, 1),
				}
				local seed = rng.int(1, 2147483646)
				local s = RollScript.build(params, PinModel.fullRack(), seed)
				local got, why = RollScript.check(wire(s))
				t.truthy(got ~= nil, `throw {i} (power {params.power}, seed {seed}) was refused: {why}`)
				local deck = s.deck
				if deck then
					local most = #deck.ball // 5
					for n = 1, 10 do
						most = math.max(most, #deck.pins[n] // 5)
					end
					t.truthy(most <= PinModel.MAX_KEYS, `throw {i}: {most} key points on one piece`)
					longest = math.max(longest, most)
					if most > 80 then
						long += 1
					end
				end
				biggest = math.max(biggest, RollScript.size(s))
			end
			t.truthy(long >= 5, `only {long} of these throws carry more than 80 key points: the test lost its teeth`)
			t.truthy(longest < PinModel.MAX_KEYS / 2, `the longest piece carries {longest} key points`)
			-- what the worst of them costs to send (numbers): a tripwire, not a budget
			t.truthy(biggest < 8000, `the largest slow throw carries {biggest} numbers`)
			-- the throw the review named
			local named = RollScript.build(
				{ offset = 0.4559424542505294, angle = 0.03297907017432154, power = 0, spin = -0.5 },
				PinModel.fullRack(),
				1806522228
			)
			t.truthy(RollScript.check(wire(named)) ~= nil)
			-- the limit is still a limit: more key points than the model can write is refused
			local w = wire(RollScript.build(POCKET, PinModel.fullRack(), 3))
			local flood = {}
			for k = 1, PinModel.MAX_KEYS + 1 do
				local o = 5 * (k - 1)
				flood[o + 1], flood[o + 2], flood[o + 3], flood[o + 4], flood[o + 5] = k / 1000, 0, 60, 0, 1
			end
			w.deck.ball = flood
			local got, why = RollScript.check(w)
			t.eq(got, nil)
			t.eq(why, "deck ball")
		end
	)

	t.test("a scripted pinfall (the engine smoke's stand-in): n pins tip where they stand, no ball", function()
		local s = RollScript.fake(maskOf({ 1, 2, 3, 7 }), 3)
		t.eq(s.down, 3)
		t.deepEq(s.standing, maskOf({ 7 }))
		t.eq((RollScript.ball(s, 0.2)), nil)
		local x, y, d, tilt, _, hidden = RollScript.pin(s, 1, s.tEnd)
		local sx, sd = PinModel.spot(1)
		t.truthy(x == sx and d == sd and not hidden)
		t.near(tilt, math.pi / 2, 1e-9)
		t.truthy(y < 0)
		t.eq(RollScript.fake(PinModel.fullRack(), 10).down, 10)
		t.eq(RollScript.fake(PinModel.fullRack(), 0).down, 0)
		t.eq(RollScript.fake(maskOf({ 4 }), 9).down, 1, "never more than stand")
		t.eq(#RollScript.cues(s), 0)
	end)
end
