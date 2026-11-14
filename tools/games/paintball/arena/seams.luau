--!strict
-- tools/games/paintball/arena/seams: where two parts of the arena would flicker against each other in the engine.
--   lune run tools/games/paintball/arena/seams.luau
-- Prints every pair Flicker finds (two boxes of different looks with a face in one plane, one over the other, in
-- plain sight) with the looks and corners of both. A spec (paintball_arena_bake) holds the count at nothing.
local Arena = require("../../../../src/shared/Minigames/Paintball/Arena")
local ArenaData = require("../../../../src/shared/Minigames/Paintball/ArenaData")
local ArenaDataPlan = require("../../../../src/shared/Minigames/Paintball/ArenaDataPlan")
local Flicker = require("./Flicker")
local PartList = require("./PartList")

local plan = ArenaData.plan()
-- what stands outside against the building, in the arena's frame
local covers: { number } = {}
for _, p in PartList.dressing(nil) do
	local x0, y0, z1 = Arena.ofSite(p.x0, p.y0, p.d0)
	local x1, y1, z0 = Arena.ofSite(p.x1, p.y1, p.d1)
	for _, v in { x0, y0, z0, x1, y1, z1 } do
		table.insert(covers, v)
	end
end
local found = Flicker.find(plan, covers)
local b = plan.boxes
local function show(i: number): string
	local k = (i - 1) * 6
	local look = ArenaDataPlan.LOOKS[plan.looks[i]]
	return `{look} #{i} ({b[k + 1]}, {b[k + 2]}, {b[k + 3]}) .. ({b[k + 4]}, {b[k + 5]}, {b[k + 6]})`
end
for _, p in found do
	print(`{p.face} at {p.plane}, {string.format("%.2f", p.area)} sq: {show(p.a)}  |  {show(p.b)}`)
end
print(`seams: {#found} pairs of faces in one plane over one another`)
