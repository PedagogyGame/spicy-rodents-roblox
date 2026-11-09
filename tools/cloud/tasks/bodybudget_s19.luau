--!strict
-- Luau Execution task (spike S19): the body budget at brief v2's floors (tests/engine/BodyBudget).
-- node tools/cloud/cloud.mjs run_engine_tests tools/cloud/tasks/bodybudget_s19.luau --version <v> --place ci \
--   --inject ci.project.json --inject-exclude generated
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")
local engineTests = ServerStorage:FindFirstChild("EngineTests") or error("EngineTests missing")
local BodyBudget = (require :: any)(engineTests:FindFirstChild("BodyBudget") :: ModuleScript)
local result = BodyBudget.run({ wallLimitSeconds = 200 })
for _, v in result.variants do
	print(`BodyBudget {v.name}: ` .. HttpService:JSONEncode(v.pass or v.error or v.skipped))
end
return result
