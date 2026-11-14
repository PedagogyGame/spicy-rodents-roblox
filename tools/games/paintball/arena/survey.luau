--!strict
-- tools/games/paintball/arena/survey: the arena lane's own look at the building as data.
--   lune run tools/games/paintball/arena/survey.luau [--maps <dir>]
-- Prints what ArenaData.build() holds (boxes by kind, nodes and links by storey, cover spots) and how many parts
-- the bake makes of it, runs Arena.check,
-- times the build and the two queries, and with --maps writes one top-down picture a storey (<dir>/level<N>.ppm,
-- 4 pixels a stud: solids by height, nodes, links, cover spots, spawn points) for the eye.
local fs = require("@lune/fs")
local process = require("@lune/process")
local Arena = require("../../../../src/shared/Minigames/Paintball/Arena")
local ArenaData = require("../../../../src/shared/Minigames/Paintball/ArenaData")
local Contract = require("../../../../src/shared/Minigames/Paintball/Contract")
local NavBuild = require("./NavBuild")
local PartList = require("./PartList")
local Reach = require("./Reach")

local maps: string? = nil
for i, a in process.args do
	if a == "--maps" then
		maps = process.args[i + 1]
	end
end

local t0 = os.clock()
local arena = ArenaData.build()
local first = os.clock() - t0
t0 = os.clock()
ArenaData.build()
local again = os.clock() - t0
-- the graph the plan gives today; the game reads the baked copy of it
do
	local nodes, links, cover = NavBuild.compute()
	local baked = "src/shared/Minigames/Paintball/ArenaDataNavBaked.luau"
	if not fs.isFile(baked) or fs.readFile(baked) ~= NavBuild.text(nodes, links, cover) then
		print(
			"arena: THE BAKED GRAPH IS STALE: run tools/games/paintball/arena/bake_nav.luau (surveying the fresh one)"
		)
		arena.nodes, arena.links, arena.cover = nodes, links, cover
	end
end
local n = #arena.kinds
local byKind: { [number]: number } = {}
for _, k in arena.kinds do
	byKind[k] = (byKind[k] or 0) + 1
end
local names: { [number]: string } = {}
for name, code in Arena.KIND :: any do
	names[code] = name
end
local parts = {}
for code = 1, 7 do
	table.insert(parts, `{names[code]} {byKind[code] or 0}`)
end
print(`arena: {n} boxes ({table.concat(parts, ", ")}), {#arena.ramps} ramps`)
print(string.format("arena: first build %.0f ms, each later build %.1f ms", first * 1000, again * 1000))
-- what the bake makes of it: a part a box, a ramp, a curtain, and the dressing outside the volume
do
	local plan = ArenaData.plan()
	local solids, dressing = PartList.solids(plan), PartList.dressing(nil)
	local lights = 0
	for _, p in solids do
		if p.light then
			lights += 1
		end
	end
	for _, p in dressing do
		if p.light then
			lights += 1
		end
	end
	print(
		`arena: the bake is {#solids + #dressing} parts ({#solids} in the volume, {#dressing} of lobby and outside), {lights} lights, {#plan.signs} signs, {#plan.marks} marks`
	)
end
local perFloor: { [number]: number } = {}
for _, node in arena.nodes do
	perFloor[node.floor] = (perFloor[node.floor] or 0) + 1
end
local stairs = 0
for _, l in arena.links do
	if l.kind == "stair" then
		stairs += 1
	end
end
local counts = {}
for f = 0, Arena.FLOORS - 1 do
	table.insert(counts, tostring(perFloor[f] or 0))
end
print(
	`arena: {#arena.nodes} nodes ({table.concat(counts, ", ")} a storey), {#arena.links} links ({stairs} stair), {#arena.cover} cover spots`
)
local ok, problems = Arena.check(arena, Contract.Rules.teamMax)
print(`arena: Arena.check {if ok then "passes" else "FAILS"}`)
for _, p in problems do
	print(`  {p}`)
end

-- the queries' cost: a ball's step (1.5 studs) and a long look (60 studs), at random
local seed = 12345
local function rnd(): number
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end
local N = 20000
local pts = table.create(N * 3)
for i = 1, N * 3 do
	pts[i] = if i % 3 == 2 then rnd() * 70 else rnd() * 118 - 59
end
local function time(len: number, sweep: Arena.Sweep): number
	local t = os.clock()
	for i = 0, N - 2 do
		local k = i * 3
		local dx, dy, dz = pts[k + 4] - pts[k + 1], (pts[k + 5] - pts[k + 2]) * 0.2, pts[k + 6] - pts[k + 3]
		local d = math.sqrt(dx * dx + dy * dy + dz * dz)
		local s = len / math.max(d, 1e-6)
		sweep(pts[k + 1], pts[k + 2], pts[k + 3], pts[k + 1] + dx * s, pts[k + 2] + dy * s, pts[k + 3] + dz * s)
	end
	return (os.clock() - t) / (N - 1) * 1e6
end
local function reference(x0: number, y0: number, z0: number, x1: number, y1: number, z1: number)
	return Arena.sweepBoxes(arena.boxes, x0, y0, z0, x1, y1, z1)
end
print(
	string.format(
		"arena: sweep of a 1.5-stud step %.2f us (reference %.1f us); of 60 studs %.2f us (reference %.1f us)",
		time(1.5, arena.sweep),
		time(1.5, reference),
		time(60, arena.sweep),
		time(60, reference)
	)
)
do
	local t = os.clock()
	for i = 0, N - 1 do
		arena.ground(pts[i * 3 + 1], pts[i * 3 + 2], pts[i * 3 + 3])
	end
	print(string.format("arena: ground %.2f us", (os.clock() - t) / N * 1e6))
end

-- on foot
t0 = os.clock()
local reach = Reach.survey(arena)
print(
	string.format(
		"arena: %d places to stand, %d walked to from team 1's room (%s a storey); %d never reached; farthest from a node %.1f studs (%d over %d) [%.1f s]",
		reach.cells,
		reach.walked,
		table.concat(reach.perLevel, ", "),
		#reach.unreached,
		reach.farthest,
		#reach.far,
		Reach.FAR,
		os.clock() - t0
	)
)
for i = 1, math.min(8, #reach.unreached) do
	local p = reach.unreached[1 + (i - 1) * math.max(1, #reach.unreached // 8)]
	print(string.format("  never reached: (%.1f, %.1f, %.1f)", p[1], p[2], p[3]))
end
for i = 1, math.min(8, #reach.far) do
	local p = reach.far[1 + (i - 1) * math.max(1, #reach.far // 8)]
	print(string.format("  far from a node: (%.1f, %.1f, %.1f) %.1f studs", p[1], p[2], p[3], p[4]))
end

if maps then
	fs.writeDir(maps)
	local S = 4 -- pixels a stud
	local W = 124 * S
	for level = 0, Arena.FLOORS - 1 do
		local y = level * Arena.FLOOR_HEIGHT
		local img = buffer.create(W * W * 3)
		local function px(ix: number, iz: number, r: number, g: number, b: number)
			if ix >= 0 and ix < W and iz >= 0 and iz < W then
				local o = (iz * W + ix) * 3
				buffer.writeu8(img, o, r)
				buffer.writeu8(img, o + 1, g)
				buffer.writeu8(img, o + 2, b)
			end
		end
		for iz = 0, W - 1 do
			for ix = 0, W - 1 do
				local x, z = (ix + 0.5) / S - 62, (iz + 0.5) / S - 62
				-- what stands here, looking down from under the ceiling's furniture
				local s = arena.sweep(x, y + 7.5, z, x, y - 0.5, z)
				local r, g, b = 10, 10, 30 -- a void
				if s ~= nil then
					local h = 7.5 - s * 8
					if h < 0.05 then
						r, g, b = 200, 200, 190
					elseif h <= 1.3 then
						r, g, b = 150, 170, 200
					elseif h <= Arena.RAIL_HEIGHT + 0.05 then
						r, g, b = 220, 160, 60
					elseif h < 7.4 then
						r, g, b = 150, 90, 60
					else
						r, g, b = 60, 60, 60
					end
				end
				px(ix, iz, r, g, b)
			end
		end
		local function dot(x: number, z: number, size: number, r: number, g: number, b: number)
			local cx, cz = math.floor((x + 62) * S), math.floor((z + 62) * S)
			for dz = -size, size do
				for dx = -size, size do
					px(cx + dx, cz + dz, r, g, b)
				end
			end
		end
		for _, p in reach.unreached do
			if math.abs(p[2] - y) < 1.3 then
				dot(p[1], p[3], 1, 255, 60, 60)
			end
		end
		for _, l in arena.links do
			local a, b = arena.nodes[l.a], arena.nodes[l.b]
			if a.floor == level or b.floor == level then
				for k = 0, 40 do
					local t = k / 40
					local r, g = if l.kind == "stair" then 255 else 40, if l.kind == "stair" then 0 else 120
					dot(a.x + (b.x - a.x) * t, a.z + (b.z - a.z) * t, 0, r, g, 40)
				end
			end
		end
		for _, node in arena.nodes do
			if node.floor == level then
				if node.kind == "cover" then
					dot(node.x, node.z, 1, 200, 0, 200)
				elseif node.kind == "stair" then
					dot(node.x, node.z, 2, 255, 0, 0)
				else
					dot(node.x, node.z, 1, 0, 90, 255)
				end
			end
		end
		if level == Arena.SPAWN_FLOOR then
			for team = 1, 2 do
				for _, sp in arena.spawns[team] do
					dot(sp.x, sp.z, 2, if team == 1 then 255 else 0, 140, if team == 1 then 0 else 140)
				end
			end
		end
		fs.writeFile(`{maps}/level{level}.ppm`, `P6\n{W} {W}\n255\n` .. buffer.tostring(img))
	end
	print(`arena: maps in {maps}`)
end
