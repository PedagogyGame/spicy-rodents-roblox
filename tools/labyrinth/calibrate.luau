--!strict
-- tools/labyrinth/calibrate.luau: a developer's look at the tilt labyrinth's model (Shared/Minigames/Labyrinth)
-- so its constants and its boards are tuned from numbers, not guesses. Prints: each board as the model sees it
-- (the drawn line numbered, holes, checkpoints); the feel numbers (how far a tap tips the board, how long a
-- hold takes, how fast the marble gets, how far it rolls on, how fast it must go to skirt a rim); what every
-- computer hand does on every board with both kinds of knob (how often it finishes, its time, the marbles it
-- drops, which holes take them); the size of the input log; and what a tick costs.
-- Usage, from the repo root: lune run tools/labyrinth/calibrate.luau [runs per line, default 20] [boards]
--   (a second argument "boards" prints only the pictures)
-- Interface: a script (prints a report); nothing is written.

local process = require("@lune/process")
local Boards = require("../../src/shared/Minigames/Labyrinth/Boards")
local Controls = require("../../src/shared/Minigames/Labyrinth/Controls")
local InputLog = require("../../src/shared/Minigames/Labyrinth/InputLog")
local Physics = require("../../src/shared/Minigames/Labyrinth/Physics")
local Pilot = require("../../src/shared/Minigames/Labyrinth/Pilot")
local Run = require("../../src/shared/Minigames/Labyrinth/Run")

local N = tonumber(process.args[1]) or 20
local ONLY_BOARDS = process.args[2] == "boards"
local STAY, LEVEL = Physics.HOLD_STAY, Physics.HOLD_LEVEL
local FIRST = Boards.ALL[1]

-- an empty board of the same box (no inside walls, no holes) to measure the marble on
local function emptyBoard(): Boards.Board
	local map = {}
	for r = Boards.ROWS, 1, -1 do
		table.insert(map, "+" .. string.rep(if r == Boards.ROWS then "--+" else "  +", Boards.COLS))
		local mark = if r == Boards.ROWS then "F" elseif r == 1 then "S" else " "
		table.insert(map, "| " .. mark .. string.rep("   ", Boards.COLS - 1) .. "|")
	end
	table.insert(map, "+" .. string.rep("--+", Boards.COLS))
	return Boards.compile({ id = "empty", name = "Empty", level = 0, blurb = "", map = map })
end
local EMPTY = emptyBoard()

local function fmt(v: number, places: number?): string
	return string.format(`%.{places or 1}f`, v)
end

print(
	`== the box: {Boards.COLS} x {Boards.ROWS} cells of {fmt(Boards.PITCH, 2)} studs; playfield {fmt(FIRST.w, 2)} x {fmt(
		FIRST.h,
		2
	)}; corridor {fmt(Boards.CORRIDOR, 2)} = {fmt(Boards.CORRIDOR / (2 * Boards.MARBLE_R), 2)} marbles; marble r {Boards.MARBLE_R}, hole r {Boards.HOLE_R}, cup r {Boards.FINISH_R}`
)
print(
	`   strip for the marble's centre beside a hole against a wall: {fmt(
		Boards.CORRIDOR - Boards.MARBLE_R - Boards.HOLE_GAP - 2 * Boards.HOLE_R,
		3
	)} studs`
)
for _, board in Boards.ALL do
	local onPath = 0
	for _, hole in board.holes do
		if hole.onPath then
			onPath += 1
		end
	end
	print(
		`-- board {board.level} "{board.name}" ({board.id}): line {fmt(board.pathS[#board.pathS], 1)} studs over {#board.pathCells} cells, {#board.holes} holes ({onPath} on the line, {fmt(
			#board.holes / board.pathS[#board.pathS],
			2
		)} to the stud), {#board.checkpoints - 1} checkpoints, {#board.walls} walls`
	)
	for _, line in Boards.picture(board) do
		print("   " .. line)
	end
end
if ONLY_BOARDS then
	return
end

-- the feel numbers ---------------------------------------------------------------------------------------------
print("")
print("== feel: the board")
local taps = {}
for _, ticks in { 1, 2, 3, 4, 6, 9 } do
	table.insert(taps, `{ticks} ticks -> {fmt(Physics.tiltAfter(ticks), 2)} deg`)
end
print("   a tap from level (knobs that stay): " .. table.concat(taps, ", "))
do
	local m = Physics.new(0, 0)
	m.on = 0
	local full = 0
	for tick = 1, 120 do
		Physics.step(FIRST, m, 1, 0, STAY)
		if m.tx >= Physics.TILT_MAX then
			full = tick
			break
		end
	end
	local back = 0
	for tick = 1, 240 do
		Physics.step(FIRST, m, -1, 0, STAY)
		if m.tx <= -Physics.TILT_MAX then
			back = tick
			break
		end
	end
	local selfLevel = 0
	for tick = 1, 240 do
		Physics.step(FIRST, m, 0, 0, LEVEL)
		if m.tx == 0 then
			selfLevel = tick
			break
		end
	end
	print(
		`   a hold: level to {Physics.TILT_MAX} deg in {fmt(full / 60, 2)} s; hard over to hard over in {fmt(
			back / 60,
			2
		)} s (with the {Physics.CATCH_TICKS}-tick catch at level); knobs that level: back to level in {fmt(
			selfLevel / 60,
			2
		)} s`
	)
end

print("== feel: the marble")
local slopeAccel = Physics.GRAVITY * Physics.ROLL * Physics.slope(Physics.TILT_MAX)
print(
	`   down the slope at full tilt: {fmt(slopeAccel, 2)} studs/s^2 ({fmt(
		Physics.GRAVITY * Physics.ROLL * Physics.slope(1),
		2
	)} per degree); it will not stir under {fmt(
		Physics.ROLL_RESIST / (Physics.GRAVITY * Physics.ROLL * Physics.slope(1)),
		2
	)} deg; terminal speed about {fmt((slopeAccel - Physics.ROLL_RESIST) / Physics.DRAG, 1)} (ceiling {Physics.MAX_SPEED})`
)
do
	-- across an empty board, full tilt held from rest: speed after each cell
	local m = Physics.new(EMPTY.x0 + Boards.PITCH * 0.5, EMPTY.y0 + Boards.PITCH * 3.5)
	m.tx = Physics.TILT_MAX
	local marks = {}
	local nextCell = 1
	for tick = 1, 600 do
		if Physics.step(EMPTY, m, 0, 0, STAY) ~= 0 or m.touch == 1 then
			break
		end
		if m.x >= EMPTY.x0 + Boards.PITCH * (0.5 + nextCell) then
			if nextCell == 1 or nextCell == 2 or nextCell == 4 or nextCell == 8 then
				table.insert(marks, `{nextCell} cells: {fmt(m.vx, 2)} studs/s at {fmt(tick / 60, 2)} s`)
			end
			nextCell += 1
		end
	end
	print("   from rest at full tilt: " .. table.concat(marks, "; "))
	local rolls = {}
	for _, v in { 0.5, 1, 2, 4 } do
		local r = Physics.new(EMPTY.x0 + Boards.PITCH * 0.5, EMPTY.y0 + Boards.PITCH * 3.5)
		r.vx = v
		local x0, ticks = r.x, 0
		for tick = 1, 1200 do
			Physics.step(EMPTY, r, 0, 0, STAY)
			if (r.vx == 0 and r.vy == 0) or r.touch == 1 then
				ticks = tick
				break
			end
		end
		table.insert(
			rolls,
			`{v} studs/s rolls {fmt(r.x - x0, 2)} studs in {fmt(ticks / 60, 1)} s{if r.touch == 1
				then " (to the wall)"
				else ""}`
		)
	end
	print("   let go on a level board: " .. table.concat(rolls, "; "))
end
do
	-- the rim: the slowest speed that skirts a hole on a line a given share of the radius inside its edge
	local hole: Boards.Hole? = nil
	for _, h in FIRST.holes do
		local cx, cy = Boards.cellCentre(FIRST, h.cell)
		if h.x == cx and h.y == cy then
			hole = h
			break
		end
	end
	if hole then
		local parts = {}
		for _, share in { 0.05, 0.1, 0.2, 0.3, 0.4 } do
			local least = -1
			for v10 = 1, 70 do
				local m = Physics.new(hole.x - 0.25, hole.y + hole.r - share * FIRST.marbleR)
				m.vx = v10 / 10
				local dropped = false
				for _ = 1, 600 do
					if Physics.step(FIRST, m, 0, 0, STAY) ~= 0 then
						dropped = true
						break
					end
					if m.x > hole.x + 0.2 or (m.vx == 0 and m.vy == 0) then
						break
					end
				end
				if not dropped and m.x > hole.x + 0.2 then
					least = v10 / 10
					break
				end
			end
			table.insert(
				parts,
				`{fmt(share * 100, 0)}% over: {if least < 0 then "never" else fmt(least, 1) .. " studs/s"}`
			)
		end
		print(
			`   skirting a rim (the marble drops at {fmt(Physics.CAPTURE * 100, 0)}% of its radius over the edge): slowest speed that lives on a line `
				.. table.concat(parts, "; ")
		)
	end
	print(
		`   a wall gives back {fmt(Physics.RESTITUTION * 100, 0)}% of a hit over {Physics.BOUNCE_MIN} studs/s and nothing of a slower one; rub along a wall {fmt(
			Physics.WALL_FRICTION * 100,
			0
		)}% of the push into it`
	)
end

-- the computer hands -------------------------------------------------------------------------------------------
print("")
print(`== computer hands: {N} seeded runs each (a run ends at the cup or at {Run.MAX_TICKS / 3600} minutes)`)
local logChars: { [number]: number } = {}
local logTicks: { [number]: number } = {}
for _, board in Boards.ALL do
	for _, hold in { STAY, LEVEL } do
		print(`-- {board.name}, knobs that {if hold == STAY then "stay" else "level"}`)
		for level, def in Pilot.LEVELS do
			local finished, ticks, drops, reached = 0, 0, 0, 0
			local best, worst = math.huge, 0
			local byHole: { [number]: number } = {}
			local runs = if level == Pilot.STEADY then 1 else N
			for seed = 1, runs do
				local s = Run.new(board, hold)
				local p = Pilot.new(board, level, seed)
				local codes: { number } = {}
				while not Run.over(s) do
					local code = Pilot.code(board, p, s)
					if s.phase == Run.PHASE.READY and code == Controls.NEUTRAL then
						continue
					end
					table.insert(codes, code)
					Run.step(board, s, code)
					if bit32.band(s.ev, Run.EV.FELL) ~= 0 then
						byHole[s.hole] = (byHole[s.hole] or 0) + 1
					end
				end
				if s.phase == Run.PHASE.FINISHED then
					finished += 1
					ticks += s.tick
					best = math.min(best, s.tick)
					worst = math.max(worst, s.tick)
				end
				drops += s.drops
				reached += s.reached
				if hold == STAY then
					logChars[level] = (logChars[level] or 0) + #InputLog.encode(codes)
					logTicks[level] = (logTicks[level] or 0) + #codes
				end
			end
			local holes = {}
			for n in byHole do
				table.insert(holes, n)
			end
			table.sort(holes, function(a, b)
				return byHole[a] > byHole[b]
			end)
			local top = {}
			for i = 1, math.min(3, #holes) do
				table.insert(top, `#{holes[i]} x{byHole[holes[i]]}`)
			end
			local times = if finished > 0
				then `time {fmt(ticks / finished / 60)} s (best {fmt(best / 60)}, worst {fmt(worst / 60)})`
				else "no finish"
			print(
				`   {string.format("%-16s", def.name)} finish {string.format("%3.0f", finished / runs * 100)}%  {times}  drops {fmt(
					drops / runs,
					1
				)}  reached {fmt(reached / runs, 1)}/{#board.holes}{if #top > 0
					then "  | worst holes " .. table.concat(top, ", ")
					else ""}`
			)
		end
	end
end

print("")
print("== the input log (knobs that stay): characters a second of play, by hand")
for level, def in Pilot.LEVELS do
	if logTicks[level] and logTicks[level] > 0 then
		print(
			`   {string.format("%-16s", def.name)} {fmt(logChars[level] / (logTicks[level] / 60), 0)} characters a second; a piece every {InputLog.SEND_EVERY} ticks is {fmt(
				logChars[level] / logTicks[level] * InputLog.SEND_EVERY,
				0
			)} characters (cap {InputLog.SEGMENT_CHARS})`
		)
	end
end

-- cost -----------------------------------------------------------------------------------------------------------
print("")
print("== cost (this machine, Lune; the engine's Luau is faster)")
do
	local board = Boards.ALL[#Boards.ALL]
	local _, codes = Pilot.play(board, 3, 1)
	local rounds = math.max(1, 400000 // #codes)
	local started = os.clock()
	local steps = 0
	for _ = 1, rounds do
		local s = Run.new(board)
		for _, code in codes do
			Run.step(board, s, code)
		end
		steps += #codes
	end
	local perTick = (os.clock() - started) / steps * 1e6
	print(
		`   Run.step (marble, board and rules; {Physics.SUBSTEPS} sub-steps): {fmt(perTick, 2)} microseconds a tick on the hardest board; the game needs {1 / Physics.TICK} ticks a second = {fmt(
			perTick * 60 / 1000,
			3
		)} ms of every second`
	)
	print(
		`   the server's replay of one {InputLog.SEGMENT_TICKS}-tick piece: {fmt(
			perTick * InputLog.SEGMENT_TICKS / 1000,
			3
		)} ms at most; of a whole four-minute run: {fmt(perTick * Run.MAX_TICKS / 1000, 1)} ms spread over the four minutes`
	)
	local s = Run.new(board)
	local p = Pilot.new(board, 3, 1)
	started = os.clock()
	local n = 0
	while not Run.over(s) and n < 20000 do
		Run.step(board, s, Pilot.code(board, p, s))
		n += 1
	end
	print(
		`   a computer hand's decision and its tick together: {fmt((os.clock() - started) / n * 1e6, 2)} microseconds`
	)
end
