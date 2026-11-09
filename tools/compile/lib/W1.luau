--!strict
-- tools/compile W1 data (BUILD_PLAN §4.4 #7, §3.3-§3.5, §3.12, §3.13): lot types, building programmes,
-- interior templates, harvest patches, population, hollows, terrain extensions and street lighting.
-- Validates each file against tools/compile/schema/*.schema.json, runs the W1 compiler invariants
-- (1 params vs paramSchema, 3 FRB subset, 5 hollows, 9 room graphs, 11 and 20 population, 19 offroad,
-- harvest patch coverage of ids) and returns the modules to emit. W1 modules stay in HTML units
-- (fields with a U suffix, rects, `at` coordinates); the builders convert with Units' 2.5 at one place.
-- Interface: W1.compile(ctx) -> { modules: { Module } }
local fs = require("@lune/fs")
local Json = require("./Json")
local Schema = require("./Schema")
local RoomGraph = require("../../../src/worldgen/RoomGraph")

local W1 = {}

export type Module = { name: string, value: any, records: number, source: string, map: boolean?, header: { string }? }

export type Ctx = {
	repo: string,
	lots: { any }, -- converted lots (studs)
	lotsHtml: { [string]: any }, -- id -> authored lot (HTML units)
	routeIds: { [number]: boolean },
	invariant: (name: string, ok: boolean, detail: string?) -> (),
	compare: (what: string, expected: any, actual: any, note: string?) -> (),
	schemaError: (path: string, errs: { Schema.Error }) -> (),
	warnings: { string },
}

-- Player-slot arithmetic comes from Roles/Ladder (invariant 13: the only place it is stated). Until
-- Track A lands Ladder.server, the BUILD_PLAN §3.7 values are used here (tools/ is outside the scan).
local function ladderNumbers(warnings: { string }): (number, number)
	local ok, Ladder = pcall(require, "../../../src/shared/Roles/Ladder")
	if ok and type(Ladder) == "table" and type(Ladder.server) == "table" and type(Ladder.humanSlots) == "table" then
		return Ladder.server.maxPlayers, Ladder.humanSlots.total
	end
	table.insert(
		warnings,
		"Roles/Ladder has no server/humanSlots yet (Track A W1 #4): invariants 11/20 use BUILD_PLAN §3.7 (49 players, 35 human slots)"
	)
	return 49, 35
end

local function onEdge(rect: { number }, x: number, z: number): boolean
	local eps = 1e-6
	local inX = x >= rect[1] - eps and x <= rect[2] + eps
	local inZ = z >= rect[3] - eps and z <= rect[4] + eps
	local onX = math.abs(x - rect[1]) <= eps or math.abs(x - rect[2]) <= eps
	local onZ = math.abs(z - rect[3]) <= eps or math.abs(z - rect[4]) <= eps
	return (onX and inZ) or (onZ and inX)
end

-- rooms/doors/graph checks shared by building programmes and interior templates
local function checkLayout(ctx: Ctx, label: string, rooms: { any }, doors: { any }, extra: { any }?)
	local byId: { [string]: any } = {}
	for _, r in rooms do
		ctx.invariant(label .. ": room id unique " .. r.id, byId[r.id] == nil)
		byId[r.id] = r
		ctx.invariant(label .. ": room rect ordered " .. r.id, r.rect[1] < r.rect[2] and r.rect[3] < r.rect[4])
	end
	local doorIds: { [string]: boolean } = {}
	local outside = 0
	for _, d in doors do
		ctx.invariant(label .. ": door id unique " .. d.id, not doorIds[d.id])
		doorIds[d.id] = true
		for _, side in { d.a, d.b } do
			if side == "outside" then
				outside += 1
			else
				local r = byId[side]
				ctx.invariant(label .. ": door " .. d.id .. " room exists " .. side, r ~= nil)
				if r then
					ctx.invariant(
						label .. ": door " .. d.id .. " lies on the boundary of " .. side,
						onEdge(r.rect, d.at[1], d.at[2])
					)
				end
			end
		end
	end
	ctx.invariant(label .. ": at least one door to the outside", outside > 0)
	local graph = RoomGraph.build(rooms, doors, extra or {})
	local unreached = RoomGraph.unreached(graph, "outside")
	ctx.invariant(label .. ": room graph connected (invariant 9)", #unreached == 0, table.concat(unreached, ", "))
	return byId, doorIds
end

function W1.compile(ctx: Ctx): { modules: { Module } }
	local repo = ctx.repo
	local schemaDir = repo .. "/tools/compile/schema/"
	local function load(rel: string, schemaName: string): any
		local path = repo .. "/" .. rel
		local value = Json.decodeFile(path)
		local errs = Schema.validate(Json.decodeFile(schemaDir .. schemaName .. ".schema.json"), value)
		if #errs > 0 then
			ctx.schemaError(rel, errs)
		end
		value["$schema"] = nil
		return value
	end
	local modules: { Module } = {}
	local lotsById: { [string]: any } = {}
	for _, l in ctx.lots do
		lotsById[l.id] = l
	end

	-- lot types + invariant 1 (params against paramSchema)
	local lotTypes = load("data/authored/lot_types.json", "lot_types")
	local paramsChecked = 0
	for _, lot in ctx.lots do
		local t = lotTypes.types[lot.type]
		ctx.invariant("lot type defined: " .. lot.type, t ~= nil, lot.id)
		local html = ctx.lotsHtml[lot.id]
		if t and html and html.params then
			ctx.invariant("lot params have a paramSchema: " .. lot.id, t.paramSchema ~= nil)
			if t.paramSchema then
				local errs = Schema.validate(t.paramSchema, html.params)
				ctx.invariant(
					"lot params validate (invariant 1): " .. lot.id,
					#errs == 0,
					Schema.formatErrors(lot.id, errs)
				)
				paramsChecked += 1
			end
		end
	end
	ctx.compare(
		"lot types (one per v5.4 type in the data)",
		74,
		(function()
			local n = 0
			for _ in lotTypes.types do
				n += 1
			end
			return n
		end)()
	)
	table.insert(modules, {
		name = "LotTypes",
		value = lotTypes,
		records = 0,
		map = true,
		source = "data/authored/lot_types.json",
		header = { "HTML units: heightU (and every U-suffixed field) is not converted; builders scale by 2.5." },
	})

	-- interior templates (4 FRB houses)
	local interiors: { [string]: any } = {}
	local nInteriors = 0
	for _, f in fs.readDir(repo .. "/data/interiors") do
		if string.sub(f, -5) == ".json" then
			local tpl = load("data/interiors/" .. f, "interior")
			ctx.invariant("interior id matches file: " .. f, tpl.id .. ".json" == f)
			ctx.invariant("interior lot exists: " .. tpl.id, lotsById[tpl.lot] ~= nil, tpl.lot)
			local hides = {}
			for _, fu in tpl.furniture do
				if fu.hide then
					table.insert(hides, { id = "hide_" .. fu.id, room = fu.room })
				end
			end
			local rooms, doorIds = checkLayout(ctx, "interior " .. tpl.id, tpl.rooms, tpl.doors, hides)
			for _, fu in tpl.furniture do
				ctx.invariant("interior " .. tpl.id .. ": furniture room " .. fu.id, rooms[fu.room] ~= nil)
			end
			ctx.invariant("interior " .. tpl.id .. ": defender room", rooms[tpl.defenderSpawn.room] ~= nil)
			ctx.invariant("interior " .. tpl.id .. ": burglar door", doorIds[tpl.burglarEntry.door] == true)
			interiors[tpl.id] = tpl
			nInteriors += 1
		end
	end
	local homes = 0
	for _, lot in ctx.lots do
		local html = ctx.lotsHtml[lot.id]
		local home = html and html.home
		if home and home.interior then
			homes += 1
			local tpl = interiors[home.interior]
			ctx.invariant("home interior template exists: " .. lot.id, tpl ~= nil, home.interior)
			if tpl then
				ctx.invariant("interior template names its lot: " .. lot.id, tpl.lot == lot.id)
			end
		end
	end
	ctx.compare("FRB homes with interior templates (W1; 40 from W3)", 4, homes)
	ctx.compare("interior templates", 4, nInteriors)
	table.insert(modules, {
		name = "Interiors",
		value = interiors,
		records = 0,
		map = true,
		source = "data/interiors/*.json",
		header = { "Fractional rects and door positions; widths and sizes in HTML units (builders scale by 2.5)." },
	})

	-- building programmes
	local buildings: { [string]: any } = {}
	for _, f in fs.readDir(repo .. "/data/buildings") do
		if string.sub(f, -5) == ".json" then
			local b = load("data/buildings/" .. f, "building")
			local lot = lotsById[b.lot]
			ctx.invariant("building lot exists: " .. b.id, lot ~= nil, b.lot)
			if lot then
				local t = lotTypes.types[lot.type]
				ctx.invariant("building builder matches lot type: " .. b.id, t ~= nil and t.builder == b.builder)
			end
			local extra = {}
			for _, s in b.stations do
				table.insert(extra, { id = "station_" .. s.id, room = s.room })
			end
			for _, s in b.shelves do
				table.insert(extra, { id = "shelf_" .. s.id, room = s.room })
			end
			local rooms = checkLayout(ctx, "building " .. b.id, b.rooms, b.doors, extra)
			for _, id in b.briefRooms do
				ctx.invariant("building " .. b.id .. ": brief room present " .. id, rooms[id] ~= nil)
			end
			buildings[b.id] = b
		end
	end
	local hosp, police = buildings.hospital, buildings.police_station
	ctx.invariant("buildings/hospital.json present", hosp ~= nil)
	ctx.invariant("buildings/police_station.json present", police ~= nil)
	if hosp then
		ctx.compare("hospital brief rooms (brief v2: 8)", 8, #hosp.briefRooms)
		ctx.compare("hospital stations (W1 v0)", 4, #hosp.stations)
		local slots = 0
		for _, s in hosp.shelves do
			slots += s.levels * s.slotsPerLevel
		end
		ctx.invariant("hospital pharmacy shelves carry item slots", slots > 0)
	end
	if police then
		local console, playerPads, aiPads = false, 0, 0
		for _, s in police.stations do
			console = console or s.kind == "drone_console"
		end
		for _, p in police.pads do
			if p.kind == "player_car" then
				playerPads += 1
			elseif p.kind == "ai_cruiser" then
				aiPads += 1
			end
		end
		ctx.invariant("police station has the drone console", console)
		ctx.compare("police player-car pads", 2, playerPads)
		ctx.compare("police AI cruiser pads", 1, aiPads)
	end
	table.insert(modules, {
		name = "Buildings",
		value = buildings,
		records = 0,
		map = true,
		source = "data/buildings/*.json",
		header = { "Local lot frame (lx across the front, lz toward the front), HTML units (builders scale by 2.5)." },
	})

	-- harvest patches: ids exist, no route listed twice; harvest_lock lots exist
	local patches = load("data/harvest_patches.json", "harvest_patches")
	local seen: { [number]: string } = {}
	local patched = 0
	for _, p in patches.patches do
		for _, id in p.routes do
			ctx.invariant("harvest patch route exists: " .. p.id .. " -> " .. id, ctx.routeIds[id] == true)
			ctx.invariant("route patched once: " .. id, seen[id] == nil, seen[id])
			seen[id] = p.id
			patched += 1
		end
	end
	for _, l in patches.lots or {} do
		ctx.invariant("harvest_lock lot exists: " .. l.lot, lotsById[l.lot] ~= nil)
	end
	table.insert(modules, {
		name = "HarvestPatches",
		value = patches,
		records = 0,
		map = true,
		source = "data/harvest_patches.json",
	})

	-- population: invariants 11 and 20 (rev 4: check sums, not stated totals)
	local pop = load("data/population.json", "population")
	local maxPlayers, humanSlots = ladderNumbers(ctx.warnings)
	for _, phase in pop.phases do
		local standing, floor, full = 0, 0, 0
		for _, p in pop.posts do
			standing += p.standing[phase]
			floor += p.floor[phase]
			full += p.fullFloor[phase]
			ctx.invariant(`population {phase}: floor <= standing ({p.id})`, p.floor[phase] <= p.standing[phase])
			ctx.invariant(`population {phase}: full floor <= floor ({p.id})`, p.fullFloor[phase] <= p.floor[phase])
			if p.neverCut then
				ctx.invariant(
					`population {phase}: {p.id} floor unchanged at a full server`,
					p.fullFloor[phase] == p.floor[phase]
				)
			end
		end
		local reserve, cap = pop.reserve[phase], pop.hardCap[phase]
		ctx.invariant(
			`inv 11 {phase}: standing {standing} >= human slots + normal floors {humanSlots + floor}`,
			standing >= humanSlots + floor
		)
		ctx.invariant(
			`inv 11 {phase}: standing + reserve {standing + reserve} >= max players + full floors {maxPlayers + full}`,
			standing + reserve >= maxPlayers + full
		)
		ctx.invariant(`inv 11 {phase}: standing + reserve <= hard cap`, standing + reserve <= cap)
		ctx.invariant(`inv 11 {phase}: hard cap - full floors >= max players`, cap - full >= maxPlayers)
	end
	local postsById: { [string]: any } = {}
	for _, p in pop.posts do
		postsById[p.id] = p
	end
	local hs, pol, amb = postsById.hospital_staff, postsById.police, postsById.ambulance_crew
	ctx.invariant("inv 11: hospital floor >= 10", hs ~= nil and hs.floor.frb >= 10 and hs.floor.w3c >= 10)
	ctx.invariant(
		"inv 11: police officer floor >= 6",
		pol ~= nil and (pol.officerFloor or 0) >= 6 and pol.floor.frb >= 6
	)
	ctx.invariant("inv 11: ambulance crew on a separate post", amb ~= nil and amb.floor.frb > 0)
	ctx.invariant("inv 11: squirrel float 10-14", pop.animals.squirrel.min == 10 and pop.animals.squirrel.max == 14)
	ctx.invariant("inv 11: deer bodies >= 5", pop.animals.deer.bodies >= 5)
	for _, p in pop.posts do
		local site = p.site
		if lotsById[site] == nil and site ~= "street" and site ~= "shops" and site ~= "attractions" then
			ctx.invariant("population post site exists: " .. p.id, false, site)
		end
	end
	table.insert(modules, {
		name = "Population",
		value = pop,
		records = 0,
		map = true,
		source = "data/population.json",
		header = { "Body counts only; player-slot counts live in Roles/Ladder (invariant 13)." },
	})

	-- hollows: invariant 5
	local hollows = load("data/hollows.json", "hollows")
	local claimable, premium, escape, single = 0, 0, 0, 0
	local ids: { [string]: boolean } = {}
	for _, h in hollows.hollows do
		ctx.invariant("hollow id unique " .. h.id, not ids[h.id])
		ids[h.id] = true
		if h.claimable then
			claimable += 1
		end
		local chambers: { [string]: boolean } = {}
		for _, c in h.chambers do
			chambers[c.id] = true
		end
		for _, k in h.knotholes do
			ctx.invariant("hollow " .. h.id .. ": knothole chamber exists", chambers[k.chamber] == true)
			local rid = string.match(k.exitTo, "^route:(%d+)$")
			if rid then
				ctx.invariant(
					"hollow " .. h.id .. ": exit route exists " .. rid,
					ctx.routeIds[tonumber(rid) :: number] == true
				)
			end
		end
		if h.tier == "premium" then
			premium += 1
			local garden, feeder = false, false
			for _, s in h.premiumForage or {} do
				local d = math.sqrt((s.x - h.x) ^ 2 + (s.z - h.z) ^ 2)
				if d <= 40 then
					garden = garden or s.kind == "garden"
					feeder = feeder or s.kind == "feeder"
				end
			end
			ctx.invariant("inv 5: premium " .. h.id .. " has a garden and a feeder within 40 u", garden and feeder)
		elseif h.tier == "escape" then
			escape += 1
			local exits: { [string]: boolean } = {}
			local n = 0
			for _, k in h.knotholes do
				if not exits[k.exitTo] then
					n += 1
				end
				exits[k.exitTo] = true
			end
			ctx.invariant(
				"inv 5: escape " .. h.id .. " has 3 knotholes with distinct exits",
				#h.knotholes == 3 and n == 3
			)
		else
			single += 1
			ctx.invariant("inv 5: single-chamber " .. h.id, #h.chambers == 1)
		end
	end
	ctx.compare("claimable hollows (brief v2 §3)", 12, claimable)
	ctx.compare("premium hollows", 2, premium)
	ctx.compare("escape hollows", 1, escape)
	ctx.compare("single-chamber hollows", 9, single)
	ctx.invariant("inv 5: the log is not claimable", hollows.log.claimable == false)
	table.insert(modules, {
		name = "Hollows",
		value = hollows,
		records = 0,
		map = true,
		source = "data/hollows.json",
		header = { "HTML units (x, z, heights as fractions of the tree height)." },
	})

	-- terrain extensions + invariant 19 (offroad: no lots; every lot in a jurisdiction district)
	local ext = load("data/terrain_extensions.json", "terrain_extensions")
	for _, d in ext.districts do
		if d.jurisdiction == false then
			for _, lot in ctx.lots do
				local html = ctx.lotsHtml[lot.id]
				local inside = html.x >= d.minX and html.x <= d.maxX and html.z >= d.minZ and html.z <= d.maxZ
				ctx.invariant("inv 19: no lot in the " .. d.id .. " district", not inside, lot.id)
			end
		end
	end
	local offroad = false
	for _, d in ext.districts do
		offroad = offroad or (d.id == "offroad" and d.jurisdiction == false)
	end
	ctx.invariant("inv 19: offroad district declared with jurisdiction false", offroad)
	local r = ext.verbatimRect
	ctx.invariant(
		"terrain extensions keep the v5.4 rectangle (World/Height PLAYABLE_U)",
		r.minX == -590 and r.maxX == 1150 and r.minZ == -565 and r.maxZ == 443
	)
	table.insert(modules, {
		name = "TerrainExtensions",
		value = ext,
		records = 0,
		map = true,
		source = "data/terrain_extensions.json",
		header = { "HTML units; World/Height.configure(this) applies the patches outside the verbatim rectangle." },
	})

	local lighting = load("data/authored/town/lighting.json", "lighting")
	table.insert(modules, {
		name = "Lighting",
		value = lighting,
		records = 0,
		map = true,
		source = "data/authored/town/lighting.json",
		header = { "HTML units (spacingMaxU, height, setbackU)." },
	})

	ctx.compare("lots whose params were validated against a paramSchema", paramsChecked, paramsChecked)
	return { modules = modules, patchedRoutes = patched }
end

return W1
