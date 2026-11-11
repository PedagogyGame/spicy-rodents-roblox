--!strict
-- ReplicatedStorage.Shared.Speech.SpeechRules
-- Who may speak, when, and which line (owner 2026-11-10): the server asks `request` whenever a
-- townsperson has a reason to say something (spotting the Spicy Rodent, a bite, a crowd, the crew)
-- and gets a line or nothing. Not everyone talks at once:
--   * a per-situation chance (some people stay quiet);
--   * a per-actor cooldown (speech.actorCooldownS, 12 s: one person does not chatter);
--   * a town-wide sliding window (at most speech.townBurst lines per speech.townWindowS);
--   * no repeat of the last three lines town-wide while the group has other lines;
--   * the line the owner asked for by name (Lines.THE_LINE) is favoured among the spotting lines: it
--     is picked OWNER_SHARE of the times it was not the very last line said in town (so never twice
--     running), which makes it about three spotting lines in ten. As one of seven equal lines it came
--     up on one sighting in sixteen, and a short look at the game could pass without it.
-- `force` (the bitten victim, the crew at the patient) skips the chance and the town window, never
-- the one-line-per-actor-per-second floor, and still counts toward the window.
-- The server replicates a line as two attributes on the body, Say then SayAt (server time); the
-- client (Client/UI/SpeechBubbles) reads Say when SayAt changes and shows it for `remaining` seconds.
-- Interface: ATTR { Say, SayAt }; CHANCE; OWNER_SHARE; defaults() -> Params (from Config/Tunables);
--   new(params?) -> State; request(state, now, actorId, situation, rand, opts?) -> string?;
--   remaining(now, sayAt, showSecs) -> seconds (0 = do not show); stats(state)
-- Pure: time and the random source are injected. No side effects on require.

local Lines = require("./Lines")
local Tunables = require("../Config/Tunables")

export type Params = {
	actorCooldown: number, -- s between two lines from the same actor
	townBurst: number, -- lines per window, town-wide
	townWindow: number, -- s
	forceGap: number, -- s: even a forced line waits this long after the actor's last line
	noRepeat: number, -- the last N lines town-wide are not repeated
	chance: { [string]: number }?,
}

export type State = {
	params: Params,
	lastByActor: { [any]: number },
	window: { number }, -- times of the lines inside the town window (oldest first)
	recent: { string }, -- the last lines town-wide (newest last)
	spoken: number,
	refused: number,
}

export type Opts = { force: boolean? }

local SpeechRules = {}

SpeechRules.ATTR = table.freeze({ Say = "Say", SayAt = "SayAt" })

-- How likely a person with a reason to speak actually does (1 = always, subject to the limits).
SpeechRules.CHANCE = table.freeze({
	spotting = 0.7,
	fleeing = 0.5,
	bitten = 1,
	witness = 0.8,
	bystander = 1,
	patient = 1,
	symptoms = 1,
	crew = 1,
	cured = 1,
}) :: { [string]: number }

-- How often a spotting line is the owner's own, when it was not the last line said in town.
SpeechRules.OWNER_SHARE = 0.45

-- A SayAt this far in the future is still shown (the client clock trails the server's a little).
SpeechRules.FUTURE_TOLERANCE = 2

function SpeechRules.defaults(): Params
	return {
		actorCooldown = Tunables.get("speech.actorCooldownS"),
		townBurst = Tunables.get("speech.townBurst"),
		townWindow = Tunables.get("speech.townWindowS"),
		forceGap = 1,
		noRepeat = 3,
	}
end

function SpeechRules.new(params: Params?): State
	return {
		params = params or SpeechRules.defaults(),
		lastByActor = {},
		window = {},
		recent = {},
		spoken = 0,
		refused = 0,
	}
end

local function refuse(state: State): string?
	state.refused += 1
	return nil
end

-- request: a line for `actorId` in `situation` at time `now`, or nil when the person stays quiet.
-- `rand` is a uniform [0, 1) source; one draw decides the chance, one picks the line.
function SpeechRules.request(
	state: State,
	now: number,
	actorId: any,
	situation: string,
	rand: () -> number,
	opts: Opts?
): string?
	local group = Lines.GROUPS[situation]
	if group == nil or #group == 0 then
		return nil
	end
	local p = state.params
	local force = opts ~= nil and opts.force == true
	local last = state.lastByActor[actorId]
	if last ~= nil and now - last < (if force then p.forceGap else p.actorCooldown) then
		return refuse(state)
	end
	-- the town window: drop what has slid out, then count
	local window = state.window
	while #window > 0 and now - window[1] >= p.townWindow do
		table.remove(window, 1)
	end
	if not force then
		if #window >= p.townBurst then
			return refuse(state)
		end
		local chance = (p.chance and p.chance[situation]) or SpeechRules.CHANCE[situation] or 1
		if rand() >= chance then
			return refuse(state)
		end
	end
	local newest = state.recent[#state.recent]
	local r = rand()
	local line: string
	local favoured = situation == "spotting" and newest ~= Lines.THE_LINE
	if favoured and r < SpeechRules.OWNER_SHARE then
		line = Lines.THE_LINE
	else
		if favoured then
			r = (r - SpeechRules.OWNER_SHARE) / (1 - SpeechRules.OWNER_SHARE) -- the same draw, spread out again
		end
		-- a line that is not among the last few said in town (nor the favourite that was just passed over)
		local pool = {}
		for _, candidate in group do
			if table.find(state.recent, candidate) == nil and not (favoured and candidate == Lines.THE_LINE) then
				table.insert(pool, candidate)
			end
		end
		if #pool == 0 then
			-- every line of a small group was just used: anything but the very last line
			for _, candidate in group do
				if candidate ~= newest then
					table.insert(pool, candidate)
				end
			end
			if #pool == 0 then
				pool = table.clone(group)
			end
		end
		line = pool[math.min(#pool, 1 + math.floor(r * #pool))]
	end
	state.lastByActor[actorId] = now
	table.insert(window, now)
	table.insert(state.recent, line)
	while #state.recent > p.noRepeat do
		table.remove(state.recent, 1)
	end
	state.spoken += 1
	return line
end

-- remaining: how many seconds a bubble stamped `sayAt` should still be shown at `now` (both on the
-- server clock). 0 for a stale stamp (a body that streams in carrying an old line), for a missing
-- one, and for one further in the future than the clock tolerance.
function SpeechRules.remaining(now: number, sayAt: number?, showSecs: number): number
	if type(sayAt) ~= "number" or sayAt ~= sayAt then
		return 0
	end
	local age = now - sayAt
	if age < -SpeechRules.FUTURE_TOLERANCE or age >= showSecs then
		return 0
	end
	return showSecs - math.max(0, age)
end

function SpeechRules.stats(state: State): { spoken: number, refused: number }
	return { spoken = state.spoken, refused = state.refused }
end

return SpeechRules
