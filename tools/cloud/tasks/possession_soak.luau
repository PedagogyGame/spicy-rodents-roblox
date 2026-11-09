--!strict
-- Luau Execution task (spike S2): runs ServerStorage.EngineTests.Possession (the 500-cycle
-- possess / release / swap / leave / recover soak with PlayerLike stubs, plus the 49-slot cap)
-- and returns its JSON. Works on a CI version built from ci.project.json or places/s2.
-- Sent by: node tools/cloud/cloud.mjs run_engine_tests tools/cloud/tasks/possession_soak.luau --version <v> --place ci
local ServerStorage = game:GetService("ServerStorage")
local tests = ServerStorage:FindFirstChild("EngineTests") or error("ServerStorage.EngineTests missing")
local Suite = (require :: any)(tests:FindFirstChild("Possession") :: ModuleScript)
local result = Suite.run({ cycles = 500 })
local s = result.soak
print(
	`Possession: ok={result.ok} possessed={s.possessed} released={s.released} swaps={s.swaps} leaves={s.leaves} errors={#s.errors} invariants={#s.invariantFailures} leaked={s.leakedBodies} resumeMax={s.resumeMaxSeconds}`
)
for _, e in s.errors do
	print("  ERR " .. e)
end
for _, e in s.invariantFailures do
	print("  INV " .. e)
end
print(`cap: admitted={result.cap.admitted} kicked={result.cap.kicked} ok={result.cap.ok}`)
result.placeVersion = game.PlaceVersion
return result
