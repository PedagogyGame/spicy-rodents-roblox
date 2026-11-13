--!strict
-- tools/bake/skylift/Bake: builds Workspace.Expansion.F4 (the sky lift, its approach and the Lookout) in memory.
-- tools/bake/skylift.luau writes it to build/Expansion_F4.rbxm; the unit specs build it in-process.
-- Contents of the root Folder "F4":
--   f4_lift_base            the base station (Station.luau; Atomic)
--   f4_lift_tower_1..9      the line towers (Towers.luau; Atomic each)
--   f4_lift_base_Skyline    masts, crossarms and the rope's open spans (Towers.skyline; Persistent, <= 40 parts)
--   CabinTemplate           the cabin the client clones six times (Cabin.luau; Persistent)
--   f4_lift_summit          the summit station in the Lookout's lift hall (Summit.luau; Atomic)
--   f3_hilltop (+ its Skyline)  THE LOOKOUT: tools/bake/lookout/Lookout.luau's build(kit, parent, venue) when that
--                           file exists (lane 3), else STUB: a plinth greybox carrying attribute Stub = true
--   xs_lift_approach        Lift Road, the car park, the walks, lamps, the hill trail and the hill's dressing
--                           (Approach.luau)
--   xs_lift_country         the farmland under the line: fields, hedges, the farm, the orchard, the brook and
--                           pond, the lane and the maintenance hut, stone walls (Countryside.luau)
-- Interface: build(roblox) -> (Folder, report); report = { models = { [name]: parts }, total, lookout = "built" |
--   "stub" }

local fs = require("@lune/fs")

local Approach = require("./Approach")
local Cabin = require("./Cabin")
local Common = require("./Common")
local Countryside = require("./Countryside")
local Kit = require("../alley/Kit")
local SkyLift = require("../../../src/shared/Rides/SkyLift")
local Station = require("./Station")
local Summit = require("./Summit")
local Towers = require("./Towers")

local Bake = {}

Bake.LOOKOUT = "tools/bake/lookout/Lookout.luau"

-- The Lookout's builder when lane 3 has written it; nil until then.
local function lookoutBuilder(): any
	if fs.isFile(Bake.LOOKOUT) then
		return require("../lookout/Lookout") :: any
	end
	return nil
end

-- Until the Lookout is built: its floor as a plinth from floorY down to ground.min - 2 over the footprint, so the
-- summit platforms stand on something (no shell, no rooms, no terrace).
function Bake.stubLookout(kit: Kit.Kit, parent: any, v: any): any
	local m = Common.venueModel(kit, parent, v.id, v, v.partBudget or 1000, "Atomic")
	m:SetAttribute("Stub", true)
	local hw, hd = v.footprint.w / 2, v.footprint.d / 2
	kit:box(m, "StubPlinth", -hw, hw, v.ground.min - 2 - v.floorY, 0, -hd, hd, Common.CONCRETE, "Concrete")
	return m
end

local function count(root: any): number
	local n = if root:IsA("BasePart") then 1 else 0
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

function Bake.build(roblox: any): (any, any)
	local folder = roblox.Instance.new("Folder")
	folder.Name = "F4"
	local st = SkyLift.stations()
	local baseV = Common.venue(st.base.venue)
	local topV = Common.venue(st.summit.venue)

	Station.build(Kit.new(roblox, Common.place(baseV)), folder, baseV)
	Towers.build(roblox, folder)
	Towers.skyline(roblox, folder)
	-- the cabin template: its origin TEMPLATE_DEPTH under the base bullwheel, yaw 0
	Cabin.build(
		Kit.new(roblox, {
			x = st.base.wheel.x,
			z = st.base.wheel.z,
			floorY = st.base.floorY - Cabin.TEMPLATE_DEPTH,
			yaw = 0,
		}),
		folder
	)
	local topKit = Kit.new(roblox, Common.place(topV))
	Summit.build(topKit, folder, topV)
	local builder = lookoutBuilder()
	local lookout = "stub"
	if builder then
		builder.build(Kit.new(roblox, Common.place(topV)), folder, topV)
		lookout = "built"
	else
		Bake.stubLookout(Kit.new(roblox, Common.place(topV)), folder, topV)
	end
	Approach.build(roblox, folder)
	Countryside.build(roblox, folder)

	local report = { models = {}, total = 0, lookout = lookout }
	for _, c in folder:GetChildren() do
		local n = count(c)
		report.models[c.Name] = n
		report.total += n
	end
	return folder, report
end

return Bake
