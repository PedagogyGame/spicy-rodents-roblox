--!strict
-- tools/sim/lib/Replay: the headless replay of the vehicle pose stream, end to end, on the game's own code.
--
--   server   every server frame (a seeded pacer gives its length) is Server/Boot/Game's step for traffic:
--            the Heartbeat clamp (PoseStream.MAX_FRAME_DT), the clock, then TrafficService.frame, which
--            steps the real fleet and sends through the real Net (BufferCodec, 13-byte records, stamp)
--   network  each send is delayed or lost by a seeded model (lib/NetModel)
--   client   every client frame (its own pacer) is Client/Render/VehicleView's frame: the packets that
--            have arrived go through PoseStream's receiver with the client clock, then Ghost.view (the
--            pure half of Ghost.render) samples the buffer and seats every vehicle on World/Height
-- Nothing of the game's logic is copied here: the spec tests/unit/traffic_posestream pins the game to
-- the same entry points (TrafficService.frame, PoseStream.newReceiver():packet, Ghost.view).
--
-- Three recordings come out of it and go to the detectors (lib/Detect; one file each in
-- tools/sim/detectors): every server tick's true state, every send, and every client frame with, per
-- vehicle, the pose the player sees, the server's true pose at that instant, and the true pose at the
-- instant the frame is drawing. `run` returns the incidents, the counts and the statistics.
--
-- A scenario (one file in tools/sim/scenarios) chooses the vehicles, forces states and supplies the
-- people the fleet reacts to:
--   return {
--     name = "<file name>", about = "one line",
--     entries = { Fleet entries }?,   -- default: the game's 25 (Traffic/Fleet.ENTRIES)
--     trafficSeed = 7?, seconds = 60?, net = "ideal"?, server = "steady"?, client = "steady"?,
--     setup = function(sim) end?,     -- once: sim.traffic is the real service; force vehicle states here
--     frame = function(sim) end?,     -- every server frame before the step: timed actions (dispatches)
--     hitch = function(sim, dt) return dt end?,   -- the length of the next server frame: return a longer
--                                     -- one to stall the server at a chosen moment
--     world = function(sim) return { people = {...}, squirrels = {...} } end?,
--     expect = { none = { kinds }, some = { kinds } }?,   -- what must hold (the regression spec and --check)
--     known = { kinds }?,             -- glitches this scenario shows TODAY: reported, and checked to still
--                                     -- show (the instrument must keep seeing them); whoever fixes one
--                                     -- moves its kind to expect.none
--     ci = 20?,                       -- seconds: tests/unit/traffic_replay.spec runs the scenario this long
--   }
--
-- Interface: defaults(); settings(opts) -> Settings; scenario(name) -> Scenario; scenarios() -> { name };
--            run(opts) -> Result; check(result) -> { failures }
-- State: World/Height is configured with the generated terrain extensions for the run and reset after.

local fs = require("@lune/fs")
local serde = require("@lune/serde")

local Data = require("@shared/Data")
local Ghost = require("@shared/Traffic/Ghost")
local PoseStream = require("@shared/Traffic/PoseStream")
local Net = require("@shared/Net/Net")
local Schemas = require("@shared/Net/Schemas")
local Height = require("@shared/World/Height")
local RoadSurface = require("@shared/World/RoadSurface")
local Colliders = require("@shared/World/Colliders")
local Ground = require("@shared/World/Ground")
local Town = require("@shared/World/Town")
local Rng = require("@shared/Util/Rng")
local Units = require("@shared/Config/Units")
local TrafficService = require("@server/Traffic/TrafficService")

local Baked = require("./Baked")
local Detect = require("./Detect")
local NetModel = require("./NetModel")
local Truth = require("./Truth")

local Replay = {}

export type Scenario = {
	name: string,
	about: string,
	entries: { any }?,
	trafficSeed: number?,
	seconds: number?,
	net: string?,
	server: string?,
	client: string?,
	control: any?,
	sceneSecs: number?,
	setup: ((sim: Sim) -> ())?,
	frame: ((sim: Sim) -> ())?,
	hitch: ((sim: Sim, dt: number) -> number)?,
	world: ((sim: Sim) -> any)?,
	expect: { none: { string }?, some: { string }? }?,
	known: { string }?,
	ci: number?,
}

export type Sim = {
	traffic: any, -- the real TrafficService
	scenario: Scenario,
	settings: Settings,
	clock: number, -- the server clock (stamps the sends)
	wall: number, -- wall-clock seconds since the replay started
	frames: number, -- server frames run
	rng: Rng.Rng, -- the scenario's own seeded stream
	state: { [string]: any }, -- scratch for the scenario
	st: (u: number) -> number, -- HTML units to studs
}

export type Settings = {
	scenario: string,
	seconds: number,
	seed: number,
	trafficSeed: number,
	net: NetModel.NetProfile,
	netName: string,
	server: NetModel.PaceProfile,
	serverName: string,
	client: NetModel.PaceProfile,
	clientName: string,
	uptime: number, -- seconds the server clock has already run when the replay starts
	clockSkew: number, -- the client clock's constant error (seconds)
	clockDrift: number, -- and its drift (seconds per second)
	phase: number, -- where in a server frame the client's first frame falls (0..1)
	warmup: number, -- seconds at the start the detectors ignore
	detectors: { string }?, -- names to run (default: all)
	thresholds: { [string]: number }, -- "detector.key" = value overrides
	maxPerKind: number,
	keepFrames: boolean, -- keep every frame in the result (short runs only)
	trace: { from: number, to: number, vehicles: { number }? }?,
}

export type Result = {
	settings: Settings,
	scenario: Scenario,
	incidents: { Detect.Incident },
	counts: { [string]: number },
	dropped: { [string]: number },
	detectors: { Detect.Def },
	stats: { [string]: any },
	frames: { Detect.Frame }?,
	trace: { { [string]: any } }?,
	vehicles: { [number]: any },
}

local SCENARIOS = "tools/sim/scenarios"

function Replay.defaults(): Settings
	return {
		scenario = "fleet",
		seconds = 60,
		seed = 1,
		trafficSeed = 7, -- Server/Boot/Game: TrafficService.new({ ..., seed = 7 })
		net = NetModel.NET.ideal,
		netName = "ideal",
		server = NetModel.SERVER.steady,
		serverName = "steady",
		client = NetModel.CLIENT.steady,
		clientName = "steady",
		uptime = 0,
		clockSkew = 0,
		clockDrift = 0,
		phase = 0.37,
		warmup = 1,
		detectors = nil,
		thresholds = {},
		maxPerKind = 20000,
		keepFrames = false,
		trace = nil,
	}
end

function Replay.scenarios(): { string }
	local names = {}
	for _, entry in fs.readDir(SCENARIOS) do
		if string.sub(entry, -5) == ".luau" then
			table.insert(names, string.sub(entry, 1, -6))
		end
	end
	table.sort(names)
	return names
end

function Replay.scenario(name: string): Scenario
	if not fs.isFile(`{SCENARIOS}/{name}.luau`) then
		error(`no scenario '{name}' (have: {table.concat(Replay.scenarios(), ", ")})`, 0)
	end
	local sc = (require :: any)(`../scenarios/{name}`) :: Scenario
	assert(sc.name == name, `scenario file {name}.luau must return name = "{name}"`)
	return sc
end

-- settings(opts): the defaults, then the scenario's own (seconds, profiles, seed), then `opts`.
-- Profiles may be given by name (net = "typical") or as a table of the profile's fields.
function Replay.settings(opts: { [string]: any }?): Settings
	local o: { [string]: any } = opts or {}
	local s = Replay.defaults()
	local sc = Replay.scenario(o.scenario or s.scenario)
	s.scenario = sc.name
	local function profile(kind: string, table_: { [string]: any }, value: any)
		if value == nil then
			return
		end
		local st = s :: any
		if type(value) == "string" then
			st[kind] = table.clone(table_[value] or error(`no {kind} profile '{value}'`, 0))
			st[kind .. "Name"] = value
		else
			st[kind] = table.clone(value)
			st[kind .. "Name"] = "custom"
		end
	end
	profile("net", NetModel.NET, sc.net)
	profile("server", NetModel.SERVER, sc.server)
	profile("client", NetModel.CLIENT, sc.client)
	profile("net", NetModel.NET, o.net)
	profile("server", NetModel.SERVER, o.server)
	profile("client", NetModel.CLIENT, o.client)
	s.net, s.server, s.client = table.clone(s.net), table.clone(s.server), table.clone(s.client)
	s.seconds = o.seconds or sc.seconds or s.seconds
	s.trafficSeed = o.trafficSeed or sc.trafficSeed or s.trafficSeed
	for _, key in { "seed", "uptime", "clockSkew", "clockDrift", "phase", "warmup", "maxPerKind", "keepFrames" } do
		if o[key] ~= nil then
			(s :: any)[key] = o[key]
		end
	end
	if o.fps then
		s.client.hz = o.fps
	end
	-- single fields of a profile: netSet = { loss = 0.05 }, serverSet = { ... }, clientSet = { ... }
	for kind, target in { netSet = s.net, serverSet = s.server, clientSet = s.client } :: { [string]: any } do
		for key, value in (o[kind] or {}) :: { [string]: any } do
			assert(target[key] ~= nil, `{kind}: no setting '{key}'`)
			target[key] = value
		end
	end
	s.detectors = o.detectors
	s.thresholds = o.thresholds or {}
	s.trace = o.trace
	return s
end

-- The game's town for the detectors: World/Ground over the town's paving (roads sit 0.14 st above the
-- terrain) and the bridge deck, the road strips and lots (World/Town) and the buildings
-- (World/Colliders). Built once per process.
local townWorld: { town: any, colliders: any, groundAt: (x: number, z: number, refY: number) -> number }? = nil
local function town(): { town: any, colliders: any, groundAt: (x: number, z: number, refY: number) -> number }
	local w = townWorld
	if w == nil then
		local data = Data.default()
		local t = Town.fromData(data)
		w = { town = t, colliders = Colliders.fromData(data), groundAt = Ground.world({ town = t }).groundAt }
		townWorld = w
	end
	return w
end

local function histogram(step: number, size: number)
	local bins = table.create(size, 0)
	local h = { n = 0, max = 0, sum = 0 }
	local function add(value: number)
		h.n += 1
		h.sum += value
		if value > h.max then
			h.max = value
		end
		local i = math.min(size, math.floor(value / step) + 1)
		bins[i] += 1
	end
	local function quantile(q: number): number
		if h.n == 0 then
			return 0
		end
		local want, seen = q * h.n, 0
		for i = 1, size do
			seen += bins[i]
			if seen >= want then
				return math.min(h.max, i * step)
			end
		end
		return h.max
	end
	local function summary(): { [string]: number }
		return {
			n = h.n,
			mean = if h.n > 0 then h.sum / h.n else 0,
			p50 = quantile(0.5),
			p95 = quantile(0.95),
			p99 = quantile(0.99),
			max = h.max,
		}
	end
	return add, summary
end

function Replay.run(opts: { [string]: any }?): Result
	local settings = Replay.settings(opts)
	local scenario = Replay.scenario(settings.scenario)
	local data = Data.default()

	-- the terrain both ends read (the server boots it in WorldTerrain, the client in ClientWorld)
	Height.configure(data:module("TerrainExtensions"))
	local ok, result = pcall(function(): Result
		-- the server, as Server/Boot/Game builds it
		local traffic = TrafficService.new({
			lanes = data:lanes(),
			roads = data:roads(),
			heightAt = Height.at,
			seed = settings.trafficSeed,
			entries = scenario.entries,
			control = scenario.control,
			sceneSecs = scenario.sceneSecs,
		})
		-- the kinds reach the client as JSON in the PlayNet folder's TrafficKinds attribute
		local kinds: Ghost.Kinds = {}
		local kindsJson: { [string]: any } = {}
		for id, k in traffic:kinds() do
			kindsJson[tostring(id)] = k
		end
		for key, k in serde.decode("json", serde.encode("json", kindsJson)) :: { [string]: any } do
			kinds[tonumber(key) :: number] = k
		end

		local vehicles: { [number]: any } = {}
		for _, e in traffic.entries do
			local v = traffic.byId[e.id]
			vehicles[e.id] =
				{ id = e.id, name = e.name, kind = e.kind, class = e.class, box = v.box, entry = e, live = v }
		end

		local network = NetModel.network(settings.net, settings.seed)
		local serverPace = NetModel.pacer(settings.server, settings.seed * 2 + 1)
		local clientPace = NetModel.pacer(settings.client, settings.seed * 2 + 2)

		local sim: Sim = {
			traffic = traffic,
			scenario = scenario,
			settings = settings,
			clock = settings.uptime,
			wall = 0,
			frames = 0,
			rng = Rng.new(settings.seed * 31 + 5),
			state = {},
			st = Units.st,
		}

		-- the detectors
		local truth = Truth.new()
		local book = Detect.newBook(settings)
		local townData = town()
		local env = {
			truth = truth,
			vehicles = vehicles,
			heightAt = Height.at,
			surfaceAt = townData.groundAt,
			bakedAt = function(x: number, z: number, maxY: number?): number
				return (Baked.get().at(x, z, maxY))
			end,
			town = townData.town,
			colliders = townData.colliders,
		}
		local defs: { Detect.Def } = {}
		local hooks: { Detect.Hooks } = {}
		for _, def in Detect.load() do
			if settings.detectors == nil or table.find(settings.detectors, def.name) then
				table.insert(defs, def)
				table.insert(hooks, def.new(book:ctx(def, env)))
			end
		end
		for _, name in settings.detectors or {} do
			local found = false
			for _, def in defs do
				found = found or def.name == name
			end
			assert(found, `no detector '{name}'`)
		end

		-- the wire: the real Net over a transport that hands every payload to the network model
		local flights: { { at: number, payload: buffer, send: Detect.Send } } = {}
		local sends = 0
		local net = Net.new({
			send = function(_player: any, name: string, payload: any)
				assert(name == PoseStream.REMOTE, `unexpected remote {name}`)
				sends += 1
				local wire = Net.decodeStream(Schemas.VehiclePose, payload)
				local stamp = Ghost.takeStamp(wire) or 0 / 0
				local poses = {}
				for _, r in wire do
					poses[r.id] = Ghost.decode(r)
				end
				local arrivals = network:send(sim.wall)
				local send: Detect.Send = {
					n = sends,
					wall = sim.wall,
					clock = sim.clock,
					stamp = stamp,
					age = traffic.acc,
					poses = poses,
					lost = #arrivals == 0,
					arrival = arrivals[1],
					processed = nil,
				}
				for _, at in arrivals do
					-- keep the flights in arrival order (the list is a handful long)
					local i = #flights + 1
					while i > 1 and flights[i - 1].at > at do
						i -= 1
					end
					table.insert(flights, i, { at = at, payload = payload, send = send })
				end
				for _, h in hooks do
					if h.send then
						h.send(send)
					end
				end
			end,
			players = function(): { any }
				return {}
			end,
		})

		local tickDt = traffic.tick
		traffic.onTick = function(_svc: any)
			truth:record(sim.clock, sim.wall, tickDt, traffic.vehicles)
			local tick: Detect.Tick =
				{ n = truth.ticks, clock = sim.clock, wall = sim.wall, dt = tickDt, vehicles = traffic.vehicles }
			for _, h in hooks do
				if h.tick then
					h.tick(tick)
				end
			end
		end

		if scenario.setup then
			scenario.setup(sim)
		end

		-- one server frame: Server/Boot/Game's Heartbeat handler and step, the traffic part
		local emptyWorld = {}
		local function serverFrame(frameDt: number)
			sim.wall += frameDt
			sim.frames += 1
			local dt = math.min(frameDt, PoseStream.MAX_FRAME_DT)
			sim.clock += dt
			if scenario.frame then
				scenario.frame(sim)
			end
			local world = if scenario.world then scenario.world(sim) else emptyWorld
			traffic:frame(dt, sim.clock, world or emptyWorld, net)
		end

		-- the client, as Client/Render/VehicleView builds it
		local receiver = PoseStream.newReceiver()
		local heightAt = RoadSurface.ground(RoadSurface.new(data:roads()), Height.at)

		local addLag, lagSummary = histogram(0.05, 4000) -- studs behind the server's pose right now
		local addLagMs, lagMsSummary = histogram(1, 3000) -- the same as time: studs / true speed
		local addRecon, reconSummary = histogram(0.02, 5000) -- studs from the pose being drawn
		local stats = {
			clientFrames = 0,
			starvedFrames = 0,
			emptyFrames = 0,
			delivered = 0,
			lateOrder = 0,
			vehicleFrames = 0,
		}
		local kept: { Detect.Frame }? = if settings.keepFrames then {} else nil
		local trace: { { [string]: any } }? = if settings.trace then {} else nil
		local traceIds: { [number]: boolean }? = nil
		if settings.trace and settings.trace.vehicles then
			traceIds = {}
			for _, id in settings.trace.vehicles do
				(traceIds :: any)[id] = true
			end
		end

		local function nextServerFrame(): number
			local dt = serverPace:next()
			return if scenario.hitch then scenario.hitch(sim, dt) else dt
		end
		local pendingServer = nextServerFrame()
		local clientWall = settings.phase / settings.server.hz
		local prevNow: number? = nil
		local prevV: { [number]: Detect.Sample } = {}
		local lastStamp = -math.huge
		local frameNo = 0
		local sortedIds: { number } = {}
		for id in vehicles do
			table.insert(sortedIds, id)
		end
		table.sort(sortedIds)

		while clientWall <= settings.seconds do
			-- the server runs up to this instant
			while sim.wall + pendingServer <= clientWall do
				serverFrame(pendingServer)
				pendingServer = nextServerFrame()
			end
			-- the client clock: workspace:GetServerTimeNow() (wall time plus its error)
			local now = clientWall + settings.clockSkew + settings.clockDrift * clientWall
			-- packets that have arrived are handled before the frame is drawn, all at this frame's clock
			local packets = 0
			while flights[1] and flights[1].at <= clientWall do
				local f = table.remove(flights, 1) :: { at: number, payload: buffer, send: Detect.Send }
				receiver:packet(f.payload, now)
				packets += 1
				stats.delivered += 1
				if f.send.stamp < lastStamp then
					stats.lateOrder += 1
				end
				lastStamp = math.max(lastStamp, f.send.stamp)
				f.send.processed = clientWall
				for _, h in hooks do
					if h.deliver then
						h.deliver(f.send, clientWall)
					end
				end
			end

			frameNo += 1
			local buf = receiver.buffer
			local nSnaps = #buf.snaps
			local offset = receiver.clock.offset
			local ref: number? = if offset then now - buf.delay - offset else nil
			local starved = if nSnaps > 0 then (now - buf.delay) - buf.snaps[nSnaps].t else 0
			local v: { [number]: Detect.Sample } = {}
			local frame: Detect.Frame = {
				i = frameNo,
				t = clientWall,
				dt = if prevNow then now - prevNow else 1 / settings.client.hz,
				now = now,
				clock = sim.clock,
				ref = ref,
				starved = starved,
				snaps = nSnaps,
				offset = offset,
				packets = packets,
				v = v,
				pv = prevV,
				ids = {},
			}
			-- Ghost.render's pure half: what every root part is given this frame
			Ghost.view(buf, now, kinds, heightAt, function(id, p, _k, x, y, z, yaw, pitch)
				local live = traffic.byId[id]
				local s: Detect.Sample = {
					id = id,
					vis = p.visible,
					x = x,
					y = y,
					z = z,
					yaw = yaw,
					pitch = pitch,
					speed = p.speed,
					snap = p.teleported,
					stopped = p.stopped,
					tvis = live.visible,
					tx = live.x,
					ty = live.y,
					tz = live.z,
					tyaw = live.yaw,
					tspeed = live.speed,
					rok = false,
					rvis = false,
					rx = 0,
					rz = 0,
					ryaw = 0,
					rspeed = 0,
				}
				if ref then
					local r = truth:at(id, ref)
					if r and not r.stale then
						s.rok, s.rvis, s.rx, s.rz, s.ryaw, s.rspeed = true, r.visible, r.x, r.z, r.yaw, r.speed
					end
				end
				v[id] = s
			end)
			for _, id in sortedIds do
				local s = v[id]
				if s then
					table.insert(frame.ids, id)
					stats.vehicleFrames += 1
					if frame.t >= settings.warmup and s.vis and s.tvis then
						local lag = math.sqrt((s.x - s.tx) ^ 2 + (s.z - s.tz) ^ 2)
						addLag(lag)
						if s.tspeed > 5 then
							addLagMs(lag / s.tspeed * 1000)
						end
						if s.rok and s.rvis then
							addRecon(math.sqrt((s.x - s.rx) ^ 2 + (s.z - s.rz) ^ 2))
						end
					end
				end
			end
			stats.clientFrames += 1
			if nSnaps == 0 then
				stats.emptyFrames += 1
			elseif starved > 0 then
				stats.starvedFrames += 1
			end

			for _, h in hooks do
				if h.frame then
					h.frame(frame)
				end
			end
			book:sweep(frame.t)

			if kept then
				table.insert(kept, frame)
			end
			if trace and settings.trace and frame.t >= settings.trace.from and frame.t <= settings.trace.to then
				for _, id in frame.ids do
					if traceIds == nil or traceIds[id] then
						local s = v[id]
						local live = traffic.byId[id]
						table.insert(trace, {
							frame = frame.i,
							t = frame.t,
							dt = frame.dt,
							packets = packets,
							snaps = nSnaps,
							starved = starved,
							offset = offset or 0 / 0,
							id = id,
							vis = s.vis,
							x = s.x,
							y = s.y,
							z = s.z,
							yaw = s.yaw,
							pitch = s.pitch,
							speed = s.speed,
							snap = s.snap,
							tvis = s.tvis,
							tx = s.tx,
							tz = s.tz,
							tyaw = s.tyaw,
							tspeed = s.tspeed,
							phase = live.phase,
							s = live.s,
							rvis = s.rvis,
							rx = if s.rok then s.rx else 0 / 0,
							rz = if s.rok then s.rz else 0 / 0,
							ryaw = if s.rok then s.ryaw else 0 / 0,
						})
					end
				end
			end

			prevV = v
			prevNow = now
			clientWall += clientPace:next()
		end

		for _, h in hooks do
			if h.finish then
				h.finish()
			end
		end
		book:finish()
		traffic.onTick = nil

		local svc = traffic:stats()
		return {
			settings = settings,
			scenario = scenario,
			incidents = book.incidents,
			counts = book.counts,
			dropped = book.dropped,
			detectors = defs,
			vehicles = vehicles,
			frames = kept,
			trace = trace,
			stats = {
				seconds = settings.seconds,
				serverFrames = sim.frames,
				serverClock = sim.clock,
				serverLongestFrame = serverPace.stats.longest,
				serverSpikes = serverPace.stats.spikes,
				serverStalls = serverPace.stats.stalls,
				ticks = svc.ticks,
				tickMeanMs = if svc.ticks > 0 then svc.ms / svc.ticks else 0,
				sends = sends,
				lost = network.stats.lost,
				reordered = network.stats.reordered,
				duplicated = network.stats.duplicated,
				delivered = stats.delivered,
				deliveredOutOfOrder = stats.lateOrder,
				clientFrames = stats.clientFrames,
				clientLongestFrame = clientPace.stats.longest,
				clientHitches = clientPace.stats.stalls + clientPace.stats.spikes,
				starvedFrames = stats.starvedFrames,
				emptyFrames = stats.emptyFrames,
				vehicleFrames = stats.vehicleFrames,
				stampOffset = receiver.clock.offset,
				detectors = book.stats,
				lagStuds = lagSummary(),
				lagMs = lagMsSummary(),
				reconStuds = reconSummary(),
				events = svc.events,
			},
		}
	end)
	Height.configure(nil)
	if not ok then
		error(result, 0)
	end
	return result
end

-- check(result): the scenario's `expect` and `known` against the counts. Returns the failures (empty:
-- all hold).
function Replay.check(result: Result): { string }
	local failures = {}
	local expect = result.scenario.expect
	if expect then
		for _, kind in expect.none or {} do
			local n = result.counts[kind] or 0
			if n > 0 then
				table.insert(failures, `{result.scenario.name}: expected no {kind}, found {n}`)
			end
		end
		for _, kind in expect.some or {} do
			if (result.counts[kind] or 0) == 0 then
				table.insert(failures, `{result.scenario.name}: expected {kind}, found none`)
			end
		end
	end
	for _, kind in result.scenario.known or {} do
		if (result.counts[kind] or 0) == 0 then
			table.insert(
				failures,
				`{result.scenario.name}: the known glitch {kind} no longer shows; if it is fixed, move it from known to expect.none in tools/sim/scenarios/{result.scenario.name}.luau`
			)
		end
	end
	return failures
end

return Replay
