--!strict
-- The kinematic squirrel (owner rule 2026-11-09): Movement/SquirrelVisual (the drawn point that follows the
-- motor), the motor's ground glue, Movement/RailWorld.empty, the climb pose in Client/Animation/Gait,
-- Client/Camera/CameraRig.focusStep and Client/World/ClientWorld.groundLike. What is pinned: running on flat
-- ground has no vertical motion at any frame rate; the drawn feet touch the ground on slopes; a kerb is
-- spread over a few frames and never overshoots; a grounded body follows the ground downhill without
-- leaving it; mounting a trunk, climbing a pole and crossing onto a wire never snap or pop; walking,
-- sprinting or grabbing onto a pole is eased, never cut; a long fall has no sawtooth; a landing on a
-- platform never dips toward its foot; every draped tile the bake draws is ground to the client; and the
-- motor is re-placed after a river fall or a server teleport (SquirrelMotor.place, Squirrel.movedFromOutside).
local Units = require("@shared/Config/Units")
local Motion = require("@shared/Routes/Motion")
local Registry = require("@shared/Routes/Registry")
local RailWorld = require("@shared/Movement/RailWorld")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local SquirrelVisual = require("@shared/Movement/SquirrelVisual")
local TestWorld = require("@tests/cheat/TestWorld")
local CameraRig = require("@client/Camera/CameraRig")
local ClientWorld = require("@client/World/ClientWorld")
local Gait = require("@client/Animation/Gait")
local Squirrel = require("@client/Controllers/Squirrel")
local Hud = require("@client/UI/Hud")
local Human = require("@client/Controllers/Human")
local Bake = require("@worldgen/Bake")

local st = Units.st
local P = SquirrelVisual.params

-- a motor world with no routes over the given ground
local function open(groundAt: (x: number, z: number, refY: number) -> number): SquirrelMotor.World
	local e = RailWorld.empty()
	return {
		registry = e.registry,
		index = e.index,
		graph = e.graph,
		trampolines = e.trampolines,
		groundAt = groundAt,
	} :: any
end

-- frame times as a player sees them: 60 Hz, 144 Hz, 30 Hz, and an uneven mix with hitches
local function frameDt(pattern: string, i: number): number
	if pattern == "60" then
		return 1 / 60
	elseif pattern == "144" then
		return 1 / 144
	elseif pattern == "30" then
		return 1 / 30
	end
	if i % 97 == 0 then
		return 0.07
	end
	return (1 / 60) * (1 + 0.6 * math.sin(i * 1.7))
end

local function shortest(a: number): number
	return math.atan2(math.sin(a), math.cos(a))
end

return function(t)
	local world = TestWorld.build()
	local input = SquirrelMotor.idleInput

	t.test("update: snaps on the first frame and on a teleport, eases at 23/s (17/s on a bridge)", function()
		local ground = { ground = true, rail = false, bridging = false }
		local rail = { ground = false, rail = true, bridging = false }
		local bridge = { ground = false, rail = true, bridging = true }
		-- a drawn point at rest on its target at the origin
		local function rest(): SquirrelVisual.Visual
			local v = SquirrelVisual.new()
			t.eq(SquirrelVisual.update(v, 0, 0, 0, 1 / 60, ground), true, "the first frame snaps")
			return v
		end
		local v = SquirrelVisual.new()
		SquirrelVisual.update(v, 10, 2, 30, 1 / 60, ground)
		t.eq(v.x, 10)
		t.eq(v.y, 2)
		t.eq(v.z, 30)
		-- a gap to a target that stands still closes by 1 - exp(-23 dt) per frame on every axis
		v.x, v.y, v.z = 9, 1, 28
		t.eq(SquirrelVisual.update(v, 10, 2, 30, 1 / 60, ground), false)
		local a = 1 - math.exp(-23 / 60)
		t.near(v.x, 9 + a, 1e-12)
		t.near(v.y, 1 + a, 1e-12)
		t.near(v.z, 28 + 2 * a, 1e-12)
		-- 2.5 u = 6.25 st is the teleport gap off a rail, 1.6 u = 4 st on one
		t.eq(SquirrelVisual.update(rest(), 5, 0, 0, 1 / 60, ground), false, "5 st on the ground eases")
		t.eq(SquirrelVisual.update(rest(), 5, 0, 0, 1 / 60, rail), true, "5 st on a rail snaps")
		t.eq(SquirrelVisual.update(rest(), 6.5, 0, 0, 1 / 60, ground), true, "6.5 st snaps")
		t.near(st(2.5), P.snap, 1e-12)
		t.near(st(1.6), P.railSnap, 1e-12)
		-- the cut is on the target's own jump, not on the distance trailed: a drawn point far behind a
		-- target that stands still eases
		v = rest()
		v.x = -10
		t.eq(SquirrelVisual.update(v, 0, 0, 0, 1 / 60, ground), false, "trailing far behind is not a teleport")
		t.near(v.x, -10 * math.exp(-23 / 60), 1e-12)
		-- what the motor travels in the frame is not a jump (a long frame at speed)
		local hitch = { ground = true, rail = false, bridging = false, travel = 7 }
		t.eq(SquirrelVisual.update(rest(), 7, 0, 0, 1 / 6, hitch), false, "7 st travelled in a hitch")
		hitch.travel = 0.5
		t.eq(SquirrelVisual.update(rest(), 7, 0, 0, 1 / 6, hitch), true, "7 st with 0.5 st travelled")
		-- mounting a rail from the ground or the air is eased however far the target moves
		local mount = { ground = false, rail = true, bridging = false, mounted = true }
		v = rest()
		t.eq(SquirrelVisual.update(v, 7.5, 3, 0, 1 / 60, mount), false, "a mount is eased")
		t.truthy(v.x > 0 and v.x < 7.5 * (1 - math.exp(-23 / 60)) + 1e-9, "and has not arrived")
		-- a transfer bridge never snaps and eases at 17/s
		v = rest()
		t.eq(SquirrelVisual.update(v, 12, 0, 0, 1 / 60, bridge), false)
		t.truthy(v.x > 0 and v.x < 12 * (1 - math.exp(-17 / 60)), "eased, the jump taken as a move")
		t.eq(SquirrelVisual.update(v, 12, 0, 0, 1 / 60, bridge), false)
		local x1 = v.x
		SquirrelVisual.update(v, 12, 0, 0, 1 / 60, bridge)
		t.near(v.x, x1 + (12 - x1) * (1 - math.exp(-17 / 60)), 1e-12)
		-- a target moving at a steady 42 st/s is trailed by 42 / 23 st at any frame time, and the drawn
		-- point moves at exactly its speed once settled
		for _, hz in { 30, 60, 144, 240 } do
			v = rest()
			local x = 0
			local lastX = 0
			for _ = 1, hz * 3 do
				x += 42 / hz
				lastX = v.x
				SquirrelVisual.update(v, x, 0, 0, 1 / hz, rail)
			end
			t.near(x - v.x, 42 / 23, 1e-9, `lag at {hz} Hz`)
			t.near((v.x - lastX) * hz, 42, 1e-6, `drawn speed at {hz} Hz`)
		end
	end)

	t.test("flat ground: a run has no vertical motion, no pitch and no lean at any frame rate", function()
		for _, pattern in { "60", "144", "30", "uneven" } do
			local w = open(function(_x: number, _z: number, _refY: number): number
				return 4.2
			end)
			local s = SquirrelMotor.new(0, 4.2, 0)
			s.tireless = true -- a long sprint: the sprint meter has its own test (movement_motor)
			local v = SquirrelVisual.new()
			local inp = input(math.pi)
			inp.fw = 1
			local maxStep = 0
			for i = 1, 900 do
				local dt = frameDt(pattern, i)
				inp.sprint = i > 200
				inp.side = if i > 500 and i < 560 then 1 else 0
				local lastX, lastZ = v.x, v.z
				local _, events = SquirrelMotor.step(s, inp, dt, w)
				for _, e in events do
					t.truthy(e.kind ~= "land", `{pattern}: a land event on flat ground`)
				end
				local snapped = SquirrelVisual.frame(v, s, w, dt)
				t.eq(snapped, i == 1, `{pattern}: snap at frame {i}`)
				t.eq(s.grounded, true)
				t.eq(s.y, 4.2)
				t.eq(v.y, 4.2, `{pattern}: drawn height at frame {i}`)
				t.eq(v.pitch, 0)
				t.eq(v.climb, 0)
				if i > 1 then
					maxStep = math.max(maxStep, math.sqrt((v.x - lastX) ^ 2 + (v.z - lastZ) ^ 2) / dt)
				end
			end
			-- the drawn point never moves faster than the motor can (the sprint speed)
			t.truthy(maxStep <= SquirrelMotor.params.sprint * 1.02, `{pattern}: drawn speed {maxStep}`)
			-- straight again for the last 5 s: level, and trailing the motor by speed / 23
			t.truthy(math.abs(v.lean) < 0.01, `{pattern}: lean {v.lean}`)
			local lag = math.sqrt((s.x - v.x) ^ 2 + (s.z - v.z) ^ 2)
			t.truthy(lag < SquirrelMotor.params.sprint / P.rate * 1.6, `{pattern}: lag {lag}`)
			t.near(v.moveSpeed, s.moveSpeed, 1e-12)
			t.near(v.cadence, Units.u(SquirrelMotor.params.sprint) * 2.85, 0.2, `{pattern}: sprint cadence`)
		end
	end)

	t.test("slopes: the motor stays grounded up and down and the drawn feet touch the ground under them", function()
		for _, pattern in { "60", "144", "uneven" } do
			-- a ridge along x: 0.45 up to z = 60, 0.6 down beyond, rounded hills on top
			local function h(x: number, z: number, _refY: number): number
				local ridge = if z < 60 then 0.45 * z else 27 - 0.6 * (z - 60)
				return ridge + 1.5 * math.sin(z / 9) + 0.8 * math.sin(x / 7)
			end
			local w = open(h)
			local s = SquirrelMotor.new(0, h(0, 0, 0), 0)
			local v = SquirrelVisual.new()
			local inp = input(math.pi)
			inp.fw = 1
			inp.sprint = true
			local worst = 0
			local elapsed, i = 0, 0
			-- 6.5 s of running at every frame pattern (far enough to be well down the far side)
			while elapsed < 6.5 do
				i += 1
				local dt = frameDt(pattern, i)
				elapsed += dt
				inp.side = if elapsed % 2 < 0.5 then 1 else 0
				local _, events = SquirrelMotor.step(s, inp, dt, w)
				for _, e in events do
					t.truthy(e.kind ~= "land", `{pattern}: left the ground at frame {i}`)
				end
				t.eq(s.grounded, true, `{pattern}: grounded at frame {i}`)
				t.near(s.y, h(s.x, s.z, 0), 1e-9)
				t.eq(SquirrelVisual.frame(v, s, w, dt), i == 1)
				worst = math.max(worst, math.abs(v.y - h(v.x, v.z, 0)))
			end
			t.truthy(s.z > 150, `{pattern}: crossed the ridge ({s.z})`)
			t.truthy(worst < 0.03, `{pattern}: drawn feet off the ground by {worst} st`)
		end
	end)

	t.test("a kerb and a plate lip are spread over a few frames, never overshoot, and the motor stays down", function()
		for _, pattern in { "60", "144", "30", "uneven" } do
			for _, case in { { 0.3, false }, { 0.3, true }, { 0.5, false }, { -0.3, false }, { -0.5, true } } do
				local rise, sprint = case[1] :: number, case[2] :: boolean
				local name = `kerb {rise} at {pattern}`
				local function h(_x: number, z: number, _refY: number): number
					return if z >= 30 then 2 + rise else 2
				end
				local w = open(h)
				local s = SquirrelMotor.new(0, 2, 0)
				local v = SquirrelVisual.new()
				local inp = input(math.pi)
				inp.fw = 1
				inp.sprint = sprint
				local maxStep, frames = 0, 0
				local lo, hi = math.min(2, 2 + rise), math.max(2, 2 + rise)
				local elapsed, i = 0, 0
				while elapsed < 4 do
					i += 1
					local dt = frameDt(pattern, i)
					elapsed += dt
					local lastY = v.y
					local _, events = SquirrelMotor.step(s, inp, dt, w)
					for _, e in events do
						t.truthy(e.kind ~= "land", `{name}: land event`)
					end
					t.eq(s.grounded, true, `{name}: grounded`)
					t.eq(SquirrelVisual.frame(v, s, w, dt), i == 1)
					t.truthy(v.y >= lo - 1e-9 and v.y <= hi + 1e-9, `{name}: overshoot {v.y}`)
					if i > 1 then
						local d = (v.y - lastY) * (if rise > 0 then 1 else -1)
						t.truthy(d >= -1e-9, `{name}: the drawn height reverses`)
						maxStep = math.max(maxStep, d)
						if d > 1e-6 then
							frames += 1
						end
					end
				end
				t.truthy(s.z > 40, "ran past the kerb")
				t.near(v.y, 2 + rise, 1e-6, `{name}: settled`)
				-- the share of the kerb taken in one frame does not grow with the distance covered in it
				-- (a 70 ms hitch in the uneven pattern is most of the easing time, so most of the kerb)
				local share = maxStep / math.abs(rise)
				t.truthy(share <= (if pattern == "uneven" then 0.95 else 0.75), `{name}: {share} of it in one frame`)
				local most = if pattern == "144" then 30 elseif pattern == "30" then 8 else 14
				t.truthy(frames >= 2 and frames <= most, `{name}: over {frames} frames`)
			end
		end
	end)

	t.test("a ledge deeper than the glue is a fall: one land event, and the drawn point eases after it", function()
		local function h(_x: number, z: number, _refY: number): number
			return if z >= 20 then 0 else 6
		end
		local w = open(h)
		local s = SquirrelMotor.new(0, 6, 0)
		local v = SquirrelVisual.new()
		local inp = input(math.pi)
		inp.fw = 1
		local lands, airborne = 0, 0
		for i = 1, 240 do
			local lastY = v.y
			local _, events = SquirrelMotor.step(s, inp, 1 / 60, w)
			for _, e in events do
				if e.kind == "land" then
					lands += 1
				end
			end
			if not s.grounded then
				airborne += 1
			end
			t.eq(SquirrelVisual.frame(v, s, w, 1 / 60), i == 1, `snap at frame {i}`)
			if i > 1 then
				t.truthy(v.y <= lastY + 1e-9, "the drawn point only goes down")
				t.truthy(lastY - v.y < 1.2, `drawn drop {lastY - v.y} st in one frame`)
			end
			t.truthy(v.y >= -1e-9, "never below the lower ground")
		end
		t.eq(lands, 1)
		t.truthy(airborne > 10, `airborne for {airborne} frames`)
		t.near(v.y, 0, 1e-3)
		t.eq(s.grounded, true)
	end)

	t.test("RailWorld.empty: the motor runs, leaps and looks for a grab with no routes", function()
		local w = open(function(_x: number, _z: number, _refY: number): number
			return 1
		end)
		local s = SquirrelMotor.new(5, 1, 5)
		local inp = input(math.pi)
		inp.grab = true
		SquirrelMotor.step(s, inp, 1 / 60, w)
		inp.grab = false
		t.eq(s.routeId, nil)
		inp.leap = true
		inp.fw = 1
		SquirrelMotor.step(s, inp, 1 / 60, w)
		inp.leap = false
		t.eq(s.grounded, false)
		local v = SquirrelVisual.new()
		local landed = false
		for _ = 1, 120 do
			local _, events = SquirrelMotor.step(s, inp, 1 / 60, w)
			for _, e in events do
				landed = landed or e.kind == "land"
			end
			SquirrelVisual.frame(v, s, w, 1 / 60)
		end
		t.truthy(landed, "the leap lands")
		t.eq(s.y, 1)
		t.near(v.y, 1, 1e-3)
		t.truthy(s.z > 5 + st(6), "and carries forward")
	end)

	t.test("lean: into the turn, clamped, level on a trunk; trunk yaw faces the bark; pitch 0.83 -> 1.43", function()
		local v = SquirrelVisual.new()
		SquirrelVisual.lean(v, 0, 1 / 60)
		t.eq(v.lean, 0)
		local yaw = 0
		for _ = 1, 120 do
			yaw += 3 / 60 -- 3 rad/s of increasing yaw
			SquirrelVisual.lean(v, yaw, 1 / 60)
		end
		t.near(v.lean, -3 * P.leanPerTurn, 0.002)
		for _ = 1, 120 do
			yaw -= 40 / 60
			SquirrelVisual.lean(v, yaw, 1 / 60)
		end
		t.near(v.lean, P.leanMax, 0.002)
		for _ = 1, 120 do
			yaw -= 40 / 60
			SquirrelVisual.lean(v, yaw, 1 / 60, true)
		end
		t.truthy(math.abs(v.lean) < 1e-6, "held level")
		-- a frame hitch does not turn a small heading change into a lurch
		local v2 = SquirrelVisual.new()
		SquirrelVisual.lean(v2, 0, 1 / 60)
		SquirrelVisual.lean(v2, 0.02, 0.001)
		t.truthy(math.abs(v2.lean) < 0.005)
		-- the same turn reads the same lean at any frame rate
		for _, hz in { 30, 60, 144, 240 } do
			local vh = SquirrelVisual.new()
			local y = 0
			SquirrelVisual.lean(vh, 0, 1 / hz)
			for _ = 1, hz * 2 do
				y += 3 / hz
				SquirrelVisual.lean(vh, y, 1 / hz)
			end
			t.near(vh.lean, -3 * P.leanPerTurn, 0.002, `lean at {hz} Hz`)
		end
		-- a body at HTML yaw faces (sin yaw, cos yaw): facing the bark is facing against the outward normal
		for _, n in { { 0, 1 }, { 1, 0 }, { -0.6, 0.8 } } do
			local y = SquirrelVisual.trunkYaw(n[1], n[2])
			t.near(math.sin(y), -n[1], 1e-12)
			t.near(math.cos(y), -n[2], 1e-12)
		end
		t.near(SquirrelVisual.trunkPitch(0), 0.83, 1e-12)
		t.near(SquirrelVisual.trunkPitch(st(0.25)), 0.83, 1e-12)
		t.near(SquirrelVisual.trunkPitch(st(2.4)), 1.43, 1e-12)
		t.near(SquirrelVisual.trunkPitch(100), 1.43, 1e-12)
		t.truthy(SquirrelVisual.trunkPitch(st(1.3)) > 0.83 and SquirrelVisual.trunkPitch(st(1.3)) < 1.43)
		-- cadence: 2.85 rad per u on the ground, 0.7 on a rail, x1.14 boosted
		t.near(SquirrelVisual.cadence(st(8), false, false), 22.8, 1e-9)
		t.near(SquirrelVisual.cadence(st(8), true, false), 5.6, 1e-9)
		t.near(SquirrelVisual.cadence(st(8), false, true), 22.8 * 1.14, 1e-9)
		t.eq(SquirrelVisual.cadence(0, false, false), 0)
	end)

	t.test("walking onto the BUR OAK trunk: no snap, no pop; paws near the bark, nose up, facing in", function()
		local trunk = world.registry:get(220) :: Registry.Route
		local foot = world.registry:foot(trunk)
		local s = SquirrelMotor.new(foot.x, world.groundHeight, foot.z - st(3))
		local v = SquirrelVisual.new()
		local inp = input(math.pi)
		inp.fw = 1
		local attachedAt: number? = nil
		local maxMove, maxYaw, maxPitch = 0, 0, 0
		for i = 1, 360 do
			local lx, ly, lz, lyaw, lpitch = v.x, v.y, v.z, v.yaw, v.pitch
			local _, events = SquirrelMotor.step(s, inp, 1 / 60, world)
			for _, e in events do
				if e.kind == "attach" then
					attachedAt = i
				end
			end
			-- stop climbing two seconds after the grab and let the pose settle
			if attachedAt and i > attachedAt + 120 then
				inp.fw = 0
			end
			t.eq(SquirrelVisual.frame(v, s, world, 1 / 60), i == 1, `snap at frame {i}`)
			if i > 1 then
				maxMove = math.max(maxMove, math.sqrt((v.x - lx) ^ 2 + (v.y - ly) ^ 2 + (v.z - lz) ^ 2))
				maxYaw = math.max(maxYaw, math.abs(shortest((v.yaw :: number) - (lyaw :: number))))
				maxPitch = math.max(maxPitch, math.abs(v.pitch - lpitch))
			end
		end
		t.truthy(attachedAt ~= nil, "walk-in grab")
		t.eq(s.routeId, 220)
		print(`      trunk mount: max drawn move {maxMove} st, yaw {maxYaw} rad, pitch {maxPitch} rad per frame`)
		t.truthy(maxMove < 0.9, `drawn move {maxMove} st in one frame`)
		t.truthy(maxYaw < 0.8, `heading change {maxYaw} rad in one frame`)
		t.truthy(maxPitch < 0.4, `pitch change {maxPitch} rad in one frame`)
		-- settled: the feet point sits barkGap outside the bark that v5.4's pad was measured from
		local vis = SquirrelMotor.visualPose(s, world)
		local out = math.sqrt((vis.x - s.x) ^ 2 + (vis.z - s.z) ^ 2)
		local drawn = math.sqrt((v.x - s.x) ^ 2 + (v.z - s.z) ^ 2)
		t.near(drawn, out - (Motion.C.visualTrunkPad - P.barkGap), 0.01, "bark gap")
		t.truthy(drawn < out, "pulled in from v5.4's pad")
		t.near(v.y, vis.y, 0.01)
		-- nose up at the full grip pitch, facing the trunk axis, level
		t.near(v.pitch, 1.43, 0.01)
		t.near(v.climb, 1, 0.01)
		local fx, fz = math.sin(v.yaw :: number), math.cos(v.yaw :: number)
		local ax, az = (s.x - v.x) / drawn, (s.z - v.z) / drawn
		t.truthy(fx * ax + fz * az > 0.999, "faces the bark")
		t.truthy(math.abs(v.lean) < 0.01)
		t.near(v.cadence, 0, 1e-6, "still")
	end)

	t.test("up a pole and onto a wire: no snap, no pop; paws near the pole; level again on the wire", function()
		local poleId: number? = nil
		for _, r in world.registry:all() do
			if r.flags.isPole and #world.graph:endLinks(r.id, false) >= 2 then
				poleId = r.id
				break
			end
		end
		local pole = world.registry:get(poleId :: number) :: Registry.Route
		local link = world.graph:endLinks(pole.id, false)[1]
		local wire = world.registry:get(link.to) :: Registry.Route
		local tan = world.registry:tangentAt(wire, math.clamp(link.t, 0.002, 0.998))
		local dir = Motion.inward(link.t, 1)
		local inp = input(math.atan2(-tan.x * dir, -tan.z * dir))
		local low = world.registry:pointAt(pole, 0.35)
		local s = SquirrelMotor.new(low.x, low.y, low.z)
		inp.grab = true
		SquirrelMotor.step(s, inp, 1 / 60, world)
		inp.grab = false
		t.eq(s.routeId, pole.id)
		inp.fw = 1
		local v = SquirrelVisual.new()
		local switchedAt: number? = nil
		local maxMove, maxYaw, maxPitch = 0, 0, 0
		local gapChecked = false
		for i = 1, 900 do
			local lx, ly, lz, lyaw, lpitch = v.x, v.y, v.z, v.yaw, v.pitch
			local _, events = SquirrelMotor.step(s, inp, 1 / 60, world)
			for _, e in events do
				if e.kind == "autoSwitch" and not switchedAt then
					switchedAt = i
				end
			end
			t.eq(SquirrelVisual.frame(v, s, world, 1 / 60), i == 1, `snap at frame {i}`)
			if i > 1 then
				maxMove = math.max(maxMove, math.sqrt((v.x - lx) ^ 2 + (v.y - ly) ^ 2 + (v.z - lz) ^ 2))
				maxYaw = math.max(maxYaw, math.abs(shortest((v.yaw :: number) - (lyaw :: number))))
				maxPitch = math.max(maxPitch, math.abs(v.pitch - lpitch))
			end
			if i == 40 and not switchedAt then
				-- on the pole: the feet point is poleGap outside its surface, nose up
				local d = math.sqrt((v.x - s.x) ^ 2 + (v.z - s.z) ^ 2)
				t.near(d, pole.surfaceRadius + P.poleGap, 0.02, "pole gap")
				t.near(v.pitch, 1.43, 0.02)
				gapChecked = true
			end
			if switchedAt and i > switchedAt + 150 then
				break
			end
		end
		t.truthy(gapChecked, "checked the pole pose")
		t.truthy(switchedAt ~= nil, "pole top -> wire")
		t.eq((world.registry:get(s.routeId :: number) :: Registry.Route).kind, "wire")
		print(`      pole to wire: max drawn move {maxMove} st, yaw {maxYaw} rad, pitch {maxPitch} rad per frame`)
		t.truthy(maxMove < 0.9, `drawn move {maxMove} st in one frame`)
		t.truthy(maxYaw < 0.8, `heading change {maxYaw} rad in one frame`)
		t.truthy(maxPitch < 0.4, `pitch change {maxPitch} rad in one frame`)
		-- 2.5 s along the wire: level, heading along the motor's, riding the wire lift
		t.truthy(math.abs(v.pitch) < 0.01, `pitch {v.pitch}`)
		t.truthy(v.climb < 0.01)
		t.truthy(math.abs(shortest((v.yaw :: number) - s.yaw)) < 0.01, "heading follows the wire")
		local vis = SquirrelMotor.visualPose(s, world)
		t.truthy(math.abs(v.y - vis.y) < 0.15, `wire height {v.y - vis.y}`)
		t.near(v.cadence, SquirrelVisual.cadence(s.moveSpeed, true, false), 1e-9)
	end)

	t.test("poles and thin trunks: a walk-in, a sprint-in and a grab from reach are eased, never cut", function()
		-- a pole (1 st) and the thinnest and thickest trees, with the ground at each one's foot as it is in
		-- the town
		local picks: { Registry.Route } = {}
		local poles, thin, thick = 0, nil :: Registry.Route?, nil :: Registry.Route?
		for _, r in world.registry:all() do
			if r.kind == "trunk" and not r.flags.autoGrabExcluded then
				if r.flags.isPole then
					poles += 1
					if poles % 40 == 1 and #picks < 6 then
						table.insert(picks, r)
					end
				else
					if not thin or r.surfaceRadius < thin.surfaceRadius then
						thin = r
					end
					if not thick or r.surfaceRadius > thick.surfaceRadius then
						thick = r
					end
				end
			end
		end
		table.insert(picks, thin :: Registry.Route)
		table.insert(picks, thick :: Registry.Route)
		t.truthy(#picks >= 4, `{#picks} trunks to mount`)
		local worstShare, worstPitch, mounts = 0, 0, 0
		for _, route in picks do
			local foot = world.registry:foot(route)
			local w: any = setmetatable({
				groundAt = function(_x: number, _z: number, _refY: number): number
					return foot.y
				end,
			}, { __index = world })
			for _, case in
				{
					{ "60", false, 0, false },
					{ "144", false, 1, false },
					{ "30", false, 2, false },
					{ "uneven", false, 3, false },
					{ "60", true, 1, false },
					{ "144", true, 2, false },
					{ "30", true, 0, false },
					{ "60", false, 2, true },
					{ "144", false, 3, true },
				}
			do
				local pattern, sprint = case[1] :: string, case[2] :: boolean
				local quarter, grab = case[3] :: number, case[4] :: boolean
				local name = `route {route.id} at {pattern}{if sprint then " sprinting" else ""}{if grab
					then " grabbing"
					else ""}`
				-- from one of four sides, facing the trunk
				local a = quarter * math.pi / 2
				local dx, dz = math.sin(a), math.cos(a)
				local from = if grab then Motion.C.groundReachE - 0.3 else 15
				local s = SquirrelMotor.new(foot.x - dx * from, foot.y, foot.z - dz * from)
				s.yaw = a
				local v = SquirrelVisual.new()
				local inp = input(a + math.pi)
				inp.fw = if grab then 0 else 1
				inp.sprint = sprint
				local attachedAt: number? = nil
				local attachedTo: number? = nil
				local elapsed, i, stopAt = 0, 0, 3
				-- until half a second up the trunk
				while elapsed < stopAt do
					i += 1
					local dt = frameDt(pattern, i)
					elapsed += dt
					inp.grab = grab and i == 20
					local lx, ly, lz, lpitch = v.x, v.y, v.z, v.pitch
					local ltx, lty, ltz = v.tx or lx, v.ty or ly, v.tz or lz
					local wasOn = s.routeId ~= nil
					SquirrelMotor.step(s, inp, dt, w)
					t.eq(SquirrelVisual.frame(v, s, w, dt), i == 1, `{name}: snap at frame {i}`)
					if s.routeId and not wasOn and not attachedAt then
						attachedAt = i
						attachedTo = s.routeId
						stopAt = elapsed + 0.5
						mounts += 1
						-- the frame of the mount: the drawn point starts toward the bark and has not
						-- arrived (it moves no more than one eased frame of its gap to the paws' place on
						-- the bark, or to where the motor was if that was further); the nose starts up
						-- and is not yet up
						local tx, ty, tz = v.tx :: number, v.ty :: number, v.tz :: number
						local gap = math.max(
							math.sqrt((tx - lx) ^ 2 + (ty - ly) ^ 2 + (tz - lz) ^ 2),
							math.sqrt((ltx - lx) ^ 2 + (lty - ly) ^ 2 + (ltz - lz) ^ 2)
						)
						local moved = math.sqrt((v.x - lx) ^ 2 + (v.y - ly) ^ 2 + (v.z - lz) ^ 2)
						local ease = 1 - math.exp(-P.rate * dt)
						t.truthy(gap > 0.3, `{name}: a gap of {gap} st to close`)
						worstShare = math.max(worstShare, moved / gap / ease)
						worstPitch = math.max(worstPitch, math.abs(v.pitch - lpitch) / (1 - math.exp(-P.poseRate * dt)))
					end
				end
				t.truthy(attachedAt ~= nil, `{name}: mounted`)
				t.eq(attachedTo, route.id, `{name}: onto its own trunk`)
			end
		end
		print(`      mounts: {mounts}; first-frame share of the gap {worstShare} x ease; pitch {worstPitch} rad x ease`)
		t.truthy(worstShare <= 1 + 1e-9, `the mount frame covers {worstShare} x one eased frame of the gap`)
		t.truthy(worstPitch <= P.trunkPitchHigh + 0.01, `pitch on the mount frame {worstPitch} rad x ease`)
	end)

	t.test("a 140 st fall: no cut and no sawtooth at any frame rate; the drawn point only goes down", function()
		for _, pattern in { "30", "60", "144", "uneven" } do
			local w = open(function(_x: number, _z: number, _refY: number): number
				return 0
			end)
			local s = SquirrelMotor.new(0, 0, 0)
			SquirrelMotor.place(s, 0, 140, 0, false)
			local v = SquirrelVisual.new()
			local inp = input(math.pi)
			local elapsed, i, landed, fastest = 0, 0, false, 0
			while elapsed < 4 do
				i += 1
				local dt = frameDt(pattern, i)
				elapsed += dt
				local lastY = v.y
				local _, events = SquirrelMotor.step(s, inp, dt, w)
				for _, e in events do
					landed = landed or e.kind == "land"
				end
				fastest = math.max(fastest, -s.vy)
				t.eq(SquirrelVisual.frame(v, s, w, dt), i == 1, `{pattern}: snap at frame {i}`)
				if i > 1 then
					t.truthy(v.y <= lastY + 1e-9, `{pattern}: the drawn point rises at frame {i}`)
				end
				t.truthy(v.y >= s.y - 1e-9 and v.y >= -1e-9, `{pattern}: the drawn point leads the fall`)
			end
			t.truthy(landed, `{pattern}: landed`)
			t.truthy(fastest > 100, `{pattern}: fell at {fastest} st/s`)
			t.eq(s.y, 0)
			t.near(v.y, 0, 1e-3, `{pattern}: settled`)
		end
	end)

	t.test("a sprint leap onto a platform: the drawn point never dips toward its foot after the landing", function()
		-- a platform H high from edgeX on; it is ground only to a body at its height (as a roof is)
		local function fly(pattern: string, H: number, edgeX: number): (number?, number, number, number)
			local function h(x: number, _z: number, refY: number): number
				return if x >= edgeX and refY + 1.5 >= H then H else 0
			end
			local w = open(h)
			local s = SquirrelMotor.new(0, 0, 0)
			s.yaw = math.pi / 2
			local v = SquirrelVisual.new()
			local inp = input(-math.pi / 2)
			inp.fw = 1
			inp.sprint = true
			local elapsed, i, landX, dip = 0, 0, nil :: number?, 0
			while elapsed < 3.2 do
				i += 1
				local dt = frameDt(pattern, i)
				elapsed += dt
				inp.leap = landX == nil and elapsed >= 1 and s.grounded
				local lastY = v.y
				local _, events = SquirrelMotor.step(s, inp, dt, w)
				for _, e in events do
					if e.kind == "land" and not landX then
						landX = s.x
					end
				end
				SquirrelVisual.frame(v, s, w, dt)
				if landX then
					dip = math.max(dip, math.min(lastY, H) - v.y)
				end
			end
			return landX, dip, s.y, v.y
		end
		local runs = 0
		for _, pattern in { "60", "144", "30", "uneven" } do
			for _, H in { 1.05, 1.9, 2.5 } do
				-- where the leap comes down to H with nothing in the way: put the edge just before it
				local free = fly(pattern, 0, math.huge)
				t.truthy(free ~= nil, `{pattern}: the leap lands`)
				for _, back in { 4, 6, 9 } do
					local landX, dip, sy, vy = fly(pattern, H, (free :: number) - back)
					if landX and sy == H then
						runs += 1
						t.truthy(dip < 1e-6, `{pattern} H {H} edge {back} st back: dips {dip} st after landing`)
						t.near(vy, H, 1e-3, `{pattern} H {H}: settled on the platform`)
					end
				end
			end
		end
		t.truthy(runs >= 24, `{runs} platform landings checked`)
	end)

	t.test(
		"Gait: the squirrel has no body bob; the climb pose reaches with the front and pushes with the back",
		function()
			local p = Gait.params("squirrel", 0.9)
			t.eq(p.bob, 0)
			t.near(p.rock, 0.022, 1e-12)
			t.near(p.stride, 5.5, 1e-12) -- one cycle per 2.2 u (2 pi / 2.85)
			local n = 360
			local front, back, maxRock, maxBob = 0, 0, 0, 0
			local fmin, fmax = math.huge, -math.huge
			for i = 0, n - 1 do
				local phase = 2 * math.pi * i / n
				local run = Gait.pose(phase, p.runSpeed, 0, p, 3)
				maxRock = math.max(maxRock, math.abs(run.rock))
				maxBob = math.max(maxBob, math.abs(run.bob))
				local climb = Gait.pose(phase, 10.8, 0, p, 3, 1)
				t.eq(climb.bob, 0)
				t.eq(climb.rock, 0)
				front += climb.legs.FrontL.upper / n
				back += climb.legs.BackL.upper / n
				fmin, fmax = math.min(fmin, climb.legs.FrontL.upper), math.max(fmax, climb.legs.FrontL.upper)
			end
			t.eq(maxBob, 0)
			t.truthy(maxRock <= 0.022 + 1e-9 and maxRock > 0.015, `rock {maxRock}`)
			t.near(front, 0.26, 1e-6)
			t.near(back, -0.22, 1e-6)
			t.truthy(fmax - fmin > 0.1 and fmax - fmin < 2 * p.swing * 0.5, `climb swing {fmax - fmin}`)
			-- a still squirrel on a trunk holds the grip pose
			local still = Gait.pose(1, 0, 0, p, 3, 1)
			t.near(still.legs.FrontR.upper, 0.26, 1e-12)
			t.near(still.legs.BackR.upper, -0.22, 1e-12)
		end
	)

	t.test("CameraRig.focusStep: eases, holds a bounded lag without a sawtooth, snaps only on a teleport", function()
		local F = CameraRig.FOCUS
		-- a fall at 60 st/s: the lag grows smoothly to the limit and stays there
		local px, py, pz = 0, 100, 0
		local ty = 100
		local lastLag = 0
		for _ = 1, 240 do
			ty -= 60 / 60
			px, py, pz = CameraRig.focusStep(px, py, pz, 0, ty, 0, 1 / 60)
			local lag = py - ty
			t.truthy(lag >= lastLag - 1e-9, "the vertical lag never jumps back")
			t.truthy(lag <= F.maxLagY + 1e-9)
			lastLag = lag
		end
		t.near(lastLag, F.maxLagY, 1e-9)
		-- a sprint at 42 st/s trails by about speed / rate; a 120 st/s ride is held at the limit
		for _, case in { { 42, 42 / F.rateXZ }, { 120, F.maxLagXZ } } do
			local speed, expect = case[1], case[2]
			local x, y, z = 0, 0, 0
			local tx = 0
			local prev = 0
			for _ = 1, 240 do
				tx += speed / 60
				x, y, z = CameraRig.focusStep(x, y, z, tx, 0, 0, 1 / 60)
				t.truthy(tx - x >= prev - 1e-9, "the horizontal lag never jumps back")
				prev = tx - x
			end
			t.truthy(math.abs(prev - expect) < expect * 0.2 + 1e-9, `lag {prev} at {speed} st/s`)
			t.eq(y, 0)
			t.eq(z, 0)
		end
		-- given the target's last position the lag is exactly speed / rate at any frame time: no
		-- sawtooth between long and short frames
		for _, pattern in { "60", "144", "30", "uneven" } do
			local x, tx = 0, 0
			local lo, hi = math.huge, -math.huge
			for i = 1, 600 do
				local dt = frameDt(pattern, i)
				local last = tx
				tx += 42 * dt
				x = CameraRig.focusStep(x, 0, 0, tx, 0, 0, dt, last, 0, 0)
				if i > 300 then
					lo, hi = math.min(lo, tx - x), math.max(hi, tx - x)
				end
			end
			t.near(lo, 42 / F.rateXZ, 1e-6, `{pattern}: focus lag`)
			t.near(hi, 42 / F.rateXZ, 1e-6, `{pattern}: focus lag`)
		end
		-- a small step is eased, not jumped
		local x1, y1 = CameraRig.focusStep(0, 0, 0, 0, 0.5, 0, 1 / 60)
		t.eq(x1, 0)
		t.near(y1, 0.5 * (1 - math.exp(-F.rateY / 60)), 1e-12)
		-- a teleport
		local sx, sy, sz = CameraRig.focusStep(0, 0, 0, 30, 5, 0, 1 / 60)
		t.eq(sx, 30)
		t.eq(sy, 5)
		t.eq(sz, 0)
	end)

	t.test("ClientWorld.groundLike: thin drawn plates are ground, bodies and glass are not", function()
		t.eq(ClientWorld.groundLike("Greybox", 0.2, 0), true)
		t.eq(ClientWorld.groundLike("Greybox_12", 0.25, 0), true)
		t.eq(ClientWorld.groundLike("Greybox", 3, 0), false)
		for _, name in { "Bank", "Tile_3", "Pad", "Seg_101" } do
			t.eq(ClientWorld.groundLike(name, 1, 0), true, name)
		end
		t.eq(ClientWorld.groundLike("Seg_101", 0.2, 0.5), false, "translucent")
		t.eq(ClientWorld.groundLike("Plinth", 0.2, 0), false)
		t.eq(ClientWorld.groundLike("Trunk", 0.2, 0), false)
		-- every tile the bake drapes over the terrain is ground, whatever its thickness; the invisible
		-- part that carries the lot is not
		local lots, tiles = 0, 0
		for _, p in Bake.plans(Bake.data()) do
			if p.kind == "lot" and p.attributes.GroundStyle == "draped" then
				lots += 1
				for _, part in p.parts do
					local drawn = (part.transparency or 0) < 1
					if string.sub(part.name, 1, 5) == "Tile_" then
						tiles += 1
						t.truthy(drawn, `{p.id} {part.name} is drawn`)
						t.eq(
							ClientWorld.groundLike(part.name, part.sy, part.transparency or 0),
							true,
							`{p.id} {part.name}`
						)
					elseif string.sub(part.name, 1, 7) == "Greybox" then
						-- a drawn Greybox thicker than a plate would be a floor the client cannot see
						t.eq(drawn, false, `{p.id} {part.name} is hidden`)
						t.eq(
							ClientWorld.groundLike(part.name, part.sy, part.transparency or 0),
							false,
							`{p.id} {part.name}`
						)
					end
				end
				t.eq(string.sub(p.parts[1].name, 1, 5) == "Tile_", false, `{p.id}: the first part is the hidden one`)
			end
		end
		t.truthy(lots >= 5 and tiles > lots, `{lots} draped lots, {tiles} tiles`)
	end)

	-- Owner 2026-11-10: the squirrel slower with sprint bursts that run out; people a slight bit faster,
	-- never out of the ability to run.
	t.test("sprint bursts are said and shown; a running person outpaces a walking squirrel", function()
		local idle = input(math.pi)
		t.eq(
			Squirrel.feedback(idle, { { kind = "winded" } }, false),
			"Out of breath: sprint comes back in a few seconds"
		)
		t.eq(Squirrel.feedback(idle, {}, false), nil)
		local full = Hud.meterLook(1, false)
		t.eq(full.scale, 1)
		t.eq(full.label, "SPRINT")
		local out = Hud.meterLook(0.2, true)
		t.eq(out.scale, 0.2)
		t.eq(out.label, "OUT OF BREATH")
		t.truthy(out.color[1] ~= full.color[1] or out.color[2] ~= full.color[2], "a different colour when winded")
		t.eq(Hud.meterLook(-3, false).scale, 0)
		t.eq(Hud.meterLook(7, false).scale, 1)
		-- the chase: a walking squirrel does not catch a running person, a sprinting one does
		local M = SquirrelMotor.params
		t.truthy(
			Human.SPRINT > M.walk and Human.SPRINT < M.sprint,
			`person {Human.SPRINT}, squirrel {M.walk}..{M.sprint}`
		)
		t.truthy(Human.WALK > 16 and Human.WALK <= 18, "a slight bit faster than 16")
		t.truthy(M.sprint < SquirrelMotor.V54.sprint and M.walk < SquirrelMotor.V54.walk, "slower than v5.4")
		-- one full burst gains less than 25 studs on a running person: not enough to run down a town
		t.truthy((M.sprint - Human.SPRINT) * M.sprintSeconds < 25)
	end)

	-- Owner 2026-11-10: "the squirrel catches and gets stuck on the crack between the sidewalk and grass".
	t.test("a kerb is a step, not a wall: the wall probe starts where the ground glue ends", function()
		local feet = 12.5
		local cy, r = ClientWorld.wallProbe(feet)
		t.near(cy - r - feet, SquirrelMotor.params.glueMin, 1e-9, "the probe's underside is one step up")
		t.eq(ClientWorld.STEP, SquirrelMotor.params.glueMin)
		t.truthy(cy + r - feet >= 1.4 and cy + r - feet <= 1.7, "and it reaches the top of the body")
		-- every sidewalk and paving lip in the town is under that step (0.4 st slabs, 0.3 st plates)
		local tallest = 0
		for _, p in Bake.plans(Bake.data()) do
			if p.kind == "road" then
				for _, part in p.parts do
					if string.sub(part.name, 1, 3) == "Seg" then
						tallest = math.max(tallest, part.sy)
					end
				end
			end
		end
		t.truthy(tallest > 0 and tallest < ClientWorld.STEP, `tallest road or sidewalk slab {tallest}`)
		-- the motor climbs a kerb it is not blocked by, and the drawn point follows without a cut
		local w = open(function(x: number, _z: number, _refY: number): number
			return if x >= 5 then 0.45 else 0
		end)
		local s = SquirrelMotor.new(0, 0, 0)
		local v = SquirrelVisual.new()
		local inp = input(-math.pi / 2) -- camera yaw -pi/2: forward = +x
		inp.fw = 1
		for i = 1, 90 do
			SquirrelMotor.step(s, inp, 1 / 60, w)
			local snapped = SquirrelVisual.frame(v, s, w, 1 / 60, w.groundAt)
			t.eq(snapped, i == 1)
		end
		t.truthy(s.x > 15, `ran on past the kerb to x = {s.x}`)
		t.eq(s.y, 0.45)
		t.eq(s.grounded, true)
	end)

	-- Owner 2026-11-10: "the squirrel turns too abruptly, make turning more smooth and agile".
	t.test("a quarter turn swings through in about a fifth of a second; the keys answer as fast as before", function()
		local w = open(function(_x: number, _z: number, _refY: number): number
			return 0
		end)
		local s = SquirrelMotor.new(0, 0, 0)
		local inp = input(math.pi) -- forward = +z
		inp.fw = 1
		for _ = 1, 60 do
			SquirrelMotor.step(s, inp, 1 / 60, w)
		end
		local yaw0 = s.yaw
		inp.fw, inp.side = 0, 1 -- now to the right of the camera
		local at50, at90, vel90 = nil, nil, nil
		local biggest = 0
		for i = 1, 60 do
			local before = s.yaw
			SquirrelMotor.step(s, inp, 1 / 60, w)
			biggest = math.max(biggest, math.abs(shortest(s.yaw - before)))
			local turned = math.abs(shortest(s.yaw - yaw0)) / (math.pi / 2)
			if at50 == nil and turned >= 0.5 then
				at50 = i / 60
			end
			if at90 == nil and turned >= 0.9 then
				at90 = i / 60
			end
			local speed = math.sqrt(s.vx * s.vx + s.vz * s.vz)
			if vel90 == nil and speed > 0 and math.abs(s.vx) / speed >= 0.9 then
				vel90 = i / 60
			end
		end
		t.truthy(at50 ~= nil and at50 >= 0.04 and at50 <= 0.09, `half the turn at {at50} s`)
		t.truthy(at90 ~= nil and at90 >= 0.14 and at90 <= 0.25, `90 % of the turn at {at90} s`)
		t.truthy(biggest < math.rad(20), `no frame turns more than 20 degrees (was 31): {math.deg(biggest)}`)
		t.truthy(vel90 ~= nil and vel90 <= 0.12, `the velocity follows the key in {vel90} s`)
		t.near(math.abs(shortest(s.yaw - yaw0)), math.pi / 2, 1e-3, "and the turn completes")
	end)

	t.test("place and movedFromOutside: the motor restarts at rest where the body was put", function()
		local trunk = world.registry:get(220) :: Registry.Route
		local foot = world.registry:foot(trunk)
		local s = SquirrelMotor.new(foot.x, world.groundHeight, foot.z - st(1.2))
		local inp = input(math.pi)
		inp.grab = true
		SquirrelMotor.step(s, inp, 1 / 60, world)
		inp.grab = false
		inp.fw = 1
		for _ = 1, 30 do
			SquirrelMotor.step(s, inp, 1 / 60, world)
		end
		t.eq(s.routeId, 220)
		t.truthy(s.moveSpeed > 0, "climbing")
		local yaw = s.yaw
		SquirrelMotor.place(s, 40, 3, -12, true)
		t.eq(s.x, 40)
		t.eq(s.y, 3)
		t.eq(s.z, -12)
		t.eq(s.routeId, nil)
		t.eq(s.bridge, nil)
		t.eq(s.pendingFork, nil)
		t.eq(s.grounded, true)
		t.eq(s.moveSpeed, 0)
		t.eq(s.vx * s.vx + s.vy * s.vy + s.vz * s.vz, 0)
		t.eq(s.yaw, yaw, "the heading is kept")
		-- and it runs on from there over the ground it was put on
		local w = open(function(_x: number, _z: number, _refY: number): number
			return 3
		end)
		local v = SquirrelVisual.new()
		for i = 1, 60 do
			SquirrelMotor.step(s, inp, 1 / 60, w)
			t.eq(SquirrelVisual.frame(v, s, w, 1 / 60), i == 1)
		end
		t.eq(s.grounded, true)
		t.eq(s.y, 3)
		t.truthy(s.z > -12 + 5, "runs on")
		-- placed in the air it falls
		SquirrelMotor.place(s, 0, 30, 0, false)
		SquirrelMotor.step(s, input(math.pi), 1 / 60, w)
		t.eq(s.grounded, false)
		t.truthy(s.y < 30 and s.vy < 0, "falling")
		-- the body is where the driver wrote it, carried by its own velocity: only a larger gap is a move
		-- made from outside (a server recovery, a reset)
		t.eq(Squirrel.movedFromOutside(0, 0, 1 / 60), false)
		t.eq(Squirrel.movedFromOutside(1.4, 42, 1 / 60), false, "one sprint frame")
		t.eq(Squirrel.movedFromOutside(42 * 0.07, 42, 0.07), false, "a hitch at a sprint")
		t.eq(Squirrel.movedFromOutside(145 / 30, 145, 1 / 30), false, "a long fall at 30 Hz")
		t.eq(Squirrel.movedFromOutside(Squirrel.OUTSIDE_SLACK + 0.1, 0, 1 / 60), true, "a still body moved")
		t.eq(Squirrel.movedFromOutside(12, 42, 1 / 60), true, "a recovery while sprinting")
	end)
end
