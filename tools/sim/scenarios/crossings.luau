--!strict
-- Scenario: the whole fleet with people on the roads. The fleet scenario has nobody in the way, so no
-- vehicle ever brakes for a person; in the game 100 townspeople and the squirrels cross all the time.
-- Scripted walkers cross the main street, the west street and the boulevard on timers, one stands on the
-- trolley track, and a player's squirrel sits in the southbound lane for a few seconds every minute:
-- sedans brake and hard-stop (traffic.md §5.1), heavies and the trolley yield (§5.2), then pull away.
local Height = require("@shared/World/Height")
local Replay = require("../lib/Replay")

type Walk = { from: { number }, to: { number }, speed: number, every: number, start: number }

-- stylua: ignore
local WALKS: { Walk } = {
	-- across the main street (x = 0, lanes at x = -13.5 and 13.5), north of the centre
	{ from = { -32, 150 },   to = { 32, 150 },    speed = 4,  every = 38, start = 6 },
	{ from = { 32, -260 },   to = { -32, -260 },  speed = 4,  every = 47, start = 21 },
	-- across the west street (x = -450, lane at x = -463.5)
	{ from = { -490, 40 },   to = { -430, 40 },   speed = 4,  every = 53, start = 12 },
	-- across the boulevard (z = 0, lanes at z = -14 and 14, the trolley at z = 21.6)
	{ from = { 1000, -34 },  to = { 1000, 40 },   speed = 4,  every = 44, start = 9 },
	{ from = { 1400, 40 },   to = { 1400, -34 },  speed = 4,  every = 61, start = 30 },
	-- a runner darting out in front of the eastbound traffic
	{ from = { 1200, 30 },   to = { 1200, 2 },    speed = 14, every = 35, start = 17 },
}

-- someone standing on the trolley track for 6 s every 80 s, and a squirrel in the southbound lane
local STAND = { x = 1300, z = 21.625, every = 80, start = 25, hold = 6 }
local SQUIRREL = { x = 13.5, z = -120, every = 60, start = 40, hold = 5 }

local scenario: Replay.Scenario = {
	name = "crossings",
	about = "the 25 vehicles with walkers crossing the streets, a person on the trolley track and a squirrel in a lane",
	seconds = 600,
	ci = 45,
	world = function(sim: Replay.Sim): any
		local t = sim.wall
		local people, squirrels = {}, {}
		for _, w in WALKS do
			local phase = (t - w.start) % w.every
			local dx, dz = w.to[1] - w.from[1], w.to[2] - w.from[2]
			local length = math.sqrt(dx * dx + dz * dz)
			local u = phase * w.speed / length
			if t >= w.start and u <= 1 then
				local x, z = w.from[1] + dx * u, w.from[2] + dz * u
				table.insert(people, { x = x, y = Height.at(x, z), z = z, kind = "human" })
			end
		end
		if t >= STAND.start and (t - STAND.start) % STAND.every < STAND.hold then
			table.insert(people, { x = STAND.x, y = Height.at(STAND.x, STAND.z), z = STAND.z, kind = "human" })
		end
		if t >= SQUIRREL.start and (t - SQUIRREL.start) % SQUIRREL.every < SQUIRREL.hold then
			-- a player-held squirrel: the fleet yields to it and the fatal sweep tests it
			table.insert(squirrels, {
				id = "squirrel",
				x = SQUIRREL.x,
				y = Height.at(SQUIRREL.x, SQUIRREL.z) + 0.45,
				z = SQUIRREL.z,
			})
		end
		return { people = people, squirrels = squirrels }
	end,
}

return scenario
