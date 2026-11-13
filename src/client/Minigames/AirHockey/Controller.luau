--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.AirHockey.Controller
-- A player's end of the air hockey table, the owner's way (AER / 01): first person from your end of the table,
-- the mouse moves your mallet across your half, move it through the puck to strike, hold it still to block.
--   Mouse: the mallet goes to the point of the bed under the pointer (a ray from the camera to the playing
--     surface), exactly as in his game. WASD / the arrows push it about instead (his 1.8 m/s; Shift held: as
--     fast as the mallet goes), a gamepad's left stick pushes it at up to the mallet's own top speed (fine near
--     the middle of the stick), and on a touch screen a finger dragged anywhere moves it as far as the finger
--     moves, and a tap serves.
--   V (gamepad X, the View button) swaps first person for the view from above. Space (gamepad A, a click, a
--     tap) lets the puck go while the countdown runs: at once against the computer, a moment later against a
--     person (Sim.press). H (gamepad Y, the HELP button on a touch screen) hides and shows the help card.
--   You stand on the mat at your end, facing down the table, for as long as you play.
-- NOTHING HERE WAITS FOR THE SERVER TO MOVE YOUR MALLET. The hand goes straight into this player's own copy of
-- the simulation (Shared/Minigames/AirHockey/Seat), which is stepped to the shared clock's tick every frame and
-- drawn between ticks (Client/Minigames/AirHockey/Rink.show); the log of the hand is sent on in segments, never a
-- message a frame; the referee's stream comes back and is checked against what was shown. Against the computer
-- that is the whole of his single-player game on this screen; against a person only the other hand arrives
-- late, and it is never guessed: the far end is drawn a moment ago, as the referee decided it, and this end now
-- (Seat's header).
-- Words on screen are his: READY WHEN YOU ARE, BEAUTIFUL SHOT, EMBER SCORES, MATCH WON, WELL PLAYED. A goal is
-- said once, on the banner; the status line keeps the score. One word is ours: PINCHED. His simulation lets a
-- puck that a mallet presses into a rail out through the rail; the table holds it in (Sim.contain: it is put back
-- on the rail, slid clear of the mallet and leaves as it would off that mallet, and the rally goes on). That
-- pop out from under the mallet is said, as the rail's sound is heard, the moment it happens on this player's
-- match (against a person, when the referee has said it), and not again for PINCH_AGAIN seconds.
-- SMALL SCREENS AND TOUCH: the whole bed has to stay in sight, so when a match starts on a touch device or a
-- short screen the help card is put away (HELP brings it back), the status line is only up while the puck
-- waits, and the scorecard is a strip in the top corner (Client/Minigames/Games/AirHockey.card). On a short
-- screen (a phone) the game opens in the view from above, where the bed stands clear of every button; View
-- still swaps to first person. The banner (a goal's words, PINCHED) is said in the top left corner there, beside
-- the bed (MinigameUI's banner is across the top middle, which from above is the far end of the bed); it is put
-- back where it was when the game closes.
-- NOTHING IS ASKED TWICE: Space in the lobby starts once, Play again and Leave are sent once, Q is this
-- controller's (it leaves, once): a second press while the first is on its way is swallowed, not refused.
-- The main client's rules (MinigameClient's header): the two views go through ctx.camera / ctx.releaseCamera;
-- the cursor is MinigameUI's; everything connected here is disconnected in stop().
-- Interface: new(ctx) -> Controller { onState, onMessage, onRefused, stop }; HELP; KEY_SPEED; STICK_SPEED;
--   STICK_DEAD; stick(x, y) -> (vx, vy) (a stick's position as the push it gives, metres a second); small() ->
--   bool (a touch device or a short screen); short() -> bool; SMALL_HEIGHT; MODE_WORDS; PINCHED; PINCH_AGAIN;
--   SMALL_BANNER; current (the controller that is open now, for the specs: its .seat is the player's prediction;
--   its .say(text, big) is the banner as this game says it)

local Import = require("../../Import")
local Layout =
	Import.shared("Minigames/AirHockey/Layout") :: typeof(require("../../../shared/Minigames/AirHockey/Layout"))
local Rules = Import.shared("Minigames/AirHockey/Rules") :: typeof(require("../../../shared/Minigames/AirHockey/Rules"))
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
		"WASD / arrows  move the mallet (Shift: faster)",
		"Left stick  move the mallet",
		"Touch  drag anywhere to move it, tap to serve",
		"Space / click / gamepad A  serve",
		"V / gamepad X  first person or from above",
		"H / gamepad Y  this card",
		"Q / gamepad B  leave the table",
	},
}
Controller.KEY_SPEED = 1.8 -- metres a second: the keys' push on the mallet's target (his)
Controller.STICK_SPEED = Sim.HUMAN_SPEED -- a stick held right over: as fast as a mallet follows its target
Controller.STICK_DEAD = 0.15
Controller.SMALL_HEIGHT = 600 -- pixels: a screen shorter than this is a small one
Controller.MODE_WORDS = { easy = "Lounge (easy)", medium = "Club (medium)", hard = "Pro (hard)" }
Controller.PINCHED = "PINCHED. PLAY ON." -- the rails held a puck a mallet pressed into them (see the header)
Controller.PINCH_AGAIN = 3 -- seconds before it is said again
-- a small screen's banner, in the top left corner beside the bed seen from above: pixels from the left and the
-- top, and how much narrower than half the screen it is (the bed's half-width from above on a phone is under 90)
Controller.SMALL_BANNER = { left = 12, top = 50, short = 110 }
Controller.current = nil :: any
local TAP_SECONDS = 0.3
local TAP_PIXELS = 14

-- A stick's position as the push it gives the mallet's target, metres a second: nothing inside the dead zone,
-- the mallet's own top speed right over, and slow near the middle (the square of how far it is pushed) so that
-- a block can be placed finely.
function Controller.stick(x: number, y: number): (number, number)
	local m = math.sqrt(x * x + y * y)
	if m <= Controller.STICK_DEAD then
		return 0, 0
	end
	local u = math.min((m - Controller.STICK_DEAD) / (1 - Controller.STICK_DEAD), 1)
	local speed = Controller.STICK_SPEED * u * u
	return x / m * speed, y / m * speed
end

-- A screen too short for first person: from your end the bed fills the bottom of a phone's screen from corner
-- to corner, under the buttons. From above it stands in the middle with room on both sides.
function Controller.short(): boolean
	local cam = workspace.CurrentCamera
	return cam ~= nil and cam.ViewportSize.Y < Controller.SMALL_HEIGHT
end

-- A touch device, or a short screen: the HUD is kept off the bed (see the header).
function Controller.small(): boolean
	return game:GetService("UserInputService").TouchEnabled or Controller.short()
end

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
		overhead = Controller.short(), -- (a phone starts from above: see short())
		phase = "",
		aimX = 0, -- where the hand is, model metres
		aimY = -0.8,
		mouse = nil, -- the pointer as it was last frame (the mouse steers only when it moves...)
		byMouse = true, -- ...and whether it was the last thing to steer (then a change of view re-aims from it)
		camWas = nil, -- the camera as it was last frame
		finger = nil, -- the touch that is dragging the mallet, where it was, how far it has gone, when it began
		fingerAt = nil,
		fingerMoved = 0,
		fingerSince = 0,
		clock = 0, -- seconds of frames since the game opened
		shown = "",
		bar = "",
		stood = nil, -- the end this player's body has been stood at
		asked = {}, -- verb -> true while a start, an again or a leave is on its way
		ended = nil, -- the match whose end has been sounded
		servedAt = nil, -- the tick of a serve this screen sounded before the referee said it
		waiting = true, -- the puck was waiting for its serve at the last tick played here, and which tick
		tickWas = -1,
		said = 0, -- goals of this match said so far (Sim.goalSerial)
		pinches = setmetatable({}, { __mode = "k" }), -- each simulation's Sim.heldSerial when it was last looked at
		pinchedAt = -math.huge, -- when PINCHED was last said
		conns = {},
		hidHelp = false, -- this controller put the help card away (a small screen): it brings it back
		stopped = false,
	}
	Rink.take(rink)
	Controller.current = self
	local bannerAt = ctx.ui.bannerLabel and ctx.ui.bannerLabel.Position -- (put back in stop())

	-- A banner, as this game says it: on a small screen in the top left corner, clear of the bed.
	local function say(text: string, big: boolean)
		ctx.ui:banner(text, big)
		local label = ctx.ui.bannerLabel
		if label ~= nil and Controller.small() then
			local b = Controller.SMALL_BANNER
			label.Position = UDim2.fromOffset(b.left, b.top)
			label.Size = UDim2.new(0.5, -b.short, 0, if big then 48 else 34)
		elseif label ~= nil and bannerAt ~= nil then
			label.Position = bannerAt
		end
	end
	self.say = say

	local function setCamera(snap: boolean)
		local view = Layout.camera(self.side, self.overhead)
		local ex, ey, ez = Layout.toWorld(place, view.eye[1], view.eye[2], view.eye[3])
		local tx, ty, tz = Layout.toWorld(place, view.target[1], view.target[2], view.target[3])
		ctx.camera(CFrame.lookAt(Vector3.new(ex, ey, ez), Vector3.new(tx, ty, tz)), view.fov, snap)
	end

	-- This player's body on the mat at their end, facing down the table (once for each end taken: the legs are
	-- the table's while the game is open, so it stays there; everyone else sees someone standing at that end).
	local function stand()
		if self.stood == self.side then
			return
		end
		local body = ctx.body()
		local root = body and body.PrimaryPart
		if root == nil then
			return
		end
		self.stood = self.side
		local mx, my = Layout.fromLocal(Layout.stance(self.side))
		local wx, _, wz = Layout.toWorld(place, mx, my)
		local cx, _, cz = Layout.toWorld(place, 0, 0)
		local at = Vector3.new(wx, root.Position.Y, wz)
		root.CFrame = CFrame.lookAt(at, Vector3.new(cx, root.Position.Y, cz))
		root.AssemblyLinearVelocity = Vector3.zero
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

	-- A start, an again or a leave: sent once. A second press before the answer is swallowed (it would come
	-- back refused: "already playing").
	local function ask(verb: string)
		if self.asked[verb] then
			return
		end
		self.asked[verb] = true
		ctx.send(verb)
	end

	local function helpShown(): boolean
		local frame = ctx.ui.helpFrame
		return frame ~= nil and frame.Visible == true
	end

	local function toggleHelp()
		ctx.ui:toggleHelp()
	end

	-- The bar is this controller's in every phase (a view button is not a verb for the server, and a button
	-- pressed twice must not be sent twice).
	local function setBar(name: string, list: { { string } })
		if self.bar == name then
			return
		end
		self.bar = name
		ctx.ui:buttons(list, function(id: string)
			if id == "view" then
				toggleView()
			elseif id == "help" then
				toggleHelp()
			elseif Controller.MODE_WORDS[id] then
				ctx.send("mode", { id })
			else
				ask(id)
			end
		end)
	end

	local function lobbyBar(mode: string)
		local list: { { string } } = { { "start", "Start (Space)" } }
		for _, m in Rules.MODES do
			table.insert(list, { m, (if m == mode then "> " else "") .. Controller.MODE_WORDS[m] })
		end
		table.insert(list, { "leave", "Leave (Q)" })
		setBar("lobby:" .. mode, list)
		ctx.ui:touch({}, function() end, function() end)
	end

	local function playBar()
		local touch = UIS.TouchEnabled
		if touch then
			-- (two short buttons: on a phone the near corner of the bed is just beside them)
			setBar("play:touch", { { "view", "View" }, { "leave", "Leave" } })
			ctx.ui:touch({ { "help", "HELP" } }, function(_id: string)
				toggleHelp()
			end, function(_id: string) end)
		else
			setBar("play", { { "view", "View (V)" }, { "leave", "Leave (Q)" } })
		end
	end

	local function doneBar()
		setBar("done", { { "again", "Play again" }, { "leave", "Leave (Q)" } })
		ctx.ui:touch({}, function() end, function() end)
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
					self.byMouse = false
				end
			elseif io.KeyCode == Key.V or io.KeyCode == Key.ButtonX then
				toggleView()
			elseif io.KeyCode == Key.ButtonY then
				toggleHelp()
			elseif io.KeyCode == Key.Q or io.KeyCode == Key.ButtonB then
				ask("leave")
			elseif io.KeyCode == Key.Space or io.KeyCode == Key.ButtonA then
				if self.phase == "lobby" then
					ask("start")
				elseif self.phase == "playing" then
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

	-- The status line: the score, and READY while the puck waits. (A goal's words are the banner's, once.) On a
	-- small screen the line lies over the far goal, so it is only up while the puck waits.
	local function words(sim: any, mode: string): string
		local a, b = sim.score0, sim.score1
		local mine, theirs = if self.side == 0 then a else b, if self.side == 0 then b else a
		local score = `You {mine} : {theirs}`
		local small = Controller.small()
		if sim.winner >= 0 then
			return if sim.winner == self.side then `MATCH WON.   {score}` else `WELL PLAYED.   {score}`
		end
		if sim.countdown > 0 and sim.countdown ~= math.huge then
			if UIS.TouchEnabled then
				return `READY WHEN YOU ARE.  Tap to serve   {score}`
			end
			return `READY WHEN YOU ARE.  Space serves   {score}`
		end
		if small then
			return ""
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
		say(text, true)
	end

	-- A goal is said once, whichever way this screen first hears of it (said: the goals said so far).
	local function goal(sim: any)
		if sim.goalSerial > self.said then
			self.said = sim.goalSerial
			Rink.cue(sim, false, true, false, self.side)
			goalWords(sim)
		end
	end

	-- The rails held the puck (Sim.contain): said in a word, once in a while (the rail's sound is the contact's).
	local function pinch(sim: any)
		local was = self.pinches[sim]
		self.pinches[sim] = sim.heldSerial
		if was ~= nil and sim.heldSerial > was then
			if self.clock - self.pinchedAt >= Controller.PINCH_AGAIN then
				self.pinchedAt = self.clock
				say(Controller.PINCHED, false)
			end
		end
	end

	-- One tick as this screen plays it (the prediction): against the computer it is the referee's tick, so a
	-- goal is said here; a serve is sounded here whoever the other end is (this player's own press, or the
	-- countdown running out, is known at once).
	local function onTick(sim: any, tick: number, _hit: boolean, scored: boolean, served: boolean)
		local duo = self.seat ~= nil and self.seat.mode == "2"
		if scored and not duo then
			goal(sim)
		end
		if not duo then
			pinch(sim)
		end
		if served then
			self.servedAt = if duo then tick else nil
			Rink.cue(sim, false, false, true, self.side)
		end
		local waiting = sim.countdown > 0
		if
			waiting
			and not self.waiting
			and tick == self.tickWas + 1
			and not scored
			and not duo
			and sim.winner < 0
			and sim.countdown ~= math.huge
		then
			-- (the net under the rails: a puck that left the table all the same was put back)
			say("PUCK OFF THE TABLE. SERVED AGAIN.", false)
		end
		self.waiting, self.tickWas = waiting, tick
	end

	-- One tick as the referee decided it: against a person a goal is said when the referee has said it, and a
	-- serve this screen did not sound itself (the other player's press that it heard of late) is sounded now.
	-- (Against the computer a goal the referee decides has been said already, unless this screen never played
	-- its tick: the stream jumped over it.)
	local function onConfirmed(sim: any, tick: number, _hit: boolean, scored: boolean, served: boolean)
		if scored then
			goal(sim)
		end
		local duo = self.seat ~= nil and self.seat.mode == "2"
		if duo then
			pinch(sim)
		end
		if served and duo then
			local mine = self.servedAt
			if mine ~= nil and math.abs(mine - tick) <= Sim.COUNTDOWN / Sim.STEP then
				self.servedAt = nil -- (heard already, when this screen played it)
			else
				Rink.cue(sim, false, false, true, self.side)
			end
		end
	end

	local function send(from: number, to: number, strings: { string })
		local args: { any } = { from, to }
		for _, text in strings do
			table.insert(args, text)
		end
		ctx.send("log", args)
	end

	table.insert(
		self.conns,
		RunService.RenderStepped:Connect(function(dt: number)
			self.clock += dt
			local seat = self.seat
			if seat == nil then
				return
			end
			-- the hand. The mouse steers when it moves; and while the view is changing under a still pointer (V),
			-- if the mouse was the last thing to steer, the mallet goes on to the point now under it.
			local cam = workspace.CurrentCamera
			local camNow = cam and cam.CFrame
			local glided = self.camWas ~= nil and camNow ~= self.camWas
			self.camWas = camNow
			if UIS.MouseEnabled and self.finger == nil then
				local mp = UIS:GetMouseLocation()
				local was = self.mouse
				local moved = was == nil or mp.X ~= was.X or mp.Y ~= was.Y
				if moved then
					self.byMouse = true
				end
				if moved or (glided and self.byMouse) then
					self.mouse = mp
					local x, y = bedUnder(mp.X, mp.Y)
					if x and y then
						setAim(x, y)
					end
				end
			end
			-- the keys and the stick push the hand about (never while the player is typing: W, A, S and D are
			-- letters then)
			local vx, vy = 0, 0
			if not InputMap.typing() then
				local sx = (if UIS:IsKeyDown(Key.D) or UIS:IsKeyDown(Key.Right) then 1 else 0)
					- (if UIS:IsKeyDown(Key.A) or UIS:IsKeyDown(Key.Left) then 1 else 0)
				local sy = (if UIS:IsKeyDown(Key.W) or UIS:IsKeyDown(Key.Up) then 1 else 0)
					- (if UIS:IsKeyDown(Key.S) or UIS:IsKeyDown(Key.Down) then 1 else 0)
				if sx ~= 0 or sy ~= 0 then
					local fast = UIS:IsKeyDown(Key.LeftShift) or UIS:IsKeyDown(Key.RightShift)
					local speed = if fast then Sim.HUMAN_SPEED else Controller.KEY_SPEED
					local n = math.sqrt(sx * sx + sy * sy)
					vx, vy = sx / n * speed, sy / n * speed
				else
					for _, state in UIS:GetGamepadState(Enum.UserInputType.Gamepad1) do
						if state.KeyCode == Key.Thumbstick1 then
							vx, vy = Controller.stick(state.Position.X, state.Position.Y)
						end
					end
				end
			end
			if vx ~= 0 or vy ~= 0 then
				-- (your right and your far end: the Ember end looks the other way down the table)
				local s = if self.side == 0 then 1 else -1
				local step = math.min(dt, 0.1)
				self.byMouse = false
				-- (from where the mallet is being sent, as his keys do)
				setAim(self.aimX + vx * s * step, self.aimY + vy * s * step)
			end
			Seat.aim(seat, self.aimX, self.aimY)
			-- the match on this screen, to the clock's tick
			local r = seat.replica
			if r.game ~= nil then
				local now = (ctx.stamp() - r.t0) / Sim.STEP
				Seat.relax(seat, dt)
				Seat.step(seat, now, send, onTick, onConfirmed)
			end
			if seat.ready then
				-- a contact is heard when the puck drawn meets it (this end's at once, the far end's when seen)
				Seat.heard(seat, Rink.contact)
				Rink.playing(rink, seat.mode, self.side)
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
		stand()
		if was ~= view.phase then
			-- (whatever was asked for has been answered by the table changing)
			table.clear(self.asked)
		end
		if view.phase == "lobby" then
			if was ~= "lobby" then
				-- a new match is coming: the last one's seat is done with, and the card is back to be read
				self.seat = nil
				self.ended = nil
				if self.hidHelp and not helpShown() then
					toggleHelp()
				end
				self.hidHelp = false
			end
			lobbyBar(view.mode or (view.game and view.game.mode) or "medium")
			local who = if #view.seats >= 2
				then "Both ends are taken"
				else "Someone can take the other end; otherwise the computer plays it"
			status(`Starting in {view.lobbyLeft or 0} s (Space starts now). {who}.`)
		elseif view.phase == "playing" then
			playBar()
		elseif view.phase == "done" then
			doneBar()
			-- the match is over, and who won is the table's word (the view's result), never this screen's guess
			local result = view.result
			if was ~= "done" and result ~= nil and self.ended ~= true then
				self.ended = true
				ctx.sound(if result.winner == msg.you then "air_hockey.win" else "air_hockey.lose", 0.9)
			end
		end
	end

	function self.onMessage(_self: any, msg: { [string]: any }, _watched: any?)
		if msg.kind == "air_hockey_seat" and type(msg.side) == "number" and type(msg.g) == "number" then
			local side = if msg.side == 1 then 1 else 0
			local from = tonumber(msg.from) or 0
			local held = self.seat
			if msg.again == true then
				-- the referee's word that a part of this hand's log never came: it is sent again from `from`
				if held ~= nil and held.game == msg.g and held.side == side then
					Seat.resume(held, from)
				end
				return
			end
			-- the referee's word: this end is yours from tick `from`
			if side ~= self.side or held == nil then
				self.side = side
				setCamera(held == nil)
			end
			stand()
			local seat = Seat.new(side)
			Seat.begin(seat, msg.g, from)
			self.seat = seat
			self.servedAt = nil
			self.waiting, self.tickWas = true, -1
			self.said = 0
			self.ended = nil
			setAim(0, if side == 0 then -0.8 else 0.8)
			self.mouse = nil
			if Controller.small() and helpShown() then
				-- (the card lies over a quarter of this player's half on a phone: HELP brings it back)
				toggleHelp()
				self.hidHelp = true
			end
		elseif msg.kind == "air_hockey" and self.seat then
			Seat.push(self.seat, msg)
		elseif msg.kind == "air_hockey_press" and self.seat and type(msg.tick) == "number" then
			-- the other player pressed their serve button: the puck leaves a moment after that tick
			if msg.g == self.seat.game and msg.side ~= self.seat.side then
				Seat.pressed(self.seat, msg.tick)
			end
		end
	end

	function self.onRefused(_self: any, _msg: { [string]: any })
		-- (the words are on screen already. Whatever was asked for may be asked again; a log is never refused
		-- with words: the table asks for it again instead, see "air_hockey_seat")
		table.clear(self.asked)
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
		if bannerAt ~= nil and ctx.ui.bannerLabel ~= nil then
			ctx.ui.bannerLabel.Position = bannerAt
		end
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
