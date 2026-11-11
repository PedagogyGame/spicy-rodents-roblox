--!strict
-- Luau Execution task script: the darts flow on a server with no clients (tests/engine/DartsFlow).
-- Seats stub throwers at the dartboard, feeds them darts and reports what every dart left: the nine-dart leg
-- of 501 (441 381 321 261 201 141 81 24 0, the rival left on 340), a leg with every kind of bust (16 darts),
-- a game of cricket (20 to 0) and three real throws; and that each session ended cleanly (the board idle with
-- no dart in it, its waiting darts back, nobody held at it, nothing more sent).
-- NOT YET RUN in the engine: the session that wrote it (2026-11-11) had the cloud tools off limits. The same
-- flow passes under Lune on the fake engine (tests/isolated/darts_client.luau).
-- Sent by: node tools/cloud/cloud.mjs run_engine_tests tools/cloud/tasks/darts_flow.luau --version <v> --place ci
-- (a saved CI place built from ci.project.json with build/Attractions.rbxm baked in)

local ServerStorage = game:GetService("ServerStorage")

local engineTests = ServerStorage:FindFirstChild("EngineTests")
if not engineTests then
	error("ServerStorage.EngineTests missing: run with --inject ci.project.json or a CI place version")
end

local DartsFlowModule = engineTests:FindFirstChild("DartsFlow") :: ModuleScript
local DartsFlow = (require :: any)(DartsFlowModule) :: { run: () -> any }
local started = os.clock()
local result = DartsFlow.run()
print(`DartsFlow: ok={result.ok} failures={#result.failures}`)
for _, f in result.failures do
	print(`  FAIL {f}`)
end
local function numbers(list: { number }?): string
	local out: { string } = {}
	local items: { number } = list or {}
	for i, n in items do
		out[i] = tostring(n)
	end
	return table.concat(out, " ")
end
for _, name in { "nine", "busts", "cricket", "real" } do
	local leg = result.legs[name]
	if leg == nil then
		print(`  {name}: not played`)
	elseif name == "cricket" then
		print(
			`  cricket: darts {table.concat(leg.darts, " ")}  points {numbers(leg.points)}  final {numbers(leg.scores)}`
		)
	elseif name == "real" then
		print(`  real: {leg.darts} darts  {table.concat(leg.labels, " ")}  left {numbers(leg.left)}`)
	else
		local tail = if leg.scores then `  final {numbers(leg.scores)}` else `  called {tostring(leg.events)}`
		print(`  {name}: darts {table.concat(leg.darts, " ")}  left {numbers(leg.left)}{tail}`)
	end
end
return {
	suite = "DartsFlow",
	ok = result.ok,
	failures = result.failures,
	numbers = result.numbers,
	legs = result.legs,
	placeVersion = game.PlaceVersion,
	elapsedSeconds = os.clock() - started,
}
