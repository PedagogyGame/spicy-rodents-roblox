--!strict
-- ServerScriptService.Server.WorldGen.Skyline
-- The far-view layer (BUILD_PLAN §4.4 #7, D6, S11): one non-colliding, non-queryable massing part per
-- building and structure (the envelope of its solid parts, roof peak included) and one emissive
-- head per street lamp, in a single Persistent model so the drone sees the whole town.
-- Interface: plan(lotPlans, lamps, lampKit) -> BuildPlan. Pure.

local Geometry = require("./Geometry")
local LampPlan = require("./LampPlan")
local Spec = require("./Spec")

local Skyline = {}

local ORIGIN = Geometry.frame(0, 0, 0, 0)

function Skyline.plan(lotPlans: { Spec.BuildPlan }, lamps: { LampPlan.Lamp }, skylineTypes: { [string]: boolean }): Spec.BuildPlan
	local list = Spec.list()
	local buildings = 0
	for _, p in lotPlans do
		if p.kind == "lot" and p.attributes.ParentLot == nil and skylineTypes[p.attributes.LotType :: string] then
			local x0, x1, y0, y1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge, math.huge, -math.huge
			for _, s in p.parts do
				if s.canCollide and s.role ~= "Door" then
					local a0, a1, b0, b1, c0, c1 = Geometry.aabb(s :: any)
					x0, x1 = math.min(x0, a0), math.max(x1, a1)
					y0, y1 = math.min(y0, b0), math.max(y1, b1)
					z0, z1 = math.min(z0, c0), math.max(z1, c1)
				end
			end
			if x0 < x1 then
				buildings += 1
				list:add(ORIGIN, p.id, (x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2, x1 - x0, y1 - y0, z1 - z0, {
					canCollide = false,
					canQuery = false,
					color = p.parts[1].color,
					role = "Skyline",
					attrs = { Lot = p.id },
				})
			end
		end
	end
	for _, l in lamps do
		list:add(ORIGIN, "Head_" .. l.id, l.x, l.top + 0.4, l.z, 0.9, 0.6, 0.9, {
			canCollide = false,
			canQuery = false,
			color = { 255, 214, 150 },
			material = "Neon",
			role = "Skyline",
			attrs = { Lamp = l.id, Flicker = l.flicker },
		})
	end
	return {
		kind = "skyline",
		id = "Skyline",
		category = "skyline",
		lod = "Disabled",
		streaming = "Persistent",
		attributes = { Buildings = buildings, LampHeads = #lamps },
		parts = list.parts,
		extras = list.extras,
	}
end

return Skyline
