--!strict
-- ReplicatedStorage.Shared.Time.DayCurve
-- The non-linear day (BUILD_PLAN §1.4, §3.8 clock.dayCurve; brief v2 §15 dec 10): the real day is cut
-- into seven segments whose real-time shares are tunable (night .20, sunrise .10, golden am .12, day
-- .30, golden pm .12, sunset .10, blue .06) while each covers a fixed span of clock hours, so sunrise
-- and sunset are held longer than a linear clock would. Pure.
-- Interface: SEGMENTS; hourAt(dayFrac, shares?) -> hour in [0, 24); dayFracAt(hour, shares?) -> [0, 1);
--            segmentAt(dayFrac, shares?) -> name. dayFrac is the real fraction of the day since midnight.

export type Shares = { [string]: number }

local DayCurve = {}

-- Segment order from the start of night; `hours` is each segment's clock span. Spans sum to 24.
DayCurve.START_HOUR = 20.5
DayCurve.SEGMENTS = {
	{ name = "night", hours = 8.5 }, -- 20:30 -> 05:00
	{ name = "sunrise", hours = 1.5 }, -- 05:00 -> 06:30
	{ name = "goldenAm", hours = 2.0 }, -- 06:30 -> 08:30
	{ name = "day", hours = 8.0 }, -- 08:30 -> 16:30
	{ name = "goldenPm", hours = 2.0 }, -- 16:30 -> 18:30
	{ name = "sunset", hours = 1.25 }, -- 18:30 -> 19:45
	{ name = "blue", hours = 0.75 }, -- 19:45 -> 20:30
}

DayCurve.DEFAULT_SHARES = {
	night = 0.20,
	sunrise = 0.10,
	goldenAm = 0.12,
	day = 0.30,
	goldenPm = 0.12,
	sunset = 0.10,
	blue = 0.06,
} :: Shares

local function normalised(shares: Shares?): { number }
	local s = shares or DayCurve.DEFAULT_SHARES
	local total = 0
	for _, seg in DayCurve.SEGMENTS do
		total += s[seg.name] or 0
	end
	assert(total > 0, "DayCurve: shares sum to zero")
	local out = {}
	for i, seg in DayCurve.SEGMENTS do
		out[i] = (s[seg.name] or 0) / total
	end
	return out
end

-- Curve position (real fraction from the start of night) -> hours after START_HOUR, and the segment.
local function curveToHours(c: number, w: { number }): (number, number)
	local acc, hours = 0, 0
	for i, seg in DayCurve.SEGMENTS do
		local share = w[i]
		if c < acc + share or i == #DayCurve.SEGMENTS then
			local local01 = if share > 0 then math.clamp((c - acc) / share, 0, 1) else 0
			return hours + local01 * seg.hours, i
		end
		acc += share
		hours += seg.hours
	end
	return 24, #DayCurve.SEGMENTS
end

local function hoursToCurve(h: number, w: { number }): number
	local acc, hours = 0, 0
	for i, seg in DayCurve.SEGMENTS do
		if h < hours + seg.hours or i == #DayCurve.SEGMENTS then
			return acc + w[i] * math.clamp((h - hours) / seg.hours, 0, 1)
		end
		acc += w[i]
		hours += seg.hours
	end
	return 1
end

-- Real fraction of the day at which midnight falls on the curve (so day counts roll at 00:00).
local function midnightOffset(w: { number }): number
	return hoursToCurve(24 - DayCurve.START_HOUR, w)
end

function DayCurve.hourAt(dayFrac: number, shares: Shares?): number
	local w = normalised(shares)
	local c = (dayFrac % 1 + midnightOffset(w)) % 1
	local h = curveToHours(c, w)
	return (DayCurve.START_HOUR + h) % 24
end

function DayCurve.segmentAt(dayFrac: number, shares: Shares?): string
	local w = normalised(shares)
	local c = (dayFrac % 1 + midnightOffset(w)) % 1
	local _, i = curveToHours(c, w)
	return DayCurve.SEGMENTS[i].name
end

function DayCurve.dayFracAt(hour: number, shares: Shares?): number
	local w = normalised(shares)
	local h = (hour - DayCurve.START_HOUR) % 24
	return (hoursToCurve(h, w) - midnightOffset(w)) % 1
end

return DayCurve
