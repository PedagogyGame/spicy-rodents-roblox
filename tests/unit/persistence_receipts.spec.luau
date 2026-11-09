--!strict
-- Server/Persistence/ProfileStore + Server/Economy/Receipts against MockDataStore (spike S15, D26,
-- risk 24): session locking between two simulated servers, lease expiry after a crash, retries,
-- and ProcessReceipt semantics under double delivery, failed and ambiguous saves and crashes.
local ProfileStore = require("@server/Persistence/ProfileStore")
local MockDataStore = require("@server/Persistence/MockDataStore")
local Receipts = require("@server/Economy/Receipts")
local Products = require("@shared/Economy/Products")

local PRODUCT = 1001
local CENTS = 10000

local function catalog()
	local tiers = Products.defaults()
	tiers[1].productId = PRODUCT
	return Products.catalog(tiers)
end

-- a fake wall clock shared by the "servers"; sleep advances it
local function clock()
	local c = { t = 1_700_000_000, slept = 0 }
	return c, function(): number
		return c.t
	end, function(s: number)
		c.t += s
		c.slept += s
	end
end

local function server(store: any, jobId: string, now: () -> number, sleep: (number) -> ())
	local ps = ProfileStore.new(store, { jobId = jobId, now = now, sleep = sleep, lockWaits = 2, lockWaitSeconds = 5 })
	local profiles: { [number]: any } = {}
	local handler = Receipts.new({
		profileOf = function(playerId: number)
			return profiles[playerId]
		end,
		catalog = catalog(),
		now = now,
	})
	return { ps = ps, profiles = profiles, handler = handler }
end

local function receipt(id: string)
	return { PurchaseId = id, PlayerId = 7, ProductId = PRODUCT }
end

return function(t)
	t.test("load creates the template and takes the lock; release clears it", function()
		local store = MockDataStore.new()
		local _, now, sleep = clock()
		local a = server(store, "A", now, sleep)
		local p, status = a.ps:load("u7")
		t.eq(status, "ok")
		t.truthy(p and p:isActive())
		t.eq(store:peek("u7").meta.lock.jobId, "A")
		t.truthy((p :: any):release())
		t.eq(store:peek("u7").meta.lock, nil)
		t.falsy((p :: any):isActive())
	end)

	t.test("two servers cannot hold one profile; a released profile moves", function()
		local store = MockDataStore.new()
		local c, now, sleep = clock()
		local a, b = server(store, "A", now, sleep), server(store, "B", now, sleep)
		local pa = a.ps:load("u7") :: any
		local pb, status, holder = b.ps:load("u7")
		t.eq(pb, nil)
		t.eq(status, "locked")
		t.eq(holder, "A")
		t.eq(c.slept, 10, "waited lockWaits x lockWaitSeconds")
		t.truthy(pa:save(), "the holder still saves")
		pa.data.wallet.cents = 55
		pa:release()
		local pb2, status2 = b.ps:load("u7")
		t.eq(status2, "ok")
		t.eq((pb2 :: any).data.wallet.cents, 55)
	end)

	t.test("a crashed server's lease expires and is stolen; the old holder can never write again", function()
		local store = MockDataStore.new()
		local c, now, sleep = clock()
		local a, b = server(store, "A", now, sleep), server(store, "B", now, sleep)
		local pa = a.ps:load("u7") :: any
		pa.data.wallet.cents = 300
		t.truthy(pa:save())
		-- A stops renewing (a crash or a hang) past the lease
		c.t += ProfileStore.DEFAULTS.leaseSeconds + 1
		local pb, status, from = b.ps:load("u7")
		t.eq(status, "stolen")
		t.eq(from, "A")
		t.eq((pb :: any).data.wallet.cents, 300)
		-- A wakes up and tries to save stale data: refused, profile marked lost
		pa.data.wallet.cents = 999999
		local ok, err = pa:save()
		t.falsy(ok)
		t.eq(err, "lost")
		t.truthy(pa.lost)
		t.eq(store:peek("u7").data.wallet.cents, 300)
		t.eq(store:peek("u7").meta.lock.jobId, "B")
	end)

	t.test("step() autosaves and keeps the lease alive", function()
		local store = MockDataStore.new()
		local c, now, sleep = clock()
		local a, b = server(store, "A", now, sleep), server(store, "B", now, sleep)
		local pa = a.ps:load("u7") :: any
		for _ = 1, 20 do -- 20 x 30 s = 600 s, three leases
			c.t += 30
			pa:step(now())
		end
		t.eq(pa.saves, 20)
		local pb, status = b.ps:load("u7")
		t.eq(pb, nil)
		t.eq(status, "locked")
	end)

	t.test("transient errors are retried with backoff; persistent errors give up", function()
		local store = MockDataStore.new()
		local c, now, sleep = clock()
		local a = server(store, "A", now, sleep)
		store:fail("throttle", 2)
		local p, status = a.ps:load("u7")
		t.eq(status, "ok")
		t.truthy(p)
		t.eq(c.slept, 1 + 2)
		store:fail("error", 5)
		local ok = (p :: any):save()
		t.falsy(ok)
		t.truthy((p :: any):isActive(), "a failed save keeps the lock; the next save retries")
		t.truthy((p :: any):save())
	end)

	t.test("an ambiguous load (committed, then error) retries into its own lock", function()
		local store = MockDataStore.new()
		local _, now, sleep = clock()
		local a = server(store, "A", now, sleep)
		store:fail("commitThenError", 1)
		local p, status = a.ps:load("u7")
		t.eq(status, "ok")
		t.truthy(p and p:isActive())
	end)

	t.test("corrupt or newer records are never overwritten", function()
		local store = MockDataStore.new()
		local _, now, sleep = clock()
		local a = server(store, "A", now, sleep)
		store.data.u7 = { data = { schema = 99 }, meta = { writes = 3 } }
		local p, status = a.ps:load("u7")
		t.eq(p, nil)
		t.eq(status, "corrupt")
		t.eq(store:peek("u7").data.schema, 99)
		local ro = ProfileStore.readOnly(a.ps, "u7")
		t.falsy(ro:isActive())
		t.deepEq({ ro:save() }, { false, "read-only" })
	end)

	t.test("ProcessReceipt: NotProcessedYet until the profile is loaded, then granted once", function()
		local store = MockDataStore.new()
		local _, now, sleep = clock()
		local a = server(store, "A", now, sleep)
		t.eq(a.handler:process(receipt("r1")), "NotProcessedYet")
		a.profiles[7] = a.ps:load("u7")
		t.eq(a.handler:process(receipt("r1")), "PurchaseGranted")
		t.eq(store:peek("u7").data.wallet.cents, CENTS, "durable before the grant")
		-- double delivery (Roblox retried because our answer was lost)
		t.eq(a.handler:process(receipt("r1")), "PurchaseGranted")
		t.eq(a.handler:process(receipt("r1")), "PurchaseGranted")
		t.eq(a.profiles[7].data.wallet.cents, CENTS)
		t.eq(a.handler.stats.credited, 1)
		t.eq(a.handler.stats.duplicates, 2)
		-- unknown product and a read-only profile are never granted
		t.eq(a.handler:process({ PurchaseId = "r2", PlayerId = 7, ProductId = 5 }), "NotProcessedYet")
		a.profiles[7] = ProfileStore.readOnly(a.ps, "u7")
		t.eq(a.handler:process(receipt("r3")), "NotProcessedYet")
	end)

	t.test("ProcessReceipt: a failed save is not granted and the redelivery does not double-credit", function()
		local store = MockDataStore.new()
		local _, now, sleep = clock()
		local a = server(store, "A", now, sleep)
		a.profiles[7] = a.ps:load("u7")
		store:fail("error", ProfileStore.DEFAULTS.retries + 1)
		t.eq(a.handler:process(receipt("r1")), "NotProcessedYet")
		t.eq(store:peek("u7").data.wallet.cents, 0)
		t.eq(a.profiles[7].data.wallet.cents, CENTS, "held in memory, pending")
		t.eq(a.handler:process(receipt("r1")), "PurchaseGranted")
		t.eq(store:peek("u7").data.wallet.cents, CENTS)
		t.eq(a.handler.stats.credited, 1)
	end)

	t.test("ProcessReceipt: an ambiguous save (committed, then error) credits once", function()
		local store = MockDataStore.new()
		local _, now, sleep = clock()
		local a = server(store, "A", now, sleep)
		a.profiles[7] = a.ps:load("u7")
		a.ps.retries = 0
		store:fail("commitThenError", 1)
		t.eq(a.handler:process(receipt("r1")), "NotProcessedYet")
		t.eq(store:peek("u7").data.wallet.cents, CENTS, "the write landed")
		t.eq(a.handler:process(receipt("r1")), "PurchaseGranted")
		t.eq(store:peek("u7").data.wallet.cents, CENTS)
		t.eq(#store:peek("u7").data.receipts.ids, 1)
	end)

	t.test("ProcessReceipt across a crash after the save: the next server grants without crediting", function()
		local store = MockDataStore.new()
		local c, now, sleep = clock()
		local a, b = server(store, "A", now, sleep), server(store, "B", now, sleep)
		a.profiles[7] = a.ps:load("u7")
		t.eq(a.handler:process(receipt("r1")), "PurchaseGranted")
		-- A crashes before Roblox saw the answer; the player rejoins on B after the lease
		c.t += ProfileStore.DEFAULTS.leaseSeconds + 1
		b.profiles[7] = b.ps:load("u7")
		t.eq(b.handler:process(receipt("r1")), "PurchaseGranted")
		t.eq(b.handler.stats.credited, 0)
		t.eq(b.profiles[7].data.wallet.cents, CENTS)
	end)

	t.test("ProcessReceipt across a crash before the save: credited exactly once on the next server", function()
		local store = MockDataStore.new()
		local c, now, sleep = clock()
		local a, b = server(store, "A", now, sleep), server(store, "B", now, sleep)
		a.profiles[7] = a.ps:load("u7")
		store:fail("error", ProfileStore.DEFAULTS.retries + 1)
		t.eq(a.handler:process(receipt("r1")), "NotProcessedYet")
		-- A dies with the credit only in memory
		c.t += ProfileStore.DEFAULTS.leaseSeconds + 1
		-- while B waits for the lock, a redelivery to B is refused (profile not loaded yet)
		t.eq(b.handler:process(receipt("r1")), "NotProcessedYet")
		b.profiles[7] = b.ps:load("u7")
		t.eq(b.profiles[7].data.wallet.cents, 0)
		t.eq(b.handler:process(receipt("r1")), "PurchaseGranted")
		t.eq(store:peek("u7").data.wallet.cents, CENTS)
	end)

	t.test("ProcessReceipt on a server whose lock was stolen answers NotProcessedYet", function()
		local store = MockDataStore.new()
		local c, now, sleep = clock()
		local a, b = server(store, "A", now, sleep), server(store, "B", now, sleep)
		a.profiles[7] = a.ps:load("u7")
		c.t += ProfileStore.DEFAULTS.leaseSeconds + 1
		b.profiles[7] = b.ps:load("u7")
		-- A has not noticed yet: its save finds B's lock, the receipt is not granted on A
		t.eq(a.handler:process(receipt("r1")), "NotProcessedYet")
		t.eq(store:peek("u7").data.wallet.cents, 0)
		t.eq(b.handler:process(receipt("r1")), "PurchaseGranted")
		t.eq(store:peek("u7").data.wallet.cents, CENTS)
		t.eq(a.handler:process(receipt("r1")), "NotProcessedYet", "A stays lost")
	end)

	t.test("randomised: 2,000 deliveries with faults and crashes never double-credit", function()
		-- a small LCG: Lune has no Random
		local seed = 15
		local rng = {
			NextNumber = function(_self: any): number
				seed = (seed * 1103515245 + 12345) % 2147483648
				return seed / 2147483648
			end,
			NextInteger = function(self: any, lo: number, hi: number): number
				return lo + math.floor(self:NextNumber() * (hi - lo + 1))
			end,
		}
		local store = MockDataStore.new()
		local c, now, sleep = clock()
		local servers = { server(store, "A", now, sleep), server(store, "B", now, sleep) }
		local active = 1
		servers[1].profiles[7] = servers[1].ps:load("u7")
		local granted: { [string]: boolean } = {}
		local outstanding: { string } = {}
		local recent: { string } = {}
		local total = 0
		local nextId = 0
		for _ = 1, 2000 do
			local roll = rng:NextNumber()
			if roll < 0.05 then
				store:fail(if rng:NextNumber() < 0.5 then "error" else "commitThenError", 1)
			elseif roll < 0.07 then
				-- crash the active server and fail over after the lease
				local dead = servers[active]
				dead.profiles[7] = nil
				active = 3 - active
				local fresh = server(store, if active == 1 then "A" else "B", now, sleep)
				servers[active] = fresh
				c.t += ProfileStore.DEFAULTS.leaseSeconds + 1
				fresh.profiles[7] = fresh.ps:load("u7")
			end
			-- Roblox redelivers ungranted receipts; a granted one comes back only when our answer was
			-- lost (a crash right after the grant), so redeliveries of granted ids stay recent
			local id: string
			local pick = rng:NextNumber()
			if #outstanding > 0 and pick < 0.5 then
				id = outstanding[rng:NextInteger(1, #outstanding)]
			elseif #recent > 0 and pick < 0.65 then
				id = recent[rng:NextInteger(1, #recent)]
			else
				nextId += 1
				id = `rand{nextId}`
				table.insert(outstanding, id)
				total += 1
			end
			if servers[active].handler:process(receipt(id)) == "PurchaseGranted" then
				granted[id] = true
				local at = table.find(outstanding, id)
				if at then
					table.remove(outstanding, at)
					table.insert(recent, id)
					if #recent > 20 then
						table.remove(recent, 1)
					end
				end
			end
			c.t += 1
		end
		-- drain: Roblox keeps redelivering until granted
		for _, id in outstanding do
			for _ = 1, 3 do
				if servers[active].handler:process(receipt(id)) == "PurchaseGranted" then
					granted[id] = true
					break
				end
			end
		end
		local count = 0
		for _ in granted do
			count += 1
		end
		t.eq(count, total, "every purchase granted in the end")
		local stored = store:peek("u7").data
		t.eq(stored.wallet.cents, count * CENTS, "credited exactly once each")
	end)
end
