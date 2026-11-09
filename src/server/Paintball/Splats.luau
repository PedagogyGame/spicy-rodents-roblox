--!strict
-- ServerScriptService.Server.Paintball.Splats
-- Paint splat records for the pooled client decals (D29, arena.json splats.pool = 400; spike S18): a
-- ring that overwrites the oldest record, so the pool never exceeds its cap; cleared at match end.
-- A splat is either on geometry (position + face normal) or on a body (bodyId, offset from feet).
-- Interface: new(cap) -> Pool; add(pool, x, y, z, nx, ny, nz, team, bodyId?); clear(pool); size(pool)

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

return Splats
