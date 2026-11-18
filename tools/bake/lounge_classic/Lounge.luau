--!strict
-- tools/bake/lounge_classic/Lounge: THE GILDED ACORN, the 1940s lounge (f3_lounge_classic in data/expansion.json;
-- brief v2 "Lounge one", addendum D14), baked as parts in the venue's local frame (tools/bake/alley/Kit: X across
-- the frontage, Y up from the finished floor, D into the building; the front is at -D). The building is sealed:
-- no window, vent or chimney opens, and the double door's leaves are solid. A person goes in and out through the
-- door's prompt (Server/Attractions/LoungeService); a squirrel has no way in.
--   Shell     the brick hall (Shell), its black-and-gold front with the recessed entry, the canopy, the sign THE
--             GILDED ACORN and the acorn on the parapet, the forecourt where the two guards stand.
--   Interior  (Interior) the long polished bar with its brass rail and stools, the back bar (cups, the coffee urn,
--             the cocoa pot, the snow-cone machine; no bottles anywhere), four leather booths, club chairs round
--             small tables, the stage with a grand piano and the radio, the fireplace, panelling and the ceiling.
--   Lamps     (Lamps) warm low light: pendants over the bar, booth lamps, sconces, two chandeliers, the stage's
--             spots, the fire, the back bar's glow, the canopy light: LIGHT_BUDGET lights, SHADOW_BUDGET shadowed.
-- The model carries Venue, Parts, Lights, Shadows, and Door* attributes (the door's world points) for the service.
-- Interface: build(kit, parent, venue) -> Model; dimensions and budgets below.
-- No side effects on require. Lune only (@lune/roblox through the Kit).

local Kit = require("../alley/Kit")
local Shell = require("./Shell")
local Interior = require("./Interior")
local Lamps = require("./Lamps")
local Style = require("./Style")

local Lounge = {}

Lounge.PART_BUDGET = 800 -- the bake's cap (data/expansion.json allows 1300; phones come first)
Lounge.LIGHT_BUDGET = 22 -- PointLights, SpotLights and SurfaceLights together
Lounge.SHADOW_BUDGET = 3 -- of those, casting shadows

function Lounge.build(kit: Kit.Kit, parent: any, venue: any): any
	local roblox = kit.roblox
	local root = kit:model(parent, venue.id)
	root.ModelStreamingMode = roblox.Enum.ModelStreamingMode.Atomic
	root.LevelOfDetail = roblox.Enum.ModelLevelOfDetail.SLIM
	root:SetAttribute("Venue", venue.id)
	local start = kit.count

	Shell.build(kit, root, venue)
	Interior.build(kit, root, venue)
	local lights, shadows = Lamps.build(kit, root, venue)

	-- the door's points for the service: outside on the landing, inside past the leaves (world)
	local D = Style.DOOR_D
	root:SetAttribute("DoorOutside", kit:cf(0, 0, D - 2).Position)
	root:SetAttribute("DoorInside", kit:cf(0, 0, D + Style.WALL + 2.5).Position)
	root:SetAttribute("Parts", kit.count - start)
	root:SetAttribute("Lights", lights)
	root:SetAttribute("Shadows", shadows)
	return root
end

return Lounge
