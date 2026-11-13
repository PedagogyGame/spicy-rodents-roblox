--!strict
-- ServerScriptService.Server.Minigames.Games.Pool
-- Pool's server half on the minigame framework (Server/Minigames/ServerGame; brief v2 §13a): eight-ball on the
-- two tables in the bowling alley's games room. Everything a cue game does on the server is Pool/CueTable
-- (the shot tried, sent to every client as a script, judged when the balls have stopped; the balls laid out;
-- the computer players; animals on the cloth); this file says what is eight-ball's own: the rules
-- (Shared/Minigames/Pool/EightBall), the rack an idle table shows, the computer players (Pool/Computer:
-- Chalky, Side-Pocket Sal, Eight-Ball Edna) and the words for what a shot came to (Pool/Words).
-- Interface: a ServerGame { game = "pool", new(ctx) -> Table }; Table.hw is the table's Pool/Hardware (nil
--   where the table is not built); Table:debug("layout", spots, fields?) / Table:debug("shoot", args)

local Import = require("../../Import")
local Computer = Import.shared("Minigames/Pool/Computer") :: typeof(require("../../../shared/Minigames/Pool/Computer"))
local EightBall =
	Import.shared("Minigames/Pool/EightBall") :: typeof(require("../../../shared/Minigames/Pool/EightBall"))
local Tables = Import.shared("Minigames/Pool/Tables") :: typeof(require("../../../shared/Minigames/Pool/Tables"))
local Words = Import.shared("Minigames/Pool/Words") :: typeof(require("../../../shared/Minigames/Pool/Words"))
local CueTable = require("../Pool/CueTable")
local ServerGame = require("../ServerGame")

local game: CueTable.Game = {
	game = "pool",
	rules = EightBall,
	table = Tables.eightBall(),
	idle = function(seed: number)
		return Tables.rack(seed)
	end,
	think = function(state: any, _seat: number, level: number, seed: number, breathe: () -> ())
		return Computer.eightBall(state, level, seed, breathe)
	end,
	-- what the words about a shot need from before it: who had which group
	snapshot = function(state: any): any
		return { group = table.clone(state.group) }
	end,
	words = function(view: { [string]: any }, names: { string }, was: any): string?
		local last = view.last
		local seat = type(last) == "table" and last.seat or nil
		local took: string? = nil
		if seat and was and was.group[seat] == nil then
			local now = view.groups and view.groups[seat]
			if now == "solids" or now == "stripes" then
				took = now
			end
		end
		return Words.eightBall(view, names, took)
	end,
	endWords = Words.eightBallEnd,
	board = nil, -- (set per table below: the board names its table)
	-- a scripted layout: the balls that are up are the ones on the cloth
	fix = function(state: any)
		local up: { [number]: boolean } = {}
		for _, s in state.spots do
			up[s.id] = true
		end
		state.down = {}
		for b = 1, 15 do
			state.onTable[b] = up[b] == true
			if not up[b] and b ~= 8 then
				table.insert(state.down, b)
			end
		end
	end,
	-- the winning 8 into the called pocket, played again slowly
	replay = function(state: any): boolean
		return state.how == "eight"
	end,
	opener = function(state: any, seat: number)
		state.seat = seat
	end,
}

local entry: ServerGame.ServerGame = {
	game = "pool",
	new = function(ctx: ServerGame.Ctx): ServerGame.Table
		local mine = table.clone(game)
		local title = `TABLE {ctx.station.index or 1}`
		mine.board = function(view: { [string]: any }?, names: { string }, wins: { [string]: number }): string
			return Words.eightBallBoard(title, view, names, wins)
		end
		return CueTable.new(ctx, mine)
	end,
}

return entry
