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
-- (Ghost.solidify: a person walks into a car, not through it), the drawn parts never collide. The server's swept test
-- stays the authority on a run-over.
-- Interface: start() -> stop(); the folder is returned by folder(). start() also starts Render/TownView
-- (street-lamp lights and the Skyline far view).
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

function VehicleView.start(): () -> ()
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
	local warned = false
	table.insert(
		conns,
		RunService.RenderStepped:Connect(function(dt: number)
			local good, err = pcall(function()
				local at = receiver:at(workspace:GetServerTimeNow(), dt)
				Ghost.render(receiver.buffer, at, folder, kinds, ground, models)
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
	end
end

return VehicleView
