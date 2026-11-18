--!strict
-- Luau Execution task script: the air hockey flow on a server with no clients (tests/engine/AirHockeyFlow).
-- Seats stub players at the table's two ends, drives each one's hand through a real Seat (the prediction and
-- log a client runs) on the real shared clock, and reports: a match against the computer stepped from the log
-- with the stream matching the stub's own prediction to the last bit; a scripted seventh goal scored by the
-- simulation's own goal line and announced once; Play again; a second person taking the computer's end in
-- mid-match and handing it back; and the table at rest with nothing more sent.
-- NOT YET RUN in the engine: the session that wrote it (2026-11-13) had the cloud tools off limits. The same
-- flow passes under Lune on the fake engine (tests/isolated/air_hockey_client.luau). It takes about twenty
-- seconds of real time: the logs are judged against the shared clock.
-- Sent by: node tools/cloud/cloud.mjs run_engine_tests tools/cloud/tasks/air_hockey_flow.luau --version <v> --place ci
-- (a saved CI place built from ci.project.json with build/Attractions.rbxm baked in)

local ServerStorage = game:GetService("ServerStorage")

local engineTests = ServerStorage:FindFirstChild("EngineTests")
if not engineTests then
	error("ServerStorage.EngineTests missing: run with --inject ci.project.json or a CI place version")
end

local FlowModule = engineTests:FindFirstChild("AirHockeyFlow") :: ModuleScript
local AirHockeyFlow = (require :: any)(FlowModule) :: { run: () -> any }
local started = os.clock()
local result = AirHockeyFlow.run()
print(`AirHockeyFlow: ok={result.ok} failures={#result.failures}`)
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
	suite = "AirHockeyFlow",
	ok = result.ok,
	failures = result.failures,
	numbers = result.numbers,
	placeVersion = game.PlaceVersion,
	elapsedSeconds = os.clock() - started,
}
