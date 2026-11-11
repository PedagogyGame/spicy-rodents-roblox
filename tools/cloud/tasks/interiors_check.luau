--!strict
-- Luau Execution task: the buildings people walk into, on the built world (the interiors work,
-- 2026-11-11). Needs a CI place version with Workspace.Town in it (rojo build ci.project.json after
-- `lune run tools/bake/main.luau`). It writes the boot terrain itself (WorldGen/WorldTerrain) and boots
-- nothing else, so the doors stand shut as baked and nobody is about.
--   parts      the town's parts in all, against Town.PartCount and the 27,000 budget; for each
--              enterable building its parts, furniture pieces, lights and rooms.
--   doors      every exterior door leaf of every lot: rays down in front of it find the sill's
--              threshold or steps and then the ground, with no rise or drop a walking body cannot
--              take and no ground standing over the sill. For the doors of the enterable buildings,
--              rays through the opening (three heights, three places across) find nothing solid.
--   buildings  each enterable building has a Floor and a Ceiling with headroom between them; under
--              the middle of every room a ray finds the floor and over it the ceiling, and no terrain
--              comes up through the floor (the hospital's back rooms had 5 st of it before its site
--              was cut level).
-- The same questions are answered on the bake plans, with World/Height as the ground, by
-- tests/unit/worldgen_enter.spec (DoorSill, EnterCheck) and worldgen_interior.spec; this asks them of
-- the engine's own voxels and parts.
-- NOT YET RUN: the session that wrote it (2026-11-11) had the cloud tools off limits. Its door looks
-- were tried on the bake plans with World/Height for the ground and boxes for the parts: 82 of the 83
-- exterior doors passed and the 11 doorways were clear; the 83rd (estate_1_mansion) was the box round
-- its sloping drive, which a real ray does not see.
-- Sent by: node tools/cloud/cloud.mjs run_engine_tests tools/cloud/tasks/interiors_check.luau --version <v> --place ci

local ServerScriptService = game:GetService("ServerScriptService")

local PART_BUDGET = 27000 -- tests/unit/worldgen_look.spec holds the bake to it
local ENTERABLE = 6 -- the four houses, the hospital and the police station (WorldGen/InteriorCheck)
local LEVEL = 0.35 -- WorldGen/DoorSill.LEVEL: a sill this far off the ground needs no step
local RISE = 0.75 -- WorldGen/DoorSill.RISE: the tallest step a walking body takes
local VOXEL = 0.6 -- how far the 4 st voxels may stand off World/Height on a slope
local BODY = 5 -- studs: the height of the body that walks in
local OUT = { 0.6, 1.2, 1.8, 2.4, 3.0, 3.6, 4.4, 5.2, 6.0 } -- studs in front of a leaf where the ground is looked for
local NEAR = 3.0 -- within this of the leaf no ground may stand over the sill (DoorSill)

local started = os.clock()
local failures: { string } = {}
local function fail(msg: string)
	table.insert(failures, msg)
end
local function round(v: number): number
	return math.floor(v * 100 + 0.5) / 100
end

local town = workspace:FindFirstChild("Town")
local lotsFolder = town and town:FindFirstChild("Lots")
if town == nil or lotsFolder == nil then
	return {
		suite = "interiors_check",
		ok = false,
		failures = { "Workspace.Town.Lots is missing (the place was saved without build/Town.rbxm)" },
		placeVersion = game.PlaceVersion,
		elapsedSeconds = os.clock() - started,
	}
end

-- the ground: the terrain the server writes at boot
local terrainSeconds = 0
do
	local worldGen = ServerScriptService:WaitForChild("Server"):WaitForChild("WorldGen")
	local WorldTerrain = (require :: any)(worldGen:WaitForChild("WorldTerrain"))
	local t0 = os.clock()
	WorldTerrain.write(workspace.Terrain)
	terrainSeconds = os.clock() - t0
	-- freshly written voxels do not meet rays until the engine has taken a step or two
	-- (tools/cloud/tasks/ground_probe.luau and terrain_calib.luau wait the same way)
	task.wait(2)
end

-- what a body would stand on or walk into: collidable parts and the terrain (never a door leaf or
-- decoration, which do not collide)
local solid = RaycastParams.new()
solid.RespectCanCollide = true
solid.IgnoreWater = true
local function only(inst: Instance): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { inst }
	params.IgnoreWater = true
	return params
end
local onlyTerrain = only(workspace.Terrain)

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-6 then f.Unit else Vector3.xAxis
end

-- 1. parts -----------------------------------------------------------------------------------------
local townParts = 0
for _, d in town:GetDescendants() do
	if d:IsA("BasePart") then
		townParts += 1
	end
end
local bakedParts = town:GetAttribute("PartCount")
if type(bakedParts) == "number" and bakedParts ~= townParts then
	fail(`the town has {townParts} parts; the bake counted {bakedParts}`)
end
if townParts > PART_BUDGET then
	fail(`the town has {townParts} parts: over the budget of {PART_BUDGET}`)
end

-- 2. doors -----------------------------------------------------------------------------------------
local doorNumbers = {
	exterior = 0,
	level = 0, -- the ground meets the sill
	stepped = 0, -- steps lead down to it
	openings = 0, -- doorways of enterable buildings looked through
	worstOverSill = -math.huge, -- the highest ground near a leaf, above its sill
	worstStep = 0, -- the tallest drop between two looks at the ground
}
local doorRows: { { [string]: any } } = {}

local function checkDoor(model: Model, leaf: BasePart, centre: Vector3, enterable: boolean)
	local roomA, roomB = leaf:GetAttribute("RoomA"), leaf:GetAttribute("RoomB")
	if not (roomA == "outside" or roomB == "outside" or roomA == nil) then
		return -- a door between two rooms
	end
	doorNumbers.exterior += 1
	local tag = `{model.Name}/{leaf.Name}`
	local cf = leaf.CFrame
	-- the outward normal, by the rule of WorldGen/DoorSill: a shell's door faces away from the middle
	-- of its building; a plain building's front door faces the way its leaf looks
	local n = flat(cf:VectorToWorldSpace(Vector3.zAxis))
	local sign = if roomA == nil and roomB == nil then -1 elseif (leaf.Position - centre):Dot(n) >= 0 then 1 else -1
	local out = n * sign
	local along = flat(cf.RightVector)
	local width, height = leaf.Size.X, leaf.Size.Y
	local sill = leaf.Position.Y - height / 2
	local base = Vector3.new(leaf.Position.X, 0, leaf.Position.Z)

	-- the ground in front: from the sill outward, what a body's feet find
	local last = sill
	local reachedGround = false
	local steps = 0
	local worstOver, worstStep = -math.huge, 0
	local ok = true
	for i, dist in OUT do
		local p = base + out * dist
		local hit = workspace:Raycast(Vector3.new(p.X, sill + 3, p.Z), Vector3.new(0, -15, 0), solid)
		if hit == nil then
			fail(`{tag}: nothing to stand on {dist} st in front of the door`)
			ok = false
			break
		end
		local y = hit.Position.Y
		if dist <= NEAR then
			worstOver = math.max(worstOver, y - sill)
		end
		local drop = last - y
		worstStep = math.max(worstStep, drop)
		if i == 1 and y - sill > LEVEL + VOXEL then
			fail(string.format("%s: the door stands %.2f st under the ground", tag, y - sill))
			ok = false
		elseif dist <= NEAR and y - sill > LEVEL + VOXEL then
			fail(string.format("%s: the ground %.1f st out stands %.2f st over the sill", tag, dist, y - sill))
			ok = false
		elseif drop > RISE + VOXEL then
			fail(string.format("%s: a drop of %.2f st, %.1f st in front of the door", tag, drop, dist))
			ok = false
		end
		-- the door's own steps are <leaf>_Step<k> (Builders/Facade); anything else underfoot is the
		-- ground: terrain, a pavement, a drive, the building's own forecourt
		if string.match(hit.Instance.Name, "_Step%d+$") ~= nil then
			if drop > 0.05 then
				steps += 1
			end
		else
			reachedGround = true
		end
		last = y
		if not ok or (reachedGround and dist >= NEAR) then
			break
		end
	end
	if ok and not reachedGround then
		fail(`{tag}: the steps never reach the ground within {OUT[#OUT]} st`)
		ok = false
	end
	if ok then
		if steps > 0 then
			doorNumbers.stepped += 1
		else
			doorNumbers.level += 1
		end
	end
	doorNumbers.worstOverSill = math.max(doorNumbers.worstOverSill, worstOver)
	doorNumbers.worstStep = math.max(doorNumbers.worstStep, worstStep)

	-- the opening: a body walks through it (only where there is a room behind the door)
	local blocked: string? = nil
	if enterable then
		doorNumbers.openings += 1
		local side = math.max(width / 2 - 0.75, 0)
		for _, h in { 1.25, 2.5, math.min(height, BODY) - 0.5 } do
			for _, a in { 0, -side, side } do
				local from = base + out * 1.5 + along * a + Vector3.new(0, sill + h, 0)
				local hit = workspace:Raycast(from, -out * 4, solid)
				if hit and blocked == nil then
					local what = hit.Instance:GetFullName()
					blocked = what
					fail(string.format("%s: %s stands in the doorway (%.1f st up, %.1f st across)", tag, what, h, a))
				end
			end
		end
	end
	if enterable or not ok then
		table.insert(doorRows, {
			door = tag,
			ok = ok and blocked == nil,
			sill = round(sill),
			width = round(width),
			height = round(height),
			steps = steps,
			overSill = round(worstOver),
			tallestStep = round(worstStep),
			blockedBy = blocked,
		})
	end
end

-- 3. buildings -------------------------------------------------------------------------------------
local buildings: { [string]: { [string]: any } } = {}
local enterableCount = 0

local function checkBuilding(model: Model)
	local row: { [string]: any } = { parts = 0, pieces = 0, lights = 0, rooms = 0, terrainOverFloor = 0 }
	buildings[model.Name] = row
	local rooms: { BasePart } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			row.parts += 1
			if d:GetAttribute("Kit") ~= nil then
				row.pieces += 1
			end
			if d:GetAttribute("RoomId") ~= nil and d:GetAttribute("Exterior") ~= true then
				table.insert(rooms, d)
			end
		elseif d:IsA("PointLight") then
			row.lights += 1
		end
	end
	row.rooms = #rooms
	local floor = model:FindFirstChild("Floor", true)
	local ceiling = model:FindFirstChild("Ceiling", true)
	if floor == nil or not floor:IsA("BasePart") then
		fail(`{model.Name}: no Floor`)
		return
	end
	if ceiling == nil or not ceiling:IsA("BasePart") then
		fail(`{model.Name}: no Ceiling`)
		return
	end
	if not floor.CanCollide then
		fail(`{model.Name}: the Floor does not collide`)
	end
	local floorTop = floor.Position.Y + floor.Size.Y / 2
	local ceilingBottom = ceiling.Position.Y - ceiling.Size.Y / 2
	row.headroom = round(ceilingBottom - floorTop)
	if ceilingBottom - floorTop < BODY + 1 then
		fail(string.format("%s: %.1f st between the floor and the ceiling", model.Name, ceilingBottom - floorTop))
	end
	if #rooms == 0 then
		fail(`{model.Name}: no rooms`)
	end
	if row.lights < #rooms then
		fail(`{model.Name}: {row.lights} lights for {#rooms} rooms`)
	end
	local onlyFloor, onlyCeiling = only(floor), only(ceiling)
	local top = math.min(ceilingBottom - 0.2, floorTop + 8)
	for _, room in rooms do
		local id = tostring(room:GetAttribute("RoomId"))
		local c = room.Position
		local under = workspace:Raycast(Vector3.new(c.X, floorTop + 3, c.Z), Vector3.new(0, -6, 0), onlyFloor)
		if under == nil or math.abs(under.Position.Y - floorTop) > 0.05 then
			fail(`{model.Name}/{id}: no floor under the middle of the room`)
		end
		local over = workspace:Raycast(Vector3.new(c.X, floorTop + 1, c.Z), Vector3.new(0, 80, 0), onlyCeiling)
		if over == nil then
			fail(`{model.Name}/{id}: no ceiling over the middle of the room`)
		end
		-- the ground stays under the floor: nine looks across the room
		local hx, hz = math.max(room.Size.X / 2 - 1.5, 0), math.max(room.Size.Z / 2 - 1.5, 0)
		local worst = 0
		for _, fx in { -1, 0, 1 } do
			for _, fz in { -1, 0, 1 } do
				local p = room.CFrame:PointToWorldSpace(Vector3.new(fx * hx, 0, fz * hz))
				local ground = workspace:Raycast(
					Vector3.new(p.X, top, p.Z),
					Vector3.new(0, -(top - floorTop - 0.1), 0),
					onlyTerrain
				)
				if ground then
					worst = math.max(worst, ground.Position.Y - floorTop)
				end
			end
		end
		if worst > 0 then
			row.terrainOverFloor = math.max(row.terrainOverFloor, round(worst))
			fail(string.format("%s/%s: terrain stands %.2f st above the floor", model.Name, id, worst))
		end
	end
end

for _, m in lotsFolder:GetChildren() do
	if m:IsA("Model") then
		local enterable = m:GetAttribute("Enterable") == true
		local primary = m.PrimaryPart
		local centre = if primary then primary.Position else m:GetPivot().Position
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("DoorId") ~= nil then
				checkDoor(m, d, centre, enterable)
			end
		end
		if enterable then
			enterableCount += 1
			checkBuilding(m)
		end
	end
end
if enterableCount ~= ENTERABLE then
	fail(`{enterableCount} enterable buildings in the town; {ENTERABLE} are baked`)
end
if doorNumbers.exterior == 0 then
	fail("no exterior doors found (no part carries DoorId)")
end
if doorNumbers.openings < enterableCount then
	fail(`{doorNumbers.openings} doorways for {enterableCount} enterable buildings`)
end
doorNumbers.worstOverSill = round(doorNumbers.worstOverSill)
doorNumbers.worstStep = round(doorNumbers.worstStep)

print(
	`interiors_check: {townParts} parts, {doorNumbers.exterior} exterior doors ({doorNumbers.level} level, `
		.. `{doorNumbers.stepped} on steps), {enterableCount} enterable buildings, {#failures} failures`
)
for _, f in failures do
	print("  FAIL " .. f)
end
return {
	suite = "interiors_check",
	ok = #failures == 0,
	failures = failures,
	parts = { town = townParts, baked = bakedParts, budget = PART_BUDGET },
	doors = doorNumbers,
	doorRows = doorRows,
	buildings = buildings,
	terrainSeconds = terrainSeconds,
	placeVersion = game.PlaceVersion,
	elapsedSeconds = os.clock() - started,
}
