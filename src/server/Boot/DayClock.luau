--!strict
-- ServerScriptService.Server.Boot.DayClock
-- Publishes the game clock (BUILD_PLAN §1.7 "Game time: server epoch attribute; clients derive everything from
-- it"; brief v2 §15 decision 10: 72 real seconds per in-game day, sunrise and sunset held longer by
-- Time/DayCurve). The server writes ReplicatedStorage attributes ClockEpoch (server time), ClockBase (game
-- seconds at the epoch), ClockRate and ClockRealSecondsPerDay once at boot; Shared/Time/Clock.fromEngine reads
-- them and every client derives the same time of day from workspace:GetServerTimeNow(), so all clients stay
-- in sync without a per-frame remote (Client/World/Sky turns it into lighting). The server never drives
-- Lighting.ClockTime: World/LightingPreset's golden afternoon stays the server's own (and the engine smoke's)
-- state. A new server opens on START_DAY at START_HOUR: a golden afternoon whose first night has a bright
-- waxing gibbous moon (Time/Moon age 9).
-- Interface: START_DAY, START_HOUR, REAL_SECONDS_PER_DAY, base(startDay?, startHour?, realSecondsPerDay?) ->
--   game seconds (pure); publish(rs, now?) -> { epoch, base, rate } (an existing epoch is kept)
-- No side effects on require.

local Import = require("../Import")
local DayCurve = Import.shared("Time/DayCurve") :: typeof(require("../../shared/Time/DayCurve"))

local DayClock = {}

DayClock.START_DAY = 9
DayClock.START_HOUR = 16.75 -- golden afternoon (DayCurve goldenPm 16:30-18:30)
DayClock.REAL_SECONDS_PER_DAY = 72 -- Tunables clock.realSecondsPerDay (brief v2 §15 decision 10)

-- Game seconds at which the clock reads `startHour` on `startDay`.
function DayClock.base(startDay: number?, startHour: number?, realSecondsPerDay: number?): number
	local day = startDay or DayClock.START_DAY
	local hour = startHour or DayClock.START_HOUR
	local rspd = realSecondsPerDay or DayClock.REAL_SECONDS_PER_DAY
	return (day + DayCurve.dayFracAt(hour)) * rspd
end

function DayClock.publish(rs: Instance, now: number?): { epoch: number, base: number, rate: number }
	local epoch = rs:GetAttribute("ClockEpoch")
	if type(epoch) == "number" then
		return {
			epoch = epoch,
			base = (rs:GetAttribute("ClockBase") :: number?) or 0,
			rate = (rs:GetAttribute("ClockRate") :: number?) or 1,
		}
	end
	local t = now or workspace:GetServerTimeNow()
	local base = DayClock.base()
	rs:SetAttribute("ClockRealSecondsPerDay", DayClock.REAL_SECONDS_PER_DAY)
	rs:SetAttribute("ClockBase", base)
	rs:SetAttribute("ClockRate", 1)
	rs:SetAttribute("ClockEpoch", t) -- last: a client that sees the epoch sees the rest
	return { epoch = t, base = base, rate = 1 }
end

return DayClock
