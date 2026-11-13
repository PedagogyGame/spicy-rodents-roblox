--!strict
-- tests/lib/BakedWorld: the baked-building harness the enclosed runs are held to. Its solids are exact (a ball is a
-- ball, a wedge slopes the way Roblox draws it, a 0.08-stud plank is found), its ground and walls are the client's
-- (Client/World/ClientWorld), the clearance sweep reports what a body passes through, and on the bowling alley
-- baked in memory it reproduces, number for number, what the run-through survey measured by hand on
-- build/Attractions.rbxm with the ball return as it was declared before the enclosed-run contract (a "trunk" vent and
-- a "bridge" tunnel): the walk-in grab pulls the squirrel 5 studs onto the vent at 0.32 s, the run reaches the rack
-- at 5.42 s, and the body passes through the kickback board for 15.5 studs.
local roblox = require("@lune/roblox")
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local Registry = require("@shared/Routes/Registry")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local BakedWorld = require("@tests/lib/BakedWorld")

local function part(model: any, name: string, class: string, size: any, cf: any, props: { [string]: any }?): any
	local p = roblox.Instance.new(class)
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.CanCollide = true
	p.Transparency = 0
	for k, v in props or {} do
		p[k] = v
	end
	p.Parent = model
	return p
end

-- the ball return as data/attractions.json declared it before the enclosed-run contract (pair 2)
local function legacy(place: AlleyLayout.Place): { Registry.RouteRecord }
	local flags = { autoGrabExcluded = false, isPole = false, isGiant = false, treeTravel = false }
	local vent = BakedWorld.alleyRecord(place, {
		id = 9003,
		name = "legacy vent",
		kind = "trunk",
		surfaceRadius = 0.1,
		flags = table.clone(flags),
		points = { { 0, -3.48, 83.4 }, { 0, -3.47, 82.2 }, { 0, -3.38, 81.2 }, { 0, -3.12, 80.2 }, { 0, -2.98, 79.2 } },
	});
	(vent.flags :: any).fixedSurfaceZ = true
	local tunnel = BakedWorld.alleyRecord(place, {
		id = 9004,
		name = "legacy tunnel",
		kind = "bridge",
		surfaceRadius = 0.6,
		visualOffset = 0,
		flags = table.clone(flags),
		points = {
			{ 0, -2.98, 79.2 },
			{ 0, -2.98, 74.0 },
			{ 0, -2.98, 66.0 },
			{ 0, -2.98, 58.0 },
			{ 0, -2.98, 46.0 },
			{ 0, -2.98, 34.0 },
			{ 0, -2.98, 22.0 },
			{ 0, -2.98, 10.0 },
			{ 0, -2.98, 1.2 },
			{ 0, -2.9, -0.7 },
			{ 0, -2.3, -1.55 },
			{ 0, -1.0, -1.75 },
			{ 0, 0.4, -1.8 },
			{ 0, 1.3, -2.3 },
			{ 0, 1.6, -3.3 },
			{ 0, 1.58, -4.2 },
			{ 0, 1.55, -4.8 },
		},
	});
	(tunnel.flags :: any).fixedSurfaceZ = false
	return { vent, tunnel }
end

return function(t)
	t.test("solids are exact: a ball, a wedge's slope, a cylinder, a thin plank; rays and containment", function()
		local m = roblox.Instance.new("Model")
		local CF = roblox.CFrame
		local V = roblox.Vector3
		local ball = part(m, "B", "Part", V.new(2, 2, 2), CF.new(0, 0, 0), { Shape = roblox.Enum.PartType.Ball })
		local _ = ball
		part(m, "W", "WedgePart", V.new(2, 2, 2), CF.new(10, 0, 0))
		part(m, "C", "Part", V.new(4, 2, 2), CF.new(20, 0, 0), { Shape = roblox.Enum.PartType.Cylinder })
		part(m, "P", "Part", V.new(4, 0.08, 4), CF.new(30, 0, 0))
		part(m, "G", "Part", V.new(4, 4, 4), CF.new(40, 0, 0), { CanCollide = false, Transparency = 1 })
		local w = BakedWorld.fromModel(m)
		t.eq(#w.parts, 5)
		local function names(list: { BakedWorld.Part }): string
			local out = {}
			for _, p in list do
				table.insert(out, p.name)
			end
			table.sort(out)
			return table.concat(out, ",")
		end
		-- the ball's bounding-box corner is outside the ball
		t.eq(names(w.containing(0.9, 0.9, 0.9)), "")
		t.eq(names(w.containing(0.5, 0.5, 0.5)), "B")
		-- the wedge: solid at the back top (+Z, +Y), empty at the front top
		t.eq(names(w.containing(10, 0.8, 0.9)), "W")
		t.eq(names(w.containing(10, 0.8, -0.9)), "")
		t.eq(names(w.containing(10, -0.9, -0.8)), "W")
		-- the cylinder lies along X, radius 1
		t.eq(names(w.containing(21.5, 0, 0.9)), "C")
		t.eq(names(w.containing(20, 0.9, 0.9)), "")
		-- a ray down onto the ball meets it at y = 1; onto the plank at its top
		local tb = w.raycast(0, 5, 0, 0, -10, 0)
		t.near(tb :: number, 0.4, 1e-6)
		local tp, hit = w.raycast(30, 5, 0, 0, -10, 0)
		t.near(5 - 10 * (tp :: number), 0.04, 1e-6)
		t.eq((hit :: BakedWorld.Part).name, "P")
		-- a box sliding over the plank finds it; one just above does not
		local axes = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }
		t.eq(names(w.overlapBox(30, 0.5, 0, axes, { 0.5, 0.48, 0.5 })), "P")
		t.eq(names(w.overlapBox(30, 0.6, 0, axes, { 0.5, 0.5, 0.5 })), "")
		-- an invisible non-colliding part is no ground and no wall
		t.eq(w.blocked(40, 0, -1), false)
	end)

	t.test("walls as the client sees them: a tree's bough cylinders are looked past, its trunk is round", function()
		local m = roblox.Instance.new("Model")
		local V, CF = roblox.Vector3, roblox.CFrame
		local tree = roblox.Instance.new("Model")
		tree.Name = "Tree_7"
		tree.Parent = m
		-- a trunk 8 across standing up (a cylinder's axis is its X), and a bough cylinder at body height beside it
		part(tree, "Trunk_1", "Part", V.new(20, 8, 8), CF.new(0, 10, 0) * CF.Angles(0, 0, math.pi / 2), {
			Shape = roblox.Enum.PartType.Cylinder,
		})
		part(tree, "R12_1", "Part", V.new(10, 1, 1), CF.new(12, 1, 0), { Shape = roblox.Enum.PartType.Cylinder })
		-- the same bough shape outside a tree is a wall
		part(m, "Pipe", "Part", V.new(10, 1, 1), CF.new(12, 1, 30), { Shape = roblox.Enum.PartType.Cylinder })
		local w = BakedWorld.fromModel(m)
		t.eq(w.blocked(12, 0, 0), false, "the bough cylinder is looked past")
		t.eq(w.blocked(12, 30, 0), true, "a cylinder that is not a tree's bough is a wall")
		-- by the trunk's round section from the probe's centre (radius 4 + the probe 0.35), not by its 8 x 8 box
		t.eq(w.blocked(3.2, 3.2, 0), false, "at the box's corner, 4.5 from the axis")
		t.eq(w.blocked(3.0, 0, 0), true, "into the bark")
	end)

	t.test("clearance: a body swept along a line reports what it passes through, and where", function()
		local m = roblox.Instance.new("Model")
		local V, CF = roblox.Vector3, roblox.CFrame
		-- a duct 1.8 high along +Z with a board hanging into it over 2 studs, and a floor rail under the feet
		part(m, "Floor", "Part", V.new(3, 1, 20), CF.new(0, -0.5, 10))
		part(m, "Roof", "Part", V.new(3, 0.2, 20), CF.new(0, 1.9, 10))
		part(m, "Board", "Part", V.new(0.1, 1, 2), CF.new(0, 1.3, 8))
		part(m, "Rail", "Part", V.new(0.08, 0.14, 20), CF.new(0.24, 0.07, 10), { CanCollide = false })
		local w = BakedWorld.fromModel(m)
		local reg = Registry.fromRecords({
			{
				id = 1,
				name = "line",
				kind = "bridge",
				points = { { 0, 0, 1 }, { 0, 0, 19 } },
				length = 18,
				surfaceRadius = 0,
			},
		})
		local route = reg:get(1) :: Registry.Route
		local hits = BakedWorld.clearance(w, reg, route)
		t.eq(#hits, 1, "only the board (the rail lies under the feet, the roof above the body)")
		t.eq(hits[1].name, "Board")
		t.near(hits[1].studs, 2.2, 0.21)
		-- the board spans z 7..9 of a line from z 1 to z 19: 6 to 8 studs along it (to a slice)
		t.truthy(
			math.abs(hits[1].t0 * 18 - 6) <= 0.15 and math.abs(hits[1].t1 * 18 - 8) <= 0.15,
			`board from {hits[1].t0 * 18} to {hits[1].t1 * 18} studs along`
		)
		-- a taller body meets the roof too
		local tall = BakedWorld.clearance(w, reg, route, { height = 2.0 })
		t.eq(#tall, 2)
	end)

	t.test("the alley baked in memory: ground, walls and the duct as the client sees them", function()
		local w, place = BakedWorld.bakeAlley()
		t.truthy(#w.parts > 2000, `{#w.parts} parts`)
		t.truthy(#w.carves >= 3, "terrain carve boxes")
		local function ground(X: number, D: number, refY: number): number
			local x, _, z = AlleyLayout.toWorld(place, X, 0, D)
			return w.groundAt(x, z, place.floorY + refY) - place.floorY
		end
		-- (parts carry float32 sizes and positions)
		t.near(ground(0, 92, 0), AlleyLayout.ALLEY_Y, 1e-4)
		t.near(ground(0, 40, AlleyLayout.DUCT_FLOOR), AlleyLayout.DUCT_FLOOR, 1e-4, "inside the duct: its floor")
		t.truthy(ground(0, 40, 1) > AlleyLayout.DUCT_CEIL, "above the lane: the lane")
		-- the rear wall stops a body; the open alley does not
		local wx, _, wz = AlleyLayout.toWorld(place, 6.2, 0, AlleyLayout.REAR_WALL_D + 0.4)
		t.truthy(w.blocked(wx, wz, place.floorY + AlleyLayout.ALLEY_Y))
		local ax, _, az = AlleyLayout.toWorld(place, 6.2, 0, 92)
		t.falsy(w.blocked(ax, az, place.floorY + AlleyLayout.ALLEY_Y))
		-- straight up from the duct floor at D 55: the kickback board hangs into the duct
		local kx, ky, kz = AlleyLayout.toWorld(place, 0, AlleyLayout.DUCT_FLOOR + 0.2, 55)
		local _, hit = w.raycast(kx, ky, kz, 0, 3, 0)
		t.eq(hit and hit.path, "Masking.Kickback")
	end)

	t.test("the survey's numbers: the old vent pulls the squirrel 5 studs in at 0.32 s; the rack at 5.42 s", function()
		local w, place = BakedWorld.bakeAlley()
		local mw = w:motorWorld(BakedWorld.recordsData(legacy(place)))
		local x, y, z = AlleyLayout.toWorld(place, 0, AlleyLayout.ALLEY_Y, 92)
		local state = SquirrelMotor.new(x, w.groundAt(x, z, y + 1), z)
		local dX, dZ = AlleyLayout.dirToWorld(place, 0, -1)
		local cam = BakedWorld.cameraYawToward(dX, dZ)
		state.yaw = math.atan2(dX, dZ)
		local trace = BakedWorld.drive(mw, state, 60 * 30, function()
			return BakedWorld.keys(cam, { fw = 1 })
		end, {
			stop = function(s)
				return s.routeId == 9004 and s.railT >= 1
			end,
		})
		local attach = nil
		for _, e in trace.events do
			if e.kind == "attach" then
				attach = e
				break
			end
		end
		t.truthy(attach ~= nil)
		local a = attach :: any
		t.eq(a.frame, 19, "0.32 s")
		local before = trace.frames[a.frame - 1]
		local after = trace.frames[a.frame]
		local _, _, D0 = AlleyLayout.toLocal(place, before.x, before.y, before.z)
		local _, _, D1 = AlleyLayout.toLocal(place, after.x, after.y, after.z)
		t.near(D0, 88.14, 0.01)
		t.near(D1, 83.10, 0.01)
		t.near(trace.maxStep, 5.04, 0.01, "one frame's jump onto the vent")
		t.near(trace.seconds, 5.42, 0.01)
		-- and the tunnel's body passes through the kickback board for 15.5 studs (survey: 1.2 wide, 1.5 high)
		local hits =
			BakedWorld.clearance(w, mw.registry, mw.registry:get(9004) :: Registry.Route, { width = 1.2, height = 1.5 })
		local kick = nil
		for _, h in hits do
			if h.path == "Masking.Kickback" then
				kick = h
			end
		end
		t.truthy(kick ~= nil)
		t.near((kick :: any).studs, 15.5, 0.2)
	end)
end
