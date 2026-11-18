--!strict
-- tools/bake/lounge_classic/Interior: THE GILDED ACORN's room (filled in by the next step).
-- Interface: build(kit, root, venue) -> Model "Interior". No side effects on require.

local Kit = require("../alley/Kit")

local Interior = {}

function Interior.build(kit: Kit.Kit, root: any, _venue: any): any
	return kit:model(root, "Interior")
end

return Interior
