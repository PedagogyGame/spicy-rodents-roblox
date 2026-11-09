--!strict
-- Luau Execution task (spike S6; BUILD_PLAN §6.5 WorldBuild + BakeParity): requires
-- ServerStorage.EngineTests.WorldBuild on a saved CI version that contains Workspace.Town
-- (rojo build ci.project.json after `lune run tools/bake/main.luau`) and returns its JSON.
-- Sent by: node tools/cloud/cloud.mjs run_engine_tests tools/cloud/tasks/world_build.luau --version <v>
local ServerStorage = game:GetService("ServerStorage")
local tests = ServerStorage:FindFirstChild("EngineTests") or error("ServerStorage.EngineTests missing")
local WorldBuild = (require :: any)(tests:FindFirstChild("WorldBuild") :: ModuleScript)
local started = os.clock()
local result = WorldBuild.run()
print(`WorldBuild: ok={result.ok} failures={#result.failures}`)
for _, f in result.failures do
	print("  FAIL " .. f)
end
result.suite = "WorldBuild"
result.placeVersion = game.PlaceVersion
result.elapsedSeconds = os.clock() - started
return result
