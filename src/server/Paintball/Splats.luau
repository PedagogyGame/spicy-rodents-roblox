--!strict
-- ServerScriptService.Server.Paintball.Splats
-- Paint splat records (D29, arena.json splats.pool = 400; spike S18; checklist PB-4).
-- TWO SHAPES OF POOL live here:
--   the S18 ring (new / add / size / clear): one ring that overwrites its oldest record, kept for the
--   S18 harness and its spec;
--   THE MATCH'S TWO POOLS (pools / wall / body / clearBody / reset / batch), as the contract's wire
--   says (Shared/Minigames/Paintball/Wire, "two pools"): the WALLS' ring holds the newest `wallCap`
--   records on the building, and EACH SLOT has a ring of its own holding the newest `bodyCap` records
--   on that body, so paint on the walls never pushes paint off a player. One `seq` counts every splat
--   of the match and orders both. A slot's ring is emptied when its occupant changes (clearBody: nobody
--   wears the last one's paint); both are emptied when the match changes (reset). batch() is what
--   whoever comes into the audience is sent: every record of every ring, oldest first.
--   A record is a Wire.Splat record as it is packed: { seq, ball, by, body, team, face, x, y, z } (body
--   = 0 on the building with the face of the box it is on; else the slot it rides on, x y z being the
--   offset from that body's feet in the body's own frame).
-- Interface: new(cap) -> Pool; add(pool, x, y, z, nx, ny, nz, team, bodyId?); clear(pool); size(pool);
--   pools(wallCap, bodyCap) -> Pools; wall(pools, ball, by, team, face, x, y, z) -> Record;
--   body(pools, ball, by, team, id, lx, ly, lz) -> Record; clearBody(pools, id); reset(pools);
--   batch(pools) -> { Record }; count(pools) -> (walls, bodies); types Splat, Pool, Record, Pools

export type Splat = {
	x: number,
	y: number,
	z: number,
	nx: number,
	ny: number,
	nz: number,
	team: number,
	bodyId: number, -- 0 on geometry
	seq: number,
}
export type Pool = { cap: number, items: { Splat }, head: number, count: number, seq: number, overwritten: number }

export type Record = { [string]: number }
type Ring = { cap: number, items: { Record }, head: number }
export type Pools = {
	seq: number, -- the last seq given out; 0 after reset
	wallCap: number,
	bodyCap: number,
	walls: Ring,
	bodies: { [number]: Ring }, -- by slot id
}

local Splats = {}

function Splats.new(cap: number): Pool
	return { cap = cap, items = table.create(cap), head = 0, count = 0, seq = 0, overwritten = 0 }
end

function Splats.add(
	pool: Pool,
	x: number,
	y: number,
	z: number,
	nx: number,
	ny: number,
	nz: number,
	team: number,
	bodyId: number?
): Splat
	local i = pool.head % pool.cap + 1
	pool.head = i
	pool.seq += 1
	local s = pool.items[i]
	if s == nil then
		s = { x = 0, y = 0, z = 0, nx = 0, ny = 0, nz = 0, team = 0, bodyId = 0, seq = 0 }
		pool.items[i] = s
		pool.count += 1
	else
		pool.overwritten += 1
	end
	s.x, s.y, s.z, s.nx, s.ny, s.nz = x, y, z, nx, ny, nz
	s.team, s.bodyId, s.seq = team, bodyId or 0, pool.seq
	return s
end

function Splats.size(pool: Pool): number
	return pool.count
end

function Splats.clear(pool: Pool)
	table.clear(pool.items)
	pool.head, pool.count = 0, 0
end

-- The match's two pools ------------------------------------------------------------------------------

local function ring(cap: number): Ring
	return { cap = cap, items = {}, head = 0 }
end

-- (a record is a fresh table every time: the service hands the same record to its tick's batch)
local function put(r: Ring, rec: Record)
	local i = r.head % r.cap + 1
	r.head = i
	r.items[i] = rec
end

function Splats.pools(wallCap: number, bodyCap: number): Pools
	return { seq = 0, wallCap = wallCap, bodyCap = bodyCap, walls = ring(wallCap), bodies = {} }
end

-- A splat on the building: the point, and the face of the box it is on (Wire.FACE).
function Splats.wall(
	pools: Pools,
	ball: number,
	by: number,
	team: number,
	face: number,
	x: number,
	y: number,
	z: number
): Record
	pools.seq += 1
	local rec: Record = { seq = pools.seq, ball = ball, by = by, body = 0, team = team, face = face, x = x, y = y, z = z }
	put(pools.walls, rec)
	return rec
end

-- A splat on slot `id`'s body: (lx, ly, lz) is the offset from its feet in its own frame (Wire.toBody).
function Splats.body(
	pools: Pools,
	ball: number,
	by: number,
	team: number,
	id: number,
	lx: number,
	ly: number,
	lz: number
): Record
	pools.seq += 1
	local rec: Record =
		{ seq = pools.seq, ball = ball, by = by, body = id, team = team, face = 0, x = lx, y = ly, z = lz }
	local r = pools.bodies[id]
	if r == nil then
		r = ring(pools.bodyCap)
		pools.bodies[id] = r
	end
	put(r, rec)
	return rec
end

-- The slot's occupant changed: its body's paint goes with the one who wore it.
function Splats.clearBody(pools: Pools, id: number)
	pools.bodies[id] = nil
end

-- A new match: both pools empty, and seq counts from 1 again.
function Splats.reset(pools: Pools)
	pools.seq = 0
	pools.walls = ring(pools.wallCap)
	pools.bodies = {}
end

function Splats.count(pools: Pools): (number, number)
	local onBodies = 0
	for _, r in pools.bodies do
		onBodies += #r.items
	end
	return #pools.walls.items, onBodies
end

-- Every record held, oldest first (by seq): what a newcomer to the audience is sent.
function Splats.batch(pools: Pools): { Record }
	local out: { Record } = {}
	for _, rec in pools.walls.items do
		table.insert(out, rec)
	end
	for _, r in pools.bodies do
		for _, rec in r.items do
			table.insert(out, rec)
		end
	end
	table.sort(out, function(a: Record, b: Record): boolean
		return a.seq < b.seq
	end)
	return out
end

return Splats
