--!strict
-- tools/games/paintball/arena/bake_nav: writes the arena's navigation graph into the game.
--   lune run tools/games/paintball/arena/bake_nav.luau      (from the repository's root)
-- NavBuild works the graph out from ArenaDataPlan (a fraction of a second: too long for a client that only wants
-- the walls); this writes its answer to src/shared/Minigames/Paintball/ArenaDataNavBaked.luau as rows of numbers,
-- which ArenaData reads. RUN IT AFTER EVERY CHANGE TO THE PLAN: tests/unit/paintball_arena_nav.spec.luau fails
-- while the file is not what NavBuild makes of the plan.
local fs = require("@lune/fs")
local NavBuild = require("./NavBuild")

local PATH = "src/shared/Minigames/Paintball/ArenaDataNavBaked.luau"
local t0 = os.clock()
local nodes, links, cover = NavBuild.compute()
fs.writeFile(PATH, NavBuild.text(nodes, links, cover))
print(
	string.format(
		"bake_nav: %d nodes, %d links, %d cover spots -> %s in %.2f s",
		#nodes,
		#links,
		#cover,
		PATH,
		os.clock() - t0
	)
)
