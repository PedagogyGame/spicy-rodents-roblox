--!strict
-- Nut foraging (owner D16 #22; Shared/Foraging/ForageRules, NutSpots; Server/Foraging/ForageService and HollowService)
-- on the real town AI headless:
--   the rules: a spot's nuts grow back one per regrowDays from the first taken, a full spot stays full; reach, the
--   gap, who forages (never the Spicy Rodent)
--   a player's squirrel picks a nut up where the server holds it (placeOf: the last clean accepted motor packet), one
--   every gap, up to nine; told once when its paws are full; never by its root (the validator's invariant D: the root
--   at a spot and the held place away picks nothing; no held place, nothing), never from a fence over the nuts
--   the deposit into a hollow by the same held place (HollowService placeOf): the root inside and the held place out
--   stores nothing; the held place inside stores them
--   the computer's squirrels: one in reach eats a nut (nothing carried, so no hollow claimed) and sits nibbling (its
--   brain's bait); a look over the whole town costs well under a millisecond
local Data = require("@shared/Data")
local Height = require("@shared/World/Height")
local HollowLayout = require("@shared/World/HollowLayout")
local ForageRules = require("@shared/Foraging/ForageRules")
local NutSpots = require("@shared/Foraging/NutSpots")
local Tunables = require("@shared/Config/Tunables")
local TownAI = require("@server/AI/TownAI")
local HollowService = require("@server/Foraging/HollowService")
local ForageService = require("@server/Foraging/ForageService")
local TerrainExtensions = require("../../generated/TerrainExtensions")

local DT = 1 / 60

return function(t)
	local data = Data.default()
	local layout = HollowLayout.default() :: HollowLayout.Layout
	local C = ForageRules.C

	t.test("the rules: growing back from the first nut taken, a full spot stays full, reach, gap, who", function()
		local s = ForageRules.newSpot(3, 10)
		t.eq(s.left, 3)
		t.falsy(ForageRules.regrow(s, 3, 1 / 3, 50), "full stays full, nothing banked")
		t.truthy(ForageRules.take(s, 3, 50))
		t.truthy(ForageRules.take(s, 3, 50.1))
		t.truthy(ForageRules.take(s, 3, 50.2))
		t.falsy(ForageRules.take(s, 3, 50.2), "none left")
		t.eq(s.left, 0)
		t.falsy(ForageRules.regrow(s, 3, 1 / 3, 50.3), "the clock started with the first nut (day 50)")
		t.truthy(ForageRules.regrow(s, 3, 1 / 3, 50.34))
		t.eq(s.left, 1)
		t.falsy(ForageRules.regrow(s, 3, 1 / 3, 50.5))
		t.truthy(ForageRules.regrow(s, 3, 1 / 3, 50.7))
		t.eq(s.left, 2)
		t.truthy(ForageRules.regrow(s, 3, 1 / 3, 60))
		t.eq(s.left, 3, "never past the stock")
		t.falsy(ForageRules.regrow(s, 3, 1 / 3, 40), "a clock read earlier changes nothing")
		t.truthy(ForageRules.inReach(0, 0, 0, C.reach - 0.01, C.rise - 0.01, 0, C.reach, C.rise))
		t.falsy(ForageRules.inReach(0, 0, 0, C.reach + 0.01, 0, 0, C.reach, C.rise))
		t.falsy(ForageRules.inReach(0, 0, 0, 0, C.rise + 0.01, 0, C.reach, C.rise), "on a fence over it")
		t.truthy(ForageRules.ready(nil, 0, C.gap))
		t.falsy(ForageRules.ready(1, 1 + C.gap - 0.01, C.gap))
		t.truthy(ForageRules.ready(1, 1 + C.gap, C.gap))
		t.truthy(ForageRules.forages("squirrel", "normal"))
		t.falsy(ForageRules.forages("squirrel", "spicy"), "nuts do nothing for the Spicy Rodent")
		t.falsy(ForageRules.forages("human", nil))
	end)

	local rail: any = nil
	type Rig = {
		world: TownAI.World,
		hollows: HollowService.Service,
		forage: ForageService.Service,
		held: { [number]: { number }? },
		picks: { { id: number, spot: string, held: number, ai: boolean } },
		fulls: { { id: number, spot: string } },
		day: { v: number },
	}
	local function rig(squirrels: number?): Rig
		Height.configure(TerrainExtensions :: any)
		local world = TownAI.build({
			data = data,
			seed = 1,
			humans = 20,
			squirrels = squirrels or 3,
			deer = 0,
			fox = 0,
			rail = rail,
		})
		rail = world.rail
		local held: { [number]: { number }? } = {}
		local function placeOf(id: number): (number?, number?, number?)
			local p = held[id]
			if p == nil then
				return nil, nil, nil
			end
			return p[1], p[2], p[3]
		end
		local hollows = HollowService.new({ world = world, layout = layout, placeOf = placeOf })
		local picks, fulls = {}, {}
		local day = { v = 20 }
		local forage = ForageService.new({
			world = world,
			hollows = hollows,
			placeOf = placeOf,
			groundAt = Height.at,
			day = function(): number
				return day.v
			end,
			onPick = function(id: number, spot: NutSpots.Spot, n: number, ai: boolean)
				table.insert(picks, { id = id, spot = spot.id, held = n, ai = ai })
			end,
			onFull = function(id: number, spot: NutSpots.Spot)
				table.insert(fulls, { id = id, spot = spot.id })
			end,
			rng = function(): number
				return 0
			end,
		})
		return {
			world = world,
			hollows = hollows,
			forage = forage,
			held = held,
			picks = picks,
			fulls = fulls,
			day = day,
		}
	end
	local function squirrel(r: Rig, variant: string?): any
		for _, a in r.world.actors do
			if a.species == "squirrel" and a.variant == (variant or "normal") then
				return a
			end
		end
		error("no squirrel")
	end
	local function possess(r: Rig, a: any)
		if not r.world.possessed[a.id] then
			TownAI.suspend(r.world, a.id)
		end
	end
	-- run the service for `secs` at 30 frames a second from server time `from`; the new time
	local function run(r: Rig, from: number, secs: number): number
		local now = from
		for _ = 1, math.floor(secs * 30 + 0.5) do
			now += 1 / 30
			r.forage:step(1 / 30, now)
		end
		return now
	end
	local function picksBy(r: Rig, id: number): number
		local n = 0
		for _, p in r.picks do
			if p.id == id then
				n += 1
			end
		end
		return n
	end

	t.test("a player's squirrel picks nuts up where the server holds it: one every gap, never past nine", function()
		local r = rig()
		local a = squirrel(r)
		possess(r, a)
		local premium = NutSpots.byId("premium_h2_feeder") :: NutSpots.Spot
		local gy = Height.at(premium.x, premium.z)
		-- the root far off (where its client says), the held place at the pile
		a.x, a.y, a.z = premium.x + 200, gy + 1, premium.z
		r.held[a.id] = { premium.x + 0.6, gy + 0.05, premium.z - 0.4 }
		local now = run(r, 100, 0.2)
		t.eq(picksBy(r, a.id), 1, "the first nut at once")
		now = run(r, now, C.gap - 0.25)
		t.eq(picksBy(r, a.id), 1, "the next only after the gap")
		now = run(r, now, 10)
		t.eq(picksBy(r, a.id), 6, "the whole pile, one at a time")
		t.eq(r.forage:left(premium.id), 0)
		t.eq(r.hollows:carried(a.id), 6)
		t.eq(r.picks[#r.picks].held, 6)
		t.falsy(r.picks[1].ai)
		-- on to a tree spot: three more make nine, then its paws are full: told once, nothing more taken
		local tree = NutSpots.byId("tree_bur_oak_1") :: NutSpots.Spot
		local ty = Height.at(tree.x, tree.z)
		r.held[a.id] = { tree.x, ty, tree.z }
		now = run(r, now, 5)
		t.eq(r.hollows:carried(a.id), Tunables.get("forage.carryMax"))
		t.eq(r.forage:left(tree.id), 0)
		local other = NutSpots.byId("tree_bur_oak_2") :: NutSpots.Spot
		r.held[a.id] = { other.x, Height.at(other.x, other.z), other.z }
		now = run(r, now, 5)
		t.eq(r.hollows:carried(a.id), 9, "never past nine")
		t.eq(r.forage:left(other.id), 3, "a full squirrel takes nothing")
		t.eq(#r.fulls, 1, "told once while it stays")
		r.held[a.id] = { other.x + 20, Height.at(other.x + 20, other.z), other.z }
		now = run(r, now, 1)
		r.held[a.id] = { other.x, Height.at(other.x, other.z), other.z }
		run(r, now, 1)
		t.eq(#r.fulls, 2, "and again on coming back")
	end)

	t.test(
		"never by the root (invariant D): root at the pile and the held place away, or none held, picks nothing",
		function()
			local r = rig()
			local a = squirrel(r)
			possess(r, a)
			local s = NutSpots.byId("park_cache_1") :: NutSpots.Spot
			local gy = Height.at(s.x, s.z)
			a.x, a.y, a.z = s.x, gy + a.hip, s.z -- the root right on it
			r.held[a.id] = { s.x + 40, Height.at(s.x + 40, s.z), s.z }
			local now = run(r, 0, 5)
			t.eq(picksBy(r, a.id), 0, "the held place is 40 studs off")
			r.held[a.id] = nil -- no clean packet (pinned, or the last one flagged)
			now = run(r, now, 5)
			t.eq(picksBy(r, a.id), 0, "nowhere the server trusts")
			r.held[a.id] = { s.x, gy + 3, s.z } -- on a fence over the pile
			now = run(r, now, 5)
			t.eq(picksBy(r, a.id), 0, "over the pile, not at it")
			r.held[a.id] = { s.x + 1, gy, s.z }
			run(r, now, 5)
			t.eq(picksBy(r, a.id), NutSpots.stockOf(s), "there by the held place: it picks them up")
			t.eq(r.forage:spotAt(s.x + 1, gy, s.z), s)
		end
	)

	t.test("the Spicy Rodent picks nothing up", function()
		local r = rig()
		local rodent = squirrel(r, "spicy")
		possess(r, rodent)
		local s = NutSpots.byId("tree_bur_oak_3") :: NutSpots.Spot
		r.held[rodent.id] = { s.x, Height.at(s.x, s.z), s.z }
		rodent.x, rodent.y, rodent.z = s.x, Height.at(s.x, s.z) + rodent.hip, s.z
		run(r, 0, 10)
		t.eq(#r.picks, 0)
		t.eq(r.forage:left(s.id), 3)
		t.eq(r.hollows:carried(rodent.id), 0)
	end)

	t.test("the nuts grow back on the game clock: a nut every third of a day under the oaks, then full", function()
		local r = rig()
		local a = squirrel(r)
		possess(r, a)
		local s = NutSpots.byId("tree_westside_2_shade_oak_1") :: NutSpots.Spot
		r.held[a.id] = { s.x, Height.at(s.x, s.z), s.z }
		local now = run(r, 0, 3)
		t.eq(r.forage:left(s.id), 0)
		r.held[a.id] = nil
		r.day.v += 0.3
		now = run(r, now, 1.1)
		t.eq(r.forage:left(s.id), 0, "not yet")
		r.day.v += 0.05
		now = run(r, now, 1.1)
		t.eq(r.forage:left(s.id), 1, "a third of a day")
		r.day.v += 5
		run(r, now, 1.1)
		t.eq(r.forage:left(s.id), 3, "full, and no more")
	end)

	t.test("into a hollow by the held place: the root inside and the held place out stores nothing", function()
		local r = rig()
		local a = squirrel(r)
		possess(r, a)
		local h = layout.hollow("H3") :: HollowLayout.Hollow
		local c = h.chambers[1]
		t.eq(r.hollows:carry(a.id, 9), 9)
		-- the root in the chamber (its client says), the held place out on the lawn
		a.x, a.y, a.z = c.x, c.y + a.hip, c.z
		TownAI.stepFrame(r.world, DT)
		r.held[a.id] = { h.x + 30, Height.at(h.x + 30, h.z), h.z }
		r.hollows:step(20)
		t.eq(r.hollows:carried(a.id), 9, "nothing stored by the root")
		t.eq(r.hollows:meter("H3"), 0)
		-- the held place in the chamber: stored
		r.held[a.id] = { c.x, c.y, c.z }
		a.x, a.y, a.z = h.x + 30, Height.at(h.x + 30, h.z) + a.hip, h.z
		TownAI.stepFrame(r.world, DT)
		r.hollows:step(20.01)
		t.eq(r.hollows:carried(a.id), 0, "all nine stored")
		t.near(r.hollows:meter("H3"), 9 / h.meter.capacity, 1e-3) -- (less a hundredth of a day's decay)
		r.hollows:stop()
	end)

	t.test("the computer's squirrels: one at a spot eats a nut and sits nibbling; it carries none", function()
		local r = rig()
		local a = squirrel(r)
		local s = NutSpots.byId("yard_garden_1") :: NutSpots.Spot
		local gy = Height.at(s.x, s.z)
		a.x, a.y, a.z = s.x + 1, gy + a.hip, s.z
		-- (its brain, listened to: the real one goes to its route's nearest point, and this one's route is elsewhere)
		local told: { { [string]: any } } = {}
		r.world.brains[a.id] = {
			onEvent = function(_self: any, ev: { [string]: any })
				table.insert(told, ev)
			end,
		} :: any
		r.forage:step(C.aiEvery, 10)
		t.eq(#r.picks, 1)
		t.eq(r.picks[1].id, a.id)
		t.truthy(r.picks[1].ai)
		t.eq(r.forage:left(s.id), NutSpots.stockOf(s) - 1)
		t.eq(r.hollows:carried(a.id), 0, "eaten, not carried: it never fills a hollow")
		t.eq(told[1] and told[1].type, "bait", "it sits nibbling (its brain's bait)")
		t.eq(told[1].x, s.x)
		t.near(told[1].untilTime - r.world.now, C.aiNibble, 1e-6)
		-- one further off but within notice may be sent along its route to the pile
		local b: any = nil
		for _, o in r.world.actors do
			if o.species == "squirrel" and o.variant == "normal" and o ~= a then
				b = o
			end
		end
		local s2 = NutSpots.byId("yard_garden_2") :: NutSpots.Spot
		b.x, b.y, b.z = s2.x + 10, Height.at(s2.x, s2.z) + 6 + b.hip, s2.z
		r.forage:step(C.aiEvery, 20)
		t.eq(r.forage:left(s2.id), NutSpots.stockOf(s2), "too far up to eat")
	end)

	t.test("the cost: a look at every squirrel and spot is a fraction of a millisecond", function()
		local r = rig(14)
		local a = squirrel(r)
		possess(r, a)
		r.held[a.id] = { 0, 0, 0 }
		local now = 0
		local worst = 0
		for _ = 1, 200 do
			local t0 = os.clock()
			r.forage:step(C.aiEvery, now)
			worst = math.max(worst, os.clock() - t0)
			now += C.aiEvery
		end
		print(
			string.format(
				"      the worst look (players, the computer's squirrels, the regrowth): %.3f ms",
				worst * 1000
			)
		)
		t.truthy(worst < 0.002, `{worst * 1000} ms`)
	end)
end
