--!strict
-- ReplicatedStorage.Shared.Minigames.MinigameRules.FortuneMachine
-- The fortune-teller cabinet in the bowling alley's fern corner on the Minigame contract (BUILD_PLAN §3.16;
-- brief v2 §13a: "free-play fortune-teller slot machine: pull the lever, reels spin, it dispenses a fortune or
-- a taunt. No money in or out, ever"; Q20: fortune-teller styling, never fruit reels). "pull" draws three
-- seeded reel symbols and a printed card: three of a kind is a Grand Omen (a special fortune), otherwise a
-- fortune or, about one pull in three, a taunt. Nothing is ever paid or charged (cents is always 0).
-- Pure; Lune-tested (tests/unit/economy.spec.luau, tests/unit/minigames_fortune.spec.luau).
-- Interface: the Minigame.Rules shape (def, init, input, result, verbs) plus REELS, FORTUNES (count),
--   LINES, OMENS, TAUNTS, lineOf(result) -> string, view(state)

local Rng = require("../../Util/Rng")

local FortuneMachine = {}

FortuneMachine.def = {
	game = "fortune_machine",
	title = "Madame Acorna's Fortunes",
	class = "no_stakes",
	seats = 1,
	authority = "server",
	money = "none",
}
FortuneMachine.verbs = { pull = true }

-- Reel faces (the cabinet paints these; never fruit).
FortuneMachine.REELS = { "eye", "moon", "star", "acorn", "crystal", "hand" }
FortuneMachine.REEL_LABEL = {
	eye = "EYE",
	moon = "MOON",
	star = "STAR",
	acorn = "ACORN",
	crystal = "ORB",
	hand = "PALM",
}

-- Fortunes (mild rating, brief v2 §15 dec 24).
FortuneMachine.LINES = {
	"A squirrel is watching you. It has been for some time.",
	"Your next ball will find the pocket. Or the gutter. The spirits are vague.",
	"Beware the ball return. Something lives in there.",
	"You will bowl a strike when you stop trying. So: never.",
	"A stranger will offer you nachos. Accept. It costs five cents.",
	"Lucky number: 7. Unlucky number: the 7-10 split.",
	"Today is a good day to wear bowling shoes. They are rented, but they believe in you.",
	"The fern beside me knows your secrets. It is a very good listener.",
	"Your reputation rises like a well-thrown hook.",
	"Look up. No, not there. Higher. Okay, never mind.",
	"You will soon hear a whoopee cushion. Act surprised.",
	"Great fortune awaits in the corner store. It is bird seed. It is always bird seed.",
	"An acorn in the hand is worth two in the tree. Squirrels disagree.",
	"Your darts will fly true. Your third one will not.",
	"Someone in this room has never once picked up a spare. Be kind.",
	"The crystal ball is cloudy. Try wiping it. Thank you.",
	"Fortune favours the bold, the quick, and anyone who keeps their ankles away from the rodent.",
	"You will find exactly what you are looking for, right where you left it.",
	"A tall drink of cocoa is in your future. Possibly two.",
	"The stars say: practise your approach.",
}
FortuneMachine.FORTUNES = #FortuneMachine.LINES

-- Taunts (the machine is cheeky).
FortuneMachine.TAUNTS = {
	"What's up, loser? The machine has spoken.",
	"Hey, Dinkleberry. Yes, you.",
	"I have seen your bowling. I have seen enough.",
	"Pull the lever again. I dare you. I double-dog dare you.",
	"Your aura is beige.",
	"Even the pins laugh at you, and they are made of wood.",
	"You call that a lever pull? My grandmother pulls harder, and she is a toaster.",
	"The future is bright. Not for you, but generally.",
	"Ask again later. Much later. Like, next season.",
	"I predict a gutter ball. I am rarely wrong.",
}

-- Three of a kind: a Grand Omen.
FortuneMachine.OMENS = {
	eye = "THE ALL-SEEING EYE: nothing escapes you today, not even the 10 pin.",
	moon = "FULL MOON: tonight the squirrels are restless. Keep your snacks close.",
	star = "SHOOTING STAR: make a wish. Then make a spare.",
	acorn = "THE GOLDEN ACORN: the squirrels will remember your name. Uh oh.",
	crystal = "CLEAR ORB: you will bowl the game of your life within the week.",
	hand = "THE OPEN PALM: high five the next person you see. Do it.",
}

FortuneMachine.TAUNT_CHANCE = 0.33

type State = {
	rng: Rng.Rng,
	pulls: number,
	fortune: number?,
	reels: { string }?,
	kind: string?, -- "fortune" | "taunt" | "omen"
	line: string?,
}

function FortuneMachine.init(_seats: number, seed: number): State
	return { rng = Rng.new(seed), pulls = 0, fortune = nil, reels = nil, kind = nil, line = nil }
end

function FortuneMachine.input(state: State, _seat: number, verb: string, _args: { any }?): (boolean, string?)
	if verb ~= "pull" then
		return false, "verb"
	end
	state.pulls += 1
	local rng = state.rng
	state.fortune = rng.int(1, FortuneMachine.FORTUNES)
	local reels = {}
	for i = 1, 3 do
		reels[i] = FortuneMachine.REELS[rng.int(1, #FortuneMachine.REELS)]
	end
	state.reels = reels
	if reels[1] == reels[2] and reels[2] == reels[3] then
		state.kind = "omen"
		state.line = FortuneMachine.OMENS[reels[1]]
	elseif rng.next() < FortuneMachine.TAUNT_CHANCE then
		state.kind = "taunt"
		state.line = FortuneMachine.TAUNTS[rng.int(1, #FortuneMachine.TAUNTS)]
	else
		state.kind = "fortune"
		state.line = FortuneMachine.LINES[state.fortune :: number]
	end
	return true
end

function FortuneMachine.result(state: State): { [string]: any }?
	if not state.fortune then
		return nil
	end
	return {
		done = true,
		scores = {},
		fortune = state.fortune,
		reels = state.reels,
		kind = state.kind,
		line = state.line,
		cents = 0, -- no money in or out, ever
	}
end

function FortuneMachine.turn(_state: State): number?
	return 1
end

function FortuneMachine.skipTurn(_state: State) end

function FortuneMachine.view(state: State): { [string]: any }
	return {
		kind = "fortune",
		pulls = state.pulls,
		reels = state.reels,
		card = state.kind,
		line = state.line,
	}
end

return FortuneMachine
