--!strict
-- tests/cheat/Harness: the S3 network simulation and cheat harness (BUILD_PLAN §4.3 S3, §6.2
-- MoveValidator row). Clients run SquirrelMotor at 60 Hz and send their serialized state every
-- `packetEvery` ticks through a lossy, jittery link (base latency + uniform jitter, random loss,
-- reordering by arrival time); the server drains arrivals in arrival order into MoveValidator.
--   Harness.honest(opts)        N scripted squirrels (tests/cheat/Driver) for M simulated minutes ->
--                               violation counts (must be 0), events, perf
--   Harness.cheat(kind, opts)   episodes of one cheat with honest warm-up and follow-through ->
--                               detection rate, time to flag, false positives in honest segments
-- Cheats (each an edit of the client's own motor state, what a modified client can do):
--   speed2        the motor runs twice per tick with an honest clock (a speed hack while sprinting)
--   speed2_clock  the motor runs twice per tick and the clock runs twice as fast (a time hack)
--   teleport30    the body jumps 30 studs sideways in one tick
--   leap20        a 20-stud "leap": variant A snaps onto a rail 20 st away without the arc (a grab
--                 far beyond 3.4 u), variant B launches at twice the leap velocity
--   wallpass      the client ignores wall colliders and sprints through a house box
--   hop           on a rail, a transfer onto a route that is not adjacent (no fork, sibling, end
--                 link or 1.7 u sample pair)
-- Pure Lune; also runnable inside the engine task (tests/engine/RailSpike) for the perf number.
local Driver = require("./Driver")
local Rng = require("./Rng")
local TestWorld = require("./TestWorld")
local Motion = require("@shared/Routes/Motion")
local Registry = require("@shared/Routes/Registry")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local MoveValidator = require("@server/Movement/MoveValidator")
local Units = require("@shared/Config/Units")

local Harness = {}

export type LinkOptions = {
	packetEvery: number?, -- ticks between packets (default 2 = 30 Hz)
	baseLatency: number?, -- seconds (default 0.08)
	jitter: number?, -- seconds of uniform jitter on top (default 0.15)
	loss: number?, -- packet loss probability (default 0.02)
}

export type HonestOptions = LinkOptions & {
	world: TestWorld.World,
	squirrels: number,
	minutes: number,
	seed: number,
	center: { x: number, z: number }?, -- studs; targets within radius of it
	radius: number?,
}

export type HonestResult = {
	ticks: number,
	packets: number,
	accepted: number,
	dropped: number,
	resyncs: number,
	violations: number,
	violationCodes: { [string]: number },
	samples: { string }, -- first few violation details for the report
	events: { [string]: number },
	validatorSeconds: number,
	validatorPerPacketMs: number,
	motorSeconds: number,
	flagged: number,
}

type Packet = { seq: number, snapshot: SquirrelMotor.Snapshot, sendTime: number, arrival: number, actor: number }

local TICK = 1 / 60
local lastHop = "" -- the hop cheat's last transfer, for the notes

local function link(opts: LinkOptions): (number, number, number, number)
	return opts.packetEvery or 2, opts.baseLatency or 0.08, opts.jitter or 0.15, opts.loss or 0.02
end

-- A tiny arrival queue: packets sorted by arrival time (insertion keeps it sorted; sizes stay small).
local function enqueue(queue: { Packet }, p: Packet)
	local i = #queue
	while i >= 1 and queue[i].arrival > p.arrival do
		i -= 1
	end
	table.insert(queue, i + 1, p)
end

function Harness.honest(opts: HonestOptions): HonestResult
	local world = opts.world
	local rng = Rng.new(opts.seed)
	local packetEvery, baseLatency, jitter, loss = link(opts)
	local center = opts.center or { x = 0, z = 0 }
	local targets = Driver.targetsAround(world, center.x, center.z, opts.radius or Units.st(95))
	assert(#targets > 0, "no trunks near the start")
	local validator = MoveValidator.new(world)

	local states: { SquirrelMotor.State } = {}
	local drivers: { Driver.Driver } = {}
	local lastEvents: { { SquirrelMotor.Event } } = {}
	local seqs: { number } = {}
	for i = 1, opts.squirrels do
		local trunk = targets[math.floor(rng.next() * #targets) + 1]
		local foot = world.registry:foot(trunk)
		local angle = rng.next() * math.pi * 2
		local s = SquirrelMotor.new(
			foot.x + math.sin(angle) * Units.st(6),
			world.groundHeight,
			foot.z + math.cos(angle) * Units.st(6)
		)
		states[i] = s
		drivers[i] = Driver.new(world, rng, targets)
		lastEvents[i] = {}
		seqs[i] = 0
	end

	local queue: { Packet } = {}
	local result: HonestResult = {
		ticks = 0,
		packets = 0,
		accepted = 0,
		dropped = 0,
		resyncs = 0,
		violations = 0,
		violationCodes = {},
		samples = {},
		events = {},
		validatorSeconds = 0,
		validatorPerPacketMs = 0,
		motorSeconds = 0,
		flagged = 0,
	}
	local totalTicks = math.floor(opts.minutes * 60 / TICK + 0.5)
	local now = 0
	for tick = 1, totalTicks do
		local motorStart = os.clock()
		for i, s in states do
			local inp = drivers[i]:input(s, lastEvents[i], TICK)
			local _, events = SquirrelMotor.step(s, inp, TICK, world)
			lastEvents[i] = events
			for _, e in events do
				result.events[e.kind] = (result.events[e.kind] or 0) + 1
			end
			if tick % packetEvery == 0 and rng.next() >= loss then
				seqs[i] += 1
				enqueue(queue, {
					seq = seqs[i],
					snapshot = SquirrelMotor.serialize(s),
					sendTime = now,
					arrival = now + baseLatency + rng.next() * jitter,
					actor = i,
				})
				result.packets += 1
			end
		end
		result.motorSeconds += os.clock() - motorStart
		now += TICK
		-- server: deliver everything that has arrived
		local serverStart = os.clock()
		while #queue > 0 and queue[1].arrival <= now do
			local p = table.remove(queue, 1) :: Packet
			local verdict = validator:accept(p.actor, { seq = p.seq, snapshot = p.snapshot }, p.arrival)
			if verdict.accepted then
				result.accepted += 1
			else
				result.dropped += 1
			end
			if verdict.resync then
				result.resyncs += 1
			end
			for _, v in verdict.violations do
				result.violations += 1
				result.violationCodes[v.code] = (result.violationCodes[v.code] or 0) + 1
				if #result.samples < 12 then
					table.insert(
						result.samples,
						`t={string.format("%.2f", p.sendTime)} squirrel {p.actor} {v.code}: {v.detail}`
					)
				end
			end
			if verdict.flagged then
				result.flagged += 1
			end
		end
		result.validatorSeconds += os.clock() - serverStart
	end
	result.ticks = totalTicks
	result.validatorPerPacketMs = if result.accepted > 0 then result.validatorSeconds / result.accepted * 1000 else 0
	for i, d in drivers do
		for k, v in d.log do
			result.events[`driver.{k}`] = (result.events[`driver.{k}`] or 0) + v
		end
		local _ = i
	end
	return result
end

-- Cheats ------------------------------------------------------------------------------------------------

export type CheatOptions = LinkOptions & {
	world: TestWorld.World, -- the validator's world (with wall boxes)
	episodes: number,
	seed: number,
	variant: string?,
}

export type CheatResult = {
	kind: string,
	episodes: number,
	detected: number,
	detectionRate: number,
	meanTimeToFlag: number,
	maxTimeToFlag: number,
	codes: { [string]: number },
	honestViolations: number, -- violations raised during the honest warm-up (false positives)
	honestPackets: number,
	notes: { string },
}

-- The client's own copy of the world for the wall-pass cheat: colliders ignored.
local function clientWorld(world: TestWorld.World, ignoreWalls: boolean): SquirrelMotor.World
	if not ignoreWalls then
		return world
	end
	local copy = table.clone(world) :: any
	copy.blocked = nil
	return copy :: SquirrelMotor.World
end

type Episode = {
	state: SquirrelMotor.State,
	driver: Driver.Driver?,
	warmup: number, -- seconds of honest play before the cheat
	cheatSeconds: number, -- how long the cheat stays active
	follow: number, -- honest seconds after the cheat
	tickCheat: ((
		state: SquirrelMotor.State,
		inp: SquirrelMotor.Input,
		world: SquirrelMotor.World,
		t: number,
		first: boolean
	) -> ())?,
	input: ((state: SquirrelMotor.State, t: number) -> SquirrelMotor.Input)?,
	ignoreWalls: boolean,
}

-- Find a trunk with forks near the flat core for the on-rail scenarios.
local function forkTrunk(world: TestWorld.World, rng: Rng.Rng): Registry.Route
	local list: { Registry.Route } = {}
	for _, r in world.registry:all() do
		if r.kind == "trunk" and #world.graph:forks(r.id) >= 3 then
			local foot = world.registry:foot(r)
			if math.abs(foot.x) < Units.st(100) and math.abs(foot.z) < Units.st(100) then
				table.insert(list, r)
			end
		end
	end
	return list[math.floor(rng.next() * #list) + 1]
end

-- A route that is NOT related to `route` whose nearest sample to (x, y, z) lies in (lo, hi].
local function unrelatedRouteNear(
	world: TestWorld.World,
	route: Registry.Route,
	x: number,
	y: number,
	z: number,
	lo: number,
	hi: number
): Motion.Candidate?
	local best: Motion.Candidate? = nil
	world.index:forEachNear(x, y, z, math.max(1, math.ceil(hi / world.index.cellSize)), function(id, t, sx, sy, sz)
		if id == route.id or world.graph:relation(route.id, id) ~= nil then
			return nil
		end
		local d = math.sqrt((sx - x) ^ 2 + (sy - y) ^ 2 + (sz - z) ^ 2)
		if d > lo and d <= hi and (best == nil or d < (best :: Motion.Candidate).d) then
			best = { routeId = id, t = t, d = d }
		end
		return nil
	end)
	return best
end

-- Open ground with no route sample within 10 u (the south-west corner of the v5.4 rectangle,
-- x -590..-510 u, z -570..-110 u has none) and no wall boxes: ground cheats start here.
Harness.OPEN_GROUND = { minX = -575, maxX = -545, minZ = -545, maxZ = -500 } -- HTML units

local function groundStart(world: TestWorld.World, rng: Rng.Rng): SquirrelMotor.State
	local g = Harness.OPEN_GROUND
	local x = Units.st(g.minX + rng.next() * (g.maxX - g.minX))
	local z = Units.st(g.minZ + rng.next() * (g.maxZ - g.minZ))
	return SquirrelMotor.new(x, world.groundHeight, z)
end

local function sprintInput(yaw: number): SquirrelMotor.Input
	local inp = SquirrelMotor.idleInput(yaw)
	inp.fw = 1
	inp.sprint = true
	return inp
end

-- A camera yaw whose forward points into the open ground (east or north), never into the world clamp
-- a few units west or south of the start.
local function openHeading(rng: Rng.Rng): number
	local theta = (rng.next() - 0.5) * 0.8 * math.pi -- from +x, within +-72 degrees
	local dx, dz = math.cos(theta), math.sin(theta)
	return math.atan2(-dx, -dz)
end

local function makeEpisode(kind: string, variant: string?, world: TestWorld.World, rng: Rng.Rng): Episode
	if kind == "speed2" or kind == "speed2_clock" then
		local s = groundStart(world, rng)
		local yaw = openHeading(rng)
		local timeHack = kind == "speed2_clock"
		return {
			state = s,
			driver = nil,
			warmup = 1.0,
			cheatSeconds = 1.0,
			follow = 1.0,
			ignoreWalls = false,
			input = function(_state, _t)
				return sprintInput(yaw)
			end,
			tickCheat = function(state, inp, w, _t, _first)
				-- a second motor step this tick: twice the distance (and, as a time hack, twice the clock)
				local clock = state.clock
				SquirrelMotor.step(state, inp, TICK, w)
				if not timeHack then
					state.clock = clock
				end
			end,
		}
	elseif kind == "teleport30" then
		local s = groundStart(world, rng)
		local yaw = openHeading(rng)
		return {
			state = s,
			driver = nil,
			warmup = 1.0,
			cheatSeconds = TICK,
			follow = 1.5,
			ignoreWalls = false,
			input = function(_state, _t)
				return sprintInput(yaw)
			end,
			tickCheat = function(state, _inp, _w, _t, first)
				if first then
					local a = rng.next() * math.pi * 2
					state.x += math.sin(a) * 30
					state.z += math.cos(a) * 30
				end
			end,
		}
	elseif kind == "leap20" then
		local superjump = variant == "superjump"
		local s: SquirrelMotor.State
		local yaw: number
		if superjump then
			s = groundStart(world, rng)
			yaw = openHeading(rng)
		else
			-- the snap needs a rail about 20 studs away: stand 8 u from a tree trunk's foot, facing away
			local trunk = forkTrunk(world, rng)
			local foot = world.registry:foot(trunk)
			local a = rng.next() * math.pi * 2
			s = SquirrelMotor.new(
				foot.x + math.sin(a) * Units.st(8),
				world.groundHeight,
				foot.z + math.cos(a) * Units.st(8)
			)
			yaw = math.atan2(-math.sin(a), -math.cos(a))
		end
		return {
			state = s,
			driver = nil,
			warmup = 1.0,
			cheatSeconds = TICK,
			follow = 1.5,
			ignoreWalls = false,
			input = function(_state, _t)
				local inp = SquirrelMotor.idleInput(yaw)
				inp.fw = if superjump then 1 else 0
				return inp
			end,
			tickCheat = function(state, _inp, w, _t, first)
				if not first then
					return
				end
				if superjump then
					-- twice the leap velocity: clears 20 studs more than any honest leap
					local vx, vy, vz = SquirrelMotor.jumpVelocity(state.yaw, false)
					state.vx, state.vy, state.vz = vx * 2, vy * 2, vz * 2
					state.grounded = false
					state.committedAirborne = true
				else
					-- snap onto whichever rail sample is about 20 studs away (beyond the 3.4 u grab)
					local best: Motion.Candidate? = nil
					w.index:forEachNear(state.x, state.y, state.z, 2, function(id, t, sx, sy, sz)
						local d = math.sqrt((sx - state.x) ^ 2 + (sy - state.y) ^ 2 + (sz - state.z) ^ 2)
						if
							d >= 18
							and d <= 24
							and (best == nil or math.abs(d - 20) < math.abs((best :: Motion.Candidate).d - 20))
						then
							best = { routeId = id, t = t, d = d }
						end
						return nil
					end)
					if not best then
						-- nothing that far: snap to any route 20 studs along the heading
						local nx, nz = state.x + math.sin(state.yaw) * 20, state.z + math.cos(state.yaw) * 20
						local near = w.index:nearest(nx, state.y, nz, 60)
						if near then
							best = { routeId = near.routeId, t = near.t, d = near.d }
						end
					end
					if best then
						local b = best :: Motion.Candidate
						local r = w.registry:get(b.routeId) :: Registry.Route
						local p = w.registry:pointAt(r, b.t)
						state.routeId = r.id
						state.railT = b.t
						state.railDir = 1
						state.x, state.y, state.z = p.x, p.y, p.z
						state.vx, state.vy, state.vz = 0, 0, 0
						state.grounded = false
						state.bridge = nil
					end
				end
			end,
		}
	elseif kind == "wallpass" then
		-- start 4 u west of the first box, sprint east through it
		local box = world.boxes[1]
		assert(box, "wallpass needs a wall box in the validator world")
		local z = (box.minZ + box.maxZ) / 2 + (rng.next() - 0.5) * (box.maxZ - box.minZ) * 0.5
		local s = SquirrelMotor.new(box.minX - Units.st(14), world.groundHeight, z)
		local yaw = -math.pi / 2 -- camera forward (+1, 0): east
		return {
			state = s,
			driver = nil,
			warmup = 0.5, -- the wall is about 0.9 s away at sprint acceleration
			cheatSeconds = 2.0,
			follow = 0.5,
			ignoreWalls = true,
			input = function(_state, _t)
				return sprintInput(yaw)
			end,
			tickCheat = nil,
		}
	elseif kind == "hop" then
		local trunk = forkTrunk(world, rng)
		local p = world.registry:pointAt(trunk, 0.35 + rng.next() * 0.3)
		local s = SquirrelMotor.new(p.x, p.y, p.z)
		s.routeId = trunk.id
		s.railT = 0.35
		local foot = world.registry:foot(trunk)
		s.trunkNormalX, s.trunkNormalZ = 1, 0
		-- recompute railT from the point we placed the body at
		local near = world.index:nearestOnRoute(trunk.id, p.x, p.y, p.z, Units.st(1))
		if near then
			s.railT = near.t
			local q = world.registry:pointAt(trunk, near.t)
			s.x, s.y, s.z = q.x, q.y, q.z
		end
		s.grounded = false
		local _ = foot
		return {
			state = s,
			driver = nil,
			warmup = 1.0,
			cheatSeconds = TICK,
			follow = 1.5,
			ignoreWalls = false,
			input = function(state, _t)
				local inp = SquirrelMotor.idleInput(state.yaw + math.pi)
				inp.fw = 1
				return inp
			end,
			tickCheat = function(state, _inp, w, _t, first)
				if not first or not state.routeId then
					return
				end
				local cur = w.registry:get(state.routeId :: number) :: Registry.Route
				-- the subtle hop: within the 3.15 u enter gap but past the 1.7 u transfer limit and unrelated
				local c = unrelatedRouteNear(world, cur, state.x, state.y, state.z, Units.st(1.7), Units.st(3.15))
					or unrelatedRouteNear(world, cur, state.x, state.y, state.z, Units.st(3.15), Units.st(12))
					or unrelatedRouteNear(world, cur, state.x, state.y, state.z, Units.st(12), Units.st(80))
				assert(c, "hop: no unrelated route within 80 u")
				if c then
					local r = w.registry:get(c.routeId) :: Registry.Route
					local q = w.registry:pointAt(r, c.t)
					lastHop = `{cur.id} -> {r.id} ({r.kind}) gap {string.format("%.2f", Units.u(c.d))} u`
					state.routeId = r.id
					state.railT = c.t
					state.railDir = 1
					state.x, state.y, state.z = q.x, q.y, q.z
					state.bridge = nil
					state.pendingFork = nil
				end
			end,
		}
	end
	error(`unknown cheat {kind}`)
end

function Harness.cheat(kind: string, opts: CheatOptions): CheatResult
	local world = opts.world
	local rng = Rng.new(opts.seed)
	local packetEvery, baseLatency, jitter, loss = link(opts)
	local result: CheatResult = {
		kind = kind .. (if opts.variant then `:{opts.variant}` else ""),
		episodes = opts.episodes,
		detected = 0,
		detectionRate = 0,
		meanTimeToFlag = 0,
		maxTimeToFlag = 0,
		codes = {},
		honestViolations = 0,
		honestPackets = 0,
		notes = {},
	}
	local totalTime = 0
	for ep = 1, opts.episodes do
		lastHop = ""
		local episode = makeEpisode(kind, opts.variant, world, rng)
		local motorWorld = clientWorld(world, episode.ignoreWalls)
		local validator = MoveValidator.new(world)
		local state = episode.state
		local queue: { Packet } = {}
		local now, seq = 0, 0
		local cheatStart = episode.warmup
		local cheatEnd = episode.warmup + episode.cheatSeconds
		local total = cheatEnd + episode.follow
		local firstCheatSend: number? = nil
		local flaggedAt: number? = nil
		local events: { SquirrelMotor.Event } = {}
		local tick = 0
		local first = true
		while now < total do
			tick += 1
			local inp = if episode.input
				then episode.input(state, now)
				else (episode.driver :: Driver.Driver):input(state, events, TICK)
			local _, ev = SquirrelMotor.step(state, inp, TICK, motorWorld)
			events = ev
			local cheating = now >= cheatStart and now < cheatEnd
			if cheating and episode.tickCheat then
				episode.tickCheat(state, inp, motorWorld, now, first)
				first = false
			end
			if tick % packetEvery == 0 and rng.next() >= loss then
				seq += 1
				local p: Packet = {
					seq = seq,
					snapshot = SquirrelMotor.serialize(state),
					sendTime = now,
					arrival = now + baseLatency + rng.next() * jitter,
					actor = 1,
				}
				enqueue(queue, p)
				-- the first packet carrying the cheat (its effect persists in the state after the tick)
				if now >= cheatStart and not firstCheatSend then
					firstCheatSend = now
				end
			end
			now += TICK
			while #queue > 0 and queue[1].arrival <= now do
				local p = table.remove(queue, 1) :: Packet
				local verdict = validator:accept(1, { seq = p.seq, snapshot = p.snapshot }, p.arrival)
				if p.sendTime < cheatStart then
					result.honestPackets += 1
					result.honestViolations += #verdict.violations
					for _, v in verdict.violations do
						if #result.notes < 10 then
							table.insert(result.notes, `episode {ep} honest {v.code}: {v.detail}`)
						end
					end
				else
					for _, v in verdict.violations do
						result.codes[v.code] = (result.codes[v.code] or 0) + 1
					end
					if verdict.flagged and not flaggedAt then
						flaggedAt = p.arrival
					end
				end
			end
		end
		if flaggedAt and firstCheatSend then
			local ttf = flaggedAt - firstCheatSend
			if ttf <= 1.0 then
				result.detected += 1
				totalTime += ttf
				result.maxTimeToFlag = math.max(result.maxTimeToFlag, ttf)
			elseif #result.notes < 10 then
				table.insert(result.notes, `episode {ep}: flagged late ({ttf} s)`)
			end
		elseif #result.notes < 10 then
			table.insert(result.notes, `episode {ep}: not flagged {lastHop}`)
		end
	end
	result.detectionRate = result.detected / math.max(1, opts.episodes)
	result.meanTimeToFlag = if result.detected > 0 then totalTime / result.detected else 0
	return result
end

-- perf(world, squirrels, ticks): the validator alone on a stream of honest packets, mean ms per
-- squirrel per tick (one packet per squirrel per tick, no link).
function Harness.perf(
	world: TestWorld.World,
	squirrels: number,
	ticks: number,
	seed: number
): { perTickMs: number, perPacketUs: number, packets: number }
	local rng = Rng.new(seed)
	local targets = Driver.targetsAround(world, 0, 0, Units.st(95))
	local validator = MoveValidator.new(world)
	local states: { SquirrelMotor.State } = {}
	local drivers: { Driver.Driver } = {}
	local lastEvents: { { SquirrelMotor.Event } } = {}
	for i = 1, squirrels do
		local trunk = targets[math.floor(rng.next() * #targets) + 1]
		local foot = world.registry:foot(trunk)
		states[i] = SquirrelMotor.new(foot.x + Units.st(4), world.groundHeight, foot.z)
		drivers[i] = Driver.new(world, rng, targets)
		lastEvents[i] = {}
	end
	-- pre-generate the packets so only the validator is timed
	local stream: { { SquirrelMotor.Snapshot } } = {}
	local now = 0
	for _ = 1, ticks do
		local frame: { SquirrelMotor.Snapshot } = {}
		for i, s in states do
			local inp = drivers[i]:input(s, lastEvents[i], TICK)
			local _, ev = SquirrelMotor.step(s, inp, TICK, world)
			lastEvents[i] = ev
			frame[i] = SquirrelMotor.serialize(s)
		end
		table.insert(stream, frame)
		now += TICK
	end
	local started = os.clock()
	local packets = 0
	for tick, frame in stream do
		local serverTime = tick * TICK + 0.1
		for i, snap in frame do
			validator:accept(i, { seq = tick, snapshot = snap }, serverTime)
			packets += 1
		end
	end
	local seconds = os.clock() - started
	return {
		perTickMs = seconds / ticks / squirrels * 1000,
		perPacketUs = seconds / packets * 1e6,
		packets = packets,
	}
end

return Harness
