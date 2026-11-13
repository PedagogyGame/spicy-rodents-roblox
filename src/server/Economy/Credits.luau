--!strict
-- ServerScriptService.Server.Economy.Credits
-- THE WALLET: the one server module every feature that takes or pays money calls (BUILD_PLAN §1.4 "Credits
-- ledger: add, spend"; brief v2 §13a: Spicy Dollars, kept in whole cents). Boot/Game makes one for the town
-- and hands it down: it is `Game.start().wallet`, a service takes it as `deps.wallet`, and a minigame reaches
-- the same money through ctx.town.charge (which IS wallet.spend) and the same pass through ctx.town.pass
-- (which IS wallet.pass). The deciding is Shared/Economy/Bank (pure; read its header for the rules: whole
-- cents, never negative, one step per spend, pocket money once, leaving, the pass, what would be saved); this
-- module adds the players, the screen and the server's log.
--
-- HOW A SHOP CHARGES A PLAYER (on the server, where the prompt fires; a client is never believed about money).
-- Sell by the thing's id: wallet.buy reads its price and its name from Economy/EconomyRules (item(id)), so the
-- price is the list's and the player reads a name, never an id:
--     local ok, words = wallet.buy(player, "coffee")
--     if not ok then
--         wallet.tell(player, words)   -- "You need 12c; you have 7c.": show it as it is
--         return
--     end
--     pourTheCoffee(player)            -- the money is gone: hand the thing over
--     wallet.tell(player, words)       -- "Paid 12c for coffee. You have S$2.88."
--   wallet.tell(player, words) puts a line on that player's screen for a few seconds (in the game: the
--   "notice" toast every refusal uses). The balance in the corner has already changed by then, with
--   "-12c  coffee" above it, so a shop with its own way of speaking (a clerk's bubble, a receipt) may say
--   the words there instead; a refusal must always be said somewhere.
--   ONE PURCHASE IS ONE SPEND. A till with a basket hands in the list and is charged the total once:
--     wallet.buy(player, { "kite", "soda", "frisbee" })   -- "Paid 69c for a kite, a soda and a frisbee. ..."
--   never thing by thing: the screen is told only the last change of a frame, so three spends would read as
--   "-69c  a kite and 2 more" at best, and a basket half paid for is a bug waiting.
--   An id with no price or no name (EconomyRules.PRICES / NAMES, or Items/ItemRules for the corner store) is
--   the shop's mistake: nothing is taken, the player reads "That is not for sale yet." and the server's log
--   gets a "Wallet" warning that names the id and where it was called from. Look for "Wallet" warnings after
--   wiring a new counter. (The pass is not sold this way: wallet.pass.buy, below.)
--   If handing the thing over can fail or has to wait (a Tool to clone, a dish served later), pass it in as
--   the last argument, and END IT WITH `return true`: only true counts as handed over.
--     local ok, words = wallet.buy(player, "kite", function()
--         giveKite(player)
--         return true               -- false (or false, "The shelf is empty."), nothing, or an error: the
--     end)                          --   money comes back, and nothing or an error is warned in the log
--   While a purchase's handing-over is waiting, every other spend by that player is refused with "One moment:
--   still serving you." and takes nothing, so a second press can never charge twice; even so, a shop's
--   prompt should ignore its own presses while a purchase is in progress (a busy flag per player).
--   wallet.spend(player, cents, why, deliver?) is the same thing for an amount that is not on the list (a
--   game's stake: ctx.town.charge is spend); `why` names the thing in a few lower-case words ("a kite").
--   To show a price before the press: wallet.can(player, cents) -> ok, words; wallet.balance(player) -> cents.
--   To pay someone (wages, a tip, a prize that is NOT a stake): wallet.add(player, 5, "mowing a lawn").
--
-- HOW A DOOR CHECKS A PASS (the paintball arena and both lounges read the same one):
--     if wallet.pass.has(player) then
--         letIn(player)             -- wallet.pass.words(player): "4.2 in-game days left (about 50 minutes)"
--     else
--         local _cents, _days, offer = wallet.pass.offer()
--         wallet.tell(player, "Members only. " .. offer)   -- "... A pass is 20c for five in-game days of
--     end                                                  --      paintball and both lounges."
--   and where the pass is sold (the desk, a lounge door's prompt):
--     local ok, words = wallet.pass.buy(player)   -- (true, "Pass bought: five days of paintball and both
--         -- lounges.") or (false, "You need 20c; you have 7c.") or (false, "You already have a pass.")
--   In a pass's last in-game day buy() renews it: the five new days go on the end of the old ones (true,
--   "Pass renewed: five more days of paintball and both lounges."), so nobody has to be turned away first.
--   Never write the price or the length into a sentence of your own: wallet.pass.offer() -> cents, days,
--   words reads the same two tunables that buy() charges by, so a changed price changes every door at once.
--   wallet.pass is { has, buy, untilDay } as the paintball server's PassDesk type wants it, plus left(player)
--   -> in-game days, words(player) and offer(). A minigame finds the very same table at ctx.town.pass: a game
--   that sells or checks the pass (paintball's desk) must use that and never keep a ledger of its own, or a
--   pass bought at its desk would not open the lounges.
--
-- What a player sees (Client/UI/WalletHud draws it; nothing else needs to): the player attributes Cents (the
-- balance, written the moment it changes), CentsNote (the last change as "seq|delta|why", written just before
-- Cents: seq counts the account's changes, so a screen that was shown only the last of several can tell),
-- PocketMoney (cents of pocket money given at this join, nil when none) and PassUntil (the game second the
-- pass runs out, nil without one). Only this module writes them.
-- Pocket money: a player is given Tunables economy.pocketMoneyCents (300: S$3.00) ONCE for as long as this
-- server runs, on first joining, so that there is something to spend before jobs pay. Coming back gives
-- nothing more. Set the tunable to 0 to switch it off. It is a hand-out: it does not count toward the human
-- queue (counted(player) is what Roles reads), and it is what a shop takes first.
-- NOT SAVED: an account lasts as long as this server does, by UserId (leaving and coming back finds it as it
-- was; a new server starts everyone afresh). The data is ready for a profile: wallet.export(player) is
-- everything an account holds as plain data and wallet.import(player, saved) puts it back. In the game the
-- join comes FIRST (Roles asks for the purse at PlayerAdded, with pocket money) and a profile can only load
-- after it, so import takes an account that has had nothing but this server's pocket money and makes it the
-- saved one; once the player has bought or been paid anything here, the account here wins and import is
-- refused. Shared/Economy/Bank's header has the whole of it, and how it fits Persistence/ProfileSchema.
-- No real money anywhere here: nothing in this module touches Robux or a developer product.
-- Roles: Roles/RoleService's member purse is wallet.purse(player), a narrow face on this wallet ({ cents,
-- counted, history } to read; credit(cents, why) and debit(cents, why) to change, both logged and shown like
-- any other change; writing a field is an error). Asking for it opens nothing: Boot/Game joins the player
-- first. Ladder pay lands here, and the human queue's money term reads `counted`.
-- Pure Luau over its deps (a player is a Player or a PlayerLike stub with a UserId); no side effects on
-- require.
-- Interface: new(deps?) -> Wallet { join(player) -> cents of pocket money given, leave(player),
--   balance(player) -> cents, counted(player) -> cents that count toward the queue, can(player, cents) ->
--   (ok, words), buy(player, id | { id }, deliver?) -> (ok, words), spend(player, cents, why, deliver?) ->
--   (ok, words), add(player, cents, why) -> (ok, words),
--   tell(player, words), purse(player) -> Purse (a face; joins nobody), pass { has, buy, left, untilDay,
--   words, offer }, log() -> the last changes of every account, export(player) -> Bank.Saved?,
--   import(player, saved) -> (ok, why?), bank (the Bank itself) }; note(seq, delta, why) -> the CentsNote
--   text; PASS; types Deps, Wallet, Pass, Purse

local Import = require("../Import")
local Bank = Import.shared("Economy/Bank") :: typeof(require("../../shared/Economy/Bank"))
local EconomyRules = Import.shared("Economy/EconomyRules") :: typeof(require("../../shared/Economy/EconomyRules"))
local Tunables = Import.shared("Config/Tunables") :: typeof(require("../../shared/Config/Tunables"))
local Log = Import.shared("Util/Log") :: typeof(require("../../shared/Util/Log"))

local Credits = {}

Credits.PASS = EconomyRules.PASS -- the one pass on sale ("paintball"): the arena and both lounges

-- (Exported types do not cross the Import shim (rule 1): the Bank's shapes are restated loosely.)
type Entry = { id: any, delta: number, why: string, balance: number, at: number, seq: number }
export type Purse = {
	cents: number, -- read only: the balance now
	counted: number?, -- read only: the cents that count toward the human queue (the balance less unspent pocket money)
	history: { any }, -- read only: the account's last changes
	credit: (any, number, string) -> (boolean, string?),
	debit: (any, number, string) -> (boolean, string?),
}

export type Deps = {
	gameSeconds: (() -> number)?, -- the game clock (Time/Clock:gameSeconds); default: seconds since new()
	daySeconds: number?, -- game seconds in an in-game day (default Tunables clock.realSecondsPerDay)
	pocket: (() -> number)?, -- pocket money in cents (default EconomyRules.pocketMoney: the tunable)
	setAttr: ((player: any, name: string, value: any) -> ())?, -- default: the Player's attribute (a stub's attrs)
	log: ((line: string) -> ())?, -- one line per change (default: the server's output, tag Wallet)
	-- a caller's mistake, loudly (default: a warning in the server's output, tag Wallet, with where it came from)
	warn: ((line: string) -> ())?,
	-- put words on a player's screen (Boot/Game: its "notice" toast; default: a PlayerLike stub's events list)
	tell: ((player: any, words: string) -> ())?,
	wall: (() -> number)?, -- real seconds, for what would be saved (default os.time)
}

export type Pass = {
	has: (player: any) -> boolean,
	buy: (player: any) -> (boolean, string),
	left: (player: any) -> number, -- in-game days (a fraction counts; 0 without one)
	untilDay: (player: any) -> number?, -- the in-game day it runs out (nil: never bought one)
	words: (player: any) -> string, -- "4.2 in-game days left (about 50 minutes)" or "No pass"
	-- what is on sale: cents, in-game days, and the sentence ("A pass is 20c for five in-game days of ...")
	offer: () -> (number, number, string),
}

export type Wallet = {
	join: (player: any) -> number,
	leave: (player: any) -> (),
	balance: (player: any) -> number,
	counted: (player: any) -> number,
	can: (player: any, cents: number) -> (boolean, string),
	buy: (player: any, what: string | { string }, deliver: (() -> (boolean?, string?))?) -> (boolean, string),
	spend: (player: any, cents: number, why: string, deliver: (() -> (boolean?, string?))?) -> (boolean, string),
	add: (player: any, cents: number, why: string) -> (boolean, string),
	tell: (player: any, words: string) -> (), -- the words a spend, a refusal or a door has for a player, on their screen
	purse: (player: any) -> Purse,
	pass: Pass,
	log: () -> { Entry },
	export: (player: any) -> any,
	import: (player: any, saved: any) -> (boolean, string?),
	bank: any, -- Shared/Economy/Bank.Bank
}

-- The CentsNote attribute: the account's change count, the change, and its reason ("7|-12|coffee").
function Credits.note(seq: number, delta: number, why: string): string
	return `{seq}|{delta}|{why}`
end

-- An account is kept by UserId where there is one (a Player object is gone when its player leaves).
local function who(player: any): any
	if type(player) == "table" then
		return if player.UserId ~= nil then player.UserId else player
	end
	if typeof(player) == "Instance" and (player :: Instance):IsA("Player") then
		return (player :: Player).UserId
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

local function defaultTell(player: any, words: string)
	if type(player) == "table" and type(player.events) == "table" then
		table.insert(player.events, { kind = "notice", text = words }) -- what Boot/Game would send them
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
	local tell = d.tell or defaultTell
	local logger = Log.new("Wallet")
	local say = d.log or function(line: string)
		logger:info(line)
	end
	local shout = d.warn or function(line: string)
		logger:warn(line)
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
		wall = d.wall or os.time,
		changed = function(id: any, e: Entry)
			-- the note first: a client that sees the new balance finds the change and its reason beside it
			show(id, "CentsNote", Credits.note(e.seq, e.delta, e.why))
			show(id, "Cents", e.balance)
			say(`{tostring(id)} {if e.delta >= 0 then "+" else ""}{e.delta}c ({e.why}) -> {e.balance}c`)
		end,
		passed = function(id: any, name: string, untilSeconds: number)
			if name == Credits.PASS then
				show(id, "PassUntil", untilSeconds)
			end
			say(`{tostring(id)} holds the {name} pass until game second {math.floor(untilSeconds)}`)
		end,
		fault = function(what: string)
			-- a shop's mistake, not the player's: say it where whoever wired the shop will see it
			shout(`{what} {debug.traceback("", 2)}`)
		end,
	})

	-- What buy() sells: one id or a basket of them, as one price and the words for it; nil and the first id
	-- that is not on sale when one is not.
	local function basket(what: any): (number?, string?, string?)
		local ids: { any } = if type(what) == "table" then what else { what }
		if #ids == 0 then
			return nil, nil, "an empty basket"
		end
		local total, names = 0, {}
		for _, id in ids do
			local item = if type(id) == "string" then EconomyRules.item(id) else nil
			if item == nil then
				local why = if id == "paintball_pass"
					then " (the pass is sold by wallet.pass.buy, which grants it)"
					else ""
				return nil, nil, `"{tostring(id)}"{why}`
			end
			total += item.cents
			table.insert(names, item.name)
		end
		local words = if #names == 1
			then names[1]
			elseif #names <= 3 then `{table.concat(names, ", ", 1, #names - 1)} and {names[#names]}`
			else `{#names} things`
		return total, words, nil
	end

	local function buy(player: any, what: any, deliver: (() -> (boolean?, string?))?): (boolean, string)
		local cents, why, missing = basket(what)
		if cents == nil or why == nil then
			bank.mistakes += 1
			shout(
				`no price or no name for {missing or "?"}: nothing was taken and the player was told "{Bank.WORDS.amount}" {debug.traceback(
					"",
					2
				)}`
			)
			return false, Bank.WORDS.amount
		end
		return bank:spend(who(player), cents, why, deliver)
	end

	local function join(player: any): number
		local id = who(player)
		local was = here[id]
		here[id] = player
		local account, given = bank:join(id)
		if was ~= player or given > 0 then
			-- (a balance that did not change at this join is still new to this Player object)
			setAttr(player, "PocketMoney", if given > 0 then given else nil)
			if given == 0 then
				-- nothing changed, so nothing wrote the note: where the count stands, with no change to show
				setAttr(player, "CentsNote", Credits.note(account.seq, 0, ""))
			end
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
		offer = function(): (number, number, string)
			local spec = passSpec()
			return spec.cents, spec.days, spec.offer
		end,
	}

	-- Roles' purse: a face on one account. It reads the bank and changes it only through the bank (logged,
	-- shown, never below nothing); it opens no account and holds no money of its own.
	local faces: { [any]: Purse } = {}
	local function face(id: any): Purse
		local f: any = {}
		function f.credit(_self: any, cents: number, why: string): (boolean, string?)
			local ok, words = bank:add(id, cents, why)
			return ok, if ok then nil else words
		end
		function f.debit(_self: any, cents: number, why: string): (boolean, string?)
			local ok, words = bank:take(id, cents, why)
			return ok, if ok then nil else words
		end
		return setmetatable(f, {
			__index = function(_t: any, key: any): any
				if key == "cents" then
					return bank:balance(id)
				elseif key == "counted" then
					return bank:counted(id)
				elseif key == "history" then
					local purse = bank:purse(id)
					return if purse then purse.history else {}
				end
				return nil
			end,
			__newindex = function(_t: any, key: any)
				error(`the wallet's purse cannot be written ({tostring(key)}): use credit and debit`, 2)
			end,
		}) :: any
	end

	return {
		join = join,
		leave = leave,
		balance = function(player: any): number
			return bank:balance(who(player))
		end,
		counted = function(player: any): number
			return bank:counted(who(player))
		end,
		can = function(player: any, cents: number): (boolean, string)
			return bank:can(who(player), cents)
		end,
		buy = buy,
		spend = function(
			player: any,
			cents: number,
			why: string,
			deliver: (() -> (boolean?, string?))?
		): (boolean, string)
			return bank:spend(who(player), cents, why, deliver)
		end,
		add = function(player: any, cents: number, why: string): (boolean, string)
			return bank:add(who(player), cents, why)
		end,
		tell = function(player: any, words: string)
			if type(words) == "string" and words ~= "" then
				tell(player, words)
			end
		end,
		purse = function(player: any): Purse
			local id = who(player)
			local f = faces[id]
			if f == nil then
				f = face(id)
				faces[id] = f
			end
			return f
		end,
		pass = pass,
		log = function(): { Entry }
			return bank.entries
		end,
		export = function(player: any): any
			return bank:export(who(player))
		end,
		import = function(player: any, saved: any): (boolean, string?)
			return bank:import(who(player), saved)
		end,
		bank = bank,
	}
end

return Credits
