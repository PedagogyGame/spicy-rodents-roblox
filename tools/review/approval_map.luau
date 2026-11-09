--!strict
-- tools/review/approval_map.luau: export what the owner's approval map draws (brief v2 §15 decision 18;
-- docs/waves/BATCH2_SPEC.md) to build/review/approval_map.json; tools/review/approval_map.py renders the PNG.
--   the baked town (build/Town.rbxm, build/Attractions.rbxm, build/Backdrop.rbxm: run the bakes first) as XZ boxes
--   by category; the ground (World/Height with the D32 extensions; Backdrop's coast and sea north of NORTH_FROM_Z)
--   on a 25-stud grid; lots, roads, the terrain-extension districts; generated/Expansion (venues, streets, pads,
--   paths, rides, zones, vehicles) as compiled.
-- Usage (repo root): lune run tools/review/approval_map.luau [--out build/review/approval_map.json]
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Backdrop = require("../../src/shared/World/Backdrop")
local Height = require("../../src/shared/World/Height")

local out = "build/review/approval_map.json"
for i, a in process.args do
	if a == "--out" then
		out = process.args[i + 1]
	end
end

local TE = require("../../generated/TerrainExtensions") :: any
Height.configure(TE)
Backdrop.reset()

local function r1(n: number): number
	return math.floor(n * 10 + 0.5) / 10
end

-- category of a baked part from its path (Model names under Workspace.Town / Attractions / Backdrop.Coast)
local function category(path: string, name: string, height: number): string?
	if string.sub(path, 1, 10) == "Town/Roads" then
		return "road"
	elseif string.find(path, "Tree_", 1, true) then
		return if string.sub(name, 1, 6) == "Leaves"
			then "canopy"
			elseif string.sub(name, 1, 5) == "Trunk" then "trunk"
			else nil
	elseif string.find(path, "Town/Props/Pole_", 1, true) then
		return if name == "Pole_1" then "pole" else nil
	elseif string.sub(path, 1, 10) == "Town/Lamps" then
		return nil
	elseif string.sub(path, 1, 12) == "Town/Skyline" then
		return nil
	elseif string.sub(path, 1, 9) == "Town/Lots" then
		return if height > 2 then "building" else "flat"
	elseif string.sub(path, 1, 11) == "Attractions" then
		return "attraction"
	elseif string.sub(path, 1, 14) == "Backdrop/Coast" then
		return "coast"
	end
	return nil
end

local boxes = {}
local function walk(inst: any, path: string, depth: number)
	for _, c in inst:GetChildren() do
		local p = if depth < 3 then path .. "/" .. c.Name else path
		if c:IsA("BasePart") then
			local cf, s = c.CFrame, c.Size
			local rx, uy, lz = cf.RightVector, cf.UpVector, cf.LookVector
			local hx = math.abs(rx.X) * s.X / 2 + math.abs(uy.X) * s.Y / 2 + math.abs(lz.X) * s.Z / 2
			local hz = math.abs(rx.Z) * s.X / 2 + math.abs(uy.Z) * s.Y / 2 + math.abs(lz.Z) * s.Z / 2
			local hy = math.abs(rx.Y) * s.X / 2 + math.abs(uy.Y) * s.Y / 2 + math.abs(lz.Y) * s.Z / 2
			local cat = category(p, c.Name, 2 * hy)
			if cat then
				local pos = cf.Position
				table.insert(
					boxes,
					{ cat, r1(pos.X - hx), r1(pos.Z - hz), r1(pos.X + hx), r1(pos.Z + hz), r1(pos.Y + hy) }
				)
			end
		end
		walk(c, p, depth + 1)
	end
end
for _, file in { "build/Town.rbxm", "build/Attractions.rbxm", "build/Backdrop.rbxm" } do
	if fs.isFile(file) then
		for _, r in roblox.deserializeModel(fs.readFile(file)) do
			walk(r, r.Name, 1)
		end
	else
		print("approval_map: " .. file .. " missing (run the bakes); drawn without it")
	end
end

-- ground grid (studs)
local B = { x0 = -1700, x1 = 4400, z0 = -2000, z1 = 2250, step = 25 }
local heights = {}
local nx = math.floor((B.x1 - B.x0) / B.step) + 1
local nz = math.floor((B.z1 - B.z0) / B.step) + 1
for k = 0, nz - 1 do
	for i = 0, nx - 1 do
		local x, z = B.x0 + i * B.step, B.z0 + k * B.step
		local h = if z >= Backdrop.NORTH_FROM_Z then Backdrop.groundAt(x, z) else Height.at(x, z)
		-- water: the river, and the sea north of the coast rewrite (inland dips below 0, e.g. in the back field, stay dry)
		local water = Height.insideRiverWater(x, z) or (z >= Backdrop.NORTH_FROM_Z and h < Backdrop.SEA_Y - 0.2)
		table.insert(heights, { r1(h), if water then 1 else 0 })
	end
end

local shore = {}
for x = B.x0, B.x1, 50 do
	table.insert(shore, { x, r1(Backdrop.shoreZ(x)) })
end

local doc = {
	bounds = B,
	grid = { nx = nx, nz = nz, cells = heights },
	shore = shore,
	boxes = boxes,
	lots = require("../../generated/Lots"),
	roads = require("../../generated/Roads"),
	extensions = TE,
	attractions = (require("../../generated/Attractions") :: any).attractions,
	expansion = require("../../generated/Expansion"),
}
local dir = string.match(out, "^(.*)/[^/]*$")
if dir and not fs.isDir(dir) then
	fs.writeDir(dir)
end
fs.writeFile(out, serde.encode("json", doc))
print(string.format("approval_map: %d boxes, %d x %d ground cells -> %s", #boxes, nx, nz, out))
Height.configure(nil)
