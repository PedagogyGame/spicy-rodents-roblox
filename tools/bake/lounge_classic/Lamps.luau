--!strict
-- tools/bake/lounge_classic/Lamps: THE GILDED ACORN's light (filled in by the next step).
-- Interface: build(kit, root, venue) -> (lights, shadowed). No side effects on require.

local Kit = require("../alley/Kit")

local Lamps = {}

function Lamps.build(kit: Kit.Kit, root: any, _venue: any): (number, number)
	kit:model(root, "Lamps")
	return 0, 0
end

return Lamps
