--!strict
-- ReplicatedStorage.Shared.Minigames.Pinball.Bot
-- A computer player for the pinball machines. It plays the way a person does: it looks at the ball (where it
-- is and how fast) and presses the same buttons (Machine.BTN: the two flippers, the plunger, a nudge). It
-- never reaches into the model. Three skill levels:
--   1 NOVICE  flips late and loosely at anything near a flipper, plunges at any strength;
--   2 REGULAR flips in good time and lets a rolling ball come down the flipper before it shoots;
--   3 WIZARD  times the flip to the spot on the flipper that pays best on this table (it has learnt the shots
--             by practice: Bot.learn plays each flipper's shots on a scratch machine once and remembers what
--             they scored), plunges for the skill shot and nudges a ball away from an outlane.
-- Pinball has no computer opponent (checklist PIN-R5); the bot is the idle machine's attract mode, the way the
-- specs play whole games, and what tools/pinball/calibrate.luau measures the tables with.
-- A bot's state is plain data with its own seeded stream; the same seed and the same machine give the same
-- game. (learn() keeps what it has learnt per table: a memo of a pure function of the table.)
-- Pure; Lune-tested (tests/unit/pinball_games.spec.luau).
-- Interface: LEVELS, NAMES; new(level, seed) -> State; step(bot, table, machine) -> buttons;
--   learn(table) -> Lesson (per flipper: the spot that pays best, and the plunger pull for the skill shot)

local Det = require("./Det")
local Layout = require("./Layout")
local Machine = require("./Machine")
local Physics = require("./Physics")

local Bot = {}

Bot.NAMES = { "NOVICE", "REGULAR", "WIZARD" }

export type Level = {
	lateMean: number, -- ticks between seeing the moment and pressing
	lateSd: number,
	aimSd: number, -- how far off its chosen spot on the flipper it lets the ball roll (fraction of the flipper)
	aimLo: number, -- without a learnt shot it picks a spot between these
	aimHi: number,
	learnt: boolean, -- uses the learnt spots and the skill-shot pull
	pullSd: number,
	nudges: boolean,
	holdTicks: number, -- how long it keeps the button down
	panic: number, -- chance that it presses both flippers at once
}
Bot.LEVELS = {
	{
		lateMean = 9,
		lateSd = 7,
		aimSd = 0.25,
		aimLo = 0.3,
		aimHi = 1.0,
		learnt = false,
		pullSd = 0.3,
		nudges = false,
		holdTicks = 70,
		panic = 0.35,
	},
	{
		lateMean = 3,
		lateSd = 3,
		aimSd = 0.1,
		aimLo = 0.5,
		aimHi = 0.95,
		learnt = false,
		pullSd = 0.12,
		nudges = false,
		holdTicks = 45,
		panic = 0.05,
	},
	{
		lateMean = 1,
		lateSd = 1,
		aimSd = 0.03,
		aimLo = 0.6,
		aimHi = 0.9,
		learnt = true,
		pullSd = 0.03,
		nudges = true,
		holdTicks = 36,
		panic = 0,
	},
} :: { Level }

export type State = {
	level: number,
	rng: number,
	pullFor: number, -- ticks it means to hold the plunger this time (0: not decided)
	pulled: number,
	aim: { number }, -- per flipper: the spot it is waiting for on this approach (0: not decided)
	pressIn: { number }, -- per flipper: ticks until it presses (0: no press coming)
	hold: { number }, -- per flipper: ticks of hold left
	rest: { number }, -- per flipper: ticks it will not press again
	nudgeRest: number,
}

export type Lesson = {
	aim: { number }, -- per flipper: the spot (fraction along the flipper) that pays best
	pull: number, -- plunger pull 0..1 for the skill shot
	shots: { { number } }, -- per flipper: (spot, what it paid) pairs as flat numbers, for the calibrate tool
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
		aim = {},
		pressIn = {},
		hold = {},
		rest = {},
		nudgeRest = 0,
	}
end

-- Where a ball is over flipper i as it lies at rest: along (0 at the pivot, 1 at the tip), the gap between the
-- two surfaces, and how fast the gap is closing.
local function over(c: Layout.Compiled, i: number, b: Physics.Ball): (number, number, number)
	local rest = c.frest[i]
	local dx, dy = c.fmir[i] * Det.cos(rest), Det.sin(rest)
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
	return along, gap, closing
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

-- learn(table): practise. For each flipper: cradle a ball, let it go, flip when it has rolled to a spot, and
-- see what the next three seconds score; the spot whose neighbourhood pays best is the one to aim for. For
-- the plunger: try every strength and keep the one that pays best in its first four seconds.
function Bot.learn(tbl: Machine.Table): Lesson
	local known = LESSONS[tbl.id]
	if known then
		return known
	end
	local c = tbl.c
	local lesson: Lesson = { aim = {}, pull = 0.8, shots = {} }
	local out: { number } = {}
	for i = 1, c.nFlip do
		local button = if c.fbtn[i] == 1 then BTN.LEFT else BTN.RIGHT
		local base = Machine.new(tbl, 7, 1)
		local phys = base.phys
		-- a ball set down in the inlane above this flipper, the flipper held: it rolls into the cradle
		local ball = phys.balls[1]
		local lane = tbl.def.sensors[if c.fbtn[i] == 1 then tbl.ix.sensor.inlane_l else tbl.ix.sensor.inlane_r]
		ball.x = (lane.x1 + lane.x2) / 2
		ball.y = lane.y1 + 0.2
		base.launched = true
		for _ = 1, 1440 do
			Machine.step(tbl, base, button, out)
			if #phys.balls > 0 and phys.balls[1].asleep then
				break
			end
		end
		local spots: { number } = {}
		local paid: { number } = {}
		for d = 20, 260, 4 do
			local m = Machine.clone(base)
			for _ = 1, d do
				Machine.step(tbl, m, 0, out)
			end
			local b = m.phys.balls[1]
			if b == nil or m.phase ~= Machine.PHASE.PLAY then
				break
			end
			local along = over(c, i, b)
			if along > 1.08 then
				break
			end
			local before = m.scores[1]
			for k = 1, 720 do
				Machine.step(tbl, m, if k <= 40 then button else 0, out)
				if m.phase ~= Machine.PHASE.PLAY then
					break
				end
			end
			local gain = m.scores[1] - before
			if m.phase ~= Machine.PHASE.PLAY then
				gain = 0
			end
			table.insert(spots, along)
			table.insert(paid, gain)
			table.clear(out)
		end
		-- the best spot is the middle of the best run of three
		local best, bestAt = -1, 0.75
		for k = 2, #spots - 1 do
			local v = paid[k - 1] + 2 * paid[k] + paid[k + 1]
			if v > best and spots[k] > 0.1 then
				best, bestAt = v, spots[k]
			end
		end
		lesson.aim[i] = bestAt
		local flat: { number } = {}
		for k = 1, #spots do
			table.insert(flat, spots[k])
			table.insert(flat, paid[k])
		end
		lesson.shots[i] = flat
	end
	local bestPull, bestGain = 0.8, -1
	local gains: { number } = {}
	for step = 1, 20 do
		local pull = step / 20
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
	for step = 2, 19 do
		local v = gains[step - 1] + 2 * gains[step] + gains[step + 1]
		if v > bestGain then
			bestGain, bestPull = v, step / 20
		end
	end
	lesson.pull = bestPull
	LESSONS[tbl.id] = lesson
	return lesson
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

	-- the flippers
	local balls = m.phys.balls
	local panic = false
	for i = 1, c.nFlip do
		local hold = bot.hold[i] or 0
		local rest = bot.rest[i] or 0
		local pressIn = bot.pressIn[i] or 0
		if hold > 0 then
			hold -= 1
			if hold == 0 then
				rest = 16
			end
		elseif rest > 0 then
			rest -= 1
		elseif pressIn > 0 then
			pressIn -= 1
			if pressIn == 0 then
				hold = level.holdTicks
				bot.aim[i] = 0
				if rand(bot) < level.panic then
					panic = true
				end
			end
		else
			for _, b in balls do
				if b.mode ~= FREE or b.x > Layout.FIELD_X1 then
					continue
				end
				local along, gap, closing = over(c, i, b)
				if along < -0.1 or along > 1.12 or gap > 0.5 or gap < -0.08 then
					continue
				end
				local now = false
				if gap < 0.03 and closing < 1.5 then
					-- the ball is rolling on the flipper: wait for the spot
					local aim = bot.aim[i] or 0
					if aim == 0 then
						local spot = if level.learnt
							then Bot.learn(tbl).aim[i]
							else level.aimLo + rand(bot) * (level.aimHi - level.aimLo)
						aim = math.clamp(spot + bell(bot) * level.aimSd, 0.15, 1.02)
						bot.aim[i] = aim
					end
					now = along >= aim
				elseif closing > 0 and along > 0.12 then
					-- the ball is coming down onto the flipper: meet it as it lands
					now = gap < closing * 7 / Physics.HZ
				end
				if now then
					pressIn = math.max(1, math.floor(level.lateMean + bell(bot) * level.lateSd + 0.5))
					break
				end
			end
		end
		bot.hold[i], bot.rest[i], bot.pressIn[i] = hold, rest, pressIn
	end
	for i = 1, c.nFlip do
		if (bot.hold[i] or 0) > 0 or panic then
			if panic and (bot.hold[i] or 0) == 0 then
				bot.hold[i] = level.holdTicks
			end
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
