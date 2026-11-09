--!strict
-- tools/bake/check.luau: the WorldBuild exit checks in Lune (BUILD_PLAN §4.4 #7) on the bake plans:
-- route-on-geometry (RouteCheck, harvest_patches exempt), door reachability (DoorReach), solid lot
-- overlaps, Skyline coverage, the hospital's rooms and the station console, lamp coverage.
-- Usage (repo root): lune run tools/bake/check.luau [--json build/world_checks.json] [--list]
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local WorldChecks = require("../../src/worldgen/WorldChecks")

local out, list = "build/world_checks.json", false
for i, a in process.args do
	if a == "--json" then
		out = process.args[i + 1]
	elseif a == "--list" then
		list = true
	end
end
local t0 = os.clock()
local r = WorldChecks.run()
if not fs.isDir("build") then
	fs.writeDir("build")
end
fs.writeFile(out, serde.encode("json", r, true))
print(string.format("world checks in %.2f s: %s", os.clock() - t0, if r.ok then "ok" else "FAILED"))
for _, f in r.failures do
	print("  FAIL " .. f)
end
if list then
	for _, f in r.routes.failures do
		print(
			string.format(
				"  route %d %s [%s %s] worst %.2f st at %.1f,%.1f,%.1f",
				f.id,
				f.name,
				f.kind,
				f.generator,
				f.worst,
				f.at[1],
				f.at[2],
				f.at[3]
			)
		)
	end
end
if not r.ok then
	process.exit(1)
end
