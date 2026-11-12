--!strict
-- ReplicatedStorage.Shared.Minigames.Paintball.Spec
-- Paintball's line in the minigame registry (Minigames/Games): a team match (flow "match") in the
-- five-storey TV station, site "f3_tv_station" of generated/Expansion. Part of the paintball contract
-- (Contract, beside this file, says how paintball sits in the framework): FROZEN, no lane edits it.
--   rules     Rules (beside this file): the match model. A seat of the Session is a slot of the match.
--   session   lobbySeconds = 0: the first person to join starts the match, and its own first phase,
--             the briefing in the spawn rooms, is where friends catch up (anyone may join while a
--             match is on: rules.def.lateJoin). No idle clock: a player who stops sending is taken
--             off by the service (Clock.DROP_SECS). doneSeconds is the end card, a little longer than
--             Rules.endCardSecs, after which the service itself rolls into the next match (ctx.again).
--   computers the bots (Contract.BOTS); fill = 8: four a side from the first moment (PB-6). The
--             service keeps the sides even and at least four a side from then on (PaintballService).
--   verbs     "reload" (Wire.VERBS). Movement and the click go on paintball's own remotes (Wire).
--   stations  two, when the site is baked: the arena's own (its prompt is at the arena door in the
--             lobby, Arena.GATE) and the pass desk (Arena.DESK), which `joins` it: the service's
--             Table.join sells the pass there and seats nobody. The framework writes ONE action line
--             on both prompts (Table.prompt is not told which prompt it is asked for), so each
--             station's label says what its prompt does; the label of the arena's own is also what
--             the framework's toasts call the game ("You joined Paintball match.").
-- The arena has no walk-away radius: the service's Table.inPlay says who is still in the match.
-- Pure. Interface: a GameSpec.Spec.

local GameSpec = require("../GameSpec")
local Arena = require("./Arena")
local Contract = require("./Contract")
local Rules = require("./Rules")
local Wire = require("./Wire")

local PROMPT_HEIGHT = 3 -- a prompt's anchor above the floor, as at every station

local Spec: GameSpec.Spec = {
	game = Contract.GAME,
	title = "Paintball",
	rules = Rules,
	flow = "match",
	session = { lobbySeconds = 0, doneSeconds = Contract.Rules.endCardSecs + Contract.Rules.endCardSpare },
	verbs = table.clone(Wire.VERBS),
	prompt = { action = "Join the match", busy = "the match is full" },
	words = {
		start = "", -- (the briefing card says it)
		removed = Contract.textFor("dropped"),
		finished = "The match is over. Press E at the arena door to play again.",
	},
	computers = Contract.BOTS :: any,
	fill = 2 * Contract.Rules.teamMin,
	stations = function(sites: { [string]: GameSpec.Place }): { GameSpec.StationDef }
		if sites[Contract.SITE] == nil then
			return {}
		end
		local gx, gy, gd = Arena.toSite(Arena.GATE.x, Arena.GATE.y + PROMPT_HEIGHT, Arena.GATE.z)
		local dx, dy, dd = Arena.toSite(Arena.DESK.x, Arena.DESK.y + PROMPT_HEIGHT, Arena.DESK.z)
		return {
			{
				id = Contract.STATION,
				game = Contract.GAME,
				label = "Paintball match",
				site = Contract.SITE,
				x = gx,
				y = gy,
				d = gd,
			},
			{
				id = Contract.DESK,
				game = Contract.GAME,
				label = "Pass desk: 20c for five days",
				site = Contract.SITE,
				x = dx,
				y = dy,
				d = dd,
				joins = Contract.STATION,
			},
		}
	end,
}

return Spec
