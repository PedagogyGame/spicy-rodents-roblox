--!strict
-- ServerScriptService.S11.S11Main (places/s11 only): starts the drone far-view test.
local S11World = (require :: any)(script.Parent:WaitForChild("S11World"))
S11World.start()
