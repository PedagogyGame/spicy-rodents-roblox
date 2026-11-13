--!strict
-- tools/games/paintball/bots/match.luau: one whole paintball match of bots, played headless on the
-- arena's data with the real match model and the real bots (Sim, beside this file), and how it went
-- on one screen (Report): the end card, the bots' aim by range, target and ball, the storeys and
-- stairs they used, stand-stills, spawn rooms, call-outs, refused commands and the cost of Bots.step.
-- Usage, from the repo root:
--   lune run tools/games/paintball/bots/match.luau [seed, default 1] [a side, 4..8, default 4]
--       [people, default 0] [ball speed, default 90] [audit]
-- `people` seats that many stand-in fair players (Sim.FAIR) first; `audit` also looks for bots that
-- follow somebody through a wall (slower).
-- Interface: a script (prints a report); nothing is written.
local process = require("@lune/process")
local Contract = require("@shared/Minigames/Paintball/Contract")
local Report = require("./Report")
local Sim = require("./Sim")

local seed = tonumber(process.args[1]) or 1
local perSide = tonumber(process.args[2]) or 4
local people = tonumber(process.args[3]) or 0
local speed = tonumber(process.args[4]) or Contract.FEEL.ballSpeed
local audit = table.find(process.args, "audit") ~= nil

local started = os.clock()
local sim = Sim.new({
	seed = seed,
	perSide = perSide,
	people = people,
	feel = Contract.feel({ ballSpeed = speed }),
	audit = audit,
})
Sim.run(sim)
for _, line in Report.lines(sim) do
	print(line)
end
print(string.format("(simulated in %.1f s)", os.clock() - started))
