--!strict
-- ReplicatedStorage.Shared.Movement.AirTrick
-- The air trick as everyone sees and hears it (owner D17, 2026-11-20: "a barrel roll and a twitch and twerk in the air
-- the squirrel can do with an extra button"). The rule itself is the motor's (Movement/SquirrelMotor: params trickRoll,
-- trickWiggle, trickTurn; state trickKind, trickTime; the packet carries both): one button, only in the air; the first
-- press in a flight is a barrel roll, the second a twitch-and-wiggle, and while either plays the flight's heading swings
-- toward the keys faster, at the speed it already has. This module is the rest:
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
})

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

-- pose(kind, elapsed): the joint offsets of move `kind` `elapsed` seconds in; {} outside it.
function AirTrick.pose(kind: number, elapsed: number): { [string]: { number } }
	local out: { [string]: { number } } = {}
	local d = AirTrick.duration(kind)
	if d <= 0 or elapsed <= 0 or elapsed >= d then
		return out
	end
	local p = elapsed / d
	local hump = math.sin(math.pi * p) -- 0 at both ends, 1 in the middle
	if kind == AirTrick.ROLL then
		out.Root = { 0, 0, AirTrick.LIMIT.roll * ease(p) }
		out.Spine1 = { -K.curl * hump, 0, 0 }
		out.Spine2 = { -K.curl * hump, 0, 0 }
		for i = 1, K.tailBones do
			out[`Tail{i}`] = { K.wrap * hump, 0, 0 }
		end
	else
		local w = math.sin(2 * math.pi * K.waves * p)
		local a = hump
		out.Root = { 0, -K.counter * a * w, 0, K.shift * a * w, 0, 0 }
		out.Hips = { 0, K.hips * a * w, K.hipsRoll * a * w }
		for i = 1, K.tailBones do
			out[`Tail{i}`] = { 0, K.tail * a * math.sin(2 * math.pi * K.waves * p - i * K.tailLag), 0 }
		end
		local flick = math.sin(2 * math.pi * 2 * p)
		out.Head = { 0, 0, K.twitch * a * flick }
		out.EarL = { 0, 0, K.ear * a * math.max(0, flick) }
		out.EarR = { 0, 0, -K.ear * a * math.max(0, -flick) }
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
