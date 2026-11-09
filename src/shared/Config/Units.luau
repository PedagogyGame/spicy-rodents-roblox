--!strict
-- ReplicatedStorage.Shared.Config.Units
-- HTML-unit/stud conversion at the single boundary (BUILD_PLAN §1.4, D21).
-- 1 HTML unit = 2.5 studs (spec/README). Authored models face Roblox LookVector (-Z);
-- the HTML faces +Z, so yawCFrame adds pi exactly once, here.

local Units = {}

Units.STUDS_PER_UNIT = 2.5

-- HTML units to studs.
function Units.st(u: number): number
	return u * Units.STUDS_PER_UNIT
end

-- Studs to HTML units.
function Units.u(st: number): number
	return st / Units.STUDS_PER_UNIT
end

-- Yaw conversion: HTML yaw (radians, model faces +Z) to a Roblox yaw (model faces -Z).
-- Pure maths so Lune can test it; the engine wrapper below builds the CFrame.
function Units.robloxYaw(htmlYaw: number): number
	return htmlYaw + math.pi
end

-- Engine-only: CFrame at pos (studs) facing the converted yaw. Lune has CFrame too (@lune/roblox),
-- so this stays testable, but callers under Lune must pass a CFrame-capable environment.
function Units.yawCFrame(htmlYaw: number, pos: Vector3): CFrame
	return CFrame.new(pos) * CFrame.Angles(0, Units.robloxYaw(htmlYaw), 0)
end

return Units
