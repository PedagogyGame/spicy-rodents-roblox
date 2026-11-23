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
local Import = require("./Import")
local Flags = Import.shared("Config/Flags") :: typeof(require("../shared/Config/Flags"))

-- The movement validator runs LOG-ONLY in the live game since 2026-11-21: version 51, the first the owner played with
-- its enforcement on, snapped his honest squirrel back to the start after a few seconds and lagged. Nothing is pinned
-- or snapped; every server system reads the newest packet's place (Movement/MovementService.heldPlace); a failure in
-- judging a packet is caught (MovementService.packet). Turn it back on only after the validator has been seen clean in
-- the real engine with real clients (docs/HANDOFF.md section 0). The specs keep the flag's default (on).
Flags.set("moveValidatorEnforce", false)

print("[SpicyRodents] first playable build: starting")
local ok, err = xpcall(function()
	return Game.start({})
end, debug.traceback)
if not ok then
	warn(`[SpicyRodents] boot failed: {err}`)
	ReplicatedStorage:SetAttribute("BootError", tostring(err))
	ReplicatedStorage:SetAttribute("BootStage", "The server failed to start the town (see View > Output)")
end

-- the loading screen's aerial (owner D39): the image behind the uploaded Decal 74058696275307, for the clients
-- (Client/UI/PlayMenu reads the LoadingImage attribute; the Decal's thumbnail is the fallback)
task.spawn(function()
	pcall(function()
		local model = game:GetService("InsertService"):LoadAsset(74058696275307)
		local decal = model:FindFirstChildWhichIsA("Decal", true)
		if decal and decal.Texture ~= "" then
			game:GetService("ReplicatedStorage"):SetAttribute("LoadingImage", decal.Texture)
		end
		model:Destroy()
	end)
end)
