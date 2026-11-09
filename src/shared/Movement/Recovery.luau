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
-- Interface: riverFall(x, y, z) -> (x, y, z)?, newHistory(capacity?, interval?), record(h, t, x, y,
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
