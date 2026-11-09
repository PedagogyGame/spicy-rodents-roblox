--!strict
-- ServerScriptService.Server.WorldGen.WorldTerrain (engine only: Lune cannot write voxels)
-- Boot-time terrain (BUILD_PLAN §4.4 #7 "TerrainBake at boot", D6, D32): configures World/Height with
-- Generated.TerrainExtensions, then writes the v5.4 rectangle (river water and mud bed, road
-- materials painted under axis roads) and the D32 patches (hill, ridge, back field, long beach) with
-- TerrainBake. WorldBoot calls write(workspace.Terrain) once when Terrain's BakeHash attribute is
-- stale (S6: about 1 s for the town and 1 s for the extensions in Luau Execution).
-- Interface: write(terrain, opts?) -> { town = Stats, extensions = Stats, seconds }

local Import = require("./Import")
local TerrainBake = require("./TerrainBake")
local Height = Import.shared("World/Height") :: typeof(require("../shared/World/Height"))

local WorldTerrain = {}

local ROAD_MATERIAL = { asphalt = "Asphalt", concrete = "Concrete", cobble = "Cobblestone", path = "Slate" }

-- v5.4 ground colours (worldgen_districts_art §11: grass #819762 under the #a2b78b tint, road #929493
-- tint over #555b5b grain, sidewalk #c3beb1, quay cobble tint #c4bdab, sand, mud bank).
local MATERIAL_COLORS: { [string]: string } = {
	Grass = "8a9f63",
	Asphalt = "4b5153",
	Concrete = "c3beb1",
	Cobblestone = "c4bdab",
	Slate = "b5a888",
	Mud = "6f6450",
	Sand = "d8c9a3",
	Ground = "8c7a5d",
}

function WorldTerrain.colour(terrain: Terrain)
	for name, h in MATERIAL_COLORS do
		pcall(function()
			terrain:SetMaterialColor((Enum.Material :: any)[name], Color3.fromHex(h))
		end)
	end
end

function WorldTerrain.write(terrain: Terrain, opts: { chunk: number? }?): { [string]: any }
	local o = opts or {}
	local t0 = os.clock()
	WorldTerrain.colour(terrain)
	Height.configure(Import.generated("TerrainExtensions"))
	local spu = Height.STUDS_PER_UNIT
	local P = Height.PLAYABLE_U
	local minX, maxX, minZ, maxZ = P.minX * spu, P.maxX * spu, P.minZ * spu, P.maxZ * spu
	local paint = {}
	for _, r in Import.generated("Roads") do
		local m = ROAD_MATERIAL[r.kind]
		if m and (r.axis == "x" or r.axis == "z") then
			local a, b = math.min(r.start, r["end"]), math.max(r.start, r["end"])
			local hw = r.width / 2
			local mat = (Enum.Material :: any)[m]
			if r.axis == "x" then
				table.insert(paint, { minX = a, maxX = b, minZ = r.coord - hw, maxZ = r.coord + hw, material = mat })
			else
				table.insert(paint, { minX = r.coord - hw, maxX = r.coord + hw, minZ = a, maxZ = b, material = mat })
			end
		end
	end
	local town = TerrainBake.write(terrain, {
		rect = { minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ },
		heightAt = Height.at,
		waterTopAt = function(x: number, z: number): number?
			return if Height.insideRiverWater(x, z) then Height.WATER_Y else nil
		end,
		materialAt = function(x: number, z: number, _h: number): Enum.Material
			return if Height.insideRiverWater(x, z) then Enum.Material.Mud else Enum.Material.Grass
		end,
		paint = paint,
		chunk = o.chunk,
	})
	local clamp = Height.worldClamp()
	local function extMaterial(x: number, z: number, _h: number): Enum.Material
		return if Height.extensionMaterial(x, z) == "Sand" then Enum.Material.Sand else Enum.Material.Grass
	end
	local ext = { seconds = 0, voxels = 0, columns = 0 }
	for _, r in
		{
			{ minX = clamp.minX, maxX = maxX, minZ = maxZ, maxZ = clamp.maxZ }, -- north (long beach)
			{ minX = maxX, maxX = clamp.maxX, minZ = clamp.minZ, maxZ = clamp.maxZ }, -- east (ridge, back field)
			{ minX = clamp.minX, maxX = maxX, minZ = clamp.minZ, maxZ = minZ }, -- south (sky-lift hill)
			{ minX = clamp.minX, maxX = minX, minZ = minZ, maxZ = maxZ }, -- west
		}
	do
		local st =
			TerrainBake.write(terrain, { rect = r, heightAt = Height.at, materialAt = extMaterial, chunk = o.chunk })
		ext.seconds += st.seconds
		ext.voxels += st.voxels
		ext.columns += st.columns
	end
	return { town = town, extensions = ext, seconds = os.clock() - t0 }
end

return WorldTerrain
