--!strict
-- ReplicatedStorage.Shared.Minigames.Paintball.ArenaGrid
-- The fast ball test and walking surface of the real arena (checklist PB-5, PB-15): the same answers as
-- the contract's reference (Arena.sweepBoxes, Arena.groundAt), number for number, found by looking only
-- at the boxes near the question. OWNED BY THE ARENA LANE (ArenaData hands these to Arena.finish).
--   sweep   a uniform 3D grid of CELL-stud cells; every box is listed in every cell it reaches (grown by
--           EPS, so a box whose face lies on a cell boundary is in the cells on both sides). A segment
--           is walked slab by slab along its longest axis; in each slab every cell its piece can touch
--           is searched. That is a superset of the cells the segment passes through, each box is put
--           to Ballistics.segmentBox itself (once a question), and the winner is the smallest s with
--           the lowest box index on a tie: exactly the reference's linear scan. The walk stops after
--           the slab in which the best hit lies.
--   ground  a 2D grid of columns, each listing the boxes and ramps over it; the reference's own
--           comparisons on that short list.
-- A question that leaves the grid (the lobby, a ball past the roof) is clamped to it: nothing solid is
-- outside, because the grid is laid over the bounds of every box. So the walk only steps through the slabs
-- that lie over the grid (a segment a million studs long walks the same few dozen), and one that misses the
-- grid along its longest axis misses everything. A question with a number that is not finite (an infinity, a
-- NaN: a bot's aim gone wrong) is put to the reference itself, so its answer is the reference's and it can
-- never walk forever.
-- Pure. Interface: new(boxes, ramps) -> (sweep: Arena.Sweep, ground: Arena.Ground, stats: { cells, entries })

local Ballistics = require("../../Paintball/Ballistics")
local Arena = require("./Arena")

local ArenaGrid = {}

ArenaGrid.CELL = 4 -- studs: a ball flies under 3.4 a tick, so a step touches one or two cells an axis
local EPS = 1e-6

function ArenaGrid.new(
	boxes: { number },
	ramps: { Arena.Ramp }
): (Arena.Sweep, Arena.Ground, { cells: number, entries: number })
	local CELL = ArenaGrid.CELL
	local n = #boxes // 6
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
	for k = 1, n * 6, 6 do
		minX, minY, minZ = math.min(minX, boxes[k]), math.min(minY, boxes[k + 1]), math.min(minZ, boxes[k + 2])
		maxX, maxY, maxZ = math.max(maxX, boxes[k + 3]), math.max(maxY, boxes[k + 4]), math.max(maxZ, boxes[k + 5])
	end
	for _, r in ramps do
		minX, minZ = math.min(minX, r.minX), math.min(minZ, r.minZ)
		maxX, maxZ = math.max(maxX, r.maxX), math.max(maxZ, r.maxZ)
	end
	if n == 0 and #ramps == 0 then
		minX, minY, minZ, maxX, maxY, maxZ = 0, 0, 0, 1, 1, 1
	end
	-- the grid's origin, a little outside everything, and its size in cells
	local ox, oy, oz = minX - 1, minY - 1, minZ - 1
	local nx = math.max(1, math.ceil((maxX + 1 - ox) / CELL))
	local ny = math.max(1, math.ceil((maxY + 1 - oy) / CELL))
	local nz = math.max(1, math.ceil((maxZ + 1 - oz) / CELL))
	local function cellOf(v: number, o: number, count: number): number
		local i = math.floor((v - o) / CELL)
		return if i < 0 then 0 elseif i >= count then count - 1 else i
	end

	-- every box into the cells it reaches
	local cells: { [number]: { number } } = table.create(nx * ny * nz) :: any
	local columns: { [number]: { number } } = table.create(nx * nz) :: any
	local entries = 0
	for i = 1, n do
		local k = (i - 1) * 6
		local ix0, ix1 = cellOf(boxes[k + 1] - EPS, ox, nx), cellOf(boxes[k + 4] + EPS, ox, nx)
		local iy0, iy1 = cellOf(boxes[k + 2] - EPS, oy, ny), cellOf(boxes[k + 5] + EPS, oy, ny)
		local iz0, iz1 = cellOf(boxes[k + 3] - EPS, oz, nz), cellOf(boxes[k + 6] + EPS, oz, nz)
		for ix = ix0, ix1 do
			for iz = iz0, iz1 do
				local col = ix * nz + iz + 1
				local list = columns[col]
				if not list then
					list = {}
					columns[col] = list
				end
				table.insert(list :: { number }, i)
				for iy = iy0, iy1 do
					local c = (ix * ny + iy) * nz + iz + 1
					local inCell = cells[c]
					if not inCell then
						inCell = {}
						cells[c] = inCell
					end
					table.insert(inCell :: { number }, i)
					entries += 1
				end
			end
		end
	end
	local rampColumns: { [number]: { number } } = table.create(nx * nz) :: any
	for i, r in ramps do
		for ix = cellOf(r.minX - EPS, ox, nx), cellOf(r.maxX + EPS, ox, nx) do
			for iz = cellOf(r.minZ - EPS, oz, nz), cellOf(r.maxZ + EPS, oz, nz) do
				local col = ix * nz + iz + 1
				local list = rampColumns[col]
				if not list then
					list = {}
					rampColumns[col] = list
				end
				table.insert(list :: { number }, i)
			end
		end
	end

	local tested: { number } = table.create(n, 0)
	local question = 0
	local segmentBox = Ballistics.segmentBox

	local function sweep(
		x0: number,
		y0: number,
		z0: number,
		x1: number,
		y1: number,
		z1: number
	): (number?, number, number, number, number)
		local sum = x0 + y0 + z0 + x1 + y1 + z1
		if sum - sum ~= 0 then
			return Arena.sweepBoxes(boxes, x0, y0, z0, x1, y1, z1) -- an infinity or a NaN
		end
		question += 1
		local q = question
		local best: number? = nil
		local bnx, bny, bnz, index = 0, 0, 0, 0
		local dx, dy, dz = x1 - x0, y1 - y0, z1 - z0
		local ax, ay, az = math.abs(dx), math.abs(dy), math.abs(dz)
		-- the longest axis: its slabs are walked from the segment's start to its end
		local p0: number, d: number, o: number, count: number
		if ax >= ay and ax >= az then
			p0, d, o, count = x0, dx, ox, nx
		elseif ay >= az then
			p0, d, o, count = y0, dy, oy, ny
		else
			p0, d, o, count = z0, dz, oz, nz
		end
		local first = math.floor((p0 - o) / CELL)
		local last = math.floor((p0 + d - o) / CELL)
		local whole = first == last -- the segment lies in one slab: its piece there is all of it
		local step = if last >= first then 1 else -1
		-- only the slabs over the grid (and the one either side of it) can hold anything
		if step > 0 then
			if first > count or last < -1 then
				return nil, 0, 0, 0, 0
			end
			first, last = math.max(first, -1), math.min(last, count)
		else
			if last > count or first < -1 then
				return nil, 0, 0, 0, 0
			end
			first, last = math.min(first, count), math.max(last, -1)
		end
		local slab = first
		while true do
			-- the piece of the segment inside this slab of the longest axis, as fractions ta..tb
			local ta, tb = 0, 1
			if not whole then
				local lo, hi = o + slab * CELL, o + (slab + 1) * CELL
				if step > 0 then
					ta, tb = (lo - p0) / d, (hi - p0) / d
				else
					ta, tb = (hi - p0) / d, (lo - p0) / d
				end
				ta, tb = math.max(0, ta), math.min(1, tb)
			end
			do
				local xa, xb = x0 + dx * ta, x0 + dx * tb
				local ya, yb = y0 + dy * ta, y0 + dy * tb
				local za, zb = z0 + dz * ta, z0 + dz * tb
				local ix0 = cellOf(math.min(xa, xb) - EPS, ox, nx)
				local ix1 = cellOf(math.max(xa, xb) + EPS, ox, nx)
				local iy0 = cellOf(math.min(ya, yb) - EPS, oy, ny)
				local iy1 = cellOf(math.max(ya, yb) + EPS, oy, ny)
				local iz0 = cellOf(math.min(za, zb) - EPS, oz, nz)
				local iz1 = cellOf(math.max(za, zb) + EPS, oz, nz)
				for ix = ix0, ix1 do
					for iy = iy0, iy1 do
						local base = (ix * ny + iy) * nz + 1
						for iz = iz0, iz1 do
							local list = cells[base + iz]
							if list then
								for _, i in list do
									if tested[i] ~= q then
										tested[i] = q
										local k = (i - 1) * 6
										local s, fx, fy, fz = segmentBox(
											x0,
											y0,
											z0,
											x1,
											y1,
											z1,
											boxes[k + 1],
											boxes[k + 2],
											boxes[k + 3],
											boxes[k + 4],
											boxes[k + 5],
											boxes[k + 6]
										)
										if s ~= nil and (best == nil or s < best or (s == best and i < index)) then
											best, bnx, bny, bnz, index = s, fx, fy, fz, i
										end
									end
								end
							end
						end
					end
				end
			end
			if slab == last or (best ~= nil and best <= tb) then
				break
			end
			slab += step
		end
		return best, bnx, bny, bnz, index
	end

	local function ground(x: number, y: number, z: number): number?
		local col = cellOf(x, ox, nx) * nz + cellOf(z, oz, nz) + 1
		local limit = y + Arena.STEP_UP
		local best: number? = nil
		local list = columns[col]
		if list then
			for _, i in list do
				local k = (i - 1) * 6
				if x >= boxes[k + 1] and x <= boxes[k + 4] and z >= boxes[k + 3] and z <= boxes[k + 6] then
					local top = boxes[k + 5]
					if top <= limit and (best == nil or top > best) then
						best = top
					end
				end
			end
		end
		local rampList = rampColumns[col]
		if rampList then
			for _, i in rampList do
				local h = Arena.rampHeight(ramps[i], x, z)
				if h ~= nil and h <= limit and (best == nil or h > best) then
					best = h
				end
			end
		end
		return best
	end

	return sweep, ground, { cells = nx * ny * nz, entries = entries }
end

return ArenaGrid
