--!strict
-- ReplicatedStorage.Shared.Attractions.LoungeClassic
-- THE GILDED ACORN, the 1940s lounge (f3_lounge_classic; brief v2 "Lounge one", addendum D14): the rules the
-- server (Server/Attractions/LoungeService), the client's music (Client/World/LoungeMusic) and the specs share.
--   The door: a person with the pass (the wallet's one pass: paintball and both lounges) goes in through the
--     prompt; one without it is offered the pass; a squirrel or the Spicy Rodent never gets in (the guards); a fox
--     or a deer is turned away. The building is sealed (tools/bake/lounge_classic): the prompt is the only way.
--   Inside: the camera is locked to first person (the body's CameraZone, Client/Camera/CameraPolicy) until the
--     person leaves through the door.
--   The guards: a squirrel-family body on the forecourt, in the entry or (should one ever be) inside is knocked
--     out by the nearest guard: the game's own knock-out (Boot/Game kill, cause "guard"): its player goes back to
--     the menu, a computer squirrel goes back to where it lives. No blood, no injury shown: a swat and it is gone.
--   The bar: hot cocoa, coffee, green tea and snow cones at EconomyRules.PRICES, held and sipped (SIPS sips, one
--     every SIP_EVERY seconds). People have no stamina in this game, so a drink is for the look only.
--   The jazz: a stock-library playlist by cue name (JAZZ; ids empty until the lead picks them), heard inside only.
--   The seats (SEATS): the seven bar stools, the four booths (two on each bench), the club chairs round the four
--     small tables and the two armchairs by the fire. A person let in sits with R on the seat's prompt (a Seat:
--     the game's own sitting, as the lawn chair and the sky lift), stays in first person, keeps a drink in hand and
--     sips it, and gets up with the seat key again, jump or by moving (Client/World/SeatGetUp asks the server:
--     Shared/World/SeatRules), standing at the seat's standSpot. A seated person is inside.
-- Everything is in the venue's local frame (Shared/Attractions/AlleyLayout: X across the frontage, Y up from the
-- floor, D into the building; the front is at D -28) unless it says world.
-- Interface: VENUE; DOOR_OUTSIDE, DOOR_INSIDE ({ X, Y, D, facing D sign }); INSIDE; GUARDED; GUARD_POSTS; COUNTER;
--   DRINKS; SIPS; SIP_EVERY; JAZZ; ZONE; WORDS; drink(id) -> Drink?; inside(x, y, d) -> boolean; guarded(x, y, d)
--   -> boolean; door(species?, hasPass) -> "enter" | "offer" | "guard" | "refuse"; nextTrack(list, from) ->
--   index?; placeOf(venue) -> Place; SEATS ({ id, kind, x, y (the seat's top), d, fx, fd (the way the sitter faces)
--   }); SEAT_ATTRIBUTE; SEAT_WORDS; standUp(moveX, moveZ, jump) -> boolean; standSpot(seat) -> x, d (where its
--   sitter stands up); STAND_BACK; STAND_BOOTH_X
-- Pure. No side effects on require.

local LoungeClassic = {}

LoungeClassic.VENUE = "f3_lounge_classic"
LoungeClassic.ZONE = "lockFirstPerson" -- the body's CameraZone inside
LoungeClassic.ATTRIBUTE = "Lounge" -- the body's attribute while the service holds it inside (the venue id)

-- where the door's prompt puts a person: on the landing outside, facing the street; just inside, facing the room
LoungeClassic.DOOR_OUTSIDE = { x = 0, d = -23.6, faceD = -1 }
LoungeClassic.DOOR_INSIDE = { x = 0, d = -18.6, faceD = 1 }

-- the room: the walls' inner faces; near the door (|X| < 6) the room starts at the door wall (D -21)
LoungeClassic.INSIDE = { x = 24, d0 = -27, d1 = 27, doorX = 6, doorD = -21, y0 = -1, y1 = 13 }
-- where the guards strike: the forecourt and the entry (to the door), from the ground to the canopy; not past the
-- forecourt's street edge (D -32: Bowl Lane's planned sidewalk starts there)
LoungeClassic.GUARDED = { x = 11, d0 = -32, d1 = -21, y0 = -6, y1 = 11 }
LoungeClassic.GUARD_POSTS = { { x = -6, d = -31 }, { x = 6, d = -31 } } -- data/expansion.json guard_1, guard_2
LoungeClassic.COUNTER = { x0 = -12, x1 = 12, d = 15 } -- the bar's front face (the order prompts stand on it)

-- The seats, as the bake builds the furniture (tools/bake/lounge_classic/Interior; tests/unit/lounge_rules.spec
-- holds them to its Style): the sitter's spot on the seat's top, and the way they face.
export type Seat = { id: string, kind: string, x: number, y: number, d: number, fx: number, fd: number }
LoungeClassic.SEAT_ATTRIBUTE = "LoungeSeat" -- on each Seat part: its id (Client/World/SeatGetUp: moving gets up)
LoungeClassic.SEAT_WORDS = table.freeze({
	action = "Sit",
	stool = "Bar stool",
	booth = "Booth",
	club = "Club chair",
	armchair = "Armchair",
})
local seats: { Seat } = {}
do
	-- seven stools along the bar (X every 3.4, D 13.2, top 2.56), facing the bar
	for i = -3, 3 do
		table.insert(seats, { id = `stool{i + 4}`, kind = "stool", x = i * 3.4, y = 2.56, d = 13.2, fx = 0, fd = 1 })
	end
	-- four booths at X +-18 (D -10 and 4): two benches (top 1.7) across a table, two places on each
	for b, c in { { -18, -10 }, { 18, -10 }, { -18, 4 }, { 18, 4 } } do
		local s = if c[1] < 0 then -1 else 1
		for _, side in { -1, 1 } do
			for k, x in { 17, 21 } do
				table.insert(seats, {
					id = `booth{b}{if side < 0 then "a" else "b"}{k}`,
					kind = "booth",
					x = s * x,
					y = 1.7,
					d = c[2] + side * 2.9,
					fx = 0,
					fd = -side,
				})
			end
		end
	end
	-- the club chairs either side of the four small tables (top 1.5), facing the table
	for i, tb in { { -6, -12 }, { 6, -12 }, { -6, -1 }, { 6, -1 } } do
		for _, s in { -1, 1 } do
			table.insert(seats, {
				id = `club{i}{if s < 0 then "a" else "b"}`,
				kind = "club",
				x = tb[1] + s * 2.4,
				y = 1.5,
				d = tb[2],
				fx = -s,
				fd = 0,
			})
		end
	end
	-- the two armchairs by the fire on the east wall (X 18.5, D 15.8 and 24.2), facing it
	for i, cd in { 15.8, 24.2 } do
		table.insert(seats, { id = `armchair{i}`, kind = "armchair", x = 18.7, y = 1.5, d = cd, fx = 1, fd = 0 })
	end
end
LoungeClassic.SEATS = table.freeze(seats)

-- Whether a seated person's input gets them up: a jump, or a move past a small dead zone (the stick's rest).
function LoungeClassic.standUp(moveX: number, moveZ: number, jump: boolean): boolean
	return jump or moveX * moveX + moveZ * moveZ > 0.25 * 0.25
end

-- Where a person who gets up from a seat stands (owner D32: "we can get back up with another button push"; the server
-- puts them there, Shared/World/SeatRules): clear of every piece of furniture and on the floor the door is reached
-- from (tests/unit/lounge_classic.spec floods it). From a stool, a club chair or an armchair: STAND_BACK behind it;
-- from a booth: out at its open end, toward the middle of the room (STAND_BOOTH_X), level with the place.
LoungeClassic.STAND_BACK = 3
LoungeClassic.STAND_BOOTH_X = 11.8
function LoungeClassic.standSpot(seat: Seat): (number, number)
	if seat.kind == "booth" then
		return (if seat.x < 0 then -1 else 1) * LoungeClassic.STAND_BOOTH_X, seat.d
	end
	return seat.x - seat.fx * LoungeClassic.STAND_BACK, seat.d - seat.fd * LoungeClassic.STAND_BACK
end

export type Drink = {
	id: string, -- EconomyRules.PRICES and NAMES row
	label: string, -- the prompt's words
	hot: boolean,
	cup: { number }, -- the vessel's colour
	fill: { number }, -- what is in it
}
LoungeClassic.DRINKS = table.freeze({
	table.freeze({ id = "hot_cocoa", label = "Hot cocoa", hot = true, cup = { 244, 240, 232 }, fill = { 96, 58, 38 } }),
	table.freeze({ id = "coffee", label = "Coffee", hot = true, cup = { 244, 240, 232 }, fill = { 52, 34, 24 } }),
	table.freeze({
		id = "green_tea",
		label = "Green tea",
		hot = true,
		cup = { 244, 240, 232 },
		fill = { 176, 168, 92 },
	}),
	table.freeze({
		id = "snow_cone",
		label = "Snow cone",
		hot = false,
		cup = { 236, 230, 214 },
		fill = { 214, 64, 74 },
	}),
})
LoungeClassic.SIPS = 4
LoungeClassic.SIP_EVERY = 5 -- seconds

-- The jazz: stock Roblox library tracks (licensed music from Roblox's verified partner APM, never uploaded), chosen
-- 18 November for the owner: a 1920s-feel set of hot jazz, stride piano, a slow number and swing. Empty: silent.
LoungeClassic.JAZZ = table.freeze({
	table.freeze({
		cue = "Lounge.Jazz1",
		id = "rbxassetid://104391003816309",
		want = "Charleston Time (Harry Gold), hot jazz",
	}),
	table.freeze({
		cue = "Lounge.Jazz2",
		id = "rbxassetid://1847365925",
		want = "Strolling Along (Paul Lenart), stride piano",
	}),
	table.freeze({
		cue = "Lounge.Jazz3",
		id = "rbxassetid://112961391906009",
		want = "White Gardenia (Harry Gold), slow jazz",
	}),
	table.freeze({
		cue = "Lounge.Jazz4",
		id = "rbxassetid://112031221369583",
		want = "Dixie Doodle (Harry Gold), swing",
	}),
})
LoungeClassic.JAZZ_VOLUME = 0.35

LoungeClassic.WORDS = table.freeze({
	enterAction = "Go in",
	leaveAction = "Leave",
	doorObject = "THE GILDED ACORN",
	buyAction = "Buy a pass",
	orderObject = "The bar",
	welcome = "Welcome to THE GILDED ACORN.",
	goodbye = "Good night. Do come again.",
	membersOnly = "Members only.",
	animals = "No animals in the lounge.",
	squirrel = "The guards do not let squirrels in.",
	noBody = "Pick a body from the menu first.",
	notInside = "Come inside to order.",
	holding = "Finish the one you have first.",
	finished = "All gone.",
})

function LoungeClassic.drink(id: string): Drink?
	for _, d in LoungeClassic.DRINKS do
		if d.id == id then
			return d
		end
	end
	return nil
end

-- Is the local point inside the room?
function LoungeClassic.inside(x: number, y: number, d: number): boolean
	local I = LoungeClassic.INSIDE
	if y < I.y0 or y > I.y1 or math.abs(x) >= I.x or d >= I.d1 then
		return false
	end
	return d > (if math.abs(x) < I.doorX then I.doorD else I.d0)
end

-- Is the local point where the guards strike (the forecourt and the entry, up to the door)?
function LoungeClassic.guarded(x: number, y: number, d: number): boolean
	local G = LoungeClassic.GUARDED
	return math.abs(x) <= G.x and d >= G.d0 and d <= G.d1 and y >= G.y0 and y <= G.y1
end

local SQUIRRELS = { squirrel = true, rodent = true }
LoungeClassic.SQUIRRELS = SQUIRRELS

-- What the door does for a body of this species: a person with the pass goes in, one without is offered it;
-- the squirrel family meets the guards; any other animal is turned away; no body: refused.
function LoungeClassic.door(species: string?, hasPass: boolean): "enter" | "offer" | "guard" | "refuse"
	if species == "human" then
		return if hasPass then "enter" else "offer"
	elseif species ~= nil and SQUIRRELS[species] then
		return "guard"
	end
	return "refuse"
end

-- The next track with an id after `from` (wrapping), or nil when none has one.
function LoungeClassic.nextTrack(list: { { cue: string, id: string } }, from: number): number?
	local n = #list
	for k = 1, n do
		local i = (from + k - 1) % n + 1
		if list[i].id ~= "" then
			return i
		end
	end
	return nil
end

export type Place = { x: number, z: number, floorY: number, yaw: number }
function LoungeClassic.placeOf(venue: any): Place
	return { x = venue.position.x, z = venue.position.z, floorY = venue.floorY, yaw = venue.yaw }
end

return LoungeClassic
