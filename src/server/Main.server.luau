--!strict
-- ServerScriptService.Server.Main
-- The only script that starts loops (BUILD_PLAN §1.3). Starts the first playable build
-- (Server/Boot/Game: sky, terrain, data, traffic, actors, possession, roles, devices, the play
-- remotes). A boot failure is published (ReplicatedStorage BootError) so the loading screen says so
-- instead of sitting silent (HANDOFF §4 owner-facing build rule). The S2 and S11 spike places run
-- their own harness and this script steps aside there.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- spike places (places/s2, places/s11) carry their own Main beside this one
if ServerScriptService:FindFirstChild("S2Main", true) or ServerScriptService:FindFirstChild("S11Main", true) then
	return
end

local Game = require("./Boot/Game")

print("[SpicyRodents] first playable build: starting")
local ok, err = xpcall(function()
	return Game.start({})
end, debug.traceback)
if not ok then
	warn(`[SpicyRodents] boot failed: {err}`)
	ReplicatedStorage:SetAttribute("BootError", tostring(err))
	ReplicatedStorage:SetAttribute("BootStage", "The server failed to start the town (see View > Output)")
end
