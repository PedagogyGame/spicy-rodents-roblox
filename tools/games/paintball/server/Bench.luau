--!strict
-- tools/games/paintball/server/Bench.luau: the paintball service's cost, measured (checklist PB-15;
-- Shared/Minigames/Paintball/Contract.COST). The real PaintballService with sixteen people in a match, eight
-- a side, in the stand-in building, on a framework context made by hand: no fake engine is installed, so
-- nothing here pays for the slow paths the fake engine switches on (tests/lib/Isolated says why) and the
-- numbers are the service's own. Every tick, as on a server:
--   * each person's Move arrives twenty times a second (they sway a stud about where they stand, round the
--     atrium on the four upper floors, team 1 on its west side, team 2 on its east) and is judged in full;
--   * clicks arrive, each judged in full (stamps, sprint, room, origin, the match), as many as it takes to
--     keep `balls` balls in flight: across the atrium at somebody on the other side, with a hand unsteady
--     enough that most miss and fly on to a wall;
--   * the service steps: events, people, balls against sixteen bodies' histories, the snapshot and the
--     audience; then the Session steps the match model.
-- The match model is the server lane's scripted one (tests/isolated/paintball_server_model) with the
-- magazine and the tag switched off, so that the balls and the bodies stay as many as asked. The bots'
-- share is the match-and-bots lane's to measure: there are none here.
-- Interface: run(opts?) -> Result. opts: balls (in flight, default Contract.COST.atBalls), seconds (of
--   match measured, default 4), countSweeps (wrap the arena's ball test to count and time it: its own clock
--   reads make every other number in that run a little worse). Result: per-tick medians and 95th centiles in
--   milliseconds { balls, rest, step, moves, fires, tick } (tick = everything the arena costs a frame: the
--   two handlers and the step), inFlight (mean), shotsPerSec, sweepsPerTick, sweepMs, downBytesPerSec (the
--   stream to one member of the audience), stats (the service's own)
local Arena = require("@shared/Minigames/Paintball/Arena")
local ArenaData = require("@shared/Minigames/Paintball/ArenaData")
local Body = require("@shared/Minigames/Paintball/Body")
local Clock = require("@shared/Minigames/Paintball/Clock")
local Contract = require("@shared/Minigames/Paintball/Contract")
local Rules = require("@shared/Minigames/Paintball/Rules")
local Wire = require("@shared/Minigames/Paintball/Wire")
local Session = require("@shared/Minigames/Session")
local PaintballService = require("@server/Minigames/Paintball/PaintballService")
local Model = require("@tests/isolated/paintball_server_model")

local Bench = {}

export type Opts = { balls: number?, seconds: number?, countSweeps: boolean? }
export type Spread = { median: number, p95: number }
export type Result = {
	balls: Spread,
	rest: Spread,
	step: Spread,
	moves: Spread,
	fires: Spread,
	tick: Spread,
	inFlight: number,
	shotsPerSec: number,
	sweepsPerTick: number,
	sweepMs: number,
	downBytesPerSec: number,
	stats: PaintballService.Stats,
}

local SLOTS = Contract.Rules.slots
local DT = 1 / Clock.TICK_HZ

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
		return { median = 0, p95 = 0 }
	end
	return { median = sorted[math.max(1, math.ceil(n * 0.5))], p95 = sorted[math.max(1, math.ceil(n * 0.95))] }
end

-- The stand-in building with the people standing round the atrium instead of in their spawn rooms: eight
-- places a side on the four upper floors, and spawn rooms nobody is in.
local function building(): Arena.Arena
	local arena = ArenaData.build()
	local spawns: { { Arena.Spawn } } = { {}, {} }
	for floor = 1, 4 do
		for _, z in { -8, 8 } do
			local y = floor * Arena.FLOOR_HEIGHT
			table.insert(spawns[1], { x = -20, y = y, z = z, yaw = -math.pi / 2 })
			table.insert(spawns[2], { x = 20, y = y, z = z, yaw = math.pi / 2 })
		end
	end
	arena.spawns = spawns
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

	local arena = building()
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
		people[i] = { player = player, seat = seat, place = 0, x = 0, y = 0, z = 0, yaw = 0, shot = 0 }
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
	local inFlightSum, shotsWere, shooter = 0, 0, 0
	local warm = math.floor(1.5 / DT)
	local total = warm + math.floor(seconds / DT)
	local seq = 0
	for frame = 1, total do
		local measured = frame > warm
		if frame == warm + 1 then
			shotsWere, sweeps, sweepSecs, downBytes = fired, 0, 0, 0
		end
		local now = 1000 + clock
		-- the Moves of this frame
		local t0 = os.clock()
		for i, p in people do
			if (frame + i) % (Clock.TICK_HZ // Clock.SEND_HZ) == 0 then
				seq += 1
				p.x = p.x0 + math.sin(now * 2 + i)
				p.z = p.z0 + math.cos(now * 2 + i)
				onMove(p.player, {
					t = now,
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
		while flying < wantBalls do
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
		local t2 = os.clock()
		tick()
		local t3 = os.clock()
		if measured then
			table.insert(movesMs, (t1 - t0) * 1000)
			table.insert(firesMs, (t2 - t1) * 1000)
			table.insert(ballsMs, stats.ballsMs)
			table.insert(restMs, stats.restMs)
			table.insert(stepMs, stats.stepMs)
			table.insert(tickMs, (t3 - t0) * 1000)
			inFlightSum += flying
		end
	end
	local frames = total - warm
	return {
		balls = spread(ballsMs),
		rest = spread(restMs),
		step = spread(stepMs),
		moves = spread(movesMs),
		fires = spread(firesMs),
		tick = spread(tickMs),
		inFlight = inFlightSum / frames,
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

return Bench
