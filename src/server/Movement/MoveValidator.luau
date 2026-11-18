--!strict
-- ServerScriptService.Server.Movement.MoveValidator
-- Validates client motor packets; log-only until W7.
-- Interface (BUILD_PLAN §1.4): accept(actor, packet) -> ok, correction; pose(id, t)
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
--     real time, so the offset never falls further below its lowest of a few seconds ago (clockLag) than the
--     link's latency can swing (clockSlack); a time hack makes it fall without end. (S3's rate over a 1 s window
--     flagged a packet held up for half a second once it became the oldest of the window.)
--   * A gap too long to judge (a stall) is still bounded: no further than the fastest the squirrel can go
--     (fastest(): sprint, leap, the fastest rail with its pipe pace, the chili rush) in that time.
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
}

export type Options = {
	flagThreshold: number?, -- bucket level that flags (default 1.0)
	leakPerSecond: number?, -- bucket drain per server second (default 0.5)
	historySeconds: number?, -- pose ring length (default 1.0)
	clockSeconds: number?, -- seconds of server time the clock check keeps offsets for (default 8)
	clockLag: number?, -- the mark is the lowest offset at least this old (default 3: a 1.12 x hack still shows)
	clockSlack: number?, -- how far (s) the offset may fall below that lowest (default 0.35: 80 to 300 ms and jitter)
	boostOf: ((actorId: any) -> boolean)?, -- the server's knowledge of the chili boost (default: never)
}

type History = { clock: { number }, x: { number }, y: { number }, z: { number }, head: number, count: number }

type ClockSample = { server: number, offset: number }

type Actor = {
	last: State,
	lastSeq: number,
	lastServerTime: number,
	bucket: number,
	flagged: boolean,
	flaggedAt: number?,
	offsets: { ClockSample }, -- the lowest offset in each CLOCK_BUCKET of server time (`server` is the bucket)
	history: History,
	packets: number,
	violations: number,
	lastLaunch: number?, -- client clock of the last launch seen in the air (pounce rate)
	drops: number,
	resyncs: number,
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
		_actors: { [any]: Actor },
		_fastest: { [boolean]: number },
	},
	MoveValidator
))

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

function MoveValidator.new(world: World, opts: Options?): MoveValidator
	local o: Options = opts or {}
	local self = setmetatable({
		world = world,
		flagThreshold = o.flagThreshold or 1.0,
		leakPerSecond = o.leakPerSecond or 0.5,
		historySeconds = o.historySeconds or 1.0,
		clockSeconds = o.clockSeconds or 8,
		clockLag = o.clockLag or 3,
		clockSlack = o.clockSlack or 0.35,
		boostOf = o.boostOf or function(_actorId: any): boolean
			return false
		end,
		_actors = {} :: { [any]: Actor },
		_fastest = {},
	}, MoveValidator)
	return self
end

-- reset(actorId, snapshot, serverTime, seq?): take the given state as the baseline with a clean bucket
-- (possession, teleport, respawn, accepted correction). `snapshot` nil forgets the actor.
function MoveValidator.reset(self: MoveValidator, actorId: any, snapshot: Snapshot?, serverTime: number?, seq: number?)
	if not snapshot or not SquirrelWire.sane(snapshot) then
		self._actors[actorId] = nil
		return
	end
	local state = SquirrelMotor.deserialize(snapshot)
	local now = serverTime or 0
	local actor: Actor = {
		last = state,
		lastSeq = seq or -math.huge,
		lastServerTime = now,
		bucket = 0,
		flagged = false,
		flaggedAt = nil,
		offsets = { { server = math.floor(now / CLOCK_BUCKET), offset = now - state.clock } },
		history = newHistory(),
		packets = 0,
		violations = 0,
		lastLaunch = nil,
		drops = 0,
		resyncs = 0,
	}
	record(actor.history, state.clock, state.x, state.y, state.z)
	self._actors[actorId] = actor
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

	-- clock: the arrival offset may not fall more than the link's swing below its lowest of a while ago (a time hack
	-- runs the client clock ahead, and the offset falls a second per second at double speed); the lowest is taken
	-- over buckets at least clockLag old, so a hack's own packets never lower the mark they are held to
	local offset = serverTime - next.clock
	local buckets = actor.offsets
	local key = math.floor(serverTime / CLOCK_BUCKET)
	local newest = buckets[#buckets]
	if newest and newest.server == key then
		newest.offset = math.min(newest.offset, offset)
	else
		table.insert(buckets, { server = key, offset = offset })
	end
	while #buckets > 1 and (key - buckets[1].server) * CLOCK_BUCKET > self.clockSeconds do
		table.remove(buckets, 1)
	end
	local mark = math.huge
	for _, b in buckets do
		if (key - b.server) * CLOCK_BUCKET >= self.clockLag then
			mark = math.min(mark, b.offset)
		end
	end
	if mark == math.huge then
		mark = buckets[1].offset -- (newer than the lag: the first bucket since the baseline)
	end
	if offset < mark - self.clockSlack then
		table.insert(violations, {
			code = "clock",
			severity = 0.5,
			detail = `client clock {mark - offset} s ahead of its arrivals`,
		})
	end

	local resync = false
	local boosted = self.boostOf(actorId)
	local riverLanding = not next.routeId
		and next.grounded
		and Recovery.riverLanding(
			prev.x,
			prev.z,
			next.x,
			next.y,
			next.z,
			Motion.C.airGrab + self:fastest(actorId) * math.max(dt, 0) + 1,
			self:fastest(actorId) * math.clamp(dt, 0, SquirrelMotor.envelopeParams.maxDt) + 1
		)
	if riverLanding then
		-- the client's own river recovery (Movement/Recovery.riverFall): the quay spot is the new baseline
		resync = true
		actor.resyncs += 1
	elseif dt > SquirrelMotor.envelopeParams.maxDt then
		-- too long to judge move by move (a stall, a long loss burst): the new baseline, but no further than the
		-- fastest the squirrel goes in that time (a stall is no way to teleport)
		resync = true
		actor.resyncs += 1
		local reach = self:fastest(actorId) * dt + Motion.C.airGrab + 2
		local moved = math.sqrt((next.x - prev.x) ^ 2 + (next.z - prev.z) ^ 2)
		local rise = next.y - prev.y
		local climb = self:fastest(actorId) * dt + SquirrelMotor.leapApex() + 2
		if moved > reach or rise > climb then
			table.insert(violations, {
				code = "teleport",
				severity = 1,
				detail = `moved {moved} st (up {rise}) in a {dt} s gap (reach {reach}, climb {climb})`,
			})
		end
	elseif dt <= 0 then
		table.insert(violations, { code = "clock", severity = 1, detail = `clock went back by {-dt} s` })
	else
		local found, launchUsed = SquirrelMotor.envelope(prev, next, dt, self.world, boosted)
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
	record(actor.history, next.clock, next.x, next.y, next.z)
	return verdict(ok, true, violations, flagged, actor.bucket, correction, resync, false)
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
