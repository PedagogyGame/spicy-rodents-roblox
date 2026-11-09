--!strict
-- Server/Actors/BrainScheduler (BUILD_PLAN D4): tiers by distance to the nearest focus, 10/4/1 Hz
-- rates with staggered phases, dt handed to a brain equals its own tick interval, the per-frame
-- budget defers and round-robins, metrics report tiers and p99.
local BrainScheduler = require("@server/Actors/BrainScheduler")
local Common = require("@server/Actors/Brains/Common")

local function countingBrain(kind: string, cost: number?): (Common.Brain, { ticks: number, dts: { number } })
	local record = { ticks = 0, dts = {}, spin = 0 }
	local brain = {
		kind = kind,
		think = function(_self: Common.Brain, dt: number, _ctx: Common.Ctx)
			record.ticks += 1
			table.insert(record.dts, dt)
			if cost then
				local t0 = os.clock()
				local spin = 0
				while os.clock() - t0 < cost do
					spin += 1
				end
				record.spin = spin
			end
		end,
		suspend = function(_self: Common.Brain): Common.Snapshot
			return {}
		end,
		resume = function(_self: Common.Brain, _s: Common.Snapshot) end,
		onEvent = function(_self: Common.Brain, _e: { [string]: any }) end,
	}
	return (brain :: any) :: Common.Brain, record
end

local function ctx(): Common.Ctx
	return {
		now = 0,
		rng = function()
			return 0.5
		end,
		groundAt = function()
			return 0
		end,
		threats = {
			query = function()
				return 0
			end,
		} :: any,
		actorsById = {},
		bounds = { minX = -1e9, maxX = 1e9, minZ = -1e9, maxZ = 1e9 },
		routes = nil,
		queryBuffer = {},
	}
end

return function(t)
	t.test("tier by distance to the nearest focus: < 150 near, < 500 mid, else far", function()
		local s = BrainScheduler.new()
		s:setFocus(function()
			return { { x = 0, z = 0 }, { x = 1000, z = 0 } }
		end)
		s.focus = { { x = 0, z = 0 }, { x = 1000, z = 0 } }
		t.eq(s:tierOf(Common.newActor(1, "human", "a", "k", 100, 0, 0)), "near")
		t.eq(s:tierOf(Common.newActor(2, "human", "a", "k", 300, 0, 0)), "mid")
		t.eq(s:tierOf(Common.newActor(3, "human", "a", "k", 0, 700, 0)), "far")
		t.eq(s:tierOf(Common.newActor(4, "human", "a", "k", 1100, 0, 0)), "near", "nearest of two foci")
	end)

	t.test("rates: a near brain ticks ~10 Hz, mid ~4 Hz, far ~1 Hz over 10 simulated seconds", function()
		local s = BrainScheduler.new()
		s:setFocus(function()
			return { { x = 0, z = 0 } }
		end)
		local near, nearRec = countingBrain("near")
		local mid, midRec = countingBrain("mid")
		local far, farRec = countingBrain("far")
		s:register(1, near, Common.newActor(1, "h", "a", "near", 10, 0, 0), 0)
		s:register(2, mid, Common.newActor(2, "h", "a", "mid", 300, 0, 0), 0)
		s:register(3, far, Common.newActor(3, "h", "a", "far", 900, 0, 0), 0)
		local c = ctx()
		local now = 0
		for _ = 1, 600 do
			now += 1 / 60
			c.now = now
			s:step(1 / 60, now, c)
		end
		t.truthy(nearRec.ticks >= 99 and nearRec.ticks <= 101, `near {nearRec.ticks}`)
		t.truthy(midRec.ticks >= 39 and midRec.ticks <= 41, `mid {midRec.ticks}`)
		t.truthy(farRec.ticks >= 9 and farRec.ticks <= 11, `far {farRec.ticks}`)
		-- dt handed to a brain is its own interval (after the first staggered tick)
		for i = 2, #nearRec.dts do
			t.near(nearRec.dts[i], 0.1, 0.02)
		end
		local m = s:metrics()
		t.eq(m.tiers.near, 1)
		t.eq(m.tiers.mid, 1)
		t.eq(m.tiers.far, 1)
		t.eq(m.brains, 3)
	end)

	t.test("phases are staggered: 100 near brains spread over the 6 frames of a 10 Hz interval", function()
		local s = BrainScheduler.new()
		s.forceTier = "near"
		local perFrame = {}
		for i = 1, 100 do
			local b = countingBrain("b")
			s:register(i, b, Common.newActor(i, "h", "a", "b", 0, 0, 0), 0)
		end
		local c = ctx()
		local now = 0
		local maxTicked = 0
		for f = 1, 60 do
			now += 1 / 60
			c.now = now
			local m = s:step(1 / 60, now, c)
			perFrame[f] = m.ticked
			if m.ticked > maxTicked then
				maxTicked = m.ticked
			end
		end
		t.truthy(maxTicked <= 25, `worst frame ticked {maxTicked} of 100 (ideal ~17)`)
	end)

	t.test("budget: expensive brains are deferred, none starve, deferred count reported", function()
		local s = BrainScheduler.new({
			rates = { near = 10, mid = 4, far = 1 },
			ranges = { near = 150, mid = 500 },
			budgetMs = 0.3,
			historyFrames = 60,
		})
		s.forceTier = "near"
		local recs = {}
		for i = 1, 12 do
			local b, rec = countingBrain("slow", 0.0002) -- 0.2 ms each: at most 2 per frame fit the budget
			recs[i] = rec
			s:register(i, b, Common.newActor(i, "h", "a", "slow", 0, 0, 0), 0)
		end
		local c = ctx()
		local now = 0
		local deferred = 0
		for _ = 1, 120 do
			now += 1 / 60
			c.now = now
			deferred += s:step(1 / 60, now, c).deferred
		end
		t.truthy(deferred > 0, "some ticks were deferred")
		for i, rec in recs do
			t.truthy(rec.ticks >= 10, `brain {i} ticked {rec.ticks} times in 2 s`)
		end
		t.eq(s:metrics().deferredTotal, deferred)
	end)

	t.test("unregister removes the brain; metrics p99 and avg are finite", function()
		local s = BrainScheduler.new()
		local b = countingBrain("x")
		local actor = Common.newActor(1, "h", "a", "x", 0, 0, 0)
		s:register(1, b, actor, 0)
		t.fails(function()
			s:register(1, b, actor, 0)
		end, "already registered")
		s:unregister(1)
		s:unregister(1)
		t.eq(#s.entries, 0)
		local c = ctx()
		s:step(1 / 60, 1 / 60, c)
		local m = s:metrics()
		t.truthy(m.avgMs >= 0 and m.p99Ms >= 0 and m.frames == 1)
	end)
end
