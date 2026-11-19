--!strict
-- ReplicatedStorage.Shared.World.GroundPlate
-- The baked town's ground plates: thin non-colliding parts laid over the terrain (lot ground, banks, court tiles, pads,
-- road and trolley-track segments) that a squirrel stands on as drawn. The client's motor finds them
-- (Client/World/ClientWorld.groundAt: the topmost plate over the colliding surface) and so does the server's floor ray
-- (Server/Movement/ValidatorWorld.engineRays), by this one rule: the two must agree, or a body walking on a plate that
-- lies more than ValidatorWorld.C.FLOOR_NEAR over the terrain is a climb (validator round 5 measured 401 of 1185 points
-- of the town's 237 plates over it, a tennis court up to 1.5 studs, a trolley track's segment 3.3:
-- tests/unit/validator_floors.spec.luau).
-- Interface: FOLDERS (the town's folders that hold plates); like(name, sizeY, transparency) -> boolean
-- Pure. No side effects on require.

local GroundPlate = {}

-- Town.<folder>: the only folders whose non-colliding parts are ground
GroundPlate.FOLDERS = table.freeze({ "Lots", "Roads" })

-- Is a non-colliding part of the town a ground plate worth standing on? Opaque only (water sheets are translucent);
-- lot ground and paving (thin Greybox), banks, court tiles, pads and road segments. Plinths, foundations, lamp bases
-- and thick grey boxes are bodies, not ground.
function GroundPlate.like(name: string, sizeY: number, transparency: number): boolean
	if transparency > 0 then
		return false
	end
	if string.sub(name, 1, 7) == "Greybox" then
		return sizeY <= 0.25
	end
	return string.sub(name, 1, 4) == "Bank"
		or string.sub(name, 1, 4) == "Tile"
		or string.sub(name, 1, 3) == "Pad"
		or string.sub(name, 1, 3) == "Seg"
end

return GroundPlate
