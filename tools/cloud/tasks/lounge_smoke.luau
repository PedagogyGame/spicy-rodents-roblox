--!strict
-- Luau Execution task script: THE GILDED ACORN's door, guards and bar on a server with no clients
-- (tests/engine/Lounge). Starts Server/Attractions/LoungeService on its own with stub players (a purse, a pass), a
-- stand-in for the bake's staff and a clock the check moves, and reports: a person with the pass let in (first
-- person, facing the room), one without told "Members only." and the offer, the pass bought with 25c and refused
-- with 7c, a squirrel's and a fox's press refused, a squirrel at 50 spots in and around the lounge (knocked out on
-- the forecourt, the steps, the landing and in the room; never on Bowl Lane, the roof or along the front), the four
-- drinks bought, sipped and finished, leaving with a drink in the hand, a new body, a leaver.
-- NOT YET RUN in the engine: written while the key had no Luau Execution permission. The same flow passes under
-- Lune on the fake engine (tests/isolated/lounge_service.luau).
-- Sent by: node tools/cloud/cloud.mjs run_engine_tests tools/cloud/tasks/lounge_smoke.luau --version <v> --place ci
-- (a saved CI place built from ci.project.json)

local ServerStorage = game:GetService("ServerStorage")

local engineTests = ServerStorage:FindFirstChild("EngineTests")
if not engineTests then
	error("ServerStorage.EngineTests missing: run with --inject ci.project.json or a CI place version")
end

local LoungeModule = engineTests:FindFirstChild("Lounge") :: ModuleScript
local LoungeFlow = (require :: any)(LoungeModule) :: { run: () -> any }
local started = os.clock()
local result = LoungeFlow.run()
print(`Lounge: ok={result.ok} failures={#result.failures}`)
for _, f in result.failures do
	print(`  FAIL {f}`)
end
local n = result.numbers or {}
if n.guards then
	print(
		`  guards: {n.guards.tried} spots, {n.guards.struck} struck, {n.guards.spared} spared, {n.guards.wrong} wrong`
	)
end
if n.drinks then
	print(`  drinks: {n.drinks.spent}c spent on the four`)
end
return {
	suite = "Lounge",
	ok = result.ok,
	failures = result.failures,
	numbers = result.numbers,
	placeVersion = game.PlaceVersion,
	elapsedSeconds = os.clock() - started,
}
