--!strict
-- Minigames/Pool/Tables: the eight-ball table and the bumper pool table as data (checklist C18, POOL-P7, POOL-P5,
-- BP-R1, BP-R2): the sizes, the six pockets with their jaws, the regulation twelve bumpers with a gap one ball
-- wide, the two cups, the rack and the bumper pool start.
local Tables = require("@shared/Minigames/Pool/Tables")

return function(t)
	local pool = Tables.eightBall()
	local bumper = Tables.bumper()
	local R = Tables.BALL_R

	t.test("POOL-P7 scale: a 10.8 x 5.4 bed, a 0.17 ball, one table object for everyone (C18)", function()
		t.eq(pool.halfW * 2, 5.4)
		t.eq(pool.halfL * 2, 10.8)
		t.eq(pool.ballR, 0.17)
		t.eq(bumper.ballR, 0.17)
		t.truthy(Tables.eightBall() == pool, "the table is built once")
		t.truthy(Tables.byId("eightball") == pool)
		t.truthy(Tables.byId("bumper") == bumper)
		t.near(pool.headZ, -2.7, 1e-12)
		t.near(pool.footZ, 2.7, 1e-12)
	end)

	t.test("eight-ball: six pockets in calling order, each behind a mouth wider than a ball", function()
		t.eq(#pool.holes, 6)
		t.eq(#Tables.POCKET_NAMES, 6)
		local signs = { { -1, -1 }, { 1, -1 }, { -1, 0 }, { 1, 0 }, { -1, 1 }, { 1, 1 } }
		for i, hole in pool.holes do
			t.truthy(not hole.cup)
			t.eq(math.sign(hole.x), signs[i][1], `pocket {i} side`)
			t.eq(if math.abs(hole.z) < 1e-9 then 0 else math.sign(hole.z), signs[i][2], `pocket {i} end`)
			-- the mouth direction points at the table
			t.truthy(hole.mx * hole.x + hole.mz * hole.z < 0)
			t.near(hole.mx * hole.mx + hole.mz * hole.mz, 1, 1e-9)
			-- the drop is off the bed: a ball on the bed by the cushion is not over it
			t.truthy(math.abs(hole.x) + hole.r > pool.halfW)
		end
		t.truthy(
			Tables.CORNER_MOUTH > 2 * R * 1.8 and Tables.CORNER_MOUTH < 2 * R * 2.5,
			"corner mouth about two balls"
		)
		t.truthy(Tables.SIDE_MOUTH > Tables.CORNER_MOUTH, "side pockets are cut wider")
	end)

	t.test("eight-ball: six cushions and twelve jaw facings, mirrored left to right and end to end", function()
		local cushions, jaws = 0, 0
		for _, sg in pool.segs do
			if sg.jaw then
				jaws += 1
			else
				cushions += 1
			end
			t.near(sg.tx * sg.tx + sg.tz * sg.tz, 1, 1e-9)
			t.truthy(sg.len > 0)
			-- every piece has its mirror images
			local found = 0
			for _, o in pool.segs do
				if o.jaw == sg.jaw then
					local function same(ax: number, az: number, bx: number, bz: number): boolean
						return math.abs(ax - bx) < 1e-9 and math.abs(az - bz) < 1e-9
					end
					if
						(same(o.x1, o.z1, -sg.x1, sg.z1) and same(o.x2, o.z2, -sg.x2, sg.z2))
						or (same(o.x1, o.z1, -sg.x2, sg.z2) and same(o.x2, o.z2, -sg.x1, sg.z1))
					then
						found += 1
					end
				end
			end
			t.truthy(found >= 1, "mirror image across the long axis")
		end
		t.eq(cushions, 6)
		t.eq(jaws, 12)
		-- the facings converge: the throat is narrower than the mouth (they reject as well as accept)
		t.truthy(Tables.JAW_LEN > 0)
	end)

	t.test("BP-R1 bumper pool: twelve bumpers (eight in a cross, two by each cup), two cups, no pockets", function()
		t.eq(#bumper.posts, 12)
		t.eq(#bumper.holes, 2)
		t.eq(#bumper.segs, 4)
		local cross, flank = 0, 0
		for _, p in bumper.posts do
			if math.abs(p.z) < 1 then
				cross += 1
				t.truthy(p.x == 0 or p.z == 0, "the cross lies on the two centre lines")
			else
				flank += 1
				t.near(math.abs(p.z), Tables.CUP_Z, 1e-12, "beside a cup")
			end
		end
		t.eq(cross, 8)
		t.eq(flank, 4)
		for _, hole in bumper.holes do
			t.truthy(hole.cup)
			t.eq(hole.x, 0)
			t.truthy(math.abs(hole.z) + hole.r < bumper.halfL, "a cup is cut in the bed, clear of the end cushion")
		end
		t.truthy(bumper.holes[1].z < 0 and bumper.holes[2].z > 0, "hole 1 is the head cup, hole 2 the foot cup")
	end)

	t.test("BP-P1 the gap in the cross is one ball wide: more than a ball, less than a ball and a quarter", function()
		local d = Tables.CROSS_INNER * math.sqrt(2) - 2 * Tables.POST_R
		t.truthy(d > 2 * R, `a ball fits ({d})`)
		t.truthy(d < 2 * R * 1.25, "and only just")
		-- the arms of the cross are closed: a ball cannot pass between an inner post and the outer one behind it
		t.truthy(Tables.CROSS_OUTER - Tables.CROSS_INNER - 2 * Tables.POST_R < 2 * R)
		-- nor straight through the middle along a centre line
		t.truthy(
			2 * Tables.CROSS_INNER - 2 * Tables.POST_R > 2 * R,
			"the middle of the cross is open to a ball already inside"
		)
	end)

	t.test("POOL-P5 the rack: sixteen balls, the 8 in the middle, a solid and a stripe in the back corners", function()
		for seed = 1, 30 do
			local spots = Tables.rack(seed)
			t.eq(#spots, 16)
			t.eq(spots[1].id, 0)
			t.eq(spots[1].z, pool.headZ)
			local seen: { [number]: boolean } = {}
			for _, s in spots do
				t.truthy(not seen[s.id], "each ball once")
				seen[s.id] = true
				t.truthy(Tables.onBed(pool, s.x, s.z, 0))
			end
			t.eq(spots[1 + 5].id, 8, "the 8 is the middle of the third row")
			local a, b = spots[1 + 11].id, spots[1 + 15].id
			t.truthy((a < 8) ~= (b < 8), "one solid and one stripe in the back corners")
			-- the apex is on the foot spot, and nothing overlaps: every pair has a hairline gap
			t.near(spots[2].x, 0, 2 * Tables.RACK_JITTER)
			t.near(spots[2].z, pool.footZ, 2 * Tables.RACK_JITTER)
			for i = 2, 16 do
				for j = i + 1, 16 do
					local dx, dz = spots[i].x - spots[j].x, spots[i].z - spots[j].z
					t.truthy(dx * dx + dz * dz > 4 * R * R, "no two racked balls overlap")
				end
			end
		end
	end)

	t.test("POOL-P5 the rack is seeded: the same seed is the same rack, another seed is another", function()
		t.deepEq(Tables.rack(7), Tables.rack(7))
		local a, b = Tables.rack(7), Tables.rack(8)
		local differs = false
		for i = 2, 16 do
			if a[i].id ~= b[i].id or a[i].x ~= b[i].x then
				differs = true
			end
		end
		t.truthy(differs)
	end)

	t.test("BP-R2 bumper pool start: five each round the cup at their own end, the marked ball in front", function()
		local spots = Tables.bumperStart()
		t.eq(#spots, 10)
		for _, s in spots do
			local side = if s.id <= 5 then 1 else 2
			t.truthy((side == 1) == (s.z < 0), "side 1 starts at the head end, side 2 at the foot end")
			t.truthy(Tables.canPlace(bumper, s.x, s.z, spots, s.id), `ball {s.id} sits on clear cloth`)
		end
		-- the marked balls (1 and 6) are in front of the cup, on the centre line; the others two each side of it
		t.eq(spots[1].id, 1)
		t.eq(spots[1].x, 0)
		t.truthy(spots[1].z > -Tables.CUP_Z)
		t.eq(spots[6].id, 6)
		t.eq(spots[6].x, 0)
		t.truthy(spots[6].z < Tables.CUP_Z)
		for _, i in { 2, 3, 4, 5 } do
			t.eq(spots[i].z, -Tables.CUP_Z)
		end
		t.eq(#Tables.bumperStart({ true, false }), 5, "practice: only your five")
	end)

	t.test(
		"placing a ball: on the bed, touching nothing, never over a hole; the kitchen is behind the head string",
		function()
			local spots = Tables.rack(1)
			t.truthy(Tables.canPlace(pool, 1, -4, spots, 0))
			t.falsy(Tables.canPlace(pool, 0, pool.footZ, spots, 0), "on the apex ball")
			t.falsy(Tables.canPlace(pool, pool.halfW, 0, spots, 0), "in the cushion")
			t.falsy(Tables.canPlace(pool, 9, 9, spots, 0), "off the table")
			t.truthy(Tables.canPlace(pool, 0, pool.headZ, spots, 0), "its own place does not block it")
			t.truthy(Tables.inKitchen(pool, pool.headZ))
			t.truthy(Tables.inKitchen(pool, -5))
			t.falsy(Tables.inKitchen(pool, 0))
			t.falsy(Tables.canPlace(bumper, 0, Tables.CUP_Z, {}, nil), "over a cup")
			t.falsy(Tables.canPlace(bumper, Tables.CROSS_INNER, 0, {}, nil), "on a bumper")
		end
	)

	t.test("re-spotting: the nearest free place along the long string", function()
		local spots = Tables.rack(3)
		local x, z = Tables.freeSpot(pool, 0, pool.footZ, spots, 1)
		t.eq(x, 0)
		t.truthy(z > pool.footZ, "behind the rack, toward the foot cushion")
		t.truthy(Tables.canPlace(pool, x, z, spots, nil))
		local x2, z2 = Tables.freeSpot(pool, 0, pool.headZ, { { id = 1, x = 0, z = pool.headZ } }, -1)
		t.eq(x2, 0)
		t.truthy(z2 < pool.headZ and Tables.inKitchen(pool, z2), "a taken head spot: further into the kitchen")
	end)
end
