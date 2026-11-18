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
--   a kick (PlayRules.kickTarget) or a bite (biteVictims) does not reach through the bark of any hollow or the log
--   (each is a Combat/Cover shape while the service runs), at the hole in the open it does
local Data = require("@shared/Data")
local HollowClaim = require("@shared/Foraging/HollowClaim")
local HollowLayout = require("@shared/World/HollowLayout")
local Tunables = require("@shared/Config/Tunables")
local Common = require("@server/Actors/Brains/Common")
local TownAI = require("@server/AI/TownAI")
local HollowService = require("@server/Foraging/HollowService")
local Cover = require("@shared/Combat/Cover")
local PlayRules = require("@shared/Combat/PlayRules")

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
	t.test("no kick or bite through the bark: every chamber and the log, from the hole and the far side", function()
		local before = #Cover.list()
		local _, svc = rig()
		t.eq(#Cover.list(), before + #layout.hollows, "a cover shape per hollow while the service runs")
		local HUMAN, SQ = 2.6, 0.5 -- a person's root over the ground, a squirrel's over its line
		local checked = 0
		local function refused(who: PlayRules.Point, look: { x: number, z: number }, sq: PlayRules.Point, what: string)
			t.eq(PlayRules.kickTarget(who, look, { sq }), nil, `kicked {what}`)
			local bitten = PlayRules.biteVictims(sq, { who }, 100, {})
			-- (the bite's reach is 3.5 studs: only a person that close is tested)
			if (who.x - sq.x) ^ 2 + (who.z - sq.z) ^ 2 <= PlayRules.BITE_RANGE ^ 2 then
				t.eq(#bitten, 0, `bitten {what}`)
			end
			checked += 1
		end
		for _, h in layout.hollows do
			local hole: HollowLayout.Mouth? = nil
			for _, m in h.mouths do
				if m.opens == "ground" then
					hole = m
				end
			end
			assert(hole, h.id)
			local ol = math.sqrt(hole.out[1] ^ 2 + hole.out[3] ^ 2)
			local ox, oz = hole.out[1] / ol, hole.out[3] / ol
			local spots: { { number } } = {}
			for _, c in h.chambers do
				table.insert(spots, { c.x, c.y + SQ, c.z })
			end
			if h.variant == "log" then
				table.insert(spots, { h.x, h.y + 0.1 + SQ, h.z })
			end
			for _, at in spots do
				local sq = { id = "sq", x = at[1], y = at[2], z = at[3] }
				t.truthy(layout.within(h, sq.x, sq.y, sq.z), `{h.id}: the chamber is in its cavity`)
				-- from the hole, one stud out of its mouth point, facing in
				local px, pz = hole.x + ox, hole.z + oz
				refused(
					{ id = "me", x = px, y = hole.y + HUMAN, z = pz },
					{ x = -ox, z = -oz },
					sq,
					`{h.id} from the hole`
				)
				-- against the bark, facing it, from four sides at the squirrel's height (the log: its two long sides)
				local trunk = if h.trunk then data:routes():get(h.trunk) else nil
				local r = if trunk then trunk.surfaceRadius + 1 else 3
				local la, lb = h.cavities[1].a, h.cavities[1].b
				local base = if la and lb then math.atan2(lb[1] - la[1], lb[3] - la[3]) + math.pi / 2 else 0
				for k = 0, if trunk then 3 else 1 do
					local ang = base + k * (if trunk then math.pi / 2 else math.pi)
					local dx, dz = math.sin(ang), math.cos(ang)
					local cx, cz = if trunk then h.x else sq.x, if trunk then h.z else sq.z
					local who = { id = "me", x = cx + dx * r, y = math.max(h.y, sq.y - 1) + HUMAN, z = cz + dz * r }
					refused(who, { x = -dx, z = -dz }, sq, `{h.id} from the side {k}`)
				end
				-- a body inside with it reaches it (the cover is the bark, nothing inside; under a stud is always in front)
				-- (half a stud from it towards the middle of the cavity)
				local mx, mz = h.x - sq.x, h.z - sq.z
				local ml = math.max(1e-6, math.sqrt(mx * mx + mz * mz))
				local s = math.min(0.5, ml)
				local near = { id = "me", x = sq.x + mx / ml * s, y = sq.y, z = sq.z + mz / ml * s }
				t.truthy(layout.within(h, near.x, near.y, near.z), `{h.id}: beside it, inside`)
				t.truthy(PlayRules.kickTarget(near, { x = 1, z = 0 }, { sq }) ~= nil, `{h.id}: inside with it`)
			end
			-- a stud out of the hole, in the open, a kick lands (the log's mouth points are its open ends)
			local sq = { id = "sq", x = hole.x + ox, y = hole.y + SQ, z = hole.z + oz }
			local hit = PlayRules.kickTarget(
				{ id = "me", x = hole.x + ox * 3, y = hole.y + HUMAN, z = hole.z + oz * 3 },
				{ x = -ox, z = -oz },
				{ sq }
			)
			t.eq(hit, "sq", `{h.id}: a squirrel at the hole in the open is kicked`)
		end
		t.truthy(checked >= 5 * #layout.hollows, `{checked} positions`)
		svc:stop()
		t.eq(#Cover.list(), before, "stopped: the shapes are gone")
	end)
end
