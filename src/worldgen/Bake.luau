--!strict
-- ServerScriptService.Server.WorldGen.Bake
-- Entry point: walks lots and roads in data order, plans them (Plan), builds them (Builders), and
-- stamps BakeHash (D6, spike S6). The same code runs in Lune (tools/bake -> build/Town.rbxm) and
-- in the engine (tests/engine/WorldBuild, BakeParity).
-- Interface (BUILD_PLAN §1.4, D6):
--   run(data, factory) -> Town Model     data = { lots = generated Lots, roads = generated Roads }
--   plans(data) -> { BuildPlan }; hash(plans) -> hex; instanceHash(town) -> hex
-- BakeHash hashes the plan with every number rounded to 1e-3 studs, so libm ulp differences
-- between Lune and the engine cannot flip it. InstanceHash hashes the built Instances' structure
-- (paths, classes, colours, materials, flags, LOD, streaming, attributes): exact in both runtimes.
-- Geometry (Size, CFrame) is float32 and rounds differently in each runtime (measured in S6: 131 of
-- 2,128 lines flip at a 1e-2 grid), so it is compared with a tolerance instead: geometry(town)
-- returns path -> 10 numbers and maxGeometryDelta(a, b) the worst difference.

local Factory = require("./Factory")
local Greybox = require("./Builders/Greybox")
local Plan = require("./Plan")
local RoadBuilder = require("./Builders/Road")

local Bake = {}

Bake.VERSION = 1

export type Data = { lots: { Plan.Lot }, roads: { Plan.Road } }

function Bake.plans(data: Data): { Plan.BuildPlan }
	local parents = Plan.containment(data.lots)
	local out: { Plan.BuildPlan } = {}
	for _, lot in data.lots do
		table.insert(out, Plan.plan(lot, lot.type, { parentId = parents[lot.id] }))
	end
	Plan.attachSlabs(out)
	for _, road in data.roads do
		table.insert(out, Plan.road(road))
	end
	return out
end

-- FNV-1a, two 32-bit lanes (different offset bases), exact in doubles.
local function fnv(s: string): string
	local h1, h2 = 2166136261, 3735928559
	for i = 1, #s do
		local b = string.byte(s, i)
		h1 = bit32.bxor(h1, b)
		h1 = (bit32.lshift(h1, 24) + h1 * 403) % 4294967296
		h2 = bit32.bxor(h2, b)
		h2 = (bit32.lshift(h2, 24) + h2 * 403) % 4294967296
	end
	return string.format("%08x%08x", h1, h2)
end
Bake.fnv = fnv

local function q(n: number, fmt: string): string
	local s = string.format(fmt, n)
	if s == string.format(fmt, -0.0) and n <= 0 then
		-- "-0.000" and "0.000" are the same value
		s = string.format(fmt, 0)
	end
	return s
end

local function attrString(v: any, fmt: string): string
	if type(v) == "number" then
		return q(v, fmt)
	end
	return tostring(v)
end

function Bake.serialize(plans: { Plan.BuildPlan }): string
	local lines: { string } = {}
	for _, p in plans do
		local keys: { string } = {}
		for k in p.attributes do
			table.insert(keys, k)
		end
		table.sort(keys)
		local attrs: { string } = {}
		for _, k in keys do
			table.insert(attrs, k .. "=" .. attrString(p.attributes[k], "%.3f"))
		end
		table.insert(lines, `{p.kind}|{p.id}|{p.category}|{p.lod}|{p.streaming}|{table.concat(attrs, ",")}`)
		for _, s in p.parts do
			table.insert(
				lines,
				table.concat({
					" " .. s.name,
					q(s.cx, "%.3f"),
					q(s.cy, "%.3f"),
					q(s.cz, "%.3f"),
					q(s.yaw, "%.4f"),
					q(s.pitch, "%.4f"),
					q(s.sx, "%.3f"),
					q(s.sy, "%.3f"),
					q(s.sz, "%.3f"),
					`{s.color[1]},{s.color[2]},{s.color[3]}`,
					s.material,
					tostring(s.canCollide),
					q(s.transparency, "%.2f"),
				}, "|")
			)
		end
	end
	return table.concat(lines, "\n")
end

function Bake.hash(plans: { Plan.BuildPlan }): string
	return fnv(Bake.serialize(plans))
end

function Bake.run(data: Data, factory: Factory.Factory): any
	local plans = Bake.plans(data)
	local town = factory.instance("Model", "Town")
	local lotsFolder = factory.instance("Folder", "Lots")
	local roadsFolder = factory.instance("Folder", "Roads")
	local lotCount, roadCount, partCount = 0, 0, 0
	for _, p in plans do
		if p.kind == "lot" then
			Greybox.build(p, factory).Parent = lotsFolder
			lotCount += 1
		else
			RoadBuilder.build(p, factory).Parent = roadsFolder
			roadCount += 1
		end
		partCount += #p.parts
	end
	lotsFolder.Parent = town
	roadsFolder.Parent = town
	town:SetAttribute("BakeHash", Bake.hash(plans))
	town:SetAttribute("BakeVersion", Bake.VERSION)
	town:SetAttribute("LotCount", lotCount)
	town:SetAttribute("RoadCount", roadCount)
	town:SetAttribute("PartCount", partCount)
	town:SetAttribute("InstanceHash", Bake.instanceHash(town))
	return town
end

-- Structural hash of the built Instances (engine or Lune): one line per BasePart / Model, sorted.
-- Town's own attributes are excluded (InstanceHash is stored there).
function Bake.instanceHash(town: any): string
	return fnv(table.concat(Bake.instanceLines(town), "\n"))
end

function Bake.instanceLines(town: any): { string }
	local lines: { string } = {}
	local function walk(inst: any, path: string)
		for _, child in inst:GetChildren() do
			local p = path .. "/" .. child.Name
			if child:IsA("BasePart") then
				local c = child.Color
				table.insert(
					lines,
					table.concat({
						p,
						child.ClassName,
						`{math.floor(c.R * 255 + 0.5)},{math.floor(c.G * 255 + 0.5)},{math.floor(c.B * 255 + 0.5)}`,
						child.Material.Name,
						tostring(child.CanCollide),
						tostring(child.Anchored),
						q(child.Transparency, "%.2f"),
					}, "|")
				)
			elseif child:IsA("Model") then
				local keys: { string } = {}
				local attrs = child:GetAttributes()
				for k in attrs do
					table.insert(keys, k)
				end
				table.sort(keys)
				local parts: { string } = {}
				for _, k in keys do
					table.insert(parts, k .. "=" .. attrString(attrs[k], "%.2f"))
				end
				table.insert(
					lines,
					`{p}|{child.LevelOfDetail.Name}|{child.ModelStreamingMode.Name}|{table.concat(parts, ",")}`
				)
			end
			walk(child, p)
		end
	end
	walk(town, "Town")
	table.sort(lines)
	return lines
end

-- Geometry of every BasePart under `town`: path -> { size xyz, position xyz, look xyz, up.Y }.
function Bake.geometry(town: any): { [string]: { number } }
	local out: { [string]: { number } } = {}
	local function walk(inst: any, path: string)
		for _, child in inst:GetChildren() do
			local p = path .. "/" .. child.Name
			if child:IsA("BasePart") then
				local cf, sz = child.CFrame, child.Size
				local look = cf.LookVector
				out[p] = {
					sz.X,
					sz.Y,
					sz.Z,
					cf.Position.X,
					cf.Position.Y,
					cf.Position.Z,
					look.X,
					look.Y,
					look.Z,
					cf.UpVector.Y,
				}
			end
			walk(child, p)
		end
	end
	walk(town, "Town")
	return out
end

-- Worst absolute difference between two geometry maps (math.huge if a path is missing on either side).
function Bake.maxGeometryDelta(a: { [string]: { number } }, b: { [string]: { number } }): (number, string?)
	local worst, at = 0, nil
	for path, va in a do
		local vb = b[path]
		if not vb then
			return math.huge, path
		end
		for i = 1, #va do
			local d = math.abs(va[i] - vb[i])
			if d > worst then
				worst, at = d, path
			end
		end
	end
	for path in b do
		if not a[path] then
			return math.huge, path
		end
	end
	return worst, at
end

return Bake
