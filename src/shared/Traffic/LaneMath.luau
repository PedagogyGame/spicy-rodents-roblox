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
-- Polyline lanes (ambulance, police, event glides) and the stop-line FSM / yield corridor are W1
-- (BUILD_PLAN §4.4 Track B 9). Yaw follows the HTML convention: heading +z is 0, +x is pi/2, -z is pi,
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

export type Lane = {
	id: string,
	shape: string, -- "straight" | "loop"
	axis: string?, -- "x" | "z" (straight)
	coord: number?, -- the fixed coordinate (straight), studs
	startAt: number, -- along the axis, studs (straight)
	endAt: number,
	dir: number, -- +1 / -1 along the axis; 0 = both ways (ping-pong lanes)
	length: number, -- studs
	curve: Curve.Curve?, -- loop lanes
	speeds: { [string]: number }, -- cruise speed per user (studs/s; the max of a range)
}

export type Pose = { x: number, y: number, z: number, yaw: number }

export type Body = { x: number, z: number, yaw: number, width: number, length: number, visible: boolean? }

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
		},
			nil
	end
	if path.closed == true and path.points and path.interpolation then
		local pts = table.create(#path.points)
		for i, p in path.points do
			pts[i] = Curve.vec3(p[1], 0, p[2])
		end
		local curve = Curve.new(pts, true)
		return {
			id = rec.id,
			shape = "loop",
			axis = nil,
			coord = nil,
			startAt = 0,
			endAt = 0,
			dir = 1,
			length = curve:getLength(),
			curve = curve,
			speeds = speedsOf(rec),
		},
			nil
	end
	return nil, "polyline, segment or template lanes are W1"
end

-- load(records): every supported lane by id plus the ids skipped with their reasons.
function LaneMath.load(records: { LaneRecord }): ({ [string]: Lane }, { [string]: string })
	local lanes: { [string]: Lane } = {}
	local skipped: { [string]: string } = {}
	for _, rec in records do
		local lane, reason = LaneMath.fromRecord(rec)
		if lane then
			lanes[rec.id] = lane
		else
			skipped[rec.id] = reason or "unsupported"
		end
	end
	return lanes, skipped
end

function LaneMath.length(lane: Lane): number
	return lane.length
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
	if axis == "x" then
		return { x = along, y = height, z = lane.coord :: number, yaw = yaw }
	end
	return { x = lane.coord :: number, y = height, z = along, yaw = yaw }
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
	if n > lane.length then
		return n - lane.length, true
	end
	return n, false
end

-- pingPong(lane, s, dir, speed, dt) -> s', dir', turned: shuttle motion between the lane ends.
function LaneMath.pingPong(lane: Lane, s: number, dir: number, speed: number, dt: number): (number, number, boolean)
	local n = s + speed * dt * dir
	if n > lane.length then
		return lane.length - (n - lane.length), -1, true
	elseif n < 0 then
		return -n, 1, true
	end
	return n, dir, false
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
