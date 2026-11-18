--!strict
-- Luau Execution task script: the paintball bots on a real server (Server/Minigames/Paintball/BotCheck):
-- fifteen bots play two minutes of a match of their own and the task reports what Bots.step cost a
-- tick in the engine (Contract.COST.botsMs is the budget), how many balls and tags there were, and
-- whether any bot broke a rule of conduct. NOT YET RUN: the key's Luau Execution permission was away
-- when it was written (docs/HANDOFF.md section 0). Send it with
--   node tools/cloud/cloud.mjs run_engine_tests tools/games/paintball/bots/engine_check.luau --version <v>
--       --place ci --inject ci.project.json --inject-exclude generated
-- It needs no arena in the place: the bots run on the arena's data.
local ServerScriptService = game:GetService("ServerScriptService")

local server = ServerScriptService:FindFirstChild("Server")
	or error("ServerScriptService.Server missing: run with --inject")
local minigames = server:FindFirstChild("Minigames") or error("Server.Minigames missing")
local paintball = minigames:FindFirstChild("Paintball") or error("Server.Minigames.Paintball missing")
local BotCheck = (require :: any)(paintball:FindFirstChild("BotCheck") :: ModuleScript)

local started = os.clock()
local result = BotCheck.run({ seconds = 120 })
local n = result.numbers
print(
	string.format(
		"PaintballBots: ok=%s; Bots.step %.3f ms a tick with %d bots (budget %.1f, worst %.2f, %.1f%% of ticks over); %d balls, %d tags",
		tostring(result.ok),
		n.botsMs,
		n.bots,
		n.budgetMs,
		n.botsMsWorst,
		n.overBudget * 100,
		n.shots,
		n.tags
	)
)
for _, f in result.failures do
	print(`  FAIL {f}`)
end
return {
	suite = "PaintballBots",
	ok = result.ok,
	failures = result.failures,
	numbers = n,
	placeVersion = game.PlaceVersion,
	elapsedSeconds = os.clock() - started,
}
