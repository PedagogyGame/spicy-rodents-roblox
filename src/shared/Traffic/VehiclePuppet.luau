--!strict
-- ReplicatedStorage.Shared.Traffic.VehiclePuppet
-- Placeholder vehicles at the TRUE logical boxes (BUILD_PLAN §4.4 W1 #9 and #10, D9, §5.2).
-- Interface: spec(kind, opts?) -> PartBuilder.ModelSpec; KINDS; baseOffset(kind) (root centre above the base); length(kind), width(kind), track(kind)
--
-- The invisible RootPart is exactly the logical box from Traffic/Boxes (the box the fatal test sweeps), and
-- the visible body plus cabin fill the same envelope, so a player never dies to a car that looks smaller.
-- These kinds are SHAPED (owner 2026-11-11: "the vehicles are extremely rough"), a vehicle from about forty
-- plain parts, no meshes (the BUILDERS below; the way worldgen/Builders/Fixtures shapes a building):
-- sedan, patrol car, ambulance. The rest are still the ten-block placeholder and
-- follow the same recipe.
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

-- stylua: ignore
local DEFAULTS: { [string]: { color: string, cabin: number, cabinLen: number, beacons: boolean } } = {
	sedan = { color = "#7c8e8b", cabin = 0.42, cabinLen = 0.55, beacons = false },        -- §2.1 event sedan grey
	patrol_car = { color = "#e0e6de", cabin = 0.42, cabinLen = 0.55, beacons = true },    -- §5.7 white, red/blue bar
	ambulance = { color = "#f0eee6", cabin = 0.5, cabinLen = 0.7, beacons = true },       -- §5.8 box and stripes
	delivery_van = { color = "#d9d4c4", cabin = 0.55, cabinLen = 0.8, beacons = false },   -- §2.3
	ice_cream_van = { color = "#f3e7d7", cabin = 0.55, cabinLen = 0.8, beacons = false },  -- §2.4 SCOOP MOBILE
	trolley = { color = "#7f2f2a", cabin = 0.6, cabinLen = 0.95, beacons = false },        -- §2.5 CITY TROLLEY
	dump_truck = { color = "#c99a2e", cabin = 0.5, cabinLen = 0.3, beacons = false },      -- §2.6
	rv = { color = "#e8e2d2", cabin = 0.6, cabinLen = 0.85, beacons = false },             -- §2.6
	cart = { color = "#e9ece6", cabin = 0.45, cabinLen = 0.5, beacons = false },           -- brief v2 golf cart
	motorcycle = { color = "#3a3f46", cabin = 0.3, cabinLen = 0.4, beacons = false },      -- §2.7
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
	add(k, "RearDoors", door, v.sill + 0.62, top - 0.15, ends - 0.05, ends + 0.09, color)
	add(k, "RearGlass", door - 0.3, v.belt + 0.3, v.screenTop - 0.2, ends - 0.05, ends + 0.12, glass).material = "Glass"
	add(k, "DoorSplit", 0.04, v.sill + 0.62, top - 0.15, ends - 0.05, ends + 0.15, seam)
	return bw, ends, s1
end

local STRIPE_RED = "#c9372c"

-- Ambulance: the sedan's box, so a low car-derived van: white, a red stripe along the flanks, a red
-- cross on each side, the red and white bar over the cab.
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
	})
	add(k, "Stripe", bw + 0.03, 2.45, 2.8, front + 2.5, ends - 0.02, red)
	local crossZ = (front + 2.4 + ends) / 2
	add(k, "CrossV", bw + 0.035, 3.1, 4.3, crossZ - 0.2, crossZ + 0.2, red)
	add(k, "CrossH", bw + 0.045, 3.5, 3.9, crossZ - 0.6, crossZ + 0.6, red)
	return front + 1.1
end

-- Kinds drawn from shaped parts instead of the ten-block placeholder.
local BUILDERS: { [string]: Builder } = {
	sedan = sedanParts,
	patrol_car = sedanParts,
	ambulance = ambulanceParts,
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
	local b = Boxes.get(kind)
	local W, L, H = b.width, b.length, b.height
	local color = hex(o.color or d.color)
	local build = BUILDERS[kind]
	if build then
		return shapedSpec(kind, build, o, color, d.cabin, if o.beacons == nil then d.beacons else o.beacons)
	end
	local dark = hex("#2b2f33")
	local glass = hex("#5d7480")
	local bodyH = H * (1 - d.cabin)
	local cabinH = H * d.cabin
	local wheelR = math.min(0.3 * H, 1.15)
	local wheelW = math.min(0.6, W * 0.2)
	local bottom = -H / 2
	local beacons = if o.beacons == nil then d.beacons else o.beacons
	local parts: { PartBuilder.PartSpec } = {
		{ name = "RootPart", size = { W, H, L }, pos = { 0, 0, 0 }, color = color, transparency = 1 },
		-- body: the full footprint, from just above the wheel centres to the cabin line
		{
			name = "Body",
			size = { W, bodyH - wheelR * 0.6, L },
			pos = { 0, bottom + wheelR * 0.6 + (bodyH - wheelR * 0.6) / 2, 0 },
			color = color,
		},
		-- cabin: full height to the box top, set back from the nose (-Z is the front)
		{
			name = "Cabin",
			size = { W * 0.92, cabinH, L * d.cabinLen },
			pos = { 0, H / 2 - cabinH / 2, L * (0.5 - d.cabinLen / 2) * 0.35 },
			color = glass,
			transparency = 0.15,
		},
		{
			name = "Headlights",
			size = { W * 0.8, 0.35, 0.1 },
			pos = { 0, bottom + bodyH * 0.65, -L / 2 + 0.04 },
			color = hex("#fff3b5"),
			material = "Neon",
		},
		{
			name = "TailLights",
			size = { W * 0.8, 0.3, 0.1 },
			pos = { 0, bottom + bodyH * 0.65, L / 2 - 0.04 },
			color = hex("#c53227"),
			material = "Neon",
		},
		-- the beacon bar: two bright Neon halves, red on the driver's side and blue (the ambulance:
		-- white) on the other (review 2026-11-09: the old navy bar barely showed); hidden on plain cars
		{
			name = "LightBar",
			size = { W * 0.3, 0.3, 0.5 },
			pos = { -W * 0.15, H / 2 - 0.15, 0 },
			color = hex(BEACON_RED),
			material = if beacons then "Neon" else "SmoothPlastic",
			transparency = if beacons then 0 else 1,
		},
	}
	if beacons then
		table.insert(parts, {
			name = "LightBarB",
			size = { W * 0.3, 0.3, 0.5 },
			pos = { W * 0.15, H / 2 - 0.15, 0 },
			color = hex(if kind == "ambulance" then BEACON_WHITE else BEACON_BLUE),
			material = "Neon",
		})
	end
	local joints: { PartBuilder.JointSpec } = {
		{ name = "BodyWeld", kind = "Weld", part0 = "RootPart", part1 = "Body" },
		{ name = "CabinWeld", kind = "Weld", part0 = "RootPart", part1 = "Cabin" },
		{ name = "HeadlightsWeld", kind = "Weld", part0 = "RootPart", part1 = "Headlights" },
		{ name = "TailLightsWeld", kind = "Weld", part0 = "RootPart", part1 = "TailLights" },
		{ name = "LightBarWeld", kind = "Weld", part0 = "RootPart", part1 = "LightBar" },
	}
	if beacons then
		table.insert(joints, { name = "LightBarBWeld", kind = "Weld", part0 = "RootPart", part1 = "LightBarB" })
	end
	local wx = W / 2 - wheelW / 2
	local wz = L / 2 - math.max(wheelR * 1.3, L * 0.16)
	for _, w in
		{
			{ name = "WheelFL", sx = -1, sz = -1 },
			{ name = "WheelFR", sx = 1, sz = -1 },
			{ name = "WheelBL", sx = -1, sz = 1 },
			{ name = "WheelBR", sx = 1, sz = 1 },
		}
	do
		local name, sx, sz = w.name, w.sx, w.sz
		table.insert(parts, {
			name = name,
			size = { wheelW, wheelR * 2, wheelR * 2 },
			pos = { sx * wx, bottom + wheelR, sz * wz },
			color = dark,
			shape = "Cylinder",
		})
		-- the wheel joint is the spin axis (local X): the procedural backend turns C0 by speed*dt/r
		table.insert(joints, { name = name, kind = "Motor6D", part0 = "RootPart", part1 = name })
	end
	local seatX = if kind == "motorcycle" then 0 else -W * 0.22
	local attachments: { PartBuilder.AttachmentSpec } = {
		{ name = "DriverSeat", part = "RootPart", pos = { seatX, bottom + bodyH, 0 } },
		{ name = "DashSocket", part = "RootPart", pos = { seatX, bottom + bodyH + 0.4, -L * 0.18 } },
		{ name = "EyeSocket", part = "RootPart", pos = { seatX, H / 2 - 0.5, 0.2 } },
	}
	return {
		name = o.name or `Vehicle_{kind}`,
		species = "car",
		primary = "RootPart",
		parts = parts,
		joints = joints,
		attachments = attachments,
		attributes = { VehicleKind = kind, BaseOffset = H / 2, BoxW = W, BoxL = L, BoxH = H },
	}
end

return VehiclePuppet
