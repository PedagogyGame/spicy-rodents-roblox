--!strict
-- W1 §4.4 #5 motors under Lune: HumanAIMotor (the folded S5 integrator), QuadrupedMotor, CarMotor
-- over every VehicleKinds kind (car, cart, bike, pickup, SUV, jet ski), DroneMotor, Movement/Recovery
-- (v5.4 recoverRiverFall L14116-14132, safe-position history, unstick, roof push-off) and the
-- trampoline bounce (v5.4 attemptTrampolineBounce L10373-10392) on its own and inside SquirrelMotor.
local Height = require("@shared/World/Height")
local HumanAIMotor = require("@shared/Movement/HumanAIMotor")
local QuadrupedMotor = require("@shared/Movement/QuadrupedMotor")
local CarMotor = require("@shared/Movement/CarMotor")
local DroneMotor = require("@shared/Movement/DroneMotor")
local Recovery = require("@shared/Movement/Recovery")
local Trampoline = require("@shared/Movement/Trampoline")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local VehicleKinds = require("@shared/Vehicles/VehicleKinds")
local Kinematics = require("@server/AI/Kinematics")
local Common = require("@server/Actors/Brains/Common")

local S = 2.5
local flat = function(_x: number, _z: number, _r: number): number
	return 0
end

return function(t)
	t.test("HumanAIMotor is the S5 integrator: Kinematics delegates and walk/heading/stand behave", function()
		local ctx = {
			groundAt = function()
				return 0
			end,
			bounds = { minX = -100, maxX = 100, minZ = -100, maxZ = 100 },
		}
		local a = Common.newActor(1, "human", "x", "Pedestrian", 0, 0, 2.5)
		a.intent.mode = "walk"
		a.intent.tx, a.intent.tz, a.intent.speed = 0, 50, 3
		for _ = 1, 120 do
			Kinematics.step(a, 1 / 60, ctx :: any)
		end
		t.truthy(a.z > 4 and a.z < 6.5, `walked {a.z}`)
		t.near(a.y, 2.5, 1e-9)
		t.eq(Kinematics.railPose, HumanAIMotor.railPose)
		local snap = HumanAIMotor.serialize(a :: any)
		t.near(snap.vz, a.speed, 1e-9)
		a.intent.mode = "heading"
		a.intent.heading, a.intent.speed = math.pi / 2, 4
		for _ = 1, 1800 do
			HumanAIMotor.step(a :: any, 1 / 60, ctx :: any)
		end
		t.truthy(a.x <= 100 and a.x > 50, "heading +X until the clamp")
	end)

	t.test("QuadrupedMotor: camera-relative run, sprint cap, jump and land, wall slide, envelope", function()
		for _, species in { "fox", "deer" } do
			local p = QuadrupedMotor.paramsFor(species)
			local s = QuadrupedMotor.new(0, p.hip, 0, 0)
			local world = { groundAt = flat }
			local input = QuadrupedMotor.idleInput(0) -- camera yaw 0: forward is -Z
			input.fw, input.sprint = 1, true
			for _ = 1, 120 do
				local prev = QuadrupedMotor.deserialize(QuadrupedMotor.serialize(s))
				QuadrupedMotor.step(s, input, 1 / 60, world, p)
				local ok, why = QuadrupedMotor.envelope(prev, s, 1 / 60, p)
				t.truthy(ok, `{species} envelope {why}`)
			end
			t.truthy(s.z < -p.sprint * 1.2, `{species} ran toward -Z: {s.z}`)
			t.truthy(math.abs(s.vz + p.sprint) < 0.5, `{species} at sprint {s.vz}`)
			t.near(s.y, p.hip, 1e-9)
			input.jump = true
			QuadrupedMotor.step(s, input, 1 / 60, world, p)
			input.jump = false
			t.truthy(not s.grounded and s.y > p.hip, "jumped")
			local landed = false
			for _ = 1, 240 do
				local _, ev = QuadrupedMotor.step(s, input, 1 / 60, world, p)
				for _, e in ev do
					landed = landed or e.kind == "land"
				end
			end
			t.truthy(landed and s.grounded, "landed")
		end
		-- wall at z < -10 blocks Z but sliding along X continues
		local p = QuadrupedMotor.paramsFor("fox")
		local s = QuadrupedMotor.new(0, p.hip, 0, 0)
		local world = {
			groundAt = flat,
			blocked = function(_x: number, z: number, _y: number): boolean
				return z < -10
			end,
		}
		local input = QuadrupedMotor.idleInput(0)
		input.fw, input.side = 1, 1
		for _ = 1, 180 do
			QuadrupedMotor.step(s, input, 1 / 60, world, p)
		end
		t.truthy(s.z >= -10 and s.x > 10, `slid along the wall ({s.x}, {s.z})`)
	end)

	t.test("CarMotor: every kind accelerates to its top speed, brakes, reverses, steers right, envelope", function()
		for _, id in VehicleKinds.list() do
			local k = VehicleKinds.kind(id)
			local s = CarMotor.new(id, 0, k.size[2] / 2, 0, 0)
			local world = {
				groundAt = flat,
				waterAt = function(_x: number, _z: number): number?
					return 0
				end,
			}
			for _ = 1, 60 * 20 do
				local prev = CarMotor.deserialize(CarMotor.serialize(s))
				CarMotor.step(s, { throttle = 1, steer = 0, handbrake = false }, 1 / 60, world)
				local ok, why = CarMotor.envelope(prev, s, 1 / 60)
				t.truthy(ok, `{id} envelope {why}`)
			end
			t.near(s.speed, k.maxSpeed, 1e-6, `{id} top speed`)
			t.truthy(s.z > 100 and math.abs(s.x) < 1e-6, `{id} drove straight along +Z`)
			for _ = 1, 60 * 10 do
				CarMotor.step(s, { throttle = -1, steer = 0, handbrake = false }, 1 / 60, world)
			end
			t.near(s.speed, -k.reverseSpeed, 1e-6, `{id} reverse`)
			-- steer right from rest heading +Z: right of +Z in the HTML convention is -X
			local r = CarMotor.new(id, 0, 0, 0, 0)
			for _ = 1, 40 do
				CarMotor.step(r, { throttle = 1, steer = 1, handbrake = false }, 1 / 60, world)
			end
			t.truthy(r.yaw < 0 and r.x < 0, `{id} turned right (yaw {r.yaw}, x {r.x})`)
			if k.motor == "bike" then
				t.truthy(r.lean ~= 0, "bike leans")
			end
		end
	end)

	t.test("CarMotor: walls stop the car, the jet ski stays on the water, cars follow the ground", function()
		local world = {
			groundAt = function(x: number, _z: number, _r: number): number
				return x * 0.1
			end,
			blocked = function(_x: number, z: number, _y: number, _r: number): boolean
				return z > 30
			end,
		}
		local s = CarMotor.new("car", 0, 3, 0, 0)
		local bumped = false
		for _ = 1, 600 do
			local _, ev = CarMotor.step(s, { throttle = 1, steer = 0, handbrake = false }, 1 / 60, world)
			for _, e in ev do
				bumped = bumped or e.kind == "bump"
			end
		end
		t.truthy(s.z <= 30 and bumped, `stopped at the wall {s.z}`)
		local j = CarMotor.new("jetski", 0, 0, 0, 0)
		local water = {
			groundAt = flat,
			waterAt = function(_x: number, z: number): number?
				return if z < 40 then 6 else nil
			end,
		}
		for _ = 1, 600 do
			CarMotor.step(j, { throttle = 1, steer = 0, handbrake = false }, 1 / 60, water)
		end
		t.truthy(j.z < 40 and j.speed == 0, `jet ski stopped at the shore {j.z}`)
		t.truthy(j.y > 6 and j.y < 8, "rides the surface")
		local c = CarMotor.new("cart", 50, 10, 0, math.pi / 2)
		for _ = 1, 60 do
			CarMotor.step(c, { throttle = 1, steer = 0, handbrake = false }, 1 / 60, world)
		end
		local half = VehicleKinds.kind("cart").size[2] / 2
		t.near(c.y, c.x * 0.1 + half, 1e-6, "on the slope")
	end)

	t.test("DroneMotor: clearance floor, ceiling, boost, envelope", function()
		local p = DroneMotor.params()
		local s = DroneMotor.new(0, 50, 0)
		local world = {
			groundAt = function()
				return 20
			end,
		}
		local inp = DroneMotor.idleInput(0)
		inp.up = -1
		for _ = 1, 300 do
			DroneMotor.step(s, inp, 1 / 60, world)
		end
		t.near(s.y, 20 + p.clearance, 1e-9, "floor")
		inp.up, inp.boost, inp.fw = 1, true, 1
		for _ = 1, 60 * 20 do
			local prev = DroneMotor.deserialize(DroneMotor.serialize(s))
			DroneMotor.step(s, inp, 1 / 60, world)
			local ok, why = DroneMotor.envelope(prev, s, 1 / 60)
			t.truthy(ok, `envelope {why}`)
		end
		t.near(s.y, p.ceiling, 1e-9, "ceiling")
		t.truthy(s.z < -2000, `boosted far ({s.z})`)
	end)

	t.test("Recovery: v5.4 river fall to the nearer quay, history, unstick, reset routing, push-off", function()
		local R = Height.RIVER
		-- in the water west of the centre at z = 100 u
		local x, z = (Height.riverCenterU(100) - 10) * S, 100 * S
		local rx, ry, rz = Recovery.riverFall(x, R.waterY * S, z)
		t.near(rx :: number, (Height.riverCenterU(100) - R.halfWidth - 5) * S, 1e-9)
		t.near(ry :: number, (R.bankY + 0.18) * S, 1e-9)
		t.near(rz :: number, z, 1e-9)
		-- east side, clamped z
		local ex = (Height.riverCenterU(430) + 3) * S
		local qx, _, qz = Recovery.riverFall(ex, 0, 430 * S)
		t.near(qz :: number, 425 * S, 1e-9)
		t.near(qx :: number, (Height.riverCenterU(425) + R.halfWidth + 5) * S, 1e-9)
		t.eq(Recovery.riverFall(x, (R.waterY + 1) * S, z), nil, "above the water: no recovery")
		t.eq(Recovery.riverFall(0, 0, 0), nil, "dry land")
		local h = Recovery.newHistory(5, 0.5)
		for i = 0, 9 do
			Recovery.record(h, i * 0.5, i * 2, 1, 0, true)
		end
		t.eq(h.count, 5)
		t.eq((Recovery.safePos(h) :: any).x, 18)
		local u = Recovery.unstick(h, 18, 1, 0, 5) :: any
		t.eq(u.x, 12)
		t.truthy(not Recovery.record(h, 100, 0 / 0, 0, 0, true), "NaN refused")
		local _, _, _, why = Recovery.resetTarget(h, x, R.waterY * S, z)
		t.eq(why, "river")
		local pushed = Recovery.onVehicleMoved(
			{ x = 0, z = 0, yaw = 0, width = 6, length = 11, top = 5 },
			{ { id = "a", x = 1, y = 5.2, z = 2 }, { id = "b", x = 9, y = 5, z = 0 } }
		)
		t.eq(#pushed, 1)
		t.near(math.abs(pushed[1].x), 4.2, 1e-9)
	end)

	t.test("Trampoline: v5.4 bounce numbers, count cap and reset, the bed as ground", function()
		local site = Trampoline.site(-33 * S, 80 * S, 0)
		local body = { x = -33 * S, y = 1.80 * S, z = 80 * S, vx = 0, vy = -5, vz = 0, grounded = false }
		t.truthy(Trampoline.attempt(site, body :: any, 2.2 * S, 0), "bounced")
		t.near(body.y, (1.68 + 0.22) * S, 1e-9)
		t.near(body.vy, (14.2 + 0.9) * S, 1e-9)
		t.near(body.vz, -1.6 * S, 1e-9, "camera-forward push")
		for i = 2, 6 do
			body.y, body.vy = 1.8 * S, -1
			Trampoline.attempt(site, body :: any, 2.2 * S, 0)
			t.near(body.vy, (14.2 + 0.9 * math.min(4, i)) * S, 1e-9)
		end
		-- rising, or off the bed, or on a rail: no bounce
		body.y, body.vy = 1.8 * S, 3
		t.truthy(not Trampoline.attempt(site, body :: any, 2.2 * S, 0), "rising")
		body.x, body.vy = (-33 + 10) * S, -1
		t.truthy(not Trampoline.attempt(site, body :: any, 2.2 * S, 0), "away")
		t.eq(site.count, 0, "reset beyond 9 u")
		t.near(Trampoline.bedAt({ site }, -33 * S, 80 * S, 2 * S) :: number, 1.65 * S, 1e-9)
		t.eq(Trampoline.bedAt({ site }, -33 * S, 80 * S, 0.5 * S), nil, "below the bed")
	end)

	t.test("Trampoline inside SquirrelMotor: a squirrel dropped on the bed bounces (bounce event)", function()
		local Data = require("@shared/Data")
		local RailWorld = require("@shared/Movement/RailWorld")
		local rail = RailWorld.get(Data.default(), Height.at)
		t.eq(#rail.trampolines, 1, "one trampoline route in the harvest")
		local site = rail.trampolines[1]
		t.near(site.x / S, -33, 0.2)
		t.near(site.z / S, 80, 0.2)
		local world = {
			registry = rail.registry,
			index = rail.index,
			graph = rail.graph,
			trampolines = rail.trampolines,
			groundAt = function(x: number, z: number, _r: number): number
				return Height.at(x, z)
			end,
		}
		local s = SquirrelMotor.new(site.x + 1, site.surface + 6, site.z + 1)
		s.grounded = false
		local bounced = false
		for _ = 1, 120 do
			local _, ev = SquirrelMotor.step(s, SquirrelMotor.idleInput(0), 1 / 60, world :: any)
			for _, e in ev do
				bounced = bounced or e.kind == "bounce"
			end
		end
		t.truthy(bounced, "bounce event")
		site.count = 0
	end)
end
