--!strict
-- ReplicatedStorage.Shared.Rodent.PowerRules
-- Power exactly as v5.4 implements it (brief v2 §15 "Power, verbatim from v5.4"; squirrel_abilities §12;
-- BUILD_PLAN §1.4, D-21): +100 bite a person (+150 when world Y > 4 HTML units), +130 an officer, +90 per
-- converted squirrel once each, -19 baton (and the pedestrian kick, same function; Q23), -12 yard cat,
-- and after each 600 real ACTIVE seconds without a bite lose max(1, ceil(15 %)) repeating (the timer
-- wraps by subtraction, v5.4 L5506-5516). A bite resets the fade timer. Never below 0. Chilis, coins,
-- climbing and missed pounces change nothing. Stages: FERAL < 600 <= RABID < 1500 <= SUPER.
-- Golden-tested against v5.4's own code (tests/golden/power.json, tests/golden/power_gen.mjs).
-- Its clock is real active seconds (rule 11), never the game clock. Pure.
-- Interface: new() -> State; apply(state, event) -> delta; fade(state, activeDt) -> lost (total);
--            stage(power) -> "FERAL"|"RABID"|"SUPER"; nextFadeIn(state) -> seconds; TABLE

export type State = { points: number, inactiveSeconds: number, converted: { [any]: boolean } }
export type Event = {
	kind: string, -- bitePerson | biteOfficer | convertSquirrel | baton | pedestrianKick | cat | chili | coin | climb | missedPounce
	y: number?, -- bitePerson: the rodent's world Y in HTML units (v5.4 compares player.pos.y > 4)
	id: any?, -- convertSquirrel: the squirrel actor id (once each)
}

local PowerRules = {}

-- The brief v2 §15 table. Tunables `power.*` mirrors these for the tuning panel; this is the authority.
PowerRules.TABLE = table.freeze({
	bitePerson = 100,
	bitePersonHigh = 150,
	highY = 4, -- HTML units, absolute world Y (v5.4 L6527)
	biteOfficer = 130,
	convertSquirrel = 90,
	batonHit = -19,
	pedestrianKick = -19,
	catHit = -12,
	fadeInterval = 600, -- POWER_DECAY_INTERVAL, real active seconds
	fadeRate = 0.15, -- POWER_DECAY_RATE
	rabid = 600,
	super = 1500,
	hudMax = 1500,
})

local T = PowerRules.TABLE

function PowerRules.new(): State
	return { points = 0, inactiveSeconds = 0, converted = {} }
end

-- Applies one event; returns the change in points.
function PowerRules.apply(state: State, event: Event): number
	local before = state.points
	local k = event.kind
	if k == "bitePerson" then
		state.points += if (event.y or 0) > T.highY then T.bitePersonHigh else T.bitePerson
		state.inactiveSeconds = 0
	elseif k == "biteOfficer" then
		state.points += T.biteOfficer
		state.inactiveSeconds = 0
	elseif k == "convertSquirrel" then
		local id = event.id
		if id ~= nil and not state.converted[id] then
			state.converted[id] = true
			state.points += T.convertSquirrel
			state.inactiveSeconds = 0
		end
	elseif k == "baton" then
		state.points = math.max(0, state.points + T.batonHit)
	elseif k == "pedestrianKick" then
		state.points = math.max(0, state.points + T.pedestrianKick)
	elseif k == "cat" then
		state.points = math.max(0, state.points + T.catHit)
	end
	-- chili, coin, climb, missedPounce and anything else: no change (brief v2 §15)
	return state.points - before
end

-- Advances the fade clock by real active seconds; returns the total Power lost.
function PowerRules.fade(state: State, activeDt: number): number
	local lostTotal = 0
	state.inactiveSeconds += activeDt
	while state.inactiveSeconds >= T.fadeInterval do
		state.inactiveSeconds -= T.fadeInterval
		if state.points > 0 then
			local lost = math.max(1, math.ceil(state.points * T.fadeRate))
			state.points = math.max(0, state.points - lost)
			lostTotal += lost
		end
	end
	return lostTotal
end

function PowerRules.stage(power: number): string
	if power >= T.super then
		return "SUPER"
	elseif power >= T.rabid then
		return "RABID"
	end
	return "FERAL"
end

-- Seconds until the next fade tick (v5.4's NEXT POWER FADE mm:ss, L5473).
function PowerRules.nextFadeIn(state: State): number
	return T.fadeInterval - state.inactiveSeconds
end

return PowerRules
