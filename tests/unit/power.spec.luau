--!strict
-- Shared/Rodent/PowerRules golden test (BUILD_PLAN §4.4 #6b; brief v2 §15 "Power, verbatim from v5.4"):
-- 40 seeded streams x 120 events replayed through v5.4's own updatePowerAndHeat and bite/hit lines
-- (tests/golden/power_gen.mjs). Points and the fade clock must match bit-exactly (PreciseJson).
local fs = require("@lune/fs")
local PowerRules = require("@shared/Rodent/PowerRules")
local PreciseJson = require("@tests/lib/PreciseJson")

return function(t)
	t.test("golden power.json: 4,800 events bit-exact (points, fade clock, stage)", function()
		local g = PreciseJson.decode(fs.readFile("tests/golden/power.json"))
		t.eq(#g.streams, 40)
		local rows, fades = 0, 0
		for _, stream in g.streams do
			local st = PowerRules.new()
			for i, row in stream.rows do
				local ev, points, inactive, stage = row[1], row[2], row[3], row[4]
				if ev.kind == "tick" then
					if PowerRules.fade(st, ev.dt) > 0 then
						fades += 1
					end
				else
					PowerRules.apply(st, ev)
				end
				rows += 1
				t.eq(st.points, points, `seed {stream.seed} row {i} points`)
				t.eq(st.inactiveSeconds, inactive, `seed {stream.seed} row {i} clock`)
				t.eq(PowerRules.stage(st.points), stage, `seed {stream.seed} row {i} stage`)
			end
		end
		t.eq(rows, 4800)
		t.truthy(fades > 100, tostring(fades))
	end)

	t.test("the brief's table, row by row", function()
		local s = PowerRules.new()
		t.eq(PowerRules.apply(s, { kind = "bitePerson", y = 1 }), 100)
		t.eq(PowerRules.apply(s, { kind = "bitePerson", y = 4 }), 100) -- strictly above 4
		t.eq(PowerRules.apply(s, { kind = "bitePerson", y = 4.01 }), 150)
		t.eq(PowerRules.apply(s, { kind = "biteOfficer" }), 130)
		t.eq(PowerRules.apply(s, { kind = "convertSquirrel", id = "sq1" }), 90)
		t.eq(PowerRules.apply(s, { kind = "convertSquirrel", id = "sq1" }), 0) -- once per squirrel
		t.eq(PowerRules.apply(s, { kind = "baton" }), -19)
		t.eq(PowerRules.apply(s, { kind = "pedestrianKick" }), -19)
		t.eq(PowerRules.apply(s, { kind = "cat" }), -12)
		for _, k in { "chili", "coin", "climb", "missedPounce" } do
			t.eq(PowerRules.apply(s, { kind = k }), 0, k)
		end
	end)

	t.test("fade: 15 % rounded up per 600 active seconds, repeating; a bite resets; floor 0", function()
		local s = PowerRules.new()
		s.points = 1000
		t.eq(PowerRules.fade(s, 599), 0)
		t.eq(PowerRules.nextFadeIn(s), 1)
		t.eq(PowerRules.fade(s, 1), 150)
		t.eq(s.points, 850)
		t.eq(PowerRules.fade(s, 1200), 128 + 109) -- ceil(127.5), then ceil(108.45)
		PowerRules.apply(s, { kind = "biteOfficer" })
		t.eq(s.inactiveSeconds, 0)
		s.points = 1
		t.eq(PowerRules.fade(s, 600), 1)
		t.eq(s.points, 0)
		t.eq(PowerRules.fade(s, 600), 0) -- nothing to lose at zero
		s.points = 5
		PowerRules.apply(s, { kind = "baton" })
		t.eq(s.points, 0)
	end)

	t.test("stages", function()
		t.eq(PowerRules.stage(0), "FERAL")
		t.eq(PowerRules.stage(599), "FERAL")
		t.eq(PowerRules.stage(600), "RABID")
		t.eq(PowerRules.stage(1499), "RABID")
		t.eq(PowerRules.stage(1500), "SUPER")
	end)
end
