--!strict
-- ReplicatedStorage.Shared.Items.Basket
-- What a shopper in Pepper's Corner Store is carrying to the till, and the words for it (brief v2 "Corner
-- store": "a working checkout counter, and about 22 pick-up-able shelf items"). Pure rules over a table the
-- server keeps (Server/Items/CornerStore): the price is always Items/ItemRules' (never a client's), a basket
-- holds at most MAX things, and what is in it when its shopper walks out goes back on the shelf. Paying is the
-- wallet's (Economy/Credits.buy with the whole basket: one purchase, one spend).
-- Interface: MAX; new() -> Baskets; take(b, key, itemId) -> (ok, words); items(b, key) -> { id };
--   total(b, key) -> cents; clear(b, key) -> { id } (what was in it); list(ids) -> "a frisbee and a soda";
--   inside(zone, x, y, z) -> boolean (zone: { cx, cy, cz, yaw, hx, hy, hz }, a box turned by yaw about Y);
--   WORDS
-- Pure; no side effects on require.

local ItemRules = require("./ItemRules")
local EconomyRules = require("../Economy/EconomyRules")
local Bank = require("../Economy/Bank")

local Basket = {}

Basket.MAX = 6

export type Baskets = { byKey: { [any]: { string } } }
export type Zone = { cx: number, cy: number, cz: number, yaw: number, hx: number, hy: number, hz: number }

Basket.WORDS = table.freeze({
	took = "%s, %s: in your basket (%s in all). Pay at the counter.", -- amounts as Economy/Bank.amount writes them
	full = "Your hands are full: pay for what you have first.",
	unknown = "That is not for sale.",
	putBack = "You put %s back: pay at the counter before you leave.",
	empty = "Pick something off the shelves first.",
})

local function nameOf(id: string): string
	return (EconomyRules.NAMES :: { [string]: string })[id] or "that"
end

local function capital(s: string): string
	return string.upper(string.sub(s, 1, 1)) .. string.sub(s, 2)
end

function Basket.new(): Baskets
	return { byKey = {} }
end

function Basket.items(b: Baskets, key: any): { string }
	return b.byKey[key] or {}
end

function Basket.total(b: Baskets, key: any): number
	local cents = 0
	for _, id in Basket.items(b, key) do
		local def = ItemRules.def(id)
		cents += if def then def.price else 0
	end
	return cents
end

function Basket.take(b: Baskets, key: any, itemId: string): (boolean, string)
	local def = ItemRules.def(itemId)
	if def == nil or not ItemRules.validate(def) or not ItemRules.onSale(itemId) then
		return false, Basket.WORDS.unknown
	end
	local list = b.byKey[key]
	if list == nil then
		list = {}
		b.byKey[key] = list
	end
	if #list >= Basket.MAX then
		return false, Basket.WORDS.full
	end
	table.insert(list, itemId)
	local bare = string.gsub(nameOf(itemId), "^an? ", "")
	return true,
		string.format(Basket.WORDS.took, capital(bare), Bank.amount(def.price), Bank.amount(Basket.total(b, key)))
end

function Basket.clear(b: Baskets, key: any): { string }
	local list = b.byKey[key] or {}
	b.byKey[key] = nil
	return list
end

-- "a frisbee", "a frisbee and a soda", "a frisbee, a soda and bubbles" (the wallet's names); the same thing
-- twice reads "a soda (x2)".
function Basket.list(ids: { string }): string
	local counts: { [string]: number } = {}
	local order: { string } = {}
	for _, id in ids do
		if counts[id] == nil then
			table.insert(order, id)
			counts[id] = 0
		end
		counts[id] += 1
	end
	local parts: { string } = {}
	for _, id in order do
		local n = counts[id]
		table.insert(parts, if n > 1 then `{nameOf(id)} (x{n})` else nameOf(id))
	end
	if #parts == 0 then
		return "nothing"
	elseif #parts == 1 then
		return parts[1]
	end
	return table.concat(parts, ", ", 1, #parts - 1) .. " and " .. parts[#parts]
end

function Basket.inside(z: Zone, x: number, y: number, zz: number): boolean
	local dx, dz = x - z.cx, zz - z.cz
	local c, s = math.cos(z.yaw), math.sin(z.yaw)
	-- into the zone's own axes (a turn of -yaw about Y, Roblox's sense)
	local lx = dx * c - dz * s
	local lz = dx * s + dz * c
	return math.abs(lx) <= z.hx and math.abs(lz) <= z.hz and math.abs(y - z.cy) <= z.hy
end

return Basket
