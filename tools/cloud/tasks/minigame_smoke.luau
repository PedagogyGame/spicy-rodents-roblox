--!strict
-- Luau Execution task script: the bowling alley and minigame framework smoke (tests/engine/Minigames).
-- Sent by: node tools/cloud/cloud.mjs run_engine_tests tools/cloud/tasks/minigame_smoke.luau --version <v> --place ci
-- (a saved CI place built from ci.project.json with build/Attractions.rbxm baked in)

local ServerStorage = game:GetService("ServerStorage")

local engineTests = ServerStorage:FindFirstChild("EngineTests")
if not engineTests then
	error("ServerStorage.EngineTests missing: run with --inject ci.project.json or a CI place version")
end

local MinigamesModule = engineTests:FindFirstChild("Minigames") :: ModuleScript
local Minigames = (require :: any)(MinigamesModule) :: { run: () -> any }
local started = os.clock()
local result = Minigames.run()
print(`Minigames: ok={result.ok} failures={#result.failures}`)
for _, f in result.failures do
	print(`  FAIL {f}`)
end
return {
	suite = "Minigames",
	ok = result.ok,
	failures = result.failures,
	numbers = result.numbers,
	placeVersion = game.PlaceVersion,
	elapsedSeconds = os.clock() - started,
}
