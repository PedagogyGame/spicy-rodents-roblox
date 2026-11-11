--!strict
-- ReplicatedStorage.Shared.Minigames.Pinball.Physics
-- The one physics core all three pinball machines run on (brief v2 §13a "three pinball machines (distinct
-- themes, real flipper physics)"; checklist PIN-P1..P5). No engine physics: a fixed step of 1/240 s over plain
-- data, the same on the player's machine and in the server's replay.
--
-- What it gets right, because these are what make pinball feel like pinball:
--   * The ball rolls on a sloped table: gravity down the table all the time, a little rolling resistance,
--     rubber that is lively and metal and wood that are dead (a bounce keeps a share of the speed INTO the
--     surface; slow touches keep none, so a ball can roll along a guide and come to rest in a corner).
--   * A flipper is a rotating body, not a paddle that teleports. It is driven up at FLIP_ACC_UP (a full stroke
--     in about 45 ms), falls back slower under its spring, and bounces a little off its stops. The ball takes
--     its speed from the flipper's SURFACE at the point of contact (pivot distance times angular speed), so the
--     tip hits harder than the base, and the direction comes from where the flipper is in its stroke when they
--     meet: timing aims. A held flipper is a solid slope (a ball can be cradled on it and stops dead); a
--     flipper that has just hit its stop is on the recoil, moving away, and a ball landing right then is
--     deadened (a live catch). None of that is scripted; it falls out of the collision.
--   * Nothing tunnels. Each tick is cut into as many sub-steps as it takes for the ball and the flipper
--     surfaces to move no more than SUB_TRAVEL (under a third of the ball's radius) relative to each other, and
--     a wall is a line the ball's centre may not come within one radius of, from either side.
--   * Pop bumpers and slingshots ADD a fixed kick; MAX_SPEED caps the ball.
--   * Ramps are rails: a ball that enters the mouth fast enough rides the rail, loses speed climbing (height
--     costs GRAVITY_H per stud) and rolls back out if it stalls. A kick-out hole swallows a slow ball and
--     throws it back out. A spinner turns as fast as the ball went through it and runs down by itself.
--
-- State is plain data (numbers, booleans, arrays): step() reads the state and the two flipper buttons, writes
-- the state, and appends what happened to an event list (four numbers per event: code, ref, value, ball).
-- Nothing is kept outside the state, so a copy of the state continues identically.
-- Only + - * / sqrt and Det.sin/cos are used, so every machine gets the same bits.
-- Pure; Lune-tested (tests/unit/pinball_physics.spec.luau, pinball_flipper.spec.luau).
-- Interface: HZ, DT, the tuning constants, EV (event codes), MODE; new(compiled, seed) -> State;
--   step(compiled, state, left, right, events); addBall(state, x, y, vx, vy) -> index; removeGone(state);
--   nudge(state, dvx, dvy); wake(state); launch(state, index, speed); rand(state) -> [0, 1);
--   energy(compiled, ball) -> number; flipperTip(compiled, state, i) -> (x, y)

local Det = require("./Det")
local Layout = require("./Layout")

local Physics = {}

Physics.HZ = 240
Physics.DT = 1 / 240
Physics.MAX_SPEED = 30 -- studs/s (about 6.5 m/s on the real table)
Physics.SUB_TRAVEL = Layout.BALL_R * 0.3
Physics.MAX_SUBSTEPS = 12
Physics.ROLL_DECEL = 0.2 -- studs/s^2 of rolling resistance
Physics.REST_V0 = 0.15 -- below this speed into a surface nothing bounces back
Physics.REST_V1 = 0.6 -- from here up the surface's full liveliness
Physics.FLIP_ACC_UP = 1000 -- rad/s^2 under the coil
Physics.FLIP_W_MAX = 40 -- rad/s
Physics.FLIP_ACC_DOWN = 240 -- rad/s^2 under the return spring
Physics.FLIP_W_DOWN = 22
Physics.FLIP_STOP_E = 0.25 -- how much of its speed the flipper keeps bouncing off the top stop
Physics.FLIP_REST_E = 0.2 -- and off the bottom one
Physics.FLIP_BOUNCE_MIN = 2 -- rad/s: slower than this it simply stops
Physics.FLIP_E = 0.55 -- flipper rubber
Physics.FLIP_MU = 0.12
Physics.BUMPER_KICK = 6.5 -- studs/s outward, whatever the ball came in at
Physics.BUMPER_MIN = 0.3 -- the skirt needs this much of a touch to fire
Physics.BUMPER_E = 0.5 -- a dead bumper (tilt, or too soft a touch) is a rubber post
Physics.SLING_KICK = 5.0
Physics.SLING_MIN = 0.7
Physics.DROP_MIN = 0.4 -- speed into a drop target that knocks it down
Physics.DROP_E = 0.3
Physics.STANDUP_MIN = 0.3
Physics.BALL_E = 0.9 -- ball against ball
Physics.GRAVITY_H = 32 -- studs/s^2 per stud of height per stud of rail (a ramp's climb)
Physics.SLEEP_V = 0.04
Physics.SLEEP_TICKS = 60
Physics.SPIN_PER_SPEED = 1.6 -- spinner turns per second per stud/s of ball
Physics.SPIN_FRICTION = 3 -- turns/s^2
Physics.SPIN_DRAG = 0.9 -- 1/s
Physics.SPIN_BALL_KEEP = 0.94 -- the ball keeps this much of its speed through a spinner
Physics.EJECT_JITTER = 0.06 -- a kick-out varies by this share, seeded
Physics.EJECT_COOL = 36 -- ticks a kicked-out ball cannot be swallowed again
Physics.SOUND_MIN = 1.2 -- wall and post hits slower than this make no event

Physics.EV = {
	WALL = 1, -- ref: material code, value: speed into it
	POST = 2,
	BUMPER = 3, -- ref: bumper number, value: 1 when it fired
	SLING = 4, -- ref: sling number
	STANDUP = 5, -- ref: target number
	DROP = 6, -- ref: target number (it went down)
	ROLLOVER = 7, -- ref: sensor number, value: +1 crossing to the left of a -> b, -1 to the right
	SPIN = 8, -- ref: sensor number: one whole turn of the spinner
	SAUCER = 9, -- ref: saucer number (the ball fell in)
	EJECT = 10, -- ref: saucer number
	RAIL_IN = 11, -- ref: rail number
	RAIL_OUT = 12, -- ref: rail number, value: 1 off the far end, 0 back out of the mouth
	FLIPPER = 13, -- ref: flipper number, value: closing speed
	FLIP_UP = 14, -- ref: flipper number (the button went down)
	FLIP_DOWN = 15,
	BALLS = 16, -- two balls clicked
	DRAIN = 17, -- value: x where it went
	GATE = 18,
	SPINNER = 19, -- ref: sensor number, value: the ball's speed through it
}

Physics.MODE = { FREE = 0, RAIL = 1, HELD = 2, GONE = 3 }

export type Ball = {
	x: number,
	y: number,
	vx: number,
	vy: number,
	z: number, -- height above the playfield (on a ramp), for drawing
	mode: number,
	ref: number, -- the rail or the saucer it is in
	s: number, -- rail: distance along
	v: number, -- rail: speed along
	k: number, -- rail: piece
	timer: number, -- held: ticks until it is kicked out (negative: until released by the rules)
	cool: number, -- ticks left of not being swallowed
	still: number, -- ticks in a row slow and touching
	hit: boolean, -- touched something this tick
	asleep: boolean,
}

export type State = {
	tick: number,
	balls: { Ball },
	fa: { number }, -- flipper angles
	fw: { number }, -- flipper angular speeds
	fp: { boolean }, -- flipper button as last seen
	drop: { boolean }, -- per target: a drop target that is down
	spinW: { number }, -- per sensor: spinner speed, turns/s
	spinA: { number }, -- per sensor: fraction of the current turn
	dead: boolean, -- tilt: flippers, bumpers and slings do nothing
	rng: number,
}

local EV = Physics.EV
local FREE, RAIL, HELD, GONE = 0, 1, 2, 3
local R = Layout.BALL_R
local R2 = R * R
local DT = Physics.DT
local INV_CELL = 1 / Layout.CELL
local SEG_DROP, SEG_SLING, SEG_GATE, SEG_STANDUP = Layout.SEG_DROP, Layout.SEG_SLING, Layout.SEG_GATE, Layout.SEG_STANDUP
local CIR_BUMPER = Layout.CIR_BUMPER
local SEN_ROLLOVER, SEN_SPINNER = Layout.SEN_ROLLOVER, Layout.SEN_SPINNER
local sqrt, floor = math.sqrt, math.floor

-- per-step scratch, rebuilt from the state at the top of every step (nothing is carried in it)
local fA0: { number } = {}
local fDA: { number } = {}
local fOm: { number } = {}
local fDx: { number } = {}
local fDy: { number } = {}

function Physics.new(c: Layout.Compiled, seed: number): State
	local s: State = {
		tick = 0,
		balls = {},
		fa = {},
		fw = {},
		fp = {},
		drop = table.create(#c.def.targets, false),
		spinW = table.create(c.nSen, 0),
		spinA = table.create(c.nSen, 0),
		dead = false,
		rng = floor(seed) % 4294967296,
	}
	for i = 1, c.nFlip do
		s.fa[i] = c.frest[i]
		s.fw[i] = 0
		s.fp[i] = false
	end
	return s
end

-- rand(state): the state's own seeded stream (kick-out jitter). A 32-bit LCG whose products stay exact in a
-- double; the top 16 bits are returned.
function Physics.rand(s: State): number
	local a = (s.rng * 69069 + 1) % 4294967296
	s.rng = a
	return floor(a / 65536) / 65536
end

function Physics.addBall(s: State, x: number, y: number, vx: number, vy: number): number
	table.insert(s.balls, {
		x = x,
		y = y,
		vx = vx,
		vy = vy,
		z = 0,
		mode = FREE,
		ref = 0,
		s = 0,
		v = 0,
		k = 1,
		timer = 0,
		cool = 0,
		still = 0,
		hit = false,
		asleep = false,
	})
	return #s.balls
end

-- removeGone(state): drained balls leave the list (after their events have been read).
function Physics.removeGone(s: State)
	local balls = s.balls
	local n = 0
	for i = 1, #balls do
		local b = balls[i]
		if b.mode ~= GONE then
			n += 1
			balls[n] = b
		end
	end
	for i = #balls, n + 1, -1 do
		balls[i] = nil
	end
end

function Physics.wake(s: State)
	for _, b in s.balls do
		b.asleep = false
		b.still = 0
	end
end

-- nudge(state, dvx, dvy): the cabinet is shoved; every loose ball is given the shove's speed.
function Physics.nudge(s: State, dvx: number, dvy: number)
	for _, b in s.balls do
		if b.mode == FREE then
			b.vx += dvx
			b.vy += dvy
			b.asleep = false
			b.still = 0
		end
	end
end

function Physics.launch(s: State, index: number, speed: number)
	local b = s.balls[index]
	if b and b.mode == FREE then
		b.vy = speed
		b.asleep = false
		b.still = 0
	end
end

-- energy(compiled, ball): kinetic plus height, per unit mass (the specs watch that it never grows by itself).
function Physics.energy(c: Layout.Compiled, b: Ball): number
	if b.mode == RAIL then
		return 0.5 * b.v * b.v + c.gravity * b.y + Physics.GRAVITY_H * b.z
	end
	return 0.5 * (b.vx * b.vx + b.vy * b.vy) + c.gravity * b.y
end

-- flipperTip(compiled, state, i): where the centre of flipper i's tip is now.
function Physics.flipperTip(c: Layout.Compiled, s: State, i: number): (number, number)
	local a = s.fa[i]
	return c.fpx[i] + c.fmir[i] * Det.cos(a) * c.flen[i], c.fpy[i] + Det.sin(a) * c.flen[i]
end

local function emit(ev: { number }, code: number, ref: number, value: number, ball: number)
	local n = #ev
	ev[n + 1] = code
	ev[n + 2] = ref
	ev[n + 3] = value
	ev[n + 4] = ball
end

-- how much of a surface's liveliness a hit at this speed gets
local V0, V1 = Physics.REST_V0, Physics.REST_V1
local function fade(sp: number): number
	if sp <= V0 then
		return 0
	elseif sp >= V1 then
		return 1
	end
	return (sp - V0) / (V1 - V0)
end

-- The ball b has come within a radius of something: push it out and turn its velocity. Up to six rounds, the
-- deepest overlap first; the last round looks at the fixed table only, so if a moving flipper and a wall
-- disagree the wall wins and the ball stays on the table.
local ROUNDS = 6
local function collide(c: Layout.Compiled, s: State, b: Ball, bi: number, ev: { number }): boolean
	local touched = false
	local gridW, gridH = c.gridW, c.gridH
	local grid = c.grid
	local sx, sy, sdx, sdy, sInv, sKind = c.sx, c.sy, c.sdx, c.sdy, c.sInv, c.sKind
	local ccx, ccy, ccr = c.cx, c.cy, c.cr
	local drop = s.drop
	local nF = c.nFlip
	for round = 1, ROUNDS do
		local x, y = b.x, b.y
		local ix = floor(x * INV_CELL)
		if ix < 0 then
			ix = 0
		elseif ix >= gridW then
			ix = gridW - 1
		end
		local iy = floor(y * INV_CELL)
		if iy < 0 then
			iy = 0
		elseif iy >= gridH then
			iy = gridH - 1
		end
		local list = grid[iy * gridW + ix + 1]
		local bestPen, bestKind, bestI, bestT, bestSd = 0, 0, 0, 0, 0
		local nx, ny = 0, 0
		for li = 1, #list do
			local id = list[li]
			if id > 0 then
				local kind = sKind[id]
				if kind == SEG_DROP and drop[c.sRef[id]] then
					continue
				end
				local ax, ay = sx[id], sy[id]
				local dx, dy = sdx[id], sdy[id]
				local t = ((x - ax) * dx + (y - ay) * dy) * sInv[id]
				if t < 0 then
					t = 0
				elseif t > 1 then
					t = 1
				end
				local qx, qy = x - (ax + dx * t), y - (ay + dy * t)
				local d2 = qx * qx + qy * qy
				if d2 < R2 then
					if kind == SEG_GATE then
						-- a gate stops only a ball that is past it and coming back
						local side = (y - ay) * dx - (x - ax) * dy
						local vn = b.vy * dx - b.vx * dy
						if side <= 0 or vn >= 0 then
							continue
						end
					end
					local d = sqrt(d2)
					local pen = R - d
					if pen > bestPen then
						bestPen, bestKind, bestI, bestT = pen, 1, id, t
						if d > 1e-9 then
							nx, ny = qx / d, qy / d
						else
							local l = c.sLen[id]
							nx, ny = -dy / l, dx / l
						end
					end
				end
			else
				local i = -id
				local qx, qy = x - ccx[i], y - ccy[i]
				local rr = R + ccr[i]
				local d2 = qx * qx + qy * qy
				if d2 < rr * rr then
					local d = sqrt(d2)
					local pen = rr - d
					if pen > bestPen then
						bestPen, bestKind, bestI = pen, 2, i
						if d > 1e-9 then
							nx, ny = qx / d, qy / d
						else
							nx, ny = 0, 1
						end
					end
				end
			end
		end
		if round < ROUNDS then
			for i = 1, nF do
				local qx, qy = x - c.fpx[i], y - c.fpy[i]
				local reach = c.freach[i] + R
				if qx * qx + qy * qy < reach * reach then
					local dx, dy = fDx[i], fDy[i]
					local along = qx * dx + qy * dy
					local perp = qy * dx - qx * dy
					local sgn = 1
					if perp < 0 then
						sgn = -1
						perp = -perp
					end
					local tb, ta = c.fb[i], c.fa[i]
					local k = ta * along - tb * perp
					local sd, np, na
					if k < 0 then
						local d = sqrt(perp * perp + along * along)
						sd = d - c.frb[i]
						if d > 1e-9 then
							np, na = perp / d, along / d
						else
							np, na = 1, 0
						end
					elseif k > ta * c.flen[i] then
						local al = along - c.flen[i]
						local d = sqrt(perp * perp + al * al)
						sd = d - c.frt[i]
						if d > 1e-9 then
							np, na = perp / d, al / d
						else
							np, na = 1, 0
						end
					else
						sd = ta * perp + tb * along - c.frb[i]
						np, na = ta, tb
					end
					if sd < R and R - sd > bestPen then
						bestPen, bestKind, bestI, bestSd = R - sd, 3, i, sd
						np *= sgn
						nx = na * dx - np * dy
						ny = na * dy + np * dx
					end
				end
			end
		end
		if bestKind == 0 then
			break
		end
		touched = true
		b.x = x + nx * bestPen
		b.y = y + ny * bestPen
		if bestKind == 3 then
			-- the flipper: its surface is moving, so everything is measured against the surface
			local i = bestI
			local qx, qy = x - c.fpx[i], y - c.fpy[i]
			local px, py = qx - nx * bestSd, qy - ny * bestSd
			local om = fOm[i]
			local svx, svy = -om * py, om * px
			local rvx, rvy = b.vx - svx, b.vy - svy
			local vn = rvx * nx + rvy * ny
			if vn < 0 then
				local sp = -vn
				local e = Physics.FLIP_E * fade(sp)
				local vt = rvy * nx - rvx * ny
				if sp > V0 then
					local rub = Physics.FLIP_MU * (1 + e) * sp
					if vt > rub then
						vt -= rub
					elseif vt < -rub then
						vt += rub
					else
						vt = 0
					end
				end
				local out = e * sp
				b.vx = svx + out * nx - vt * ny
				b.vy = svy + out * ny + vt * nx
				if sp > Physics.SOUND_MIN then
					emit(ev, EV.FLIPPER, i, sp, bi)
				end
			end
		else
			local vn = b.vx * nx + b.vy * ny
			if vn < 0 then
				local sp = -vn
				local e, mu, kick
				kick = 0
				if bestKind == 1 then
					local id = bestI
					local kind = sKind[id]
					e, mu = c.sE[id], c.sMu[id]
					if kind == SEG_SLING then
						if not s.dead and sp > Physics.SLING_MIN and bestT > 0.12 and bestT < 0.88 then
							kick = Physics.SLING_KICK
							emit(ev, EV.SLING, c.sRef[id], sp, bi)
						end
					elseif kind == SEG_DROP then
						e = Physics.DROP_E
						if sp > Physics.DROP_MIN then
							drop[c.sRef[id]] = true
							emit(ev, EV.DROP, c.sRef[id], sp, bi)
						end
					elseif kind == SEG_STANDUP then
						if sp > Physics.STANDUP_MIN then
							emit(ev, EV.STANDUP, c.sRef[id], sp, bi)
						end
					elseif kind == SEG_GATE then
						if sp > Physics.SOUND_MIN then
							emit(ev, EV.GATE, c.sRef[id], sp, bi)
						end
					elseif sp > Physics.SOUND_MIN then
						emit(ev, EV.WALL, c.sMat[id], sp, bi)
					end
				else
					local i = bestI
					e, mu = c.cE[i], c.cMu[i]
					if c.cKind[i] == CIR_BUMPER then
						if not s.dead and sp > Physics.BUMPER_MIN then
							emit(ev, EV.BUMPER, c.cRef[i], 1, bi)
							-- a bumper throws the ball out at its own speed, whatever came in
							local vt = b.vy * nx - b.vx * ny
							b.vx = Physics.BUMPER_KICK * nx - vt * ny
							b.vy = Physics.BUMPER_KICK * ny + vt * nx
							continue
						end
						e = Physics.BUMPER_E
						emit(ev, EV.BUMPER, c.cRef[i], 0, bi)
					elseif sp > Physics.SOUND_MIN then
						emit(ev, EV.POST, 0, sp, bi)
					end
				end
				e *= fade(sp)
				local vt = b.vy * nx - b.vx * ny
				if sp > V0 then
					local rub = mu * (1 + e) * sp
					if vt > rub then
						vt -= rub
					elseif vt < -rub then
						vt += rub
					else
						vt = 0
					end
				end
				local out = e * sp + kick
				b.vx = out * nx - vt * ny
				b.vy = out * ny + vt * nx
			end
		end
	end
	return touched
end

-- A ball on a rail: one number along it. Climbing costs speed; a stalled ball rolls back out of the mouth.
local function ride(c: Layout.Compiled, b: Ball, bi: number, ev: { number })
	local r = c.rails[b.ref]
	local k = b.k
	local v = b.v - (c.gravity * r.ty[k] + Physics.GRAVITY_H * r.slope[k]) * DT
	v -= v * r.drag * DT
	local at = b.s + v * DT
	b.v = v
	b.s = at
	if at >= r.total then
		local last = r.n - 1
		b.x, b.y, b.z = r.x[r.n], r.y[r.n], 0
		b.vx, b.vy = r.tx[last] * r.exitSpeed, r.ty[last] * r.exitSpeed
		b.mode = FREE
		b.cool = 0
		emit(ev, EV.RAIL_OUT, b.ref, 1, bi)
		return
	elseif at <= 0 then
		local sp = if v < 0 then -v else 0.5
		b.x, b.y, b.z = r.x[1] - r.tx[1] * 0.02, r.y[1] - r.ty[1] * 0.02, 0
		b.vx, b.vy = -r.tx[1] * sp, -r.ty[1] * sp
		b.mode = FREE
		emit(ev, EV.RAIL_OUT, b.ref, 0, bi)
		return
	end
	while k < r.n - 1 and at > r.at[k + 1] do
		k += 1
	end
	while k > 1 and at < r.at[k] do
		k -= 1
	end
	b.k = k
	local u = at - r.at[k]
	b.x = r.x[k] + r.tx[k] * u
	b.y = r.y[k] + r.ty[k] * u
	b.z = r.h[k] + r.slope[k] * u
end

-- step(compiled, state, left, right, events): one tick of 1/240 s.
function Physics.step(c: Layout.Compiled, s: State, left: boolean, right: boolean, ev: { number })
	s.tick += 1
	local balls = s.balls
	local nBalls = #balls
	local nF = c.nFlip
	local g = c.gravity

	-- the flippers move first: where each will be at the end of the tick, and how fast its surface turns
	local reachMoved = 0
	local anyMoved = false
	for i = 1, nF do
		local a0, w = s.fa[i], s.fw[i]
		local a1 = a0
		local pressed = not s.dead and ((c.fbtn[i] == 1 and left) or (c.fbtn[i] == 2 and right))
		if pressed ~= s.fp[i] then
			s.fp[i] = pressed
			emit(ev, if pressed then EV.FLIP_UP else EV.FLIP_DOWN, i, 0, 0)
		end
		if pressed then
			local up = c.fup[i]
			if a0 < up or w ~= 0 then
				w += Physics.FLIP_ACC_UP * DT
				if w > Physics.FLIP_W_MAX then
					w = Physics.FLIP_W_MAX
				end
				a1 = a0 + w * DT
				if a1 >= up then
					a1 = up
					w = if w > Physics.FLIP_BOUNCE_MIN then -w * Physics.FLIP_STOP_E else 0
				end
			end
		else
			local rest = c.frest[i]
			if a0 > rest or w ~= 0 then
				w -= Physics.FLIP_ACC_DOWN * DT
				if w < -Physics.FLIP_W_DOWN then
					w = -Physics.FLIP_W_DOWN
				end
				a1 = a0 + w * DT
				if a1 <= rest then
					a1 = rest
					w = if -w > Physics.FLIP_BOUNCE_MIN then -w * Physics.FLIP_REST_E else 0
				end
			end
		end
		s.fw[i] = w
		s.fa[i] = a1
		fA0[i] = a0
		local da = a1 - a0
		fDA[i] = da
		fOm[i] = c.fmir[i] * da / DT
		if da ~= 0 then
			anyMoved = true
			local moved = (if da < 0 then -da else da) * (c.freach[i] + R)
			if moved > reachMoved then
				reachMoved = moved
			end
		else
			fDx[i] = c.fmir[i] * Det.cos(a1)
			fDy[i] = Det.sin(a1)
		end
	end

	-- how fine to cut this tick
	local top2 = 0
	local anyFree = false
	for bi = 1, nBalls do
		local b = balls[bi]
		if b.mode == FREE then
			if anyMoved and b.asleep then
				b.asleep = false
				b.still = 0
			end
			if not b.asleep then
				anyFree = true
				local v2 = b.vx * b.vx + b.vy * b.vy
				if v2 > top2 then
					top2 = v2
				end
			end
		end
	end
	local n = 1
	if anyFree then
		n = math.ceil(((sqrt(top2) + g * DT) * DT + reachMoved) / Physics.SUB_TRAVEL)
		if n < 1 then
			n = 1
		elseif n > Physics.MAX_SUBSTEPS then
			n = Physics.MAX_SUBSTEPS
		end
	end
	local h = DT / n
	local maxV2 = Physics.MAX_SPEED * Physics.MAX_SPEED
	local sgrid = c.sgrid
	local gridW, gridH = c.gridW, c.gridH

	if anyFree then
		for k = 1, n do
			if anyMoved then
				local frac = k / n
				for i = 1, nF do
					local da = fDA[i]
					if da ~= 0 then
						local a = if k == n then s.fa[i] else fA0[i] + da * frac
						fDx[i] = c.fmir[i] * Det.cos(a)
						fDy[i] = Det.sin(a)
					end
				end
			end
			for bi = 1, nBalls do
				local b = balls[bi]
				if b.mode ~= FREE or b.asleep then
					continue
				end
				local x0, y0 = b.x, b.y
				local vx, vy = b.vx, b.vy - g * h
				local sp2 = vx * vx + vy * vy
				if sp2 > 1e-12 then
					local sp = sqrt(sp2)
					local lose = Physics.ROLL_DECEL * h
					if sp <= lose then
						vx, vy = 0, 0
					else
						local keep = 1 - lose / sp
						vx *= keep
						vy *= keep
					end
				end
				b.vx, b.vy = vx, vy
				b.x = x0 + vx * h
				b.y = y0 + vy * h
				if collide(c, s, b, bi, ev) then
					b.hit = true
				end
				vx, vy = b.vx, b.vy
				sp2 = vx * vx + vy * vy
				if sp2 > maxV2 then
					local keep = Physics.MAX_SPEED / sqrt(sp2)
					b.vx = vx * keep
					b.vy = vy * keep
				end

				-- switches the ball rolled over in this sub-step, ramp mouths among them
				local x1, y1 = b.x, b.y
				local ix = floor(x1 * INV_CELL)
				if ix < 0 then
					ix = 0
				elseif ix >= gridW then
					ix = gridW - 1
				end
				local iy = floor(y1 * INV_CELL)
				if iy < 0 then
					iy = 0
				elseif iy >= gridH then
					iy = gridH - 1
				end
				local list = sgrid[iy * gridW + ix + 1]
				for li = 1, #list do
					local id = list[li]
					local ax, ay = c.nx1[id], c.ny1[id]
					local dx, dy = c.ndx[id], c.ndy[id]
					local s0 = (y0 - ay) * dx - (x0 - ax) * dy
					local s1 = (y1 - ay) * dx - (x1 - ax) * dy
					if (s0 <= 0 and s1 > 0) or (s0 > 0 and s1 <= 0) then
						local u = s0 / (s0 - s1)
						local px, py = x0 + (x1 - x0) * u, y0 + (y1 - y0) * u
						local t = ((px - ax) * dx + (py - ay) * dy) * c.nInv[id]
						if t >= 0 and t <= 1 then
							local kind = c.nKind[id]
							local dir = if s1 > 0 then 1 else -1
							if kind == SEN_ROLLOVER then
								emit(ev, EV.ROLLOVER, c.nRef[id], dir, bi)
							elseif kind == SEN_SPINNER then
								local len = sqrt(dx * dx + dy * dy)
								local through = (b.vy * dx - b.vx * dy) / len
								local w = through * Physics.SPIN_PER_SPEED
								local have = s.spinW[id]
								if (if w < 0 then -w else w) > (if have < 0 then -have else have) then
									s.spinW[id] = w
								end
								b.vx *= Physics.SPIN_BALL_KEEP
								b.vy *= Physics.SPIN_BALL_KEEP
								emit(ev, EV.SPINNER, c.nRef[id], if through < 0 then -through else through, bi)
							elseif dir == 1 then
								local ri = c.nRef[id]
								local r = c.rails[ri]
								local va = b.vx * r.tx[1] + b.vy * r.ty[1]
								if va >= r.minSpeed then
									b.mode = RAIL
									b.ref = ri
									b.s = 0
									b.v = va
									b.k = 1
									b.x, b.y, b.z = r.x[1], r.y[1], r.h[1]
									b.vx, b.vy = 0, 0
									b.still = 0
									emit(ev, EV.RAIL_IN, ri, va, bi)
									break
								end
							end
						end
					end
				end
				if b.mode ~= FREE then
					continue
				end

				-- kick-out holes
				if b.cool == 0 then
					for j, sc in c.def.saucers do
						local qx, qy = b.x - sc.x, b.y - sc.y
						if qx * qx + qy * qy < sc.r * sc.r then
							if b.vx * b.vx + b.vy * b.vy < sc.maxSpeed * sc.maxSpeed then
								b.mode = HELD
								b.ref = j
								b.timer = sc.holdTicks
								b.x, b.y = sc.x, sc.y
								b.vx, b.vy = 0, 0
								b.still = 0
								emit(ev, EV.SAUCER, j, 0, bi)
								break
							end
						end
					end
				end
			end

			-- ball against ball (multiball): equal masses trade their speed along the line between them
			if nBalls > 1 then
				for i = 1, nBalls - 1 do
					local a = balls[i]
					if a.mode ~= FREE then
						continue
					end
					for j = i + 1, nBalls do
						local b = balls[j]
						if b.mode ~= FREE or (a.asleep and b.asleep) then
							continue
						end
						local qx, qy = b.x - a.x, b.y - a.y
						local d2 = qx * qx + qy * qy
						if d2 < 4 * R2 then
							local d = sqrt(d2)
							local nx, ny = 1, 0
							if d > 1e-9 then
								nx, ny = qx / d, qy / d
							end
							local half = (2 * R - d) / 2
							a.x -= nx * half
							a.y -= ny * half
							b.x += nx * half
							b.y += ny * half
							local vn = (b.vx - a.vx) * nx + (b.vy - a.vy) * ny
							if vn < 0 then
								local j2 = -(1 + Physics.BALL_E * fade(-vn)) * vn / 2
								a.vx -= j2 * nx
								a.vy -= j2 * ny
								b.vx += j2 * nx
								b.vy += j2 * ny
								if -vn > Physics.SOUND_MIN then
									emit(ev, EV.BALLS, 0, -vn, i)
								end
							end
							a.asleep, b.asleep = false, false
							-- a ball shoved by another must not be left inside a wall
							collide(c, s, a, i, ev)
							collide(c, s, b, j, ev)
						end
					end
				end
			end
		end
	end

	-- once a tick: rails, held balls, drains, sleep
	for bi = 1, nBalls do
		local b = balls[bi]
		local mode = b.mode
		if b.cool > 0 then
			b.cool -= 1
		end
		if mode == FREE then
			if b.y < c.drainY then
				b.mode = GONE
				emit(ev, EV.DRAIN, 0, b.x, bi)
			elseif not b.asleep then
				-- slow and touching something for a quarter of a second: it has come to rest
				if b.hit and b.vx * b.vx + b.vy * b.vy < Physics.SLEEP_V * Physics.SLEEP_V then
					b.still += 1
					if b.still >= Physics.SLEEP_TICKS then
						b.asleep = true
						b.vx, b.vy = 0, 0
						b.still = 0
					end
				else
					b.still = 0
				end
			end
			b.hit = false
		elseif mode == RAIL then
			ride(c, b, bi, ev)
		elseif mode == HELD then
			if b.timer > 0 then
				b.timer -= 1
				if b.timer == 0 then
					local sc = c.def.saucers[b.ref]
					local j1 = 1 + (Physics.rand(s) * 2 - 1) * Physics.EJECT_JITTER
					local j2 = (Physics.rand(s) * 2 - 1) * Physics.EJECT_JITTER
					b.vx = sc.vx * j1 - sc.vy * j2
					b.vy = sc.vy * j1 + sc.vx * j2
					b.mode = FREE
					b.cool = Physics.EJECT_COOL
					emit(ev, EV.EJECT, b.ref, 0, bi)
				end
			end
		end
	end

	-- spinners run down
	for _, id in c.spinners do
		local w = s.spinW[id]
		if w ~= 0 then
			local mag = if w < 0 then -w else w
			local a = s.spinA[id] + mag * DT
			while a >= 1 do
				a -= 1
				emit(ev, EV.SPIN, c.nRef[id], mag, 0)
			end
			s.spinA[id] = a
			mag -= (Physics.SPIN_FRICTION + Physics.SPIN_DRAG * mag) * DT
			if mag <= 0 then
				s.spinW[id] = 0
			else
				s.spinW[id] = if w < 0 then -mag else mag
			end
		end
	end
end

Physics.FREE, Physics.RAIL, Physics.HELD, Physics.GONE = FREE, RAIL, HELD, GONE

return Physics
