--!strict
-- ReplicatedStorage.Shared.Items.KiteFlight
-- The corner store's kite in the air, as numbers (the owner, 18 November: "make the steering for the kite quite
-- basic"). The server flies it (Server/Items/ItemWorld, every 0.1 s); the flier's client only says which way the
-- keys point (Client/UI/KiteSteer) and the server clamps that. No tricks, no loops, no physics string.
--   lean     -1 .. 1: the kite across the wind, to the flier's left or right (A/D, the left stick, the touch
--            arrows); it follows the held key at LEAN_RATE and settles back to the wind's centre at the same rate
--            when let go. At full lean it is MAX_LEAN round from straight downwind and a little lower (DIP).
--   length   the string, MIN_LENGTH .. MAX_LENGTH studs (W lets it out, S reels it in, REEL_RATE studs a second);
--            it starts at LENGTH and stays where it is left.
--   sway     the small wobble it always had (SWAY studs at SWAY_HZ), on top of the lean.
-- The steer input: { x, y } each -1 .. 1 (anything else counts as 0); the client sends it when it changes and
-- every RESEND seconds while a key is held, at most RATE times a second; the server drops a packet past its
-- bucket (accept) and treats an input not refreshed for STALE seconds as let go.
-- Interface: new() -> Flight; steer(flight, x, y, now); step(flight, dt, now); offset(flight, t, wind) ->
--   (dx, dy, dz) from the flier's hand; clampSteer(x, y) -> (x, y); bucket() -> Bucket; accept(bucket, now) ->
--   boolean; screenSide(x, lookX, lookZ, wind) -> x; send(last, x, y, now) -> boolean (the client's rate);
--   constants below
-- Pure. No side effects on require.

local KiteFlight = {}

KiteFlight.LAUNCH_SECS = 3 -- from the hand to its height
KiteFlight.REEL_SECS = 2.5 -- reeled all the way in (a second use, out of the zone, put away)
KiteFlight.LENGTH = 40 -- studs of string at launch (the old fixed flight: 22 downwind, 34 up)
KiteFlight.MIN_LENGTH = 20
KiteFlight.MAX_LENGTH = 60
KiteFlight.REEL_RATE = 8 -- studs a second, W or S held
KiteFlight.ELEVATION = math.rad(57) -- the string's angle above the ground with the kite at the wind's centre
KiteFlight.MAX_LEAN = math.rad(55) -- round from downwind at full lean
KiteFlight.DIP = math.rad(18) -- how much lower it flies at full lean (the edge of the wind)
KiteFlight.LEAN_RATE = 1.4 -- lean units a second (full lean in about 0.7 s), out and back
KiteFlight.SWAY = 4 -- studs side to side
KiteFlight.SWAY_HZ = 0.15
KiteFlight.HAND = 2 -- studs above the root the string leaves from
KiteFlight.WIND = table.freeze({ 0.6, 0.8 }) -- the town's wind (XZ, unit; downwind)
KiteFlight.RATE = 10 -- steer packets a second at most (client), the server's bucket refill
KiteFlight.BURST = 4 -- the server's bucket size
KiteFlight.RESEND = 0.5 -- seconds: a held key is said again this often
KiteFlight.STALE = 1.5 -- seconds: an input not said again for this long counts as let go
KiteFlight.DEAD = 0.3 -- a stick nearer the middle than this is nothing

export type Flight = {
	lean: number, -- -1 .. 1, now
	length: number, -- studs, now
	x: number, -- the input, -1 .. 1 (lean)
	y: number, -- the input, -1 .. 1 (+1 lets the string out)
	at: number, -- when the input was last said
}

function KiteFlight.new(): Flight
	return { lean = 0, length = KiteFlight.LENGTH, x = 0, y = 0, at = -math.huge }
end

local function axis(v: any): number
	if type(v) ~= "number" or v ~= v then
		return 0
	end
	return math.clamp(v, -1, 1)
end

-- Whatever came over the wire, as two numbers in -1 .. 1 (NaN, infinity, a string or a table: 0).
function KiteFlight.clampSteer(x: any, y: any): (number, number)
	return axis(x), axis(y)
end

function KiteFlight.steer(f: Flight, x: any, y: any, now: number)
	f.x, f.y = KiteFlight.clampSteer(x, y)
	f.at = now
end

local function toward(v: number, target: number, step: number): number
	if v < target then
		return math.min(target, v + step)
	end
	return math.max(target, v - step)
end

-- Move the lean toward the held side (or back to the centre) and the string's length out or in.
function KiteFlight.step(f: Flight, dt: number, now: number)
	local x, y = f.x, f.y
	if now - f.at > KiteFlight.STALE then
		x, y = 0, 0
	end
	f.lean = toward(f.lean, x, KiteFlight.LEAN_RATE * dt)
	f.length = math.clamp(f.length + y * KiteFlight.REEL_RATE * dt, KiteFlight.MIN_LENGTH, KiteFlight.MAX_LENGTH)
end

-- Where the kite is from the flier's root (studs, world axes) at time t into the flight, fully up. +lean is to the
-- right of a flier facing downwind.
function KiteFlight.offset(f: Flight, t: number, wind: { number }?): (number, number, number)
	local w = wind or KiteFlight.WIND
	local wx, wz = w[1], w[2]
	local yaw = f.lean * KiteFlight.MAX_LEAN
	local elev = KiteFlight.ELEVATION - math.abs(f.lean) * KiteFlight.DIP
	-- downwind turned by yaw toward the right (right of downwind = (-wz, wx))
	local c, s = math.cos(yaw), math.sin(yaw)
	local dx, dz = wx * c - wz * s, wz * c + wx * s
	local flat = math.cos(elev) * f.length
	local sway = math.sin(t * math.pi * 2 * KiteFlight.SWAY_HZ) * KiteFlight.SWAY
	-- the sway is across the string's own direction
	return dx * flat - dz * sway, math.sin(elev) * f.length + KiteFlight.HAND, dz * flat + dx * sway
end

-- The keys as the flier sees them: A is left on the screen. A camera looking upwind (at the flier, the kite behind
-- it) sees the kite's right on its left, so the side is swapped.
function KiteFlight.screenSide(x: number, lookX: number, lookZ: number, wind: { number }?): number
	local w = wind or KiteFlight.WIND
	if lookX * w[1] + lookZ * w[2] < 0 then
		return -x
	end
	return x
end

export type Bucket = { tokens: number, at: number }

function KiteFlight.bucket(): Bucket
	return { tokens = KiteFlight.BURST, at = -math.huge }
end

-- The server's limit: true when this packet is within the flier's rate (a token is spent), false to drop it.
function KiteFlight.accept(b: Bucket, now: number): boolean
	if b.at == -math.huge then
		b.at = now
	end
	b.tokens = math.min(KiteFlight.BURST, b.tokens + (now - b.at) * KiteFlight.RATE)
	b.at = now
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

export type Sent = { x: number, y: number, at: number }

-- The client's rate: whether to send (x, y) now, given what was last sent. A change is sent (at most RATE a
-- second); a held key is said again every RESEND seconds; nothing held and nothing changed: silence.
function KiteFlight.send(last: Sent, x: number, y: number, now: number): boolean
	if now - last.at < 1 / KiteFlight.RATE then
		return false
	end
	if x ~= last.x or y ~= last.y then
		return true
	end
	return (x ~= 0 or y ~= 0) and now - last.at >= KiteFlight.RESEND
end

-- A stick or a pair of keys as one axis: -1, 0 or 1 past the dead zone.
function KiteFlight.digital(v: number): number
	if v > KiteFlight.DEAD then
		return 1
	elseif v < -KiteFlight.DEAD then
		return -1
	end
	return 0
end

return KiteFlight
