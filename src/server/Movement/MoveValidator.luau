--!strict
-- ServerScriptService.Server.Movement.MoveValidator
-- Validates client motor packets; log-only until W7.
-- Interface (BUILD_PLAN §1.4): accept(actor, packet) -> ok, correction; pose(id, t); also new(world, opts); reset;
--   forget; hop; reachable; throughSlab; meterOf; wallGap; fastest; clearFlag; isFlagged; last; stats; the shared bounds leapRise, apexAllowance,
--   leapUpAllowance, gravity, nearTrampoline; C
--
-- The server side of D2: players move their own squirrel with the shared SquirrelMotor and stream its
-- serialized state; this module judges every transition with `SquirrelMotor.envelope` (adjacency and
-- transfer gaps against Routes/Graph, per-kind speed caps with tolerance, gravity-consistent arcs,
-- launch envelopes, wall crossings), keeps a leaky bucket of violation weight per actor, a 1 s pose
-- history for lag compensation (pose(id, t)), a pounce-rate check and a clock check (the client's
-- clock may not run faster than real time beyond what jitter explains). A flagged actor gets the last
-- accepted state as its correction. Pure and steppable: no engine calls, no threads; the service that
-- owns it drains the remote queue into `accept` each frame (BUILD_PLAN §1.3 step 1) and calls `reset`
-- on possession, teleports and respawns (§1.5 step 6). Budget (spike S3): <= 0.05 ms per squirrel per
-- tick.
-- Live (Boot/Game.movement, 2026-11-18), on top of S3:
--   * The clock check reads the arrival offset (server time - client clock): an honest clock never runs ahead of
--     real time, so the offset never falls further below its lowest of a few seconds ago (clockLag) and of about
--     eight seconds ago than the link's latency can swing (clockSlack, or the engine's round trip: pingOf); a time
--     hack makes it fall without end. (S3's rate over a 1 s window flagged a packet held up for half a second once
--     it became the oldest of the window.)
--   * A packet with a number that is not finite is never judged nor taken (SquirrelWire.sane).
--   * A gap too long to judge move by move (a stall, a loss burst, a client sending sparsely) is judged as a whole
--     (hop(): reach at the fastest pace over the time the server's own arrivals allow, no climb or height above a
--     leap without a rail as high near or a trampoline, walls chord by chord), and more than gapMax of them in
--     gapWindow flag; it is never a snap target. MovementService uses hop() for the first packet after a move it made.
--   * Bounded cost: the world's rail index answers no query wider than C.RAIL_REACH_MAX, a long line's walls take at
--     most ValidatorWorld.C.MAX_CHORDS chords: no packet's numbers and no silence make a judgement dear.
--   * The clock over the long run (C.CLOCK_RUN_*): a clock a little fast adds up past any latency's drop.
--   * Marks (the clock's history, recent gaps and walls, the sprint meter) outlive a reset; forget() drops them.
--   * The server's own sprint meter (_stamina): a sprint that never tires shows.
--   * The client's own river recovery (Movement/Recovery.riverFall: a fall into the river puts the body on the
--     nearer quay) is taken as honest: the quay spot is the new baseline.
--   * Floors: a grounded body off the rails must have something under its feet (world.floorBelow, when the world
--     has one: Movement/ValidatorWorld); "float", a third of a flag each, so a vehicle drawn a little behind the
--     server's under a body on its roof is not a flag.
--   * Pounces (the combat re-review, 2026-11-19): the envelope dates the motor's pounce by its window
--     (verdict.pounce, the client clock it launched at, and verdict.pounceGap, the gap it lies in); two closer than
--     the cooldown are a flag at any gap. A plain arc's baseline takes the vertical speed gravity gives, not the one
--     the packet claims within the slack (claimed a little slower each packet, the slack added up to a slow fall).
--   * Round 3 (2026-11-19): the baseline keeps only what the envelope judged (SquirrelMotor.Judged: the vertical speed
--     within the bounds it was checked against, the horizontal one within its cap, an arc's height no higher than the
--     arc), so no later packet is judged by a number only the client claimed; a line too long for the short wall test
--     that crosses a wall is weighed as a gap's (wallGap); a grounded packet higher than where the body last stood needs
--     a floor just under its feet (world.floorNear: no creeping up posSlack a packet); a landing the gap hid counts as
--     ground for the sprint meter.
--   * Round 6 (2026-11-19), two invariants whatever path a packet takes: (A) every packet's rail claim agrees with its
--     x, y, z (SquirrelMotor.fieldCheck), and a packet with no baseline is judged from a place the server holds (the
--     service's gate, root or last accepted place: never taken where it says); (B) the displacement governor (_govern):
--     every window of up to C.GOV_WINDOW of accepted places stays within the motor's honest pace across and up
--     (governorBounds), its history kept across a snap (anchor). Every grounded packet off the rails needs floorNear.
--   * Round 10 (2026-11-20, the round-9 review): reachable() no more lenient than the envelope (riseFrom, both legs of
--     a way round with cover, no rail rule), the gate's rail rule only for the route its first packet claims, a move
--     with one end on a rail slab-judged at the off-rail end's column (world.railSlab), a way round a corner or a
--     building's end up to ValidatorWorld.C.AROUND_GAP explains a gap's wall (a third, never escalated: verdict.cornered),
--     the sprint meter on the packets' own clocks (a gap drains the least sprint that covers it), gapMax 6.

local Import = require("../Import")
local Motion = Import.shared("Routes/Motion") :: typeof(require("../../shared/Routes/Motion"))
local SquirrelMotor = Import.shared("Movement/SquirrelMotor") :: typeof(require("../../shared/Movement/SquirrelMotor"))
local Recovery = Import.shared("Movement/Recovery") :: typeof(require("../../shared/Movement/Recovery"))
local Trampoline = Import.shared("Movement/Trampoline") :: typeof(require("../../shared/Movement/Trampoline"))
local Units = Import.shared("Config/Units") :: typeof(require("../../shared/Config/Units"))
local SquirrelWire = Import.shared("Movement/SquirrelWire") :: typeof(require("../../shared/Movement/SquirrelWire"))

local MoveValidator = {}
MoveValidator.__index = MoveValidator

-- Exported types do not cross the Import shim (rule 1): restated loosely from Shared/Movement/SquirrelMotor.
export type Snapshot = { [string]: number | boolean }
export type State = any
export type Violation = { [string]: any }
export type World = any

export type Packet = { seq: number, snapshot: Snapshot }

export type Verdict = {
	ok: boolean, -- no violation in this packet
	accepted: boolean, -- the state became the new baseline (false when dropped as stale)
	violations: { Violation },
	flagged: boolean, -- the bucket is over the threshold after this packet
	bucket: number,
	correction: Snapshot?, -- the state the client should snap to (flagged packets only)
	resync: boolean, -- the gap was too long to judge; the packet was taken as the new baseline
	baseline: boolean, -- the first packet of an unknown actor
	snapped: boolean?, -- (Movement/MovementService) the body was snapped back for this packet
	launched: boolean?, -- the move from the last packet holds a launch (a leap, a pounce, off a rail) the envelope saw
	-- the client clock the motor's pounce launched at, when the move holds a pounce-shaped launch (the window rose, the
	-- body flies as that pounce: SquirrelMotor.envelope's pounce), and the client clock gap it lies in (somewhere in it:
	-- Movement/MovementService dates no pounce from a gap a silence may have made)
	pounce: number?,
	pounceGap: number?,
	-- (Movement/MovementService) a click's copy the packet carried, not taken yet: its number and motor clock
	click: { seq: number, clock: number }?,
	river: boolean?, -- the packet is the client's own river recovery (the quay spot of a fall it could have made)
	-- the packet's only doubts are a gap too long to judge move by move and a wall third a way round a corner explains
	-- (judged from the last packet, both ends off the rails): reached from it (MovementService: invariant E's chain)
	cornered: boolean?,
}

export type Options = {
	flagThreshold: number?, -- bucket level that flags (default 1.0)
	leakPerSecond: number?, -- bucket drain per server second (default 0.5)
	historySeconds: number?, -- pose ring length (default 1.0)
	clockSeconds: number?, -- seconds of server time the clock check keeps offsets for (default 10)
	clockLag: number?, -- the mark is the lowest offset at least this old (default 3: a 1.12 x hack still shows)
	clockSlack: number?, -- how far (s) the offset may fall below that lowest (default 0.35: 80 to 300 ms and jitter)
	boostOf: ((actorId: any) -> boolean)?, -- the server's knowledge of the chili boost (default: never)
	-- gaps too long to judge move by move allowed inside gapWindow (default 6: an honest link's loss bursts every 2 s,
	-- validator round 10; each gap is judged as a whole by hop(), and by invariant E never the held place but by a chain)
	gapMax: number?,
	gapWindow: number?, -- seconds of server time (default 10)
	clockStepMax: number?, -- the most (s) the offset may ever fall below a mark, whatever the ping (default 0.9)
	-- the link's round trip in seconds as the engine measures it (Player:GetNetworkPing): a latency that drops can lower
	-- the offset by as much as it was. Default: none (the slack alone)
	pingOf: ((actorId: any) -> number?)?,
}

type History = { clock: { number }, x: { number }, y: { number }, z: { number }, head: number, count: number }

type ClockSample = { server: number, offset: number, ping: number }

-- What the validator remembers of an actor across a reset that keeps it (a snap-back, a move the server made): the
-- client's clock runs on through them, and so does a client hiding its moves.
type Marks = {
	-- the lowest offset in each CLOCK_BUCKET of server time (`server` is the bucket) and the highest ping in it
	offsets: { ClockSample },
	runs: { ClockSample }, -- the lowest offset in each C.CLOCK_RUN_BUCKET of server time, for C.CLOCK_RUN_KEEP
	gaps: { number }, -- server times of the recent gaps too long to judge move by move
	wallGaps: { number }, -- server times of the recent gaps whose straight line went through a wall
	stamina: number, -- the server's own sprint meter (stamina()): 1 full, below 0 the client sprints on credit
	staminaAt: number, -- server time it was last brought up to date
	-- the body is in the flight of a launch made with the meter empty: a winded one, no faster than a walk (_stamina)
	tiredFlight: boolean?,
	gov: Gov?, -- the displacement governor's history (_govern); kept across a snap-back, cleared by a move (anchor)
	-- the governor's closest call per window (studs over its allowance, below 0 within it): across and up, for windows
	-- of up to 0.25 s, 1 s and C.GOV_WINDOW (governorPeak: the honest margin the specs report)
	govPeak: { number }?,
	-- client clock of the last grab a short gap hid (SquirrelMotor.envelope: one per two frames); in the marks so a reset
	-- (a snap, a teleport, a Reset) does not give a fresh one (validator round 8, the round-7 review's LOW)
	lastGrab: number?,
	-- where the walls were last judged from (validator round 9: a move shorter than ValidatorWorld.C.MIN_CHORD is no
	-- chord, so a creep of under 0.05 st a packet was never wall-tested, nor the first packet after a snap; the line
	-- from here is, once it is a chord). In the marks: a snap back, a hand-off (parked) keep it; a move the server made
	-- puts it where the body was put
	wallX: number?,
	wallY: number?,
	wallZ: number?,
	wallAt: number?, -- (server time the anchor was set, and its client clock: the run a way round from it may stand for)
	wallClock: number?,
}

-- What a body keeps of its last driver when no one drives it (forget), for the next (takeOver): the constraints, never
-- spare allowance (invariant C, validator round 8): the governor's history, the server's sprint meter (refilled by the
-- server's own time since), and the recent gaps and wall gaps
type Parked = {
	gov: Gov,
	stamina: number,
	staminaAt: number,
	gaps: { number },
	wallGaps: { number },
	wallX: number?,
	wallY: number?,
	wallZ: number?,
}

-- The displacement governor (validator round 6, invariant B; _govern): the newest accepted place, the running sums it is
-- judged by, and a ring of earlier ones C.GOV_SPACING apart, C.GOV_WINDOW back. Each sum is cumulative from the ring's
-- start: G the time the moves stand for, S the server's arrival time, BH / BV the honest horizontal travel and rise those
-- moves allowed (studs).
type Gov = {
	G: number,
	S: number,
	X: number,
	Y: number,
	Z: number,
	BH: number,
	BV: number,
	clock: number?, -- the client clock of the newest packet (nil: an anchor the server set)
	route: boolean, -- the newest packet was on a rail
	g: { number },
	s: { number },
	x: { number },
	y: { number },
	z: { number },
	bh: { number },
	bv: { number },
	head: number,
	count: number,
}

type Actor = {
	last: State,
	lastSeq: number,
	lastServerTime: number,
	bucket: number,
	flagged: boolean,
	flaggedAt: number?,
	marks: Marks,
	history: History,
	packets: number,
	violations: number,
	lastPounce: number?, -- client clock of the last pounce's launch (the pounce rate)
	drops: number,
	resyncs: number,
	lastAcceptedAt: number, -- server time of the last accepted packet
	lastLanded: boolean, -- the last accepted packet came down on a floor inside its gap (the envelope's Judged.landed)
	standY: number?, -- the height it last stood at off the rails (a grounded packet higher than this rose with its floor)
	lastOffset: number, -- its arrival offset (server time - client clock)
	lastRiver: boolean, -- the last accepted packet was a river landing (a landing never follows a landing)
}

export type MoveValidator = typeof(setmetatable(
	{} :: {
		world: World,
		flagThreshold: number,
		leakPerSecond: number,
		historySeconds: number,
		clockSeconds: number,
		clockLag: number,
		clockSlack: number,
		boostOf: (actorId: any) -> boolean,
		gapMax: number,
		gapWindow: number,
		clockStepMax: number,
		pingOf: (actorId: any) -> number?,
		_actors: { [any]: Actor },
		_marks: { [any]: Marks },
		_fastest: { [boolean]: number },
		_govBounds: { [boolean]: GovBounds },
		_parked: { [any]: Parked? }, -- what a body no one drives keeps of its last driver (forget), for its next
	},
	MoveValidator
))

MoveValidator.C = table.freeze({
	WALL_GAP_WINDOW = 20, -- seconds: a second gap through a wall inside this is a whole flag
	STAMINA_WALK = 1.08, -- faster than this times the walk on the ground drains the server's sprint meter
	STAMINA_GROUND = 0.6, -- studs: a packet "in the air" this near a floor ...
	STAMINA_AIR_VY = 3, -- ... with less vertical speed than this (studs/s) is on the ground for the meter
	STAMINA_SLACK = 0.5, -- how far below empty it may go (two seconds of sprint: landings' carry, rounding)
	-- seconds: the longest gap the meter takes for an honest loss burst (the least sprint that covers it drains, the rest
	-- refills); a longer one drains all of its time when faster than a walk, and never refills (validator round 10)
	STAMINA_BURST = 1.2,
	-- studs: the widest any rail query of the validator looks (its world's index is bounded to it: a packet's numbers,
	-- a long silence, never widen a query's scan, which grows with the cube of its radius); a body high in the air after
	-- leaving the tallest trunk is within this of it
	RAIL_REACH_MAX = 90,
	-- studs: a packet that claims a route is on it only this near its samples (a rail's grab; the feet drawn on a big
	-- trunk's bark are up to 5.95 off them): a route id made up, or far from where the packet is, is no rail
	ROUTE_NEAR = Motion.C.airGrab,
	CLOCK_PING_SHARE = 0.6, -- of the median round trip: what a one-way latency that drops can lower the offset by
	CLOCK_RUN_BUCKET = 5, -- seconds of server time per long-run clock bucket ...
	CLOCK_RUN_KEEP = 120, -- ... kept this long ...
	CLOCK_RUN_AGE = 60, -- ... the mark: the lowest of those at least this old (a 1.02 x clock is 1.2 s ahead of it) ...
	CLOCK_RUN_MAX = 1.1, -- ... which the offset may never fall below by more (seconds: more than any latency drops)
	-- the displacement governor (_govern, validator round 6): every pair of accepted places this far apart in time or
	-- less (seconds) is judged, the places kept at least GOV_SPACING apart (seconds) in a ring of GOV_SLOTS (the cost)
	GOV_WINDOW = 3,
	GOV_SPACING = 1 / 20,
	GOV_SLOTS = 64,
	-- studs: the farthest the drawn pose lies off a rail's centreline (a big trunk's bark, 5.95; a lookout's lift)
	DRAWN_MAX = 6.5,
	-- seconds: the most of a move's time the governor's "near a rail" and "near a trampoline" reach from the last place
	-- stands for (a quarter second of the fastest pace)
	GOV_NEAR_T = 0.25,
	-- seconds: what an arrival's jitter may add to the server's time since the wall anchor (creep's way round)
	CREEP_JITTER = 0.35,
})

local creep: (
	world: World,
	marks: Marks,
	prev: State?,
	next: State,
	violations: { Violation },
	serverTime: number,
	pace: number
) -> ()
local CLOCK_BUCKET = 0.5 -- seconds of server time per clock bucket
-- (ValidatorWorld.C's chord bound: a shorter move is no chord)
local MIN_CHORD = 0.05
local HISTORY_SLOTS = 64 -- 1 s at 60 Hz, with room for bursts

local function newHistory(): History
	return {
		clock = table.create(HISTORY_SLOTS, 0),
		x = table.create(HISTORY_SLOTS, 0),
		y = table.create(HISTORY_SLOTS, 0),
		z = table.create(HISTORY_SLOTS, 0),
		head = 0,
		count = 0,
	}
end

local function record(h: History, clock: number, x: number, y: number, z: number)
	h.head = (h.head % HISTORY_SLOTS) + 1
	h.clock[h.head] = clock
	h.x[h.head] = x
	h.y[h.head] = y
	h.z[h.head] = z
	if h.count < HISTORY_SLOTS then
		h.count += 1
	end
end

-- bounded(index): the index with every query's radius held to C.RAIL_REACH_MAX (cells for forEachNear)
local function bounded(index: any): any
	if index == nil or index.bounded then
		return index
	end
	local most = MoveValidator.C.RAIL_REACH_MAX
	local cells = math.ceil(most / (index.cellSize or 20))
	local b = setmetatable({ bounded = true }, { __index = index })
	function b.nearest(_self: any, x: number, y: number, z: number, maxDist: number, ...: any): any
		return index:nearest(x, y, z, math.min(maxDist, most), ...)
	end
	function b.nearestOnRoute(_self: any, routeId: number, x: number, y: number, z: number, maxDist: number): any
		return index:nearestOnRoute(routeId, x, y, z, math.min(maxDist, most))
	end
	function b.forEachNear(_self: any, x: number, y: number, z: number, radiusCells: number, fn: any)
		return index:forEachNear(x, y, z, math.min(radiusCells, cells), fn)
	end
	return b
end

function MoveValidator.new(world: World, opts: Options?): MoveValidator
	local o: Options = opts or {}
	-- (its own copy of the world, with the index bounded: Motion's caches on it are the validator's own)
	local own = table.clone(world)
	own.index = bounded(world.index)
	local self = setmetatable({
		world = own,
		flagThreshold = o.flagThreshold or 1.0,
		leakPerSecond = o.leakPerSecond or 0.5,
		historySeconds = o.historySeconds or 1.0,
		clockSeconds = o.clockSeconds or 10,
		clockLag = o.clockLag or 3,
		clockSlack = o.clockSlack or 0.35,
		boostOf = o.boostOf or function(_actorId: any): boolean
			return false
		end,
		gapMax = o.gapMax or 6,
		gapWindow = o.gapWindow or 10,
		clockStepMax = o.clockStepMax or 0.9,
		pingOf = o.pingOf or function(_actorId: any): number?
			return nil
		end,
		_actors = {} :: { [any]: Actor },
		_marks = {} :: { [any]: Marks },
		_fastest = {},
		_govBounds = {},
		_parked = {},
	}, MoveValidator)
	return self
end

-- reset(actorId, snapshot, serverTime, seq?): take the given state as the baseline with a clean bucket
-- (possession, teleport, respawn, accepted correction). `snapshot` nil: the next packet is the baseline. Either way the
-- actor's marks (its clock's history, its recent gaps) are kept: forget() drops them (a new body).
function MoveValidator.reset(self: MoveValidator, actorId: any, snapshot: Snapshot?, serverTime: number?, seq: number?)
	if not snapshot or not SquirrelWire.sane(snapshot) then
		self._actors[actorId] = nil
		return
	end
	local state = SquirrelMotor.deserialize(snapshot)
	local now = serverTime or 0
	local marks = self._marks[actorId]
	if marks == nil then
		marks = { offsets = {}, runs = {}, gaps = {}, wallGaps = {}, stamina = 1, staminaAt = now }
		self._marks[actorId] = marks
	end
	local m = marks :: Marks
	local key = math.floor(now / CLOCK_BUCKET)
	local newest = m.offsets[#m.offsets]
	if newest and newest.server == key then
		newest.offset = math.min(newest.offset, now - state.clock)
	else
		table.insert(m.offsets, { server = key, offset = now - state.clock, ping = 0 })
	end
	local actor: Actor = {
		last = state,
		lastSeq = seq or -math.huge,
		lastServerTime = now,
		bucket = 0,
		flagged = false,
		flaggedAt = nil,
		marks = m,
		history = newHistory(),
		packets = 0,
		violations = 0,
		lastPounce = nil,
		drops = 0,
		resyncs = 0,
		lastAcceptedAt = now,
		lastLanded = false,
		standY = if state.grounded and not state.routeId then state.y else nil,
		lastOffset = now - state.clock,
		lastRiver = false,
	}
	record(actor.history, state.clock, state.x, state.y, state.z)
	self._actors[actorId] = actor
end

-- forget(actorId): drop the actor and its marks (a hand-off: a new driver, a new start), all but the displacement
-- governor's history of the body, kept aside for whoever takes it next (takeOver; invariant C: giving a body up and
-- taking it back buys no fresh allowance)
function MoveValidator.forget(self: MoveValidator, actorId: any)
	local marks = self._marks[actorId]
	self._actors[actorId] = nil
	self._marks[actorId] = nil
	if marks and marks.gov then
		self._parked[actorId] = {
			gov = marks.gov,
			stamina = marks.stamina,
			staminaAt = marks.staminaAt,
			gaps = marks.gaps,
			wallGaps = marks.wallGaps,
			wallX = marks.wallX,
			wallY = marks.wallY,
			wallZ = marks.wallZ,
		}
	end
end

local function verdict(
	ok: boolean,
	accepted: boolean,
	violations: { Violation },
	flagged: boolean,
	bucket: number,
	correction: Snapshot?,
	resync: boolean,
	baseline: boolean
): Verdict
	return {
		ok = ok,
		accepted = accepted,
		violations = violations,
		flagged = flagged,
		bucket = bucket,
		correction = correction,
		resync = resync,
		baseline = baseline,
	}
end

-- accept(actorId, packet, serverTime) -> verdict. The first packet of an unknown actor is the baseline.
function MoveValidator.accept(self: MoveValidator, actorId: any, packet: Packet, serverTime: number): Verdict
	local actor = self._actors[actorId]
	if not SquirrelWire.sane(packet.snapshot) or not (math.abs(packet.seq) < SquirrelWire.MAX_MAGNITUDE) then
		-- a number off the wire that is NaN, infinite or out of the world: never judged, never a baseline
		local bad = { { code = "malformed", severity = 1, detail = "a number in the packet is not finite" } }
		if not actor then
			return verdict(false, false, bad, true, 1, nil, false, false)
		end
		actor.packets += 1
		actor.violations += 1
		actor.bucket += 1
		local flagged = actor.bucket >= self.flagThreshold
		if flagged and not actor.flagged then
			actor.flaggedAt = serverTime
		end
		actor.flagged = flagged
		return verdict(false, false, bad, flagged, actor.bucket, SquirrelMotor.serialize(actor.last), false, false)
	end
	-- every field within its own bounds (SquirrelMotor.FIELD_BOUNDS), the baseline's too: a number no check bounds is
	-- one a later reader trusts (the round-4 review: the trunk normal moved the drawn pose 600 studs)
	local fieldFaults = SquirrelMotor.fieldCheck(packet.snapshot, self.world)
	if not actor then
		if #fieldFaults > 0 then
			return verdict(false, false, fieldFaults, true, 1, nil, false, false)
		end
		self:reset(actorId, packet.snapshot, serverTime, packet.seq)
		-- (the governor from the place the server anchored, for the time since: MovementService's gate)
		local first = self._actors[actorId]
		-- (the meter brought up to date by the server's own time since its last packet: a ride, a hold, a move the
		-- server made refill it as the motor's does; validator round 10: the meter is otherwise judged on the packets'
		-- clocks, and none covers that time)
		local fm = first.marks
		fm.stamina =
			math.min(1, fm.stamina + math.max(0, serverTime - fm.staminaAt) / SquirrelMotor.params.sprintRefill)
		fm.staminaAt = serverTime
		local gov = first.marks.gov
		local govFaults: { Violation } = {}
		-- (the first packet after a snap or a hand-off: a creep's walls from the kept anchor, as any packet's)
		creep(
			self.world,
			first.marks,
			nil,
			first.last,
			govFaults,
			serverTime,
			SquirrelMotor.runCap(self.boostOf(actorId))
		)
		MoveValidator._govern(
			self,
			actorId,
			first.marks,
			first.last,
			if gov then math.max(0, serverTime - gov.S) else 0,
			serverTime,
			self.clockSlack,
			govFaults
		)
		if #govFaults > 0 then
			first.bucket = 1
			first.flagged = true
			first.flaggedAt = serverTime
			first.violations += #govFaults
			return verdict(false, true, govFaults, true, 1, nil, false, true)
		end
		return verdict(true, true, {}, false, 0, nil, false, true)
	end
	actor.packets += 1
	-- drain the bucket by server time
	local elapsed = math.max(0, serverTime - actor.lastServerTime)
	actor.bucket = math.max(0, actor.bucket - self.leakPerSecond * elapsed)
	actor.lastServerTime = serverTime

	if packet.seq <= actor.lastSeq then
		actor.drops += 1
		return verdict(true, false, {}, actor.flagged, actor.bucket, nil, false, false)
	end
	actor.lastSeq = packet.seq

	local next = SquirrelMotor.deserialize(packet.snapshot)
	local prev = actor.last
	local dt = next.clock - prev.clock
	local violations: { Violation } = table.clone(fieldFaults)

	-- clock: the arrival offset (server time - client clock: the one-way latency and a constant) may not fall more
	-- than the link can swing below its lowest of a while ago. A time hack runs the client clock ahead, and the offset
	-- falls without end (a second per second at double speed); a latency that drops (a congested link clearing, a
	-- handover from cellular to wifi) lowers it once, by at most the latency it had. Two marks: the lowest offset of
	-- the buckets at least clockLag old (a fast hack shows within a second; a hack's own packets never lower the mark
	-- they are held to) and of those at least clockSeconds - 2 old (a slow one adds up: a 1.12 x clock shows within
	-- three seconds on a quick link, eight on the slowest). The swing allowed below each bucket: the slack, or
	-- C.CLOCK_PING_SHARE of the round trip the engine measured in that bucket when larger (the one-way latency that
	-- dropped since was at most that; a lag spike widens the swing below its own bucket only), never more than
	-- clockStepMax. And over the long run
	-- (C.CLOCK_RUN_AGE to C.CLOCK_RUN_KEEP seconds back) the offset may never fall more than C.CLOCK_RUN_MAX, the most
	-- any latency can drop: a clock a little fast (1.02 x) adds up past it in a minute or so.
	local offset = serverTime - next.clock
	local marks = actor.marks
	local buckets = marks.offsets
	local key = math.floor(serverTime / CLOCK_BUCKET)
	local ping = self.pingOf(actorId)
	ping = if type(ping) == "number" and ping >= 0 and ping < 10 then ping else 0
	local newest = buckets[#buckets]
	if newest and newest.server == key then
		newest.offset = math.min(newest.offset, offset)
		newest.ping = math.max(newest.ping, ping :: number)
	else
		table.insert(buckets, { server = key, offset = offset, ping = ping :: number })
	end
	while #buckets > 1 and (key - buckets[1].server) * CLOCK_BUCKET > self.clockSeconds do
		table.remove(buckets, 1)
	end
	local mark = math.huge
	local worst, worstAhead, worstSwing, swing = -math.huge, 0, 0, self.clockSlack
	local function judge(b: ClockSample)
		local swingB = math.min(math.max(self.clockSlack, b.ping * MoveValidator.C.CLOCK_PING_SHARE), self.clockStepMax)
		swing = math.max(swing, swingB)
		local aheadB = b.offset - offset
		if aheadB - swingB > worst then
			worst, worstAhead, worstSwing = aheadB - swingB, aheadB, swingB
		end
	end
	for _, b in buckets do
		if (key - b.server) * CLOCK_BUCKET >= self.clockLag then
			mark = math.min(mark, b.offset)
			judge(b)
		end
	end
	if mark == math.huge then
		mark = buckets[1].offset -- (newer than the lag: the first bucket since the baseline)
		judge(buckets[1])
	end
	if worst > 0 then
		table.insert(violations, {
			code = "clock",
			severity = if worstAhead > self.clockStepMax then 1 else 0.5,
			detail = `client clock {worstAhead} s ahead of its arrivals (swing {worstSwing} s)`,
		})
	end
	-- the long run: the lowest offset of each C.CLOCK_RUN_BUCKET seconds, kept C.CLOCK_RUN_KEEP
	local runs = marks.runs
	local runKey = math.floor(serverTime / MoveValidator.C.CLOCK_RUN_BUCKET)
	local lastRun = runs[#runs]
	if lastRun and lastRun.server == runKey then
		lastRun.offset = math.min(lastRun.offset, offset)
	else
		table.insert(runs, { server = runKey, offset = offset, ping = 0 })
	end
	while #runs > 1 and (runKey - runs[1].server) * MoveValidator.C.CLOCK_RUN_BUCKET > MoveValidator.C.CLOCK_RUN_KEEP do
		table.remove(runs, 1)
	end
	local runMark = math.huge
	for _, b in runs do
		if (runKey - b.server) * MoveValidator.C.CLOCK_RUN_BUCKET >= MoveValidator.C.CLOCK_RUN_AGE then
			runMark = math.min(runMark, b.offset)
		end
	end
	if runMark < math.huge and runMark - offset > MoveValidator.C.CLOCK_RUN_MAX then
		table.insert(violations, {
			code = "clock",
			severity = 1,
			detail = `client clock {runMark - offset} s ahead of its arrivals of a minute ago`,
		})
	end

	-- the time the gap can stand for: the client's clock gap, but never more than the server's own gap between the two
	-- arrivals and what the clock check lets the arrival offset fall (an honest dt is the server gap plus the fall of
	-- the offset, and the check above holds that fall to the mark less the swing): a clock jumped ahead buys no reach
	local serverGap = math.max(0, serverTime - actor.lastAcceptedAt)
	local dtEff = math.min(dt, serverGap + math.max(0, actor.lastOffset - mark) + swing)

	local resync = false
	local cornered = false -- (a wall third a way round a corner explains: verdict.cornered)
	local launched = false
	local charge: string? = nil -- (a launch the meter pays for: the envelope's judged.charge)
	local pounceAt: number? = nil
	-- what the validator keeps of the packet's speeds (the round-3 review: no later packet is judged by a speed only the
	-- client claimed): the envelope's Judged, or, for a move it does not judge, the claim held to the motor's own bounds
	local P = SquirrelMotor.params
	local keepVy = if next.grounded or next.routeId
		then 0
		else math.clamp(next.vy, -P.terminalFall, P.leapUp * SquirrelMotor.envelopeParams.launchTol)
	local keepXZ = if next.routeId then 0 else self:fastest(actorId)
	local landed = false
	local boosted = self.boostOf(actorId)
	local fastest = self:fastest(actorId)
	-- the client's own river recovery (Movement/Recovery.riverFall: the client sends the quay spot on the frame it put the
	-- body there): the spot of a fall into the water the body could have made from the last place the server accepted
	-- (its own vertical speed, the gap's time up to maxDt), or a walk on from it in the time left (that packet lost),
	-- never right after another landing (validator round 7: a landing claimed every packet ran the quay at 112 to 296
	-- st/s, each one a fresh governor). The floor is not asked of the spot itself (riverFall's own), only of a walk on
	local entryX, entryY, entryZ, quayExact = nil, nil, nil, nil
	if not next.routeId and next.grounded and not actor.lastRiver then
		local _after: number? = nil
		entryX, entryY, entryZ, _after, quayExact = Recovery.riverEntry(
			{ x = prev.x, y = prev.y, z = prev.z, vy = prev.vy, onRail = prev.routeId ~= nil },
			next.x,
			next.y,
			next.z,
			math.clamp(dtEff, 0, SquirrelMotor.envelopeParams.maxDt),
			fastest,
			P.gravity,
			SquirrelMotor.envelopeParams.posSlack
		)
	end
	local riverLanding = entryX ~= nil
	if riverLanding then
		-- the quay spot is the new baseline; the move to it is the move into the water (the governor below)
		resync = true
		actor.resyncs += 1
		-- (the client's own recovery puts the body on the quay: the walls are judged from there on)
		actor.marks.wallX, actor.marks.wallY, actor.marks.wallZ, actor.marks.wallAt, actor.marks.wallClock =
			next.x, next.y, next.z, serverTime, next.clock
	elseif dt > SquirrelMotor.envelopeParams.maxDt then
		-- too long to judge move by move (a stall, a long loss burst): the new baseline, judged as a whole (gap())
		resync = true
		actor.resyncs += 1
		cornered = self:_gap(actorId, actor, prev, next, dtEff, serverTime, violations)
		creep(self.world, actor.marks, prev, next, violations, serverTime, SquirrelMotor.runCap(boosted))
	elseif dt <= 0 then
		table.insert(violations, { code = "clock", severity = 1, detail = `clock went back by {-dt} s` })
	else
		local found, launchUsed, pounceAgo, judged =
			SquirrelMotor.envelope(prev, next, dt, self.world, boosted, actor.marks.lastGrab)
		if judged.grab then
			actor.marks.lastGrab = judged.grab
		end
		launched = launchUsed
		for _, v in found do
			table.insert(violations, v)
		end
		keepVy, keepXZ, landed = judged.vy, judged.xz, judged.landed
		charge = judged.charge
		if judged.y then
			-- (a plain arc: the baseline no higher than the arc, whatever slack the packet took)
			next.y = judged.y :: number
		end
		if judged.longWall then
			-- a line too long for the short wall test went through a wall: weighed as a gap's (one may be a corner). A
			-- way round a corner clear (judged.cornered: validator round 10) is a third whatever the count, the doubt E
			-- keeps from the held place (the round-9 review: an honest body running close round a house through loss
			-- bursts was snapped for its second gap in WALL_GAP_WINDOW); one too long to tell, the second a whole flag
			local n = if judged.cornered then #actor.marks.wallGaps else self:wallGap(actorId, serverTime)
			cornered = judged.cornered == true
			table.insert(violations, {
				code = "wall",
				severity = if n >= 2 and not judged.cornered then 1 else 0.34,
				detail = `a {dt} s move's straight line goes through a wall ({n} in {MoveValidator.C.WALL_GAP_WINDOW} s{if judged.cornered
					then ", a way round a corner"
					else ""})`,
			})
		end
		creep(self.world, actor.marks, prev, next, violations, serverTime, SquirrelMotor.runCap(boosted))
		-- the pounce rate: the motor pounces only once its cooldown is over, wherever the body is and however long the gap
		-- (the window dates each launch exactly)
		if pounceAgo then
			local at = next.clock - pounceAgo
			local lastPounce = actor.lastPounce
			if lastPounce and at - lastPounce < SquirrelMotor.envelopeParams.pounceMinInterval then
				table.insert(
					violations,
					{ code = "launch", severity = 1, detail = `two pounces {at - lastPounce} s apart` }
				)
			end
			actor.lastPounce = at
			pounceAt = at
		end
	end
	-- (the speeds kept: a plain arc's baseline falls as gravity says, not as the packet claims within the slack)
	next.vy = keepVy
	local hxz = math.sqrt(next.vx * next.vx + next.vz * next.vz)
	if hxz > keepXZ then
		local k = if hxz > 0 then keepXZ / hxz else 0
		next.vx, next.vz = next.vx * k, next.vz * k
	end

	self:_stamina(
		actor,
		prev,
		next,
		dt,
		dtEff,
		serverTime,
		resync or dt > SquirrelMotor.envelopeParams.maxDt,
		boosted or riverLanding,
		landed,
		charge,
		violations
	)

	-- floors: a grounded body off the rails stands on a floor just under its feet (world.floorNear), never on air a
	-- slack at a time (the round-3 review: a body crept up posSlack a packet to FLOOR_DEPTH over the floor; round 5: one
	-- walked on level off a ledge): a whole flag, a third on a car's roof the client draws a little behind the server's
	local floorBelow = self.world.floorBelow
	local standY = actor.standY
	if next.routeId then
		actor.standY = nil
	elseif next.grounded then
		actor.standY = next.y
	end
	local onBed = floorBelow ~= nil
		and next.grounded
		and Trampoline.bedAt(self.world.trampolines or {}, next.x, next.z, next.y) ~= nil
	if floorBelow and next.grounded and not next.routeId and not (riverLanding and quayExact) and not onBed then
		local floorNear = self.world.floorNear
		-- (validator round 6, the round-5 review's LOW: a level packet was held only to floorBelow, FLOOR_DEPTH, so from
		-- a ledge a body walked on level over open ground: every grounded packet off the rails stands on a floor just
		-- under its feet, the motor's ground glue keeping the feet on it)
		local unknown = resync or standY == nil
		local rose = not unknown and next.y > (standY :: number) + 1e-3
		if floorNear then
			if not floorNear(next.x, next.y, next.z) then
				-- (a car's roof the client draws a little behind or off the server's box, on a slope or a bump: a third)
				local carFloor = self.world.carFloor
				local onCar = carFloor ~= nil and carFloor(next.x, next.y, next.z)
				actor.standY = nil -- (never a height it floated at: the next packet is judged the same way)
				table.insert(violations, {
					code = if rose then "climb" else "float",
					severity = if onCar then 0.34 else 1,
					detail = if rose
						then `rose {next.y - (standY :: number)} st on the ground with no floor just under the feet`
						else "grounded with no floor just under the feet",
				})
			end
		elseif not floorBelow(next.x, next.y, next.z) then
			table.insert(violations, { code = "float", severity = 0.34, detail = "grounded with nothing underfoot" })
		end
	end

	-- slabs (validator round 8, the round-7 review's MEDIUM): no move through a floor, a roof or a ceiling, nor ending
	-- inside one (ValidatorWorld.slab: one ray, only for a move that rose or fell); off the rails (a rail's own parts, a
	-- bough's cylinder round its centreline, are the route's) and away from a trampoline's bed
	if MoveValidator.throughSlab(self.world, prev, next, standY) and not riverLanding then
		table.insert(violations, {
			code = "slab",
			severity = 1,
			detail = `went from {prev.y} to {next.y} st through a floor, a roof or a ceiling`,
		})
	end

	-- the displacement governor over every window of accepted places (invariant B: whatever path the packet took). The
	-- client's own river recovery: the move judged is the move into the water (to the entry point), the riverFall jump
	-- from there to the quay carried by the whole history (shift: kept, never started afresh, invariant C)
	if riverLanding then
		local qx, qy, qz = Recovery.riverFall(entryX :: number, entryY :: number, entryZ :: number)
		if qx and qy and qz then
			MoveValidator.shift(
				self,
				actorId,
				qx - (entryX :: number),
				qy - (entryY :: number),
				qz - (entryZ :: number)
			)
		end
	end
	-- (the clock check's swing for the governor's windows: never the ping-widened one, the base slack at most; validator
	-- round 7: a clock run ahead by an inflated ping's swing bought 42.7 st on top of the one-off)
	MoveValidator._govern(
		self,
		actorId,
		actor.marks,
		next,
		dtEff,
		serverTime,
		math.min(swing, self.clockSlack),
		violations
	)

	local ok = #violations == 0
	for _, v in violations do
		actor.bucket += v.severity
	end
	actor.violations += #violations
	local flagged = actor.bucket >= self.flagThreshold
	if flagged and not actor.flagged then
		actor.flaggedAt = serverTime
	end
	actor.flagged = flagged

	local correction: Snapshot? = nil
	if flagged and not ok then
		-- log-only until W7: the correction is offered, the baseline still advances so a cheater does not
		-- accumulate a growing gap (the service decides whether to enforce)
		correction = SquirrelMotor.serialize(prev)
	end
	actor.last = next
	actor.lastLanded = landed
	actor.lastRiver = riverLanding
	actor.lastAcceptedAt = serverTime
	actor.lastOffset = offset
	record(actor.history, next.clock, next.x, next.y, next.z)
	local v = verdict(ok, true, violations, flagged, actor.bucket, correction, resync, false)
	v.launched = launched
	v.pounce = pounceAt
	v.pounceGap = if pounceAt then dt else nil
	v.river = riverLanding or nil
	-- (validator round 10, invariant E's chain: the packet's only doubts are a gap too long to judge move by move and a
	-- wall third a way round a corner explains, judged from the last packet, both ends off the rails: the place it stands
	-- for is reached from that one, MovementService.packet)
	local only = true
	for _, x in violations do
		only = only and x.code == "wall" and cornered
	end
	v.cornered = only and prev.routeId == nil and next.routeId == nil and (resync or cornered) and not riverLanding
	return v
end

local function prune(times: { number }, now: number, window: number)
	while #times > 0 and now - times[1] > window do
		table.remove(times, 1)
	end
end

-- The bounds a move judged as a whole shares with the server's own view of the root (Movement/MovementService.watch):
-- leapRise(): how high a leap rises (with its tolerance);
-- apexAllowance(): how high over a floor a leap (with a landing's step and a margin) can put the feet; leapUpAllowance(): the fastest an honest body rises (st/s);
-- gravity(); nearTrampoline(world, x, z, margin): a trampoline's bed within `margin` (it bounces higher than a leap).
function MoveValidator.leapRise(): number
	local E = SquirrelMotor.envelopeParams
	return SquirrelMotor.leapApex() * E.launchTol * E.launchTol
end

function MoveValidator.apexAllowance(): number
	return MoveValidator.leapRise() + Units.st(1.4) + 2
end

function MoveValidator.leapUpAllowance(): number
	return SquirrelMotor.params.leapUp * SquirrelMotor.envelopeParams.launchTol
end

function MoveValidator.gravity(): number
	return SquirrelMotor.params.gravity
end

function MoveValidator.nearTrampoline(world: World, x: number, z: number, margin: number): boolean
	for _, site in world.trampolines or {} do
		if math.sqrt((x - site.x) ^ 2 + (z - site.z) ^ 2) <= Trampoline.C.radius + margin then
			return true
		end
	end
	return false
end

-- throughSlab(world, from, next) -> boolean: the move from `from` to `next` went through a floor, a roof or a ceiling
-- (world.slab; `standY`: the height it last stood at, for a long slanting fall), neither end by a trampoline's bed. Both
-- ends off the rails: world.slab. One end on a rail (validator round 10, the round-9 review's MEDIUM: such a move was
-- never judged, so a drop off a bridge over a house with its packets held back landed in the sealed storey under it):
-- world.railSlab at the off-rail end's column, from just over its feet to C.RAIL_CLEAR under the rail. Both on rails:
-- the rails' own (the envelope's transfers).
function MoveValidator.throughSlab(
	world: World,
	from: { x: number, y: number, z: number, routeId: number? },
	next: State,
	standY: number?
): boolean
	local slab = (world :: any).slab
	if
		slab == nil
		or MoveValidator.nearTrampoline(world, next.x, next.z, 2)
		or MoveValidator.nearTrampoline(world, from.x, from.z, 2)
	then
		return false
	end
	local fromRail, nextRail = from.routeId ~= nil, next.routeId ~= nil
	if not fromRail and not nextRail then
		return slab(from.x, from.y, from.z, next.x, next.y, next.z, standY)
	end
	local railSlab = (world :: any).railSlab
	if railSlab == nil or (fromRail and nextRail) then
		return false
	end
	if fromRail then
		return railSlab(next.x, next.y, next.z, from.x, from.y, from.z)
	end
	return railSlab(from.x, from.y, from.z, next.x, next.y, next.z)
end

-- riseFrom(fromY, toY, rise) -> number: the rise over the higher end that puts a line's high rays a leap over its START
-- (validator round 10, the round-9 review's MEDIUM: a line was given the higher end's height plus a whole leap's rise,
-- so a low end on the ground outside and a high end mid-leap inside cleared a 17-st wall): a climbing line rises a leap
-- over its low end, a descending one over its high end, as a body that leapt from where it was
local function riseFrom(fromY: number, toY: number, rise: number): number
	return math.max(0, fromY + rise - math.max(fromY, toY))
end

-- creep(world, marks, prev?, next, violations, serverTime, pace): every move's walls judged again from where the body
-- was last clear of them (marks.wallX..: the anchor), once that line is a chord. Validator round 9: a move shorter than a
-- chord was judged by no wall test, so a creep of under 0.05 st a packet, and the first packet after a snap or a
-- hand-off, crossed walls unjudged. Round 10: the anchor moves only to a packet whose CENTRE line from it is clear
-- (world.crossesCenter; the round-9 review's face case, and more: a move whose side ray alone missed a wall, a packet a
-- little way into a wall obliquely, is no crossing for the lenient test, and every ray of the next move starts inside
-- the wall, where the engine's ray meets nothing: two oblique packets walked through a 1-st wall). A centre line from the
-- anchor through a wall is a wall, unless a way round no longer than the run since explains it (world.around: a
-- corner the chord between two packets clipped; then the anchor moves on): an honest body's centre never goes through a
-- wall (the client's narrow probe keeps it 0.35 off one). Off the rails (a rail's line is the route's: the anchor moves
-- to it); never past a wall the packet went through
function creep(
	world: World,
	marks: Marks,
	prev: State?,
	next: State,
	violations: { Violation },
	serverTime: number,
	pace: number
)
	-- (never past a wall the packet went through: the anchor stays on the near side, a snap's target with it)
	for _, v in violations do
		if v.code == "wall" or v.code == "slab" then
			return
		end
	end
	local center = world.crossesCenter
	if marks.wallX == nil and prev and prev.routeId == nil then
		-- (no anchor yet, a validator no service anchored: from the baseline)
		marks.wallX, marks.wallY, marks.wallZ, marks.wallAt, marks.wallClock =
			prev.x, prev.y, prev.z, serverTime, prev.clock
	end
	local wx, wy, wz = marks.wallX, marks.wallY, marks.wallZ
	if
		center == nil
		or next.routeId ~= nil
		or (prev and prev.routeId ~= nil)
		or wx == nil
		or wy == nil
		or wz == nil
	then
		marks.wallX, marks.wallY, marks.wallZ, marks.wallAt, marks.wallClock =
			next.x, next.y, next.z, serverTime, next.clock
		return
	end
	local far = math.sqrt((next.x - wx) ^ 2 + (next.z - wz) ^ 2)
	if far < MIN_CHORD then
		return
	end
	local lo, hi = math.min(wy, next.y), math.max(wy, next.y)
	-- (over the line's start by a leap only for a move in the air: a creep on the ground clears nothing over its top)
	local leap = if next.grounded and (prev == nil or prev.grounded) then 0 else MoveValidator.leapRise()
	local rise = riseFrom(wy, next.y, leap)
	if not center(wx, wz, next.x, next.z, lo, hi, rise, next.y) then
		marks.wallX, marks.wallY, marks.wallZ, marks.wallAt, marks.wallClock =
			next.x, next.y, next.z, serverTime, next.clock
		return
	end
	local round = world.around
	-- (the packets' own clocks since the anchor, never more than the server's arrivals and an arrival's jitter allow)
	local since = math.max(
		0,
		math.min(
			next.clock - (marks.wallClock or next.clock),
			serverTime - (marks.wallAt or serverTime) + MoveValidator.C.CREEP_JITTER
		)
	)
	local path = pace * since + 1 + 2 * SquirrelMotor.envelopeParams.posSlack
	if round ~= nil and far <= (world.aroundMax or 0) and round(wx, wz, next.x, next.z, lo, hi, rise, next.y, path) then
		marks.wallX, marks.wallY, marks.wallZ, marks.wallAt, marks.wallClock =
			next.x, next.y, next.z, serverTime, next.clock
		return
	end
	table.insert(violations, {
		code = "wall",
		severity = 1,
		detail = "the centre line from where the body was last clear of walls crosses a wall collider",
	})
end

local function marksOf(self: MoveValidator, actorId: any): Marks
	local marks = self._marks[actorId]
	if marks == nil then
		marks = { offsets = {}, runs = {}, gaps = {}, wallGaps = {}, stamina = 1, staminaAt = 0 }
		self._marks[actorId] = marks
	end
	return marks :: Marks
end

-- railAbove(index, x, y, z, r, minY): a rail sample within `r` of the point no lower than minY (the rail a body high
-- up left, or the one it is on). The scan is bounded by the index (C.RAIL_REACH_MAX).
local function railAbove(index: any, x: number, y: number, z: number, r: number, minY: number): boolean
	if index == nil then
		return false
	end
	local found = false
	local r2 = r * r
	index:forEachNear(
		x,
		y,
		z,
		math.ceil(r / (index.cellSize or 20)),
		function(_id: number, _t: number, sx: number, sy: number, sz: number): boolean?
			if sy >= minY and (sx - x) ^ 2 + (sy - y) ^ 2 + (sz - z) ^ 2 <= r2 then
				found = true
				return true
			end
			return nil
		end
	)
	return found
end

-- nearRoute(index, id, x, y, z): route `id` runs within C.ROUTE_NEAR of the point (a route id a packet claims is a rail
-- only there)
local function nearRoute(index: any, id: any, x: number, y: number, z: number): boolean
	return type(id) == "number"
		and index ~= nil
		and index:nearestOnRoute(id, x, y, z, MoveValidator.C.ROUTE_NEAR) ~= nil
end

-- onRails(index, from, next, along): the straight line from `from` to `next` is on the rails (hop): an end near the
-- route it claims, or with `along` (a gate), the route NEXT claims near both ends (the body put there got on it or ran
-- along it; validator round 10, the round-9 review's MEDIUM: a gate on a trunk let an off-rail first packet within
-- C.ROUTE_NEAR of the trunk, inside a closed room, through with no wall test)
local function onRails(index: any, from: any, next: any, along: boolean): boolean
	if not along then
		return nearRoute(index, next.routeId, next.x, next.y, next.z)
			or nearRoute(index, from.routeId, from.x, from.y, from.z)
	end
	local id = next.routeId
	return id ~= nil and nearRoute(index, id, from.x, from.y, from.z) and nearRoute(index, id, next.x, next.y, next.z)
end

-- hop(actorId, from, next, dt, serverTime, along?) -> (violations, cornered): a move judged as a whole, not tick by tick, over `dt` (the
-- time it can stand for): a gap too long for the envelope (gap()), and the first packet after a move the server
-- made, from where it put the body (MovementService's gate). `from` holds x, y, z and routeId (nil: off the rails).
--   * reach: no further than the fastest the squirrel goes in that time (arithmetic only: a long gap costs nothing);
--   * climb: no higher than a leap (and a landing's step) above where it was, unless a rail near where it now is
--     (within its reach, never more than C.RAIL_REACH_MAX) runs as high as that less a leap (it climbed and leapt from
--     it, or is on it), or a trampoline bounced it;
--   * the air (and a body on a rail): no higher above a floor than a leap, unless such a rail or a trampoline explains it;
--   * walls: the straight line, chord by chord (world.crossesLong, its chords bounded), only when within reach (a
--     longer one is a teleport already), its high rays a leap over its start (riseFrom); an honest body may have gone
--     round a corner: a way round no longer than the reach clear (world.around) is a third of a flag, none a whole one,
--     and a line too long to tell a third, the second inside C.WALL_GAP_WINDOW a whole one. A line on the rails is not
--     judged for walls, and a route id is only a rail where that route runs (within C.ROUTE_NEAR: a made-up or far one
--     is no rail): for a gap, an end on the rail it claims; for a gate (`along`), the route the first packet claims near
--     both ends (validator round 10).
-- Returns the violations and whether a crossing was explained by a way round (`cornered`: MovementService's chain).
-- Its cost is bounded whatever dt and the packet hold: the rail scans by C.RAIL_REACH_MAX, the walls by the chords.
function MoveValidator.hop(
	self: MoveValidator,
	actorId: any,
	from: { x: number, y: number, z: number, routeId: number? },
	next: State,
	dt: number,
	serverTime: number,
	along: boolean?
): ({ Violation }, boolean)
	local violations: { Violation } = {}
	local explained = false -- (a wall crossed, and a way round a corner clear)
	local E = SquirrelMotor.envelopeParams
	local world = self.world
	local fastest = self:fastest(actorId)
	local airGrab = Motion.C.airGrab
	local reach = fastest * math.max(dt, 0) + airGrab + 2
	local near = math.min(reach, MoveValidator.C.RAIL_REACH_MAX)
	local moved = math.sqrt((next.x - from.x) ^ 2 + (next.z - from.z) ^ 2)
	if moved > reach then
		table.insert(violations, {
			code = "teleport",
			severity = 1,
			detail = `moved {moved} st in a {dt} s gap (reach {reach})`,
		})
	end
	local apex = SquirrelMotor.leapApex() * E.launchTol * E.launchTol
	local bounce = 0
	local tramps = world.trampolines
	if tramps then
		for _, site in tramps do
			local r = Trampoline.C.radius + near
			if
				math.sqrt((from.x - site.x) ^ 2 + (from.z - site.z) ^ 2) <= r
				or math.sqrt((next.x - site.x) ^ 2 + (next.z - site.z) ^ 2) <= r
			then
				local vy = (Trampoline.C.baseVy + Trampoline.C.maxCount * Trampoline.C.perBounceVy) * E.launchTol
				bounce = vy * vy / (2 * SquirrelMotor.params.gravity)
				break
			end
		end
	end
	local lift = math.max(apex, bounce) + Units.st(1.4) + 2
	local railUp: boolean? = nil -- (asked once, when needed)
	local function railHigh(): boolean
		if railUp == nil then
			railUp = railAbove(world.index, next.x, next.y, next.z, near, next.y - lift)
		end
		return railUp :: boolean
	end
	local rise = next.y - from.y
	if rise > lift and not railHigh() then
		table.insert(violations, {
			code = "climb",
			severity = 1,
			detail = `rose {rise} st in a {dt} s gap (a leap {lift}, no rail near as high)`,
		})
	end
	local landable = world.landable
	if landable and (not next.grounded or next.routeId ~= nil) and bounce == 0 and rise <= lift then
		if not landable(next.x, next.y, next.z, lift) and not railHigh() then
			table.insert(violations, {
				code = "fly",
				severity = 1,
				detail = `higher than a leap over any floor after a {dt} s gap, no rail near as high`,
			})
		end
	end
	if MoveValidator.throughSlab(world, from, next) then
		table.insert(violations, {
			code = "slab",
			severity = 1,
			detail = `went from {from.y} to {next.y} st through a floor, a roof or a ceiling in a {dt} s gap`,
		})
	end
	local crossesLong = world.crossesLong
	if
		crossesLong
		and moved <= reach
		and not onRails(world.index, from, next, along == true)
		and crossesLong(
			from.x,
			from.z,
			next.x,
			next.z,
			math.min(from.y, next.y),
			math.max(from.y, next.y),
			riseFrom(from.y, next.y, apex),
			next.y
		)
	then
		-- (validator round 9: a third only when a corner rounded unseen explains it, world.around; else a whole flag)
		local round = world.around
		local cornered = round == nil
			or round(
				from.x,
				from.z,
				next.x,
				next.z,
				math.min(from.y, next.y),
				math.max(from.y, next.y),
				riseFrom(from.y, next.y, apex),
				next.y,
				-- (no way round longer than a run covers in the gap: a leap goes straight)
				SquirrelMotor.runCap(self.boostOf(actorId)) * math.max(dt, 0) + 1 + 2 * E.posSlack
			)
		-- (validator round 10: a way round a corner clear is a third whatever the count; a line too long to tell, the
		-- second in C.WALL_GAP_WINDOW a whole flag)
		local far = round == nil or moved > (world.aroundMax or 0)
		explained = cornered and not far
		local n = if explained then #marksOf(self, actorId).wallGaps else self:wallGap(actorId, serverTime)
		table.insert(violations, {
			code = "wall",
			severity = if (n >= 2 and far) or not cornered then 1 else 0.34,
			detail = `the straight line of a {dt} s gap goes through a wall ({n} in {MoveValidator.C.WALL_GAP_WINDOW} s{if not cornered
				then ", no way round a corner"
				elseif explained then ", a way round a corner"
				else ""})`,
		})
	end
	return violations, explained
end

-- reachable(from, next, path?) -> boolean: could a body have gone from `from` to `next` with no wall and no slab
-- between, by the line or a way round a corner (world.aroundFar) no longer than `path` (studs; nil: any)? (Invariant E, validator round 9: after a doubtful packet a clean
-- one becomes the held place only when the held place reaches it; the packets between were judged from the doubtful
-- one.) No more lenient than the envelope it stands in for (validator round 10, the round-9 review's MEDIUM): the line's
-- high rays a leap over its START (riseFrom), its centre line judged (crossesCenter: a chord's side ray that misses a
-- wall is no way through), both legs of a way round asked with the cover over their far ends, and no rail rule (a held place on a rail reaches an off-rail packet only by the wall test, as any line does). Pure (no wall
-- gap counted); its cost only after a doubtful packet: a slab ray or two, a line's chords, the corners only when the
-- line is through a wall
function MoveValidator.reachable(
	self: MoveValidator,
	from: { x: number, y: number, z: number, routeId: number? },
	next: State,
	path: number?
): boolean
	local world = self.world
	if MoveValidator.throughSlab(world, from, next) then
		return false
	end
	-- (the centre line, chord by chord: where the body's centre would have gone; a corner it clipped is a way round)
	local center = world.crossesCenter
	if center == nil then
		return true
	end
	local lo, hi = math.min(from.y, next.y), math.max(from.y, next.y)
	local rise = riseFrom(from.y, next.y, MoveValidator.leapRise())
	if not center(from.x, from.z, next.x, next.z, lo, hi, rise, next.y) then
		return true
	end
	-- (a way round a corner, for a line no longer than the world's AROUND_FAR: a longer one through a wall is none)
	local round = world.aroundFar
	local most = world.aroundFarMax or 16
	if round == nil or (next.x - from.x) ^ 2 + (next.z - from.z) ^ 2 > most * most then
		return false
	end
	return round(from.x, from.z, next.x, next.z, lo, hi, rise, next.y, path)
end

-- _stamina: the server's own sprint meter (the client's is its own feel, and a modified client keeps it full), on the
-- motor's own rules (SquirrelMotor.params: sprintSeconds, sprintRefill, leapCost, pounceCost, leapForwardWinded):
--   * Drain. Faster on the ground than a walk can explain (C.STAMINA_WALK times the walk) between two packets off the
--     rails drains it as the motor's sprint does (a full meter is sprintSeconds). On the ground: grounded, or a packet
--     that says it is in the air but is within C.STAMINA_GROUND of a floor with hardly a vertical speed (a client
--     flipping its grounded flag to hide a sprint).
--   * Launches (validator round 11, the round-10 review's HIGH: a client that kept its own meter full hopped at 35 st/s
--     for good): a leap off the ground costs leapCost, a pounce anywhere off a rail pounceCost (the envelope's
--     judged.charge); off a rail or a trampoline's bed both are free. A launch made with the meter empty (at
--     -C.STAMINA_SLACK) is a winded one, which the motor carries no faster than leapForwardWinded: the launch, and every
--     packet of its flight until it lands, faster than that is a sprint on credit.
--   * A pounce's lunge runs on along the ground, unsteered, for the motor's pounceWindow: paid with pounceCost, so the
--     ground packets inside it no faster than the lunge drain nothing.
--   * Refill, at the motor's rate (sprintRefill), only for a move whose ends are both on the ground or on a rail: never
--     in the air ("or a hop would pay for itself"). A ride, a stall or a respawn refill by the server's own time on the
--     first packet after (accept).
--   * The time a move stands for is the packets' own clocks (validator round 10): the client clock's gap, never more than
--     the clock check lets it stand for (dtEff).
--   * A gap too long to judge move by move (`unjudged`) that starts on the ground, whatever its end (validator round 11:
--     a sprint hidden in gaps that ended a moment into a hop drained nothing), pays the least the motor could have
--     covered its distance with: a sprint for what a walk does not cover, or a leap (leapCost) whose carry covers part
--     of it and a sprint for the rest. One as long as an honest loss burst (C.STAMINA_BURST) refills the rest of its
--     time when it ends on the ground; a longer one drains all its time when faster than a walk and never refills (a
--     client that hides its moves gets no credit for them). A gap inside a winded flight faster than a winded leap
--     carries is on credit as a whole.
-- The server's meter never drains where the client's does not, but for a landing's carry and a sprint's slowing down (a
-- moment faster than a walk with the key let go) and the moments on the ground of a packet that lands or launches (not
-- refilled), which C.STAMINA_SLACK covers. Below -C.STAMINA_SLACK the client is sprinting on credit: half a flag a
-- packet's worth of sprint (a gap's span, a whole one), and the meter held there. The chili rush (boostOf) runs faster
-- than a sprint and is left out, and so is the client's own river recovery.
function MoveValidator._stamina(
	self: MoveValidator,
	actor: Actor,
	prev: State,
	next: State,
	dt: number,
	dtEff: number,
	serverTime: number,
	unjudged: boolean,
	exempt: boolean,
	landed: boolean,
	charge: string?,
	violations: { Violation }
)
	local marks = actor.marks
	marks.staminaAt = serverTime
	local P = SquirrelMotor.params
	local E = SquirrelMotor.envelopeParams
	local C = MoveValidator.C
	local landable = self.world.landable
	-- (a packet whose landing the gap hid, `hidden`, came down on a floor and walked off its edge: on the ground; every
	-- vertical speed here is the validator's own)
	local function onGround(s: State, hidden: boolean): boolean
		return s.routeId == nil
			and (
				s.grounded
				or hidden
				or (math.abs(s.vy) < C.STAMINA_AIR_VY and landable ~= nil and landable(s.x, s.y, s.z, C.STAMINA_GROUND))
			)
	end
	local function onCredit(sprinted: number, why: string)
		if marks.stamina < -C.STAMINA_SLACK then
			marks.stamina = -C.STAMINA_SLACK
			table.insert(violations, {
				code = "stamina",
				-- (half a flag a packet's worth of sprint on credit: a gap's whole span is a whole flag)
				severity = math.min(1, 0.5 * sprinted / SquirrelWire.SEND_EVERY),
				detail = why,
			})
		end
	end
	local span = math.min(math.max(dt, 0), math.max(dtEff, 0))
	local groundA = onGround(prev, actor.lastLanded)
	local groundB = onGround(next, landed)
	local footB = groundB or next.routeId ~= nil
	-- launches: the motor's leapCost / pounceCost; a winded one (the meter empty before it) carries at a walk
	if charge ~= nil and not exempt then
		local tired = marks.stamina <= -C.STAMINA_SLACK + 1e-6
		marks.stamina -= if charge == "pounce" then P.pounceCost else P.leapCost
		marks.stamina = math.max(marks.stamina, -C.STAMINA_SLACK)
		marks.tiredFlight = tired and not footB
		local hxz = math.sqrt(next.vx * next.vx + next.vz * next.vz)
		if tired and hxz > P.leapForwardWinded * E.launchTol then
			table.insert(violations, {
				code = "stamina",
				severity = 0.5,
				detail = `a {charge} at {hxz} st/s with the sprint meter empty (a winded one carries at a walk)`,
			})
		end
	elseif footB then
		marks.tiredFlight = nil
	end
	if span <= 1e-3 then
		return
	end
	local walk = P.walk * C.STAMINA_WALK
	local across = math.sqrt((next.x - prev.x) ^ 2 + (next.z - prev.z) ^ 2)
	local winded = P.leapForwardWinded * E.speedTol * span + E.posSlack
	local sprinted = 0
	if exempt then
		sprinted = 0
	elseif unjudged and groundA then
		-- (a gap from the ground, whatever its end)
		if across / span > walk then
			if span <= C.STAMINA_BURST then
				-- the least the motor covers it with: a sprint for what a walk does not, or a leap paid with leapCost
				-- whose carry (at most a leap's flight, at the leap's speed over a walk) covers part of it
				local over = across - walk * span
				local rate = math.max(P.sprint - walk, 1e-3)
				local flight = math.min(span, 2 * P.leapUp / P.gravity)
				local carry = math.max(0, P.leapForward * E.launchTol - walk) * flight
				local byLeap = P.leapCost * P.sprintSeconds + math.max(0, over - carry) / rate
				sprinted = math.clamp(math.min(over / rate, byLeap), 0, span)
			else
				sprinted = span
			end
		end
	elseif marks.tiredFlight and not groundA and (unjudged or not footB) and across > winded then
		-- a winded flight (a launch made with the meter empty), or a gap inside one: no faster across than a winded
		-- leap carries
		marks.stamina -= span / P.sprintSeconds
		onCredit(
			span,
			`{across} st in {span} s in the air ({if unjudged then "a gap" else "a packet"}) with the sprint meter empty`
		)
		return
	elseif not unjudged and groundA and groundB and across / span > walk then
		-- (a pounce's lunge runs on along the ground for its window, unsteered: paid with pounceCost, not the sprint)
		local pounced = actor.lastPounce
		local lunge = pounced ~= nil
			and prev.clock >= pounced - 1e-3
			and next.clock <= pounced + P.pounceWindow + 1e-3
			and across <= P.pounceSpeedFast * E.speedTol * span + E.posSlack
		sprinted = if lunge then 0 else span
	end
	marks.stamina -= sprinted / P.sprintSeconds
	onCredit(sprinted, "faster than a walk on the ground for longer than the sprint meter lasts")
	-- (the rest of the move's time refills, as the motor's does off the sprint, only on the ground or a rail; a gap longer
	-- than an honest loss burst never refills: a client hiding its moves gets no credit for them)
	local footA = groundA or prev.routeId ~= nil
	if footA and footB and not (unjudged and span > C.STAMINA_BURST) then
		marks.stamina = math.min(1, marks.stamina + math.max(0, span - sprinted) / P.sprintRefill)
	end
end

-- wallGap(actorId, now) -> n: a straight line too long to be sure of (a gap, a jump of the root) went through a wall;
-- how many inside C.WALL_GAP_WINDOW (one may be a corner rounded unseen; a second is a whole flag).
function MoveValidator.wallGap(self: MoveValidator, actorId: any, now: number): number
	local marks = marksOf(self, actorId)
	table.insert(marks.wallGaps, now)
	prune(marks.wallGaps, now, MoveValidator.C.WALL_GAP_WINDOW)
	return #marks.wallGaps
end

-- _gap: a gap too long to judge move by move (a stall, a loss burst, a client that sends sparsely on purpose): hop()
-- over `dt` (held to the server's own arrival gap), and how often: more than gapMax gaps inside gapWindow is a client
-- that hides its moves (an honest link loses a burst now and then).
function MoveValidator._gap(
	self: MoveValidator,
	actorId: any,
	actor: Actor,
	prev: State,
	next: State,
	dt: number,
	serverTime: number,
	violations: { Violation }
): boolean
	local marks = actor.marks
	table.insert(marks.gaps, serverTime)
	prune(marks.gaps, serverTime, self.gapWindow)
	if #marks.gaps > self.gapMax then
		table.insert(violations, {
			code = "gaps",
			severity = 1,
			detail = `{#marks.gaps} gaps too long to judge in {self.gapWindow} s`,
		})
	end
	local found, cornered = self:hop(actorId, prev, next, dt, serverTime)
	for _, v in found do
		table.insert(violations, v)
	end
	return cornered
end

-- pose(actorId, clock) -> x, y, z at a client clock within the last second (linear interpolation; the
-- rewind the arena and combat use). nil when unknown or older than the history.
function MoveValidator.pose(self: MoveValidator, actorId: any, clock: number): (number?, number?, number?)
	local actor = self._actors[actorId]
	if not actor then
		return nil, nil, nil
	end
	local h = actor.history
	if h.count == 0 then
		return nil, nil, nil
	end
	local newest = h.head
	if clock >= h.clock[newest] then
		return h.x[newest], h.y[newest], h.z[newest]
	end
	local i = newest
	for _ = 2, h.count do
		local j = ((i - 2) % HISTORY_SLOTS) + 1
		if h.clock[j] <= clock then
			local span = h.clock[i] - h.clock[j]
			local a = if span > 0 then (clock - h.clock[j]) / span else 0
			return h.x[j] + (h.x[i] - h.x[j]) * a, h.y[j] + (h.y[i] - h.y[j]) * a, h.z[j] + (h.z[i] - h.z[j]) * a
		end
		i = j
		if h.clock[newest] - h.clock[j] > self.historySeconds then
			break
		end
	end
	return nil, nil, nil
end

-- fastest(actorId): the most studs a second the squirrel can cover honestly (the sprint, a leap, the fastest rail of
-- the world with its own pace, with the chili rush if the server says it is on), with the envelope's tolerance.
local function fastestFor(self: MoveValidator, boosted: boolean): number
	local cached = self._fastest[boosted]
	if cached then
		return cached
	end
	local rail = SquirrelMotor.railCap(false, boosted)
	local reg = self.world.registry
	if reg then
		for _, r in reg:all() do
			rail = math.max(rail, SquirrelMotor.routeCap(r, boosted))
		end
	end
	local v = math.max(SquirrelMotor.groundCap(boosted), SquirrelMotor.launchCapXZ(boosted), rail)
		* SquirrelMotor.envelopeParams.speedTol
	self._fastest[boosted] = v
	return v
end

function MoveValidator.fastest(self: MoveValidator, actorId: any): number
	return fastestFor(self, self.boostOf(actorId))
end

-- The displacement governor (validator round 6, invariant B). Five review rounds each found a path the envelope's local
-- reasoning did not cover (an unchecked field, a packet that skipped section 1, a grab's reach along a rail). The
-- governor holds whatever path a packet took: over every window of up to C.GOV_WINDOW seconds of ACCEPTED places, the
-- straight horizontal distance and the net rise between its two ends may not exceed what an honest squirrel covers in
-- that time, from the motor's own constants (governorBounds), with a little slack. Each move between two packets adds
-- the time it stands for (the validator's dtEff: the client's clock gap, never more than the server's arrivals allow)
-- and the most it could honestly cover in it to running sums; a window's allowance is the difference of the sums,
-- never for more time than the server's own arrivals span and the clock check's swing, plus a one-off. A window that
-- breaks it is a whole flag ("governor"): the service snaps the body to its last clean packet, which kept within it.
-- Its history outlives a snap (anchor: back to the snap's target, the moves after it dropped), so a snap buys no new
-- allowance; a move the server makes itself (a teleport, a hand-off) starts it afresh.
export type GovBounds = {
	vh: number, -- studs/s across: the fastest any way of moving goes (fastest: sprint, a leap, the fastest rail)
	vhTramp: number, -- ... near a trampoline: with every bounce's push
	vRail: number, -- studs/s up near a rail: its climb, or a leap off it regrabbed (Space and E every second frame)
	vLedge: number, -- studs/s up anywhere else: a leap onto a ledge a step under its apex, and on again
	vTramp: number, -- studs/s up near a trampoline: the highest bounce's launch
	dh: number, -- studs across once per window: a grab's snap and the drawn pose's offset off the centreline
	dv: number, -- studs up once per window: a grab's snap, the drawn pose's lift, a landing's step and a fork's hop
}

-- railClimbOf(registry, boosted): the fastest any rail of the world carries a body up (studs/s): each route's cap times
-- its steepest rise per stud along it (16 chords), once per registry
local climbCache: { [any]: { [boolean]: number } } = setmetatable({}, { __mode = "k" }) :: any
local function railClimbOf(reg: any, boosted: boolean): number
	if reg == nil then
		return 0
	end
	local cache = climbCache[reg]
	if cache == nil then
		cache = {}
		climbCache[reg] = cache
	end
	local known = (cache :: { [boolean]: number })[boosted]
	if known then
		return known
	end
	local v = 0
	for _, r in reg:all() do
		local a = reg:pointAt(r, 0)
		local steep = 0
		for i = 1, 16 do
			local b = reg:pointAt(r, i / 16)
			local ds = math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2 + (b.z - a.z) ^ 2)
			if ds > 1e-6 then
				steep = math.max(steep, math.abs(b.y - a.y) / ds)
			end
			a = b
		end
		v = math.max(v, SquirrelMotor.routeCap(r, boosted) * steep)
	end
	(cache :: { [boolean]: number })[boosted] = v
	return v
end

-- governorBounds(boosted): the honest rates and one-offs the governor allows, from the motor's constants (derivation in
-- each field's comment; the slack: the envelope's own tolerances, speedTol on speeds, launchTol on launches, railTol on
-- rails, and posSlack twice per one-off)
function MoveValidator.governorBounds(self: MoveValidator, boosted: boolean): GovBounds
	local cached = self._govBounds[boosted]
	if cached then
		return cached
	end
	local P, E, MC = SquirrelMotor.params, SquirrelMotor.envelopeParams, Motion.C
	local launchUp = P.leapUp * E.launchTol
	local step = Units.st(1.4) -- (a landing's snap up onto a ledge: the envelope's step)
	local vh = fastestFor(self, boosted)
	local b: GovBounds = {
		vh = vh,
		vhTramp = vh + Trampoline.C.maxCount * Trampoline.C.push * E.launchTol,
		-- (a leap off a rail regrabbed, again and again: E and Space every second frame. A one-frame cycle rises less
		-- than half the index's sample spacing, so the regrab lands on the sample it left and the body climbs nothing
		-- (measured: 0.8 st in 3 s; every second frame 28.9 st/s); over a two-frame cycle gravity takes g * substep of the
		-- launch's speed on average)
		vRail = math.max(railClimbOf(self.world.registry, boosted) * E.railTol, launchUp - P.gravity * P.substep),
		-- (a leap rises its apex in leapUp / g; the ground probe takes the feet onto a ledge a step over them)
		vLedge = (MoveValidator.leapRise() + step) / (P.leapUp / P.gravity),
		vTramp = (Trampoline.C.baseVy + Trampoline.C.maxCount * Trampoline.C.perBounceVy) * E.launchTol,
		dh = MC.airGrab + MoveValidator.C.DRAWN_MAX + 2 * E.posSlack,
		dv = MC.airGrab
			+ math.max(MC.visualBranchLift, MC.visualLookoutLift)
			+ step
			+ MC.forkTakeForced
			+ 2 * E.posSlack,
	}
	self._govBounds[boosted] = b
	return b
end

local function newGov(x: number, y: number, z: number, serverTime: number, clock: number?, route: boolean): Gov
	local slots = MoveValidator.C.GOV_SLOTS
	local gov: Gov = {
		G = 0,
		S = serverTime,
		X = x,
		Y = y,
		Z = z,
		BH = 0,
		BV = 0,
		clock = clock,
		route = route,
		g = table.create(slots, 0),
		s = table.create(slots, 0),
		x = table.create(slots, 0),
		y = table.create(slots, 0),
		z = table.create(slots, 0),
		bh = table.create(slots, 0),
		bv = table.create(slots, 0),
		head = 1,
		count = 1,
	}
	gov.s[1], gov.x[1], gov.y[1], gov.z[1] = serverTime, x, y, z
	return gov
end

-- keep(gov): the newest place into the ring's newest slot. That slot is the newer place's to take until it lies
-- C.GOV_SPACING after the slot before it; then the next place opens a new one (the oldest is overwritten)
local function keep(gov: Gov)
	local slots = MoveValidator.C.GOV_SLOTS
	local i = gov.head
	if gov.count == 1 or gov.g[i] - gov.g[(i - 2) % slots + 1] >= MoveValidator.C.GOV_SPACING then
		i = i % slots + 1
		gov.head = i
		gov.count = math.min(gov.count + 1, slots)
	end
	gov.g[i], gov.s[i], gov.x[i], gov.y[i], gov.z[i], gov.bh[i], gov.bv[i] =
		gov.G, gov.S, gov.X, gov.Y, gov.Z, gov.BH, gov.BV
end

-- hasAnchor(actorId): the governor has a place to judge the next packet from
function MoveValidator.hasAnchor(self: MoveValidator, actorId: any): boolean
	local marks = self._marks[actorId]
	return marks ~= nil and marks.gov ~= nil
end

-- shift(actorId, dx, dy, dz): a jump the server allows without the body's own moves (the river's quay, a Reset to a safe
-- place, a body held and given back, a body taken back: invariant C) carries the whole history with it: every kept
-- place moves by the jump, so every window is judged as if the body had gone on from where it was. Nothing is cleared,
-- no allowance is added: the one-offs and the rates already spent stay spent.
function MoveValidator.shift(self: MoveValidator, actorId: any, dx: number, dy: number, dz: number)
	local marks = self._marks[actorId]
	local gov = if marks then marks.gov else nil
	if gov == nil then
		return
	end
	local g = gov :: Gov
	local slots = MoveValidator.C.GOV_SLOTS
	local i = g.head
	for _ = 1, g.count do
		g.x[i] += dx
		g.y[i] += dy
		g.z[i] += dz
		i = (i - 2) % slots + 1
	end
	g.X += dx
	g.Y += dy
	g.Z += dz
end

-- relocate(actorId, x, y, z, serverTime): the server moved the body to (x, y, z) (feet) itself, by a move the client
-- can ask for (a Reset, a hold given back, a body taken back, a minigame's knock): the history is kept and carried to
-- the new place (shift; the history its last driver left, forget, when it has none of its own), the time since the
-- last place passes with no allowance (the body was put there, it did not go), and the newest place is the new one.
-- With no history at all (a body no player has driven): a new one there, the server's own place.
function MoveValidator.relocate(self: MoveValidator, actorId: any, x: number, y: number, z: number, serverTime: number)
	local marks = marksOf(self, actorId)
	local parked = self._parked[actorId]
	if marks.gov == nil and parked then
		-- (the last driver's constraints, never its spare allowance: the meter no fuller than it left it, refilled from
		-- then by the server's own time; its gaps and wall gaps still counted)
		marks.gov = parked.gov
		if parked.stamina < marks.stamina or marks.staminaAt == 0 then
			marks.stamina, marks.staminaAt = parked.stamina, parked.staminaAt
		end
		for _, t in parked.gaps do
			table.insert(marks.gaps, t)
		end
		for _, t in parked.wallGaps do
			table.insert(marks.wallGaps, t)
		end
	end
	-- (where the server put the body: the walls are judged from here on; but the anchor the body's walls were last
	-- judged from, when the body was put back within a chord of it, a body handed over where it was let go: else a
	-- retake every 0.75 s would buy a creep's step unjudged)
	local wx, wz = marks.wallX, marks.wallZ
	if parked and marks.wallX == nil then
		wx, wz = parked.wallX, parked.wallZ
		marks.wallX, marks.wallY, marks.wallZ = parked.wallX, parked.wallY, parked.wallZ
	end
	if wx == nil or wz == nil or math.sqrt((x - wx) ^ 2 + (z - wz) ^ 2) >= MIN_CHORD then
		marks.wallX, marks.wallY, marks.wallZ, marks.wallAt, marks.wallClock = x, y, z, serverTime, nil
	end
	self._parked[actorId] = nil
	local gov = marks.gov
	if gov == nil then
		marks.gov = newGov(x, y, z, serverTime, nil, false)
		return
	end
	local g = gov :: Gov
	MoveValidator.shift(self, actorId, x - g.X, y - g.Y, z - g.Z)
	g.G += math.max(0, serverTime - g.S)
	g.S = math.max(g.S, serverTime)
	g.clock = nil
	g.route = false
	keep(g)
end

-- meterOf(actorId, serverTime) -> (stamina, winded): the sprint meter the next driver of a body starts with (validator
-- round 9, the round-8 review's LOW-MEDIUM: takeOver carries the last driver's meter, no fuller than it left it, but the
-- new driver's motor started full, so an honest player who took a body run winded, and sprinted, was snapped): the
-- server's own meter as the body's last driver left it (forget), refilled by the server's time since, as takeOver will
-- have it; full for a body no player drove. Possession's grant carries it (Actors/ActorsRuntime) and the client's motor
-- starts from it (Client/Controllers/Squirrel). Never below 0 (the motor's range); winded below the motor's
-- sprintRecover (the motor sprints again only from there: the meter it may spend is then the server's too)
function MoveValidator.meterOf(self: MoveValidator, actorId: any, serverTime: number): (number, boolean)
	local src: any = self._parked[actorId] or self._marks[actorId]
	if src == nil or src.staminaAt == nil or src.staminaAt == 0 then
		return 1, false
	end
	local P = SquirrelMotor.params
	local s = math.min(1, src.stamina + math.max(0, serverTime - src.staminaAt) / P.sprintRefill)
	return math.clamp(s, 0, 1), s < P.sprintRecover
end

-- takeOver(actorId, x, y, z, serverTime): a driver takes the body where the server has it (feet): the history its last
-- driver left (forget) carried there (relocate: the AI's moves in between are the server's own), else a new one there.
function MoveValidator.takeOver(self: MoveValidator, actorId: any, x: number, y: number, z: number, serverTime: number)
	MoveValidator.relocate(self, actorId, x, y, z, serverTime)
end

-- anchor(actorId, x, y, z, serverTime, keepUntil?): the server put the body at (x, y, z) (feet). keepUntil nil: a move it
-- made (a teleport, a hand-off's gate, the river's quay): the governor starts afresh there. keepUntil: a snap back to a
-- place the body held at that server time (its last clean packet, or the gate): the moves accepted after it are dropped
-- and the history before it kept, so a snap buys no new allowance.
function MoveValidator.anchor(
	self: MoveValidator,
	actorId: any,
	x: number,
	y: number,
	z: number,
	serverTime: number,
	keepUntil: number?
)
	local marks = marksOf(self, actorId)
	local gov = marks.gov
	if keepUntil == nil or gov == nil then
		marks.gov = newGov(x, y, z, serverTime, nil, false)
		return
	end
	local g = gov :: Gov
	local slots = MoveValidator.C.GOV_SLOTS
	-- (drop the kept places newer than keepUntil; the newest left is the history's end)
	while g.count > 1 and g.s[g.head] > keepUntil + 1e-9 do
		g.head = (g.head - 2) % slots + 1
		g.count -= 1
	end
	local i = g.head
	local B = self:governorBounds(self.boostOf(actorId))
	-- (from it to the target: what an honest body covers in the time between, the target being a place it held then)
	local span = math.max(0, keepUntil - g.s[i]) + MoveValidator.C.GOV_SPACING
	g.G = g.g[i] + math.max(0, serverTime - g.s[i])
	g.S = serverTime
	g.BH = g.bh[i] + B.vh * span
	g.BV = g.bv[i] + B.vRail * span
	g.X, g.Y, g.Z = x, y, z
	g.clock = nil
	g.route = false
	keep(g)
end

-- _govern(actorId, marks, next, tau, serverTime, swing, violations): the governor's judgement of an accepted packet
-- (above): `tau` the time its move stands for (dtEff), `swing` how far the client clock may lead the server's (the clock
-- check's). Cost: arithmetic over the ring (C.GOV_SLOTS at most), and one bounded rail query for a rising move off a rail.
function MoveValidator._govern(
	self: MoveValidator,
	actorId: any,
	marks: Marks,
	next: State,
	tau: number,
	serverTime: number,
	swing: number,
	violations: { Violation }
)
	local onRoute = next.routeId ~= nil
	local gov = marks.gov
	if gov == nil then
		-- (the very first packet of a validator no service anchored: the service always anchors first, invariant A)
		local g = newGov(next.x, next.y, next.z, serverTime, next.clock, onRoute)
		marks.gov = g
		return
	end
	local g = gov :: Gov
	local B = self:governorBounds(self.boostOf(actorId))
	local t = math.max(0, tau)
	local x, y, z = next.x, next.y, next.z
	-- (near a trampoline, near a rail: from the server's own last place, by what the gap's time covers, capped at
	-- C.GOV_NEAR_T of it; validator round 7: at 1 to 2 packets a second the uncapped radius was 39 to 62 st, almost
	-- anywhere in a wooded town)
	local tNear = math.min(t, MoveValidator.C.GOV_NEAR_T)
	local tramps = self.world.trampolines
	local tramp = tramps ~= nil
		and #tramps > 0
		and (
			MoveValidator.nearTrampoline(self.world, x, z, 2)
			or MoveValidator.nearTrampoline(self.world, g.X, g.Z, B.vh * tNear + 2)
		)
	local vv = 0
	if y > g.Y then
		-- (only a rising move earns rise: none is banked standing still)
		if tramp then
			vv = B.vTramp
		elseif onRoute or g.route then
			vv = B.vRail
		else
			local index = self.world.index
			local grab = Motion.C.airGrab + MoveValidator.C.DRAWN_MAX
			local near = index ~= nil
				and (
					index:nearest(x, y, z, grab) ~= nil
					or index:nearest(g.X, g.Y, g.Z, math.min(grab + B.vh * tNear, MoveValidator.C.RAIL_REACH_MAX))
						~= nil
				)
			vv = if near then B.vRail else B.vLedge
		end
	end
	local G, S = g.G + t, serverTime
	local BH = g.BH + (if tramp then B.vhTramp else B.vh) * t
	local BV = g.BV + vv * t
	local worstH, worstV, overH, overV = 0, 0, 0, 0
	local peak = marks.govPeak
	if peak == nil then
		peak = table.create(6, -math.huge)
		marks.govPeak = peak
	end
	local pk = peak :: { number }
	-- (every kept place C.GOV_WINDOW back, the newest slot being the last packet's: keep)
	local slots, window, dh, dv = MoveValidator.C.GOV_SLOTS, MoveValidator.C.GOV_WINDOW, B.dh, B.dv
	local gg, gs, gx, gy, gz, gbh, gbv = g.g, g.s, g.x, g.y, g.z, g.bh, g.bv
	local i = g.head
	for _ = 1, g.count do
		local tg = G - gg[i]
		if tg > window then
			break
		end
		local ts = S - gs[i] + swing
		-- (never more time than the server's own arrivals span, with the clock check's swing)
		local scale = if tg > ts and tg > 0 then math.max(0, ts) / tg else 1
		local dx, dz = x - gx[i], z - gz[i]
		local h = math.sqrt(dx * dx + dz * dz) - (scale * (BH - gbh[i]) + dh)
		local v = (y - gy[i]) - (scale * (BV - gbv[i]) + dv)
		local class = if tg <= 0.25 then 1 elseif tg <= 1 then 2 else 3
		if h > pk[class] then
			pk[class] = h
		end
		if v > pk[class + 3] then
			pk[class + 3] = v
		end
		if h > overH then
			overH, worstH = h, tg
		end
		if v > overV then
			overV, worstV = v, tg
		end
		i = (i - 2) % slots + 1
	end
	if overH > 0 then
		table.insert(violations, {
			code = "governor",
			severity = 1,
			detail = `{overH} st further across than an honest body goes in {worstH} s`,
		})
	end
	if overV > 0 then
		table.insert(violations, {
			code = "governor",
			severity = 1,
			detail = `{overV} st higher than an honest body rises in {worstV} s`,
		})
	end
	g.G, g.S, g.X, g.Y, g.Z, g.BH, g.BV = G, S, x, y, z, BH, BV
	g.clock = next.clock
	g.route = onRoute
	keep(g)
end

-- clearFlag(actorId): the service applied the correction; start a fresh bucket.
function MoveValidator.clearFlag(self: MoveValidator, actorId: any)
	local actor = self._actors[actorId]
	if actor then
		actor.bucket = 0
		actor.flagged = false
		actor.flaggedAt = nil
	end
end

function MoveValidator.isFlagged(self: MoveValidator, actorId: any): boolean
	local actor = self._actors[actorId]
	return actor ~= nil and actor.flagged
end

function MoveValidator.last(self: MoveValidator, actorId: any): State?
	local actor = self._actors[actorId]
	return if actor then actor.last else nil
end

-- governorPeak(actorId) -> { number }?: the governor's closest calls so far (studs over its allowance; below 0 within
-- it): across in windows of up to 0.25 s, 1 s and 3 s, then up in the same three
function MoveValidator.governorPeak(self: MoveValidator, actorId: any): { number }?
	local marks = self._marks[actorId]
	return if marks then marks.govPeak else nil
end

export type Stats = {
	packets: number,
	violations: number,
	drops: number,
	resyncs: number,
	bucket: number,
	flagged: boolean,
}

function MoveValidator.stats(self: MoveValidator, actorId: any): Stats?
	local actor = self._actors[actorId]
	if not actor then
		return nil
	end
	return {
		packets = actor.packets,
		violations = actor.violations,
		drops = actor.drops,
		resyncs = actor.resyncs,
		bucket = actor.bucket,
		flagged = actor.flagged,
	}
end

return MoveValidator
