--!strict
-- tools/compile W1 data tests (BUILD_PLAN §3.12, §3.13, §4.4 #7): the compiled W1 modules hold the
-- brief's numbers (12 hollows with H12 and the log; the rev-4 population sums for invariants 11/20;
-- 8 hospital rooms; 4 FRB interiors; every harvest patch with a reason), and the schema regex
-- subset handles the lot `seat` alternation.
local Schema = require("@tests/../tools/compile/lib/Schema")
local Hollows = require("../../generated/Hollows") :: any
local Population = require("../../generated/Population") :: any
local Buildings = require("../../generated/Buildings") :: any
local Interiors = require("../../generated/Interiors") :: any
local Patches = require("../../generated/HarvestPatches") :: any
local LotTypes = require("../../generated/LotTypes") :: any
local Ext = require("../../generated/TerrainExtensions") :: any

return function(t)
	t.test("hollows: 12 claimable (2 premium, 1 escape with 3 distinct exits, 9 single) + the log", function()
		local tiers: { [string]: number } = {}
		for _, h in Hollows.hollows do
			t.truthy(h.claimable, h.id)
			tiers[h.tier] = (tiers[h.tier] or 0) + 1
		end
		t.eq(#Hollows.hollows, 12)
		t.eq(tiers.premium, 2)
		t.eq(tiers.escape, 1)
		t.eq(tiers.single, 9)
		t.eq(Hollows.log.claimable, false)
		t.eq(Hollows.log.routeKind, "tunnel")
		for _, h in Hollows.hollows do
			if h.id == "H12" then
				t.eq(#h.knotholes, 3)
			end
		end
	end)

	t.test("population: rev-4 sums (invariants 11 and 20) and the brief's floors", function()
		local maxPlayers, humanSlots = 49, 35 -- BUILD_PLAN §3.7 Ladder values (the data must not state them)
		local expect = { frb = { 72, 35, 31 }, w3c = { 84, 46, 38 } }
		for _, phase in Population.phases do
			local standing, floor, full = 0, 0, 0
			for _, p in Population.posts do
				standing += p.standing[phase]
				floor += p.floor[phase]
				full += p.fullFloor[phase]
			end
			t.eq(standing, expect[phase][1], phase)
			t.eq(floor, expect[phase][2], phase)
			t.eq(full, expect[phase][3], phase)
			t.truthy(standing >= humanSlots + floor, phase)
			t.truthy(standing + Population.reserve[phase] >= maxPlayers + full, phase)
			t.truthy(Population.hardCap[phase] - full >= maxPlayers, phase)
		end
		t.eq(Population.animals.deer.bodies, 6)
		t.eq(Population.animals.squirrel.min, 10)
		t.eq(Population.animals.squirrel.max, 14)
	end)

	t.test("buildings, interiors, lot types, patches and the offroad district", function()
		t.eq(#Buildings.hospital.briefRooms, 8)
		t.eq(#Buildings.hospital.stations, 4)
		local n = 0
		for _ in Interiors do
			n += 1
		end
		t.eq(n, 4)
		local types = 0
		for _ in LotTypes.types do
			types += 1
		end
		t.eq(types, 74)
		for _, p in Patches.patches do
			t.truthy(#p.reason >= 12 and #p.cite >= 4, p.id)
		end
		t.eq(#Patches.lots, 20)
		local off = Ext.districts[1]
		t.eq(off.id, "offroad")
		t.eq(off.jurisdiction, false)
	end)

	t.test("schema regex subset: alternation, optional groups and literal '-'", function()
		local s = { type = "string", pattern = "^(graded_pad|terrain_centre|absolute:-?\\d+(\\.\\d+)?)$" }
		for _, ok in { "graded_pad", "terrain_centre", "absolute:8", "absolute:-2", "absolute:4.563" } do
			t.eq(#Schema.validate(s, ok), 0, ok)
		end
		for _, bad in { "absolute:", "absolute:4.", "graded", "absolute:x" } do
			t.eq(#Schema.validate(s, bad), 1, bad)
		end
		t.eq(#Schema.validate({ type = "string", pattern = "^[A-Za-z][A-Za-z0-9_.\\-]*$" }, "env_shrub-A"), 0)
	end)
end
