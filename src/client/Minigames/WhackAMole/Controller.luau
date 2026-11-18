--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.WhackAMole.Controller
-- The player at the whack-a-mole cabinet. The camera frames the deck from above and behind the player's head
-- with the sign's SCORE and TIME windows in view (Shared/Minigames/WhackAMole/Layout.camera: the field of view
-- is worked out for this screen's shape, so the five holes and both windows are on any screen from 4:3 to a
-- wide phone); the body stands at the cabinet's front, facing it; the legs are the game's while it is open.
-- STRIKING: a click or a tap on a mole (a ray from the camera through the point, tested against each mole's head
-- and body as they stand on this screen, the nearest taken), or anywhere on a hole's mouth (a hole with nothing
-- in it is a miss, as on his deck); keys 1-5 and the keypad's (1, 2, 3 the back row from the left, 4, 5 the
-- front), and on a gamepad the D-pad's left, up and right for the back row and the two shoulder buttons (LB, RB;
-- the triggers too) for the front: the deck's own shape under the thumbs, shown on the card and the help.
-- Each strike is one message, "whack" { hole, the shared clock's time }, and the mallet swings at once on this
-- screen (Client/Minigames/WhackAMole/Cabinet.swing; a mole this screen sees can be hit drops as it is struck);
-- the server judges it and its word wins. Strikes closer together than Round.MIN_GAP are not sent (one mallet;
-- it also keeps a mashing hand under the wire's 20 a second), nor any before GO (the sign says READY).
-- Q, gamepad B and the Leave button leave (the framework's bar: Leave, and Play again at the end; Space or
-- gamepad A there too).
-- The main client's rules (MinigameClient's header): the camera through ctx.camera / ctx.releaseCamera, the
-- cursor MinigameUI's (its buttons are up in every phase), everything connected here disconnected in stop().
-- Interface: new(ctx) -> Controller { onState, onMessage, onRefused, stop }; HELP; KEYS (KeyCode name -> hole);
--   pick(cab, ray origin, ray direction) -> hole? (the mole or hole a ray meets); holeAt(cab, x, y) -> hole?
--   (the hole under a point of the screen); current (the open controller: .cab, .phase, .sent, .over)

local Import = require("../../Import")
local Layout =
	Import.shared("Minigames/WhackAMole/Layout") :: typeof(require("../../../shared/Minigames/WhackAMole/Layout"))
local Round =
	Import.shared("Minigames/WhackAMole/Round") :: typeof(require("../../../shared/Minigames/WhackAMole/Round"))
local InputMap = require("../../Input/InputMap")
local ClientGame = require("../ClientGame")
local Cabinet = require("./Cabinet")

local Controller = {}

Controller.HELP = {
	how = {
		"Whack each mole as it pops up: +10 a hit, -2 a miss (never below zero). 45 seconds, and it speeds up.",
	},
	keys = {
		"Click or tap a mole",
		"1 2 3  the back row, 4 5  the front row",
		"Gamepad  D-pad left / up / right: back row; LB / RB: front row",
		"Q / gamepad B  leave",
	},
}

-- KeyCode name -> hole
Controller.KEYS = {
	One = 1,
	Two = 2,
	Three = 3,
	Four = 4,
	Five = 5,
	KeypadOne = 1,
	KeypadTwo = 2,
	KeypadThree = 3,
	KeypadFour = 4,
	KeypadFive = 5,
	DPadLeft = 1,
	DPadUp = 2,
	DPadRight = 3,
	ButtonL1 = 4,
	ButtonR1 = 5,
	ButtonL2 = 4,
	ButtonR2 = 5,
} :: { [string]: number }

Controller.current = nil :: any

-- the nearest point where a ray meets an upright spheroid (centre, radius across, radius up), or nil
local function meet(o: Vector3, d: Vector3, c: Vector3, r: number, ry: number): number?
	-- scale the vertical so the spheroid is a sphere of radius r
	local k = r / ry
	local ox, oy, oz = o.X - c.X, (o.Y - c.Y) * k, o.Z - c.Z
	local dx, dy, dz = d.X, d.Y * k, d.Z
	local a = dx * dx + dy * dy + dz * dz
	local b = 2 * (ox * dx + oy * dy + oz * dz)
	local q = ox * ox + oy * oy + oz * oz - r * r
	local disc = b * b - 4 * a * q
	if disc < 0 or a <= 0 then
		return nil
	end
	local t = (-b - math.sqrt(disc)) / (2 * a)
	return if t > 0 then t else nil
end

-- pick(cab, origin, direction): the hole whose mole (as it stands on this screen) the ray meets first, else the
-- hole whose mouth it passes through at the deck's face; nil if neither
function Controller.pick(cab: any, origin: Vector3, dir: Vector3): number?
	local M = Layout.MOLE
	local best, bestT = nil :: number?, math.huge
	for hole = 1, Round.HOLES do
		local h = Cabinet.heightOf(cab, hole)
		if h <= 0 then
			continue
		end
		local hu, hw = Layout.HOLES[hole][1], Layout.HOLES[hole][2]
		local up = M.pop * h
		-- (a little larger than drawn: a finger or a quick click near the edge of a head counts)
		for _, part in
			{
				{ M.headV + up, M.headR * 1.15, M.headHalfV * 1.15 },
				{ M.bodyV + up, M.bodyR * 1.1, M.bodyHalfV },
			}
		do
			if part[1] + part[3] < Layout.DECK.top then
				continue -- (below the deck: hidden)
			end
			local c = Cabinet.cframe(cab, hu, part[1], hw).Position
			local t = meet(origin, dir.Unit, c, part[2], part[3])
			if t and t < bestT then
				best, bestT = hole, t
			end
		end
	end
	if best then
		return best
	end
	-- the deck's face: which hole's mouth (with its brass lip) the ray goes through
	local top = Cabinet.cframe(cab, 0, Layout.DECK.top, 0)
	local n = top.UpVector
	local denom = dir:Dot(n)
	if math.abs(denom) < 1e-6 then
		return nil
	end
	local t = (top.Position - origin):Dot(n) / denom
	if t <= 0 then
		return nil
	end
	local p = top:PointToObjectSpace(origin + dir * t)
	-- (object space of the cabinet frame: X = u, Z = -w)
	for hole = 1, Round.HOLES do
		local h = Layout.HOLES[hole]
		local du, dw = p.X - h[1], -p.Z - h[2]
		if du * du + dw * dw <= (Layout.DECK.lipR + Layout.DECK.lipTube) ^ 2 then
			return hole
		end
	end
	return nil
end

function Controller.holeAt(cab: any, x: number, y: number): number?
	local cam = workspace.CurrentCamera
	if cam == nil then
		return nil
	end
	local ray = cam:ViewportPointToRay(x, y)
	return Controller.pick(cab, ray.Origin, ray.Direction)
end

function Controller.new(ctx: ClientGame.Ctx): ClientGame.Controller
	local UIS = game:GetService("UserInputService")
	local place = ctx.place :: any
	local cab = Cabinet.get(ctx.station, place)
	local self: any = {
		ctx = ctx,
		cab = cab,
		phase = "",
		camOn = false,
		over = nil, -- this player's place on the board, best and the board, at the end (the server's state)
		sentAt = -math.huge, -- shared-clock time of the last strike sent
		sent = 0, -- strikes sent (for the specs)
		asked = {}, -- verb -> true while a start, an again or a leave is on its way
		conns = {},
		stood = false,
		aspect = 0,
	}
	Controller.current = self
	Cabinet.take(cab)
	ctx.controls(false)

	local function setCamera(snap: boolean)
		local cam = workspace.CurrentCamera
		local size = cam and cam.ViewportSize
		local aspect = if size and size.Y > 0 then size.X / size.Y else 16 / 9
		self.aspect = aspect
		local eye, look, fov = Layout.camera(aspect)
		local e = Cabinet.cframe(cab, eye[1], eye[2], eye[3]).Position
		local l = Cabinet.cframe(cab, look[1], look[2], look[3]).Position
		ctx.camera(CFrame.lookAt(e, l), fov, snap)
	end

	-- the body at the cabinet's front, facing the deck (once: the legs are the game's while it is open)
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
		local at = Cabinet.cframe(cab, Layout.STAND.u, 0, Layout.STAND.w).Position
		local facing = Cabinet.cframe(cab, 0, 0, 0).Position
		local y = root.Position.Y
		root.CFrame = CFrame.lookAt(Vector3.new(at.X, y, at.Z), Vector3.new(facing.X, y, facing.Z))
		root.AssemblyLinearVelocity = Vector3.zero
	end

	local function ask(verb: string)
		if self.asked[verb] then
			return
		end
		self.asked[verb] = true
		ctx.send(verb)
	end

	local function strike(hole: number?)
		if hole == nil or self.phase ~= "playing" then
			return
		end
		local t = Cabinet.roundTime(cab)
		if t == nil or t < 0 or cab.done then
			return -- (the sign says READY: nothing is sent before GO)
		end
		local at = ctx.stamp()
		if at - self.sentAt < Round.MIN_GAP then
			return
		end
		self.sentAt = at
		self.sent += 1
		ctx.send("whack", { hole, at })
		Cabinet.swing(cab, hole, at)
	end

	table.insert(
		self.conns,
		UIS.InputBegan:Connect(function(io: InputObject, processed: boolean)
			if InputMap.ignore(io, processed) then
				return
			end
			local kind = io.UserInputType
			if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
				strike(Controller.holeAt(cab, io.Position.X, io.Position.Y))
				return
			end
			local name = io.KeyCode.Name
			local hole = Controller.KEYS[name]
			if hole then
				strike(hole)
			elseif (name == "Space" or name == "ButtonA") and self.phase == "done" then
				ask("again")
			end
		end)
	)
	-- a window that changes shape (a phone turned, a window resized) is framed again
	local cam = workspace.CurrentCamera
	if cam then
		local ok, sig = pcall(function()
			return cam:GetPropertyChangedSignal("ViewportSize")
		end)
		if ok and sig then
			table.insert(
				self.conns,
				sig:Connect(function()
					if self.phase ~= "" then
						setCamera(false)
					end
				end)
			)
		end
	end

	function self.onState(_self: any, msg: { [string]: any })
		local view = msg.view or {}
		local phase = view.phase or ""
		if type(msg.place) == "number" then
			self.over = { place = msg.place, best = msg.best, newBest = msg.newBest, board = msg.board }
		elseif phase ~= "done" then
			self.over = nil
		end
		if type(msg.start) == "number" and type(msg.g) == "number" and cab.g ~= msg.g then
			-- (the round's own message has not come: the state carries enough to draw it)
			Cabinet.round(cab, { g = msg.g, start = msg.start, score = view.game and view.game.score or 0 })
		end
		if phase ~= self.phase then
			self.phase = phase
			table.clear(self.asked)
		end
		if phase == "playing" or phase == "done" then
			stand()
			setCamera(not self.camOn)
			self.camOn = true
		end
	end

	function self.onMessage(_self: any, _msg: { [string]: any }, _watched: any?) end

	function self.onRefused(_self: any, _msg: { [string]: any })
		table.clear(self.asked)
	end

	function self.stop(_self: any)
		for _, c in self.conns do
			c:Disconnect()
		end
		table.clear(self.conns)
		Cabinet.release(cab)
		ctx.controls(true)
		if self.camOn then
			self.camOn = false
			ctx.releaseCamera()
		end
		if Controller.current == self then
			Controller.current = nil
		end
	end

	return self
end

return Controller
