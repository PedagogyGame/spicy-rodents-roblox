--!strict
-- ServerScriptService.Server.Actors.DeviceService
-- The engine side of player vehicles and the drone (BUILD_PLAN §1.5 Devices, §4.4 #5): spawns the
-- placeholder fleet (Shared/Vehicles/Placeholder at the VehicleKinds boxes), and on the client's
-- "interact" request seats the possessed human in the nearest vehicle (or launches the drone),
-- hands the vehicle root's network ownership to that player and tells the client
-- (DeviceGranted -> Vehicle / Drone controller and camera); "interact" again gets out (the vehicle
-- is anchored where it stopped, the body stands beside it). Seats and keys are
-- Shared/Vehicles/PlayerVehicles; keys only change hands while parked. W1 has no ranks yet, so
-- `openKeys` (default on) hands a parked vehicle's key to whoever asks; W2 wires
-- Ladder.keyHolders through grantKeys instead.
-- Interface: start(opts) -> Service { fleet, models, interact(player, body), exitAll(player),
--   spawn(kind, x, y, z, yaw) -> id }
-- Engine only inside the functions. No side effects on require.

local Import = require("../Import")
local PossessionState =
	Import.shared("Actors/PossessionState") :: typeof(require("../../shared/Actors/PossessionState"))
local PlayerVehicles =
	Import.shared("Vehicles/PlayerVehicles") :: typeof(require("../../shared/Vehicles/PlayerVehicles"))
local VehicleKinds = Import.shared("Vehicles/VehicleKinds") :: typeof(require("../../shared/Vehicles/VehicleKinds"))
local Placeholder = Import.shared("Vehicles/Placeholder") :: typeof(require("../../shared/Vehicles/Placeholder"))
local Height = Import.shared("World/Height") :: typeof(require("../../shared/World/Height"))
local Units = Import.shared("Config/Units") :: typeof(require("../../shared/Config/Units"))

export type Opts = {
	net: Folder, -- ReplicatedStorage.PossessionNet
	parent: Instance?, -- default workspace.Vehicles
	openKeys: boolean?,
	speciesOf: (player: Player) -> string?, -- the possessed body's species
	bodyOf: (player: Player) -> Model?,
	placements: { { kind: string, x: number, z: number, yaw: number } }?,
}

export type Service = {
	fleet: PlayerVehicles.Fleet,
	models: { [string]: Model },
	interact: (self: Service, player: Player) -> (boolean, string?),
	exitAll: (self: Service, player: Player) -> (),
	spawn: (self: Service, kind: string, x: number, y: number, z: number, yaw: number) -> string,
}

local DeviceService = {}

local REACH = 16 -- studs from the body to the vehicle's root

-- Default placements (studs, HTML yaw): patrol cars at the police station, carts and bikes in the
-- core, a pickup and an SUV on the main street, a jet ski on the river, the drone at the station.
function DeviceService.defaultPlacements(data: any?): { { kind: string, x: number, z: number, yaw: number } }
	local st = Units.st
	local px, pz = st(-510), st(-107)
	if data then
		local lot = data:lot("west_police_station")
		if lot then
			px, pz = lot.x, lot.z
		end
	end
	local riverZ = 120
	return {
		{ kind = "car", x = px + 20, z = pz + 30, yaw = 0 },
		{ kind = "car", x = px + 32, z = pz + 30, yaw = 0 },
		{ kind = "cart", x = st(-14), z = st(20), yaw = 0 },
		{ kind = "cart", x = st(14), z = st(-20), yaw = math.pi },
		{ kind = "bike", x = st(-13), z = st(30), yaw = 0 },
		{ kind = "bike", x = st(13), z = st(-30), yaw = math.pi },
		{ kind = "pickup", x = st(-5.4), z = st(45), yaw = 0 },
		{ kind = "suv", x = st(5.4), z = st(-45), yaw = math.pi },
		{ kind = "jetski", x = st(Height.riverCenterU(riverZ)), z = st(riverZ), yaw = 0 },
		{ kind = "drone", x = px + 10, z = pz + 18, yaw = 0 },
	}
end

local function buildDrone(name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	local root = Instance.new("Part")
	root.Name = "RootPart"
	root.Size = Vector3.new(2, 0.8, 2)
	root.Color = Color3.fromRGB(30, 30, 40)
	root.CanCollide = false
	root.Parent = m
	for i = 1, 4 do
		local rotor = Instance.new("Part")
		rotor.Name = `Rotor{i}`
		rotor.Size = Vector3.new(1.2, 0.1, 1.2)
		rotor.CanCollide = false
		rotor.Massless = true
		local a = (i - 0.5) * math.pi / 2
		rotor.CFrame = CFrame.new(math.cos(a) * 1.4, 0.4, math.sin(a) * 1.4)
		rotor.Parent = m
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = root, rotor
		w.Parent = rotor
	end
	local cam = Instance.new("Attachment")
	cam.Name = "Camera"
	cam.Parent = root
	m.PrimaryPart = root
	m:SetAttribute("VehicleKind", "drone")
	return m
end

local function remote(parent: Instance, name: string): RemoteEvent
	local r = parent:FindFirstChild(name)
	if r and r:IsA("RemoteEvent") then
		return r
	end
	local e = Instance.new("RemoteEvent")
	e.Name = name
	e.Parent = parent
	return e
end

local function groundY(x: number, z: number, model: Model): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { model }
	local hit = workspace:Raycast(Vector3.new(x, 400, z), Vector3.new(0, -800, 0), params)
	return if hit then hit.Position.Y else Height.at(x, z)
end

function DeviceService.start(opts: Opts): Service
	local parent = opts.parent
	if parent == nil then
		local f = workspace:FindFirstChild("Vehicles") or Instance.new("Folder")
		f.Name = "Vehicles"
		f.Parent = workspace
		parent = f
	end
	local granted = remote(opts.net, PossessionState.NET.DeviceGranted)
	local released = remote(opts.net, PossessionState.NET.DeviceReleased)
	local request = remote(opts.net, PossessionState.NET.DeviceRequest)
	local fleet = PlayerVehicles.new()
	local models: { [string]: Model } = {}
	local drones: { [string]: boolean } = {}
	local flying: { [Player]: string } = {}
	local openKeys = opts.openKeys ~= false
	local count = 0

	local self: Service
	self = {
		fleet = fleet,
		models = models,
		spawn = function(_s: Service, kind: string, x: number, y: number, z: number, yaw: number): string
			count += 1
			local id = `{kind}_{count}`
			local model: Model
			local half: number
			if kind == "drone" then
				model = buildDrone(id)
				half = 0.4
				drones[id] = true
			else
				model = Placeholder.build(kind, id)
				half = VehicleKinds.kind(kind).size[2] * 0.5
				PlayerVehicles.add(fleet, id, kind, x, z, yaw)
			end
			local gy = if kind == "jetski" then Height.WATER_Y else groundY(x, z, model)
			model:PivotTo(Units.yawCFrame(yaw, Vector3.new(x, y ~= 0 and y or gy + half + 0.05, z)))
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					d.Anchored = d == model.PrimaryPart
				end
			end
			model.Parent = parent
			models[id] = model
			return id
		end,
		interact = function(_s: Service, player: Player): (boolean, string?)
			-- getting out (vehicle or drone)
			local current = PlayerVehicles.vehicleOf(fleet, player.UserId) or flying[player]
			local body = opts.bodyOf(player)
			if current then
				local model = models[current]
				local root = model.PrimaryPart :: BasePart
				pcall(function()
					root:SetNetworkOwner(nil)
				end)
				root.Anchored = true
				root.AssemblyLinearVelocity = Vector3.zero
				if drones[current] then
					flying[player] = nil
					player.ReplicationFocus = nil
				else
					PlayerVehicles.setMotion(fleet, current, 0, root.Position.X, root.Position.Z)
					PlayerVehicles.exit(fleet, player.UserId)
					local seat = model:FindFirstChild("DriverSeat") :: Seat?
					if seat and seat.Occupant then
						seat.Occupant.Sit = false
						local weld = seat:FindFirstChild("SeatWeld")
						if weld then
							weld:Destroy()
						end
					end
					if body and body.PrimaryPart then
						local side = root.CFrame.RightVector * (model:GetExtentsSize().X * 0.5 + 3)
						body:PivotTo(CFrame.new(root.Position - side + Vector3.new(0, 3, 0)))
					end
				end
				released:FireClient(player, "exit")
				return true, nil
			end
			if body == nil or body.PrimaryPart == nil then
				return false, "no body"
			end
			if opts.speciesOf(player) ~= "human" then
				return false, "only people drive"
			end
			local pos = (body.PrimaryPart :: BasePart).Position
			local best, bestD = nil, REACH
			for id, model in models do
				local r = model.PrimaryPart
				if r then
					local d = (r.Position - pos).Magnitude
					local free = if drones[id] then true else PlayerVehicles.get(fleet, id).driver == nil
					if d < bestD and free then
						best, bestD = id, d
					end
				end
			end
			if best == nil then
				return false, "no vehicle within reach"
			end
			local model = models[best]
			local root = model.PrimaryPart :: BasePart
			if drones[best] then
				for _, other in flying do
					if other == best then
						return false, "the drone is in use"
					end
				end
				flying[player] = best
				root.Anchored = false
				root:SetNetworkOwner(player)
				player.ReplicationFocus = root
				granted:FireClient(player, { device = "drone", model = model, kind = "drone" })
				return true, nil
			end
			local v = PlayerVehicles.get(fleet, best) :: PlayerVehicles.Vehicle
			if openKeys and v.parked and v.driver == nil then
				v.key = player.UserId
			end
			local ok, reason = PlayerVehicles.enter(fleet, best, player.UserId, {
				human = true,
				officer = openKeys or body:GetAttribute("Post") == "police",
				paidRental = openKeys,
			})
			if not ok then
				return false, reason
			end
			root.Anchored = false
			local seat = model:FindFirstChild("DriverSeat") :: Seat?
			local humanoid = body:FindFirstChildOfClass("Humanoid")
			if seat and humanoid then
				body:PivotTo(seat.CFrame * CFrame.new(0, 2, 0))
				seat:Sit(humanoid)
			end
			root:SetNetworkOwner(player)
			granted:FireClient(player, { device = "vehicle", model = model, kind = v.kind })
			return true, nil
		end,
		exitAll = function(s: Service, player: Player)
			if PlayerVehicles.vehicleOf(fleet, player.UserId) or flying[player] then
				s:interact(player)
			end
		end,
	}
	for _, p in opts.placements or DeviceService.defaultPlacements(nil) do
		self:spawn(p.kind, p.x, 0, p.z, p.yaw)
	end
	request.OnServerEvent:Connect(function(player: Player, verb: any)
		if verb ~= "interact" then
			return
		end
		local ok, reason = self:interact(player)
		if not ok then
			released:FireClient(player, reason or "cannot")
		end
	end)
	return self
end

return DeviceService
