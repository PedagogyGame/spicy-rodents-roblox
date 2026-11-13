--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.Paintball.World
-- The show, drawn (checklist PB-4, PB-8; the rating: cartoon paint, toy markers, a raised hand): the
-- Instances for what ShowCore holds, for anyone in the audience. Everything it makes is local to this
-- screen, anchored, and neither collides nor answers a raycast, and lives in one Folder under the
-- camera, so stop() leaves nothing behind.
--   puppets  one blocky figure per shown slot (legs, torso in the team's colour, head with goggles, a
--            toy marker along its look, a name tag), standing where the core drew it and sunk with its
--            crouch; see-through while it cannot be hit; a hand straight up when it is tagged out
--   balls    a small bright ball in the team's colour for every ball in flight
--   splats   the two pools: a flat blot on the wall's face, and blots that ride on a puppet; three
--            sizes and two shapes picked from the ball's id, the same on every screen
--   puffs    a quarter-second burst where your own ball met a puppet
--   bodies   the replicated REAL bodies of the people in the match are hidden on this screen
--            (LocalTransparencyModifier on the body whose DriverUserId attribute is a slot's `user`),
--            and shown again when their owner leaves the roster or the show ends
--   sounds   the core's cues, played through the minigames' own cue layer
--   the ear  the core is told where the camera is, so its cues are placed in space
-- Interface: new(show, tuning?) -> World { step(dt), stop(), folder }; counts() for a spec

local Import = require("../../Import")
local ArenaModule: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Arena)) =
	Import.shared("Minigames/Paintball/Arena")
local Body: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Body)) =
	Import.shared("Minigames/Paintball/Body")
local Contract: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Contract)) =
	Import.shared("Minigames/Paintball/Contract")
local Wire: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Wire)) =
	Import.shared("Minigames/Paintball/Wire")
local MinigameSounds = require("../MinigameSounds")
local ShowCore = require("./ShowCore")
local Tuning = require("./Tuning")

type Place = typeof(ArenaModule.T.Place)

export type World = {
	folder: Instance,
	step: (self: World, dt: number) -> (),
	stop: (self: World) -> (),
	counts: (self: World) -> { puppets: number, balls: number, splats: number, hidden: number },
}

local World = {}

local BIT = Wire.BIT
local NEUTRAL = { 150, 150, 160 }
-- the figure, in studs: half widths and depths of its three blocks
local LEGS = { 0.7, 0.45 }
local TORSO = { 1.0, 0.55 }
local HEAD = 0.6
local HIDE_EVERY = 0.5 -- seconds between two looks for real bodies to hide (they stream in)

local function teamColor(team: number): Color3
	local t = Contract.TEAMS[team]
	local c = if t then t.color else NEUTRAL
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function part(name: string, size: Vector3, color: Color3, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.Color = color
	p.Parent = parent
	return p
end

type Figure = {
	model: Model,
	legs: Part,
	torso: Part,
	head: Part,
	goggles: Part,
	marker: Part,
	hand: Part,
	tag: TextLabel,
	team: number,
	name: string,
	crouch: number,
	faded: boolean,
}

function World.new(show: ShowCore.Show, tuning: typeof(Tuning.T)?): World
	local tune = tuning or Tuning
	local splatSizes = { tune.splatSmall, tune.splatMid, tune.splatBig }
	local camera = workspace.CurrentCamera
	local folder = Instance.new("Folder")
	folder.Name = "PaintballShow"
	folder.Parent = camera

	local figures: { [number]: Figure } = {}
	local balls: { [number]: Part } = {}
	local wallSplats: { [number]: Part } = {}
	local bodySplats: { [number]: { [number]: Part } } = {}
	local puffs: { { part: Part, age: number } } = {}
	local hidden: { [Instance]: boolean } = {}
	local drawnVersion = -1
	local hideAcc = HIDE_EVERY

	local function frame(): Place?
		return show.frame
	end

	local function worldCF(place: Place, x: number, y: number, z: number, yaw: number): CFrame
		local wx, wy, wz = ArenaModule.toWorld(place, x, y, z)
		return CFrame.new(wx, wy, wz) * CFrame.Angles(0, ArenaModule.yawToWorld(place, yaw), 0)
	end

	local function figure(id: number, team: number, name: string): Figure
		local model = Instance.new("Model")
		model.Name = `Puppet{id}`
		local color = teamColor(team)
		local dark = Color3.fromRGB(46, 48, 58)
		local fig: Figure = {
			model = model,
			legs = part("Legs", Vector3.new(1, 1, 1), dark, model),
			torso = part("Torso", Vector3.new(1, 1, 1), color, model),
			head = part("Head", Vector3.new(HEAD * 2, HEAD * 2, HEAD * 2), Color3.fromRGB(232, 222, 204), model),
			goggles = part("Goggles", Vector3.new(HEAD * 2 + 0.1, 0.4, 0.3), dark, model),
			marker = part("Marker", Vector3.new(0.3, 0.4, 1.8), Color3.fromRGB(70, 200, 90), model),
			hand = part("Hand", Vector3.new(0.4, 2.2, 0.4), color, model),
			tag = Instance.new("TextLabel"),
			team = team,
			name = name,
			crouch = -1,
			faded = false,
		}
		local board = Instance.new("BillboardGui")
		board.Name = "NameTag"
		board.Size = UDim2.fromOffset(160, 26)
		board.StudsOffset = Vector3.new(0, 1.4, 0)
		board.MaxDistance = tune.nameTagFar
		board.Adornee = fig.head
		board.Parent = fig.head
		fig.tag.BackgroundTransparency = 1
		fig.tag.Size = UDim2.fromScale(1, 1)
		fig.tag.Font = Enum.Font.GothamBold
		fig.tag.TextScaled = true
		fig.tag.TextStrokeTransparency = 0.4
		fig.tag.TextColor3 = color
		fig.tag.Text = name
		fig.tag.Parent = board
		return fig
	end

	local function drawPuppets(place: Place)
		for id, p in show.puppets do
			local fig = figures[id]
			if not p.shown then
				if fig and fig.model.Parent ~= nil then
					fig.model.Parent = nil
				end
				continue
			end
			if fig == nil then
				fig = figure(id, p.team, p.name)
				figures[id] = fig
			end
			if fig.team ~= p.team or fig.name ~= p.name then
				fig.team, fig.name = p.team, p.name
				local color = teamColor(p.team)
				fig.torso.Color, fig.hand.Color = color, color
				fig.tag.TextColor3 = color
				fig.tag.Text = p.name
			end
			local top = Body.top(p.crouch)
			if math.abs(fig.crouch - p.crouch) > 1e-3 then
				fig.crouch = p.crouch
				fig.legs.Size = Vector3.new(LEGS[1] * 2, top * 0.45, LEGS[2] * 2)
				fig.torso.Size = Vector3.new(TORSO[1] * 2, top * 0.35, TORSO[2] * 2)
			end
			-- it cannot be hit (protected, in its own room, or out): see-through says so before you fire
			local faded = Wire.has(p.bits, BIT.safe) or Wire.has(p.bits, BIT.out)
			if faded ~= fig.faded then
				fig.faded = faded
				local a = if faded then 0.55 else 0
				for _, piece in { fig.legs, fig.torso, fig.head, fig.goggles, fig.marker, fig.hand } do
					piece.Transparency = a
				end
			end
			local base = worldCF(place, p.x, p.y, p.z, p.yaw)
			local headY = top - HEAD
			fig.legs.CFrame = base * CFrame.new(0, top * 0.225, 0)
			fig.torso.CFrame = base * CFrame.new(0, top * 0.625, 0)
			fig.head.CFrame = base * CFrame.new(0, headY, 0)
			fig.goggles.CFrame = base * CFrame.new(0, headY + 0.1, -HEAD + 0.05)
			-- the toy marker: at the right shoulder along the look; down while sprinting; gone when out
			local tip = if Wire.has(p.bits, BIT.sprint) then -0.9 else p.pitch
			fig.marker.CFrame = base
				* CFrame.new(0.75, top * 0.7, -0.3)
				* CFrame.Angles(tip, 0, 0)
				* CFrame.new(0, 0, -0.9)
			if p.hand then
				fig.hand.CFrame = base * CFrame.new(-TORSO[1] - 0.2, top * 0.8 + 1.1, 0)
				fig.hand.Parent = fig.model
				fig.marker.Parent = nil
			else
				fig.hand.Parent = nil
				fig.marker.Parent = fig.model
			end
			if fig.model.Parent == nil then
				fig.model.Parent = folder
			end
		end
		for id, fig in figures do
			if show.puppets[id] == nil then
				fig.model:Destroy()
				figures[id] = nil
			end
		end
	end

	local function drawBalls(place: Place)
		local seen: { [number]: boolean } = {}
		for _, ball in show.balls do
			if not ball.born then
				continue
			end
			seen[ball.key] = true
			local had: Part? = balls[ball.key]
			local p: Part
			if had == nil then
				local d = Contract.Rules.ballRadius * 2
				p = part("Ball", Vector3.new(d, d, d), teamColor(ball.team), folder)
				p.Shape = Enum.PartType.Ball
				p.Material = Enum.Material.Neon
				balls[ball.key] = p
			else
				p = had
			end
			local wx, wy, wz = ArenaModule.toWorld(place, ball.x, ball.y, ball.z)
			p.CFrame = CFrame.new(wx, wy, wz)
		end
		for key, p in balls do
			if not seen[key] then
				p:Destroy()
				balls[key] = nil
			end
		end
	end

	-- a blot: its size and shape from the ball's id, so every screen draws the same one
	local function blot(splat: ShowCore.Splat): Part
		local pick = (splat.ball + splat.by * 7) % 6
		local d = splatSizes[pick % 3 + 1]
		local p = part("Splat", Vector3.new(0.08, d, if pick >= 3 then d * 0.7 else d), teamColor(splat.team), folder)
		p.Shape = Enum.PartType.Cylinder
		return p
	end

	local function drawWalls(place: Place)
		local seen: { [number]: boolean } = {}
		for _, s in show.walls do
			seen[s.key] = true
			local had: Part? = wallSplats[s.key]
			if had == nil then
				local p = blot(s)
				local nx, ny, nz = Wire.normalOf(s.face)
				local wx, wy, wz = ArenaModule.toWorld(place, s.x + nx * 0.04, s.y + ny * 0.04, s.z + nz * 0.04)
				local dx, dy, dz = ArenaModule.dirToWorld(place, nx, ny, nz)
				local at = Vector3.new(wx, wy, wz)
				local normal = Vector3.new(dx, dy, dz)
				-- a cylinder's flat faces look along its own X: turn X onto the wall's normal
				local up = if math.abs(dy) > 0.9 then Vector3.new(1, 0, 0) else Vector3.new(0, 1, 0)
				local cf = if normal.Magnitude > 0.5
					then CFrame.lookAt(at, at + normal, up) * CFrame.Angles(0, math.pi / 2, 0)
					else CFrame.new(at)
				p.CFrame = cf * CFrame.Angles((s.ball % 12) * math.pi / 6, 0, 0)
				wallSplats[s.key] = p
			end
		end
		for key, p in wallSplats do
			if not seen[key] then
				p:Destroy()
				wallSplats[key] = nil
			end
		end
	end

	local function syncBodySplats()
		for id, list in show.bodies do
			local parts = bodySplats[id]
			if parts == nil then
				parts = {}
				bodySplats[id] = parts
			end
			local seen: { [number]: boolean } = {}
			for _, s in list do
				seen[s.key] = true
				local had: Part? = parts[s.key]
				if had == nil then
					local p = blot(s)
					p.Size = Vector3.new(0.08, p.Size.Y * tune.splatOnBody, p.Size.Z * tune.splatOnBody)
					p.Parent = nil
					parts[s.key] = p
				end
			end
			for key, p in parts do
				if not seen[key] then
					p:Destroy()
					parts[key] = nil
				end
			end
		end
		for id, parts in bodySplats do
			if show.bodies[id] == nil then
				for _, p in parts do
					p:Destroy()
				end
				bodySplats[id] = nil
			end
		end
	end

	-- a body's paint rides on its puppet: the offset in the body's frame, pulled onto the drawn figure
	local function rideBodySplats(place: Place)
		for id, list in show.bodies do
			local parts = bodySplats[id]
			local p = show.puppets[id]
			local on = p ~= nil and p.shown
			for _, s in list do
				local piece: Part? = if parts then parts[s.key] else nil
				if piece == nil then
					continue
				end
				if not on or p == nil then
					if piece.Parent ~= nil then
						piece.Parent = nil
					end
					continue
				end
				local top = Body.top(p.crouch)
				local ly = math.clamp(s.y, 0.2, top - 0.1)
				local half = if Body.partAt(ly, p.crouch) == 1
					then LEGS
					elseif Body.partAt(ly, p.crouch) == 2 then TORSO
					else { HEAD, HEAD }
				-- onto the nearest face of the block it struck
				local lx, lz = s.x, s.z
				local k = math.max(math.abs(lx) / half[1], math.abs(lz) / half[2], 1e-6)
				lx, lz = lx / k, lz / k
				local out = if math.abs(lx) / half[1] >= math.abs(lz) / half[2]
					then Vector3.new(if lx >= 0 then 1 else -1, 0, 0)
					else Vector3.new(0, 0, if lz >= 0 then 1 else -1)
				local base = worldCF(place, p.x, p.y, p.z, p.yaw)
				local at = base * Vector3.new(lx + out.X * 0.05, ly, lz + out.Z * 0.05)
				local normal = base:VectorToWorldSpace(out)
				piece.CFrame = CFrame.lookAt(at, at + normal) * CFrame.Angles(0, math.pi / 2, 0)
				if piece.Parent == nil then
					piece.Parent = folder
				end
			end
		end
	end

	local function drawPuffs(place: Place, dt: number)
		for _, puff in show.puffs do
			local p = part("Puff", Vector3.new(0.8, 0.8, 0.8), teamColor(puff.team), folder)
			p.Shape = Enum.PartType.Ball
			p.Transparency = 0.25
			local wx, wy, wz = ArenaModule.toWorld(place, puff.x, puff.y, puff.z)
			p.CFrame = CFrame.new(wx, wy, wz)
			table.insert(puffs, { part = p, age = 0 })
		end
		table.clear(show.puffs)
		for i = #puffs, 1, -1 do
			local puff = puffs[i]
			puff.age += dt
			local f = puff.age / tune.puffSecs
			if f >= 1 then
				puff.part:Destroy()
				table.remove(puffs, i)
			else
				local d = 0.8 + 1.6 * f
				puff.part.Size = Vector3.new(d, d, d)
				puff.part.Transparency = 0.25 + 0.75 * f
			end
		end
	end

	local function setHidden(body: Instance, on: boolean)
		for _, d in body:GetDescendants() do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = if on then 1 else 0
			end
		end
	end

	-- The people in the match are drawn as puppets: their replicated bodies are not drawn as well.
	local function hideBodies()
		local users: { [number]: boolean } = {}
		for _, slot in show.slots do
			if slot.user ~= 0 then
				users[slot.user] = true
			end
		end
		local mine = game:GetService("Players").LocalPlayer.UserId
		local want: { [Instance]: boolean } = {}
		local bodies = workspace:FindFirstChild("Bodies")
		for _, body in if bodies then bodies:GetChildren() else {} do
			local driver = body:GetAttribute("DriverUserId")
			-- (your own body is the stock first-person camera's to hide)
			if type(driver) == "number" and users[driver] and driver ~= mine then
				want[body] = true
			end
		end
		for body in want do
			hidden[body] = true
			setHidden(body, true) -- (again each time: parts stream in after the model)
		end
		for body in hidden do
			if not want[body] then
				hidden[body] = nil
				if body.Parent ~= nil then
					setHidden(body, false)
				end
			end
		end
	end

	local world = { folder = folder } :: World

	function world.step(_self: World, dt: number)
		local place = frame()
		-- the ear: where the camera is, in the arena's frame
		if place then
			local at = camera.CFrame.Position
			local x, y, z = ArenaModule.toLocal(place, at.X, at.Y, at.Z)
			show.listener = { x = x, y = y, z = z }
		end
		for _, cue in show.cues do
			MinigameSounds.play(cue.cue, cue.volume)
		end
		table.clear(show.cues)
		hideAcc += dt
		if hideAcc >= HIDE_EVERY then
			hideAcc = 0
			hideBodies()
		end
		if place == nil then
			return
		end
		drawPuppets(place)
		drawBalls(place)
		if drawnVersion ~= show.version then
			drawnVersion = show.version
			drawWalls(place)
			syncBodySplats()
		end
		rideBodySplats(place)
		drawPuffs(place, dt)
	end

	function world.stop(_self: World)
		for body in hidden do
			if body.Parent ~= nil then
				setHidden(body, false)
			end
		end
		table.clear(hidden)
		table.clear(figures)
		table.clear(balls)
		table.clear(wallSplats)
		table.clear(bodySplats)
		table.clear(puffs)
		folder:Destroy()
	end

	function world.counts(_self: World): { puppets: number, balls: number, splats: number, hidden: number }
		local out = { puppets = 0, balls = 0, splats = 0, hidden = 0 }
		for _, c in folder:GetChildren() do
			if c.ClassName == "Model" then
				out.puppets += 1
			elseif c.Name == "Ball" then
				out.balls += 1
			elseif c.Name == "Splat" then
				out.splats += 1
			end
		end
		for _ in hidden do
			out.hidden += 1
		end
		return out
	end

	return world
end

return World
