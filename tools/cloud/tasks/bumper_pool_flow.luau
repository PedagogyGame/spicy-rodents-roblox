--!strict
-- Luau Execution task script: the bumper pool flow on a server with no clients (tests/engine/BumperPoolFlow).
-- Seats stub players at the bumper pool table and plays what the computer players would play through the input
-- path, and reports: practice (a strike, one script to everyone, nothing judged while the balls roll, the ball
-- Models where the rules lay them, the other five out of sight); a whole game against Bumper Bob from the
-- opening (one script carrying both strikes) to the end; two people opening together, one leaving and
-- forfeiting; the table at rest with nothing more sent.
-- NOT YET RUN in the engine: the session that wrote it (2026-11-13) had the cloud tools off limits. The same
-- flow passes under Lune on the fake engine (tests/isolated/bumper_pool_game.luau). The service is stepped as
-- fast as it goes (bumper pool judges nothing by the shared clock).
-- Sent by: node tools/cloud/cloud.mjs run_engine_tests tools/cloud/tasks/bumper_pool_flow.luau --version <v> --place ci
-- (a saved CI place built from ci.project.json with build/Attractions.rbxm baked in)

local ServerStorage = game:GetService("ServerStorage")

local engineTests = ServerStorage:FindFirstChild("EngineTests")
if not engineTests then
	error("ServerStorage.EngineTests missing: run with --inject ci.project.json or a CI place version")
end

local FlowModule = engineTests:FindFirstChild("BumperPoolFlow") :: ModuleScript
local BumperPoolFlow = (require :: any)(FlowModule) :: { run: () -> any }
local started = os.clock()
local result = BumperPoolFlow.run()
print(`BumperPoolFlow: ok={result.ok} failures={#result.failures}`)
for _, f in result.failures do
	print(`  FAIL {f}`)
end
local keys: { string } = {}
for k in result.numbers do
	table.insert(keys, k)
end
table.sort(keys)
for _, k in keys do
	print(`  {k}: {result.numbers[k]}`)
end
return {
	suite = "BumperPoolFlow",
	ok = result.ok,
	failures = result.failures,
	numbers = result.numbers,
	placeVersion = game.PlaceVersion,
	elapsedSeconds = os.clock() - started,
}
