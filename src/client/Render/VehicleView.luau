--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Render.VehicleView
-- Ghost AI vehicles from the pose stream (BUILD_PLAN §1.4, §1.6 VehiclePoses, D9; W1 #9 hand-off):
-- ReplicatedStorage.Net.VehiclePoses (an UnreliableRemoteEvent carrying 13-byte records) is decoded
-- with Net.decodeStream(Schemas.VehiclePose) into a Traffic/Ghost buffer, and every RenderStepped
-- Ghost.render places the placeholder cars (Traffic/VehiclePuppet at the true logical box) 100 ms
-- behind the newest snapshot with one BulkMoveTo. The kinds come once from the PlayNet folder's
-- TrafficKinds attribute (JSON, id -> { kind, color }). The ghosts live in workspace.TrafficGhosts,
-- are local to this client and never collide (the server's swept test is the authority).
-- Interface: start() -> stop(); the folder is returned by folder(). start() also starts Render/TownView
-- (street-lamp lights and the Skyline far view).
-- No side effects on require.

local Import = require("../Import")
local Ghost = Import.shared("Traffic/Ghost") :: typeof(require("../../shared/Traffic/Ghost"))
local Net = Import.shared("Net/Net") :: typeof(require("../../shared/Net/Net"))
local Schemas = Import.shared("Net/Schemas") :: typeof(require("../../shared/Net/Schemas"))
local Height = Import.shared("World/Height") :: typeof(require("../../shared/World/Height"))
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
	local buffer = Ghost.new()
	local clock = Ghost.newClock()
	local models: { [number]: Model } = {}
	local conns: { RBXScriptConnection } = {}
	table.insert(
		conns,
		poses.OnClientEvent:Connect(function(b: buffer)
			if typeof(b) ~= "buffer" then
				return
			end
			local good, records = pcall(Net.decodeStream, Schemas.VehiclePose, b)
			if good then
				-- the server's own clock spaces the snapshots; the arrival time only anchors them
				local arrival = workspace:GetServerTimeNow()
				local stamp = Ghost.takeStamp(records)
				buffer:push(if stamp then clock:localTime(stamp, arrival) else arrival, records)
			end
		end)
	)
	local warned = false
	table.insert(
		conns,
		RunService.RenderStepped:Connect(function()
			local good, err = pcall(function()
				local before = #folder:GetChildren()
				Ghost.render(buffer, workspace:GetServerTimeNow(), folder, kinds, Height.at, models)
				if #folder:GetChildren() ~= before then
					for _, d in folder:GetDescendants() do
						if d:IsA("BasePart") then
							d.CanCollide = false
							d.CanQuery = false
							d.CanTouch = false
						end
					end
				end
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
