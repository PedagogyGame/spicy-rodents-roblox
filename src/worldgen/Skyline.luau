--!strict
-- ServerScriptService.Server.WorldGen.Skyline
-- The far-view layer (BUILD_PLAN §4.4 #7, D6, S11): one non-colliding, non-queryable massing part per
-- building and structure (the envelope of its solid parts, roof peak included; baked transparent, shown
-- by the client only while the lot itself is streamed out) and one emissive
-- head per street lamp (with its arm and housing), in a single Persistent model so the drone sees the
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
				if s.canCollide and s.role ~= "Door" then
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
	for _, l in lamps do
		-- the arm from the post top over the kerb and the dark housing over the lit lens
		local dx, dz = l.hx - l.x, l.hz - l.z
		local arm = math.sqrt(dx * dx + dz * dz)
		local armYaw = math.atan2(-dx, -dz)
		if arm > 0.1 then
			list:add(ORIGIN, "Arm_" .. l.id, (l.x + l.hx) / 2, l.top - 0.2, (l.z + l.hz) / 2, 0.3, 0.3, arm, {
				yaw = armYaw,
				canCollide = false,
				canQuery = false,
				color = { 60, 62, 64 },
				material = "Metal",
				role = "Skyline",
			})
		end
		list:add(ORIGIN, "Housing_" .. l.id, l.hx, l.top + 0.05, l.hz, 1.3, 0.35, 1.0, {
			yaw = armYaw,
			canCollide = false,
			canQuery = false,
			color = { 52, 58, 60 },
			material = "Metal",
			role = "Skyline",
		})
		list:add(ORIGIN, "Head_" .. l.id, l.hx, l.top - 0.25, l.hz, 1.0, 0.25, 0.8, {
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
