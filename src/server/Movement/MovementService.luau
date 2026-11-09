--!strict
-- ServerScriptService.Server.Movement.MovementService
-- Wires movement validation for every possessed body (BUILD_PLAN §4.4 #6; §1.5 step 6; HANDOFF rule 12):
--   * squirrel-family bodies (squirrel, rodent) go through MoveValidator (spike S3) unchanged;
--   * every other kind (human, quadruped, drone, vehicle) gets a per-kind horizontal speed cap check;
--   * every body gets a 1 s pose history (Paintball/PoseHistory, the ring the arena rewinds; D29);
--   * LOG-ONLY until W7: verdicts are counted and logged (rate-limited), corrections are never sent
--     unless Flags "moveValidatorEnforce" is on;
--   * onHandoff(actor, player, kind) is Possession's hook: SweptCollision.markTeleported(actor.id) and
--     MoveValidator.reset(actor.id) plus a fresh pose history, on possess and on release.
-- Pure over injected collaborators; no side effects on require.
-- Interface: new(deps) -> Movement; M:onHandoff(actor, player?, kind); M:packet(actorId, kind, packet, now)
--            -> Verdict?; M:pose(actorId, t) -> (x, y, z)?; M:stats() -> Stats

local Import = require("../Import")
local Flags = Import.shared("Config/Flags") :: typeof(require("../../shared/Config/Flags"))
local Log = Import.shared("Util/Log") :: typeof(require("../../shared/Util/Log"))
local Units = Import.shared("Config/Units") :: typeof(require("../../shared/Config/Units"))
local PoseHistory = require("../Paintball/PoseHistory")
local MoveValidatorT = require("./MoveValidator")

export type Deps = {
	validator: MoveValidatorT.MoveValidator?, -- squirrel packets; nil = no rail validation (tests)
	swept: { markTeleported: (self: any, actorId: any) -> () }?, -- Traffic/SweptCollision instance
	historySeconds: number?, -- default 1.0 (Tunables movement.poseHistorySecs)
	historyHz: number?, -- default 60
	speedCaps: { [string]: number }?, -- studs/s per kind for the generic check
	tolerance: number?, -- multiplier on the caps (default 1.25)
}

-- Generic packets: position (studs) and the client clock.
export type GenericPacket = { seq: number, t: number, x: number, y: number, z: number }

export type Stats = { packets: number, flagged: number, overSpeed: number, handoffs: number, corrections: number }

export type Movement = {
	deps: Deps,
	histories: { [any]: PoseHistory.History },
	last: { [any]: GenericPacket },
	log: Log.Logger,
	_stats: Stats,
	onHandoff: (self: Movement, actor: any, player: any?, kind: string) -> (),
	packet: (self: Movement, actorId: any, kind: string, packet: any, now: number) -> any,
	pose: (self: Movement, actorId: any, t: number) -> (number?, number?, number?),
	stats: (self: Movement) -> Stats,
}

local MovementService = {}

-- W1 caps for the non-rail kinds (studs/s): sprinting human 16, deer/fox running, the drone's speed,
-- the fastest player vehicle (jet ski 20 u/s). Tunables-driven in W2 when the motors land.
MovementService.DEFAULT_CAPS = {
	human = 16,
	quadruped = Units.st(14),
	drone = Units.st(24),
	vehicle = Units.st(20),
} :: { [string]: number }

local RAIL_KINDS = { squirrel = true, rodent = true }

function MovementService.new(deps: Deps): Movement
	local hz = deps.historyHz or 60
	local seconds = deps.historySeconds or 1.0
	local m = {
		deps = deps,
		histories = {},
		last = {},
		log = Log.new("Movement"),
		_stats = { packets = 0, flagged = 0, overSpeed = 0, handoffs = 0, corrections = 0 },
	} :: Movement

	local function history(self: Movement, id: any): PoseHistory.History
		local h = self.histories[id]
		if not h then
			h = PoseHistory.new(seconds, hz)
			self.histories[id] = h
		end
		return h
	end

	function m.onHandoff(self: Movement, actor: any, _player: any?, _kind: string)
		local id = actor.id
		self._stats.handoffs += 1
		if self.deps.swept then
			self.deps.swept:markTeleported(id)
		end
		if self.deps.validator then
			self.deps.validator:reset(id, nil) -- forget: the next packet is the new baseline
		end
		self.histories[id] = nil
		self.last[id] = nil
	end

	function m.packet(self: Movement, actorId: any, kind: string, packet: any, now: number): any
		self._stats.packets += 1
		local enforce = Flags.enabled("moveValidatorEnforce")
		if RAIL_KINDS[kind] and self.deps.validator then
			local v = self.deps.validator:accept(actorId, packet, now)
			local snap = packet.snapshot
			if v.accepted and type(snap.x) == "number" then
				PoseHistory.push(history(self, actorId), now, snap.x :: number, snap.y :: number, snap.z :: number)
			end
			if v.flagged then
				self._stats.flagged += 1
				self.log:every(`flag:{actorId}`, 5, "warn", `{actorId} flagged (bucket {v.bucket}); log-only`)
			end
			if not enforce then
				v.correction = nil
			elseif v.correction then
				self._stats.corrections += 1
			end
			return v
		end
		-- generic kinds: horizontal speed against the per-kind cap
		local p = packet :: GenericPacket
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
