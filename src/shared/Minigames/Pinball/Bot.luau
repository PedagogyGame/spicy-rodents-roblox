--!strict
-- ReplicatedStorage.Shared.Minigames.Pinball.Bot
-- A computer player for the pinball machines. It plays the way a person does: it looks at the ball (where it
-- is and how fast) and presses the same buttons (Machine.BTN: the two flippers, the plunger, a nudge). It
-- never reaches into the model. Three skill levels:
--   1 NOVICE  bats late and loosely at anything near a flipper, sometimes with both at once, and plunges at
--             any strength;
--   2 REGULAR bats in good time, traps the ball on a raised flipper more often than not and then shoots it:
--             mostly at what the rule sheet wants (it knows the machine's main shots, and times them to a
--             frame or two), otherwise from somewhere in the outer half of the flipper;
--   3 WIZARD  traps whenever it can, reads what the rule sheet wants hit now (sheet.wants), looks the shot up
--             in the table's shot book (Shots: where on the flipper to flip for it, learnt by measuring the
--             table, as a good player learns a machine), lets the ball go and flips when it has rolled to
--             that spot; it plunges for the skill shot and nudges a ball away from an outlane.
-- Pinball has no computer opponent (checklist PIN-R5); the bot is the idle machine's attract mode, the way the
-- specs play whole games, and what tools/pinball/calibrate.luau measures the tables with.
-- A bot's state is plain data with its own seeded stream; the same seed and the same machine give the same
-- game. (learn() keeps what it has learnt per table: a memo of a pure function of the table.)
-- Pure; Lune-tested (tests/unit/pinball_games.spec.luau).
-- Interface: LEVELS, NAMES; new(level, seed) -> State; step(bot, table, machine) -> buttons;
--   learn(table) -> Lesson (the plunger pull for the skill shot; about a tenth of a second of practice, once);
--   the REGULAR and the WIZARD also need the table's shot book (Shots.book: about a fifth of a second, once),
--   so an attract mode that must not hitch uses level 1, or asks for the book (and learn) before the first frame

local Det = require("./Det")
local Layout = require("./Layout")
local Machine = require("./Machine")
local Physics = require("./Physics")
local Shots = require("./Shots")

local Bot = {}

Bot.NAMES = { "NOVICE", "REGULAR", "WIZARD" }

export type Level = {
	lateMean: number, -- ticks between seeing the moment and pressing
	lateSd: number,
	aimTicks: number, -- how far off the moment it flips a ball it is timing (standard deviation, in ticks)
	aimLo: number, -- without a learnt shot it picks a spot between these
	aimHi: number,
	learnt: boolean, -- plunges for the skill shot
	book: number, -- how often it aims by the shot book (what the rule sheet wants now), 0..1; otherwise anywhere
	pullSd: number,
	nudges: boolean,
	holdTicks: number, -- how long it keeps the button down after a flip
	panic: number, -- chance that it presses both flippers at once
	trap: number, -- chance that it tries to catch an incoming ball on a raised flipper
}
Bot.LEVELS = {
	{
		lateMean = 9,
		lateSd = 7,
		aimTicks = 14,
		aimLo = 0.3,
		aimHi = 1.0,
		learnt = false,
		book = 0,
		pullSd = 0.3,
		nudges = false,
		holdTicks = 70,
		panic = 0.35,
		trap = 0,
	},
	{
		lateMean = 3,
		lateSd = 3,
		aimTicks = 5,
		aimLo = 0.45,
		aimHi = 0.95,
		learnt = false,
		book = 0.7,
		pullSd = 0.12,
		nudges = false,
		holdTicks = 45,
		panic = 0.05,
		trap = 0.7,
	},
	{
		lateMean = 1,
		lateSd = 1,
		aimTicks = 2.5,
		aimLo = 0.6,
		aimHi = 0.9,
		learnt = true,
		book = 1,
		pullSd = 0.03,
		nudges = true,
		holdTicks = 36,
		panic = 0,
		trap = 1,
	},
} :: { Level }

Bot.TRAP_SPEED = 9 -- a ball faster than this is batted, not caught
Bot.SKID = 4.5 -- flipper lengths a second: a ball crossing the flipper faster than this is hit at once
Bot.TRAP_TICKS = 1200 -- it gives a catch this long to settle
Bot.STILL_TICKS = 30 -- a caught ball must lie this long before it is let go
Bot.MIN_WINDOW = 3 -- ticks: a shot with a narrower window than this is not worth trying for

-- what a flipper hand is doing
local IDLE, WAIT, HOLD, REST, TRAP = 0, 1, 2, 3, 4

export type State = {
	level: number,
	rng: number,
	pullFor: number, -- ticks it means to hold the plunger this time (0: not decided)
	pulled: number,
	mode: { number }, -- per flipper
	timer: { number }, -- per flipper: ticks left in WAIT, HOLD, REST or TRAP
	aim: { number }, -- per flipper: the spot it is waiting for on this approach (0: not decided)
	lead: { number }, -- per flipper: how many ticks ahead of the spot it will press this time (its timing error is in it)
	still: { number }, -- per flipper: ticks the trapped ball has lain still
	noTrap: { number }, -- per flipper: ticks in which it will not trap again (it has just let a ball go to shoot it)
	nudgeRest: number,
}

export type Lesson = {
	pull: number, -- plunger pull 0..1 for the skill shot
}

local R = Layout.BALL_R
local BTN = Machine.BTN
local FREE = Physics.FREE

local function rand(b: State): number
	local a = (b.rng * 69069 + 1) % 4294967296
	b.rng = a
	return math.floor(a / 65536) / 65536
end

-- a bell-shaped number from three uniform ones (mean 0, standard deviation 1)
local function bell(b: State): number
	return (rand(b) + rand(b) + rand(b) - 1.5) * 2
end

function Bot.new(level: number, seed: number): State
	assert(Bot.LEVELS[level], "bot level 1, 2 or 3")
	return {
		level = level,
		rng = math.floor(seed) % 4294967296,
		pullFor = 0,
		pulled = 0,
		mode = { IDLE, IDLE },
		timer = { 0, 0 },
		aim = { 0, 0 },
		lead = { 0, 0 },
		still = { 0, 0 },
		noTrap = { 0, 0 },
		nudgeRest = 0,
	}
end

-- Where a ball is over flipper i as it lies at rest (or, with up, as it stands when raised): along (0 at the
-- pivot, 1 at the tip), the gap between the two surfaces, how fast the gap is closing, and how fast the ball
-- is moving toward the tip.
local function over(c: Layout.Compiled, i: number, b: Physics.Ball, up: boolean?): (number, number, number, number)
	local angle = if up then c.fup[i] else c.frest[i]
	local dx, dy = c.fmir[i] * Det.cos(angle), Det.sin(angle)
	-- the flipper's upper side: its direction turned a quarter turn, whichever way faces up the table
	local nx, ny = -dy, dx
	if ny < 0 then
		nx, ny = dy, -dx
	end
	local qx, qy = b.x - c.fpx[i], b.y - c.fpy[i]
	local along = (qx * dx + qy * dy) / c.flen[i]
	local t = math.clamp(along, 0, 1)
	local surface = c.frb[i] + (c.frt[i] - c.frb[i]) * t
	local gap = qx * nx + qy * ny - R - surface
	local closing = -(b.vx * nx + b.vy * ny)
	return along, gap, closing, (b.vx * dx + b.vy * dy) / c.flen[i]
end

local function plungerBall(tbl: Machine.Table, m: Machine.State): boolean
	local p = tbl.def.plunger
	for _, b in m.phys.balls do
		if b.mode == FREE and b.x > Layout.FIELD_X1 and b.y < p.y + 0.04 and b.vy < 0.3 and b.vy > -0.3 then
			return true
		end
	end
	return false
end

local LESSONS: { [string]: Lesson } = {}

-- learn(table): practise the plunge: try every strength and keep the one that pays best in its first four
-- seconds (the skill shot).
function Bot.learn(tbl: Machine.Table): Lesson
	local known = LESSONS[tbl.id]
	if known then
		return known
	end
	local lesson: Lesson = { pull = 0.8 }
	local out: { number } = {}
	local bestPull, bestGain = 0.8, -1
	local gains: { number } = {}
	local STEPS = 50
	for step = 1, STEPS do
		local pull = step / STEPS
		local m = Machine.new(tbl, 11, 1)
		local hold = math.floor(pull * tbl.def.plunger.pullTicks + 0.5)
		for k = 1, hold + 1 do
			Machine.step(tbl, m, if k <= hold then BTN.PLUNGE else 0, out)
		end
		for _ = 1, 960 do
			Machine.step(tbl, m, 0, out)
			if m.phase ~= Machine.PHASE.PLAY then
				break
			end
		end
		gains[step] = m.scores[1]
		table.clear(out)
	end
	for step = 2, STEPS - 1 do
		local v = gains[step - 1] + 2 * gains[step] + gains[step + 1]
		if v > bestGain then
			bestGain, bestPull = v, step / STEPS
		end
	end
	lesson.pull = bestPull
	LESSONS[tbl.id] = lesson
	return lesson
end

-- Where on flipper i to flip. A player who knows the machine asks the rule sheet what is wanted now and takes
-- the first of those that this flipper can make; one who does not picks a spot somewhere out along it.
local function chooseAim(bot: State, tbl: Machine.Table, level: Level, i: number, m: Machine.State): number
	local spot = level.aimLo + rand(bot) * (level.aimHi - level.aimLo)
	if level.book > 0 and (level.book >= 1 or rand(bot) < level.book) then
		local book = Shots.book(tbl)
		local mine = book.windows[i]
		local first: Shots.Window?, second: Shots.Window? = nil, nil
		for _, kk in tbl.sheet.wants(m, m.sheets[m.up]) do
			local w = mine[kk]
			if w and w.ticks >= Bot.MIN_WINDOW then
				if first == nil then
					first = w
				elseif w.key ~= first.key then
					second = w
					break
				end
			end
		end
		if first == nil then
			-- nothing that is wanted can be made from here: the widest shot there is
			for _, kk in book.keys do
				if mine[kk] then
					first = mine[kk]
					break
				end
			end
		end
		if first then
			-- now and then the next best, so the whole table gets played
			spot = if second and rand(bot) < 0.2 then second.along else first.along
		end
	end
	-- a hand is early or late by a time, not by a distance
	bot.lead[i] = level.lateMean - bell(bot) * level.aimTicks
	return math.clamp(spot, -0.09, 1.0)
end

-- step(bot, table, machine): the buttons the bot holds this tick.
function Bot.step(bot: State, tbl: Machine.Table, m: Machine.State): number
	if m.phase ~= Machine.PHASE.PLAY then
		return 0
	end
	local level = Bot.LEVELS[bot.level]
	local c = tbl.c
	local buttons = 0

	-- the plunger
	if m.autoIn == 0 and plungerBall(tbl, m) then
		if bot.pullFor == 0 then
			local want = if level.learnt then Bot.learn(tbl).pull else 0.45 + rand(bot) * 0.5
			want = math.clamp(want + bell(bot) * level.pullSd, 0.05, 1)
			bot.pullFor = math.max(2, math.floor(want * tbl.def.plunger.pullTicks + 0.5))
			bot.pulled = 0
		end
		if bot.pulled < bot.pullFor then
			bot.pulled += 1
			buttons += BTN.PLUNGE
		else
			bot.pullFor = 0
		end
	else
		bot.pullFor = 0
		bot.pulled = 0
	end

	-- the flippers: one hand each
	local balls = m.phys.balls
	local panic = false
	for i = 1, c.nFlip do
		local mode, timer = bot.mode[i], bot.timer[i]
		if bot.noTrap[i] > 0 then
			bot.noTrap[i] -= 1
		end
		if mode == HOLD or mode == REST then
			timer -= 1
			if timer <= 0 then
				mode, timer = if mode == HOLD then REST else IDLE, 16
			end
		elseif mode == WAIT then
			timer -= 1
			if timer <= 0 then
				mode, timer = HOLD, level.holdTicks
				bot.aim[i] = 0
				if rand(bot) < level.panic then
					panic = true
				end
			end
		elseif mode == TRAP then
			-- the flipper is up; wait for the ball to settle in the cradle, then let it go and shoot it
			timer -= 1
			local near, lying = false, false
			for _, b in balls do
				if b.mode == FREE and b.x < Layout.FIELD_X1 then
					local along, gap = over(c, i, b)
					if along > -0.9 and along < 1.4 and gap > -0.3 and gap < 0.9 then
						near = true
						if b.vx * b.vx + b.vy * b.vy < 0.02 then
							lying = true
						end
					end
				end
			end
			bot.still[i] = if lying then bot.still[i] + 1 else 0
			if bot.still[i] >= Bot.STILL_TICKS then
				mode, timer = IDLE, 0
				bot.aim[i] = chooseAim(bot, tbl, level, i, m)
				bot.noTrap[i] = 480
			elseif not near or timer <= 0 then
				mode, timer = REST, 8
			end
		else
			for _, b in balls do
				if b.mode ~= FREE or b.x > Layout.FIELD_X1 then
					continue
				end
				-- a catch: the flipper has to be up and still before the ball lands on it, so the moment is
				-- judged against the flipper as it will stand
				if level.trap > 0 and bot.noTrap[i] == 0 then
					local upAlong, upGap, upClosing, upOutward = over(c, i, b, true)
					if upClosing > 0.3 and upGap > 0.02 and upGap < upClosing * 34 / Physics.HZ then
						local lands = upAlong + upOutward * upGap / upClosing
						if
							lands > 0.05
							and lands < 0.8
							and b.vx * b.vx + b.vy * b.vy < Bot.TRAP_SPEED * Bot.TRAP_SPEED
						then
							if rand(bot) < level.trap then
								mode, timer = TRAP, Bot.TRAP_TICKS
								bot.still[i] = 0
								break
							end
							-- not this time: this ball is batted
							bot.noTrap[i] = 120
						end
					end
				end
				local along, gap, closing, outward = over(c, i, b)
				if along < -0.1 or along > 1.12 or gap > 0.5 or gap < -0.08 then
					continue
				end
				local now, timed = false, false
				if gap < 0.03 and closing < 1.5 then
					if outward > Bot.SKID then
						-- the ball is skidding out along the flipper: no time to pick a spot
						now = along > 0.25
					else
						-- the ball is rolling on the flipper: wait for the spot
						if bot.aim[i] == 0 then
							bot.aim[i] = chooseAim(bot, tbl, level, i, m)
						end
						-- (it presses a moment after it decides, and allows for that)
						now = along + outward * bot.lead[i] / Physics.HZ >= bot.aim[i]
						timed = true
					end
				elseif closing > 0 and along > 0.12 then
					-- the ball is coming down onto the flipper: meet it as it lands
					now = gap < closing * 7 / Physics.HZ
				end
				if now then
					mode = WAIT
					-- a timed shot is pressed now (its error is already in the lead); a ball met on the fly is
					-- pressed after the hand's own delay
					timer = if timed
						then 1
						else math.max(1, math.floor(level.lateMean + bell(bot) * level.lateSd + 0.5))
					break
				end
			end
		end
		bot.mode[i], bot.timer[i] = mode, timer
	end
	for i = 1, c.nFlip do
		if panic and bot.mode[i] ~= HOLD and bot.mode[i] ~= TRAP then
			bot.mode[i], bot.timer[i] = HOLD, level.holdTicks
		end
		if bot.mode[i] == HOLD or bot.mode[i] == TRAP then
			buttons = bit32.bor(buttons, if c.fbtn[i] == 1 then BTN.LEFT else BTN.RIGHT)
		end
	end

	-- a nudge away from an outlane
	if bot.nudgeRest > 0 then
		bot.nudgeRest -= 1
	elseif level.nudges and m.warnings == 0 and m.bob < 0.2 then
		local lo = c.fpy[1] + 0.25
		for _, b in balls do
			if b.mode == FREE and b.vy < -0.5 and b.y > lo and b.y < lo + 0.55 then
				if b.x < 0.2 and b.vx <= 0.2 then
					buttons += BTN.NUDGE_L
					bot.nudgeRest = 480
					break
				elseif b.x > Layout.FIELD_X1 - 0.2 and b.x < Layout.FIELD_X1 and b.vx >= -0.2 then
					buttons += BTN.NUDGE_R
					bot.nudgeRest = 480
					break
				end
			end
		end
	end
	return buttons
end

return Bot
