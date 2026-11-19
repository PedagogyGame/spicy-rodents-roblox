--!strict
-- Cars are solid (owner's playtest 2026-11-18: "I did run right through a car"): Shared/Traffic/Solid's boxes, the
-- ghost's collision (Traffic/Ghost.solidify) and a person's body against it (tests/lib/HumanWalk: an R15 Humanoid's
-- 2 x 5.2, stepping 0.75, jumping 7.2, on the ghost as built by Ghost's own code, tests/lib/BakedWorld).
local roblox = require("@lune/roblox")
local Boxes = require("@shared/Traffic/Boxes")
local Ghost = require("@shared/Traffic/Ghost")
local PartBuilder = require("@shared/Avatar/PartBuilder")
local Solid = require("@shared/Traffic/Solid")
local VehiclePuppet = require("@shared/Traffic/VehiclePuppet")
local Height = require("@shared/World/Height")
local ClientWorld = require("@client/World/ClientWorld")
local BakedWorld = require("../lib/BakedWorld")
local HumanWalk = require("../lib/HumanWalk")
local Data = require("@shared/Data")
local TrafficService = require("@server/Traffic/TrafficService")
local CarMotor = require("@shared/Movement/CarMotor")
local VehicleKinds = require("@shared/Vehicles/VehicleKinds")
local Vehicle = require("@client/Controllers/Vehicle")

local lib = {
	Instance = roblox.Instance,
	Vector3 = roblox.Vector3,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	Enum = roblox.Enum,
}

-- a ghost of `kind` drawn at (x, z) heading `yaw` on the town's terrain, as Ghost.render builds and places it
local function ghost(kind: string, x: number, z: number, yaw: number, solidify: boolean): (any, number)
	local base, pitch, roll = Ghost.seat(x, z, yaw, VehiclePuppet.length(kind), Height.at, VehiclePuppet.track(kind))
	local at = Ghost.rootCFrame(lib, x, base + VehiclePuppet.baseOffset(kind), z, yaw, pitch, true, roll)
	local model = PartBuilder.instantiate(VehiclePuppet.spec(kind, { name = "Ghost_1" }), lib, at)
	if solidify then
		Ghost.solidify(model)
	end
	local folder = roblox.Instance.new("Model")
	folder.Name = "TrafficGhosts"
	model.Parent = folder
	return folder, base
end

return function(t)
	t.test("Solid.BODY is the squirrel's body as Client/World/ClientWorld measures it", function()
		t.eq(Solid.BODY.STEP, ClientWorld.STEP)
		t.eq(Solid.BODY.TOP, ClientWorld.BODY_TOP)
		t.eq(Solid.BODY.HALF, ClientWorld.BODY_HALF)
		t.eq(Solid.BODY.CORE, ClientWorld.PROBE_RADIUS)
		t.eq(Solid.BODY.RAY_ABOVE, BakedWorld.RAY_ABOVE)
	end)

	t.test("Solid: a box is the kind's logical box, turned to its heading (HTML yaw: it faces (sin, cos))", function()
		local b = Boxes.get("sedan")
		for _, yaw in { 0, 0.4, math.pi / 2, 2.5, -1.1 } do
			local h = Solid.hull("sedan", 10, 2, -4, yaw)
			local fx, fz = math.sin(yaw), math.cos(yaw)
			local rx, rz = math.cos(yaw), -math.sin(yaw) -- across
			t.truthy(Solid.inside(h, 10 + fx * (b.length / 2 - 0.05), -4 + fz * (b.length / 2 - 0.05)), "nose in")
			t.falsy(Solid.inside(h, 10 + fx * (b.length / 2 + 0.05), -4 + fz * (b.length / 2 + 0.05)), "past the nose")
			t.truthy(Solid.inside(h, 10 + rx * (b.width / 2 - 0.05), -4 + rz * (b.width / 2 - 0.05)), "side in")
			t.falsy(Solid.inside(h, 10 + rx * (b.width / 2 + 0.05), -4 + rz * (b.width / 2 + 0.05)), "past the side")
			t.near(h.top - h.base, b.height, 1e-9)
		end
		-- a trail stretches it behind, never ahead
		local h = Solid.hull("sedan", 0, 0, 0, 0, 10)
		t.truthy(Solid.inside(h, 0, -b.length / 2 - 9.9))
		t.falsy(Solid.inside(h, 0, b.length / 2 + 0.1))
	end)

	t.test("Solid.overlaps agrees with a dense point test (square bodies against turned boxes)", function()
		local seed = 7
		local function rnd(): number
			seed = (seed * 1103515245 + 12345) % 2147483648
			return seed / 2147483648
		end
		local disagree = 0
		for _ = 1, 400 do
			local yaw = rnd() * 6.3 - 3.15
			local h = Solid.hull("delivery_van", 0, 0, 0, yaw)
			local x, z, half = rnd() * 20 - 10, rnd() * 20 - 10, 0.2 + rnd() * 1.2
			local fast = Solid.overlaps(h, x, z, half, 0.5, 1.5)
			local dense = false
			for i = 0, 20 do
				for j = 0, 20 do
					if Solid.inside(h, x - half + 2 * half * i / 20, z - half + 2 * half * j / 20) then
						dense = true
					end
				end
			end
			if fast ~= dense then
				disagree += 1
			end
		end
		-- the dense test samples, so a graze can differ: never more than a handful in 400
		t.truthy(disagree <= 4, `disagreements {disagree}`)
		-- heights: below the box and above its roof never overlap
		local h = Solid.hull("sedan", 0, 3, 0, 0)
		t.falsy(Solid.overlaps(h, 0, 0, 1, 0, 3))
		t.falsy(Solid.overlaps(h, 0, 0, 1, h.top, h.top + 2))
		t.truthy(Solid.overlaps(h, 0, 0, 1, h.top - 0.1, h.top + 2))
	end)

	t.test(
		"Solid.enters: a segment meets the box where it goes in; one that starts inside does not (as a raycast)",
		function()
			local h = Solid.hull("sedan", 0, 0, 0, 0) -- across x, along z
			local hw = Boxes.get("sedan").width / 2
			local tHit = Solid.enters(h, -10, 1, 0, 20, 0, 0)
			t.truthy(tHit ~= nil)
			t.near(tHit :: number, (10 - hw) / 20, 1e-9)
			t.eq(Solid.enters(h, 0, 1, 0, 20, 0, 0), nil, "starts inside")
			t.eq(Solid.enters(h, -10, 1, 0, 5, 0, 0), nil, "stops short")
			t.eq(Solid.enters(h, -10, h.top + 0.1, 0, 20, 0, 0), nil, "over the roof")
			local down = Solid.enters(h, 0, h.top + 1.5, 0, 0, -5, 0)
			t.truthy(down ~= nil, "a ray down meets the roof")
			-- a set: the quick reject never drops a hit
			local set = Solid.newSet()
			Solid.add(set, h)
			Solid.add(set, Solid.hull("trolley", 40, 0, 0, 1))
			t.truthy(Solid.ray(set, -10, 1, 0, 20, 0, 0))
			t.truthy(Solid.ray(set, 40, 1, -20, 0, 0, 40))
			t.falsy(Solid.ray(set, 20, 1, -20, 0, 0, 40))
			Solid.clear(set)
			t.falsy(Solid.ray(set, -10, 1, 0, 20, 0, 0), "cleared")
		end
	)

	t.test("Solid.roof: the highest roof a ray down from `from` meets; none when it starts inside", function()
		local set = Solid.newSet()
		local h = Solid.hull("sedan", 0, 0, 0, 0)
		Solid.add(set, h)
		t.eq(Solid.roof(set, 0, 0, h.top + 1), h.top)
		t.eq(Solid.roof(set, 0, 0, h.top - 1), nil, "from inside the box")
		t.eq(Solid.roof(set, 5, 0, h.top + 1), nil, "beside it")
	end)

	t.test(
		"Ghost.solidify: only the invisible RootPart (the logical box) collides; the drawn parts never do",
		function()
			for _, kind in VehiclePuppet.KINDS do
				local folder = ghost(kind, 0, 0, 0, true)
				local model = folder:GetChildren()[1]
				local roots, drawn = 0, 0
				for _, d in model:GetDescendants() do
					if d:IsA("BasePart") then
						if d == model.PrimaryPart then
							roots += 1
							t.truthy(d.CanCollide and d.CanQuery and not d.CanTouch and d.Anchored, kind)
							t.eq(d.Transparency, 1, kind)
							local b = Boxes.get(kind)
							t.near(d.Size.X, b.width, 1e-4, kind)
							t.near(d.Size.Y, b.height, 1e-4, kind)
							t.near(d.Size.Z, b.length, 1e-4, kind)
						else
							drawn += 1
							t.truthy(not d.CanCollide and not d.CanQuery and not d.CanTouch, `{kind} {d.Name}`)
						end
					end
				end
				t.eq(roots, 1, kind)
				t.truthy(drawn > 5, kind)
			end
		end
	)

	-- a person walking at a car: the cells round it, the footprint's at road level never reached
	local function personAt(kind: string, yaw: number, solidify: boolean): (any, number, number, number)
		local cx, cz = 30, 40
		local folder, base = ghost(kind, cx, cz, yaw, solidify)
		local world = BakedWorld.fromModel(folder)
		local reach = HumanWalk.fill(world, { cx - 19, Height.at(cx - 19, cz), cz }, {
			x0 = cx - 20,
			x1 = cx + 20,
			z0 = cz - 20,
			z1 = cz + 20,
			cell = 0.5,
		})
		local h = Solid.hull(kind, cx, base, cz, yaw)
		-- cells whose centre is inside the footprint and reached at road level
		local inside, far = 0, 0
		for _, s in reach.states do
			if Solid.inside(h, s[1], s[3]) and s[2] < base + 1 then
				inside += 1
			end
			if s[1] > cx + 16 then
				far += 1
			end
		end
		return reach, inside, far, base
	end

	t.test("a person walks into a stopped car, not through it (and before the fix walked straight through)", function()
		for _, case in { { "sedan", 0 }, { "sedan", 0.7 }, { "trolley", math.pi / 2 }, { "motorcycle", 0.3 } } do
			local _, inside, far = personAt(case[1], case[2], true)
			t.eq(inside, 0, `{case[1]}: a person stood inside the car`)
			t.truthy(far > 0, `{case[1]}: a person still walks round it`)
			local _, through = personAt(case[1], case[2], false)
			t.truthy(through > 0, `{case[1]}: without the solid root the person walked through (the bug)`)
		end
	end)

	-- a person's body as Render/VehicleView gives it (an R15 root 2 x 2 x 1 at hip 2: its centre column, the feet up)
	local function personBody(x: number, z: number, feet: number): Ghost.Body
		return { x = x, z = z, half = 0.4, y0 = feet, y1 = feet + 2 + 2 }
	end

	t.test("Ghost.solidFor: a near-still car is a wall, a moving one or one already over the body is not", function()
		local function pose(speed: number, visible: boolean?): Ghost.Pose
			return {
				id = 1,
				x = 0,
				z = 0,
				yaw = 0,
				speed = speed,
				visible = visible ~= false,
				beacons = false,
				teleported = false,
				stopped = speed == 0,
			}
		end
		local sedan = Boxes.get("sedan")
		local h = Solid.hull("sedan", 0, 0, 0, 0)
		local away = personBody(10, 0, 0)
		t.truthy(Ghost.solidFor(pose(0), h, away), "parked")
		t.truthy(Ghost.solidFor(pose(0.5), h, away), "creeping")
		t.truthy(Ghost.solidFor(pose(0), h, nil), "no body")
		t.falsy(Ghost.solidFor(pose(1.0), h, away), "moving at 1 st/s")
		t.falsy(Ghost.solidFor(pose(20), h, away), "driving")
		t.falsy(Ghost.solidFor(pose(0, false), h, away), "hidden")
		t.falsy(Ghost.solidFor(pose(0), h, personBody(0, 0, 0)), "over the body")
		t.falsy(Ghost.solidFor(pose(0), h, personBody(sedan.width / 2 - 0.2, 0, 0)), "just over the body's edge")
		-- pressed on its side (the root's centre half its depth out) or standing on its roof: a wall
		t.truthy(Ghost.solidFor(pose(0), h, personBody(sedan.width / 2 + 0.5, 0, 0)), "pressed on the side")
		t.truthy(Ghost.solidFor(pose(0), h, personBody(0, 0, h.top)), "on the roof")
	end)

	-- one client frame after another: the pose stream through a real Ghost buffer (60 Hz frames, 20 Hz sends), the car
	-- drawn as Ghost.view gives it. Returns the frames a colliding root overlapped the body (a squeeze), the frames it
	-- moved more than a creep since the last frame (a shove), whether it was a wall at the end, and its wall frames
	local function replay(
		kind: string,
		serverAt: (t: number) -> (number, number, boolean?), -- z, speed, teleported
		bodyAt: (t: number) -> Ghost.Body,
		seconds: number
	): (number, number, boolean, number)
		local buffer = Ghost.new()
		local kinds = { [1] = { kind = kind } }
		local flat = function(_x: number, _z: number): number
			return 0
		end
		local sendT = 0
		local squeezed, shoved, solid, solidFrames = 0, 0, false, 0
		local lastZ: number? = nil
		local frame = 1 / 60
		local tt = 0
		while tt < seconds do
			while sendT <= tt do
				local z, speed, teleported = serverAt(sendT)
				buffer:push(sendT, {
					Ghost.encode({
						id = 1,
						x = 0,
						z = z,
						yaw = 0,
						speed = speed,
						visible = true,
						beacons = false,
						teleported = teleported == true,
						stopped = speed == 0,
					}),
				})
				sendT += 0.05
			end
			local body = bodyAt(tt)
			Ghost.view(buffer, tt, kinds, flat, function(_id, p, k, x, y, z, yaw)
				local hull = Solid.hull(k.kind, x, y - VehiclePuppet.baseOffset(k.kind), z, yaw)
				solid = Ghost.solidFor(p, hull, body)
				if solid then
					solidFrames += 1
					if Solid.overlaps(hull, body.x, body.z, body.half, body.y0, body.y1) then
						squeezed += 1
					end
					if lastZ and math.abs(z - lastZ) > Ghost.STILL_SPEED * frame + 1e-3 then
						shoved += 1
					end
				end
				lastZ = z
			end)
			tt += frame
		end
		return squeezed, shoved, solid, solidFrames
	end

	t.test("a person in a car's way: a colliding root never moves into the body nor starts over it", function()
		local sedan = Boxes.get("sedan")
		local function standing(x: number, z: number): (t: number) -> Ghost.Body
			return function(_t: number): Ghost.Body
				return personBody(x, z, 0)
			end
		end
		-- the ambulance's incident edge (AICarMotor: 5 st/s after 4 s waiting) crawls through a person standing in it
		local sq, sh, _, n = replay("ambulance", function(s: number)
			return -20 + 5 * s, 5
		end, standing(0, 0), 8)
		t.eq(sq + sh, 0, `ambulance edging through: {sq} squeezed, {sh} shoved`)
		t.eq(n, 0, "a moving car is never a wall")
		-- a sedan at 20 st/s the server stopped short of the person: drawn late, it brakes hard to a stop on them
		sq, sh = replay("sedan", function(s: number)
			if s < 1 then
				return -30 + 20 * s, 20
			end
			local u = math.min(s - 1, 0.5)
			return -10 + 20 * u - 20 * u * u, math.max(20 - 40 * u, 0)
		end, standing(0, -5 + sedan.length / 2 - 0.5), 4)
		t.eq(sq + sh, 0, `braking hard onto the person: {sq} squeezed, {sh} shoved`)
		-- a car that appears (a dispatch, a wrap) on the person: no wall until they step out sideways, then a wall
		local walkOut = function(s: number): Ghost.Body
			local x = if s < 1 then 0 else math.min((s - 1) * 7, sedan.width / 2 + 0.5)
			return personBody(x, 0, 0)
		end
		local solid
		sq, sh, solid = replay("sedan", function(_t: number)
			return 0, 0, true
		end, walkOut, 3)
		t.eq(sq + sh, 0, `appeared over the person: {sq} squeezed, {sh} shoved`)
		t.truthy(solid, "once out, pressed on its side, the car is a wall again")
		-- a parked car the person walks up to: a wall all the time
		local _, _, parkedSolid, frames = replay("sedan", function(_t: number)
			return 0, 0
		end, standing(sedan.width / 2 + 0.5, 0), 2)
		t.truthy(parkedSolid and frames >= 110, `parked: a wall ({frames} frames)`)
	end)

	t.test("a player's car: its nose stops at a town car's side, and a town car over it never locks it in", function()
		-- review 2026-11-18 (car_stuck): Controllers/Vehicle's wall test on the real CarMotor, flat ground, no walls
		local cars = Solid.newSet()
		local function world(state: CarMotor.State): CarMotor.World
			return {
				groundAt = function(_x: number, _z: number, _refY: number): number
					return 0
				end,
				blocked = Vehicle.blocked(
					state,
					cars,
					function(_x: number, _z: number, _y: number, _r: number): boolean
						return false
					end
				),
			}
		end
		local function drive(s: CarMotor.State, throttle: number, steer: number, seconds: number)
			local w = world(s)
			for _ = 1, math.floor(seconds * 60) do
				CarMotor.step(s, { throttle = throttle, steer = steer, handbrake = false }, 1 / 60, w)
			end
		end
		local size = VehicleKinds.kind("car").size
		local y = CarMotor.new("car", 0, 3, 0, 0).y
		-- driving at a town sedan's side (it crosses, heading +x, its near side 6 studs ahead of the player's nose)
		local sedan = Boxes.get("sedan")
		local side = size[3] / 2 + 6 -- the town car's near side, z
		Solid.add(cars, Solid.hull("sedan", 0, 0, side + sedan.width / 2, math.pi / 2))
		local s = CarMotor.new("car", 0, y, 0, 0)
		drive(s, 1, 0, 5)
		local nose = s.z + size[3] / 2
		print(`      driving at a town car's side: the nose stops {string.format("%.2f", side - nose)} short of it`)
		t.truthy(nose <= side + 0.05, `the nose stops at the side (overlap {nose - side})`)
		t.truthy(nose > side - 1.5, `and close to it (gap {side - nose})`)
		-- a town sedan drawn over the player's car (its side 1.5 into the car's middle): it backs out (straight or
		-- steering); driving on into the sedan's middle stays refused (it would go deeper); never deeper either way
		for _, c in
			{
				{ "reverse", -1, 0, true },
				{ "reverse + steer", -1, 1, true },
				{ "forward", 1, 0, false },
				{ "forward + steer", 1, -1, false },
			}
		do
			Solid.clear(cars)
			local over = Solid.hull("sedan", 0, 0, sedan.width / 2 - 1.5, math.pi / 2)
			Solid.add(cars, over)
			local car = CarMotor.new("car", 0, y, 0, 0)
			local before = Solid.depth(Solid.box(size[1], size[3], 1, car.x, car.y - 0.5, car.z, car.yaw), over)
			-- (1.5 s: at full lock for longer it circles round and backs into the sedan again, a wall like any other)
			drive(car, c[2], c[3], 1.5)
			local moved = math.sqrt(car.x * car.x + car.z * car.z)
			local after = Solid.depth(Solid.box(size[1], size[3], 1, car.x, car.y - 0.5, car.z, car.yaw), over)
			print(
				`      {c[1]}: moved {string.format("%.1f", moved)} studs, overlap {string.format(
					"%.2f -> %.2f",
					before,
					after
				)}`
			)
			if c[4] then
				t.truthy(moved > 3 and after == 0, `{c[1]}: drives out (moved {moved}, overlap {after})`)
			end
			-- (CarMotor turns the heading even on a refused move, at any wall: a few hundredths of a turn in place)
			t.truthy(after <= before + 0.25, `{c[1]}: never deeper ({before} -> {after})`)
			t.truthy(c[4] or moved < 0.5, `{c[1]}: not driven through the sedan (moved {moved})`)
		end
	end)

	t.test("Solid.depth agrees with a dense point test (two turned boxes)", function()
		local seed = 5
		local function rnd(): number
			seed = (seed * 1103515245 + 12345) % 2147483648
			return seed / 2147483648
		end
		for _ = 1, 300 do
			local a = Solid.box(2 + rnd() * 4, 3 + rnd() * 8, 2, 0, 0, 0, rnd() * 6.28)
			local b =
				Solid.box(2 + rnd() * 4, 3 + rnd() * 8, 2, (rnd() - 0.5) * 14, 0, (rnd() - 0.5) * 14, rnd() * 6.28)
			-- a point of either footprint inside the other: they overlap
			local function meets(p: Solid.Hull, q: Solid.Hull): boolean
				for i = -30, 30 do
					for j = -30, 30 do
						local u, v = i / 30 * p.hw * 0.999, j / 30 * p.hl * 0.999
						-- across (c, -s), along (s, c)
						if Solid.inside(q, p.x + u * p.c + v * p.s, p.z - u * p.s + v * p.c) then
							return true
						end
					end
				end
				return false
			end
			local hit = meets(a, b) or meets(b, a)
			local d = Solid.depth(a, b)
			t.near(d, Solid.depth(b, a), 1e-9, "symmetric")
			if hit then
				t.truthy(d > 0, "overlapping boxes have a depth")
			elseif d > 0.05 then
				t.truthy(false, `apart boxes have no depth ({d})`)
			end
		end
		-- heights apart: none; side by side, half a stud into each other: 0.5
		t.eq(Solid.depth(Solid.box(2, 4, 1, 0, 0, 0, 0), Solid.box(2, 4, 1, 0, 1, 0, 0)), 0)
		t.near(Solid.depth(Solid.box(2, 4, 1, 0, 0, 0, 0), Solid.box(2, 4, 1, 1.5, 0, 0, 0)), 0.5, 1e-9)
	end)

	t.test(
		"TrafficService.solids: walls are the cars stood still SETTLE s, floors every visible car (the live fleet)",
		function()
			local data = Data.default()
			local traffic =
				TrafficService.new({ lanes = data:lanes(), roads = data:roads(), heightAt = Height.at, seed = 7 })
			local solids = traffic:solids()
			local still: { [number]: number } = {}
			local sawWall, sawMovingWall = 0, 0
			for _ = 1, 30 * 20 do
				traffic:step(1 / 30)
				local visible = 0
				for _, v in traffic.vehicles do
					if v.visible then
						visible += 1
					end
					still[v.id] = if v.visible and v.speed < TrafficService.STILL_SPEED
						then (still[v.id] or 0) + 1 / 30
						else 0
				end
				t.eq(solids.floors.n, visible, "a floor for every visible car")
				sawWall = math.max(sawWall, solids.walls.n)
				-- every wall is a car that has stood still SETTLE seconds (counted here as well)
				for i = 1, solids.walls.n do
					local h = solids.walls.hulls[i]
					local found = false
					for _, v in traffic.vehicles do
						if math.abs(v.x - h.x) < 1e-6 and math.abs(v.z - h.z) < 1e-6 then
							found = true
							if
								(still[v.id] or 0) < TrafficService.SETTLE - 2 / 30
								or v.speed >= TrafficService.STILL_SPEED
							then
								sawMovingWall += 1
							end
						end
					end
					t.truthy(found, "a wall is a car")
				end
			end
			print(
				`      most walls at once: {sawWall} (the parked emergency vehicles, riders at the kerb, cars at stop lines)`
			)
			t.truthy(sawWall >= 3, "the parked emergency vehicles are walls")
			t.eq(sawMovingWall, 0, "never a moving car")
		end
	)
end
