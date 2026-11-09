--!strict
-- One-time migration of the verified spec extraction (spec/data/*.json) into the authored data
-- layout (data/authored/**, schema shape of data/schema/*.schema.json). Re-runnable: it rebuilds
-- every file from the spec; once hand edits start in data/authored, run `migrate --check` only.
local Json = require("./Json")

local Migrate = {}

export type Output = { [string]: any } -- relative path -> value to encode

local KEY_ORDER = {
	"$schema",
	"id",
	"name",
	"district",
	"type",
	"generator",
	"kind",
	"line",
	"x",
	"z",
	"y",
	"facing",
	"yaw",
	"footprint",
	"axis",
	"coord",
	"start",
	"end",
	"width",
	"roads",
	"roadNote",
	"path",
	"dir",
	"users",
	"speed",
	"count",
	"formula",
}
Migrate.KEY_ORDER = KEY_ORDER

local function src(line: any): string
	return "v5.4 L" .. tostring(line)
end

local function srcList(lines: any): { string }
	local out = Json.array()
	if type(lines) == "table" then
		for _, l in lines :: { any } do
			table.insert(out, src(l))
		end
	else
		table.insert(out, src(lines))
	end
	return out
end

-- "+Z" | "-X" | "yaw 81.36 deg" | "yaw 1.57 rad" | "n/a" | "spans X" | "+Z (ascending ...)"
local function parseFacing(s: string): (string?, number?)
	local axis = string.match(s, "^([%+%-][XZ])")
	if axis then
		return axis, nil
	end
	local deg = string.match(s, "^yaw (%-?[%d%.]+) deg")
	if deg then
		return nil, (tonumber(deg) :: number) * math.pi / 180
	end
	local rad = string.match(s, "^yaw (%-?[%d%.]+) rad")
	if rad then
		return nil, tonumber(rad) :: number
	end
	return nil, nil
end
Migrate.parseFacing = parseFacing

local function slug(name: string): string
	local s = string.lower(name)
	s = string.gsub(s, "[^%w]+", "_")
	s = string.gsub(s, "^_+", "")
	s = string.gsub(s, "_+$", "")
	if not string.find(s, "^%a") then
		s = "c_" .. s
	end
	return s
end
Migrate.slug = slug

-- ---------------------------------------------------------------- lots
function Migrate.lots(core: { any }, districts: { any }): { [string]: any }
	local byDistrict: { [string]: { any } } = {}
	local order = {}
	local all = {}
	for _, l in core do
		table.insert(all, { lot = l, file = "lots_core.json" })
	end
	for _, l in districts do
		table.insert(all, { lot = l, file = "lots_districts.json" })
	end
	for _, entry in all do
		local l = entry.lot
		local facing, yaw = parseFacing(l.facing)
		local rec: { [string]: any } = {
			id = l.id,
			district = l.district,
			type = l.type,
			x = l.x,
			z = l.z,
			facing = facing,
			yaw = yaw,
			footprint = if type(l.footprint) == "table" then { w = l.footprint.w, d = l.footprint.d } else nil,
			hasInterior = l.has_interior == true,
			style = l.style,
			notes = l.notes,
			routes = { source = "harvest" },
			src = src(l.src_line),
			v54 = { facing = l.facing },
		}
		if not byDistrict[l.district] then
			byDistrict[l.district] = Json.array()
			table.insert(order, l.district)
		end
		table.insert(byDistrict[l.district], rec)
	end
	local files: { [string]: any } = {}
	for _, district in order do
		files["town/lots/" .. district .. ".json"] = {
			["$schema"] = "../../../schema/lots.schema.json",
			district = district,
			src = "spec/data/lots_core.json + lots_districts.json (verified v5.4 extraction); HTML units",
			lots = byDistrict[district],
		}
	end
	return files
end

-- ---------------------------------------------------------------- roads
function Migrate.roads(roads: { any }): any
	local out = Json.array()
	for _, r in roads do
		table.insert(out, {
			id = r.id,
			axis = r.axis,
			coord = r.coord,
			start = r.start,
			["end"] = r["end"],
			width = r.width,
			kind = r.kind,
			registered = type(r.notes) == "string" and string.find(r.notes, "^registered") ~= nil,
			notes = r.notes,
			src = src(r.src_line),
		})
	end
	return {
		["$schema"] = "../../schema/roads.schema.json",
		src = "spec/data/roads.json (worldgen_core 4); HTML units",
		roads = out,
	}
end

-- ---------------------------------------------------------------- lanes
function Migrate.lanes(lanes: { any }): any
	local out = Json.array()
	for _, l in lanes do
		local roads = Json.array()
		local seen: { [string]: boolean } = {}
		for token in string.gmatch(l.road or "", "rd_%d%d%d_[%w_%.%-]+") do
			local id = string.gsub(token, "[%.%-]+$", "")
			if not seen[id] then
				seen[id] = true
				table.insert(roads, id)
			end
		end
		local users = Json.array()
		for _, u in (l.vehicles or {}) :: { any } do
			table.insert(users, u)
		end
		local yields = Json.array()
		for _, y in (l.yields_to or {}) :: { any } do
			table.insert(yields, y)
		end
		table.insert(out, {
			id = l.lane_id,
			roads = roads,
			roadNote = l.road,
			path = l.path,
			dir = l.direction,
			users = users,
			speed = l.speed,
			wrap = l.wrap,
			yieldsTo = if l.yields_to then yields else nil,
			stops = l.stops,
			schedule = l.schedule,
			stations = l.stations,
			dwellSeconds = l.dwell_seconds,
			notes = l.notes,
			src = srcList(l.src_line),
		})
	end
	return {
		["$schema"] = "../../schema/lanes.schema.json",
		src = "spec/data/traffic_lanes.json (traffic 3); HTML units, speeds u/s",
		lanes = out,
	}
end

-- ---------------------------------------------------------------- cast
function Migrate.cast(cast: { any }): any
	local out = Json.array()
	local used: { [string]: boolean } = {}
	for _, c in cast do
		local id = slug(c.name)
		if used[id] then
			id = id .. "_l" .. tostring(c.src_line)
		end
		used[id] = true
		local homeLot = string.match(c.home or "", "lot ([%w_]+)")
		local personality = string.match(c.personality or "", "^(%a+)")
		if personality ~= "wary" and personality ~= "panic" and personality ~= "brave" and personality ~= "bluster" then
			personality = "n/a"
		end
		table.insert(out, {
			id = id,
			name = c.name,
			role = c.role,
			homeLot = homeLot,
			home = c.home,
			personality = personality,
			personalityNote = if c.personality ~= personality then c.personality else nil,
			look = { skinTone = c.skin, outfit = c.outfit },
			spawnRule = c.spawn_rule,
			specialProps = c.special_props,
			src = src(c.src_line),
		})
	end
	return {
		["$schema"] = "../../schema/cast.schema.json",
		src = "spec/data/human_cast.json (humans_actors 1-3)",
		cast = out,
	}
end

-- ---------------------------------------------------------------- routes catalogue
function Migrate.catalog(entries: { any }): any
	local out = Json.array()
	for _, e in entries do
		table.insert(out, {
			generator = e.generator,
			kind = e.kind,
			line = e.created_at_line,
			formula = e.how_points_are_computed,
			count = e.count_estimate,
			speed = e.speed,
			surfaceRadius = e.surfaceRadius,
			visualOffset = e.visualOffset,
			connectsTo = e.connects_to,
			notes = e.notes,
			src = src(e.created_at_line),
		})
	end
	return {
		["$schema"] = "../../schema/routes_catalog.schema.json",
		src = "spec/data/routes_catalog.json (routes_movement 2); HTML units",
		generators = out,
	}
end

-- ---------------------------------------------------------------- wildlife
local function copy(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in pairs(v) do
		out[k] = copy(x)
	end
	return setmetatable(out, getmetatable(v))
end

local function pickKeys(t: { [string]: any }, keys: { string }): { [string]: any }
	local out = {}
	for _, k in keys do
		out[k] = copy(t[k])
	end
	return out
end

function Migrate.wildlife(w: any): { [string]: any }
	local v54 = w.v54
	local v41 = w.v41_restore
	local proposals = w.proposals
	local files: { [string]: any } = {}
	local units = "HTML units (x 2.5 for studs)"

	local trees = pickKeys(v54.trees, { "list" })
	files["wildlife/trees.json"] = {
		["$schema"] = "../../schema/wildlife_trees.schema.json",
		src = "wildlife.json v54.trees (runtime, headless run; wildlife_foraging 6.1); " .. units,
		count = #(trees.list :: { any }),
		trees = trees.list,
		acornTrees = copy(v54.acornTrees),
		knotholesDecorative = copy(v54.knotholesDecorative),
	}

	local apples = v54.appleTrees
	files["wildlife/apple_trees.json"] = {
		["$schema"] = "../../schema/wildlife_apple_trees.schema.json",
		src = "wildlife.json v54.appleTrees (v5.4 L15131-15329; wildlife_foraging 7); " .. units,
		count = #(apples.list :: { any }),
		appleTrees = copy(apples.list),
		candidateSectors = copy(apples.candidateSectors),
		perSectorMax = apples.perSectorMax,
		fallbackRow = copy(apples.fallbackRow),
		siteClear = copy(apples.siteClear),
		model = copy(apples.model),
		collectible = apples.collectible,
		selectionNote = apples.selectionNote,
		rejectedCandidates = copy(apples.rejectedCandidates),
	}

	local nests = v54.nests
	files["wildlife/nests.json"] = {
		["$schema"] = "../../schema/wildlife_nests.schema.json",
		src = "wildlife.json v54.nests + v54.birds (v5.4 L15330-15506; wildlife_foraging 8); " .. units,
		count = #(nests.list :: { any }),
		routeT = nests.routeT,
		yOffset = nests.yOffset,
		yOffsetApple = nests.yOffsetApple,
		eggs = nests.eggs,
		eggColors = copy(nests.eggColors),
		bowl = nests.bowl,
		rim = nests.rim,
		nests = copy(nests.list),
		birds = copy(v54.birds),
	}

	local adjacent = v54.adjacentFauna
	files["wildlife/fauna.json"] = {
		["$schema"] = "../../schema/wildlife_fauna.schema.json",
		src = "wildlife.json v54.normalSquirrels, rabbits, yardCats, adjacentFauna, shelterZones, overflight (wildlife_foraging 2-5, 9); "
			.. units,
		normalSquirrels = copy(v54.normalSquirrels),
		rabbits = copy(v54.rabbits),
		yardCats = copy(v54.yardCats),
		turtles = copy(adjacent.turtles),
		yardDogs = copy(adjacent.yardDogs),
		chainedDogs = copy(adjacent.chainedDogs),
		idlePredators = copy(adjacent.idlePredators),
		shelterZones = copy(v54.shelterZones),
		overflight = copy(v54.overflight),
	}

	local forage = copy(v54.forage)
	forage["$schema"] = "../../schema/wildlife_forage_v54.schema.json"
	forage.src = "wildlife.json v54.forage (wildlife_foraging 10); " .. units
	files["wildlife/forage_v54.json"] = forage

	local restore = pickKeys(v41, {
		"note",
		"lifeSafeSpot",
		"nutCaches",
		"deer",
		"fox",
		"gardens",
		"insects",
		"birdFeeders",
		"scavengeTrashCans",
		"floweringBushes",
		"handlerOrder",
	})
	restore["$schema"] = "../../schema/wildlife_restore_v41.schema.json"
	restore.src = "wildlife.json v41_restore (v4.1 L12233-12793; wildlife_foraging 11), nut cache "
		.. tostring(proposals.nutCacheFix.index)
		.. " moved per proposals.nutCacheFix; "
		.. units
	local fix = proposals.nutCacheFix
	local moved = false
	for _, cache in restore.nutCaches.list :: { any } do
		if cache.index == fix.index then
			cache.moved = { from = { cache.x, cache.z }, to = copy(fix.to), reason = fix.reason }
			cache.x = fix.to[1]
			cache.z = fix.to[2]
			moved = true
		end
	end
	if not moved then
		error("nutCacheFix index " .. tostring(fix.index) .. " not found in nutCaches.list")
	end
	files["wildlife/restore_v41.json"] = restore

	local hollows = copy(proposals.hollowTrees)
	hollows["$schema"] = "../../schema/wildlife_hollows.schema.json"
	hollows.src = "wildlife.json proposals.hollowTrees (designer proposal, wildlife_foraging 6.5); " .. units
	files["wildlife/hollows.json"] = hollows
	return files
end

-- ---------------------------------------------------------------- all
function Migrate.build(specDir: string): Output
	local core = Json.decodeFile(specDir .. "/lots_core.json")
	local districts = Json.decodeFile(specDir .. "/lots_districts.json")
	local out: Output = table.clone(Migrate.lots(core, districts))
	out["town/roads.json"] = Migrate.roads(Json.decodeFile(specDir .. "/roads.json"))
	out["town/lanes.json"] = Migrate.lanes(Json.decodeFile(specDir .. "/traffic_lanes.json"))
	out["cast/cast.json"] = Migrate.cast(Json.decodeFile(specDir .. "/human_cast.json"))
	out["routes/catalog.json"] = Migrate.catalog(Json.decodeFile(specDir .. "/routes_catalog.json"))
	for k, v in Migrate.wildlife(Json.decodeFile(specDir .. "/wildlife.json")) do
		out[k] = v
	end
	return out
end

return Migrate
