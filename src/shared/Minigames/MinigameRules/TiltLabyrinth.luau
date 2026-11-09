--!strict
-- ReplicatedStorage.Shared.Minigames.MinigameRules.TiltLabyrinth
-- The wooden tilt marble labyrinth on the waiting-room table at Dr. Maple's Family Practice (brief v2 §13a:
-- "a playable tilt marble labyrinth"; BATCH2_SPEC §4 #18, §6 "Tilt labyrinth"). The owner's controls are
-- deliberate and fixed (do not change): W / S tilt the board forward and back; the Up and Down arrows tilt it
-- right and left, and the UP ARROW IS RIGHT (CONTROLS, codeFromKeys).
-- One player, no stakes, no money. The marble is simulated on the client at a fixed 60 Hz with step() so it
-- feels instant; the run is sent as its input log (one tilt code per tick, run-length encoded) in "tilt"
-- segments and the server REPLAYS the same deterministic simulation to score it (time to the goal, marbles
-- dropped). Falling into a hole puts the marble back on the last numbered checkpoint it passed (no game over:
-- it is a waiting-room toy for kids); the clock keeps running. Same log -> same result, every time.
-- Board units: 1 unit = 0.1 stud (STUDS); x right, y forward (away from the player), origin the board centre.
-- Pure; Lune-tested (tests/unit/minigames_labyrinth.spec.luau).
-- Interface: the Minigame.Rules shape (def, init, input, result, verbs "tilt", turn, skipTurn, view) plus BOARD,
--   CONTROLS, TICK, newSim() -> Sim, step(sim, code) (one tick), code(fx, fy), axes(code), codeFromKeys(keys),
--   encode(codes) -> string, decode(s) -> codes?, replay(codes) -> Sim, autopilot(sim) -> code (tests/demo),
--   SEGMENT_MAX, MAX_TICKS

local TiltLabyrinth = {}

TiltLabyrinth.def = {
	game = "tilt_labyrinth",
	title = "Tilt Labyrinth",
	class = "no_stakes",
	seats = 1,
	authority = "client_sim_server_replay",
	money = "none",
}
TiltLabyrinth.verbs = { tilt = true }

-- The owner's controls (brief v2 §13a, verbatim intent; fixedControls). Keys are Enum.KeyCode names.
TiltLabyrinth.CONTROLS = table.freeze({
	W = { axis = "forward", sign = 1 },
	S = { axis = "forward", sign = -1 },
	Up = { axis = "right", sign = 1 }, -- the Up arrow tilts RIGHT
	Down = { axis = "right", sign = -1 }, -- the Down arrow tilts LEFT
})
TiltLabyrinth.CONTROLS_TEXT = {
	"W  tilt forward",
	"S  tilt back",
	"Up arrow  tilt right",
	"Down arrow  tilt left",
}

TiltLabyrinth.TICK = 1 / 60
TiltLabyrinth.MAX_TICKS = 60 * 60 * 4 -- four minutes, then the run is called off
TiltLabyrinth.SEGMENT_MAX = 190 -- characters per "tilt" segment (Net scalar strings are <= 200)
TiltLabyrinth.MAX_LOG = 24000 -- characters in a whole run
TiltLabyrinth.STUDS = 0.1 -- studs per board unit

-- Physics (board units, seconds).
TiltLabyrinth.ACCEL = 55 -- at full tilt (g x sin(max tilt) x 5/7 for a rolling marble, scaled to feel right)
TiltLabyrinth.TILT_RATE = 5 -- full tilt in 0.2 s (the board eases, the keys are digital)
TiltLabyrinth.DRAG = 1.1 -- rolling resistance per second
TiltLabyrinth.MAX_SPEED = 24
TiltLabyrinth.BOUNCE = 0.3
TiltLabyrinth.MAX_TILT_DEG = 6 -- what the board shows at full tilt

-- The board: a 32 x 24 tray, three rows joined by gaps (bottom row to the right, middle row to the left, top row
-- to the goal), short stubs that make the middle row zig-zag, holes to weave between, numbered checkpoints.
TiltLabyrinth.BOARD = table.freeze({
	w = 32,
	h = 24,
	marble = 0.55, -- radius
	start = { -13, -8 },
	goal = { x = 13.2, y = 8.2, r = 1.3 },
	walls = {
		-- the frame (inside faces at +-15.6 and +-11.6)
		{ -16, 16, -12, -11.6 },
		{ -16, 16, 11.6, 12 },
		{ -16, -15.6, -12, 12 },
		{ 15.6, 16, -12, 12 },
		-- the two long walls
		{ -15.6, 8, -4.4, -3.6 },
		{ -8, 15.6, 3.6, 4.4 },
		-- the stubs in the middle row
		{ 3.1, 3.9, 0.8, 3.6 },
		{ -1.9, -1.1, -3.6, -0.8 },
	},
	holes = {
		{ -7, -9.6, 1.05 },
		{ -2, -6.4, 1.05 },
		{ 3, -9.6, 1.05 },
		{ 6, -1.8, 1.05 },
		{ 1, 1.9, 1.05 },
		{ -4, -1.8, 1.05 },
		{ -6, 9.8, 1.05 },
		{ -1, 6.2, 1.05 },
		{ 4, 9.8, 1.05 },
		{ 8.5, 6.2, 1.05 },
	},
	checkpoints = { { -13, -8 }, { 12.5, -1 }, { -12.5, 7.5 } },
	-- the painted guide line (numbered dots on the real board; also the autopilot's way round)
	guide = {
		{ -13, -8 },
		{ -7, -6.6 },
		{ -2, -9.7 },
		{ 3, -6.4 },
		{ 12, -8 },
		{ 12.5, -1 },
		{ 6, 1.5 },
		{ 1, -1.6 },
		{ -4, 1.5 },
		{ -12.5, 0 },
		{ -12.5, 7.5 },
		{ -6, 6.3 },
		{ -1, 9.7 },
		{ 4, 6.3 },
		{ 8.5, 9.7 },
		{ 13.2, 8.2 },
	},
})

export type Sim = {
	x: number,
	y: number,
	vx: number,
	vy: number,
	tx: number, -- board tilt (-1..1) toward +x
	ty: number, -- toward +y (forward)
	tick: number,
	drops: number,
	checkpoint: number,
	finished: boolean,
	finishTick: number?,
	fell: boolean, -- this tick
	guide: number, -- autopilot's next guide point
}

export type State = {
	sim: Sim?,
	log: { string },
	logLen: number,
	done: boolean,
	finished: boolean,
	gaveUp: boolean,
	ticks: number,
	drops: number,
	why: string?,
}

-- Codes: 0..8 = (fx + 1) * 3 + (fy + 1), fx/fy in {-1, 0, 1}; 4 is level.
function TiltLabyrinth.code(fx: number, fy: number): number
	return (math.clamp(fx, -1, 1) + 1) * 3 + (math.clamp(fy, -1, 1) + 1)
end

function TiltLabyrinth.axes(code: number): (number, number)
	return code // 3 - 1, code % 3 - 1
end

-- keys: { [KeyCode name] = true } held down. Opposite keys cancel.
function TiltLabyrinth.codeFromKeys(keys: { [string]: boolean }): number
	local fx, fy = 0, 0
	for name, held in keys do
		local c = TiltLabyrinth.CONTROLS[name]
		if held and c then
			if c.axis == "right" then
				fx += c.sign
			else
				fy += c.sign
			end
		end
	end
	return TiltLabyrinth.code(fx, fy)
end

function TiltLabyrinth.newSim(): Sim
	local b = TiltLabyrinth.BOARD
	return {
		x = b.start[1],
		y = b.start[2],
		vx = 0,
		vy = 0,
		tx = 0,
		ty = 0,
		tick = 0,
		drops = 0,
		checkpoint = 1,
		finished = false,
		finishTick = nil,
		fell = false,
		guide = 2,
	}
end

local function approach(v: number, target: number, d: number): number
	if v < target then
		return math.min(target, v + d)
	end
	return math.max(target, v - d)
end

-- one fixed tick of the marble under input `code`
function TiltLabyrinth.step(sim: Sim, code: number)
	sim.fell = false
	if sim.finished then
		return
	end
	local T = TiltLabyrinth
	local dt = T.TICK
	local b = T.BOARD
	local fx, fy = T.axes(code)
	sim.tx = approach(sim.tx, fx, T.TILT_RATE * dt)
	sim.ty = approach(sim.ty, fy, T.TILT_RATE * dt)
	sim.vx += sim.tx * T.ACCEL * dt
	sim.vy += sim.ty * T.ACCEL * dt
	local drag = math.max(0, 1 - T.DRAG * dt)
	sim.vx *= drag
	sim.vy *= drag
	local sp = math.sqrt(sim.vx * sim.vx + sim.vy * sim.vy)
	if sp > T.MAX_SPEED then
		sim.vx *= T.MAX_SPEED / sp
		sim.vy *= T.MAX_SPEED / sp
	end
	sim.x += sim.vx * dt
	sim.y += sim.vy * dt
	-- walls: push the marble out of every rectangle it overlaps and bounce the normal speed
	local r = b.marble
	for _ = 1, 2 do
		for _, w in b.walls do
			local cx = math.clamp(sim.x, w[1], w[2])
			local cy = math.clamp(sim.y, w[3], w[4])
			local dx, dy = sim.x - cx, sim.y - cy
			local d2 = dx * dx + dy * dy
			if d2 < r * r then
				local nx, ny
				local d = math.sqrt(d2)
				if d > 1e-9 then
					nx, ny = dx / d, dy / d
				else
					-- centre inside the wall: out along the shallowest side
					local l, rr = sim.x - w[1], w[2] - sim.x
					local bo, tp = sim.y - w[3], w[4] - sim.y
					local m = math.min(l, rr, bo, tp)
					if m == l then
						nx, ny = -1, 0
					elseif m == rr then
						nx, ny = 1, 0
					elseif m == bo then
						nx, ny = 0, -1
					else
						nx, ny = 0, 1
					end
					d = 0
				end
				sim.x = cx + nx * r
				sim.y = cy + ny * r
				local vn = sim.vx * nx + sim.vy * ny
				if vn < 0 then
					sim.vx -= (1 + T.BOUNCE) * vn * nx
					sim.vy -= (1 + T.BOUNCE) * vn * ny
				end
			end
		end
	end
	sim.tick += 1
	-- checkpoints passed
	for i, c in b.checkpoints do
		if i > sim.checkpoint then
			local dx, dy = sim.x - c[1], sim.y - c[2]
			if dx * dx + dy * dy < 2.5 * 2.5 then
				sim.checkpoint = i
			end
		end
	end
	-- the goal
	local g = b.goal
	if (sim.x - g.x) ^ 2 + (sim.y - g.y) ^ 2 < g.r * g.r then
		sim.finished = true
		sim.finishTick = sim.tick
		sim.vx, sim.vy = 0, 0
		return
	end
	-- holes: the marble drops once its centre is well over the hole
	for _, h in b.holes do
		local dx, dy = sim.x - h[1], sim.y - h[2]
		if dx * dx + dy * dy < (h[3] * 0.8) ^ 2 then
			sim.fell = true
			sim.drops += 1
			local c = b.checkpoints[sim.checkpoint]
			sim.x, sim.y = c[1], c[2]
			sim.vx, sim.vy = 0, 0
			sim.tx, sim.ty = 0, 0
			-- the autopilot restarts from the checkpoint's guide point
			for gi, p in b.guide do
				if p[1] == c[1] and p[2] == c[2] then
					sim.guide = gi + 1
				end
			end
			return
		end
	end
end

-- Run-length encoding of the tick codes: "<letter a..i><count>," per run.
function TiltLabyrinth.encode(codes: { number }): string
	local out = {}
	local i = 1
	while i <= #codes do
		local c = codes[i]
		local n = 1
		while codes[i + n] == c do
			n += 1
		end
		table.insert(out, string.char(97 + c) .. tostring(n) .. ",")
		i += n
	end
	return table.concat(out)
end

function TiltLabyrinth.decode(s: string): { number }?
	if #s > TiltLabyrinth.MAX_LOG then
		return nil
	end
	local codes = {}
	local pos = 1
	while pos <= #s do
		local letter, count, nextPos = string.match(s, "^([a-i])(%d+),()", pos)
		if letter == nil then
			return nil
		end
		local n = tonumber(count) :: number
		if n < 1 or #codes + n > TiltLabyrinth.MAX_TICKS then
			return nil
		end
		local c = string.byte(letter :: string) - 97
		for _ = 1, n do
			table.insert(codes, c)
		end
		pos = nextPos :: number
	end
	return codes
end

-- Replay a whole input log from the start (stops at the goal).
function TiltLabyrinth.replay(codes: { number }): Sim
	local sim = TiltLabyrinth.newSim()
	for _, c in codes do
		if sim.finished then
			break
		end
		TiltLabyrinth.step(sim, c)
	end
	return sim
end

-- A steady hand following the painted guide line (tests; the demo marble when nobody plays).
function TiltLabyrinth.autopilot(sim: Sim): number
	local g = TiltLabyrinth.BOARD.guide
	local idx = math.min(sim.guide, #g)
	local p = g[idx]
	local dx, dy = p[1] - sim.x, p[2] - sim.y
	if dx * dx + dy * dy < 1.0 and idx < #g then
		sim.guide = idx + 1
		p = g[sim.guide]
		dx, dy = p[1] - sim.x, p[2] - sim.y
	end
	-- desired speed toward the point, capped; tilt toward the velocity error
	local dist = math.sqrt(dx * dx + dy * dy)
	local want = math.min(5, dist * 1.6)
	local wx, wy = 0, 0
	if dist > 1e-6 then
		wx, wy = dx / dist * want, dy / dist * want
	end
	local ex, ey = wx - sim.vx, wy - sim.vy
	local fx = if ex > 0.6 then 1 elseif ex < -0.6 then -1 else 0
	local fy = if ey > 0.6 then 1 elseif ey < -0.6 then -1 else 0
	return TiltLabyrinth.code(fx, fy)
end

-- Minigame.Rules ---------------------------------------------------------------------------------------------------
function TiltLabyrinth.init(_seats: number, _seed: number): State
	return {
		sim = nil,
		log = {},
		logLen = 0,
		done = false,
		finished = false,
		gaveUp = false,
		ticks = 0,
		drops = 0,
		why = nil,
	}
end

-- "tilt" { "seg", data }: a piece of the run's log; { "end" }: the run is over, replay and score it;
-- { "giveup" }: stop without a time.
function TiltLabyrinth.input(state: State, seat: number, verb: string, args: { any }?): (boolean, string?)
	if seat ~= 1 then
		return false, "one player at a time"
	end
	if state.done then
		return false, "this run is over: play again"
	end
	if verb ~= "tilt" then
		return false, "verb"
	end
	local a = args or {}
	local what = a[1]
	if what == "seg" then
		local data = a[2]
		if type(data) ~= "string" or #data == 0 or #data > 200 then
			return false, "bad segment"
		end
		if state.logLen + #data > TiltLabyrinth.MAX_LOG then
			return false, "run too long"
		end
		table.insert(state.log, data)
		state.logLen += #data
		return true
	elseif what == "end" then
		local codes = TiltLabyrinth.decode(table.concat(state.log))
		if codes == nil then
			return false, "the run could not be read"
		end
		local sim = TiltLabyrinth.replay(codes)
		state.sim = sim
		state.ticks = sim.finishTick or sim.tick
		state.drops = sim.drops
		if not sim.finished then
			state.log = {}
			state.logLen = 0
			return false, "the marble has not reached the goal yet"
		end
		state.finished = true
		state.done = true
		return true
	elseif what == "giveup" then
		state.gaveUp = true
		state.done = true
		return true
	end
	return false, "tilt what?"
end

function TiltLabyrinth.turn(state: State): number?
	return if state.done then nil else 1
end

function TiltLabyrinth.skipTurn(state: State)
	state.gaveUp = true
	state.done = true
end

function TiltLabyrinth.result(state: State): { [string]: any }?
	if not state.done then
		return nil
	end
	local tenths = if state.finished then math.floor(state.ticks * TiltLabyrinth.TICK * 10 + 0.5) else 0
	return {
		done = true,
		scores = { tenths },
		winner = if state.finished then 1 else nil,
		finished = state.finished,
		seconds = tenths / 10,
		drops = state.drops,
		ticks = state.ticks,
	}
end

function TiltLabyrinth.view(state: State): { [string]: any }
	return {
		finished = state.finished,
		gaveUp = state.gaveUp,
		seconds = if state.finished then math.floor(state.ticks * TiltLabyrinth.TICK * 10 + 0.5) / 10 else nil,
		drops = state.drops,
	}
end

-- "m:ss.t" for the end card and the best-times card
function TiltLabyrinth.clock(seconds: number): string
	local m = math.floor(seconds / 60)
	local s = seconds - m * 60
	return string.format("%d:%04.1f", m, s)
end

return TiltLabyrinth
