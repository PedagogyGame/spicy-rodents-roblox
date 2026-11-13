--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.Pool.CueController
-- The shooter's side of a cue-sport table: pool (eight-ball) and bumper pool share it; each game's own file
-- (Client/Minigames/Games/Pool, BumperPool) hands it a `Game` that says which ball is struck, what the rules
-- allow and what the status line reads. On your turn:
--   AIM   the camera takes the line behind the ball, low over the cue, and you stand behind the shot; drag
--         (mouse or finger) or A / D turns the aim, Shift for a fine touch; T is the top view, where a click
--         or a drag on the cloth points the cue at the cursor. The aim line runs to a GHOST BALL at the first
--         contact, with a short line for the object ball and one for where the struck ball goes after (both
--         from Shared/Minigames/Pool/Cue.preview: the same table model that will play the shot, so the lines
--         answer the tip and the power). The lines are short: potting stays a skill.
--   SPIN  the small cue-ball picture: drag the dot (or W / S for follow and draw, Z / X for side, C centres).
--   POWER draw the cue back: pull the bar on the right down and let go, or hold Space (the power rises once
--         and falls back: let it run out to change your mind). The cue is drawn back as far as the power.
--   BALL IN HAND  the top view comes up and the cue ball follows the cursor (or WASD); it is set down where
--         the rules allow (the rules' own check, so the server never has to refuse), then Space.
--   THE 8  click a pocket to call it (1 to 6 also do): a ring marks it.
--   WALK  V gives your legs and your own camera back: walk round the table, and V again takes the shot from
--         where you stand (the line from you through the ball).
--   Bumper pool: click one of your balls (or R) to choose which to strike.
-- After the strike the camera rises to watch the balls run (the top view for a break) until the last one has
-- stopped. Between turns your legs and camera are your own; T still gives the top view to watch from.
-- Gamepad: left stick aims (L1 / R1 nudge), right stick sets the spin, hold and release R2, Y top view, X
-- walk, D-pad moves a ball in hand, picks the pocket or the ball, A sets the ball down. Touch: drag to aim,
-- drag the dot, pull the bar, and the hold buttons (HOLD TO SHOOT, TOP VIEW, WALK, DONE).
-- The main client's rules (MinigameClient's header): shots go through ctx.camera / ctx.releaseCamera; the
-- cursor is the one MinigameUI's buttons ask for; nothing from before a hand-over of the keys counts; nothing
-- is left bound after stop(). A finger is followed by its InputObject. One "shoot" (and a "place" or "call"
-- only when something is set down or chosen) goes to the server: never a message a frame.
-- Interface: new(ctx, mode: Game) -> Controller (onState, onMessage, onRefused, stop); Controller facts a spec
--   reads: phase ("off" | "place" | "aim" | "walk" | "sent" | "watch"), angle, power, tipX, tipY, sel,
--   pocket, top, preview; pad() / strip() -> the widgets' rectangles in pixels; live[stationId] -> the
--   Controller open at that station; constants (TURN, DRAG, RISE, MIN_POWER ...)

local Import = require("../../Import")
local AlleyLayout =
	Import.shared("Attractions/AlleyLayout") :: typeof(require("../../../shared/Attractions/AlleyLayout"))
local Cue = Import.shared("Minigames/Pool/Cue") :: typeof(require("../../../shared/Minigames/Pool/Cue"))
local Furniture =
	Import.shared("Minigames/Pool/Furniture") :: typeof(require("../../../shared/Minigames/Pool/Furniture"))
local Games = Import.shared("Minigames/Games") :: typeof(require("../../../shared/Minigames/Games"))
local InputMap = require("../../Input/InputMap")
local Playback = require("./Playback")
local Stick = require("./Stick")

local Controller = {}
Controller.__index = Controller

-- the controllers that are open, by station (a developer's console and the specs look at one through this)
Controller.live = {} :: { [string]: any }

Controller.TURN = 1.1 -- radians a second with A / D or the stick
Controller.FINE = 0.07 -- with Shift held
Controller.DRAG = 0.0022 -- radians for a pixel dragged
Controller.FINE_DRAG = 0.2 -- of that, with Shift held
Controller.NUDGE = 0.004 -- radians: one tap of L1 / R1
Controller.RISE = 1.5 -- seconds a held stroke takes to reach full power (and as long to fall back)
Controller.MIN_POWER = 0.02 -- less than this is no stroke at all
Controller.SET_POWER = 0.45 -- the power the aim lines are drawn for while the cue is at rest
Controller.TIP_RATE = 1.2 -- of the tip's reach a second (W / S / Z / X)
Controller.PLACE_RATE = 1.8 -- studs a second (WASD with the ball in hand)
Controller.WARN_AT = 15 -- seconds left on the turn clock when the warning comes up
Controller.CLICK = 6 -- pixels: a press that moves less than this is a click
Controller.SENT_WAIT = 3 -- seconds a strike waits for the server before the cue is yours again
Controller.POCKET_REACH = 0.9 -- studs: a click this near a pocket calls it
Controller.BALL_REACH = 0.4 -- studs: a click this near one of your balls picks it
Controller.CAM_BACK = 3.4 -- the cue view: behind the ball, above the cloth, looking ahead of the ball
Controller.CAM_UP = 1.75
Controller.CAM_AHEAD = 3.2
Controller.CAM_FOV = 58
Controller.TOP_H = 7.6 -- the top view's height above the cloth (kept under the ceiling)
Controller.OBJECT_LINE = 1.5 -- studs of the object ball's line that are drawn

export type Spot = { id: number, x: number, z: number }
export type Game = {
	game: string, -- the game id; its messages are "<game>_shot" and "<game>_rack", its sounds "<game>.<cue>"
	table: any, -- Tables.Table
	-- is it this seat's go? (view = the state message's view)
	mine: (view: { [string]: any }, you: number?) -> boolean,
	-- the balls this seat may strike now, the one to start on first
	strikeable: (g: { [string]: any }, you: number) -> { number },
	inHand: (g: { [string]: any }) -> string, -- "none" | "kitchen" | "anywhere"
	mustCall: (g: { [string]: any }, you: number) -> boolean,
	called: (g: { [string]: any }) -> number,
	canPlace: (g: { [string]: any }, spots: { Spot }, x: number, z: number) -> boolean,
	firstAim: (g: { [string]: any }, you: number, spots: { Spot }, ball: number) -> number,
	args: (ball: number, angle: number, power: number, tipX: number, tipY: number, pocket: number) -> { any },
	-- the status line: what the seat is on ("Your shot: solids, 3 left."); phase as the Controller's
	say: (view: { [string]: any }, you: number?, phase: string) -> string,
}

local function part(name: string, shape: Enum.PartType, color: Color3, transparency: number): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Shape = shape
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = 1
	p:SetAttribute("Shown", transparency)
	p.Parent = workspace.CurrentCamera
	return p
end

local function hide(p: BasePart)
	p.Transparency = 1
end

local function show(p: BasePart)
	p.Transparency = p:GetAttribute("Shown") :: number
end

function Controller.new(ctx: { [string]: any }, mode: Game): any
	local self = setmetatable({}, Controller) :: any
	self.ctx = ctx
	self.mode = mode
	self.tb = mode.table
	self.place = ctx.place
	self.def = Games.station(ctx.station, { bowling_alley = ctx.place }) :: any
	self.phase = "off"
	self.view = nil :: { [string]: any }?
	self.you = nil :: number?
	self.live = false -- the last state said it is my go
	self.rolling = false -- the last state said a shot is in flight
	self.spots = {} :: { Spot }
	self.byId = {} :: { [number]: Spot }
	self.angle = 0
	self.power = 0 -- the cue is drawn back this far (0 at rest)
	self.tipX = 0
	self.tipY = 0
	self.sel = 0 -- the ball being struck
	self.pocket = 0 -- the pocket called for the 8
	self.top = false -- the top view is wanted
	self.watchTop = false
	self.charge = nil :: number? -- seconds a held stroke has run
	self.presses = {} :: { [any]: { [string]: any } } -- pointers that are down: the mouse ("mouse") or a finger's InputObject
	self.stick1 = Vector2.zero -- the gamepad's sticks
	self.stick2 = Vector2.zero
	self.hand = nil :: { x: number, z: number, ok: boolean, moved: number? }? -- the cue ball while it is carried
	self.preview = nil :: any
	self.previewKey = ""
	self.version = 0 -- bumped whenever the balls on the table change
	self.t = 0
	self.sentAt = -math.huge
	self.watchSince = 0
	self.turnLeft = nil :: number?
	self.turnLeftAt = 0
	self.camUp = false -- my shot of the table is up
	self.legs = true -- my legs are my own
	self.lampHidden = false
	self.saidPhase = "" -- the phase the status line was last written for
	self.conns = {} :: { RBXScriptConnection }
	self.stick = Stick.new()
	local white = Color3.fromRGB(255, 255, 255)
	self.parts = {
		line = part("PoolAimLine", Enum.PartType.Block, white, 0.35),
		ghost = part("PoolGhostBall", Enum.PartType.Ball, white, 0.55),
		object = part("PoolObjectLine", Enum.PartType.Block, Color3.fromRGB(255, 214, 92), 0.2),
		path1 = part("PoolCuePath1", Enum.PartType.Block, Color3.fromRGB(140, 236, 236), 0.3),
		path2 = part("PoolCuePath2", Enum.PartType.Block, Color3.fromRGB(140, 236, 236), 0.45),
		path3 = part("PoolCuePath3", Enum.PartType.Block, Color3.fromRGB(140, 236, 236), 0.6),
		ring = part("PoolCalledPocket", Enum.PartType.Cylinder, Color3.fromRGB(255, 214, 92), 0.25),
		pick = part("PoolPickedBall", Enum.PartType.Cylinder, Color3.fromRGB(140, 236, 236), 0.4),
		spot = part("PoolPlaceSpot", Enum.PartType.Cylinder, Color3.fromRGB(120, 255, 140), 0.4),
	}
	self.parts.ghost.Material = Enum.Material.SmoothPlastic
	self:_widgets()
	Controller.live[ctx.station] = self
	local UIS = game:GetService("UserInputService")
	table.insert(
		self.conns,
		UIS.InputBegan:Connect(function(io: InputObject, processed: boolean)
			if not InputMap.ignore(io, processed) then
				self:_began(io)
			end
		end)
	)
	table.insert(
		self.conns,
		UIS.InputChanged:Connect(function(io: InputObject)
			self:_changed(io)
		end)
	)
	table.insert(
		self.conns,
		UIS.InputEnded:Connect(function(io: InputObject)
			self:_ended(io)
		end)
	)
	table.insert(
		self.conns,
		game:GetService("RunService").RenderStepped:Connect(function(dt: number)
			self:_frame(dt)
		end)
	)
	ctx.ui:touch(
		{ { "bowl", "HOLD TO SHOOT" }, { "top", "TOP VIEW" }, { "walk", "WALK" }, { "done", "DONE" } },
		function(id: string)
			if id == "bowl" then
				self:_hold(true)
			elseif id == "top" then
				self:_toggleTop()
			elseif id == "walk" then
				self:_toggleWalk()
			elseif id == "done" then
				self:_confirm()
			end
		end,
		function(id: string)
			if id == "bowl" then
				self:_hold(false)
			end
		end
	)
	return self
end

-- Widgets of its own: the cue-ball picture (the tip) and the bar the cue is drawn back on. They are plain
-- frames laid out in pixels (never Active: a press on them must reach this controller, which tests where it
-- landed itself), in a ScreenGui that ignores the top bar's inset so its pixels are the mouse's.
function Controller._widgets(self: any)
	local player = game:GetService("Players").LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "PoolHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 21
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")
	self.gui = gui
	local function frame(name: string, parent: Instance, color: Color3, round: number): Frame
		local f = Instance.new("Frame")
		f.Name = name
		f.BackgroundColor3 = color
		f.BorderSizePixel = 0
		f.Active = false
		f.Parent = parent
		if round > 0 then
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(round, 0)
			c.Parent = f
		end
		return f
	end
	local function caption(name: string, parent: Instance, text: string): TextLabel
		local t = Instance.new("TextLabel")
		t.Name = name
		t.BackgroundTransparency = 1
		t.Text = text
		t.TextColor3 = Color3.fromRGB(245, 245, 245)
		t.Font = Enum.Font.GothamBold
		t.TextScaled = true
		t.Active = false
		t.Parent = parent
		return t
	end
	self.padFrame = frame("TipPad", gui, Color3.fromRGB(245, 245, 240), 0.5)
	self.padDot = frame("TipDot", self.padFrame, Color3.fromRGB(220, 40, 40), 0.5)
	self.padLabel = caption("TipLabel", gui, "SPIN")
	self.stripFrame = frame("PowerStrip", gui, Color3.fromRGB(16, 20, 44), 0.2)
	self.stripFill = frame("PowerFill", self.stripFrame, Color3.fromRGB(255, 214, 92), 0.2)
	self.stripLabel = caption("PowerLabel", gui, "PULL")
end

-- The two widgets' rectangles, in the mouse's own pixels: x, y, width, height.
function Controller.pad(_self: any): (number, number, number, number)
	local vp = workspace.CurrentCamera.ViewportSize
	local size = math.clamp(vp.Y * 0.14, 90, 150)
	return 36, vp.Y - size - 150, size, size
end

function Controller.strip(_self: any): (number, number, number, number)
	local vp = workspace.CurrentCamera.ViewportSize
	local h = math.clamp(vp.Y * 0.42, 180, 400)
	return vp.X - 110, vp.Y * 0.22, 54, h
end

function Controller._layout(self: any, on: boolean)
	self.gui.Enabled = on
	if not on then
		return
	end
	local px, py, ps = self:pad()
	self.padFrame.Position = UDim2.fromOffset(px, py)
	self.padFrame.Size = UDim2.fromOffset(ps, ps)
	local dot = ps * 0.16
	local reach = ps / 2 - dot / 2
	self.padDot.Size = UDim2.fromOffset(dot, dot)
	self.padDot.Position = UDim2.fromOffset(ps / 2 + self.tipX * reach - dot / 2, ps / 2 - self.tipY * reach - dot / 2)
	self.padLabel.Position = UDim2.fromOffset(px, py + ps + 4)
	self.padLabel.Size = UDim2.fromOffset(ps, 18)
	local sx, sy, sw, sh = self:strip()
	self.stripFrame.Position = UDim2.fromOffset(sx, sy)
	self.stripFrame.Size = UDim2.fromOffset(sw, sh)
	self.stripFill.Position = UDim2.fromOffset(4, 4)
	self.stripFill.Size = UDim2.fromOffset(sw - 8, math.max(0, (sh - 8) * self.power))
	self.stripLabel.Position = UDim2.fromOffset(sx - 12, sy + sh + 4)
	self.stripLabel.Size = UDim2.fromOffset(sw + 24, 18)
end

-- Geometry ----------------------------------------------------------------------------------------------------
function Controller._point(self: any, x: number, y: number, z: number): Vector3
	local wx, wy, wz = Furniture.world(self.place, self.def, x, y, z)
	return Vector3.new(wx, wy, wz)
end

function Controller._dir(self: any, angle: number): Vector3
	local dx, dz = Cue.dirOf(angle)
	local wx, wz = Furniture.dir(self.place, dx, dz)
	return Vector3.new(wx, 0, wz)
end

-- Where a pointer (the mouse's own pixels) lies on the plane of the balls' centres: table x, z.
function Controller._tablePoint(self: any, sx: number, sy: number): (number?, number?)
	local cam = workspace.CurrentCamera
	local ray = cam:ViewportPointToRay(sx, sy)
	local plane = self:_point(0, self.tb.ballR, 0).Y
	local dy = ray.Direction.Y
	if math.abs(dy) < 1e-6 then
		return nil, nil
	end
	local k = (plane - ray.Origin.Y) / dy
	if k <= 0 then
		return nil, nil
	end
	local hit = ray.Origin + ray.Direction * k
	local x, _, z = Furniture.fromWorld(self.place, self.def, hit.X, hit.Y, hit.Z)
	return x, z
end

-- A pointer's place on the screen, in the mouse's own pixels (a finger's Position leaves out the top bar).
local function pointerOf(io: InputObject): (number, number)
	local UIS = game:GetService("UserInputService")
	if io.UserInputType == Enum.UserInputType.Touch then
		local inset = Vector2.zero
		pcall(function()
			inset = (game:GetService("GuiService"):GetGuiInset())
		end)
		return io.Position.X + inset.X, io.Position.Y + inset.Y
	end
	local m = UIS:GetMouseLocation()
	return m.X, m.Y
end

local function inRect(px: number, py: number, x: number, y: number, w: number, h: number): boolean
	return px >= x and px <= x + w and py >= y and py <= y + h
end

-- The state -----------------------------------------------------------------------------------------------------
function Controller._setSpots(self: any, flat: { number }?)
	local spots: { Spot } = {}
	local byId: { [number]: Spot } = {}
	for k = 1, #(flat or {}) - 2, 3 do
		local f = flat :: { number }
		local s = { id = f[k], x = f[k + 1], z = f[k + 2] }
		table.insert(spots, s)
		byId[s.id] = s
	end
	self.spots = spots
	self.byId = byId
	self.version += 1
end

function Controller._g(self: any): { [string]: any }?
	local view = self.view
	return view and view.game
end

-- My turn begins: nothing from before counts.
function Controller._begin(self: any)
	local g = self:_g()
	local you = self.you
	if g == nil or you == nil or self.def == nil then
		return
	end
	local mode = self.mode :: Game
	self.presses = {}
	self.charge = nil
	self.power = 0
	self.tipX, self.tipY = 0, 0
	local can = mode.strikeable(g, you)
	self.sel = can[1] or 0
	self.pocket = mode.called(g)
	self.angle = mode.firstAim(g, you, self.spots, self.sel)
	self.hand = nil
	self.previewKey = ""
	if mode.inHand(g) ~= "none" and self.byId[0] then
		self.phase = "place"
		self.hand = { x = self.byId[0].x, z = self.byId[0].z, ok = true }
	else
		self.phase = "aim"
	end
	if self.legs then
		self.legs = false
		self.ctx.controls(false)
	end
	self.ctx.sound(`{mode.game}.chalk`, 0.5)
end

-- My turn is over (or was never mine): camera and legs are my own again, unless I asked for the top view.
function Controller._end(self: any)
	self.phase = "off"
	self.presses = {}
	self.charge = nil
	self.power = 0
	self.hand = nil
	self:_hideAim()
	self.ctx.ui:meter(nil)
	self.ctx.ui:clock(nil)
	if not self.top then
		-- (let go at once, not in the next frame's drawing: see _toggleWalk)
		self:_noShot()
	end
	if not self.legs then
		self.legs = true
		self.ctx.controls(true)
	end
end

function Controller._hideAim(self: any)
	for _, p in self.parts do
		hide(p)
	end
	self.stick:hide()
	self:_layout(false)
end

-- What the latest state means for the phase (also asked each frame: a shot that has just finished playing).
function Controller._reconcile(self: any)
	local phase = self.phase
	local busy = self.rolling or (self.def ~= nil and Playback.playing(self.def.id))
	if self.live and not busy then
		if phase == "off" or phase == "watch" then
			self:_begin()
		elseif phase == "sent" and self.t - self.sentAt > Controller.SENT_WAIT then
			self.phase = "aim"
			self.power = 0
		end
	elseif not self.live then
		-- (my own shot still rolling is watched to its end)
		if phase ~= "off" and not (phase == "watch" and busy) then
			self:_end()
		end
	end
end

-- msg = the "state" payload: { view, you, rolling }.
function Controller.onState(self: any, msg: { [string]: any })
	local view = msg.view
	local mode = self.mode :: Game
	self.view = view
	self.you = msg.you
	self.rolling = msg.rolling == true
	self.live = view.phase == "playing" and mode.mine(view, msg.you)
	self.turnLeft = view.turnLeft
	self.turnLeftAt = self.t
	local g = view.game
	if g and not (self.def ~= nil and Playback.playing(self.def.id)) and self.phase ~= "sent" then
		-- (while my own shot is on its way the balls are the script's; and a ball I am carrying is mine)
		local carried = self.hand
		self:_setSpots(g.balls)
		if carried and self.byId[0] and self.phase == "place" then
			carried.x, carried.z = self.byId[0].x, self.byId[0].z
		end
	end
	if self.phase == "aim" or self.phase == "place" or self.phase == "walk" then
		if g and self.you then
			-- still my go: what I may strike and what is called may have changed
			local can = mode.strikeable(g, self.you)
			if table.find(can, self.sel) == nil then
				self.sel = can[1] or 0
			end
			if mode.called(g) ~= 0 then
				self.pocket = mode.called(g)
			end
			if self.phase == "place" and mode.inHand(g) == "none" then
				self.phase = "aim"
				self.hand = nil
			end
		end
	end
	self:_reconcile()
	self:_say()
end

function Controller.onMessage(self: any, msg: { [string]: any }, _watched: any?)
	local mode = self.mode :: Game
	if msg.kind == `{mode.game}_shot` and msg.replay == true then
		-- the winning shot played again, slowly: watched from the top of the table
		self.ctx.toast("The winning shot, again, slowly", 4)
	elseif msg.kind == `{mode.game}_shot` then
		if self.phase == "sent" or (msg.seat == self.you and self.phase ~= "off") then
			-- my own shot is on its way: watch it
			local g = self:_g()
			self.watchTop = self.top or (g ~= nil and g.broken == false)
			self.phase = "watch"
			self.watchSince = self.t
			self.charge = nil
			self.presses = {}
			self:_hideAim()
			self.ctx.ui:meter(nil)
		end
	elseif msg.kind == "event" and msg.shot ~= nil and type(msg.text) == "string" then
		-- what a shot came to (a foul in the rules' words, who is at the table): the banner is gone in a moment
		-- (the next turn's banner follows it at once), so it is said where it stays a while too
		self.ctx.toast(msg.text, 5)
	elseif msg.kind == `{mode.game}_rack` then
		if type(msg.balls) == "table" then
			self:_setSpots(msg.balls)
		end
		if self.phase == "watch" or self.phase == "sent" then
			self.phase = "off"
			self:_reconcile()
		end
	end
end

-- The server refused an input: the cue (or the ball in hand) is mine again.
function Controller.onRefused(self: any, _msg: { [string]: any })
	if self.phase == "sent" then
		self.phase = "aim"
		self.power = 0
	elseif self.phase == "place" then
		local s = self.byId[0]
		if s and self.hand then
			self.hand.x, self.hand.z, self.hand.ok = s.x, s.z, true
		end
	end
end

-- Input -----------------------------------------------------------------------------------------------------------
local TURN_PHASES: { [string]: boolean } = { aim = true, place = true, walk = true }

function Controller._toggleTop(self: any)
	self.top = not self.top
end

function Controller._toggleWalk(self: any)
	if self.phase == "aim" or self.phase == "place" then
		-- up from the shot: my own legs and camera
		if self.phase == "place" then
			self:_setDown()
		end
		self.phase = "walk"
		self.charge = nil
		self.power = 0
		self.presses = {}
		self:_hideAim()
		self.ctx.ui:meter(nil)
		-- (the camera is let go here and not in the next frame's drawing: a shot let go in a render step
		-- would have been moved once more by the shot's own step that frame)
		self.top = false
		self:_noShot()
		if not self.legs then
			self.legs = true
			self.ctx.controls(true)
		end
		self:_say()
	elseif self.phase == "walk" then
		-- down on the shot from where I stand: the line from me through the ball
		local body = self.ctx.body()
		local root = body and body.PrimaryPart
		local s = self.byId[self.sel]
		if root and s then
			local x, _, z = Furniture.fromWorld(self.place, self.def, root.Position.X, root.Position.Y, root.Position.Z)
			if (s.x - x) ^ 2 + (s.z - z) ^ 2 > 0.01 then
				self.angle = Cue.angleOf(s.x - x, s.z - z)
			end
		end
		self.phase = "aim"
		self.top = false
		self.previewKey = ""
		if self.legs then
			self.legs = false
			self.ctx.controls(false)
		end
		self:_say()
	end
end

-- The ball in hand is set down where it is (if the rules allow it there) and told to the server.
function Controller._setDown(self: any)
	local hand = self.hand
	local s = self.byId[0]
	if hand == nil or s == nil then
		return
	end
	if hand.ok and (math.abs(hand.x - s.x) > 1e-6 or math.abs(hand.z - s.z) > 1e-6) then
		s.x, s.z = hand.x, hand.z
		self.version += 1
		self.ctx.send("place", { hand.x, hand.z })
	elseif not hand.ok then
		hand.x, hand.z, hand.ok = s.x, s.z, true
	end
	hand.moved = nil
end

-- Space / A / DONE with the ball in hand: set it down and take the shot.
function Controller._confirm(self: any)
	if self.phase ~= "place" then
		return
	end
	self:_setDown()
	local mode = self.mode :: Game
	local g = self:_g()
	self.phase = "aim"
	self.hand = nil
	self.presses = {}
	if g and self.you then
		self.angle = mode.firstAim(g, self.you, self.spots, self.sel)
	end
	self.previewKey = ""
end

function Controller._carry(self: any, x: number, z: number)
	local hand = self.hand
	local g = self:_g()
	if hand == nil or g == nil then
		return
	end
	local mode = self.mode :: Game
	local tb = self.tb
	local m = tb.ballR + 0.003
	hand.x = math.clamp(x, -tb.halfW + m, tb.halfW - m)
	hand.z = math.clamp(z, -tb.halfL + m, tb.halfL - m)
	hand.ok = mode.canPlace(g, self.spots, hand.x, hand.z)
end

-- The held stroke: down starts the power rising, letting go strikes.
function Controller._hold(self: any, down: boolean)
	if down then
		if self.phase == "aim" and self.charge == nil then
			self.charge = 0
		end
	elseif self.charge ~= nil then
		local p = self.power
		self.charge = nil
		if self.phase == "aim" then
			self:_strike(p)
		end
	end
end

function Controller._strike(self: any, power: number)
	local mode = self.mode :: Game
	if self.phase ~= "aim" or power < Controller.MIN_POWER then
		self.power = 0
		self.ctx.ui:meter(nil)
		return
	end
	self.power = power
	self.phase = "sent"
	self.sentAt = self.t
	self.presses = {}
	self.ctx.ui:meter(nil)
	self.ctx.send("shoot", mode.args(self.sel, self.angle, power, self.tipX, self.tipY, self.pocket))
end

function Controller._call(self: any, pocket: number)
	local mode = self.mode :: Game
	local g = self:_g()
	if g and self.you and mode.mustCall(g, self.you) and pocket >= 1 and pocket <= #self.tb.holes then
		if pocket ~= self.pocket then
			self.pocket = pocket
			self.ctx.send("call", { pocket })
		end
	end
end

function Controller._cycle(self: any, by: number)
	local mode = self.mode :: Game
	local g = self:_g()
	if g == nil or self.you == nil then
		return
	end
	if mode.mustCall(g, self.you) then
		local n = #self.tb.holes
		-- (from no pocket called: the first one forward, the last one back)
		self:_call(if self.pocket < 1 then (if by > 0 then 1 else n) else ((self.pocket - 1 + by) % n) + 1)
		return
	end
	local can = mode.strikeable(g, self.you)
	local at = table.find(can, self.sel)
	if at and #can > 1 then
		self.sel = can[((at - 1 + by) % #can) + 1]
		self.angle = mode.firstAim(g, self.you, self.spots, self.sel)
		self.previewKey = ""
	end
end

local NUMBER_KEYS: { [string]: number } = { One = 1, Two = 2, Three = 3, Four = 4, Five = 5, Six = 6 }

function Controller._began(self: any, io: InputObject)
	local mode = self.mode :: Game
	local kind = io.UserInputType
	local key = io.KeyCode
	if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
		self:_pressed(io)
		return
	end
	if key == Enum.KeyCode.T or key == Enum.KeyCode.ButtonY then
		self:_toggleTop()
		return
	end
	if not TURN_PHASES[self.phase] then
		return
	end
	if key == Enum.KeyCode.V or key == Enum.KeyCode.ButtonX then
		self:_toggleWalk()
	elseif self.phase == "walk" then
		return
	elseif key == Enum.KeyCode.Space or key == Enum.KeyCode.ButtonR2 then
		if self.phase == "place" then
			self:_confirm()
		else
			self:_hold(true)
		end
	elseif key == Enum.KeyCode.ButtonA or key == Enum.KeyCode.Return then
		self:_confirm()
	elseif key == Enum.KeyCode.B then
		local g = self:_g()
		if self.phase == "aim" and g and mode.inHand(g) ~= "none" and self.byId[0] then
			self.phase = "place"
			self.hand = { x = self.byId[0].x, z = self.byId[0].z, ok = true }
			self.charge = nil
			self.power = 0
		elseif self.phase == "place" then
			self:_confirm()
		end
	elseif key == Enum.KeyCode.C then
		self.tipX, self.tipY = 0, 0
	elseif key == Enum.KeyCode.R or key == Enum.KeyCode.DPadRight then
		if self.phase == "aim" then
			self:_cycle(1)
		end
	elseif key == Enum.KeyCode.DPadLeft then
		if self.phase == "aim" then
			self:_cycle(-1)
		end
	elseif key == Enum.KeyCode.ButtonL1 then
		self.angle -= Controller.NUDGE
	elseif key == Enum.KeyCode.ButtonR1 then
		self.angle += Controller.NUDGE
	elseif NUMBER_KEYS[key.Name] and self.phase == "aim" then
		local n = NUMBER_KEYS[key.Name]
		local g = self:_g()
		if g and self.you and mode.mustCall(g, self.you) then
			self:_call(n)
		elseif g and self.you then
			local can = mode.strikeable(g, self.you)
			if can[n] and #can > 1 then
				self.sel = can[n]
				self.angle = mode.firstAim(g, self.you, self.spots, self.sel)
			end
		end
	end
end

-- A pointer went down: on the cue-ball picture, on the power bar, or on the table.
function Controller._pressed(self: any, io: InputObject)
	local id: any = if io.UserInputType == Enum.UserInputType.Touch then io else "mouse"
	local px, py = pointerOf(io)
	local phase = self.phase
	if phase ~= "aim" and phase ~= "place" then
		return
	end
	local press: { [string]: any } = { x0 = px, y0 = py, x = px, y = py, moved = false, kind = "table" }
	if phase == "aim" then
		local ax, ay, as = self:pad()
		local sx, sy, sw, sh = self:strip()
		if inRect(px, py, ax, ay, as, as) then
			press.kind = "tip"
			self:_tipFrom(px, py)
		elseif inRect(px, py, sx - 10, sy - 10, sw + 20, sh + 20) then
			press.kind = "strip"
			self.charge = nil
		elseif self.top then
			self:_pointAt(px, py)
		end
	else
		press.kind = "place"
		local x, z = self:_tablePoint(px, py)
		if x and z then
			self:_carry(x, z)
		end
	end
	self.presses[id] = press
end

function Controller._tipFrom(self: any, px: number, py: number)
	local ax, ay, as = self:pad()
	local dot = as * 0.16
	local reach = as / 2 - dot / 2
	self.tipX, self.tipY = Cue.clampTip((px - ax - as / 2) / reach, -(py - ay - as / 2) / reach)
end

-- The top view: the cue points from the ball at the pointer's place on the cloth.
function Controller._pointAt(self: any, px: number, py: number)
	local s = self.byId[self.sel]
	local x, z = self:_tablePoint(px, py)
	if s and x and z and ((x - s.x) ^ 2 + (z - s.z) ^ 2) > 1e-4 then
		self.angle = Cue.angleOf(x - s.x, z - s.z)
	end
end

function Controller._changed(self: any, io: InputObject)
	local kind = io.UserInputType
	if kind == Enum.UserInputType.Gamepad1 then
		if io.KeyCode == Enum.KeyCode.Thumbstick1 then
			self.stick1 = Vector2.new(io.Position.X, io.Position.Y)
		elseif io.KeyCode == Enum.KeyCode.Thumbstick2 then
			self.stick2 = Vector2.new(io.Position.X, io.Position.Y)
		end
		return
	end
	local id: any
	if kind == Enum.UserInputType.Touch then
		id = io
	elseif kind == Enum.UserInputType.MouseMovement then
		id = "mouse"
	else
		return
	end
	local press = self.presses[id]
	if press == nil then
		return
	end
	local px, py = pointerOf(io)
	local dx = px - press.x
	press.x, press.y = px, py
	if math.abs(px - press.x0) + math.abs(py - press.y0) > Controller.CLICK then
		press.moved = true
	end
	if press.kind == "tip" then
		self:_tipFrom(px, py)
	elseif press.kind == "strip" then
		local _, _, _, sh = self:strip()
		self.power = math.clamp((py - press.y0) / sh, 0, 1)
	elseif press.kind == "place" then
		local x, z = self:_tablePoint(px, py)
		if x and z then
			self:_carry(x, z)
		end
	elseif self.phase == "aim" then
		if self.top then
			self:_pointAt(px, py)
		elseif press.moved then
			local UIS = game:GetService("UserInputService")
			local fine = UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift)
			self.angle += dx * Controller.DRAG * (if fine then Controller.FINE_DRAG else 1)
		end
	end
end

function Controller._ended(self: any, io: InputObject)
	local kind = io.UserInputType
	local key = io.KeyCode
	if key == Enum.KeyCode.Space or key == Enum.KeyCode.ButtonR2 then
		self:_hold(false)
		return
	end
	local id: any
	if kind == Enum.UserInputType.Touch then
		id = io
	elseif kind == Enum.UserInputType.MouseButton1 then
		id = "mouse"
	else
		return
	end
	local press = self.presses[id]
	if press == nil then
		return
	end
	self.presses[id] = nil
	if press.kind == "strip" then
		if self.phase == "aim" then
			self:_strike(self.power)
		end
	elseif press.kind == "place" then
		if self.phase == "place" then
			self:_setDown()
		end
	elseif press.kind == "table" and not press.moved and self.phase == "aim" then
		self:_clicked(press.x, press.y)
	end
end

-- A click on the table: a pocket (when the 8 must be called) or one of my balls (when I may choose).
function Controller._clicked(self: any, px: number, py: number)
	local mode = self.mode :: Game
	local g = self:_g()
	local x, z = self:_tablePoint(px, py)
	if g == nil or self.you == nil or x == nil or z == nil then
		return
	end
	if mode.mustCall(g, self.you) then
		local best, bestD = 0, Controller.POCKET_REACH
		for i, hole in self.tb.holes do
			local d = math.sqrt((hole.x - x) ^ 2 + (hole.z - z) ^ 2)
			if d < bestD then
				best, bestD = i, d
			end
		end
		if best > 0 then
			self:_call(best)
		end
		return
	end
	local can = mode.strikeable(g, self.you)
	if #can > 1 then
		for _, id in can do
			local s = self.byId[id]
			if s and math.sqrt((s.x - x) ^ 2 + (s.z - z) ^ 2) < Controller.BALL_REACH and id ~= self.sel then
				self.sel = id
				self.angle = mode.firstAim(g, self.you, self.spots, id)
				self.previewKey = ""
			end
		end
	end
end

-- Cameras ----------------------------------------------------------------------------------------------------------
function Controller._cueCam(self: any): (CFrame, number)
	local s = self.byId[self.sel]
	local r = self.tb.ballR
	local ball = self:_point(if s then s.x else 0, r, if s then s.z else 0)
	local d = self:_dir(self.angle)
	local eye = ball - d * Controller.CAM_BACK + Vector3.new(0, Controller.CAM_UP, 0)
	return CFrame.lookAt(eye, ball + d * Controller.CAM_AHEAD), Controller.CAM_FOV
end

function Controller._topCam(self: any): (CFrame, number)
	local hw, hl = Furniture.outer(self.tb)
	local vp = workspace.CurrentCamera.ViewportSize
	local aspect = vp.X / math.max(vp.Y, 1)
	local h = math.min(Controller.TOP_H, AlleyLayout.CEILING_Y - Furniture.BED_Y - 1)
	local half = math.max(hw + 1, (hl + 1.2) / aspect)
	local fov = math.clamp(math.deg(2 * math.atan(half / h)), 20, 110)
	local centre = self:_point(0, 0, 0)
	-- the head of the table on the left of the screen, the rack on the right
	local ux, uz = Furniture.dir(self.place, -1, 0)
	return CFrame.lookAt(centre + Vector3.new(0, h, 0), centre, Vector3.new(ux, 0, uz)), fov
end

-- After the strike: up and back, over the line of the shot, the whole table in view.
function Controller._watchCam(self: any): (CFrame, number)
	if self.watchTop then
		return self:_topCam()
	end
	local _, hl = Furniture.outer(self.tb)
	local d = self:_dir(self.angle)
	local centre = self:_point(0, 0, 0)
	local eye = centre - d * (hl * 0.75 + 2.2) + Vector3.new(0, hl * 0.55 + 2.2, 0)
	return CFrame.lookAt(eye, centre + d * 0.4), 62
end

function Controller._lamp(self: any, hidden: boolean)
	if self.lampHidden == hidden then
		return
	end
	self.lampHidden = hidden
	local model = self.def and Playback.find(self.def)
	local lamp = model and model:FindFirstChild("Lamp")
	for _, d in if lamp then lamp:GetDescendants() else {} do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = if hidden then 1 else 0
		end
	end
end

function Controller._shot(self: any, cf: CFrame, fov: number, top: boolean)
	self.camUp = true
	self.ctx.camera(cf, fov)
	self:_lamp(top)
end

function Controller._noShot(self: any)
	if self.camUp then
		self.camUp = false
		self.ctx.releaseCamera()
	end
	self:_lamp(false)
end

-- Drawing ---------------------------------------------------------------------------------------------------------
local function segment(p: BasePart, a: Vector3, b: Vector3, width: number)
	local len = (b - a).Magnitude
	if len < 1e-3 then
		hide(p)
		return
	end
	p.Size = Vector3.new(width, 0.006, len)
	p.CFrame = CFrame.lookAt((a + b) / 2, b)
	show(p)
end

local function disc(p: BasePart, at: Vector3, diameter: number)
	p.Size = Vector3.new(0.012, diameter, diameter)
	p.CFrame = CFrame.new(at) * CFrame.Angles(0, 0, math.pi / 2)
	show(p)
end

function Controller._drawAim(self: any)
	local tb = self.tb
	local r = tb.ballR
	local parts = self.parts
	local s = self.byId[self.sel]
	if s == nil then
		self:_hideAim()
		return
	end
	local shown = if self.power > 0 then self.power else Controller.SET_POWER
	local key = `{self.angle}|{shown}|{self.tipX}|{self.tipY}|{self.sel}|{self.version}`
	if key ~= self.previewKey then
		self.previewKey = key
		self.preview = Cue.preview(tb, self.spots, self.sel, self.angle, shown, self.tipX, self.tipY)
	end
	local pv = self.preview
	local lift = 0.014 -- the lines lie just above the cloth
	local dx, dz = Cue.dirOf(self.angle)
	local from = self:_point(s.x + dx * r, lift, s.z + dz * r)
	if pv.kind == "none" then
		hide(parts.ghost)
		segment(parts.line, from, self:_point(pv.gx, lift, pv.gz), 0.03)
	else
		segment(parts.line, from, self:_point(pv.gx, lift, pv.gz), 0.03)
		parts.ghost.Size = Vector3.new(2 * r, 2 * r, 2 * r)
		parts.ghost.CFrame = CFrame.new(self:_point(pv.gx, r, pv.gz))
		show(parts.ghost)
	end
	if pv.kind == "ball" and pv.target >= 0 and self.byId[pv.target] and (pv.ox ~= 0 or pv.oz ~= 0) then
		local o = self.byId[pv.target]
		-- (longer for a harder hit, never long enough to read a whole pot off it)
		local len = Controller.OBJECT_LINE * math.clamp(0.4 + pv.speed / 20, 0.4, 1)
		segment(
			parts.object,
			self:_point(o.x + pv.ox * r, lift, o.z + pv.oz * r),
			self:_point(o.x + pv.ox * (r + len), lift, o.z + pv.oz * (r + len)),
			0.03
		)
	else
		hide(parts.object)
	end
	-- the struck ball's own way after the contact: three strokes through the preview's points
	local path = pv.path
	local last = self:_point(pv.gx, lift, pv.gz)
	for k, name in { "path1", "path2", "path3" } do
		local i = k * 4 - 1 -- points 2, 4, 6 of the six
		if pv.kind ~= "none" and path[i + 1] ~= nil then
			local to = self:_point(path[i], lift, path[i + 1])
			segment(parts[name], last, to, 0.024)
			last = to
		else
			hide(parts[name])
		end
	end
	-- the cue: behind the ball on the line, drawn back by the power, its tip where the picture says
	local d = self:_dir(self.angle)
	local right = Vector3.new(-d.Z, 0, d.X)
	local toward = (d * math.cos(Furniture.CUE_PITCH) - Vector3.new(0, math.sin(Furniture.CUE_PITCH), 0)).Unit
	local at = self:_point(s.x, r, s.z)
		+ right * (self.tipX * Cue.TIP_MAX * r)
		+ Vector3.new(0, self.tipY * Cue.TIP_MAX * r, 0)
	self.stick:pose(at - toward * (r + Furniture.CUE_REST + Furniture.CUE_BACK * self.power), toward, 1)
	-- the called pocket, the picked ball
	local mode = self.mode :: Game
	local g = self:_g()
	if self.pocket > 0 and tb.holes[self.pocket] and g and self.you and mode.mustCall(g, self.you) then
		local hole = tb.holes[self.pocket]
		disc(parts.ring, self:_point(hole.x, 0.03, hole.z), hole.r * 2.5)
	else
		hide(parts.ring)
	end
	if g and self.you and #mode.strikeable(g, self.you) > 1 then
		disc(parts.pick, self:_point(s.x, 0.012, s.z), r * 3.2)
	else
		hide(parts.pick)
	end
	hide(parts.spot)
end

function Controller._drawPlace(self: any)
	local parts = self.parts
	for name, p in parts do
		if name ~= "spot" then
			hide(p)
		end
	end
	self.stick:hide()
	local hand = self.hand
	if hand == nil then
		hide(parts.spot)
		return
	end
	parts.spot.Color = if hand.ok then Color3.fromRGB(120, 255, 140) else Color3.fromRGB(255, 80, 70)
	disc(parts.spot, self:_point(hand.x, 0.012, hand.z), self.tb.ballR * 3.4)
	Playback.put(self.place, self.def, self.tb, 0, hand.x, hand.z)
end

-- I stand behind the shot, on the ring round the table (my legs are the table's while I aim).
function Controller._standAt(self: any, dt: number)
	local body = self.ctx.body()
	local root = body and body.PrimaryPart
	local s = self.byId[self.sel]
	if root == nil or s == nil then
		return
	end
	local sx, sz = Furniture.stand(self.tb, s.x, s.z, self.angle)
	local feet = self:_point(sx, 0, sz)
	local target = Vector3.new(feet.X, root.Position.Y, feet.Z)
	local pos = root.Position:Lerp(target, math.min(1, dt * 10))
	local ball = self:_point(s.x, 0, s.z)
	local look = Vector3.new(ball.X, pos.Y, ball.Z)
	if (look - pos).Magnitude > 0.05 then
		root.CFrame = CFrame.lookAt(pos, look)
	end
	root.AssemblyLinearVelocity = Vector3.zero
end

-- Words -----------------------------------------------------------------------------------------------------------
function Controller._say(self: any)
	local view = self.view
	if view == nil then
		return
	end
	local mode = self.mode :: Game
	local UIS = game:GetService("UserInputService")
	local touch = UIS.TouchEnabled and not UIS.MouseEnabled
	local what = mode.say(view, self.you, self.phase)
	local how = ""
	if self.phase == "aim" then
		how = if touch
			then " Drag to aim, pull the bar (or hold the button) and let go to strike."
			else " Drag or A/D to aim (Shift: fine), pull the bar or hold Space to strike. T: top view."
	elseif self.phase == "place" then
		how = if touch
			then " Drag the cue ball where you want it, then DONE."
			else " Ball in hand: drag the cue ball (or WASD), then Space."
	elseif self.phase == "walk" then
		how = " Walk round the table; V takes the shot from where you stand."
	end
	self.saidPhase = self.phase
	self.ctx.ui:status(what .. how)
end

-- A frame -----------------------------------------------------------------------------------------------------------
function Controller._frame(self: any, dt: number)
	local ctx = self.ctx
	self.t += dt
	if self.def == nil then
		return
	end
	local UIS = game:GetService("UserInputService")
	local id = self.def.id
	local phase = self.phase
	-- a shot of mine that has finished playing, or a strike the server never answered
	if phase == "watch" or phase == "sent" or (phase == "off" and self.live) then
		self:_reconcile()
		if self.phase ~= phase then
			self:_say()
		end
		phase = self.phase
	end
	if phase == "aim" then
		local fine = UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift)
		local turn = 0
		if UIS:IsKeyDown(Enum.KeyCode.D) or UIS:IsKeyDown(Enum.KeyCode.Right) then
			turn += 1
		end
		if UIS:IsKeyDown(Enum.KeyCode.A) or UIS:IsKeyDown(Enum.KeyCode.Left) then
			turn -= 1
		end
		if math.abs(self.stick1.X) > 0.15 then
			turn += self.stick1.X
		end
		if turn ~= 0 then
			self.angle += turn * dt * (if fine then Controller.FINE else Controller.TURN)
		end
		local tx, ty = 0, 0
		if UIS:IsKeyDown(Enum.KeyCode.W) or UIS:IsKeyDown(Enum.KeyCode.Up) then
			ty += 1
		end
		if UIS:IsKeyDown(Enum.KeyCode.S) or UIS:IsKeyDown(Enum.KeyCode.Down) then
			ty -= 1
		end
		if UIS:IsKeyDown(Enum.KeyCode.X) then
			tx += 1
		end
		if UIS:IsKeyDown(Enum.KeyCode.Z) then
			tx -= 1
		end
		if tx ~= 0 or ty ~= 0 then
			self.tipX, self.tipY =
				Cue.clampTip(self.tipX + tx * dt * Controller.TIP_RATE, self.tipY + ty * dt * Controller.TIP_RATE)
		end
		if self.stick2.Magnitude > 0.15 then
			self.tipX, self.tipY = Cue.clampTip(self.stick2.X, self.stick2.Y)
		end
		-- the held stroke: up once, and back down to nothing
		if self.charge ~= nil then
			self.charge += dt
			local u = self.charge / Controller.RISE
			if u >= 2 then
				self.charge = nil
				self.power = 0
				ctx.ui:meter(nil)
			else
				self.power = if u <= 1 then u else 2 - u
			end
		end
		if self.power > 0 then
			ctx.ui:meter(self.power, nil, "Let go to strike")
		elseif self.charge == nil then
			ctx.ui:meter(nil)
		end
	elseif phase == "place" then
		-- WASD and the D-pad carry the ball as the top view shows it: up the screen is across the table
		local mx, mz = 0, 0
		if UIS:IsKeyDown(Enum.KeyCode.W) or UIS:IsKeyDown(Enum.KeyCode.DPadUp) then
			mx -= 1
		end
		if UIS:IsKeyDown(Enum.KeyCode.S) or UIS:IsKeyDown(Enum.KeyCode.DPadDown) then
			mx += 1
		end
		if UIS:IsKeyDown(Enum.KeyCode.D) or UIS:IsKeyDown(Enum.KeyCode.DPadRight) then
			mz += 1
		end
		if UIS:IsKeyDown(Enum.KeyCode.A) or UIS:IsKeyDown(Enum.KeyCode.DPadLeft) then
			mz -= 1
		end
		if self.stick1.Magnitude > 0.2 then
			mx -= self.stick1.Y
			mz += self.stick1.X
		end
		local hand = self.hand
		if hand and (mx ~= 0 or mz ~= 0) then
			self:_carry(hand.x + mx * dt * Controller.PLACE_RATE, hand.z + mz * dt * Controller.PLACE_RATE)
			hand.moved = self.t
		elseif hand and hand.moved and self.t - hand.moved > 0.35 and next(self.presses) == nil then
			-- the keys have been let go: the ball is set down there
			self:_setDown()
		end
	end
	-- the status line follows the phase (set down, struck, up from the shot), not only the server's states
	if self.view ~= nil and self.saidPhase ~= phase then
		self:_say()
	end
	-- what is drawn, where I stand, what the camera shows
	if phase == "aim" then
		self:_layout(true)
		self:_drawAim()
		self:_standAt(dt)
		if self.top then
			local cf, fov = self:_topCam()
			self:_shot(cf, fov, true)
		else
			local cf, fov = self:_cueCam()
			self:_shot(cf, fov, false)
		end
	elseif phase == "place" then
		self:_layout(false)
		self:_drawPlace()
		self:_standAt(dt)
		local cf, fov = self:_topCam()
		self:_shot(cf, fov, true)
	elseif phase == "sent" then
		-- the cue stays drawn back until the table answers
		self:_layout(false)
		if self.top then
			local cf, fov = self:_topCam()
			self:_shot(cf, fov, true)
		else
			local cf, fov = self:_cueCam()
			self:_shot(cf, fov, false)
		end
	elseif phase == "watch" then
		local cf, fov = self:_watchCam()
		self:_shot(cf, fov, self.watchTop)
	elseif self.top and Playback.find(self.def) ~= nil then
		-- not my go (or walking): the top view to watch from, if I asked for it
		local cf, fov = self:_topCam()
		self:_shot(cf, fov, true)
	else
		self:_noShot()
	end
	-- the turn clock, counted down between the server's once-a-second reports
	if phase == "aim" or phase == "place" or phase == "walk" then
		local left = if self.turnLeft then math.max(0, self.turnLeft - (self.t - self.turnLeftAt)) else nil
		local warning: string? = nil
		if left ~= nil and left <= Controller.WARN_AT then
			local secs = math.max(0, math.ceil(left))
			warning = `Play within {secs} second{if secs == 1 then "" else "s"} or the shot is lost`
		end
		ctx.ui:clock(left, warning)
	elseif Playback.playing(id) then
		ctx.ui:clock(nil)
	end
end

function Controller.stop(self: any)
	if Controller.live[self.ctx.station] == self then
		Controller.live[self.ctx.station] = nil
	end
	for _, c in self.conns do
		c:Disconnect()
	end
	table.clear(self.conns)
	for _, p in self.parts do
		p:Destroy()
	end
	self.stick:destroy()
	self.gui:Destroy()
	self:_lamp(false)
	self.phase = "off"
	self.camUp = false -- (MinigameClient's close() gives the camera and the legs back itself)
	self.legs = true
	self.presses = {}
	self.charge = nil
	local ui = self.ctx.ui
	ui:meter(nil)
	ui:clock(nil)
end

return Controller
