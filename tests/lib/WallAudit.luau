--!strict
-- tests/lib/WallAudit: does any computer-run body walk through a wall of the baked town (the owner's playtest,
-- 19 November: "one of the characters ran through a wall")? The town's people are anchored and kinematic
-- (Movement/HumanAIMotor moves them in straight legs toward whatever their brain or a service names): nothing in
-- the engine stops one at a wall, so every leg must already go round.
--   load(files?) -> Town         the solids of the baked town: build/Town.rbxm, the bowling alley and the TV
--                                 station (build/Attractions.rbxm) and the built expansions (the corner store, Bowl
--                                 Lane, the lounge, the Neighbourhood Shop, the sky lift and the Lookout); a file not
--                                 baked is listed in `missing`
--   wall(part) -> boolean         a colliding part that is a wall to a walker: not a tree (its trunk and limbs), not
--                                 a small prop (a post, a hydrant: under PROP across both ways)
--   crossing(town, ax, ay, az, bx, by, bz) -> Part?   the wall a step from feet (a) to feet (b) walks into, tested
--                                 at HEIGHTS over the feet (a waist and a chest: what is lower is stepped over or a
--                                 bench, not a wall); a step that starts inside a part is not walking into it
--   inside(town, x, y, z) -> Part?   the wall holding a body's waist
--   standable(town, x, feet, z) -> boolean   a player could leave a body here: ground under it within a step of
--                                 `feet` and nothing in the body's box
--   run(town, data, opts) -> Report   the whole town AI (AI/TownAI with every brain, the real TrafficService, the
--                                 bite-to-hospital sequence with its crowds, ambulances and walks, the staff loops),
--                                 with a player on the rodent biting someone every `biteEvery` seconds, police
--                                 calls and stakeouts, and bodies a player walked somewhere and let go (anywhere a
--                                 body can stand: in the houses, the alley, the venues, the yards), stepped for
--                                 `minutes`; every step of every computer-run body on the ground is tested
--   dogs(town, minutes, night) -> Report   the yard dogs' own walk (Shared/Wildlife/YardDogs), day or night
-- Report: steps tested, `crossings` (each with the body, its post, the brain and the leg that moved it, the part),
-- `byCause` and `byPart` counts, `inside` (body-steps spent with the waist in a wall, by cause), `jumps` (moves
-- longer than JUMP in one step: a body placed somewhere, not a walk).
-- Pure Lune (BakedWorld loads the files). Studs.

local fs = require("@lune/fs")
local BakedWorld = require("@tests/lib/BakedWorld")
local Height = require("@shared/World/Height")
local AlleyStaff = require("@shared/Attractions/AlleyStaff")
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local YardDogs = require("@shared/Wildlife/YardDogs")
local Rng = require("@shared/Util/Rng")
local TownAI = require("@server/AI/TownAI")
local TrafficService = require("@server/Traffic/TrafficService")
local InfectionService = require("@server/Infection/InfectionService")
local CombatService = require("@server/Combat/CombatService")

local WallAudit = {}

WallAudit.FILES = {
	"build/Town.rbxm",
	"build/Attractions.rbxm",
	"build/Expansion_F1.rbxm",
	"build/Expansion_F2.rbxm",
	"build/Expansion_LoungeClassic.rbxm",
	"build/Expansion_NeighbourhoodShop.rbxm",
	"build/Expansion_F4.rbxm",
}
WallAudit.HEIGHTS = { 2.0, 3.8 } -- studs over the feet (a townsperson is 5.2 tall, the hip 2.5)
WallAudit.PROP = 3 -- studs: no wider than this both ways is a prop (a telephone pole, a post, a sign), not a wall
WallAudit.JUMP = 8 -- studs in one step: a body placed somewhere, not walking
WallAudit.EXAMPLES = 6 -- crossings kept per cause
WallAudit.TRAILS = false -- format() prints each example's last steps
WallAudit.TRAIL = 8 -- steps kept

export type Town = { worlds: { BakedWorld.World }, missing: { string } }

export type Crossing = {
	t: number,
	id: number,
	post: string,
	cause: string,
	part: string,
	ax: number,
	az: number,
	bx: number,
	bz: number,
	y: number,
	trail: { string }?, -- the body's last steps before it (each: time, place, what moved it)
}

export type Report = {
	steps: number,
	crossings: number,
	byCause: { [string]: number },
	byPart: { [string]: number },
	examples: { [string]: { Crossing } },
	inside: { [string]: number },
	insideExamples: { [string]: { Crossing } },
	jumps: number,
	events: { [string]: number },
	-- (review, RunOpts.soft) steps through trees ("tree") and props by part name; shoulder clips by cause
	soft: { [string]: number }?,
	shoulder: { [string]: number }?,
	shoulderExamples: { [string]: { Crossing } }?,
	stuck: { string }?, -- bodies that stood 60 s or more for want of a way
}

function WallAudit.load(files: { string }?): Town
	local town: Town = { worlds = {}, missing = {} }
	for _, path in files or WallAudit.FILES do
		if fs.isFile(path) then
			table.insert(town.worlds, BakedWorld.load(path, nil, { adjust = BakedWorld.alleyRuntime }))
		else
			table.insert(town.missing, path)
		end
	end
	return town
end

local function isTree(p: BakedWorld.Part): boolean
	-- (the town's trees, and the trunks of the countryside's oaks and apple trees)
	return string.find(p.path, "Tree_", 1, true) ~= nil or p.name == "Limb" or p.name == "Trunk"
end

function WallAudit.wall(p: BakedWorld.Part): boolean
	if not p.collide or isTree(p) then
		return false
	end
	return p.x1 - p.x0 > WallAudit.PROP or p.z1 - p.z0 > WallAudit.PROP
end

local wall = WallAudit.wall

function WallAudit.crossing(
	town: Town,
	ax: number,
	ay: number,
	az: number,
	bx: number,
	by: number,
	bz: number
): BakedWorld.Part?
	local dx, dy, dz = bx - ax, by - ay, bz - az
	if dx * dx + dz * dz < 1e-8 then
		return nil
	end
	for _, h in WallAudit.HEIGHTS do
		for _, w in town.worlds do
			local t, part = w.raycast(ax, ay + h, az, dx, dy, dz, wall)
			if t and part then
				return part
			end
		end
	end
	return nil
end

-- (review) the tree or prop a step walks through at the waist (what `wall` leaves out), if any
function WallAudit.softCrossing(
	town: Town,
	ax: number,
	ay: number,
	az: number,
	bx: number,
	by: number,
	bz: number
): BakedWorld.Part?
	local dx, dy, dz = bx - ax, by - ay, bz - az
	if dx * dx + dz * dz < 1e-8 then
		return nil
	end
	local function soft(p: BakedWorld.Part): boolean
		return p.collide and not wall(p)
	end
	for _, w in town.worlds do
		local t, part = w.raycast(ax, ay + WallAudit.HEIGHTS[1], az, dx, dy, dz, soft)
		if t and part then
			return part
		end
	end
	return nil
end

-- (review) a wall a step's shoulders walk into: the lines SHOULDER studs to either side of the step, at HEIGHTS
function WallAudit.shoulderCrossing(
	town: Town,
	ax: number,
	ay: number,
	az: number,
	bx: number,
	by: number,
	bz: number
): BakedWorld.Part?
	local dx, dz = bx - ax, bz - az
	local len = math.sqrt(dx * dx + dz * dz)
	if len < 1e-4 then
		return nil
	end
	local ox, oz = -dz / len * WallAudit.SHOULDER, dx / len * WallAudit.SHOULDER
	for _, s in { 1, -1 } do
		local part = WallAudit.crossing(town, ax + ox * s, ay, az + oz * s, bx + ox * s, by, bz + oz * s)
		if part then
			return part
		end
	end
	return nil
end

function WallAudit.inside(town: Town, x: number, y: number, z: number): BakedWorld.Part?
	for _, w in town.worlds do
		local hit = w.containing(x, y + WallAudit.HEIGHTS[1], z, wall)
		if #hit > 0 then
			return hit[1]
		end
	end
	return nil
end

local AXES = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }

-- the ground a body stands on at (x, z) near `feet`: the highest colliding top no more than a step above the feet
function WallAudit.groundNear(town: Town, x: number, feet: number, z: number): number
	local best = -math.huge
	for _, w in town.worlds do
		local g = w.groundAt(x, z, feet + 0.5)
		if g > best then
			best = g
		end
	end
	return best
end

function WallAudit.standable(town: Town, x: number, feet: number, z: number): boolean
	if math.abs(WallAudit.groundNear(town, x, feet, z) - feet) > 1.2 then
		return false
	end
	for _, w in town.worlds do
		if #w.overlapBox(x, feet + 2.7, z, AXES, { 0.9, 1.9, 0.9 }, function(p)
			return p.collide
		end) > 0 then
			return false
		end
	end
	return true
end

-- what moved a body this step: the brain, and the leg of its life it is on
local function causeOf(world: any, actor: any): string
	local brain = world.brains[actor.id]
	if brain == nil then
		return "none"
	end
	local kind = brain.kind
	local d = brain.directive
	local tag = brain._auditTag
	if d and d.mode ~= nil then
		return `{kind}:directive {d.mode}{if tag then " (" .. tag .. ")" else ""}`
	end
	if kind == "Pedestrian" then
		return `Pedestrian:{brain.state}{if actor.post == "rider" then " rider" else ""}`
	elseif kind == "Staff" then
		local leg = if brain.back then "way back" elseif brain.stops then "work loop" else "circuit"
		return `Staff:{leg} ({actor.post})`
	elseif kind == "Officer" then
		local leg = if brain.stakeout
			then "stakeout"
			elseif world.now < (brain.respondUntil or 0) then "respond"
			else "beat"
		return `Officer:{leg}`
	end
	return kind
end

local function newReport(): Report
	return {
		steps = 0,
		crossings = 0,
		byCause = {},
		byPart = {},
		examples = {},
		inside = {},
		insideExamples = {},
		jumps = 0,
		events = {},
	}
end

local function topPath(path: string): string
	-- the lot or model and the part's own name: Lots.<lot>.<part> -> <lot>.<part>
	local parts = string.split(path, ".")
	if #parts >= 3 and (parts[1] == "Lots" or parts[1] == "Props" or parts[1] == "Roads") then
		return parts[2] .. "." .. parts[#parts]
	end
	return parts[1] .. "." .. parts[#parts]
end

local function note(report: Report, c: Crossing)
	report.crossings += 1
	report.byCause[c.cause] = (report.byCause[c.cause] or 0) + 1
	local key = topPath(c.part)
	report.byPart[key] = (report.byPart[key] or 0) + 1
	local list = report.examples[c.cause]
	if list == nil then
		list = {}
		report.examples[c.cause] = list
	end
	if #list < WallAudit.EXAMPLES then
		table.insert(list, c)
	end
end

local function count(report: Report, kind: string)
	report.events[kind] = (report.events[kind] or 0) + 1
end

export type RunOpts = {
	seed: number,
	minutes: number,
	dt: number?, -- seconds a step (0.2)
	biteEvery: number?, -- seconds between the rodent's bites (25)
	handBackEvery: number?, -- seconds between bodies a player leaves somewhere (12)
	policeEvery: number?, -- seconds between police calls (40)
	near: boolean?, -- brains near the rodent think at the near rate (a player is there); else nobody is near
	rail: any?,
	world: any?, -- reuse a built world's rail
	-- (review additions, all off by default)
	combat: boolean?, -- run Combat/CombatService (the duel: people square up, close in, back away) round the rodent,
	-- which feints every few seconds while it lingers at a scene
	chase: boolean?, -- after each bite the two nearest officers chase the rodent (a new "respond" every 0.5 s, 40 s)
	soft: boolean?, -- also count steps through trees and props (report.soft) and shoulder clips (report.shoulder:
	-- the centre line clear but a line SHOULDER to either side hits a wall)
}

WallAudit.SHOULDER = 0.9 -- studs: half a townsperson's shoulder width

-- spots where a player could leave a body: in every lot (houses with rooms, shops, yards), in the venues, in the
-- alley, on open ground; each one a place a body stands (the AI's own ground agrees with the baked one)
local function dropSpots(town: Town, data: any, world: any, rng: any): { { number } }
	local out: { { number } } = {}
	local ctx = world.ctx
	local function try(x: number, z: number)
		local feet = ctx.groundAt(x, z)
		if WallAudit.standable(town, x, feet, z) then
			table.insert(out, { x, z })
		end
	end
	for _, lot in data:lots() do
		local fp = lot.footprint
		if fp then
			for _ = 1, 4 do
				try(lot.x + (rng.next() - 0.5) * (fp.w + 16), lot.z + (rng.next() - 0.5) * (fp.d + 16))
			end
		end
	end
	local ex = data:module("Expansion") :: any
	for _, v in (if ex and ex.venues then ex.venues else {}) :: { any } do
		local poly = v.footPoly
		if v.built and poly and #poly >= 3 then
			local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
			for _, p in poly do
				minX, maxX = math.min(minX, p[1]), math.max(maxX, p[1])
				minZ, maxZ = math.min(minZ, p[2]), math.max(maxZ, p[2])
			end
			for _ = 1, 24 do
				try(minX - 8 + rng.next() * (maxX - minX + 16), minZ - 8 + rng.next() * (maxZ - minZ + 16))
			end
		end
	end
	local alley = AlleyStaff.placeOf(data)
	if alley then
		for _ = 1, 60 do
			local lx = AlleyLayout.X0 + rng.next() * (AlleyLayout.X1 - AlleyLayout.X0)
			local ld = AlleyLayout.FRONT_D + rng.next() * (AlleyLayout.REAR_WALL_D - AlleyLayout.FRONT_D)
			-- (not on the lanes: a player cannot get past the LaneGuard)
			local onLanes = false
			for _, zone in AlleyLayout.ZONES do
				if zone.id == "lanes" and lx >= zone.x0 and lx <= zone.x1 and ld >= zone.d0 and ld <= zone.d1 then
					onLanes = true
				end
			end
			local x, _, z = AlleyLayout.toWorld(alley, lx, 0, ld)
			if not onLanes then
				try(x, z)
			end
		end
	end
	local b = world.ctx.bounds
	for _ = 1, 200 do
		try(b.minX + rng.next() * (b.maxX - b.minX), b.minZ + rng.next() * (b.maxZ - b.minZ))
	end
	return out
end

function WallAudit.run(town: Town, data: any, opts: RunOpts): Report
	local report = newReport()
	local dt = opts.dt or 0.2
	local rng = Rng.new(opts.seed)
	local world = TownAI.build({ data = data, seed = opts.seed, rail = opts.rail })
	local traffic = TrafficService.new({
		lanes = data:lanes(),
		roads = data:roads(),
		heightAt = Height.at,
		seed = opts.seed + 6,
	})
	local locked: { [number]: boolean } = {}
	local svc = InfectionService.new({
		world = world,
		traffic = traffic,
		data = data,
		rand = function(): number
			return rng.next()
		end,
		-- (a body the service has taken off the players, a crew member out on a call, is never handed to one)
		setPossessable = function(id: number, value: boolean)
			locked[id] = if value then nil else true
		end,
	})
	-- which part of the service gave an order (for the report: the function names on the stack)
	if WallAudit.TRAILS then
		for _, brain in world.brains do
			local b = brain :: any
			local on = b.onEvent
			b.onEvent = function(self: any, evt: any)
				if evt.type == "medical" and evt.mode ~= nil then
					local names = {}
					for level = 2, 8 do
						local name = debug.info(level, "n")
						if name and name ~= "" then
							table.insert(names, name)
						end
					end
					local pts = {}
					for i, q in evt.points or {} do
						if i <= 3 then
							table.insert(pts, string.format("%.0f,%.0f", q[1], q[2]))
						end
					end
					self._auditTag = table.concat(names, "<") .. " " .. table.concat(pts, " ")
				end
				return on(self, evt)
			end
		end
	end
	-- what the brains' ways cost (a brain asks inside a server frame)
	local ctx = world.ctx :: any
	local way = ctx.way
	local ways, worstMs, slow, none = 0, 0, 0, 0
	local stepMs, worstStepMs = 0, 0
	if way then
		ctx.way = function(x0: number, z0: number, x1: number, z1: number): any
			local t0 = os.clock()
			local out = way(x0, z0, x1, z1)
			ways += 1
			local ms = (os.clock() - t0) * 1000
			stepMs += ms
			worstMs = math.max(worstMs, ms)
			slow += if ms > 4 then 1 else 0
			none += if out == nil then 1 else 0
			return out
		end
	end
	-- the rodent is a player's
	local rodent: any = nil
	for _, a in world.actors do
		if a.variant == "spicy" then
			rodent = a
		end
	end
	TownAI.suspend(world, rodent.id)
	local combat: any = nil
	if opts.combat then
		combat = CombatService.new({
			world = world,
			infection = svc,
			rand = function(): number
				return rng.next()
			end,
			rodents = function(): { number }
				return { rodent.id }
			end,
		})
	end
	local nextFeint = 0
	local chases: { [number]: number } = {} -- officer id -> chase ends
	local nextChase = 0
	local stuckRun: { [number]: number } = {}
	local stuckWorst: { [number]: { number } } = {} -- id -> { seconds, x, z }
	report.soft = {}
	report.shoulder = {}
	report.shoulderExamples = {}
	if opts.near then
		TownAI.setFocus(world, function()
			return { { x = rodent.x, z = rodent.z } }
		end)
	end
	local spots = dropSpots(town, data, world, rng)
	report.events.spots = #spots
	local humans, officers = {}, {}
	for _, a in world.actors do
		if a.species == "human" then
			table.insert(humans, a)
			local brain = world.brains[a.id]
			if brain and brain.kind == "Officer" then
				table.insert(officers, a)
			end
		end
	end
	local function pick(list: { any }): any
		return list[math.floor(rng.next() * #list) + 1]
	end
	-- bodies a player holds now: id -> when they are let go
	local held: { [number]: number } = {}
	local function spot(): { number }
		return pick(spots)
	end
	local function free(a: any): boolean
		return not world.possessed[a.id] and (a.lift or 0) == 0
	end

	local biteEvery = opts.biteEvery or 25
	local handBackEvery = opts.handBackEvery or 12
	local policeEvery = opts.policeEvery or 40
	local nextBite, nextHand, nextPolice = 5, 3, 10
	local victimAt: { number }? = nil
	local stay = 0

	local prev: { [number]: { number } } = {}
	local trails: { [number]: { string } } = {}
	for _, a in world.actors do
		prev[a.id] = { a.x, a.y - a.hip, a.z }
		trails[a.id] = {}
	end

	local steps = math.floor(opts.minutes * 60 / dt + 0.5)
	for _ = 1, steps do
		local now = world.now
		-- the player on the rodent: to a victim, a bite, a few seconds round the scene, then the next
		if now >= nextBite then
			nextBite = now + biteEvery * (0.5 + rng.next())
			local victim = nil
			for _ = 1, 20 do
				local v = pick(humans)
				if free(v) and svc:biteable(v.id) then
					victim = v
					break
				end
			end
			if victim then
				local ang = rng.next() * math.pi * 2
				local rx, rz = victim.x + math.cos(ang) * 2.5, victim.z + math.sin(ang) * 2.5
				rodent.x, rodent.z = rx, rz
				rodent.y = world.ctx.groundAt(rx, rz) + rodent.hip
				if svc:bite(victim.id, rodent.id) then
					count(report, "bites")
				end
				victimAt = { victim.x, victim.z }
				stay = now + 6 + rng.next() * 10
				if opts.chase then
					local cops = table.clone(officers)
					table.sort(cops, function(p: any, q: any): boolean
						return (p.x - rx) ^ 2 + (p.z - rz) ^ 2 < (q.x - rx) ^ 2 + (q.z - rz) ^ 2
					end)
					for i = 1, math.min(2, #cops) do
						if free(cops[i]) then
							chases[cops[i].id] = now + 40
						end
					end
				end
			end
		elseif victimAt and now < stay then
			-- (it lingers by the scene: people round the patient see it and run)
			local ang = now * 0.7
			rodent.x, rodent.z = victimAt[1] + math.cos(ang) * 6, victimAt[2] + math.sin(ang) * 6
			if combat and now >= nextFeint then
				nextFeint = now + 2 + rng.next() * 3
				combat:rodentAct(rodent.id, "feint", now)
			end
		elseif victimAt then
			victimAt = nil
			local s = spot()
			rodent.x, rodent.z = s[1], s[2]
		end
		-- a player takes a body, walks it somewhere a body can stand, and lets it go
		if now >= nextHand then
			nextHand = now + handBackEvery * (0.5 + rng.next())
			local a = pick(humans)
			if
				free(a)
				and held[a.id] == nil
				and not locked[a.id]
				and a.post ~= "rider"
				and svc:stateOf(a.id) == nil
			then
				TownAI.suspend(world, a.id)
				local s = spot()
				a.x, a.z = s[1], s[2]
				a.y = world.ctx.groundAt(s[1], s[2]) + a.hip
				held[a.id] = now + 5 + rng.next() * 30
				count(report, "handBacks")
			end
		end
		for id, at in held do
			if now >= at then
				held[id] = nil
				local a = world.actorsById[id]
				TownAI.resume(world, id, a.x, a.y, a.z)
				-- (the jump to the spot is the player's walk: it is not tested)
				prev[id] = { a.x, a.y - a.hip, a.z }
			end
		end
		-- the police: a call to a spot (the alley's door after a sighting in the rafters, a storm drain's grate
		-- after the rodent came up), or a stakeout beside a grate
		if now >= nextPolice and #officers > 0 then
			nextPolice = now + policeEvery * (0.5 + rng.next())
			local o = pick(officers)
			local brain = world.brains[o.id] :: any
			if free(o) and brain then
				local s = spot()
				if rng.next() < 0.7 then
					brain:onEvent({ type = "respond", x = s[1], z = s[2], untilTime = now + 20 + rng.next() * 30 })
					count(report, "responds")
				else
					brain:onEvent({
						type = "stakeout",
						x = s[1],
						z = s[2],
						faceX = s[1] + 2,
						faceZ = s[2],
						secs = 10 + rng.next() * 20,
						mouth = tostring(s[1]),
					})
					count(report, "stakeouts")
				end
			end
		end

		-- (the police chase: CombatService.stepChases re-orders a chasing officer every 0.5 s where the rodent is)
		if now >= nextChase then
			nextChase = now + 0.5
			for id, untilT in chases do
				local brain = world.brains[id] :: any
				if now >= untilT or not free(world.actorsById[id]) or locked[id] then
					chases[id] = nil
				elseif brain then
					brain:onEvent({ type = "respond", x = rodent.x, z = rodent.z, untilTime = now + 1 })
					count(report, "chaseOrders")
				end
			end
		end
		stepMs = 0
		TownAI.stepFrame(world, dt)
		traffic:step(dt, { people = {} })
		svc:step(dt)
		if combat then
			combat:step(dt, world.now)
		end
		worstStepMs = math.max(worstStepMs, stepMs)

		for _, a in world.actors do
			local p = prev[a.id]
			local fx, fy, fz = a.x, a.y - a.hip, a.z
			if world.possessed[a.id] or (a.lift or 0) ~= 0 or a.intent.mode == "rail" then
				p[1], p[2], p[3] = fx, fy, fz
				continue
			end
			local mx, mz = fx - p[1], fz - p[3]
			if combat and (world.brains[a.id] :: any).state == "duel" and a.intent.mode == "walk" then
				count(report, "duelWalkSteps")
			end
			local trail = trails[a.id]
			if #trail >= WallAudit.TRAIL then
				table.remove(trail, 1)
			end
			table.insert(trail, string.format("%.1f (%.1f, %.1f) %s", world.now, fx, fz, causeOf(world, a)))
			if mx * mx + mz * mz > WallAudit.JUMP * WallAudit.JUMP then
				report.jumps += 1
			elseif mx * mx + mz * mz > 1e-8 then
				report.steps += 1
				local part = WallAudit.crossing(town, p[1], p[2], p[3], fx, fy, fz)
				if part then
					note(report, {
						t = world.now,
						id = a.id,
						post = a.post or a.species,
						cause = causeOf(world, a),
						part = part.path,
						ax = p[1],
						az = p[3],
						bx = fx,
						bz = fz,
						y = fy,
						trail = table.clone(trail),
					})
				elseif opts.soft then
					local soft = WallAudit.softCrossing(town, p[1], p[2], p[3], fx, fy, fz)
					if soft then
						local key = if isTree(soft) then "tree" else soft.name
						report.soft[key] = (report.soft[key] or 0) + 1
					end
					local clip = WallAudit.shoulderCrossing(town, p[1], p[2], p[3], fx, fy, fz)
					if clip then
						local cause = causeOf(world, a)
						report.shoulder[cause] = (report.shoulder[cause] or 0) + 1
						local list = report.shoulderExamples[cause]
						if list == nil then
							list = {}
							report.shoulderExamples[cause] = list
						end
						if #list < 3 then
							table.insert(list, {
								t = world.now,
								id = a.id,
								post = a.post or a.species,
								cause = cause,
								part = clip.path,
								ax = p[1],
								az = p[3],
								bx = fx,
								bz = fz,
								y = fy,
							})
						end
					end
				end
			end
			-- standing because no way was found (a brain's leg waiting out a failed search)
			local brain = world.brains[a.id] :: any
			local leg = brain and brain.leg
			if a.species == "human" and leg and leg.points == nil and leg.misses > 0 and a.intent.mode == "stand" then
				local run = (stuckRun[a.id] or 0) + dt
				stuckRun[a.id] = run
				local w = stuckWorst[a.id]
				if w == nil or run > w[1] then
					stuckWorst[a.id] = { run, fx, fz }
				end
			else
				stuckRun[a.id] = 0
			end
			local inPart = WallAudit.inside(town, fx, fy, fz)
			if inPart then
				local cause = causeOf(world, a)
				report.inside[cause] = (report.inside[cause] or 0) + 1
				local list = report.insideExamples[cause]
				if list == nil then
					list = {}
					report.insideExamples[cause] = list
				end
				if #list < 3 then
					table.insert(list, {
						t = world.now,
						id = a.id,
						post = a.post or a.species,
						cause = cause,
						part = inPart.path,
						ax = p[1],
						az = p[3],
						bx = fx,
						bz = fz,
						y = fy,
					})
				end
			end
			p[1], p[2], p[3] = fx, fy, fz
		end
	end
	local stats = svc:stats()
	for k, v in stats do
		report.events[k] = v
	end
	if combat then
		for k, v in combat:stats() do
			report.events["duel_" .. k] = v
		end
	end
	report.events.brainWays = ways
	report.events.brainWaysOver4ms = slow
	report.events.brainWaysNone = none
	report.events.brainWayWorstMs = math.floor(worstMs * 10 + 0.5) / 10
	report.events.brainWayWorstStepMs = math.floor(worstStepMs * 10 + 0.5) / 10
	-- bodies that stood for want of a way: how many stood 60 s or more at a stretch, and the longest
	local over, longest = 0, 0
	report.stuck = {}
	for id, w in stuckWorst do
		longest = math.max(longest, w[1])
		if w[1] >= 60 then
			over += 1
			if #report.stuck < 8 then
				local a = world.actorsById[id]
				table.insert(report.stuck, string.format("#%d %s %.0f s at (%.0f, %.0f)", id, a.post, w[1], w[2], w[3]))
			end
		end
	end
	report.events.noWayStand60s = over
	report.events.noWayStandLongest = math.floor(longest)
	return report
end

-- the yard dogs walking their yards (day: wandering; night: to the house and lying down)
function WallAudit.dogs(town: Town, minutes: number, night: boolean): Report
	local report = newReport()
	local dt = 0.1
	local dogs = {}
	for i, y in YardDogs.YARDS do
		table.insert(dogs, YardDogs.newDog(y, i))
	end
	local sense = {
		night = night,
		squirrels = function(): { any }
			return {}
		end,
	}
	local now = 0
	for _ = 1, math.floor(minutes * 60 / dt) do
		now += dt
		for _, d in dogs do
			local ax, az = d.x, d.z
			YardDogs.think(d, now, sense :: any)
			YardDogs.move(d, dt)
			local g0, g1 = Height.at(ax, az), Height.at(d.x, d.z)
			report.steps += 1
			-- a dog is a foot and a half tall: tested at its back, not a person's waist
			for _, w in town.worlds do
				local t, part = w.raycast(ax, g0 + 1, az, d.x - ax, g1 - g0, d.z - az, wall)
				if t and part then
					note(report, {
						t = now,
						id = d.index,
						post = "dog",
						cause = `Dog:{d.mode} ({d.yard.id})`,
						part = part.path,
						ax = ax,
						az = az,
						bx = d.x,
						bz = d.z,
						y = g1,
					})
					break
				end
			end
		end
	end
	return report
end

-- the report as lines (worst causes first)
function WallAudit.format(report: Report): string
	local lines = {
		`{report.steps} steps tested, {report.crossings} wall crossings, {report.jumps} placements`,
	}
	local causes = {}
	for c, n in report.byCause do
		table.insert(causes, { c, n })
	end
	table.sort(causes, function(a, b)
		return a[2] > b[2]
	end)
	for _, c in causes do
		table.insert(lines, `  {c[2]}  {c[1]}`)
		for _, e in report.examples[c[1]] or {} do
			table.insert(
				lines,
				string.format(
					"      t=%.1f #%d %s %s (%.1f, %.1f) -> (%.1f, %.1f) y %.1f",
					e.t,
					e.id,
					e.post,
					e.part,
					e.ax,
					e.az,
					e.bx,
					e.bz,
					e.y
				)
			)
			if WallAudit.TRAILS then
				for _, line in e.trail or {} do
					table.insert(lines, "          " .. line)
				end
			end
		end
	end
	local parts = {}
	for p, n in report.byPart do
		table.insert(parts, { p, n })
	end
	table.sort(parts, function(a, b)
		return a[2] > b[2]
	end)
	if #parts > 0 then
		table.insert(lines, "  by part:")
		for i, p in parts do
			if i > 25 then
				break
			end
			table.insert(lines, `    {p[2]}  {p[1]}`)
		end
	end
	local inside = {}
	for c, n in report.inside do
		table.insert(inside, { c, n })
	end
	table.sort(inside, function(a, b)
		return a[2] > b[2]
	end)
	if #inside > 0 then
		table.insert(lines, "  body-steps with the waist in a wall:")
		for _, c in inside do
			table.insert(lines, `    {c[2]}  {c[1]}`)
			for _, e in report.insideExamples[c[1]] or {} do
				table.insert(lines, string.format("      #%d %s %s at (%.1f, %.1f)", e.id, e.post, e.part, e.bx, e.bz))
			end
		end
	end
	local shoulder = {}
	for c, n in report.shoulder or {} do
		table.insert(shoulder, { c, n })
	end
	table.sort(shoulder, function(a, b)
		return a[2] > b[2]
	end)
	if #shoulder > 0 then
		table.insert(lines, `  shoulder clips (centre line clear, {WallAudit.SHOULDER} studs to a side not):`)
		for _, c in shoulder do
			table.insert(lines, `    {c[2]}  {c[1]}`)
			for _, e in (report.shoulderExamples or {})[c[1]] or {} do
				table.insert(
					lines,
					string.format(
						"      #%d %s %s (%.1f, %.1f) -> (%.1f, %.1f)",
						e.id,
						e.post,
						e.part,
						e.ax,
						e.az,
						e.bx,
						e.bz
					)
				)
			end
		end
	end
	local soft = {}
	for k, n in report.soft or {} do
		table.insert(soft, `{k}={n}`)
	end
	if #soft > 0 then
		table.sort(soft)
		table.insert(lines, "  steps through trees and props: " .. table.concat(soft, " "))
	end
	if report.stuck and #report.stuck > 0 then
		table.insert(lines, "  stood 60 s+ for want of a way: " .. table.concat(report.stuck, "; "))
	end
	local ev = {}
	for k, v in report.events do
		table.insert(ev, `{k}={v}`)
	end
	table.sort(ev)
	table.insert(lines, "  " .. table.concat(ev, " "))
	return table.concat(lines, "\n")
end

return WallAudit
