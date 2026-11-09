--!strict
-- ReplicatedStorage.Shared.Actors.LoopWalker
-- The reference brain for the possession spike (S2) and its test place: walks a closed polyline
-- in the XZ plane at a fixed speed. It implements the brain contract Possession relies on
-- (BUILD_PLAN §1.5 steps 2 and "Release"): `suspend()` returns a snapshot of mode, position,
-- velocity, yaw and arc position; `resume(pose)` re-enters the loop at the arc position nearest
-- to where the player left the body, so the AI carries on from the last validated state.
-- Pure numbers (no Vector3), so Lune and the engine run it identically. W1's Pedestrian and
-- Squirrel brains keep the same contract.
-- Interface: new(points, speed, s0?, mode?) -> Walker; step(w, dt) -> (x, z, yaw); pose(w);
-- suspend(w) -> SuspendData; resume(w, x, z) -> number (distance to the loop); nearest(w, x, z);
-- brain(w) -> the closure form Server/Actors/ActorService expects ({ suspend, resume })

export type Point = { x: number, z: number }

export type Walker = {
	points: { Point },
	cum: { number }, -- cumulative arc length at each point (cum[1] = 0)
	length: number,
	speed: number, -- studs per second
	mode: string, -- "walk" | "run"
	s: number, -- arc position, [0, length)
	active: boolean, -- false while suspended
	ticks: number, -- steps taken while active (the soak's "AI resumed" probe)
}

export type SuspendData = {
	s: number,
	x: number,
	z: number,
	yaw: number,
	vx: number,
	vz: number,
	speed: number,
	mode: string,
}

local LoopWalker = {}

function LoopWalker.new(points: { Point }, speed: number, s0: number?, mode: string?): Walker
	assert(#points >= 2, "LoopWalker.new: need at least 2 points")
	local cum = { 0 }
	local total = 0
	for i = 1, #points do
		local a = points[i]
		local b = points[i % #points + 1]
		total += math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
		cum[i + 1] = total
	end
	assert(total > 0, "LoopWalker.new: degenerate loop")
	return {
		points = points,
		cum = cum,
		length = total,
		speed = speed,
		mode = mode or "walk",
		s = (s0 or 0) % total,
		active = true,
		ticks = 0,
	}
end

-- Position, unit direction at arc position s.
local function at(w: Walker, s: number): (number, number, number, number)
	local n = #w.points
	local lo = 1
	for i = 1, n do
		if w.cum[i + 1] > s then
			lo = i
			break
		end
		lo = i
	end
	local a = w.points[lo]
	local b = w.points[lo % n + 1]
	local segLen = w.cum[lo + 1] - w.cum[lo]
	local t = if segLen > 0 then (s - w.cum[lo]) / segLen else 0
	local dx, dz = b.x - a.x, b.z - a.z
	local inv = if segLen > 0 then 1 / segLen else 0
	return a.x + dx * t, a.z + dz * t, dx * inv, dz * inv
end

-- Roblox yaw (radians about +Y) that faces direction (dx, dz): yaw 0 faces -Z.
local function yawOf(dx: number, dz: number): number
	return math.atan2(-dx, -dz)
end

function LoopWalker.pose(w: Walker): (number, number, number, number, number)
	local x, z, dx, dz = at(w, w.s)
	return x, z, yawOf(dx, dz), dx * w.speed, dz * w.speed
end

-- Advances an active walker by dt seconds; a suspended walker does not move.
function LoopWalker.step(w: Walker, dt: number): (number, number, number)
	if w.active then
		w.s = (w.s + w.speed * dt) % w.length
		w.ticks += 1
	end
	local x, z, yaw = LoopWalker.pose(w)
	return x, z, yaw
end

function LoopWalker.suspend(w: Walker): SuspendData
	local x, z, yaw, vx, vz = LoopWalker.pose(w)
	w.active = false
	return { s = w.s, x = x, z = z, yaw = yaw, vx = vx, vz = vz, speed = w.speed, mode = w.mode }
end

-- Arc position of the point on the loop nearest to (x, z), and the distance to it.
function LoopWalker.nearest(w: Walker, x: number, z: number): (number, number)
	local bestS, bestD2 = 0, math.huge
	local n = #w.points
	for i = 1, n do
		local a = w.points[i]
		local b = w.points[i % n + 1]
		local dx, dz = b.x - a.x, b.z - a.z
		local len2 = dx * dx + dz * dz
		local t = if len2 > 0 then math.clamp(((x - a.x) * dx + (z - a.z) * dz) / len2, 0, 1) else 0
		local px, pz = a.x + dx * t, a.z + dz * t
		local d2 = (px - x) ^ 2 + (pz - z) ^ 2
		if d2 < bestD2 then
			bestD2 = d2
			bestS = w.cum[i] + t * (w.cum[i + 1] - w.cum[i])
		end
	end
	return bestS % w.length, math.sqrt(bestD2)
end

-- Re-enters the loop where the released body stands (projected) and reactivates; returns the
-- projection distance (the body glides back onto the loop over the next steps in W1; the
-- spike's walker snaps, which is what the harness measures as the resume offset).
function LoopWalker.resume(w: Walker, x: number, z: number): number
	local s, d = LoopWalker.nearest(w, x, z)
	w.s = s
	w.active = true
	return d
end

-- The brain contract in closure form (ActorService.Brain): suspend() -> snapshot fields,
-- resume(x, y, z) re-enters the loop.
function LoopWalker.brain(w: Walker): { suspend: () -> { [string]: any }, resume: (number, number, number) -> () }
	return {
		suspend = function(): { [string]: any }
			local d = LoopWalker.suspend(w)
			return {
				x = d.x,
				z = d.z,
				yaw = d.yaw,
				vx = d.vx,
				vz = d.vz,
				mode = d.mode,
				brain = { s = d.s, speed = d.speed },
			}
		end,
		resume = function(x: number, _y: number, z: number)
			LoopWalker.resume(w, x, z)
		end,
	}
end

return LoopWalker
