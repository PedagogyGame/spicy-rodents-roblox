--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.AirHockey.Controller
-- A player's end of the air hockey table, the owner's way (AER / 01): first person from your end of the table,
-- the mouse moves your mallet across your half, move it through the puck to strike, hold it still to block.
--   Mouse: the mallet goes to the point of the bed under the pointer (a ray from the camera to the playing
--     surface), exactly as in his game. WASD / the arrows and a gamepad's left stick push it about instead
--     (his 1.8 m/s); on a touch screen a finger dragged anywhere moves it as far as the finger moves, and a tap
--     serves.
--   V (gamepad X, the VIEW button) swaps first person for the view from above. Space (gamepad A, a click, a
--     tap, SERVE) lets the puck go at once while the countdown runs.
-- NOTHING HERE WAITS FOR THE SERVER TO MOVE YOUR MALLET. The hand goes straight into this player's own copy of
-- the simulation (Shared/Minigames/AirHockey/Seat), which is stepped to the shared clock's tick every frame and
-- drawn between ticks (Client/Minigames/AirHockey/Rink.show); the log of the hand is sent on in segments, never a
-- message a frame; the referee's stream comes back and is checked against what was shown. Against the computer
-- that is the whole of his single-player game on this screen; against a person only the other hand arrives
-- late, and it is never guessed: the far end is drawn a moment ago, as the referee decided it, and this end now
-- (Seat's header).
-- Words on screen are his: READY WHEN YOU ARE, BEAUTIFUL SHOT, EMBER SCORES, MATCH WON, WELL PLAYED.
-- The main client's rules (MinigameClient's header): the two views go through ctx.camera / ctx.releaseCamera;
-- the cursor is MinigameUI's; everything connected here is disconnected in stop().
-- Interface: new(ctx) -> Controller { onState, onMessage, onRefused, stop }; HELP; KEY_SPEED; STICK_SPEED;
--   current (the controller that is open now, for the specs: its .seat is the player's prediction)

local Import = require("../../Import")
local Layout =
	Import.shared("Minigames/AirHockey/Layout") :: typeof(require("../../../shared/Minigames/AirHockey/Layout"))
local Seat = Import.shared("Minigames/AirHockey/Seat") :: typeof(require("../../../shared/Minigames/AirHockey/Seat"))
local Sim = Import.shared("Minigames/AirHockey/Sim") :: typeof(require("../../../shared/Minigames/AirHockey/Sim"))
local InputMap = require("../../Input/InputMap")
local ClientGame = require("../ClientGame")
local Rink = require("./Rink")

local Controller = {}

Controller.HELP = {
	how = {
		"Knock the puck into the far goal. First to seven wins.",
		"Move your mallet through the puck to strike it; hold it still to block. It stays in your half.",
		"After a goal the puck is served from the side that let it in.",
	},
	keys = {
		"Mouse  your mallet follows it",
		"WASD / arrows / left stick  move the mallet",
		"Touch  drag anywhere to move it, tap to serve",
		"Space / click / gamepad A  serve at once",
		"V / gamepad X  first person or from above",
		"Q  leave the table",
	},
}
Controller.KEY_SPEED = 1.8 -- metres a second: the keys' push on the mallet's target (his)
Controller.STICK_SPEED = 2.6 -- and a stick held right over
Controller.current = nil :: any
local TAP_SECONDS = 0.3
local TAP_PIXELS = 14

function Controller.new(ctx: ClientGame.Ctx): ClientGame.Controller
	local UIS = game:GetService("UserInputService")
	local RunService = game:GetService("RunService")
	local place = ctx.place :: any
	local rink = Rink.get(ctx.station, place)
	local self: any = {
		ctx = ctx,
		rink = rink,
		seat = nil, -- Shared/Minigames/AirHockey/Seat while a match is on
		side = 0, -- the end this player has (or asked for)
		overhead = false,
		phase = "",
		aimX = 0, -- where the hand is, model metres
		aimY = -0.8,
		mouse = nil, -- the pointer as it was last frame (the mouse steers only when it moves)
		finger = nil, -- the touch that is dragging the mallet, where it was, how far it has gone, when it began
		fingerAt = nil,
		fingerMoved = 0,
		fingerSince = 0,
		clock = 0, -- seconds of frames since the game opened
		shown = "",
		bar = "",
		notice = nil, -- { text, until } a goal's words
		conns = {},
		stopped = false,
	}
	Rink.take(rink)
	Controller.current = self

	local function setCamera(snap: boolean)
		local view = Layout.camera(self.side, self.overhead)
		local ex, ey, ez = Layout.toWorld(place, view.eye[1], view.eye[2], view.eye[3])
		local tx, ty, tz = Layout.toWorld(place, view.target[1], view.target[2], view.target[3])
		ctx.camera(CFrame.lookAt(Vector3.new(ex, ey, ez), Vector3.new(tx, ty, tz)), view.fov, snap)
	end

	local function status(text: string)
		if text ~= self.shown then
			self.shown = text
			ctx.ui:status(text)
		end
	end

	local function toggleView()
		self.overhead = not self.overhead
		setCamera(false)
	end

	local function serve()
		if self.seat then
			Seat.serve(self.seat)
		end
	end

	-- the bar while a match is on is this controller's own (a view button is not a verb for the server)
	local function playBar()
		if self.bar == "play" then
			return
		end
		self.bar = "play"
		ctx.ui:buttons({ { "view", "View (V)" }, { "leave", "Leave (Q)" } }, function(id: string)
			if id == "view" then
				toggleView()
			else
				ctx.send(id)
			end
		end)
		ctx.ui:touch({ { "serve", "SERVE", "wide" }, { "view", "VIEW" } }, function(id: string)
			if id == "view" then
				toggleView()
			else
				serve()
			end
		end, function(_id: string) end)
	end

	-- the point of the bed under a point of the screen (model metres), or nil if the ray misses the table's plane
	local function bedUnder(x: number, y: number): (number?, number?)
		local cam = workspace.CurrentCamera
		local ray = cam:ViewportPointToRay(x, y)
		local bed = place.floorY + Layout.BED_Y
		if ray.Direction.Y > -1e-4 then
			return nil, nil
		end
		local t = (bed - ray.Origin.Y) / ray.Direction.Y
		local hit = ray.Origin + ray.Direction * t
		return Layout.fromWorld(place, hit.X, hit.Z)
	end

	local function setAim(x: number, y: number)
		-- (kept to where this end's mallet can be, as his setTarget keeps it: a push from the keys starts from
		-- there, never from a pointer that is off the table or over the far half)
		local reachX = Sim.HALF_WIDTH - Sim.PADDLE_RADIUS
		local near, far = Sim.PADDLE_RADIUS, Sim.HALF_LENGTH - Sim.PADDLE_RADIUS
		self.aimX = math.clamp(x, -reachX, reachX)
		if self.side == 0 then
			self.aimY = math.clamp(y, -far, -near)
		else
			self.aimY = math.clamp(y, near, far)
		end
	end

	local Key = Enum.KeyCode
	table.insert(
		self.conns,
		UIS.InputBegan:Connect(function(io: InputObject, processed: boolean)
			-- chat and the Roblox menu own the keys while they are up; a click or a touch on a button is the button's
			if InputMap.ignore(io, processed) then
				return
			end
			if io.UserInputType == Enum.UserInputType.Touch then
				if self.finger == nil then
					self.finger = io
					self.fingerAt = io.Position
					self.fingerMoved = 0
					self.fingerSince = self.clock
				end
			elseif io.KeyCode == Key.V or io.KeyCode == Key.ButtonX then
				toggleView()
			elseif io.KeyCode == Key.Space or io.KeyCode == Key.ButtonA then
				if self.phase == "lobby" then
					ctx.send("start")
				else
					serve()
				end
			elseif io.UserInputType == Enum.UserInputType.MouseButton1 then
				serve()
			end
		end)
	)
	table.insert(
		self.conns,
		UIS.InputChanged:Connect(function(io: InputObject)
			local was = self.fingerAt
			if io == self.finger and was ~= nil then
				-- the mallet moves as far across the screen as the finger did, from where the mallet is
				local now = io.Position
				local dx, dy = now.X - was.X, now.Y - was.Y
				self.fingerAt = now
				self.fingerMoved += math.abs(dx) + math.abs(dy)
				local wx, wy, wz = Layout.toWorld(place, self.aimX, self.aimY)
				local at = workspace.CurrentCamera:WorldToViewportPoint(Vector3.new(wx, wy, wz))
				local x, y = bedUnder(at.X + dx, at.Y + dy)
				if x and y then
					setAim(x, y)
				end
			end
		end)
	)
	table.insert(
		self.conns,
		UIS.InputEnded:Connect(function(io: InputObject)
			if io == self.finger then
				if self.fingerMoved < TAP_PIXELS and self.clock - self.fingerSince < TAP_SECONDS then
					serve()
				end
				self.finger = nil
				self.fingerAt = nil
			end
		end)
	)

	local function words(sim: any, mode: string): string
		local a, b = sim.score0, sim.score1
		local mine, theirs = if self.side == 0 then a else b, if self.side == 0 then b else a
		local score = `You {mine} : {theirs}`
		local notice = self.notice
		if notice and self.clock < notice.until_ then
			return `{notice.text}   {score}`
		end
		if sim.winner >= 0 then
			return if sim.winner == self.side then `MATCH WON.   {score}` else `WELL PLAYED.   {score}`
		end
		if sim.countdown > 0 and sim.countdown ~= math.huge then
			return `READY WHEN YOU ARE.  Space or tap to serve   {score}`
		end
		if mode == "2" then
			return `{score}   first to {Sim.WIN}`
		end
		return `{score}   first to {Sim.WIN}   (the computer has the {Layout.SIDE_NAMES[1 - self.side]} end)`
	end

	local function goalWords(sim: any)
		local text = if sim.lastGoal == self.side
			then "BEAUTIFUL SHOT."
			else `{string.upper(Layout.SIDE_NAMES[sim.lastGoal] or "")} SCORES.`
		self.notice = { text = text, until_ = self.clock + 1.1 }
		ctx.ui:banner(text, true)
	end

	table.insert(
		self.conns,
		RunService.RenderStepped:Connect(function(dt: number)
			self.clock += dt
			local seat = self.seat
			if seat == nil then
				return
			end
			-- the hand
			if UIS.MouseEnabled and self.finger == nil then
				local mp = UIS:GetMouseLocation()
				local was = self.mouse
				if was == nil or mp.X ~= was.X or mp.Y ~= was.Y then
					self.mouse = mp
					local x, y = bedUnder(mp.X, mp.Y)
					if x and y then
						setAim(x, y)
					end
				end
			end
			local sx = (if UIS:IsKeyDown(Key.D) or UIS:IsKeyDown(Key.Right) then 1 else 0)
				- (if UIS:IsKeyDown(Key.A) or UIS:IsKeyDown(Key.Left) then 1 else 0)
			local sy = (if UIS:IsKeyDown(Key.W) or UIS:IsKeyDown(Key.Up) then 1 else 0)
				- (if UIS:IsKeyDown(Key.S) or UIS:IsKeyDown(Key.Down) then 1 else 0)
			local speed = Controller.KEY_SPEED
			if sx == 0 and sy == 0 then
				for _, state in UIS:GetGamepadState(Enum.UserInputType.Gamepad1) do
					if state.KeyCode == Key.Thumbstick1 and state.Position.Magnitude > 0.15 then
						sx, sy, speed = state.Position.X, state.Position.Y, Controller.STICK_SPEED
					end
				end
			end
			if sx ~= 0 or sy ~= 0 then
				-- (your right and your far end: the Ember end looks the other way down the table)
				local s = if self.side == 0 then 1 else -1
				local step = math.min(dt, 0.1) * speed
				-- (from where the mallet is being sent, as his keys do)
				setAim(self.aimX + sx * s * step, self.aimY + sy * s * step)
			end
			Seat.aim(seat, self.aimX, self.aimY)
			-- the match on this screen, to the clock's tick
			local r = seat.replica
			if r.game ~= nil then
				local now = (ctx.stamp() - r.t0) / Sim.STEP
				Seat.relax(seat, dt)
				local duo = seat.mode == "2"
				Seat.step(seat, now, function(from: number, to: number, strings: { string })
					local args: { any } = { from, to }
					for _, text in strings do
						table.insert(args, text)
					end
					ctx.send("log", args)
				end, function(sim: any, _tick: number, _hit: boolean, goal: boolean)
					-- against the computer a goal is said the tick this screen plays it (it is the referee's,
					-- tick for tick)
					if goal and not duo then
						Rink.cue(sim, false, true, false, self.side)
						goalWords(sim)
					end
				end, function(sim: any, _tick: number, _hit: boolean, goal: boolean)
					-- against a person a goal is said when the referee has said it
					if goal and duo then
						Rink.cue(sim, false, true, false, self.side)
						goalWords(sim)
					end
				end)
			end
			if seat.ready then
				-- a contact is heard when the puck drawn meets it (this end's at once, the far end's when seen)
				Seat.heard(seat, Rink.contact)
				Rink.show(rink, Seat.view(seat))
				status(words(if seat.mode == "2" then seat.replica.sim else seat.pred, seat.mode))
			end
		end)
	)

	function self.onState(_self: any, msg: { [string]: any })
		local view = msg.view
		local was = self.phase
		self.phase = view.phase
		if type(msg.side) == "number" and self.seat == nil and msg.side ~= self.side then
			self.side = msg.side
			setAim(0, if self.side == 0 then -0.8 else 0.8)
			setCamera(true)
		end
		if view.phase == "lobby" then
			self.bar = ""
			if was ~= "lobby" then
				-- a new match is coming: the last one's seat is done with
				self.seat = nil
			end
			local who = if #view.seats >= 2
				then "Both ends are taken"
				else "Someone can take the other end; otherwise the computer plays it"
			status(`Starting in {view.lobbyLeft or 0} s (Space starts now). {who}.`)
		elseif view.phase == "playing" then
			playBar()
		elseif view.phase == "done" then
			self.bar = ""
		end
	end

	function self.onMessage(_self: any, msg: { [string]: any }, _watched: any?)
		if msg.kind == "air_hockey_seat" and type(msg.side) == "number" and type(msg.g) == "number" then
			-- the referee's word: this end is yours from tick `from`
			local side = if msg.side == 1 then 1 else 0
			if side ~= self.side or self.seat == nil then
				self.side = side
				setCamera(self.seat == nil)
			end
			local seat = Seat.new(side)
			Seat.begin(seat, msg.g, tonumber(msg.from) or 0)
			self.seat = seat
			self.notice = nil
			setAim(0, if side == 0 then -0.8 else 0.8)
			self.mouse = nil
			ctx.sound("air_hockey.serve", 0.5)
		elseif msg.kind == "air_hockey" and self.seat then
			Seat.push(self.seat, msg)
		elseif msg.kind == "event" and msg.over then
			local seat = self.seat
			local won = seat ~= nil and seat.replica.sim.winner == self.side
			ctx.sound(if won then "air_hockey.win" else "air_hockey.lose", 0.9)
		end
	end

	function self.onRefused(_self: any, _msg: { [string]: any })
		-- (the words are on screen already; the log simply carries on from the next segment)
	end

	function self.stop(_self: any)
		if self.stopped then
			return
		end
		self.stopped = true
		if Controller.current == self then
			Controller.current = nil
		end
		for _, c in self.conns do
			c:Disconnect()
		end
		table.clear(self.conns)
		self.seat = nil
		Rink.give(rink)
		-- (the pieces are left where this screen last drew them only for a moment: the stream, if the match
		-- goes on without this player, or the server's word that the table is at rest, moves them next)
		ctx.ui:touch({}, function() end, function() end)
		ctx.controls(true)
		ctx.releaseCamera()
	end

	-- at the table: your end's view, and the keys are the table's
	ctx.controls(false)
	setCamera(true)
	return self
end

return Controller
