--!strict
-- ServerScriptService.Server.Minigames.Games.BumperPool
-- Bumper pool's server half on the minigame framework (Server/Minigames/ServerGame; brief v2 §13a): the bumper
-- pool table in the bowling alley's games room. Everything a cue game does on the server is pool's
-- Pool/CueTable (the shot tried, sent to every client as a script, judged when the balls have stopped; the
-- balls laid out; the computer players; animals on the cloth); this file says what is bumper pool's own: the
-- rules (Shared/Minigames/Pool/BumperPool: the opening's first strike waits for the second, and the table
-- plays them together), how an idle table lies (every ball on its spot), which balls are out of sight
-- (practice: the other five), the computer players (Pool/Computer: Bumper Bob, Bank-Shot Betty, Cushion Carl)
-- and the words for what a shot came to (Pool/Words).
-- Interface: a ServerGame { game = "bumper_pool", new(ctx) -> Table }; Table.hw is the table's Pool/Hardware
--   (nil where the table is not built); Table:debug("layout", spots, fields?) / Table:debug("shoot", args)

local Import = require("../../Import")
local BumperPool =
	Import.shared("Minigames/Pool/BumperPool") :: typeof(require("../../../shared/Minigames/Pool/BumperPool"))
local Computer = Import.shared("Minigames/Pool/Computer") :: typeof(require("../../../shared/Minigames/Pool/Computer"))
local Tables = Import.shared("Minigames/Pool/Tables") :: typeof(require("../../../shared/Minigames/Pool/Tables"))
local Words = Import.shared("Minigames/Pool/Words") :: typeof(require("../../../shared/Minigames/Pool/Words"))
local CueTable = require("../Pool/CueTable")
local ServerGame = require("../ServerGame")

local game: CueTable.Game = {
	game = "bumper_pool",
	rules = BumperPool,
	table = Tables.bumper(),
	idle = function(_seed: number)
		return Tables.bumperStart()
	end,
	-- practice: the other side's five are not in the game, and are kept out of sight inside the table
	away = function(state: any): { [number]: boolean }?
		if state.seats >= 2 then
			return nil
		end
		local out: { [number]: boolean } = {}
		for id = 6, 10 do
			out[id] = true
		end
		return out
	end,
	think = function(state: any, seat: number, level: number, seed: number, breathe: () -> ())
		return Computer.bumper(state, seat, level, seed, breathe)
	end,
	snapshot = function(_state: any): any
		return {}
	end,
	words = function(view: { [string]: any }, names: { string }, _was: any): string?
		return Words.bumper(view, names)
	end,
	endWords = Words.bumperEnd,
	board = Words.bumperBoard,
}

local entry: ServerGame.ServerGame = {
	game = "bumper_pool",
	new = function(ctx: ServerGame.Ctx): ServerGame.Table
		return CueTable.new(ctx, game)
	end,
}

return entry
