--!strict
-- tests/isolated/wallet.luau: cases for tests/unit/wallet.spec.luau, run in their own Lune process
-- (tests/lib/Isolated) because they install fake engine globals (tests/lib/FakeEngine).
-- The town's wallet as the game runs it: the real Server/Economy/Credits on engine Players (the attributes a
-- client reads change the moment the money does), the real Roles/RoleService holding the wallet's purse, the
-- real MinigameService with the wallet behind ctx.town.charge (on tests/lib/MinigameRig, with the real
-- fortune teller and the spec-only games), and the real Client/UI/WalletHud drawing what the server wrote.
-- Interface: return function(t) (the spec shape)
-- (FakeGames first: it registers its games, and the wire's verb list is read from the registry when
-- Shared/Net/Schemas loads)
local FakeGames = require("@tests/lib/FakeGames")
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local Bank = require("@shared/Economy/Bank")
local Tunables = require("@shared/Config/Tunables")
local Credits = require("@server/Economy/Credits")
local RoleLab = require("@server/Roles/RoleLab")
local RoleService = require("@server/Roles/RoleService")
local WalletHud = require("@client/UI/WalletHud")
local FakeEngine = require("@tests/lib/FakeEngine")
local Rig = require("@tests/lib/MinigameRig")
local roblox = require("@lune/roblox")

local SITE, PLACE, S = FakeGames.SITE, FakeGames.PLACE, FakeGames.STATIONS
local DAY = 720
local F = AlleyLayout.FORTUNE
local CABINET = "fortune_1"
local AT_CABINET = { site = "bowling_alley", x = F.x - 1.6, y = 3, d = F.d - 1.6 }

type Town = { wallet: Credits.Wallet, t: number, lines: { string } }

-- a wallet on a game clock the case moves by hand (it opens on day 9, as the game does)
local function town(): Town
	local w = { t = 9 * DAY, lines = {} } :: Town
	w.wallet = Credits.new({
		gameSeconds = function(): number
			return w.t
		end,
		daySeconds = DAY,
		log = function(line: string)
			table.insert(w.lines, line)
		end,
	})
	return w
end

local function person(name: string, userId: number): any
	local p = FakeEngine.new("Player", name)
	rawset(p, "UserId", userId)
	return p
end

-- every value an attribute takes, as a client listening to it would see them (with the reason beside it)
local function watch(player: any, name: string): { any }
	local seen: { any } = {}
	player:GetAttributeChangedSignal(name):Connect(function()
		table.insert(seen, { player:GetAttribute(name), player:GetAttribute("CentsWhy") })
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
			t.eq(ann:GetAttribute("CentsWhy"), "pocket money")
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
			t.deepEq(seen, { { 288, "coffee" } }, "the new balance, with why already beside it")
			t.deepEq({ w.wallet.add(ann, 5, "mowing a lawn") }, { true, "+5c: mowing a lawn. You have S$2.93." })
			t.deepEq(seen[2], { 293, "mowing a lawn" })
			-- refused: words, and nothing on the Player moves
			t.deepEq({ w.wallet.spend(ann, 294, "a jet ski") }, { false, "You need 294c; you have 293c" })
			t.deepEq({ w.wallet.can(ann, 294) }, { false, "You need 294c; you have 293c" })
			t.deepEq({ w.wallet.spend(ann, 1.5, "half a thing") }, { false, Bank.WORDS.amount })
			t.eq(#seen, 2)
			t.eq(ann:GetAttribute("Cents"), 293)
			-- a handing-over that fails is never charged: taken, then straight back, both logged
			t.deepEq({
				w.wallet.spend(ann, 30, "a kite", function(): (boolean?, string?)
					return false, "The shelf is empty."
				end),
			}, { false, "The shelf is empty." })
			t.deepEq(seen[3], { 263, "a kite" })
			t.deepEq(seen[4], { 293, "refund: a kite" })
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
		end)
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
			t.deepEq({ desk.buy(ann) }, { true, "Pass bought: five days of paintball and both lounges." })
			t.truthy(desk.has(ann))
			t.eq(w.wallet.balance(ann), 280)
			t.eq(ann:GetAttribute("Cents"), 280)
			t.eq(ann:GetAttribute("CentsWhy"), "a paintball pass")
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
			t.truthy(desk.buy(ann), "run out: it can be bought again")
			t.eq(ann:GetAttribute("PassUntil"), 19 * DAY)
			-- short of money: the paintball contract's words, and no pass
			local bob = person("Bob", 12)
			Tunables.applyOverrides({ ["economy.pocketMoneyCents"] = 7 })
			w.wallet.join(bob)
			Tunables.reset()
			t.deepEq({ desk.buy(bob) }, { false, "You need 20c; you have 7c" })
			t.falsy(desk.has(bob))
			t.eq(bob:GetAttribute("PassUntil"), nil)
			-- someone who never joined
			t.deepEq({ desk.buy(person("Cat", 13)) }, { false, Bank.WORDS.none })
		end)
	end)

	t.test("leaving: the account is closed and kept; coming back finds it, on the new Player", function()
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
			-- back: the same UserId, a new Player object. Topped up to S$3.00, the pass still running
			w.t += DAY
			local again = person("Ann", 11)
			t.eq(w.wallet.join(again), 100)
			t.eq(again:GetAttribute("Cents"), 300)
			t.eq(again:GetAttribute("PocketMoney"), 100)
			t.eq(again:GetAttribute("PassUntil"), 14 * DAY)
			t.truthy(w.wallet.pass.has(again))
			t.near(w.wallet.pass.left(again), 4)
			-- back with a run-out pass: none on the screen
			w.wallet.leave(again)
			w.t += 5 * DAY
			local third = person("Ann", 11)
			w.wallet.join(third)
			t.eq(third:GetAttribute("PassUntil"), nil)
			t.eq(third:GetAttribute("PocketMoney"), nil, "nothing given this time")
			-- what a profile would keep, as plain data
			w.wallet.spend(third, 12, "coffee")
			t.deepEq(w.wallet.export(third), { v = 1, cents = 288, pocket = 400, passes = {} })
			t.eq(w.wallet.export(person("Nobody", 99)), nil)
		end)
	end)

	t.test("PlayerLike stubs (the engine smoke's players) get the same wallet, on their attrs", function()
		local w = town()
		local stub: any = { UserId = 4242, Name = "Smoke" }
		t.eq(w.wallet.join(stub), 300)
		t.eq(stub.attrs.Cents, 300)
		t.truthy(w.wallet.spend(stub, 12, "coffee"))
		t.eq(stub.attrs.Cents, 288)
		t.eq(stub.attrs.CentsWhy, "coffee")
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
			{ "Ann", "You need 500c; you have 288c" },
		})
		-- the header's door
		local function door(player: any): boolean
			if wallet.pass.has(player) then
				return true
			end
			wallet.tell(player, "Members only: a pass is 20c for five in-game days.")
			return false
		end
		t.falsy(door(ann))
		t.eq(told[3][2], "Members only: a pass is 20c for five in-game days.")
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
		"roles: a member's purse is the wallet's, so Ladder pay, the queue's money term and the screen agree",
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
					purse = w.wallet.purse,
				})
				local ann, bob, cat = person("Ann", 1), person("Bob", 2), person("Cat", 3)
				t.eq(roles:onJoin(ann), "possessed")
				t.eq(ann:GetAttribute("Cents"), 300, "pocket money came with the purse")
				t.eq(roles:member(1).purse, w.wallet.bank:purse(1), "one purse, not two")
				t.eq(roles:stats(ann).cents, 300)
				roles:onJoin(bob)
				-- the server is full: the third is turned away before anything is touched, wallet included
				t.eq(roles:onJoin(cat), "kicked")
				t.eq(#kicked, 1)
				t.falsy(w.wallet.bank:has(3))
				t.eq(cat:GetAttribute("Cents"), nil)
				-- Ladder pay lands in the wallet, with its rule as the reason, and on the screen
				roles:report({ kind = "work.completed", player = 1, class = "standard", pay = 6 })
				t.eq(w.wallet.balance(ann), 306)
				t.eq(ann:GetAttribute("Cents"), 306)
				local last = w.wallet.log()[#w.wallet.log()]
				t.eq(last.delta, 6)
				t.truthy(type(last.why) == "string" and #last.why > 0)
				-- money spent in a shop is money the queue no longer counts
				t.truthy(w.wallet.spend(ann, 200, "the corner store"))
				t.eq(roles:stats(ann).cents, 106)
				roles:queue("human")
				t.eq(roles:member(1).stats.cents, 106)
				t.eq(roles:member(2).stats.cents, 300)
				-- the Role Lab's "cents" goes through the wallet too
				local lab = RoleLab.new(roles, {
					isDev = function(): boolean
						return true
					end,
				})
				t.truthy((lab:command(ann, "stat", { "cents", 500 })))
				t.eq(w.wallet.balance(ann), 500)
				t.eq(ann:GetAttribute("Cents"), 500)
				t.eq(ann:GetAttribute("CentsWhy"), "role lab")
				t.truthy((lab:command(ann, "stat", { "cents", 20 })))
				t.eq(w.wallet.balance(ann), 20)
				t.falsy((lab:command(ann, "stat", { "cents", 2.5 })))
				t.eq(w.wallet.balance(ann), 20)
				t.eq(roles:stats(ann).cents, 20)
				-- leaving and coming back: the Ladder's member is new, the money is not
				roles:onLeave(ann)
				w.wallet.leave(ann)
				t.eq(roles:onJoin(person("Ann", 1)), "possessed")
				t.eq(roles:stats({ UserId = 1 }).cents, 300, "topped up, as on any join")
				-- without a wallet (a bare test's RoleService) a member still has a purse of its own, at nothing
				local bare = RoleService.new({
					possession = possession,
					pickBody = function(): any
						return { id = "human" }
					end,
				})
				bare:onJoin(person("Dee", 4))
				t.eq(bare:member(4).purse.cents, 0)
			end)
		end
	)

	t.test("minigames: ctx.town.charge is the wallet, and a game played with it behind is as it was", function()
		local w = town()
		local opts = function(more: { [string]: any }?): Rig.Opts
			local o: any = {
				service = {
					games = {
						-- exactly Boot/Game's line
						charge = function(player: any, cents: number, why: string): (boolean, string?)
							return w.wallet.spend(player, cents, why)
						end,
					},
				},
			}
			for k, v in more or {} do
				o[k] = v
			end
			return o
		end
		-- a Table of a spec-only game asks the town for money
		Rig.play(function(r)
			w.wallet.join(r.player)
			local charge = FakeGames.tables[S.match].ctx.town.charge
			t.truthy(charge == FakeGames.tables[S.coin].ctx.town.charge, "one town for every Table")
			t.deepEq(
				{ charge(r.player, 20, "a paintball pass") },
				{ true, "Paid 20c for a paintball pass. You have S$2.80." }
			)
			t.eq(r.player:GetAttribute("Cents"), 280)
			t.deepEq({ charge(r.player, 500, "the arena") }, { false, "You need 500c; you have 280c" })
			t.deepEq({ charge(Rig.stub("Bob"), 5, "a token") }, { false, Bank.WORDS.none })
			t.eq(w.wallet.balance(r.player), 280)
			-- and sitting down at a game through the framework costs nothing and is not disturbed
			Rig.press(r, S.coin)
			Rig.run(r, 0.3)
			t.eq(r.client.active(), S.coin)
			t.eq(w.wallet.balance(r.player), 280)
			w.wallet.leave(r.player)
		end, opts({ sites = { [SITE] = PLACE }, furnish = FakeGames.furnish }))
		-- the real fortune teller with the real wallet behind the town: a pull is free, as the brief demands
		Rig.play(function(r)
			w.wallet.join(r.player)
			local before = w.wallet.balance(r.player)
			Rig.press(r, CABINET)
			Rig.run(r, 0.3)
			t.eq(r.client.active(), CABINET)
			t.truthy(Rig.has(Rig.texts(r.gui), "The reels are spinning..."), Rig.screen(r))
			FakeEngine.runDelayed(function(seconds: number): boolean
				return seconds < 4
			end)
			t.eq(Rig.count(r.got, "fortune"), 1)
			t.eq(w.wallet.balance(r.player), before, "no money in or out of the fortune machine, ever")
			for _, e in w.wallet.log() do
				t.truthy(not string.find(e.why, "fortune", 1, true))
			end
		end, opts({ stand = AT_CABINET }))
	end)

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
		end
	)

	t.test("the HUD: the balance is always on screen and changes the moment the server's wallet does", function()
		FakeEngine.with(function()
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
			-- the server opens the account: the balance and the pocket money line appear at once
			w.wallet.join(player)
			t.truthy(hud.balance.Visible)
			t.eq(hud.balance.Text, "Wallet  S$3.00")
			t.truthy(hud.note.Visible)
			t.eq(hud.note.Text, "Pocket money: S$3.00 to spend")
			t.falsy(hud.pass.Visible)
			FakeEngine.runDelayed()
			t.falsy(hud.note.Visible, "the pocket money line goes after a while")
			t.truthy(hud.balance.Visible, "the balance never does")
			-- a purchase: the new balance in the same instant, the change and its reason above it, in red
			t.truthy(w.wallet.spend(player, 12, "coffee"))
			t.eq(hud.balance.Text, "Wallet  S$2.88")
			t.truthy(hud.note.Visible)
			t.eq(hud.note.Text, "-12c  coffee")
			t.eq(hud.note.TextColor3, roblox.Color3.fromRGB(255, 130, 110))
			t.eq(hud.balance.TextColor3, roblox.Color3.fromRGB(255, 130, 110), "the balance flashes")
			-- pay: green
			t.truthy(w.wallet.add(player, 5, "mowing a lawn"))
			t.eq(hud.balance.Text, "Wallet  S$2.93")
			t.eq(hud.note.Text, "+5c  mowing a lawn")
			t.eq(hud.note.TextColor3, roblox.Color3.fromRGB(120, 230, 120))
			FakeEngine.runDelayed()
			t.falsy(hud.note.Visible)
			t.eq(hud.balance.TextColor3, roblox.Color3.new(1, 1, 1), "and settles back to white")
			-- a refusal changes nothing on screen (the shop shows the words itself)
			t.falsy((w.wallet.spend(player, 999, "a jet ski")))
			t.eq(hud.balance.Text, "Wallet  S$2.93")
			t.falsy(hud.note.Visible)
			-- a purchase that could not be handed over: down and straight back up, ending on the refund
			w.wallet.spend(player, 30, "a kite", function(): (boolean?, string?)
				return false
			end)
			t.eq(hud.balance.Text, "Wallet  S$2.93")
			t.eq(hud.note.Text, "+30c  refund: a kite")
			FakeEngine.runDelayed()
			-- the pass: a line of its own with the time left, counted down from the day clock once a second
			t.truthy(w.wallet.pass.buy(player))
			t.eq(hud.balance.Text, "Wallet  S$2.73")
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
			t.truthy(hud.balance.Visible)
			-- bought again: back at once (PassUntil changed), no waiting for the next second
			t.truthy(w.wallet.pass.buy(player))
			t.truthy(hud.pass.Visible)
			t.eq(hud.pass.Text, "Pass: 5.0 days (60 min)")
			-- stopped: gone from the screen and deaf to the wallet
			FakeEngine.runDelayed()
			hud.stop()
			t.eq(hud.gui.Parent, nil)
			t.eq(player:GetAttributeChangedSignal("Cents").count(), 0)
			t.eq(heartbeat.count(), 0)
			w.wallet.spend(player, 1, "bubble gum")
			t.eq(hud.balance.Text, "Wallet  S$2.53", "nothing redrawn after stop")
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
				player:SetAttribute("InMinigame", nil)
				t.eq(stack.Position.Y.Offset, -144)
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
end
