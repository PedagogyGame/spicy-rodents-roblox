--!strict
-- Luau Execution task script: the paintball movement rules held to a real body (tests/engine/PaintballFlow,
-- "the walk"; review of the server lane, 13 November: the height rule's footprint, the hop-and-fall envelope
-- and the body rule were tuned against scripted bodies only). One stub person buys a pass, joins, and once the
-- match is live its own R15 townsperson, walked by its Humanoid on a server with no clients, follows the
-- building's navigation graph out of the spawn room, up and down the stairs to all five storeys and up to the
-- atrium's rail on each, and stands at the top storey's rail for ten seconds; its Moves are sampled from that
-- body twenty times a second, and the service reads the same body for the body rule. The bots stand still.
-- Reports and holds: no correction; every storey reached; the refusals by the rule that refused them
-- (Stats.movesRefusedBy: inside, room, height, walls, speed, body) and the nodes the body could not reach.
-- Until this has run with no correction, Stream's FOOT, FALL_FLOOR and LANDING are provisional.
-- NOT YET RUN in the engine (written 2026-11-13, the cloud tools off limits); it needs the arena baked into
-- the place and the real match model (against the stub the match never goes live and this says so). The
-- same walk passes under Lune on the fake engine with a scripted body in the stand-in building
-- (tests/isolated/paintball_server_fire.luau, "the walk").
-- Sent by: node tools/cloud/cloud.mjs run_engine_tests tools/cloud/tasks/paintball_walk.luau --version <v> --place ci
-- (a saved CI place built from ci.project.json with build/Attractions.rbxm baked in)

local ServerStorage = game:GetService("ServerStorage")

local engineTests = ServerStorage:FindFirstChild("EngineTests")
if not engineTests then
	error("ServerStorage.EngineTests missing: run with --inject ci.project.json or a CI place version")
end

local PaintballFlowModule = engineTests:FindFirstChild("PaintballFlow") :: ModuleScript
local PaintballFlow = (require :: any)(PaintballFlowModule) :: { runWalk: () -> any }
local started = os.clock()
local result = PaintballFlow.runWalk()
print(`PaintballWalk: ok={result.ok} failures={#result.failures}`)
for _, f in result.failures do
	print(`  FAIL {f}`)
end
local n = result.numbers
local parts = {}
for what, count in n.movesRefusedBy or {} do
	table.insert(parts, `{what} {count}`)
end
table.sort(parts)
print(
	`  storeys {tostring(n.storeys)}, nodes walked {tostring(n.nodesWalked)}, not reached {tostring(n.nodesStuck)}; Moves accepted {tostring(
		n.movesAccepted
	)}, refused {tostring(n.movesRefused)} ({if #parts > 0 then table.concat(parts, ", ") else "none"}); corrections {tostring(
		n.corrections
	)}`
)
for _, at in n.stuckAt or {} do
	print(`  not reached: {at}`)
end
return {
	suite = "PaintballWalk",
	ok = result.ok,
	failures = result.failures,
	numbers = result.numbers,
	placeVersion = game.PlaceVersion,
	elapsedSeconds = os.clock() - started,
}
