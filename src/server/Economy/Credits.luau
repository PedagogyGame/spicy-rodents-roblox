--!strict
-- ServerScriptService.Server.Economy.Credits
-- THE WALLET: the one server module every feature that takes or pays money calls (BUILD_PLAN §1.4 "Credits
-- ledger: add, spend"; brief v2 §13a: Spicy Dollars, kept in whole cents). Boot/Game makes one for the town
-- and hands it down: it is `Game.start().wallet`, a service takes it as `deps.wallet`, and a minigame reaches
-- the same money through ctx.town.charge (which IS wallet.spend). The deciding is Shared/Economy/Bank (pure;
-- read its header for the rules: whole cents, never negative, one step per spend, pocket money on joining,
-- leaving, the pass, what would be saved); this module adds the players, the screen and the server's log.
--
-- HOW A SHOP CHARGES A PLAYER (on the server, where the prompt fires; a client is never believed about money):
--     local ok, words = wallet.spend(player, 12, "coffee")
--     if not ok then
--         tell(player, words)       -- "You need 12c; you have 7c": show it as it is
--         return
--     end
--     pourTheCoffee(player)         -- the money is gone: hand the thing over
--     tell(player, words)           -- "Paid 12c for coffee. You have S$2.88."
--   `why` names the thing in a few lower-case words ("coffee", "a kite", "lane shoes"): it is logged and set
--   into the words. The price is whole cents (Economy/EconomyRules.price(id) has the list).
--   If handing the thing over can fail or has to wait, pass it in, and a failure is never charged:
--     local ok, words = wallet.spend(player, 30, "a kite", function()
--         return giveKite(player)   -- false (or false, "The shelf is empty.") or an error: the 30c comes back
--     end)
--   To show a price before the press: wallet.can(player, 12) -> ok, words; wallet.balance(player) -> cents.
--   To pay someone (wages, a tip, a prize that is NOT a stake): wallet.add(player, 5, "mowing a lawn").
--
-- HOW A DOOR CHECKS A PASS (the paintball arena and both lounges read the same one):
--     if wallet.pass.has(player) then
--         letIn(player)             -- wallet.pass.words(player): "4.2 in-game days left (about 50 minutes)"
--     else
--         tell(player, "Members only: a pass is 20c for five in-game days.")
--     end
--   and where the pass is sold (the desk, a lounge door's prompt):
--     local ok, words = wallet.pass.buy(player)   -- (true, "Pass bought: five days of paintball and both
--         -- lounges.") or (false, "You need 20c; you have 7c") or (false, "You already have a pass.")
--   wallet.pass is { has, buy } as the paintball server's PassDesk type wants it (its deps.pass), plus
--   left(player) -> in-game days, untilDay(player) -> the in-game day it runs out, words(player).
--
-- What a player sees (Client/UI/WalletHud draws it; nothing else needs to): the player attributes Cents (the
-- balance, written the moment it changes), CentsWhy (the reason of the last change, written just before),
-- PocketMoney (cents of pocket money given at this join, nil when none) and PassUntil (the game second the
-- pass runs out, nil without one).
-- Pocket money: a joining player is topped up to Tunables economy.pocketMoneyCents (300: S$3.00), once per
-- join, so that there is something to spend before jobs pay. Set the tunable to 0 to switch it off.
-- NOT SAVED: an account lasts as long as this server does, by UserId (leaving and coming back finds it as it
-- was; a new server starts everyone afresh). The data is ready for a profile: wallet.export(player) is
-- everything an account holds as plain data and wallet.bank:import(id, saved) puts it back before the join
-- (Shared/Economy/Bank's header says how it fits Persistence/ProfileSchema). No real money anywhere here:
-- nothing in this module touches Robux or a developer product.
-- Roles: Roles/RoleService's member purse is this wallet's (its deps.purse = wallet.purse), so Ladder pay
-- lands here and the human queue's money term reads this balance.
-- Pure Luau over its deps (a player is a Player or a PlayerLike stub with a UserId); no side effects on
-- require.
-- Interface: new(deps?) -> Wallet { join(player) -> cents of pocket money given, leave(player),
--   balance(player) -> cents, can(player, cents) -> (ok, words), spend(player, cents, why, deliver?) -> (ok,
--   words), add(player, cents, why) -> (ok, words), purse(player) -> Purse (joins the player if need be),
--   pass { has, buy, left, untilDay, words }, log() -> the last changes of every account, export(player) ->
--   Bank.Saved?, bank (the Bank itself) }; PASS; types Deps, Wallet, Pass

local Import = require("../Import")
local Bank = Import.shared("Economy/Bank") :: typeof(require("../../shared/Economy/Bank"))
local EconomyRules = Import.shared("Economy/EconomyRules") :: typeof(require("../../shared/Economy/EconomyRules"))
local Tunables = Import.shared("Config/Tunables") :: typeof(require("../../shared/Config/Tunables"))
local Log = Import.shared("Util/Log") :: typeof(require("../../shared/Util/Log"))

local Credits = {}

Credits.PASS = "paintball" -- the one pass on sale: the arena and both lounges

-- (Exported types do not cross the Import shim (rule 1): the Bank's shapes are restated loosely.)
type Entry = { id: any, delta: number, why: string, balance: number, at: number }
type Purse = {
	cents: number,
	history: { any },
	credit: (any, number, string) -> (boolean, string?),
	debit: (any, number, string) -> (boolean, string?),
}

export type Deps = {
	gameSeconds: (() -> number)?, -- the game clock (Time/Clock:gameSeconds); default: seconds since new()
	daySeconds: number?, -- game seconds in an in-game day (default Tunables clock.realSecondsPerDay)
	pocket: (() -> number)?, -- pocket money in cents (default EconomyRules.pocketMoney: the tunable)
	setAttr: ((player: any, name: string, value: any) -> ())?, -- default: the Player's attribute (a stub's attrs)
	log: ((line: string) -> ())?, -- one line per change (default: the server's output, tag Wallet)
}

export type Pass = {
	has: (player: any) -> boolean,
	buy: (player: any) -> (boolean, string),
	left: (player: any) -> number, -- in-game days (a fraction counts; 0 without one)
	untilDay: (player: any) -> number?, -- the in-game day it runs out (nil: never bought one)
	words: (player: any) -> string, -- "4.2 in-game days left (about 50 minutes)" or "No pass"
}

export type Wallet = {
	join: (player: any) -> number,
	leave: (player: any) -> (),
	balance: (player: any) -> number,
	can: (player: any, cents: number) -> (boolean, string),
	spend: (player: any, cents: number, why: string, deliver: (() -> (boolean?, string?))?) -> (boolean, string),
	add: (player: any, cents: number, why: string) -> (boolean, string),
	purse: (player: any) -> Purse,
	pass: Pass,
	log: () -> { Entry },
	export: (player: any) -> any,
	bank: any, -- Shared/Economy/Bank.Bank
}

-- An account is kept by UserId where there is one (a Player object is gone when its player leaves).
local function who(player: any): any
	if (type(player) == "table" or typeof(player) == "Instance") and player.UserId ~= nil then
		return player.UserId
	end
	return player
end

local function defaultSetAttr(player: any, name: string, value: any)
	if typeof(player) == "Instance" then
		(player :: Instance):SetAttribute(name, value)
	elseif type(player) == "table" then
		player.attrs = player.attrs or {}
		player.attrs[name] = value
	end
end

function Credits.new(deps: Deps?): Wallet
	local d: Deps = deps or {}
	local born = os.clock()
	local gameSeconds = d.gameSeconds or function(): number
		return os.clock() - born
	end
	local daySeconds = d.daySeconds or (Tunables.get("clock.realSecondsPerDay") :: number)
	local setAttr = d.setAttr or defaultSetAttr
	local logger = Log.new("Wallet")
	local say = d.log or function(line: string)
		logger:info(line)
	end
	local here: { [any]: any } = {} -- id -> the player, while they are in the game

	local function show(id: any, name: string, value: any)
		local player = here[id]
		if player ~= nil then
			setAttr(player, name, value)
		end
	end

	local bank = Bank.new({
		now = gameSeconds,
		daySeconds = daySeconds,
		pocket = d.pocket or EconomyRules.pocketMoney,
		changed = function(id: any, e: Entry)
			-- the reason first: a client that sees the new balance finds why beside it
			show(id, "CentsWhy", e.why)
			show(id, "Cents", e.balance)
			say(`{tostring(id)} {if e.delta >= 0 then "+" else ""}{e.delta}c ({e.why}) -> {e.balance}c`)
		end,
		passed = function(id: any, name: string, untilSeconds: number)
			if name == Credits.PASS then
				show(id, "PassUntil", untilSeconds)
			end
			say(`{tostring(id)} holds the {name} pass until game second {math.floor(untilSeconds)}`)
		end,
	})

	local function join(player: any): number
		local id = who(player)
		local was = here[id]
		here[id] = player
		local _, given = bank:join(id)
		if was ~= player or given > 0 then
			-- (a balance that did not change at this join is still new to this Player object)
			setAttr(player, "PocketMoney", if given > 0 then given else nil)
			setAttr(player, "Cents", bank:balance(id))
			local untilSeconds = bank:passUntil(id, Credits.PASS)
			setAttr(player, "PassUntil", if untilSeconds and untilSeconds > gameSeconds() then untilSeconds else nil)
		end
		return given
	end

	local function leave(player: any)
		local id = who(player)
		bank:leave(id)
		here[id] = nil
	end

	local function passSpec(): any
		return EconomyRules.pass(Credits.PASS)
	end

	local pass: Pass = {
		has = function(player: any): boolean
			return bank:hasPass(who(player), Credits.PASS)
		end,
		buy = function(player: any): (boolean, string)
			return bank:buyPass(who(player), passSpec())
		end,
		left = function(player: any): number
			return bank:passLeft(who(player), Credits.PASS)
		end,
		untilDay = function(player: any): number?
			local untilSeconds = bank:passUntil(who(player), Credits.PASS)
			return if untilSeconds then untilSeconds / daySeconds else nil
		end,
		words = function(player: any): string
			return EconomyRules.passLeftWords(bank:passLeft(who(player), Credits.PASS), daySeconds)
		end,
	}

	return {
		join = join,
		leave = leave,
		balance = function(player: any): number
			return bank:balance(who(player))
		end,
		can = function(player: any, cents: number): (boolean, string)
			return bank:can(who(player), cents)
		end,
		spend = function(
			player: any,
			cents: number,
			why: string,
			deliver: (() -> (boolean?, string?))?
		): (boolean, string)
			return bank:spend(who(player), cents, tostring(why), deliver)
		end,
		add = function(player: any, cents: number, why: string): (boolean, string)
			return bank:add(who(player), cents, tostring(why))
		end,
		purse = function(player: any): Purse
			if not bank:has(who(player)) then
				join(player)
			end
			return bank:purse(who(player)) :: any
		end,
		pass = pass,
		log = function(): { Entry }
			return bank.entries
		end,
		export = function(player: any): any
			return bank:export(who(player))
		end,
		bank = bank,
	}
end

return Credits
