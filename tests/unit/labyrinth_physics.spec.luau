--!strict
-- Minigames/Labyrinth/Physics and Run: the marble and the tilting board, pinned against the checklist's "what
-- real must mean" (LAB-P1..P6) and against the cases a fixed-step model must survive: energy never grows,
-- nothing passes through a wall at top speed, the same inputs give the same bytes, and a marble left alone
-- comes to rest.
local Boards = require("@shared/Minigames/Labyrinth/Boards")
local Controls = require("@shared/Minigames/Labyrinth/Controls")
local Physics = require("@shared/Minigames/Labyrinth/Physics")
local Run = require("@shared/Minigames/Labyrinth/Run")
local Rng = require("@shared/Util/Rng")
local Tunables = require("@shared/Config/Tunables")

local STAY, LEVEL = Physics.HOLD_STAY, Physics.HOLD_LEVEL
local FIRST = Boards.ALL[1] -- wide lanes: room to roll
local KNOWN = "1.244398391 -0.680778990 1 1"

-- a marble in the open middle of the first board's near lane (two cells high, clear for a stud each way)
local function openMarble(): Physics.Marble
	local x, y = Boards.cellCentre(FIRST, 1 * FIRST.cols + 5) -- column 5, row 2
	local m = Physics.new(x + FIRST.pitch / 2, y - FIRST.pitch / 2)
	m.cell = Boards.cellOf(FIRST, m.x, m.y)
	return m
end

-- a hole in the middle of its cell with open board around it (the first board's "5" holes)
local function openHole(): Boards.Hole
	for _, hole in FIRST.holes do
		local cx, cy = Boards.cellCentre(FIRST, hole.cell)
		if hole.x == cx and hole.y == cy then
			return hole
		end
	end
	error("the first board has no hole in the middle of a cell")
end

local function steps(board: Boards.Board, m: Physics.Marble, n: number, ux: number, uy: number, hold: number): number
	for _ = 1, n do
		local into = Physics.step(board, m, ux, uy, hold)
		if into ~= 0 then
			return into
		end
	end
	return 0
end

local function speed(m: Physics.Marble): number
	return math.sqrt(m.vx * m.vx + m.vy * m.vy)
end

-- the least distance from a point to any wall of a board
local function clearance(board: Boards.Board, x: number, y: number): number
	local least = math.huge
	for _, w in board.walls do
		local qx = math.clamp(x, w[1], w[2])
		local qy = math.clamp(y, w[3], w[4])
		least = math.min(least, math.sqrt((x - qx) ^ 2 + (y - qy) ^ 2))
	end
	return least
end

return function(t)
	t.test("LAB-P5: the board has weight: a tap tips it a fraction of a degree, a hold swings it to about 6", function()
		t.eq(Physics.TILT_RATE, Tunables.get("minigames.labyrinthTiltDegPerS"), "the swing rate is the tunable")
		t.near(Physics.TILT_MAX, 6, 1, "about six degrees")
		for ticks = 1, 3 do
			local tipped = Physics.tiltAfter(ticks)
			t.truthy(tipped > 0 and tipped < 1, `a {ticks}-tick tap tips the board a fraction of a degree ({tipped})`)
		end
		t.truthy(Physics.tiltAfter(2) > Physics.tiltAfter(1), "a longer tap tips it further")
		-- a hold: full swing, then the stop
		local m = openMarble()
		m.on = 0
		local reached = 0
		for tick = 1, 60 do
			local before = m.tx
			Physics.step(FIRST, m, 1, 0, STAY)
			t.truthy(m.tx - before <= Physics.TILT_RATE * Physics.TICK + 1e-9, "never faster than the swing rate")
			if m.tx >= Physics.TILT_MAX and reached == 0 then
				reached = tick
			end
		end
		t.eq(m.tx, Physics.TILT_MAX, "a hold ends at the stop")
		t.eq(m.ty, 0, "the other knob was not touched")
		t.truthy(reached >= 15 and reached <= 24, `full tilt in about a third of a second ({reached} ticks)`)
	end)

	t.test(
		"LAB-P5 / D1: let go and the board stays where it is, with a soft catch as it comes back to level",
		function()
			local m = openMarble()
			m.on = 0
			steps(FIRST, m, 12, 1, 0, STAY)
			steps(FIRST, m, 6, 0, 0, STAY)
			local tipped = m.tx
			t.truthy(tipped > 2 and tipped < Physics.TILT_MAX, "part way over")
			steps(FIRST, m, 120, 0, 0, STAY)
			t.eq(m.tx, tipped, "two seconds later it has not moved: real knobs stay put")
			-- hold the other key: it comes back, rests at level for the catch, then goes on over
			local levelTicks, wentOver = 0, false
			for _ = 1, 60 do
				Physics.step(FIRST, m, -1, 0, STAY)
				if m.tx == 0 then
					levelTicks += 1
				elseif m.tx < 0 then
					wentOver = true
					break
				end
			end
			t.truthy(levelTicks >= Physics.CATCH_TICKS, `it rests at level ({levelTicks} ticks) before going on`)
			t.truthy(wentOver, "held on, it goes on over the other way")
			-- letting go inside the catch leaves it dead level
			local n = openMarble()
			n.on = 0
			steps(FIRST, n, 12, 0, 1, STAY)
			for _ = 1, 60 do
				Physics.step(FIRST, n, 0, -1, STAY)
				if n.ty == 0 then
					break
				end
			end
			steps(FIRST, n, 60, 0, 0, STAY)
			t.eq(n.ty, 0, "let go in the catch: level, and it stays level")
			t.eq(n.wy, 0)
		end
	)

	t.test("D1, the other answer: with HOLD_LEVEL the board levels itself when the keys are let go", function()
		local m = openMarble()
		m.on = 0
		steps(FIRST, m, 30, 1, 1, LEVEL)
		t.eq(m.tx, Physics.TILT_MAX)
		steps(FIRST, m, 30, 0, 0, LEVEL)
		t.eq(m.tx, 0, "level again within half a second")
		t.eq(m.ty, 0)
		steps(FIRST, m, 30, 0, 0, LEVEL)
		t.eq(m.tx, 0, "and it stays there")
	end)

	t.test(
		"LAB-P1: the marble has weight: it speeds up down the slope and keeps going when the board levels",
		function()
			local m = openMarble()
			local x0 = m.x
			m.tx = Physics.TILT_MAX -- the board is already tipped right and held there
			local last = 0
			for _ = 1, 20 do
				t.eq(Physics.step(FIRST, m, 0, 0, STAY), 0)
				t.truthy(m.vx > last, "faster every tick down the slope")
				last = m.vx
			end
			-- a rolling ball takes 5/7 of the slope; a third of a second in, drag has hardly begun
			local slope = Physics.GRAVITY * Physics.ROLL * Physics.slope(Physics.TILT_MAX)
			t.near(slope, 5.97, 0.05, "full tilt is about six studs per second per second")
			t.near(m.vx, slope * 20 * Physics.TICK, 0.35, "speed after a third of a second")
			t.near(m.vy, 0, 1e-12, "straight down the slope")
			-- level the board in an instant: it keeps going
			m.tx = 0
			local v = m.vx
			steps(FIRST, m, 12, 0, 0, STAY)
			t.truthy(m.vx > v * 0.75, "a fifth of a second after the board levels it has most of its speed")
			t.truthy(m.x > x0 + 0.3, "and it has travelled on")
		end
	)

	t.test("LAB-P1: overshoot is the game: a counter-tilt catches the marble, level alone lets it run on", function()
		local function travel(counter: number): number
			local m = openMarble()
			m.vx = 1.5
			local x0 = m.x
			for _ = 1, 600 do
				-- hold the counter-tilt until the marble has stopped, then let the board be level
				local u = if counter ~= 0 and m.vx > 0.05 then counter else 0
				if u == 0 and counter ~= 0 then
					m.tx, m.wx = 0, 0
				end
				Physics.step(FIRST, m, u, 0, LEVEL)
				if speed(m) == 0 and m.tx == 0 then
					break
				end
			end
			return m.x - x0
		end
		local coasting = travel(0)
		local caught = travel(-1)
		t.truthy(coasting > 0.6, `left alone at 1.5 studs/s it rolls on a long way ({coasting} studs)`)
		t.truthy(caught < coasting * 0.6, `a counter-tilt stops it much sooner ({caught} against {coasting})`)
	end)

	t.test("LAB-P2: it rolls with a little resistance: a tiny tilt makes it creep, level stops it slowly", function()
		-- a one-tick tap (a twelfth of a degree) is under the rolling resistance: nothing moves
		local m = openMarble()
		local x0 = m.x
		Physics.step(FIRST, m, 1, 0, STAY)
		steps(FIRST, m, 120, 0, 0, STAY)
		t.truthy(m.tx > 0 and m.tx < 0.2)
		t.eq(m.x, x0, "under a fifth of a degree the marble does not stir")
		-- a three-tick tap (over half a degree): it creeps
		local c = openMarble()
		steps(FIRST, c, 3, 1, 0, STAY)
		steps(FIRST, c, 60, 0, 0, STAY)
		t.truthy(c.tx > 0.4 and c.tx < 1)
		t.truthy(c.vx > 0.05 and c.vx < 0.6, `a second later it is creeping ({c.vx} studs/s)`)
		-- level stops it, slowly, and then it is at rest for good
		local r = openMarble()
		r.vx = 1.2
		local stopped = 0
		for tick = 1, 600 do
			Physics.step(FIRST, r, 0, 0, STAY)
			if speed(r) == 0 then
				stopped = tick
				break
			end
		end
		t.truthy(stopped >= 60 and stopped <= 240, `on a level board it takes a few seconds to stop ({stopped} ticks)`)
		local rx, ry = r.x, r.y
		steps(FIRST, r, 300, 0, 0, STAY)
		t.eq(r.x, rx, "a rest state: five seconds later it has not moved a hair")
		t.eq(r.y, ry)
		t.eq(r.vx, 0)
		t.eq(r.vy, 0)
	end)

	t.test("LAB-P3: walls are wood: about a third of the speed comes back, a slow touch does not bounce", function()
		local R = FIRST.marbleR
		local nearFace = FIRST.y0 + Boards.WALL / 2 -- the inside face of the near frame wall
		for _, into in { 1, 2, 4 } do
			local m = openMarble()
			m.y = nearFace + R + 0.1
			m.vy = -into
			local hit, back = 0, 0
			for _ = 1, 30 do
				Physics.step(FIRST, m, 0, 0, STAY)
				if m.hit > 0 then
					hit, back = m.hit, m.vy
					break
				end
			end
			t.truthy(hit > into * 0.85 and hit <= into, `the hit is reported with its speed ({hit} of {into})`)
			t.near(back / hit, Physics.RESTITUTION, 0.02, "a third of the speed comes back")
			t.truthy(m.y >= nearFace + R - 1e-9, "and the marble is outside the wood")
		end
		local slow = openMarble()
		slow.y = nearFace + R + 0.01
		slow.vy = -0.2
		for _ = 1, 20 do
			Physics.step(FIRST, slow, 0, 0, STAY)
			t.truthy(slow.vy <= 1e-12, "a slow touch never comes back off the wall")
			t.eq(slow.hit, 0, "and makes no click")
		end
		t.near(slow.y, nearFace + R, 1e-9, "it rests against the wall")
	end)

	t.test("LAB-P3: it slides along a wall, and an inside corner neither traps it nor shakes it", function()
		local R = FIRST.marbleR
		local nearFace = FIRST.y0 + Boards.WALL / 2
		local leftFace = FIRST.x0 + Boards.WALL / 2
		-- tipped into the near wall and to the left: it runs along the wall, touching it all the way
		local m = Physics.new(-0.75, nearFace + R + 0.02)
		m.tx, m.ty = -3, -4
		steps(FIRST, m, 20, 0, 0, STAY)
		local x1 = m.x
		for _ = 1, 20 do
			Physics.step(FIRST, m, 0, 0, STAY)
			t.eq(m.touch, 1, "against the wall")
			t.near(m.y, nearFace + R, 1e-9, "its distance from the wall does not flicker")
			t.eq(m.hit, 0, "sliding makes no clicks")
		end
		t.truthy(m.x < x1 - 0.05, "and it moves along the wall")
		-- into the corner: it comes to rest there, exactly still
		m.tx, m.ty = -5, -5
		steps(FIRST, m, 180, 0, 0, STAY)
		t.near(m.x, leftFace + R, 1e-9, "in the corner")
		t.near(m.y, nearFace + R, 1e-9)
		local cx, cy = m.x, m.y
		for _ = 1, 120 do
			Physics.step(FIRST, m, 0, 0, STAY)
			t.eq(m.x, cx, "no jitter in the corner")
			t.eq(m.y, cy)
		end
		-- and it leaves the corner the moment the board tips the other way
		m.tx, m.ty = 5, 5
		steps(FIRST, m, 30, 0, 0, STAY)
		t.truthy(m.x > cx + 0.05 and m.y > cy + 0.05, "a corner never traps it")
	end)

	t.test("the end of a wall is a round corner: the marble catches on it and rolls around", function()
		-- the first board's lane wall above row 2 runs from the left frame to the post after column 8
		local R = FIRST.marbleR
		local wallY = FIRST.y0 + 2 * FIRST.pitch
		local wallEnd = FIRST.x0 + 8 * FIRST.pitch + Boards.WALL / 2
		local m = Physics.new(wallEnd - 0.25, wallY - Boards.WALL / 2 - R - 0.01)
		m.tx, m.ty = 2, 4 -- pressed up under the wall, drifting right toward its end
		local passed = false
		for _ = 1, 360 do
			Physics.step(FIRST, m, 0, 0, STAY)
			t.truthy(clearance(FIRST, m.x, m.y) >= R - 1e-6, "never inside the wood on the way round")
			if m.y > wallY + Boards.WALL / 2 + R then
				passed = true
				break
			end
		end
		t.truthy(passed, "it rolls round the end of the wall and on up the board")
		t.truthy(m.x > wallEnd, "round the outside of the corner")
	end)

	t.test("LAB-P4: holes have rims: clear of the edge it stays, past the edge it is drawn in and drops", function()
		local hole = openHole()
		local index = hole.n
		-- at rest with the centre just outside the edge: nothing happens
		local out = Physics.new(hole.x + hole.r + 0.004, hole.y)
		t.eq(steps(FIRST, out, 120, 0, 0, STAY), 0)
		t.eq(out.x, hole.x + hole.r + 0.004, "clear of the rim it stays where it is")
		t.eq(out.rim, 0)
		-- at rest with the centre a hair past the edge: the rim draws it in, faster and faster, and it drops
		local over = Physics.new(hole.x + hole.r - 0.004, hole.y)
		local dropped, deepest = 0, 0
		for tick = 1, 120 do
			local into = Physics.step(FIRST, over, 0, 0, STAY)
			if into ~= 0 then
				t.eq(into, index, "the model says which hole")
				dropped = tick
				break
			end
			t.truthy(over.rim >= deepest, "it only sinks further")
			deepest = over.rim
			t.truthy(over.vx <= 0, "drawn toward the hole")
		end
		t.truthy(dropped > 3 and dropped < 60, `it tips in over a moment, not at once ({dropped} ticks)`)
		t.eq(over.on, 0, "gone from the board")
		t.truthy(deepest > 0.2 and deepest < Physics.CAPTURE, "it stood over the rim on the way")
	end)

	t.test("LAB-P4: clip the rim at speed and it skirts round and lives; the same line slowly, it drops", function()
		local hole = openHole()
		local function cross(v: number): (number, Physics.Marble, number)
			-- a line that passes with the centre a seventh of the marble's radius inside the edge
			local m = Physics.new(hole.x - 0.25, hole.y + hole.r - FIRST.marbleR / 7)
			m.vx = v
			local deepest = 0
			for _ = 1, 240 do
				local into = Physics.step(FIRST, m, 0, 0, STAY)
				deepest = math.max(deepest, m.rim)
				if into ~= 0 then
					return into, m, deepest
				end
				if m.x > hole.x + 0.2 then
					break
				end
			end
			return 0, m, deepest
		end
		local into, fast, deepest = cross(3)
		t.eq(into, 0, "at speed it lives")
		t.truthy(deepest > 0.1 and deepest < Physics.CAPTURE, `it did stand over the rim ({deepest} of its radius)`)
		t.truthy(fast.vy < -0.05, "and the rim bent its path toward the hole")
		t.truthy(fast.x > hole.x + 0.15, "and it is past")
		local slowInto = cross(0.5)
		t.eq(slowInto, hole.n, "slowly along the same line the rim takes it")
	end)

	t.test("LAB-P4: a marble well over the edge drops whatever its speed; the finish cup is a hole too", function()
		local hole = openHole()
		for _, v in { 0.5, 2, 4, Physics.MAX_SPEED } do
			local m = Physics.new(hole.x - 0.2, hole.y)
			m.vx = v
			t.eq(steps(FIRST, m, 120, 0, 0, STAY), hole.n, `straight over the middle at {v} studs/s`)
		end
		local cup = Physics.new(FIRST.finish.x + 0.15, FIRST.finish.y)
		cup.vx = -1
		t.eq(steps(FIRST, cup, 120, 0, 0, STAY), FIRST.goal, "into the cup")
		t.truthy(FIRST.finish.r > hole.r, "the cup is a little wider than a hole")
	end)

	t.test("nothing passes through a wall: top speed, any direction, any tilt, every board", function()
		for _, board in Boards.ALL do
			local rng = Rng.new(900 + board.level)
			local R = board.marbleR
			for _ = 1, 120 do
				local cell = rng.int(1, board.cols * board.rows)
				local cx, cy = Boards.cellCentre(board, cell)
				local m = Physics.new(cx + rng.range(-0.06, 0.06), cy + rng.range(-0.06, 0.06))
				local dx, dy = rng.range(-1, 1), rng.range(-1, 1)
				local d = math.max(math.sqrt(dx * dx + dy * dy), 1e-6)
				m.vx, m.vy = dx / d * Physics.MAX_SPEED, dy / d * Physics.MAX_SPEED
				local ux, uy = rng.int(-1, 1), rng.int(-1, 1)
				local was = Boards.cellOf(board, m.x, m.y)
				for _ = 1, 90 do
					if Physics.step(board, m, ux, uy, STAY) ~= 0 then
						break
					end
					t.truthy(speed(m) <= Physics.MAX_SPEED + 1e-9, "never over the top speed")
					t.truthy(clearance(board, m.x, m.y) >= R - 1e-6, "the marble is never inside a wall")
					-- and it only ever changes cell through an open side
					local now = Boards.cellOf(board, m.x, m.y)
					if now ~= was then
						local dc = (now - 1) % board.cols - (was - 1) % board.cols
						local dr = (now - 1) // board.cols - (was - 1) // board.cols
						t.truthy(math.abs(dc) <= 1 and math.abs(dr) <= 1, "one cell at a time")
						local function open(from: number, c: number, r: number): boolean
							local bit = if c == 1 then 1 elseif c == -1 then 4 elseif r == 1 then 2 else 8
							return bit32.band(board.open[from], bit) ~= 0
						end
						if dc ~= 0 and dr ~= 0 then
							-- round a post: one of the two ways round must be open
							local viaC = open(was, dc, 0) and open(was + dc, 0, dr)
							local viaR = open(was, 0, dr) and open(was + dr * board.cols, dc, 0)
							t.truthy(viaC or viaR, "a diagonal move goes round an open corner")
						else
							t.truthy(open(was, dc, dr), `from cell {was} to {now} there is a wall`)
						end
						was = now
					end
				end
			end
		end
	end)

	t.test(
		"energy never grows while the board is held still (only a rim crossing wobbles, and gives it back)",
		function()
			for _, board in Boards.ALL do
				local rng = Rng.new(40 + board.level)
				for _ = 1, 80 do
					local cell = rng.int(1, board.cols * board.rows)
					local cx, cy = Boards.cellCentre(board, cell)
					local m = Physics.new(cx + rng.range(-0.05, 0.05), cy + rng.range(-0.05, 0.05))
					local dx, dy = rng.range(-1, 1), rng.range(-1, 1)
					local v = rng.range(0, Physics.MAX_SPEED) / math.max(math.sqrt(dx * dx + dy * dy), 1e-6)
					m.vx, m.vy = dx * v, dy * v
					m.tx, m.ty = rng.range(-6, 6), rng.range(-6, 6)
					local start = Physics.energy(m, board)
					local e, wasOverRim = start, true
					for _ = 1, 240 do
						if Physics.step(board, m, 0, 0, STAY) ~= 0 then
							break
						end
						local now = Physics.energy(m, board)
						if m.rim == 0 and not wasOverRim then
							t.truthy(now <= e + 1e-9, `on the flat, energy only ever goes down ({e} to {now})`)
						end
						t.truthy(now <= start + 0.1, "and never above where it started (rim wobble under 0.1)")
						wasOverRim = m.rim > 0
						e = now
					end
					if m.on == 1 and m.rim == 0 then
						t.truthy(e <= start + 1e-9, "at the end it has no more than it began with")
					end
				end
			end
		end
	)

	t.test("a marble left alone on a level board always comes to rest", function()
		for _, board in Boards.ALL do
			local rng = Rng.new(7 + board.level)
			for _ = 1, 40 do
				local cx, cy = Boards.cellCentre(board, rng.int(1, board.cols * board.rows))
				local m = Physics.new(cx, cy)
				m.vx, m.vy = rng.range(-5, 5), rng.range(-5, 5)
				local rested = false
				for _ = 1, 900 do
					if Physics.step(board, m, 0, 0, STAY) ~= 0 or speed(m) == 0 then
						rested = true
						break
					end
				end
				t.truthy(rested, "within fifteen seconds it has stopped (or gone down a hole)")
			end
		end
	end)

	t.test("LAB-P6: the same board, hold and codes give the same bytes; no state is hidden", function()
		for _, board in Boards.ALL do
			for _, hold in { STAY, LEVEL } do
				local rng = Rng.new(board.level * 10 + hold)
				local codes: { number } = {}
				local code = Controls.code(1, 1)
				for i = 1, 1500 do
					if i % 20 == 0 then
						code = rng.int(0, 8)
					end
					codes[i] = code
				end
				local a = Run.new(board, hold)
				local b = Run.new(board, hold)
				local copied: Run.State? = nil
				for i, c in codes do
					Run.step(board, a, c)
					Run.step(board, b, c)
					if i % 250 == 0 then
						t.eq(Run.bytes(a), Run.bytes(b), `the same bytes at tick {i}`)
					end
					if i == 700 then
						-- a copy taken mid-run, and a snapshot sent over a wire, carry everything
						copied = Run.restore(Run.snapshot(a))
						t.truthy(copied ~= nil, "a snapshot restores")
					elseif copied ~= nil then
						Run.step(board, copied, c)
					end
				end
				t.eq(Run.bytes(a), Run.bytes(b))
				t.eq(Run.bytes(copied :: Run.State), Run.bytes(a), "the restored copy played on to the same bytes")
				t.eq(Run.digest(a), Run.digest(b))
				t.eq(Run.bytes(Run.replay(board, hold, codes)), Run.bytes(a), "replay is the same run")
				-- one different key, one tick long, and it is a different run
				local head = table.move(codes, 1, 60, 1, {})
				local other = table.clone(head)
				other[40] = if other[40] == 0 then 8 else 0
				t.neq(
					Run.bytes(Run.replay(board, hold, other)),
					Run.bytes(Run.replay(board, hold, head)),
					"a different log is a different run"
				)
			end
		end
	end)

	t.test("LAB-P6: a known run lands on a known spot (the pin that notices a change on any machine)", function()
		-- hold right for half a second, forward for a second, then nothing: the first board, knobs that stay
		local codes: { number } = {}
		for i = 1, 240 do
			codes[i] = if i <= 30 then Controls.code(1, 0) elseif i <= 90 then Controls.code(0, 1) else Controls.NEUTRAL
		end
		local s = Run.replay(FIRST, STAY, codes)
		t.eq(s.tick, 240)
		t.eq(s.m.tx, Physics.TILT_MAX, "the right-hand knob was left hard over")
		t.eq(s.m.ty, Physics.TILT_MAX)
		-- if a tuning constant changes on purpose, read the new numbers from the failure and put them here
		t.eq(string.format("%.9f %.9f %d %d", s.m.x, s.m.y, s.phase, s.drops), KNOWN, "the known run")
	end)
end
