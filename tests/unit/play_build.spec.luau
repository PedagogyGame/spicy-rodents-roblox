--!strict
-- First playable build (owner directive 2026-11-09): Combat/PlayRules (health 100, kick 55, the bite on
-- contact, mild shouts, death messages), World/LightingPreset (the v5.4 golden mapping), PlayMenu's
-- pure parts (help lines per role and device, the status line) and Power through PowerRules.
local PlayRules = require("@shared/Combat/PlayRules")
local PowerRules = require("@shared/Rodent/PowerRules")
local LightingPreset = require("@shared/World/LightingPreset")
local PlayMenu = require("@client/UI/PlayMenu")
local Game = require("@server/Boot/Game")

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

	t.test("Game.pickOfficer: Police and Drone picks skip an officer who is a patient or already played", function()
		local function person(name: string, police: boolean, free: boolean, possessable: boolean): any
			return { actor = name, police = police, free = free, possessable = possessable }
		end
		-- the first officer in the town's order collapsed a moment ago (not possessable): the pick
		-- used to grab that body, teleport the patient to the patrol car and then be refused
		local town = {
			person("walker", false, true, true),
			person("patient officer", true, true, false),
			person("played officer", true, false, true),
			person("free officer", true, true, true),
			person("another officer", true, true, true),
		}
		t.eq(Game.pickOfficer(town), "free officer")
		-- every officer is a patient or taken: any free, healthy person will do
		town[4].possessable = false
		town[5].free = false
		t.eq(Game.pickOfficer(town), "walker")
		-- nobody at all: a patient is never the answer
		town[1].possessable = false
		t.eq(Game.pickOfficer(town), nil)
		t.eq(Game.pickOfficer({}), nil)
		-- a refusal reads as a sentence, never as the log's reason
		t.truthy(string.find(Game.refusalText("not possessable"), "collapsed", 1, true) ~= nil)
		t.truthy(string.find(Game.refusalText("not possessable"), "possessable", 1, true) == nil)
		t.truthy(string.find(Game.refusalText("body is driven"), "Someone else", 1, true) ~= nil)
		t.eq(
			Game.refusalText("Every squirrel is taken. Pick another body."),
			"Every squirrel is taken. Pick another body."
		)
		t.eq(Game.refusalText(nil), "that body is busy")
		-- an officer moved to the patrol car for a pick that was then refused goes back where they
		-- were, unless they collapsed at the car in the meantime: their scene is there
		t.eq(Game.putBack(true, true), true, "still the AI's and on their feet: back to the beat")
		t.eq(Game.putBack(true, false), false, "a patient stays where they fell")
		t.eq(Game.putBack(false, true), false, "somebody else's body is not moved")
		t.eq(Game.putBack(false, false), false)
	end)

	t.test("PlayMenu.sickLine: a bitten player's line says what is wrong and what to do; nothing otherwise", function()
		t.eq(PlayMenu.sickLine({}), nil)
		t.eq(PlayMenu.sickLine({ PlayRole = "townsperson" }), nil)
		t.eq(PlayMenu.sickLine({ Infected = "no such status" }), nil)
		t.eq(PlayMenu.sickLine({ Infected = false }), nil)
		for status, word in { infected = "INFECTED", symptoms = "RED EYES", treating = "TREATED" } do
			local line = PlayMenu.sickLine({ PlayRole = "townsperson", Infected = status }) :: string
			t.truthy(line ~= nil and string.find(line, word, 1, true) ~= nil, `{status}: {line}`)
			t.truthy(string.find(line, "hospital", 1, true) ~= nil, `{status} names the hospital`)
			t.truthy(#line <= 70, `{status}: {#line} characters fit the line`)
			-- no compass word (the game has no compass) and no signs (the town has none)
			for _, word2 in { "west", "east", "north", "south", "sign" } do
				t.truthy(string.find(string.lower(line), word2, 1, true) == nil, `{status}: "{word2}" in the line`)
			end
		end
	end)

	t.test(
		"the way to the hospital for a bitten player: the distance and direction on the line, a marker text",
		function()
			-- Roblox's axes: a camera looking along -Z has +X on its right
			t.eq(PlayMenu.wayWords(0, -100, 0, -1), "ahead")
			t.eq(PlayMenu.wayWords(100, 0, 0, -1), "to your right")
			t.eq(PlayMenu.wayWords(-100, 0, 0, -1), "to your left")
			t.eq(PlayMenu.wayWords(0, 100, 0, -1), "behind you")
			-- the camera turned to look along +X: what was to the right is ahead
			t.eq(PlayMenu.wayWords(100, 0, 1, 0), "ahead")
			t.eq(PlayMenu.wayWords(0, 100, 1, 0), "to your right")
			t.eq(PlayMenu.wayWords(0, -100, 1, 0), "to your left")
			t.eq(PlayMenu.wayWords(-100, 5, 1, 0), "behind you")
			t.eq(PlayMenu.wayWords(100, -60, 0.6, -0.8), "ahead", "an unnormalised, slanted look works too")
			-- on the line: how far and which way, in place of "to be cured"
			local line = PlayMenu.sickLine({ Infected = "infected" }, { dist = 2496.4, words = "to your left" }) :: string
			t.eq(line, "INFECTED  ·  Walk into the hospital: 2500 studs to your left")
			local near = PlayMenu.sickLine({ Infected = "symptoms" }, { dist = 41.6, words = "ahead" }) :: string
			t.eq(near, "INFECTED, RED EYES  ·  Walk into the hospital: 42 studs ahead")
			t.truthy(
				#(PlayMenu.sickLine({ Infected = "symptoms" }, { dist = 9999, words = "to your right" }) :: string)
					<= 76
			)
			-- inside, being treated: nothing to walk to
			t.eq(PlayMenu.sickLine({ Infected = "treating" }, { dist = 12, words = "ahead" }), PlayMenu.SICK.treating)
			t.eq(PlayMenu.sickLine({}, { dist = 12, words = "ahead" }), nil)
			t.eq(PlayMenu.markerText(1234), "HOSPITAL\n1230 studs")
			t.eq(PlayMenu.markerText(7.2), "HOSPITAL\n7 studs")
			-- what the server tells a bitten player points at the marker, not at a compass or at signs
			local InfectionService = require("@server/Infection/InfectionService")
			for _, key in { "bitten", "bittenAgain", "infected", "symptoms" } do
				local toast = InfectionService.TOASTS[key]
				t.truthy(string.find(toast, "HOSPITAL marker", 1, true) ~= nil, `{key}: {toast}`)
				for _, word in { "west", "east", "north", "south", "signs" } do
					t.truthy(string.find(string.lower(toast), word, 1, true) == nil, `{key} says "{word}"`)
				end
			end
		end
	)
end
