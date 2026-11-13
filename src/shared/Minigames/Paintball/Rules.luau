--!strict
-- ReplicatedStorage.Shared.Minigames.Paintball.Rules
-- The paintball match as a pure model (checklist PB-2, PB-6, PB-7, PB-14), and the `rules` of
-- paintball's Spec: the minigame framework's Session starts it, steps it, tells it of every seat taken
-- and left, and ends the game when result() says so. No Instances, no remotes, no arena, no bodies.
-- OWNED BY THE MATCH-AND-BOTS LANE. THIS IS A STUB that already is a sound Minigame.Rules (the registry
-- builds a Session on it today): every function below keeps its name and signature (the service, the
-- bots and the client are written against them) and gets its real body from that lane. The stub seats
-- slots, deals their teams, keeps its clock as told and never fires, tags or ends.
--
-- THE TWO HALVES OF THE INTERFACE
--   what the Session calls (Shared/Minigames/Minigame.Rules): def, verbs, init, step, join, gone,
--     input, result, view. A SEAT IS A SLOT: seat n is slot n.
--   what the service and the bots call directly, on ctx.session.game.state (typed, and without the
--     "state changed" broadcast a server verb would cost on every shot): tune, sync, drain, slot,
--     assign, canFire, fire, reload, canBeHit, tag, bits, card.
-- TIME: THE MODEL IS SLAVED TO THE SHARED CLOCK (Shared/Minigames/Paintball/Clock). init() cannot know
-- it, so a fresh State counts from 0. The service calls sync(state, stamp) on the framework's "start"
-- event and then at the top of EVERY step. The FIRST sync of a State moves every time it holds by the
-- same amount (state.synced becomes true); every later one only sets state.now. step(state, dt) then
-- moves the phases, the respawns and the events up to state.now and no further: once synced it does
-- not add dt (the framework clamps a long frame to 0.1 s; a model that counted its own clock would
-- fall behind the stamps its magazines and respawn times are set from). Before any sync (a bare
-- Session in a spec) step adds dt, so the model still runs on its own. Functions that judge something
-- take the time to judge it at, on the shared clock.
-- TEAMS (Contract decision 11). A slot's team is its own field. init deals seats 1..n by
-- Contract.teamOf. join(seat): a seat that was held before in this match keeps the team it had (a
-- person who takes a bot's seat plays for that bot's side, and a bot that takes a person's seat for
-- theirs); a seat never held joins the side with fewer slots on (level: Contract.teamOf(seat)).
-- assign(id, team) puts a slot on a team, for the service's "side" verb and for keeping people
-- together from one match to the next. So the service balances a match only by adding bots: each
-- joins the smaller side.
-- THE FEEL. state.feel is this match's Contract.Feel: init takes the defaults; the service calls
-- tune(state, feel) on "start", before the first sync and before any bot joins, when the feel has been
-- changed; tune rebuilds every slot's magazine. Every number of FEEL the model uses, it reads there.
--
-- WHAT THE REAL MODEL DOES (Contract holds the numbers and the shapes)
--   * init(seats, seed): slots 1..seats, all on (the people seated when the match starts; the
--     framework then seats computer players up to the Spec's `fill`, each through join()). Phase
--     "briefing" for Rules.briefingSecs, then "live" for Rules.matchSecs, then "ended": result() is
--     non-nil from then on and the framework shows the end card. Each change is a "phase" event.
--     At the start every slot gets a "respawn" event (its place in its team's spawn room).
--   * join(state, seat): the seat is on (a late joiner, a bot filling a side, a person taking the
--     seat a bot gave up, a bot taking the seat a person left). Its tally starts again from nothing,
--     `since` is now, and it gets a "respawn" event at once (protected as after any respawn).
--     gone(state, seat): the seat is off: it cannot fire or be hit; its balls in flight still count
--     for its team (see tag).
--   * a "respawn" event always means: stand at that spawn point (an index 1..Rules.teamMax into the
--     team's points, not one in use if it can be helped), WITH A FULL MAGAZINE AND NO RELOAD RUNNING,
--     protected for feel.protectSecs (cannot be hit, cannot fire). Nobody comes back from being out
--     with the one ball they had left.
--   * assign(state, id, team): false when the slot is off or already on that team. Otherwise the
--     slot changes team, keeps its tally, and gets a "respawn" event for its new team's room: at once
--     if it is in play, at its respawn time if it is out. (The team scores stay as they are.)
--   * one Magazine per slot (Shared/Paintball/Magazine with Rules.magazine, feel.fireInterval,
--     feel.reloadSecs). fire(state, id, t, m) judges the phase, out and protection AT t (the ball's
--     birth: Clock.stamp's f for a person, now for a bot) and the magazine at m (Clock.stamp's m;
--     nil = t). A slot that was tagged at T (slot.outAt) may fire with t < T: the click came first,
--     whichever packet did. It counts the shot. An automatic or manual reload emits "reload".
--     canFire is the same judgment without firing. Neither knows about spawn rooms: the service
--     refuses a shot from inside one itself (the model has no arena).
--   * tag(state, by, id, now, born): the server's verdict that a ball born at `born` (nil = now)
--     from slot `by` struck `id`. Nothing unless `id` is on, on the other team from `by` now
--     (Rules.friendlyFire is false), the phase is "live", and `id` is neither out nor protected at
--     `now`. A BALL IS GOOD WHATEVER HAS BECOME OF ITS SHOOTER SINCE: `by` may be out, or off. The
--     point goes to by's team; the tag and the hit go to slot `by` unless the seat has changed hands
--     since the ball was born (slot.since > born). `id` is out from now (outAt) for feel.respawnSecs
--     (a "tag" event), then gets its "respawn" event.
--   * view(): Contract.MatchView. result(): Contract.Result once ended, with the card: the winner or
--     a draw, a row per slot that is on, most tags first, and the silly awards.
--   * input(): the client verbs "reload" { t } and "side" {}. The service answers both itself (its
--     Table.input), so this is reached only if it did not: "reload" holds t inside [state.now -
--     Clock.MAG_LATE, state.now] and reloads; "side" is refused (only the service knows who is a bot).
-- Interface: def; verbs; init(seats, seed) -> State; tune(state, feel); sync(state, stamp);
--   step(state, dt); join(state, seat); gone(state, seat); assign(state, id, team) -> changed;
--   input(state, seat, verb, args) -> (ok, why?); result(state) -> Result?; view(state) -> MatchView;
--   drain(state) -> { Event }; slot(state, id) -> Slot?; canFire(state, id, t, m?) -> (ok, why?);
--   fire(state, id, t, m?) -> (ok, why?); reload(state, id, t) -> ok; canBeHit(state, id, now) -> ok;
--   tag(state, by, id, now, born?) -> tagged; bits(state, id, now) -> Wire.BIT flags; card(state) ->
--   EndCard; types Slot, State; T (type witnesses)

local Magazine = require("../../Paintball/Magazine")
local Minigame = require("../Minigame")
local Contract = require("./Contract")

export type Slot = {
	id: number, -- the seat
	team: number, -- 1 or 2: THE slot's team (see TEAMS)
	on: boolean, -- somebody holds the seat
	since: number, -- when its present holder took the seat
	out: boolean, -- tagged out, waiting to respawn
	outAt: number, -- when it was last tagged (meaningful while out)
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
	now: number, -- the shared clock, as the service last told it (see TIME)
	synced: boolean, -- the first sync has been (every time in the State is on the shared clock)
	seed: number,
	feel: Contract.Feel, -- this match's feel
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

-- "reload" and "side" are the verbs a client's input reaches the rules with. There is no server
-- verb: the service calls fire, tag and the rest directly.
Rules.verbs = { reload = true, side = true } :: { [string]: boolean }

local function newSlot(state: State, id: number, team: number): Slot
	return {
		id = id,
		team = team,
		on = true,
		since = state.now,
		out = false,
		outAt = 0,
		outUntil = 0,
		safeUntil = state.now,
		spawn = math.ceil(id / 2),
		mag = Magazine.new(R.magazine, state.feel.fireInterval, state.feel.reloadSecs),
		tags = 0,
		outs = 0,
		shots = 0,
		hits = 0,
	}
end

function Rules.init(seats: number, seed: number): State
	local state: State = {
		now = 0,
		synced = false,
		seed = seed,
		feel = Contract.feel(),
		phase = "briefing",
		endsAt = R.briefingSecs,
		scores = { 0, 0 },
		slots = {},
		events = {},
	}
	for id = 1, seats do
		state.slots[id] = newSlot(state, id, Contract.teamOf(id))
	end
	return state
end

-- This match is played with `feel` (a Contract.Feel; the service calls this on "start" when the feel
-- is not the default, before the first sync and before any bot joins). Rebuilds every magazine.
function Rules.tune(state: State, feel: Contract.Feel)
	state.feel = Contract.feel(feel :: any)
	for _, slot in state.slots do
		slot.mag = Magazine.new(R.magazine, state.feel.fireInterval, state.feel.reloadSecs)
	end
end

-- The shared clock reads `stamp` now. The first call moves every time the State holds by the
-- difference; every later call only sets state.now (see TIME).
function Rules.sync(state: State, stamp: number)
	if state.synced then
		state.now = stamp
		return
	end
	local d = stamp - state.now
	state.synced = true
	state.now = stamp
	state.endsAt += d
	for _, slot in state.slots do
		slot.since += d
		slot.outAt += d
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

-- Move the phases, the respawns and the protection up to state.now; appends events. Before the first
-- sync, state.now is first advanced by dt.
function Rules.step(state: State, dt: number)
	if not state.synced then
		state.now += dt
	end
end

local function sideCount(state: State, team: number): number
	local n = 0
	for _, slot in state.slots do
		if slot.on and slot.team == team then
			n += 1
		end
	end
	return n
end

function Rules.join(state: State, seat: number)
	for id = #state.slots + 1, seat - 1 do
		local empty = newSlot(state, id, Contract.teamOf(id))
		empty.on = false
		empty.since = math.huge -- never held
		state.slots[id] = empty
	end
	local was = state.slots[seat]
	local team: number
	if was ~= nil and was.since ~= math.huge then
		team = was.team -- the seat keeps its side
	else
		local one, two = sideCount(state, 1), sideCount(state, 2)
		team = if one < two then 1 elseif two < one then 2 else Contract.teamOf(seat)
	end
	state.slots[seat] = newSlot(state, seat, team)
end

function Rules.gone(state: State, seat: number)
	local slot = state.slots[seat]
	if slot then
		slot.on = false
	end
end

-- Put a slot on a team. True when it changed.
function Rules.assign(state: State, id: number, team: number): boolean
	local slot = state.slots[id]
	if slot == nil or not slot.on or slot.team == team or (team ~= 1 and team ~= 2) then
		return false
	end
	slot.team = team
	return true
end

-- A seated player's verb: "reload" { t }, "side" {}.
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

-- May this slot fire a ball born at t, its magazine judged at m (nil = t)? The why is a Contract.WHY
-- code: "phase", "out", "safe", "empty", "fast".
function Rules.canFire(_state: State, _id: number, _t: number, _m: number?): (boolean, string?)
	return false, "phase"
end

-- Fire one ball from this slot's magazine and count the shot: phase, out and protection judged at t,
-- the magazine at m (nil = t).
function Rules.fire(_state: State, _id: number, _t: number, _m: number?): (boolean, string?)
	return false, "phase"
end

-- R: start a reload at time t. False when full, already reloading, or not in play.
function Rules.reload(_state: State, _id: number, _t: number): boolean
	return false
end

-- Is this slot on, in play and unprotected at `now`? (The service adds the spawn room: a body inside
-- its own cannot be hit either.)
function Rules.canBeHit(_state: State, _id: number, _now: number): boolean
	return false
end

-- The server's verdict that a ball born at `born` (nil = now) from slot `by` struck `id`. True when
-- it was a tag.
function Rules.tag(_state: State, _by: number, _id: number, _now: number, _born: number?): boolean
	return false
end

-- The Wire.BIT flags the match knows for a slot: out, safe (protection), reload. (The service adds
-- safe for a body in its own spawn room.)
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
