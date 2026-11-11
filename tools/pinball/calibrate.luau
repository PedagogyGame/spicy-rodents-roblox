--!strict
-- tools/pinball/calibrate.luau: a developer's look at the pinball model (Shared/Minigames/Pinball) so the
-- tables are tuned from numbers, not guesses. For each of the three machines it prints:
--   * the flipper: stroke and fall time, and the shot table (where the ball is on the flipper when you flip
--     against the angle and speed it leaves at: checklist PIN-P1 asks for it to rise steadily), the live catch;
--   * the plunger: what each strength of pull does first (the skill shot is the band that pays);
--   * the computer players, NOVICE, REGULAR and WIZARD: scores, how long a ball lasts, flips, what gets hit a
--     game, how often each goal on the rule sheet is reached, where balls are lost;
--   * what a step costs.
-- Usage, from the repo root: lune run tools/pinball/calibrate.luau [games per level, default 40] [table id part]
-- Interface: a script (prints a report); nothing is written.

local process = require("@lune/process")
local Bot = require("../../src/shared/Minigames/Pinball/Bot")
local Layout = require("../../src/shared/Minigames/Pinball/Layout")
local Machine = require("../../src/shared/Minigames/Pinball/Machine")
local Physics = require("../../src/shared/Minigames/Pinball/Physics")
local Tables = require("../../src/shared/Minigames/Pinball/Tables")

local GAMES = tonumber(process.args[1]) or 40
local ONLY = process.args[2]

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
	for _ = 1, 60 do
		Physics.step(c, s, true, false, ev)
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
		)} degrees, tip speed {fmt(Physics.FLIP_W_MAX * c.freach[1])} studs/s`
	)

	-- the shot table: a cradled ball is let go and flipped after a delay
	local base = Machine.new(tbl, 7, 1)
	local lane = tbl.def.sensors[tbl.ix.sensor.inlane_l]
	local ball = base.phys.balls[1]
	ball.x, ball.y = (lane.x1 + lane.x2) / 2, lane.y1 + 0.2
	base.launched = true
	local out: { number } = {}
	for _ = 1, 1440 do
		Machine.step(tbl, base, BTN.LEFT, out)
		if base.phys.balls[1].asleep then
			break
		end
	end
	print("  shot table, left flipper (ball let go from a cradle; angle from straight up, + across the table):")
	print("    flip after   ball at   angle   speed   reaches")
	local last = -999
	local steady = true
	local rest = c.frest[1]
	for delay = 60, 240, 12 do
		local m = Machine.clone(base)
		for _ = 1, delay do
			Machine.step(tbl, m, 0, out)
		end
		local b = m.phys.balls[1]
		if b == nil then
			break
		end
		local along = ((b.x - c.fpx[1]) * math.cos(rest) + (b.y - c.fpy[1]) * math.sin(rest)) / c.flen[1]
		local angle, speed, top = 0 / 0, 0, 0
		for _ = 1, 400 do
			Machine.step(tbl, m, BTN.LEFT, out)
			b = m.phys.balls[1]
			if b == nil or b.mode ~= Physics.FREE then
				break
			end
			top = math.max(top, b.y)
			if angle ~= angle and b.y > c.fpy[1] + 0.4 and b.vy > 0 then
				angle = math.deg(math.atan2(b.vx, b.vy))
				speed = math.sqrt(b.vx * b.vx + b.vy * b.vy)
			end
		end
		if angle == angle and along > 0.05 and along < 1.02 then
			if angle < last - 2.5 then
				steady = false
			end
			last = math.max(last, angle)
			print(
				string.format(
					"    %4d ms    %5.2f    %+6.1f   %5.1f   y %.1f",
					delay / 240 * 1000,
					along,
					angle,
					speed,
					top
				)
			)
		end
		table.clear(out)
	end
	print(`    the angle rises steadily with the ball's place on the flipper: {if steady then "yes" else "NO"}`)

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
	for flipAt = landsAt - 22, landsAt - 6, 2 do
		local high = hop(flipAt)
		table.insert(parts, `{fmt((flipAt - landsAt) / 240 * 1000, 0)} ms: {fmt(high / held * 100, 0)}%`)
	end
	print(
		`  live catch (a ball dropped on the flipper hops {fmt(held, 2)} studs off it when it is held; flipped so long before the ball lands, the hop is):`
	)
	print("    " .. table.concat(parts, "   "))
end

local function plungerReport(tbl: Machine.Table)
	local p = tbl.def.plunger
	print(`  plunger (full pull {fmt(p.pullTicks / 240, 2)} s; launch {p.vMin} to {p.vMax} studs/s):`)
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
		local first = "back to the plunger"
		local skill = false
		for _ = 1, 1200 do
			Machine.step(tbl, m, 0, out)
			for i = 1, #out, 3 do
				local cue = out[i]
				if cue == CUE.JINGLE and m.skillLeft == 0 and not skill and first == "back to the plunger" then
					skill = true
				end
				if first == "back to the plunger" then
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
				if cue == CUE.SAY and out[i + 1] >= 101 and string.find(tbl.sheet.text[out[i + 1]], "SHOT", 1, true) then
					skill = true
				end
			end
			table.clear(out)
			if m.phase ~= PHASE.PLAY then
				break
			end
		end
		table.insert(line, `    pull {fmt(pull, 2)} -> {first}{if skill then "  ** SKILL SHOT **" else ""}`)
	end
	print(table.concat(line, "\n"))
	local lesson = Bot.learn(tbl)
	local function spots(list: { number }): string
		local parts = {}
		for _, v in list do
			table.insert(parts, fmt(v, 2))
		end
		return table.concat(parts, ", ")
	end
	print(
		`  the wizard's lesson: plunge at {fmt(lesson.pull, 2)}; from a cradle, flip the left flipper when the ball is at {spots(
			lesson.aim[1]
		)} along it, the right at {spots(lesson.aim[2])} (best first)`
	)
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
		print(
			`    {Bot.NAMES[level]}: median {commas(scores[(#scores + 1) // 2])}, mean {commas(sum / #scores)}, best {commas(
				scores[#scores]
			)}, worst {commas(scores[1])}; a game lasts {fmt(ticks / GAMES / 240, 0)} s, a ball {fmt(
				plays / balls / 240,
				0
			)} s in play with {fmt(flips / balls, 0)} flips`
		)
		local per = {}
		for _, name in { "BUMPER", "SLING", "STANDUP", "DROP", "ROLLOVER", "SPIN", "SAUCER", "RAMP_IN", "RAMP_OUT", "SAVE", "EXTRA_BALL", "NUDGE", "TILT_WARN", "TILT", "SEARCH" } do
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
	flipperReport(tbl)
	plungerReport(tbl)
	gamesReport(tbl)
	costReport(tbl)
end
