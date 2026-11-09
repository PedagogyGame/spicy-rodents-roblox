--!strict
-- Shared/Time/Clock + DayCurve + Calendar (BUILD_PLAN §1.4, §3.8 clock, §4.4 #1): the non-linear day
-- holds sunrise and sunset, is monotonic and invertible; game time is continuous through rate changes.
local Calendar = require("@shared/Time/Calendar")
local Clock = require("@shared/Time/Clock")
local DayCurve = require("@shared/Time/DayCurve")

return function(t)
	t.test("DayCurve: spans sum to 24 h, shares to 1; midnight at frac 0", function()
		local h = 0
		for _, s in DayCurve.SEGMENTS do
			h += s.hours
		end
		t.near(h, 24, 1e-12)
		local share = 0
		for _, v in DayCurve.DEFAULT_SHARES do
			share += v
		end
		t.near(share, 1, 1e-12)
		t.near(DayCurve.hourAt(0), 0, 1e-9)
	end)

	t.test("DayCurve: monotonic over the day and inverse of dayFracAt", function()
		local prev = -1
		for i = 0, 999 do
			local f = i / 1000
			local hour = DayCurve.hourAt(f)
			t.truthy(hour > prev or (prev > 23.9 and hour < 0.1), `frac {f}`)
			prev = hour
			t.near(DayCurve.dayFracAt(hour), f, 1e-9)
		end
	end)

	t.test("DayCurve: sunrise and sunset are held longer than a linear clock", function()
		-- sunrise spans 1.5 h of clock but 10 % of the real day (a linear clock gives it 6.25 %)
		local a, b = DayCurve.dayFracAt(5.0), DayCurve.dayFracAt(6.5)
		t.near(b - a, 0.10, 1e-9)
		local c, d = DayCurve.dayFracAt(18.5), DayCurve.dayFracAt(19.75)
		t.near(d - c, 0.10, 1e-9)
		t.eq(DayCurve.segmentAt(DayCurve.dayFracAt(5.5)), "sunrise")
		t.eq(DayCurve.segmentAt(DayCurve.dayFracAt(12)), "day")
		t.eq(DayCurve.segmentAt(DayCurve.dayFracAt(2)), "night")
	end)

	t.test("Clock: 72 s days, weeks, winter, raid week, moon", function()
		local now = 1000
		local c = Clock.new({
			serverTime = function()
				return now
			end,
			epoch = 1000,
		})
		local g = c:game()
		t.eq(g.day, 0)
		t.eq(g.week, 1)
		now = 1000 + 72 * 36 -- day 36: week 6 of the cycle = winter
		g = c:game()
		t.eq(g.day, 36)
		t.eq(g.week, 6)
		t.truthy(g.isWinter)
		t.eq(g.raidWeek, 5)
		t.eq(Clock.raidWeek(13), 1)
		t.eq(Calendar.raidWeek(14), 2)
		t.near(g.lunarAge, 36 % 29.530588, 1e-9)
		t.isType(g.phase, "string")
	end)

	t.test("Clock: setRate re-anchors so game time is continuous", function()
		local now = 0
		local c = Clock.new({
			serverTime = function()
				return now
			end,
		})
		now = 50
		local before = c:gameSeconds()
		c:setRate(40)
		t.near(c:gameSeconds(), before, 1e-12)
		now = 51
		t.near(c:gameSeconds(), before + 40, 1e-9)
		local a = c:anchor()
		t.eq(a.rate, 40)
		local mirror = Clock.new({
			serverTime = function()
				return now
			end,
			epoch = a.epoch,
			base = a.base,
			rate = a.rate,
		})
		t.near(mirror:gameSeconds(), c:gameSeconds(), 1e-12) -- clients derive the same time
		t.fails(function()
			c:setRate(-1)
		end)
	end)
end
