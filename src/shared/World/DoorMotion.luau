--!strict
-- ReplicatedStorage.Shared.World.DoorMotion
-- How a door moves, and when (the interiors work, 2026-11-11: rooms a body can walk into). The bake
-- makes every doorway of an enterable building a real opening in the wall and its leaf a part that
-- never collides (WorldGen/Builders/Shell), so nothing ever stops a body at a door; what is left is to
-- show the leaf opening as somebody comes near and closing behind them. Each client does that for the
-- doors near its own camera (Client/Render/DoorView); the server moves nothing.
--   * A swing door turns SWING radians about its hinge edge (the leaf's local -X edge), away from the
--     body that opened it, so it never sweeps through the one walking in.
--   * A slide door (the wide doors of the hospital and the police station) runs along the wall into
--     it: the leaf is thinner than the wall and stands inside its thickness, so it disappears.
-- A door opens when a body's centre is within OPEN of the doorway (the segment the closed leaf stands
-- on) and closes when the last one is further than CLOSE; the gap between the two keeps a body that
-- stands at the edge from flapping it.
-- Interface: pose(closed, size, motion, sign, run, alpha, C) -> CFrame; reach(dx, dz, tx, tz, half) ->
--   studs; wants(open, dist) -> boolean; side(dx, dz, nx, nz) -> 1 | -1; ease(alpha, target, dt) ->
--   alpha; SWING; OPEN; CLOSE; OPEN_SECS; CLOSE_SECS; TALL
-- Pure: `C` is the CFrame library (the engine's, or Lune's), so the same pose runs in the tests.

local DoorMotion = {}

DoorMotion.SWING = 1.35 -- radians (v5.4 buildHouse door)
DoorMotion.OPEN = 7.5 -- studs from the doorway at which a body opens it
DoorMotion.CLOSE = 9.5 -- and beyond which the last body lets it close
DoorMotion.TALL = 9 -- a body this far above or below the sill is on another level (a roof, a branch)
DoorMotion.OPEN_SECS = 0.35
DoorMotion.CLOSE_SECS = 0.7

-- The leaf's CFrame `alpha` of the way open (0 closed, 1 open). `sign` is +1 or -1: for a swing door
-- which way the free edge goes (+1 toward the leaf's local -Z), for a slide door which way along its
-- local X; `run` is how far a slide door travels.
function DoorMotion.pose(closed: any, size: any, motion: string, sign: number, run: number, alpha: number, C: any): any
	if alpha <= 0 then
		return closed
	end
	if motion == "slide" then
		return closed * C.new(sign * run * alpha, 0, 0)
	end
	local hinge = closed * C.new(-size.X / 2, 0, 0)
	return hinge * C.Angles(0, sign * DoorMotion.SWING * alpha, 0) * C.new(size.X / 2, 0, 0)
end

-- Distance from a body to the doorway: (dx, dz) is the body relative to the leaf's centre, (tx, tz)
-- the unit direction along the leaf and `half` half its width.
function DoorMotion.reach(dx: number, dz: number, tx: number, tz: number, half: number): number
	local along = math.clamp(dx * tx + dz * tz, -half, half)
	local ox, oz = dx - tx * along, dz - tz * along
	return math.sqrt(ox * ox + oz * oz)
end

-- Should the door be open, given whether it is now and the distance of the nearest body?
function DoorMotion.wants(open: boolean, dist: number): boolean
	if open then
		return dist <= DoorMotion.CLOSE
	end
	return dist <= DoorMotion.OPEN
end

-- Which way a swing door turns so that it goes away from a body at (dx, dz) from the leaf, whose
-- local +Z looks along (nx, nz): +1 swings the free edge toward local -Z.
function DoorMotion.side(dx: number, dz: number, nx: number, nz: number): number
	return if dx * nx + dz * nz >= 0 then 1 else -1
end

-- One frame of opening or closing: `alpha` moves toward `target` (0 or 1) at an even rate.
function DoorMotion.ease(alpha: number, target: number, dt: number): number
	if target > alpha then
		return math.min(target, alpha + dt / DoorMotion.OPEN_SECS)
	end
	return math.max(target, alpha - dt / DoorMotion.CLOSE_SECS)
end

return DoorMotion
