--!strict
-- THE GILDED ACORN's rules (Shared/Attractions/LoungeClassic): the room and the guarded ground agree with the bake
-- (tools/bake/lounge_classic/Style) and the plan (data/expansion.json), the door's decisions, the drinks' prices,
-- and the jazz playlist (cue names, empty ids, nothing plays until the lead fills one).
local LoungeClassic = require("@shared/Attractions/LoungeClassic")
local EconomyRules = require("@shared/Economy/EconomyRules")
local Expansion = require("../../generated/Expansion")
local Style = require("../../tools/bake/lounge_classic/Style")
local Staff = require("../../tools/bake/lounge_classic/Staff")
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local StaffRounds = require("@shared/Actors/StaffRounds")
local Data = require("@shared/Data")
local TownAI = require("@server/AI/TownAI")

local function venue(): any
	for _, v in (Expansion :: any).venues do
		if v.id == LoungeClassic.VENUE then
			return v
		end
	end
	error("no venue")
end

local function anchor(id: string): { number }
	for _, a in venue().anchors do
		if a.id == id then
			return a.at
		end
	end
	error("no anchor " .. id)
end

return function(t)
	t.test("the room is the bake's: inside the walls, out past the door wall, the entry is not inside", function()
		local I = LoungeClassic.INSIDE
		t.eq(I.x, Style.INNER_X)
		t.eq(I.d0, Style.FRONT_D + Style.WALL)
		t.eq(I.d1, Style.INNER_BACK)
		t.eq(I.doorD, Style.DOOR_D + Style.WALL)
		t.eq(I.doorX, Style.ALCOVE_X + Style.WALL)
		t.eq(I.y1, Style.CEILING)
		t.truthy(LoungeClassic.inside(0, 0, 0))
		t.truthy(LoungeClassic.inside(20, 2, -26)) -- a front corner, beside the entry
		t.truthy(not LoungeClassic.inside(0, 0, -23)) -- the landing
		t.truthy(not LoungeClassic.inside(0, 0, -30)) -- the forecourt
		t.truthy(not LoungeClassic.inside(0, 15, 0)) -- the roof
		t.truthy(not LoungeClassic.inside(25, 0, 0)) -- outside the east wall
		local o, i = LoungeClassic.DOOR_OUTSIDE, LoungeClassic.DOOR_INSIDE
		t.truthy(LoungeClassic.inside(i.x, 0, i.d))
		t.truthy(not LoungeClassic.inside(o.x, 0, o.d))
		t.truthy(o.d > Style.LANDING_D and o.d < Style.DOOR_D, "outside: on the landing")
	end)

	t.test("the guarded ground: the forecourt and the entry to the door, where the plan's guards stand", function()
		for k, p in LoungeClassic.GUARD_POSTS do
			local a = anchor(`guard_{k}`)
			t.eq(p.x, a[1])
			t.eq(p.d, a[3])
			t.eq(Staff.FIGURES[k].x, a[1])
			t.eq(Staff.FIGURES[k].d, a[3])
		end
		local G = LoungeClassic.GUARDED
		t.truthy(G.d0 == Style.FORECOURT_D and G.d1 == Style.DOOR_D + Style.WALL)
		t.truthy(G.x >= Style.FORECOURT_X)
		t.truthy(LoungeClassic.guarded(0, -2.4, -30)) -- the forecourt
		t.truthy(LoungeClassic.guarded(0, 0, LoungeClassic.DOOR_OUTSIDE.d)) -- the landing
		t.truthy(LoungeClassic.guarded(-4, -1.2, -26)) -- the steps
		t.truthy(not LoungeClassic.guarded(0, 0, 0)) -- the room (the inside check covers it)
		t.truthy(not LoungeClassic.guarded(0, -5, -40)) -- Bowl Lane, beyond the planned sidewalk
		t.truthy(LoungeClassic.guarded(0, -2.4, Style.FORECOURT_D)) -- the forecourt's street edge
		for _, gx in { 0, -10.9, 10.9 } do
			for sd = -32.5, -38, -0.5 do -- Bowl Lane's planned sidewalk (world z -330..-324): nobody is struck there
				for _, gy in { -2.4, -3 } do
					t.truthy(not LoungeClassic.guarded(gx, gy, sd), `the sidewalk at X {gx} D {sd}`)
				end
			end
		end
		t.truthy(not LoungeClassic.guarded(20, 0, -30)) -- along the front, away from the entry
		local pc = anchor("pass_check")
		t.truthy(LoungeClassic.guarded(pc[1], pc[2], pc[3]), "the pass check stands in the guarded entry")
		local bt = anchor("bartender")
		t.eq(Style.BARTENDER[1], bt[1])
		t.eq(Style.BARTENDER[2], bt[3])
	end)

	t.test("the bartender is the lounge's own: the town staffs no counter here and puts nobody in the room", function()
		local v = venue()
		local posts: { [string]: boolean } = {}
		for _, sv in StaffRounds.venues(Expansion) do
			posts[sv.id] = sv.post ~= nil
		end
		t.eq(posts[LoungeClassic.VENUE], false) -- (the bake's Staff.Bartender stands there)
		t.eq(posts.f1_corner_store, true) -- the corner store keeps its shop worker
		local world = TownAI.build({ data = Data.default(), seed = 3 })
		for frame = 0, 30 * 10 do
			if frame > 0 then
				TownAI.stepFrame(world, 1 / 30)
			end
			if frame % 30 == 0 then
				for _, a in world.actors do
					local x, _, d = AlleyLayout.toLocal(v.place, a.x, a.y, a.z)
					local inBuilding = math.abs(x) < v.footprint.w / 2 and math.abs(d) < v.footprint.d / 2
					t.truthy(not inBuilding, `{a.post} {a.id} in the lounge at {x}, {d}`)
				end
			end
		end
	end)

	t.test(
		"the door: the pass lets a person in, offers it otherwise, the guards take squirrels, animals are turned away",
		function()
			t.eq(LoungeClassic.door("human", true), "enter")
			t.eq(LoungeClassic.door("human", false), "offer")
			t.eq(LoungeClassic.door("squirrel", true), "guard")
			t.eq(LoungeClassic.door("rodent", false), "guard")
			t.eq(LoungeClassic.door("fox", true), "refuse")
			t.eq(LoungeClassic.door("deer", false), "refuse")
			t.eq(LoungeClassic.door(nil, true), "refuse")
			-- the one pass: the wallet's paintball pass, which says it opens both lounges
			local spec: any = EconomyRules.pass(EconomyRules.PASS)
			t.truthy(spec ~= nil)
			t.truthy(string.find(spec.offer, "both lounges", 1, true) ~= nil, spec.offer)
			t.eq(spec.cents, 20)
			t.eq(spec.days, 5)
		end
	)

	t.test("the bar sells the brief's four at the wallet's prices: hot cocoa, coffee, green tea, snow cones", function()
		local ids = {}
		for _, d in LoungeClassic.DRINKS do
			table.insert(ids, d.id)
			local item = EconomyRules.item(d.id)
			t.truthy(item ~= nil, d.id)
			t.truthy((item :: any).cents > 0 and (item :: any).cents <= 12, `{d.id}: {(item :: any).cents}c`)
			t.eq(LoungeClassic.drink(d.id), d)
		end
		t.eq(table.concat(ids, ","), "hot_cocoa,coffee,green_tea,snow_cone")
		t.eq(LoungeClassic.drink("whisky"), nil)
		t.truthy(LoungeClassic.SIPS * LoungeClassic.SIP_EVERY <= 30)
	end)

	t.test("the jazz: four cue names with empty ids (never uploaded); a filled id is the next track", function()
		t.eq(#LoungeClassic.JAZZ, 4)
		for i, j in LoungeClassic.JAZZ do
			t.eq(j.cue, `Lounge.Jazz{i}`)
			t.eq(j.id, "")
		end
		t.eq(LoungeClassic.nextTrack(LoungeClassic.JAZZ, 0), nil)
		local list =
			{ { cue = "a", id = "" }, { cue = "b", id = "rbxassetid://1" }, { cue = "c", id = "rbxassetid://2" } }
		t.eq(LoungeClassic.nextTrack(list, 0), 2)
		t.eq(LoungeClassic.nextTrack(list, 2), 3)
		t.eq(LoungeClassic.nextTrack(list, 3), 2)
	end)
end
