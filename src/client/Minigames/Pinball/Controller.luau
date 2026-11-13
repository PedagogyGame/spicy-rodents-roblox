--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.Pinball.Controller
-- A player at a pinball machine. NOTHING HERE WAITS FOR THE SERVER TO MOVE A FLIPPER: while it is this player's
-- ball, this screen's own copy of the game (the Replay the cabinet keeps, Client/Minigames/Pinball/Cabinet) is
-- stepped live (Replay.live) at 240 ticks a second against this screen's clock, the hands (Pinball/Hands) giving
-- the buttons for every tick, and drawn as it stands each frame; the log it records is sent to the server about
-- ten times a second as the verb "log" { fromTick, toTick, packed changes, Replay.sum } (at most one message
-- every SEND_EVERY seconds: segments that pile up in a long frame are joined into one, never across the end of
-- a ball). The server replays it and is the score of record; if it says this copy drifted (or played by itself)
-- it sends a snapshot and the ball carries on from the server's game.
-- WHEN A PRESS LANDS. The engine hands a client its input events once a frame, before the frame's render step,
-- and gives them no time of their own: a press is put on the first 240 Hz tick that has not been played yet
-- (the tick just after the frame the player last saw), a release likewise, and a press that went down and up
-- between two frames still holds the button for one tick. So a press is placed to within one frame: 4 ticks at
-- 60 frames a second, 8 at 30, never later than the frame it arrived in (no added delay).
-- Between this player's balls (another player is up) the camera and the legs are given back and the cabinet
-- follows the other player's ball half a second behind; when the copy reaches this player's ball the controller
-- takes over again on its own. An animal that lands on the cabinet is a thump the server grants
-- ("pinball_thump"): it is let into the log on the next tick.
-- The camera: the player's eye over the lockdown bar looking down the playfield (Shared/Minigames/Pinball/
-- Cabinet.camera: the whole field, both flippers and the plunger in view on any screen shape). The body stands
-- at the cabinet's front facing it. Shift lock is switched off while the game is open (Left Shift is a flipper).
-- The main client's rules (MinigameClient's header): the camera through ctx.camera / ctx.releaseCamera, the cursor
-- MinigameUI's, everything connected here disconnected in stop().
-- Interface: new(ctx) -> Controller; HELP; SEND_EVERY; STRIP (the touch plunger strip, fractions of the screen);
--   current (the controller open now, for the specs: .cab, .live, .hands, .seat, .sent)

local Import = require("../../Import")
local CabinetLayout =
	Import.shared("Minigames/Pinball/Cabinet") :: typeof(require("../../../shared/Minigames/Pinball/Cabinet"))
local InputLog =
	Import.shared("Minigames/Pinball/InputLog") :: typeof(require("../../../shared/Minigames/Pinball/InputLog"))
local Machine =
	Import.shared("Minigames/Pinball/Machine") :: typeof(require("../../../shared/Minigames/Pinball/Machine"))
local Physics =
	Import.shared("Minigames/Pinball/Physics") :: typeof(require("../../../shared/Minigames/Pinball/Physics"))
local Replay = Import.shared("Minigames/Pinball/Replay") :: typeof(require("../../../shared/Minigames/Pinball/Replay"))
local Stream = Import.shared("Minigames/Pinball/Stream") :: typeof(require("../../../shared/Minigames/Pinball/Stream"))
local AlleyLayout =
	Import.shared("Attractions/AlleyLayout") :: typeof(require("../../../shared/Attractions/AlleyLayout"))
local InputMap = require("../../Input/InputMap")
local ClientGame = require("../ClientGame")
local Cabinet = require("./Cabinet")
local Hands = require("./Hands")

local Controller = {}

Controller.HELP = {
	how = {
		"Keep the ball in play with the flippers and hit everything that lights up. Three balls a game.",
		"Hold a flipper up to trap the ball, let go and flip again to aim. Nudge to save a ball, but nudge too hard and it TILTS.",
	},
	keys = {
		"Left flipper  Left Shift, A, Left arrow, left mouse button",
		"Right flipper  Right Shift, D, Right arrow, right mouse button",
		"Plunger  hold Space (S, Down) to pull, let go to launch",
		"Nudge  Z from the left, X from the right, W / Up forward",
		"Gamepad  L1/L2, R1/R2 flippers; A or right stick down: plunger; flick the left stick: nudge",
		"Touch  left half and right half of the screen: flippers; drag down the strip at the bottom right: plunger",
		"H  this card     Q / gamepad B  leave",
	},
}
Controller.SEND_EVERY = 0.09 -- seconds: at most this often a segment of the log goes out
Controller.CHASE_LIMIT = 10 -- seconds: a frame hitch up to this long is caught up (the ball played on), longer is not
Controller.HIST_TICKS = 4800 -- ticks of this player's own hands kept to play again from a snapshot (20 s)

Controller.STRIP = { x0 = 0.84, y0 = 0.5, drag = 0.3 } -- the touch plunger: right of x0, below y0; a full pull is drag of the screen's height
Controller.current = nil :: any

local BTN = Machine.BTN
local PLAY, OVER = Machine.PHASE.PLAY, Machine.PHASE.OVER

-- two segments as one (the second straight after the first, the first not ending a ball)
local function join(a: { number }, b: { number }): { number }
	local out = table.clone(a)
	local shift = a[2] - a[1]
	out[2] = b[2]
	for i = 3, #b, 2 do
		table.insert(out, b[i] + shift)
		table.insert(out, b[i + 1])
	end
	return out
end

function Controller.new(ctx: ClientGame.Ctx): ClientGame.Controller
	local UIS = game:GetService("UserInputService")
	local RunService = game:GetService("RunService")
	local cab = Cabinet.get(ctx.station, ctx.place, ctx.index, nil)
	local self: any = {
		ctx = ctx,
		cab = cab,
		hands = Hands.new(),
		seat = nil, -- this player's seat
		phase = "",
		g = 0,
		live = false, -- this player's ball is being played on this screen
		rec = nil, -- the log being recorded (InputLog.Recorder)
		tick0 = 0, -- the tick and the clock when the live play (re)started
		clock0 = 0,
		clock = 0, -- seconds of frames since the game opened
		queue = {}, -- segments not sent yet: { seg, ends a ball, sum, v }
		v = 0, -- the number of the last snapshot the server sent (every segment cut after it echoes it)
		hist = {}, -- the buttons of every tick played live since histFrom (to play again from a snapshot)
		histFrom = 0,
		liveTick = 0, -- the tick the live copy had reached at the end of the last frame
		rolled = 0, -- snapshots taken by playing this player's own hands again from them (specs)
		sentAt = -math.huge,
		sent = 0, -- segments sent (specs)
		thump = false,
		frame = nil,
		out = {},
		asked = {},
		conns = {},
		stood = false,
		touchOn = nil, -- the touch bar as it was last put up
		camOn = false,
		mouseLock = nil,
		fingers = {}, -- touch InputObject -> "left" | "right" | "pull"
		pullFrom = {}, -- the plunger finger's first height
		stickWas = 0,
		shown = "",
		bar = "",
		stopped = false,
	}
	Controller.current = self
	local place = ctx.place :: any

	local function setCamera(snap: boolean)
		if place == nil then
			return
		end
		local cam = workspace.CurrentCamera
		local size = cam and cam.ViewportSize
		local aspect = if size and size.Y > 0 then size.X / size.Y else 16 / 9
		local view = CabinetLayout.camera(cab.index, aspect)
		local ex, ey, ez = AlleyLayout.toWorld(place, view.eye[1], view.eye[2], view.eye[3])
		local tx, ty, tz = AlleyLayout.toWorld(place, view.target[1], view.target[2], view.target[3])
		ctx.camera(CFrame.lookAt(Vector3.new(ex, ey, ez), Vector3.new(tx, ty, tz)), view.fov, snap)
		self.camOn = true
	end

	-- the body at the cabinet's front, facing it
	local function stand()
		if self.stood or place == nil then
			return
		end
		local body = ctx.body()
		local root = body and body.PrimaryPart
		if root == nil then
			return
		end
		self.stood = true
		local X, D = CabinetLayout.stance(cab.index)
		local x, _, z = AlleyLayout.toWorld(place, X, 0, D)
		local fx, _, fz = AlleyLayout.toWorld(place, X, 0, D - 1)
		root.CFrame = CFrame.lookAt(Vector3.new(x, root.Position.Y, z), Vector3.new(fx, root.Position.Y, fz))
		root.AssemblyLinearVelocity = Vector3.zero
	end

	local function status(text: string)
		if text ~= self.shown then
			self.shown = text
			ctx.ui:status(text)
		end
	end

	local function ask(verb: string)
		if self.asked[verb] then
			return
		end
		self.asked[verb] = true
		ctx.send(verb)
	end

	local function setBar(name: string, list: { { string } })
		if self.bar == name then
			return
		end
		self.bar = name
		ctx.ui:buttons(list, function(id: string)
			ask(id)
		end)
	end

	local function touchBar(on: boolean)
		-- (put up once: the bar is not rebuilt under a thumb that is holding NUDGE)
		if self.touchOn == on then
			return
		end
		self.touchOn = on
		if on then
			ctx.ui:touch({ { "nudge", "NUDGE" } }, function(_id: string)
				Hands.press(self.hands, "touchNudge", BTN.NUDGE_UP)
			end, function(_id: string)
				Hands.release(self.hands, "touchNudge", BTN.NUDGE_UP)
			end)
		else
			ctx.ui:touch({}, function() end, function() end)
		end
	end

	-- segments out: joined where they may be, at most one message every SEND_EVERY (a ball's last segment at once)
	local function flush(force: boolean)
		local q = self.queue
		if #q == 0 then
			return
		end
		if not force and self.clock - self.sentAt < Controller.SEND_EVERY and not q[#q].ends then
			return
		end
		local blocks: { any } = {}
		for _, item in q do
			local last = blocks[#blocks]
			if
				last
				and not last.ends
				and last.v == item.v
				and InputLog.changes(last.seg) + InputLog.changes(item.seg) <= InputLog.WIRE_CHANGES
				and item.seg[2] - last.seg[1] <= InputLog.MAX_TICKS
			then
				last.seg = join(last.seg, item.seg)
				last.ends = item.ends
				last.sum = item.sum
			else
				table.insert(blocks, { seg = item.seg, ends = item.ends, sum = item.sum, v = item.v })
			end
		end
		table.clear(q)
		for _, b in blocks do
			local from, to, packed = InputLog.pack(b.seg)
			ctx.send("log", { from, to, packed, b.sum, b.v })
			self.sent += 1
		end
		self.sentAt = self.clock
	end

	local function startLive()
		local r = cab.r
		if r == nil then
			return
		end
		self.live = true
		cab.live = true
		self.rec = Replay.recorder(r)
		self.tick0 = r.tick
		self.clock0 = self.clock
		self.histFrom = r.tick
		self.liveTick = r.tick
		table.clear(self.hist)
		table.clear(self.queue)
		-- (a key pressed or held while it was not this player's ball does not carry into it)
		Hands.clear(self.hands)
		ctx.controls(false)
		stand()
		setCamera(not self.camOn)
	end

	local function stopLive()
		if not self.live then
			return
		end
		flush(true)
		self.live = false
		cab.live = false
		self.rec = nil
		-- the cabinet follows the game from where this screen left it
		Cabinet.rebase(cab)
		ctx.controls(true)
		if self.camOn then
			self.camOn = false
			ctx.releaseCamera()
		end
	end

	-- is the copy at this player's ball?
	local function mine(): boolean
		local r = cab.r
		return r ~= nil and self.seat ~= nil and r.m.phase ~= OVER and r.m.up == self.seat and cab.g == self.g
	end

	local function checkTurn()
		if mine() then
			if not self.live then
				startLive()
			end
		elseif self.live then
			stopLive()
		end
	end

	-- the live play, up to the clock
	local function play()
		local r = cab.r
		local rec = self.rec
		if r == nil or rec == nil then
			return
		end
		local due = self.tick0 + math.floor((self.clock - self.clock0) * Physics.HZ)
		local out = self.out
		local guard = 0
		while r.tick < due and guard < 2 * Physics.HZ do
			guard += 1
			local buttons = Hands.buttons(self.hands)
			if self.thump then
				self.thump = false
				buttons = bit32.bor(buttons, BTN.THUMP)
			end
			local up = r.m.up
			self.hist[r.tick - self.histFrom + 1] = buttons
			local seg = Replay.live(r, rec, buttons, out)
			for i = 1, #out, 3 do
				Cabinet.cue(cab, out[i], out[i + 1], out[i + 2])
			end
			table.clear(out)
			if seg then
				local m = r.m
				local ends = m.phase == OVER or m.up ~= up or (m.phase == PLAY and m.ballTicks == 0)
				table.insert(self.queue, { seg = seg, ends = ends, sum = Replay.sum(r), v = self.v })
				if m.phase == OVER or m.up ~= self.seat then
					break
				end
			end
		end
		self.liveTick = r.tick
		local kept = #self.hist
		if kept > 2 * Controller.HIST_TICKS then
			-- (only the last HIST_TICKS are kept: a snapshot is never further behind than a round trip)
			local drop = kept - Controller.HIST_TICKS
			table.move(self.hist, drop + 1, kept, 1)
			for i = kept - drop + 1, kept do
				self.hist[i] = nil
			end
			self.histFrom += drop
		end
		if r.tick < due - Controller.CHASE_LIMIT * Physics.HZ then
			-- (a hitch longer than CHASE_LIMIT: the clock is not chased, the game carries on from here. Shorter
			-- ones are caught up two seconds a frame, so the log keeps time with the server's clock)
			self.tick0 = r.tick
			self.clock0 = self.clock
		end
		flush(false)
		self.frame = Stream.read(cab.tbl, r.m, self.frame)
	end

	local Key = Enum.KeyCode
	local Kind = Enum.UserInputType

	local function plungerStrip(pos: Vector3): boolean
		local cam = workspace.CurrentCamera
		local size = cam and cam.ViewportSize
		if size == nil then
			return false
		end
		return pos.X >= size.X * Controller.STRIP.x0 and pos.Y >= size.Y * Controller.STRIP.y0
	end

	table.insert(
		self.conns,
		UIS.InputBegan:Connect(function(io: InputObject, processed: boolean)
			if InputMap.ignore(io, processed) then
				return
			end
			local name = io.KeyCode.Name
			if io.UserInputType == Kind.Touch then
				local cam = workspace.CurrentCamera
				local half = if cam then cam.ViewportSize.X / 2 else 960
				if plungerStrip(io.Position) then
					self.fingers[io] = "pull"
					self.pullFrom[io] = io.Position.Y
				elseif io.Position.X < half then
					self.fingers[io] = "left"
					Hands.press(self.hands, io, BTN.LEFT)
				else
					self.fingers[io] = "right"
					Hands.press(self.hands, io, BTN.RIGHT)
				end
				return
			end
			if name == "Space" and self.phase == "lobby" then
				ask("start")
				return
			end
			local b = Hands.KEYS[name] or Hands.PAD[name] or Hands.MOUSE[io.UserInputType.Name]
			if b then
				Hands.press(self.hands, name ~= "Unknown" and name or io.UserInputType.Name, b)
			end
		end)
	)
	table.insert(
		self.conns,
		UIS.InputEnded:Connect(function(io: InputObject, _processed: boolean)
			local name = io.KeyCode.Name
			local finger = self.fingers[io]
			if finger then
				self.fingers[io] = nil
				if finger == "pull" then
					Hands.pull(self.hands, io, nil)
					self.pullFrom[io] = nil
				else
					Hands.release(self.hands, io, if finger == "left" then BTN.LEFT else BTN.RIGHT)
				end
				return
			end
			local b = Hands.KEYS[name] or Hands.PAD[name] or Hands.MOUSE[io.UserInputType.Name]
			if b then
				-- (released even when the game took the event: a key let go must never stay held)
				Hands.release(self.hands, name ~= "Unknown" and name or io.UserInputType.Name, b)
			end
		end)
	)
	table.insert(
		self.conns,
		UIS.InputChanged:Connect(function(io: InputObject, _processed: boolean)
			local finger = self.fingers[io]
			if finger == "pull" then
				local cam = workspace.CurrentCamera
				local h = if cam then cam.ViewportSize.Y else 1080
				local from = self.pullFrom[io] or io.Position.Y
				Hands.pull(self.hands, io, (io.Position.Y - from) / (h * Controller.STRIP.drag))
			elseif io.KeyCode == Key.Thumbstick2 then
				-- the right stick pulled down is the plunger, as far as it is pulled
				local down = -io.Position.Y
				Hands.pull(self.hands, "stick", if down > Hands.STICK_PULL_DEAD then down else nil)
			elseif io.KeyCode == Key.Thumbstick1 then
				-- the left stick flicked out is a nudge
				local x, y = io.Position.X, io.Position.Y
				local m = math.sqrt(x * x + y * y)
				if m >= Hands.STICK_NUDGE and self.stickWas < Hands.STICK_RESET then
					local b = if math.abs(x) > math.abs(y)
						then (if x < 0 then BTN.NUDGE_L else BTN.NUDGE_R)
						else BTN.NUDGE_UP
					Hands.press(self.hands, "stickNudge", b)
				elseif m < Hands.STICK_RESET then
					Hands.release(self.hands, "stickNudge", BTN.NUDGE_L)
					Hands.release(self.hands, "stickNudge", BTN.NUDGE_R)
					Hands.release(self.hands, "stickNudge", BTN.NUDGE_UP)
				end
				self.stickWas = m
			end
		end)
	)

	table.insert(
		self.conns,
		RunService.RenderStepped:Connect(function(dt: number)
			self.clock += dt
			if self.live then
				play()
				if self.frame then
					Cabinet.show(cab, self.frame, dt)
				end
				checkTurn()
			end
		end)
	)

	local function card(view: { [string]: any }): string
		local g = view.game
		if g == nil or g.phase == "off" then
			return ""
		end
		return tostring(g.status or "")
	end

	function self.onState(_self: any, msg: { [string]: any })
		local view = msg.view
		local was = self.phase
		self.phase = view.phase
		self.seat = msg.you or self.seat
		if was ~= view.phase then
			table.clear(self.asked)
		end
		if view.phase == "lobby" then
			setBar("lobby", { { "start", "Start (Space)" }, { "leave", "Leave (Q)" } })
			touchBar(false)
			stand()
			local n = #(view.seats or {})
			status(
				`Starting in {view.lobbyLeft or 0} s (Space starts now). {n} of 4 players: friends can press E to join.`
			)
		elseif view.phase == "playing" then
			setBar("playing", { { "leave", "Leave (Q)" } })
			touchBar(UIS.TouchEnabled)
			status(card(view))
			checkTurn()
		elseif view.phase == "done" then
			stopLive()
			setBar("done", { { "again", "Play again" }, { "leave", "Leave (Q)" } })
			touchBar(false)
			status("")
		end
	end

	-- A snapshot while this player's ball is live: the server's game at its tick, which is behind this screen's.
	-- When the ball is still this player's, their own hands from that tick on (kept tick by tick) are played
	-- again on it up to where this screen had got to, and sent again under the snapshot's number: the ball does
	-- not jump back in time and nothing pressed is lost (it lands where the server's game puts it, if that
	-- differs). Otherwise (the server took the ball) the copy carries on from the snapshot.
	local function rollForward(): boolean
		local r = cab.r
		local back = self.liveTick
		if
			r == nil
			or cab.g ~= self.g
			or r.m.phase == OVER
			or r.m.up ~= self.seat
			or r.tick < self.histFrom
			or r.tick > back
		then
			return false
		end
		self.rec = Replay.recorder(r)
		table.clear(self.queue)
		local out = self.out
		while r.tick < back do
			local buttons = self.hist[r.tick - self.histFrom + 1] or 0
			local up = r.m.up
			local seg = Replay.live(r, self.rec, buttons, out)
			table.clear(out) -- (heard once already)
			if seg then
				local m = r.m
				local ends = m.phase == OVER or m.up ~= up or (m.phase == PLAY and m.ballTicks == 0)
				table.insert(self.queue, { seg = seg, ends = ends, sum = Replay.sum(r), v = self.v })
				if m.phase == OVER or m.up ~= self.seat then
					break
				end
			end
		end
		self.liveTick = r.tick
		self.rolled += 1
		self.frame = Stream.read(cab.tbl, r.m, self.frame)
		flush(true)
		return true
	end

	function self.onMessage(_self: any, msg: { [string]: any }, _watched: any?)
		local kind = msg.kind
		if kind == "pinball_sync" then
			self.g = tonumber(msg.g) or self.g
			self.v = tonumber(msg.v) or self.v
			if self.live and not rollForward() then
				-- the server's game, from which this ball carries on (the server played by itself)
				self.live = false
				cab.live = false
				ctx.controls(true)
			end
			checkTurn()
		elseif kind == "pinball" then
			checkTurn()
		elseif kind == "pinball_thump" then
			if self.live then
				self.thump = true
			end
		end
	end

	function self.onRefused(_self: any, _msg: { [string]: any })
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
		Hands.clear(self.hands)
		self.live = false
		cab.live = false
		cab.mine = nil
		ctx.ui:touch({}, function() end, function() end)
		ctx.controls(true)
		pcall(function()
			local p = game:GetService("Players").LocalPlayer
			if self.mouseLock ~= nil then
				(p :: any).DevEnableMouseLock = self.mouseLock
			end
		end)
		ctx.releaseCamera()
	end

	-- Left Shift is a flipper: no shift lock while the game is open
	pcall(function()
		local p = game:GetService("Players").LocalPlayer :: any
		self.mouseLock = p.DevEnableMouseLock
		p.DevEnableMouseLock = false
	end)
	stand()
	return self
end

return Controller
