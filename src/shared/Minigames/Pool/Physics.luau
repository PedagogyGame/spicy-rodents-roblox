--!strict
-- ReplicatedStorage.Shared.Minigames.Pool.Physics
-- The table model both cue games share: every ball on one table for one fixed step. No Roblox physics: the
-- server runs this the moment a ball is struck and every client draws the result (Shot), and the same code
-- runs the aim preview and the computer players. A world is plain data (the table, the balls, the clock, the
-- events and key points so far): state in, state out, nothing hidden, so the same world stepped twice gives
-- the same bytes.
-- A step is DT (1/240 s). Inside it nothing is ever allowed to overlap: the model finds the EARLIEST moment in
-- the step at which a ball would touch another ball, a cushion, a pocket's jaw or point, a post, or a hole's
-- rim (solved exactly from where the balls are and how they move), moves every ball on to that moment with
-- Cloth.advance, settles that one contact, and looks again until the step is used up. So nothing tunnels at
-- any speed, a cut is as thin as it was aimed, a tight rack breaks ball by ball in the order the contacts
-- really happen (ties go to the lower ball, then the table's own order), and the same break is the same
-- break every time.
--   Ball to ball: equal masses, restitution E_BALL along the line of centres, and a little friction between
--   the balls that falls as they rub faster: that is cut and spin THROW and the spin one ball hands another.
--   A stunned cue ball leaves along the tangent line; the cloth then bends a rolling one forward and brings a
--   drawn one back (Cloth).
--   Cushions: the speed into the cushion comes back times a restitution that falls from E_SOFT to E_HARD as
--   the shot gets harder; the cushion's grip on the ball's side (speed along the cushion plus side spin)
--   takes or gives up to MU of the hit, which is how running side widens the angle and check side narrows
--   it; a hard hit sinks in and comes off a little short (SHORTEN); and the ball leaves with ROLL of a
--   natural roll already on it, so a bank learned once works again.
--   Jaws are cushions that give less back, with the point between cushion and jaw as a round corner: a ball
--   that catches a point rattles. Posts (bumper pool) are small, lively rubber circles.
--   Holes: a ball whose centre crosses a hole's rim is in the air and falls (Cloth). Down by the hole's
--   depth it is pocketed. If it reaches the rim again first: behind a pocket is the liner, which kills it and
--   drops it; anywhere else it must climb back out, which costs RIM_K times the height it fell taken from its
--   outward speed: a slow ball cannot (it tips back in), a fast one skips over, and one in between is turned
--   off its line and lips out. That is a cup's whole character and a hanging ball's too.
-- Everything in a step is + - * / and sqrt. Pure; Lune-tested (tests/unit/pool_physics.spec.luau).
-- Interface: constants and the Response sets; world(table, spots) -> World; strike(world, id, vx, vz, qx,
--   qz, s); step(world) -> moving; ball(world, id) -> Ball?; energy(world) -> number; moving(world) ->
--   boolean; EV (event kinds). world.events is flat { t, kind, a, b, speed, ... } (EVENT_STRIDE numbers each);
--   world.keys[i] is ball i's flat key points { t, x, z, vx, vz, qx, qz, s, y, mode, ... } (KEY_STRIDE each),
--   written whenever something changes its motion.

local Cloth = require("./Cloth")
local Tables = require("./Tables")

local Physics = {}

Physics.DT = 1 / 240
Physics.MAX_EVENTS = 64 -- contacts settled inside one step before the rest of the step is given up
Physics.E_BALL = 0.94 -- ball to ball
Physics.TOUCH = 0.004 -- studs: balls this close are touching (they are struck together, as one wave)
Physics.WAVE_SWEEPS = 40 -- the most sweeps over a wave's contacts
-- friction between two balls: MU_BALL_MIN + MU_BALL_VAR / (1 + C1 u + C2 u^2), u = rubbing speed in studs/s
Physics.MU_BALL_MIN = 0.01
Physics.MU_BALL_VAR = 0.108
Physics.MU_BALL_C1 = 0.2016
Physics.MU_BALL_C2 = 0.01694
Physics.V_DEAD = 0.06 -- studs/s: below this a touch does not bounce at all
Physics.RIM_K = 1 -- the price of climbing out of a hole, in fallen heights
Physics.E_LINER = 0.25 -- the back of a pocket
Physics.LINER_DOT = -0.05 -- behind this (dot with the mouth direction) the rim is liner, not cloth

export type Response = {
	eSoft: number, -- restitution of a soft touch
	eHard: number, -- and of the hardest
	hard: number, -- studs/s into the surface at which it is half way between them
	mu: number, -- grip along the surface
	shorten: number, -- share of the speed along the surface lost on the hardest hit
	keep: number, -- share of the roll into the surface the ball keeps
	roll: number, -- share of a natural roll it leaves with
}
Physics.CUSHION = { eSoft = 0.86, eHard = 0.7, hard = 24, mu = 0.25, shorten = 0.2, keep = 0.1, roll = 0.4 } :: Response
Physics.JAW = { eSoft = 0.62, eHard = 0.45, hard = 20, mu = 0.2, shorten = 0.1, keep = 0.1, roll = 0.2 } :: Response
Physics.POST = { eSoft = 0.92, eHard = 0.84, hard = 30, mu = 0.1, shorten = 0, keep = 0.1, roll = 0.4 } :: Response

Physics.EV = {
	ball = 1, -- a hit b (ball ids), speed = closing speed
	cushion = 2, -- a = ball, b = segment index
	jaw = 3, -- a = ball, b = segment index (a pocket facing or point)
	post = 4, -- a = ball, b = post index
	enter = 5, -- a = ball, b = hole: its centre is over the rim
	drop = 6, -- a = ball, b = hole: pocketed
	rim = 7, -- a = ball, b = hole: it climbed back out (a lip-out or a skip)
	liner = 8, -- a = ball, b = hole: it hit the back of the pocket
}
Physics.EVENT_STRIDE = 5
Physics.KEY_STRIDE = 10

export type World = {
	table: Tables.Table,
	balls: { Cloth.Ball },
	t: number,
	steps: number,
	events: { number },
	keys: { { number } },
	contacts: number, -- contacts settled so far (a cost measure)
}

function Physics.world(tb: Tables.Table, spots: { Tables.Spot }): World
	local balls: { Cloth.Ball } = {}
	local keys: { { number } } = {}
	for i, s in spots do
		balls[i] = Cloth.new(s.id, s.x, s.z)
		keys[i] = {}
	end
	return { table = tb, balls = balls, t = 0, steps = 0, events = {}, keys = keys, contacts = 0 }
end

function Physics.ball(w: World, id: number): Cloth.Ball?
	for _, b in w.balls do
		if b.id == id then
			return b
		end
	end
	return nil
end

local function indexOf(w: World, id: number): number
	for i, b in w.balls do
		if b.id == id then
			return i
		end
	end
	return 0
end

local function key(w: World, i: number, t: number)
	local b = w.balls[i]
	local k = w.keys[i]
	local n = #k
	k[n + 1] = t
	k[n + 2] = b.x
	k[n + 3] = b.z
	k[n + 4] = b.vx
	k[n + 5] = b.vz
	k[n + 6] = b.qx
	k[n + 7] = b.qz
	k[n + 8] = b.s
	k[n + 9] = b.y
	k[n + 10] = b.mode
end

local function event(w: World, t: number, kind: number, a: number, b: number, speed: number)
	local e = w.events
	local n = #e
	e[n + 1] = t
	e[n + 2] = kind
	e[n + 3] = a
	e[n + 4] = b
	e[n + 5] = speed
end

-- Set a resting ball going (the cue's strike): velocity, roll and side spin.
function Physics.strike(w: World, id: number, vx: number, vz: number, qx: number, qz: number, s: number)
	local i = indexOf(w, id)
	assert(i > 0, "no such ball")
	local b = w.balls[i]
	assert(b.mode == 0, "ball is not at rest on the table")
	b.vx, b.vz, b.qx, b.qz, b.s = vx, vz, qx, qz, s
	b.mode = 1
	key(w, i, w.t)
end

function Physics.energy(w: World): number
	local e = 0
	for _, b in w.balls do
		e += Cloth.energy(b)
	end
	return e
end

function Physics.moving(w: World): boolean
	for _, b in w.balls do
		if b.mode == 1 or b.mode == 2 then
			return true
		end
	end
	return false
end

local E_BALL = Physics.E_BALL
local V_DEAD = Physics.V_DEAD

-- A ball meets a fixed surface whose inward normal (from the ball to the surface) is nx, nz.
local function bounce(b: Cloth.Ball, nx: number, nz: number, P: Response): number
	local vn = b.vx * nx + b.vz * nz
	if vn <= 0 then
		return 0
	end
	local h = vn / (vn + P.hard)
	local e = if vn < V_DEAD then 0 else P.eSoft - (P.eSoft - P.eHard) * h
	local tx, tz = -nz, nx
	local vt = b.vx * tx + b.vz * tz
	local uh = vt + b.s
	local pmax = P.mu * (1 + e) * vn
	local p = uh * (2 / 7)
	if p > pmax then
		p = pmax
	elseif p < -pmax then
		p = -pmax
	end
	local vt2 = (vt - p) * (1 - P.shorten * h)
	local vn2 = -e * vn
	local qn = b.qx * nx + b.qz * nz
	local qt = b.qx * tx + b.qz * tz
	local qn2 = P.keep * qn + P.roll * vn2
	b.s -= 2.5 * p
	b.vx = vn2 * nx + vt2 * tx
	b.vz = vn2 * nz + vt2 * tz
	b.qx = qn2 * nx + qt * tx
	b.qz = qn2 * nz + qt * tz
	return vn
end

-- A WAVE: every pair of balls that is touching (within TOUCH) and closing at this instant, settled together.
-- Each contact must turn its closing speed u into a parting speed E_BALL u; the impulses that do it are found
-- by sweeping the contacts in a fixed order until they agree (an impulse can push, never pull). One pair
-- alone gets exactly the two-ball answer. A ball that drives into two at once shares itself between them
-- evenly, which is what makes a tight rack burst open instead of handing everything down one line of balls.
-- A wave can never add energy: if the sweep overshoots, the whole wave is scaled back to break even.
-- Then each contact rubs: the friction between the balls is throw and handed-on spin.
local function wave(w: World, t: number, R: number)
	local balls = w.balls
	local n = #balls
	local lim = 2 * R + Physics.TOUCH
	local lim2 = lim * lim
	local ci: { number }, cj: { number } = {}, {}
	local cnx: { number }, cnz: { number }, cu: { number }, cl: { number } = {}, {}, {}, {}
	local nc = 0
	for i = 1, n - 1 do
		local a = balls[i]
		if a.mode <= 2 then
			for j = i + 1, n do
				local b = balls[j]
				if b.mode <= 2 then
					local dx, dz = b.x - a.x, b.z - a.z
					local d2 = dx * dx + dz * dz
					if d2 <= lim2 and d2 > 0 then
						local closing = (a.vx - b.vx) * dx + (a.vz - b.vz) * dz
						if closing > 0 then
							local d = math.sqrt(d2)
							nc += 1
							ci[nc], cj[nc] = i, j
							cnx[nc], cnz[nc] = dx / d, dz / d
							cu[nc] = closing / d
							cl[nc] = 0
							-- balls that have sunk into each other (only ever by a hair) are set touching again
							local over = 2 * R - d
							if over > 0 then
								local half = 0.5 * over
								a.x -= dx / d * half
								a.z -= dz / d * half
								b.x += dx / d * half
								b.z += dz / d * half
							end
						end
					end
				end
			end
		end
	end
	if nc == 0 then
		return
	end
	-- the velocity each ball had before the wave (for the energy check)
	local pvx: { [number]: number }, pvz: { [number]: number } = {}, {}
	if nc > 1 then
		for c = 1, nc do
			local i, j = ci[c], cj[c]
			pvx[i], pvz[i] = balls[i].vx, balls[i].vz
			pvx[j], pvz[j] = balls[j].vx, balls[j].vz
		end
	end
	local sweeps = if nc == 1 then 1 else Physics.WAVE_SWEEPS
	for _ = 1, sweeps do
		local worst = 0
		for c = 1, nc do
			local a, b = balls[ci[c]], balls[cj[c]]
			local nx, nz = cnx[c], cnz[c]
			local u = cu[c]
			local e = if u < V_DEAD then 0 else E_BALL
			local rel = (a.vx - b.vx) * nx + (a.vz - b.vz) * nz
			local l0 = cl[c]
			local l1 = l0 + 0.5 * (rel + e * u)
			if l1 < 0 then
				l1 = 0
			end
			local dl = l1 - l0
			if dl ~= 0 then
				cl[c] = l1
				a.vx -= dl * nx
				a.vz -= dl * nz
				b.vx += dl * nx
				b.vz += dl * nz
				if dl > worst then
					worst = dl
				elseif -dl > worst then
					worst = -dl
				end
			end
		end
		if worst < 1e-7 then
			break
		end
	end
	if nc > 1 then
		local before, after, cross, dd = 0, 0, 0, 0
		for i, x in pvx do
			local a = balls[i]
			local z = pvz[i]
			local ex, ez = a.vx - x, a.vz - z
			before += x * x + z * z
			after += a.vx * a.vx + a.vz * a.vz
			cross += x * ex + z * ez
			dd += ex * ex + ez * ez
		end
		if after > before and dd > 0 then
			-- scale the whole wave back to break even (momentum is kept at any scale)
			local s = -2 * cross / dd
			if s < 0 then
				s = 0
			end
			if s < 1 then
				for i, x in pvx do
					local a = balls[i]
					local z = pvz[i]
					a.vx = x + s * (a.vx - x)
					a.vz = z + s * (a.vz - z)
				end
				for c = 1, nc do
					cl[c] *= s
				end
			end
		end
	end
	for c = 1, nc do
		local jn = cl[c]
		if jn > 0 then
			local i, j = ci[c], cj[c]
			local a, b = balls[i], balls[j]
			local nx, nz = cnx[c], cnz[c]
			local tx, tz = -nz, nx
			-- rubbing at the contact point: along the level (motion plus both side spins) and up and down (both rolls)
			local uh = (a.vx - b.vx) * tx + (a.vz - b.vz) * tz + a.s + b.s
			local uv = -((a.qx + b.qx) * nx + (a.qz + b.qz) * nz)
			local u = math.sqrt(uh * uh + uv * uv)
			if u > 1e-9 then
				local mu = Physics.MU_BALL_MIN
					+ Physics.MU_BALL_VAR / (1 + Physics.MU_BALL_C1 * u + Physics.MU_BALL_C2 * u * u)
				local pmax = mu * jn
				local ph = pmax * uh / u
				if math.abs(ph) > math.abs(uh) / 7 then
					ph = uh / 7
				end
				local pv = pmax * uv / u
				if math.abs(pv) > math.abs(uv) / 5 then
					pv = uv / 5
				end
				a.vx -= ph * tx
				a.vz -= ph * tz
				b.vx += ph * tx
				b.vz += ph * tz
				a.s -= 2.5 * ph
				b.s -= 2.5 * ph
				local dq = 2.5 * pv
				a.qx += dq * nx
				a.qz += dq * nz
				b.qx += dq * nx
				b.qz += dq * nz
			end
			if a.mode == 0 then
				a.mode = 1
			end
			if b.mode == 0 then
				b.mode = 1
			end
			event(w, t, 1, a.id, b.id, cu[c])
			key(w, i, t)
			key(w, j, t)
		end
	end
end

-- candidate kinds inside step()
local C_BALL, C_FACE, C_END1, C_END2, C_POST, C_ENTER, C_EXIT, C_DROP = 1, 2, 3, 4, 5, 6, 7, 8

-- One fixed step. Returns whether anything is still moving.
function Physics.step(w: World): boolean
	local tb = w.table
	local balls = w.balls
	local n = #balls
	local R = tb.ballR
	local R2 = R * R
	local D2 = 4 * R2
	local segs, posts, holes = tb.segs, tb.posts, tb.holes
	local nSegs, nPosts, nHoles = #segs, #posts, #holes
	local safeX, safeZ = tb.safeX, tb.safeZ
	local inner = nPosts > 0 or (nHoles > 0 and holes[1].cup)
	local G = Cloth.G
	local remaining = Physics.DT
	local t = w.t
	local guard = 0
	local anyMoving = false
	while true do
		local best = remaining
		local kind, bi, bj = 0, 0, 0
		anyMoving = false
		for i = 1, n do
			local a = balls[i]
			local ma = a.mode
			if ma == 1 or ma == 2 then
				anyMoving = true
				local ax, az, avx, avz = a.x, a.z, a.vx, a.vz
				local sp2 = avx * avx + avz * avz
				if sp2 > 0 then
					local reach = math.sqrt(sp2) * best
					local absX = if ax < 0 then -ax else ax
					local absZ = if az < 0 then -az else az
					local nearEdge = absX + reach >= safeX or absZ + reach >= safeZ
					if nearEdge then
						for k = 1, nSegs do
							local sg = segs[k]
							if
								ax >= sg.minX - reach
								and ax <= sg.maxX + reach
								and az >= sg.minZ - reach
								and az <= sg.maxZ + reach
							then
								local tx, tz = sg.tx, sg.tz
								local px, pz = ax - sg.x1, az - sg.z1
								-- the face: signed distance from the line (normal -tz, tx) and place along it
								local sd = pz * tx - px * tz
								local vn = avz * tx - avx * tz
								local faced = false
								if (sd >= 0 and vn < 0) or (sd < 0 and vn > 0) then
									local gap = (if sd < 0 then -sd else sd) - R
									local tt = if gap <= 0 then 0 else gap / (if vn < 0 then -vn else vn)
									if tt <= best then
										local al = px * tx + pz * tz + (avx * tx + avz * tz) * tt
										if al >= 0 and al <= sg.len then
											faced = true
											if tt < best then
												best, kind, bi, bj = tt, C_FACE, i, k
											end
										end
									end
								end
								if not faced then
									-- the two ends as round corners
									local ex, ez = sg.x1 - ax, sg.z1 - az
									local bd = ex * avx + ez * avz
									if bd > 0 then
										local c = ex * ex + ez * ez - R2
										if c <= 0 then
											if 0 < best then
												best, kind, bi, bj = 0, C_END1, i, k
											end
										else
											local disc = bd * bd - sp2 * c
											local rhs = bd - sp2 * best
											if disc >= 0 and (rhs <= 0 or disc > rhs * rhs) then
												best, kind, bi, bj = (bd - math.sqrt(disc)) / sp2, C_END1, i, k
											end
										end
									end
									ex, ez = sg.x2 - ax, sg.z2 - az
									bd = ex * avx + ez * avz
									if bd > 0 then
										local c = ex * ex + ez * ez - R2
										if c <= 0 then
											if 0 < best then
												best, kind, bi, bj = 0, C_END2, i, k
											end
										else
											local disc = bd * bd - sp2 * c
											local rhs = bd - sp2 * best
											if disc >= 0 and (rhs <= 0 or disc > rhs * rhs) then
												best, kind, bi, bj = (bd - math.sqrt(disc)) / sp2, C_END2, i, k
											end
										end
									end
								end
							end
						end
					end
					if inner then
						for k = 1, nPosts do
							local p = posts[k]
							local ex, ez = p.x - ax, p.z - az
							local bd = ex * avx + ez * avz
							if bd > 0 then
								local lim = p.r + R
								local c = ex * ex + ez * ez - lim * lim
								if c <= 0 then
									if 0 < best then
										best, kind, bi, bj = 0, C_POST, i, k
									end
								else
									local disc = bd * bd - sp2 * c
									local rhs = bd - sp2 * best
									if disc >= 0 and (rhs <= 0 or disc > rhs * rhs) then
										best, kind, bi, bj = (bd - math.sqrt(disc)) / sp2, C_POST, i, k
									end
								end
							end
						end
					end
					if ma == 1 and (nearEdge or inner) then
						-- onto a hole: the centre crosses the rim going in
						for k = 1, nHoles do
							local hole = holes[k]
							local ex, ez = hole.x - ax, hole.z - az
							local bd = ex * avx + ez * avz
							if bd > 0 then
								local c = ex * ex + ez * ez - hole.r * hole.r
								if c <= 0 then
									if 0 < best then
										best, kind, bi, bj = 0, C_ENTER, i, k
									end
								else
									local disc = bd * bd - sp2 * c
									local rhs = bd - sp2 * best
									if disc >= 0 and (rhs <= 0 or disc > rhs * rhs) then
										best, kind, bi, bj = (bd - math.sqrt(disc)) / sp2, C_ENTER, i, k
									end
								end
							end
						end
					end
				end
				if ma == 2 then
					local hole = holes[a.hole]
					-- down for good
					local tDrop = (math.sqrt(2 * G * hole.depth) - math.sqrt(-2 * G * a.y)) / G
					if tDrop < best then
						best, kind, bi, bj = if tDrop < 0 then 0 else tDrop, C_DROP, i, a.hole
					end
					-- back to the rim from inside
					if sp2 > 0 then
						local ex, ez = ax - hole.x, az - hole.z
						local dv = ex * avx + ez * avz
						local c = ex * ex + ez * ez - hole.r * hole.r
						if c >= 0 then
							if dv > 0 and 0 < best then
								best, kind, bi, bj = 0, C_EXIT, i, a.hole
							end
						else
							local tt = (-dv + math.sqrt(dv * dv - sp2 * c)) / sp2
							if tt < best then
								best, kind, bi, bj = tt, C_EXIT, i, a.hole
							end
						end
					end
				end
				-- other balls: each moving pair once, and every ball at rest
				for j = 1, n do
					local b = balls[j]
					local mb = b.mode
					if (mb == 0 or (j > i and (mb == 1 or mb == 2))) and j ~= i then
						local dx, dz = b.x - ax, b.z - az
						local rvx, rvz = avx - b.vx, avz - b.vz
						local bd = dx * rvx + dz * rvz
						if bd > 0 then
							local c = dx * dx + dz * dz - D2
							if c <= 0 then
								if 0 < best then
									best, kind, bi, bj = 0, C_BALL, i, j
								end
							else
								local aa = rvx * rvx + rvz * rvz
								local disc = bd * bd - aa * c
								local rhs = bd - aa * best
								if disc >= 0 and (rhs <= 0 or disc > rhs * rhs) then
									best, kind, bi, bj = (bd - math.sqrt(disc)) / aa, C_BALL, i, j
								end
							end
						end
					end
				end
			end
		end
		if not anyMoving then
			break
		end
		if guard >= Physics.MAX_EVENTS then
			-- a knot of contacts this step cannot untie: the rest of the step is given up (the balls wait where
			-- they are for a few thousandths of a second) rather than let anything move unchecked
			break
		end
		if kind == 0 then
			for i = 1, n do
				local a = balls[i]
				if a.mode == 1 or a.mode == 2 then
					Cloth.advance(a, remaining)
				end
			end
			break
		end
		if best > 0 then
			for i = 1, n do
				local a = balls[i]
				if a.mode == 1 or a.mode == 2 then
					Cloth.advance(a, best)
				end
			end
			t += best
			remaining -= best
		end
		guard += 1
		local a = balls[bi]
		if a.mode == 0 then
			-- it came to rest at the very moment of the contact
			a.mode = 1
		end
		if kind == C_BALL then
			wave(w, t, R)
		elseif kind == C_FACE or kind == C_END1 or kind == C_END2 then
			local sg = segs[bj]
			local nx: number, nz: number
			if kind == C_FACE then
				local sd = (a.z - sg.z1) * sg.tx - (a.x - sg.x1) * sg.tz
				-- the normal from the ball to the cushion, and the ball set back on the surface if it sank in
				if sd >= 0 then
					nx, nz = sg.tz, -sg.tx
				else
					nx, nz = -sg.tz, sg.tx
					sd = -sd
				end
				if sd < R then
					a.x -= nx * (R - sd)
					a.z -= nz * (R - sd)
				end
			else
				local ex = (if kind == C_END1 then sg.x1 else sg.x2) - a.x
				local ez = (if kind == C_END1 then sg.z1 else sg.z2) - a.z
				local d = math.sqrt(ex * ex + ez * ez)
				if d > 0 then
					nx, nz = ex / d, ez / d
					if d < R then
						a.x -= nx * (R - d)
						a.z -= nz * (R - d)
					end
				else
					nx, nz = 0, 0
				end
			end
			local speed = bounce(a, nx, nz, if sg.jaw then Physics.JAW else Physics.CUSHION)
			if speed > 0 then
				event(w, t, if sg.jaw or kind ~= C_FACE then 3 else 2, a.id, bj, speed)
				key(w, bi, t)
			end
		elseif kind == C_POST then
			local p = posts[bj]
			local ex, ez = p.x - a.x, p.z - a.z
			local d = math.sqrt(ex * ex + ez * ez)
			if d > 0 then
				local nx, nz = ex / d, ez / d
				local lim = p.r + R
				if d < lim then
					a.x -= nx * (lim - d)
					a.z -= nz * (lim - d)
				end
				local speed = bounce(a, nx, nz, Physics.POST)
				if speed > 0 then
					event(w, t, 4, a.id, bj, speed)
					key(w, bi, t)
				end
			end
		elseif kind == C_ENTER then
			a.mode = 2
			a.y = 0
			a.hole = bj
			event(w, t, 5, a.id, bj, math.sqrt(a.vx * a.vx + a.vz * a.vz))
			key(w, bi, t)
		elseif kind == C_DROP then
			local speed = math.sqrt(a.vx * a.vx + a.vz * a.vz)
			a.mode = 3
			a.vx, a.vz, a.qx, a.qz, a.s = 0, 0, 0, 0, 0
			event(w, t, 6, a.id, bj, speed)
			key(w, bi, t)
		elseif kind == C_EXIT then
			local hole = holes[bj]
			local ex, ez = a.x - hole.x, a.z - hole.z
			local d = math.sqrt(ex * ex + ez * ez)
			if d > 0 then
				local rx, rz = ex / d, ez / d
				local vr = a.vx * rx + a.vz * rz
				local vt = a.vz * rx - a.vx * rz
				if vr > 0 then
					local liner = not hole.cup and rx * hole.mx + rz * hole.mz < Physics.LINER_DOT
					local need = 2 * G * -a.y * Physics.RIM_K
					if liner then
						vr = -Physics.E_LINER * vr
						vt *= 0.6
						event(w, t, 8, a.id, bj, -vr)
					elseif vr * vr > need then
						-- out again: over the rim with what is left
						vr = math.sqrt(vr * vr - need)
						a.mode = 1
						a.y = 0
						a.hole = 0
						event(w, t, 7, a.id, bj, vr)
					else
						vr = -0.3 * vr
					end
					a.vx = vr * rx - vt * rz
					a.vz = vr * rz + vt * rx
					if a.mode == 2 and d > hole.r then
						a.x = hole.x + rx * hole.r
						a.z = hole.z + rz * hole.r
					end
					key(w, bi, t)
				end
			end
		end
		w.contacts += 1
	end
	w.steps += 1
	w.t = w.steps * Physics.DT
	return anyMoving and Physics.moving(w)
end

return Physics
