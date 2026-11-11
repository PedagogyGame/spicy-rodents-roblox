--!strict
-- ReplicatedStorage.Shared.Traffic.LaneMath
-- Lane pose, leader/follower, yield corridor, stop-line FSM, ice-cream spline table.
-- Interface (BUILD_PLAN §1.4): pointAt, leader, seesHazard, stopLine
--
-- Pure lane geometry over the compiled lane records (generated/Lanes.luau from
-- data/authored/town/lanes.json; traffic.md §3). W0 (spike S4) covers what the fleet needs to drive:
--   straight lanes {axis, coord, start, end, dir}: length, pose at an arc distance, wrap (one-way,
--   the v5.4 teleport that is never fatal), ping-pong (patrol beat, trolley shuttle);
--   the closed ice-cream loop as a centripetal Catmull-Rom (Routes/Curve, closed) with its 200-division
--   arc table (length 519.92 u, traffic.md verifier 13);
--   trafficVehicleAhead (L15721-15736) and a per-lane leader query.
-- W1 (BUILD_PLAN §4.4 #9) adds the six remaining records: open polylines (legacy ambulance, responder
-- trunk), the incident-police template (resolved per scene by `incidentRoute`), the two event-car segment
-- sets (one lane per car, `<id>#<n>`) and the outer sidewalk set (one lane per sidewalk, `<id>#<n>`), so all
-- 25 compiled records load (36 lanes). `unify(lanes, roads)` applies owner decision 9 (drive on the right
-- everywhere, traffic.md §14 Q1): one-way lanes on the wrong side of their road are mirrored across its
-- centreline (the boulevard), ping-pong vehicle lanes take the right-hand side for each direction (the
-- patrol beat), and vehicle polylines are offset to the right of travel (`POLY_OFFSET`), with a separate
-- reverse geometry so a return trip keeps right too. `seesHazard` is StreetVehicleLogic.seesHazard
-- (traffic.md §5.2) in studs. Yaw follows the HTML convention: heading +z is 0, +x is pi/2, -z is pi,
-- -x is -pi/2 (traffic.md §2.6); Config/Units.yawCFrame adds the engine's pi exactly once.

local Curve = require("../Routes/Curve")
local Units = require("../Config/Units")

local LaneMath = {}

export type Vec3 = Curve.Vec3

export type LaneRecord = {
	id: string,
	path: any,
	dir: string?,
	speed: { [string]: any }?,
	roads: { string }?,
	wrap: string?,
}

-- A polyline as driven: its corner points (`pts`, `cum` along them, kept for the offsets), and the path a
-- vehicle follows, `pieces`: straight runs joined by circular arcs at the corners (LaneMath.CORNER_RADIUS),
-- so the heading turns continuously; `length` is the driven length.
export type Piece = {
	s: number, -- arc distance where the piece starts
	len: number,
	ax: number, -- line: start point and unit direction; arc: centre, radius, start angle and signed sweep
	az: number,
	dx: number,
	dz: number,
	r: number, -- 0 for a line
	a0: number,
	sweep: number,
}
export type Poly = { pts: { { number } }, cum: { number }, length: number, pieces: { Piece } }

export type Lane = {
	id: string,
	source: string?, -- the compiled record id when one record expands into several lanes
	shape: string, -- "straight" | "loop" | "polyline"
	axis: string?, -- "x" | "z" (straight)
	coord: number?, -- the fixed coordinate (straight), studs
	startAt: number, -- along the axis, studs (straight)
	endAt: number,
	dir: number, -- +1 / -1 along the axis; 0 = both ways (ping-pong lanes)
	length: number, -- studs
	curve: Curve.Curve?, -- loop lanes
	speeds: { [string]: number }, -- cruise speed per user (studs/s; the max of a range)
	speedRanges: { [string]: { number } }?, -- {min, max} where the record gives a range
	poly: Poly?, -- polyline geometry in the +1 direction
	polyRev: Poly?, -- polyline geometry walked in reverse (-1), kept right after `unify`
	coordFor: { [number]: number }?, -- ping-pong vehicle lanes after `unify`: the coord per direction
	vehicle: boolean, -- a vehicle lane (handedness applies) rather than a sidewalk or rider lane
	mirrored: boolean?, -- `unify` moved it to the right-hand side
}

export type Pose = { x: number, y: number, z: number, yaw: number }

export type Body = {
	x: number,
	z: number,
	yaw: number,
	width: number,
	length: number,
	visible: boolean?,
	id: any?,
	speed: number?,
}

-- headingYaw(axis, dir): HTML yaw for travel along an axis (traffic.md §2.6: axis x -> dir*pi/2;
-- axis z -> 0 if dir > 0 else pi).
function LaneMath.headingYaw(axis: string, dir: number): number
	if axis == "x" then
		return dir * math.pi / 2
	end
	return if dir > 0 then 0 else math.pi
end

local function parseDir(dir: string?): number
	if dir == nil then
		return 0
	end
	local sign = string.sub(dir, 1, 1)
	if sign == "+" then
		return 1
	elseif sign == "-" then
		return -1
	end
	return 0 -- "both ..." (ping-pong)
end

local function speedsOf(rec: LaneRecord): { [string]: number }
	local out: { [string]: number } = {}
	if rec.speed then
		for user, v in rec.speed do
			if type(v) == "number" then
				out[user] = v
			elseif type(v) == "table" then
				out[user] = math.max(v[1], v[2])
			end
		end
	end
	return out
end

local function rangesOf(rec: LaneRecord): { [string]: { number } }
	local out: { [string]: { number } } = {}
	for user, v in (rec.speed or {}) :: { [string]: any } do
		if type(v) == "table" then
			out[user] = { math.min(v[1], v[2]), math.max(v[1], v[2]) }
		end
	end
	return out
end

-- Sidewalk and rider lanes are not vehicle lanes (handedness and the fleet ignore them).
function LaneMath.isVehicleLane(id: string): boolean
	return not (string.sub(id, 1, 8) == "sidewalk" or string.sub(id, 1, 7) == "novelty")
end

LaneMath.LOOP_ARC_DIVISIONS = 4000 -- arc-length table of loop lanes (the ice cream loop: 0.3 st apart)
LaneMath.POLY_OFFSET = Units.st(3) -- keep-right offset for centreline polylines (inside an 18 u road's right half)

LaneMath.CORNER_RADIUS = Units.st(8) -- 20 st: a street corner taken inside an 18 u road

-- The driven path through `pts`: every corner is cut by an arc of CORNER_RADIUS tangent to both legs, or a
-- smaller one where a leg is too short (a leg between two corners gives each half of itself; the first
-- and last legs give all of theirs). A path that turned on the spot at each corner (v5.4's polylines) spun
-- the vehicle 90 degrees in one tick and slid it sideways through the turn on screen.
local function pieces(pts: { { number } }): { Piece }
	local n = #pts
	-- drop zero-length legs
	local p: { { number } } = { pts[1] }
	for i = 2, n do
		local a, b = p[#p], pts[i]
		if (b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2 > 1e-18 then
			table.insert(p, b)
		end
	end
	n = #p
	local out: { Piece } = {}
	if n < 2 then
		local q = pts[1]
		return { { s = 0, len = 0, ax = q[1], az = q[2], dx = 0, dz = 1, r = 0, a0 = 0, sweep = 0 } }
	end
	local lens, dirs = {}, {}
	for i = 1, n - 1 do
		local dx, dz = p[i + 1][1] - p[i][1], p[i + 1][2] - p[i][2]
		local len = math.sqrt(dx * dx + dz * dz)
		lens[i], dirs[i] = len, { dx / len, dz / len }
	end
	-- the tangent length cut from each side of every interior corner
	local cut, radius, turn = { [1] = 0, [n] = 0 }, {}, {}
	for i = 2, n - 1 do
		local d0, d1 = dirs[i - 1], dirs[i]
		local cross = d0[1] * d1[2] - d0[2] * d1[1]
		local dot = math.clamp(d0[1] * d1[1] + d0[2] * d1[2], -1, 1)
		local theta = math.atan2(cross, dot) -- signed turn
		turn[i] = theta
		local half = math.tan(math.abs(theta) / 2)
		if math.abs(theta) < 1e-6 or half > 1e6 then
			cut[i], radius[i] = 0, 0
		else
			local room = math.min(
				if i - 1 == 1 then lens[i - 1] else lens[i - 1] / 2,
				if i == n - 1 then lens[i] else lens[i] / 2
			)
			local r = math.min(LaneMath.CORNER_RADIUS, room / half)
			cut[i], radius[i] = r * half, r
		end
	end
	local s = 0
	local function line(x: number, z: number, d: { number }, len: number)
		if len > 1e-9 then
			table.insert(out, { s = s, len = len, ax = x, az = z, dx = d[1], dz = d[2], r = 0, a0 = 0, sweep = 0 })
			s += len
		end
	end
	for i = 1, n - 1 do
		local d = dirs[i]
		local x0, z0 = p[i][1] + d[1] * cut[i], p[i][2] + d[2] * cut[i]
		line(x0, z0, d, lens[i] - cut[i] - cut[i + 1])
		local j = i + 1
		if j < n and radius[j] > 0 then
			-- the arc from the end of leg i to the start of leg j, turning by turn[j]
			local r, theta = radius[j], turn[j]
			local sx, sz = p[j][1] - d[1] * cut[j], p[j][2] - d[2] * cut[j]
			-- the centre is r to the side the path turns towards: left of (dx, dz) is (-dz, dx) here
			local side = if theta > 0 then 1 else -1
			local cx, cz = sx - d[2] * r * side, sz + d[1] * r * side
			local a0 = math.atan2(sz - cz, sx - cx)
			table.insert(
				out,
				{ s = s, len = r * math.abs(theta), ax = cx, az = cz, dx = 0, dz = 0, r = r, a0 = a0, sweep = theta }
			)
			s += r * math.abs(theta)
		end
	end
	if #out == 0 then
		table.insert(
			out,
			{ s = 0, len = 0, ax = p[1][1], az = p[1][2], dx = dirs[1][1], dz = dirs[1][2], r = 0, a0 = 0, sweep = 0 }
		)
	end
	return out
end

function LaneMath.poly(pts: { { number } }): Poly
	local cum = { 0 }
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		cum[i] = cum[i - 1] + math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
	end
	local ps = pieces(pts)
	local last = ps[#ps]
	return { pts = pts, cum = cum, length = last.s + last.len, pieces = ps }
end

-- offsetRight(pts, d): the polyline moved d to the RIGHT of travel (right of heading f = (fx, fz) is
-- (-fz, fx)... in this right-handed, Y-up frame the right of +z is -x and the right of +x is +z, i.e.
-- right = (-fz, fx)), with mitred corners (the offset legs' intersection).
function LaneMath.offsetRight(pts: { { number } }, d: number): { { number } }
	local n = #pts
	if n < 2 or d == 0 then
		return table.clone(pts)
	end
	local normals = {}
	for i = 1, n - 1 do
		local a, b = pts[i], pts[i + 1]
		local dx, dz = b[1] - a[1], b[2] - a[2]
		local len = math.sqrt(dx * dx + dz * dz)
		if len < 1e-9 then
			normals[i] = if i > 1 then normals[i - 1] else { 0, 0 }
		else
			normals[i] = { -dz / len, dx / len }
		end
	end
	local out = table.create(n)
	for i = 1, n do
		local p = pts[i]
		if i == 1 or i == n then
			local nm = normals[if i == 1 then 1 else n - 1]
			out[i] = { p[1] + nm[1] * d, p[2] + nm[2] * d }
		else
			local n0, n1 = normals[i - 1], normals[i]
			local mx, mz = n0[1] + n1[1], n0[2] + n1[2]
			local dot = 1 + n0[1] * n1[1] + n0[2] * n1[2] -- = |m|^2 / 2 for unit normals
			if dot < 1e-6 then -- a U-turn: fall back to the first leg's normal
				out[i] = { p[1] + n0[1] * d, p[2] + n0[2] * d }
			else
				out[i] = { p[1] + mx * d / dot, p[2] + mz * d / dot }
			end
		end
	end
	return out
end

local function reversed(pts: { { number } }): { { number } }
	local out = table.create(#pts)
	for i = #pts, 1, -1 do
		table.insert(out, pts[i])
	end
	return out
end

local function polylineLane(rec: LaneRecord, id: string, pts: { { number } }, dir: number): Lane
	local poly = LaneMath.poly(pts)
	return {
		id = id,
		source = if id ~= rec.id then rec.id else nil,
		shape = "polyline",
		axis = nil,
		coord = nil,
		startAt = 0,
		endAt = poly.length,
		dir = dir,
		length = poly.length,
		curve = nil,
		speeds = speedsOf(rec),
		speedRanges = rangesOf(rec),
		poly = poly,
		polyRev = LaneMath.poly(reversed(pts)),
		vehicle = LaneMath.isVehicleLane(rec.id),
	}
end

-- makeRoute(id, pts, speeds, offset?): an ad-hoc polyline vehicle lane (a dispatched trip), kept right
-- by `offset` (default POLY_OFFSET) in both directions like a unified record polyline.
function LaneMath.makeRoute(id: string, pts: { { number } }, speeds: { [string]: number }, offset: number?): Lane
	local d = offset or LaneMath.POLY_OFFSET
	local poly = LaneMath.poly(LaneMath.offsetRight(pts, d))
	return {
		id = id,
		source = nil,
		shape = "polyline",
		axis = nil,
		coord = nil,
		startAt = 0,
		endAt = poly.length,
		dir = 1,
		length = poly.length,
		curve = nil,
		speeds = speeds,
		poly = poly,
		polyRev = LaneMath.poly(LaneMath.offsetRight(reversed(pts), d)),
		vehicle = true,
		mirrored = d ~= 0,
	}
end

-- incidentRoute(rec, car, start, scene) -> points (traffic.md §5.10): start -> (-300 u, start.z) ->
-- (-300 u, p.z + 10 u) -> (p.x -/+ 9 u, p.z + 10 u). `car` is 0 or 1; positions in studs.
function LaneMath.incidentRoute(car: number, start: { number }, scene: { number }): { { number } }
	local st = Units.st
	local side = if car == 0 then -1 else 1
	return {
		{ start[1], start[2] },
		{ st(-300), start[2] },
		{ st(-300), scene[2] + st(10) },
		{ scene[1] + side * st(9), scene[2] + st(10) },
	}
end

-- fromRecord(rec): a Lane, or nil plus the reason when the shape is not supported yet.
function LaneMath.fromRecord(rec: LaneRecord): (Lane?, string?)
	local path = rec.path
	if type(path) ~= "table" then
		return nil, "no path"
	end
	if path.axis then
		local s, e = path.start, path["end"]
		return {
			id = rec.id,
			shape = "straight",
			axis = path.axis,
			coord = path.coord,
			startAt = s,
			endAt = e,
			dir = parseDir(rec.dir),
			length = math.abs(e - s),
			curve = nil,
			speeds = speedsOf(rec),
			speedRanges = rangesOf(rec),
			vehicle = LaneMath.isVehicleLane(rec.id),
		},
			nil
	end
	if path.closed == true and path.points and path.interpolation then
		local pts = table.create(#path.points)
		for i, p in path.points do
			pts[i] = Curve.vec3(p[1], 0, p[2])
		end
		local curve = Curve.new(pts, true)
		local length = curve:getLength() -- v5.4's 200-division length (traffic.md verifier 13)
		-- ...but a vehicle drives it by arc length, and 200 divisions are 6.5 st each on this loop: inside
		-- one, the raw parameter's speed changes sharply where the long straights meet the tight U-turn
		-- knots, so the van surged and dragged by up to 30 % going into each U-turn. A dense table maps arc
		-- length to the parameter evenly (the length moves by under 0.1 %; `length` stays v5.4's).
		curve.arcLengthDivisions = LaneMath.LOOP_ARC_DIVISIONS
		curve._lengths = nil
		return {
			id = rec.id,
			shape = "loop",
			axis = nil,
			coord = nil,
			startAt = 0,
			endAt = 0,
			dir = 1,
			length = length,
			curve = curve,
			speeds = speedsOf(rec),
			speedRanges = rangesOf(rec),
			vehicle = LaneMath.isVehicleLane(rec.id),
		},
			nil
	end
	if path.points and path.closed == false then
		return polylineLane(rec, rec.id, path.points, 1), nil
	end
	if path.points_template then
		-- the default resolution (car 0 from the station to a scene at the origin); dispatches resolve
		-- their own scene with `incidentRoute`
		local start = if path.resolved_start then path.resolved_start[1] else { 0, 0 }
		return polylineLane(rec, rec.id, LaneMath.incidentRoute(0, start, { 0, 0 }), 1), nil
	end
	return nil, "multi-lane record: use expand"
end

-- expand(rec): every lane a record yields (segments and lane sets give one lane per member).
function LaneMath.expand(rec: LaneRecord): ({ Lane }, string?)
	local path = rec.path
	if type(path) == "table" and path.segments then
		local out = {}
		local d = parseDir(rec.dir)
		for i, seg in path.segments do
			table.insert(out, polylineLane(rec, `{rec.id}#{i}`, seg, if d == 0 then 1 else d))
		end
		return out, nil
	end
	if type(path) == "table" and path.lanes then
		local out = {}
		for i, l in path.lanes do
			local sub = table.clone(rec)
			sub.id = `{rec.id}#{i}`
			sub.path = { axis = l.axis, coord = l.coord, start = path.start, ["end"] = path["end"] }
			local lane = LaneMath.fromRecord(sub)
			if lane then
				lane.source = rec.id
				table.insert(out, lane)
			end
		end
		return out, nil
	end
	local lane, reason = LaneMath.fromRecord(rec)
	if lane then
		return { lane }, nil
	end
	return {}, reason
end

-- load(records): every lane by id (expanded) plus the record ids skipped with their reasons.
function LaneMath.load(records: { LaneRecord }): ({ [string]: Lane }, { [string]: string })
	local lanes: { [string]: Lane } = {}
	local skipped: { [string]: string } = {}
	for _, rec in records do
		local list, reason = LaneMath.expand(rec)
		if #list == 0 then
			skipped[rec.id] = reason or "unsupported"
		end
		for _, lane in list do
			lanes[lane.id] = lane
		end
	end
	return lanes, skipped
end

export type RoadRecord = {
	id: string,
	axis: string,
	coord: any,
	width: number?,
	kind: string?,
	start: number?,
	["end"]: number?,
}

-- A lane that runs beside a rail road keeps its vehicles' centreline this far from the rail's: the
-- trolley's half width (1.75 u) plus the widest lane vehicle's (the dump truck, 1.675 u) plus 0.125 u.
-- Under drive-on-the-right the boulevard's eastbound lane (z = +5.6 u) sits on the trolley's side (track
-- z = 8.65 u): a dump truck passing the trolley was 0.94 st inside it.
LaneMath.RAIL_CLEARANCE = Units.st(3.55)

-- unify(lanes, roads, records?): drive on the right everywhere (owner decision 9). Returns the ids changed.
-- Straight one-way lanes compare their coord with their road's centreline (the record's first road);
-- ping-pong vehicle lanes get coordFor[+1] / coordFor[-1]; vehicle polylines are offset right.
function LaneMath.unify(lanes: { [string]: Lane }, roads: { RoadRecord }, records: { LaneRecord }): { string }
	local roadCoord: { [string]: number } = {}
	for _, r in roads do
		if type(r.coord) == "number" then
			roadCoord[r.id] = r.coord
		end
	end
	local recRoad: { [string]: number } = {}
	for _, rec in records do
		local first = if type(rec.roads) == "table" then rec.roads[1] else nil
		if first and roadCoord[first] then
			recRoad[rec.id] = roadCoord[first]
		end
	end
	local rails: { RoadRecord } = {}
	for _, r in roads do
		if r.kind == "rail" and type(r.coord) == "number" and r.start and r["end"] then
			table.insert(rails, r)
		end
	end
	-- coord, pulled away from any parallel rail alongside the lane's extent
	local function clearOfRails(lane: Lane, coord: number): number
		local lo, hi = math.min(lane.startAt, lane.endAt), math.max(lane.startAt, lane.endAt)
		for _, r in rails do
			local rlo, rhi =
				math.min(r.start :: number, r["end"] :: number), math.max(r.start :: number, r["end"] :: number)
			local rc = r.coord :: number
			if r.axis == lane.axis and rlo < hi and rhi > lo and math.abs(coord - rc) < LaneMath.RAIL_CLEARANCE then
				coord = rc + (if coord < rc then -1 else 1) * LaneMath.RAIL_CLEARANCE
			end
		end
		return coord
	end
	local changed = {}
	for id, lane in lanes do
		if not lane.vehicle then
			continue
		end
		if lane.shape == "straight" then
			local road = recRoad[lane.source or id]
			local coord = lane.coord :: number
			if road == nil or math.abs(coord - road) < 1e-9 then
				continue -- on its own centreline (the trolley's track): nothing to choose
			end
			local off = math.abs(coord - road)
			-- right of +z is -x; right of +x is +z
			local function rightCoord(d: number): number
				if lane.axis == "z" then
					return clearOfRails(lane, road - d * off)
				end
				return clearOfRails(lane, road + d * off)
			end
			if lane.dir == 0 then
				lane.coordFor = { [1] = rightCoord(1), [-1] = rightCoord(-1) }
				table.insert(changed, id)
			else
				local want = rightCoord(lane.dir)
				if math.abs(want - coord) > 1e-9 then
					lane.coord = want
					lane.mirrored = true
					table.insert(changed, id)
				end
			end
		elseif lane.shape == "polyline" and not lane.source then
			local poly = lane.poly :: Poly
			lane.poly = LaneMath.poly(LaneMath.offsetRight(poly.pts, LaneMath.POLY_OFFSET))
			lane.polyRev = LaneMath.poly(LaneMath.offsetRight(reversed(poly.pts), LaneMath.POLY_OFFSET))
			lane.length = (lane.poly :: Poly).length
			lane.endAt = lane.length
			lane.mirrored = true
			table.insert(changed, id)
		end
	end
	table.sort(changed)
	return changed
end

function LaneMath.length(lane: Lane, dir: number?): number
	if lane.shape == "polyline" and dir == -1 then
		return (lane.polyRev :: Poly).length
	end
	return lane.length
end

-- polyPoint(poly, s): position and heading at arc distance s (clamped to the ends).
function LaneMath.polyPoint(poly: Poly, s: number): (number, number, number)
	local ps = poly.pieces
	if ps then
		local d = math.clamp(s, 0, poly.length)
		local lo, hi = 1, #ps
		while lo < hi do -- the last piece starting at or before d
			local mid = (lo + hi + 1) // 2
			if ps[mid].s <= d then
				lo = mid
			else
				hi = mid - 1
			end
		end
		local pc = ps[lo]
		local k = math.clamp(d - pc.s, 0, pc.len)
		if pc.r == 0 then
			return pc.ax + pc.dx * k, pc.az + pc.dz * k, math.atan2(pc.dx, pc.dz)
		end
		-- on the arc: the angle round the centre advances by sweep * k / len; the heading is the tangent
		local sign = if pc.sweep > 0 then 1 else -1
		local a = pc.a0 + sign * k / pc.r
		local x, z = pc.ax + pc.r * math.cos(a), pc.az + pc.r * math.sin(a)
		local tx, tz = -math.sin(a) * sign, math.cos(a) * sign
		return x, z, math.atan2(tx, tz)
	end
	local pts, cum = poly.pts, poly.cum
	local n = #pts
	if n == 1 then
		return pts[1][1], pts[1][2], 0
	end
	local d = math.clamp(s, 0, poly.length)
	local i = 1
	while i < n - 1 and cum[i + 1] < d do
		i += 1
	end
	-- skip zero-length legs for the heading
	local a, b = pts[i], pts[i + 1]
	local seg = cum[i + 1] - cum[i]
	local t = if seg > 1e-12 then (d - cum[i]) / seg else 0
	local x, z = a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t
	return x, z, math.atan2(b[1] - a[1], b[2] - a[2])
end

-- halfTurn(x, z, yaw, r, d) -> pose: d studs into a left U-turn of radius r that starts at (x, z) heading
-- `yaw` and ends 2r to its left heading the other way (the right of heading f is (-fz, fx), its left
-- (fz, -fx)).
function LaneMath.halfTurn(x: number, z: number, yaw: number, r: number, d: number): Pose
	local fx, fz = math.sin(yaw), math.cos(yaw)
	local lx, lz = fz, -fx
	local phi = math.clamp(d / math.max(r, 1e-9), 0, math.pi)
	local c, sn = math.cos(phi), math.sin(phi)
	local px = x + r * lx * (1 - c) + r * fx * sn
	local pz = z + r * lz * (1 - c) + r * fz * sn
	local tx, tz = lx * sn + fx * c, lz * sn + fz * c
	return { x = px, y = 0, z = pz, yaw = math.atan2(tx, tz) }
end

-- cornerCap(lane, dir, s, lateral, decel) -> speed: the fastest a vehicle at s may go so that it can
-- slow, at `decel`, to take every rounded corner ahead at `lateral` sideways acceleration (math.huge on
-- lanes without corners).
function LaneMath.cornerCap(lane: Lane, dir: number, s: number, lateral: number, decel: number): number
	if lane.shape ~= "polyline" then
		return math.huge
	end
	local poly = if dir < 0 then lane.polyRev :: Poly else lane.poly :: Poly
	local cap = math.huge
	for _, pc in poly.pieces do
		if pc.r > 0 and pc.s + pc.len > s then
			local dist = math.max(0, pc.s - s)
			local v = math.sqrt(lateral * pc.r)
			cap = math.min(cap, math.sqrt(v * v + 2 * decel * dist))
		end
	end
	return cap
end

-- pointAt(lane, s, dir?, y?) -> pose: s studs along the lane from its start end in the travel
-- direction (`dir` overrides the lane's own for ping-pong lanes); straight lanes measure from `startAt`
-- for +1 and from `endAt` for -1. Loop lanes take s modulo the length.
function LaneMath.pointAt(lane: Lane, s: number, dir: number?, y: number?): Pose
	local d = dir or lane.dir
	if d == 0 then
		d = 1
	end
	local height = y or 0
	if lane.shape == "polyline" then
		local poly = if d < 0 then lane.polyRev :: Poly else lane.poly :: Poly
		local x, z, yaw = LaneMath.polyPoint(poly, s)
		return { x = x, y = height, z = z, yaw = yaw }
	end
	if lane.shape == "loop" then
		local curve = lane.curve :: Curve.Curve
		local u = (s / lane.length) % 1
		if u < 0 then
			u += 1
		end
		local p = curve:getPointAt(u)
		local tan = curve:getTangentAt(u)
		return { x = p.x, y = height, z = p.z, yaw = math.atan2(tan.x * d, tan.z * d) }
	end
	local axis = lane.axis :: string
	local along = if d > 0 then lane.startAt + s else lane.endAt - s
	local yaw = LaneMath.headingYaw(axis, d)
	local coord = if lane.coordFor then lane.coordFor[d] else lane.coord :: number
	if axis == "x" then
		return { x = along, y = height, z = coord, yaw = yaw }
	end
	return { x = coord, y = height, z = along, yaw = yaw }
end

-- advance(lane, s, speed, dt) -> s', wrapped: one-way motion; past the end the vehicle wraps to the
-- start (the v5.4 teleport, flagged so the swept test skips it).
function LaneMath.advance(lane: Lane, s: number, speed: number, dt: number): (number, boolean)
	local n = s + speed * dt
	if lane.shape == "loop" then
		if n >= lane.length then
			return n - lane.length, false -- a loop is continuous: no teleport
		end
		return n, false
	end
	if lane.shape == "polyline" then
		return math.min(n, lane.length), false -- polylines end; the caller decides what happens next
	end
	if n > lane.length then
		return n - lane.length, true
	end
	return n, false
end

-- arcOf(lane, x, z, dir?) -> s: the arc distance of the lane point nearest (x, z) (straight lanes: the
-- projection; polylines: the nearest leg; loops: a 200-sample search). Used to seat fleet spawns given
-- in world coordinates (traffic.md §2.2) and the stop lines.
function LaneMath.arcOf(lane: Lane, x: number, z: number, dir: number?): number
	local d = dir or lane.dir
	if d == 0 then
		d = 1
	end
	if lane.shape == "straight" then
		local along = if lane.axis == "x" then x else z
		local s = if d > 0 then along - lane.startAt else lane.endAt - along
		return math.clamp(s, 0, lane.length)
	end
	local best, bestD = 0, math.huge
	local n = if lane.shape == "loop" then 200 else math.max(2, math.ceil(LaneMath.length(lane, d) / 2))
	local len = LaneMath.length(lane, d)
	for i = 0, n do
		local s = len * i / n
		local p = LaneMath.pointAt(lane, s, d)
		local dd = (p.x - x) ^ 2 + (p.z - z) ^ 2
		if dd < bestD then
			best, bestD = s, dd
		end
	end
	return best
end

export type Hazard = { x: number, z: number, r: number }

-- seesHazard(px, pz, fx, fz, range, halfWidth, hazards, rear?) (StreetVehicleLogic.seesHazard, traffic.md
-- §5.2, L7493-7536): a candidate is a hazard if -rear < along < range + r and lateral < halfWidth + r.
-- (fx, fz) must be a unit heading. `rear` defaults to 0.55 u in studs. Returns the first hazard hit.
function LaneMath.seesHazard(
	px: number,
	pz: number,
	fx: number,
	fz: number,
	range: number,
	halfWidth: number,
	hazards: { Hazard },
	rear: number?
): Hazard?
	local back = rear or Units.st(0.55)
	for _, h in hazards do
		local dx, dz = h.x - px, h.z - pz
		local along = dx * fx + dz * fz
		if along > -back and along < range + h.r then
			local lateral = math.abs(dx * fz - dz * fx)
			if lateral < halfWidth + h.r then
				return h
			end
		end
	end
	return nil
end

-- pingPong(lane, s, dir, speed, dt) -> s', dir', turned: shuttle motion between the lane ends. `s` is
-- measured in the travel direction's own frame, as `pointAt`, `arcOf` and the stop lines measure it (from
-- `startAt` for +1, from `endAt` for -1), so it always grows; past the end the vehicle comes back the other
-- way from that same end: s' is the overshoot in the new direction's frame. (It used to reflect s in the
-- old frame, which `pointAt` then read from the far end: the patrol car jumped the whole beat at every
-- turn and drove the next leg backwards.)
function LaneMath.pingPong(lane: Lane, s: number, dir: number, speed: number, dt: number): (number, number, boolean)
	local n = s + math.abs(speed) * dt
	if n > lane.length then
		return math.min(n - lane.length, lane.length), -dir, true
	end
	return n, dir, false
end

-- uturnLength(lane): the arc length of the U-turn that joins the end of one direction of a ping-pong lane
-- to the start of the other (a half circle between `coordFor[1]` and `coordFor[-1]`); 0 when both
-- directions share one line.
function LaneMath.uturnLength(lane: Lane): number
	local cf = lane.coordFor
	if not cf then
		return 0
	end
	return math.pi * math.abs(cf[1] - cf[-1]) / 2
end

-- uturnPoint(lane, dir, d) -> pose: d studs into the U-turn at the far end of direction `dir` (a left turn
-- under drive-on-the-right): a half circle, beyond the lane's end, from the dir side to the -dir side.
function LaneMath.uturnPoint(lane: Lane, dir: number, d: number): Pose
	local cf = lane.coordFor :: { [number]: number }
	local r = math.abs(cf[1] - cf[-1]) / 2
	local mid = (cf[1] + cf[-1]) / 2
	local endAlong = if dir > 0 then lane.endAt else lane.startAt
	local phi = math.clamp(d / math.max(r, 1e-9), 0, math.pi)
	-- in (along, coord) coordinates: forward is (dir, 0); out from the centre to the start is (0, u)
	local u = if cf[dir] > mid then 1 else -1
	local along = endAlong + dir * r * math.sin(phi)
	local coord = mid + u * r * math.cos(phi)
	local tAlong, tCoord = dir * math.cos(phi), -u * math.sin(phi)
	if lane.axis == "x" then
		return { x = along, y = 0, z = coord, yaw = math.atan2(tAlong, tCoord) }
	end
	return { x = coord, y = 0, z = along, yaw = math.atan2(tCoord, tAlong) }
end

-- vehicleAhead(me, fx, fz, range, halfWidth, others) (trafficVehicleAhead, L15721-15736): is another
-- visible body in the corridor ahead of `me` along (fx, fz)? Lengths in the caller's unit; the lateral
-- margin 0.2 u is scaled by `scale` (default 2.5).
function LaneMath.vehicleAhead(
	me: Body,
	fx: number,
	fz: number,
	range: number,
	halfWidth: number,
	others: { Body },
	scale: number?
): boolean
	local margin = 0.2 * (scale or Units.STUDS_PER_UNIT)
	for _, item in others do
		if item ~= me and item.visible ~= false then
			local dx, dz = item.x - me.x, item.z - me.z
			local along = dx * fx + dz * fz
			local across = math.abs(dx * fz - dz * fx)
			local psi = item.yaw
			local otherAlong = math.abs(math.sin(psi) * fx + math.cos(psi) * fz) * item.length / 2
				+ math.abs(math.cos(psi) * fx - math.sin(psi) * fz) * item.width / 2
			if along > 0 and along < range + otherAlong and across < halfWidth + item.width / 2 + margin then
				return true
			end
		end
	end
	return false
end

-- leader(s, dir, others): among bodies on the same lane (their arc distances), the nearest one ahead
-- in the travel direction and the gap to it (nil when alone).
function LaneMath.leader(s: number, dir: number, others: { { s: number } }): ({ s: number }?, number)
	local best: { s: number }? = nil
	local bestGap = math.huge
	for _, o in others do
		local gap = (o.s - s) * dir
		if gap > 0 and gap < bestGap then
			bestGap = gap
			best = o
		end
	end
	return best, bestGap
end

return LaneMath
