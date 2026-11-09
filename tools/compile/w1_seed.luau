--!strict
-- tools/compile/w1_seed.luau: one-off W1 seeding of lot `params`, `seat` and `home` from the v5.4
-- harvest (BUILD_PLAN §3.2, §4.4 #7). Run once from the repository root:
--   lune run tools/compile/w1_seed.luau
-- After W1, data/authored/town/lots/*.json is hand-edited data (§3.1 "migrates once; new content is
-- added by hand"); this script is kept for provenance and is idempotent (it overwrites the same keys).
-- Sources: data/harvest/houses.json (houses[0..23]: core cfg eave/peak, outer homes with their
-- terrain base; riverBuildings: quay h/rise/base/name; commercialBounds: flat landable roofs) and the
-- harvested roof routes (ridge axis). Heights in params are HTML units above the seat (x-unit u).
local fs = require("@lune/fs")
local Json = require("./lib/Json")
local Migrate = require("./lib/Migrate")
local Height = require("../../src/shared/World/Height")

local DIR = "data/authored/town/lots"
local houses = Json.decodeFile("data/harvest/houses.json")
local routes = Json.decodeFile("data/harvest/routes.json").routes

local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 0.01)
end

-- 3-decimal rounding keeps authored numbers short (the harvest has 17 digits)
local function r3(x: number): number
	return math.floor(x * 1000 + 0.5) / 1000
end

-- ridge axis from the nearest harvested roof route over the footprint
local function ridgeAxis(x: number, z: number, fallback: string): string
	local best, bestD = nil, math.huge
	for _, r in routes do
		if r.kind == "roof" then
			local p0, p1 = r.points[1], r.points[#r.points]
			local mx, mz = (p0[1] + p1[1]) / 2, (p0[3] + p1[3]) / 2
			local d = (mx - x) ^ 2 + (mz - z) ^ 2
			if d < bestD then
				best, bestD = r, d
			end
		end
	end
	if best and bestD < 15 * 15 then
		local p0, p1 = best.points[1], best.points[#best.points]
		return if math.abs(p1[1] - p0[1]) >= math.abs(p1[3] - p0[3]) then "x" else "z"
	end
	return fallback
end

local SIGNS: { [string]: string } = {
	quay_sign_entry = "BELLWETHER QUAY",
	quay_sign_river = "WILLOW RIVER",
	quay_sign_market = "QUAY MARKET",
	east_fuel_price_tower = "FUEL",
	north_sign_park_cemetery = "SYCAMORE PARK",
	east_chilis_restaurant = "CHILI'S",
	east_corner_shops = "CORNER SHOPS",
	west_police_station = "WEST TOPEKA POLICE",
	hospital_main = "HOSPITAL",
	west_storage_units = "WESTSIDE STORAGE",
	galleria_building = "BELLWETHER GALLERIA",
}

-- the four FRB houses (BUILD_PLAN §3.4: the schema and Interior builder exist from W1 for them)
local HOMES: { [string]: string } = {
	core_house_0_victorian = "frb_victorian",
	core_house_1_bungalow = "frb_bungalow",
	core_house_2_brick = "frb_brick",
	core_house_3_blue_cottage = "frb_cottage",
}

local seeded = 0
for _, f in fs.readDir(DIR) do
	local path = DIR .. "/" .. f
	local doc = Json.decodeFile(path)
	for _, lot in doc.lots do
		local params = lot.params or {}
		local touched = false
		for i = 1, 24 do
			local h = houses.houses[i]
			if lot.type == "house" and near(h.x, lot.x) and near(h.z, lot.z) then
				local base = h.g.position[2]
				params.eaveU = r3(h.cfg.h - base)
				params.peakU = r3(h.cfg.peak - base)
				-- outer homes: the v5.4 landing is the flat commercialBounds-style roof at the ridge
				-- height (routes_movement verifier 4); core houses are real gables.
				params.roof = if i <= 4 then "gable" else "flat"
				params.ridge = ridgeAxis(lot.x, lot.z, "x")
				if i > 4 then
					lot.seat = "absolute:" .. tostring(r3(base))
				end
				touched = true
			end
		end
		for _, b in houses.riverBuildings do
			if lot.type == "quay_building" and near(b.x, lot.x) and near(b.z, lot.z) then
				params.eaveU = b.h
				params.peakU = r3(b.h + b.rise)
				params.roof = "gable"
				params.ridge = if math.abs(math.sin(b.rotation)) > 0.5 then "z" else "x"
				params.sign = b.name
				lot.seat = "absolute:" .. tostring(b.base)
				touched = true
			end
		end
		for _, c in houses.commercialBounds do
			if near(c.x, lot.x) and near(c.z, lot.z) and lot.type ~= "house" then
				params.eaveU = r3(c.roof - Height.atU(c.x, c.z))
				params.roof = "flat"
				touched = true
			end
		end
		if SIGNS[lot.id] then
			params.sign = SIGNS[lot.id]
			touched = true
		end
		if HOMES[lot.id] then
			lot.home = { interior = HOMES[lot.id], claimable = true, backExit = true, hideSpots = 3 }
			touched = true
		end
		if touched then
			lot.params = params
			seeded += 1
		end
	end
	Json.writeFile(path, doc, { keyOrder = Migrate.KEY_ORDER })
end
print(`w1_seed: params/seat/home on {seeded} lots`)
