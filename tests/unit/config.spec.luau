--!strict
-- Shared/Config/Tunables + TunableMeta + Flags (BUILD_PLAN §3.8, §4.4 #1): studs on read for HTML-unit
-- leaves, authored values on raw, validated live overrides with onChanged, diff for "Export tuning",
-- and the Power mirror equal to Rodent/PowerRules (the authority).
local Flags = require("@shared/Config/Flags")
local PowerRules = require("@shared/Rodent/PowerRules")
local Tunables = require("@shared/Config/Tunables")

return function(t)
	t.test("get converts HTML units to studs; raw and meta keep the authored value", function()
		t.eq(Tunables.get("squirrel.walk"), 18)
		t.eq(Tunables.raw("squirrel.walk"), 7.2)
		t.eq(Tunables.get("squirrel.shoulderHeight"), 1.2) -- already studs
		t.eq(Tunables.get("clock.realSecondsPerDay"), 720)
		t.deepEq(Tunables.get("traffic.sedanBox"), { 2.35 * 2.5, 4.45 * 2.5, 2.04 * 2.5 })
		local m = Tunables.meta("squirrel.walk")
		t.eq(m.unit, "u/s")
		t.truthy(m.studs)
		t.eq(m.default, 7.2)
		t.fails(function()
			Tunables.get("squirrel.nope")
		end)
	end)

	t.test("every leaf is reachable and get never errors", function()
		local paths = Tunables.paths()
		t.truthy(#paths > 150, tostring(#paths))
		for _, p in paths do
			Tunables.get(p)
		end
	end)

	t.test("applyOverrides validates, fires onChanged, diff and reset", function()
		local seen = {}
		local conn = Tunables.onChanged("squirrel.walk", function(v)
			table.insert(seen, v)
		end)
		local applied, errors = Tunables.applyOverrides({
			["squirrel.walk"] = 9,
			["squirrel.sprint"] = "fast",
			["alert.kickMult"] = 1.9, -- D33: must stay below 1.82
			["rodent.kick"] = -5, -- sign change
			["no.such"] = 1,
		})
		t.eq(applied, 1)
		t.eq(#errors, 4)
		t.deepEq(seen, { 22.5 })
		t.eq(Tunables.get("squirrel.walk"), 22.5)
		local d = Tunables.diff()
		t.eq(#d, 1)
		t.deepEq(d[1], { path = "squirrel.walk", from = 7.2, to = 9 })
		Tunables.reset()
		t.eq(#Tunables.diff(), 0)
		t.deepEq(seen, { 22.5, 18 })
		conn:disconnect()
	end)

	t.test("returned tables are copies", function()
		local box = Tunables.raw("traffic.sedanBox")
		box[1] = 99
		t.eq(Tunables.raw("traffic.sedanBox")[1], 2.35)
	end)

	t.test("power leaves mirror Rodent/PowerRules.TABLE (brief v2 §15)", function()
		local T = PowerRules.TABLE
		t.eq(Tunables.get("power.bitePerson"), T.bitePerson)
		t.eq(Tunables.get("power.bitePersonHigh"), T.bitePersonHigh)
		t.eq(Tunables.get("power.biteOfficer"), T.biteOfficer)
		t.eq(Tunables.get("power.convertSquirrel"), T.convertSquirrel)
		t.eq(Tunables.get("power.batonHit"), T.batonHit)
		t.eq(Tunables.get("power.pedestrianKick"), T.pedestrianKick)
		t.eq(Tunables.get("power.catHit"), T.catHit)
		t.eq(Tunables.get("power.fadeAfterActiveMin") * 60, T.fadeInterval)
		t.eq(Tunables.get("power.fadePct"), T.fadeRate)
		t.deepEq(Tunables.get("power.stages"), { feral = 0, rabid = T.rabid, super = T.super })
	end)

	t.test("Flags: defaults, set/reset, isDev by Studio or dev list", function()
		t.falsy(Flags.enabled("moveValidatorEnforce"))
		Flags.set("moveValidatorEnforce", true)
		t.truthy(Flags.enabled("moveValidatorEnforce"))
		Flags.reset()
		t.falsy(Flags.enabled("moveValidatorEnforce"))
		Flags.configure({
			devUserIds = { 42 },
			isStudio = function()
				return false
			end,
		})
		t.truthy(Flags.isDev({ UserId = 42 }))
		t.falsy(Flags.isDev({ UserId = 7 }))
		Flags.configure({
			isStudio = function()
				return true
			end,
		})
		t.truthy(Flags.isDev({ UserId = 7 }))
		Flags.configure({
			devUserIds = {},
			isStudio = function()
				return false
			end,
		})
	end)
end
