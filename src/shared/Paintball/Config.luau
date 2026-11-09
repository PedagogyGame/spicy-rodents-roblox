--!strict
-- ReplicatedStorage.Shared.Paintball.Config
-- The arena constants of paintball/arena.json (BUILD_PLAN §3, D29; spike S18), in studs and seconds.
-- W4 loads them from the compiled data; the spike pins the plan's values here.

local Config = {
	projectile = {
		speed = 90, -- studs/s muzzle speed
		drop = 9.8, -- studs/s^2 ("travel and slight drop": 4.9 studs over a full second)
		ttl = 1.5, -- seconds before a ball that hit nothing is dropped
		radius = 0.25, -- studs
	},
	magazine = 5,
	fireInterval = 0.25, -- seconds between shots
	reloadSecs = 1.6,
	historySecs = 1.0, -- lag-compensation pose history per body
	historyHz = 60,
	maxRewindSecs = 0.4, -- a claimed rewind beyond this is clamped (anti-cheat)
	splatPool = 400,
	body = { radius = 1.2, low = 1.0, high = 4.4, eye = 4.0 }, -- capsule above the feet, studs
}

return Config
