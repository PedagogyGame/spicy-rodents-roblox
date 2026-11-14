--!strict
-- Luau Execution task script: a whole paintball match on a server with no clients, bots only
-- (tests/engine/PaintballFlow). One stub person buys a pass, joins at the arena door and stands in its spawn
-- room; the bots play. Reports the pass, the roster (one person, seven bots, four a side), the briefing and
-- the live match (snapshots, balls, tags against the scores), a click refused from the spawn room, a scripted
-- tag and the respawn after it, the end card and the door shut during it, the next match beginning by
-- itself, and leaving (the table closed, the body in the lobby, nothing more stepped); and what the
-- service's step cost while the bots played (the whole step and its balls, bots and rest shares: the
-- average and the 95th centile of the whole step are asserted under the contract's 1.5 ms and the worst
-- step under a quarter of a frame, checklist PB-15), and the refusals by the rule that refused them.
-- The match runs on the clock clients share, so this takes about a minute of real time.
-- NOT YET RUN in the engine: the session that wrote it (2026-11-13) had the cloud tools off limits, and it
-- needs the arena baked into the place (the arena lane's tools/bake/games/Paintball) and the real match
-- model and bots (the match-and-bots lane's): against the stubs the match never goes live and this reports
-- so. The same flow passes under Lune on the fake engine with a scripted match model and scripted bots
-- (tests/isolated/paintball_server_fire.luau).
-- Sent by: node tools/cloud/cloud.mjs run_engine_tests tools/cloud/tasks/paintball_flow.luau --version <v> --place ci
-- (a saved CI place built from ci.project.json with build/Attractions.rbxm baked in)

local ServerStorage = game:GetService("ServerStorage")

local engineTests = ServerStorage:FindFirstChild("EngineTests")
if not engineTests then
	error("ServerStorage.EngineTests missing: run with --inject ci.project.json or a CI place version")
end

local PaintballFlowModule = engineTests:FindFirstChild("PaintballFlow") :: ModuleScript
local PaintballFlow = (require :: any)(PaintballFlowModule) :: { run: () -> any }
local started = os.clock()
local result = PaintballFlow.run()
print(`PaintballFlow: ok={result.ok} failures={#result.failures}`)
for _, f in result.failures do
	print(`  FAIL {f}`)
end
local n = result.numbers
local function share(name: string): string
	local s = n[name]
	if type(s) ~= "table" then
		return `{name} not measured`
	end
	return string.format("%s %.3f ms (95th centile %.3f, worst %.3f)", name, s.avg, s.p95 or 0, s.max)
end
print(
	`  live for {tostring(n.liveSeconds)} s: {tostring(n.snapshots)} snapshots, {tostring(n.balls)} balls, {tostring(
		n.tags
	)} tags`
)
print(`  the step: {share("stepMs")}; {share("ballsMs")}; {share("botsMs")}; {share("restMs")}`)
local function byWhat(map: any): string
	local parts = {}
	for what, count in map or {} do
		table.insert(parts, `{what} {count}`)
	end
	table.sort(parts)
	return if #parts > 0 then table.concat(parts, ", ") else "none"
end
if type(n.stats) == "table" then
	print(
		`  refused: {tostring(n.stats.movesRefused)} Moves ({byWhat(n.stats.movesRefusedBy)}), {tostring(
			n.stats.shotsRefused
		)} clicks ({byWhat(n.stats.shotsRefusedBy)}); corrections {tostring(n.stats.corrections)}`
	)
end
if n.banner ~= nil then
	print(`  the end banner: {tostring(n.banner)}`)
end
return {
	suite = "PaintballFlow",
	ok = result.ok,
	failures = result.failures,
	numbers = result.numbers,
	placeVersion = game.PlaceVersion,
	elapsedSeconds = os.clock() - started,
}
