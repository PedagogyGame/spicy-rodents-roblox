--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Main
-- Client entry (BUILD_PLAN §1.3, §4.4 #5): HUD first (the owner-facing rule: say what this is and
-- what to press, show progress), then the AnimationDriver over every body (D3) and PossessionClient
-- (controllers, cameras, devices, Reset routing). Bodies live in workspace.Bodies (Server/Actors/
-- ActorsRuntime). The S2 test place runs its own S2Client and this script steps aside there.

local container = script.Parent
if container and container.Parent and container.Parent:FindFirstChild("S2Client") then
	return
end

local Hud = require("./UI/Hud")
local AnimationDriver = require("./Animation/AnimationDriver")
local PossessionClient = require("./Possession/PossessionClient")

local hud = Hud.start()
hud.set("Spicy Rodents (W1 build)", "Loading the town…")
local bodies = workspace:WaitForChild("Bodies", 60)
if bodies == nil then
	hud.set("Spicy Rodents (W1 build)", "No bodies in this place yet: the server has not started the town")
	return
end
AnimationDriver.start({ container = bodies })
PossessionClient.start({
	bodies = bodies,
	overview = { position = Vector3.new(0, 120, 260), lookAt = Vector3.zero },
	hud = hud,
})
