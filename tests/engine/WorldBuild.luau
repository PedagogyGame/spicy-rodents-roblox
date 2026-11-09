--!strict
-- ServerStorage.EngineTests.WorldBuild (CI place only; spike S6, BUILD_PLAN §6.5 WorldBuild + BakeParity)
-- Against the saved place's Workspace.Town (the Lune bake, build/Town.rbxm):
--   counts:    lot Models == #Generated.Lots, road Models == #Generated.Roads
--   overlaps:  no 3-D overlap between solid lot greyboxes (engine CFrame/Size, 0.05 st tolerance)
--   parity:    Bake.plans(Generated) hashed in the engine == Town.BakeHash (Lune);
--              Bake.instanceHash(Workspace.Town) == Town.InstanceHash (the .rbxm round trip);
--              a full engine-side Bake.run gives the same InstanceHash (and is timed)
--   requires:  first-require time of every Generated chunk (largest < 100 ms)
-- terrain(which): TerrainBake timing for "town" (the v5.4 playable rectangle from World/Height)
-- or "bands" (near-hill backdrop band, 0-2 km beyond the south and west play edges, stand-in hills).

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

	-- 4. BakeParity
	local Bake = worldgen("Bake")
	local Factory = worldgen("Factory")
	local data = { lots = lots, roads = roads }
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
	if freshHash ~= town:GetAttribute("InstanceHash") or placedHash ~= town:GetAttribute("InstanceHash") then
		-- evidence for the diff: the first lines of each side (compare with the Lune bake locally)
		local a, b = Bake.instanceLines(town), Bake.instanceLines(fresh)
		result.sampleLines = { placed = { a[1], a[2], a[3], a[#a] }, engine = { b[1], b[2], b[3], b[#b] } }
	end
	fresh:Destroy()
	result.parity = {
		lunePlanHash = town:GetAttribute("BakeHash"),
		enginePlanHash = planHash,
		luneInstanceHash = town:GetAttribute("InstanceHash"),
		placedInstanceHash = placedHash,
		engineBakeInstanceHash = freshHash,
		planMs = tPlan * 1000,
		instanceHashMs = tInst * 1000,
		engineBakeMs = tRun * 1000,
	}
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
			return edge + smooth((d - 150) / 900) * hills
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

return WorldBuild
