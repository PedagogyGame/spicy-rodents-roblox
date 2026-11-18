--!strict
-- ReplicatedStorage.Shared.Traffic.VehiclePuppet
-- Part-built vehicles at the TRUE logical boxes (BUILD_PLAN §4.4 W1 #9 and #10, D9, §5.2).
-- Interface: spec(kind, opts?) -> PartBuilder.ModelSpec; KINDS; baseOffset(kind) (root centre above the base); length(kind), width(kind), track(kind)
--
-- The invisible RootPart is exactly the logical box from Traffic/Boxes (the box the fatal test sweeps), and
-- the visible vehicle fills the same envelope and stays inside it, so a player never dies to a car that
-- looks smaller.
-- Every kind is SHAPED (owner 2026-11-11: "the vehicles are extremely rough"): a vehicle from about forty
-- plain parts, no meshes (the BUILDERS below; the way worldgen/Builders/Fixtures shapes a building).
-- Names follow Actors/RigSpec.car (RootPart, Body, WheelFL/FR/BL/BR, LightBar (+ LightBarB, the second
-- beacon colour), Headlights, TailLights;
-- sockets DriverSeat, DashSocket, EyeSocket). Authored rigs face -Z (RigSpec header; Config/Units adds
-- the HTML pi once). Drive on the right (owner decision 9) makes the cars left-hand drive: the driver
-- sits on local -X. Colours: traffic.md §2 (kind defaults) or the fleet entry's colour.

local Boxes = require("./Boxes")
local PartBuilder = require("../Avatar/PartBuilder")

export type Opts = { color: string?, name: string?, beacons: boolean? }

local VehiclePuppet = {}

local hex = PartBuilder.hex

-- cabin: the share of the box height above the driver's seat (where the sockets go)
-- stylua: ignore
local DEFAULTS: { [string]: { color: string, cabin: number, beacons: boolean } } = {
	sedan = { color = "#7c8e8b", cabin = 0.42, beacons = false },        -- §2.1 event sedan grey
	patrol_car = { color = "#e0e6de", cabin = 0.42, beacons = true },    -- §5.7 white, red/blue bar
	ambulance = { color = "#f0eee6", cabin = 0.5, beacons = true },       -- §5.8 box and stripes
	delivery_van = { color = "#d9d4c4", cabin = 0.55, beacons = false },   -- §2.3
	ice_cream_van = { color = "#f3e7d7", cabin = 0.55, beacons = false },  -- §2.4 SCOOP MOBILE
	trolley = { color = "#7f2f2a", cabin = 0.6, beacons = false },        -- §2.5 CITY TROLLEY
	dump_truck = { color = "#c99a2e", cabin = 0.5, beacons = false },      -- §2.6
	rv = { color = "#e8e2d2", cabin = 0.6, beacons = false },             -- §2.6
	cart = { color = "#e9ece6", cabin = 0.45, beacons = false },           -- brief v2 golf cart
	motorcycle = { color = "#3a3f46", cabin = 0.3, beacons = false },      -- §2.7
}

local BEACON_RED, BEACON_BLUE, BEACON_WHITE = "#ff2a2a", "#2f6bff", "#fff4e6"
VehiclePuppet.BEACONS = { red = BEACON_RED, blue = BEACON_BLUE, white = BEACON_WHITE }

VehiclePuppet.KINDS = {} :: { string }
for kind in DEFAULTS do
	table.insert(VehiclePuppet.KINDS, kind)
end
table.sort(VehiclePuppet.KINDS)

function VehiclePuppet.baseOffset(kind: string): number
	return Boxes.get(kind).height / 2
end

function VehiclePuppet.length(kind: string): number
	return Boxes.get(kind).length
end

function VehiclePuppet.width(kind: string): number
	return Boxes.get(kind).width
end

-- track(kind): how far apart its left and right wheels stand (studs), or nil for a two-wheeler, which
-- stands upright whatever the road's crossfall (Traffic/Ghost.seat rolls the rest with the ground)
function VehiclePuppet.track(kind: string): number?
	if kind == "motorcycle" then
		return nil
	end
	return Boxes.get(kind).width * 0.8
end

-- Colours the fleet entry does not choose (the paint is the entry's colour or the kind's default).
local FIXED = {
	trim = "#2a2d31", -- bumpers, sills
	seam = "#16181b", -- door seams, the grille
	glass = "#1f2c35",
	tyre = "#17181a",
	arch = "#0c0d0f",
	chrome = "#c4c9cc", -- hub caps
	plate = "#e8e6da",
	head = "#fff3b5",
	tail = "#c53227",
}

type Rgb = PartBuilder.Rgb
type Part = PartBuilder.PartSpec

-- A vehicle being drawn: its box and the visible parts so far. Every helper below takes heights in studs
-- ABOVE THE GROUND (the box bottom) and stations along Z with the nose at -L/2, and returns the part so
-- the caller can set a shape or a material on it.
type Kit = { parts: { Part }, W: number, L: number, H: number, hw: number, hl: number, bottom: number }

local function newKit(W: number, L: number, H: number): Kit
	return { parts = {}, W = W, L = L, H = H, hw = W / 2, hl = L / 2, bottom = -H / 2 }
end

local function put(k: Kit, p: Part): Part
	table.insert(k.parts, p)
	return p
end

-- a box centred on the car's axis: half-width in X, y0..y1 above the ground, z0..z1. Many of these run
-- THROUGH the body and show only at their two ends (side glass, door seams, stripes, mirrors): one part
-- draws the left and the right of the vehicle, which is what keeps a whole vehicle near forty parts.
local function add(k: Kit, name: string, halfX: number, y0: number, y1: number, z0: number, z1: number, c: Rgb): Part
	return put(k, {
		name = name,
		size = { halfX * 2, y1 - y0, z1 - z0 },
		pos = { 0, k.bottom + (y0 + y1) / 2, (z0 + z1) / 2 },
		color = c,
	})
end

-- a cylinder across the car (axis X) of radius r, its centre y above the ground at station z
local function across(k: Kit, name: string, halfX: number, r: number, y: number, z: number, c: Rgb): Part
	return put(k, {
		name = name,
		size = { halfX * 2, r * 2, r * 2 },
		pos = { 0, k.bottom + y, z },
		color = c,
		shape = "Cylinder",
	})
end

-- an upright cylinder of radius r (a rounded corner in plan, a post) from y0 to y1 above the ground
local function upright(k: Kit, name: string, x: number, z: number, r: number, y0: number, y1: number, c: Rgb): Part
	return put(k, {
		name = name,
		size = { y1 - y0, r * 2, r * 2 },
		pos = { x, k.bottom + (y0 + y1) / 2, z },
		roll = math.pi / 2,
		color = c,
		shape = "Cylinder",
	})
end

-- a cylinder along the car (axis Z) of radius r from z0 to z1 (a rounded roof edge, a rail)
local function along(k: Kit, name: string, x: number, y: number, r: number, z0: number, z1: number, c: Rgb): Part
	return put(k, {
		name = name,
		size = { z1 - z0, r * 2, r * 2 },
		pos = { x, k.bottom + y, (z0 + z1) / 2 },
		yaw = math.pi / 2,
		color = c,
		shape = "Cylinder",
	})
end

local function ball(k: Kit, name: string, x: number, y: number, z: number, r: number, c: Rgb): Part
	return put(k, {
		name = name,
		size = { r * 2, r * 2, r * 2 },
		pos = { x, k.bottom + y, z },
		color = c,
		shape = "Ball",
	})
end

-- The four named wheels (tyres on the ground, outer faces at x = +-outer) under a dark arch disc on each
-- flank (one cylinder through the body per axle, a little larger than the tyre and centred above it) and
-- one bright axle per pair whose ends are the hub caps. `body` is the half-width of the flank the arches
-- lie on.
local function running(
	k: Kit,
	body: number,
	outer: number,
	wheelR: number,
	wheelW: number,
	archR: number,
	hubR: number,
	axleF: number,
	axleB: number
)
	for _, a in { { tag = "F", z = axleF }, { tag = "B", z = axleB } } do
		across(k, `Arch{a.tag}`, body + 0.03, archR, archR, a.z, hex(FIXED.arch))
		across(k, `Hubs{a.tag}`, math.min(outer + 0.05, k.hw), hubR, wheelR, a.z, hex(FIXED.chrome)).material = "Metal"
	end
	for _, w in
		{
			{ name = "WheelFL", sx = -1, z = axleF },
			{ name = "WheelFR", sx = 1, z = axleF },
			{ name = "WheelBL", sx = -1, z = axleB },
			{ name = "WheelBR", sx = 1, z = axleB },
		}
	do
		put(k, {
			name = w.name,
			size = { wheelW, wheelR * 2, wheelR * 2 },
			pos = { w.sx * (outer - wheelW / 2), k.bottom + wheelR, w.z },
			color = hex(FIXED.tyre),
			shape = "Cylinder",
		})
	end
end

-- A rounded nose in front of a body slab that starts at -ends + R: a lower, narrower block with a rounded
-- top edge, an upright cylinder at each corner and a ball where the two rounds meet (six parts).
local function roundNose(k: Kit, bw: number, ends: number, R: number, sill: number, waist: number, c: Rgb)
	add(k, "Nose", bw - R, sill, waist - R, -ends, -ends + R, c)
	across(k, "NoseEdge", bw - R, R, waist - R, -ends + R, c)
	for _, sx in { -1, 1 } do
		local side = if sx < 0 then "L" else "R"
		upright(k, `CornerF{side}`, sx * (bw - R), -ends + R, R, sill, waist - R, c)
		ball(k, `Fender{side}`, sx * (bw - R), waist - R, -ends + R, R, c)
	end
end

-- A lit strip across the nose and one across the tail, each with its middle covered by the caller (a
-- grille; a boot panel or rear doors): a PAIR of lamps from one part, under RigSpec's two names.
local function lamps(k: Kit, half: number, ends: number, headY: number, tailY: number, tall: number)
	add(k, "Headlights", half, headY, headY + tall, -ends - 0.05, -ends + 0.05, hex(FIXED.head)).material = "Neon"
	add(k, "TailLights", half, tailY, tailY + tall, ends - 0.05, ends + 0.05, hex(FIXED.tail)).material = "Neon"
end

-- A builder draws one kind into the kit and returns the station (Z) of its beacon bar, which shapedSpec
-- lays against the top of the box (hidden unless the kind carries beacons).
type Builder = (k: Kit, color: Rgb) -> number

-- The saloon (sedan, patrol car): the bumpers, wheels, mirrors and roof touch the faces of the box so
-- the car fills it. Tuned for the 5.9 x 5.1 x 11.1 box.
local function sedanParts(k: Kit, color: Rgb): number
	local hw, hl, L, H = k.hw, k.hl, k.L, k.H
	local trim, seam, glass = hex(FIXED.trim), hex(FIXED.seam), hex(FIXED.glass)
	local wheelR, wheelW = 1.05, 0.85
	local axleZ = hl - L * 0.18
	local archR = 1.22
	local bw = hw - 0.14 -- body half-width: the tyres stand 0.09 proud of it, the hub caps 0.14
	local cw = bw - 0.42 -- cabin half-width: a shoulder each side
	local ends = hl - 0.2 -- the body's nose and tail faces; the bumpers reach the box
	local sill, waist, belt, roof = 0.5, 2.65, 3.05, H - 0.3
	local R = 0.6 -- the corners in plan, and the rounded top edge of the nose
	local screen0, screen1 = -hl + L * 0.31, -hl + L * 0.445 -- windscreen foot and head
	local rear1, rear0 = hl - L * 0.275, hl - L * 0.155 -- rear window head and foot

	-- lower body: one full-width slab between the rounded ends, the rounded nose in front of it, the
	-- tail block and its two corners up to the boot lid behind. On top the bonnet rises from the nose
	-- to the windscreen foot, and the deck (scuttle, shoulders and boot lid) runs at belt height to
	-- the tail.
	add(k, "Body", bw, sill, waist, -ends + R, ends - R, color)
	roundNose(k, bw, ends, R, sill, waist, color)
	add(k, "Tail", bw - R, sill, belt, ends - R, ends, color)
	add(k, "Bonnet", bw, waist, belt, -ends + R, screen0, color).shape = "Wedge"
	add(k, "Deck", bw, waist, belt, screen0, ends - R, color)
	upright(k, "CornerBL", -(bw - R), ends - R, R, sill, belt, color)
	upright(k, "CornerBR", bw - R, ends - R, R, sill, belt, color)

	-- cabin: a painted box under the roof between two glass wedges (the raked windscreen, and the rear
	-- window turned about), side glass and a centre pillar let through it, a low crown on the roof
	add(k, "Cabin", cw, belt, roof, screen1, rear1, color)
	local screen = add(k, "Windscreen", cw, belt, roof, screen0, screen1, glass)
	screen.shape, screen.material = "Wedge", "Glass"
	local rear = add(k, "RearWindow", cw, belt, roof, rear1, rear0, glass)
	rear.shape, rear.material, rear.yaw = "Wedge", "Glass", math.pi
	add(k, "SideGlass", cw + 0.04, belt + 0.12, roof - 0.4, screen1 + 0.28, rear1 - 0.28, glass).material = "Glass"
	local pillarZ = screen1 + (rear1 - screen1) * 0.45
	add(k, "PillarB", cw + 0.07, belt, roof, pillarZ - 0.13, pillarZ + 0.13, color)
	add(k, "Roof", cw - 0.25, roof, roof + 0.15, screen1 + 0.15, rear1 - 0.15, color)
	add(k, "Mirrors", hw, belt + 0.12, belt + 0.46, screen1 - 0.2, screen1 + 0.06, color)

	running(k, bw, hw - 0.05, wheelR, wheelW, archR, 0.5, -axleZ, axleZ)

	-- trim: bumpers out to the box faces, a sill between the arches and two door seams (each seam one
	-- part through the body: the front door's leading edge and the pillar; the rear door ends at its arch)
	add(k, "BumperF", bw + 0.06, sill - 0.05, 1.12, -hl, -ends + 0.45, trim)
	add(k, "BumperB", bw + 0.06, sill - 0.05, 1.12, ends - 0.45, hl, trim)
	add(k, "Sill", bw + 0.04, sill, sill + 0.28, -axleZ + archR, axleZ - archR, trim)
	for i, z in { -axleZ + archR + 0.14, pillarZ } do
		add(k, `Seam{i}`, bw + 0.03, sill + 0.28, belt - 0.04, z - 0.035, z + 0.035, seam)
	end

	-- face and tail: the lamp strips with their middles covered by the grille, and by the boot panel
	-- and the number plate
	local lamp = bw - R - 0.04
	add(k, "Headlights", lamp, 1.28, 1.86, -ends - 0.05, -ends + 0.05, hex(FIXED.head)).material = "Neon"
	add(k, "Grille", lamp - 0.95, 1.24, 1.9, -ends - 0.09, -ends + 0.05, seam)
	add(k, "TailLights", lamp, 1.82, 2.34, ends - 0.05, ends + 0.05, hex(FIXED.tail)).material = "Neon"
	add(k, "BootPanel", lamp - 0.9, 1.78, 2.38, ends - 0.05, ends + 0.09, color)
	add(k, "Plate", 0.75, 1.24, 1.66, ends - 0.05, ends + 0.06, hex(FIXED.plate))
	return (screen1 + rear1) / 2
end

-- a box anywhere: x0..x1, y0..y1 above the ground, z0..z1
local function box(
	k: Kit,
	name: string,
	x0: number,
	x1: number,
	y0: number,
	y1: number,
	z0: number,
	z1: number,
	c: Rgb
): Part
	return put(k, {
		name = name,
		size = { x1 - x0, y1 - y0, z1 - z0 },
		pos = { (x0 + x1) / 2, k.bottom + (y0 + y1) / 2, (z0 + z1) / 2 },
		color = c,
	})
end

-- The one-box body the vans share (ambulance, delivery van, ice cream van, RV): a short sloped bonnet
-- behind the rounded nose, a raked windscreen, then one tall hull to a square tail under a roof with
-- rounded edges; cab glass, mirrors out to the box, door seams, bumpers, lamps and the rear doors.
-- Heights above the ground; stations from the nose (0) toward the tail, turned into Z here.
type Van = {
	inset: number, -- the flanks stand this far inside the box (the mirrors reach it)
	sill: number,
	waist: number, -- top of the nose and foot of the bonnet
	belt: number, -- top of the bonnet at the windscreen foot; the cab window sill
	roof: number,
	roofR: number, -- the rounded roof edges
	R: number, -- the nose's corners and top edge
	screen0: number, -- windscreen foot and head, stations behind the nose
	screen1: number,
	screenTop: number, -- the windscreen's top edge (the hull stands above it on a high roof)
	cab: number, -- length of the cab door and its glass behind the windscreen head
	wheelR: number,
	wheelW: number,
	axleF: number, -- stations behind the nose
	axleB: number,
	lampY: number, -- headlamp strip height
	tailY: number,
	doors: boolean, -- rear doors with a window, split down the middle; else a plain panel between the lamps
}

-- Returns the half-width of the flanks, the station (Z) of the body's tail face and of the hull's front.
local function vanBody(k: Kit, color: Rgb, v: Van): (number, number, number)
	local hw, hl = k.hw, k.hl
	local trim, seam, glass = hex(FIXED.trim), hex(FIXED.seam), hex(FIXED.glass)
	local bw, ends, R, rr = hw - v.inset, hl - 0.2, v.R, v.roofR
	local s0, s1 = -ends + v.screen0, -ends + v.screen1
	local top = v.roof - rr
	local axleF, axleB = -ends + v.axleF, -ends + v.axleB
	local archR = v.wheelR + 0.17

	add(k, "Body", bw, v.sill, v.waist, -ends + R, s1, color)
	roundNose(k, bw, ends, R, v.sill, v.waist, color)
	add(k, "Bonnet", bw, v.waist, v.belt, -ends + R, s0, color).shape = "Wedge"
	add(k, "Scuttle", bw, v.waist, v.belt, s0, s1, color)
	add(k, "Hull", bw, v.sill, top, s1, ends, color)
	add(k, "Roof", bw - rr, top, v.roof, s1, ends, color)
	along(k, "RoofEdgeL", -(bw - rr), top, rr, s1 + 0.03, ends - 0.03, color)
	along(k, "RoofEdgeR", bw - rr, top, rr, s1 + 0.03, ends - 0.03, color)

	local screen = add(k, "Windscreen", bw - 0.14, v.belt, v.screenTop, s0, s1, glass)
	screen.shape, screen.material = "Wedge", "Glass"
	add(k, "SideGlass", bw + 0.04, v.belt + 0.15, v.screenTop - 0.2, s1 + 0.3, s1 + v.cab, glass).material = "Glass"
	add(k, "Mirrors", hw, v.belt + 0.2, v.belt + 0.2 + math.max(0.4, v.wheelR * 0.5), s1 + 0.04, s1 + 0.3, trim)

	running(k, bw, bw + 0.1, v.wheelR, v.wheelW, archR, v.wheelR * 0.48, axleF, axleB)

	add(k, "BumperF", bw + 0.06, v.sill - 0.05, v.sill + 0.62, -hl, -ends + 0.45, trim)
	add(k, "BumperB", bw + 0.06, v.sill - 0.05, v.sill + 0.62, ends - 0.45, hl, trim)
	-- the cab door: its leading edge behind the front arch, its trailing edge behind the glass
	for i, z in { math.max(axleF + archR + 0.14, s1 + 0.12), s1 + v.cab + 0.22 } do
		add(k, `Seam{i}`, bw + 0.03, v.sill + 0.2, v.belt + 0.1, z - 0.035, z + 0.035, seam)
	end

	-- face: the lamp strip behind the grille; tail: the lamp strip behind the rear doors, which carry
	-- a window and are split down the middle
	local lamp = bw - R - 0.04
	local tall = math.max(0.55, v.wheelR * 0.5)
	lamps(k, lamp, ends, v.lampY, v.tailY, tall)
	add(k, "Grille", lamp * 0.58, v.lampY - 0.04, v.lampY + tall + 0.04, -ends - 0.09, -ends + 0.05, seam)
	local door = lamp - math.max(0.55, bw * 0.16)
	if v.doors then
		add(k, "RearDoors", door, v.sill + 0.62, top - 0.15, ends - 0.05, ends + 0.09, color)
		add(k, "RearGlass", door - 0.3, v.belt + 0.3, v.screenTop - 0.2, ends - 0.05, ends + 0.12, glass).material =
			"Glass"
		add(k, "DoorSplit", 0.04, v.sill + 0.62, top - 0.15, ends - 0.05, ends + 0.15, seam)
	else
		add(k, "RearPanel", door, v.tailY - 0.08, v.tailY + tall + 0.08, ends - 0.05, ends + 0.09, color)
	end
	return bw, ends, s1
end

local STRIPE_RED = "#c9372c"

-- Ambulance: the sedan's box, so a low car-derived van: white, a red stripe along the flanks, a green
-- medical cross on each side, the red and white bar over the cab.
local function ambulanceParts(k: Kit, color: Rgb): number
	local H = k.H
	local red = hex(STRIPE_RED)
	local bw, ends, front = vanBody(k, color, {
		inset = 0.14,
		sill = 0.5,
		waist = 2.4,
		belt = 2.95,
		roof = H - 0.3,
		roofR = 0.35,
		R = 0.5,
		screen0 = 2.3,
		screen1 = 3.35,
		screenTop = H - 0.65,
		cab = 2.2,
		wheelR = 1.05,
		wheelW = 0.85,
		axleF = 1.75,
		axleB = 8.9,
		lampY = 1.2,
		tailY = 1.75,
		doors = true,
	})
	add(k, "Stripe", bw + 0.03, 2.45, 2.8, front + 2.5, ends - 0.02, red)
	local crossZ = (front + 2.4 + ends) / 2
	-- the medical cross is green: a red cross on white is the protected emblem of the Red Cross and
	-- must not be used on a game's ambulance
	local green = hex("#2f9e5b")
	add(k, "CrossV", bw + 0.035, 3.1, 4.3, crossZ - 0.2, crossZ + 0.2, green)
	add(k, "CrossH", bw + 0.045, 3.5, 3.9, crossZ - 0.6, crossZ + 0.6, green)
	return front + 1.1
end

local PARCEL_BROWN = "#9a5a2a"

-- Delivery van: a tall panel van, the cab under a high roof, a brown band and a parcel panel on the
-- load space, a sliding-door seam, double doors at the back.
local function deliveryVanParts(k: Kit, color: Rgb): number
	local brown = hex(PARCEL_BROWN)
	local bw, ends, front = vanBody(k, color, {
		inset = 0.3,
		sill = 0.75,
		waist = 3.3,
		belt = 4.3,
		roof = k.H,
		roofR = 0.7,
		R = 0.65,
		screen0 = 2.3,
		screen1 = 3.9,
		screenTop = 7.0,
		cab = 2.6,
		wheelR = 1.3,
		wheelW = 1.0,
		axleF = 2.6,
		axleB = 11.0,
		lampY = 1.7,
		tailY = 2.3,
		doors = true,
	})
	local load = front + 2.6 + 0.6 -- behind the cab door
	add(k, "Band", bw + 0.02, 3.5, 4.15, load, ends - 0.02, brown)
	add(k, "Parcel", bw + 0.03, 5.3, 7.5, load + 2.3, load + 5.1, brown)
	add(k, "Seam3", bw + 0.03, 0.95, 8.2, load + 1.5, load + 1.57, hex(FIXED.seam))
	return front + 1.2
end

local SCOOP_PINK, WAFER = "#e58aa6", "#d2a25c"

-- Ice cream van (SCOOP MOBILE): cream with a pink skirt between the wheels; on the kerb side (local +X,
-- we drive on the right) a serving hatch with a counter and a pink awning; a wafer and a pink scoop on
-- the roof over the cab, up to the top of the box.
local function iceCreamVanParts(k: Kit, color: Rgb): number
	local pink = hex(SCOOP_PINK)
	local roof = k.H - 2.1
	local bw, ends, front = vanBody(k, color, {
		inset = 0.4,
		sill = 0.75,
		waist = 3.2,
		belt = 4.2,
		roof = roof,
		roofR = 0.6,
		R = 0.65,
		screen0 = 2.4,
		screen1 = 4.0,
		screenTop = roof - 0.6,
		cab = 2.6,
		wheelR = 1.3,
		wheelW = 1.0,
		axleF = 2.7,
		axleB = 12.4,
		lampY = 1.7,
		tailY = 2.3,
		doors = false,
	})
	local archR = 1.3 + 0.17
	add(k, "Skirt", bw + 0.02, 0.95, 2.7, -ends + 2.7 + archR + 0.06, -ends + 12.4 - archR - 0.06, pink)
	local hatch0, hatch1 = front + 4.0, front + 7.6
	box(k, "Hatch", bw - 0.3, bw + 0.03, 4.55, roof - 0.8, hatch0, hatch1, hex("#3b2c2a"))
	box(k, "Counter", bw - 0.1, k.hw, 4.3, 4.55, hatch0 - 0.25, hatch1 + 0.25, hex(FIXED.chrome)).material = "Metal"
	-- the awning: a wedge turned so its high side is against the van and it falls away toward the kerb
	put(k, {
		name = "Awning",
		size = { hatch1 - hatch0 + 0.5, 0.6, k.hw - bw },
		pos = { (bw + k.hw) / 2, k.bottom + roof - 0.9, (hatch0 + hatch1) / 2 },
		yaw = -math.pi / 2,
		color = pink,
		shape = "Wedge",
	})
	local coneZ = front + 1.4
	upright(k, "Cone", 0, coneZ, 0.55, roof, roof + 0.95, hex(WAFER))
	ball(k, "Scoop", 0, k.H - 0.82, coneZ, 0.8, pink)
	return coneZ + 2
end

local TROLLEY_CREAM, TROLLEY_GOLD, TROLLEY_ROOF = "#e9dfc4", "#d8b04a", "#4b4e52"

-- Trolley (CITY TROLLEY): a streetcar. A painted lower body with rounded ends, a cream window band with
-- one long strip of glass let through it and cream pillars across the strip, upright glass at both ends,
-- a grey roof with rounded edges and a raised monitor, the trolley pole trailing up to the top of the
-- box, one round headlamp, a lit destination board, a dark door on the kerb side (local +X).
local function trolleyParts(k: Kit, color: Rgb): number
	local hw, hl, H = k.hw, k.hl, k.H
	local cream, grey, glass, trim = hex(TROLLEY_CREAM), hex(TROLLEY_ROOF), hex(FIXED.glass), hex(FIXED.trim)
	local bw, ends, R = hw - 0.3, hl - 0.25, 1.2
	local sill, belt, top = 0.9, 4.4, H - 1.5
	local z0, z1 = -ends + R, ends - R -- the straight flanks between the rounded ends

	add(k, "Body", bw, sill, belt, z0, z1, color)
	add(k, "Nose", bw - R, sill, belt, -ends, z0, color)
	add(k, "Tail", bw - R, sill, belt, z1, ends, color)
	add(k, "Cabin", bw, belt, top, z0, z1, cream)
	add(k, "CabinF", bw - R, belt, top, -ends, z0, cream)
	add(k, "CabinB", bw - R, belt, top, z1, ends, cream)
	for _, c in
		{
			{ tag = "FL", sx = -1, z = z0 },
			{ tag = "FR", sx = 1, z = z0 },
			{ tag = "BL", sx = -1, z = z1 },
			{ tag = "BR", sx = 1, z = z1 },
		}
	do
		upright(k, `Corner{c.tag}`, c.sx * (bw - R), c.z, R, sill, top, color)
	end

	-- windows: one strip of glass through the car, four pillars across it; upright glass at the ends
	local g0, g1 = z0 + 0.8, z1 - 0.8
	add(k, "SideGlass", bw + 0.04, belt + 0.35, top - 0.55, g0, g1, glass).material = "Glass"
	for i = 1, 4 do
		local z = g0 + (g1 - g0) * i / 5
		add(k, `Pillar{i}`, bw + 0.07, belt, top, z - 0.2, z + 0.2, cream)
	end
	add(k, "Windscreen", bw - R - 0.15, belt + 0.35, top - 0.75, -ends - 0.05, -ends + 0.3, glass).material = "Glass"
	add(k, "RearWindow", bw - R - 0.15, belt + 0.35, top - 0.75, ends - 0.3, ends + 0.05, glass).material = "Glass"
	add(k, "Board", 1.7, top - 0.6, top - 0.1, -ends - 0.07, -ends + 0.1, hex("#f6e7a6")).material = "Neon"
	box(k, "Door", bw - 0.1, bw + 0.09, sill + 0.3, top - 0.55, g0 + 0.25, g0 + 2.4, hex("#2a2422"))
	add(k, "Stripe", bw + 0.02, belt - 0.55, belt - 0.25, z0, z1, hex(TROLLEY_GOLD))
	add(k, "Mirrors", hw, belt + 0.6, belt + 1.3, z0 + 0.05, z0 + 0.35, trim)

	-- roof: a grey lid with rounded edges, the monitor along it, the pole trailing up and back
	add(k, "Roof", bw - 0.9, top, top + 0.4, -ends + 0.5, ends - 0.5, grey)
	along(k, "RoofEdgeL", -(bw - 0.9), top, 0.4, -ends + 0.53, ends - 0.53, grey)
	along(k, "RoofEdgeR", bw - 0.9, top, 0.4, -ends + 0.53, ends - 0.53, grey)
	add(k, "Monitor", 1.5, top + 0.4, top + 0.95, z0 + 2, z1 - 2, hex("#6a6d70"))
	put(k, {
		name = "Pole",
		size = { 0.12, 0.12, 5 },
		pos = { 0, k.bottom + H - 0.3, 2.4 },
		pitch = -0.09,
		color = trim,
	})

	running(k, bw, bw + 0.1, 1.15, 0.9, 1.32, 0.5, -hl * 0.62, hl * 0.62)
	add(k, "BumperF", bw - R * 0.6, sill - 0.15, sill + 0.55, -hl, -ends + 0.5, trim)
	add(k, "BumperB", bw - R * 0.6, sill - 0.15, sill + 0.55, ends - 0.5, hl, trim)
	along(k, "Headlights", 0, 2.7, 0.5, -ends - 0.1, -ends + 0.2, hex(FIXED.head)).material = "Neon"
	add(k, "TailLights", 1.5, 2.4, 2.85, ends - 0.05, ends + 0.05, hex(FIXED.tail)).material = "Neon"
	return 0
end

-- Dump truck: a bonneted cab riding high on big wheels, an exhaust stack behind it, and an open tipper
-- body on a dark chassis: floor, two ribbed sides, a headboard with a shield over the cab roof (the top
-- of the box), a tailgate, a load of earth; two rear axles (the second is one roller through the truck).
local function dumpTruckParts(k: Kit, color: Rgb): number
	local hw, hl, H = k.hw, k.hl, k.H
	local trim, seam, glass, tyre = hex(FIXED.trim), hex(FIXED.seam), hex(FIXED.glass), hex(FIXED.tyre)
	local chrome = hex(FIXED.chrome)
	local bw, ends, R = hw - 0.3, hl - 0.2, 0.7
	local sill, waist, belt, roof = 1.4, 4.3, 5.3, H - 1.3
	local s0, s1 = -ends + 3.3, -ends + 4.7 -- windscreen foot and head
	local cabEnd = -ends + 7.6
	local wheelR, wheelW = 1.6, 1.25
	local axleF, axleB, axleT = -ends + 2.5, ends - 6.6, ends - 3.0

	-- cab: the van's nose and bonnet under a short painted cabin
	add(k, "Body", bw, sill, waist, -ends + R, cabEnd, color)
	roundNose(k, bw, ends, R, sill, waist, color)
	add(k, "Bonnet", bw, waist, belt, -ends + R, s0, color).shape = "Wedge"
	add(k, "Scuttle", bw, waist, belt, s0, cabEnd, color)
	add(k, "Cabin", bw, belt, roof, s1, cabEnd, color)
	local screen = add(k, "Windscreen", bw - 0.14, belt, roof - 0.3, s0, s1, glass)
	screen.shape, screen.material = "Wedge", "Glass"
	add(k, "SideGlass", bw + 0.04, belt + 0.2, roof - 0.6, s1 + 0.3, cabEnd - 0.5, glass).material = "Glass"
	add(k, "Mirrors", hw, belt + 0.3, belt + 1.2, s1 + 0.04, s1 + 0.32, trim)
	upright(k, "Stack", -(bw + 0.06), cabEnd - 0.35, 0.22, waist, H - 0.5, chrome).material = "Metal"

	-- chassis and tipper
	local bed0, floor, rim = cabEnd + 0.75, 3.5, H - 2.1
	add(k, "Chassis", bw - 1.4, 2.0, floor, cabEnd, ends - 0.2, trim)
	add(k, "Bed", bw, floor, floor + 0.45, bed0, ends, color)
	box(k, "BedL", -bw, -bw + 0.4, floor + 0.45, rim, bed0, ends, color)
	box(k, "BedR", bw - 0.4, bw, floor + 0.45, rim, bed0, ends, color)
	add(k, "Headboard", bw, floor + 0.45, H - 0.4, bed0, bed0 + 0.4, color)
	add(k, "Shield", bw, H - 0.4, H, cabEnd - 2.2, bed0 + 0.4, color)
	add(k, "Tailgate", bw - 0.4, floor + 0.45, rim, ends - 0.35, ends, color)
	-- heaped above the rim, so the ribs (which run through the body) show on the flanks only
	add(k, "Load", bw - 0.4, floor + 0.45, rim + 0.25, bed0 + 0.4, ends - 0.35, hex("#6b5a45")).material = "Slate"
	local span = ends - bed0
	for i = 1, 2 do
		local z = bed0 + span * (i * 0.33 + 0.02)
		add(k, `Rib{i}`, bw + 0.06, floor, rim, z - 0.18, z + 0.18, trim)
	end

	-- running gear: an arch on the cab's flank only; the rear wheels stand bare under the tipper
	across(k, "ArchF", bw + 0.03, wheelR + 0.2, wheelR + 0.2, axleF, hex(FIXED.arch))
	for _, a in { { tag = "F", z = axleF }, { tag = "B", z = axleB }, { tag = "T", z = axleT } } do
		across(k, `Hubs{a.tag}`, bw + 0.15, wheelR * 0.45, wheelR, a.z, chrome).material = "Metal"
	end
	across(k, "Tandem", bw + 0.1, wheelR, wheelR, axleT, tyre)
	for _, w in
		{
			{ name = "WheelFL", sx = -1, z = axleF },
			{ name = "WheelFR", sx = 1, z = axleF },
			{ name = "WheelBL", sx = -1, z = axleB },
			{ name = "WheelBR", sx = 1, z = axleB },
		}
	do
		put(k, {
			name = w.name,
			size = { wheelW, wheelR * 2, wheelR * 2 },
			pos = { w.sx * (bw + 0.1 - wheelW / 2), k.bottom + wheelR, w.z },
			color = tyre,
			shape = "Cylinder",
		})
	end

	add(k, "BumperF", bw + 0.06, sill - 0.2, sill + 0.7, -hl, -ends + 0.5, trim)
	-- the tail: a cross-member under the tailgate carrying the lamp strip out to the end of the box
	add(k, "BumperB", bw - 0.3, 1.7, floor, ends - 0.6, hl - 0.06, trim)
	add(k, "TailLights", bw - 0.7, 2.3, 2.9, hl - 0.1, hl, hex(FIXED.tail)).material = "Neon"
	local lamp = bw - R - 0.04
	add(k, "Headlights", lamp, 2.45, 3.2, -ends - 0.05, -ends + 0.05, hex(FIXED.head)).material = "Neon"
	add(k, "Grille", lamp * 0.6, 2.35, 3.5, -ends - 0.09, -ends + 0.05, seam)
	return (s1 + cabEnd) / 2
end

-- RV: a long motorhome on the van body: two saloon windows through the hull, a tan stripe, an entry door
-- and a rolled awning on the kerb side (local +X), an air conditioner on the roof up to the top of the box.
local function rvParts(k: Kit, color: Rgb): number
	local roof = k.H - 0.85
	local glass = hex(FIXED.glass)
	local bw, ends, front = vanBody(k, color, {
		inset = 0.35,
		sill = 0.8,
		waist = 3.4,
		belt = 4.5,
		roof = roof,
		roofR = 0.7,
		R = 0.65,
		screen0 = 2.4,
		screen1 = 4.1,
		screenTop = 7.3,
		cab = 2.7,
		wheelR = 1.35,
		wheelW = 1.0,
		axleF = 2.7,
		axleB = 15.7,
		lampY = 1.75,
		tailY = 2.4,
		doors = false,
	})
	local saloon = front + 2.7 + 1.1 -- behind the cab door
	add(k, "Stripe", bw + 0.02, 3.7, 4.3, front + 0.02, ends - 0.02, hex("#9b7b4f"))
	add(k, "WindowA", bw + 0.04, 5.6, 7.6, saloon, saloon + 3.2, glass).material = "Glass"
	add(k, "WindowB", bw + 0.04, 5.6, 7.6, saloon + 5.4, saloon + 9.2, glass).material = "Glass"
	box(k, "Door", bw - 0.1, bw + 0.03, 1.1, 7.9, saloon + 3.6, saloon + 5.0, hex("#cfc8b6"))
	add(k, "AirCon", 1.2, roof, k.H, saloon + 2.6, saloon + 5.2, hex("#d7d4ca"))
	along(k, "Awning", bw + 0.1, roof - 0.95, 0.25, saloon - 0.3, saloon + 9.6, hex("#6f4f3a"))
	return front + 1.2
end

local CART_SEAT = "#c9b68f"

-- Golf cart: an open tub with a rounded nose and a sloped cowl, a bench seat, two golf bags standing on
-- the rear deck, and a canopy (the top of the box) on four posts behind a clear windshield.
local function cartParts(k: Kit, color: Rgb): number
	local hw, hl, H = k.hw, k.hl, k.H
	local trim, seat = hex(FIXED.trim), hex(CART_SEAT)
	local bw, ends, R = hw - 0.12, hl - 0.12, 0.45
	local sill, floor, cowl = 0.45, 1.3, 1.85
	local dash, bench, deck = -hl + 2.3, 0.4, 1.9 -- stations (Z) of the dash, the seat front and the deck

	add(k, "Body", bw, sill, floor, dash + 0.3, ends, color)
	add(k, "Front", bw, sill, cowl, -ends + R, dash + 0.3, color)
	roundNose(k, bw, ends, R, sill, cowl, color)
	add(k, "Cowl", bw, cowl, 2.25, -ends + R, dash + 0.3, color).shape = "Wedge"
	add(k, "SeatBase", bw - 0.1, floor, 1.85, bench, deck, color)
	add(k, "Seat", bw - 0.2, 1.85, 2.12, bench - 0.05, deck - 0.15, seat)
	add(k, "SeatBack", bw - 0.2, 2.12, 3.1, deck - 0.4, deck - 0.1, seat)
	add(k, "Deck", bw, floor, 1.75, deck, ends, color)
	upright(k, "Bag1", -0.75, deck + 0.75, 0.38, 1.75, 3.4, hex("#3f6b4a"))
	upright(k, "Bag2", 0.75, deck + 0.75, 0.38, 1.75, 3.25, hex("#8c3b32"))

	-- canopy, posts, windshield, steering wheel (on the driver's side, local -X)
	add(k, "Canopy", bw, H - 0.25, H, dash - 0.5, deck + 0.9, color)
	for _, c in
		{
			{ tag = "FL", sx = -1, z = dash + 0.15, foot = 2.1 },
			{ tag = "FR", sx = 1, z = dash + 0.15, foot = 2.1 },
			{ tag = "BL", sx = -1, z = deck + 0.1, foot = 1.75 },
			{ tag = "BR", sx = 1, z = deck + 0.1, foot = 1.75 },
		}
	do
		local x = c.sx * (bw - 0.1)
		box(k, `Post{c.tag}`, x - 0.07, x + 0.07, c.foot, H - 0.25, c.z - 0.07, c.z + 0.07, trim)
	end
	local shield = add(k, "Windshield", bw - 0.2, 2.2, H - 0.5, dash + 0.12, dash + 0.18, hex("#a9c0cb"))
	shield.material, shield.transparency = "Glass", 0.55
	along(k, "Steering", -0.85, 2.45, 0.32, dash + 0.45, dash + 0.53, trim)

	running(k, bw, hw - 0.05, 0.6, 0.5, 0.75, 0.3, -hl + 1.35, hl - 1.3)
	add(k, "BumperF", bw - 0.2, sill - 0.05, sill + 0.3, -hl, -ends + 0.3, trim)
	add(k, "BumperB", bw - 0.1, sill - 0.05, sill + 0.3, ends - 0.3, hl, trim)
	local lamp = bw - R - 0.04
	add(k, "Headlights", lamp, 0.95, 1.27, -ends - 0.05, -ends + 0.05, hex(FIXED.head)).material = "Neon"
	add(k, "Badge", lamp - 0.5, 0.91, 1.31, -ends - 0.08, -ends + 0.05, color)
	add(k, "TailLights", bw - 0.2, 0.85, 1.1, ends - 0.05, ends + 0.05, hex(FIXED.tail)).material = "Neon"
	add(k, "TailPanel", bw - 0.75, 0.81, 1.14, ends - 0.05, ends + 0.08, color)
	return 0.6
end

-- Motorcycle: two wheels in line (each drawn as two half-width tyres, so RigSpec's four wheel names
-- stand), raked forks, a round tank in the paint colour over a dark engine, a seat, mudguards, an
-- exhaust, handlebars out to the sides of the box and a tall clear screen up to its top.
local function motorcycleParts(k: Kit, color: Rgb): number
	local hw, hl, H = k.hw, k.hl, k.H
	local trim, tyre, chrome = hex(FIXED.trim), hex(FIXED.tyre), hex(FIXED.chrome)
	local metal = hex("#585c61")
	local wheelR, half = 0.82, 0.2
	local axle = hl - wheelR - 0.01
	for _, w in
		{
			{ name = "WheelFL", sx = -1, z = -axle },
			{ name = "WheelFR", sx = 1, z = -axle },
			{ name = "WheelBL", sx = -1, z = axle },
			{ name = "WheelBR", sx = 1, z = axle },
		}
	do
		put(k, {
			name = w.name,
			size = { half, wheelR * 2, wheelR * 2 },
			pos = { w.sx * half / 2, k.bottom + wheelR, w.z },
			color = tyre,
			shape = "Cylinder",
		})
	end
	across(k, "HubsF", half + 0.06, 0.36, wheelR, -axle, chrome).material = "Metal"
	across(k, "HubsB", half + 0.06, 0.36, wheelR, axle, chrome).material = "Metal"

	add(k, "Body", 0.28, 0.75, 1.6, -0.75, 0.75, metal).material = "Metal"
	across(k, "Engine", 0.4, 0.3, 1.05, -0.15, chrome).material = "Metal"
	along(k, "Tank", 0, 1.85, 0.38, -1.0, 0.15, color)
	add(k, "Seat", 0.3, 1.75, 2.05, 0.1, 1.45, hex("#1c1d20"))
	add(k, "FenderB", 0.24, 1.72, 1.86, 1.2, hl - 0.2, color)
	add(k, "FenderF", 0.22, 1.7, 1.8, -hl + 0.25, -axle + 0.55, color)
	along(k, "Exhaust", 0.38, 0.72, 0.11, 0.2, hl - 0.35, chrome).material = "Metal"
	-- forks: two thin legs from the front axle, raked back to the bars
	for _, sx in { -1, 1 } do
		put(k, {
			name = if sx < 0 then "ForkL" else "ForkR",
			size = { 0.09, 2.0, 0.11 },
			pos = { sx * 0.27, k.bottom + 1.72, -axle + 0.4 },
			pitch = 0.42,
			color = chrome,
			material = "Metal",
		})
	end
	across(k, "Bars", hw, 0.06, 2.68, -axle + 0.85, trim)
	along(k, "Headlights", 0, 2.3, 0.24, -axle + 0.3, -axle + 0.6, hex(FIXED.head)).material = "Neon"
	add(k, "Swingarm", 0.26, 0.72, 0.92, 0.6, axle, trim)
	local screen = add(k, "Screen", 0.42, 2.5, H, -axle + 0.62, -axle + 0.7, hex("#a9c0cb"))
	screen.material, screen.transparency = "Glass", 0.5
	add(k, "TailLights", 0.16, 1.62, 1.8, hl - 0.22, hl - 0.14, hex(FIXED.tail)).material = "Neon"
	return 0
end

-- Kinds drawn from shaped parts instead of the ten-block placeholder.
local BUILDERS: { [string]: Builder } = {
	sedan = sedanParts,
	patrol_car = sedanParts,
	ambulance = ambulanceParts,
	delivery_van = deliveryVanParts,
	ice_cream_van = iceCreamVanParts,
	trolley = trolleyParts,
	dump_truck = dumpTruckParts,
	rv = rvParts,
	cart = cartParts,
	motorcycle = motorcycleParts,
}

-- The whole shaped model: the invisible root at the logical box, the kind's body, the beacon bar against
-- the top of the box (hidden on a kind without beacons, as on the placeholders) and the same sockets as
-- the placeholder had.
local function shapedSpec(
	kind: string,
	build: Builder,
	o: Opts,
	color: Rgb,
	cabin: number,
	beacons: boolean
): PartBuilder.ModelSpec
	local size = Boxes.get(kind)
	local W, L, H = size.width, size.length, size.height
	local bottom = -H / 2
	local k = newKit(W, L, H)
	put(k, { name = "RootPart", size = { W, H, L }, pos = { 0, 0, 0 }, color = color, transparency = 1 })
	local barZ = build(k, color)
	local bar = { { name = "LightBar", sx = -1, color = BEACON_RED } }
	if beacons then
		table.insert(
			bar,
			{ name = "LightBarB", sx = 1, color = if kind == "ambulance" then BEACON_WHITE else BEACON_BLUE }
		)
	end
	local barW = math.min(W * 0.3, 1.8)
	for _, half in bar do
		put(k, {
			name = half.name,
			size = { barW, 0.3, 0.5 },
			pos = { half.sx * barW / 2, H / 2 - 0.15, barZ },
			color = hex(half.color),
			material = if beacons then "Neon" else "SmoothPlastic",
			transparency = if beacons then 0 else 1,
		})
	end
	local joints: { PartBuilder.JointSpec } = {}
	for i = 2, #k.parts do
		local name = k.parts[i].name
		if string.sub(name, 1, 5) == "Wheel" then
			-- the wheel joint is the spin axis (local X), as on the placeholders
			table.insert(joints, { name = name, kind = "Motor6D", part0 = "RootPart", part1 = name })
		else
			table.insert(joints, { name = `{name}Weld`, kind = "Weld", part0 = "RootPart", part1 = name })
		end
	end
	local seatX, bodyH = if kind == "motorcycle" then 0 else -W * 0.22, H * (1 - cabin)
	return {
		name = o.name or `Vehicle_{kind}`,
		species = "car",
		primary = "RootPart",
		parts = k.parts,
		joints = joints,
		attachments = {
			{ name = "DriverSeat", part = "RootPart", pos = { seatX, bottom + bodyH, 0 } },
			{ name = "DashSocket", part = "RootPart", pos = { seatX, bottom + bodyH + 0.4, -L * 0.18 } },
			{ name = "EyeSocket", part = "RootPart", pos = { seatX, H / 2 - 0.5, 0.2 } },
		},
		attributes = { VehicleKind = kind, BaseOffset = H / 2, BoxW = W, BoxL = L, BoxH = H },
	}
end

function VehiclePuppet.spec(kind: string, opts: Opts?): PartBuilder.ModelSpec
	local o: Opts = opts or {}
	local d = DEFAULTS[kind] or error(`VehiclePuppet: unknown kind {kind}`)
	local color = hex(o.color or d.color)
	local build = BUILDERS[kind] or error(`VehiclePuppet: no builder for {kind}`)
	return shapedSpec(kind, build, o, color, d.cabin, if o.beacons == nil then d.beacons else o.beacons)
end

return VehiclePuppet
