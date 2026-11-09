--!strict
-- Server/Actors/Perception grid: set/move/remove/query against a brute-force reference, plus the
-- query cost at the S5 scale (BUILD_PLAN D4: perception at 5-10 Hz on a spatial grid).
local Perception = require("@server/Actors/Perception")

local function lcg(seed: number): () -> number
	local s = seed
	return function(): number
		s = (s * 1103515245 + 12345) % 2147483648
		return s / 2147483648
	end
end

return function(t)
	t.test("query matches brute force over 2,000 random moves", function()
		local rng = lcg(3)
		local grid = Perception.newGrid(40)
		local pos: { [number]: { number } } = {}
		local n = 150
		for id = 1, n do
			local x, z = (rng() - 0.5) * 2400, (rng() - 0.5) * 1700
			pos[id] = { x, z }
			grid:set(id, x, z)
		end
		t.eq(grid.count, n)
		local out = {}
		for step = 1, 2000 do
			local id = math.floor(rng() * n) + 1
			local x, z = pos[id][1] + (rng() - 0.5) * 60, pos[id][2] + (rng() - 0.5) * 60
			pos[id] = { x, z }
			grid:set(id, x, z)
			if step % 50 == 0 then
				local qx, qz, r = (rng() - 0.5) * 2400, (rng() - 0.5) * 1700, 30 + rng() * 120
				local count = grid:query(qx, qz, r, out)
				local expected = {}
				for pid, p in pos do
					local dx, dz = p[1] - qx, p[2] - qz
					if dx * dx + dz * dz <= r * r then
						expected[pid] = true
					end
				end
				local expectedCount = 0
				for _ in expected do
					expectedCount += 1
				end
				t.eq(count, expectedCount, `query {step}`)
				for i = 1, count do
					t.truthy(expected[out[i]], `id {out[i]} not within {r}`)
				end
			end
		end
	end)

	t.test("remove drops the id and query no longer returns it", function()
		local grid = Perception.newGrid(40)
		grid:set(7, 10, 10)
		grid:set(8, 12, 12)
		local out = {}
		t.eq(grid:query(10, 10, 5, out), 2)
		grid:remove(7)
		t.eq(grid.count, 1)
		t.eq(grid:query(10, 10, 5, out), 1)
		t.eq(out[1], 8)
		grid:remove(7) -- idempotent
		t.eq(grid.count, 1)
	end)

	t.test("a 50-stud query over 15 threats costs well under 10 us on average", function()
		local rng = lcg(11)
		local grid = Perception.newGrid(40)
		for id = 1, 15 do
			grid:set(id, (rng() - 0.5) * 2400, (rng() - 0.5) * 1700)
		end
		local out = {}
		local reps = 20000
		local t0 = os.clock()
		local hits = 0
		for _ = 1, reps do
			hits += grid:query((rng() - 0.5) * 2400, (rng() - 0.5) * 1700, 50, out)
		end
		local us = (os.clock() - t0) / reps * 1e6
		t.truthy(us < 10, `{us} us per query ({hits} hits)`)
	end)
end
