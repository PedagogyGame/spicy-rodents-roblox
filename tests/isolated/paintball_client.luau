--!strict
-- tests/isolated/paintball_client.luau: cases for tests/unit/paintball_client.spec.luau, run in their own Lune
-- process (tests/lib/Isolated) because they install fake engine globals (tests/lib/FakeEngine).
-- The paintball client played through the real framework on the fake engine: the real MinigameService and
-- MinigameClient (tests/lib/MinigameRig), paintball's own remotes beside them (tests/lib/PaintballRig: every
-- pose and click the client fires goes through the real Shared/Net, its layouts and its rate limits), the
-- client's real World, Self, Marker, Hud and Controls on fake Instances. THE CASE PLAYS THE SERVER: the stub
-- service's join is replaced so the framework seats the player; snapshots, shots and splats are fired through
-- the rig's port and paintball's kinds are sent through the stub service's ctx, each one held to
-- Wire.checkMessage first. Keys, the mouse, a gamepad and fingers go in; what is drawn (parts, the HUD's words,
-- the camera's offset) and what is sent comes out.
-- The building is the kit's own small one (tests/isolated/paintball_client_kit.luau) unless a case asks for the
-- arena lane's: ArenaData.build is replaced for the length of a case, so no case leans on rooms that lane owns.
-- Interface: return function(t) (the spec shape)
local Kit = require("@tests/isolated/paintball_client_kit")
local Arena = require("@shared/Minigames/Paintball/Arena")
local ArenaData = require("@shared/Minigames/Paintball/ArenaData")
local Ballistics = require("@shared/Paintball/Ballistics")
local Body = require("@shared/Minigames/Paintball/Body")
local Clock = require("@shared/Minigames/Paintball/Clock")
local Contract = require("@shared/Minigames/Paintball/Contract")
local Rules = require("@shared/Minigames/Paintball/Rules")
local Wire = require("@shared/Minigames/Paintball/Wire")
local PaintballClient = require("@client/Minigames/Paintball/PaintballClient")
local Tuning = require("@client/Minigames/Paintball/Tuning")
local FakeEngine = require("@tests/lib/FakeEngine")
local PaintballRig = require("@tests/lib/PaintballRig")
local Rig = require("@tests/lib/MinigameRig")
local roblox = require("@lune/roblox")

local R = Contract.Rules
local F = Contract.FEEL
local BIT = Wire.BIT
local Key = roblox.Enum.KeyCode
local Kind = roblox.Enum.UserInputType
local CFrame, Vector3 = roblox.CFrame, roblox.Vector3
local STATION = Contract.STATION

-- The server the case plays.
type Server = {
	w: Rig.World,
	wires: PaintballRig.Wires,
	service: any,
	place: Arena.Place,
	you: number,
	now: () -> number,
	state: () -> any, -- the match model's State (Rules.State)
	send: (msg: { [string]: any }) -> (), -- ctx.send to the player
	broadcast: (msg: { [string]: any }) -> (),
	snap: (bodies: { any }, t: number?) -> (),
	shots: (records: { any }) -> (),
	splats: (records: { any }) -> (),
	live: () -> (), -- the briefing is over
	respawn: (over: { [string]: any }?) -> (),
	run: (seconds: number, bodies: { any }?) -> (), -- frames, with a snapshot of `bodies` every third
	hud: () -> any,
	show: () -> any, -- the Folder the show is drawn in
	hum: any, -- the fake Humanoid on the player's body
}

local function world(w: Rig.World, wires: PaintballRig.Wires): Server
	local tbl = PaintballRig.table(w)
	local service = tbl.service
	local s = { w = w, wires = wires, service = service, place = service.place, you = 0 } :: Server
	-- a Humanoid on the body, as the possessed R15 body has
	local hum = FakeEngine.new("Humanoid", "Humanoid", {
		HipHeight = 2,
		JumpHeight = 7.2,
		UseJumpPower = true,
		CameraOffset = Vector3.new(0, 0, 0),
		FloorMaterial = roblox.Enum.Material.Plastic,
	})
	hum.Parent = w.body
	rawset(w.player, "UserId", 41) -- (the roster the case sends names the player by it)
	rawset(w.body.PrimaryPart, "Size", Vector3.new(2, 2, 1))
	s.hum = hum
	s.now = function(): number
		return Rig.SERVER_TIME + w.frames / 60
	end
	s.state = function(): any
		return service.ctx.session.game.state
	end
	local function checked(msg: { [string]: any })
		local ok, err = Wire.checkMessage(msg)
		assert(ok, `not a message the server may send: {tostring(err)}`)
	end
	s.send = function(msg: { [string]: any })
		checked(msg)
		service.ctx.send(w.player, msg)
	end
	s.broadcast = function(msg: { [string]: any })
		checked(msg)
		service.ctx.broadcast(msg)
	end
	s.snap = function(bodies: { any }, t: number?)
		wires.port.fire(w.player, "Paintball.Snap", Wire.encodeSnap(t or s.now(), w.frames, service.match, bodies))
	end
	s.shots = function(records: { any })
		wires.port.fire(w.player, "Paintball.Shot", Wire.pack(Wire.Shot, records))
	end
	s.splats = function(records: { any })
		wires.port.fire(w.player, "Splat", Wire.pack(Wire.Splat, records))
	end
	s.live = function()
		local state = s.state()
		-- (a server goes live when the briefing it announced is over, never before)
		while s.now() < state.endsAt do
			PaintballRig.frame(wires, w)
		end
		state.phase = "live"
		state.endsAt = s.now() + R.matchSecs
		service.ctx.dirty()
	end
	s.respawn = function(over: { [string]: any }?)
		local o: { [string]: any } = over or {}
		local seat = PaintballClient.seat()
		s.broadcast({
			kind = "paintball_respawn",
			id = o.id or s.you,
			x = o.x or 0,
			y = o.y or 0,
			z = o.z or 30,
			yaw = o.yaw or 0,
			at = o.at or (s.now() - 10),
			place = o.place or Wire.nextPlace(if seat then seat.place else 0),
		})
	end
	s.run = function(seconds: number, bodies: { any }?)
		for _ = 1, math.max(1, math.floor(seconds * 60 + 0.5)) do
			if bodies and w.frames % 3 == 0 then
				s.snap(bodies)
			end
			PaintballRig.frame(wires, w)
		end
	end
	s.hud = function(): any
		return w.player:FindFirstChild("PlayerGui"):FindFirstChild("PaintballHud")
	end
	s.show = function(): any
		return workspace.CurrentCamera:FindFirstChild("PaintballShow")
	end
	return s
end

-- A case on the rig with the stream. opts: arena = "lane" for ArenaData's own; rig = MinigameRig opts; wires.
local function play(fn: (s: Server) -> (), opts: { [string]: any }?)
	local o: { [string]: any } = opts or {}
	local wires = PaintballRig.new(o.wires)
	local build = ArenaData.build
	if o.arena ~= "lane" then
		ArenaData.build = Kit.arena
	end
	local ok, err = pcall(Rig.play, function(w: Rig.World)
		PaintballRig.attach(wires, w)
		fn(world(w, wires))
	end, PaintballRig.opts(wires, o.rig))
	ArenaData.build = build
	if not ok then
		error(err, 0)
	end
end

-- The player walks up and joins; the server says who is in the match. Returns once the seat is open, with
-- `briefing` seconds of briefing still to run (default: the whole ten).
local function join(s: Server, briefing: number?)
	local w, service = s.w, s.service
	service.match = 1
	service.join = function(): (boolean, string?)
		return true, nil
	end
	Rig.press(w, STATION)
	s.run(0.2)
	assert(w.client.active() == STATION, "the framework seated the player")
	Rules.sync(s.state(), s.now()) -- the model is slaved to the shared clock (the real service does this)
	if briefing then
		s.state().endsAt = s.now() + briefing
	end
	service.ctx.dirty()
	local joined = Rig.last(w.got, "joined")
	s.you = joined.seat
	local slots = {}
	for id, slot in s.state().slots do
		if slot.on then
			local seat = service.ctx.session.names[id]
			table.insert(slots, {
				id = id,
				team = slot.team,
				name = seat or `Bot {id}`,
				bot = id ~= s.you,
				user = if id == s.you then 41 else 0,
			})
		end
	end
	s.send({ kind = "paintball_watch", match = 1, slots = slots, now = s.now(), feel = Contract.feel() })
	s.run(0.2)
end

-- Joined, placed in the open at (0, 0, 30) looking north, the match live.
local function playing(s: Server, over: { [string]: any }?)
	join(s, 0.3)
	s.live()
	s.respawn(over)
	s.run(0.3)
end

-- Put the body somewhere (the arena frame's feet point), as walking there would.
local function stand(s: Server, x: number, y: number, z: number)
	local wx, wy, wz = Arena.toWorld(s.place, x, y, z)
	s.w.body:PivotTo(CFrame.new(wx, wy + 3, wz))
end

-- Turn the view (the stock camera's doing, so not a move the rig should mind).
local function aim(s: Server, yaw: number, pitch: number)
	local cam = workspace.CurrentCamera
	local dx, dy, dz = Arena.dirToWorld(s.place, Body.look(yaw, pitch))
	local at = cam.CFrame.Position
	local cf = CFrame.lookAt(at, at + Vector3.new(dx, dy, dz))
	rawset(cam, "CFrame", cf)
	s.w.camWas = cf
end

local function click(s: Server)
	Rig.mouse(true)
	Rig.mouse(false)
	local _ = s
end

local function pad(code: any, down: boolean)
	FakeEngine.input(if down then "began" else "ended", { KeyCode = code, UserInputType = Kind.Gamepad1 })
end

local function heard(s: Server, remote: string): { { [string]: number } }
	return s.wires.heard[remote] or {}
end

local function named(root: any, name: string): any
	for _, d in root:GetDescendants() do
		if d.Name == name then
			return d
		end
	end
	return nil
end

local function count(root: any, name: string): number
	local n = 0
	for _, c in if root then root:GetChildren() else {} do
		if c.Name == name or (name == "Puppet" and c.ClassName == "Model") then
			n += 1
		end
	end
	return n
end

local function opponent(s: Server): number
	local mine = s.state().slots[s.you].team
	for id, slot in s.state().slots do
		if slot.on and slot.team ~= mine then
			return id
		end
	end
	error("no opponent seated")
end

local function mate(s: Server): number
	local mine = s.state().slots[s.you].team
	for id, slot in s.state().slots do
		if slot.on and slot.team == mine and id ~= s.you then
			return id
		end
	end
	error("no team-mate seated")
end

return function(t)
	t.test(
		"joining: first person is locked, the briefing is read, nothing is sent before the placement; leaving releases it all",
		function()
			play(function(s)
				local w = s.w
				t.eq(w.body:GetAttribute("CameraZone"), nil)
				join(s)
				local seat = PaintballClient.seat() :: PaintballClient.Seat
				t.truthy(seat ~= nil, "the seat is open")
				t.eq(seat.you, s.you)
				t.eq(w.body:GetAttribute("CameraZone"), "lockFirstPerson", "brief 14: locked to first person")
				t.eq(s.hum.JumpHeight, Body.JUMP_HEIGHT, "a hop, not a way over a rail")
				t.eq(s.hum.UseJumpPower, false)
				t.eq(FakeEngine.bound(), 1, "one render step for all of paintball")
				-- the lock is KEPT, not set once: another script writing the body's zone does not let the view out
				w.body:SetAttribute("CameraZone", "tunnel")
				s.run(0.05)
				t.eq(w.body:GetAttribute("CameraZone"), "lockFirstPerson", "first person for the whole match")
				-- and it follows the player onto another body (the seat opened before this one streamed in)
				local first = w.body
				local second = FakeEngine.model("Ann2", first.PrimaryPart.CFrame, nil)
				second.PrimaryPart = FakeEngine.part("HumanoidRootPart", first.PrimaryPart.CFrame, second)
				local hum2 = FakeEngine.new("Humanoid", "Humanoid", {
					HipHeight = 2,
					JumpHeight = 7.2,
					UseJumpPower = true,
					CameraOffset = Vector3.new(0, 0, 0),
					FloorMaterial = roblox.Enum.Material.Plastic,
				})
				hum2.Parent = second
				rawset(second.PrimaryPart, "Size", Vector3.new(2, 2, 1))
				w.body = second
				s.run(0.05)
				t.eq(second:GetAttribute("CameraZone"), "lockFirstPerson")
				t.eq(hum2.JumpHeight, Body.JUMP_HEIGHT)
				t.eq(first:GetAttribute("CameraZone"), nil, "the body left behind is as it was found")
				t.eq(s.hum.JumpHeight, 7.2)
				t.eq(s.hum.UseJumpPower, true)
				w.body = first
				s.run(0.05)
				t.eq(first:GetAttribute("CameraZone"), "lockFirstPerson")
				t.eq(second:GetAttribute("CameraZone"), nil)
				t.eq(hum2.JumpHeight, 7.2)
				-- the briefing: the controls card is the framework's help card; the HUD says which side and how long
				local hud = s.hud()
				t.truthy(hud ~= nil)
				local words = Rig.texts(hud)
				t.truthy(Rig.has(words, "BRIEFING"), table.concat(words, " | "))
				t.truthy(Rig.has(words, "You are ORANGE") or Rig.has(words, "You are TEAL"))
				t.truthy(Rig.has(words, "The match starts in"))
				local screen = Rig.screen(w)
				t.truthy(string.find(screen, "Left button  fire", 1, true), "the controls card")
				t.truthy(Rig.button(w.gui, "Leave the match") ~= nil, "a deliberate Leave")
				t.truthy(Rig.button(w.gui, "Change sides") ~= nil)
				t.eq(w.gui:FindFirstChild("Scorecard").Visible, false, "the framework's empty scorecard is put away")
				-- still at the arena door: no pose, no click
				click(s)
				s.run(0.5)
				t.eq(#heard(s, "Paintball.Move"), 0, "no Move before the first placement")
				t.eq(#heard(s, "Paintball.Fire"), 0)
				-- the server places the body in its spawn room
				local spawn = { x = -52, y = 0, z = 2, yaw = -math.pi / 2 }
				s.respawn({ x = spawn.x, y = spawn.y, z = spawn.z, yaw = spawn.yaw, at = s.now() + 2 })
				s.run(0.5)
				local p = w.body.PrimaryPart.Position
				local x, y, z = Arena.toLocal(s.place, p.X, p.Y - 3, p.Z)
				t.near(x, spawn.x, 1e-6, "the client pivots its own body")
				t.near(y, spawn.y, 1e-6)
				t.near(z, spawn.z, 1e-6)
				-- the look was turned to the placement's yaw through ONE hold, and the camera is free again
				t.deepEq(w.holds, { true, false })
				local look = workspace.CurrentCamera.CFrame.LookVector
				local dx, _, dz = Arena.dirToWorld(s.place, Body.look(spawn.yaw, 0))
				t.near(look.X, dx, 1e-6)
				t.near(look.Z, dz, 1e-6)
				local eye = workspace.CurrentCamera.CFrame.Position
				local _, ey = Arena.toLocal(s.place, eye.X, eye.Y, eye.Z)
				t.near(ey, Body.STAND_EYE, 1e-6, "from the eye's height")
				-- the pose stream, through the real Net: SEND_HZ a second, each with the placement it obeyed
				local before = #heard(s, "Paintball.Move")
				t.truthy(before >= 8)
				s.run(1)
				local moves = heard(s, "Paintball.Move")
				t.truthy(math.abs(#moves - before - Clock.SEND_HZ) <= 1, `{#moves - before} poses in a second`)
				t.eq(moves[#moves].place, 1)
				t.near(moves[#moves].x, spawn.x, 1e-4)
				t.near(moves[#moves].yaw, spawn.yaw, 1e-3)
				t.truthy(Rig.has(Rig.texts(hud), "SAFE in your spawn room"), "safe in your own room, and it says so")
				-- Q is not Leave here; the button is
				Rig.key(Key.Q, true)
				s.run(0.2)
				t.eq(w.client.active(), STATION)
				Rig.click(w, "Leave the match")
				s.run(0.3)
				t.eq(w.client.active(), nil)
				t.eq(PaintballClient.seat(), nil)
				t.eq(w.body:GetAttribute("CameraZone"), nil, "released")
				t.eq(s.hum.JumpHeight, 7.2)
				t.eq(s.hum.UseJumpPower, true)
				t.eq(s.hum.CameraOffset.Y, 0)
				t.eq(w.body:GetAttribute("MoveScale"), nil, "the pace is the town's again")
				t.eq(s.hud(), nil, "the HUD is gone")
				t.eq(workspace.CurrentCamera:FindFirstChild("PaintballMarker"), nil, "and the marker")
				t.eq(w.held, false)
				-- still in the lobby, still in the audience: the show goes on until the server says otherwise
				t.truthy(PaintballClient.show() ~= nil)
				s.send({ kind = "paintball_unwatch" })
				s.run(0.3)
				t.eq(PaintballClient.show(), nil)
				t.eq(s.show(), nil)
				t.eq(FakeEngine.bound(), 0, "nothing left bound")
				local sent = #heard(s, "Paintball.Move")
				s.run(0.5)
				t.eq(#heard(s, "Paintball.Move"), sent, "and nothing more is sent")
			end)
		end
	)

	t.test(
		"a click: the ball is drawn that frame, the server hears it with both stamps, the pips count down",
		function()
			play(function(s)
				playing(s)
				local w = s.w
				local hud = s.hud()
				local marker = workspace.CurrentCamera:FindFirstChild("PaintballMarker")
				t.truthy(marker ~= nil, "the marker is in view")
				t.eq(#marker:GetChildren(), 4)
				t.truthy(named(hud, "Cross").Visible)
				local at = s.now()
				click(s)
				PaintballRig.frame(s.wires, w)
				t.eq(count(s.show(), "Ball"), 1, "a ball is on screen in the frame of the click")
				local ball = named(s.show(), "Ball")
				local muzzle = (marker:FindFirstChild("Barrel").CFrame * CFrame.new(0, 0, -0.5)).Position
				t.truthy(
					(ball.CFrame.Position - muzzle).Magnitude < 2.5,
					"leaving the marker, not the middle of the screen"
				)
				s.run(0.2)
				local fires = heard(s, "Paintball.Fire")
				t.eq(#fires, 1, "through the real Net")
				t.eq(fires[1].shot, 1)
				t.near(fires[1].ft, at, 1e-9)
				t.truthy(fires[1].vt < fires[1].ft and fires[1].vt > fires[1].ft - 0.3)
				t.near(fires[1].oy, Body.STAND_EYE, 1e-4)
				t.near(fires[1].dz, -1, 1e-4, "along the look")
				-- the ball flies the server's curve: a third of a second on it is 30 studs out and half a stud low
				local bx, by, bz =
					Arena.toLocal(s.place, ball.CFrame.Position.X, ball.CFrame.Position.Y, ball.CFrame.Position.Z)
				local age = PaintballClient.show().balls[1].age
				local x, y, z =
					Ballistics.position(fires[1].ox, fires[1].oy, fires[1].oz, 0, 0, -F.ballSpeed, F.ballDrop, age)
				t.near(bx, x, 1e-3)
				t.near(by, y, 1e-3)
				t.near(bz, z, 1e-3)
				-- four pips lit
				local lit = 0
				for i = 1, R.magazine do
					if named(hud, `Pip{i}`).BackgroundColor3 ~= named(hud, "Pip5").BackgroundColor3 then
						lit += 1
					end
				end
				t.eq(lit, 4)
				s.send({ kind = "paintball_ack", shot = 1, ok = true, ball = 17, rounds = 4 })
				-- it meets the north wall and leaves your splat at once; the server's record takes its place
				s.run(0.8)
				t.eq(count(s.show(), "Ball"), 0)
				t.eq(count(s.show(), "Splat"), 1)
				local splat = PaintballClient.show().walls[1]
				t.truthy(splat.predicted)
				s.splats({
					{
						seq = 1,
						ball = 17,
						by = s.you,
						body = 0,
						team = 1,
						face = Wire.FACE.pz,
						x = splat.x + 0.2,
						y = splat.y,
						z = -40,
					},
				})
				s.run(0.3)
				t.eq(count(s.show(), "Splat"), 1, "one splat, the server's")
				t.falsy(PaintballClient.show().walls[1].predicted)
				s.run(2)
				t.eq(count(s.show(), "Splat"), 1, "and it stays")
			end)
		end
	)

	t.test("six clicks a second fire four balls and Net drops none; five, then the reload shows and rattles", function()
		play(function(s)
			playing(s)
			local start = s.now()
			for f = 0, 59 do
				if f % 10 == 0 then
					click(s)
				end
				PaintballRig.frame(s.wires, s.w)
			end
			s.run(0.3)
			local n = 0
			for _, rec in heard(s, "Paintball.Fire") do
				if rec.ft < start + 0.999 then
					n += 1
				end
			end
			t.eq(n, 4)
			-- the fifth empties it: the reload bar is up
			s.run(0.3)
			click(s)
			s.run(0.1)
			local hud = s.hud()
			t.eq(#heard(s, "Paintball.Fire"), 5)
			t.truthy(named(hud, "ReloadBar").Visible)
			t.truthy(Rig.has(Rig.texts(hud), "RELOADING"))
			t.falsy(named(hud, "Arm1").BackgroundTransparency == 0, "the crosshair says not ready")
			s.run(F.reloadSecs)
			t.falsy(named(hud, "ReloadBar").Visible)
			t.eq(named(hud, "Arm1").BackgroundTransparency, 0)
			-- R with a ball gone: the verb goes to the server with its stamp
			click(s)
			s.run(0.3)
			Rig.key(Key.R, true)
			Rig.key(Key.R, false)
			s.run(0.2)
			local reload = Rig.last(s.w.sent, "reload")
			t.truthy(reload ~= nil)
			t.truthy(math.abs(reload.args[1] - s.now()) < 0.5)
			-- (the stub service refuses every input with words: the client takes the reload back)
			t.truthy(Rig.last(s.w.got, "refused") ~= nil)
			t.eq((PaintballClient.seat() :: PaintballClient.Seat).mag.reloadDoneAt, nil)
		end)
	end)

	t.test(
		"sprint: Shift with W ramps the pace and widens the view; a click fires 0.15 s later; the server is told",
		function()
			play(function(s)
				playing(s)
				local w = s.w
				local cam = workspace.CurrentCamera
				local fov = cam.FieldOfView
				t.eq(w.body:GetAttribute("NoSprint"), true, "the town's Shift is off: the ramp is paintball's own")
				t.eq(w.body:GetAttribute("MoveScale"), nil, "walking pace")
				Rig.key(Key.LeftShift, true)
				s.run(0.3)
				t.eq(
					w.body:GetAttribute("MoveScale"),
					nil,
					"Shift alone, standing still: no sprint, the marker stays up"
				)
				Rig.key(Key.W, true)
				s.run(0.1)
				local mid = w.body:GetAttribute("MoveScale")
				t.truthy(mid > 1 and mid < F.sprintMult, "accelerating")
				s.run(0.4)
				t.near(w.body:GetAttribute("MoveScale"), F.sprintMult, 1e-9)
				t.truthy(cam.FieldOfView > fov + Tuning.sprintFov * 0.8, "the view widens")
				local marker = cam:FindFirstChild("PaintballMarker")
				local down = marker:FindFirstChild("Body").CFrame.Position.Y
				local sprintMoves = 0
				for _, move in heard(s, "Paintball.Move") do
					if Wire.has(move.bits, BIT.sprint) then
						sprintMoves += 1
					end
				end
				t.truthy(sprintMoves >= 5, "the sprint bit rides on the pose")
				-- the cost: the marker is down, and a click waits for it
				local at = s.now()
				click(s)
				t.near(w.body:GetAttribute("MoveScale"), F.sprintMult, 1e-9)
				PaintballRig.frame(s.wires, w)
				t.eq(count(s.show(), "Ball"), 0, "not yet")
				s.run(0.4)
				local fires = heard(s, "Paintball.Fire")
				t.eq(#fires, 1, "never lost")
				t.truthy(fires[1].ft >= at + Body.SPRINT_FIRE_DELAY - 1e-9)
				t.truthy(fires[1].ft < at + Body.SPRINT_FIRE_DELAY + 0.04)
				for _, move in heard(s, "Paintball.Move") do
					if Wire.has(move.bits, BIT.sprint) and move.t < fires[1].ft then
						t.truthy(move.t <= fires[1].ft - Body.SPRINT_FIRE_DELAY + Contract.MARGIN.sprint)
					end
				end
				-- let go: walking pace at once, the view eases back, the marker comes up
				Rig.key(Key.LeftShift, false)
				s.run(0.5)
				t.eq(w.body:GetAttribute("MoveScale"), nil)
				t.near(cam.FieldOfView, fov, 0.05)
				t.truthy(marker:FindFirstChild("Body").CFrame.Position.Y > down + 0.3, "it was lowered while sprinting")
				Rig.key(Key.W, false)
			end)
		end
	)

	t.test(
		"crouch: C sinks the camera for real, under the rail and back over it; the pace halves; the ball leaves lower",
		function()
			play(function(s)
				playing(s)
				local w = s.w
				t.eq(s.hum.CameraOffset.Y, 0, "standing: the stock eye")
				t.truthy(Body.STAND_EYE + s.hum.CameraOffset.Y > Arena.RAIL_HEIGHT)
				Rig.key(Key.C, true)
				s.run(0.1)
				t.truthy(s.hum.CameraOffset.Y < -0.4 and s.hum.CameraOffset.Y > -1.6, "sinking, not snapping")
				s.run(F.crouchSecs)
				t.near(s.hum.CameraOffset.Y, Body.CROUCH_EYE - Body.STAND_EYE, 1e-6)
				t.truthy(Body.STAND_EYE + s.hum.CameraOffset.Y < Arena.RAIL_HEIGHT, "hidden behind an atrium rail")
				t.near(w.body:GetAttribute("MoveScale"), 0.5, 1e-9)
				local moves = heard(s, "Paintball.Move")
				s.run(0.2)
				moves = heard(s, "Paintball.Move")
				t.truthy(Wire.has(moves[#moves].bits, BIT.crouch))
				click(s)
				s.run(0.2)
				t.near(heard(s, "Paintball.Fire")[1].oy, Body.CROUCH_EYE, 1e-4)
				-- up again in a fifth of a second: a peek over the rail
				Rig.key(Key.C, false)
				s.run(F.crouchSecs + 0.03)
				t.eq(s.hum.CameraOffset.Y, 0)
				t.eq(w.body:GetAttribute("MoveScale"), nil)
				-- Left Ctrl is the same key
				Rig.key(Key.LeftControl, true)
				s.run(0.3)
				t.near(s.hum.CameraOffset.Y, Body.CROUCH_EYE - Body.STAND_EYE, 1e-6)
				Rig.key(Key.LeftControl, false)
			end)
		end
	)

	t.test(
		"the audience: a player who only watches sees puppets, balls and paint, and not the real bodies twice",
		function()
			play(function(s)
				local w = s.w
				-- two real bodies in the town's Bodies folder: one is in the match, one is a passer-by
				local bodies = FakeEngine.new("Folder", "Bodies")
				bodies.Parent = workspace
				local function body(name: string, user: number): any
					local m = FakeEngine.model(name, CFrame.new(0, 0, 0), bodies)
					m:SetAttribute("DriverUserId", user)
					FakeEngine.part("Torso", CFrame.new(0, 0, 0), m)
					return m
				end
				local inMatch, passerBy = body("Cy", 77), body("Dee", 78)
				s.service.match = 4
				s.send({
					kind = "paintball_watch",
					match = 4,
					slots = {
						{ id = 1, team = 1, name = "Cy", bot = false, user = 77 },
						{ id = 2, team = 2, name = "Rusty", bot = true, user = 0 },
					},
					now = s.now(),
					feel = Contract.feel(),
				})
				s.run(0.2)
				t.eq(w.client.active(), nil, "in no game")
				t.eq(PaintballClient.seat(), nil)
				t.eq(FakeEngine.bound(), 1)
				local walk = 0
				local function people(): { any }
					walk += 0.05
					return {
						Kit.body(1, walk, 14, 0, { yaw = 0.5 }),
						Kit.body(2, 10, 14, 5, { crouch = 1, bits = BIT.crouch }),
					}
				end
				for _ = 1, 20 do
					s.run(0.05, people())
				end
				local show = s.show()
				t.eq(count(show, "Puppet"), 2, "a puppet for the person and one for the bot")
				local puppet = show:FindFirstChild("Puppet1")
				local torso = puppet:FindFirstChild("Torso")
				local orange = Contract.TEAMS[1].color
				t.near(torso.Color.R * 255, orange[1], 1)
				t.near(torso.Color.G * 255, orange[2], 1)
				t.eq(named(puppet, "NameTag"):FindFirstChildOfClass("TextLabel").Text, "Cy")
				local at = torso.CFrame.Position
				local x, y = Arena.toLocal(s.place, at.X, at.Y, at.Z)
				t.truthy(x > 0.3 and x < 1.1, "where the snapshots put it, a view-lag behind")
				t.near(y, 14 + Body.STAND_TOP * 0.625, 0.01)
				local low = show:FindFirstChild("Puppet2"):FindFirstChild("Head").CFrame.Position.Y
				t.truthy(
					low < puppet:FindFirstChild("Head").CFrame.Position.Y - 1.5,
					"a crouched puppet is drawn crouched"
				)
				for _, piece in puppet:GetChildren() do
					t.eq(piece.CanCollide, false)
					t.eq(piece.CanQuery, false, "a puppet is not found by a raycast")
				end
				-- the real body of the person in the match is hidden here; the passer-by is not
				t.eq(inMatch:FindFirstChild("Torso").LocalTransparencyModifier, 1)
				t.eq(passerBy:FindFirstChild("Torso").LocalTransparencyModifier, nil)
				-- a ball from a Shot record, and paint: on a wall, and riding on a puppet
				s.shots({ { ball = 3, id = 2, t = s.now(), ox = 10, oy = 18, oz = 5, vx = 0, vy = 0, vz = -90 } })
				s.run(0.3, people())
				t.eq(count(show, "Ball"), 1)
				s.splats({
					{ seq = 1, ball = 2, by = 2, body = 0, team = 2, face = Wire.FACE.px, x = 20, y = 15, z = 0 },
					{ seq = 2, ball = 5, by = 2, body = 1, team = 2, face = 0, x = 0.3, y = 3, z = -1.2 },
				})
				s.run(0.2, people())
				t.eq(count(show, "Splat"), 2)
				local onBody: any = nil
				for _, c in show:GetChildren() do
					if c.Name == "Splat" and c.Size.Y < 1.3 then
						onBody = c
					end
				end
				t.truthy(onBody ~= nil)
				local before = onBody.CFrame.Position
				for _ = 1, 10 do
					s.run(0.05, people())
				end
				t.truthy((onBody.CFrame.Position - before).Magnitude > 0.3, "the paint rides on the body")
				local teal = Contract.TEAMS[2].color
				t.near(onBody.Color.B * 255, teal[3], 1, "in the shooter's team colour, never red")
				-- the person leaves the roster: their body is shown again and their paint is gone
				s.send({
					kind = "paintball_watch",
					match = 4,
					slots = {
						{ id = 1, team = 1, name = "Gaffer", bot = true, user = 0 },
						{ id = 2, team = 2, name = "Rusty", bot = true, user = 0 },
					},
					now = s.now(),
					feel = Contract.feel(),
				})
				s.run(0.8, people())
				t.eq(inMatch:FindFirstChild("Torso").LocalTransparencyModifier, 0)
				t.eq(count(show, "Splat"), 1, "the wall's stays")
				-- out of the audience: everything goes
				s.send({ kind = "paintball_unwatch" })
				s.run(0.3)
				t.eq(s.show(), nil)
				t.eq(FakeEngine.bound(), 0)
			end)
		end
	)

	t.test(
		"your ball and a puppet: it stops on an opponent with a puff, passes a team-mate; the marker waits for the server",
		function()
			play(function(s)
				playing(s)
				local foe, friend = opponent(s), mate(s)
				local function bodies(): { any }
					return { Kit.body(s.you, 0, 0, 30), Kit.body(friend, 0, 0, 20), Kit.body(foe, 0, 0, 0) }
				end
				s.run(0.5, bodies())
				t.eq(count(s.show(), "Puppet"), 2, "your own slot is not drawn")
				click(s)
				s.run(0.45, bodies())
				t.eq(count(s.show(), "Ball"), 0, "through the team-mate, onto the opponent")
				t.eq(count(s.show(), "Splat"), 0, "no splat of your own on a body")
				local hud = s.hud()
				t.falsy(named(hud, "Hit").Visible, "no hit marker on the client's own say-so")
				t.eq(named(hud, "Score1").Text, "0")
				-- the server's word
				local mine = s.state().slots[s.you].team
				s.broadcast({
					kind = "paintball_tag",
					by = s.you,
					id = foe,
					ball = 9,
					scores = if mine == 1 then { 1, 0 } else { 0, 1 },
					tags = 1,
					outs = 1,
					at = s.now() + 4,
					x = 0,
					y = 4,
					z = 1.2,
				})
				s.run(0.1, bodies())
				t.truthy(named(hud, "Hit").Visible, "THE hit marker")
				t.eq(named(hud, `Score{mine}`).Text, "1")
				t.truthy(Rig.has(Rig.texts(hud), "Ann tagged"), "the feed says who tagged whom")
				s.run(Tuning.hitMarkerSecs + 0.1, bodies())
				t.falsy(named(hud, "Hit").Visible)
				-- the tagged puppet throws up a hand, then is walked off
				local out = {
					Kit.body(s.you, 0, 0, 30),
					Kit.body(friend, 0, 0, 20),
					Kit.body(foe, 0, 0, 0, { bits = BIT.out }),
				}
				s.run(0.5, out)
				local puppet = s.show():FindFirstChild(`Puppet{foe}`)
				t.truthy(puppet:FindFirstChild("Hand") ~= nil, "a raised hand")
				t.eq(puppet:FindFirstChild("Marker"), nil)
				s.run(Tuning.outHandSecs + 0.3, out)
				t.eq(s.show():FindFirstChild(`Puppet{foe}`), nil, "not drawn while out")
			end)
		end
	)

	t.test(
		"tagged out: the legs are taken, the screen says who and from where; the respawn brings it back, protected",
		function()
			play(function(s)
				playing(s)
				local w = s.w
				local foe = opponent(s)
				local function bodies(): { any }
					return { Kit.body(s.you, 0, 0, 30), Kit.body(foe, 20, 0, 30) } -- to the east: on the right
				end
				s.run(0.4, bodies())
				click(s)
				s.run(0.3, bodies())
				local sent = #heard(s, "Paintball.Move")
				local back = s.now() + F.respawnSecs
				s.broadcast({
					kind = "paintball_tag",
					by = foe,
					id = s.you,
					ball = 5,
					scores = { 0, 1 },
					tags = 1,
					outs = 1,
					at = back,
					x = 1,
					y = 3,
					z = 30,
				})
				s.run(0.3, bodies())
				local hud = s.hud()
				t.deepEq(w.controls, { false }, "the legs are taken")
				local words = Rig.texts(hud)
				t.truthy(Rig.has(words, "TAGGED OUT by"), table.concat(words, " | "))
				t.truthy(Rig.has(words, "back in 4"))
				t.truthy(named(hud, "Goggles").Visible, "paint on the goggles")
				t.falsy(named(hud, "Cross").Visible)
				local tick = named(hud, "TaggedFrom")
				t.truthy(tick.Visible)
				t.truthy(tick.Position.X.Offset > 80, "it came from the right")
				local stopped = #heard(s, "Paintball.Move")
				t.truthy(stopped <= sent + 2)
				click(s)
				s.run(1, bodies())
				t.eq(#heard(s, "Paintball.Move"), stopped, "no pose while out")
				t.eq(#heard(s, "Paintball.Fire"), 1, "and no ball")
				-- back in the spawn room
				local safe = s.now() + F.protectSecs
				s.respawn({ x = -52, z = 0, yaw = -math.pi / 2, at = safe })
				s.run(0.3)
				t.deepEq(w.controls, { false, true }, "the legs are back")
				t.falsy(Rig.has(Rig.texts(hud), "TAGGED OUT"))
				t.truthy(named(hud, "Cross").Visible)
				t.eq((PaintballClient.seat() :: PaintballClient.Seat).mag.rounds, R.magazine)
				t.truthy(#heard(s, "Paintball.Move") > stopped)
				-- walk out of the room while still protected: it says so, and no ball leaves
				stand(s, -30, 0, 0)
				s.run(0.3)
				t.truthy(Rig.has(Rig.texts(hud), "PROTECTED"))
				-- the protected moment is not one line of words: a border round the screen in your colour, a bar
				-- that drains, and the marker a ghost of itself
				local shield = named(hud, "Shield")
				t.truthy(shield.Visible, "the border")
				local mine = Contract.TEAMS[s.state().slots[s.you].team].color
				t.near(named(shield, "Top").BackgroundColor3.G * 255, mine[2], 1, "in your team's colour")
				local bar = named(shield, "ShieldBar"):FindFirstChild("Fill")
				local full = bar.Size.X.Scale
				t.truthy(full > 0.5 and full < 1, "the bar has begun to drain")
				local marker = workspace.CurrentCamera:FindFirstChild("PaintballMarker")
				t.eq(
					marker:FindFirstChild("Body").Transparency,
					Tuning.markerGhost,
					"the marker is a ghost: it cannot fire"
				)
				click(s)
				s.run(0.2)
				t.eq(#heard(s, "Paintball.Fire"), 1)
				t.truthy(bar.Size.X.Scale < full, "draining")
				s.run(F.protectSecs)
				t.falsy(shield.Visible, "gone the moment it is over")
				t.eq(marker:FindFirstChild("Body").Transparency, 0, "and the marker is solid again")
				t.falsy(Rig.has(Rig.texts(hud), "PROTECTED"))
				click(s)
				s.run(0.2)
				t.eq(#heard(s, "Paintball.Fire"), 2, "and after it, one does")
				s.run(Tuning.goggleSecs)
				t.falsy(named(hud, "Goggles").Visible, "the goggles have cleared")
			end)
		end
	)

	t.test(
		"the scoreboard on G: both sides and the tallies, a free cursor, Leave and Change sides; gone on release",
		function()
			play(function(s)
				playing(s)
				local w = s.w
				local hud = s.hud()
				t.eq(Rig.button(w.gui, "Leave the match"), nil, "nothing to press while playing: the mouse is the look")
				t.falsy(named(hud, "Board").Visible)
				t.falsy(named(hud, "Modal").Visible)
				t.eq(
					w.gui:FindFirstChild("Help").Visible,
					true,
					"the controls card stays up through a joiner's first moments"
				)
				s.run(Tuning.cardSecs)
				t.eq(w.gui:FindFirstChild("Help").Visible, false, "and is put away once the match is on")
				Rig.key(Key.G, true)
				s.run(0.4)
				t.truthy(named(hud, "Board").Visible)
				local words = Rig.texts(hud)
				t.truthy(Rig.has(words, "ORANGE") and Rig.has(words, "TEAL"), table.concat(words, " | "))
				t.truthy(Rig.has(words, "Ann (you)"))
				t.truthy(Rig.has(words, "(computer)"), "bots are on the board like anyone")
				t.truthy(named(hud, "Modal").Visible, "what frees a first-person mouse")
				t.eq(named(hud, "Modal").Modal, true)
				t.truthy(Rig.button(w.gui, "Leave the match") ~= nil)
				-- a click with the board up is for its buttons, not a shot
				click(s)
				s.run(0.2)
				t.eq(#heard(s, "Paintball.Fire"), 0)
				Rig.click(w, "Change sides")
				s.run(0.3)
				t.truthy(Rig.last(w.sent, "side") ~= nil, "the verb")
				t.truthy(Rig.last(w.got, "refused") ~= nil, "(the stub service says no, with words)")
				Rig.key(Key.G, false)
				s.run(0.2)
				t.falsy(named(hud, "Board").Visible)
				t.falsy(named(hud, "Modal").Visible)
				t.eq(Rig.button(w.gui, "Leave the match"), nil)
				click(s)
				s.run(0.2)
				t.eq(#heard(s, "Paintball.Fire"), 1)
			end)
		end
	)

	t.test(
		"gamepad: R2 fires, X reloads, B and L3 are toggles, View holds the scoreboard and Y leaves from it",
		function()
			play(function(s)
				playing(s)
				local w = s.w
				pad(Key.ButtonR2, true)
				pad(Key.ButtonR2, false)
				s.run(0.2)
				t.eq(#heard(s, "Paintball.Fire"), 1)
				pad(Key.ButtonX, true)
				s.run(0.2)
				t.truthy(Rig.last(w.sent, "reload") ~= nil)
				-- B: one press crouches and it stays; the framework's own B (leave) does not fire
				pad(Key.ButtonB, true)
				pad(Key.ButtonB, false)
				s.run(0.4)
				t.near(s.hum.CameraOffset.Y, Body.CROUCH_EYE - Body.STAND_EYE, 1e-6)
				t.eq(w.client.active(), STATION)
				pad(Key.ButtonB, true)
				pad(Key.ButtonB, false)
				s.run(0.4)
				t.eq(s.hum.CameraOffset.Y, 0)
				-- L3 with the stick pushed: sprint until a fire press
				Rig.key(Key.W, true)
				FakeEngine.input(
					"changed",
					{ KeyCode = Key.Thumbstick1, UserInputType = Kind.Gamepad1, Position = Vector3.new(0, 1, 0) }
				)
				pad(Key.ButtonL3, true)
				pad(Key.ButtonL3, false)
				s.run(0.5)
				t.near(w.body:GetAttribute("MoveScale"), F.sprintMult, 1e-9)
				s.run(F.reloadSecs)
				pad(Key.ButtonR2, true)
				s.run(0.5)
				t.eq(w.body:GetAttribute("MoveScale"), nil, "the fire press ended the toggled sprint")
				t.eq(#heard(s, "Paintball.Fire"), 2)
				-- and the stick let go ends one too
				pad(Key.ButtonL3, true)
				s.run(0.3)
				t.truthy(w.body:GetAttribute("MoveScale") ~= nil)
				FakeEngine.input(
					"changed",
					{ KeyCode = Key.Thumbstick1, UserInputType = Kind.Gamepad1, Position = Vector3.new(0, 0, 0) }
				)
				s.run(0.2)
				t.eq(w.body:GetAttribute("MoveScale"), nil)
				Rig.key(Key.W, false)
				-- Y alone does nothing; with View held it leaves
				pad(Key.ButtonY, true)
				s.run(0.2)
				t.eq(w.client.active(), STATION)
				pad(Key.ButtonSelect, true)
				s.run(0.3)
				t.truthy(named(s.hud(), "Board").Visible)
				pad(Key.ButtonY, true)
				s.run(0.3)
				t.eq(w.client.active(), nil, "left")
				pad(Key.ButtonSelect, false)
			end)
		end
	)

	t.test(
		"touch: FIRE does not sink its touch, a second FIRE on the left, CROUCH and SCORES toggle, a full push sprints",
		function()
			play(function(s)
				playing(s)
				local w = s.w
				local hud = s.hud()
				local fire = named(hud, "FireRight")
				t.truthy(fire ~= nil, "the buttons are up on a touch screen")
				t.eq(fire.ClassName, "Frame", "not a button: the touch goes on to the camera")
				t.eq(fire.Active, false)
				local vp = workspace.CurrentCamera.ViewportSize
				local fx, fy = vp.X * Tuning.touchFire[1], vp.Y * Tuning.touchFire[2]
				-- a finger lands on FIRE (not processed: nothing sank it), drags to look, lifts
				Rig.touch("a", "began", fx + 5, fy - 5)
				Rig.touch("a", "changed", fx - 60, fy - 20)
				Rig.touch("a", "ended", fx - 60, fy - 20)
				s.run(0.2)
				t.eq(#heard(s, "Paintball.Fire"), 1)
				-- a finger elsewhere on the right half only looks
				Rig.touch("b", "began", vp.X * 0.6, vp.Y * 0.3)
				Rig.touch("b", "ended", vp.X * 0.6, vp.Y * 0.3)
				s.run(0.3)
				t.eq(#heard(s, "Paintball.Fire"), 1)
				named(hud, "FireLeft").MouseButton1Down.fire()
				s.run(0.3)
				t.eq(#heard(s, "Paintball.Fire"), 2, "the left thumb's FIRE")
				named(hud, "Reload").MouseButton1Down.fire()
				s.run(0.2)
				t.truthy(Rig.last(w.sent, "reload") ~= nil)
				-- CROUCH is a toggle
				named(hud, "Crouch").MouseButton1Down.fire()
				s.run(0.4)
				t.near(s.hum.CameraOffset.Y, Body.CROUCH_EYE - Body.STAND_EYE, 1e-6)
				named(hud, "Crouch").MouseButton1Down.fire()
				s.run(0.4)
				t.eq(s.hum.CameraOffset.Y, 0)
				-- the stick: half way walks, a full push sprints, and it lasts until under half
				rawset(s.hum, "MoveDirection", Vector3.new(0.6, 0, 0))
				s.run(0.4)
				t.eq(w.body:GetAttribute("MoveScale"), nil)
				rawset(s.hum, "MoveDirection", Vector3.new(1, 0, 0))
				s.run(0.4)
				t.near(w.body:GetAttribute("MoveScale"), F.sprintMult, 1e-9)
				rawset(s.hum, "MoveDirection", Vector3.new(0.7, 0, 0))
				s.run(0.2)
				t.near(w.body:GetAttribute("MoveScale"), F.sprintMult, 1e-9, "still sprinting at 0.7")
				-- a fire press ends it, and it wants the stick eased before it starts again
				rawset(s.hum, "MoveDirection", Vector3.new(1, 0, 0))
				s.run(F.reloadSecs)
				named(hud, "FireLeft").MouseButton1Down.fire()
				s.run(0.5)
				t.eq(w.body:GetAttribute("MoveScale"), nil)
				rawset(s.hum, "MoveDirection", Vector3.new(0.4, 0, 0))
				s.run(0.1)
				rawset(s.hum, "MoveDirection", Vector3.new(1, 0, 0))
				s.run(0.4)
				t.near(w.body:GetAttribute("MoveScale"), F.sprintMult, 1e-9)
				rawset(s.hum, "MoveDirection", Vector3.new(0, 0, 0))
				-- SCORES opens the board with its buttons, and closes it
				named(hud, "Scores").MouseButton1Down.fire()
				s.run(0.4)
				t.truthy(named(hud, "Board").Visible)
				t.truthy(Rig.button(w.gui, "Leave the match") ~= nil)
				named(hud, "Scores").MouseButton1Down.fire()
				s.run(0.2)
				t.falsy(named(hud, "Board").Visible)
			end, { rig = { touch = true } })
		end
	)

	t.test(
		"the end card: the framework's, dressed as the bulletin, with the awards and no Play again; then the next match",
		function()
			play(function(s)
				playing(s)
				local w = s.w
				local state = s.state()
				local rows = {}
				for id, slot in state.slots do
					if slot.on then
						table.insert(rows, {
							id = id,
							team = slot.team,
							tags = if id == s.you then 6 else 1,
							outs = 2,
							shots = 20,
							hits = if id == s.you then 6 else 1,
							accuracy = if id == s.you then 0.3 else 0.05,
						})
					end
				end
				local winners = {}
				for id, slot in state.slots do
					if slot.on and slot.team == 1 then
						table.insert(winners, id)
					end
				end
				local result = {
					done = true,
					scores = {},
					winners = winners,
					text = "Orange wins 9 - 7",
					card = {
						winner = 1,
						scores = { 9, 7 },
						rows = rows,
						awards = {
							{ title = "Most Paint Wasted", id = opponent(s) },
							{ title = "Sharpest Eye", id = s.you },
						},
					},
				}
				local real = Rules.result
				Rules.result = function(): any
					return result
				end
				state.phase = "ended"
				s.run(1.5)
				Rules.result = real
				t.eq(s.service.ctx.session.phase, "done")
				local screen = Rig.screen(w)
				t.truthy(string.find(screen, "FULL TIME", 1, true), screen)
				t.truthy(string.find(screen, "Orange wins 9 - 7", 1, true))
				t.truthy(string.find(screen, "Ann (you)", 1, true), "each player's line")
				t.truthy(string.find(screen, "30%", 1, true), "tags, times out and aim")
				t.truthy(string.find(screen, "The next match starts in", 1, true))
				t.eq(string.find(screen, "Play again", 1, true), nil, "the next match starts by itself")
				t.eq(string.find(screen, "Leave (Q)", 1, true), nil, "Q is not Leave here")
				t.truthy(Rig.button(w.gui, "Leave the match") ~= nil)
				local hud = s.hud()
				local words = Rig.texts(hud)
				t.truthy(Rig.has(words, "WBLW CHANNEL 7 SPORTS"), table.concat(words, " | "))
				t.truthy(Rig.has(words, "Most Paint Wasted:"))
				t.truthy(Rig.has(words, "Sharpest Eye: Ann"))
				t.truthy(Rig.has(words, "FULL TIME"))
				t.truthy(named(hud, "Modal").Visible, "the cursor is free for Leave")
				t.falsy(named(hud, "Cross").Visible)
				-- nothing fires at the end card
				click(s)
				s.run(0.3)
				t.eq(#heard(s, "Paintball.Fire"), 0)
				-- sixteen lines are taller than a phone: there the card is scaled to fit, and only there
				local summary = w.gui:FindFirstChild("Summary")
				t.eq(summary:FindFirstChild("PaintballFit"), nil, "a desktop: the framework's card as it is")
				rawset(workspace.CurrentCamera, "ViewportSize", roblox.Vector2.new(844, 390))
				s.run(0.1)
				local fit = summary:FindFirstChild("PaintballFit")
				t.truthy(fit ~= nil and fit.Scale < 1)
				t.truthy(summary.Size.Y.Offset * fit.Scale <= 390, "every player's line is on the screen")
				rawset(workspace.CurrentCamera, "ViewportSize", roblox.Vector2.new(1920, 1080))
				-- the service rolls on: the next briefing, a clean HUD
				s.service.ctx.again()
				s.run(0.3)
				Rules.sync(s.state(), s.now())
				s.service.ctx.dirty()
				s.run(0.3)
				t.eq(w.client.active(), STATION, "still seated")
				words = Rig.texts(hud)
				t.truthy(Rig.has(words, "BRIEFING"), table.concat(words, " | "))
				t.falsy(named(hud, "Awards").Visible)
				t.truthy(Rig.button(w.gui, "Change sides") ~= nil)
				-- leaving takes off the framework's card whatever this game hung on it
				Rig.click(w, "Leave the match")
				s.run(0.3)
				t.eq(w.client.active(), nil)
				t.eq(summary:FindFirstChild("PaintballFit"), nil)
			end)
		end
	)

	t.test(
		"the arena lane's own building: the spawn room is safe and silent, the other team's curtains are shut to you",
		function()
			local curtains: { any } = {}
			play(function(s)
				join(s, 0.3)
				local arena = ArenaData.build()
				local mine = s.state().slots[s.you].team
				local other = if mine == 1 then 2 else 1
				t.eq(curtains[other].CanCollide, true, "solid on this screen only, and only the other team's")
				t.eq(curtains[mine].CanCollide, false)
				s.live()
				local spawn = arena.spawns[mine][1]
				s.respawn({ x = spawn.x, y = spawn.y, z = spawn.z, yaw = spawn.yaw })
				s.run(0.4)
				t.truthy(Rig.has(Rig.texts(s.hud()), "SAFE in your spawn room"))
				click(s)
				s.run(0.3)
				t.eq(#heard(s, "Paintball.Fire"), 0, "no ball from inside a spawn room")
				local moves = heard(s, "Paintball.Move")
				t.near(moves[#moves].y, spawn.y, 1e-3, "the middle storey")
				-- a curtain that streams in later is shut too
				local late = FakeEngine.part(Arena.CURTAIN .. other, CFrame.new(0, 0, 0), curtains[other].Parent)
				late.CanCollide = false
				s.run(1.2)
				t.eq(late.CanCollide, true)
				Rig.key(Key.G, true)
				s.run(0.2)
				Rig.click(s.w, "Leave the match")
				s.run(0.3)
				Rig.key(Key.G, false)
				t.eq(curtains[other].CanCollide, false, "and open again when you leave")
				t.eq(late.CanCollide, false)
			end, {
				arena = "lane",
				rig = {
					furnish = function(roots: { [string]: any })
						PaintballRig.furnish(roots)
						local model = roots[PaintballRig.SITE]:FindFirstChild(Arena.MODEL)
						local floor = FakeEngine.model("Floor3", CFrame.new(0, 0, 0), model)
						for team = 1, 2 do
							curtains[team] = FakeEngine.part(Arena.CURTAIN .. team, CFrame.new(0, 0, 0), floor)
							curtains[team].CanCollide = false
						end
					end,
				},
			})
		end
	)

	t.test(
		"a placement the server corrects: the body goes back, the stream carries the new number from the new place",
		function()
			play(function(s)
				playing(s)
				stand(s, 15, 0, 30)
				aim(s, 0.4, 0.1)
				s.run(0.4)
				local moves = heard(s, "Paintball.Move")
				t.near(moves[#moves].x, 15, 1e-3)
				t.near(moves[#moves].yaw, 0.4, 1e-3, "the look rides on the pose")
				t.near(moves[#moves].pitch, 0.1, 1e-3)
				s.send({ kind = "paintball_correct", x = 2, y = 0, z = 28, yaw = 0, why = "speed", place = 2 })
				s.run(0.4)
				for _, move in heard(s, "Paintball.Move") do
					if move.place == 2 then
						t.near(move.x, 2, 1e-3, "never the new number from the old place")
						t.near(move.z, 28, 1e-3)
					else
						t.eq(move.place, 1)
					end
				end
				moves = heard(s, "Paintball.Move")
				t.eq(moves[#moves].place, 2)
				t.truthy(Rig.has(Rig.texts(s.hud()), Contract.textFor("speed")), "and the screen says why")
			end)
		end
	)

	t.test(
		"standing idle: the screen says so before the server takes the player off; a turn of the view answers it",
		function()
			play(function(s)
				playing(s)
				local hud = s.hud()
				s.run(R.idleSecs - Tuning.idleWarn - 2)
				t.falsy(Rig.has(Rig.texts(hud), "Still there?"), "not yet")
				s.run(4)
				local words = Rig.texts(hud)
				t.truthy(
					Rig.has(words, "Still there? Move, or you are taken out of the match in"),
					table.concat(words, " | ")
				)
				aim(s, 0.3, 0)
				s.run(0.2)
				t.falsy(Rig.has(Rig.texts(hud), "Still there?"), "looking round is being there")
				-- and the marker still answers
				click(s)
				s.run(0.2)
				t.eq(#heard(s, "Paintball.Fire"), 1)
			end)
		end
	)

	t.test(
		"the eye is the contract's whatever the body: this game's own people stand with the root 3.2 up, not 3.0",
		function()
			play(function(s)
				-- (Avatar/PuppetSpec: HipHeight 2.2 under a root 2 high; the stock camera would sit at 4.7)
				s.hum.HipHeight = 2.2
				playing(s)
				local p = s.w.body.PrimaryPart.Position
				local _, rootY = Arena.toLocal(s.place, p.X, p.Y, p.Z)
				t.near(rootY, 3.2, 1e-6, "placed with its feet on the floor, not 0.2 into it")
				t.near(s.hum.CameraOffset.Y, -0.2, 1e-6, "the camera is brought to Body.eye over the feet")
				click(s)
				s.run(0.3)
				local fire = heard(s, "Paintball.Fire")[1]
				t.near(fire.oy, Body.STAND_EYE, 1e-4, "which is where the ball leaves from: the crosshair is true")
				local moves = heard(s, "Paintball.Move")
				t.near(moves[#moves].y, 0, 1e-4, "and the feet point on the wire is the feet")
				Rig.key(Key.C, true)
				s.run(F.crouchSecs + 0.1)
				t.near(3.2 + 1.5 + s.hum.CameraOffset.Y, Body.CROUCH_EYE, 1e-6, "crouched: the eye is at 2.7")
				t.truthy(3.2 + 1.5 + s.hum.CameraOffset.Y < Arena.RAIL_HEIGHT, "under the rail for this body too")
				Rig.key(Key.C, false)
				s.run(0.4)
				Rig.key(Key.G, true)
				s.run(0.2)
				Rig.click(s.w, "Leave the match")
				s.run(0.3)
				Rig.key(Key.G, false)
				t.eq(s.hum.CameraOffset.Y, 0, "and the town has its own eye back")
			end)
		end
	)

	t.test("the cues: every sound the client asks for is one the game declares, each still without an id", function()
		local declared = require("@client/Minigames/Games/Paintball").sounds
		local names = {}
		for cue, id in declared do
			t.eq(id, "", `{cue}: no id until the licensed sounds are chosen`)
			t.truthy(string.sub(cue, 1, 10) == "paintball.", cue)
			table.insert(names, cue)
		end
		t.eq(#names, 11)
		-- every cue a seat and a show can ask for, gathered from a played stretch on the headless bench
		local b = Kit.playing()
		Kit.snap(b, { Kit.body(2, 6, 0, 24) }, b.now() - 0.1)
		Kit.snap(b, { Kit.body(2, 6, 0, 24, { bits = BIT.reload }) }, b.now())
		b.show:onShots(
			Wire.pack(
				Wire.Shot,
				{ { ball = 3, id = 2, t = b.now(), ox = 6, oy = 4, oz = 24, vx = 0, vy = 0, vz = -90 } }
			)
		)
		local asked: { [string]: boolean } = {}
		local function gather()
			for _, sound in b.sounds do
				asked[sound.cue] = true
			end
			for _, sound in b.show.cues do
				asked[sound.cue] = true
			end
		end
		for _ = 1, 6 do
			b.seat:input("fire", true)
			Kit.run(b, 0.3)
		end
		b.seat:input("fire", true) -- (dry)
		for step = 1, 240 do
			b.pose.x = step * 0.2 -- (walking: footsteps)
			Kit.frame(b)
		end
		gather()
		Kit.message(b, {
			kind = "paintball_tag",
			by = 1,
			id = 2,
			ball = 3,
			scores = { 1, 0 },
			tags = 1,
			outs = 1,
			at = b.now() + 4,
			x = 0,
			y = 3,
			z = 0,
		})
		Kit.message(b, {
			kind = "paintball_tag",
			by = 2,
			id = 1,
			ball = 4,
			scores = { 1, 1 },
			tags = 1,
			outs = 1,
			at = b.now() + 4,
			x = 0,
			y = 3,
			z = 0,
		})
		Kit.place(b)
		gather()
		for cue in asked do
			t.truthy(declared[cue] ~= nil, `{cue} is asked for and must be declared`)
		end
		for _, cue in { "fire", "fire_far", "splat", "tag", "tagged", "reload", "dry", "step", "ready", "back" } do
			t.truthy(asked[`paintball.{cue}`], `{cue} was heard in a played stretch`)
		end
	end)
end
