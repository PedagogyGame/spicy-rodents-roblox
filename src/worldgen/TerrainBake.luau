--!strict
-- ServerScriptService.Server.WorldGen.TerrainBake (engine only: Lune cannot write voxels)
-- Writes smooth Terrain from a height function with Terrain:WriteVoxels in square chunks
-- (BUILD_PLAN D6, spike S6). Each chunk samples the height at column centres, sizes its vertical
-- range to the chunk's own max height, and fills occupancy so the drawn surface lands on the height
-- (see SURFACE_BIAS); columns with a water top (the v5.4 river) fill Water up to it. Axis-aligned paint
-- rectangles (roads, gardens) override the column's surface material.
-- Interface (BUILD_PLAN §1.4, D6): write(terrain, opts) -> Stats
-- No side effects on require; yields (task.wait) every `yieldEvery` seconds of work so a long
-- write never trips script-timeout watchdogs.

local TerrainBake = {}

local RES = 4
-- The engine draws (and collides) a column's surface half a voxel above its solid fraction: a column
-- full to y with air above meets a ray at y + 2, and a partly filled top voxel at yb + 4 * occupancy + 2
-- (tools/cloud/tasks/terrain_calib.luau, measured 2026-11-09: error 0.000 st on flats once the half
-- voxel is taken off, against exactly +2.000 st before). So the fill level is the height minus RES / 2.
-- Water is the exception: its surface sits at the fill level itself (tools/cloud/tasks/ground_probe.luau:
-- a river filled to WATER_Y - 2 met the ray at WATER_Y - 2), so water columns take no bias.
local SURFACE_BIAS = RES / 2

export type Rect = { minX: number, maxX: number, minZ: number, maxZ: number }
export type PaintRect = { minX: number, maxX: number, minZ: number, maxZ: number, material: Enum.Material }

export type Opts = {
	rect: Rect, -- studs; expanded outward to the 4-stud grid
	heightAt: (x: number, z: number) -> number, -- studs
	waterTopAt: ((x: number, z: number) -> number?)?, -- studs, nil = dry column
	materialAt: ((x: number, z: number, h: number) -> Enum.Material)?, -- surface material
	paint: { PaintRect }?,
	floorY: number?, -- bottom of the written slab (studs; default -16)
	chunk: number?, -- chunk edge in voxels (default 64 = 256 st)
	yieldEvery: number?, -- seconds of work between task.wait() (default 1; 0 = never yield)
}

export type Stats = {
	chunks: number,
	columns: number,
	voxels: number,
	seconds: number, -- wall time (os.clock) for the whole write, yields included
	sampleSeconds: number, -- height sampling and table fill
	writeSeconds: number, -- inside Terrain:WriteVoxels
	yields: number,
	maxTopY: number,
}

local function floorTo(v: number): number
	return math.floor(v / RES) * RES
end
local function ceilTo(v: number): number
	return math.ceil(v / RES) * RES
end

function TerrainBake.write(terrain: Terrain, opts: Opts): Stats
	local x0, x1 = floorTo(opts.rect.minX), ceilTo(opts.rect.maxX)
	local z0, z1 = floorTo(opts.rect.minZ), ceilTo(opts.rect.maxZ)
	local floorY = floorTo(opts.floorY or -16)
	local chunk = opts.chunk or 64
	local yieldEvery = opts.yieldEvery or 1
	local heightAt, waterTopAt, materialAt = opts.heightAt, opts.waterTopAt, opts.materialAt
	local paint: { PaintRect } = opts.paint or {}
	local grass, water, air = Enum.Material.Grass, Enum.Material.Water, Enum.Material.Air
	local stats: Stats = {
		chunks = 0,
		columns = 0,
		voxels = 0,
		seconds = 0,
		sampleSeconds = 0,
		writeSeconds = 0,
		yields = 0,
		maxTopY = floorY,
	}
	local started = os.clock()
	local lastYield = started
	local nxAll, nzAll = (x1 - x0) / RES, (z1 - z0) / RES

	for cz = 0, nzAll - 1, chunk do
		for cx = 0, nxAll - 1, chunk do
			local ts = os.clock()
			local nx = math.min(chunk, nxAll - cx)
			local nz = math.min(chunk, nzAll - cz)
			local bx, bz = x0 + cx * RES, z0 + cz * RES
			-- column samples
			local hs: { { number } } = table.create(nx)
			local ws: { { number } } = table.create(nx)
			local ms: { { Enum.Material } } = table.create(nx)
			local top = floorY + RES
			for i = 1, nx do
				local hcol: { number } = table.create(nz)
				local wcol: { number } = table.create(nz)
				local mcol: { Enum.Material } = table.create(nz)
				local x = bx + (i - 0.5) * RES
				for k = 1, nz do
					local z = bz + (k - 0.5) * RES
					local h = heightAt(x, z)
					local w = if waterTopAt then waterTopAt(x, z) else nil
					hcol[k] = h
					wcol[k] = w or -math.huge
					mcol[k] = if materialAt then materialAt(x, z, h) else grass
					local t = math.max(h, w or -math.huge)
					if t > top then
						top = t
					end
				end
				hs[i], ws[i], ms[i] = hcol, wcol, mcol
			end
			for _, r in paint do
				local i0 = math.max(1, math.floor((r.minX - bx) / RES + 0.5) + 1)
				local i1 = math.min(nx, math.floor((r.maxX - bx) / RES + 0.5))
				local k0 = math.max(1, math.floor((r.minZ - bz) / RES + 0.5) + 1)
				local k1 = math.min(nz, math.floor((r.maxZ - bz) / RES + 0.5))
				for i = i0, i1 do
					local mcol = ms[i]
					for k = k0, k1 do
						if ws[i][k] < hs[i][k] then
							mcol[k] = r.material
						end
					end
				end
			end
			local topY = ceilTo(top) + RES
			local ny = (topY - floorY) / RES
			local mats: { { { Enum.Material } } } = table.create(nx)
			local occs: { { { number } } } = table.create(nx)
			for i = 1, nx do
				local mi: { { Enum.Material } } = table.create(ny)
				local oi: { { number } } = table.create(ny)
				local hcol, wcol, mcol = hs[i], ws[i], ms[i]
				for j = 1, ny do
					local yb = floorY + (j - 1) * RES
					local mj: { Enum.Material } = table.create(nz)
					local oj: { number } = table.create(nz)
					for k = 1, nz do
						local occ = (hcol[k] - SURFACE_BIAS - yb) / RES
						if occ >= 0.5 then
							mj[k] = mcol[k]
							oj[k] = if occ > 1 then 1 else occ
						elseif wcol[k] > yb then
							mj[k] = water
							local wf = (wcol[k] - yb) / RES
							oj[k] = if wf > 1 then 1 else wf
						elseif occ > 0 then
							mj[k] = mcol[k]
							oj[k] = occ
						else
							mj[k] = air
							oj[k] = 0
						end
					end
					mi[j], oi[j] = mj, oj
				end
				mats[i], occs[i] = mi, oi
			end
			local tw = os.clock()
			stats.sampleSeconds += tw - ts
			local region = Region3.new(Vector3.new(bx, floorY, bz), Vector3.new(bx + nx * RES, topY, bz + nz * RES))
			terrain:WriteVoxels(region, RES, mats, occs)
			local te = os.clock()
			stats.writeSeconds += te - tw
			stats.chunks += 1
			stats.columns += nx * nz
			stats.voxels += nx * ny * nz
			if topY > stats.maxTopY then
				stats.maxTopY = topY
			end
			if yieldEvery > 0 and te - lastYield >= yieldEvery then
				task.wait()
				stats.yields += 1
				lastYield = os.clock()
			end
		end
	end
	stats.seconds = os.clock() - started
	return stats
end

return TerrainBake
