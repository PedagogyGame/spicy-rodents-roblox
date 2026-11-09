--!strict
-- ServerScriptService.Server.WorldGen.DoorReach
-- "Every door reachable from a sidewalk" (BUILD_PLAN §4.4 #7 exit criteria): a 2-D walkability grid
-- (2.5 st cells) over the baked plans. Cells covered by a solid part standing on the ground (walls,
-- bodies, fences, trunks, posts) or by river water are blocked; floors, plates, roads, doors and
-- anything overhead are not. A breadth-first fill from every road cell must reach the cell just
-- outside each exterior door.
-- Interface: run(plans, heightAt, isWater) -> { doors, unreachable = { "<lot>/<door>" }, cells }
-- Pure (Luau buffers; runs in Lune and the engine).

local Geometry = require("./Geometry")
local Spec = require("./Spec")

local DoorReach = {}

local CELL = 2.5
local PASS_ROLES = { Door = true, Floor = true, Room = true, Anchor = true, Skyline = true, Sign = true, Pad = true }

function DoorReach.run(plans: { Spec.BuildPlan }, heightAt: (number, number) -> number, isWater: (number, number) -> boolean): { [string]: any }
	local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
	for _, p in plans do
		if p.kind == "lot" or p.kind == "road" then
			for _, s in p.parts do
				local a0, a1, _, _, c0, c1 = Geometry.aabb(s :: any)
				x0, x1, z0, z1 = math.min(x0, a0), math.max(x1, a1), math.min(z0, c0), math.max(z1, c1)
			end
		end
	end
	x0, z0 = x0 - 20, z0 - 20
	local nx, nz = math.ceil((x1 + 20 - x0) / CELL), math.ceil((z1 + 20 - z0) / CELL)
	local grid = buffer.create(nx * nz) -- 0 free, 1 blocked, 2 road, 3 reached
	local function idx(i: number, j: number): number
		return j * nx + i
	end
	local function cellOf(x: number, z: number): (number, number)
		return math.floor((x - x0) / CELL), math.floor((z - z0) / CELL)
	end
	-- water
	for j = 0, nz - 1 do
		for i = 0, nx - 1 do
			local x, z = x0 + (i + 0.5) * CELL, z0 + (j + 0.5) * CELL
			if isWater(x, z) then
				buffer.writeu8(grid, idx(i, j), 1)
			end
		end
	end
	local function raster(s: Spec.PartSpec, value: number)
		local a0, a1, _, _, c0, c1 = Geometry.aabb(s :: any)
		local i0, j0 = cellOf(a0, c0)
		local i1, j1 = cellOf(a1, c1)
		for j = math.max(j0, 0), math.min(j1, nz - 1) do
			for i = math.max(i0, 0), math.min(i1, nx - 1) do
				local x, z = x0 + (i + 0.5) * CELL, z0 + (j + 0.5) * CELL
				if Geometry.containsXZ(s :: any, x, z, 0) then
					local k = idx(i, j)
					if value == 2 or buffer.readu8(grid, k) ~= 2 then
						buffer.writeu8(grid, k, value)
					end
				end
			end
		end
	end
	-- blockers first, then roads on top (bridges over water, roads under nothing)
	for _, p in plans do
		if p.kind ~= "road" and p.kind ~= "skyline" then
			for _, s in p.parts do
				if s.canCollide and not PASS_ROLES[s.role or ""] then
					local _, _, b0, b1 = Geometry.aabb(s :: any)
					local ground = heightAt(s.cx, s.cz)
					if b1 - b0 >= 1 and b0 - ground < 3 then
						raster(s, 1)
					end
				end
			end
		end
	end
	local queue = buffer.create(nx * nz * 4)
	local head, tail = 0, 0
	for _, p in plans do
		if p.kind == "road" then
			for _, s in p.parts do
				raster(s, 2)
			end
		end
	end
	for k = 0, nx * nz - 1 do
		if buffer.readu8(grid, k) == 2 then
			buffer.writeu8(grid, k, 3)
			buffer.writeu32(queue, tail * 4, k)
			tail += 1
		end
	end
	while head < tail do
		local k = buffer.readu32(queue, head * 4)
		head += 1
		local i, j = k % nx, k // nx
		for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
			local ii, jj = i + d[1], j + d[2]
			if ii >= 0 and ii < nx and jj >= 0 and jj < nz then
				local kk = idx(ii, jj)
				if buffer.readu8(grid, kk) == 0 then
					buffer.writeu8(grid, kk, 3)
					buffer.writeu32(queue, tail * 4, kk)
					tail += 1
				end
			end
		end
	end
	-- exterior doors
	local doors, unreachable = 0, {}
	for _, p in plans do
		if p.kind == "lot" then
			local centre = p.parts[1]
			for _, s in p.parts do
				local a = s.attrs
				if s.role == "Door" and a and (a.RoomB == "outside" or a.RoomA == "outside" or (a.RoomA == nil and a.DoorId ~= nil)) then
					doors += 1
					-- door normal (the part's local Z), pointing away from the lot centre
					local n = Geometry.rotate({ 0, 0, 1 }, s.yaw, 0, 0)
					local dot = (s.cx - centre.cx) * n[1] + (s.cz - centre.cz) * n[3]
					if a.RoomA == nil and a.RoomB == nil then
						-- generic front door: the model faces -Z (LookVector)
						dot = -1
					end
					local sign = if dot >= 0 then 1 else -1
					local ok = false
					for step = 1, 3 do
						local ox, oz = s.cx + n[1] * sign * (CELL * step), s.cz + n[3] * sign * (CELL * step)
						local i, j = cellOf(ox, oz)
						if i >= 0 and i < nx and j >= 0 and j < nz and buffer.readu8(grid, idx(i, j)) == 3 then
							ok = true
							break
						end
					end
					if not ok then
						table.insert(unreachable, p.id .. "/" .. s.name)
					end
				end
			end
		end
	end
	table.sort(unreachable)
	return { doors = doors, unreachable = unreachable, cells = nx * nz, reached = tail }
end

return DoorReach
