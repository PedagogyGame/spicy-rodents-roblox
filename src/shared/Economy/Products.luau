--!strict
-- ReplicatedStorage.Shared.Economy.Products
-- Developer products that sell Spicy Dollars for Robux (BUILD_PLAN D26, §3.14 economy/products.json,
-- Q19; spike S15). The owner creates the products on the Creator Hub (whole Robux amounts); their
-- IDs are wired into products.json by Claude. Until then `productId` is nil and no tier is buyable,
-- so a receipt for an unknown product is never granted (ProcessReceipt answers NotProcessedYet).
-- Interface: defaults() -> { Tier }, catalog(tiers) -> Catalog, lookup(catalog, productId) -> Tier?

export type Tier = { productId: number?, robux: number, cents: number, label: string }
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

-- Validates and indexes tiers; errors on a fractional Robux price, a non-integer grant or a repeated id.
function Products.catalog(tiers: { Tier }): Catalog
	local byProductId: { [number]: Tier } = {}
	for i, tier in tiers do
		assert(
			type(tier.robux) == "number" and tier.robux >= 1 and math.floor(tier.robux) == tier.robux,
			`tier {i}: robux must be a whole number`
		)
		assert(
			type(tier.cents) == "number" and tier.cents >= 1 and math.floor(tier.cents) == tier.cents,
			`tier {i}: cents must be a whole number`
		)
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

return Products
