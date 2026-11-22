--!strict
-- The stock options review's fixes (tests/unit/stock_options_review.spec.luau holds the reviewer's R1 and R2 cases):
--   R1  a withdrawal is two-phase in the profile (options.pending): a slow save that lands is paid once, one that
--       fails gives the options back, a pending entry found on load is given back (or settled, if this server paid
--       it), and 200 random withdrawals under every DataStore fault neither lose nor double an option;
--   R3  withdrawals never take the save budget into debt ("The bank is busy"); a receipt takes it at most DEBT below
--       zero and waits for it to refill past that;
--   R4  a receipt waits for a player who is here but not joined to the saves yet, and for a load that failed on
--       another server's lock and is tried again;
--   L2  a thank-you that fails after the grant was saved does not change PurchaseGranted;
--   L3  no grants in Studio unless Flags "stockOptionsStudio" is on;
--   L6  leave clears the player's request gaps and remembered receipts.
local MockDataStore = require("@server/Persistence/MockDataStore")
local PlayerSaves = require("@server/Persistence/PlayerSaves")
local StockOptions = require("@server/Economy/StockOptions")
local Credits = require("@server/Economy/Credits")
local Products = require("@shared/Economy/Products")
local PlayerHomes = require("@shared/World/PlayerHomes")
local Flags = require("@shared/Config/Flags")

local VIC = PlayerHomes.HOMES[1]

type Clock = { t: number, os: number, onSleep: (() -> ())? }

local function newClock(): Clock
	return { t = 1_700_000_000, os = 0, onSleep = nil }
end

-- A DataStore in front of `raw`: `hang` makes the next write yield (until its thread is resumed) and then commit
-- ("commit") or throw ("error"); `errors` makes the next writes throw at once.
local function gate(raw: any): any
	local g: any = { raw = raw, hang = nil, errors = 0 }
	function g.UpdateAsync(self: any, key: string, fn: any): (any, any)
		local mode = self.hang
		if mode then
			self.hang = nil
			coroutine.yield()
			if mode == "error" then
				error("502 (injected after a hang)")
			end
			return raw:UpdateAsync(key, fn)
		end
		if self.errors > 0 then
			self.errors -= 1
			error("502 (injected)")
		end
		return raw:UpdateAsync(key, fn)
	end
	return g
end

type Server = {
	saves: any,
	stock: any,
	wallet: any,
	players: { [number]: any },
	said: { [number]: { string } },
	threads: { thread },
	paid: number, -- cents the wallet was paid for withdrawals
	tellFails: boolean,
}

-- One simulated server. `threaded`: each DataStore job runs in its own coroutine (a hung write suspends it).
local function server(store: any, jobId: string, clk: Clock, threaded: boolean?, studio: boolean?): Server
	local sv: Server = {
		saves = nil,
		stock = nil,
		wallet = nil,
		players = {},
		said = {},
		threads = {},
		paid = 0,
		tellFails = false,
	}
	local function now(): number
		return clk.t
	end
	local function sleep(s: number)
		clk.t += s
		clk.os += s
		if clk.onSleep then
			clk.onSleep()
		end
	end
	sv.saves = PlayerSaves.new({
		store = store,
		jobId = jobId,
		now = now,
		sleep = sleep,
		spawn = function(fn: () -> ())
			if threaded then
				local co = coroutine.create(fn)
				table.insert(sv.threads, co)
				local ok, err = coroutine.resume(co)
				assert(ok, err)
			else
				fn()
			end
		end,
		tell = function(_p: any, _w: string) end,
		loaded = function(player: any, data: any): boolean
			return sv.stock.loaded(player, data) -- (as Boot/Game chains it)
		end,
		log = function(_l: string) end,
		warn = function(_l: string) end,
		lockWaits = 1,
		lockWaitSeconds = 5,
		retries = 1,
		backoffSeconds = 1,
	})
	sv.wallet = Credits.new({
		setAttr = function() end,
		log = function(_l: string) end,
		warn = function(_l: string) end,
		tell = function(_p: any, _w: string) end,
	})
	local realAdd = sv.wallet.add
	sv.wallet.add = function(player: any, cents: number, why: string): (boolean, string)
		local ok, words = realAdd(player, cents, why)
		if ok and why == StockOptions.WHY then
			sv.paid += cents
		end
		return ok, words
	end
	sv.stock = StockOptions.new({
		saves = sv.saves,
		wallet = sv.wallet,
		tell = function(player: any, words: string)
			if sv.tellFails then
				error("the screen is gone")
			end
			sv.said[player.UserId] = sv.said[player.UserId] or {}
			table.insert(sv.said[player.UserId], words)
		end,
		bodyOf = function(_player: any): (string?, number?, number?, number?)
			local p = VIC.computer
			return "human", p[1] + 2, p[2] - 1, p[3] + 2
		end,
		playerById = function(userId: number): any?
			return sv.players[userId]
		end,
		clock = function(): number
			return clk.os
		end,
		now = now,
		sleep = sleep,
		jobId = jobId,
		studio = function(): boolean
			return studio == true
		end,
		warn = function(_l: string) end,
	})
	return sv
end

-- resume every DataStore job that a hung write suspended
local function resume(sv: Server)
	for _, co in sv.threads do
		if coroutine.status(co) == "suspended" then
			local ok, err = coroutine.resume(co)
			assert(ok, err)
		end
	end
end

local function arrive(sv: Server, player: any)
	sv.players[player.UserId] = player
	sv.wallet.join(player)
	sv.saves:join(player)
	sv.stock.sweep({ player })
end

local function depart(sv: Server, player: any)
	sv.players[player.UserId] = nil
	sv.saves:leave(player)
	sv.wallet.leave(player)
	sv.stock.leave(player)
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

local function options(sv: Server, player: any): any
	return sv.saves:data(player).options
end

local function stored(raw: any, userId: number): any
	return raw:peek(`p_{userId}`).data.options
end

local function lastSaid(sv: Server, player: any): string?
	local list = sv.said[player.UserId]
	return list and list[#list]
end

return function(t)
	t.test("R1: a slow withdrawal whose write lands while the player stays is paid once, then settled", function()
		local raw = MockDataStore.new()
		local g = gate(raw)
		local clk = newClock()
		local a = server(g, "A", clk, true)
		local ann = { UserId = 60 }
		arrive(a, ann)
		t.eq(a.stock.processReceipt(receipt("k1", 60, 25)), "PurchaseGranted") -- 100 options
		local before = a.wallet.balance(ann)
		g.hang = "commit"
		local ok, words = a.stock.withdraw(ann, 40)
		t.falsy(ok)
		t.eq(words, StockOptions.WORDS.slow)
		t.eq(a.wallet.balance(ann), before, "nothing paid while the write is in flight")
		t.deepEq(options(a, ann), { held = 60, bought = 100, withdrawn = 0, pending = { ["A:1"] = 40 } })
		t.truthy(a.stock.busy[60], "busy until it is settled")
		resume(a) -- the write lands
		t.eq(a.wallet.balance(ann), before + 4000, "paid once the write landed")
		t.deepEq(options(a, ann), { held = 60, bought = 100, withdrawn = 40 })
		t.eq(lastSaid(a, ann), string.format(StockOptions.WORDS.done, 40, 40, 60))
		t.eq(a.stock.busy[60], nil)
		t.eq(a.stock.withdrawnHere(ann), 40)
		resume(a)
		t.eq(a.wallet.balance(ann), before + 4000, "and only once")
		clk.t += 10
		clk.os += 10
		a.saves:step(clk.t)
		resume(a)
		t.deepEq(stored(raw, 60), { held = 60, bought = 100, withdrawn = 40 }, "the settled entry is saved")
	end)

	t.test("R1: a slow withdrawal whose write then fails gives the options back and pays nothing", function()
		local raw = MockDataStore.new()
		local g = gate(raw)
		local clk = newClock()
		local a = server(g, "A", clk, true)
		local ann = { UserId = 61 }
		arrive(a, ann)
		t.eq(a.stock.processReceipt(receipt("k2", 61, 25)), "PurchaseGranted")
		local before = a.wallet.balance(ann)
		g.hang = "error"
		g.errors = 1 -- (its retry fails too)
		t.eq(select(2, a.stock.withdraw(ann, 40)), StockOptions.WORDS.slow)
		resume(a)
		t.eq(a.wallet.balance(ann), before, "nothing paid")
		t.deepEq(options(a, ann), { held = 100, bought = 100, withdrawn = 0 }, "back where they were")
		t.eq(lastSaid(a, ann), string.format(StockOptions.WORDS.backSlow, 40))
		t.eq(a.stock.busy[61], nil)
		t.eq(a.stock.withdrawnHere(ann), 0)
		clk.t += 10
		a.saves:step(clk.t)
		resume(a)
		t.deepEq(stored(raw, 61), { held = 100, bought = 100, withdrawn = 0 }, "and saved that way")
	end)

	t.test("R1: a pending entry left by a server that ended before paying is given back on the next load", function()
		local raw = MockDataStore.new()
		local clk = newClock()
		local x = server(raw, "X", clk)
		local ann = { UserId = 62 }
		arrive(x, ann)
		t.eq(x.stock.processReceipt(receipt("k3", 62, 25)), "PurchaseGranted")
		local before = x.wallet.balance(ann)
		raw:fail("commitThenError", 1) -- the write lands, its answer is lost
		raw:fail("error", 1) -- and the retry fails
		t.eq(select(2, x.stock.withdraw(ann, 50)), StockOptions.WORDS.notSaved)
		t.eq(x.wallet.balance(ann), before, "not paid")
		t.deepEq(options(x, ann), { held = 100, bought = 100, withdrawn = 0 }, "given back in memory")
		t.deepEq(stored(raw, 62), { held = 50, bought = 100, withdrawn = 0, pending = { ["X:1"] = 50 } })
		-- X ends before its next write; its lease lapses and the player joins Y
		clk.t += 200
		local y = server(raw, "Y", clk)
		arrive(y, ann)
		t.deepEq(options(y, ann), { held = 100, bought = 100, withdrawn = 0 }, "the 50 are back")
		clk.t += 10
		y.saves:step(clk.t)
		t.deepEq(stored(raw, 62), { held = 100, bought = 100, withdrawn = 0 }, "and saved")
	end)

	t.test("R1: a same-server rejoin after a paid withdrawal whose saves all failed settles it, never twice", function()
		local raw = MockDataStore.new()
		local g = gate(raw)
		local clk = newClock()
		local a = server(g, "A", clk)
		local ann = { UserId = 63 }
		arrive(a, ann)
		t.eq(a.stock.processReceipt(receipt("k4", 63, 25)), "PurchaseGranted")
		t.truthy((a.stock.withdraw(ann, 30)))
		local balance = a.wallet.balance(ann)
		t.deepEq(stored(raw, 63), { held = 70, bought = 100, withdrawn = 0, pending = { ["A:1"] = 30 } })
		g.errors = 100 -- every write fails: the settled entry is never saved, the release fails
		depart(a, ann)
		g.errors = 0
		clk.t += 10
		arrive(a, ann) -- back on the same server: its wallet still has the S$30
		t.eq(a.wallet.balance(ann), balance)
		t.deepEq(options(a, ann), { held = 70, bought = 100, withdrawn = 30 }, "paid here: withdrawn, not given back")
		-- the same record loaded on another server, which paid nothing: given back (the documented repay)
		local copy = MockDataStore.new()
		copy.data.p_63 = raw:peek("p_63")
		copy.data.p_63.meta.lock = nil
		local b = server(copy, "B", clk)
		arrive(b, ann)
		t.deepEq(options(b, ann), { held = 100, bought = 100, withdrawn = 0 })
	end)

	t.test("R1: 200 random withdrawals under every DataStore fault neither lose nor double an option", function()
		local seed = 2611
		local function int(lo: number, hi: number): number -- (a small LCG: Lune has no Random)
			seed = (seed * 1103515245 + 12345) % 2147483648
			return lo + seed % (hi - lo + 1)
		end
		local seen: { [string]: number } = {}
		local paidAll = 0
		for round = 1, 8 do
			local raw = MockDataStore.new()
			local g = gate(raw)
			local clk = newClock()
			local a = server(g, "A", clk, true)
			local id = 70 + round
			local ann = { UserId = id }
			arrive(a, ann)
			t.eq(a.stock.processReceipt(receipt(`z{round}`, id, 100)), "PurchaseGranted") -- 400 options
			for _ = 1, 25 do
				clk.t += StockOptions.WITHDRAW_GAP
				clk.os += StockOptions.WITHDRAW_GAP
				local fault = int(1, 6)
				if fault == 2 then
					raw:fail("error", 2) -- fails for certain
				elseif fault == 3 then
					raw:fail("commitThenError", 1) -- lands, the answer is lost
					raw:fail("error", 1)
				elseif fault == 4 then
					g.hang = "commit" -- slow, then lands
				elseif fault == 5 then
					g.hang = "error" -- slow, then fails
					g.errors = 1
				end
				local _ok, words = a.stock.withdraw(ann, int(1, 9))
				seen[words] = (seen[words] or 0) + 1
				resume(a)
				if round % 2 == 0 and int(1, 4) == 1 then
					a.saves:step(clk.t)
					resume(a)
				end
				raw.faults = {}
				g.hang, g.errors = nil, 0
				t.eq(a.stock.busy[id], nil, "every withdrawal is settled")
				local o = options(a, ann)
				t.eq(o.held + o.withdrawn, 400, "in memory: held + withdrawn = bought")
				t.eq(o.withdrawn * 100, a.paid, "withdrawn = what the wallet was paid")
			end
			depart(a, ann)
			resume(a)
			clk.t += 10
			local b = server(raw, "B", clk)
			arrive(b, ann)
			local o = options(b, ann)
			t.eq(o.pending, nil)
			t.eq(o.held + a.paid // 100, 400, `round {round}: every option is held or was paid, once`)
			t.eq(o.withdrawn * 100, a.paid)
			paidAll += a.paid
		end
		local W = StockOptions.WORDS
		t.truthy(seen[W.slow] and seen[W.notSaved], "slow and failed saves both came up")
		t.truthy(paidAll > 0, "and paid withdrawals")
	end)

	t.test("R3: a withdrawal never takes the save budget into debt; a receipt at most DEBT below zero", function()
		local raw = MockDataStore.new()
		local clk = newClock()
		local a = server(raw, "A", clk)
		local ann = { UserId = 64 }
		arrive(a, ann)
		t.eq(a.stock.processReceipt(receipt("k5", 64, 25)), "PurchaseGranted")
		local writes = raw.calls.writes
		a.saves.tokens, a.saves.tokensAt = 0.5, clk.t
		local ok, words = a.stock.withdraw(ann, 10)
		t.falsy(ok)
		t.eq(words, StockOptions.WORDS.bankBusy)
		t.eq(words, "The bank is busy, try again in a moment.")
		t.deepEq(options(a, ann), { held = 100, bought = 100, withdrawn = 0 }, "nothing taken")
		t.eq(raw.calls.writes, writes, "nothing written")
		-- receipts: down to -DEBT, then each waits for the bucket to refill past it
		a.saves.tokens, a.saves.tokensAt = 0, clk.t
		local lowest = 0
		for i = 1, 20 do
			t.eq(a.stock.processReceipt(receipt(`d{i}`, 64, 1)), "PurchaseGranted", `receipt {i}`)
			lowest = math.min(lowest, a.saves.tokens)
		end
		t.truthy(lowest >= -PlayerSaves.DEBT, `the bucket stays within -DEBT ({lowest})`)
		t.truthy(lowest < 0, "receipts may use the debt")
		t.eq(stored(raw, 64).held, 180)
		-- a withdrawal now waits for a whole token of its own
		clk.os += StockOptions.WITHDRAW_GAP
		t.eq(select(2, a.stock.withdraw(ann, 10)), StockOptions.WORDS.bankBusy)
		clk.t += 120
		clk.os += StockOptions.WITHDRAW_GAP
		t.truthy((a.stock.withdraw(ann, 10)))
		t.truthy(a.saves.tokens >= 0)
		t.eq(StockOptions.WITHDRAW_GAP, PlayerSaves.WRITE_GAP, "one withdrawal per write gap")
	end)

	t.test("R4: a receipt waits for a player not yet joined, and for a load retried after a lock", function()
		local raw = MockDataStore.new()
		local clk = newClock()
		local a = server(raw, "A", clk)
		local ann = { UserId = 65 }
		a.players[65] = ann -- here, but Boot/Game's PlayerAdded has not joined them to the saves yet
		a.wallet.join(ann)
		local t0 = clk.t
		clk.onSleep = function()
			if a.saves:status(ann) == nil and clk.t - t0 >= 3 then
				a.saves:join(ann)
			end
		end
		t.eq(a.stock.processReceipt(receipt("k6", 65, 1)), "PurchaseGranted")
		t.eq(stored(raw, 65).held, 4)
		clk.onSleep = nil
		-- a server hop: B's load finds A's live lock, gives up ("unsaved") and step tries again once A released it
		local bob = { UserId = 66 }
		arrive(a, bob)
		local b = server(raw, "B", clk)
		b.players[66] = bob
		b.wallet.join(bob)
		b.saves:join(bob)
		t.eq(b.saves:status(bob), "unsaved")
		local t1 = clk.t
		clk.onSleep = function()
			if clk.t - t1 >= 4 and a.saves:status(bob) ~= nil then
				depart(a, bob)
			end
			b.saves:step(clk.t)
		end
		t.eq(b.stock.processReceipt(receipt("k7", 66, 1)), "PurchaseGranted")
		t.truthy(clk.t - t1 <= StockOptions.RECEIPT_WAIT)
		t.eq(stored(raw, 66).held, 4)
		clk.onSleep = nil
		-- a player who leaves while it waits: NotProcessedYet at once
		local cy = { UserId = 67 }
		a.players[67] = cy
		local t2 = clk.t
		clk.onSleep = function()
			a.players[67] = nil
		end
		t.eq(a.stock.processReceipt(receipt("k8", 67, 1)), "NotProcessedYet")
		t.truthy(clk.t - t2 <= 1)
		clk.onSleep = nil
		t.truthy(StockOptions.RECEIPT_WAIT >= 30)
	end)

	t.test("L2: a thank-you that fails after the saved grant does not change PurchaseGranted", function()
		local raw = MockDataStore.new()
		local a = server(raw, "A", newClock())
		local ann = { UserId = 68 }
		arrive(a, ann)
		a.tellFails = true
		t.eq(a.stock.processReceipt(receipt("k9", 68, 2)), "PurchaseGranted")
		t.eq(stored(raw, 68).held, 8)
		a.tellFails = false
		t.eq(a.stock.processReceipt(receipt("k9", 68, 2)), "PurchaseGranted", "the retry: granted once")
		t.eq(stored(raw, 68).held, 8)
	end)

	t.test("L3: a Studio session grants nothing unless Flags stockOptionsStudio is on", function()
		local raw = MockDataStore.new()
		local a = server(raw, "A", newClock(), false, true)
		local ann = { UserId = 69 }
		arrive(a, ann)
		t.falsy(Flags.enabled("stockOptionsStudio"), "off by default")
		t.eq(a.stock.processReceipt(receipt("s1", 69, 5)), "NotProcessedYet")
		t.eq(stored(raw, 69).held, 0)
		t.eq(lastSaid(a, ann), StockOptions.WORDS.studio)
		Flags.set("stockOptionsStudio", true)
		t.eq(a.stock.processReceipt(receipt("s1", 69, 5)), "PurchaseGranted")
		t.eq(stored(raw, 69).held, 20)
		Flags.reset()
	end)

	t.test("L6: leaving clears the player's request gaps and remembered receipts", function()
		local raw = MockDataStore.new()
		local clk = newClock()
		local a = server(raw, "A", clk)
		local ann, bob = { UserId = 80 }, { UserId = 81 }
		arrive(a, ann)
		arrive(a, bob)
		a.stock.request(ann, "open")
		a.stock.request(bob, "open")
		raw:fail("error", 2)
		t.eq(a.stock.processReceipt(receipt("m1", 80, 1)), "NotProcessedYet")
		t.truthy(a.stock.receipts.pending.m1, "remembered while not durable")
		depart(a, ann)
		t.eq(a.stock.receipts.pending.m1, nil)
		for key in a.stock.last do
			t.truthy(string.sub(key, 1, 3) ~= "80:", `{key} cleared`)
		end
		t.truthy(a.stock.last["81:open"], "another player's gap stays")
	end)
end
