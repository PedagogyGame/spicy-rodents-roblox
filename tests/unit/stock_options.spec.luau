--!strict
-- Spicy Stock Options (owner D30): Persistence/ProfileSchema v3 (the saved options), Economy/ReceiptLedger.grantOptions,
-- Economy/Receipts through Economy/StockOptions on Persistence/PlayerSaves over MockDataStore (every receipt path:
-- first, retry, another server, failed and ambiguous saves, unknown product, amount bounds, no profile, the switch,
-- a profile still loading, a lost lock), the home computer's withdrawal (saved before the money, the S$100 cap per
-- server, every refusal, a failing save, a refusing wallet, one at a time), promptBuy, the remote's checks, and
-- Shared/World/PlayerHomes (the homes, the registry, and the four computers where the bake puts the desks).
local ProfileSchema = require("@server/Persistence/ProfileSchema")
local MockDataStore = require("@server/Persistence/MockDataStore")
local PlayerSaves = require("@server/Persistence/PlayerSaves")
local ReceiptLedger = require("@server/Economy/ReceiptLedger")
local StockOptions = require("@server/Economy/StockOptions")
local Credits = require("@server/Economy/Credits")
local Products = require("@shared/Economy/Products")
local PlayerHomes = require("@shared/World/PlayerHomes")
local Flags = require("@shared/Config/Flags")
local StockOptionsUI = require("@client/UI/StockOptionsUI")
local Bake = require("@worldgen/Bake")
local Furniture = require("@worldgen/Builders/Furniture")
local InteriorCheck = require("@worldgen/InteriorCheck")

local ID = Products.SPICY_BUCK_ID

local function clock()
	local c = { t = 1_700_000_000, os = 0 }
	return c, function(): number
		return c.t
	end, function(s: number)
		c.t += s
	end
end

type Server = {
	saves: any,
	stock: any,
	wallet: any,
	bodies: { [number]: { any } },
	players: { [number]: any },
	said: { [number]: { string } },
	sent: { [number]: { any } },
	attrs: { [number]: { [string]: any } },
	prompts: { { any } },
	jobs: { () -> () }?,
	price: number?,
}

local VIC = PlayerHomes.HOMES[1]

-- One simulated server: PlayerSaves on `store`, the real wallet, StockOptions. `deferred` keeps spawned jobs.
local function server(
	store: any,
	jobId: string,
	c: any,
	now: () -> number,
	sleep: (number) -> (),
	deferred: boolean?
): Server
	local sv: Server = {
		saves = nil,
		stock = nil,
		wallet = nil,
		bodies = {},
		players = {},
		said = {},
		sent = {},
		attrs = {},
		prompts = {},
		jobs = if deferred then {} else nil,
		price = 25,
	}
	local function attr(player: any, name: string, value: any)
		sv.attrs[player.UserId] = sv.attrs[player.UserId] or {}
		sv.attrs[player.UserId][name] = value
	end
	sv.saves = PlayerSaves.new({
		store = store,
		jobId = jobId,
		now = now,
		sleep = sleep,
		spawn = function(fn: () -> ())
			if sv.jobs then
				table.insert(sv.jobs, fn)
			else
				fn()
			end
		end,
		tell = function(_p: any, _w: string) end,
		loaded = function(player: any, data: any): boolean
			return sv.stock.loaded(player, data) -- (as Boot/Game chains it)
		end,
		log = function(_line: string) end,
		warn = function(_line: string) end,
		lockWaits = 1,
		lockWaitSeconds = 5,
		retries = 1,
		backoffSeconds = 1,
	})
	sv.wallet = Credits.new({
		setAttr = attr,
		log = function(_l: string) end,
		warn = function(_l: string) end,
		tell = function(_p: any, _w: string) end,
	})
	sv.stock = StockOptions.new({
		saves = sv.saves,
		wallet = sv.wallet,
		tell = function(player: any, words: string)
			sv.said[player.UserId] = sv.said[player.UserId] or {}
			table.insert(sv.said[player.UserId], words)
		end,
		send = function(player: any, payload: { [string]: any })
			sv.sent[player.UserId] = sv.sent[player.UserId] or {}
			table.insert(sv.sent[player.UserId], payload)
		end,
		setAttr = attr,
		bodyOf = function(player: any): (string?, number?, number?, number?)
			local b = sv.bodies[player.UserId]
			if b == nil then
				return nil
			end
			return b[1], b[2], b[3], b[4]
		end,
		playerById = function(userId: number): any?
			return sv.players[userId]
		end,
		prompt = function(player: any, productId: number)
			table.insert(sv.prompts, { player, productId })
		end,
		price = function(): number?
			return sv.price
		end,
		clock = function(): number
			return c.os
		end,
		now = now,
		sleep = sleep,
		jobId = jobId,
		warn = function(_l: string) end,
	})
	return sv
end

local function run(sv: Server)
	local jobs = sv.jobs :: { () -> () }
	while #jobs > 0 do
		table.remove(jobs, 1)()
	end
end

-- a player arrives on `sv` as a person standing at their computer in the Victorian house
local function arrive(sv: Server, player: any)
	sv.players[player.UserId] = player
	sv.wallet.join(player)
	sv.saves:join(player)
	local p = VIC.computer
	sv.bodies[player.UserId] = { "human", p[1] + 2, p[2] - 1, p[3] + 2 }
	sv.stock.sweep({ player })
end

local function depart(sv: Server, player: any)
	sv.players[player.UserId] = nil
	sv.saves:leave(player)
	sv.wallet.leave(player)
end

local function receipt(id: string, userId: number, robux: any, product: number?): any
	return {
		PurchaseId = id,
		PlayerId = userId,
		ProductId = product or ID,
		CurrencySpent = robux,
		CurrencyType = "Robux",
	}
end

local function saved(store: any, userId: number): any
	local rec = store:peek(`p_{userId}`)
	return rec and rec.data.options
end

local function lastSaid(sv: Server, player: any): string?
	local list = sv.said[player.UserId]
	return list and list[#list]
end

return function(t)
	t.test("schema v3: the template, a v2 record gains empty options, bad options are refused", function()
		local tpl = ProfileSchema.template()
		t.eq(tpl.schema, 3)
		t.deepEq(tpl.options, { held = 0, bought = 0, withdrawn = 0 })
		local v2 = ProfileSchema.template() :: any
		v2.schema = 2
		v2.options = nil
		v2.wardrobe = { alley_shirt = true }
		local d = ProfileSchema.migrate(v2) :: any
		t.eq(d.schema, 3)
		t.deepEq(d.options, { held = 0, bought = 0, withdrawn = 0 })
		t.deepEq(d.wardrobe, { alley_shirt = true })
		t.eq(v2.options, nil, "the raw record is not changed in place")
		for _, bad in
			{
				{ held = -1, bought = 0, withdrawn = 0 },
				{ held = 1.5, bought = 2, withdrawn = 0 },
				{ held = 5, bought = 4, withdrawn = 0 },
				{ held = 0, bought = 0 },
				"lots",
			}
		do
			local r = ProfileSchema.template() :: any
			r.options = bad
			t.eq(ProfileSchema.migrate(r), nil, "refused, never written over")
		end
		t.eq(ProfileSchema.migrate({ schema = 4 }), nil, "a newer record is not read")
	end)

	t.test("ledger: grantOptions credits whole options once per purchase; a refusal changes nothing", function()
		local data = ProfileSchema.template()
		local r = { PurchaseId = "a", PlayerId = 7, ProductId = ID }
		t.truthy(ReceiptLedger.grantOptions(data, r, 4000, 5))
		t.deepEq(data.options, { held = 40, bought = 40, withdrawn = 0 })
		t.eq(data.receipts.byId.a.options, 40)
		t.eq(data.receipts.byId.a.cents, 4000)
		t.eq(data.wallet.cents, 0, "the saved wallet is not touched")
		local before = ProfileSchema.deepCopy(data)
		local ok, err = ReceiptLedger.grantOptions(data, r, 4000, 6)
		t.falsy(ok)
		t.eq(err, "duplicate")
		for _, cents in { 0, 50, 150, -400, 0 / 0, math.huge } do
			t.falsy(
				ReceiptLedger.grantOptions(data, { PurchaseId = `c{cents}`, PlayerId = 7, ProductId = ID }, cents, 6)
			)
		end
		t.falsy(ReceiptLedger.grantOptions(data, { PurchaseId = "", PlayerId = 7, ProductId = ID }, 400, 6))
		t.deepEq(data, before)
	end)

	t.test("receipt: granted, saved before PurchaseGranted; a retry on the same server grants nothing more", function()
		local store = MockDataStore.new()
		local c, now, sleep = clock()
		local a = server(store, "A", c, now, sleep)
		local ann = { UserId = 7 }
		arrive(a, ann)
		local realSave = a.saves.saveNow
		local durableAtAnswer: any = nil
		a.saves.saveNow = function(self: any, player: any): (boolean, string?)
			local ok, err = realSave(self, player)
			durableAtAnswer = saved(store, 7)
			return ok, err
		end
		t.eq(a.stock.processReceipt(receipt("p1", 7, 10)), "PurchaseGranted")
		t.deepEq(durableAtAnswer, { held = 40, bought = 40, withdrawn = 0 }, "in the store before the answer")
		t.deepEq(saved(store, 7), { held = 40, bought = 40, withdrawn = 0 }, "10 Robux = 40 options")
		t.eq(store:peek("p_7").data.receipts.byId.p1.options, 40)
		t.eq(a.attrs[7].StockOptions, 40)
		t.truthy(string.find(lastSaid(a, ann) or "", "40 Spicy Stock Options added", 1, true))
		t.eq(a.stock.processReceipt(receipt("p1", 7, 10)), "PurchaseGranted", "the retry")
		t.eq(saved(store, 7).held, 40, "granted once")
		t.eq(a.wallet.balance(ann), 300, "buying puts nothing in the wallet (pocket money only)")
	end)

	t.test("receipt: the same purchase offered on another server grants nothing twice", function()
		local store = MockDataStore.new()
		local c, now, sleep = clock()
		local a, b = server(store, "A", c, now, sleep), server(store, "B", c, now, sleep)
		local ann = { UserId = 8 }
		arrive(a, ann)
		t.eq(a.stock.processReceipt(receipt("p2", 8, 5)), "PurchaseGranted")
		depart(a, ann) -- (the answer was lost on the way; Roblox offers it again where the player is next)
		arrive(b, ann)
		t.eq(b.stock.processReceipt(receipt("p2", 8, 5)), "PurchaseGranted")
		t.deepEq(saved(store, 8), { held = 20, bought = 20, withdrawn = 0 })
		t.eq(b.attrs[8].StockOptions, 20)
	end)

	t.test("receipt: a failed save is NotProcessedYet; a later offer is granted once", function()
		local store = MockDataStore.new()
		local c, now, sleep = clock()
		local a = server(store, "A", c, now, sleep)
		local ann = { UserId = 9 }
		arrive(a, ann)
		store:fail("error", 2) -- (the write and its one retry)
		t.eq(a.stock.processReceipt(receipt("p3", 9, 3)), "NotProcessedYet")
		t.eq(saved(store, 9).held, 0, "nothing durable")
		t.eq(a.stock.processReceipt(receipt("p3", 9, 3)), "PurchaseGranted", "the store is back")
		t.deepEq(saved(store, 9), { held = 12, bought = 12, withdrawn = 0 })
	end)

	t.test("receipt: an ambiguous save (written, then an error) is granted once on the retry", function()
		local store = MockDataStore.new()
		local c, now, sleep = clock()
		local a = server(store, "A", c, now, sleep)
		local ann = { UserId = 10 }
		arrive(a, ann)
		store:fail("commitThenError", 1)
		store:fail("error", 2)
		t.eq(a.stock.processReceipt(receipt("p4", 10, 1)), "NotProcessedYet")
		t.eq(a.stock.processReceipt(receipt("p4", 10, 1)), "PurchaseGranted")
		t.deepEq(saved(store, 10), { held = 4, bought = 4, withdrawn = 0 })
		-- and on a server that crashed after the ambiguous write: the record holds the ledger, so no second grant
		local store2 = MockDataStore.new()
		local x = server(store2, "X", c, now, sleep)
		local bob = { UserId = 11 }
		arrive(x, bob)
		store2:fail("commitThenError", 1)
		store2:fail("error", 2)
		t.eq(x.stock.processReceipt(receipt("p5", 11, 1)), "NotProcessedYet")
		c.t += 200 -- X is gone; its lease lapses
		local y = server(store2, "Y", c, now, sleep)
		arrive(y, bob)
		t.eq(y.stock.processReceipt(receipt("p5", 11, 1)), "PurchaseGranted")
		t.deepEq(saved(store2, 11), { held = 4, bought = 4, withdrawn = 0 })
	end)

	t.test("receipt: unknown product, unbelievable amounts, absent or unloaded players: NotProcessedYet", function()
		local store = MockDataStore.new()
		local c, now, sleep = clock()
		local a = server(store, "A", c, now, sleep)
		local ann = { UserId = 12 }
		arrive(a, ann)
		t.eq(a.stock.processReceipt(receipt("q1", 12, 10, 999)), "NotProcessedYet", "another product")
		for i, spent in { nil, 0, -5, 2.5, "10", 0 / 0, Products.MAX_ROBUX + 1 } :: { any } do
			t.eq(a.stock.processReceipt(receipt(`q2{i}`, 12, spent)), "NotProcessedYet", `spent {spent}`)
		end
		local odd = receipt("q3", 12, 10)
		odd.CurrencyType = "Tix"
		t.eq(a.stock.processReceipt(odd), "NotProcessedYet", "not Robux")
		t.eq(a.stock.processReceipt(receipt("q4", 99, 10)), "NotProcessedYet", "not on this server")
		t.eq(a.stock.processReceipt("junk"), "NotProcessedYet")
		t.eq(saved(store, 12).held, 0)
		t.eq(a.stock.processReceipt(receipt("q5", 12, Products.MAX_ROBUX)), "PurchaseGranted", "the largest believed")
		t.eq(saved(store, 12).held, Products.MAX_ROBUX * 4)
		-- saving off (no DataStore): never granted
		local off = server(nil, "OFF", c, now, sleep)
		local cy = { UserId = 13 }
		arrive(off, cy)
		t.eq(off.saves:status(cy), "off")
		t.eq(off.stock.processReceipt(receipt("q6", 13, 10)), "NotProcessedYet")
		-- a record this build cannot read: never granted, never written
		local store3 = MockDataStore.new()
		store3.data.p_14 = { data = { schema = 9 }, meta = { writes = 1 } }
		local d = server(store3, "D", c, now, sleep)
		local dee = { UserId = 14 }
		arrive(d, dee)
		t.eq(d.saves:status(dee), "corrupt")
		t.eq(d.stock.processReceipt(receipt("q7", 14, 10)), "NotProcessedYet")
		t.eq(store3.data.p_14.data.schema, 9)
	end)

	t.test("receipt: the switch off holds every receipt; back on, it is granted", function()
		local store = MockDataStore.new()
		local c, now, sleep = clock()
		local a = server(store, "A", c, now, sleep)
		local ann = { UserId = 15 }
		arrive(a, ann)
		t.truthy(Flags.enabled("stockOptions"), "on by default")
		Flags.set("stockOptions", false)
		t.eq(a.stock.processReceipt(receipt("s1", 15, 2)), "NotProcessedYet")
		t.eq(saved(store, 15).held, 0)
		local ok = a.stock.promptBuy(ann)
		t.falsy(ok)
		t.eq(#a.prompts, 0)
		t.falsy((a.stock.withdraw(ann, 1)))
		Flags.reset()
		t.eq(a.stock.processReceipt(receipt("s1", 15, 2)), "PurchaseGranted")
		t.eq(saved(store, 15).held, 8)
	end)

	t.test("receipt: waits for a profile that is still loading; a lost lock is NotProcessedYet", function()
		local store = MockDataStore.new()
		local c, now, _ = clock()
		local sv: Server
		-- the load is still queued when the receipt comes; the wait lets it run
		sv = server(store, "A", c, now, function(s: number)
			c.t += s
			if sv.jobs then
				run(sv)
			end
		end, true)
		local ann = { UserId = 16 }
		arrive(sv, ann)
		t.eq(sv.saves:status(ann), "loading")
		t.eq(sv.stock.processReceipt(receipt("w1", 16, 1)), "PurchaseGranted")
		t.eq(saved(store, 16).held, 4)
		-- a load that never comes: answered NotProcessedYet after RECEIPT_WAIT
		local store2 = MockDataStore.new()
		local c2, now2, sleep2 = clock()
		local stuck = server(store2, "S", c2, now2, sleep2, true)
		local bob = { UserId = 17 }
		arrive(stuck, bob)
		local t0 = c2.t
		t.eq(stuck.stock.processReceipt(receipt("w2", 17, 1)), "NotProcessedYet")
		t.eq(c2.t - t0, StockOptions.RECEIPT_WAIT)
		-- the lock taken by another server (ours lapsed): nothing is written here
		local store3 = MockDataStore.new()
		local c3, now3, sleep3 = clock()
		local a = server(store3, "A", c3, now3, sleep3)
		local cy = { UserId = 18 }
		arrive(a, cy)
		c3.t += 200
		local b = server(store3, "B", c3, now3, sleep3)
		arrive(b, cy)
		t.eq(a.stock.processReceipt(receipt("w3", 18, 1)), "NotProcessedYet")
		t.eq(a.saves:status(cy), "lost")
		t.eq(b.stock.processReceipt(receipt("w3", 18, 1)), "PurchaseGranted")
		t.eq(saved(store3, 18).held, 4)
	end)

	t.test("withdraw: saved off the profile before the wallet is paid; S$100 per server at most", function()
		local store = MockDataStore.new()
		local c, now, sleep = clock()
		local a = server(store, "A", c, now, sleep)
		local ann = { UserId = 20 }
		arrive(a, ann)
		t.eq(a.attrs[20].Home, VIC.lot, "the home nearest to where they first stood as a person")
		t.eq(a.stock.processReceipt(receipt("b1", 20, 50)), "PurchaseGranted") -- 200 options
		local realAdd = a.wallet.add
		local storeAtPay: any = nil
		a.wallet.add = function(player: any, cents: number, why: string): (boolean, string)
			storeAtPay = saved(store, 20)
			t.eq(why, "stock options")
			return realAdd(player, cents, why)
		end
		c.os += 1
		local ok, words = a.stock.withdraw(ann, 30)
		t.truthy(ok, words)
		t.deepEq(
			storeAtPay,
			{ held = 170, bought = 200, withdrawn = 0, pending = { ["A:1"] = 30 } },
			"taken off and saved as pending before the money moved"
		)
		t.deepEq(a.saves:profileOf(20).data.options, { held = 170, bought = 200, withdrawn = 30 }, "paid: settled")
		t.eq(a.wallet.balance(ann), 300 + 3000)
		t.eq(a.stock.withdrawnHere(ann), 30)
		t.eq(a.attrs[20].StockOptions, 170)
		local view = a.sent[20][#a.sent[20]]
		t.eq(view.kind, "view")
		t.eq(view.where, "computer")
		t.eq(view.capLeft, 70)
		t.eq(view.held, 170)
		-- over the cap: refused with how much is left
		local no, why = a.stock.withdraw(ann, 80)
		t.falsy(no)
		t.eq(why, string.format(StockOptions.WORDS.tooMany, 70))
		local soon, wait = a.stock.withdraw(ann, 70)
		t.falsy(soon, "one withdrawal per WITHDRAW_GAP")
		t.eq(wait, StockOptions.WORDS.wait)
		c.os += StockOptions.WITHDRAW_GAP
		t.truthy((a.stock.withdraw(ann, 70)))
		c.os += StockOptions.WITHDRAW_GAP
		local none, full = a.stock.withdraw(ann, 1)
		t.falsy(none)
		t.eq(full, StockOptions.WORDS.capReached)
		-- leaving and coming back to this server does not reset it
		depart(a, ann)
		arrive(a, ann)
		t.falsy((a.stock.withdraw(ann, 1)))
		t.eq(a.stock.withdrawnHere(ann), 100)
		-- another server: a fresh S$100
		depart(a, ann)
		t.deepEq(saved(store, 20), { held = 100, bought = 200, withdrawn = 100 }, "the release wrote it settled")
		local b = server(store, "B", c, now, sleep)
		arrive(b, ann)
		t.eq(b.attrs[20].StockOptions, 100)
		t.truthy((b.stock.withdraw(ann, 100)))
		t.deepEq(saved(store, 20), { held = 0, bought = 200, withdrawn = 100, pending = { ["B:1"] = 100 } })
		c.t += 10
		b.saves:step(now())
		t.deepEq(saved(store, 20), { held = 0, bought = 200, withdrawn = 200 }, "the settled entry is saved")
		c.os += StockOptions.WITHDRAW_GAP
		local empty, have = b.stock.withdraw(ann, 1)
		t.falsy(empty)
		t.truthy(have == StockOptions.WORDS.capReached or string.find(have, "0 options", 1, true) ~= nil)
	end)

	t.test("withdraw: every refusal says why and changes nothing", function()
		local store = MockDataStore.new()
		local c, now, sleep = clock()
		local a = server(store, "A", c, now, sleep)
		local ann = { UserId = 21 }
		arrive(a, ann)
		a.stock.processReceipt(receipt("r1", 21, 2)) -- 8 options
		local function refused(amount: any, words: string, msg: string)
			local before = ProfileSchema.deepCopy(saved(store, 21))
			local ok, said = a.stock.withdraw(ann, amount)
			t.falsy(ok, msg)
			t.eq(said, words, msg)
			t.deepEq(saved(store, 21), before, msg)
			t.eq(a.wallet.balance(ann), 300, msg)
			t.eq(lastSaid(a, ann), words, `{msg}: said`)
		end
		for _, bad in { 0, -1, 1.5, "10", 0 / 0, math.huge, {} } :: { any } do
			refused(bad, StockOptions.WORDS.amount, `amount {bad}`)
		end
		refused(9, string.format(StockOptions.WORDS.notEnough, 8), "more than held")
		local p = VIC.computer
		a.bodies[21] = { "human", p[1] + 30, p[2], p[3] }
		refused(1, string.format(StockOptions.WORDS.far, VIC.name), "away from the computer")
		local other = PlayerHomes.HOMES[4].computer
		a.bodies[21] = { "human", other[1], other[2], other[3] }
		refused(1, string.format(StockOptions.WORDS.far, VIC.name), "at someone else's computer")
		a.bodies[21] = { "squirrel", p[1], p[2], p[3] }
		refused(1, StockOptions.WORDS.notHuman, "a squirrel")
		a.bodies[21] = nil
		refused(1, StockOptions.WORDS.noBody, "no body")
		local bob = { UserId = 22 }
		a.players[22] = bob
		a.wallet.join(bob)
		a.saves:join(bob)
		a.bodies[22] = { "human", p[1], p[2], p[3] }
		local ok, said = a.stock.withdraw(bob, 1)
		t.falsy(ok)
		t.eq(said, StockOptions.WORDS.noHome, "never seen as a person yet: no home")
		-- the computer's prompt: someone else's home is named
		a.bodies[21] = { "human", other[1], other[2], other[3] }
		a.stock.computer(ann, PlayerHomes.HOMES[4].lot)
		t.eq(lastSaid(a, ann), string.format(StockOptions.WORDS.notHome, VIC.name))
		c.os += 1
		a.stock.computer(ann, VIC.lot)
		t.eq(a.sent[21][#a.sent[21]].where, "computer", "their own: the computer's screen")
	end)

	t.test("withdraw: a failing save gives everything back; a refusing wallet gives the options back", function()
		local store = MockDataStore.new()
		local c, now, sleep = clock()
		local a = server(store, "A", c, now, sleep)
		local ann = { UserId = 23 }
		arrive(a, ann)
		a.stock.processReceipt(receipt("f1", 23, 5)) -- 20
		store:fail("error", 2)
		local ok, words = a.stock.withdraw(ann, 10)
		t.falsy(ok)
		t.eq(words, StockOptions.WORDS.notSaved)
		t.eq(a.wallet.balance(ann), 300, "no money")
		t.eq(a.stock.withdrawnHere(ann), 0, "nothing counted")
		local p = a.saves:profileOf(23)
		t.deepEq(p.data.options, { held = 20, bought = 20, withdrawn = 0 }, "options back")
		-- the wallet refuses (no account here): the options go back and are saved again
		a.wallet.leave(ann)
		a.wallet.add = function(_p: any, _c: number, _w: string): (boolean, string)
			return false, "You have no wallet yet."
		end
		c.os += StockOptions.WITHDRAW_GAP
		local ok2, words2 = a.stock.withdraw(ann, 10)
		t.falsy(ok2)
		t.eq(words2, StockOptions.WORDS.walletRefused)
		t.deepEq(p.data.options, { held = 20, bought = 20, withdrawn = 0 })
		t.eq(a.stock.withdrawnHere(ann), 0)
		c.t += 10
		a.saves:step(now())
		t.deepEq(saved(store, 23), { held = 20, bought = 20, withdrawn = 0 }, "the give-back is saved")
		-- a wallet that throws is the same
		a.wallet.add = function(_p: any, _c: number, _w: string): (boolean, string)
			error("boom")
		end
		c.os += StockOptions.WITHDRAW_GAP
		t.falsy((a.stock.withdraw(ann, 10)))
		t.deepEq(p.data.options, { held = 20, bought = 20, withdrawn = 0 })
	end)

	t.test("withdraw: one at a time; a second request while the first is saving is refused", function()
		local store = MockDataStore.new()
		local c, now, _ = clock()
		local sv: Server
		local second: any = nil
		local armed = false
		sv = server(store, "A", c, now, function(s: number)
			c.t += s
			if armed and second == nil and sv.jobs and #sv.jobs > 0 then
				second = { sv.stock.withdraw({ UserId = 24 }, 5) }
			end
			if sv.jobs then
				run(sv)
			end
		end, true)
		local ann = { UserId = 24 }
		arrive(sv, ann)
		run(sv)
		sv.stock.processReceipt(receipt("o1", 24, 5)) -- 20
		armed = true
		local ok = sv.stock.withdraw(ann, 5)
		t.truthy(ok)
		t.truthy(second, "the second came while the first was saving")
		t.falsy(second[1])
		t.eq(second[2], StockOptions.WORDS.busy)
		t.deepEq(saved(store, 24), { held = 15, bought = 20, withdrawn = 0, pending = { ["A:1"] = 5 } })
		t.deepEq(sv.saves:profileOf(24).data.options, { held = 15, bought = 20, withdrawn = 5 })
		t.eq(sv.wallet.balance(ann), 300 + 500)
	end)

	t.test("promptBuy and the remote: refused until loaded, rate-limited, only known verbs", function()
		local store = MockDataStore.new()
		local c, now, _ = clock()
		local sv = server(store, "A", c, now, function(s: number)
			c.t += s
		end, true)
		local ann = { UserId = 25 }
		arrive(sv, ann)
		local ok, words = sv.stock.promptBuy(ann)
		t.falsy(ok)
		t.eq(words, StockOptions.WORDS.buyLoading)
		run(sv)
		c.os += StockOptions.BUY_GAP
		t.truthy((sv.stock.promptBuy(ann)))
		t.eq(#sv.prompts, 1)
		t.eq(sv.prompts[1][2], ID)
		t.falsy((sv.stock.promptBuy(ann)), "a second press at once")
		t.eq(#sv.prompts, 1)
		c.os += StockOptions.BUY_GAP
		sv.stock.request(ann, "buy")
		t.eq(#sv.prompts, 2)
		sv.stock.request(ann, "grant", 1000) -- (no such verb: nothing)
		sv.stock.request(ann, "open")
		local view = sv.sent[25][#sv.sent[25]]
		t.eq(view.kind, "view")
		t.eq(view.where, "menu")
		t.eq(view.loaded, true)
		t.eq(view.held, 0)
		t.eq(view.price, 25)
		t.eq(view.perRobux, 4)
		t.eq(view.cap, 100)
		t.eq(view.homeName, VIC.name)
		local n = #sv.sent[25]
		sv.stock.request(ann, "open")
		t.eq(#sv.sent[25], n, "an open within the gap is ignored")
		c.os += 1
		sv.stock.request(ann, "withdraw", "all")
		t.eq(lastSaid(sv, ann), StockOptions.WORDS.amount)
	end)

	t.test("the screen's words are plain: play money, no real-world value, nothing like a prize or a return", function()
		local all = table.concat(StockOptions.ABOUT, " ")
		for _, w in StockOptions.WORDS do
			all ..= " " .. w
		end
		local lower = string.lower(all)
		for _, banned in
			{
				"invest%a*",
				"profit%a*",
				"returns?",
				"interest",
				"dividends?",
				"grows?",
				"wins?",
				"winn%a*",
				"prizes?",
				"jackpot",
				"luck%a*",
				"bets?",
				"gambl%a*",
				"real money",
				"earn%a*",
			}
		do
			t.eq(string.find(lower, "%f[%a]" .. banned .. "%f[%A]"), nil, `no "{banned}"`)
		end
		t.truthy(string.find(lower, "no value outside the game", 1, true))
		t.truthy(string.find(lower, "1 option = s$1", 1, true))
		t.truthy(string.find(lower, "s$100", 1, true))
		t.eq(StockOptions.PER_ROBUX, 4)
		t.eq(StockOptions.CAP, 100)
	end)

	t.test("the screen (Client/UI/StockOptionsUI): its lines and the amounts the computer offers", function()
		local view = {
			kind = "view",
			where = "menu",
			enabled = true,
			loaded = true,
			held = 170,
			withdrawnHere = 30,
			cap = 100,
			capLeft = 70,
			homeName = "the blue cottage",
			price = 25,
			perRobux = 4,
		}
		t.deepEq(StockOptionsUI.lines(view), {
			"Your options: 170 (saved)",
			"Withdrawn on this server: S$30 of S$100",
			"Your home: the blue cottage",
			"One purchase: 25 Robux for 100 options.",
		})
		view.where = "computer"
		t.deepEq(StockOptionsUI.amounts(view), { 5, 10, 25, 50, 70 }, "the choices that fit, then the most there is")
		view.held = 12
		t.deepEq(StockOptionsUI.amounts(view), { 5, 10, 12 })
		view.held = 5
		t.deepEq(StockOptionsUI.amounts(view), { 5 }, "the most only once")
		view.held, view.capLeft = 0, 70
		t.deepEq(StockOptionsUI.amounts(view), {})
		view.held, view.capLeft = 40, 0
		t.deepEq(StockOptionsUI.amounts(view), {})
		view.enabled = false
		view.capLeft = 70
		t.deepEq(StockOptionsUI.amounts(view), {})
		t.eq(StockOptionsUI.lines(view)[1], "Spicy Stock Options are closed for now.")
		local loading = StockOptionsUI.lines({ loaded = false, where = "menu", perRobux = 4 })
		t.eq(loading[1], "Your saved options are still loading.")
		t.eq(loading[3], "You get a home when you first walk the town as a person.")
		t.eq(loading[4], "4 options for each Robux (the Roblox window shows the price).")
	end)

	t.test("PlayerSaves.saveNow: only a held profile; waits for the queue; false when it cannot", function()
		local store = MockDataStore.new()
		local c, now, sleep = clock()
		local a = server(store, "A", c, now, sleep)
		local ann = { UserId = 26 }
		t.eq(select(2, a.saves:saveNow(ann)), "absent")
		arrive(a, ann)
		local p = a.saves:profileOf(26)
		p.data.options.held, p.data.options.bought = 3, 3
		t.truthy(a.saves:saveNow(ann))
		t.eq(saved(store, 26).held, 3)
		-- a deferred queue that never runs: "slow" after SAVE_NOW_WAIT
		local c2, now2, sleep2 = clock()
		local d = server(MockDataStore.new(), "D", c2, now2, sleep2, true)
		local bob = { UserId = 27 }
		arrive(d, bob)
		run(d)
		local t0 = c2.t
		local ok, why = d.saves:saveNow(bob)
		t.falsy(ok)
		t.eq(why, "slow")
		t.truthy(c2.t - t0 >= PlayerSaves.SAVE_NOW_WAIT - 0.01)
		run(d) -- (the write lands later; the profile is then durable)
		t.eq(d.saves:profileOf(27).savedRevision, d.saves:profileOf(27).revision)
		d.saves:closeAll(0)
		t.eq(select(2, d.saves:saveNow(bob)), "absent")
	end)

	t.test("PlayerHomes: nearest, a stable registry, the attribute, inside and at the computer", function()
		t.eq(#PlayerHomes.HOMES, 4)
		for _, h in PlayerHomes.HOMES do
			t.eq(PlayerHomes.nearest(h.x, h.z).lot, h.lot)
			t.truthy(PlayerHomes.inside(h.lot, h.computer[1], h.computer[3]), `{h.lot}: the computer is inside`)
			t.falsy(PlayerHomes.inside(h.lot, h.x + h.hw + 1, h.z))
			t.truthy(PlayerHomes.atComputer(h.lot, h.computer[1] + 3, h.computer[2] - 2, h.computer[3]))
			t.falsy(PlayerHomes.atComputer(h.lot, h.computer[1] + 11, h.computer[2], h.computer[3]))
		end
		local reg = PlayerHomes.new()
		local first = reg:assign(5, 140, 140)
		t.eq(first, "core_house_3_blue_cottage")
		t.eq(reg:assign(5, -140, -140), first, "decided once")
		t.eq(reg:of(6), nil)
		local fake = {
			GetAttribute = function(_self: any, name: string): any
				return if name == "Home" then first else nil
			end,
		}
		t.eq(PlayerHomes.homeOf(fake), first)
		t.eq(
			PlayerHomes.homeOf({
				GetAttribute = function()
					return "nowhere"
				end,
			}),
			nil
		)
		t.eq(PlayerHomes.homeOf({}), nil)
		t.falsy(PlayerHomes.inside("nowhere", 0, 0))
	end)

	t.test(
		"PlayerHomes: every home's computer is the bake's desk screen, in a room that passes InteriorCheck",
		function()
			local plans = Bake.plans(Bake.data())
			local byId: { [string]: any } = {}
			for _, p in plans do
				if p.kind == "lot" then
					byId[p.id] = p
				end
			end
			for _, h in PlayerHomes.HOMES do
				local plan = byId[h.lot]
				t.truthy(plan, h.lot)
				local root, screen = nil, nil
				for _, s in plan.parts do
					if s.name == h.desk then
						root = s
					elseif s.name == h.desk .. "_Monitor" then
						screen = s
					end
				end
				t.truthy(root and (root.attrs :: any).Kit == "desk", `{h.lot}: {h.desk}`)
				t.truthy(screen, `{h.lot}: its screen`)
				t.near(screen.cx, h.computer[1], 0.01, `{h.lot} x`)
				t.near(screen.cy, h.computer[2], 0.01, `{h.lot} y`)
				t.near(screen.cz, h.computer[3], 0.01, `{h.lot} z`)
				t.eq((root.attrs :: any).Room, h.room)
				local floor = nil
				for _, s in plan.parts do
					if s.name == "Floor" then
						floor = s
					end
				end
				t.near(floor.cx, h.x, 0.01)
				t.near(floor.cz, h.z, 0.01)
				t.near(floor.sx / 2, h.hw, 0.01)
				t.near(floor.sz / 2, h.hd, 0.01)
				local check = InteriorCheck.lot(plan)
				t.eq(#check.failures, 0, `{h.lot}: {table.concat(check.failures, "; ")}`)
			end
			-- the cost: the two desks added (the Victorian house and the blue cottage), each this many parts
			local parts = #Furniture.piece("desk", Furniture.TONES.cottage).parts
			print(`      a desk computer is {parts} parts; two added to the town`)
			t.truthy(parts <= 16)
		end
	)
end
