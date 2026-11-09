--!strict
-- ReplicatedStorage.Shared.Traffic.VehiclePuppet
-- Placeholder vehicles at the TRUE logical boxes (BUILD_PLAN §4.4 W1 #9 and #10, D9, §5.2).
-- Interface: spec(kind, opts?) -> PartBuilder.ModelSpec; KINDS; baseOffset(kind) (root centre above the base)
--
-- The invisible RootPart is exactly the logical box from Traffic/Boxes (the box the fatal test sweeps), and
-- the visible body plus cabin fill the same envelope, so a player never dies to a car that looks smaller.
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

function VehiclePuppet.spec(kind: string, opts: Opts?): PartBuilder.ModelSpec
	local o: Opts = opts or {}
	local d = DEFAULTS[kind] or error(`VehiclePuppet: unknown kind {kind}`)
	local b = Boxes.get(kind)
	local W, L, H = b.width, b.length, b.height
	local color = hex(o.color or d.color)
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
