--!strict
-- tools/sim/lib/Detect: what a detector is, and the bookkeeping every detector shares.
--
-- A detector is one file in tools/sim/detectors/ that returns a `Def`:
--   name        the file's name; `--detectors a,b` and `--th name.key=value` refer to it
--   kinds       { [kind] = "one line: what the player sees" } for every incident kind it can report
--   thresholds  { { key, value, unit, why } }: every number it judges by, with the reason for it
--   mergeGap    seconds: flags of one kind on one vehicle closer than this are one incident (0.25)
--   new(ctx)    -> { tick?, send?, deliver?, frame?, finish? }: the hooks the replay calls
-- The hooks see the three recordings of a replay (types below):
--   tick(Tick)        after every server simulation tick: the true state of every vehicle
--   send(Send)        when the server sends a VehiclePoses packet (decoded: stamp, poses, bits)
--   deliver(Send, at) when the client processes it (`send.lost` packets never get here)
--   frame(Frame)      after every client frame: per vehicle what the player sees (`seen`), the server's
--                     true pose at that instant (`t*`) and the true pose at the instant the client is
--                     trying to draw (`r*`, the reference: the seen pose minus what delay explains)
-- and report through `ctx`:
--   ctx.th.<key>                                    a threshold (after --th overrides)
--   ctx.flag(kind, frame, sample, magnitude, limit, unit, detail?, key?)
--                                                   this vehicle shows `kind` in this frame; consecutive
--                                                   flags merge into one incident that keeps the worst frame
--   ctx.report(incident)                            an incident that is not tied to a run of frames
--   ctx.truth                                       the true history (lib/Replay: at, window)
--   ctx.vehicles[id]                                { id, name, kind, class, box, entry }
--   ctx.surfaceAt(x, z, refY), ctx.heightAt(x, z)   the game's ground (World/Ground with the town's paving)
--   ctx.settings                                    the run's settings
--   ctx.stats                                       a table of the detector's own numbers for the report
-- Severity is magnitude / limit: how many times over its limit an incident is. It ranks "the worst".
-- Interface: load(dir?) -> { Def }; newBook(settings) -> Book; Book:ctx(def, env) -> Ctx; Book:sweep(t);
--            Book:finish(); Book.incidents; Book.counts; Book.stats; wrapAngle(a); obbOverlap(a, b);
--            inside(x, z) (studs inside the town's modelled rectangle; negative outside)
--            bench(def, opts?) -> Bench (a detector on its own, fed by hand: for its spec)

local fs = require("@lune/fs")
local Boxes = require("@shared/Traffic/Boxes")
local Height = require("@shared/World/Height")
local Truth = require("./Truth")

local Detect = {}

export type Sample = {
	id: number,
	-- seen: what Ghost.render gives the root part this frame
	vis: boolean,
	x: number,
	y: number,
	z: number,
	yaw: number,
	pitch: number,
	speed: number, -- the speed on the wire (interpolated like the pose)
	snap: boolean, -- this frame's pose is a snap to a snapshot flagged TELEPORTED
	stopped: boolean,
	-- truth now: the server's state at this wall-clock instant
	tvis: boolean,
	tx: number,
	ty: number,
	tz: number,
	tyaw: number,
	tspeed: number,
	-- reference: the true pose at the server-clock instant this frame is drawing (rok false before
	-- the first packet); rjump is the largest true step of one tick in the window around it
	rok: boolean,
	rvis: boolean,
	rx: number,
	rz: number,
	ryaw: number,
	rspeed: number,
}

export type Frame = {
	i: number, -- client frame number
	t: number, -- wall-clock seconds since the replay started
	dt: number, -- client clock seconds since the previous frame
	now: number, -- the client clock handed to Ghost.render (workspace:GetServerTimeNow())
	clock: number, -- the server's clock (the one that stamps sends) at this instant
	ref: number?, -- the server-clock instant being drawn: now - delay - the stamp clock's offset
	starved: number, -- seconds the render time is past the newest snapshot (<= 0: it has data)
	snaps: number, -- snapshots in the buffer
	offset: number?, -- the stamp clock's offset
	packets: number, -- packets processed this frame
	v: { [number]: Sample }, -- this frame's samples by vehicle id
	pv: { [number]: Sample }, -- the previous frame's
	ids: { number }, -- the ids in `v`, ascending
}

export type Tick = {
	n: number, -- tick number (1 = the first)
	clock: number, -- the server's clock in the frame that ran this tick
	wall: number,
	dt: number, -- the tick length
	vehicles: { any }, -- the live AICarMotor vehicles (x, z, yaw, visible, teleported, phase, s, ...): read, never write
}

export type Send = {
	n: number,
	wall: number, -- when the server sent it
	clock: number, -- the server's clock when it sent it
	stamp: number, -- the stamp it carries (the clock as decoded from the wire: an f32)
	poses: { [number]: any }, -- Ghost.Pose by id, decoded from the wire
	lost: boolean,
	arrival: number?, -- when it reaches the client's machine
	processed: number?, -- the wall-clock time of the client frame that handled it
}

export type Incident = {
	kind: string,
	detector: string,
	t: number,
	frame: number?,
	vehicle: number,
	name: string?,
	class: string?,
	vkind: string?,
	magnitude: number,
	limit: number,
	unit: string,
	severity: number,
	duration: number,
	frames: number,
	origin: string?, -- "sim": the server's own state did it; "stream": only the reconstruction did
	seen: { [string]: any }?,
	truth: { [string]: any }?,
	ref: { [string]: any }?,
	stream: { [string]: any }?,
	detail: { [string]: any }?,
}

export type Threshold = { key: string, value: number, unit: string, why: string }

export type Hooks = {
	tick: ((tick: Tick) -> ())?,
	send: ((send: Send) -> ())?,
	deliver: ((send: Send, at: number) -> ())?,
	frame: ((frame: Frame) -> ())?,
	finish: (() -> ())?,
}

export type Ctx = {
	th: { [string]: number },
	stats: { [string]: any },
	settings: any,
	truth: any,
	vehicles: { [number]: any },
	heightAt: (x: number, z: number) -> number,
	surfaceAt: (x: number, z: number, refY: number) -> number,
	flag: (
		kind: string,
		frame: Frame,
		s: Sample,
		magnitude: number,
		limit: number,
		unit: string,
		detail: { [string]: any }?,
		key: string?
	) -> (),
	report: (incident: { [string]: any }) -> (),
}

export type Def = {
	name: string,
	kinds: { [string]: string },
	thresholds: { Threshold },
	mergeGap: number?,
	new: (ctx: Ctx) -> Hooks,
}

local DIR = "tools/sim/detectors"

-- load(dir?): every detector in the folder, by name.
function Detect.load(dir: string?): { Def }
	local out: { Def } = {}
	local names = {}
	for _, entry in fs.readDir(dir or DIR) do
		if string.sub(entry, -5) == ".luau" then
			table.insert(names, string.sub(entry, 1, -6))
		end
	end
	table.sort(names)
	for _, name in names do
		local def = (require :: any)(`../detectors/{name}`) :: Def
		assert(def.name == name, `detector file {name}.luau must return name = "{name}"`)
		table.insert(out, def)
	end
	return out
end

function Detect.wrapAngle(a: number): number
	return math.atan2(math.sin(a), math.cos(a))
end

-- inside(x, z): studs inside the rectangle v5.4 modelled (World/Height.PLAYABLE_U: where the town, its
-- streets and the river are); negative outside. A pop well inside it happens where players are.
function Detect.inside(x: number, z: number): number
	local r, k = Height.PLAYABLE_U, Height.STUDS_PER_UNIT
	return math.min(x - r.minX * k, r.maxX * k - x, z - r.minZ * k, r.maxZ * k - z)
end

export type Obb = { x: number, z: number, yaw: number, hw: number, hl: number }

-- obbOverlap(a, b) -> depth: how far two rectangles on the ground (centre, HTML yaw, half width, half
-- length) are into each other: the smallest overlap along the four separating axes, <= 0 when apart.
function Detect.obbOverlap(a: Obb, b: Obb): number
	local dx, dz = b.x - a.x, b.z - a.z
	local depth = math.huge
	for _, yaw in { a.yaw, b.yaw } do
		local fx, fz = math.sin(yaw), math.cos(yaw)
		for pass = 1, 2 do
			-- the axis: forward on the first pass, right on the second
			local ax, az = fx, fz
			if pass == 2 then
				ax, az = fz, -fx
			end
			local function reach(o: Obb): number
				local ofx, ofz = math.sin(o.yaw), math.cos(o.yaw)
				return math.abs(ofx * ax + ofz * az) * o.hl + math.abs(ofz * ax - ofx * az) * o.hw
			end
			local overlap = reach(a) + reach(b) - math.abs(dx * ax + dz * az)
			if overlap < depth then
				depth = overlap
			end
		end
	end
	return depth
end

local function copySeen(s: Sample): { [string]: any }
	return {
		visible = s.vis,
		x = s.x,
		y = s.y,
		z = s.z,
		yaw = s.yaw,
		pitch = s.pitch,
		speed = s.speed,
		snap = s.snap,
		stopped = s.stopped,
	}
end

export type Book = {
	incidents: { Incident },
	counts: { [string]: number },
	dropped: { [string]: number },
	stats: { [string]: { [string]: any } },
	ctx: (self: Book, def: Def, env: any) -> Ctx,
	sweep: (self: Book, t: number) -> (),
	finish: (self: Book) -> (),
}

type Episode = { incident: Incident, last: number, gap: number, first: number }

-- newBook(settings): collects incidents. `settings.warmup` seconds at the start are ignored (a player
-- who has just joined sees every car appear at once; that is not a glitch), `settings.thresholds` holds
-- the "detector.key" overrides, `settings.maxPerKind` caps what is stored per kind (the count goes on).
function Detect.newBook(settings: any): Book
	local open: { [string]: Episode } = {}
	local book: Book
	local maxPerKind = settings.maxPerKind or 20000

	local function store(inc: Incident)
		local n = (book.counts[inc.kind] or 0) + 1
		book.counts[inc.kind] = n
		if n <= maxPerKind then
			table.insert(book.incidents, inc)
		else
			book.dropped[inc.kind] = (book.dropped[inc.kind] or 0) + 1
		end
	end

	book = {
		incidents = {},
		counts = {},
		dropped = {},
		stats = {},
		ctx = function(_self: Book, def: Def, env: any): Ctx
			local th: { [string]: number } = {}
			for _, item in def.thresholds do
				local override = settings.thresholds and settings.thresholds[`{def.name}.{item.key}`]
				th[item.key] = if override ~= nil then override else item.value
			end
			local gap = def.mergeGap or 0.25
			local function describe(inc: Incident)
				local info = env.vehicles[inc.vehicle]
				if info then
					inc.name, inc.class, inc.vkind = info.name, info.class, info.kind
				end
			end
			local stats = {}
			book.stats[def.name] = stats
			return {
				th = th,
				stats = stats,
				settings = settings,
				truth = env.truth,
				vehicles = env.vehicles,
				heightAt = env.heightAt,
				surfaceAt = env.surfaceAt,
				flag = function(
					kind: string,
					frame: Frame,
					s: Sample,
					magnitude: number,
					limit: number,
					unit: string,
					detail: { [string]: any }?,
					key: string?
				)
					assert(def.kinds[kind], `detector {def.name} flagged an undeclared kind {kind}`)
					if frame.t < (settings.warmup or 0) then
						return
					end
					local severity = if limit > 0 then magnitude / limit else magnitude
					local id = `{kind}|{key or s.id}`
					local ep = open[id]
					if ep == nil then
						local inc: Incident = {
							kind = kind,
							detector = def.name,
							t = frame.t,
							frame = frame.i,
							vehicle = s.id,
							magnitude = -math.huge,
							limit = limit,
							unit = unit,
							severity = -math.huge,
							duration = 0,
							frames = 0,
						}
						describe(inc)
						ep = { incident = inc, last = frame.t, gap = gap, first = frame.t }
						open[id] = ep
					end
					local inc = ep.incident
					ep.last = frame.t
					inc.frames += 1
					inc.duration = frame.t - ep.first
					if severity > inc.severity then
						-- keep the worst frame of the run
						inc.severity = severity
						inc.magnitude = magnitude
						inc.limit = limit
						inc.detail = detail
						inc.origin = if detail and detail.origin then detail.origin else inc.origin
						inc.seen = copySeen(s)
						inc.truth = { visible = s.tvis, x = s.tx, y = s.ty, z = s.tz, yaw = s.tyaw, speed = s.tspeed }
						inc.ref = if s.rok
							then { visible = s.rvis, x = s.rx, z = s.rz, yaw = s.ryaw, speed = s.rspeed }
							else nil
						inc.stream = {
							worstAt = frame.t,
							worstFrame = frame.i,
							dt = frame.dt,
							starved = frame.starved,
							snaps = frame.snaps,
							offset = frame.offset,
							clock = frame.clock,
							ref = frame.ref,
						}
						local live = env.vehicles[s.id] and env.vehicles[s.id].live
						if live then
							local t = inc.truth :: { [string]: any }
							t.phase, t.s, t.dir = live.phase, live.s, live.dir
							t.lane = if live.route then live.route.id else live.lane.id
						end
					end
				end,
				report = function(raw: { [string]: any })
					assert(def.kinds[raw.kind], `detector {def.name} reported an undeclared kind {raw.kind}`)
					if raw.t < (settings.warmup or 0) then
						return
					end
					local inc = raw :: any
					inc.detector = def.name
					inc.limit = inc.limit or 1
					inc.unit = inc.unit or ""
					inc.severity = if inc.limit > 0 then inc.magnitude / inc.limit else inc.magnitude
					inc.duration = inc.duration or 0
					inc.frames = inc.frames or 0
					describe(inc)
					store(inc)
				end,
			}
		end,
		sweep = function(_self: Book, t: number)
			for id, ep in open do
				if t - ep.last > ep.gap then
					open[id] = nil
					store(ep.incident)
				end
			end
		end,
		finish = function(_self: Book)
			local ids = {}
			for id in open do
				table.insert(ids, id)
			end
			table.sort(ids)
			for _, id in ids do
				store(open[id].incident)
				open[id] = nil
			end
			table.sort(book.incidents, function(a: Incident, b: Incident): boolean
				if a.t ~= b.t then
					return a.t < b.t
				end
				if a.vehicle ~= b.vehicle then
					return a.vehicle < b.vehicle
				end
				return a.kind < b.kind
			end)
		end,
	}
	return book
end

export type Bench = {
	truth: Truth.Truth,
	book: Book,
	hooks: Hooks,
	tick: (self: Bench, clock: number, vehicles: { any }) -> (),
	frame: (self: Bench, t: number, seen: { [number]: { [string]: any } }, ref: number?) -> Frame,
	finish: (self: Bench) -> ({ Incident }, { [string]: number }),
}

-- bench(def, opts?): one detector on its own, fed by hand, for the detector's spec
-- (tests/unit/traffic_replay.spec.luau shows every detector on a bench).
--   bench:tick(clock, { { id, x, z, yaw, visible, speed, teleported? } })   one true tick
--   bench:frame(t, { [id] = { x, z, yaw, vis?, y?, pitch?, speed?, snap? } }, ref?)
--       one client frame at time t: what is drawn, and the server-clock instant it draws (`ref`: the
--       reference pose is then read from the truth, as the replay does). y defaults to standing on the
--       ground; the frame's dt is the time since the previous frame.
--   bench:finish() -> incidents, counts
-- opts: vehicles { [id] = { name, kind, class } } (default: #1, a sedan), thresholds ("key" = value),
-- heightAt / surfaceAt (default: flat ground at y = 0), tickDt (1 / 30).
function Detect.bench(def: Def, opts: { [string]: any }?): Bench
	local o: { [string]: any } = opts or {}
	local thresholds = {}
	for key, value in (o.thresholds or {}) :: { [string]: number } do
		thresholds[`{def.name}.{key}`] = value
	end
	local heightAt = o.heightAt or function(_x: number, _z: number): number
		return 0
	end
	local surfaceAt = o.surfaceAt or function(x: number, z: number, _refY: number): number
		return heightAt(x, z)
	end
	local vehicles: { [number]: any } = {}
	for id, info in
		(o.vehicles or { [1] = { name = "Bench sedan", kind = "sedan", class = "sedan" } }) :: { [number]: any }
	do
		vehicles[id] = { id = id, name = info.name, kind = info.kind, class = info.class, box = Boxes.get(info.kind) }
	end
	local truth = Truth.new()
	local book = Detect.newBook({ warmup = 0, thresholds = thresholds })
	local hooks =
		def.new(book:ctx(def, { truth = truth, vehicles = vehicles, heightAt = heightAt, surfaceAt = surfaceAt }))
	local tickDt = o.tickDt or 1 / 30
	local live: { [number]: any } = {}
	local frames, lastT = 0, nil :: number?
	local prev: { [number]: Sample } = {}
	local bench: Bench
	bench = {
		truth = truth,
		book = book,
		hooks = hooks,
		tick = function(_self: Bench, clock: number, list: { any })
			for _, v in list do
				v.teleported = v.teleported == true
				v.visible = v.visible ~= false
				v.speed = v.speed or 0
				v.phase = v.phase or "drive"
				v.lane = v.lane or { id = "bench" }
				live[v.id] = v
			end
			truth:record(clock, clock, tickDt, list)
			if hooks.tick then
				hooks.tick({ n = truth.ticks, clock = clock, wall = clock, dt = tickDt, vehicles = list })
			end
		end,
		frame = function(_self: Bench, t: number, seen: { [number]: { [string]: any } }, ref: number?): Frame
			frames += 1
			local v: { [number]: Sample } = {}
			local ids = {}
			for id, p in seen do
				local info = vehicles[id] or error(`bench: no vehicle {id}`)
				local now = live[id]
				local vis = p.vis ~= false
				local s: Sample = {
					id = id,
					vis = vis,
					x = p.x,
					y = p.y or (if vis then surfaceAt(p.x, p.z, 0) + info.box.height / 2 else -500),
					z = p.z,
					yaw = p.yaw or 0,
					pitch = p.pitch or 0,
					speed = p.speed or 0,
					snap = p.snap == true,
					stopped = (p.speed or 0) < 0.05,
					tvis = if now then now.visible else vis,
					tx = if now then now.x else p.x,
					ty = 0,
					tz = if now then now.z else p.z,
					tyaw = if now then now.yaw else p.yaw or 0,
					tspeed = if now then now.speed else p.speed or 0,
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
				table.insert(ids, id)
			end
			table.sort(ids)
			local frame: Frame = {
				i = frames,
				t = t,
				dt = if lastT then t - lastT else 1 / 60,
				now = t,
				clock = truth.newest,
				ref = ref,
				starved = 0,
				snaps = 2,
				offset = 0,
				packets = 0,
				v = v,
				pv = prev,
				ids = ids,
			}
			if hooks.frame then
				hooks.frame(frame)
			end
			book:sweep(t)
			prev = v
			lastT = t
			return frame
		end,
		finish = function(_self: Bench): ({ Incident }, { [string]: number })
			if hooks.finish then
				hooks.finish()
			end
			book:finish()
			return book.incidents, book.counts
		end,
	}
	return bench
end

return Detect
