--!strict
-- tools/games/paintball/server/Bench.luau: the paintball service's cost, measured (checklist PB-15;
-- Shared/Minigames/Paintball/Contract.COST). The real PaintballService with sixteen people in a match, eight
-- a side, on a framework context made by hand: no fake engine is installed, so nothing here pays for the
-- slow paths the fake engine switches on (tests/lib/Isolated says why) and the numbers are the service's
-- own. THE BUILDING is the one handed in: the lane's Greybox by default (the ground its pinned numbers stand
-- on), or the game's own (ArenaData.build(), whatever the arena lane has made of it). Nothing here knows
-- either: the sixteen stand where places() finds room on the building's own navigation nodes. Every tick,
-- as on a server:
--   * each person's Move arrives twenty times a second (they sway a stud about where they stand: eight a
--     side on the storeys above the ground, team 1 on the building's west half, team 2 on its east, as near
--     the atrium as there is room) and is judged in full;
--   * clicks arrive, each judged in full (stamps, sprint, room, origin, the match), as many as it takes to
--     keep `balls` balls in flight: at somebody on the other side, with a hand unsteady enough that most
--     miss and fly on to a wall;
--   * the service steps: events, people, balls against sixteen bodies' histories, the snapshot and the
--     audience; then the Session steps the match model.
-- The match model is the server lane's scripted one (tests/isolated/paintball_server_model) with the
-- magazine and the tag switched off, so that the balls and the bodies stay as many as asked. The bots'
-- share is the match-and-bots lane's to measure: there are none here.
-- Interface: run(opts?) -> Result; places(arena) -> { { Spawn } } (eight standing places a side). opts:
--   build (the building: default Greybox.build; a fresh one is built for each run), balls (in flight, default Contract.COST.atBalls), seconds (of match
--   measured, default 4), countSweeps (wrap the arena's ball test to count and time it: its own clock reads
--   make every other number in that run a little worse). Result: per-tick medians, 95th centiles, means and maxima in
--   milliseconds { balls, rest, step, moves, fires, tick } (tick = everything the arena costs a frame: the
--   two handlers and the step), snapTick and plainTick (the whole tick on the snapshot ticks and on the
--   others), allocKB (the garbage one tick makes, from the ticks the collector freed nothing in), inFlight (mean), shotsPerSec, sweepsPerTick, sweepMs, downBytesPerSec (the
--   stream to one member of the audience), stats (the service's own), yard and slow (the yardstick: how
--   fast the machine was running Luau during the run, and how much slower that is than the quiet machine
--   the budgets were measured on); yardstick(runs?) -> ms; YARD_QUIET
local Arena = require("@shared/Minigames/Paintball/Arena")
local Body = require("@shared/Minigames/Paintball/Body")
local Clock = require("@shared/Minigames/Paintball/Clock")
local Contract = require("@shared/Minigames/Paintball/Contract")
local Rules = require("@shared/Minigames/Paintball/Rules")
local Wire = require("@shared/Minigames/Paintball/Wire")
local Session = require("@shared/Minigames/Session")
local PaintballService = require("@server/Minigames/Paintball/PaintballService")
local Model = require("@tests/isolated/paintball_server_model")
local Greybox = require("./Greybox")

local Bench = {}

export type Opts = {
	balls: number?,
	seconds: number?,
	countSweeps: boolean?,
	build: (() -> Arena.Arena)?,
}
export type Spread = { median: number, p95: number, mean: number, max: number }
export type Result = {
	balls: Spread,
	rest: Spread,
	step: Spread,
	moves: Spread,
	fires: Spread,
	tick: Spread,
	inFlight: number,
	-- the whole tick on the snapshot ticks (one in three: the encode and the sends are in these only) and on
	-- the others; tick.median is a plain tick, so the snapshot frame is held by snapTick
	snapTick: Spread,
	plainTick: Spread,
	allocKB: number, -- what one tick makes for the collector (the Moves, the clicks and the step), KB: the GC work it costs later
	shotsPerSec: number,
	sweepsPerTick: number,
	sweepMs: number,
	downBytesPerSec: number,
	stats: PaintballService.Stats,
	yard: number, -- the yardstick's median during the run, ms
	slow: number, -- max(1, yard / YARD_QUIET): how much slower than the quiet machine this run was
}

local SLOTS = Contract.Rules.slots
local DT = 1 / Clock.TICK_HZ

-- THE YARDSTICK. A budget in milliseconds is a statement about the code, and a number of milliseconds
-- is also a statement about the machine: on a shared machine whose neighbours are busy the same Luau
-- runs up to 1.6 times slower from one second to the next (measured here: the tick at 80 balls 0.75 ms
-- and 1.20 ms in one minute, with nothing changed). So beside the service a run times a fixed piece of
-- pure Luau of the kind the service runs (float arithmetic, table reads and writes, calls into the
-- math library), every YARD_EVERY-th tick, between the ticks it measures: Result.yard is its median
-- and Result.slow = max(1, yard / YARD_QUIET) is how much slower than the quiet machine the budgets
-- were measured on this run was. tests/unit/paintball_server_cost.spec.luau holds a run to its budget
-- times `slow`: a slower service fails it on any machine, and a busy machine does not.
-- YARD_QUIET is the yardstick on the machine the pinned numbers were measured on, when it was quiet
-- (0.106 ms, when the tick at 80 balls was 0.75 ms and the balls' share at 48 was 0.35 ms).
Bench.YARD_QUIET = 0.106
local YARD_EVERY = 4
local yardCells = table.create(64, 0)
local function yard(): number
	local cells = yardCells
	local t0 = os.clock()
	local acc = 0
	for i = 1, 20000 do
		local k = i % 64 + 1
		local v = cells[k] * 0.5 + math.sqrt(i)
		cells[k] = v
		acc += math.min(v, i)
	end
	return (os.clock() - t0) * 1000 + acc * 0
end

local function lcg(seed: number): () -> number
	local s = seed
	return function(): number
		s = (s * 48271) % 2147483647
		return (s - 1) / 2147483646
	end
end

local function spread(list: { number }): Spread
	local sorted = table.clone(list)
	table.sort(sorted)
	local n = #sorted
	if n == 0 then
		return { median = 0, p95 = 0, mean = 0, max = 0 }
	end
	local sum = 0
	for _, v in sorted do
		sum += v
	end
	return {
		median = sorted[math.max(1, math.ceil(n * 0.5))],
		p95 = sorted[math.max(1, math.ceil(n * 0.95))],
		mean = sum / n,
		max = sorted[n],
	}
end

-- Is there room to stand and sway at this point: level floor a stud and a half to every side, and nothing
-- solid within that at chest height?
local REACH = 1.5
local function roomy(arena: Arena.Arena, x: number, y: number, z: number): boolean
	local ground = arena.ground(x, y, z)
	if ground == nil or math.abs(ground - y) > 0.05 then
		return false
	end
	for k = 0, 7 do
		local a = k * math.pi / 4
		local px, pz = x + math.cos(a) * REACH, z + math.sin(a) * REACH
		local there = arena.ground(px, y, pz)
		if there == nil or math.abs(there - y) > 0.05 then
			return false
		end
		if arena.sweep(x, y + Arena.CHEST, z, px, y + Arena.CHEST, pz) ~= nil then
			return false
		end
	end
	return true
end

-- Eight standing places a side on the building's own navigation nodes: outside every spawn and exit room,
-- with room to sway, team 1 on the west half and team 2 on the east, two a storey on the four storeys above
-- the ground (then wherever is left), the nearest the middle of the building first. Each looks at the middle.
function Bench.places(arena: Arena.Arena): { { Arena.Spawn } }
	local out: { { Arena.Spawn } } = { {}, {} }
	for team = 1, 2 do
		local side = if team == 1 then -1 else 1
		local byFloor: { [number]: { Arena.NavNode } } = {}
		for _, node in arena.nodes do
			if node.team ~= 0 or node.kind == "stair" or node.kind == "spawn" or node.x * side < 4 then
				continue
			end
			local inRoom = false
			for _, room in arena.exits do
				inRoom = inRoom or Arena.inRoom(room, node.x, node.y + 0.1, node.z, 2)
			end
			for _, room in arena.spawnRooms do
				inRoom = inRoom or Arena.inRoom(room, node.x, node.y + 0.1, node.z, 2)
			end
			if not inRoom and roomy(arena, node.x, node.y, node.z) then
				local list = byFloor[node.floor] or {}
				byFloor[node.floor] = list
				table.insert(list, node)
			end
		end
		for _, list in byFloor do
			table.sort(list, function(a: Arena.NavNode, b: Arena.NavNode): boolean
				local da, db = a.x * a.x + a.z * a.z, b.x * b.x + b.z * b.z
				if da ~= db then
					return da < db
				end
				return a.id < b.id
			end)
		end
		local taken: { [number]: number } = {}
		for _, perFloor in { 2, 8 } do
			for _, floor in { 1, 2, 3, 4, 0 } do
				local list = byFloor[floor] or {}
				while (taken[floor] or 0) < math.min(perFloor, #list) and #out[team] < 8 do
					local node = list[(taken[floor] or 0) + 1]
					taken[floor] = (taken[floor] or 0) + 1
					table.insert(out[team], { x = node.x, y = node.y, z = node.z, yaw = math.atan2(node.x, node.z) })
				end
			end
		end
		assert(#out[team] == 8, `the building has room for only {#out[team]} of team {team}'s eight to stand`)
	end
	return out
end

-- The building with the people standing where places() found room instead of in their spawn rooms, and
-- spawn rooms nobody is in.
local function building(build: (() -> Arena.Arena)?): Arena.Arena
	local arena = (build or Greybox.build)()
	arena.spawns = Bench.places(arena)
	local nowhere = { minX = 0, minY = -20, minZ = 0, maxX = 1, maxY = -19, maxZ = 1 }
	arena.spawnRooms = { nowhere, nowhere }
	return arena
end

local function measure(opts: Opts?): Result
	local o: Opts = opts or {}
	local wantBalls = o.balls or Contract.COST.atBalls
	local seconds = o.seconds or 4
	local open = Rules :: any
	local fired = 0
	open.fire = function(): (boolean, string?)
		fired += 1
		return true, nil
	end
	open.tag = function(): boolean
		return false
	end

	local arena = building(o.build)
	local sweeps, sweepSecs = 0, 0
	if o.countSweeps then
		local inner = arena.sweep
		arena.sweep = function(x0: number, y0: number, z0: number, x1: number, y1: number, z1: number)
			local t0 = os.clock()
			local s, nx, ny, nz, box = inner(x0, y0, z0, x1, y1, z1)
			sweepSecs += os.clock() - t0
			sweeps += 1
			return s, nx, ny, nz, box
		end
	end

	-- the framework's side, by hand: a Session, and the part of a Ctx the service asks for
	local session = Session.new(Rules, { lobbySeconds = 0, doneSeconds = 16 })
	local clock = 0
	local handlers: { [string]: (player: any, rec: { [string]: number }) -> () } = {}
	local downBytes, ended = 0, 0
	local watcher: any = nil
	local station = { id = Contract.STATION, game = Contract.GAME, label = "Paintball match", site = Contract.SITE }
	local hw = {}
	local ctx: any = {
		station = station,
		session = session,
		place = { x = 2080, z = -890, floorY = 8.6, yaw = 0 },
		root = {
			FindFirstChild = function(): any
				return hw
			end,
		},
		opts = {},
		town = {
			people = function(): { any }
				return {}
			end,
			charge = function(): (boolean, string?)
				return true, nil
			end,
		},
		now = function(): number
			return clock
		end,
		stamp = function(): number
			return 1000 + clock
		end,
		seated = function(): { any }
			local out = {}
			for i, key in session.seats do
				if not session.gone[i] then
					table.insert(out, key)
				end
			end
			return out
		end,
		seatOf = function(key: any): number?
			return Session.seatOf(session, key)
		end,
		nameOf = function(seat: number): string
			return session.names[seat] or "?"
		end,
		bodyOf = function(): any
			return nil
		end,
		send = function() end,
		broadcast = function() end,
		dirty = function() end,
		leave = function() end,
		addComputer = function(): (boolean, string?, any?)
			return false, "none in the bench", nil
		end,
		removeComputer = function(): boolean
			return false
		end,
		again = function(): (boolean, string?)
			return false, nil
		end,
	}
	local service = PaintballService.new(ctx, {
		arena = arena,
		engine = {
			positionOf = function(): (number?, number?, number?)
				return nil, nil, nil
			end,
			teleport = function() end,
			ghost = function() end,
		},
		port = {
			on = function(remote: string, fn: (player: any, rec: { [string]: number }) -> ())
				handlers[remote] = fn
			end,
			fire = function(player: any, remote: string, payload: buffer)
				if player == watcher then
					downBytes += buffer.len(payload)
					if remote == "Splat" then
						-- (every ball that ends in this closed building leaves one splat record)
						ended += buffer.len(payload) // Wire.Splat.size
					end
				end
			end,
		},
		pass = {
			has = function(): boolean
				return true
			end,
			buy = function(): (boolean, string)
				return false, ""
			end,
		},
	})

	-- sixteen people take their seats
	local people: { any } = {}
	for i = 1, SLOTS do
		local player = { Name = `P{i}`, UserId = 7000 + i }
		assert(service:join(player, station :: any), "the door lets each of them in")
		local was = session.phase
		local ok, _, seat = Session.join(session, player, player.Name, clock)
		assert(ok and seat, "a seat for each of the sixteen")
		if was ~= "playing" and session.phase == "playing" then
			service:event({ kind = "start" })
		end
		service:joined(player, seat, station :: any)
		people[i] =
			{ player = player, seat = seat, place = 0, x = 0, y = 0, z = 0, yaw = 0, shot = 0, moveT = nil :: number? }
	end
	watcher = people[1].player
	local state = (session.game :: any).state :: Rules.State
	local function tick()
		clock += DT
		service:step(DT)
		Session.step(session, clock)
	end
	tick()
	tick()
	Model.liveNow(state, 1000 + clock)
	for _, p in people do
		local slot = state.slots[p.seat]
		slot.safeUntil = 0
		local sp = arena.spawns[slot.team][(p.seat - 1) // 2 % 8 + 1]
		p.team, p.place = slot.team, 1
		p.x0, p.y, p.z0, p.yaw = sp.x, sp.y, sp.z, sp.yaw
		p.x, p.z = sp.x, sp.z
	end

	local rand = lcg(20261113)
	local onMove, onFire = handlers["Paintball.Move"], handlers["Paintball.Fire"]
	local stats = service:stats()
	local ballsMs, restMs, stepMs, movesMs, firesMs, tickMs = {}, {}, {}, {}, {}, {}
	local yardMs: { number } = {}
	local inFlightSum, shotsWere, shooter = 0, 0, 0
	local warm = math.floor(1.5 / DT)
	local total = warm + math.floor(seconds / DT)
	local seq = 0
	local allocKB, allocTicks = 0, 0
	local snapMs, plainMs = {}, {} -- the whole tick, on the snapshot ticks and on the others
	for frame = 1, total do
		local measured = frame > warm
		if frame == warm + 1 then
			shotsWere, sweeps, sweepSecs, downBytes = fired, 0, 0, 0
		end
		local now = 1000 + clock
		local k0 = collectgarbage("count")
		-- the Moves of this frame
		local t0 = os.clock()
		for i, p in people do
			if (frame + i) % (Clock.TICK_HZ // Clock.SEND_HZ) == 0 then
				seq += 1
				p.x = p.x0 + math.sin(now * 2 + i)
				p.z = p.z0 + math.cos(now * 2 + i)
				local ownT = math.max(now, (p.moveT or now) + 1e-4)
				p.moveT = ownT
				onMove(p.player, {
					t = ownT,
					seq = seq % 65536,
					x = p.x,
					y = p.y,
					z = p.z,
					yaw = p.yaw,
					pitch = 0,
					bits = 0,
					place = p.place,
				})
			end
		end
		local t1 = os.clock()
		-- the clicks that keep the balls in flight (in flight = born and not yet ended)
		local flying = stats.balls - ended
		-- (from half a second in: everybody placed, and a Move of theirs heard, as a real client fires)
		while flying < wantBalls and frame > 30 do
			shooter = shooter % SLOTS + 1
			local p = people[shooter]
			local other = people[(shooter + 1 + 2 * math.floor(rand() * 8)) % SLOTS + 1]
			if other.team == p.team then
				other = people[other.seat % SLOTS + 1]
			end
			local ex, ey, ez = Body.eyePoint(p.x, p.y, p.z, 0)
			local dx = other.x - ex
			local dy = other.y + 3 + (rand() - 0.5) * 4 - ey
			local dz = other.z + (rand() - 0.5) * 6 - ez
			local len = math.sqrt(dx * dx + dy * dy + dz * dz)
			-- as the real client: the look turns to the shot, and the click carries its pose
			local yaw, pitch = Body.yawPitch(dx, dy, dz)
			p.yaw = yaw
			seq += 1
			local ownT = math.max(now, (p.moveT or now) + 1e-4)
			p.moveT = ownT
			onMove(p.player, {
				t = ownT,
				seq = seq % 65536,
				x = p.x,
				y = p.y,
				z = p.z,
				yaw = yaw,
				pitch = pitch,
				bits = 0,
				place = p.place,
			})
			p.shot = p.shot % 65535 + 1
			onFire(p.player, {
				shot = p.shot,
				vt = now - Clock.INTERP_SECS,
				ft = now,
				ox = ex,
				oy = ey,
				oz = ez,
				dx = dx / len,
				dy = dy / len,
				dz = dz / len,
			})
			flying += 1
		end
		local snapsWere = stats.snapshots
		local t2 = os.clock()
		tick()
		local t3 = os.clock()
		local k1 = collectgarbage("count")
		if measured and k1 >= k0 then
			-- (a tick in which the collector freed nothing: what it made is what the heap grew by)
			allocKB += k1 - k0
			allocTicks += 1
		end
		if measured then
			table.insert(movesMs, (t1 - t0) * 1000)
			table.insert(firesMs, (t2 - t1) * 1000)
			table.insert(ballsMs, stats.ballsMs)
			table.insert(restMs, stats.restMs)
			table.insert(stepMs, stats.stepMs)
			table.insert(tickMs, (t3 - t0) * 1000)
			table.insert(if stats.snapshots > snapsWere then snapMs else plainMs, (t3 - t0) * 1000)
			inFlightSum += flying
			if frame % YARD_EVERY == 0 then
				table.insert(yardMs, yard())
			end
		end
	end
	local frames = total - warm
	local yardMedian = spread(yardMs).median
	return {
		yard = yardMedian,
		slow = math.max(1, yardMedian / Bench.YARD_QUIET),
		balls = spread(ballsMs),
		rest = spread(restMs),
		step = spread(stepMs),
		moves = spread(movesMs),
		fires = spread(firesMs),
		tick = spread(tickMs),
		snapTick = spread(snapMs),
		plainTick = spread(plainMs),
		inFlight = inFlightSum / frames,
		allocKB = if allocTicks > 0 then allocKB / allocTicks else 0,
		shotsPerSec = (fired - shotsWere) / seconds,
		sweepsPerTick = sweeps / frames,
		sweepMs = sweepSecs * 1000 / frames,
		downBytesPerSec = downBytes / seconds,
		stats = table.clone(stats),
	}
end

-- (the scripted match model is in the stub's place only while a run lasts, however the run ends)
function Bench.run(opts: Opts?): Result
	local undo = Model.install()
	local ok, result = pcall(measure, opts)
	undo()
	if not ok then
		error(result, 0)
	end
	return result
end

-- The median of `runs` goes at the yardstick (default 15), in milliseconds: how fast this machine is
-- running Luau at this moment (see YARD_QUIET).
function Bench.yardstick(runs: number?): number
	local times: { number } = {}
	for _ = 1, runs or 15 do
		table.insert(times, yard())
	end
	table.sort(times)
	return times[math.ceil(#times / 2)]
end

return Bench
