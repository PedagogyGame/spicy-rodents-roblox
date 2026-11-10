--!strict
-- ServerScriptService.Server.WorldGen.Skyline
-- The far-view layer (BUILD_PLAN §4.4 #7, D6, S11): one non-colliding, non-queryable massing part per
-- building and structure (the envelope of its solid parts, roof peak included; baked transparent, shown
-- by the client only while the lot itself is streamed out) and one emissive
-- head per street lamp (with its curved arm and housing), in a single Persistent model so the drone sees the
-- whole town. The client lights the nearest heads (Client/Render/LampLights).
-- Interface: plan(lotPlans, lamps, lampKit) -> BuildPlan. Pure.

local Geometry = require("./Geometry")
local LampPlan = require("./LampPlan")
local Spec = require("./Spec")

local Skyline = {}

local ORIGIN = Geometry.frame(0, 0, 0, 0)

function Skyline.plan(
	lotPlans: { Spec.BuildPlan },
	lamps: { LampPlan.Lamp },
	skylineTypes: { [string]: boolean }
): Spec.BuildPlan
	local list = Spec.list()
	local buildings = 0
	for _, p in lotPlans do
		if p.kind == "lot" and p.attributes.ParentLot == nil and skylineTypes[p.attributes.LotType :: string] then
			local x0, x1, y0, y1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge, math.huge, -math.huge
			for _, s in p.parts do
				-- door steps stand outside the massing: the far-view box is the building itself
				if s.canCollide and s.role ~= "Door" and s.role ~= "Step" then
					local a0, a1, b0, b1, c0, c1 = Geometry.aabb(s :: any)
					x0, x1 = math.min(x0, a0), math.max(x1, a1)
					y0, y1 = math.min(y0, b0), math.max(y1, b1)
					z0, z1 = math.min(z0, c0), math.max(z1, c1)
				end
			end
			if x0 < x1 then
				buildings += 1
				-- baked invisible: the client shows a massing box only while its lot is streamed out
				-- (Client/Render/TownView), so it never hides the real roofs, windows and colours
				list:add(ORIGIN, p.id, (x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2, x1 - x0, y1 - y0, z1 - z0, {
					canCollide = false,
					canQuery = false,
					transparency = 1,
					castShadow = false,
					color = p.parts[1].color,
					role = "Skyline",
					attrs = { Lot = p.id },
				})
			end
		end
	end
	local function arm(name: string, a: { number }, b: { number })
		local d = { b[1] - a[1], b[2] - a[2], b[3] - a[3] }
		local len = math.sqrt(d[1] * d[1] + d[2] * d[2] + d[3] * d[3])
		local yaw, roll = Geometry.axisAngles(d)
		list:add(ORIGIN, name, (a[1] + b[1]) / 2, (a[2] + b[2]) / 2, (a[3] + b[3]) / 2, len + 0.25, 0.4, 0.4, {
			yaw = yaw,
			roll = roll,
			shape = "Cylinder",
			canCollide = false,
			canQuery = false,
			color = { 44, 48, 50 },
			material = "Metal",
			role = "Skyline",
		})
	end
	for _, l in lamps do
		-- the curved arm from just under the post's finial out over the kerb, the dark housing and the
		-- lit lens under it (the head is what the client lights)
		local ox, oz = l.ox, l.oz
		local p0 = { l.x, l.top - 0.9, l.z }
		local p1 = { p0[1] + ox * 1.3, p0[2] + 1.1, p0[3] + oz * 1.3 }
		local p2 = { p1[1] + ox * 1.8, p1[2] + 0.25, p1[3] + oz * 1.8 }
		local p3 = { l.hx, p2[2] - 0.55, l.hz }
		arm("Arm_" .. l.id, p0, p1)
		arm("ArmB_" .. l.id, p1, p2)
		arm("ArmC_" .. l.id, p2, p3)
		local armYaw = math.atan2(-ox, -oz)
		list:add(ORIGIN, "Housing_" .. l.id, l.hx + ox * 0.3, p3[2] - 0.2, l.hz + oz * 0.3, 1.2, 0.5, 2.0, {
			yaw = armYaw,
			canCollide = false,
			canQuery = false,
			color = { 40, 44, 46 },
			material = "Metal",
			role = "Skyline",
		})
		list:add(ORIGIN, "Head_" .. l.id, l.hx + ox * 0.3, p3[2] - 0.52, l.hz + oz * 0.3, 0.9, 0.16, 1.5, {
			yaw = armYaw,
			canCollide = false,
			canQuery = false,
			color = { 255, 228, 170 },
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
