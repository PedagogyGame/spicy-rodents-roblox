--!strict
-- ReplicatedStorage.Shared.Time.Moon
-- Lunar phase from the in-game day count (synodic month 29.53 days; BUILD_PLAN §1.4, D19).
-- Reused from the feasibility smoke project (spec/roblox_feasibility.md, Part B.f).

local Moon = {}

Moon.SYNODIC_DAYS = 29.530588

local PHASE_NAMES = {
	"new",
	"waxing crescent",
	"first quarter",
	"waxing gibbous",
	"full",
	"waning gibbous",
	"last quarter",
	"waning crescent",
}

-- 0 = new, 0.5 = full, wraps at 1.
function Moon.phase(day: number): number
	return (day / Moon.SYNODIC_DAYS) % 1
end

-- Age in days since the last new moon.
function Moon.age(day: number): number
	return Moon.phase(day) * Moon.SYNODIC_DAYS
end

-- Index 1..8 into the eight named phases (1 = new, 5 = full).
function Moon.phaseIndex(day: number): number
	return (math.floor(Moon.phase(day) * 8 + 0.5) % 8) + 1
end

function Moon.name(day: number): string
	return PHASE_NAMES[Moon.phaseIndex(day)]
end

return Moon
