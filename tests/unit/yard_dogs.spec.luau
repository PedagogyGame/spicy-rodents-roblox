--!strict
-- The town's yard dogs (Shared/Wildlife/YardDogs): eight yards, each its own and clear of the town (no building,
-- road, path or tree trunk in it; three doghouses at their yards' back edges, as the town builds them), on
-- gentle ground; and the dog's mind: it wanders inside its yard, chases a squirrel on the ground in it (not one up
-- a fence, not one next door) and barks no more than every BARK_EVERY seconds, ignores squirrels while a treat
-- lasts, goes home and lies down at night, and thinks only every THINK seconds.
local YardDogs = require("@shared/Wildlife/YardDogs")
local Height = require("@shared/World/Height")
local Lots = require("../../generated/Lots")
local Roads = require("../../generated/Roads")
local Wildlife = require("../../generated/Wildlife")
local TerrainExtensions = require("../../generated/TerrainExtensions")

local function lotById(id: string): any?
	for _, l in Lots :: { any } do
		if l.id == id then
			return l
		end
	end
	return nil
end

-- a lot's footprint as a square of its larger side (the facing may turn w and d): x0, x1, z0, z1
local function box(l: any): (number, number, number, number)
	local fp = l.footprint or { w = 0, d = 0 }
	local h = math.max(fp.w or 0, fp.d or 0) / 2
	return l.x - h, l.x + h, l.z - h, l.z + h
end

local function overlaps(y: YardDogs.Yard, x0: number, x1: number, z0: number, z1: number, m: number): boolean
	return x1 > y.x0 - m and x0 < y.x1 + m and z1 > y.z0 - m and z0 < y.z1 + m
end

-- the distance from a point to a segment
local function segDist(px: number, pz: number, ax: number, az: number, bx: number, bz: number): number
	local vx, vz = bx - ax, bz - az
	local l2 = vx * vx + vz * vz
	local t = if l2 > 0 then math.clamp(((px - ax) * vx + (pz - az) * vz) / l2, 0, 1) else 0
	local dx, dz = ax + vx * t - px, az + vz * t - pz
	return math.sqrt(dx * dx + dz * dz)
end

local function squirrel(id: any, x: number, z: number, above: number?, rodent: boolean?): YardDogs.Squirrel
	return { id = id, x = x, y = above or 0, z = z, ground = 0, rodent = rodent == true }
end

local function sense(list: { YardDogs.Squirrel }, night: boolean?, barks: { any }?): YardDogs.Sense
	return {
		night = night == true,
		squirrels = function(): { YardDogs.Squirrel }
			return list
		end,
		bark = function(_d: YardDogs.Dog, s: YardDogs.Squirrel)
			if barks then
				table.insert(barks, s.id)
			end
		end,
	}
end

local function run(d: YardDogs.Dog, from: number, secs: number, s: YardDogs.Sense): number
	local now = from
	for _ = 1, math.floor(secs / 0.1 + 0.5) do
		now += 0.1
		YardDogs.think(d, now, s)
		YardDogs.move(d, 0.1)
	end
	return now
end

return function(t)
	t.test("eight yards with unique ids; three doghouses at their yards' back edges, the rest get kennels", function()
		t.eq(#YardDogs.YARDS, 8)
		local ids = {}
		local houses = 0
		for _, y in YardDogs.YARDS do
			t.falsy(ids[y.id], y.id)
			ids[y.id] = true
			t.truthy(y.x1 - y.x0 >= 20 and y.z1 - y.z0 >= 20, `{y.id}: room to run`)
			t.truthy(YardDogs.inYard(y, y.homeX, y.homeZ), `{y.id}: home in the yard`)
			if y.doghouse then
				houses += 1
				local l = lotById(y.doghouse)
				t.truthy(l, y.doghouse)
				t.truthy(string.find(l.type, "doghouse", 1, true), y.doghouse)
				t.eq(l.facing, "-Z", "opens toward the yard")
				local _, _, z0 = box(l)
				t.truthy(math.abs(z0 - y.z1) <= 1.5, `{y.id}: the doghouse sits on the back edge ({z0} vs {y.z1})`)
				t.truthy(l.x > y.x0 and l.x < y.x1, `{y.id}: in line with the yard`)
				t.truthy(y.homeZ < z0 and z0 - y.homeZ < 4, `{y.id}: home in front of the door`)
			end
		end
		t.eq(houses, 3)
	end)

	t.test("each yard is clear: no building, road, path or trunk in it, and no other yard near", function()
		for _, y in YardDogs.YARDS do
			for _, l in Lots :: { any } do
				if l.id ~= y.doghouse then
					local x0, x1, z0, z1 = box(l)
					t.falsy(overlaps(y, x0, x1, z0, z1, 2), `{y.id} overlaps lot {l.id}`)
				end
			end
			local cx, cz = (y.x0 + y.x1) / 2, (y.z0 + y.z1) / 2
			for _, r in Roads :: { any } do
				local w = (r.width or 0) / 2
				if r.axis == "z" then
					t.falsy(overlaps(y, r.coord - w, r.coord + w, r.start, r["end"], 2), `{y.id} on road {r.id}`)
				elseif r.axis == "x" then
					t.falsy(overlaps(y, r.start, r["end"], r.coord - w, r.coord + w, 2), `{y.id} on road {r.id}`)
				elseif r.axis == "free" then
					-- the nearest the path comes to the yard's rectangle: sample the rectangle's edge and inside
					local near = math.huge
					for i = 0, 10 do
						for j = 0, 10 do
							local px = y.x0 + (y.x1 - y.x0) * i / 10
							local pz = y.z0 + (y.z1 - y.z0) * j / 10
							near = math.min(near, segDist(px, pz, r.start[1], r.start[2], r["end"][1], r["end"][2]))
						end
					end
					t.truthy(near - w > 2, `{y.id} on path {r.id} ({near - w})`)
				end
			end
			for _, tr in (Wildlife :: any).studs.trees.trees do
				local r = (tr.trunkBaseRadius or 2) + 2
				t.falsy(overlaps(y, tr.x - r, tr.x + r, tr.z - r, tr.z + r, 0), `{y.id} round the trunk of {tr.name}`)
			end
			for _, o in YardDogs.YARDS do
				if o ~= y then
					t.falsy(overlaps(y, o.x0, o.x1, o.z0, o.z1, 2 * YardDogs.SENSE + 10), `{y.id} next to {o.id}`)
				end
			end
			t.truthy(cx == cx and cz == cz)
		end
	end)

	t.test("each yard is on gentle ground (the dogs walk on the terrain)", function()
		Height.configure(TerrainExtensions :: any)
		for _, y in YardDogs.YARDS do
			local lo, hi = math.huge, -math.huge
			for i = 0, 8 do
				for j = 0, 8 do
					local h = Height.at(y.x0 + (y.x1 - y.x0) * i / 8, y.z0 + (y.z1 - y.z0) * j / 8)
					lo, hi = math.min(lo, h), math.max(hi, h)
				end
			end
			t.truthy(hi - lo < 6, `{y.id}: {hi - lo} studs from low to high`)
		end
		Height.configure(nil)
	end)

	t.test(
		"a kennel: in its yard behind home; no wander or chase spot, nor the dog, in it; lying, the tail clear",
		function()
			local K = YardDogs.KENNEL
			local e = K.half + K.keep
			local kennels = 0
			for i, y in YardDogs.YARDS do
				local kx, kz = YardDogs.kennelOf(y)
				if y.doghouse then
					t.eq(kx, nil, `{y.id}: the town's doghouse`)
					continue
				end
				assert(kx and kz, "a kennel")
				kennels += 1
				t.truthy(
					YardDogs.inYard(y, kx - K.half, kz - K.half) and YardDogs.inYard(y, kx + K.half, kz + K.half),
					`{y.id}: the kennel in the yard`
				)
				-- lying at home facing out, the tail (keep behind the root) stops short of the kennel's front
				t.truthy(K.back - K.half >= K.keep, "the tail clear")
				local function out(x: number, z: number): boolean
					return math.abs(x - kx) >= e - 1e-6 or math.abs(z - kz) >= e - 1e-6
				end
				t.truthy(out(y.homeX, y.homeZ), `{y.id}: home clear of the kennel`)
				local d = YardDogs.newDog(y, i)
				local s = sense({})
				for k = 1, 2000 do
					YardDogs.think(d, k * 10, s)
					t.truthy(out(d.tx, d.tz), `{y.id}: a wander spot in the kennel ({d.tx}, {d.tz})`)
				end
				-- a squirrel behind the kennel: the dog runs to it, round the kennel, never into it
				local sq = squirrel("s", kx - y.faceX * (K.half + 0.5), kz - y.faceZ * (K.half + 0.5))
				local cs = sense({ sq })
				local now = 30000
				for _ = 1, 200 do
					now += 0.05
					YardDogs.think(d, now, cs)
					YardDogs.move(d, 0.05)
					t.truthy(out(d.tx, d.tz), `{y.id}: a chase spot in the kennel`)
					t.truthy(out(d.x, d.z), `{y.id}: the dog in the kennel ({d.x}, {d.z})`)
					t.truthy(YardDogs.inYard(y, d.x, d.z), `{y.id}: in the yard`)
				end
			end
			t.eq(kennels, 5)
		end
	)

	t.test("it wanders about its yard and never leaves it", function()
		for i, y in YardDogs.YARDS do
			local d = YardDogs.newDog(y, i)
			local seen: { [string]: boolean } = {}
			local now = 0
			for _ = 1, 600 do
				now = run(d, now, 0.5, sense({}))
				t.truthy(YardDogs.inYard(y, d.x, d.z), `{y.id}: in the yard`)
				seen[`{math.floor((d.x - y.x0) / (y.x1 - y.x0) * 2)},{math.floor((d.z - y.z0) / (y.z1 - y.z0) * 2)}`] =
					true
			end
			local n = 0
			for _ in seen do
				n += 1
			end
			t.truthy(n >= 3, `{y.id}: gets about ({n} quarters)`)
		end
	end)

	t.test("a squirrel on the ground in the yard is chased and barked at, every BARK_EVERY at most", function()
		local y = YardDogs.YARDS[1]
		local d = YardDogs.newDog(y, 1)
		local barks = {}
		local sq = squirrel("s1", y.x0 + 3, y.z0 + 3)
		local s = sense({ sq }, false, barks)
		local now = run(d, 0, 0.5, s)
		t.eq(d.mode, "chase")
		t.eq(d.target, "s1")
		t.eq(#barks, 1, "a bark")
		now = run(d, now, 3, s)
		t.eq(#barks, 1, "not again yet")
		t.truthy(math.abs(d.x - sq.x) < 2 and math.abs(d.z - sq.z) < 2, "it got there")
		now = run(d, now, YardDogs.BARK_EVERY, s)
		t.eq(#barks, 2, "and again")
		-- the squirrel runs off past the fence: the dog stops at the edge and goes back to wandering
		sq.x = y.x0 - 20
		now = run(d, now, 1, s)
		t.eq(d.mode, "wander")
		t.truthy(YardDogs.inYard(y, d.x, d.z))
		-- one up a fence or a branch is out of reach: ignored
		local high = squirrel("s2", y.x0 + 5, y.z0 + 5, YardDogs.ABOVE + 3)
		run(d, now, 2, sense({ high }, false, barks))
		t.eq(d.mode, "wander")
		t.eq(#barks, 2)
		-- the rodent too
		local d2 = YardDogs.newDog(y, 2)
		local b2 = {}
		run(d2, 0, 1, sense({ squirrel("r", y.x1 - 2, y.z1 - 2, 0, true) }, false, b2))
		t.eq(d2.mode, "chase")
		t.eq(b2[1], "r")
	end)

	t.test("a squirrel in the next yard over (or just outside SENSE) is left alone", function()
		local y = YardDogs.YARDS[5]
		local d = YardDogs.newDog(y, 5)
		local barks = {}
		run(d, 0, 2, sense({ squirrel("s", y.x1 + YardDogs.SENSE + 1, (y.z0 + y.z1) / 2) }, false, barks))
		t.eq(d.mode, "wander")
		t.eq(#barks, 0)
		local sq = squirrel("s", y.x1 + YardDogs.SENSE - 1, (y.z0 + y.z1) / 2)
		local now = run(d, 2, 1, sense({ sq }, false, barks))
		t.eq(d.mode, "chase", "coming in over the edge: it runs to the fence")
		-- but it barks (and a player is told it chases them out) only at one in its yard
		now = run(d, now, 20, sense({ sq }, false, barks))
		t.eq(#barks, 0, "no bark at one just outside")
		sq.x = y.x1 - 1
		run(d, now, 1, sense({ sq }, false, barks))
		t.eq(#barks, 1, "a bark once it is in")
	end)

	t.test("a dog treat calms it: it sits, ignores squirrels, and is itself again after", function()
		local y = YardDogs.YARDS[2]
		local d = YardDogs.newDog(y, 2)
		local barks = {}
		YardDogs.calm(d, 120)
		local sq = squirrel("s", y.x0 + 4, y.z0 + 4)
		local x, z = d.x, d.z
		local now = run(d, 0, 60, sense({ sq }, false, barks))
		t.eq(d.mode, "calm")
		t.eq(#barks, 0, "no barking")
		t.eq(d.x, x, "sits where it is")
		t.eq(d.z, z)
		YardDogs.calm(d, 30) -- (an earlier end never shortens it)
		t.eq(d.calmUntil, 120)
		run(d, now, 61, sense({ sq }, false, barks))
		t.eq(d.mode, "chase", "after the treat")
	end)

	t.test("at night it goes to its house and lies down facing out; by day it is up again", function()
		local y = YardDogs.YARDS[1]
		local d = YardDogs.newDog(y, 1)
		local now = run(d, 0, 20, sense({ squirrel("s", y.x0 + 3, y.z0 + 3) }, true))
		t.eq(d.mode, "sleep", "even with a squirrel about")
		t.truthy(d.lying)
		t.truthy(math.abs(d.x - y.homeX) < 1 and math.abs(d.z - y.homeZ) < 1, "at the door")
		local off = (d.yaw - math.atan2(y.faceX, y.faceZ) + math.pi) % (2 * math.pi) - math.pi
		t.near(off, 0, 0.05, "facing out of its house")
		run(d, now, 1, sense({}, false))
		t.falsy(d.lying)
		t.eq(d.mode, "wander")
	end)

	t.test("it thinks only every THINK seconds", function()
		local d = YardDogs.newDog(YardDogs.YARDS[3], 3)
		t.truthy(YardDogs.think(d, 0, sense({})))
		t.falsy(YardDogs.think(d, YardDogs.THINK / 2, sense({})))
		t.truthy(YardDogs.think(d, YardDogs.THINK, sense({})))
	end)
end
