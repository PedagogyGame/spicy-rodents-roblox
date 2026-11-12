--!strict
-- ReplicatedStorage.Shared.Minigames.Paintball.Rules
-- The paintball match as a pure model (checklist PB-2, PB-6, PB-7, PB-14), and the `rules` of
-- paintball's Spec: the minigame framework's Session starts it, steps it, tells it of every seat taken
-- and left, and ends the game when result() says so. No Instances, no remotes, no arena, no bodies.
-- OWNED BY THE MATCH-AND-BOTS LANE. THIS IS A STUB that already is a sound Minigame.Rules (the registry
-- builds a Session on it today): every function below keeps its name and signature (the service, the
-- bots and the client are written against them) and gets its real body from that lane. The stub seats
-- slots, counts its clock and never fires, tags or ends.
--
-- THE TWO HALVES OF THE INTERFACE
--   what the Session calls (Shared/Minigames/Minigame.Rules): def, verbs, init, step, join, gone,
--     input, result, view. A SEAT IS A SLOT: seat n is slot n, of team Contract.teamOf(n).
--   what the service and the bots call directly, on ctx.session.game.state (typed, and without the
--     "state changed" broadcast a server verb would cost on every shot): sync, drain, slot, canFire,
--     fire, reload, canBeHit, tag, bits, card.
-- TIME. Every time in a State is on the shared clock (Shared/Minigames/Paintball/Clock). init() cannot
-- know it, so a fresh State counts from 0 until the service calls sync(state, stamp) (on the
-- framework's "start" event, before any step), which moves every time in the State by the same
-- amount. step(state, dt) then counts on. Functions that judge something take the time to judge it at.
--
-- WHAT THE REAL MODEL DOES (Contract holds the numbers and the shapes)
--   * init(seats, seed): slots 1..seats, all on (the people seated when the match starts; the
--     framework then seats computer players up to the Spec's `fill`, each through join()). Phase
--     "briefing" for Rules.briefingSecs, then "live" for Rules.matchSecs, then "ended": result() is
--     non-nil from then on and the framework shows the end card. Each change is a "phase" event.
--     At the start every slot gets a "respawn" event (its place in its team's spawn room).
--   * join(state, seat): the seat is on (a late joiner, a bot filling a side, a person taking the
--     seat a bot gave up, a bot taking the seat a person left). Its tally starts again from nothing,
--     its magazine is full, and it gets a "respawn" event at once (protected as after any respawn).
--     gone(state, seat): the seat is off: it cannot fire or be hit; its balls in flight still count.
--   * one Magazine per slot (Shared/Paintball/Magazine with Rules.magazine, fireInterval, reloadSecs),
--     judged at the time it is given: for a person the clamped fire time of Clock.stamp, for a bot
--     the server's now. fire() refuses outside "live", while out, while protected, and whatever the
--     magazine refuses; it counts the shot. An automatic or manual reload emits "reload".
--   * tag(by, id, now): nothing unless both are on, on different teams (Rules.friendlyFire is false),
--     the phase is "live", and `id` is neither out nor protected. Otherwise a tag: a point to by's
--     team, a hit to `by`, `id` is out for Rules.respawnSecs (a "tag" event), then a "respawn" event
--     with a spawn point index (1..Rules.teamMax, not one in use if it can be helped) and
--     Rules.protectSecs of protection.
--   * view(): Contract.MatchView. result(): Contract.Result once ended, with the card: the winner or
--     a draw, a row per slot that is on, most tags first, and the silly awards.
--   * input(): the one client verb, "reload" { t }. The service answers a client's "reload" itself
--     (its Table.input, with t clamped as a fire time is), so this is reached only if it did not:
--     hold t inside [state.now - Clock.MAX_LATE, state.now] all the same, then reload().
-- Interface: def; verbs; init(seats, seed) -> State; sync(state, stamp); step(state, dt); join(state,
--   seat); gone(state, seat); input(state, seat, verb, args) -> (ok, why?); result(state) -> Result?;
--   view(state) -> MatchView; drain(state) -> { Event }; slot(state, id) -> Slot?; canFire(state, id,
--   t) -> (ok, why?); fire(state, id, t) -> (ok, why?); reload(state, id, t) -> ok; canBeHit(state,
--   id, now) -> ok; tag(state, by, id, now) -> tagged; bits(state, id, now) -> Wire.BIT flags;
--   card(state) -> EndCard; types Slot, State; T (type witnesses)

local Magazine = require("../../Paintball/Magazine")
local Minigame = require("../Minigame")
local Contract = require("./Contract")

export type Slot = {
	id: number, -- the seat
	team: number, -- Contract.teamOf(id)
	on: boolean, -- somebody holds the seat
	out: boolean, -- tagged out, waiting to respawn
	outUntil: number,
	safeUntil: number, -- spawn protection ends
	spawn: number, -- the index of the spawn point it last stood on
	mag: Magazine.Mag,
	tags: number,
	outs: number,
	shots: number,
	hits: number,
}

export type State = {
	now: number, -- the shared clock as the model counts it (see TIME)
	seed: number,
	phase: Contract.Phase,
	endsAt: number, -- when the phase ends
	scores: { number },
	slots: { Slot }, -- by id, no gaps: 1..the highest seat taken so far
	events: { Contract.Event },
}

local R = Contract.Rules

local Rules = {}

Rules.def = {
	game = Contract.GAME,
	title = "Paintball",
	class = "arena",
	seats = R.slots,
	authority = "server",
	money = "none",
	lateJoin = true,
} :: Minigame.Def

-- "reload" is the one verb a client's input reaches the rules with. There is no server verb: the
-- service calls fire, tag and the rest directly.
Rules.verbs = { reload = true } :: { [string]: boolean }

local function newSlot(id: number, now: number): Slot
	return {
		id = id,
		team = Contract.teamOf(id),
		on = true,
		out = false,
		outUntil = 0,
		safeUntil = now,
		spawn = math.ceil(id / 2),
		mag = Magazine.new(R.magazine, R.fireInterval, R.reloadSecs),
		tags = 0,
		outs = 0,
		shots = 0,
		hits = 0,
	}
end

function Rules.init(seats: number, seed: number): State
	local state: State = {
		now = 0,
		seed = seed,
		phase = "briefing",
		endsAt = R.briefingSecs,
		scores = { 0, 0 },
		slots = {},
		events = {},
	}
	for id = 1, seats do
		state.slots[id] = newSlot(id, 0)
	end
	return state
end

-- The shared clock reads `stamp` now: move every time the State holds by the difference. The service
-- calls it on every "start", and again whenever state.now has strayed Clock.SYNC_SLACK from ctx.stamp().
function Rules.sync(state: State, stamp: number)
	local d = stamp - state.now
	state.now = stamp
	state.endsAt += d
	for _, slot in state.slots do
		slot.outUntil += d
		slot.safeUntil += d
		slot.mag.nextFireAt += d
		local reloading = slot.mag.reloadDoneAt
		if reloading ~= nil then
			slot.mag.reloadDoneAt = reloading + d
		end
	end
	for _, e in state.events do
		local at = e.at
		if at ~= nil then
			e.at = at + d
		end
	end
end

-- Advance the phase clock, respawns and protection by dt; appends events.
function Rules.step(state: State, dt: number)
	state.now += dt
end

function Rules.join(state: State, seat: number)
	for id = #state.slots + 1, seat - 1 do
		local empty = newSlot(id, state.now)
		empty.on = false
		state.slots[id] = empty
	end
	state.slots[seat] = newSlot(seat, state.now)
end

function Rules.gone(state: State, seat: number)
	local slot = state.slots[seat]
	if slot then
		slot.on = false
	end
end

-- A seated player's verb: "reload" { t }.
function Rules.input(_state: State, _seat: number, _verb: string, _args: { any }?): (boolean, string?)
	return false, Contract.textFor("phase")
end

function Rules.result(_state: State): Contract.Result?
	return nil
end

function Rules.view(state: State): Contract.MatchView
	local slots: { Contract.SlotView } = {}
	local on = 0
	for id, slot in state.slots do
		slots[id] = {
			id = id,
			team = slot.team,
			on = slot.on,
			tags = slot.tags,
			outs = slot.outs,
			shots = slot.shots,
			hits = slot.hits,
		}
		if slot.on then
			on += 1
		end
	end
	return {
		phase = state.phase,
		endsAt = state.endsAt,
		size = math.clamp(math.ceil(on / 2), R.teamMin, R.teamMax),
		scores = { state.scores[1], state.scores[2] },
		slots = slots,
	}
end

-- The events since the last drain, oldest first.
function Rules.drain(state: State): { Contract.Event }
	local out = state.events
	state.events = {}
	return out
end

function Rules.slot(state: State, id: number): Slot?
	return state.slots[id]
end

-- May this slot fire at time t? The why is a Contract.WHY code: "phase", "out", "safe", "empty", "fast".
function Rules.canFire(_state: State, _id: number, _t: number): (boolean, string?)
	return false, "phase"
end

-- Fire one ball from this slot's magazine at time t and count the shot.
function Rules.fire(_state: State, _id: number, _t: number): (boolean, string?)
	return false, "phase"
end

-- R: start a reload at time t. False when full, already reloading, or not in play.
function Rules.reload(_state: State, _id: number, _t: number): boolean
	return false
end

function Rules.canBeHit(_state: State, _id: number, _now: number): boolean
	return false
end

-- The server's verdict that a ball from `by` struck `id`. True when it was a tag.
function Rules.tag(_state: State, _by: number, _id: number, _now: number): boolean
	return false
end

-- The Wire.BIT flags the match knows for a slot: out, safe, reload.
function Rules.bits(_state: State, _id: number, _now: number): number
	return 0
end

-- The end card as it would be if the match ended now (result() carries it once it has).
function Rules.card(state: State): Contract.EndCard
	return { winner = 0, scores = { state.scores[1], state.scores[2] }, rows = {}, awards = {} }
end

-- Type witnesses (Contract, HOW TO IMPORT): from another root, type State = typeof(RulesModule.T.State).
Rules.T = ({} :: any) :: { Slot: Slot, State: State }

return Rules
