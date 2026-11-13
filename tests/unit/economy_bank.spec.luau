--!strict
-- Shared/Economy/Bank: the town's money, pure. Whole cents, never negative, every change logged with its
-- reason; a spend larger than the balance, two spends racing, a player leaving mid-spend; pocket money once
-- for the server's life (leaving and coming back is never a way to more); the hand-out kept out of the queue's
-- money; a caller's mistake said kindly to the player and loudly to the server; the timed pass on the game
-- clock; what would be saved, and putting it back before or just after the join.
local Bank = require("@shared/Economy/Bank")
local EconomyRules = require("@shared/Economy/EconomyRules")
local Tunables = require("@shared/Config/Tunables")
local Rng = require("@shared/Util/Rng")

local DAY = 720

type World = { bank: Bank.Bank, t: number, wall: number, seen: { Bank.Entry }, passed: { any }, faults: { string } }

local function world(pocket: number?): World
	local w = { t = 6480, wall = 1000000, seen = {}, passed = {}, faults = {} } :: World
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
		fault = function(what: string)
			table.insert(w.faults, what)
		end,
		wall = function(): number
			return w.wall
		end,
	})
	return w
end

local PASS = EconomyRules.pass("paintball") :: Bank.PassSpec

return function(t)
	t.test(
		"pocket money: S$3.00 on first joining, once for the server's life; coming back is never a way to more",
		function()
			t.eq(EconomyRules.pocketMoney(), 300, "the one tunable: Tunables economy.pocketMoneyCents")
			local w = world(EconomyRules.pocketMoney())
			local a, given = w.bank:join(7)
			t.eq(given, 300)
			t.eq(w.bank:balance(7), 300)
			t.truthy(a.open and a.pocket == 300)
			t.deepEq(w.seen, { { id = 7, delta = 300, why = "pocket money", balance = 300, at = 6480, seq = 1 } })
			-- a second join without a leave gives nothing, even after spending
			t.truthy(w.bank:spend(7, 204, "the whole corner store"))
			local _, again = w.bank:join(7)
			t.eq(again, 0)
			t.eq(w.bank:balance(7), 96)
			-- leaving and coming back gives NOTHING more: what was spent stays spent (the review's case: one
			-- player, five joins, spending everything each time, must end having spent S$3.00 and no more)
			local spent = 204
			for _ = 1, 5 do
				w.bank:leave(7)
				local _, back = w.bank:join(7)
				t.eq(back, 0, "nothing for coming back")
				local have = w.bank:balance(7)
				if have > 0 then
					t.truthy(w.bank:spend(7, have, "everything"))
					spent += have
				end
			end
			t.eq(spent, 300)
			t.eq(w.bank:balance(7), 0, "broke until something pays: that is the price of once")
			t.eq(w.bank.accounts[7].pocket, 300, "pocket money given so far is kept (for the day it is saved)")
			-- money earned is no reason to give or withhold anything
			t.truthy(w.bank:add(7, 50, "mowing a lawn"))
			w.bank:leave(7)
			local _, rich = w.bank:join(7)
			t.eq(rich, 0)
			t.eq(w.bank:balance(7), 50)
			-- the amount was raised while the server ran: the difference is owed, once
			local raised = 300
			local b = Bank.new({
				now = function(): number
					return 0
				end,
				daySeconds = DAY,
				pocket = function(): number
					return raised
				end,
			})
			b:join(1)
			b:spend(1, 300, "everything")
			b:leave(1)
			raised = 350
			local _, more = b:join(1)
			t.eq(more, 50)
			b:leave(1)
			raised = 100
			local _, less = b:join(1)
			t.eq(less, 0, "a lowered amount takes nothing back")
			t.eq(b:balance(1), 50)
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
		end
	)

	t.test("spend: whole cents, the words to show, and a balance that is never negative", function()
		local w = world(300)
		w.bank:join("ann")
		t.deepEq({ w.bank:spend("ann", 12, "coffee") }, { true, "Paid 12c for coffee. You have S$2.88." })
		t.eq(w.bank:balance("ann"), 288)
		-- a spend larger than the balance: refused with the price and what is held; nothing changes
		t.deepEq({ w.bank:spend("ann", 289, "a kite") }, { false, "You need S$2.89; you have S$2.88." })
		t.eq(w.bank:balance("ann"), 288)
		t.eq(#w.seen, 2, "a refusal is not a change")
		-- exactly everything is allowed, and then nothing is
		t.truthy(w.bank:spend("ann", 288, "everything"))
		t.eq(w.bank:balance("ann"), 0)
		t.deepEq({ w.bank:spend("ann", 1, "bubble gum") }, { false, "You need 1c; you have 0c." })
		-- a dollar or more is written as the corner of the screen writes it, less as the shops do
		t.eq(Bank.short(240, 233), "You need S$2.40; you have S$2.33.")
		t.eq(Bank.short(12, 7), "You need 12c; you have 7c.")
		t.eq(Bank.short(100, 99), "You need S$1.00; you have 99c.")
		t.eq(Bank.amount(67), "67c")
		t.eq(Bank.amount(204), "S$2.04")
		t.eq(Bank.price(12), "12c")
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
		t.deepEq({ w.bank:can("ann", 5) }, { false, "You need 5c; you have 0c." })
		-- a dollar or more paid reads in dollars too
		w.bank:add("ann", 500, "found")
		t.deepEq({ w.bank:spend("ann", 204, "22 things") }, { true, "Paid S$2.04 for 22 things. You have S$2.96." })
	end)

	t.test(
		"a price that is not cents, or no reason: the shop's mistake, kind words for the player, loud for the server",
		function()
			local w = world(300)
			w.bank:join("ann")
			local n = #w.seen
			-- not a price: fractions, negatives, not-a-number, infinity, a string
			local bads: { any } = { 0.5, -3, 0 / 0, math.huge, "12" }
			for _, bad in bads do
				t.deepEq({ w.bank:spend("ann", bad, "x") }, { false, "That is not for sale yet." })
				t.deepEq({ w.bank:can("ann", bad) }, { false, "That is not for sale yet." })
				t.deepEq({ w.bank:add("ann", bad, "x") }, { false, "That could not be paid." })
				t.deepEq({ w.bank:take("ann", bad, "x") }, { false, "That could not be paid." })
			end
			-- nil: a row missing from the price list (the review's lane_shoes and hilltop_lunch)
			t.deepEq({ w.bank:spend("ann", nil :: any, "lane shoes") }, { false, Bank.WORDS.amount })
			t.eq(#w.faults, 4 * #bads + 1, "every one of them reached the server's log")
			t.truthy(string.find(w.faults[#w.faults], "nil", 1, true), w.faults[#w.faults])
			-- no reason: never "Paid 12c for nil."
			local before = #w.faults
			local whys: { any } = { false, "", "   ", 12, {} }
			for _, why in whys do
				t.deepEq({ w.bank:spend("ann", 12, why) }, { false, Bank.WORDS.amount })
				t.deepEq({ w.bank:add("ann", 12, why) }, { false, Bank.WORDS.pay })
			end
			t.deepEq({ w.bank:spend("ann", 12, nil :: any) }, { false, Bank.WORDS.amount })
			t.eq(#w.faults, before + 2 * #whys + 1)
			t.eq(w.bank.mistakes, #w.faults)
			-- and nothing was taken or given by any of it
			t.eq(w.bank:balance("ann"), 300)
			t.eq(#w.seen, n)
			-- the venues' prices are in the list, so none of them is such a mistake
			t.eq(EconomyRules.price("hilltop_lunch"), 10)
			t.eq(EconomyRules.price("bowling_ball"), 25)
			t.eq(EconomyRules.price("lane_shoes"), 0)
			t.eq(EconomyRules.price("coffee"), 12)
			t.eq(EconomyRules.price("nachos"), 5)
			t.eq(EconomyRules.price("hot_cocoa"), 10)
			t.eq(EconomyRules.price("soda"), 4, "a corner-store item, from Items/ItemRules")
			for _, id in { "alley_postcard", "alley_pin_toy", "alley_mug", "alley_shirt" } do
				local p = EconomyRules.price(id) :: number
				t.truthy(p >= 3 and p <= 10, `{id}: souvenirs are 3 to 10 cents`)
			end
			t.eq(EconomyRules.price("a thing nobody sells"), nil)
			-- a hook that throws on a mistake changes nothing either
			local b = Bank.new({
				now = function(): number
					return 0
				end,
				daySeconds = DAY,
				fault = function()
					error("the log is broken")
				end,
			})
			b:join(1)
			t.deepEq({ b:spend(1, 0.5, "x") }, { false, Bank.WORDS.amount })
			t.eq(b.faults, 1)
		end
	)

	t.test("pocket money is a hand-out: it is spent first and never counts toward the queue", function()
		local w = world(300)
		w.bank:join(1)
		t.eq(w.bank:counted(1), 0, "S$3.00 of pocket money buys no place in the queue")
		-- shopping with pocket money costs no rank: nothing that counted is gone
		t.truthy(w.bank:spend(1, 204, "the whole corner store"))
		t.eq(w.bank:balance(1), 96)
		t.eq(w.bank:counted(1), 0)
		-- earnings count in full, beside whatever pocket money is left
		t.truthy(w.bank:add(1, 50, "mowing a lawn"))
		t.eq(w.bank:counted(1), 50)
		-- a spend takes the hand-out first, and earnings only once it is gone
		t.truthy(w.bank:spend(1, 90, "a day out"))
		t.eq(w.bank:counted(1), 50)
		t.truthy(w.bank:spend(1, 16, "a radio and a soda")) -- 6 of pocket money, then 10 earned
		t.eq(w.bank:balance(1), 40)
		t.eq(w.bank:counted(1), 40)
		t.eq(w.bank.accounts[1].pocketLeft, 0)
		-- a purchase that could not be handed over gives the hand-out back as a hand-out
		local w2 = world(300)
		w2.bank:join(1)
		w2.bank:add(1, 100, "work")
		w2.bank:spend(1, 350, "a jet ski", function(): (boolean?, string?)
			return false
		end)
		t.eq(w2.bank:balance(1), 400)
		t.eq(w2.bank:counted(1), 100)
		-- take (a fine, the Role Lab): earnings first, the hand-out last
		t.deepEq({ w2.bank:take(1, 30, "a fine") }, { true, "-30c: a fine. You have S$3.70." })
		t.eq(w2.bank:counted(1), 70)
		t.truthy(w2.bank:take(1, 170, "a fine"))
		t.eq(w2.bank:balance(1), 200)
		t.eq(w2.bank:counted(1), 0)
		t.deepEq({ w2.bank:take(1, 201, "a fine") }, { false, "You need S$2.01; you have S$2.00." })
		t.deepEq({ w2.bank:take("nobody", 1, "a fine") }, { false, Bank.WORDS.none })
		-- what is owed is owed: a closed account can still be taken from
		w2.bank:leave(1)
		t.truthy(w2.bank:take(1, 50, "a fine"))
		t.eq(w2.bank:balance(1), 150)
		-- no account: nothing counted
		t.eq(w.bank:counted("nobody"), 0)
		-- in any order of spending, paying, taking and failed handing-over: 0 <= counted <= balance, and the
		-- hand-out left is never more than was given or than there is
		for seed = 1, 30 do
			local rng = Rng.new(seed)
			local r = world(300)
			r.bank:join(1)
			for _ = 1, 40 do
				local k = rng.int(1, 4)
				local c = rng.int(0, 120)
				if k == 1 then
					r.bank:spend(1, c, "a thing")
				elseif k == 2 then
					r.bank:add(1, c, "work")
				elseif k == 3 then
					r.bank:take(1, c, "a fine")
				else
					r.bank:spend(1, c, "a thing", function(): (boolean?, string?)
						return false
					end)
				end
				local a = r.bank.accounts[1]
				t.truthy(
					a.pocketLeft >= 0 and a.pocketLeft <= a.pocket and a.pocketLeft <= a.purse.cents,
					`seed {seed}`
				)
				t.eq(r.bank:counted(1), a.purse.cents - a.pocketLeft)
			end
		end
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
			-- (seq: each account's own count of changes, for a screen that was shown only the last of several)
			{ id = 1, delta = 300, why = "pocket money", balance = 300, at = 6480, seq = 1 },
			{ id = 2, delta = 300, why = "pocket money", balance = 300, at = 6480, seq = 1 },
			{ id = 1, delta = -12, why = "coffee", balance = 288, at = 6500, seq = 2 },
			{ id = 2, delta = 4, why = "a tip", balance = 304, at = 6500, seq = 2 },
			{ id = 1, delta = -20, why = "a paintball pass", balance = 268, at = 6500, seq = 3 },
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
		t.deepEq({ w.bank:spend(1, 7, "a football") }, { false, "You need 7c; you have 3c." })
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
		t.eq(w2.bank.accounts[1].held, 1, "one purchase in hand")
		coroutine.resume(second)
		t.deepEq(results["a frisbee"], { false, Bank.WORDS.busy })
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
		t.deepEq({ w3.bank:spend(1, 7, "a frisbee") }, { false, Bank.WORDS.busy })
		coroutine.resume(co)
		t.deepEq(out, { false, "The shelf is empty." })
		t.eq(w3.bank:balance(1), 10)
		t.truthy(w3.bank:spend(1, 7, "a frisbee"))
		t.deepEq(
			w3.bank.entries[#w3.bank.entries - 1],
			{ id = 1, delta = 7, why = "refund: a kite", balance = 10, at = 6480, seq = 3 }
		)
	end)

	t.test(
		"Pay pressed twice while the basket is still being handed over: charged once (the review's caller 1)",
		function()
			-- a corner-store till charges a basket of three (69c) and waits a frame to hand the Tools over; the
			-- player presses Pay again in that frame
			local w = world(300)
			w.bank:join(1)
			local waiting: { thread } = {}
			local owned = 0
			local said: { any } = {}
			local function pay()
				table.insert(said, {
					w.bank:spend(1, 69, "a kite, a soda and a frisbee", function(): (boolean?, string?)
						table.insert(waiting, coroutine.running())
						coroutine.yield() -- (task.wait: the Tools are being cloned)
						owned += 3
						return true
					end),
				})
			end
			local first, second = coroutine.create(pay), coroutine.create(pay)
			coroutine.resume(first)
			coroutine.resume(second) -- the second press, same frame
			t.deepEq(said[1], { false, "One moment: still serving you." }, "the second press is told to wait")
			t.eq(w.bank:balance(1), 231, "and charged nothing")
			-- the frame ends: the first is handed over
			for _, co in waiting do
				coroutine.resume(co)
			end
			t.deepEq(said[2], { true, "Paid 69c for a kite, a soda and a frisbee. You have S$2.31." })
			t.eq(owned, 3, "one basket")
			t.eq(w.bank:balance(1), 231, "paid for once")
			t.eq(w.bank.accounts[1].held, 0)
			-- once it is handed over the next purchase goes through as usual
			t.truthy(w.bank:spend(1, 12, "coffee"))
			t.eq(w.bank:balance(1), 219)
			-- a purchase in hand refuses a pass, a free thing and a plain spend alike; pay and fines still land
			local co = coroutine.create(function()
				w.bank:spend(1, 5, "nachos", function(): (boolean?, string?)
					coroutine.yield()
					return true
				end)
			end)
			coroutine.resume(co)
			t.deepEq({ w.bank:buyPass(1, PASS) }, { false, Bank.WORDS.busy })
			t.deepEq({ w.bank:spend(1, 0, "lane shoes") }, { false, Bank.WORDS.busy })
			t.truthy(w.bank:add(1, 2, "a tip"))
			t.truthy(w.bank:take(1, 1, "a parking fine"))
			t.falsy(w.bank:hasPass(1, "paintball"))
			coroutine.resume(co)
			t.eq(w.bank:balance(1), 219 - 5 + 2 - 1)
			-- another player is never kept waiting by someone else's purchase
			w.bank:join(2)
			local co2 = coroutine.create(function()
				w.bank:spend(1, 5, "nachos", function(): (boolean?, string?)
					coroutine.yield()
					return true
				end)
			end)
			coroutine.resume(co2)
			t.truthy(w.bank:spend(2, 5, "nachos"))
			coroutine.resume(co2)
			-- a handing-over that fails or throws while waiting frees the player for the next one too
			for _, ending in { "false", "error" } do
				local co3 = coroutine.create(function()
					w.bank:spend(1, 5, "nachos", function(): (boolean?, string?)
						coroutine.yield()
						if ending == "error" then
							error("the fryer caught fire")
						end
						return false
					end)
				end)
				coroutine.resume(co3)
				t.eq(w.bank.accounts[1].held, 1)
				coroutine.resume(co3)
				t.eq(w.bank.accounts[1].held, 0, ending)
				t.truthy(w.bank:can(1, 5))
			end
			t.eq(w.bank:balance(1), 210, "both refunded")
		end
	)

	t.test(
		"a handing-over must say true: nothing, an error or anything else is refunded and said in the server's log",
		function()
			local w = world(300)
			w.bank:join(1)
			-- the review's caller 5: a typo in the kitchen code
			local ok, words = w.bank:spend(1, 10, "a hilltop lunch", function(): (boolean?, string?)
				local plate: any = nil
				return plate.soup
			end)
			t.deepEq({ ok, words }, { false, "That did not work, so you were not charged for a hilltop lunch." })
			t.eq(w.bank:balance(1), 300)
			t.eq(#w.faults, 1, "the server's log hears of it")
			t.truthy(string.find(w.faults[1], "the delivery step for a hilltop lunch threw", 1, true), w.faults[1])
			t.truthy(string.find(w.faults[1], "attempt to index nil", 1, true), "with the error's own words")
			t.truthy(string.find(w.faults[1], "economy_bank.spec", 1, true), "and where it was")
			-- a give-function that returns nil on failure, or a step that forgot its `return`: refunded, and said
			local function giveKite(): boolean?
				return nil -- (the shelf was empty)
			end
			t.deepEq({
				w.bank:spend(1, 30, "a kite", function(): (boolean?, string?)
					return giveKite()
				end),
			}, { false, "That did not work, so you were not charged for a kite." })
			t.eq(w.bank:balance(1), 300, "never charged for nothing")
			t.eq(#w.faults, 2)
			t.truthy(string.find(w.faults[2], 'end it with "return true"', 1, true), w.faults[2])
			local forgot: any = function() end
			t.falsy((w.bank:spend(1, 30, "a kite", forgot)))
			t.eq(#w.faults, 3)
			local odd: any = function()
				return "yes"
			end
			t.falsy((w.bank:spend(1, 30, "a kite", odd)))
			t.truthy(string.find(w.faults[4], "returned yes, not true", 1, true), w.faults[4])
			t.eq(w.bank:balance(1), 300)
			t.eq(w.bank.mistakes, 4)
			-- false is a refusal, not a mistake: refunded, its words passed on, nothing warned
			t.deepEq({
				w.bank:spend(1, 30, "a kite", function(): (boolean?, string?)
					return false, "The shelf is empty."
				end),
			}, { false, "The shelf is empty." })
			t.eq(#w.faults, 4)
			-- and true is handed over
			t.deepEq({
				w.bank:spend(1, 30, "a kite", function(): (boolean?, string?)
					return true
				end),
			}, { true, "Paid 30c for a kite. You have S$2.70." })
			t.eq(#w.faults, 4)
		end
	)

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
		t.eq(topUp, 0, "pocket money is given once, whatever is in flight")
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
			t.eq(PASS.cents, 20)
			t.eq(EconomyRules.price("paintball_pass"), PASS.cents, "one price: the price list reads the pass")
			t.eq((EconomyRules.PRICES :: any).paintball_pass, nil, "and keeps no copy of its own")
			t.eq(PASS.offer, "A pass is 20c for five in-game days of paintball and both lounges.")
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
			t.deepEq({ poor.bank:buyPass(2, PASS) }, { false, "You need 20c; you have 7c." })
			t.falsy(poor.bank:hasPass(2, "paintball"))
			t.eq(poor.bank:balance(2), 7)
			-- someone else's pass is not mine
			t.falsy(w.bank:hasPass(2, "paintball"))
			-- a changed price or length is what is sold
			Tunables.applyOverrides({ ["economy.paintballPassCents"] = 30, ["economy.paintballPassDays"] = 2 })
			local dear = EconomyRules.pass("paintball") :: Bank.PassSpec
			t.eq(dear.cents, 30)
			t.eq(dear.bought, "Pass bought: two days of paintball and both lounges.")
			t.eq(dear.offer, "A pass is 30c for two in-game days of paintball and both lounges.")
			t.eq(EconomyRules.price("paintball_pass"), 30, "the price list follows the tunable")
			Tunables.applyOverrides({ ["economy.paintballPassCents"] = 150 })
			t.eq(
				(EconomyRules.pass("paintball") :: Bank.PassSpec).offer,
				"A pass is S$1.50 for two in-game days of paintball and both lounges."
			)
			Tunables.reset()
		end
	)

	t.test(
		"a pass in its last in-game day can be renewed: the new days go on the end, nobody is turned away",
		function()
			t.eq(Bank.RENEW_DAYS, 1)
			t.eq(PASS.renewed, "Pass renewed: five more days of paintball and both lounges.")
			local w = world(300)
			w.bank:join(1)
			t.truthy(w.bank:buyPass(1, PASS))
			local ends = 6480 + 5 * DAY
			-- with a day or more left: "You already have a pass.", and nothing taken
			w.t = ends - DAY
			t.deepEq({ w.bank:buyPass(1, PASS) }, { false, PASS.has })
			t.eq(w.bank:balance(1), 280)
			-- the review's case: ten game seconds left, in the middle of an evening
			w.t = ends - 10
			t.deepEq({ w.bank:buyPass(1, PASS) }, { true, PASS.renewed })
			t.eq(w.bank:balance(1), 260)
			t.eq(w.bank:passUntil(1, "paintball"), ends + 5 * DAY, "the ten seconds are kept")
			t.near(w.bank:passLeft(1, "paintball"), 5 + 10 / DAY)
			t.deepEq(w.passed[#w.passed], { 1, "paintball", ends + 5 * DAY }, "the screen hears the new end")
			-- and the renewed pass is a pass with five days left: not renewable again until its own last day
			t.deepEq({ w.bank:buyPass(1, PASS) }, { false, PASS.has })
			-- one that has run out is simply bought again, from now
			w.t = ends + 5 * DAY + 100
			t.deepEq({ w.bank:buyPass(1, PASS) }, { true, PASS.bought })
			t.eq(w.bank:passUntil(1, "paintball"), w.t + 5 * DAY)
			-- short of money in the last day: the pass runs on as it was
			local poor = world(25)
			poor.bank:join(2)
			t.truthy(poor.bank:buyPass(2, PASS))
			poor.t += 4.5 * DAY
			t.deepEq({ poor.bank:buyPass(2, PASS) }, { false, "You need 20c; you have 5c." })
			t.eq(poor.bank:passUntil(2, "paintball"), 6480 + 5 * DAY)
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
		t.deepEq(
			saved,
			{ v = 1, cents = 250, pocket = 300, pocketLeft = 250, passes = { paintball = 3 * DAY }, at = 1000000 }
		)
		t.eq(w.bank:export("nobody"), nil)
		-- another server at the same moment: its game clock reads something else entirely
		local later = world(300)
		later.t = 99
		t.truthy(later.bank:import(1, saved))
		t.eq(later.bank:balance(1), 250)
		t.falsy(later.bank:has(1), "put back, not yet joined")
		t.near(later.bank:passLeft(1, "paintball"), 3)
		t.deepEq(later.passed, { { 1, "paintball", 99 + 3 * DAY } })
		local _, given = later.bank:join(1)
		t.eq(given, 0, "the saved account had its pocket money already: none again on a new server")
		t.eq(later.bank.accounts[1].pocket, 300)
		t.eq(later.bank:counted(1), 0, "and what is left of it is still a hand-out")
		-- an expired pass is not carried
		w.t += 4 * DAY
		t.deepEq((w.bank:export(1) :: Bank.Saved).passes, {})
		-- a second import: the account has been put back once and is not replaced again
		t.deepEq({ later.bank:import(1, saved) }, { false, "this account has already been used here" })
		-- a pass runs down while its holder is away between servers, as it does on one: real seconds come off
		local nextDay = world(300)
		nextDay.wall = saved.at :: number + DAY
		t.truthy(nextDay.bank:import(1, saved))
		t.near(nextDay.bank:passLeft(1, "paintball"), 2)
		local nextWeek = world(300)
		nextWeek.wall = saved.at :: number + 3 * DAY
		t.truthy(nextWeek.bank:import(1, saved))
		t.falsy(nextWeek.bank:hasPass(1, "paintball"), "three days away: the three days left are gone")
		t.eq(#nextWeek.passed, 0)
		-- a record without the time of saving keeps its time left (nothing to take off)
		local undated = world(300)
		undated.wall = 5e9
		t.truthy(undated.bank:import(1, { v = 1, cents = 5, pocket = 0, pocketLeft = 0, passes = { paintball = DAY } }))
		t.near(undated.bank:passLeft(1, "paintball"), 1)
		-- a record that is not sound changes nothing
		local fresh = world(0)
		for _, bad in
			{
				nil :: any,
				"cents",
				{ v = 2, cents = 1, pocket = 0, pocketLeft = 0, passes = {} },
				{ v = 1, cents = 1.5, pocket = 0, pocketLeft = 0, passes = {} },
				{ v = 1, cents = -1, pocket = 0, pocketLeft = 0, passes = {} },
				{ v = 1, cents = 1, pocket = 0, passes = {} },
				{ v = 1, cents = 1, pocket = 0, pocketLeft = 0 },
				{ v = 1, cents = 1, pocket = 0, pocketLeft = 0, passes = { paintball = -5 } },
				{ v = 1, cents = 1, pocket = 0, pocketLeft = 0, passes = { paintball = 0 / 0 } },
				{ v = 1, cents = 1, pocket = 0, pocketLeft = 0, passes = { 5 } },
				{ v = 1, cents = 1, pocket = 0, pocketLeft = 0, passes = {}, at = "noon" },
			}
		do
			t.falsy((fresh.bank:import(9, bad)))
			t.eq(fresh.bank.accounts[9], nil)
		end
	end)

	t.test(
		"saving later, as the game joins: the account is opened BEFORE a profile can load, and import still works",
		function()
			-- the review's case: 980c and a pass saved; on a new server the player arrives (pocket money at once,
			-- as RoleService asks for the purse at PlayerAdded) and the profile load comes a moment later
			local saved: Bank.Saved =
				{ v = 1, cents = 980, pocket = 300, pocketLeft = 0, passes = { paintball = 2 * DAY } }
			local w = world(300)
			local _, given = w.bank:join(1)
			t.eq(given, 300)
			t.deepEq({ w.bank:import(1, saved) }, { true, nil })
			t.eq(w.bank:balance(1), 980, "the saved balance, not this server's pocket money")
			t.truthy(w.bank:hasPass(1, "paintball"))
			t.near(w.bank:passLeft(1, "paintball"), 2)
			t.eq(w.bank.accounts[1].pocket, 300, "they had their pocket money in an earlier life: not again")
			t.eq(w.bank:counted(1), 980)
			t.truthy(w.bank:has(1), "still in the game")
			-- every step of it is in the log, with a reason
			local whys = {}
			for _, e in w.seen do
				table.insert(whys, `{e.delta} {e.why}`)
			end
			t.deepEq(whys, { "300 pocket money", "680 your saved wallet" })
			-- a saved account that never had pocket money (or less than today's) is owed the rest, once
			local old = world(300)
			old.bank:join(1)
			t.truthy(old.bank:import(1, { v = 1, cents = 40, pocket = 100, pocketLeft = 0, passes = {} }))
			t.eq(old.bank:balance(1), 240, "40 saved, and the 200 of pocket money they never had")
			t.eq(old.bank.accounts[1].pocket, 300)
			t.eq(old.bank:counted(1), 40)
			-- once anything has happened to the account here, it is the newer one: the saved one is refused
			for _, touch in
				{
					function(b: Bank.Bank)
						b:spend(1, 12, "coffee")
					end,
					function(b: Bank.Bank)
						b:add(1, 1, "a tip")
					end,
					function(b: Bank.Bank)
						b:buyPass(1, PASS)
					end,
					function(b: Bank.Bank)
						b:take(1, 1, "a fine")
					end,
				}
			do
				local used = world(300)
				used.bank:join(1)
				touch(used.bank)
				local before = used.bank:balance(1)
				t.deepEq({ used.bank:import(1, saved) }, { false, "this account has already been used here" })
				t.eq(used.bank:balance(1), before)
			end
			-- a free thing (lane shoes at 0c) changes nothing, so the account is still as good as new
			local shoes = world(300)
			shoes.bank:join(1)
			shoes.bank:spend(1, 0, "lane shoes")
			t.truthy(shoes.bank:import(1, saved))
			-- an unsound record leaves the joined account exactly as it was
			local sound = world(300)
			sound.bank:join(1)
			t.falsy((sound.bank:import(1, { v = 1, cents = -5, pocket = 0, pocketLeft = 0, passes = {} })))
			t.eq(sound.bank:balance(1), 300)
			t.truthy(sound.bank.accounts[1].fresh)
		end
	)
end
