--!strict
-- Luau Execution task script: the playtester smoke of the first playable build (tests/engine/Playtest).
-- Sent by: node tools/cloud/cloud.mjs run_engine_tests tools/cloud/tasks/playtest_smoke.luau --version <v>
--          --place ci --inject ci.project.json --inject-exclude generated

local ServerStorage = game:GetService("ServerStorage")

local engineTests = ServerStorage:FindFirstChild("EngineTests")
if not engineTests then
	error("ServerStorage.EngineTests missing: run with --inject ci.project.json")
end

local PlaytestModule = engineTests:FindFirstChild("Playtest") :: ModuleScript
local Playtest = (require :: any)(PlaytestModule) :: { run: () -> any }
local started = os.clock()
local result = Playtest.run()
print(`Playtest: ok={result.ok} failures={#result.failures}`)
for _, f in result.failures do
	print(`  FAIL {f}`)
end
return {
	suite = "Playtest",
	ok = result.ok,
	failures = result.failures,
	numbers = result.numbers,
	placeVersion = game.PlaceVersion,
	elapsedSeconds = os.clock() - started,
}
