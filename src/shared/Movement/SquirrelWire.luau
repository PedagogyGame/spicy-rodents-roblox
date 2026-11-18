--!strict
-- ReplicatedStorage.Shared.Movement.SquirrelWire
-- The held squirrel's motor state on the wire (Net "Squirrel.State", client to server, unreliable): every field
-- Server/Movement/MoveValidator judges (SquirrelMotor.serialize's snapshot), a sequence number, and the motor epoch
-- the server last handed this player (Possession.Granted's `motorEpoch`, then each "Correction"). The server drops a
-- packet from an older epoch: it was sent before a teleport, a snap-back or a hand-off reached the client.
-- 162 bytes: positions, the rail parameter and the clock as f64 (the on-rail check is 0.125 studs and the clock only
-- grows), velocities and timers as f32, the four optional ids as i32 (-1 none), the flags as one byte.
-- SEND_EVERY: the client sends when its motor clock has moved this far since the last packet (20 a second at any
-- frame rate; a frame is at most SquirrelMotor.params.frameDtCap, so honest gaps are 0.05 to 0.08 s plus losses).
-- Interface: LAYOUT (Util/BufferCodec); SEND_EVERY; encode(seq, epoch, snapshot) -> buffer;
--   fromRecord(record) -> (seq, epoch, snapshot) (a record Net decoded from LAYOUT); decode(buffer) -> same;
--   sane(snapshot) -> boolean (every number finite and in range: the server judges nothing else); MAX_MAGNITUDE
-- Pure. No side effects on require.

local BufferCodec = require("../Util/BufferCodec")

local SquirrelWire = {}

SquirrelWire.SEND_EVERY = 0.05

local FLAG_BITS = { "grounded", "committedAirborne", "focus", "routeWasMoving", "alive", "winded", "bridgeActive" }
local IDS = { "routeId", "pendingFork", "selectedJunction", "emergedFrom" }
local F32 = {
	"vx",
	"vy",
	"vz",
	"yaw",
	"moveSpeed",
	"boostRemaining",
	"cooldown",
	"attack",
	"attackWindow",
	"cameraCommit",
	"trunkNormalX",
	"trunkNormalZ",
	"routeFreeLook",
	"stamina",
	"emergedEnd",
	"emergedFw",
}
local F64 = { "x", "y", "z", "railT", "clock" }
local BRIDGE = { "bfx", "bfy", "bfz", "btx", "bty", "btz", "bElapsed", "bDuration" }

local fields: { BufferCodec.Field } = {
	{ name = "seq", kind = "u32" },
	{ name = "epoch", kind = "u32" },
	{ name = "flags", kind = "u8" },
	{ name = "railDir", kind = "i8" },
}
for _, k in F64 do
	table.insert(fields, { name = k, kind = "f64" })
end
for _, k in F32 do
	table.insert(fields, { name = k, kind = "f32" })
end
for _, k in IDS do
	table.insert(fields, { name = k, kind = "i32" })
end
for _, k in BRIDGE do
	table.insert(fields, { name = k, kind = "f32" })
end
SquirrelWire.LAYOUT = BufferCodec.layout(fields)

function SquirrelWire.encode(seq: number, epoch: number, snapshot: { [string]: number | boolean }): buffer
	local rec: { [string]: number } = { seq = seq, epoch = epoch }
	local flags = 0
	for i, k in FLAG_BITS do
		if snapshot[k] == true then
			flags += bit32.lshift(1, i - 1)
		end
	end
	rec.flags = flags
	local dir = snapshot.railDir
	rec.railDir = if type(dir) == "number" and dir < 0 then -1 else 1
	for _, k in F64 do
		rec[k] = snapshot[k] :: number
	end
	for _, k in F32 do
		rec[k] = snapshot[k] :: number
	end
	for _, k in IDS do
		local v = snapshot[k]
		rec[k] = if type(v) == "number" then v else -1
	end
	if snapshot.bridgeActive == true then
		for _, k in BRIDGE do
			rec[k] = snapshot[k] :: number
		end
	end
	return BufferCodec.encode(SquirrelWire.LAYOUT, rec)
end

-- The snapshot SquirrelMotor.deserialize takes, from a record of LAYOUT's fields.
function SquirrelWire.fromRecord(rec: { [string]: number }): (number, number, { [string]: number | boolean })
	local s: { [string]: number | boolean } = {}
	local flags = rec.flags or 0
	for i, k in FLAG_BITS do
		s[k] = bit32.btest(flags, bit32.lshift(1, i - 1))
	end
	s.railDir = if (rec.railDir or 1) < 0 then -1 else 1
	for _, k in F64 do
		s[k] = rec[k] or 0
	end
	for _, k in F32 do
		s[k] = rec[k] or 0
	end
	for _, k in IDS do
		local v = rec[k] or -1
		s[k] = if v < 0 then -1 else v
	end
	if s.bridgeActive == true then
		for _, k in BRIDGE do
			s[k] = rec[k] or 0
		end
	end
	return rec.seq or 0, rec.epoch or 0, s
end

function SquirrelWire.decode(b: buffer): (number, number, { [string]: number | boolean })
	return SquirrelWire.fromRecord(BufferCodec.decode(SquirrelWire.LAYOUT, b))
end

-- The largest magnitude any number of an honest snapshot reaches (positions within the world, the clock in seconds of
-- a session, speeds and timers far below it).
SquirrelWire.MAX_MAGNITUDE = 1e7

-- sane(snapshot): every number in it is finite and within MAX_MAGNITUDE (an f64 or f32 off the wire can be NaN or
-- infinite, and a NaN passes every `>` test a judge makes). The server judges nothing else.
function SquirrelWire.sane(snapshot: { [string]: any }): boolean
	if type(snapshot) ~= "table" then
		return false
	end
	for _, v in snapshot do
		-- (NaN fails every comparison, so `not (|v| < MAX)` is true for NaN and both infinities)
		if type(v) == "number" and not (math.abs(v) < SquirrelWire.MAX_MAGNITUDE) then
			return false
		end
	end
	return type(snapshot.x) == "number"
		and type(snapshot.y) == "number"
		and type(snapshot.z) == "number"
		and type(snapshot.clock) == "number"
end

return SquirrelWire
