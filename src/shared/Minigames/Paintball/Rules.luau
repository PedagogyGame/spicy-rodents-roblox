--!strict
-- ReplicatedStorage.Shared.Minigames.Paintball.Rules
-- The paintball match as a pure model (checklist PB-2, PB-6, PB-7, PB-14), and the `rules` of
-- paintball's Spec: the minigame framework's Session starts it, steps it, tells it of every seat taken
-- and left, and ends the game when result() says so. No Instances, no remotes, no arena, no bodies.
-- OWNED BY THE MATCH-AND-BOTS LANE. Every function keeps the name and signature the contract gave it
-- (the service, the bots and the client are written against them).
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
-- WHAT THE MODEL DOES (Contract holds the numbers and the shapes)
--   * init(seats, seed): slots 1..seats, all on (the people seated when the match starts; the
--     framework then seats computer players up to the Spec's `fill`, each through join()). Phase
--     "briefing" for Rules.briefingSecs, then "live" for Rules.matchSecs, then "ended": result() is
--     non-nil from then on and the framework shows the end card. Each change is a "phase" event.
--     At the start every slot is owed a placement (its place in its team's spawn room; see
--     PLACEMENTS).
--   * join(state, seat): the seat is on (a late joiner, a bot filling a side, a person taking the
--     seat a bot gave up, a bot taking the seat a person left). Its tally starts again from nothing,
--     `since` is now, and it is owed a placement (protected from this moment, as after any respawn).
--     gone(state, seat): the seat is off: it cannot fire or be hit; its balls in flight still count
--     for its team (see tag).
--   * a "respawn" event always means: stand at that spawn point (an index 1..Rules.teamMax into the
--     team's points, the one of its team's that has gone longest without anybody standing on it),
--     WITH A FULL MAGAZINE AND NO RELOAD RUNNING, protected for feel.protectSecs from the event
--     (cannot be hit, cannot fire). Nobody comes back from being out with the one ball they had left.
--   * assign(state, id, team): false when the slot is off or already on that team. Otherwise the
--     slot changes team, keeps its tally, and gets a "respawn" event for its new team's room: a
--     placement owed now if it is in play, its ordinary respawn (into the new room) if it is out.
--     (The team scores stay as they are.)
--   * one Magazine per slot (Shared/Paintball/Magazine with Rules.magazine, feel.fireInterval,
--     feel.reloadSecs). fire(state, id, t, m) judges the phase, out and protection AT t (the ball's
--     birth: Clock.stamp's f for a person, now for a bot) and the magazine at m (Clock.stamp's m;
--     nil = t). A slot that was tagged at T (slot.outAt) may fire with t < T: the click came first,
--     whichever packet did. It counts the shot. An automatic or manual reload emits "reload".
--     canFire is the same judgment without firing. Neither knows about spawn rooms: the service
--     refuses a shot from inside one itself (the model has no arena). The phase a click is judged in
--     is "live" as it stands and t not before the match went live: once the clock has run out
--     nothing more is born, whatever its stamp (the card is already on every screen).
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
-- PLACEMENTS ARE TOLD BY step, NEVER BY THE CALL THAT OWED THEM. init, join and assign do not put a
-- "respawn" event in the queue themselves: they mark the slot (slot.owed = the moment it was asked
-- for) and the first step whose clock is PAST that moment places it: picks the spawn index, fills the
-- magazine, starts the protection and emits the event. Nothing is placed before the first sync (there
-- is nobody to place a body: a bare Session in a spec still runs its phases, its tags and its
-- respawns from being out), and a placement owed before the first sync is owed from that sync. So in
-- the service a joiner's event is in the drain of the second step after the join, not the first: one
-- frame. (Why: the contract's own spec, tests/unit/paintball_contract.spec.luau, holds that a State
-- which has been joined, stepped and synced but whose clock nobody has run on has nothing to drain.)
-- A slot that is owed a placement is protected until it gets it.
-- THE END CARD'S AWARDS (the WBLW Channel 7 sports bulletin; an award is only given when somebody
-- earned it, and a tie goes to the lower seat): "Top Tagger" most tags; "Sharpest Eye" the best
-- accuracy over at least AWARD_SHOTS balls; "Most Paint Wasted" the most balls that tagged nobody;
-- "Human Canvas" the most times tagged out; "Clean Overalls" never tagged out, with at least one tag
-- of their own; "Saving It For Later" the fewest balls fired.
-- Interface: def; verbs; init(seats, seed) -> State; tune(state, feel); sync(state, stamp);
--   step(state, dt); join(state, seat); gone(state, seat); assign(state, id, team) -> changed;
--   input(state, seat, verb, args) -> (ok, why?); result(state) -> Result?; view(state) -> MatchView;
--   drain(state) -> { Event }; slot(state, id) -> Slot?; canFire(state, id, t, m?) -> (ok, why?);
--   fire(state, id, t, m?) -> (ok, why?); reload(state, id, t) -> ok; canBeHit(state, id, now) -> ok;
--   tag(state, by, id, now, born?) -> tagged; bits(state, id, now) -> Wire.BIT flags; card(state) ->
--   EndCard; AWARD_SHOTS; types Slot, State; T (type witnesses)

local Magazine = require("../../Paintball/Magazine")
local Minigame = require("../Minigame")
local Clock = require("./Clock")
local Contract = require("./Contract")
local Wire = require("./Wire")

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
	spawnAt: number, -- when it was last placed there (-math.huge: never)
	owed: number?, -- a placement is owed since this moment (see PLACEMENTS)
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
	liveAt: number, -- when the match goes, or went, live
	scores: { number },
	slots: { Slot }, -- by id, no gaps: 1..the highest seat taken so far
	events: { Contract.Event },
	final: Contract.Result?, -- the result, once the clock has run out
}

local R = Contract.Rules
local BIT = Wire.BIT

local Rules = {}

-- "Sharpest Eye" is among those who fired at least this many balls.
Rules.AWARD_SHOTS = 5

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

local function newMag(state: State): Magazine.Mag
	return Magazine.new(R.magazine, state.feel.fireInterval, state.feel.reloadSecs)
end

local function newSlot(state: State, id: number, team: number): Slot
	return {
		id = id,
		team = team,
		on = true,
		since = state.now,
		out = false,
		outAt = 0,
		outUntil = 0,
		safeUntil = state.now + state.feel.protectSecs,
		spawn = math.ceil(id / 2),
		spawnAt = -math.huge,
		owed = state.now,
		mag = newMag(state),
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
		liveAt = R.briefingSecs,
		scores = { 0, 0 },
		slots = {},
		events = {},
		final = nil,
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
		slot.mag = newMag(state)
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
	state.liveAt += d
	for _, slot in state.slots do
		slot.since += d
		slot.outAt += d
		slot.outUntil += d
		slot.safeUntil += d
		slot.spawnAt += d
		slot.mag.nextFireAt += d
		local reloading = slot.mag.reloadDoneAt
		if reloading ~= nil then
			slot.mag.reloadDoneAt = reloading + d
		end
		if slot.owed ~= nil then
			slot.owed = stamp -- owed from this sync: the first step past it places the slot
		end
	end
	for _, e in state.events do
		local at = e.at
		if at ~= nil then
			e.at = at + d
		end
	end
end

-- The spawn point a slot of this team is put on: of 1..Rules.teamMax, the one that has gone longest
-- without one of the team's slots being placed on it (never used first); the seed and the slot break
-- ties so that two matches do not open alike.
local function pickSpawn(state: State, slot: Slot): number
	local last: { number } = table.create(R.teamMax, -math.huge)
	for _, other in state.slots do
		if other ~= slot and other.on and other.team == slot.team then
			local i = other.spawn
			if i >= 1 and i <= R.teamMax and other.spawnAt > last[i] then
				last[i] = other.spawnAt
			end
		end
	end
	local start = (state.seed + slot.id * 7 + slot.outs * 3) % R.teamMax
	local best, bestAt = 1, math.huge
	for k = 0, R.teamMax - 1 do
		local i = (start + k) % R.teamMax + 1
		if last[i] < bestAt then
			best, bestAt = i, last[i]
		end
	end
	return best
end

-- Put a slot in its team's spawn room, as of `now`: the "respawn" event and everything it means.
local function place(state: State, slot: Slot, now: number)
	slot.spawn = pickSpawn(state, slot)
	slot.spawnAt = now
	slot.owed = nil
	slot.out = false
	slot.safeUntil = now + state.feel.protectSecs
	local mag = slot.mag
	mag.rounds = mag.capacity
	mag.reloadDoneAt = nil
	mag.nextFireAt = now
	table.insert(
		state.events,
		{ kind = "respawn", id = slot.id, team = slot.team, spawn = slot.spawn, at = slot.safeUntil }
	)
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

-- The end card as it would be if the match ended now (result() carries it once it has).
function Rules.card(state: State): Contract.EndCard
	local rows: { Contract.CardRow } = {}
	for _, slot in state.slots do
		if slot.on then
			table.insert(rows, {
				id = slot.id,
				team = slot.team,
				tags = slot.tags,
				outs = slot.outs,
				shots = slot.shots,
				hits = slot.hits,
				accuracy = if slot.shots > 0 then math.min(1, slot.hits / slot.shots) else 0,
			})
		end
	end
	table.sort(rows, function(a: Contract.CardRow, b: Contract.CardRow): boolean
		if a.tags ~= b.tags then
			return a.tags > b.tags
		elseif a.outs ~= b.outs then
			return a.outs < b.outs
		end
		return a.id < b.id
	end)
	local awards: { Contract.Award } = {}
	-- the row that scores highest, the lower seat on a tie; nil when nobody is eligible
	local function give(title: string, score: (row: Contract.CardRow) -> number?)
		local best: Contract.CardRow? = nil
		local bestScore = -math.huge
		for _, row in rows do
			local v = score(row)
			if v ~= nil and (v > bestScore or (v == bestScore and best ~= nil and row.id < best.id)) then
				best, bestScore = row, v
			end
		end
		if best ~= nil then
			table.insert(awards, { title = title, id = best.id })
		end
	end
	give("Top Tagger", function(row: Contract.CardRow): number?
		return if row.tags > 0 then row.tags else nil
	end)
	give("Sharpest Eye", function(row: Contract.CardRow): number?
		return if row.shots >= Rules.AWARD_SHOTS and row.hits > 0 then row.accuracy else nil
	end)
	give("Most Paint Wasted", function(row: Contract.CardRow): number?
		local wasted = row.shots - row.hits
		return if wasted > 0 then wasted else nil
	end)
	give("Human Canvas", function(row: Contract.CardRow): number?
		return if row.outs > 0 then row.outs else nil
	end)
	give("Clean Overalls", function(row: Contract.CardRow): number?
		return if row.outs == 0 and row.tags > 0 then row.tags else nil
	end)
	give("Saving It For Later", function(row: Contract.CardRow): number?
		return if #rows > 1 then -row.shots else nil
	end)
	local one, two = state.scores[1], state.scores[2]
	return {
		winner = if one > two then 1 elseif two > one then 2 else 0,
		scores = { one, two },
		rows = rows,
		awards = awards,
	}
end

local function finish(state: State)
	local card = Rules.card(state)
	local scores: { [number]: number } = {}
	local winners: { number } = {}
	for _, slot in state.slots do
		scores[slot.id] = slot.tags
		if slot.on and slot.team == card.winner then
			table.insert(winners, slot.id)
		end
	end
	local text: string
	if card.winner == 0 then
		text = `A draw, {card.scores[1]} all`
	else
		local loser = 3 - card.winner
		text = `{Contract.TEAMS[card.winner].name} wins {card.scores[card.winner]} - {card.scores[loser]}`
	end
	state.final = { done = true, scores = scores, winners = winners, text = text, card = card }
end

-- Move the phases, the respawns and the protection up to state.now; appends events. Before the first
-- sync, state.now is first advanced by dt.
function Rules.step(state: State, dt: number)
	if not state.synced then
		state.now += dt
	end
	local now = state.now
	if state.phase == "briefing" and now >= state.endsAt then
		state.phase = "live"
		state.liveAt = state.endsAt
		state.endsAt += R.matchSecs
		table.insert(state.events, { kind = "phase", phase = "live", at = state.endsAt })
	end
	if state.phase == "live" and now >= state.endsAt then
		state.phase = "ended"
		state.endsAt += R.endCardSecs
		finish(state)
		table.insert(state.events, { kind = "phase", phase = "ended", at = state.endsAt })
	end
	if state.phase == "ended" then
		return -- the card is up: nobody comes back, nobody is moved
	end
	for _, slot in state.slots do
		if not slot.on then
			continue
		end
		if slot.out then
			if now >= slot.outUntil then
				place(state, slot, now)
			end
		elseif slot.owed ~= nil and state.synced and now > slot.owed then
			place(state, slot, now)
		end
	end
end

function Rules.join(state: State, seat: number)
	for id = #state.slots + 1, seat - 1 do
		local empty = newSlot(state, id, Contract.teamOf(id))
		empty.on = false
		empty.owed = nil
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
	local slot = newSlot(state, seat, team)
	if was ~= nil then
		-- the spawn point the seat's last holder stood on is still "in use" for as long as it was
		slot.spawn, slot.spawnAt = was.spawn, was.spawnAt
	end
	state.slots[seat] = slot
end

function Rules.gone(state: State, seat: number)
	local slot = state.slots[seat]
	if slot then
		slot.on = false
		slot.owed = nil
	end
end

-- Put a slot on a team. True when it changed.
function Rules.assign(state: State, id: number, team: number): boolean
	local slot = state.slots[id]
	if slot == nil or not slot.on or slot.team == team or (team ~= 1 and team ~= 2) then
		return false
	end
	slot.team = team
	if not slot.out then
		-- in play: to the new room (a slot that is out goes there by its ordinary respawn)
		slot.owed = state.now
		slot.safeUntil = math.max(slot.safeUntil, state.now + state.feel.protectSecs)
	end
	return true
end

function Rules.result(state: State): Contract.Result?
	return state.final
end

function Rules.view(state: State): Contract.MatchView
	local slots: { Contract.SlotView } = {}
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
	end
	local side = math.max(sideCount(state, 1), sideCount(state, 2))
	return {
		phase = state.phase,
		endsAt = state.endsAt,
		size = math.clamp(side, R.teamMin, R.teamMax),
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

-- Phase, out and protection at t: nil when the slot may fire as far as they go, else the why.
local function barred(state: State, slot: Slot?, t: number): string?
	if state.phase ~= "live" or t < state.liveAt then
		return "phase"
	end
	if slot == nil or not slot.on then
		return "out"
	end
	if slot.out and t >= slot.outAt then
		return "out"
	end
	if slot.owed ~= nil or t < slot.safeUntil then
		return "safe"
	end
	return nil
end

-- May this slot fire a ball born at t, its magazine judged at m (nil = t)? The why is a Contract.WHY
-- code: "phase", "out", "safe", "empty", "fast".
function Rules.canFire(state: State, id: number, t: number, m: number?): (boolean, string?)
	local slot = state.slots[id]
	local why = barred(state, slot, t)
	if why ~= nil or slot == nil then
		return false, why
	end
	local mag = slot.mag
	local at = m or t
	Magazine.update(mag, at)
	if mag.reloadDoneAt ~= nil or mag.rounds <= 0 then
		return false, "empty"
	elseif at < mag.nextFireAt then
		return false, "fast"
	end
	return true, nil
end

-- Fire one ball from this slot's magazine and count the shot: phase, out and protection judged at t,
-- the magazine at m (nil = t).
function Rules.fire(state: State, id: number, t: number, m: number?): (boolean, string?)
	local ok, why = Rules.canFire(state, id, t, m)
	if not ok then
		return false, why
	end
	local slot = state.slots[id]
	local mag = slot.mag
	Magazine.fire(mag, m or t)
	slot.shots += 1
	local reloading = mag.reloadDoneAt
	if reloading ~= nil then
		table.insert(state.events, { kind = "reload", id = id, at = reloading })
	end
	return true, nil
end

-- R: start a reload at time t. False when full, already reloading, or not in play.
function Rules.reload(state: State, id: number, t: number): boolean
	local slot = state.slots[id]
	if slot == nil or not slot.on or slot.out or slot.owed ~= nil or state.phase == "ended" then
		return false
	end
	if not Magazine.reload(slot.mag, t) then
		return false
	end
	table.insert(state.events, { kind = "reload", id = id, at = slot.mag.reloadDoneAt })
	return true
end

-- Is this slot on, in play and unprotected at `now`? (The service adds the spawn room: a body inside
-- its own cannot be hit either.)
function Rules.canBeHit(state: State, id: number, now: number): boolean
	local slot = state.slots[id]
	return slot ~= nil
		and slot.on
		and state.phase == "live"
		and now >= state.liveAt
		and not slot.out
		and slot.owed == nil
		and now >= slot.safeUntil
end

-- The server's verdict that a ball born at `born` (nil = now) from slot `by` struck `id`. True when
-- it was a tag.
function Rules.tag(state: State, by: number, id: number, now: number, born: number?): boolean
	local shooter = state.slots[by]
	local target = state.slots[id]
	if shooter == nil or target == nil or not Rules.canBeHit(state, id, now) then
		return false
	end
	if shooter.team == target.team and not R.friendlyFire then
		return false
	end
	state.scores[shooter.team] += 1
	if shooter.since <= (born or now) then
		-- the same holder as when the ball was born: theirs
		shooter.tags += 1
		shooter.hits += 1
	end
	target.out = true
	target.outAt = now
	target.outUntil = now + state.feel.respawnSecs
	target.outs += 1
	table.insert(state.events, { kind = "tag", by = by, id = id, at = target.outUntil })
	return true
end

-- The Wire.BIT flags the match knows for a slot: out, safe (protection), reload. (The service adds
-- safe for a body in its own spawn room.)
function Rules.bits(state: State, id: number, now: number): number
	local slot = state.slots[id]
	if slot == nil or not slot.on then
		return 0
	end
	if slot.out then
		return BIT.out
	end
	local bits = 0
	if slot.owed ~= nil or now < slot.safeUntil then
		bits += BIT.safe
	end
	local reloading = slot.mag.reloadDoneAt
	if reloading ~= nil and now < reloading then
		bits += BIT.reload
	end
	return bits
end

-- A seated player's verb: "reload" { t }, "side" {}. (The service answers both itself; see the header.)
function Rules.input(state: State, seat: number, verb: string, args: { any }?): (boolean, string?)
	if verb == "reload" then
		local given = if args then args[1] else nil
		local t = state.now
		if type(given) == "number" and given == given then
			t = math.clamp(given, state.now - Clock.MAG_LATE, state.now)
		end
		if Rules.reload(state, seat, t) then
			return true, nil
		end
		return false, Contract.textFor("phase")
	elseif verb == "side" then
		return false, Contract.textFor("side")
	end
	return false, Contract.textFor("phase")
end

-- Type witnesses (Contract, HOW TO IMPORT): from another root, type State = typeof(RulesModule.T.State).
Rules.T = ({} :: any) :: { Slot: Slot, State: State }

return Rules
