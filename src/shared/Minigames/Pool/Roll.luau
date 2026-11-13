--!strict
-- ReplicatedStorage.Shared.Minigames.Pool.Roll
-- How a ball TURNS as it rolls: the picture of a shot's spin, so the number and the stripe on a ball go round
-- as the ball's roll and side spin say (follow rolls on, draw spins back toward the cue, side spin turns the
-- ball about its upright axis). The table model (Physics, Shot) carries a ball's roll q and side spin s but
-- not which way its number faces; this module turns q and s into an orientation.
-- An orientation is a rotation matrix as nine numbers (row by row) in the table's own right-handed frame:
-- x across the table, y up, and the third axis pointing at the HEAD end (table -z), which is exactly how a
-- part's axes lie in the site's frame (Attractions/AlleyLayout: local +D is the part's -Z). So a ball's
-- CFrame is CFrame.new(place) * the site's yaw * CFrame.new(0, 0, 0, the nine numbers).
-- The turning is integrated on a FIXED grid of STEP seconds from the shot's script (the roll and side spin at
-- the middle of each step), never by the frame time, so every screen and the server come to the same
-- orientation at the end of a shot whatever their frame rates, and a ball's number does not jump when the
-- server sets the ball down where it stopped.
-- Pure (+ - * / sqrt, sin and cos); Lune-tested (tests/unit/pool_roll.spec.luau).
-- Interface: STEP; identity() -> Rot; turn(rot, wx, wy, wz, dt) (in place: spin about the axis w, radians a
--   second, for dt); advance(rot, script, i, fromStep, toStep) (in place: grid steps fromStep+1 .. toStep of
--   the i-th ball of a Shot.Script); steps(t) -> the grid steps done by time t; final(rot, script, i) (in
--   place: the whole shot); at(rot, script, i, t) -> Rot (a copy turned on from the last grid step to t, for
--   drawing between steps); tidy(rot) (in place: square the matrix up again after many steps)

local Shot = require("./Shot")
local Tables = require("./Tables")

local Roll = {}

Roll.STEP = 1 / 120

export type Rot = { number } -- nine numbers, row by row

function Roll.identity(): Rot
	return { 1, 0, 0, 0, 1, 0, 0, 0, 1 }
end

-- rot <- R(w * dt) * rot (Rodrigues' formula; the turn is about a fixed axis in the table's frame)
function Roll.turn(rot: Rot, wx: number, wy: number, wz: number, dt: number)
	local w = math.sqrt(wx * wx + wy * wy + wz * wz)
	local a = w * dt
	if a < 1e-9 then
		return
	end
	local kx, ky, kz = wx / w, wy / w, wz / w
	local c, s = math.cos(a), math.sin(a)
	local v = 1 - c
	local m11, m12, m13 = c + kx * kx * v, kx * ky * v - kz * s, kx * kz * v + ky * s
	local m21, m22, m23 = ky * kx * v + kz * s, c + ky * ky * v, ky * kz * v - kx * s
	local m31, m32, m33 = kz * kx * v - ky * s, kz * ky * v + kx * s, c + kz * kz * v
	local r11, r12, r13 = rot[1], rot[2], rot[3]
	local r21, r22, r23 = rot[4], rot[5], rot[6]
	local r31, r32, r33 = rot[7], rot[8], rot[9]
	rot[1] = m11 * r11 + m12 * r21 + m13 * r31
	rot[2] = m11 * r12 + m12 * r22 + m13 * r32
	rot[3] = m11 * r13 + m12 * r23 + m13 * r33
	rot[4] = m21 * r11 + m22 * r21 + m23 * r31
	rot[5] = m21 * r12 + m22 * r22 + m23 * r32
	rot[6] = m21 * r13 + m22 * r23 + m23 * r33
	rot[7] = m31 * r11 + m32 * r21 + m33 * r31
	rot[8] = m31 * r12 + m32 * r22 + m33 * r32
	rot[9] = m31 * r13 + m32 * r23 + m33 * r33
end

-- The turn a ball's roll (qx, qz: table frame) and side spin s give it, as an axis times radians a second in
-- the right-handed frame (x, y, -z). A ball rolling toward +x turns about the level axis on its left; side
-- spin is counter-clockwise from above for s > 0.
local function spinOf(qx: number, qz: number, s: number, r: number): (number, number, number)
	-- up x (qx, 0, -qz) = (-qz, 0, -qx)
	return -qz / r, s / r, -qx / r
end

function Roll.steps(t: number): number
	return math.max(0, math.floor(t / Roll.STEP + 1e-9))
end

-- Grid steps fromStep+1 .. toStep of the i-th ball (a ball nothing moved is left alone).
function Roll.advance(rot: Rot, script: Shot.Script, i: number, fromStep: number, toStep: number)
	if #script.tracks[i] == 0 then
		return
	end
	local r = Tables.byId(script.table).ballR
	local step = Roll.STEP
	for k = fromStep, toStep - 1 do
		local _, _, _, mode, _, _, qx, qz, s = Shot.pose(script, i, (k + 0.5) * step)
		if mode == 1 and (qx ~= 0 or qz ~= 0 or s ~= 0) then
			local wx, wy, wz = spinOf(qx, qz, s, r)
			Roll.turn(rot, wx, wy, wz, step)
		end
	end
end

function Roll.final(rot: Rot, script: Shot.Script, i: number)
	Roll.advance(rot, script, i, 0, Roll.steps(script.tEnd))
	Roll.tidy(rot)
end

-- A copy of `rot` (which stands at grid step `done`) turned on to time t: what is drawn between grid steps.
function Roll.at(rot: Rot, script: Shot.Script, i: number, done: number, t: number): Rot
	local out = table.clone(rot)
	local rest = t - done * Roll.STEP
	if rest > 0 and #script.tracks[i] > 0 then
		local _, _, _, mode, _, _, qx, qz, s = Shot.pose(script, i, done * Roll.STEP + rest / 2)
		if mode == 1 then
			local wx, wy, wz = spinOf(qx, qz, s, Tables.byId(script.table).ballR)
			Roll.turn(out, wx, wy, wz, rest)
		end
	end
	return out
end

-- Many small turns leave the rows a hair off square: make them unit and at right angles again (Gram-Schmidt).
function Roll.tidy(rot: Rot)
	local ax, ay, az = rot[1], rot[2], rot[3]
	local bx, by, bz = rot[4], rot[5], rot[6]
	local n = math.sqrt(ax * ax + ay * ay + az * az)
	if n < 1e-9 then
		rot[1], rot[2], rot[3], rot[4], rot[5], rot[6], rot[7], rot[8], rot[9] = 1, 0, 0, 0, 1, 0, 0, 0, 1
		return
	end
	ax, ay, az = ax / n, ay / n, az / n
	local d = ax * bx + ay * by + az * bz
	bx, by, bz = bx - d * ax, by - d * ay, bz - d * az
	n = math.sqrt(bx * bx + by * by + bz * bz)
	if n < 1e-9 then
		rot[1], rot[2], rot[3], rot[4], rot[5], rot[6], rot[7], rot[8], rot[9] = 1, 0, 0, 0, 1, 0, 0, 0, 1
		return
	end
	bx, by, bz = bx / n, by / n, bz / n
	rot[1], rot[2], rot[3] = ax, ay, az
	rot[4], rot[5], rot[6] = bx, by, bz
	rot[7], rot[8], rot[9] = ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx
end

return Roll
