--!strict
-- Luau Execution task script: Pepper's Corner Store in the engine (tests/engine/CornerStoreFlow): the bake in the
-- place, buying through the real wallet, the Tools a buyer is handed, a few items used in the world. Written for
-- the day Luau Execution works for the key again; not run.
-- Sent by: node tools/cloud/cloud.mjs run_engine_tests tools/cloud/tasks/corner_store_flow.luau --version <v> --place ci

local ServerStorage = game:GetService("ServerStorage")

local engineTests = ServerStorage:FindFirstChild("EngineTests")
if not engineTests then
	error("ServerStorage.EngineTests missing: build the place from ci.project.json")
end

local FlowModule = engineTests:FindFirstChild("CornerStoreFlow") :: ModuleScript
local Flow = (require :: any)(FlowModule) :: { run: () -> any }
local started = os.clock()
local result = Flow.run()
print(`CornerStoreFlow: ok={result.ok} failures={#result.failures}`)
for _, f in result.failures do
	print(`  FAIL {f}`)
end
return {
	suite = "CornerStoreFlow",
	ok = result.ok,
	failures = result.failures,
	numbers = result.numbers,
	placeVersion = game.PlaceVersion,
	elapsedSeconds = os.clock() - started,
}
