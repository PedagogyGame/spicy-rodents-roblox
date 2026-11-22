--!strict
-- ServerScriptService.Server.Economy.Receipts
-- MarketplaceService.ProcessReceipt semantics (BUILD_PLAN D26, risk 24; spike S15). The handler
-- answers "PurchaseGranted" only once the credit is durable in the player's DataStore profile, and
-- "NotProcessedYet" whenever it cannot be sure: the player is not here, the profile is not loaded,
-- read-only or lost to another server, the product is unknown, or the save failed. Roblox redelivers
-- NotProcessedYet receipts (on the next join or purchase), and the ledger keyed by PurchaseId makes
-- the redelivery idempotent: a receipt already in the profile is never credited again, and one
-- credited in memory but not yet saved is only saved, not re-credited.
-- The engine edge maps the string to Enum.ProductPurchaseDecision; this module stays pure.
-- WIRING IT LIVE: the profile it credits must be the one Persistence/PlayerSaves already holds for the player
-- (the live server's only session lock on key p_<userId>), never one loaded through its own ProfileStore or
-- Persistence/Profiles: a second lock on the same key from the same server would lock the two out of each other.
-- What a receipt grants is deps.grant's (default ReceiptLedger.grant, the saved wallet; Economy/StockOptions passes
-- ReceiptLedger.grantOptions), and the durable write is deps.save's (default profile:save(); live, PlayerSaves'
-- saveNow, which goes through that player's one queue of DataStore calls). deps.enabled false (the Flags switch)
-- answers NotProcessedYet to everything: Roblox keeps the receipt and offers it again later.
-- A credit not yet known durable is remembered by PurchaseId with the Profile OBJECT that holds it and its revision:
-- a later offer to another Profile object (a rejoin, on this server or another) finds the ledger entry in a profile
-- loaded from the store, so it is durable and granted, never held back by an older object's revision.
-- Interface: new(deps) -> Handler; handler:process(receiptInfo) -> Decision; handler:forget(playerId) (the player
--   left: their remembered credits go; their profile object is gone with them); handler.stats

local Import = require("../Import")
local Products = Import.shared("Economy/Products") :: typeof(require("../../shared/Economy/Products"))
-- (a module reached through Import carries its values' types but not its exported type names:
-- this is the same type, taken from a value)
type Catalog = typeof(Products.catalog({}))
local ReceiptLedger = require("./ReceiptLedger")
local ProfileStore = require("../Persistence/ProfileStore")

export type Decision = "PurchaseGranted" | "NotProcessedYet"
export type Deps = {
	profileOf: (playerId: number) -> ProfileStore.Profile?, -- nil while the player is absent or loading
	catalog: Catalog,
	now: () -> number,
	-- credits the receipt into the profile's data and records it in the ledger, in one step (ReceiptLedger.grant)
	grant: ((data: any, receipt: ReceiptLedger.Receipt, cents: number, now: number) -> (boolean, string?))?,
	-- makes the profile durable: (true) once a write holding everything it had when called has landed
	save: ((profile: ProfileStore.Profile, playerId: number) -> (boolean, string?))?,
	enabled: (() -> boolean)?, -- false: everything is NotProcessedYet (default on)
}
export type Stats = {
	off: number,
	granted: number,
	credited: number,
	duplicates: number,
	notReady: number,
	unknownProduct: number,
	saveFailed: number,
}
-- a credit in memory, not yet known durable: the Profile object that holds it and the revision that does
export type Pending = { profile: ProfileStore.Profile, rev: number, playerId: number }
export type Handler = {
	deps: Deps,
	pending: { [string]: Pending }, -- PurchaseId -> where the credit is, until it is durable
	stats: Stats,
	process: (self: Handler, receipt: ReceiptLedger.Receipt) -> Decision,
	forget: (self: Handler, playerId: number) -> (),
}

local Receipts = {}

local function save(self: Handler, profile: ProfileStore.Profile, playerId: number): boolean
	local fn = self.deps.save
	local ok = if fn then fn(profile, playerId) else profile:save()
	return ok == true
end

local function process(self: Handler, receipt: ReceiptLedger.Receipt): Decision
	local stats = self.stats
	local enabled = self.deps.enabled
	if enabled and not enabled() then
		stats.off += 1
		return "NotProcessedYet"
	end
	if type(receipt) ~= "table" or type(receipt.ProductId) ~= "number" or type(receipt.PlayerId) ~= "number" then
		stats.unknownProduct += 1
		return "NotProcessedYet"
	end
	local tier = Products.lookup(self.deps.catalog, receipt.ProductId)
	local cents = if tier then Products.grantFor(tier, receipt) else nil
	if cents == nil then
		-- an unknown product, or a rate product whose receipt does not say what was paid
		stats.unknownProduct += 1
		return "NotProcessedYet"
	end
	local profile = self.deps.profileOf(receipt.PlayerId)
	if profile == nil or not profile:isActive() then
		stats.notReady += 1
		return "NotProcessedYet"
	end
	local id = receipt.PurchaseId
	local entry: Pending? = self.pending[id]
	if entry and entry.profile ~= profile then
		-- another Profile object (a rejoin): what it holds was loaded from the store, so the older entry is moot
		self.pending[id] = nil
		entry = nil
	end
	local want: number
	if ReceiptLedger.has(profile.data, id) then
		if entry == nil or profile.savedRevision >= entry.rev then
			-- already durable: a redelivery or a retry after an answer that was lost
			self.pending[id] = nil
			stats.duplicates += 1
			stats.granted += 1
			return "PurchaseGranted"
		end
		want = entry.rev
	else
		local grant: (any, ReceiptLedger.Receipt, number, number) -> (boolean, string?) = self.deps.grant
			or ReceiptLedger.grant
		local ok = grant(profile.data, receipt, cents, self.deps.now())
		if not ok then
			stats.saveFailed += 1
			return "NotProcessedYet"
		end
		want = profile:markDirty()
		self.pending[id] = { profile = profile, rev = want, playerId = receipt.PlayerId }
		stats.credited += 1
	end
	local saved = save(self, profile, receipt.PlayerId)
	if saved and profile.savedRevision >= want then
		self.pending[id] = nil
		stats.granted += 1
		return "PurchaseGranted"
	end
	stats.saveFailed += 1
	return "NotProcessedYet"
end

local function forget(self: Handler, playerId: number)
	for id, entry in self.pending do
		if entry.playerId == playerId then
			self.pending[id] = nil
		end
	end
end

function Receipts.new(deps: Deps): Handler
	return {
		deps = deps,
		pending = {},
		stats = { off = 0, granted = 0, credited = 0, duplicates = 0, notReady = 0, unknownProduct = 0, saveFailed = 0 },
		process = process,
		forget = forget,
	}
end

return Receipts
