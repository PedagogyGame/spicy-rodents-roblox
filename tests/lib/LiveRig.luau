--!strict
-- tests/lib/LiveRig: the live squirrel validator end to end, headless (Boot/Game.movement; Server/Movement/
-- MovementService over MoveValidator; the client's Controllers/MotorLink; Shared/Movement/SquirrelWire). One player
-- holds one squirrel:
--   the client: the real SquirrelMotor stepped at the client's own frame rate (opts.fps: a number or a function of
--     the frame, so a slow phone and its hitches are a rig case), with scripted keys, the controller's frame as
--     Controllers/Squirrel runs it (MotorLink.apply at the top, a root the server moved restarts the motor unless it
--     is the echo of a correction already taken, the river recovery after the step, MotorLink.tick after it), and
--     its root replicated to the server at opts.link.rootHz;
--   the link, both ways: base latency, uniform jitter, random loss (up only: the motor state is unreliable), and
--     two kinds of burst: `hold` (everything sent in holdFor seconds arrives together at its end) and `drop`
--     (everything sent in dropFor seconds is lost), every holdEvery / dropEvery seconds; reliable messages down
--     (Correction, the grant, the ride's end) keep their order, the server's own writes of the root keep theirs,
--     and the two streams race;
--   the server: MovementService with the validator, its engine.correct and engine.hold as Boot/Game has them (a snap
--     writes the root), every packet decoded from the bytes the client sent, the root watched fifteen times a second,
--     the sky lift's Ride attribute turned into suspend / teleported exactly as Boot/Game.watchSquirrels does.
-- Server events a case can schedule: teleport (the Reset button, a knock, the lounge's door), board / alight (the
-- sky lift), handoff (a new body; packets of the old one still arriving are taken for the new, as the game does),
-- release and possess again (a knock-out and a respawn).
-- The server pins a new body (engine.pin, as Boot/Game: anchored, its own) until the first packet passes the gate: the
-- client's root updates are not taken while it is pinned.
-- Interface: new(opts) -> Rig; Rig:possess(state, keys); Rig:run(seconds); Rig:at(t, fn); Rig:teleport(x, y, z,
--   why); Rig:board(); Rig:alight(x, y, z); Rig:handoff(state, keys); Rig:release(); Rig:unreported(x, y, z);
--   Rig:result() -> Result;
--   town() -> Town (the rig's town: the S3 world with houses, its validator world, honest drivers); describe(name, r)
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local SquirrelWire = require("@shared/Movement/SquirrelWire")
local Recovery = require("@shared/Movement/Recovery")
local MoveValidator = require("@server/Movement/MoveValidator")
local MovementService = require("@server/Movement/MovementService")
local MotorLink = require("@client/Controllers/MotorLink")
local Rng = require("@tests/cheat/Rng")
local Units = require("@shared/Config/Units")
local ValidatorWorld = require("@server/Movement/ValidatorWorld")
local Driver = require("@tests/cheat/Driver")
local Harness = require("@tests/cheat/Harness")
local TestWorld = require("@tests/cheat/TestWorld")

local LiveRig = {}

type State = SquirrelMotor.State
type Input = SquirrelMotor.Input
type Event = SquirrelMotor.Event

export type Link = {
	latency: number?, -- one way, seconds (default 0.08)
	latencyAt: ((t: number) -> number)?, -- one way at time t, in place of `latency` (a link whose latency changes)
	jitter: number?, -- uniform on top (default 0.15)
	loss: number?, -- up, per packet (default 0.02)
	holdEvery: number?, -- seconds between holds (nil: none)
	holdFor: number?,
	dropEvery: number?, -- seconds between loss bursts (nil: none)
	dropFor: number?,
	rootHz: number?, -- the root's replication to the server (default 30)
}

export type Keys = (t: number, state: State, events: { Event }) -> Input

export type Options = {
	world: SquirrelMotor.World, -- the client's motor world
	vworld: any, -- the validator's world (Movement/ValidatorWorld.build or any MoveValidator world)
	link: Link?,
	seed: number?,
	fps: (number | (frame: number, t: number) -> number)?,
	boosted: boolean?, -- the server knows of a chili rush (and the client's motor runs it)
	enforce: boolean?, -- default true
	-- cheats: an edit of the client's own state after its step; a client that never takes a correction; no packets
	cheat: ((state: State, input: Input, t: number, world: SquirrelMotor.World) -> ())?,
	ignoreCorrections: boolean?,
	silent: ((t: number) -> boolean)?,
	clockRate: number?, -- the client's motor clock against real time (a time hack: 2)
	-- a client that writes its root as it likes: an edit of the root's replicated position at send time
	rootCheat: ((p: { x: number, y: number, z: number }, t: number, state: State) -> ())?,
	-- an edit of a packet's snapshot before it is encoded (false: not sent)
	packetCheat: ((snap: { [string]: any }, t: number) -> boolean?)?,
	-- the engine's round trip as the server reads it, in place of the link's own (Player:GetNetworkPing)
	pingOf: ((t: number) -> number)?,
	-- seconds the client spends loading a new body (the town streaming in round it) before its controller starts
	loadSeconds: number?,
}

export type Result = {
	snaps: number,
	reasons: { [string]: number },
	holds: number,
	firstSnap: number?, -- server time of the first snap
	packets: number,
	accepted: number,
	stale: number,
	violations: { string },
	sent: number,
	serverMsPerTick: number, -- the server's cost for this squirrel per 60 Hz tick
	recoveries: number,
	visited: { [number]: boolean },
	frames: number,
	seconds: number,
	-- where the server's root is at the end, and the client's motor
	root: { x: number, y: number, z: number },
	client: State?,
}

type Ev = { t: number, n: number, fn: () -> () }

export type Rig = {
	t: number,
	opts: Options,
	run: (self: Rig, seconds: number) -> (),
	at: (self: Rig, t: number, fn: () -> ()) -> (),
	possess: (self: Rig, state: State, keys: Keys) -> (),
	teleport: (self: Rig, x: number, y: number, z: number, why: string) -> (),
	board: (self: Rig) -> (),
	alight: (self: Rig, x: number, y: number, z: number) -> (),
	handoff: (self: Rig, state: State, keys: Keys) -> (),
	release: (self: Rig) -> (),
	unreported: (self: Rig, x: number, y: number, z: number) -> (),
	server: any,
	result: (self: Rig) -> Result,
	movement: any,
	client: any,
}

function LiveRig.new(opts: Options): Rig
	local link: Link = opts.link or {}
	local latency = link.latency or 0.08
	local jitter = link.jitter or 0.15
	local loss = link.loss or 0.02
	local rootHz = link.rootHz or 30
	local rng = Rng.new(opts.seed or 1)
	local queue: { Ev } = {}
	local n = 0
	local rig: any = { t = 0, opts = opts }
	local violations: { string } = {}
	local accepted, packets, holds = 0, 0, 0
	local serverSeconds = 0 -- the server's time on the squirrel: decoding, judging, watching

	local function at(t: number, fn: () -> ())
		n += 1
		local e: Ev = { t = t, n = n, fn = fn }
		local i = #queue
		while i >= 1 and (queue[i].t > t or (queue[i].t == t and queue[i].n > e.n)) do
			i -= 1
		end
		table.insert(queue, i + 1, e)
	end
	rig.at = function(_self: any, t: number, fn: () -> ())
		at(t, fn)
	end

	local function oneWay(): number
		local base = if link.latencyAt then link.latencyAt(rig.t) else latency
		return base + rng.next() * jitter
	end
	-- the reliable stream down keeps its order; so does the stream of the server's root writes
	local lastReliable, lastWrite = 0, 0
	local function reliable(fn: () -> ())
		local t = math.max(rig.t + oneWay(), lastReliable + 1e-4)
		lastReliable = t
		at(t, fn)
	end
	local function write(fn: () -> ())
		local t = math.max(rig.t + oneWay(), lastWrite + 1e-4)
		lastWrite = t
		at(t, fn)
	end
	-- an up packet's fate at send time t: nil (lost) or its arrival
	local function upArrival(t: number): number?
		if link.dropEvery and (t % link.dropEvery) < (link.dropFor or 0) then
			return nil
		end
		if rng.next() < loss then
			return nil
		end
		local arrival = t + oneWay()
		if link.holdEvery then
			local phase = t % link.holdEvery
			local holdFor = link.holdFor or 0
			if phase < holdFor then
				arrival = math.max(arrival, t - phase + holdFor + latency)
			end
		end
		return arrival
	end

	-- the server ----------------------------------------------------------------------------------------------
	local server = {
		actor = 0, -- the held body's id (a number; a hand-off is the next one; 0: none)
		count = 0,
		root = { x = 0, y = 0, z = 0 },
		rootSent = -math.huge, -- send time of the root update last applied
		riding = false,
		onLift = false,
		held = false,
		pinned = false, -- the server keeps the new body (engine.pin): the client's root updates are not taken
		unpinnedAt = -math.huge,
	}
	local client: any = {
		state = nil :: State?,
		keys = nil :: Keys?,
		running = false,
		events = {} :: { Event },
		frame = 0,
		write = nil :: { x: number, y: number, z: number }?, -- a root the server wrote, not yet seen by the controller
		lastRoot = -math.huge,
		clockBase = 0,
		recoveries = 0, -- river recoveries the client made
		visited = {} :: { [number]: boolean }, -- routes the client's motor ran
		lastT = 0,
	}
	rig.client = client
	local function actorKey(): string
		return `squirrel_{server.actor}`
	end
	client.link = MotorLink.new(function(b0: buffer)
		local b = b0
		local cheatPacket = opts.packetCheat
		if cheatPacket then
			local q, e, snap = SquirrelWire.decode(b0)
			if cheatPacket(snap, rig.t) == false then
				return
			end
			b = SquirrelWire.encode(q, e, snap :: any)
		end
		local sentAt = rig.t
		if opts.silent and opts.silent(sentAt) then
			return
		end
		local arrival = upArrival(sentAt)
		if arrival == nil then
			return
		end
		at(arrival, function()
			-- the server takes the packet for whichever body the player holds when it arrives (Boot/Game)
			if server.actor == 0 then
				return
			end
			local c0 = os.clock()
			local seq, epoch, snapshot = SquirrelWire.decode(b)
			packets += 1
			local v =
				rig.movement:packet(actorKey(), "squirrel", { seq = seq, epoch = epoch, snapshot = snapshot }, rig.t)
			serverSeconds += os.clock() - c0
			if v.accepted then
				accepted += 1
			end
			for _, x in v.violations or {} do
				if #violations < 40 then
					table.insert(
						violations,
						`t={string.format("%.2f", rig.t)} {x.code}: {x.detail} (sent {string.format("%.2f", sentAt)})`
					)
				end
			end
		end)
	end)

	local vworld = opts.vworld
	local boosted = opts.boosted == true
	local validator = MoveValidator.new(vworld, {
		boostOf = function(_id: any): boolean
			return boosted
		end,
		-- the engine's round trip (Player:GetNetworkPing): twice the one-way latency now, and the jitter's mean
		pingOf = function(_id: any): number?
			if opts.pingOf then
				return opts.pingOf(rig.t)
			end
			local base = if link.latencyAt then link.latencyAt(rig.t) else latency
			return 2 * base + jitter
		end,
	})
	local movement = MovementService.new({
		validator = validator,
		enforce = opts.enforce ~= false,
		poseOf = function(_actor: any): (number?, number?, number?)
			return server.root.x, server.root.y, server.root.z
		end,
		engine = {
			correct = function(id: any, msg: any)
				if id ~= actorKey() then
					return
				end
				if msg.snap then
					rig.firstSnap = rig.firstSnap or rig.t
					server.root = { x = msg.x, y = msg.y, z = msg.z }
					server.rootSent = rig.t
					local w = { x = msg.x, y = msg.y, z = msg.z }
					write(function()
						client.write = w
					end)
				end
				reliable(function()
					if not opts.ignoreCorrections then
						client.link:offer(msg)
					end
				end)
			end,
			pin = function(id: any, on: boolean)
				if id ~= actorKey() then
					return
				end
				server.pinned = on
				if not on then
					server.unpinnedAt = rig.t
				end
			end,
			hold = function(_id: any, x: number, y: number, z: number, _seconds: number)
				holds += 1
				server.root = { x = x, y = y, z = z }
				server.rootSent = rig.t
			end,
		},
	})
	rig.movement = movement

	-- the client's controller --------------------------------------------------------------------------------
	local function frameDt(): number
		local f = opts.fps
		if type(f) == "function" then
			return f(client.frame, rig.t)
		end
		return 1 / ((f :: number?) or 60)
	end
	local function startController(state: State, keys: Keys)
		client.state = state
		client.keys = keys
		state.clock = client.link:resumeClock()
		client.running = true
		client.fresh = true
		client.events = {}
		client.write = nil
	end
	local function clientFrame(dt: number)
		local state = client.state :: State
		local world = opts.world
		if not opts.ignoreCorrections then
			client.link:apply(state, rig.t)
		end
		local w = client.write
		client.write = nil
		if w and not client.link:echo(w.x, w.y, w.z, 0, rig.t) then
			-- moved by the server: the motor restarts where the body now is (Controllers/Squirrel)
			local g = world.groundAt(w.x, w.z, w.y)
			local air = w.y - g > SquirrelMotor.params.glueMin
			SquirrelMotor.place(state, w.x, if air then w.y else g, w.z, not air)
		end
		local inp = (client.keys :: Keys)(rig.t, state, client.events)
		local step = math.min(dt, SquirrelMotor.params.frameDtCap)
		local _, events = SquirrelMotor.step(state, inp, step, world)
		client.events = events
		if state.routeId then
			client.visited[state.routeId] = true
		end
		if opts.clockRate and opts.clockRate ~= 1 then
			state.clock += step * (opts.clockRate - 1)
		end
		if opts.cheat then
			opts.cheat(state, inp, rig.t, world)
		end
		if state.routeId == nil then
			local rx, ry, rz = Recovery.riverFall(state.x, state.y, state.z)
			if rx and ry and rz then
				SquirrelMotor.place(state, rx, ry, rz, true)
				client.link:urgent()
				client.recoveries += 1
			end
		end
		client.link:tick(state)
		-- the root's replication up (physics, unreliable, the newest wins)
		if rig.t - client.lastRoot >= 1 / rootHz - 1e-9 then
			client.lastRoot = rig.t
			local sentAt = rig.t
			local p = { x = state.x, y = state.y, z = state.z }
			if opts.rootCheat then
				opts.rootCheat(p, rig.t, state)
			end
			local arrival = upArrival(sentAt)
			if arrival then
				at(arrival, function()
					if
						sentAt > server.rootSent
						and not server.riding
						and not server.held
						and not server.pinned
						and sentAt >= server.unpinnedAt
					then
						server.rootSent = sentAt
						server.root = p
					end
				end)
			end
		end
	end

	-- the server's watch, as Boot/Game.watchSquirrels ------------------------------------------------------------
	local function watch()
		if server.actor ~= 0 then
			local id = actorKey()
			if server.riding ~= server.onLift then
				server.onLift = server.riding
				movement:suspend(id, server.riding)
				if not server.riding then
					movement:teleported(id, server.root.x, server.root.y, server.root.z, "ride", rig.t)
				end
			end
			if not server.riding then
				local c0 = os.clock()
				movement:watch(id, server.root.x, server.root.y, server.root.z, rig.t)
				serverSeconds += os.clock() - c0
			end
		end
	end

	-- server events ------------------------------------------------------------------------------------------
	rig.possess = function(_self: any, state: State, keys: Keys)
		server.count += 1
		server.actor = server.count
		server.root = { x = state.x, y = state.y, z = state.z }
		server.rootSent = rig.t
		movement:onHandoff({ id = actorKey(), species = "squirrel" }, "player", "possess")
		local epoch = movement:epochOf(actorKey())
		local s = SquirrelMotor.clone(state)
		local load = opts.loadSeconds or 0
		reliable(function()
			if load <= 0 then
				client.link:setEpoch(epoch)
				startController(s, keys)
				return
			end
			-- (PossessionClient: the grant is taken once the body has streamed in)
			at(rig.t + load, function()
				client.link:setEpoch(epoch)
				startController(s, keys)
			end)
		end)
	end
	rig.handoff = function(self: any, state: State, keys: Keys)
		movement:onHandoff({ id = actorKey(), species = "squirrel" }, "player", "release")
		self:possess(state, keys)
	end
	rig.release = function(_self: any)
		movement:onHandoff({ id = actorKey(), species = "squirrel" }, "player", "release")
		server.actor = 0 -- (no body: packets still arriving are dropped, as Boot/Game does)
		reliable(function()
			client.running = false
		end)
	end
	rig.teleport = function(_self: any, x: number, y: number, z: number, why: string)
		server.root = { x = x, y = y, z = z }
		server.rootSent = rig.t
		movement:teleported(actorKey(), x, y, z, why, rig.t)
		local w = { x = x, y = y, z = z }
		write(function()
			client.write = w
		end)
	end
	-- a move of the body the server makes and tells the validator nothing of (what every server move must not be)
	rig.unreported = function(_self: any, x: number, y: number, z: number)
		server.root = { x = x, y = y, z = z }
		server.rootSent = rig.t
		local w = { x = x, y = y, z = z }
		write(function()
			client.write = w
		end)
	end
	rig.server = server
	rig.board = function(_self: any)
		server.riding = true
		reliable(function()
			client.running = false -- DeviceGranted { device = "ride" }: the controller stops
		end)
	end
	rig.alight = function(_self: any, x: number, y: number, z: number)
		server.root = { x = x, y = y, z = z }
		server.rootSent = rig.t
		server.riding = false
		local w = { x = x, y = y, z = z }
		write(function()
			client.write = w
		end)
		local keys = client.keys
		reliable(function()
			-- DeviceReleased: back on foot where the server put it (a fresh controller at the root)
			local s = SquirrelMotor.new(x, y, z)
			startController(s, keys)
		end)
	end

	rig.run = function(_self: any, seconds: number)
		local stop = rig.t + seconds
		local nextFrame = rig.t
		local nextWatch = math.ceil(rig.t * 15 + 1e-9) / 15
		while true do
			local te = if #queue > 0 then queue[1].t else math.huge
			local tf = if client.running then nextFrame else math.huge
			local t = math.min(te, tf, nextWatch)
			if t > stop then
				break
			end
			rig.t = t
			if t == te then
				local e = table.remove(queue, 1) :: Ev
				e.fn()
			elseif t == tf then
				-- this frame's time is the time since the controller's last frame (a fresh controller: one frame)
				local since = t - client.lastT
				local dt = if client.fresh or since <= 0 then frameDt() else since
				client.fresh = false
				client.frame += 1
				clientFrame(dt)
				client.lastT = t
				nextFrame = t + frameDt()
			else
				watch()
				nextWatch = t + 1 / 15
			end
			if not client.running then
				nextFrame = math.max(nextFrame, rig.t)
			end
		end
		rig.t = stop
	end

	rig.result = function(_self: any): Result
		local st = movement:stats()
		return {
			snaps = st.snaps,
			reasons = table.clone(st.reasons),
			holds = holds,
			firstSnap = rig.firstSnap,
			packets = packets,
			accepted = accepted,
			stale = st.stale,
			violations = violations,
			sent = client.link.sent,
			serverMsPerTick = serverSeconds * 1000 / math.max(1, rig.t * 60),
			recoveries = client.recoveries,
			visited = client.visited,
			frames = client.frame,
			seconds = rig.t,
			root = table.clone(server.root),
			client = client.state,
		}
	end

	return rig :: Rig
end

export type Town = {
	world: any, -- the client's motor world: the S3 town with the houses
	noWalls: any, -- the same with no walls (a client that walks through them)
	vworld: any, -- the validator's world over it (the live wall and floor rays over the houses)
	boxes: { TestWorld.Box },
	wall: ValidatorWorld.Ray,
	down: ValidatorWorld.Ray,
	startAt: (rng: Rng.Rng) -> State, -- on the ground near a random trunk of the centre
	driven: (rng: Rng.Rng, boosted: boolean?) -> Keys, -- the S3 driver: leaps, pounces, sprints and transfers
	openStart: () -> State, -- the S3 harness's open ground (no route, no house)
}

-- town(): the town every rig spec plays in: the S3 world (tests/cheat/TestWorld: the harvest's 1,332 routes on v5.4's
-- flat core) with houses among the trees for walls (boxes clear of every route by 4 studs), judged by the live wall
-- and floor rays (Server/Movement/ValidatorWorld) over the boxes.
function LiveRig.town(): Town
	local base = TestWorld.build()
	local boxes: { TestWorld.Box } = {}
	local rng = Rng.new(99)
	local tries = 0
	while #boxes < 14 and tries < 400 do
		tries += 1
		local cx, cz = (rng.next() * 2 - 1) * Units.st(80), (rng.next() * 2 - 1) * Units.st(80)
		local hw, hd = 6 + rng.next() * 6, 6 + rng.next() * 6
		if base.index:nearest(cx, base.groundHeight + 3, cz, math.max(hw, hd) + 6) == nil then
			table.insert(boxes, { minX = cx - hw, maxX = cx + hw, minZ = cz - hd, maxZ = cz + hd, top = 14 })
		end
	end
	local world = TestWorld.build({ boxes = boxes })
	local function wall(ox: number, oy: number, oz: number, dx: number, _dy: number, dz: number): boolean
		return TestWorld.segmentCrossesBox(boxes, ox, oz, ox + dx, oz + dz, oy)
	end
	local function down(ox: number, oy: number, oz: number, _dx: number, dy: number, _dz: number): boolean
		local lo = oy + dy
		if lo <= 0 and oy >= 0 then
			return true
		end
		for _, b in boxes do
			if ox > b.minX and ox < b.maxX and oz > b.minZ and oz < b.maxZ and b.top >= lo and b.top <= oy then
				return true
			end
		end
		return false
	end
	local vworld = ValidatorWorld.build(world, { wall = wall, down = down })
	local targets = Driver.targetsAround(world, 0, 0, Units.st(95))
	local noWalls: any = table.clone(world)
	noWalls.blocked, noWalls.blockedCore, noWalls.blockedHalf = nil, nil, nil
	return {
		world = world,
		noWalls = noWalls,
		vworld = vworld,
		boxes = boxes,
		wall = wall,
		down = down,
		startAt = function(r: Rng.Rng): State
			local trunk = targets[math.floor(r.next() * #targets) + 1]
			local foot = world.registry:foot(trunk)
			local angle = r.next() * math.pi * 2
			return SquirrelMotor.new(
				foot.x + math.sin(angle) * Units.st(6),
				world.groundHeight,
				foot.z + math.cos(angle) * Units.st(6)
			)
		end,
		driven = function(r: Rng.Rng, boosted: boolean?): Keys
			local d = Driver.new(world, r, targets)
			return function(_t: number, state: State, events: { Event }): Input
				if boosted then
					state.boostRemaining = 30
				end
				return d:input(state, events, 1 / 60)
			end
		end,
		openStart = function(): State
			local g = Harness.OPEN_GROUND
			return SquirrelMotor.new(
				Units.st((g.minX + g.maxX) / 2),
				world.groundHeight,
				Units.st((g.minZ + g.maxZ) / 2)
			)
		end,
	}
end

-- A one-line account of a result for the spec's output.
function LiveRig.describe(name: string, r: Result): string
	local reasons = {}
	for k, v in r.reasons do
		table.insert(reasons, `{k}={v}`)
	end
	table.sort(reasons)
	return `{name}: {r.snaps} snaps{if #reasons > 0 then " (" .. table.concat(reasons, " ") .. ")" else ""}, {r.packets} packets in {string.format(
		"%.0f",
		r.seconds
	)} s ({r.accepted} judged, {r.stale} before the client knew of a move)`
end

return LiveRig
