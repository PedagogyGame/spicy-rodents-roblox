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
-- (tests/unit/pinball_layout.spec.luau, pinball_rules.spec.luau, pinball_shots.spec.luau).
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
local POD_SPEED = 6.6 -- a ball crossing a pod's hole faster than this skips over it
local RAMP_MOUTH = 0.16 -- half the width of a ramp's mouth

-- The orbit's inner guide: round under the arch, with the docking gap top right. Its two lower ends are laid
-- further down, once the ramps stand (each runs down to the back of a ramp).
local OR, OY = 0.885, 3.7
local guideLeft = Layout.arc(XC, OY, OR, 180, 66, 20)
local guideRight = Layout.arc(XC, OY, OR, 34, 0, 6)
do
	local g1 = Layout.arc(XC, OY, OR, 66, 66, 1)
	local g2 = Layout.arc(XC, OY, OR, 34, 34, 1)
	-- (the left guide comes down to the gap at a gentle slope: its post is set flush, or a ball would sit on it)
	Layout.endPost(def, g1[1], g1[2], guideLeft[#guideLeft - 3], guideLeft[#guideLeft - 2])
	Layout.post(def, g2[1], g2[2])
	table.insert(def.sensors, { id = "dock", kind = "rollover", x1 = g1[1], y1 = g1[2], x2 = g2[1], y2 = g2[2] })
	Layout.lamp(def, "dock", (g1[1] + g2[1]) / 2 - 0.1, (g1[2] + g2[2]) / 2 - 0.1, "blue")
end
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
	local body = Layout.addRamp(
		def,
		{ id = "ramp_l", pts = pts, mouth = RAMP_MOUTH, minSpeed = 0.6, exitSpeed = 1.2, drag = 0.2 }
	)
	local mirrored: { number } = {}
	for i = 1, #pts, 3 do
		table.insert(mirrored, mx(pts[i]))
		table.insert(mirrored, pts[i + 1])
		table.insert(mirrored, pts[i + 2])
	end
	Layout.addRamp(
		def,
		{ id = "ramp_r", pts = mirrored, mouth = RAMP_MOUTH, minSpeed = 0.6, exitSpeed = 1.2, drag = 0.2 }
	)
	Layout.lamp(def, "ramp_l", 0.82, 2.4, "white")
	Layout.lamp(def, "ramp_r", mx(0.82), 2.4, "white")

	-- F stands at the inner corner of the left ramp's mouth and L at the right ramp's: a standup target facing
	-- down the table, between the ramp and the way up the middle
	do
		local cx, cy = body[7], body[8]
		local x1, y1, x2, y2 = cx - 0.01, cy - 0.045, cx + 0.1, cy - 0.095
		table.insert(def.targets, { id = "fuel_f", kind = "standup", x1 = x1, y1 = y1, x2 = x2, y2 = y2 })
		table.insert(def.targets, { id = "fuel_l", kind = "standup", x1 = mx(x2), y1 = y2, x2 = mx(x1), y2 = y1 })
		local back = { cx, cy, cx + 0.105, cy - 0.085 }
		Layout.wall(def, "plastic", back)
		Layout.wall(def, "plastic", Layout.mirror(back))
		Layout.post(def, cx + 0.105, cy - 0.09, 0.02)
		Layout.post(def, mx(cx + 0.105), cy - 0.09, 0.02)
		Layout.lamp(def, "fuel_f", (x1 + x2) / 2, y2 - 0.1, "yellow")
		Layout.lamp(def, "fuel_l", mx((x1 + x2) / 2), y2 - 0.1, "yellow")
	end

	-- The orbit lanes. Everything outside a ramp is the way into the orbit: the inner guide runs from the back
	-- of the ramp up to the arch, so the mouth of the lane is wide (the same-side flipper's backhand finds it,
	-- and so does a late shot across the table) and narrows as it climbs.
	local left = { body[3], body[4] }
	table.move(guideLeft, 1, #guideLeft, 3, left)
	Layout.wall(def, "metal", left)
	local right = table.clone(guideRight)
	table.insert(right, mx(body[3]))
	table.insert(right, body[4])
	Layout.wall(def, "metal", right)
	-- A roof over the back of each ramp, from part way up the guide down to the ramp's inner corner: without it
	-- the guide and the ramp's back make a pocket that catches every ball that dribbles out of the asteroid
	-- field. With it the ball rolls off toward the middle and falls past the ramp's mouth to the flippers.
	do
		local u = 0.33
		local rx, ry = body[3] + (guideLeft[1] - body[3]) * u, body[4] + (guideLeft[2] - body[4]) * u
		local roof = { rx, ry, body[5], body[6] }
		Layout.wall(def, "plastic", roof)
		Layout.wall(def, "plastic", Layout.mirror(roof))
	end
	local SY = body[4] + 0.07
	local gx = body[3] + (guideLeft[1] - body[3]) * 0.07 / (guideLeft[2] - body[4])
	table.insert(def.sensors, { id = "orbit_l", kind = "rollover", x1 = 0, y1 = SY, x2 = gx, y2 = SY })
	table.insert(def.sensors, { id = "orbit_r", kind = "rollover", x1 = mx(gx), y1 = SY, x2 = X1, y2 = SY })

	-- The lock pods: a kick-out hole in the floor of each orbit lane's mouth. A ball that comes up the lane
	-- slowly drops in; a fast one skips over the hole and goes round the orbit. So the same lane is two shots,
	-- told apart by how hard it is hit: an early, soft backhand for the pod, a later, harder one for the orbit.
	local PX, PY = 0.27, 2.78
	table.insert(
		def.saucers,
		{ id = "pod_1", x = PX, y = PY, r = 0.085, maxSpeed = POD_SPEED, vx = 0.45, vy = -1.2, holdTicks = 240 }
	)
	table.insert(
		def.saucers,
		{ id = "pod_2", x = mx(PX), y = PY, r = 0.085, maxSpeed = POD_SPEED, vx = -0.45, vy = -1.2, holdTicks = 240 }
	)
end
Layout.lamp(def, "pod_1", 0.27, 2.6, "green")
Layout.lamp(def, "pod_2", mx(0.27), 2.6, "green")
Layout.lamp(def, "extra_ball", 0.46, 2.48, "red")

-- F-U-E-L: U on the left rail and E on the right (each flipper's own soft backhand); F and L stand at the
-- inner corners of the two ramp mouths (laid with the ramps, above)
do
	-- (the bump stands far enough out of the rail to be in the path of the soft backhand: a ball flipped as it
	-- starts to roll off the cradle; a harder one passes inside it to the pod and the orbit)
	local UX1, UY1, UX2, UY2 = 0.1, 2.14, 0.2, 2.34
	table.insert(def.targets, { id = "fuel_u", kind = "standup", x1 = UX1, y1 = UY1, x2 = UX2, y2 = UY2 })
	Layout.lamp(def, "fuel_u", UX2 + 0.1, UY1 + 0.03, "yellow")
	Layout.wall(def, "wood", { 0.0, UY1 - 0.08, UX1, UY1 })
	Layout.wall(def, "wood", { UX2, UY2, 0.0, UY2 + 0.28 })
	table.insert(def.targets, { id = "fuel_e", kind = "standup", x1 = X1 - UX2, y1 = UY2, x2 = X1 - UX1, y2 = UY1 })
	Layout.lamp(def, "fuel_e", X1 - UX2 - 0.1, UY1 + 0.03, "yellow")
	Layout.wall(def, "wood", { X1, UY1 - 0.08, X1 - UX1, UY1 })
	Layout.wall(def, "wood", { X1 - UX2, UY2, X1, UY2 + 0.28 })
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
	scoreScale = "a good game is 1,500,000; ten million is a great one",
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
	wants = function(_m, t)
		local list: { number } = {}
		local ramps = { Machine.key(EV.RAIL_OUT, ix.rail.ramp_l), Machine.key(EV.RAIL_OUT, ix.rail.ramp_r) }
		local orbit = Machine.key(EV.ROLLOVER, ix.sensor.orbit_top)
		local pods = { Machine.key(EV.SAUCER, ix.saucer.pod_1), Machine.key(EV.SAUCER, ix.saucer.pod_2) }
		if t.multi == 1 or t.count > 0 or t.locked >= LOCKS then
			-- jackpots, or the ramp that starts the countdown
			table.move(ramps, 1, 2, #list + 1, list)
			table.insert(list, orbit)
			return list
		end
		if t.extraLit == 1 then
			table.insert(list, pods[1])
		end
		if t.locksLit == 1 then
			table.move(pods, 1, 2, #list + 1, list)
		else
			for i = 1, 4 do
				if not bit(t.fuel, i) then
					table.insert(list, Machine.key(EV.STANDUP, FUEL[i]))
				end
			end
		end
		table.move(ramps, 1, 2, #list + 1, list)
		table.insert(list, orbit)
		table.move(pods, 1, 2, #list + 1, list)
		return list
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
