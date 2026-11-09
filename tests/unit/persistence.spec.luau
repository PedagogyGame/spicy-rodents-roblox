--!strict
-- Server/Persistence/Serializer + MemoryStore + Profiles (BUILD_PLAN §3.20, §4.4 #6b, D26): canonical
-- versioned JSON that round-trips every profile shape, refuses what a DataStore would mangle, an
-- in-memory store holding the exact strings, and the Profiles facade over S15's ProfileStore (locking,
-- read-only fallback, release) with the receipt ledger surviving a reload.
local serde = require("@lune/serde")
local MemoryStore = require("@server/Persistence/MemoryStore")
local ProfileSchema = require("@server/Persistence/ProfileSchema")
local Profiles = require("@server/Persistence/Profiles")
local ReceiptLedger = require("@server/Economy/ReceiptLedger")
local Serializer = require("@server/Persistence/Serializer")

local function sample(): ProfileSchema.Data
	local d = ProfileSchema.template()
	d.wallet.cents = 123456
	d.wardrobe = { green_set_a = true, sewer_fedora = true }
	d.inventory = { water_gun = 1, kite = 2 }
	d.reputation = -7.25
	d.stats = { activeMinutes = 61, kicks = 3, lifetimeAnimalCents = 150 }
	return d
end

return function(t)
	t.test("encode is canonical (sorted keys, exact integers) and valid JSON", function()
		local text = Serializer.encode({ b = 1, a = { 3, 2.5, "x" }, c = { z = true, y = false } })
		t.eq(text, '{"a":[3,2.5,"x"],"b":1,"c":{"y":false,"z":true}}')
		t.deepEq(serde.decode("json", text), { a = { 3, 2.5, "x" }, b = 1, c = { y = false, z = true } })
		t.eq(Serializer.encode(2 ^ 52 + 1), "4503599627370497")
		t.eq(Serializer.encode('q"\\\n\1'), '"q\\"\\\\\\n\\u0001"')
	end)

	t.test("decode is the inverse; doubles round-trip bit-exactly", function()
		for _, v in { 0.1, 1 / 3, -2.0752915949449546, 1e-300, 123456789.125 } do
			t.eq(Serializer.decode(Serializer.encode(v)), v)
		end
		local v = { s = "héllo \u{1F600}", n = { 1, 2, { k = "v" } }, e = {} }
		t.deepEq(Serializer.decode(Serializer.encode(v)), v)
		t.deepEq(Serializer.decode(' { "a" : [ 1 , 2 ] , "b" : null } '), { a = { 1, 2 } })
		t.fails(function()
			Serializer.decode("{")
		end)
		t.fails(function()
			Serializer.decode("[1] x")
		end)
	end)

	t.test("refuses NaN, infinity, functions, mixed and sparse tables", function()
		local sparse: { [number]: number } = {}
		sparse[1], sparse[3] = 1, 3
		local mixed: { [any]: number } = { 1 }
		mixed.x = 2
		for _, bad in { 0 / 0, math.huge, print, mixed, sparse, { [true] = 1 } } :: { any } do
			t.fails(function()
				Serializer.encode(bad)
			end)
		end
	end)

	t.test("the profile round-trips through the versioned envelope", function()
		local d = sample()
		ReceiptLedger.grant(d, { PurchaseId = "p1", PlayerId = 9, ProductId = 111 } :: any, 10000, 5)
		local back = Serializer.unpack(Serializer.pack({ data = d, meta = { writes = 3 } }))
		t.deepEq(back.data, d)
		t.truthy(ProfileSchema.validate(back.data))
		t.deepEq({ Serializer.unpack('{"format":"spicy-profile","v":99,"record":{}}') }, {
			nil,
			"envelope v99 is newer than this server (v1)",
		})
		local _, err = Serializer.unpack("not json")
		t.truthy(string.find(err :: string, "corrupt") ~= nil)
		local _, err2 = Serializer.unpack('{"v":1}')
		t.eq(err2, "not a profile envelope")
	end)

	t.test("MemoryStore keeps strings; a nil transform cancels the write", function()
		local s = MemoryStore.new()
		s:UpdateAsync("k", function(old)
			t.eq(old, nil)
			return { n = 1 }
		end)
		t.isType(s:raw("k"), "string")
		s:UpdateAsync("k", function(_old)
			return nil
		end)
		t.eq(s:writes(), 1)
		t.deepEq(s:GetAsync("k"), { n = 1 })
	end)

	t.test("Profiles: load, edit, save, release, reload on another server", function()
		local now = 1000
		local store = MemoryStore.new()
		local clock = function()
			return now
		end
		local a = Profiles.new({ store = store, jobId = "A", now = clock })
		local player = { UserId = 77 }
		local data, status = a:load(player)
		t.eq(status, "ok")
		data.wallet.cents = 500
		ReceiptLedger.grant(data, { PurchaseId = "r1", PlayerId = 77, ProductId = 1 } :: any, 400, now)
		t.truthy(a:save(player))
		t.falsy(a:locked(player))
		-- a second server cannot take the live profile: read-only session, nothing saved
		local b = Profiles.new({ store = store, jobId = "B", now = clock })
		local _, st = b:load(player)
		t.eq(st, "locked")
		t.truthy(b:locked(player))
		t.deepEq({ b:save(player) }, { false, "read-only" })
		b:release(player)
		-- released by A, B loads it with the receipt ledger intact (no double credit)
		t.truthy(a:release(player))
		local d2 = b:load(player)
		t.eq(d2.wallet.cents, 900)
		t.deepEq({ ReceiptLedger.grant(d2, { PurchaseId = "r1", PlayerId = 77, ProductId = 1 } :: any, 400, now) }, {
			false,
			"duplicate",
		})
		t.truthy(string.find(store:raw(Profiles.key(77)) :: string, '"format":"spicy-profile"', 1, true) ~= nil)
		b:releaseAll()
		t.eq(b:data(player), nil)
	end)
end
