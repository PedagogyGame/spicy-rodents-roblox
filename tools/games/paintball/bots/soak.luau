--!strict
-- tools/games/paintball/bots/soak.luau: many whole paintball matches of bots, one after another, to
-- find the match that goes wrong. The specs pin a handful of seeds; this plays every size of team
-- (4 to 8 a side), with nobody, one or two stand-in fair players (Sim.FAIR), over a run of seeds, and
-- prints one line a match and, at the end, the worst of every conduct figure and the seed that gave
-- it. A match BREAKS A RULE when it does not finish, a team does not score, a command is refused, a
-- ball leaves inside the fire interval, a brain's body takes a step a person's would be refused, a
-- bot aims at somebody quiet on their own doorstep, a bot watches the other team's door, a bot stands
-- still for STILL seconds, a life takes ROOM seconds to leave its spawn room, a storey goes unused, one
-- flight carries more than STAIR of its storey pair's stair traffic, or a bot holds its fire for HELD
-- on somebody in plain view close by: those are counted, and the script exits 1 if there were any.
-- Usage, from the repo root:
--   lune run tools/games/paintball/bots/soak.luau [seeds a size, default 3] [first seed, default 101]
--       [ball speed, default 90] [greybox] [audit]
-- (five sizes x three kinds of company x the seeds: 45 matches by default, about two minutes.)
-- Interface: a script (prints a report; exit code 1 when a rule was broken); nothing is written.
local process = require("@lune/process")
local Contract = require("@shared/Minigames/Paintball/Contract")
local Greybox = require("./Greybox")
local Report = require("./Report")
local Sim = require("./Sim")

local STILL = 20 -- seconds: the longest a bot may stand in one place (the brain's own watch acts at 9)
local ROOM = 8 -- seconds: the longest a life may take to leave its spawn room
local STAIR = 0.66 -- the largest share one flight may have of its storey pair's stair traffic (PB-10)
local HELD = 2 -- seconds: the longest a bot may hold its fire on somebody in plain view close by

local numbers: { number } = {}
for _, arg in process.args do
	local n = tonumber(arg)
	if n ~= nil then
		table.insert(numbers, n)
	end
end
local seeds = math.max(1, math.floor(numbers[1] or 3))
local first = math.floor(numbers[2] or 101)
local speed = numbers[3] or Contract.FEEL.ballSpeed
local greybox = table.find(process.args, "greybox") ~= nil
local audit = table.find(process.args, "audit") ~= nil

type Worst = { value: number, where: string }
local worst: { [string]: Worst } = {}
local order: { string } = {}
local function note(key: string, value: number, where: string, least: boolean?)
	local had = worst[key]
	if had == nil then
		table.insert(order, key)
		worst[key] = { value = value, where = where }
	elseif (least and value < had.value) or (not least and value > had.value) then
		had.value, had.where = value, where
	end
end

local broken: { string } = {}
local started = os.clock()
local matches = 0
print(
	`PAINTBALL SOAK in {if greybox then "the lane's test building (Greybox)" else "the game's building (ArenaData)"}`
		.. `, ball {speed} studs/s: sizes 4 to 8, with 0, 1 and 2 stand-in people, {seeds} seed(s) each from {first}`
)
print("  match              score     tags  hit   still  room  storeys 1-5 (%)   stair  nose  legs  refused  ms/tick")
for perSide = Contract.Rules.teamMin, Contract.Rules.teamMax do
	for people = 0, 2 do
		for k = 0, seeds - 1 do
			local seed = first + k + perSide * 1000 + people * 100
			local where = `{perSide}v{perSide} people {people} seed {seed}`
			local sim = Sim.new({
				seed = seed,
				perSide = perSide,
				people = people,
				feel = Contract.feel({ ballSpeed = speed }),
				audit = audit,
				arena = if greybox then Greybox.build() else nil,
			})
			Sim.run(sim)
			local s = Report.summary(sim)
			matches += 1
			local floors = {}
			local least = 1
			for f, share in s.floorShare do
				floors[f] = string.format("%2d", math.floor(share * 100 + 0.5))
				least = math.min(least, share)
			end
			print(
				string.format(
					"  %-18s %3d - %-3d  %4d  %3d%%  %4.1fs %4.1fs  %s   %3d%%  %3d%%  %4d  %7d  %6.3f",
					where,
					s.scores[1],
					s.scores[2],
					s.tags,
					math.floor(s.accuracy * 100 + 0.5),
					s.still,
					s.roomSlowest,
					table.concat(floors, " "),
					math.floor(s.stairBusiest * 100 + 0.5),
					math.floor(s.noseShare * 100 + 0.5),
					s.legs,
					s.refused,
					s.botMs
				)
			)
			note("longest stand-still (s)", s.still, where)
			note("slowest out of a spawn room (s)", s.roomSlowest, where)
			note("least-used storey's share of the bots' time", least, where, true)
			note("busiest flight's share of its storey's traffic", s.stairBusiest, where)
			note("longest held fire on somebody in plain view (s)", s.held, where)
			note("crouched (share of the bots' time), least", s.crouchShare, where, true)
			note("look on a wall at a post (share)", s.noseShare, where)
			note("fewest tags by the losing side", math.min(s.scores[1], s.scores[2]), where, true)
			note(
				"most one-sided score (share of the tags)",
				math.max(s.scores[1], s.scores[2]) / math.max(1, s.tags),
				where
			)
			note("bots' hit rate, highest", s.accuracy, where)
			note("bots' hit rate, lowest", s.accuracy, where, true)
			note("tags on a doorstep", s.doorTags, where)
			note("Bots.step, mean ms a tick", s.botMs, where)
			note("sight checks in the busiest second, over the cap", s.sweepsSecond - s.sweepsCap, where)
			if s.facedOf > 0 then
				note("aimed tags by a bot that had faced its victim (share), lowest", s.faced / s.facedOf, where, true)
			end
			if people > 0 then
				note("the stand-in's share of its duels with bots, highest", s.personWin, where)
				note("the stand-in's share of its duels with bots, lowest", s.personWin, where, true)
			end
			if audit then
				note("times a bot followed somebody through a wall", s.stares, where)
			end
			local function rule(ok: boolean, what: string)
				if not ok then
					table.insert(broken, `{where}: {what}`)
				end
			end
			rule(s.finished, "the match did not finish")
			rule(s.scores[1] > 0 and s.scores[2] > 0, `a team did not score ({s.scores[1]} - {s.scores[2]})`)
			rule(s.refused == 0, `{s.refused} commands refused`)
			rule(s.tooSoon == 0, `{s.tooSoon} balls inside the fire interval`)
			rule(s.legs == 0, `{s.legs} steps a person's body would be refused ({sim.rec.legsFirst or "?"})`)
			rule(s.doorTrap == 0, `{s.doorTrap} balls aimed at somebody quiet on their doorstep`)
			rule(s.outTrap == 0, `{s.outTrap} balls aimed at somebody just out of their room who had not fired`)
			rule(s.camping == 0, `{s.camping} bot-seconds watching the other team's door`)
			rule(s.still < STILL, `seat {s.stillSlot} stood still for {string.format("%.1f", s.still)} s`)
			rule(s.roomSlowest < ROOM, `a life took {string.format("%.1f", s.roomSlowest)} s to leave its spawn room`)
			rule(least > 0, "a storey was never used")
			rule(
				s.stairBusiest <= STAIR,
				`one flight took {math.floor(s.stairBusiest * 100 + 0.5)}% of its storey's stair traffic`
			)
			rule(s.held < HELD, `a bot held its fire {s.held} s on somebody in plain view (seat {s.heldSlot})`)
			rule(s.sweepsSecond <= s.sweepsCap, `{s.sweepsSecond} sight checks in a second (cap {s.sweepsCap})`)
		end
	end
end
print("")
print(`THE WORST OF {matches} MATCHES`)
for _, key in order do
	local w = worst[key]
	print(string.format("  %-66s %8.3f   (%s)", key, w.value, w.where))
end
print("")
if #broken == 0 then
	print("RULES BROKEN: none")
else
	print(`RULES BROKEN: {#broken}`)
	for _, line in broken do
		print("  " .. line)
	end
end
print(string.format("(simulated in %.0f s)", os.clock() - started))
if #broken > 0 then
	process.exit(1)
end
