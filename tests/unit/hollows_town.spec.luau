--!strict
-- The hollow trees in the baked town (build/Town.rbxm: lune run tools/bake/main.luau; Shared/World/HollowLayout,
-- Server/World/HollowShell): every ground hole and the 8 studs a squirrel runs in on are open ground (nothing of
-- the town in the way, the ground level with the hole), and no piece of a hollow's shell stands in a part of the town.
local fs = require("@lune/fs")
local HollowLayout = require("@shared/World/HollowLayout")
local BakedWorld = require("@tests/lib/BakedWorld")

return function(t)
	local layout = HollowLayout.default() :: HollowLayout.Layout

	t.test("every hole's run-in is open ground, and no shell piece stands in the town", function()
		t.truthy(fs.isFile("build/Town.rbxm"), "build/Town.rbxm (lune run tools/bake/main.luau)")
		local town = BakedWorld.load("build/Town.rbxm")
		for _, h in layout.hollows do
			for _, m in h.mouths do
				if m.opens ~= "ground" then
					continue
				end
				local ol = math.sqrt(m.out[1] ^ 2 + m.out[3] ^ 2)
				local ox, oz = m.out[1] / ol, m.out[3] / ol
				for d = 0, 8, 0.5 do
					local x, z = m.x + ox * d, m.z + oz * d
					local g = town.groundAt(x, z, m.y + 3)
					local b = town.blocker(x, z, g, 0.8)
					t.eq(b and b.path, nil, `{h.id} {m.name}: {d} studs out`)
					t.truthy(math.abs(g - m.y) < 1.5, `{h.id} {m.name}: the ground {d} studs out at {g} (hole {m.y})`)
				end
			end
		end
		for _, h in layout.hollows do
			-- its own tree, or the log's own lot (its marker and the foundation sunk under the ground)
			local own = if h.trunk then `Tree_{h.trunk}.` else "Lots.north_hollow_log."
			for _, pc in h.parts do
				-- (a knothole's oval is on the bark outside; a floor lies on the ground under the bark by design)
				if pc.role == "knothole" or pc.role == "floor" then
					continue
				end
				local x, y, z = pc.p[1], pc.p[2], pc.p[3]
				local xv, yv = pc.xv, pc.yv
				local zv = {
					xv[2] * yv[3] - xv[3] * yv[2],
					xv[3] * yv[1] - xv[1] * yv[3],
					xv[1] * yv[2] - xv[2] * yv[1],
				}
				local hits = town.overlapBox(
					x,
					y,
					z,
					{ xv, yv, zv },
					{ pc.size[1] / 2 - 0.02, pc.size[2] / 2 - 0.02, pc.size[3] / 2 - 0.02 },
					function(p: BakedWorld.Part): boolean
						-- not its own tree (the bark mesh and the invisible trunk colliders round the cavity), nor any
						-- mesh (BakedWorld takes a MeshPart as its whole box: a tree's is its canopy)
						if own and string.find(p.path, own, 1, true) or p.shape == "box" then
							return false
						end
						return p.visible or p.collide
					end
				)
				local names = {}
				for _, p in hits do
					table.insert(names, p.path)
				end
				t.eq(#names, 0, `{h.id} {pc.role}: {table.concat(names, ", ")}`)
			end
		end
	end)
end
