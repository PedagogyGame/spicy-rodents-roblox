--!strict
-- The storm drains end to end, the three sewer lanes joined (the motor on the real bake, World/SewerService on the
-- real town AI, World/SewerAmbience on the client): down the drain at P1's grate, through the chamber, up at the far
-- corner, the police losing it at the grate. The case lives in tests/isolated/sewers_play.luau and runs in its own
-- Lune process (tests/lib/Isolated says why).
-- And the engine check written for when Luau Execution returns (tests/engine/Sewers), held here where it can be:
-- the points it reads the carve at lie inside the pipes, and its module boxes are the manifest's.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local SewerLayout = require("@shared/World/SewerLayout")
local EngineSewers = require("@tests/engine/Sewers")
local Isolated = require("@tests/lib/Isolated")

return function(t)
	Isolated.register(t, "tests/isolated/sewers_play")

	t.test("the engine check: its carve samples lie in the pipes, its module boxes are the manifest's", function()
		local layout = SewerLayout.default() :: SewerLayout.Layout
		local samples = EngineSewers.samples(layout)
		t.truthy(#samples > 500, `{#samples} samples`)
		local outside = 0
		for _, q in samples do
			local space = layout.contains(q.x, q.y, q.z)
			if space ~= (layout.pipe(q.pipe) :: SewerLayout.Pipe).space then
				outside += 1
			end
		end
		t.eq(outside, 0, "samples outside their pipe")
		local art = serde.decode("json", fs.readFile("data/art/sewer_modules.json"))
		for key, m in art.modules do
			local lo, hi = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
			for _, mesh in m.meshes do
				for i = 1, 3 do
					lo[i] = math.min(lo[i], mesh.centre[i] - mesh.size[i] / 2)
					hi[i] = math.max(hi[i], mesh.centre[i] + mesh.size[i] / 2)
				end
			end
			local box = EngineSewers.ART_BOX[key]
			t.truthy(box ~= nil, `{key} has a box`)
			for i = 1, 3 do
				t.near(box.size[i], hi[i] - lo[i], 0.01, `{key} size {i}`)
				t.near(box.centre[i], (hi[i] + lo[i]) / 2, 0.01, `{key} centre {i}`)
			end
		end
	end)
end
