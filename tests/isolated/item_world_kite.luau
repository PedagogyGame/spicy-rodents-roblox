--!strict
-- tests/isolated/item_world_kite.luau: cases for tests/unit/item_world_kite.spec.luau, run in their own Lune process
-- (tests/lib/Isolated) because they install fake engine globals (tests/lib/FakeEngine).
-- Server/Items/ItemWorld's kite on that fake engine, server-authoritative: it goes up downwind of its flier, the
-- flier carries KiteUp while it is up, steer() leans it and lets out its string (clamped, rate-limited, nothing
-- from anyone else or for a kite coming down), and it settles back to the wind's centre when let go.
-- Interface: return function(t) (the spec shape)
local FakeEngine = require("@tests/lib/FakeEngine")
local ItemWorld = require("@server/Items/ItemWorld")
local KiteFlight = require("@shared/Items/KiteFlight")
local roblox = require("@lune/roblox")

local ZONES = { { id = "zone_kite_park", kind = "kite", rect = { x0 = -500, x1 = 500, z0 = -500, z1 = 500 } } }

type Rig = { world: any, player: any, other: any, root: any, notices: { string } }

local function rig(): Rig
	-- (the string's Beam colour: a datatype the fake engine does not put in place)
	-- selene: allow(deprecated)
	local env = getfenv(0) :: any
	env.ColorSequence = roblox.ColorSequence
	local Players = game:GetService("Players")
	rawset(game:GetService("Debris"), "AddItem", function() end)
	rawset(workspace, "GetServerTimeNow", function()
		return 0
	end)
	local function person(name: string): (any, any)
		local p = FakeEngine.new("Player", name)
		rawset(p, "UserId", #name)
		p.Parent = Players
		local body = FakeEngine.model(name .. "Body", roblox.CFrame.new(0, 3, 0), nil)
		local root = FakeEngine.part("HumanoidRootPart", roblox.CFrame.new(0, 3, 0), body)
		body.PrimaryPart = root
		local tool = FakeEngine.new("Tool", "Kite")
		tool:SetAttribute("ItemId", "kite")
		tool.Parent = body
		FakeEngine.part("Handle", roblox.CFrame.new(1, 3, 0), tool)
		FakeEngine.part("Sail", roblox.CFrame.new(1, 4, 0), tool)
		rawset(p, "Character", body)
		return p, root
	end
	local player, root = person("Flier")
	local other = person("Other")
	local notices: { string } = {}
	local world = ItemWorld.start({
		inventory = {
			count = function(): number
				return 1
			end,
			take = function(): boolean
				return true
			end,
		},
		possession = {
			actorOf = function(_self: any, p: any): any
				return { species = "human", body = p.Character }
			end,
		},
		runtime = nil,
		fire = function(_p: any, msg: any)
			table.insert(notices, msg.text)
		end,
		zones = ZONES,
		heartbeat = false,
	})
	return { world = world, player = player, other = other, root = root, notices = notices }
end

local function kitePos(): any
	local folder = workspace:FindFirstChild("CornerStoreItems")
	local m = folder and folder:FindFirstChild("Kite")
	return m and m:GetPivot().Position
end

-- across the wind from the flier (+ right of downwind) and along it
local function across(r: Rig): (number, number)
	local p = kitePos() - r.root.Position
	local w = KiteFlight.WIND
	return p.X * -w[2] + p.Z * w[1], p.X * w[1] + p.Z * w[2]
end

return function(t)
	t.test("up downwind of its flier, KiteUp on while it flies and off when it starts down", function()
		FakeEngine.with(function()
			local r = rig()
			t.truthy(r.world.use(r.player, "kite"), "it goes up")
			t.eq(r.player:GetAttribute(ItemWorld.KITE_ATTRIBUTE), true)
			for _ = 1, 40 do
				r.world.step()
			end
			local side, down = across(r)
			t.truthy(down > 15, `downwind ({down})`)
			t.truthy(math.abs(side) < KiteFlight.SWAY + 0.1, "at the wind's centre")
			-- a second use (past the cooldown) brings it down
			r.world.service:state(r.player, "kite").last = -100
			t.truthy(r.world.use(r.player, "kite"))
			t.eq(r.player:GetAttribute(ItemWorld.KITE_ATTRIBUTE), nil, "off as soon as it starts down")
			t.falsy(r.world.steer(r.player, 1, 0), "a kite coming down is not steered")
			for _ = 1, 40 do
				r.world.step()
			end
			t.eq(kitePos(), nil, "reeled in")
		end)
	end)

	t.test("steer leans it within the limit, lets out the string, and it settles back when let go", function()
		FakeEngine.with(function()
			local r = rig()
			r.world.use(r.player, "kite")
			for _ = 1, 30 do
				r.world.step()
			end
			t.truthy(r.world.steer(r.player, 9, 1), "taken (and clamped)")
			for _ = 1, 15 do
				r.world.step()
			end
			local f = r.world.kiteOf(r.player)
			t.eq(f.lean, 1, "full lean, no further")
			t.truthy(f.length > KiteFlight.LENGTH, "string let out")
			local side = across(r)
			t.truthy(side > 20, `well over to the right ({side})`)
			t.truthy(r.world.steer(r.player, 0, 0), "let go")
			for _ = 1, 15 do
				r.world.step()
			end
			t.eq(f.lean, 0, "back at the centre")
			t.truthy(math.abs((across(r))) < KiteFlight.SWAY + 0.1)
		end)
	end)

	t.test("only the flier steers it, and a flood of packets is cut to the bucket", function()
		FakeEngine.with(function()
			local r = rig()
			r.world.use(r.player, "kite")
			t.falsy(r.world.steer(r.other, 1, 0), "somebody else's keys do nothing")
			t.eq(r.world.kiteOf(r.player).x, 0)
			local took = 0
			for _ = 1, 50 do
				if r.world.steer(r.player, -1, 0) then
					took += 1
				end
			end
			t.truthy(took <= KiteFlight.BURST + 1, `the burst, not fifty ({took})`)
			t.eq(r.world.kiteOf(r.player).x, -1)
		end)
	end)

	t.test("put away (a body change) brings it down and gives the flier's feet back", function()
		FakeEngine.with(function()
			local r = rig()
			r.world.use(r.player, "kite")
			r.world.putAway(r.player)
			t.eq(r.player:GetAttribute(ItemWorld.KITE_ATTRIBUTE), nil)
			t.eq(r.world.kiteOf(r.player), nil)
		end)
	end)

	t.test("the world stopped with a kite up gives the flier's feet back", function()
		FakeEngine.with(function()
			local r = rig()
			r.world.use(r.player, "kite")
			t.eq(r.player:GetAttribute(ItemWorld.KITE_ATTRIBUTE), true)
			r.world.stop()
			t.eq(r.player:GetAttribute(ItemWorld.KITE_ATTRIBUTE), nil)
		end)
	end)
end
