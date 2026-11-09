--!strict
-- Luau Execution task (spike S15): DataStoreService availability probe plus the ProfileStore and
-- receipt handler against the real store (keys under the "ci-s15-" DataStore only).
-- node tools/cloud/cloud.mjs run_engine_tests tools/cloud/tasks/receipts_probe.luau --version <v> --place ci \
--   --inject ci.project.json --inject-exclude generated
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")
local engineTests = ServerStorage:FindFirstChild("EngineTests") or error("EngineTests missing")
local Receipts = (require :: any)(engineTests:FindFirstChild("Receipts") :: ModuleScript)
local result = Receipts.run()
print("Receipts: " .. HttpService:JSONEncode(result))
return result
