--!strict
-- ReplicatedStorage.Shared.Movement.AirTrick
-- The air trick as everyone sees and hears it (owner D17, 2026-11-20: "a barrel roll and a twitch and twerk in the air
-- the squirrel can do with an extra button"; redone by D18: "barrel roll should be when you press as you land, twitch
-- wiggle re-aim ... from the moment the button is pushed mid jump"). The rule itself is the motor's
-- (Movement/SquirrelMotor: doTrick, reaim; params trick*; state trickKind, trickTime, aimYaw, aimReach; the packet
-- carries them): one button; pressed as the body lands, a barrel roll carried along the ground at the speed it landed
-- with; pressed mid-jump, once a flight, a twitch-and-wiggle, and from then the camera re-aims the rest of the jump.
-- This module is the rest:
--   * pose(kind, elapsed) -> { [bone] = { rx, ry, rz, tx?, ty?, tz? } }: the joint offsets on the hero rig's own axes
--     (+X right, +Y up, -Z ahead; rz + rolls the left side down; Animation/Liveliness's convention) that the animation
--     layer multiplies onto the clip, as Animation/AnimationDriver.heroLayers does with its other layers: the roll is a
--     whole turn of the Root about the body's long axis, eased in and out, with the back curled a little and the tail
--     wrapped; the wiggle is a cartoon shimmy, hips and tail swung side to side in a quick wave with the body shifted
--     against them and an ear-and-head twitch (side to side only: playful, never suggestive). Zero at the start and the
--     end of each move, every angle bounded (LIMIT);
--   * ATTR: the body attributes the server writes from a driver's accepted motor packets (Server/Boot/Game), so every
--     other client poses the move: AirTrick (the move: 0 none, 1 roll, 2 wiggle) and AirTrickAt (the server time it
--     began); mark(curKind, curAt, kind, left, now) -> (kind, at)? says when to write them (pure);
--   * playing(kind, at, now) -> (kind, elapsed)? reads them back; own(kind, left) -> (kind, elapsed)? reads the held
--     body's own motor (no round trip for the player's own squirrel);
--   * SOUNDS: one licensed library sound per move (docs/AUDIO_BUDGET.md), played at the body by each client.
-- Pure; no side effects on require.

local SquirrelMotor = require("./SquirrelMotor")

local AirTrick = {}

AirTrick.NONE = 0
AirTrick.ROLL = 1
AirTrick.WIGGLE = 2

AirTrick.ATTR = table.freeze({
	kind = "AirTrick",
	at = "AirTrickAt",
	-- the twitch's aim, as the server last accepted it (aimAttr: a Vector2 of the turn over its most and the reach, in
	-- twentieths), and its seed (seedOf)
	aim = "AirTrickAim",
	seed = "AirTrickSeed",
})

-- aimAttr(aimYaw, aimReach) -> (x, y): the aim as the body attribute carries it (sideways -1..1, reach -1..1, each in
-- twentieths: a write only when it moves that far)
function AirTrick.aimAttr(aimYaw: number, aimReach: number): (number, number)
	local x = math.clamp(aimYaw / SquirrelMotor.params.trickAimYaw, -1, 1)
	return math.floor(x * 20 + 0.5) / 20, math.floor(math.clamp(aimReach, -1, 1) * 20 + 0.5) / 20
end

-- one sound per move, heard at the body (ProSoundEffects, licensed; chosen by title, not heard yet)
AirTrick.SOUNDS = table.freeze({
	["AirTrick.Roll"] = "rbxassetid://9113842150", -- Cloth Whooshes Soft 1: a soft whoosh going past
	["AirTrick.Wiggle"] = "rbxassetid://9119702970", -- Swish, Paddle Swish, Soft: a quick light swish
})
AirTrick.CUE = table.freeze({ [1] = "AirTrick.Roll", [2] = "AirTrick.Wiggle" }) :: { [number]: string }
AirTrick.VOLUME = 0.45
AirTrick.SPEED = table.freeze({ [1] = 1.15, [2] = 1.35 }) :: { [number]: number }
-- studs: a move is heard and posed only this near the camera
AirTrick.RANGE = 120

-- the bounds of every offset (radians; Root's shift in studs)
AirTrick.LIMIT = table.freeze({ roll = 2 * math.pi, bend = 0.4, swing = 0.5, shift = 0.2 })

-- the shape of each move
local K = {
	curl = 0.25, -- the back curls this far (rad) at the middle of the roll
	wrap = 0.15, -- each tail segment folds this far round the roll (eight segments: the tail curls about 70 degrees)
	waves = 4, -- side-to-side swings in a wiggle
	hips = 0.35, -- the hips' swing (rad)
	hipsRoll = 0.12,
	shift = 0.12, -- the body's shift against the hips (studs)
	counter = 0.12, -- the root's counter-turn (rad)
	tail = 0.3, -- each tail segment's swing (rad), a wave running down the tail
	tailLag = 0.6, -- the wave's lag a segment (rad)
	twitch = 0.15, -- the head's twitch (rad)
	ear = 0.4,
	tailBones = 8, -- (Animation/Liveliness TAIL: the hero rig's Tail1..Tail8)
}

function AirTrick.duration(kind: number): number
	local P = SquirrelMotor.params
	return if kind == AirTrick.ROLL then P.trickRoll elseif kind == AirTrick.WIGGLE then P.trickWiggle else 0
end

-- (0 -> 1, eased in and out)
local function ease(p: number): number
	p = math.clamp(p, 0, 1)
	return p * p * (3 - 2 * p)
end

-- THE TWITCH (owner D18, 2026-11-20: "a quick spin, twist, summersault, 360 plus weird strange bizarre body-twists, a
-- variety ... based on the final aim and direction"; "all sorts of variations and combinations"; "keep side to side
-- wiggle as well as primary, and add the others in, for other situations, or angles"; "make which one occurs, partially
-- random"). A twitch is built from MOVES: the side-to-side WIGGLE (the primary), and spin (a flat 360 / 720 turn),
-- flip (a forward somersault), tuck (a back tuck), corkscrew (a roll and a turn at once), cartwheel (a sideways turn),
-- pretzel (head and hips counter-twisting), starfish (a snap open and shut) and whip (a double tail helix). Each move has
-- a WEIGHT set by the aim (weights below: the wiggle's grows as the aim gets small; a hard push sideways weights the
-- spin, out the flip, in the tuck, out-and-sideways the corkscrew, in-and-sideways the cartwheel), and the twitch's SEED
-- (seedOf: from the client clock the button was pressed at, which the motor's packet dates, so every client draws the
-- same) draws the moves from those weights (a Gumbel draw: a weighted random pick, so the same aim gives different
-- moves on different jumps). The draw is soft (a softmax over the drawn scores at TEMPERATURE), so as the aim moves
-- during the twitch the pose blends toward the move the new aim draws instead of popping. On top, the seed sometimes
-- (FLOURISH) lays a second odd move over the first, later in the twitch: combinations. The seed also sets the turn
-- count (360 or 720) and when the turn starts. The whole-body turn is one rotation about the blended axis of the turning
-- moves, of a whole number of turns at the end (the turning share is rounded over the last quarter), so the body ends
-- upright and facing its heading; every other offset is zero at both ends and held to LIMIT.

AirTrick.MOVES =
	table.freeze({ "wiggle", "spin", "flip", "tuck", "corkscrew", "cartwheel", "pretzel", "starfish", "whip" })
AirTrick.TEMPERATURE = 0.7
AirTrick.MAX_YAW = SquirrelMotor.params.trickAimYaw -- (the aim attribute's sideways is over this)
AirTrick.FLOURISH = 0.4 -- the share of twitches with a second, odd move laid over the first

-- seedOf(pressClock): the twitch's seed (an integer 0..1023) from the client clock its button was pressed at (eighths of
-- a second): the client reads its own clock, the server dates the press from the packet (clock less the wiggle's time
-- run) and writes the seed on the body for every other client.
function AirTrick.seedOf(pressClock: number): number
	return math.floor(pressClock * 8) % 1024
end

-- pressOf(clock, trickTime): the client clock a wiggle with trickTime left at `clock` was pressed at
function AirTrick.pressOf(clock: number, trickTime: number): number
	return clock - (SquirrelMotor.params.trickWiggle - trickTime)
end

-- (0 < u < 1 from a seed and a salt: an integer hash, the same everywhere)
local function hash(seed: number, salt: number): number
	local h = bit32.bxor((seed * 73856093) % 4294967296, (salt * 19349663 + 83492791) % 4294967296)
	h = (h * 1103515245 + 12345) % 2147483648
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = (h * 1103515245 + 12345) % 2147483648
	return (h + 0.5) / 2147483648
end

-- weights(sideways, reach): each move's weight for an aim (sideways -1..1: the aim's turn over its most; reach -1 in ..
-- 1 out). Pure.
function AirTrick.weights(sideways: number, reach: number): { [string]: number }
	local s = math.min(math.abs(sideways), 1)
	local o, i = math.clamp(reach, 0, 1), math.clamp(-reach, 0, 1)
	local mag = math.min(1, math.sqrt(s * s + reach * reach))
	local small = (1 - mag) ^ 2
	-- (a move that turns to a side fades out as the aim comes to the middle: it has no side to turn to there, and an aim
	-- that swings across lets it go and draws it again the other way instead of reversing it mid-turn)
	local sided = math.min(1, s / 0.5)
	return {
		wiggle = 1.6 + 6 * small,
		spin = (4 * s * s * math.max(0, 1 - o - i) + 0.06) * sided + 1e-6,
		flip = 4 * o * o * (1 - s) + 0.06,
		tuck = 4 * i * i * (1 - s) + 0.06,
		corkscrew = (5 * s * o + 0.06) * sided + 1e-6,
		cartwheel = (5 * s * i + 0.06) * sided + 1e-6,
		pretzel = 0.25 + 0.5 * small,
		starfish = 0.2 + 0.3 * mag,
		whip = 0.2 + 0.4 * s,
	}
end

-- blend(sideways, reach, seed): each move's share of the twitch (they sum to 1): the seed's weighted draw, softened.
function AirTrick.blend(sideways: number, reach: number, seed: number): { [string]: number }
	local w = AirTrick.weights(sideways, reach)
	local score: { [string]: number } = {}
	local top = -math.huge
	for k, name in AirTrick.MOVES do
		local g = -math.log(-math.log(hash(seed, k)))
		local sc = (math.log(w[name]) + g) / AirTrick.TEMPERATURE
		score[name] = sc
		top = math.max(top, sc)
	end
	local sum = 0
	for name, sc in score do
		score[name] = math.exp(sc - top)
		sum += score[name]
	end
	for name in score do
		score[name] /= sum
	end
	return score
end

-- the move a twitch mostly is (the largest share), for the specs and the owner's sheet
function AirTrick.drawn(sideways: number, reach: number, seed: number): string
	local b = AirTrick.blend(sideways, reach, seed)
	local best, at = "wiggle", -1
	for _, name in AirTrick.MOVES do
		if b[name] > at then
			best, at = name, b[name]
		end
	end
	return best
end

-- (the rig's Euler offsets {rx, ry, rz} for CFrame.Angles(rx, ry, rz) = Rx Ry Rz of a turn of `angle` about unit (x, y, z))
-- (a turn of `angle` about unit (x, y, z), as a row-major 3x3)
local function turnOf(x: number, y: number, z: number, angle: number): { number }
	local c, s = math.cos(angle), math.sin(angle)
	local t = 1 - c
	return {
		t * x * x + c,
		t * x * y - s * z,
		t * x * z + s * y,
		t * x * y + s * z,
		t * y * y + c,
		t * y * z - s * x,
		t * x * z - s * y,
		t * y * z + s * x,
		t * z * z + c,
	}
end

local function times(m: { number }, n: { number }): { number }
	local o = table.create(9, 0)
	for i = 0, 2 do
		for j = 0, 2 do
			o[i * 3 + j + 1] = m[i * 3 + 1] * n[j + 1] + m[i * 3 + 2] * n[3 + j + 1] + m[i * 3 + 3] * n[6 + j + 1]
		end
	end
	return o
end

-- (the rig's Euler offsets {rx, ry, rz} for CFrame.Angles(rx, ry, rz) = Rx Ry Rz of a rotation)
local function eulerOf(r: { number }): (number, number, number)
	return math.atan2(-r[6], r[9]), math.asin(math.clamp(r[3], -1, 1)), math.atan2(-r[2], r[1])
end

local function addTo(out: { [string]: { number } }, bone: string, rx: number, ry: number, rz: number)
	local o = out[bone]
	if o == nil then
		out[bone] = { rx, ry, rz }
	else
		o[1] += rx
		o[2] += ry
		o[3] += rz
	end
end

-- one move's offsets on the body (not its whole-body turn) at p (0..1), amplitude a, side sg (+1 / -1)
local function body(out: { [string]: { number } }, name: string, p: number, a: number, sg: number)
	if a < 1e-4 then
		return
	end
	local hump = math.sin(math.pi * math.clamp(p, 0, 1))
	local h = a * hump
	if name == "wiggle" then
		local w = math.sin(2 * math.pi * K.waves * p)
		local r = out.Root or { 0, 0, 0, 0, 0, 0 }
		r[2] = (r[2] or 0) - K.counter * h * w
		r[4] = (r[4] or 0) + K.shift * h * w
		r[5], r[6] = r[5] or 0, r[6] or 0
		r[1], r[3] = r[1] or 0, r[3] or 0
		out.Root = r
		addTo(out, "Hips", 0, K.hips * h * w, K.hipsRoll * h * w)
		for i = 1, K.tailBones do
			addTo(out, `Tail{i}`, 0, K.tail * h * math.sin(2 * math.pi * K.waves * p - i * K.tailLag), 0)
		end
		local flick = math.sin(2 * math.pi * 2 * p)
		addTo(out, "Head", 0, 0, K.twitch * h * flick)
		addTo(out, "EarL", 0, 0, K.ear * h * math.max(0, flick))
		addTo(out, "EarR", 0, 0, -K.ear * h * math.max(0, -flick))
	elseif name == "spin" then
		-- (the tail flung out by the turn, the ears laid back)
		for i = 1, K.tailBones do
			addTo(out, `Tail{i}`, 0, -sg * 0.2 * h, 0)
		end
		addTo(out, "EarL", 0, 0, 0.3 * h)
		addTo(out, "EarR", 0, 0, -0.3 * h)
		addTo(out, "Spine2", 0, sg * 0.15 * h, 0)
	elseif name == "flip" then
		-- (tucked tight over the somersault)
		addTo(out, "Spine1", -0.35 * h, 0, 0)
		addTo(out, "Spine2", -0.35 * h, 0, 0)
		addTo(out, "Head", -0.3 * h, 0, 0)
		for i = 1, K.tailBones do
			addTo(out, `Tail{i}`, 0.18 * h, 0, 0)
		end
	elseif name == "tuck" then
		-- (the back arched over the back tuck, the hips drawn in)
		addTo(out, "Spine1", 0.3 * h, 0, 0)
		addTo(out, "Spine2", 0.3 * h, 0, 0)
		addTo(out, "Head", 0.25 * h, 0, 0)
		addTo(out, "Hips", -0.3 * h, 0, 0)
	elseif name == "corkscrew" then
		-- (the body wrung: the spine twisted one way at the chest, the other at the hips, the tail in a helix)
		addTo(out, "Spine1", 0, sg * 0.3 * h, 0)
		addTo(out, "Spine2", 0, -sg * 0.3 * h, 0)
		for i = 1, K.tailBones do
			local ph = 2 * math.pi * 2 * p - i * 0.7
			addTo(out, `Tail{i}`, 0.15 * h * math.cos(ph), 0.15 * h * math.sin(ph), 0)
		end
	elseif name == "cartwheel" then
		-- (spread wide across the turn: back bent sideways, tail fanned, ears out)
		addTo(out, "Spine1", 0, 0, sg * 0.25 * h)
		addTo(out, "Spine2", 0, 0, sg * 0.25 * h)
		for i = 1, K.tailBones do
			addTo(out, `Tail{i}`, 0, 0, -sg * 0.12 * h)
		end
		addTo(out, "EarL", 0, 0, 0.35 * h)
		addTo(out, "EarR", 0, 0, -0.35 * h)
	elseif name == "pretzel" then
		-- (head and hips counter-twisting, twice)
		local w = math.sin(2 * math.pi * 2 * p)
		addTo(out, "Head", 0, 0.45 * h * w, 0)
		addTo(out, "Neck", 0, 0.2 * h * w, 0)
		addTo(out, "Hips", 0, -0.45 * h * w, 0)
		addTo(out, "Spine1", 0, -0.2 * h * w, 0.1 * h * w)
		addTo(out, "Spine2", 0, 0.2 * h * w, -0.1 * h * w)
	elseif name == "starfish" then
		-- (a snap open and shut: back arched, head up, tail fanned flat, ears out, at the twitch's middle)
		local q = math.clamp((p - 0.2) / 0.5, 0, 1)
		local snap = a * math.sin(math.pi * q) ^ 2
		addTo(out, "Spine1", 0.3 * snap, 0, 0)
		addTo(out, "Spine2", 0.3 * snap, 0, 0)
		addTo(out, "Head", 0.25 * snap, 0, 0)
		for i = 1, K.tailBones do
			addTo(out, `Tail{i}`, -0.15 * snap, 0, 0)
		end
		addTo(out, "EarL", 0, 0, 0.45 * snap)
		addTo(out, "EarR", 0, 0, -0.45 * snap)
	elseif name == "whip" then
		-- (the tail cracked round in a double helix, the hips answering)
		for i = 1, K.tailBones do
			local ph = 2 * math.pi * 4 * p - i * 0.8
			addTo(out, `Tail{i}`, 0.3 * h * math.cos(ph), 0.3 * h * math.sin(ph), 0)
		end
		addTo(out, "Hips", 0, -0.12 * h * math.sin(2 * math.pi * 4 * p), 0)
	end
end

-- the turning moves' axes (rig: +X right, +Y up, -Z ahead; a flip turns head over heels forward), side sg
local function axisOf(name: string, sg: number): (number, number, number)
	if name == "spin" then
		return 0, sg, 0
	elseif name == "flip" then
		return -1, 0, 0
	elseif name == "tuck" then
		return 1, 0, 0
	elseif name == "corkscrew" then
		return 0, sg * 0.7071, 0.7071 * sg
	elseif name == "cartwheel" then
		return 0.3, 0, sg * 0.954
	end
	return 0, 0, 0
end

-- twitch(p, sideways, reach, seed): the twitch's offsets at p (0..1) for an aim and a seed (pure).
function AirTrick.twitch(p: number, sideways: number, reach: number, seed: number): { [string]: { number } }
	local out: { [string]: { number } } = {}
	if p <= 0 or p >= 1 then
		return out
	end
	-- (the side, eased through the middle: an aim that swings across turns the other way through none, never a flip)
	local sg = math.clamp(sideways / 0.25, -1, 1)
	local b = AirTrick.blend(sideways, reach, seed)
	local mag = math.min(1, math.sqrt(sideways * sideways + reach * reach))
	local vigour = 0.6 + 0.4 * mag
	-- the whole-body turn: about the turning moves' blended axis, their share of a whole number of turns
	local ax, ay, az = 0, 0, 0
	for _, name in AirTrick.MOVES do
		local x, y, z = axisOf(name, sg)
		if x ~= 0 or y ~= 0 or z ~= 0 then
			ax += b[name] * x
			ay += b[name] * y
			az += b[name] * z
		end
	end
	local len = math.sqrt(ax * ax + ay * ay + az * az)
	-- Two whole turns at once, about u and about v: each ends where it began, so the body ends upright facing its
	-- heading whatever u and v are. v is u when the turning moves have the twitch (len 1: a double turn about u), and
	-- swings over to -u as their share falls (len 0: the two cancel, no turn at all), through stranger tumbles between;
	-- so the turn grows and shrinks with the aim's draw and never pops (the 720-degree trick: a single 360 could not
	-- shrink to none smoothly)
	local start = 0.04 + 0.12 * hash(seed, 43)
	local q = ease((p - start) / (0.86 - start))
	if q > 0 and q < 1 then
		local ux, uy, uz = 0, 1, 0
		if len > 1e-6 then
			ux, uy, uz = ax / len, ay / len, az / len
		end
		-- (w: a direction square to u, from a fixed one no axis lies along)
		local fx, fy, fz = 0.267, 0.535, 0.802
		local wx, wy, wz = uy * fz - uz * fy, uz * fx - ux * fz, ux * fy - uy * fx
		local wl = math.max(math.sqrt(wx * wx + wy * wy + wz * wz), 1e-9)
		wx, wy, wz = wx / wl, wy / wl, wz / wl
		local swing = math.pi * (1 - math.min(len, 1))
		local cs, sn = math.cos(swing), math.sin(swing)
		local vx, vy, vz = ux * cs + wx * sn, uy * cs + wy * sn, uz * cs + wz * sn
		local angle = 2 * math.pi * q
		local rx, ry, rz = eulerOf(times(turnOf(ux, uy, uz, angle), turnOf(vx, vy, vz, angle)))
		out.Root = { rx, ry, rz, 0, 0, 0 }
	end
	for _, name in AirTrick.MOVES do
		body(out, name, p, b[name] * vigour, sg)
	end
	-- a flourish: a second, odd move over the first, later in the twitch
	if hash(seed, 47) < AirTrick.FLOURISH then
		local extra = ({ "pretzel", "starfish", "whip", "wiggle" })[1 + math.floor(hash(seed, 53) * 4) % 4]
		local from = 0.25 + 0.2 * hash(seed, 59)
		body(out, extra, (p - from) / (1 - from), 0.7 * vigour, -sg)
	end
	-- bounds: every bone but the Root's turn held to LIMIT
	local L = AirTrick.LIMIT
	for bone, r in out do
		if bone ~= "Root" then
			for k = 1, 3 do
				r[k] = math.clamp(r[k], -L.swing, L.swing)
			end
		else
			r[4] = math.clamp(r[4] or 0, -L.shift, L.shift)
		end
	end
	return out
end

-- pose(kind, elapsed, aimYaw?, aimReach?, seed?): the joint offsets of move `kind` `elapsed` seconds in ({} outside
-- it): the barrel roll, or the twitch for the aim (radians, -1..1; none: no aim) and the twitch's seed (seedOf; 0).
function AirTrick.pose(
	kind: number,
	elapsed: number,
	aimYaw: number?,
	aimReach: number?,
	seed: number?
): { [string]: { number } }
	local out: { [string]: { number } } = {}
	local d = AirTrick.duration(kind)
	if d <= 0 or elapsed <= 0 or elapsed >= d then
		return out
	end
	local p = elapsed / d
	if kind ~= AirTrick.ROLL then
		local side = math.clamp((aimYaw or 0) / SquirrelMotor.params.trickAimYaw, -1, 1)
		return AirTrick.twitch(p, side, math.clamp(aimReach or 0, -1, 1), seed or 0)
	end
	local hump = math.sin(math.pi * p) -- 0 at both ends, 1 in the middle
	out.Root = { 0, 0, AirTrick.LIMIT.roll * ease(p) }
	out.Spine1 = { -K.curl * hump, 0, 0 }
	out.Spine2 = { -K.curl * hump, 0, 0 }
	for i = 1, K.tailBones do
		out[`Tail{i}`] = { K.wrap * hump, 0, 0 }
	end
	return out
end

-- onto(layers, trick): the move's offsets added onto another layer's (the offsets are small angles on the same axes,
-- as Animation/Liveliness.onto adds them; the roll is the Root's only large one and nothing else rolls the Root far)
function AirTrick.onto(layers: { [string]: { number } }, trick: { [string]: { number } }): { [string]: { number } }
	for bone, r in trick do
		local o = layers[bone]
		if o == nil then
			layers[bone] = table.clone(r)
		else
			for i = 1, math.max(#o, #r) do
				o[i] = (o[i] or 0) + (r[i] or 0)
			end
		end
	end
	return layers
end

-- The held body's own move from its motor: (kind, elapsed) while one plays, else nil.
function AirTrick.own(kind: number?, left: number?): (number?, number?)
	if kind == nil or left == nil or left <= 0 then
		return nil, nil
	end
	local d = AirTrick.duration(kind)
	if d <= 0 then
		return nil, nil
	end
	return kind, math.clamp(d - left, 0, d)
end

-- Another body's move from its attributes: (kind, elapsed) while one plays at server time `now`, else nil.
function AirTrick.playing(kind: any, at: any, now: number): (number?, number?)
	if type(kind) ~= "number" or type(at) ~= "number" then
		return nil, nil
	end
	local d = AirTrick.duration(kind)
	local e = now - at
	if d <= 0 or e < 0 or e >= d then
		return nil, nil
	end
	return kind, e
end

-- The server, on an accepted packet that says move `kind` has `left` seconds to run at server time `now`, with the body's
-- attributes at (curKind, curAt): the attributes to write, or nil when they already say so (a new move, or the same
-- move in a later flight; a move that ended or a landing writes nothing: playing() stops at its end by itself).
function AirTrick.mark(curKind: any, curAt: any, kind: number, left: number, now: number): (number?, number?)
	local d = AirTrick.duration(kind)
	if d <= 0 or left <= 0 then
		return nil, nil
	end
	local at = now - (d - math.clamp(left, 0, d))
	if curKind == kind and type(curAt) == "number" and math.abs(curAt - at) < d then
		return nil, nil
	end
	return kind, at
end

return AirTrick
