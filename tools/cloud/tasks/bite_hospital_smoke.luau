--!strict
-- Luau Execution task script: the bite-to-hospital sequence in the engine (tests/engine/BiteHospital):
-- a collapse, the crowd, the ambulance and its crew, the bed, the cure in the hospital and the walk
-- home; then a bitten person a player holds, told what to do and cured by standing in the hospital.
-- Sent by: node tools/cloud/cloud.mjs run_engine_tests tools/cloud/tasks/bite_hospital_smoke.luau --version <v>
--          --place ci --inject ci.project.json --inject-exclude generated
-- The run steps up to about 30 minutes of game time by hand (0.1 s frames).

local ServerStorage = game:GetService("ServerStorage")

local engineTests = ServerStorage:FindFirstChild("EngineTests")
if not engineTests then
	error("ServerStorage.EngineTests missing: run with --inject ci.project.json")
end

local Module = engineTests:FindFirstChild("BiteHospital") :: ModuleScript
local BiteHospital = (require :: any)(Module) :: { run: () -> any }
local started = os.clock()
local result = BiteHospital.run()
print(`BiteHospital: ok={result.ok} failures={#result.failures}`)
for _, f in result.failures do
	print(`  FAIL {f}`)
end
return {
	suite = "BiteHospital",
	ok = result.ok,
	failures = result.failures,
	numbers = result.numbers,
	placeVersion = game.PlaceVersion,
	elapsedSeconds = os.clock() - started,
}
