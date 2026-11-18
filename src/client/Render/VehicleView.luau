--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Render.VehicleView
-- Ghost AI vehicles from the pose stream (BUILD_PLAN §1.4, §1.6 VehiclePoses, D9; W1 #9 hand-off):
-- ReplicatedStorage.Net.VehiclePoses (an UnreliableRemoteEvent carrying 13-byte records) goes through
-- Traffic/PoseStream's receiver (decode, the server's stamp placed on the local clock, the Traffic/Ghost
-- snapshot buffer), and every RenderStepped Ghost.render places the placeholder cars
-- (Traffic/VehiclePuppet at the true logical box, seated on World/RoadSurface) Ghost.DELAY behind the newest snapshot with one
-- BulkMoveTo. All the arithmetic between a packet and a CFrame lives in those two shared modules, which
-- the headless replay (tools/sim) runs as well; this file only wires them to the engine. The kinds come once from the PlayNet folder's
-- TrafficKinds attribute (JSON, id -> { kind, color }). The ghosts live in workspace.TrafficGhosts and are
-- local to this client; each one's invisible RootPart (the logical box) is solid to this client's own body
-- (Ghost.solidify: a person walks into a car, not through it) while the car is near still and not already over that
-- body (Ghost.solidFor: a moving box would shove a Humanoid), the drawn parts never collide. The server's swept test
-- stays the authority on a run-over.
-- The boxes of the cars drawn this frame go into `opts.cars` (a Traffic/Solid set: Client/World/ClientWorld's `cars`),
-- where the squirrel's motor meets them as walls and roofs.
-- Interface: start(opts?) -> stop() (opts.cars: Traffic/Solid.Set); the folder is returned by folder(). start() also
-- starts Render/TownView (street-lamp lights and the Skyline far view).
-- No side effects on require.

local Import = require("../Import")
local Ghost = Import.shared("Traffic/Ghost") :: typeof(require("../../shared/Traffic/Ghost"))
local PoseStream = Import.shared("Traffic/PoseStream") :: typeof(require("../../shared/Traffic/PoseStream"))
local Height = Import.shared("World/Height") :: typeof(require("../../shared/World/Height"))
local RoadSurface = Import.shared("World/RoadSurface") :: typeof(require("../../shared/World/RoadSurface"))
local Data = Import.shared("Data") :: typeof(require("../../shared/Data"))
local TownView = require("./TownView")

local VehicleView = {}

local folderRef: Folder? = nil

function VehicleView.folder(): Folder?
	return folderRef
end

function VehicleView.start(opts: { cars: any? }?): () -> ()
	local cars = if opts then opts.cars else nil
	-- the street lamps and Skyline far view (no remotes needed) start first, whatever happens below
	TownView.start()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local RunService = game:GetService("RunService")
	local HttpService = game:GetService("HttpService")
	local netFolder = ReplicatedStorage:WaitForChild("Net", 30)
	local playNet = ReplicatedStorage:WaitForChild("PlayNet", 30)
	if netFolder == nil or playNet == nil then
		warn("VehicleView: no Net / PlayNet folder; traffic is not drawn")
		return function() end
	end
	local poses = netFolder:WaitForChild("VehiclePoses", 10) :: any
	if poses == nil then
		warn("VehicleView: no VehiclePoses remote; traffic is not drawn")
		return function() end
	end
	local kinds: { [number]: { kind: string, color: string? } } = {}
	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(playNet:GetAttribute("TrafficKinds") :: string)
	end)
	if ok and type(decoded) == "table" then
		for k, v in decoded do
			local id = tonumber(k)
			if id then
				kinds[id] = v
			end
		end
	end
	local folder = Instance.new("Folder")
	folder.Name = "TrafficGhosts"
	folder.Parent = workspace
	folderRef = folder
	local receiver = PoseStream.newReceiver()
	-- the ghosts stand on the roads as baked (World/RoadSurface: the same parts worldgen lays), not on
	-- the terrain under them
	local ground = RoadSurface.ground(RoadSurface.new(Data.default():roads()), Height.at)
	local models: { [number]: Model } = {}
	local conns: { RBXScriptConnection } = {}
	table.insert(
		conns,
		poses.OnClientEvent:Connect(function(b: buffer)
			-- the server's own clock spaces the snapshots; the arrival time only anchors them
			receiver:packet(b, workspace:GetServerTimeNow())
		end)
	)
	-- this client's own body (the possessed one is the player's Character), for Ghost.solidFor: its root's centre
	-- column, a little inside the root so a body pressed on a car's side does not count as inside it, from the feet
	local player = game:GetService("Players").LocalPlayer
	local body = { x = 0, z = 0, half = 0, y0 = 0, y1 = 0 }
	local function bodyBox(): { x: number, z: number, half: number, y0: number, y1: number }?
		local character = player.Character
		local root = character and character.PrimaryPart
		if root == nil then
			return nil
		end
		local humanoid = (character :: Model):FindFirstChildOfClass("Humanoid")
		local p, size = root.Position, root.Size
		body.x, body.z = p.X, p.Z
		body.half = math.min(size.X, size.Z) * 0.4
		body.y0 = p.Y - size.Y / 2 - (if humanoid then humanoid.HipHeight else 0)
		body.y1 = p.Y + size.Y / 2
		return body
	end
	local warned = false
	table.insert(
		conns,
		RunService.RenderStepped:Connect(function(dt: number)
			local good, err = pcall(function()
				local at = receiver:at(workspace:GetServerTimeNow(), dt)
				Ghost.render(receiver.buffer, at, folder, kinds, ground, models, cars, bodyBox())
			end)
			if not good and not warned then
				warned = true
				warn(`VehicleView: render failed: {err}`)
			end
		end)
	)
	return function()
		for _, c in conns do
			c:Disconnect()
		end
		folder:Destroy()
		if cars then
			cars.n = 0
		end
	end
end

return VehicleView
