--!strict
-- ReplicatedStorage.Shared.Minigames.AirHockey.Sim
-- The owner's air hockey simulation, AER / 01 (docs/reference/air_hockey/: HockeyPhysics.h is the whole game,
-- physics.js is the same in JavaScript), ported line for line. Engine-independent, deterministic, two
-- dimensions, SI units (metres, seconds), 240 fixed steps a second: swept-circle contacts against the two moving
-- mallets and the four rounded goal posts, analytic rails, restitution, a speed limit, light air drag, a goal
-- when the whole puck has crossed deep inside the slot, a serve after each goal toward the side that scored from
-- the side that conceded, first to seven, mallets kept to their own halves, and the computer opponent with its
-- difficulty number.
-- NOTHING HERE IS TUNED OR IMPROVED: the numbers, the order the contacts are looked at and the order of every
-- sum are his. The port is proven against his physics.js tick for tick (tools/games/air_hockey/golden.js writes
-- tests/golden/air_hockey.json; tests/unit/air_hockey_golden.spec.luau replays it to 1e-9, and in practice to
-- the last bit), and his C++ checks are tests/unit/air_hockey_sim.spec.luau. Where the two sources differ in the
-- last bit the JavaScript is followed, because it is the one that can be run here: the literal sums (.588 for
-- HalfWidth - PuckRadius and so on), a mallet's velocity as delta * (1 / dt), a unit normal as q * (1 / l), and
-- lengths by V8's Math.hypot (scaled by the larger component), not sqrt(dot).
-- Sides: 0 is Glacier (y < 0), 1 is Ember (y > 0). x runs across the table, y along it.
-- Two things are added that the simulation never reads (they are for sound and drawing): hitWhat / hitSpeed say
-- what the last contact was and how hard; and the drag of one whole step is a constant (DECAY) instead of a call
-- to exp on every machine, so that a client and the server never differ by a rounding of exp.
-- ONE RULE IS NOT HIS, and it is kept outside his step: play() is tick() followed by contain(), THE RAILS HOLD.
-- His simulation lets a puck out: a mallet that presses a puck into a rail squeezes it through (a rail is only
-- looked for while the puck is still inside it), and it never comes back, so the match never ends. It happens in
-- his JavaScript with the same inputs (tests/golden/air_hockey.json, the case "flaw: ..."; the port reproduces
-- it bit for bit), and with a plain mouse hand it happens several times a match (the pointer put on a puck that
-- is running along a rail or into a corner). Nothing in tick() is changed. After his step, a puck whose centre
-- is past a rail's face is put back on the face with its speed turned inward, and slid along the rail clear of
-- the mallet that pressed it: the rally goes on. A step that ends with the puck on the table is his step and
-- nothing else, so a match in which no puck is pressed out is his match to the last bit
-- (tests/unit/air_hockey_sim.spec.luau; whole matches: tests/unit/air_hockey_opponents.spec.luau). The old
-- answer, the puck put back for a serve, is kept only as a net under that (nothing known reaches it).
-- A match is stepped with play(); tick() is his, alone.
-- The state is one flat record of numbers (no vectors, nothing allocated in tick): it is stepped several hundred
-- times a frame when a client replays.
-- Pure. Interface: constants; new() -> State; reset(s); resetPuck(s); serve(s); press(s, computer) (a player's
--   serve button: at once against the computer, SERVE_LEAD later between two people); setTarget(s, side, x, y);
--   ai(s, side); tick(s, dt?, human?, computer?); play(s, human, computer) -> bool (one step of a match: his
--   tick, then the rails hold; true only if the puck had to be put back for a serve); contain(s) -> bool (the
--   rails hold: true if it moved the puck); offTable(s) -> bool; copy(dst, src) -> dst; clone(s) -> State;
--   hypot(x, y); fold(x, bound); FIELDS (every field, in a fixed order)

local Sim = {}

Sim.STEP = 1 / 240
Sim.HALF_WIDTH = 0.62
Sim.HALF_LENGTH = 1.17
Sim.GOAL = 0.22 -- half the goal's width
Sim.PUCK_RADIUS = 0.032
Sim.PADDLE_RADIUS = 0.064
Sim.POST_RADIUS = 0.012
Sim.GOAL_DEPTH = 1.245 -- a goal counts when the puck's far edge is this deep (its centre at 1.277)
Sim.WIN = 7
Sim.COUNTDOWN = 1.25
Sim.SERVE_LEAD = 96 / 240 -- (not his) between two people: a serve button lets the puck go this much later
Sim.DRAG = 0.08
Sim.RESTITUTION = 0.95
Sim.PADDLE_RESTITUTION = 0.94
Sim.MAX_SPEED = 7.5
Sim.HUMAN_SPEED = 3.5 -- a person's mallet follows its target at this many metres a second
Sim.COMPUTER_SPEED = 2.1 -- times the difficulty
Sim.DIFFICULTY = { easy = 0.62, medium = 1, hard = 1.38 }
-- exp(-DRAG * STEP): what one step of drag multiplies the puck's velocity by (the spec checks it is exp's value)
Sim.DECAY = 0.99966672221604991

-- what the last contact was (hitWhat)
Sim.HIT_RAIL = 0
Sim.HIT_POST = 1
Sim.HIT_MALLET = 2 -- + the side: 2 Glacier's mallet, 3 Ember's

-- his literals (physics.js), kept as literals: X_RAIL = HalfWidth - PuckRadius and so on
local X_RAIL = 0.588
local X_CHANNEL = 0.188 -- Goal - PuckRadius: the side walls of the goal slot
local Y_RAIL = 1.138
local Y_GOAL = 1.277
local HALF_LENGTH = 1.17
local GOAL = 0.22
local POST_REACH = 0.044 -- PuckRadius + PostRadius
local PADDLE_REACH = 0.096 -- PuckRadius + PaddleRadius
local TARGET_X = 0.556 -- HalfWidth - PaddleRadius
local TARGET_NEAR = 0.064
local TARGET_FAR = 1.106

export type State = {
	px: number, -- the puck
	py: number,
	vx: number,
	vy: number,
	p0x: number, -- Glacier's mallet: where it is, where it is going, its velocity this step
	p0y: number,
	t0x: number,
	t0y: number,
	v0x: number,
	v0y: number,
	p1x: number, -- Ember's
	p1y: number,
	t1x: number,
	t1y: number,
	v1x: number,
	v1y: number,
	score0: number,
	score1: number,
	countdown: number,
	drag: number,
	restitution: number,
	maxSpeed: number,
	difficulty: number,
	winner: number, -- -1, or the side
	serveSide: number, -- whose half the puck is served from (the side that conceded)
	lastGoal: number, -- -1, or the side that scored last
	hitSerial: number,
	goalSerial: number,
	paused: boolean,
	hitWhat: number, -- (not read by the simulation) the last contact: HIT_RAIL, HIT_POST, HIT_MALLET + side
	hitSpeed: number, -- (not read by the simulation) how fast the puck met it along the normal, m/s
}

Sim.FIELDS = {
	"px",
	"py",
	"vx",
	"vy",
	"p0x",
	"p0y",
	"t0x",
	"t0y",
	"v0x",
	"v0y",
	"p1x",
	"p1y",
	"t1x",
	"t1y",
	"v1x",
	"v1y",
	"score0",
	"score1",
	"countdown",
	"drag",
	"restitution",
	"maxSpeed",
	"difficulty",
	"winner",
	"serveSide",
	"lastGoal",
	"hitSerial",
	"goalSerial",
	"paused",
	"hitWhat",
	"hitSpeed",
}

local sqrt = math.sqrt
local abs = math.abs
local fmod = math.fmod

-- V8's Math.hypot for two numbers: the components are scaled by the larger before they are squared. (The same
-- value as sqrt(x * x + y * y) to within a rounding; the JavaScript game rounds this way.)
local function hypot(x: number, y: number): number
	local ax, ay = abs(x), abs(y)
	local m = if ax > ay then ax else ay
	if m == 0 then
		return 0
	end
	local nx, ny = ax / m, ay / m
	-- (Kahan summation of the two squares, as V8 does it)
	local sum = nx * nx
	local summand = ny * ny
	local preliminary = sum + summand
	return sqrt(preliminary) * m
end
Sim.hypot = hypot

-- A coordinate reflected back and forth between -bound and bound (where a rail shot will be). JavaScript's %
-- keeps the sign of the dividend, which is fmod.
local function fold(x: number, bound: number): number
	local span = 4 * bound
	local v = fmod(fmod(x + bound, span) + span, span)
	return if v <= 2 * bound then v - bound else 3 * bound - v
end
Sim.fold = fold

local function clamp(v: number, a: number, b: number): number
	-- Math.max(a, Math.min(b, v))
	local m = if v < b then v else b
	return if m > a then m else a
end

function Sim.resetPuck(s: State)
	s.px, s.py = 0, if s.serveSide ~= 0 then 0.3 else -0.3
	s.vx, s.vy = 0, 0
	s.countdown = 1.25
end

function Sim.reset(s: State)
	s.score0, s.score1 = 0, 0
	s.winner = -1
	s.paused = false
	s.serveSide = 0
	s.lastGoal = -1
	s.p0x, s.p0y, s.t0x, s.t0y, s.v0x, s.v0y = 0, -0.8, 0, -0.8, 0, 0
	s.p1x, s.p1y, s.t1x, s.t1y, s.v1x, s.v1y = 0, 0.8, 0, 0.8, 0, 0
	Sim.resetPuck(s)
end

function Sim.new(): State
	local s: State = {
		px = 0,
		py = 0,
		vx = 0,
		vy = 0,
		p0x = 0,
		p0y = 0,
		t0x = 0,
		t0y = 0,
		v0x = 0,
		v0y = 0,
		p1x = 0,
		p1y = 0,
		t1x = 0,
		t1y = 0,
		v1x = 0,
		v1y = 0,
		score0 = 0,
		score1 = 0,
		countdown = 1.25,
		drag = 0.08,
		restitution = 0.95,
		maxSpeed = 7.5,
		difficulty = 1,
		winner = -1,
		serveSide = 0,
		lastGoal = -1,
		hitSerial = 0,
		goalSerial = 0,
		paused = false,
		hitWhat = -1,
		hitSpeed = 0,
	}
	Sim.reset(s)
	return s
end

function Sim.copy(dst: State, src: State): State
	local d, f = dst :: any, src :: any
	for _, k in Sim.FIELDS do
		d[k] = f[k]
	end
	return dst
end

function Sim.clone(s: State): State
	return table.clone(s)
end

-- The puck is let go: toward the side that scored, from the side that conceded.
function Sim.serve(s: State)
	if s.winner < 0 then
		s.countdown = 0
		s.vx = if s.goalSerial % 2 ~= 0 then -0.34 else 0.34
		s.vy = if s.serveSide ~= 0 then -1.25 else 1.25
	end
end

-- NOT HIS (the timing only): a player's serve button, pressed while the puck waits. Against the computer it is
-- his: the puck is let go at once. Between two people the puck is let go SERVE_LEAD later (the countdown is cut
-- to that, never lengthened): the other player's screen cannot know of the press sooner, and a puck that has
-- already left when the news arrives would have to jump. Both screens and the referee apply the press on the
-- same tick, so the puck leaves on the same tick everywhere.
function Sim.press(s: State, computer: boolean)
	if s.countdown <= 0 or s.winner >= 0 then
		return
	end
	if computer then
		Sim.serve(s)
	elseif s.countdown > Sim.SERVE_LEAD then
		s.countdown = Sim.SERVE_LEAD
	end
end

-- Where a mallet is asked to go: kept on the table and in its own half.
function Sim.setTarget(s: State, side: number, x: number, y: number)
	local tx = clamp(x, -TARGET_X, TARGET_X)
	if side ~= 0 then
		s.t1x, s.t1y = tx, clamp(y, TARGET_NEAR, TARGET_FAR)
	else
		s.t0x, s.t0y = tx, clamp(y, -TARGET_FAR, -TARGET_NEAR)
	end
end

-- The computer opponent: shadow the puck, meet a shot where it will arrive, get behind a puck in its half and
-- commit through it toward the other goal.
function Sim.ai(s: State, side: number)
	local sg = if side ~= 0 then 1 else -1
	local mx, my
	if side ~= 0 then
		mx, my = s.p1x, s.p1y
	else
		mx, my = s.p0x, s.p0y
	end
	local px, py, vx, vy = s.px, s.py, s.vx, s.vy
	local tx, ty = px * 0.65, sg * 0.85
	if vy * sg > 0.05 then
		local t = clamp((sg * 0.88 - py) / vy, 0, 1.4)
		tx, ty = fold(px + vx * t, 0.588), sg * 0.88
	end
	if py * sg > 0.08 and py * sg < 1.07 then
		-- Get behind the puck, then commit through it toward the opposing goal.
		tx, ty = px, py + sg * 0.115
		if abs(mx - px) < 0.065 and (my - py) * sg > 0.025 then
			tx, ty = px * 0.78, py - sg * 0.26
		end
	end
	if s.countdown > 0 then
		tx, ty = 0, sg * 0.8
	end
	Sim.setTarget(s, side, tx, ty)
end

-- When a point at q moving by `relative` a second first comes within r of the origin, within `horizon` seconds
-- (nil: it does not). Already inside counts at once if it is still closing.
local function circleTOI(qx: number, qy: number, rx: number, ry: number, r: number, horizon: number): number?
	local a = rx * rx + ry * ry
	local b = qx * rx + qy * ry
	local c = (qx * qx + qy * qy) - r * r
	if c <= 1e-10 then
		return if b < -1e-9 then 0 else nil
	end
	if a < 1e-12 or b >= 0 then
		return nil
	end
	local d = b * b - a * c
	if d < 0 then
		return nil
	end
	local t = (-b - sqrt(d)) / a
	return if t >= -1e-9 and t <= horizon then t else nil
end

-- One step. human: the side a person plays (its mallet follows its target at HUMAN_SPEED); computer: the other
-- side is the computer's (it picks its own target here and moves at COMPUTER_SPEED * difficulty). With
-- computer = false both mallets are people's.
function Sim.tick(s: State, dtIn: number?, humanIn: number?, computerIn: boolean?)
	local dt: number = dtIn or Sim.STEP
	local human: number = humanIn or 0
	local computer = computerIn ~= false
	if s.paused or s.winner >= 0 then
		return
	end
	if computer then
		Sim.ai(s, 1 - human)
	end
	local s0x, s0y, s1x, s1y = s.p0x, s.p0y, s.p1x, s.p1y
	local inv = 1 / dt
	-- each mallet's velocity for this step: toward its target, no faster than its speed
	do
		local limit = (if human == 0 or not computer then 3.5 else 2.1 * s.difficulty) * dt
		local dx, dy = s.t0x - s0x, s.t0y - s0y
		local n = hypot(dx, dy)
		if n > limit then
			local k = limit / n
			dx, dy = dx * k, dy * k
		end
		s.v0x, s.v0y = dx * inv, dy * inv
	end
	do
		local limit = (if human == 1 or not computer then 3.5 else 2.1 * s.difficulty) * dt
		local dx, dy = s.t1x - s1x, s.t1y - s1y
		local n = hypot(dx, dy)
		if n > limit then
			local k = limit / n
			dx, dy = dx * k, dy * k
		end
		s.v1x, s.v1y = dx * inv, dy * inv
	end
	local v0x, v0y, v1x, v1y = s.v0x, s.v0y, s.v1x, s.v1y
	if s.countdown > 0 then
		s.p0x, s.p0y = s0x + v0x * dt, s0y + v0y * dt
		s.p1x, s.p1y = s1x + v1x * dt, s1y + v1y * dt
		s.countdown -= dt
		if s.countdown <= 0 then
			Sim.serve(s)
		end
		return
	end
	local decay = if dt == Sim.STEP and s.drag == 0.08 then Sim.DECAY else math.exp(-s.drag * dt)
	local px, py = s.px, s.py
	local vx, vy = s.vx * decay, s.vy * decay
	local left, elapsed = dt, 0
	local iteration = 0
	while iteration < 16 and left > 1e-9 do
		iteration += 1
		-- the earliest contact in what is left of the step: hit time, normal, the surface's velocity, its kind
		-- (0 a rail or a post, 1 a mallet, 3 / 4 a goal for Glacier / Ember) and what it was (for sound)
		local ht, hnx, hny, hsx, hsy, hk, hw = left + 1, 0, 0, 0, 0, -1, -1
		for sg = -1, 1, 2 do
			if vx * sg > 1e-9 then
				-- a side rail
				local t = (sg * X_RAIL - px) / vx
				if t >= -1e-9 and t <= left and t < ht then
					ht, hnx, hny, hsx, hsy, hk, hw = if t > 0 then t else 0, -sg, 0, 0, 0, 0, 0
				end
				-- a side wall of the goal slot, once the puck is past the end rail
				t = (sg * X_CHANNEL - px) / vx
				if abs(py + vy * t) >= HALF_LENGTH then
					if t >= -1e-9 and t <= left and t < ht then
						ht, hnx, hny, hsx, hsy, hk, hw = if t > 0 then t else 0, -sg, 0, 0, 0, 0, 0
					end
				end
			end
			if vy * sg > 1e-9 then
				-- an end rail, beside the goal
				local t = (sg * Y_RAIL - py) / vy
				local x = px + vx * t
				if abs(x) >= GOAL then
					if t >= -1e-9 and t <= left and t < ht then
						ht, hnx, hny, hsx, hsy, hk, hw = if t > 0 then t else 0, 0, -sg, 0, 0, 0, 0
					end
				end
				-- A full-puck crossing deep inside the goal awards exactly one point.
				t = (sg * Y_GOAL - py) / vy
				if t >= -1e-9 and t <= left and t < ht then
					ht, hnx, hny, hsx, hsy, hk, hw = if t > 0 then t else 0, 0, 0, 0, 0, if sg > 0 then 3 else 4, -1
				end
			end
		end
		-- the four rounded goal posts
		for sx = -1, 1, 2 do
			for sy = -1, 1, 2 do
				local cx, cy = sx * GOAL, sy * HALF_LENGTH
				local t = circleTOI(px - cx, py - cy, vx, vy, POST_REACH, left)
				if t ~= nil and t < ht then
					local qx, qy = (px + vx * t) - cx, (py + vy * t) - cy
					local l = hypot(qx, qy)
					if l > 1e-9 then
						local k = 1 / l
						hnx, hny = qx * k, qy * k
					else
						hnx, hny = 0, 1
					end
					ht, hsx, hsy, hk, hw = if t > 0 then t else 0, 0, 0, 0, 1
				end
			end
		end
		-- the two mallets, where they are `elapsed` into the step
		do
			local cx, cy = s0x + v0x * elapsed, s0y + v0y * elapsed
			local t = circleTOI(px - cx, py - cy, vx - v0x, vy - v0y, PADDLE_REACH, left)
			if t ~= nil and t < ht then
				local qx, qy = (px + vx * t) - (cx + v0x * t), (py + vy * t) - (cy + v0y * t)
				local l = hypot(qx, qy)
				if l > 1e-9 then
					local k = 1 / l
					hnx, hny = qx * k, qy * k
				else
					hnx, hny = 0, 1
				end
				ht, hsx, hsy, hk, hw = if t > 0 then t else 0, v0x, v0y, 1, 2
			end
			cx, cy = s1x + v1x * elapsed, s1y + v1y * elapsed
			t = circleTOI(px - cx, py - cy, vx - v1x, vy - v1y, PADDLE_REACH, left)
			if t ~= nil and t < ht then
				local qx, qy = (px + vx * t) - (cx + v1x * t), (py + vy * t) - (cy + v1y * t)
				local l = hypot(qx, qy)
				if l > 1e-9 then
					local k = 1 / l
					hnx, hny = qx * k, qy * k
				else
					hnx, hny = 0, 1
				end
				ht, hsx, hsy, hk, hw = if t > 0 then t else 0, v1x, v1y, 1, 3
			end
		end
		if hk < 0 then
			px, py = px + vx * left, py + vy * left
			left = 0
			break
		end
		px, py = px + vx * ht, py + vy * ht
		elapsed += ht
		left -= ht
		if hk == 3 or hk == 4 then
			local scorer = if hk == 3 then 0 else 1
			local score
			if scorer == 0 then
				s.score0 += 1
				score = s.score0
			else
				s.score1 += 1
				score = s.score1
			end
			s.lastGoal = scorer
			s.goalSerial += 1
			s.serveSide = 1 - scorer
			if score >= 7 then
				s.winner = scorer
				vx, vy = 0, 0
			else
				-- (ResetPuck)
				px, py = 0, if s.serveSide ~= 0 then 0.3 else -0.3
				vx, vy = 0, 0
				s.countdown = 1.25
			end
			break
		end
		local vn = (vx - hsx) * hnx + (vy - hsy) * hny
		if vn < 0 then
			local k = -(1 + (if hk == 1 then 0.94 else s.restitution)) * vn
			vx, vy = vx + hnx * k, vy + hny * k
			s.hitSerial += 1
			s.hitWhat, s.hitSpeed = hw, -vn
		end
		do
			local n = hypot(vx, vy)
			if n > s.maxSpeed then
				local k = s.maxSpeed / n
				vx, vy = vx * k, vy * k
			end
		end
		px, py = px + hnx * 1e-6, py + hny * 1e-6
		-- Progress even when two contacts share exactly the same instant.
		if ht < 1e-8 then
			local e = if left < 1e-7 then left else 1e-7
			px, py = px + vx * e, py + vy * e
			left -= e
			elapsed += e
		end
	end
	s.px, s.py, s.vx, s.vy = px, py, vx, vy
	s.p0x, s.p0y = s0x + v0x * dt, s0y + v0y * dt
	s.p1x, s.p1y = s1x + v1x * dt, s1y + v1y * dt
end

-- NOT HIS (see the header). Is the puck's centre somewhere no table has it: beyond a side rail's face, deep past
-- a goal line, or inside an end rail beside the goal?
function Sim.offTable(s: State): boolean
	local ax, ay = abs(s.px), abs(s.py)
	return ax > 0.62 or ay > 1.3 or (ay > HALF_LENGTH and ax > 0.235)
end

-- NOT HIS (see the header): THE RAILS HOLD. Called after his step. A puck whose centre is past a face his step
-- can no longer see (beyond a side rail, inside an end rail beside the goal, inside a wall of the goal slot or a
-- post) is put back on that face with its speed turned inward; if a mallet is still on top of it there (that is
-- how it got out: the mallet pressed it into the rail), it is slid along the rail to the mallet's edge and
-- leaves as it would off that mallet. Returns true when it moved the puck. On the table it reads five numbers
-- and changes nothing: a match in which no puck is ever pressed out is his step's match to the last bit.
-- (PAST: further than his own rail test forgives a puck that is on its way out, 7.5 m/s * 1e-9 s)
local PAST = 1e-8
local SLOT_BULGE = 0.0302 -- how far a post reaches into the goal mouth at the end rail's face (sqrt(.044^2 - .032^2))

-- Push the puck off one mallet along a rail it lies on (flags say which), or straight away from the mallet.
local function unpin(
	px: number,
	py: number,
	mx: number,
	my: number,
	onSide: boolean,
	onEnd: boolean
): (number, number, boolean)
	local dx, dy = px - mx, py - my
	if dx * dx + dy * dy >= (PADDLE_REACH - 1e-9) * (PADDLE_REACH - 1e-9) then
		return px, py, false
	end
	-- where along its rail the puck just touches the mallet, the nearest such place first (a dead heat: the
	-- one nearer the middle of the table)
	local bx, by, best = px, py, math.huge
	if onSide then
		local a = PADDLE_REACH * PADDLE_REACH - dx * dx
		local h = if a > 0 then sqrt(a) else 0
		for sg = -1, 1, 2 do
			local cy = my + sg * h
			local d = abs(cy - py) + abs(cy) * 1e-6
			if abs(cy) <= Y_RAIL and d < best then
				bx, by, best = px, cy, d
			end
		end
	end
	if onEnd then
		local a = PADDLE_REACH * PADDLE_REACH - dy * dy
		local h = if a > 0 then sqrt(a) else 0
		for sg = -1, 1, 2 do
			local cx = mx + sg * h
			local ax = abs(cx)
			local d = abs(cx - px) + ax * 1e-6
			if ax <= X_RAIL and (ax >= GOAL or ax <= GOAL - SLOT_BULGE - 1e-6) and d < best then
				bx, by, best = cx, py, d
			end
		end
	end
	if best == math.huge then
		-- (not on a rail, or no room along it: straight away from the mallet)
		local l = hypot(dx, dy)
		if l > 1e-9 then
			bx, by = mx + dx / l * PADDLE_REACH, my + dy / l * PADDLE_REACH
		else
			bx, by = mx, my - (if my > 0 then PADDLE_REACH else -PADDLE_REACH)
		end
	end
	return bx, by, true
end

function Sim.contain(s: State): boolean
	local px, py = s.px, s.py
	local ax, ay = abs(px), abs(py)
	if ax <= X_RAIL + PAST and ay <= Y_RAIL + PAST then
		return false -- (on the bed: nearly every step ends here)
	end
	local vx, vy = s.vx, s.vy
	local e = s.restitution
	local onSide, onEnd, moved = false, false, false
	if ax > X_RAIL + PAST then
		local sg = if px > 0 then 1 else -1
		px, ax = sg * X_RAIL, X_RAIL
		if vx * sg > 0 then
			vx = -vx * e
		end
		onSide, moved = true, true
	end
	if ay > Y_RAIL + PAST then
		local sg = if py > 0 then 1 else -1
		if ax >= GOAL then
			-- inside the end rail beside the goal
			py, ay = sg * Y_RAIL, Y_RAIL
			if vy * sg > 0 then
				vy = -vy * e
			end
			onEnd, moved = true, true
		else
			if ay >= HALF_LENGTH and ax > X_CHANNEL + PAST then
				-- inside a wall of the goal slot
				local sx = if px > 0 then 1 else -1
				px, ax = sx * X_CHANNEL, X_CHANNEL
				if vx * sx > 0 then
					vx = -vx * e
				end
				moved = true
			end
			-- inside a post
			local cx, cy = if px > 0 then GOAL else -GOAL, sg * HALF_LENGTH
			local qx, qy = px - cx, py - cy
			local l = hypot(qx, qy)
			if l < POST_REACH - PAST then
				local nx, ny = 0, -sg
				if l > 1e-9 then
					nx, ny = qx / l, qy / l
				end
				px, py = cx + nx * POST_REACH, cy + ny * POST_REACH
				local vn = vx * nx + vy * ny
				if vn < 0 then
					vx, vy = vx - (1 + e) * vn * nx, vy - (1 + e) * vn * ny
				end
				moved = true
			end
		end
	end
	if not moved then
		return false -- (in the goal mouth or the slot, where it may be)
	end
	-- a mallet still on top of it: off along the rail, leaving as it would off that mallet
	local what = Sim.HIT_RAIL
	for side = 0, 1 do
		local mx, my, mvx, mvy = s.p0x, s.p0y, s.v0x, s.v0y
		if side ~= 0 then
			mx, my, mvx, mvy = s.p1x, s.p1y, s.v1x, s.v1y
		end
		local nxp, nyp, pinned = unpin(px, py, mx, my, onSide, onEnd)
		if pinned then
			px, py = nxp, nyp
			local qx, qy = px - mx, py - my
			local l = hypot(qx, qy)
			if l > 1e-9 then
				local nx, ny = qx / l, qy / l
				local vn = (vx - mvx) * nx + (vy - mvy) * ny
				if vn < 0 then
					local k = -(1 + 0.94) * vn
					vx, vy = vx + nx * k, vy + ny * k
				end
			end
			what = Sim.HIT_MALLET + side
		end
	end
	-- (and never back into the rail it was put on)
	if onSide and vx * px > 0 then
		vx = -vx * e
	end
	if onEnd and vy * py > 0 then
		vy = -vy * e
	end
	local n = hypot(vx, vy)
	if n > s.maxSpeed then
		local k = s.maxSpeed / n
		vx, vy = vx * k, vy * k
		n = s.maxSpeed
	end
	s.px, s.py, s.vx, s.vy = px, py, vx, vy
	s.hitSerial += 1
	s.hitWhat, s.hitSpeed = what, n
	return true
end

-- One step of a match: his tick, then the rails hold (contain). Should a puck ever be off the table all the same
-- (nothing known does it), it is put back on the serve spot of the half it left, to be served toward the other
-- (the side it left from pushed it out), after the countdown. Returns true only when that happened.
function Sim.play(s: State, human: number, computer: boolean): boolean
	Sim.tick(s, Sim.STEP, human, computer)
	if s.winner < 0 and s.countdown <= 0 then
		Sim.contain(s)
		if Sim.offTable(s) then
			s.serveSide = if s.py > 0 then 1 else 0
			Sim.resetPuck(s)
			return true
		end
	end
	return false
end

return Sim
