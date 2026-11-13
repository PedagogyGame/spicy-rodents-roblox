--!strict
-- ReplicatedStorage.Shared.Attractions.AlleyRoof
-- The bowling alley's roof run (BRIEF_ADDENDUM D9, D10): "an elaborate roof based vent the squirrel can get to from
-- the roof of the bowling alley, via, climbing up on to the roof of a house, then jumping to tree branch, then
-- crawling into the top rafters of the bowling alley, the squirrel must practice sneaking through those rafters or
-- will be spotted, also, people ... can climb up metal stairs on the back of the bowling alley, and can keep watch
-- and guard the area around where that access to that upper vent is".
-- Every number of it in one place, in the alley's local frame (Shared/Attractions/AlleyLayout: X across, Y up from
-- the finished floor, D down the lane; with the placement of data/attractions.json world = (1300 + X, 16.5 + Y,
-- -420 - D)), so the bakes (tools/bake/alley/Yard, Roof, RoofVent, RoofStairs), the server (RafterWatch's
-- service) and the specs read the same figures. Kept out of AlleyLayout so the eighteen-lane builder's file is not
-- touched. Built for the eighteen-lane building (the east games wing at X 101..149.8, its back wall at D 30..30.8).
--
-- THE WAY UP (ordinary routes the motor already runs):
--   9101 the yard house's downspout (trunk, walked into) -> 9102 gutter to roof (bridge) -> 9103 the ridge (roof);
--   a leap west off the ridge's end lands on 9105, the tree's house bough (branch), which runs down past the trunk's
--   top and on as the roof crossing, drooping over the wing's east parapet to end 0.7 above the wing roof: Q drops
--   the squirrel onto it. The house is the only way up (owner question Q11, default): the tree's trunk carries no
--   route (a squirrel baffle on it says why), so nothing reaches 9105 but the leap.
-- WHERE THE LEAP WORKS (tests/unit/attractions_roofvent.spec.luau sweeps it): from the ridge's west end, where
--   holding W stops the squirrel, Space catches the bough whatever is held. Earlier along the ridge only a sprint
--   carries far enough (from about 15 st short of the end); a walking leap from more than about 5 st short passes
--   under the bough and falls into the yard, unless E is pressed in the air near it (E grabs a route within reach).
--   The hint for lane L6: "Run to the end of the ridge, then Space".
-- Retired ids: 9104 (the trunk's climb) and 9106 (the crossing, now part of 9105).
-- THE VENT: 9107 (kind "tunnel", the enclosed-run contract of Shared/Routes/Enclosure): in through one bent louvre
--   slat of the air-handling unit on the wing roof (a ground mouth), up the plenum, through the duct in the hall's
--   raised east wall, down the elbow and out of the boot (a link mouth) onto the truss chord 9120. The motor runs it
--   (tests/unit/attractions_roofvent.spec.luau drives the whole way in and back out on the baked alley); the unit and
--   the duct round it are tools/bake/alley/RoofVent.
-- THE RAFTERS (the raised hall roof, tools/bake/alley/Roof): nine truss bottom plates 9120..9128 (kind fence, Y 12.32;
--   the ninth truss, over the pinsetters, is in the backstage's ground and carries none), nine light rails 9130..9138
--   over the lane pairs (Y 10.1, the lit and risky level) and two aisle braces 9139, 9140 across the plates.
-- Routes are written as data/attractions.json writes them (local points, explicit flags; tools/compile/
-- alley_roof_routes.luau writes them there, with ANNEX as the attraction's annex); records(place) turns them into
-- world records the way tools/compile/lib/Attractions does.
-- Pure. Interface: constants below; routes() -> { LocalRoute } (copies); route(id) -> LocalRoute;
--   records(place, lotId?) -> { world route records }; lamps() -> { {X, Y, D} }; isRafter(id) -> boolean;
--   inHall(X, D) -> boolean; inAnnex(X, D) -> boolean; inPlatform(X, D) -> string?; guardEyes() -> { {X, Y, D} };
--   CHAIN, RETIRED, BOUGH_FORK_T.

local AlleyLayout = require("./AlleyLayout")
local Curve = require("../Routes/Curve")
local Enclosure = require("../Routes/Enclosure")

local AlleyRoof = {}

export type Rect = { x0: number, x1: number, d0: number, d1: number }
export type Flags = {
	autoGrabExcluded: boolean,
	isPole: boolean,
	isGiant: boolean,
	fixedSurfaceZ: boolean,
	treeTravel: boolean,
}
export type MouthRecord = Enclosure.MouthRecord
export type EnclosureRecord = Enclosure.Record
-- As data/attractions.json writes a route (local [X, Y, D]); `enclosure` as Shared/Routes/Enclosure's Record with
-- its mouths' `out` in the local frame.
export type LocalRoute = {
	id: number,
	name: string,
	kind: string,
	surfaceRadius: number,
	visualOffset: number?,
	flags: Flags,
	points: { { number } },
	enclosure: EnclosureRecord?,
	note: string,
}

local STUDS_PER_UNIT = 2.5 -- as tools/compile (the sample count is v5.4's, on the length in HTML units)

-- The ground kept for the yard house and its tree: outside the alley's footprint (X -42..152), outside the
-- backstage reserve (D >= 54.2) and lounge one (world x 1462..1512, z -334..-390 = X 162..212, D -86..-30).
-- (D to 48, not the survey's 40: the tree's crown reaches 16 south of its trunk.)
AlleyRoof.ANNEX = { x0 = 152, x1 = 212, d0 = 4, d1 = 48, ["for"] = "the yard house and tree, addendum D9" }

-- THE BUILDING AS IT STANDS (feat/alley-18, tools/bake/alley/Shell) -----------------------------------------------
-- The games wing's roof: membrane on top of the 1.6 slab, parapets 1.2 tall with a 0.2 coping.
AlleyRoof.WING_ROOF = {
	x0 = 101.8, -- inner face of the hall's east wall
	x1 = 149, -- inner face of the wing's east wall
	d0 = -68,
	d1 = 30, -- inner face of the wing's back wall (WingBack D 30..30.8)
	outerX1 = 149.8,
	outerD1 = 30.8,
	y = 13.6, -- the membrane (world 30.1)
	copingY = 15.0,
}

-- THE RAISED HALL ROOF (lane L1: tools/bake/alley/Roof, the model AlleyLayout.HALL_ROOF.model) -------------------
-- The lane hall's roof raised to a deck at Y 21.0 (why 21.0: a leap from a chord peaks 6.56 up, and the motor has no
-- ceilings, plus the 1.7 body = 20.6), on brick clerestory walls standing on the old roof line (13.6) north, east and
-- west and on the machine wall south; the old flat roof stays as a strip from AlleyLayout.HALL_ROOF.d0 (the
-- concourse's back edge) to the north wall, with its hung ceiling. wallT: the walls' thickness; northD0..d0 the north
-- wall, southD0..d1 the south wall; the deck over x0..x1, d0..southD0.
AlleyRoof.HALL_ROOF = {
	x0 = -26,
	x1 = 101,
	outerX0 = -26.8,
	outerX1 = 101.8,
	stripD0 = AlleyLayout.HALL_ROOF.d0,
	northD0 = -15.8,
	d0 = -15,
	southD0 = 65.7,
	d1 = 66.5,
	wallT = 0.8,
	deckY0 = 21.0,
	deckY1 = 22.6,
	parapetY = 24.0,
	clerestoryY0 = 13.6,
}
-- Nine steel box trusses across the hall, each a 2.4-wide bottom plate (its top, y1, is the rafter routes' line), two
-- Warren lattice planes `web` either side of its centre line (rods `webT` thick, a bottom node at every lane pair's
-- edge and a top node over every pair's middle: webPitch 6.2) and two top chords under the deck: the body (1.6 wide)
-- walks the plate between the planes, and the vent's duct (2.0 wide) drops between them onto the D 16.5 truss.
AlleyRoof.TRUSS_D = { -10.5, -1.5, 7.5, 16.5, 25.5, 34.5, 43.5, 52.5, 61.5 }
AlleyRoof.CHORD = {
	y0 = 12.0,
	y1 = 12.32,
	width = 2.4,
	web = 1.08,
	webT = 0.14,
	topY0 = 20.2,
	topY1 = 20.5,
	topW = 0.3,
	webPitch = 6.2,
	x0 = -25.4,
}
-- The light rails over the lane pairs (the lit, risky level): 1.9 under the plates, so a body on a rail clears them
-- (0.15 lift + 1.7), hung from the trusses at hangD by a yoke and two rods outside the body; the lamps under them.
-- The routes run d0..d1; each rail runs on into the masking header (AlleyLayout.MACHINE_D0 - 0.4).
AlleyRoof.LIGHT_RAIL = { y = 10.1, d0 = 0, d1 = 53.4, lampY = 9.8, width = 0.4, hangD = { 16.5, 34.5, 52.5 } }
AlleyRoof.BRACE_X = { 96.9, -22.3 }
AlleyRoof.BRACE_D = { d0 = -14.5, d1 = 53.0 }
-- Where people stand to see the rafters: the lane hall from the front rooms' wall to the masking (Stealth/RafterWatch
-- also asks for an eye near floor height).
AlleyRoof.HALL_WATCH = { x0 = -26, x1 = 101, d0 = -48, d1 = 66.5 }

-- THE VENT (lane L2; planned) ---------------------------------------------------------------------------------------
AlleyRoof.AHU = {
	curb = { x0 = 103.6, x1 = 116.4, y0 = 13.6, y1 = 14.2, d0 = 10.6, d1 = 22.4 },
	housing = { x0 = 104, x1 = 116, y0 = 14.2, y1 = 19.0, d0 = 11, d1 = 22 },
	louvre = { x = 116, d0 = 13, d1 = 20 },
	stack = { x = 110, d = 16.5, r = 2.2, y0 = 19.0, y1 = 20.6 },
}
-- The squirrel's way in: one bent louvre slat, the curb cut so the sill is the membrane. In front of the louvre a
-- strip of bare membrane (the apron, X 116.4..118.0) carries no grating: the platform's louvre strip starts behind
-- it, so the mouth and the first stretch of 9107 lie on the membrane and the guard sees the bent slat over the apron.
AlleyRoof.MOUTH = { x = 117.0, y = 13.62, d = 16.5, slat = { d0 = 15.6, d1 = 17.4, y0 = 13.6, y1 = 15.4 } }
AlleyRoof.APRON = { x0 = 116.4, x1 = 118.0, d0 = 8, d1 = 22.5 }
-- (the duct's sleeve runs through the hall's east wall, X 101..101.8)
AlleyRoof.DUCT = { x0 = 101.0, x1 = 104, d0 = 15.5, d1 = 17.5, y0 = 15.0, y1 = 17.0 }
AlleyRoof.ELBOW = { x0 = 99.6, x1 = 101, d0 = 15.5, d1 = 17.5, y0 = 12.32, y1 = 17.0 }
AlleyRoof.BOOT = { x0 = 98.6, x1 = 101, d0 = 15.5, d1 = 17.5, y0 = 12.32, y1 = 14.3 }

-- THE STAIRS AND THE GUARD PLATFORM (lane L2; planned) -------------------------------------------------------------
-- In the open yard behind the games wing, against its back wall: 27 risers of 0.734 in three flights of nine, eight
-- treads of 1.5 each, landings between, the top landing level with the platform.
AlleyRoof.STAIR = {
	d0 = 31.2,
	d1 = 35.2,
	riser = 0.734,
	tread = 1.5,
	footX = 149,
	footY = -6.1,
	flights = {
		{ x0 = 149, x1 = 137, y0 = -6.1, y1 = 0.51 },
		{ x0 = 133, x1 = 121, y0 = 0.51, y1 = 7.12 },
		{ x0 = 117, x1 = 105, y0 = 7.12, y1 = 13.72 },
	},
	landings = {
		{ x0 = 133, x1 = 137, y = 0.51 },
		{ x0 = 117, x1 = 121, y = 7.12 },
		{ x0 = 101.8, x1 = 105, y = 13.72 },
	},
	railTop = 3.6,
	railMid = 1.8,
	parapetCut = { x0 = 101.8, x1 = 105 },
}
AlleyRoof.PLATFORM = {
	y = 13.72, -- top of the 0.1 grating
	rects = {
		{ x0 = 101.8, x1 = 121, d0 = 22.5, d1 = 30, name = "walkway" },
		{ x0 = 118.0, x1 = 121, d0 = 8, d1 = 22.5, name = "louvre strip" },
		{ x0 = 101.8, x1 = 121, d0 = 8, d1 = 10.6, name = "north strip" },
	},
}
-- People stay on the platform: a visible rail (squirrels pass under its 1.8 bottom rail) and an invisible wall up to
-- Y 29.7 (a person jumps about 7.2 onto the 5.3-high unit).
AlleyRoof.PEOPLE_FENCE = {
	lines = {
		{ x0 = 121, x1 = 121, d0 = 8, d1 = 30 },
		{ x0 = 101.8, x1 = 121, d0 = 8, d1 = 8 },
	},
	railTop = 3.6,
	bottomRail = 1.8,
	postPitch = 3,
	wallY0 = 13.72,
	wallY1 = 29.7,
}
AlleyRoof.GUARD = { x = 118.5, d = 16.5, eyeY = 18.9 }
-- Where else on the platform a guard looks out from toward the yard: the louvre strip's two outer corners and the
-- walkway's south-east corner (eye 5.2 over the grating). The yard's leaves keep clear of the lines from these to the
-- ridge, the leap and the bough (tools/bake/alley/Yard.keepOut).
AlleyRoof.LOOKOUTS = { { x = 120.5, d = 8.5 }, { x = 120.5, d = 22 }, { x = 120.5, d = 29.5 } }

-- THE YARD (lane L3: tools/bake/alley/Yard) -------------------------------------------------------------------------
-- A plain two-storey house (not one of the enterable homes), gables facing west (toward the tree) and east, the
-- ridge along X; the ground falls east (world 7.35 at its north-west corner, 5.2 at the east).
AlleyRoof.HOUSE = {
	x0 = 184,
	x1 = 208,
	d0 = 8,
	d1 = 32,
	floorY = -8.5, -- world 8.0
	storey = 8.5,
	eaveY = 8.5, -- world 25.0
	ridgeD = 20,
	ridgeY = 16.9, -- top of the roof boards at the ridge (world 33.4)
	overhang = 0.8,
}
-- The tree: trunk base 16 east and 1 south of the wing's south-east corner, outside the footprint and the reserve.
-- spine: the trunk's axis from its foot to the fork (the top of the trunk, where 9105 bends from bough to crossing);
-- trunkR the bark at the foot, forkR at the fork. No route climbs it (Q11): a sheet-metal squirrel baffle round it
-- (baffle: its lower and upper rim heights and outer radius) is the cue. crown: the envelope of the leaf clumps'
-- centres (an ellipsoid, radii rx, ry, rd), the clumps at most maxClump across and at most `count` of them; a later
-- builder sizing clearances or the meshed tree reads this, and tools/bake/alley/Yard scatters the clumps in it.
AlleyRoof.TREE = {
	x = 166,
	y = -7.5,
	d = 32,
	trunkR = 2.0,
	forkR = 1.15,
	spine = { { 166, -7.4, 32 }, { 166.3, 5.0, 32 }, { 166.5, 17.5, 31.8 } },
	baffle = { y0 = -3.2, y1 = -1.6, r = 3.6 },
	crown = { x = 164, y = 26, d = 34, rx = 20, ry = 12, rd = 14, maxClump = 11, count = 38 },
}

-- THE ROUTES --------------------------------------------------------------------------------------------------------
local function flags(grab: boolean, surfaceZ: boolean, tree: boolean): Flags
	return { autoGrabExcluded = grab, isPole = false, isGiant = false, fixedSurfaceZ = surfaceZ, treeTravel = tree }
end

local ROUTES: { LocalRoute } = {
	{
		id = 9101,
		name = "alley yard house downspout",
		kind = "trunk",
		surfaceRadius = 0.35,
		flags = flags(false, true, false),
		points = { { 206.5, -10.9, 7.6 }, { 206.5, -1.3, 7.6 }, { 206.5, 8.35, 7.6 } },
		note = "On the house's north face by its north-east corner: run into it and the squirrel climbs (walk-in "
			.. "allowed, unlike the town's downspouts). Its top meets the gutter.",
	},
	{
		id = 9102,
		name = "alley yard house gutter to roof",
		kind = "bridge",
		surfaceRadius = 0.6,
		visualOffset = 0,
		flags = flags(true, false, false),
		points = { { 206.5, 8.35, 7.6 }, { 207.5, 17.1, 20.0 } },
		note = "From the downspout's head up the north roof slope to the ridge's east end (exactly its first point: "
			.. "a joint short of it would be met part-way along the ridge and turned back east). Its line rides "
			.. "0.15 over the slates, so the body is drawn on it (visualOffset 0, not a bough's lift).",
	},
	{
		id = 9103,
		name = "alley yard house ridge",
		kind = "roof",
		surfaceRadius = 0.5,
		flags = flags(false, false, false),
		points = { { 207.5, 17.1, 20.0 }, { 184.5, 17.1, 20.0 } },
		note = "The ridge, east to west. Its west end faces the tree: Space there leaps onto the house bough.",
	},
	{
		id = 9105,
		name = "alley yard tree house bough and roof crossing",
		kind = "branch",
		surfaceRadius = 0.55,
		flags = flags(false, false, true),
		points = {
			{ 171.25, 23.1, 17.0 },
			{ 170.5, 22.6, 20.0 },
			{ 168.8, 20.6, 25.5 },
			{ 166.5, 17.5, 31.8 },
			{ 160.0, 17.12, 31.0 },
			{ 154.6, 16.8, 27.2 },
			{ 151.2, 16.35, 23.2 },
			{ 149.4, 16.0, 21.5 },
			{ 147.6, 15.25, 20.6 },
			{ 145.5, 14.3, 20.0 },
		},
		note = "One limb from 3 st past where it crosses the ridge's line (D 20, 14 west of the ridge's end and 5.5 "
			.. "above it, where a leap west off the ridge's end lands on it held, sprinting or with no key), down to "
			.. "the trunk's top and on west as the roof crossing, drooping over the games wing's east parapet (1.0 "
			.. "above its coping) to end 0.7 above the wing roof: Q drops the squirrel onto it. One route, so once "
			.. "W carries the squirrel down the bough it carries on to the roof whatever the camera does.",
	},
	{
		id = 9107,
		name = "alley roof vent duct",
		kind = "tunnel",
		surfaceRadius = 0.6,
		visualOffset = 0,
		flags = flags(true, false, false),
		points = {
			{ 117.0, 13.62, 16.5 },
			{ 115.2, 13.62, 16.5 },
			{ 112.0, 14.30, 16.5 },
			{ 108.0, 14.30, 16.5 },
			{ 105.0, 14.30, 16.5 },
			{ 104.6, 15.12, 16.5 },
			{ 101.4, 15.12, 16.5 },
			{ 100.35, 15.0, 16.5 },
			{ 100.05, 13.4, 16.5 },
			{ 99.6, 12.36, 16.5 },
			{ 98.6, 12.32, 16.5 },
		},
		enclosure = {
			id = "alley.roofvent",
			hidden = true,
			width = 1.8,
			height = 1.8,
			mouths = {
				{ t = 0, opens = "ground", out = { 1, 0, 0 }, name = "louvre" } :: MouthRecord,
				{ t = 1, opens = "link", links = { { route = 9120, t = 0, dir = 1 } }, name = "boot" } :: MouthRecord,
			},
		},
		note = "In through the bent louvre slat, up the plenum, through the duct in the hall's raised east wall, down "
			.. "the elbow and out of the boot onto the truss chord over lane 18 (9120). Both ways.",
	},
}

-- The rafters: truss bottom chords, then light rails, then the aisle braces.
do
	-- (no route on the ninth truss, D 61.5: it stands over the pinsetters, in the ground kept for the backstage)
	local chordIds = { 9121, 9122, 9123, 9120, 9124, 9125, 9126, 9127 }
	for i, id in chordIds do
		local d = AlleyRoof.TRUSS_D[i]
		local fromX = if id == 9120 then AlleyRoof.BOOT.x0 else 100.4
		table.insert(ROUTES, {
			id = id,
			name = `alley rafter truss chord (D {d})`,
			kind = "fence",
			surfaceRadius = 0.25,
			flags = flags(true, false, false),
			points = { { fromX, AlleyRoof.CHORD.y1, d }, { AlleyRoof.CHORD.x0, AlleyRoof.CHORD.y1, d } },
			note = if id == 9120
				then "The chord the vent's boot opens onto, over the lanes from the east aisle to the west."
				else "A truss's bottom chord, over the lanes from the east aisle to the west.",
		})
	end
	for p = 1, AlleyLayout.PAIRS do
		local x = AlleyLayout.pairX(p)
		table.insert(ROUTES, {
			id = 9129 + p,
			name = `alley rafter light rail (lanes {2 * p - 1}-{2 * p})`,
			kind = "fence",
			surfaceRadius = 0.25,
			flags = flags(true, false, false),
			points = {
				{ x, AlleyRoof.LIGHT_RAIL.y, AlleyRoof.LIGHT_RAIL.d0 },
				{ x, AlleyRoof.LIGHT_RAIL.y, AlleyRoof.LIGHT_RAIL.d1 },
			},
			note = "The rail the lane lights hang from: 1.9 under the truss plates, right over the lamps.",
		})
	end
	for i, x in AlleyRoof.BRACE_X do
		table.insert(ROUTES, {
			id = 9138 + i,
			name = `alley rafter aisle brace ({if i == 1 then "east" else "west"})`,
			kind = "fence",
			surfaceRadius = 0.25,
			flags = flags(true, false, false),
			points = {
				{ x, AlleyRoof.CHORD.y1, AlleyRoof.BRACE_D.d0 },
				{ x, AlleyRoof.CHORD.y1, AlleyRoof.BRACE_D.d1 },
			},
			note = "Across every chord along the aisle: the way from one truss to the next.",
		})
	end
end

-- The order a squirrel takes them on the way in (between 9103 and 9105 the leap; between 9105 and 9107 the roof).
AlleyRoof.CHAIN = { 9101, 9102, 9103, 9105, 9107, 9120 }
AlleyRoof.RETIRED = { 9104, 9106 }
AlleyRoof.BOUGH = 9105
AlleyRoof.VENT = 9107
AlleyRoof.FIRST_RAFTER = 9120
AlleyRoof.LAST_RAFTER = 9140

local byId: { [number]: LocalRoute } = {}
for _, r in ROUTES do
	byId[r.id] = r
end

-- Where on 9105 (arc-length t) the trunk's top is: the bough above it, the crossing below.
AlleyRoof.BOUGH_FORK_T = (function(): number
	local pts = byId[9105].points
	local fork = AlleyRoof.TREE.spine[#AlleyRoof.TREE.spine]
	local c = Curve.fromArrays(pts)
	local best, bestT = math.huge, 0
	for i = 0, 2000 do
		local p = c:getPointAt(i / 2000)
		local d = (p.x - fork[1]) ^ 2 + (p.y - fork[2]) ^ 2 + (p.z - fork[3]) ^ 2
		if d < best then
			best, bestT = d, i / 2000
		end
	end
	return bestT
end)()

local function deepCopy(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = deepCopy(x)
	end
	return out
end

function AlleyRoof.routes(): { LocalRoute }
	return deepCopy(ROUTES)
end

function AlleyRoof.route(id: number): LocalRoute
	local r = byId[id]
	if not r then
		error(`AlleyRoof.route: no route {id}`)
	end
	return deepCopy(r)
end

-- A rafter route: the only routes RafterWatch counts (the vent itself is hidden, the yard is outside).
function AlleyRoof.isRafter(id: number?): boolean
	return id ~= nil and id >= AlleyRoof.FIRST_RAFTER and id <= AlleyRoof.LAST_RAFTER and byId[id] ~= nil
end

local function r4(n: number): number
	return math.floor(n * 1e4 + 0.5) / 1e4
end

-- records(place, lotId?): world route records as tools/compile/lib/Attractions writes them (points, arc length,
-- the v5.4 sample count, origin "attraction", explicit flags), plus 9107's enclosure with its mouths' `out` turned
-- into world directions (the run-through contract's world form).
function AlleyRoof.records(place: AlleyLayout.Place, lotId: string?): { any }
	local out = {}
	for _, r in ROUTES do
		local pts = {}
		local vecs = {}
		for _, p in r.points do
			local x, y, z = AlleyLayout.toWorld(place, p[1], p[2], p[3])
			table.insert(pts, { r4(x), r4(y), r4(z) })
			table.insert(vecs, Curve.vec3(x, y, z))
		end
		local length = Curve.new(vecs):getLength()
		local rec: { [string]: any } = {
			id = r.id,
			name = r.name,
			kind = r.kind,
			speedMult = 1,
			surfaceRadius = r.surfaceRadius,
			length = r4(length),
			sampleCount = Curve.sampleSteps(length / STUDS_PER_UNIT) + 1,
			points = pts,
			origin = "attraction",
			generator = "attraction:" .. (lotId or "alley_roof"),
			lotId = lotId,
			flags = table.clone(r.flags),
		}
		if r.visualOffset ~= nil then
			rec.visualOffset = r.visualOffset
		end
		if r.enclosure then
			local e = deepCopy(r.enclosure)
			for _, m in e.mouths or {} do
				if m.out then
					local dx, dz = AlleyLayout.dirToWorld(place, m.out[1], m.out[3])
					m.out = { r4(dx), r4(m.out[2]), r4(dz) }
				end
			end
			rec.enclosure = e
		end
		table.insert(out, rec)
	end
	return out
end

-- The lamps under the raised roof (Lanes' ceiling lights re-hung by lane L1): the troffers over the approaches hang
-- on rods from the first two trusses, the cans and the lane washes hang under the light rails.
function AlleyRoof.lamps(): { { number } }
	local out = {}
	for p = 1, AlleyLayout.PAIRS do
		local x = AlleyLayout.pairX(p)
		for _, d in { -13, -6 } do
			table.insert(out, { x, 11.0, d })
		end
		for _, d in { 8, 12, 20, 30, 32, 44 } do
			table.insert(out, { x, AlleyRoof.LIGHT_RAIL.lampY, d })
		end
	end
	return out
end

local function inRect(r: Rect, X: number, D: number): boolean
	return X >= r.x0 and X <= r.x1 and D >= r.d0 and D <= r.d1
end

function AlleyRoof.inHall(X: number, D: number): boolean
	return inRect(AlleyRoof.HALL_WATCH, X, D)
end

function AlleyRoof.inAnnex(X: number, D: number): boolean
	return inRect(AlleyRoof.ANNEX, X, D)
end

-- The platform rectangle a point lies on (its name), or nil.
function AlleyRoof.inPlatform(X: number, D: number): string?
	for _, r in AlleyRoof.PLATFORM.rects do
		if inRect(r :: any, X, D) then
			return r.name
		end
	end
	return nil
end

-- The guard's eye at the louvre, then at each lookout (local {X, Y, D}).
function AlleyRoof.guardEyes(): { { number } }
	local g = AlleyRoof.GUARD
	local out = { { g.x, g.eyeY, g.d } }
	for _, l in AlleyRoof.LOOKOUTS do
		table.insert(out, { l.x, g.eyeY, l.d })
	end
	return out
end

return AlleyRoof
