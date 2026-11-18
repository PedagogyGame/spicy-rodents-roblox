--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Controllers.MotorLink
-- The held squirrel's line to the server's validator (Server/Movement/MovementService, spike S3), one per player for
-- the whole session (Possession/PossessionClient owns it; Controllers/Squirrel uses it every frame):
--   * up: the motor's state (Shared/Movement/SquirrelWire) each time the motor clock has moved SEND_EVERY since the
--     last packet (20 a second at any frame rate), with a rising sequence number and the motor epoch the server last
--     gave (Possession.Granted's motorEpoch, then each Correction);
--   * down: a "Correction" is queued (offer) and taken by the controller at the top of its next frame (apply): the
--     epoch is adopted, a snap-back's snapshot restored as the motor state (the clock runs on), a move the server made
--     itself taken as the motor's place unless the motor is already within NEAR of it (the root's own move reached
--     here first and the motor restarted there);
--   * echo(): the server also moves the root; when that move reaches this client after the correction did, it is no
--     news (within ECHO_RADIUS of the corrected place, for ECHO_SECONDS) and the controller does not restart over it;
--   * the motor clock never runs back between controllers (resumeClock: a new body, the end of a ride).
-- Interface: new(send) -> Link; Link:setEpoch(n); Link:offer(msg); Link:apply(state, now) -> msg?;
--   Link:tick(state) -> boolean (sent); Link:urgent() (the next tick sends: the river recovery's own frame); Link:echo(x, y, z, hip, now) -> boolean; Link:resumeClock() -> number;
--   NEAR, ECHO_RADIUS, ECHO_SECONDS
-- Pure but for `send` (the caller's remote). No side effects on require.

local Import = require("../Import")
local SquirrelMotor = Import.shared("Movement/SquirrelMotor") :: typeof(require("../../shared/Movement/SquirrelMotor"))
local SquirrelWire = Import.shared("Movement/SquirrelWire") :: typeof(require("../../shared/Movement/SquirrelWire"))

local MotorLink = {}
MotorLink.__index = MotorLink

MotorLink.NEAR = 4
MotorLink.ECHO_RADIUS = 1.5
MotorLink.ECHO_SECONDS = 3

export type Correction = {
	epoch: number,
	x: number,
	y: number,
	z: number,
	snapshot: { [string]: number | boolean }?,
	why: string?,
	snap: boolean?,
}

export type Link = typeof(setmetatable(
	{} :: {
		send: (b: buffer) -> (),
		epoch: number,
		seq: number,
		lastClock: number,
		sentClock: number,
		pending: { Correction },
		applied: Correction?,
		appliedAt: number,
		sent: number,
	},
	MotorLink
))

function MotorLink.new(send: (b: buffer) -> ()): Link
	return setmetatable({
		send = send,
		epoch = 0,
		seq = 0,
		lastClock = 0,
		sentClock = -math.huge,
		pending = {},
		applied = nil,
		appliedAt = -math.huge,
		sent = 0,
	}, MotorLink)
end

function MotorLink.setEpoch(self: Link, n: number)
	self.epoch = n
	self.pending = {}
end

function MotorLink.offer(self: Link, msg: Correction)
	if type(msg) == "table" and type(msg.epoch) == "number" and msg.epoch >= self.epoch then
		table.insert(self.pending, msg)
	end
end

-- The clock a new controller's motor starts at: where the last one stopped.
function MotorLink.resumeClock(self: Link): number
	return self.lastClock
end

-- Takes the queued corrections into `state` (the newest wins); returns the one applied, if any.
-- (`state` is a SquirrelMotor.State: exported types do not cross the Import shim)
function MotorLink.apply(self: Link, state: any, now: number): Correction?
	if #self.pending == 0 then
		return nil
	end
	local msg = self.pending[#self.pending]
	self.pending = {}
	self.epoch = msg.epoch
	local snap = msg.snapshot
	if snap then
		local ok, restored = pcall(SquirrelMotor.deserialize, snap)
		if ok then
			local clock = state.clock
			local s = state :: any
			for k in s do
				s[k] = nil
			end
			for k, v in restored :: any do
				s[k] = v
			end
			state.clock = clock
		else
			SquirrelMotor.place(state, msg.x, msg.y, msg.z, false)
		end
	else
		local d = math.sqrt((state.x - msg.x) ^ 2 + (state.y - msg.y) ^ 2 + (state.z - msg.z) ^ 2)
		if d > MotorLink.NEAR then
			SquirrelMotor.place(state, msg.x, msg.y, msg.z, false)
		end
	end
	self.applied = msg
	self.appliedAt = now
	self.sentClock = -math.huge -- the new epoch's first packet goes now
	return msg
end

-- The next tick sends whatever the clock says (a move the motor made by itself: the river recovery).
function MotorLink.urgent(self: Link)
	self.sentClock = -math.huge
end

-- After the motor stepped: send when the clock has moved SEND_EVERY since the last packet.
function MotorLink.tick(self: Link, state: any): boolean
	self.lastClock = state.clock
	if state.clock - self.sentClock < SquirrelWire.SEND_EVERY - 1e-6 then
		return false
	end
	self.sentClock = state.clock
	self.seq += 1
	self.send(SquirrelWire.encode(self.seq, self.epoch, SquirrelMotor.serialize(state)))
	self.sent += 1
	return true
end

-- Is a root found at (x, y, z) the server's own move for the correction just applied (feet + hip)?
function MotorLink.echo(self: Link, x: number, y: number, z: number, hip: number, now: number): boolean
	local a = self.applied
	if a == nil or now - self.appliedAt > MotorLink.ECHO_SECONDS then
		return false
	end
	return math.sqrt((x - a.x) ^ 2 + (y - (a.y + hip)) ^ 2 + (z - a.z) ^ 2) <= MotorLink.ECHO_RADIUS
end

return MotorLink
