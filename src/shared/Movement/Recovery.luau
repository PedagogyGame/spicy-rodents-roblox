--!strict
-- ReplicatedStorage.Shared.Movement.Recovery
-- River-fall recovery, the last-safe-position history, "unstick" for the Reset button and the
-- push-off when a parked car carrying riders moves (BUILD_PLAN §1.4, §4.4 #5).
-- * riverFall(x, y, z): v5.4 recoverRiverFall (L14116-14132): inside the river water and at or below
--   waterY + 0.45 u, the body goes to the nearer quay: x = riverCenter(z') + side * (halfWidth + 5),
--   y = bankY + 0.18, z' = clamp(z, -225, 425) (HTML units), velocity zeroed. Kept for squirrels and
--   people alike (worldgen_districts_art §16 "keep the teleport to nearer quay rule").
-- * History: a ring of grounded, sane positions sampled every `interval` seconds; `safePos` is the
--   newest, `unstick` the newest at least `minAway` studs from where the body is stuck.
-- * Reset routing: `resetTarget(history, x, y, z)` picks river recovery, else unstick, else stay.
-- * onVehicleMoved(car, riders): riders standing on a car's roof are pushed off to the nearer side.
-- * riverEntry(from, x, y, z, t, speed, gravity, slack, ySlack?): is (x, y, z) the quay spot riverFall gives (within
--   `slack` across, `ySlack` up) for a fall into the water at a point a body at `from` (the server's own last place of
--   it: x, y, z, its vertical speed, on a rail or not) could have reached in `t` seconds (across at `speed`, down as
--   gravity takes it, or at `speed` off a rail)? The water point it went in at (the nearest such), else nil. The
--   server's MoveValidator takes the client's own recovery as honest with it (validator round 7: the body must have
--   been able to reach the water; the old rule, riverLanding, asked only that the water lay within reach, and a quay
--   spot is itself within reach of the water, so landings chained along the quay at 112 to 296 st/s).
-- Interface: riverFall(x, y, z) -> (x, y, z)?, riverEntry(from, x, y, z, t, speed, gravity, slack, ySlack?) ->
--   (x, y, z)?, QUAY_Y, newHistory(capacity?, interval?), record(h, t, x, y,
--   z, grounded), safePos(h), unstick(h, x, y, z, minAway?), resetTarget(h, x, y, z), isSane(x, y, z),
--   onVehicleMoved(car, riders) -> { { id, x, z } }
-- Pure; studs. No side effects on require.

local Height = require("../World/Height")

export type Sample = { t: number, x: number, y: number, z: number }
export type History = {
	capacity: number,
	interval: number,
	ring: { Sample },
	head: number, -- index of the newest sample (0 = empty)
	count: number,
	lastT: number,
}

local Recovery = {}

local S = Height.STUDS_PER_UNIT
local R = Height.RIVER

-- Positions below this are lost (below the river bed and the sewer floor, §1.2 FallenPartsDestroyHeight).
Recovery.FLOOR_Y = (R.bedY - 6) * S

function Recovery.isSane(x: number, y: number, z: number): boolean
	return x == x and y == y and z == z and math.abs(x) < 1e5 and math.abs(z) < 1e5 and y > Recovery.FLOOR_Y
end

-- v5.4 recoverRiverFall in studs; nil when the body is not in the river.
function Recovery.riverFall(x: number, y: number, z: number): (number?, number?, number?)
	local ux, uy, uz = x / S, y / S, z / S
	if not Height.insideRiverWaterU(ux, uz) or uy > R.waterY + 0.45 then
		return nil, nil, nil
	end
	local side = if ux < Height.riverCenterU(uz) then -1 else 1
	local cz = math.clamp(uz, -225, 425)
	return (Height.riverCenterU(cz) + side * (R.halfWidth + 5)) * S, (R.bankY + 0.18) * S, cz * S
end

-- the quay's height (studs): where riverFall puts the feet
Recovery.QUAY_Y = (R.bankY + 0.18) * S

-- the server's own last place of a body (riverEntry's `from`)
export type From = { x: number, y: number, z: number, vy: number, onRail: boolean }

-- riverEntry(from, x, y, z, t, speed, gravity, slack, ySlack?) -> (wx, wy, wz)?: (above) the water point nearest `from`
-- whose riverFall spot is (x, y, z), when the body could have reached it: across within speed * t (+ slack), and down to
-- the recovery height (waterY + 0.45 u) in t: falling from its own downward speed (none up: a leap only delays it), or
-- at `speed` off a rail. riverFall's spot for a water point: x on the quay line of the side of the centre line it is on,
-- y the quay, z its own clamped to the quay's ends (a point past an end lands at that end).
function Recovery.riverEntry(
	from: From,
	x: number,
	y: number,
	z: number,
	t: number,
	speed: number,
	gravity: number,
	slack: number,
	ySlack: number?
): (number?, number?, number?)
	if math.abs(y - Recovery.QUAY_Y) > (ySlack or slack) or t < 0 then
		return nil, nil, nil
	end
	local cU = Height.riverCenterU(z / S)
	local side = if x / S < cU then -1 else 1
	if math.abs(x - (cU + side * (R.halfWidth + 5)) * S) > slack then
		return nil, nil, nil
	end
	local zLo, zHi = -225 * S, 425 * S
	if z < zLo - slack or z > zHi + slack then
		return nil, nil, nil
	end
	-- (the water's z for that spot: its own, or anywhere past the quay's end it is at)
	local wzLo, wzHi = z - slack, z + slack
	if z <= zLo + slack then
		wzLo = R.zMin * S
	end
	if z >= zHi - slack then
		wzHi = R.zMax * S
	end
	wzLo, wzHi = math.max(wzLo, R.zMin * S), math.min(wzHi, R.zMax * S)
	if wzLo > wzHi then
		return nil, nil, nil
	end
	local wz = math.clamp(from.z, wzLo, wzHi)
	local c = Height.riverCenterU(wz / S) * S
	local hw = R.halfWidth * S - 1e-3
	local wx = if side < 0 then math.clamp(from.x, c - hw, c) else math.clamp(from.x, c, c + hw)
	if math.sqrt((wx - from.x) ^ 2 + (wz - from.z) ^ 2) > speed * t + slack then
		return nil, nil, nil
	end
	local wy = (R.waterY + 0.45) * S
	local drop = from.y - wy
	if drop > 0 then
		local v0 = math.max(0, -from.vy)
		local tFall = (-v0 + math.sqrt(v0 * v0 + 2 * gravity * drop)) / gravity
		if from.onRail then
			tFall = math.min(tFall, drop / math.max(speed, 1e-6))
		end
		-- (a frame's grace: the motor's fall is stepped, a little ahead of the exact one)
		if tFall > t + 1 / 60 then
			return nil, nil, nil
		end
	end
	return wx, math.min(from.y, wy), wz
end

function Recovery.newHistory(capacity: number?, interval: number?): History
	local cap = capacity or 20
	return {
		capacity = cap,
		interval = interval or 0.5,
		ring = table.create(cap),
		head = 0,
		count = 0,
		lastT = -math.huge,
	}
end

-- record(h, t, x, y, z, grounded): keeps a grounded, sane, dry sample at most every `interval` s.
function Recovery.record(h: History, t: number, x: number, y: number, z: number, grounded: boolean): boolean
	if not grounded or t - h.lastT < h.interval or not Recovery.isSane(x, y, z) then
		return false
	end
	if Height.insideRiverWater(x, z) then
		return false
	end
	h.head = h.head % h.capacity + 1
	h.ring[h.head] = { t = t, x = x, y = y, z = z }
	h.count = math.min(h.capacity, h.count + 1)
	h.lastT = t
	return true
end

function Recovery.safePos(h: History): Sample?
	if h.count == 0 then
		return nil
	end
	return h.ring[h.head]
end

-- unstick(h, x, y, z, minAway): the newest sample at least minAway studs (default 4) from (x, z).
function Recovery.unstick(h: History, x: number, _y: number, z: number, minAway: number?): Sample?
	local m = minAway or 4
	local idx = h.head
	for _ = 1, h.count do
		local s = h.ring[idx]
		local dx, dz = s.x - x, s.z - z
		if dx * dx + dz * dz >= m * m then
			return s
		end
		idx = if idx == 1 then h.capacity else idx - 1
	end
	return nil
end

-- resetTarget: what the Reset button does (never a kill, never a respawn): river -> quay; insane
-- or stuck -> last safe position away from here; else the newest safe sample; else stay put.
function Recovery.resetTarget(h: History, x: number, y: number, z: number): (number, number, number, string)
	local rx, ry, rz = Recovery.riverFall(x, y, z)
	if rx and ry and rz then
		return rx, ry, rz, "river"
	end
	local s = Recovery.unstick(h, x, y, z) or Recovery.safePos(h)
	if s then
		return s.x, s.y, s.z, "safe"
	end
	return x, y, z, "stay"
end

export type CarBox = { x: number, z: number, yaw: number, width: number, length: number, top: number }
export type Rider = { id: string, x: number, y: number, z: number }

-- onVehicleMoved(car, riders): riders standing on the roof (inside the box, within 1.5 st of the top)
-- are pushed off to the nearer side, 1.2 st clear of the box.
function Recovery.onVehicleMoved(car: CarBox, riders: { Rider }): { { id: string, x: number, z: number } }
	local out = {}
	local fx, fz = math.sin(car.yaw), math.cos(car.yaw)
	local rx, rz = -fz, fx
	for _, r in riders do
		local dx, dz = r.x - car.x, r.z - car.z
		local along, across = dx * fx + dz * fz, dx * rx + dz * rz
		if
			math.abs(along) <= car.length * 0.5
			and math.abs(across) <= car.width * 0.5
			and math.abs(r.y - car.top) < 1.5
		then
			local side = if across >= 0 then 1 else -1
			local off = car.width * 0.5 + 1.2
			table.insert(
				out,
				{ id = r.id, x = car.x + fx * along + rx * side * off, z = car.z + fz * along + rz * side * off }
			)
		end
	end
	return out
end

return Recovery
