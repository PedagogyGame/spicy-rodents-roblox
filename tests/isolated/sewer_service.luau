--!strict
-- tests/isolated/sewer_service.luau: cases for tests/unit/sewer_service.spec.luau, run in their own Lune process
-- (tests/lib/Isolated) because they install fake engine globals (tests/lib/FakeEngine).
-- Server/World/SewerService.start on that fake engine: the terrain is carved out of the pipes with one FillBlock
-- Air per box of SewerLayout.carveBoxes() (the list the bake draws its TerrainCarve folder from), at the moment
-- start is called, so after the terrain write that comes before it (Boot/Game: terrain first, then the drains);
-- carve = false carves nothing; the cover goes on the town AI and comes off with stop.
-- Interface: return function(t) (the spec shape)
local SewerLayout = require("@shared/World/SewerLayout")
local TownAI = require("@server/AI/TownAI")
local SewerService = require("@server/World/SewerService")
local FakeEngine = require("@tests/lib/FakeEngine")

type Call = { kind: string, cf: any?, size: any?, material: any? }

-- the parts of a TownAI world the service touches (the cover and the listeners), without the town
local function stubWorld(): TownAI.World
	return {
		listeners = {},
		covered = {},
		cover = nil,
		possessed = {},
		actors = {},
		actorsById = {},
		brains = {},
		now = 0,
		events = {},
	} :: any
end

-- a Terrain that records what is done to it
local function fakeTerrain(calls: { Call }): any
	local terrain = FakeEngine.new("Terrain", "Terrain")
	rawset(terrain, "FillBlock", function(_self: any, cf: any, size: any, material: any)
		table.insert(calls, { kind = "fill", cf = cf, size = size, material = material })
	end)
	rawset(terrain, "WriteVoxels", function()
		table.insert(calls, { kind = "write" })
	end)
	return terrain
end

return function(t)
	local layout = SewerLayout.default() :: SewerLayout.Layout

	t.test("start carves one FillBlock Air per carve box, after the terrain write that came first", function()
		FakeEngine.with(function()
			local calls: { Call } = {}
			local terrain = fakeTerrain(calls)
			rawset(workspace, "Terrain", terrain)
			terrain:WriteVoxels() -- Boot/Game's terrain write (WorldGen/WorldTerrain)
			local world = stubWorld()
			local svc = SewerService.start({ world = world, layout = layout })
			local boxes = layout.carveBoxes()
			t.truthy(#boxes > 0, "the layout has carve boxes")
			t.eq(svc.carved, #boxes)
			t.eq(#calls, #boxes + 1)
			t.eq(calls[1].kind, "write", "the terrain write first")
			for i, b in boxes do
				local c = calls[i + 1]
				t.eq(c.kind, "fill")
				t.eq(c.material, Enum.Material.Air)
				local p, s = c.cf.Position, c.size
				t.near(p.X, (b.x0 + b.x1) / 2, 1e-4)
				t.near(p.Y, (b.y0 + b.y1) / 2, 1e-4)
				t.near(p.Z, (b.z0 + b.z1) / 2, 1e-4)
				t.near(s.X, b.x1 - b.x0, 1e-4)
				t.near(s.Y, b.y1 - b.y0, 1e-4)
				t.near(s.Z, b.z1 - b.z0, 1e-4)
				-- on the 4-stud voxel grid, so no partial voxel is left to smooth into a blob
				for _, v in { b.x0, b.x1, b.y0, b.y1, b.z0, b.z1 } do
					t.near(v / 4, math.floor(v / 4 + 0.5), 1e-9, "on the grid")
				end
			end
			-- the cover is on the world, and comes off with stop
			t.truthy(world.cover ~= nil, "cover installed")
			t.eq(#world.listeners, 1, "one listener")
			svc:stop()
			t.eq(world.cover, nil)
			t.eq(#world.listeners, 0)
		end)
	end)

	t.test("carve = false carves nothing; carve() on its own takes any terrain and box list", function()
		FakeEngine.with(function()
			local calls: { Call } = {}
			local terrain = fakeTerrain(calls)
			rawset(workspace, "Terrain", terrain)
			local svc = SewerService.start({ world = stubWorld(), layout = layout, carve = false })
			t.eq(svc.carved, 0)
			t.eq(#calls, 0)
			local n = SewerService.carve(terrain, { { x0 = 0, x1 = 4, y0 = -8, y1 = -4, z0 = 4, z1 = 12 } })
			t.eq(n, 1)
			t.eq(calls[1].size.Z, 8)
			t.eq(calls[1].cf.Position.Y, -6)
		end)
	end)
end
