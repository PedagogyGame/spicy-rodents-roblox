--!strict
-- Owner D30 (2026-11-22): "place a few banks around town, outside of which there are tasks or other optional errands,
-- deliver such and such to such and such place or person. At which point, it pays to know your way around town" and
-- "if ... the errand delivery person steals the item, or places it in their home and does not bring it back, in the
-- event they can't find the drop off spot, they should get penalized".
--   banks     three bank fronts (Shared/Work/Banks): BANK on their fascia in the town data; each errand board clear of
--             every road and building, on level ground with nothing baked in it or over it, apart from the others,
--             and the three joined on foot
--   places    every destination (Shared/Work/Errands) a spot on foot, off the roads and out of every building,
--             reached on foot from every bank; the people are the town's own residents at their own doors
--   offer     an errand names its place or person (never a map mark), pays more the farther it goes (to a cap),
--             gives time for the walk and more, and is never next door
--   run       the gentle "you're close" once, delivered at the spot in time, late is kept, home too long is kept,
--             handed back is nothing either way
local Data = require("@shared/Data")
local WalkWay = require("@shared/World/WalkWay")
local Height = require("@shared/World/Height")
local RoadSurface = require("@shared/World/RoadSurface")
local Banks = require("@shared/Work/Banks")
local Errands = require("@shared/Work/Errands")
local Bake = require("@worldgen/Bake")
local Geometry = require("@worldgen/Geometry")

local function seq(values: { number }): () -> number
	local i = 0
	return function(): number
		i += 1
		return values[(i - 1) % #values + 1]
	end
end

return function(t)
	local data = Data.default()
	local way = WalkWay.new({ data = data })
	-- every road a car drives (the town's roads data also holds its sidewalks, paths and front walks: walked on)
	local roads = RoadSurface.new(data:roads())
	local carRoads = {}
	for _, r in data:roads() do
		if r.kind == "asphalt" or r.kind == "rail" then
			table.insert(carRoads, r)
		end
	end
	local asphalt = RoadSurface.new(carRoads)

	t.test("banks: three, BANK on their fascia, boards clear of roads and buildings, level, apart, joined", function()
		t.eq(#Banks.BANKS, 3)
		local parts = {}
		for _, plan in Bake.plans(Bake.data()) do
			for _, sp in plan.parts do
				local x0, x1, y0, y1, z0, z1 = Geometry.aabb(sp)
				table.insert(
					parts,
					{ name = `{plan.id}/{sp.name}`, x0 = x0, x1 = x1, y0 = y0, y1 = y1, z0 = z0, z1 = z1 }
				)
			end
		end
		local boards = {}
		for _, bank in Banks.BANKS do
			local lot = data:lot(bank.lot)
			t.eq(lot.params.sign, Banks.SIGN, `{bank.id}: its fascia`)
			local b = Banks.board(bank)
			table.insert(boards, b)
			-- the board's footprint and a player's standing room in front of it
			local hw = Banks.BOARD.w / 2 + 0.5
			local lo, hi = math.huge, -math.huge
			for _, k in { { -1, 0 }, { 1, 0 }, { -1, 3 }, { 1, 3 }, { 0, 0 } } do
				-- along the front (perpendicular to the normal) and out from the board
				local x = b.x + b.nz * k[1] * hw + b.nx * k[2]
				local z = b.z - b.nx * k[1] * hw + b.nz * k[2]
				t.truthy(WalkWay.solidAt(way, x, z, 0) == nil, `{bank.id}: in a building at {x}, {z}`)
				t.truthy(RoadSurface.topAt(roads, x, z, 1000) == nil, `{bank.id}: on a road at {x}, {z}`)
				t.truthy(not Height.insideRiverWater(x, z), `{bank.id}: in the river`)
				local h = Height.at(x, z)
				lo, hi = math.min(lo, h), math.max(hi, h)
			end
			t.truthy(hi - lo <= 0.5, `{bank.id}: the ground rises {hi - lo}`)
			local r = Banks.BOARD.w / 2 + 0.4
			for _, q in parts do
				if q.x1 >= b.x - r and q.x0 <= b.x + r and q.z1 >= b.z - r and q.z0 <= b.z + r then
					t.truthy(
						q.y1 <= lo + 0.4 or q.y0 >= lo + Banks.BOARD.h + 2,
						`{bank.id}: {q.name} where the board stands`
					)
				end
			end
			-- facing out of the bank: CFrame.Angles(0, yaw, 0).LookVector is the outward normal
			t.near(-math.sin(b.yaw), b.nx, 1e-9)
			t.near(-math.cos(b.yaw), b.nz, 1e-9)
		end
		for i = 1, #boards do
			for j = i + 1, #boards do
				local a, c = boards[i], boards[j]
				local d = math.sqrt((a.x - c.x) ^ 2 + (a.z - c.z) ^ 2)
				t.truthy(d >= 300, `banks {i} and {j} only {d} apart`)
				t.truthy(
					WalkWay.find(way, a.x, a.z, c.x, c.z, { maxNodes = 60000 }) ~= nil,
					`no way from bank {i} to {j}`
				)
			end
		end
	end)

	t.test("places: on foot, off the roads, out of buildings, reached from every bank; real residents", function()
		local residents: { [string]: string } = {}
		for _, c in data:cast() do
			if c.homeLot then
				residents[c.name] = c.homeLot
			end
		end
		local names: { [string]: boolean } = {}
		for _, d in Errands.DESTINATIONS do
			t.falsy(names[d.name], `{d.name} twice`)
			names[d.name] = true
			t.truthy(WalkWay.solidAt(way, d.x, d.z, 0) == nil, `{d.id}: in a building`)
			t.truthy(RoadSurface.topAt(asphalt, d.x, d.z, 1000) == nil, `{d.id}: on a road`)
			t.truthy(not Height.insideRiverWater(d.x, d.z), `{d.id}: in the river`)
			for _, bank in Banks.BANKS do
				local b = Banks.board(bank)
				t.truthy(
					WalkWay.find(way, b.x, b.z, d.x, d.z, { maxNodes = 80000 }) ~= nil,
					`no way on foot from {bank.id} to {d.id}`
				)
			end
			if d.people then
				local lot: string? = nil
				for _, who in d.people do
					t.truthy(residents[who] ~= nil, `{who} is not one of the town's residents`)
					lot = lot or residents[who]
					t.eq(residents[who], lot, `{who} lives elsewhere`)
				end
				-- their door: within a few studs of the front of their own house
				local home = data:lot(lot :: string)
				local dx, dz = d.x - home.x, d.z - home.z
				local out = math.max(math.abs(dx) - home.footprint.w / 2, math.abs(dz) - home.footprint.d / 2)
				t.truthy(out > 0 and out < 12, `{d.id}: {out} studs from its house`)
			end
		end
	end)

	t.test("offer: named, never next door, pays more the farther (to a cap), time for the walk and more", function()
		local b = Banks.board(Banks.BANKS[1])
		local seen: { [string]: boolean } = {}
		for k = 0, 59 do
			local e = Errands.offer("south_quay", { b.x, b.z }, seq({ (k % 15) / 15 + 0.01, 0.4, 0.7 }))
			seen[e.dest.id] = true
			t.truthy(e.distance >= Errands.MIN_DISTANCE, `{e.dest.id} only {e.distance} away`)
			t.truthy(string.find(e.words, e.dest.name, 1, true) ~= nil, e.words)
			if e.person then
				t.truthy(string.find(e.words, e.person, 1, true) ~= nil, e.words)
				t.truthy(e.item.person == true)
			else
				t.truthy(e.item.place == true)
			end
			t.eq(e.cents, Errands.pay(e.distance))
			-- generous: the straight way at a slow walk (5 studs a second) plus two minutes at least
			t.truthy(e.secs >= e.distance / 5 + 120 - 1e-6, `{e.secs} s for {e.distance} studs`)
		end
		local n = 0
		for _ in seen do
			n += 1
		end
		t.truthy(n >= 10, `only {n} places offered`)
		t.truthy(Errands.pay(2000) > Errands.pay(400), "farther pays more")
		-- owner D31: errands pay about S$2 to S$15
		t.eq(Errands.pay(1e6), 1500, "the cap")
		t.eq(Errands.pay(0), 200, "the base")
		t.eq(Errands.pay(600), 800, "S$2.00 and S$1.00 for every 100 studs")
		t.eq(Errands.duration(30), "30 seconds")
		t.eq(Errands.duration(600), "10 minutes")
	end)

	t.test("run: close once, delivered in time, late is kept, home too long is kept, handed back is nothing", function()
		local e = Errands.offer("market", { 0, -3000 }, seq({ 0, 0, 0 }))
		local d = e.dest
		local run = Errands.start(e, 100)
		t.eq(Errands.step(run, 101, { d.x + 300, d.z }, false, 1), nil, "far away")
		t.eq(Errands.step(run, 102, { d.x + 30, d.z }, false, 1), "close")
		t.eq(Errands.step(run, 103, { d.x + 20, d.z }, false, 1), nil, "close is said once")
		t.eq(Errands.step(run, 104, { d.x + 5, d.z }, false, 1), "delivered")
		t.eq(Errands.step(run, 105, { d.x, d.z }, false, 1), nil, "over")
		-- late: kept, even if they come to the spot afterwards
		local late = Errands.start(e, 0)
		t.eq(Errands.step(late, e.secs + 1, { d.x + 500, d.z }, false, 1), "expired")
		local lateAtSpot = Errands.start(e, 0)
		t.eq(Errands.step(lateAtSpot, e.secs + 1, { d.x, d.z }, false, 1), "expired")
		-- at home: kept after errandHomeSecs in all (a walk through is not); not in a body: only the clock runs
		local home = Errands.start(e, 0)
		for s = 1, 19 do
			t.eq(Errands.step(home, s, { 5000, 5000 }, true, 1), nil)
		end
		t.eq(Errands.step(home, 20, { 5000, 5000 }, true, 1), "kept_home")
		local away = Errands.start(e, 0)
		t.eq(Errands.step(away, 10, nil, true, 1), nil)
		t.eq(Errands.step(away, e.secs + 0.5, nil, false, 1), "expired")
		-- handed back at a board: over, nothing either way
		local back = Errands.start(e, 0)
		Errands.handBack(back)
		t.eq(back.over, "returned")
		t.eq(Errands.step(back, e.secs + 10, { d.x, d.z }, false, 1), nil)
		t.eq(Errands.left(Errands.start(e, 0), 10), e.secs - 10)
	end)
end
