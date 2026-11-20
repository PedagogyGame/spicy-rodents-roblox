--!strict
-- The air trick (owner D17): the motor's rule (Shared/Movement/SquirrelMotor: doTrick, trickSteer), its packet fields
-- (Shared/Movement/SquirrelWire, SquirrelMotor.fieldCheck), the pose and the attributes others see
-- (Shared/Movement/AirTrick), the touch button's rule (Client/UI/AirTrickButton) and the controls (Client/Input/InputMap).
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local SquirrelWire = require("@shared/Movement/SquirrelWire")
local AirTrick = require("@shared/Movement/AirTrick")
local AirTrickButton = require("@client/UI/AirTrickButton")
local InputMap = require("@client/Input/InputMap")
local PlayMenu = require("@client/UI/PlayMenu")
local AnimationDriver = require("@client/Animation/AnimationDriver")
local Units = require("@shared/Config/Units")
local TestWorld = require("@tests/cheat/TestWorld")

type State = SquirrelMotor.State

local P = SquirrelMotor.params

local function speed(s: State): number
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

	t.test("one button, only in the air: a roll, then a wiggle, then nothing until the next flight", function()
		local s = fresh()
		t.falsy(has(step(s, { trick = true }), "trick"), "on the ground: nothing")
		t.eq(s.trickKind, 0)
		step(s, { fw = 1, leap = true })
		t.falsy(s.grounded)
		local e = step(s, { fw = 1, trick = true })
		t.truthy(has(e, "trick", "roll"), "the first press in a flight: the barrel roll")
		t.eq(s.trickKind, 1)
		t.near(s.trickTime, P.trickRoll - 1 / 60, 1e-9)
		t.falsy(has(step(s, { fw = 1, trick = true }), "trick"), "a press while the roll plays does nothing")
		for _ = 1, math.ceil(P.trickRoll * 60) do
			step(s, { fw = 1 })
		end
		t.eq(s.trickTime, 0, "the roll is over")
		t.falsy(s.grounded, "still in the air")
		t.truthy(has(step(s, { fw = 1, trick = true }), "trick", "wiggle"), "the second press: the wiggle")
		t.eq(s.trickKind, 2)
		for _ = 1, math.ceil(P.trickWiggle * 60) do
			step(s, { fw = 1 })
		end
		t.falsy(has(step(s, { fw = 1, trick = true }), "trick"), "a third press does nothing")
		for _ = 1, 120 do
			step(s, { fw = 1 })
		end
		t.truthy(s.grounded, "landed")
		t.eq(s.trickKind, 0, "landing ends the flight's moves")
		t.eq(s.trickTime, 0)
		-- the next flight starts again with a roll; winded makes no difference
		s.stamina, s.winded = 0, true
		step(s, { fw = 1, leap = true })
		t.truthy(has(step(s, { fw = 1, trick = true }), "trick", "roll"), "winded: the roll still plays")
	end)

	t.test("not on a rail, not in a pounce's window; the same frame as the leap is in the air", function()
		local trunk = world.registry:get(220) :: any
		local foot = world.registry:foot(trunk)
		local s = SquirrelMotor.new(foot.x, world.groundHeight, foot.z - Units.st(1.2))
		step(s, { grab = true })
		t.eq(s.routeId, 220)
		t.falsy(has(step(s, { trick = true }), "trick"), "on a rail: nothing")
		local p = fresh()
		t.truthy(has(step(p, { fw = 1, leap = true, trick = true }), "trick", "roll"), "leap and trick together")
		local q = fresh()
		step(q, { fw = 1, pounce = true })
		t.truthy(q.attackWindow > 0)
		t.falsy(has(step(q, { fw = 1, trick = true }), "trick"), "in a pounce's window: nothing")
		-- a pounce in the air ends a move's steering
		local r = fresh()
		step(r, { fw = 1, leap = true, trick = true })
		for _ = 1, 30 do
			step(r, { fw = 1 })
		end
		step(r, { fw = 1, pounce = true })
		t.eq(r.trickTime, 0, "the pounce ends the move")
	end)

	t.test(
		"the steering: the heading swings toward the keys, the speed and the height exactly as without it",
		function()
			-- trickSteer itself: the speed kept to rounding, the turn at most trickTurn x dt
			for _, c in { { 40, 0, 0, 1 }, { 0, 30, 1, 0 }, { -20, 5, 0, -1 }, { 10, 10, -1, -1 } } do
				local vx, vz = SquirrelMotor.trickSteer(c[1], c[2], c[3], c[4], 1 / 60)
				t.near(math.sqrt(vx * vx + vz * vz), math.sqrt(c[1] ^ 2 + c[2] ^ 2), 1e-9, "speed kept")
				local turn = math.acos(math.clamp((vx * c[1] + vz * c[2]) / (c[1] ^ 2 + c[2] ^ 2), -1, 1))
				t.truthy(turn <= P.trickTurn / 60 + 1e-9, `turned {turn} rad in a frame`)
			end
			-- a leap north, then the keys held to the right (D) for the rest of the flight, with and without the trick
			local function flight(trick: boolean): (State, number, number)
				local s = fresh()
				step(s, { fw = 1, leap = true })
				local fastest, highest = 0, s.y
				local plain = SquirrelMotor.clone(s)
				local f = 0
				while not s.grounded and f < 200 do
					f += 1
					local o = { side = 1, trick = trick and (f == 1 or f == 30) }
					step(s, o)
					step(plain, { side = 1 })
					-- (no frame faster than the same frame without the trick's swing from the same state, no higher)
					fastest = math.max(fastest, speed(s) - math.max(speed(plain), speed(s)))
					highest = math.max(highest, s.y)
					plain = SquirrelMotor.clone(s)
					plain.trickTime = 0
				end
				return s, fastest, highest
			end
			local with, gain, top = flight(true)
			local without, _, top0 = flight(false)
			local x0 = fresh().x
			print(
				string.format(
					"      a leap north, D held: lands %.2f st right with the trick, %.2f without",
					x0 - with.x,
					x0 - without.x
				)
			)
			t.truthy(gain <= 1e-9, `no frame faster for the trick ({gain})`)
			t.near(top, top0, 1e-9, "no height")
			-- (camera yaw pi: forward is +z, D is -x)
			t.truthy((x0 - with.x) > (x0 - without.x) + 1, "the trick steers the landing further toward the keys")
			-- (the trick keeps the flight's speed through the turn, where the air's own steering sheds some turning, so it
			-- lands further from the take-off than the same keys without it; never further than the straight leap with W)
			local straight = fresh()
			step(straight, { fw = 1, leap = true })
			while not straight.grounded do
				step(straight, { fw = 1 })
			end
			local z0 = fresh().z
			local d1 = math.sqrt((with.x - x0) ^ 2 + (with.z - z0) ^ 2)
			local d2 = straight.z - z0
			print(string.format("      from the take-off: %.2f st with the trick, the straight leap %.2f", d1, d2))
			t.truthy(d1 <= d2 + 0.05, `no further from the take-off than the straight leap ({d1} st against {d2})`)
		end
	)

	t.test(
		"the packet: both fields on the wire, bounded by fieldCheck, a snapshot without them reads as none",
		function()
			local s = fresh()
			step(s, { fw = 1, leap = true, trick = true })
			local snap = SquirrelMotor.serialize(s)
			local _, _, back = SquirrelWire.decode(SquirrelWire.encode(1, 1, snap))
			t.eq(back.trickKind, 1)
			t.near(back.trickTime :: number, s.trickTime, 1e-6)
			t.eq(#SquirrelMotor.fieldCheck(back, world), 0, "an honest packet")
			t.truthy(SquirrelMotor.FIELD_BOUNDS.trickKind ~= nil and SquirrelMotor.FIELD_BOUNDS.trickTime ~= nil)
			local function bad(edit: { [string]: any }): boolean
				local c = table.clone(back)
				for k, v in edit do
					c[k] = v
				end
				return #SquirrelMotor.fieldCheck(c, world) > 0
			end
			t.truthy(bad({ trickKind = 3 }), "no third move")
			t.truthy(bad({ trickKind = 1.5 }), "a whole move")
			t.truthy(bad({ trickTime = P.trickRoll + 0.01 }), "a roll no longer than a roll")
			t.truthy(bad({ trickKind = 2, trickTime = P.trickWiggle + 0.01 }), "a wiggle no longer than a wiggle")
			t.truthy(bad({ trickKind = 0, trickTime = 0.1 }), "no time without a move")
			t.truthy(bad({ grounded = true, vy = 0 }), "no move on the ground")
			local old = table.clone(snap)
			old.trickKind, old.trickTime = nil, nil
			local st = SquirrelMotor.deserialize(old)
			t.eq(st.trickKind, 0)
			t.eq(st.trickTime, 0)
			t.eq(#SquirrelMotor.fieldCheck(old, world), 0, "a snapshot from before the trick")
		end
	)

	t.test("the pose: a whole roll and a side-to-side shimmy, zero at both ends, bounded", function()
		for _, kind in { AirTrick.ROLL, AirTrick.WIGGLE } do
			local d = AirTrick.duration(kind)
			t.eq(next(AirTrick.pose(kind, 0)), nil, "nothing at the start")
			t.eq(next(AirTrick.pose(kind, d)), nil, "nothing at the end")
			local L = AirTrick.LIMIT
			for i = 1, 99 do
				for bone, r in AirTrick.pose(kind, d * i / 100) do
					for k = 1, 3 do
						local lim = if bone == "Root" and k == 3 and kind == AirTrick.ROLL then L.roll else L.swing
						t.truthy(math.abs(r[k] or 0) <= lim + 1e-9, `{bone}[{k}] {r[k]} at {i} %`)
					end
					for k = 4, 6 do
						t.truthy(math.abs(r[k] or 0) <= L.shift + 1e-9, `{bone} shift {r[k]}`)
					end
					-- (the wiggle swings side to side only: no pitch of the hips, no shift up or forward)
					if kind == AirTrick.WIGGLE then
						t.eq(r[1] or 0, 0, `{bone}: no pitch in the wiggle`)
						t.eq(r[5] or 0, 0)
						t.eq(r[6] or 0, 0)
					end
				end
			end
			-- near the ends the offsets are small (the move eases in and out)
			for bone, r in AirTrick.pose(kind, d * 0.01) do
				t.truthy(math.abs(r[3] or 0) < 0.05 and math.abs(r[2] or 0) < 0.05, `{bone} eases in`)
			end
		end
		t.near(AirTrick.pose(AirTrick.ROLL, P.trickRoll / 2).Root[3], math.pi, 1e-6, "half a turn at the middle")
		t.near(AirTrick.pose(AirTrick.ROLL, P.trickRoll * 0.999).Root[3], 2 * math.pi, 1e-3, "a whole turn")
		-- heroLayers adds the move on top of the rest
		local plain = AnimationDriver.heroLayers("squirrel", 1000, 3)
		local withTrick = AnimationDriver.heroLayers("squirrel", 1000, 3, nil, AirTrick.pose(AirTrick.ROLL, 0.2))
		t.eq(next(plain), nil)
		t.truthy(withTrick.Root ~= nil and withTrick.Root[3] > 0, "the roll on the hero's Root")
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
		local k3 = AirTrick.mark(1, at, 1, P.trickRoll, now + 2)
		t.eq(k3, 1, "a roll in a later flight")
		local pk, pe = AirTrick.playing(1, now, now + 0.2)
		t.eq(pk, 1)
		t.near(pe :: number, 0.2, 1e-9)
		t.eq(AirTrick.playing(1, now, now + P.trickRoll + 0.01), nil, "over")
		t.eq(AirTrick.playing(nil, nil, now), nil)
		local ok, oe =
			AnimationDriver.trickOf({ moveSpeed = 0, cadence = 0, climb = 0, trick = 2, trickLeft = 0.1 }, 1, now, now)
		t.eq(ok, 2, "the held body reads its own motor, not the attributes")
		t.near(oe :: number, P.trickWiggle - 0.1, 1e-9)
		t.eq(
			AnimationDriver.trickOf({ moveSpeed = 0, cadence = 0, climb = 0, trick = 1, trickLeft = 0 }, 1, now, now),
			nil
		)
	end)

	t.test(
		"the controls: G and gamepad R1 free of every other on-foot verb; the touch button only with a move left",
		function()
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
				t.truthy(string.find(InputMap.HINTS(role), "G in the air", 1, true) ~= nil, role)
				t.truthy(string.find(table.concat(PlayMenu.helpLines(role), "\n"), "barrel roll", 1, true) ~= nil, role)
			end
			local s = fresh()
			t.falsy(AirTrickButton.shows(s :: any), "on the ground: hidden")
			step(s, { fw = 1, leap = true })
			t.truthy(AirTrickButton.shows(s :: any), "in the air: shown")
			step(s, { fw = 1, trick = true })
			t.falsy(AirTrickButton.shows(s :: any), "while the roll plays: hidden")
			for _ = 1, math.ceil(P.trickRoll * 60) do
				step(s, { fw = 1 })
			end
			t.truthy(AirTrickButton.shows(s :: any), "the wiggle is left")
			step(s, { fw = 1, trick = true })
			for _ = 1, math.ceil(P.trickWiggle * 60) do
				step(s, { fw = 1 })
			end
			t.falsy(AirTrickButton.shows(s :: any), "both done: hidden")
		end
	)
end
