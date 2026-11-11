--!strict
-- ReplicatedStorage.Shared.World.RoadSurface
-- The roads as the bake draws them, as a pure function. worldgen/Plan.road builds every road from
-- `layout` (straight segments that follow the terrain along the road and are rolled to its crossfall,
-- each a flat part RoadSurface.THICKNESS thick whose top sits `offset` over the ground at its centre
-- line), so the parts a player sees and `topAt` here are the same planes. Clients seat the traffic
-- ghosts on `ground` (Traffic/Ghost.seat): on the asphalt that is drawn, not on World/Height under it.
-- Owner 2026-11-10 "the cars are glitching": seated on the terrain, ghosts drove up to 2.9 st inside
-- the road where it was laid level over sloping ground, and 0.14 to 0.6 st inside it everywhere else
-- (tools/sim detectors/surface, scenario road_surface).
-- Interface: layout(road, offset) -> Layout; groundAt(x, z) -> (y, onDeck); OFFSET_U; SOLID;
--            new(roads) -> Surface; topAt(surface, x, z, maxY) -> y?; ground(surface, heightAt) -> (x, z) -> y
-- Pure; studs. No side effects on require.

local Height = require("./Height")

local RoadSurface = {}

local S = Height.STUDS_PER_UNIT

RoadSurface.SEGMENT = 40 -- studs: roads follow the terrain in straight segments this long or less
-- A road wider than WIDE is cut twice as fine: its segments are rolled to the crossfall at their
-- middles, and the further a lane is from the centre line the more a change of crossfall along a
-- segment lifts or drops it (on the 65 st boulevard, 0.35 st steps at the lanes with 40 st segments)
RoadSurface.WIDE = 20
RoadSurface.SEGMENT_WIDE = 20
RoadSurface.THICKNESS = 0.4
RoadSurface.MAX_ROLL = 0.3 -- radians: a road's crossfall is followed up to this (17 degrees)
RoadSurface.MAX_ABOVE = 3 -- studs: `ground` takes a road top at most this far over the terrain (not a deck overhead)

-- The kinds' heights over the ground (HTML units; worldgen/Kits.ROAD holds the same, pinned by
-- tests/unit/world_roadsurface.spec) and whether they are solid (rails are paint on another road).
RoadSurface.OFFSET_U = table.freeze({ asphalt = 0.055, concrete = 0.09, cobble = 0.09, path = 0.06, rail = 0.12 })
RoadSurface.SOLID = table.freeze({ asphalt = true, concrete = true, cobble = true, path = true, rail = false })

export type Road = { id: string, kind: string, axis: string?, coord: any, start: any, ["end"]: any, width: number }

export type Layout = {
	x0: number,
	z0: number,
	dx: number,
	dz: number,
	len: number,
	ux: number,
	uz: number,
	n: number, -- segments
	yaw: number, -- the parts' yaw (LookVector along the road)
	y: { number }, -- y[i + 1]: the part centre height at fraction i / n, i = 0..n
	roll: { number }, -- roll[i]: segment i's roll about the road's axis (+: its right side up)
	pitch: { number }, -- pitch[i]
}

-- groundAt(x, z): what a road is laid on: the terrain, or the Quay bridge's deck and ramps (not the river
-- bed under them); and whether that is the deck.
function RoadSurface.groundAt(x: number, z: number): (number, boolean)
	local deck = Height.riverDeckAt(x, z)
	local ground = Height.at(x, z)
	if deck and deck > ground then
		return deck, true
	end
	return ground, false
end

local function endpoints(road: Road): (number, number, number, number)
	if road.axis == "x" then
		local z = road.coord :: number
		return road.start :: number, z, road["end"] :: number, z
	elseif road.axis == "z" then
		local x = road.coord :: number
		return x, road.start :: number, x, road["end"] :: number
	end
	local s, e = road.start :: { number }, road["end"] :: { number }
	return s[1], s[2], e[1], e[2]
end
RoadSurface.endpoints = endpoints

-- layout(road, offset): the segments worldgen/Plan.road builds the road from; `offset` is the top's
-- height over the ground (studs).
function RoadSurface.layout(road: Road, offset: number): Layout
	local x0, z0, x1, z1 = endpoints(road)
	local dx, dz = x1 - x0, z1 - z0
	local len = math.sqrt(dx * dx + dz * dz)
	local step = if road.width > RoadSurface.WIDE then RoadSurface.SEGMENT_WIDE else RoadSurface.SEGMENT
	local n = math.max(1, math.ceil(len / step))
	local ux, uz = if len > 0 then dx / len else 0, if len > 0 then dz / len else 0
	local ys: { number } = {}
	for i = 0, n do
		local t = i / n
		ys[i + 1] = (RoadSurface.groundAt(x0 + dx * t, z0 + dz * t)) + offset - RoadSurface.THICKNESS / 2
	end
	local rolls, pitches = {}, {}
	local hw = road.width / 2
	local seg = len / n
	for i = 1, n do
		-- rolled so the top follows the ground ACROSS the road too (left edge to right edge at the
		-- segment's middle): level across, a wide road over sloping ground floats off the terrain on its
		-- low side and sinks into it on the high side, and where two roads cross one's level slab stood
		-- up to 2.9 st proud of the other. Level on and next to the bridge deck.
		local t = (i - 0.5) / n
		local x, z = x0 + dx * t, z0 + dz * t
		local right, onDeckR = RoadSurface.groundAt(x - uz * hw, z + ux * hw)
		local left, onDeckL = RoadSurface.groundAt(x + uz * hw, z - ux * hw)
		local _, onDeck = RoadSurface.groundAt(x, z)
		local roll = 0
		if not (onDeck or onDeckR or onDeckL) and road.width > 0 then
			roll = math.clamp(math.atan2(right - left, road.width), -RoadSurface.MAX_ROLL, RoadSurface.MAX_ROLL)
		end
		rolls[i] = roll
		pitches[i] = math.atan2(ys[i + 1] - ys[i], seg)
	end
	return {
		x0 = x0,
		z0 = z0,
		dx = dx,
		dz = dz,
		len = len,
		ux = ux,
		uz = uz,
		n = n,
		yaw = if len > 0 then math.atan2(-dx, -dz) else 0,
		y = ys,
		roll = rolls,
		pitch = pitches,
	}
end

-- One segment's top face: a plane through (qx, qy, qz) with normal (nx, ny, nz), over the rectangle
-- centred on (cx, cz) with half extents (hx across, hz along) in the part's own axes (rx, rz) / (fx, fz).
type Top = {
	qx: number,
	qy: number,
	qz: number,
	nx: number,
	ny: number,
	nz: number,
	cx: number,
	cz: number,
	ax: number, -- the road's axis (unit, XZ)
	az: number,
	hx: number,
	hz: number,
}

export type Surface = { cells: { [number]: { Top } } }

local CELL = 32

local function key(i: number, j: number): number
	return (i + 32768) * 65536 + (j + 32768)
end

-- new(roads): every solid segment of every road, in a 32-stud grid.
function RoadSurface.new(roads: { Road }): Surface
	local self: Surface = { cells = {} }
	for _, road in roads do
		if not RoadSurface.SOLID[road.kind] then
			continue
		end
		local offset = (RoadSurface.OFFSET_U[road.kind] or RoadSurface.OFFSET_U.concrete) * S
		local l = RoadSurface.layout(road, offset)
		if l.len <= 0 then
			continue
		end
		local seg = l.len / l.n
		for i = 1, l.n do
			local tm = (i - 0.5) / l.n
			local cx, cz = l.x0 + l.dx * tm, l.z0 + l.dz * tm
			local cy = (l.y[i] + l.y[i + 1]) / 2
			-- the part's up axis: Ry(yaw) * Rx(pitch) * Rz(roll) applied to (0, 1, 0), as Factory places it
			local yaw, pitch, roll = l.yaw, l.pitch[i], l.roll[i]
			local x, y, z = -math.sin(roll), math.cos(roll), 0
			y, z = y * math.cos(pitch) - z * math.sin(pitch), y * math.sin(pitch) + z * math.cos(pitch)
			local c, s = math.cos(yaw), math.sin(yaw)
			x, z = x * c + z * s, -x * s + z * c
			local h = RoadSurface.THICKNESS / 2
			local top: Top = {
				qx = cx + x * h,
				qy = cy + y * h,
				qz = cz + z * h,
				nx = x,
				ny = y,
				nz = z,
				cx = cx,
				cz = cz,
				ax = l.ux,
				az = l.uz,
				hx = road.width / 2,
				hz = math.sqrt(seg * seg + (l.y[i + 1] - l.y[i]) ^ 2) / 2,
			}
			local reach = math.sqrt(top.hx * top.hx + top.hz * top.hz)
			for ci = math.floor((cx - reach) / CELL), math.floor((cx + reach) / CELL) do
				for cj = math.floor((cz - reach) / CELL), math.floor((cz + reach) / CELL) do
					local k = key(ci, cj)
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
	return self
end

-- topAt(surface, x, z, maxY): the highest road top over (x, z) that is not above maxY, or nil.
function RoadSurface.topAt(self: Surface, x: number, z: number, maxY: number): number?
	local best: number? = nil
	local here: { Top } = self.cells[key(math.floor(x / CELL), math.floor(z / CELL))] or {}
	for _, t in here do
		local ox, oz = x - t.cx, z - t.cz
		local along = ox * t.ax + oz * t.az
		local across = ox * t.az - oz * t.ax
		-- the footprint of a part pitched by at most a few degrees: within its half extents (plan view)
		if math.abs(along) <= t.hz and math.abs(across) <= t.hx then
			local y = t.qy - (t.nx * (x - t.qx) + t.nz * (z - t.qz)) / t.ny
			if y <= maxY and (best == nil or y > (best :: number)) then
				best = y
			end
		end
	end
	return best
end

-- rideAt(surface, x, z, floor, maxY): where a tyre rides at (x, z): the drawn road tops over the
-- point (not above maxY) on the `floor` (terrain or deck), each eased in over its last EASE studs
-- from its edge. The tops do not meet exactly: a rolled segment and the next differ by 0.1 to 0.15 st
-- at a lane 15 st off a wide road's centre line, and where one road crosses another the higher one's
-- side edge stands up to 0.3 st proud. A tyre rolls up such a lip over its own radius; drawn on the
-- exact tops a short vehicle's nose flicks by up to 4 degrees in one frame (tools/sim pitch_jump).
-- Within a part, more than EASE from its edges, this is exactly its top. Continuous everywhere.
RoadSurface.EASE = 1.5 -- studs: about a tyre's diameter
function RoadSurface.rideAt(self: Surface, x: number, z: number, floor: number, maxY: number): number
	local found: { { number } } = {}
	local here: { Top } = self.cells[key(math.floor(x / CELL), math.floor(z / CELL))] or {}
	for _, t in here do
		local ox, oz = x - t.cx, z - t.cz
		local along = math.abs(ox * t.ax + oz * t.az)
		local across = math.abs(ox * t.az - oz * t.ax)
		if along <= t.hz and across <= t.hx then
			local y = t.qy - (t.nx * (x - t.qx) + t.nz * (z - t.qz)) / t.ny
			if y <= maxY then
				table.insert(found, { y, math.min(t.hz - along, t.hx - across) })
			end
		end
	end
	if #found > 1 then
		table.sort(found, function(a: { number }, b: { number }): boolean
			return a[1] < b[1]
		end)
	end
	local v = floor
	for _, f in found do
		if f[1] > v then
			v += (f[1] - v) * math.min(1, f[2] / RoadSurface.EASE)
		end
	end
	return v
end

-- ground(surface, heightAt): the height a vehicle's wheel stands on: the drawn road tops over (x, z)
-- within MAX_ABOVE of the terrain (or the deck), eased at their edges (rideAt), else that terrain.
function RoadSurface.ground(self: Surface, heightAt: (x: number, z: number) -> number): (x: number, z: number) -> number
	return function(x: number, z: number): number
		local h = heightAt(x, z)
		local deck = Height.riverDeckAt(x, z)
		if deck and deck > h then
			h = deck
		end
		return RoadSurface.rideAt(self, x, z, h, h + RoadSurface.MAX_ABOVE)
	end
end

return RoadSurface
