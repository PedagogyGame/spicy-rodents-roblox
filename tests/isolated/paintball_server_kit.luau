--!strict
-- tests/isolated/paintball_server_kit.luau: what the paintball server lane's cases share. A case is a whole
-- game on the fake engine (tests/lib/MinigameRig with paintball's remotes beside it, tests/lib/PaintballRig):
-- the real MinigameService, Session and PaintballService, with
--   * the scripted match model in the stub Rules' place (tests/isolated/paintball_server_model);
--   * SCRIPTED CLIENTS for the people in the match: PlayerLike stubs that send Wire.Move twenty times a second
--     and Wire.Fire when told, through the real Shared/Net (PaintballRig.send), each with its own delay in
--     frames either way, jitter and loss, and that hear what the service sends them the same delay later
--     (their Minigame.State messages from stub.events, their streams from stub.streams). A client keeps the
--     picture a real one would: the snapshots it was sent, its view time (Clock.viewTime), where it would draw
--     each body (Wire.between), and so what its own ball would hit (Hit.body): "what the shooter saw";
--   * a fake Engine: a stub's body is a table { x, y, z, yaw, ghost, teleports } in world studs;
--   * a small arena of its own, hall(), where every scenario is a short walk from a spawn room.
-- Every Minigame.State message any client hears is held to Wire.checkMessage as it is heard.
-- ONLY IN AN ISOLATED RUN (it needs the rig).
-- Interface: play(fn(kit), opts?) (opts: arena, feel, paintball = more Deps, service = more service opts,
--   lag, realPass = the service's own pass desk instead of one that says everybody holds a pass); kit.w, kit.wires, kit.service, kit.state(), kit.now(), kit.frame(), kit.run(seconds),
--   kit.untilTrue(limit, cond), kit.client(name, opts?) -> Client (opts: delay frames each way or up and down, jitter, lose 0..1,
--   seed), kit.join(client) -> (ok, why), kit.walk(client, x, z, speed?), kit.live() (cut the briefing short and
--   let protection run out), kit.broken (schema failures); Client: seat, place, x, y, z, yaw, pitch, crouch,
--   sprint, air, out, silent, events, acks, tags, move(), fire(dx, dy, dz, opts?) -> shot, aim(tx, ty, tz) ->
--   dir, drawn(id) -> (x, y, z, crouch)?, last(kind, pred?), count(kind); hall(opts?) -> Arena; fakeEngine()
local Arena = require("@shared/Minigames/Paintball/Arena")
local Body = require("@shared/Minigames/Paintball/Body")
local Clock = require("@shared/Minigames/Paintball/Clock")
local Contract = require("@shared/Minigames/Paintball/Contract")
local Rules = require("@shared/Minigames/Paintball/Rules")
local Wire = require("@shared/Minigames/Paintball/Wire")
local FakeEngine = require("@tests/lib/FakeEngine")
local PaintballRig = require("@tests/lib/PaintballRig")
local Rig = require("@tests/lib/MinigameRig")
local Model = require("@tests/isolated/paintball_server_model")

local Kit = {}

export type Client = { [string]: any }
export type Kit = { [string]: any }

-- A hall with nothing in the way but what a case asks for (arena frame; the ground is y = 0):
--   two spawn rooms as boxes of air on the ground, team 1's at x -50..-40, team 2's at x 40..50, z -5..5,
--   eight spawn points in each, looking at the other;
--   wall = true   a wall 2 thick from (-30, -20) to (-28, 0), 10 high: its end is at z = 0
--   rail = true   a rail RAIL_HEIGHT high along z at x 0..0.5
--   ledge = true  team 1's room stands on a platform 14 high (x -52..-30) with an open east edge
--   exit = true   an exit room at x -38..-34, z 10..14
--   room2 = x     team 2's room begins at this x instead of 40 (a short walk from team 1's)
function Kit.hall(opts: { [string]: any }?): Arena.Arena
	local o: { [string]: any } = opts or {}
	local half, top = Arena.HALF, Arena.HEIGHT
	local boxes: { number } = {}
	local kinds: { number } = {}
	local function box(kind: number, x0: number, y0: number, z0: number, x1: number, y1: number, z1: number)
		for _, v in { x0, y0, z0, x1, y1, z1 } do
			table.insert(boxes, v)
		end
		table.insert(kinds, kind)
	end
	local K = Arena.KIND
	box(K.slab, -half, -1, -half, half, 0, half)
	box(K.slab, -half, top, -half, half, top + 1, half)
	box(K.wall, -half - 1, -1, -half, -half, top + 1, half)
	box(K.wall, half, -1, -half, half + 1, top + 1, half)
	box(K.wall, -half, -1, -half - 1, half, top + 1, -half)
	box(K.wall, -half, -1, half, half, top + 1, half + 1)
	if o.wall then
		box(K.wall, -30, 0, -20, -28, 10, 0)
	end
	if o.rail then
		box(K.rail, 0, 0, -10, 0.5, Arena.RAIL_HEIGHT, 10)
	end
	local floor1 = 0
	if o.ledge then
		floor1 = Arena.FLOOR_HEIGHT
		box(K.slab, -52, 0, -8, -30, floor1, 8)
	end
	local room2: number = o.room2 or 40
	local spawns: { { Arena.Spawn } } = { {}, {} }
	for _, z in { -2, 2 } do
		for _, x in { -48, -46, -44, -42 } do
			table.insert(spawns[1], { x = x, y = floor1, z = z, yaw = -math.pi / 2 })
			table.insert(spawns[2], { x = room2 + 50 + x, y = 0, z = z, yaw = math.pi / 2 })
		end
	end
	return Arena.finish({
		boxes = boxes,
		kinds = kinds,
		ramps = {},
		spawns = spawns,
		spawnRooms = {
			{ minX = -50, minY = floor1, minZ = -5, maxX = -40, maxY = floor1 + Arena.HEADROOM, maxZ = 5 },
			{ minX = room2, minY = 0, minZ = -5, maxX = room2 + 10, maxY = Arena.HEADROOM, maxZ = 5 },
		},
		curtains = { {}, {} },
		exits = if o.exit then { { minX = -38, minY = 0, minZ = 10, maxX = -34, maxY = 6.5, maxZ = 14 } } else {},
		lobby = { x = -14, y = 0, z = 72, yaw = 0 },
		nodes = {},
		links = {},
		cover = {},
	})
end

-- The fake Engine: a stub's body is a plain table in world studs; the rig's own player has a fake Instance,
-- whose root part stands 3 above its feet.
function Kit.fakeEngine(): { [string]: any }
	local roblox = require("@lune/roblox")
	return {
		positionOf = function(body: any): (number?, number?, number?)
			if FakeEngine.isInstance(body) then
				local root = body.PrimaryPart
				if root == nil then
					return nil, nil, nil
				end
				return root.Position.X, root.Position.Y - 3, root.Position.Z
			end
			return body.x, body.y, body.z
		end,
		teleport = function(body: any, x: number, y: number, z: number, yaw: number)
			if FakeEngine.isInstance(body) then
				body:PivotTo(roblox.CFrame.new(x, y + 3, z))
				return
			end
			body.x, body.y, body.z, body.yaw = x, y, z, yaw
			body.teleports = (body.teleports or 0) + 1
		end,
		ghost = function(body: any, on: boolean)
			if not FakeEngine.isInstance(body) then
				body.ghost = on
			end
		end,
	}
end

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

function Kit.play(fn: (kit: Kit) -> (), opts: { [string]: any }?)
	local o: { [string]: any } = opts or {}
	local undo = Model.install()
	local wires = PaintballRig.new({ lag = o.lag })
	local arena = o.arena or Kit.hall()
	local deps: { [string]: any } = { arena = arena, engine = Kit.fakeEngine(), feel = o.feel, seed = 5 }
	if not o.realPass then
		-- (everybody holds a pass, unless the case is about the pass)
		deps.pass = {
			has = function(): boolean
				return true
			end,
			buy = function(): (boolean, string)
				return false, Contract.textFor("has_pass")
			end,
		}
	end
	for k, v in o.paintball or {} do
		deps[k] = v
	end
	local service: { [string]: any } = table.clone(o.service or {})
	service.paintball = deps
	local ok, err = pcall(Rig.play, function(w: Rig.World)
		PaintballRig.attach(wires, w)
		local kit: Kit = { w = w, wires = wires, arena = arena, clients = {}, broken = {}, queue = {} }
		local place = Arena.placeOf(PaintballRig.PLACE)
		kit.place = place
		kit.service = PaintballRig.table(w).service
		kit.session = w.svc.stations[Contract.STATION].session

		function kit.now(): number
			return Rig.SERVER_TIME + w.frames / 60
		end

		function kit.state(): Rules.State
			return kit.session.game.state
		end

		-- run `fn` when `frames` more frames have gone by (a message on its way up)
		function kit.later(frames: number, later: () -> ())
			table.insert(kit.queue, { at = w.frames + math.max(0, frames), fn = later })
		end

		local function hear(c: Client, msg: any)
			table.insert(c.events, msg)
			if type(msg.kind) == "string" and string.sub(msg.kind, 1, 10) == "paintball_" then
				local good, why = Wire.checkMessage(msg)
				if not good and #kit.broken < 8 then
					table.insert(kit.broken, `{c.name} was sent a bad {msg.kind}: {tostring(why)}`)
				end
			end
			if
				msg.kind == "left"
				or msg.kind == "paintball_correct"
				or (msg.kind == "paintball_respawn" and msg.id == c.seat)
			then
				c.teleportsHeard = c.stub.body.teleports
			end
			if msg.kind == "joined" then
				c.seat = msg.seat
			elseif msg.kind == "state" then
				c.seat = msg.you or c.seat
				c.view = msg.view
				c.extras = msg
			elseif msg.kind == "left" then
				c.left = msg
				c.seat = nil
			elseif msg.kind == "paintball_respawn" and msg.id == c.seat then
				c.place = msg.place
				c.x, c.y, c.z, c.yaw, c.pitch = msg.x, msg.y, msg.z, msg.yaw, 0
				c.out = false
				c.safeUntil = msg.at
			elseif msg.kind == "paintball_correct" then
				c.place = msg.place
				c.x, c.y, c.z, c.yaw = msg.x, msg.y, msg.z, msg.yaw
				c.corrected = (c.corrected or 0) + 1
			elseif msg.kind == "paintball_tag" then
				table.insert(c.tags, msg)
				if msg.id == c.seat then
					c.out = true
				end
			elseif msg.kind == "paintball_ack" then
				c.acks[msg.shot] = msg
			elseif msg.kind == "paintball_watch" then
				c.watch = msg
			end
		end

		local function hearStream(c: Client, remote: string, payload: buffer)
			if remote == "Paintball.Snap" then
				local t, _, _, bodies = Wire.decodeSnap(payload)
				if t ~= nil then
					Clock.observe(c.lagView, t, kit.now())
					table.insert(c.snaps, { t = t, bodies = bodies })
					if #c.snaps > 40 then
						table.remove(c.snaps, 1)
					end
				end
			elseif remote == "Paintball.Shot" then
				for _, rec in Wire.unpack(Wire.Shot, payload) do
					table.insert(c.shots, rec)
				end
			elseif remote == "Splat" then
				for _, rec in Wire.unpack(Wire.Splat, payload) do
					table.insert(c.splats, rec)
				end
			end
		end

		-- one frame of everything: what the clients sent arrives, the game steps, what it sent arrives
		function kit.frame()
			local queue = kit.queue
			local i = 1
			while i <= #queue do
				if queue[i].at <= w.frames then
					local item = table.remove(queue, i)
					item.fn()
				else
					i += 1
				end
			end
			for _, c in kit.clients do
				if c.auto and c.seat ~= nil and c.place ~= 0 and not c.out and not c.silent then
					if (w.frames + c.phase) % (60 // Clock.SEND_HZ) == 0 then
						c.move()
					end
				end
			end
			PaintballRig.frame(wires, w)
			for _, c in kit.clients do
				-- note what was sent since the last frame; hand over what has had its delay
				local sent = c.stub.events
				while c.noted < #sent do
					c.noted += 1
					table.insert(c.inbox, { at = w.frames + c.down, msg = sent[c.noted] })
				end
				for _, remote in { "Paintball.Snap", "Paintball.Shot", "Splat" } do
					local list = c.stub.streams and c.stub.streams[remote]
					local seen = c.streamNoted[remote] or 0
					while list ~= nil and seen < #list do
						seen += 1
						local lost = remote ~= "Splat" and c.lose > 0 and c.rand() < c.lose
						if not lost then
							local extra = if c.jitter > 0 then math.floor(c.rand() * (c.jitter + 1)) else 0
							table.insert(
								c.inbox,
								{ at = w.frames + c.down + extra, remote = remote, payload = list[seen] }
							)
						end
					end
					c.streamNoted[remote] = seen
				end
				local k = 1
				while k <= #c.inbox do
					local item = c.inbox[k]
					if item.at <= w.frames then
						table.remove(c.inbox, k)
						if item.msg ~= nil then
							hear(c, item.msg)
						else
							hearStream(c, item.remote, item.payload)
						end
					else
						k += 1
					end
				end
			end
		end

		function kit.run(seconds: number)
			for _ = 1, math.max(1, math.floor(seconds * 60 + 0.5)) do
				kit.frame()
			end
		end

		function kit.untilTrue(limit: number, cond: () -> boolean): boolean
			for _ = 1, math.floor(limit * 60) do
				if cond() then
					return true
				end
				kit.frame()
			end
			return cond()
		end

		-- A scripted client: a person with a body, a connection and a picture of the match.
		function kit.client(name: string, copts: { [string]: any }?): Client
			local co: { [string]: any } = copts or {}
			local stub = Rig.stub(name)
			local gx, gy, gz = Arena.toWorld(place, Arena.GATE.x + #kit.clients * 2, 0, Arena.GATE.z + 4)
			stub.body = { x = gx, y = gy, z = gz, yaw = 0, ghost = false, teleports = 0 }
			local c: Client = {
				name = name,
				stub = stub,
				seat = nil,
				place = 0,
				x = 0,
				y = 0,
				z = 0,
				yaw = 0,
				pitch = 0,
				crouch = false,
				sprint = false,
				air = false,
				out = false,
				silent = false,
				auto = co.auto ~= false,
				up = co.up or co.delay or 0,
				down = co.down or co.delay or 0,
				jitter = co.jitter or 0,
				lose = co.lose or 0,
				rand = lcg(co.seed or (#kit.clients + 11)),
				phase = #kit.clients,
				seq = 0,
				shot = 0,
				noted = 0,
				streamNoted = {},
				inbox = {},
				events = {},
				acks = {},
				tags = {},
				snaps = {},
				shots = {},
				splats = {},
				lagView = Clock.newView(),
				teleportsHeard = 0,
			}
			-- its pose as a Move, sampled now and sent on its way
			function c.move(over: { [string]: number }?): { [string]: number }
				c.seq += 1
				local bits = (if c.crouch then Wire.BIT.crouch else 0)
					+ (if c.sprint then Wire.BIT.sprint else 0)
					+ (if c.air then Wire.BIT.air else 0)
				local rec: { [string]: number } = {
					t = kit.now(),
					seq = c.seq % 65536,
					x = c.x,
					y = c.y,
					z = c.z,
					yaw = c.yaw,
					pitch = c.pitch,
					bits = bits,
					place = c.place,
				}
				for k, v in over or {} do
					rec[k] = v
				end
				-- (the real body is where the client says it is, unless a case moves it apart, or the server has
				-- moved it and the client has not heard yet)
				if not c.bodyApart and stub.body.teleports == c.teleportsHeard then
					stub.body.x, stub.body.y, stub.body.z = Arena.toWorld(place, rec.x, rec.y, rec.z)
				end
				local lost = c.lose > 0 and c.rand() < c.lose
				if not lost then
					local extra = if c.jitter > 0 then math.floor(c.rand() * (c.jitter + 1)) else 0
					kit.later(c.up + extra, function()
						PaintballRig.send(wires, stub, "Paintball.Move", rec)
					end)
				end
				return rec
			end
			-- where this client draws a body now (its view time, between the two snapshots either side)
			function c.viewTime(): number
				return Clock.viewTime(c.lagView, kit.now())
			end
			function c.drawnAt(id: number, vt: number): (number?, number, number, number)
				local older: any, newer: any = nil, nil
				for i = #c.snaps, 1, -1 do
					local snap = c.snaps[i]
					local body: any = nil
					for _, b in snap.bodies do
						if b.id == id then
							body = b
							break
						end
					end
					if body ~= nil then
						if snap.t > vt then
							newer = { t = snap.t, body = body }
						else
							older = { t = snap.t, body = body }
							break
						end
					end
				end
				if older == nil and newer == nil then
					return nil, 0, 0, 0
				elseif older == nil then
					return newer.body.x, newer.body.y, newer.body.z, newer.body.crouch
				elseif newer == nil then
					return older.body.x, older.body.y, older.body.z, older.body.crouch
				end
				return Wire.between(older.body, older.t, newer.body, newer.t, vt)
			end
			function c.drawn(id: number): (number?, number, number, number)
				return c.drawnAt(id, c.viewTime())
			end
			function c.eye(): (number, number, number)
				return Body.eyePoint(c.x, c.y, c.z, if c.crouch then 1 else 0)
			end
			-- the unit direction from its eye to a point
			function c.aim(tx: number, ty: number, tz: number): (number, number, number)
				local ex, ey, ez = c.eye()
				local dx, dy, dz = tx - ex, ty - ey, tz - ez
				local len = math.sqrt(dx * dx + dy * dy + dz * dz)
				return dx / len, dy / len, dz / len
			end
			-- a click: Wire.Fire with its two stamps, the eye and the look; `over` replaces any field
			function c.fire(dx: number, dy: number, dz: number, over: { [string]: number }?, held: number?): number
				c.shot += 1
				local ex, ey, ez = c.eye()
				local rec: { [string]: number } = {
					shot = c.shot,
					vt = c.viewTime(),
					ft = kit.now(),
					ox = ex,
					oy = ey,
					oz = ez,
					dx = dx,
					dy = dy,
					dz = dz,
				}
				for k, v in over or {} do
					rec[k] = v
				end
				c.lastFire = rec
				kit.later(c.up + (held or 0), function()
					PaintballRig.send(wires, stub, "Paintball.Fire", rec)
				end)
				return c.shot
			end
			function c.last(kind: string, pred: ((m: any) -> boolean)?): any
				return Rig.last(c.events, kind, pred)
			end
			function c.count(kind: string): number
				return Rig.count(c.events, kind)
			end
			table.insert(kit.clients, c)
			return c
		end

		function kit.join(c: Client, station: string?): (boolean, string?)
			return w.svc:join(c.stub, station or Contract.STATION)
		end

		-- walk a client in a straight line to (x, z) on its present floor, a frame at a time
		function kit.walk(c: Client, x: number, z: number, speed: number?)
			local v = (speed or Body.WALK) / 60
			for _ = 1, 3600 do
				local dx, dz = x - c.x, z - c.z
				local d = math.sqrt(dx * dx + dz * dz)
				if d < 1e-6 then
					break
				end
				local step = math.min(d, v)
				c.x += dx / d * step
				c.z += dz / d * step
				kit.frame()
			end
		end

		-- the briefing cut short, and everybody's protection run out: the match is live and anyone may fire
		function kit.live()
			local state = kit.state()
			Model.liveNow(state, kit.now())
			for _, slot in state.slots do
				slot.safeUntil = kit.now()
			end
			kit.run(0.1)
		end

		fn(kit)
		if #kit.broken > 0 then
			error(`messages the wire refuses:\n{table.concat(kit.broken, "\n")}`, 0)
		end
	end, PaintballRig.opts(wires, { service = service, lag = o.lag }))
	undo()
	if not ok then
		error(err, 0)
	end
end

return Kit
