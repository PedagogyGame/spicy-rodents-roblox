--!strict
-- Traffic/Swept golden tests (spike S4; BUILD_PLAN §6.2 "Traffic/Swept" row, §6.3): exact boolean
-- agreement with all 10,126 sweptVehicleHit cases (126 hand + 10,000 seeded), the 3,000
-- segmentBoxEntry slab cases, the 72 travel-filter cases, and the broad phase never rejecting a true
-- hit. Golden units are HTML units, so `scale = 1`.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Swept = require("@shared/Traffic/Swept")

local function num(v: any): number
	if type(v) == "string" then
		return tonumber(v) :: number
	end
	return v
end

local function vec(a: { any }): Swept.Vec3
	return { x = num(a[1]), y = num(a[2]), z = num(a[3]) }
end

return function(t)
	local swept = serde.decode("json", fs.readFile("tests/golden/swept.json"))

	t.test("golden swept.json: 100 % agreement on 10,126 cases (4,715 hits)", function()
		t.eq(swept.count, 10126)
		t.eq(#swept.rows, 10126)
		local hits, mismatches = 0, {}
		for _, row in swept.rows do
			local p0, p1, v0, v1 = vec(row[6]), vec(row[7]), vec(row[8]), vec(row[9])
			local got = Swept.hit(p0, p1, v0, v1, num(row[10]), num(row[11]), row[3], row[4], row[5], 1)
			if got then
				hits += 1
			end
			if got ~= row[12] then
				table.insert(mismatches, row[1])
			end
		end
		print(`      {hits} hits; {#mismatches} mismatches`)
		for i = 1, math.min(5, #mismatches) do
			print(`      MISMATCH {mismatches[i]}`)
		end
		t.eq(#mismatches, 0, "mismatches")
		t.eq(hits, swept.hits, "hit count")
	end)

	t.test("golden swept.json: the broad phase never rejects a true hit and prunes most misses", function()
		local rejected, falseRejects = 0, 0
		for _, row in swept.rows do
			local p0, p1, v0, v1 = vec(row[6]), vec(row[7]), vec(row[8]), vec(row[9])
			local pass = Swept.broadPhase(
				p0.x,
				p0.y,
				p0.z,
				p1.x,
				p1.y,
				p1.z,
				v0.x,
				v0.y,
				v0.z,
				v1.x,
				v1.y,
				v1.z,
				num(row[10]),
				num(row[11]),
				row[3],
				row[4],
				row[5],
				1
			)
			if not pass then
				rejected += 1
				if row[12] then
					falseRejects += 1
				end
			end
		end
		print(`      broad phase rejected {rejected} of {#swept.rows} ({#swept.rows - swept.hits} are misses)`)
		t.eq(falseRejects, 0, "a true hit rejected by the broad phase")
		t.truthy(rejected > (#swept.rows - swept.hits) * 0.3, "prunes at least 30 % of the misses")
	end)

	t.test("golden segment_box_entry.json: 3,000 slab cases (enter to 1e-12, nil exact)", function()
		local g = serde.decode("json", fs.readFile("tests/golden/segment_box_entry.json"))
		t.eq(#g.rows, 3000)
		for i, row in g.rows do
			local got = Swept.segmentBoxEntry(vec(row[1]), vec(row[2]), row[3], row[4], row[5], row[6])
			local want = row[7]
			if want == nil then
				t.eq(got, nil, `case {i} expected nil`)
			else
				t.truthy(got ~= nil, `case {i} expected {want}`)
				t.near(got :: number, want, 1e-12, `case {i}`)
			end
		end
	end)

	t.test("golden travel_filter.json: 72 finishTrafficFrame filter cases", function()
		local g = serde.decode("json", fs.readFile("tests/golden/travel_filter.json"))
		t.eq(#g.cases, 72)
		for _, c in g.cases do
			t.eq(Swept.travelFilterSkips(c.travel, c.dt, 1), c.skip, `travel {c.travel} dt {c.dt}`)
		end
		-- in studs the same thresholds scale by 2.5
		t.truthy(Swept.travelFilterSkips(2e-5, 1 / 60))
		t.falsy(Swept.travelFilterSkips(3e-5, 1 / 60))
		t.falsy(Swept.travelFilterSkips(30, 0.08))
		t.truthy(Swept.travelFilterSkips(30.01, 0.08))
	end)

	t.test("hypot matches sqrt within an ulp and handles zero and infinity like V8", function()
		t.eq(Swept.hypot(0, 0), 0)
		t.eq(Swept.hypot(math.huge, 1), math.huge)
		t.near(Swept.hypot(3, 4), 5, 1e-15)
		t.near(Swept.hypot(2.35, 4.45), math.sqrt(2.35 * 2.35 + 4.45 * 4.45), 1e-14)
	end)

	t.test("studs: a sedan passing under a squirrel on a wire at 17 u never hits; at ground height it does", function()
		local k = 2.5
		local W, L, H = 2.35 * k, 4.45 * k, 2.04 * k
		local high = { x = 0, y = 17 * k, z = 0 }
		t.falsy(
			Swept.hit(
				high,
				high,
				{ x = 0, y = 0.04 * k, z = -8 * k },
				{ x = 0, y = 0.04 * k, z = 4 * k },
				0,
				0,
				W,
				L,
				H
			)
		)
		local low = { x = 0, y = 0.18 * k, z = 0 }
		t.truthy(
			Swept.hit(low, low, { x = 0, y = 0.04 * k, z = -8 * k }, { x = 0, y = 0.04 * k, z = 4 * k }, 0, 0, W, L, H)
		)
	end)
end
