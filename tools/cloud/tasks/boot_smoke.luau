--!strict
-- Luau Execution task script (spike S1; BUILD_PLAN §6.5 BootSmoke).
-- Runs in the real engine against a pinned CI-place version; scripts do not auto-run there, so
-- this file requires ServerStorage.EngineTests.BootSmoke explicitly and returns its JSON result.
-- Sent by: node tools/cloud/cloud.mjs run_engine_tests --version <v> tools/cloud/tasks/boot_smoke.luau

local ServerStorage = game:GetService("ServerStorage")

local engineTests = ServerStorage:FindFirstChild("EngineTests")
if not engineTests then
	error("ServerStorage.EngineTests missing: this version was not built from ci.project.json")
end

local BootSmoke = require(engineTests:FindFirstChild("BootSmoke") :: ModuleScript)
local started = os.clock()
local result = BootSmoke.run()

print(
	`BootSmoke: ok={result.ok} injected={result.injected} required={result.required} failed={#result.failed} warnings={#result.warnings} unreadable={#result.unreadableProperties}`
)
for _, failure in result.failed do
	print(`  FAIL {failure.path}: {failure.err}`)
end

return {
	suite = "BootSmoke",
	ok = result.ok,
	required = result.required,
	failed = result.failed,
	properties = result.properties,
	unreadableProperties = result.unreadableProperties,
	warnings = result.warnings,
	injected = result.injected,
	stringRequireOk = result.stringRequireOk,
	roots = result.roots,
	placeId = game.PlaceId,
	placeVersion = game.PlaceVersion,
	jobId = game.JobId,
	elapsedSeconds = os.clock() - started,
}
