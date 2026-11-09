--!strict
-- ServerScriptService.Server.Paintball.Harness
-- The S18 hit-registration harness (BUILD_PLAN §4.3 S18, D29; the W4 `Paintball` suite grows from
-- it): stub players and navigation-brain bots run around the five-floor Layout and shoot each other
-- with five-ball magazines; every ball is simulated three ways:
--   server : the real path, Projectiles against the 60 Hz PoseHistory rewound to the shooter's
--            timestamp (the server time of the frame the client was showing when it fired), clamped
--            to the server's own estimate (EWMA of jittered RTT samples + the interpolation delay)
--            +/- a tolerance; or, in "estimate" mode, rewound by the estimate alone;
--   truth  : the shooter's own view, i.e. targets interpolated from 20 Hz snapshots at the shot's
--            *actual* delay (this shot's jittered RTT + the interpolation delay) - ground truth;
--   naive  : no lag compensation (current poses), for contrast.
-- A shot "agrees" when the server's verdict (which body, or none) equals the truth's.
-- Timing splits the server's real work (bot brains and motion, pose history, server balls, splats:
-- `arenaMs`) from the harness's own (stub players' movement and aim, truth and naive balls).
-- Pure Luau with an injected seed: Lune runs it for the accuracy tests, the engine task for timing.
-- Interface: new(opts) -> Harness; step(h, dt) -> (arenaMs, harnessMs); report(h) -> table

local Import = require("../Import")
local Config = Import.shared("Paintball/Config") :: typeof(require("../../shared/Paintball/Config"))
local Ballistics = Import.shared("Paintball/Ballistics") :: typeof(require("../../shared/Paintball/Ballistics"))
local Magazine = Import.shared("Paintball/Magazine") :: typeof(require("../../shared/Paintball/Magazine"))
local PoseHistory = require("./PoseHistory")
local Projectiles = require("./Projectiles")
local Splats = require("./Splats")
local Layout = require("./Layout")

export type Opts = {
	shooters: number?, -- stub players (lag-compensated)
	bots: number?, -- server-side bots (no latency)
	seed: number?,
	rttMs: number?, -- the players' base round trip
	jitter: number?, -- +/- fraction of the RTT per sample (0.12)
	interpSecs: number?, -- client interpolation delay, known to the server (0.05)
	snapshotHz: number?, -- replication snapshots the client interpolates (20)
	aimSigma: number?, -- studs of aim error at the target (0.9)
	evaluate: boolean?, -- fly truth and naive balls (false: timing only)
	-- "timestamp" (the plan's method): the client stamps each shot with the server time of the frame it
	-- was showing; the server uses it, clamped to its own estimate +/- timestampTolerance.
	-- "estimate": the server ignores the stamp and rewinds by its RTT estimate alone.
	rewindMode: ("timestamp" | "estimate")?,
	timestampTolerance: number?, -- seconds (0.075)
}

export type Body = {
	id: number,
	team: number,
	isBot: boolean,
	x: number,
	y: number,
	z: number,
	yaw: number,
	vx: number,
	vz: number,
	floor: number,
	tx: number,
	tz: number,
	stair: Layout.Stair?,
	stairUp: boolean,
	stairT: number,
	pendingStair: Layout.Stair?,
	pendingUp: boolean,
	speed: number,
	phase: number,
	mag: Magazine.Mag,
	nextThink: number,
	rttEst: number,
	nextPing: number,
	history: PoseHistory.History,
	moved: number,
	floorsSeen: { [number]: boolean },
	manualReloads: number,
}

type Shot = { server: Projectiles.Ball, truth: Projectiles.Ball, naive: Projectiles.Ball }

export type Harness = {
	opts: Opts,
	layout: Layout.Layout,
	bodies: { Body },
	players: { Body },
	bots: { Body },
	now: number,
	frame: number,
	rand: () -> number,
	server: Projectiles.Sim,
	truth: Projectiles.Sim,
	naive: Projectiles.Sim,
	splats: Splats.Pool,
	shots: { Shot },
	results: {
		shots: number,
		agree: number,
		agreeNaive: number,
		truthHits: number,
		serverHits: number,
		naiveHits: number,
		falsePos: number,
		falseNeg: number,
		wrongBody: number,
		botShots: number,
	},
	arenaMs: { number },
	harnessMs: { number },
	splatMax: number,
}

local Harness = {}

local function lcg(seed: number): () -> number
	local s = seed % 2147483647
	if s <= 0 then
		s += 2147483646
	end
	return function(): number
		s = (s * 48271) % 2147483647
		return (s - 1) / 2147483646
	end
end

local function gauss(rand: () -> number): number
	local u1 = math.max(rand(), 1e-12)
	return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * rand())
end

local function pickWaypoint(h: Harness, b: Body)
	local layout = h.layout
	-- now and then take the stairs up or down
	if h.rand() < 0.15 then
		local up: Layout.Stair?, down: Layout.Stair? = nil, nil
		for _, s in layout.stairs do
			if s.floor == b.floor then
				up = s
			elseif s.floor == b.floor - 1 then
				down = s
			end
		end
		local useUp = if up and down then h.rand() < 0.5 else up ~= nil
		local s = if useUp then up else down
		if s then
			b.pendingStair, b.pendingUp = s, useUp
			b.tx, b.tz = if useUp then s.x0 else s.x1, if useUp then s.z0 else s.z1
			return
		end
	end
	local list = layout.waypoints[b.floor]
	local w = list[math.floor(h.rand() * #list) + 1]
	b.tx, b.tz = w.x, w.z
end

local STAIR_LEN = math.sqrt(16 * 16 + 14 * 14)

local function moveBody(h: Harness, b: Body, dt: number)
	local fh = h.layout.floorHeight
	local px, pz = b.x, b.z
	local stair = b.stair
	if stair then
		b.stairT += b.speed * 0.6 * dt / STAIR_LEN
		local a = math.min(b.stairT, 1)
		local u = if b.stairUp then a else 1 - a
		b.x = stair.x0 + (stair.x1 - stair.x0) * u
		b.z = stair.z0 + (stair.z1 - stair.z0) * u
		b.y = (stair.floor + u) * fh
		if b.stairT >= 1 then
			b.floor = if b.stairUp then stair.floor + 1 else stair.floor
			b.floorsSeen[b.floor] = true
			b.stair = nil
			pickWaypoint(h, b)
		end
	else
		local dx, dz = b.tx - b.x, b.tz - b.z
		local d = math.sqrt(dx * dx + dz * dz)
		if d < 1 then
			if b.pendingStair then
				b.stair, b.stairUp, b.stairT = b.pendingStair, b.pendingUp, 0
				b.pendingStair = nil
			else
				pickWaypoint(h, b)
			end
		else
			local step = math.min(d, b.speed * dt)
			local ux, uz = dx / d, dz / d
			b.x += ux * step
			b.z += uz * step
			if not b.isBot then
				-- stub players strafe: a lateral weave on top of the walk
				b.phase += dt * 3.1
				local lateral = 7 * math.sin(b.phase) * dt
				b.x = math.clamp(b.x - uz * lateral, -58, 58)
				b.z = math.clamp(b.z + ux * lateral, -58, 58)
			end
			b.y = b.floor * fh
		end
	end
	b.vx, b.vz = (b.x - px) / dt, (b.z - pz) / dt
	if b.vx * b.vx + b.vz * b.vz > 1e-6 then
		b.yaw = math.atan2(b.vx, b.vz)
	end
	b.moved += math.sqrt((b.x - px) ^ 2 + (b.z - pz) ^ 2)
end

-- the shooter's view: positions interpolated between 20 Hz snapshots taken from the true trajectory
local function makeViewSampler(hz: number): Projectiles.Sampler
	return function(target: Projectiles.Target, t: number): (number, number, number)
		local k = math.floor(t * hz + 1e-9)
		local t0 = k / hz
		local x0, y0, z0 = PoseHistory.sample(target.history, t0)
		local x1, y1, z1 = PoseHistory.sample(target.history, t0 + 1 / hz)
		local a = (t - t0) * hz
		return x0 + (x1 - x0) * a, y0 + (y1 - y0) * a, z0 + (z1 - z0) * a
	end
end

local function think(h: Harness, b: Body, viewSampler: Projectiles.Sampler)
	local now = h.now
	if now < b.nextThink then
		return
	end
	b.nextThink = now + 0.12 + h.rand() * 0.1
	local mag = b.mag
	Magazine.update(mag, now)
	local opts = h.opts
	local interp = opts.interpSecs or 0.05
	local rtt = (opts.rttMs or 0) / 1000
	local jitter = opts.jitter or 0.12
	-- this moment's actual delay between the server state and what the shooter sees
	local actualDelay = 0
	if not b.isBot then
		actualDelay = rtt * (1 + (h.rand() * 2 - 1) * jitter) + interp
	end
	local best: Body? = nil
	local bestD = 80
	local bx, by, bz = 0, 0, 0
	for _, o in h.bodies do
		if o.team == b.team then
			continue
		end
		local x, y, z
		if b.isBot then
			x, y, z = o.x, o.y, o.z
		else
			x, y, z = viewSampler(o, now - actualDelay)
		end
		if math.abs(y - b.y) > 5 then
			continue
		end
		local d = math.sqrt((x - b.x) ^ 2 + (z - b.z) ^ 2)
		if d > 6 and d < bestD then
			best, bestD, bx, by, bz = o, d, x, y, z
		end
	end
	if best == nil then
		if mag.rounds <= 2 and Magazine.reload(mag, now) then
			b.manualReloads += 1 -- R with nothing to shoot at
		end
		return
	end
	if h.rand() > 0.6 or not Magazine.canFire(mag, now) then
		return
	end
	local target = best :: Body
	-- lead the target with its apparent velocity
	local vx, vz = target.vx, target.vz
	if not b.isBot then
		local x2, _, z2 = viewSampler(target, now - actualDelay - 0.1)
		vx, vz = (bx - x2) / 0.1, (bz - z2) / 0.1
	end
	local cfg = Config.projectile
	local ex, ey, ez = b.x, b.y + Config.body.eye, b.z
	local tof = bestD / cfg.speed
	local sigma = opts.aimSigma or 0.9
	local ax = bx + vx * tof + gauss(h.rand) * sigma
	local ay = by + 1.6 + h.rand() * 2.2 + gauss(h.rand) * sigma * 0.5
	local az = bz + vz * tof + gauss(h.rand) * sigma
	local mvx, mvy, mvz = Ballistics.aim(ex, ey, ez, ax, ay, az, cfg.speed, cfg.drop)
	Magazine.fire(mag, now)
	local rewind = 0
	if not b.isBot then
		local estimate = b.rttEst + interp
		if (opts.rewindMode or "timestamp") == "timestamp" then
			local tol = opts.timestampTolerance or 0.075
			rewind = math.clamp(actualDelay, estimate - tol, estimate + tol)
		else
			rewind = estimate
		end
	end
	local serverBall = Projectiles.fire(h.server, b.id, b.team, ex, ey, ez, mvx, mvy, mvz, rewind)
	if b.isBot then
		h.results.botShots += 1
	elseif opts.evaluate ~= false then
		local truthBall = Projectiles.fire(h.truth, b.id, b.team, ex, ey, ez, mvx, mvy, mvz, actualDelay)
		local naiveBall = Projectiles.fire(h.naive, b.id, b.team, ex, ey, ez, mvx, mvy, mvz, 0)
		table.insert(h.shots, { server = serverBall, truth = truthBall, naive = naiveBall })
	end
end

function Harness.new(opts: Opts): Harness
	local layout = Layout.build()
	local rand = lcg(opts.seed or 18)
	local splats = Splats.new(Config.splatPool)
	local h: Harness = {
		opts = opts,
		layout = layout,
		bodies = {},
		players = {},
		bots = {},
		now = 0,
		frame = 0,
		rand = rand,
		server = Projectiles.new(layout.boxes, splats),
		truth = Projectiles.new(layout.boxes, nil, makeViewSampler(opts.snapshotHz or 20)),
		naive = Projectiles.new(layout.boxes, nil),
		splats = splats,
		shots = {},
		results = {
			shots = 0,
			agree = 0,
			agreeNaive = 0,
			truthHits = 0,
			serverHits = 0,
			naiveHits = 0,
			falsePos = 0,
			falseNeg = 0,
			wrongBody = 0,
			botShots = 0,
		},
		arenaMs = {},
		harnessMs = {},
		splatMax = 0,
	}
	local nShooters, nBots = opts.shooters or 16, opts.bots or 10
	local rtt = (opts.rttMs or 0) / 1000
	for i = 1, nShooters + nBots do
		local isBot = i > nShooters
		local floor = (i - 1) % layout.floors
		local list = layout.waypoints[floor]
		local w = list[math.floor(rand() * #list) + 1]
		local b: Body = {
			id = i,
			team = i % 2,
			isBot = isBot,
			x = w.x,
			y = floor * layout.floorHeight,
			z = w.z,
			yaw = 0,
			vx = 0,
			vz = 0,
			floor = floor,
			tx = w.x,
			tz = w.z,
			stair = nil,
			stairUp = true,
			stairT = 0,
			pendingStair = nil,
			pendingUp = true,
			speed = if isBot then 14 + rand() * 4 else 16 + rand() * 6,
			phase = rand() * 6.28,
			mag = Magazine.new(Config.magazine, Config.fireInterval, Config.reloadSecs),
			nextThink = rand() * 0.3,
			rttEst = rtt,
			nextPing = rand() * 0.5,
			history = PoseHistory.new(Config.historySecs, Config.historyHz),
			moved = 0,
			floorsSeen = { [floor] = true },
			manualReloads = 0,
		}
		pickWaypoint(h, b)
		table.insert(h.bodies, b)
		table.insert(if isBot then h.bots else h.players, b)
	end
	-- prime one second of history at the start poses
	for f = -Config.historyHz, 0 do
		for _, b in h.bodies do
			PoseHistory.push(b.history, f / Config.historyHz, b.x, b.y, b.z)
		end
	end
	return h
end

local function resolve(h: Harness)
	local r = h.results
	local shots = h.shots
	local i = 1
	while i <= #shots do
		local s = shots[i]
		if s.server.done and s.truth.done and s.naive.done then
			r.shots += 1
			local sv, tv, nv = s.server.hitBody, s.truth.hitBody, s.naive.hitBody
			if sv == tv then
				r.agree += 1
			elseif tv == 0 then
				r.falsePos += 1
			elseif sv == 0 then
				r.falseNeg += 1
			else
				r.wrongBody += 1
			end
			if nv == tv then
				r.agreeNaive += 1
			end
			r.truthHits += if tv ~= 0 then 1 else 0
			r.serverHits += if sv ~= 0 then 1 else 0
			r.naiveHits += if nv ~= 0 then 1 else 0
			shots[i] = shots[#shots]
			shots[#shots] = nil
		else
			i += 1
		end
	end
end

-- One 60 Hz server frame. Returns (arenaMs, harnessMs).
function Harness.step(h: Harness, dt: number): (number, number)
	local t0 = os.clock()
	h.now += dt
	h.frame += 1
	local now = h.now
	local viewSampler = h.truth.sampler
	local opts = h.opts
	local jitter = opts.jitter or 0.12
	local rtt = (opts.rttMs or 0) / 1000
	-- stub players (their clients' work): move, then maybe shoot
	for _, b in h.players do
		moveBody(h, b, dt)
		if now >= b.nextPing then
			-- the server's RTT estimate: an EWMA of jittered samples twice a second
			b.nextPing = now + 0.5
			local sample = rtt * (1 + (h.rand() * 2 - 1) * jitter)
			b.rttEst += (sample - b.rttEst) * 0.2
		end
		think(h, b, viewSampler)
	end
	local t1 = os.clock()
	-- the server: bot brains and motion, pose history, balls, splats
	for _, b in h.bots do
		moveBody(h, b, dt)
		think(h, b, viewSampler)
	end
	for _, b in h.bodies do
		PoseHistory.push(b.history, now, b.x, b.y, b.z)
	end
	Projectiles.step(h.server, now, dt, h.bodies :: any)
	local t2 = os.clock()
	if opts.evaluate ~= false then
		Projectiles.step(h.truth, now, dt, h.bodies :: any)
		Projectiles.step(h.naive, now, dt, h.bodies :: any)
		resolve(h)
	end
	local t3 = os.clock()
	h.splatMax = math.max(h.splatMax, Splats.size(h.splats))
	local arena = (t2 - t1) * 1000
	local harness = ((t1 - t0) + (t3 - t2)) * 1000
	table.insert(h.arenaMs, arena)
	table.insert(h.harnessMs, harness)
	return arena, harness
end

local function summarise(list: { number }): { avg: number, p50: number, p99: number, max: number }
	local sorted = table.clone(list)
	table.sort(sorted)
	local sum = 0
	for _, v in sorted do
		sum += v
	end
	local n = #sorted
	local function pct(p: number): number
		return if n == 0 then 0 else sorted[math.max(1, math.ceil(n * p))]
	end
	return { avg = if n > 0 then sum / n else 0, p50 = pct(0.5), p99 = pct(0.99), max = pct(1) }
end

function Harness.report(h: Harness): { [string]: any }
	local r = h.results
	local fired, autoReloads, manual, floorsMin, stuck = 0, 0, 0, math.huge, 0
	for _, b in h.bodies do
		fired += b.mag.fired
		autoReloads += b.mag.reloads - b.manualReloads
		manual += b.manualReloads
		local n = 0
		for _ in b.floorsSeen do
			n += 1
		end
		floorsMin = math.min(floorsMin, n)
		if b.moved < 5 then
			stuck += 1
		end
	end
	return {
		rttMs = h.opts.rttMs or 0,
		rewindMode = h.opts.rewindMode or "timestamp",
		jitter = h.opts.jitter or 0.12,
		aimSigma = h.opts.aimSigma or 0.9,
		frames = h.frame,
		simSeconds = h.now,
		bodies = #h.bodies,
		shots = r.shots,
		agreement = if r.shots > 0 then r.agree / r.shots else 0,
		agreementNaive = if r.shots > 0 then r.agreeNaive / r.shots else 0,
		truthHits = r.truthHits,
		serverHits = r.serverHits,
		naiveHits = r.naiveHits,
		falsePos = r.falsePos,
		falseNeg = r.falseNeg,
		wrongBody = r.wrongBody,
		botShots = r.botShots,
		ballsFired = fired,
		autoReloads = autoReloads,
		manualReloads = manual,
		server = table.clone(h.server.stats),
		splats = { max = h.splatMax, cap = h.splats.cap, overwritten = h.splats.overwritten },
		minFloorsVisited = floorsMin,
		stuckBodies = stuck,
		arenaMs = summarise(h.arenaMs),
		harnessMs = summarise(h.harnessMs),
	}
end

return Harness
