--!strict
-- ServerScriptService.Server.Movement.MoveValidator
-- Validates client motor packets; log-only until W7.
-- Interface (BUILD_PLAN §1.4): accept(actor, packet) -> ok, correction; pose(id, t)
--
-- The server side of D2: players move their own squirrel with the shared SquirrelMotor and stream its
-- serialized state; this module judges every transition with `SquirrelMotor.envelope` (adjacency and
-- transfer gaps against Routes/Graph, per-kind speed caps with tolerance, gravity-consistent arcs,
-- launch envelopes, wall crossings), keeps a leaky bucket of violation weight per actor, a 1 s pose
-- history for lag compensation (pose(id, t)), a pounce-rate check and a clock-rate check (the client's
-- clock may not run faster than real time beyond what jitter explains). A flagged actor gets the last
-- accepted state as its correction. Pure and steppable: no engine calls, no threads; the service that
-- owns it drains the remote queue into `accept` each frame (BUILD_PLAN §1.3 step 1) and calls `reset`
-- on possession, teleports and respawns (§1.5 step 6). Budget (spike S3): <= 0.05 ms per squirrel per
-- tick.

local Import = require("../Import")
local Motion = Import.shared("Routes/Motion") :: typeof(require("../../shared/Routes/Motion"))
local SquirrelMotor = Import.shared("Movement/SquirrelMotor") :: typeof(require("../../shared/Movement/SquirrelMotor"))

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
}

export type Options = {
	flagThreshold: number?, -- bucket level that flags (default 1.0)
	leakPerSecond: number?, -- bucket drain per server second (default 0.5)
	historySeconds: number?, -- pose ring length (default 1.0)
	clockWindow: number?, -- seconds of server time the clock-rate check looks back over (default 1.0)
	clockRatio: number?, -- client/server clock rate that flags (default 1.3; 150 ms jitter reads < 1.2)
	boostOf: ((actorId: any) -> boolean)?, -- the server's knowledge of the chili boost (default: never)
}

type History = { clock: { number }, x: { number }, y: { number }, z: { number }, head: number, count: number }

type ClockSample = { server: number, client: number }

type Actor = {
	last: State,
	lastSeq: number,
	lastServerTime: number,
	bucket: number,
	flagged: boolean,
	flaggedAt: number?,
	clockWindow: { ClockSample },
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
		clockWindow: number,
		clockRatio: number,
		boostOf: (actorId: any) -> boolean,
		_actors: { [any]: Actor },
	},
	MoveValidator
))

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
		clockWindow = o.clockWindow or 1.0,
		clockRatio = o.clockRatio or 1.3,
		boostOf = o.boostOf or function(_actorId: any): boolean
			return false
		end,
		_actors = {} :: { [any]: Actor },
	}, MoveValidator)
	return self
end

-- reset(actorId, snapshot, serverTime, seq?): take the given state as the baseline with a clean bucket
-- (possession, teleport, respawn, accepted correction). `snapshot` nil forgets the actor.
function MoveValidator.reset(self: MoveValidator, actorId: any, snapshot: Snapshot?, serverTime: number?, seq: number?)
	if not snapshot then
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
		clockWindow = { { server = now, client = state.clock } },
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

	-- clock rate: over the last `clockWindow` seconds of server time the client clock may not advance
	-- faster than real time beyond what jitter explains (a time hack doubles it)
	local cw = actor.clockWindow
	table.insert(cw, { server = serverTime, client = next.clock })
	while #cw > 2 and serverTime - cw[1].server > self.clockWindow do
		table.remove(cw, 1)
	end
	local oldest = cw[1]
	local serverSpan = serverTime - oldest.server
	if serverSpan >= self.clockWindow * 0.8 then
		local ratio = (next.clock - oldest.client) / serverSpan
		if ratio > self.clockRatio then
			table.insert(violations, {
				code = "clock",
				severity = 1,
				detail = `client clock runs at {ratio} x real time over {serverSpan} s`,
			})
		end
	end

	local resync = false
	if dt > SquirrelMotor.envelopeParams.maxDt then
		-- too long to judge (a stall, a long loss burst): take it as the new baseline, log only
		resync = true
		actor.resyncs += 1
	elseif dt <= 0 then
		table.insert(violations, { code = "clock", severity = 1, detail = `clock went back by {-dt} s` })
	else
		local found, launchUsed = SquirrelMotor.envelope(prev, next, dt, self.world, self.boostOf(actorId))
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
