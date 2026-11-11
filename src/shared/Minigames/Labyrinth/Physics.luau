--!strict
-- ReplicatedStorage.Shared.Minigames.Labyrinth.Physics
-- The marble and the tilting board: one fixed tick (1/60 s) at a time, state in, state out, nothing hidden. The
-- same code runs live on the player's machine and is replayed by the server from the input log (C1, LAB-P6),
-- so it uses only + - * / and sqrt on doubles (identical on every machine): no sin, no cos, no clock, no random.
-- What it gets right, because that is what the wooden toy feels like:
--   the board   has weight (LAB-P5): a key does not set its angle, it swings it. The swing gathers speed, so a
--               tap moves the board a fraction of a degree and a hold swings it at TILT_RATE to TILT_MAX. Let
--               go and it stays where it is, as real knobs do (HOLD_STAY), with a soft catch as it comes back
--               through level; or it levels itself (HOLD_LEVEL: the other answer to the owner's question D1).
--   the marble  rolls (LAB-P1, P2): it speeds up down the slope (a rolling ball takes 5/7 of the slope), keeps
--               going when the board levels, and is slowed only by a little rolling resistance and drag, so
--               it must be caught with a counter-tilt. A tiny tilt makes it creep; level stops it slowly.
--   walls       are wood (LAB-P3): about a third of the speed comes back off a square hit, none off a slow
--               touch (so it never chatters), and it slides along a wall with a little rub. Each sub-step
--               resolves the deepest contact first, so a seam between two walls or an inside corner neither
--               snags nor shakes it; the end of a wall is a round corner it catches on and rolls around.
--   holes       have rims (LAB-P4): once the centre is past the edge the marble is tipping over a corner of
--               wood, which pulls it in harder the further over it is (the potential of a ball on an edge);
--               well over the edge it drops, clipping the rim at speed it skirts round and lives.
-- The tick is cut into SUBSTEPS sub-steps so that the marble can never move further than half its radius
-- between two looks at the walls: nothing tunnels at top speed.
-- Board frame and units as Boards: studs, +x right, +y forward. Tilt is in degrees: tx > 0 tips the right side
-- down (the marble rolls right), ty > 0 tips the far side down (the marble rolls away from the player).
-- Pure; Lune-tested (tests/unit/labyrinth_physics.spec.luau).
-- Interface: TICK, SUBSTEPS, the tuning constants below, HOLD_STAY, HOLD_LEVEL; new(x, y) -> Marble;
--   copy(m) -> Marble; step(board, m, ux, uy, hold) -> hole index the marble dropped into this tick (0: none;
--   board.goal: the finish cup); place(m, x, y) (put the marble back on the board, at rest);
--   slope(degrees) -> sine; energy(m, board) -> the marble's energy per unit mass in the model's own terms
--   (for tests: it never grows while the board is held still); tiltAfter(ticks held from level) -> degrees

local Boards = require("./Boards")

local Physics = {}

Physics.TICK = 1 / 60
Physics.SUBSTEPS = 4

-- the board
Physics.TILT_MAX = 6 -- degrees either way on each axis (LAB-P5 "about 6 degrees")
Physics.TILT_RATE = 25 -- degrees per second at full swing (Tunables minigames.labyrinthTiltDegPerS; a spec checks)
Physics.TILT_ACCEL = 300 -- degrees per second per second: the swing takes 5 ticks to gather
Physics.TILT_BRAKE = 600 -- letting go stops the swing in half that
Physics.CATCH_TICKS = 8 -- HOLD_STAY: a board swung back through level rests there this long before going on
Physics.HOLD_STAY = 0
Physics.HOLD_LEVEL = 1

-- the marble
Physics.GRAVITY = 80 -- studs/s^2 (the scale bowling's pit uses; the toy is drawn large)
Physics.ROLL = 5 / 7 -- a solid ball rolling without slipping takes this share of the slope
Physics.ROLL_RESIST = 0.2 -- studs/s^2 of rolling resistance: tilts under about 0.2 degrees do not move it
Physics.DRAG = 0.8 -- 1/s: speed lost in proportion to speed (terminal speed at full tilt is about 7)
Physics.MAX_SPEED = 7 -- studs/s, a hard ceiling so a sub-step is never longer than half the marble's radius
Physics.RESTITUTION = 0.33 -- LAB-P3 "about a third of the speed back"
Physics.BOUNCE_MIN = 0.25 -- studs/s into a wall below which it does not bounce at all
Physics.WALL_FRICTION = 0.1 -- rub along a wall, as a share of the push into it
Physics.CAPTURE = 0.6 -- the marble drops when its centre is this share of its radius past a hole's edge

export type Marble = {
	x: number,
	y: number,
	vx: number,
	vy: number,
	on: number, -- 1 on the board, 0 gone (down a hole, or in the cup)
	tx: number, -- board tilt in degrees, + rolls the marble right
	ty: number, -- + rolls it forward
	wx: number, -- how fast each tilt is swinging, degrees per second
	wy: number,
	cx: number, -- ticks left in the catch at level, per axis
	cy: number,
	cell: number, -- the cell its centre is in
	-- what happened this tick, for sound and drawing (rewritten every step)
	hit: number, -- hardest wall hit, studs/s (0: none)
	rim: number, -- deepest it stood over a hole's edge, as a share of its radius (0: clear)
	touch: number, -- 1 when it touched a wall this tick
}

local TICK = Physics.TICK
local SUBSTEPS = Physics.SUBSTEPS
local H = TICK / SUBSTEPS
local DEG = 3.141592653589793 / 180
local G_ROLL = Physics.GRAVITY * Physics.ROLL

-- the sine of a small angle from + - * alone (exact to 1e-9 at 6 degrees)
function Physics.slope(degrees: number): number
	local r = degrees * DEG
	return r - r * r * r / 6
end

function Physics.new(x: number, y: number): Marble
	return {
		x = x,
		y = y,
		vx = 0,
		vy = 0,
		on = 1,
		tx = 0,
		ty = 0,
		wx = 0,
		wy = 0,
		cx = 0,
		cy = 0,
		cell = 0,
		hit = 0,
		rim = 0,
		touch = 0,
	}
end

function Physics.copy(m: Marble): Marble
	return table.clone(m)
end

function Physics.place(m: Marble, x: number, y: number)
	m.x, m.y, m.vx, m.vy, m.on = x, y, 0, 0, 1
end

-- one axis of the board for one tick: angle, swing, catch in; the same out. u is the key: -1, 0 or 1.
local function tiltAxis(a: number, w: number, catch: number, u: number, hold: number): (number, number, number)
	if catch > 0 then
		-- resting in the catch at level: letting go ends it there; holding on waits it out
		if u == 0 then
			return 0, 0, 0
		end
		return 0, 0, catch - 1
	end
	local target = u * Physics.TILT_RATE
	if u == 0 and hold == Physics.HOLD_LEVEL and a ~= 0 then
		target = if a > 0 then -Physics.TILT_RATE else Physics.TILT_RATE
	end
	local dw = (if target == 0 or target * w < 0 then Physics.TILT_BRAKE else Physics.TILT_ACCEL) * TICK
	if w < target then
		w = math.min(target, w + dw)
	else
		w = math.max(target, w - dw)
	end
	local na = a + w * TICK
	if na >= Physics.TILT_MAX then
		return Physics.TILT_MAX, 0, 0
	elseif na <= -Physics.TILT_MAX then
		return -Physics.TILT_MAX, 0, 0
	end
	if a ~= 0 and (na == 0 or (na > 0) ~= (a > 0)) then
		-- back through level: it stops there
		return 0, 0, if hold == Physics.HOLD_STAY and u ~= 0 then Physics.CATCH_TICKS else 0
	end
	return na, w, 0
end

-- How far a board swung from level has tipped after a key is held for `ticks` and then let go (HOLD_STAY).
function Physics.tiltAfter(ticks: number): number
	local a, w, c = 0, 0, 0
	for _ = 1, ticks do
		a, w, c = tiltAxis(a, w, c, 1, Physics.HOLD_STAY)
	end
	for _ = 1, 60 do
		a, w, c = tiltAxis(a, w, c, 0, Physics.HOLD_STAY)
	end
	return a
end

function Physics.step(board: Boards.Board, m: Marble, ux: number, uy: number, hold: number): number
	m.tx, m.wx, m.cx = tiltAxis(m.tx, m.wx, m.cx, ux, hold)
	m.ty, m.wy, m.cy = tiltAxis(m.ty, m.wy, m.cy, uy, hold)
	m.hit, m.rim, m.touch = 0, 0, 0
	if m.on == 0 then
		return 0
	end
	local gx = G_ROLL * Physics.slope(m.tx)
	local gy = G_ROLL * Physics.slope(m.ty)
	local R = board.marbleR
	local R2 = R * R
	local captureDepth = Physics.CAPTURE * R
	local x, y, vx, vy = m.x, m.y, m.vx, m.vy
	local cols, rows, pitch, bx0, by0 = board.cols, board.rows, board.pitch, board.x0, board.y0
	local wx0, wx1, wy0, wy1 = board.wx0, board.wx1, board.wy0, board.wy1
	local hx, hy, hr = board.hx, board.hy, board.hr
	local hit, rim, touch, cell = 0, 0, 0, m.cell
	local resist, drag, maxSpeed = Physics.ROLL_RESIST, Physics.DRAG, Physics.MAX_SPEED
	local restitution, bounceMin, wallFriction = Physics.RESTITUTION, Physics.BOUNCE_MIN, Physics.WALL_FRICTION
	for _ = 1, SUBSTEPS do
		local c = (x - bx0) // pitch
		local r = (y - by0) // pitch
		if c < 0 then
			c = 0
		elseif c >= cols then
			c = cols - 1
		end
		if r < 0 then
			r = 0
		elseif r >= rows then
			r = rows - 1
		end
		cell = r * cols + c + 1

		-- the slope, and the pull of any rim the centre is past
		local ax, ay = gx, gy
		local holes = board.cellHoles[cell]
		for i = 1, #holes do
			local k = holes[i]
			local dx, dy = hx[k] - x, hy[k] - y
			local d2 = dx * dx + dy * dy
			local rh = hr[k]
			if d2 < rh * rh then
				local d = math.sqrt(d2)
				local depth = rh - d
				if depth >= captureDepth then
					-- well over the edge: gone
					m.x, m.y, m.vx, m.vy = x, y, vx, vy
					m.on, m.cell = 0, cell
					m.hit, m.rim, m.touch = hit, 1, 0
					return k
				end
				local pull = G_ROLL * depth / math.sqrt(R2 - depth * depth)
				ax += pull * dx / d
				ay += pull * dy / d
				if depth / R > rim then
					rim = depth / R
				end
			end
		end

		vx += ax * H
		vy += ay * H
		local speed = math.sqrt(vx * vx + vy * vy)
		if speed > 0 then
			local lost = (resist + drag * speed) * H
			if lost >= speed then
				vx, vy = 0, 0
			else
				local left = speed - lost
				if left > maxSpeed then
					left = maxSpeed
				end
				local k = left / speed
				vx *= k
				vy *= k
			end
		end
		x += vx * H
		y += vy * H

		-- walls: the deepest contact first, then look again
		local walls = board.cellWalls[cell]
		for _ = 1, 4 do
			local best, bnx, bny = 0, 0, 0
			for i = 1, #walls do
				local k = walls[i]
				local ax0, ax1, ay0, ay1 = wx0[k], wx1[k], wy0[k], wy1[k]
				local qx = if x < ax0 then ax0 elseif x > ax1 then ax1 else x
				local qy = if y < ay0 then ay0 elseif y > ay1 then ay1 else y
				local dx, dy = x - qx, y - qy
				local d2 = dx * dx + dy * dy
				if d2 < R2 then
					local pen, nx, ny
					if d2 > 1e-18 then
						local d = math.sqrt(d2)
						pen, nx, ny = R - d, dx / d, dy / d
					else
						-- the centre is inside the wood (it cannot get there by rolling): out by the nearest face
						local left, right = x - ax0, ax1 - x
						local near, far = y - ay0, ay1 - y
						local least = math.min(left, right, near, far)
						if least == left then
							pen, nx, ny = R + left, -1, 0
						elseif least == right then
							pen, nx, ny = R + right, 1, 0
						elseif least == near then
							pen, nx, ny = R + near, 0, -1
						else
							pen, nx, ny = R + far, 0, 1
						end
					end
					if pen > best then
						best, bnx, bny = pen, nx, ny
					end
				end
			end
			if best <= 0 then
				break
			end
			touch = 1
			x += bnx * best
			y += bny * best
			local vn = vx * bnx + vy * bny
			if vn < 0 then
				local into = -vn
				local push = if into > bounceMin then (1 + restitution) * into else into
				vx += push * bnx
				vy += push * bny
				-- the rub along the wall
				local vt = vy * bnx - vx * bny
				local rub = wallFriction * push
				if rub >= math.abs(vt) then
					vx -= -bny * vt
					vy -= bnx * vt
				else
					local s = if vt > 0 then rub else -rub
					vx -= -bny * s
					vy -= bnx * s
				end
				if into > hit then
					hit = into
				end
			end
		end
	end
	m.x, m.y, m.vx, m.vy = x, y, vx, vy
	m.cell = cell
	m.hit = if hit > bounceMin then hit else 0
	m.rim, m.touch = rim, touch
	return 0
end

-- The marble's energy per unit mass in the model's own terms: motion, height on the slope, and how far it has
-- sunk over a rim. With the board held still this never grows (tests).
function Physics.energy(m: Marble, board: Boards.Board): number
	local R = board.marbleR
	local e = 0.5 * (m.vx * m.vx + m.vy * m.vy)
	e -= G_ROLL * (Physics.slope(m.tx) * m.x + Physics.slope(m.ty) * m.y)
	for k = 1, #board.hx do
		local dx, dy = board.hx[k] - m.x, board.hy[k] - m.y
		local d = math.sqrt(dx * dx + dy * dy)
		local depth = board.hr[k] - d
		if depth > 0 then
			depth = math.min(depth, R)
			e -= G_ROLL * (R - math.sqrt(R * R - depth * depth))
		end
	end
	return e
end

return Physics
