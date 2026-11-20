--!strict
-- Shared/Economy/Wallet + Products + Server/Economy/ReceiptLedger (spike S15, D26): integer cents,
-- product tiers, one credit per PurchaseId.
local Wallet = require("@shared/Economy/Wallet")
local Products = require("@shared/Economy/Products")
local ReceiptLedger = require("@server/Economy/ReceiptLedger")
local Receipts = require("@server/Economy/Receipts")
local ProfileSchema = require("@server/Persistence/ProfileSchema")

return function(t)
	t.test("credit and debit stay in whole cents", function()
		local ok, b = Wallet.credit(0, 10000)
		t.truthy(ok)
		t.eq(b, 10000)
		local ok2, b2 = Wallet.debit(b :: number, 12)
		t.truthy(ok2)
		t.eq(b2, 9988)
		t.deepEq({ Wallet.debit(5, 6) }, { false, "insufficient" })
		t.deepEq({ Wallet.credit(5, 0.5) }, { false, "bad amount" })
		t.deepEq({ Wallet.credit(5, -1) }, { false, "bad amount" })
		t.deepEq({ Wallet.credit(5, 0 / 0) }, { false, "bad amount" })
		t.deepEq({ Wallet.credit(Wallet.MAX_CENTS, 1) }, { false, "over cap" })
		t.deepEq({ Wallet.debit(1.5, 1) }, { false, "bad balance" })
	end)
	t.test("format", function()
		t.eq(Wallet.format(0), "S$0.00")
		t.eq(Wallet.format(160000), "S$1,600.00")
		t.eq(Wallet.format(123456789), "S$1,234,567.89")
		t.eq(Wallet.format(5), "S$0.05")
	end)
	t.test("default tiers are whole Robux and about 4 S$ per R$", function()
		for _, tier in Products.defaults() do
			local robux, cents = tier.robux :: number, tier.cents :: number
			t.eq(math.floor(robux), robux)
			t.eq(cents / 100 / robux, 4)
			t.eq(tier.productId, nil)
		end
		local cat = Products.catalog(Products.defaults())
		t.eq(Products.lookup(cat, 1), nil, "no product is buyable until the owner's ids are wired")
	end)
	t.test("catalog refuses fractional Robux and repeated ids", function()
		t.fails(function()
			Products.catalog({ { productId = 1, robux = 2.5, cents = 100, label = "x" } })
		end, "whole")
		t.fails(function()
			Products.catalog({
				{ productId = 1, robux = 2, cents = 100, label = "x" },
				{ productId = 1, robux = 3, cents = 100, label = "y" },
			})
		end, "repeated")
	end)
	t.test("the owner's Spicy buck: 4 Spicy Dollars per Robux, from what the receipt says was paid (D15)", function()
		local tier = Products.spicyBuck()
		t.eq(tier.productId, 3730438620)
		local cat = Products.catalog({ tier })
		t.eq(Products.lookup(cat, 3730438620), tier)
		-- whatever the product's price on the Creator Hub: 4 S$ (400 cents) for each Robux spent
		t.eq(Products.grantFor(tier, { CurrencySpent = 1 }), 400)
		t.eq(Products.grantFor(tier, { CurrencySpent = 25 }), 10000)
		t.eq(Products.grantFor(tier, { CurrencySpent = 400, CurrencyType = "Enum.CurrencyType.Robux" }), 160000)
		-- a receipt that does not say a believable whole Robux amount is never guessed at
		t.eq(Products.grantFor(tier, {}), nil)
		t.eq(Products.grantFor(tier, { CurrencySpent = 0 }), nil)
		t.eq(Products.grantFor(tier, { CurrencySpent = -5 }), nil)
		t.eq(Products.grantFor(tier, { CurrencySpent = 2.5 }), nil)
		t.eq(Products.grantFor(tier, { CurrencySpent = 1e9 }), nil)
		t.eq(Products.grantFor(tier, { CurrencySpent = 10, CurrencyType = "Enum.CurrencyType.Tix" }), nil)
		-- a fixed tier ignores the receipt
		t.eq(Products.grantFor(Products.defaults()[1], { CurrencySpent = 999 }), 10000)
		-- a tier cannot be both
		t.fails(function()
			Products.catalog({ { productId = 1, perRobux = 400, robux = 2, label = "x" } })
		end, "rate tier")
	end)
	t.test("receipts: a Spicy buck purchase credits 4 S$ per Robux once; one with no amount is not granted", function()
		local data = ProfileSchema.template()
		local profile = {
			data = data,
			session = "s",
			savedRevision = 0,
			rev = 0,
			isActive = function()
				return true
			end,
			markDirty = function(self: any)
				self.rev += 1
				return self.rev
			end,
			save = function(self: any)
				self.savedRevision = self.rev
				return true
			end,
		}
		local h = Receipts.new({
			profileOf = function()
				return profile :: any
			end,
			catalog = Products.catalog({ Products.spicyBuck() }),
			now = function()
				return 1
			end,
		})
		local r = { PurchaseId = "b1", PlayerId = 7, ProductId = 3730438620, CurrencySpent = 50 }
		t.eq(h:process(r), "PurchaseGranted")
		t.eq(data.wallet.cents, 20000, "50 Robux -> 200 Spicy Dollars")
		t.eq(h:process(r), "PurchaseGranted")
		t.eq(data.wallet.cents, 20000, "a redelivery is not credited twice")
		t.eq(h:process({ PurchaseId = "b2", PlayerId = 7, ProductId = 3730438620 }), "NotProcessedYet")
		t.eq(data.wallet.cents, 20000)
	end)
	t.test("ledger credits once per PurchaseId and trims to KEEP", function()
		local data = ProfileSchema.template()
		local r = { PurchaseId = "p1", PlayerId = 7, ProductId = 11 }
		t.truthy((ReceiptLedger.grant(data, r, 10000, 1)))
		t.deepEq({ ReceiptLedger.grant(data, r, 10000, 2) }, { false, "duplicate" })
		t.eq(data.wallet.cents, 10000)
		for i = 1, ReceiptLedger.KEEP + 10 do
			ReceiptLedger.grant(data, { PurchaseId = `q{i}`, PlayerId = 7, ProductId = 11 }, 1, i)
		end
		t.eq(#data.receipts.ids, ReceiptLedger.KEEP)
		t.falsy(ReceiptLedger.has(data, "p1"))
		t.truthy(ReceiptLedger.has(data, `q{ReceiptLedger.KEEP + 10}`))
		t.eq(data.wallet.cents, 10000 + ReceiptLedger.KEEP + 10)
		t.truthy((ProfileSchema.validate(data)))
	end)
	t.test("schema: new player, no v0, newer schema refused, corrupt refused", function()
		-- a new player is the template (ProfileStore: only an absent key); there is no v0 (nothing wrote the store
		-- before v1), so a record without a numeric schema is refused, never read as a fresh one
		local fresh = ProfileSchema.template()
		t.eq(fresh.wallet.cents, 0)
		t.eq(ProfileSchema.migrate(nil), nil)
		t.eq(ProfileSchema.migrate({ cents = 450 }), nil)
		local v1 = ProfileSchema.migrate({
			schema = 1,
			wallet = { cents = 450 },
			receipts = { ids = {}, byId = {} },
			wardrobe = {},
			inventory = {},
			reputation = 0,
			stats = {},
		})
		t.eq((v1 :: any).wallet.cents, 450)
		t.eq((v1 :: any).schema, ProfileSchema.VERSION)
		local newer, err = ProfileSchema.migrate({ schema = ProfileSchema.VERSION + 1 })
		t.eq(newer, nil)
		t.truthy(err and string.find(err, "newer"))
		local bad = ProfileSchema.migrate({ schema = 1, wallet = { cents = 1.5 } })
		t.eq(bad, nil)
	end)
end
