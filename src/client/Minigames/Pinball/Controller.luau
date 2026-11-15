--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.Pinball.Controller
-- A player at a pinball machine. NOTHING HERE WAITS FOR THE SERVER TO MOVE A FLIPPER: while it is this player's
-- ball, this screen's own copy of the game (the Replay the cabinet keeps, Client/Minigames/Pinball/Cabinet) is
-- stepped live (Replay.live) at 240 ticks a second against this screen's clock, the hands (Pinball/Hands) giving
-- the buttons for every tick; the log it records is sent to the server about ten times a second as the verb
-- "log" { fromTick, toTick, packed changes, Replay.sum, v } (at most one message every SEND_EVERY seconds:
-- segments that pile up in a long frame are joined into one, never across the end of a ball; v is the number
-- of the last snapshot the server sent, so the server can drop what was cut before it). The server replays it
-- and is the score of record. A frame hitch is caught up (up to CHASE_LIMIT), so the log keeps the server's time.
-- DRAWN SMOOTHLY: the frame shown is blended between the last two ticks played, at the fraction of a tick this
-- frame's clock stands at (Stream.blend), so a fast ball moves the same distance every frame at any frame
-- rate (at 144 a second a frame is 1.67 ticks: drawing whole ticks would step it 1, 2, 2, 1, 2 ticks).
-- A SNAPSHOT while this player's ball is live (the server found a drift) is not a step back in time: the
-- player's own hands, kept tick by tick (HIST_TICKS), are played again on the server's game from its tick to
-- where this screen had got to, and sent again under the snapshot's number. Only when the server took the ball
-- (it played by itself) does the copy simply carry on from the snapshot.
-- WHEN A PRESS LANDS. The engine hands a client its input events once a frame, before the frame's render step,
-- and gives them no time of their own: a press is put on the first 240 Hz tick that has not been played yet
-- (the tick just after the frame the player last saw), a release likewise; a flipper tapped down and up between
-- two frames is held for a whole stroke (Hands.PULSE). So a press is placed to within one frame: 4 ticks at 60
-- frames a second, 8 at 30, never later than the frame it arrived in (no added delay). Keys pressed while it is
-- not this player's ball are not kept for it (Hands is cleared when the ball comes up).
-- Between this player's balls (another player is up) the camera and the legs are given back, the body steps
-- aside to its own spot (SPOTS: nobody stands on anybody), and the cabinet follows the other player's ball half
-- a second behind; when the copy reaches this player's ball the controller takes over again on its own, and the
-- body steps up to the cabinet. An animal that lands on the cabinet is a thump the server grants
-- ("pinball_thump"): it is let into the log on the next tick.
-- THE PICTURE. The camera is the player's eye over the lockdown bar looking down the playfield (Shared/
-- Minigames/Pinball/Cabinet.camera: the whole field, both flippers and the plunger in view on any screen shape);
-- V (the gamepad's D-pad up, VIEW on a touch screen) leans out over the glass for the view from nearly above.
-- While the ball is live the glass on this screen and this player's own body (and anybody else's within
-- HIDE_NEAR of the eye) are not drawn. Shift lock is switched off while the game is open (Left Shift is a
-- flipper).
-- THE HUD keeps off the table (layout(): every rectangle is placed against where the camera puts the playfield
-- on this screen): the dot-matrix display (Pinball/Dmd: score, ball, player up, every callout of the backglass,
-- TILT WARNING in red) stands beside the table in the empty cabinet side when the screen is wide enough (SIDE_MIN
-- pixels), else along the top, with the camera framing the table under it. The buttons, the touch buttons
-- (NUDGE, HELP, VIEW) and the banner go in the same side column; the scorecard goes where the table is not
-- (Games/Pinball asks cardRect()). The rule line is the display's, never a status line across the table. The
-- help card is put away when the ball comes up if it lies over the table (H, or HELP, brings it back).
-- LEAVING. In the lobby and at the end Q (gamepad B, the Leave button) leaves at once; while a game is on it
-- takes a second press within LEAVE_AGAIN ("Press Q again to leave"): Q sits beside A, W and Z.
-- TOUCH: the left half of the screen is the left flipper and the right half the right, each finger followed by
-- its own InputObject; while a ball waits on the plunger for the player's hand (Machine.resting) a finger that
-- comes down on the right half pulls the plunger instead, as far as it is dragged down (STRIP.drag of the
-- screen's height is a full pull).
-- The main client's rules (MinigameClient's header): the camera through ctx.camera / ctx.releaseCamera, the
-- cursor MinigameUI's, everything connected here disconnected in stop() (and the HUD put back where it was).
-- Interface: new(ctx) -> Controller; HELP; SEND_EVERY; CHASE_LIMIT; HIST_TICKS; STRIP; SPOTS; HIDE_NEAR;
--   LEAVE_AGAIN; SIDE_MIN; SMALL_HEIGHT; INSET; small() -> bool; short() -> bool; cardRect() -> { x, y, w, h,
--   small } (the scorecard's place for the open controller, pixels of the HUD); current (the controller open
--   now, for the specs: .cab, .live, .hands, .seat, .sent, .rolled, .drawn, .dmd, .lay, .view, .over, .say)

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
local Layout = Import.shared("Minigames/Pinball/Layout") :: typeof(require("../../../shared/Minigames/Pinball/Layout"))
local AlleyLayout =
	Import.shared("Attractions/AlleyLayout") :: typeof(require("../../../shared/Attractions/AlleyLayout"))
local InputMap = require("../../Input/InputMap")
local ClientGame = require("../ClientGame")
local Cabinet = require("./Cabinet")
local Dmd = require("./Dmd")
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
		"Gamepad  L1/L2, R1/R2 flippers; A or right stick down: plunger; flick the left stick: nudge; D-pad up: view",
		"Touch  left half and right half of the screen: flippers; with the ball on the plunger, drag down on the right half to pull it",
		"V  the view from above     H  this card     Q twice / gamepad B twice  leave",
	},
}
Controller.SEND_EVERY = 0.09 -- seconds: at most this often a segment of the log goes out
Controller.CHASE_LIMIT = 10 -- seconds: a frame hitch up to this long is caught up (the ball played on), longer is not
Controller.HIST_TICKS = 4800 -- ticks of this player's own hands kept to play again from a snapshot (20 s)
Controller.STRIP = { drag = 0.3 } -- the touch plunger: a full pull is a drag of this much of the screen's height
-- where a seated player stands while somebody else's ball is up (studs from the stance: across, and back)
Controller.SPOTS = { { x = -1.9, d = 1.3 }, { x = 1.9, d = 1.3 }, { x = 0, d = 2.6 } }
Controller.HIDE_NEAR = 2.2 -- studs: a body this close to the eye is not drawn on this screen while the ball is live
Controller.LEAVE_AGAIN = 2.5 -- seconds: while a game is on, a second Q (B, Leave) inside this leaves
Controller.SIDE_MIN = 230 -- pixels of empty screen beside the table for the display to stand there
Controller.SMALL_HEIGHT = 600 -- pixels: a screen shorter than this is a small one
Controller.INSET = 58 -- pixels the top bar takes when the engine does not say (GuiService:GetGuiInset)
Controller.current = nil :: any

local BTN = Machine.BTN
local PLAY, OVER = Machine.PHASE.PLAY, Machine.PHASE.OVER
local GAP = 12

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

local function viewport(): Vector2
	local cam = workspace.CurrentCamera
	local size = cam and cam.ViewportSize
	if size == nil or size.X <= 0 or size.Y <= 0 then
		return Vector2.new(1920, 1080)
	end
	return size
end

local function inset(): number
	local ok, top = pcall(function(): number
		return (game:GetService("GuiService") :: any):GetGuiInset().Y
	end)
	return if ok and type(top) == "number" and top > 0 then top else Controller.INSET
end

-- A screen too short for much beside the table.
function Controller.short(): boolean
	return viewport().Y < Controller.SMALL_HEIGHT
end

-- A touch device, or a short screen.
function Controller.small(): boolean
	return game:GetService("UserInputService").TouchEnabled or Controller.short()
end

-- Where the HUD goes on this screen, from where the camera puts the table (pixels of the HUD: the top bar's
-- inset is above y = 0). side: the display stands in the empty cabinet side at the left; otherwise it runs along
-- the top and the camera keeps the table under it (reserve).
export type Lay = {
	w: number,
	h: number,
	inset: number,
	side: boolean,
	reserve: { top: number, bottom: number },
	dmd: { number },
	column: number, -- the left column's width (pixels) beside the table
	bars: number, -- where the button rows start in the left column (y)
	banner: { number },
	card: { number },
	smallCard: boolean,
	key: string,
}

local function layoutFor(index: number, which: string): Lay
	local size = viewport()
	local w, h = size.X, size.Y
	local top = inset()
	local touch = game:GetService("UserInputService").TouchEnabled
	local short = h < Controller.SMALL_HEIGHT
	-- with the display beside the table, the table may use the whole height
	local sideReserve = { top = 0.02, bottom = 0.02 }
	local view = CabinetLayout.camera(index, w / h, which, sideReserve)
	local u0 = CabinetLayout.project(view, CabinetLayout.point(index, 0, 0, 0))
	local u1 = CabinetLayout.project(view, CabinetLayout.point(index, Layout.WIDTH, 0, 0))
	local left = math.min(u0, u1) * w
	local lay: any = { w = w, h = h, inset = top }
	if left - 2 * GAP >= Controller.SIDE_MIN then
		lay.side = true
		lay.reserve = sideReserve
		lay.column = math.floor(left - 2 * GAP)
		local dh = math.clamp(math.floor(lay.column * 0.42), 70, 130)
		lay.dmd = { GAP, 6, lay.column, dh }
		lay.bars = 6 + dh + 8
	else
		-- along the top: the camera frames the table under it
		local dw = math.min(w - 2 * GAP, 560)
		local dh = math.clamp(math.floor(h * 0.085), 40, 80)
		lay.side = false
		lay.reserve = { top = (top + 6 + dh + 6) / h, bottom = 0.02 }
		view = CabinetLayout.camera(index, w / h, which, lay.reserve)
		u0 = CabinetLayout.project(view, CabinetLayout.point(index, 0, 0, 0))
		u1 = CabinetLayout.project(view, CabinetLayout.point(index, Layout.WIDTH, 0, 0))
		left = math.min(u0, u1) * w
		lay.column = math.max(110, math.floor(left - 2 * GAP))
		lay.dmd = { math.floor((w - dw) / 2), 6, dw, dh }
		lay.bars = if touch then math.floor(h * 0.22) else -1 -- (-1: the framework's own place, bottom left)
	end
	-- the banner: in the left column, under the buttons (or, with the buttons in their own place, a third down)
	local bannerY = if lay.bars >= 0 then lay.bars + (if touch then 112 else 56) else math.floor((h - top) * 0.33)
	lay.banner = { GAP, bannerY, lay.column, 46 }
	-- the scorecard: the bottom right corner when the table leaves it free (and no thumb rests there), else a
	-- strip in the top right corner
	local right = math.max(u0, u1) * w
	local cw, ch = 330, 150
	local cx = w - cw - GAP
	if not touch and not short and cx >= right + GAP then
		lay.smallCard = false
		lay.card = { cx, h - top - ch - GAP, cw, ch }
	else
		lay.smallCard = true
		local sw = math.clamp(math.floor(w - right - 2 * GAP), 150, 230)
		lay.card = { w - sw - GAP, 6, sw, 54 }
	end
	lay.key = `{w}x{h}:{which}:{touch}`
	return lay :: Lay
end

-- the scorecard's place for the controller open now (Games/Pinball draws the card there)
function Controller.cardRect(): { [string]: any }
	local c = Controller.current
	local lay = c and c.lay
	if lay == nil then
		return { x = -342, y = -162, w = 330, h = 150, small = false, fromRight = true }
	end
	return { x = lay.card[1], y = lay.card[2], w = lay.card[3], h = lay.card[4], small = lay.smallCard }
end

function Controller.new(ctx: ClientGame.Ctx): ClientGame.Controller
	local UIS = game:GetService("UserInputService")
	local RunService = game:GetService("RunService")
	local cab = Cabinet.get(ctx.station, ctx.place, ctx.index, nil)
	local ui = ctx.ui :: any
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
		frame = nil, -- the live copy's frame at its last tick
		prev = nil, -- and at the tick before
		drawn = nil, -- what was drawn this frame (blended)
		out = {},
		asked = {},
		conns = {},
		standing = "", -- where the body was last stood: "stance" | "spot"
		touchOn = nil, -- the touch bar as it was last put up
		camOn = false,
		view = "play",
		mouseLock = nil,
		fingers = {}, -- touch InputObject -> "left" | "right" | "pull"
		pullFrom = {}, -- the plunger finger's first height
		stickWas = 0,
		shown = "",
		bar = "",
		leaveAt = -math.huge, -- when the first of the two presses that leave a game in play was made
		hidHelp = false,
		hidden = {}, -- parts whose LocalTransparencyModifier this screen set: part -> what it was
		hideAt = -math.huge,
		lay = nil,
		over = nil, -- the end of the last game as the server said it: { place, best, newBest }
		stopped = false,
	}
	Controller.current = self
	local place = ctx.place :: any
	local dmd = Dmd.new(ui.gui or ui.card.Parent)
	self.dmd = dmd
	-- the framework's widgets this controller moves, put back in stop()
	local home = {}
	for _, name in { "buttonBar", "touchBar", "bannerLabel" } do
		local g = ui[name]
		if g ~= nil then
			home[name] = { g, g.Position, g.Size }
		end
	end

	local function relayout()
		local lay = layoutFor(cab.index, self.view)
		self.lay = lay
		Dmd.place(dmd, lay.dmd[1], lay.dmd[2], lay.dmd[3], lay.dmd[4])
		local bar, touch = ui.buttonBar, ui.touchBar
		if lay.bars >= 0 then
			if touch then
				touch.Position = UDim2.fromOffset(GAP, lay.bars)
			end
			if bar then
				bar.Position = UDim2.fromOffset(GAP, lay.bars + (if UIS.TouchEnabled then 54 else 0))
			end
		else
			for _, name in { "buttonBar", "touchBar" } do
				local h = home[name]
				if h then
					h[1].Position = h[2]
				end
			end
		end
	end
	relayout()

	-- a banner, as this game says it: in the left column, beside the table
	local function say(text: string, big: boolean?)
		ui:banner(text, big == true)
		local label = ui.bannerLabel
		local lay = self.lay
		if label ~= nil and lay ~= nil then
			label.Position = UDim2.fromOffset(lay.banner[1], lay.banner[2])
			label.Size = UDim2.fromOffset(lay.banner[3], lay.banner[4])
		end
	end
	self.say = say

	local function setCamera(snap: boolean)
		if place == nil then
			return
		end
		local size = viewport()
		local lay = self.lay
		local view = CabinetLayout.camera(cab.index, size.X / size.Y, self.view, lay and lay.reserve)
		local ex, ey, ez = AlleyLayout.toWorld(place, view.eye[1], view.eye[2], view.eye[3])
		local tx, ty, tz = AlleyLayout.toWorld(place, view.target[1], view.target[2], view.target[3])
		ctx.camera(CFrame.lookAt(Vector3.new(ex, ey, ez), Vector3.new(tx, ty, tz)), view.fov, snap)
		self.camOn = true
		self.eye = Vector3.new(ex, ey, ez)
	end

	-- the body: at the cabinet's front facing it while this player's ball is live, else at the seat's own spot
	local function stand(where: string)
		if self.standing == where or place == nil then
			return
		end
		local body = ctx.body()
		local root = body and body.PrimaryPart
		if root == nil then
			return
		end
		self.standing = where
		local X, D = CabinetLayout.stance(cab.index)
		local px = X
		if where == "spot" then
			local spot = Controller.SPOTS[((self.seat or 1) - 1) % #Controller.SPOTS + 1]
			X += spot.x
			D += spot.d
		end
		local x, _, z = AlleyLayout.toWorld(place, X, 0, D)
		-- (facing the backglass)
		local fx, _, fz = AlleyLayout.toWorld(place, px, 0, D - 3)
		root.CFrame = CFrame.lookAt(Vector3.new(x, root.Position.Y, z), Vector3.new(fx, root.Position.Y, fz))
		root.AssemblyLinearVelocity = Vector3.zero
	end

	-- not drawn on this screen while the ball is live: the glass, this player's body, anyone at the eye
	local function hide(part: any)
		if self.hidden[part] == nil then
			local ok, was = pcall(function()
				return part.LocalTransparencyModifier
			end)
			self.hidden[part] = if ok and type(was) == "number" then was else 0
			pcall(function()
				part.LocalTransparencyModifier = 1
			end)
		end
	end
	local function hideBody(model: any)
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") or d:IsA("Decal") then
				hide(d)
			end
		end
	end
	local function unhide()
		for part, was in self.hidden do
			pcall(function()
				part.LocalTransparencyModifier = was
			end)
		end
		table.clear(self.hidden)
	end
	local function hideAll()
		local parts = cab.parts
		if parts then
			-- (looked at again every half second; every frame until the cabinet's parts have been found)
			self.hideAt = self.clock
			if parts.glass then
				hide(parts.glass)
			end
		end
		local body = ctx.body()
		if body then
			hideBody(body)
		end
		local eye = self.eye
		if eye == nil then
			return
		end
		pcall(function()
			for _, p in (game:GetService("Players") :: any):GetPlayers() do
				local char = p.Character
				local root = char and char.PrimaryPart
				if char and char ~= body and root and (root.Position - eye).Magnitude < Controller.HIDE_NEAR + 2 then
					hideBody(char)
				end
			end
		end)
	end

	local function status(text: string)
		if text ~= self.shown then
			self.shown = text
			ui:status(text)
		end
	end

	local function ask(verb: string)
		if self.asked[verb] then
			return
		end
		self.asked[verb] = true
		ctx.send(verb)
	end

	local leave: (source: string) -> ()
	local toggleView: () -> ()

	local function setBar(name: string, list: { { string } })
		if self.bar == name then
			return
		end
		self.bar = name
		ui:buttons(list, function(id: string)
			if id == "leave" then
				leave("button")
			elseif id == "view" then
				toggleView()
			else
				ask(id)
			end
		end)
	end

	local function playBar()
		local confirm = self.clock - self.leaveAt <= Controller.LEAVE_AGAIN
		if confirm then
			setBar("playing:again", { { "leave", "Tap again to leave" } })
		else
			setBar("playing", { { "leave", if UIS.TouchEnabled then "Leave" else "Leave (Q)" } })
		end
	end

	local function helpShown(): boolean
		local frame = ui.helpFrame
		return frame ~= nil and frame.Visible == true
	end

	local function touchBar(on: boolean)
		-- (put up once: the bar is not rebuilt under a thumb that is holding NUDGE)
		if self.touchOn == on then
			return
		end
		self.touchOn = on
		if on then
			ui:touch({ { "nudge", "NUDGE" }, { "help", "HELP" }, { "view", "VIEW" } }, function(id: string)
				if id == "nudge" then
					Hands.press(self.hands, "touchNudge", BTN.NUDGE_UP)
				elseif id == "help" then
					ui:toggleHelp()
				elseif id == "view" then
					toggleView()
				end
			end, function(id: string)
				if id == "nudge" then
					Hands.release(self.hands, "touchNudge", BTN.NUDGE_UP)
				end
			end)
		else
			ui:touch({}, function() end, function() end)
		end
	end

	-- Leaving: at once in the lobby and at the end, a second press while a game is on
	leave = function(source: string)
		if self.phase ~= "playing" then
			ask("leave")
			return
		end
		if self.clock - self.leaveAt <= Controller.LEAVE_AGAIN then
			ask("leave")
			return
		end
		self.leaveAt = self.clock
		say(
			if source == "pad"
				then "Press B again to leave"
				elseif source == "button" and UIS.TouchEnabled then "Tap Leave again to leave"
				elseif source == "button" then "Click Leave again to leave"
				else "Press Q again to leave",
			false
		)
		playBar()
	end

	toggleView = function()
		self.view = if self.view == "play" then "high" else "play"
		relayout()
		if self.camOn then
			setCamera(false)
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
		self.prev = nil
		self.frame = Stream.read(cab.tbl, r.m, self.frame)
		table.clear(self.hist)
		table.clear(self.queue)
		-- (a key pressed or held while it was not this player's ball does not carry into it)
		Hands.clear(self.hands)
		ctx.controls(false)
		stand("stance")
		setCamera(not self.camOn)
		hideAll()
		if helpShown() and (self.lay.side == false or self.lay.column < 340 + GAP) then
			-- (the card lies over the table on this screen: H, or HELP, brings it back)
			ui:toggleHelp()
			self.hidHelp = true
		end
	end

	local function stopLive()
		if not self.live then
			return
		end
		flush(true)
		self.live = false
		cab.live = false
		self.rec = nil
		unhide()
		-- the cabinet follows the game from where this screen left it
		Cabinet.rebase(cab)
		ctx.controls(true)
		if self.camOn then
			self.camOn = false
			ctx.releaseCamera()
		end
		if self.phase == "playing" then
			stand("spot")
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

	-- the live play, up to the clock; the frame drawn is blended between the last two ticks
	local function play()
		local r = cab.r
		local rec = self.rec
		if r == nil or rec == nil then
			return
		end
		local at = (self.clock - self.clock0) * Physics.HZ
		local due = self.tick0 + math.floor(at)
		local out = self.out
		local guard = 0
		local tbl = cab.tbl
		while r.tick < due and guard < 2 * Physics.HZ do
			guard += 1
			if r.tick == due - 1 then
				self.prev = Stream.read(tbl, r.m, self.prev)
			end
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
		self.frame = Stream.read(tbl, r.m, self.frame)
		local prev = self.prev
		if prev ~= nil and r.tick == due and prev.tick == self.frame.tick - 1 then
			-- (what the ball looked like at the fraction of a tick this frame's clock stands at, one tick back)
			self.drawn = Stream.blend(prev, self.frame, at - math.floor(at), self.drawn)
		else
			self.drawn = self.frame
		end
	end

	local Key = Enum.KeyCode
	local Kind = Enum.UserInputType

	-- a ball waits on the plunger for this player's hand (a touch on the right half pulls it)
	local function plungerWaits(): boolean
		local r = cab.r
		return self.live and r ~= nil and Machine.resting(cab.tbl, r.m) > 0
	end

	table.insert(
		self.conns,
		UIS.InputBegan:Connect(function(io: InputObject, processed: boolean)
			if InputMap.ignore(io, processed) then
				return
			end
			local name = io.KeyCode.Name
			if io.UserInputType == Kind.Touch then
				if not self.live then
					return
				end
				local half = viewport().X / 2
				if io.Position.X >= half and plungerWaits() then
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
			if name == "Q" then
				leave("key")
				return
			elseif name == "ButtonB" then
				leave("pad")
				return
			elseif name == "V" or name == "DPadUp" then
				toggleView()
				return
			end
			if name == "Space" and self.phase == "lobby" then
				ask("start")
				return
			end
			if not self.live then
				return -- (between this player's balls the keys walk the body; nothing is kept for the next ball)
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
				local h = viewport().Y
				local from = self.pullFrom[io] or io.Position.Y
				Hands.pull(self.hands, io, (io.Position.Y - from) / (h * Controller.STRIP.drag))
			elseif not self.live then
				return
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

	-- the display: the frame this player is looking at (their own ball, or the one they follow)
	local function drawDmd()
		local f, m = nil, nil
		if self.live then
			f = self.drawn
			m = cab.r and cab.r.m
		elseif cab.mode == "follow" and cab.frame then
			f = cab.frame
			m = cab.r and cab.r.m
		end
		if f == nil or self.phase ~= "playing" then
			Dmd.show(dmd, false)
			return
		end
		Dmd.show(dmd, true)
		Dmd.draw(dmd, cab.tbl, f, m, {
			score = if cab.variant == "acorn" then cab.reel else nil,
			clock = self.clock,
		})
	end

	table.insert(
		self.conns,
		RunService.RenderStepped:Connect(function(dt: number)
			self.clock += dt
			local lay = self.lay
			local size = viewport()
			if lay and (lay.w ~= size.X or lay.h ~= size.Y) then
				-- (the window was resized, or the phone turned)
				relayout()
				if self.camOn then
					setCamera(false)
				end
			end
			if self.live then
				play()
				if self.drawn then
					Cabinet.show(cab, self.drawn, dt)
				end
				if self.clock - self.hideAt > 0.5 then
					hideAll()
				end
				checkTurn()
			end
			if self.bar == "playing:again" and self.clock - self.leaveAt > Controller.LEAVE_AGAIN then
				playBar()
			end
			drawDmd()
		end)
	)

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
			stand(if (self.seat or 1) == 1 then "stance" else "spot")
			local n = #(view.seats or {})
			status(
				`Starting in {view.lobbyLeft or 0} s (Space starts now). {n} of 4 players: friends can press E to join.`
			)
		elseif view.phase == "playing" then
			self.over = nil
			playBar()
			touchBar(UIS.TouchEnabled)
			-- (no words over the table: what to shoot for is on the display)
			status("")
			checkTurn()
			if not self.live then
				stand("spot")
			end
		elseif view.phase == "done" then
			stopLive()
			if msg.place ~= nil or msg.best ~= nil then
				self.over = { place = msg.place, best = msg.best, newBest = msg.newBest }
			end
			setBar("done", { { "again", "Play again" }, { "leave", "Leave (Q)" } })
			touchBar(false)
			status("")
		end
	end

	-- A snapshot while this player's ball is live: the server's game at its tick, which is behind this screen's.
	-- When the ball is still this player's, their own hands from that tick on are played again on it up to where
	-- this screen had got to, and sent again under the snapshot's number (see the header).
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
		self.prev = nil
		self.frame = Stream.read(cab.tbl, r.m, self.frame)
		self.drawn = self.frame
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
				unhide()
				ctx.controls(true)
			end
			checkTurn()
		elseif kind == "pinball" then
			checkTurn()
		elseif kind == "pinball_thump" then
			if self.live then
				self.thump = true
			end
		elseif kind == "pinball_over" then
			if msg.seat ~= nil and msg.seat == self.seat then
				self.over = {
					place = msg.places and msg.places[msg.seat],
					best = msg.best,
					newBest = msg.newBest,
				}
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
		unhide()
		Dmd.destroy(dmd)
		for _, h in home do
			h[1].Position = h[2]
			h[1].Size = h[3]
		end
		if self.hidHelp and not helpShown() then
			ui:toggleHelp()
		end
		ui:touch({}, function() end, function() end)
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
	return self
end

return Controller
