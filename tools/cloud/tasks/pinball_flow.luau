--!strict
-- Luau Execution task script: the pinball flow on a server with no clients (tests/engine/PinballFlow).
-- Seats stub players at the three machines, each playing its balls on a Replay of its own (the same live play
-- and input log a client runs, the model's computer player at the buttons), and reports: a whole game alone on
-- ACORN ATTACK (the server's replay ends on the player's own score, fair, the board written on the cabinet), two
-- players on SPICY RODENT taking a ball each in turn and one leaving (the other sent the server's game, the
-- leaver's score kept), a ball played out by the server on SPACE SQUIRREL (the player carries on from the
-- server's game), and every machine idle at the end with nobody held and nothing more sent.
-- NOT YET RUN in the engine: the session that wrote it (2026-11-13) had the cloud tools off limits. The same flow
-- passes under Lune on the fake engine (tests/isolated/pinball_client.luau).
-- Sent by: node tools/cloud/cloud.mjs run_engine_tests tools/cloud/tasks/pinball_flow.luau --version <v> --place ci
-- (a saved CI place built from ci.project.json with build/Attractions.rbxm baked in)

local ServerStorage = game:GetService("ServerStorage")

local engineTests = ServerStorage:FindFirstChild("EngineTests")
if not engineTests then
	error("ServerStorage.EngineTests missing: run with --inject ci.project.json or a CI place version")
end

local PinballFlowModule = engineTests:FindFirstChild("PinballFlow") :: ModuleScript
local PinballFlow = (require :: any)(PinballFlowModule) :: { run: () -> any }
local started = os.clock()
local result = PinballFlow.run()
print(`PinballFlow: ok={result.ok} failures={#result.failures}`)
for _, f in result.failures do
	print(`  FAIL {f}`)
end
for k, v in result.numbers do
	print(`  {k}: {tostring(v)}`)
end
return {
	suite = "PinballFlow",
	ok = result.ok,
	failures = result.failures,
	numbers = result.numbers,
	placeVersion = game.PlaceVersion,
	elapsedSeconds = os.clock() - started,
}
