--!strict
-- ReplicatedStorage.Shared.Wildlife.JumpedAt
-- When has an ORDINARY squirrel "jumped right on" a person "or at them" (owner D21, 2026-11-21: "the regular squirrel
-- should not be ran away from by npcs, unless it jumps right on them or at them")? The rule, on one leap as the server
-- knows it: where it left its footing (the launch), the places the server held the body at in the air, and where it
-- came down (the landing). Nothing a squirrel does on its feet counts, however near or fast: walking up to someone,
-- sprinting past, following them, brushing by, sitting on a wire over their head.
--   ON them   a move of the leap (one held place to the next, or the last one to the landing) passes within C.on of
--             the person, level, at a height between C.under below their feet and C.over above their head: it landed
--             on them, hit them or brushed past their ear, whatever its heading. A move that begins there already is
--             no arrival (a hop on the spot at their feet, a leap away from them), but a drop from over their head is.
--   AT them   the leap came down within C.short of them, level, in that band of heights, having been aimed at them:
--             its line from the launch to the landing, carried on, passes within C.on of them, they were ahead of it,
--             and it covered at least C.minFlight on the level (a hop on the spot beside someone is no leap at them).
-- A leap that goes by further off than C.on to a side, or lands beyond C.short of them, or passes more than C.over
-- above their head (wire to wire across the street), is neither.
-- The distances come from the bodies (Actors/Species hitboxes: a person's 1.1 st radius and 5.2 st height, a
-- squirrel's 0.8 st radius): C.on is the two radii and half a stud (touching, near enough), C.short the two radii and
-- 3.5 st (about two squirrel lengths short of their feet).
-- Interface: C; launch(x, y, z) -> Flight (y: the squirrel's feet); advance(flight, x, y, z) (the place the body is
--   held at now); passes(flight, x, y, z, px, feet, pz) -> boolean (ON: the move from the flight's last place to here);
--   lands(flight, x, y, z, px, feet, pz) -> boolean (AT: the landing here); allow(book, personId, squirrelId, now) ->
--   boolean (the caps: one start a person every C.personCooldown, at most C.squirrelMax a squirrel in
--   C.squirrelWindow; a yes is booked); newBook() -> Book; forget(book, id)
-- Pure. Studs; y up. No side effects on require.

local Species = require("../Actors/Species")

export type Flight = {
	x0: number, -- the launch (the squirrel's feet)
	y0: number,
	z0: number,
	x: number, -- the last place it was held at
	y: number,
	z: number,
}

export type Book = {
	person: { [any]: number }, -- when each person last started at a squirrel
	squirrel: { [any]: { number } }, -- when each squirrel made someone start (the newest C.squirrelMax)
}

local JumpedAt = {}

local human = Species.def("human").hitbox
local squirrel = Species.def("squirrel").hitbox

JumpedAt.C = table.freeze({
	on = human.radius + squirrel.radius + 0.5, -- studs, level: on them
	short = human.radius + squirrel.radius + 3.5, -- studs, level: a landing this near, aimed at them
	height = human.height, -- studs: a person, feet to the top of the head
	over = 2, -- studs above their head that is still at them (higher is overhead: nobody's start)
	under = 1, -- studs below their feet (a kerb, a step)
	minFlight = 2, -- studs on the level a leap AT someone covers at least
	personCooldown = 20, -- seconds before the same person starts again
	squirrelMax = 3, -- people one squirrel makes start ...
	squirrelWindow = 10, -- ... in any this many seconds
})

function JumpedAt.launch(x: number, y: number, z: number): Flight
	return { x0 = x, y0 = y, z0 = z, x = x, y = y, z = z }
end

function JumpedAt.advance(flight: Flight, x: number, y: number, z: number)
	flight.x, flight.y, flight.z = x, y, z
end

local function inBand(y: number, feet: number): boolean
	local C = JumpedAt.C
	return y >= feet - C.under and y <= feet + C.height + C.over
end

-- passes: does the move from the flight's last place to (x, y, z) go within C.on of the person standing at (px, pz)
-- with their feet at `feet`, at a height in their band there?
function JumpedAt.passes(flight: Flight, x: number, y: number, z: number, px: number, feet: number, pz: number): boolean
	local ax, ay, az = flight.x, flight.y, flight.z
	local on = JumpedAt.C.on
	-- (a move that begins on them is no arrival: a hop on the spot at their feet, or a leap away from them)
	if (ax - px) ^ 2 + (az - pz) ^ 2 <= on * on and inBand(ay, feet) then
		return false
	end
	local dx, dz = x - ax, z - az
	local l2 = dx * dx + dz * dz
	local u = if l2 > 1e-9 then math.clamp(((px - ax) * dx + (pz - az) * dz) / l2, 0, 1) else 1
	local cx, cy, cz = ax + dx * u, ay + (y - ay) * u, az + dz * u
	return (cx - px) ^ 2 + (cz - pz) ^ 2 <= on * on and inBand(cy, feet)
end

-- lands: the leap came down at (x, y, z): short of the person, level with them, and aimed at them?
function JumpedAt.lands(flight: Flight, x: number, y: number, z: number, px: number, feet: number, pz: number): boolean
	local C = JumpedAt.C
	if not inBand(y, feet) then
		return false
	end
	local gx, gz = px - x, pz - z
	if gx * gx + gz * gz > C.short * C.short then
		return false
	end
	local dx, dz = x - flight.x0, z - flight.z0
	local len = math.sqrt(dx * dx + dz * dz)
	if len < C.minFlight then
		return false
	end
	local ux, uz = dx / len, dz / len
	local rx, rz = px - flight.x0, pz - flight.z0
	-- the person is ahead of the launch, the leap's line passes within `on` of them, and it did not come down beyond them
	local along = rx * ux + rz * uz
	local aside = math.abs(rx * uz - rz * ux)
	return along > 0 and aside <= C.on and gx * ux + gz * uz >= -C.on
end

function JumpedAt.newBook(): Book
	return { person = {}, squirrel = {} }
end

-- allow: may this person start at this squirrel now? One start a person every C.personCooldown (whichever squirrel),
-- and no squirrel makes more than C.squirrelMax people start in C.squirrelWindow: a squirrel bouncing through a
-- crowd leaves a few yelps behind it, never a street in uproar. A yes is booked.
function JumpedAt.allow(book: Book, personId: any, squirrelId: any, now: number): boolean
	local C = JumpedAt.C
	local last = book.person[personId]
	if last ~= nil and now - last < C.personCooldown then
		return false
	end
	local times = book.squirrel[squirrelId]
	if times == nil then
		times = {}
		book.squirrel[squirrelId] = times
	end
	while #times > 0 and now - times[1] >= C.squirrelWindow do
		table.remove(times, 1)
	end
	if #times >= C.squirrelMax then
		return false
	end
	table.insert(times, now)
	book.person[personId] = now
	return true
end

-- forget: a body that is gone from the town's books (either side)
function JumpedAt.forget(book: Book, id: any)
	book.person[id] = nil
	book.squirrel[id] = nil
end

return JumpedAt
