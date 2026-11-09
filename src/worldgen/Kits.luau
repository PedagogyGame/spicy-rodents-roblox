--!strict
-- ServerScriptService.Server.WorldGen.Kits
-- Greybox kit registry (spike S6, W0): one entry per lot type present in generated/Lots, giving the
-- greybox category, height and look. Heights are HTML units read off the v5.4 notes (eaves, roof
-- tops, slab heights) and converted to studs here; they are greybox massing, not final geometry.
-- W1 replaces this table with data/lot_types/*.json (BUILD_PLAN §3.2-§3.3); the categories stay.
-- Interface: get(lotType) -> Kit (unknown types fall back to "marker" so the bake never fails).
-- Pure data, no side effects on require.

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

-- type -> { category, heightU }
local TYPES: { [string]: { any } } = {
	-- buildings
	house = { "building", 11 },
	quay_building = { "building", 12 },
	mall = { "building", 22.94 },
	mall_shop = { "building", 6.35 },
	guesthouse = { "building", 6 },
	restaurant = { "building", 7 },
	restaurant_icecream = { "building", 5 },
	shop = { "building", 6 },
	hospital = { "building", 13.34 },
	police_station = { "building", 9 },
	gas_station = { "building", 6 },
	estate_mansion = { "building", 14 },
	chapel_crypt = { "building", 9 },
	shelter_house = { "building", 5 },
	storage_units = { "building", 4 },
	triage_bay = { "building", 4.4 },
	treatment_ward = { "building", 4.4 },
	waiting_room = { "building", 4.4 },
	reception = { "building", 4.4 },
	supply_room = { "building", 4.4 },
	observation_room = { "building", 4.4 },
	atrium = { "building", 14 },
	-- structures
	landmark_tower = { "structure", 30 },
	bridge_tower = { "structure", 20 },
	shed = { "structure", 3 },
	doghouse = { "structure", 1.5 },
	backyard_doghouse = { "structure", 1.5 },
	treehouse = { "structure", 4 },
	gazebo = { "structure", 4 },
	pergola_summer_kitchen = { "structure", 3.5 },
	transit_stop = { "structure", 3 },
	shelter = { "structure", 1.5 },
	market_stall = { "structure", 4 },
	fountain = { "structure", 1.12 },
	backyard_trampoline = { "structure", 1.65 },
	-- slabs
	gas_canopy = { "slab", 10.74 },
	porte_cochere = { "slab", 8.1 },
	dock = { "slab", 0.5 },
	footbridge = { "slab", 0.78 },
	-- plates
	district_ground = { "plate", 0 },
	lawn = { "plate", 0 },
	plaza = { "plate", 0 },
	garden = { "plate", 0 },
	community_garden = { "plate", 0 },
	park = { "plate", 0 },
	playground = { "plate", 0 },
	parking = { "plate", 0 },
	sports_field = { "plate", 0 },
	tennis_court = { "plate", 0 },
	cemetery = { "plate", 0 },
	intersection = { "plate", 0 },
	path = { "plate", 0 },
	river = { "plate", 0 },
	stream = { "plate", 0 },
	pond = { "plate", 0 },
	estate_parcel = { "plate", 0 },
	estate_pool = { "plate", 0 },
	backyard_pool = { "plate", 0 },
	ambulance_bay = { "plate", 0 },
	bridge = { "plate", 0 },
	-- props
	tree = { "prop", 19 },
	detail = { "prop", 1.2 },
	sign = { "prop", 3.2 },
	shrub_cluster = { "prop", 1.5 },
	fence_run = { "prop", 1.2 },
	backyard_prop = { "prop", 1 },
	-- markers
	overhead_lines = { "marker", 15 },
	ambient_npcs = { "marker", 2 },
	street_furniture = { "marker", 4 },
	roof = { "marker", 0.75 },
	stair = { "marker", 6.46 },
	mezzanine = { "marker", 0.5 },
	duct = { "marker", 1.76 },
	sewer = { "marker", 2 },
}

local cache: { [string]: Kit } = {}

function Kits.get(lotType: string): Kit
	local hit = cache[lotType]
	if hit then
		return hit
	end
	local entry = TYPES[lotType] or { "marker", 1 }
	local category = entry[1] :: Category
	local look = LOOK[category]
	local kit: Kit = {
		category = category,
		heightU = entry[2] :: number,
		color = look.color,
		material = look.material,
		lod = look.lod,
		streaming = look.streaming,
	}
	cache[lotType] = kit
	return kit
end

function Kits.isSolid(category: Category): boolean
	return category == "building" or category == "structure" or category == "slab"
end

function Kits.known(lotType: string): boolean
	return TYPES[lotType] ~= nil
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
