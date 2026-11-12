--!strict
-- ReplicatedStorage.Shared.Minigames.Bowling.Spec
-- Bowling's line in the minigame registry (Minigames/Games): ten-pin rules, turn by turn, up to four at a lane,
-- three computer bowlers (Bowling/Referee.AI), and one station at each of the alley's six lanes.
-- Pure. Interface: a GameSpec.Spec.

local AlleyLayout = require("../../Attractions/AlleyLayout")
local GameSpec = require("../GameSpec")
local Bowling = require("../MinigameRules/Bowling")
local Referee = require("./Referee")

local Spec: GameSpec.Spec = {
	game = "bowling",
	title = "Bowling",
	rules = Bowling,
	flow = "turns",
	session = { lobbySeconds = 8, turnSeconds = 60, doneSeconds = 30 },
	verbs = { "release" },
	prompt = { action = "Bowl", busy = "try another" },
	words = { unit = "frame" },
	computers = Referee.AI,
	stations = function(sites: { [string]: GameSpec.Place }): { GameSpec.StationDef }
		local out: { GameSpec.StationDef } = {}
		if sites.bowling_alley == nil then
			return out
		end
		for lane = 1, AlleyLayout.LANES do
			table.insert(out, {
				id = `bowling_lane_{lane}`,
				game = "bowling",
				label = `Lane {lane}`,
				site = "bowling_alley",
				x = AlleyLayout.laneX(lane),
				y = 3,
				d = -9,
				index = lane,
			})
		end
		return out
	end,
}

return Spec
