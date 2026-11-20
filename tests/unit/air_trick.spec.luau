--!strict
-- The air trick (owner D17, redone by D18) and the grab-leap cooldown: the motor's rule (Shared/Movement/SquirrelMotor:
-- doTrick, reaim, trickReachAt, landingIn, the roll's carry, grabLeapCooldown), its packet fields (Shared/Movement/
-- SquirrelWire, SquirrelMotor.fieldCheck), the pose and the attributes others see (Shared/Movement/AirTrick), the aim's
-- controls (Client/Controllers/Squirrel.aimOf, Client/UI/AirTrickButton), the marker (Client/UI/AimMarker) and the help.
-- Prints the out / in table (flat ground, a leap pressed at each moment) and the chain paces.
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local SquirrelWire = require("@shared/Movement/SquirrelWire")
local AirTrick = require("@shared/Movement/AirTrick")
local AirTrickButton = require("@client/UI/AirTrickButton")
local AimMarker = require("@client/UI/AimMarker")
local Squirrel = require("@client/Controllers/Squirrel")
local InputMap = require("@client/Input/InputMap")
local PlayMenu = require("@client/UI/PlayMenu")
local AnimationDriver = require("@client/Animation/AnimationDriver")
local Units = require("@shared/Config/Units")
local TestWorld = require("@tests/cheat/TestWorld")

type State = SquirrelMotor.State

local P = SquirrelMotor.params

local function across(s: State): number
	return math.sqrt(s.vx * s.vx + s.vz * s.vz)
end

return function(t)
	local world = TestWorld.build({ boxes = {} })
	-- (open ground at the south-west, running north: no route within reach)
	local function fresh(): State
		return SquirrelMotor.new(Units.st(-560), world.groundHeight, Units.st(-545))
	end
	local function keys(o: { [string]: any }?): SquirrelMotor.Input
		local i = SquirrelMotor.idleInput(math.pi)
		for k, v in o or {} do
			(i :: any)[k] = v
		end
		return i
	end
	local function step(s: State, o: { [string]: any }?): { SquirrelMotor.Event }
		local _, events = SquirrelMotor.step(s, keys(o), 1 / 60, world)
		return events
	end
	local function has(events: { SquirrelMotor.Event }, kind: string, reason: string?): boolean
		for _, e in events do
			if e.kind == kind and (reason == nil or e.reason == reason) then
				return true
			end
		end
		return false
	end
	local function landIn(s: State): number
		return SquirrelMotor.landingIn(s.x, s.y, s.z, s.vx, s.vy, s.vz, world)
	end

	t.test("mid-jump the wiggle, once a flight; as you land the roll; nothing on the ground otherwise", function()
		local s = fresh()
		t.falsy(has(step(s, { trick = true }), "trick"), "standing: nothing")
		step(s, { fw = 1, leap = true })
		t.falsy(s.grounded)
		for _ = 1, 10 do
			step(s, { fw = 1 })
		end
		local e = step(s, { fw = 1, trick = true })
		t.truthy(has(e, "trick", "wiggle"), "mid-jump: the wiggle")
		t.eq(s.trickKind, 2)
		t.truthy(s.trickReach > 0 and s.trickReach <= P.trickOutPeak, `a reach out ({s.trickReach})`)
		for _ = 1, 8 do
			t.falsy(has(step(s, { fw = 1, trick = true }), "trick"), "again mid-jump: nothing (once a flight)")
		end
		-- pressed every frame on the way down: the roll comes when touchdown is close, no sooner
		local rolled = false
		for _ = 1, 120 do
			local near = s.vy <= 0 and landIn(s) <= P.trickLand
			local ev = step(s, { fw = 1, trick = true })
			if has(ev, "trick", "roll") then
				t.truthy(near, "the roll only with touchdown within trickLand")
				rolled = true
				break
			end
		end
		t.truthy(rolled, "as it lands: the roll")
		t.eq(s.trickKind, 1)
		while not s.grounded do
			step(s, { fw = 1 })
		end
		t.eq(s.aimYaw, 0, "the landing ends the re-aim")
		t.eq(s.aimReach, 0)
		-- the roll plays on along the ground at the speed it landed with: no more, no less, the keys ignored
		local landed = across(s)
		local frames = 0
		while s.trickKind == 1 do
			step(s, { fw = -1, side = 1 })
			if s.trickKind == 1 then
				t.near(across(s), landed, 1e-6, "the roll carries the landing's speed")
				frames += 1
			end
		end
		t.truthy(frames > 10, `the roll rolled on along the ground ({frames} frames)`)
		t.truthy(has(step(s, { fw = 1 }), "trick") == false)
		t.truthy(across(s) < landed, "after the roll the ground takes the speed again")
		-- on the ground just after a landing (within trickLandGrace): the roll; later: nothing
		local g = fresh()
		step(g, { fw = 1, leap = true })
		while not g.grounded do
			step(g, { fw = 1 })
		end
		t.truthy(has(step(g, { fw = 1, trick = true }), "trick", "roll"), "on the landing frame: the roll")
		local h = fresh()
		step(h, { fw = 1, leap = true })
		while not h.grounded do
			step(h, { fw = 1 })
		end
		for _ = 1, math.ceil(P.trickLandGrace * 60) + 1 do
			step(h, { fw = 1 })
		end
		t.falsy(has(step(h, { fw = 1, trick = true }), "trick"), "a moment after landing: nothing")
		-- the next flight has its wiggle again
		step(h, { fw = 1, leap = true })
		for _ = 1, 10 do
			step(h, { fw = 1 })
		end
		t.truthy(has(step(h, { fw = 1, trick = true }), "trick", "wiggle"), "the next flight: a wiggle again")
		-- a leap off the ground ends a roll's carry
		local r = fresh()
		step(r, { fw = 1, leap = true })
		while not r.grounded do
			step(r, { fw = 1 })
		end
		step(r, { trick = true })
		t.eq(r.trickKind, 1)
		step(r, { fw = 1, leap = true })
		t.eq(r.trickKind, 0, "a leap ends the roll")
	end)

	t.test("not on a rail, not in a pounce's window; the meter pays 10 % for a wiggle, nothing when empty", function()
		local trunk = world.registry:get(220) :: any
		local foot = world.registry:foot(trunk)
		local s = SquirrelMotor.new(foot.x, world.groundHeight, foot.z - Units.st(1.2))
		step(s, { grab = true })
		t.eq(s.routeId, 220)
		t.falsy(has(step(s, { trick = true }), "trick"), "on a rail: nothing")
		local q = fresh()
		step(q, { fw = 1, pounce = true })
		t.truthy(q.attackWindow > 0)
		t.falsy(has(step(q, { fw = 1, trick = true }), "trick"), "in a pounce's window: nothing")
		local m = fresh()
		step(m, { fw = 1, leap = true })
		for _ = 1, 10 do
			step(m, { fw = 1 })
		end
		local before = m.stamina
		step(m, { fw = 1, trick = true })
		t.near(m.stamina, before - P.trickCost, 1e-9, "a wiggle takes trickCost of the meter")
		local w = fresh()
		w.stamina, w.winded = 0, true
		step(w, { fw = 1, leap = true })
		for _ = 1, 10 do
			step(w, { fw = 1 })
		end
		t.truthy(has(step(w, { fw = 1, trick = true }), "trick", "wiggle"), "an empty meter: the wiggle still plays")
		t.eq(w.stamina, 0, "and costs nothing")
		local low = fresh()
		step(low, { fw = 1, leap = true })
		for _ = 1, 10 do
			step(low, { fw = 1 })
		end
		low.stamina = 0.04
		step(low, { fw = 1, trick = true })
		t.eq(low.stamina, 0, "a meter under 10 % is emptied, no further")
		t.truthy(low.winded, "and winded")
		t.eq(P.trickCost, 0.1)
	end)

	t.test("the re-aim: up to 30 degrees either side at the speed across it had, at a bounded rate", function()
		-- reaim itself: the turn held to trickAimYaw and trickYawRate x dt, the speed across kept
		local s = SquirrelMotor.new(0, 10, 0)
		s.vx, s.vy, s.vz, s.trickKind, s.trickReach = 0, 5, 30, 2, 0.1
		SquirrelMotor.reaim(s, 2, nil, 1 / 60)
		t.near(s.aimYaw, P.trickYawRate / 60, 1e-12, "a frame's turn at most")
		t.near(across(s), 30, 1e-9, "speed across kept")
		t.near(math.atan2(s.vx, s.vz), P.trickYawRate / 60, 1e-9, "the velocity turned as much")
		for _ = 1, 60 do
			SquirrelMotor.reaim(s, 2, nil, 1 / 60)
		end
		t.near(s.aimYaw, P.trickAimYaw, 1e-12, "no more than 30 degrees")
		t.near(math.atan2(s.vx, s.vz), P.trickAimYaw, 1e-9)
		t.near(across(s), 30, 1e-9)
		t.eq(s.vy, 5, "a turn leaves the vertical speed")
		-- in the motor: a leap north, no keys, the camera's turn asked from the press: the landing turned 30 degrees
		local function flight(yaw: number?): State
			local f = fresh()
			step(f, { fw = 1, leap = true })
			for _ = 1, 10 do
				step(f, {})
			end
			step(f, { trick = yaw ~= nil })
			while not f.grounded do
				step(f, { aimYaw = yaw })
			end
			return f
		end
		local z0, x0 = fresh().z, fresh().x
		local straight, left, right = flight(nil), flight(-1), flight(1)
		local function bearing(f: State): number
			return math.deg(math.atan2(f.x - x0, f.z - z0))
		end
		print(
			string.format(
				"      a leap north, the aim swung full either way from 0.18 s in: lands at %.1f / %.1f degrees (straight %.1f)",
				bearing(left),
				bearing(right),
				bearing(straight)
			)
		)
		t.truthy(bearing(right) > 10 and bearing(right) < 30, "turned toward the aim, less than the velocity's 30")
		t.near(bearing(left), -bearing(right), 0.2, "the same either way")
	end)

	t.test("out at most 9 % of the jump, best near the apex; in 15 % or more, further from a higher jump", function()
		-- a leap with the keys (sprint + W, W, none), the press at frame `at` (nil: none), the aim held full out or in
		local function flight(at: number?, reach: number, o: { [string]: any }): number
			local s = fresh()
			for _ = 1, 30 do
				step(s, o)
			end
			local x0, z0 = s.x, s.z
			local f = 0
			repeat
				f += 1
				local k = table.clone(o)
				k.leap = f == 1
				k.trick = at ~= nil and f == at
				if at and f > at then
					k.aimReach = reach
				end
				step(s, k)
			until (s.grounded and f > 2) or f > 600
			return math.sqrt((s.x - x0) ^ 2 + (s.z - z0) ^ 2)
		end
		local most, bestAt = 0, 0
		for _, o in { { fw = 1, sprint = true }, { fw = 1 }, {} } do
			local d0 = flight(nil, 0, o)
			local line = string.format(
				"      keys %-14s plain %.1f st:",
				if o.sprint then "W + Shift" elseif o.fw then "W" else "none",
				d0
			)
			for _, at in { 3, 9, 15, 21, 26, 32, 38, 44 } do
				local dO, dI = flight(at, 1, o), flight(at, -1, o)
				local out = dO / d0 - 1
				if out > most then
					most, bestAt = out, at
				end
				t.truthy(out <= P.trickOut + 1e-6, `out {out} at frame {at}`)
				if at <= 38 then
					t.truthy(dI < d0, "in comes in")
				end
				line ..= string.format("  f%d %+.1f%%/%+.1f%%", at, out * 100, (dI / d0 - 1) * 100)
				if at <= 26 then
					t.truthy(dI / d0 - 1 <= -0.11, `in from before the apex: {dI / d0 - 1}`)
				end
			end
			print(line)
		end
		print(string.format("      the most out: %+.1f %% (pressed %d frames in)", most * 100, bestAt))
		t.truthy(most > 0.05, "out is worth pressing")
		t.truthy(bestAt >= 9 and bestAt <= 32, "best near the apex, not at the takeoff or the landing")
		t.near(SquirrelMotor.trickReachAt(0, 0, 10), 0, 1e-12, "nothing at the takeoff")
		t.truthy(SquirrelMotor.trickReachAt(10, 1000, 1) <= P.trickOutPeak, "never past the peak")
		t.near(
			SquirrelMotor.trickReachAt(1, 1, 1),
			P.trickOut * 2,
			1e-12,
			"9 % of the whole carry: half of it left, twice that"
		)
		-- in from a higher fall comes in further: a body moving across at 30 st/s from rest high over the ground
		local function fall(height: number, reach: number): number
			local s = fresh()
			SquirrelMotor.place(s, s.x, s.y + height, s.z, false)
			s.vz = 30
			step(s, { trick = true })
			t.eq(s.trickKind, 2)
			local z0 = s.z
			while not s.grounded do
				step(s, { aimReach = reach })
			end
			return s.z - z0
		end
		local l0, l1, h0, h1 = fall(8, 0), fall(8, -1), fall(40, 0), fall(40, -1)
		print(
			string.format(
				"      in from a fall of 8 st: %.1f st nearer (%+.1f %%); of 40 st: %.1f st nearer (%+.1f %%)",
				l0 - l1,
				(l1 / l0 - 1) * 100,
				h0 - h1,
				(h1 / h0 - 1) * 100
			)
		)
		t.truthy(h0 - h1 > l0 - l1, "a higher jump comes in further (studs)")
		t.truthy(h1 / h0 - 1 <= -0.15 and l1 / l0 - 1 <= -0.15, "15 % or more")
	end)

	t.test(
		"the packet: the trick and the aim on the wire, bounded by fieldCheck, a snapshot without them reads none",
		function()
			local s = fresh()
			step(s, { fw = 1, leap = true })
			for _ = 1, 10 do
				step(s, { fw = 1 })
			end
			step(s, { fw = 1, trick = true })
			for _ = 1, 6 do
				step(s, { fw = 1, aimYaw = 0.3, aimReach = 0.5 })
			end
			local snap = SquirrelMotor.serialize(s)
			local _, _, back = SquirrelWire.decode(SquirrelWire.encode(1, 1, snap))
			t.eq(back.trickKind, 2)
			t.near(back.trickTime :: number, s.trickTime, 1e-6)
			t.near(back.aimYaw :: number, s.aimYaw, 1e-6)
			t.near(back.aimReach :: number, s.aimReach, 1e-6)
			t.eq(#SquirrelMotor.fieldCheck(back, world), 0, "an honest packet")
			for _, k in { "trickKind", "trickTime", "aimYaw", "aimReach" } do
				t.truthy(SquirrelMotor.FIELD_BOUNDS[k] ~= nil, k)
			end
			local function bad(edit: { [string]: any }): boolean
				local c = table.clone(back)
				for k, v in edit do
					c[k] = v
				end
				return #SquirrelMotor.fieldCheck(c, world) > 0
			end
			t.truthy(bad({ trickKind = 3 }), "no third move")
			t.truthy(bad({ trickKind = 1.5 }), "a whole move")
			t.truthy(bad({ trickKind = 1, trickTime = P.trickRoll + 0.01 }), "a roll no longer than a roll")
			t.truthy(bad({ trickTime = P.trickWiggle + 0.01 }), "a wiggle no longer than a wiggle")
			t.truthy(bad({ trickKind = 0, trickTime = 0.1, aimYaw = 0, aimReach = 0 }), "no time without a move")
			t.truthy(bad({ grounded = true, vy = 0, aimYaw = 0, aimReach = 0 }), "no wiggle on the ground")
			t.truthy(bad({ aimYaw = P.trickAimYaw + 0.01 }), "no more than 30 degrees")
			t.truthy(bad({ aimReach = 1.01 }), "no more than full out")
			t.truthy(bad({ trickKind = 0, trickTime = 0 }), "no re-aim with no move")
			t.truthy(bad({ grounded = true, vy = 0, trickKind = 1, trickTime = 0.2 }), "no re-aim on the ground")
			t.falsy(
				bad({ grounded = true, vy = 0, trickKind = 1, trickTime = 0.2, aimYaw = 0, aimReach = 0 }),
				"a roll on the ground"
			)
			t.truthy(bad({ routeId = 220, railT = 0, trickKind = 1, trickTime = 0.2, aimYaw = 0, aimReach = 0 }))
			local old = table.clone(snap)
			old.trickKind, old.trickTime, old.aimYaw, old.aimReach = nil, nil, nil, nil
			local st = SquirrelMotor.deserialize(old)
			t.eq(st.trickKind, 0)
			t.eq(st.aimYaw, 0)
			t.eq(#SquirrelMotor.fieldCheck(old, world), 0, "a snapshot from before the trick")
		end
	)

	-- (the rotation CFrame.Angles(rx, ry, rz) makes, as rows: Rx Ry Rz)
	local function rot(r: { number }?): { number }
		local a, b, c = if r then r[1] or 0 else 0, if r then r[2] or 0 else 0, if r then r[3] or 0 else 0
		local ca, sa, cb, sb, cc, sc = math.cos(a), math.sin(a), math.cos(b), math.sin(b), math.cos(c), math.sin(c)
		return {
			cb * cc,
			-cb * sc,
			sb,
			ca * sc + sa * sb * cc,
			ca * cc - sa * sb * sc,
			-sa * cb,
			sa * sc - ca * sb * cc,
			sa * cc + ca * sb * sc,
			ca * cb,
		}
	end
	-- (the angle between two rotations)
	local function apart(m: { number }, n: { number }): number
		local tr = 0
		for i = 0, 2 do
			for j = 0, 2 do
				tr += m[i * 3 + j + 1] * n[i * 3 + j + 1]
			end
		end
		return math.acos(math.clamp((tr - 1) / 2, -1, 1))
	end
	local IDENTITY = rot(nil)

	t.test("the pose: the roll a whole turn; every twitch zero at both ends, upright at the end, bounded", function()
		local d = AirTrick.duration(AirTrick.ROLL)
		t.eq(next(AirTrick.pose(AirTrick.ROLL, 0)), nil, "nothing at the start")
		t.eq(next(AirTrick.pose(AirTrick.ROLL, d)), nil, "nothing at the end")
		t.near(AirTrick.pose(AirTrick.ROLL, P.trickRoll / 2).Root[3], math.pi, 1e-6, "half a turn at the middle")
		t.near(AirTrick.pose(AirTrick.ROLL, P.trickRoll * 0.999).Root[3], 2 * math.pi, 1e-3, "a whole turn")
		local L = AirTrick.LIMIT
		local worstEnd, cases = 0, 0
		for seed = 0, 1023, 7 do
			for _, aim in
				{ { 0, 0 }, { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 0.7, 0.7 }, { -0.6, -0.8 }, { 0.2, -0.1 } }
			do
				local yaw = aim[1] * P.trickAimYaw
				t.eq(next(AirTrick.pose(AirTrick.WIGGLE, 0, yaw, aim[2], seed)), nil)
				t.eq(next(AirTrick.pose(AirTrick.WIGGLE, P.trickWiggle, yaw, aim[2], seed)), nil)
				for i = 1, 99, 7 do
					for bone, r in AirTrick.pose(AirTrick.WIGGLE, P.trickWiggle * i / 100, yaw, aim[2], seed) do
						local lim = if bone == "Root" then L.roll else L.swing
						for k = 1, 3 do
							t.truthy(math.abs(r[k] or 0) <= lim + 1e-9, `{bone}[{k}] {r[k]}`)
						end
						t.truthy(math.abs(r[4] or 0) <= L.shift + 1e-9 and (r[5] or 0) == 0 and (r[6] or 0) == 0)
					end
				end
				-- upright and facing its heading at the end: the Root's turn back to none, the rest nearly none
				local last = AirTrick.pose(AirTrick.WIGGLE, P.trickWiggle * 0.999, yaw, aim[2], seed)
				worstEnd = math.max(worstEnd, apart(rot(last.Root), IDENTITY))
				for bone, r in last do
					if bone ~= "Root" then
						t.truthy(math.abs(r[1]) + math.abs(r[2]) + math.abs(r[3]) < 0.05, `{bone} settles`)
					end
				end
				cases += 1
			end
		end
		print(
			string.format(
				"      %d twitches: the furthest from upright at 99.9 %% of the move %.4f rad",
				cases,
				worstEnd
			)
		)
		t.truthy(worstEnd < 0.02, "every twitch ends upright, facing its heading")
		local plain = AnimationDriver.heroLayers("squirrel", 1000, 3)
		local withTrick = AnimationDriver.heroLayers("squirrel", 1000, 3, nil, AirTrick.pose(AirTrick.ROLL, 0.2))
		t.eq(next(plain), nil)
		t.truthy(withTrick.Root ~= nil and withTrick.Root[3] > 0, "the roll on the hero's Root")
	end)

	t.test("the twitch: nine moves, drawn partly at random by the aim; the wiggle the most common", function()
		-- how often each move is drawn over every seed, for an aim
		local function counts(side: number, reach: number): { [string]: number }
			local c: { [string]: number } = {}
			for _, m in AirTrick.MOVES do
				c[m] = 0
			end
			for seed = 0, 1023 do
				local m = AirTrick.drawn(side, reach, seed)
				c[m] += 1
			end
			return c
		end
		local situations = {
			neutral = { 0, 0 },
			small = { 0.15, -0.1 },
			right = { 1, 0 },
			left = { -1, 0 },
			out = { 0, 1 },
			["in"] = { 0, -1 },
			outSide = { 0.8, 0.8 },
			inSide = { -0.8, -0.8 },
		}
		local at: { [string]: { [string]: number } } = {}
		for name, a in situations do
			at[name] = counts(a[1], a[2])
		end
		for _, name in { "neutral", "small", "right", "out", "in", "outSide", "inSide" } do
			local c = at[name]
			local line = string.format("      %-8s", name)
			for _, m in AirTrick.MOVES do
				line ..= string.format(" %s %d", m, c[m])
			end
			print(line)
		end
		-- ordinary play: small re-aims mostly (60 %), the rest anywhere: the wiggle is drawn most
		local rng = 12345
		local function rand(): number
			rng = (rng * 1103515245 + 12345) % 2147483648
			return rng / 2147483648
		end
		local overall: { [string]: number } = {}
		for _, m in AirTrick.MOVES do
			overall[m] = 0
		end
		for n = 1, 4000 do
			local side, reach
			if rand() < 0.6 then
				side, reach = (rand() * 2 - 1) * 0.3, (rand() * 2 - 1) * 0.3
			else
				side, reach = rand() * 2 - 1, rand() * 2 - 1
			end
			local m = AirTrick.drawn(side, reach, n % 1024)
			overall[m] += 1
		end
		for _, m in AirTrick.MOVES do
			if m ~= "wiggle" then
				t.truthy(overall.wiggle > overall[m], `the wiggle ({overall.wiggle}) over {m} ({overall[m]})`)
			end
		end
		t.truthy(at.neutral.wiggle > 512, "a near-neutral aim: mostly the wiggle")
		-- each move turns up for its situation more often than at a neutral aim
		local own =
			{ spin = "right", flip = "out", tuck = "in", corkscrew = "outSide", cartwheel = "inSide", whip = "right" }
		for m, where in own do
			t.truthy(at[where][m] > at.neutral[m] * 2, `{m}: {at[where][m]} at {where}, {at.neutral[m]} at neutral`)
		end
		t.truthy(at.small.pretzel > at.out.pretzel, "the pretzel: a small aim's oddity")
		t.truthy(at.out.starfish > at.neutral.starfish, "the starfish: a hard push's")
		-- every move is reachable, and the same aim draws different moves on different jumps
		for _, m in AirTrick.MOVES do
			local seen = 0
			for _, c in at do
				seen += c[m]
			end
			t.truthy(seen > 0, `{m} is drawn somewhere`)
		end
		local kinds = 0
		for _, n in at.right do
			kinds += if n > 0 then 1 else 0
		end
		t.truthy(kinds >= 4, `a hard push right draws {kinds} different moves over the seeds`)
	end)

	t.test("the twitch: each move distinct; the same inputs the same pose; a moving aim blends, never pops", function()
		-- a seed and an aim that draw each move (its share over 0.9), and its pose at the middle
		local probes = {
			{ 0, 0 },
			{ 1, 0 },
			{ -1, 0 },
			{ 0, 1 },
			{ 0, -1 },
			{ 0.8, 0.8 },
			{ -0.8, 0.8 },
			{ 0.8, -0.8 },
			{ -0.8, -0.8 },
			{ 0.1, 0 },
		}
		local found: { [string]: { [string]: { number } } } = {}
		for _, a in probes do
			for seed = 0, 1023 do
				local m = AirTrick.drawn(a[1], a[2], seed)
				if found[m] == nil and AirTrick.blend(a[1], a[2], seed)[m] > 0.9 then
					found[m] = AirTrick.twitch(0.5, a[1], a[2], seed)
				end
			end
		end
		local names = {}
		for m in found do
			table.insert(names, m)
		end
		table.sort(names)
		print(`      moves found clearly drawn: {table.concat(names, ", ")}`)
		t.eq(#names, #AirTrick.MOVES, "every move drawn on its own somewhere")
		local function differ(x: { [string]: { number } }, y: { [string]: { number } }): number
			local most = 0
			for _, pose in { x, y } do
				for bone in pose do
					local u, v = x[bone] or {}, y[bone] or {}
					for k = 1, 4 do
						most = math.max(most, math.abs((u[k] or 0) - (v[k] or 0)))
					end
				end
			end
			return most
		end
		for i = 1, #names do
			for j = i + 1, #names do
				t.truthy(differ(found[names[i]], found[names[j]]) > 0.08, `{names[i]} and {names[j]} differ`)
			end
		end
		-- the same inputs, the same pose (every client draws alike)
		t.eq(differ(AirTrick.twitch(0.37, 0.4, -0.2, 77), AirTrick.twitch(0.37, 0.4, -0.2, 77)), 0)
		t.eq(AirTrick.seedOf(AirTrick.pressOf(12.5 + 0.2, P.trickWiggle - 0.2)), AirTrick.seedOf(12.5))
		local ax, ay = AirTrick.aimAttr(P.trickAimYaw * 0.333, -0.71)
		t.near(ax, 0.35, 1e-12)
		t.near(ay, -0.7, 1e-12)
		local kyaw, kreach, kseed = AnimationDriver.trickAim(
			{ moveSpeed = 0, cadence = 0, climb = 0, trickAimYaw = 0.2, trickAimReach = -0.5, trickSeed = 9 },
			nil,
			nil
		)
		t.truthy(kyaw == 0.2 and kreach == -0.5 and kseed == 9, "the held body reads its own motor's aim")
		-- the aim swung across during the twitch (left, through out, to right): every frame close to the last
		local worstTurn, worstBend = 0, 0
		for seed = 0, 1023, 3 do
			local prev: { [string]: { number } }? = nil
			for f = 1, 29 do
				local p = f / 30
				local ang = math.pi * p
				local pose = AirTrick.twitch(p, -math.cos(ang), math.sin(ang), seed)
				if prev then
					worstTurn = math.max(worstTurn, apart(rot(pose.Root), rot(prev.Root)))
					for bone, r in pose do
						if bone ~= "Root" then
							local q = prev[bone] or { 0, 0, 0 }
							for k = 1, 3 do
								worstBend = math.max(worstBend, math.abs(r[k] - (q[k] or 0)))
							end
						end
					end
				end
				prev = pose
			end
		end
		print(
			string.format(
				"      the aim swung left -> out -> right over the twitch, 342 seeds: at most %.2f rad of turn and %.2f of bend a frame (30 fps)",
				worstTurn,
				worstBend
			)
		)
		t.truthy(worstTurn < 1.6, "the body's turn never pops")
		t.truthy(worstBend < 0.5, "no bone pops")
	end)
	t.test("others see it: the server's attributes, written once a move, read back while it plays", function()
		local now = 100
		local kind, at = AirTrick.mark(nil, nil, 1, P.trickRoll - 0.1, now)
		t.eq(kind, 1)
		t.near(at :: number, now - 0.1, 1e-9)
		t.eq(AirTrick.mark(kind, at, 1, P.trickRoll - 0.15, now + 0.05), nil, "the same move: nothing to write")
		local k2, at2 = AirTrick.mark(kind, at, 2, P.trickWiggle, now + 0.5)
		t.eq(k2, 2, "the wiggle")
		t.near(at2 :: number, now + 0.5, 1e-9)
		t.eq(AirTrick.mark(nil, nil, 0, 0, now), nil, "no move")
		t.eq(AirTrick.mark(nil, nil, 1, 0, now), nil, "a move that is over")
		t.eq(AirTrick.mark(1, at, 1, P.trickRoll, now + 2), 1, "a roll at a later landing")
		local pk, pe = AirTrick.playing(1, now, now + 0.2)
		t.eq(pk, 1)
		t.near(pe :: number, 0.2, 1e-9)
		t.eq(AirTrick.playing(1, now, now + P.trickRoll + 0.01), nil, "over")
		t.eq(AirTrick.playing(nil, nil, now), nil)
		local ok, oe =
			AnimationDriver.trickOf({ moveSpeed = 0, cadence = 0, climb = 0, trick = 2, trickLeft = 0.1 }, 1, now, now)
		t.eq(ok, 2, "the held body reads its own motor, not the attributes")
		t.near(oe :: number, P.trickWiggle - 0.1, 1e-9)
	end)

	t.test("the controls: G / R1 free, the aim from the camera's turn or a drag, the marker small and faint", function()
		t.eq(InputMap.BINDINGS.trick[1], "G")
		t.eq(InputMap.BINDINGS.trick[2], "ButtonR1")
		for verb, names in InputMap.BINDINGS :: any do
			if verb ~= "trick" then
				for _, n in names do
					t.truthy(n ~= "G" and n ~= "ButtonR1", `{verb} has {n}`)
				end
			end
		end
		for _, role in { "squirrel", "rodent" } do
			t.truthy(string.find(InputMap.HINTS(role), "G mid-jump", 1, true) ~= nil, role)
			local help = table.concat(PlayMenu.helpLines(role), "\n")
			t.truthy(string.find(help, "barrel roll", 1, true) ~= nil, role)
			t.truthy(string.find(help, "aim the rest of the jump", 1, true) ~= nil, role)
		end
		-- the camera's turn since the press: the yaw wrapped, the look up out and down in, full at AIM_PITCH
		local y, r = Squirrel.aimOf(3.0, 0.1, -3.0, 0.1 + Squirrel.AIM_PITCH)
		t.near(y, 2 * math.pi - 6, 1e-9, "wrapped the short way")
		t.eq(r, 1)
		local _, r2 = Squirrel.aimOf(0, 0, 0, -2 * Squirrel.AIM_PITCH)
		t.eq(r2, -1, "held to full in")
		-- a drag from the touch button: right turns right, up the screen is out
		local dy, dr = AirTrickButton.aimOf(AirTrickButton.AIM_PX / 2, -AirTrickButton.AIM_PX, P.trickAimYaw)
		t.near(dy, P.trickAimYaw / 2, 1e-12)
		t.eq(dr, 1)
		-- the button shows in the air while a press can do something
		local s = fresh()
		t.falsy(AirTrickButton.shows(s :: any), "on the ground: hidden")
		step(s, { fw = 1, leap = true })
		t.truthy(AirTrickButton.shows(s :: any), "in the air: shown")
		for _ = 1, 10 do
			step(s, { fw = 1 })
		end
		step(s, { fw = 1, trick = true })
		t.truthy(AirTrickButton.shows(s :: any), "after the wiggle: still shown (the roll as it lands, the drag)")
		-- the marker: small, faint, light sky blue (no green), fading over FADE seconds
		t.truthy(AimMarker.SIZE <= 1.5 and AimMarker.SHOWN >= 0.6, "small and faint")
		local c = AimMarker.COLOR
		t.truthy(c[3] > c[2] and c[2] > c[1], "sky blue: blue over green over red")
		local tr = 1
		for _ = 1, math.ceil(AimMarker.FADE * 60) do
			tr = AimMarker.fade(tr, true, 1 / 60)
		end
		t.near(tr, AimMarker.SHOWN, 1e-9, "faded in within FADE")
		t.eq(AimMarker.fade(AimMarker.SHOWN, false, 1), 1, "and out")
	end)

	t.test(
		"the grab-leap cooldown: a macro's chain no faster than a person's; a person's and a climb unchanged",
		function()
			local function chain(
				id: number,
				t0: number,
				yaw: number,
				every: number,
				t1: number,
				t2: number,
				up: boolean
			): number
				local r = world.registry:get(id)
				local p = world.registry:pointAt(r, t0)
				local s = SquirrelMotor.new(p.x, p.y, p.z)
				s.routeId, s.railT, s.grounded, s.clock, s.yaw = id, t0, false, 0, yaw
				local x0, y0, z0 = s.x, s.y, s.z
				local fx, fz = -math.sin(yaw), -math.cos(yaw)
				local function gone(): number
					return if up then s.y - y0 else (s.x - x0) * fx + (s.z - z0) * fz
				end
				local g1 = 0
				for f = 1, math.floor(t2 * 60 + 0.5) do
					local i = SquirrelMotor.idleInput(yaw)
					i.fw, i.sprint = 1, true
					i.leap = s.routeId ~= nil or (not s.grounded and f % every == 0)
					i.grab = not s.grounded and s.routeId == nil and f % every == 0
					SquirrelMotor.step(s, i, 1 / 60, world)
					if f == math.floor(t1 * 60 + 0.5) then
						g1 = gone()
					end
				end
				return (gone() - g1) / (t2 - t1)
			end
			local function heading(id: number, t0: number): number
				local a, b =
					world.registry:pointAt(world.registry:get(id), t0),
					world.registry:pointAt(world.registry:get(id), t0 + 0.1)
				return math.atan2(-(b.x - a.x), -(b.z - a.z))
			end
			local trunk = world.registry:get(604)
			local up0 = if world.registry:pointAt(trunk, 0).y < world.registry:pointAt(trunk, 1).y then 0.02 else 0.98
			local cd = P.grabLeapCooldown
			local function paces(): { number }
				local out = {}
				for _, every in { 2, 3, 6 } do
					table.insert(out, chain(1075, 0.02, heading(1075, 0.02), every, 1, 9, false))
					table.insert(out, chain(660, 0.02, heading(660, 0.02), every, 1, 9, false))
					table.insert(out, chain(604, up0, 0, every, 0, 2.5, true))
				end
				return out
			end
			P.grabLeapCooldown = 0
			local before = paces()
			P.grabLeapCooldown = cd
			local now = paces()
			local names = { "parapet", "cable", "trunk up" }
			for i = 1, 3 do
				print(
					string.format(
						"      %-9s E+Space every 2 / 3 / 6 frames: %.1f / %.1f / %.1f st/s (no cooldown %.1f / %.1f / %.1f)",
						names[i],
						now[i],
						now[3 + i],
						now[6 + i],
						before[i],
						before[3 + i],
						before[6 + i]
					)
				)
				t.near(now[6 + i], before[6 + i], 0.05, `{names[i]}: a person's chain unchanged`)
				t.truthy(
					now[i] <= now[6 + i] * 1.05 and now[3 + i] <= now[6 + i] * 1.05,
					`{names[i]}: a macro about a person's pace (within 5 %)`
				)
			end
			t.truthy(before[1] > before[7] + 3, "(without it the macro was faster)")
		end
	)
end
