--!strict
-- Owner D30 (2026-11-22): "lets put a kick ball in the store and if a person kicks it at another player or winds up and
-- throws it at another player, their reputation score goes down".
--   rules     Shared/Items/KickBall: a click kicks, a hold winds up and throws (harder the longer, capped); the sweep of
--             a flying ball against a person; F by a ball on the ground (in reach, in front); the small knock
--   store     on Pepper's shelf (Items/ItemRules, EconomyRules' name, the bake's slot and model), used up never, a
--             borrowed one only thrown back; ItemRules.use by the wind-up; ItemService passes the server's timing on
--   press     Items/CornerStore.wirePress: the kick ball is used when the press ends, timed on the server; an
--             unequip drops the press; everything else is used on Activated as before
--   world     the engine cases (Items/ItemWorld on a fake engine with the real reputation): tests/isolated/
--             kick_ball_world.luau
local Isolated = require("@tests/lib/Isolated")
local KickBall = require("@shared/Items/KickBall")
local ItemRules = require("@shared/Items/ItemRules")
local EconomyRules = require("@shared/Economy/EconomyRules")
local Conduct = require("@shared/Reputation/Conduct")
local ItemService = require("@server/Items/ItemService")
local CornerStore = require("@server/Items/CornerStore")
local Stock = require("../../tools/bake/corner_store/Stock")
local Fixtures = require("../../tools/bake/corner_store/Fixtures")

local C = KickBall.C

-- a fake RBXScriptSignal: Connect, and fire by hand
local function signal(): any
	local fns: { (...any) -> () } = {}
	return {
		Connect = function(_self: any, fn: (...any) -> ())
			table.insert(fns, fn)
			return {
				Disconnect = function()
					local i = table.find(fns, fn)
					if i then
						table.remove(fns, i)
					end
				end,
			}
		end,
		fire = function(...: any)
			for _, fn in table.clone(fns) do
				fn(...)
			end
		end,
	}
end

return function(t)
	Isolated.register(t, "tests/isolated/kick_ball_world")

	t.test("rules: a click kicks; a hold winds up and throws, harder the longer, capped", function()
		local k = KickBall.launch(nil)
		t.eq(k.style, "kick")
		t.eq(k.speed, C.kickSpeed)
		t.truthy(KickBall.hard(k.speed), "a kick is hard: it can knock")
		t.eq(KickBall.launch(C.windupMin - 0.01).style, "kick")
		local lob = KickBall.launch(C.windupMin)
		t.eq(lob.style, "throw")
		t.eq(lob.speed, C.throwMin)
		t.falsy(KickBall.hard(lob.speed), "a quick lob is soft: it is caught")
		local mid = KickBall.launch((C.windupMin + C.windupMax) / 2)
		t.truthy(mid.speed > C.throwMin and mid.speed < C.throwMax)
		t.eq(KickBall.launch(C.windupMax).speed, C.throwMax)
		t.eq(KickBall.launch(99).speed, C.throwMax, "capped")
		t.eq(KickBall.launch(99).windup, C.windupMax)
		t.eq(KickBall.launch(-3).style, "kick")
		t.eq(KickBall.launch(0 / 0).style, "kick", "nonsense is a click")
		t.eq(C.throwMax >= Conduct.C.ball.hardSpeed, true, "a full wind-up is hard")
	end)

	t.test(
		"rules: the sweep finds a person the ball's path passes through, not one beside it, above or below",
		function()
			local p = { x = 0, y = 0, z = -10 }
			t.truthy(KickBall.sweep({ x = 0, y = 1, z = 0 }, { x = 0, y = 1, z = -20 }, p), "straight through")
			t.truthy(KickBall.sweep({ x = 0, y = 4, z = -9 }, { x = 0, y = 4, z = -9.5 }, p), "ending at the chest")
			t.falsy(KickBall.sweep({ x = 3, y = 1, z = 0 }, { x = 3, y = 1, z = -20 }, p), "three studs aside")
			t.falsy(KickBall.sweep({ x = 0, y = 9, z = 0 }, { x = 0, y = 9, z = -20 }, p), "over the head")
			t.falsy(KickBall.sweep({ x = 0, y = 1, z = 0 }, { x = 0, y = 1, z = -5 }, p), "short of them")
			t.truthy(KickBall.sweep({ x = 0, y = 1, z = -10 }, { x = 0, y = 1, z = -10 }, p), "a still point inside")
		end
	)

	t.test(
		"rules: F by a ball on the ground: in reach and in front, the kick's speed the way the kicker faces",
		function()
			local feet = { x = 0, y = 0, z = 0 }
			local vx, vy, vz = KickBall.groundKick({ x = 0, y = 0.5, z = -2 }, feet, 0, -1)
			t.truthy(vx ~= nil)
			t.near(math.sqrt((vx :: number) ^ 2 + (vy :: number) ^ 2 + (vz :: number) ^ 2), C.kickSpeed, 1e-6)
			t.truthy((vz :: number) < 0 and (vy :: number) > 0)
			t.eq(KickBall.groundKick({ x = 0, y = 0.5, z = 2 }, feet, 0, -1), nil, "behind")
			t.eq(KickBall.groundKick({ x = 0, y = 0.5, z = -(C.footReach + 0.5) }, feet, 0, -1), nil, "out of reach")
			t.eq(KickBall.groundKick({ x = 0, y = 6, z = -1 }, feet, 0, -1), nil, "up on a wall")
			t.eq(KickBall.groundKick({ x = 0, y = 0.5, z = -1 }, feet, 0, 0), nil, "no facing")
			t.truthy(KickBall.groundKick({ x = 0.1, y = 0.5, z = 0.1 }, feet, 0, -1) ~= nil, "at the toes")
			local k = KickBall.stagger(0, -45)
			t.eq(k.dx, 0)
			t.eq(k.dz, -C.staggerSlide)
			t.eq(k.secs, C.staggerSecs)
			t.truthy(C.staggerSlide <= 2 and C.staggerSecs <= 1, "a small stagger, never a fall")
		end
	)

	t.test("on the shelf: priced, named, placed and modelled; it lasts; a sensible price", function()
		local d = ItemRules.def("kick_ball") :: any
		t.truthy(d ~= nil)
		t.truthy(ItemRules.validate(d))
		t.truthy(ItemRules.onSale("kick_ball"))
		t.falsy(ItemRules.findersKeep("kick_ball"), "bought: it stays the buyer's (D16 #26)")
		t.eq(ItemRules.USES.kick_ball, nil, "it lasts")
		t.truthy(d.price >= (ItemRules.def("frisbee") :: any).price and d.price <= (ItemRules.def("kite") :: any).price)
		local item = EconomyRules.item("kick_ball") :: any
		t.eq(item.name, "a kick ball")
		t.eq(item.cents, d.price)
		t.truthy(table.find(Stock.IDS, "kick_ball") ~= nil)
		t.eq(#Stock.IDS, #ItemRules.CATALOG)
		t.truthy((Fixtures.SLOTS :: any).kick_ball ~= nil, "a shelf place")
		t.eq((Fixtures.SLOTS :: any).kick_ball.fixture, "gondola4")
		t.eq(ItemRules.CUES.kick_ball, "Items.Throw")
	end)

	t.test(
		"ItemRules.use: the press's wind-up decides kick or throw (borrowed ones too: its effect is a throw)",
		function()
			local d = ItemRules.def("kick_ball") :: any
			t.eq(d.effect, "throw", "so a borrowed one may be thrown back")
			local kick = ItemRules.use(d, { userId = 1 })
			t.eq(kick[1].kind, "throw")
			t.eq(kick[1].style, "kick")
			t.eq(kick[1].speed, C.kickSpeed)
			local throw = ItemRules.use(d, { userId = 1, windup = C.windupMax })
			t.eq(throw[1].style, "throw")
			t.eq(throw[1].speed, C.throwMax)
			t.eq(throw[1].windup, C.windupMax)
			t.eq(throw[2].cue, "Items.Throw")
		end
	)

	t.test("ItemService: the server's timing reaches the throw; nobody else's words can", function()
		local acted: { any } = {}
		local owned = 1
		local svc = ItemService.new({
			inventory = {
				count = function()
					return owned
				end,
				take = function()
					owned -= 1
					return true
				end,
			},
			now = function()
				return 100
			end,
			pose = function()
				return { x = 0, y = 3, z = 0, lx = 0, lz = -1 }
			end,
			speciesOf = function()
				return "human"
			end,
			night = function()
				return false
			end,
			zoneAt = function()
				return nil
			end,
			nearby = function()
				return {}
			end,
			filter = function(_p: any, s: string)
				return s
			end,
			notify = function() end,
			refuse = function() end,
			act = function(_p: any, e: any)
				table.insert(acted, e)
				return true
			end,
		})
		local p = { UserId = 3 }
		t.truthy((svc:use(p, "kick_ball", { windup = 0.9 })))
		t.eq(acted[1].kind, "throw")
		t.eq(acted[1].style, "throw")
		t.eq(acted[1].speed, KickBall.launch(0.9).speed)
		t.eq(owned, 0, "out of the hand, still the buyer's (Items/Lending)")
	end)

	t.test("the press: the kick ball goes when the press ends, timed here; anything else on Activated", function()
		local clock = 10
		local held = true
		local function tool(): any
			return { Activated = signal(), Deactivated = signal(), Unequipped = signal() }
		end
		local used: { any } = {}
		local ball = tool()
		CornerStore.wirePress(ball, "kick_ball", function()
			return held
		end, function(payload: any)
			table.insert(used, payload)
		end, function()
			return clock
		end)
		ball.Activated.fire()
		t.eq(#used, 0, "nothing on the press itself")
		clock += 0.8
		ball.Deactivated.fire()
		t.eq(#used, 1)
		t.near(used[1].windup, 0.8, 1e-9)
		-- a click: released at once
		ball.Activated.fire()
		ball.Deactivated.fire()
		t.eq(used[2].windup, 0)
		-- a release with no press, or after the ball was put away mid-press: nothing
		ball.Deactivated.fire()
		ball.Activated.fire()
		ball.Unequipped.fire()
		ball.Deactivated.fire()
		t.eq(#used, 2)
		-- held for a minute: capped
		ball.Activated.fire()
		clock += 60
		ball.Deactivated.fire()
		t.eq(used[3].windup, CornerStore.WINDUP_CAP)
		-- not in this player's hand: nothing
		held = false
		ball.Activated.fire()
		ball.Deactivated.fire()
		t.eq(#used, 3)
		-- the frisbee is used on the press, as before
		held = true
		local frisbee = tool()
		local n = 0
		CornerStore.wirePress(frisbee, "frisbee", function()
			return held
		end, function(payload: any)
			t.eq(payload, nil)
			n += 1
		end)
		frisbee.Activated.fire()
		t.eq(n, 1)
	end)
end
