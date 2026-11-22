--!strict
-- ReplicatedStorage.Shared.Vehicles.SharedRides
-- The town's shared little vehicles and the rules for being bumped by one (owner D29, 2026-11-22: "a scattered
-- restricted total of 3 golf carts, 2 mopeds, and 5 electric scooters, anyone can take them or use them, and you do not
-- get tickets or problems with the police with them. prepare most carefully, the dynamics, physics and scene of being
-- hit by a ..."; the lead's reading: people dodge an oncoming one; one that is hit is knocked aside, stumbles or falls
-- and gets back up; mild, no gore).
--   * SPOTS: where the ten stand when the server starts (and go back to): on paths, lawns, plazas or parking beside
--     the sidewalks, never in a road lane or inside a building (tests/unit/shared_rides.spec holds each against the
--     town's lanes, buildings, fences, water and baked parts), spread over the town: the old town centre (two
--     scooters), the houses west and east, the Neighbourhood Shop and Pepper's Corner Store on the boulevard, the
--     bowling alley's front, Sycamore Park, the hospital and the Quay's market square.
--   * Riding: any player in a person's body (Vehicles/VehicleKinds `shared`: no key, no rental; never a squirrel or the
--     rodent); nobody owns one; left where its rider got off; one left away from its spot, untouched for C.returnSecs,
--     with no player near it or its spot, is quietly put back (returnHome). No police trouble (VehicleKinds.policeIgnore).
--   * The people ahead (Server/Vehicles/RideBumps does the moving): a person in the way of a moving one (oncoming:
--     within C.look seconds at its speed, inside its width and a margin) steps or hops aside (dodgeTo: square to its
--     path, to the side they are on), C.dodgeChance of the time: the rest freeze and may be bumped.
--   * Bumped (hit: the person's circle meets the vehicle's box, their feet near its floor): knocked aside along its
--     way and to the side (knock: a slide of C.knockMin + C.knockPer x speed studs, at most C.knockMax); from
--     C.fallSpeed they fall and lie a moment (downSecs: C.downMin to C.downMax by speed), slower they stagger; then up
--     and on their way. Never killed, never sent to the menu, nothing on the ground. The rider feels it (C.keep of
--     the speed is kept). A person is not knocked again for C.cooldown seconds (allow).
--   * A squirrel or the rodent on the ground in the way: the traffic's run-over is the AI fleet's only (Traffic/
--     TrafficService's sweep never sees a player's vehicle); a shared vehicle knocks a player's squirrel aside the same
--     mild way (C.dazeSecs dazed) and the computer's skitter off along their rails.
-- Studs and the HTML yaw (0 faces +Z). Interface: SPOTS; C; NAMES; placements() -> { {kind, x, z, yaw} }; frame(ride, x, z)
--   -> (ahead, side, speed); hit(ride, x, z, feetY, r) -> boolean; oncoming(ride, x, z, r) -> seconds?;
--   dodgeSide(side, rand) -> -1 | 1; dodgeTo(ride, x, z, r, sign) -> (x, z); knock(ride, x, z) -> Knock;
--   downSecs(speed) -> seconds; newBook() -> Book; allow(book, id, now, rest) -> boolean;
--   returnHome(now, touchedAt, fromHome, nearestPlayer) -> boolean
-- Pure. No side effects on require.

local VehicleKinds = require("./VehicleKinds")

local SharedRides = {}

export type Spot = { kind: string, x: number, z: number, yaw: number, where: string }

-- A shared vehicle as RideBumps sees it this frame: where its box is (x, z its centre on the ground, `floor` the
-- ground's height under it, `yaw` its facing) and how it moves (vx, vz studs/s, the root's velocity).
export type Ride = { kind: string, x: number, z: number, floor: number, yaw: number, vx: number, vz: number }

-- A knock: the slide (dx, dz studs, over C.slideSecs), whether they fall, and how long they are down (or stagger).
export type Knock = { dx: number, dz: number, fall: boolean, secs: number }

export type Book = { [any]: number }

local HALF_PI = math.pi / 2

-- stylua: ignore
SharedRides.SPOTS = table.freeze({
	table.freeze({ kind = "cart", x = 40, z = 760, yaw = 0, where = "Sycamore Park, beside the playground" }),
	table.freeze({ kind = "cart", x = -760, z = 740, yaw = 0, where = "the hospital, east of its front entrance" }),
	table.freeze({ kind = "cart", x = 2560, z = 0, yaw = HALF_PI, where = "the Quay's market square, between the stalls" }),
	table.freeze({ kind = "moped", x = 985, z = 54, yaw = HALF_PI, where = "before Pepper's Corner Store" }),
	table.freeze({ kind = "moped", x = 1395, z = -337, yaw = HALF_PI, where = "the bowling alley's front lawn, on Bowl Lane" }),
	table.freeze({ kind = "escooter", x = -37, z = 60, yaw = 0, where = "the old town centre, west of the main street" }),
	table.freeze({ kind = "escooter", x = 37, z = -60, yaw = math.pi, where = "the old town centre, east of the main street" }),
	table.freeze({ kind = "escooter", x = -300, z = 140, yaw = 0, where = "the houses on the west side" }),
	table.freeze({ kind = "escooter", x = 380, z = 115, yaw = 0, where = "the ice cream stand on the east side" }),
	table.freeze({ kind = "escooter", x = 715, z = 45, yaw = HALF_PI, where = "the Neighbourhood Shop, on the boulevard" }),
}) :: { Spot }

SharedRides.C = table.freeze({
	-- left somewhere
	returnSecs = 300, -- untouched this long ...
	homeNear = 12, -- ... further than this from its spot ...
	playerClear = 60, -- ... and no player within this of it or its spot: it is put back
	-- the people ahead
	minSpeed = 3, -- studs/s: slower than this nothing is judged (a crawl past someone)
	look = 1.3, -- seconds ahead a person sees one coming at them ...
	lookMin = 4, -- ... and never fewer studs than this
	margin = 1.6, -- studs past its half width a person counts as in its way
	dodgeChance = 0.85, -- a person in its way steps aside this often (the rest freeze)
	dodgeSpeed = 13, -- studs/s: the quick sidestep or hop
	dodgeClear = 2.2, -- studs clear of its side the step ends
	dodgeSecs = 1.1, -- they step, face it a moment, and walk on
	dodgeRest = 4, -- seconds before the same person is judged again
	lineChance = 0.35, -- a startled word now and then (the town's speech pacing has the last say)
	-- the bump
	personR = 0.9, -- a person's half width
	squirrelR = 0.5,
	reachUp = 3.5, -- studs: feet further than this above or below its floor are not in its way
	fallSpeed = 9, -- studs/s: from this a person bumped falls; slower they stagger
	fullSpeed = 30, -- studs/s: at this or faster the longest time on the ground
	knockMin = 1.6, -- studs knocked: knockMin + knockPer x speed, at most knockMax
	knockPer = 0.12,
	knockMax = 5.5,
	side = 0.75, -- the share of the knock to the side (the rest along its way)
	downMin = 1.5, -- seconds on the ground, by speed
	downMax = 3,
	staggerSecs = 0.7, -- a stagger
	slideSecs = 0.35, -- the knock's slide
	cooldown = 6, -- seconds before one person is knocked again
	keep = 0.55, -- the rider keeps this share of the speed
	dazeSecs = 1.2, -- a player's squirrel knocked aside is dazed this long
})

local C = SharedRides.C

-- what each kind is called on a player's screen
SharedRides.NAMES = table.freeze({ cart = "golf cart", moped = "moped", escooter = "scooter" }) :: { [string]: string }

-- placements(): the ten as DeviceService takes its placements.
function SharedRides.placements(): { { kind: string, x: number, z: number, yaw: number } }
	local out = {}
	for _, s in SharedRides.SPOTS do
		table.insert(out, { kind = s.kind, x = s.x, z = s.z, yaw = s.yaw })
	end
	return out
end

-- frame(ride, x, z): the point in the frame of the vehicle's way: how far ahead of its centre and to its side, and its
-- speed. Its way is where it moves (backing up included); a vehicle at a standstill looks where it faces.
function SharedRides.frame(r: Ride, x: number, z: number): (number, number, number)
	local speed = math.sqrt(r.vx * r.vx + r.vz * r.vz)
	local fx, fz
	if speed > 0.1 then
		fx, fz = r.vx / speed, r.vz / speed
	else
		fx, fz = math.sin(r.yaw), math.cos(r.yaw)
	end
	local dx, dz = x - r.x, z - r.z
	return dx * fx + dz * fz, dx * fz - dz * fx, speed
end

-- hit(ride, x, z, feetY, r): a body of half width r with its feet at feetY meets the vehicle's box.
function SharedRides.hit(ride: Ride, x: number, z: number, feetY: number, r: number): boolean
	if math.abs(feetY - ride.floor) > C.reachUp then
		return false
	end
	local size = VehicleKinds.kind(ride.kind).size
	local s, c = math.sin(ride.yaw), math.cos(ride.yaw)
	local dx, dz = x - ride.x, z - ride.z
	local along = dx * s + dz * c
	local across = dx * c - dz * s
	return math.abs(along) <= size[3] / 2 + r and math.abs(across) <= size[1] / 2 + r
end

-- oncoming(ride, x, z, r): seconds until a moving vehicle reaches a body of half width r in its way (its width and
-- C.margin, within C.look seconds or C.lookMin studs ahead of its front), else nil.
function SharedRides.oncoming(ride: Ride, x: number, z: number, r: number): number?
	local ahead, side, speed = SharedRides.frame(ride, x, z)
	if speed < C.minSpeed then
		return nil
	end
	local size = VehicleKinds.kind(ride.kind).size
	local front = ahead - size[3] / 2 - r
	if front < 0 or front > math.max(C.lookMin, speed * C.look) then
		return nil
	end
	if math.abs(side) > size[1] / 2 + C.margin + r then
		return nil
	end
	return front / speed
end

-- dodgeSide(side, rand): which way a person steps: away from the vehicle's line, on the side they are on (dead ahead:
-- either, by the dice).
function SharedRides.dodgeSide(side: number, rand: () -> number): number
	if math.abs(side) < 0.2 then
		return if rand() < 0.5 then -1 else 1
	end
	return if side > 0 then 1 else -1
end

-- dodgeTo(ride, x, z, r, sign): where the step ends: square to the vehicle's way, C.dodgeClear past its side on the
-- `sign` side (its frame's side axis), for a body of half width r.
function SharedRides.dodgeTo(ride: Ride, x: number, z: number, r: number, sign: number): (number, number)
	local _, side, speed = SharedRides.frame(ride, x, z)
	local fx, fz
	if speed > 0.1 then
		fx, fz = ride.vx / speed, ride.vz / speed
	else
		fx, fz = math.sin(ride.yaw), math.cos(ride.yaw)
	end
	local size = VehicleKinds.kind(ride.kind).size
	local want = sign * (size[1] / 2 + C.dodgeClear + r)
	local move = want - side
	-- the side axis is (fz, -fx) (frame's `side`)
	return x + fz * move, z - fx * move
end

-- downSecs(speed): how long someone knocked over at this speed stays down.
function SharedRides.downSecs(speed: number): number
	local k = math.clamp((speed - C.fallSpeed) / (C.fullSpeed - C.fallSpeed), 0, 1)
	return C.downMin + (C.downMax - C.downMin) * k
end

-- knock(ride, x, z): the knock for a body at (x, z) the vehicle has just met: along its way and away to the side the
-- body is on (dead ahead: always the same side), farther the faster it went.
function SharedRides.knock(ride: Ride, x: number, z: number): Knock
	local _, side, speed = SharedRides.frame(ride, x, z)
	local fx, fz
	if speed > 0.1 then
		fx, fz = ride.vx / speed, ride.vz / speed
	else
		fx, fz = math.sin(ride.yaw), math.cos(ride.yaw)
	end
	local sign = if side < 0 then -1 else 1
	local sx, sz = fz * sign, -fx * sign
	local a, b = 1 - C.side, C.side
	local kx, kz = fx * a + sx * b, fz * a + sz * b
	local len = math.sqrt(kx * kx + kz * kz)
	local dist = math.min(C.knockMax, C.knockMin + C.knockPer * speed)
	local fall = speed >= C.fallSpeed
	return {
		dx = kx / len * dist,
		dz = kz / len * dist,
		fall = fall,
		secs = if fall then SharedRides.downSecs(speed) else C.staggerSecs,
	}
end

function SharedRides.newBook(): Book
	return {}
end

-- allow(book, id, now, rest): true (and noted) unless `id` was let through within `rest` seconds.
function SharedRides.allow(book: Book, id: any, now: number, rest: number): boolean
	local last = book[id]
	if last and now - last < rest then
		return false
	end
	book[id] = now
	return true
end

-- returnHome(now, touchedAt, fromHome, nearestPlayer): whether a parked shared vehicle `fromHome` studs from its spot,
-- last ridden or left at touchedAt, with the nearest player `nearestPlayer` studs from it or its spot, goes back now.
function SharedRides.returnHome(now: number, touchedAt: number, fromHome: number, nearestPlayer: number): boolean
	return fromHome > C.homeNear and now - touchedAt >= C.returnSecs and nearestPlayer > C.playerClear
end

return SharedRides
