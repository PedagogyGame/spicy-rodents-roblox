--!strict
-- ReplicatedStorage.Shared.Items.KickBall
-- The corner store's kick ball (owner D30: "lets put a kick ball in the store and if a person kicks it at another player
-- or winds up and throws it at another player, their reputation score goes down"): a red playground ball, a real ball
-- the server's physics moves (Items/ItemWorld), still its buyer's wherever it goes (Items/Lending: anyone else who
-- catches or picks it up only borrows it).
--   * In hand: a click (or a tap, or the trigger) KICKS it: dropped to the foot and sent low and fast along the way the
--     holder faces. Held down, it WINDS UP: let go after C.windupMin seconds or more and it is THROWN from the hand,
--     harder the longer the hold, up to C.windupMax (launch). The server times the press itself (the Tool's Activated
--     and Deactivated, both seen on the server): a client cannot say how long it held.
--   * On the ground: anyone in a person's body kicks it with F, the townsperson's kick (groundKick: within C.footReach
--     of the feet, in front), the same low kick, and it is still its buyer's.
--   * A hit: a ball flying at Conduct's hardSpeed or more that meets a person (sweep: the ball's path over the last
--     step against an upright person, C.personR across and C.personH tall) knocks them a little (stagger: a short slide
--     and a moment without control, never a fall) and is handed to Reputation/Conduct as a hard hit (it rarely counts:
--     see there). Slower, a player catches it as before (Items/Lending); the thrower is never hit by their own ball.
-- Studs and seconds. Interface: C; launch(windup?) -> Launch; sweep(a, b, p) -> boolean (a, b the ball's last and
--   present place {x, y, z}; p a person's feet {x, y, z}); groundKick(ball, feet, lookX, lookZ) -> (vx, vy, vz)?;
--   stagger(vx, vz) -> { dx, dz, secs }; hard(speed) -> boolean
-- Pure. No side effects on require.

local Conduct = require("../Reputation/Conduct")

local KickBall = {}

-- stylua: ignore
KickBall.C = table.freeze({
	kickSpeed = 46, kickLift = 0.14, -- the click: low and fast (a lift of 0.14 rises about 1 stud in 10)
	throwMin = 28, throwMax = 64, throwLift = 0.3, -- the wind-up: from a lob to a fast throw
	windupMin = 0.25, windupMax = 1.2, -- seconds held: under windupMin it is a kick; the throw tops out at windupMax
	footReach = 4.5, -- studs from the feet a ball on the ground can be kicked with F
	frontDot = 0.2, -- ... and in front (the cosine of about 78 degrees)
	personR = 1.6, personH = 5.2, -- a person as the ball sees them: an upright 3.2-stud-wide column from the feet
	staggerSlide = 1.5, staggerSecs = 0.6, -- the knock of a hard hit: a short push, the controls off a moment
	density = 0.35, friction = 0.6, elasticity = 0.55, -- a light, bouncy rubber ball
})

export type Launch = { style: string, speed: number, lift: number, windup: number }
export type V3 = { x: number, y: number, z: number }

-- What a press does, by how long it was held (seconds, the server's own timing; nil: a plain click).
function KickBall.launch(windup: number?): Launch
	local C = KickBall.C
	local w = if type(windup) == "number" and windup == windup then math.max(0, windup) else 0
	if w < C.windupMin then
		return { style = "kick", speed = C.kickSpeed, lift = C.kickLift, windup = w }
	end
	local k = math.clamp((w - C.windupMin) / (C.windupMax - C.windupMin), 0, 1)
	return {
		style = "throw",
		speed = C.throwMin + (C.throwMax - C.throwMin) * k,
		lift = C.throwLift,
		windup = math.min(w, C.windupMax),
	}
end

-- Hard enough to hurt (Conduct's line: the same number decides the knock and the reputation).
function KickBall.hard(speed: number): boolean
	return speed >= Conduct.C.ball.hardSpeed
end

-- Did the ball's path from a to b pass through a person standing at p (feet)? The nearest point of the segment to the
-- person's upright axis, within personR across and between the feet and personH up (with the ball's own half stud).
function KickBall.sweep(a: V3, b: V3, p: V3): boolean
	local C = KickBall.C
	local dx, dz = b.x - a.x, b.z - a.z
	local len2 = dx * dx + dz * dz
	local t = 0
	if len2 > 1e-9 then
		t = math.clamp(((p.x - a.x) * dx + (p.z - a.z) * dz) / len2, 0, 1)
	end
	local cx, cy, cz = a.x + dx * t, a.y + (b.y - a.y) * t, a.z + dz * t
	local ox, oz = cx - p.x, cz - p.z
	if ox * ox + oz * oz > C.personR * C.personR then
		return false
	end
	return cy >= p.y - 0.5 and cy <= p.y + C.personH + 0.5
end

-- F by a ball on the ground: the kick's velocity, or nil when it is out of reach or behind (look: the kicker's facing).
function KickBall.groundKick(ball: V3, feet: V3, lookX: number, lookZ: number): (number?, number?, number?)
	local C = KickBall.C
	local dx, dz = ball.x - feet.x, ball.z - feet.z
	local d = math.sqrt(dx * dx + dz * dz)
	if d > C.footReach or math.abs(ball.y - feet.y) > 3 then
		return nil, nil, nil
	end
	local ll = math.sqrt(lookX * lookX + lookZ * lookZ)
	if ll < 1e-6 then
		return nil, nil, nil
	end
	local lx, lz = lookX / ll, lookZ / ll
	if d > 0.3 and (dx * lx + dz * lz) / d < C.frontDot then
		return nil, nil, nil
	end
	local s, lift = C.kickSpeed, C.kickLift
	local h = math.sqrt(1 - lift * lift)
	return lx * s * h, s * lift, lz * s * h
end

-- The knock on a person a hard ball hits, along the ball's way (vx, vz: its velocity).
function KickBall.stagger(vx: number, vz: number): { dx: number, dz: number, secs: number }
	local C = KickBall.C
	local l = math.sqrt(vx * vx + vz * vz)
	if l < 1e-6 then
		return { dx = 0, dz = 0, secs = C.staggerSecs }
	end
	return { dx = vx / l * C.staggerSlide, dz = vz / l * C.staggerSlide, secs = C.staggerSecs }
end

return KickBall
