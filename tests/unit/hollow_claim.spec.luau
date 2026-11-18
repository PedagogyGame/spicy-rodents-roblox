--!strict
-- A hollow tree's nut meter, its claim and its cover (brief v2 §3 "Claiming is proximity, not a ritual ... owns a
-- tree while its meter is at 70% or above and it has visited the tree at least once every three in-game days";
-- §7 "other squirrels cannot take its nuts"; at most 9 nuts carried; §8 hollows are rodent refuges):
-- Shared/Foraging/HollowClaim (the pure rules) and Server/Foraging/HollowService on the real town AI headless:
--   at most forage.carryMax nuts carried; nuts brought into a hollow raise its meter (never past capacity); the
--   squirrel that lifts it to 70 % owns it; the owner keeps it by visiting, loses it after three days away or when
--   the meter decays under 70 %; nobody takes nuts from another's claimed tree
--   inside a hollow a squirrel is out of the threat grid and people around the tree never spot it; at the hole,
--   in the open, they do; a body let go inside comes back at the hole facing out; no bites from inside; the fed
--   rodent heals inside at the hollow rate; the log hides but is never claimed; the Spicy Rodent claims nothing
local Data = require("@shared/Data")
local HollowClaim = require("@shared/Foraging/HollowClaim")
local HollowLayout = require("@shared/World/HollowLayout")
local Tunables = require("@shared/Config/Tunables")
local Common = require("@server/Actors/Brains/Common")
local TownAI = require("@server/AI/TownAI")
local HollowService = require("@server/Foraging/HollowService")

local DT = 1 / 60

return function(t)
	local data = Data.default()
	local layout = HollowLayout.default() :: HollowLayout.Layout
	local OWN = Tunables.get("forage.ownThreshold")

	t.test("the rules: carry cap, deposit to capacity, the claim at 70 %, theft refused, lapse by absence", function()
		local max = Tunables.get("forage.carryMax")
		t.eq(max, 9)
		local held, took = HollowClaim.carry(7, 5, max)
		t.eq(held, 9)
		t.eq(took, 2)
		local c = HollowClaim.new()
		t.eq(HollowClaim.deposit(c, 1, 9, 0, 30, OWN), 9)
		t.eq(c.owner, nil, "30 % is no claim")
		t.eq(HollowClaim.deposit(c, 2, 9, 0.1, 30, OWN), 9)
		t.eq(c.owner, nil, "60 %")
		t.eq(HollowClaim.deposit(c, 2, 9, 0.2, 30, OWN), 9)
		t.eq(c.owner, 2, "the squirrel that lifts it to 70 % owns it")
		t.eq(HollowClaim.deposit(c, 1, 9, 0.3, 30, OWN), 3, "full at capacity: the rest stays carried")
		t.eq(c.owner, 2, "filling it does not take it over")
		t.eq(HollowClaim.withdraw(c, 1, 5), 0, "nobody takes from another's claimed tree")
		t.eq(HollowClaim.withdraw(c, 2, 2), 2, "the owner may")
		-- visits keep it; three days away lose it
		HollowClaim.update(c, 0.3, 30, OWN, 3, 0)
		for day = 1, 9 do
			HollowClaim.visit(c, 2, day)
			t.eq(HollowClaim.update(c, day, 30, OWN, 3, 0), false, `day {day}`)
		end
		t.eq(c.owner, 2)
		t.eq(HollowClaim.update(c, 12.5, 30, OWN, 3, 0), true, "3.5 days away")
		t.eq(c.owner, nil)
		t.eq(HollowClaim.withdraw(c, 1, 5), 5, "an unclaimed tree can be raided")
		-- decay: the meter falls by decayPerDay of capacity each day and the claim goes under 70 %
		local d = HollowClaim.new()
		HollowClaim.deposit(d, 4, 30, 0, 30, OWN)
		t.eq(d.owner, 4)
		HollowClaim.update(d, 0, 30, OWN, 3, 0.1)
		HollowClaim.visit(d, 4, 2)
		t.eq(HollowClaim.update(d, 2, 30, OWN, 3, 0.1), false)
		t.near(HollowClaim.meter(d, 30), 0.8, 1e-9)
		HollowClaim.visit(d, 4, 3.5)
		t.eq(HollowClaim.update(d, 3.5, 30, OWN, 3, 0.1), true, "65 %: lapsed")
		t.near(HollowClaim.meter(d, 30), 0.65, 1e-9)
	end)

	local rail: any = nil
	local function rig(): (TownAI.World, HollowService.Service, { [string]: { [string]: any } })
		local world = TownAI.build({
			data = data,
			seed = 1,
			humans = 90,
			squirrels = 3,
			deer = 0,
			fox = 0,
			rail = rail,
		})
		rail = world.rail
		-- the town's brains run in full round the core's hollows (H3, the BUR OAK; H12; H2)
		TownAI.setFocus(world, function()
			return { { x = -85, z = -82.5 } }
		end)
		local shown: { [string]: { [string]: any } } = {}
		local svc = HollowService.new({
			world = world,
			layout = layout,
			show = function(id: string, attrs: { [string]: any })
				shown[id] = attrs
			end,
			nameOf = function(id: number): string?
				return if id == 1 then "Pip" else nil
			end,
		})
		return world, svc, shown
	end
	local function squirrels(world: TownAI.World): { any }
		local out = {}
		for _, a in world.actors do
			if a.species == "squirrel" and a.variant ~= "spicy" then
				table.insert(out, a)
			end
		end
		return out
	end
	local function hold(world: TownAI.World, a: any, x: number, y: number, z: number)
		if not world.possessed[a.id] then
			TownAI.suspend(world, a.id)
		end
		a.x, a.y, a.z = x, y, z
		a.speed = 0
	end
	local function chamberOf(id: string): HollowLayout.Chamber
		return ((layout.hollow(id) :: HollowLayout.Hollow).chambers)[1]
	end

	t.test("the service: nuts brought in raise the meter, the claim is shown on the tree, and lapses", function()
		local world, svc, shown = rig()
		local a = squirrels(world)[1]
		local h = layout.hollow("H3") :: HollowLayout.Hollow
		local cap = h.meter.capacity
		local c = chamberOf("H3")
		local day = 10
		local trips = 0
		while svc:owner("H3") == nil and trips < 40 do
			-- out to forage, nine nuts, back in
			hold(world, a, h.x + 30, h.y + 1, h.z)
			TownAI.stepFrame(world, DT)
			t.eq(svc:carry(a.id, 12), 9, "never more than nine")
			hold(world, a, c.x, c.y + 0.8, c.z)
			TownAI.stepFrame(world, DT)
			t.eq(svc:inside(a.id), "H3")
			svc:step(day)
			t.eq(svc:carried(a.id), 0, "all nine stored")
			trips += 1
			day += 0.05
		end
		t.eq(trips, math.ceil(cap * OWN / 9), "the trip that lifts it to 70 % claims it")
		t.eq(svc:owner("H3"), a.id)
		t.truthy(svc:meter("H3") >= OWN)
		t.eq(shown.H3.Claimed, true)
		t.eq(shown.H3.Owner, a.id)
		-- away for more than three game days: the claim lapses and the tree says so
		hold(world, a, h.x + 30, h.y + 1, h.z)
		TownAI.stepFrame(world, DT)
		svc:step(day + 3.2)
		t.eq(svc:owner("H3"), nil)
		t.eq(shown.H3.Claimed, false)
		-- the log hides but is never claimed; the rodent claims nothing
		local log = layout.hollow("LOG") :: HollowLayout.Hollow
		hold(world, a, log.x, log.y + 0.9, log.z)
		TownAI.stepFrame(world, DT)
		t.eq(svc:inside(a.id), "LOG")
		svc:carry(a.id, 9)
		svc:step(day + 4)
		t.eq(svc:carried(a.id), 9, "nothing stored in the log")
		t.eq(svc:meter("LOG"), 0)
		local rodent: any = nil
		for _, r in world.actors do
			if r.variant == "spicy" then
				rodent = r
			end
		end
		hold(world, rodent, c.x, c.y + 0.8, c.z)
		TownAI.stepFrame(world, DT)
		svc:carry(rodent.id, 9)
		svc:step(day + 4.1)
		t.eq(svc:carried(rodent.id), 9, "the rodent stores nothing")
		svc:stop()
	end)

	t.test("cover: inside nobody spots it, at the hole they do; let go inside, back at the hole; rest", function()
		local h = layout.hollow("H3") :: HollowLayout.Hollow
		local c = chamberOf("H3")
		local hole = h.mouths[1]
		-- a fresh town, ten walkers put round the tree 6 studs out facing it, the Spicy Rodent (the squirrel people
		-- take fright at: Brains/Pedestrian emits "spotted" as they flee) held at (x, y, z) for `frames`: the spots
		local function scene(x: number, y: number, z: number, frames: number): (number, TownAI.World, any, any)
			local world, svc = rig()
			local a: any = nil
			for _, r in world.actors do
				if r.variant == "spicy" then
					a = r
				end
			end
			local n = 0
			for _, p in world.actors do
				local b = world.brains[p.id]
				if p.species == "human" and p.post ~= "rider" and b and b.kind == "Pedestrian" and n < 10 then
					local ang = n * math.pi / 5
					local px, pz = h.x + 6 * math.sin(ang), h.z + 6 * math.cos(ang)
					TownAI.suspend(world, p.id)
					TownAI.resume(
						world,
						p.id,
						px,
						world.ctx.groundAt(px, pz) + p.hip,
						pz,
						Common.yawOf(h.x - px, h.z - pz)
					)
					n += 1
				end
			end
			local spotted = 0
			TownAI.listen(world, function(ev: TownAI.Event)
				if ev.kind == "spotted" and ev.other == a.id then
					spotted += 1
				end
			end)
			for _ = 1, frames do
				hold(world, a, x, y, z)
				TownAI.stepFrame(world, DT)
			end
			return spotted, world, svc, a
		end
		local inside, world, svc, a = scene(c.x, c.y + 0.8, c.z, 60 * 5)
		t.eq(svc:inside(a.id), "H3")
		t.eq(inside, 0, "nobody sees the rodent inside (5 s, ten people round the tree)")
		t.eq(svc:mayBite(a.id), false)
		local function inGrid(w: TownAI.World, id: number, x: number, z: number): boolean
			local out = {}
			local n = (w.grid :: any):query(x, z, 4, out)
			for i = 1, n do
				if out[i] == id then
					return true
				end
			end
			return false
		end
		t.eq(inGrid(world, a.id, c.x, c.z), false, "inside: out of the threat grid people see and hear by")
		local _, w2, svc2, a2 = scene(hole.x, hole.y + 0.6, hole.z, 30)
		t.eq(svc2:inside(a2.id), nil)
		t.eq(inGrid(w2, a2.id, hole.x, hole.z), true, "at the hole, in the open: in the threat grid")
		svc2:stop()
		-- let go inside: the AI takes it at the hole, facing out
		hold(world, a, c.x, c.y + 0.8, c.z)
		TownAI.resume(world, a.id, c.x, c.y + 0.8, c.z, 0)
		t.near(a.x, hole.x, 1e-6)
		t.near(a.z, hole.z, 1e-6)
		-- the fed rodent rests inside at the hollow rate, not outside, not when hungry
		local rodent = a
		hold(world, rodent, c.x, c.y + 0.8, c.z)
		TownAI.stepFrame(world, DT)
		local rate = Tunables.get("rodent.regenHollow")
		t.near(svc:heal(rodent.id, 50, 100, 10, true), 50 + 10 * rate, 1e-9)
		t.eq(svc:heal(rodent.id, 50, 100, 10, false), 50)
		hold(world, rodent, hole.x + 5, hole.y + 0.8, hole.z)
		TownAI.stepFrame(world, DT)
		t.eq(svc:heal(rodent.id, 50, 100, 10, true), 50)
		svc:stop()
	end)
end
