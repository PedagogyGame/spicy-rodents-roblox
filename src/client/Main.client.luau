--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Main
-- Client entry of the first playable build (owner directive 2026-11-09; BUILD_PLAN §1.3, §4.4 #5):
-- the loading screen first (UI/PlayMenu: server boot progress, then the climbing routes prepared on
-- this computer), then the AnimationDriver over every body (D3), the traffic ghosts
-- (Render/VehicleView), PossessionClient (controllers, cameras, devices, Reset routing) and the menu
-- (pick Spicy Rodent, Squirrel, Townsperson, Police or the Police drone; PlayNet.Pick). F kicks
-- (PlayNet.Kick) when on foot as a person. Server messages (PlayNet.Event) become toasts and banners:
-- bites, kicks, RUN OVER, KICKED OUT. The S2 test place runs its own S2Client and this script steps
-- aside there.

local container = script.Parent
if container and container.Parent and container.Parent:FindFirstChild("S2Client") then
	return
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")

local Hud = require("./UI/Hud")
local PlayMenu = require("./UI/PlayMenu")
local AnimationDriver = require("./Animation/AnimationDriver")
local PossessionClient = require("./Possession/PossessionClient")
local VehicleView = require("./Render/VehicleView")
local ClientWorld = require("./World/ClientWorld")

local pickRemote: RemoteEvent? = nil
local menu = PlayMenu.start(function(choice: string)
	if pickRemote then
		pickRemote:FireServer(choice)
	end
end)
local hud = Hud.start()
hud.set("Spicy Rodents: first playable build", "Loading the town…")

local world = ClientWorld.get() -- starts building the rail world in the background now
if not menu.loading(function(): boolean
	return world.railReady
end) then
	hud.set("Spicy Rodents: the server did not start", "See View > Output in Studio")
	return
end

local playNet = ReplicatedStorage:WaitForChild("PlayNet", 30)
local bodies = workspace:WaitForChild("Bodies", 30)
if playNet == nil or bodies == nil then
	hud.set("Spicy Rodents", "The server did not create the town's bodies (see View > Output)")
	menu.toast("The server did not finish starting: see View > Output", 30)
	return
end
pickRemote = playNet:WaitForChild("Pick") :: RemoteEvent
local kickRemote = playNet:WaitForChild("Kick") :: RemoteEvent
local eventRemote = playNet:WaitForChild("Event") :: RemoteEvent

AnimationDriver.start({ container = bodies })
task.spawn(function()
	VehicleView.start()
	local ghosts = VehicleView.folder()
	if ghosts then
		world.ignore({ ghosts })
	end
end)
local client = PossessionClient.start({
	bodies = bodies,
	overview = { position = Vector3.new(0, 120, 260), lookAt = Vector3.zero },
	hud = hud,
})

-- keep the help panel in step with vehicles and the drone
local lastDevice: string? = nil
game:GetService("RunService").Heartbeat:Connect(function()
	local d = client.state().device
	if d ~= lastDevice then
		lastDevice = d
		menu.setDevice(d)
	end
end)

UIS.InputBegan:Connect(function(io: InputObject, processed: boolean)
	if processed then
		return
	end
	if io.KeyCode == Enum.KeyCode.F or io.KeyCode == Enum.KeyCode.ButtonX then
		local st = client.state()
		if st.species == "human" and st.device == nil then
			kickRemote:FireServer()
		elseif io.KeyCode == Enum.KeyCode.F then
			menu.toast(if st.species then "Only people can kick" else "Pick a body from the menu first", 2)
		end
	end
end)

eventRemote.OnClientEvent:Connect(function(msg: { [string]: any })
	local kind = msg.kind
	if kind == "picked" then
		menu.close()
		local names = {
			rodent = "You are the SPICY RODENT. Bite people!",
			squirrel = "You are a squirrel. Climb something!",
			townsperson = "You are a townsperson. F kicks the rodent.",
			police = "You are a police officer. Your patrol car is right here: press E.",
			drone = "Police drone: launching…",
		}
		menu.toast(names[msg.role] or "Here you go", 4)
	elseif kind == "refused" then
		menu.toast(tostring(msg.text), 3)
	elseif kind == "bite" then
		menu.toast(`CHOMP! "{msg.line}"   +{msg.delta} Power   ({msg.bites} bites)`, 2.5)
	elseif kind == "bitten" then
		menu.toast(`The rodent bit you! You shout: "{msg.line}"`, 2.5)
	elseif kind == "kick" then
		if msg.hit then
			menu.toast(
				if (msg.health or 0) <= 0
					then `KICK! The {msg.target} is knocked out.`
					else `KICK! The {msg.target} has {msg.health} health left.`,
				2.5
			)
		else
			menu.toast("Kick missed: get right next to it, facing it", 1.5)
		end
	elseif kind == "hurt" then
		menu.toast(`OUCH! You were kicked: {msg.health} health left`, 2.5)
	elseif kind == "died" then
		menu.banner(tostring(msg.title), tostring(msg.line), 3.5)
		task.delay(3.5, function()
			menu.open()
		end)
	end
end)

hud.set("Spicy Rodents: first playable build", "Pick who to play from the menu")
