--!strict
-- ServerScriptService.Server.Movement.MovementService
-- Wires movement validation for every possessed body (BUILD_PLAN §4.4 #6; §1.5 step 6; HANDOFF rule 12):
--   * squirrel-family bodies (squirrel, rodent) go through MoveValidator (spike S3);
--   * every other kind (human, quadruped, drone, vehicle) gets a per-kind horizontal speed cap check (log-only);
--   * every body gets a 1 s pose history (Paintball/PoseHistory, the ring the arena rewinds; D29);
--   * onHandoff(actor, player, kind) is Possession's hook: SweptCollision.markTeleported(actor.id), a fresh validator
--     and pose history, on possess and on release.
-- Enforcement (Flags "moveValidatorEnforce", on since the live validator, 2026-11-18): the gentlest answer that stops a
-- cheat. A flagged squirrel is snapped back: the last packet that was clean becomes the body's state again, the
-- server moves the body there and tells its driver ("Correction": the snapshot to restore, and a new motor epoch),
-- and the validator starts afresh from it. Never a kick, whatever the count; every snap is logged.
-- The motor epoch: every packet carries the epoch the server last gave its driver (Possession.Granted's motorEpoch,
-- then each Correction). The server bumps it whenever it moves the body itself (snapped(), teleported(): the Reset
-- button, a minigame knocking an animal clear, the sky lift's platform), so a packet sent before the client knew is
-- dropped, never judged against where the body now is. The first packet of an epoch must be within reach of where the
-- server put the body (the gate: C.GATE_SLACK and the fastest the squirrel goes in at most C.GATE_MOVE: the client's
-- body is put there when it takes the move, so a first packet held back buys no reach) and the move to it is judged as
-- a whole (MoveValidator.hop: no climb above a leap, no hanging in the air, no wall), or it is snapped to the gate.
-- A squirrel's new body is the server's (engine.pin: anchored, its own) from the hand-off until its driver's first
-- packet passes the gate: a client that never sends cannot move it, and nothing is judged while its town streams in.
-- Only its own unpin hands the body back (Movement/BodyPin keeps every other path off a kept body), and stays pinned
-- until the engine says it did (not while the body rides); should a pinned body still move off where it is kept, it is
-- taken again and snapped back (reason "pin").
-- What packets cannot show, watch() does: the server's own view of the root (a client owns its body's physics), ten
-- to fifteen times a second:
--   * drift: the root against the last accepted packet by the packets' own pace (their speed over the packet's age,
--     the spread of their arrivals or half the round trip, and a little: driftBounds); a leap's start not yet in a
--     packet only for a moment (C.DRIFT_PERSIST); a root standing still judged against where the packets were when it
--     last moved (its updates held up); before an epoch's first packet, against the gate; for a while after a move
--     (ignoredFor: a round trip, twice, and a second) the place before it, within what the pace covers in a round trip;
--     never more than C.DRIFT_BASE and the fastest the squirrel goes since (C.DRIFT_LAG);
--   * walls: between two samples of the root once an epoch has settled, the live wall rays (a client that stops sending
--     still cannot walk through a house); a root by a rail (C.RAIL_NEAR: a trunk's bark, a downspout on a wall) crosses
--     a wall only where a packet on a rail within C.RAIL_RECENT of the crossing has the body drawn (_explained: its drawn
--     pose reaches the crossing's far end with no wall between; the root may lead the packets, so it waits that long);
--   * the air: while no packet is fresh, a root off the rails higher above any floor than a leap may only fall
--     (C.HIGH_LAG of a held update, then gravity): no hanging, no flying while silent;
--   * silence: a body that moves C.SILENT_MOVE with no packet accepted for C.SILENT seconds (a client that stopped
--     sending, or ignores its correction) is snapped, and one still sending under an old epoch ignoredFor after the
--     move it was told of is told again under the same epoch (a packet under it may still be on its way).
-- C.HOLD_AFTER snaps inside C.HOLD_WINDOW, and the body is held (engine.hold: the server takes its physics and keeps it
-- still) for C.HOLD_SECONDS, then given back with a new epoch. A body on the sky lift (suspend) is not judged at all.
-- For C.STREAM_GRACE after a hand-off a wall alone does not snap (logged): the town around a new body may still be
-- streaming in on its client, and a house it has not got yet is no wall to its motor. A packet with a number that is
-- not finite (SquirrelWire.sane) is snapped and never judged. No packet and no root sample costs more than a bounded
-- time: the validator's rail scans and long lines are bounded (MoveValidator.C.RAIL_REACH_MAX, ValidatorWorld.C).
-- Validator round 3 (2026-11-19, the rule: nothing judged by a number only the client claimed): the duel's pose of the
-- rodent is its last ACCEPTED packet (motorOf), a pounce is dated with the link's spread measured before the click and
-- by its own arrival offset when that is later than the spread explains (a clock slowed while a lunge is held), a click
-- dated at most C.CLICK_EARLY before it arrived and on its arrival when it came long after the launch it says it
-- preceded, the spread never above the round trip the engine measures, and the pace by the validator's kept speeds.
-- Pure over injected collaborators; no side effects on require.
-- Interface: new(deps) -> Movement; M:onHandoff(actor, player?, kind); M:packet(actorId, kind, packet, now) ->
--   Verdict?; M:teleported(actorId, x, y, z, why, now); M:suspend(actorId, on); M:watch(actorId, x, y, z, now);
--   M:epochOf(actorId) -> number; M:safeTarget(actorId) -> (x, y, z)? (where a Reset puts the body); M:motorOf(actorId) -> (snapshot?, at?, pounceAt?, cleanAt?);
--   M:clickAt(actorId, clock, now) ->
--   number?; M:clickNew(actorId, seq) -> boolean (a click's number not taken yet: the first copy of a click to arrive,
--   the Duel remote's or a motor packet's (verdict.click), is the one taken); M:isPinned(actorId) -> boolean; M:pose(actorId, t) -> (x, y, z)?; M:paceOf(actorId) -> number? (read
--   only: the flat pace of the accepted packets, Stealth/Pace.stretch); M:stats() -> Stats; C

local Import = require("../Import")
local Flags = Import.shared("Config/Flags") :: typeof(require("../../shared/Config/Flags"))
local Log = Import.shared("Util/Log") :: typeof(require("../../shared/Util/Log"))
local Units = Import.shared("Config/Units") :: typeof(require("../../shared/Config/Units"))
local SquirrelWire = Import.shared("Movement/SquirrelWire") :: typeof(require("../../shared/Movement/SquirrelWire"))
local PoseHistory = require("../Paintball/PoseHistory")
local MoveValidator = require("./MoveValidator")
local SquirrelMotor = Import.shared("Movement/SquirrelMotor") :: typeof(require("../../shared/Movement/SquirrelMotor"))
local Recovery = Import.shared("Movement/Recovery") :: typeof(require("../../shared/Movement/Recovery"))
local Motion = Import.shared("Routes/Motion") :: typeof(require("../../shared/Routes/Motion"))
local Curve = Import.shared("Routes/Curve") :: typeof(require("../../shared/Routes/Curve"))
local Pace = Import.shared("Stealth/Pace") :: typeof(require("../../shared/Stealth/Pace"))

local ValidatorWorld = require("./ValidatorWorld")

-- What the server says to a squirrel's driver ("Correction"): the new epoch, where the body is (feet), and for a
-- snap the motor state to restore.
export type Correction = {
	epoch: number,
	x: number,
	y: number,
	z: number,
	snapshot: { [string]: number | boolean }?,
	why: string,
	snap: boolean, -- a snap-back (the server moves the body itself); false for a move the server already made
}

export type Engine = {
	-- tell the body's driver (and, for a snap, move the body on the server: feet at x, y, z)
	correct: (actorId: any, msg: Correction) -> (),
	-- take the body's physics and keep it still at x, y, z (feet) for `seconds`, then give it back
	hold: ((actorId: any, x: number, y: number, z: number, seconds: number) -> ())?,
	-- on: the server takes a newly held body's physics and keeps it still where it stands (anchored, its own, marked kept:
	-- Movement/BodyPin); off: gives it to its driver (the first packet passed the gate) -> whether it did (false: not
	-- now, the body rides; nil counts as done)
	pin: ((actorId: any, on: boolean) -> boolean?)?,
}

export type Deps = {
	validator: MoveValidator.MoveValidator?, -- squirrel packets; nil = no rail validation (tests)
	swept: { markTeleported: (self: any, actorId: any) -> () }?, -- Traffic/SweptCollision instance
	historySeconds: number?, -- default 1.0 (Tunables movement.poseHistorySecs)
	historyHz: number?, -- default 60
	speedCaps: { [string]: number }?, -- studs/s per kind for the generic check
	tolerance: number?, -- multiplier on the caps (default 1.25)
	enforce: boolean?, -- snap flagged squirrels back (default: Flags "moveValidatorEnforce")
	engine: Engine?, -- the game's hands (Boot/Game); nil: nothing is sent or moved (the decisions are still made)
	-- where a body stands when it changes hands (feet), for the first packet's gate; nil: no gate at a hand-off
	poseOf: ((actor: any) -> (number?, number?, number?))?,
}

-- Generic packets: position (studs) and the client clock.
export type GenericPacket = { seq: number, t: number, x: number, y: number, z: number }

export type Stats = {
	packets: number,
	flagged: number,
	overSpeed: number,
	handoffs: number,
	corrections: number,
	snaps: number,
	stale: number,
	teleports: number,
	holds: number,
	pins: number, -- new bodies the server kept until a first packet (engine.pin)
	reasons: { [string]: number },
}

type Gate = { x: number, y: number, z: number, at: number, snapshot: { [string]: number | boolean }? }

type Squirrel = {
	epoch: number,
	gate: Gate?,
	good: { [string]: number | boolean }?, -- the last clean packet's snapshot (a snap's target)
	shot: { [string]: number | boolean }?, -- the last accepted packet's snapshot (where the duel has the rodent)
	cleanAt: number?, -- server time of the last clean packet
	lastAt: number?, -- server time of the last accepted packet
	pounceAt: number?, -- server time of the last pounce launch a clean packet showed (the envelope saw the launch)
	pounceClock: number?, -- its client clock
	since: number?, -- server time of this epoch's first accepted packet
	possessedAt: number?, -- server time of the first packet after the hand-off (0: the hand-off, none yet)
	lastX: number,
	lastY: number,
	lastZ: number,
	placed: boolean, -- lastX/Y/Z hold a packet the server accepted (false: never yet; they are no place then)
	suspended: boolean,
	heldUntil: number?,
	held: Gate?,
	snapTimes: { number },
	prior: Gate?, -- the place before the last move the server made (its own updates may still be on their way)
	priorUntil: number,
	rootX: number?, -- the last sample of the root watch() saw this epoch
	rootY: number,
	rootZ: number,
	rootAt: number,
	highSince: number?, -- the root has been high in the air with nothing near since then (its C.HIGH_LAG runs from it)
	highY: number, -- ... from this height ...
	highFrom: number, -- ... at this time (highSince, or the last move the server made since: rebase)
	lastRiver: boolean, -- the last accepted packet was the client's own river recovery (MoveValidator's verdict.river)
	safe: any, -- Movement/Recovery History: the places accepted clean grounded packets stood, a floor under the feet
	paces: { number }, -- the recent packets' speeds (studs/s: their velocity, or the step from the one before)
	-- the recent packets' arrival offsets (server time - client clock) and the link's round trip then
	offsets: { { at: number, off: number, ping: number } },
	rootMovedAt: number, -- server time the root last moved (its updates come while it moves)
	overSince: number?, -- the root has been beyond the packets' own pace since then
	toldAt: number?, -- server time the driver was last told again of the move it ignores
	pinned: boolean, -- a newly held body the server keeps (engine.pin) until its driver's first packet passes the gate
	pinnedAt: number, -- server time it was first watched pinned (0: not yet)
	pinAt: Gate?, -- where a pinned body is kept (the hand-off's place, or where the server moved it since)
	railAt: number?, -- server time of the last accepted packet on a rail
	-- the recent accepted packets on a rail (their snapshots and arrival), C.RAIL_RECENT and a little back
	rails: { { at: number, shot: { [string]: number | boolean } } },
	-- the root's crossings of a wall by a rail not yet explained by a packet on a rail (their time and the root's far end)
	crossings: { { at: number, x: number, y: number, z: number } },
	-- the last click the duel dated (clickAt): its client clock, arrival, and the link's spread measured before it
	click: { at: number, clock: number, spread: number }?,
	-- the newest click number taken (clickNew: the remote's and the packets' copies of one click count once)
	clickSeq: number?,
}

export type Movement = {
	deps: Deps,
	histories: { [any]: PoseHistory.History },
	last: { [any]: GenericPacket },
	squirrels: { [any]: Squirrel },
	log: any,
	_stats: Stats,
	_epoch: number,
	onHandoff: (self: Movement, actor: any, player: any?, kind: string) -> (),
	packet: (self: Movement, actorId: any, kind: string, packet: any, now: number) -> any,
	teleported: (self: Movement, actorId: any, x: number, y: number, z: number, why: string, now: number) -> (),
	suspend: (self: Movement, actorId: any, on: boolean) -> (),
	watch: (self: Movement, actorId: any, x: number, y: number, z: number, now: number) -> (),
	_rootPath: (self: Movement, actorId: any, sq: Squirrel, x: number, y: number, z: number, now: number) -> string?,
	_explained: (
		self: Movement,
		sq: Squirrel,
		c: { at: number, x: number, y: number, z: number },
		rail: any?
	) -> boolean,
	epochOf: (self: Movement, actorId: any) -> number,
	safeTarget: (self: Movement, actorId: any) -> (number?, number?, number?),
	clickAt: (self: Movement, actorId: any, clock: any, now: number) -> number?,
	clickNew: (self: Movement, actorId: any, seq: any) -> boolean,
	motorOf: (self: Movement, actorId: any) -> ({ [string]: number | boolean }?, number?, number?, number?),
	paceOf: (self: Movement, actorId: any) -> number?,
	isPinned: (self: Movement, actorId: any) -> boolean,
	pose: (self: Movement, actorId: any, t: number) -> (number?, number?, number?),
	stats: (self: Movement) -> Stats,
}

local MovementService = {}

MovementService.C = table.freeze({
	GATE_SLACK = 6, -- studs: the first packet of an epoch this near where the server put the body (root or feet) ...
	GATE_MOVE = 0.6, -- ... plus the fastest the squirrel goes in at most this many seconds
	-- a gate high in the air (no floor within a leap under it): the first packet may fall from it, no higher than this
	-- above it nor rising faster (studs, studs/s) ...
	GATE_RISE = 1,
	GATE_AIR = 0.15, -- ... and no further across than GATE_SLACK and the fastest pace for this many seconds
	DRIFT_BASE = 8, -- studs: the root against the last accepted packet (the drawn pose eases behind the motor)
	DRIFT_LAG = 0.6, -- seconds: how far the root may lead the packets (their jitter against the root's)
	DRIFT_FRESH = 0.5, -- seconds: packets older than this are late; the root's height is then judged
	SETTLE = 1, -- seconds after an epoch's first packet in which the place before a move still counts
	IGNORED = 2, -- seconds after a move the server made: packets still under the old epoch mean the client ignores it
	SILENT = 5, -- seconds with no accepted packet ...
	SILENT_MOVE = 6, -- ... while the root moved this far from the last known place: snapped
	HOLD_AFTER = 3, -- snaps ...
	HOLD_WINDOW = 10, -- ... inside this many seconds: the body is held
	HOLD_SECONDS = 2,
	STREAM_GRACE = 3, -- seconds after a hand-off's first packet in which a wall alone is logged, not snapped
	ROOT_STEP = 0.25, -- seconds: two samples of the root further apart than this are not judged for walls
	-- studs: a root this near a rail's samples (the feet drawn on a big trunk's bark are up to 5.95 off them) is not judged
	-- for height, nor for walls while the packets have the body on a rail ...
	RAIL_NEAR = 6.5,
	RAIL_RECENT = 1, -- ... one accepted within this many seconds of the root's crossing, before it or after it

	DRIFT_FRESH_LAG = 0.1, -- seconds: what the root may lead the packets by beyond their arrivals' spread (the send rates)
	DRIFT_DV = 55, -- studs/s: a leap's start from standing (the root may show it a moment before a packet does)
	DRIFT_ACCEL = 80, -- studs/s^2: a fall's gain in speed (gravity) and a sprint's
	DRIFT_PERSIST = 0.6, -- seconds the root may stay beyond the packets' own pace (a leap's start) before it is drift
	SPREAD_WINDOW = 2, -- seconds of packet arrivals whose spread (latest less earliest arrival offset) is the jitter ...
	SPREAD_MAX = 0.5, -- ... never counted above this (nor half the link's round trip)
	ROOT_STALE_MAX = 1, -- seconds a root standing still may be judged against older packets (its updates held up)
	PACE_PAIRS = 4, -- the pace is the fastest of this many recent packets (their own velocity, or their step)
	HIGH_LAG = 1, -- seconds a root high in the air may keep its height (a held-up update) before it must fall
	PIN_LOG = 20, -- seconds a new body may stay pinned with no packet past the gate before it is logged (it stays)
	-- seconds: the most of the engine's round trip (Player:GetNetworkPing, up to 10 s) any wait or window here takes; a
	-- slower link is no reason to let the root sit further off for longer
	PING_MAX = 1,
	-- seconds of client clock: a pounce is dated only from a packet that follows the last one taken by no more than this
	-- (a send interval and the longest frame: a lost packet at 60 frames a second) and the arrivals' spread (a packet
	-- overtaken by a later one is dropped) up to POUNCE_SPREAD_MAX: a longer silence may hide a lunge held back for a
	-- better moment
	POUNCE_GAP = SquirrelWire.SEND_EVERY + SquirrelMotor.params.frameDtCap,
	POUNCE_SPREAD_MAX = 0.3,
	-- seconds: the most a click's own clock may put it before the remote carrying it arrived: the wind-up (0.12) and the
	-- most jitter a pounce's date allows (POUNCE_SPREAD_MAX). (It was 1 s, for a remote resent after a loss; the round-3
	-- review: a click sent once the lunge had reached the person, back-dated onto it, was tied. A click resent that late
	-- now loses its pounce, logged)
	CLICK_EARLY = 0.4,
	-- seconds a click's measured spread stands for the pounce that follows it (the wind-up and the longest hold the tie
	-- takes, with room)
	CLICK_HOLD = 1,
	RAIL_KEEP = 2, -- seconds of packets on a rail kept to explain a crossing of the root by a rail (RAIL_RECENT either side)
	CROSSINGS_MAX = 4, -- unexplained crossings kept at once (a fifth is a wall at once)
	RAILS_TRIED = 8, -- rail packets a new crossing is tried against (the newest)
	RIVER_ROOT_RISE = 1, -- studs: the root on the quay ahead of the packet, this near the quay's height (a step on)
})
local C = MovementService.C

-- W1 caps for the non-rail kinds (studs/s): sprinting human 16, deer/fox running, the drone's speed,
-- the fastest player vehicle (jet ski 20 u/s). Tunables-driven in W2 when the motors land.
MovementService.DEFAULT_CAPS = {
	human = 16,
	quadruped = Units.st(14),
	drone = Units.st(24),
	vehicle = Units.st(20),
} :: { [string]: number }

local RAIL_KINDS = { squirrel = true, rodent = true }

local function dist(ax: number, ay: number, az: number, bx: number, by: number, bz: number): number
	return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2 + (az - bz) ^ 2)
end

local function finite3(x: any, y: any, z: any): boolean
	local m = SquirrelWire.MAX_MAGNITUDE
	return type(x) == "number"
		and type(y) == "number"
		and type(z) == "number"
		and math.abs(x) < m
		and math.abs(y) < m
		and math.abs(z) < m
end

-- fallsFrom(validator, gate, next, fast): the gate itself is high in the air (a body taken, or put back, mid-leap with no
-- floor within a leap under it) and the first packet only falls from it: no higher than C.GATE_RISE above it, not
-- rising, and no further across than C.GATE_SLACK and C.GATE_AIR of the fastest pace (the client's body starts there)
local function fallsFrom(validator: any, gate: Gate, next: any, fast: number): boolean
	local landable = validator.world.landable
	if landable == nil or landable(gate.x, gate.y, gate.z, MoveValidator.apexAllowance()) then
		return false
	end
	local across = math.sqrt((next.x - gate.x) ^ 2 + (next.z - gate.z) ^ 2)
	return next.y <= gate.y + C.GATE_RISE
		and (next.vy or 0) <= C.GATE_RISE
		and across <= C.GATE_SLACK + fast * C.GATE_AIR
end

function MovementService.new(deps: Deps): Movement
	local hz = deps.historyHz or 60
	local seconds = deps.historySeconds or 1.0
	local m = {
		deps = deps,
		histories = {},
		last = {},
		squirrels = {},
		log = Log.new("Movement"),
		_stats = {
			packets = 0,
			flagged = 0,
			overSpeed = 0,
			handoffs = 0,
			corrections = 0,
			snaps = 0,
			stale = 0,
			teleports = 0,
			holds = 0,
			pins = 0,
			reasons = {},
		},
		_epoch = 0,
	} :: Movement

	local function enforcing(): boolean
		if deps.enforce ~= nil then
			return deps.enforce
		end
		return Flags.enabled("moveValidatorEnforce")
	end

	local function history(self: Movement, id: any): PoseHistory.History
		local h = self.histories[id]
		if not h then
			h = PoseHistory.new(seconds, hz)
			self.histories[id] = h
		end
		return h
	end

	local function nextEpoch(self: Movement): number
		self._epoch += 1
		return self._epoch
	end

	local function squirrel(self: Movement, id: any): Squirrel
		local sq = self.squirrels[id]
		if not sq then
			sq = {
				epoch = nextEpoch(self),
				gate = nil,
				good = nil,
				lastAt = nil,
				pounceAt = nil,
				pounceClock = nil,
				since = nil,
				lastX = 0,
				lastY = 0,
				lastZ = 0,
				placed = false,
				suspended = false,
				heldUntil = nil,
				held = nil,
				snapTimes = {},
				prior = nil,
				priorUntil = -math.huge,
				rootX = nil,
				rootY = 0,
				rootZ = 0,
				rootAt = -math.huge,
				highSince = nil,
				highY = 0,
				highFrom = 0,
				lastRiver = false,
				safe = Recovery.newHistory(),
				pinned = false,
				pinnedAt = 0,
				paces = {},
				offsets = {},
				rails = {},
				crossings = {},
				overSince = nil,
				rootMovedAt = 0,
			}
			self.squirrels[id] = sq
		end
		return sq
	end

	local function fastest(self: Movement, id: any): number
		local v = self.deps.validator
		return if v then v:fastest(id) else 60
	end

	local tell: (self: Movement, id: any, sq: Squirrel, t: Gate, why: string, now: number) -> ()

	-- pingOf(self, id): the driver's round trip as the engine measures it, never above C.PING_MAX (0: unknown)
	local function pingOf(self: Movement, id: any): number
		local v = self.deps.validator
		local ping = if v then v.pingOf(id) else nil
		return if type(ping) == "number" and ping >= 0 then math.min(ping, C.PING_MAX) else 0
	end

	-- ignoredFor(self, id): how long after telling its driver of a move the server waits for packets under the new
	-- epoch before it takes the old one's for a client ignoring it (a correction and the first packet after it cross
	-- the link twice: the engine's round trip, twice, and a second)
	local function ignoredFor(self: Movement, id: any): number
		return math.max(C.IGNORED, 2 * pingOf(self, id) + 1)
	end

	-- a new epoch from `target`: the validator forgets, the first packet of the epoch is gated there; the place before
	-- the move (the root last seen, else the last packet) still counts for the drift a while
	-- (`snapped`: the root was judged, so the place before is the last packet's, or the gate's, never the root's)
	-- (`keepUntil`, a snap's: the server time the body held the target place; the displacement governor keeps its history
	-- up to then: MoveValidator.anchor. nil: a move the server made (a Reset, a hold given back, a knock): the governor's
	-- whole history is carried to the target, MoveValidator.relocate. Invariant C (validator round 7): nothing the client
	-- can trigger starts the governor afresh, nor the in-air timer: a root high in the air when the move came must fall
	-- from the target from now on, its C.HIGH_LAG not given again)
	local function rebase(self: Movement, id: any, sq: Squirrel, target: Gate, snapped: boolean?, keepUntil: number?)
		local now = target.at
		local gate = sq.gate
		if sq.rootX and not snapped then
			sq.prior = { x = sq.rootX :: number, y = sq.rootY, z = sq.rootZ, at = now }
		elseif sq.lastAt then
			sq.prior = { x = sq.lastX, y = sq.lastY, z = sq.lastZ, at = now }
		elseif gate and snapped then
			sq.prior = { x = gate.x, y = gate.y, z = gate.z, at = now }
		end
		sq.priorUntil = now + ignoredFor(self, id)
		sq.toldAt = nil
		sq.rootX = nil
		table.clear(sq.crossings)
		table.clear(sq.rails)
		if sq.highSince ~= nil then
			sq.highY, sq.highFrom = target.y, now
		end
		sq.overSince = nil
		sq.epoch = nextEpoch(self)
		sq.gate = target
		if sq.pinned then
			sq.pinAt = target -- (a pinned body the server moved is kept where it put it)
		end
		sq.lastAt = nil
		sq.since = nil
		sq.good = nil -- (a snap from here on goes to the gate, never back over the move)
		sq.shot = nil
		sq.cleanAt = nil
		sq.pounceAt = nil
		sq.pounceClock = nil
		local validator = self.deps.validator
		if validator then
			validator:reset(id, nil)
			if keepUntil then
				validator:anchor(id, target.x, target.y, target.z, now, keepUntil)
			else
				validator:relocate(id, target.x, target.y, target.z, now)
			end
		end
		if self.deps.swept then
			self.deps.swept:markTeleported(id)
		end
		self.histories[id] = nil
	end

	-- anchorOf(sq): a place the server itself holds for the body, to judge a packet the validator has no baseline for
	-- (validator round 6, invariant A): where it keeps a pinned body, else the root it last saw this epoch, else the last
	-- packet it accepted; nil when it knows none (never an uninitialised 0, 0, 0: the round-5 review)
	local function anchorOf(sq: Squirrel): Gate?
		local pin = sq.pinAt
		if sq.pinned and pin then
			return { x = pin.x, y = pin.y, z = pin.z, at = pin.at }
		end
		if sq.rootX then
			return { x = sq.rootX :: number, y = sq.rootY, z = sq.rootZ, at = sq.rootAt }
		end
		if sq.placed then
			return { x = sq.lastX, y = sq.lastY, z = sq.lastZ, at = 0 }
		end
		return nil
	end

	-- snap the body back to `target` (default: the last clean packet, else the gate, else a place the server holds:
	-- anchorOf), tell its driver, hold it after a run of snaps. With no place known at all nothing is moved (logged)
	local function snap(self: Movement, id: any, why: string, now: number, target: Gate?)
		local sq = squirrel(self, id)
		local to = target
		-- (the server time the body held the target: the governor's history is kept to then)
		local keepUntil: number? = if target then (if target.at > 0 then target.at else now) else nil
		if to == nil then
			local good = sq.good
			if good then
				to = { x = good.x :: number, y = good.y :: number, z = good.z :: number, at = now, snapshot = good }
				keepUntil = sq.cleanAt or now
			elseif sq.gate then
				to = sq.gate
				keepUntil = if (sq.gate :: Gate).at > 0 then (sq.gate :: Gate).at else now
			else
				to = anchorOf(sq) -- (a place the server saw: the governor's history carried there, rebase)
			end
		end
		if to == nil then
			self.log:every(`snap:{id}`, 1, "warn", `{id}: no place to snap back to ({why}); not moved`)
			return
		end
		local t = to :: Gate
		local gate: Gate = { x = t.x, y = t.y, z = t.z, at = now, snapshot = t.snapshot }
		rebase(self, id, sq, gate, true, keepUntil)
		tell(self, id, sq, gate, why, now)
	end

	-- tell(self, id, sq, gate, why, now): the snap to `gate` under the current epoch: counted, logged, the body moved
	-- there and its driver told; a run of them holds it
	function tell(self: Movement, id: any, sq: Squirrel, t: Gate, why: string, now: number)
		local gate = t
		local st = self._stats
		st.snaps += 1
		st.corrections += 1
		st.reasons[why] = (st.reasons[why] or 0) + 1
		table.insert(sq.snapTimes, now)
		while #sq.snapTimes > 0 and now - sq.snapTimes[1] > C.HOLD_WINDOW do
			table.remove(sq.snapTimes, 1)
		end
		self.log:every(
			`snap:{id}`,
			1,
			"warn",
			`{id} snapped back ({why}) to {math.floor(t.x)}, {math.floor(t.y)}, {math.floor(t.z)}; {#sq.snapTimes} in {C.HOLD_WINDOW} s`
		)
		local engine = self.deps.engine
		if engine then
			engine.correct(
				id,
				{ epoch = sq.epoch, x = t.x, y = t.y, z = t.z, snapshot = t.snapshot, why = why, snap = true }
			)
			if #sq.snapTimes >= C.HOLD_AFTER and engine.hold and sq.heldUntil == nil and not sq.pinned then
				sq.heldUntil = now + C.HOLD_SECONDS
				sq.held = gate
				st.holds += 1
				self.log:every(`hold:{id}`, 5, "warn", `{id} held for {C.HOLD_SECONDS} s after {#sq.snapTimes} snaps`)
				engine.hold(id, t.x, t.y, t.z, C.HOLD_SECONDS)
			end
		end
	end

	function m.onHandoff(self: Movement, actor: any, _player: any?, kind: string)
		local id = actor.id
		self._stats.handoffs += 1
		if self.deps.swept then
			self.deps.swept:markTeleported(id)
		end
		if self.deps.validator then
			self.deps.validator:forget(id) -- a new start: the next packet is the new baseline
		end
		self.histories[id] = nil
		self.last[id] = nil
		local old = self.squirrels[id]
		local engine = self.deps.engine
		if old and old.pinned and engine and engine.pin then
			engine.pin(id, false) -- (a body still kept goes back to the AI: no longer the validator's)
		end
		self.squirrels[id] = nil
		if kind == "possess" then
			local sq = squirrel(self, id)
			local poseOf = self.deps.poseOf
			if poseOf then
				local x, y, z = poseOf(actor)
				if x and y and z then
					sq.gate = { x = x, y = y, z = z, at = 0 } -- (its time is set by the first packet or watch)
				end
			end
			sq.possessedAt = 0
			-- a squirrel's new body is the server's until its driver's first packet passes the gate (pin)
			if RAIL_KINDS[actor.species] and self.deps.validator and engine and engine.pin and enforcing() then
				sq.pinned = true
				sq.pinAt = sq.gate
				self._stats.pins += 1
				engine.pin(id, true)
			end
		end
	end

	-- pace(self, id, sq, snapshot, now): an accepted packet's speed, arrival offset and the link's round trip, for the
	-- drift's bounds
	local function pace(self: Movement, id: any, sq: Squirrel, shot: { [string]: number | boolean }, now: number)
		local vx, vy, vz = shot.vx :: number, shot.vy :: number, shot.vz :: number
		local v = math.sqrt(vx * vx + vy * vy + vz * vz)
		local clock = shot.clock :: number
		local prev = sq.offsets[#sq.offsets]
		if sq.lastAt and prev then
			local dt = clock - (prev.at - prev.off)
			if dt > 1e-3 then
				local sx, sy, sz = shot.x :: number, shot.y :: number, shot.z :: number
				v = math.max(v, dist(sx, sy, sz, sq.lastX, sq.lastY, sq.lastZ) / dt)
			end
		end
		table.insert(sq.paces, v)
		while #sq.paces > C.PACE_PAIRS do
			table.remove(sq.paces, 1)
		end
		table.insert(sq.offsets, { at = now, off = now - clock, ping = pingOf(self, id) })
		while #sq.offsets > 1 and now - sq.offsets[1].at > C.SPREAD_WINDOW do
			table.remove(sq.offsets, 1)
		end
	end

	-- arrivalSpread(sq): the spread of the recent packets' arrival offsets (the link's jitter as these packets met it),
	-- never above C.POUNCE_SPREAD_MAX
	local function arrivalSpread(sq: Squirrel): number
		local lo, hi = math.huge, -math.huge
		for _, o in sq.offsets do
			lo, hi = math.min(lo, o.off), math.max(hi, o.off)
		end
		return if hi >= lo then math.min(hi - lo, C.POUNCE_SPREAD_MAX) else 0
	end

	-- spreadOf(self, id, sq): the arrivals' spread (the link's jitter as the packets met it), never above the round trip
	-- the engine measures (when it does: the spread is the client's clocks against the server's arrivals, which a client
	-- can widen by running its clock unevenly; the round trip is the server's own)
	local function spreadOf(self: Movement, id: any, sq: Squirrel): number
		local spread = arrivalSpread(sq)
		local ping = pingOf(self, id)
		return if ping > 0 then math.min(spread, ping) else spread
	end

	-- offsetFloor(sq, now): the lowest arrival offset (server time - client clock) of the recent packets: the client clock
	-- to server time with the link's latency and none of a packet's jitter (0 before any)
	local function offsetFloor(sq: Squirrel, _now: number): number
		local lo = math.huge
		for _, o in sq.offsets do
			lo = math.min(lo, o.off)
		end
		return if lo < math.huge then lo else 0
	end

	-- paceOf(sq) -> v, lead, ping: the recent packets' pace (studs/s), how far the root may lead or trail them in time
	-- (the spread of their arrivals, or half the link's round trip: a latency that drops lets the root's updates overtake
	-- packets in flight; C.SPREAD_MAX at most) and the link's round trip
	local function paceOf(sq: Squirrel): (number, number, number)
		local v = 0
		for _, p in sq.paces do
			v = math.max(v, p)
		end
		local lo, hi, ping = math.huge, -math.huge, 0
		for _, o in sq.offsets do
			lo, hi, ping = math.min(lo, o.off), math.max(hi, o.off), math.max(ping, o.ping)
		end
		return v, math.min(math.max(if hi >= lo then hi - lo else 0, ping / 2), C.SPREAD_MAX), ping
	end

	-- reachIn(v, window, fast): how far a body at pace v goes in `window` seconds, gaining speed as a fall or a sprint's
	-- start does (C.DRIFT_ACCEL), never faster than the fastest
	local function reachIn(v: number, window: number, fast: number): number
		return math.min(v * window + 0.5 * C.DRIFT_ACCEL * window * window, fast * window)
	end

	-- driftBounds(sq, now, fast) -> tight, loose: how far the root may be from the last packet by the packets' own pace
	-- (tight), and for a moment, a leap's start not yet in a packet (loose: C.DRIFT_DV more); never more than the fastest
	-- allows. The time the root may be apart from the packets: the last packet's age, the lead (paceOf) and
	-- C.DRIFT_FRESH_LAG
	local function driftBounds(sq: Squirrel, now: number, fast: number): (number, number)
		local v, lead = paceOf(sq)
		local age = now - (sq.lastAt :: number)
		local window = age + lead + C.DRIFT_FRESH_LAG
		local most = C.DRIFT_BASE + fast * (age + C.DRIFT_LAG)
		local tight = C.DRIFT_BASE + reachIn(v, window, fast)
		local loose = C.DRIFT_BASE + reachIn(v + C.DRIFT_DV, window, fast)
		return math.min(tight, most), math.min(loose, most)
	end

	-- the first packet passed the gate: the body is its driver's
	-- (the only hand-back of a pinned body; pinned until the engine says it did: not while the body rides, when a later
	-- packet asks again)
	local function unpin(self: Movement, id: any, sq: Squirrel, now: number)
		if not sq.pinned then
			return
		end
		local engine = self.deps.engine
		if engine and engine.pin and engine.pin(id, false) == false then
			self.log:every(`unpin:{id}`, 5, "warn", `{id}: past the gate while it rides; kept until it is off`)
			return
		end
		sq.pinned = false
		local at = sq.pinAt
		sq.pinAt = nil
		if at then
			-- (the root stays where it was pinned until the driver's own updates come, a round trip on)
			sq.prior = { x = at.x, y = at.y, z = at.z, at = now }
			sq.priorUntil = math.max(sq.priorUntil, now + ignoredFor(self, id))
		end
	end

	-- motorOf(actorId): the held squirrel's motor state as its last accepted packet gave it (nil before one: the place the
	-- drift test holds the root to; the round-3 review: the last CLEAN one froze where a run of packets each with a
	-- violation too small to flag left it), the server time that packet came in, the server time of the last pounce
	-- launch a clean packet showed (nil before one), and the server time of the last clean packet. Combat/CombatService
	-- ties a bite to that launch (the motor's own, validated pounce, when the click said) and judges bites and blows where
	-- the packets have the rodent while they are fresh.
	function m.motorOf(self: Movement, actorId: any): ({ [string]: number | boolean }?, number?, number?, number?)
		local sq = self.squirrels[actorId]
		if sq == nil then
			return nil, nil, nil, nil
		end
		return sq.shot, sq.lastAt, sq.pounceAt, sq.cleanAt
	end

	-- paceOf(actorId): the body's flat pace by its accepted packets (where each put it, at the server time it came in:
	-- the pose history), the fastest Stealth/Pace.stretch; nil before a stretch's worth of them. Read only (the duel's
	-- ear, Combat/CombatService opts.paceOf: a late or bunched packet barely shows, tapping W shows its bursts)
	function m.paceOf(self: Movement, actorId: any): number?
		local h = self.histories[actorId]
		if h == nil or h.count < 2 then
			return nil
		end
		local newest = PoseHistory.newest(h)
		return Pace.stretch(function(t: number): (number, number)
			local x, _, z = PoseHistory.sample(h, t)
			return x, z
		end, newest, newest - PoseHistory.span(h))
	end

	-- clickAt(actorId, clock, now): the server time of a click the held squirrel's client made at motor clock `clock`
	-- (the duel's tell carries it), on the packets' own mapping (offsetFloor): when it was made, not when the remote
	-- carrying it got through (its own jitter). Never later than it arrived, and never more than C.CLICK_EARLY before (an
	-- older clock is a stale or made-up one). A click that says it came before the launch the server last dated, yet
	-- arrived longer after that launch than the link's jitter (measured before it) and a packet explain, is no tell for
	-- that launch: dated on its arrival (the round-3 review: the motor lunged untold and the click went once the lunge
	-- had reached the person; an honest click resent after a loss is late the same way, and loses that one pounce,
	-- logged). The click and the spread before it are kept for the pounce's date (packet). Nil when the clock is no
	-- number or no packet came yet.
	function m.clickAt(self: Movement, actorId: any, clock: any, now: number): number?
		local sq = self.squirrels[actorId]
		if sq == nil or sq.lastAt == nil or #sq.offsets == 0 then
			return nil
		end
		if type(clock) ~= "number" or not (math.abs(clock) < SquirrelWire.MAX_MAGNITUDE) then
			return nil
		end
		local spread = spreadOf(self, actorId, sq)
		sq.click = { at = now, clock = clock, spread = spread }
		local said = clock + offsetFloor(sq, now)
		local at = math.clamp(said, now - C.CLICK_EARLY, now)
		local launch = sq.pounceAt
		if launch and said < launch and now - launch > spread + C.POUNCE_GAP then
			self.log:every(
				`clicklate:{actorId}`,
				5,
				"warn",
				`{actorId}: a click arrived {now - launch} s after the launch it says it came before; dated on arrival`
			)
			return now
		end
		return at
	end

	-- clickNew(actorId, seq): is click number `seq` (1 to 255, round: Movement/SquirrelWire's clickSeq) newer than the
	-- last one taken? Takes it if so. A click rides in the Duel remote and, as a copy, in every motor packet for
	-- SquirrelWire.CLICK_COPY seconds (the round-4 review: a remote resent after a loss came too late to tie its pounce):
	-- whichever arrives first is the click, through the same gate, dating and once-per-click count; an older or the
	-- same number is a copy already taken (or one overtaken by a newer click). A remote with no number (nil) is always
	-- new.
	function m.clickNew(self: Movement, actorId: any, seq: any): boolean
		if seq == nil then
			return true
		end
		if type(seq) ~= "number" or seq < 1 or seq > 255 or seq ~= math.floor(seq) then
			return false
		end
		local sq = squirrel(self, actorId)
		local last = sq.clickSeq
		if last ~= nil then
			local d = (seq - last) % 256
			if d < 1 or d >= 128 then
				return false
			end
		end
		sq.clickSeq = seq
		return true
	end

	-- safeTarget(actorId) -> (x, y, z)?: where a Reset puts the body (feet), from where the server holds it (the last
	-- accepted packet, else the gate or the place it keeps a pinned body; never the root the client moves): the quay of
	-- the river it is in (Recovery.riverFall), else the newest place a clean grounded packet stood on a floor at least 4
	-- st across from there (Recovery.unstick), else the newest such place, else that place itself; the feet on the
	-- floor, no lift over it. nil: the server holds no place of the body
	function m.safeTarget(self: Movement, actorId: any): (number?, number?, number?)
		local sq = self.squirrels[actorId]
		if sq == nil then
			return nil, nil, nil
		end
		local last: Gate? = if sq.placed then { x = sq.lastX, y = sq.lastY, z = sq.lastZ, at = 0 } else nil
		local held: Gate? = if sq.lastAt then last else sq.gate or sq.pinAt or last
		if held == nil then
			return nil, nil, nil
		end
		local h = held :: Gate
		local qx, qy, qz = Recovery.riverFall(h.x, h.y, h.z)
		if qx and qy and qz then
			return qx, qy, qz
		end
		local s = Recovery.unstick(sq.safe, h.x, h.y, h.z) or Recovery.safePos(sq.safe)
		if s then
			return s.x, s.y, s.z
		end
		return h.x, h.y, h.z
	end

	function m.epochOf(self: Movement, actorId: any): number
		return squirrel(self, actorId).epoch
	end

	-- isPinned(actorId): the server keeps the body until its driver's first packet passes the gate (nothing else may
	-- hand it back: Movement/BodyPin)
	function m.isPinned(self: Movement, actorId: any): boolean
		local sq = self.squirrels[actorId]
		return sq ~= nil and sq.pinned
	end

	function m.teleported(self: Movement, actorId: any, x: number, y: number, z: number, why: string, now: number)
		local sq = squirrel(self, actorId)
		rebase(self, actorId, sq, { x = x, y = y, z = z, at = now })
		self._stats.teleports += 1
		local engine = self.deps.engine
		if engine then
			engine.correct(actorId, { epoch = sq.epoch, x = x, y = y, z = z, why = why, snap = false })
		end
	end

	function m.suspend(self: Movement, actorId: any, on: boolean)
		local sq = squirrel(self, actorId)
		if sq.suspended == on then
			return
		end
		sq.suspended = on
		if on then
			sq.gate = nil
			sq.lastAt = nil
			if self.deps.validator then
				self.deps.validator:reset(actorId, nil)
			end
		end
	end

	function m.watch(self: Movement, actorId: any, x: number, y: number, z: number, now: number)
		local sq = self.squirrels[actorId]
		if sq == nil or sq.suspended or not enforcing() or not finite3(x, y, z) then
			return
		end
		if sq.heldUntil then
			if now < sq.heldUntil then
				return
			end
			-- given back: where it was held, under a new epoch (and the root judged from there at once)
			local h = sq.held :: Gate
			sq.heldUntil, sq.held = nil, nil
			self:teleported(actorId, h.x, h.y, h.z, "held", now)
		end
		local gate = sq.gate
		if gate and gate.at == 0 then
			gate.at = now
		end
		if sq.pinned then
			-- the server's own body (engine.pin): nothing its driver does moves it, nothing to judge. Should it move off
			-- where it is kept all the same (a path that let it go), it is taken again and put back
			local at = sq.pinAt
			if at == nil then
				sq.pinAt = { x = x, y = y, z = z, at = now }
			elseif dist(x, y, z, at.x, at.y, at.z) > C.GATE_SLACK then
				self.log:every(
					`pinmoved:{actorId}`,
					5,
					"warn",
					`{actorId} moved while the server keeps it; taken again`
				)
				local engine = self.deps.engine
				if engine and engine.pin then
					engine.pin(actorId, true)
				end
				snap(self, actorId, "pin", now, { x = at.x, y = at.y, z = at.z, at = now })
				return
			end
			if sq.pinnedAt == 0 then
				sq.pinnedAt = now
			elseif now - sq.pinnedAt > C.PIN_LOG then
				self.log:every(`pin:{actorId}`, 30, "warn", `{actorId}: no packet past the gate in {C.PIN_LOG} s; kept`)
			end
			return
		end
		local fast = fastest(self, actorId)
		-- drift: the root against the last packet of this epoch (by the packets' own pace: driftBounds); before the
		-- epoch's first packet, against the gate (where the server put the body: from there at the pace it had, and a
		-- leap's start, since the move); for a while after a move, the place before it (the root's own updates sent
		-- before the client took the move may still come: the last packet's place, or the root's, within what the pace
		-- covers in a round trip). Not before a hand-off's first packet: the body is the server's until its driver starts
		local ok = true
		local refX, refY, refZ, refAt
		local v, lead, ping = paceOf(sq)
		local moved = sq.rootX == nil or dist(x, y, z, sq.rootX :: number, sq.rootY, sq.rootZ) > 0.05
		if sq.lastAt then
			refX, refY, refZ, refAt = sq.lastX, sq.lastY, sq.lastZ, sq.lastAt :: number
			local tight, loose = driftBounds(sq, now, fast)
			local d = dist(x, y, z, refX, refY, refZ)
			-- a root that has not moved since its last update (held up behind the packets, which came on): judged
			-- against where the packets were when it last moved, at most C.ROOT_STALE_MAX ago
			local h = self.histories[actorId]
			local movedAt = if moved then now else sq.rootMovedAt
			if d > tight and h and h.count > 0 and now - movedAt > 0 and now - movedAt <= C.ROOT_STALE_MAX then
				local ox, oy, oz = PoseHistory.sample(h, movedAt)
				if dist(x, y, z, ox, oy, oz) <= C.DRIFT_BASE + reachIn(v, lead + C.DRIFT_FRESH_LAG, fast) then
					d = 0
				end
			end
			if d > loose then
				-- (the client's own river recovery: the root on the quay a moment before the packet saying so. The rule the
				-- validator holds the packet to (Recovery.riverEntry): the quay spot of a fall into the water the body could
				-- have made from the last accepted packet, never right after a landing; the root may have walked on from
				-- the spot for C.DRIFT_FRESH_LAG)
				local shot = sq.shot
				local rid = if shot then shot.routeId else nil
				ok = shot ~= nil
					and not sq.lastRiver
					and Recovery.riverEntry(
							{
								x = refX,
								y = refY,
								z = refZ,
								vy = (shot.vy :: number?) or 0,
								onRail = type(rid) == "number" and rid >= 0,
							},
							x,
							y,
							z,
							math.min(now - refAt + C.DRIFT_LAG, SquirrelMotor.envelopeParams.maxDt),
							fast,
							SquirrelMotor.params.gravity,
							SquirrelMotor.envelopeParams.posSlack + fast * C.DRIFT_FRESH_LAG,
							C.RIVER_ROOT_RISE
						)
						~= nil
			elseif d > tight then
				-- (a leap's start the packets do not show yet: for a moment only)
				sq.overSince = sq.overSince or now
				ok = now - (sq.overSince :: number) <= C.DRIFT_PERSIST
			else
				sq.overSince = nil
			end
		elseif gate and sq.possessedAt ~= 0 then
			refX, refY, refZ, refAt = gate.x, gate.y, gate.z, gate.at
			local since = math.max(0, now - gate.at)
			ok = dist(x, y, z, refX, refY, refZ) <= C.DRIFT_BASE + reachIn(v + C.DRIFT_DV, since, fast)
		end
		local prior = sq.prior
		if not ok and prior and now <= sq.priorUntil then
			-- (never further than a gate's reach: the ping is capped, and so is what it covers)
			local window = ping + lead + C.DRIFT_FRESH_LAG
			local reach = math.min(C.DRIFT_BASE + reachIn(v, window, fast), C.GATE_SLACK + fast * C.GATE_MOVE)
			ok = dist(x, y, z, prior.x, prior.y, prior.z) <= reach
		end
		local why: string? = if ok then nil else "drift"
		if why == nil and refX and now - refAt > C.SILENT and dist(x, y, z, refX, refY, refZ) > C.SILENT_MOVE then
			why = "silent"
		end
		if why == nil then
			why = self:_rootPath(actorId, sq, x, y, z, now)
		end
		if moved then
			sq.rootMovedAt = now
		end
		sq.rootX, sq.rootY, sq.rootZ, sq.rootAt = x, y, z, now
		if why then
			snap(self, actorId, why, now, nil)
		end
	end

	-- _explained(sq, c, rail?) -> boolean: the root's crossing of a wall by a rail, ending at c, is where a packet on a
	-- rail has the body drawn (its feet on a big trunk's bark, a downspout on a wall): the packet's own drawn pose
	-- (Motion.visualPose) within a chord of c and no wall between them (over the higher end by a leap's rise), the packet
	-- within C.RAIL_RECENT of the crossing. `rail`: that packet only; else the newest C.RAILS_TRIED kept (sq.rails)
	function m._explained(
		self: Movement,
		sq: Squirrel,
		c: { at: number, x: number, y: number, z: number },
		rail: any?
	): boolean
		local validator = self.deps.validator
		local world = if validator then validator.world else nil
		if world == nil or world.crosses == nil then
			return true
		end
		local function one(r: { at: number, shot: { [string]: number | boolean } }): boolean
			if math.abs(r.at - c.at) > C.RAIL_RECENT then
				return false
			end
			local shot = r.shot
			local route = world.registry:get(shot.routeId :: number)
			if route == nil then
				return false
			end
			local vis = Motion.visualPose(
				world,
				route,
				shot.railT :: number,
				Curve.vec3(shot.x :: number, shot.y :: number, shot.z :: number),
				shot.trunkNormalX :: number,
				shot.trunkNormalZ :: number
			)
			if
				math.sqrt((vis.x - c.x) ^ 2 + (vis.z - c.z) ^ 2) > ValidatorWorld.C.MAX_CHORD
				or math.abs(vis.y - c.y) > C.RAIL_NEAR
			then
				return false
			end
			return not world.crosses(
				vis.x,
				vis.z,
				c.x,
				c.z,
				math.min(vis.y, c.y),
				math.max(vis.y, c.y),
				MoveValidator.leapRise(),
				c.y
			)
		end
		if rail then
			return one(rail)
		end
		local rails = sq.rails
		for i = #rails, math.max(1, #rails - C.RAILS_TRIED + 1), -1 do
			if one(rails[i]) then
				return true
			end
		end
		return false
	end

	-- _rootPath(actorId, sq, x, y, z, now) -> why?: the root's own path between two samples: no wall (once the epoch has
	-- settled), and high in the air with no packet fresh only on a fall
	function m._rootPath(
		self: Movement,
		actorId: any,
		sq: Squirrel,
		x: number,
		y: number,
		z: number,
		now: number
	): string?
		local validator = self.deps.validator
		local world = if validator then validator.world else nil
		if world == nil then
			return nil
		end
		local reach = C.RAIL_NEAR
		local index = world.index
		-- (the root itself near a rail: a packet on a rail with the root far from any is still judged)
		local onRail = index and index:nearest(x, y, z, reach) ~= nil
		local apex = MoveValidator.apexAllowance()
		-- walls between consecutive samples, once the epoch has settled and the town has streamed in
		local settled = sq.since ~= nil and now - (sq.since :: number) >= C.SETTLE
		local fresh = sq.possessedAt ~= nil
			and sq.possessedAt ~= 0
			and now - (sq.possessedAt :: number) < C.STREAM_GRACE
		local px = sq.rootX
		-- (a wall the root passed by a rail that no packet on a rail has explained within C.RAIL_RECENT of it: a wall)
		local crossings = sq.crossings
		for _, c in crossings do
			if now - c.at > C.RAIL_RECENT then
				table.clear(crossings)
				return "wall"
			end
		end
		-- a root by a rail (the feet drawn on a big trunk's bark, a downspout on a house's wall) may pass a wall's
		-- collider where a packet on a rail has the body drawn: every crossing by a rail is kept until a packet on a rail
		-- within C.RAIL_RECENT of it (before or after: the root may lead the packets) explains it (_explained). (The
		-- round-3 review: any packet on a rail used to turn the test off for a second, and a root walked through a wall
		-- in that second was never recorded)
		local byRail = onRail or (index and index:nearest(px or x, sq.rootY, sq.rootZ, reach) ~= nil)
		if px and settled and not fresh and now - sq.rootAt <= C.ROOT_STEP then
			local y0, y1 = math.min(sq.rootY, y), math.max(sq.rootY, y)
			-- (over the higher end, what a leap rises in the time between the samples)
			local rise = MoveValidator.leapUpAllowance() * (now - sq.rootAt)
			local crossed = world.crosses and world.crosses(px, sq.rootZ, x, z, y0, y1, rise, y)
			-- a jump of the root longer than a chord (its updates held up, or a hop): judged chord by chord, weighed as a
			-- gap is (one may be a corner rounded unseen)
			if
				not crossed
				and world.crossesLong
				and dist(px, sq.rootY, sq.rootZ, x, y, z) > ValidatorWorld.C.MAX_CHORD
				and world.crossesLong(px, sq.rootZ, x, z, y0, y1, MoveValidator.leapRise(), y)
			then
				crossed = byRail or (validator :: any):wallGap(actorId, now) >= 2
			end
			if crossed then
				if not byRail then
					return "wall"
				end
				local c = { at = now, x = x, y = y, z = z }
				if not self:_explained(sq, c, nil) then
					if #crossings >= C.CROSSINGS_MAX then
						return "wall"
					end
					table.insert(crossings, c)
				end
			end
		end
		-- the air, while no packet is fresh: a root higher above any floor than a leap may only fall
		local stale = sq.lastAt == nil or now - (sq.lastAt :: number) > C.DRIFT_FRESH
		local landable = world.landable
		if not stale or onRail or landable == nil or MoveValidator.nearTrampoline(world, x, z, 10) then
			sq.highSince = nil
			return nil
		end
		if landable(x, y, z, apex) then
			sq.highSince = nil
			return nil
		end
		if sq.highSince == nil then
			sq.highSince, sq.highY, sq.highFrom = now, y, now
			return nil
		end
		-- (from highY at highFrom: a leap's rise at most, and gravity's fall once C.HIGH_LAG after highSince has passed)
		local tau = now - sq.highFrom
		local fall = math.max(0, now - math.max((sq.highSince :: number) + C.HIGH_LAG, sq.highFrom))
		local ceiling = sq.highY
			+ 2
			+ MoveValidator.leapUpAllowance() * tau
			- 0.5 * MoveValidator.gravity() * fall * fall
		if y > ceiling then
			return "fly"
		end
		return nil
	end

	function m.packet(self: Movement, actorId: any, kind: string, packet: any, now: number): any
		self._stats.packets += 1
		local enforce = enforcing()
		local validator = self.deps.validator
		if RAIL_KINDS[kind] and validator then
			local sq = squirrel(self, actorId)
			if sq.suspended or sq.heldUntil ~= nil or (packet.epoch ~= nil and packet.epoch ~= sq.epoch) then
				-- riding, held, or sent before the client knew of the last move the server made
				self._stats.stale += 1
				local gate = sq.gate
				if
					enforce
					and not sq.suspended
					and sq.heldUntil == nil
					and gate
					and gate.at > 0
					and now - (sq.toldAt or gate.at) > ignoredFor(self, actorId)
				then
					-- long after the move it was told of: the client ignores it. Told again under the same epoch (a packet
					-- under it may be on its way: a new one would make that stale too); a run of these holds it
					sq.toldAt = now
					tell(self, actorId, sq, gate, "ignored", now)
				end
				return { ok = true, accepted = false, violations = {}, flagged = false, stale = true }
			end
			local snapshot = packet.snapshot
			if not SquirrelWire.sane(snapshot) or not (math.abs(packet.seq) < SquirrelWire.MAX_MAGNITUDE) then
				-- NaN, infinite or out of the world: never judged, never a baseline, never a snap target
				local violations =
					{ { code = "malformed", severity = 1, detail = "a number in the packet is not finite" } }
				if enforce then
					snap(self, actorId, "malformed", now, nil)
				end
				return { ok = false, accepted = false, violations = violations, flagged = true, snapped = enforce }
			end
			if sq.possessedAt == 0 then
				sq.possessedAt = now
			end
			local px, py, pz = snapshot.x :: number, snapshot.y :: number, snapshot.z :: number
			local gate = sq.gate
			if gate == nil and validator:last(actorId) == nil then
				-- (validator round 6, invariant A: a packet the validator has no baseline for is judged against a place the
				-- server holds, never taken where it says: the root the server last saw, else the last place it accepted)
				gate = anchorOf(sq)
				sq.gate = gate
				if gate == nil then
					self._stats.stale += 1
					self.log:every(
						`anchor:{actorId}`,
						5,
						"warn",
						`{actorId}: a first packet with no place to judge it from`
					)
					return { ok = true, accepted = false, violations = {}, flagged = false, stale = true }
				end
			end
			if gate and validator:last(actorId) == nil then
				if gate.at == 0 then
					gate.at = now
				end
				local span = math.min(math.max(0, now - gate.at), C.GATE_MOVE)
				local reach = C.GATE_SLACK + fastest(self, actorId) * span
				-- every field in bounds and the rail it claims where its x, y, z are, before the gate is cleared and the body
				-- handed back (the round-5 review: a field fault found after both snapped the new body to 0, 0, 0)
				-- (a fault is snapped to the gate below, as a gate failure is)
				local violations: { any } = SquirrelMotor.fieldCheck(snapshot, validator.world)
				local away = dist(px, py, pz, gate.x, gate.y, gate.z) > reach
				if away then
					table.insert(
						violations,
						{ code = "gate", severity = 1, detail = "first packet away from the body" }
					)
				elseif #violations == 0 then
					-- the move from the gate as a whole: no climb, no hanging in the air, no wall
					local from: any = { x = gate.x, y = gate.y, z = gate.z }
					if gate.snapshot then
						from.routeId = SquirrelMotor.deserialize(gate.snapshot).routeId
					end
					-- (a wall too: the client's body was put at the gate, and its first packet comes a tick or two later;
					-- the line is on a rail only with both ends near the route claimed, so a route id buys no way through)
					local next = SquirrelMotor.deserialize(snapshot)
					local falling = fallsFrom(validator, gate, next, fastest(self, actorId))
					for _, v in validator:hop(actorId, from, next, span + 0.1, now, true) do
						local code: string = v.code
						local fell = falling and code == "fly" -- (a fall from a gate high in the air: fallsFrom)
						if (v.severity >= 1 or code == "wall") and not fell then
							table.insert(violations, v)
						end
					end
				end
				if #violations > 0 then
					if enforce then
						local codes = {}
						for _, v in violations do
							table.insert(codes, v.code)
						end
						snap(self, actorId, "gate:" .. table.concat(codes, "+"), now, gate)
					end
					return { ok = false, accepted = false, violations = violations, flagged = true }
				end
				sq.gate = nil
				if not validator:hasAnchor(actorId) then
					-- (a body taken: the governor judges from where the server had it, its history from its last driver, if
					-- any, carried there: MoveValidator.takeOver)
					validator:takeOver(actorId, gate.x, gate.y, gate.z, gate.at)
				end
			end
			unpin(self, actorId, sq, now)
			-- (the link's spread and latency floor as the packets before this one showed them)
			local spread0 = spreadOf(self, actorId, sq)
			local floor0 = if #sq.offsets > 0 then offsetFloor(sq, now) else math.huge
			local v = validator:accept(actorId, packet, now)
			if v.accepted then
				PoseHistory.push(history(self, actorId), now, px, py, pz)
				-- (its pace by the speeds the validator kept, never one only the client claimed)
				pace(self, actorId, sq, validator:last(actorId) or snapshot, now)
				-- a pounce the server believes: a clean move holding a pounce-shaped launch (MoveValidator's verdict.pounce:
				-- the client clock it launched at, somewhere in the gap since the last packet) from a gap no longer than
				-- C.POUNCE_GAP and the link's spread (a packet lost, or overtaken: one later in the gap would have shown it;
				-- a longer silence hides when the lunge went). Its server time is that clock on the packets' own mapping
				-- (the lowest arrival offset of the last C.SPREAD_WINDOW: the link's latency without this packet's
				-- jitter), never later than it arrived. Combat/CombatService ties the bite to it and the click's own clock
				-- on the same mapping (clickAt), so a click and a lunge held back for a better moment are not one pounce,
				-- and the link's jitter parts neither. The spread is the one measured before the click (a client cannot
				-- widen it while it holds the lunge), and this packet's own arrival offset dates the launch when it is
				-- later than that spread above the floor explains (the round-3 review: a client that slowed its clock
				-- while it held the lunge raised its offsets, and the old low one dated the late lunge back onto the
				-- click; the click to the launch is then as long on the server's clock as on the client's)
				local click = sq.click
				local spread = spread0
				if click and now - click.at <= C.CLICK_HOLD then
					spread = math.min(spread, click.spread)
				end
				if v.ok and not v.resync and v.pounce and (v.pounceGap or math.huge) <= C.POUNCE_GAP + spread then
					local off = now - (snapshot.clock :: number)
					-- (the click and the launch in the order their clocks say, whichever arrived first: a click that says
					-- it came before this launch, yet arrived longer after the launch than the jitter and a packet explain,
					-- is no tell for it, as clickAt judges a click that arrives after its launch was dated; the round-4
					-- review held the lunge's packets back and sent the click ahead of them)
					local launch = v.pounce + math.min(floor0, off)
					local told = not (
						click
						and now - click.at <= C.CLICK_HOLD
						and click.clock <= v.pounce
						and click.at - launch > spread + C.POUNCE_GAP
					)
					if told then
						sq.pounceClock = v.pounce
						sq.pounceAt = math.min(now, v.pounce + math.max(math.min(floor0, off), off - spread))
					else
						self.log:every(
							`clicklate:{actorId}`,
							5,
							"warn",
							`{actorId}: a click arrived {(click :: any).at - launch} s after the launch it came before; untied`
						)
					end
				end
				sq.lastAt, sq.lastX, sq.lastY, sq.lastZ, sq.placed = now, px, py, pz, true
				sq.shot = snapshot
				-- (a click's copy riding in the packet, newer than the last click taken: the caller takes it as it takes
				-- the Duel remote's, clickNew counting it once; its motor clock is the packet's less its age)
				local cs = snapshot.clickSeq
				if type(cs) == "number" and cs ~= 0 then
					local last = sq.clickSeq
					local d = if last then (cs - last) % 256 else 1
					if d >= 1 and d < 128 then
						v.click =
							{ seq = cs, clock = (snapshot.clock :: number) - ((snapshot.clickAgo :: number?) or 0) }
					end
				end
				local rid = snapshot.routeId
				if type(rid) == "number" and rid >= 0 then
					sq.railAt = now
					local rails = sq.rails
					table.insert(rails, { at = now, shot = snapshot })
					while #rails > 0 and now - rails[1].at > C.RAIL_KEEP do
						table.remove(rails, 1)
					end
					-- (a crossing of the root by a rail this packet's own drawn pose explains)
					local crossings = sq.crossings
					for i = #crossings, 1, -1 do
						if self:_explained(sq, crossings[i], rails[#rails]) then
							table.remove(crossings, i)
						end
					end
				end
				if sq.since == nil then
					sq.since = now
					sq.priorUntil = math.max(sq.priorUntil, now + C.SETTLE)
				end
				if v.ok and not v.resync then
					-- (a packet after a gap too long to judge move by move is never a snap target)
					sq.good = snapshot
					sq.cleanAt = now
					-- a place a Reset may put the body back on: clean, grounded, off the rails, a floor under the feet
					-- (the server's own floor ray; validator round 7: the raw root was recorded, so a root held still in the
					-- air was "safe")
					local floorNear = validator.world.floorNear
					if
						snapshot.grounded == true
						and not (type(rid) == "number" and rid >= 0)
						and (floorNear == nil or floorNear(px, py, pz))
					then
						Recovery.record(sq.safe, now, px, py, pz, true)
					end
				end
				sq.lastRiver = v.river == true
			end
			if v.flagged then
				self._stats.flagged += 1
				if not enforce then
					self.log:every(`flag:{actorId}`, 5, "warn", `{actorId} flagged (bucket {v.bucket}); log-only`)
				end
			end
			v.correction = nil
			if enforce and v.flagged and not v.ok then
				local codes = {}
				local wallOnly = true
				for _, x in v.violations do
					table.insert(codes, x.code)
					wallOnly = wallOnly and x.code == "wall"
				end
				local fresh = sq.possessedAt ~= nil and now - (sq.possessedAt :: number) < C.STREAM_GRACE
				if wallOnly and fresh then
					-- (a house its client may not have streamed in yet: logged, the bucket emptied)
					validator:clearFlag(actorId)
					self.log:every(
						`grace:{actorId}`,
						5,
						"warn",
						`{actorId} through a wall {now - (sq.possessedAt :: number)} s after a hand-off; not snapped`
					)
				else
					snap(self, actorId, table.concat(codes, "+"), now, nil)
					v.snapped = true
				end
			end
			return v
		end
		-- generic kinds: horizontal speed against the per-kind cap
		local p = packet :: GenericPacket
		if not finite3(p.x, p.y, p.z) or not finite3(p.t, p.seq, 0) then
			return { ok = false, accepted = false, flagged = true }
		end
		local prev = self.last[actorId]
		local over = false
		if prev and p.seq > prev.seq then
			local dt = p.t - prev.t
			if dt > 1e-3 then
				local speed = math.sqrt((p.x - prev.x) ^ 2 + (p.z - prev.z) ^ 2) / dt
				local caps = self.deps.speedCaps or MovementService.DEFAULT_CAPS
				local cap = (caps[kind] or MovementService.DEFAULT_CAPS.human) * (self.deps.tolerance or 1.25)
				if speed > cap then
					over = true
					self._stats.overSpeed += 1
					self.log:every(`speed:{actorId}`, 5, "warn", `{actorId} {kind} at {speed} st/s > {cap}; log-only`)
				end
			end
		end
		if not prev or p.seq > prev.seq then
			self.last[actorId] = p
			PoseHistory.push(history(self, actorId), now, p.x, p.y, p.z)
		end
		return { ok = not over, accepted = true, flagged = over }
	end

	function m.pose(self: Movement, actorId: any, t: number): (number?, number?, number?)
		local h = self.histories[actorId]
		if not h or h.count == 0 then
			return nil, nil, nil
		end
		return PoseHistory.sample(h, t)
	end

	function m.stats(self: Movement): Stats
		return self._stats
	end

	return m
end

return MovementService
