--!strict
-- tools/games/paintball/arena/ray: what a ball flown straight between two points of the arena stops on.
--   lune run tools/games/paintball/arena/ray.luau x0 y0 z0 x1 y1 z1      (arena frame; heights are absolute)
-- Prints the hit point, the face, and the box (its index, kind, look and bounds), or that the line is clear.
local process = require("@lune/process")
local Arena = require("../../../../src/shared/Minigames/Paintball/Arena")
local ArenaData = require("../../../../src/shared/Minigames/Paintball/ArenaData")
local ArenaDataPlan = require("../../../../src/shared/Minigames/Paintball/ArenaDataPlan")

local v: { number } = {}
for i = 1, 6 do
	v[i] = tonumber(process.args[i]) or error("six numbers: x0 y0 z0 x1 y1 z1")
end
local arena = ArenaData.build()
local plan = ArenaData.plan()
local s, nx, ny, nz, index = arena.sweep(v[1], v[2], v[3], v[4], v[5], v[6])
if s == nil then
	print("clear")
else
	local names: { [number]: string } = {}
	for name, code in Arena.KIND :: any do
		names[code] = name
	end
	local k = (index - 1) * 6
	local b = arena.boxes
	print(
		string.format(
			"stops at (%.2f, %.2f, %.2f), %.1f%% along, face (%d, %d, %d), on box %d: %s / %s, (%.2f, %.2f, %.2f) to (%.2f, %.2f, %.2f)",
			v[1] + (v[4] - v[1]) * s,
			v[2] + (v[5] - v[2]) * s,
			v[3] + (v[6] - v[3]) * s,
			s * 100,
			nx,
			ny,
			nz,
			index,
			names[arena.kinds[index]],
			ArenaDataPlan.LOOKS[plan.looks[index]],
			b[k + 1],
			b[k + 2],
			b[k + 3],
			b[k + 4],
			b[k + 5],
			b[k + 6]
		)
	)
end
