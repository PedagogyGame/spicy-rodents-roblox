--!strict
-- ServerScriptService.Server.WorldGen.EnterCheck
-- "Every building with an interior can be entered" (owner 2026-11-11), checked on the bake plans alone
-- so Lune and the engine give the same verdict. A body is walked from the ground in front of the
-- building's first exterior door into the building the way the game's own motors move one
-- (Client/World/ClientWorld, Shared/Movement/SquirrelMotor):
--   * the ground under a point is the highest collidable top (or the terrain) not more than 1.5 st above
--     the feet: the ray the motor casts;
--   * a body steps onto ground up to STEP higher or lower (a kerb, a door step, a threshold) and no more;
--   * a body is stopped by any collidable part its own box overlaps: HALF to each side, from STEP above
--     the feet to TOP. TOP is a person's height, so what a person gets through a squirrel does too.
-- The walk is a flood fill on a CELL grid over the building's footprint and a porch in front of each
-- exterior door (it may not go round the outside: to come out at the back door it has to cross the
-- house). It must reach the middle of every room (within REACH) and the porch of every other exterior
-- door. So this fails when a leaf collides, a wall has no opening, a threshold or a step is too tall, a
-- piece of furniture stands in a doorway, a lintel is lower than a person, or the ground comes up
-- through the floor (also checked directly, on a 2 st grid).
-- Interface: lot(plan, heightAt) -> { rooms, doors, cells, failures }; run(plans, heightAt) -> the same
--   summed over the enterable lots, plus `lots`, failures prefixed with the lot id; STEP, HALF, TOP,
--   CELL, REACH
-- Pure.

local DoorSill = require("./DoorSill")
local Geometry = require("./Geometry")
local Spec = require("./Spec")
local Yield = require("./Yield")

local EnterCheck = {}

EnterCheck.STEP = 0.75 -- Client/World/ClientWorld.STEP
EnterCheck.HALF = 1.0 -- ClientWorld.BODY_HALF
EnterCheck.TOP = 5.5 -- a person standing
EnterCheck.CELL = 0.5
EnterCheck.REACH = 7 -- how near the middle of a room the walk must come

local BUCKET = 4
local EPS = 0.02

type Rect = { x0: number, x1: number, z0: number, z1: number }

function EnterCheck.lot(p: Spec.BuildPlan, heightAt: (number, number) -> number): { [string]: any }
	local failures: { string } = {}
	local STEP, HALF, TOP, CELL = EnterCheck.STEP, EnterCheck.HALF, EnterCheck.TOP, EnterCheck.CELL
	local floor: Spec.PartSpec? = nil
	for _, s in p.parts do
		if s.name == "Floor" then
			floor = s
		end
	end
	if floor == nil then
		return { rooms = 0, doors = 0, cells = 0, failures = { "no Floor part" } }
	end
	local floorTop = floor.cy + floor.sy / 2
	local fx0, fx1, _, _, fz0, fz1 = Geometry.aabb(floor :: any)

	-- what a body at floor level can stand on or run into (ceilings and roofs are out of its reach)
	local bx0: { number }, bx1: { number } = {}, {}
	local by0: { number }, by1: { number } = {}, {}
	local bz0: { number }, bz1: { number } = {}, {}
	local buckets: { [number]: { number } } = {}
	local function bucketKey(i: number, j: number): number
		return (i + 32768) * 65536 + (j + 32768)
	end
	local n = 0
	for _, s in p.parts do
		if s.canCollide then
			local x0, x1, y0, y1, z0, z1 = Geometry.aabb(s :: any)
			if y0 < floorTop + TOP + 1 then
				n += 1
				bx0[n], bx1[n], by0[n], by1[n], bz0[n], bz1[n] = x0, x1, y0, y1, z0, z1
				for i = math.floor(x0 / BUCKET), math.floor(x1 / BUCKET) do
					for j = math.floor(z0 / BUCKET), math.floor(z1 / BUCKET) do
						local k = bucketKey(i, j)
						local list = buckets[k]
						if list == nil then
							list = {}
							buckets[k] = list
						end
						table.insert(list, n)
					end
				end
			end
		end
	end

	-- the porches: in front of each exterior door, past its steps
	local doors = DoorSill.exterior(p)
	if #doors == 0 then
		return { rooms = 0, doors = 0, cells = 0, failures = { "no exterior door" } }
	end
	local region: { Rect } = { { x0 = fx0, x1 = fx1, z0 = fz0, z1 = fz1 } }
	local starts: { { name: string, x: number, z: number } } = {}
	for _, d in doors do
		local s = d.part
		local reach = 0
		local prefix = s.name .. "_Step"
		for _, q in p.parts do
			if q.role == "Step" and string.sub(q.name, 1, #prefix) == prefix then
				local x0, x1, _, _, z0, z1 = Geometry.aabb(q :: any)
				local half = math.abs(d.nx) * (x1 - x0) / 2 + math.abs(d.nz) * (z1 - z0) / 2
				reach = math.max(reach, (q.cx - s.cx) * d.nx + (q.cz - s.cz) * d.nz + half)
			end
		end
		local out = math.max(4, reach + 3)
		local half = d.width / 2 + 2
		local ax, az = s.cx - d.tx * half, s.cz - d.tz * half
		local cx, cz = s.cx + d.tx * half + d.nx * out, s.cz + d.tz * half + d.nz * out
		table.insert(region, {
			x0 = math.min(ax, cx),
			x1 = math.max(ax, cx),
			z0 = math.min(az, cz),
			z1 = math.max(az, cz),
		})
		table.insert(starts, { name = s.name, x = s.cx + d.nx * (out - 1), z = s.cz + d.nz * (out - 1) })
	end

	local gx0, gx1, gz0, gz1 = math.huge, -math.huge, math.huge, -math.huge
	for _, r in region do
		gx0, gx1, gz0, gz1 = math.min(gx0, r.x0), math.max(gx1, r.x1), math.min(gz0, r.z0), math.max(gz1, r.z1)
	end
	local nx = math.max(1, math.ceil((gx1 - gx0) / CELL))
	local nz = math.max(1, math.ceil((gz1 - gz0) / CELL))
	local function inRegion(x: number, z: number): boolean
		for _, r in region do
			if x >= r.x0 and x <= r.x1 and z >= r.z0 and z <= r.z1 then
				return true
			end
		end
		return false
	end

	local terrain: { number } = table.create(nx * nz, math.huge)
	local function groundAt(k: number, x: number, z: number, refY: number): number
		local g = terrain[k]
		if g == math.huge then
			g = heightAt(x, z)
			terrain[k] = g
		end
		local list = buckets[bucketKey(math.floor(x / BUCKET), math.floor(z / BUCKET))]
		if list then
			local limit = refY + 1.5
			for _, b in list do
				local top = by1[b]
				if top > g and top <= limit and x >= bx0[b] and x <= bx1[b] and z >= bz0[b] and z <= bz1[b] then
					g = top
				end
			end
		end
		return g
	end
	local function blocked(x: number, z: number, feet: number): boolean
		local lo, hi = feet + STEP + EPS, feet + TOP - EPS
		local ax0, ax1, az0, az1 = x - HALF + EPS, x + HALF - EPS, z - HALF + EPS, z + HALF - EPS
		for i = math.floor(ax0 / BUCKET), math.floor(ax1 / BUCKET) do
			for j = math.floor(az0 / BUCKET), math.floor(az1 / BUCKET) do
				local list = buckets[bucketKey(i, j)]
				if list then
					for _, b in list do
						if
							by1[b] > lo
							and by0[b] < hi
							and bx1[b] > ax0
							and bx0[b] < ax1
							and bz1[b] > az0
							and bz0[b] < az1
						then
							return true
						end
					end
				end
			end
		end
		return false
	end

	-- the walk
	local feetAt: { number } = table.create(nx * nz, math.huge)
	local function cellOf(x: number, z: number): (number, number)
		return math.clamp(math.floor((x - gx0) / CELL), 0, nx - 1), math.clamp(math.floor((z - gz0) / CELL), 0, nz - 1)
	end
	local si, sj = cellOf(starts[1].x, starts[1].z)
	local sk = sj * nx + si + 1
	local sx, sz = gx0 + (si + 0.5) * CELL, gz0 + (sj + 0.5) * CELL
	local queue: { number } = { sk }
	feetAt[sk] = groundAt(sk, sx, sz, heightAt(sx, sz) + 0.5)
	if blocked(sx, sz, feetAt[sk]) then
		table.insert(failures, `the ground in front of {starts[1].name} is not clear`)
	end
	local head = 1
	local DI, DJ = { 1, -1, 0, 0 }, { 0, 0, 1, -1 }
	while head <= #queue do
		local k = queue[head]
		head += 1
		if head % 20000 == 0 then
			Yield.breathe()
		end
		local i, j = (k - 1) % nx, (k - 1) // nx
		local feet = feetAt[k]
		for m = 1, 4 do
			local ii, jj = i + DI[m], j + DJ[m]
			if ii >= 0 and ii < nx and jj >= 0 and jj < nz then
				local kk = jj * nx + ii + 1
				if feetAt[kk] == math.huge then
					local x, z = gx0 + (ii + 0.5) * CELL, gz0 + (jj + 0.5) * CELL
					if inRegion(x, z) then
						local g = groundAt(kk, x, z, feet)
						if math.abs(g - feet) <= STEP + 1e-6 and not blocked(x, z, g) then
							feetAt[kk] = g
							table.insert(queue, kk)
						end
					end
				end
			end
		end
	end

	local function reached(x: number, z: number, r: number, box: Rect?): boolean
		local ci, cj = cellOf(x, z)
		local span = math.ceil(r / CELL)
		for j = math.max(cj - span, 0), math.min(cj + span, nz - 1) do
			for i = math.max(ci - span, 0), math.min(ci + span, nx - 1) do
				if feetAt[j * nx + i + 1] ~= math.huge then
					local px, pz = gx0 + (i + 0.5) * CELL, gz0 + (j + 0.5) * CELL
					if
						(px - x) ^ 2 + (pz - z) ^ 2 <= r * r
						and (box == nil or (px > box.x0 and px < box.x1 and pz > box.z0 and pz < box.z1))
					then
						return true
					end
				end
			end
		end
		return false
	end

	-- every room, and out again at every other door
	local rooms = 0
	for _, s in p.parts do
		local a: any = s.attrs or {}
		if s.role == "Room" and a.Exterior ~= true then
			rooms += 1
			local x0, x1, _, _, z0, z1 = Geometry.aabb(s :: any)
			if not reached(s.cx, s.cz, EnterCheck.REACH, { x0 = x0, x1 = x1, z0 = z0, z1 = z1 }) then
				table.insert(failures, `no way from {starts[1].name} into the room {a.RoomId}`)
			end
		end
	end
	for i = 2, #starts do
		if not reached(starts[i].x, starts[i].z, 1.0, nil) then
			table.insert(failures, `no way through the building from {starts[1].name} out at {starts[i].name}`)
		end
	end

	-- the ground stays under the floor
	local poke, worst = 0, 0
	for x = fx0 + 1, fx1 - 1, 2 do
		for z = fz0 + 1, fz1 - 1, 2 do
			local over = heightAt(x, z) - (floorTop - 0.05)
			if over > 0 then
				poke += 1
				worst = math.max(worst, over)
			end
		end
	end
	if poke > 0 then
		table.insert(
			failures,
			string.format("the ground comes up through the floor at %d places (by as much as %.1f st)", poke, worst)
		)
	end
	return { rooms = rooms, doors = #doors, cells = #queue, failures = failures }
end

-- Every enterable lot of the town.
function EnterCheck.run(plans: { Spec.BuildPlan }, heightAt: (number, number) -> number): { [string]: any }
	local out = { lots = 0, rooms = 0, doors = 0, cells = 0, failures = {} :: { string } }
	for _, p in plans do
		if p.kind == "lot" and p.attributes.Enterable == true then
			Yield.breathe()
			local r = EnterCheck.lot(p, heightAt)
			out.lots += 1
			out.rooms += r.rooms
			out.doors += r.doors
			out.cells += r.cells
			for _, f in r.failures do
				table.insert(out.failures, p.id .. ": " .. f)
			end
		end
	end
	return out
end

return EnterCheck
