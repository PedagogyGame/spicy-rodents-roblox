--!strict
-- ReplicatedStorage.Shared.Minigames.Labyrinth.Boards
-- The tilt marble labyrinth's boards as data (brief v2 §13a: "a playable tilt marble labyrinth" on the
-- waiting-room table at the doctor's office). One wooden box, several boards of rising difficulty that fit it.
-- A board is DRAWN here as a picture, the way the player sees it from the seat (far side at the top):
--   +--+--+   posts and walls on the grid lines ("--" and "|" are walls, spaces are open)
--   | S 6 |   two characters inside each cell: a hole (a digit, placed like the keys of a number pad: 7 8 9
--   +  +--+   far, 4 5 6 middle, 1 2 3 near; 5 is the middle of the cell, the others sit against that wall or
--   |  C F|   corner) then a mark (S the start, F the finish cup, C a checkpoint)
--   +--+--+
-- compile() turns the picture into geometry in studs: wall rectangles, holes, the line drawn on the board from
-- the start to the finish (the shortest way through, with the fewest turns, stepping aside from every hole it
-- passes), the holes numbered in the order that line passes them, the checkpoints, and the lookup tables the
-- physics uses. Everything the bake, the server and the client need about a board comes from here (C18).
-- Board frame: origin the middle of the board, +x to the player's right, +y forward (away from the player).
-- Sizes: a cell is PITCH across; a corridor is CORRIDOR wide, "a little over two marbles" (LAB-P4); a hole
-- against a wall leaves a strip beside the far wall that a marble can run along with its centre clear of the rim.
-- Pure; Lune-tested (tests/unit/labyrinth_boards.spec.luau).
-- Interface: PITCH, WALL, CORRIDOR, MARBLE_R, HOLE_R, FINISH_R, COLS, ROWS, WALL_HEIGHT, BOX; SOURCES;
--   compile(source) -> Board (errors with a plain reason when the picture is wrong); ALL { Board } in order of
--   difficulty; get(id or index) -> Board?; cellOf(board, x, y) -> cell; cellCentre(board, cell) -> (x, y);
--   picture(board) -> { string } (the board redrawn from its geometry, with the path numbered: tools and tests)

local Boards = {}

Boards.COLS = 10
Boards.ROWS = 8
Boards.WALL = 0.04 -- thickness of a wall
Boards.CORRIDOR = 0.27 -- clear width between two walls
Boards.PITCH = Boards.CORRIDOR + Boards.WALL
Boards.MARBLE_R = 0.06
Boards.HOLE_R = 0.07
Boards.HOLE_GAP = 0.008 -- wood left between a hole against a wall and that wall's face
Boards.FINISH_R = 0.085 -- the finish cup is a little wider than a hole
Boards.WALL_HEIGHT = 0.1 -- for the bake: the walls stand this far above the board
-- the box the board sits in (for the bake and the camera): the frame round the playfield and the depth under it
-- that the dropped marble rolls home through
Boards.BOX = table.freeze({ frame = 0.14, depth = 0.5, knobRadius = 0.11, knobLength = 0.16 })

-- where a hole sits in its cell, by number-pad digit: { across, forward } in units of the hole's offset
local HOLE_AT: { [string]: { number } } = {
	["1"] = { -1, -1 },
	["2"] = { 0, -1 },
	["3"] = { 1, -1 },
	["4"] = { -1, 0 },
	["5"] = { 0, 0 },
	["6"] = { 1, 0 },
	["7"] = { -1, 1 },
	["8"] = { 0, 1 },
	["9"] = { 1, 1 },
}
-- how far the drawn line steps aside from a hole in its own cell: to within a hair of the far wall
local SIDESTEP = Boards.CORRIDOR / 2 - Boards.MARBLE_R - 0.01
local CORNER_SIDESTEP = 0.035

export type Source = { id: string, name: string, level: number, blurb: string, map: { string } }
export type Hole = { x: number, y: number, r: number, n: number, at: number, cell: number, onPath: boolean }
export type Checkpoint = { x: number, y: number, at: number, n: number, cell: number }
export type Board = {
	id: string,
	name: string,
	level: number,
	blurb: string,
	cols: number,
	rows: number,
	pitch: number,
	x0: number, -- the grid's near-left corner (the centre lines of the left and near frame walls)
	y0: number,
	w: number, -- outside size of the playfield including its frame walls
	h: number,
	marbleR: number,
	walls: { { number } }, -- { x0, x1, y0, y1 }
	holes: { Hole }, -- numbered 1..#holes in the order the path passes them
	start: { x: number, y: number },
	finish: { x: number, y: number, r: number },
	checkpoints: { Checkpoint }, -- [1] is the start
	path: { { number } }, -- the drawn line: one { x, y } per cell on the way
	pathS: { number }, -- distance along the line to each of its points
	pathCells: { number },
	cellAt: { number }, -- cell -> its place on the path (0: not on it)
	placeAt: { number }, -- cell -> how far along the path a marble in that cell has come (a cell beside the
	-- line, or down a dead end, counts as the point of the line it lies off)
	numberAt: { number }, -- place on the path -> the highest hole number reached there
	checkpointAt: { number }, -- place on the path -> the last checkpoint passed there
	open: { number }, -- cell -> which sides are open: 1 right, 2 forward, 4 left, 8 near (bits)
	goal: number, -- the finish cup's index in hx/hy/hr (it is the last "hole")
	-- flat arrays for the physics
	wx0: { number },
	wx1: { number },
	wy0: { number },
	wy1: { number },
	hx: { number },
	hy: { number },
	hr: { number },
	cellWalls: { { number } }, -- cell -> the walls a marble whose centre is in that cell could touch
	cellHoles: { { number } },
}

-- The boards, easiest first. Each must fit the one box: COLS x ROWS cells.
Boards.SOURCES = {
	{
		id = "first_visit",
		name = "First Visit",
		level = 1,
		blurb = "Wide lanes and a handful of holes.",
		map = {
			"+--+--+--+--+--+--+--+--+--+--+",
			"| F          5            C   |",
			"+  +  +  +  +  +  +  +  +  +  +",
			"|                  5        9 |",
			"+--+--+--+--+--+--+--+--+  +  +",
			"|         5                   |",
			"+  +  +  +  +  +  +  +  +  +  +",
			"|    C             5          |",
			"+  +  +--+--+--+--+--+--+--+--+",
			"|               5             |",
			"+  +  +  +  +  +  +  +  +  +  +",
			"|1     5                     C|",
			"+--+--+--+--+--+--+--+--+  +  +",
			"|                  5          |",
			"+  +  +  +  +  +  +  +  +  +  +",
			"| S       5                 3 |",
			"+--+--+--+--+--+--+--+--+--+--+",
		},
	},
} :: { Source }

local function cellIndex(cols: number, c: number, r: number): number
	return (r - 1) * cols + c
end

-- the shortest way from one cell to another with the fewest turns: Dijkstra over (cell, heading), a step costs
-- 1000 and a turn 1, so the count of steps always decides first
local DC = { 1, 0, -1, 0 }
local DR = { 0, 1, 0, -1 }
local SIDE_BIT = { 1, 2, 4, 8 }

local function route(
	cols: number,
	rows: number,
	open: { number },
	blocked: { boolean },
	from: number,
	to: number
): { number }?
	local n = cols * rows
	local dist: { number } = table.create(n * 4, math.huge)
	local prev: { number } = table.create(n * 4, 0)
	local done: { boolean } = table.create(n * 4, false)
	for d = 1, 4 do
		dist[(from - 1) * 4 + d] = 0
	end
	while true do
		local best, bestD = 0, math.huge
		for i = 1, n * 4 do
			if not done[i] and dist[i] < bestD then
				best, bestD = i, dist[i]
			end
		end
		if best == 0 then
			break
		end
		done[best] = true
		local cell = (best - 1) // 4 + 1
		local heading = (best - 1) % 4 + 1
		if cell == to then
			local out = { cell }
			local at = best
			while prev[at] ~= 0 do
				at = prev[at]
				table.insert(out, 1, (at - 1) // 4 + 1)
			end
			return out
		end
		local c = (cell - 1) % cols + 1
		local r = (cell - 1) // cols + 1
		for d = 1, 4 do
			if bit32.band(open[cell], SIDE_BIT[d]) ~= 0 then
				local nc, nr = c + DC[d], r + DR[d]
				local nextCell = cellIndex(cols, nc, nr)
				if not blocked[nextCell] then
					local state = (nextCell - 1) * 4 + d
					local cost = bestD + 1000 + (if d == heading or cell == from then 0 else 1)
					if cost < dist[state] then
						dist[state] = cost
						prev[state] = best
					end
				end
			end
		end
	end
	return nil
end

function Boards.cellOf(board: Board, x: number, y: number): number
	local c = math.clamp(math.floor((x - board.x0) / board.pitch), 0, board.cols - 1)
	local r = math.clamp(math.floor((y - board.y0) / board.pitch), 0, board.rows - 1)
	return r * board.cols + c + 1
end

function Boards.cellCentre(board: Board, cell: number): (number, number)
	local c = (cell - 1) % board.cols
	local r = (cell - 1) // board.cols
	return board.x0 + (c + 0.5) * board.pitch, board.y0 + (r + 0.5) * board.pitch
end

function Boards.compile(source: Source): Board
	local cols, rows = Boards.COLS, Boards.ROWS
	local pitch, t = Boards.PITCH, Boards.WALL
	local map = source.map
	local function bad(why: string): never
		error(`labyrinth board "{source.id}": {why}`, 0)
	end
	if #map ~= rows * 2 + 1 then
		bad(`the picture needs {rows * 2 + 1} lines, it has {#map}`)
	end
	for i, line in map do
		if #line ~= cols * 3 + 1 then
			bad(`line {i} needs {cols * 3 + 1} characters, it has {#line}`)
		end
	end
	local x0, y0 = -cols * pitch / 2, -rows * pitch / 2
	-- line of the picture for the wall under row r (r = 0 is the near frame) and for the cells of row r
	local function wallLine(r: number): string
		return map[(rows - r) * 2 + 1]
	end
	local function cellLine(r: number): string
		return map[(rows - r) * 2 + 2]
	end
	-- is there a wall on the grid line above row r, between columns c-1 and c's posts? (r 0..rows)
	local function hWall(c: number, r: number): boolean
		local s = string.sub(wallLine(r), c * 3 - 1, c * 3)
		if s ~= "--" and s ~= "  " then
			bad(`row line {r}, column {c}: expected "--" or two spaces, found "{s}"`)
		end
		return s == "--"
	end
	-- is there a wall on the grid line to the right of column c, in row r? (c 0..cols)
	local function vWall(c: number, r: number): boolean
		local s = string.sub(cellLine(r), c * 3 + 1, c * 3 + 1)
		if s ~= "|" and s ~= " " then
			bad(`row {r}, after column {c}: expected "|" or a space, found "{s}"`)
		end
		return s == "|"
	end
	for r = 0, rows do
		local line = wallLine(r)
		for c = 0, cols do
			if string.sub(line, c * 3 + 1, c * 3 + 1) ~= "+" then
				bad(`row line {r}: no post at column {c}`)
			end
		end
	end
	for c = 1, cols do
		if not hWall(c, 0) or not hWall(c, rows) then
			bad(`the frame is open at column {c}`)
		end
	end
	for r = 1, rows do
		if not vWall(0, r) or not vWall(cols, r) then
			bad(`the frame is open at row {r}`)
		end
	end

	-- walls: every unbroken run along a grid line is one rectangle, its ends covering the posts
	local walls: { { number } } = {}
	for r = 0, rows do
		local y = y0 + r * pitch
		local c = 1
		while c <= cols do
			if hWall(c, r) then
				local first = c
				while c < cols and hWall(c + 1, r) do
					c += 1
				end
				table.insert(walls, { x0 + (first - 1) * pitch - t / 2, x0 + c * pitch + t / 2, y - t / 2, y + t / 2 })
			end
			c += 1
		end
	end
	for c = 0, cols do
		local x = x0 + c * pitch
		local r = 1
		while r <= rows do
			if vWall(c, r) then
				local first = r
				while r < rows and vWall(c, r + 1) do
					r += 1
				end
				table.insert(walls, { x - t / 2, x + t / 2, y0 + (first - 1) * pitch - t / 2, y0 + r * pitch + t / 2 })
			end
			r += 1
		end
	end

	-- cells: open sides, holes and marks
	local n = cols * rows
	local open: { number } = table.create(n, 0)
	local holeCode: { string } = table.create(n, " ")
	local blocked: { boolean } = table.create(n, false)
	local startCell, finishCell = 0, 0
	local checkpointCells: { number } = {}
	for r = 1, rows do
		for c = 1, cols do
			local cell = cellIndex(cols, c, r)
			local bits = 0
			if not vWall(c, r) then
				bits += 1
			end
			if not hWall(c, r) then
				bits += 2
			end
			if not vWall(c - 1, r) then
				bits += 4
			end
			if not hWall(c, r - 1) then
				bits += 8
			end
			open[cell] = bits
			local code = string.sub(cellLine(r), c * 3 - 1, c * 3 - 1)
			local mark = string.sub(cellLine(r), c * 3, c * 3)
			if code ~= " " and HOLE_AT[code] == nil then
				bad(`row {r}, column {c}: "{code}" is not a hole position (1 to 9)`)
			end
			holeCode[cell] = code
			blocked[cell] = code == "5"
			if mark == "S" then
				if startCell ~= 0 then
					bad("two starts")
				end
				startCell = cell
			elseif mark == "F" then
				if finishCell ~= 0 then
					bad("two finishes")
				end
				finishCell = cell
			elseif mark == "C" then
				table.insert(checkpointCells, cell)
			elseif mark ~= " " then
				bad(`row {r}, column {c}: "{mark}" is not a mark (S, F or C)`)
			end
		end
	end
	if startCell == 0 or finishCell == 0 then
		bad("a board needs one S and one F")
	end
	if holeCode[startCell] ~= " " or holeCode[finishCell] ~= " " then
		bad("the start and the finish cells cannot hold a hole")
	end

	local pathCells = route(cols, rows, open, blocked, startCell, finishCell)
	if pathCells == nil then
		bad("there is no way from the start to the finish")
	end
	local cellAt: { number } = table.create(n, 0)
	for i, cell in pathCells do
		cellAt[cell] = i
	end

	local function centre(cell: number): (number, number)
		local c = (cell - 1) % cols
		local r = (cell - 1) // cols
		return x0 + (c + 0.5) * pitch, y0 + (r + 0.5) * pitch
	end

	-- the drawn line: through the middle of each cell, stepping aside from a hole in that cell
	local holeOffset = Boards.CORRIDOR / 2 - Boards.HOLE_R - Boards.HOLE_GAP
	local path: { { number } } = {}
	local pathS: { number } = {}
	for i, cell in pathCells do
		local x, y = centre(cell)
		local at = HOLE_AT[holeCode[cell]]
		if at then
			if at[1] ~= 0 and at[2] ~= 0 then
				x -= at[1] * CORNER_SIDESTEP
				y -= at[2] * CORNER_SIDESTEP
			else
				x -= at[1] * SIDESTEP
				y -= at[2] * SIDESTEP
			end
		end
		path[i] = { x, y }
		if i == 1 then
			pathS[i] = 0
		else
			local dx, dy = x - path[i - 1][1], y - path[i - 1][2]
			pathS[i] = pathS[i - 1] + math.sqrt(dx * dx + dy * dy)
		end
	end

	-- every cell's place beside the path: where its branch joins the line (a hole down a dead end is numbered
	-- by the point of the path it lies off)
	local joinAt: { number } = table.create(n, 0)
	local queue: { number } = {}
	for i, cell in pathCells do
		joinAt[cell] = i
		queue[i] = cell
	end
	local head = 1
	while head <= #queue do
		local cell = queue[head]
		head += 1
		local c = (cell - 1) % cols + 1
		local r = (cell - 1) // cols + 1
		for d = 1, 4 do
			if bit32.band(open[cell], SIDE_BIT[d]) ~= 0 then
				local nextCell = cellIndex(cols, c + DC[d], r + DR[d])
				if joinAt[nextCell] == 0 then
					joinAt[nextCell] = joinAt[cell]
					table.insert(queue, nextCell)
				end
			end
		end
	end

	local holes: { Hole } = {}
	for cell = 1, n do
		local at = HOLE_AT[holeCode[cell]]
		if at then
			local x, y = centre(cell)
			if joinAt[cell] == 0 then
				bad(`the hole in cell {cell} can never be reached`)
			end
			table.insert(holes, {
				x = x + at[1] * holeOffset,
				y = y + at[2] * holeOffset,
				r = Boards.HOLE_R,
				n = 0,
				at = joinAt[cell],
				cell = cell,
				onPath = cellAt[cell] ~= 0,
			})
		end
	end
	table.sort(holes, function(a, b)
		if a.at ~= b.at then
			return a.at < b.at
		end
		return a.cell < b.cell
	end)
	for i, hole in holes do
		hole.n = i
	end
	-- the line must clear every rim
	for i, p in path do
		for _, hole in holes do
			local dx, dy = p[1] - hole.x, p[2] - hole.y
			if math.sqrt(dx * dx + dy * dy) < hole.r + 0.03 then
				bad(`the path's point {i} is on the rim of hole {hole.n}`)
			end
		end
	end

	local numberAt: { number } = table.create(#pathCells, 0)
	do
		local k = 0
		for i = 1, #pathCells do
			while k < #holes and holes[k + 1].at <= i do
				k += 1
			end
			numberAt[i] = k
		end
	end

	local sx, sy = centre(startCell)
	local checkpoints: { Checkpoint } = { { x = sx, y = sy, at = 1, n = 0, cell = startCell } }
	table.sort(checkpointCells, function(a, b)
		if joinAt[a] ~= joinAt[b] then
			return joinAt[a] < joinAt[b]
		end
		return a < b
	end)
	for _, cell in checkpointCells do
		if joinAt[cell] == 0 then
			bad(`the checkpoint in cell {cell} can never be reached`)
		end
		if holeCode[cell] ~= " " then
			bad(`the checkpoint in cell {cell} shares its cell with a hole`)
		end
		local x, y = centre(cell)
		table.insert(checkpoints, { x = x, y = y, at = joinAt[cell], n = numberAt[joinAt[cell]], cell = cell })
	end
	local checkpointAt: { number } = table.create(#pathCells, 1)
	do
		local k = 1
		for i = 1, #pathCells do
			while k < #checkpoints and checkpoints[k + 1].at <= i do
				k += 1
			end
			checkpointAt[i] = k
		end
	end

	-- flat arrays and the per-cell lookups for the physics
	local wx0, wx1, wy0, wy1 = {}, {}, {}, {}
	for i, w in walls do
		wx0[i], wx1[i], wy0[i], wy1[i] = w[1], w[2], w[3], w[4]
	end
	local hx, hy, hr = {}, {}, {}
	for i, hole in holes do
		hx[i], hy[i], hr[i] = hole.x, hole.y, hole.r
	end
	local fx, fy = centre(finishCell)
	local goal = #holes + 1
	hx[goal], hy[goal], hr[goal] = fx, fy, Boards.FINISH_R
	local reach = Boards.MARBLE_R + 0.05 -- a marble moves less than this in one step of the physics
	local cellWalls: { { number } } = {}
	local cellHoles: { { number } } = {}
	for cell = 1, n do
		local cx, cy = centre(cell)
		local ax0, ax1 = cx - pitch / 2, cx + pitch / 2
		local ay0, ay1 = cy - pitch / 2, cy + pitch / 2
		local wl, hl = {}, {}
		for i = 1, #walls do
			if wx1[i] > ax0 - reach and wx0[i] < ax1 + reach and wy1[i] > ay0 - reach and wy0[i] < ay1 + reach then
				table.insert(wl, i)
			end
		end
		for i = 1, #hx do
			local qx = math.clamp(hx[i], ax0, ax1)
			local qy = math.clamp(hy[i], ay0, ay1)
			local dx, dy = hx[i] - qx, hy[i] - qy
			if dx * dx + dy * dy < (hr[i] + 0.01) ^ 2 then
				table.insert(hl, i)
			end
		end
		cellWalls[cell] = wl
		cellHoles[cell] = hl
	end

	return table.freeze({
		id = source.id,
		name = source.name,
		level = source.level,
		blurb = source.blurb,
		cols = cols,
		rows = rows,
		pitch = pitch,
		x0 = x0,
		y0 = y0,
		w = cols * pitch + t,
		h = rows * pitch + t,
		marbleR = Boards.MARBLE_R,
		walls = walls,
		holes = holes,
		start = { x = sx, y = sy },
		finish = { x = fx, y = fy, r = Boards.FINISH_R },
		checkpoints = checkpoints,
		path = path,
		pathS = pathS,
		pathCells = pathCells,
		cellAt = cellAt,
		placeAt = joinAt,
		numberAt = numberAt,
		checkpointAt = checkpointAt,
		open = open,
		goal = goal,
		wx0 = wx0,
		wx1 = wx1,
		wy0 = wy0,
		wy1 = wy1,
		hx = hx,
		hy = hy,
		hr = hr,
		cellWalls = cellWalls,
		cellHoles = cellHoles,
	})
end

-- The board redrawn from its compiled geometry: walls from the open sides, each path cell showing the last two
-- digits of its place on the line, holes as "o", checkpoints as "C". For the calibrate tool and for eyes.
function Boards.picture(board: Board): { string }
	local out: { string } = {}
	local holeIn: { [number]: boolean } = {}
	for _, hole in board.holes do
		holeIn[hole.cell] = true
	end
	local checkpointIn: { [number]: boolean } = {}
	for _, cp in board.checkpoints do
		checkpointIn[cp.cell] = true
	end
	for r = board.rows, 1, -1 do
		local top, mid = { "+" }, {}
		for c = 1, board.cols do
			local cell = (r - 1) * board.cols + c
			table.insert(top, if bit32.band(board.open[cell], 2) ~= 0 then "  +" else "--+")
			local inside = "  "
			if holeIn[cell] then
				inside = if board.cellAt[cell] ~= 0 then "o." else "o "
			elseif checkpointIn[cell] then
				inside = "C" .. tostring(board.cellAt[cell] % 10)
			elseif board.cellAt[cell] ~= 0 then
				inside = string.format("%02d", board.cellAt[cell] % 100)
			end
			table.insert(mid, (if bit32.band(board.open[cell], 4) ~= 0 then " " else "|") .. inside)
		end
		table.insert(mid, "|")
		table.insert(out, table.concat(top))
		table.insert(out, table.concat(mid))
	end
	table.insert(out, "+" .. string.rep("--+", board.cols))
	return out
end

local all: { Board } = {}
for i, source in Boards.SOURCES do
	all[i] = Boards.compile(source)
end
Boards.ALL = all

function Boards.get(which: string | number): Board?
	if type(which) == "number" then
		return Boards.ALL[which]
	end
	for _, board in Boards.ALL do
		if board.id == which then
			return board
		end
	end
	return nil
end

return Boards
