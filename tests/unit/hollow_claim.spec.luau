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
--   the computer's squirrel on a hollow tree's trunk route (its point the axis, inside the cavity test) is not hidden;
--   on the hollow's own runs it is
--   a kick (PlayRules.kickTarget) or a bite (biteVictims) does not reach through the bark of any hollow or the log
--   (each is a Combat/Cover shape while the service runs), at the hole in the open it does
--   one tree each (owner, D16 #21): a squirrel holding a tree brings no nuts into another (refused, with the words
--   once a visit), so it never holds two; once its claim lapses (it is told) it claims anew; a player inside someone
--   else's tree is told whose it is; the computer's squirrels keep the same rule; every tree has a player's name
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
		local M = 0.1 -- forage.keepMargin
		t.eq(max, 9)
		t.eq(Tunables.get("forage.keepMargin"), M)
		local held, took = HollowClaim.carry(7, 5, max)
		t.eq(held, 9)
		t.eq(took, 2)
		local c = HollowClaim.new()
		t.eq(HollowClaim.deposit(c, 1, 9, 0, 30, OWN, M), 9)
		t.eq(c.owner, nil, "30 % is no claim")
		t.eq(HollowClaim.deposit(c, 2, 9, 0.1, 30, OWN, M), 9)
		t.eq(c.owner, nil, "60 %")
		t.eq(HollowClaim.deposit(c, 2, 9, 0.2, 30, OWN, M), 9)
		t.eq(c.owner, 2, "the squirrel that lifts it to 70 % owns it")
		t.eq(HollowClaim.deposit(c, 1, 9, 0.3, 30, OWN, M), 0, "nobody brings nuts into another's claimed tree")
		t.eq(HollowClaim.deposit(c, 2, 9, 0.3, 30, OWN, M), 3, "full at capacity: the rest stays carried")
		t.eq(c.owner, 2)
		t.eq(HollowClaim.withdraw(c, 1, 5), 0, "nobody takes from another's claimed tree")
		t.eq(HollowClaim.withdraw(c, 2, 2), 2, "the owner may")
		-- visits keep it; three days away lose it
		HollowClaim.update(c, 0.3, 30, OWN, 3, 0, M)
		for day = 1, 9 do
			HollowClaim.visit(c, 2, day)
			t.eq(HollowClaim.update(c, day, 30, OWN, 3, 0, M), false, `day {day}`)
		end
		t.eq(c.owner, 2)
		t.eq(HollowClaim.update(c, 12.5, 30, OWN, 3, 0, M), true, "3.5 days away")
		t.eq(c.owner, nil)
		-- a lapsed tree's store is not taken with one nut: the newcomer brings margin x capacity itself
		t.truthy(HollowClaim.meter(c, 30) >= OWN)
		t.eq(HollowClaim.withdraw(c, 1, 2), 2, "an unclaimed tree can be raided")
		t.eq(HollowClaim.deposit(c, 3, 1, 13, 30, OWN, M), 1)
		t.eq(c.owner, nil, "one nut takes nothing")
		t.eq(HollowClaim.deposit(c, 3, 1, 13, 30, OWN, M), 1)
		t.eq(c.owner, nil, "two")
		t.eq(HollowClaim.deposit(c, 3, 1, 13, 30, OWN, M), 1)
		t.eq(c.owner, 3, "three (10 % of 30) of its own: it owns it")
		-- decay: the meter falls by decayPerDay of capacity each day; the owner keeps the tree down to 70 % less the
		-- margin (a claim just made does not lapse with the first day's decay), and loses it under that
		local d = HollowClaim.new()
		HollowClaim.deposit(d, 4, 23, 0, 30, OWN, M)
		t.eq(d.owner, 4, "claimed at 77 %")
		HollowClaim.update(d, 0, 30, OWN, 3, 0.03, M)
		for day = 1, 5 do
			HollowClaim.visit(d, 4, day)
			t.eq(HollowClaim.update(d, day, 30, OWN, 3, 0.03, M), false, `visited, day {day}`)
		end
		t.near(HollowClaim.meter(d, 30), 0.7667 - 0.15, 1e-3)
		HollowClaim.visit(d, 4, 6)
		t.eq(HollowClaim.update(d, 6, 30, OWN, 3, 0.03, M), true, "58.7 %: under 70 less 10: lapsed")
	end)

	local rail: any = nil
	local function rig(
		keyOf: ((id: number) -> HollowClaim.Who)?,
		tell: ((key: HollowClaim.Who, text: string) -> ())?
	): (TownAI.World, HollowService.Service, { [string]: { [string]: any } })
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
			keyOf = keyOf,
			nameOf = function(key: HollowClaim.Who): string?
				return if key == 1 or key == "player 1" then "Pip" else nil
			end,
			tell = tell,
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
		t.eq(shown.H3.Owner, tostring(a.id))
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

	t.test(
		"claims: the player's, not the body's; nuts drop when the body changes hands; none into another's tree",
		function()
			-- who holds each body: a player's key while they drive it, the computer's otherwise
			local holder: { [number]: string } = {}
			local world, svc = rig(function(id: number): HollowClaim.Who
				return holder[id] or `body {id}`
			end)
			local sq = squirrels(world)
			local a, b = sq[1], sq[2]
			local h = layout.hollow("H3") :: HollowLayout.Hollow
			local c = chamberOf("H3")
			holder[a.id] = "player 7"
			local day = 20
			while svc:owner("H3") == nil and day < 22 do
				hold(world, a, h.x + 30, h.y + 1, h.z)
				TownAI.stepFrame(world, DT)
				svc:carry(a.id, 9)
				hold(world, a, c.x, c.y + 0.8, c.z)
				TownAI.stepFrame(world, DT)
				svc:step(day)
				day += 0.05
			end
			t.eq(svc:owner("H3"), "player 7", "the player owns it")
			-- another squirrel inside the claimed tree keeps what it carries
			hold(world, b, c.x, c.y + 0.8, c.z)
			TownAI.stepFrame(world, DT)
			svc:step(day)
			local before = svc:meter("H3")
			t.eq(svc:carry(b.id, 9), 9)
			svc:step(day)
			t.eq(svc:carried(b.id), 9, "nothing brought into another's claimed tree")
			t.eq(svc:meter("H3"), before)
			-- the player lets the body go with nuts in its cheeks: the claim stays theirs, the nuts drop
			hold(world, a, h.x + 30, h.y + 1, h.z)
			TownAI.stepFrame(world, DT)
			t.eq(svc:carry(a.id, 9), 9)
			holder[a.id] = nil
			svc:step(day + 0.01)
			t.eq(svc:carried(a.id), 0, "changed hands: the nuts are gone")
			t.eq(svc:owner("H3"), "player 7", "the claim is still the player's")
			-- the computer's body inside the player's tree visits nothing for them; three days on the claim lapses
			hold(world, a, c.x, c.y + 0.8, c.z)
			TownAI.stepFrame(world, DT)
			svc:step(day + 3.5)
			t.eq(svc:owner("H3"), nil, "the player stayed away: lapsed")
			-- a knock-out drops what a body carries
			svc:carry(b.id, 9)
			svc:drop(b.id)
			t.eq(svc:carried(b.id), 0)
			svc:stop()
		end
	)

	t.test("the computer's squirrel climbing a hollow tree's bark is not hidden; on the hollow's runs it is", function()
		local world = rig()
		local a = squirrels(world)[1]
		local reg = data:routes()
		for _, h in layout.hollows do
			if h.trunk == nil then
				continue
			end
			-- on the trunk route its point is the trunk's line, the axis, which runs up through the cavity
			a.intent.mode, a.intent.routeId = "rail", h.trunk
			local tr = reg:get(h.trunk) :: any
			local inCavity, hidden = 0, 0
			for k = 0, 200 do
				local p = reg:pointAt(tr, k / 200)
				if layout.contains(p.x, p.y, p.z) then
					inCavity += 1
				end
				if HollowService.under(layout, world, p.x, p.y, p.z, a) then
					hidden += 1
				end
			end
			t.eq(hidden, 0, `{h.id}: on the outside trunk ({inCavity} of its points in the cavity test)`)
			-- on the hollow's own runs, inside: hidden
			for _, c in h.chambers do
				a.intent.mode, a.intent.routeId = "rail", c.route
				t.eq(HollowService.under(layout, world, c.x, c.y + 0.5, c.z, a), h.space, `{h.id} {c.id}`)
			end
		end
		-- the log (no trunk): on its run, hidden; a player's body is judged where it is drawn
		local log = layout.hollow("LOG") :: HollowLayout.Hollow
		a.intent.mode, a.intent.routeId = "rail", log.routes[1]
		t.eq(HollowService.under(layout, world, log.x, log.y + 0.6, log.z, a), log.space)
		TownAI.suspend(world, a.id)
		local h2 = layout.hollow("H2") :: HollowLayout.Hollow
		local c2 = h2.chambers[1]
		a.intent.mode, a.intent.routeId = "rail", h2.trunk :: number
		t.eq(HollowService.under(layout, world, c2.x, c2.y + 0.5, c2.z, a), h2.space, "a player's body in the cavity")
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
	-- one tree each: fill `id` with `a`'s nuts until it is claimed (or `trips` runs out); the day after
	local function fill(
		world: TownAI.World,
		svc: HollowService.Service,
		a: any,
		id: string,
		day: number,
		trips: number?
	): number
		local h = layout.hollow(id) :: HollowLayout.Hollow
		local c = chamberOf(id)
		for _ = 1, trips or 40 do
			if svc:owner(id) ~= nil then
				break
			end
			hold(world, a, h.x + 30, h.y + 1, h.z)
			TownAI.stepFrame(world, DT)
			svc:step(day)
			svc:carry(a.id, 9)
			hold(world, a, c.x, c.y + 0.8, c.z)
			TownAI.stepFrame(world, DT)
			svc:step(day)
			day += 0.05
		end
		return day
	end

	t.test("the rule: a squirrel that holds a tree brings nothing into another and never claims it", function()
		local M = Tunables.get("forage.keepMargin")
		local claims = { A = HollowClaim.new(), B = HollowClaim.new() }
		t.eq(HollowClaim.heldBy(claims, 1), nil)
		HollowClaim.deposit(claims.A, 1, 23, 0, 30, OWN, M)
		t.eq(claims.A.owner, 1)
		t.eq(HollowClaim.heldBy(claims, 1), "A")
		-- B is unclaimed and nearly full of someone else's nuts: one trip would claim it, but 1 holds A
		HollowClaim.deposit(claims.B, 2, 18, 0, 30, OWN, M)
		t.eq(HollowClaim.deposit(claims.B, 1, 9, 0.1, 30, OWN, M, true), 0, "its nuts stay carried")
		t.eq(claims.B.owner, nil, "no second tree")
		t.eq(claims.B.stored, 18)
		t.eq(HollowClaim.deposit(claims.A, 1, 3, 0.1, 30, OWN, M, false), 3, "its own tree takes them")
		-- A lapses: B can be claimed now
		HollowClaim.update(claims.A, 0.1, 30, OWN, 3, 0, M)
		t.eq(HollowClaim.update(claims.A, 4, 30, OWN, 3, 0, M), true)
		t.eq(HollowClaim.heldBy(claims, 1), nil)
		t.eq(HollowClaim.deposit(claims.B, 1, 9, 4, 30, OWN, M, false), 9)
		t.eq(claims.B.owner, 1, "claimed anew once the first lapsed")
	end)

	t.test("one tree each: a player's second tree is refused with words, claimed once the first lapses", function()
		local holder: { [number]: string } = {}
		local told: { [string]: { string } } = {}
		local world, svc, shown = rig(function(id: number): HollowClaim.Who
			return holder[id] or `body {id}`
		end, function(key: HollowClaim.Who, text: string)
			local list = told[tostring(key)] or {}
			told[tostring(key)] = list
			table.insert(list, text)
		end)
		local a = squirrels(world)[1]
		holder[a.id] = "player 1"
		local day = fill(world, svc, a, "H3", 30)
		t.eq(svc:owner("H3"), "player 1")
		t.eq(svc:heldBy("player 1"), "H3")
		t.eq(
			told["player 1"][#told["player 1"]],
			"The Bur Oak is your tree now! Visit it at least every 3 game days to keep it."
		)
		-- into the American Elm (unclaimed) with nine nuts: they stay carried, the meter does not move, one notice
		local h12 = layout.hollow("H12") :: HollowLayout.Hollow
		local c12 = chamberOf("H12")
		hold(world, a, h12.x + 30, h12.y + 1, h12.z)
		TownAI.stepFrame(world, DT)
		svc:step(day)
		svc:carry(a.id, 9)
		local n = #told["player 1"]
		hold(world, a, c12.x, c12.y + 0.8, c12.z)
		TownAI.stepFrame(world, DT)
		t.eq(svc:inside(a.id), "H12")
		for k = 1, 5 do
			svc:step(day + k * 0.01)
		end
		t.eq(svc:carried(a.id), 9, "its nuts stay with it")
		t.eq(svc:meter("H12"), 0)
		t.eq(svc:owner("H12"), nil)
		t.eq(#told["player 1"], n + 1, "told once a visit, not once a second")
		t.eq(
			told["player 1"][n + 1],
			"You already have a tree: the Bur Oak. A squirrel keeps just one, so your nuts stay with you."
		)
		-- out and back in: told again
		hold(world, a, h12.x + 30, h12.y + 1, h12.z)
		TownAI.stepFrame(world, DT)
		svc:step(day + 0.1)
		hold(world, a, c12.x, c12.y + 0.8, c12.z)
		TownAI.stepFrame(world, DT)
		svc:step(day + 0.11)
		t.eq(#told["player 1"], n + 2)
		-- the Bur Oak is left three game days: it lapses (the player is told), and the elm is claimed instead
		svc:step(day + 3.5)
		t.eq(svc:owner("H3"), nil)
		t.eq(told["player 1"][#told["player 1"]], "The Bur Oak is not your tree any more. You can claim a new one.")
		t.eq(shown.H3.Claimed, false)
		day = fill(world, svc, a, "H12", day + 3.6)
		t.eq(svc:owner("H12"), "player 1")
		t.eq(svc:heldBy("player 1"), "H12")
		t.eq(
			told["player 1"][#told["player 1"]],
			"The American Elm is your tree now! Visit it at least every 3 game days to keep it."
		)
		-- never two at once, whatever was done above
		local count = 0
		for _, h in layout.hollows do
			if svc:owner(h.id) == "player 1" then
				count += 1
			end
		end
		t.eq(count, 1)
		svc:stop()
	end)

	t.test("someone else's tree says whose it is; the computer's squirrels keep one tree too", function()
		local told: { [string]: { string } } = {}
		local holder: { [number]: string } = {}
		local world, svc = rig(function(id: number): HollowClaim.Who
			return holder[id] or `body {id}`
		end, function(key: HollowClaim.Who, text: string)
			local list = told[tostring(key)] or {}
			told[tostring(key)] = list
			table.insert(list, text)
		end)
		local sq = squirrels(world)
		local a, b, c = sq[1], sq[2], sq[3]
		holder[a.id] = "player 1"
		local day = fill(world, svc, a, "H3", 40)
		t.eq(svc:owner("H3"), "player 1")
		-- the computer's squirrel b claims the American Elm, then cannot take the Sycamore as well
		day = fill(world, svc, b, "H12", day)
		local bKey = `body {b.id}`
		t.eq(svc:owner("H12"), bKey, "a computer squirrel claims a tree")
		day = fill(world, svc, b, "H2", day, 30)
		t.eq(svc:owner("H2"), nil, "but not a second")
		t.eq(svc:meter("H2"), 0)
		t.eq(svc:carried(b.id), 9, "its nuts stay carried")
		-- a third (a player too) carries nuts into the player's Bur Oak: it is told whose tree it is
		holder[c.id] = "player 2"
		local h3 = layout.hollow("H3") :: HollowLayout.Hollow
		local c3 = chamberOf("H3")
		hold(world, c, h3.x + 30, h3.y + 1, h3.z)
		TownAI.stepFrame(world, DT)
		svc:carry(c.id, 9)
		hold(world, c, c3.x, c3.y + 0.8, c3.z)
		TownAI.stepFrame(world, DT)
		svc:step(day)
		svc:step(day + 0.01)
		t.eq(svc:carried(c.id), 9)
		t.eq(#told["player 2"], 1, "once")
		t.eq(told["player 2"][1], "This tree belongs to Pip. Your nuts stay with you.")
		-- and a computer squirrel's owner is "another squirrel"
		local h12 = layout.hollow("H12") :: HollowLayout.Hollow
		local c12 = chamberOf("H12")
		hold(world, c, h12.x + 30, h12.y + 1, h12.z)
		TownAI.stepFrame(world, DT)
		svc:step(day + 0.02)
		hold(world, c, c12.x, c12.y + 0.8, c12.z)
		TownAI.stepFrame(world, DT)
		svc:step(day + 0.03)
		t.eq(told["player 2"][2], "This tree belongs to another squirrel. Your nuts stay with you.")
		svc:stop()
	end)

	t.test("every claimable tree has a name a player reads, and the words are mild", function()
		for _, h in layout.hollows do
			if h.claimable then
				local name = HollowService.NAMES[h.id]
				t.truthy(name ~= nil, `{h.id} has a name`)
				t.eq(HollowService.treeName(h), name)
				t.falsy(string.find(string.lower(name :: string), "chili", 1, true), `{h.id}: no restaurant brand`)
			end
		end
		for key, w in HollowService.WORDS do
			t.falsy(string.find(w, "!!", 1, true), key)
			t.truthy(#w < 100, `{key} is short`)
		end
	end)
end
