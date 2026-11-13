--!strict
-- ReplicatedStorage.Shared.Attractions.AlleyRoof
-- The bowling alley's roof run (BRIEF_ADDENDUM D9, D10): "an elaborate roof based vent the squirrel can get to from
-- the roof of the bowling alley, via, climbing up on to the roof of a house, then jumping to tree branch, then
-- crawling into the top rafters of the bowling alley, the squirrel must practice sneaking through those rafters or
-- will be spotted, also, people ... can climb up metal stairs on the back of the bowling alley, and can keep watch
-- and guard the area around where that access to that upper vent is".
-- Every number of it in one place, in the alley's local frame (Shared/Attractions/AlleyLayout: X across, Y up from
-- the finished floor, D down the lane; with the placement of data/attractions.json world = (1300 + X, 16.5 + Y,
-- -420 - D)), so the bakes (tools/bake/alley/Yard, and later Roof, RoofVent, RoofStairs), the server (RafterWatch's
-- service) and the specs read the same figures. Kept out of AlleyLayout so the eighteen-lane builder's file is not
-- touched. Built for the eighteen-lane building (the east games wing at X 101..149.8, its back wall at D 30..30.8).
--
-- THE WAY UP (ordinary routes the motor already runs):
--   9101 the yard house's downspout (trunk, walked into) -> 9102 gutter to roof (bridge) -> 9103 the ridge (roof);
--   a leap west off the ridge's end lands on 9105, the tree's house bough (branch), which runs down to the fork;
--   9104 the tree's trunk (trunk) also climbs to that fork; 9106 the roof crossing (bridge) leaves the fork over
--   the wing's east parapet and ends 1.9 above the wing roof: Q drops the squirrel onto it.
-- THE VENT: 9107 (kind "tunnel", the enclosed-run contract of Shared/Routes/Enclosure on feat/run-through): in
--   through one bent louvre slat of the air-handling unit on the wing roof, up the plenum, through the duct in the
--   hall's raised east wall, down the elbow and out of the boot onto the truss chord 9120.
-- THE RAFTERS (planned with the raised hall roof, lane L1; no geometry yet): nine truss bottom chords 9120..9128
--   (kind fence, Y 12.32; the ninth truss, over the pinsetters, is in the backstage's ground and carries none),
--   nine light rails 9130..9138 over the lane pairs (Y 10.2, the lit and risky level) and two aisle braces 9139,
--   9140 across the chords.
-- Routes are written as data/attractions.json writes them (local points, explicit flags); records(place) turns them
-- into world records the way tools/compile/lib/Attractions does. They are NOT in data/attractions.json yet: the
-- house and the tree stand outside the alley's footprint, in ANNEX, which the compiler and the expansion check do
-- not know about yet; and 9107 needs the enclosed-run contract in the Registry.
-- Pure. Interface: constants below; routes() -> { LocalRoute } (copies); route(id) -> LocalRoute;
--   records(place, lotId?) -> { world route records }; lamps() -> { {X, Y, D} }; isRafter(id) -> boolean;
--   inHall(X, D) -> boolean; inAnnex(X, D) -> boolean; CHAIN, RAFTERS.

local AlleyLayout = require("./AlleyLayout")
local Curve = require("../Routes/Curve")

local AlleyRoof = {}

export type Rect = { x0: number, x1: number, d0: number, d1: number }
export type Flags = {
	autoGrabExcluded: boolean,
	isPole: boolean,
	isGiant: boolean,
	fixedSurfaceZ: boolean,
	treeTravel: boolean,
}
-- Shared/Routes/Enclosure's Record (feat/run-through ff0c127), written out here so this file loads without it.
export type LinkRecord = { route: number, t: number, dir: number }
export type MouthRecord = {
	t: number,
	opens: string,
	out: { number }?,
	reach: number?,
	rise: number?,
	links: { LinkRecord }?,
	name: string?,
}
export type EnclosureRecord = {
	id: string,
	climb: boolean?,
	mouths: { MouthRecord }?,
	width: number?,
	height: number?,
	hidden: boolean?,
}
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
AlleyRoof.ANNEX = { x0 = 152, x1 = 212, d0 = 4, d1 = 40, ["for"] = "the yard house and tree, addendum D9" }

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

-- THE RAISED HALL ROOF (lane L1; planned, not built) ----------------------------------------------------------------
-- Why the deck is at 21.0: a leap from a chord peaks 6.56 up (the motor has no ceilings), plus the 1.7 body = 20.6.
AlleyRoof.HALL_ROOF = {
	x0 = -26,
	x1 = 101,
	outerX0 = -26.8,
	outerX1 = 101.8,
	d0 = -15,
	d1 = 66.5,
	deckY0 = 21.0,
	deckY1 = 22.6,
	parapetY = 24.0,
	clerestoryY0 = 13.6,
}
AlleyRoof.TRUSS_D = { -10.5, -1.5, 7.5, 16.5, 25.5, 34.5, 43.5, 52.5, 61.5 }
AlleyRoof.CHORD = { y0 = 12.0, y1 = 12.32, width = 0.5, topY0 = 20.2, topY1 = 20.5, webPitch = 6.2, x0 = -25.4 }
AlleyRoof.LIGHT_RAIL = { y = 10.2, d0 = 0, d1 = 53.8, lampY = 9.9 }
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
-- The squirrel's way in: one bent louvre slat, the curb cut so the sill is the membrane.
AlleyRoof.MOUTH = { x = 117.0, y = 13.62, d = 16.5, slat = { d0 = 15.6, d1 = 17.4, y0 = 13.6, y1 = 15.4 } }
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
		{ x0 = 116.4, x1 = 121, d0 = 8, d1 = 22.5, name = "louvre strip" },
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
AlleyRoof.TREE = { x = 166, y = -7.5, d = 32, trunkR = 1.4, crownR = 18 }

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
		flags = flags(true, false, false),
		points = { { 206.5, 8.35, 7.6 }, { 207.5, 17.1, 20.0 } },
		note = "From the downspout's head up the north roof slope to the ridge's east end (exactly its first point: "
			.. "a joint short of it would be met part-way along the ridge and turned back east).",
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
		id = 9104,
		name = "alley yard tree trunk",
		kind = "trunk",
		surfaceRadius = 1.4,
		flags = flags(false, false, true),
		points = { { 166, -7.2, 32 }, { 166.3, 5.0, 32 }, { 166.5, 17.5, 31.8 } },
		note = "The tree beside the games wing, from its foot to the fork (world y 34.0).",
	},
	{
		id = 9105,
		name = "alley yard tree house bough",
		kind = "branch",
		surfaceRadius = 0.55,
		flags = flags(false, false, true),
		points = { { 166.5, 17.5, 31.8 }, { 168.8, 20.6, 25.5 }, { 170.5, 22.6, 20.0 }, { 172.5, 24.0, 12.0 } },
		note = "From the fork up toward the house: it crosses the ridge's line (D 20) 14 west of the ridge's end "
			.. "and 5.5 above it, where a leap west off the ridge lands on it held, sprinting or with no key.",
	},
	{
		id = 9106,
		name = "alley yard tree roof crossing",
		kind = "bridge",
		surfaceRadius = 0.6,
		flags = flags(false, false, true),
		points = {
			{ 166.5, 17.5, 31.8 },
			{ 160.0, 17.3, 31.0 },
			{ 154.6, 16.9, 27.2 },
			{ 151.2, 16.3, 23.2 },
			{ 149.4, 16.0, 21.5 },
			{ 146.0, 15.5, 20.0 },
		},
		note = "From the fork west, then over the games wing's east parapet (1.0 above its coping); it ends 1.9 above "
			.. "the wing roof: Q drops the squirrel onto it. It leaves the fork heading west-south-west, along the "
			.. "bough's own way down, so running down the bough carries on onto it.",
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
			note = "The rail the lane lights hang from: 2.1 under the chords, right over the lamps.",
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

-- The order a squirrel takes them on the way in (the trunk 9104 is the other way up to the fork).
AlleyRoof.CHAIN = { 9101, 9102, 9103, 9105, 9106, 9107, 9120 }
AlleyRoof.VENT = 9107
AlleyRoof.FIRST_RAFTER = 9120
AlleyRoof.LAST_RAFTER = 9140

local byId: { [number]: LocalRoute } = {}
for _, r in ROUTES do
	byId[r.id] = r
end

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

return AlleyRoof
