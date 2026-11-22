--!strict
-- ServerScriptService.Server.Economy.StockOptions
-- SPICY STOCK OPTIONS (owner D30, 2026-11-22): "purchasing spicy bucks ... will be spicy stock options, and those will
-- equate to 1 spicy buck, when taken out, players can access their computers at home, to withdraw 100 spicy bucks per
-- server experience maximum from their purchased total". This handles real money: it is exact and conservative.
--
-- BUYING. The owner's developer product (Shared/Economy/Products.SPICY_BUCK_ID, a rate tier: 4 S$ per Robux, owner
-- D15 #3) sells options: each Robux its receipt says was spent buys PER_ROBUX options (1 option = S$1.00). Only the
-- server grants, only from MarketplaceService.ProcessReceipt (processReceipt here, Economy/Receipts underneath):
--   * the grant is written into the player's session-locked profile (Persistence/PlayerSaves: the clothing's, never a
--     second lock) and recorded in its receipt ledger by PurchaseId in the same step (ReceiptLedger.grantOptions);
--   * the profile is saved (PlayerSaves.saveNow) BEFORE PurchaseGranted is answered;
--   * NotProcessedYet on any doubt: the switch is off (Flags "stockOptions"), the product or the amount is unknown, the
--     player is not here, their profile is not loaded (waited for up to RECEIPT_WAIT seconds while the player is here
--     and it is on its way: not joined yet, loading, or a failed load about to be tried again), the save failed, or
--     this is a Studio session (test purchases cost nothing; Flags "stockOptionsStudio" lets a developer test the
--     grant on purpose). Roblox offers the receipt again later (their next join or purchase), and the ledger, which
--     travels with the profile, makes a second offer on this or any other server grant nothing twice. Once the grant
--     is saved the answer is PurchaseGranted, whatever the thank-you on the screen does after it.
-- promptBuy(player) opens Roblox's purchase window (MarketplaceService:PromptProductPurchase) from the server: the
-- menu's "Stock options" screen and a bank's counter (D30 H3) call it. It is refused with words while the switch is
-- off or the player's profile is not loaded (a purchase then could not be saved).
--
-- WITHDRAWING. At their own home computer (Shared/World/PlayerHomes: E on the desk's screen) a person sees their saved
-- options and takes out up to CAP options (S$100) on each server, in total: the count is kept by this server for as
-- long as it runs (leaving and coming back does not reset it) and is never saved. One withdrawal per WITHDRAW_GAP
-- seconds per player, and none while the server's save budget is spent ("the bank is busy"). A withdrawal is
-- two-phase in the profile:
--   1. the options move from `held` to a PENDING entry (options.pending[id] = n, id unique to this server) and the
--      profile is SAVED (saveNow); nothing is paid before that write is known to have landed;
--   2. landed: the money goes into the per-server wallet (Economy/Credits.add, reason WHY) and the entry moves to
--      `withdrawn` (written by the next save). Not landed (refused, failed, the lock lost): the entry goes back to
--      `held` in memory, and is saved that way. The save is slow (saveNow's "slow": the write may still land): the
--      player is told so, stays busy, and the withdrawal is settled when the write is done (landed and the player
--      still here on that profile: paid; otherwise back to `held`). A wallet that refuses puts the options back.
--   A pending entry found when a profile LOADS was left by a session that ended before it was settled (a crash, or
--   every later save failing). If this server paid it (a same-server rejoin), it is settled as withdrawn; else it
--   goes back to `held` (loaded returns true, so it is saved). That is never a loss. It can repay at most that one
--   withdrawal (S$100 at most) when the paying server ended before saving the settled entry: those Spicy Dollars
--   were that server's spending money and went with it, and anything saved that was bought with them would have
--   been written in the same profile, with the settled entry.
-- Withdrawn Spicy Dollars are this server's spending money: they are not saved, and the screen says so before anyone
-- withdraws.
--
-- The client asks through one RemoteEvent (REMOTE: "open", "buy", "withdraw" with a whole amount): every request is
-- checked here (the verb, the amount, a gap of GAP seconds per player, one withdrawal at a time, a person's body at
-- their own home's computer); the server answers with a "view" (what the screen shows) and "said" (a sentence).
-- Interface: new(deps) -> Service { processReceipt(receiptInfo) -> Decision, promptBuy(player) -> (ok, words),
--   withdraw(player, amount) -> (ok, words), view(player, where) -> View, open(player, where), computer(player,
--   lotId), request(player, verb, arg), loaded(player, data), sweep(players), homes (PlayerHomes registry),
--   withdrawnHere(player) -> options, leave(player) (clears the player's request gaps and remembered receipts),
--   receipts (Economy/Receipts handler) }; loaded(player, data) -> boolean (true when a pending entry was settled);
--   start(opts) -> Service? (the engine: ProcessReceipt, the remote, the prompts on the four desks, the home sweep,
--   PlayerRemoving); CAP; PER_ROBUX; GAP; WITHDRAW_GAP; RECEIPT_WAIT; WHY; REMOTE; WORDS; ABOUT (the screen's plain
--   explanation)
-- Engine only inside start; no side effects on require.

local Import = require("../Import")
local Products = Import.shared("Economy/Products") :: typeof(require("../../shared/Economy/Products"))
local PlayerHomes = Import.shared("World/PlayerHomes") :: typeof(require("../../shared/World/PlayerHomes"))
local Flags = Import.shared("Config/Flags") :: typeof(require("../../shared/Config/Flags"))
local Receipts = require("./Receipts")
-- (exported type names do not cross Import: the same types, taken from values)
type Home = typeof(PlayerHomes.HOMES[1])
type Registry = typeof(PlayerHomes.new())
local ReceiptLedger = require("./ReceiptLedger")

local StockOptions = {}

StockOptions.CAP = 100 -- options (S$) a player may withdraw on one server, in total (owner D30)
StockOptions.PER_ROBUX = Products.PER_ROBUX // ReceiptLedger.OPTION_CENTS -- 4 options per Robux (owner D15 #3)
StockOptions.GAP = 0.5 -- seconds between one player's requests that count
StockOptions.BUY_GAP = 3 -- seconds between one player's purchase windows
StockOptions.WITHDRAW_GAP = 6 -- seconds between one player's withdrawals (PlayerSaves.WRITE_GAP: one write each)
-- seconds a receipt waits for the buyer's profile: past a load's worst case (four lock waits of 4 s while another
-- server releases, and a failed load's first retry at 15 s)
StockOptions.RECEIPT_WAIT = 30
StockOptions.WHY = "stock options" -- the wallet's reason for a withdrawal
StockOptions.REMOTE = "StockOptions" -- ReplicatedStorage.PlayNet.StockOptions
StockOptions.ATTRIBUTE = "StockOptions" -- the player attribute: options held (saved), nil until the profile loads

-- What the screen says about them, every time it opens (plain: no returns, no prizes, no real-world value).
StockOptions.ABOUT = table.freeze({
	"Spicy Stock Options are play money for this game only. They have no value outside the game: they cannot be cashed out, sold or traded.",
	"1 option = S$1 to spend in the game. You buy them with Robux, and they are saved with your profile.",
	"To spend them, withdraw them at the computer in your home: up to S$100 on each server you play on.",
	"Spicy Dollars you withdraw are spending money for that server: they are not saved when you leave, so take out only what you will use.",
})

StockOptions.WORDS = table.freeze({
	off = "Spicy Stock Options are closed for now. Nothing has been taken.",
	notLoaded = "Your saved options have not loaded yet. Try again in a moment.",
	notHuman = "Only a person can use a computer.",
	noBody = "Pick a person from the menu first (M).",
	noHome = "You get a home when you first walk the town as a person.",
	notHome = "This is not your computer. Your home is %s.",
	far = "Withdraw at the computer in your home: %s.",
	amount = "Choose how many options to withdraw.",
	capReached = "You have withdrawn S$100 on this server, the most there is. You can withdraw more on another server.",
	tooMany = "You can withdraw up to S$%d more on this server.",
	notEnough = "You have %d options saved.",
	slow = "Saving is slow right now. Your withdrawal finishes when it is saved: the money comes, or your options go back.",
	notSaved = "Saving did not work just now, so nothing was taken. Try again in a minute.",
	bankBusy = "The bank is busy, try again in a moment.",
	wait = "One withdrawal at a time: try again in a few seconds.",
	backSlow = "Your withdrawal could not be saved, so your %d options are back.",
	studio = "Test purchases in Studio add no options.",
	walletRefused = "Your wallet could not take it, so your options are back where they were.",
	busy = "One moment: still working on your last request.",
	done = "Withdrew %d options: S$%d is in your wallet for this server. %d options left.",
	thanks = "Thank you! %d Spicy Stock Options added: you have %d. Withdraw them at the computer in your home.",
	buyLoading = "Your saved options have not loaded yet, so buying waits a moment.",
	buyOpen = "The Roblox purchase window is open.",
})

export type View = {
	kind: "view",
	where: string, -- "menu" | "computer"
	enabled: boolean,
	loaded: boolean, -- the profile is held: `held` is the saved count
	held: number?,
	withdrawnHere: number,
	cap: number,
	capLeft: number,
	home: string?, -- lot id
	homeName: string?,
	price: number?, -- Robux for one purchase, when the product's price is known
	perRobux: number,
	about: { string },
}

export type Deps = {
	saves: any, -- Persistence/PlayerSaves: profileOf(userId), saveNow(player), status(player), dirty(player, purchase?)
	wallet: any, -- Economy/Credits: add(player, cents, why) -> (ok, words)
	tell: (player: any, words: string) -> (),
	send: ((player: any, payload: { [string]: any }) -> ())?, -- to the player's StockOptions screen
	setAttr: ((player: any, name: string, value: any) -> ())?,
	-- the player's body: its species ("human" for a person) and where it stands; nil without one
	bodyOf: (player: any) -> (string?, number?, number?, number?),
	playerById: (userId: number) -> any?, -- a player in this server
	prompt: ((player: any, productId: number) -> ())?, -- MarketplaceService:PromptProductPurchase
	price: (() -> number?)?, -- the product's Robux price, once known
	enabled: (() -> boolean)?, -- default Flags.enabled("stockOptions")
	studio: (() -> boolean)?, -- a Studio session (RunService:IsStudio()); default false
	jobId: string?, -- this server's id (game.JobId): withdrawal ids are "<jobId>:<n>"
	clock: (() -> number)?, -- seconds, for the request gaps (os.clock)
	now: (() -> number)?, -- wall seconds for the ledger (os.time)
	sleep: ((seconds: number) -> ())?, -- the receipt's wait for a loading profile (task.wait)
	warn: ((line: string) -> ())?,
}

export type Service = {
	deps: Deps,
	homes: Registry,
	receipts: Receipts.Handler,
	withdrawn: { [number]: number }, -- options withdrawn on this server, by UserId (never saved)
	busy: { [number]: boolean }, -- a withdrawal is being saved (cleared by that withdrawal, slow or not)
	last: { [string]: number },
	paid: { [number]: { [string]: boolean } }, -- withdrawal ids paid on this server, by UserId (at most CAP each)
	processReceipt: (receipt: any) -> Receipts.Decision,
	promptBuy: (player: any) -> (boolean, string),
	withdraw: (player: any, amount: any) -> (boolean, string),
	view: (player: any, where: string) -> View,
	open: (player: any, where: string) -> (),
	computer: (player: any, lotId: string) -> (),
	request: (player: any, verb: any, arg: any) -> (),
	loaded: (player: any, data: any) -> boolean,
	sweep: (players: { any }) -> (),
	withdrawnHere: (player: any) -> number,
	leave: (player: any) -> (),
	stop: (() -> ())?, -- (start's: the prompts, the remote's handler and the sweep go; receipts are no longer taken)
}

local function whole(v: any): boolean
	return type(v) == "number" and v == v and v >= 1 and math.floor(v) == v and v < math.huge
end

function StockOptions.new(deps: Deps): Service
	local enabled = deps.enabled or function(): boolean
		return Flags.enabled("stockOptions")
	end
	local clock = deps.clock or os.clock
	local studio = deps.studio or function(): boolean
		return false
	end
	local jobId = deps.jobId or "server"
	local serial = 0
	local sleep = deps.sleep or function(_s: number) end
	local shout = deps.warn or function(line: string)
		warn(line)
	end
	local homes = PlayerHomes.new()
	local withdrawn: { [number]: number } = {}
	local busy: { [number]: boolean } = {}
	local last: { [string]: number } = {}
	local paid: { [number]: { [string]: boolean } } = {}
	local lastWithdraw: { [number]: number } = {}

	local function uid(player: any): number
		return player.UserId :: number
	end

	local function say(player: any, ok: boolean, words: string): (boolean, string)
		deps.tell(player, words)
		if deps.send then
			deps.send(player, { kind = "said", ok = ok, text = words })
		end
		return ok, words
	end

	-- a player's requests of one sort count once per `gap` seconds
	local function tooSoon(player: any, what: string, gap: number): boolean
		local key = `{uid(player)}:{what}`
		local t = clock()
		local prev = last[key]
		if prev and t - prev < gap then
			return true
		end
		last[key] = t
		return false
	end

	local function heldOf(player: any): number?
		local p = deps.saves:profileOf(uid(player))
		return if p then p.data.options.held else nil
	end

	local function show(player: any)
		if deps.setAttr then
			deps.setAttr(player, StockOptions.ATTRIBUTE, heldOf(player))
		end
	end

	local handler = Receipts.new({
		profileOf = function(playerId: number): any
			return deps.saves:profileOf(playerId)
		end,
		catalog = Products.catalog({ Products.spicyBuck() }),
		now = deps.now or os.time,
		grant = ReceiptLedger.grantOptions,
		save = function(_profile: any, playerId: number): (boolean, string?)
			local player = deps.playerById(playerId)
			if player == nil then
				return false, "absent"
			end
			return deps.saves:saveNow(player, { receipt = true })
		end,
		enabled = enabled,
	})

	local self = {
		deps = deps,
		homes = homes,
		receipts = handler,
		withdrawn = withdrawn,
		busy = busy,
		last = last,
		paid = paid,
	} :: Service

	function self.withdrawnHere(player: any): number
		return withdrawn[uid(player)] or 0
	end

	function self.view(player: any, where: string): View
		local id = uid(player)
		local home = homes:of(id)
		local h = if home then PlayerHomes.lot(home) else nil
		local held = heldOf(player)
		local here = withdrawn[id] or 0
		return {
			kind = "view",
			where = where,
			enabled = enabled(),
			loaded = held ~= nil,
			held = held,
			withdrawnHere = here,
			cap = StockOptions.CAP,
			capLeft = math.max(0, StockOptions.CAP - here),
			home = home,
			homeName = if h then h.name else nil,
			price = if deps.price then deps.price() else nil,
			perRobux = StockOptions.PER_ROBUX,
			about = StockOptions.ABOUT,
		}
	end

	function self.open(player: any, where: string)
		if deps.send then
			deps.send(player, self.view(player, where) :: any)
		end
	end

	-- ProcessReceipt: everything that is not certain is NotProcessedYet
	function self.processReceipt(receipt: any): Receipts.Decision
		if type(receipt) ~= "table" or type(receipt.PlayerId) ~= "number" then
			return "NotProcessedYet"
		end
		local player = deps.playerById(receipt.PlayerId)
		if player == nil then
			return "NotProcessedYet"
		end
		if studio() and not Flags.enabled("stockOptionsStudio") then
			pcall(say, player, false, StockOptions.WORDS.studio)
			return "NotProcessedYet"
		end
		-- a purchase made while the profile is on its way waits for it: the player not joined to the saves yet, the
		-- load running (lock waits included), or a failed load that step() tries again
		local waited = 0
		while deps.saves:profileOf(receipt.PlayerId) == nil and waited < StockOptions.RECEIPT_WAIT do
			local state = deps.saves:status(player)
			if state ~= nil and state ~= "loading" and state ~= "unsaved" then
				break
			end
			sleep(0.5)
			waited += 0.5
			player = deps.playerById(receipt.PlayerId)
			if player == nil then
				return "NotProcessedYet"
			end
		end
		local before = heldOf(player)
		local decision = handler:process(receipt)
		if decision == "PurchaseGranted" then
			-- (saved: only the thank-you is left, and nothing it does changes the answer)
			local told, err = pcall(function()
				local after = heldOf(player)
				if before and after and after > before then
					say(player, true, string.format(StockOptions.WORDS.thanks, after - before, after))
					show(player)
					self.open(player, "menu")
				end
			end)
			if not told then
				shout(`[StockOptions] the thank-you for a saved purchase failed: {err}`)
			end
		end
		return decision :: Receipts.Decision
	end

	function self.promptBuy(player: any): (boolean, string)
		if not enabled() then
			return say(player, false, StockOptions.WORDS.off)
		end
		if tooSoon(player, "buy", StockOptions.BUY_GAP) then
			return false, StockOptions.WORDS.busy -- (not said: a held button would flood the screen)
		end
		if deps.saves:profileOf(uid(player)) == nil then
			return say(player, false, StockOptions.WORDS.buyLoading)
		end
		if deps.prompt == nil then
			return say(player, false, StockOptions.WORDS.off)
		end
		deps.prompt(player, Products.SPICY_BUCK_ID)
		return true, StockOptions.WORDS.buyOpen
	end

	-- a pending withdrawal goes back to `held` (not paid)
	local function putBack(profile: any, wid: string)
		local o = profile.data.options
		local n = o.pending and o.pending[wid]
		if n then
			o.pending[wid] = nil
			if next(o.pending) == nil then
				o.pending = nil
			end
			o.held += n
		end
	end

	-- a pending withdrawal whose write landed: counted against this server's cap, paid, and moved to `withdrawn`
	-- (saved by the next write); a wallet that refuses puts it back
	local function pay(player: any, profile: any, wid: string, n: number): (boolean, string)
		local W = StockOptions.WORDS
		local id = uid(player)
		local o = profile.data.options
		local here = withdrawn[id] or 0
		withdrawn[id] = here + n
		local addCalled, ok, words = pcall(deps.wallet.add, player, n * ReceiptLedger.OPTION_CENTS, StockOptions.WHY)
		if not addCalled then
			ok, words = false, tostring(ok)
		end
		if not ok then
			withdrawn[id] = here
			putBack(profile, wid)
			deps.saves:dirty(player, true)
			shout(`[StockOptions] {id}: the wallet refused {n} withdrawn options ({words}); given back`)
			show(player)
			return say(player, false, W.walletRefused)
		end
		local mine = paid[id] or {}
		mine[wid] = true
		paid[id] = mine
		if o.pending and o.pending[wid] then
			o.pending[wid] = nil
			if next(o.pending) == nil then
				o.pending = nil
			end
			o.withdrawn += n
		end
		deps.saves:dirty(player)
		show(player)
		local done, text = say(player, true, string.format(W.done, n, n, o.held))
		self.open(player, "computer")
		return done, text
	end

	function self.withdraw(player: any, amount: any): (boolean, string)
		local W = StockOptions.WORDS
		if not enabled() then
			return say(player, false, W.off)
		end
		local id = uid(player)
		if busy[id] then
			return say(player, false, W.busy)
		end
		local species, x, y, z = deps.bodyOf(player)
		if species == nil then
			return say(player, false, W.noBody)
		end
		if species ~= "human" then
			return say(player, false, W.notHuman)
		end
		local home = homes:of(id)
		if home == nil then
			return say(player, false, W.noHome)
		end
		local h = PlayerHomes.lot(home) :: Home
		if x == nil or y == nil or z == nil or not PlayerHomes.atComputer(home, x, y, z) then
			return say(player, false, string.format(W.far, h.name))
		end
		local profile = deps.saves:profileOf(id)
		if profile == nil then
			return say(player, false, W.notLoaded)
		end
		if not whole(amount) then
			return say(player, false, W.amount)
		end
		local n = amount :: number
		local here = withdrawn[id] or 0
		local left = StockOptions.CAP - here
		if left <= 0 then
			return say(player, false, W.capReached)
		end
		if n > left then
			return say(player, false, string.format(W.tooMany, left))
		end
		local o = profile.data.options
		if n > o.held then
			return say(player, false, string.format(W.notEnough, o.held))
		end
		local t = clock()
		local prev = lastWithdraw[id]
		if prev and t - prev < StockOptions.WITHDRAW_GAP then
			return say(player, false, W.wait)
		end
		lastWithdraw[id] = t
		busy[id] = true
		-- 1. off `held` onto a pending entry, and saved, before any money moves
		serial += 1
		local wid = `{jobId}:{serial}`
		o.held -= n
		local out = o.pending or {}
		out[wid] = n
		o.pending = out
		local gaveUp = false
		local called, saved, why = pcall(deps.saves.saveNow, deps.saves, player, {
			-- the write we stopped waiting for is done: settle it now (from the player's save queue)
			settle = function(landed: boolean, lateWhy: string?)
				if not gaveUp then
					return
				end
				busy[id] = nil
				if landed and deps.saves:profileOf(id) == profile then
					pay(player, profile, wid, n)
					return
				end
				putBack(profile, wid)
				deps.saves:dirty(player, true) -- (a player who left: their release writes it)
				shout(
					`[StockOptions] {id}: a slow withdrawal of {n} was not paid ({lateWhy or "they left"}); given back`
				)
				if deps.saves:profileOf(id) == profile then
					pcall(function()
						show(player)
						say(player, false, string.format(W.backSlow, n))
					end)
				end
			end,
		})
		if not called then
			why, saved = tostring(saved), false
		end
		if not saved and why == "slow" then
			-- the write may still land: nothing is paid or given back until it is done (busy until then)
			gaveUp = true
			shout(`[StockOptions] {id}: a withdrawal of {n} is waiting on a slow save`)
			return say(player, false, W.slow)
		end
		busy[id] = nil
		if not saved then
			putBack(profile, wid)
			deps.saves:dirty(player, true)
			shout(`[StockOptions] {id}: a withdrawal of {n} was not saved ({why}); nothing taken`)
			show(player)
			return say(player, false, if why == "budget" then W.bankBusy else W.notSaved)
		end
		-- 2. saved: paid into the per-server wallet
		return pay(player, profile, wid, n)
	end

	-- E on a home computer: the owner's screen, or whose home this is not
	function self.computer(player: any, lotId: string)
		if tooSoon(player, "computer", StockOptions.GAP) then
			return
		end
		local species = deps.bodyOf(player)
		if species == nil then
			say(player, false, StockOptions.WORDS.noBody)
			return
		end
		if species ~= "human" then
			say(player, false, StockOptions.WORDS.notHuman)
			return
		end
		local home = homes:of(uid(player))
		if home == nil then
			say(player, false, StockOptions.WORDS.noHome)
			return
		end
		if home ~= lotId then
			local h = PlayerHomes.lot(home) :: Home
			say(player, false, string.format(StockOptions.WORDS.notHome, h.name))
			return
		end
		self.open(player, "computer")
	end

	-- the remote: one verb, checked, at most once per GAP
	function self.request(player: any, verb: any, arg: any)
		if verb == "open" then
			if not tooSoon(player, "open", StockOptions.GAP) then
				self.open(player, "menu")
			end
		elseif verb == "buy" then
			self.promptBuy(player)
		elseif verb == "withdraw" then
			if not tooSoon(player, "withdraw", StockOptions.GAP) then
				self.withdraw(player, arg)
			end
		end
	end

	-- the profile arrived (PlayerSaves' loaded): a withdrawal left pending by a session that ended before settling it
	-- is settled (paid on this server: withdrawn; else back to held), and the screen's count; true when it changed
	function self.loaded(player: any, data: any): boolean
		local changed = false
		local o = type(data) == "table" and data.options or nil
		if o and o.pending then
			local mine = paid[uid(player)] or {}
			for wid, n in o.pending do
				if mine[wid] then
					o.withdrawn += n
				else
					o.held += n
					shout(`[StockOptions] {uid(player)}: an unsettled withdrawal of {n} ({wid}) is given back`)
				end
			end
			o.pending = nil
			changed = true
		end
		show(player)
		return changed
	end

	-- the player left: their request gaps and remembered receipts go (the per-server cap and the paid ids stay)
	function self.leave(player: any)
		local id = uid(player)
		local prefix = `{id}:`
		for key in last do
			if string.sub(key, 1, #prefix) == prefix then
				last[key] = nil
			end
		end
		lastWithdraw[id] = nil
		handler:forget(id)
	end

	-- once a second: a player seen as a person for the first time on this server gets the home nearest to them
	function self.sweep(players: { any })
		for _, player in players do
			local id = uid(player)
			if homes:of(id) == nil then
				local species, x, _y, z = deps.bodyOf(player)
				if species == "human" and x and z then
					local lot = homes:assign(id, x, z)
					if deps.setAttr then
						deps.setAttr(player, PlayerHomes.ATTRIBUTE, lot)
					end
				end
			end
		end
	end

	return self
end

export type StartOpts = {
	saves: any,
	wallet: any,
	possession: any, -- Actors/Possession: actorOf(player) -> { species, body }
	town: Instance?, -- Workspace.Town (the desks)
	playNet: Instance, -- ReplicatedStorage.PlayNet
	tell: (player: any, words: string) -> (),
	setAttr: (player: any, name: string, value: any) -> (),
	heartbeat: boolean?,
}

-- The engine: ProcessReceipt, the remote, a prompt on each home's computer, the home sweep and the price.
function StockOptions.start(opts: StartOpts): Service?
	local Players = game:GetService("Players")
	local Marketplace = game:GetService("MarketplaceService")
	local remote = opts.playNet:FindFirstChild(StockOptions.REMOTE) :: RemoteEvent?
	if remote == nil then
		local r = Instance.new("RemoteEvent")
		r.Name = StockOptions.REMOTE
		r.Parent = opts.playNet
		remote = r
	end
	local ev = remote :: RemoteEvent
	local price: number? = nil
	local service = StockOptions.new({
		saves = opts.saves,
		wallet = opts.wallet,
		tell = opts.tell,
		send = function(player: any, payload: { [string]: any })
			ev:FireClient(player, payload)
		end,
		setAttr = opts.setAttr,
		bodyOf = function(player: any): (string?, number?, number?, number?)
			local a = opts.possession and opts.possession:actorOf(player)
			local body = a and a.body
			if not (a and body) then
				return nil
			end
			if a.species ~= "human" then
				return a.species -- (only a person's place is read: a held squirrel's is MovementService's to judge)
			end
			local ok, pos = pcall(function(): Vector3
				return (body :: Model):GetPivot().Position
			end)
			if not ok then
				return a.species
			end
			return a.species, pos.X, pos.Y, pos.Z
		end,
		playerById = function(userId: number): any?
			return Players:GetPlayerByUserId(userId)
		end,
		prompt = function(player: any, productId: number)
			Marketplace:PromptProductPurchase(player, productId)
		end,
		price = function(): number?
			return price
		end,
		clock = os.clock,
		now = os.time,
		sleep = function(s: number)
			task.wait(s)
		end,
		studio = function(): boolean
			return game:GetService("RunService"):IsStudio()
		end,
		jobId = if game.JobId ~= "" then game.JobId else `studio-{game:GetService("HttpService"):GenerateGUID(false)}`,
	})
	Marketplace.ProcessReceipt = function(info: any): Enum.ProductPurchaseDecision
		local ok, decision = pcall(service.processReceipt, info)
		if ok and decision == "PurchaseGranted" then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		if not ok then
			warn(`[StockOptions] a receipt failed: {decision}`)
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local conns: { RBXScriptConnection } = {}
	local made: { Instance } = {}
	local running = true
	conns[#conns + 1] = Players.PlayerRemoving:Connect(function(player: Player)
		local ok, err = pcall(function()
			service.leave(player)
		end)
		if not ok then
			warn(`[StockOptions] leave failed: {err}`)
		end
	end)
	conns[#conns + 1] = ev.OnServerEvent:Connect(function(player: Player, verb: any, arg: any)
		if type(verb) ~= "string" or #verb > 16 then
			return
		end
		local ok, err = pcall(function()
			service.request(player, verb, arg)
		end)
		if not ok then
			warn(`[StockOptions] a request failed: {err}`)
		end
	end)
	-- the product's price, for the screen (what one purchase costs and gives)
	task.spawn(function()
		local ok, info = pcall(function(): any
			return Marketplace:GetProductInfo(Products.SPICY_BUCK_ID, Enum.InfoType.Product)
		end)
		if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
			price = info.PriceInRobux
		else
			warn(`[StockOptions] the product's price could not be read: {info}`)
		end
	end)
	-- a prompt on each home's computer screen (the bake's desk; at its recorded place if the desk is not found)
	for _, h in PlayerHomes.HOMES do
		local lots = opts.town and opts.town:FindFirstChild("Lots") -- (Workspace.Town.Lots.<lot>; Town.Skyline has
		local lot = lots and lots:FindFirstChild(h.lot) --   a far-view stand-in of the same name)
		local screen = lot and lot:FindFirstChild(h.desk .. "_Monitor")
		local att = Instance.new("Attachment")
		att.Name = "HomeComputer"
		if screen and screen:IsA("BasePart") then
			att.Parent = screen
		else
			warn(`[StockOptions] {h.lot}: no desk screen in the town; its computer stands at its recorded place`)
			att.Position = Vector3.new(h.computer[1], h.computer[2], h.computer[3])
			att.Parent = workspace.Terrain
		end
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "HomeComputerPrompt"
		prompt.ActionText = "Use computer"
		prompt.ObjectText = "Home computer: Spicy Stock Options"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		prompt.MaxActivationDistance = 7
		prompt.RequiresLineOfSight = false
		prompt.HoldDuration = 0
		prompt:SetAttribute("Door", true) -- E belongs to the prompt (Client/Minigames/MinigameClient)
		prompt.Parent = att
		table.insert(made, att)
		local lotId = h.lot
		conns[#conns + 1] = prompt.Triggered:Connect(function(player: Player)
			local ok, err = pcall(function()
				service.computer(player, lotId)
			end)
			if not ok then
				warn(`[StockOptions] the computer failed: {err}`)
			end
		end)
	end
	if opts.heartbeat ~= false then
		task.spawn(function()
			while running do
				task.wait(1)
				local ok, err = pcall(function()
					service.sweep(Players:GetPlayers())
				end)
				if not ok then
					warn(`[StockOptions] the home sweep failed: {err}`)
				end
			end
		end)
	end
	service.stop = function()
		running = false
		for _, c in conns do
			c:Disconnect()
		end
		for _, i in made do
			i:Destroy()
		end
		pcall(function()
			(Marketplace :: any).ProcessReceipt = nil
		end)
	end
	return service
end

return StockOptions
