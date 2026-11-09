--!strict
-- ServerScriptService.Server.Paintball.Projectiles
-- Server-simulated paintballs with lag-compensated hit registration (D29; spike S18). Each ball flies
-- analytically (Shared/Paintball/Ballistics) and is stepped every 60 Hz frame against the arena's
-- boxes and against every opposing body's capsule *as it was `rewind` seconds ago*, read from that
-- body's pose history: the server judges the shot in the shooter's own timeframe (rewind = the
-- shooter's estimated RTT plus the client's interpolation delay, clamped to maxRewindSecs). The
-- first contact along the step wins; a body hit or a wall hit leaves a splat record.
-- The pose source is injectable (`sampler`) so the S18 harness can fly the same ball through the
-- shooter's exact view (ground truth) or with no rewind (the naive server) for comparison.
-- Interface: new(boxes, splats?, sampler?) -> Sim; fire(sim, ...) -> Ball; step(sim, now, dt, targets)

local Import = require("../Import")
local Config = Import.shared("Paintball/Config") :: typeof(require("../../shared/Paintball/Config"))
local Ballistics = Import.shared("Paintball/Ballistics") :: typeof(require("../../shared/Paintball/Ballistics"))
local PoseHistory = require("./PoseHistory")
local Splats = require("./Splats")

export type Target = { id: number, team: number, history: PoseHistory.History }
export type Sampler = (target: Target, t: number) -> (number, number, number)
export type Ball = {
	id: number,
	shooter: number,
	team: number,
	ox: number,
	oy: number,
	oz: number,
	vx: number,
	vy: number,
	vz: number,
	rewind: number,
	age: number,
	done: boolean,
	hitBody: number, -- 0 = no body (wall, floor or expired)
	hx: number,
	hy: number,
	hz: number,
}
export type Sim = {
	boxes: { number }, -- flat: minX, minY, minZ, maxX, maxY, maxZ per box
	splats: Splats.Pool?,
	sampler: Sampler,
	balls: { Ball },
	nextId: number,
	stats: { fired: number, bodyHits: number, wallHits: number, expired: number, rewindClamped: number },
}

local Projectiles = {}

local function historySampler(target: Target, t: number): (number, number, number)
	return PoseHistory.sample(target.history, t)
end

function Projectiles.new(boxes: { number }, splats: Splats.Pool?, sampler: Sampler?): Sim
	return {
		boxes = boxes,
		splats = splats,
		sampler = sampler or historySampler,
		balls = {},
		nextId = 0,
		stats = { fired = 0, bodyHits = 0, wallHits = 0, expired = 0, rewindClamped = 0 },
	}
end

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
	rewind: number
): Ball
	sim.nextId += 1
	local r = rewind
	if r > Config.maxRewindSecs then
		r = Config.maxRewindSecs
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
		age = 0,
		done = false,
		hitBody = 0,
		hx = ox,
		hy = oy,
		hz = oz,
	}
	table.insert(sim.balls, ball)
	sim.stats.fired += 1
	return ball
end

-- Advance every live ball by dt; `now` is the server time at the end of this frame. Finished balls
-- are removed from sim.balls (callers that need the verdict keep their own reference).
function Projectiles.step(sim: Sim, now: number, dt: number, targets: { Target })
	local g, ttl = Config.projectile.drop, Config.projectile.ttl
	local body = Config.body
	local reach = body.radius + Config.projectile.radius
	local boxes = sim.boxes
	local nBoxes = #boxes
	local sampler = sim.sampler
	local balls = sim.balls
	local i = 1
	while i <= #balls do
		local b = balls[i]
		local t0 = b.age
		local t1 = math.min(t0 + dt, ttl)
		local p0x, p0y, p0z = Ballistics.position(b.ox, b.oy, b.oz, b.vx, b.vy, b.vz, g, t0)
		local p1x, p1y, p1z = Ballistics.position(b.ox, b.oy, b.oz, b.vx, b.vy, b.vz, g, t1)
		local best, bnx, bny, bnz = 2, 0, 0, 0
		local hitId = 0
		for k = 1, nBoxes, 6 do
			local s, nx, ny, nz = Ballistics.segmentBox(
				p0x,
				p0y,
				p0z,
				p1x,
				p1y,
				p1z,
				boxes[k],
				boxes[k + 1],
				boxes[k + 2],
				boxes[k + 3],
				boxes[k + 4],
				boxes[k + 5]
			)
			if s ~= nil and s < best then
				best, bnx, bny, bnz = s, nx, ny, nz
			end
		end
		-- bodies as they were `rewind` seconds before this frame's end
		local tq = now - b.rewind
		local loX, hiX = math.min(p0x, p1x) - reach, math.max(p0x, p1x) + reach
		local loZ, hiZ = math.min(p0z, p1z) - reach, math.max(p0z, p1z) + reach
		for _, target in targets do
			if target.team == b.team then
				continue
			end
			local x, y, z = sampler(target, tq)
			if x < loX or x > hiX or z < loZ or z > hiZ then
				continue
			end
			local s = Ballistics.segmentCapsule(p0x, p0y, p0z, p1x, p1y, p1z, x, y + body.low, y + body.high, z, reach)
			if s ~= nil and s < best then
				best, hitId = s, target.id
				bnx, bny, bnz = 0, 0, 0
			end
		end
		b.age = t1
		if best <= 1 then
			b.done = true
			b.hitBody = hitId
			b.hx, b.hy, b.hz = p0x + (p1x - p0x) * best, p0y + (p1y - p0y) * best, p0z + (p1z - p0z) * best
			if hitId ~= 0 then
				sim.stats.bodyHits += 1
			else
				sim.stats.wallHits += 1
			end
			local pool = sim.splats
			if pool then
				Splats.add(pool, b.hx, b.hy, b.hz, bnx, bny, bnz, b.team, hitId)
			end
		elseif t1 >= ttl then
			b.done = true
			sim.stats.expired += 1
		end
		if b.done then
			balls[i] = balls[#balls]
			balls[#balls] = nil
		else
			i += 1
		end
	end
end

return Projectiles
