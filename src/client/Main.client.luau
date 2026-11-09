--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Main
-- Client entry of the first playable build (owner directive 2026-11-09; BUILD_PLAN §1.3, §4.4 #5):
-- the day cycle (World/Sky) and the loading screen first (UI/PlayMenu: server boot progress, then the climbing
-- routes prepared on this computer), then the AnimationDriver over every body (D3), the traffic ghosts
-- (Render/VehicleView), PossessionClient (controllers, cameras, devices, Reset routing) and the menu
-- (pick Spicy Rodent, Squirrel, Townsperson, Police or the Police drone; PlayNet.Pick). F kicks
-- (PlayNet.Kick) when on foot as a person. Server messages (PlayNet.Event) become toasts and banners:
-- bites, kicks, RUN OVER, KICKED OUT. The S2 test place runs its own S2Client and this script steps
-- aside there.
-- Live-server robustness (W1 client review): Shift Lock is switched off (Shift is sprint); the Roblox
-- Reset button does nothing until a body is handed over (then PossessionClient routes it to the safe-
-- spot recovery); every wait on the server has a timeout and an on-screen message that works outside
-- Studio (F9 opens the Developer Console); every toast goes to the one toast line at the top.

local container = script.Parent
if container and container.Parent and container.Parent:FindFirstChild("S2Client") then
	return
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")

local InputMap = require("./Input/InputMap")
local Hud = require("./UI/Hud")
local PlayMenu = require("./UI/PlayMenu")
local AnimationDriver = require("./Animation/AnimationDriver")
local PossessionClient = require("./Possession/PossessionClient")
local VehicleView = require("./Render/VehicleView")
local ClientWorld = require("./World/ClientWorld")
local Sky = require("./World/Sky")

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

-- Shift is sprint: Shift Lock would also grab it (and sink it) when a player has it on in Settings
pcall(function()
	(Players.LocalPlayer :: any).DevEnableMouseLock = false
end)
-- the Roblox Reset button would kill the body before PossessionClient routes it: off until then
task.spawn(function()
	for _ = 1, 50 do
		if pcall(function()
			StarterGui:SetCore("ResetButtonCallback", false)
		end) then
			return
		end
		task.wait(0.2)
	end
end)

-- the day cycle, the moon and the backdrop's lights from the server's clock (World/Sky), from the first frame
local skyOk, skyErr = pcall(Sky.start)
if not skyOk then
	warn(`Client: the sky did not start: {skyErr}`)
end

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
	hud.set(
		"Spicy Rodents: the server did not start",
		"Press F9 (Developer Console, Server tab) and send the red lines"
	)
	return
end

local playNet = ReplicatedStorage:WaitForChild("PlayNet", 30)
local bodies = workspace:WaitForChild("Bodies", 30)
local pickR = playNet and playNet:WaitForChild("Pick", 10)
local kickR = playNet and playNet:WaitForChild("Kick", 10)
local eventR = playNet and playNet:WaitForChild("Event", 10)
if bodies == nil or pickR == nil or kickR == nil or eventR == nil then
	hud.set("Spicy Rodents", "The server did not create the town (press F9 and send the red lines)")
	menu.toast("The server did not finish starting: press F9 and send the red lines", 30)
	return
end
pickRemote = pickR :: RemoteEvent
local kickRemote = kickR :: RemoteEvent
local eventRemote = eventR :: RemoteEvent

AnimationDriver.start({ container = bodies })
task.spawn(function()
	VehicleView.start()
	local ghosts = VehicleView.folder()
	if ghosts then
		world.ignore({ ghosts })
	end
end)
local started, clientOrErr = pcall(PossessionClient.start, {
	bodies = bodies :: Instance,
	overview = { position = Vector3.new(0, 120, 260), lookAt = Vector3.zero },
	hud = { set = hud.set, toast = menu.toast },
})
if not started then
	warn(`Client: PossessionClient failed: {clientOrErr}`)
	menu.toast("The controls did not start: press F9 and send the red lines", 30)
	return
end
local client = clientOrErr :: PossessionClient.Client

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
	if InputMap.ignore(io, processed) then
		return
	end
	if io.KeyCode == Enum.KeyCode.F or io.KeyCode == Enum.KeyCode.ButtonX then
		local st = client.state()
		if st.species == "human" and st.device == nil then
			kickRemote:FireServer()
		elseif io.KeyCode == Enum.KeyCode.F then
			menu.toast(
				if st.device
					then "Get out first (E), then F kicks"
					elseif st.species then "Only people can kick: animals pounce with a left click"
					else "Pick a body from the menu first (M)",
				2
			)
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
		menu.toast(if msg.note then tostring(msg.note) else (names[msg.role] or "Here you go"), 4)
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
