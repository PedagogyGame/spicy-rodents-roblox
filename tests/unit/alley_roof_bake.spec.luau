--!strict
-- The lane hall's raised roof as baked (tools/bake/alley/Roof, the model HallRoof; BRIEF_ADDENDUM D9, D10, owner
-- question Q2's default), on the alley baked in memory by its own bake code (tests/lib/BakedWorld.bakeAlley):
--   * every rafter route (Shared/Attractions/AlleyRoof: the truss plates, the light rails, the aisle braces) stands on
--     a colliding part along its whole length, within 0.05;
--   * the body (1.6 wide, 1.7 high) swept along every rafter route meets nothing, seen or colliding: the lattice
--     planes, the top chords, the hangers, the lamps and the walls all stand clear;
--   * a leap from any rafter (its apex plus the body) stays under the deck, which covers the whole hall; the walls
--     close the roof space; a drop from a plate between the rails lands on the hall's floor (Q10: a squirrel can drop
--     onto a lane or an approach);
--   * a lamp stands at every point RafterWatch lights from (AlleyRoof.lamps), the score monitors and the masking face
--     keep their places and nothing of the roof runs into them.
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local AlleyRoof = require("@shared/Attractions/AlleyRoof")
local Registry = require("@shared/Routes/Registry")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local BakedWorld = require("../lib/BakedWorld")

local R = AlleyRoof
local HR = R.HALL_ROOF

return function(t)
	local world, place, root = BakedWorld.bakeAlley()
	local records = R.records(place)
	local registry = Registry.fromRecords(records :: any)
	local function rafters(): { Registry.Route }
		local out = {}
		for _, r in records do
			if R.isRafter(r.id) then
				table.insert(out, registry:get(r.id) :: Registry.Route)
			end
		end
		return out
	end
	local function toLocal(x: number, y: number, z: number): (number, number, number)
		return AlleyLayout.toLocal(place, x, y, z)
	end
	local function toWorld(X: number, Y: number, D: number): (number, number, number)
		return AlleyLayout.toWorld(place, X, Y, D)
	end

	t.test("every rafter route stands on a colliding part along its whole length", function()
		for _, route in rafters() do
			local worst, at = 0, 0
			for i = 0, 200 do
				local p = registry:pointAt(route, i / 200)
				local g = world.groundAt(p.x, p.z, p.y)
				if math.abs(g - p.y) > worst then
					worst, at = math.abs(g - p.y), i / 200
				end
			end
			t.truthy(worst <= 0.05, `route {route.id}: {worst} off its support at t {at}`)
		end
	end)

	t.test("the body swept along every rafter route meets nothing, seen or colliding", function()
		local total = 0
		for _, route in rafters() do
			local hits = BakedWorld.clearance(world, registry, route, { step = 0.25 })
			local names = {}
			for _, b in hits do
				table.insert(names, `{b.path} (t {string.format("%.3f", b.t0)}..{string.format("%.3f", b.t1)})`)
			end
			t.eq(#hits, 0, `route {route.id}: {table.concat(names, "; ")}`)
			total += route.length
		end
		print(`      {#rafters()} rafter routes, {string.format("%.0f", total)} st swept clear`)
	end)

	t.test("a leap from any rafter stays under the deck; the deck and the walls close the roof space", function()
		local apex = SquirrelMotor.leapApex()
		for _, route in rafters() do
			for i = 0, 40 do
				local p = registry:pointAt(route, i / 40)
				local rise = apex + 1.7
				-- (another rafter overhead is where a leap from a light rail is meant to go: up onto a plate; 9120's
				-- first 0.6 st is inside the vent's boot, where the drop stands over it)
				local inBoot = toLocal(p.x, p.y, p.z) > R.ELBOW.x0 - 0.1
				local hit, part = world.raycast(p.x, p.y + 0.01, p.z, 0, rise, 0, function(q)
					return q.collide and q.name ~= "Plate" and q.name ~= "Rail" and string.sub(q.name, 1, 5) ~= "Brace"
				end)
				t.truthy(hit == nil or inBoot, `route {route.id} t {i / 40}: a leap meets {part and part.path}`)
				local _, Y = toLocal(p.x, p.y, p.z)
				t.truthy(Y + rise <= HR.deckY0, `route {route.id}: a leap's top {Y + rise} under the deck`)
			end
		end
		-- the deck over the whole hall, from the north wall to the south wall; the strip of the old roof in front
		local function partAt(X: number, Y: number, D: number, name: string): boolean
			local x, y, z = toWorld(X, Y, D)
			for _, p in world.containing(x, y, z) do
				if p.collide and p.name == name then
					return true
				end
			end
			return false
		end
		for X = HR.x0 + 0.5, HR.x1 - 0.5, 4 do
			for D = HR.d0 + 0.3, HR.southD0 - 0.3, 4 do
				t.truthy(partAt(X, (HR.deckY0 + HR.deckY1) / 2 + 0.1, D, "Roof"), `the deck at X {X} D {D}`)
			end
			for D = HR.stripD0 + 0.3, HR.northD0 - 0.3, 2 do
				t.truthy(partAt(X, 12.8, D, "RoofStrip"), `the strip at X {X} D {D}`)
			end
			t.truthy(partAt(X, 18, (HR.northD0 + HR.d0) / 2, "WallNorth"), `the north wall at X {X}`)
			t.truthy(partAt(X, 18, (HR.southD0 + HR.d1) / 2, "WallSouth"), `the south wall at X {X}`)
		end
		for D = HR.d0 + 0.5, HR.d1 - 0.5, 3 do
			t.truthy(partAt((HR.outerX0 + HR.x0) / 2, 18, D, "WallWest"), `the west wall at D {D}`)
			local inDuct = D >= R.DUCT.d0 and D <= R.DUCT.d1
			t.truthy(inDuct or partAt((HR.x1 + HR.outerX1) / 2, 18, D, "WallEast"), `the east wall at D {D}`)
		end
	end)

	t.test("a drop from a plate between the light rails lands on the hall's floor (a lane or an approach)", function()
		local landed = {}
		for i, d in R.TRUSS_D do
			if i <= 8 then
				for p = 1, AlleyLayout.PAIRS do
					local X = AlleyLayout.laneX(2 * p)
					local x, _, z = toWorld(X, 0, d)
					-- (a ray from just under the plate: what a body dropping off its edge meets)
					local _, y = toLocal(x, world.groundAt(x, z, place.floorY + R.CHORD.y0 - 1.6), z)
					t.truthy(y < 0.6, `under plate D {d} at lane {2 * p}: lands at Y {y}`)
					table.insert(landed, y)
				end
			end
		end
		t.eq(#landed, 8 * AlleyLayout.PAIRS)
	end)

	t.test("a lamp at every point RafterWatch lights from; the monitors and the masking face untouched", function()
		local hall = root:FindFirstChild(AlleyLayout.HALL_ROOF.model) :: any
		local lamps = {}
		for _, d in hall:GetDescendants() do
			if d:IsA("BasePart") and d.Material.Name == "Neon" then
				table.insert(lamps, d)
			end
		end
		for _, lp in R.lamps() do
			local x, y, z = toWorld(lp[1], lp[2], lp[3])
			local best = math.huge
			for _, p in lamps do
				local q = p.CFrame.Position
				best = math.min(best, math.sqrt((q.X - x) ^ 2 + (q.Y - y) ^ 2 + (q.Z - z) ^ 2))
			end
			t.truthy(best < 0.5, `a lamp at ({lp[1]}, {lp[2]}, {lp[3]}): the nearest is {best} away`)
		end
		-- the monitors where Lanes hangs them (cy 9.6, cd -3.5) and the masking face's top where it was; nothing of the
		-- roof that can be seen runs into a monitor
		local boards = root:FindFirstChild("Scoreboards") :: any
		local n = 0
		for lane = 1, AlleyLayout.LANES do
			local screen = boards:FindFirstChild(`Lane{lane}`):FindFirstChild("Screen")
			local X, Y, D = toLocal(screen.CFrame.Position.X, screen.CFrame.Position.Y, screen.CFrame.Position.Z)
			t.near(X, AlleyLayout.laneX(lane), 1e-3)
			t.near(Y, 9.6, 1e-3)
			t.near(D, -3.5 - 0.04, 1e-3)
			for _, p in
				world.overlapBox(
					screen.CFrame.Position.X,
					screen.CFrame.Position.Y,
					screen.CFrame.Position.Z,
					{ { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } },
					{ 3, 1.8, 0.4 },
					function(q)
						return q.visible
							and string.sub(q.path, 1, #AlleyLayout.HALL_ROOF.model) == AlleyLayout.HALL_ROOF.model
					end
				)
			do
				t.truthy(false, `{p.path} runs into lane {lane}'s monitor`)
			end
			n += 1
		end
		t.eq(n, AlleyLayout.LANES)
		local face = (root:FindFirstChild("Masking") :: any):FindFirstChild("MaskFace")
		local _, top = toLocal(0, face.CFrame.Position.Y + face.Size.Y / 2, 0)
		t.near(top, AlleyLayout.CEILING_Y, 1e-3, "the masking face's top")
	end)
end
