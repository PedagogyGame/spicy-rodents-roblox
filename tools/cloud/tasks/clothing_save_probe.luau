--!strict
-- Luau Execution task (owner D16 #25): the live clothing save (Persistence/PlayerSaves + Cosmetics/Wardrobe) against
-- a real DataStore, two simulated servers on one key (keys under the "ci-clothes-" DataStore only).
-- node tools/cloud/cloud.mjs run_engine_tests tools/cloud/tasks/clothing_save_probe.luau --version <v> --place ci \
--   --inject ci.project.json --inject-exclude generated
-- (Not yet run: the key's Luau Execution permission was off on 2026-11-19. Expect pass.* all true.)
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")
local engineTests = ServerStorage:FindFirstChild("EngineTests") or error("EngineTests missing")
local ClothingSave = (require :: any)(engineTests:FindFirstChild("ClothingSave") :: ModuleScript)
local result = ClothingSave.run()
print("ClothingSave: " .. HttpService:JSONEncode(result))
return result
