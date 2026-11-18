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
-- server put the body (the gate: C.GATE_SLACK and the fastest the squirrel goes since then), or it is snapped again.
-- What packets cannot show, watch() does: the server's own view of the root (a client owns its body's physics). While
-- packets come in, the root may not stray from the last accepted one by more than C.DRIFT_BASE and the fastest the
-- squirrel goes in the time since (plus C.DRIFT_LAG), once an epoch has settled (C.SETTLE after its first packet:
-- the root's own updates sent before the client took a move may still be on their way); a body that moves
-- C.SILENT_MOVE with no packet accepted for C.SILENT seconds (a client that stopped sending, or ignores its
-- correction) is snapped too, and so is one still sending under an old epoch C.IGNORED after the move it was told of. C.HOLD_AFTER snaps inside
-- C.HOLD_WINDOW, and the body is held (engine.hold: the server takes its physics and keeps it still) for
-- C.HOLD_SECONDS, then given back with a new epoch. A body on the sky lift (suspend) is not judged at all.
-- For C.STREAM_GRACE after a hand-off a wall alone does not snap (logged): the town around a new body may still be
-- streaming in on its client, and a house it has not got yet is no wall to its motor.
-- Pure over injected collaborators; no side effects on require.
-- Interface: new(deps) -> Movement; M:onHandoff(actor, player?, kind); M:packet(actorId, kind, packet, now) ->
--   Verdict?; M:teleported(actorId, x, y, z, why, now); M:suspend(actorId, on); M:watch(actorId, x, y, z, now);
--   M:epochOf(actorId) -> number; M:pose(actorId, t) -> (x, y, z)?; M:stats() -> Stats; C

local Import = require("../Import")
local Flags = Import.shared("Config/Flags") :: typeof(require("../../shared/Config/Flags"))
local Log = Import.shared("Util/Log") :: typeof(require("../../shared/Util/Log"))
local Units = Import.shared("Config/Units") :: typeof(require("../../shared/Config/Units"))
local SquirrelWire = Import.shared("Movement/SquirrelWire") :: typeof(require("../../shared/Movement/SquirrelWire"))
local PoseHistory = require("../Paintball/PoseHistory")
local MoveValidatorT = require("./MoveValidator")

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
}

export type Deps = {
	validator: MoveValidatorT.MoveValidator?, -- squirrel packets; nil = no rail validation (tests)
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
	reasons: { [string]: number },
}

type Gate = { x: number, y: number, z: number, at: number, snapshot: { [string]: number | boolean }? }

type Squirrel = {
	epoch: number,
	gate: Gate?,
	good: { [string]: number | boolean }?, -- the last clean packet's snapshot
	lastAt: number?, -- server time of the last accepted packet
	since: number?, -- server time of this epoch's first accepted packet
	possessedAt: number?, -- server time of the first packet after the hand-off (0: the hand-off, none yet)
	lastX: number,
	lastY: number,
	lastZ: number,
	suspended: boolean,
	heldUntil: number?,
	held: Gate?,
	snapTimes: { number },
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
	epochOf: (self: Movement, actorId: any) -> number,
	pose: (self: Movement, actorId: any, t: number) -> (number?, number?, number?),
	stats: (self: Movement) -> Stats,
}

local MovementService = {}

MovementService.C = table.freeze({
	GATE_SLACK = 6, -- studs: the first packet of an epoch this near where the server put the body (root or feet)
	DRIFT_BASE = 8, -- studs: the root against the last accepted packet (the drawn pose eases behind the motor)
	DRIFT_LAG = 0.6, -- seconds: how far the root may lead the packets (their jitter against the root's)
	DRIFT_FRESH = 0.5, -- seconds: packets older than this are late; the drift is then left to SILENT
	SETTLE = 1, -- seconds after an epoch's first packet before the root's drift is judged
	IGNORED = 2, -- seconds after a move the server made: packets still under the old epoch mean the client ignores it
	SILENT = 5, -- seconds with no accepted packet ...
	SILENT_MOVE = 6, -- ... while the root moved this far from the last known place: snapped
	HOLD_AFTER = 3, -- snaps ...
	HOLD_WINDOW = 10, -- ... inside this many seconds: the body is held
	HOLD_SECONDS = 2,
	STREAM_GRACE = 3, -- seconds after a hand-off's first packet in which a wall alone is logged, not snapped
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
				since = nil,
				lastX = 0,
				lastY = 0,
				lastZ = 0,
				suspended = false,
				heldUntil = nil,
				held = nil,
				snapTimes = {},
			}
			self.squirrels[id] = sq
		end
		return sq
	end

	local function fastest(self: Movement, id: any): number
		local v = self.deps.validator
		return if v then v:fastest(id) else 60
	end

	-- a new epoch from `target`: the validator forgets, the first packet of the epoch is gated there
	local function rebase(self: Movement, id: any, sq: Squirrel, target: Gate)
		sq.epoch = nextEpoch(self)
		sq.gate = target
		sq.lastAt = nil
		sq.since = nil
		sq.good = nil -- (a snap from here on goes to the gate, never back over the move)
		if self.deps.validator then
			self.deps.validator:reset(id, nil)
		end
		if self.deps.swept then
			self.deps.swept:markTeleported(id)
		end
		self.histories[id] = nil
	end

	-- snap the body back to `target` (default: the last clean packet), tell its driver, hold it after a run of snaps
	local function snap(self: Movement, id: any, why: string, now: number, target: Gate?)
		local sq = squirrel(self, id)
		local to = target
		if to == nil then
			local good = sq.good
			if good then
				to = { x = good.x :: number, y = good.y :: number, z = good.z :: number, at = now, snapshot = good }
			elseif sq.gate then
				to = sq.gate
			else
				to = { x = sq.lastX, y = sq.lastY, z = sq.lastZ, at = now }
			end
		end
		local t = to :: Gate
		local gate: Gate = { x = t.x, y = t.y, z = t.z, at = now, snapshot = t.snapshot }
		rebase(self, id, sq, gate)
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
			if #sq.snapTimes >= C.HOLD_AFTER and engine.hold and sq.heldUntil == nil then
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
		end
	end

	function m.epochOf(self: Movement, actorId: any): number
		return squirrel(self, actorId).epoch
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
			-- given back: where it was held, under a new epoch
			local h = sq.held :: Gate
			sq.heldUntil, sq.held = nil, nil
			self:teleported(actorId, h.x, h.y, h.z, "held", now)
			return
		end
		local gate = sq.gate
		if gate and gate.at == 0 then
			gate.at = now
		end
		local refX, refY, refZ, refAt
		if sq.lastAt then
			refX, refY, refZ, refAt = sq.lastX, sq.lastY, sq.lastZ, sq.lastAt :: number
		elseif gate then
			refX, refY, refZ, refAt = gate.x, gate.y, gate.z, gate.at
		else
			return
		end
		local away = dist(x, y, z, refX, refY, refZ)
		local age = now - refAt
		if age <= C.DRIFT_FRESH then
			local settled = sq.since ~= nil and now - (sq.since :: number) >= C.SETTLE
			if settled and away > C.DRIFT_BASE + fastest(self, actorId) * (age + C.DRIFT_LAG) then
				snap(self, actorId, "drift", now, nil)
			end
		elseif age > C.SILENT and away > C.SILENT_MOVE then
			snap(self, actorId, "silent", now, nil)
		end
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
					and now - gate.at > C.IGNORED
				then
					-- long after the move it was told of: the client ignores it (told again; a run of these holds it)
					snap(self, actorId, "ignored", now, gate)
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
			if gate and validator:last(actorId) == nil then
				if gate.at == 0 then
					gate.at = now
				end
				local reach = C.GATE_SLACK + fastest(self, actorId) * math.max(0, now - gate.at)
				if dist(px, py, pz, gate.x, gate.y, gate.z) > reach then
					local violations = { { code = "gate", severity = 1, detail = "first packet away from the body" } }
					if enforce then
						snap(self, actorId, "gate", now, gate)
					end
					return { ok = false, accepted = false, violations = violations, flagged = true }
				end
				sq.gate = nil
			end
			local v = validator:accept(actorId, packet, now)
			if v.accepted then
				PoseHistory.push(history(self, actorId), now, px, py, pz)
				sq.lastAt, sq.lastX, sq.lastY, sq.lastZ = now, px, py, pz
				if sq.since == nil then
					sq.since = now
				end
				if v.ok and not v.resync then
					-- (a packet after a gap too long to judge move by move is never a snap target)
					sq.good = snapshot
				end
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
