--!strict
-- ReplicatedStorage.Shared.Minigames.Paintball.Wire
-- The paintball wire (checklist PB-1 to PB-4, PB-7): every message, with its payload, direction,
-- reliability and rate. FROZEN: no lane edits this file.
-- All positions and directions are in the arena frame (Arena); all times are the shared clock (Clock).
--
-- TWO CARRIERS. Paintball is a game of the minigame registry, so what any game sends goes the
-- framework's way: verbs on Minigame.Input ("reload", and the service's own "leave"), and table
-- messages on Minigame.State through ctx.send / ctx.broadcast (KINDS below). For the real-time stream
-- it keeps FIVE REMOTES OF ITS OWN (REMOTES below; Net/Schemas merges them into its table, so
-- Shared/Net checks and rate-limits them and nothing else may be sent).
-- WHY REMOTES OF ITS OWN, when the framework's first rule is that a game has none (the lead's steer,
-- checked against the code):
--   1. Minigame.Input is reliable, a table, and carries 20 messages a second for everything a player
--      sends. A pose 20 times a second would take all of it, and a reliable ordered stream stalls
--      behind every lost packet: one loss holds every later pose, and the click behind it, for a
--      resend. A pose stream must be unreliable: a lost pose is replaced by the next one.
--   2. The framework's recipe for paintball (send verbs; the server samples the replicated Humanoid
--      bodies itself; players see each other's replicated bodies) leaves what the shooter saw outside
--      our hands: how far behind the engine draws another player's body is not told to us and moves
--      with the connection, so the rewind would be a guess, and 50 ms of error on a sprinting body is
--      1.2 studs, the radius of the hit shape. Bots have no body in the world at all (the town lends
--      none), so they need a stream of poses anyway. With ONE snapshot stream, drawn by every screen
--      for bots and people alike at a view time the client states, the server rewinds to exactly what
--      was on the shooter's screen (Clock; the keystone test of the contract spec).
--   3. Minigame.State is reliable and a table. Sixteen bodies 20 times a second as reliable tables is
--      several times the bytes and stalls on loss the same way. Snapshots and ball births are
--      unreliable buffers; splats are reliable buffers (a late joiner is sent up to 400 in one).
--   4. The click is reliable and small, but rides its own remote: its two f64 stamps arrive exact,
--      Net drops a non-finite number before any code sees it, and its rate limit is its own, so a
--      spray of clicks cannot starve Leave and nothing else can starve a click.
--   What the code showed: the steer holds. Shared/Net already carries unreliable buffer remotes with a
--   layout and a rate each (Motor.State is one), and the test rig refuses a remote only when it goes
--   through the service's own net, so the service reaches the wire through a Port (PaintballService:
--   ctx.net in the game; tests/lib/PaintballRig beside the rig). One thing changed: "Paintball.State"
--   is gone, because once the framework carries the table messages nothing is left for it.
--
-- CLIENT TO SERVER
--   Paintball.Move  unreliable, SEND_HZ a second, 27 bytes (layout Move). The client's own pose: t (when
--                   it was sampled), seq, feet x y z, yaw, pitch, bits (BIT.crouch = wants to crouch,
--                   BIT.sprint, BIT.air). Stance and look direction ride here. Sent only while seated.
--   Paintball.Fire  reliable, 42 bytes (layout Fire). One per click that the client's own magazine
--                   allowed: shot (the client's counter, echoed in the ack), vt and ft (Clock.stamp),
--                   the origin (the eye point) and the unit look direction.
--   Minigame.Input  verb "reload" { t }: R was pressed at t (the shared clock). The framework's "leave".
-- SERVER TO THE AUDIENCE (everybody near: Arena.AUDIENCE_MARGIN; the seated are always in it)
--   Paintball.Snap  unreliable buffer, SNAP_HZ a second: a 12-byte head (t, seq, match, n) and 13 bytes
--                   a body (id, x y z, yaw, pitch, crouch fraction, bits). Every slot that is on is in
--                   every snapshot, the reader's own included. encodeSnap / decodeSnap; the pose history
--                   holds exactly quantPose of what was sent (Clock, "the history is the snapshot stream").
--   Paintball.Shot  unreliable stream of 35-byte Shot records, one batch a server tick (at most
--                   SHOTS_PER_MESSAGE in one): a ball was born (ball id, shooter slot, birth time t =
--                   the clamped fire time, origin, velocity). Every screen but the shooter's draws that
--                   ball with Ballistics from t and plays the marker's pop at the origin; the shooter
--                   already drew its own. Losing one loses a picture, never a result.
--   Splat           RELIABLE stream of 22-byte Splat records, one batch a server tick: a ball ended on
--                   something. body = 0: on the building at x y z with the face normal `face`; body =
--                   a slot id: on that body, x y z being the offset from its feet in its own frame
--                   (toBody / fromBody), so it rides on the body. `seq` orders the pool: every client
--                   keeps the newest Rules.splatPool wall splats by seq and so holds the same ones;
--                   a body's splats stay until the match ends. A ball that hit nothing sends nothing.
--                   Whoever comes into the audience is sent every splat so far as one batch.
--                   (Declared unreliable before this contract; reliable now, because a splat must stay
--                   on every screen: PB-4.)
--   Minigame.State  kind "paintball_watch" { match, slots, now }: you are in the audience (sent on
--                   coming near, at each new match and when the roster changes): who is in which slot,
--                   for the puppets' colours and names; a new `match` clears every splat and ball.
--                   kind "paintball_unwatch" {}: you are out of it, or the match is over and nobody is
--                   left: clear everything. Both go by ctx.send to one player who may not be seated,
--                   so they are the game's `kinds` (ClientGame.watch hears them).
-- SERVER TO THE SEATED (Minigame.State, ctx.broadcast unless said; checkMessage holds each to KINDS)
--   the framework's "state"  view.game = Contract.MatchView (roster, phase, clock, scores) and the
--                   service's Contract.Extras (match, bots, your magazine); view.result at the end card
--   paintball_tag      { by, id, ball, scores, at, x, y, z }   `by` tagged `id` out with that ball at
--                      x y z; the new scores; `at` = when `id` respawns. THE hit marker and hit sound
--                      (PB-3, PB-8).
--   paintball_respawn  { id, x, y, z, yaw, at }   `id` stands at a spawn point; protected until `at`
--   paintball_reload   { id, at }                 `id` began to reload, full again at `at` (the rattle)
--   paintball_say      { id, line, n? }           a bot's call-out (Contract.LINES)
--   paintball_ack      { shot, ok, ball?, why?, rounds, reloadAt? }   to the shooter only (ctx.send): the
--                      verdict on its click, the server's magazine after it, when a running reload ends
--   paintball_correct  { x, y, z, yaw, why }      to one player (ctx.send): the server put your body here
--
-- HOW MUCH (budget(16): 8 v 8, everyone firing as fast as the magazine allows): down about 7.1 kB/s
-- (snapshots 4.4 kB/s, balls and splats 1.8 kB/s, the rest a guess at framing); up about 1.0 kB/s
-- (poses 0.5 kB/s). The contract spec holds these under 8 and 1.5 kB/s. The framework's "state" (about
-- 1 kB once a second) is on top of that.
-- Interface: REMOTES; layouts Move, Fire, Shot, Splat, SnapHead, SnapBody; SHOTS_PER_MESSAGE; VERBS;
--   BIT, has(bits, bit); FACE, faceOf(nx, ny, nz), normalOf(face); encodeSnap(t, seq, match, bodies)
--   -> buffer; decodeSnap(b) -> (t?, seq, match, bodies); quantPose(x, y, z, crouch) -> the same four
--   as a snapshot returns them; between(a, ta, b, tb, t) -> (x, y, z, crouch); pack(layout, records)
--   -> buffer; unpack(layout, b) -> records; toBody, fromBody; KINDS, EVERYONE_KINDS, checkMessage(msg)
--   -> (ok, err?); budget(bodies) -> { snap, down, up }; T (type witnesses)

local BufferCodec = require("../../Util/BufferCodec")
local Schema = require("../../Util/Schema")
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
-- who holds a slot, for the audience ("paintball_watch")
export type Watched = { id: number, team: number, name: string, bot: boolean }

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
	{ name = "match", kind = "u8" }, -- Extras.match % 256: a reader that sees it change clears its splats
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

-- An unreliable message over about 900 bytes is not delivered: a Shot batch is cut to this many records
-- (a full snapshot is 220 bytes).
Wire.SHOTS_PER_MESSAGE = 25

-- Paintball's verbs on Minigame.Input (the Spec's `verbs`, which is what puts them on the Net schema).
--   reload { t }   R was pressed at t (the shared clock); refused with words when it does nothing
Wire.VERBS = table.freeze({ "reload" })

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

function Wire.encodeSnap(t: number, seq: number, match: number, bodies: { SnapBody }): buffer
	local head, each = Wire.SnapHead, Wire.SnapBody
	local n = #bodies
	local b = buffer.create(head.size + n * each.size)
	BufferCodec.encode(head, { t = t, seq = seq % 65536, match = match % 256, n = n }, b, 0)
	local rec: Record = {}
	for i, body in bodies do
		rec.id, rec.x, rec.y, rec.z = body.id, body.x, body.y, body.z
		rec.yaw, rec.pitch, rec.bits = body.yaw, body.pitch, body.bits
		rec.crouch = crouchByte(body.crouch)
		BufferCodec.encode(each, rec, b, head.size + (i - 1) * each.size)
	end
	return b
end

-- Returns the snapshot's time (nil when the buffer is not a snapshot), its seq, its match and its bodies.
function Wire.decodeSnap(b: any): (number?, number, number, { SnapBody })
	local head, each = Wire.SnapHead, Wire.SnapBody
	if typeof(b) ~= "buffer" or buffer.len(b) < head.size then
		return nil, 0, 0, {}
	end
	local h = BufferCodec.decode(head, b, 0)
	if buffer.len(b) ~= head.size + h.n * each.size or h.t ~= h.t then
		return nil, 0, 0, {}
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
	return h.t, h.seq, h.match, bodies
end

-- THE interpolation: a body's position and crouch fraction at time t from the snapshots either side
-- of it (a at ta, the older; b at tb), in a straight line, held at b when t is past it and at a when
-- t is before it. This is the arithmetic of Server/Paintball/PoseHistory.sample, so a client that
-- draws with it shows exactly the bodies the server rewinds to (the contract spec proves the two
-- equal). Yaw and pitch are the drawer's to smooth: no hit depends on them.
function Wire.between(a: SnapBody, ta: number, b: SnapBody, tb: number, t: number): (number, number, number, number)
	if t >= tb then
		return b.x, b.y, b.z, b.crouch
	elseif t <= ta then
		return a.x, a.y, a.z, a.crouch
	end
	local f = (t - ta) / (tb - ta)
	return a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f, a.z + (b.z - a.z) * f, a.crouch + (b.crouch - a.crouch) * f
end

-- Many fixed-size records in one buffer (Shot and Splat batches).
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

-- Paintball's own kinds on Minigame.State (the framework's are joined, state, event, left, refused).
-- The framework adds `station` to each (and `site` to one sent to everyone); every kind allows both.
local num = Schema.num()
local function int(min: number, max: number): Schema.Schema
	return Schema.num({ min = min, max = max, int = true })
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
local why = Schema.enum(keys(Contract.WHY))
local scores = Schema.arr(count, 2)
local function message(kind: string, fields: { [string]: Schema.Schema }): Schema.Schema
	fields.kind = Schema.enum({ kind })
	fields.station = Schema.opt(Schema.str({ max = 64 }))
	fields.site = Schema.opt(Schema.str({ max = 64 }))
	return Schema.rec(fields)
end

Wire.KINDS = table.freeze({
	paintball_watch = message("paintball_watch", {
		match = count,
		slots = Schema.arr(
			Schema.rec({ id = slotId, team = int(1, 2), name = Schema.str({ max = 60 }), bot = Schema.bool() }),
			slots
		),
		now = num,
	}),
	paintball_unwatch = message("paintball_unwatch", {}),
	paintball_tag = message("paintball_tag", {
		by = slotId,
		id = slotId,
		ball = int(0, 65535),
		scores = scores,
		at = num,
		x = num,
		y = num,
		z = num,
	}),
	paintball_respawn = message("paintball_respawn", { id = slotId, x = num, y = num, z = num, yaw = num, at = num }),
	paintball_reload = message("paintball_reload", { id = slotId, at = num }),
	paintball_say = message("paintball_say", {
		id = slotId,
		line = Schema.enum(keys(Contract.LINES)),
		n = Schema.opt(num),
	}),
	paintball_ack = message("paintball_ack", {
		shot = int(0, 65535),
		ok = Schema.bool(),
		ball = Schema.opt(int(0, 65535)),
		why = Schema.opt(why),
		rounds = int(0, Contract.Rules.magazine),
		reloadAt = Schema.opt(num),
	}),
	paintball_correct = message("paintball_correct", { x = num, y = num, z = num, yaw = num, why = why }),
}) :: { [string]: Schema.Schema }

-- The kinds that go to players who may not be seated (ctx.send to each of the audience): the client
-- half lists exactly these as its `kinds`, so ClientGame.watch hears them.
Wire.EVERYONE_KINDS = table.freeze({ "paintball_watch", "paintball_unwatch" })

-- Is this a well-formed paintball message for Minigame.State? The server lane's tests hold everything
-- it sends to this; the client lane's tests feed it only messages that pass.
function Wire.checkMessage(msg: any): (boolean, string?)
	if type(msg) ~= "table" or type(msg.kind) ~= "string" then
		return false, "no kind"
	end
	local schema = Wire.KINDS[msg.kind]
	if schema == nil then
		return false, `unknown kind '{msg.kind}'`
	end
	return Schema.check(schema, msg)
end

-- The remotes of paintball's own. Net/Schemas copies these into Schemas.REMOTES.
local REMOTES: { [string]: Def } = {
	["Paintball.Move"] = { dir = "c2s", reliable = false, rate = 30, burst = 45, layout = Wire.Move },
	["Paintball.Fire"] = { dir = "c2s", reliable = true, rate = 8, burst = 12, layout = Wire.Fire },
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
Wire.T = ({} :: any) :: { Def: Def, SnapBody: SnapBody, Record: Record, Watched: Watched }

return Wire
