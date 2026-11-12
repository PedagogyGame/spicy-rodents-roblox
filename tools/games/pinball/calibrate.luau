--!strict
-- tools/games/pinball/calibrate.luau: a developer's look at the pinball model (Shared/Minigames/Pinball) so the
-- tables are tuned from numbers, not guesses. For each of the three machines it prints:
--   * dead spots: places a ball comes to rest by itself with the flippers down, and balls that never drain
--     (Survey; both must be none);
--   * the flipper: stroke and fall time, how far it comes back off its top stop, how hard it hits a ball met
--     in mid-stroke (the same wherever inside a tick the two meet), the shot table (where the ball is on the
--     flipper when you flip against the angle and speed it leaves at: checklist PIN-P1 asks for it to rise
--     steadily), and the live catch tick by tick (PIN-P2: how wide the moment is);
--   * the plunger: with nobody at the flippers, the first thing the ball does after each strength of pull
--     (the skill shot is the band that pays; too soft a pull does not leave the lane);
--   * the computer players, NOVICE, REGULAR and WIZARD: scores (and where each would stand on the machine's
--     board of best scores), how long a ball lasts, flips, what gets hit a game, how often each goal on the
--     rule sheet is reached, where balls are lost;
--   * what a step costs.
-- Usage, from the repo root: lune run tools/games/pinball/calibrate.luau [games per level, default 40] [table id part]
-- Interface: a script (prints a report); nothing is written.

local process = require("@lune/process")
local Bot = require("../../../src/shared/Minigames/Pinball/Bot")
local HighScores = require("../../../src/shared/Minigames/Pinball/HighScores")
local Layout = require("../../../src/shared/Minigames/Pinball/Layout")
local Machine = require("../../../src/shared/Minigames/Pinball/Machine")
local Physics = require("../../../src/shared/Minigames/Pinball/Physics")
local Shots = require("../../../src/shared/Minigames/Pinball/Shots")
local Survey = require("../../../src/shared/Minigames/Pinball/Survey")
local Tables = require("../../../src/shared/Minigames/Pinball/Tables")

local GAMES = tonumber(process.args[1]) or 40
local ONLY = process.args[2]
local ONLY_SHOTS = process.args[3] == "shots"

local CUE, BTN, PHASE = Machine.CUE, Machine.BTN, Machine.PHASE
local CUE_NAMES: { [number]: string } = {}
for name, code in Machine.CUE :: { [string]: number } do
	CUE_NAMES[code] = name
end

local function fmt(v: number, places: number?): string
	return string.format(`%.{places or 1}f`, v)
end

local function commas(v: number): string
	local s = tostring(math.floor(v + 0.5))
	local out = ""
	while #s > 3 do
		out = "," .. string.sub(s, -3) .. out
		s = string.sub(s, 1, -4)
	end
	return s .. out
end

local function flipperReport(tbl: Machine.Table)
	local c = tbl.c
	local ev: { number } = {}
	local s = Physics.new(c, 1)
	local up = 0
	while s.fa[1] < c.fup[1] and up < 200 do
		Physics.step(c, s, true, false, ev)
		up += 1
	end
	-- off the stop again: how far it comes back and how long it is coming home
	local back, away = 0, 0
	for _ = 1, 60 do
		Physics.step(c, s, true, false, ev)
		if s.fa[1] < c.fup[1] then
			away += 1
			back = math.max(back, math.deg(c.fup[1] - s.fa[1]))
		end
	end
	local down = 0
	while s.fa[1] > c.frest[1] and down < 400 do
		Physics.step(c, s, false, false, ev)
		down += 1
	end
	print(
		`  flipper: stroke {fmt(up / 240 * 1000, 0)} ms, fall {fmt(down / 240 * 1000, 0)} ms, swing {fmt(
			math.deg(c.fup[1] - c.frest[1]),
			0
		)} degrees, tip speed {fmt(Physics.FLIP_W_MAX * c.freach[1])} studs/s; at the top it comes {fmt(back)} degrees back off its stop and is home in {fmt(
			away / 240 * 1000,
			0
		)} ms`
	)

	-- a ball met in mid-stroke: dropped from a hair higher each time, it meets the flipper at every point
	-- inside a tick in turn; it must leave as fast each time
	local mid = (c.frest[1] + c.fup[1]) / 2
	local mx, my = c.fpx[1] + math.cos(mid) * c.flen[1] * 0.7, c.fpy[1] + math.sin(mid) * c.flen[1] * 0.7
	local slow, fast = math.huge, 0
	for k = 0, 79 do
		local p = Physics.new(c, 1)
		Physics.addBall(p, mx, my + 0.22 + k * 0.0011, 0, -3)
		local b = p.balls[1]
		local met = 0
		for tick = 1, 60 do
			table.clear(ev)
			Physics.step(c, p, true, false, ev)
			for i = 1, #ev, 4 do
				if ev[i] == Physics.EV.FLIPPER and met == 0 then
					met = tick
				end
			end
			if met > 0 and tick == met + 6 then
				local speed = math.sqrt(b.vx * b.vx + b.vy * b.vy)
				slow, fast = math.min(slow, speed), math.max(fast, speed)
				break
			end
		end
	end
	table.clear(ev)
	print(
		`  a ball falling at 3 studs/s met in mid-stroke, 0.7 of the way out (surface {fmt(
			Physics.FLIP_W_MAX * c.flen[1] * 0.7
		)} studs/s): it leaves at {fmt(slow)} to {fmt(fast)} studs/s, wherever inside a tick the two meet`
	)

	-- the shot curve: a cradled ball is let go and flipped after a delay (from the shot book's trials)
	local trials = Shots.book(tbl).trials[1]
	print(
		"  shot curve, left flipper (ball let go from a cradle; angle from straight up, + across the table; one row every tenth of the flipper):"
	)
	print("    flip after   ball at   angle   speed   a tick later the angle is")
	local nextAt = 0
	local steady, worst = true, 0
	for n, tr in trials do
		if tr.angle ~= tr.angle or tr.along < 0 or tr.along > 1 then
			continue
		end
		local after = trials[n + 1]
		local step = if after and after.angle == after.angle then after.angle - tr.angle else 0
		if step < -0.3 then
			steady = false
		end
		worst = math.max(worst, step)
		if tr.along >= nextAt then
			nextAt += 0.1
			print(
				string.format(
					"    %4.0f ms    %5.2f    %+6.1f   %5.1f   %+.2f degrees on",
					tr.delay / 240 * 1000,
					tr.along,
					tr.angle,
					tr.speed,
					step
				)
			)
		end
	end
	print(
		`    the angle rises steadily with the ball's place on the flipper: {if steady then "yes" else "NO"}; the largest step from one tick to the next is {fmt(
			worst,
			2
		)} degrees`
	)

	-- live catch: how far the ball hops off the raised flipper's face after landing on it
	local upAngle = c.fup[1]
	local nx, ny = -math.sin(upAngle), math.cos(upAngle)
	local function hop(flipAt: number): (number, number)
		local p = Physics.new(c, 1)
		local i = Physics.addBall(p, c.fpx[1] + 0.2, 2.2, 0, 0)
		local b = p.balls[i]
		local landed, high = 0, 0
		for tick = 1, 420 do
			local vy = b.vy
			Physics.step(c, p, tick >= flipAt, false, ev)
			if landed == 0 then
				if b.vy > vy + 0.5 then
					landed = tick
				end
			elseif tick <= landed + 60 and b.mode == Physics.FREE then
				high = math.max(high, (b.x - c.fpx[1]) * nx + (b.y - c.fpy[1]) * ny - Layout.BALL_R - c.frb[1])
			end
		end
		return high, landed
	end
	local held, landsAt = hop(1)
	local parts = {}
	local window, first, last = 0, 0, 0
	for flipAt = landsAt - 26, landsAt - 6 do
		local high = hop(flipAt)
		table.insert(parts, `{flipAt - landsAt}: {fmt(high / held * 100, 0)}%`)
		if high < held / 2 then
			window += 1
			first = if first == 0 then flipAt - landsAt else first
			last = flipAt - landsAt
		end
	end
	print(
		`  live catch (a ball dropped on the flipper hops {fmt(held, 2)} studs off it when it is held; flipped so many ticks before the ball lands, the hop is):`
	)
	print("    " .. table.concat(parts, "  "))
	print(
		if window > 0
			then `    the catch (under half the hop): {window} ticks ({fmt(window / 240 * 1000, 0)} ms), flipping {-first} to {-last} ticks ahead; earlier is a held flipper, later is a hit`
			else "    NO live catch at this spot"
	)
end

local function surveyReport(tbl: Machine.Table)
	local report = Survey.rests(tbl, 1)
	local where = {}
	for i = 1, math.min(#report.rest, 12), 2 do
		table.insert(where, string.format("%.2f, %.2f", report.rest[i], report.rest[i + 1]))
	end
	for i = 1, math.min(#report.moving, 12), 2 do
		table.insert(where, string.format("never drains from %.2f, %.2f", report.moving[i], report.moving[i + 1]))
	end
	print(
		`  dead spots (a ball let go at each of {report.tried} spots it can reach, flippers down): {#report.rest // 2} where it comes to rest by itself, {#report.moving // 2} that never drain; the slowest drain took {fmt(
			report.slowest
		)} s{if #where > 0 then " !! " .. table.concat(where, "; ") else ""}`
	)
end

local function shotsReport(tbl: Machine.Table)
	local book = Shots.book(tbl)
	print(
		`  shot book (a cradled ball let go and flipped after every delay in turn; a window is how many ticks in a row reach the same thing; {Shots.FAIR_TICKS} ticks, two screen frames, is a fair shot):`
	)
	for i = 1, tbl.c.nFlip do
		local rows = {}
		for _, kk in book.keys do
			local w = book.windows[i][kk]
			if w and w.ticks >= 2 then
				table.insert(
					rows,
					string.format(
						"%s %d ticks (%.0f ms) at %.2f, %+.0f deg, %.0f st/s",
						Shots.name(tbl, kk),
						w.ticks,
						w.ticks / 240 * 1000,
						w.along,
						w.angle,
						w.speed
					)
				)
			end
		end
		print(`    {tbl.def.flippers[i].id}: {table.concat(rows, "; ")}`)
	end
end

local function plungerReport(tbl: Machine.Table)
	local p = tbl.def.plunger
	print(
		`  plunger (full pull {fmt(p.pullTicks / 240, 2)} s; launch {p.vMin} to {p.vMax} studs/s; nobody at the flippers: the first thing the ball does on its way down):`
	)
	local out: { number } = {}
	local line = {}
	for step = 1, 20 do
		local pull = step / 20
		local m = Machine.new(tbl, 11, 1)
		local hold = math.floor(pull * p.pullTicks + 0.5)
		for k = 1, hold + 1 do
			Machine.step(tbl, m, if k <= hold then BTN.PLUNGE else 0, out)
		end
		table.clear(out)
		-- nobody at the flippers: the first switch the ball makes on its way down, in ten seconds
		local NONE = ""
		local first = NONE
		local skill = false
		local launched = false
		for _ = 1, 2400 do
			Machine.step(tbl, m, 0, out)
			launched = launched or m.launched
			for i = 1, #out, 3 do
				local cue = out[i]
				if cue == CUE.JINGLE and m.skillLeft == 0 and not skill and first == NONE then
					skill = true
				end
				if first == NONE then
					if cue == CUE.ROLLOVER then
						first = tbl.def.sensors[out[i + 1]].id
					elseif cue == CUE.BUMPER then
						first = "bumper"
					elseif cue == CUE.SLING then
						first = "sling"
					elseif cue == CUE.STANDUP or cue == CUE.DROP then
						first = tbl.def.targets[out[i + 1]].id
					elseif cue == CUE.SAUCER then
						first = tbl.def.saucers[out[i + 1]].id
					elseif cue == CUE.FLIPPER_HIT then
						first = "flipper"
					end
				end
				if
					cue == CUE.SAY
					and out[i + 1] >= 101
					and string.find(tbl.sheet.text[out[i + 1]], "SHOT", 1, true)
				then
					skill = true
				end
			end
			table.clear(out)
			if m.phase ~= PHASE.PLAY or first ~= NONE then
				break
			end
		end
		if first == NONE then
			first = if launched
				then "out of the lane and down the table past everything"
				else "not out of the lane: back to the plunger"
		end
		table.insert(line, `    pull {fmt(pull, 2)} -> {first}{if skill then "  ** SKILL SHOT **" else ""}`)
	end
	print(table.concat(line, "\n"))
	print(`  the wizard's lesson: plunge at {fmt(Bot.learn(tbl).pull, 2)} of a full pull`)
end

type Tally = { [string]: number }

local function gamesReport(tbl: Machine.Table)
	print(`  computer players, {GAMES} one-player games each ({tbl.sheet.scoreScale}):`)
	for level = 1, #Bot.LEVELS do
		local scores: { number } = {}
		local ticks, balls, flips, plays = 0, 0, 0, 0
		local cues: Tally = {}
		local says: Tally = {}
		local gamesWith: Tally = {}
		local lost: Tally = { centre = 0, left = 0, right = 0 }
		local clock = 0
		for seed = 1, GAMES do
			local m = Machine.new(tbl, seed, 1)
			local bot = Bot.new(level, seed * 977 + level)
			local out: { number } = {}
			local seen: { [string]: boolean } = {}
			local started = os.clock()
			local n = 0
			while m.phase ~= PHASE.OVER and n < 240 * 60 * 60 do
				Machine.step(tbl, m, Bot.step(bot, tbl, m), out)
				n += 1
				if m.phase == PHASE.PLAY and m.launched then
					plays += 1
				end
				for i = 1, #out, 3 do
					local cue = out[i]
					local name = CUE_NAMES[cue]
					cues[name] = (cues[name] or 0) + 1
					if cue == CUE.SAY then
						local text = tbl.sheet.text[out[i + 1]] or Machine.TEXT[out[i + 1]]
						says[text] = (says[text] or 0) + 1
						seen[text] = true
					elseif cue == CUE.DRAIN then
						local x = out[i + 2]
						local where = if x < tbl.def.flippers[1].x
							then "left"
							elseif x > tbl.def.flippers[2].x then "right"
							else "centre"
						lost[where] += 1
					elseif cue == CUE.FLIP_UP then
						flips += 1
					end
				end
				table.clear(out)
			end
			clock += os.clock() - started
			if m.phase ~= PHASE.OVER then
				print(`    !! seed {seed}: the game did not end in an hour`)
			end
			for text in seen do
				gamesWith[text] = (gamesWith[text] or 0) + 1
			end
			ticks += n
			balls += m.stats[1].balls
			table.insert(scores, m.scores[1])
		end
		table.sort(scores)
		local sum = 0
		for _, v in scores do
			sum += v
		end
		local median = scores[(#scores + 1) // 2]
		local board = HighScores.new(tbl.id)
		local onBoard = 0
		for _, v in scores do
			if HighScores.place(board, v) then
				onBoard += 1
			end
		end
		local place = HighScores.place(board, median)
		print(
			`    {Bot.NAMES[level]}: median {commas(median)}, quartiles {commas(scores[(#scores + 3) // 4])} and {commas(
				scores[(3 * #scores + 1) // 4]
			)}, mean {commas(sum / #scores)}, best {commas(scores[#scores])}, worst {commas(scores[1])}; a game lasts {fmt(
				ticks / GAMES / 240,
				0
			)} s, a ball {fmt(plays / balls / 240, 0)} s in play with {fmt(flips / balls, 0)} flips`
		)
		print(
			`      on the house's board: {fmt(onBoard / #scores * 100, 0)}% of games make it; the median game {if place
				then "takes place " .. place
				else "does not make it"}`
		)
		local per = {}
		for _, name in
			{
				"BUMPER",
				"SLING",
				"STANDUP",
				"DROP",
				"ROLLOVER",
				"SPIN",
				"SAUCER",
				"RAMP_IN",
				"RAMP_OUT",
				"SAVE",
				"EXTRA_BALL",
				"NUDGE",
				"TILT_WARN",
				"TILT",
				"SEARCH",
			}
		do
			if cues[name] then
				table.insert(per, `{string.lower(name)} {fmt(cues[name] / GAMES)}`)
			end
		end
		print("      a game: " .. table.concat(per, ", "))
		local drains = lost.centre + lost.left + lost.right
		print(
			`      balls lost: centre {fmt(lost.centre / drains * 100, 0)}%, left outlane {fmt(
				lost.left / drains * 100,
				0
			)}%, right outlane {fmt(lost.right / drains * 100, 0)}%`
		)
		local goals = {}
		for text, n in gamesWith do
			if tbl.sheet.text[101] and says[text] and not Machine.TEXT[table.find(Machine.TEXT, text) or 0] then
				table.insert(goals, `{text} {fmt(n / GAMES * 100, 0)}% of games ({fmt(says[text] / GAMES)} a game)`)
			end
		end
		table.sort(goals)
		print("      goals: " .. table.concat(goals, "; "))
		print(`      cost: {fmt(clock / ticks * 1e6, 2)} microseconds a tick (machine and player together)`)
	end
end

local function costReport(tbl: Machine.Table)
	local c = tbl.c
	local s = Physics.new(c, 1)
	local ev: { number } = {}
	local seed = 5
	local function rnd(): number
		seed = (seed * 69069 + 1) % 4294967296
		return seed / 4294967296
	end
	local steps = 0
	local worst = 0
	local started = os.clock()
	for round = 1, 60 do
		Physics.removeGone(s)
		while #s.balls < 3 do
			Physics.addBall(s, 0.5 + rnd(), 2.2 + rnd() * 2, rnd() * 16 - 8, rnd() * 16 - 8)
		end
		local t0 = os.clock()
		for i = 1, 1200 do
			Physics.step(c, s, (i + round) % 90 < 30, i % 130 < 40, ev)
		end
		worst = math.max(worst, (os.clock() - t0) / 1200)
		steps += 1200
		table.clear(ev)
	end
	local each = (os.clock() - started) / steps
	print(
		`  cost of the physics with three balls loose and the flippers working: {fmt(each * 1e6, 2)} microseconds a step (worst five-second stretch {fmt(
			worst * 1e6,
			2
		)}); the game needs {Physics.HZ} steps a second: {fmt(each * Physics.HZ * 1000, 3)} ms of every second`
	)
end

print(
	`pinball: tick 1/{Physics.HZ} s, ball {Layout.BALL_R * 2} studs on a {Layout.WIDTH} x {Layout.LENGTH} playfield, top speed {Physics.MAX_SPEED} studs/s, at most {Physics.MAX_SUBSTEPS} sub-steps a tick`
)
for _, id in Tables.IDS do
	if ONLY and not string.find(id, ONLY, 1, true) then
		continue
	end
	local tbl = Tables.need(id)
	print("")
	print(
		`{tbl.title} ({id}): slope {tbl.def.slopeDeg} degrees, gravity {fmt(tbl.def.gravity, 2)} studs/s^2, ball save {fmt(
			tbl.sheet.saveTicks / 240,
			0
		)} s, {tbl.c.nSeg} wall pieces, {tbl.c.nCir} posts and bumpers`
	)
	surveyReport(tbl)
	flipperReport(tbl)
	shotsReport(tbl)
	if ONLY_SHOTS then
		continue
	end
	plungerReport(tbl)
	gamesReport(tbl)
	costReport(tbl)
end
