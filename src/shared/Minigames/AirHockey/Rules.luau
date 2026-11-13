--!strict
-- ReplicatedStorage.Shared.Minigames.AirHockey.Rules
-- Air hockey's rules as the minigame framework sees them (Minigame.Rules): two ends, first to seven, nothing
-- staked. The match itself is the owner's simulation (AirHockey/Sim), run by the table's referee on the server
-- (AirHockey/Referee); these rules keep what the Session needs of it: which end each seat plays, the score the
-- referee reports ("goal", a server verb), the winner, and the computer's difficulty the lobby chose (MODES:
-- his LOUNGE / EASY, CLUB / MEDIUM, PRO / HARD). A seat's "log" is a segment of its hand's log: the table has
-- already checked it and handed it to the referee; here it only says the seat is alive (the idle clock).
-- A seat may be taken while the match is on (def.lateJoin): a person at the computer's end, or the computer at
-- the end of a person who left.
-- Pure. Interface: a Minigame.Rules (def, MODES, verbs, serverVerbs, init, input, result, view, join, gone); TO;
--   COMPUTERS { { name, mode, difficulty } }; computerFor(mode) -> name

local Sim = require("./Sim")

local Rules = {}

Rules.def = {
	game = "air_hockey",
	title = "Air hockey",
	class = "shared_table",
	seats = 2,
	authority = "server",
	money = "none",
	lateJoin = true,
}
Rules.TO = Sim.WIN
Rules.MODES = { "easy", "medium", "hard" }
-- the computer opponents, by his title screen's names
Rules.COMPUTERS = {
	{ name = "Club", mode = "medium", difficulty = Sim.DIFFICULTY.medium },
	{ name = "Lounge", mode = "easy", difficulty = Sim.DIFFICULTY.easy },
	{ name = "Pro", mode = "hard", difficulty = Sim.DIFFICULTY.hard },
}
Rules.verbs = { log = true, mode = true, sides = true, goal = true }
Rules.serverVerbs = { sides = true, goal = true }

function Rules.computerFor(mode: string): string
	for _, c in Rules.COMPUTERS do
		if c.mode == mode then
			return c.name
		end
	end
	return Rules.COMPUTERS[1].name
end

function Rules.init(seats: number, _seed: number): any
	return {
		n = seats,
		mode = "medium",
		sideOf = { 0, 1 }, -- seat -> end (0 Glacier, 1 Ember)
		score = { 0, 0 }, -- by end: Glacier's, Ember's
		winner = false :: any, -- the end that won
		out = {} :: { [number]: boolean },
		ticks = { 0, 0 },
	}
end

function Rules.input(state: any, seat: number, verb: string, args: { any }?): (boolean, string?)
	local a = args or {}
	if verb == "mode" then
		if table.find(Rules.MODES, a[1]) == nil then
			return false, "Easy, medium or hard"
		end
		state.mode = a[1]
		return true
	elseif verb == "log" then
		local to = a[2]
		if type(to) ~= "number" then
			return false, "That part of the game could not be read"
		end
		state.ticks[seat] = to
		return true
	elseif verb == "sides" then
		-- (the table's word: the end seat 1 plays; seat 2 has the other)
		local side = if a[1] == 1 then 1 else 0
		state.sideOf = { side, 1 - side }
		return true
	elseif verb == "goal" then
		local s0, s1 = a[2], a[3]
		if type(s0) ~= "number" or type(s1) ~= "number" then
			return false, "score"
		end
		state.score = { s0, s1 }
		if s0 >= Rules.TO then
			state.winner = 0
		elseif s1 >= Rules.TO then
			state.winner = 1
		end
		return true
	end
	return false, "That does not work at this game"
end

function Rules.join(state: any, seat: number)
	state.n = math.max(state.n, seat)
	state.out[seat] = nil
end

function Rules.gone(state: any, seat: number)
	state.out[seat] = true
end

local function seatOfSide(state: any, side: number): number?
	for seat = 1, state.n do
		if state.sideOf[seat] == side then
			return seat
		end
	end
	return nil
end

function Rules.result(state: any): any
	local side = state.winner
	if side == false then
		return nil
	end
	local scores = {}
	for seat = 1, state.n do
		scores[seat] = state.score[(state.sideOf[seat] or 0) + 1]
	end
	return {
		done = true,
		scores = scores,
		winner = seatOfSide(state, side),
		side = side,
		score = { state.score[1], state.score[2] },
		mode = state.mode,
	}
end

function Rules.view(state: any): { [string]: any }
	local seats = {}
	for seat = 1, state.n do
		local side = state.sideOf[seat] or 0
		seats[seat] = { side = side, score = state.score[side + 1] }
	end
	return { score = { state.score[1], state.score[2] }, seats = seats, mode = state.mode, to = Rules.TO }
end

return Rules
