--!strict
-- tools/review/rides: a lineup review scene of the things the town builds at run time or bakes small (the street
-- riders, the player's vehicles, yard props), straight from the code that builds them, so they can be judged without
-- the game. Nothing here ships.
-- Usage (repo root): lune run tools/review/rides.luau [--out build/review/rides] [--res 1600x620] [--rows N] entry ...
--   rider:<slot>      Server/AI/Puppets.build("human", "rider", 100 + slot, ..., slot): a street rider (1-8)
--   device:<kind>     Shared/Vehicles/Placeholder.build(kind): a player vehicle (car, cart, bike, pickup, suv, jetski)
--   vehicle:<kind>    Shared/Traffic/VehiclePuppet.spec(kind): a traffic vehicle (a motorcycle with its rider)
--   prop:<name>       the first model in build/Town.rbxm whose name contains <name> (run tools/bake/main.luau first)
-- The engine-side builders run on @lune/roblox instances (the engine globals are put in place for them here). Each
-- entry stands on y = 0 (its lowest visible part), facing -Z, in rows; each row gets a front and a rear three-quarter
-- view, framed to its own entries. Writes <out>/scene.json (the tools/review/export.luau part format, group "lineup")
-- and <out>/views.json for tools/review/render.py; tools/review/rides.sh renders and stacks them into one JPEG.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local PartBuilder = require("../../src/shared/Avatar/PartBuilder")
local VehiclePuppet = require("../../src/shared/Traffic/VehiclePuppet")

local out = "build/review/rides"
local res = "1600x620"
local rows: number? = nil
local entries: { string } = {}
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
		table.insert(entries, a)
	end
	i += 1
end
if #entries == 0 then
	error("rides: name at least one entry (rider:1, device:bike, vehicle:motorcycle, prop:kids_bike)")
end
local nRows = math.clamp(rows or 1, 1, #entries)

local lib = {
	Instance = roblox.Instance,
	Vector3 = roblox.Vector3,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	Enum = roblox.Enum,
}

-- the engine globals the server and shared builders look up when they run (a review tool's own process)
local dataModel = roblox.Instance.new("DataModel")
do
	-- selene: allow(deprecated)
	local env = getfenv(0) :: any
	env.Instance = roblox.Instance
	env.Vector3 = roblox.Vector3
	env.CFrame = roblox.CFrame
	env.Color3 = roblox.Color3
	env.Enum = roblox.Enum
	env.game = dataModel
	env.workspace = dataModel:GetService("Workspace")
end

local town: { any }? = nil
local function fromTown(name: string): any
	if town == nil then
		town = roblox.deserializeModel(fs.readFile("build/Town.rbxm"))
	end
	for _, inst in town :: { any } do
		for _, d in inst:GetDescendants() do
			if d:IsA("Model") and string.find(d.Name, name, 1, true) then
				-- placed later in its root part's own frame, like everything else
				local m = d:Clone()
				return m
			end
		end
	end
	error(`rides: no model named like {name} in build/Town.rbxm`)
end

local function build(entry: string): (any, string)
	local what, arg = string.match(entry, "^(%w+):([%w_]+)$")
	if what == "rider" then
		local Puppets = (require :: any)("../../src/server/AI/Puppets")
		local slot = tonumber(arg) or error(`rides: {entry}`)
		local folder = roblox.Instance.new("Folder")
		local rig = Puppets.build("human", "rider", 100 + slot, folder, slot)
		return rig.model, `rider {slot}`
	elseif what == "device" then
		local Placeholder = (require :: any)("../../src/shared/Vehicles/Placeholder")
		return Placeholder.build(arg), `{arg} (player)`
	elseif what == "vehicle" then
		-- a motorcycle carries its rider, as the traffic draws it (Traffic/Ghost: Morgan Rider)
		local rider = if arg == "motorcycle" then 7 else nil
		return PartBuilder.instantiate(VehiclePuppet.spec(arg :: string, { rider = rider }), lib), arg :: string
	elseif what == "prop" then
		return fromTown(arg :: string), arg :: string
	end
	error(`rides: unknown entry {entry}`)
end

local function r4(n: number): number
	return math.floor(n * 1e4 + 0.5) / 1e4
end

-- the visible parts' box in the model's root frame (min, max)
local function extent(model: any): (any, any, number)
	local root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	local lo = roblox.Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	local n = 0
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p.Transparency < 0.95 then
			n += 1
			local cf, s = root.CFrame:ToObjectSpace(p.CFrame), p.Size
			local x, y, z = cf.XVector, cf.YVector, cf.ZVector
			local h = roblox.Vector3.new(
				(math.abs(x.X) * s.X + math.abs(y.X) * s.Y + math.abs(z.X) * s.Z) / 2,
				(math.abs(x.Y) * s.X + math.abs(y.Y) * s.Y + math.abs(z.Y) * s.Z) / 2,
				(math.abs(x.Z) * s.X + math.abs(y.Z) * s.Y + math.abs(z.Z) * s.Z) / 2
			)
			lo = lo:Min(cf.Position - h)
			hi = hi:Max(cf.Position + h)
		end
	end
	return lo, hi, n
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
				s = if p.ClassName == "WedgePart" then "Wedge" elseif p:IsA("Part") then p.Shape.Name else "Box",
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

-- Built once, measured, then placed per view (front and rear).
type Item = { entry: string, label: string, lo: any, hi: any, n: number, total: number }
local items: { Item } = {}
for _, e in entries do
	local m, label = build(e)
	local lo, hi, n = extent(m)
	local total = 0
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			total += 1
		end
	end
	table.insert(items, { entry = e, label = label, lo = lo, hi = hi, n = n, total = total })
end

-- The camera looks along (-sin A, cos A) in (x, z): from the entries' right and front (tools/review/vehicles.luau's
-- framing, before it was dropped).
local ANGLE = math.rad(38)
local ROW = math.rad(22)
local SKEW = math.cos(ANGLE - ROW)
local ax, az = math.cos(ROW), math.sin(ROW)
local resW, resH = string.match(res, "^(%d+)x(%d+)$")
local aspect = (tonumber(resW) or 1600) / (tonumber(resH) or 620)
local FOV = 17
local tanV = math.tan(math.rad(FOV / 2))

local views: { any } = {}
local perRow = math.ceil(#items / nRows)
local place = 0
for row = 1, nRows do
	local group: { Item } = {}
	for k = (row - 1) * perRow + 1, math.min(row * perRow, #items) do
		table.insert(group, items[k])
	end
	local widths, total, tallest = {}, 0, 0
	local gap = 1.6
	for k, it in group do
		local w, l = it.hi.X - it.lo.X, it.hi.Z - it.lo.Z
		widths[k] = w * math.cos(ANGLE) + l * math.sin(ANGLE)
		total += widths[k] + (if k > 1 then gap else 0)
		tallest = math.max(tallest, it.hi.Y - it.lo.Y)
	end
	for _, turned in { false, true } do
		place += 1
		local originZ = -400 * (place - 1)
		local cursor = total / 2
		for k, it in group do
			local s = (cursor - widths[k] / 2) / SKEW
			cursor -= widths[k] + gap
			local m = build(it.entry)
			local root = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart", true)
			local centre = (it.lo + it.hi) / 2
			-- the entry's middle over the spot, its lowest visible part on the ground
			local cf = roblox.CFrame.new(s * ax, -it.lo.Y, originZ + s * az)
			if turned then
				cf *= roblox.CFrame.Angles(0, math.pi, 0)
			end
			cf *= roblox.CFrame.new(-centre.X, 0, -centre.Z)
			local base = root.CFrame
			for _, p in m:GetDescendants() do
				if p:IsA("BasePart") then
					p.CFrame = cf * base:ToObjectSpace(p.CFrame)
				end
			end
			emit(m, `{it.label}_{place}`)
			local size = math.clamp(total * 0.02, 0.35, 1.4)
			table.insert(labels, {
				text = `{it.label}\n{it.n} parts`,
				pos = { r4(s * ax), r4(tallest + 0.4 + size * 1.1), r4(originZ + s * az) },
				size = r4(size),
			})
		end
		local dist = math.max((total * 1.14 + 3) / 2 / (tanV * aspect), (tallest * 1.6 + 2.5) / 2 / tanV)
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
			ground = { y = 0, minX = -80, maxX = 80, minZ = -400 * place, maxZ = 60 },
			labels = labels,
		},
	}, false)
)
fs.writeFile(
	`{out}/views.json`,
	serde.encode("json", {
		about = "generated by tools/review/rides.luau",
		defaults = {
			res = res,
			samples = tonumber(process.env.REVIEW_SAMPLES) or 40,
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
for _, it in items do
	print(`rides: {it.entry}: {it.n} visible parts ({it.total} with the root and hidden parts)`)
end
print(`rides: {#parts} visible parts in {#views} views -> {out}/scene.json, views.json`)
