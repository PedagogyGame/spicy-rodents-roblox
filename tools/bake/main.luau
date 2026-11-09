--!strict
-- tools/bake: Lune bake of generated/ data into build/Town.rbxm (BUILD_PLAN D6, spike S6).
-- Usage (repo root): lune run tools/bake/main.luau [--out build/Town.rbxm] [--report build/bake_report.json]
-- The rbxm is mapped to Workspace.Town by default/ci/build project files ($path optional).
-- Prints BakeHash and InstanceHash; the engine's WorldBuild suite recomputes both (BakeParity).
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Bake = require("../../src/worldgen/Bake")
local Factory = require("../../src/worldgen/Factory")

local out, report = "build/Town.rbxm", "build/bake_report.json"
local i = 1
while i <= #process.args do
	local a = process.args[i]
	if a == "--out" then
		out = process.args[i + 1]
		i += 1
	elseif a == "--report" then
		report = process.args[i + 1]
		i += 1
	else
		error("unknown argument: " .. a)
	end
	i += 1
end

local t0 = os.clock()
local lots = require("../../generated/Lots") :: any
local roads = require("../../generated/Roads") :: any
local tRequire = os.clock() - t0

local factory = Factory.new({
	Instance = roblox.Instance,
	Vector3 = roblox.Vector3,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	Enum = roblox.Enum,
})
local t1 = os.clock()
local town = Bake.run({ lots = lots, roads = roads }, factory)
local tBake = os.clock() - t1
local t2 = os.clock()
local bytes = roblox.serializeModel({ town })
if not fs.isDir("build") then
	fs.writeDir("build")
end
fs.writeFile(out, bytes)
local tWrite = os.clock() - t2

local result = {
	out = out,
	bytes = #bytes,
	lots = town:GetAttribute("LotCount"),
	roads = town:GetAttribute("RoadCount"),
	parts = town:GetAttribute("PartCount"),
	bakeHash = town:GetAttribute("BakeHash"),
	instanceHash = town:GetAttribute("InstanceHash"),
	seconds = { require = tRequire, bake = tBake, serialize = tWrite, total = os.clock() - t0 },
}
fs.writeFile(report, serde.encode("json", result, true))
print(
	`bake: {result.lots} lots, {result.roads} roads, {result.parts} parts -> {out} ({#bytes} bytes) in {string.format(
		"%.2f",
		result.seconds.total
	)} s; BakeHash {result.bakeHash} InstanceHash {result.instanceHash}`
)
