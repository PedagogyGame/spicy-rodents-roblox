--!strict
-- World/SkyKeys, Server/Boot/DayClock and the client Sky's pure parts (brief v2 §3 Backdrop sky, §15 decision 10;
-- worldgen_districts_art §14.3-14.4): the golden afternoon is LightingPreset.GOLDEN exactly, the ClockTime warp puts
-- Roblox's sun on the horizon inside the held-longer sunrise and sunset moments, the look never jumps, night is
-- dark and lamplit, the moon's rows draw the right lit fraction, and every client reads the same time.
local SkyKeys = require("@shared/World/SkyKeys")
local LightingPreset = require("@shared/World/LightingPreset")
local DayCurve = require("@shared/Time/DayCurve")
local Clock = require("@shared/Time/Clock")
local Moon = require("@shared/Time/Moon")
local DayClock = require("@server/Boot/DayClock")
local Sky = require("@client/World/Sky")

local function hex(s: string): { number }
	return {
		tonumber(string.sub(s, 1, 2), 16) :: number,
		tonumber(string.sub(s, 3, 4), 16) :: number,
		tonumber(string.sub(s, 5, 6), 16) :: number,
	}
end

return function(t)
	t.test("golden afternoon is World/LightingPreset.GOLDEN (the default look)", function()
		local G = LightingPreset.GOLDEN
		for _, h in { 16.5, 17.0, 17.6 } do
			local s = SkyKeys.stateAt(h)
			t.near(s.brightness, G.brightness, 1e-9)
			t.near(s.exposure, G.exposure, 1e-9)
			t.near(s.atmDensity, G.atmosphere.density, 1e-9)
			t.deepEq(s.top, hex(G.colorShiftTop))
			t.deepEq(s.outdoor, hex(G.outdoorAmbient))
			t.deepEq(s.atmColor, hex(G.atmosphere.color))
			t.eq(s.lamps, 0)
		end
		t.near(SkyKeys.clockTimeAt(16.5), G.clockTime, 1e-9, "golden pm starts at the preset's ClockTime")
	end)

	t.test("warp: the sun crosses the horizon inside the sunrise and sunset moments; monotone over the day", function()
		t.near(SkyKeys.clockTimeAt(5.83), 6.0, 1e-9)
		t.near(SkyKeys.clockTimeAt(19.08), 18.0, 1e-9)
		t.eq(DayCurve.segmentAt(DayCurve.dayFracAt(5.83)), "sunrise")
		t.eq(DayCurve.segmentAt(DayCurve.dayFracAt(19.08)), "sunset")
		local prev = SkyKeys.clockTimeAt(5.0)
		local unwrapped = prev
		for i = 1, 2400 do
			local h = (5.0 + i * 24 / 2400) % 24
			local ct = SkyKeys.clockTimeAt(h)
			local step = (ct - prev) % 24
			t.truthy(step >= 0 and step < 0.1, `warp step {step} at {h}`)
			unwrapped += step
			prev = ct
		end
		t.near(unwrapped - SkyKeys.clockTimeAt(5.0), 24, 1e-6, "one full turn per day")
	end)

	t.test("the look never jumps; night is dark and lamplit, the day is bright and unlit", function()
		local worst = 0
		local prev = SkyKeys.stateAt(0)
		for i = 1, 24 * 60 do
			local s = SkyKeys.stateAt(i / 60)
			worst = math.max(worst, math.abs(s.brightness - prev.brightness), math.abs(s.lamps - prev.lamps))
			for ch = 1, 3 do
				worst = math.max(worst, math.abs(s.atmColor[ch] - prev.atmColor[ch]) / 255)
			end
			prev = s
		end
		t.truthy(worst < 0.08, `largest per-minute change {worst}`)
		local night, day = SkyKeys.stateAt(1.0), SkyKeys.stateAt(12.0)
		t.truthy(night.brightness < 0.6 and night.exposure < 0, "night dark")
		t.eq(night.lamps, 1)
		t.eq(day.lamps, 0)
		t.truthy(day.brightness > 2.5)
		t.truthy(SkyKeys.stateAt(19.08).raysIntensity >= 0.25, "sunset sun rays")
		t.truthy(SkyKeys.stateAt(5.83).atmGlare >= 0.5, "sunrise glare")
	end)

	t.test("sunrise and sunset are held longer than a linear clock", function()
		local function realShare(h0: number, h1: number): number
			return (DayCurve.dayFracAt(h1) - DayCurve.dayFracAt(h0)) % 1
		end
		t.truthy(realShare(5.0, 6.5) > 1.5 / 24 * 1.4, "sunrise")
		t.truthy(realShare(18.5, 19.75) > 1.25 / 24 * 1.4, "sunset")
	end)

	t.test("moon rows: the lit area matches the illuminated fraction; the lit limb faces +x", function()
		for _, phase in { 0, 0.125, 0.25, 0.4, 0.5, 0.6, 0.75, 0.9 } do
			local rows = SkyKeys.moonRows(phase, 200)
			local lit, disc = 0, 0
			for _, r in rows do
				lit += (r.litTo - r.litFrom) * r.height
				disc += (r.litTo - r.darkFrom) * r.height
				t.truthy(r.litFrom >= r.darkFrom - 1e-9 and r.litTo >= r.litFrom - 1e-9)
			end
			t.near(lit / disc, SkyKeys.illumination(phase), 0.01, `phase {phase}`)
		end
		t.near(SkyKeys.illumination(Moon.phase(14.765)), 1, 1e-3, "full")
		t.near(SkyKeys.illumination(0), 0, 1e-9, "new")
	end)

	t.test("DayClock: a new server opens on a golden afternoon with a waxing gibbous moon; clients agree", function()
		local base = DayClock.base()
		local now = 1000
		local function fakeTime(): number
			return now
		end
		local perDay = DayClock.REAL_SECONDS_PER_DAY
		local a = Clock.new({ serverTime = fakeTime, epoch = 500, base = base, realSecondsPerDay = perDay })
		local b = Clock.new({ serverTime = fakeTime, epoch = 500, base = base, realSecondsPerDay = perDay })
		now = 500
		local g = a:game()
		t.eq(g.day, DayClock.START_DAY)
		t.near(g.hour, DayClock.START_HOUR, 1e-6)
		t.eq(g.segment, "goldenPm")
		t.eq(g.phase, "waxing gibbous")
		now = 500 + 123.4
		t.deepEq(a:game(), b:game())
		-- one in-game day is 12 real minutes (owner 2026-11-10), and dawn and dusk are slow: the sun
		-- takes over a minute to rise and to set, with over a minute of golden light either side
		t.eq(perDay, 720)
		for _, seg in { "sunrise", "sunset", "goldenAm", "goldenPm" } do
			t.truthy(
				DayCurve.DEFAULT_SHARES[seg] * perDay >= 70,
				`{seg} lasts {DayCurve.DEFAULT_SHARES[seg] * perDay} s`
			)
		end
		now = 500 + 140
		t.eq(a:game().segment, "sunset", "over two minutes in, the sun is still setting")
		t.eq(a:game().day, DayClock.START_DAY)
		now = 500 + perDay
		t.near(a:game().hour, DayClock.START_HOUR, 1e-6)
		t.eq(a:game().day, DayClock.START_DAY + 1)
		-- before the server publishes, the client shows the same opening moment
		t.eq(Sky.FALLBACK_DAY, DayClock.START_DAY)
		t.eq(Sky.FALLBACK_HOUR, DayClock.START_HOUR)
	end)

	t.test("weather: slow cloud cover within Roblox's range", function()
		for d = 0, 40, 0.37 do
			local w = SkyKeys.weather(d)
			t.truthy(w >= 0.2 and w <= 0.72)
			t.truthy(math.abs(SkyKeys.weather(d + 1 / 72) - w) < 0.01, "changes slowly")
		end
	end)
end
