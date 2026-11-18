--!strict
-- tools/bake/bowl_lane/Street: Bowl Lane (data/expansion.json xs_bowl_lane, BRIEF_ADDENDUM D2, D5), the street in
-- front of the bowling alley, the lounges, the steakhouse's and the racquet club's sites. Two lanes and no traffic
-- AI (the plan): it is not in generated/Roads or generated/Lanes, so no car, ambulance or patrol is ever routed onto
-- it; people walk it (World/FootPath, the Alley Walk from Main Street) and the squirrel runs it (its parts collide).
-- Everything paved is laid by the town's own road plan (worldgen Plan.road on Road-shaped strips: flat segments on
-- the terrain at the kind's height, the town's colours, materials, dashed centre line and kerbs), so the lane looks
-- and stands exactly as the town's streets do:
--   Lane        the asphalt from the cross street's kerb (x 903.75, end to end with rd_022) to the turning bay;
--   Sidewalks   both, from the cross street's east sidewalk (rd_024 ends at x 915.5: nothing overlaps it) to the
--               turning bay, each with its kerb on the street edge (Plan.road's curb);
--   Turn        the turning bay (xp_bowl_lane_turn), asphalt over the pad in TURN_STRIPS strips side by side along
--               the lane (each follows the ground along x and is rolled to its own crossfall: one strip the pad's
--               48 wide stood flat across a ground that is not, and the grass came up through half of it), with a
--               kerb strip round its three outer edges;
--   AlleyWalk   the Alley Walk (xpath_alley_walk) from Main Street's south sidewalk to the north sidewalk, and the
--               steps walk (xpath_alley_steps) from the south sidewalk to the foot of the alley's entrance ramp;
--   Crossing    a zebra crossing between the two, straight across the lane on the walk's line;
--   Lamps       LAMPS street lamps in the town's shape (a 15-stud post, the curved arm over the road, a glowing head),
--               in one row behind the north sidewalk (the south side is the venues' frontage), each its own Persistent
--               Model (always on every client, a dozen parts); no light of their own: the head carries the tag
--               LAMP_TAG and the town's lamp pool (Client/Render/TownView) lights it as it lights the town's, the
--               nearest to the camera, off by day;
--   NameSign    the street's name on a post at the junction with the cross street, in the town's street-sign green.
-- Pure planning (Street.plan: strips, lamp spots, the crossing; no Instances) is apart from the Instances
-- (Street.build), so tests/unit/bowl_lane.spec.luau holds the plan without baking.
-- Interface: plan() -> Plan; build(roblox, parent) -> Model; on(plan, x, z) -> strip?; constants

local Expansion = require("../../../generated/Expansion")
local Roads = require("../../../generated/Roads")
local TerrainExtensions = require("../../../generated/TerrainExtensions")
local Factory = require("../../../src/worldgen/Factory")
local Height = require("../../../src/shared/World/Height")
local Kit = require("../alley/Kit")
local Palette = require("../../../src/worldgen/Palette")
local Plan = require("../../../src/worldgen/Plan")
local Road = require("../../../src/worldgen/Builders/Road")

local Street = {}

Street.ID = "xs_bowl_lane"
Street.TURN = "xp_bowl_lane_turn"
Street.TURN_STRIPS = 7 -- the bay's asphalt in this many strips across (6.9 wide each: under a road's 10, no centre line)
Street.WALKS = { "xpath_alley_walk", "xpath_alley_steps" }
Street.CROSS_SIDEWALK = "rd_024_commercial_sidewalk_x364.5" -- the cross street's east sidewalk, which the lane meets
Street.CROSS_ROAD = "rd_022_commercial_cross_x347"
Street.LAMP_X = { 978, 1104, 1232, 1452, 1566, 1642 } -- behind the north sidewalk (clear of the Alley Walk, x 1318..1326, and the antique store's front, x 1340..1380)
Street.LAMP_HEIGHT = 15 -- studs: the town's lamp (Kits.lamp heightU 6)
Street.LAMP_BACK = 1.6 -- studs behind the sidewalk's outer edge (LampPlan: a sidewalk that meets the kerb)
Street.ZEBRA = { stripes = 7, width = 1.2, gap = 1.2 } -- stripes along the lane on the walk's line
Street.BUDGET = 700 -- parts (Model attribute PartBudget; tests/unit/bowl_lane.spec)
Street.SIGN_GREEN = { 32, 74, 50 } -- the town's street-name green (tools/bake/Ways)
Street.METAL = { 44, 48, 50 } -- the town's lamp metal (worldgen LampPlan)
Street.LAMP_TAG = "StreetLampHead" -- (Client/Render/TownView.TAG: the heads its light pool lights)

export type Strip = Plan.Road
export type Lamp = { x: number, z: number, ox: number, oz: number }
export type StreetPlan = {
	lane: Strip,
	sidewalks: { Strip },
	turn: Strip, -- the whole bay (its rectangle)
	turns: { Strip }, -- the bay as laid: TURN_STRIPS strips along x, side by side across it
	walks: { Strip },
	strips: { Strip }, -- every paved strip above, the lane first
	lamps: { Lamp },
	crossing: { x: number, z0: number, z1: number },
	sign: { x: number, z: number },
}

local function record(list: { any }, id: string): any
	for _, r in list do
		if r.id == id then
			return r
		end
	end
	error("bowl lane: no " .. id)
end

local function strip(r: any): Strip
	return {
		id = r.id,
		kind = r.kind,
		axis = r.axis,
		coord = r.coord,
		start = r.start,
		["end"] = r["end"],
		width = r.width,
		registered = r.registered,
	} :: any
end

-- a path's legs as strips (each leg runs along x or along z)
local function legs(path: any): { Strip }
	local out: { Strip } = {}
	local pts = path.points
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local along = if a[1] == b[1] then "z" elseif a[2] == b[2] then "x" else error(`{path.id}: a leg on a slant`)
		table.insert(
			out,
			{
				id = if #pts == 2 then path.id else `{path.id}_{i}`,
				kind = "concrete",
				axis = along,
				coord = if along == "z" then a[1] else a[2],
				start = if along == "z" then a[2] else a[1],
				["end"] = if along == "z" then b[2] else b[1],
				width = path.width,
			} :: any
		)
	end
	return out
end

-- The street as planned: the strips from generated/Expansion, trimmed where they meet the town's roads and the
-- turning bay (so no two paved parts ever overlap at one height), the lamps and the crossing. Pure.
function Street.plan(): StreetPlan
	local exp = Expansion :: any
	local lane = strip(record(exp.strips, Street.ID))
	local turnRect = record(exp.pads, Street.TURN).rect
	local cross = record(Roads :: any, Street.CROSS_SIDEWALK)
	local crossEdge = cross.coord + cross.width / 2 -- x 915.5
	-- the lane runs on to the bay's west edge; the sidewalks start at the cross street's east sidewalk's edge
	lane["end"] = turnRect.x0
	local sidewalks: { Strip } = {}
	for _, suffix in { "_sidewalk_a", "_sidewalk_b" } do
		local s = strip(record(exp.strips, Street.ID .. suffix))
		s.start = crossEdge
		s["end"] = turnRect.x0
		table.insert(sidewalks, s)
	end
	table.sort(sidewalks, function(a, b)
		return a.coord < b.coord
	end)
	local turn: Strip = {
		id = Street.TURN,
		kind = "asphalt",
		axis = "x",
		coord = (turnRect.z0 + turnRect.z1) / 2,
		start = turnRect.x0,
		["end"] = turnRect.x1,
		width = turnRect.z1 - turnRect.z0,
	} :: any
	local turns: { Strip } = {}
	local w = turn.width / Street.TURN_STRIPS
	for k = 1, Street.TURN_STRIPS do
		table.insert(
			turns,
			{
				id = `{Street.TURN}_{k}`,
				kind = "asphalt",
				axis = "x",
				coord = turnRect.z0 + w * (k - 0.5),
				start = turnRect.x0,
				["end"] = turnRect.x1,
				width = w,
			} :: any
		)
	end
	local walks: { Strip } = {}
	for _, id in Street.WALKS do
		for _, leg in legs(record(exp.paths, id)) do
			table.insert(walks, leg)
		end
	end
	local strips: { Strip } = { lane }
	for _, list in { sidewalks, turns, walks } do
		for _, s in list do
			table.insert(strips, s)
		end
	end
	-- the lamps: one row behind the north sidewalk, each arm reaching south over the road
	local north = sidewalks[#sidewalks]
	local lz = north.coord + north.width / 2 + Street.LAMP_BACK
	local lamps: { Lamp } = {}
	for _, x in Street.LAMP_X do
		table.insert(lamps, { x = x, z = lz, ox = 0, oz = -1 })
	end
	-- the crossing on the Alley Walk's line, kerb to kerb
	local walk = walks[1]
	local crossing = { x = walk.coord, z0 = lane.coord - lane.width / 2, z1 = lane.coord + lane.width / 2 }
	-- the name sign at the north-west corner of the junction, behind the sidewalk
	local sign = { x = crossEdge + 3, z = lz }
	return {
		lane = lane,
		sidewalks = sidewalks,
		turn = turn,
		turns = turns,
		walks = walks,
		strips = strips,
		lamps = lamps,
		crossing = crossing,
		sign = sign,
	}
end

local function box(s: any): (number, number, number, number)
	local a0, a1 = math.min(s.start, s["end"]), math.max(s.start, s["end"])
	local c0, c1 = s.coord - s.width / 2, s.coord + s.width / 2
	if s.axis == "x" then
		return a0, a1, c0, c1
	end
	return c0, c1, a0, a1
end
Street.box = box

-- The planned strip under (x, z), or nil.
function Street.on(p: StreetPlan, x: number, z: number): Strip?
	for _, s in p.strips do
		local x0, x1, z0, z1 = box(s)
		if x >= x0 and x <= x1 and z >= z0 and z <= z1 then
			return s
		end
	end
	return nil
end

local function factoryOf(roblox: any): any
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

-- the top of a strip Model's paving at (x, z): the segment under the point, its tilted top there
local function topAt(roblox: any, model: any, x: number, z: number): number?
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") and string.sub(p.Name, 1, 3) == "Seg" then
			local l = p.CFrame:Inverse() * roblox.Vector3.new(x, p.CFrame.Position.Y, z)
			if math.abs(l.X) <= p.Size.X / 2 + 0.01 and math.abs(l.Z) <= p.Size.Z / 2 + 0.01 then
				return (p.CFrame * roblox.CFrame.new(l.X, p.Size.Y / 2, l.Z)).Position.Y
			end
		end
	end
	return nil
end
Street.topAt = topAt

-- a world-frame kit (local X = world x, local D = -world z)
local function lamp(kit: Kit.Kit, parent: any, i: number, l: Lamp)
	local roblox = kit.roblox
	local m = kit:model(parent, `Lamp{i}`)
	m.ModelStreamingMode = roblox.Enum.ModelStreamingMode.Persistent
	local x, z, ox, oz = l.x, l.z, l.ox, l.oz
	local g = Height.at(x, z)
	local top = g + Street.LAMP_HEIGHT
	local METAL = Street.METAL
	kit:cyl(m, "Base", x, g + 0.2, -z, 1.4, 1.4, "Y", METAL, "Metal")
	kit:cyl(m, "Post", x, (g + 0.9 + top) / 2, -z, top - g - 0.9, 0.84, "Y", METAL, "Metal")
	kit:cyl(m, "Finial", x, top + 0.25, -z, 0.5, 0.5, "Y", METAL, "Metal", { collide = false, query = false })
	local p0 = { x, top - 0.9, z }
	local p1 = { p0[1] + ox * 1.3, p0[2] + 1.1, p0[3] + oz * 1.3 }
	local p2 = { p1[1] + ox * 1.8, p1[2] + 0.25, p1[3] + oz * 1.8 }
	local hx, hz = x + ox * 4.2, z + oz * 4.2
	local p3 = { hx, p2[2] - 0.55, hz }
	for k, seg in { { p0, p1 }, { p1, p2 }, { p2, p3 } } do
		local a, b = seg[1], seg[2]
		kit:rod(m, `Arm{k}`, a[1], a[2], -a[3], b[1], b[2], -b[3], 0.3, METAL, "Metal")
	end
	local yaw = math.atan2(-ox, -oz)
	local rot = roblox.CFrame.Angles(0, yaw, 0)
	local hcx, hcz = hx + ox * 0.3, hz + oz * 0.3
	kit:at(m, "Housing", hcx, p3[2] - 0.2, -hcz, 1.2, 0.5, 2.0, { 40, 44, 46 }, "Metal", {
		collide = false,
		query = false,
		rot = rot,
	})
	local head = kit:at(m, "Head", hcx, p3[2] - 0.52, -hcz, 0.9, 0.16, 1.5, { 255, 228, 170 }, "Neon", {
		collide = false,
		query = false,
		shadow = false,
		rot = rot,
	})
	head:AddTag(Street.LAMP_TAG)
end

-- The street's Model, `xs_bowl_lane`, in `parent`. Returns it (attributes Parts, PartBudget, Lights).
function Street.build(roblox: any, parent: any): any
	Height.configure(TerrainExtensions)
	local p = Street.plan()
	local factory = factoryOf(roblox)
	local kit = Kit.new(roblox, { x = 0, z = 0, floorY = 0, yaw = 0 })
	local root = kit:model(parent, Street.ID)
	root.ModelStreamingMode = roblox.Enum.ModelStreamingMode.Default
	root:SetAttribute("Street", Street.ID)
	root:SetAttribute("TrafficAI", false)
	-- the paving: the town's road plan on every strip (kerbs from the lane, which every sidewalk borders)
	local paving = kit:folder(root, "Paving")
	local models: { [string]: any } = {}
	for _, s in p.strips do
		local m = Road.build(Plan.road(s, p.strips), factory)
		m.Parent = paving
		models[s.id] = m
	end
	-- the turning bay's kerb on its north, south and east edges (the lane comes in on the west)
	do
		local t = p.turn
		local x0, x1, z0, z1 = box(t)
		local KERB = Palette.ROAD.curb
		local function kerb(name: string, ax: number, az: number, bx: number, bz: number)
			local cx, cz = (ax + bx) / 2, (az + bz) / 2
			local under = Street.on(p, cx, cz) :: Strip -- the bay's strip the kerb stands on
			local m = models[under.id]
			local y = (topAt(roblox, m, cx, cz) or Height.at(cx, cz)) + 0.12
			local len = math.max(math.abs(bx - ax), math.abs(bz - az))
			local alongX = math.abs(bx - ax) > math.abs(bz - az)
			kit:at(
				m,
				name,
				cx,
				y,
				-cz,
				if alongX then len else 0.4,
				0.3,
				if alongX then 0.4 else len,
				KERB,
				"SmoothPlastic",
				{ collide = false, query = false, shadow = false }
			)
		end
		-- each edge in pieces, so the kerb follows the bay's fall
		local n = 4
		for k = 0, n - 1 do
			local a, b = x0 + (x1 - x0) * k / n, x0 + (x1 - x0) * (k + 1) / n
			kerb(`KerbN{k + 1}`, a, z1 - 0.2, b, z1 - 0.2)
			kerb(`KerbS{k + 1}`, a, z0 + 0.2, b, z0 + 0.2)
			local c, d = z0 + (z1 - z0) * k / n, z0 + (z1 - z0) * (k + 1) / n
			kerb(`KerbE{k + 1}`, x1 - 0.2, c, x1 - 0.2, d)
		end
	end
	-- the zebra crossing on the Alley Walk's line
	do
		local c = p.crossing
		local m = kit:model(root, "Crossing")
		local z = Street.ZEBRA
		local span = z.stripes * z.width + (z.stripes - 1) * z.gap
		local laneModel = models[p.lane.id]
		for k = 0, z.stripes - 1 do
			local sx = c.x - span / 2 + z.width / 2 + k * (z.width + z.gap)
			local cz = (c.z0 + c.z1) / 2
			local y = (topAt(roblox, laneModel, sx, cz) or Height.at(sx, cz)) + 0.03
			kit:at(m, "Stripe", sx, y, -cz, z.width, 0.05, c.z1 - c.z0 - 1.2, Palette.ROAD.paint, "SmoothPlastic", {
				collide = false,
				query = false,
				shadow = false,
			})
		end
	end
	-- the lamps
	local lamps = kit:folder(root, "Lamps")
	for i, l in p.lamps do
		lamp(kit, lamps, i, l)
	end
	-- the name sign at the junction
	do
		local s = p.sign
		local m = kit:model(root, "NameSign")
		local g = Height.at(s.x, s.z)
		kit:cyl(m, "Post", s.x, g + 4.5, -s.z, 9, 0.35, "Y", Street.METAL, "Metal")
		local board = kit:box(
			m,
			"Board",
			s.x + 0.25, -- hung beside the post, east along the lane
			s.x + 7.45,
			g + 7.6,
			g + 8.9,
			-s.z - 0.08,
			-s.z + 0.08,
			Street.SIGN_GREEN,
			"SmoothPlastic",
			{ collide = false }
		)
		for _, face in { "Front", "Back" } do
			local gui = kit:gui(board, face, 40)
			kit:label(gui, { Text = "BOWL LANE", TextColor = { 236, 236, 228 }, Font = "GothamBold" })
		end
	end
	local parts, lights = 0, 0
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
		elseif d:IsA("PointLight") then
			lights += 1
		end
	end
	root:SetAttribute("Parts", parts)
	root:SetAttribute("PartBudget", Street.BUDGET)
	root:SetAttribute("Lights", lights)
	return root
end

return Street
