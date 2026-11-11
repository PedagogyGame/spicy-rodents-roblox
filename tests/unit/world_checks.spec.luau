--!strict
-- WorldBuild exit checks in Lune (BUILD_PLAN §4.4 #7): on the bake plans, every route sample lies
-- within surfaceRadius + 0.3 u of geometry or terrain except harvest_patches.json; every exterior door
-- is reachable from a sidewalk; no solid overlap; a Skyline part for every building; the hospital's
-- 8 rooms and the station's drone console exist. The engine runs the same module (WorldBuild).
local WorldChecks = require("@worldgen/WorldChecks")

return function(t)
	t.test("WorldChecks.run: all exit checks pass", function()
		local r = WorldChecks.run()
		print(
			`      routes {r.routes.checked} ({r.routes.samples} samples), off-geometry {#r.routes.failures}, patched still off {r.routes.patchedFailing}; doors {r.doors.doors}; solids {r.solids}; skyline {r.skyline.buildings}`
		)
		t.eq(#r.failures, 0, table.concat(r.failures, " | "))
		t.eq(r.routes.checked, 1332)
		t.eq(r.hospitalRooms, 8)
		t.truthy(r.droneConsole)
		t.truthy(r.doors.doors >= 80)
		t.eq(r.interiors.lots, 6)
		t.eq(r.interiors.rooms, 31)
	end)
end
