--!strict
-- ServerScriptService.Server.WorldGen.Bake
-- Entry point: walks lots and roads in data order, plans them (Plan), builds them (Builders), and
-- stamps BakeHash (D6, spike S6). The same code runs in Lune (tools/bake -> build/Town.rbxm) and
-- in the engine (tests/engine/WorldBuild, BakeParity).
-- Interface (BUILD_PLAN §1.4, D6):
--   run(data, factory) -> Town Model     data = { lots = generated Lots, roads = generated Roads }
--   plans(data) -> { BuildPlan }; hash(plans) -> hex; instanceHash(town) -> hex
-- BakeHash hashes the plan with every number rounded to 1e-3 studs, so libm ulp differences
-- between Lune and the engine cannot flip it; InstanceHash hashes the built Instances (what the
-- .rbxm round trip must preserve) at 1e-2 studs.

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

-- Hash of the built Instances (engine or Lune): one line per BasePart / Model, sorted by path.
-- Town's own attributes are excluded (InstanceHash is stored there).
function Bake.instanceHash(town: any): string
	local lines: { string } = {}
	local function walk(inst: any, path: string)
		for _, child in inst:GetChildren() do
			local p = path .. "/" .. child.Name
			if child:IsA("BasePart") then
				local cf = child.CFrame
				local look, up = cf.LookVector, cf.UpVector
				local c = child.Color
				table.insert(
					lines,
					table.concat({
						p,
						q(child.Size.X, "%.2f"),
						q(child.Size.Y, "%.2f"),
						q(child.Size.Z, "%.2f"),
						q(cf.Position.X, "%.2f"),
						q(cf.Position.Y, "%.2f"),
						q(cf.Position.Z, "%.2f"),
						q(look.X, "%.3f"),
						q(look.Y, "%.3f"),
						q(look.Z, "%.3f"),
						q(up.Y, "%.3f"),
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
	return fnv(table.concat(lines, "\n"))
end

return Bake
