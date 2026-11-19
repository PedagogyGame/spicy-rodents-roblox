--!strict
-- ServerScriptService.Server.Movement.MoveValidator
-- Validates client motor packets; log-only until W7.
-- Interface (BUILD_PLAN §1.4): accept(actor, packet) -> ok, correction; pose(id, t); also new(world, opts); reset;
--   forget; hop; wallGap; fastest; clearFlag; isFlagged; last; stats; the shared bounds leapRise, apexAllowance,
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
}

export type Options = {
	flagThreshold: number?, -- bucket level that flags (default 1.0)
	leakPerSecond: number?, -- bucket drain per server second (default 0.5)
	historySeconds: number?, -- pose ring length (default 1.0)
	clockSeconds: number?, -- seconds of server time the clock check keeps offsets for (default 10)
	clockLag: number?, -- the mark is the lowest offset at least this old (default 3: a 1.12 x hack still shows)
	clockSlack: number?, -- how far (s) the offset may fall below that lowest (default 0.35: 80 to 300 ms and jitter)
	boostOf: ((actorId: any) -> boolean)?, -- the server's knowledge of the chili boost (default: never)
	gapMax: number?, -- gaps too long to judge move by move allowed inside gapWindow (default 4)
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
	lastLaunch: number?, -- client clock of the last launch seen in the air (pounce rate)
	drops: number,
	resyncs: number,
	lastAcceptedAt: number, -- server time of the last accepted packet
	lastOffset: number, -- its arrival offset (server time - client clock)
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
	},
	MoveValidator
))

MoveValidator.C = table.freeze({
	WALL_GAP_WINDOW = 20, -- seconds: a second gap through a wall inside this is a whole flag
	STAMINA_WALK = 1.08, -- faster than this times the walk on the ground drains the server's sprint meter
	STAMINA_GROUND = 0.6, -- studs: a packet "in the air" this near a floor ...
	STAMINA_AIR_VY = 3, -- ... with less vertical speed than this (studs/s) is on the ground for the meter
	STAMINA_SLACK = 0.5, -- how far below empty it may go (two seconds of sprint: landings' carry, rounding)
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
})

local CLOCK_BUCKET = 0.5 -- seconds of server time per clock bucket
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
		gapMax = o.gapMax or 4,
		gapWindow = o.gapWindow or 10,
		clockStepMax = o.clockStepMax or 0.9,
		pingOf = o.pingOf or function(_actorId: any): number?
			return nil
		end,
		_actors = {} :: { [any]: Actor },
		_marks = {} :: { [any]: Marks },
		_fastest = {},
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
		lastLaunch = nil,
		drops = 0,
		resyncs = 0,
		lastAcceptedAt = now,
		lastOffset = now - state.clock,
	}
	record(actor.history, state.clock, state.x, state.y, state.z)
	self._actors[actorId] = actor
end

-- forget(actorId): drop the actor and its marks (a hand-off: a new body, a new start).
function MoveValidator.forget(self: MoveValidator, actorId: any)
	self._actors[actorId] = nil
	self._marks[actorId] = nil
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
	if not actor then
		self:reset(actorId, packet.snapshot, serverTime, packet.seq)
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
	local violations: { Violation } = {}

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
	local launched = false
	local boosted = self.boostOf(actorId)
	local fastest = self:fastest(actorId)
	local riverLanding = not next.routeId
		and next.grounded
		and Recovery.riverLanding(
			prev.x,
			prev.z,
			next.x,
			next.y,
			next.z,
			Motion.C.airGrab + fastest * math.max(dtEff, 0) + 1,
			fastest * math.clamp(dtEff, 0, SquirrelMotor.envelopeParams.maxDt) + 1
		)
	if riverLanding then
		-- the client's own river recovery (Movement/Recovery.riverFall): the quay spot is the new baseline
		resync = true
		actor.resyncs += 1
	elseif dt > SquirrelMotor.envelopeParams.maxDt then
		-- too long to judge move by move (a stall, a long loss burst): the new baseline, judged as a whole (gap())
		resync = true
		actor.resyncs += 1
		self:_gap(actorId, actor, prev, next, dtEff, serverTime, violations)
	elseif dt <= 0 then
		table.insert(violations, { code = "clock", severity = 1, detail = `clock went back by {-dt} s` })
	else
		local found, launchUsed = SquirrelMotor.envelope(prev, next, dt, self.world, boosted)
		launched = launchUsed
		for _, v in found do
			table.insert(violations, v)
		end
		-- pounce rate: two launches in the air closer than the cooldown, between consecutive packets
		-- with no rail within reach (nothing could have reset the cooldown)
		local inAir = not next.routeId and not next.grounded and not prev.routeId and not prev.grounded
		if inAir and launchUsed then
			local lastLaunch = actor.lastLaunch
			if lastLaunch and dt <= SquirrelMotor.envelopeParams.shortDt then
				local gap = next.clock - lastLaunch
				if gap < SquirrelMotor.envelopeParams.pounceMinInterval then
					local reach = Motion.C.airGrab + math.sqrt(prev.vx ^ 2 + prev.vy ^ 2 + prev.vz ^ 2) * dt
					if not self.world.index:nearest(prev.x, prev.y, prev.z, reach) then
						table.insert(
							violations,
							{ code = "launch", severity = 1, detail = `two air launches {gap} s apart` }
						)
					end
				end
			end
			actor.lastLaunch = next.clock
		end
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
		violations
	)

	-- floors: a grounded body off the rails stands on something (a third of a flag: a car drawn behind the server's)
	local floorBelow = self.world.floorBelow
	if floorBelow and next.grounded and not next.routeId and not riverLanding then
		local bed = Trampoline.bedAt(self.world.trampolines or {}, next.x, next.z, next.y)
		if not bed and not floorBelow(next.x, next.y, next.z) then
			table.insert(violations, { code = "float", severity = 0.34, detail = "grounded with nothing underfoot" })
		end
	end

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
	actor.lastAcceptedAt = serverTime
	actor.lastOffset = offset
	record(actor.history, next.clock, next.x, next.y, next.z)
	local v = verdict(ok, true, violations, flagged, actor.bucket, correction, resync, false)
	v.launched = launched
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
-- route it claims, or with `along`, both ends near the route one of them claims
local function onRails(index: any, from: any, next: any, along: boolean): boolean
	if not along then
		return nearRoute(index, next.routeId, next.x, next.y, next.z)
			or nearRoute(index, from.routeId, from.x, from.y, from.z)
	end
	for _, id in { from.routeId or false, next.routeId or false } do
		if id and nearRoute(index, id, from.x, from.y, from.z) and nearRoute(index, id, next.x, next.y, next.z) then
			return true
		end
	end
	return false
end

-- hop(actorId, from, next, dt, serverTime, along?) -> violations: a move judged as a whole, not tick by tick, over `dt` (the
-- time it can stand for): a gap too long for the envelope (gap()), and the first packet after a move the server
-- made, from where it put the body (MovementService's gate). `from` holds x, y, z and routeId (nil: off the rails).
--   * reach: no further than the fastest the squirrel goes in that time (arithmetic only: a long gap costs nothing);
--   * climb: no higher than a leap (and a landing's step) above where it was, unless a rail near where it now is
--     (within its reach, never more than C.RAIL_REACH_MAX) runs as high as that less a leap (it climbed and leapt from
--     it, or is on it), or a trampoline bounced it;
--   * the air (and a body on a rail): no higher above a floor than a leap, unless such a rail or a trampoline explains it;
--   * walls: the straight line, chord by chord (world.crossesLong, its chords bounded), only when within reach (a
--     longer one is a teleport already); an honest body may have gone round a corner, so one is a third of a flag and
--     a second inside C.WALL_GAP_WINDOW a whole one. A line on the rails is not judged for walls, and a route id is
--     only a rail where that route runs (within C.ROUTE_NEAR: a made-up or far one is no rail): for a gap, an end on
--     the rail it claims; for a gate (`along`), both ends near one rail (the body put there got on it or ran along it).
-- Its cost is bounded whatever dt and the packet hold: the rail scans by C.RAIL_REACH_MAX, the walls by the chords.
function MoveValidator.hop(
	self: MoveValidator,
	actorId: any,
	from: { x: number, y: number, z: number, routeId: number? },
	next: State,
	dt: number,
	serverTime: number,
	along: boolean?
): { Violation }
	local violations: { Violation } = {}
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
	local crossesLong = world.crossesLong
	if
		crossesLong
		and moved <= reach
		and not onRails(world.index, from, next, along == true)
		and crossesLong(from.x, from.z, next.x, next.z, math.min(from.y, next.y), math.max(from.y, next.y), apex)
	then
		local n = self:wallGap(actorId, serverTime)
		table.insert(violations, {
			code = "wall",
			severity = if n >= 2 then 1 else 0.34,
			detail = `the straight line of a {dt} s gap goes through a wall ({n} in {MoveValidator.C.WALL_GAP_WINDOW} s)`,
		})
	end
	return violations
end

-- _stamina: the server's own sprint meter (the client's is its own feel, and a modified client keeps it full). Faster
-- on the ground than a walk can explain (MoveValidator.C.STAMINA_WALK times the walk) between two packets off the
-- rails drains it as the motor's sprint does (a full meter is sprintSeconds). On the ground: grounded, or a packet
-- that says it is in the air but is within C.STAMINA_GROUND of a floor with hardly a vertical speed (a client
-- flipping its grounded flag to hide a sprint); a leap or a pounce in the air is not. A gap too long to judge move by
-- move drains by its own distance over the time it stands for, and never refills. Anything else refills it by the
-- server's own time at the motor's rate (sprintRefill), so a ride, a stall or a respawn never leaves it short. The
-- server's meter never drains where the client's does not, but for a landing's carry and a sprint's slowing down
-- (a moment faster than a walk with the key let go), which C.STAMINA_SLACK covers. Below -C.STAMINA_SLACK the client
-- is sprinting on credit: half a flag a packet (a gap's span, a whole one), and the meter held there. The chili rush (boostOf) runs faster than a
-- sprint and is left out, and so is the client's own river recovery.
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
	violations: { Violation }
)
	local marks = actor.marks
	local elapsed = math.max(0, serverTime - marks.staminaAt)
	marks.staminaAt = serverTime
	local P = SquirrelMotor.params
	local C = MoveValidator.C
	local landable = self.world.landable
	local function onGround(s: State): boolean
		return s.grounded
			or (math.abs(s.vy) < C.STAMINA_AIR_VY and landable ~= nil and landable(s.x, s.y, s.z, C.STAMINA_GROUND))
	end
	local span = if unjudged then dtEff else dt
	local running = not exempt
		and dt > 0
		and span > 1e-3
		and prev.routeId == nil
		and next.routeId == nil
		and onGround(prev)
		and onGround(next)
		and math.sqrt((next.x - prev.x) ^ 2 + (next.z - prev.z) ^ 2) / span > P.walk * C.STAMINA_WALK
	if not running then
		if not unjudged then
			marks.stamina = math.min(1, marks.stamina + elapsed / P.sprintRefill)
		end
		return
	end
	marks.stamina -= span / P.sprintSeconds
	if marks.stamina < -C.STAMINA_SLACK then
		marks.stamina = -C.STAMINA_SLACK
		table.insert(violations, {
			code = "stamina",
			-- (half a flag a packet's worth of sprint on credit: a gap's whole span is a whole flag)
			severity = math.min(1, 0.5 * span / SquirrelWire.SEND_EVERY),
			detail = "faster than a walk on the ground for longer than the sprint meter lasts",
		})
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
)
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
	for _, v in self:hop(actorId, prev, next, dt, serverTime) do
		table.insert(violations, v)
	end
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
function MoveValidator.fastest(self: MoveValidator, actorId: any): number
	local boosted = self.boostOf(actorId)
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
