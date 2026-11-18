-- SAMPLE ONLY: Disabled until explicitly activated and wired to your real Studio objects.
-- DO NOT insert this script into an existing place with ENABLE = true without review.
local ENABLE = false
if not ENABLE then return end

local features = script.Parent:WaitForChild("SpicyFeatures")
local WalletService = require(features.WalletService)
local PoolZoneService = require(features.PoolZoneService)
local AlleyPatrolService = require(features.AlleyPatrolService)
local RoofRouteService = require(features.RoofRouteService)
local PaintballService = require(features.PaintballService)
local SkyLiftService = require(features.SkyLiftService)

local wallet = WalletService.new(0) -- session only; persistence not implemented
-- Explicitly place these named objects in Workspace before enabling their services:
--  SpicyPoolZone (BasePart), SpicyPaintballArena (BasePart),
--  SpicyLiftCabin/SpicyLiftStart/SpicyLiftEnd (anchored BaseParts),
--  AlleyNPC (Humanoid Model), AlleyWaypoints (Folder), RoofRoot (BasePart).
-- Uncomment only the service you actually want after setup and in-Studio testing.
-- local pool = PoolZoneService.new(workspace.SpicyPoolZone); pool:Start()
-- local paintball = PaintballService.new(workspace.SpicyPaintballArena)
-- local lift = SkyLiftService.new(workspace.SpicyLiftCabin,workspace.SpicyLiftStart,workspace.SpicyLiftEnd)
-- local alley = AlleyPatrolService.new(workspace.AlleyNPC,workspace.AlleyWaypoints); alley:Start()
-- local roof = RoofRouteService.new(workspace.RoofRoot.CFrame)
-- Paintball:Join / :StartRound / :Fire must be called by a separately validated SERVER bridge.
-- Lift:Board must be called on the server after checking the player's permission.
-- NEVER connect a wallet mutation directly to arbitrary client-provided requests.
