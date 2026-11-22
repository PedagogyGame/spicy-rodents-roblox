--!strict
-- REVIEW (D30 stock options, review/stock-options): failing cases for findings in the real-money review. Each test
-- names its finding (R1, R2) in docs of the review; they are expected to FAIL until the game code is fixed.
--   R1 (HIGH): a withdrawal whose saveNow times out ("slow") is rolled back in memory while the write holding the
--      decrement is still in flight; the write lands later, the restore never does (the player leaves during the
--      same DataStore trouble and the release fails): the options are gone and nothing was paid.
--   R2 (MEDIUM): Economy/Receipts keys `pending` by "<session>/<PurchaseId>", and PlayerSaves reuses one session id
--      per player per server, so after a same-server rejoin a stale revision from the previous Profile object makes
--      a durable, already-credited purchase answer NotProcessedYet on Roblox's retries.
local MockDataStore = require("@server/Persistence/MockDataStore")
local PlayerSaves = require("@server/Persistence/PlayerSaves")
local StockOptions = require("@server/Economy/StockOptions")
local Credits = require("@server/Economy/Credits")
local Products = require("@shared/Economy/Products")
local PlayerHomes = require("@shared/World/PlayerHomes")

local VIC = PlayerHomes.HOMES[1]

type Harness = { saves: any, stock: any, wallet: any, players: { [number]: any } }

local function harness(store: any, jobId: string, now: () -> number, sleep: (number) -> (), spawn: any): Harness
	local h: Harness = { saves = nil, stock = nil, wallet = nil, players = {} }
	h.saves = PlayerSaves.new({
		store = store,
		jobId = jobId,
		now = now,
		sleep = sleep,
		spawn = spawn or function(fn: () -> ())
			fn()
		end,
		tell = function(_p: any, _w: string) end,
		-- (as Boot/Game chains it: StockOptions settles a withdrawal a previous session left pending)
		loaded = function(player: any, data: any): boolean
			return h.stock.loaded(player, data)
		end,
		log = function(_l: string) end,
		warn = function(_l: string) end,
		lockWaits = 1,
		lockWaitSeconds = 5,
		retries = 1,
		backoffSeconds = 1,
	})
	h.wallet = Credits.new({
		setAttr = function() end,
		log = function(_l: string) end,
		warn = function(_l: string) end,
		tell = function(_p: any, _w: string) end,
	})
	h.stock = StockOptions.new({
		saves = h.saves,
		wallet = h.wallet,
		tell = function(_p: any, _w: string) end,
		bodyOf = function(_player: any): (string?, number?, number?, number?)
			local p = VIC.computer
			return "human", p[1] + 2, p[2] - 1, p[3] + 2
		end,
		playerById = function(userId: number): any?
			return h.players[userId]
		end,
		clock = function(): number
			return now()
		end,
		now = now,
		sleep = sleep,
		warn = function(_l: string) end,
	})
	return h
end

local function arrive(h: Harness, player: any)
	h.players[player.UserId] = player
	h.wallet.join(player)
	h.saves:join(player)
	h.stock.sweep({ player })
end

local function depart(h: Harness, player: any)
	h.players[player.UserId] = nil
	h.saves:leave(player)
	h.wallet.leave(player)
end

local function receipt(id: string, userId: number, robux: number): any
	return {
		PurchaseId = id,
		PlayerId = userId,
		ProductId = Products.SPICY_BUCK_ID,
		CurrencySpent = robux,
		CurrencyType = "Robux",
	}
end

return function(t)
	t.test("R1 (HIGH): a timed-out withdrawal is rolled back, its write lands late, the release fails", function()
		local raw = MockDataStore.new()
		local clockT = 1_700_000_000
		local function now(): number
			return clockT
		end
		local function sleep(s: number)
			clockT += s
		end
		local hang, failAfter = false, 0
		local store = {
			UpdateAsync = function(_self: any, key: string, fn: any): (any, any)
				if hang then
					hang = false
					coroutine.yield()
					local r1, r2 = raw:UpdateAsync(key, fn) -- the late commit
					failAfter = 10 -- every write after it fails (the release and its retry)
					return r1, r2
				end
				if failAfter > 0 then
					failAfter -= 1
					error("502 (injected: DataStore degraded)")
				end
				return raw:UpdateAsync(key, fn)
			end,
		}
		local threads: { thread } = {}
		local a = harness(store, "A", now, sleep, function(fn: () -> ())
			local co = coroutine.create(fn)
			table.insert(threads, co)
			local ok, err = coroutine.resume(co)
			assert(ok, err)
		end)
		local ann = { UserId = 42 }
		arrive(a, ann)
		t.eq(a.stock.processReceipt(receipt("r2", 42, 25)), "PurchaseGranted") -- 100 options
		local before = a.wallet.balance(ann)
		hang = true
		local ok, words = a.stock.withdraw(ann, 100)
		t.falsy(ok)
		t.eq(words, StockOptions.WORDS.slow)
		-- (fixed: not rolled back while the write may land; the options wait in a pending entry, the player busy)
		t.eq(a.saves:data(ann).options.held, 0, "not restored while the write may still land")
		local _wid, out = next(a.saves:data(ann).options.pending)
		t.eq(out, 100, "pending")
		t.eq(select(2, a.stock.withdraw(ann, 1)), StockOptions.WORDS.busy, "busy until it is settled")
		depart(a, ann) -- the release is queued behind the hung save
		for _, co in threads do
			if coroutine.status(co) == "suspended" then
				local resumed, err = coroutine.resume(co)
				assert(resumed, err)
			end
		end
		clockT += 200
		local b = harness(raw, "B", now, sleep, nil)
		arrive(b, ann)
		t.eq(a.wallet.balance(ann), before, "nothing was paid (the player left before the write was known)")
		t.eq(b.saves:data(ann).options.held, 100, "the 100 options the player was told were not taken")
	end)

	t.test("R2 (MEDIUM): a durable purchase retried after a same-server rejoin is answered PurchaseGranted", function()
		local store = MockDataStore.new()
		local clockT = 1_700_000_000
		local function now(): number
			return clockT
		end
		local function sleep(s: number)
			clockT += s
		end
		local a = harness(store, "A", now, sleep, nil)
		local ann = { UserId = 43 }
		arrive(a, ann)
		for _ = 1, 8 do
			a.saves:dirty(ann) -- ordinary play: clothing changes bump the profile's revision
		end
		store:fail("error", 2) -- the immediate save and its retry
		t.eq(a.stock.processReceipt(receipt("r3", 43, 5)), "NotProcessedYet")
		depart(a, ann) -- the release writes the grant and the ledger: it is durable now
		t.eq(store:peek("p_43").data.options.held, 20)
		t.truthy(store:peek("p_43").data.receipts.byId.r3, "the ledger entry is durable")
		clockT += 10
		arrive(a, ann) -- back on the same server: Roblox offers the receipt again
		t.eq(a.stock.processReceipt(receipt("r3", 43, 5)), "PurchaseGranted", "durable and credited: must be granted")
		t.eq(store:peek("p_43").data.options.held, 20, "and never twice")
	end)
end
