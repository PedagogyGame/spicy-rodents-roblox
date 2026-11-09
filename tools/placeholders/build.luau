--!strict
-- tools/placeholders/build: the W1 placeholder bodies and vehicles as .rbxm (BUILD_PLAN §4.4 W1 #10, §5.2).
--   lune run tools/placeholders/build.luau [outDir]      (default assets/placeholders)
-- Writes one .rbxm per puppet (squirrel, rodent, fox, deer doe/buck/fawn, drone, one block R15 human per
-- role palette with its stock HumanoidDescription) and per vehicle kind at its true logical box, validates
-- each against Actors/RigSpec (final bone, socket and region names) and writes manifest.json with part
-- counts and a content hash per file. Deterministic: rebuilding gives byte-identical files.
-- Also writes the rendered town map (town_map.svg) from Map/MapModel (W1 #11).

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local PartBuilder = require("../../src/shared/Avatar/PartBuilder")
local PuppetSpec = require("../../src/shared/Avatar/PuppetSpec")
local RolePalettes = require("../../src/shared/Avatar/RolePalettes")
local RigSpec = require("../../src/shared/Actors/RigSpec")
local VehiclePuppet = require("../../src/shared/Traffic/VehiclePuppet")
local MapModel = require("../../src/shared/Map/MapModel")

local outDir = process.args[1] or "assets/placeholders"
fs.writeDir(outDir)

local lib = {
	Instance = roblox.Instance,
	Vector3 = roblox.Vector3,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	Enum = roblox.Enum,
}

local manifest = { generator = "tools/placeholders/build.luau", files = {} :: { any } }
local failures = 0

local function emit(file: string, spec: PartBuilder.ModelSpec, species: string)
	local model = PartBuilder.instantiate(spec, lib)
	local report = RigSpec.validate(model, species)
	if not report.ok then
		failures += 1
		print(`FAIL {file}: {serde.encode("json", report)}`)
	end
	local bytes = roblox.serializeModel({ model })
	fs.writeFile(`{outDir}/{file}`, bytes)
	table.insert(manifest.files, {
		file = file,
		species = species,
		parts = #spec.parts,
		joints = #spec.joints,
		sockets = #spec.attachments,
		bytes = #bytes,
		sha = serde.hash("sha256", bytes),
		rigspec = report.ok,
	})
end

for _, species in { "squirrel", "rodent", "fox" } do
	emit(`{species}.rbxm`, PuppetSpec.spec(species), species)
end
for _, variant in { "doe", "buck", "fawn" } do
	emit(`deer_{variant}.rbxm`, PuppetSpec.spec("deer", { variant = variant }), "deer")
end
emit("drone.rbxm", PuppetSpec.spec("drone"), "drone")
for _, role in RolePalettes.ROLES do
	emit(`human_{role}.rbxm`, PuppetSpec.human(role, 1, lib), "human")
end
for _, kind in VehiclePuppet.KINDS do
	emit(`vehicle_{kind}.rbxm`, VehiclePuppet.spec(kind), "car")
end

local luau = require("@lune/luau")
local function generated(name: string): any
	return luau.load(fs.readFile(`generated/{name}.luau`), { debugName = name })()
end
local map = MapModel.fromData({
	lots = generated("Lots"),
	roads = generated("Roads"),
	lotTypes = generated("LotTypes"),
	extensions = generated("TerrainExtensions"),
})
local svg = MapModel.svg(map, { width = 1024 })
fs.writeFile(`{outDir}/town_map.svg`, svg)
table.insert(manifest.files, { file = "town_map.svg", bytes = #svg, sha = serde.hash("sha256", svg) })

table.sort(manifest.files, function(a, b)
	return a.file < b.file
end)
fs.writeFile(`{outDir}/manifest.json`, serde.encode("json", manifest, true))
print(`placeholders: {#manifest.files} files in {outDir}, {failures} RigSpec failures`)
if failures > 0 then
	process.exit(1)
end
