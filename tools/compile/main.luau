--!strict
-- tools/compile: validate the authored data, convert HTML units to studs and emit generated/*.luau.
--   lune run tools/compile/main.luau migrate [--check]   spec/data/*.json -> data/authored/**
--   lune run tools/compile/main.luau compile              data/authored + data/harvest -> generated/ + report
--   lune run tools/compile/main.luau check                regenerate into build/compile-check and diff (CI)
--   lune run tools/compile/main.luau all                  migrate + compile
-- Options: --repo <dir> (default: cwd, must hold default.project.json), --spec <dir>, --chunk-kb <n>, --no-stylua
local fs = require("@lune/fs")
local process = require("@lune/process")
local DateTime = require("@lune/datetime")
local stdio = require("@lune/stdio")
local Json = require("./lib/Json")
local Schema = require("./lib/Schema")
local Units = require("./lib/Units")
local LuauEmit = require("./lib/LuauEmit")
local Migrate = require("./lib/Migrate")
local Report = require("./lib/Report")
local W1 = require("./lib/W1")
local Attractions = require("./lib/Attractions")
local TreeArt = require("./lib/TreeArt")
local Expansion = require("./lib/Expansion")
local Sewers = require("./lib/Sewers")

type Opts = { command: string, repo: string, spec: string, chunkKb: number, stylua: boolean, check: boolean }

local function parseArgs(args: { string }): Opts
	local o: Opts = {
		command = "",
		repo = process.cwd,
		spec = "/home/user/spicy-rodents/spec/data",
		chunkKb = 200,
		stylua = true,
		check = false,
	}
	local i = 1
	while i <= #args do
		local a = args[i]
		if a == "--" then
			i += 1
			continue
		end
		if a == "--repo" then
			i += 1
			o.repo = args[i]
		elseif a == "--spec" then
			i += 1
			o.spec = args[i]
		elseif a == "--chunk-kb" then
			i += 1
			o.chunkKb = tonumber(args[i]) :: number
		elseif a == "--no-stylua" then
			o.stylua = false
		elseif a == "--check" then
			o.check = true
		elseif string.sub(a, 1, 2) == "--" then
			error("unknown option " .. a)
		elseif o.command == "" then
			o.command = a
		else
			error("unexpected argument " .. a)
		end
		i += 1
	end
	if o.command == "" then
		o.command = "compile"
	end
	o.repo = string.gsub(o.repo, "/$", "")
	if not fs.isFile(o.repo .. "/default.project.json") then
		error("run from the repository root or pass --repo: no default.project.json in " .. o.repo)
	end
	return o
end

local function listFiles(dir: string, pattern: string): { string }
	local out = {}
	if fs.isDir(dir) then
		for _, name in fs.readDir(dir) do
			if string.find(name, pattern) and fs.isFile(dir .. "/" .. name) then
				table.insert(out, name)
			end
		end
	end
	table.sort(out)
	return out
end

local function fail(msg: string): never
	stdio.ewrite("compile: " .. msg .. "\n")
	return process.exit(1)
end

-- ---------------------------------------------------------------- migrate
local function migrate(o: Opts)
	local outDir = o.repo .. "/data/authored"
	local built = Migrate.build(o.spec)
	local names = {}
	for k in pairs(built) do
		table.insert(names, k)
	end
	table.sort(names)
	local differences = {}
	for _, rel in names do
		local text = Json.encode(built[rel], { keyOrder = Migrate.KEY_ORDER })
		local path = outDir .. "/" .. rel
		if o.check then
			if not fs.isFile(path) or fs.readFile(path) ~= text then
				table.insert(differences, rel)
			end
		else
			local dir = string.match(path, "^(.*)/[^/]+$") :: string
			fs.writeDir(dir)
			fs.writeFile(path, text)
		end
	end
	if o.check then
		if #differences > 0 then
			fail(
				"migrate --check: "
					.. #differences
					.. " authored file(s) differ from a fresh migration: "
					.. table.concat(differences, ", ")
			)
		end
		print("migrate --check: " .. #names .. " authored files match a fresh migration")
	else
		print("migrate: wrote " .. #names .. " files to " .. outDir)
	end
end

-- ---------------------------------------------------------------- compile
type Comparison = { what: string, expected: any, actual: any, status: string, note: string }

local function compile(o: Opts, outDir: string, writeReport: boolean)
	local t0 = os.clock()
	local repo = o.repo
	local schemaDir = repo .. "/data/schema"
	local authored = repo .. "/data/authored"
	local harvestDir = repo .. "/data/harvest"
	local errorsTotal = 0
	local filesValidated = 0
	local warnings: { string } = {}
	local comparisons: { Comparison } = {}
	local invariantsChecked, invariantsFailed = 0, 0

	local function compare(what: string, expected: any, actual: any, note: string?)
		invariantsChecked += 1
		local ok = expected == actual
		if not ok then
			invariantsFailed += 1
		end
		table.insert(comparisons, {
			what = what,
			expected = expected,
			actual = actual,
			status = if ok then "match" else "MISMATCH",
			note = note or "",
		})
	end
	local function invariant(name: string, ok: boolean, detail: string?)
		invariantsChecked += 1
		if not ok then
			invariantsFailed += 1
			errorsTotal += 1
			stdio.ewrite(string.format("  invariant failed: %s%s\n", name, if detail then ": " .. detail else ""))
		end
	end

	local function loadSchema(name: string): any
		return Json.decodeFile(schemaDir .. "/" .. name .. ".schema.json")
	end
	local function loadValidated(path: string, schema: any): any
		local value = Json.decodeFile(path)
		local errs = Schema.validate(schema, value)
		filesValidated += 1
		if #errs > 0 then
			errorsTotal += #errs
			stdio.ewrite("compile: schema errors in " .. path .. "\n" .. Schema.formatErrors(path, errs) .. "\n")
		end
		return value
	end

	-- authored
	local lotsSchema = loadSchema("lots")
	local lotFiles = listFiles(authored .. "/town/lots", "%.json$")
	local lots: { any } = {}
	local lotsPerDistrict = {}
	local lotIds: { [string]: boolean } = {}
	local lotsHtml: { [string]: any } = {}
	for _, f in lotFiles do
		local doc = loadValidated(authored .. "/town/lots/" .. f, lotsSchema)
		local conv = Units.convert(doc, lotsSchema)
		local row = { district = doc.district, count = 0, withFootprint = 0, withFacing = 0, interiors = 0 }
		for i, lot in doc.lots :: { any } do
			invariant("lot id unique: " .. tostring(lot.id), not lotIds[lot.id])
			lotIds[lot.id] = true
			invariant("lot district matches file: " .. tostring(lot.id), lot.district == doc.district, f)
			row.count += 1
			if lot.footprint then
				row.withFootprint += 1
			end
			if lot.facing or lot.yaw then
				row.withFacing += 1
			end
			if lot.hasInterior then
				row.interiors += 1
			end
			table.insert(lots, conv.lots[i])
			lotsHtml[lot.id] = lot
		end
		table.insert(lotsPerDistrict, row)
	end
	table.sort(lotsPerDistrict, function(a, b)
		return a.district < b.district
	end)
	local lotTypes: { [string]: number } = {}
	for _, lot in lots do
		lotTypes[lot.type] = (lotTypes[lot.type] or 0) + 1
	end
	local typeNames = {}
	for k in pairs(lotTypes) do
		table.insert(typeNames, k)
	end
	table.sort(typeNames)

	local roadsSchema = loadSchema("roads")
	local roadsDoc = loadValidated(authored .. "/town/roads.json", roadsSchema)
	local roadIds: { [string]: boolean } = {}
	for _, r in roadsDoc.roads :: { any } do
		invariant("road id unique: " .. tostring(r.id), not roadIds[r.id])
		roadIds[r.id] = true
		if r.axis == "free" then
			invariant(
				"free road has [x,z] ends: " .. r.id,
				type(r.start) == "table" and type(r["end"]) == "table" and r.coord == nil
			)
		else
			invariant(
				"axis road has numeric ends and coord: " .. r.id,
				type(r.start) == "number" and type(r["end"]) == "number" and type(r.coord) == "number"
			)
		end
	end
	local roads = Units.convert(roadsDoc, roadsSchema).roads

	local lanesSchema = loadSchema("lanes")
	local lanesDoc = loadValidated(authored .. "/town/lanes.json", lanesSchema)
	local laneIds: { [string]: boolean } = {}
	local lanesWithoutRoad = 0
	for _, l in lanesDoc.lanes :: { any } do
		invariant("lane id unique: " .. tostring(l.id), not laneIds[l.id])
		laneIds[l.id] = true
		if #(l.roads :: { any }) == 0 then
			lanesWithoutRoad += 1
		end
		for _, rid in l.roads :: { any } do
			invariant("lane road exists: " .. l.id .. " -> " .. rid, roadIds[rid] == true)
		end
	end
	if lanesWithoutRoad > 0 then
		table.insert(
			warnings,
			string.format(
				"%d lane(s) reference no road id (yard glides, verges, templated routes): kept with roadNote only",
				lanesWithoutRoad
			)
		)
	end
	local lanes = Units.convert(lanesDoc, lanesSchema).lanes

	local castSchema = loadSchema("cast")
	local castDoc = loadValidated(authored .. "/cast/cast.json", castSchema)
	local castIds: { [string]: boolean } = {}
	local names: { [string]: number } = {}
	for _, c in castDoc.cast :: { any } do
		invariant("cast id unique: " .. tostring(c.id), not castIds[c.id])
		castIds[c.id] = true
		names[c.name] = (names[c.name] or 0) + 1
		if c.homeLot then
			invariant("cast home lot exists: " .. c.id .. " -> " .. c.homeLot, lotIds[c.homeLot] == true)
		end
	end
	local dupNames = {}
	for n, k in pairs(names) do
		if k > 1 then
			table.insert(dupNames, n)
		end
	end
	table.sort(dupNames)
	if #dupNames > 0 then
		table.insert(
			warnings,
			"duplicate cast names (ids disambiguated with their source line): " .. table.concat(dupNames, ", ")
		)
	end
	local cast = Units.convert(castDoc, castSchema).cast

	local catalogSchema = loadSchema("routes_catalog")
	local catalogDoc = loadValidated(authored .. "/routes/catalog.json", catalogSchema)
	local catalogLines: { [number]: any } = {}
	local catalogTotal = 0
	for _, g in catalogDoc.generators :: { any } do
		invariant("catalog line unique: " .. tostring(g.line), catalogLines[g.line] == nil)
		catalogLines[g.line] = g
		catalogTotal += g.count
	end
	local catalog = Units.convert(catalogDoc, catalogSchema).generators

	local wildlifeNames = { "trees", "apple_trees", "nests", "fauna", "forage_v54", "restore_v41", "hollows" }
	local wildlife: { [string]: any } = {}
	local wildlifeDocs: { [string]: any } = {}
	for _, w in wildlifeNames do
		local schema = loadSchema("wildlife_" .. w)
		local doc = loadValidated(authored .. "/wildlife/" .. w .. ".json", schema)
		wildlifeDocs[w] = doc
		local conv = Units.convert(doc, schema)
		conv["$schema"] = nil
		wildlife[w] = conv
	end

	-- harvest
	local hrSchema = loadSchema("harvest_routes")
	local routesDoc = loadValidated(harvestDir .. "/routes.json", hrSchema)
	local hfSchema = loadSchema("harvest_forks")
	local forksDoc = loadValidated(harvestDir .. "/forks.json", hfSchema)
	local routeIds: { [number]: boolean } = {}
	local perLine: { [number]: number } = {}
	for i, r in routesDoc.routes :: { any } do
		invariant("route id is creation order: " .. tostring(r.id), r.id == i - 1)
		routeIds[r.id] = true
		invariant("route sampleCount rule: " .. r.name, r.sampleCount == math.max(20, math.ceil(r.length * 3)) + 1)
		local finite = true
		for _, p in r.points :: { any } do
			for _, c in p :: { number } do
				if c ~= c or c == math.huge or c == -math.huge then
					finite = false
				end
			end
		end
		invariant("route points finite: " .. r.name, finite)
		local line = r.callSite and r.callSite.line
		if line then
			perLine[line] = (perLine[line] or 0) + 1
		end
	end
	for line, g in pairs(catalogLines) do
		compare(
			string.format("catalogue L%d %s", line, g.generator),
			g.count,
			perLine[line] or 0,
			"routes created at this addRoute line (harvest callSite)"
		)
	end
	local usedLines = 0
	for _ in pairs(perLine) do
		usedLines += 1
	end
	for _, t in forksDoc.trunks :: { any } do
		invariant("fork trunk exists: " .. tostring(t.trunk), routeIds[t.trunk] == true)
		for _, f in t.forks :: { any } do
			invariant("fork branch exists: " .. tostring(f.branch), routeIds[f.branch] == true)
		end
	end
	local routesConv = Units.convert(routesDoc, hrSchema).routes
	local forksConv = Units.convert(forksDoc, hfSchema).trunks

	-- trees: spec list vs harvest trees
	local treesHarvest = Json.decodeFile(harvestDir .. "/trees.json")
	local matched = 0
	for _, t in wildlifeDocs.trees.trees :: { any } do
		for _, h in treesHarvest.trees :: { any } do
			if math.abs(h.x - t.x) <= 0.0051 and math.abs(h.z - t.z) <= 0.0051 then
				matched += 1
				break
			end
		end
	end

	-- count comparisons against the specs and the task targets
	compare("lots (90 core + 153 districts)", 243, #lots)
	local coreCount = 0
	for _, lot in lots do
		if lot.src and lotTypes then
			-- core file lots are those whose district is one of the two Old Town districts
			if
				lot.district == "old_town_core"
				or lot.district == "old_town_outer"
				or lot.district == "east_commercial" and false
			then
				coreCount += 0
			end
		end
	end
	compare("lot districts", 11, #lotsPerDistrict)
	compare("roads", 116, #roads)
	compare("lanes", 25, #lanes)
	compare("cast entries", 87, #cast)
	compare("route generators in the catalogue", 60, #catalog)
	compare("catalogue instance total", 1332, catalogTotal)
	compare("harvest routes", 1332, #routesConv)
	compare("addRoute lines used by the harvest", 60, usedLines)
	compare("harvest fork trunks", 95, #forksConv)
	compare("trees (authored list)", 95, #(wildlife.trees.trees :: { any }))
	compare("trees matching the harvest by (x,z) within 0.005", 95, matched)
	compare("apple trees", 12, #(wildlife.apple_trees.appleTrees :: { any }))
	compare("nests", 24, #(wildlife.nests.nests :: { any }))
	compare("nut caches", 10, #(wildlife.restore_v41.nutCaches.list :: { any }))
	compare("deer", 5, #(wildlife.restore_v41.deer.list :: { any }))
	compare("insects", 30, #(wildlife.restore_v41.insects.list :: { any }))
	compare(
		"hollow proposals (premium + knothole)",
		11,
		#(wildlife.hollows.premium :: { any }) + #(wildlife.hollows.knothole :: { any })
	)

	-- W1 data (lot types, buildings, interiors, patches, population, hollows, terrain, lighting)
	local w1 = W1.compile({
		repo = repo,
		lots = lots,
		lotsHtml = lotsHtml,
		routeIds = routeIds,
		invariant = invariant,
		compare = compare,
		schemaError = function(path: string, errs: { Schema.Error })
			errorsTotal += #errs
			filesValidated += 1
			stdio.ewrite("compile: schema errors in " .. path .. "\n" .. Schema.formatErrors(path, errs) .. "\n")
		end,
		warnings = warnings,
	})
	-- data/attractions.json: buildings baked on their own (Workspace.Attractions) and their routes
	local attractionsModule = Attractions.compile({
		repo = repo,
		routeIds = routeIds,
		invariant = invariant,
		compare = compare,
		schemaError = function(path: string, errs: { Schema.Error })
			errorsTotal += #errs
			filesValidated += 1
			stdio.ewrite("compile: schema errors in " .. path .. "\n" .. Schema.formatErrors(path, errs) .. "\n")
		end,
	})
	if attractionsModule then
		table.insert(w1.modules, attractionsModule)
	end
	-- data/sewers.json: the storm drains under the town (Shared/World/SewerLayout) and their enclosed routes
	local otherIds: { [number]: boolean } = {}
	for _, r in (if attractionsModule then attractionsModule.value.routes else {}) :: { any } do
		otherIds[r.id] = true
	end
	local sewersModule = Sewers.compile({
		repo = repo,
		routeIds = routeIds,
		otherIds = otherIds,
		invariant = invariant,
		compare = compare,
		schemaError = function(path: string, errs: { Schema.Error })
			errorsTotal += #errs
			filesValidated += 1
			stdio.ewrite("compile: schema errors in " .. path .. "\n" .. Schema.formatErrors(path, errs) .. "\n")
		end,
	})
	if sewersModule then
		table.insert(w1.modules, sewersModule)
	end
	-- data/expansion.json: the batch 2 town expansion layout (docs/waves/BATCH2_SPEC.md), checked against the town
	local terrainExtensions = nil
	for _, m in w1.modules do
		if m.name == "TerrainExtensions" then
			terrainExtensions = m.value
		end
	end
	local expansionModule = Expansion.compile({
		repo = repo,
		lots = lots,
		roads = roads,
		routes = routesConv,
		trees = wildlife.trees.trees,
		appleTrees = wildlife.apple_trees.appleTrees,
		terrainExtensions = terrainExtensions,
		invariant = invariant,
		compare = compare,
		schemaError = function(path: string, errs: { Schema.Error })
			errorsTotal += #errs
			filesValidated += 1
			stdio.ewrite("compile: schema errors in " .. path .. "\n" .. Schema.formatErrors(path, errs) .. "\n")
		end,
	})
	if expansionModule then
		table.insert(w1.modules, expansionModule)
	end
	-- data/art/tree_meshes.json: the Blender tree models the bake places (WorldGen/Builders/Trees)
	local treeArtModule = TreeArt.compile({ repo = repo, invariant = invariant, compare = compare })
	if treeArtModule then
		table.insert(w1.modules, treeArtModule)
	end

	for _, c in comparisons do
		if c.status ~= "match" then
			errorsTotal += 1
			stdio.ewrite(
				string.format(
					"  count mismatch: %s expected %s got %s\n",
					c.what,
					tostring(c.expected),
					tostring(c.actual)
				)
			)
		end
	end
	if errorsTotal > 0 then
		fail(string.format("%d error(s); nothing written", errorsTotal))
	end

	-- ---- emit
	if fs.isDir(outDir) then
		for _, name in listFiles(outDir, "%.luau$") do
			fs.removeFile(outDir .. "/" .. name)
		end
	end
	fs.writeDir(outDir)
	local pinSha = routesDoc.pin.sha256
	local common = {
		"GENERATED by tools/compile (lune run tools/compile/main.luau compile). Do not edit; edit data/authored and recompile.",
		"Units: studs (HTML units x 2.5) for every field the schemas mark as a length or speed; angles in radians.",
	}
	local generated = {}
	local function emitModule(name: string, value: any, records: number, source: string, extraHeader: { string }?)
		local header = table.clone(common)
		table.insert(header, "Source: " .. source)
		for _, h in extraHeader or {} do
			table.insert(header, h)
		end
		local text = LuauEmit.module(value, header, { keyOrder = Migrate.KEY_ORDER })
		local path = outDir .. "/" .. name .. ".luau"
		fs.writeFile(path, text)
		table.insert(generated, { name = name, records = records, source = source, path = path })
	end

	emitModule("Lots", lots, #lots, "data/authored/town/lots/*.json")
	emitModule("Roads", roads, #roads, "data/authored/town/roads.json")
	emitModule("Lanes", lanes, #lanes, "data/authored/town/lanes.json")
	emitModule("Cast", cast, #cast, "data/authored/cast/cast.json")
	emitModule("RoutesCatalog", catalog, #catalog, "data/authored/routes/catalog.json")
	-- wildlife: converted lists plus the unconverted constant blocks under htmlUnits
	local wl: { [string]: any } = {}
	local htmlConst: { [string]: any } = {}
	for _, w in wildlifeNames do
		wl[w] = wildlife[w]
	end
	htmlConst.note =
		"blocks the schemas do not annotate keep v5.4 HTML units; convert with x 2.5 where they are lengths"
	emitModule(
		"Wildlife",
		{ studs = wl, htmlUnits = htmlConst },
		#(wildlife.trees.trees :: { any }),
		"data/authored/wildlife/*.json",
		{
			"Lists (positions, heights, radii) are in studs. Nested v5.4 constant blocks (model, wander, behaviour tables) are",
			"copied verbatim and stay in HTML units; see each schema's x-unit annotations for what was converted.",
		}
	)

	local routeRecords = {}
	for _, r in routesConv do
		local fn = r.callSite and r.callSite.fn or "module"
		local line = r.callSite and r.callSite.line or 0
		local rec: { [string]: any } = {
			id = r.id,
			name = r.name,
			kind = r.kind,
			speedMult = 1, -- v5.4 ignores route.speed (routes_movement 1.1; D8 note); kept as a field
			v54Speed = r.speed,
			surfaceRadius = r.surfaceRadius,
			length = r.length,
			points = r.points,
			origin = "harvest",
			generator = string.format("%s@L%d", fn, line),
		}
		if r.center then
			rec.center = r.center
		end
		if r.visualOffset then
			rec.visualOffset = r.visualOffset
		end
		if r.trunkClearance then
			rec.trunkClearance = r.trunkClearance
		end
		table.insert(routeRecords, rec)
	end
	local chunks = LuauEmit.chunk(routeRecords, o.chunkKb * 1024, { keyOrder = Migrate.KEY_ORDER })
	local routeChunkNames = {}
	for i, chunk in chunks do
		local name = string.format("Routes_%02d", i)
		table.insert(routeChunkNames, name)
		emitModule(
			name,
			chunk,
			#chunk,
			string.format(
				"data/harvest/routes.json (chunk %d of %d; pinned to v5.4 HTML SHA-256 %s)",
				i,
				#chunks,
				pinSha
			)
		)
	end
	local forkRecords = {}
	for _, t in forksConv do
		local forks = {}
		for _, f in t.forks do
			local rec: { [string]: any } =
				{ branch = f.branch, t = f.t, height = f.height, origin = f.origin, outward = f.outward }
			if f.trunkClearance then
				rec.trunkClearance = f.trunkClearance
			end
			table.insert(forks, rec)
		end
		table.insert(forkRecords, { trunk = t.trunk, forks = forks })
	end
	emitModule(
		"Forks",
		forkRecords,
		#forkRecords,
		"data/harvest/forks.json (canopyForks; pinned to v5.4 HTML SHA-256 " .. pinSha .. ")"
	)

	local index = {
		studsPerUnit = Units.STUDS_PER_UNIT,
		units = "studs",
		harvestPin = { sha256 = pinSha },
		modules = {
			Lots = { count = #lots, chunks = { "Lots" } },
			Roads = { count = #roads, chunks = { "Roads" } },
			Lanes = { count = #lanes, chunks = { "Lanes" } },
			Cast = { count = #cast, chunks = { "Cast" } },
			RoutesCatalog = { count = #catalog, chunks = { "RoutesCatalog" } },
			Wildlife = { count = 1, chunks = { "Wildlife" } },
			Routes = { count = #routeRecords, chunks = routeChunkNames },
			Forks = { count = #forkRecords, chunks = { "Forks" } },
		},
	}
	for _, m in w1.modules do
		emitModule(m.name, m.value, m.records, m.source, m.header)
		generated[#generated].map = m.map
		index.modules[m.name] = { count = 1, chunks = { m.name } }
	end
	emitModule("Index", index, 1, "tools/compile (module list, counts and the harvest pin)")

	-- stylua pass so the generated files match the repository formatting
	local styluaNote = "not run (--no-stylua)"
	if o.stylua then
		local args = {}
		if fs.isFile(repo .. "/stylua.toml") then
			table.insert(args, "--config-path")
			table.insert(args, repo .. "/stylua.toml")
		end
		for _, g in generated do
			table.insert(args, g.path)
		end
		local res = process.exec("stylua", args)
		styluaNote = if res.ok then "stylua ok" else "stylua FAILED: " .. res.stderr
		if not res.ok then
			fail("stylua failed on generated files: " .. res.stderr)
		end
	end

	-- verify: every module requires under Lune, record size and time
	local totalBytes = 0
	local largest = { name = "", bytes = 0, requireMs = 0 }
	for _, g in generated do
		local text = fs.readFile(g.path)
		g.bytes = #text
		totalBytes += #text
		local rel = string.gsub(g.path, "^" .. repo:gsub("%p", "%%%0") .. "/", "")
		local reqPath = "../../" .. string.gsub(rel, "%.luau$", "")
		local t1 = os.clock()
		local ok, result = pcall(require, reqPath)
		local ms = (os.clock() - t1) * 1000
		g.requireMs = string.format("%.1f", ms)
		if not ok then
			fail("generated module does not load under Lune: " .. g.name .. ": " .. tostring(result))
		end
		local n = if type(result) == "table" then #result else 0
		if g.name ~= "Index" and g.name ~= "Wildlife" and not g.map and n ~= g.records then
			fail(string.format("generated module %s has %d records, expected %d", g.name, n, g.records))
		end
		if #text > largest.bytes then
			largest = { name = g.name, bytes = #text, requireMs = ms }
		end
	end

	local elapsed = os.clock() - t0
	print(
		string.format(
			"compile: %d modules, %d bytes -> %s (%s) in %.2f s",
			#generated,
			totalBytes,
			outDir,
			styluaNote,
			elapsed
		)
	)
	for _, c in comparisons do
		if c.status ~= "match" then
			print("  " .. c.what .. ": expected " .. tostring(c.expected) .. " got " .. tostring(c.actual))
		end
	end

	if writeReport then
		local rows = {}
		for _, row in lotsPerDistrict do
			table.insert(rows, row)
		end
		local report = Report.markdown({
			generatedAt = DateTime.now():toIsoDate(),
			luneVersion = (process.exec("lune", { "--version" }).stdout:gsub("%s+$", "")),
			harvestSha = pinSha,
			comparisons = comparisons,
			lotsPerDistrict = rows,
			lotTypeCount = #typeNames,
			lotTypes = table.concat(typeNames, ", "),
			filesValidated = filesValidated,
			schemaErrors = 0,
			invariantsChecked = invariantsChecked,
			invariantsFailed = invariantsFailed,
			warnings = warnings,
			generated = generated,
			generatedCount = #generated,
			generatedBytes = totalBytes,
			largest = largest,
			chunkKb = o.chunkKb,
			notes = {
				"`default.project.json` already maps `generated` to `ReplicatedStorage.Shared.Generated`; the `Data` accessor (W1) reads `Index.luau` and requires each chunk by name.",
				"Lot types are not yet authored (`data/lot_types/` is W1); lots carry the v5.4 `type` string and the compiler reports the distinct set above. Invariant 1 (paramSchema) therefore does not run yet.",
				'Routes carry `generator = <function>@L<line>` from the harvest call site and `origin = "harvest"`; `lotId` assignment and `harvest_patches.json` are W1 (BUILD_PLAN 4.4).',
				"The migration is re-runnable (`migrate`) and checkable (`migrate --check`); once hand edits begin in `data/authored`, stop re-running `migrate`.",
				"`check` writes to `build/compile-check/` (gitignored) and diffs against `generated/`; wire it into `tools/ci.sh` after the unit tests.",
				"Generated files are StyLua-formatted (repo `stylua.toml`) and excluded from Selene by `selene.toml`.",
				"Authored data lives under `data/authored/` (the path assigned to this task); BUILD_PLAN 1.2 names `data/town/`, `data/cast/`, `data/wildlife/` directly under `data/`. Moving the directories means changing the paths in `tools/compile/main.luau` and the `$schema` relative links; nothing else depends on them.",
				"`data/harvest/` (6.6 MB) and `tests/golden/` (11 MB) are machine output; consider Git LFS rules for `*.json` under those two directories if the repository size matters.",
			},
		})
		local reportPath = repo .. "/docs/reports/compile_report.md"
		fs.writeDir(repo .. "/docs/reports")
		fs.writeFile(reportPath, report)
		print("compile: report at " .. reportPath)
	end
end

-- ---------------------------------------------------------------- check
local function check(o: Opts)
	local tmp = o.repo .. "/build/compile-check/generated"
	if fs.isDir(tmp) then
		fs.removeDir(tmp)
	end
	compile(o, tmp, false)
	local live = o.repo .. "/generated"
	local a = listFiles(live, "%.luau$")
	local b = listFiles(tmp, "%.luau$")
	local problems = {}
	local seen: { [string]: boolean } = {}
	for _, name in b do
		seen[name] = true
		local livePath = live .. "/" .. name
		if not fs.isFile(livePath) then
			table.insert(problems, "missing in generated/: " .. name)
		elseif fs.readFile(livePath) ~= fs.readFile(tmp .. "/" .. name) then
			table.insert(problems, "stale: " .. name)
		end
	end
	for _, name in a do
		if not seen[name] then
			table.insert(problems, "extra file in generated/: " .. name)
		end
	end
	if #problems > 0 then
		fail(
			"generated/ is stale ("
				.. #problems
				.. "): "
				.. table.concat(problems, "; ")
				.. ". Run: lune run tools/compile/main.luau compile"
		)
	end
	print("check: generated/ is up to date (" .. #b .. " files)")
end

local o = parseArgs(process.args)
if o.command == "migrate" then
	migrate(o)
elseif o.command == "compile" then
	compile(o, o.repo .. "/generated", true)
elseif o.command == "check" then
	check(o)
elseif o.command == "all" then
	migrate(o)
	compile(o, o.repo .. "/generated", true)
else
	fail("unknown command " .. o.command .. " (migrate | compile | check | all)")
end
