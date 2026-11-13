--!strict
-- tests/isolated/wallet.luau: cases for tests/unit/wallet.spec.luau, run in their own Lune process
-- (tests/lib/Isolated) because they install fake engine globals (tests/lib/FakeEngine).
-- The town's wallet as the game runs it: the real Server/Economy/Credits on engine Players (the attributes a
-- client reads change the moment the money does), the game's own wiring of it (Boot/Game.wallet: the day
-- clock, the notice toast, the join sweep, leaving, the minigames' charge and pass), the real
-- Roles/RoleService holding the wallet's purse, the real MinigameService with the wallet behind
-- ctx.town.charge and ctx.town.pass (on tests/lib/MinigameRig, with the real fortune teller and the spec-only
-- games), and the real Client/UI/WalletHud drawing what the server wrote, fed the way a client is fed
-- (FakeEngine.deferAttributes: one signal per attribute per frame, carrying the last value).
-- Interface: return function(t) (the spec shape)
-- (FakeGames first: it registers its games, and the wire's verb list is read from the registry when
-- Shared/Net/Schemas loads)
local FakeGames = require("@tests/lib/FakeGames")
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local Bank = require("@shared/Economy/Bank")
local Tunables = require("@shared/Config/Tunables")
local DayClock = require("@server/Boot/DayClock")
local Game = require("@server/Boot/Game")
local Credits = require("@server/Economy/Credits")
local RoleLab = require("@server/Roles/RoleLab")
local RoleService = require("@server/Roles/RoleService")
local PlayMenu = require("@client/UI/PlayMenu")
local WalletHud = require("@client/UI/WalletHud")
local FakeEngine = require("@tests/lib/FakeEngine")
local Rig = require("@tests/lib/MinigameRig")
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local SITE, PLACE, S = FakeGames.SITE, FakeGames.PLACE, FakeGames.STATIONS
local DAY = 720
local F = AlleyLayout.FORTUNE
local CABINET = "fortune_1"
local AT_CABINET = { site = "bowling_alley", x = F.x - 1.6, y = 3, d = F.d - 1.6 }

type Town = { wallet: Credits.Wallet, t: number, lines: { string }, warned: { string } }

-- a wallet on a game clock the case moves by hand (it opens on day 9, as the game does)
local function town(): Town
	local w = { t = 9 * DAY, lines = {}, warned = {} } :: Town
	w.wallet = Credits.new({
		gameSeconds = function(): number
			return w.t
		end,
		daySeconds = DAY,
		log = function(line: string)
			table.insert(w.lines, line)
		end,
		warn = function(line: string)
			table.insert(w.warned, line)
		end,
	})
	return w
end

local function person(name: string, userId: number): any
	local p = FakeEngine.new("Player", name)
	rawset(p, "UserId", userId)
	return p
end

-- every value an attribute takes, as a server-side listener would see them (with the note beside it)
local function watch(player: any, name: string): { any }
	local seen: { any } = {}
	player:GetAttributeChangedSignal(name):Connect(function()
		table.insert(seen, { player:GetAttribute(name), player:GetAttribute("CentsNote") })
	end)
	return seen
end

return function(t)
	t.test("joining: an account, S$3.00 of pocket money, and the balance on the Player for the screen", function()
		FakeEngine.with(function()
			local w = town()
			local ann = person("Ann", 11)
			t.eq(w.wallet.balance(ann), 0)
			t.deepEq({ w.wallet.spend(ann, 1, "bubble gum") }, { false, Bank.WORDS.none })
			t.eq(w.wallet.join(ann), 300)
			t.eq(w.wallet.balance(ann), 300)
			t.eq(ann:GetAttribute("Cents"), 300)
			t.eq(ann:GetAttribute("PocketMoney"), 300)
			t.eq(ann:GetAttribute("CentsNote"), "1|300|pocket money")
			t.eq(ann:GetAttribute("PassUntil"), nil)
			t.deepEq(w.lines, { "11 +300c (pocket money) -> 300c" })
			-- joined twice (RoleService and the once-a-second sweep both ask): nothing more
			t.eq(w.wallet.join(ann), 0)
			t.eq(w.wallet.balance(ann), 300)
			t.eq(ann:GetAttribute("PocketMoney"), 300, "still what this join gave")
			t.eq(#w.lines, 1)
			-- the amount is the tunable, read at each join; 0 switches pocket money off
			Tunables.applyOverrides({ ["economy.pocketMoneyCents"] = 0 })
			local bob = person("Bob", 12)
			t.eq(w.wallet.join(bob), 0)
			t.eq(bob:GetAttribute("Cents"), 0, "an empty wallet still shows")
			t.eq(bob:GetAttribute("PocketMoney"), nil)
			t.eq(bob:GetAttribute("CentsNote"), "0|0|", "no change yet: the count, and nothing to say")
			Tunables.reset()
		end)
	end)

	t.test("spend and add: ok and words, and the Player's balance changes the moment the money does", function()
		FakeEngine.with(function()
			local w = town()
			local ann = person("Ann", 11)
			w.wallet.join(ann)
			local seen = watch(ann, "Cents")
			t.deepEq({ w.wallet.can(ann, 12) }, { true, "" })
			t.deepEq({ w.wallet.spend(ann, 12, "coffee") }, { true, "Paid 12c for coffee. You have S$2.88." })
			t.deepEq(seen, { { 288, "2|-12|coffee" } }, "the new balance, with the change already beside it")
			t.deepEq({ w.wallet.add(ann, 5, "mowing a lawn") }, { true, "+5c: mowing a lawn. You have S$2.93." })
			t.deepEq(seen[2], { 293, "3|5|mowing a lawn" })
			-- refused: words (in the screen's own form, with a full stop), and nothing on the Player moves
			t.deepEq({ w.wallet.spend(ann, 294, "a jet ski") }, { false, "You need S$2.94; you have S$2.93." })
			t.deepEq({ w.wallet.can(ann, 294) }, { false, "You need S$2.94; you have S$2.93." })
			t.eq(#seen, 2)
			t.eq(ann:GetAttribute("Cents"), 293)
			-- a handing-over that fails is never charged: taken, then straight back, both logged
			t.deepEq({
				w.wallet.spend(ann, 30, "a kite", function(): (boolean?, string?)
					return false, "The shelf is empty."
				end),
			}, { false, "The shelf is empty." })
			t.deepEq(seen[3], { 263, "4|-30|a kite" })
			t.deepEq(seen[4], { 293, "5|30|refund: a kite" })
			-- one that throws is not charged either, and the wallet goes on working
			local ok, words = w.wallet.spend(ann, 30, "a kite", function(): (boolean?, string?)
				error("the kite service fell over")
			end)
			t.deepEq({ ok, words }, { false, "That did not work, so you were not charged for a kite." })
			t.eq(w.wallet.balance(ann), 293)
			-- every change is in the log with its reason, in order
			local log = w.wallet.log()
			local whys = {}
			for _, e in log do
				table.insert(whys, `{e.delta} {e.why}`)
			end
			t.deepEq(whys, {
				"300 pocket money",
				"-12 coffee",
				"5 mowing a lawn",
				"-30 a kite",
				"30 refund: a kite",
				"-30 a kite",
				"30 refund: a kite",
			})
			t.eq(#w.lines, #log, "and each is a line in the server's output")
			t.eq(w.lines[2], "11 -12c (coffee) -> 288c")
			-- two people: one never pays for the other
			local bob = person("Bob", 12)
			w.wallet.join(bob)
			t.truthy(w.wallet.spend(bob, 300, "everything"))
			t.eq(w.wallet.balance(ann), 293)
			t.eq(bob:GetAttribute("Cents"), 0)
			t.eq(#w.warned, 0, "nothing in all that was a shop's mistake")
		end)
	end)

	t.test("a shop's mistake (no price, no reason): the player reads plain words and the server is warned", function()
		local w = town()
		local ann: any = { UserId = 7, Name = "Ann", events = {} }
		w.wallet.join(ann)
		-- the review's two callers: a venue looked up a price that is not in the list and got nil
		local price: any = nil
		t.deepEq({ w.wallet.spend(ann, price, "lane shoes") }, { false, "That is not for sale yet." })
		t.eq(#w.warned, 1)
		t.truthy(string.find(w.warned[1], "nil", 1, true), w.warned[1])
		t.truthy(string.find(w.warned[1], "nothing was taken", 1, true), w.warned[1])
		t.truthy(string.find(w.warned[1], "wallet", 1, true), "the warning says where it was called from")
		-- a reason left off: never "Paid 12c for nil."
		local why: any = nil
		t.deepEq({ w.wallet.spend(ann, 12, why) }, { false, "That is not for sale yet." })
		t.deepEq({ w.wallet.add(ann, 5, why) }, { false, "That could not be paid." })
		t.eq(#w.warned, 3)
		t.eq(w.wallet.balance(ann), 300, "and nothing was taken")
		t.eq(ann.attrs.Cents, 300)
		-- through the minigames' charge it is the same (ctx.town is `any` to a game: the type check cannot help)
		local hooks = Game.wallet({
			clock = { GetAttribute = function() end },
			published = { epoch = 0, base = 0, rate = 1 },
			serverTime = function(): number
				return 0
			end,
			fire = function() end,
			players = function(): { any }
				return {}
			end,
			log = function() end,
			warn = function(line: string)
				table.insert(w.warned, line)
			end,
		})
		hooks.wallet.join(ann)
		t.deepEq({ hooks.charge(ann, price, why) }, { false, "That is not for sale yet." })
		t.eq(#w.warned, 4)
	end)

	t.test("the pass: sold once for 20c, five in-game days on the game clock, in the paintball desk's shape", function()
		FakeEngine.with(function()
			local w = town()
			local ann = person("Ann", 11)
			w.wallet.join(ann)
			local desk = w.wallet.pass
			t.falsy(desk.has(ann))
			t.eq(desk.left(ann), 0)
			t.eq(desk.untilDay(ann), nil)
			t.eq(desk.words(ann), "No pass")
			-- what a door says is the wallet's own sentence, from the numbers buy() charges by
			t.deepEq({ desk.offer() }, { 20, 5, "A pass is 20c for five in-game days of paintball and both lounges." })
			t.deepEq({ desk.buy(ann) }, { true, "Pass bought: five days of paintball and both lounges." })
			t.truthy(desk.has(ann))
			t.eq(w.wallet.balance(ann), 280)
			t.eq(ann:GetAttribute("Cents"), 280)
			t.eq(ann:GetAttribute("CentsNote"), "2|-20|a paintball pass")
			t.eq(ann:GetAttribute("PassUntil"), 14 * DAY, "the game second it runs out, for the screen")
			t.eq(desk.untilDay(ann), 14)
			t.eq(desk.words(ann), "5.0 in-game days left (about 60 minutes)")
			t.deepEq({ desk.buy(ann) }, { false, "You already have a pass." })
			t.eq(w.wallet.balance(ann), 280)
			-- the lounge door an hour later: nothing left
			w.t += 4.5 * DAY
			t.near(desk.left(ann), 0.5)
			t.eq(desk.words(ann), "12 in-game hours left (about 6 minutes)")
			w.t += 0.5 * DAY
			t.falsy(desk.has(ann))
			t.eq(desk.words(ann), "No pass")
			-- the price is changed: the charge, the door's sentence and the price list all follow
			Tunables.applyOverrides({ ["economy.paintballPassCents"] = 35, ["economy.paintballPassDays"] = 3 })
			t.deepEq({ desk.offer() }, { 35, 3, "A pass is 35c for three in-game days of paintball and both lounges." })
			t.truthy(desk.buy(ann), "run out: it can be bought again")
			t.eq(w.wallet.balance(ann), 245)
			t.eq(ann:GetAttribute("PassUntil"), 17 * DAY)
			Tunables.reset()
			-- short of money: the words, and no pass
			local bob = person("Bob", 12)
			Tunables.applyOverrides({ ["economy.pocketMoneyCents"] = 7 })
			w.wallet.join(bob)
			Tunables.reset()
			t.deepEq({ desk.buy(bob) }, { false, "You need 20c; you have 7c." })
			t.falsy(desk.has(bob))
			t.eq(bob:GetAttribute("PassUntil"), nil)
			-- someone who never joined
			t.deepEq({ desk.buy(person("Cat", 13)) }, { false, Bank.WORDS.none })
		end)
	end)

	t.test("leaving and coming back: the account is kept as it was left, and nothing more is given", function()
		FakeEngine.with(function()
			local w = town()
			local ann = person("Ann", 11)
			w.wallet.join(ann)
			w.wallet.pass.buy(ann)
			w.wallet.spend(ann, 80, "a day out")
			t.eq(w.wallet.balance(ann), 200)
			-- mid-purchase when they left: the handing-over fails, the money is back in the kept account
			local out: { any } = {}
			local co = coroutine.create(function()
				out = {
					w.wallet.spend(ann, 50, "a jet ski", function(): (boolean?, string?)
						coroutine.yield()
						return false
					end),
				}
			end)
			coroutine.resume(co)
			t.eq(ann:GetAttribute("Cents"), 150)
			w.wallet.leave(ann)
			coroutine.resume(co)
			t.falsy(out[1])
			t.eq(w.wallet.balance(ann), 200, "refunded")
			t.eq(ann:GetAttribute("Cents"), 150, "nothing is written to a Player who has gone")
			t.deepEq({ w.wallet.spend(ann, 1, "bubble gum") }, { false, Bank.WORDS.gone })
			-- back: the same UserId, a new Player object. The balance as it was left (NOT topped up: the review's
			-- "spend, leave, rejoin" must not refill), the pass still running, and no pocket money line to show
			w.t += DAY
			local again = person("Ann", 11)
			t.eq(w.wallet.join(again), 0)
			t.eq(again:GetAttribute("Cents"), 200)
			t.eq(
				again:GetAttribute("PocketMoney"),
				nil,
				"nothing was given, so the screen says nothing of pocket money"
			)
			t.eq(again:GetAttribute("CentsNote"), "5|0|", "where the count stands, and no change to announce")
			t.eq(again:GetAttribute("PassUntil"), 14 * DAY)
			t.truthy(w.wallet.pass.has(again))
			t.near(w.wallet.pass.left(again), 4)
			-- five more times, spending everything each time: S$3.00 was all there ever was
			local spent = 100
			local now = again
			for i = 1, 5 do
				local have = w.wallet.balance(now)
				if have > 0 then
					t.truthy(w.wallet.spend(now, have, "everything"))
					spent += have
				end
				w.wallet.leave(now)
				now = person("Ann", 11)
				t.eq(w.wallet.join(now), 0, `join {i + 2}`)
				t.eq(now:GetAttribute("Cents"), 0)
				t.eq(now:GetAttribute("PocketMoney"), nil)
			end
			t.eq(spent, 300)
			-- back with a run-out pass: none on the screen
			w.wallet.leave(now)
			w.t += 5 * DAY
			local last = person("Ann", 11)
			w.wallet.join(last)
			t.eq(last:GetAttribute("PassUntil"), nil)
			-- what a profile would keep, as plain data
			w.wallet.add(last, 12, "work")
			local saved = w.wallet.export(last)
			t.eq(type(saved.at), "number", "stamped with the real time, so a pass can be run down on loading")
			saved.at = nil
			t.deepEq(saved, { v = 1, cents = 12, pocket = 300, pocketLeft = 0, passes = {} })
			t.eq(w.wallet.export(person("Nobody", 99)), nil)
		end)
	end)

	t.test(
		"saving later: the join comes first in the game, and wallet.import still puts a saved account back",
		function()
			FakeEngine.with(function()
				-- an account with 980c and a pass, saved on one server
				local saved = { v = 1, cents = 980, pocket = 300, pocketLeft = 0, passes = { paintball = 2 * DAY } }
				-- a new server does what the game does: the player arrives (Roles asks for the purse at
				-- PlayerAdded: join, pocket money), and the profile's load comes a moment later
				local w = town()
				local ann = person("Ann", 11)
				t.eq(w.wallet.join(ann), 300)
				t.deepEq({ w.wallet.import(ann, saved) }, { true, nil })
				t.eq(w.wallet.balance(ann), 980)
				t.eq(ann:GetAttribute("Cents"), 980, "and the screen follows")
				t.eq(ann:GetAttribute("CentsNote"), "2|680|your saved wallet")
				t.truthy(w.wallet.pass.has(ann))
				t.eq(ann:GetAttribute("PassUntil"), 11 * DAY)
				-- once they have bought something here, the account here is the newer one
				local bob = person("Bob", 12)
				w.wallet.join(bob)
				w.wallet.spend(bob, 12, "coffee")
				t.deepEq({ w.wallet.import(bob, saved) }, { false, "this account has already been used here" })
				t.eq(w.wallet.balance(bob), 288)
			end)
		end
	)

	t.test("PlayerLike stubs (the engine smoke's players) get the same wallet, on their attrs", function()
		local w = town()
		local stub: any = { UserId = 4242, Name = "Smoke" }
		t.eq(w.wallet.join(stub), 300)
		t.eq(stub.attrs.Cents, 300)
		t.truthy(w.wallet.spend(stub, 12, "coffee"))
		t.eq(stub.attrs.Cents, 288)
		t.eq(stub.attrs.CentsNote, "2|-12|coffee")
		t.truthy(w.wallet.pass.buy(stub))
		t.eq(stub.attrs.PassUntil, 14 * DAY)
	end)

	t.test("tell: a shop's words reach the one player's screen, as the header's example writes it", function()
		-- the game's wallet: Boot/Game hands in its "notice" toast
		local told: { any } = {}
		local wallet = Credits.new({
			daySeconds = DAY,
			log = function() end,
			tell = function(player: any, words: string)
				table.insert(told, { player.Name, words })
			end,
		})
		local ann: any = { UserId = 7, Name = "Ann" }
		wallet.join(ann)
		-- the header's coffee counter, word for word
		local function counter(player: any, cents: number)
			local ok, words = wallet.spend(player, cents, "coffee")
			if not ok then
				wallet.tell(player, words)
				return
			end
			wallet.tell(player, words)
		end
		counter(ann, 12)
		counter(ann, 500)
		wallet.tell(ann, "") -- nothing to say: nothing sent
		t.deepEq(told, {
			{ "Ann", "Paid 12c for coffee. You have S$2.88." },
			{ "Ann", "You need S$5.00; you have S$2.88." },
		})
		-- the header's door: the sentence is the wallet's, never the door's own copy of the price
		local function door(player: any): boolean
			if wallet.pass.has(player) then
				return true
			end
			local _cents, _days, offer = wallet.pass.offer()
			wallet.tell(player, "Members only. " .. offer)
			return false
		end
		t.falsy(door(ann))
		t.eq(told[3][2], "Members only. A pass is 20c for five in-game days of paintball and both lounges.")
		t.deepEq({ wallet.pass.buy(ann) }, { true, "Pass bought: five days of paintball and both lounges." })
		t.truthy(door(ann))
		t.eq(#told, 3)
		-- with nothing handed in, a PlayerLike stub (the engine smoke's player) finds the line among its events
		local w = town()
		local stub: any = { UserId = 4243, Name = "Smoke", events = {} }
		w.wallet.join(stub)
		w.wallet.tell(stub, "The till is closed.")
		t.deepEq(stub.events, { { kind = "notice", text = "The till is closed." } })
		w.wallet.tell({ UserId = 1 }, "nobody to tell: harmless")
	end)

	t.test(
		"the game's own wiring (Boot/Game.wallet): the day clock, the notice toast, the join sweep, leaving, charge and pass",
		function()
			FakeEngine.with(function()
				-- what Game.start hands it: where DayClock published, the shared clock, its fire, the Players list
				local rs = (game :: any):GetService("ReplicatedStorage")
				local serverTime = 5000
				local published = DayClock.publish(rs, serverTime)
				local fired: { any } = {}
				local inGame: { any } = {}
				local lines: { string } = {}
				local hooks = Game.wallet({
					clock = rs,
					published = published,
					serverTime = function(): number
						return serverTime
					end,
					fire = function(player: any, payload: { [string]: any })
						table.insert(fired, { player.Name, payload })
					end,
					players = function(): { any }
						return inGame
					end,
					log = function(line: string)
						table.insert(lines, line)
					end,
				})
				local wallet = hooks.wallet
				-- PlayerAdded: RoleService asks for the purse. The hook opens the account (pocket money) and
				-- hands over the wallet's face
				local ann = person("Ann", 11)
				table.insert(inGame, ann)
				local purse = hooks.purse(ann)
				t.eq(purse.cents, 300)
				t.eq(ann:GetAttribute("Cents"), 300)
				t.eq(ann:GetAttribute("PocketMoney"), 300)
				-- the once-a-second sweep: a join that was missed is caught; nobody already here gets anything
				local bob = person("Bob", 12)
				table.insert(inGame, bob)
				hooks.sweep()
				t.eq(bob:GetAttribute("Cents"), 300)
				t.eq(wallet.balance(ann), 300)
				local n = #lines
				for _ = 1, 5 do
					hooks.sweep()
				end
				t.eq(#lines, n, "sweeping again changes nothing")
				t.eq(wallet.balance(bob), 300)
				-- wallet.tell is the game's "notice" toast, to that one player
				wallet.tell(ann, "The till is closed.")
				t.deepEq(fired, { { "Ann", { kind = "notice", text = "The till is closed." } } })
				-- the minigames' charge IS wallet.spend: the same money, the same words
				t.deepEq({ hooks.charge(ann, 12, "coffee") }, { true, "Paid 12c for coffee. You have S$2.88." })
				t.eq(wallet.balance(ann), 288)
				t.deepEq({ hooks.charge(ann, 1000, "a game") }, { false, "You need S$10.00; you have S$2.88." })
				-- nobody gets an account by being charged: a computer player, a stand-in, someone who never
				-- came through the door
				local computer = { ai = true, name = "Wall" }
				t.deepEq({ hooks.charge(computer, 5, "a token") }, { false, Bank.WORDS.none })
				local cat = person("Cat", 13)
				t.deepEq({ hooks.charge(cat, 5, "a token") }, { false, Bank.WORDS.none })
				t.falsy(wallet.bank:has(13))
				t.falsy(wallet.bank:has(computer))
				t.eq(cat:GetAttribute("Cents"), nil)
				-- the minigames' pass IS wallet.pass, sold on the published day clock
				t.truthy(hooks.pass == wallet.pass)
				t.truthy(hooks.pass.buy(ann))
				t.eq(ann:GetAttribute("PassUntil"), published.base + 5 * DAY)
				t.near(wallet.pass.left(ann), 5)
				serverTime += 4.5 * DAY
				t.near(wallet.pass.left(ann), 0.5) -- (the pass runs on the clock both sides share)
				-- a clock that is re-anchored is followed (the attributes are read each time)
				rs:SetAttribute("ClockBase", published.base + 0.25 * DAY)
				t.near(wallet.pass.left(ann), 0.25)
				rs:SetAttribute("ClockRate", 2) -- (twice as fast since the epoch: day 9 of the pass's 5)
				t.eq(wallet.pass.left(ann), 0)
				t.falsy(wallet.pass.has(ann))
				-- an attribute that is gone: what DayClock.publish answered is used
				rs:SetAttribute("ClockBase", nil)
				rs:SetAttribute("ClockRate", nil)
				t.near(wallet.pass.left(ann), 0.5)
				-- PlayerRemoving: closed and kept
				hooks.leave(ann)
				table.remove(inGame, 1)
				t.deepEq({ hooks.charge(ann, 1, "bubble gum") }, { false, Bank.WORDS.gone })
				hooks.sweep()
				t.falsy(wallet.bank:has(11), "the sweep joins only who is in the game")
				-- back on a new Player object: the same account, nothing more given
				local again = person("Ann", 11)
				table.insert(inGame, again)
				t.eq(hooks.purse(again).cents, 268)
				t.eq(again:GetAttribute("Cents"), 268)
				t.eq(again:GetAttribute("PocketMoney"), nil)
				-- and Game.start plugs in exactly these hooks (it cannot run here: read that it does)
				local src = fs.readFile("src/server/Boot/Game.luau")
				for _, line in
					{
						"local money = Game.wallet({",
						"purse = money.purse,",
						"money.sweep()",
						"money.leave(player)",
						"charge = money.charge,",
						"pass = money.pass,",
						"wallet = wallet,",
						"fireLater = fire",
					}
				do
					t.truthy(string.find(src, line, 1, true), `Game.start no longer has: {line}`)
				end
			end)
		end
	)

	t.test(
		"roles: a member's purse is a face on the wallet, so Ladder pay, the queue's money term and the screen agree",
		function()
			FakeEngine.with(function()
				local w = town()
				local possession = {
					by = {} :: { [number]: any },
					possess = function(self: any, p: any, a: any): boolean
						self.by[p.UserId] = a
						return true
					end,
					release = function(self: any, p: any)
						self.by[p.UserId] = nil
					end,
					swap = function(self: any, p: any, a: any): boolean
						self.by[p.UserId] = a
						return true
					end,
					actorOf = function(self: any, p: any): any
						return self.by[p.UserId]
					end,
				}
				local kicked: { any } = {}
				local roles = RoleService.new({
					possession = possession,
					pickBody = function(_p: any, rung: string?): any
						return { id = rung or "human" }
					end,
					maxPlayers = 2,
					kick = function(p: any)
						table.insert(kicked, p)
					end,
					-- Boot/Game's hook (Game.wallet's purse): join, then the wallet's face
					purse = function(player: any): any
						w.wallet.join(player)
						return w.wallet.purse(player)
					end,
				})
				local ann, bob, cat = person("Ann", 1), person("Bob", 2), person("Cat", 3)
				t.eq(roles:onJoin(ann), "possessed")
				t.eq(ann:GetAttribute("Cents"), 300, "pocket money came with the purse")
				local purse = roles:member(1).purse
				t.eq(purse.cents, 300, "the face reads the wallet")
				t.eq(#purse.history, 1)
				-- pocket money is a hand-out: it buys no place in the queue
				t.eq(purse.counted, 0)
				t.eq(roles:stats(ann).cents, 0)
				-- the face cannot be written: the review's `purse.cents = 999999` is an error, not a balance
				local wrote = pcall(function()
					(purse :: any).cents = 999999
				end)
				t.falsy(wrote)
				t.eq(w.wallet.balance(ann), 300)
				t.eq(ann:GetAttribute("Cents"), 300)
				roles:onJoin(bob)
				-- the server is full: the third is turned away before anything is touched, wallet included
				t.eq(roles:onJoin(cat), "kicked")
				t.eq(#kicked, 1)
				t.falsy(w.wallet.bank:has(3))
				t.eq(cat:GetAttribute("Cents"), nil)
				-- Ladder pay lands in the wallet under plain words (never "work.completed"), and on the screen
				roles:report({ kind = "work.completed", player = 1, class = "standard", pay = 6 })
				t.eq(w.wallet.balance(ann), 306)
				t.eq(ann:GetAttribute("Cents"), 306)
				t.eq(ann:GetAttribute("CentsNote"), "2|6|work")
				t.eq(w.wallet.log()[#w.wallet.log()].why, "work")
				t.eq(WalletHud.changeText(6, "work"), "+6c  work", "what the first wage reads on screen")
				t.eq(roles:stats(ann).cents, 6, "earnings count")
				-- shopping with pocket money costs no rank: the queue counts what it counted before
				t.truthy(w.wallet.spend(ann, 204, "the corner store"))
				t.eq(roles:stats(ann).cents, 6)
				roles:queue("human")
				t.eq(roles:member(1).stats.cents, 6)
				t.eq(roles:member(2).stats.cents, 0, "someone who spent nothing is not ahead for it")
				-- the Role Lab's "cents" is the money the queue counts, and goes through the wallet too
				local lab = RoleLab.new(roles, {
					isDev = function(): boolean
						return true
					end,
				})
				t.truthy((lab:command(ann, "stat", { "cents", 500 })))
				t.eq(roles:stats(ann).cents, 500)
				t.eq(w.wallet.balance(ann), 596, "500 that count, and the 96c of pocket money still unspent")
				t.eq(ann:GetAttribute("Cents"), 596)
				t.eq(ann:GetAttribute("CentsNote"), "4|494|role lab")
				t.truthy((lab:command(ann, "stat", { "cents", 20 })))
				t.eq(roles:stats(ann).cents, 20)
				t.eq(w.wallet.balance(ann), 116)
				t.falsy((lab:command(ann, "stat", { "cents", 2.5 })))
				t.eq(w.wallet.balance(ann), 116)
				t.eq(roles:stats(ann).cents, 20)
				-- leaving and coming back: the Ladder's member is new, the money is not, and nothing is added
				roles:onLeave(ann)
				w.wallet.leave(ann)
				t.eq(roles:onJoin(person("Ann", 1)), "possessed")
				t.eq(roles:stats({ UserId = 1 }).cents, 20)
				t.eq(w.wallet.balance({ UserId = 1 }), 116)
				-- asking for a purse opens nothing and gives nothing (the review's case: spend to 0c, leave, then
				-- wallet.purse(p) must not reopen the account, refill it, or let the absent player spend)
				t.truthy(w.wallet.spend(bob, 300, "everything"))
				roles:onLeave(bob)
				w.wallet.leave(bob)
				local ghost = w.wallet.purse(bob)
				t.eq(ghost.cents, 0)
				t.falsy(w.wallet.bank:has(2), "still closed")
				t.deepEq({ w.wallet.spend(bob, 10, "ghost") }, { false, Bank.WORDS.gone })
				local stranger = w.wallet.purse(person("Zed", 77))
				t.eq(stranger.cents, 0)
				t.eq(w.wallet.bank.accounts[77], nil, "no account was made by asking")
				t.deepEq({ stranger:credit(5, "a tip") }, { false, Bank.WORDS.none })
				-- pay still owed to someone who left lands in the kept account, logged
				t.truthy(ghost:credit(4, "work"))
				t.eq(w.wallet.balance(bob), 4)
				t.eq(w.wallet.log()[#w.wallet.log()].why, "work")
				-- a debit through the face is logged and never goes below nothing
				t.deepEq({ ghost:debit(5, "a fine") }, { false, "You need 5c; you have 4c." })
				t.truthy(ghost:debit(4, "a fine"))
				t.eq(w.wallet.balance(bob), 0)
				-- without a wallet (a bare test's RoleService) a member still has a purse of its own, at nothing
				local bare = RoleService.new({
					possession = possession,
					pickBody = function(): any
						return { id = "human" }
					end,
				})
				bare:onJoin(person("Dee", 4))
				t.eq(bare:member(4).purse.cents, 0)
				bare:report({ kind = "work.completed", player = 4, class = "standard", pay = 6 })
				t.eq(bare:stats({ UserId = 4 }).cents, 6, "and its balance is what the queue counts")
			end)
		end
	)

	t.test(
		"minigames: ctx.town.charge and ctx.town.pass are the wallet, and a game played with it behind is as it was",
		function()
			-- the rig's own wiring, which is the game's: its charge is the wallet's spend and its pass the wallet's
			Rig.play(function(r)
				local town1 = FakeGames.tables[S.match].ctx.town
				t.truthy(town1.charge == FakeGames.tables[S.coin].ctx.town.charge, "one town for every Table")
				t.eq(r.wallet.balance(r.player), 300)
				t.deepEq({ town1.charge(r.player, 20, "a token") }, { true, "Paid 20c for a token. You have S$2.80." })
				t.eq(r.player:GetAttribute("Cents"), 280)
				t.deepEq({ town1.charge(r.player, 500, "the arena") }, { false, "You need S$5.00; you have S$2.80." })
				-- as in the game, nobody gets an account by being charged: a stand-in and a computer are refused,
				-- and are left with nothing (the old rig joined them and handed them pocket money)
				local bob = Rig.stub("Bob")
				t.deepEq({ town1.charge(bob, 5, "a token") }, { false, Bank.WORDS.none })
				t.eq(r.wallet.balance(bob), 0)
				t.eq(r.wallet.bank.accounts[bob.UserId], nil)
				t.deepEq({ town1.charge({ ai = true, name = "Wall" }, 5, "a token") }, { false, Bank.WORDS.none })
				-- a case that wants someone else to pay joins them, as arriving in the game would
				r.wallet.join(bob)
				t.truthy(town1.charge(bob, 5, "a token"))
				t.eq(r.wallet.balance(bob), 295)
				-- ONE pass: bought through a game's ctx.town.pass (paintball's desk), it opens the lounge door
				-- (wallet.pass.has) and shows on the screen (PassUntil); bought at a door, the game sees it
				t.truthy(town1.pass == r.wallet.pass)
				t.falsy(r.wallet.pass.has(r.player))
				t.deepEq(
					{ town1.pass.buy(r.player) },
					{ true, "Pass bought: five days of paintball and both lounges." }
				)
				t.truthy(r.wallet.pass.has(r.player), "the lounge door lets them in")
				t.eq(type(r.player:GetAttribute("PassUntil")), "number", "and the corner shows the pass line")
				t.eq(r.wallet.balance(r.player), 260)
				t.deepEq({ r.wallet.pass.buy(r.player) }, { false, "You already have a pass." })
				t.eq(r.wallet.balance(r.player), 260, "the lounge door does not sell a second one")
				t.truthy(r.wallet.pass.buy(bob), "bought at a lounge door")
				t.truthy(town1.pass.has(bob), "and the arena sees it")
				-- and sitting down at a game through the framework costs nothing and is not disturbed
				Rig.press(r, S.coin)
				Rig.run(r, 0.3)
				t.eq(r.client.active(), S.coin)
				t.eq(r.wallet.balance(r.player), 260)
				-- and the balance is on screen during the game: the HUD finds the real MinigameUI's scorecard by
				-- the names it knows and stands above it
				local hud = WalletHud.start({
					player = r.player,
					now = function(): number
						return 9 * DAY
					end,
					daySeconds = DAY,
				})
				t.eq(r.gui.Name, WalletHud.CARD_GUI)
				local card = r.gui:FindFirstChild(WalletHud.CARD)
				t.truthy(card ~= nil and card.ClassName == "Frame", "MinigameUI's scorecard, by name")
				t.truthy(r.player:GetAttribute("InMinigame") ~= nil)
				Rig.run(r, 0.1)
				local stack = hud.gui:FindFirstChild("Stack")
				t.truthy(card.Visible, "the game's scorecard is up")
				local top = -card.Position.Y.Offset
				t.truthy(top >= 182, `the card's top edge was read ({top})`)
				t.eq(-stack.Position.Y.Offset, top + WalletHud.GAP)
				t.truthy(hud.balance.Visible)
				t.eq(hud.balance.Text, "Wallet  S$2.60")
				hud.stop()
			end, { sites = { [SITE] = PLACE }, furnish = FakeGames.furnish })
			-- a case with a charge of its own (a bare test's town) gets the service's stand-in pass, sold through
			-- THAT charge on the same terms: paintball's own specs record their charge this way
			local charged: { any } = {}
			Rig.play(function(r)
				local desk = FakeGames.tables[S.match].ctx.town.pass
				t.truthy(desk ~= r.wallet.pass)
				t.falsy(desk.has(r.player))
				t.deepEq({ desk.buy(r.player) }, { true, "Pass bought: five days of paintball and both lounges." })
				t.deepEq(charged, { { r.player, 20, "a paintball pass" } })
				t.truthy(desk.has(r.player))
				t.near(desk.left(r.player), 5)
				t.deepEq({ desk.buy(r.player) }, { false, "You already have a pass." })
				t.eq(#charged, 1, "a holder is not charged again")
				t.deepEq({ desk.offer() }, { r.wallet.pass.offer() })
				t.eq(r.wallet.balance(r.player), 300, "the rig's wallet was not asked")
				-- a refusal from that charge is passed on in its words
				local refused = Rig.stub("Ref")
				refused.broke = true
				t.deepEq({ desk.buy(refused) }, { false, "No." })
				t.falsy(desk.has(refused))
			end, {
				sites = { [SITE] = PLACE },
				furnish = FakeGames.furnish,
				service = {
					games = {
						charge = function(p: any, cents: number, why: string): (boolean, string?)
							if type(p) == "table" and p.broke then
								return false, "No."
							end
							table.insert(charged, { p, cents, why })
							return true
						end,
					},
				},
			})
			-- the real fortune teller with the real wallet behind the town: a pull is free, as the brief demands
			Rig.play(function(r)
				local before = r.wallet.balance(r.player)
				Rig.press(r, CABINET)
				Rig.run(r, 0.3)
				t.eq(r.client.active(), CABINET)
				t.truthy(Rig.has(Rig.texts(r.gui), "The reels are spinning..."), Rig.screen(r))
				FakeEngine.runDelayed(function(seconds: number): boolean
					return seconds < 4
				end)
				t.eq(Rig.count(r.got, "fortune"), 1)
				t.eq(r.wallet.balance(r.player), before, "no money in or out of the fortune machine, ever")
				for _, e in r.wallet.log() do
					t.truthy(not string.find(e.why, "fortune", 1, true))
				end
			end, { stand = AT_CABINET })
		end
	)

	-- ONCE PAINTBALL IS JOINED (its server lane is not on this branch: the case appears by itself the day its
	-- test kit is in the tree, and was run on a scratch merge of the two branches before it was written down).
	-- Paintball's desk must sell the TOWN's pass: PaintballService takes ctx.town.pass when nobody hands it one
	-- (`d.pass or (if d.day == nil then ctx.town.pass else nil) or its own desk`), and its kit joins each
	-- stand-in to the rig's wallet (`w.wallet.join(stub)` in kit.client), as arriving in the game does.
	if fs.isFile("tests/isolated/paintball_server_kit.luau") then
		t.test(
			"joined with paintball: the desk in the TV station sells the town's one pass, and a lounge door's pass opens the arena",
			function()
				local load: any = require
				local Kit = load("@tests/isolated/paintball_server_kit")
				local Contract = load("@shared/Minigames/Paintball/Contract")
				Kit.play(function(kit: any)
					local wallet = kit.w.wallet -- the rig's: wired as Boot/Game wires the town's
					local ada = kit.client("Ada")
					wallet.join(ada.stub)
					t.deepEq({ kit.join(ada) }, { false, Contract.textFor("pass") })
					-- bought at Contract.DESK: the wallet holds it, so the lounge door opens and the corner shows it
					t.deepEq({ kit.join(ada, Contract.DESK) }, { false, Contract.textFor("bought") })
					t.truthy(wallet.pass.has(ada.stub), "a pass bought at the paintball desk opens the lounges")
					t.eq(type(ada.stub.attrs.PassUntil), "number", "and the pass line shows in the corner")
					t.eq(wallet.balance(ada.stub), 280)
					t.deepEq({ wallet.pass.buy(ada.stub) }, { false, "You already have a pass." })
					t.deepEq({ kit.join(ada, Contract.DESK) }, { false, Contract.textFor("has_pass") })
					t.eq(wallet.balance(ada.stub), 280, "one pass, paid for once")
					-- the reverse: bought at a lounge door, the arena lets them in and its desk sells no second one
					local bea = kit.client("Beatrice") -- (a stand-in is known by the length of its name: not Ada again)
					wallet.join(bea.stub)
					t.truthy(wallet.pass.buy(bea.stub))
					t.deepEq({ kit.join(bea, Contract.DESK) }, { false, Contract.textFor("has_pass") })
					t.truthy((kit.join(bea)), "a pass bought at a lounge door opens the arena")
					t.eq(wallet.balance(bea.stub), 280)
				end, { realPass = true })
			end
		)
	end

	t.test(
		"the HUD's words: the balance, a change with its reason, pocket money, the pass in days and minutes",
		function()
			t.eq(WalletHud.balanceText(300), "Wallet  S$3.00")
			t.eq(WalletHud.balanceText(0), "Wallet  S$0.00")
			t.eq(WalletHud.balanceText(123456), "Wallet  S$1,234.56")
			t.eq(WalletHud.changeText(-12, "coffee"), "-12c  coffee")
			t.eq(WalletHud.changeText(5, "mowing a lawn"), "+5c  mowing a lawn")
			t.eq(WalletHud.changeText(-204, "the corner store"), "-S$2.04  the corner store")
			t.eq(WalletHud.changeText(7, nil), "+7c")
			t.eq(WalletHud.pocketText(300), "Pocket money: S$3.00 to spend")
			t.eq(WalletHud.passText(14 * DAY, 9 * DAY, DAY), "Pass: 5.0 days (60 min)")
			t.eq(WalletHud.passText(14 * DAY, 10.5 * DAY, DAY), "Pass: 3.5 days (42 min)")
			t.eq(WalletHud.passText(14 * DAY, 13.5 * DAY, DAY), "Pass: 6 min left")
			t.eq(WalletHud.passText(14 * DAY, 14 * DAY - 1, DAY), "Pass: 1 min left")
			t.eq(WalletHud.passText(14 * DAY, 14 * DAY, DAY), nil, "run out")
			t.eq(WalletHud.passText(nil, 0, DAY), nil, "no pass")
			-- the note the server writes, and reading it back
			t.eq(Credits.note(7, -12, "coffee"), "7|-12|coffee")
			t.deepEq({ WalletHud.parseNote("7|-12|coffee") }, { 7, -12, "coffee" })
			t.deepEq(
				{ WalletHud.parseNote("12|30|refund: a kite | a string") },
				{ 12, 30, "refund: a kite | a string" }
			)
			t.deepEq({ WalletHud.parseNote("0|0|") }, { 0, 0, "" })
			t.deepEq({ WalletHud.parseNote(nil) }, {})
			t.deepEq({ WalletHud.parseNote("coffee") }, {})
			-- what is said of a balance that moved: the amount is always the true movement
			t.eq(WalletHud.noteText(-12, 1, 2, -12, "coffee"), "-12c  coffee", "one change, its reason")
			t.eq(WalletHud.noteText(-67, 1, 4, -60, "a kite"), "-67c  a kite and 2 more", "three reached us as one")
			t.eq(WalletHud.noteText(-7, 1, 3, 5, "a tip"), "-7c", "a spend and a pay: the total, and no wrong reason")
			t.eq(WalletHud.noteText(-30, 1, 4, -30, "a kite"), "-30c  a kite", "refunded and bought again")
			t.eq(WalletHud.noteText(300, 0, 1, 300, "pocket money"), nil, "pocket money has its own line")
			t.eq(WalletHud.noteText(-12, 1, nil, nil, nil), "-12c", "no note at all: the amount alone")
			-- where it stands
			t.eq(WalletHud.bottom(false), 144)
			t.eq(WalletHud.bottom(true, 266), 278)
			t.eq(WalletHud.top(false), 150)
			t.eq(WalletHud.top(true), 216)
			t.truthy(WalletHud.underMenu(true, 667), "a phone: the role menu's panel fills the width")
			t.truthy(WalletHud.underMenu(true, 1024), "a tablet")
			t.falsy(WalletHud.underMenu(true, 1366), "a laptop has room beside the panel")
			t.falsy(WalletHud.underMenu(false, 667), "menu shut: always shown")
		end
	)

	t.test("the HUD: the balance is always on screen and changes the moment the server's wallet does", function()
		FakeEngine.with(function()
			-- as a client gets it: one signal per attribute per frame, with the frame's last value
			FakeEngine.deferAttributes(true)
			local frame = FakeEngine.frame
			local w = town()
			local player = (game :: any):GetService("Players").LocalPlayer
			local heartbeat = (game :: any):GetService("RunService").Heartbeat
			local hud = WalletHud.start({
				now = function(): number
					return w.t
				end,
				daySeconds = DAY,
			})
			-- where and how: its own ScreenGui under PlayerGui, in the HUD's style, bottom-right
			t.truthy(hud.gui.Parent == player:FindFirstChild("PlayerGui"))
			t.eq(hud.gui.Name, "SpicyWallet")
			t.eq(hud.balance.Font, roblox.Enum.Font.GothamBold)
			t.eq(hud.balance.BackgroundTransparency, 0.45)
			t.eq(hud.balance.BackgroundColor3, roblox.Color3.new(0, 0, 0))
			local stack = hud.gui:FindFirstChild("Stack")
			t.eq(stack.AnchorPoint, roblox.Vector2.new(1, 1))
			t.truthy(stack.Position.X.Scale == 1 and stack.Position.Y.Scale == 1, "anchored to the bottom-right corner")
			-- before the server has written anything there is nothing to draw (never a made-up balance)
			t.falsy(hud.balance.Visible)
			t.falsy(hud.note.Visible)
			t.falsy(hud.pass.Visible)
			-- the server opens the account: the balance and the pocket money line appear in that frame
			w.wallet.join(player)
			frame()
			t.truthy(hud.balance.Visible)
			t.eq(hud.balance.Text, "Wallet  S$3.00")
			t.truthy(hud.note.Visible)
			t.eq(hud.note.Text, "Pocket money: S$3.00 to spend")
			t.falsy(hud.pass.Visible)
			FakeEngine.runDelayed()
			t.falsy(hud.note.Visible, "the pocket money line goes after a while")
			t.truthy(hud.balance.Visible, "the balance never does")
			-- a purchase: the new balance, the change and its reason above it, in red
			t.truthy(w.wallet.spend(player, 12, "coffee"))
			frame()
			t.eq(hud.balance.Text, "Wallet  S$2.88")
			t.truthy(hud.note.Visible)
			t.eq(hud.note.Text, "-12c  coffee")
			t.eq(hud.note.TextColor3, roblox.Color3.fromRGB(255, 130, 110))
			t.eq(hud.balance.TextColor3, roblox.Color3.fromRGB(255, 130, 110), "the balance flashes")
			-- pay: green
			t.truthy(w.wallet.add(player, 5, "mowing a lawn"))
			frame()
			t.eq(hud.balance.Text, "Wallet  S$2.93")
			t.eq(hud.note.Text, "+5c  mowing a lawn")
			t.eq(hud.note.TextColor3, roblox.Color3.fromRGB(120, 230, 120))
			FakeEngine.runDelayed()
			t.falsy(hud.note.Visible)
			t.eq(hud.balance.TextColor3, roblox.Color3.new(1, 1, 1), "and settles back to white")
			-- a refusal changes nothing on screen (the shop shows the words itself)
			t.falsy((w.wallet.spend(player, 999, "a jet ski")))
			frame()
			t.eq(hud.balance.Text, "Wallet  S$2.93")
			t.falsy(hud.note.Visible)
			-- a purchase that could not be handed over, all in one frame: the balance went down and straight
			-- back, a client never saw it move, and nothing is said (the shop says why it did not work)
			w.wallet.spend(player, 30, "a kite", function(): (boolean?, string?)
				return false
			end)
			frame()
			t.eq(hud.balance.Text, "Wallet  S$2.93")
			t.falsy(hud.note.Visible, "no '+30c refund' for money that never visibly left")
			-- the same over two frames (a handing-over that waited): down, then back up with its reason
			local co = coroutine.create(function()
				w.wallet.spend(player, 30, "a kite", function(): (boolean?, string?)
					coroutine.yield()
					return false
				end)
			end)
			coroutine.resume(co)
			frame()
			t.eq(hud.balance.Text, "Wallet  S$2.63")
			t.eq(hud.note.Text, "-30c  a kite", "exact, although two changes went unseen before it")
			coroutine.resume(co)
			frame()
			t.eq(hud.balance.Text, "Wallet  S$2.93")
			t.eq(hud.note.Text, "+30c  refund: a kite")
			FakeEngine.runDelayed()
			-- the review's checkout charging thing by thing: bubbles 3, soda 4 and a kite 60 in one frame. The
			-- amount is the true total and the reason does not pretend the kite cost 67c
			w.wallet.spend(player, 3, "bubbles")
			w.wallet.spend(player, 4, "soda")
			w.wallet.spend(player, 60, "a kite")
			frame()
			t.eq(hud.balance.Text, "Wallet  S$2.26")
			t.eq(hud.note.Text, "-67c  a kite and 2 more")
			-- what the header tells a till to do instead: one purchase, one spend
			w.wallet.spend(player, 67, "3 things")
			frame()
			t.eq(hud.balance.Text, "Wallet  S$1.59")
			t.eq(hud.note.Text, "-67c  3 things")
			-- a spend and a pay in one frame: the total, in the colour of where it ended, and no wrong reason
			w.wallet.spend(player, 12, "coffee")
			w.wallet.add(player, 5, "a tip")
			frame()
			t.eq(hud.balance.Text, "Wallet  S$1.52")
			t.eq(hud.note.Text, "-7c")
			t.eq(hud.note.TextColor3, roblox.Color3.fromRGB(255, 130, 110))
			FakeEngine.runDelayed()
			-- the pass: a line of its own with the time left, counted down from the day clock once a second
			t.truthy(w.wallet.pass.buy(player))
			frame()
			t.eq(hud.balance.Text, "Wallet  S$1.32")
			t.eq(hud.note.Text, "-20c  a paintball pass")
			t.truthy(hud.pass.Visible)
			t.eq(hud.pass.Text, "Pass: 5.0 days (60 min)")
			w.t += 1.5 * DAY
			heartbeat.fire(0.4)
			t.eq(hud.pass.Text, "Pass: 5.0 days (60 min)", "not recounted every frame")
			heartbeat.fire(0.7)
			t.eq(hud.pass.Text, "Pass: 3.5 days (42 min)")
			w.t += 3 * DAY
			heartbeat.fire(1)
			t.eq(hud.pass.Text, "Pass: 6 min left")
			w.t += 0.5 * DAY
			heartbeat.fire(1)
			t.falsy(hud.pass.Visible, "run out: the line goes")
			t.truthy(hud.note.Visible, "and the player is told, once")
			t.eq(hud.note.Text, "Your pass has run out")
			FakeEngine.runDelayed()
			t.falsy(hud.note.Visible)
			heartbeat.fire(1)
			t.falsy(hud.note.Visible, "not said again every second")
			t.truthy(hud.balance.Visible)
			-- bought again: back in that frame (PassUntil changed), no waiting for the next second
			t.truthy(w.wallet.pass.buy(player))
			frame()
			t.truthy(hud.pass.Visible)
			t.eq(hud.pass.Text, "Pass: 5.0 days (60 min)")
			-- stopped: gone from the screen and deaf to the wallet
			FakeEngine.runDelayed()
			hud.stop()
			t.eq(hud.gui.Parent, nil)
			t.eq(player:GetAttributeChangedSignal("Cents").count(), 0)
			t.eq(heartbeat.count(), 0)
			w.wallet.spend(player, 1, "bubble gum")
			frame()
			t.eq(hud.balance.Text, "Wallet  S$1.12", "nothing redrawn after stop")
		end)
	end)

	t.test("the HUD after leaving and coming back: the balance as it was left, and no pocket money line", function()
		FakeEngine.with(function()
			FakeEngine.deferAttributes(true)
			local w = town()
			-- the review's case: a 12c coffee, leave, rejoin. The old wallet refilled to S$3.00 and the screen
			-- read "Pocket money: S$0.12 to spend" over it
			local first = person("Ann", 11)
			w.wallet.join(first)
			w.wallet.spend(first, 12, "coffee")
			w.wallet.leave(first)
			local player = (game :: any):GetService("Players").LocalPlayer
			rawset(player, "UserId", 11)
			local hud = WalletHud.start({
				now = function(): number
					return w.t
				end,
				daySeconds = DAY,
			})
			t.eq(w.wallet.join(player), 0)
			FakeEngine.frame()
			t.eq(hud.balance.Text, "Wallet  S$2.88")
			t.falsy(hud.note.Visible, "nothing was given: nothing is said")
			-- and the next change reads exactly, from the count the join handed over
			w.wallet.spend(player, 5, "nachos")
			FakeEngine.frame()
			t.eq(hud.balance.Text, "Wallet  S$2.83")
			t.eq(hud.note.Text, "-5c  nachos")
			hud.stop()
		end)
	end)

	t.test(
		"the HUD started after the money is already there (every real join): everything shows at once, on the day clock",
		function()
			FakeEngine.with(function()
				local w = town()
				local player = (game :: any):GetService("Players").LocalPlayer
				w.wallet.join(player)
				w.wallet.pass.buy(player)
				-- the day clock as Boot/DayClock publishes it, and the clock every client shares
				local rs = (game :: any):GetService("ReplicatedStorage")
				rs:SetAttribute("ClockRealSecondsPerDay", DAY)
				rs:SetAttribute("ClockBase", 9 * DAY)
				rs:SetAttribute("ClockRate", 1)
				rs:SetAttribute("ClockEpoch", 5000)
				local serverTime = 5000 + 2 * DAY
				rawset(workspace, "GetServerTimeNow", function(_self: any): number
					return serverTime
				end)
				local hud = WalletHud.start()
				t.eq(hud.balance.Text, "Wallet  S$2.80")
				t.truthy(hud.balance.Visible)
				t.eq(hud.note.Text, "Pocket money: S$3.00 to spend")
				t.truthy(hud.note.Visible)
				t.truthy(hud.pass.Visible)
				t.eq(hud.pass.Text, "Pass: 3.0 days (36 min)", "two days into a five-day pass, by the published clock")
				-- a second HUD line never hides the first: three lines, three labels, stacked by the layout
				local stack = hud.gui:FindFirstChild("Stack")
				t.truthy(stack:FindFirstChildOfClass("UIListLayout") ~= nil)
				t.truthy(hud.note.LayoutOrder < hud.pass.LayoutOrder and hud.pass.LayoutOrder < hud.balance.LayoutOrder)
				-- a minigame's scorecard takes the corner: the wallet stands above it, and comes back down after
				t.eq(stack.Position.Y.Offset, -144, "just above the Menu button")
				player:SetAttribute("InMinigame", "bowling_lane_3")
				t.eq(stack.Position.Y.Offset, -194, "clear of the scorecard (170 tall at -182)")
				t.truthy(WalletHud.bottom(true) > 182 and WalletHud.bottom(false) > 96 + 40)
				-- each game sizes the scorecard for itself: the wallet follows the card's own top edge
				local heartbeat = (game :: any):GetService("RunService").Heartbeat
				local ui = FakeEngine.new("ScreenGui", WalletHud.CARD_GUI)
				ui.Parent = player:FindFirstChild("PlayerGui")
				local card = FakeEngine.new("Frame", WalletHud.CARD)
				card.Visible = true
				card.Parent = ui
				local function cardAt(top: number): number
					card.Position = roblox.UDim2.new(1, -612, 1, -top)
					heartbeat.fire(1 / 60)
					return -stack.Position.Y.Offset
				end
				t.eq(cardAt(38 + 6 * 38), 278, "six bowlers: Games/Bowling's card is 266 high")
				t.eq(cardAt(262), 274, "darts cricket")
				t.eq(cardAt(46 + 2 * 40), 194, "a short card: never lower than over the standard one")
				card.Visible = false
				heartbeat.fire(1 / 60)
				t.eq(stack.Position.Y.Offset, -194)
				card.Visible = true
				t.eq(cardAt(300), 312)
				player:SetAttribute("InMinigame", nil)
				t.eq(stack.Position.Y.Offset, -144, "the game over: back above the Menu button at once")
				heartbeat.fire(1 / 60)
				t.eq(stack.Position.Y.Offset, -144, "and a card left on screen moves nothing outside a game")
				t.eq(WalletHud.bottom(true, 266), 278)
				t.eq(WalletHud.bottom(false, 266), 144)
				-- a player with an empty wallet still sees it
				hud.stop()
				player:SetAttribute("Cents", 0)
				player:SetAttribute("PocketMoney", nil)
				player:SetAttribute("PassUntil", nil)
				local empty = WalletHud.start()
				t.truthy(empty.balance.Visible)
				t.eq(empty.balance.Text, "Wallet  S$0.00")
				t.falsy(empty.note.Visible)
				t.falsy(empty.pass.Visible)
				empty.stop()
			end)
		end
	)

	t.test(
		"the HUD on a phone or tablet, and under the role menu: clear of the jump button and of the menu's panel",
		function()
			FakeEngine.with(function()
				local w = town()
				local player = (game :: any):GetService("Players").LocalPlayer
				local heartbeat = (game :: any):GetService("RunService").Heartbeat
				local camera = (workspace :: any).CurrentCamera
				w.wallet.join(player)
				w.wallet.pass.buy(player)
				-- a touch device is found from the input service (touch and no keyboard), as the bowling client does
				local uis = FakeEngine.uis()
				uis.TouchEnabled = true
				uis.KeyboardEnabled = false
				rawset(camera, "ViewportSize", roblox.Vector2.new(1024, 768))
				local hud = WalletHud.start({
					now = function(): number
						return w.t
					end,
					daySeconds = DAY,
				})
				local stack = hud.gui:FindFirstChild("Stack")
				-- it hangs from the top-right, under the status, sickness and toast lines (to 144), and grows down
				t.eq(stack.AnchorPoint, roblox.Vector2.new(1, 0))
				t.truthy(stack.Position.X.Scale == 1 and stack.Position.Y.Scale == 0, "anchored to the top-right")
				t.eq(stack.Position.X.Offset, -12)
				t.eq(stack.Position.Y.Offset, 150)
				t.truthy(WalletHud.TOUCH_TOP >= 108 + 36, "under UI/PlayMenu's toast")
				local list = stack:FindFirstChildOfClass("UIListLayout")
				t.eq(list.VerticalAlignment, roblox.Enum.VerticalAlignment.Top)
				t.truthy(
					hud.balance.LayoutOrder < hud.pass.LayoutOrder and hud.pass.LayoutOrder < hud.note.LayoutOrder,
					"the balance on top, the lines that come and go beneath it"
				)
				-- its three lines (32 + 27 + 27 and two gaps of 4) end at 244: above Roblox's jump button on a
				-- 375-high phone (70 tall, 90 above the bottom: from 285 down) and on a 768-high tablet (120 tall, 210
				-- above the bottom: from 558 down)
				local lowest = WalletHud.TOUCH_TOP + 32 + 4 + 27 + 4 + 27
				t.truthy(lowest < 375 - 90, `the stack ends at {lowest}`)
				t.truthy(lowest < 768 - 210)
				-- and above UI/PlayMenu's Menu button, which stands 96 above the bottom and is scaled down on a
				-- small screen (40 tall times PlayMenu.scaleFor: 24 on that phone, its top edge at 255)
				for _, size in { { 667, 375 }, { 844, 390 }, { 1024, 768 }, { 1180, 820 } } do
					local buttonTop = size[2] - 96 - 40 * PlayMenu.scaleFor(size[1], size[2])
					t.truthy(lowest < buttonTop, `{size[1]} x {size[2]}: the Menu button begins at {buttonTop}`)
				end
				-- in a minigame: under that game's status and warning lines (to 210). On a tablet that is clear
				-- of the scorecard (from 586 down); on a 375-high phone the game's own screen, which is not sized
				-- for phones, covers most of the display and the wallet with it (a known limit, for the minigame UI)
				player:SetAttribute("InMinigame", "bowling_lane_3")
				t.eq(stack.Position.Y.Offset, 216)
				t.truthy(WalletHud.TOUCH_TOP_GAME >= 182 + 28, "under UI/MinigameUI's warning line")
				player:SetAttribute("InMinigame", nil)
				t.eq(stack.Position.Y.Offset, 150)
				t.truthy(hud.balance.Visible and hud.pass.Visible)
				-- the role menu opens (UI/PlayMenu: ScreenGui "SpicyPlay", Frame "Menu"): on a tablet the panel
				-- leaves no room beside it, so the stack goes; it is back the moment the menu shuts
				local play = FakeEngine.new("ScreenGui", WalletHud.MENU_GUI)
				play.Parent = player:FindFirstChild("PlayerGui")
				local menu = FakeEngine.new("Frame", WalletHud.MENU)
				menu.Visible = false
				menu.Parent = play
				heartbeat.fire(1 / 60)
				t.truthy(stack.Visible)
				menu.Visible = true
				heartbeat.fire(1 / 60)
				t.falsy(stack.Visible, "hidden under the open menu")
				menu.Visible = false
				heartbeat.fire(1 / 60)
				t.truthy(stack.Visible)
				-- a phone, menu open
				rawset(camera, "ViewportSize", roblox.Vector2.new(667, 375))
				menu.Visible = true
				heartbeat.fire(1 / 60)
				t.falsy(stack.Visible)
				-- a wide screen has room for both
				rawset(camera, "ViewportSize", roblox.Vector2.new(1920, 1080))
				heartbeat.fire(1 / 60)
				t.truthy(stack.Visible)
				hud.stop()
				-- a desktop narrower than the panel plus the stack hides it the same way, and stays bottom-right
				uis.TouchEnabled = false
				uis.KeyboardEnabled = true
				rawset(camera, "ViewportSize", roblox.Vector2.new(1000, 700))
				local desk = WalletHud.start({ daySeconds = DAY })
				local deskStack = desk.gui:FindFirstChild("Stack")
				t.eq(deskStack.AnchorPoint, roblox.Vector2.new(1, 1))
				t.falsy(deskStack.Visible, "the menu was open when it started")
				menu.Visible = false
				heartbeat.fire(1 / 60)
				t.truthy(deskStack.Visible)
				desk.stop()
				-- the names and sizes it goes by are UI/PlayMenu's own
				local src = fs.readFile("src/client/UI/PlayMenu.luau")
				t.truthy(string.find(src, `gui.Name = "{WalletHud.MENU_GUI}"`, 1, true))
				t.truthy(string.find(src, `menu.Name = "{WalletHud.MENU}"`, 1, true))
				t.truthy(string.find(src, `panel.Size = UDim2.fromOffset({WalletHud.MENU_PANEL}, 520)`, 1, true))
				t.truthy(string.find(src, "Position = UDim2.new(0.5, 0, 0, 108)", 1, true), "the toast's top edge")
			end)
		end
	)
end
