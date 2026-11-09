--!strict
-- ReplicatedStorage.Shared.Economy.EconomyRules
-- Spicy Dollars in integer cents (BUILD_PLAN §1.4, §3.14, D26; brief v2 §13a): wages per in-game hour
-- (the minimum is 2 cents), prices, gig pay by quality (Gigs/GigRules), developer-product grants
-- (Economy/Products), the receipt idempotency key, and the MONEY TERM of the human queue score, which
-- Roles/Ladder reads (queueMoney). Wallet stays server-life until W4. Pure.
-- Interface: WAGES; PRICES; wage(job, hours) -> cents; price(itemId) -> cents?; gigPay(gig, quality) -> Payout;
--            grant(catalog, productId) -> cents?; receiptKey(receipt) -> string; queueMoney(cents) -> S$

local GigRules = require("../Gigs/GigRules")
local ItemRules = require("../Items/ItemRules")
local Products = require("./Products")

local EconomyRules = {}

-- economy/wages.json defaults (cents per in-game hour)
EconomyRules.WAGES = table.freeze({
	minimum = 2,
	jobs = table.freeze({ cashier = 2, barber_cut = 4, restock = 3, hospital_shift = 6, police_shift = 6 }),
})

-- economy/prices.json defaults (cents); items price from Items/ItemRules
-- stylua: ignore
EconomyRules.PRICES = table.freeze({ coffee = 12, nachos = 5, hot_cocoa = 10, green_tea = 8, snow_cone = 6, jetski_rental = 50,
	paintball_pass = 20, paintball_garb_set = 100, wind_tunnel_balls = 15 })

-- Whole cents for `hours` in-game hours of `job`; never below the minimum wage, rounded down so a
-- partial cent is never paid (the job service carries the remainder).
function EconomyRules.wage(job: string, hours: number): number
	local rate = math.max(EconomyRules.WAGES.minimum, EconomyRules.WAGES.jobs[job] or EconomyRules.WAGES.minimum)
	return math.floor(rate * math.max(0, hours) + 1e-9)
end

function EconomyRules.price(itemId: string): number?
	local p = EconomyRules.PRICES[itemId]
	if p then
		return p
	end
	local item = ItemRules.def(itemId)
	return if item then item.price else nil
end

function EconomyRules.gigPay(gig: string, quality: number): GigRules.Payout
	return GigRules.payout(gig, quality)
end

function EconomyRules.grant(catalog: Products.Catalog, productId: number): number?
	local tier = Products.lookup(catalog, productId)
	return if tier then tier.cents else nil
end

-- One credit per purchase: the key is the PurchaseId Roblox repeats on redelivery (D26).
function EconomyRules.receiptKey(receipt: { PurchaseId: string, PlayerId: number? }): string
	assert(type(receipt.PurchaseId) == "string" and receipt.PurchaseId ~= "", "receiptKey: PurchaseId missing")
	return receipt.PurchaseId
end

-- The money term of the human queue score: Spicy Dollars held (brief v2 §13a "queue rank = money plus
-- reputation"). Ladder multiplies it by Ladder.params.w.money.
function EconomyRules.queueMoney(cents: number): number
	return math.max(0, cents) / 100
end

return EconomyRules
