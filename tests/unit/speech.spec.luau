--!strict
-- Speech/Lines and Speech/SpeechRules (owner 2026-11-10: townspeople say worried things): the line
-- the owner asked for is there word for word, the lines are many, mild and short, and the limits hold:
-- a per-actor cooldown, a town-wide window, no immediate repeats, a forced line for the bitten
-- victim, and the client's "how long is this bubble still shown" answer.
local Lines = require("@shared/Speech/Lines")
local SpeechRules = require("@shared/Speech/SpeechRules")
local PlayRules = require("@shared/Combat/PlayRules")
local Rng = require("@shared/Util/Rng")

-- brief v2 §15 mild rating: nothing stronger than "Oh my god"
local BANNED = { "damn", "hell", "bastard", "crap", "piss", "bloody", "stupid", "idiot", "kill", "die", "dead", "shit" }

local function params(over: { [string]: any }?): SpeechRules.Params
	local p: any = { actorCooldown = 12, townBurst = 3, townWindow = 5, forceGap = 1, noRepeat = 3 }
	for k, v in over or {} do
		p[k] = v
	end
	return p
end

local function always(): number
	return 0
end

return function(t)
	t.test("lines: the owner's line is there word for word, among at least 15 others, in every situation", function()
		t.eq(Lines.THE_LINE, "Oh my god, it's one of those squirrels again!")
		t.truthy(table.find(Lines.GROUPS.spotting, "Oh my god, it's one of those squirrels again!") ~= nil)
		local all = Lines.all()
		t.truthy(#all >= 15, `{#all} lines`)
		local seen: { [string]: boolean } = {}
		for _, line in all do
			t.truthy(not seen[line], `duplicate line: {line}`)
			seen[line] = true
		end
		for _, s in { "spotting", "fleeing", "bitten", "bystander", "crew" } do
			t.truthy(#Lines.of(s) >= 3, `{s} has {#Lines.of(s)} lines`)
		end
		for _, s in Lines.SITUATIONS do
			t.truthy(#Lines.of(s) >= 1, `{s} is empty`)
			t.truthy(SpeechRules.CHANCE[s] ~= nil, `{s} has no chance`)
		end
		local n = 0
		for _ in Lines.GROUPS do
			n += 1
		end
		t.eq(n, #Lines.SITUATIONS, "every group is listed in SITUATIONS")
		t.eq(#Lines.of("nonsense"), 0)
	end)

	t.test("lines: short and mild (nothing stronger than 'Oh my god')", function()
		for _, line in Lines.all() do
			t.truthy(#line <= 60, `too long for a bubble ({#line}): {line}`)
			t.truthy(#line >= 4, `too short: {line}`)
			local lower = " " .. string.lower(line) .. " "
			for _, word in BANNED do
				t.truthy(string.find(lower, "%f[%a]" .. word .. "%f[%A]") == nil, `'{word}' in: {line}`)
			end
			-- "god" only as part of "Oh my god"
			local stripped = string.gsub(lower, "oh my god", "")
			t.truthy(string.find(stripped, "god", 1, true) == nil, `'god' outside "Oh my god": {line}`)
		end
	end)

	t.test("the bite shouts moved into the shared lines; PlayRules.shout still cycles them", function()
		t.eq(PlayRules.SHOUTS, Lines.GROUPS.bitten)
		t.eq(#PlayRules.SHOUTS, 8)
		t.eq(PlayRules.shout(1), Lines.GROUPS.bitten[1])
		t.eq(PlayRules.shout(9), Lines.GROUPS.bitten[1])
	end)

	t.test("town-wide limit: 40 people spotting in the same second produce at most townBurst lines", function()
		local state = SpeechRules.new(params())
		local said = 0
		for actor = 1, 40 do
			if SpeechRules.request(state, 100 + actor * 0.02, actor, "spotting", always) then
				said += 1
			end
		end
		t.eq(said, 3, "townBurst = 3")
		-- the window slides: 5 s later three more may speak, and no more
		local later = 0
		for actor = 41, 80 do
			if SpeechRules.request(state, 106 + actor * 0.001, actor, "spotting", always) then
				later += 1
			end
		end
		t.eq(later, 3)
		-- without the window everyone would have spoken
		local loose = SpeechRules.new(params({ townBurst = 1000 }))
		local all = 0
		for actor = 1, 40 do
			if SpeechRules.request(loose, 100, actor, "spotting", always) then
				all += 1
			end
		end
		t.eq(all, 40)
	end)

	t.test("per-actor cooldown: one person asking every 0.1 s for 60 s speaks once per 12 s", function()
		local state = SpeechRules.new(params({ townBurst = 1000 }))
		local times = {}
		for i = 0, 600 do
			local now = i * 0.1
			if SpeechRules.request(state, now, "ped_7", "fleeing", always) then
				table.insert(times, now)
			end
		end
		t.eq(#times, 6, "0, 12, 24, 36, 48, 60")
		for i = 2, #times do
			t.truthy(times[i] - times[i - 1] >= 12 - 1e-6, `gap {times[i] - times[i - 1]}`)
		end
		-- another person is not held back by this one's cooldown
		t.truthy(SpeechRules.request(state, 60.05, "ped_8", "fleeing", always) ~= nil)
	end)

	t.test("the chance keeps some people quiet; a quiet person keeps their turn", function()
		local state = SpeechRules.new(params({ townBurst = 1000 }))
		local function never(): number
			return 0.999
		end
		t.eq(SpeechRules.request(state, 1, "a", "spotting", never), nil)
		-- nothing was recorded: the same person may speak a moment later
		t.truthy(SpeechRules.request(state, 1.1, "a", "spotting", always) ~= nil)
		t.eq(SpeechRules.stats(state).spoken, 1)
		t.eq(SpeechRules.stats(state).refused, 1)
	end)

	t.test("a forced line (the bitten victim) always comes out, but not twice in a second", function()
		local state = SpeechRules.new(params())
		-- fill the town window
		for actor = 1, 3 do
			t.truthy(SpeechRules.request(state, 10, actor, "spotting", always) ~= nil)
		end
		t.eq(SpeechRules.request(state, 10.1, 9, "bitten", always), nil, "the window is full")
		local line = SpeechRules.request(state, 10.2, 9, "bitten", always, { force = true })
		t.truthy(line ~= nil and table.find(Lines.GROUPS.bitten, line :: string) ~= nil)
		-- actor 1 spoke at t = 10: forced still goes through the cooldown, not through the 1 s floor
		t.truthy(SpeechRules.request(state, 11.5, 1, "bitten", always, { force = true }) ~= nil)
		t.eq(SpeechRules.request(state, 12.0, 1, "bitten", always, { force = true }), nil, "0.5 s after the last")
		-- forced lines count toward the window
		t.eq(SpeechRules.request(state, 12.1, 30, "spotting", always), nil)
	end)

	t.test(
		"2,000 seeded draws: every spotting line appears, never the same line twice running, the owner's line about three times in ten",
		function()
			local rng = Rng.new(20261110)
			local state = SpeechRules.new(params({ actorCooldown = 0, townBurst = 1000, chance = { spotting = 1 } }))
			local counts: { [string]: number } = {}
			local last: string? = nil
			local window: { string } = {}
			for i = 1, 2000 do
				local line = SpeechRules.request(state, i, i, "spotting", rng.next)
				t.truthy(line ~= nil, `draw {i} gave nothing`)
				local s = line :: string
				t.truthy(s ~= last, `"{s}" twice running at draw {i}`)
				-- the other lines keep clear of the last three; the owner's line only of the very last
				t.truthy(s == Lines.THE_LINE or table.find(window, s) == nil, `"{s}" within the last three at draw {i}`)
				table.insert(window, s)
				if #window > 3 then
					table.remove(window, 1)
				end
				last = s
				counts[s] = (counts[s] or 0) + 1
			end
			for _, line in Lines.GROUPS.spotting do
				t.truthy((counts[line] or 0) > 100, `"{line}" came up {counts[line] or 0} times`)
			end
			-- the line the owner asked for by name: as one of seven equal lines it was 1 in 7 of these
			local share = counts[Lines.THE_LINE] / 2000
			t.truthy(share > 0.26 and share < 0.36, `the owner's line was {share * 100} % of the spotting lines`)
			for _, line in Lines.GROUPS.spotting do
				t.truthy(
					line == Lines.THE_LINE or counts[line] < counts[Lines.THE_LINE] / 2,
					`"{line}" came up {counts[line]} times, the owner's line {counts[Lines.THE_LINE]}`
				)
			end
			-- through the server's own dice (0.65 of spotters get a spotting line, 0.7 of those speak):
			-- about one sighting in seven produces it (it was one in sixteen)
			local town = SpeechRules.new(params({ actorCooldown = 0, townBurst = 100000 }))
			local owner = 0
			for i = 1, 20000 do
				if rng.next() < 0.65 and SpeechRules.request(town, i, i, "spotting", rng.next) == Lines.THE_LINE then
					owner += 1
				end
			end
			t.truthy(owner / 20000 > 0.11, `the owner's line on {owner / 200} % of sightings`)
			-- only the spotting lines have a favourite
			t.truthy(SpeechRules.OWNER_SHARE > 0.3 and SpeechRules.OWNER_SHARE < 0.6)
			-- a three-line group still never repeats back to back
			local small = SpeechRules.new(params({ actorCooldown = 0, townBurst = 1000 }))
			local prev: string? = nil
			for i = 1, 300 do
				local line = SpeechRules.request(small, i, i, "cured", rng.next)
				t.truthy(line ~= nil and line ~= prev, `cured repeat at {i}`)
				prev = line
			end
		end
	)

	t.test("unknown situations say nothing; the defaults come from Tunables", function()
		local state = SpeechRules.new()
		t.eq(SpeechRules.request(state, 0, 1, "weather", always), nil)
		t.eq(state.params.actorCooldown, 12)
		t.eq(state.params.townBurst, 3)
		t.eq(state.params.townWindow, 5)
	end)

	t.test("remaining: stale, missing and far-future stamps are not shown; a late stream-in shows the rest", function()
		t.eq(SpeechRules.remaining(100, 100, 3.5), 3.5)
		t.near(SpeechRules.remaining(102, 100, 3.5), 1.5, 1e-9, "a body that streams in 2 s late")
		t.eq(SpeechRules.remaining(103.5, 100, 3.5), 0, "exactly expired")
		t.eq(SpeechRules.remaining(900, 100, 3.5), 0, "an old line on a body that just streamed in")
		t.eq(SpeechRules.remaining(100, nil, 3.5), 0)
		t.eq(SpeechRules.remaining(100, 0 / 0, 3.5), 0)
		t.eq(SpeechRules.remaining(100, 101, 3.5), 3.5, "a second ahead: the client clock trails")
		t.eq(SpeechRules.remaining(100, 110, 3.5), 0, "far in the future: not a real stamp")
		t.eq(SpeechRules.ATTR.Say, "Say")
		t.eq(SpeechRules.ATTR.SayAt, "SayAt")
	end)
end
