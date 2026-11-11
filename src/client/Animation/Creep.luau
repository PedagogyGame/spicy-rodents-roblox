--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Animation.Creep
-- The Spicy Rodent's wrongness in motion (owner 2026-11-11: "just crank up that squirrels creepy
-- weirdness, even further"). A layer of small involuntary movements on top of whatever clip the body is
-- playing: the head is always cocked to one side and now and then SNAPS to a new angle and back; the jaw
-- chatters in bursts; an ear flicks; the tail whips with a kink that runs down it; the whole back
-- shudders; and it breathes too fast. Nothing here moves the body: these are joint offsets only.
--
-- Stateless and deterministic: pose(t, seed) is a pure function of the time and the body's seed. Time is
-- cut into slots per kind of movement; a hash of the slot number decides whether the movement happens in
-- that slot, when, how long, how far and which way. So every client shows the same rodent doing the same
-- thing at the same moment (t is the server's clock), and it can be tested without an engine.
-- Angles in radians on the rig's own axes (bones rest unrotated: +X right, +Y up, -Z ahead):
--   head { pitch, yaw, roll }, jaw (0 shut .. opens positive), earL, earR (flick), tail[1..8] yaw,
--   spine roll (the shudder), chest pitch (the breath).
-- Interface: pose(t, seed) -> Pose; SLOTS; apply is the caller's (AnimationDriver multiplies these onto
-- the clip's joint transforms).

local Creep = {}

export type Pose = {
	head: { pitch: number, yaw: number, roll: number },
	jaw: number,
	earL: number,
	earR: number,
	tail: { number },
	spine: number,
	chest: number,
}

-- seconds per slot, and the chance that the movement happens in a slot
Creep.SLOTS = {
	snap = { every = 1.3, chance = 0.62 }, -- the head jerk
	chatter = { every = 2.7, chance = 0.5 },
	ear = { every = 0.85, chance = 0.4 },
	whip = { every = 2.1, chance = 0.55 }, -- the tail
	shudder = { every = 3.9, chance = 0.45 },
}
Creep.TILT = 0.26 -- the cocked head, always
Creep.SNAP = 0.5 -- the largest head jerk
Creep.JAW = 0.3 -- how far the jaw drops when it chatters
Creep.TAIL_SEGMENTS = 8

-- A hash of (slot, salt, seed) in [0, 1).
local function rnd(slot: number, salt: number, seed: number): number
	local x = math.sin(slot * 127.1 + salt * 311.7 + seed * 74.7) * 43758.5453
	return x - math.floor(x)
end

-- 0 outside [a, a + d]; inside, a fast rise, a hold and a fast fall (a twitch, not a sway).
local function pulse(t: number, a: number, d: number): number
	local u = (t - a) / d
	if u <= 0 or u >= 1 then
		return 0
	end
	local edge = 0.3
	if u < edge then
		local k = u / edge
		return k * k * (3 - 2 * k)
	elseif u > 1 - edge then
		local k = (1 - u) / edge
		return k * k * (3 - 2 * k)
	end
	return 1
end

-- The movement of one kind active at time t: its strength 0..1, the slot's own random numbers, and the
-- seconds since it began (0 when idle).
local function event(
	t: number,
	seed: number,
	kind: any,
	salt: number,
	minLen: number,
	maxLen: number
): (number, number, number, number)
	local slot = math.floor(t / kind.every)
	if rnd(slot, salt, seed) >= kind.chance then
		return 0, 0, 0, 0
	end
	local length = minLen + (maxLen - minLen) * rnd(slot, salt + 1, seed)
	local start = slot * kind.every + rnd(slot, salt + 2, seed) * math.max(kind.every - length, 0)
	return pulse(t, start, length), rnd(slot, salt + 3, seed), rnd(slot, salt + 4, seed), math.max(t - start, 0)
end

function Creep.pose(t: number, seed: number): Pose
	local S = Creep.SLOTS
	-- the head: cocked, drifting a little, and now and then snapping to a new angle
	local function sideOf(slot: number): number
		return if rnd(slot, 90, seed) < 0.75 then 1 else -1
	end
	-- which way it is cocked: it changes over now and then, swinging across in a third of a second
	local sideSlot = math.floor(t / 11)
	local turn = math.clamp((t - sideSlot * 11) / 0.35, 0, 1)
	turn = turn * turn * (3 - 2 * turn)
	local side = sideOf(sideSlot - 1) + (sideOf(sideSlot) - sideOf(sideSlot - 1)) * turn
	local roll = side * Creep.TILT + 0.05 * math.sin(t * 0.7 + seed)
	local yaw = 0.04 * math.sin(t * 0.43 + seed * 2)
	local pitch = 0.03 * math.sin(t * 0.57 + seed * 3)
	local k, a, b = event(t, seed, S.snap, 10, 0.16, 0.3)
	if k > 0 then
		yaw += (a * 2 - 1) * Creep.SNAP * k
		roll += (b * 2 - 1) * Creep.SNAP * 0.7 * k
		pitch -= 0.12 * k
	end
	-- the jaw chatters: a burst of fast little bites
	local jaw = 0
	local ck, _, _, since = event(t, seed, S.chatter, 20, 0.35, 0.7)
	if ck > 0 then
		jaw = Creep.JAW * ck * (0.5 - 0.5 * math.cos(since * 2 * math.pi * 11))
	end
	-- one ear flicks
	local earL, earR = 0, 0
	local ek, which = event(t, seed, S.ear, 30, 0.07, 0.13)
	if ek > 0 then
		if which < 0.5 then
			earL = 0.55 * ek
		else
			earR = 0.55 * ek
		end
	end
	-- the tail whips: a kink that runs from the root to the tip
	local tail = table.create(Creep.TAIL_SEGMENTS, 0)
	local wk, dir, _, wsince = event(t, seed, S.whip, 40, 0.4, 0.6)
	if wk > 0 then
		local sign = if dir < 0.5 then 1 else -1
		for i = 1, Creep.TAIL_SEGMENTS do
			local u = (wsince - (i - 1) * 0.035) / 0.2
			if u > 0 and u < 1 then
				tail[i] = sign * (0.32 + 0.03 * i) * math.sin(math.pi * u)
			end
		end
	end
	-- the back shudders
	local spine = 0
	local sk, _, _, ssince = event(t, seed, S.shudder, 50, 0.3, 0.45)
	if sk > 0 then
		spine = 0.07 * sk * math.sin(ssince * 2 * math.pi * 17)
	end
	return {
		head = { pitch = pitch, yaw = yaw, roll = roll },
		jaw = jaw,
		earL = earL,
		earR = earR,
		tail = tail,
		spine = spine,
		chest = 0.02 * math.sin(t * 2 * math.pi * 3.1), -- quick, shallow breaths
	}
end

return Creep
