--!strict
-- tools/sim/wall_audit: the long run of tests/lib/WallAudit (tests/unit/town_walls.spec runs 24 simulated minutes of
-- it in CI): the whole town AI on the baked town, with a player biting, police calls and bodies left anywhere, every
-- step of every computer-run body tested against the town's walls; then the yard dogs by day and at night. Prints
-- each run's report (each crossing with the brain and the leg that moved the body, its last steps, and the order's
-- caller) and exits 1 when any run crossed a wall.
--
-- Usage (repo root; bake first: lune run tools/bake/main.luau, attractions.luau and the expansion bakes):
--   lune run tools/sim/wall_audit.luau                       4 seeds x 30 simulated minutes, near and far
--   lune run tools/sim/wall_audit.luau --seeds 1,2 --minutes 10 --far
local process = require("@lune/process")
local Data = require("@shared/Data")
local WallAudit = require("@tests/lib/WallAudit")

local seeds = { 1, 2, 3, 4 }
local minutes = 30
local modes = { true, false } -- near (a player by the rodent: brains at 10 Hz), far (1 Hz)
local i = 1
local args = process.args
while i <= #args do
	local a = args[i]
	if a == "--seeds" then
		seeds = {}
		for _, s in string.split(args[i + 1], ",") do
			table.insert(seeds, tonumber(s) :: number)
		end
		i += 1
	elseif a == "--minutes" then
		minutes = tonumber(args[i + 1]) :: number
		i += 1
	elseif a == "--near" then
		modes = { true }
	elseif a == "--far" then
		modes = { false }
	else
		print(`wall_audit: unknown option {a} (--seeds 1,2 --minutes N --near|--far)`)
		process.exit(2)
	end
	i += 1
end

WallAudit.TRAILS = true
local town = WallAudit.load()
if #town.missing > 0 then
	print(`wall_audit: not baked: {table.concat(town.missing, ", ")}`)
	process.exit(2)
end
local data = Data.default()
local crossings, steps = 0, 0
for _, seed in seeds do
	for _, near in modes do
		local t0 = os.clock()
		local r = WallAudit.run(town, data, { seed = seed, minutes = minutes, near = near })
		print(`== seed {seed}, {minutes} min, {if near then "near" else "far"} ({math.floor(os.clock() - t0)} s)`)
		print(WallAudit.format(r))
		crossings += r.crossings
		steps += r.steps
	end
end
for _, night in { false, true } do
	local r = WallAudit.dogs(town, minutes, night)
	print(`== yard dogs, {minutes} min, {if night then "night" else "day"}`)
	print(WallAudit.format(r))
	crossings += r.crossings
	steps += r.steps
end
print(`wall_audit: {steps} steps, {crossings} wall crossings`)
process.exit(if crossings == 0 then 0 else 1)
