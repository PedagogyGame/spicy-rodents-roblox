--!strict
-- ReplicatedStorage.Shared.Minigames.WhackAMole.Rules
-- Whack-a-mole in the shape of the Minigame contract (Shared/Minigames/Minigame): one seat, a machine that runs on
-- its own clock (flow "solo": step(state, dt) moves the round; the Session's idle clock takes a player off who
-- strikes nothing for a while). The round itself is WhackAMole/Round; this is the thin wrapper the Session drives.
-- Verbs: "whack" { hole, t } (t in round seconds: the station's Table turns the client's stamp on the shared clock
-- into them, so a client never reaches this verb with a time of its own making); "stop" is the server's (the
-- player went: the round ends where it stands, the score kept).
-- result() comes when the round is over: { done, scores = { score }, hits, misses, strikes, rate, stopped }.
-- view() is { game, freePlay, score, hits, misses, left (seconds, a tenth), ready (count-in seconds left, 0 once
-- GO), now (round seconds) }. Free play: money is "none"; nothing is staked or won.
-- Pure; Lune-tested (tests/unit/whack_round.spec.luau).
-- Interface: a Minigame.Rules; GAME; CLIENT_VERBS; round(state) -> Round.State

local Minigame = require("../Minigame")
local Round = require("./Round")

local Rules = {}

Rules.GAME = "whack_a_mole"
Rules.CLIENT_VERBS = { "whack" }

Rules.def = {
	game = Rules.GAME,
	title = "Whack-a-Mole",
	class = "no_stakes",
	seats = 1,
	authority = "server",
	money = "none",
} :: Minigame.Def
Rules.verbs = { whack = true, stop = true }
Rules.serverVerbs = { stop = true }

function Rules.init(_seats: number, seed: number): any
	return Round.new(seed)
end

function Rules.input(state: any, _seat: number, verb: string, args: { any }?): (boolean, string?)
	local s = state :: Round.State
	if verb == "whack" then
		local ok, why = Round.strike(s, args and args[1], args and args[2])
		return ok, why
	elseif verb == "stop" then
		Round.stop(s)
		return true
	end
	return false, "verb"
end

function Rules.step(state: any, dt: number)
	Round.advance(state :: Round.State, dt)
end

function Rules.gone(state: any, _seat: number)
	Round.stop(state :: Round.State)
end

function Rules.result(state: any): Minigame.Result?
	local s = state :: Round.State
	if not Round.over(s) then
		return nil
	end
	return {
		done = true,
		scores = { s.score },
		winner = 1,
		hits = s.hits,
		misses = s.misses,
		strikes = s.strikes,
		rate = Round.rateOf(s),
		stopped = s.stopped,
	}
end

function Rules.view(state: any): { [string]: any }
	local s = state :: Round.State
	return {
		game = Rules.GAME,
		freePlay = true,
		score = s.score,
		hits = s.hits,
		misses = s.misses,
		left = math.ceil(Round.left(s) * 10) / 10,
		ready = math.max(0, math.ceil(-s.now * 10) / 10),
		now = math.floor(s.now * 1000 + 0.5) / 1000,
	}
end

function Rules.round(state: any): Round.State
	return state :: Round.State
end

return Rules
