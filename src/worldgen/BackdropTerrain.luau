--!strict
-- ServerScriptService.Server.WorldGen.BackdropTerrain (engine only: Lune cannot write voxels)
-- The boot terrain beyond the town (BUILD_PLAN W6 #1, worldgen_districts_art §14.4, brief v2 §3 Backdrop): after
-- WorldGen/WorldTerrain, writes World/Backdrop's terrain rectangles with WorldGen/TerrainBake:
--   * the band BAND st beyond the world clamp on the south and both sides, continuous with World/Height at the
--     clamp edge and settling onto the backdrop's land mesh (Workspace.Backdrop.Land, which carries on beyond);
--   * the north strip from NORTH_FROM_Z: the long beach running down to the waterline, rocky where the coast
--     cuts the ridge's end, and the sandy sea floor under Terrain water out to WATER_TO_Z (beyond the shallows
--     the Persistent ocean plane of Workspace.Backdrop lies just under the water surface and carries on to the
--     horizon).
-- Also sets the water look (worldgen_districts_art §14.2: WaterColor #315c61, reflectance 0.4, transparency 0.3,
-- wave size 0.1, wave speed 6) and the Rock colour. Called by Server/Boot/Game right after WorldTerrain.write.
-- Interface: write(terrain, opts?) -> { seconds, voxels, columns, rects }
-- No side effects on require.

local Import = require("./Import")
local TerrainBake = require("./TerrainBake")
local Height = Import.shared("World/Height") :: typeof(require("../shared/World/Height"))
local Backdrop = Import.shared("World/Backdrop") :: typeof(require("../shared/World/Backdrop"))

local BackdropTerrain = {}

BackdropTerrain.WATER = table.freeze({
	color = "315c61",
	reflectance = 0.4,
	transparency = 0.3,
	waveSize = 0.1,
	waveSpeed = 6,
})
BackdropTerrain.ROCK_COLOR = "8c877c"

function BackdropTerrain.write(terrain: Terrain, opts: { chunk: number? }?): { [string]: any }
	local o: { chunk: number? } = opts or {}
	local t0 = os.clock()
	Height.configure(Import.generated("TerrainExtensions"))
	Backdrop.reset()
	local w = BackdropTerrain.WATER
	pcall(function()
		terrain.WaterColor = Color3.fromHex(w.color)
		terrain.WaterReflectance = w.reflectance
		terrain.WaterTransparency = w.transparency
		terrain.WaterWaveSize = w.waveSize
		terrain.WaterWaveSpeed = w.waveSpeed
		terrain:SetMaterialColor(Enum.Material.Rock, Color3.fromHex(BackdropTerrain.ROCK_COLOR))
	end)
	local materials: { [string]: Enum.Material } = {
		Sand = Enum.Material.Sand,
		Grass = Enum.Material.Grass,
		Rock = Enum.Material.Rock,
	}
	-- TerrainBake asks for a column's height and then its material: one sample serves both
	local lx, lz, lland, lt, ld = math.huge, math.huge, 0, 0, 0
	local function heightAt(x: number, z: number): number
		local h, land, t, d = Backdrop.sample(x, z)
		lx, lz, lland, lt, ld = x, z, land, t, d
		return h
	end
	local function materialAt(x: number, z: number, h: number): Enum.Material
		if x ~= lx or z ~= lz then
			heightAt(x, z)
		end
		return materials[Backdrop.materialFor(x, z, h, lland, lt, ld)] or Enum.Material.Grass
	end
	local sea = Backdrop.SEA_Y
	local function waterTopAt(_x: number, _z: number): number?
		return sea
	end
	local stats = { seconds = 0, voxels = 0, columns = 0, rects = 0, maxTopY = -math.huge }
	for _, r in Backdrop.terrainRects() do
		local st = TerrainBake.write(terrain, {
			rect = { minX = r.minX, maxX = r.maxX, minZ = r.minZ, maxZ = r.maxZ },
			heightAt = heightAt,
			waterTopAt = if r.water then waterTopAt else nil,
			materialAt = materialAt,
			chunk = o.chunk,
		})
		stats.voxels += st.voxels
		stats.columns += st.columns
		stats.rects += 1
		stats.maxTopY = math.max(stats.maxTopY, st.maxTopY)
	end
	stats.seconds = os.clock() - t0
	return stats
end

return BackdropTerrain
