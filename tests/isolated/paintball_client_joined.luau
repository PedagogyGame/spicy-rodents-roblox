--!strict
-- tests/isolated/paintball_client_joined.luau: THE REAL CLIENT AGAINST THE REAL SERVER, for
-- tests/unit/paintball_client_joined.spec.luau (run in its own Lune process: tests/lib/Isolated).
-- The client lane's other cases play the server themselves, because in the lane's own tree the service and the
-- match model are the contract's stubs. These put NOTHING in anything's place: the real client (the seat, the
-- show, the player's own body, the marker, the HUD, the controls) through the real framework and the real
-- Shared/Net, against the real PaintballService on the real match model with the real brains in the game's own
-- building. The only things a case supplies are what the engine would: the legs (it walks the body at the pace
-- the client set, along the building's own navigation graph, while the client says the legs are the player's),
-- the stock camera's look, keys and the mouse; and the two things the town would: a pass desk that says the
-- player holds a pass, and the body's place in the world.
-- THEY RUN BY THEMSELVES ONCE THE LANES ARE JOINED. real() asks the match model the one thing its stub cannot
-- do (go live when the briefing is over) and the service the one thing its stub cannot (seat a pass holder at
-- the arena's own door); while either cannot, the one case here says so and passes, and nothing is proven. So in
-- the client lane's own tree this file is one line of a report, and in the joined tree it is:
--   * A WHOLE VISIT, the brains asleep (Bots.step answers as its stub does, so nothing is left to chance): the
--     door, the seat, first person, the placement in the spawn room with the look turned, the briefing and the
--     horn, the walk out, five balls and the reload that follows, a sprint and the click that ends it, a crouched
--     shot, being tagged and coming back protected, tagging somebody on the server's word, full time and the
--     card, the next match on a clean building, Leave. All along: NOT ONE POSE REFUSED OR CORRECTED AND NOT ONE
--     DRAWN BALL REFUSED (every click the server heard is acked ok), the pips the server's own count, every
--     paintball message one the wire knows.
--   * A MINUTE AND A HALF AMONG THE REAL BOTS: the player walks six links out of the spawn room and patrols
--     there, looks at whichever opponent is in clear sight (aimed up for the drop, not led) and fires as fast
--     as the marker lets go, whatever the bots do to them. The same invariants, and a line of what happened
--     (printed by the child process: `lune run tests/lib/isolated_main.luau tests/isolated/paintball_client_joined`
--     shows it; the spec runner keeps only pass and fail): balls fired and acked, how many met a body on this
--     screen against the tags the server counted, times tagged out, the bots' balls drawn, poses accepted.
--   * TWO PEOPLE: somebody is in the match already (a scripted person: Moves and clicks through the real
--     Shared/Net, as the server lane's own cases send them), has walked out and painted a wall. The player
--     joins the running match: on the other side, in a bot's seat, shown the match so far (the roster with a
--     person in it, the paint), protected, the controls card up for a moment; is tagged by the other person
--     (who it was, and the tick that points at her); changes sides while out, to play WITH her; she leaves and
--     a bot has her seat and her name is off her puppet.
--   * STANDING IDLE: the player only trembles the mouse and shuffles a foot (inside the server's bounds), is
--     tagged and comes back; the HUD says "Still there?" a full Tuning.idleWarn before the real server takes
--     the player off by its idle rule, and first person is let go.
--   * FROM THE STREET (the join's end-to-end case): no pass and 27c in the purse, the player walks from the
--     street in front of the station into the lobby (shown the match from the audience's edge), buys the
--     pass at the desk through the town's charge (20c taken once; a second press says so and takes
--     nothing), joins at the arena door, plays a short match among the real bots to the end card, leaves
--     from it, and walks back out into the street (the show ends).
-- Interface: return function(t) (the spec shape); real() -> boolean
local Arena = require("@shared/Minigames/Paintball/Arena")
local Body = require("@shared/Minigames/Paintball/Body")
local Contract = require("@shared/Minigames/Paintball/Contract")
local Rules = require("@shared/Minigames/Paintball/Rules")
local Wire = require("@shared/Minigames/Paintball/Wire")
local Magazine = require("@shared/Paintball/Magazine")
local Bots = require("@server/Minigames/Paintball/Bots")
local PaintballClient = require("@client/Minigames/Paintball/PaintballClient")
local Tuning = require("@client/Minigames/Paintball/Tuning")
local FakeEngine = require("@tests/lib/FakeEngine")
local PaintballRig = require("@tests/lib/PaintballRig")
local Rig = require("@tests/lib/MinigameRig")
local roblox = require("@lune/roblox")

local R = Contract.Rules
local M = Contract.MARGIN
local Key = roblox.Enum.KeyCode
local CFrame, Vector3 = roblox.CFrame, roblox.Vector3
local STATION = Contract.STATION
local ROOT = 3 -- the fake body's root above its feet (HipHeight 2 + half a root 2 tall)
local HOP_FRAMES = 30 -- a jump lasts half a second
local USER = 41

-- Is the match model the real one? The stub keeps its seats and its clock and never leaves the briefing.
local function realModel(): boolean
	local ok, live = pcall(function(): boolean
		local state = Rules.init(2, 1)
		Rules.sync(state, 1000)
		Rules.step(state, 0)
		Rules.sync(state, 1000 + R.briefingSecs + 1)
		Rules.step(state, 0.1)
		return state.phase == "live"
	end)
	return ok and live
end

-- What the engine does with a body, on the fake engine's Instances (the service's Engine: world studs).
local function engine(): { [string]: any }
	return {
		positionOf = function(body: any): (number?, number?, number?)
			if not FakeEngine.isInstance(body) then
				return body.x, body.y, body.z -- (a scripted person's body is a plain table in world studs)
			end
			local root = body.PrimaryPart
			if root == nil then
				return nil, nil, nil
			end
			return root.Position.X, root.Position.Y - ROOT, root.Position.Z
		end,
		teleport = function(body: any, x: number, y: number, z: number, yaw: number)
			if FakeEngine.isInstance(body) then
				body:PivotTo(CFrame.new(x, y + ROOT, z) * CFrame.Angles(0, yaw, 0))
			else
				body.x, body.y, body.z = x, y, z
			end
		end,
		ghost = function(_body: any, _on: boolean) end,
	}
end

type Visit = {
	w: Rig.World,
	wires: PaintballRig.Wires,
	service: any,
	arena: Arena.Arena,
	place: Arena.Place,
	hum: any,
	target: { x: number, z: number }?, -- where the legs are walking to
	hop: number?, -- frames into a jump (nil: on the floor)
	each: { () -> () }, -- what else a case does once a frame (a scripted person's own stream)
	others: number, -- clicks a scripted person sent (the wire's record does not say whose a click is)
	checked: number, -- how many of w.got have been held to the wire
	unknown: { string }, -- messages the wire does not know
	now: () -> number,
	seat: () -> PaintballClient.Seat,
	state: () -> any,
	feet: () -> (number, number, number), -- the body's feet point, arena frame
	frame: () -> (),
	run: (seconds: number) -> (),
	untilTrue: (limit: number, cond: () -> boolean) -> boolean,
	look: (yaw: number, pitch: number) -> (),
	walk: (x: number, z: number, limit: number?) -> boolean, -- there within the limit?
	hud: () -> any,
	words: () -> { string },
	acks: () -> (number, number), -- acked ok, refused
	fires: () -> number, -- clicks the server heard
}

local function visit(w: Rig.World, wires: PaintballRig.Wires): Visit
	local service = PaintballRig.table(w).service
	local v = {
		w = w,
		wires = wires,
		service = service,
		arena = service.arena,
		place = service.place,
		target = nil,
		hop = nil,
		each = {},
		others = 0,
		checked = 0,
		unknown = {},
	} :: Visit
	local hum = FakeEngine.new("Humanoid", "Humanoid", {
		HipHeight = 2,
		JumpHeight = 7.2,
		UseJumpPower = true,
		CameraOffset = Vector3.new(0, 0, 0),
		FloorMaterial = roblox.Enum.Material.Plastic,
	})
	hum.Parent = w.body
	rawset(w.player, "UserId", USER)
	rawset(w.body.PrimaryPart, "Size", Vector3.new(2, 2, 1))
	w.body:SetAttribute("DriverUserId", USER)
	v.hum = hum
	v.now = function(): number
		return Rig.SERVER_TIME + w.frames / 60
	end
	v.seat = function(): PaintballClient.Seat
		local seat = PaintballClient.seat()
		assert(seat, "the seat is open")
		return seat
	end
	v.state = function(): any
		return service.ctx.session.game.state
	end
	v.feet = function(): (number, number, number)
		local p = w.body.PrimaryPart.Position
		return Arena.toLocal(v.place, p.X, p.Y - ROOT, p.Z)
	end
	local walking = false
	-- THE LEGS: what the stock controls and the Humanoid do. The body goes towards the target at the town's
	-- walk times the pace the client set on it (the framework's MoveScale), on the walking surface, and only
	-- while the client has not taken the legs.
	local function legs()
		local target = v.target
		local free = w.controls[#w.controls] ~= false
		local want = target ~= nil and free
		if want ~= walking then
			walking = want
			Rig.key(Key.W, want)
		end
		local hop = v.hop
		if (target == nil or not free) and hop == nil then
			return
		end
		local x, y, z = v.feet()
		if target ~= nil and free then
			local dx, dz = target.x - x, target.z - z
			local d = math.sqrt(dx * dx + dz * dz)
			local scale = w.body:GetAttribute("MoveScale")
			local step = Body.WALK * (if type(scale) == "number" then scale else 1) / 60
			if d <= step then
				x, z = target.x, target.z
				v.target = nil
			else
				x, z = x + dx / d * step, z + dz / d * step
			end
		end
		local ground = v.arena.ground(x, y + 0.5, z) or y
		-- a hop: up to the match's jump height and down again in half a second, off the floor meanwhile
		local up = 0
		if hop ~= nil then
			local u = (hop + 1) / HOP_FRAMES
			v.hop = if u < 1 then hop + 1 else nil
			up = if u < 1 then 4 * Body.JUMP_HEIGHT * u * (1 - u) else 0
			hum.FloorMaterial = if u < 1 then roblox.Enum.Material.Air else roblox.Enum.Material.Plastic
		end
		local wx, wy, wz = Arena.toWorld(v.place, x, ground + up, z)
		w.body:PivotTo(CFrame.new(wx, wy + ROOT, wz))
	end
	v.frame = function()
		legs()
		for _, fn in v.each do
			fn()
		end
		PaintballRig.frame(wires, w)
		-- every message of paintball's own that reaches the client is one the wire knows
		while v.checked < #w.got do
			v.checked += 1
			local msg = w.got[v.checked]
			if type(msg) == "table" and type(msg.kind) == "string" and string.sub(msg.kind, 1, 10) == "paintball_" then
				local ok, err = Wire.checkMessage(msg)
				if not ok and #v.unknown < 5 then
					table.insert(v.unknown, `{msg.kind}: {tostring(err)}`)
				end
			end
		end
	end
	v.run = function(seconds: number)
		for _ = 1, math.max(1, math.floor(seconds * 60 + 0.5)) do
			v.frame()
		end
	end
	v.untilTrue = function(limit: number, cond: () -> boolean): boolean
		for _ = 1, math.floor(limit * 60) do
			if cond() then
				return true
			end
			v.frame()
		end
		return cond()
	end
	-- the stock camera's doing: the view turned (the rig is told it was not the game that moved it)
	v.look = function(yaw: number, pitch: number)
		local cam = workspace.CurrentCamera
		local dx, dy, dz = Arena.dirToWorld(v.place, Body.look(yaw, pitch))
		local at = cam.CFrame.Position
		local cf = CFrame.lookAt(at, at + Vector3.new(dx, dy, dz))
		rawset(cam, "CFrame", cf)
		w.camWas = cf
	end
	v.walk = function(x: number, z: number, limit: number?): boolean
		v.target = { x = x, z = z }
		return v.untilTrue(limit or 20, function(): boolean
			return v.target == nil
		end)
	end
	v.hud = function(): any
		return w.player:FindFirstChild("PlayerGui"):FindFirstChild("PaintballHud")
	end
	v.words = function(): { string }
		local hud = v.hud()
		local words = if hud then Rig.texts(hud) else {}
		local aim = w.player:FindFirstChild("PlayerGui"):FindFirstChild("PaintballAim")
		for _, word in if aim then Rig.texts(aim) else {} do
			table.insert(words, word)
		end
		return words
	end
	v.acks = function(): (number, number)
		local ok, refused = 0, 0
		for _, msg in w.got do
			if type(msg) == "table" and msg.kind == "paintball_ack" then
				if msg.ok == true then
					ok += 1
				else
					refused += 1
				end
			end
		end
		return ok, refused
	end
	v.fires = function(): number
		return #(wires.heard["Paintball.Fire"] or {}) - v.others
	end
	return v
end

-- A case in the real game. Returns false, and plays nothing, where the service behind the door is the stub.
-- purse: no pass is held; the real pass desk sells one through the town's charge, out of this purse
type Purse = { cents: number, paid: { string } }
type PlayOpts = { asleep: boolean?, lag: number?, lose: number?, first: ((v: Visit) -> ())?, purse: Purse? }
local function play(fn: (v: Visit) -> (), opts: PlayOpts?): boolean
	local o: PlayOpts = opts or {}
	-- (lag: frames each way, for the stream and for the framework's messages alike; lose: one unreliable
	-- message down in this many is lost)
	local every = o.lose
	local wires = PaintballRig.new({
		lag = o.lag,
		lose = if every
			then function(_remote: string, n: number): boolean
				return n % every == 0
			end
			else nil,
	})
	local brains = Bots :: any
	local step = brains.step
	if o.asleep then
		-- the brains asleep: every bot stands where the match put it and wants nothing done
		brains.step = function(): { any }
			return {}
		end
	end
	local seated = true
	local ok, err = pcall(
		Rig.play,
		function(w: Rig.World)
			PaintballRig.attach(wires, w)
			local v = visit(w, wires)
			-- (what happens before the player walks up: somebody else's match already running)
			if o.first then
				o.first(v)
			end
			Rig.press(w, STATION)
			if not v.untilTrue(1.5, function(): boolean
				return w.client.active() == STATION
			end) then
				seated = false
				return
			end
			fn(v)
			assert(#v.unknown == 0, `a message the wire does not know: {table.concat(v.unknown, "; ")}`)
		end,
		PaintballRig.opts(wires, {
			lag = o.lag,
			service = {
				paintball = {
					engine = engine(),
					seed = 7,
					pass = if o.purse
						then nil -- (the service's own desk, on the town's charge below)
						else {
							has = function(): boolean
								return true
							end,
							buy = function(): (boolean, string)
								return false, Contract.textFor("has_pass")
							end,
						},
				},
				games = if o.purse
					then {
						charge = function(_player: any, cents: number, why: string): (boolean, string?)
							local purse = o.purse :: Purse
							if purse.cents < cents then
								return false, Contract.passShort(cents, purse.cents)
							end
							purse.cents -= cents
							table.insert(purse.paid, why)
							return true, nil
						end,
					}
					else nil,
			},
		})
	)
	brains.step = step
	if not ok then
		error(err, 0)
	end
	return seated
end

-- Are both the model and the service the real ones?
local function real(): boolean
	if not realModel() then
		return false
	end
	local ok, seated = pcall(play, function() end)
	return ok and seated
end

-- The way out of the spawn room the body stands in, along the building's own graph: from the node nearest the
-- body in clear sight, by the links (breadth first), to the first node `beyond` links outside every spawn room
-- on the same storey. The points to walk through, the first one included.
local function wayOut(arena: Arena.Arena, x: number, y: number, z: number, beyond: number): { Arena.NavNode }
	local start: Arena.NavNode? = nil
	local best = math.huge
	for _, node in arena.nodes do
		local d = (node.x - x) ^ 2 + (node.z - z) ^ 2
		if
			math.abs(node.y - y) < 1
			and d < best
			and Arena.clearPath(arena.sweep, x, z, node.x, node.z, y + Arena.CHEST)
		then
			start, best = node, d
		end
	end
	assert(start, "a node of the graph stands in clear sight of the body")
	local next: { [number]: { number } } = {}
	for _, link in arena.links do
		if link.kind == "walk" then
			next[link.a] = next[link.a] or {}
			next[link.b] = next[link.b] or {}
			table.insert(next[link.a], link.b)
			table.insert(next[link.b], link.a)
		end
	end
	local from: { [number]: number } = { [start.id] = 0 }
	local outside: { [number]: number } = { [start.id] = 0 }
	local queue = { start.id }
	local head = 1
	while head <= #queue do
		local at = queue[head]
		head += 1
		local here = arena.nodes[at]
		local clear = true
		for _, room in arena.spawnRooms do
			if Arena.inRoom(room, here.x, here.y + 0.1, here.z, M.room + 1) then
				clear = false
			end
		end
		if outside[at] >= beyond and clear then
			local path: { Arena.NavNode } = {}
			local n = at
			while n ~= 0 do
				table.insert(path, 1, arena.nodes[n])
				n = from[n]
			end
			return path
		end
		for _, to in next[at] or {} do
			local node = arena.nodes[to]
			if from[to] == nil and math.abs(node.y - y) < 1 then
				from[to] = at
				outside[to] = if node.team ~= 0 or node.kind == "spawn" then 0 else outside[at] + 1
				table.insert(queue, to)
			end
		end
	end
	error("the graph leads out of the spawn room")
end

-- A level look from the eye that meets a wall between `near` and `far` studs out: the yaw.
local function wallYaw(arena: Arena.Arena, x: number, y: number, z: number, near: number, far: number): number
	local ey = y + Body.STAND_EYE
	for i = 0, 31 do
		local yaw = i * math.pi / 16
		local dx, _, dz = Body.look(yaw, 0)
		local s = arena.sweep(x, ey, z, x + dx * far, ey, z + dz * far)
		if s ~= nil and s * far >= near then
			return yaw
		end
	end
	error("no wall in sight")
end

local function inOwnRoom(v: Visit): boolean
	local seat = v.seat()
	local room = v.arena.spawnRooms[seat.team]
	local x, y, z = v.feet()
	return room ~= nil and Arena.inRoom(room, x, y + 0.1, z)
end

-- Out of the spawn room by the graph, to a spot the marker may fire from. Returns the route walked.
local function walkOut(v: Visit, t: any): { Arena.NavNode }
	local x, y, z = v.feet()
	local route = wayOut(v.arena, x, y, z, 2)
	for _, node in route do
		t.truthy(v.walk(node.x, node.z, 30), `the legs reach node {node.id}`)
	end
	return route
end

-- The server's own count of this player's magazine, brought up to now.
local function serverRounds(v: Visit): number
	local slot = v.state().slots[v.seat().you]
	Magazine.update(slot.mag, v.now())
	return slot.mag.rounds
end

-- `outs`: how many times the player was tagged out by somebody else's ball while firing. A click made
-- on the shared clock at or after the tag and before the word of it has come down the line (half a
-- round trip and its jitter) is refused "out" by the contract's rule, and no client can know better:
-- at 300 ms a tag can race one click. Only that refusal is let through, at most once for each tag.
local function settled(v: Visit, t: any, what: string, outs: number?)
	local stats = v.service:stats()
	t.eq(stats.movesRefused, 0, `{what}: no pose of an honest client refused`)
	t.eq(stats.corrections, 0, `{what}: and none corrected`)
	t.eq(Rig.count(v.w.got, "paintball_correct"), 0)
	local ok, refused = v.acks()
	local whys = {}
	for why, n in stats.shotsRefusedBy do
		table.insert(whys, `{why} x{n}`)
	end
	local raced = math.min(stats.shotsRefusedBy.out or 0, outs or 0)
	t.eq(refused - raced, 0, `{what}: no ball that was drawn refused ({table.concat(whys, ", ")})`)
	t.eq(ok + refused, v.fires(), `{what}: every click the server heard is acked`)
	t.eq(stats.shotsRefused - raced, 0)
end

-- A SCRIPTED PERSON in the match beside the player: a PlayerLike stub with a body, who sends her own pose
-- twenty times a second and her clicks through the real Shared/Net, each click with its own Move first (as
-- the real client does), and walks at walking pace. She hears what the service sends her (stub.events).
type Person = {
	stub: any,
	seat: number,
	team: number,
	x: number,
	y: number,
	z: number,
	yaw: number,
	place: number,
	out: boolean,
	walkTo: (x: number, z: number) -> (),
	fire: (yaw: number) -> (),
}

local function person(v: Visit, name: string): Person
	local w, wires = v.w, v.wires
	local stub = Rig.stub(name)
	local gx, gy, gz = Arena.toWorld(v.place, Arena.GATE.x + 3, 0, Arena.GATE.z + 4)
	stub.body = { x = gx, y = gy, z = gz }
	table.insert(w.people, { key = stub, name = name, species = "human", x = gx, y = gy, z = gz })
	local ok, why = w.svc:join(stub, STATION)
	assert(ok, `{name} is seated: {tostring(why)}`)
	local p = { stub = stub, seat = 0, team = 0, x = 0, y = 0, z = 0, yaw = 0, place = 0, out = false } :: Person
	local heard = 0
	local seq, shot = 0, 0
	local function move()
		seq += 1
		stub.body.x, stub.body.y, stub.body.z = Arena.toWorld(v.place, p.x, p.y, p.z)
		PaintballRig.send(wires, stub, "Paintball.Move", {
			t = v.now(),
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
	table.insert(v.each, function()
		while heard < #stub.events do
			heard += 1
			local msg = stub.events[heard]
			if msg.kind == "joined" then
				p.seat = msg.seat
			elseif msg.kind == "paintball_respawn" and msg.id == p.seat then
				p.x, p.y, p.z, p.yaw, p.place, p.out = msg.x, msg.y, msg.z, msg.yaw, msg.place, false
			elseif msg.kind == "paintball_tag" and msg.id == p.seat then
				p.out = true
			end
		end
		if p.place ~= 0 and not p.out and w.frames % 3 == 0 then
			move()
		end
	end)
	p.walkTo = function(x: number, z: number)
		for _ = 1, 1800 do
			local dx, dz = x - p.x, z - p.z
			local d = math.sqrt(dx * dx + dz * dz)
			if d < 1e-6 then
				return
			end
			local step = math.min(d, Body.WALK / 60)
			p.x += dx / d * step
			p.z += dz / d * step
			v.frame()
		end
	end
	p.fire = function(yaw: number)
		shot += 1
		v.others += 1
		p.yaw = yaw
		v.frame()
		move()
		local dx, dy, dz = Body.look(yaw, 0)
		local now = v.now()
		PaintballRig.send(wires, stub, "Paintball.Fire", {
			shot = shot,
			vt = now - 0.1,
			ft = now,
			ox = p.x,
			oy = p.y + Body.STAND_EYE,
			oz = p.z,
			dx = dx,
			dy = dy,
			dz = dz,
		})
	end
	return p
end

return function(t)
	if not real() then
		t.test(
			"the real client against the real server: waiting for the lanes to be joined (the service or the match model is still the contract's stub)",
			function()
				t.truthy(true)
			end
		)
		return
	end

	t.test(
		"a whole visit, the brains asleep: door, briefing, five balls and the reload, sprint, crouch, tagged and back, a tag, full time, the next match, Leave; nothing of an honest client refused",
		function()
			local seated = play(function(v)
				local w, wires = v.w, v.wires
				v.run(0.5)
				local seat = v.seat()
				-- THE SEAT: the slot, the side, the placement, first person, the look
				t.truthy(seat.you >= 1, "the client knows its slot")
				t.truthy(seat.team == 1 or seat.team == 2, "and its side")
				t.truthy(seat.place >= 1, "the server's placement was obeyed")
				t.eq(w.body:GetAttribute("CameraZone"), "lockFirstPerson", "brief 14")
				t.truthy(inOwnRoom(v), "placed in its own spawn room")
				t.eq(seat.phase, "briefing")
				local words = v.words()
				t.truthy(Rig.has(words, "BRIEFING"), table.concat(words, " | "))
				local slot = v.state().slots[seat.you]
				t.eq(slot.team, seat.team, "the side is the server's")
				local spawn = v.arena.spawns[seat.team][slot.spawn]
				local look = workspace.CurrentCamera.CFrame.LookVector
				local dx, _, dz = Arena.dirToWorld(v.place, Body.look(spawn.yaw, 0))
				t.near(look.X, dx, 1e-4, "the look was turned to the placement's yaw")
				t.near(look.Z, dz, 1e-4)
				-- the others are drawn as puppets (seven bots), the real body of nobody twice
				local show = PaintballClient.show()
				assert(show, "the show is on")
				local puppets = 0
				for id, p in show.puppets do
					if id ~= seat.you then
						puppets += 1
						t.truthy(p.team == 1 or p.team == 2, "every puppet has its side from the roster")
					end
				end
				t.eq(puppets, 2 * R.teamMin - 1, "four a side: seven others")
				t.eq(seat.feel.ballSpeed, v.state().feel.ballSpeed, "the match's feel is the client's")
				-- a click in the briefing is nothing
				Rig.mouse(true)
				Rig.mouse(false)
				v.run(0.3)
				t.eq(v.fires(), 0, "nobody fires in the briefing")
				-- THE MATCH GOES LIVE (the briefing cut short), the horn, and the protection runs out
				t.truthy(v.service:debug("end"))
				t.truthy(
					v.untilTrue(2, function(): boolean
						return seat.phase == "live"
					end),
					"the client hears the match go live"
				)
				t.truthy(Rig.has(v.words(), "GO!"))
				t.truthy(v.untilTrue(4, function(): boolean
					return seat:protected(v.now()) == nil
				end))
				-- in your own room: safe, and no ball
				t.truthy(Rig.has(v.words(), "SAFE in your spawn room"), table.concat(v.words(), " | "))
				Rig.mouse(true)
				Rig.mouse(false)
				v.run(0.3)
				t.eq(v.fires(), 0, "no ball from a spawn room")
				-- THE WALK OUT, along the building's own graph, at the pace the client set
				local route = walkOut(v, t)
				t.falsy(inOwnRoom(v))
				v.run(0.3)
				settled(v, t, "the walk out")
				-- FIVE BALLS AT A WALL, clicking faster than the marker: then the reload by itself
				local x, y, z = v.feet()
				local yaw = wallYaw(v.arena, x, y, z, 12, 60)
				v.look(yaw, 0)
				v.run(0.2)
				t.truthy(seat:ready(v.now()), "the marker may fire here")
				for _ = 1, 12 do
					Rig.mouse(true)
					Rig.mouse(false)
					v.run(1 / 6)
				end
				v.run(0.5)
				t.eq(seat.fired, R.magazine, "five balls, and the sixth click is dry")
				t.eq(v.fires(), R.magazine)
				settled(v, t, "five balls")
				-- each ball's splat is on the wall, and it is the server's record now
				v.run(1.2)
				local mine, predicted = 0, 0
				for _, splat in show.walls do
					if splat.predicted then
						predicted += 1
					elseif splat.by == seat.you then
						mine += 1
					end
				end
				t.eq(predicted, 0, "every predicted splat was replaced by the server's record")
				t.eq(mine, R.magazine, "one splat a ball, and they stay")
				-- the reload runs its time on both sides and the pips are the server's own count
				t.truthy(
					v.untilTrue(seat.feel.reloadSecs + 0.5, function(): boolean
						return seat.mag.rounds == R.magazine and seat.mag.reloadDoneAt == nil
					end),
					"full again"
				)
				t.eq(serverRounds(v), R.magazine)
				-- A SPRINT along the last link and back, then a click in mid-stride
				local a, b = route[#route - 1], route[#route]
				Rig.key(Key.LeftShift, true)
				t.truthy(v.walk(a.x, a.z, 10))
				local sprinted = false
				for _, move in wires.heard["Paintball.Move"] or {} do
					if Wire.has(move.bits, Wire.BIT.sprint) then
						sprinted = true
					end
				end
				t.truthy(sprinted, "the server was told of the sprint")
				v.target = { x = b.x, z = b.z }
				v.run(0.15)
				t.truthy(seat.k > 0, "sprinting")
				local before = v.fires()
				Rig.mouse(true)
				Rig.mouse(false)
				v.run(0.1)
				t.eq(v.fires(), before, "the marker is still coming up")
				v.run(0.4)
				t.eq(v.fires(), before + 1, "and the click was not lost")
				Rig.key(Key.LeftShift, false)
				t.truthy(v.untilTrue(10, function(): boolean
					return v.target == nil
				end))
				v.run(0.3)
				settled(v, t, "the sprint and the click that ended it")
				-- A CROUCHED SHOT: the eye is down for real and the ball leaves from it
				Rig.key(Key.C, true)
				v.run(0.5)
				t.near(
					v.hum.CameraOffset.Y,
					Body.CROUCH_EYE - Body.STAND_EYE,
					1e-6,
					"the camera is at the crouched eye"
				)
				before = v.fires()
				Rig.mouse(true)
				Rig.mouse(false)
				v.run(0.4)
				t.eq(v.fires(), before + 1)
				local fire = wires.heard["Paintball.Fire"][before + 1]
				local _, fy = v.feet()
				t.near(fire.oy, fy + Body.CROUCH_EYE, 1e-3, "from the crouched eye")
				Rig.key(Key.C, false)
				v.run(0.5)
				settled(v, t, "the crouched shot")
				t.eq(seat.mag.rounds, serverRounds(v), "the pips are the server's count")
				-- TAGGED: the server's verdict takes the legs; the respawn gives everything back
				local other = 0
				for id, s in v.state().slots do
					if s.on and s.team ~= seat.team and other == 0 then
						other = id
					end
				end
				t.truthy(other ~= 0)
				local placedBefore = seat.place
				local moves = #(wires.heard["Paintball.Move"] or {})
				local ok, why = v.service:debug("tag", other, seat.you)
				t.truthy(ok, tostring(why))
				t.truthy(
					v.untilTrue(1, function(): boolean
						return seat.out
					end),
					"the client hears it was tagged"
				)
				v.run(0.3)
				words = v.words()
				t.truthy(Rig.has(words, "TAGGED OUT by"), table.concat(words, " | "))
				t.eq(w.controls[#w.controls], false, "the legs are taken")
				moves = #(wires.heard["Paintball.Move"] or {})
				v.run(0.5)
				t.eq(#(wires.heard["Paintball.Move"] or {}), moves, "no pose while out")
				t.truthy(
					v.untilTrue(seat.feel.respawnSecs + 1, function(): boolean
						return not seat.out
					end),
					"the respawn comes"
				)
				v.run(0.2)
				t.truthy(seat.place ~= placedBefore, "a new placement")
				t.truthy(inOwnRoom(v), "back in the spawn room")
				t.eq(w.controls[#w.controls], true, "the legs are back")
				t.eq(seat.mag.rounds, R.magazine, "a full magazine")
				t.truthy(seat:protected(v.now()) ~= nil, "protected")
				t.truthy(Rig.has(v.words(), "PROTECTED"), table.concat(v.words(), " | "))
				t.truthy(v.untilTrue(seat.feel.protectSecs + 0.5, function(): boolean
					return seat:protected(v.now()) == nil
				end))
				-- YOU TAG SOMEBODY: the marker on the crosshair and the score, on the server's word
				local score = seat.scores[seat.team]
				ok, why = v.service:debug("tag", seat.you, other)
				t.truthy(ok, tostring(why))
				t.truthy(
					v.untilTrue(1, function(): boolean
						return seat.hitAt > 0
					end),
					"the hit marker's moment"
				)
				t.eq(seat.scores[seat.team], score + 1, "the score moved with the tag")
				-- (who it was is in the feed; under the crosshair the spawn room's own line has the place)
				t.truthy(Rig.has(v.words(), " tagged "), table.concat(v.words(), " | "))
				local aim = w.player:FindFirstChild("PlayerGui"):FindFirstChild("PaintballAim")
				t.truthy(aim:FindFirstChild("Hit").Visible, "the X on the crosshair")
				-- out again, fire a little, so the match has something to show at the end
				walkOut(v, t)
				x, y, z = v.feet()
				v.look(wallYaw(v.arena, x, y, z, 12, 60), 0)
				v.run(0.2)
				Rig.mouse(true)
				Rig.mouse(false)
				v.run(1.5)
				settled(v, t, "after the respawn")
				t.truthy(#show.walls > 0, "paint on the walls")
				-- FULL TIME: the card, every player's line, and the next match by itself
				t.truthy(v.service:debug("end"))
				t.truthy(
					v.untilTrue(2, function(): boolean
						return seat.phase == "ended"
					end),
					"the client hears full time"
				)
				v.run(0.5)
				local screen = Rig.screen(w)
				t.truthy(string.find(screen, "FULL TIME", 1, true), screen)
				t.truthy(string.find(screen, "The next match starts in", 1, true))
				local on = 0
				for id, s in v.state().slots do
					if s.on then
						on += 1
						local name = tostring(v.service.ctx.session.names[id])
						t.truthy(string.find(screen, name, 1, true), `the card has {name}'s line`)
					end
				end
				t.eq(on, 2 * R.teamMin)
				Rig.mouse(true)
				Rig.mouse(false)
				v.run(0.3)
				local fired = v.fires()
				local matchWas = show.match
				t.truthy(
					v.untilTrue(R.endCardSecs + R.endCardSpare + 2, function(): boolean
						return seat.phase == "briefing"
					end),
					"the next match begins by itself"
				)
				v.run(0.5)
				t.eq(v.fires(), fired, "nothing was fired at the end card")
				t.eq(w.client.active(), STATION, "still seated")
				t.eq(show.match, matchWas + 1, "a new match")
				t.eq(#show.walls, 0, "on a clean building")
				t.truthy(inOwnRoom(v), "placed anew")
				t.truthy(Rig.has(v.words(), "BRIEFING"))
				-- LEAVE: the button with the scoreboard; first person is released and the server walks you out
				Rig.key(Key.G, true)
				v.run(0.2)
				Rig.click(w, "Leave the match")
				v.run(0.5)
				Rig.key(Key.G, false)
				t.eq(w.client.active(), nil, "left")
				t.eq(PaintballClient.seat(), nil)
				t.eq(w.body:GetAttribute("CameraZone"), nil, "first person released")
				t.eq(v.hum.CameraOffset.Y, 0)
				local lx, _, lz = v.feet()
				t.truthy(not Arena.inVolume(lx, 1, lz), "the server put the body in the lobby")
			end, { asleep = true })
			t.truthy(seated)
		end
	)

	-- A fight among the real bots at one connection: `seconds` of live play, `lag` frames each way, one
	-- unreliable message down in `lose` lost. The player walks six links out of the spawn room and patrols
	-- there: one leg walked, the next sprinted, the next crouched, a hop now and then; looks at the nearest
	-- opponent in clear sight and clicks all the while.
	local function fight(name: string, seconds: number, lag: number, lose: number?)
		t.test(name, function()
			local line = ""
			play(function(v)
				v.run(0.5)
				local seat = v.seat()
				t.truthy(v.service:debug("end"))
				t.truthy(v.untilTrue(2, function(): boolean
					return seat.phase == "live"
				end))
				local route: { Arena.NavNode } = {}
				local leg = 1
				local legs = 0
				local placed = -1
				local outs, back = 0, 0
				local wasOut = false
				local frames = 0
				local show = PaintballClient.show()
				assert(show, "the show is on")
				local seen: { [number]: boolean } = {} -- other slots' balls drawn on this screen
				local others = 0
				local sighted = 0 -- looks taken at an opponent in clear sight
				local folder = workspace.CurrentCamera:FindFirstChild("PaintballShow")
				local puffSeen: { [any]: boolean } = {}
				local puffs = 0
				local hops, sprints, crouches = 0, 0, 0
				for _ = 1, seconds * 60 do
					frames += 1
					for _, ball in show.balls do
						if not ball.own and ball.born and not seen[ball.key] then
							seen[ball.key] = true
							others += 1
						end
					end
					-- (a puff is where the player's own ball met a body on this screen)
					for _, c in if folder then folder:GetChildren() else {} do
						if c.Name == "Puff" and not puffSeen[c] then
							puffSeen[c] = true
							puffs += 1
						end
					end
					if seat.out ~= wasOut then
						wasOut = seat.out
						if wasOut then
							outs += 1
						else
							back += 1
						end
					end
					-- a new placement: the way out is planned afresh from where the server put the body
					if seat.place ~= placed and not seat.out then
						placed = seat.place
						local x, y, z = v.feet()
						route = wayOut(v.arena, x, y, z, 6)
						leg = 1
						v.target = nil
					end
					if v.target == nil and #route > 0 and not seat.out then
						-- out along the route, then to and fro on its last link: walked, sprinted, crouched in turn
						if leg > #route then
							leg = #route - 1
						end
						local node = route[leg]
						v.target = { x = node.x, z = node.z }
						leg += 1
						legs += 1
						local mode = if leg <= #route then 0 else legs % 3
						Rig.key(Key.LeftShift, mode == 1)
						Rig.key(Key.C, mode == 2)
						if mode == 1 then
							sprints += 1
						elseif mode == 2 then
							crouches += 1
						end
					end
					-- a hop every four seconds or so, wherever the legs are (never crouched: C is held)
					if frames % 251 == 0 and v.hop == nil and not seat.out and not seat.wantCrouch then
						v.hop = 0
						hops += 1
					end
					-- the look: at the nearest opponent in clear sight (aimed a little high for the drop, not
					-- led: a walker is often missed, as a person misses), else at a wall
					if frames % 6 == 0 and not seat.out then
						local x, y, z = v.feet()
						local ex, ey, ez = Body.eyePoint(x, y, z, seat.c)
						local best: any, bestD = nil, 90
						for id, p in show.puppets do
							local open = p.shown
								and p.team ~= seat.team
								and id ~= seat.you
								and not Wire.has(p.bits, Wire.BIT.out)
								and not Wire.has(p.bits, Wire.BIT.safe)
							if open then
								local cx, cy, cz = p.x, p.y + Arena.CHEST, p.z
								local d = math.sqrt((cx - ex) ^ 2 + (cy - ey) ^ 2 + (cz - ez) ^ 2)
								if d < bestD and v.arena.sweep(ex, ey, ez, cx, cy, cz) == nil then
									best, bestD = p, d
								end
							end
						end
						if best then
							local flight = bestD / seat.feel.ballSpeed
							local rise = 0.5 * seat.feel.ballDrop * flight * flight
							v.look(Body.yawPitch(best.x - ex, best.y + Arena.CHEST + rise - ey, best.z - ez))
							sighted += 1
						elseif frames % 60 == 0 then
							local ok, yaw = pcall(wallYaw, v.arena, x, y, z, 6, 80)
							if ok then
								v.look(yaw, 0)
							end
						end
					end
					if frames % 7 == 0 then
						Rig.mouse(true)
						Rig.mouse(false)
					end
					v.frame()
				end
				-- quiet for a moment, so every click has its answer
				v.target = nil
				Rig.key(Key.LeftShift, false)
				Rig.key(Key.C, false)
				v.run(1.0 + lag / 30)
				local stats = v.service:stats()
				local ok, refused = v.acks()
				local tags, mine = 0, 0
				for _, msg in v.w.got do
					if type(msg) == "table" and msg.kind == "paintball_tag" then
						tags += 1
						if msg.by == seat.you then
							mine += 1
						end
					end
				end
				line =
					`{seconds} s among the real bots at {math.floor(lag * 2000 / 60 + 0.5)} ms round trip: {v.fires()} balls fired ({ok} acked, {refused} refused); {sprints} legs sprinted, {crouches} crouched, {hops} hops; an opponent in sight {sighted} times, {puffs} balls met a body on this screen and the server counted {mine} tags; tagged out {outs} time(s); {others} of the bots' balls drawn, {tags} tags heard; {stats.movesAccepted} poses accepted, {stats.movesRefused} refused, {stats.movesDropped} dropped, {stats.corrections} corrections`
				print("      " .. line)
				settled(v, t, "among the bots", outs)
				t.truthy(v.fires() >= seconds / 2, "the marker was fired all the way through")
				t.eq(back, if seat.out then outs - 1 else outs, "every time out was followed by a respawn")
				if not seat.out and seat.mag.reloadDoneAt == nil then
					t.eq(seat.mag.rounds, serverRounds(v), "the pips are the server's count")
				end
				local state = v.state()
				t.eq(seat.scores[1], state.scores[1], "the HUD's score is the match's")
				t.eq(seat.scores[2], state.scores[2])
				for _, splat in show.walls do
					t.falsy(splat.predicted, "no predicted splat is left waiting")
				end
			end, { lag = lag, lose = lose })
			t.truthy(line ~= "")
		end)
	end

	fight(
		"a minute and a half among the real bots at 100 ms: walking, sprinting, crouching, hopping, aiming at whoever is in sight and firing as fast as the marker lets go; nothing of an honest client is refused",
		90,
		3,
		nil
	)
	fight("and a minute at 300 ms with one unreliable packet in twenty lost: the same", 60, 9, 20)

	t.test(
		"two people: the player joins a running match on the other side and is shown it so far; is tagged by the other person and told who and where from; changes sides to play with her; she leaves and a bot has her seat",
		function()
			local bea: Person
			play(function(v)
				local w = v.w
				v.run(0.5)
				local seat = v.seat()
				local show = PaintballClient.show()
				assert(show, "the show is on")
				-- A LATE SEAT: a bot's, on the side with fewer people, in a match already live
				t.truthy(seat.you ~= bea.seat and seat.you >= 1)
				t.truthy(seat.team ~= bea.team, "on the other side from the person already in: the sides stay level")
				t.eq(seat.phase, "live", "the match is running")
				t.truthy(seat.place >= 1 and inOwnRoom(v), "placed in its spawn room")
				t.truthy(seat:protected(v.now()) ~= nil, "protected as it comes in")
				t.truthy(string.find(Rig.screen(w), "Left button  fire", 1, true), "the controls card, for a moment")
				-- the match so far: the roster with a person in it, and her paint on the wall
				local her = show.slots[bea.seat]
				t.truthy(her ~= nil and her.bot == false and her.name == "Bea", "the roster knows Bea is a person")
				local paint = 0
				for _, splat in show.walls do
					if splat.by == bea.seat then
						paint += 1
					end
				end
				t.eq(paint, R.magazine, "the paint of the match so far is on the walls")
				local puppet = show.puppets[bea.seat]
				t.truthy(puppet ~= nil and puppet.shown, "and she is drawn")
				t.near(puppet.x, bea.x, 0.5, "where she stands")
				t.near(puppet.z, bea.z, 0.5)
				settled(v, t, "the late seat")
				-- TAGGED BY HER: who, and the tick that points at where she stood
				t.truthy(v.untilTrue(seat.feel.protectSecs + 1, function(): boolean
					return seat:protected(v.now()) == nil
				end))
				local ok, why = v.service:debug("tag", bea.seat, seat.you)
				t.truthy(ok, tostring(why))
				t.truthy(v.untilTrue(1, function(): boolean
					return seat.out
				end))
				v.run(0.3)
				local words = v.words()
				t.truthy(Rig.has(words, "TAGGED OUT by Bea"), table.concat(words, " | "))
				t.truthy(Rig.has(words, "Bea tagged Ann"), "and in the feed")
				local from = seat.tagFrom
				assert(from, "where the ball came from is known")
				t.near(from.x, bea.x, 0.5)
				t.near(from.z, bea.z, 0.5)
				-- CHANGE SIDES while out: to play WITH her (the other side has a bot to trade with)
				local was = seat.team
				Rig.key(Key.G, true)
				v.run(0.2)
				Rig.click(w, "Change sides")
				v.run(0.5)
				Rig.key(Key.G, false)
				t.truthy(
					v.untilTrue(2, function(): boolean
						return seat.team ~= was
					end),
					"the side changed"
				)
				t.eq(seat.team, bea.team, "friends on one side")
				t.eq(v.state().slots[seat.you].team, seat.team)
				t.truthy(
					v.untilTrue(seat.feel.respawnSecs + 1.5, function(): boolean
						return not seat.out
					end),
					"placed on the new side"
				)
				v.run(0.2)
				t.truthy(inOwnRoom(v), "in the new side's spawn room")
				t.eq(show:teamOf(seat.you), seat.team, "the show knows it too")
				local puppets = show.puppets[bea.seat]
				t.eq(puppets.team, seat.team, "and Bea's puppet is a team-mate's now")
				-- SHE LEAVES: a bot has her seat, and the roster says so on this screen
				w.svc:leave(bea.stub)
				t.truthy(
					v.untilTrue(2, function(): boolean
						local slot = show.slots[bea.seat]
						return slot ~= nil and slot.bot == true
					end),
					"a bot has her seat"
				)
				t.truthy(show.slots[bea.seat].name ~= "Bea")
				settled(v, t, "two people")
				t.eq(w.client.active(), STATION, "and the player plays on")
			end, {
				asleep = true,
				first = function(v)
					-- Bea starts a match, walks out of her spawn room and empties a magazine at a wall
					bea = person(v, "Bea")
					v.run(0.5)
					t.truthy(bea.seat >= 1 and bea.place >= 1, "Bea is seated and placed")
					bea.team = v.state().slots[bea.seat].team
					t.truthy(v.service:debug("end"))
					v.run(v.state().feel.protectSecs + 0.5)
					local route = wayOut(v.arena, bea.x, bea.y, bea.z, 2)
					for _, node in route do
						bea.walkTo(node.x, node.z)
					end
					local yaw = wallYaw(v.arena, bea.x, bea.y, bea.z, 12, 60)
					for _ = 1, R.magazine do
						bea.fire(yaw)
						v.run(v.state().feel.fireInterval + 0.05)
					end
					v.run(1.5)
					t.eq(v.service:stats().shotsRefused, 0, "the scripted person's own clicks were good")
				end,
			})
		end
	)

	t.test(
		"standing idle: the screen says so a full warning before the real server takes the player off, through a tremble of the mouse, a shuffle of the feet, being tagged and coming back",
		function()
			play(function(v)
				local w = v.w
				v.run(0.5)
				local seat = v.seat()
				local slot = v.state().slots[seat.you]
				local yaw = v.arena.spawns[seat.team][slot.spawn].yaw
				t.truthy(v.service:debug("end"))
				t.truthy(v.untilTrue(2, function(): boolean
					return seat.phase == "live"
				end))
				local liveAt = v.now()
				local x0, _, z0 = v.feet()
				-- twenty seconds of a hand on the mouse and a foot on W that the server does not count as being
				-- there (inside its half stud and twentieth of a radian of where the count began)
				for i = 1, 10 do
					v.look(yaw + (if i % 2 == 0 then 0.03 else -0.03), 0)
					t.truthy(v.walk(x0 + (if i % 2 == 0 then 0 else 0.3), z0, 2))
					v.run(2 - 0.3)
				end
				t.eq(seat:idle(v.now()), nil, "not yet")
				-- tagged out and placed again: the count runs on through both, on the server and here
				local other = 0
				for id, s in v.state().slots do
					if s.on and s.team ~= seat.team and other == 0 then
						other = id
					end
				end
				local ok, why = v.service:debug("tag", other, seat.you)
				t.truthy(ok, tostring(why))
				t.truthy(v.untilTrue(seat.feel.respawnSecs + 2, function(): boolean
					return seat.out
				end))
				t.truthy(v.untilTrue(seat.feel.respawnSecs + 2, function(): boolean
					return not seat.out
				end))
				-- the warning comes; the server acts no sooner than a full warning later
				local warnedAt: number? = nil
				local said = false
				local gone = v.untilTrue(R.idleSecs + 5 - (v.now() - liveAt), function(): boolean
					if w.client.active() ~= STATION then
						return true
					end
					if warnedAt == nil and seat:idle(v.now()) ~= nil then
						warnedAt = v.now()
					end
					if warnedAt ~= nil and not said then
						for _, word in v.words() do
							said = said or string.find(word, "Still there", 1, true) ~= nil
						end
					end
					return false
				end)
				t.truthy(gone, "the server took the idle player off")
				local offAt = v.now()
				t.truthy(offAt - liveAt >= R.idleSecs - 0.1, "by the idle rule, not sooner")
				assert(warnedAt, "the screen warned")
				t.truthy(said, "in words on the HUD")
				t.truthy(
					offAt - warnedAt >= Tuning.idleWarn - 0.5,
					`a full warning before the server acted ({string.format("%.2f", offAt - warnedAt)} s)`
				)
				t.eq(w.body:GetAttribute("CameraZone"), nil, "and first person was let go")
			end, { asleep = true })
		end
	)

	-- FROM THE STREET, the join's own end-to-end case: the real pass desk on the town's money, the door, a short
	-- match among the real bots to the end card, and out again
	t.test(
		"from the street: a person walks to the station, buys the pass at the desk, joins, plays a short match against the real bots to the end card, and leaves",
		function()
			local purse: Purse = { cents = 27, paid = {} }
			local inLobby = false
			local seated = play(function(v)
				local w = v.w
				t.truthy(inLobby, "the walk to the desk came first")
				v.run(0.5)
				local seat = v.seat()
				-- SEATED: first person, the spawn room, the briefing
				t.eq(w.body:GetAttribute("CameraZone"), "lockFirstPerson", "brief 14: first person in the match")
				t.truthy(inOwnRoom(v), "placed in its own spawn room")
				t.eq(seat.phase, "briefing")
				t.eq(#purse.paid, 1, "the door charges nothing: the pass is checked, not sold")
				-- LIVE: out of the room and five balls at a wall
				t.truthy(v.service:debug("end"))
				t.truthy(
					v.untilTrue(2, function(): boolean
						return seat.phase == "live"
					end),
					"the match goes live"
				)
				t.truthy(v.untilTrue(4, function(): boolean
					return seat:protected(v.now()) == nil
				end))
				walkOut(v, t)
				local x, y, z = v.feet()
				v.look(wallYaw(v.arena, x, y, z, 12, 60), 0)
				v.run(0.2)
				for _ = 1, 6 do
					Rig.mouse(true)
					Rig.mouse(false)
					v.run(0.3)
				end
				-- the real bots have their way with the building for a few seconds; the player keeps firing
				for _ = 1, 8 * 4 do
					Rig.mouse(true)
					Rig.mouse(false)
					v.run(0.25)
				end
				local show = PaintballClient.show()
				assert(show, "the show is on")
				t.truthy(v.fires() >= 5, `{v.fires()} balls fired`)
				t.truthy(#show.walls > 0, "paint on the walls")
				local stats = v.service:stats()
				t.eq(stats.movesRefused, 0, "no pose of an honest client refused")
				-- FULL TIME: the bulletin with every player's line
				t.truthy(v.service:debug("end"))
				t.truthy(
					v.untilTrue(2, function(): boolean
						return seat.phase == "ended"
					end),
					"the client hears full time"
				)
				v.run(0.5)
				local screen = Rig.screen(w)
				t.truthy(string.find(screen, "FULL TIME", 1, true), screen)
				t.truthy(string.find(screen, "The next match starts in", 1, true))
				-- LEAVE from the end card: first person is let go and the server walks the body to the lobby
				Rig.click(w, "Leave the match")
				v.run(0.5)
				t.eq(w.client.active(), nil, "left")
				t.eq(PaintballClient.seat(), nil)
				t.eq(w.body:GetAttribute("CameraZone"), nil, "first person released")
				local lx, _, lz = v.feet()
				t.truthy(not Arena.inVolume(lx, 1, lz), "the server put the body in the lobby")
				-- the last person gone, the match is over and nothing more is shown (the bots do not play alone)
				t.truthy(
					v.untilTrue(2, function(): boolean
						return PaintballClient.show() == nil
					end),
					"the show is over"
				)
				-- and back out into the street
				t.truthy(v.walk(0, 88, 10) and v.walk(0, 106, 10), "out of the front door")
				v.run(1)
				t.eq(PaintballClient.show(), nil)
				t.eq(purse.cents, 7, "20c, once")
			end, {
				purse = purse,
				first = function(v)
					local w = v.w
					-- IN THE STREET in front of the station, out of the audience's reach, with 27c and no pass
					local sx, sy, sz = Arena.toWorld(v.place, 0, 0, 106)
					w.body:PivotTo(CFrame.new(sx, sy + ROOT, sz))
					v.run(1)
					t.eq(PaintballClient.show(), nil, "nothing of the match is shown in the street")
					-- the door is shut to a player with no pass
					Rig.press(w, STATION)
					v.run(0.5)
					t.eq(w.client.active(), nil, "no pass, no match")
					-- THE WALK: through the front door into the lobby, to the pass desk (an empty arena shows nothing:
					-- no match is on until somebody joins)
					t.truthy(v.walk(0, 88, 10), "to the front door")
					t.truthy(v.walk(Arena.DESK.x, Arena.DESK.z + 3, 10), "to the pass desk")
					inLobby = true
					v.run(1)
					t.eq(PaintballClient.show(), nil, "an empty arena costs nothing")
					-- THE DESK: 20c for the pass, once; a second press says so and takes nothing
					local toasts = #w.toasts
					Rig.press(w, Contract.DESK)
					v.run(0.5)
					t.eq(purse.cents, 7, "20c taken")
					t.deepEq(purse.paid, { "a paintball pass" })
					t.eq(w.client.active(), nil, "the desk seats nobody")
					t.truthy(
						Rig.has({ table.unpack(w.toasts, toasts + 1) }, Contract.textFor("bought")),
						table.concat(w.toasts, " | ")
					)
					Rig.press(w, Contract.DESK)
					v.run(0.5)
					t.eq(purse.cents, 7, "nothing more")
					t.truthy(Rig.has(w.toasts, Contract.textFor("has_pass")), table.concat(w.toasts, " | "))
					-- to the arena door (play presses it)
					t.truthy(v.walk(Arena.GATE.x, Arena.GATE.z + 3, 10), "to the arena door")
				end,
			})
			t.truthy(seated, "seated at the door with the pass")
		end
	)
end
