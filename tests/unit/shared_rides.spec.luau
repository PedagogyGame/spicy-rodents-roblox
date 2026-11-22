--!strict
-- Owner D29 (2026-11-22): "a scattered restricted total of 3 golf carts, 2 mopeds, and 5 electric scooters, anyone can
-- take them or use them, and you do not get tickets or problems with the police with them. prepare most carefully, the
-- dynamics, physics and scene of being hit by a ..." (the lead's reading: people dodge an oncoming one; one that is hit
-- is knocked aside, stumbles or falls and gets back up; mild, no gore).
--   spots     exactly 3 carts, 2 mopeds, 5 scooters (Shared/Vehicles/SharedRides.SPOTS, and so in DeviceService's
--             placements, in place of the two old carts), each clear of every road lane the town's vehicles drive, of
--             every building and fence (World/WalkWay), of the river, of every baked part over its footprint, on
--             nearly level ground, spread over the town, near where the town's people are
--   rules     the pure rules: in the way, met, the knock (aside, farther and longer down the faster), the cooldown,
--             going back to its spot
--   dodge     on the real town (tests/lib/BiteRig: the town AI on its lanes, the fleet, the sequence, the duel) with
--             Server/Vehicles/RideBumps stepped as Boot/Game steps it: a walker in the way of a scooter steps aside
--             square to its way and is never touched; then walks on
--   bumped    a walker who freezes is knocked aside along its way and to the side, down on the ground (Tumble) for the
--             time the speed gives, up again and walking; never a patient, never killed; the rider felt it; not again
--             within the cooldown; a slow bump is a stagger
--   players   a player's person or squirrel is knocked on its own client / put aside (opts.knockHeld), never killed; a
--             body aboard a vehicle is never in one's way; the computer's squirrels skitter off
--   run-over  the traffic's fatal sweep never sees a shared vehicle: a scooter over a player's squirrel fires no RunOver
--             (the fleet's own run-over is pinned unchanged by tests/unit/traffic_fleet.spec)
--   client    the client's halves: the tumble's push (Controllers/Human.knock), the rider's bump (Controllers/Vehicle.
--             afterBump), the standing rider and the down pose (Animation/AnimationDriver), the prompt (UI/RideHint)
local Data = require("@shared/Data")
local WalkWay = require("@shared/World/WalkWay")
local Height = require("@shared/World/Height")
local LaneMath = require("@shared/Traffic/LaneMath")
local VehicleKinds = require("@shared/Vehicles/VehicleKinds")
local SharedRides = require("@shared/Vehicles/SharedRides")
local Lines = require("@shared/Speech/Lines")
local TrafficService = require("@server/Traffic/TrafficService")
local DeviceService = require("@server/Actors/DeviceService")
local RideBumps = require("@server/Vehicles/RideBumps")
local Directive = require("@server/Actors/Brains/Directive")
local TownAI = require("@server/AI/TownAI")
local BiteRig = require("@tests/lib/BiteRig")
local Bake = require("@worldgen/Bake")
local Geometry = require("@worldgen/Geometry")
local Human = require("@client/Controllers/Human")
local Vehicle = require("@client/Controllers/Vehicle")
local AnimationDriver = require("@client/Animation/AnimationDriver")
local RideHint = require("@client/UI/RideHint")
local roblox = require("@lune/roblox")

local C = SharedRides.C
local DT = 0.05

-- the corners and centre of a vehicle's footprint at a spot, `pad` studs out
local function footprint(kind: string, x: number, z: number, yaw: number, pad: number): { { number } }
	local size = VehicleKinds.kind(kind).size
	local hw, hl = size[1] / 2 + pad, size[3] / 2 + pad
	local s, c = math.sin(yaw), math.cos(yaw)
	local out = {}
	for _, k in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 }, { 0, 0 } } do
		local lx, lz = k[1] * hw, k[2] * hl
		table.insert(out, { x + lx * c + lz * s, z - lx * s + lz * c })
	end
	return out
end

-- a walker on the town as Boot/Game runs it, with the bumps service; `rand` the dice
local function town(rand: () -> number)
	local rig = BiteRig.new({ dt = DT, seed = 3 })
	local world = rig.world
	local held: { { id: number, knock: any, squirrel: boolean, kind: string } } = {}
	local bumps: { string } = {}
	local rides: { any } = {}
	local aboard: { [number]: boolean } = {}
	local svc = RideBumps.new({
		world = world,
		speech = rig.speech,
		rides = function(): { any }
			return rides
		end,
		aboard = function(id: number): boolean
			return aboard[id] == true
		end,
		busy = function(pid: number): boolean
			return rig.infection:engaged(pid) or rig.combat:guardOf(pid) ~= nil
		end,
		setAttr = function(pid: number, name: string, value: any)
			rig.setAttr(pid, name, value)
		end,
		knockHeld = function(id: number, k: any, squirrel: boolean, kind: string)
			table.insert(held, { id = id, knock = k, squirrel = squirrel, kind = kind })
		end,
		bump = function(rideId: string)
			table.insert(bumps, rideId)
		end,
		rand = rand,
	})
	-- (`each` runs after the town's frame and before the service's step: what it measures or sets is what the service
	-- sees)
	local function step(secs: number, each: (() -> ())?)
		for _ = 1, math.max(1, math.floor(secs / DT + 0.5)) do
			rig.step(DT, function()
				for _, r in rides do
					r.x += r.vx * DT
					r.z += r.vz * DT
					r.floor = world.ctx.groundAt(r.x, r.z)
				end
				if each then
					each()
				end
				svc:step(DT)
			end)
		end
	end
	return {
		rig = rig,
		world = world,
		svc = svc,
		rides = rides,
		held = held,
		bumps = bumps,
		aboard = aboard,
		step = step,
	}
end

-- the townsperson nearest the town's centre who walks (no rider), as in tests/unit/regular_squirrel_people
local function walker(world: any): any
	local best, bestD = nil, math.huge
	for _, a in world.actors do
		local brain = world.brains[a.id]
		if
			a.species == "human"
			and a.post == "townsperson"
			and brain.kind == "Pedestrian"
			and not brain.params.cyclist
		then
			local d = a.x * a.x + a.z * a.z
			if d < bestD then
				best, bestD = a, d
			end
		end
	end
	return best
end

-- a ride `from` studs ahead of the person, coming straight at them at `speed`
local function headOn(T: any, p: any, kind: string, from: number, speed: number): any
	local fx, fz = math.sin(p.yaw), math.cos(p.yaw)
	local x, z = p.x + fx * from, p.z + fz * from
	local r = {
		id = `{kind}_1`,
		kind = kind,
		x = x,
		z = z,
		floor = T.world.ctx.groundAt(x, z),
		yaw = p.yaw + math.pi,
		vx = -fx * speed,
		vz = -fz * speed,
	}
	table.insert(T.rides, r)
	TownAI.setFocus(T.world, function()
		return { { x = r.x, z = r.z } }
	end)
	return r
end

local function always(v: number): () -> number
	return function(): number
		return v
	end
end

return function(t)
	t.test("spots: 3 carts, 2 mopeds, 5 scooters, the only carts placed, in place of the two old ones", function()
		local n: { [string]: number } = {}
		for _, s in SharedRides.SPOTS do
			n[s.kind] = (n[s.kind] or 0) + 1
			t.truthy(VehicleKinds.isShared(s.kind), `{s.kind} is a shared kind`)
		end
		t.eq(n.cart, 3)
		t.eq(n.moped, 2)
		t.eq(n.escooter, 5)
		local placed: { [string]: number } = {}
		for _, p in DeviceService.defaultPlacements(nil) do
			placed[p.kind] = (placed[p.kind] or 0) + 1
		end
		t.eq(placed.cart, 3, "no other carts")
		t.eq(placed.moped, 2)
		t.eq(placed.escooter, 5)
		-- the rest of the fleet as it was
		t.eq(placed.car, 2)
		t.eq(placed.bike, 2)
		t.eq(placed.pickup, 1)
		t.eq(placed.suv, 1)
		t.eq(placed.jetski, 1)
		t.eq(placed.drone, 1)
	end)

	t.test(
		"spots: off every road lane, out of every building, fence and the river, nothing baked over them, level",
		function()
			local data = Data.default()
			local way = WalkWay.new({ data = data })
			local traffic =
				TrafficService.new({ lanes = data:lanes(), roads = data:roads(), heightAt = Height.at, seed = 7 })
			local lanes: { { number } } = {}
			for id, lane in traffic.lanes do
				if LaneMath.isVehicleLane(id) then
					local len = LaneMath.length(lane)
					local s = 0
					while s <= len do
						local p = LaneMath.pointAt(lane, s, 1)
						table.insert(lanes, { p.x, p.z })
						s += 2
					end
				end
			end
			local parts = {}
			for _, plan in Bake.plans(Bake.data()) do
				for _, sp in plan.parts do
					if sp.canCollide or sp.canQuery ~= false then
						local x0, x1, y0, y1, z0, z1 = Geometry.aabb(sp)
						table.insert(
							parts,
							{ name = `{plan.id}/{sp.name}`, x0 = x0, x1 = x1, y0 = y0, y1 = y1, z0 = z0, z1 = z1 }
						)
					end
				end
			end
			for _, s in SharedRides.SPOTS do
				local tag = `{s.kind} at {s.where}`
				local size = VehicleKinds.kind(s.kind).size
				local corners = footprint(s.kind, s.x, s.z, s.yaw, 1)
				local lo, hi = math.huge, -math.huge
				for _, c in corners do
					local box = WalkWay.solidAt(way, c[1], c[2], 0)
					t.truthy(box == nil, `{tag}: a corner in a building or fence`)
					t.truthy(not Height.insideRiverWater(c[1], c[2]), `{tag}: in the river`)
					local h = Height.at(c[1], c[2])
					lo, hi = math.min(lo, h), math.max(hi, h)
				end
				t.truthy(hi - lo <= 1, `{tag}: the ground under it rises {hi - lo} studs`)
				-- no lane a car drives within its half length and a car's half width
				local near = math.huge
				for _, p in lanes do
					near = math.min(near, math.sqrt((p[1] - s.x) ^ 2 + (p[2] - s.z) ^ 2))
				end
				t.truthy(near >= size[3] / 2 + 6, `{tag}: {near} studs from a road lane`)
				-- nothing baked stands in it or over it (the ground ray that sets it down would land on it); the pavement
				-- it stands on is lower than 0.6 over the ground
				local r = math.sqrt((size[1] / 2 + 1) ^ 2 + (size[3] / 2 + 1) ^ 2)
				for _, q in parts do
					if q.x1 >= s.x - r and q.x0 <= s.x + r and q.z1 >= s.z - r and q.z0 <= s.z + r then
						t.truthy(q.y1 <= lo + 0.6, `{tag}: {q.name} over it`)
					end
				end
			end
		end
	)

	t.test("spots: spread over the town, and near where its people walk", function()
		local spots = SharedRides.SPOTS
		local closest = math.huge
		for i = 1, #spots do
			for j = i + 1, #spots do
				closest = math.min(closest, math.sqrt((spots[i].x - spots[j].x) ^ 2 + (spots[i].z - spots[j].z) ^ 2))
			end
		end
		t.truthy(closest >= 100, `the nearest two are {closest} studs apart`)
		-- the town's people at the start: how many have one within a short run (250 studs: about 10 s at a sprint)
		local rig = BiteRig.new({ dt = DT, seed = 3 })
		local people, near = 0, 0
		for _, a in rig.world.actors do
			if a.species == "human" then
				people += 1
				for _, s in spots do
					if (a.x - s.x) ^ 2 + (a.z - s.z) ^ 2 <= 250 * 250 then
						near += 1
						break
					end
				end
			end
		end
		print(`      {near} of {people} people start within 250 studs of a shared vehicle`)
		t.truthy(near >= people * 0.6, `{near} of {people}`)
	end)

	t.test("rules: in the way, met, the knock, down by speed, the cooldown, back to its spot", function()
		local r = { kind = "escooter", x = 0, z = 0, floor = 0, yaw = 0, vx = 0, vz = 20 }
		-- in its way: ahead within its look, inside its width and the margin; not behind, not off to the side
		t.truthy(SharedRides.oncoming(r, 0, 10, C.personR) ~= nil, "dead ahead")
		t.truthy(SharedRides.oncoming(r, 1.5, 10, C.personR) ~= nil, "a little to the side")
		t.truthy(SharedRides.oncoming(r, 0, -10, C.personR) == nil, "behind")
		t.truthy(SharedRides.oncoming(r, 6, 10, C.personR) == nil, "well to the side")
		t.truthy(SharedRides.oncoming(r, 0, 40, C.personR) == nil, "too far ahead to matter yet")
		local crawl = table.clone(r)
		crawl.vz = 1
		t.truthy(SharedRides.oncoming(crawl, 0, 3, C.personR) == nil, "a crawl past nobody")
		-- met: the box and a body's half width, feet near its floor
		t.truthy(SharedRides.hit(r, 0, 1.5, 0, C.personR), "at its front")
		t.truthy(not SharedRides.hit(r, 0, 3, 0, C.personR), "clear of its front")
		t.truthy(not SharedRides.hit(r, 0, 0, 6, C.personR), "a squirrel up a tree over it")
		-- the step aside: square to its way, clear of its side, on the side the person is on
		local dx, dz = SharedRides.dodgeTo(r, 0.4, 6, C.personR, SharedRides.dodgeSide(0.4, always(0.5)))
		t.near(dz, 6, 1e-9, "square to its way")
		t.truthy(dx >= 0.5 + C.dodgeClear, `clear of its side ({dx})`)
		-- the knock: along its way and to the side, farther and longer down the faster
		local slow = SharedRides.knock({ kind = "cart", x = 0, z = 0, floor = 0, yaw = 0, vx = 0, vz = 6 }, 0.3, 2)
		local fast = SharedRides.knock({ kind = "cart", x = 0, z = 0, floor = 0, yaw = 0, vx = 0, vz = 26 }, 0.3, 2)
		t.truthy(not slow.fall and slow.secs == C.staggerSecs, "slow: a stagger")
		t.truthy(fast.fall, "fast: a fall")
		t.truthy(fast.dz > 0 and fast.dx > 0, "along its way and away to the person's side")
		local d = math.sqrt(fast.dx ^ 2 + fast.dz ^ 2)
		t.truthy(d > math.sqrt(slow.dx ^ 2 + slow.dz ^ 2) and d <= C.knockMax, `knocked {d} studs`)
		t.near(SharedRides.downSecs(C.fallSpeed), C.downMin, 1e-9)
		t.near(SharedRides.downSecs(100), C.downMax, 1e-9)
		t.truthy(C.downMin >= 1.5 and C.downMax <= 3, "down 1.5 to 3 s")
		-- the cooldown
		local book = SharedRides.newBook()
		t.truthy(SharedRides.allow(book, 7, 10, C.cooldown))
		t.truthy(not SharedRides.allow(book, 7, 10 + C.cooldown - 0.1, C.cooldown), "not again so soon")
		t.truthy(SharedRides.allow(book, 7, 10 + C.cooldown, C.cooldown), "again after it")
		-- back to its spot: away, untouched long enough, nobody near
		t.truthy(SharedRides.returnHome(400, 0, 100, 200), "left far away, long ago, nobody near")
		t.truthy(not SharedRides.returnHome(100, 0, 100, 200), "not yet")
		t.truthy(not SharedRides.returnHome(400, 0, 5, 200), "it is home")
		t.truthy(not SharedRides.returnHome(400, 0, 100, 20), "a player is near")
		-- nobody owns one; no police trouble
		for _, kind in { "cart", "moped", "escooter" } do
			t.truthy(VehicleKinds.policeIgnore(kind), `{kind}: no tickets, no police`)
		end
	end)

	t.test("dodge: a walker in a scooter's way steps aside square to it, is never touched, and walks on", function()
		local T = town(always(0.1)) -- (every dodge taken)
		local p = walker(T.world)
		local brain = T.world.brains[p.id]
		local r = headOn(T, p, "escooter", 16, 20)
		-- its line: where it started, along its way
		local lx, lz, ux, uz = r.x, r.z, r.vx / 20, r.vz / 20
		local gap = math.huge
		T.step(1.6, function()
			-- the person's distance from its line while it is level with them
			local along = (p.x - r.x) * ux + (p.z - r.z) * uz
			if math.abs(along) < 2 then
				gap = math.min(gap, math.abs((p.x - lx) * uz - (p.z - lz) * ux))
			end
		end)
		local s = T.svc:stats()
		t.eq(s.dodges, 1, "stepped aside once")
		t.eq(s.knocks, 0, "never bumped")
		t.eq(#T.bumps, 0)
		t.truthy(gap >= 0.5 + C.personR, `clear of its side as it passed ({gap})`)
		t.eq(T.rig.attrs[p.id] and T.rig.attrs[p.id].Tumble, nil, "never down")
		table.clear(T.rides)
		T.step(3)
		t.truthy(not Directive.active(brain.directive), "the step's order is over")
		local x1, z1 = p.x, p.z
		T.step(2)
		t.truthy(math.sqrt((p.x - x1) ^ 2 + (p.z - z1) ^ 2) > 1, "walking again")
		t.eq(p.infected, nil, "never a patient")
	end)

	t.test("bumped: knocked aside and down by a fast cart, up again and walking; once in the cooldown", function()
		local T = town(always(0.99)) -- (nobody steps aside)
		local p = walker(T.world)
		local brain = T.world.brains[p.id]
		local r = headOn(T, p, "cart", 14, 24)
		local x0, z0 = p.x, p.z
		local downAt: number? = nil
		local upAt: number? = nil
		T.step(1.5, function()
			local tumble = T.rig.attrs[p.id] and T.rig.attrs[p.id].Tumble
			if tumble == "down" and downAt == nil then
				downAt = T.rig.time
			end
		end)
		local s = T.svc:stats()
		t.eq(s.knocks, 1, "bumped once")
		t.eq(s.falls, 1, "and fell")
		t.eq(#T.bumps, 1, "the rider felt it")
		t.truthy(downAt ~= nil, "on the ground (Tumble down)")
		t.truthy(Directive.active(brain.directive), "held still while down")
		local moved = math.sqrt((p.x - x0) ^ 2 + (p.z - z0) ^ 2)
		t.truthy(moved >= 1.5, `knocked {moved} studs aside`)
		-- the same cart back through them at once: not again within the cooldown
		r.vx, r.vz = -r.vx, -r.vz
		r.x, r.z = p.x - r.vx * 0.3, p.z - r.vz * 0.3
		T.step(0.6)
		t.eq(T.svc:stats().knocks, 1, "not knocked again so soon")
		table.clear(T.rides)
		T.step(4, function()
			local tumble = T.rig.attrs[p.id] and T.rig.attrs[p.id].Tumble
			if tumble == nil and downAt and upAt == nil then
				upAt = T.rig.time
			end
		end)
		t.truthy(upAt ~= nil, "up again")
		local lay = (upAt :: number) - (downAt :: number)
		t.truthy(lay >= C.downMin - DT and lay <= C.downMax + 2 * DT, `down {lay} s`)
		t.truthy(not Directive.active(brain.directive), "the order is over")
		local x1, z1 = p.x, p.z
		T.step(2)
		t.truthy(math.sqrt((p.x - x1) ^ 2 + (p.z - z1) ^ 2) > 1, "walking on")
		t.eq(p.infected, nil, "never a patient")
		t.eq(T.rig.attrs[p.id] and T.rig.attrs[p.id].Med, nil, "no Med")
		-- a word of surprise, from the mild lines
		for _, said in T.rig.said do
			if said.id == p.id then
				t.truthy(said.situation == "bumped" or said.situation == "rideClose", `said "{said.line}"`)
			end
		end
	end)

	t.test("bumped, then taken by a player while down: the order goes with it, the body is free when let go", function()
		local T = town(always(0.99))
		local p = walker(T.world)
		headOn(T, p, "cart", 10, 24)
		T.step(0.8)
		t.eq(T.svc:stats().falls, 1, "down")
		T.rig.hold(p.id)
		T.step(0.2)
		t.eq(T.rig.attrs[p.id].Tumble, nil, "up the moment a player has it")
		table.clear(T.rides)
		T.rig.let(p.id)
		T.step(0.5)
		t.truthy(not Directive.active(T.world.brains[p.id].directive), "no order left on the brain")
	end)

	t.test("bumped slowly: a stagger (arms up, a short shove), never down", function()
		local T = town(always(0.99))
		local p = walker(T.world)
		headOn(T, p, "escooter", 6, 6)
		local downs = 0
		T.step(1.5, function()
			if T.rig.attrs[p.id] and T.rig.attrs[p.id].Tumble then
				downs += 1
			end
		end)
		local s = T.svc:stats()
		t.eq(s.knocks, 1)
		t.eq(s.falls, 0, "no fall")
		t.eq(downs, 0, "never on the ground")
		table.clear(T.rides)
		T.step(2)
		t.truthy(not Directive.active(T.world.brains[p.id].directive), "on their way")
	end)

	t.test("players: a held person is knocked on their client, a held squirrel put aside; aboard: never", function()
		local T = town(always(0.99))
		local p = walker(T.world)
		T.rig.hold(p.id)
		headOn(T, p, "moped", 12, 26)
		T.step(1)
		t.eq(#T.held, 1, "one knock")
		local h = T.held[1]
		t.eq(h.id, p.id)
		t.truthy(not h.squirrel and h.knock.fall and h.kind == "moped", "a person, over, by a moped")
		t.truthy(h.knock.secs >= C.downMin and h.knock.secs <= C.downMax)
		-- the same, aboard a vehicle: nothing
		local T2 = town(always(0.99))
		local p2 = walker(T2.world)
		T2.rig.hold(p2.id)
		T2.aboard[p2.id] = true
		headOn(T2, p2, "moped", 12, 26)
		T2.step(1)
		t.eq(#T2.held, 0, "aboard: never in its way")
		-- a player's squirrel on the ground in its way: put aside, dazed, never killed (nothing here kills)
		local T3 = town(always(0.99))
		local sq = nil
		for _, a in T3.world.actors do
			if a.species == "squirrel" and a.variant == "normal" then
				sq = a
				break
			end
		end
		t.truthy(sq ~= nil)
		local q = sq :: any
		T3.rig.hold(q.id)
		local p3 = walker(T3.world)
		T3.rig.put(q.id, p3.x + 40, p3.z + 40, 0)
		q.y = T3.world.ctx.groundAt(q.x, q.z) + q.hip
		headOn(T3, q, "escooter", 8, 20)
		T3.step(1)
		t.eq(#T3.held, 1, "the squirrel bumped aside")
		t.truthy(T3.held[1].squirrel, "as a squirrel")
		t.eq(T3.svc:stats().squirrels, 1)
	end)

	t.test("run-over: the traffic's fatal sweep never sees a shared vehicle over a player's squirrel", function()
		local data = Data.default()
		local svc = TrafficService.new({ lanes = data:lanes(), roads = data:roads(), heightAt = Height.at, seed = 7 })
		local hits = 0
		svc.RunOver:connect(function()
			hits += 1
		end)
		-- a scooter at its spot in the old town centre, rolling at 20 studs/s over a squirrel on the lawn
		local spot = SharedRides.SPOTS[6]
		local sq = { id = "p", x = spot.x, y = 0.2, z = spot.z }
		for i = 1, 30 do
			local z = spot.z - 10 + i * (20 / 30)
			svc:step(1 / 30, {
				squirrels = { sq },
				cars = { { id = "escooter_1", x = spot.x, z = z, yaw = 0, width = 1, length = 3.2, speed = 20 } },
			})
		end
		t.eq(hits, 0, "no RunOver from a shared vehicle")
	end)

	t.test(
		"the computer's squirrels on the ground in a scooter's way skitter off (a startle), never knocked flat",
		function()
			local T = town(always(0.99))
			local p = walker(T.world)
			local q = nil
			for _, a in T.world.actors do
				if a.species == "squirrel" and a.variant == "normal" then
					q = a
					break
				end
			end
			local s = q :: any
			-- (held on the ground at a spot near the walker, as one out on the ground would be: its rails would take it up)
			local gx, gz = p.x + 30, p.z + 30
			local function ground()
				s.x, s.z = gx, gz
				s.y = T.world.ctx.groundAt(gx, gz) + s.hip
			end
			ground()
			local seen = {}
			local brain = T.world.brains[s.id]
			local was = brain.onEvent
			brain.onEvent = function(self: any, evt: any)
				table.insert(seen, evt.type)
				return was(self, evt)
			end
			headOn(T, s, "escooter", 8, 20)
			T.step(0.6, ground)
			t.truthy(table.find(seen, "startle") ~= nil, "startled off")
			t.truthy(table.find(seen, "runOver") == nil, "never run over")
			t.eq(#T.held, 0, "no knock for the computer's")
			t.truthy(s.gone ~= true, "still in town")
		end
	)

	t.test("client: the tumble's push, the rider's bump, the standing rider, the down pose, the prompt", function()
		-- Controllers/Human.knock
		local now = 100
		local push = Human.knock(roblox.Vector3.new(2, 2.5, -1), true, now - 0.1, now) :: any
		t.truthy(push ~= nil and push.fall, "a fresh fall")
		t.near(push.vx, 2 / Human.KNOCK.slide, 1e-6)
		t.near(push.vz, -1 / Human.KNOCK.slide, 1e-6)
		t.truthy(push.vy > 0, "a small hop")
		t.near(push.secs, 2.5, 1e-6)
		t.near(push.tipX * 2 + push.tipZ * -1, 0, 1e-6, "tips over about an axis square to the push")
		t.eq(Human.knock(roblox.Vector3.new(2, 2.5, -1), true, now - 5, now), nil, "a stale knock is not played")
		t.eq(Human.knock("nonsense", true, now, now), nil)
		local stagger = Human.knock(roblox.Vector3.new(1, 0.7, 0), false, now, now) :: any
		t.truthy(not stagger.fall and stagger.vy == 0, "a stagger: a push, no hop")
		-- Controllers/Vehicle.afterBump
		local sp, seen = Vehicle.afterBump(20, nil, 5)
		t.near(sp, 20 * C.keep, 1e-9, "slowed")
		local sp2 = Vehicle.afterBump(sp, seen, 5)
		t.eq(sp2, sp, "once a bump")
		-- Animation/AnimationDriver
		t.eq(AnimationDriver.seatClip("escooter"), "idle", "the scooter's rider stands")
		t.eq(AnimationDriver.seatClip("moped"), "sit")
		t.eq(AnimationDriver.seatClip(nil), "sit")
		t.eq(AnimationDriver.medOf(nil, "down"), "down", "knocked over: the patient's sit on the ground")
		t.eq(AnimationDriver.medOf("symptomatic", "down"), "symptomatic", "a Med wins")
		t.eq(AnimationDriver.medOf(nil, nil), nil)
		-- UI/RideHint
		local cands = { { x = 10, z = 0, free = true }, { x = 3, z = 0, free = false }, { x = 30, z = 0, free = true } }
		t.eq(RideHint.pick(0, 0, cands), 1, "the nearest free one in reach")
		t.eq(RideHint.pick(100, 0, cands), nil, "none in reach")
		t.eq(RideHint.words("escooter", false, false), "E  ride the scooter")
		t.eq(RideHint.words("cart", true, false), "RIDE")
		-- (owner D32, never stuck: a touch screen has no E, so every device but the sky lift has its way out)
		t.eq(RideHint.offWords("vehicle"), "GET OFF", "any vehicle, a shared one or not")
		t.eq(RideHint.offWords("passenger"), "GET OFF", "beside the golf cart's driver")
		t.eq(RideHint.offWords("drone"), "LAND")
		t.eq(RideHint.offWords("ride"), nil, "the sky lift's cabin takes its riders to the platform")
		t.eq(RideHint.offWords(nil), nil, "on foot")
		-- the lines are mild and short (tests/unit/speech.spec holds every line to its rules)
		for _, situation in { "rideClose", "bumped" } do
			t.truthy(#Lines.of(situation) >= 4, situation)
		end
	end)
end
