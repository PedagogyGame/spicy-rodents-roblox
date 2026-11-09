--!strict
-- ReplicatedStorage.Shared.Minigames.Minigame
-- The `Minigame` contract (BUILD_PLAN §1.4, §3.16, D28): every game is a pure rules module with a def
-- (seats, stakes class, authority), a state machine driven by validated inputs, and a server-scored
-- result. MinigameService (W4b) owns seats, turn order and replication; this module checks that a rules
-- module satisfies the contract and drives it generically. W1 ships the contract and ONE stub game
-- (MinigameRules/FortuneMachine: no money in or out, Q20). Pure.
-- Interface: CLASSES; check(rules) -> (ok, err?); start(rules, seats, seed) -> Game; input(game, seat, verb, args)
--            -> (ok, err?); result(game) -> Result?

export type Def = {
	game: string,
	class: "shared_table" | "no_stakes" | "arena",
	seats: number,
	authority: string,
	money: string?,
}
export type Result = { done: boolean, scores: { [number]: number }, winner: number?, [string]: any }
export type Rules = {
	def: Def,
	init: (seats: number, seed: number) -> any,
	input: (state: any, seat: number, verb: string, args: { any }?) -> (boolean, string?),
	result: (state: any) -> Result?,
	verbs: { [string]: boolean },
}
export type Game = { rules: Rules, state: any, seats: number }

local Minigame = {}

Minigame.CLASSES = { shared_table = true, no_stakes = true, arena = true } :: { [string]: boolean }

function Minigame.check(rules: any): (boolean, string?)
	if type(rules) ~= "table" or type(rules.def) ~= "table" then
		return false, "no def"
	end
	local d = rules.def
	if type(d.game) ~= "string" then
		return false, "def.game"
	end
	if not Minigame.CLASSES[d.class] then
		return false, "def.class"
	end
	if type(d.seats) ~= "number" or d.seats < 1 then
		return false, "def.seats"
	end
	if d.money ~= nil and d.money ~= "none" then
		return false, "money must be none (no gambling)"
	end
	for _, fn in { "init", "input", "result" } do
		if type(rules[fn]) ~= "function" then
			return false, `missing {fn}`
		end
	end
	if type(rules.verbs) ~= "table" then
		return false, "verbs"
	end
	return true
end

function Minigame.start(rules: Rules, seats: number, seed: number): Game
	assert(Minigame.check(rules))
	assert(seats >= 1 and seats <= rules.def.seats, "seats out of range")
	return { rules = rules, state = rules.init(seats, seed), seats = seats }
end

function Minigame.input(g: Game, seat: number, verb: string, args: { any }?): (boolean, string?)
	if seat < 1 or seat > g.seats then
		return false, "seat"
	end
	if not g.rules.verbs[verb] then
		return false, "verb"
	end
	return g.rules.input(g.state, seat, verb, args)
end

function Minigame.result(g: Game): Result?
	return g.rules.result(g.state)
end

return Minigame
