--!strict
-- Luau Execution task script: the backdrop and day-cycle smoke (tests/engine/Backdrop): boot terrain beyond the
-- clamp and the near sea, Workspace.Backdrop's streaming and limits, the published clock, Sky.step on Lighting.
-- Sent by: node tools/cloud/cloud.mjs run_engine_tests tools/cloud/tasks/backdrop_smoke.luau --version <v> --place ci

local ServerStorage = game:GetService("ServerStorage")

local engineTests = ServerStorage:FindFirstChild("EngineTests")
if not engineTests then
	error("ServerStorage.EngineTests missing: build the place from ci.project.json")
end

local BackdropModule = engineTests:FindFirstChild("Backdrop") :: ModuleScript
local Backdrop = (require :: any)(BackdropModule) :: { run: () -> any }
local started = os.clock()
local result = Backdrop.run()
print(`Backdrop: ok={result.ok} failures={#result.failures}`)
for _, f in result.failures do
	print(`  FAIL {f}`)
end
return {
	suite = "Backdrop",
	ok = result.ok,
	failures = result.failures,
	numbers = result.numbers,
	placeVersion = game.PlaceVersion,
	elapsedSeconds = os.clock() - started,
}
