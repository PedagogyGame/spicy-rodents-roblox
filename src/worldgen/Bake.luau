--!strict
-- ServerScriptService.Server.WorldGen.Bake
-- Entry point: walks lots and roads in data order, plans them (Plan and the builder families), adds
-- the route props (trees, poles, wires, pipes, fences), street lamps (LampPlan) and the Skyline
-- layer, builds them (Builders/Greybox) and stamps BakeHash (D6, spike S6, W1 #7). The same code
-- runs in Lune (tools/bake -> build/Town.rbxm) and in the engine (tests/engine/WorldBuild, BakeParity).
-- Interface (BUILD_PLAN §1.4, D6):
--   data() -> Data (every generated module the bake reads, via Import.generated)
--   run(data, factory) -> Town Model     data = { lots, roads, routes?, lighting? }
--   plans(data) -> { BuildPlan }; hash(plans) -> hex; instanceHash(town) -> hex
-- BakeHash hashes the plan with every number rounded to 1e-3 studs, so libm ulp differences
-- between Lune and the engine cannot flip it. InstanceHash hashes the built Instances' structure
-- (paths, classes, colours, materials, flags incl. CanQuery, LOD, streaming, attributes, PointLight
-- range and brightness): exact in both runtimes. Town carries LightCount (PointLights baked).
-- Geometry (Size, CFrame) is float32 and rounds differently in each runtime (measured in S6: 131 of
-- 2,128 lines flip at a 1e-2 grid), so it is compared with a tolerance instead: geometry(town)
-- returns path -> 10 numbers and maxGeometryDelta(a, b) the worst difference.

local Facade = require("./Builders/Facade")
local Factory = require("./Factory")
local Greybox = require("./Builders/Greybox")
local Import = require("./Import")
local Kits = require("./Kits")
local LampPlan = require("./LampPlan")
local Plan = require("./Plan")
local RoadBuilder = require("./Builders/Road")
local RouteProps = require("./Builders/RouteProps")
local Skyline = require("./Skyline")
local Surface = require("./Surface")
local Yield = require("./Yield")
local Curve = Import.shared("Routes/Curve") :: typeof(require("../shared/Routes/Curve"))
local Height = Import.shared("World/Height") :: typeof(require("../shared/World/Height"))

local Bake = {}

Bake.VERSION = 3 -- 3: canQuery and light parameters are hashed; PointLights in the instance lines

export type Data = { lots: { Plan.Lot }, roads: { Plan.Road }, routes: { any }?, lighting: any?, treeArt: { any }? }

-- Every generated module the bake reads (Lune: generated/*.luau; engine: Shared.Generated).
function Bake.data(): Data
	local index = Import.generated("Index")
	local routes = {}
	for _, chunk in index.modules.Routes.chunks do
		for _, r in Import.generated(chunk) do
			table.insert(routes, r)
		end
	end
	return {
		lots = Import.generated("Lots"),
		roads = Import.generated("Roads"),
		routes = routes,
		lighting = Import.generated("Lighting"),
		treeArt = if index.modules.TreeArt then Import.generated("TreeArt") else nil,
	}
end

-- The solid lot boxes lamps must avoid (every collidable part of a solid lot: buildings, structures,
-- slabs; not the ground plates, whose collidable parts are the bridge deck and the river walls).
local function solidBoxes(plans: { Plan.BuildPlan }): { any }
	local out = {}
	for _, p in plans do
		if p.kind == "lot" and p.category ~= "plate" then
			for _, s in p.parts do
				-- door steps and indoor ceilings do not push lamps about (they keep their pinned places)
				if s.canCollide and s.role ~= "Step" and s.role ~= "Ceiling" then
					table.insert(out, s)
				end
			end
		end
	end
	return out
end

function Bake.plans(data: Data): { Plan.BuildPlan }
	local parents = Plan.containment(data.lots)
	local out: { Plan.BuildPlan } = {}
	for _, lot in data.lots do
		table.insert(out, Plan.plan(lot, lot.type, { parentId = parents[lot.id] }))
		Yield.breathe()
	end
	Plan.attachSlabs(out)
	local lotPlans = table.clone(out)
	local roadPlans = {}
	for _, road in data.roads do
		local rp = Plan.road(road, data.roads)
		table.insert(out, rp)
		table.insert(roadPlans, rp)
		Yield.breathe()
	end
	-- what stands under a point: terrain, paving, plates, decks and roofs (poles, pipes, fences, lamps)
	local surface = Surface.new(out, Height.at)
	local function groundAt(x: number, z: number, maxY: number?): (number, boolean)
		return Surface.at(surface, x, z, maxY)
	end
	Yield.breathe()
	local obstacles: { { number } } = {}
	if data.routes then
		local props = RouteProps.plans(data.routes, Kits.routeProps, Curve, Height.at, groundAt, data.treeArt)
		-- every drawn downspout meets the gutter above it (visual parts on the lot's own plan)
		Facade.downspouts(lotPlans, props)
		for _, p in props do
			table.insert(out, p)
			-- lamps keep clear of utility poles and tree trunks
			if p.category == "pole" or p.category == "tree" then
				local s = p.parts[1]
				table.insert(obstacles, { s.cx, s.cz, if p.category == "tree" then 3 else 0 })
			end
		end
	end
	Yield.breathe()
	local lamps = {}
	if data.lighting then
		local function baseAt(x: number, z: number): number
			local ref = Height.at(x, z)
			local deck = Height.riverDeckAt(x, z)
			if deck and deck > ref then
				ref = deck
			end
			return (Surface.at(surface, x, z, ref + 1))
		end
		local lampPlans
		lampPlans, lamps =
			LampPlan.plan(data.roads, roadPlans, solidBoxes(lotPlans), data.lighting, Kits.lamp, baseAt, obstacles)
		for _, p in lampPlans do
			table.insert(out, p)
		end
	end
	local skylineTypes: { [string]: boolean } = {}
	for _, lot in data.lots do
		skylineTypes[lot.type] = Kits.get(lot.type).skyline
	end
	table.insert(out, Skyline.plan(lotPlans, lamps, skylineTypes))
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

local function attrList(attrs: { [string]: any }?): string
	if not attrs then
		return ""
	end
	local keys: { string } = {}
	for k in attrs do
		table.insert(keys, k)
	end
	table.sort(keys)
	local out: { string } = {}
	for _, k in keys do
		table.insert(out, k .. "=" .. attrString(attrs[k], "%.3f"))
	end
	return table.concat(out, ",")
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
					q(s.roll or 0, "%.4f"),
					s.shape or "",
					if s.castShadow == nil then "" else tostring(s.castShadow),
					s.role or "",
					attrList(s.attrs) .. (if s.mesh then "|mesh:" .. s.mesh.id else ""),
					if s.canQuery == nil then "" else tostring(s.canQuery),
				}, "|")
			)
		end
		for _, e in p.extras or {} do
			local nums: { string } = {}
			for _, v in e.offset or {} do
				table.insert(nums, q(v, "%.3f"))
			end
			table.insert(
				lines,
				`  +{e.kind}|{e.part}|{e.name}|{e.text or ""}|{e.a or ""}|{e.b or ""}|{table.concat(nums, ",")}|{attrList(
					e.attrs
				)}`
					.. (
						if e.kind == "PointLight"
							then `|{q(e.range or 12, "%.1f")}|{q(e.brightness or 1, "%.2f")}|{tostring(
								e.shadows == true
							)}|{table.concat(e.color or { 255, 255, 255 }, ",")}`
							else ""
					)
			)
		end
	end
	return table.concat(lines, "\n")
end

function Bake.hash(plans: { Plan.BuildPlan }): string
	Yield.breathe()
	return fnv(Bake.serialize(plans))
end

local FOLDER = { lot = "Lots", road = "Roads", props = "Props", lamps = "Lamps" }

function Bake.run(data: Data, factory: Factory.Factory): any
	local plans = Bake.plans(data)
	local town = factory.instance("Model", "Town")
	local folders: { [string]: any } = {}
	for _, name in { "Lots", "Roads", "Props", "Lamps" } do
		folders[name] = factory.instance("Folder", name)
	end
	local counts = { lot = 0, road = 0, props = 0, lamps = 0, skyline = 0 }
	local partCount, lightCount = 0, 0
	for _, p in plans do
		for _, e in p.extras or {} do
			if e.kind == "PointLight" then
				lightCount += 1
			end
		end
		local model = if p.kind == "road" then RoadBuilder.build(p, factory) else Greybox.build(p, factory)
		model.Parent = if p.kind == "skyline" then town else folders[FOLDER[p.kind]]
		counts[p.kind] += 1
		partCount += #p.parts
		Yield.breathe()
	end
	for _, name in { "Lots", "Roads", "Props", "Lamps" } do
		folders[name].Parent = town
	end
	town:SetAttribute("BakeHash", Bake.hash(plans))
	town:SetAttribute("BakeVersion", Bake.VERSION)
	town:SetAttribute("LotCount", counts.lot)
	town:SetAttribute("RoadCount", counts.road)
	town:SetAttribute("PropCount", counts.props)
	town:SetAttribute("LampModels", counts.lamps)
	town:SetAttribute("PartCount", partCount)
	town:SetAttribute("LightCount", lightCount)
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
						tostring(child.CanQuery),
					}, "|")
				)
			elseif
				child:IsA("SurfaceGui")
				or child:IsA("ProximityPrompt")
				or child:IsA("Attachment")
				or child:IsA("Beam")
				or child:IsA("TextLabel")
				or child:IsA("PointLight")
			then
				local extra = ""
				if child:IsA("TextLabel") then
					extra = child.Text
				elseif child:IsA("ProximityPrompt") then
					extra = child.ActionText .. "/" .. tostring(child.Enabled)
				elseif child:IsA("PointLight") then
					extra = q(child.Range, "%.1f")
						.. "/"
						.. q(child.Brightness, "%.2f")
						.. "/"
						.. tostring(child.Enabled)
				elseif child:IsA("Beam") then
					extra = (if child.Attachment0 then child.Attachment0.Name else "")
						.. ">"
						.. (if child.Attachment1 then child.Attachment1.Name else "")
				end
				table.insert(lines, `{p}|{child.ClassName}|{extra}`)
			elseif child:IsA("Model") then
				Yield.breathe()
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
		Yield.breathe()
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
