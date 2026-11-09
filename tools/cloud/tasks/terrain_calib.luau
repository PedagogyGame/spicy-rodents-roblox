--!strict
-- Engine probe: where does the smooth-terrain surface sit for a given voxel occupancy? Writes small
-- patches far from the town (flat columns at several heights, a slope, a grid-aligned FillBlock slab)
-- and raycasts them, so TerrainBake's occupancy rule can be checked against the engine itself.
local terrain = workspace.Terrain
local RES = 4
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include
params.FilterDescendantsInstances = { terrain }

local pending: { () -> () } = {}
local function later(f: () -> ())
	table.insert(pending, f)
end
local function cast(x: number, z: number): number?
	local hit = workspace:Raycast(Vector3.new(x, 60, z), Vector3.new(0, -200, 0), params)
	return if hit then hit.Position.Y else nil
end

-- writes an n x n column patch whose surface height is heightAt(x, z), with occupancy = solid
-- fraction of each voxel after shifting the height by `shift`
local function patch(bx: number, bz: number, n: number, shift: number, heightAt: (number, number) -> number)
	local floorY, topY = -16, 32
	local ny = (topY - floorY) / RES
	local mats, occs = table.create(n), table.create(n)
	for i = 1, n do
		local mi, oi = table.create(ny), table.create(ny)
		for j = 1, ny do
			local yb = floorY + (j - 1) * RES
			local mj, oj = table.create(n), table.create(n)
			for k = 1, n do
				local h = heightAt(bx + (i - 0.5) * RES, bz + (k - 0.5) * RES) + shift
				local occ = math.clamp((h - yb) / RES, 0, 1)
				mj[k] = if occ > 0 then Enum.Material.Grass else Enum.Material.Air
				oj[k] = occ
			end
			mi[j], oi[j] = mj, oj
		end
		mats[i], occs[i] = mi, oi
	end
	terrain:WriteVoxels(
		Region3.new(Vector3.new(bx, floorY, bz), Vector3.new(bx + n * RES, topY, bz + n * RES)),
		RES,
		mats,
		occs
	)
end

local out: { [string]: any } = { flat = {}, slope = {} }
local slot = 0
local function nextOrigin(): (number, number)
	slot += 1
	return 6000 + slot * 200, 6000
end

for _, shift in { 0, -2 } do
	for _, h in { 0, 0.5, 1, 1.5, 2, 2.5, 3, 3.5, 4, 5.3 } do
		local bx, bz = nextOrigin()
		patch(bx, bz, 12, shift, function()
			return h
		end)
		later(function()
			local y = cast(bx + 24.7, bz + 23.1)
			table.insert(out.flat, { shift = shift, h = h, y = y, err = if y then y - h else nil })
		end)
	end
end

for _, shift in { 0, -2 } do
	for _, slope in { 0.02, 0.1, 0.3, 0.6 } do
		local bx, bz = nextOrigin()
		local function f(x: number, z: number): number
			return 2 + (x - bx) * slope + math.sin((z - bz) * 0.05) * 1.5
		end
		patch(bx, bz, 24, shift, f)
		later(function()
			local n, sum, lo, hi = 0, 0, 1e9, -1e9
			for i = 0, 200 do
				local x = bx + 16 + i * 0.3
				local z = bz + 20 + i * 0.27
				local y = cast(x, z)
				if y then
					local e = y - f(x, z)
					n += 1
					sum += e
					lo = math.min(lo, e)
					hi = math.max(hi, e)
				end
			end
			table.insert(
				out.slope,
				{ shift = shift, slope = slope, n = n, mean = sum / math.max(n, 1), min = lo, max = hi }
			)
		end)
	end
end

-- a grid-aligned FillBlock slab with its top at y = 8, and what ReadVoxels says about it
do
	local bx, bz = nextOrigin()
	terrain:FillBlock(CFrame.new(bx + 24, 0, bz + 24), Vector3.new(48, 16, 48), Enum.Material.Grass)
	later(function()
		out.fillBlock.y = cast(bx + 24.7, bz + 23.1)
	end)
	local _, occ =
		terrain:ReadVoxels(Region3.new(Vector3.new(bx + 20, -8, bz + 20), Vector3.new(bx + 24, 20, bz + 24)), RES)
	local col = {}
	for j = 1, occ.Size.Y do
		table.insert(col, occ[1][j][1])
	end
	out.fillBlock = { top = 8, occupancyFromYMinus8 = col }
end

-- sanity: a part with its top at y = 3 under the same ray
do
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = Vector3.new(8, 2, 8)
	p.Position = Vector3.new(30000, 2, 30000)
	p.Parent = workspace
	local hit = workspace:Raycast(Vector3.new(30000, 60, 30000), Vector3.new(0, -200, 0))
	out.partTop = { expect = 3, y = if hit then hit.Position.Y else nil }
end

task.wait(2)
for _, f in pending do
	f()
end
out.pending = #pending
return out
