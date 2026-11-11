--!strict
-- Minigames/Pinball/Layout and the three tables as data: every definition is whole and inside the cabinet the
-- alley bakes (checklist C18: one layout module, what is drawn is what is simulated); the three machines are
-- three different playfields, not one recoloured (PIN-R6); the bottom of every table is a proper pinball
-- bottom (two flippers, a slingshot over each, an inlane and an outlane each side, a gap a ball can fall
-- through); the slope is a real table's (PIN-P4).
local Det = require("@shared/Minigames/Pinball/Det")
local Layout = require("@shared/Minigames/Pinball/Layout")
local Machine = require("@shared/Minigames/Pinball/Machine")
local Tables = require("@shared/Minigames/Pinball/Tables")
local Test = require("../lib/Test")

local function count<T>(list: { T }, pred: (T) -> boolean): number
	local n = 0
	for _, v in list do
		if pred(v) then
			n += 1
		end
	end
	return n
end

return function(t: Test.T)
	t.test("Det: sine and cosine from + - * / agree with the library to 1e-12 over the angles a table uses", function()
		for i = -2000, 2000 do
			local a = i * 0.00731
			t.near(Det.sin(a), math.sin(a), 1e-12, `sin {a}`)
			t.near(Det.cos(a), math.cos(a), 1e-12, `cos {a}`)
		end
		t.eq(Det.sin(0), 0)
		t.eq(Det.cos(0), 1)
		t.near(Det.rad(180), math.pi, 1e-15)
	end)

	t.test("C18: the playfield is the cabinet's (2.4 x 4.9 studs) and the ball a real ball on it", function()
		t.eq(Layout.WIDTH, 2.4)
		t.eq(Layout.LENGTH, 4.9)
		-- a 1 1/16 inch ball on a 20.25 inch playfield
		t.near(2 * Layout.BALL_R / Layout.WIDTH, 1.0625 / 20.25, 0.001)
		-- the shooter lane is wide enough for the ball and no wider than two
		local lane = Layout.WIDTH - Layout.FIELD_X1
		t.truthy(lane > 2 * Layout.BALL_R + 0.02 and lane < 4 * Layout.BALL_R, "shooter lane width")
		-- the playfield's pitch in the cabinet: the middle of the playfield is the origin
		local across, up, along = Layout.cabinetPoint(Layout.WIDTH / 2, Layout.LENGTH / 2, 0)
		t.near(across, 0, 1e-12)
		t.near(up, 0, 1e-12)
		t.near(along, 0, 1e-12)
		local _, upBack = Layout.cabinetPoint(0, Layout.LENGTH, 0)
		local _, upFront = Layout.cabinetPoint(0, 0, 0)
		t.truthy(upBack > upFront + 0.5, "the back of the playfield is higher than the front")
	end)

	t.test("PIN-R6: there are exactly the three machines the alley's cabinets name", function()
		t.deepEq(Tables.IDS, { "pinball_acorn", "pinball_rodent", "pinball_space" })
		t.eq(Tables.need("pinball_acorn").title, "ACORN ATTACK")
		t.eq(Tables.need("pinball_rodent").title, "SPICY RODENT")
		t.eq(Tables.need("pinball_space").title, "SPACE SQUIRREL")
		t.eq(Tables.get("pinball_riverside"), nil)
		t.fails(function()
			Tables.need("pinball_riverside")
		end)
	end)

	for _, id in Tables.IDS do
		local tbl = Tables.need(id)
		local def = tbl.def

		t.test(`{def.title}: the definition is whole, inside the cabinet, and compiles`, function()
			local ok, why = Layout.check(def)
			t.truthy(ok, why)
			t.eq(tbl.id, id)
			t.truthy(tbl.c.nSeg > 40, "walls")
			t.eq(tbl.c.nFlip, 2)
			-- every collider is in the grid cell it stands in
			for i = 1, tbl.c.nCir do
				local cell = math.floor(tbl.c.cy[i] / Layout.CELL) * tbl.c.gridW + math.floor(tbl.c.cx[i] / Layout.CELL) + 1
				t.truthy(table.find(tbl.c.grid[cell], -i), `circle {i} in its cell`)
			end
		end)

		t.test(`{def.title}: PIN-P4 the slope is a real table's (6 to 7 degrees) and gravity follows from it`, function()
			t.truthy(def.slopeDeg >= 6 and def.slopeDeg <= 7, "slope")
			t.near(def.gravity, Layout.gravityFor(def.slopeDeg), 1e-9)
			-- a ball rolling the length of the table from rest takes between one and a half and two seconds
			local seconds = math.sqrt(2 * Layout.LENGTH / def.gravity)
			t.truthy(seconds > 1.4 and seconds < 2.0, `fall time {seconds}`)
		end)

		t.test(`{def.title}: a pinball bottom: two flippers, slings, inlanes, outlanes, a gap to lose the ball in`, function()
			local l, r = def.flippers[1], def.flippers[2]
			t.eq(l.button, "left")
			t.eq(r.button, "right")
			t.eq(l.mirror, false)
			t.eq(r.mirror, true)
			-- mirror images about the playfield's centre line
			t.near(l.x + r.x, 2 * Layout.XC, 1e-9)
			t.eq(l.y, r.y)
			-- the flipper is a real flipper's size (3 inches on a 20.25 inch table) and swings 50 to 70 degrees
			t.near(l.len / Layout.WIDTH, 3 / 20.25, 0.02)
			local swing = math.deg(l.up - l.rest)
			t.truthy(swing >= 50 and swing <= 70, `swing {swing}`)
			-- the gap between the tips at rest lets a ball through, and is no wider than three balls
			local tipL = l.x + Det.cos(l.rest) * l.len + l.rTip
			local tipR = r.x - Det.cos(r.rest) * r.len - r.rTip
			local gap = tipR - tipL
			t.truthy(gap > 2 * Layout.BALL_R + 0.02, `gap {gap}`)
			t.truthy(gap < 6 * Layout.BALL_R, `gap {gap}`)
			t.eq(#def.slings, 2)
			for _, name in { "inlane_l", "inlane_r", "outlane_l", "outlane_r" } do
				t.truthy(tbl.ix.sensor[name], name)
			end
			-- an outlane is wide enough to take a ball
			local out = def.sensors[tbl.ix.sensor.outlane_l]
			t.truthy(out.x2 - out.x1 > 2 * Layout.BALL_R, "outlane width")
			t.truthy(tbl.ix.lamp.shoot_again, "a shoot-again lamp")
			t.truthy(tbl.ix.lamp.extra_ball, "an extra-ball lamp")
		end)

		t.test(`{def.title}: the plunger sits at the foot of the shooter lane and its full pull takes about a second`, function()
			local p = def.plunger
			t.truthy(p.x > Layout.FIELD_X1 + Layout.BALL_R and p.x < Layout.WIDTH - Layout.BALL_R)
			t.truthy(p.vMax > p.vMin and p.vMin > 0)
			t.truthy(p.pullTicks >= 200 and p.pullTicks <= 360)
			-- a full plunge has the speed to go right round the arch; the softest one has not
			local top = Layout.ARCH_Y + Layout.WIDTH / 2 - p.y
			t.truthy(p.vMax * p.vMax > 2 * def.gravity * top * 1.2, "a full plunge clears the arch")
			t.truthy(p.vMin * p.vMin < 2 * def.gravity * top, "a soft plunge does not")
			t.truthy(tbl.ix.gate.lane_gate, "the one-way gate at the head of the lane")
		end)

		t.test(`{def.title}: every lamp, switch and callout the rule sheet names exists`, function()
			local m = Machine.new(tbl, 1, 1)
			local lamps = Machine.lamps(tbl, m, {})
			t.eq(#lamps, #def.lamps)
			for i = 1, #lamps do
				t.truthy(lamps[i] == 0 or lamps[i] == 1 or lamps[i] == 2, `lamp {i}`)
			end
			for say, text in tbl.sheet.text do
				t.truthy(say >= 101, "a sheet's own callouts start at 101")
				t.truthy(#text > 0)
			end
			t.truthy(#tbl.sheet.status(m, m.sheets[1]) > 0, "a status line")
			t.truthy(tbl.sheet.saveTicks >= 8 * 240 and tbl.sheet.saveTicks <= 10 * 240, "PIN-R2: ball save of 8 to 10 s")
		end)
	end

	t.test("PIN-R6: ACORN ATTACK is the electro-mechanical one: three bumpers, the five-target bank, a spinner", function()
		local def = Tables.need("pinball_acorn").def
		t.eq(#def.bumpers, 3)
		t.eq(
			count(def.targets, function(x)
				return x.kind == "drop"
			end),
			5
		)
		t.eq(
			count(def.sensors, function(x)
				return x.kind == "spinner"
			end),
			1
		)
		t.eq(#def.rails, 0)
		t.eq(#def.saucers, 0)
	end)

	t.test("PIN-R6: SPICY RODENT has the wire ramp, five S-P-I-C-Y targets and the bite, and is steeper and hungrier", function()
		local def = Tables.need("pinball_rodent").def
		local acorn = Tables.need("pinball_acorn").def
		t.eq(#def.rails, 1)
		t.eq(def.rails[1].id, "wire")
		t.eq(
			count(def.targets, function(x)
				return x.kind == "standup"
			end),
			5
		)
		t.eq(#def.saucers, 1)
		t.eq(def.saucers[1].id, "bite")
		t.truthy(def.gravity > acorn.gravity, "steeper")
		local function gapOf(d: Layout.TableDef): number
			return d.flippers[2].x - d.flippers[1].x
		end
		t.truthy(gapOf(def) > gapOf(acorn), "a wider gap between the flippers")
		local function outlane(d: Layout.TableDef): number
			local s = d.sensors[Layout.index(d).sensor.outlane_l]
			return s.x2 - s.x1
		end
		t.truthy(outlane(def) > outlane(acorn), "wider outlanes")
	end)

	t.test("PIN-R6: SPACE SQUIRREL has two ramps, an orbit and two lock pods", function()
		local tbl = Tables.need("pinball_space")
		t.eq(#tbl.def.rails, 2)
		t.eq(#tbl.def.saucers, 2)
		for _, name in { "orbit_l", "orbit_r", "orbit_top", "dock" } do
			t.truthy(tbl.ix.sensor[name], name)
		end
		-- each ramp brings the ball back to the inlane on its own side
		for _, r in tbl.def.rails do
			local n = #r.pts
			local endX = r.pts[n - 2]
			local startX = r.pts[1]
			t.truthy((endX < Layout.XC) == (startX < Layout.XC), `ramp {r.id} returns on its own side`)
			t.truthy(r.pts[n - 1] < 1.6, "to the inlane")
		end
	end)

	t.test("PIN-R6: the three playfields differ in what stands where, and in how they score", function()
		local a, s, p = Tables.need("pinball_acorn"), Tables.need("pinball_rodent"), Tables.need("pinball_space")
		local function where(tbl: Machine.Table): string
			local parts = {}
			for _, b in tbl.def.bumpers do
				table.insert(parts, `{b.x},{b.y}`)
			end
			return table.concat(parts, " ")
		end
		t.neq(where(a), where(s))
		t.neq(where(s), where(p))
		t.neq(where(a), where(p))
		-- the score scales are orders apart: the guard on each is its sheet's own
		t.truthy(a.sheet.maxScorePerSec * 10 < s.sheet.maxScorePerSec)
		t.truthy(s.sheet.maxScorePerSec * 2 < p.sheet.maxScorePerSec)
		t.neq(a.sheet.saveTicks, s.sheet.saveTicks)
	end)
end
