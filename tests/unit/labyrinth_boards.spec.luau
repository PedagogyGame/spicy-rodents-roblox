--!strict
-- Minigames/Labyrinth/Boards: the boards as data. What is drawn in the picture is what is compiled, what is
-- compiled is what the physics looks things up in (C18), and every board is a fair labyrinth: one start, one
-- finish, a drawn line between them that a marble fits along, holes numbered in the order the line passes them.
local Boards = require("@shared/Minigames/Labyrinth/Boards")
local Rng = require("@shared/Util/Rng")

local function dist(ax: number, ay: number, bx: number, by: number): number
	return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

-- the least distance from a point to a wall rectangle
local function toWall(w: { number }, x: number, y: number): number
	return dist(x, y, math.clamp(x, w[1], w[2]), math.clamp(y, w[3], w[4]))
end

-- a copy of a board's source with one line of its picture changed
local function broken(line: number, text: string): Boards.Source
	local source = table.clone(Boards.SOURCES[1])
	source.map = table.clone(source.map)
	source.map[line] = text
	return source
end

return function(t)
	t.test("LAB-P4 / C18: one box, a corridor a little over two marbles wide, a strip to pass every hole", function()
		local marble = Boards.MARBLE_R * 2
		t.truthy(Boards.CORRIDOR > 2 * marble and Boards.CORRIDOR < 2.5 * marble, "a little over two marbles wide")
		t.near(Boards.PITCH, Boards.CORRIDOR + Boards.WALL, 1e-12)
		t.truthy(Boards.HOLE_R > Boards.MARBLE_R, "the marble fits down a hole")
		t.truthy(Boards.FINISH_R > Boards.HOLE_R, "the cup is wider than a hole")
		-- past a hole against one wall, the marble's centre has this much room clear of the rim along the other
		local strip = Boards.CORRIDOR - Boards.MARBLE_R - (Boards.HOLE_GAP + 2 * Boards.HOLE_R)
		t.truthy(strip >= 0.05, `the strip beside a hole is passable ({strip} studs for the centre)`)
		t.truthy(strip < Boards.MARBLE_R * 2, "and narrow enough to matter")
		t.eq(#Boards.ALL, #Boards.SOURCES)
		t.truthy(#Boards.ALL >= 3, "several boards")
		for i, board in Boards.ALL do
			t.eq(board.level, i, "in order of difficulty")
			t.eq(board.cols, Boards.COLS)
			t.eq(board.rows, Boards.ROWS)
			t.near(board.w, Boards.COLS * Boards.PITCH + Boards.WALL, 1e-12, "every board fits the one box")
			t.near(board.h, Boards.ROWS * Boards.PITCH + Boards.WALL, 1e-12)
			t.eq(board.marbleR, Boards.MARBLE_R)
			t.eq(Boards.get(board.id), board, "found by id")
			t.eq(Boards.get(i), board, "and by number")
		end
		t.eq(Boards.get("nowhere"), nil)
		t.truthy(Boards.ALL[1].w > 3 and Boards.ALL[1].w < 3.3, "about three studs across, as the table expects")
		t.truthy(Boards.ALL[1].h > 2.4 and Boards.ALL[1].h < 2.7)
	end)

	t.test("the walls are inside the box, the frame is whole, and no hole is cut into a wall", function()
		for _, board in Boards.ALL do
			local halfW, halfH = board.w / 2, board.h / 2
			for _, w in board.walls do
				t.truthy(w[1] < w[2] and w[3] < w[4], "a wall has a size")
				t.truthy(w[1] >= -halfW - 1e-9 and w[2] <= halfW + 1e-9, "inside the box across")
				t.truthy(w[3] >= -halfH - 1e-9 and w[4] <= halfH + 1e-9, "inside the box front to back")
				local thin = math.min(w[2] - w[1], w[4] - w[3])
				t.near(thin, Boards.WALL, 1e-9, "every wall is one wall thick")
			end
			-- the frame: a point just inside each edge of the box is in wood, all the way round
			for i = 0, 200 do
				local x = -halfW + board.w * i / 200
				local y = -halfH + board.h * i / 200
				for _, p in { { x, -halfH + 0.01 }, { x, halfH - 0.01 }, { -halfW + 0.01, y }, { halfW - 0.01, y } } do
					local inWood = false
					for _, w in board.walls do
						if toWall(w, p[1], p[2]) == 0 then
							inWood = true
							break
						end
					end
					t.truthy(inWood, `{board.id}: the frame is open at {p[1]}, {p[2]}`)
				end
			end
			for _, hole in board.holes do
				for _, w in board.walls do
					t.truthy(toWall(w, hole.x, hole.y) >= hole.r + Boards.HOLE_GAP - 1e-9, "wood between rim and wall")
				end
				local cx, cy = Boards.cellCentre(board, hole.cell)
				t.truthy(math.abs(hole.x - cx) + hole.r < board.pitch / 2, "a hole lies inside its own cell")
				t.truthy(math.abs(hole.y - cy) + hole.r < board.pitch / 2)
				t.eq(Boards.cellOf(board, hole.x, hole.y), hole.cell)
			end
			for i, a in board.holes do
				for j, b in board.holes do
					if i < j then
						t.truthy(dist(a.x, a.y, b.x, b.y) > a.r + b.r, "holes do not run into each other")
					end
				end
			end
		end
	end)

	t.test("LAB-R1: one start, one finish, and a drawn line between them that a marble fits along", function()
		for _, board in Boards.ALL do
			local path, cells = board.path, board.pathCells
			t.truthy(#cells >= 10, "a real way round")
			t.eq(#path, #cells)
			t.eq(Boards.cellOf(board, board.start.x, board.start.y), cells[1], "the line starts at the start")
			t.eq(Boards.cellOf(board, board.finish.x, board.finish.y), cells[#cells], "and ends at the finish")
			t.eq(path[1][1], board.start.x)
			t.eq(path[#path][1], board.finish.x)
			t.eq(path[#path][2], board.finish.y)
			t.eq(board.hx[board.goal], board.finish.x, "the cup is the last hole of the physics")
			t.eq(board.hr[board.goal], board.finish.r)
			t.eq(board.goal, #board.holes + 1)
			local seen: { [number]: boolean } = {}
			for i, cell in cells do
				t.falsy(seen[cell], "the line never crosses itself")
				seen[cell] = true
				t.eq(board.cellAt[cell], i)
				t.eq(board.placeAt[cell], i)
				t.eq(Boards.cellOf(board, path[i][1], path[i][2]), cell, "each point of the line is in its cell")
				if i > 1 then
					-- consecutive cells are neighbours with no wall between them
					local d = cell - cells[i - 1]
					local bit = if d == 1 then 4 elseif d == -1 then 1 elseif d == board.cols then 8 else 2
					t.truthy(
						d == 1 or d == -1 or d == board.cols or d == -board.cols,
						"the line goes from a cell to the cell next door"
					)
					t.truthy(bit32.band(board.open[cell], bit) ~= 0, "through an open side")
					t.near(
						board.pathS[i] - board.pathS[i - 1],
						dist(path[i][1], path[i][2], path[i - 1][1], path[i - 1][2]),
						1e-12
					)
				end
			end
			-- all along the line a marble's centre is clear of every wall and of every rim
			for i = 2, #path do
				for k = 0, 10 do
					local x = path[i - 1][1] + (path[i][1] - path[i - 1][1]) * k / 10
					local y = path[i - 1][2] + (path[i][2] - path[i - 1][2]) * k / 10
					for _, w in board.walls do
						t.truthy(
							toWall(w, x, y) >= board.marbleR + 0.005,
							`{board.id}: the line scrapes a wall near point {i}`
						)
					end
					for _, hole in board.holes do
						t.truthy(
							dist(x, y, hole.x, hole.y) >= hole.r + 0.02,
							`{board.id}: the line crosses the rim of hole {hole.n} near point {i}`
						)
					end
				end
			end
		end
	end)

	t.test("LAB-R1 / R2: holes are numbered in the order the line passes them; checkpoints follow the line", function()
		for _, board in Boards.ALL do
			t.truthy(#board.holes >= 5, "holes to pass")
			for i, hole in board.holes do
				t.eq(hole.n, i, "numbered 1, 2, 3 ...")
				t.truthy(hole.at >= 1 and hole.at <= #board.pathCells)
				if i > 1 then
					t.truthy(hole.at >= board.holes[i - 1].at, "in the order the line passes them")
				end
				t.eq(hole.at, board.placeAt[hole.cell], "a hole belongs to the point of the line it lies off")
				t.eq(hole.onPath, board.cellAt[hole.cell] ~= 0)
			end
			t.eq(board.numberAt[1], 0, "no number at the start")
			t.eq(board.numberAt[#board.pathCells], #board.holes, "every number by the finish")
			for i = 2, #board.pathCells do
				t.truthy(board.numberAt[i] >= board.numberAt[i - 1], "numbers only go up along the line")
				t.truthy(board.checkpointAt[i] >= board.checkpointAt[i - 1])
			end
			local cps = board.checkpoints
			t.truthy(#cps >= 3, "the start and at least two checkpoints")
			t.eq(cps[1].x, board.start.x, "the first checkpoint is the start")
			t.eq(cps[1].y, board.start.y)
			t.eq(cps[1].n, 0)
			for i, cp in cps do
				t.eq(Boards.cellOf(board, cp.x, cp.y), cp.cell)
				t.eq(cp.n, board.numberAt[cp.at], "a checkpoint carries the number reached there")
				t.eq(board.checkpointAt[cp.at], i, "and is the checkpoint of its point of the line")
				for _, hole in board.holes do
					t.truthy(hole.cell ~= cp.cell, "a checkpoint never shares its cell with a hole")
					t.truthy(dist(cp.x, cp.y, hole.x, hole.y) > hole.r + board.marbleR, "nor sits by a rim")
				end
				for _, w in board.walls do
					t.truthy(
						toWall(w, cp.x, cp.y) > board.marbleR + 0.03,
						"a marble set down there is clear of the walls"
					)
				end
				if i > 1 then
					t.truthy(cp.at > cps[i - 1].at, "checkpoints come in the order of the line")
				end
			end
		end
	end)

	t.test("the boards rise in difficulty: more holes to the stud, board after board", function()
		local last = 0
		for _, board in Boards.ALL do
			local density = #board.holes / board.pathS[#board.pathS]
			t.truthy(density > last, `{board.id}: {density} holes to the stud of line (the board before: {last})`)
			last = density
		end
		t.truthy(#Boards.ALL[#Boards.ALL].holes >= 2 * #Boards.ALL[1].holes, "the last board has many more holes")
	end)

	t.test("C18: the physics lookups hold every wall and hole a marble in a cell could touch", function()
		for _, board in Boards.ALL do
			local rng = Rng.new(board.level)
			for cell = 1, board.cols * board.rows do
				local cx, cy = Boards.cellCentre(board, cell)
				local listed: { [number]: boolean } = {}
				for _, k in board.cellWalls[cell] do
					listed[k] = true
				end
				local holes: { [number]: boolean } = {}
				for _, k in board.cellHoles[cell] do
					holes[k] = true
				end
				for _ = 1, 40 do
					local x = cx + rng.range(-0.5, 0.5) * board.pitch
					local y = cy + rng.range(-0.5, 0.5) * board.pitch
					for k, w in board.walls do
						if toWall(w, x, y) < board.marbleR + 0.03 then
							t.truthy(listed[k], `{board.id} cell {cell}: wall {k} is within reach and not listed`)
						end
					end
					for k = 1, #board.hx do
						if dist(x, y, board.hx[k], board.hy[k]) < board.hr[k] then
							t.truthy(holes[k], `{board.id} cell {cell}: hole {k} is underfoot and not listed`)
						end
					end
				end
			end
			for k, w in board.walls do
				t.eq(board.wx0[k], w[1])
				t.eq(board.wx1[k], w[2])
				t.eq(board.wy0[k], w[3])
				t.eq(board.wy1[k], w[4])
			end
		end
	end)

	t.test("the picture is the board: redrawn from its geometry, the walls are the ones that were drawn", function()
		for i, board in Boards.ALL do
			local drawn = Boards.SOURCES[i].map
			local again = Boards.picture(board)
			t.eq(#again, #drawn)
			for line = 1, #drawn do
				if line % 2 == 1 then
					t.eq(again[line], drawn[line], `{board.id}: wall line {line}`)
				else
					for c = 0, board.cols do
						local at = c * 3 + 1
						t.eq(
							string.sub(again[line], at, at),
							string.sub(drawn[line], at, at),
							`{board.id}: line {line}`
						)
					end
				end
			end
		end
	end)

	t.test("a picture that is not a fair board is refused, with the reason", function()
		local good = Boards.SOURCES[1].map
		t.truthy(Boards.compile(Boards.SOURCES[1]).id == Boards.SOURCES[1].id, "the real one compiles")
		t.fails(function()
			Boards.compile(broken(1, string.sub(good[1], 1, -2)))
		end, "characters")
		t.fails(function()
			Boards.compile(broken(1, "+  " .. string.sub(good[1], 4)))
		end, "frame is open")
		t.fails(function()
			Boards.compile(broken(#good - 1, (string.gsub(good[#good - 1], "S", " "))))
		end, "one S and one F")
		t.fails(function()
			Boards.compile(broken(2, (string.gsub(good[2], " F", "5F"))))
		end, "cannot hold a hole")
		t.fails(function()
			Boards.compile(broken(2, (string.gsub(good[2], " F", " X"))))
		end, "not a mark")
		t.fails(function()
			Boards.compile(broken(2, (string.gsub(good[2], " F", "0F"))))
		end, "not a hole position")
		t.fails(function()
			-- wall the finish in
			local source = broken(2, "| F|" .. string.sub(good[2], 5))
			source.map[3] = "+--+" .. string.sub(good[3], 5)
			Boards.compile(source)
		end, "no way from the start to the finish")
		t.fails(function()
			local source = table.clone(Boards.SOURCES[1])
			source.map = table.move(good, 1, #good - 2, 1, {})
			Boards.compile(source)
		end, "lines")
	end)
end
