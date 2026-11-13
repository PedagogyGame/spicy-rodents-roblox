--!strict
-- ServerScriptService.Server.Paintball.Projectiles
-- Server-simulated paintballs with lag-compensated hit registration (D29; spike S18; checklist PB-1,
-- PB-3). Each ball flies analytically (Shared/Paintball/Ballistics) and is stepped against the building
-- and against every opposing body AS IT WAS `rewind` SECONDS BEFORE, read from that body's pose history
-- (position and crouch): the server judges the shot in the shooter's own timeframe.
-- THE TEST IS THE CONTRACT'S (Shared/Minigames/Paintball/Hit): a ball is its centre line; the building
-- is asked through one `sweep` function (the arena's own: Arena.sweep; nobody scans a box list here);
-- a body is hit where the line ENTERS its capsule at the crouch fraction it had then, and only if no
-- wall stands between that point and the body's middle; the first thing along the step wins and a tie
-- goes to the wall, then to the lower slot id (the order of `targets`). Nothing is added for the
-- ball's radius, so a body wholly behind a rail cannot be tagged over it.
-- TWO WAYS TO BUILD ONE
--   forArena(arena, feel)   a match: the arena's sweep, the match's drop (Contract.Feel), the ttl of
--                           Contract.Rules, rewinds clamped to Clock.MAX_REWIND, and the early reject
--                           below. Balls carry their birth time (the clamped fire time) and are flown
--                           to `now - born`, in steps no longer than a server tick, each against the
--                           bodies of its own moment: so advance() can fly a ball that is already
--                           `late` seconds old on the shooter's screen forward at once (Clock.stamp).
--   new(boxes, splats?, sampler?)   the S18 harness's: a box list (through Arena.sweepBoxes), the S18
--                           numbers of Shared/Paintball/Config, one step of dt per call.
-- WHO MAY BE HIT is the caller's to say, per target: `live = false` (off, tagged out, protected) and a
-- target whose history is empty are passed over; `room` (its own team's spawn room) passes it over
-- while its REWOUND feet are inside. THE EARLY REJECT (Contract.COST): a target that carries its newest
-- pose (x, y, z) is passed over without its history being sampled when that pose is further from the
-- box round the ball's step than a body could have come in the time a ball may be judged back
-- (sim.reject sideways, two storeys up or down).
-- DETERMINISM: balls are stepped in the order they were born and targets in the order given, and a
-- ball that ends is reported at once (onEnd), before the next ball is stepped: the caller marks a
-- tagged body `live = false` there, so of two balls that reach one body in one tick the older tags it
-- and the younger flies on, every time.
-- The pose source is injectable (`sampler`) so the S18 harness can fly the same ball through the
-- shooter's exact view (ground truth) or with no rewind (the naive server) for comparison.
-- Interface: new(boxes, splats?, sampler?) -> Sim; forArena(arena, feel, sampler?) -> Sim; fire(sim,
--   shooter, team, ox, oy, oz, vx, vy, vz, rewind, born?) -> Ball; step(sim, now, dt, targets, onEnd?);
--   advance(sim, ball, now, targets, onEnd?); clear(sim); SUBSTEP; types Target, Sampler, Ball, Sim

local Import = require("../Import")
local Config = Import.shared("Paintball/Config") :: typeof(require("../../shared/Paintball/Config"))
local Ballistics = Import.shared("Paintball/Ballistics") :: typeof(require("../../shared/Paintball/Ballistics"))
local ArenaModule: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Arena)) =
	Import.shared("Minigames/Paintball/Arena")
local Body: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Body)) =
	Import.shared("Minigames/Paintball/Body")
local Clock: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Clock)) =
	Import.shared("Minigames/Paintball/Clock")
local Contract: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Contract)) =
	Import.shared("Minigames/Paintball/Contract")
local Hit: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Hit)) =
	Import.shared("Minigames/Paintball/Hit")
local PoseHistory = require("./PoseHistory")
local Splats = require("./Splats")

type Arena = typeof(ArenaModule.T.Arena)
type Room = typeof(ArenaModule.T.Room)
type Feel = typeof(Contract.T.Feel)
type Sweep = (
	x0: number,
	y0: number,
	z0: number,
	x1: number,
	y1: number,
	z1: number
) -> (number?, number, number, number, number)

export type Target = {
	id: number,
	team: number,
	history: PoseHistory.History,
	live: boolean?, -- false: cannot be hit now (off, out, protected). nil counts as true
	room: Room?, -- its own team's spawn room: passed over while its rewound feet are inside
	x: number?, -- its newest pose, for the early reject (all three or none)
	y: number?,
	z: number?,
}
-- (x, y, z, crouch fraction; a sampler that returns no fourth value means standing)
export type Sampler = (target: Target, t: number) -> (number, number, number, number?)
export type Ball = {
	id: number, -- 1..65535, then round again (the wire's u16)
	shooter: number,
	team: number,
	ox: number,
	oy: number,
	oz: number,
	vx: number,
	vy: number,
	vz: number,
	rewind: number,
	born: number?, -- its birth on the shared clock (a match's balls); nil: stepped by dt (the S18 harness)
	age: number,
	done: boolean,
	hitBody: number, -- 0 = no body (wall, floor or expired)
	hitWall: boolean, -- it ended on the building
	hx: number, -- where it ended: on a body, the ENTRY point
	hy: number,
	hz: number,
	nx: number, -- the face normal of the box it ended on (zero on a body)
	ny: number,
	nz: number,
	bx: number, -- the feet of the body it ended on, where that body was judged to be
	by: number,
	bz: number,
}
export type Sim = {
	sweep: Sweep,
	drop: number,
	ttl: number,
	maxRewind: number,
	reject: number?, -- the early reject's sideways reach; nil = none
	splats: Splats.Pool?,
	sampler: Sampler,
	balls: { Ball }, -- in the order they were born
	nextId: number,
	stats: {
		fired: number,
		bodyHits: number,
		wallHits: number,
		expired: number,
		rewindClamped: number,
		sweeps: number, -- the balls' own steps asked of the building
		samples: number, -- pose histories sampled
		rejected: number, -- targets passed over by their newest pose alone
	},
}
export type OnEnd = (ball: Ball) -> ()

local Projectiles = {}

-- The longest piece of flight judged against one moment of the bodies: a server tick.
Projectiles.SUBSTEP = 1 / Clock.TICK_HZ

local MAX_ID = 65535
local REJECT_Y = 2 * ArenaModule.FLOOR_HEIGHT
local RADIUS = Body.RADIUS
local inRoom = ArenaModule.inRoom

local function historySampler(target: Target, t: number): (number, number, number, number?)
	return PoseHistory.sample(target.history, t)
end

local function build(sweep: Sweep, drop: number, ttl: number, maxRewind: number, sampler: Sampler?): Sim
	return {
		sweep = sweep,
		drop = drop,
		ttl = ttl,
		maxRewind = maxRewind,
		reject = nil,
		splats = nil,
		sampler = sampler or historySampler,
		balls = {},
		nextId = 0,
		stats = {
			fired = 0,
			bodyHits = 0,
			wallHits = 0,
			expired = 0,
			rewindClamped = 0,
			sweeps = 0,
			samples = 0,
			rejected = 0,
		},
	}
end

-- The S18 harness's sim: a flat box list, the S18 numbers.
function Projectiles.new(boxes: { number }, splats: Splats.Pool?, sampler: Sampler?): Sim
	local function sweep(
		x0: number,
		y0: number,
		z0: number,
		x1: number,
		y1: number,
		z1: number
	): (number?, number, number, number, number)
		return ArenaModule.sweepBoxes(boxes, x0, y0, z0, x1, y1, z1)
	end
	local sim = build(sweep, Config.projectile.drop, Config.projectile.ttl, Config.maxRewindSecs, sampler)
	sim.splats = splats
	return sim
end

-- A match's sim: the arena's own ball test and the match's feel.
function Projectiles.forArena(arena: Arena, feel: Feel, sampler: Sampler?): Sim
	local sim = build(arena.sweep, feel.ballDrop, Contract.Rules.ballTtl, Clock.MAX_REWIND, sampler)
	sim.reject = RADIUS
		+ Body.speed(0, true, feel) * Contract.TRUST.speedTolerance * (Clock.MAX_REWIND + Clock.MAX_LATE)
	return sim
end

-- A ball leaves (ox, oy, oz) with velocity (vx, vy, vz), judged `rewind` seconds back (clamped to the
-- sim's bound). `born` is its birth on the shared clock: step and advance then fly it to `now - born`.
function Projectiles.fire(
	sim: Sim,
	shooter: number,
	team: number,
	ox: number,
	oy: number,
	oz: number,
	vx: number,
	vy: number,
	vz: number,
	rewind: number,
	born: number?
): Ball
	sim.nextId = sim.nextId % MAX_ID + 1
	local r = rewind
	if r > sim.maxRewind then
		r = sim.maxRewind
		sim.stats.rewindClamped += 1
	elseif r < 0 then
		r = 0
	end
	local ball: Ball = {
		id = sim.nextId,
		shooter = shooter,
		team = team,
		ox = ox,
		oy = oy,
		oz = oz,
		vx = vx,
		vy = vy,
		vz = vz,
		rewind = r,
		born = born,
		age = 0,
		done = false,
		hitBody = 0,
		hitWall = false,
		hx = ox,
		hy = oy,
		hz = oz,
		nx = 0,
		ny = 0,
		nz = 0,
		bx = 0,
		by = 0,
		bz = 0,
	}
	table.insert(sim.balls, ball)
	sim.stats.fired += 1
	return ball
end

-- Fly one ball until its age is `toAge` (the shared clock then reads `now`), in pieces no longer than
-- SUBSTEP, each against the building and the bodies of its own moment.
local function fly(sim: Sim, b: Ball, now: number, toAge: number, targets: { Target })
	local g, ttl = sim.drop, sim.ttl
	local sweep, sampler, reject = sim.sweep, sim.sampler, sim.reject
	local stats = sim.stats
	local goal = math.min(toAge, ttl)
	local SUB = Projectiles.SUBSTEP
	while not b.done do
		local t0 = b.age
		local t1 = goal
		if t1 <= t0 then
			if t0 >= ttl then
				b.done = true
				stats.expired += 1
			end
			return
		end
		if t1 - t0 > SUB + 1e-9 then
			t1 = t0 + SUB
		end
		local p0x, p0y, p0z = Ballistics.position(b.ox, b.oy, b.oz, b.vx, b.vy, b.vz, g, t0)
		local p1x, p1y, p1z = Ballistics.position(b.ox, b.oy, b.oz, b.vx, b.vy, b.vz, g, t1)
		local ws, wnx, wny, wnz = sweep(p0x, p0y, p0z, p1x, p1y, p1z)
		stats.sweeps += 1
		local best = ws or 2
		local hitId = 0
		local ex, ey, ez = 0, 0, 0
		local fx, fy, fz = 0, 0, 0
		-- the bodies as they were `rewind` before the moment this piece ends
		local tq = now - (toAge - t1) - b.rewind
		local loX, hiX = math.min(p0x, p1x), math.max(p0x, p1x)
		local loY, hiY = math.min(p0y, p1y), math.max(p0y, p1y)
		local loZ, hiZ = math.min(p0z, p1z), math.max(p0z, p1z)
		local team = b.team
		for _, target in targets do
			if target.team == team or target.live == false or target.history.count == 0 then
				continue
			end
			local nx = target.x
			if reject ~= nil and nx ~= nil then
				local ny, nz = target.y :: number, target.z :: number
				if
					nx < loX - reject
					or nx > hiX + reject
					or nz < loZ - reject
					or nz > hiZ + reject
					or ny < loY - REJECT_Y
					or ny > hiY + REJECT_Y
				then
					stats.rejected += 1
					continue
				end
			end
			local x, y, z, c = sampler(target, tq)
			stats.samples += 1
			if x < loX - RADIUS or x > hiX + RADIUS or z < loZ - RADIUS or z > hiZ + RADIUS then
				continue
			end
			local room = target.room
			if room ~= nil and inRoom(room, x, y + 0.1, z) then
				continue
			end
			local s, hx, hy, hz = Hit.body(sweep, p0x, p0y, p0z, p1x, p1y, p1z, x, y, z, c or 0)
			if s ~= nil and s < best then
				best, hitId = s, target.id
				ex, ey, ez = hx, hy, hz
				fx, fy, fz = x, y, z
			end
		end
		b.age = t1
		if best <= 1 then
			b.done = true
			b.hitBody = hitId
			if hitId ~= 0 then
				b.hx, b.hy, b.hz = ex, ey, ez
				b.bx, b.by, b.bz = fx, fy, fz
				stats.bodyHits += 1
			else
				b.hitWall = true
				b.hx, b.hy, b.hz = p0x + (p1x - p0x) * best, p0y + (p1y - p0y) * best, p0z + (p1z - p0z) * best
				b.nx, b.ny, b.nz = wnx, wny, wnz
				stats.wallHits += 1
			end
			local pool = sim.splats
			if pool then
				Splats.add(pool, b.hx, b.hy, b.hz, b.nx, b.ny, b.nz, b.team, hitId)
			end
		elseif t1 >= ttl then
			b.done = true
			stats.expired += 1
		end
	end
end

-- Advance every live ball; `now` is the server time at the end of this frame. A ball with a birth time
-- is flown to `now - born`; one without is flown `dt` further. Finished balls leave sim.balls (in
-- order) and are handed to onEnd the moment they end (callers that need the verdict later keep their
-- own reference).
function Projectiles.step(sim: Sim, now: number, dt: number, targets: { Target }, onEnd: OnEnd?)
	local balls = sim.balls
	local n = #balls
	local kept = 0
	for i = 1, n do
		local b = balls[i]
		local born = b.born
		fly(sim, b, now, if born ~= nil then now - born else b.age + dt, targets)
		if b.done then
			if onEnd then
				onEnd(b)
			end
		else
			kept += 1
			balls[kept] = b
		end
	end
	for i = n, kept + 1, -1 do
		balls[i] = nil
	end
end

-- Fly ONE ball (just fired, with a birth time) up to `now` at once: the part of its flight the
-- shooter has already seen. Ends and reports it like step.
function Projectiles.advance(sim: Sim, ball: Ball, now: number, targets: { Target }, onEnd: OnEnd?)
	local born = ball.born
	if ball.done or born == nil then
		return
	end
	fly(sim, ball, now, now - born, targets)
	if ball.done then
		local at = table.find(sim.balls, ball)
		if at then
			table.remove(sim.balls, at)
		end
		if onEnd then
			onEnd(ball)
		end
	end
end

-- Every ball in flight is gone (a new match).
function Projectiles.clear(sim: Sim)
	table.clear(sim.balls)
end

return Projectiles
