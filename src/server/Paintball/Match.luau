--!strict
-- ServerScriptService.Server.Paintball.Match
-- The paintball match as a pure model (checklist PB-2, PB-6, PB-7, PB-14): teams, slots, bot fill,
-- the phase clock, magazines, tags, respawns and protection, the score and the end card. No
-- Instances, no remotes, no arena: the service (PaintballService) feeds it time, joins, leaves, shots
-- and hit verdicts, and turns the events it emits into wire messages.
-- OWNED BY THE MATCH-AND-BOTS LANE. THIS IS A STUB: every function below keeps its name and signature
-- (the service and the bots are written against them today) and gets its real body from that lane.
--
-- WHAT THE REAL MODEL DOES (Shared/Paintball/Contract holds the numbers and the shapes):
--   * idle until the first person joins; then every slot of both teams exists at once: 2 x size
--     slots, ids 1..2 x size, odd ids team 1 and even ids team 2, bots in every slot no person holds
--     (PB-6: one person is enough; never fewer than Rules.teamMin a side).
--   * join: a person takes a bot's slot on the side with fewer people (same id, same team; the tally
--     of that slot starts again). When every slot is a person and size < teamMax the match grows by
--     one a side (a "roster" event). Past 2 x teamMax people: refused "full". leave: a bot takes the
--     slot back at once. When the last person leaves the match goes idle and everything is dropped.
--   * phases: briefing (Rules.briefingSecs, everyone placed in the spawn rooms: a "respawn" event per
--     slot) -> live (Rules.matchSecs) -> ended (Rules.endCardSecs, an "end" event with the card) ->
--     briefing again with matchId + 1, scores and tallies cleared, sizes fitted to the people present.
--   * one Magazine per slot (Shared/Paintball/Magazine with Rules.magazine, fireInterval, reloadSecs),
--     judged at the time it is given: for a person that is the clamped fire time of Clock.stamp, for
--     a bot the server's now. fire() refuses outside "live", while out, while protected, and whatever
--     the magazine refuses; it counts the shot. An automatic or manual reload emits "reload".
--   * hit(by, id): ignored unless both are in play, on different teams, `id` not out and not
--     protected. Otherwise a tag: a point to by's team, `id` is out for Rules.respawnSecs (a "tag"
--     event), then a "respawn" event with a spawn point index (not one in use, not one an opponent is
--     near if it can be helped) and Rules.protectSecs of protection. Balls already flying still count.
--   * the end card: the winner (or a draw), a row per slot with tags, outs, shots, hits and accuracy,
--     most tags first, and the silly awards.
-- Interface: new(opts?) -> Match; join(m, key, name, userId, now) -> (id?, why?); leave(m, key, now)
--   -> id?; slot(m, id) -> Slot?; slotOf(m, key) -> Slot?; humans(m) -> n; step(m, now); drain(m) ->
--   { Event }; canFire(m, id, t) -> (ok, why?); fire(m, id, t) -> (ok, why?); reload(m, id, t) -> ok;
--   canBeHit(m, id, now) -> ok; hit(m, by, id, now) -> tagged; bits(m, id, now) -> Wire.BIT flags;
--   view(m) -> MatchView; card(m, now) -> EndCard

local Import = require("../Import")
local Contract: typeof(require(game.ReplicatedStorage.Shared.Paintball.Contract)) = Import.shared("Paintball/Contract")
local Magazine: typeof(require(game.ReplicatedStorage.Shared.Paintball.Magazine)) = Import.shared("Paintball/Magazine")

type Mag = typeof(Magazine.new(1, 1, 1))
type Phase = typeof(Contract.T.Phase)
type Event = typeof(Contract.T.Event)
type MatchView = typeof(Contract.T.MatchView)
type EndCard = typeof(Contract.T.EndCard)

export type Slot = {
	id: number,
	team: number,
	name: string,
	bot: boolean,
	key: any?, -- the player who holds the slot (anything usable as a table key); nil for a bot
	userId: number, -- 0 for a bot
	out: boolean, -- tagged out, waiting to respawn
	outUntil: number,
	safeUntil: number, -- spawn protection ends
	mag: Mag,
	tags: number,
	outs: number,
	shots: number,
	hits: number,
}

export type Match = {
	matchId: number,
	phase: Phase,
	endsAt: number, -- server time the phase ends; 0 while idle
	size: number, -- a side
	scores: { number },
	slots: { Slot }, -- by id; empty while idle
	byKey: { [any]: number }, -- player -> slot id
	events: { Event },
	seed: number,
}

export type Opts = { seed: number? }

local Match = {}

function Match.new(opts: Opts?): Match
	return {
		matchId = 0,
		phase = "idle",
		endsAt = 0,
		size = Contract.Rules.teamMin,
		scores = { 0, 0 },
		slots = {},
		byKey = {},
		events = {},
		seed = (opts and opts.seed) or 1,
	}
end

-- A person joins. Returns their slot id, or nil and a Contract.WHY code ("full", "already").
function Match.join(_m: Match, _key: any, _name: string, _userId: number, _now: number): (number?, string?)
	return nil, "closed"
end

-- A person leaves; a bot takes the slot. Returns the slot id, nil if they were not in.
function Match.leave(_m: Match, _key: any, _now: number): number?
	return nil
end

function Match.slot(m: Match, id: number): Slot?
	return m.slots[id]
end

function Match.slotOf(m: Match, key: any): Slot?
	local id = m.byKey[key]
	return if id then m.slots[id] else nil
end

function Match.humans(m: Match): number
	local n = 0
	for _ in m.byKey do
		n += 1
	end
	return n
end

-- Advance the phase clock, respawns and protection to `now`; appends events.
function Match.step(_m: Match, _now: number) end

-- The events since the last drain, oldest first.
function Match.drain(m: Match): { Event }
	local out = m.events
	m.events = {}
	return out
end

-- May this slot fire at time t? The why is a Contract.WHY code: "phase", "out", "safe", "empty", "fast".
function Match.canFire(_m: Match, _id: number, _t: number): (boolean, string?)
	return false, "phase"
end

-- Fire one ball from this slot's magazine at time t and count the shot.
function Match.fire(_m: Match, _id: number, _t: number): (boolean, string?)
	return false, "phase"
end

-- R: start a reload at time t. False when full, already reloading, or not in play.
function Match.reload(_m: Match, _id: number, _t: number): boolean
	return false
end

function Match.canBeHit(_m: Match, _id: number, _now: number): boolean
	return false
end

-- The server's verdict that a ball from `by` struck `id`. True when it was a tag.
function Match.hit(_m: Match, _by: number, _id: number, _now: number): boolean
	return false
end

-- The Wire.BIT flags the match knows for a slot: out, safe, reload.
function Match.bits(_m: Match, _id: number, _now: number): number
	return 0
end

function Match.view(m: Match): MatchView
	return { matchId = m.matchId, phase = m.phase, endsAt = m.endsAt, size = m.size, scores = { 0, 0 }, slots = {} }
end

function Match.card(m: Match, now: number): EndCard
	return { matchId = m.matchId, winner = 0, scores = { 0, 0 }, rows = {}, awards = {}, nextAt = now }
end

return Match
