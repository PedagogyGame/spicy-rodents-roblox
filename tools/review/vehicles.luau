--!strict
-- tools/review/vehicles: a vehicles-only review scene straight from Traffic/VehiclePuppet (no bake, no .rbxm),
-- so a vehicle can be judged without the game. Nothing here ships.
-- Usage (repo root): lune run tools/review/vehicles.luau [--out build/review/vehicles] [--res 1600x620]
--   [--rows N] [kind[:#rrggbb] ...]      default: every kind, in two rows
-- Writes <out>/scene.json (the tools/review/export.luau part format, group "lineup") and <out>/views.json for
-- tools/review/render.py. The kinds are dealt into N rows in the order given; each row gets two views,
-- `front_<n>` (front three-quarter) and `rear_<n>` (rear three-quarter, the same vehicles turned about, 800 st
-- away). A row stands nearly square to its camera and is framed to its own vehicles, so a row of
-- motorcycles is drawn larger than a row of trolleys. Both cameras look from the vehicles' right with the
-- review sun on the faces they see. tools/review/vehicles.sh renders the views and stacks them into one JPEG.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local PartBuilder = require("../../src/shared/Avatar/PartBuilder")
local VehiclePuppet = require("../../src/shared/Traffic/VehiclePuppet")
local Boxes = require("../../src/shared/Traffic/Boxes")

local out = "build/review/vehicles"
local res = "1600x620"
local rows: number? = nil
local entries: { { kind: string, color: string? } } = {}
local i = 1
while i <= #process.args do
	local a = process.args[i]
	if a == "--out" then
		out = process.args[i + 1]
		i += 1
	elseif a == "--res" then
		res = process.args[i + 1]
		i += 1
	elseif a == "--rows" then
		rows = tonumber(process.args[i + 1]) or error("--rows needs a number")
		i += 1
	else
		local kind, color = string.match(a, "^([%w_]+):(#%x+)$")
		table.insert(entries, { kind = kind or a, color = color })
	end
	i += 1
end
if #entries == 0 then
	-- the most seen first; the sedan in a fleet colour
	entries = {
		{ kind = "sedan", color = "#6d7f8f" },
		{ kind = "patrol_car" },
		{ kind = "ambulance" },
		{ kind = "cart" },
		{ kind = "motorcycle" },
		{ kind = "delivery_van" },
		{ kind = "ice_cream_van" },
		{ kind = "rv" },
		{ kind = "dump_truck" },
		{ kind = "trolley" },
	}
	rows = rows or 2
end
local nRows = math.clamp(rows or 1, 1, #entries)

local lib = {
	Instance = roblox.Instance,
	Vector3 = roblox.Vector3,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	Enum = roblox.Enum,
}

local function r4(n: number): number
	return math.floor(n * 1e4 + 0.5) / 1e4
end

local parts: { any } = {}
local labels: { any } = {}

local function emit(model: any, path: string)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p.Transparency < 0.95 then
			local cf = p.CFrame
			local x, y, z = cf.XVector, cf.YVector, cf.ZVector
			table.insert(parts, {
				g = "lineup",
				p = `{path}.{p.Name}`,
				s = if p.ClassName == "WedgePart" then "Wedge" else p.Shape.Name,
				size = { r4(p.Size.X), r4(p.Size.Y), r4(p.Size.Z) },
				pos = { r4(cf.Position.X), r4(cf.Position.Y), r4(cf.Position.Z) },
				rot = { r4(x.X), r4(y.X), r4(z.X), r4(x.Y), r4(y.Y), r4(z.Y), r4(x.Z), r4(y.Z), r4(z.Z) },
				c = {
					math.floor(p.Color.R * 255 + 0.5),
					math.floor(p.Color.G * 255 + 0.5),
					math.floor(p.Color.B * 255 + 0.5),
				},
				t = p.Transparency,
				m = p.Material.Name,
			})
		end
	end
end

-- The camera looks along (-sin A, cos A) in (x, z): from the vehicles' right and front. A row runs 16
-- degrees short of the perpendicular (cos A, sin A): square to the camera, each car's glossy side glass
-- mirrors its neighbour's lamps into the picture as a coloured blot.
local ANGLE = math.rad(38)
local ROW = math.rad(22)
local SKEW = math.cos(ANGLE - ROW)
local ax, az = math.cos(ROW), math.sin(ROW)
local resW, resH = string.match(res, "^(%d+)x(%d+)$")
local aspect = (tonumber(resW) or 1600) / (tonumber(resH) or 620)
local FOV = 17 -- vertical, degrees
local tanV = math.tan(math.rad(FOV / 2))

local views: { any } = {}
local perRow = math.ceil(#entries / nRows)
local place = 0
for row = 1, nRows do
	local group = {}
	for k = (row - 1) * perRow + 1, math.min(row * perRow, #entries) do
		table.insert(group, entries[k])
	end
	-- how wide each vehicle stands across the camera's view, and the row's width and height
	local widths, total, tallest = {}, 0, 0
	for k, e in group do
		local b = Boxes.get(e.kind)
		widths[k] = b.width * math.cos(ANGLE) + b.length * math.sin(ANGLE)
		total += widths[k] + (if k > 1 then 2.2 else 0)
		tallest = math.max(tallest, b.height)
	end
	for _, turned in { false, true } do
		place += 1
		local originZ = -800 * (place - 1)
		-- +s along the row is the camera's left: the first kind stands at the left of the picture
		local cursor = total / 2
		for k, e in group do
			local s = (cursor - widths[k] / 2) / SKEW
			cursor -= widths[k] + 2.2
			local spec = VehiclePuppet.spec(e.kind, { color = e.color, name = `{e.kind}_{place}` })
			local base = VehiclePuppet.baseOffset(e.kind)
			local cf = lib.CFrame.new(s * ax, base, originZ + s * az)
			if turned then
				cf *= lib.CFrame.Angles(0, math.pi, 0)
			end
			emit(PartBuilder.instantiate(spec, lib, cf), spec.name)
			-- two short lines, so the label of a narrow vehicle does not run into its neighbour's
			local size = math.clamp(total * 0.019, 0.45, 1.5)
			table.insert(labels, {
				text = `{e.kind}\n{PartBuilder.partCount(spec)} parts`,
				pos = { r4(s * ax), r4(base * 2 + 0.6 + tallest * 0.08 + size * 1.1), r4(originZ + s * az) },
				size = r4(size),
			})
		end
		-- far enough for the row's width and for its tallest vehicle under its label; the left end of
		-- the row is the nearer one and spreads wider in the frame, so the camera aims a little left
		local dist = math.max((total * 1.14 + 3) / 2 / (tanV * aspect), (tallest * 1.5 + 2.5) / 2 / tanV)
		local aim = total * 0.045 / SKEW
		table.insert(views, {
			name = `{if turned then "rear" else "front"}_{row}`,
			desc = if turned then "rear three-quarter" else "front three-quarter",
			pos = {
				r4(aim * ax + math.sin(ANGLE) * dist),
				r4(dist * 0.3),
				r4(originZ + aim * az - math.cos(ANGLE) * dist),
			},
			look = { r4(aim * ax), r4(tallest * 0.55), r4(originZ + aim * az) },
			fov = FOV,
			groups = { "lineup", "lineup_ground" },
		})
	end
end

if not fs.isDir(out) then
	fs.writeDir(out)
end
fs.writeFile(
	`{out}/scene.json`,
	serde.encode("json", {
		version = 1,
		units = "studs, Roblox axes (Y up, -Z forward)",
		parts = parts,
		beams = {},
		lineup = {
			ground = { y = 0, minX = -120, maxX = 120, minZ = -800 * place, maxZ = 80 },
			labels = labels,
		},
	}, false)
)
fs.writeFile(
	`{out}/views.json`,
	serde.encode("json", {
		about = "generated by tools/review/vehicles.luau",
		defaults = {
			res = res,
			samples = tonumber(process.env.REVIEW_SAMPLES) or 48,
			groups = { "lineup", "lineup_ground" },
		},
		sun = {
			dir = { 0.7, 0.55, -0.45 },
			strength = 3.6,
			color = { 1.0, 0.9, 0.78 },
			angleDeg = 1.5,
			skyStrength = 1.0,
		},
		views = views,
	}, true)
)
print(`vehicles: {#parts} visible parts, {#entries} vehicles in {nRows} row(s) -> {out}/scene.json, views.json`)
