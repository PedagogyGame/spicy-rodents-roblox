--!strict
-- tools/bake/skylift/Common: what the sky lift's bake pieces share (tools/bake/skylift.luau, Station, Towers,
-- Cabin, Summit, Approach): the lift's colours, the venue records and frames from generated/Expansion, the
-- venue Model with the BATCH2 §2.2 attributes, the Anchors folder, and a few shapes drawn between world points.
-- Lune only (@lune/roblox Instances through tools/bake/alley/Kit). Pure apart from the Instances it makes.
-- Interface: venue(id) -> record; place(venue) -> Kit place; worldKit(roblox) -> Kit in world axes (X = x,
--   Y = y, D = -z); venueModel(kit, parent, name, venue, budget, streaming) -> Model; anchors(kit, model, venue,
--   family) -> Folder; rodW(kit0, parent, name, a, b, d, color, material, opts?) -> Part (world points);
--   boxW(kit0, parent, name, a, b, w, h, color, material, opts?) -> Part (a box from a to b, up = +Y);
--   ground(x, z) -> Height.at; colours (STEEL, ...).

local AlleyLayout = require("../../../src/shared/Attractions/AlleyLayout")
local Expansion = require("../../../generated/Expansion")
local Height = require("../../../src/shared/World/Height")
local Kit = require("../alley/Kit")
local TerrainExtensions = require("../../../generated/TerrainExtensions")

Height.configure(TerrainExtensions)

local Common = {}

-- the lift's livery and the station's materials
Common.STEEL = { 96, 104, 110 } -- galvanised lattice, crossarms
Common.STEEL_DARK = { 58, 63, 68 } -- sheaves, rails, machinery
Common.ROPE = { 52, 50, 48 } -- haul rope (greased steel)
Common.CONCRETE = { 170, 166, 158 }
Common.CONCRETE_DARK = { 128, 124, 118 }
Common.TERRAZZO = { 206, 200, 188 }
Common.CREAM = { 238, 230, 210 }
Common.RED = { 178, 50, 38 } -- the lift's colour: cabins, station trim, signs
Common.RED_DARK = { 128, 34, 28 }
Common.GLASS = { 168, 200, 214 }
Common.FRAME = { 44, 48, 52 } -- window frames, rails
Common.YELLOW = { 232, 196, 52 } -- platform edge line
Common.WOOD = { 132, 92, 58 }
Common.WOOD_DARK = { 92, 64, 42 }
Common.WARM_LIGHT = { 255, 214, 160 }
Common.GRAVEL = { 156, 146, 128 }
Common.ROCK = { 124, 122, 116 }
Common.PINE = { 52, 82, 52 }
Common.PINE_DARK = { 40, 66, 44 }
Common.SHRUB = { 82, 108, 60 }
Common.BARK = { 86, 64, 48 }

Common.FAMILY = "F4"

-- generated/Expansion venue by id
function Common.venue(id: string): any
	for _, v in (Expansion :: any).venues do
		if v.id == id then
			return v
		end
	end
	error("skylift bake: no venue " .. id)
end

function Common.expansion(): any
	return Expansion
end

function Common.place(v: any): AlleyLayout.Place
	return { x = v.position.x, z = v.position.z, floorY = v.floorY, yaw = v.yaw }
end

function Common.ground(x: number, z: number): number
	return Height.at(x, z)
end

-- A Kit whose local frame is the world: X = x, Y = y, D = -z.
function Common.worldKit(roblox: any): Kit.Kit
	return Kit.new(roblox, { x = 0, z = 0, floorY = 0, yaw = 0 })
end

-- The venue Model (BATCH2 §2.2 attributes).
function Common.venueModel(kit: Kit.Kit, parent: any, name: string, v: any, budget: number, streaming: string): any
	local m = kit:model(parent, name)
	m:SetAttribute("VenueId", v.id)
	m:SetAttribute("Family", Common.FAMILY)
	m:SetAttribute("Type", v.type)
	m:SetAttribute("FloorY", v.floorY)
	m:SetAttribute("Yaw", v.yaw)
	m:SetAttribute("PartBudget", budget)
	m.ModelStreamingMode = (kit.roblox.Enum.ModelStreamingMode :: any)[streaming]
	return m
end

-- The Anchors folder: one 0.2-stud invisible part per anchor this family owns, at its world point and yaw.
function Common.anchors(kit: Kit.Kit, model: any, v: any, family: string): any
	local folder = kit:folder(model, "Anchors")
	local CFrame = kit.roblox.CFrame
	for _, a in v.anchors do
		if a.owner == family then
			local p = kit:at(
				folder,
				a.id,
				a.at[1],
				a.at[2],
				a.at[3],
				0.2,
				0.2,
				0.2,
				{ 255, 255, 255 },
				"SmoothPlastic",
				{
					collide = false,
					query = false,
					shadow = false,
					transparency = 1,
					rot = CFrame.Angles(0, math.rad(a.yaw or 0), 0),
					attrs = { Kind = a.kind, Ride = a.ride },
				}
			)
			p.Locked = true
		end
	end
	return folder
end

local function v3(roblox: any, p: { number }): any
	return roblox.Vector3.new(p[1], p[2], p[3])
end

-- A round rod between two world points.
function Common.rodW(
	kit0: Kit.Kit,
	parent: any,
	name: string,
	a: { number },
	b: { number },
	d: number,
	color: { number },
	material: string,
	opts: Kit.Opts?
): any
	return kit0:rod(parent, name, a[1], a[2], -a[3], b[1], b[2], -b[3], d, color, material, opts)
end

-- A box from world point a to world point b (its length along a->b), w wide and h tall, kept upright (its
-- width horizontal, perpendicular to a->b in plan).
function Common.boxW(
	kit0: Kit.Kit,
	parent: any,
	name: string,
	a: { number },
	b: { number },
	w: number,
	h: number,
	color: { number },
	material: string,
	opts: Kit.Opts?
): any
	local roblox = kit0.roblox
	local pa, pb = v3(roblox, a), v3(roblox, b)
	local len = (pb - pa).Magnitude
	local p = kit0:at(parent, name, 0, 0, 0, w, h, len, color, material, opts)
	p.CFrame = roblox.CFrame.lookAt((pa + pb) / 2, pb, roblox.Vector3.new(0, 1, 0))
	return p
end

-- The haul rope (SkyLift.loop(), at cable height) cut into who draws it: `spans` are the open spans between the
-- stations (segments at least SPAN_MIN long whose middle is outside both footprints: drawn by the Skyline,
-- always streamed), `base` and `summit` everything else, by the nearer bullwheel (the station runs, the
-- bullwheels, the fillet at the summit lip). Each entry is { a, b } world points.
Common.SPAN_MIN = 30
local ropeCache: any = nil
function Common.ropeSegments(): { spans: { any }, base: { any }, summit: { any } }
	if ropeCache then
		return ropeCache
	end
	local SkyLift = require("../../../src/shared/Rides/SkyLift")
	local st = SkyLift.stations()
	local venues = { Common.venue(st.base.venue), Common.venue(st.summit.venue) }
	local function inside(x: number, z: number): boolean
		for _, v in venues do
			local X, _, D = AlleyLayout.toLocal(Common.place(v), x, 0, z)
			if math.abs(X) <= v.footprint.w / 2 + 1 and math.abs(D) <= v.footprint.d / 2 + 1 then
				return true
			end
		end
		return false
	end
	local out = { spans = {}, base = {}, summit = {} }
	local L = SkyLift.loop()
	for i = 1, #L.points - 1 do
		local a, b = L.points[i], L.points[i + 1]
		local len = math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2 + (b.z - a.z) ^ 2)
		if len > 1e-3 then
			local mx, mz = (a.x + b.x) / 2, (a.z + b.z) / 2
			local seg = { { a.x, a.y, a.z }, { b.x, b.y, b.z } }
			if len >= Common.SPAN_MIN and not inside(mx, mz) then
				table.insert(out.spans, seg)
			else
				local db = (mx - st.base.wheel.x) ^ 2 + (mz - st.base.wheel.z) ^ 2
				local ds = (mx - st.summit.wheel.x) ^ 2 + (mz - st.summit.wheel.z) ^ 2
				table.insert(if db < ds then out.base else out.summit, seg)
			end
		end
	end
	ropeCache = out
	return out
end

-- Parts under an instance (BaseParts only).
function Common.parts(root: any): { any }
	local out = {}
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(out, d)
		end
	end
	return out
end

return Common
