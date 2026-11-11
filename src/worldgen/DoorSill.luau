--!strict
-- ServerScriptService.Server.WorldGen.DoorSill
-- "Every door stands on its threshold at ground level" (the interiors work, 2026-11-11): on the bake
-- plans, for every exterior door leaf,
--   * the ground in front of it (across its width, from the wall to 3 st out) is nowhere more than
--     LEVEL above its sill: no door stands under the grass. 14 did, by 0.3 to 3.6 st, because a building
--     is seated at the height of its centre and the ground on its uphill side stands higher;
--   * its sill is level with that ground (within LEVEL), or collidable steps lead down from the sill to
--     the ground, the first step flush with the sill and no rise taller than RISE (the step a walking
--     body takes: Client/World/ClientWorld.STEP).
-- The ground is whatever `heightAt` says: World/Height.at, which already has the level building sites
-- cut into it.
-- Interface: exterior(plan) -> { Door }; run(plans, heightAt) -> { doors, level, stepped, failures }
--   (failures: "<lot>/<leaf>: why", sorted); LEVEL; RISE
-- Pure (runs in Lune and the engine).

local Geometry = require("./Geometry")
local Spec = require("./Spec")

local DoorSill = {}

DoorSill.LEVEL = 0.35 -- studs a sill may stand off the ground with no step (a threshold)
DoorSill.RISE = 0.75 -- the tallest step

export type Door = {
	part: Spec.PartSpec,
	sill: number, -- the leaf's bottom (world)
	nx: number, -- the outward normal
	nz: number,
	tx: number, -- along the leaf
	tz: number,
	width: number,
}

-- The exterior door leaves of a lot plan: a shell's doors onto "outside" and a plain building's front
-- door (the rule Builders/DoorReach uses), each with its outward normal.
function DoorSill.exterior(p: Spec.BuildPlan): { Door }
	local out: { Door } = {}
	local centre = p.parts[1]
	for _, s in p.parts do
		local a: any = s.attrs
		if
			s.role == "Door"
			and a
			and (a.RoomB == "outside" or a.RoomA == "outside" or (a.RoomA == nil and a.DoorId ~= nil))
		then
			local n = Geometry.rotate({ 0, 0, 1 }, s.yaw, 0, 0)
			local tangent = Geometry.rotate({ 1, 0, 0 }, s.yaw, 0, 0)
			local dot = (s.cx - centre.cx) * n[1] + (s.cz - centre.cz) * n[3]
			if a.RoomA == nil and a.RoomB == nil then
				dot = -1 -- a plain front door: the model's front is its local -Z
			end
			local sign = if dot >= 0 then 1 else -1
			table.insert(out, {
				part = s,
				sill = s.cy - s.sy / 2,
				nx = n[1] * sign,
				nz = n[3] * sign,
				tx = tangent[1],
				tz = tangent[3],
				width = s.sx,
			})
		end
	end
	return out
end

function DoorSill.run(plans: { Spec.BuildPlan }, heightAt: (number, number) -> number): { [string]: any }
	local failures: { string } = {}
	local doors, level, stepped = 0, 0, 0
	for _, p in plans do
		if p.kind == "lot" then
			for _, d in DoorSill.exterior(p) do
				doors += 1
				local s = d.part
				local tag = p.id .. "/" .. s.name
				local function ground(across: number, out: number): number
					return heightAt(s.cx + d.tx * across + d.nx * out, s.cz + d.tz * across + d.nz * out)
				end
				local top = -math.huge
				for _, a in { -0.5, 0, 0.5 } do
					for _, dist in { 0.5, 1.5, 3 } do
						top = math.max(top, ground(a * d.width, dist))
					end
				end
				if top - d.sill > DoorSill.LEVEL then
					table.insert(failures, string.format("%s: %.1f st under the ground", tag, top - d.sill))
					continue
				end
				local drop = d.sill - ground(0, 3)
				if drop <= DoorSill.LEVEL then
					level += 1
					continue
				end
				-- steps: <leaf>_Step1 (at the sill) .. <leaf>_StepN (at the ground)
				local steps: { Spec.PartSpec } = {}
				for _, q in p.parts do
					if q.role == "Step" and q.canCollide then
						local k = string.match(q.name, "^" .. string.gsub(s.name, "%p", "%%%0") .. "_Step(%d+)$")
						if k then
							steps[tonumber(k) :: number] = q
						end
					end
				end
				if #steps == 0 then
					table.insert(failures, string.format("%s: %.1f st above the ground with no steps", tag, drop))
					continue
				end
				local from = d.sill
				local ok = true
				local reach = 0
				for k, q in steps do
					local stepTop = q.cy + q.sy / 2
					local rise = from - stepTop
					if k == 1 and math.abs(rise) > 0.05 then
						table.insert(failures, string.format("%s: the top step is %.2f st off the sill", tag, rise))
						ok = false
					elseif rise > DoorSill.RISE + 1e-6 or rise < -1e-6 then
						table.insert(failures, string.format("%s: step %d rises %.2f st", tag, k, rise))
						ok = false
					end
					from = stepTop
					-- how far out this step reaches (its far edge along the normal)
					local x0, x1, _, _, z0, z1 = Geometry.aabb(q :: any)
					local half = math.abs(d.nx) * (x1 - x0) / 2 + math.abs(d.nz) * (z1 - z0) / 2
					reach = math.max(reach, (q.cx - s.cx) * d.nx + (q.cz - s.cz) * d.nz + half)
				end
				local last = from - ground(0, reach + 0.7)
				if last > DoorSill.RISE + 1e-6 then
					table.insert(
						failures,
						string.format("%s: the bottom step stands %.2f st above the ground", tag, last)
					)
					ok = false
				end
				if ok then
					stepped += 1
				end
			end
		end
	end
	table.sort(failures)
	return { doors = doors, level = level, stepped = stepped, failures = failures }
end

return DoorSill
