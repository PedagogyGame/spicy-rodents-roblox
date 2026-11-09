--!strict
-- ServerScriptService.Server.WorldGen.Surface
-- What stands under a point (review 2026-11-09: poles, downspouts, fence panels and lamps must meet the
-- ground they stand on, which is not always the terrain: the bridge deck, plazas, sidewalks, decks,
-- lower roofs). An XZ grid over the near-level top faces of the baked lot and road parts (collidable
-- parts and ground plates; leaves, rooms, windows, signs and doors excluded) plus World/Height.
-- Interface: new(plans, heightAt) -> Surface; Surface.at(s, x, z, maxY?) -> (studs, onPart): the highest
--   top face (or terrain) under (x, z) that is not above maxY + 0.5 (nil maxY: no limit), and whether
--   it is a part (paving, deck, plate, roof) rather than the terrain.
-- Pure.

local Geometry = require("./Geometry")
local Spec = require("./Spec")

local Surface = {}

local CELL = 32
local MAX_TILT = 0.35 -- radians: steeper tops (roof plates, ramps' sides) are not ground
local SKIP_ROLES = {
	Leaves = true,
	Twig = true,
	Room = true,
	Anchor = true,
	Skyline = true,
	Window = true,
	Sign = true,
	Door = true,
	Paint = true,
}

type Top = { box: Spec.PartSpec, nx: number, ny: number, nz: number, qx: number, qy: number, qz: number }

export type Surface = {
	cells: { [number]: { Top } },
	heightAt: (number, number) -> number,
}

local function key(i: number, j: number): number
	return (i + 32768) * 65536 + (j + 32768)
end

local function usable(s: Spec.PartSpec, plateLot: boolean): boolean
	if SKIP_ROLES[s.role or ""] or s.transparency >= 1 then
		return false
	end
	if s.shape == "Ball" or s.shape == "Cylinder" or s.shape == "Wedge" then
		return false
	end
	if math.abs(s.pitch) > MAX_TILT or math.abs(s.roll or 0) > MAX_TILT then
		return false
	end
	return s.canCollide or plateLot
end

function Surface.new(plans: { Spec.BuildPlan }, heightAt: (number, number) -> number): Surface
	local self: Surface = { cells = {}, heightAt = heightAt }
	for _, p in plans do
		if p.kind == "lot" or p.kind == "road" then
			local plateLot = p.kind == "lot" and p.category == "plate"
			for _, s in p.parts do
				if usable(s, plateLot) then
					local up = Geometry.rotate({ 0, 1, 0 }, s.yaw, s.pitch, s.roll or 0)
					local top: Top = {
						box = s,
						nx = up[1],
						ny = up[2],
						nz = up[3],
						qx = s.cx + up[1] * s.sy / 2,
						qy = s.cy + up[2] * s.sy / 2,
						qz = s.cz + up[3] * s.sy / 2,
					}
					local x0, x1, _, _, z0, z1 = Geometry.aabb(s :: any)
					for i = math.floor(x0 / CELL), math.floor(x1 / CELL) do
						for j = math.floor(z0 / CELL), math.floor(z1 / CELL) do
							local k = key(i, j)
							local list = self.cells[k]
							if not list then
								list = {}
								self.cells[k] = list
							end
							table.insert(list, top)
						end
					end
				end
			end
		end
	end
	return self
end

function Surface.at(self: Surface, x: number, z: number, maxY: number?): (number, boolean)
	local best = self.heightAt(x, z)
	local onPart = false
	local limit = if maxY then maxY + 0.5 else math.huge
	for _, t in self.cells[key(math.floor(x / CELL), math.floor(z / CELL))] or {} do
		if t.ny > 0.5 and Geometry.containsXZ(t.box :: any, x, z, 0) then
			local y = t.qy - (t.nx * (x - t.qx) + t.nz * (z - t.qz)) / t.ny
			if y <= limit and y > best - 0.05 then
				best = math.max(best, y)
				onPart = true
			end
		end
	end
	return best, onPart
end

return Surface
