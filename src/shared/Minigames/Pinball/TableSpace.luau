--!strict
-- ReplicatedStorage.Shared.Minigames.Pinball.TableSpace
-- SPACE SQUIRREL: the third machine (checklist PIN-R6), the flow table. Two ramps that feed each other (the
-- left ramp, shot from the right flipper, drops the ball in the left inlane; the right ramp, shot from the
-- left flipper, in the right inlane), an orbit right round the top of the table, two lock pods and a
-- three-ball multiball. Scores run to the millions.
-- The playfield: the orbit lane inside both rails and under the arch; inside it the asteroid field of three
-- pop bumpers, reached up the middle or through the docking gap top right (a soft plunge falls through it:
-- the skill shot); the two ramps; a lock pod beside each ramp; F-U and E-L standup targets on the rails.
-- The rule sheet (one goal: LIFTOFF):
--   * F-U-E-L lights the locks. A ball shot into a lit pod stays there and a new ball comes to the plunger.
--   * With both pods full, either ramp starts the countdown: 3, 2, 1, LIFTOFF, both pods fire and three balls
--     are in play. During multiball every ramp and every orbit is a jackpot; it ends when one ball is left.
--   * Ramps and orbits made within four seconds of each other are a combo: each one in the chain is worth
--     one more times its value (up to 5x).
--   * Three orbits in one ball light the extra ball at the left pod (once a game).
--   * End of ball: 10,000 for every ramp and orbit of that ball, times one more for every ball locked.
-- Geometry is in studs in Layout's playfield frame. Pure data and pure functions; Lune-tested
-- (tests/unit/pinball_tables.spec.luau, pinball_rules.spec.luau).
-- Interface: a Machine.Table (id, title, def, ix, c, sheet) plus POINTS, SAY, COMBO_TICKS, COUNT_TICKS, LOCKS

local Layout = require("./Layout")
local Machine = require("./Machine")
local Physics = require("./Physics")

local def = Layout.new("pinball_space", "SPACE SQUIRREL")
def.slopeDeg = 6.5
def.gravity = Layout.gravityFor(6.5)
def.plunger.vMin = 4.7
def.plunger.vMax = 9.2

Layout.addShell(def)
Layout.addBottom(def, { gap = 0.22, outlane = 0.17, inlane = 0.17, pivotY = 0.62 })

local XC = Layout.XC
local X1 = Layout.FIELD_X1
local function mx(x: number): number
	return 2 * XC - x
end

-- the orbit's inner guide: up the left, round under the arch, down the right, with the docking gap top right
local OR, OY = 0.885, 3.7
do
	local left = { XC - OR, 2.6 }
	for _, v in Layout.arc(XC, OY, OR, 180, 66, 20) do
		table.insert(left, v)
	end
	Layout.wall(def, "metal", left)
	local right = Layout.arc(XC, OY, OR, 34, 0, 6)
	table.insert(right, XC + OR)
	table.insert(right, 2.6)
	Layout.wall(def, "metal", right)
	Layout.post(def, XC - OR, 2.6)
	Layout.post(def, XC + OR, 2.6)
	local g1 = Layout.arc(XC, OY, OR, 66, 66, 1)
	local g2 = Layout.arc(XC, OY, OR, 34, 34, 1)
	Layout.post(def, g1[1], g1[2])
	Layout.post(def, g2[1], g2[2])
	table.insert(def.sensors, { id = "dock", kind = "rollover", x1 = g1[1], y1 = g1[2], x2 = g2[1], y2 = g2[2] })
	Layout.lamp(def, "dock", (g1[1] + g2[1]) / 2 - 0.1, (g1[2] + g2[2]) / 2 - 0.1, "blue")
end
table.insert(def.sensors, { id = "orbit_l", kind = "rollover", x1 = 0, y1 = 3.0, x2 = XC - OR, y2 = 3.0 })
table.insert(def.sensors, { id = "orbit_r", kind = "rollover", x1 = XC + OR, y1 = 3.0, x2 = X1, y2 = 3.0 })
table.insert(def.sensors, { id = "orbit_top", kind = "rollover", x1 = XC, y1 = OY + OR, x2 = XC, y2 = 4.9 })
Layout.lamp(def, "orbit_l", 0.11, 2.45, "blue")
Layout.lamp(def, "orbit_r", X1 - 0.11, 2.45, "blue")

-- the asteroid field
table.insert(def.bumpers, { id = "bumper_1", x = 0.84, y = 3.98, r = 0.11 })
table.insert(def.bumpers, { id = "bumper_2", x = 1.375, y = 3.98, r = 0.11 })
table.insert(def.bumpers, { id = "bumper_3", x = XC, y = 3.56, r = 0.11 })
for i, b in def.bumpers do
	Layout.lamp(def, `bumper_{i}`, b.x, b.y, "blue")
end

-- the two ramps
do
	local lx, ly = Layout.inlaneDrop(def, "left")
	local pts = {
		0.75,
		2.62,
		0,
		0.58,
		3.32,
		0.25,
		0.44,
		3.62,
		0.3,
		0.24,
		3.66,
		0.3,
		0.1,
		3.3,
		0.3,
		0.085,
		2.3,
		0.24,
		0.1,
		1.8,
		0.16,
		lx,
		ly,
		0,
	}
	local body =
		Layout.addRamp(def, { id = "ramp_l", pts = pts, mouth = 0.11, minSpeed = 0.6, exitSpeed = 1.2, drag = 0.2 })
	local mirrored: { number } = {}
	for i = 1, #pts, 3 do
		table.insert(mirrored, mx(pts[i]))
		table.insert(mirrored, pts[i + 1])
		table.insert(mirrored, pts[i + 2])
	end
	Layout.addRamp(def, { id = "ramp_r", pts = mirrored, mouth = 0.11, minSpeed = 0.6, exitSpeed = 1.2, drag = 0.2 })
	Layout.lamp(def, "ramp_l", 0.82, 2.4, "white")
	Layout.lamp(def, "ramp_r", mx(0.82), 2.4, "white")

	-- The lock pods. Each is the blind end of the alley between the orbit's inner guide and a ramp: a kick-out
	-- hole under a horseshoe, shot from the far flipper. A roof from the guide down to the back of the ramp
	-- keeps a ball from the asteroid field out of the alley and sheds it into the middle of the table; every
	-- wall of the alley slopes, so a ball that is not swallowed rolls back out.
	local PX, PY, PR = 0.44, 2.86, 0.125
	local alley = { XC - OR, 2.6 }
	for _, v in Layout.arc(PX, PY, PR, 200, 20, 10) do
		table.insert(alley, v)
	end
	-- the horseshoe's right end meets the ramp's left side
	local endY = alley[#alley]
	local u = (endY - body[2]) / (body[4] - body[2])
	table.insert(alley, body[1] + (body[3] - body[1]) * u)
	table.insert(alley, endY)
	local roof = { XC - OR, 3.32, body[5], body[6] }
	Layout.wall(def, "metal", alley)
	Layout.wall(def, "metal", Layout.mirror(alley))
	Layout.wall(def, "metal", roof)
	Layout.wall(def, "metal", Layout.mirror(roof))
	Layout.post(def, body[5], body[6])
	Layout.post(def, mx(body[5]), body[6])
	table.insert(
		def.saucers,
		{ id = "pod_1", x = PX, y = PY, r = 0.085, maxSpeed = 7, vx = 1.1, vy = -3.0, holdTicks = 240 }
	)
	table.insert(
		def.saucers,
		{ id = "pod_2", x = mx(PX), y = PY, r = 0.085, maxSpeed = 7, vx = -1.1, vy = -3.0, holdTicks = 240 }
	)
end
Layout.lamp(def, "pod_1", 0.52, 2.62, "green")
Layout.lamp(def, "pod_2", mx(0.52), 2.62, "green")
Layout.lamp(def, "extra_ball", 0.58, 2.48, "red")

-- F-U on the left rail, E-L on the right
do
	local function standup(id: string, x1: number, y1: number, x2: number, y2: number, lx: number, ly: number)
		table.insert(def.targets, { id = id, kind = "standup", x1 = x1, y1 = y1, x2 = x2, y2 = y2 })
		Layout.lamp(def, id, lx, ly, "yellow")
	end
	standup("fuel_f", 0.04, 2.02, 0.09, 2.13, 0.2, 2.0)
	standup("fuel_u", 0.09, 2.15, 0.14, 2.26, 0.25, 2.13)
	Layout.wall(def, "wood", { 0.0, 2.0, 0.04, 2.02 })
	Layout.wall(def, "wood", { 0.14, 2.26, 0.0, 2.5 })
	standup("fuel_e", X1 - 0.14, 2.26, X1 - 0.09, 2.15, X1 - 0.25, 2.13)
	standup("fuel_l", X1 - 0.09, 2.13, X1 - 0.04, 2.02, X1 - 0.2, 2.0)
	Layout.wall(def, "wood", { X1, 2.0, X1 - 0.04, 2.02 })
	Layout.wall(def, "wood", { X1 - 0.14, 2.26, X1, 2.5 })
end

-- a kink in each rail above the outlanes leans a ball coming down out of the orbit toward the inlane
Layout.wall(def, "wood", { 0.0, 1.92, 0.15, 1.66 })
Layout.wall(def, "wood", { X1, 1.92, X1 - 0.15, 1.66 })
Layout.post(def, 0.15, 1.66)
Layout.post(def, X1 - 0.15, 1.66)

for i = 1, 3 do
	Layout.lamp(def, `count_{i}`, XC - 0.4 + 0.2 * i, 2.1, "red")
end
for i = 1, 5 do
	Layout.lamp(def, `combo_{i}`, XC - 0.36 + 0.12 * i, 1.6, "white")
end
Layout.lamp(def, "jackpot", XC, 2.6, "red")
Layout.lamp(def, "shoot_again", XC, 0.35, "red")

local ix = Layout.index(def)

-- ---------------------------------------------------------------------------------------------------------
-- The rule sheet
-- ---------------------------------------------------------------------------------------------------------
local CUE, EV = Machine.CUE, Physics.EV

local SAY = {
	DOCKED = 101,
	LOCKS_LIT = 102,
	LOCKED = 103,
	READY = 104,
	COUNT = 105,
	LIFTOFF = 106,
	JACKPOT = 107,
	COMBO = 108,
	RAMP = 109,
	ORBIT = 110,
	MULTIBALL_OVER = 111,
}
local POINTS = {
	ramp = 20000,
	orbit = 15000,
	jackpot = 100000,
	fuel = 5000,
	fuelAgain = 1000,
	pod = 5000,
	lock = 10000,
	dock = 2500,
	docked = 50000,
	bumper = 1000,
	sling = 500,
	inlane = 2500,
	outlane = 10000,
	bonusEach = 10000,
}
local COMBO_TICKS = 960 -- four seconds
local COMBO_MAX = 5
local ARM_TICKS = 720 -- an orbit is a side lane, then the top of the arch, within three seconds
local COUNT_TICKS = 720 -- 3, 2, 1
local ORBITS_FOR_EXTRA = 3
local LOCKS = 2

local FUEL = { ix.target.fuel_f, ix.target.fuel_u, ix.target.fuel_e, ix.target.fuel_l }
local FUEL_NAMES = { "f", "u", "e", "l" }

local function bit(n: number, i: number): boolean
	return bit32.band(n, bit32.lshift(1, i - 1)) ~= 0
end

local function liftoff(m: Machine.State, t: Machine.Numbers, out: { number })
	-- the pods fire whatever they hold; the plunger makes the three up
	local held = 0
	for _, b in m.phys.balls do
		if b.mode == Physics.HELD and b.timer < 0 then
			held += 1
			b.timer = 1 + 48 * (held - 1)
		end
	end
	Machine.feed(m, LOCKS - held)
	t.multi = 1
	t.locked = 0
	t.fuel = 0
	t.locksLit = 0
	t.multiballs += 1
	Machine.callout(m, out, SAY.LIFTOFF, 0)
	Machine.cue(out, CUE.JINGLE, 6, 0)
end

-- a ramp or an orbit made: the combo chain, the jackpot in multiball, the countdown
local function flowShot(m: Machine.State, t: Machine.Numbers, out: { number }, ramp: boolean)
	if t.comboLeft > 0 and t.combo < COMBO_MAX then
		t.combo += 1
	elseif t.comboLeft == 0 then
		t.combo = 1
	end
	t.comboLeft = COMBO_TICKS
	t.flow += 1
	local value
	if t.multi == 1 then
		value = POINTS.jackpot * t.combo
		t.jackpots += 1
		Machine.callout(m, out, SAY.JACKPOT, value)
		Machine.cue(out, CUE.JINGLE, 5, t.combo)
	else
		value = (if ramp then POINTS.ramp else POINTS.orbit) * t.combo
		if t.combo > 1 then
			Machine.callout(m, out, SAY.COMBO, value)
		else
			Machine.callout(m, out, if ramp then SAY.RAMP else SAY.ORBIT, value)
		end
		Machine.cue(out, CUE.JINGLE, if ramp then 1 else 2, t.combo)
	end
	Machine.add(m, value)
	if not ramp then
		t.orbits += 1
		Machine.stat(m, "orbits")
		if t.orbits == ORBITS_FOR_EXTRA and m.extras[m.up] == 0 and t.extraLit == 0 then
			t.extraLit = 1
			Machine.callout(m, out, Machine.SAY.EXTRA_BALL_LIT, 0)
		end
	elseif t.locked >= LOCKS and t.multi == 0 and t.count == 0 then
		t.count = COUNT_TICKS
		Machine.callout(m, out, SAY.COUNT, 3)
	end
end

local sheet: Machine.Sheet = {
	saveTicks = 2160, -- nine seconds
	maxScorePerSec = 600000,
	scoreScale = "a good game is 1,500,000; five million is a great one",
	text = {
		[101] = "DOCKED! SKILL SHOT",
		[102] = "F-U-E-L! THE LOCKS ARE LIT",
		[103] = "BALL LOCKED",
		[104] = "BOTH PODS FULL: SHOOT A RAMP",
		[105] = "COUNTDOWN",
		[106] = "LIFTOFF! MULTIBALL",
		[107] = "JACKPOT",
		[108] = "COMBO",
		[109] = "RAMP",
		[110] = "ORBIT",
		[111] = "BACK TO ONE BALL",
	},
	init = function(): Machine.Numbers
		return {
			fuel = 0, -- bits: F-U-E-L lit
			locksLit = 0,
			locked = 0, -- balls this player has locked (the count is the player's; the pods are emptied between balls)
			count = 0, -- ticks of countdown left
			multi = 0,
			multiballs = 0,
			jackpots = 0,
			combo = 0,
			comboLeft = 0,
			flow = 0, -- ramps and orbits on this ball
			orbits = 0, -- on this ball
			armLeft = 0, -- ticks left in which the top of the arch completes an orbit
			extraLit = 0,
		}
	end,
	ballStart = function(_m, t, _tbl, _out)
		t.count = 0
		t.multi = 0
		t.combo = 0
		t.comboLeft = 0
		t.flow = 0
		t.orbits = 0
		t.armLeft = 0
	end,
	flip = function(_m, _t, _left) end,
	event = function(m, t, _tbl, out, code, ref, value, ball)
		if code == EV.BUMPER then
			if value == 1 then
				Machine.add(m, POINTS.bumper)
			end
		elseif code == EV.SLING then
			Machine.add(m, POINTS.sling)
		elseif code == EV.RAIL_OUT then
			if value == 1 then
				flowShot(m, t, out, true)
			end
		elseif code == EV.STANDUP then
			for i = 1, 4 do
				if ref == FUEL[i] then
					if bit(t.fuel, i) or t.locksLit == 1 or t.locked >= LOCKS or t.multi == 1 then
						Machine.add(m, POINTS.fuelAgain)
					else
						t.fuel += bit32.lshift(1, i - 1)
						Machine.add(m, POINTS.fuel)
						if t.fuel == 15 then
							t.fuel = 0
							t.locksLit = 1
							Machine.callout(m, out, SAY.LOCKS_LIT, 0)
							Machine.cue(out, CUE.JINGLE, 3, 0)
						end
					end
					return
				end
			end
		elseif code == EV.SAUCER then
			if t.locksLit == 1 and t.locked < LOCKS and t.multi == 0 then
				-- the pod keeps the ball and the plunger serves another
				local b = m.phys.balls[ball]
				if b then
					b.timer = -1
				end
				t.locked += 1
				Machine.feed(m, 1)
				Machine.add(m, POINTS.lock)
				Machine.cue(out, CUE.JINGLE, 4, t.locked)
				if t.locked >= LOCKS then
					t.locksLit = 0
					Machine.callout(m, out, SAY.READY, 0)
				else
					Machine.callout(m, out, SAY.LOCKED, t.locked)
				end
			else
				Machine.add(m, POINTS.pod)
			end
			if ref == ix.saucer.pod_1 and t.extraLit == 1 then
				t.extraLit = 0
				Machine.extraBall(m, out)
			end
		elseif code == EV.ROLLOVER then
			if ref == ix.sensor.orbit_l or ref == ix.sensor.orbit_r then
				-- going up a side lane arms the orbit; coming down one does not
				if value == 1 then
					t.armLeft = ARM_TICKS
				end
			elseif ref == ix.sensor.orbit_top then
				if t.armLeft > 0 then
					t.armLeft = 0
					flowShot(m, t, out, false)
				end
			elseif ref == ix.sensor.dock then
				if m.skillLeft > 0 then
					m.skillLeft = 0
					Machine.add(m, POINTS.docked)
					Machine.callout(m, out, SAY.DOCKED, POINTS.docked)
					Machine.cue(out, CUE.JINGLE, 7, 0)
				else
					Machine.add(m, POINTS.dock)
				end
			elseif ref == ix.sensor.inlane_l or ref == ix.sensor.inlane_r then
				Machine.add(m, POINTS.inlane)
			elseif ref == ix.sensor.outlane_l or ref == ix.sensor.outlane_r then
				Machine.add(m, POINTS.outlane)
			end
		end
	end,
	tick = function(m, t, _tbl, out)
		if t.comboLeft > 0 then
			t.comboLeft -= 1
		end
		if t.armLeft > 0 then
			t.armLeft -= 1
		end
		if t.count > 0 then
			t.count -= 1
			if t.count == 0 then
				liftoff(m, t, out)
			elseif t.count % 240 == 0 then
				Machine.callout(m, out, SAY.COUNT, t.count / 240)
			end
		elseif t.multi == 1 and Machine.live(m) <= 1 then
			t.multi = 0
			Machine.callout(m, out, SAY.MULTIBALL_OVER, 0)
		end
	end,
	drained = function(_m, _t, _tbl, _out, _saved) end,
	bonus = function(_m, t)
		return POINTS.bonusEach * t.flow, 1 + t.locked
	end,
	lamps = function(m, t, _tbl, lamp)
		local L = ix.lamp
		local multi = t.multi == 1
		for i = 1, 4 do
			if bit(t.fuel, i) or t.locksLit == 1 or t.locked >= LOCKS then
				lamp[L[`fuel_{FUEL_NAMES[i]}`]] = 1
			end
		end
		local podLamp = if t.locksLit == 1 and t.locked < LOCKS and not multi then 2 else 0
		lamp[L.pod_1] = podLamp
		lamp[L.pod_2] = podLamp
		local rampLamp = if multi or (t.locked >= LOCKS and t.count == 0) then 2 else 1
		lamp[L.ramp_l] = rampLamp
		lamp[L.ramp_r] = rampLamp
		lamp[L.orbit_l] = if multi then 2 else 1
		lamp[L.orbit_r] = if multi then 2 else 1
		lamp[L.dock] = if m.skillLeft > 0 or not m.launched then 2 else 0
		for i = 1, 3 do
			lamp[L[`bumper_{i}`]] = 1
			-- the countdown lamps go out one a second
			if t.count > (i - 1) * 240 then
				lamp[L[`count_{i}`]] = 2
			elseif t.locked >= i then
				lamp[L[`count_{i}`]] = 1
			end
		end
		if t.comboLeft > 0 then
			for i = 1, COMBO_MAX do
				if i <= t.combo then
					lamp[L[`combo_{i}`]] = 1
				end
			end
		end
		if multi then
			lamp[L.jackpot] = 2
		end
		if t.extraLit == 1 then
			lamp[L.extra_ball] = 2
		end
	end,
	status = function(_m, t)
		if t.multi == 1 then
			return "MULTIBALL! EVERY RAMP AND ORBIT IS A JACKPOT"
		elseif t.count > 0 then
			return `LIFTOFF IN {math.ceil(t.count / 240)}`
		elseif t.extraLit == 1 then
			return "EXTRA BALL IS LIT AT THE LEFT POD"
		elseif t.locked >= LOCKS then
			return "BOTH PODS ARE FULL: SHOOT A RAMP TO START THE COUNTDOWN"
		elseif t.locksLit == 1 then
			return `THE LOCKS ARE LIT: SHOOT A POD ({t.locked} OF {LOCKS} LOCKED)`
		end
		local need = 0
		for i = 1, 4 do
			if not bit(t.fuel, i) then
				need += 1
			end
		end
		return `SPELL F-U-E-L ({need} TO GO) TO LIGHT THE LOCKS`
	end,
}

local TableSpace = {
	id = def.id,
	title = def.title,
	def = def,
	ix = ix,
	c = Layout.compile(def),
	sheet = sheet,
	POINTS = POINTS,
	SAY = SAY,
	COMBO_TICKS = COMBO_TICKS,
	COUNT_TICKS = COUNT_TICKS,
	LOCKS = LOCKS,
}

return TableSpace
