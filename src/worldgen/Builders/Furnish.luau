--!strict
-- ServerScriptService.Server.WorldGen.Builders.Furnish
-- Room dressing for every enterable shell (the four FRB houses, the hospital, the police station):
-- owner 2026-11-10 "make ... interiors of houses much nicer", "all required interior builds". Each room
-- is furnished for its purpose from a recipe (Builders/Furniture pieces), on a floor finish of its own
-- material and colour, inside lined and skirted walls, under a ceiling with a lit fixture, with glazed
-- panes and curtains on the inside of its windows and pictures on its free walls.
--
-- Two steps, because the room graph (Builders/Shell) needs to know where the hide spots end up:
--   plan(ctx, info) -> Plan      lays every room out (pure; no parts yet)
--   emit(ctx, plan)              adds the parts and lights to ctx.list
-- The layout is a deterministic solver on a 0.5 st grid of the room:
--   1. keep-outs: a zone in front of every door (its swing and the way through), discs round the spots
--      staff stand on;
--   2. pinned pieces: template furniture as near its template position as the doors allow (its back to
--      the nearest wall), stations and shelves exactly where the building data puts them;
--   3. walkways: a body 1 st in radius must be able to walk from the first door to every other door,
--      to the middle of the room and to every pinned piece; a spot is only taken if that still holds
--      with the new piece standing on it (a flood fill per candidate);
--   4. recipe pieces, in order, each on the best free spot for its rule: along a named wall, in a
--      corner, near or facing another piece, in front of one, under one (rugs), at the centre, or hung
--      on a free span of wall. A piece that does not fit is skipped, never squeezed into a doorway.
-- WorldGen/InteriorCheck verifies the result independently (rooms furnished for their kind, doorways
-- and paths clear, nothing floating or buried, a light in every room).
--
-- Interface:
--   roomKind(buildingId, roomId) -> kind;  RECIPES[kind];  FINISH[kind];  KNOBS (part budget)
--   layout(room, recipe, tones) -> { placed, skipped, unreached }     one room (pure, tested directly)
--   plan(ctx, info) -> Plan;  emit(ctx, plan);  hideSpots(plan) -> { { id, room, x, z } }
-- Pure (adds PartSpecs/ExtraSpecs to ctx.list).

local Facade = require("./Facade")
local Furniture = require("./Furniture")
local Spec = require("../Spec")
local Yield = require("../Yield")

local Furnish = {}

-- Part-budget knobs (the town must stay under 27,000 parts). Turn off in this order if the count
-- runs over: pictures, skirting, curtains.
Furnish.KNOBS = {
	pictures = true,
	skirting = true,
	curtains = true,
}

Furnish.CEILING = 10.5 -- studs from a house floor to its ceiling (the roof void above is closed off)
Furnish.CELL = 0.5 -- layout grid
Furnish.OFF = 0.2 -- floor pieces stand this far off the wall face (lining and skirting)
Furnish.BODY = 1.0 -- the radius of the body every walkway must let through

export type Item = {
	kind: string,
	pref: string?, -- A | B | C | D (walls by free length) | corner | far | near:<kind> | facing:<kind> | front:<kind> | under:<kind> | centre | above:<kind> | hang
	frac: number?, -- with a wall: where along it (0..1)
	dist: number?, -- with front: the gap to the target
	face: boolean?, -- with front: turn to face the target
	shift: number?, -- with under: how far toward the target's front, in target depths
	req: boolean?,
	w: number?,
	seats: number?,
	variant: number?,
}

export type DoorIn = { id: string, x: number, z: number, w: number, wall: number }
export type WindowIn = {
	wall: number,
	c: number,
	w: number,
	h: number,
	y: number,
	covered: boolean?, -- a counter, sofa or bed stands under it: no curtains
}
export type Pin = {
	id: string, -- part name
	kind: string, -- furniture kind, or "station" / "shelf" (fixed boxes)
	x: number,
	z: number,
	hide: string?,
	fixed: boolean?, -- never moved (stations, shelves)
	sx: number?, -- fixed box footprint (model-local)
	sz: number?,
	dress: string?, -- Furniture.dress kind
	optional: boolean?, -- a fixed piece that is left out where a door, a desk or a walkway needs the floor
	w: number?,
	seats: number?,
}
export type Room = {
	id: string,
	kind: string,
	x0: number, -- inner clear rect (wall faces), model-local studs
	x1: number,
	z0: number,
	z1: number,
	doors: { DoorIn },
	windows: { WindowIn },
	pins: { Pin },
	discs: { { x: number, z: number, r: number } },
	lanes: { { number } }?, -- ways people walk: { x1, z1, x2, z2 }, kept clear `laneHalf` to each side
	laneHalf: number?,
}
export type Placed = {
	name: string,
	kind: string,
	room: string,
	x: number,
	z: number,
	q: number,
	piece: Furniture.Piece?,
	fixed: boolean,
	pinned: boolean?, -- from the template: keeps its template name and hide type
	hide: string?,
	hideX: number?,
	hideZ: number?,
	dress: string?,
	wall: number?, -- the wall its back stands on
	along: number?,
	hx: number,
	hz: number,
	w: number?,
	seats: number?,
}
export type LayoutResult = { placed: { Placed }, skipped: { string }, unreached: { string } }

-- Room kinds by room id (data/interiors, data/buildings).
local KIND_BY_ID: { [string]: string } = {
	living = "living",
	kitchen = "kitchen",
	bedroom = "bedroom",
	bath = "bath",
	hall = "hall",
	dining = "dining",
	study = "study",
	den = "den",
	pantry = "pantry",
	reception = "reception",
	triage = "triage",
	pharmacy = "pharmacy",
	ward_a = "ward",
	ward_b = "ward",
	isolation = "isolation",
	staff_room = "staff",
	supply = "supply",
	lobby = "lobby",
	briefing = "briefing",
	dispatch = "dispatch",
	back_office = "lockers",
}

function Furnish.roomKind(_buildingId: string, roomId: string): string
	return KIND_BY_ID[roomId] or "generic"
end

-- What goes in a room, in placement order. `req` pieces are what the room is for (InteriorCheck holds
-- the same lists independently); the rest make it lived-in and are dropped first when space is short.
Furnish.RECIPES = {
	living = {
		{ kind = "sofa", pref = "A", req = true },
		{ kind = "tv_stand", pref = "facing:sofa", req = true },
		{ kind = "coffee_table", pref = "front:sofa", dist = 1.5, req = true },
		{ kind = "rug", pref = "under:sofa", shift = 1.0, w = 10, req = true },
		{ kind = "armchair", pref = "near:sofa", req = true },
		{ kind = "bookshelf", pref = "corner", req = true },
		{ kind = "floor_lamp", pref = "near:sofa", req = true },
		{ kind = "sideboard", pref = "B" },
		{ kind = "plant", pref = "corner", variant = 1 },
		{ kind = "picture", pref = "hang" },
		{ kind = "picture", pref = "hang", variant = 2 },
	},
	kitchen = {
		{ kind = "counter_run", pref = "A", req = true },
		{ kind = "fridge", pref = "near:counter_run", req = true },
		{ kind = "dining_set", pref = "centre", req = true },
		{ kind = "rug", pref = "under:dining_set", shift = 0, w = 11 },
		{ kind = "sideboard", pref = "B" },
		{ kind = "plant", pref = "corner" },
		{ kind = "picture", pref = "hang", variant = 3 },
	},
	bedroom = {
		{ kind = "bed", pref = "A", req = true },
		{ kind = "nightstand", pref = "near:bed", req = true },
		{ kind = "wardrobe", pref = "corner", req = true },
		{ kind = "rug", pref = "under:bed", shift = 0.35, w = 9, req = true },
		{ kind = "armchair", pref = "corner" },
		{ kind = "floor_lamp", pref = "near:armchair" },
		{ kind = "plant", pref = "corner" },
		{ kind = "picture", pref = "hang", variant = 1 },
		{ kind = "picture", pref = "hang", variant = 4 },
	},
	bath = {
		{ kind = "bathtub", pref = "A", req = true },
		{ kind = "toilet", pref = "corner", req = true },
		{ kind = "basin", pref = "B", req = true },
		{ kind = "mirror", pref = "above:basin", req = true },
		{ kind = "plant", pref = "corner" },
	},
	hall = {
		{ kind = "shoe_bench", pref = "A", frac = 0.25, req = true },
		{ kind = "coat_hooks", pref = "hang", req = true },
		{ kind = "plant", pref = "corner", variant = 1 },
		{ kind = "picture", pref = "hang", variant = 2 },
		{ kind = "picture", pref = "hang", variant = 1 },
	},
	dining = {
		{ kind = "dining_set", pref = "centre", seats = 6, req = true },
		{ kind = "sideboard", pref = "A", req = true },
		{ kind = "rug", pref = "under:dining_set", shift = 0, w = 12 },
		{ kind = "plant", pref = "corner", variant = 1 },
		{ kind = "picture", pref = "hang", variant = 0 },
		{ kind = "picture", pref = "hang", variant = 3 },
	},
	study = {
		{ kind = "desk", pref = "A", req = true },
		{ kind = "bookshelf", pref = "corner", req = true },
		{ kind = "armchair", pref = "corner" },
		{ kind = "rug", pref = "under:desk", shift = 1.2, w = 8 },
		{ kind = "floor_lamp", pref = "near:armchair" },
		{ kind = "picture", pref = "hang", variant = 4 },
	},
	den = {
		{ kind = "armchair", pref = "A", frac = 0.35, req = true },
		{ kind = "bookshelf", pref = "corner", req = true },
		{ kind = "desk", pref = "B" },
		{ kind = "rug", pref = "under:armchair", shift = 1.4, w = 8 },
		{ kind = "floor_lamp", pref = "near:armchair" },
		{ kind = "plant", pref = "corner" },
		{ kind = "picture", pref = "hang", variant = 2 },
	},
	pantry = {
		{ kind = "pantry_shelf", pref = "A", frac = 0.3, req = true },
		{ kind = "pantry_shelf", pref = "A", frac = 0.7, variant = 1, req = true },
		{ kind = "pantry_shelf", pref = "B", variant = 2 },
		{ kind = "fridge", pref = "corner" },
	},
	generic = {
		{ kind = "plant", pref = "corner" },
	},
} :: { [string]: { Item } }

-- `n` of a kind spread evenly along a wall (A, B, C or D).
local function spread(kind: string, wall: string, n: number, req: boolean?, variant: number?, seats: number?): { Item }
	local out: { Item } = {}
	for i = 1, n do
		table.insert(out, {
			kind = kind,
			pref = wall,
			frac = (i - 0.5) / n,
			req = req,
			variant = if variant then variant + i else nil,
			seats = seats,
		})
	end
	return out
end
local function compose(...: { Item } | Item): { Item }
	local out: { Item } = {}
	for _, part in { ... } do
		local p: any = part
		if p.kind then
			table.insert(out, p)
		else
			for _, item in p do
				table.insert(out, item)
			end
		end
	end
	return out
end

-- The big blocks: the hospital (worldgen_districts_art §2: reception and waiting, triage bays, wards of
-- curtained beds, isolation, pharmacy, staff room, supply) and the police station (lobby, briefing
-- room, dispatch, lockers and the holding cell). Their rooms are 60 to 120 st across, so pieces come
-- in rows.
Furnish.RECIPES.reception = compose(
	spread("waiting_row", "C", 3, true),
	spread("waiting_row", "D", 3, true),
	{ kind = "waiting_row", pref = "centre", seats = 5 },
	{ kind = "plant", pref = "corner", variant = 1 },
	{ kind = "plant", pref = "corner", variant = 1 },
	{ kind = "plant", pref = "corner", variant = 1 },
	{ kind = "notice_board", pref = "hang" },
	{ kind = "picture", pref = "hang", variant = 1 },
	{ kind = "picture", pref = "hang", variant = 3 }
)
Furnish.RECIPES.triage = compose(
	spread("treatment_bay", "A", 4, true),
	spread("waiting_row", "B", 2, false, nil, 3),
	{ kind = "medicine_cabinet", pref = "hang", req = true },
	{ kind = "medicine_cabinet", pref = "hang" },
	{ kind = "basin", pref = "corner" },
	{ kind = "plant", pref = "corner" },
	{ kind = "plant", pref = "corner", variant = 1 }
)
Furnish.RECIPES.pharmacy = compose(
	{ kind = "medicine_cabinet", pref = "hang", req = true },
	{ kind = "medicine_cabinet", pref = "hang", req = true },
	{ kind = "medicine_cabinet", pref = "hang" },
	spread("pantry_shelf", "A", 4, false, 9),
	spread("waiting_row", "C", 2, false, nil, 3),
	{ kind = "plant", pref = "corner", variant = 1 },
	{ kind = "plant", pref = "corner" }
)
Furnish.RECIPES.ward = compose(
	spread("ward_bed", "A", 6, true),
	spread("ward_bed", "B", 6, true),
	{ kind = "medicine_cabinet", pref = "hang", req = true },
	{ kind = "medicine_cabinet", pref = "hang" },
	{ kind = "basin", pref = "corner" },
	{ kind = "basin", pref = "corner" },
	{ kind = "waiting_row", pref = "C", seats = 3 },
	{ kind = "waiting_row", pref = "D", seats = 3 },
	{ kind = "plant", pref = "corner", variant = 1 },
	{ kind = "plant", pref = "corner", variant = 1 }
)
Furnish.RECIPES.isolation = compose(
	spread("ward_bed", "A", 3, true),
	{ kind = "iv_stand", pref = "near:ward_bed" },
	{ kind = "iv_stand", pref = "corner" },
	{ kind = "medicine_cabinet", pref = "hang", req = true },
	{ kind = "medicine_cabinet", pref = "hang" },
	{ kind = "basin", pref = "corner" },
	{ kind = "waiting_row", pref = "B", seats = 3 },
	{ kind = "plant", pref = "corner" }
)
Furnish.RECIPES.staff = compose(
	{ kind = "counter_run", pref = "A", req = true, w = 14 },
	{ kind = "fridge", pref = "near:counter_run", req = true },
	{ kind = "dining_set", pref = "centre", seats = 6, req = true },
	{ kind = "sofa", pref = "B", frac = 0.3 },
	{ kind = "coffee_table", pref = "front:sofa", dist = 1.5 },
	{ kind = "armchair", pref = "near:sofa" },
	{ kind = "sofa", pref = "B", frac = 0.7 },
	spread("locker_bank", "C", 2),
	{ kind = "bookshelf", pref = "D" },
	{ kind = "plant", pref = "corner", variant = 1 },
	{ kind = "plant", pref = "corner", variant = 1 },
	{ kind = "notice_board", pref = "hang", variant = 1 },
	{ kind = "picture", pref = "hang", variant = 2 }
)
Furnish.RECIPES.supply = compose(
	spread("pantry_shelf", "A", 6, true, 9),
	spread("pantry_shelf", "B", 6, false, 10),
	spread("pantry_shelf", "C", 3, false, 11),
	{ kind = "medicine_cabinet", pref = "hang", req = true },
	{ kind = "medicine_cabinet", pref = "hang" },
	{ kind = "fridge", pref = "corner" },
	{ kind = "fridge", pref = "corner" }
)
Furnish.RECIPES.lobby = compose(
	spread("waiting_row", "C", 2, true),
	spread("waiting_row", "D", 2, true),
	{ kind = "notice_board", pref = "hang", req = true },
	{ kind = "notice_board", pref = "hang", variant = 1 },
	{ kind = "plant", pref = "corner", variant = 1 },
	{ kind = "plant", pref = "corner", variant = 1 },
	{ kind = "plant", pref = "corner" },
	{ kind = "picture", pref = "hang", variant = 1 }
)
Furnish.RECIPES.briefing = compose(
	{ kind = "briefing_row", pref = "front:station", dist = 5.5, face = true, req = true },
	{ kind = "briefing_row", pref = "front:station", dist = 9.5, face = true, req = true },
	{ kind = "briefing_row", pref = "front:station", dist = 13.5, face = true },
	{ kind = "briefing_row", pref = "front:station", dist = 17.5, face = true },
	{ kind = "desk", pref = "A", frac = 0.8 },
	spread("pantry_shelf", "B", 2, false, 9),
	{ kind = "notice_board", pref = "hang", variant = 1 },
	{ kind = "notice_board", pref = "hang" },
	{ kind = "plant", pref = "corner" },
	{ kind = "plant", pref = "corner", variant = 1 }
)
Furnish.RECIPES.dispatch = compose(
	spread("desk", "A", 3, true),
	{ kind = "desk", pref = "B", frac = 0.25 },
	spread("pantry_shelf", "C", 2, false, 9),
	{ kind = "notice_board", pref = "hang" },
	{ kind = "notice_board", pref = "hang", variant = 1 },
	{ kind = "plant", pref = "corner", variant = 1 },
	{ kind = "plant", pref = "corner" }
)
Furnish.RECIPES.lockers = compose(
	{ kind = "cell", pref = "corner", req = true },
	{ kind = "cell", pref = "near:cell" },
	spread("locker_bank", "A", 3, true),
	spread("locker_bank", "B", 2),
	{ kind = "waiting_row", pref = "centre", seats = 4 },
	{ kind = "shoe_bench", pref = "C" },
	{ kind = "shoe_bench", pref = "D" },
	{ kind = "notice_board", pref = "hang", variant = 1 },
	{ kind = "plant", pref = "corner" }
)

export type Finish = { floor: { number }, floorMaterial: string, wall: { number }, skirt: { number } }

local function fin(floor: { number }, material: string, wall: { number }, skirt: { number }?): Finish
	return { floor = floor, floorMaterial = material, wall = wall, skirt = skirt or { 238, 232, 216 } }
end

-- Per-room floors and walls (wood, tile and carpet tones; the hospital in its v5.4 floor #b9c4ba, tile
-- #e5eee9 and wall #a5ada9).
Furnish.FINISH = {
	living = fin({ 176, 137, 96 }, "WoodPlanks", { 226, 214, 190 }),
	kitchen = fin({ 214, 208, 196 }, "CeramicTiles", { 214, 222, 200 }),
	bedroom = fin({ 168, 160, 172 }, "Carpet", { 204, 212, 220 }),
	bath = fin({ 196, 214, 214 }, "CeramicTiles", { 228, 238, 233 }),
	hall = fin({ 150, 112, 78 }, "WoodPlanks", { 234, 226, 206 }),
	dining = fin({ 160, 120, 84 }, "WoodPlanks", { 208, 190, 170 }),
	study = fin({ 140, 104, 74 }, "WoodPlanks", { 190, 200, 184 }),
	den = fin({ 150, 140, 122 }, "Carpet", { 198, 190, 170 }),
	pantry = fin({ 196, 190, 176 }, "CeramicTiles", { 232, 226, 210 }),
	reception = fin({ 201, 210, 202 }, "CeramicTiles", { 229, 238, 233 }, { 98, 142, 157 }),
	triage = fin({ 185, 196, 186 }, "CeramicTiles", { 229, 238, 233 }, { 189, 161, 125 }),
	pharmacy = fin({ 214, 220, 214 }, "CeramicTiles", { 236, 240, 234 }, { 98, 142, 157 }),
	ward = fin({ 185, 196, 186 }, "CeramicTiles", { 218, 230, 226 }, { 108, 169, 158 }),
	isolation = fin({ 178, 190, 184 }, "CeramicTiles", { 226, 232, 222 }, { 189, 161, 125 }),
	staff = fin({ 142, 156, 152 }, "Carpet", { 224, 220, 204 }, { 165, 173, 169 }),
	supply = fin({ 170, 172, 168 }, "Concrete", { 214, 216, 210 }, { 165, 173, 169 }),
	lobby = fin({ 176, 186, 190 }, "CeramicTiles", { 214, 220, 222 }, { 52, 72, 82 }),
	briefing = fin({ 110, 126, 136 }, "Carpet", { 206, 212, 214 }, { 52, 72, 82 }),
	dispatch = fin({ 96, 108, 116 }, "Carpet", { 196, 204, 208 }, { 52, 72, 82 }),
	lockers = fin({ 160, 162, 158 }, "Concrete", { 204, 208, 206 }, { 52, 72, 82 }),
	generic = fin({ 170, 164, 150 }, "Concrete", { 226, 222, 210 }),
} :: { [string]: Finish }

-- Which Furniture.dress goes round a station of each kind.
local STATION_DRESS: { [string]: string } = {
	admit = "desk",
	triage = "desk",
	dispense = "desk",
	desk = "desk",
	treat = "console",
	drone_console = "console",
	quest_board = "board",
}
Furnish.STATION_DRESS = STATION_DRESS

-- Template furniture kits -> library kinds.
local KIT_KIND: { [string]: string } = {
	sofa = "sofa",
	bed = "bed",
	wardrobe = "wardrobe",
	counter = "counter_run",
	bookshelf = "bookshelf",
	pantry_shelf = "pantry_shelf",
	table = "dining_set",
}
Furnish.KIT_KIND = KIT_KIND

local WALL_Q = { 0, 1, 2, 3 } -- wall 1 back (+z), 2 right (+x), 3 front (-z), 4 left (-x)

-- Lays one room out. Pure and deterministic.
function Furnish.layout(room: Room, recipe: { Item }, tones: Furniture.Tones): LayoutResult
	local CELL, OFF, BODY = Furnish.CELL, Furnish.OFF, Furnish.BODY
	local x0, x1, z0, z1 = room.x0, room.x1, room.z0, room.z1
	local nx = math.max(1, math.ceil((x1 - x0) / CELL - 1e-6))
	local nz = math.max(1, math.ceil((z1 - z0) / CELL - 1e-6))
	local keep: { boolean } = table.create(nx * nz, false) -- no floor piece here
	local gate: { boolean } = table.create(nx * nz, false) -- doorways and standing room: nothing at all
	local occ: { boolean } = table.create(nx * nz, false) -- a floor piece stands here
	local walk: { boolean } = table.create(nx * nz, false) -- a body cannot stand here
	local seen: { number } = table.create(nx * nz, 0)
	local stamp = 0
	local placed: { Placed } = {}
	local skipped: { string } = {}
	local unreached: { string } = {}
	local mountedOn: { { { a: number, hw: number, bottom: number, top: number } } } = { {}, {}, {}, {} }
	local against: { { { a: number, hw: number, h: number } } } = { {}, {}, {}, {} }
	local rugs: { { number } } = {}

	local function cells(a0: number, a1: number, origin: number, n: number): (number, number)
		local i0 = math.floor((a0 - origin) / CELL + 1e-6)
		local i1 = math.ceil((a1 - origin) / CELL - 1e-6) - 1
		return math.max(i0, 0), math.min(i1, n - 1)
	end
	local function mark(arr: { boolean }, rx0: number, rx1: number, rz0: number, rz1: number)
		local i0, i1 = cells(rx0, rx1, x0, nx)
		local j0, j1 = cells(rz0, rz1, z0, nz)
		for j = j0, j1 do
			for i = i0, i1 do
				arr[j * nx + i + 1] = true
			end
		end
	end
	local function hit(arr: { boolean }, rx0: number, rx1: number, rz0: number, rz1: number): boolean
		local i0, i1 = cells(rx0, rx1, x0, nx)
		local j0, j1 = cells(rz0, rz1, z0, nz)
		for j = j0, j1 do
			for i = i0, i1 do
				if arr[j * nx + i + 1] then
					return true
				end
			end
		end
		return false
	end
	local function inRoom(rx0: number, rx1: number, rz0: number, rz1: number, m: number): boolean
		return rx0 >= x0 + m - 1e-6 and rx1 <= x1 - m + 1e-6 and rz0 >= z0 + m - 1e-6 and rz1 <= z1 - m + 1e-6
	end

	-- walls: the band a body cannot enter, all round
	mark(walk, x0, x1, z0, z0 + BODY)
	mark(walk, x0, x1, z1 - BODY, z1)
	mark(walk, x0, x0 + BODY, z0, z1)
	mark(walk, x1 - BODY, x1, z0, z1)

	local function wallLo(k: number): (number, number)
		if k == 1 or k == 3 then
			return x0, x1
		end
		return z0, z1
	end
	-- the room-side point `depth` in from wall k at `a` along it
	local function inward(k: number, a: number, depth: number): (number, number)
		if k == 1 then
			return a, z1 - depth
		elseif k == 3 then
			return a, z0 + depth
		elseif k == 2 then
			return x1 - depth, a
		end
		return x0 + depth, a
	end
	local function doorAlong(d: DoorIn): number
		return if d.wall == 1 or d.wall == 3 then d.x else d.z
	end

	-- 1. keep-outs: the floor a door swings over and a body steps onto, and the staff discs
	for _, d in room.doors do
		local a = doorAlong(d)
		local depth = math.min(d.w, 6.5) + 0.5
		local half = d.w / 2 + 0.25
		local ax, az = inward(d.wall, a - half, 0)
		local bx, bz = inward(d.wall, a + half, depth)
		mark(keep, math.min(ax, bx), math.max(ax, bx), math.min(az, bz), math.max(az, bz))
		mark(gate, math.min(ax, bx), math.max(ax, bx), math.min(az, bz), math.max(az, bz))
	end
	for _, c in room.discs do
		for j = 0, nz - 1 do
			for i = 0, nx - 1 do
				local px, pz = x0 + (i + 0.5) * CELL, z0 + (j + 0.5) * CELL
				if (px - c.x) ^ 2 + (pz - c.z) ^ 2 <= c.r * c.r then
					keep[j * nx + i + 1] = true
					gate[j * nx + i + 1] = true
				end
			end
		end
	end
	-- the ways people walk (kinematic staff and patients stop for nothing): every cell the lane's
	-- band touches
	for _, l in room.lanes or {} do
		local hw = (room.laneHalf or Furnish.BODY) + CELL * 0.71
		local i0, i1 = cells(math.min(l[1], l[3]) - hw, math.max(l[1], l[3]) + hw, x0, nx)
		local j0, j1 = cells(math.min(l[2], l[4]) - hw, math.max(l[2], l[4]) + hw, z0, nz)
		local abx, abz = l[3] - l[1], l[4] - l[2]
		local len2 = math.max(abx * abx + abz * abz, 1e-9)
		for j = j0, j1 do
			for i = i0, i1 do
				local px, pz = x0 + (i + 0.5) * CELL, z0 + (j + 0.5) * CELL
				local f = math.clamp(((px - l[1]) * abx + (pz - l[2]) * abz) / len2, 0, 1)
				if (px - l[1] - abx * f) ^ 2 + (pz - l[2] - abz * f) ^ 2 <= hw * hw then
					keep[j * nx + i + 1] = true
					gate[j * nx + i + 1] = true
				end
			end
		end
	end

	-- walls by free length: A the freest, B the one opposite it, then C and D
	local free: { number } = {}
	for k = 1, 4 do
		local lo, hi = wallLo(k)
		local len = hi - lo
		for _, d in room.doors do
			if d.wall == k then
				len -= d.w + 1.2
			end
		end
		free[k] = len
	end
	local A = 1
	for k = 2, 4 do
		if free[k] > free[A] + 1e-6 then
			A = k
		end
	end
	local B = (A + 1) % 4 + 1
	local C = A % 4 + 1
	local D = (C + 1) % 4 + 1
	if free[D] > free[C] + 1e-6 then
		C, D = D, C
	end
	local WALLS: { [string]: number } = { A = A, B = B, C = C, D = D }
	local RANK: { number } = {}
	RANK[A], RANK[B], RANK[C], RANK[D] = 0, 1, 2, 3

	local function wallRect(k: number, a: number, fw: number, fd: number, off: number): (number, number, number, number)
		if k == 1 then
			return a, z1 - off - fd / 2, fw / 2, fd / 2
		elseif k == 3 then
			return a, z0 + off + fd / 2, fw / 2, fd / 2
		elseif k == 2 then
			return x1 - off - fd / 2, a, fd / 2, fw / 2
		end
		return x0 + off + fd / 2, a, fd / 2, fw / 2
	end

	local function find(kind: string): Placed?
		for _, p in placed do
			if p.kind == kind then
				return p
			end
		end
		return nil
	end

	-- 3. walkways. Where a body must be able to get: in at every door, to the middle of the room and
	-- to every pinned piece. A candidate spot is taken only if all of them can still be reached from the
	-- first door, by a body BODY st in radius, with the candidate in place.
	local targets: { { label: string, x: number, z: number, reach: number } } = {}
	local cxr, czr = (x0 + x1) / 2, (z0 + z1) / 2
	local startX, startZ = cxr, czr
	for i, d in room.doors do
		local sx, sz = inward(d.wall, doorAlong(d), 1.5)
		if i == 1 then
			startX, startZ = sx, sz
		else
			table.insert(targets, { label = "door " .. d.id, x = sx, z = sz, reach = 1.0 })
		end
	end
	table.insert(targets, { label = "centre", x = cxr, z = czr, reach = 7 })
	local function cellOf(px: number, pz: number): (number, number)
		return math.clamp(math.floor((px - x0) / CELL), 0, nx - 1), math.clamp(math.floor((pz - z0) / CELL), 0, nz - 1)
	end
	local queue: { number } = table.create(nx * nz, 0)
	-- how many targets a body reaches, with an extra blocking rect (already inflated) in place
	local function reached(bx0: number?, bx1: number?, bz0: number?, bz1: number?, missing: { string }?): number
		stamp += 1
		local ti0, ti1, tj0, tj1 = 1, 0, 1, 0
		if bx0 and bx1 and bz0 and bz1 then
			ti0, ti1 = cells(bx0, bx1, x0, nx)
			tj0, tj1 = cells(bz0, bz1, z0, nz)
		end
		local si, sj = cellOf(startX, startZ)
		local head, tail = 1, 1
		queue[1] = sj * nx + si + 1
		seen[queue[1]] = stamp
		while head <= tail do
			local k = queue[head]
			head += 1
			local i, j = (k - 1) % nx, (k - 1) // nx
			for dj = -1, 1 do
				for di = -1, 1 do
					local ii, jj = i + di, j + dj
					if (di ~= 0 or dj ~= 0) and ii >= 0 and ii < nx and jj >= 0 and jj < nz then
						local kk = jj * nx + ii + 1
						if
							seen[kk] ~= stamp
							and not walk[kk]
							and not (ii >= ti0 and ii <= ti1 and jj >= tj0 and jj <= tj1)
						then
							seen[kk] = stamp
							tail += 1
							queue[tail] = kk
						end
					end
				end
			end
		end
		local n = 0
		for _, t in targets do
			local ci, cj = cellOf(t.x, t.z)
			local r = math.ceil(t.reach / CELL)
			local ok = false
			for j = math.max(cj - r, 0), math.min(cj + r, nz - 1) do
				for i = math.max(ci - r, 0), math.min(ci + r, nx - 1) do
					if
						not ok
						and seen[j * nx + i + 1] == stamp
						and (x0 + (i + 0.5) * CELL - t.x) ^ 2 + (z0 + (j + 0.5) * CELL - t.z) ^ 2 <= t.reach * t.reach
					then
						ok = true
					end
				end
			end
			if ok then
				n += 1
			elseif missing then
				table.insert(missing, t.label)
			end
		end
		return n
	end
	local reachedNow = reached()
	-- may a blocking piece stand on this rect? (no target is lost)
	local function passable(cx: number, cz: number, hx: number, hz: number): boolean
		return reached(cx - hx - BODY, cx + hx + BODY, cz - hz - BODY, cz + hz + BODY) >= reachedNow
	end

	local function commit(p: Placed, blocks: boolean, clear: number)
		table.insert(placed, p)
		local piece = p.piece
		if piece and piece.mounted then
			if p.wall then
				table.insert(
					mountedOn[p.wall],
					{ a = p.along :: number, hw = piece.w / 2, bottom = piece.mounted, top = piece.h }
				)
			end
			return
		end
		local rx0, rx1, rz0, rz1 = p.x - p.hx, p.x + p.hx, p.z - p.hz, p.z + p.hz
		mark(occ, rx0, rx1, rz0, rz1)
		if blocks then
			mark(walk, rx0 - BODY, rx1 + BODY, rz0 - BODY, rz1 + BODY)
		end
		if p.wall and piece then
			table.insert(against[p.wall], { a = p.along :: number, hw = piece.w / 2, h = piece.h })
			if piece.h > 2.0 then
				for _, w in room.windows do
					if w.wall == p.wall and math.abs((p.along :: number) - w.c) < piece.w / 2 + w.w / 2 + 0.9 then
						w.covered = true
					end
				end
			end
		end
		if clear > 0 then
			-- the floor in front stays free of other pieces (a body may cross it)
			local bx, bz = Furniture.backDir(p.q)
			local fx0, fx1 = p.x - p.hx, p.x + p.hx
			local fz0, fz1 = p.z - p.hz, p.z + p.hz
			if bx > 0 then
				fx0, fx1 = p.x - p.hx - clear, p.x - p.hx
			elseif bx < 0 then
				fx0, fx1 = p.x + p.hx, p.x + p.hx + clear
			elseif bz > 0 then
				fz0, fz1 = p.z - p.hz - clear, p.z - p.hz
			else
				fz0, fz1 = p.z + p.hz, p.z + p.hz + clear
			end
			mark(keep, fx0, fx1, fz0, fz1)
		end
	end

	-- is the floor rect of a piece free? (inside the room, off the keep-outs, clear of other pieces)
	local function floorOk(cx: number, cz: number, hx: number, hz: number, margin: number, mask: { boolean }?): boolean
		local rx0, rx1, rz0, rz1 = cx - hx, cx + hx, cz - hz, cz + hz
		if not inRoom(rx0, rx1, rz0, rz1, margin) then
			return false
		end
		if hit(mask or keep, rx0, rx1, rz0, rz1) then
			return false
		end
		return not hit(occ, rx0 - 0.3, rx1 + 0.3, rz0 - 0.3, rz1 + 0.3)
	end
	local function frontOk(cx: number, cz: number, hx: number, hz: number, q: number, clear: number): boolean
		if clear <= 0 then
			return true
		end
		local bx, bz = Furniture.backDir(q)
		local fx0, fx1, fz0, fz1 = cx - hx, cx + hx, cz - hz, cz + hz
		if bx > 0 then
			fx0, fx1 = cx - hx - clear, cx - hx
		elseif bx < 0 then
			fx0, fx1 = cx + hx, cx + hx + clear
		elseif bz > 0 then
			fz0, fz1 = cz - hz - clear, cz - hz
		else
			fz0, fz1 = cz + hz, cz + hz + clear
		end
		return inRoom(fx0, fx1, fz0, fz1, 0) and not hit(occ, fx0, fx1, fz0, fz1)
	end
	-- may a piece of height h stand against wall k over [a - hw, a + hw]? (not across a window if it
	-- is tall, not under a hung piece it would reach)
	local function wallOk(k: number, a: number, hw: number, h: number): boolean
		if h > 4.6 then
			for _, w in room.windows do
				if w.wall == k and math.abs(a - w.c) < hw + w.w / 2 + 0.9 then
					return false
				end
			end
		end
		for _, m in mountedOn[k] do
			if m.bottom < h + 0.3 and math.abs(a - m.a) < hw + m.hw + 0.3 then
				return false
			end
		end
		return true
	end

	-- 2. pinned pieces
	for _, pin in room.pins do
		if pin.fixed and pin.optional then
			-- a column of the grid: only where the floor is not needed
			local piece = Furniture.piece(pin.kind, tones, { w = pin.w })
			local hx, hz = piece.w / 2, piece.d / 2
			if
				inRoom(pin.x - hx, pin.x + hx, pin.z - hz, pin.z + hz, 3)
				and not hit(gate, pin.x - hx - 1, pin.x + hx + 1, pin.z - hz - 1, pin.z + hz + 1)
				and not hit(occ, pin.x - hx - 3, pin.x + hx + 3, pin.z - hz - 3, pin.z + hz + 3)
				and passable(pin.x, pin.z, hx, hz)
			then
				commit({
					name = pin.id,
					kind = pin.kind,
					room = room.id,
					x = pin.x,
					z = pin.z,
					q = 0,
					piece = piece,
					fixed = false,
					hx = hx,
					hz = hz,
				}, true, 0)
				reachedNow = reached()
			end
		elseif pin.fixed then
			local hx, hz = (pin.sx or 6) / 2, (pin.sz or 2.5) / 2
			local q = 0
			local cz = pin.z
			if pin.dress == "shelf" then
				-- shelf boards stand out on the slot side
				hx, hz, cz = hx + 0.35, 1.45, pin.z - 0.55
			elseif pin.dress then
				-- the dressed desk faces the room's nearest door (front or back: the box is not turned)
				local best = math.huge
				for _, d in room.doors do
					local dd = (d.x - pin.x) ^ 2 + (d.z - pin.z) ^ 2
					if dd < best then
						best = dd
						q = if d.z > pin.z + 1e-6 then 2 else 0
					end
				end
				hx, hz = 4.5, 1.8
			end
			local p: Placed = {
				name = pin.id,
				kind = pin.kind,
				room = room.id,
				x = pin.x,
				z = cz,
				q = q,
				fixed = true,
				dress = pin.dress,
				hx = hx,
				hz = hz,
				w = pin.w,
				seats = pin.seats,
			}
			commit(p, true, 0)
			-- the floor a body stands on to use it stays free
			mark(keep, p.x - hx - 2.5, p.x + hx + 2.5, cz - hz - 3, cz + hz + 3)
			mark(gate, p.x - hx - 2.5, p.x + hx + 2.5, cz - hz - 3, cz + hz + 3)
			p.z = pin.z
			table.insert(targets, { label = pin.id, x = pin.x, z = pin.z, reach = math.max(hx, hz) + 3.5 })
			reachedNow = reached()
		else
			local piece = Furniture.piece(pin.kind, tones, { w = pin.w, seats = pin.seats })
			local low: Furniture.Piece? = if pin.kind == "counter_run"
				then Furniture.piece(pin.kind, tones, { w = pin.w, variant = 1 })
				else nil
			local gap = if pin.hide == "behind" then 2.6 else 0
			-- orientations, the wall nearest the template spot first
			local order = { 1, 2, 3, 4 }
			local function wallDist(k: number): number
				if k == 1 then
					return z1 - pin.z
				elseif k == 3 then
					return pin.z - z0
				elseif k == 2 then
					return x1 - pin.x
				end
				return pin.x - x0
			end
			table.sort(order, function(k1, k2)
				local d1, d2 = wallDist(k1), wallDist(k2)
				if math.abs(d1 - d2) > 1e-6 then
					return d1 < d2
				end
				return k1 < k2
			end)
			local done = false
			local function take(k: number, cx: number, cz: number, flush: boolean)
				local q = WALL_Q[k]
				local fw, fd = Furniture.footprint(piece, q)
				local hx, hz = fw / 2, fd / 2
				local bx, bz = Furniture.backDir(q)
				-- room for the hiding gap behind
				local gx0, gx1, gz0, gz1 = cx - hx, cx + hx, cz - hz, cz + hz
				if gap > 0 then
					if bx > 0 then
						gx1 += gap
					elseif bx < 0 then
						gx0 -= gap
					elseif bz > 0 then
						gz1 += gap
					else
						gz0 -= gap
					end
				end
				local along = if k == 1 or k == 3 then cx else cz
				if
					inRoom(gx0, gx1, gz0, gz1, OFF - 1e-6)
					and floorOk(cx, cz, hx, hz, OFF - 1e-6)
					and not hit(occ, gx0, gx1, gz0, gz1)
					and (not flush or wallOk(k, along, (if k == 1 or k == 3 then hx else hz), piece.h))
					and (not flush or frontOk(cx, cz, hx, hz, q, piece.clear))
					and passable(cx, cz, hx, hz)
				then
					local p: Placed = {
						name = pin.id,
						kind = pin.kind,
						room = room.id,
						x = cx,
						z = cz,
						q = q,
						piece = piece,
						fixed = false,
						pinned = true,
						hide = pin.hide,
						hx = hx,
						hz = hz,
						wall = if flush then k else nil,
						along = along,
						w = pin.w,
						seats = pin.seats,
					}
					if pin.hide == "behind" then
						p.hideX, p.hideZ = cx + bx * (hx + 1.3), cz + bz * (hz + 1.3)
						-- the gap itself stays free
						mark(keep, gx0, gx1, gz0, gz1)
					elseif pin.hide then
						p.hideX, p.hideZ = cx, cz
					end
					commit(p, true, piece.clear)
					table.insert(targets, {
						label = pin.id,
						x = p.hideX or cx,
						z = p.hideZ or cz,
						reach = math.max(hx, hz) + 3.5,
					})
					reachedNow = reached()
					done = true
				end
			end
			if gap == 0 and pin.kind ~= "dining_set" then
				-- a wall piece: flush against a wall, as near its template spot as the doors, windows
				-- and walkways allow (every wall, every quarter stud along it, nearest first)
				local cands: { { number } } = {}
				for _, k in order do
					local q = WALL_Q[k]
					local fw, fd = Furniture.footprint(piece, q)
					local lo, hi = wallLo(k)
					local fa = if k == 1 or k == 3 then fw else fd
					local a = lo + fa / 2 + OFF
					while a <= hi - fa / 2 - OFF + 1e-6 do
						local cx, cz = wallRect(k, a, piece.w, piece.d, OFF)
						table.insert(cands, { (cx - pin.x) ^ 2 + (cz - pin.z) ^ 2, #cands, k, cx, cz })
						a += CELL / 2
					end
				end
				table.sort(cands, function(c1, c2)
					if c1[1] ~= c2[1] then
						return c1[1] < c2[1]
					end
					return c1[2] < c2[2]
				end)
				for _, c in cands do
					if not done then
						take(c[3], c[4], c[5], true)
					end
				end
				if not done and low then
					-- no stretch of wall without a window: the run goes under one, without wall cupboards
					piece = low
					for _, c in cands do
						if not done then
							take(c[3], c[4], c[5], true)
						end
					end
				end
			else
				-- free-standing (a sofa to hide behind, a table): the valid spot nearest the template
				-- position, on a growing square ring, its back to the nearest wall
				for ring = 0, 24 do
					for _, k in order do
						for dj = -ring, ring do
							for di = -ring, ring do
								if not done and math.max(math.abs(di), math.abs(dj)) == ring then
									take(k, pin.x + di * CELL, pin.z + dj * CELL, false)
								end
							end
						end
					end
					if done then
						break
					end
				end
			end
			if not done then
				table.insert(skipped, pin.kind)
			end
		end
	end
	if reachedNow < #targets then
		reached(nil, nil, nil, nil, unreached)
	end

	-- 4. recipe pieces
	local counts: { [string]: number } = {}
	local function nameOf(kind: string): string
		counts[kind] = (counts[kind] or 0) + 1
		return `Furniture_{room.id}_{kind}` .. (if counts[kind] > 1 then tostring(counts[kind]) else "")
	end
	local hasPinned: { [string]: number } = {}
	for _, p in placed do
		hasPinned[p.kind] = (hasPinned[p.kind] or 0) + 1
	end

	local function placeOnWall(
		item: Item,
		piece: Furniture.Piece,
		restrict: number?,
		score: (k: number, a: number, cx: number, cz: number) -> number
	): boolean
		local cands: { { number } } = {}
		local mounted = piece.mounted ~= nil
		for k = 1, 4 do
			if restrict == nil or restrict == k then
				local lo, hi = wallLo(k)
				local q = WALL_Q[k]
				local fw, fd = piece.w, piece.d
				local a = lo + fw / 2 + (if mounted then 0.4 else OFF)
				local last = hi - fw / 2 - (if mounted then 0.4 else OFF)
				-- candidates every quarter stud, plus the exact middle of the wall
				local list: { number } = {}
				while a <= last + 1e-6 do
					table.insert(list, a)
					a += CELL / 2
				end
				if last - (lo + fw / 2) >= -1e-6 then
					table.insert(list, (lo + hi) / 2)
				end
				for _, along in list do
					local cx, cz, hx, hz = wallRect(k, along, fw, fd, if mounted then 0.07 else OFF)
					local ok
					if mounted then
						ok = true
						for _, d in room.doors do
							if d.wall == k and math.abs(along - doorAlong(d)) < fw / 2 + d.w / 2 + 0.9 then
								ok = false
							end
						end
						for _, w in room.windows do
							if w.wall == k and math.abs(along - w.c) < fw / 2 + w.w / 2 + 1.3 then
								ok = false
							end
						end
						for _, f in against[k] do
							if
								f.h + 0.4 > (piece.mounted :: number)
								and math.abs(along - f.a) < fw / 2 + f.hw + 0.3
							then
								ok = false
							end
						end
						for _, m in mountedOn[k] do
							if math.abs(along - m.a) < fw / 2 + m.hw + 1.0 then
								ok = false
							end
						end
					else
						ok = floorOk(cx, cz, hx, hz, OFF - 1e-6)
							and frontOk(cx, cz, hx, hz, q, piece.clear)
							and wallOk(k, along, fw / 2, piece.h)
					end
					if ok then
						table.insert(cands, { score(k, along, cx, cz), #cands, k, along, cx, cz, hx, hz })
					end
				end
			end
		end
		table.sort(cands, function(c1, c2)
			if c1[1] ~= c2[1] then
				return c1[1] < c2[1]
			end
			return c1[2] < c2[2]
		end)
		-- the best spot that leaves every walkway open (a few tries: a blocked best spot usually has
		-- a free neighbour a little further along)
		local tries = 0
		for _, c in cands do
			if mounted or passable(c[5], c[6], c[7], c[8]) then
				local k = c[3]
				commit({
					name = nameOf(item.kind),
					kind = item.kind,
					room = room.id,
					x = c[5],
					z = c[6],
					q = WALL_Q[k],
					piece = piece,
					fixed = false,
					hx = c[7],
					hz = c[8],
					wall = k,
					along = c[4],
					w = item.w,
					seats = item.seats,
				}, true, piece.clear)
				return true
			end
			tries += 1
			if tries >= 40 then
				break
			end
		end
		return false
	end

	local function doorDist(cx: number, cz: number): number
		local best = math.huge
		for _, d in room.doors do
			best = math.min(best, math.sqrt((d.x - cx) ^ 2 + (d.z - cz) ^ 2))
		end
		return best
	end

	for _, item in recipe do
		if (hasPinned[item.kind] or 0) > 0 then
			-- the template already put one here
			hasPinned[item.kind] -= 1
			continue
		end
		local opts = { w = item.w, seats = item.seats, variant = item.variant }
		local pref = item.pref or "any"
		local verb, arg = string.match(pref, "^(%a+):(.+)$")
		if item.kind == "counter_run" and not item.w then
			local lo, hi = wallLo(A)
			opts.w = math.clamp(math.floor((hi - lo) * 0.55), 8, 14)
		end
		local piece = Furniture.piece(item.kind, tones, opts)
		local target: Placed? = if arg then find(arg) else nil
		local ok = false
		if verb == "front" then
			if target then
				local bx, bz = Furniture.backDir(target.q)
				local fx, fz = -bx, -bz
				local q = if item.face
					then (if fx > 0 then 1 elseif fx < 0 then 3 elseif fz > 0 then 0 else 2)
					else target.q
				local fw, fd = Furniture.footprint(piece, q)
				local reach = (if bx ~= 0 then target.hx else target.hz)
					+ (item.dist or 1.5)
					+ (if bx ~= 0 then fw else fd) / 2
				local cx, cz = target.x + fx * reach, target.z + fz * reach
				-- on the free floor in front of its target (only doorways are off limits); if that very
				-- spot is taken, the nearest free one within 4 st
				for ring = 0, 8 do
					for dj = -ring, ring do
						for di = -ring, ring do
							if not ok and math.max(math.abs(di), math.abs(dj)) == ring then
								local px, pz = cx + di * CELL, cz + dj * CELL
								if floorOk(px, pz, fw / 2, fd / 2, 0.4, gate) and passable(px, pz, fw / 2, fd / 2) then
									commit({
										name = nameOf(item.kind),
										kind = item.kind,
										room = room.id,
										x = px,
										z = pz,
										q = q,
										piece = piece,
										fixed = false,
										hx = fw / 2,
										hz = fd / 2,
									}, true, 0)
									ok = true
								end
							end
						end
					end
				end
			end
		elseif verb == "under" then
			if target then
				local bx, bz = Furniture.backDir(target.q)
				local depth = if bx ~= 0 then target.hx else target.hz
				local q = target.q
				local fw, fd = Furniture.footprint(piece, q)
				local cx = target.x - bx * depth * 2 * (item.shift or 0.5)
				local cz = target.z - bz * depth * 2 * (item.shift or 0.5)
				-- slide it inside the room; a rug never lies over another rug or in a doorway
				cx = math.clamp(cx, x0 + fw / 2 + 0.5, math.max(x0 + fw / 2 + 0.5, x1 - fw / 2 - 0.5))
				cz = math.clamp(cz, z0 + fd / 2 + 0.5, math.max(z0 + fd / 2 + 0.5, z1 - fd / 2 - 0.5))
				local r = { cx - fw / 2, cx + fw / 2, cz - fd / 2, cz + fd / 2 }
				local free2 = inRoom(r[1], r[2], r[3], r[4], 0.4)
				for _, o in rugs do
					if r[1] < o[2] and r[2] > o[1] and r[3] < o[4] and r[4] > o[3] then
						free2 = false
					end
				end
				for _, d in room.doors do
					local dx, dz = inward(d.wall, doorAlong(d), 0.6)
					if dx > r[1] - 0.5 and dx < r[2] + 0.5 and dz > r[3] - 0.5 and dz < r[4] + 0.5 then
						free2 = false
					end
				end
				if free2 then
					table.insert(rugs, r)
					table.insert(placed, {
						name = nameOf(item.kind),
						kind = item.kind,
						room = room.id,
						x = cx,
						z = cz,
						q = q,
						piece = piece,
						fixed = false,
						hx = fw / 2,
						hz = fd / 2,
					})
					ok = true
				end
			end
		elseif pref == "centre" then
			local step = if nx * nz > 8000 then 2 else 1
			local cands: { { number } } = {}
			local longX = (x1 - x0) >= (z1 - z0)
			for _, q in { if longX then 0 else 1, if longX then 1 else 0 } do
				local fw, fd = Furniture.footprint(piece, q)
				for j = 0, nz - 1, step do
					for i = 0, nx - 1, step do
						local cx, cz = x0 + i * CELL, z0 + j * CELL
						if floorOk(cx, cz, fw / 2 + 0.2, fd / 2 + 0.2, 0.8) then
							local s = (cx - cxr) ^ 2
								+ (cz - czr) ^ 2
								+ (if q == (if longX then 0 else 1) then 0 else 0.5)
							table.insert(cands, { s, #cands, cx, cz, q, fw / 2, fd / 2 })
						end
					end
				end
			end
			table.sort(cands, function(c1, c2)
				if c1[1] ~= c2[1] then
					return c1[1] < c2[1]
				end
				return c1[2] < c2[2]
			end)
			for n, c in cands do
				if passable(c[3], c[4], c[6], c[7]) then
					commit({
						name = nameOf(item.kind),
						kind = item.kind,
						room = room.id,
						x = c[3],
						z = c[4],
						q = c[5],
						piece = piece,
						fixed = false,
						hx = c[6],
						hz = c[7],
					}, true, piece.clear)
					ok = true
					break
				end
				if n >= 60 then
					break
				end
			end
		elseif verb == "above" then
			if target and target.wall then
				local ta = target.along :: number
				ok = placeOnWall(item, piece, target.wall, function(_k, a)
					return math.abs(a - ta)
				end)
			end
		elseif verb == "facing" then
			if target then
				local bx, bz = Furniture.backDir(target.q)
				-- the wall the target looks at
				local k = if bx > 0 then 4 elseif bx < 0 then 2 elseif bz > 0 then 3 else 1
				local ta = if k == 1 or k == 3 then target.x else target.z
				ok = placeOnWall(item, piece, k, function(_k, a)
					return math.abs(a - ta)
				end)
			end
			if not ok then
				ok = placeOnWall(item, piece, nil, function(k, a)
					local lo, hi = wallLo(k)
					return RANK[k] * 100 + math.abs(a - (lo + hi) / 2)
				end)
			end
		elseif verb == "near" then
			if target then
				local tx, tz = target.x, target.z
				ok = placeOnWall(item, piece, nil, function(_k, _a, cx, cz)
					return math.sqrt((cx - tx) ^ 2 + (cz - tz) ^ 2)
				end)
			end
		elseif pref == "corner" then
			ok = placeOnWall(item, piece, nil, function(k, a)
				local lo, hi = wallLo(k)
				return math.min(a - lo, hi - a) + RANK[k] * 0.01
			end)
		elseif pref == "far" then
			ok = placeOnWall(item, piece, nil, function(_k, _a, cx, cz)
				return -doorDist(cx, cz)
			end)
		elseif pref == "hang" then
			-- on the freest stretch of wall: far from other hung pieces and tall furniture
			ok = placeOnWall(item, piece, nil, function(k, a)
				local lo, hi = wallLo(k)
				local nearest = math.min(a - lo, hi - a) * 2
				for _, m in mountedOn[k] do
					nearest = math.min(nearest, math.abs(a - m.a) - m.hw)
				end
				for _, f in against[k] do
					if f.h > 3.5 then
						nearest = math.min(nearest, math.abs(a - f.a) - f.hw)
					end
				end
				for _, d in room.doors do
					if d.wall == k then
						nearest = math.min(nearest, math.abs(a - doorAlong(d)) - d.w / 2)
					end
				end
				for _, w in room.windows do
					if w.wall == k then
						nearest = math.min(nearest, math.abs(a - w.c) - w.w / 2)
					end
				end
				return -math.min(nearest, 6) + #mountedOn[k] * 2 + RANK[k] * 0.01
			end)
		else
			local k = WALLS[pref]
			local frac = item.frac or 0.5
			if k then
				local lo, hi = wallLo(k)
				local want = lo + (hi - lo) * frac
				ok = placeOnWall(item, piece, k, function(_k, a)
					return math.abs(a - want)
				end)
			end
			if not ok then
				ok = placeOnWall(item, piece, nil, function(kk, a)
					local lo, hi = wallLo(kk)
					return RANK[kk] * 100 + math.abs(a - (lo + (hi - lo) * frac))
				end)
			end
		end
		if not ok and item.kind == "counter_run" then
			opts.variant = 1
			local lowPiece = Furniture.piece(item.kind, tones, opts)
			ok = placeOnWall(item, lowPiece, nil, function(kk, a)
				local lo, hi = wallLo(kk)
				return RANK[kk] * 100 + math.abs(a - (lo + hi) / 2)
			end)
		end
		if not ok then
			table.insert(skipped, item.kind)
		end
	end

	return { placed = placed, skipped = skipped, unreached = unreached }
end

export type Info = {
	building: string, -- "house" | "hospital" | "police_station"
	tones: string, -- Furniture.TONES key
	rooms: { { id: string, kind: string, x0: number, x1: number, z0: number, z1: number, exterior: boolean? } },
	doors: { { id: string, a: string, b: string, x: number, z: number, w: number } },
	thick: number, -- exterior wall
	partition: number, -- partition wall
	floorTop: number,
	ceiling: number, -- above the floor
	doorH: number,
	grid: { Facade.Win }, -- exterior windows (ground floor panes get an inside)
	band: { y: number, h: number }?, -- ribbon windows instead (hospital)
	pins: { [string]: { Pin } }, -- by room
	discs: { { x: number, z: number, r: number } },
	lanes: { { number } }?, -- the ways people walk through the building (model-local studs)
	laneHalf: number?,
	columns: number?, -- grid spacing of structural columns in rooms over 60 st both ways
}
export type Plan = {
	info: Info,
	rooms: { Room },
	layouts: { [string]: LayoutResult },
	skipped: { string },
	unreached: { string },
}

local FACE_WALL: { [string]: number } = { B = 1, R = 2, F = 3, L = 4 }

-- Lays out every interior room of a shell. Pure.
function Furnish.plan(ctx: Spec.LotCtx, info: Info): Plan
	local W, D, EPS = ctx.W, ctx.D, 1e-3
	local tones = Furniture.TONES[info.tones] or Furniture.TONES.bungalow
	local rooms: { Room } = {}
	local layouts: { [string]: LayoutResult } = {}
	local skipped: { string } = {}
	local unreached: { string } = {}
	for _, r in info.rooms do
		if not r.exterior then
			-- the inner faces of its four walls: an edge on the footprint is an exterior wall
			local function inset(edge: number, half: number): number
				return if math.abs(math.abs(edge) - half) <= EPS then info.thick else info.partition / 2
			end
			local room: Room = {
				id = r.id,
				kind = r.kind,
				x0 = r.x0 + inset(r.x0, W / 2),
				x1 = r.x1 - inset(r.x1, W / 2),
				z0 = r.z0 + inset(r.z0, D / 2),
				z1 = r.z1 - inset(r.z1, D / 2),
				doors = {},
				windows = {},
				pins = info.pins[r.id] or {},
				discs = {},
			}
			for _, d in info.doors do
				if d.a == r.id or d.b == r.id then
					local wall
					if math.abs(d.z - r.z1) <= EPS * 2 then
						wall = 1
					elseif math.abs(d.z - r.z0) <= EPS * 2 then
						wall = 3
					elseif math.abs(d.x - r.x1) <= EPS * 2 then
						wall = 2
					elseif math.abs(d.x - r.x0) <= EPS * 2 then
						wall = 4
					end
					if wall then
						table.insert(room.doors, { id = d.id, x = d.x, z = d.z, w = d.w, wall = wall })
					end
				end
			end
			for _, w in info.grid do
				local wall = FACE_WALL[w.face]
				local onEdge
				if w.face == "F" then
					onEdge = math.abs(r.z0 + D / 2) <= EPS
				elseif w.face == "B" then
					onEdge = math.abs(r.z1 - D / 2) <= EPS
				elseif w.face == "L" then
					onEdge = math.abs(r.x0 + W / 2) <= EPS
				else
					onEdge = math.abs(r.x1 - W / 2) <= EPS
				end
				local lo, hi = room.x0, room.x1
				if wall == 2 or wall == 4 then
					lo, hi = room.z0, room.z1
				end
				-- a pane with its casing and curtains must fit on this room's stretch of the wall, under
				-- the ceiling
				if
					onEdge
					and w.floor == 1
					and w.kind == "sash"
					and w.c - w.w / 2 - 1.6 >= lo
					and w.c + w.w / 2 + 1.6 <= hi
					and w.y + w.h / 2 + 0.9 <= info.floorTop + info.ceiling
				then
					table.insert(room.windows, { wall = wall, c = w.c, w = w.w, h = w.h, y = w.y })
				end
			end
			for _, c in info.discs do
				if c.x + c.r > room.x0 and c.x - c.r < room.x1 and c.z + c.r > room.z0 and c.z - c.r < room.z1 then
					table.insert(room.discs, c)
				end
			end
			local half = info.laneHalf or Furnish.BODY
			for _, l in info.lanes or {} do
				if
					math.max(l[1], l[3]) + half > room.x0
					and math.min(l[1], l[3]) - half < room.x1
					and math.max(l[2], l[4]) + half > room.z0
					and math.min(l[2], l[4]) - half < room.z1
				then
					room.lanes = room.lanes or {}
					table.insert(room.lanes :: { { number } }, l)
				end
			end
			room.laneHalf = half
			if info.columns then
				-- a grid of columns carries the ceiling of the big rooms (and gives them scale)
				local rw, rd = room.x1 - room.x0, room.z1 - room.z0
				local gx, gz = math.floor(rw / info.columns), math.floor(rd / info.columns)
				if rw > 60 and rd > 60 then
					room.pins = table.clone(room.pins)
					local n = 0
					for j = 1, gz - 1 do
						for i = 1, gx - 1 do
							n += 1
							table.insert(room.pins, {
								id = `Column_{r.id}_{n}`,
								kind = "column",
								x = room.x0 + rw * i / gx,
								z = room.z0 + rd * j / gz,
								fixed = true,
								optional = true,
								w = info.ceiling,
							})
						end
					end
				end
			end
			table.insert(rooms, room)
			Yield.breathe() -- (engine bakes: a big room is many flood fills)
			local res = Furnish.layout(room, Furnish.RECIPES[r.kind] or Furnish.RECIPES.generic, tones)
			layouts[r.id] = res
			for _, k in res.skipped do
				table.insert(skipped, r.id .. "." .. k)
			end
			for _, k in res.unreached do
				table.insert(unreached, r.id .. ": " .. k)
			end
		end
	end
	return { info = info, rooms = rooms, layouts = layouts, skipped = skipped, unreached = unreached }
end

-- Where the template's hide spots ended up: { id (the furniture part name), room, x, z }.
function Furnish.hideSpots(plan: Plan): { { id: string, room: string, x: number, z: number, hide: string } }
	local out = {}
	for _, room in plan.rooms do
		for _, p in plan.layouts[room.id].placed do
			if p.hide and p.hideX and p.hideZ then
				table.insert(out, { id = p.name, room = room.id, x = p.hideX, z = p.hideZ, hide = p.hide })
			end
		end
	end
	return out
end

local CEIL = { 240, 236, 226 }
local GLASS_IN = { 176, 204, 212 }
local WARM = { 255, 218, 152 } -- v5.4 lamp #ffda98
local COOL = { 240, 246, 219 } -- v5.4 hospital glow #f0f6db

-- Adds the dressed rooms to ctx.list (after Shell.build: the walls, doors and room volumes exist).
function Furnish.emit(ctx: Spec.LotCtx, plan: Plan)
	local info = plan.info
	local list, frame = ctx.list, ctx.frame
	local W, D = ctx.W, ctx.D
	local y0 = info.floorTop
	local ceilY = y0 + info.ceiling
	local house = info.building == "house"
	local tones = Furniture.TONES[info.tones] or Furniture.TONES.bungalow
	local knobs = Furnish.KNOBS
	local lights, pieces = 0, 0

	local function deco(
		name: string,
		mx: number,
		my: number,
		mz: number,
		sx: number,
		sy: number,
		sz: number,
		color: { number },
		material: string?,
		o: Spec.Opts?
	): Spec.PartSpec
		local opts: Spec.Opts = o or {}
		opts.color = color
		opts.material = material or "SmoothPlastic"
		if opts.canCollide == nil then
			opts.canCollide = false
		end
		if opts.canQuery == nil then
			opts.canQuery = false
		end
		opts.castShadow = false
		opts.role = opts.role or "Finish"
		return list:add(frame, name, mx, my, mz, sx, sy, sz, opts)
	end

	-- one ceiling over the whole floor, let a little way into the outer walls (a body, a camera and the
	-- light stay under it)
	deco(
		"Ceiling",
		0,
		ceilY + 0.15,
		0,
		W - 2 * info.thick + 0.1,
		0.3,
		D - 2 * info.thick + 0.1,
		CEIL,
		"SmoothPlastic",
		{
			canCollide = true,
			canQuery = true,
			role = "Ceiling",
		}
	)

	-- a strip on wall k of a room: `a0..a1` along it, `b0..b1` above the floor, standing `depth` into the room
	local function strip(
		room: Room,
		k: number,
		name: string,
		a0: number,
		a1: number,
		b0: number,
		b1: number,
		d0: number,
		d1: number,
		color: { number },
		material: string?,
		o: Spec.Opts?
	)
		local mid, len, t = (a0 + a1) / 2, a1 - a0, d1 - d0
		local dm = (d0 + d1) / 2
		local y = y0 + (b0 + b1) / 2
		if k == 1 then
			deco(name, mid, y, room.z1 - dm, len, b1 - b0, t, color, material, o)
		elseif k == 3 then
			deco(name, mid, y, room.z0 + dm, len, b1 - b0, t, color, material, o)
		elseif k == 2 then
			deco(name, room.x1 - dm, y, mid, t, b1 - b0, len, color, material, o)
		else
			deco(name, room.x0 + dm, y, mid, t, b1 - b0, len, color, material, o)
		end
	end

	for _, room in plan.rooms do
		local finish = Furnish.FINISH[room.kind] or Furnish.FINISH.generic
		local rw, rd = room.x1 - room.x0, room.z1 - room.z0
		local cx, cz = (room.x0 + room.x1) / 2, (room.z0 + room.z1) / 2
		-- floor finish: drawn 0.05 over the structural floor a body stands on
		deco("Finish_" .. room.id, cx, y0 + 0.025, cz, rw, 0.05, rd, finish.floor, finish.floorMaterial)

		-- wall lining and skirting, split round the doors
		for k = 1, 4 do
			local lo, hi = room.x0, room.x1
			if k == 2 or k == 4 then
				lo, hi = room.z0, room.z1
			end
			local gaps: { { number } } = {}
			for _, d in room.doors do
				if d.wall == k then
					local a = if k == 1 or k == 3 then d.x else d.z
					table.insert(gaps, { a - d.w / 2, a + d.w / 2 })
				end
			end
			table.sort(gaps, function(g1, g2)
				return g1[1] < g2[1]
			end)
			local cur, n = lo, 0
			local function span(a0: number, a1: number)
				if a1 - a0 > 0.05 then
					n += 1
					strip(room, k, `Liner_{room.id}_{k}_{n}`, a0, a1, 0, info.ceiling, 0, 0.06, finish.wall, "Plaster")
					if knobs.skirting then
						strip(room, k, `Skirt_{room.id}_{k}_{n}`, a0, a1, 0, 0.5, 0.03, 0.14, finish.skirt)
					end
				end
			end
			for _, g in gaps do
				span(cur, g[1])
				if info.ceiling - info.doorH > 0.05 then
					n += 1
					strip(
						room,
						k,
						`Liner_{room.id}_{k}_{n}`,
						g[1],
						g[2],
						info.doorH,
						info.ceiling,
						0,
						0.06,
						finish.wall,
						"Plaster"
					)
				end
				cur = g[2]
			end
			span(cur, hi)
		end

		-- the inside of the windows: casing, pane, and curtains on a rail (houses) or a blind (station)
		local wn = 0
		for _, w in room.windows do
			wn += 1
			local id = `{room.id}_{wn}`
			local b0, b1 = w.y - y0 - w.h / 2, w.y - y0 + w.h / 2
			strip(
				room,
				w.wall,
				"PaneFrame_" .. id,
				w.c - w.w / 2 - 0.3,
				w.c + w.w / 2 + 0.3,
				b0 - 0.3,
				b1 + 0.3,
				0.025,
				0.11,
				finish.skirt,
				nil,
				{ role = "Window" }
			)
			strip(
				room,
				w.wall,
				"Pane_" .. id,
				w.c - w.w / 2,
				w.c + w.w / 2,
				b0,
				b1,
				0.05,
				0.15,
				GLASS_IN,
				"Glass",
				{ role = "Window" }
			)
			if house and knobs.curtains and not w.covered then
				for s, side in { -1, 1 } do
					local c = w.c + side * (w.w / 2 + 0.5)
					strip(
						room,
						w.wall,
						`Curtain_{id}_{s}`,
						c - 0.55,
						c + 0.55,
						b0 - 0.5,
						b1 + 0.55,
						0.3,
						0.44,
						tones.curtain,
						"Fabric"
					)
				end
				-- the rail: a rod along the wall over the casing
				local len = w.w + 2.6
				local y = y0 + b1 + 0.6
				local opts: Spec.Opts = { shape = "Cylinder", role = "Finish" }
				if w.wall == 1 then
					deco("CurtainRail_" .. id, w.c, y, room.z1 - 0.37, len, 0.16, 0.16, tones.woodDark, "Wood", opts)
				elseif w.wall == 3 then
					deco("CurtainRail_" .. id, w.c, y, room.z0 + 0.37, len, 0.16, 0.16, tones.woodDark, "Wood", opts)
				else
					opts.yaw = math.pi / 2
					local x = if w.wall == 2 then room.x1 - 0.37 else room.x0 + 0.37
					deco("CurtainRail_" .. id, x, y, w.c, len, 0.16, 0.16, tones.woodDark, "Wood", opts)
				end
			elseif not house then
				strip(
					room,
					w.wall,
					"Blind_" .. id,
					w.c - w.w / 2 - 0.1,
					w.c + w.w / 2 + 0.1,
					b1 - 1.0,
					b1 + 0.2,
					0.15,
					0.3,
					finish.skirt
				)
			end
		end
		-- ribbon windows (hospital): a glazed band along the room's stretch of every outer wall
		if info.band then
			for k = 1, 4 do
				local outer = (k == 1 and math.abs(room.z1 + info.thick - D / 2) < 1e-3)
					or (k == 3 and math.abs(room.z0 - info.thick + D / 2) < 1e-3)
					or (k == 2 and math.abs(room.x1 + info.thick - W / 2) < 1e-3)
					or (k == 4 and math.abs(room.x0 - info.thick + W / 2) < 1e-3)
				if outer then
					local lo, hi = room.x0 + 3, room.x1 - 3
					if k == 2 or k == 4 then
						lo, hi = room.z0 + 3, room.z1 - 3
					end
					local spans = { { lo, hi } }
					for _, d in room.doors do
						if d.wall == k then
							local a = if k == 1 or k == 3 then d.x else d.z
							local nextSpans = {}
							for _, sp in spans do
								local g0, g1 = a - d.w / 2 - 2.5, a + d.w / 2 + 2.5
								if g1 <= sp[1] or g0 >= sp[2] then
									table.insert(nextSpans, sp)
								else
									table.insert(nextSpans, { sp[1], g0 })
									table.insert(nextSpans, { g1, sp[2] })
								end
							end
							spans = nextSpans
						end
					end
					for i, sp in spans do
						if sp[2] - sp[1] >= 4 then
							local b0, b1 = info.band.y - y0 - info.band.h / 2, info.band.y - y0 + info.band.h / 2
							strip(
								room,
								k,
								`Ribbon_{room.id}_{k}_{i}`,
								sp[1],
								sp[2],
								b0,
								b1,
								0.03,
								0.14,
								GLASS_IN,
								"Glass",
								{ role = "Window" }
							)
							strip(
								room,
								k,
								`RibbonSill_{room.id}_{k}_{i}`,
								sp[1] - 0.3,
								sp[2] + 0.3,
								b0 - 0.4,
								b0,
								0.03,
								0.4,
								finish.skirt
							)
						end
					end
				end
			end
		end

		-- lights: a shaded pendant in a house room, a grid of glow panels in the big blocks. Lit as
		-- baked; Client/Render/TownLights brightens them at night (attribute NightLight).
		if house then
			local name = "Light_" .. room.id
			deco(name, cx, ceilY - 1.5, cz, 0.6, 1.7, 1.7, { 244, 232, 204 }, "SmoothPlastic", {
				shape = "Cylinder",
				roll = math.pi / 2,
				role = "Light",
				attrs = { NightLight = true, Room = room.id },
			})
			deco(name .. "_Cord", cx, ceilY - 0.6, cz, 1.2, 0.1, 0.1, { 60, 60, 60 }, "Metal", {
				shape = "Cylinder",
				roll = math.pi / 2,
				role = "Light",
			})
			list:extra({
				kind = "PointLight",
				part = name,
				name = "Glow",
				range = math.clamp(math.floor(math.max(rw, rd) / 2 + 2.5), 10, 18),
				brightness = 0.9,
				color = WARM,
			})
			lights += 1
		else
			local gx = math.max(1, math.floor(rw / 45 + 0.5))
			local gz = math.max(1, math.floor(rd / 45 + 0.5))
			local n = 0
			for j = 1, gz do
				for i = 1, gx do
					n += 1
					local name = `Light_{room.id}_{n}`
					local lx, lz = room.x0 + rw * (i - 0.5) / gx, room.z0 + rd * (j - 0.5) / gz
					deco(name, lx, ceilY - 0.09, lz, 5.0, 0.18, 2.4, COOL, "Neon", {
						role = "Light",
						attrs = { NightLight = true, Room = room.id },
					})
					list:extra({
						kind = "PointLight",
						part = name,
						name = "Glow",
						range = math.clamp(math.floor(math.max(rw / gx, rd / gz) / 2 + 8), 18, 34),
						brightness = 0.9,
						color = COOL,
					})
					lights += 1
				end
			end
		end

		-- the furniture
		for _, p in plan.layouts[room.id].placed do
			if p.fixed then
				if p.dress then
					local parts = Furniture.dress(p.dress, tones, { w = p.w, seats = p.seats })
					Furniture.emitDress(list, frame, p.name, parts, p.x, p.z, p.q, y0)
				end
			elseif p.piece then
				local attrs: { [string]: string | number | boolean } = { Room = room.id }
				if p.pinned then
					attrs.HideType = p.hide or ""
				end
				Furniture.emit(list, frame, p.name, p.piece, p.x, p.z, p.q, y0, attrs)
				pieces += 1
			end
		end
	end

	-- a threshold in every doorway, across the wall's thickness
	for _, d in info.doors do
		local onX = math.abs(math.abs(d.z) - D / 2) <= info.thick + 1e-3
		local onZ = math.abs(math.abs(d.x) - W / 2) <= info.thick + 1e-3
		local alongX = true -- the wall runs along x
		local dx, dz = d.x, d.z
		local t = info.partition
		if onX then
			t = info.thick
			dz = if d.z < 0 then -D / 2 + t / 2 else D / 2 - t / 2
		elseif onZ then
			t = info.thick
			alongX = false
			dx = if d.x < 0 then -W / 2 + t / 2 else W / 2 - t / 2
		else
			for _, r in info.rooms do
				if r.id == d.a and (math.abs(d.x - r.x0) <= 1e-3 or math.abs(d.x - r.x1) <= 1e-3) then
					alongX = false
				end
			end
		end
		if alongX then
			deco("Threshold_" .. d.id, dx, y0 + 0.045, dz, d.w, 0.09, t + 0.3, tones.woodDark, "Wood")
		else
			deco("Threshold_" .. d.id, dx, y0 + 0.045, dz, t + 0.3, 0.09, d.w, tones.woodDark, "Wood")
		end
	end

	ctx.attributes.Furnished = pieces
	ctx.attributes.RoomLights = lights
	ctx.attributes.NightLights = ((ctx.attributes.NightLights :: number?) or 0) + lights
end

return Furnish
