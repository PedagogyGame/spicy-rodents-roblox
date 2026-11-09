--!strict
-- Luau Execution task (spike S6): TerrainBake timing in ONE task. Writes the v5.4 playable
-- rectangle from World/Height (target < 20 s; plan S6 < 25 s with extensions and bands), then the
-- near-hill bands, timed separately. Returns both stats.
-- Sent by: node tools/cloud/cloud.mjs run_engine_tests tools/cloud/tasks/world_terrain.luau --version <v> --timeout 300s
local ServerStorage = game:GetService("ServerStorage")
local tests = ServerStorage:FindFirstChild("EngineTests") or error("ServerStorage.EngineTests missing")
local WorldBuild = (require :: any)(tests:FindFirstChild("WorldBuild") :: ModuleScript)
local wall0 = DateTime.now().UnixTimestampMillis
local town = WorldBuild.terrain("town")
local wall1 = DateTime.now().UnixTimestampMillis
print(`terrain town: {town.seconds} s, {town.voxels} voxels, {town.chunks} chunks`)
-- read-back: road centre (asphalt at y 0), river channel (mud bed, water to 6 st), east hills
-- (grass up to Height.at), the bridge-strip bank
local probeTown = WorldBuild.probe({ { 2, 2 }, { 2125, 250 }, { 1177.5, -225 }, { 1880, 500 } }, -16, 32)
local bands = WorldBuild.terrain("bands")
local wall2 = DateTime.now().UnixTimestampMillis
print(`terrain bands: {bands.seconds} s, {bands.voxels} voxels`)
return {
	suite = "WorldTerrain",
	ok = town.seconds < 20,
	town = town,
	townWallMs = wall1 - wall0,
	bands = bands,
	bandsWallMs = wall2 - wall1,
	probeTown = probeTown,
	probeBand = WorldBuild.probe({ { -3000, -3000 } }, -16, 256),
	placeVersion = game.PlaceVersion,
}
