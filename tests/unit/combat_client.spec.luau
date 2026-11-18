--!strict
-- The duel on a player's screen (brief v2 §8; owner playtest 2026-11-18): the rodent's wind-up (the click is the tell,
-- the motor's pounce follows pounce.windup later), F feints, the stances a person shows (the vigilante's "squared" is
-- the tell), the crouch every client plays at the wind-up, and the words the rodent's player reads.
local Squirrel = require("@client/Controllers/Squirrel")
local StanceView = require("@client/Render/StanceView")
local DuelWords = require("@client/UI/DuelWords")
local InputMap = require("@client/Input/InputMap")
local AnimationDriver = require("@client/Animation/AnimationDriver")
local Tunables = require("@shared/Config/Tunables")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")

return function(t)
	t.test("the wind-up: a click tells the duel at once and pounces the motor windup seconds later", function()
		local w = Tunables.get("pounce.windup")
		t.eq(w, 0.12)
		local now, pend, tell = Squirrel.windup(nil, 10, true, w, true)
		t.falsy(now)
		t.truthy(tell, "the click is the tell")
		t.near(pend :: number, 10 + w, 1e-9)
		now, pend, tell = Squirrel.windup(pend, 10.05, true, w, true)
		t.falsy(now, "a second click during the wind-up changes nothing")
		t.falsy(tell)
		now, pend, tell = Squirrel.windup(pend, 10 + w, false, w, true)
		t.truthy(now, "the motor pounces")
		t.eq(pend, nil)
		t.falsy(tell)
		-- the motor on its cooldown: the click is not sent, nothing is pending
		now, pend, tell = Squirrel.windup(nil, 11, true, w, false)
		t.falsy(now or tell)
		t.eq(pend, nil)
		-- the pounce the motor makes is the same move the validator always accepted (its numbers are untouched)
		t.eq(SquirrelMotor.params.pounceCooldown, 0.7)
		t.eq(SquirrelMotor.params.pounceWindow, 0.78)
	end)

	t.test("F feints for the rodent; the rodent's hint says so", function()
		local h = InputMap.HINTS("rodent")
		t.truthy(string.find(h, "F feint", 1, true) ~= nil)
		t.truthy(string.find(h, "Click pounce", 1, true) ~= nil)
		t.truthy(string.find(InputMap.HINTS("human"), "F kick", 1, true) ~= nil)
	end)

	t.test(
		"stances: four, each a turn of the R15's joints; the vigilante's squared stance is unlike the others",
		function()
			for _, stance in { "squared", "guard", "windup", "flinch" } do
				local turns = StanceView.turns(stance)
				local n = 0
				for name, r in turns do
					n += 1
					t.truthy(table.find(StanceView.JOINTS, name) ~= nil, name)
					for _, a in r do
						t.truthy(math.abs(a) <= math.pi, "a turn a body can make")
					end
				end
				t.truthy(n >= 2, stance)
			end
			t.eq(next(StanceView.turns(nil)), nil)
			t.eq(next(StanceView.turns("nonsense")), nil)
			local sq = StanceView.turns("squared")
			t.truthy(sq.RightShoulder ~= nil and sq.LeftShoulder ~= nil, "both fists up")
		end
	)

	t.test("the wind-up's crouch plays once per stamp, never for an old one", function()
		t.truthy(AnimationDriver.WINDUP.secs > Tunables.get("pounce.windup"), "the crouch outlasts the wind-up")
		local due, seen = AnimationDriver.biteDue(nil, 100, true)
		t.falsy(due, "a body first seen with a stamp: nothing")
		due, seen = AnimationDriver.biteDue(seen, 101, false)
		t.truthy(due)
		due = AnimationDriver.biteDue(seen, 101, false)
		t.falsy(due, "once")
	end)

	t.test("the rodent's player reads what happened, mildly", function()
		for _, what in { "batted", "missed", "dodged", "winded" } do
			local words = DuelWords.news(what, false)
			t.truthy(type(words) == "string" and #words > 5, what)
		end
		t.truthy(DuelWords.news("batted", true) ~= DuelWords.news("batted", false), "the alert zone is named")
		t.eq(DuelWords.news("nonsense", false), nil)
		for _, by in { "kick", "swing", "baton" } do
			t.truthy(#DuelWords.hurt(by) > 5)
		end
		-- the mild rating: the speech spec's banned words do not appear
		local all = {}
		for _, w in DuelWords.NEWS do
			table.insert(all, w)
		end
		for _, by in { "kick", "swing", "baton" } do
			table.insert(all, DuelWords.hurt(by))
		end
		for _, w in all do
			for _, bad in { "damn", "hell", "kill", "blood", "die" } do
				t.truthy(string.find(string.lower(w), bad, 1, true) == nil, `{w}: {bad}`)
			end
		end
	end)
end
