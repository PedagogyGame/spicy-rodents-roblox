--!strict
-- ReplicatedStorage.Shared.Minigames.Pinball.Machine
-- A whole pinball machine as a state machine: the physics core (Physics) plus everything a real machine's
-- board does round it. One machine, one to four players taking a ball each in turn, three balls a game, on
-- free play (checklist PIN-R1..R5):
--   * the plunger is analogue: hold to pull back (a full pull takes PULL time), let go to launch; the strength
--     is the launch speed, so a soft plunge can drop into a table's skill shot. A hand that can say HOW FAR
--     (a stick pulled down, a finger dragged down a strip) sends the pull itself, 1..31, in the same number
--     as the buttons, and the rod follows the hand;
--   * a ball save runs for the table's own time from the moment the ball enters the playfield: a ball lost in
--     it comes back to the plunger and is launched by the machine;
--   * nudges shove the ball and swing the tilt bob: two warnings a ball, the third TILTS (flippers, bumpers
--     and slingshots dead, every lamp out, the rule sheet deaf to everything but the drain, the ball and its
--     bonus lost). A thump on the glass from outside (an animal landing on the cabinet) is half a nudge: on
--     top of the player's own shoving it can be the swing that brings the first warning, never the last
--     warning and never the tilt, and thumps closer together than THUMP_COOL are one thump;
--   * the end-of-ball bonus is counted out step by step with its multiplier;
--   * one extra ball at most per game (EXTRA_BALLS, whoever earns it: once it is taken every player's
--     extra-ball light goes out), earned by play; no credits, no replays, no match number;
--   * a ball that sits still where no flipper holds it is found by a ball search (a seeded kick), so a game
--     can always be finished;
--   * a player who has gone for good (walked away, bitten) is retired: the ball in play is played out dead,
--     their later balls are passed over (an extra ball they were owed among them), their score stands.
-- What each table scores, lights and says is its rule sheet (Sheet, in TableAcorn / TableSpicy / TableSpace):
-- the machine hands every switch event from the physics to the sheet and offers it add(), callout(),
-- extraBall(), feed() and the like.
-- The state is plain data (numbers, booleans, arrays, string-keyed maps of numbers): step() reads the state
-- and one number of buttons, writes the state and appends cues for the eye and ear to a list. Nothing lives
-- outside the state, so a copy continues identically and the server's replay of the input log (InputLog,
-- Replay) is the score of record (PIN-P6).
-- Pure; Lune-tested (tests/unit/pinball_machine.spec.luau, pinball_rules.spec.luau, pinball_games.spec.luau).
-- Interface: BTN (button bits), PHASE, CUE, SAY (the callouts every table shares), TEXT; BALLS, MAX_PLAYERS and
--   the tuning constants; new(table, seed, players) -> State; step(table, state, buttons, out);
--   forfeit(table, state, out) (an abandoned ball is played out dead); retire(table, state, seat, out) (a
--   player has gone for good); buttons(bits, pull) -> the number step() takes; pullOf(buttons) -> 0..31;
--   lamps(table, state, into) -> into;
--   for sheets: add, callout, cue, extraBall, extraOpen, feed, save, stat, raiseDrops, dropsClear,
--   live(state) -> number;
--   key(code, ref) -> shot key;
--   clone(state) -> State; types Sheet, Table, State

local Layout = require("./Layout")
local Physics = require("./Physics")

local Machine = {}

Machine.BALLS = 3
Machine.EXTRA_BALLS = 1 -- extra balls in a whole game, whoever earns them (checklist PIN-R4: "one extra ball at most per game")
Machine.MAX_PLAYERS = 4
Machine.SAVE_GRACE = 360 -- ticks after the ball save lamp goes out in which a drain is still given back
Machine.SKILL_TICKS = 1680 -- the skill shot is open this long after the ball leaves the shooter lane
Machine.FEED_TICKS = 168 -- a ball the machine owes comes up to the plunger this long after the lane is clear
Machine.AUTO_TICKS = 96 -- and is launched by the machine this long after that
Machine.AUTO_SPREAD = 0.1 -- the machine's own launch varies by this much of a full pull either way
Machine.NUDGE_SIDE = 0.85 -- studs/s a sideways nudge gives the ball
Machine.NUDGE_UP = 0.7
Machine.NUDGE_COOL = 36 -- ticks: a second press sooner than this is the same shove
Machine.BOB_LIMIT = 1.5 -- the tilt bob touches its ring past this
Machine.BOB_SETTLE = 300 -- ticks for one nudge's swing to die away
Machine.WARNINGS = 2 -- warnings a ball; the next one tilts
Machine.THUMP_BOB = 0.5 -- a thump on the glass swings the bob half as far as a nudge
Machine.THUMP_COOL = 480 -- ticks: a second thump sooner than this is the same thump (two seconds)
Machine.BONUS_STEPS = 16
Machine.BONUS_STEP_TICKS = 20
Machine.BONUS_HOLD = 240 -- ticks the counted bonus stays on the display
Machine.SEARCH_TICKS = 720 -- a loose ball that lies still this long with no flipper held: ball search
Machine.SAY_TICKS = 480 -- a callout stays on the display this long
Machine.FORFEIT_TICKS = 14400 -- an abandoned ball is given a minute to drain, then taken

Machine.BTN = { LEFT = 1, RIGHT = 2, PLUNGE = 4, NUDGE_L = 8, NUDGE_R = 16, NUDGE_UP = 32, THUMP = 64 }
Machine.BTN_ALL = 127
-- above the button bits the same number carries an analogue plunger: how far the hand has pulled it, 0 (not
-- held this way) to PULL_LEVELS (right back)
Machine.PULL_UNIT = 128
Machine.PULL_LEVELS = 31
Machine.BUTTONS_MAX = 127 + 31 * 128
Machine.ROD_TICKS = 40 -- the rod follows the hand this fast: its whole travel in this many ticks

Machine.PHASE = { PLAY = 1, BONUS = 2, OVER = 3 }

-- What the machine tells the eye and the ear: three numbers each (cue, a, b) appended to step()'s out list.
-- A table's sound set maps the same cues to its own sounds (checklist PIN-S4).
Machine.CUE = {
	FLIP_UP = 1, -- a: flipper number
	FLIP_DOWN = 2,
	FLIPPER_HIT = 3, -- a: flipper, b: closing speed
	WALL = 4, -- a: material code, b: speed
	POST = 5, -- b: speed
	BUMPER = 6, -- a: bumper number, b: 1 fired
	SLING = 7, -- a: sling number
	STANDUP = 8, -- a: target number
	DROP = 9, -- a: target number
	ROLLOVER = 10, -- a: sensor number
	SPIN = 11, -- a: sensor number (one turn)
	SAUCER = 12, -- a: saucer number
	EJECT = 13,
	RAMP_IN = 14, -- a: rail number
	RAMP_OUT = 15, -- a: rail number, b: 1 made, 0 rolled back
	BALLS_CLICK = 16,
	DRAIN = 17,
	PLUNGE = 18, -- b: strength 0..1
	SAVE = 19, -- the ball is given back
	BONUS_TICK = 20, -- b: points in this step
	TILT_WARN = 21, -- a: warnings so far
	TILT = 22,
	BALL_START = 23, -- a: player, b: ball number
	BALL_END = 24, -- a: player, b: bonus total
	EXTRA_BALL = 25,
	GAME_OVER = 26,
	SAY = 27, -- a: callout number, b: its value (points, a count)
	NUDGE = 28, -- a: 1 from the left, 2 from the right, 3 forward, 4 a thump on the glass
	SEARCH = 29,
	RESET_DROPS = 30,
	JINGLE = 31, -- a: the table's own jingle number (a goal made)
	GATE = 32,
}

-- the callouts every table shares; a sheet's own start at 101
Machine.SAY = {
	FREE_PLAY = 1,
	BALL_SAVED = 2,
	TILT_WARNING = 3,
	TILT = 4,
	EXTRA_BALL = 5,
	SHOOT_AGAIN = 6,
	BONUS = 7,
	GAME_OVER = 8,
	PLUNGE = 9,
	BALL_SEARCH = 10,
	THUMP = 11,
	EXTRA_BALL_LIT = 12,
}
Machine.TEXT = {
	[1] = "FREE PLAY",
	[2] = "BALL SAVED",
	[3] = "CAREFUL! TILT WARNING",
	[4] = "TILT",
	[5] = "EXTRA BALL",
	[6] = "SHOOT AGAIN",
	[7] = "BONUS",
	[8] = "GAME OVER",
	[9] = "HOLD TO PULL THE PLUNGER, LET GO TO LAUNCH",
	[10] = "BALL SEARCH",
	[11] = "SOMETHING THUMPED THE GLASS!",
	[12] = "EXTRA BALL IS LIT",
} :: { [number]: string }

export type Numbers = { [string]: number }

export type State = {
	phys: Physics.State,
	phase: number,
	players: number,
	up: number, -- the player whose ball it is
	ball: number, -- that player's ball number, 1..BALLS
	scores: { number },
	extras: { number }, -- per player: extra balls earned this game (EXTRA_BALLS in all, between them)
	sheets: { Numbers }, -- per player: the table's own state
	stats: { Numbers }, -- per player: bumpers, ramps, targets, bestBonus, ...
	shootAgain: boolean,
	launched: boolean, -- this ball has been on the playfield
	saveLeft: number, -- ticks of ball save left (the grace is on top)
	graceLeft: number,
	skillLeft: number,
	pull: number, -- ticks the plunger has been held
	prev: number, -- the buttons as last seen
	bob: number,
	nudgeCool: number,
	thumpCool: number, -- ticks in which another thump on the glass is the same thump
	warnings: number,
	tilted: boolean,
	forfeit: boolean,
	forfeitLeft: number,
	gone: { boolean }, -- per player: retired from this game (their balls are passed over)
	queue: number, -- balls the machine owes the plunger
	feedIn: number, -- ticks until the next owed ball comes up (0: not counting)
	autoIn: number, -- ticks until the machine launches the ball on the plunger (0: the player launches)
	quiet: number, -- ticks a loose ball has lain still with no flipper held
	bonusBase: number,
	bonusMult: number,
	bonusLeft: number,
	bonusChunk: number,
	bonusTimer: number,
	say: number, -- the callout on the display
	sayValue: number,
	sayLeft: number,
	ballTicks: number, -- ticks this ball has been in play
}

export type Sheet = {
	saveTicks: number,
	maxScorePerSec: number, -- more than this, averaged over a ball, cannot be play (the replay guard)
	scoreScale: string, -- for the record: what a good game looks like
	text: { [number]: string }, -- the sheet's own callouts, from 101
	init: () -> Numbers,
	ballStart: (m: State, t: Numbers, tbl: Table, out: { number }) -> (),
	event: (
		m: State,
		t: Numbers,
		tbl: Table,
		out: { number },
		code: number,
		ref: number,
		value: number,
		ball: number
	) -> (),
	tick: (m: State, t: Numbers, tbl: Table, out: { number }) -> (),
	flip: (m: State, t: Numbers, left: boolean) -> (), -- a flipper button went down (lane change)
	drained: (m: State, t: Numbers, tbl: Table, out: { number }, saved: boolean) -> (),
	-- the machine has just gone dead. On a tilt the sheet is told of nothing but drains from here to the end of
	-- the ball (no event, no flip, no tick); on an abandoned ball (forfeit) the switches still count but nobody
	-- is playing. Either way whatever was running (a countdown, a mode) is put away here
	tilted: (m: State, t: Numbers, tbl: Table, out: { number }) -> (),
	bonus: (m: State, t: Numbers) -> (number, number), -- base, multiplier
	lamps: (m: State, t: Numbers, tbl: Table, lamp: { number }) -> (), -- 1 lit, 2 flashing
	status: (m: State, t: Numbers) -> string, -- one line: what to shoot for now
	-- what to shoot for now, as shot keys (Machine.key), the most wanted first: what the status line says,
	-- in a form a computer player can aim by (Shots, Bot)
	wants: (m: State, t: Numbers) -> { number },
}

export type Table = {
	id: string,
	title: string,
	def: Layout.TableDef,
	ix: Layout.Index,
	c: Layout.Compiled,
	sheet: Sheet,
}

local BTN = Machine.BTN
local CUE = Machine.CUE
local SAY = Machine.SAY
local EV = Physics.EV
local PLAY, BONUS, OVER = 1, 2, 3
local FREE, HELD, GONE = Physics.FREE, Physics.HELD, Physics.GONE
local band = bit32.band

-- step()'s own scratch list of physics events; emptied at the top of every step
local ev: { number } = {}

local function push(out: { number }, cue: number, a: number, b: number)
	local n = #out
	out[n + 1] = cue
	out[n + 2] = a
	out[n + 3] = b
end

-- key(code, ref): one number for "this happened at that element" (a Physics.EV code and the element's number):
-- how a shot is named (Shots) and how a sheet says what it wants hit.
function Machine.key(code: number, ref: number): number
	return code * 1000 + ref
end

-- buttons(bits, pull): the one number step() takes: BTN bits plus an analogue plunger pull of 0..1 (0: the
-- plunger is not held this way).
function Machine.buttons(bits: number, pull: number?): number
	local level = 0
	if pull and pull > 0 then
		level = math.clamp(math.floor(pull * Machine.PULL_LEVELS + 0.5), 1, Machine.PULL_LEVELS)
	end
	return bit32.band(bits, Machine.BTN_ALL) + level * Machine.PULL_UNIT
end

-- pullOf(buttons): the analogue plunger level in a buttons number, 0..PULL_LEVELS.
function Machine.pullOf(buttons: number): number
	return bit32.band(bit32.rshift(buttons, 7), Machine.PULL_LEVELS)
end

-- cue(out, cue, a, b): for sheets.
function Machine.cue(out: { number }, cue: number, a: number, b: number)
	push(out, cue, a, b)
end

-- callout(m, out, id, value): put a line on the display.
function Machine.callout(m: State, out: { number }, id: number, value: number?)
	m.say = id
	m.sayValue = value or 0
	m.sayLeft = Machine.SAY_TICKS
	push(out, CUE.SAY, id, value or 0)
end

-- add(m, points): score for the player up. A tilted machine scores nothing.
function Machine.add(m: State, points: number)
	if m.tilted or m.phase == OVER then
		return
	end
	m.scores[m.up] += points
end

function Machine.stat(m: State, key: string, n: number?)
	local s = m.stats[m.up]
	s[key] = (s[key] or 0) + (n or 1)
end

-- extraOpen(m): the game's extra ball has not been taken yet (a sheet lights its extra-ball shot only then).
function Machine.extraOpen(m: State): boolean
	local taken = 0
	for _, n in m.extras do
		taken += n
	end
	return taken < Machine.EXTRA_BALLS
end

-- extraBall(m, out): the one extra ball of the game, for the player up. True when it was given. Once it is
-- taken, the extra-ball light on every player's sheet (a sheet's own `extraLit`) goes out.
function Machine.extraBall(m: State, out: { number }): boolean
	if m.tilted or m.phase ~= PLAY or m.gone[m.up] or not Machine.extraOpen(m) then
		return false
	end
	m.extras[m.up] += 1
	m.shootAgain = true
	if not Machine.extraOpen(m) then
		for _, sheet in m.sheets do
			if sheet.extraLit ~= nil then
				sheet.extraLit = 0
			end
		end
	end
	push(out, CUE.EXTRA_BALL, m.up, 0)
	Machine.callout(m, out, SAY.EXTRA_BALL, 0)
	return true
end

-- save(m, ticks): the ball save runs for at least this long from now (a sheet's own save: the start of a
-- multiball). Nothing on a tilted or abandoned ball.
function Machine.save(m: State, ticks: number)
	if m.tilted or m.forfeit or m.phase ~= PLAY then
		return
	end
	if ticks > m.saveLeft then
		m.saveLeft = ticks
	end
	m.graceLeft = 0
end

-- feed(m, n): the machine owes the plunger n more balls (a lock, a multiball); it launches them itself.
function Machine.feed(m: State, n: number)
	m.queue += n
end

-- raiseDrops(m, tbl, out): every drop target stands up again.
function Machine.raiseDrops(m: State, tbl: Table, out: { number })
	local drop = m.phys.drop
	for _, i in tbl.c.dropTargets do
		drop[i] = false
	end
	push(out, CUE.RESET_DROPS, 0, 0)
end

-- dropsClear(m, tbl): no loose ball is so close to a drop target that standing the bank up would catch it.
function Machine.dropsClear(m: State, tbl: Table): boolean
	local c = tbl.c
	local reach = Layout.BALL_R * 2.2
	for _, b in m.phys.balls do
		if b.mode == FREE then
			for id = 1, c.nSeg do
				if c.sKind[id] == Layout.SEG_DROP then
					local ax, ay, dx, dy = c.sx[id], c.sy[id], c.sdx[id], c.sdy[id]
					local u = math.clamp(((b.x - ax) * dx + (b.y - ay) * dy) * c.sInv[id], 0, 1)
					local qx, qy = b.x - (ax + dx * u), b.y - (ay + dy * u)
					if qx * qx + qy * qy < reach * reach then
						return false
					end
				end
			end
		end
	end
	return true
end

-- live(m): balls in play, the ones owed to the plunger among them. A ball locked in a pod is not in play.
function Machine.live(m: State): number
	local n = m.queue
	for _, b in m.phys.balls do
		if b.mode ~= GONE and not (b.mode == HELD and b.timer < 0) then
			n += 1
		end
	end
	return n
end

local function inLane(b: Physics.Ball, tbl: Table): boolean
	return b.mode == FREE and b.x > Layout.FIELD_X1 and b.y < tbl.def.plunger.laneTop
end

-- the ball sitting on the plunger, if there is one
local function onPlunger(m: State, tbl: Table): number
	local p = tbl.def.plunger
	for i, b in m.phys.balls do
		if b.mode == FREE and b.x > Layout.FIELD_X1 and b.y < p.y + 0.04 and b.vy < 0.3 and b.vy > -0.3 then
			return i
		end
	end
	return 0
end

local function startBall(m: State, tbl: Table, out: { number })
	local phys = m.phys
	for i = #phys.balls, 1, -1 do
		phys.balls[i] = nil
	end
	phys.dead = false
	m.phase = PLAY
	m.launched = false
	m.saveLeft = 0
	m.graceLeft = 0
	m.skillLeft = 0
	m.pull = 0
	m.bob = 0
	m.nudgeCool = 0
	m.thumpCool = 0
	m.warnings = 0
	m.tilted = false
	m.forfeit = false
	m.forfeitLeft = 0
	m.queue = 0
	m.feedIn = 0
	m.autoIn = 0
	m.quiet = 0
	m.ballTicks = 0
	local p = tbl.def.plunger
	Physics.addBall(phys, p.x, p.y, 0, 0)
	push(out, CUE.BALL_START, m.up, m.ball)
	tbl.sheet.ballStart(m, m.sheets[m.up], tbl, out)
	if m.say == 0 or m.sayLeft == 0 then
		Machine.callout(m, out, SAY.PLUNGE, 0)
	end
end

function Machine.new(tbl: Table, seed: number, players: number): State
	assert(players >= 1 and players <= Machine.MAX_PLAYERS, "one to four players")
	local m: State = {
		phys = Physics.new(tbl.c, seed),
		phase = PLAY,
		players = players,
		up = 1,
		ball = 1,
		scores = table.create(players, 0),
		extras = table.create(players, 0),
		sheets = {},
		stats = {},
		shootAgain = false,
		launched = false,
		saveLeft = 0,
		graceLeft = 0,
		skillLeft = 0,
		pull = 0,
		prev = 0,
		bob = 0,
		nudgeCool = 0,
		thumpCool = 0,
		warnings = 0,
		tilted = false,
		forfeit = false,
		forfeitLeft = 0,
		gone = table.create(players, false),
		queue = 0,
		feedIn = 0,
		autoIn = 0,
		quiet = 0,
		bonusBase = 0,
		bonusMult = 1,
		bonusLeft = 0,
		bonusChunk = 0,
		bonusTimer = 0,
		say = SAY.FREE_PLAY,
		sayValue = 0,
		sayLeft = 0,
		ballTicks = 0,
	}
	for i = 1, players do
		m.sheets[i] = tbl.sheet.init()
		m.stats[i] = { bumpers = 0, ramps = 0, targets = 0, bestBonus = 0, balls = 0, extraBalls = 0 }
	end
	local out: { number } = {}
	startBall(m, tbl, out)
	return m
end

-- clone(state): a deep copy (the state is plain data, so this is also what crosses the wire).
local function copy(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = copy(x)
	end
	return out
end
function Machine.clone(m: State): State
	return copy(m)
end

local function endBall(m: State, tbl: Table, out: { number })
	local phys = m.phys
	for i = #phys.balls, 1, -1 do
		phys.balls[i] = nil
	end
	local base, mult = 0, 1
	if not m.tilted then
		base, mult = tbl.sheet.bonus(m, m.sheets[m.up])
	end
	local total = base * mult
	m.phase = BONUS
	m.bonusBase = base
	m.bonusMult = mult
	m.bonusLeft = total
	m.bonusChunk = math.ceil(total / Machine.BONUS_STEPS)
	m.bonusTimer = if total > 0 then Machine.BONUS_STEP_TICKS else Machine.BONUS_HOLD // 2
	m.queue = 0
	m.feedIn = 0
	m.autoIn = 0
	m.pull = 0
	m.saveLeft = 0
	m.graceLeft = 0
	m.skillLeft = 0
	local st = m.stats[m.up]
	st.balls += 1
	if total > st.bestBonus then
		st.bestBonus = total
	end
	push(out, CUE.BALL_END, m.up, total)
	if not m.tilted then
		Machine.callout(m, out, SAY.BONUS, total)
	end
end

local function nextBall(m: State, tbl: Table, out: { number })
	-- an extra ball is the same player's ball again; one owed to a player who has gone is owed to nobody
	local again = m.shootAgain and not m.gone[m.up]
	m.shootAgain = false
	if again then
		m.stats[m.up].extraBalls += 1
		Machine.callout(m, out, SAY.SHOOT_AGAIN, m.up)
		startBall(m, tbl, out)
		return
	end
	-- the next player who is still here (a retired player's balls are passed over)
	repeat
		m.up += 1
		if m.up > m.players then
			m.up = 1
			m.ball += 1
		end
	until m.ball > Machine.BALLS or not m.gone[m.up]
	if m.ball > Machine.BALLS then
		m.up = 1
		m.ball = Machine.BALLS
		m.phase = OVER
		m.phys.dead = true
		push(out, CUE.GAME_OVER, 0, 0)
		Machine.callout(m, out, SAY.GAME_OVER, 0)
		return
	end
	m.say = 0
	m.sayLeft = 0
	startBall(m, tbl, out)
end

local function tilt(m: State, tbl: Table, out: { number })
	m.tilted = true
	m.phys.dead = true
	m.saveLeft = 0
	m.graceLeft = 0
	m.skillLeft = 0
	m.queue = 0
	m.feedIn = 0
	-- nothing stays behind in a hole
	for _, b in m.phys.balls do
		if b.mode == HELD then
			b.timer = 1
		end
	end
	tbl.sheet.tilted(m, m.sheets[m.up], tbl, out)
	push(out, CUE.TILT, m.up, 0)
	Machine.callout(m, out, SAY.TILT, 0)
end

local function nudge(m: State, tbl: Table, out: { number }, way: number)
	local phys = m.phys
	-- a shove moves only a ball that is out on the playfield
	local any = false
	for _, b in phys.balls do
		if b.mode == FREE and not inLane(b, tbl) then
			any = true
		end
	end
	push(out, CUE.NUDGE, way, 0)
	if not any or m.tilted then
		return
	end
	if way == 1 then
		Physics.nudge(phys, Machine.NUDGE_SIDE, 0.15)
	elseif way == 2 then
		Physics.nudge(phys, -Machine.NUDGE_SIDE, 0.15)
	elseif way == 3 then
		Physics.nudge(phys, 0, Machine.NUDGE_UP)
	else
		local side = if Physics.rand(phys) < 0.5 then -0.4 else 0.4
		Physics.nudge(phys, side, 0.3)
	end
	m.bob += if way == 4 then Machine.THUMP_BOB else 1
	if m.bob > Machine.BOB_LIMIT then
		m.bob = Machine.BOB_LIMIT
		if way == 4 then
			-- a thump from outside can be the swing that warns, but it never tilts and never spends the last
			-- warning: that one is the player's own, so their next honest nudge is at worst a warning
			if m.warnings < Machine.WARNINGS - 1 then
				m.warnings += 1
				push(out, CUE.TILT_WARN, m.warnings, 0)
			end
			Machine.callout(m, out, SAY.THUMP, 0)
		elseif m.warnings < Machine.WARNINGS then
			m.warnings += 1
			push(out, CUE.TILT_WARN, m.warnings, 0)
			Machine.callout(m, out, SAY.TILT_WARNING, m.warnings)
		else
			tilt(m, tbl, out)
		end
	elseif way == 4 then
		Machine.callout(m, out, SAY.THUMP, 0)
	end
end

local CUE_OF: { [number]: number } = {
	[EV.WALL] = CUE.WALL,
	[EV.POST] = CUE.POST,
	[EV.BUMPER] = CUE.BUMPER,
	[EV.SLING] = CUE.SLING,
	[EV.STANDUP] = CUE.STANDUP,
	[EV.DROP] = CUE.DROP,
	[EV.ROLLOVER] = CUE.ROLLOVER,
	[EV.SPIN] = CUE.SPIN,
	[EV.SAUCER] = CUE.SAUCER,
	[EV.EJECT] = CUE.EJECT,
	[EV.RAIL_IN] = CUE.RAMP_IN,
	[EV.RAIL_OUT] = CUE.RAMP_OUT,
	[EV.FLIPPER] = CUE.FLIPPER_HIT,
	[EV.FLIP_UP] = CUE.FLIP_UP,
	[EV.FLIP_DOWN] = CUE.FLIP_DOWN,
	[EV.BALLS] = CUE.BALLS_CLICK,
	[EV.DRAIN] = CUE.DRAIN,
	[EV.GATE] = CUE.GATE,
}
-- what closes the skill shot: the ball has got into the game
local ENDS_SKILL: { [number]: boolean } = {
	[EV.BUMPER] = true,
	[EV.SLING] = true,
	[EV.STANDUP] = true,
	[EV.DROP] = true,
	[EV.FLIPPER] = true,
	[EV.RAIL_IN] = true,
	[EV.SAUCER] = true,
}

-- step(table, state, buttons, out): one tick of 1/240 s. buttons is a sum of BTN bits; out receives cues.
function Machine.step(tbl: Table, m: State, buttons: number, out: { number })
	local phase = m.phase
	if phase == OVER then
		return
	end
	local phys = m.phys
	local c = tbl.c
	local sheet = tbl.sheet
	local t = m.sheets[m.up]
	local prev = m.prev
	m.prev = buttons
	table.clear(ev)

	if m.sayLeft > 0 then
		m.sayLeft -= 1
	end

	if phase == BONUS then
		-- the flippers fall; the bonus is counted out
		Physics.step(c, phys, false, false, ev)
		m.bonusTimer -= 1
		if m.bonusTimer <= 0 then
			if m.bonusLeft > 0 then
				local chunk = math.min(m.bonusChunk, m.bonusLeft)
				m.bonusLeft -= chunk
				m.scores[m.up] += chunk
				push(out, CUE.BONUS_TICK, m.up, chunk)
				m.bonusTimer = if m.bonusLeft > 0 then Machine.BONUS_STEP_TICKS else Machine.BONUS_HOLD
			else
				nextBall(m, tbl, out)
			end
		end
		return
	end

	local forfeit = m.forfeit
	if forfeit then
		buttons = 0
	end
	local left = band(buttons, BTN.LEFT) ~= 0
	local right = band(buttons, BTN.RIGHT) ~= 0
	local pressed = band(buttons, bit32.bnot(prev))
	m.ballTicks += 1

	if not m.tilted then
		if band(pressed, BTN.LEFT) ~= 0 then
			sheet.flip(m, t, true)
		end
		if band(pressed, BTN.RIGHT) ~= 0 then
			sheet.flip(m, t, false)
		end
	end

	-- nudges
	if m.nudgeCool > 0 then
		m.nudgeCool -= 1
	end
	if m.bob > 0 then
		m.bob -= 1 / Machine.BOB_SETTLE
		if m.bob < 0 then
			m.bob = 0
		end
	end
	if m.thumpCool > 0 then
		m.thumpCool -= 1
	end
	if band(pressed, BTN.THUMP) ~= 0 and m.thumpCool == 0 then
		m.thumpCool = Machine.THUMP_COOL
		nudge(m, tbl, out, 4)
	end
	if band(pressed, BTN.NUDGE_L + BTN.NUDGE_R + BTN.NUDGE_UP) ~= 0 and m.nudgeCool == 0 then
		m.nudgeCool = Machine.NUDGE_COOL
		if band(pressed, BTN.NUDGE_L) ~= 0 then
			nudge(m, tbl, out, 1)
		elseif band(pressed, BTN.NUDGE_R) ~= 0 then
			nudge(m, tbl, out, 2)
		else
			nudge(m, tbl, out, 3)
		end
	end

	-- the plunger
	local p = tbl.def.plunger
	local resting = onPlunger(m, tbl)
	if resting == 0 then
		m.pull = 0
		m.autoIn = 0
	else
		local auto = m.autoIn > 0 or m.tilted or forfeit
		if auto then
			if m.autoIn == 0 then
				m.autoIn = Machine.AUTO_TICKS
			end
			m.autoIn -= 1
			m.pull = 0
			if m.autoIn == 0 then
				-- the machine's own kicker is never twice the same strength (seeded), so a ball it gives back
				-- does not come down the table the same way every time
				local pull = p.autoPull + (Physics.rand(phys) * 2 - 1) * Machine.AUTO_SPREAD
				pull = math.clamp(pull, 0, 1)
				Physics.launch(phys, resting, p.vMin + (p.vMax - p.vMin) * pull)
				push(out, CUE.PLUNGE, 0, pull)
			end
		elseif buttons >= Machine.PULL_UNIT then
			-- an analogue hand: the rod follows it, quickly but not at once
			local want = Machine.pullOf(buttons) / Machine.PULL_LEVELS * p.pullTicks
			local rate = p.pullTicks / Machine.ROD_TICKS
			if want > m.pull + rate then
				m.pull += rate
			elseif want < m.pull - rate then
				m.pull -= rate
			else
				m.pull = want
			end
		elseif band(buttons, BTN.PLUNGE) ~= 0 then
			if m.pull < p.pullTicks then
				m.pull += 1
				if m.pull > p.pullTicks then
					m.pull = p.pullTicks
				end
			end
		elseif m.pull > 0 then
			local strength = m.pull / p.pullTicks
			m.pull = 0
			Physics.launch(phys, resting, p.vMin + (p.vMax - p.vMin) * strength)
			push(out, CUE.PLUNGE, m.up, strength)
		end
	end

	Physics.step(c, phys, left, right, ev)

	-- what the switches saw
	local drains = 0
	for i = 1, #ev, 4 do
		local code, ref, value, ball = ev[i], ev[i + 1], ev[i + 2], ev[i + 3]
		local cue = CUE_OF[code]
		if cue then
			push(out, cue, ref, value)
		end
		if code == EV.DRAIN then
			drains += 1
		elseif not m.tilted then
			-- (a tilted machine's switches are dead: the sheet sees nothing a dead ball rolls over, and nothing
			-- it hits is counted)
			if code == EV.BUMPER and value == 1 then
				Machine.stat(m, "bumpers")
			elseif code == EV.STANDUP or code == EV.DROP then
				Machine.stat(m, "targets")
			elseif code == EV.RAIL_OUT and value == 1 then
				Machine.stat(m, "ramps")
			end
			sheet.event(m, t, tbl, out, code, ref, value, ball)
			if ENDS_SKILL[code] then
				m.skillLeft = 0
			end
		end
	end

	-- the ball leaves the shooter lane: the ball save and the skill shot start
	local balls = phys.balls
	if not m.launched then
		for _, b in balls do
			if b.mode == FREE and b.x < Layout.FIELD_X1 then
				m.launched = true
				if not m.tilted and not forfeit then
					m.saveLeft = sheet.saveTicks
					m.skillLeft = Machine.SKILL_TICKS
				end
				break
			end
		end
	else
		if m.saveLeft > 0 then
			m.saveLeft -= 1
			if m.saveLeft == 0 then
				m.graceLeft = Machine.SAVE_GRACE
			end
		elseif m.graceLeft > 0 then
			m.graceLeft -= 1
		end
		if m.skillLeft > 0 then
			m.skillLeft -= 1
		end
	end

	-- drains: given back inside the ball save, otherwise gone
	if drains > 0 then
		Physics.removeGone(phys)
		for _ = 1, drains do
			local saved = not m.tilted and not forfeit and (m.saveLeft > 0 or m.graceLeft > 0)
			if saved then
				m.queue += 1
				push(out, CUE.SAVE, m.up, 0)
				Machine.callout(m, out, SAY.BALL_SAVED, 0)
			end
			sheet.drained(m, t, tbl, out, saved)
		end
	end

	if not m.tilted then
		sheet.tick(m, t, tbl, out)
	end

	-- balls the machine owes come up to the plunger one at a time, when the lane is clear
	if m.queue > 0 then
		local clear = true
		for _, b in balls do
			if inLane(b, tbl) then
				clear = false
				break
			end
		end
		if not clear then
			m.feedIn = 0
		else
			if m.feedIn == 0 then
				m.feedIn = Machine.FEED_TICKS
			end
			m.feedIn -= 1
			if m.feedIn == 0 then
				m.queue -= 1
				Physics.addBall(phys, p.x, p.y, 0, 0)
				m.autoIn = Machine.AUTO_TICKS
			end
		end
	end

	-- is the ball over?
	local live = m.queue
	local loose, moving = false, false
	for _, b in balls do
		if not (b.mode == HELD and b.timer < 0) then
			live += 1
			if b.mode ~= FREE then
				moving = true
			elseif not inLane(b, tbl) then
				loose = true
				if b.vx * b.vx + b.vy * b.vy > 0.09 then
					moving = true
				end
			end
		end
	end
	if live == 0 then
		endBall(m, tbl, out)
		return
	end

	-- a ball that lies still where nobody is holding it (perched on a post, say) is searched for
	if not loose or moving or left or right then
		m.quiet = 0
	else
		m.quiet += 1
		if m.quiet >= Machine.SEARCH_TICKS then
			m.quiet = 0
			for _, b in balls do
				if b.mode == FREE and not inLane(b, tbl) then
					b.vx += (Physics.rand(phys) - 0.5) * 3
					b.vy += 1 + Physics.rand(phys) * 2
					b.asleep = false
					b.still = 0
					b.firm = 0
				end
			end
			push(out, CUE.SEARCH, 0, 0)
			if not m.tilted then
				Machine.callout(m, out, SAY.BALL_SEARCH, 0)
			end
		end
	end

	if forfeit then
		m.forfeitLeft -= 1
		if m.forfeitLeft <= 0 then
			endBall(m, tbl, out)
		end
	end
end

-- forfeit(table, state, out): the player has walked away from this ball (an idle turn, a bite): the flippers
-- go dead, the machine launches the ball itself and it is left to drain; no ball save, no bonus is lost that
-- was earned. The caller keeps stepping; the ball ends within FORFEIT_TICKS.
function Machine.forfeit(tbl: Table, m: State, out: { number })
	if m.phase ~= PLAY or m.forfeit then
		return
	end
	m.forfeit = true
	m.forfeitLeft = Machine.FORFEIT_TICKS
	m.phys.dead = true
	m.saveLeft = 0
	m.graceLeft = 0
	m.skillLeft = 0
	m.queue = 0
	m.feedIn = 0
	for _, b in m.phys.balls do
		if b.mode == HELD then
			b.timer = 1
		end
	end
	-- whatever the sheet had running (a countdown) is put away, as on a tilt
	if not m.tilted then
		tbl.sheet.tilted(m, m.sheets[m.up], tbl, out)
	end
end

-- retire(table, state, seat, out): this player has gone for good (walked away, bitten, removed). Their score
-- stands; if their ball is in play it is played out dead (forfeit) and every later ball of theirs is passed
-- over. When nobody is left the game is over at once.
function Machine.retire(tbl: Table, m: State, seat: number, out: { number })
	if m.phase == OVER or seat < 1 or seat > m.players or m.gone[seat] then
		return
	end
	m.gone[seat] = true
	local left = false
	for i = 1, m.players do
		if not m.gone[i] then
			left = true
		end
	end
	if not left then
		for i = #m.phys.balls, 1, -1 do
			m.phys.balls[i] = nil
		end
		m.phase = OVER
		m.phys.dead = true
		push(out, CUE.GAME_OVER, 0, 0)
		Machine.callout(m, out, SAY.GAME_OVER, 0)
	elseif m.up == seat then
		-- an extra ball owed to them is owed to nobody now
		m.shootAgain = false
		if m.phase == PLAY then
			Machine.forfeit(tbl, m, out)
		end
	end
end

-- lamps(table, state, into): every lamp on the playfield by number: 0 dark, 1 lit, 2 flashing. A tilted
-- machine is dark.
function Machine.lamps(tbl: Table, m: State, into: { number }): { number }
	local n = #tbl.def.lamps
	for i = 1, n do
		into[i] = 0
	end
	if m.phase ~= OVER and not m.tilted then
		tbl.sheet.lamps(m, m.sheets[m.up], tbl, into)
		local again = tbl.ix.lamp.shoot_again
		if again then
			if m.shootAgain then
				into[again] = 1
			end
			if m.phase == PLAY and (m.saveLeft > 0 or (not m.launched and not m.tilted)) then
				into[again] = 2
			end
		end
	end
	return into
end

return Machine
