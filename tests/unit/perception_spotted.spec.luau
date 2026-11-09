--!strict
-- Server/Actors/Perception: the ported spotted() predicate against the golden vectors from the
-- original game (tests/golden/spotted.json, 3,010 rows; BUILD_PLAN §6.3, humans_actors §5.3).
-- Inputs are HTML units in the file; they cross Config/Units once here (studs in, studs out).
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Units = require("@shared/Config/Units")
local Perception = require("@server/Actors/Perception")

local GOLDEN = "tests/golden/spotted.json"

type Row = { any }

return function(t)
	local golden = serde.decode("json", fs.readFile(GOLDEN))
	local rows: { Row } = golden.rows
	local columns: { string } = golden.columns
	local col: { [string]: number } = {}
	for i, name in columns do
		col[name] = i
	end
	local concealment = Perception.concealmentFromHtml(golden.hedgePatches, golden.garden)

	t.test("golden file has the expected shape", function()
		t.eq(golden.count, 3010)
		t.eq(#rows, 3010)
		t.eq(#golden.hedgePatches, 5)
	end)

	t.test("every intermediate and the verdict match for all 3,010 vectors (detailed path)", function()
		local mismatches = {}
		for _, row in rows do
			local playerPos: { number } = row[col.playerPos]
			local humanPos: { number } = row[col.humanPos]
			local observer: Perception.Observer = {
				x = Units.st(humanPos[1]),
				y = Units.st(humanPos[2]),
				z = Units.st(humanPos[3]),
				facing = row[col.humanFacing],
				-- the golden's `remembered` models n.witnessUntil (200) > time (100)
				witnessUntil = if row[col.remembered] then 200 else 0,
			}
			local target: Perception.Target = {
				x = Units.st(playerPos[1]),
				y = Units.st(playerPos[2]),
				z = Units.st(playerPos[3]),
				groundY = 0, -- v5.4 tests absolute Y; ground 0 reproduces it
				moveSpeed = Units.st(row[col.moveSpeed]),
				focus = row[col.focus],
				inInterior = row[col.activeHouseInterior],
			}
			local ctx: Perception.Ctx = { time = 100, hotHere = row[col.hotHere], concealment = concealment }
			local d = Perception.spottedDetailed(observer, target, ctx)
			local expectedDist = row[col.dist2]
			local ok = math.abs(Units.u(d.dist2) - expectedDist) <= 1e-9 * math.max(1, expectedDist)
				and d.isVisible == row[col.isVisible]
				and d.inView == row[col.inView]
				and d.noise == row[col.noise]
				and d.gardenBlind == row[col.gardenBlind]
				and d.hedgeBlind == row[col.hedgeBlind]
				and d.concealed == row[col.concealed]
				and d.radar == row[col.radar]
				and d.spotted == row[col.spotted]
			if not ok then
				table.insert(mismatches, row[col.name])
			end
		end
		t.eq(#mismatches, 0, `mismatches: {table.concat(mismatches, ", ", 1, math.min(10, #mismatches))}`)
	end)

	t.test("the fast path agrees with the detailed path on every vector", function()
		local disagreements = 0
		for _, row in rows do
			local playerPos: { number } = row[col.playerPos]
			local humanPos: { number } = row[col.humanPos]
			local observer: Perception.Observer = {
				x = Units.st(humanPos[1]),
				y = Units.st(humanPos[2]),
				z = Units.st(humanPos[3]),
				facing = row[col.humanFacing],
				witnessUntil = if row[col.remembered] then 200 else 0,
			}
			local target: Perception.Target = {
				x = Units.st(playerPos[1]),
				y = Units.st(playerPos[2]),
				z = Units.st(playerPos[3]),
				groundY = 0,
				moveSpeed = Units.st(row[col.moveSpeed]),
				focus = row[col.focus],
				inInterior = row[col.activeHouseInterior],
			}
			local ctx: Perception.Ctx = { time = 100, hotHere = row[col.hotHere], concealment = concealment }
			if Perception.spotted(observer, target, ctx) ~= row[col.spotted] then
				disagreements += 1
			end
		end
		t.eq(disagreements, 0)
	end)

	t.test("height above local ground replaces absolute Y (porting note humans_actors §15)", function()
		-- a squirrel 3 u above a 6 u hill is 9 u absolute: v5.4 would never see it; the port does
		local observer: Perception.Observer = { x = 0, y = Units.st(6), z = 0, facing = 0 }
		local ctx: Perception.Ctx = { time = 0, hotHere = false, concealment = nil }
		local onHill: Perception.Target = {
			x = 0,
			y = Units.st(9),
			z = Units.st(5),
			groundY = Units.st(6),
			moveSpeed = 0,
			focus = false,
			inInterior = false,
		}
		t.truthy(Perception.spotted(observer, onHill, ctx), "3 u above local ground, 5 u ahead: seen")
		onHill.groundY = 0
		t.falsy(Perception.spotted(observer, onHill, ctx), "9 u absolute with ground 0: canopy, unseen")
	end)

	t.test("the default concealment volumes equal the v5.4 tables in studs", function()
		local c = Perception.defaultConcealment()
		t.eq(#c.hedges, 5)
		t.near(c.hedges[1].cx, Units.st(125))
		t.near(c.hedges[5].h, Units.st(2.2))
		t.near(c.gardens[1].cx, Units.st(115))
		t.near(c.gardens[1].cz, Units.st(341))
	end)
end
