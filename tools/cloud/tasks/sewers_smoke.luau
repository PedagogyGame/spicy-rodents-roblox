--!strict
-- Luau Execution task script: the storm drains in the engine (tests/engine/Sewers): the carve read back after the
-- terrain write, Workspace.Sewers as published, the owner's modules loaded as the game loads them and checked where
-- the client looks for them. Written for the day Luau Execution works for the key again (lost 2026-11-11); not run.
-- Sent by: node tools/cloud/cloud.mjs run_engine_tests tools/cloud/tasks/sewers_smoke.luau --version <v> --place ci

local ServerStorage = game:GetService("ServerStorage")

local engineTests = ServerStorage:FindFirstChild("EngineTests")
if not engineTests then
	error("ServerStorage.EngineTests missing: build the place from ci.project.json")
end

local SewersModule = engineTests:FindFirstChild("Sewers") :: ModuleScript
local Sewers = (require :: any)(SewersModule) :: { run: () -> any }
local started = os.clock()
local result = Sewers.run()
print(`Sewers: ok={result.ok} failures={#result.failures}`)
for _, f in result.failures do
	print(`  FAIL {f}`)
end
return {
	suite = "Sewers",
	ok = result.ok,
	failures = result.failures,
	numbers = result.numbers,
	placeVersion = game.PlaceVersion,
	elapsedSeconds = os.clock() - started,
}
