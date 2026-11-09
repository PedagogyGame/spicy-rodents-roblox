--!strict
-- ReplicatedStorage.Shared.Util.SpatialHash
-- Uniform 2D (x, z) grid of ids with per-id circles; insert/move/remove are O(cells touched) and a
-- query returns each id once (BUILD_PLAN §1.4 Util; perception and colliders use it). Pure.
-- Interface: new(cellSize) -> Hash; insert(h, id, x, z, r?); move(h, id, x, z, r?); remove(h, id);
--            query(h, x, z, r, out?) -> { id } (circle against the stored circles, exact); count(h)

export type Entry = { x: number, z: number, r: number, cells: { number } }
export type Hash = { cell: number, cells: { [number]: { [any]: true } }, entries: { [any]: Entry }, n: number }

local SpatialHash = {}

-- Cell key packs (ix, iz) into one integer; fine for |ix|, |iz| < 2^20.
local function key(ix: number, iz: number): number
	return (ix + 1048576) * 2097152 + (iz + 1048576)
end

function SpatialHash.new(cellSize: number): Hash
	assert(cellSize > 0, "SpatialHash: cellSize must be positive")
	return { cell = cellSize, cells = {}, entries = {}, n = 0 }
end

local function cover(h: Hash, x: number, z: number, r: number, fn: (k: number) -> ())
	local c = h.cell
	for ix = math.floor((x - r) / c), math.floor((x + r) / c) do
		for iz = math.floor((z - r) / c), math.floor((z + r) / c) do
			fn(key(ix, iz))
		end
	end
end

function SpatialHash.remove(h: Hash, id: any)
	local e = h.entries[id]
	if not e then
		return
	end
	for _, k in e.cells do
		local bucket = h.cells[k]
		if bucket then
			bucket[id] = nil
			if next(bucket) == nil then
				h.cells[k] = nil
			end
		end
	end
	h.entries[id] = nil
	h.n -= 1
end

function SpatialHash.insert(h: Hash, id: any, x: number, z: number, r: number?)
	if h.entries[id] then
		SpatialHash.remove(h, id)
	end
	local rr = r or 0
	local e: Entry = { x = x, z = z, r = rr, cells = {} }
	cover(h, x, z, rr, function(k)
		local bucket = h.cells[k]
		if not bucket then
			bucket = {}
			h.cells[k] = bucket
		end
		bucket[id] = true
		table.insert(e.cells, k)
	end)
	h.entries[id] = e
	h.n += 1
end

SpatialHash.move = SpatialHash.insert

function SpatialHash.query(h: Hash, x: number, z: number, r: number, out: { any }?): { any }
	local result = out or {}
	local seen: { [any]: boolean } = {}
	cover(h, x, z, r, function(k)
		local bucket = h.cells[k]
		if not bucket then
			return
		end
		for id in bucket do
			if not seen[id] then
				seen[id] = true
				local e = h.entries[id]
				local dx, dz, rr = e.x - x, e.z - z, e.r + r
				if dx * dx + dz * dz <= rr * rr then
					table.insert(result, id)
				end
			end
		end
	end)
	return result
end

function SpatialHash.count(h: Hash): number
	return h.n
end

return SpatialHash
