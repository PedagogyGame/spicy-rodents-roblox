--!strict
-- ReplicatedStorage.Shared.Minigames.WhackAMole.HighScores
-- The cabinet's board of best rounds for this server, as the pinball machines keep theirs (Minigames/Pinball/
-- HighScores): SIZE entries, best first, the player's name beside each. A cabinet nobody has played yet shows the
-- house's own rounds (the owner's sign calls the house THE MIDNIGHT ARCADE; the names are the moles' own), set so
-- a good first round beats the lowest and a great one tops the list. No prize hangs on it: a place on the board
-- is the whole reward (free play). A board is plain data, sent as it is and kept for the life of the server.
-- Pure; Lune-tested (tests/unit/whack_round.spec.luau).
-- Interface: SIZE, NAME_MAX, HOUSE; new() -> Board; place(board, score) -> number?; add(board, name, score)
--   -> number? (the place it took); lines(board) -> { string }; types Entry, Board

local HighScores = {}

HighScores.SIZE = 5
HighScores.NAME_MAX = 20

export type Entry = { name: string, score: number, house: boolean }
export type Board = { entries: { Entry } }

-- A good round in his browser game is 200 to 300 (about one mole in two, a few misses); 400 is very good.
HighScores.HOUSE = {
	{ name = "MIDNIGHT", score = 400 },
	{ name = "COCOA", score = 300 },
	{ name = "TAUPE", score = 220 },
	{ name = "CHARCOAL", score = 150 },
	{ name = "LITTLE NOSE", score = 80 },
}

function HighScores.new(): Board
	local board: Board = { entries = {} }
	for _, e in HighScores.HOUSE do
		table.insert(board.entries, { name = e.name, score = e.score, house = true })
	end
	return board
end

-- place(board, score): where the score would stand (1 is the top), or nil. A score equal to one already there
-- stands below it (whoever made it first keeps the place); nothing for zero.
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

function HighScores.add(board: Board, name: string, score: number): number?
	local at = HighScores.place(board, score)
	if at == nil then
		return nil
	end
	table.insert(board.entries, at, { name = string.sub(name, 1, HighScores.NAME_MAX), score = score, house = false })
	for i = #board.entries, HighScores.SIZE + 1, -1 do
		board.entries[i] = nil
	end
	return at
end

function HighScores.lines(board: Board): { string }
	local out: { string } = {}
	for i, e in board.entries do
		out[i] = `{i}. {e.name}  {e.score}`
	end
	return out
end

return HighScores
