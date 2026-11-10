--!strict
-- ReplicatedStorage.Shared.Infection.InfectionRules
-- One bitten person's story from the bite to the cure, as a pure state machine (owner 2026-11-10:
-- "a person bit just ran away, there should be an ambulance come and a crowd gather sometimes,
-- sometimes the symptoms should show up a bit later, but it should always be that they have to go
-- to the hospital to get cured"). Time and the random source are injected; the server glue
-- (Server/Infection/InfectionService) feeds plain facts in and applies the plain effects that come out.
--
--   bitten ----(collapseAfterSecs)---------------------------------------------> down
--   incubating --(incubateSecs)--> symptomatic --(symptomSecs)--> walkin --(at the door)--> admitted
--                                        |                           '--(too slow)--> down
--                                        '--(no route, too far, or the dice)--------> down
--   down --(dispatchDelaySecs: the call)--> scene --(an ambulance is assigned)--> enroute
--     --(it arrives)--> approach (the crew walks over) --> assess --> loading --> retrieve (the
--     patient is carried to the ambulance) --> transit (out of sight, driven in) --> admitted
--   scene | enroute --(no ambulance within ambulanceTimeoutSecs)--> transit (taken in anyway)
--   admitted --(a bed)--> treated --(hospital.treatSecs)--> released (cured)
--
-- THE ONLY CURE IS THE HOSPITAL: `infected` is cleared in one place, the step from treated to
-- released. Nothing else clears it: not time, not the rodent's death (the old brief v2 §8 rule, cured
-- instantly if bitten within infection.recentBiteSecs, is off: that tunable now defaults to 0).
-- A person a player is holding is never frozen, hidden or moved: they incubate, get the tell, and are
-- treated by standing in the hospital for hospital.treatSecs (leaving early starts it over).
-- Nothing a client can read shows an incubating case: `tell` is nil until the symptoms show.
-- Interface: STATES; defaults() -> Params (Config/Tunables); newCase(id, now, inputs, rand, params)
--   -> (Case, { Effect }); advance(case, now, inputs, rand, params) -> { Effect };
--   rebite(case, now) -> { Effect }; tell(case) -> string?; isInfected(case); biteable(case);
--   possessable(case); atScene(case); closed(case); townPercent(infected, humans) -> number
-- Pure. No side effects on require.

local Tunables = require("../Config/Tunables")

export type Range = { number } -- { low, high }

export type Params = {
	immediateChance: number,
	collapseAfterSecs: Range,
	incubateSecs: Range,
	symptomSecs: Range,
	walkInChance: number,
	walkInSpeed: number, -- studs/s
	walkInMaxDist: number, -- studs
	dispatchDelaySecs: Range,
	assessSecs: Range,
	loadSecs: number,
	ambulanceTimeoutSecs: number,
	transitMaxSecs: number,
	groanSecs: Range,
	treatSecs: number,
	crewMaxSecs: number,
}

export type Case = {
	id: any,
	state: string,
	infected: boolean,
	bittenAt: number,
	since: number, -- when the current state was entered
	untilT: number, -- when the current timed state ends (math.huge when a fact ends it)
	immediate: boolean, -- the bite chose the collapse-at-once path
	selfTreat: boolean, -- a player-held person being treated by standing in the hospital
	arrival: string?, -- "walk" | "ambulance"
	deadline: number, -- the ambulance must have arrived by then
	crewSecs: number, -- the crew's walk from the ambulance to the patient (0 = no crew)
	nextGroan: number,
	symptomsAt: number?, -- when the tell first showed
	controller: string, -- who held the body at the last step ("ai" | "player")
}

export type Inputs = {
	controller: string, -- "ai" | "player"
	nearHospital: boolean?, -- on the hospital's grounds
	atEntrance: boolean?, -- at the door or inside
	routeLen: number?, -- studs of the walk-in route from here; nil = no route
	ambulance: string?, -- none | queued | assigned | arrived | returning | home
	crewSecs: number?, -- valid with ambulance == "arrived"
	hospital: string?, -- none | queued | bed | done
}

export type Effect = { kind: string, situation: string?, force: boolean?, key: string?, by: string? }

local InfectionRules = {}

InfectionRules.STATES = table.freeze({
	"bitten",
	"incubating",
	"symptomatic",
	"walkin",
	"down",
	"scene",
	"enroute",
	"approach",
	"assess",
	"loading",
	"retrieve",
	"transit",
	"admitted",
	"treated",
	"released",
})

local TELL: { [string]: string } = {
	symptomatic = "symptomatic",
	walkin = "symptomatic",
	down = "down",
	scene = "down",
	enroute = "down",
	approach = "down",
	assess = "down",
	loading = "down",
	retrieve = "down",
	transit = "transit",
	treated = "treated",
}

local POSSESSABLE: { [string]: boolean } =
	{ bitten = true, incubating = true, symptomatic = true, walkin = true, released = true }
local BITEABLE: { [string]: boolean } = { incubating = true, symptomatic = true, walkin = true, released = true }
local AT_SCENE: { [string]: boolean } = {
	down = true,
	scene = true,
	enroute = true,
	approach = true,
	assess = true,
	loading = true,
	retrieve = true,
}

function InfectionRules.defaults(): Params
	local g = Tunables.get
	return {
		immediateChance = g("infection.immediateChance"),
		collapseAfterSecs = g("infection.collapseAfterSecs"),
		incubateSecs = g("infection.incubateSecs"),
		symptomSecs = g("infection.symptomSecs"),
		walkInChance = g("infection.walkInChance"),
		walkInSpeed = g("infection.walkInSpeed"),
		walkInMaxDist = g("infection.walkInMaxDist"),
		dispatchDelaySecs = g("infection.dispatchDelaySecs"),
		assessSecs = g("infection.assessSecs"),
		loadSecs = g("infection.loadSecs"),
		ambulanceTimeoutSecs = g("infection.ambulanceTimeoutSecs"),
		transitMaxSecs = g("infection.transitMaxSecs"),
		groanSecs = g("infection.groanSecs"),
		treatSecs = g("hospital.treatSecs"),
		crewMaxSecs = 55, -- hospital_police_infection §7.5: walkTime = clamp(len / 3.45, 3, 55)
	}
end

local function range(rand: () -> number, r: Range): number
	return r[1] + (r[2] - r[1]) * rand()
end

local function enter(case: Case, state: string, now: number, untilT: number?)
	case.state = state
	case.since = now
	case.untilT = untilT or math.huge
end

local function collapse(case: Case, now: number, rand: () -> number, params: Params, effects: { Effect })
	enter(case, "down", now, now + range(rand, params.dispatchDelaySecs))
	case.nextGroan = now + range(rand, params.groanSecs)
	table.insert(effects, { kind = "collapse" })
end

-- newCase: the bite. The person is infected and runs; the dice pick the path. A person a player
-- holds, or one bitten on the hospital's own grounds, never collapses at once.
-- Draws: one for the path (AI away from the hospital only), one for its first timer.
function InfectionRules.newCase(
	id: any,
	now: number,
	inputs: Inputs,
	rand: () -> number,
	params: Params
): (Case, { Effect })
	local player = inputs.controller == "player"
	local immediate = not player and not inputs.nearHospital and rand() < params.immediateChance
	local case: Case = {
		id = id,
		state = "bitten",
		infected = true,
		bittenAt = now,
		since = now,
		untilT = math.huge,
		immediate = immediate,
		selfTreat = false,
		arrival = nil,
		deadline = math.huge,
		crewSecs = 0,
		nextGroan = math.huge,
		symptomsAt = nil,
		controller = inputs.controller,
	}
	if immediate then
		enter(case, "bitten", now, now + range(rand, params.collapseAfterSecs))
	else
		enter(case, "incubating", now, now + range(rand, params.incubateSecs))
	end
	local effects: { Effect } = {
		{ kind = "flee" },
		{ kind = "say", situation = "bitten", force = true },
	}
	if player then
		table.insert(effects, { kind = "toast", key = "bitten" })
	end
	return case, effects
end

-- rebite: the rodent bites a person who is already infected and still on their feet: they run and
-- shout again; the case itself does not change (one infection, one cure).
function InfectionRules.rebite(case: Case, _now: number): { Effect }
	if not InfectionRules.biteable(case) then
		return {}
	end
	return { { kind = "flee" }, { kind = "say", situation = "bitten", force = true } }
end

local function showSymptoms(
	case: Case,
	now: number,
	player: boolean,
	rand: () -> number,
	params: Params,
	effects: { Effect }
)
	enter(case, "symptomatic", now, if player then math.huge else now + range(rand, params.symptomSecs))
	case.symptomsAt = case.symptomsAt or now
	table.insert(effects, { kind = "say", situation = "symptoms", force = true })
	if player then
		table.insert(effects, { kind = "toast", key = "symptoms" })
	end
end

local function selfTreat(case: Case, now: number, params: Params, effects: { Effect })
	enter(case, "treated", now, now + params.treatSecs)
	case.selfTreat = true
	case.arrival = "walk"
	table.insert(effects, { kind = "toast", key = "treating" })
end

-- One transition at most; returns true when the state changed (advance loops on it).
local function stepOnce(
	case: Case,
	now: number,
	inputs: Inputs,
	rand: () -> number,
	params: Params,
	effects: { Effect }
): boolean
	local state = case.state
	local player = inputs.controller == "player"
	if state == "bitten" then
		if player then
			-- taken over before the collapse: a held person never collapses, so they incubate instead
			case.immediate = false
			enter(case, "incubating", now, case.bittenAt + range(rand, params.incubateSecs))
			table.insert(effects, { kind = "toast", key = "bitten" })
			return true
		elseif now >= case.untilT then
			collapse(case, now, rand, params, effects)
			return true
		end
	elseif state == "incubating" then
		if player and inputs.atEntrance then
			selfTreat(case, now, params, effects)
			return true
		elseif now >= case.untilT then
			showSymptoms(case, now, player, rand, params, effects)
			return true
		end
	elseif state == "symptomatic" then
		if player then
			case.untilT = math.huge
			if inputs.atEntrance then
				selfTreat(case, now, params, effects)
				return true
			end
		else
			if case.untilT == math.huge then
				case.untilT = now + range(rand, params.symptomSecs) -- handed back to the AI
			end
			if now >= case.untilT then
				local len = inputs.routeLen
				local walk = len ~= nil
					and (inputs.nearHospital == true or (len <= params.walkInMaxDist and rand() < params.walkInChance))
				if walk and len then
					local secs = math.min(len, params.walkInMaxDist) / math.max(0.1, params.walkInSpeed)
					enter(case, "walkin", now, now + secs * 1.35 + 20)
					table.insert(effects, { kind = "walkIn" })
					table.insert(effects, { kind = "say", situation = "symptoms" })
				else
					collapse(case, now, rand, params, effects)
				end
				return true
			end
		end
	elseif state == "walkin" then
		if player then
			enter(case, "symptomatic", now)
			table.insert(effects, { kind = "resume" })
			table.insert(effects, { kind = "toast", key = "symptoms" })
			return true
		elseif inputs.atEntrance then
			enter(case, "admitted", now)
			case.arrival = "walk"
			table.insert(effects, { kind = "arrive", by = "walk" })
			return true
		elseif now >= case.untilT then
			collapse(case, now, rand, params, effects)
			return true
		end
	elseif state == "down" then
		if now >= case.untilT then
			enter(case, "scene", now)
			case.deadline = now + params.ambulanceTimeoutSecs
			table.insert(effects, { kind = "call" })
			return true
		end
	elseif state == "scene" or state == "enroute" then
		if inputs.ambulance == "arrived" then
			case.crewSecs = math.clamp(inputs.crewSecs or 0, 0, params.crewMaxSecs)
			if case.crewSecs > 0 then
				enter(case, "approach", now, now + case.crewSecs)
				table.insert(effects, { kind = "crewOut" })
			else
				enter(case, "assess", now, now + range(rand, params.assessSecs))
			end
			return true
		elseif now >= case.deadline then
			-- no ambulance came in time: nobody is left on the pavement, the patient is taken in anyway
			enter(case, "transit", now, now + params.transitMaxSecs)
			table.insert(effects, { kind = "abandon" })
			return true
		elseif state == "scene" and inputs.ambulance == "assigned" then
			enter(case, "enroute", now)
			return true
		end
	elseif state == "approach" then
		if now >= case.untilT then
			enter(case, "assess", now, now + range(rand, params.assessSecs))
			table.insert(effects, { kind = "say", situation = "crew", force = true })
			return true
		end
	elseif state == "assess" then
		if now >= case.untilT then
			enter(case, "loading", now, now + params.loadSecs)
			return true
		end
	elseif state == "loading" then
		if now >= case.untilT then
			if case.crewSecs > 0 then
				enter(case, "retrieve", now, now + case.crewSecs)
				table.insert(effects, { kind = "carry" })
			else
				enter(case, "transit", now, now + params.transitMaxSecs)
				table.insert(effects, { kind = "load" })
			end
			return true
		end
	elseif state == "retrieve" then
		if now >= case.untilT then
			enter(case, "transit", now, now + params.transitMaxSecs)
			table.insert(effects, { kind = "load" })
			return true
		end
	elseif state == "transit" then
		local amb = inputs.ambulance
		if amb == "home" or amb == "none" or amb == nil or now >= case.untilT then
			enter(case, "admitted", now)
			case.arrival = "ambulance"
			table.insert(effects, { kind = "arrive", by = "ambulance" })
			return true
		end
	elseif state == "admitted" then
		if inputs.hospital == "bed" or inputs.hospital == "done" then
			enter(case, "treated", now)
			table.insert(effects, { kind = "bed" })
			return true
		end
	elseif state == "treated" then
		if case.selfTreat then
			if not player then
				-- the player let go mid-treatment: the person finishes the walk in as an AI patient
				case.selfTreat = false
				enter(case, "symptomatic", now, now)
				return true
			elseif not inputs.atEntrance then
				case.selfTreat = false
				enter(case, "symptomatic", now)
				table.insert(effects, { kind = "toast", key = "leftEarly" })
				return true
			elseif now >= case.untilT then
				case.infected = false -- the cure (1 of 2: a held person, treated in the hospital)
				enter(case, "released", now)
				table.insert(effects, { kind = "cure" })
				table.insert(effects, { kind = "toast", key = "cured" })
				return true
			end
		elseif inputs.hospital == "done" then
			case.infected = false -- the cure (2 of 2: a patient, treated in a bed)
			enter(case, "released", now)
			table.insert(effects, { kind = "cure" })
			table.insert(effects, { kind = "discharge" })
			table.insert(effects, { kind = "say", situation = "cured" })
			return true
		end
	end
	return false
end

-- advance: bring the case up to `now` given the facts. Returns the effects, in order.
function InfectionRules.advance(case: Case, now: number, inputs: Inputs, rand: () -> number, params: Params): { Effect }
	local effects: { Effect } = {}
	if inputs.controller ~= case.controller then
		-- a player who takes a body that already shows the tell is told what to do about it
		if inputs.controller == "player" and case.state == "symptomatic" then
			table.insert(effects, { kind = "toast", key = "symptoms" })
		end
		case.controller = inputs.controller
	end
	for _ = 1, 8 do
		if not stepOnce(case, now, inputs, rand, params, effects) then
			break
		end
	end
	-- the patient on the ground groans now and then (humans_actors §7.2)
	if AT_SCENE[case.state] and now >= case.nextGroan then
		case.nextGroan = now + range(rand, params.groanSecs)
		table.insert(effects, { kind = "say", situation = "patient" })
	end
	return effects
end

-- tell: what a client may see of the case (the Med attribute). nil while nothing shows.
function InfectionRules.tell(case: Case): string?
	if case.state == "treated" and case.selfTreat then
		return "symptomatic" -- a held person keeps their own pose; the red eyes stay until the cure
	elseif case.state == "admitted" then
		-- waiting for a bed: an ambulance patient is still out of sight, a walk-in stands in reception
		return if case.arrival == "ambulance" then "transit" else "symptomatic"
	end
	return TELL[case.state]
end

function InfectionRules.isInfected(case: Case): boolean
	return case.infected
end

-- biteable: may the rodent bite this person again? Not while they are down, hidden or in a bed.
function InfectionRules.biteable(case: Case): boolean
	return BITEABLE[case.state] == true and not case.selfTreat
end

-- possessable: may a player take this body? Never one that is down, hidden, carried or in a bed.
function InfectionRules.possessable(case: Case): boolean
	return POSSESSABLE[case.state] == true or (case.state == "treated" and case.selfTreat)
end

-- atScene: on the ground at a scene (traffic's emergency classes do not stop for them).
function InfectionRules.atScene(case: Case): boolean
	return AT_SCENE[case.state] == true
end

function InfectionRules.closed(case: Case): boolean
	return case.state == "released"
end

-- townPercent: infected humans over all humans, in percent.
function InfectionRules.townPercent(infected: number, humans: number): number
	if humans <= 0 then
		return 0
	end
	return 100 * infected / humans
end

return InfectionRules
