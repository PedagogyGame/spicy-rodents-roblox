--!strict
-- ServerScriptService.Server.Economy.ReceiptLedger
-- The idempotent receipt ledger inside the profile (BUILD_PLAN D26; spike S15): a purchase is
-- credited once per PurchaseId, ever. Pure functions over ProfileSchema.Data; the durable save and
-- the ProcessReceipt answer live in Economy/Receipts. The ledger keeps the newest KEEP ids (Roblox
-- never redelivers a receipt once it was answered PurchaseGranted, and only granted, saved receipts
-- age out).
-- Interface: has(data, purchaseId) -> boolean, grant(data, receipt, cents, now) -> (ok, err?)

local Import = require("../Import")
local Wallet = Import.shared("Economy/Wallet") :: typeof(require("../../shared/Economy/Wallet"))
local ProfileSchema = require("../Persistence/ProfileSchema")

export type Receipt = { PurchaseId: string, PlayerId: number, ProductId: number }

local ReceiptLedger = {}

ReceiptLedger.KEEP = 200

function ReceiptLedger.has(data: ProfileSchema.Data, purchaseId: string): boolean
	return data.receipts.byId[purchaseId] ~= nil
end

-- Credits the wallet and records the receipt in one step; refuses a repeat or a bad amount and
-- leaves the data untouched on refusal.
function ReceiptLedger.grant(data: ProfileSchema.Data, receipt: Receipt, cents: number, now: number): (boolean, string?)
	local id = receipt.PurchaseId
	if type(id) ~= "string" or id == "" then
		return false, "bad purchase id"
	end
	if data.receipts.byId[id] ~= nil then
		return false, "duplicate"
	end
	local ok, balance = Wallet.credit(data.wallet.cents, cents)
	if not ok then
		return false, balance :: string
	end
	data.wallet.cents = balance :: number
	data.receipts.byId[id] = { productId = receipt.ProductId, cents = cents, at = now, playerId = receipt.PlayerId }
	table.insert(data.receipts.ids, id)
	while #data.receipts.ids > ReceiptLedger.KEEP do
		local old = table.remove(data.receipts.ids, 1) :: string
		data.receipts.byId[old] = nil
	end
	return true, nil
end

return ReceiptLedger
