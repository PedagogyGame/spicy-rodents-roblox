--!strict
-- ReplicatedStorage.Shared.Minigames.Labyrinth.Pilot
-- Computer hands on the two knobs. A pilot plays through exactly what a person has: every tick it looks at the
-- board and answers with one input code (Controls.code: W/S and the Up/Down arrows held or not), and the same
-- Run.step moves the marble. It cannot set the tilt, nudge the marble or see anything a player cannot.
-- How it plays: it follows the line drawn on the board. It finds the marble's place on the line, aims at a
-- point a little further along, and wants a speed that the bends, the holes and the cup ahead allow (it brakes
-- early for them). From the speed it wants and the speed the marble has it works out the tilt it needs, then
-- taps or holds the keys that swing the board there, knowing the board has weight and carries on a little
-- after a key is let go. While a dropped marble rolls home it levels the board.
-- Skill levels differ the way people do: how fast they dare go, how late they brake, how long their eye and
-- hand take (they act on what they saw a moment ago and re-decide only so often), how exactly they judge where
-- the marble is, and how often a thumb slips. The labyrinth is played alone (the checklist's "one player at a
-- time, no computer opponent"): the pilots are the marble that plays itself on an empty table, a stand-in for
-- a player in tests and flow checks, and the way a designer learns how hard a board is before a person tries.
-- LEVELS[4], the steady hand, has no error at all: it is the scripted run that proves each board can be done.
-- Deterministic: a pilot's whole state is in its table (its dice are a number in it), so the same board, level
-- and seed play the same run on any machine.
-- Pure; Lune-tested (tests/unit/labyrinth_pilot.spec.luau).
-- Interface: LEVELS { Level }, STEADY (= 4); new(board, level, seed) -> Pilot; code(board, pilot, run) -> code
--   for the tick about to be played; play(board, level, seed, hold?, maxTicks?) -> (Run.State, codes) (a whole
--   run, with its input log)

local Boards = require("./Boards")
local Controls = require("./Controls")
local Physics = require("./Physics")
local Run = require("./Run")

local Pilot = {}

export type Level = {
	id: string,
	name: string,
	cruise: number, -- studs/s on a clear straight
	turn: number, -- through a bend
	hole: number, -- past a hole in its own cell
	cup: number, -- into the finish cup
	brake: number, -- studs/s^2 it plans to slow down at
	gain: number, -- 1/s: how hard it corrects its speed
	look: number, -- studs it aims ahead along the line
	react: number, -- ticks between seeing and doing
	think: number, -- ticks between decisions
	judge: number, -- studs of error in where it thinks the marble is
	slip: number, -- chance per decision that a thumb does something else
	band: number, -- degrees of tilt error it lets be
	lean: number, -- degrees it tips the board into the far wall to slide past a hole
	foresee: number, -- 0..1: how much of its own lateness it makes up for by reckoning where the marble is by now
}

-- Names from the waiting room. Tuned with tools/labyrinth/calibrate.luau.
Pilot.LEVELS = table.freeze({
	table.freeze({
		id = "pip",
		name = "Pip",
		cruise = 1.6,
		turn = 0.9,
		hole = 0.8,
		cup = 0.7,
		brake = 2.4,
		gain = 3,
		look = 0.2,
		react = 10,
		think = 5,
		judge = 0.03,
		slip = 0.02,
		band = 0.7,
		lean = 1.5,
		foresee = 0.5,
	}),
	table.freeze({
		id = "hazel",
		name = "Nurse Hazel",
		cruise = 1.5,
		turn = 0.7,
		hole = 0.55,
		cup = 0.7,
		brake = 1.8,
		gain = 3.5,
		look = 0.18,
		react = 6,
		think = 3,
		judge = 0.015,
		slip = 0.006,
		band = 0.5,
		lean = 2.0,
		foresee = 0.8,
	}),
	table.freeze({
		id = "maple",
		name = "Dr. Maple",
		cruise = 1.7,
		turn = 0.75,
		hole = 0.55,
		cup = 0.7,
		brake = 1.8,
		gain = 4,
		look = 0.16,
		react = 3,
		think = 2,
		judge = 0.006,
		slip = 0.001,
		band = 0.35,
		lean = 2.0,
		foresee = 1,
	}),
	table.freeze({
		id = "steady",
		name = "The steady hand",
		cruise = 1.4,
		turn = 0.6,
		hole = 0.45,
		cup = 0.6,
		brake = 1.4,
		gain = 6,
		look = 0.16,
		react = 0,
		think = 1,
		judge = 0,
		slip = 0,
		band = 0.3,
		lean = 1.5,
		foresee = 1,
	}),
}) :: { Level }
Pilot.STEADY = 4

local HISTORY = 16 -- ticks of what it saw (more than any level's react)

export type Pilot = {
	level: number,
	dice: number, -- the state of its random numbers
	seg: number, -- the stretch of the line the marble is on (between path[seg] and path[seg + 1])
	held: number, -- the code it is holding
	tapX: number, -- ticks it goes on pressing each axis of that code; after that the thumb comes off (a tap)
	tapY: number,
	wait: number, -- ticks until it decides again
	head: number, -- where the next sighting goes in the ring below
	seenX: { number },
	seenY: { number },
	seenVx: { number },
	seenVy: { number },
	limits: { number }, -- the speed it allows itself at each point of the line
	leanX: { number }, -- at each point of the line: the wall to lean on while passing a hole there (0: none)
	leanY: { number },
}

-- the dice: a 32-bit linear congruential generator in exact double arithmetic
local function roll(p: Pilot): number
	p.dice = (p.dice * 1664525 + 1013904223) % 4294967296
	return p.dice / 4294967296
end

-- The speed the pilot allows itself at each point of the line: slow for bends, for holes and for the cup, and
-- early enough before each of them that braking at its own rate gets there.
local function speedLimits(board: Boards.Board, level: Level): { number }
	local path, n = board.path, #board.path
	local limits: { number } = table.create(n, level.cruise)
	for i = 2, n - 1 do
		local ax, ay = path[i][1] - path[i - 1][1], path[i][2] - path[i - 1][2]
		local bx, by = path[i + 1][1] - path[i][1], path[i + 1][2] - path[i][2]
		local dot = ax * bx + ay * by
		local la, lb = math.sqrt(ax * ax + ay * ay), math.sqrt(bx * bx + by * by)
		if dot < 0.8 * la * lb then
			limits[i] = math.min(limits[i], level.turn)
		end
	end
	for i = 1, n do
		for _, hole in board.holes do
			local dx, dy = hole.x - path[i][1], hole.y - path[i][2]
			if dx * dx + dy * dy < 0.2 * 0.2 then
				limits[i] = math.min(limits[i], level.hole)
			end
		end
	end
	limits[n] = math.min(limits[n], level.cup)
	for i = n - 1, 1, -1 do
		local reach = math.sqrt(limits[i + 1] ^ 2 + 2 * level.brake * (board.pathS[i + 1] - board.pathS[i]))
		limits[i] = math.min(limits[i], reach)
	end
	return limits
end

-- Where the line steps aside from a hole there is usually a wall to lean on: tip the board into it and the
-- marble slides along the wood, clear of the rim, without having to be steered to a hair. A person leans
-- early, so the cell before leans the same way; before a bend with a hole in its outside corner that means
-- leaning on the inside wall, which is also what carries the marble round the bend when the wall ends.
local function leans(board: Boards.Board): ({ number }, { number })
	local cells, path = board.pathCells, board.path
	local n = #cells
	local wishX: { number }, wishY: { number } = table.create(n, 0), table.create(n, 0)
	for i, cell in cells do
		local cx, cy = Boards.cellCentre(board, cell)
		local dx, dy = path[i][1] - cx, path[i][2] - cy
		wishX[i] = if dx > 0.01 then 1 elseif dx < -0.01 then -1 else 0
		wishY[i] = if dy > 0.01 then 1 elseif dy < -0.01 then -1 else 0
	end
	local function walled(cell: number, x: number, y: number): (number, number)
		local open = board.open[cell]
		local lx = if x ~= 0 and bit32.band(open, if x > 0 then 1 else 4) == 0 then x else 0
		local ly = if y ~= 0 and bit32.band(open, if y > 0 then 2 else 8) == 0 then y else 0
		return lx, ly
	end
	local leanX: { number }, leanY: { number } = table.create(n, 0), table.create(n, 0)
	for i, cell in cells do
		if wishX[i] ~= 0 or wishY[i] ~= 0 then
			leanX[i], leanY[i] = walled(cell, wishX[i], wishY[i])
		elseif i > 1 and i < n then
			-- the next cell's wish, less the part that points back along the way there
			local along = math.abs(cells[i + 1] - cell) == 1 -- the next cell is to the left or right
			local wx = if along then 0 else wishX[i + 1]
			local wy = if along then wishY[i + 1] else 0
			leanX[i], leanY[i] = walled(cell, wx, wy)
		end
	end
	return leanX, leanY
end

function Pilot.new(board: Boards.Board, level: number, seed: number): Pilot
	local def = Pilot.LEVELS[level]
	assert(def ~= nil, "no such pilot level")
	local leanX, leanY = leans(board)
	return {
		leanX = leanX,
		leanY = leanY,
		level = level,
		dice = math.floor(seed) % 4294967296,
		seg = 1,
		held = Controls.NEUTRAL,
		tapX = 0,
		tapY = 0,
		wait = 0,
		head = 1,
		seenX = table.create(HISTORY, board.start.x),
		seenY = table.create(HISTORY, board.start.y),
		seenVx = table.create(HISTORY, 0),
		seenVy = table.create(HISTORY, 0),
		limits = speedLimits(board, def),
	}
end

-- how far a tap of n ticks tips a board at rest (index n); a pilot picks the shortest tap that is enough
local TAP: { number } = {}
for n = 1, 12 do
	TAP[n] = Physics.tiltAfter(n)
end

-- the key for one axis, and for how many ticks: swing the board toward the tilt wanted, allowing for the swing
-- it already has, and letting go as soon as a tap that long has done the job
local function key(tilt: number, swing: number, want: number, band: number, ticks: number): (number, number)
	local rest = tilt + swing * math.abs(swing) / (2 * Physics.TILT_BRAKE)
	local err = want - rest
	if math.abs(err) <= band then
		return 0, 0
	end
	local hold = ticks
	for n = 1, math.min(ticks, #TAP) do
		if TAP[n] >= math.abs(err) then
			hold = n
			break
		end
	end
	return if err > 0 then 1 else -1, hold
end

local DEG_PER_ACCEL = 1 / (Physics.GRAVITY * Physics.ROLL * Physics.slope(1))

function Pilot.code(board: Boards.Board, p: Pilot, s: Run.State): number
	local def = Pilot.LEVELS[p.level]
	local m = s.m
	-- remember what it sees; act on what it saw a moment ago
	p.seenX[p.head], p.seenY[p.head], p.seenVx[p.head], p.seenVy[p.head] = m.x, m.y, m.vx, m.vy
	local at = (p.head - 1 - def.react) % HISTORY + 1
	p.head = p.head % HISTORY + 1
	if p.wait > 0 then
		p.wait -= 1
		local right, forward = Controls.axes(p.held)
		p.tapX -= 1
		p.tapY -= 1
		return Controls.code(if p.tapX > 0 then right else 0, if p.tapY > 0 then forward else 0)
	end
	p.wait = def.think - 1
	if def.slip > 0 and roll(p) < def.slip then
		-- a thumb slips: some other keys, for a moment
		p.held = math.floor(roll(p) * 9)
		p.wait = def.think * 2
		p.tapX, p.tapY = p.wait + 1, p.wait + 1
		return p.held
	end
	if m.on == 0 then
		-- the marble is rolling home: level the board for it
		local kx, nx = key(m.tx, m.wx, 0, def.band, def.think)
		local ky, ny = key(m.ty, m.wy, 0, def.band, def.think)
		p.held, p.tapX, p.tapY = Controls.code(kx, ky), nx, ny
		return p.held
	end
	local x, y, vx, vy = p.seenX[at], p.seenY[at], p.seenVx[at], p.seenVy[at]
	if def.react > 0 and def.foresee > 0 then
		-- it knows it is late, and how its own hands have the board: reckon where the marble is by now
		local late = def.react * Physics.TICK * def.foresee
		x += vx * late
		y += vy * late
		vx += m.tx / DEG_PER_ACCEL * late
		vy += m.ty / DEG_PER_ACCEL * late
	end
	if def.judge > 0 then
		x += (roll(p) + roll(p) - 1) * def.judge
		y += (roll(p) + roll(p) - 1) * def.judge
	end

	-- where on the line is it?
	local path, pathS = board.path, board.pathS
	local n = #path
	local place = board.placeAt[Boards.cellOf(board, x, y)]
	if math.abs(place - p.seg) > 3 then
		p.seg = math.clamp(place, 1, n - 1)
	end
	local bestD, bestSeg, bestT = math.huge, p.seg, 0
	for k = math.max(1, p.seg - 1), math.min(n - 1, p.seg + 2) do
		local ax, ay = path[k][1], path[k][2]
		local bx, by = path[k + 1][1] - ax, path[k + 1][2] - ay
		local t = math.clamp(((x - ax) * bx + (y - ay) * by) / (bx * bx + by * by), 0, 1)
		local dx, dy = x - (ax + bx * t), y - (ay + by * t)
		local d = dx * dx + dy * dy
		if d <= bestD then
			bestD, bestSeg, bestT = d, k, t
		end
	end
	p.seg = bestSeg
	local along = pathS[bestSeg] + (pathS[bestSeg + 1] - pathS[bestSeg]) * bestT

	-- the point to aim at: a little further along the line
	local aim = math.min(along + def.look, pathS[n])
	local k = bestSeg
	while k < n - 1 and pathS[k + 1] < aim do
		k += 1
	end
	local span = pathS[k + 1] - pathS[k]
	local t = if span > 0 then (aim - pathS[k]) / span else 1
	local aimX = path[k][1] + (path[k + 1][1] - path[k][1]) * t
	local aimY = path[k][2] + (path[k + 1][2] - path[k][2]) * t

	-- the speed it wants: what the points ahead allow, braking at its own rate
	local want = def.cruise
	for j = bestSeg + 1, math.min(n, bestSeg + 6) do
		local gap = math.max(0, pathS[j] - along)
		want = math.min(want, math.sqrt(p.limits[j] ^ 2 + 2 * def.brake * gap))
	end
	local dx, dy = aimX - x, aimY - y
	local dist = math.sqrt(dx * dx + dy * dy)
	local wantVx, wantVy = 0, 0
	if dist > 1e-6 then
		-- at the very end, ease into the cup
		local speed = if aim >= pathS[n] then math.min(want, dist * 6 + 0.25) else want
		wantVx, wantVy = dx / dist * speed, dy / dist * speed
	end

	-- the tilt that would give it that speed, and the keys that swing the board there
	local limit = Physics.TILT_MAX
	local leanX = p.leanX[bestSeg] * (1 - bestT) + p.leanX[bestSeg + 1] * bestT
	local leanY = p.leanY[bestSeg] * (1 - bestT) + p.leanY[bestSeg + 1] * bestT
	local tiltX = math.clamp((wantVx - vx) * def.gain * DEG_PER_ACCEL + leanX * def.lean, -limit, limit)
	local tiltY = math.clamp((wantVy - vy) * def.gain * DEG_PER_ACCEL + leanY * def.lean, -limit, limit)
	local kx, nx = key(m.tx, m.wx, tiltX, def.band, def.think)
	local ky, ny = key(m.ty, m.wy, tiltY, def.band, def.think)
	p.held, p.tapX, p.tapY = Controls.code(kx, ky), nx, ny
	return p.held
end

-- A whole run by one pilot: the final state and the input log that made it.
function Pilot.play(
	board: Boards.Board,
	level: number,
	seed: number,
	hold: number?,
	maxTicks: number?
): (Run.State, { number })
	local s = Run.new(board, hold)
	local p = Pilot.new(board, level, seed)
	local codes: { number } = {}
	local limit = maxTicks or Run.MAX_TICKS
	local idle = 0
	while not Run.over(s) and #codes < limit do
		local code = Pilot.code(board, p, s)
		if s.phase == Run.PHASE.READY and code == Controls.NEUTRAL then
			-- nothing has been pressed yet: the clock has not started and this tick is not part of the log
			idle += 1
			if idle > 600 then
				break
			end
			continue
		end
		table.insert(codes, code)
		Run.step(board, s, code)
	end
	return s, codes
end

return Pilot
