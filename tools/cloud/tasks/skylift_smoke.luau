--!strict
-- Luau Execution task script: the sky lift's rider flow on a server with no clients (tests/engine/SkyLift).
-- Starts Server/Rides/SkyLiftService on its own with stub players and a clock the check moves, and reports: a
-- person up and a person down (device grant ride/gondola/first person at the cabin's doors, on the seat all the
-- way, on the far platform with the arrival words within 2 s of the timetable), a squirrel and a driver refused
-- with words, five at once (four in one cabin, the fifth in the next), walking away from the gate, a rider whose
-- player leaves mid-ride (held, then handed to its brain on the platform), and 200 random boardings and leaves
-- with nothing left behind.
-- NOT YET RUN in the engine: written while the key had no Luau Execution permission (2026-11-11). The same flow
-- passes under Lune on the fake engine (tests/isolated/skylift_service.luau).
-- Sent by: node tools/cloud/cloud.mjs run_engine_tests tools/cloud/tasks/skylift_smoke.luau --version <v> --place ci
-- (a saved CI place built from ci.project.json)

local ServerStorage = game:GetService("ServerStorage")

local engineTests = ServerStorage:FindFirstChild("EngineTests")
if not engineTests then
	error("ServerStorage.EngineTests missing: run with --inject ci.project.json or a CI place version")
end

local SkyLiftModule = engineTests:FindFirstChild("SkyLift") :: ModuleScript
local SkyLiftFlow = (require :: any)(SkyLiftModule) :: { run: () -> any }
local started = os.clock()
local result = SkyLiftFlow.run()
print(`SkyLift: ok={result.ok} failures={#result.failures}`)
for _, f in result.failures do
	print(`  FAIL {f}`)
end
local n = result.numbers or {}
if n.up then
	print(`  up: waited {n.up.wait} s, rode {n.up.ride} s, seat error {n.up.seatError}, stood {n.up.fromAlight} back`)
end
if n.down then
	print(`  down: waited {n.down.wait} s, rode {n.down.ride} s, seat error {n.down.seatError}`)
end
if n.soak then
	print(`  soak: {n.soak.presses} presses, {n.soak.granted} boardings`)
end
return {
	suite = "SkyLift",
	ok = result.ok,
	failures = result.failures,
	numbers = result.numbers,
	placeVersion = game.PlaceVersion,
	elapsedSeconds = os.clock() - started,
}
