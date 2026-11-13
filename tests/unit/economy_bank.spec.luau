--!strict
-- Shared/Economy/Bank: the town's money, pure. Whole cents, never negative, every change logged with its
-- reason; a spend larger than the balance, two spends racing, a player leaving mid-spend; pocket money once
-- per join; the timed pass on the game clock; what would be saved, and putting it back.
local Bank = require("@shared/Economy/Bank")
local EconomyRules = require("@shared/Economy/EconomyRules")
local Tunables = require("@shared/Config/Tunables")
local Rng = require("@shared/Util/Rng")

local DAY = 720

type World = { bank: Bank.Bank, t: number, seen: { Bank.Entry }, passed: { any } }

local function world(pocket: number?): World
	local w = { t = 6480, seen = {}, passed = {} } :: World
	w.bank = Bank.new({
		now = function(): number
			return w.t
		end,
		daySeconds = DAY,
		pocket = pocket,
		changed = function(_id: any, entry: Bank.Entry)
			table.insert(w.seen, entry)
		end,
		passed = function(id: any, name: string, untilSeconds: number)
			table.insert(w.passed, { id, name, untilSeconds })
		end,
	})
	return w
end

local PASS = EconomyRules.pass("paintball") :: Bank.PassSpec

return function(t)
	t.test("pocket money: S$3.00 on joining, once per join, a top-up and never a stack", function()
		t.eq(EconomyRules.pocketMoney(), 300, "the one tunable: Tunables economy.pocketMoneyCents")
		local w = world(EconomyRules.pocketMoney())
		local a, given = w.bank:join(7)
		t.eq(given, 300)
		t.eq(w.bank:balance(7), 300)
		t.truthy(a.open and a.pocket == 300)
		t.deepEq(w.seen, { { id = 7, delta = 300, why = "pocket money", balance = 300, at = 6480 } })
		-- a second join without a leave gives nothing, even after spending
		t.truthy(w.bank:spend(7, 204, "the whole corner store"))
		local _, again = w.bank:join(7)
		t.eq(again, 0)
		t.eq(w.bank:balance(7), 96)
		-- leaving and coming back: topped up to the amount, not given it again on top
		w.bank:leave(7)
		local _, back = w.bank:join(7)
		t.eq(back, 204)
		t.eq(w.bank:balance(7), 300)
		-- someone who has earned more than the amount gets nothing
		t.truthy(w.bank:add(7, 50, "mowing a lawn"))
		w.bank:leave(7)
		local _, rich = w.bank:join(7)
		t.eq(rich, 0)
		t.eq(w.bank:balance(7), 350)
		t.eq(w.bank.accounts[7].pocket, 504, "pocket money given so far is kept (for the day it is saved)")
		-- no pocket money configured: a wallet at nothing
		local bare = world(nil)
		local _, none = bare.bank:join(1)
		t.eq(none, 0)
		t.eq(bare.bank:balance(1), 0)
		-- the tunable is read at each join, and a bad value reads as none
		Tunables.applyOverrides({ ["economy.pocketMoneyCents"] = 120 })
		t.eq(EconomyRules.pocketMoney(), 120)
		Tunables.applyOverrides({ ["economy.pocketMoneyCents"] = 12.5 })
		t.eq(EconomyRules.pocketMoney(), 0)
		Tunables.reset()
		t.eq(EconomyRules.pocketMoney(), 300)
	end)

	t.test("spend: whole cents, the words to show, and a balance that is never negative", function()
		local w = world(300)
		w.bank:join("ann")
		t.deepEq({ w.bank:spend("ann", 12, "coffee") }, { true, "Paid 12c for coffee. You have S$2.88." })
		t.eq(w.bank:balance("ann"), 288)
		-- a spend larger than the balance: refused with the price and what is held; nothing changes
		t.deepEq({ w.bank:spend("ann", 289, "a kite") }, { false, "You need 289c; you have 288c" })
		t.eq(w.bank:balance("ann"), 288)
		t.eq(#w.seen, 2, "a refusal is not a change")
		-- exactly everything is allowed, and then nothing is
		t.truthy(w.bank:spend("ann", 288, "everything"))
		t.eq(w.bank:balance("ann"), 0)
		t.deepEq({ w.bank:spend("ann", 1, "bubble gum") }, { false, "You need 1c; you have 0c" })
		-- not a price: fractions, negatives, not-a-number, infinity, a string
		for _, bad in { 0.5, -3, 0 / 0, math.huge, "12" :: any } do
			t.deepEq({ w.bank:spend("ann", bad, "x") }, { false, Bank.WORDS.amount })
			t.deepEq({ w.bank:add("ann", bad, "x") }, { false, Bank.WORDS.amount })
		end
		t.eq(w.bank:balance("ann"), 0)
		-- free is fine and is not a change
		local n = #w.seen
		t.deepEq({ w.bank:spend("ann", 0, "a glass of water") }, { true, "Nothing to pay for a glass of water." })
		t.eq(#w.seen, n)
		-- nobody: no wallet, in words
		t.deepEq({ w.bank:spend("nobody", 1, "x") }, { false, Bank.WORDS.none })
		t.deepEq({ w.bank:add("nobody", 1, "x") }, { false, Bank.WORDS.none })
		t.eq(w.bank:balance("nobody"), 0)
		t.deepEq({ w.bank:can("ann", 0) }, { true, "" })
		t.deepEq({ w.bank:can("ann", 5) }, { false, "You need 5c; you have 0c" })
	end)

	t.test("add: pay with a reason; the cap holds", function()
		local w = world(0)
		w.bank:join(1)
		t.deepEq({ w.bank:add(1, 5, "mowing a lawn") }, { true, "+5c: mowing a lawn. You have S$0.05." })
		t.truthy(w.bank:add(1, 100_000_000_000_000 - 5, "a windfall"))
		t.deepEq({ w.bank:add(1, 1, "one more") }, { false, Bank.WORDS.full })
		t.eq(w.bank:balance(1), 100_000_000_000_000)
	end)

	t.test("every change is logged with its reason: the purse, the bank's list and the hook", function()
		local w = world(300)
		w.bank:join(1)
		w.bank:join(2)
		w.t = 6500
		w.bank:spend(1, 12, "coffee")
		w.bank:add(2, 4, "a tip")
		w.bank:spend(2, 500, "too much")
		w.bank:buyPass(1, PASS)
		local want = {
			{ id = 1, delta = 300, why = "pocket money", balance = 300, at = 6480 },
			{ id = 2, delta = 300, why = "pocket money", balance = 300, at = 6480 },
			{ id = 1, delta = -12, why = "coffee", balance = 288, at = 6500 },
			{ id = 2, delta = 4, why = "a tip", balance = 304, at = 6500 },
			{ id = 1, delta = -20, why = "a paintball pass", balance = 268, at = 6500 },
		}
		t.deepEq(w.bank.entries, want)
		t.deepEq(w.seen, want)
		local mine = (w.bank:purse(1) :: any).history
		t.eq(#mine, 3)
		t.deepEq(mine[3], { delta = -20, why = "a paintball pass", balance = 268 })
		-- the log is a ring: the last Bank.LOG changes
		for _ = 1, Bank.LOG + 20 do
			w.bank:add(2, 1, "a penny")
		end
		t.eq(#w.bank.entries, Bank.LOG)
		t.eq(w.bank.entries[Bank.LOG].balance, 304 + Bank.LOG + 20)
		-- the sum of an account's changes is its balance: replay the hook's record
		local sum = 0
		for _, e in w.seen do
			if e.id == 2 then
				sum += e.delta
				t.eq(e.balance, sum)
			end
		end
		t.eq(sum, w.bank:balance(2))
	end)

	t.test("a hook that throws never undoes or blocks a change", function()
		local now = 0
		local bank = Bank.new({
			now = function(): number
				return now
			end,
			daySeconds = DAY,
			pocket = 300,
			changed = function()
				error("the screen is broken")
			end,
			passed = function()
				error("so is the door")
			end,
		})
		bank:join(1)
		t.eq(bank:balance(1), 300)
		t.truthy(bank:spend(1, 10, "soda"))
		t.truthy(bank:buyPass(1, PASS))
		t.eq(bank:balance(1), 270)
		t.truthy(bank:hasPass(1, "paintball"))
		t.eq(bank.faults, 4)
	end)

	t.test("two spends racing for the same money: one wins, the other is refused, never below nothing", function()
		-- with nothing to wait for a spend is one step: the second simply finds what the first left
		local w = world(0)
		w.bank:join(1)
		w.bank:add(1, 10, "found")
		t.truthy(w.bank:spend(1, 7, "a football"))
		t.deepEq({ w.bank:spend(1, 7, "a football") }, { false, "You need 7c; you have 3c" })
		-- with a handing-over that waits: two purchases start before either finishes
		local w2 = world(0)
		w2.bank:join(1)
		w2.bank:add(1, 10, "found")
		local results: { [string]: { any } } = {}
		local function buyer(name: string): thread
			return coroutine.create(function()
				results[name] = {
					w2.bank:spend(1, 7, name, function(): (boolean?, string?)
						coroutine.yield() -- the shop is busy handing it over
						return true
					end),
				}
			end)
		end
		local first, second = buyer("a football"), buyer("a frisbee")
		coroutine.resume(first)
		t.eq(w2.bank:balance(1), 3, "the first buyer's money is already out of reach")
		t.eq(w2.bank.accounts[1].held, 7)
		coroutine.resume(second)
		t.deepEq(results["a frisbee"], { false, "You need 7c; you have 3c" })
		t.eq(coroutine.status(second), "dead", "the loser is told at once, without waiting")
		coroutine.resume(first)
		t.deepEq(results["a football"], { true, "Paid 7c for a football. You have S$0.03." })
		t.eq(w2.bank:balance(1), 3)
		t.eq(w2.bank.accounts[1].held, 0)
		-- the winner's handing-over fails: the money is back, and the next buyer can have it
		local w3 = world(0)
		w3.bank:join(1)
		w3.bank:add(1, 10, "found")
		local out: { any } = {}
		local co = coroutine.create(function()
			out = {
				w3.bank:spend(1, 7, "a kite", function(): (boolean?, string?)
					coroutine.yield()
					return false, "The shelf is empty."
				end),
			}
		end)
		coroutine.resume(co)
		t.deepEq({ w3.bank:spend(1, 7, "a frisbee") }, { false, "You need 7c; you have 3c" })
		coroutine.resume(co)
		t.deepEq(out, { false, "The shelf is empty." })
		t.eq(w3.bank:balance(1), 10)
		t.truthy(w3.bank:spend(1, 7, "a frisbee"))
		t.deepEq(
			w3.bank.entries[#w3.bank.entries - 1],
			{ id = 1, delta = 7, why = "refund: a kite", balance = 10, at = 6480 }
		)
	end)

	t.test("many buyers at once, in any order: never negative, and the log adds up", function()
		for seed = 1, 40 do
			local rng = Rng.new(seed)
			local w = world(0)
			w.bank:join(1)
			local start = rng.int(0, 60)
			w.bank:add(1, start, "found")
			local live: { thread } = {}
			local paid = 0
			for i = 1, 12 do
				local price = rng.int(0, 25)
				local waits = rng.int(0, 3)
				local fails = (rng.next() < 0.3)
				local co = coroutine.create(function()
					local ok = w.bank:spend(1, price, `item {i}`, function(): (boolean?, string?)
						for _ = 1, waits do
							coroutine.yield()
						end
						if fails and (rng.next() < 0.5) then
							error("the shop fell over")
						end
						return not fails
					end)
					if ok then
						paid += price
					end
				end)
				table.insert(live, co)
			end
			-- run them interleaved, picking at random who goes next
			while #live > 0 do
				local i = rng.int(1, #live)
				coroutine.resume(live[i])
				t.truthy(w.bank:balance(1) >= 0, `seed {seed}: below nothing`)
				t.truthy(w.bank.accounts[1].held >= 0)
				if coroutine.status(live[i]) == "dead" then
					table.remove(live, i)
				end
			end
			t.eq(w.bank:balance(1), start - paid, `seed {seed}`)
			t.eq(w.bank.accounts[1].held, 0)
			local sum = 0
			for _, e in w.seen do
				sum += e.delta
				t.truthy(e.balance >= 0 and e.balance == sum, `seed {seed}: the log does not add up`)
			end
		end
	end)

	t.test("a player leaving mid-spend: charged only for what was handed over, and nothing spent after", function()
		-- the shop was still handing it over when the player left, and then could not: the money is back
		local w = world(300)
		w.bank:join(1)
		local out: { any } = {}
		local co = coroutine.create(function()
			out = {
				w.bank:spend(1, 30, "a kite", function(): (boolean?, string?)
					coroutine.yield()
					return false -- nobody to hand it to
				end),
			}
		end)
		coroutine.resume(co)
		t.eq(w.bank:balance(1), 270)
		w.bank:leave(1)
		t.falsy(w.bank:has(1))
		coroutine.resume(co)
		t.deepEq(out, { false, "That did not work, so you were not charged for a kite." })
		t.eq(w.bank:balance(1), 300, "refunded into the account they left behind")
		-- gone: nothing can be spent, in words; pay still owed is kept
		t.deepEq({ w.bank:spend(1, 5, "nachos") }, { false, Bank.WORDS.gone })
		t.deepEq({ w.bank:can(1, 5) }, { false, Bank.WORDS.gone })
		t.truthy(w.bank:buyPass(1, PASS) == false)
		t.truthy(w.bank:add(1, 4, "the end of a shift"))
		t.eq(w.bank:balance(1), 304)
		-- back again: the account as it was left, no pocket money on top
		local _, given = w.bank:join(1)
		t.eq(given, 0)
		t.eq(w.bank:balance(1), 304)
		-- the handing-over had already happened when they left: the charge stands
		local done: { any } = {}
		local co2 = coroutine.create(function()
			done = {
				w.bank:spend(1, 30, "a kite", function(): (boolean?, string?)
					coroutine.yield()
					return true
				end),
			}
		end)
		coroutine.resume(co2)
		w.bank:leave(1)
		coroutine.resume(co2)
		t.truthy(done[1])
		t.eq(w.bank:balance(1), 274)
		-- leaving and coming straight back while a purchase is still in flight is not a way to more money
		local w2 = world(300)
		w2.bank:join(1)
		local co3 = coroutine.create(function()
			w2.bank:spend(1, 250, "a jet ski", function(): (boolean?, string?)
				coroutine.yield()
				return false
			end)
		end)
		coroutine.resume(co3)
		w2.bank:leave(1)
		local _, topUp = w2.bank:join(1)
		t.eq(topUp, 0, "the 250c in flight still counts as theirs")
		coroutine.resume(co3)
		t.eq(w2.bank:balance(1), 300)
		-- leaving twice, or someone who never joined leaving, is harmless
		w2.bank:leave(1)
		w2.bank:leave(1)
		w2.bank:leave("never")
		t.falsy(w2.bank:has("never"))
	end)

	t.test(
		"the pass: 20c for five in-game days on the game clock, one at a time, the same words as paintball",
		function()
			t.eq(PASS.cents, EconomyRules.PRICES.paintball_pass)
			t.eq(PASS.days, 5)
			t.eq(PASS.bought, "Pass bought: five days of paintball and both lounges.")
			t.eq(PASS.has, "You already have a pass.")
			t.eq(EconomyRules.pass("backstage"), nil)
			local w = world(300)
			w.bank:join(1)
			t.falsy(w.bank:hasPass(1, "paintball"))
			t.eq(w.bank:passLeft(1, "paintball"), 0)
			t.eq(w.bank:passUntil(1, "paintball"), nil)
			t.deepEq({ w.bank:buyPass(1, PASS) }, { true, PASS.bought })
			t.eq(w.bank:balance(1), 280)
			t.truthy(w.bank:hasPass(1, "paintball"))
			t.eq(w.bank:passLeft(1, "paintball"), 5)
			t.eq(w.bank:passUntil(1, "paintball"), 6480 + 5 * DAY)
			t.deepEq(w.passed, { { 1, "paintball", 6480 + 5 * DAY } })
			-- a holder is never sold a second one, and is not charged for asking
			t.deepEq({ w.bank:buyPass(1, PASS) }, { false, PASS.has })
			t.eq(w.bank:balance(1), 280)
			-- time runs on the game clock: a fraction of a day counts
			w.t += 1.5 * DAY
			t.near(w.bank:passLeft(1, "paintball"), 3.5)
			-- it runs while they are away
			w.bank:leave(1)
			w.t += 3.5 * DAY - 1
			t.truthy(w.bank:hasPass(1, "paintball"))
			w.t += 1
			t.falsy(w.bank:hasPass(1, "paintball"), "five days to the second")
			t.eq(w.bank:passLeft(1, "paintball"), 0)
			-- run out: it can be bought again (back in the game)
			t.deepEq({ w.bank:buyPass(1, PASS) }, { false, Bank.WORDS.gone })
			w.bank:join(1)
			t.truthy(w.bank:buyPass(1, PASS))
			t.eq(w.bank:passLeft(1, "paintball"), 5)
			-- short of money: the price and what is held, and no pass
			local poor = world(7)
			poor.bank:join(2)
			t.deepEq({ poor.bank:buyPass(2, PASS) }, { false, "You need 20c; you have 7c" })
			t.falsy(poor.bank:hasPass(2, "paintball"))
			t.eq(poor.bank:balance(2), 7)
			-- someone else's pass is not mine
			t.falsy(w.bank:hasPass(2, "paintball"))
			-- a changed price or length is what is sold
			Tunables.applyOverrides({ ["economy.paintballPassCents"] = 30, ["economy.paintballPassDays"] = 2 })
			local dear = EconomyRules.pass("paintball") :: Bank.PassSpec
			t.eq(dear.cents, 30)
			t.eq(dear.bought, "Pass bought: two days of paintball and both lounges.")
			Tunables.reset()
		end
	)

	t.test("how long a pass has left, in words: in-game days and real minutes", function()
		t.eq(EconomyRules.passLeftWords(5, DAY), "5.0 in-game days left (about 60 minutes)")
		t.eq(EconomyRules.passLeftWords(3.52, DAY), "3.5 in-game days left (about 43 minutes)")
		t.eq(EconomyRules.passLeftWords(0.5, DAY), "12 in-game hours left (about 6 minutes)")
		t.eq(EconomyRules.passLeftWords(0.01, DAY), "1 in-game hour left (about a minute)")
		t.eq(EconomyRules.passLeftWords(0, DAY), "No pass")
		t.eq(EconomyRules.passLeftWords(-1, DAY), "No pass")
		t.eq(EconomyRules.passLeftWords(0 / 0, DAY), "No pass")
	end)

	t.test("saving later: an account as plain data, a pass as time left, put back on another server's clock", function()
		local w = world(300)
		w.bank:join(1)
		w.bank:buyPass(1, PASS)
		w.bank:spend(1, 30, "a kite")
		w.t += 2 * DAY
		local saved = w.bank:export(1) :: Bank.Saved
		t.deepEq(saved, { v = 1, cents = 250, pocket = 300, passes = { paintball = 3 * DAY } })
		t.eq(w.bank:export("nobody"), nil)
		-- another server: its game clock reads something else entirely
		local later = world(300)
		later.t = 99
		t.truthy(later.bank:import(1, saved))
		t.eq(later.bank:balance(1), 250)
		t.falsy(later.bank:has(1), "put back, not yet joined")
		t.near(later.bank:passLeft(1, "paintball"), 3)
		t.deepEq(later.passed, { { 1, "paintball", 99 + 3 * DAY } })
		local _, given = later.bank:join(1)
		t.eq(given, 50, "topped up to the pocket amount, as on any join")
		t.eq(later.bank.accounts[1].pocket, 350)
		-- an expired pass is not carried
		w.t += 4 * DAY
		t.deepEq((w.bank:export(1) :: Bank.Saved).passes, {})
		-- an account already open here is newer than anything saved
		t.deepEq({ later.bank:import(1, saved) }, { false, "an account is already open here" })
		-- a record that is not sound changes nothing
		local fresh = world(0)
		for _, bad in
			{
				nil :: any,
				"cents",
				{ v = 2, cents = 1, pocket = 0, passes = {} },
				{ v = 1, cents = 1.5, pocket = 0, passes = {} },
				{ v = 1, cents = -1, pocket = 0, passes = {} },
				{ v = 1, cents = 1, pocket = 0 },
				{ v = 1, cents = 1, pocket = 0, passes = { paintball = -5 } },
				{ v = 1, cents = 1, pocket = 0, passes = { paintball = 0 / 0 } },
				{ v = 1, cents = 1, pocket = 0, passes = { 5 } },
			}
		do
			t.falsy((fresh.bank:import(9, bad)))
			t.eq(fresh.bank.accounts[9], nil)
		end
	end)
end
