--!strict
-- ReplicatedStorage.Shared.Traffic.VehiclePuppet
-- Placeholder vehicles at the TRUE logical boxes (BUILD_PLAN §4.4 W1 #9 and #10, D9, §5.2).
-- Interface: spec(kind, opts?) -> PartBuilder.ModelSpec; KINDS; baseOffset(kind) (root centre above the base); length(kind), width(kind), track(kind)
--
-- The invisible RootPart is exactly the logical box from Traffic/Boxes (the box the fatal test sweeps), and
-- the visible body plus cabin fill the same envelope, so a player never dies to a car that looks smaller.
-- The sedan and the patrol car are SHAPED (owner 2026-11-11: "the vehicles are extremely rough"): a car
-- from under forty plain parts, no meshes (sedanParts below; the way worldgen/Builders/Fixtures shapes a
-- building). The other eight kinds are still the ten-block placeholder and follow the same recipe.
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

-- Kinds drawn by sedanParts instead of the ten-block placeholder.
local SHAPED: { [string]: boolean } = { sedan = true, patrol_car = true }

-- The shaped saloon body (sedan, patrol car): every visible part inside the W x H x L box, with the
-- bumpers, wheels, mirrors and roof touching its faces so the car fills it. Heights are studs above the
-- ground (the box bottom); lengths run along Z with the nose at -L/2; tuned for the 5.9 x 5.1 x 11.1 box.
-- Several parts run THROUGH the body and show only at their two ends (wheel arches, hub caps, side glass,
-- door seams, mirrors): one part draws the left and the right of the car, which is what keeps
-- a whole car under forty parts. Returns the visible parts; shapedSpec welds all but the wheels to the root.
-- Also returns the station (Z) of the middle of the roof, where a beacon bar goes.
local function sedanParts(W: number, L: number, H: number, color: PartBuilder.Rgb): ({ PartBuilder.PartSpec }, number)
	local hw, hl, bottom = W / 2, L / 2, -H / 2
	local trim, seam, glass, chrome = hex(FIXED.trim), hex(FIXED.seam), hex(FIXED.glass), hex(FIXED.chrome)
	local parts: { PartBuilder.PartSpec } = {}
	-- a box from its extents: half-width in X, y0..y1 above the ground, z0..z1
	local function add(
		name: string,
		halfX: number,
		y0: number,
		y1: number,
		z0: number,
		z1: number,
		c: PartBuilder.Rgb
	): PartBuilder.PartSpec
		local p: PartBuilder.PartSpec = {
			name = name,
			size = { halfX * 2, y1 - y0, z1 - z0 },
			pos = { 0, bottom + (y0 + y1) / 2, (z0 + z1) / 2 },
			color = c,
		}
		table.insert(parts, p)
		return p
	end
	-- a cylinder across the car (axis X) of radius r, its centre y above the ground at station z
	local function across(
		name: string,
		halfX: number,
		r: number,
		y: number,
		z: number,
		c: PartBuilder.Rgb
	): PartBuilder.PartSpec
		local p: PartBuilder.PartSpec = {
			name = name,
			size = { halfX * 2, r * 2, r * 2 },
			pos = { 0, bottom + y, z },
			color = c,
			shape = "Cylinder",
		}
		table.insert(parts, p)
		return p
	end

	-- an upright cylinder of radius r (a rounded corner in plan) from y0 to y1 above the ground
	local function upright(name: string, x: number, z: number, r: number, y0: number, y1: number, c: PartBuilder.Rgb)
		table.insert(parts, {
			name = name,
			size = { y1 - y0, r * 2, r * 2 },
			pos = { x, bottom + (y0 + y1) / 2, z },
			roll = math.pi / 2,
			color = c,
			shape = "Cylinder",
		})
	end

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

	-- lower body: one full-width slab between the rounded ends. In front of it a lower, narrower nose
	-- block with a rounded top edge, an upright cylinder at each corner and a ball where the two rounds
	-- meet; behind it the tail block and its two corners up to the boot lid. On top the bonnet rises
	-- from the nose to the windscreen foot, and the deck (scuttle, shoulders and boot lid) runs at belt
	-- height to the tail.
	add("Body", bw, sill, waist, -ends + R, ends - R, color)
	add("Nose", bw - R, sill, waist - R, -ends, -ends + R, color)
	across("NoseEdge", bw - R, R, waist - R, -ends + R, color)
	add("Tail", bw - R, sill, belt, ends - R, ends, color)
	add("Bonnet", bw, waist, belt, -ends + R, screen0, color).shape = "Wedge"
	add("Deck", bw, waist, belt, screen0, ends - R, color)
	for _, sx in { -1, 1 } do
		local side = if sx < 0 then "L" else "R"
		upright(`CornerF{side}`, sx * (bw - R), -ends + R, R, sill, waist - R, color)
		table.insert(parts, {
			name = `Fender{side}`,
			size = { R * 2, R * 2, R * 2 },
			pos = { sx * (bw - R), bottom + waist - R, -ends + R },
			color = color,
			shape = "Ball",
		})
		upright(`CornerB{side}`, sx * (bw - R), ends - R, R, sill, belt, color)
	end

	-- cabin: a painted box under the roof between two glass wedges (the raked windscreen, and the rear
	-- window turned about), side glass and a centre pillar let through it, a low crown on the roof
	add("Cabin", cw, belt, roof, screen1, rear1, color)
	local screen = add("Windscreen", cw, belt, roof, screen0, screen1, glass)
	screen.shape, screen.material = "Wedge", "Glass"
	local rear = add("RearWindow", cw, belt, roof, rear1, rear0, glass)
	rear.shape, rear.material, rear.yaw = "Wedge", "Glass", math.pi
	add("SideGlass", cw + 0.04, belt + 0.12, roof - 0.4, screen1 + 0.28, rear1 - 0.28, glass).material = "Glass"
	local pillarZ = screen1 + (rear1 - screen1) * 0.45
	add("PillarB", cw + 0.07, belt, roof, pillarZ - 0.13, pillarZ + 0.13, color)
	add("Roof", cw - 0.25, roof, roof + 0.15, screen1 + 0.15, rear1 - 0.15, color)
	add("Mirrors", hw, belt + 0.12, belt + 0.46, screen1 - 0.2, screen1 + 0.06, color)

	-- running gear: a dark arch disc on each flank (one cylinder through the body per axle), a little
	-- larger than the tyre and centred above it, and one bright axle whose ends are the hub caps
	for _, a in { { tag = "F", z = -axleZ }, { tag = "B", z = axleZ } } do
		across(`Arch{a.tag}`, bw + 0.03, archR, archR, a.z, hex(FIXED.arch))
		across(`Hubs{a.tag}`, hw, 0.5, wheelR, a.z, chrome).material = "Metal"
	end
	for _, w in
		{
			{ name = "WheelFL", sx = -1, sz = -1 },
			{ name = "WheelFR", sx = 1, sz = -1 },
			{ name = "WheelBL", sx = -1, sz = 1 },
			{ name = "WheelBR", sx = 1, sz = 1 },
		}
	do
		table.insert(parts, {
			name = w.name,
			size = { wheelW, wheelR * 2, wheelR * 2 },
			pos = { w.sx * (hw - 0.05 - wheelW / 2), bottom + wheelR, w.sz * axleZ },
			color = hex(FIXED.tyre),
			shape = "Cylinder",
		})
	end

	-- trim: bumpers out to the box faces, a sill between the arches and two door seams (each seam one
	-- part through the body: the front door's leading edge and the pillar; the rear door ends at its arch)
	add("BumperF", bw + 0.06, sill - 0.05, 1.12, -hl, -ends + 0.45, trim)
	add("BumperB", bw + 0.06, sill - 0.05, 1.12, ends - 0.45, hl, trim)
	add("Sill", bw + 0.04, sill, sill + 0.28, -axleZ + archR, axleZ - archR, trim)
	for i, z in { -axleZ + archR + 0.14, pillarZ } do
		add(`Seam{i}`, bw + 0.03, sill + 0.28, belt - 0.04, z - 0.035, z + 0.035, seam)
	end

	-- face and tail: a lit strip across each end with its middle covered (the grille; the boot panel and
	-- the number plate), which leaves a PAIR of lamps from one part and keeps RigSpec's two names
	local lamp = bw - R - 0.04
	local head = add("Headlights", lamp, 1.28, 1.86, -ends - 0.05, -ends + 0.05, hex(FIXED.head))
	head.material = "Neon"
	add("Grille", lamp - 0.95, 1.24, 1.9, -ends - 0.09, -ends + 0.05, seam)
	local tail = add("TailLights", lamp, 1.82, 2.34, ends - 0.05, ends + 0.05, hex(FIXED.tail))
	tail.material = "Neon"
	add("BootPanel", lamp - 0.9, 1.78, 2.38, ends - 0.05, ends + 0.09, color)
	add("Plate", 0.75, 1.24, 1.66, ends - 0.05, ends + 0.06, hex(FIXED.plate))
	return parts, (screen1 + rear1) / 2
end

-- The whole shaped model: the invisible root at the logical box, the saloon body, the beacon bar on the
-- roof (hidden on a plain car, as on the placeholders) and the same sockets as the placeholder had.
local function shapedSpec(
	kind: string,
	o: Opts,
	color: PartBuilder.Rgb,
	cabin: number,
	beacons: boolean
): PartBuilder.ModelSpec
	local box = Boxes.get(kind)
	local W, L, H = box.width, box.length, box.height
	local bottom = -H / 2
	local parts: { PartBuilder.PartSpec } = {
		{ name = "RootPart", size = { W, H, L }, pos = { 0, 0, 0 }, color = color, transparency = 1 },
	}
	local joints: { PartBuilder.JointSpec } = {}
	local body, roofZ = sedanParts(W, L, H, color)
	for _, p in body do
		table.insert(parts, p)
	end
	local bar = { { name = "LightBar", sx = -1, color = BEACON_RED } }
	if beacons then
		table.insert(bar, { name = "LightBarB", sx = 1, color = BEACON_BLUE })
	end
	for _, half in bar do
		table.insert(parts, {
			name = half.name,
			size = { W * 0.3, 0.3, 0.5 },
			pos = { half.sx * W * 0.15, H / 2 - 0.15, roofZ },
			color = hex(half.color),
			material = if beacons then "Neon" else "SmoothPlastic",
			transparency = if beacons then 0 else 1,
		})
	end
	for i = 2, #parts do
		local name = parts[i].name
		if string.sub(name, 1, 5) == "Wheel" then
			-- the wheel joint is the spin axis (local X), as on the placeholders
			table.insert(joints, { name = name, kind = "Motor6D", part0 = "RootPart", part1 = name })
		else
			table.insert(joints, { name = `{name}Weld`, kind = "Weld", part0 = "RootPart", part1 = name })
		end
	end
	local seatX, bodyH = -W * 0.22, H * (1 - cabin)
	return {
		name = o.name or `Vehicle_{kind}`,
		species = "car",
		primary = "RootPart",
		parts = parts,
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
	if SHAPED[kind] then
		return shapedSpec(kind, o, color, d.cabin, if o.beacons == nil then d.beacons else o.beacons)
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
