--!strict
-- Luau Execution task script: the bowling flow on a server with no clients (tests/engine/BowlingFlow).
-- Seats stub bowlers at two lanes, feeds them throws and reports every sheet: twelve strikes (300), a mixed
-- game of strikes, spares and open frames (167), all spares (150) and a whole game of real throws; and that
-- each session ended cleanly (the lane idle and whole, nobody held at it, nothing more sent).
-- NOT YET RUN in the engine: the session that wrote it (2026-11-11) had the cloud tools off limits. The same
-- flow passes under Lune on the fake engine (tests/isolated/minigames_service.luau).
-- Sent by: node tools/cloud/cloud.mjs run_engine_tests tools/cloud/tasks/bowling_flow.luau --version <v> --place ci
-- (a saved CI place built from ci.project.json with build/Attractions.rbxm baked in)

local ServerStorage = game:GetService("ServerStorage")

local engineTests = ServerStorage:FindFirstChild("EngineTests")
if not engineTests then
	error("ServerStorage.EngineTests missing: run with --inject ci.project.json or a CI place version")
end

local BowlingFlowModule = engineTests:FindFirstChild("BowlingFlow") :: ModuleScript
local BowlingFlow = (require :: any)(BowlingFlowModule) :: { run: () -> any }
local started = os.clock()
local result = BowlingFlow.run()
print(`BowlingFlow: ok={result.ok} failures={#result.failures}`)
for _, f in result.failures do
	print(`  FAIL {f}`)
end
for _, name in { "perfect", "mixed", "spares", "real" } do
	local g = result.games[name]
	if g then
		local frames: { string } = {}
		for f = 1, 10 do
			frames[f] = tostring(g.frames[f])
		end
		print(`  {name}: {g.total}  frames {table.concat(frames, " ")}  marks {table.concat(g.marks, " | ")}`)
	else
		print(`  {name}: not played`)
	end
end
return {
	suite = "BowlingFlow",
	ok = result.ok,
	failures = result.failures,
	numbers = result.numbers,
	games = result.games,
	placeVersion = game.PlaceVersion,
	elapsedSeconds = os.clock() - started,
}
