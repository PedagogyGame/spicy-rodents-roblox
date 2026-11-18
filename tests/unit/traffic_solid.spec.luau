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
end
