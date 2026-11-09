--!strict
-- ServerScriptService.S2.S2Main (places/s2 only): starts the possession test harness.
local S2Harness = (require :: any)(script.Parent:WaitForChild("S2Harness"))
S2Harness.start()
