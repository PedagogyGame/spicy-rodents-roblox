--!strict
-- ReplicatedStorage.Shared.Minigames.MinigameRules.FortuneMachine
-- The stub game on the Minigame contract (BUILD_PLAN §3.16; Q20): a fortune-teller cabinet that takes
-- no money and pays none; "pull" draws a seeded fortune index. W4b wires speech/fortunes.json lines.
-- Interface: the Minigame.Rules shape (def, init, input, result, verbs)

local Rng = require("../../Util/Rng")

local FortuneMachine = {}

FortuneMachine.def = { game = "fortune_machine", class = "no_stakes", seats = 1, authority = "server", money = "none" }
FortuneMachine.verbs = { pull = true }
FortuneMachine.FORTUNES = 20 -- placeholder count until speech/fortunes.json lands

type State = { rng: Rng.Rng, fortune: number?, pulls: number }

function FortuneMachine.init(_seats: number, seed: number): State
	return { rng = Rng.new(seed), fortune = nil, pulls = 0 }
end

function FortuneMachine.input(state: State, _seat: number, verb: string, _args: { any }?): (boolean, string?)
	if verb ~= "pull" then
		return false, "verb"
	end
	state.pulls += 1
	state.fortune = state.rng.int(1, FortuneMachine.FORTUNES)
	return true
end

function FortuneMachine.result(state: State): { [string]: any }?
	if not state.fortune then
		return nil
	end
	return { done = true, scores = {}, fortune = state.fortune, cents = 0 }
end

return FortuneMachine
