--!strict
-- Luau Execution task script: the first playable build's scripted smoke (tests/engine/PlayBuild).
-- Sent by: node tools/cloud/cloud.mjs run_engine_tests tools/cloud/tasks/play_smoke.luau --version <v>
--          --place ci --inject ci.project.json --inject-exclude generated

local ServerStorage = game:GetService("ServerStorage")

local engineTests = ServerStorage:FindFirstChild("EngineTests")
if not engineTests then
	error("ServerStorage.EngineTests missing: run with --inject ci.project.json")
end

local PlayBuildModule = engineTests:FindFirstChild("PlayBuild") :: ModuleScript
local PlayBuild = (require :: any)(PlayBuildModule) :: { run: () -> any }
local started = os.clock()
local result = PlayBuild.run()
print(`PlayBuild: ok={result.ok} failures={#result.failures}`)
for _, f in result.failures do
	print(`  FAIL {f}`)
end
return {
	suite = "PlayBuild",
	ok = result.ok,
	failures = result.failures,
	numbers = result.numbers,
	placeVersion = game.PlaceVersion,
	elapsedSeconds = os.clock() - started,
}
