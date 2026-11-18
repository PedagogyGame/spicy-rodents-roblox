--!strict
-- tools/games/paintball/client/engine_check.luau: the paintball client's check in the real engine (a Luau
-- Execution task script). The client lane's specs run on a fake engine, which believes whatever it is told: a
-- property that does not exist is just another field there. This asks the real one the questions the fake
-- cannot answer, and runs the client's two headless cores on the engine's own Luau.
--   THE ENGINE'S FACTS (needs nothing of ours)
--     every property the client writes exists and takes the value: Humanoid.CameraOffset / JumpHeight /
--       UseJumpPower (the eye and the hop: Self), LocalTransparencyModifier on a part and on a Decal (the real
--       bodies hidden: World), ScreenGui.ScreenInsets = None (the crosshair's layer: Hud), GuiButton.Modal (what
--       frees a first-person mouse), UIScale, BillboardGui.MaxDistance, Camera.FieldOfView
--     every enum item and key the client names exists (RenderPriority.Camera, CameraMode.LockFirstPerson, the
--       gamepad's buttons, Material.Air for "off the floor")
--     a Cylinder's flat faces look along its own X (World turns X onto the wall's normal for a splat): asked
--       with three rays
--   THE CORES ON THE ENGINE'S LUAU (needs ReplicatedStorage.Shared and StarterPlayerScripts.Client: a CI place
--     version, or --inject ci.project.json): a seat is joined, placed and fires; the click that went up is one
--     the wire decodes; the predicted ball ends on the wall where Ballistics says and leaves its splat there;
--     two snapshots draw a puppet between them; sprint and crouch move the pace and the eye
--   THE BUILDING (needs the baked Attractions): the arena's model is found the way the client looks for it,
--     and each team has curtains by the names the client makes solid
-- What it cannot ask: anything with a screen, a camera or a player (a Luau Execution task has no client). That
-- the stock first-person camera carries on from a one-frame hold, that a non-sinking FIRE leaves its drag to
-- the camera, and where the crosshair sits against the camera's middle are for Studio and a device. So are:
-- that NO NAME, HEALTH BAR OR CHAT BUBBLE is drawn over a hidden opponent's real body (two players in Studio's
-- local server, one crouched behind a rail: the other sees no label there; this script only checks that the
-- properties World writes take their values); that a shot fired behind you on the left is heard from there;
-- and that holding View on a gamepad, then pressing A, does not leave the match.
-- NOT YET RUN in the engine: the session that wrote it (2026-11-13) had the cloud tools off limits. Under plain
-- Lune it runs the cores part from the files on disk and notes that the engine's facts were not asked;
-- tests/unit/paintball_client_core.spec.luau requires it and holds it to that.
-- Sent by: node tools/cloud/cloud.mjs run_engine_tests tools/games/paintball/client/engine_check.luau --version <v> --place ci
-- Interface: a task script (returns { suite, ok, failures, notes, numbers, placeVersion })

local failures: { string } = {}
local notes: { string } = {}
local numbers: { [string]: any } = {}
local inEngine = (game :: any) ~= nil and (workspace :: any) ~= nil

local function check(name: string, fn: () -> (boolean, string?))
	local ran, ok, why = pcall(fn)
	if not ran then
		table.insert(failures, `{name}: {tostring(ok)}`)
	elseif ok ~= true then
		table.insert(failures, `{name}: {tostring(why or "not so")}`)
	end
end

local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-4)
end

-- THE ENGINE'S FACTS ----------------------------------------------------------------------------------------
if inEngine then
	check("Humanoid: the eye and the hop (CameraOffset, JumpHeight, UseJumpPower, the rig's own heights)", function()
		local hum = Instance.new("Humanoid")
		hum.CameraOffset = Vector3.new(0, -1.8, 0)
		hum.UseJumpPower = false
		hum.JumpHeight = 2
		local read = { hum.HipHeight, hum.AutomaticScalingEnabled, hum.RigType, hum.FloorMaterial, hum.MoveDirection }
		return near(hum.CameraOffset.Y, -1.8) and near(hum.JumpHeight, 2) and #read == 5 and hum.RootPart == nil
	end)
	check("LocalTransparencyModifier on a part and on a Decal", function()
		local part = Instance.new("Part")
		local face = Instance.new("Decal");
		(part :: any).LocalTransparencyModifier = 1
		(face :: any).LocalTransparencyModifier = 1
		return (part :: any).LocalTransparencyModifier == 1 and (face :: any).LocalTransparencyModifier == 1
	end)
	check("a hidden body's Humanoid draws no name and no health bar (World.setHidden)", function()
		local hum = Instance.new("Humanoid")
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.DisplayWhenDamaged
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		return hum.DisplayDistanceType == Enum.HumanoidDisplayDistanceType.None
			and hum.HealthDisplayType == Enum.HumanoidHealthDisplayType.AlwaysOff
	end)
	check("a sound placed in space: a Sound in an Attachment, its roll-off pushed out, a floor's dulling", function()
		local holder = Instance.new("Part")
		holder.CFrame = CFrame.new(0, 0, 0)
		local at = Instance.new("Attachment")
		at.Position = Vector3.new(12, 4, -30)
		at.Parent = holder
		local sound = Instance.new("Sound")
		sound.RollOffMode = Enum.RollOffMode.Linear
		sound.RollOffMinDistance = 110
		sound.RollOffMaxDistance = 220
		local dull = Instance.new("EqualizerSoundEffect")
		dull.HighGain = -12
		dull.MidGain = -6
		dull.LowGain = 0
		dull.Parent = sound
		sound.Parent = at
		local ok = near(sound.RollOffMinDistance, 110) and near(dull.HighGain, -12) and near(at.WorldPosition.X, 12)
		holder:Destroy()
		return ok
	end)
	check("the HUD's pieces: IgnoreGuiInset, Modal, UIScale, a square that follows the height, a name tag", function()
		local gui = Instance.new("ScreenGui")
		gui.IgnoreGuiInset = true
		gui.ScreenInsets = Enum.ScreenInsets.None
		gui.ResetOnSpawn = false
		gui.DisplayOrder = 18
		local button = Instance.new("TextButton")
		button.Modal = true
		local scale = Instance.new("UIScale")
		scale.Scale = 0.7
		local frame = Instance.new("Frame")
		frame.SizeConstraint = Enum.SizeConstraint.RelativeYY
		frame.Active = false
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		local board = Instance.new("BillboardGui")
		board.MaxDistance = 70
		board.StudsOffset = Vector3.new(0, 1.4, 0)
		return gui.IgnoreGuiInset
			and gui.ScreenInsets == Enum.ScreenInsets.None
			and button.Modal
			and near(scale.Scale, 0.7)
			and board.MaxDistance == 70
	end)
	check("the camera's view can be widened", function()
		local camera = Instance.new("Camera")
		camera.FieldOfView = 76
		return near(camera.FieldOfView, 76)
	end)
	check("the enum items and keys the client names", function()
		local missing: { string } = {}
		for _, name in
			{
				"LeftShift",
				"RightShift",
				"LeftControl",
				"C",
				"G",
				"R",
				"ButtonR2",
				"ButtonX",
				"ButtonB",
				"ButtonL3",
				"ButtonSelect",
				"ButtonY",
				"DPadUp",
				"Thumbstick1",
			}
		do
			local ok, item = pcall(function()
				return (Enum.KeyCode :: any)[name]
			end)
			if not ok or item == nil or item.Name ~= name then
				table.insert(missing, name)
			end
		end
		local items = {
			Enum.RenderPriority.Camera,
			Enum.CameraMode.LockFirstPerson,
			Enum.CameraType.Scriptable,
			Enum.UserInputType.MouseButton1,
			Enum.UserInputType.Touch,
			Enum.Material.Air,
			Enum.Material.Neon,
			Enum.PartType.Cylinder,
			Enum.PartType.Ball,
			Enum.HumanoidRigType.R15,
		}
		numbers.renderPriorityCamera = Enum.RenderPriority.Camera.Value
		return #missing == 0 and #items == 10, `no such key: {table.concat(missing, ", ")}`
	end)
	check("a Cylinder's flat faces look along its own X", function()
		local disc = Instance.new("Part")
		disc.Shape = Enum.PartType.Cylinder
		disc.Size = Vector3.new(0.08, 2, 2)
		disc.Anchored = true
		disc.CFrame = CFrame.new(0, 5000, 0)
		disc.Parent = workspace
		local only = RaycastParams.new()
		only.FilterType = Enum.RaycastFilterType.Include
		only.FilterDescendantsInstances = { disc }
		-- through the middle along X: the flat face, 0.04 out
		local face = workspace:Raycast(Vector3.new(-5, 5000, 0), Vector3.new(10, 0, 0), only)
		-- along X at the corner of the square it is cut from: a block is hit there, a disc facing X is not
		local corner = workspace:Raycast(Vector3.new(-5, 5000.9, 0.9), Vector3.new(10, 0, 0), only)
		-- down onto the rim: one radius up
		local rim = workspace:Raycast(Vector3.new(0, 5005, 0), Vector3.new(0, -10, 0), only)
		disc:Destroy()
		if face == nil or rim == nil then
			return false, "a ray that should have met the disc did not"
		end
		numbers.cylinderFaceX = face.Position.X
		numbers.cylinderRimY = rim.Position.Y - 5000
		return near(face.Position.X, -0.04, 0.01) and corner == nil and near(rim.Position.Y, 5001, 0.02),
			`face at x {face.Position.X}, the corner {if corner then "hit" else "clear"}, rim at y {rim.Position.Y - 5000}`
	end)
	check("the clock both sides share", function()
		local now = workspace:GetServerTimeNow()
		return type(now) == "number" and now > 0
	end)
else
	table.insert(notes, "no engine here: the engine's facts were not asked")
end

-- THE CORES ON THIS LUAU ------------------------------------------------------------------------------------
-- The client's modules: out of the DataModel in the engine, off the disk under Lune.
local function sharedModule(path: string): any
	if inEngine then
		local node: Instance? = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
		for part in string.gmatch(path, "[^/]+") do
			node = if node then node:FindFirstChild(part) else nil
		end
		return if node then (require :: any)(node) else nil
	end
	return (require :: any)("../../../../src/shared/" .. path)
end

local function clientModule(name: string): any
	if inEngine then
		local scripts = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
		local client = if scripts then scripts:FindFirstChild("Client") else nil
		local games = if client then client:FindFirstChild("Minigames") else nil
		local folder = if games then games:FindFirstChild("Paintball") else nil
		local node = if folder then folder:FindFirstChild(name) else nil
		return if node then (require :: any)(node) else nil
	end
	return (require :: any)("../../../../src/client/Minigames/Paintball/" .. name)
end

local loaded, M = pcall(function()
	local m = {
		Arena = sharedModule("Minigames/Paintball/Arena"),
		Body = sharedModule("Minigames/Paintball/Body"),
		Contract = sharedModule("Minigames/Paintball/Contract"),
		Wire = sharedModule("Minigames/Paintball/Wire"),
		Ballistics = sharedModule("Paintball/Ballistics"),
		BufferCodec = sharedModule("Util/BufferCodec"),
		ShowCore = clientModule("ShowCore"),
		SeatCore = clientModule("SeatCore"),
		Self = if inEngine then clientModule("Self") else nil,
	}
	for _, name in { "Arena", "Body", "Contract", "Wire", "Ballistics", "BufferCodec", "ShowCore", "SeatCore" } do
		assert((m :: any)[name] ~= nil, `{name} is not in this place`)
	end
	return m
end)

if not loaded then
	if inEngine then
		table.insert(notes, `the client's code is not in this place ({tostring(M)}): the cores were not run`)
	else
		table.insert(failures, `the cores did not load: {tostring(M)}`)
	end
else
	local Arena, Body, Contract, Wire = M.Arena, M.Body, M.Contract, M.Wire
	-- a floor, a wall across the north at z = -40, a spawn room either side; the player at (0, 0, 30) looking north
	local boxes: { number } = {}
	local kinds: { number } = {}
	local function box(kind: number, list: { number })
		for _, v in list do
			table.insert(boxes, v)
		end
		table.insert(kinds, kind)
	end
	box(Arena.KIND.slab, { -60, -1, -60, 60, 0, 60 })
	box(Arena.KIND.wall, { -30, 0, -41, 30, 12, -40 })
	local function spawns(x: number): { any }
		local list = {}
		for i = 1, 8 do
			table.insert(list, { x = x, y = 0, z = -8 + (i - 1) * 2, yaw = 0 })
		end
		return list
	end
	local T0, DT = 1000, 1 / 60
	local frames = 0
	local function now(): number
		return T0 + frames * DT
	end
	local pose = { x = 0, y = 0, z = 30, yaw = 0, pitch = 0 }
	local sent: { [string]: { buffer } } = {}
	local paces: { number } = {}
	local eye = 0
	local show: any, seat: any = nil, nil
	check("the cores: joined, placed, one click", function()
		local arena = Arena.finish({
			boxes = boxes,
			kinds = kinds,
			ramps = {},
			spawns = { spawns(-52), spawns(52) },
			spawnRooms = {
				{ minX = -60, minY = 0, minZ = -12, maxX = -44, maxY = 6.5, maxZ = 12 },
				{ minX = 44, minY = 0, minZ = -12, maxX = 60, maxY = 6.5, maxZ = 12 },
			},
			curtains = { {}, {} },
			exits = {},
			lobby = { x = 0, y = 0, z = 75, yaw = 0 },
			nodes = {},
			links = {},
			cover = {},
		})
		show = M.ShowCore.new({ arena = arena, now = now })
		local ctx: any = {
			station = Contract.STATION,
			game = Contract.GAME,
			label = "Paintball match",
			send = function() end,
			camera = function() end,
			releaseCamera = function() end,
			controls = function() end,
			pace = function(scale: number?)
				table.insert(paces, scale or 1)
			end,
			stamp = now,
			setButtons = function() end,
			toast = function() end,
			body = function()
				return nil
			end,
			sound = function()
				return false
			end,
		}
		seat = M.SeatCore.new(ctx, {
			now = now,
			arena = arena,
			link = {
				send = function(remote: string, payload: buffer)
					sent[remote] = sent[remote] or {}
					table.insert(sent[remote], payload)
				end,
				listen = function()
					return function() end
				end,
			},
			show = function()
				return show
			end,
			port = {
				pose = function()
					local cp = math.cos(pose.pitch)
					return pose.x,
						pose.y,
						pose.z,
						-math.sin(pose.yaw) * cp,
						math.sin(pose.pitch),
						-math.cos(pose.yaw) * cp,
						false
				end,
				push = function()
					return 1
				end,
				place = function(x: number, y: number, z: number)
					pose.x, pose.y, pose.z = x, y, z
				end,
				eye = function(offset: number)
					eye = offset
				end,
				user = function()
					return 11
				end,
			},
		})
		local slots, seats = {}, {}
		for id, name in { "Ann", "Cy" } do
			slots[id] = { id = id, team = id, on = true, tags = 0, outs = 0, shots = 0, hits = 0 }
			seats[id] = { name = name, gone = false }
		end
		local watch = {
			kind = "paintball_watch",
			match = 1,
			slots = {
				{ id = 1, team = 1, name = "Ann", bot = false, user = 11 },
				{ id = 2, team = 2, name = "Cy", bot = false, user = 12 },
			},
			now = now(),
			feel = Contract.feel(),
		}
		assert(Wire.checkMessage(watch))
		show:onWatch(watch, nil)
		seat:onMessage(watch, show)
		seat:onState({
			kind = "state",
			station = Contract.STATION,
			you = 1,
			view = {
				phase = "playing",
				seats = seats,
				game = { phase = "live", endsAt = now() + 300, size = 2, scores = { 0, 0 }, slots = slots },
			},
			match = 1,
			bots = { false, false },
			rounds = Contract.Rules.magazine,
			reloadAt = 0,
			shot = 0,
			feel = Contract.feel(),
		})
		local placed = {
			kind = "paintball_respawn",
			id = 1,
			x = 0,
			y = 0,
			z = 30,
			yaw = 0,
			at = now() - 10,
			place = Wire.nextPlace(0),
		}
		assert(Wire.checkMessage(placed))
		seat:onMessage(placed, nil)
		local function frame(n: number)
			for _ = 1, n do
				frames += 1
				show:step(DT)
				seat:step(DT)
			end
		end
		frame(2)
		seat:input("fire", true)
		seat:input("fire", false) -- (one click: a press and its release)
		local fires = sent["Paintball.Fire"] or {}
		if #fires ~= 1 or #show.balls ~= 1 then
			return false, `{#fires} clicks sent and {#show.balls} balls drawn in the frame of the click`
		end
		local fire = M.BufferCodec.decode(Wire.Fire, fires[1])
		local ex, ey, ez = Body.eyePoint(0, 0, 30, 0)
		if
			not (near(fire.ox, ex) and near(fire.oy, ey) and near(fire.oz, ez) and near(fire.dz, -1) and fire.shot == 1)
		then
			return false, "the click on the wire is not the eye and the look"
		end
		-- the ball crosses 70 studs to the wall at z = -40: it ends there, as low as Ballistics says, and its splat is on the wall
		frame(60)
		local feel = Contract.feel()
		local t = 70 / feel.ballSpeed
		local _, wantY = M.Ballistics.position(ex, ey, ez, 0, 0, -feel.ballSpeed, feel.ballDrop, t)
		local splat = show.walls[1]
		if #show.balls ~= 0 or splat == nil then
			return false, `after a second {#show.balls} balls still fly and {#show.walls} splats are on the wall`
		end
		numbers.predictedSplat = { x = splat.x, y = splat.y, z = splat.z, wantY = wantY }
		if not (near(splat.z, -40, 1e-3) and near(splat.y, wantY, 1e-3) and near(splat.x, 0, 1e-3)) then
			return false, `the splat is at ({splat.x}, {splat.y}, {splat.z}), not (0, {wantY}, -40)`
		end
		return seat.mag.rounds == Contract.Rules.magazine - 1, "the magazine did not count the ball"
	end)
	check("the cores: a puppet between two snapshots; sprint and crouch", function()
		if show == nil or seat == nil then
			return false, "the seat did not open"
		end
		local function body(x: number): any
			return { id = 2, x = x, y = 0, z = -10, yaw = 0, pitch = 0, crouch = 0, bits = 0 }
		end
		for i = 0, 30 do
			show:onSnap(Wire.encodeSnap(now(), i, 1, { body(i * 0.5) }))
			frames += 1
			show:step(DT)
			seat:step(DT)
		end
		local puppet = show.puppets[2]
		if puppet == nil or not puppet.shown then
			return false, "no puppet for the other slot"
		end
		-- drawn in the past, between snapshots: behind the newest, ahead of the first
		if not (puppet.x > 0 and puppet.x < 15) then
			return false, `the puppet is drawn at x = {puppet.x}`
		end
		numbers.puppetLagStuds = 15 - puppet.x
		seat:input("sprint", true)
		for _ = 1, 30 do
			frames += 1
			show:step(DT)
			seat:step(DT)
		end
		local sprint = paces[#paces]
		seat:input("sprint", false)
		seat:input("crouch", true)
		for _ = 1, 30 do
			frames += 1
			show:step(DT)
			seat:step(DT)
		end
		local crouch = paces[#paces]
		numbers.pace = { sprint = sprint, crouch = crouch, eye = eye }
		return near(sprint, Contract.feel().sprintMult) and crouch < 1 and near(eye, Body.CROUCH_EYE - Body.STAND_EYE),
			`sprint pace {sprint}, crouch pace {crouch}, the eye at {eye}`
	end)

	-- THE BUILDING -------------------------------------------------------------------------------------------
	if inEngine and M.Self ~= nil then
		local found, model = pcall(M.Self.arenaModel)
		if not found or model == nil then
			table.insert(
				notes,
				"the arena's model is not in this place (no baked Attractions): the curtains were not counted"
			)
		else
			check("the building: each team has curtains by the names the client makes solid", function()
				local count = { 0, 0 }
				for _, d in (model :: Instance):GetDescendants() do
					if d:IsA("BasePart") then
						for team = 1, 2 do
							if d.Name == Arena.CURTAIN .. team then
								count[team] += 1
							end
						end
					end
				end
				numbers.curtains = count
				return count[1] > 0 and count[2] > 0, `{count[1]} of team 1's and {count[2]} of team 2's`
			end)
		end
	end
end

-- (quiet where there is nothing to say and nobody but a spec asking)
if inEngine or #failures > 0 then
	for _, f in failures do
		print(`  FAIL {f}`)
	end
	for _, n in notes do
		print(`  note: {n}`)
	end
	print(`PaintballClientEngine: ok={#failures == 0} failures={#failures}`)
end

return {
	suite = "PaintballClientEngine",
	ok = #failures == 0,
	failures = failures,
	notes = notes,
	numbers = numbers,
	placeVersion = if inEngine then game.PlaceVersion else nil,
}
