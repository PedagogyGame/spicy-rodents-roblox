--!strict
-- World/Height + World/Ground golden tests (spike S6; BUILD_PLAN §6.2 "World/Height, World/Ground"
-- row): every row of tests/golden/terrain.json (11,060 vectors from the verbatim v5.4 functions,
-- HTML units) through the verbatim port at 1e-9, and the stud wrappers at 1e-6 after x2.5 scaling.
local fs = require("@lune/fs")
local Height = require("@shared/World/Height")
local Ground = require("@shared/World/Ground")
local PreciseJson = require("@tests/lib/PreciseJson")

local function num(v: any): number
	if type(v) == "string" then
		return tonumber(v) :: number
	end
	return v
end

return function(t)
	local golden = PreciseJson.decode(fs.readFile("tests/golden/terrain.json"))
	-- columns: tag, x, z, base, height, riverCenter, inRiverDistrict, insideRiverWater, riverDeck

	t.test("golden terrain.json: 11,060 rows match the verbatim port within 1e-9 (HTML units)", function()
		t.eq(#golden.rows, 11060)
		local worst, bad = 0, 0
		for _, row in golden.rows do
			local x, z = num(row[2]), num(row[3])
			local errs = {
				math.abs(Height.baseU(x, z) - num(row[4])),
				math.abs(Height.atU(x, z) - num(row[5])),
				math.abs(Height.riverCenterU(z) - num(row[6])),
			}
			local deck = Height.riverDeckAtU(x, z)
			local okDeck = if row[9] == nil then deck == nil else deck ~= nil and math.abs(deck - num(row[9])) <= 1e-9
			local okFlags = Height.inRiverDistrictU(x, z) == row[7] and Height.insideRiverWaterU(x, z) == row[8]
			local e = math.max(errs[1], errs[2], errs[3])
			worst = math.max(worst, e)
			if e > 1e-9 or not okDeck or not okFlags then
				bad += 1
				if bad <= 5 then
					print(`      MISMATCH {row[1]} ({x}, {z}) err {e} deck {okDeck} flags {okFlags}`)
				end
			end
		end
		print(`      worst abs error {worst}; {bad} mismatches`)
		t.eq(bad, 0, "mismatches")
	end)

	t.test("stud wrappers equal the HTML-unit port scaled by 2.5 (1e-6)", function()
		local worst = 0
		for i, row in golden.rows do
			if i % 7 == 0 then
				local x, z = num(row[2]), num(row[3])
				worst = math.max(worst, math.abs(Height.at(x * 2.5, z * 2.5) - num(row[5]) * 2.5))
				worst = math.max(worst, math.abs(Height.base(x * 2.5, z * 2.5) - num(row[4]) * 2.5))
			end
		end
		t.truthy(worst <= 1e-6, `worst {worst}`)
	end)

	t.test("flat core: height is exactly 0 for Chebyshev distance <= 104 u", function()
		for x = -104, 104, 8 do
			t.eq(Height.atU(x, 104), 0)
			t.eq(Height.atU(104, x), 0)
		end
	end)

	t.test("Ground: deck snap, water and terrain kinds; groundAt is pure in (x, z, refY)", function()
		-- bridge centre (850, 0) u: deck 15.8 u above the river bed
		local x, z = 850 * 2.5, 0
		t.eq(Ground.surfaceKind(x, z), "deck")
		t.near(Ground.groundAt(x, z, 40), 15.8 * 2.5, 1e-9)
		t.near(Ground.groundAt(x, z, 0), -2 * 2.5, 1e-9) -- below the deck: the river bed
		t.eq(Ground.surfaceKind(850 * 2.5, 100 * 2.5), "water")
		t.eq(Ground.surfaceKind(0, 0), "terrain")
		t.eq(Ground.groundAt(300, 300, 0), Ground.groundAt(300, 300, 0))
		t.eq(Ground.roofAt(0, 0, 0), nil)
	end)
end
