--!strict
-- Buying in Pepper's Corner Store (Server/Items/CornerStore over the town's real wallet, Economy/Credits, and the
-- record of what a player owns, Server/Items/Inventory): pick up, pay once at the till, short of money, a
-- double press, walking out unpaid, an animal at the shelf, a leaver mid-purchase; a body change (the Tool in hand
-- goes back to the Backpack, a Tool left in a body is nobody's to use); and the pure basket (Shared/Items/Basket).
local Basket = require("@shared/Items/Basket")
local ItemRules = require("@shared/Items/ItemRules")
local Credits = require("@server/Economy/Credits")
local Inventory = require("@server/Items/Inventory")
local CornerStore = require("@server/Items/CornerStore")
local FakeEngine = require("@tests/lib/FakeEngine")

type Rig = {
	store: CornerStore.Store,
	wallet: Credits.Wallet,
	inventory: Inventory.Inventory,
	player: any,
	pos: { number }?,
	species: string?,
	present: boolean,
	told: { string },
	refused: { string },
	attrs: { [string]: any },
	onGive: (() -> ())?,
}

-- the store's inside: a 46 x 42 box at the origin, turned a half turn (as the real one is)
local ZONE: Basket.Zone = { cx = 0, cy = 5, cz = 0, yaw = math.pi, hx = 23, hy = 6, hz = 21 }
local INSIDE = { 0, 3, 0 }
local OUTSIDE = { 0, 3, -30 }

local function rig(cents: number?): Rig
	local r: Rig = {
		player = { UserId = 101, Name = "Shopper" },
		pos = INSIDE,
		species = "human",
		present = true,
		told = {},
		refused = {},
		attrs = {},
	} :: any
	r.wallet = Credits.new({
		pocket = function(): number
			return cents or 300
		end,
		log = function() end,
		warn = function() end,
		tell = function() end,
	})
	r.wallet.join(r.player)
	r.inventory = Inventory.new()
	local inv = r.inventory
	r.store = CornerStore.new({
		wallet = r.wallet,
		inventory = {
			add = function(player: any, id: string, n: number?): number
				if r.onGive then
					(r.onGive :: () -> ())()
				end
				return inv.add(player, id, n)
			end,
			take = inv.take,
			count = inv.count,
			list = inv.list,
			export = inv.export,
			refresh = inv.refresh,
			forget = inv.forget,
		},
		zone = ZONE,
		speciesOf = function(_p: any): string?
			return r.species
		end,
		positionOf = function(_p: any): (number?, number?, number?)
			local p = r.pos
			if p == nil then
				return nil, nil, nil
			end
			return p[1], p[2], p[3]
		end,
		present = function(_p: any): boolean
			return r.present
		end,
		notify = function(_p: any, words: string)
			table.insert(r.told, words)
		end,
		refuse = function(_p: any, words: string)
			table.insert(r.refused, words)
		end,
		setAttr = function(_p: any, name: string, value: any)
			r.attrs[name] = value
		end,
	})
	return r
end

local function last(list: { string }): string
	return list[#list] or ""
end

return function(t)
	t.test("the basket: ItemRules' prices, six at most, the words a shopper reads", function()
		local b = Basket.new()
		local ok, words = Basket.take(b, 1, "frisbee")
		t.truthy(ok)
		t.eq(words, "Frisbee, 5c: in your basket (5c in all). Pay at the counter.")
		t.truthy(Basket.take(b, 1, "kite"))
		t.eq(Basket.total(b, 1), 65)
		t.eq(select(2, Basket.take(b, 1, "lottery_ticket")), Basket.WORDS.unknown)
		for _ = 3, Basket.MAX do
			t.truthy(Basket.take(b, 1, "soda"))
		end
		t.eq(select(2, Basket.take(b, 1, "soda")), Basket.WORDS.full)
		t.eq(Basket.list(Basket.items(b, 1)), "a frisbee, a kite and a soda (x4)")
		t.eq(#Basket.clear(b, 1), Basket.MAX)
		t.eq(Basket.total(b, 1), 0)
		-- the zone turns with the store
		t.truthy(Basket.inside(ZONE, 22, 3, 20))
		t.eq(Basket.inside(ZONE, 24, 3, 0), false)
		t.eq(Basket.inside({ cx = 0, cy = 0, cz = 0, yaw = math.pi / 2, hx = 10, hy = 5, hz = 2 }, 0, 0, 8), true)
		t.eq(Basket.inside({ cx = 0, cy = 0, cz = 0, yaw = math.pi / 2, hx = 10, hy = 5, hz = 2 }, 8, 0, 0), false)
	end)

	t.test("buy: pick up two things, pay at the till once, the money gone once, the things in hand", function()
		local r = rig(300)
		t.truthy(r.store:take(r.player, "frisbee"))
		t.truthy(r.store:take(r.player, "soda"))
		t.eq(r.attrs.StoreBasket, "frisbee,soda")
		local before = r.wallet.balance(r.player)
		local ok, words = r.store:pay(r.player)
		t.truthy(ok, words)
		t.eq(r.wallet.balance(r.player), before - 9)
		t.eq(r.inventory.count(r.player, "frisbee"), 1)
		t.eq(r.inventory.count(r.player, "soda"), 1)
		t.eq(r.attrs.StoreBasket, "")
		t.truthy(string.find(words, "Paid 9c", 1, true) ~= nil, words)
		-- one spend for the basket: the account changed once
		local spends = 0
		for _, e in r.wallet.log() do
			if e.delta < 0 then
				spends += 1
			end
		end
		t.eq(spends, 1)
		-- paying again with nothing in the basket takes nothing
		t.eq(r.store:pay(r.player), false)
		t.eq(last(r.refused), Basket.WORDS.empty)
		t.eq(r.wallet.balance(r.player), before - 9)
	end)

	t.test("short of money: refused with words, nothing taken, nothing handed over, the basket kept", function()
		local r = rig(20)
		t.truthy(r.store:take(r.player, "kite"))
		local ok, words = r.store:pay(r.player)
		t.eq(ok, false)
		t.eq(r.wallet.balance(r.player), 20)
		t.eq(r.inventory.count(r.player, "kite"), 0)
		t.truthy(string.find(words, "60c", 1, true) ~= nil, words)
		t.eq(last(r.refused), words)
		t.eq(#r.store:basket(r.player), 1)
		-- put it back at the till, and the cheap thing is bought
		t.truthy(r.store:putBack(r.player))
		t.eq(#r.store:basket(r.player), 0)
		t.truthy(r.store:take(r.player, "bubbles"))
		t.truthy(r.store:pay(r.player))
		t.eq(r.wallet.balance(r.player), 17)
	end)

	t.test("a double press: a second Pay while the first is served is refused and charges nothing", function()
		local r = rig(300)
		t.truthy(r.store:take(r.player, "radio"))
		local inner: { any } = {}
		r.onGive = function()
			if #inner == 0 then
				-- the second press arrives while the first purchase is handing over
				local ok, words = r.store:pay(r.player)
				table.insert(inner, { ok, words })
			end
		end
		t.truthy(r.store:pay(r.player))
		t.eq(inner[1][1], false)
		t.eq(inner[1][2], CornerStore.WORDS.busy)
		t.eq(r.wallet.balance(r.player), 292)
		t.eq(r.inventory.count(r.player, "radio"), 1)
		-- and a plain second press after the sale finds an empty basket
		r.onGive = nil
		t.eq(r.store:pay(r.player), false)
		t.eq(r.wallet.balance(r.player), 292)
	end)

	t.test("walking out unpaid puts it all back; so does losing the body", function()
		local r = rig(300)
		t.truthy(r.store:take(r.player, "football"))
		t.truthy(r.store:take(r.player, "chalk"))
		r.store:step()
		t.eq(#r.store:basket(r.player), 2, "still inside: nothing happens")
		r.pos = OUTSIDE
		r.store:step()
		t.eq(#r.store:basket(r.player), 0)
		t.eq(last(r.told), "You put a football and sidewalk chalk back: pay at the counter before you leave.")
		t.eq(r.attrs.StoreBasket, "")
		t.eq(r.inventory.count(r.player, "football"), 0)
		t.eq(r.wallet.balance(r.player), 300)
		-- no body: the same
		r.pos = INSIDE
		t.truthy(r.store:take(r.player, "peanuts"))
		r.pos = nil
		r.store:step()
		t.eq(#r.store:basket(r.player), 0)
		-- and from outside the store nothing can be picked up or paid for
		r.pos = OUTSIDE
		t.eq(r.store:take(r.player, "peanuts"), false)
		t.eq(last(r.refused), CornerStore.WORDS.outside)
	end)

	t.test("only a person shops: the rodent, a squirrel and someone with no body are told why", function()
		local r = rig(300)
		for _, s in { "rodent", "squirrel" } do
			r.species = s
			t.eq(r.store:take(r.player, "bird_seed"), false)
			t.eq(last(r.refused), CornerStore.WORDS.animal)
		end
		r.species = nil
		t.eq(r.store:take(r.player, "bird_seed"), false)
		t.eq(last(r.refused), CornerStore.WORDS.noBody)
		t.eq(#r.store:basket(r.player), 0)
	end)

	t.test("a leaver: their basket goes back; one who leaves while being served is refunded", function()
		local r = rig(300)
		t.truthy(r.store:take(r.player, "lawn_chair"))
		r.store:gone(r.player)
		t.eq(#r.store:basket(r.player), 0)
		-- mid-purchase: the player is gone by the time the things are handed over
		t.truthy(r.store:take(r.player, "lawn_chair"))
		local real = r.inventory
		local seen = 0
		r.onGive = function()
			seen += 1
		end
		r.present = false
		local ok = r.store:pay(r.player)
		t.eq(ok, false)
		t.eq(seen, 0, "nothing handed to nobody")
		t.eq(real.count(r.player, "lawn_chair"), 0)
		t.eq(r.wallet.balance(r.player), 300, "the money came back")
		r.store:step()
		t.eq(#r.store:basket(r.player), 0, "the basket put back")
		t.eq(r.store:busy(r.player), false)
	end)

	t.test("every one of the 22 can be bought at its catalogue price", function()
		local r = rig(1000)
		local spent = 0
		for _, def in ItemRules.CATALOG do
			t.truthy(r.store:take(r.player, def.id), def.id)
			local ok, words = r.store:pay(r.player)
			t.truthy(ok, `{def.id}: {words}`)
			spent += def.price
			t.eq(r.inventory.count(r.player, def.id), 1, def.id)
		end
		t.eq(r.wallet.balance(r.player), 1000 - spent)
		-- all cheap but bird seed and the kite (brief v2)
		for _, def in ItemRules.CATALOG do
			t.truthy(def.price <= 15 or def.id == "bird_seed" or def.id == "kite", def.id)
		end
	end)
	t.test(
		"a body change: the Tool in hand goes back to the Backpack, none is made twice, none is left behind",
		function()
			local player = FakeEngine.new("Player", "A", { UserId = 11 })
			local backpack = FakeEngine.new("Backpack", "Backpack")
			backpack.Parent = player
			local bodyX = FakeEngine.new("Model", "PersonX")
			local bodyY = FakeEngine.new("Model", "PersonY")
			player.Character = bodyX
			local made = 0
			local inv = Inventory.new({
				makeTool = function(_p: any, id: string): any?
					made += 1
					local tool = FakeEngine.new("Tool", id)
					tool:SetAttribute("ItemId", id)
					tool.Parent = backpack
					return tool
				end,
				toolsOf = function(p: any, id: string): { any }
					local out = {}
					for _, holder in { backpack, p.Character } do
						for _, tl in holder:GetChildren() do
							if tl:GetAttribute("ItemId") == id then
								table.insert(out, tl)
							end
						end
					end
					return out
				end,
			})
			inv.add(player, "water_gun")
			local gun = backpack:GetChildren()[1]
			gun.Parent = bodyX -- equipped: in the hand of body X
			local other = FakeEngine.new("Tool", "Sword")
			other.Parent = bodyX -- (not the store's: left alone)
			t.truthy(CornerStore.heldBy(gun, player), "in the hand of the body A drives: A's to use")
			-- A possesses body Y (Possession sets Character); CornerStore's body watch stows, then refreshes
			player.Character = bodyY
			t.eq(CornerStore.stow(bodyX, backpack), 1)
			inv.refresh(player)
			t.eq(made, 1, "no second Tool made")
			t.eq(gun.Parent, backpack, "the water gun is back in A's Backpack")
			t.eq(#bodyX:GetChildren(), 1, "body X keeps only what was never the store's")
			-- a Tool somehow still in body X (B now drives X) is not A's to use
			gun.Parent = bodyX
			t.falsy(CornerStore.heldBy(gun, player), "a Tool left in a body A no longer drives does nothing for A")
			-- a leaver: whatever body they held keeps none of their things
			t.eq(CornerStore.stow(bodyX, nil), 1)
			t.eq(gun.Parent, nil, "destroyed")
		end
	)
end
