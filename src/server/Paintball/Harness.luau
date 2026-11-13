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
-- TWO CONDITIONS. The S18 one above is the spike's, kept as it was (its bodies' true trajectories at 60
-- Hz, a view sampled from them at a snapshot rate, the S18 numbers of Shared/Paintball/Config).
-- opts.contract = true is THE CONTRACT'S: the same bodies judged end to end the way the match judges
-- them (the 20 Hz quantised snapshot stream as the only history, clients that draw from the snapshots
-- they were actually sent at their own view time, Clock.stamp with the measured upstream delay,
-- Clock.MAX_REWIND, Hit.body, crouching runners, lost snapshots: opts.loss). Its section below says how.
-- Interface: new(opts) -> Harness; step(h, dt) -> (arenaMs, harnessMs); report(h) -> table

local Import = require("../Import")
local Config = Import.shared("Paintball/Config") :: typeof(require("../../shared/Paintball/Config"))
local Ballistics = Import.shared("Paintball/Ballistics") :: typeof(require("../../shared/Paintball/Ballistics"))
local Magazine = Import.shared("Paintball/Magazine") :: typeof(require("../../shared/Paintball/Magazine"))
-- (a module reached through Import carries its values' types but not its exported type names:
-- this is the same type, taken from a value)
type Mag = typeof(Magazine.new(1, 1, 1))
local ArenaModule: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Arena)) =
	Import.shared("Minigames/Paintball/Arena")
local BodyModule: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Body)) =
	Import.shared("Minigames/Paintball/Body")
local Clock: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Clock)) =
	Import.shared("Minigames/Paintball/Clock")
local Contract: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Contract)) =
	Import.shared("Minigames/Paintball/Contract")
local Wire: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Wire)) =
	Import.shared("Minigames/Paintball/Wire")
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
	contract: boolean?, -- the contract's condition (see the header) instead of the S18 one
	loss: number?, -- the contract's condition: the fraction of snapshots a client never gets (0)
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
	mag: Mag,
	nextThink: number,
	rttEst: number,
	nextPing: number,
	history: PoseHistory.History,
	moved: number,
	floorsSeen: { [number]: boolean },
	manualReloads: number,
}

-- (in the contract's condition the server's balls are born when the click arrives: nil until then)
type Shot = { server: Projectiles.Ball?, truth: Projectiles.Ball, naive: Projectiles.Ball? }

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
	condition: any?, -- the contract's condition's own state (nil: the S18 condition)
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
			x, y, z = viewSampler(o :: any, now - actualDelay)
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
		local x2, _, z2 = viewSampler(target :: any, now - actualDelay - 0.1)
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

local setUpContract: (h: Harness) -> ()

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
		condition = nil,
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
	if opts.contract then
		setUpContract(h)
		for k = -Clock.SNAP_HZ, 0 do
			for _, b in h.bodies do
				local qx, qy, qz, qc = Wire.quantPose(b.x, b.y, b.z, 0)
				PoseHistory.push(b.history, k / Clock.SNAP_HZ, qx, qy, qz, qc)
			end
		end
		return h
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
		local sb, nb = s.server, s.naive
		if sb ~= nil and nb ~= nil and sb.done and s.truth.done and nb.done then
			r.shots += 1
			local sv, tv, nv = sb.hitBody, s.truth.hitBody, nb.hitBody
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

-- THE CONTRACT'S CONDITION (opts.contract; Shared/Minigames/Paintball/Clock) ------------------------------
-- The same bodies on the same floors, judged the way the match judges them, end to end:
--   the stream   twenty times a second the server takes every body's pose, quantises it as a snapshot
--                carries it (Wire.quantPose, the crouch fraction with it) and pushes exactly that into the
--                body's history (Clock.HISTORY_SECS at Clock.SNAP_HZ); the same snapshot is on its way to
--                every stub player, late by half the round trip with jitter, and lost opts.loss of the time;
--   the client   a stub player keeps what arrived, its lag (Clock.observe) and its view time
--                (Clock.viewTime), and DRAWS every other body between the two snapshots either side of
--                that time. It aims at what it draws, stamps its click (vt, ft) and flies its own ball
--                against what it draws, frame by frame: that ball's verdict is the truth, "what the
--                shooter saw";
--   the server   hears the click half a round trip later, stamps it with Clock.stamp and the shooter's
--                own measured upstream delay (its Moves, observed the same way), gives the ball its birth
--                and its rewind, flies it forward the part already flown and then tick by tick against
--                the histories, with Hit.body (Projectiles.forArena: the match's own sim, early reject and
--                all);
--   naive        the same ball with no rewind, for contrast.
-- Stub players crouch and stand as they run (the stance rides in the history and in the snapshots).
type View = typeof(Clock.newView())
type Snap = { t: number, xs: { number }, ys: { number }, zs: { number }, cs: { number } }
type Seat = {
	view: View, -- how late snapshots reach this player
	up: View, -- how late its Moves reach the server
	got: { Snap }, -- the snapshots that have arrived, oldest first
	arriving: { { at: number, snap: Snap } },
	moves: { { at: number, t: number } },
	truth: Projectiles.Sim, -- its own predicted balls
	vt: number, -- its view time this frame
	lastM: number?,
	nextCrouch: number,
}
type Condition = {
	seats: { [number]: Seat }, -- by body id (stub players only)
	crouch: { [number]: number }, -- every body's crouch fraction
	want: { [number]: boolean },
	pending: { { at: number, run: (now: number) -> () } }, -- clicks on their way up
	clamped: number,
	lost: number,
	sent: number,
}

-- Where a player draws body `id` at view time vt (Wire.between's arithmetic); nil before any snapshot.
local function drawn(seat: Seat, id: number, vt: number): (number?, number, number, number)
	local got = seat.got
	local newer: Snap? = nil
	for i = #got, 1, -1 do
		local s = got[i]
		if s.t > vt then
			newer = s
		else
			if newer == nil then
				return s.xs[id], s.ys[id], s.zs[id], s.cs[id]
			end
			local f = (vt - s.t) / (newer.t - s.t)
			return s.xs[id] + (newer.xs[id] - s.xs[id]) * f,
				s.ys[id] + (newer.ys[id] - s.ys[id]) * f,
				s.zs[id] + (newer.zs[id] - s.zs[id]) * f,
				s.cs[id] + (newer.cs[id] - s.cs[id]) * f
		end
	end
	if newer ~= nil then
		return newer.xs[id], newer.ys[id], newer.zs[id], newer.cs[id]
	end
	return nil, 0, 0, 0
end

local function delay(h: Harness): number
	local opts = h.opts
	local half = (opts.rttMs or 0) / 2000
	return half * (1 + (h.rand() * 2 - 1) * (opts.jitter or 0.12))
end

local function sweepOf(boxes: { number }): any
	return function(x0: number, y0: number, z0: number, x1: number, y1: number, z1: number)
		return ArenaModule.sweepBoxes(boxes, x0, y0, z0, x1, y1, z1)
	end
end

setUpContract = function(h: Harness)
	local feel = Contract.feel()
	local building: any = { sweep = sweepOf(h.layout.boxes) }
	h.server = Projectiles.forArena(building, feel)
	h.naive = Projectiles.forArena(building, feel)
	local cond: Condition = { seats = {}, crouch = {}, want = {}, pending = {}, clamped = 0, lost = 0, sent = 0 }
	for _, b in h.bodies do
		b.history = PoseHistory.new(Clock.HISTORY_SECS, Clock.SNAP_HZ)
		cond.crouch[b.id] = 0
		cond.want[b.id] = false
		if not b.isBot then
			local seat: Seat
			seat = {
				view = Clock.newView(),
				up = Clock.newView(),
				got = {},
				arriving = {},
				moves = {},
				truth = Projectiles.forArena(building, feel, function(target: Projectiles.Target, _t: number)
					local x, y, z, c = drawn(seat, target.id, seat.vt)
					if x == nil then
						return 0, -1000, 0, 0
					end
					return x, y, z, c
				end),
				vt = 0,
				lastM = nil,
				nextCrouch = h.rand() * 3,
			}
			cond.seats[b.id] = seat
		end
	end
	h.condition = cond
end

-- a stub player's turn to think: aim at what it draws, click, fly its own ball
local function thinkContract(h: Harness, cond: Condition, b: Body, seat: Seat)
	local now = h.now
	if now < b.nextThink then
		return
	end
	b.nextThink = now + 0.12 + h.rand() * 0.1
	local mag = b.mag
	Magazine.update(mag, now)
	local vt = seat.vt
	local best: Body? = nil
	local bestD = 80
	local bx, by, bz = 0, 0, 0
	for _, o in h.bodies do
		if o.team ~= b.team then
			local x, y, z = drawn(seat, o.id, vt)
			if x ~= nil and math.abs(y - b.y) <= 5 then
				local d = math.sqrt((x - b.x) ^ 2 + (z - b.z) ^ 2)
				if d > 6 and d < bestD then
					best, bestD, bx, by, bz = o, d, x, y, z
				end
			end
		end
	end
	if best == nil then
		if mag.rounds <= 2 and Magazine.reload(mag, now) then
			b.manualReloads += 1
		end
		return
	end
	if h.rand() > 0.6 or not Magazine.canFire(mag, now) then
		return
	end
	local target = best :: Body
	local x2, _, z2 = drawn(seat, target.id, vt - 0.1)
	local vx, vz = (bx - (x2 or bx)) / 0.1, (bz - z2) / 0.1
	if x2 == nil then
		vx, vz = 0, 0
	end
	local feel = Contract.FEEL
	local ex, ey, ez = BodyModule.eyePoint(b.x, b.y, b.z, cond.crouch[b.id])
	local tof = bestD / feel.ballSpeed
	local sigma = h.opts.aimSigma or 0.9
	local ax = bx + vx * tof + gauss(h.rand) * sigma
	local ay = by + 1.6 + h.rand() * 2.2 + gauss(h.rand) * sigma * 0.5
	local az = bz + vz * tof + gauss(h.rand) * sigma
	local mvx, mvy, mvz = Ballistics.aim(ex, ey, ez, ax, ay, az, feel.ballSpeed, feel.ballDrop)
	Magazine.fire(mag, now)
	local targets = h.bodies :: any
	local shot: Shot = {
		server = nil,
		truth = Projectiles.fire(seat.truth, b.id, b.team, ex, ey, ez, mvx, mvy, mvz, 0, now),
		naive = nil,
	}
	table.insert(h.shots, shot)
	local ft = now
	table.insert(cond.pending, {
		at = now + delay(h),
		run = function(arrived: number)
			-- the server's reading of the click (PaintballService, onFire b)
			local f, _, rewind, clamped, m = Clock.stamp(arrived, vt, ft, seat.lastM, seat.up.lag)
			seat.lastM = m
			if clamped then
				cond.clamped += 1
			end
			local ball = Projectiles.fire(h.server, b.id, b.team, ex, ey, ez, mvx, mvy, mvz, rewind, f)
			Projectiles.advance(h.server, ball, arrived, targets)
			shot.server = ball
			local plain = Projectiles.fire(h.naive, b.id, b.team, ex, ey, ez, mvx, mvy, mvz, 0, f)
			Projectiles.advance(h.naive, plain, arrived, targets)
			shot.naive = plain
		end,
	})
end

-- a bot sees the server's present: no stamp, no rewind
local function thinkBot(h: Harness, b: Body)
	local now = h.now
	if now < b.nextThink then
		return
	end
	b.nextThink = now + 0.12 + h.rand() * 0.1
	Magazine.update(b.mag, now)
	local best: Body? = nil
	local bestD = 80
	for _, o in h.bodies do
		if o.team ~= b.team and math.abs(o.y - b.y) <= 5 then
			local d = math.sqrt((o.x - b.x) ^ 2 + (o.z - b.z) ^ 2)
			if d > 6 and d < bestD then
				best, bestD = o, d
			end
		end
	end
	if best == nil or h.rand() > 0.6 or not Magazine.canFire(b.mag, now) then
		return
	end
	local o = best :: Body
	local feel = Contract.FEEL
	local ex, ey, ez = BodyModule.eyePoint(b.x, b.y, b.z, 0)
	local tof = bestD / feel.ballSpeed
	local sigma = h.opts.aimSigma or 0.9
	local mvx, mvy, mvz = Ballistics.aim(
		ex,
		ey,
		ez,
		o.x + o.vx * tof + gauss(h.rand) * sigma,
		o.y + 1.6 + h.rand() * 2.2,
		o.z + o.vz * tof + gauss(h.rand) * sigma,
		feel.ballSpeed,
		feel.ballDrop
	)
	Magazine.fire(b.mag, now)
	Projectiles.fire(h.server, b.id, b.team, ex, ey, ez, mvx, mvy, mvz, 0, now)
	h.results.botShots += 1
end

-- One 60 Hz frame of the contract's condition. Returns (arenaMs, harnessMs).
local function contractStep(h: Harness, cond: Condition, dt: number): (number, number)
	local t0 = os.clock()
	h.now += dt
	h.frame += 1
	local now = h.now
	local frame = h.frame
	local loss = h.opts.loss or 0
	local feel = Contract.FEEL
	local per = Clock.TICK_HZ // Clock.SNAP_HZ
	-- the clients' own work: they move, crouch, send their Moves, take in snapshots, look, think
	for _, b in h.players do
		moveBody(h, b, dt)
		local seat = cond.seats[b.id]
		if now >= seat.nextCrouch then
			seat.nextCrouch = now + 0.6 + h.rand() * 2.5
			cond.want[b.id] = h.rand() < 0.4
		end
		cond.crouch[b.id] = BodyModule.crouchStep(cond.crouch[b.id], cond.want[b.id], dt, feel)
		if (frame + b.id) % per == 0 then
			table.insert(seat.moves, { at = now + delay(h), t = now })
		end
	end
	-- what reaches the server this frame: Moves (the upstream delay is measured from them) and clicks
	for _, b in h.players do
		local seat = cond.seats[b.id]
		local moves = seat.moves
		local i = 1
		while i <= #moves do
			if moves[i].at <= now then
				Clock.observe(seat.up, moves[i].t, now)
				table.remove(moves, i)
			else
				i += 1
			end
		end
	end
	local pending = cond.pending
	local k = 1
	while k <= #pending do
		if pending[k].at <= now then
			local item = table.remove(pending, k) :: { at: number, run: (now: number) -> () }
			item.run(now)
		else
			k += 1
		end
	end
	local t1 = os.clock()
	-- the server: bots, the snapshot tick, the balls
	for _, b in h.bots do
		moveBody(h, b, dt)
		thinkBot(h, b)
	end
	if frame % per == 0 then
		local n = #h.bodies
		local snap: Snap = {
			t = now,
			xs = table.create(n, 0),
			ys = table.create(n, 0),
			zs = table.create(n, 0),
			cs = table.create(n, 0),
		}
		for _, b in h.bodies do
			local qx, qy, qz, qc = Wire.quantPose(b.x, b.y, b.z, cond.crouch[b.id])
			PoseHistory.push(b.history, now, qx, qy, qz, qc)
			snap.xs[b.id], snap.ys[b.id], snap.zs[b.id], snap.cs[b.id] = qx, qy, qz, qc
		end
		for _, b in h.players do
			cond.sent += 1
			if h.rand() < loss then
				cond.lost += 1
			else
				table.insert(cond.seats[b.id].arriving, { at = now + delay(h), snap = snap })
			end
		end
	end
	Projectiles.step(h.server, now, dt, h.bodies :: any)
	local t2 = os.clock()
	-- the clients again: snapshots arrive, the view time moves on, they think and fly their own balls
	for _, b in h.players do
		local seat = cond.seats[b.id]
		local arriving = seat.arriving
		local i = 1
		while i <= #arriving do
			local item = arriving[i]
			if item.at <= now then
				table.remove(arriving, i)
				Clock.observe(seat.view, item.snap.t, now)
				-- kept in order of their own time, whatever order they came in
				local got = seat.got
				local at = #got + 1
				while at > 1 and got[at - 1].t > item.snap.t do
					at -= 1
				end
				table.insert(got, at, item.snap)
				if #got > 30 then
					table.remove(got, 1)
				end
			else
				i += 1
			end
		end
		seat.vt = Clock.viewTime(seat.view, now)
		thinkContract(h, cond, b, seat)
		Projectiles.step(seat.truth, now, dt, h.bodies :: any)
	end
	Projectiles.step(h.naive, now, dt, h.bodies :: any)
	resolve(h)
	local t3 = os.clock()
	local arena = (t2 - t1) * 1000
	local harness = ((t1 - t0) + (t3 - t2)) * 1000
	table.insert(h.arenaMs, arena)
	table.insert(h.harnessMs, harness)
	return arena, harness
end

-- One 60 Hz server frame. Returns (arenaMs, harnessMs).
function Harness.step(h: Harness, dt: number): (number, number)
	local condition = h.condition
	if condition ~= nil then
		return contractStep(h, condition, dt)
	end
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
		-- (the contract's condition: stamps the server clamped, snapshots sent and lost)
		rewindsClamped = if h.condition then h.condition.clamped else 0,
		snapshotsSent = if h.condition then h.condition.sent else 0,
		snapshotsLost = if h.condition then h.condition.lost else 0,
		minFloorsVisited = floorsMin,
		stuckBodies = stuck,
		arenaMs = summarise(h.arenaMs),
		harnessMs = summarise(h.harnessMs),
	}
end

return Harness
