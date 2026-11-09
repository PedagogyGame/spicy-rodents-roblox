--!strict
-- First playable build (owner directive 2026-11-09): Combat/PlayRules (health 100, kick 55, the bite on
-- contact, mild shouts, death messages), World/LightingPreset (the v5.4 golden mapping), PlayMenu's
-- pure parts (help lines per role and device, the status line) and Power through PowerRules.
local PlayRules = require("@shared/Combat/PlayRules")
local PowerRules = require("@shared/Rodent/PowerRules")
local LightingPreset = require("@shared/World/LightingPreset")
local PlayMenu = require("@client/UI/PlayMenu")

return function(t)
	t.test("PlayRules: two kicks knock out a 100-health rodent; health never below 0", function()
		local h, dead = PlayRules.damage(PlayRules.HEALTH, PlayRules.KICK_DAMAGE)
		t.eq(h, 45)
		t.truthy(not dead)
		h, dead = PlayRules.damage(h, PlayRules.KICK_DAMAGE)
		t.eq(h, 0)
		t.truthy(dead)
	end)

	t.test("PlayRules.kickTarget: nearest in front, within reach, not up a tree, not yourself", function()
		local me = { id = "me", x = 0, y = 0, z = 0 }
		local look = { x = 0, z = 1 }
		local targets = {
			{ id = "behind", x = 0, y = 0, z = -2 },
			{ id = "far", x = 0, y = 0, z = 9 },
			{ id = "near", x = 0.5, y = 0, z = 3 },
			{ id = "nearer", x = -0.5, y = 0, z = 2 },
			{ id = "tree", x = 0, y = 12, z = 1.5 },
			{ id = "me", x = 0, y = 0, z = 0 },
		}
		t.eq(PlayRules.kickTarget(me, look, targets), "nearer")
		t.eq(PlayRules.kickTarget(me, { x = 0, z = -1 }, targets), "behind")
		t.eq(PlayRules.kickTarget(me, look, { targets[2], targets[5] }), nil)
		t.eq(PlayRules.kickTarget(me, { x = 0, z = 0 }, targets), nil, "no facing")
	end)

	t.test("PlayRules.biteVictims: contact range and a per-person cooldown", function()
		local last = {}
		local rodent = { id = "r", x = 0, y = 1, z = 0 }
		local people = {
			{ id = "a", x = 2, y = 3, z = 0 },
			{ id = "b", x = 5, y = 3, z = 0 },
			{ id = "c", x = 0, y = 9, z = 1 },
		}
		local v = PlayRules.biteVictims(rodent, people, 10, last)
		t.eq(#v, 1)
		t.eq(v[1], "a")
		t.eq(#PlayRules.biteVictims(rodent, people, 11, last), 0, "cooldown")
		t.eq(#PlayRules.biteVictims(rodent, people, 10 + PlayRules.BITE_COOLDOWN, last), 1, "after the cooldown")
	end)

	t.test("PlayRules: mild shouts cycle; death messages name the cause", function()
		t.eq(PlayRules.shout(1), PlayRules.SHOUTS[1])
		t.eq(PlayRules.shout(#PlayRules.SHOUTS + 1), PlayRules.SHOUTS[1])
		for _, line in PlayRules.SHOUTS do
			local l = string.lower(line)
			for _, bad in { "damn", "hell", "crap" } do
				t.truthy(not string.find(l, bad, 1, true), `mild: {line}`)
			end
		end
		t.eq((PlayRules.deathMessage("traffic")), "RUN OVER!")
		t.eq((PlayRules.deathMessage("kick")), "KICKED OUT!")
	end)

	t.test("Power per brief v2 §15: +100 a bite, +150 high up, +130 an officer, -19 a kick", function()
		local s = PowerRules.new()
		t.eq(PowerRules.apply(s, { kind = "bitePerson", y = 0.4 }), 100)
		t.eq(PowerRules.apply(s, { kind = "bitePerson", y = 6 }), 150)
		t.eq(PowerRules.apply(s, { kind = "biteOfficer" }), 130)
		t.eq(PowerRules.apply(s, { kind = "pedestrianKick" }), -19)
		t.eq(s.points, 361)
	end)

	t.test("LightingPreset: the v5.4 golden mapping as daylight", function()
		local g = LightingPreset.GOLDEN
		t.truthy(g.clockTime >= 9 and g.clockTime <= 18, "daytime")
		t.eq(g.colorShiftTop, "ffe0ab")
		t.eq(g.outdoorAmbient, "a2a180")
		t.eq(g.atmosphere.color, "c8d1bd")
		t.near(g.exposure, math.log(1.12) / math.log(2), 0.01, "exposure 1.12 as EV")
		t.eq(g.latitude, 39)
	end)

	t.test("PlayMenu: five choices; help lines for every role and device; status line", function()
		t.eq(#PlayMenu.CHOICES, 5)
		local ids = {}
		for _, c in PlayMenu.CHOICES do
			table.insert(ids, c.id)
		end
		t.eq(table.concat(ids, ","), "rodent,squirrel,townsperson,police,drone")
		local function has(lines: { string }, needle: string): boolean
			for _, l in lines do
				if string.find(l, needle, 1, true) then
					return true
				end
			end
			return false
		end
		t.truthy(has(PlayMenu.helpLines("rodent"), "pounce"))
		t.truthy(has(PlayMenu.helpLines("rodent"), "bite"))
		t.truthy(has(PlayMenu.helpLines("squirrel"), "climb"))
		t.truthy(has(PlayMenu.helpLines("townsperson"), "F  kick"))
		t.truthy(has(PlayMenu.helpLines("police"), "E  get into"))
		t.truthy(has(PlayMenu.helpLines("police", "vehicle"), "E  get out"))
		t.truthy(has(PlayMenu.helpLines("drone", "drone"), "E  land"))
		t.truthy(has(PlayMenu.helpLines(nil), "menu"))
		t.truthy(string.find(PlayMenu.statusLine({ PlayRole = "rodent", Bites = 3, Power = 300 }), "Bites 3", 1, true))
		t.truthy(string.find(PlayMenu.statusLine({}), "menu", 1, true))
	end)
end
