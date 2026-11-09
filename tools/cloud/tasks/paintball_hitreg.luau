--!strict
-- Luau Execution task (spike S18): the paintball arena beside the S5 town population.
-- node tools/cloud/cloud.mjs run_engine_tests tools/cloud/tasks/paintball_hitreg.luau --version <v> --place ci \
--   --inject ci.project.json --inject-exclude generated
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")
local engineTests = ServerStorage:FindFirstChild("EngineTests") or error("EngineTests missing")
local Paintball = (require :: any)(engineTests:FindFirstChild("Paintball") :: ModuleScript)
local result = Paintball.run({ wallLimitSeconds = 200 })
for _, c in result.conditions do
	print(`Paintball rtt={c.rttMs}: ` .. HttpService:JSONEncode(c.pass))
end
return result
