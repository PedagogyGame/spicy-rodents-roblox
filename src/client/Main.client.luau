--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Main
-- Client entry of the first playable build (owner directive 2026-11-09; BUILD_PLAN §1.3, §4.4 #5):
-- the day cycle (World/Sky) and the loading screen first (UI/PlayMenu: server boot progress, then the climbing
-- routes prepared on this computer), then the AnimationDriver over every body (D3), the traffic ghosts
-- (Render/VehicleView), PossessionClient (controllers, cameras, devices, Reset routing) and the menu
-- (pick Spicy Rodent, Squirrel, Townsperson, Police or the Police drone; PlayNet.Pick). F kicks
-- (PlayNet.Kick) when on foot as a person. Server messages (PlayNet.Event) become toasts and banners:
-- bites, kicks, RUN OVER, KICKED OUT, and "med": what a bitten player must do (go to the hospital).
-- UI/WalletHud keeps the wallet's balance in the corner (and the pocket money and pass lines).
-- The bite-to-hospital sequence is drawn by UI/SpeechBubbles (what townspeople say) and
-- Render/MedicalView (red eyes, a patient out of sight); AnimationDriver sits a patient down.
-- The sky lift (Client/Rides/SkyLiftView: the six cabins drawn from the shared clock) and the Lookout's telescope
-- (Client/Rides/Telescope, entered on the server's "telescope" event) start after the minigames.
-- The S2 test place runs its own S2Client and this script steps aside there.
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
local MedicalView = require("./Render/MedicalView")
local SpeechBubbles = require("./UI/SpeechBubbles")
local WalletHud = require("./UI/WalletHud")
local ClientWorld = require("./World/ClientWorld")
local MinigameClient = require("./Minigames/MinigameClient")
local Sky = require("./World/Sky")
local CameraRig = require("./Camera/CameraRig")
local FarTown = require("./Render/FarTown")
local SkyLiftView = require("./Rides/SkyLiftView")
local Telescope = require("./Rides/Telescope")

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
-- the wallet in the corner, always (the server writes the balance on the Player: Server/Economy/Credits)
local walletOk, walletErr = pcall(WalletHud.start)
if not walletOk then
	warn(`Client: WalletHud failed: {walletErr}`)
	menu.toast("The wallet display did not start: press F9 and send the red lines", 10)
end
-- what townspeople say, and what a bitten person looks like (owner 2026-11-10)
task.spawn(function()
	local okS, errS = pcall(SpeechBubbles.start, { bodies = bodies :: Instance })
	if not okS then
		warn(`Client: SpeechBubbles failed: {errS}`)
		menu.toast("Speech bubbles did not start: press F9 and send the red lines", 10)
	end
	local okV, errV = pcall(MedicalView.start, { bodies = bodies :: Instance })
	if not okV then
		warn(`Client: MedicalView failed: {errV}`)
		menu.toast("The infection visuals did not start: press F9 and send the red lines", 10)
	end
end)
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
	hud = { set = hud.set, toast = menu.toast, meter = hud.meter },
})
if not started then
	warn(`Client: PossessionClient failed: {clientOrErr}`)
	menu.toast("The controls did not start: press F9 and send the red lines", 30)
	return
end
local client = clientOrErr :: PossessionClient.Client

-- the bowling alley's games: walk up to a lane, the dartboard or the fortune teller and press E
task.spawn(function()
	local okM, errM = pcall(MinigameClient.start, {
		state = client.state,
		current = client.current,
		toast = menu.toast,
		refreshCamera = client.refreshCamera,
		flushInput = client.flushInput,
	})
	if not okM then
		warn(`Client: MinigameClient failed: {errM}`)
	end
end)

-- the sky lift's cabins (drawn here from the clock) and the Lookout's telescope (its HUD lines; no walking while
-- looking; the usual HUD and camera back after)
local okSL, errSL = pcall(SkyLiftView.start)
if not okSL then
	warn(`Client: SkyLiftView failed: {errSL}`)
end
-- the town from far off (the Lookout, the cabins, the drone): far houses with roofs and lit windows, lamp dots
-- and tree crowns where the real lots have streamed out
local okFar, errFar = pcall(FarTown.start)
if not okFar then
	warn(`Client: FarTown failed: {errFar}`)
end
-- the wait for a booked cabin, counted down on the HUD (the usual HUD back once seated or given up)
pcall(SkyLiftView.watchWait, function(title: string?, hint: string?)
	if title then
		hud.set(title, hint or "")
	else
		client.refreshCamera()
	end
end)
pcall(Telescope.start, {
	hud = function(title: string?, hint: string?)
		if title then
			hud.set(title, hint or "")
		else
			client.refreshCamera()
		end
	end,
	onChange = function(on: boolean)
		InputMap.setCharacterControls(not on and client.state().device == nil)
		-- the server streams the town the telescope looks at; stepping back gives the Lookout back
		local look = if on then nil else game:GetService("ReplicatedStorage"):FindFirstChild("SkyLiftLook")
		if look and look:IsA("RemoteEvent") then
			look:FireServer("off")
		end
	end,
})

-- keep the help panel in step with vehicles and the drone
local lastDevice: string? = nil
game:GetService("RunService").Heartbeat:Connect(function()
	-- the orbit camera owns the mouse on foot; the menu needs the cursor back while it is up
	CameraRig.wantCursor("menu", menu.isOpen())
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
	-- (not while a minigame is open: F and gamepad X are that game's keys then)
	if InputMap.kicks(io.KeyCode.Name, Players.LocalPlayer:GetAttribute("InMinigame")) then
		local st = client.state()
		if st.species == "human" and st.device == nil then
			kickRemote:FireServer()
		elseif io.KeyCode == Enum.KeyCode.F then
			menu.toast(
				if st.device == "ride"
					then "No kicking from a sky-lift cabin"
					elseif st.device then "Get out first (E), then F kicks"
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
	elseif kind == "telescope" then
		-- the Lookout's telescope (Server/Rides/SkyLiftService): look through the baked one
		local exp = workspace:FindFirstChild("Expansion")
		local hill = exp and exp:FindFirstChild("F4") and (exp :: any).F4:FindFirstChild("f3_hilltop")
		local scope = hill and hill:FindFirstChild("Telescope", true)
		local post = workspace:FindFirstChild("SkyLiftService")
		local prompt = post
			and post:FindFirstChild("TelescopePost")
			and (post :: any).TelescopePost:FindFirstChild("SkyLiftPrompt", true)
		if scope == nil or not Telescope.enter(scope, prompt) then
			menu.toast(tostring(msg.text or "The telescope has not loaded yet"), 3)
		end
	elseif kind == "notice" then
		-- something the game did to you that you should read (a bowling ball knocked you off a lane)
		menu.toast(tostring(msg.text), 4)
	elseif kind == "bite" then
		menu.toast(`CHOMP! "{msg.line}"   +{msg.delta} Power   ({msg.bites} bites)`, 2.5)
	elseif kind == "bitten" then
		menu.toast(`The rodent bit you! You shout: "{msg.line}"`, 2.5)
	elseif kind == "med" then
		-- the bite-to-hospital sequence: what is happening to you and what to do about it
		menu.toast(tostring(msg.text), if type(msg.secs) == "number" then msg.secs else 6)
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
