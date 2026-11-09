--!strict
-- ReplicatedStorage.Shared.Time.Clock
-- Game time from the server clock plus an epoch (BUILD_PLAN §1.4, §1.7 "Game time: server epoch
-- attribute; clients derive everything from it"). Time runs at `rate` game seconds per real second
-- (1 normally; the outbreak cinematic raises it, D31); a rate change re-anchors the epoch so game time
-- is continuous. Pure: the engine passes workspace:GetServerTimeNow and the epoch/rate attributes
-- (fromEngine); Lune passes a fake clock.
-- Interface: new(opts) -> Clock; Clock:now() (server seconds); Clock:gameSeconds(); Clock:game() ->
--            { day, dayFrac, hour, segment, week, isWinter, lunarAge, phase, raidWeek }; Clock:setRate(mult, at?);
--            Clock:anchor() -> { epoch, base, rate } (what the server replicates); Clock.raidWeek(day);
--            Clock.fromEngine(realSecondsPerDay?)

local Calendar = require("./Calendar")
local DayCurve = require("./DayCurve")
local Moon = require("./Moon")

export type GameTime = {
	day: number, -- whole in-game days since the epoch
	dayFrac: number, -- real fraction of the current day since midnight
	hour: number, -- clock hour through the non-linear curve, [0, 24)
	segment: string,
	week: number,
	isWinter: boolean,
	lunarAge: number,
	phase: string,
	raidWeek: number,
}

export type Options = {
	serverTime: () -> number,
	epoch: number?, -- server time at which game time was `base`
	base: number?, -- game seconds at the epoch (default 0)
	rate: number?, -- game seconds per real second (default 1)
	realSecondsPerDay: number?, -- default 72 (Tunables clock.realSecondsPerDay)
	shares: DayCurve.Shares?,
}

export type Clock = {
	serverTime: () -> number,
	epoch: number,
	base: number,
	rate: number,
	realSecondsPerDay: number,
	shares: DayCurve.Shares?,
	now: (self: Clock) -> number,
	gameSeconds: (self: Clock) -> number,
	game: (self: Clock) -> GameTime,
	setRate: (self: Clock, mult: number, at: number?) -> (),
	anchor: (self: Clock) -> { epoch: number, base: number, rate: number },
}

local Clock = {}

function Clock.raidWeek(day: number): number
	return Calendar.raidWeek(day)
end

function Clock.new(opts: Options): Clock
	local clock = {
		serverTime = opts.serverTime,
		epoch = opts.epoch or opts.serverTime(),
		base = opts.base or 0,
		rate = opts.rate or 1,
		realSecondsPerDay = opts.realSecondsPerDay or 72,
		shares = opts.shares,
	} :: Clock

	function clock.now(self: Clock): number
		return self.serverTime()
	end

	function clock.gameSeconds(self: Clock): number
		return self.base + (self.serverTime() - self.epoch) * self.rate
	end

	function clock.game(self: Clock): GameTime
		local days = self:gameSeconds() / self.realSecondsPerDay
		local day = math.floor(days)
		local frac = days - day
		return {
			day = day,
			dayFrac = frac,
			hour = DayCurve.hourAt(frac, self.shares),
			segment = DayCurve.segmentAt(frac, self.shares),
			week = Calendar.week(day),
			isWinter = Calendar.isWinter(day),
			lunarAge = Moon.age(days),
			phase = Moon.name(days),
			raidWeek = Calendar.raidWeek(day),
		}
	end

	function clock.setRate(self: Clock, mult: number, at: number?)
		assert(mult >= 0 and mult == mult, "Clock.setRate: bad multiplier")
		local t = at or self.serverTime()
		self.base = self.base + (t - self.epoch) * self.rate
		self.epoch = t
		self.rate = mult
	end

	function clock.anchor(self: Clock): { epoch: number, base: number, rate: number }
		return { epoch = self.epoch, base = self.base, rate = self.rate }
	end

	return clock
end

-- Engine constructor: reads ReplicatedStorage attributes ClockEpoch / ClockBase / ClockRate (the
-- server writes them once at boot and on every setRate). Never called on require.
function Clock.fromEngine(realSecondsPerDay: number?): Clock
	local rs = game:GetService("ReplicatedStorage")
	local function serverTime(): number
		return workspace:GetServerTimeNow()
	end
	return Clock.new({
		serverTime = serverTime,
		epoch = rs:GetAttribute("ClockEpoch") or serverTime(),
		base = rs:GetAttribute("ClockBase") or 0,
		rate = rs:GetAttribute("ClockRate") or 1,
		realSecondsPerDay = realSecondsPerDay,
	})
end

return Clock
