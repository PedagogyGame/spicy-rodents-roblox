--!strict
-- Bowl Lane (tools/bake/bowl_lane/Street, Workspace.Expansion.F2), planned and built in memory by the same code that
-- writes build/Expansion_F2.rbxm, with the town's roads it meets (worldgen Plan.road on generated/Roads, as the town
-- bake lays them), the bowling alley (BakedWorld.bakeAlley) and THE GILDED ACORN (its own bake's code) round it:
--   * the plan: the lane continues the cross street's asphalt end to end, its sidewalks start at the cross street's
--     east sidewalk and stop at the turning bay, nothing paved overlaps at one height, and no traffic AI knows it;
--   * no grass comes up through the paving: every strip's top, the turning bay's strips too, is on the ground;
--   * a person walks on paving with no step a body cannot take from Main Street's south sidewalk down the Alley Walk,
--     over the crossing and up the steps walk to the foot of the alley's ramp, along both sidewalks end to end, and
--     from the south sidewalk onto the lounge's forecourt;
--   * the town's path-finder (World/FootPath) walks the same ways straight, and the lounge's guards never reach the
--     sidewalk (LoungeClassic.GUARDED stays off it);
--   * the squirrel's real motor runs the lane, both sidewalks and across the street on the paving;
--   * its cost: parts, lights, lamps on the grass and clear of the venues' fronts.
local roblox = require("@lune/roblox")
local Colliders = require("@shared/World/Colliders")
local Data = require("@shared/Data")
local FootPath = require("@shared/World/FootPath")
local Height = require("@shared/World/Height")
local LoungeClassic = require("@shared/Attractions/LoungeClassic")
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local Town = require("@shared/World/Town")
local BakedWorld = require("../lib/BakedWorld")
local Expansion = require("../../generated/Expansion")
local Roads = require("../../generated/Roads")
local Lanes = require("../../generated/Lanes")
local TerrainExtensions = require("../../generated/TerrainExtensions")
local Factory = require("../../src/worldgen/Factory")
local Plan = require("../../src/worldgen/Plan")
local Road = require("../../src/worldgen/Builders/Road")
local Kit = require("../../tools/bake/alley/Kit")
local Lounge = require("../../tools/bake/lounge_classic/Lounge")
local Street = require("../../tools/bake/bowl_lane/Street")
local TownView = require("@client/Render/TownView")

local STEP = 0.75 -- studs: what a person (a Humanoid) and the squirrel (ClientWorld.STEP) step up without a jump
local SAMPLE = 0.5 -- studs between the profile's samples

local function record(list: { any }, id: string): any
	for _, r in list do
		if r.id == id then
			return r
		end
	end
	error("no " .. id)
end

local function factory(): any
	return Factory.new({
		Instance = roblox.Instance,
		Vector3 = roblox.Vector3,
		CFrame = roblox.CFrame,
		Color3 = roblox.Color3,
		Enum = roblox.Enum,
		UDim2 = roblox.UDim2,
		ColorSequence = roblox.ColorSequence,
	})
end

return function(t)
	Height.configure(TerrainExtensions)
	local plan = Street.plan()
	local folder = roblox.Instance.new("Folder")
	folder.Name = "F2"
	local street = Street.build(roblox, folder)

	-- the world round it: the street, the town roads it meets, the alley and the lounge
	local scene = roblox.Instance.new("Folder")
	street:Clone().Parent = scene
	local town = roblox.Instance.new("Folder")
	town.Name = "TownRoads"
	town.Parent = scene
	local townRoads = {
		record(Roads :: any, "rd_019_commercial_blvd"),
		record(Roads :: any, "rd_020_commercial_sidewalk_z-17.4"),
		record(Roads :: any, Street.CROSS_ROAD),
		record(Roads :: any, Street.CROSS_SIDEWALK),
	}
	local f = factory()
	for _, r in townRoads do
		Road.build(Plan.road(r, Roads :: any), f).Parent = town
	end
	local _, _, alley = BakedWorld.bakeAlley()
	alley.Parent = scene
	local loungeVenue = record((Expansion :: any).venues, LoungeClassic.VENUE)
	Lounge.build(Kit.new(roblox, loungeVenue.place), scene, loungeVenue)
	local world = BakedWorld.fromModel(scene)

	-- the paving a body stands on at (x, z) from above: (top, part name, part path)
	local function paving(x: number, z: number, refY: number?): (number, string?, string?)
		local y, part = world.groundPart(x, z, refY or (Height.at(x, z) + 3))
		return y, if part then part.name else nil, if part then part.path else nil
	end

	-- walk a straight line from a to b on paving: every sample stands on a colliding part, never a step taller than
	-- STEP between two samples; returns the worst step
	local function profile(name: string, ax: number, az: number, bx: number, bz: number, ok: ((string) -> boolean)?)
		local len = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
		local n = math.max(1, math.ceil(len / SAMPLE))
		local prev: number? = nil
		local worst = 0
		local bare = 0
		for k = 0, n do
			local x, z = ax + (bx - ax) * k / n, az + (bz - az) * k / n
			local y, part, path = paving(x, z, if prev then prev + 1.5 else nil)
			if part == nil or (ok and not ok(path :: string)) then
				bare += 1
				if bare <= 3 then
					t.truthy(false, `{name}: no paving at ({x}, {z}) (on {path or "the ground"})`)
				end
			end
			if prev then
				worst = math.max(worst, math.abs(y - prev))
			end
			prev = y
		end
		t.truthy(worst <= STEP, `{name}: a step of {worst} studs`)
		return worst
	end

	t.test(
		"the plan: the cross street's asphalt runs on to a turning bay; sidewalks, walks and bay meet edge to edge",
		function()
			local cross = record(Roads :: any, Street.CROSS_ROAD)
			local sw = record(Roads :: any, Street.CROSS_SIDEWALK)
			local lane = plan.lane
			local planned = record((Expansion :: any).strips, Street.ID)
			t.eq(lane.axis, "x")
			t.eq(lane.coord, planned.coord)
			t.eq(lane.width, planned.width)
			t.eq(lane.start, cross.coord + cross.width / 2, "the lane starts on the cross street's east kerb line")
			local turn = record((Expansion :: any).pads, Street.TURN).rect
			t.eq(lane["end"], turn.x0, "and ends where the turning bay begins")
			t.eq(plan.turn.start, turn.x0)
			t.eq(plan.turn["end"], turn.x1)
			t.eq(#plan.sidewalks, 2)
			for _, s in plan.sidewalks do
				t.eq(s.kind, "concrete")
				t.eq(s.start, sw.coord + sw.width / 2, "a sidewalk starts at the cross street's east sidewalk")
				t.eq(s["end"], turn.x0)
				-- each meets the kerb: its inner edge is the lane's edge
				t.near(math.abs(s.coord - lane.coord) - s.width / 2, lane.width / 2, 1e-9)
			end
			-- the Alley Walk ends on the north sidewalk's outer edge and on Main Street's south sidewalk; the steps walk
			-- starts on the south sidewalk's outer edge and ends at the foot of the alley's ramp
			local walk, steps = plan.walks[1], plan.walks[2]
			local south, north = plan.sidewalks[1], plan.sidewalks[2]
			local main = record(Roads :: any, "rd_020_commercial_sidewalk_z-17.4")
			t.near(math.min(walk.start, walk["end"]), north.coord + north.width / 2, 1e-9)
			t.near(math.max(walk.start, walk["end"]), main.coord - main.width / 2, 0.05)
			t.near(math.max(steps.start, steps["end"]), south.coord - south.width / 2, 1e-9)
			t.eq(walk.coord, steps.coord, "the two walks are on one line, straight across the lane")
			-- no two strips of the street overlap (they meet edge to edge); the lane crosses only the cross street's
			-- sidewalk, which lies on it a little higher, as every town sidewalk crosses the street at a junction
			for i, a in plan.strips do
				local ax0, ax1, az0, az1 = Street.box(a)
				for j, b in plan.strips do
					if j > i then
						local bx0, bx1, bz0, bz1 = Street.box(b)
						local ox = math.min(ax1, bx1) - math.max(ax0, bx0)
						local oz = math.min(az1, bz1) - math.max(az0, bz0)
						t.truthy(ox <= 0.01 or oz <= 0.01, `{a.id} overlaps {b.id} ({ox} x {oz})`)
					end
				end
				for _, r in Roads :: { any } do
					if r.axis == "x" or r.axis == "z" then
						local rx0, rx1, rz0, rz1 = Street.box(r)
						local ox = math.min(ax1, rx1) - math.max(ax0, rx0)
						local oz = math.min(az1, rz1) - math.max(az0, rz0)
						if ox > 0.05 and oz > 0.05 then
							t.truthy(
								a.id == Street.ID and r.id == Street.CROSS_SIDEWALK,
								`{a.id} overlaps the town's {r.id}`
							)
						end
					end
				end
			end
		end
	)

	t.test("the zebra crossing: bars along the lane, the walk's width long, one after another kerb to kerb", function()
		local c = plan.crossing
		local walk = plan.walks[1]
		t.truthy(#c.bars >= 5, `{#c.bars} bars`)
		local model = street:FindFirstChild("Crossing") :: any
		local stripes = model:GetChildren()
		t.eq(#stripes, #c.bars)
		for _, s in stripes do
			-- long the way the traffic runs (x), across the walker's way (z)
			t.truthy(s.Size.X > s.Size.Z * 3, `a bar {s.Size.X} along the lane by {s.Size.Z} across`)
			t.near(s.Size.X, walk.width, 1e-6)
			t.near(s.CFrame.Position.X, walk.coord, 1e-6)
		end
		for k = 2, #c.bars do
			local gap = c.bars[k].z - c.bars[k - 1].z
			t.near(gap, Street.ZEBRA.width + Street.ZEBRA.gap, 1e-6)
		end
		t.truthy(c.bars[1].z - c.bars[1].width / 2 >= c.z0, "inside the south kerb")
		t.truthy(c.bars[#c.bars].z + c.bars[#c.bars].width / 2 <= c.z1, "inside the north kerb")
	end)

	t.test("no traffic AI: the lane is in neither the town's roads nor its traffic lanes", function()
		local townData = Town.fromData(Data.default())
		for _, s in townData.strips do
			t.truthy(not string.find(s.id, "bowl", 1, true), s.id)
		end
		local x0, x1, z0, z1 = Street.box(plan.lane)
		local tx0, tx1, tz0, tz1 = Street.box(plan.turn)
		local function inside(x: number, z: number): boolean
			return (x > x0 + 1 and x < x1 and z > z0 and z < z1) or (x > tx0 and x < tx1 and z > tz0 and z < tz1)
		end
		-- every traffic lane's line, sampled every 2 studs (straight lanes; polylines of { x, z } points)
		local n = 0
		local function leg(id: string, ax: number, az: number, bx: number, bz: number)
			local k = math.max(1, math.ceil(math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2) / 2))
			for i = 0, k do
				local x, z = ax + (bx - ax) * i / k, az + (bz - az) * i / k
				n += 1
				t.truthy(not inside(x, z), `traffic lane {id} runs over Bowl Lane at ({x}, {z})`)
			end
		end
		for _, lane in Lanes :: { any } do
			for _, r in lane.roads or {} do
				t.truthy(not string.find(r, "bowl", 1, true), `{lane.id} runs on {r}`)
			end
			local path = lane.path
			if path and path.axis == "x" then
				leg(lane.id, path.start, path.coord, path["end"], path.coord)
			elseif path and path.axis == "z" then
				leg(lane.id, path.coord, path.start, path.coord, path["end"])
			elseif path then
				for _, list in { path.points or {}, path.resolved_start or {} } do
					for i = 1, #list - 1 do
						local a, b = list[i], list[i + 1]
						if type(a[1]) == "number" and type(b[1]) == "number" then
							leg(lane.id, a[1], a[2], b[1], b[2])
						end
					end
				end
			end
		end
		t.truthy(n > 1000, `the traffic lanes were read ({n} points)`)
		t.eq(street:GetAttribute("TrafficAI"), false)
	end)

	t.test("no grass through the paving: every strip's whole top stands on the ground, the turning bay too", function()
		-- (a strip stands flat across its width, rolled to the crossfall: the turning bay, 48 wide, is laid in
		-- TURN_STRIPS narrow strips, as one it was under the ground over half its area)
		local paved = street:FindFirstChild("Paving")
		t.eq(#plan.turns, Street.TURN_STRIPS)
		for _, s in plan.strips do
			local m = paved:FindFirstChild(s.id)
			t.truthy(m ~= nil, `{s.id} is laid`)
			local x0, x1, z0, z1 = Street.box(s)
			local n, under, worst = 0, 0, -math.huge
			for x = x0 + 0.3, x1 - 0.3, 1 do
				for z = z0 + 0.3, z1 - 0.3, 1 do
					local top = Street.topAt(roblox, m, x, z)
					if top then
						n += 1
						local d = Height.at(x, z) - top
						worst = math.max(worst, d)
						if d > 0.06 then
							under += 1
						end
					end
				end
			end
			t.truthy(n > 0, `{s.id}: sampled`)
			t.eq(under, 0, `{s.id}: the ground above the paving at {under} of {n} spots (worst {worst})`)
		end
		-- and across the bay, strip to strip, a person and the squirrel walk it with no step (where the ground is a
		-- hair above the paving, the foot is on the ground: the paving's top is within 0.06 of it)
		local x0, x1, z0, z1 = Street.box(plan.turn)
		for _, x in { x0 + 2, (x0 + x1) / 2, x1 - 2 } do
			local prev: number? = nil
			local worst = 0
			for z = z0 + 0.5, z1 - 0.5, SAMPLE do
				local y = paving(x, z, if prev then prev + 1.5 else nil)
				if prev then
					worst = math.max(worst, math.abs(y - prev))
				end
				prev = y
			end
			t.truthy(worst <= 0.3, `across the turning bay at x {x}: a step of {worst}`)
		end
	end)

	t.test(
		"on foot: Main Street to the alley's ramp, both sidewalks end to end, onto the lounge's forecourt",
		function()
			local walk = plan.walks[1]
			local x = walk.coord
			local main = record(Roads :: any, "rd_020_commercial_sidewalk_z-17.4")
			local ramp = AlleyLayout.RAMP
			-- from the middle of Main Street's south sidewalk, down the walk, over the crossing, up the steps walk, onto
			-- the foot of the alley's ramp
			local a =
				require("@lune/serde").decode("json", require("@lune/fs").readFile("data/attractions.json")).attractions[1]
			local _, _, rampFootZ = AlleyLayout.toWorld(a.place, (ramp.x0 + ramp.x1) / 2, 0, ramp.d0 + 1)
			local worst = profile("Alley Walk", x, main.coord, x, rampFootZ)
			print(`      Main Street to the alley's ramp: worst step {string.format("%.2f", worst)} studs`)
			-- along both sidewalks and the lane, the cross street's sidewalk to the turning bay
			for _, s in plan.sidewalks do
				profile(s.id, 912, s.coord, s["end"] - 0.5, s.coord)
			end
			profile("the lane", plan.lane.start + 0.25, plan.lane.coord, plan.turn["end"] - 1, plan.lane.coord)
			-- the join with the cross street: its asphalt (rolled to its crossfall, so its edge lies at the terrain
			-- there) and the lane's start are within a step of each other on each lane of the lane
			for _, dz in { -8, 0, 8 } do
				local z = plan.lane.coord + dz
				local west = world.groundAt(plan.lane.start - 0.5, z, Height.at(plan.lane.start, z) + 3)
				local east = world.groundAt(plan.lane.start + 0.5, z, Height.at(plan.lane.start, z) + 3)
				t.truthy(math.abs(east - west) <= STEP, `the join with the cross street: a step of {east - west}`)
			end
			-- the lounge's forecourt meets the south sidewalk: from the lane's centre to the forecourt at D -30
			local place = loungeVenue.place
			local fx, _, fz = AlleyLayout.toWorld(place, 0, 0, -30)
			local w2 = profile("to the lounge", fx, plan.lane.coord, fx, fz)
			print(`      the south sidewalk onto the lounge's forecourt: worst step {string.format("%.2f", w2)} studs`)
		end
	)

	t.test("the town's path-finder walks it straight; the lounge's guards never reach the sidewalk", function()
		local data = Data.default()
		local colliders = Colliders.fromData(data)
		local finder = FootPath.new({ colliders = colliders, bounds = Height.worldClamp() })
		local walk = plan.walks[1]
		local south = plan.sidewalks[1]
		local legs = {
			{ "Main Street to the alley's doors", walk.coord, -44, walk.coord, south.coord - 4 },
			{ "the cross street to the lounge", 911, south.coord, 1487, south.coord },
			{ "along the lane to the turning bay", 911, plan.lane.coord, 1690, plan.lane.coord },
		}
		for _, l in legs do
			local points, len = FootPath.find(finder, l[2], l[3], l[4], l[5])
			t.truthy(points ~= nil, `{l[1]}: no way`)
			local direct = math.sqrt((l[4] - l[2]) ^ 2 + (l[5] - l[3]) ^ 2)
			t.truthy(len <= direct + 1, `{l[1]}: {len} studs for {direct} straight`)
		end
		-- every point of the south sidewalk in front of the lounge is outside the guarded ground
		local place = loungeVenue.place
		for x = place.x - 30, place.x + 30, 0.5 do
			-- (the sidewalk's outer edge is the guarded ground's edge, D -32: from just inside it)
			for z = south.coord - south.width / 2 + 0.05, south.coord + south.width / 2, 0.5 do
				local X, Y, D = AlleyLayout.toLocal(place, x, Height.at(x, z) + 1, z)
				t.truthy(not LoungeClassic.guarded(X, Y, D), `guarded on the sidewalk at ({x}, {z})`)
			end
		end
	end)

	t.test("the squirrel runs the lane, the sidewalks and across the street on the paving", function()
		local w = world:motorWorld(Data.default())
		local function run(name: string, x: number, z: number, dx: number, dz: number, secs: number, want: number)
			local s = SquirrelMotor.new(x, world.groundAt(x, z, Height.at(x, z) + 3), z)
			s.yaw = math.atan2(dx, dz)
			local cam = BakedWorld.cameraYawToward(dx, dz)
			local trace = BakedWorld.drive(w, s, math.floor(60 * secs), function()
				return BakedWorld.keys(cam, { fw = 1 })
			end)
			local moved = (s.x - x) * dx + (s.z - z) * dz
			t.truthy(moved >= want, `{name}: {moved} studs in {secs} s`)
			local off = 0
			for _, fr in trace.frames do
				if fr.grounded then
					local y = world.groundAt(fr.x, fr.z, fr.y + 1)
					off = math.max(off, math.abs(fr.y - y))
				end
			end
			t.truthy(off <= 0.3, `{name}: {off} studs off the paving`)
			t.truthy(s.routeId == nil, `{name}: ended on route {s.routeId}`)
		end
		run("the lane, eastbound", 920, plan.lane.coord - 4, 1, 0, 10, 60)
		run("the lane, westbound", 1640, plan.lane.coord + 4, -1, 0, 10, 60)
		for _, sd in plan.sidewalks do
			run(sd.id, 1200, sd.coord, 1, 0, 8, 50)
		end
		local walk = plan.walks[1]
		run("across on the crossing", walk.coord, -250, 0, -1, 10, 60)
	end)

	t.test("its cost and its lamps: parts in budget, six lamps the town's pool lights, on the grass", function()
		local parts = street:GetAttribute("Parts") :: number
		t.truthy(parts <= Street.BUDGET, `{parts} parts (budget {Street.BUDGET})`)
		-- no light of its own: the town's lamp pool (Client/Render/TownView) lights the tagged heads, off by day
		t.eq(street:GetAttribute("Lights"), 0)
		t.eq(Street.LAMP_TAG, TownView.TAG)
		print(`      Bowl Lane: {parts} parts (budget {Street.BUDGET}), no lights of its own`)
		local lamps = street:FindFirstChild("Lamps") :: any
		t.eq(#lamps:GetChildren(), #Street.LAMP_X)
		for _, m in lamps:GetChildren() do
			-- always on the client, so the pool knows every head from the start
			t.eq(m.ModelStreamingMode, roblox.Enum.ModelStreamingMode.Persistent)
			local heads = 0
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") and d:HasTag(TownView.TAG) then
					heads += 1
				end
			end
			t.eq(heads, 1, `{m.Name}: one head for the pool`)
			local post = m:FindFirstChild("Post") :: any
			local p = post.CFrame.Position
			t.eq(Street.on(plan, p.X, p.Z), nil, `{m.Name} stands on the paving`)
			-- clear of the venues' fronts and walks (nothing of the alley or the lounge within 6 studs)
			for _, other in { alley, scene:FindFirstChild(LoungeClassic.VENUE) } do
				for _, d in (other :: any):GetDescendants() do
					if d:IsA("BasePart") then
						local q = d.CFrame.Position
						t.truthy(
							math.abs(q.X - p.X) > d.Size.X / 2 + 6 or math.abs(q.Z - p.Z) > d.Size.Z / 2 + 6,
							`{m.Name} beside {d:GetFullName()}`
						)
					end
				end
			end
		end
	end)
end
