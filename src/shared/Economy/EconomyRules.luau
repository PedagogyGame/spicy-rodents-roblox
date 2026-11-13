--!strict
-- ReplicatedStorage.Shared.Economy.EconomyRules
-- Spicy Dollars in integer cents (BUILD_PLAN §1.4, §3.14, D26; brief v2 §13a): wages per in-game hour
-- (the minimum is 2 cents), prices, gig pay by quality (Gigs/GigRules), developer-product grants
-- (Economy/Products), the receipt idempotency key, and the MONEY TERM of the human queue score, which
-- Roles/Ladder reads (queueMoney). Wallet stays server-life until W4. Pure.
-- Pocket money and the timed pass (what Server/Economy/Credits hands Economy/Bank): pocketMoney() is the
-- one number a joining player is topped up to until jobs pay (Tunables economy.pocketMoneyCents; 0 switches
-- it off); pass("paintball") is the one pass the arena and both lounges read (brief v2 §13: "20 spicy cents
-- buys five in-game days of access, which also unlocks five days in the lounges"), with the paintball
-- contract's own words; passLeftWords says how long a pass has left in in-game days AND real minutes (a
-- five-day pass is one real hour at a 12-minute day).
-- Interface: WAGES; PRICES; wage(job, hours) -> cents; price(itemId) -> cents?; gigPay(gig, quality) -> Payout;
--            grant(catalog, productId) -> cents?; receiptKey(receipt) -> string; queueMoney(cents) -> S$;
--            pocketMoney() -> cents; pass(name) -> Bank.PassSpec?; passLeftWords(days, daySeconds) -> string

local Tunables = require("../Config/Tunables")
local GigRules = require("../Gigs/GigRules")
local ItemRules = require("../Items/ItemRules")
local Bank = require("./Bank")
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

-- What a joining player is topped up to (whole cents; anything else reads as none).
function EconomyRules.pocketMoney(): number
	local v = Tunables.get("economy.pocketMoneyCents")
	return if type(v) == "number" and v >= 0 and v ~= math.huge and math.floor(v) == v then v else 0
end

local COUNT = { "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten" }

-- The timed passes on sale, by name. One so far: "paintball" (the arena and both lounges).
function EconomyRules.pass(name: string): Bank.PassSpec?
	if name ~= "paintball" then
		return nil
	end
	local cents = Tunables.get("economy.paintballPassCents") :: number
	local days = Tunables.get("economy.paintballPassDays") :: number
	return {
		name = "paintball",
		cents = cents,
		days = days,
		why = "a paintball pass",
		-- (word for word the paintball contract's "bought" and "has_pass": Shared/Minigames/Paintball/Contract)
		bought = `Pass bought: {COUNT[days] or tostring(days)} days of paintball and both lounges.`,
		has = "You already have a pass.",
	}
end

-- "4.2 in-game days left (about 50 minutes)"; "No pass" with nothing left. `daySeconds`: real seconds a day.
function EconomyRules.passLeftWords(days: number, daySeconds: number): string
	if not (days > 0) then
		return "No pass"
	end
	local minutes = math.max(1, math.ceil(days * daySeconds / 60))
	local real = if minutes == 1 then "about a minute" else `about {minutes} minutes`
	if days >= 1 then
		return `{string.format("%.1f", days)} in-game days left ({real})`
	end
	local hours = math.max(1, math.ceil(days * 24))
	return `{hours} in-game {if hours == 1 then "hour" else "hours"} left ({real})`
end

return EconomyRules
