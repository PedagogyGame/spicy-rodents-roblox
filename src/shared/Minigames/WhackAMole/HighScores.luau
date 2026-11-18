--!strict
-- ReplicatedStorage.Shared.Minigames.WhackAMole.HighScores
-- The cabinet's board of best rounds for this server, as the pinball machines keep theirs (Minigames/Pinball/
-- HighScores): SIZE entries, best first, the player's name beside each. A cabinet nobody has played yet shows the
-- house's own rounds (the owner's sign calls the house THE MIDNIGHT ARCADE; the names are the moles' own), set so
-- a good first round beats the lowest and a great one tops the list. No prize hangs on it: a place on the board
-- is the whole reward (free play). A board is plain data, sent as it is and kept for the life of the server.
-- Pure; Lune-tested (tests/unit/whack_round.spec.luau).
-- Interface: SIZE, NAME_MAX, HOUSE; new() -> Board; place(board, score) -> number?; add(board, name, score)
--   -> number? (the place it took); lines(board) -> { string }; list(board) -> { { name, score } } (as sent to the
--   player's end card); types Entry, Board

local HighScores = {}

HighScores.SIZE = 5
HighScores.NAME_MAX = 20

export type Entry = { name: string, score: number, house: boolean }
export type Board = { entries: { Entry } }

-- What a round scores (his pacing; a hit frees its hole sooner, so a sure hand is sent more moles): striking every
-- mole about 0.35 s after it starts up makes about 710; a steady hand (0.55 s, now and then the wrong hole) about
-- 580; a casual one (0.7 s) about 490; a first round (0.9 s, often the wrong hole) about 340
-- (tests/unit/whack_round.spec.luau plays these hands). So a first round reaches the bottom, a steady one the
-- middle, and only a quick and sure one tops it.
HighScores.HOUSE = {
	{ name = "MIDNIGHT", score = 650 },
	{ name = "COCOA", score = 560 },
	{ name = "TAUPE", score = 480 },
	{ name = "CHARCOAL", score = 400 },
	{ name = "LITTLE NOSE", score = 300 },
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

function HighScores.list(board: Board): { { name: string, score: number } }
	local out = {}
	for i, e in board.entries do
		out[i] = { name = e.name, score = e.score }
	end
	return out
end

return HighScores
