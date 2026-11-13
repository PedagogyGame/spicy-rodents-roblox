--!strict
-- tools/bake/skylift/Approach: the way to the sky lift and up the hill (lane 7). Placeholder: an empty model.
local Common = require("./Common")

local Approach = {}

function Approach.build(roblox: any, parent: any): any
	local kit0 = Common.worldKit(roblox)
	local m = kit0:model(parent, "xs_lift_approach")
	return m
end

return Approach
