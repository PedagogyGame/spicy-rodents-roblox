--!strict
-- ReplicatedStorage.Shared.Minigames.Pinball.HighScores
-- The table of best scores on one pinball machine, for this server (checklist: "a per-machine high-score table
-- for this server with the player's name"; "your name stays on the machine"). A board holds SIZE entries, best
-- first. A machine that nobody has played yet shows the house's own scores, set where a good first game beats
-- the lowest and a great one tops the list, so there is always something to play for. No prize hangs on it:
-- a place on the board is the whole reward (free play, PIN-R4).
-- A board is plain data (it can be sent as it is and kept for the life of the server).
-- Pure; Lune-tested (tests/unit/pinball_attract.spec.luau).
-- Interface: SIZE, HOUSE; new(tableId) -> Board; place(board, score) -> number? (the place a score would
--   take); add(board, name, score, fair?) -> number? (enter it; the place it took; a game that was not fair,
--   Replay.fair, is not entered); lines(board) -> { string };
--   commas(n) -> string

local HighScores = {}

HighScores.SIZE = 5
HighScores.NAME_MAX = 20

export type Entry = { name: string, score: number, house: boolean }
export type Board = { id: string, entries: { Entry } }
export type House = { name: string, score: number }

-- the house's scores per machine: the names are the machine's own cast, the numbers its own score scale
HighScores.HOUSE = {
	pinball_acorn = {
		{ name = "OLD OAK", score = 40000 },
		{ name = "CHESTNUT", score = 25000 },
		{ name = "HAZEL", score = 15000 },
		{ name = "BEECH", score = 8000 },
		{ name = "SAPLING", score = 4000 },
	},
	pinball_rodent = {
		{ name = "THE RODENT", score = 900000 },
		{ name = "SCORCH", score = 500000 },
		{ name = "EMBER", score = 250000 },
		{ name = "CINDER", score = 100000 },
		{ name = "SPARK", score = 40000 },
	},
	pinball_space = {
		{ name = "MISSION CONTROL", score = 60000000 },
		{ name = "COMET", score = 20000000 },
		{ name = "ORBITER", score = 6000000 },
		{ name = "BOOSTER", score = 1500000 },
		{ name = "CADET", score = 500000 },
	},
} :: { [string]: { House } }

function HighScores.new(tableId: string): Board
	local board: Board = { id = tableId, entries = {} }
	local house = HighScores.HOUSE[tableId]
	if house then
		for _, e in house do
			table.insert(board.entries, { name = e.name, score = e.score, house = true })
		end
	end
	return board
end

-- place(board, score): where this score would stand on the board (1 is the top), or nil when it does not
-- make it. A score equal to one already there stands below it (the first to make a score keeps the place).
function HighScores.place(board: Board, score: number): number?
	if score <= 0 then
		return nil
	end
	for i, e in board.entries do
		if score > e.score then
			return i
		end
	end
	if #board.entries < HighScores.SIZE then
		return #board.entries + 1
	end
	return nil
end

-- add(board, name, score, fair): enter a finished game. Returns the place it took, or nil. `fair` is the
-- replay's word on the game (Replay.fair, the result's `fair`): a game that was suspect or out of pace keeps
-- its score on the end card but takes no place here.
function HighScores.add(board: Board, name: string, score: number, fair: boolean?): number?
	if fair == false then
		return nil
	end
	local at = HighScores.place(board, score)
	if at == nil then
		return nil
	end
	local shown = string.sub(name, 1, HighScores.NAME_MAX)
	table.insert(board.entries, at, { name = shown, score = score, house = false })
	for i = #board.entries, HighScores.SIZE + 1, -1 do
		board.entries[i] = nil
	end
	return at
end

-- commas(n): 1234567 -> "1,234,567"
function HighScores.commas(n: number): string
	local s = tostring(math.floor(n + 0.5))
	local out = ""
	while #s > 3 do
		out = "," .. string.sub(s, -3) .. out
		s = string.sub(s, 1, -4)
	end
	return s .. out
end

-- lines(board): the board as the backglass shows it, best first.
function HighScores.lines(board: Board): { string }
	local lines: { string } = {}
	for i, e in board.entries do
		lines[i] = `{i}. {e.name}  {HighScores.commas(e.score)}`
	end
	return lines
end

return HighScores
