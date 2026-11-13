--!strict
-- tools/games/paintball/bots/Report.luau: what a headless paintball match (Sim, beside this file)
-- showed, as numbers a spec can pin (summary) and as one screen a person can read (lines). The
-- figures are the ones the paintball contract asks the match-and-bots lane to watch: both teams score,
-- nobody is stuck, nobody camps a spawn room or is tagged at its door, every storey and both stairs
-- of each are used, the bots miss more at range, at a moving target and with the first ball, a bot
-- has faced whoever it tags, and what Bots.step costs.
-- Interface: summary(sim) -> Summary; lines(sim, summary?) -> { string }; type Summary
local Contract = require("@shared/Minigames/Paintball/Contract")
local Rules = require("@shared/Minigames/Paintball/Rules")
local Sim = require("./Sim")

export type Band = { label: string, shots: number, tags: number, rate: number }

export type Summary = {
	finished: boolean,
	seconds: number, -- of the match's clock, briefing included
	scores: { number },
	text: string, -- the end banner ("" when not finished)
	shots: number,
	tags: number,
	accuracy: number, -- bots: tags over shots
	byRange: { Band }, -- bots' shots at a target, by range
	bySpeed: { Band }, -- by the target's speed
	byOrder: { Band }, -- the first ball at a target, the second, the rest
	facedOf: number, -- bot tags counted for the facing figure
	faced: number, -- of them, the bot had faced its victim for BOT.faced
	floorShare: { number }, -- bots' time in play by storey, 0..1
	stairPairs: { { number } }, -- by storey pair (1 = ground to first): the uses of each of its flights
	stairBusiest: number, -- the largest share one flight has of its storey pair's traffic
	still: number, -- the longest any bot stood still, seconds
	stillSlot: number,
	camping: number, -- bot-seconds spent watching the other team's door
	stares: number, -- times a bot followed somebody through a wall (audited matches only)
	roomSlowest: number, -- the longest any life took to leave its spawn room, seconds
	roomMean: number,
	doorTags: number, -- tags on somebody standing on their own doorstep (BotNav.atDoor)
	doorStray: number, -- of them, somebody who had not fired for 4 s, by a bot's ball fired at somebody else
	-- balls a bot fired AT somebody who was then on their own doorstep and had not fired for 4 s, tagged
	-- or not (a bot never does it)
	doorTrap: number,
	lives: number,
	coverShare: number, -- bots' time at a cover spot
	crouchShare: number,
	sprintShare: number,
	botMs: number, -- Bots.step, mean milliseconds a tick while live
	botMsMax: number,
	botCount: number,
	sweepsTick: number,
	sweepsSecond: number,
	sweepsCap: number, -- BOT.sightHz x the bots
	refused: number, -- commands the judge refused
	tooSoon: number,
	personTags: number, -- the stand-in people's tags on bots ...
	personOuts: number, -- ... and bots' tags on them
	personWin: number, -- personTags / (personTags + personOuts); 0 with no people
	personCompany: number, -- the share of the people's time in play with a bot of their own team near by
	botCompany: number, -- the same for the bots: how much a bot is near another of its team anyway
}

local Report = {}

local function band(label: string): Band
	return { label = label, shots = 0, tags = 0, rate = 0 }
end

local function add(b: Band, tagged: boolean)
	b.shots += 1
	if tagged then
		b.tags += 1
	end
	b.rate = b.tags / b.shots
end

function Report.summary(sim: Sim.Sim): Summary
	local rec = sim.rec
	local state = sim.state
	local arena = sim.arena
	local result = Rules.result(state)
	local byRange = { band("under 20 studs"), band("20 to 40"), band("40 to 60"), band("over 60") }
	local bySpeed = { band("standing"), band("walking"), band("sprinting") }
	local byOrder = { band("first ball"), band("second"), band("third on") }
	local botShots, botTagged = 0, 0
	local doorTrap = 0
	for _, shot in rec.shots do
		if not shot.bot then
			continue
		end
		botShots += 1
		if shot.tagged then
			botTagged += 1
		end
		if shot.trap then
			doorTrap += 1
		end
		if shot.target == nil then
			continue
		end
		local r = shot.range
		add(byRange[if r < 20 then 1 elseif r < 40 then 2 elseif r < 60 then 3 else 4], shot.tagged)
		add(bySpeed[if shot.speed < 4 then 1 elseif shot.speed < 20 then 2 else 3], shot.tagged)
		add(byOrder[math.min(3, math.max(1, shot.nth))], shot.tagged)
	end
	local facedOf, faced, doorTags, doorStray = 0, 0, 0, 0
	local personTags, personOuts = 0, 0
	for _, tag in rec.tags do
		if tag.byBot then
			facedOf += 1
			if tag.faced then
				faced += 1
			end
		end
		if tag.doorstep then
			doorTags += 1
			if tag.quiet and tag.byBot and tag.stray then
				doorStray += 1
			end
		end
		if not tag.byBot and tag.idBot then
			personTags += 1
		elseif tag.byBot and not tag.idBot then
			personOuts += 1
		end
	end
	local floorTime: { number } = table.create(arena.floors, 0)
	local play, cover, crouched, sprinted = 0, 0, 0, 0
	local still, stillSlot, camping, stares = 0, 0, 0, 0
	local roomSlowest, roomSum, lives = 0, 0, 0
	local botCount = 0
	local personPlay, personCompany, botCompany = 0, 0, 0
	for id, rs in rec.slots do
		if not rs.bot then
			personPlay += rs.play
			personCompany += rs.company
			continue
		end
		botCompany += rs.company
		botCount += 1
		play += rs.play
		cover += rs.atCover
		crouched += rs.crouched
		sprinted += rs.sprinted
		camping += rs.camping
		stares += rs.stares
		for f = 1, arena.floors do
			floorTime[f] += rs.floors[f]
		end
		if rs.still > still then
			still, stillSlot = rs.still, id
		end
		for _, life in rs.lives do
			local left = life.leftRoom
			local from = math.max(life.from, state.liveAt)
			if left ~= nil then
				lives += 1
				roomSum += left - from
				roomSlowest = math.max(roomSlowest, left - from)
			elseif life.ended == nil and state.phase ~= "briefing" then
				-- still in the room when the match ended: counted as long as it lasted
				local upTo = if state.phase == "ended" then state.endsAt - Contract.Rules.endCardSecs else sim.now
				roomSlowest = math.max(roomSlowest, upTo - from)
			end
		end
	end
	local floorShare: { number } = table.create(arena.floors, 0)
	for f = 1, arena.floors do
		floorShare[f] = if play > 0 then floorTime[f] / play else 0
	end
	local stairPairs: { { number } } = {}
	for f = 1, arena.floors - 1 do
		stairPairs[f] = {}
	end
	local busiest = 0
	for index, link in arena.links do
		if link.kind == "stair" then
			local a, b = arena.nodes[link.a], arena.nodes[link.b]
			local low = math.min(a.floor, b.floor) + 1
			if stairPairs[low] ~= nil then
				table.insert(stairPairs[low], rec.stairs[index] or 0)
			end
		end
	end
	for _, uses in stairPairs do
		local total, most = 0, 0
		for _, n in uses do
			total += n
			most = math.max(most, n)
		end
		if total > 0 then
			busiest = math.max(busiest, most / total)
		end
	end
	local refused = 0
	for _, n in rec.refused do
		refused += n
	end
	local ended = state.phase == "ended"
	return {
		finished = ended and result ~= nil,
		seconds = (if ended then state.endsAt - Contract.Rules.endCardSecs else sim.now) - sim.start,
		scores = { state.scores[1], state.scores[2] },
		text = if result ~= nil then result.text else "",
		shots = botShots,
		tags = #rec.tags,
		accuracy = if botShots > 0 then botTagged / botShots else 0,
		byRange = byRange,
		bySpeed = bySpeed,
		byOrder = byOrder,
		facedOf = facedOf,
		faced = faced,
		floorShare = floorShare,
		stairPairs = stairPairs,
		stairBusiest = busiest,
		still = still,
		stillSlot = stillSlot,
		camping = camping,
		stares = stares,
		roomSlowest = roomSlowest,
		roomMean = if lives > 0 then roomSum / lives else 0,
		doorTags = doorTags,
		doorTrap = doorTrap,
		doorStray = doorStray,
		lives = lives,
		coverShare = if play > 0 then cover / play else 0,
		crouchShare = if play > 0 then crouched / play else 0,
		sprintShare = if play > 0 then sprinted / play else 0,
		botMs = if rec.ticks > 0 then rec.botMs / rec.ticks else 0,
		botMsMax = rec.botMsMax,
		botCount = botCount,
		sweepsTick = rec.sweepsMax,
		sweepsSecond = rec.sweepsSecond,
		sweepsCap = Contract.BOT.sightHz * botCount,
		refused = refused,
		tooSoon = rec.firedTooSoon,
		personTags = personTags,
		personOuts = personOuts,
		personWin = if personTags + personOuts > 0 then personTags / (personTags + personOuts) else 0,
		personCompany = if personPlay > 0 then personCompany / personPlay else 0,
		botCompany = if play > 0 then botCompany / play else 0,
	}
end

local function pct(v: number): string
	return string.format("%.0f%%", v * 100)
end

local function bands(list: { Band }): string
	local out = {}
	for _, b in list do
		table.insert(out, `{b.label} {pct(b.rate)} of {b.shots}`)
	end
	return table.concat(out, "; ")
end

-- The match on one screen.
function Report.lines(sim: Sim.Sim, given: Summary?): { string }
	local s = given or Report.summary(sim)
	local state = sim.state
	local feel = state.feel
	local out: { string } = {}
	local function say(text: string)
		table.insert(out, text)
	end
	local seats = sim.session.names
	local perSide = 0
	for _, slot in state.slots do
		if slot.on and slot.team == 1 then
			perSide += 1
		end
	end
	say(
		`PAINTBALL {perSide} v {perSide}, seed {sim.opts.seed or 1}: ball {feel.ballSpeed} studs/s, drop {feel.ballDrop}, `
			.. `one ball every {feel.fireInterval} s, reload {feel.reloadSecs} s, back in {feel.respawnSecs} s`
	)
	if s.finished then
		say(`{s.text} when the clock ran out at {string.format("%.0f", s.seconds)} s. {s.tags} tags, {s.lives} lives.`)
	else
		say(
			`NOT FINISHED: phase {state.phase} at {string.format("%.0f", s.seconds)} s, `
				.. `{Contract.TEAMS[1].name} {s.scores[1]} - {s.scores[2]} {Contract.TEAMS[2].name}`
		)
	end
	say("")
	say("  seat  who                  side    tags outs balls  hit   storeys 1-5 (% of time)   cover still  walked")
	local card = Rules.card(state)
	for _, row in card.rows do
		local rs = sim.rec.slots[row.id]
		local who = (seats[row.id] or "?") .. (if rs ~= nil and not rs.bot then " (stand-in)" else "")
		local floors = {}
		if rs ~= nil then
			for f, secs in rs.floors do
				floors[f] = string.format("%3.0f", if rs.play > 0 then secs / rs.play * 100 else 0)
			end
		end
		say(
			string.format(
				"  %4d  %-20s %-7s %4d %4d %5d %4s   %s   %5s %4.0fs %6.0f",
				row.id,
				who,
				Contract.TEAMS[row.team].name,
				row.tags,
				row.outs,
				row.shots,
				pct(row.accuracy),
				table.concat(floors, " "),
				if rs ~= nil and rs.play > 0 then pct(rs.atCover / rs.play) else "-",
				if rs ~= nil then rs.still else 0,
				if rs ~= nil then rs.walked else 0
			)
		)
	end
	local awards = {}
	for _, a in card.awards do
		table.insert(awards, `{a.title}: {seats[a.id] or a.id}`)
	end
	say("  awards: " .. table.concat(awards, "; "))
	say("")
	say(`BOTS' AIM ({s.shots} balls, {pct(s.accuracy)} tagged their target)`)
	say("  by range:  " .. bands(s.byRange))
	say("  by target: " .. bands(s.bySpeed))
	say("  by ball:   " .. bands(s.byOrder))
	say(
		`  facing: {s.faced} of {s.facedOf} bot tags came from a bot that had its victim in view for `
			.. `{Contract.BOT.faced} s before the ball`
	)
	say("THE BUILDING")
	local shares = {}
	for f, v in s.floorShare do
		shares[f] = pct(v)
	end
	say("  bots' time by storey (1-5): " .. table.concat(shares, " "))
	local stairs = {}
	for f, uses in s.stairPairs do
		table.insert(stairs, `{f}-{f + 1}: {table.concat(uses, "/")}`)
	end
	say(
		`  stairs used, each flight: {table.concat(stairs, "  ")}  (busiest flight {pct(s.stairBusiest)} of its storey's)`
	)
	say(
		`  at cover {pct(s.coverShare)} of the time, crouched {pct(s.crouchShare)}, sprinting {pct(s.sprintShare)}; `
			.. `longest stand-still {string.format("%.1f", s.still)} s (seat {s.stillSlot})`
	)
	say(
		`  spawn rooms: out in {string.format("%.1f", s.roomMean)} s on average, {string.format("%.1f", s.roomSlowest)} s at the slowest; `
			.. `{s.doorTags} tagged on their own doorstep ({s.doorStray} of them quiet, by a ball meant for somebody else); `
			.. `balls a bot fired at somebody quiet on their doorstep: {s.doorTrap}; `
			.. `{string.format("%.1f", s.camping)} bot-seconds watching a door`
	)
	if sim.opts.audit then
		say(`  followed somebody through a wall: {s.stares} times`)
	end
	local calls = {}
	for line, n in sim.rec.says do
		local words = (Contract.LINES :: { [string]: string })[line] or line
		table.insert(calls, `{(string.gsub(words, "%%d", "N"))} x{n}`)
	end
	table.sort(calls)
	say("  call-outs: " .. (if #calls > 0 then table.concat(calls, ", ") else "none"))
	if s.personTags + s.personOuts > 0 then
		say(
			`THE STAND-IN PLAYER tagged a bot {s.personTags} times and was tagged by one {s.personOuts} times: `
				.. `it wins {pct(s.personWin)} of its exchanges`
		)
		say(
			`  a bot of its own team was near it {pct(s.personCompany)} of the time `
				.. `(a bot has another near it {pct(s.botCompany)} of the time)`
		)
	end
	local refused = {}
	for key, n in sim.rec.refused do
		table.insert(refused, `{key} x{n}`)
	end
	table.sort(refused)
	say(
		`RULES: commands refused: {if #refused > 0 then table.concat(refused, ", ") else "none"}; `
			.. `balls fired inside the fire interval: {s.tooSoon}`
	)
	say(
		string.format(
			"COST: Bots.step %.3f ms a tick on average, %.2f ms at worst, for %d bots (budget %.1f ms at %d); "
				.. "sight checks: %d in the busiest tick, %d in the busiest second (cap %d)",
			s.botMs,
			s.botMsMax,
			s.botCount,
			Contract.COST.botsMs,
			Contract.COST.atBots,
			s.sweepsTick,
			s.sweepsSecond,
			s.sweepsCap
		)
	)
	return out
end

return Report
