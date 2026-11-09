--!strict
-- ServerScriptService.Server.WorldGen.Kits
-- Greybox kit registry (spike S6; W1 #7): one entry per lot type, read from generated/LotTypes
-- (data/authored/lot_types.json, BUILD_PLAN §3.3) plus the greybox look per category. Heights are HTML
-- units read off the v5.4 notes; builders convert to studs. Greybox massing, not final geometry.
-- Interface: get(lotType) -> Kit (unknown types fall back to "marker" so the bake never fails);
--   isSolid(category); known(lotType); routeProps; lamp; ROAD; STUDS_PER_UNIT
-- Pure data (requires generated/LotTypes), no side effects on require.

local Import = require("./Import")

local Kits = {}

-- building:  solid block, CanCollide, LevelOfDetail SLIM, ModelStreamingMode Atomic.
-- structure: solid smaller block (sheds, stalls, towers), CanCollide, LevelOfDetail Automatic.
-- slab:      solid thin deck at `height` above the seat (canopies, docks, footbridges).
-- plate:     flat ground marker 0.2 st thick, no collision (lawns, plazas, pools, parcels).
-- prop:      visual block, no collision (trees as crowns, details, signs, fences, shrubs).
-- marker:    invisible zone, no collision (wires, walkers, ducts, sewer, analytic roofs/stairs).
export type Category = "building" | "structure" | "slab" | "plate" | "prop" | "marker"

export type Kit = {
	category: Category,
	heightU: number, -- block height (or slab top for "slab"), HTML units
	color: { number }, -- RGB 0-255
	material: string, -- Enum.Material name
	lod: string, -- Enum.ModelLevelOfDetail name
	streaming: string, -- Enum.ModelStreamingMode name
	builder: string, -- builder family (Builders/<family>.luau via Plan)
	roof: string?, -- "gable" | "flat" (buildings)
	door: boolean,
	signText: string?,
	skyline: boolean,
}

local STUDS_PER_UNIT = 2.5
Kits.STUDS_PER_UNIT = STUDS_PER_UNIT

local LOOK: { [Category]: { color: { number }, material: string, lod: string, streaming: string } } = {
	building = { color = { 222, 210, 186 }, material = "SmoothPlastic", lod = "SLIM", streaming = "Atomic" },
	structure = { color = { 182, 169, 155 }, material = "SmoothPlastic", lod = "Automatic", streaming = "Atomic" },
	slab = { color = { 117, 96, 75 }, material = "WoodPlanks", lod = "Automatic", streaming = "Atomic" },
	plate = { color = { 118, 147, 119 }, material = "Grass", lod = "Disabled", streaming = "Default" },
	prop = { color = { 88, 111, 91 }, material = "SmoothPlastic", lod = "Disabled", streaming = "Default" },
	marker = { color = { 255, 0, 255 }, material = "ForceField", lod = "Disabled", streaming = "Default" },
}

-- Lot types are data (W1): generated/LotTypes from data/authored/lot_types.json (category, builder
-- family, height in HTML units, roof, door, sign text, Skyline and the LevelOfDetail/streaming flags).
local LotTypes = Import.generated("LotTypes") :: any
Kits.routeProps = LotTypes.routeProps :: { [string]: any }
Kits.lamp = LotTypes.lamp :: { heightU: number, lod: string, streaming: string }

local cache: { [string]: Kit } = {}

function Kits.get(lotType: string): Kit
	local hit = cache[lotType]
	if hit then
		return hit
	end
	local entry = LotTypes.types[lotType]
	local category: Category = if entry then entry.category else "marker"
	local look = LOOK[category]
	local kit: Kit = {
		category = category,
		heightU = if entry then entry.heightU else 1,
		color = look.color,
		material = look.material,
		lod = if entry then entry.lod else look.lod,
		streaming = if entry then entry.streaming else look.streaming,
		builder = if entry then entry.builder else "Marker",
		roof = entry and entry.roof,
		door = entry ~= nil and entry.door == true,
		signText = entry and entry.signText,
		skyline = entry ~= nil and entry.skyline == "box",
	}
	cache[lotType] = kit
	return kit
end

function Kits.isSolid(category: Category): boolean
	return category == "building" or category == "structure" or category == "slab"
end

function Kits.known(lotType: string): boolean
	return LotTypes.types[lotType] ~= nil
end

-- Road kinds -> look; heights are the v5.4 vertical offsets over terrain [worldgen_core §5].
Kits.ROAD = {
	asphalt = { color = { 146, 148, 147 }, material = "Asphalt", offsetU = 0.055, canCollide = true },
	concrete = { color = { 196, 192, 182 }, material = "Concrete", offsetU = 0.09, canCollide = true },
	cobble = { color = { 160, 146, 128 }, material = "Cobblestone", offsetU = 0.09, canCollide = true },
	path = { color = { 170, 160, 140 }, material = "Slate", offsetU = 0.06, canCollide = true },
	rail = { color = { 90, 86, 80 }, material = "Metal", offsetU = 0.12, canCollide = false },
} :: { [string]: { color: { number }, material: string, offsetU: number, canCollide: boolean } }

return Kits
