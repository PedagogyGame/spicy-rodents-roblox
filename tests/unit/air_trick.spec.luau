--!strict
-- The air trick (owner D17, redone by D18; its burst, D20) and the grab-leap cooldown: the motor's rule
-- (Shared/Movement/SquirrelMotor: doTrick, reaim, trickReachAt, landingIn, the roll's carry, grabLeapCooldown; the
-- burst: burstFacing, burstOf, shiftDone, popAt, landingSpot), its packet fields (Shared/Movement/
-- SquirrelWire, SquirrelMotor.fieldCheck), the pose and the attributes others see (Shared/Movement/AirTrick), the aim's
-- controls (Client/Controllers/Squirrel.aimOf, Client/UI/AirTrickButton), the marker (Client/UI/AimMarker) and the help.
-- Prints the out / in table (flat ground, a leap pressed at each moment), the burst's distance table (a standing, a
-- running, a sprint and a winded leap) and the chain paces.
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

	-- THE BURST (owner D20) ----------------------------------------------------------------------------------------
	-- (a run-up of half a second and a leap with the keys `o`, `n` frames into the flight)
	local function leapt(o: { [string]: any }, n: number, winded: boolean?): State
		local s = fresh()
		if winded then
			s.stamina, s.winded = 0, true
		end
		for _ = 1, 30 do
			step(s, o)
		end
		local k = table.clone(o)
		k.leap = true
		step(s, k)
		for _ = 2, n do
			step(s, o)
		end
		return s
	end
	local function with(o: { [string]: any }, more: { [string]: any }): { [string]: any }
		local k = table.clone(o)
		for key, v in more do
			k[key] = v
		end
		return k
	end

	t.test(
		"the burst: the press pops the speed and shifts the body along its line at once; no lift; once a flight",
		function()
			t.truthy(P.trickShift >= 2.5 and P.trickShift <= 3.5, "the shift: 2.5 to 3.5 studs")
			t.truthy(P.trickPop >= 0.25 and P.trickPop <= 0.3, "the pop: a quarter to three tenths of the speed")
			t.truthy(P.trickPopTime >= 0.3 and P.trickPopTime <= 0.4, "easing back over 0.3 to 0.4 s")
			t.truthy(
				P.trickShiftTime >= 0.08 and P.trickShiftTime <= 0.15,
				"the shift within about a tenth of a second"
			)
			t.truthy(P.trickShiftTime <= P.trickLand, "the shift is over before a roll's window opens")
			t.truthy(P.trickPopTime <= P.trickWiggle, "the pop within the wiggle (the packet's trickTime dates both)")
			-- the shapes
			t.eq(SquirrelMotor.shiftDone(0), 0)
			t.eq(SquirrelMotor.shiftDone(P.trickShiftTime), 1)
			t.eq(SquirrelMotor.shiftDone(1), 1)
			t.truthy(SquirrelMotor.shiftDone(P.trickShiftTime / 3) > 0.5, "most of the shift in its first third")
			t.truthy(SquirrelMotor.shiftDone(1 / 60) < 0.3, "never one frame's jump (60 fps)")
			t.eq(SquirrelMotor.popAt(0), 1)
			t.eq(SquirrelMotor.popAt(P.trickPopTime), 0)
			t.near(SquirrelMotor.popCarry(0, 9), P.trickPopTime / 2, 1e-12)
			t.near(
				SquirrelMotor.popCarry(0, 0.1) + SquirrelMotor.popCarry(0.1, 9),
				P.trickPopTime / 2,
				1e-12,
				"the parts add up"
			)
			-- twins on a sprint leap, one pressed 16 frames in: frame by frame
			local hold = { fw = 1, sprint = true }
			local a, b = leapt(hold, 15), leapt(hold, 15)
			local v0 = across(b)
			step(a, with(hold, { trick = true }))
			step(b, hold)
			t.eq(a.trickKind, 2)
			t.near(a.trickTurn, 0, 1e-9, "pressed along its line: no turn")
			t.near(a.shiftX, 0, 1e-9)
			t.near(a.shiftZ, P.trickShift, 1e-9, "the shift fixed at the press, along the line")
			t.eq(a.trickPop, P.trickPop)
			t.near(
				across(a) / across(b),
				1 + P.trickPop * SquirrelMotor.popAt(1 / 60),
				1e-9,
				"the speed popped at once"
			)
			local lead = { a.z - b.z }
			t.truthy(lead[1] > 0.3, `felt in the press's own frame ({lead[1]} st)`)
			t.truthy(lead[1] < 0.45 * P.trickShift, "the first frame is a part of the shift, not all of it")
			local n = 1
			while not a.grounded do
				t.eq(a.vy, b.vy, "no lift: the vertical speed is the same flight's")
				t.eq(a.y, b.y, "and the height")
				step(a, hold)
				step(b, hold)
				n += 1
				lead[n] = a.z - b.z
				if not a.grounded then
					t.near(
						across(a) / across(b),
						1 + P.trickPop * SquirrelMotor.popAt(n / 60),
						1e-6,
						"the pop eases off"
					)
				end
			end
			t.truthy(b.grounded, "it lands on the same frame")
			local shiftFrames = math.ceil(P.trickShiftTime * 60 - 1e-6)
			local popFrames = math.ceil(P.trickPopTime * 60 - 1e-6)
			t.truthy(lead[3] > 0.5 * P.trickShift, "most of the shift in the first three frames")
			t.truthy(lead[shiftFrames] >= P.trickShift, "the whole shift within trickShiftTime")
			for i = 2, shiftFrames do
				t.truthy(lead[i] - lead[i - 1] <= lead[1] + 1e-9, "front-loaded: no frame more than the first")
			end
			for i = popFrames + 2, n - 1 do
				t.near(lead[i], lead[popFrames + 1], 1e-6, "after the burst: the same flight, that much further on")
			end
			local carry = SquirrelMotor.burstCarry(P.trickShift, P.trickPop, v0)
			t.truthy(
				lead[n - 1] > P.trickShift + 0.5 and lead[n - 1] <= carry + 0.05,
				`the burst carried {lead[n - 1]}`
			)
			print(
				string.format(
					"      a sprint leap pressed 16 frames in: +%.2f st after one frame, +%.2f after three, +%.2f at %.2f s, +%.2f at the landing (the shift %.1f, the pop %.0f %% for %.1f s)",
					lead[1],
					lead[3],
					lead[shiftFrames],
					shiftFrames / 60,
					lead[n - 1],
					P.trickShift,
					P.trickPop * 100,
					P.trickPopTime
				)
			)
			-- once a flight: pressed again and again, the same flight
			local c = leapt(hold, 15)
			step(c, with(hold, { trick = true }))
			while not c.grounded do
				local k = with(hold, { trick = c.vy > 0 })
				step(c, k)
			end
			t.near(c.z, a.z, 1e-9, "a second press adds nothing")
			t.eq(a.shiftX + a.shiftZ + a.trickPop + a.trickTurn, 0, "the landing ends the burst's state")
			-- winded: two thirds; a press whose own cost empties the meter is a full one
			local w = leapt({ fw = 1 }, 15, true)
			step(w, { fw = 1, trick = true })
			t.near(w.shiftZ, P.trickShift * P.trickWinded, 1e-9, "winded: two thirds of the shift")
			t.near(w.trickPop, P.trickPop * P.trickWinded, 1e-12, "and of the pop")
			t.near(P.trickWinded, 2 / 3, 1e-12)
			local low = leapt({ fw = 1 }, 15)
			low.stamina = 0.04
			step(low, { fw = 1, trick = true })
			t.truthy(low.winded and low.shiftZ == P.trickShift, "the press that empties the meter: still a full burst")
			-- a body with no speed across: the shift alone, exactly, along the camera's facing
			local d = fresh()
			SquirrelMotor.place(d, d.x, d.y + 30, d.z, false)
			local x0, z0 = d.x, d.z
			step(d, { trick = true, cameraYaw = math.pi + 0.5 })
			for i = 1, shiftFrames + 2 do
				local done = SquirrelMotor.shiftDone(i / 60) * P.trickShift
				t.near(d.x - x0, math.sin(0.5) * done, 1e-9, "the shift's path")
				t.near(d.z - z0, math.cos(0.5) * done, 1e-9)
				local sx, sz = SquirrelMotor.landingSpot(d, world)
				t.near(sx :: number, x0 + math.sin(0.5) * P.trickShift, 1e-9, "the marker's spot: where it comes down")
				t.near(sz :: number, z0 + math.cos(0.5) * P.trickShift, 1e-9)
				step(d, {})
			end
			t.eq(across(d), 0, "no speed made of nothing")
		end
	)

	t.test(
		"the burst: the flight turns onto the line the keys steer from the camera, 60 degrees at most; the heading follows",
		function()
			-- the line: the camera's facing with W or no key, the keys' own direction from it otherwise
			local cam = 0.7
			local fx, fz = SquirrelMotor.burstFacing(cam, 0, 0)
			t.near(fx, -math.sin(cam), 1e-12)
			t.near(fz, -math.cos(cam), 1e-12)
			local wx, wz = SquirrelMotor.burstFacing(cam, 1, 0)
			t.truthy(wx == fx and wz == fz, "W: the camera's facing")
			local bx, bz = SquirrelMotor.burstFacing(cam, -1, 0)
			t.near(bx, -fx, 1e-12, "S: toward the camera")
			t.near(bz, -fz, 1e-12)
			local rx, rz = SquirrelMotor.burstFacing(cam, 0, 1)
			t.near(rx * fx + rz * fz, 0, 1e-12, "a strafe key: square to it")
			local hold = { fw = 1, sprint = true }
			local function heading(s: State): number
				return math.atan2(s.vx, s.vz)
			end
			for _, deg in { 25, -25, 60, 120, -120 } do
				local turn = math.rad(deg)
				local s = leapt(hold, 15)
				t.near(heading(s), 0, 1e-9, "a leap north")
				local v0, vy0 = across(s), s.vy
				-- (the press alone, no step: SquirrelMotor.step with a zero frame runs the press and a substep of no length)
				SquirrelMotor.step(s, keys(with(hold, { trick = true, cameraYaw = math.pi + turn })), 0, world)
				t.near(s.trickTurn, turn, 1e-9, "the turn asked, kept whole")
				local snap = math.clamp(turn, -P.trickSnapYaw, P.trickSnapYaw)
				t.near(heading(s), snap, 1e-9, `{deg} degrees asked: the flight turned {math.deg(snap)} at the press`)
				t.near(across(s), v0 * (1 + P.trickPop), 1e-9, "the speed it had, popped: a turn takes none")
				t.eq(s.vy, vy0, "no lift")
				t.near(s.shiftX, math.sin(turn) * P.trickShift, 1e-9, "the shift along the line asked")
				t.near(s.shiftZ, math.cos(turn) * P.trickShift, 1e-9)
				-- the body's heading comes round to the line while the shift runs
				for _ = 1, math.ceil(P.trickShiftTime * 60) do
					step(s, with(hold, { cameraYaw = math.pi + turn }))
				end
				local off = s.yaw - turn
				t.truthy(math.abs(math.atan2(math.sin(off), math.cos(off))) < 0.05, "the heading on the new line")
			end
			t.near(P.trickSnapYaw, math.rad(60), 1e-12)
			-- with a strafe key held the line is the key's, not the camera's
			local s = leapt({ fw = 1 }, 15)
			step(s, { side = 1, trick = true })
			local kx, kz = SquirrelMotor.burstFacing(math.pi, 0, 1)
			t.near(s.shiftX, kx * P.trickShift, 1e-9)
			t.near(s.shiftZ, kz * P.trickShift, 1e-9)
			-- the landing lands turned: a sprint leap pressed 16 frames in with the camera 30 degrees round
			local function landed(turn: number?): State
				local f = leapt(hold, 15)
				local x0, z0 = f.x, f.z
				local camYaw = math.pi + (turn or 0)
				step(f, with(hold, { trick = turn ~= nil, cameraYaw = camYaw }))
				while not f.grounded do
					step(f, with(hold, { cameraYaw = camYaw }))
				end
				f.x, f.z = f.x - x0, f.z - z0
				return f
			end
			local plain, left, right = landed(nil), landed(math.rad(30)), landed(math.rad(-30))
			local bearing = math.deg(math.atan2(left.x, left.z))
			t.near(bearing, 30, 0.5, "the rest of the flight goes the new way")
			t.near(math.atan2(right.x, right.z), -math.atan2(left.x, left.z), 1e-6, "the same either way")
			local farther = math.sqrt(left.x ^ 2 + left.z ^ 2) - math.sqrt(plain.x ^ 2 + plain.z ^ 2)
			t.truthy(farther > P.trickShift, `and further ({farther} st over the same steering with no press)`)
		end
	)

	t.test("the burst: none in a chained leap's flight, and none sooner than trickBurstRest after the last", function()
		local hold = { fw = 1, sprint = true }
		-- inside the rest: the wiggle and its re-aim, no burst
		local s = leapt(hold, 15)
		s.burstWait = 0.2
		local v0 = across(s)
		step(s, with(hold, { trick = true, cameraYaw = math.pi + 0.6 }))
		t.eq(s.trickKind, 2, "the wiggle all the same")
		t.eq(s.shiftX + s.shiftZ + s.trickPop + s.trickTurn, 0, "no burst inside the rest")
		t.truthy(across(s) < v0 * 1.02, "no pop")
		t.near(s.burstWait, 0.2 - 1 / 60, 1e-9, "the rest runs down")
		-- a burst starts the rest, which runs down on the ground too
		local a = leapt(hold, 15)
		t.eq(a.burstWait, 0)
		step(a, with(hold, { trick = true }))
		t.near(a.burstWait, P.trickBurstRest - 1 / 60, 1e-9, "a burst starts the rest")
		while not a.grounded do
			step(a, hold)
		end
		t.eq(a.burstWait, 0, "over well before a leap's flight is (0.85 s): jump after jump, each has its burst")
		t.truthy(P.trickBurstRest < 0.85 - P.trickLand and P.trickBurstRest >= 0.4)
		step(a, with(hold, { leap = true }))
		step(a, with(hold, { trick = true }))
		t.near(a.trickPop, P.trickPop, 1e-12, "the next jump's press bursts again")
		-- a chained leap (owner D19): no burst
		local c = leapt(hold, 15)
		c.leapScale = P.chainCarry
		step(c, with(hold, { trick = true }))
		t.eq(c.trickKind, 2)
		t.eq(c.shiftX + c.shiftZ + c.trickPop, 0, "a chained leap's flight: the wiggle alone")
		-- along a rail: E, a frame on it, Space, G at once, E again `air` frames on: G buys the chain no pace
		local function chain(id: number, air: number, trick: boolean): number
			local r = world.registry:get(id)
			local p0, p1 = world.registry:pointAt(r, 0.02), world.registry:pointAt(r, 0.12)
			local yaw = math.atan2(-(p1.x - p0.x), -(p1.z - p0.z))
			local b = SquirrelMotor.new(p0.x, p0.y, p0.z)
			b.routeId, b.railT, b.grounded, b.clock, b.yaw = id, 0.02, false, 0, yaw
			local fx, fz = -math.sin(yaw), -math.cos(yaw)
			local on, up, at1 = 0, 0, 0
			for f = 1, 540 do
				local i = SquirrelMotor.idleInput(yaw)
				i.fw, i.sprint = 1, true
				if b.routeId ~= nil then
					on, up = on + 1, 0
					i.leap = on > 1
				elseif not b.grounded then
					on, up = 0, up + 1
					i.trick = trick and up == 1
					i.grab = up >= air
				end
				SquirrelMotor.step(b, i, 1 / 60, world)
				if f == 60 then
					at1 = (b.x - p0.x) * fx + (b.z - p0.z) * fz
				end
			end
			return ((b.x - p0.x) * fx + (b.z - p0.z) * fz - at1) / 8
		end
		for _, case in { { "parapet", 1075 }, { "cable", 660 } } do
			local line = string.format("      %-8s E, Space, (G,) E again 3 / 6 / 10 frames on:", case[1])
			for _, air in { 3, 6, 10 } do
				local plain, tricked = chain(case[2], air, false), chain(case[2], air, true)
				line ..= string.format("  %.1f -> %.1f st/s", plain, tricked)
				t.truthy(tricked <= plain + 0.5, `{case[1]} every {air}: G buys a chain nothing ({plain} -> {tricked})`)
			end
			print(line)
		end
	end)

	t.test("the burst: the marker shows the new landing spot from the press's frame", function()
		local hold = { fw = 1, sprint = true }
		local s = leapt(hold, 15)
		local _, before = SquirrelMotor.landingSpot(s, world)
		local v0 = across(s)
		step(s, with(hold, { trick = true }))
		local _, after = SquirrelMotor.landingSpot(s, world)
		local carry = SquirrelMotor.burstCarry(P.trickShift, P.trickPop, v0)
		-- (a frame of the flight's own steering between the two looks: a fifth of a stud)
		t.near((after :: number) - (before :: number), carry, 0.3, "the spot moved on by the burst at the press")
		local last, worst = after :: number, 0
		while not s.grounded do
			step(s, hold)
			if not s.grounded then
				local _, z = SquirrelMotor.landingSpot(s, world)
				if z then
					worst = math.max(worst, math.abs(z - last))
					last = z
				end
			end
		end
		t.truthy(worst < 0.35, `and never jumps after (most {worst} st a frame)`)
		t.near(last, s.z, 1, "it ends where the flight lands")
		-- with no burst left it is the flight's own landing
		local p = leapt(hold, 15)
		local lx, lz, lt = SquirrelMotor.landingSpot(p, world)
		local tt = landIn(p)
		t.near(lt :: number, tt, 1e-12)
		t.near(lx :: number, p.x + p.vx * tt, 1e-9)
		t.near(lz :: number, p.z + p.vz * tt, 1e-9)
	end)

	t.test(
		"the burst's distance: the same whatever the aim; with farther out about a fifth of a jump at most",
		function()
			-- a leap after a run-up with the keys, the press at frame `at` (nil: none), the aim held `reach` and `yaw`
			local function flight(
				o: { [string]: any },
				winded: boolean,
				at: number?,
				reach: number?,
				yaw: number?
			): (number, number, number)
				local s = leapt(o, 1, winded)
				-- (the leap's own frame was the first: from where it left the ground)
				local x0, z0 = s.x - s.vx / 60, s.z - s.vz / 60
				local f, path = 1, across(s) / 60
				repeat
					f += 1
					local k = table.clone(o)
					k.trick = at ~= nil and f == at
					if at and f > at then
						k.aimReach, k.aimYaw = reach, yaw
					end
					local px, pz = s.x, s.z
					step(s, k)
					path += math.sqrt((s.x - px) ^ 2 + (s.z - pz) ^ 2)
				until s.grounded or f > 600
				-- (the straight distance from the take-off, the frames, and the length of the path flown)
				return math.sqrt((s.x - x0) ^ 2 + (s.z - z0) ^ 2), f, path
			end
			local rows = {
				{ "standing leap (no key)", {}, false },
				{ "running leap (W)", { fw = 1 }, false },
				{ "sprint leap (W + Shift)", { fw = 1, sprint = true }, false },
				{ "winded leap (W)", { fw = 1 }, true },
			}
			local presses = { 3, 9, 15, 21, 26, 32, 38 }
			print(
				"      pressed (frames after take-off; 60 fps)         "
					.. "3            9            15           21           26           32           38"
			)
			for _, row in rows do
				local name, o, winded = row[1], row[2], row[3]
				local plain, frames = flight(o, winded, nil)
				local line = string.format("      %-24s %5.1f st |", name, plain)
				local most, mostAll, least = 0, 0, math.huge
				for _, at in presses do
					local b, _, bPath = flight(o, winded, at, 0)
					local all = flight(o, winded, at, 1)
					line ..= string.format(" +%.1f / +%.1f |", b - plain, all - plain)
					most, least = math.max(most, b / plain - 1), math.min(least, b / plain - 1)
					-- the burst is the same whatever the aim: full either side the path flown is as long (the turn keeps the
					-- speed; with a key held the air steers the turned flight back a little)
					local _, _, sidePath = flight(o, winded, at, 0, 1)
					t.near(
						sidePath,
						bPath,
						if next(o) == nil then 0.05 else 0.6,
						`{name} at {at}: as far aimed to a side`
					)
					t.truthy(all - b <= P.trickOut * plain + 1e-6, "out adds its 9 % at most")
				end
				for at = 2, frames - 10 do
					mostAll = math.max(mostAll, flight(o, winded, at, 1) / plain - 1)
				end
				print(line)
				print(
					string.format(
						"      %-24s the burst alone +%.1f to +%.1f %%; with farther out +%.1f %% at most (any press)",
						"",
						least * 100,
						most * 100,
						mostAll * 100
					)
				)
				local shift = SquirrelMotor.burstOf(winded)
				t.truthy(least * plain > shift, `{name}: the burst carries more than its shift`)
				t.truthy(most <= 0.19, `{name}: the burst alone {most}`)
				t.truthy(mostAll <= 0.22, `{name}: the whole trick {mostAll}`)
			end
			t.truthy(P.trickTotal <= 0.2)
		end
	)

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
				-- (against the same press with the aim left alone: the burst is the same whatever the aim, owner D20)
				local dB, dO, dI = flight(at, 0, o), flight(at, 1, o), flight(at, -1, o)
				local out, inn = (dO - dB) / d0, (dI - dB) / d0
				if out > most then
					most, bestAt = out, at
				end
				t.truthy(out <= P.trickOut + 1e-6, `out {out} at frame {at}`)
				if at <= 38 then
					t.truthy(dI < dB, "in comes in")
				end
				line ..= string.format("  f%d %+.1f%%/%+.1f%%", at, out * 100, inn * 100)
				if at <= 26 then
					t.truthy(inn <= -0.11, `in from before the apex: {inn}`)
				end
			end
			print(line)
		end
		print(
			string.format(
				"      the most out: %+.1f %% (pressed %d frames in); each over the same press with no aim",
				most * 100,
				bestAt
			)
		)
		t.truthy(most > 0.04, "out is worth pressing")
		t.truthy(bestAt >= 9 and bestAt <= 32, "best near the apex, not at the takeoff or the landing")
		t.near(SquirrelMotor.trickReachAt(0, 0, 10), 0, 1e-12, "nothing at the takeoff")
		t.truthy(SquirrelMotor.trickReachAt(10, 1000, 1) <= P.trickOutPeak, "never past the peak")
		t.near(
			SquirrelMotor.trickReachAt(1, 1, 1),
			P.trickOut * 2,
			1e-12,
			"9 % of the whole carry: half of it left, twice that"
		)
		t.near(
			SquirrelMotor.trickReachAt(1, 10, 10, 2),
			(P.trickTotal * 20 - 2) / 10,
			1e-12,
			"with a burst: what it leaves of trickTotal of the whole carry"
		)
		t.eq(SquirrelMotor.trickReachAt(1, 1, 1, 5), 0, "a burst over the whole allowance leaves none")
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
			t.near(back.trickTurn :: number, s.trickTurn, 1e-6)
			t.eq(#SquirrelMotor.fieldCheck(back, world), 0, "an honest packet")
			-- (owner D20: the burst's turn on the wire, a camera swung at the press)
			local q = fresh()
			step(q, { fw = 1, leap = true })
			for _ = 1, 10 do
				step(q, { fw = 1 })
			end
			step(q, { fw = 1, trick = true, cameraYaw = math.pi + 2 })
			local _, _, turned = SquirrelWire.decode(SquirrelWire.encode(1, 1, SquirrelMotor.serialize(q)))
			t.near(turned.trickTurn :: number, 2, 1e-5, "the turn asked, whole")
			t.near(turned.burstWait :: number, q.burstWait, 1e-6, "the burst's rest, which dates its press")
			t.truthy(SquirrelMotor.freshBurst(SquirrelMotor.new(0, 0, 0), q), "a burst pressed since")
			local q2 = SquirrelMotor.clone(q)
			step(q2, { fw = 1 })
			t.falsy(SquirrelMotor.freshBurst(q, q2), "the same burst a frame on: not a new one")
			t.eq(#SquirrelMotor.fieldCheck(turned, world), 0, "an honest packet with a turn")
			back.trickTurn = 0
			for _, k in { "trickKind", "trickTime", "aimYaw", "aimReach", "trickTurn", "burstWait" } do
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
			t.truthy(bad({ trickTurn = math.pi + 0.01 }), "a turn no more than half round")
			t.truthy(
				bad({ grounded = true, vy = 0, trickKind = 1, trickTime = 0.2, aimYaw = 0, aimReach = 0, trickTurn = 1 }),
				"no burst's turn with no wiggle"
			)
			t.falsy(bad({ trickTurn = -3 }), "a wiggle's turn")
			t.truthy(bad({ burstWait = P.trickBurstRest + 0.01 }), "a rest no longer than the motor's")
			t.truthy(bad({ burstWait = -0.01 }))
			t.truthy(bad({ trickKind = 0, trickTime = 0 }), "no re-aim with no move")
			t.truthy(bad({ grounded = true, vy = 0, trickKind = 1, trickTime = 0.2 }), "no re-aim on the ground")
			t.falsy(
				bad({ grounded = true, vy = 0, trickKind = 1, trickTime = 0.2, aimYaw = 0, aimReach = 0 }),
				"a roll on the ground"
			)
			t.truthy(bad({ routeId = 220, railT = 0, trickKind = 1, trickTime = 0.2, aimYaw = 0, aimReach = 0 }))
			local old = table.clone(snap)
			old.trickKind, old.trickTime, old.aimYaw, old.aimReach, old.trickTurn = nil, nil, nil, nil, nil
			old.shiftX, old.shiftZ, old.trickPop, old.burstWait = nil, nil, nil, nil
			local st = SquirrelMotor.deserialize(old)
			t.eq(st.trickKind, 0)
			t.eq(st.aimYaw, 0)
			t.eq(st.trickTurn, 0)
			t.eq(st.shiftX, 0)
			t.eq(st.trickPop, 0)
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
						t.truthy(math.abs(r[4] or 0) <= L.shift + 1e-9 and (r[5] or 0) == 0)
						t.truthy(math.abs(r[6] or 0) <= L.shift + 1e-9, "the lunge ahead bounded")
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

	t.test(
		"the throw: at the press the body snaps toward the new line, hips whipping after, stretched long; a spring",
		function()
			local T = AirTrick.THROW
			-- the spring: in within a tenth of a second, a little past, and settled
			t.eq(AirTrick.spasm(0), 0)
			local peakAt, peak, low = 0, 0, 0
			for i = 1, 500 do
				local v = AirTrick.spasm(i / 1000)
				if v > peak then
					peak, peakAt = v, i / 1000
				end
				low = math.min(low, v)
			end
			t.near(peak, 1, 1e-3, "at its most once")
			t.truthy(peakAt >= 0.02 and peakAt <= 0.06, `at its most {peakAt} s in: sudden`)
			t.truthy(T.snap >= 0.08 and T.snap <= 0.12, "in within about a tenth of a second")
			t.near(AirTrick.spasm(T.snap), 0, 1e-9, "back through none")
			t.truthy(low < -0.1 and low > -0.5, `a slight overshoot ({low})`)
			t.truthy(math.abs(AirTrick.spasm(T.release + 0.1)) < 0.05, "and it settles")
			-- the stretch: in fast, held while the pop lasts, gone after
			t.eq(AirTrick.stretch(0), 0)
			t.truthy(AirTrick.stretch(T.reach) > 0.9, "stretched within THROW.reach")
			t.truthy(AirTrick.stretch(T.hold) > 0.85, "held a beat")
			t.eq(AirTrick.stretch(T.release), 0)
			t.truthy(T.release >= P.trickPopTime, "held while the speed's pop lasts")
			-- which way: a quarter turn to the left
			local left = math.pi / 2
			local side, back = AirTrick.turnParts(left)
			t.eq(side, 1)
			t.eq(back, 0)
			t.eq(AirTrick.turnParts(0), 0)
			local s2, b2 = AirTrick.turnParts(-math.pi)
			t.near(s2, 0, 1e-12, "half round: no side")
			t.eq(b2, 1, "all back")
			t.eq(next(AirTrick.throw(0, left)), nil, "nothing at the press itself")
			-- the first 0.15 s: the head, neck and chest toward the turn; the hips and the tail against it at first; banked in
			local early = AirTrick.throw(0.03, left)
			t.truthy(
				early.Head[2] > 0.25 and early.Neck[2] > 0 and early.Spine2[2] > 0,
				"the head and chest lead, left"
			)
			t.truthy(early.Hips[2] < 0, "the hips are left behind")
			t.truthy(AirTrick.throw(0.06, left).Tail2[2] < 0, "the tail lashes the other way, a moment after")
			t.truthy(early.Root[3] > 0, "banked into the turn (rz + rolls the left side down)")
			t.truthy(math.abs(early.Head[2]) > math.abs(early.Hips[2]), "the head ahead of the hips")
			local past = AirTrick.throw(T.snap + T.lag + 0.03, left)
			t.truthy(past.Hips[2] > 0, "then the hips whip round past the line")
			t.truthy(past.Tail1[2] > 0)
			local held = AirTrick.throw(0.15, left)
			t.truthy(held.FrontL_Upper[1] > 0.3 and held.FrontR_Upper[1] > 0.3, "fore paws reaching ahead")
			t.truthy(held.BackL_Upper[1] < -0.3 and held.BackR_Upper[1] < -0.3, "hind legs trailing")
			t.truthy(held.Spine1[1] > 0 and held.Head[1] < 0, "the back long, the head low along the line")
			t.truthy(held.Root[6] < -0.05, "lunging ahead (-Z)")
			t.truthy(held.EarL[3] > 0 and held.EarR[3] < 0, "ears flat")
			-- mirrored to the right: the twist's every angle the other way, the stretch the same
			for _, at in { 0.02, 0.05, 0.09, 0.15, 0.25 } do
				local l, r = AirTrick.throw(at, left), AirTrick.throw(at, -left)
				for bone, a in l do
					local m = r[bone]
					t.near(m[1], a[1], 1e-12, `{bone}: the stretch the same`)
					t.near(m[2], -a[2], 1e-12, `{bone}: the twist mirrored`)
					t.near(m[3], if bone == "Root" then -a[3] else a[3], 1e-12)
				end
			end
			-- straight ahead: no twist at all, the stretch and the snap forward only
			for _, at in { 0.02, 0.05, 0.1, 0.2 } do
				local f = AirTrick.throw(at, 0)
				for bone, a in f do
					t.eq(a[2], 0, `{bone}: no twist straight ahead`)
				end
				t.eq(f.Root[3], 0)
				t.truthy(f.FrontL_Upper[1] > 0 and f.BackL_Upper[1] < 0, "the stretch forward")
			end
			-- the size follows the turn: an eighth turn half of a quarter turn's; back toward the camera none to a side
			t.near(AirTrick.throw(0.03, left / 2).Head[2], early.Head[2] / 2, 1e-12)
			t.near(AirTrick.throw(0.03, math.pi).Head[2], 0, 1e-12)
			-- inside the twitch: every pose with a turn still zero at both ends, bounded, upright at the end
			local L = AirTrick.LIMIT
			for seed = 0, 1023, 37 do
				for _, turn in { 0, 0.4, -1.2, math.pi / 2, -math.pi / 2, 2.5, math.pi } do
					t.eq(next(AirTrick.pose(AirTrick.WIGGLE, 0, 0, 0, seed, turn)), nil)
					t.eq(next(AirTrick.pose(AirTrick.WIGGLE, P.trickWiggle, 0, 0, seed, turn)), nil)
					for i = 1, 99, 3 do
						for bone, r in AirTrick.pose(AirTrick.WIGGLE, P.trickWiggle * i / 100, 0.2, -0.3, seed, turn) do
							local lim = if bone == "Root" then L.roll else L.swing
							for k = 1, 3 do
								t.truthy(math.abs(r[k] or 0) <= lim + 1e-9, `{bone}[{k}] {r[k]}`)
							end
						end
					end
					local last = AirTrick.pose(AirTrick.WIGGLE, P.trickWiggle * 0.999, 0, 0, seed, turn)
					t.truthy(apart(rot(last.Root), IDENTITY) < 0.02, "upright at the end")
					for bone, r in last do
						if bone ~= "Root" then
							t.truthy(math.abs(r[1]) + math.abs(r[2]) + math.abs(r[3]) < 0.05, `{bone} settles`)
						end
					end
				end
			end
			-- the pose's opening shows in the twitch: 0.03 s in, a left throw's head is to the left of a right throw's
			local pl = AirTrick.pose(AirTrick.WIGGLE, 0.03, 0, 0, 5, left)
			local pr = AirTrick.pose(AirTrick.WIGGLE, 0.03, 0, 0, 5, -left)
			t.truthy(pl.Head[2] > 0.2 and pr.Head[2] < -0.2, "the twitch opens with the throw")
			-- no pop: a 240 Hz walk through the twitch, the turn held (it is fixed at the press)
			local worst = 0
			for _, turn in { 0, left, -2.6 } do
				local prev: { [string]: { number } }? = nil
				for f = 1, 119 do
					local pose = AirTrick.pose(AirTrick.WIGGLE, f / 240, 0.1, 0.2, 11, turn)
					if prev then
						for bone, r in pose do
							if bone ~= "Root" then
								local q = prev[bone] or { 0, 0, 0 }
								for k = 1, 3 do
									worst = math.max(worst, math.abs(r[k] - (q[k] or 0)))
								end
							end
						end
					end
					prev = pose
				end
			end
			print(string.format("      the throw: at most %.2f rad of bend a quarter of a 60 fps frame", worst))
			t.truthy(worst < 0.2, "sudden, never a pop")
		end
	)

	t.test(
		"the throw picks the twitch: to a side the spin and the whip, back toward the camera the back tuck",
		function()
			local function counts(turn: number): { [string]: number }
				local c: { [string]: number } = {}
				for _, m in AirTrick.MOVES do
					c[m] = 0
				end
				for seed = 0, 1023 do
					local m = AirTrick.drawn(0, 0, seed, turn)
					c[m] += 1
				end
				return c
			end
			local rows = {
				{ "ahead", 0 },
				{ "a little left (20 deg)", math.rad(20) },
				{ "left (60 deg)", math.rad(60) },
				{ "hard left (90 deg)", math.rad(90) },
				{ "back (150 deg)", math.rad(150) },
				{ "right round (180 deg)", math.pi },
			}
			local at: { [string]: { [string]: number } } = {}
			for _, r in rows do
				local c = counts(r[2])
				at[r[1]] = c
				local parts = {}
				for _, m in AirTrick.MOVES do
					table.insert(parts, `{m} {c[m]}`)
				end
				print(string.format("      %-22s %s", r[1], table.concat(parts, " ")))
			end
			t.truthy(at["ahead"].wiggle > 850, "straight ahead: the wiggle as before")
			t.truthy(at["a little left (20 deg)"].wiggle > 700, "a small turn: still mostly the wiggle")
			t.truthy(at["hard left (90 deg)"].spin > at["hard left (90 deg)"].wiggle, "a quarter turn: mostly the spin")
			t.truthy(at["hard left (90 deg)"].whip > at["ahead"].whip, "and the tail whip more often")
			t.truthy(at["right round (180 deg)"].tuck > at["right round (180 deg)"].wiggle, "back: it folds and flips")
			t.eq(at["ahead"].tuck, 0)
			-- the side of the turning move is the throw's
			local w = AirTrick.weights(0, 0, 0)
			local base = AirTrick.weights(0, 0)
			for _, m in AirTrick.MOVES do
				t.eq(w[m], base[m], "no turn: the aim's weights as they were")
			end
			-- the attribute and what each client reads
			t.eq(AirTrick.ATTR.turn, "AirTrickTurn")
			t.eq(AirTrick.turnAttr(1.234), 1.25)
			t.eq(AirTrick.turnAttr(-9), -3.15, "held to half a turn")
			local kin = { moveSpeed = 0, cadence = 0, climb = 0, trickAimYaw = 0.1, trickAimReach = 0.2, trickSeed = 7 }
			local _, _, _, mine = AnimationDriver.trickAim(with(kin, { trickTurn = 0.9 }) :: any, nil, nil, 2)
			t.eq(mine, 0.9, "the held body's own motor")
			local _, _, _, theirs = AnimationDriver.trickAim(nil, nil, 3, 1.25)
			t.eq(theirs, 1.25, "another body's attribute")
			local _, _, _, none = AnimationDriver.trickAim(nil, nil, nil, nil)
			t.eq(none, nil, "no burst: no throw")
			local _, _, _, mineNone = AnimationDriver.trickAim(kin :: any, nil, nil, 2)
			t.eq(mineNone, nil)
			-- a wiggle with no burst is not posed as a throw; one with a burst is (the rest dates the same press)
			t.truthy(AirTrick.thrown(P.trickWiggle - 0.1, P.trickBurstRest - 0.1), "pressed together")
			t.truthy(AirTrick.thrown(P.trickWiggle - 0.1, P.trickBurstRest - 0.11), "to a frame")
			t.falsy(AirTrick.thrown(P.trickWiggle - 0.1, 0), "no burst")
			t.falsy(
				AirTrick.thrown(P.trickWiggle - 0.1, P.trickBurstRest - 0.4),
				"an earlier burst's rest still running"
			)
			t.eq(AirTrick.pose(AirTrick.WIGGLE, 0.1, 0, 0, 5).FrontL_Upper, nil, "no throw without a burst")
			t.truthy(AirTrick.pose(AirTrick.WIGGLE, 0.1, 0, 0, 5, 0).FrontL_Upper ~= nil, "straight ahead: the stretch")
			local held = leapt({ fw = 1, sprint = true }, 15)
			step(held, { fw = 1, sprint = true, trick = true })
			t.truthy(AirTrick.thrown(held.trickTime, held.burstWait), "the motor's burst reads as thrown")
			local chained = leapt({ fw = 1, sprint = true }, 15)
			chained.leapScale = P.chainCarry
			step(chained, { fw = 1, sprint = true, trick = true })
			t.falsy(AirTrick.thrown(chained.trickTime, chained.burstWait), "a chained leap's wiggle does not")
		end
	)

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
		local found: { [string]: { number } } = {}
		for _, a in probes do
			for seed = 0, 1023 do
				local m = AirTrick.drawn(a[1], a[2], seed)
				if found[m] == nil and AirTrick.blend(a[1], a[2], seed)[m] > 0.9 then
					found[m] = { a[1], a[2], seed }
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
				local u, v = found[names[i]], found[names[j]]
				local most = 0
				for _, p in { 0.25, 0.4, 0.55, 0.7 } do
					most = math.max(
						most,
						differ(AirTrick.twitch(p, u[1], u[2], u[3]), AirTrick.twitch(p, v[1], v[2], v[3]))
					)
				end
				t.truthy(most > 0.08, `{names[i]} and {names[j]} differ`)
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
			for f = 1, 239 do
				local p = f / 240
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
				"      the aim swung left -> out -> right across the twitch's half second, 342 seeds: at most %.2f rad of turn and %.2f of bend a quarter of a 60 fps frame",
				worstTurn,
				worstBend
			)
		)
		t.truthy(worstTurn < 0.5, "the body's turn never pops")
		t.truthy(worstBend < 0.2, "no bone pops")
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
			t.truthy(string.find(InputMap.HINTS(role), "G mid-jump: a burst the way you face", 1, true) ~= nil, role)
			local help = table.concat(PlayMenu.helpLines(role), "\n")
			t.truthy(string.find(help, "a burst the way you face", 1, true) ~= nil, role)
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
				-- (owner D19: a chained leap carries less, so the cooldown matters less; up a trunk a faster rhythm regrabs
				-- sooner and rises a little more, 27 against 25 st/s, both in the climb's band)
				local within = if i == 3 then 1.1 else 1.05
				t.truthy(
					now[i] <= now[6 + i] * within and now[3 + i] <= now[6 + i] * within,
					`{names[i]}: a macro about a person's pace (within {math.floor((within - 1) * 100 + 0.5)} %)`
				)
			end
			t.truthy(math.max(before[1], before[4]) > before[7] + 3, "(without it the macro was faster)")
		end
	)
end
