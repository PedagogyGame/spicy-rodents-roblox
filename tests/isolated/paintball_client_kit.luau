--!strict
-- tests/isolated/paintball_client_kit.luau: what the paintball client lane's specs share (it is not a cases file:
-- nothing registers it). A small building of its own, so that no case leans on the arena lane's rooms; a bench
-- that runs the two headless cores (Client/Minigames/Paintball/ShowCore and SeatCore) on a clock of its own
-- with every way out recorded; and the messages a server would send, each held to Wire.checkMessage before it
-- is handed over.
-- THE BUILDING (the arena frame): one floor slab; a wall across the north at z = -40 (x -30..30, 12 high); a
-- rail (Arena.RAIL_HEIGHT high) across at z = 10 (x -10..10); team 1's spawn room against the west wall (x
-- -60..-44, z -12..12), team 2's against the east. The player stands at (0, 0, 30) looking north (yaw 0, along
-- -z) unless a case moves it.
-- Interface: arena() -> Arena; bench(opts?) -> Bench; frame(b, n?); run(b, seconds); state(b, over?) -> msg (and
--   hands it to the seat); message(b, msg) (checked, then to the seat); snap(b, bodies, t?); watch(b, slots?,
--   over?); body(id, x, y, z, more?) -> a snapshot body; fires(b) / moves(b) -> decoded records; cues(b, cue) ->
--   how many times it was asked for; SERVER_TIME; DT
local ShowCore = require("@client/Minigames/Paintball/ShowCore")
local SeatCore = require("@client/Minigames/Paintball/SeatCore")
local Arena = require("@shared/Minigames/Paintball/Arena")
local Contract = require("@shared/Minigames/Paintball/Contract")
local Wire = require("@shared/Minigames/Paintball/Wire")
local BufferCodec = require("@shared/Util/BufferCodec")

local Kit = {}

Kit.SERVER_TIME = 1000
Kit.DT = 1 / 60

export type Bench = {
	frames: number,
	now: () -> number,
	arena: Arena.Arena,
	show: ShowCore.Show,
	seat: SeatCore.Seat,
	pose: { x: number, y: number, z: number, yaw: number, pitch: number, air: boolean },
	push: number,
	sent: { [string]: { buffer } }, -- what went up the link, by remote
	verbs: { { verb: string, args: { any } } },
	sounds: { { cue: string, volume: number? } },
	paces: { { scale: number?, sprint: boolean? } },
	controls: { boolean },
	buttons: { { { string } } },
	cameras: number, -- camera holds begun
	releases: number,
	placed: { { x: number, y: number, z: number, yaw: number } },
	looks: { { x: number, y: number, z: number, yaw: number } },
	eye: number, -- the eye's offset as last set
	fov: number,
	curtains: { any },
	locks: { boolean },
	toasts: { string },
}

function Kit.arena(): Arena.Arena
	local boxes: { number } = {}
	local kinds: { number } = {}
	local function box(kind: number, x0: number, y0: number, z0: number, x1: number, y1: number, z1: number)
		for _, v in { x0, y0, z0, x1, y1, z1 } do
			table.insert(boxes, v)
		end
		table.insert(kinds, kind)
	end
	box(Arena.KIND.slab, -60, -1, -60, 60, 0, 60)
	box(Arena.KIND.wall, -30, 0, -41, 30, 12, -40)
	box(Arena.KIND.rail, -10, 0, 10, 10, Arena.RAIL_HEIGHT, 10.5)
	local function spawns(x: number): { Arena.Spawn }
		local list = {}
		for i = 1, 8 do
			table.insert(list, { x = x, y = 0, z = -8 + (i - 1) * 2, yaw = 0 })
		end
		return list
	end
	return Arena.finish({
		boxes = boxes,
		kinds = kinds,
		ramps = {},
		spawns = { spawns(-52), spawns(52) },
		spawnRooms = {
			{ minX = -60, minY = 0, minZ = -12, maxX = -44, maxY = 6.5, maxZ = 12 },
			{ minX = 44, minY = 0, minZ = -12, maxX = 60, maxY = 6.5, maxZ = 12 },
		},
		curtains = { {}, {} },
		exits = {},
		lobby = { x = 0, y = 0, z = 75, yaw = 0 },
		nodes = {},
		links = {},
		cover = {},
	})
end

function Kit.bench(opts: { tuning: any?, noShow: boolean? }?): Bench
	local o = opts or {}
	local arena = Kit.arena()
	local b = {
		frames = 0,
		arena = arena,
		pose = { x = 0, y = 0, z = 30, yaw = 0, pitch = 0, air = false },
		push = 1,
		sent = {},
		verbs = {},
		sounds = {},
		paces = {},
		controls = {},
		buttons = {},
		cameras = 0,
		releases = 0,
		placed = {},
		looks = {},
		eye = 0,
		fov = 0,
		curtains = {},
		locks = {},
		toasts = {},
	} :: Bench
	b.now = function(): number
		return Kit.SERVER_TIME + b.frames * Kit.DT
	end
	b.show = ShowCore.new({ arena = arena, now = b.now, tuning = o.tuning })
	local ctx: any = {
		station = Contract.STATION,
		game = Contract.GAME,
		label = "Paintball match",
		place = nil,
		ui = nil,
		send = function(verb: string, args: { any }?)
			table.insert(b.verbs, { verb = verb, args = args or {} })
		end,
		camera = function()
			b.cameras += 1
		end,
		releaseCamera = function()
			b.releases += 1
		end,
		controls = function(on: boolean)
			table.insert(b.controls, on)
		end,
		pace = function(scale: number?, sprint: boolean?)
			table.insert(b.paces, { scale = scale, sprint = sprint })
		end,
		stamp = b.now,
		setButtons = function(list: { { string } })
			table.insert(b.buttons, list)
		end,
		toast = function(text: string)
			table.insert(b.toasts, text)
		end,
		body = function(): any
			return nil
		end,
		sound = function(cue: string, volume: number?): boolean
			table.insert(b.sounds, { cue = cue, volume = volume })
			return false
		end,
	}
	b.seat = SeatCore.new(ctx, {
		now = b.now,
		arena = arena,
		tuning = o.tuning,
		link = {
			send = function(remote: string, payload: buffer)
				b.sent[remote] = b.sent[remote] or {}
				table.insert(b.sent[remote], payload)
			end,
			listen = function(): () -> ()
				return function() end
			end,
		},
		show = function(): ShowCore.Show?
			return if o.noShow then nil else b.show
		end,
		port = {
			pose = function(): (number?, number, number, number, number, number, boolean)
				local p = b.pose
				local cp = math.cos(p.pitch)
				return p.x, p.y, p.z, -math.sin(p.yaw) * cp, math.sin(p.pitch), -math.cos(p.yaw) * cp, p.air
			end,
			push = function(): number
				return b.push
			end,
			place = function(x: number, y: number, z: number, yaw: number)
				b.pose.x, b.pose.y, b.pose.z = x, y, z
				table.insert(b.placed, { x = x, y = y, z = z, yaw = yaw })
			end,
			look = function(x: number, y: number, z: number, yaw: number)
				b.pose.yaw, b.pose.pitch = yaw, 0
				table.insert(b.looks, { x = x, y = y, z = z, yaw = yaw })
				ctx.camera()
			end,
			eye = function(offset: number)
				b.eye = offset
			end,
			fov = function(extra: number)
				b.fov = extra
			end,
			curtains = function(team: number?)
				table.insert(b.curtains, team or false)
			end,
			lock = function(on: boolean)
				table.insert(b.locks, on)
			end,
		},
	})
	return b
end

-- n frames: the clock moves, then the show draws, then the seat (the order of PaintballClient's one render step).
function Kit.frame(b: Bench, n: number?)
	for _ = 1, n or 1 do
		b.frames += 1
		b.show:step(Kit.DT)
		b.seat:step(Kit.DT)
	end
end

function Kit.run(b: Bench, seconds: number)
	Kit.frame(b, math.max(1, math.floor(seconds * 60 + 0.5)))
end

local function roster(): ({ any }, { any }, { boolean })
	-- you (slot 1, orange) with Bea (3); Cy (2) and the bot Rusty (4) on teal
	local slots, seats, bots = {}, {}, {}
	for id, name in { "Ann", "Cy", "Bea", "Rusty (computer)" } do
		slots[id] = { id = id, team = if id % 2 == 1 then 1 else 2, on = true, tags = 0, outs = 0, shots = 0, hits = 0 }
		seats[id] = { name = name, gone = false }
		bots[id] = id == 4
	end
	return slots, seats, bots
end

-- The framework's "state" with the service's Extras, as a seated client gets it. `over`: phase ("briefing" |
-- "live" | "ended"), endsAt, you, scores, slots, seats, bots, match, rounds, reloadAt, shot, feel, done (the
-- Session's own phase is "done").
function Kit.state(b: Bench, over: { [string]: any }?): { [string]: any }
	local o: { [string]: any } = over or {}
	local slots, seats, bots = roster()
	local msg = {
		kind = "state",
		station = Contract.STATION,
		you = o.you or 1,
		view = {
			phase = if o.done then "done" else "playing",
			seats = o.seats or seats,
			game = {
				phase = o.phase or "live",
				endsAt = o.endsAt or (b.now() + 300),
				size = 4,
				scores = o.scores or { 0, 0 },
				slots = o.slots or slots,
			},
			result = o.result,
			doneLeft = o.doneLeft,
		},
		match = o.match or 1,
		bots = o.bots or bots,
		rounds = o.rounds or Contract.Rules.magazine,
		reloadAt = o.reloadAt or 0,
		shot = o.shot or 0,
		feel = Contract.feel(o.feel),
	}
	b.seat:onState(msg)
	return msg
end

-- One of paintball's own kinds, as the server would send it: held to the wire's schema first.
function Kit.message(b: Bench, msg: { [string]: any })
	local ok, err = Wire.checkMessage(msg)
	assert(ok, `not a message the server may send: {tostring(err)}`)
	b.seat:onMessage(msg, nil)
end

-- You are placed (a respawn of your own): at the bench's pose unless told otherwise.
function Kit.place(b: Bench, over: { [string]: any }?)
	local o: { [string]: any } = over or {}
	Kit.message(b, {
		kind = "paintball_respawn",
		id = o.id or b.seat.you,
		x = o.x or b.pose.x,
		y = o.y or b.pose.y,
		z = o.z or b.pose.z,
		yaw = o.yaw or 0,
		at = o.at or (b.now() - 10),
		place = o.place or Wire.nextPlace(b.seat.place),
	})
end

function Kit.body(id: number, x: number, y: number, z: number, more: { [string]: any }?): any
	local m: { [string]: any } = more or {}
	return {
		id = id,
		x = x,
		y = y,
		z = z,
		yaw = m.yaw or 0,
		pitch = m.pitch or 0,
		crouch = m.crouch or 0,
		bits = m.bits or 0,
	}
end

-- A snapshot of these bodies stamped t (default: now), through the wire's own encoder.
function Kit.snap(b: Bench, bodies: { any }, t: number?)
	b.show:onSnap(Wire.encodeSnap(t or b.now(), b.frames, b.show.match, bodies))
end

-- "paintball_watch": the default roster unless `slots` says otherwise.
function Kit.watch(b: Bench, slots: { any }?, over: { [string]: any }?)
	local o: { [string]: any } = over or {}
	local msg = {
		kind = "paintball_watch",
		match = o.match or 1,
		slots = slots or {
			{ id = 1, team = 1, name = "Ann", bot = false, user = 11 },
			{ id = 2, team = 2, name = "Cy", bot = false, user = 12 },
			{ id = 3, team = 1, name = "Bea", bot = false, user = 13 },
			{ id = 4, team = 2, name = "Rusty", bot = true, user = 0 },
		},
		now = b.now(),
		feel = Contract.feel(o.feel),
	}
	local ok, err = Wire.checkMessage(msg)
	assert(ok, `not a message the server may send: {tostring(err)}`)
	b.show:onWatch(msg, nil)
end

function Kit.fires(b: Bench): { { [string]: number } }
	local out = {}
	for _, payload in b.sent["Paintball.Fire"] or {} do
		table.insert(out, BufferCodec.decode(Wire.Fire, payload))
	end
	return out
end

function Kit.moves(b: Bench): { { [string]: number } }
	local out = {}
	for _, payload in b.sent["Paintball.Move"] or {} do
		table.insert(out, BufferCodec.decode(Wire.Move, payload))
	end
	return out
end

function Kit.cues(b: Bench, cue: string): number
	local n = 0
	for _, s in b.sounds do
		if s.cue == cue then
			n += 1
		end
	end
	return n
end

-- How many times the show asked for a cue (its sounds in space), emptying nothing.
function Kit.showCues(b: Bench, cue: string): number
	local n = 0
	for _, s in b.show.cues do
		if s.cue == cue then
			n += 1
		end
	end
	return n
end

-- A seated, placed, live player with the roster watched: where most cases start.
function Kit.playing(opts: { [string]: any }?): Bench
	local b = Kit.bench(opts)
	Kit.watch(b)
	Kit.state(b, { phase = "live" })
	Kit.place(b)
	Kit.frame(b, 2)
	return b
end

return Kit
