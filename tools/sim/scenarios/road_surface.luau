--!strict
-- Scenario: cars where the drawn road and World/Height disagree most. The bake lays roads as flat parts;
-- level across their width (until 2026-11-11) they stood well off the terrain the ghosts were seated
-- on. Three places, each reached within a few seconds:
--   * the eastbound sedan climbing the commercial boulevard into the cross street at x = 867.5: the
--     cross street's slab stood up to 2.7 st proud of the boulevard (a ledge the car drove straight
--     into), and the boulevard's own slab was off the terrain by its crossfall
--   * the northbound sedan and the dump truck crossing the east-west streets at z = 405 (the same
--     thing on a narrower street: 1.5 and 2.1 st)
--   * the trolley on its track along the boulevard's edge (z = 22), where the crossfall is largest
-- Fixed by rolling the road parts to the crossfall (Shared/World/RoadSurface, worldgen/Plan.road) and
-- seating the ghosts on those parts, pitched and rolled with them (Traffic/Ghost.seat).
local Fleet = require("@shared/Traffic/Fleet")
local Replay = require("../lib/Replay")

local function entry(id: number): any
	for _, e in Fleet.ENTRIES do
		if e.id == id then
			return e
		end
	end
	error(`no fleet entry {id}`)
end

local scenario: Replay.Scenario = {
	name = "road_surface",
	about = "sedans, a dump truck and the trolley across the town's road seams and crossfalls",
	seconds = 30,
	ci = 15,
	entries = { entry(1), entry(4), entry(6), entry(13) },
	setup = function(sim: Replay.Sim)
		local sedanNB, dumpNB, sedanEB = sim.traffic.byId[1], sim.traffic.byId[4], sim.traffic.byId[6]
		sedanNB.s = 1020 -- the crossing at z = 405 is at s = 1051
		dumpNB.s = 990 -- its crossing at z = 405 is at s = 1022
		sedanEB.s = 80 -- the cross street's west edge (x = 831) is at s = 128
	end,
	expect = {
		none = { "sink", "float", "height_jump", "pitch_jump", "roll_missing", "hover", "ledge", "buried" },
	},
}

return scenario
