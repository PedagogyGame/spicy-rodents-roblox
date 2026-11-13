--!strict
-- tools/games/paintball/bots/calibrate.luau: how hard the paintball bots are, and whether they keep the
-- contract's rules of conduct, measured over whole headless matches (Sim, beside this file) at ball
-- speeds 90, 120 and 150, so that a faster ball can be judged at the owner's playtest without a new
-- calibration. For each speed it plays matches of one stand-in fair player (Sim.FAIR) and three bots
-- against four bots, every bot the AVERAGE bot (skill 0.5), and prints:
--   beats   how often the stand-in beats a bot: of all the tags between it and a bot, its share
--           (the target is about three in five), and below the table the same share by the range of
--           the tag. THE STAND-IN IS NOBODY'S MEASURED PLAYER: it is a brain with a person's numbers
--           (Sim.FAIR: a person's reaction, a narrower view, a steady hand at any range, a slower read
--           of a target's speed, the same misjudged drop and lead to walk in, none of a bot's
--           courtesies). The three in five is therefore UNVERIFIED until the owner's playtest; the
--           knob to turn there is the bots' skill (Contract.BOTS, or `skill=` here).
--   stuck   the longest any bot stood still, and how long the slowest took to leave its spawn room
--   camps   bot-seconds spent standing with a line to the other team's door; tags on somebody on
--           their own doorstep, and of those the ones a bot AIMED at somebody who had not fired (a
--           stray ball that such a body walked into is not counted there)
--   stairs  the largest share one flight has of its storey's traffic (not all up one stair), and the
--           bots' time on the least-used storey
--   facing  of the bots' tags, how many came from a bot that had faced its victim for BOT.faced
--   walls   times a bot followed an opponent through a wall (the audit)
--   cost    Bots.step with 15 bots (an 8 v 8 with one stand-in): mean milliseconds a tick, and the
--           share of ticks over the budget
-- Usage, from the repo root:
--   lune run tools/games/paintball/bots/calibrate.luau [matches a speed, default 10] [key=value ...] [greybox]
-- where each key is a Contract.FEEL number (fireInterval=0.3 reloadSecs=2 ...) or `skill`, the bots';
-- `greybox` plays in the lane's test building (Greybox, beside this file) instead of the game's own.
-- Interface: a script (prints a report); nothing is written.
local process = require("@lune/process")
local Contract = require("@shared/Minigames/Paintball/Contract")
local Rules = require("@shared/Minigames/Paintball/Rules")
local Greybox = require("./Greybox")
local Report = require("./Report")
local Sim = require("./Sim")

local matches = 10
local over: { [string]: number } = {}
local skill = 0.5
local greybox = false
for i, arg in process.args do
	local key, value = string.match(arg, "^(%a+)=([%d%.]+)$")
	if arg == "greybox" then
		greybox = true
	elseif key ~= nil and tonumber(value) ~= nil then
		if key == "skill" then
			skill = tonumber(value) :: number
		else
			over[key] = tonumber(value) :: number
		end
	elseif i == 1 and tonumber(arg) ~= nil then
		matches = math.max(1, math.floor(tonumber(arg) :: number))
	else
		print(`calibrate: did not understand '{arg}'`)
		process.exit(2)
	end
end

local SPEEDS = { 90, 120, 150 }

local function f(v: number, places: number?): string
	return string.format(`%.{places or 1}f`, v)
end

local arena = if greybox then Greybox.build() else nil
print(
	`PAINTBALL BOTS in {if greybox then "the lane's test building (Greybox)" else "the game's building (ArenaData)"}: `
		.. `{matches} matches a speed, 1 stand-in + 3 bots v 4 bots, every bot of skill {skill}`
)
local fair = Sim.FAIR
print(
	`the stand-in: reacts in {fair.reactMin} to {fair.reactMax} s, sees {f(math.deg(fair.sightHalf), 0)} degrees either side `
		.. `and 0.15 s late (its balls judged at what it saw), aim error {f(math.deg((fair.errLo + fair.errHi) / 2))} degrees `
		.. `at close range, standing, doubled at {fair.errFar} studs; first ball x{fair.first}; reads a speed over `
		.. `{fair.velLag} s; misjudges a new target's range by {f(fair.rangeSd * 100, 0)}% and lead by {f(
			fair.leadBias * 100,
			0
		)}%, `
		.. `walked in to {f(fair.walkIn * 100, 0)}% a ball`
)
print("(a stand-in, not a measured person: the three in five it is held to is unverified until the owner's playtest)")
print("")
print("  speed  beats a bot    tags  bot hit  stuck   room   camps  door tags  stair  least storey  facing   walls")
local started = os.clock()
for _, speed in SPEEDS do
	over.ballSpeed = speed
	local feel = Contract.feel(over)
	local tags, outs, all = 0, 0, 0
	local shots, hit = 0, 0
	local still, room, camping, doorTags, doorTrap, busiest, stares = 0, 0, 0, 0, 0, 0, 0
	local faced, facedOf = 0, 0
	local least = 1
	local unfinished = 0
	local byRange = { { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 } }
	local awards: { [string]: number } = {}
	for seed = 1, matches do
		local sim =
			Sim.new({ seed = seed, perSide = 4, people = 1, feel = feel, skill = skill, audit = true, arena = arena })
		Sim.run(sim)
		local s = Report.summary(sim)
		if not s.finished then
			unfinished += 1
		end
		tags += s.personTags
		outs += s.personOuts
		all += s.tags
		shots += s.shots
		hit += s.accuracy * s.shots
		still = math.max(still, s.still)
		room = math.max(room, s.roomSlowest)
		camping += s.camping
		doorTags += s.doorTags
		doorTrap += s.doorTrap
		busiest = math.max(busiest, s.stairBusiest)
		stares += s.stares
		faced += s.faced
		facedOf += s.facedOf
		for _, share in s.floorShare do
			least = math.min(least, share)
		end
		for i, b in s.personByRange do
			byRange[i][1] += b.tags
			byRange[i][2] += b.shots
		end
		for _, a in (Rules.card(sim.state)).awards do
			if sim.folkWho[a.id] ~= nil then
				awards[a.title] = (awards[a.title] or 0) + 1
			end
		end
	end
	print(
		string.format(
			"  %5d  %3.0f%% (%3d:%-3d) %5.0f  %6.1f%%  %4.1fs  %4.1fs  %5.1fs  %4.1f (%2d)  %4.0f%%  %11.0f%%  %5.1f%%  %6d%s",
			speed,
			if tags + outs > 0 then tags / (tags + outs) * 100 else 0,
			tags,
			outs,
			all / matches,
			if shots > 0 then hit / shots * 100 else 0,
			still,
			room,
			camping / matches,
			doorTags / matches,
			doorTrap,
			busiest * 100,
			least * 100,
			if facedOf > 0 then faced / facedOf * 100 else 0,
			stares,
			if unfinished > 0 then `  ({unfinished} did not finish)` else ""
		)
	)
	do
		local ranges = {}
		for i, label in { "under 20 studs", "20-40", "40-60", "over 60" } do
			local won, of = byRange[i][1], byRange[i][2]
			table.insert(ranges, `{label} {if of > 0 then f(won / of * 100, 0) else "-"}% of {of}`)
		end
		local got = {}
		for title, n in awards do
			table.insert(got, `{title} x{n}`)
		end
		table.sort(got)
		print(`         the stand-in's share by range: {table.concat(ranges, "; ")}`)
		print(`         its awards in {matches} matches: {if #got > 0 then table.concat(got, ", ") else "none"}`)
	end
end
print(
	"  (tags, camps and door tags are a match, with in brackets all the balls a bot aimed at a doorstep nobody had fired from;"
)
print("   stuck, room and stair are the worst of all the matches; walls is all of them together)")
print("")
-- the cost, with as many bots as the budget is written for
over.ballSpeed = SPEEDS[1]
local sim = Sim.new({ seed = 1, perSide = 8, people = 1, feel = Contract.feel(over), skill = skill, arena = arena })
local overBudget, ticks = 0, 0
while not sim.done do
	local before = sim.rec.botMs
	Sim.tick(sim)
	if sim.state.phase == "live" then
		ticks += 1
		if sim.rec.botMs - before > Contract.COST.botsMs then
			overBudget += 1
		end
	end
end
local s = Report.summary(sim)
print(
	string.format(
		"COST with %d bots (8 v 8, one stand-in): Bots.step %.3f ms a tick on average (budget %.1f ms), "
			.. "%.2f%% of ticks over it, worst %.2f ms; sight checks %d in the busiest second (cap %d), %d in the busiest tick",
		s.botCount,
		s.botMs,
		Contract.COST.botsMs,
		if ticks > 0 then overBudget / ticks * 100 else 0,
		s.botMsMax,
		s.sweepsSecond,
		s.sweepsCap,
		s.sweepsTick
	)
)
print(string.format("(simulated in %.0f s)", os.clock() - started))
