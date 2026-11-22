--!strict
-- ServerScriptService.Server.Economy.ReceiptLedger
-- The idempotent receipt ledger inside the profile (BUILD_PLAN D26; spike S15): a purchase is
-- credited once per PurchaseId, ever. Pure functions over ProfileSchema.Data; the durable save and
-- the ProcessReceipt answer live in Economy/Receipts. The ledger keeps the newest KEEP ids (Roblox
-- never redelivers a receipt once it was answered PurchaseGranted, and only granted, saved receipts
-- age out).
-- Two kinds of grant, each one step that changes nothing on refusal: grant credits Spicy cents to the saved wallet
-- (not used live: the wallet is per server), grantOptions credits Spicy Stock Options (owner D30: 1 option per
-- OPTION_CENTS of the grant, a whole number of options or nothing).
-- Interface: has(data, purchaseId) -> boolean, grant(data, receipt, cents, now) -> (ok, err?),
--   grantOptions(data, receipt, cents, now) -> (ok, err?); KEEP; OPTION_CENTS; MAX_OPTIONS

local Import = require("../Import")
local Wallet = Import.shared("Economy/Wallet") :: typeof(require("../../shared/Economy/Wallet"))
local ProfileSchema = require("../Persistence/ProfileSchema")

export type Receipt = {
	PurchaseId: string,
	PlayerId: number,
	ProductId: number,
	CurrencySpent: number?, -- Robux paid (a rate tier's grant is worked out from it: Products.grantFor)
	CurrencyType: any?,
}

local ReceiptLedger = {}

ReceiptLedger.KEEP = 200
ReceiptLedger.OPTION_CENTS = 100 -- one Spicy Stock Option is worth S$1.00 (owner D30)
ReceiptLedger.MAX_OPTIONS = 100_000_000 -- a holding past this is refused, never stored (it would be a bug)

function ReceiptLedger.has(data: ProfileSchema.Data, purchaseId: string): boolean
	return data.receipts.byId[purchaseId] ~= nil
end

local function check(data: ProfileSchema.Data, receipt: Receipt): string?
	local id = receipt.PurchaseId
	if type(id) ~= "string" or id == "" then
		return "bad purchase id"
	end
	if data.receipts.byId[id] ~= nil then
		return "duplicate"
	end
	return nil
end

local function record(data: ProfileSchema.Data, receipt: Receipt, entry: ProfileSchema.ReceiptEntry)
	local id = receipt.PurchaseId
	data.receipts.byId[id] = entry
	table.insert(data.receipts.ids, id)
	while #data.receipts.ids > ReceiptLedger.KEEP do
		local old = table.remove(data.receipts.ids, 1) :: string
		data.receipts.byId[old] = nil
	end
end

-- Credits the wallet and records the receipt in one step; refuses a repeat or a bad amount and
-- leaves the data untouched on refusal.
function ReceiptLedger.grant(data: ProfileSchema.Data, receipt: Receipt, cents: number, now: number): (boolean, string?)
	local err = check(data, receipt)
	if err then
		return false, err
	end
	local ok, balance = Wallet.credit(data.wallet.cents, cents)
	if not ok then
		return false, balance :: string
	end
	data.wallet.cents = balance :: number
	record(data, receipt, { productId = receipt.ProductId, cents = cents, at = now, playerId = receipt.PlayerId })
	return true, nil
end

-- Credits Spicy Stock Options (cents / OPTION_CENTS of them: a grant that is not a whole number of options, or
-- none, is refused) and records the receipt in one step; refuses a repeat and leaves the data untouched on refusal.
function ReceiptLedger.grantOptions(
	data: ProfileSchema.Data,
	receipt: Receipt,
	cents: number,
	now: number
): (boolean, string?)
	local err = check(data, receipt)
	if err then
		return false, err
	end
	if type(cents) ~= "number" or cents < ReceiptLedger.OPTION_CENTS or cents % ReceiptLedger.OPTION_CENTS ~= 0 then
		return false, "not a whole number of options"
	end
	local n = cents // ReceiptLedger.OPTION_CENTS
	local o = data.options
	if o.bought + n > ReceiptLedger.MAX_OPTIONS then
		return false, "too many options"
	end
	o.held += n
	o.bought += n
	record(
		data,
		receipt,
		{ productId = receipt.ProductId, cents = cents, options = n, at = now, playerId = receipt.PlayerId }
	)
	return true, nil
end

return ReceiptLedger
