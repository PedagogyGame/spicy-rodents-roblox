--!strict
-- Rev 3 framework contracts (BUILD_PLAN §4.4 #6b): Economy/EconomyRules and the server-life Wallet
-- purse, Items (water gun stub), Gigs (mow stub), the Minigame contract (fortune machine stub) and the
-- Ride contract (sky lift stub). Brief v2 §13a numbers; no gambling.
local EconomyRules = require("@shared/Economy/EconomyRules")
local FortuneMachine = require("@shared/Minigames/MinigameRules/FortuneMachine")
local GigRules = require("@shared/Gigs/GigRules")
local ItemRules = require("@shared/Items/ItemRules")
local Minigame = require("@shared/Minigames/Minigame")
local Products = require("@shared/Economy/Products")
local RideSpec = require("@shared/Rides/RideSpec")
local Tunables = require("@shared/Config/Tunables")
local Wallet = require("@shared/Economy/Wallet")

return function(t)
	t.test("wages: whole cents, never below the 2-cent minimum", function()
		t.eq(EconomyRules.WAGES.minimum, Tunables.get("economy.minWageCentsPerHour"))
		t.eq(EconomyRules.wage("cashier", 3), 6)
		t.eq(EconomyRules.wage("hospital_shift", 1.5), 9)
		t.eq(EconomyRules.wage("unknown_job", 2), 4)
		t.eq(EconomyRules.wage("cashier", 0.4), 0) -- no partial cents
		t.eq(EconomyRules.wage("cashier", -5), 0)
	end)

	t.test("prices: the brief's (coffee 12, nachos 5) and items from ItemRules", function()
		t.eq(EconomyRules.price("coffee"), 12)
		t.eq(EconomyRules.price("nachos"), 5)
		t.eq(EconomyRules.price("water_gun"), 6)
		t.eq(EconomyRules.price("kite"), 60)
		t.eq(EconomyRules.price("nope"), nil)
	end)

	t.test("grants and receipt keys", function()
		local tiers = Products.defaults()
		tiers[1].productId = 111
		local cat = Products.catalog(tiers)
		t.eq(EconomyRules.grant(cat, 111), 10000)
		t.eq(EconomyRules.grant(cat, 999), nil)
		t.eq(EconomyRules.receiptKey({ PurchaseId = "abc" }), "abc")
		t.fails(function()
			EconomyRules.receiptKey({ PurchaseId = "" })
		end)
		t.eq(EconomyRules.queueMoney(250), 2.5)
	end)

	t.test("purse: server-life wallet with history, never fractional or negative", function()
		local p = Wallet.purse(0)
		t.truthy(p:credit(12, "shift"))
		t.deepEq({ p:debit(20, "coffee") }, { false, "insufficient" })
		t.truthy(p:debit(12, "coffee"))
		t.deepEq({ p:credit(0.5, "x") }, { false, "bad amount" })
		t.eq(p.cents, 0)
		t.eq(#p.history, 2)
		for i = 1, 30 do
			p:credit(1, `c{i}`)
		end
		t.eq(#p.history, Wallet.HISTORY)
		t.eq(p.history[#p.history].why, "c30")
	end)

	t.test("items: 22, all valid, no gambling; the water gun stub", function()
		t.eq(#ItemRules.CATALOG, 22)
		for _, d in ItemRules.CATALOG do
			t.truthy(ItemRules.validate(d), d.id)
		end
		t.falsy(ItemRules.validate({ id = "scratch", price = 1, effect = "lottery" }))
		local gun = ItemRules.def("water_gun") :: any
		local fx = ItemRules.use(gun, { userId = 1, targetKind = "rodent", targetInRange = true, stunUsed = false })
		t.eq(fx[2].kind, "stun")
		t.eq(fx[2].secs, Tunables.get("rodent.waterGunStunSecs"))
		t.eq(fx[3].kind, "markStunUsed")
		local again = ItemRules.use(gun, { userId = 1, targetKind = "rodent", targetInRange = true, stunUsed = true })
		t.eq(#again, 1) -- once per player
		t.eq(ItemRules.use(gun, { userId = 1, targetInRange = false })[1].hit, false)
		t.eq(ItemRules.use(ItemRules.def("kite") :: any, { userId = 1 })[1].kind, "todo")
	end)

	t.test("gigs: quality >= 0.9 tips, < 0.4 dings; mow quality from coverage and time", function()
		t.eq(GigRules.quality("mow", { cells = 100, mown = 100, secs = 50 }), 1)
		t.near(GigRules.quality("mow", { cells = 100, mown = 100, secs = 90 }) :: number, 0.5)
		t.near(GigRules.quality("mow", { cells = 100, mown = 30, secs = 10 }) :: number, 0.3)
		t.eq(GigRules.quality("delivery", {}), nil)
		local tip = EconomyRules.gigPay("mow", 0.95)
		t.eq(tip.tip, GigRules.GIGS.mow.tipCents)
		t.eq(tip.reputationEvent, "gig_tip")
		t.eq(EconomyRules.gigPay("mow", 0.39).reputationEvent, "gig_bad")
		t.eq(EconomyRules.gigPay("mow", 0.6).reputationEvent, nil)
		local n = 0
		for _ in GigRules.GIGS do
			n += 1
		end
		t.eq(n, 6)
	end)

	t.test("minigame contract: the fortune machine takes no money", function()
		t.truthy(Minigame.check(FortuneMachine))
		t.falsy(Minigame.check({ def = { game = "slots", class = "no_stakes", seats = 1, money = "robux" } }))
		local g = Minigame.start(FortuneMachine :: any, 1, 42)
		t.eq(Minigame.result(g), nil)
		t.deepEq({ Minigame.input(g, 1, "spin") }, { false, "verb" })
		t.deepEq({ Minigame.input(g, 2, "pull") }, { false, "seat" })
		t.truthy(Minigame.input(g, 1, "pull"))
		local r = Minigame.result(g) :: any
		t.truthy(r.done)
		t.eq(r.cents, 0)
		t.truthy(r.fortune >= 1 and r.fortune <= FortuneMachine.FORTUNES)
		local g2 = Minigame.start(FortuneMachine :: any, 1, 42)
		Minigame.input(g2, 1, "pull")
		t.eq((Minigame.result(g2) :: any).fortune, r.fortune) -- seeded
	end)

	t.test("ride contract: the sky lift has no controls and no score; path and exit", function()
		local d = RideSpec.def("sky_lift") :: RideSpec.Def
		t.truthy(RideSpec.check(d))
		t.falsy(RideSpec.check({ ride = "x", kind = "cable", controls = true, score = false }))
		local dur = RideSpec.duration(d)
		t.truthy(dur > 0)
		local x0, y0, z0 = RideSpec.pathAt(d, 0)
		t.deepEq({ x0, y0, z0 }, { 0, 10, 0 })
		local x1, y1, z1 = RideSpec.pathAt(d, dur + 5)
		t.deepEq({ x1, y1, z1 }, { RideSpec.exitPoint(d) })
		local _, ym = RideSpec.pathAt(d, dur / 2)
		t.near(ym, 85, 1e-9)
	end)
end
