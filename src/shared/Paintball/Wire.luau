--!strict
-- ReplicatedStorage.Shared.Paintball.Wire
-- The paintball wire (checklist PB-1 to PB-4, PB-7): every message on every remote, with its payload,
-- direction, reliability and rate. Net/Schemas merges REMOTES into its own table, so Shared/Net checks
-- and rate-limits all of it; nothing else may be sent. FROZEN: no lane edits this file.
-- All positions and directions are in the arena frame (Arena); all times are server time (Clock).
--
-- CLIENT TO SERVER
--   Paintball.Move  unreliable, SEND_HZ a second, 27 bytes (layout Move). The client's own pose: t (when
--                   it was sampled), seq, feet x y z, yaw, pitch, bits (BIT.crouch = wants to crouch,
--                   BIT.sprint, BIT.air). Stance and look direction ride here. Sent only while in a match.
--   Paintball.Fire  reliable, 42 bytes (layout Fire). One per click that the client's own magazine
--                   allowed: shot (the client's counter, echoed in the ack), vt and ft (Clock.stamp),
--                   the origin (the eye point) and the unit look direction.
--   Paintball.Cmd   reliable table { verb, t? }: "pass" (buy one at the desk), "join", "leave",
--                   "reload" (t = when R was pressed).
-- SERVER TO CLIENT (only to the audience: players inside Arena.AUDIENCE_MARGIN of the arena volume)
--   Paintball.Snap  unreliable buffer, SNAP_HZ a second: an 11-byte head (t, seq, n) and 13 bytes a body
--                   (id, x y z, yaw, pitch, crouch fraction, bits). Every slot of the match is in every
--                   snapshot, the reader's own included. encodeSnap / decodeSnap; the pose history holds
--                   exactly quantPose of what was sent (Clock, "the history is the snapshot stream").
--   Paintball.Shot  unreliable stream of 35-byte Shot records, one batch a server tick: a ball was
--                   born (ball id, shooter slot, birth time t = the clamped fire time, origin, velocity).
--                   Every screen but the shooter's draws that ball with Ballistics from t and plays the
--                   marker's pop at the origin; the shooter already drew its own. Losing one loses a
--                   picture, never a result.
--   Splat           RELIABLE stream of 22-byte Splat records, one batch a server tick: a ball ended on
--                   something. body = 0: on the building at x y z with the face normal `face`; body =
--                   a slot id: on that body, x y z being the offset from its feet in its own frame
--                   (toBody / fromBody), so it rides on the body. `seq` orders the pool: every client
--                   keeps the newest Rules.splatPool wall splats by seq and so holds the same ones;
--                   a body's splats stay until the match ends. A ball that hit nothing sends nothing.
--                   (Declared unreliable before this contract; reliable now, because a splat must stay
--                   on every screen: PB-4.)
--   Paintball.State reliable table { k = kind, ... }, checked by checkState against STATE:
--     pass     { ok, text, untilDay?, cents? }   the pass desk's answer
--     joined   { you, match, place, splats, now }   you are in: your slot id, the match, where the
--              arena is in the world, every splat so far (a buffer of Splat records)
--     watch    { match, place, splats, now }   you came into the audience without being in the match
--     unwatch  {}                              you left the audience: clear everything
--     left     { why, text }                   you are out of the match and back in the lobby
--     match    { match }                       the roster, the phase or the size changed (whole view)
--     tag      { by, id, ball, scores, at, x, y, z }   `by` tagged `id` out with that ball at x y z; the
--              new scores; `at` = when `id` respawns. THE hit marker and hit sound (PB-3, PB-8).
--     respawn  { id, x, y, z, yaw, at }        `id` is back at a spawn point; protected until `at`
--     ack      { shot, ok, ball?, why?, rounds, reloadAt? }   to the shooter only: the verdict on its
--              click, the server's magazine after it, and when a running reload ends
--     reload   { id, at }                      `id` began to reload, full again at `at` (the rattle)
--     refused  { what, why, text }             a "join", "pass", "reload" or "leave" was refused
--     correct  { x, y, z, yaw, why }           the server put your body back here
--     end      { card }                        the end card
--     say      { id, line, n? }                a bot's call-out (Contract.LINES)
--
-- HOW MUCH (budget(16): 8 v 8, everyone firing as fast as the magazine allows): down about 7.1 kB/s
-- (snapshots 4.4 kB/s, balls and splats 1.8 kB/s, the rest a guess at framing); up about 1.0 kB/s
-- (poses 0.5 kB/s). The contract spec holds these under 8 and 1.5 kB/s.
-- Interface: REMOTES; layouts Move, Fire, Shot, Splat, SnapHead, SnapBody; CMD_VERBS; BIT, has(bits,
--   bit); FACE, faceOf(nx, ny, nz), normalOf(face); encodeSnap(t, seq, bodies) -> buffer;
--   decodeSnap(b) -> (t?, seq, bodies); quantPose(x, y, z, crouch) -> the same four as a snapshot
--   returns them; pack(layout, records) -> buffer; unpack(layout, b) -> records; toBody, fromBody;
--   STATE, checkState(msg) -> (ok, err?); budget(bodies) -> { snap, down, up }; T (type witnesses)

local BufferCodec = require("../Util/BufferCodec")
local Schema = require("../Util/Schema")
local Clock = require("./Clock")
local Contract = require("./Contract")

-- the same shape as Net/Schemas.Def (Schemas requires this module, so it cannot be named from here)
export type Def = {
	dir: "c2s" | "s2c",
	reliable: boolean,
	rate: number?,
	burst: number?,
	payload: Schema.Schema?,
	layout: BufferCodec.Layout?,
	devOnly: boolean?,
}
export type SnapBody = {
	id: number,
	x: number,
	y: number,
	z: number,
	yaw: number,
	pitch: number,
	crouch: number,
	bits: number,
}
export type Record = { [string]: number }

local Wire = {}

-- what a q16 position can hold: wider than the arena volume (Arena.HALF 60, HEIGHT 70)
Wire.XZ = 64
Wire.Y_LO = -8
Wire.Y_HI = 88
local PI = math.pi
local PITCH = PI / 2

Wire.Move = BufferCodec.layout({
	{ name = "t", kind = "f64" },
	{ name = "seq", kind = "u16" },
	{ name = "x", kind = "f32" },
	{ name = "y", kind = "f32" },
	{ name = "z", kind = "f32" },
	{ name = "yaw", kind = "q16", lo = -PI, hi = PI },
	{ name = "pitch", kind = "q16", lo = -PITCH, hi = PITCH },
	{ name = "bits", kind = "u8" },
})

Wire.Fire = BufferCodec.layout({
	{ name = "shot", kind = "u16" },
	{ name = "vt", kind = "f64" },
	{ name = "ft", kind = "f64" },
	{ name = "ox", kind = "f32" },
	{ name = "oy", kind = "f32" },
	{ name = "oz", kind = "f32" },
	{ name = "dx", kind = "f32" },
	{ name = "dy", kind = "f32" },
	{ name = "dz", kind = "f32" },
})

Wire.Shot = BufferCodec.layout({
	{ name = "ball", kind = "u16" },
	{ name = "id", kind = "u8" },
	{ name = "t", kind = "f64" },
	{ name = "ox", kind = "f32" },
	{ name = "oy", kind = "f32" },
	{ name = "oz", kind = "f32" },
	{ name = "vx", kind = "f32" },
	{ name = "vy", kind = "f32" },
	{ name = "vz", kind = "f32" },
})

Wire.Splat = BufferCodec.layout({
	{ name = "seq", kind = "u32" },
	{ name = "ball", kind = "u16" },
	{ name = "by", kind = "u8" },
	{ name = "body", kind = "u8" },
	{ name = "team", kind = "u8" },
	{ name = "face", kind = "u8" },
	{ name = "x", kind = "f32" },
	{ name = "y", kind = "f32" },
	{ name = "z", kind = "f32" },
})

Wire.SnapHead = BufferCodec.layout({
	{ name = "t", kind = "f64" },
	{ name = "seq", kind = "u16" },
	{ name = "n", kind = "u8" },
})

Wire.SnapBody = BufferCodec.layout({
	{ name = "id", kind = "u8" },
	{ name = "x", kind = "q16", lo = -Wire.XZ, hi = Wire.XZ },
	{ name = "y", kind = "q16", lo = Wire.Y_LO, hi = Wire.Y_HI },
	{ name = "z", kind = "q16", lo = -Wire.XZ, hi = Wire.XZ },
	{ name = "yaw", kind = "q16", lo = -PI, hi = PI },
	{ name = "pitch", kind = "q16", lo = -PITCH, hi = PITCH },
	{ name = "crouch", kind = "u8" }, -- the crouch fraction x 255
	{ name = "bits", kind = "u8" },
})

Wire.CMD_VERBS = table.freeze({ "pass", "join", "leave", "reload" })

-- Flags of a pose. A client's Move may set crouch (it WANTS to crouch), sprint and air; the server
-- sets all six in snapshots (crouch there still means "wants to": the shape is the crouch fraction).
Wire.BIT = table.freeze({
	crouch = 1,
	sprint = 2,
	air = 4, -- off the floor (a jump or a fall)
	out = 8, -- tagged out, waiting to respawn: cannot fire, cannot be hit
	safe = 16, -- spawn protection: cannot fire, cannot be hit
	reload = 32, -- reloading
})

function Wire.has(bits: number, bit: number): boolean
	return bit32.band(bits, bit) ~= 0
end

-- The face of a box a wall splat is on (every solid surface is axis-aligned).
Wire.FACE = table.freeze({ none = 0, px = 1, nx = 2, py = 3, ny = 4, pz = 5, nz = 6 })

function Wire.faceOf(nx: number, ny: number, nz: number): number
	if nx > 0.5 then
		return 1
	elseif nx < -0.5 then
		return 2
	elseif ny > 0.5 then
		return 3
	elseif ny < -0.5 then
		return 4
	elseif nz > 0.5 then
		return 5
	elseif nz < -0.5 then
		return 6
	end
	return 0
end

function Wire.normalOf(face: number): (number, number, number)
	if face == 1 then
		return 1, 0, 0
	elseif face == 2 then
		return -1, 0, 0
	elseif face == 3 then
		return 0, 1, 0
	elseif face == 4 then
		return 0, -1, 0
	elseif face == 5 then
		return 0, 0, 1
	elseif face == 6 then
		return 0, 0, -1
	end
	return 0, 0, 0
end

-- A point as an offset from a body's feet in the body's own frame (CFrame.new(feet) *
-- CFrame.Angles(0, yaw, 0)), and back: how a splat on a body is carried.
function Wire.toBody(
	px: number,
	py: number,
	pz: number,
	bx: number,
	by: number,
	bz: number,
	yaw: number
): (number, number, number)
	local c, s = math.cos(yaw), math.sin(yaw)
	local dx, dz = px - bx, pz - bz
	return dx * c - dz * s, py - by, dx * s + dz * c
end

function Wire.fromBody(
	lx: number,
	ly: number,
	lz: number,
	bx: number,
	by: number,
	bz: number,
	yaw: number
): (number, number, number)
	local c, s = math.cos(yaw), math.sin(yaw)
	return bx + lx * c + lz * s, by + ly, bz - lx * s + lz * c
end

local function quant(v: number, lo: number, hi: number): number
	return BufferCodec.dequantize(BufferCodec.quantize(v, lo, hi), lo, hi)
end

local function crouchByte(c: number): number
	if c ~= c then
		return 0
	end
	return math.clamp(math.floor(c * 255 + 0.5), 0, 255)
end

-- A pose's position and crouch fraction exactly as a snapshot hands them back. The server pushes
-- THESE into the pose history, so the bodies it rewinds to are the bodies clients were sent.
function Wire.quantPose(x: number, y: number, z: number, crouch: number): (number, number, number, number)
	return quant(x, -Wire.XZ, Wire.XZ),
		quant(y, Wire.Y_LO, Wire.Y_HI),
		quant(z, -Wire.XZ, Wire.XZ),
		crouchByte(crouch) / 255
end

function Wire.encodeSnap(t: number, seq: number, bodies: { SnapBody }): buffer
	local head, each = Wire.SnapHead, Wire.SnapBody
	local n = #bodies
	local b = buffer.create(head.size + n * each.size)
	BufferCodec.encode(head, { t = t, seq = seq % 65536, n = n }, b, 0)
	local rec: Record = {}
	for i, body in bodies do
		rec.id, rec.x, rec.y, rec.z = body.id, body.x, body.y, body.z
		rec.yaw, rec.pitch, rec.bits = body.yaw, body.pitch, body.bits
		rec.crouch = crouchByte(body.crouch)
		BufferCodec.encode(each, rec, b, head.size + (i - 1) * each.size)
	end
	return b
end

-- Returns the snapshot's time (nil when the buffer is not a snapshot), its seq and its bodies.
function Wire.decodeSnap(b: any): (number?, number, { SnapBody })
	local head, each = Wire.SnapHead, Wire.SnapBody
	if typeof(b) ~= "buffer" or buffer.len(b) < head.size then
		return nil, 0, {}
	end
	local h = BufferCodec.decode(head, b, 0)
	if buffer.len(b) ~= head.size + h.n * each.size or h.t ~= h.t then
		return nil, 0, {}
	end
	local bodies: { SnapBody } = table.create(h.n)
	for i = 1, h.n do
		local r = BufferCodec.decode(each, b, head.size + (i - 1) * each.size)
		bodies[i] = {
			id = r.id,
			x = r.x,
			y = r.y,
			z = r.z,
			yaw = r.yaw,
			pitch = r.pitch,
			crouch = r.crouch / 255,
			bits = r.bits,
		}
	end
	return h.t, h.seq, bodies
end

-- Many fixed-size records in one buffer (Shot and Splat batches; the splats of "joined" and "watch").
function Wire.pack(layout: BufferCodec.Layout, records: { Record }): buffer
	local b = buffer.create(layout.size * #records)
	for i, rec in records do
		BufferCodec.encode(layout, rec, b, (i - 1) * layout.size)
	end
	return b
end

-- Empty when the buffer is not a whole number of records.
function Wire.unpack(layout: BufferCodec.Layout, b: any): { Record }
	local out: { Record } = {}
	if typeof(b) ~= "buffer" or buffer.len(b) % layout.size ~= 0 then
		return out
	end
	for i = 0, buffer.len(b) // layout.size - 1 do
		out[i + 1] = BufferCodec.decode(layout, b, i * layout.size)
	end
	return out
end

-- The reliable Paintball.State messages, by kind.
local num = Schema.num()
local function int(min: number, max: number): Schema.Schema
	return Schema.num({ min = min, max = max, int = true })
end
local function kind(k: string): Schema.Schema
	return Schema.enum({ k })
end
local function keys(t: { [string]: any }): { string }
	local out: { string } = {}
	for key in t do
		table.insert(out, key)
	end
	table.sort(out)
	return out
end
local slots = Contract.Rules.slots
local slotId = int(1, slots)
local count = int(0, 1e6)
local text = Schema.str({ max = 200 })
local name = Schema.str({ max = 40 })
local why = Schema.enum(keys(Contract.WHY))
local scores = Schema.arr(count, 2)
local bytes = Schema.custom(function(v: any): boolean
	return typeof(v) == "buffer"
end, "buffer")
local slot = Schema.rec({
	id = slotId,
	team = int(1, 2),
	name = name,
	bot = Schema.bool(),
	userId = num,
	tags = count,
	outs = count,
})
local match = Schema.rec({
	matchId = count,
	phase = Schema.enum(Contract.PHASES :: { string }),
	endsAt = num,
	size = int(Contract.Rules.teamMin, Contract.Rules.teamMax),
	scores = scores,
	slots = Schema.arr(slot, slots),
})
local place = Schema.rec({ x = num, y = num, z = num, yaw = num })
local row = Schema.rec({
	id = slotId,
	name = name,
	team = int(1, 2),
	bot = Schema.bool(),
	tags = count,
	outs = count,
	shots = count,
	hits = count,
	accuracy = Schema.num({ min = 0, max = 1 }),
})
local card = Schema.rec({
	matchId = count,
	winner = int(0, 2),
	scores = scores,
	rows = Schema.arr(row, slots),
	awards = Schema.arr(Schema.rec({ title = name, id = slotId, name = name }), 8),
	nextAt = num,
})

Wire.STATE = table.freeze({
	pass = Schema.rec({
		k = kind("pass"),
		ok = Schema.bool(),
		text = text,
		untilDay = Schema.opt(num),
		cents = Schema.opt(num),
	}),
	joined = Schema.rec({ k = kind("joined"), you = slotId, match = match, place = place, splats = bytes, now = num }),
	watch = Schema.rec({ k = kind("watch"), match = match, place = place, splats = bytes, now = num }),
	unwatch = Schema.rec({ k = kind("unwatch") }),
	left = Schema.rec({ k = kind("left"), why = why, text = text }),
	match = Schema.rec({ k = kind("match"), match = match }),
	tag = Schema.rec({
		k = kind("tag"),
		by = slotId,
		id = slotId,
		ball = int(0, 65535),
		scores = scores,
		at = num,
		x = num,
		y = num,
		z = num,
	}),
	respawn = Schema.rec({ k = kind("respawn"), id = slotId, x = num, y = num, z = num, yaw = num, at = num }),
	ack = Schema.rec({
		k = kind("ack"),
		shot = int(0, 65535),
		ok = Schema.bool(),
		ball = Schema.opt(int(0, 65535)),
		why = Schema.opt(why),
		rounds = int(0, Contract.Rules.magazine),
		reloadAt = Schema.opt(num),
	}),
	reload = Schema.rec({ k = kind("reload"), id = slotId, at = num }),
	refused = Schema.rec({
		k = kind("refused"),
		what = Schema.enum(Wire.CMD_VERBS :: { string }),
		why = why,
		text = text,
	}),
	correct = Schema.rec({ k = kind("correct"), x = num, y = num, z = num, yaw = num, why = why }),
	["end"] = Schema.rec({ k = kind("end"), card = card }),
	say = Schema.rec({ k = kind("say"), id = slotId, line = Schema.enum(keys(Contract.LINES)), n = Schema.opt(num) }),
}) :: { [string]: Schema.Schema }

-- Is this a well-formed Paintball.State message? The server lane's tests hold everything it sends to
-- this; the client lane's tests feed it only messages that pass.
function Wire.checkState(msg: any): (boolean, string?)
	if type(msg) ~= "table" or type(msg.k) ~= "string" then
		return false, "no kind"
	end
	local schema = Wire.STATE[msg.k]
	if schema == nil then
		return false, `unknown kind '{msg.k}'`
	end
	return Schema.check(schema, msg)
end

-- The remotes. Net/Schemas copies these into Schemas.REMOTES.
local REMOTES: { [string]: Def } = {
	["Paintball.Move"] = { dir = "c2s", reliable = false, rate = 30, burst = 45, layout = Wire.Move },
	["Paintball.Fire"] = { dir = "c2s", reliable = true, rate = 8, burst = 12, layout = Wire.Fire },
	["Paintball.Cmd"] = {
		dir = "c2s",
		reliable = true,
		rate = 5,
		burst = 10,
		payload = Schema.rec({ verb = Schema.enum(Wire.CMD_VERBS :: { string }), t = Schema.opt(num) }),
	},
	["Paintball.State"] = { dir = "s2c", reliable = true },
	["Paintball.Snap"] = { dir = "s2c", reliable = false },
	["Paintball.Shot"] = { dir = "s2c", reliable = false, layout = Wire.Shot },
	Splat = { dir = "s2c", reliable = true, layout = Wire.Splat },
}
Wire.REMOTES = table.freeze(REMOTES)

-- Rough bytes a second for one player in a match of `bodies` slots, everyone firing as fast as the
-- magazine allows; FRAMING is a guess at what the engine adds to each message.
function Wire.budget(bodies: number): { snap: number, down: number, up: number }
	local R = Contract.Rules
	local FRAMING = 16
	local shotsPerSec = R.magazine / ((R.magazine - 1) * R.fireInterval + R.reloadSecs)
	local snap = Wire.SnapHead.size + bodies * Wire.SnapBody.size
	local balls = shotsPerSec * bodies * (Wire.Shot.size + Wire.Splat.size)
	local down = Clock.SNAP_HZ * (snap + FRAMING) + balls + 2 * Clock.SNAP_HZ * FRAMING
	local up = Clock.SEND_HZ * (Wire.Move.size + FRAMING) + shotsPerSec * (Wire.Fire.size + FRAMING)
	return { snap = snap, down = down, up = up }
end

-- Type witnesses (see Contract.T).
Wire.T = ({} :: any) :: { Def: Def, SnapBody: SnapBody, Record: Record }

return Wire
