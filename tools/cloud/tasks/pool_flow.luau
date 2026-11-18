--!strict
-- Luau Execution task script: the eight-ball flow on a server with no clients (tests/engine/PoolFlow).
-- Seats stub players at pool table 1 and plays what the computer players would play through the input path,
-- and reports: practice (the cue ball set down, the break, one script to everyone, nothing judged while the
-- balls roll, the ball Models where the rules lay them); a scripted 8 called and potted; a whole game against
-- Chalky with Play again and the winner breaking; two people, one leaving and forfeiting; the table at rest
-- with nothing more sent.
-- NOT YET RUN in the engine: the session that wrote it (2026-11-13) had the cloud tools off limits. The same
-- flow passes under Lune on the fake engine (tests/isolated/pool_game.luau). The service is stepped as fast as
-- it goes (pool judges nothing by the shared clock).
-- Sent by: node tools/cloud/cloud.mjs run_engine_tests tools/cloud/tasks/pool_flow.luau --version <v> --place ci
-- (a saved CI place built from ci.project.json with build/Attractions.rbxm baked in)

local ServerStorage = game:GetService("ServerStorage")

local engineTests = ServerStorage:FindFirstChild("EngineTests")
if not engineTests then
	error("ServerStorage.EngineTests missing: run with --inject ci.project.json or a CI place version")
end

local FlowModule = engineTests:FindFirstChild("PoolFlow") :: ModuleScript
local PoolFlow = (require :: any)(FlowModule) :: { run: () -> any }
local started = os.clock()
local result = PoolFlow.run()
print(`PoolFlow: ok={result.ok} failures={#result.failures}`)
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
	suite = "PoolFlow",
	ok = result.ok,
	failures = result.failures,
	numbers = result.numbers,
	placeVersion = game.PlaceVersion,
	elapsedSeconds = os.clock() - started,
}
