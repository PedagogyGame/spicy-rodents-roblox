--!strict
-- Shared/Actors/Population (BUILD_PLAN §6.2 Population row, §1.5 supply order, §3.13 invariant 11):
-- floors never broken by 1,000 random joins, leaves and promotions up to 49 players; supply order
-- (above-floor, re-post, reserve, cap floors); the plan config validates, the S5 config records
-- its own smaller cap.
local Population = require("@shared/Actors/Population")

local function lcg(seed: number): () -> number
	local s = seed
	return function(): number
		s = (s * 1103515245 + 12345) % 2147483648
		return s / 2147483648
	end
end

return function(t)
	t.test("the plan config validates (police >= 6, hospital >= 10, cap - cap floors >= 49)", function()
		local ok, errors = Population.validate(Population.plan())
		t.truthy(ok, table.concat(errors, "; "))
	end)

	t.test("the S5 spike config fails only the 49-slot arithmetic (hard cap 72 is the measured count)", function()
		local ok, errors = Population.validate(Population.spikeS5())
		t.falsy(ok)
		t.eq(#errors, 1)
		t.truthy(string.find(errors[1], "hard cap 72"), errors[1])
	end)

	t.test("validate rejects a cut police or hospital floor", function()
		local cfg = Population.plan()
		for _, post in cfg.posts do
			if post.id == "police" then
				post.floor, post.floorAtCap = 5, 5
			end
		end
		local ok, errors = Population.validate(cfg)
		t.falsy(ok)
		t.truthy(string.find(table.concat(errors, " "), "police floor 5"))
	end)

	t.test("supply order: body above floor, then re-post, then reserve, then cap floors, then wait", function()
		local cfg = Population.plan()
		local state = Population.newState(cfg)
		-- townspeople: 32 standing, floor 8 -> 24 direct bodies
		for i = 1, 24 do
			local d = Population.pickBody("townsperson", state, cfg)
			t.eq(d.kind, "body", `join {i}`)
			Population.apply(state, d)
		end
		-- next: re-post from the shop post (6 standing, floor 6 -> no slack) or attraction (0): none has
		-- slack, so the reserve goes next: 8 parked bodies, then bodies built up to the hard cap (90 - 69 = 21)
		local d = Population.pickBody("townsperson", state, cfg)
		t.eq(d.kind, "reserve")
		t.eq(state.reserveLeft, 21)
		for _ = 1, 21 do
			d = Population.pickBody("townsperson", state, cfg)
			t.eq(d.kind, "reserve")
			Population.apply(state, d)
		end
		t.eq(state.reserveLeft, 0)
		t.eq(Population.builtAtRuntime(state), 13)
		t.eq(Population.totalBodies(state), 90)
		-- reserve gone: drop to the hard-cap floors (townsperson 8 -> 4 frees 4 bodies)
		d = Population.pickBody("townsperson", state, cfg)
		t.eq(d.kind, "capFloors")
		Population.apply(state, d)
		t.truthy(state.atCap)
		t.truthy(Population.floorsOk(state, cfg))
		-- the protected posts never supply anyone
		for _ = 1, 20 do
			d = Population.pickBody("townsperson", state, cfg)
			if d.kind == "wait" then
				break
			end
			t.truthy(
				d.fromPost ~= "police" and d.fromPost ~= "hospitalStaff" and d.fromPost ~= "ambulanceCrew",
				d.fromPost or ""
			)
			Population.apply(state, d)
			t.truthy(Population.floorsOk(state, cfg))
		end
	end)

	t.test("a hospital promotion takes a hospital body only above the floor of 10", function()
		local cfg = Population.plan()
		local state = Population.newState(cfg)
		for i = 1, 4 do
			local d = Population.pickBody("hospitalStaff", state, cfg)
			t.eq(d.kind, "body", `promotion {i}`)
			Population.apply(state, d)
		end
		local d = Population.pickBody("hospitalStaff", state, cfg)
		t.neq(d.kind, "body", "the 10 AI staff stay")
		t.eq(state.bodies.hospitalStaff.ai, 10)
	end)

	t.test("1,000 random joins, leaves and promotions up to 49 players never break a floor", function()
		local rng = lcg(5)
		local cfg = Population.plan()
		local state = Population.newState(cfg)
		local held: { string } = {}
		local posts = { "townsperson", "townsperson", "townsperson", "hospitalStaff", "police", "shopWorker" }
		local waits = 0
		for step = 1, 1000 do
			local r = rng()
			if r < 0.55 and #held < 49 then
				local post = posts[math.floor(rng() * #posts) + 1]
				local d = Population.pickBody(post, state, cfg)
				if d.kind == "wait" then
					waits += 1
				else
					Population.apply(state, d)
					table.insert(held, post)
				end
			elseif #held > 0 then
				local i = math.floor(rng() * #held) + 1
				Population.release(state, held[i])
				table.remove(held, i)
			end
			local ok, violations = Population.floorsOk(state, cfg)
			t.truthy(ok, `step {step}: {table.concat(violations, "; ")}`)
			t.truthy(Population.totalBodies(state) <= cfg.hardCap, "never above the hard cap")
			t.eq(Population.humanPlayers(state), #held)
		end
		t.eq(waits, 0, `{waits} waits (a join is never refused inside the 49, §1.5)`)
	end)

	t.test("release of a post with no player body is an error", function()
		local cfg = Population.plan()
		local state = Population.newState(cfg)
		t.fails(function()
			Population.release(state, "police")
		end, "no player body")
	end)
end
