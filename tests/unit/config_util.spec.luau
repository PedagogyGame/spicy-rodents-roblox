--!strict
-- Shared/Util/* (BUILD_PLAN §4.4 #1): Rng against V8's mulberry32 (values printed by node from
-- reference/v5_4_game.js L80-89), Signal, Trove, Spring, SpatialHash, Geometry (agrees with
-- Traffic/Swept on the 3,000 golden slab cases), Schema, BufferCodec, Log.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local BufferCodec = require("@shared/Util/BufferCodec")
local Geometry = require("@shared/Util/Geometry")
local Log = require("@shared/Util/Log")
local Rng = require("@shared/Util/Rng")
local Schema = require("@shared/Util/Schema")
local Signal = require("@shared/Util/Signal")
local SpatialHash = require("@shared/Util/SpatialHash")
local Spring = require("@shared/Util/Spring")
local Swept = require("@shared/Traffic/Swept")
local Trove = require("@shared/Util/Trove")

return function(t)
	t.test("Rng: bit-exact with V8 mulberry32", function()
		local r = Rng.new(12345)
		t.eq(r.next(), 0.9797282677609473)
		t.eq(r.next(), 0.3067522644996643)
		t.eq(r.next(), 0.484205421525985)
		t.eq(r.next(), 0.817934412509203)
		local q = Rng.new(1)
		t.eq(q.next(), 0.6270739405881613)
		t.eq(q.next(), 0.002735721180215478)
	end)

	t.test("Rng: int, pick and shuffle stay in range and repeat by seed", function()
		local a, b = Rng.new(7), Rng.new(7)
		for _ = 1, 500 do
			local x = a.int(3, 9)
			t.truthy(x >= 3 and x <= 9 and math.floor(x) == x)
			t.eq(x, b.int(3, 9))
		end
		local list = { 1, 2, 3, 4, 5, 6 }
		Rng.new(3).shuffle(list)
		table.sort(list)
		t.deepEq(list, { 1, 2, 3, 4, 5, 6 })
		t.truthy(table.find({ "a", "b" }, Rng.new(9).pick({ "a", "b" })) ~= nil)
	end)

	t.test("Signal: order, once, disconnect inside fire, errors isolated", function()
		local s = Signal.new()
		local seen = {}
		local errs = 0
		s.onError = function()
			errs += 1
		end
		local c1
		c1 = s:connect(function(v)
			table.insert(seen, "a" .. v)
			c1:disconnect()
		end)
		s:connect(function()
			error("boom")
		end)
		s:once(function(v)
			table.insert(seen, "o" .. v)
		end)
		s:connect(function(v)
			table.insert(seen, "c" .. v)
		end)
		s:fire(1)
		s:fire(2)
		t.deepEq(seen, { "a1", "o1", "c1", "c2" })
		t.eq(errs, 2)
		t.eq(s:count(), 2)
		s:destroy()
		t.eq(s:count(), 0)
	end)

	t.test("Trove: cleans in reverse order, once", function()
		local tr = Trove.new()
		local order = {}
		tr:add(function()
			table.insert(order, 1)
		end)
		tr:add({
			disconnect = function()
				table.insert(order, 2)
			end,
		})
		tr:add({
			destroy = function()
				table.insert(order, 3)
			end,
		})
		tr:clean()
		tr:clean()
		t.deepEq(order, { 3, 2, 1 })
	end)

	t.test("Spring: closed form is frame-rate independent and settles", function()
		for _, z in { 0.5, 1, 2 } do
			local a, b = Spring.new(0, 8, z), Spring.new(0, 8, z)
			a.target, b.target = 10, 10
			Spring.step(a, 0.5)
			for _ = 1, 50 do
				Spring.step(b, 0.01)
			end
			t.near(a.value, b.value, 1e-9, `damping {z}`)
			Spring.step(a, 10)
			t.near(a.value, 10, 1e-6)
		end
	end)

	t.test("SpatialHash: query matches brute force; move and remove", function()
		local h = SpatialHash.new(16)
		local r = Rng.new(11)
		local pts = {}
		for i = 1, 400 do
			local x, z, rad = r.range(-300, 300), r.range(-300, 300), r.range(0, 5)
			pts[i] = { x, z, rad }
			SpatialHash.insert(h, i, x, z, rad)
		end
		for _ = 1, 50 do
			local qx, qz, qr = r.range(-300, 300), r.range(-300, 300), r.range(1, 60)
			local got = SpatialHash.query(h, qx, qz, qr)
			local want = 0
			for _, p in pts do
				if (p[1] - qx) ^ 2 + (p[2] - qz) ^ 2 <= (p[3] + qr) ^ 2 then
					want += 1
				end
			end
			t.eq(#got, want)
		end
		SpatialHash.move(h, 1, 1000, 1000, 0)
		t.deepEq(SpatialHash.query(h, 1000, 1000, 1), { 1 })
		SpatialHash.remove(h, 1)
		t.eq(#SpatialHash.query(h, 1000, 1000, 1), 0)
		t.eq(SpatialHash.count(h), 399)
	end)

	t.test("Geometry.segmentBoxEntry agrees with Traffic/Swept on the golden slab cases", function()
		local g = serde.decode("json", fs.readFile("tests/golden/segment_box_entry.json"))
		local hits = 0
		for _, row in g.rows do
			local a, b = row[1], row[2]
			local box = { minX = -row[3], maxX = row[3], minY = row[5], maxY = row[6], minZ = -row[4], maxZ = row[4] }
			local got = Geometry.segmentBoxEntry(a[1], a[2], a[3], b[1], b[2], b[3], box)
			local want = Swept.entryN(a[1], a[2], a[3], b[1], b[2], b[3], row[3], row[4], row[5], row[6])
			t.eq(got == nil, want == nil)
			if got and want then
				hits += 1
				t.near(got, want, 1e-12)
			end
		end
		t.truthy(hits > 100)
	end)

	t.test("Geometry: AABB, OBB and closest point", function()
		local a = { minX = 0, minY = 0, minZ = 0, maxX = 2, maxY = 2, maxZ = 2 }
		t.truthy(Geometry.aabbOverlap(a, { minX = 1, minY = 1, minZ = 1, maxX = 3, maxY = 3, maxZ = 3 }))
		t.falsy(Geometry.aabbOverlap(a, { minX = 2.1, minY = 0, minZ = 0, maxX = 3, maxY = 1, maxZ = 1 }))
		t.truthy(Geometry.aabbContains(a, 1, 1, 1))
		local o = { x = 0, z = 0, hx = 2, hz = 1, yaw = math.pi / 2 }
		t.truthy(Geometry.obbContains2(o, 0, 1.9))
		t.falsy(Geometry.obbContains2(o, 1.9, 0))
		t.truthy(Geometry.obbOverlap2(o, { x = 0, z = 2.5, hx = 1, hz = 1, yaw = 0 }))
		t.falsy(Geometry.obbOverlap2(o, { x = 2.5, z = 0, hx = 1, hz = 1, yaw = 0 }))
		local tt, d2 = Geometry.closestOnSegment(5, 3, 0, 0, 10, 0)
		t.near(tt, 0.5)
		t.near(d2, 9)
	end)

	t.test("Schema: finite numbers, enums, records, arrays", function()
		local s = Schema.rec({
			verb = Schema.enum({ "Kick", "Leap" }),
			n = Schema.num({ min = 0, max = 10, int = true }),
			o = Schema.opt(Schema.str({ max = 3 })),
			a = Schema.opt(Schema.arr(Schema.num(), 2)),
		})
		t.truthy(Schema.check(s, { verb = "Kick", n = 3 }))
		t.falsy(Schema.check(s, { verb = "Fly", n = 3 }))
		t.falsy(Schema.check(s, { verb = "Kick", n = 0 / 0 }))
		t.falsy(Schema.check(s, { verb = "Kick", n = math.huge }))
		t.falsy(Schema.check(s, { verb = "Kick", n = 2.5 }))
		t.falsy(Schema.check(s, { verb = "Kick", n = 3, extra = 1 }))
		t.falsy(Schema.check(s, { verb = "Kick", n = 3, o = "long" }))
		t.falsy(Schema.check(s, { verb = "Kick", n = 3, a = { 1, 2, 3 } }))
		t.falsy(Schema.check(s, { verb = "Kick", n = 3, a = { [1] = 1, [3] = 3 } }))
		t.falsy(Schema.check(s, "nope"))
	end)

	t.test("BufferCodec: layouts round-trip; q16 within one step", function()
		local L = BufferCodec.layout({
			{ name = "a", kind = "u16" },
			{ name = "b", kind = "i8" },
			{ name = "s", kind = "q16", lo = 0, hi = 1 },
			{ name = "x", kind = "f64" },
		})
		t.eq(L.size, 13)
		local b = BufferCodec.encode(L, { a = 65535, b = -5, s = 0.3333, x = math.pi })
		local r = BufferCodec.decode(L, b)
		t.eq(r.a, 65535)
		t.eq(r.b, -5)
		t.near(r.s, 0.3333, 1 / 65535)
		t.eq(r.x, math.pi)
		local c = BufferCodec.decode(L, BufferCodec.encode(L, { a = 1e9, b = 1e9, s = 9, x = 0 }))
		t.eq(c.a, 65535)
		t.eq(c.b, 127)
		t.eq(c.s, 1)
		t.fails(function()
			BufferCodec.decode(L, buffer.create(5))
		end)
	end)

	t.test("Log: levels, sink capture, every() rate limit", function()
		local now = 0
		Log.setClock(function()
			return now
		end)
		local rec = Log.capture()
		local l = Log.new("T")
		l:debug("hidden")
		l:info("one")
		t.truthy(l:every("k", 5, "warn", "two"))
		t.falsy(l:every("k", 5, "warn", "suppressed"))
		now = 6
		t.truthy(l:every("k", 5, "warn", "three"))
		Log.setSink()
		Log.setClock()
		t.eq(#rec, 3)
		t.eq(rec[1].msg, "one")
		t.eq(rec[3].level, "warn")
		t.eq(l.suppressed, 1)
	end)
end
