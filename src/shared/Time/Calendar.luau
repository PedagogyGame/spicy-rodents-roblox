--!strict
-- ReplicatedStorage.Shared.Time.Calendar
-- Weeks, winter (week 6 of each 6-week cycle) and raid week (BUILD_PLAN §1.4, D19).
-- The cycle numbers below are placeholders until Tunables lands (§3.8: clock.weeksPerCycle,
-- clock.winterWeek); Calendar.configure() lets Tunables override them without a re-require.
--
-- This module also carries the W0 proof that relative string requires resolve the same way
-- under Lune, Rojo and the Roblox engine (spike S1 BootSmoke requires it in the real engine).

local Moon = require("./Moon")

local Calendar = {}

Calendar.DAYS_PER_WEEK = 7
Calendar.WEEKS_PER_CYCLE = 6
Calendar.WINTER_WEEK = 6

function Calendar.configure(weeksPerCycle: number, winterWeek: number)
	Calendar.WEEKS_PER_CYCLE = weeksPerCycle
	Calendar.WINTER_WEEK = winterWeek
end

-- 1-based week within the current cycle.
function Calendar.week(day: number): number
	local weekIndex = math.floor(day / Calendar.DAYS_PER_WEEK)
	return (weekIndex % Calendar.WEEKS_PER_CYCLE) + 1
end

function Calendar.isWinter(day: number): boolean
	return Calendar.week(day) == Calendar.WINTER_WEEK
end

-- Lunar age is part of the calendar read-out the Clock exposes (§1.4 Clock.game()).
function Calendar.lunarAge(day: number): number
	return Moon.age(day)
end

return Calendar
