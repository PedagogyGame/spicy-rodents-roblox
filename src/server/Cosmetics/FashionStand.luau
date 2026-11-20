--!strict
-- ServerScriptService.Server.Cosmetics.FashionStand
-- Sewer fashion stand (the prototype's 3 x 10 hats, jackets and trousers). Not built. What it sells is clothing:
-- its pieces go into Shared/Items/Clothing.CATALOG and are handed over with Cosmetics/Wardrobe:give, which saves them
-- between servers (owner D16 #25) like the alley shirt (Cosmetics/GiftShop).
-- Interface (BUILD_PLAN §1.4): buy, equip
-- W0 skeleton stub: no behaviour yet. Requiring this module must have no side effects
-- (rule 4: requiring never starts a thread; services expose init(ctx) and step(dt, now)).

local FashionStand = {}

FashionStand.__skeleton = true

return FashionStand
