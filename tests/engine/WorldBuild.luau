--!strict
-- ServerStorage.EngineTests.WorldBuild (CI place only; spike S6 + W1 #7, BUILD_PLAN §4.4 exit
-- criteria, §6.5 WorldBuild + BakeParity)
-- Against the saved place's Workspace.Town (the Lune bake, build/Town.rbxm):
--   counts:    lot Models == #Generated.Lots, road Models == #Generated.Roads
--   W1 checks: WorldGen.WorldChecks on engine-computed plans (routes on geometry except
--              harvest_patches, doors reachable from a sidewalk, no solid overlap, Skyline for every
--              building, hospital rooms, drone console), plus the placed Town: a Skyline part per
--              building, the hospital's Room_ volumes, the station console, server-owned doors
--   overlaps:  no 3-D overlap between solid lot greyboxes (engine CFrame/Size, 0.05 st tolerance)
--   parity:    Bake.plans(Generated) hashed in the engine == Town.BakeHash (Lune);
--              Bake.instanceHash(Workspace.Town) == Town.InstanceHash (structure after the .rbxm
--              round trip); a full engine-side Bake.run gives the same InstanceHash (and is timed),
--              and its geometry matches the placed Town within 1e-3 st
--   requires:  first-require time of every Generated chunk (largest < 100 ms)
-- terrain(which): TerrainBake timing for "town" (the v5.4 playable rectangle from World/Height),
-- "extensions" (the D32 patches from Generated.TerrainExtensions) or "bands" (near-hill backdrop
-- band, 0-2 km beyond the south and west play edges, stand-in hills).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local WorldBuild = {}

local function child(parent: Instance, ...: string): Instance
	local node = parent
	for _, name in { ... } do
		node = node:FindFirstChild(name) or error(`WorldBuild: {node:GetFullName()}.{name} missing`)
	end
	return node
end

local function req(inst: Instance): any
	return (require :: any)(inst)
end

local function generated(): Instance
	return child(ReplicatedStorage, "Shared", "Generated")
end

local function worldgen(name: string): any
	return req(child(ServerScriptService, "Server", "WorldGen", name))
end

local function aabb(p: BasePart): (Vector3, Vector3)
	local cf, s = p.CFrame, p.Size
	local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
	local ex = Vector3.new(
		math.abs(r.X) * s.X + math.abs(u.X) * s.Y + math.abs(l.X) * s.Z,
		math.abs(r.Y) * s.X + math.abs(u.Y) * s.Y + math.abs(l.Y) * s.Z,
		math.abs(r.Z) * s.X + math.abs(u.Z) * s.Y + math.abs(l.Z) * s.Z
	) / 2
	return cf.Position - ex, cf.Position + ex
end

function WorldBuild.requires(): { [string]: number }
	local out: { [string]: number } = {}
	for _, m in generated():GetChildren() do
		if m:IsA("ModuleScript") then
			local t0 = os.clock()
			req(m)
			out[m.Name] = (os.clock() - t0) * 1000
		end
	end
	return out
end

function WorldBuild.run(): { [string]: any }
	local result: { [string]: any } = { failures = {} }
	local function fail(msg: string)
		table.insert(result.failures, msg)
	end

	-- 1. first-require times (before anything else touches Generated)
	local reqMs = WorldBuild.requires()
	local worst, worstName = 0, ""
	for name, ms in reqMs do
		if ms > worst then
			worst, worstName = ms, name
		end
	end
	result.requireMs = reqMs
	result.largestRequire = { name = worstName, ms = worst }
	if worst >= 100 then
		fail(`require {worstName} took {worst} ms (>= 100)`)
	end

	local gen = generated()
	local lots = req(child(gen, "Lots"))
	local roads = req(child(gen, "Roads"))

	-- 2. counts
	local town = workspace:FindFirstChild("Town")
	if not town then
		fail("Workspace.Town missing (place saved without build/Town.rbxm)")
		result.ok = false
		return result
	end
	local lotModels = child(town, "Lots"):GetChildren()
	local roadModels = child(town, "Roads"):GetChildren()
	result.counts = { lots = #lotModels, dataLots = #lots, roads = #roadModels, dataRoads = #roads }
	if #lotModels ~= #lots then
		fail(`lot count {#lotModels} ~= data {#lots}`)
	end
	if #roadModels ~= #roads then
		fail(`road count {#roadModels} ~= data {#roads}`)
	end

	-- 3. solid overlaps (and every lot Model has its PrimaryPart and LevelOfDetail)
	local solids: { BasePart } = {}
	local lod: { [string]: number } = {}
	for _, m in lotModels do
		local model = m :: Model
		local pp = model.PrimaryPart
		if not pp then
			fail(`{model.Name}: no PrimaryPart`)
		elseif model:GetAttribute("Solid") == true then
			if not pp.CanCollide or not pp.Anchored then
				fail(`{model.Name}: solid greybox not anchored+CanCollide`)
			end
			table.insert(solids, pp)
		end
		lod[model.LevelOfDetail.Name] = (lod[model.LevelOfDetail.Name] or 0) + 1
	end
	result.levelOfDetail = lod
	local overlaps: { string } = {}
	for i = 1, #solids do
		local a0, a1 = aabb(solids[i])
		for j = i + 1, #solids do
			local b0, b1 = aabb(solids[j])
			local o = a1:Min(b1) - a0:Max(b0)
			if o.X > 0.05 and o.Y > 0.05 and o.Z > 0.05 then
				table.insert(overlaps, `{(solids[i].Parent :: Instance).Name} x {(solids[j].Parent :: Instance).Name}`)
			end
		end
	end
	result.solids = #solids
	result.overlaps = overlaps
	if #overlaps > 0 then
		fail(`{#overlaps} solid overlaps`)
	end

	-- 4. W1 exit checks on engine-computed plans, then on the placed Town
	local Bake = worldgen("Bake")
	local Factory = worldgen("Factory")
	local WorldChecks = worldgen("WorldChecks")
	local data = Bake.data()
	local tc = os.clock()
	local checks = WorldChecks.run(data)
	result.checks = {
		ok = checks.ok,
		failures = checks.failures,
		routes = {
			checked = checks.routes.checked,
			samples = checks.routes.samples,
			offGeometry = #checks.routes.failures,
			patchedStillOff = checks.routes.patchedFailing,
		},
		doors = { doors = checks.doors.doors, unreachable = #checks.doors.unreachable },
		solids = checks.solids,
		overlaps = #checks.overlaps,
		skylineBuildings = checks.skyline.buildings,
		hospitalRooms = checks.hospitalRooms,
		droneConsole = checks.droneConsole,
		ms = (os.clock() - tc) * 1000,
	}
	for _, f in checks.failures do
		fail("WorldChecks: " .. f)
	end
	local skyline = town:FindFirstChild("Skyline")
	local lotsFolder = child(town, "Lots")
	local placedMissing = 0
	for _, m in lotModels do
		local model = m :: Model
		local cat = model:GetAttribute("Category")
		if (cat == "building" or cat == "structure") and not (skyline and skyline:FindFirstChild(model.Name)) then
			placedMissing += 1
		end
	end
	if not skyline or placedMissing > 0 then
		fail(`placed Skyline missing for {placedMissing} buildings`)
	end
	local hosp = lotsFolder:FindFirstChild("hospital_main")
	local rooms = 0
	for _, id in { "reception", "triage", "ward_a", "ward_b", "isolation", "pharmacy", "staff_room", "ambulance_bay" } do
		if hosp and hosp:FindFirstChild("Room_" .. id) then
			rooms += 1
		end
	end
	local station = lotsFolder:FindFirstChild("west_police_station")
	local console = station and station:FindFirstChild("Station_drone_console")
	local doors, serverOwned = 0, 0
	for _, d in town:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("DoorId") ~= nil then
			doors += 1
			if d:GetAttribute("ServerOwned") == true then
				serverOwned += 1
			end
		end
	end
	result.placed =
		{ hospitalRooms = rooms, droneConsole = console ~= nil, doors = doors, serverOwnedDoors = serverOwned }
	if rooms ~= 8 then
		fail(`placed hospital has {rooms} of 8 brief rooms`)
	end
	if not console then
		fail("placed police station has no drone console")
	end
	if doors == 0 or serverOwned ~= doors then
		fail(`server-owned doors {serverOwned} of {doors}`)
	end

	-- 5. BakeParity
	local t0 = os.clock()
	local planHash = Bake.hash(Bake.plans(data))
	local tPlan = os.clock() - t0
	local t1 = os.clock()
	local placedHash = Bake.instanceHash(town)
	local tInst = os.clock() - t1
	local t2 = os.clock()
	local fresh = Bake.run(data, Factory.new(Factory.engineEnv()))
	local tRun = os.clock() - t2
	local freshHash = fresh:GetAttribute("InstanceHash")
	local geomDelta, geomAt = Bake.maxGeometryDelta(Bake.geometry(town), Bake.geometry(fresh))
	fresh:Destroy()
	result.parity = {
		lunePlanHash = town:GetAttribute("BakeHash"),
		enginePlanHash = planHash,
		luneInstanceHash = town:GetAttribute("InstanceHash"),
		placedInstanceHash = placedHash,
		engineBakeInstanceHash = freshHash,
		geometryMaxDelta = geomDelta,
		geometryMaxDeltaAt = geomAt,
		planMs = tPlan * 1000,
		instanceHashMs = tInst * 1000,
		engineBakeMs = tRun * 1000,
	}
	if geomDelta > 1e-3 then
		fail(`BakeParity: placed geometry differs from an engine-side bake by {geomDelta} at {geomAt}`)
	end
	if planHash ~= town:GetAttribute("BakeHash") then
		fail("BakeParity: engine plan hash differs from the Lune BakeHash")
	end
	if placedHash ~= town:GetAttribute("InstanceHash") then
		fail("BakeParity: placed Town instance hash differs from the Lune InstanceHash")
	end
	if freshHash ~= town:GetAttribute("InstanceHash") then
		fail("BakeParity: engine-side bake instance hash differs from the Lune InstanceHash")
	end
	result.ok = #result.failures == 0
	return result
end

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

function WorldBuild.terrain(which: string, opts: { chunk: number?, clear: boolean? }?): { [string]: any }
	local Height = req(child(ReplicatedStorage, "Shared", "World", "Height"))
	local TerrainBake = worldgen("TerrainBake")
	local terrain = workspace.Terrain
	local o = opts or {}
	if o.clear then
		terrain:Clear()
	end
	local P = Height.PLAYABLE_U
	local spu = Height.STUDS_PER_UNIT
	local minX, maxX, minZ, maxZ = P.minX * spu, P.maxX * spu, P.minZ * spu, P.maxZ * spu
	local stats
	if which == "town" then
		local roads = req(child(generated(), "Roads"))
		local paint = {}
		local mats = {
			asphalt = Enum.Material.Asphalt,
			concrete = Enum.Material.Concrete,
			cobble = Enum.Material.Cobblestone,
			path = Enum.Material.Slate,
		}
		for _, r in roads do
			local m = mats[r.kind]
			if m and (r.axis == "x" or r.axis == "z") then
				local a, b = math.min(r.start, r["end"]), math.max(r.start, r["end"])
				local hw = r.width / 2
				if r.axis == "x" then
					table.insert(paint, { minX = a, maxX = b, minZ = r.coord - hw, maxZ = r.coord + hw, material = m })
				else
					table.insert(paint, { minX = r.coord - hw, maxX = r.coord + hw, minZ = a, maxZ = b, material = m })
				end
			end
		end
		local mud = Enum.Material.Mud
		local grass = Enum.Material.Grass
		stats = TerrainBake.write(terrain, {
			rect = { minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ },
			heightAt = Height.at,
			waterTopAt = function(x: number, z: number): number?
				return if Height.insideRiverWater(x, z) then Height.WATER_Y else nil
			end,
			materialAt = function(x: number, z: number, _h: number): Enum.Material
				return if Height.insideRiverWater(x, z) then mud else grass
			end,
			paint = paint,
			chunk = o.chunk,
		})
		stats.paintRects = #paint
	elseif which == "extensions" then
		-- D32: the authored patches outside the verbatim rectangle (hill, ridge, back field, long beach)
		Height.configure(req(child(generated(), "TerrainExtensions")))
		local clamp = Height.worldClamp()
		local grass, sand = Enum.Material.Grass, Enum.Material.Sand
		local function materialAt(x: number, z: number, _h: number): Enum.Material
			return if Height.extensionMaterial(x, z) == "Sand" then sand else grass
		end
		local rects = {
			{ minX = -320 * spu, maxX = maxX, minZ = maxZ, maxZ = clamp.maxZ }, -- long beach (north)
			{ minX = maxX, maxX = clamp.maxX, minZ = minZ, maxZ = clamp.maxZ }, -- ridge, back field, beach east
			{ minX = -620 * spu, maxX = -220 * spu, minZ = clamp.minZ, maxZ = minZ }, -- sky-lift hill
		}
		stats = { seconds = 0, voxels = 0, columns = 0, parts = {} }
		for _, r in rects do
			local st =
				TerrainBake.write(terrain, { rect = r, heightAt = Height.at, materialAt = materialAt, chunk = o.chunk })
			stats.seconds += st.seconds
			stats.voxels += st.voxels
			stats.columns += st.columns
			table.insert(stats.parts, st.seconds)
		end
	elseif which == "bands" then
		-- Stand-in near-hill band (worldgen_districts_art §14.4: Terrain 0.5-2 km beyond the play
		-- edge; owner decision 7 puts hills south and west). The 0-0.5 km apron is written too so the
		-- ground is continuous. Heights rise from the edge height to rolling hills of 60-200 st.
		local band = 2000
		local function heightAt(x: number, z: number): number
			local ex, ez = math.clamp(x, minX, maxX), math.clamp(z, minZ, maxZ)
			local d = math.max(minX - x, minZ - z, 0)
			local edge = Height.at(ex, ez)
			local hills = 130
				+ 70 * math.sin(x * 0.0021 + 0.7) * math.cos(z * 0.0017 - 0.4)
				+ 25 * math.sin(x * 0.011 + z * 0.007)
			local h = edge + smooth((d - 150) / 900) * hills
			-- the D32 patches (once configured) win where they apply, so the band never cuts the hill
			if Height.extensionMaterial(x, z) ~= nil then
				return math.max(h, Height.at(x, z))
			end
			return h
		end
		local s1 = TerrainBake.write(terrain, {
			rect = { minX = minX - band, maxX = minX, minZ = minZ - band, maxZ = maxZ },
			heightAt = heightAt,
			chunk = o.chunk,
		})
		local s2 = TerrainBake.write(terrain, {
			rect = { minX = minX, maxX = maxX, minZ = minZ - band, maxZ = minZ },
			heightAt = heightAt,
			chunk = o.chunk,
		})
		stats = {
			west = s1,
			south = s2,
			seconds = s1.seconds + s2.seconds,
			voxels = s1.voxels + s2.voxels,
			columns = s1.columns + s2.columns,
		}
	else
		error("WorldBuild.terrain: unknown region " .. which)
	end
	return stats
end

-- Read back what TerrainBake wrote: the voxel column at (x, z) in studs, bottom-up, as
-- "Material:occupancy" strings from y0 to y1, plus Terrain:CountCells().
function WorldBuild.probe(points: { { number } }, y0: number, y1: number): { [string]: any }
	local terrain = workspace.Terrain
	local out: { [string]: any } = { cells = terrain:CountCells() }
	for _, pt in points do
		local x, z = math.floor(pt[1] / 4) * 4, math.floor(pt[2] / 4) * 4
		local region = Region3.new(Vector3.new(x, y0, z), Vector3.new(x + 4, y1, z + 4))
		local mats, occs = terrain:ReadVoxels(region, 4)
		local col: { string } = {}
		for j = 1, #mats[1] do
			table.insert(col, `{mats[1][j][1].Name}:{string.format("%.2f", occs[1][j][1])}`)
		end
		out[`{pt[1]},{pt[2]}`] = table.concat(col, " ")
	end
	return out
end

return WorldBuild
