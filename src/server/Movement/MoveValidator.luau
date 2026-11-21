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
--   * Round 11 (2026-11-20, the round-10 review): the sprint meter on the motor's rules (_stamina: a launch off the ground
--     charged, winded as the motor's, refilled only on the ground or a rail, a gap from the ground charged whatever its
--     end), railSlab's column up to the rail past the rails' own props, and a ray budget per actor for the ways round a
--     corner (budgeted).
--   * Round 12 (2026-11-20, the round-11 review): the meter and the air bound step the motor's own speed model
--     (SquirrelMotor.speedBound from the speed the server keeps, marks.speedU / speedS): a sprint slowing to a walk, a
--     landing's carry and a flight coasting from its launch drain nothing, the rest the least sprint the motor covers it
--     with; gaps from the air pay their flight's carry and any launch they hid; a flight past the sprint-steered step is a
--     "speed" violation; the rail rule's slab columns look past up to ValidatorWorld.C.RAIL_HOPS props, then fail closed.
--   * Round 13 (2026-11-20, the round-12 review), two rules for the meter and the speed kept: (P1) no allowance is sized or
--     skipped from a claim the server has not checked (a hidden relaunch is at least a substep old and charged; where a
--     fact is unknown, the honest-favourable bound, never a free one); (P2) a free flight is earned only by a rail launch
--     the server knows of (the envelope's judged.railLaunch, a packet on a rail, a rail at hand where a hidden launch
--     ends) and ends when its arc must have come down. A charge that takes the meter to its floor winds it before any
--     refill; a launch packet's time before its launch is judged as a move of its own.
--   * Round 14 (2026-11-20, the round-13 review), two structural rules for every rail credit (a free launch, a free flight,
--     rail-leap time, a refill as on a rail): (S1) given only where the server itself has the body on the rail: the last
--     accepted packet on it (its claim checked), the packet's own checked claim, or a grab the motor's own step from the
--     last accepted place explains (the envelope's grab search, up to SquirrelMotor.envelopeParams.grabSimDt); a rail
--     merely near earns nothing, and a gap's hidden time is charged as if no rail were there; (S2) charge first, credit
--     second: every hidden or claimed launch pays leapCost unless S1 holds, time credited as a flight is never refilled,
--     one carry per flight. A move with an end on a rail judges its off-rail leg as a move of its own (legOf).
--   * Round 15 (2026-11-20, the round-14 review): a move with both ends on a rail is the rail's pace only along one route
--     within its cap; any other leaves A, crosses and grabs B, its leg judged as the one-end move's (legOf). The grab search
--     reaches the longest honest packet (grabSimDt) at a bounded cost, and a launch it explains starts the air bound at
--     its first grab (judged.grabFrom). A ledge excuses no leap the body needed to get onto it; a leap onto a rail higher
--     than a grab from the ground is paid; a pounce off a rail flies as a pounce.

local Import = require("../Import")
local Motion = Import.shared("Routes/Motion") :: typeof(require("../../shared/Routes/Motion"))
local SquirrelMotor = Import.shared("Movement/SquirrelMotor") :: typeof(require("../../shared/Movement/SquirrelMotor"))
local Recovery = Import.shared("Movement/Recovery") :: typeof(require("../../shared/Movement/Recovery"))
local Trampoline = Import.shared("Movement/Trampoline") :: typeof(require("../../shared/Movement/Trampoline"))
local Units = Import.shared("Config/Units") :: typeof(require("../../shared/Config/Units"))
local Curve = Import.shared("Routes/Curve") :: typeof(require("../../shared/Routes/Curve"))
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
	-- the server's meter ran out (at -C.STAMINA_SLACK) and has not come back by the motor's sprintRecover since (_stamina:
	-- a launch now is a winded one); the last pounce was such a one
	winded: boolean?,
	tiredLunge: boolean?,
	-- the motor's speed as the server bounds it at the last packet (_stamina, validator round 12: SquirrelMotor.speedBound
	-- stepped over each move and gap): the most horizontal speed and moveSpeed the body can have; the client clock its
	-- pounce's window holds the speed until; its flight steers at v5.4's speeds (a launch off a rail or a bed: free). nil:
	-- unknown (a reset, a ride), taken at the most an honest body has there
	speedU: number?,
	speedS: number?,
	speedHold: number?,
	speedRail: boolean?,
	-- the free flight's launch (validator round 13): the client clock, the height and the vertical speed judged at the
	-- packet it was seen or dated at; its arc decides when the flight must have come down (_stamina's onArc)
	speedArcAt: number?,
	speedArcY: number?,
	speedArcVy: number?,
	-- (the route a free flight left, when the server had the body on it: a relaunch hidden in an air gap off that same
	-- route is the motor's free leap chain, validator round 15)
	speedRoute: number?,
	-- the air trick (owner D18; _stamina): a flight began since the last wiggle charged (the server saw the body on the
	-- ground or a rail, or a gap long enough to hide a landing), and since the last roll's carry (the server saw it in the
	-- air); the client clock of the last packet on its footing; the flight's reach out (SquirrelMotor.trickReachAt)
	-- (trickArmed nil: not yet known, a body the server has only just taken on, perhaps in a flight already: armed)
	trickArmed: boolean?,
	rollArmed: boolean?,
	footClock: number?,
	trickReach: number?,
	-- (owner D20) the burst the packets last dated was the flight's first by the server's count and pressed no sooner
	-- than trickBurstRest after the one before (burstAt: its press's client clock): it is the motor's (_stamina)
	trickBurst: boolean?,
	burstAt: number?,
	trickHidden: boolean?, -- (this packet's move needed a wiggle the gap hid: SquirrelMotor.Judged.trickHidden)
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
	-- the wall rays its ways round may still cast, and the server time that was counted at (budgeted; validator round 11)
	rays: number?,
	raysAt: number?,
}

-- What a body keeps of its last driver when no one drives it (forget), for the next (takeOver): the constraints, never
-- spare allowance (invariant C, validator round 8): the governor's history, the server's sprint meter (refilled by the
-- server's own time since), and the recent gaps and wall gaps
type Parked = {
	gov: Gov,
	stamina: number,
	staminaAt: number,
	-- (validator round 13, the round-12 review's LOW d: the meter's winded state and the speed kept, never a free flight)
	winded: boolean?,
	speedU: number?,
	speedS: number?,
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
	-- ... and how much sooner than the motor's sprintRecover over that floor the server's meter stops being winded (the
	-- moments on the ground of a packet that lands or launches, which the server does not refill)
	STAMINA_RECOVER_SLACK = 0.1,
	-- seconds: the longest gap the meter takes for an honest loss burst (the least sprint that covers it drains, the rest
	-- refills); a longer one drains all of its time when faster than a walk, and never refills (validator round 10)
	STAMINA_BURST = 1.2,
	-- how far over the motor's own speed step (SquirrelMotor.speedBound from the speed kept) a move may go before it needs
	-- the sprint: the motor's substeps of other lengths, rounding (validator round 12)
	STAMINA_STEP = 1.02,
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
	-- (validator round 13, the round-12 review's HIGH 1: a snap, a move the server made, end a free flight: P2)
	m.speedRail, m.speedArcAt, m.speedArcY, m.speedArcVy, m.speedRoute = nil, nil, nil, nil, nil
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
			winded = marks.winded,
			speedU = marks.speedU,
			speedS = marks.speedS,
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

-- accept(actorId, packet, serverTime) -> verdict. The first packet of an unknown actor is the baseline. (Its ways round a
-- corner within the actor's ray budget: budgeted)
function MoveValidator.accept(self: MoveValidator, actorId: any, packet: Packet, serverTime: number): Verdict
	return MoveValidator.budgeted(self, actorId, serverTime, function(): any
		return MoveValidator._accept(self, actorId, packet, serverTime)
	end)
end

function MoveValidator._accept(self: MoveValidator, actorId: any, packet: Packet, serverTime: number): Verdict
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
	local railLaunch: boolean? = nil -- (the launch is off a rail the envelope saw or a visit it explains: judged.railLaunch)
	-- (the first grab of the motor's own grab and leap that explain the launch: judged.grabFrom)
	local grabFrom: { clock: number, x: number, z: number, reach: number }? = nil
	local launchRoute: number? = nil -- (the route a free launch left: prev's, or the grab's)
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
	elseif dt > SquirrelMotor.envelopeParams.maxDt + SquirrelMotor.envelopeParams.dtEps then
		-- too long to judge move by move (a stall, a long loss burst): the new baseline, judged as a whole (gap())
		resync = true
		actor.resyncs += 1
		cornered = self:_gap(actorId, actor, prev, next, dtEff, serverTime, violations)
		creep(self.world, actor.marks, prev, next, violations, serverTime, SquirrelMotor.runCap(boosted))
	elseif dt <= 0 then
		table.insert(violations, { code = "clock", severity = 1, detail = `clock went back by {-dt} s` })
	else
		local found, launchUsed, pounceAgo, judged = SquirrelMotor.envelope(
			prev,
			next,
			dt,
			self.world,
			boosted,
			actor.marks.lastGrab,
			-- (`prev`'s flight is a leap off a rail the server knows of (a free flight on its arc): a grab in it is a
			-- chained grab-leap's, owner D19)
			actor.marks.speedRail == true and prev.routeId == nil and not prev.grounded
		)
		if judged.grab then
			actor.marks.lastGrab = judged.grab
		end
		launched = launchUsed
		for _, v in found do
			table.insert(violations, v)
		end
		keepVy, keepXZ, landed = judged.vy, judged.xz, judged.landed
		charge = judged.charge
		actor.marks.trickHidden = judged.trickHidden
		railLaunch = judged.railLaunch
		grabFrom = if railLaunch then judged.grabFrom else nil
		launchRoute = if railLaunch then prev.routeId or judged.grabRoute else nil
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
		resync or dt > SquirrelMotor.envelopeParams.maxDt + SquirrelMotor.envelopeParams.dtEps,
		boosted or riverLanding,
		landed,
		charge,
		launched,
		pounceAt,
		railLaunch,
		grabFrom,
		launchRoute,
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
-- world.railSlab at the off-rail end's column, from just over its feet up to the rail. Both on rails:
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

-- budgeted(actorId, now, fn) -> fn(): fn run with the actor's own ray budget for ways round a corner in the world's pool
-- (ValidatorWorld.around's `pool`; validator round 11, the round-10 review's LOW): refilled at the world's aroundBudget
-- (ValidatorWorld.C.AROUND_BUDGET) a second up to that much, kept in the actor's marks (a snap or a reset refills none).
-- accept() runs in it; so do MovementService's root path, gate hop and reachable. Not nested. Its clock only goes on.
function MoveValidator.budgeted(self: MoveValidator, actorId: any, now: number, fn: () -> any): any
	local pool = self.world.aroundPool
	if pool == nil then
		return fn()
	end
	local marks = marksOf(self, actorId)
	local most = self.world.aroundBudget or math.huge
	local left = if marks.rays == nil
		then most
		else math.min(most, (marks.rays :: number) + math.max(0, now - (marks.raysAt or now)) * most)
	local outer = pool.left
	pool.left = left
	local ok, result = pcall(fn)
	-- (the refill's clock never goes back: a caller's `now` older than the last refill, MovementService's packet time for
	-- the reach check, would refill that stretch twice; the round-13 review's nit)
	marks.rays, marks.raysAt = pool.left, math.max(now, marks.raysAt or now)
	pool.left = outer
	if not ok then
		error(result, 0)
	end
	return result
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

-- railWithin(index, x, z, reach, minY, maxY, ok?): a rail sample within `reach` across of the point at a height between
-- minY and maxY, and that `ok(id, sx, sy, sz)` takes (validator round 13: the rail a hidden launch left; round 14: only
-- the route the last accepted packet stood on, reached in time). The scan is bounded by the index (C.RAIL_REACH_MAX).
local function railWithin(
	index: any,
	x: number,
	z: number,
	reach: number,
	minY: number,
	maxY: number,
	ok: ((id: number, sx: number, sy: number, sz: number) -> boolean)?
): boolean
	if index == nil or maxY < minY then
		return false
	end
	local found = false
	local r2 = reach * reach
	index:forEachNear(
		x,
		(minY + maxY) / 2,
		z,
		math.ceil(math.max(reach, (maxY - minY) / 2) / (index.cellSize or 20)),
		function(id: number, _t: number, sx: number, sy: number, sz: number): boolean?
			if
				sy >= minY
				and sy <= maxY
				and (sx - x) ^ 2 + (sz - z) ^ 2 <= r2
				and (ok == nil or ok(id, sx, sy, sz))
			then
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
-- motor's own rules (SquirrelMotor.params: sprintSeconds, sprintRefill, leapCost, pounceCost, leapForwardWinded) and its
-- own speed step (validator round 12, the round-11 review: SquirrelMotor.speedBound, stepped by the server over each move
-- and each gap from the speed it keeps, marks.speedU / speedS):
--   * The speed kept. The most horizontal speed and moveSpeed the body can have, stepped with the walk as moveSpeed's goal
--     where the move needed no sprint and with the sprint where it did; a launch sets it to the launch's speed (the
--     envelope's cap, a winded one's no more than leapForwardWinded; a pounce's held for pounceWindow), a free launch
--     (off a rail the server knows of; a bounce keeps a free flight free) steers at v5.4's speeds as the motor's railLeap
--     does, until its arc from the launch must have come down (validator round 13: onArc).
--   * Drain: what the walk-steered step does not cover. On the ground a move longer than C.STAMINA_WALK times both a walk
--     and the walk-steered step from the speed kept (a landing's carry, a sprint slowing to a walk at speedSmooth: the
--     motor drains none of it) drains all its time, as the motor's sprint does (a full meter is sprintSeconds). In the
--     air, where the motor steers by accelAir and coasts by dragAir from the launch, the distance past the walk-steered
--     step drains the least sprint that covers it (the sprint steers no more than the sprint less the walk faster); past
--     the sprint-steered step it is a flight faster than the motor's (a "speed" violation). On the ground: grounded, or a
--     packet that says it is in the air but is within C.STAMINA_GROUND of a floor with hardly a vertical speed (a client
--     flipping its grounded flag to hide a sprint). A move that lands or walks off an edge is its two parts (the time
--     its arc takes to come down to where it ends).
--   * Launches (validator round 11): a leap off the ground costs leapCost, a pounce anywhere off a rail pounceCost (the
--     envelope's judged.charge); off a rail or a trampoline's bed both are free. A launch made while the meter is winded
--     (it ran out, at -C.STAMINA_SLACK, and has not come back by the motor's sprintRecover since, less
--     C.STAMINA_RECOVER_SLACK) carries no faster than leapForwardWinded: faster is a violation, and its flight steers at a
--     walk (more is a sprint on credit).
--   * A pounce's lunge runs on along the ground, unsteered, for the motor's pounceWindow: paid with pounceCost, so the
--     ground packets inside it no faster than the lunge drain nothing (a winded pounce's lunge is a walk: not exempt).
--   * Refill, at the motor's rate (sprintRefill), for the time on the ground or a rail not sprinting: a move whose ends are
--     both there, and the ground part of one that lands or launches (validator round 12; a launch packet's ground part is
--     judged as a ground move first, validator round 13); never in the air ("or a hop would pay for itself"). A charge or
--     a sprint that takes the meter to its floor winds it there, before any refill (validator round 13). A ride, a stall or a respawn refill by the server's own time on the first packet after.
--   * The time a move stands for is the packets' own clocks (validator round 10): the client clock's gap, never more than
--     the clock check lets it stand for (dtEff).
--   * A gap too long to judge move by move (`unjudged`) pays the least the motor could have covered its distance with,
--     the most favourable honest reading of what it hid: from the ground (validator round 11), a sprint for what the
--     walk-steered step does not cover, or a leap (leapCost) whose carry covers part of it and a sprint for the rest; from
--     the air (validator round 12, the round-11 review's HIGH), the flight in progress at its walk-steered carry until
--     its arc comes down to the gap's end, a walk after, the rest as from the ground. One as long as an honest loss burst
--     (C.STAMINA_BURST) refills the rest of its time on the ground; a longer one drains all of its time on the ground when
--     faster than that, and never refills (a client that hides its moves gets no credit for them).
--   * A move with an end on a rail (validator round 14): the rail's own pace, refilled; the off-rail end's distance from the
--     nearest point of the claimed route (less a grab onto it, or the drawn pose's offset off it) a move of its own in the
--     time the run along the route leaves: off the rail the body was on, one free leap off it and then the ground; onto a
--     rail, the flight in progress and then the ground; a launch a gap hid off a rail is free only off that same route,
--     reached in time (hiddenLaunch). No other gap takes a rail credit.
-- The server's meter never drains where the client's does not, but for rounding, which C.STAMINA_SLACK covers. Below
-- -C.STAMINA_SLACK the client is sprinting on credit: half a flag a packet's worth of sprint (a gap's span, a whole one),
-- and the meter held there. The chili rush (boostOf) runs faster than a sprint and is left out, and so is the client's
-- own river recovery.
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
	launched: boolean,
	pounceAt: number?,
	railLaunch: boolean?,
	grabFrom: { clock: number, x: number, z: number, reach: number }?,
	launchRoute: number?,
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
	-- (a charge or a sprint that takes the meter to its floor winds it there and then, before any refill the same packet
	-- brings, as the motor's doLeap and its sprint wind it at 0; validator round 13, the round-12 review's HIGH 2: a launch
	-- packet's ground refill lifted the meter a hair over its floor after each leapCost, and no leap was ever winded)
	local function spend(amount: number)
		marks.stamina -= amount
		if marks.stamina <= -C.STAMINA_SLACK + 1e-6 then
			marks.winded = true
		end
	end
	-- (winded once the meter is at its floor, until it is back by the motor's sprintRecover, less a little)
	local function settle()
		if marks.stamina <= -C.STAMINA_SLACK + 1e-6 then
			marks.winded = true
		elseif marks.stamina >= -C.STAMINA_SLACK + P.sprintRecover - C.STAMINA_RECOVER_SLACK then
			marks.winded = nil
		end
	end
	local span = math.min(math.max(dt, 0), math.max(dtEff, 0))
	local groundA = onGround(prev, actor.lastLanded)
	local groundB = onGround(next, landed)
	local railA, railB = prev.routeId ~= nil, next.routeId ~= nil
	local footA = groundA or railA
	local footB = groundB or railB
	local hxz = math.sqrt(next.vx * next.vx + next.vz * next.vz)
	-- launches: the motor's leapCost / pounceCost; a winded one (the meter empty before it) carries at a walk
	local tired = false
	if charge ~= nil and not exempt then
		tired = marks.winded == true or marks.stamina <= -C.STAMINA_SLACK + 1e-6
		spend(if charge == "pounce" then P.pounceCost else P.leapCost)
		marks.stamina = math.max(marks.stamina, -C.STAMINA_SLACK)
		if charge == "pounce" then
			marks.tiredLunge = tired
		end
		if tired and hxz > P.leapForwardWinded * E.launchTol then
			table.insert(violations, {
				code = "stamina",
				severity = 0.5,
				detail = `a {charge} at {hxz} st/s with the sprint meter empty (a winded one carries at a walk)`,
			})
		end
	end
	-- the air trick (owner D18), by the server's own footing (a flight: from a packet on the ground or a rail, or a gap
	-- long enough to hide a landing, to the next). A fresh wiggle claimed pays trickCost from a meter with any left, the
	-- client's own word on its meter aside; the first of a flight earns a reach out, the motor's rule on the server's
	-- numbers (trickReachAt: its time in the air no less than since the last footing seen; no landing known, so the
	-- timing's bound alone), the next of the same flight none. While a wiggle's re-aim is live the horizontal speed bound
	-- scales as the re-aim's reach changed, at that reach (the motor's aimScale; it telescopes, so a re-aim to and fro
	-- buys nothing). A fresh roll after a flight the server saw holds the speed (neither steered nor dragged) for the
	-- roll's length from its press, dated within the packet: the motor's carry along the ground
	-- The wiggle's burst (owner D20): a burst moves the body across by the motor's own numbers, the shift's part and the
	-- pop's carry over the move's time since the press, as the packets date it (SquirrelMotor.freshBurst: the packet's
	-- burstWait, the motor's rest, which only runs down; burstFrom, burstTo: seconds after the press, so the parts add
	-- up to one burst at most, whatever a gap hid of the flight it was pressed in); the move's distance is judged less
	-- that. Granted to the first burst of a flight (the wiggle's count) pressed no sooner than the motor's
	-- trickBurstRest after the last one granted; any other claimed earns nothing. (The motor gives none in a chained
	-- leap's flight either: the server, which does not date the chain, allows that one.)
	local trickScale, trickOut = 1, 1
	local burstFrom, burstTo = 0, 0
	if not exempt then
		local freshWiggle = SquirrelMotor.freshMove(prev, next, 2)
		local freshRoll = SquirrelMotor.freshMove(prev, next, 1)
		if unjudged then
			marks.trickArmed, marks.rollArmed = true, true
		end
		if launched or grabFrom then
			-- (a launch in the gap, off the ground, a rail or a grab the envelope explained: a new flight, begun after `prev`)
			marks.trickArmed = true
			marks.footClock = math.max(marks.footClock or -math.huge, prev.clock)
		end
		if marks.trickHidden then
			-- (a wiggle the gap hid, which the envelope needed: paid as one seen; that flight's reach is none)
			marks.trickHidden = nil
			if marks.stamina > 0 then
				spend(math.min(P.trickCost, marks.stamina))
			end
		end
		if freshWiggle then
			if marks.stamina > 0 then
				spend(math.min(P.trickCost, marks.stamina)) -- (the motor empties a meter, no further)
			end
			marks.trickReach = if marks.trickArmed ~= false
				then SquirrelMotor.trickReachAt(next.clock - (marks.footClock or -math.huge), 0, 0)
				else 0
		end
		-- (the burst: the flight's first, pressed no sooner than the motor's trickBurstRest after the last the server
		-- granted, by the packets' own dating of the press)
		local freshBurst = SquirrelMotor.freshBurst(prev, next)
		local rested = P.trickBurstRest
		if freshBurst then
			local press = next.clock - (rested - next.burstWait)
			local earned = marks.trickArmed ~= false and press - (marks.burstAt or -math.huge) >= rested - E.gravityEps
			if earned then
				marks.burstAt = press
			end
			marks.trickBurst = if earned then true else nil
		end
		if freshWiggle or (freshBurst and not (launched or grabFrom or unjudged)) then
			-- (the flight has had its wiggle; a burst whose flight ended in the gap before a new launch, or in a gap too
			-- long to judge, leaves the new flight its own: the honest lossy runs')
			marks.trickArmed = false
		end
		if marks.trickBurst and (freshBurst or prev.burstWait > 0) then
			burstFrom = if freshBurst then 0 else rested - prev.burstWait
			burstTo = if next.burstWait > 0 then math.max(burstFrom, rested - next.burstWait) else rested
		end
		if not footB and next.trickKind ~= 0 and (freshWiggle or prev.trickKind ~= 0) then
			local R = marks.trickReach or 0
			local from = if freshWiggle then 0 else prev.aimReach or 0
			trickScale = SquirrelMotor.aimScale(next.aimReach or 0, R) / SquirrelMotor.aimScale(from, R)
			trickOut = SquirrelMotor.aimScale(math.max(next.aimReach or 0, from), R)
		end
		if freshRoll and marks.rollArmed then
			local at = math.clamp(next.clock - (P.trickRoll - next.trickTime), prev.clock, next.clock)
			marks.speedHold = math.max(marks.speedHold or -math.huge, at + P.trickRoll)
			marks.rollArmed = nil
		end
		if next.routeId ~= nil or next.grounded then
			marks.trickArmed = true
			marks.trickBurst = nil
			marks.footClock = next.clock
		else
			marks.rollArmed = true
		end
	end
	-- the speed kept (unknown: the most an honest body has there: a sprint on the ground, a launch's in the air)
	local u = (marks.speedU or (if footA then P.sprint else SquirrelMotor.launchCapXZ(false) * E.launchTol))
		* trickScale
	local s = marks.speedS or P.sprint
	local holdLeft = math.max(0, (marks.speedHold or -math.huge) - prev.clock)
	-- (a free flight, validator round 13, the round-12 review's HIGH 1: earned only by a launch off a rail the server
	-- knows of (railLaunch: the envelope saw it, or a hidden one with a rail at hand: hiddenLaunch) and over once its arc
	-- from that launch must have come down to where the body is: a body at height y later than the arc passes y on its
	-- way down is over the arc, so it came down on something since (the motor's railLeap ends at its landing))
	local function onArc(c: number, y: number): boolean
		local at, ay, avy = marks.speedArcAt, marks.speedArcY, marks.speedArcVy
		if at == nil or ay == nil or avy == nil then
			return false
		end
		local disc = avy * avy + 2 * P.gravity * (ay - (y - E.posSlack))
		return disc >= 0 and c <= at + (avy + math.sqrt(disc)) / P.gravity + E.gravityEps
	end
	local free = marks.speedRail == true and onArc(prev.clock, prev.y)
	local V54 = SquirrelMotor.V54
	-- (a free launch's flight steers toward v5.4's speeds, the sprint's with the key held whatever the meter says: the
	-- motor's railLeap)
	local walkLo: number? = if free then V54.sprint else nil
	local sprintLo: number? = walkLo
	if trickOut > 1 then
		-- (a wiggle's re-aim out: the motor's air steers toward its speed scaled as the speed was, a sprint's at most)
		local lo = math.max(walkLo or 0, P.sprint) * trickOut
		walkLo, sprintLo = lo, lo
	end
	-- (`rail`: the flight is free from here; `arcFrom`: a free launch, its arc dated from this packet (its clock, its height
	-- and the vertical speed judged); a free flight carried on keeps its launch's)
	-- (`route`: the rail a fresh free flight left, when the server had the body on it)
	local function keepModel(nu: number?, ns: number?, hold: number?, rail: boolean?, arcFrom: State?, route: number?)
		marks.speedU, marks.speedS, marks.speedHold = nu, ns, hold
		marks.speedRail = if rail then true else nil
		if not rail then
			marks.speedArcAt, marks.speedArcY, marks.speedArcVy, marks.speedRoute = nil, nil, nil, nil
		elseif arcFrom then
			marks.speedArcAt, marks.speedArcY, marks.speedArcVy = arcFrom.clock, arcFrom.y, arcFrom.vy
			marks.speedRoute = route
		end
	end
	-- the launch's speed: the envelope's cap held to the claim (keepXZ), a winded one's no more than a winded leap or pounce;
	-- free off a rail the envelope saw, and a trampoline's bounce keeps a free flight free (the motor's railLeap is kept)
	-- (`most`: the most its flight can have kept by the packet's end, when the packet dates the launch)
	local function launchModel(most: number?)
		local cap = if tired
			then (if charge == "pounce" then P.walk else P.leapForwardWinded) * E.launchTol
			else math.huge
		local freeLaunch = not footB and (railLaunch == true or (charge == nil and free))
		keepModel(
			math.min(hxz, cap, most or math.huge),
			s,
			if pounceAt then pounceAt + P.pounceWindow else nil,
			freeLaunch,
			if freeLaunch then next else nil,
			if railLaunch == true then launchRoute else marks.speedRoute
		)
	end
	if exempt then
		-- (the chili rush, the river's quay: unknown speed after)
		keepModel(nil, nil, nil, nil)
		if footA and footB and not (unjudged and span > C.STAMINA_BURST + E.dtEps) and span > 1e-3 then
			marks.stamina = math.min(1, marks.stamina + span / P.sprintRefill)
		end
		settle()
		return
	end
	if span <= 1e-3 then
		if launched then
			launchModel()
		end
		settle()
		return
	end
	local tol = C.STAMINA_WALK
	local across = math.sqrt((next.x - prev.x) ^ 2 + (next.z - prev.z) ^ 2)
	if burstTo > burstFrom then
		-- (the wiggle's burst: the shift's part, and the pop's carry at the most the flight's own speed is)
		across = math.max(
			0,
			across
				- P.trickShift * P.trickSideK * (SquirrelMotor.shiftDone(burstTo) - SquirrelMotor.shiftDone(burstFrom))
				- P.trickPop
					* P.trickSideK
					* SquirrelMotor.popCarry(burstFrom, burstTo)
					* math.max(u, sprintLo or P.sprint)
		)
	end
	-- (the time an arc from `prev` takes to come down to height y; its apex's when it never reaches it)
	local function fallTo(y: number): number
		local vy = prev.vy
		local disc = vy * vy + 2 * P.gravity * (prev.y - y)
		local t = if disc >= 0 then (vy + math.sqrt(disc)) / P.gravity else math.max(vy, 0) / P.gravity
		return math.clamp(t, 0, span)
	end
	-- (the move as air then ground (`airFirst`) or ground then air, `airT` of it in the air, moveSpeed's goal the sprint
	-- from `from` to `to` seconds into it and the walk the rest: the distance the speed step covers and the speed it keeps.
	-- `total`: the time stepped, when not the whole move's: a launch packet's time before its launch)
	local function stepped(
		airT: number,
		airFirst: boolean,
		from: number,
		to: number,
		total: number?
	): (number, number, number)
		local T = total or span
		local d, nu, ns = 0, u, s
		local at = 0
		local function piece(grounded: boolean, t: number, sprint: boolean)
			if t <= 1e-6 then
				return
			end
			local dd: number
			dd, nu, ns = SquirrelMotor.speedBound(
				nu,
				ns,
				if sprint then P.sprint else P.walk,
				grounded,
				t,
				math.max(0, holdLeft - at),
				if grounded then nil elseif sprint then sprintLo else walkLo
			)
			at += t
			d += dd
		end
		local function part(grounded: boolean, t: number)
			local p0, p1 = at, at + math.max(t, 0)
			local a, b = math.clamp(from, p0, p1), math.clamp(to, p0, p1)
			piece(grounded, a - p0, false)
			piece(grounded, b - a, true)
			piece(grounded, p1 - b, false)
		end
		if airFirst then
			part(false, airT)
			part(true, T - airT)
		else
			part(true, T - airT)
			part(false, airT)
		end
		return d, nu, ns
	end
	-- (the least sprint the motor covers `across` with: the sprint first, where it carries furthest inside the move, past
	-- the walk-steered step by C.STAMINA_STEP, with `credit` studs more. Past even the whole move's sprint (a speed the
	-- motor's step cannot reach from the speed kept: a sprint claimed at once from a walk) the rest is sprint too, at the
	-- sprint's own pace over the walk: never free. `total` and `dist`: a part of the move, its time and the distance it
	-- must cover)
	local function least(airT: number, airFirst: boolean, credit: number, total: number?, dist: number?): number
		local T, D = total or span, dist or across
		local function covers(t: number): boolean
			return (stepped(airT, airFirst, 0, t, T)) * C.STAMINA_STEP + credit >= D
		end
		if not covers(T) then
			local dS = stepped(airT, airFirst, 0, T, T)
			return T + math.max(0, D - dS * C.STAMINA_STEP - credit) / math.max(P.sprint - P.walk, 1e-3)
		end
		local lo, hi = 0, T
		for _ = 1, 12 do
			local mid = (lo + hi) / 2
			if covers(mid) then
				hi = mid
			else
				lo = mid
			end
		end
		return hi
	end
	-- (a launch a gap hid off the rail the last accepted packet stood on, ending in the air at `next`; validator round 14,
	-- the round-13 review: the only rail a gap's launch is free off is the one the server itself had the body on (S1), never
	-- one merely near. Its age: the time a launch at the clamp takes to fall to the vertical speed judged, never less than
	-- a substep (a claim at the clamp is no launch for nothing). A sample of that route where a launch off it explains
	-- `next`: across, within a grab, the drawn pose's offset and the launch's flight over that age; up, between the most a
	-- launch at the clamp ending at that speed rises (the vertical speed's fall since) and the most a drop from rest falls
	-- to it, a grab either side (hop()'s railHigh, the envelope's); and one a run along the route from `prev` at its cap
	-- reaches before the launch (straight: no longer than the run)
	local function launchAge(): number
		return math.min(span, math.max(P.substep, (P.leapUp * E.launchTol - next.vy) / P.gravity))
	end
	-- (`along`: the route, when not the one `prev` is on: a relaunch in an air gap off the route the free flight left; no
	-- run along it then, the flight's own reach judged with the gap)
	local function hiddenLaunch(along: number?): (number, boolean)
		local launchUp = P.leapUp * E.launchTol
		local vy = next.vy
		local tau = launchAge()
		local id = along or prev.routeId
		local route = if id ~= nil then self.world.registry:get(id) else nil
		if route == nil then
			return tau, false
		end
		local reach = math.min(
			Motion.C.airGrab + C.DRAWN_MAX + SquirrelMotor.launchCapXZ(false) * E.launchTol * tau,
			C.RAIL_REACH_MAX
		)
		local minY = next.y - math.max(0, launchUp * launchUp - vy * vy) / (2 * P.gravity) - Motion.C.airGrab
		local maxY = next.y + math.max(0, -vy) ^ 2 / (2 * P.gravity) + Motion.C.airGrab
		local run = SquirrelMotor.routeCap(route, false) * E.railTol * math.max(0, span - tau) + E.posSlack
		return tau,
			railWithin(
				self.world.index,
				next.x,
				next.z,
				reach,
				minY,
				maxY,
				function(sid: number, sx: number, sy: number, sz: number): boolean
					return sid == id
						and (along ~= nil or (sx - prev.x) ^ 2 + (sy - prev.y) ^ 2 + (sz - prev.z) ^ 2 <= run * run)
				end
			)
	end
	-- (a leap off the ground a gap hid, validator round 13: the motor charges leapCost down to an empty meter, never below,
	-- and a winded body leaps at leapForwardWinded. Winded already, or short of leapCost with the end no faster than a
	-- winded leap carries, it is read as a winded one: the meter taken to empty at most, its carry a winded one's (an
	-- honest body on a lossy link leaps winded far more often than the server's lagging meter can tell); else a full one,
	-- paid in full whatever the claim (P1), winding the meter at its floor. Returns the leap's horizontal speed)
	local function hiddenLeap(): number
		local windedXZ = P.leapForwardWinded * E.launchTol
		local tiredBefore = marks.winded == true or marks.stamina <= -C.STAMINA_SLACK + 1e-6
		if tiredBefore or (marks.stamina < P.leapCost and hxz <= windedXZ) then
			marks.stamina -= math.clamp(marks.stamina, 0, P.leapCost)
			return windedXZ
		end
		spend(P.leapCost)
		marks.stamina = math.max(marks.stamina, -C.STAMINA_SLACK)
		return P.leapForward * E.launchTol
	end
	-- (a gap from the ground ending in the air with no rising speed fell off an edge only where one can be: the height its
	-- fall from rest starts at no more than a step over where the gap started, or a floor at that height where the body
	-- left it (back along its velocity by the fall's time; two rays at most). Validator round 14, the round-13 review's LOW: the sign of a
	-- claimed vertical speed alone skipped a hidden leap, P1. Round 15, the round-14 review's LOW b: a ledge only one the
	-- body got onto without a leap it did not pay for: `climb` over where it started and a step (from the ground none; off
	-- a rail, the free leap's rise))
	local function fellOff(climb: number): boolean
		local fall = math.max(0, -next.vy) / P.gravity
		local top = next.y + P.gravity * fall * fall / 2
		local step = Units.st(1.4) + E.posSlack
		if top <= prev.y + step then
			return true
		end
		if landable == nil or top > prev.y + climb + step then
			return false
		end
		-- (the edge where the fall began, and a stud further back along the way it went: the feet leave a little past it)
		local hxzNext = math.sqrt(next.vx * next.vx + next.vz * next.vz)
		local bx, bz = next.x - next.vx * fall, next.z - next.vz * fall
		local ux, uz = if hxzNext > 1e-6 then next.vx / hxzNext else 0, if hxzNext > 1e-6 then next.vz / hxzNext else 0
		return landable(bx, top + E.posSlack, bz, step) or landable(bx - ux, top + E.posSlack, bz - uz, step)
	end
	-- (the least sprint a distance past the walk-steered step needs: the sprint steers it no more than this faster)
	local rate = math.max(P.sprint - P.walk, if free then V54.sprint - V54.walk else 0, 1e-3)
	-- (`over` studs past the walk-steered step in a gap, inside an honest burst: the least of a sprint and a leap off the
	-- ground whose carry covers part of it, leapCost (unless `paid`) as the sprint it is worth. The carry: the leap's flight
	-- from `leapXZ` as the motor's air steps it (toward a sprint, dragged), and its landing's on the ground for the time
	-- left, over a walk; validator round 17: a leap's speed held for its whole flight let a gap from a step off an edge
	-- cover 45 st in 1.19 s for one leapCost, 30.8 st/s far from any rail against an honest hop's 20-24. Returns that
	-- sprint and the time it holds neither on the ground nor on a rail (sprinting, or in the leap's flight): validator
	-- round 14, the round-13 review's HIGH 2, time credited as a flight is never refilled)
	local function sprintOrLeap(over: number, leapXZ: number, room: number, paid: boolean, r: number): (number, number)
		local bySprint = over / r
		local flight = math.min(room, 2 * P.leapUp / P.gravity)
		local dFly, uLand, sLand = SquirrelMotor.speedBound(leapXZ, P.sprint, P.sprint, false, flight)
		local dLand = SquirrelMotor.speedBound(uLand, sLand, P.walk, true, math.max(0, room - flight))
		local carry = math.max(0, dFly + dLand - P.walk * tol * room)
		local leapRun = math.max(0, over - carry) / r
		local byLeap = (if paid then 0 else P.leapCost * P.sprintSeconds) + leapRun
		if byLeap < bySprint then
			return math.clamp(byLeap, 0, span), flight + leapRun
		end
		local t = math.clamp(bySprint, 0, span)
		return t, t
	end
	-- (the off-rail leg of a move with one end on a rail, validator round 14, the round-13 review's MEDIUM: `leg` studs in
	-- `T` seconds, the first `tAir` of them a flight covering `dAir`, the rest on the ground from the speed (gu, gs) at a
	-- walk-steered step, and the least of a sprint and a leap off the ground for what that does not cover; past an honest
	-- burst, all the gap's time when faster. Returns the sprint and the ground time left to refill)
	local function legOf(
		leg: number,
		T: number,
		tAir: number,
		dAir: number,
		gu: number,
		gs: number,
		leapXZ: number
	): (number, number)
		local Tg = math.max(0, T - tAir)
		local dW = SquirrelMotor.speedBound(gu, gs, P.walk, true, Tg)
		local over = leg - dAir * C.STAMINA_STEP - math.max(P.walk * Tg * tol, dW * C.STAMINA_STEP) - E.posSlack
		if over <= 0 then
			return 0, Tg
		end
		if unjudged and span > C.STAMINA_BURST + E.dtEps then
			return span, 0
		end
		local spent, busy = sprintOrLeap(over, leapXZ, Tg, false, math.max(P.sprint - P.walk, 1e-3))
		return spent, math.max(0, Tg - busy)
	end
	local sprinted = 0
	local refill = 0
	local airT, airFirst = 0, true
	-- (the speed kept after the move, when a branch sets it: u, s, rail, and whether its free flight starts here)
	local after: { u: number, s: number, rail: boolean?, arc: boolean? }? = nil
	-- (a gap from the ground that ends in the air: the most its hidden launch carries)
	local gapCap = SquirrelMotor.launchCapXZ(false) * E.launchTol
	if launched then
		-- (the launch's own packet, validator round 13, the round-12 review's MEDIUM: the time before the launch is a move of
		-- its own, judged as any other: the least sprint past the walk-steered step for the distance the launch's flight, at
		-- its cap for the whole of its time, does not cover; on the ground, or from the air the ground or the air, whichever
		-- needs less (a landing the packet may hide). Only the ground time not sprinting refills. The launch's time: the
		-- window's for a pounce, else the time a leap's vertical speed (leapUp, winded or not) takes to fall to the one
		-- judged: a claim at the clamp is a launch at the packet's very end, all of its time before it. Off a rail the
		-- rail's pace is the rail's own)
		-- (a launch the envelope's grab search explains: from that grab on, the motor's own grabs and their free leaps; before
		-- it, the body's own flight to where the grab's snap reached from: validator round 15, the round-14 review's MEDIUM 4)
		local inAir = math.clamp(
			if grabFrom
				then next.clock - grabFrom.clock
				elseif pounceAt then next.clock - pounceAt
				else (P.leapUp - math.min(next.vy, P.leapUp)) / P.gravity,
			0,
			span
		)
		local before = span - inAir
		-- (the launch's flight over its time: from its cap (a winded one's; a bounce's or a rail leap's no less than the
		-- speed judged at the end), steered toward the sprint at accelAir as the motor's flight is, a pounce's window held,
		-- a rail leap's toward v5.4's sprint: what it covers, and the most it keeps; validator round 13, a 0.49 s launch
		-- packet credited at its cap throughout and kept at it after carried 29.7 st/s)
		local flyCap = if tired
			then (if charge == "pounce" then P.walk else P.leapForwardWinded) * E.launchTol
			else SquirrelMotor.launchCapXZ(false) * E.launchTol
		if charge == nil then
			flyCap = math.max(flyCap, hxz)
		end
		local fly, uFly = SquirrelMotor.speedBound(
			flyCap,
			P.sprint,
			P.sprint,
			false,
			inAir,
			if pounceAt then P.pounceWindow else nil,
			if railLaunch then V54.sprint else nil
		)
		if before > 1e-3 and not railA then
			local onFoot = if grabFrom
				then math.sqrt((grabFrom.x - prev.x) ^ 2 + (grabFrom.z - prev.z) ^ 2) - grabFrom.reach - E.posSlack
				else across - fly * C.STAMINA_STEP - E.posSlack
			local function need(air: boolean): number
				local inAirBefore = if air then before else 0
				local dW = stepped(inAirBefore, true, 0, 0, before)
				local credit = math.max(0, P.walk * before * tol - dW * C.STAMINA_STEP)
				if onFoot <= dW * C.STAMINA_STEP + credit then
					return 0
				end
				return least(inAirBefore, true, credit, before, onFoot)
			end
			sprinted = need(not groundA)
			if not groundA and sprinted > 0 then
				sprinted = math.min(sprinted, need(false))
			end
			spend(sprinted / P.sprintSeconds)
			onCredit(
				sprinted,
				`{across} st in {span} s with a launch {inAir} s before its end: faster than a walk before it for longer than the sprint meter lasts`
			)
		end
		if footA then
			refill = math.max(0, before - sprinted)
		end
		marks.stamina = math.min(1, marks.stamina + refill / P.sprintRefill)
		launchModel(uFly)
		settle()
		return
	elseif railA or railB then
		-- (a move with an end on a rail. On a rail the motor's velocity is none: its pace is the rail's (the envelope's,
		-- hop()'s), refilled. Validator round 14, the round-13 review's MEDIUM: the off-rail end's distance from the nearest
		-- point of the claimed route, less a grab and the drawn pose's offset, is a move of its own in the time the run along
		-- the route to the rail end leaves (straight: no longer than the run): off the rail the server had the body on, after
		-- one free leap off it (S1) down to the off-rail end's height; onto a rail, the flight in progress and then the
		-- ground. The rest the least sprint or a leap off the ground, as any move's (legOf); refilled only for the time on
		-- the rail and on the ground not sprinting nor in a leap's flight)
		local windedNow = marks.winded == true or marks.stamina <= -C.STAMINA_SLACK + 1e-6
		local leapXZ = (if windedNow then P.leapForwardWinded else P.leapForward) * E.launchTol
		local launchCap = SquirrelMotor.launchCapXZ(false) * E.launchTol
		local launchUp = P.leapUp * E.launchTol
		local railT, groundT = span, 0
		local atRail, cap = false, launchCap
		local reg = self.world.registry
		-- (the free leap off a rail the server had the body on, from its drawn pose at a point of it (its height the drawn
		-- pose's: a bough's lift) down to height y: its time, at most T, and what it covers steered at v5.4's sprint)
		local function freeLeap(route: any, hit: any, y: number, T: number): (number, number, number, number, number)
			local topY = hit.y
			local off = C.DRAWN_MAX
			if route then
				local drawn = Motion.visualPose(self.world, route, hit.t, Curve.vec3(hit.x, hit.y, hit.z), 0, 1)
				off, topY = math.sqrt((drawn.x - hit.x) ^ 2 + (drawn.z - hit.z) ^ 2), math.max(hit.y, drawn.y)
			end
			local disc = launchUp * launchUp + 2 * P.gravity * (topY - y)
			local tf = math.clamp(if disc >= 0 then (launchUp + math.sqrt(disc)) / P.gravity else 0, 0, T)
			local dF, uF, sF = SquirrelMotor.speedBound(launchCap, V54.sprint, V54.sprint, false, tf, nil, V54.sprint)
			return off, tf, dF, uF, sF
		end
		if railA and railB then
			-- (both ends on a rail, validator round 15, the round-14 review's MEDIUM 1: the rail's pace, refilled, only for a
			-- move along one route within its cap. Any other is judged as the one-end move is: a run along A to the point
			-- NA of it nearest B (the end's own point on one route: a leap along it), one free leap off A (the server had
			-- the body on it: S1) and the leg across to NB, B's point nearest NA, less A's drawn offset and a grab onto
			-- another rail, judged as any off-rail move in the time the runs leave (legOf), then a run along B; refilled
			-- only for the runs and the ground time neither sprinting nor in a leap's flight)
			local ra, rb = reg:get(prev.routeId), reg:get(next.routeId)
			local capA = if ra then SquirrelMotor.routeCap(ra, false) * E.railTol else math.huge
			local capB = if rb then SquirrelMotor.routeCap(rb, false) * E.railTol else math.huge
			local along = prev.routeId == next.routeId
				and ra ~= nil
				and math.abs(next.railT - prev.railT) * ra.length <= capA * (span + P.substep) + E.posSlack
			if not along and ra and rb then
				local a = { x = prev.x, y = prev.y, z = prev.z, t = prev.railT }
				local b = { x = next.x, y = next.y, z = next.z, t = next.railT }
				if prev.routeId ~= next.routeId then
					local index = self.world.index
					local dist = math.sqrt((next.x - prev.x) ^ 2 + (next.y - prev.y) ^ 2 + (next.z - prev.z) ^ 2)
					local hitA = index:nearestOnRoute(
						prev.routeId,
						next.x,
						next.y,
						next.z,
						math.min(dist + C.ROUTE_NEAR + 1, C.RAIL_REACH_MAX)
					)
					if hitA then
						a = hitA
					end
					local back = math.sqrt((next.x - a.x) ^ 2 + (next.y - a.y) ^ 2 + (next.z - a.z) ^ 2)
					local hitB = index:nearestOnRoute(
						next.routeId,
						a.x,
						a.y,
						a.z,
						math.min(back + C.ROUTE_NEAR + 1, C.RAIL_REACH_MAX)
					)
					if hitB then
						b = hitB
					end
				end
				local runA = math.sqrt((a.x - prev.x) ^ 2 + (a.y - prev.y) ^ 2 + (a.z - prev.z) ^ 2)
				local runB = math.sqrt((next.x - b.x) ^ 2 + (next.y - b.y) ^ 2 + (next.z - b.z) ^ 2)
				railT = math.min(span, runA / capA + runB / capB)
				local T = span - railT
				local off, tf, dF, uF, sF = freeLeap(ra, a, b.y, T)
				-- (a grab lands at the rail's nearest point: onto another rail it reaches across to NB, along one route it
				-- adds nothing, the envelope's section 2)
				local grabTo = if prev.routeId == next.routeId then 0 else Motion.C.airGrab
				local leg = math.max(0, math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2) - off - grabTo - E.posSlack)
				sprinted, groundT = legOf(leg, T, tf, dF, uF, sF, leapXZ)
			end
		else
			local o = if railA then next else prev
			local r = if railA then prev else next
			local route = self.world.registry:get(r.routeId)
			local nx, ny, nz = r.x, r.y, r.z
			local hit = self.world.index:nearestOnRoute(r.routeId, o.x, o.y, o.z, C.RAIL_REACH_MAX)
			-- (the reach off the rail: onto it a grab (the motor's, from the body); off it the drawn pose's offset there,
			-- where a leap leaves from (a trunk's bark; a bough's lift is height), its height the drawn pose's)
			local off, topY = C.DRAWN_MAX, ny
			if hit then
				nx, ny, nz = hit.x, hit.y, hit.z
				if route then
					local drawn = Motion.visualPose(self.world, route, hit.t, Curve.vec3(nx, ny, nz), 0, 1)
					off, topY = math.sqrt((drawn.x - nx) ^ 2 + (drawn.z - nz) ^ 2), math.max(ny, drawn.y)
				end
			end
			local leg = math.max(
				0,
				math.sqrt((o.x - nx) ^ 2 + (o.z - nz) ^ 2) - (if railA then off else Motion.C.airGrab) - E.posSlack
			)
			local railCap = if route then SquirrelMotor.routeCap(route, false) * E.railTol else math.huge
			railT = math.min(span, math.sqrt((nx - r.x) ^ 2 + (ny - r.y) ^ 2 + (nz - r.z) ^ 2) / railCap)
			local T = span - railT
			if railA then
				-- (off the rail: one free leap off it, down to the off-rail end's height)
				local disc = launchUp * launchUp + 2 * P.gravity * (topY - o.y)
				local tf = math.clamp(if disc >= 0 then (launchUp + math.sqrt(disc)) / P.gravity else 0, 0, T)
				local dF, uF, sF =
					SquirrelMotor.speedBound(launchCap, V54.sprint, V54.sprint, false, tf, nil, V54.sprint)
				if not footB then
					-- (ending in the air: a launch off that same route at hand where `next` is (hiddenLaunch) is the free
					-- leap itself; else the free leap came down, and an end rising, or over any edge it could have
					-- fallen off, leapt off the ground: paid, its carry the last of the time)
					local tau: number
					tau, atRail = hiddenLaunch()
					local climb = math.max(0, topY - prev.y) + launchUp * launchUp / (2 * P.gravity)
					if not atRail and (next.vy > 0 or not fellOff(climb)) then
						cap = hiddenLeap()
						leg = math.max(0, leg - cap * tau * C.STAMINA_STEP)
						T = math.max(0, T - tau)
						tf = math.min(tf, T)
					end
				end
				if not atRail then
					sprinted, groundT = legOf(leg, T, tf, dF, uF, sF, leapXZ)
				end
			elseif groundA then
				-- (from the ground onto a rail higher than a grab from where it stood reaches: a leap onto it, paid,
				-- its carry while it rises there; validator round 15, the round-14 review's LOW c)
				local over = ny - (o.y + Motion.C.airGrab + E.posSlack)
				if over > 0 then
					local leapCap = hiddenLeap()
					local tUp = if over < launchUp * launchUp / (2 * P.gravity)
						then (launchUp - math.sqrt(launchUp * launchUp - 2 * P.gravity * over)) / P.gravity
						else launchUp / P.gravity
					tUp = math.min(tUp, T)
					sprinted, groundT = legOf(leg, T, tUp, leapCap * tUp, u, s, leapXZ)
				else
					sprinted, groundT = legOf(leg, T, 0, 0, u, s, leapXZ)
				end
			else
				-- (onto a rail from the air: the flight in progress until its arc comes down to the rail's height)
				local t1 = math.min(fallTo(ny), T)
				local d1, u1, s1 = SquirrelMotor.speedBound(u, s, P.walk, false, t1, holdLeft, walkLo)
				sprinted, groundT = legOf(leg, T, t1, d1, u1, s1, leapXZ)
			end
		end
		spend(sprinted / P.sprintSeconds)
		onCredit(
			sprinted,
			`{across} st in {span} s with an end on a rail: faster off it than a walk for longer than the sprint meter lasts`
		)
		if not (unjudged and span > C.STAMINA_BURST + E.dtEps) then
			refill = railT + groundT
		end
		marks.stamina = math.min(1, marks.stamina + refill / P.sprintRefill)
		if railB then
			keepModel(0, P.sprint, nil, nil)
		elseif footB then
			keepModel(math.min(hxz, launchCap), P.sprint, nil, nil)
		else
			keepModel(math.min(hxz, cap), P.sprint, nil, atRail, next, prev.routeId)
		end
		settle()
		return
	elseif unjudged and groundA then
		-- (a gap from the ground, whatever its end: the least the motor covers it with, a sprint for what the walk-steered
		-- step does not, or a leap paid with leapCost whose carry, at most a leap's flight at the leap's speed over a walk,
		-- covers part of it)
		airT, airFirst = 0, true
		-- (validator round 13: one that ends in the air hid a launch; round 14, the round-13 review's HIGH 2 and LOW: never a
		-- free one (no rail the server had the body on: S1), a leap off the ground paid with leapCost whatever the claim,
		-- unless it fell off an edge (no rising speed, and an edge it could have fallen from: fellOff) or a trampoline in
		-- reach bounced it; a leap made winded carries at a winded one's speed)
		local leapXZ = (
			if marks.winded == true or marks.stamina <= -C.STAMINA_SLACK + 1e-6
				then P.leapForwardWinded
				else P.leapForward
		) * E.launchTol
		local leapPaid = false
		if not footB then
			local bed = MoveValidator.nearTrampoline(
				self.world,
				next.x,
				next.z,
				SquirrelMotor.launchCapXZ(false) * E.launchTol * span
			)
			if not bed and (next.vy > 0 or not fellOff(0)) then
				leapXZ = hiddenLeap()
				gapCap = leapXZ
				leapPaid = true
			end
		end
		local dW = stepped(0, true, 0, 0)
		local over = across - math.max(P.walk * span, dW) * tol
		local busy = 0
		if over > 0 then
			if span <= C.STAMINA_BURST + E.dtEps then
				sprinted, busy = sprintOrLeap(over, leapXZ, span, leapPaid, rate)
			else
				sprinted = span
			end
		end
		if footB and span <= C.STAMINA_BURST + E.dtEps then
			refill = math.max(0, span - busy)
		end
	elseif unjudged then
		-- (a gap from the air, validator round 12, the round-11 review's HIGH: the flight in progress at its walk-steered
		-- carry until its arc comes down, then the ground; a gap that ends in a fresh flight (its vertical speed no
		-- continuation of the arc, or the body over where the arc has come down to) hid a launch, at least a substep old
		-- (round 13). Validator round 14, the round-13 review's HIGH 2 (S1, S2): no rail credit here, none being one the
		-- server had the body on: that relaunch is a leap off the ground, charged leapCost (at a winded one's speed when
		-- winded), its flight never a free one; the flight in progress lasts no longer than its arc takes to come down to the
		-- lowest the relaunch can have left from; the time between is on the ground, at a walk-steered step and the least
		-- of a sprint and one leap (its carry the only one: a relaunch's is its own), and only the time neither sprinting nor
		-- in that leap's flight refills. A free flight carried through the gap stays free only while `next` is on its arc.
		-- Past an honest burst all its time on the ground drains when faster)
		local launchUp = P.leapUp * E.launchTol
		-- (where the flight in progress has come down to by the gap's end, held at the terminal speed)
		local vyEnd = math.max(prev.vy - P.gravity * span, -P.terminalFall)
		local tTerm = math.clamp((prev.vy + P.terminalFall) / P.gravity, 0, span)
		local yEnd = prev.y + prev.vy * tTerm - 0.5 * P.gravity * tTerm * tTerm - P.terminalFall * (span - tTerm)
		local relaunch = not footB
			and (
				next.vy > vyEnd + P.gravity * E.gravityEps
				or next.y > yEnd + E.posSlack + P.gravity * E.gravityEps * span
			)
		local tau = if relaunch then launchAge() else 0
		local t1 = if groundB
			then fallTo(next.y)
			elseif relaunch then math.min(
				span - tau,
				fallTo(next.y - math.max(0, launchUp * tau - 0.5 * P.gravity * tau * tau))
			)
			else span
		local rest = math.max(0, span - t1 - tau)
		local d1, u1, s1 = SquirrelMotor.speedBound(u, s, P.walk, false, t1, holdLeft, walkLo)
		local d2, u2, s2 = 0, u1, s1
		if rest > 0 then
			d2, u2, s2 = SquirrelMotor.speedBound(u1, s1, P.walk, true, rest)
		end
		local d3, u3, s3 = 0, u2, s2
		-- (a hidden leap off the ground made winded carries at a winded one's speed: validator round 13, the round-12
		-- review's LOW a)
		local gapTired = marks.winded == true or marks.stamina <= -C.STAMINA_SLACK + 1e-6
		local leapXZ = (if gapTired then P.leapForwardWinded else P.leapForward) * E.launchTol
		-- (validator round 15: a free flight off a rail the server had the body on, on its arc when the gap began, and a
		-- relaunch at hand on that same route where `next` is: the motor's free leap chain along it (caught by the rail,
		-- Space again), free and a rail leap's flight; any other relaunch is a leap off the ground, paid)
		local chain = false
		if tau > 0 and free and marks.speedRoute ~= nil then
			local _, at = hiddenLaunch(marks.speedRoute)
			chain = at
		end
		if chain then
			local launchCap = SquirrelMotor.launchCapXZ(false) * E.launchTol
			d3, u3, s3 = SquirrelMotor.speedBound(launchCap, s2, V54.sprint, false, tau, nil, V54.sprint)
			u3 = math.min(u3, launchCap)
		elseif tau > 0 then
			leapXZ = hiddenLeap()
			d3, u3, s3 = SquirrelMotor.speedBound(leapXZ, s2, P.walk, false, tau)
			u3 = math.min(u3, leapXZ)
		end
		local over = across - math.max(P.walk * span, d1 + d2 + d3) * tol - E.posSlack
		local busy = 0
		if over > 0 then
			if span <= C.STAMINA_BURST + E.dtEps then
				if rest > 0 and not relaunch then
					sprinted, busy = sprintOrLeap(over, leapXZ, rest, false, rate)
				else
					sprinted = math.clamp(over / rate, 0, span)
					busy = sprinted
				end
			else
				sprinted = if rest > 0 then rest else math.clamp(over / rate, 0, span)
			end
		end
		if groundB and span <= C.STAMINA_BURST + E.dtEps then
			refill = math.max(0, rest - busy)
		end
		local ku, ks, kr = u1, s1, free and onArc(next.clock, next.y)
		if relaunch then
			ku, ks, kr = math.min(hxz, u3), s3, chain
		elseif groundB then
			ku, ks, kr = u2, s2, false
		end
		if sprinted > 0 then
			ku, ks = math.max(ku, P.sprint), P.sprint
		end
		after = { u = ku, s = ks, rail = if kr then true else nil, arc = chain }
	else
		-- a move judged move by move: on the ground, in the air, or one that lands or walks off an edge
		if groundA and groundB then
			airT = 0
		elseif not groundA and not groundB then
			airT = span
		elseif groundB then
			airT, airFirst = fallTo(next.y), true
		else
			-- (off an edge: falling from rest since it left the ground)
			airT, airFirst = math.clamp(math.max(0, -next.vy) / P.gravity, 0, span), false
		end
		-- (a walk, or the walk-steered step: the motor's own, so only C.STAMINA_STEP over it; a sprint slowing to a walk
		-- at speedSmooth, a landing's carry, a flight coasting from its launch drain nothing)
		local dW = stepped(airT, airFirst, 0, 0)
		local credit = math.max(0, P.walk * span * tol - dW * C.STAMINA_STEP)
		if across > dW * C.STAMINA_STEP + credit then
			-- (a pounce's lunge runs on along the ground for its window, unsteered: paid with pounceCost, not the sprint)
			local pounced = actor.lastPounce
			local lunge = airT <= 0
				and pounced ~= nil
				and not marks.tiredLunge
				and prev.clock >= pounced - 1e-3
				and next.clock <= pounced + P.pounceWindow + 1e-3
				and across <= P.pounceSpeedFast * E.speedTol * span + E.posSlack
			sprinted = if lunge then 0 else least(airT, airFirst, credit)
			if airT >= span then
				-- (past what the sprint-steered step covers: a flight faster than the motor's from its launch)
				local dS = stepped(airT, airFirst, 0, span)
				local most = dS * E.speedTol + E.posSlack
				if across > most then
					table.insert(violations, {
						code = "speed",
						severity = math.min(1, across / most - 1),
						detail = `{across} st across in {span} s in the air (the motor's air step from its speed carries {dS})`,
					})
				end
			end
		end
		refill = math.max(0, span - airT - sprinted)
	end
	spend(sprinted / P.sprintSeconds)
	onCredit(
		sprinted,
		if airT > 0
			then `{across} st in {span} s{if unjudged then " (a gap)" else ""} with the air carrying {span} s: faster than the motor's flight at a walk for longer than the sprint meter lasts`
			else "faster than a walk on the ground for longer than the sprint meter lasts"
	)
	marks.stamina = math.min(1, marks.stamina + refill / P.sprintRefill)
	-- (the speed kept: stepped as the move was judged, its sprint last, where it leaves the most; a gap from the ground that
	-- ends in the air hid a launch)
	local _, nu, ns = stepped(airT, airFirst, span - sprinted, span)
	if after then
		keepModel(after.u, after.s, nil, after.rail, if after.arc then next else nil, marks.speedRoute)
	elseif unjudged and groundA and not footB then
		keepModel(math.min(hxz, gapCap), ns, nil, nil)
	else
		-- (a pounce's window holds the speed on the ground too: its lunge; a free flight stays free while on its arc)
		local holdTo = marks.speedHold
		keepModel(
			nu,
			ns,
			if holdTo and holdTo > next.clock then holdTo else nil,
			not groundB and free and onArc(next.clock, next.y)
		)
	end
	settle()
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
		-- (owner D19: a leap that follows another off a rail rises chainLift of a leap's; the first's extra is the one-off's)
		vRail = math.max(
			railClimbOf(self.world.registry, boosted) * E.railTol,
			launchUp * P.chainLift - P.gravity * P.substep
		),
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
		marks.winded = marks.winded or parked.winded
		if marks.speedU == nil then
			marks.speedU, marks.speedS = parked.speedU, parked.speedS
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
