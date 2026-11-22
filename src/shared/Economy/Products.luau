--!strict
-- ReplicatedStorage.Shared.Economy.Products
-- Developer products that sell Spicy Dollars for Robux (BUILD_PLAN D26, §3.14 economy/products.json,
-- Q19; spike S15). The owner creates the products on the Creator Hub (whole Robux amounts); their
-- IDs are wired into products.json by Claude. Until then `productId` is nil and no tier is buyable,
-- so a receipt for an unknown product is never granted (ProcessReceipt answers NotProcessedYet).
-- A tier is either fixed (`robux` and `cents`: the price and what it sells) or a RATE (`perRobux`: Spicy cents granted
-- for each Robux the receipt says was spent, its CurrencySpent). The owner's "Spicy buck" product is a rate: "4 Spicy
-- Dollars per 1 Robux" (owner 2026-11-19, BRIEF_ADDENDUM D15). The key cannot read the product's price, so the grant
-- is worked out from what each purchase actually cost: right whatever price the product has on the Creator Hub, and
-- still right if it is changed there.
-- LIVE through Server/Economy/StockOptions (owner D30, 2026-11-22): the product sells SPICY STOCK OPTIONS, saved in
-- the player's profile (1 option = S$1.00 = 100 cents, so 4 options per Robux), withdrawn at the player's home
-- computer into the per-server wallet. The fixed default tiers below are not on sale (no product ids).
-- Interface: defaults() -> { Tier }, spicyBuck() -> Tier, catalog(tiers) -> Catalog, lookup(catalog, productId) -> Tier?,
--   grantFor(tier, receipt) -> cents? (nil: the receipt cannot be priced; answer NotProcessedYet)

export type Tier = { productId: number?, robux: number?, cents: number?, perRobux: number?, label: string }
export type Catalog = { byProductId: { [number]: Tier }, tiers: { Tier } }

local Products = {}

-- The plan's default tiers (25, 100 and 400 R$ for 100, 400 and 1,600 S$; about 1 R$ to 4 S$).
function Products.defaults(): { Tier }
	return {
		{ productId = nil, robux = 25, cents = 10000, label = "100 Spicy Dollars" },
		{ productId = nil, robux = 100, cents = 40000, label = "400 Spicy Dollars" },
		{ productId = nil, robux = 400, cents = 160000, label = "1,600 Spicy Dollars" },
	}
end

Products.SPICY_BUCK_ID = 3730438620 -- the owner's "Spicy buck" developer product (docs/spec/PROJECT_IDS.md)
Products.PER_ROBUX = 400 -- Spicy cents per Robux: 4 Spicy Dollars per 1 Robux (owner, D15)
Products.MAX_ROBUX = 100000 -- a receipt claiming more is not believed (the Creator Hub's own cap is far lower)

-- The owner's product as a rate tier.
function Products.spicyBuck(): Tier
	return { productId = Products.SPICY_BUCK_ID, perRobux = Products.PER_ROBUX, label = "Spicy Stock Options" }
end

local function whole(v: any): boolean
	return type(v) == "number" and v >= 1 and math.floor(v) == v
end

-- Validates and indexes tiers; errors on a fractional Robux price, a non-integer grant, a tier that is both or
-- neither fixed and rate, or a repeated id.
function Products.catalog(tiers: { Tier }): Catalog
	local byProductId: { [number]: Tier } = {}
	for i, tier in tiers do
		if tier.perRobux ~= nil then
			assert(whole(tier.perRobux), `tier {i}: perRobux must be a whole number of cents`)
			assert(tier.robux == nil and tier.cents == nil, `tier {i}: a rate tier has no fixed robux or cents`)
		else
			assert(whole(tier.robux), `tier {i}: robux must be a whole number`)
			assert(whole(tier.cents), `tier {i}: cents must be a whole number`)
		end
		local id = tier.productId
		if id ~= nil then
			assert(byProductId[id] == nil, `tier {i}: productId {id} repeated`)
			byProductId[id] = tier
		end
	end
	return { byProductId = byProductId, tiers = tiers }
end

function Products.lookup(catalog: Catalog, productId: number): Tier?
	return catalog.byProductId[productId]
end

-- The Spicy cents a receipt for this tier grants: the fixed amount, or the rate times the Robux the receipt says
-- were spent (CurrencySpent, in Robux: CurrencyType Robux or absent). nil when a rate tier's receipt carries no
-- believable whole Robux amount: the purchase is not granted (NotProcessedYet), never guessed.
function Products.grantFor(tier: Tier, receipt: { CurrencySpent: any?, CurrencyType: any? }): number?
	local rate = tier.perRobux
	if rate == nil then
		return tier.cents
	end
	local spent = receipt.CurrencySpent
	local kind = receipt.CurrencyType
	if kind ~= nil and tostring(kind) ~= "Enum.CurrencyType.Robux" and tostring(kind) ~= "Robux" then
		return nil
	end
	if type(spent) ~= "number" or not whole(spent) or spent > Products.MAX_ROBUX then
		return nil
	end
	return spent * rate
end

return Products
