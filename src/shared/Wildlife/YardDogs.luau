--!strict
-- ReplicatedStorage.Shared.Wildlife.YardDogs
-- The town's yard dogs (brief v2: backyards have "dog houses"; v5.4 "cats and dogs stay"; the corner store's dog
-- treats need them). Eight friendly dogs, each in its own yard (YARDS): three at the town's doghouses, where v5.4's
-- yard dogs lived (its fourth stands in Sycamore Park, not a yard: left without a dog), one behind the old town's
-- Victorian house, and four behind the west side's houses, where v5.4 kept its dogs on a lead (those five get a
-- kennel).
-- What a dog does (think, at THINK seconds, only with a player near: Server/Wildlife/YardHazards on the town's
-- brain scheduler):
--   wander  ambles about its yard to a new spot every few seconds
--   chase   a squirrel or the Spicy Rodent on the ground in its yard: it runs at it (never out of the yard; one
--           just outside, SENSE, only to the fence) and barks (BARK_EVERY seconds apart): a computer squirrel bolts, a player is told to clear off, people
--           near a bark at the rodent notice it (v5.4: a bark put the people within 12 units on alert). No harm.
--   calm    a dog treat given near it (Shared/Items/ItemRules dog_treats: calm_dog): it sits and wags and ignores
--           squirrels for the treat's seconds
--   sleep   at night it walks to its house and lies down in front of the door
-- Interface: YARDS; constants; newDog(yard, index) -> Dog; think(dog, now, sense) (decides mode and target);
--   move(dog, dt) (walks toward the target at the mode's pace, kept in the yard); calm(dog, untilTime);
--   inYard(yard, x, z, margin?) -> boolean; clampToYard(yard, x, z) -> (x, z) (also out of the kennel);
--   kennelOf(yard) -> (x, z)? (its centre; nil where the town has a doghouse); KENNEL; FUR
-- Pure (the sense callbacks are the caller's). Positions in studs. No side effects on require.

local YardDogs = {}

-- A yard: its rectangle (studs, world), the spot in front of the house where the dog lies at night, the way it
-- faces lying there, and whether the town already has a doghouse there (else YardHazards builds a kennel).
export type Yard = {
	id: string,
	x0: number,
	x1: number,
	z0: number,
	z1: number,
	homeX: number,
	homeZ: number,
	faceX: number,
	faceZ: number,
	doghouse: string?, -- the lot id of the town's doghouse at the yard's back edge
}

-- stylua: ignore
YardDogs.YARDS = table.freeze({
	-- three of the town's doghouses (generated/Lots), each opening -Z onto its yard
	{ id = "core", x0 = 82, x1 = 113, z0 = 170, z1 = 194, homeX = 97.5, homeZ = 191, faceX = 0, faceZ = -1, doghouse = "core_doghouse" },
	{ id = "north_gardens_a", x0 = 490, x1 = 525, z0 = 884, z1 = 906.5, homeX = 507.5, homeZ = 904, faceX = 0, faceZ = -1, doghouse = "north_doghouse_0" },
	{ id = "north_gardens_b", x0 = 572, x1 = 608, z0 = 964, z1 = 986.5, homeX = 590, homeZ = 984, faceX = 0, faceZ = -1, doghouse = "north_doghouse_1" },
	-- behind the Victorian house in the old town core: a kennel at the yard's far edge, opening toward the house
	{ id = "core_victorian", x0 = -155, x1 = -125, z0 = -183, z1 = -159, homeX = -140, homeZ = -177, faceX = 0, faceZ = 1 },
	-- behind the west side's houses (v5.4's dogs on a lead): a kennel at the yard's west edge, opening east
	{ id = "west_a", x0 = -1031, x1 = -985, z0 = -537, z1 = -493, homeX = -1022, homeZ = -515, faceX = 1, faceZ = 0 },
	{ id = "west_b", x0 = -1031, x1 = -985, z0 = -210, z1 = -165, homeX = -1022, homeZ = -187.5, faceX = 1, faceZ = 0 },
	{ id = "west_c", x0 = -1066, x1 = -1022, z0 = 135, z1 = 180, homeX = -1057, homeZ = 157.5, faceX = 1, faceZ = 0 },
	{ id = "west_d", x0 = -1031, x1 = -985, z0 = 345, z1 = 380, homeX = -1022, homeZ = 362, faceX = 1, faceZ = 0 },
} :: { Yard })

-- the dogs' coats (v5.4's dogFur: brown, fawn, near-black, cream)
YardDogs.FUR = table.freeze({
	{ 149, 110, 81 },
	{ 183, 158, 116 },
	{ 62, 58, 51 },
	{ 224, 200, 161 },
})

YardDogs.THINK = 0.5 -- seconds between a dog's looks (the scheduler calls more often; the brain waits)
YardDogs.SENSE = 3 -- studs past its yard's edge a dog notices a squirrel coming in (runs to it; barks once it is in)
YardDogs.ABOVE = 6 -- studs above the ground: a squirrel higher up (a fence, a branch) is out of reach and ignored
YardDogs.BELOW = 3 -- studs below it: one in a storm drain under the yard is not there for a dog
YardDogs.BARK_EVERY = 8 -- seconds between barks (v5.4's barkCooldown)
YardDogs.ALERT_RADIUS = 30 -- studs: people this near a bark at the rodent notice it (v5.4: 12 units)
YardDogs.WALK = 5 -- studs a second, wandering
YardDogs.RUN = 16 -- chasing (a squirrel sprints at 33: it gets away)
YardDogs.HOME = 7 -- going home at dusk
YardDogs.TURN = 6 -- radians a second
YardDogs.WANDER = { 3, 7 } -- seconds between new spots
YardDogs.ARRIVE = 0.8 -- studs: there
YardDogs.HIP = 1.3 -- the body's root over the ground (standing)
-- A kennel (Server/Wildlife/YardHazards builds it where the town has no doghouse): a square box `half` across each
-- way from its centre, `back` studs behind the home spot. A dog's root keeps `keep` from its sides (the tail's reach
-- behind the root; the body is shorter to the sides), so it never walks into it, nor lies with its tail in it.
YardDogs.KENNEL = table.freeze({ half = 1.7, keep = 2.4, back = 4.2 })

export type Mode = "wander" | "chase" | "calm" | "sleep"
export type Dog = {
	index: number,
	yard: Yard,
	x: number,
	z: number,
	yaw: number, -- 0 faces +Z (atan2(dx, dz))
	speed: number, -- now
	mode: Mode,
	tx: number,
	tz: number,
	nextWander: number,
	nextThink: number,
	lastBark: number,
	calmUntil: number,
	target: any?, -- what it chases (the sense's id)
	lying: boolean, -- asleep at its house
	seed: number,
}

-- What the dog can see when it thinks (the caller's: the town's threat grid, the clock).
export type Squirrel = { id: any, x: number, y: number, z: number, ground: number, rodent: boolean }
export type Sense = {
	night: boolean,
	squirrels: (x: number, z: number, r: number) -> { Squirrel },
	bark: ((dog: Dog, at: Squirrel) -> ())?,
}

function YardDogs.inYard(y: Yard, x: number, z: number, margin: number?): boolean
	local m = margin or 0
	return x >= y.x0 - m and x <= y.x1 + m and z >= y.z0 - m and z <= y.z1 + m
end

-- The kennel's centre in a yard the town gave no doghouse (nil where it did).
function YardDogs.kennelOf(y: Yard): (number?, number?)
	if y.doghouse then
		return nil, nil
	end
	local b = YardDogs.KENNEL.back
	return y.homeX - y.faceX * b, y.homeZ - y.faceZ * b
end

-- A point kept in the yard (a stud inside its edge) and out of its kennel: pushed out of the kennel's square by its
-- nearest side that is in the yard (a dog walking into it slides along it).
function YardDogs.clampToYard(y: Yard, x: number, z: number): (number, number)
	local function clamp(px: number, pz: number): (number, number)
		return math.clamp(px, y.x0 + 1, y.x1 - 1), math.clamp(pz, y.z0 + 1, y.z1 - 1)
	end
	x, z = clamp(x, z)
	local kx, kz = YardDogs.kennelOf(y)
	if kx == nil or kz == nil then
		return x, z
	end
	local e = YardDogs.KENNEL.half + YardDogs.KENNEL.keep
	if math.abs(x - kx) >= e or math.abs(z - kz) >= e then
		return x, z
	end
	local bx, bz, best = x, z, math.huge
	for _, c in { { kx - e, z }, { kx + e, z }, { x, kz - e }, { x, kz + e } } do
		local cx, cz = clamp(c[1], c[2])
		local moved = math.abs(cx - x) + math.abs(cz - z)
		if (math.abs(cx - kx) >= e - 1e-9 or math.abs(cz - kz) >= e - 1e-9) and moved < best then
			bx, bz, best = cx, cz, moved
		end
	end
	return bx, bz
end

-- a small repeatable random number in [0, 1) per dog (no shared generator: the order dogs think in is free)
local function rand(d: Dog): number
	d.seed = (d.seed * 1103515245 + 12345) % 2147483648
	return d.seed / 2147483648
end

function YardDogs.newDog(yard: Yard, index: number): Dog
	local cx, cz = (yard.x0 + yard.x1) / 2, (yard.z0 + yard.z1) / 2
	return {
		index = index,
		yard = yard,
		x = cx,
		z = cz,
		yaw = math.atan2(yard.faceX, yard.faceZ),
		speed = 0,
		mode = "wander",
		tx = cx,
		tz = cz,
		nextWander = 0,
		nextThink = 0,
		lastBark = -math.huge,
		calmUntil = -math.huge,
		target = nil,
		lying = false,
		seed = 7919 * index + 17,
	}
end

-- A dog treat: calm until then (a later treat only lengthens it).
function YardDogs.calm(d: Dog, untilTime: number)
	d.calmUntil = math.max(d.calmUntil, untilTime)
end

-- The nearest squirrel on the ground in (or just coming into) the yard, or nil.
local function intruder(d: Dog, sense: Sense): Squirrel?
	local y = d.yard
	local cx, cz = (y.x0 + y.x1) / 2, (y.z0 + y.z1) / 2
	local r = math.sqrt((y.x1 - y.x0) ^ 2 + (y.z1 - y.z0) ^ 2) / 2 + YardDogs.SENSE
	local best: Squirrel? = nil
	local bestD = math.huge
	for _, s in sense.squirrels(cx, cz, r) do
		local up = s.y - s.ground
		if YardDogs.inYard(y, s.x, s.z, YardDogs.SENSE) and up <= YardDogs.ABOVE and up >= -YardDogs.BELOW then
			local dd = (s.x - d.x) ^ 2 + (s.z - d.z) ^ 2
			if dd < bestD then
				best, bestD = s, dd
			end
		end
	end
	return best
end

-- One look: what the dog does now and where it is going. Returns true when it thought (THINK apart).
function YardDogs.think(d: Dog, now: number, sense: Sense): boolean
	if now < d.nextThink then
		return false
	end
	d.nextThink = now + YardDogs.THINK
	local y = d.yard
	if now < d.calmUntil then
		d.mode, d.target, d.lying = "calm", nil, false
		d.tx, d.tz = d.x, d.z
		return true
	end
	if sense.night then
		d.mode, d.target = "sleep", nil
		d.tx, d.tz = y.homeX, y.homeZ
		return true
	end
	d.lying = false
	local s = intruder(d, sense)
	if s then
		d.mode, d.target = "chase", s.id
		d.tx, d.tz = YardDogs.clampToYard(y, s.x, s.z)
		-- (a bark tells a player it chases them out of its yard: only once they are in it)
		if YardDogs.inYard(y, s.x, s.z) and now - d.lastBark >= YardDogs.BARK_EVERY then
			d.lastBark = now
			if sense.bark then
				sense.bark(d, s)
			end
		end
		return true
	end
	if d.mode ~= "wander" or now >= d.nextWander then
		d.mode, d.target = "wander", nil
		d.tx, d.tz =
			YardDogs.clampToYard(y, y.x0 + 1 + rand(d) * (y.x1 - y.x0 - 2), y.z0 + 1 + rand(d) * (y.z1 - y.z0 - 2))
		local w = YardDogs.WANDER
		d.nextWander = now + w[1] + rand(d) * (w[2] - w[1])
	end
	return true
end

local function angleTo(a: number, b: number): number
	return (b - a + math.pi) % (2 * math.pi) - math.pi
end

-- Walk toward the target at the mode's pace, turning at TURN, never out of the yard; lie down at home at night.
function YardDogs.move(d: Dog, dt: number)
	local pace = if d.mode == "chase" then YardDogs.RUN elseif d.mode == "sleep" then YardDogs.HOME else YardDogs.WALK
	if d.mode == "calm" then
		pace = 0
	end
	local dx, dz = d.tx - d.x, d.tz - d.z
	local dist = math.sqrt(dx * dx + dz * dz)
	if dist <= YardDogs.ARRIVE or pace == 0 then
		d.speed = 0
		if d.mode == "sleep" and dist <= YardDogs.ARRIVE then
			d.lying = true
			local want = math.atan2(d.yard.faceX, d.yard.faceZ)
			d.yaw += math.clamp(angleTo(d.yaw, want), -YardDogs.TURN * dt, YardDogs.TURN * dt)
		end
		return
	end
	local want = math.atan2(dx, dz)
	d.yaw += math.clamp(angleTo(d.yaw, want), -YardDogs.TURN * dt, YardDogs.TURN * dt)
	local step = math.min(dist, pace * dt)
	d.x, d.z = YardDogs.clampToYard(d.yard, d.x + dx / dist * step, d.z + dz / dist * step)
	d.speed = pace
end

return YardDogs
