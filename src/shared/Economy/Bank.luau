--!strict
-- ReplicatedStorage.Shared.Economy.Bank
-- The town's money, pure (brief v2 §13a: Spicy Dollars in whole cents; BUILD_PLAN D26). One Account per
-- player, kept for as long as the server runs: a purse (Economy/Wallet: the balance and its last changes) and
-- the timed passes the player holds. Server/Economy/Credits is the one module the game's features call; this
-- is what it decides with, and what the specs drive without an engine.
-- The rules, all of them:
--   * Money is whole cents and a balance is never negative: a spend larger than the balance is refused with
--     words and changes nothing.
--   * A spend is one step with no wait in it, so two spends racing for the same money cannot both win: the
--     second finds what the first left. A shop that must hand something over (and may have to wait to do it)
--     passes `deliver`: the money is taken first, so nothing else can spend it meanwhile, and comes straight
--     back if the handing-over throws or returns false.
--   * Every change is logged with its reason: in the account's purse (the last Wallet.HISTORY), in the bank's
--     own list (the last Bank.LOG, every account) and to opts.changed, at the moment it happens. Each entry
--     carries the account's own count of changes (`seq`: 1, 2, 3 ...), so a screen that was shown only the
--     last of several can tell that it missed some.
--   * A price that is not whole cents, or a reason that is missing, is the caller's mistake, never the
--     player's: nothing is taken, the player reads "That is not for sale yet." (WORDS.amount) and opts.fault
--     hears what was wrong, so the server can say so loudly in its own log.
--   * Pocket money: an account is given the pocket amount ONCE for as long as this server runs. join() gives
--     whatever of it the account has not had yet: all of it the first time, nothing on coming back, the
--     difference if the amount has since been raised. Leaving and coming back is never a way to more.
--   * Pocket money is a hand-out, not earnings: counted(id) is the balance less the pocket money still unspent,
--     which is what the human queue's money term reads (brief v2 §13a, "money's main use is buying your place
--     in the human queue", was written of money earned or bought). A spend takes the hand-out first, so
--     shopping with pocket money costs no rank; take() (a fine, the Role Lab) takes earnings first.
--   * leave() closes the account: nothing can be spent from it, but it is kept (a refund or pay still owed
--     lands in it, a pass keeps running) and join() opens it again as it was.
--   * A pass is bought once and lasts spec.days in-game days from the moment of buying, on the game clock
--     (opts.now, game seconds; a day is opts.daySeconds of them), whether its holder is in the game or away. A
--     holder is never sold a second one.
-- Words: every refusal comes back as a sentence a player can be shown as it is (Bank.WORDS, short()). An
-- amount is written as the shops write it under a dollar ("12c") and as the corner of the screen writes it
-- from a dollar up ("S$2.40"): amount(cents).
-- `why` is a few words naming the thing, lower case, no full stop ("coffee", "a paintball pass", "mowing a
-- lawn"): it is logged as given and set into the words ("Paid 12c for coffee. You have S$2.88.").
-- Saving (NOT wired: profiles are not live): export(id) gives everything an account holds as plain numbers and
-- strings ({ v, cents, pocket, pocketLeft, passes = { name = game seconds LEFT }, at = opts.wall() }: the game
-- clock starts again with every server, so a pass is kept as time left, never as a clock reading; `at` is the
-- real time of saving, and import takes the real seconds since off every pass, so a pass runs down while its
-- holder is away between servers as it does on one). import(id, saved) puts it back. In the game a player's
-- account is opened, with pocket money, the moment they arrive (Roles/RoleService asks for the purse at
-- PlayerAdded), which is BEFORE any profile can have loaded; so import also takes an account that exists but
-- has had nothing happen to it except this server's pocket money: the balance becomes the saved one (logged,
-- reason SAVED_WHY), and pocket money is then owed only as far as the saved account never had it. An account
-- that has been used here (anything bought or paid, a pass) is newer than the saved one and is left alone.
-- `cents` is Persistence/ProfileSchema's wallet.cents; `pocket`, `pocketLeft`, `passes` and `at` would be new
-- fields there (a schema version of their own).
-- Interface: new(opts) -> Bank; Bank:join(id) -> (Account, cents given), leave(id), has(id), balance(id),
--   counted(id) -> cents that count toward the queue, can(id, cents) -> (ok, words), spend(id, cents, why,
--   deliver?) -> (ok, words), add(id, cents, why) -> (ok, words), take(id, cents, why) -> (ok, words),
--   purse(id) -> Wallet.Purse? (the bank's own: never handed to a feature), buyPass(id, spec) -> (ok, words),
--   hasPass(id, name), passUntil(id, name) -> game seconds?, passLeft(id, name) -> in-game days (0 without
--   one), export(id) -> Saved?, import(id, saved) -> (ok, why?); Bank.entries (the log), Bank.faults,
--   Bank.mistakes; WORDS, short(need, have), amount(cents) -> "12c" | "S$2.40", price (the same), LOG,
--   SAVED_VERSION, POCKET_WHY, SAVED_WHY; types Account, Entry, PassSpec, Saved, Options

local Wallet = require("./Wallet")

local Bank = {}

Bank.LOG = 200 -- entries the bank keeps, every account together
Bank.SAVED_VERSION = 1
Bank.POCKET_WHY = "pocket money"
Bank.SAVED_WHY = "your saved wallet"

Bank.WORDS = table.freeze({
	none = "You have no wallet yet.",
	gone = "You have left the game.",
	amount = "That is not for sale yet.", -- a price or a reason the caller got wrong: a server fault, said kindly
	pay = "That could not be paid.", -- the same for add() and take()
	full = "Your wallet is full.",
})

export type Entry = { id: any, delta: number, why: string, balance: number, at: number, seq: number }
export type PassSpec = {
	name: string, -- which pass ("paintball": the arena and both lounges read the same one)
	cents: number,
	days: number, -- in-game days
	why: string, -- "a paintball pass"
	bought: string, -- the words on buying
	has: string, -- the words for a holder who asks again
	offer: string, -- what it is and what it costs ("A pass is 20c for five in-game days of ...")
}
export type Saved = {
	v: number,
	cents: number,
	pocket: number,
	pocketLeft: number,
	passes: { [string]: number }, -- game seconds left
	at: number?, -- the real time of saving (opts.wall), when there is one
}
export type Account = {
	id: any,
	purse: Wallet.Purse,
	passes: { [string]: number }, -- pass name -> the game second it runs out
	pocket: number, -- pocket money given to this account so far
	pocketLeft: number, -- how much of it is still unspent (never more than the balance)
	seq: number, -- how many changes this account has had
	fresh: boolean, -- nothing has happened to it yet but pocket money (import may still replace it)
	held: number, -- cents taken by spends whose handing-over has not finished (theirs again if it fails)
	open: boolean, -- false once the player has left: nothing can be spent
}
export type Options = {
	now: () -> number, -- game seconds (Time/Clock:gameSeconds)
	daySeconds: number, -- game seconds in an in-game day
	pocket: (number | (() -> number))?, -- pocket money in cents (default 0: none)
	changed: ((id: any, entry: Entry) -> ())?, -- every change to any account, as it happens
	passed: ((id: any, name: string, untilSeconds: number) -> ())?, -- a pass was bought (or brought back by import)
	fault: ((what: string) -> ())?, -- a caller's mistake (a price that is not cents, no reason): for the server's log
	wall: (() -> number)?, -- real seconds (os.time): stamps export, so import can run a saved pass down
}
export type Deliver = () -> (boolean?, string?)
export type Bank = {
	opts: Options,
	accounts: { [any]: Account },
	entries: { Entry },
	faults: number, -- how often opts.changed, opts.passed or opts.fault threw (the change itself always stands)
	mistakes: number, -- how often a caller handed in a price or a reason that could not be used
	join: (self: Bank, id: any) -> (Account, number),
	leave: (self: Bank, id: any) -> (),
	has: (self: Bank, id: any) -> boolean,
	balance: (self: Bank, id: any) -> number,
	counted: (self: Bank, id: any) -> number,
	can: (self: Bank, id: any, cents: number) -> (boolean, string),
	spend: (self: Bank, id: any, cents: number, why: string, deliver: Deliver?) -> (boolean, string),
	add: (self: Bank, id: any, cents: number, why: string) -> (boolean, string),
	take: (self: Bank, id: any, cents: number, why: string) -> (boolean, string),
	purse: (self: Bank, id: any) -> Wallet.Purse?,
	buyPass: (self: Bank, id: any, spec: PassSpec) -> (boolean, string),
	hasPass: (self: Bank, id: any, name: string) -> boolean,
	passUntil: (self: Bank, id: any, name: string) -> number?,
	passLeft: (self: Bank, id: any, name: string) -> number,
	export: (self: Bank, id: any) -> Saved?,
	import: (self: Bank, id: any, saved: any) -> (boolean, string?),
}

-- An amount as a player reads it: as the shops write it under a dollar ("12c"), as the corner of the screen
-- writes it from a dollar up ("S$2.40").
function Bank.amount(cents: number): string
	return if cents < 100 then `{cents}c` else Wallet.format(cents)
end
Bank.price = Bank.amount

-- What someone short of money reads: "You need 12c; you have 7c." / "You need S$2.40; you have S$2.33."
function Bank.short(need: number, have: number): string
	return `You need {Bank.amount(need)}; you have {Bank.amount(have)}.`
end

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- A reason that can be logged and shown: a string with something in it.
local function named(why: any): boolean
	return type(why) == "string" and string.match(why, "%S") ~= nil
end

function Bank.new(opts: Options): Bank
	assert(finite(opts.daySeconds) and opts.daySeconds > 0, "Bank.new: daySeconds must be a positive number")
	local bank = { opts = opts, accounts = {}, entries = {}, faults = 0, mistakes = 0 } :: Bank

	local function tell(fn: any, ...: any)
		if fn then
			local ok = pcall(fn, ...)
			if not ok then
				bank.faults += 1
			end
		end
	end

	-- a caller's mistake: counted, and said to whoever keeps the server's log
	local function mistake(what: string)
		bank.mistakes += 1
		tell(opts.fault, what)
	end

	local function open(id: any, cents: number): Account
		local account: Account
		local purse = Wallet.purse(cents, function(e: Wallet.Entry)
			account.seq += 1
			if e.why ~= Bank.POCKET_WHY then
				account.fresh = false
			end
			-- (the hand-out still unspent is never more than there is)
			account.pocketLeft = math.min(account.pocketLeft, e.balance)
			local entry: Entry =
				{ id = id, delta = e.delta, why = e.why, balance = e.balance, at = opts.now(), seq = account.seq }
			table.insert(bank.entries, entry)
			if #bank.entries > Bank.LOG then
				table.remove(bank.entries, 1)
			end
			tell(opts.changed, id, entry)
		end)
		account = {
			id = id,
			purse = purse,
			passes = {},
			pocket = 0,
			pocketLeft = 0,
			seq = 0,
			fresh = true,
			held = 0,
			open = false,
		}
		bank.accounts[id] = account
		return account
	end

	local function pocketNow(): number
		local p = opts.pocket
		local v = if type(p) == "function" then p() else p
		return if Wallet.isCents(v) then v :: number else 0
	end

	-- Whatever of the pocket amount this account has not had yet (once for the server's life: the header).
	local function pocketMoney(a: Account): number
		local give = pocketNow() - a.pocket
		if give > 0 then
			-- (counted before the credit, so that the change is reported with the hand-out already known)
			a.pocket += give
			a.pocketLeft += give
			if a.purse:credit(give, Bank.POCKET_WHY) then
				return give
			end
			a.pocket -= give
			a.pocketLeft = math.min(a.pocketLeft - give, a.purse.cents)
		end
		return 0
	end

	function bank.join(self: Bank, id: any): (Account, number)
		local a = self.accounts[id] or open(id, 0)
		if a.open then
			return a, 0
		end
		a.open = true
		return a, pocketMoney(a)
	end

	function bank.leave(self: Bank, id: any)
		local a = self.accounts[id]
		if a then
			a.open = false
		end
	end

	function bank.has(self: Bank, id: any): boolean
		local a = self.accounts[id]
		return a ~= nil and a.open
	end

	function bank.balance(self: Bank, id: any): number
		local a = self.accounts[id]
		return if a then a.purse.cents else 0
	end

	-- The cents that count toward the human queue: the balance less the pocket money still unspent.
	function bank.counted(self: Bank, id: any): number
		local a = self.accounts[id]
		return if a then math.max(0, a.purse.cents - a.pocketLeft) else 0
	end

	function bank.purse(self: Bank, id: any): Wallet.Purse?
		local a = self.accounts[id]
		return if a then a.purse else nil
	end

	-- Could `id` pay `cents` now? (true, "") or (false, the words). Nothing changes.
	function bank.can(self: Bank, id: any, cents: number): (boolean, string)
		if not Wallet.isCents(cents) then
			mistake(`a price of {tostring(cents)} is not whole cents`)
			return false, Bank.WORDS.amount
		end
		local a = self.accounts[id]
		if a == nil then
			return false, Bank.WORDS.none
		end
		if not a.open then
			return false, Bank.WORDS.gone
		end
		if cents > a.purse.cents then
			return false, Bank.short(cents, a.purse.cents)
		end
		return true, ""
	end

	function bank.spend(self: Bank, id: any, cents: number, why: string, deliver: Deliver?): (boolean, string)
		if not named(why) then
			mistake(`a spend of {tostring(cents)} came with no reason`)
			return false, Bank.WORDS.amount
		end
		local ok, words = self:can(id, cents)
		if not ok then
			return false, words
		end
		local a = self.accounts[id]
		-- (the hand-out goes first: shopping with pocket money takes nothing that counts toward the queue)
		local fromPocket = math.min(a.pocketLeft, cents)
		if cents > 0 then
			a.pocketLeft -= fromPocket
			a.purse:debit(cents, why)
		end
		if deliver then
			-- (the money is already out of reach of any other spend while this runs, however long it waits)
			a.held += cents
			local ran, got, said = pcall(deliver)
			a.held -= cents
			if not ran or got == false then
				if cents > 0 then
					a.pocketLeft += fromPocket
					a.purse:credit(cents, `refund: {why}`)
				end
				if ran and type(said) == "string" and said ~= "" then
					return false, said
				end
				return false, `That did not work, so you were not charged for {why}.`
			end
		end
		if cents == 0 then
			return true, `Nothing to pay for {why}.`
		end
		return true, `Paid {Bank.amount(cents)} for {why}. You have {Wallet.format(a.purse.cents)}.`
	end

	-- Pay `id` (wages, a tip, a refund). A closed account still takes it: money owed is never lost.
	function bank.add(self: Bank, id: any, cents: number, why: string): (boolean, string)
		if not Wallet.isCents(cents) or not named(why) then
			mistake(`pay of {tostring(cents)} for {tostring(why)} is not whole cents with a reason`)
			return false, Bank.WORDS.pay
		end
		local a = self.accounts[id]
		if a == nil then
			return false, Bank.WORDS.none
		end
		if cents > 0 and not a.purse:credit(cents, why) then
			return false, Bank.WORDS.full
		end
		return true, `+{Bank.amount(cents)}: {why}. You have {Wallet.format(a.purse.cents)}.`
	end

	-- Take money that is not a purchase (a fine, the Role Lab): earnings first, the hand-out last. A closed
	-- account can still be taken from; never below nothing.
	function bank.take(self: Bank, id: any, cents: number, why: string): (boolean, string)
		if not Wallet.isCents(cents) or not named(why) then
			mistake(`a taking of {tostring(cents)} for {tostring(why)} is not whole cents with a reason`)
			return false, Bank.WORDS.pay
		end
		local a = self.accounts[id]
		if a == nil then
			return false, Bank.WORDS.none
		end
		if cents > a.purse.cents then
			return false, Bank.short(cents, a.purse.cents)
		end
		if cents > 0 then
			a.purse:debit(cents, why) -- (the purse's watcher keeps the hand-out no larger than what is left)
		end
		return true, `-{Bank.amount(cents)}: {why}. You have {Wallet.format(a.purse.cents)}.`
	end

	function bank.passUntil(self: Bank, id: any, name: string): number?
		local a = self.accounts[id]
		return if a then a.passes[name] else nil
	end

	function bank.hasPass(self: Bank, id: any, name: string): boolean
		local e = self:passUntil(id, name)
		return e ~= nil and opts.now() < e
	end

	function bank.passLeft(self: Bank, id: any, name: string): number
		local e = self:passUntil(id, name)
		return if e then math.max(0, e - opts.now()) / opts.daySeconds else 0
	end

	function bank.buyPass(self: Bank, id: any, spec: PassSpec): (boolean, string)
		if self:hasPass(id, spec.name) then
			return false, spec.has
		end
		local ok, words = self:spend(id, spec.cents, spec.why)
		if not ok then
			return false, words
		end
		local a = self.accounts[id]
		local untilSeconds = opts.now() + spec.days * opts.daySeconds
		a.passes[spec.name] = untilSeconds
		a.fresh = false
		tell(opts.passed, id, spec.name, untilSeconds)
		return true, spec.bought
	end

	function bank.export(self: Bank, id: any): Saved?
		local a = self.accounts[id]
		if a == nil then
			return nil
		end
		local passes: { [string]: number } = {}
		local now = opts.now()
		for name, untilSeconds in a.passes do
			if untilSeconds > now then
				passes[name] = untilSeconds - now
			end
		end
		return {
			v = Bank.SAVED_VERSION,
			cents = a.purse.cents,
			pocket = a.pocket,
			pocketLeft = a.pocketLeft,
			passes = passes,
			at = if opts.wall then opts.wall() else nil,
		}
	end

	-- Put a saved account back: before the player's join, or after it while nothing has happened to the
	-- account here but this server's pocket money (the header says why). An account that has been used here is
	-- newer than anything saved and is left alone. A record that is not sound changes nothing.
	function bank.import(self: Bank, id: any, saved: any): (boolean, string?)
		local had = self.accounts[id]
		if had ~= nil and not had.fresh then
			return false, "this account has already been used here"
		end
		if type(saved) ~= "table" or saved.v ~= Bank.SAVED_VERSION then
			return false, "not a saved account of this version"
		end
		if
			not Wallet.isCents(saved.cents)
			or not Wallet.isCents(saved.pocket)
			or not Wallet.isCents(saved.pocketLeft)
			or type(saved.passes) ~= "table"
		then
			return false, "a saved amount is not whole cents"
		end
		if saved.at ~= nil and not finite(saved.at) then
			return false, "a saved time is not a time"
		end
		for name, left in saved.passes do
			if type(name) ~= "string" or not finite(left) or left < 0 then
				return false, "a saved pass is not a time left"
			end
		end
		local a: Account
		if had == nil then
			a = open(id, saved.cents)
		else
			-- this server's pocket money goes back and the saved balance takes its place, logged like any change
			a = had
			a.pocketLeft = 0
			local delta = saved.cents - a.purse.cents
			if delta > 0 then
				a.purse:credit(delta, Bank.SAVED_WHY)
			elseif delta < 0 then
				a.purse:debit(-delta, Bank.SAVED_WHY)
			end
		end
		a.fresh = false
		a.pocket = saved.pocket
		a.pocketLeft = math.min(saved.pocketLeft, saved.pocket, a.purse.cents)
		-- a pass runs down while its holder is away: the real seconds since the saving come off it
		local away = 0
		if opts.wall and saved.at ~= nil then
			away = math.max(0, opts.wall() - saved.at)
		end
		local now = opts.now()
		for name, left in saved.passes do
			if left - away > 0 then
				a.passes[name] = now + left - away
				tell(opts.passed, id, name, now + left - away)
			end
		end
		if a.open then
			pocketMoney(a) -- (only what the saved account never had)
		end
		return true
	end

	return bank
end

return Bank
