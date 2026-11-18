--!strict
-- Luau Execution task script: the whack-a-mole flow on a server with no clients (tests/engine/WhackAMoleFlow).
-- Seats a stub player at the cabinet with a stub watching beside it: a strike in the count-in refused, a few
-- seconds of moles struck from the stream (every one a hit, +10, the watcher sent the same), a scripted miss
-- (-2), the cabinet refused to the watcher while the round is on, the round running out by itself (its end said
-- once, on the cabinet's board), Play again, and the player walking off mid-round (the cabinet idle, the watcher
-- told, nothing more sent to the player). About a minute of real time: strikes are judged on the shared clock.
-- NOT YET RUN in the engine: written 2026-11-18 for later (the cloud tools were off limits to the session that
-- wrote it). The same flow passes under Lune on the fake engine (tests/isolated/whack_a_mole_client.luau).
-- Sent by: node tools/cloud/cloud.mjs run_engine_tests tools/cloud/tasks/whack_a_mole_flow.luau --version <v> --place ci
-- (a saved CI place built from ci.project.json with build/Attractions.rbxm baked in)

local ServerStorage = game:GetService("ServerStorage")

local engineTests = ServerStorage:FindFirstChild("EngineTests")
if not engineTests then
	error("ServerStorage.EngineTests missing: run with --inject ci.project.json or a CI place version")
end

local FlowModule = engineTests:FindFirstChild("WhackAMoleFlow") :: ModuleScript
local WhackAMoleFlow = (require :: any)(FlowModule) :: { run: () -> any }
local started = os.clock()
local result = WhackAMoleFlow.run()
print(`WhackAMoleFlow: ok={result.ok} failures={#result.failures}`)
for _, f in result.failures do
	print(`  FAIL {f}`)
end
for name, n in result.numbers do
	print(`  {name}: {n}`)
end
return {
	suite = "WhackAMoleFlow",
	ok = result.ok,
	failures = result.failures,
	numbers = result.numbers,
	placeVersion = game.PlaceVersion,
	elapsedSeconds = os.clock() - started,
}
