--!strict
-- tests/isolated/item_world_lending.luau: cases for tests/unit/item_world_lending.spec.luau, run in their own Lune
-- process (tests/lib/Isolated) because they install fake engine globals (tests/lib/FakeEngine).
-- Server/Items/ItemWorld on that fake engine with the real Items/Inventory: a bought thing stays its buyer's (owner,
-- D16 #26; Server/Items/Lending). A game of catch (picked up, caught in flight, thrown back), two players after one
-- ball, a borrowed ball going home (held too long, walked off with, a body change, an animal's body, the borrower
-- leaving), the buyer leaving (a held ball, a ball on the ground: into their record, theirs again when they come
-- back), a ball left lying, somebody else's whoopee cushion, and a lawn chair whose owner left.
-- Interface: return function(t) (the spec shape)
local FakeEngine = require("@tests/lib/FakeEngine")
local ItemWorld = require("@server/Items/ItemWorld")
local Inventory = require("@server/Items/Inventory")
local Lending = require("@server/Items/Lending")
local roblox = require("@lune/roblox")

type Rig = {
	world: any,
	inv: any,
	pip: any,
	sam: any,
	kim: any,
	species: { [any]: string },
	told: { [string]: { string } },
	clock: number,
	Players: any,
}

local function rig(): Rig
	FakeEngine.events({ "Touched" })
	-- selene: allow(deprecated)
	local env = getfenv(0) :: any
	env.RaycastParams = {
		new = function(): any
			return {}
		end,
	}
	env.OverlapParams = env.RaycastParams
	env.Color3 = roblox.Color3
	local Players = game:GetService("Players")
	rawset(game:GetService("Debris"), "AddItem", function() end)
	rawset(workspace, "GetServerTimeNow", function()
		return 0
	end)
	rawset(workspace, "Gravity", 196.2)
	rawset(workspace, "Raycast", function(_self: any, from: any, _dir: any, _params: any): any
		return { Position = roblox.Vector3.new(from.X, 0, from.Z) }
	end)
	rawset(workspace, "GetPartBoundsInRadius", function(): { any }
		return {}
	end)
	local r: Rig = {
		species = {},
		told = {},
		clock = 1000,
		Players = Players,
	} :: any
	local byBody: { [any]: any } = {}
	rawset(Players, "GetPlayers", function(self: any): { any }
		local out = {}
		for _, c in self:GetChildren() do
			if c.ClassName == "Player" and c.Name ~= "LocalPlayer" then
				table.insert(out, c)
			end
		end
		return out
	end)
	rawset(Players, "GetPlayerFromCharacter", function(_self: any, body: any): any
		return if body then byBody[body] else nil
	end)
	local function person(name: string, id: number, z: number): any
		local p = FakeEngine.new("Player", name)
		rawset(p, "UserId", id)
		rawset(p, "DisplayName", name)
		p.Parent = Players
		FakeEngine.new("Backpack", "Backpack").Parent = p
		local body = FakeEngine.model(name .. "Body", roblox.CFrame.new(0, 3, z), workspace)
		local root = FakeEngine.part("HumanoidRootPart", roblox.CFrame.new(0, 3, z), body)
		rawset(root, "FindFirstAncestorOfClass", function(_self: any, _class: string): any
			return body
		end)
		body.PrimaryPart = root
		byBody[body] = p
		rawset(p, "Character", body)
		r.species[p] = "human"
		r.told[name] = {}
		return p
	end
	-- a Tool like the store's: a Handle (with the members the throw asks of a part) and an attribute
	local function tool(name: string, attrs: { [string]: any }): any
		local t = FakeEngine.new("Tool", name)
		for k, v in attrs do
			t:SetAttribute(k, v)
		end
		local h = FakeEngine.part("Handle", roblox.CFrame.new(0, 3, 0), t)
		rawset(h, "SetNetworkOwner", function() end)
		rawset(h, "AssemblyMass", 1)
		return t
	end
	r.inv = Inventory.new({
		makeTool = function(player: any, itemId: string): any?
			local bp = player:FindFirstChildOfClass("Backpack")
			if bp == nil or player.Parent ~= Players then
				return nil
			end
			local t = tool(itemId, { ItemId = itemId })
			t.Parent = bp
			return t
		end,
		toolsOf = function(player: any, itemId: string): { any }
			local out = {}
			for _, holder in { player:FindFirstChildOfClass("Backpack"), player.Character } do
				for _, c in (if holder then holder:GetChildren() else {}) :: { any } do
					if c:IsA("Tool") and c:GetAttribute("ItemId") == itemId then
						table.insert(out, c)
					end
				end
			end
			return out
		end,
	})
	r.pip = person("Pip", 11, 0)
	r.sam = person("Sam", 12, 30)
	r.kim = person("Kim", 13, 32)
	r.world = ItemWorld.start({
		inventory = r.inv,
		possession = {
			actorOf = function(_self: any, p: any): any
				if p.Character == nil then
					return nil
				end
				return { species = r.species[p], body = p.Character }
			end,
		},
		runtime = nil,
		fire = function(p: any, msg: any)
			table.insert(r.told[p.Name], msg.text)
		end,
		heartbeat = false,
		now = function(): number
			return r.clock
		end,
		lendTool = function(player: any, itemId: string, ownerName: string, use: () -> ()): any?
			local bp = player:FindFirstChildOfClass("Backpack")
			if bp == nil then
				return nil
			end
			local t = tool(`{ownerName}'s {itemId}`, { LentItem = itemId, LentFrom = ownerName })
			t.Activated:Connect(use)
			t.Parent = bp
			return t
		end,
	})
	return r
end

local function last(r: Rig, name: string): string?
	local list = r.told[name]
	return list[#list]
end

local function lying(item: string): any?
	local folder = workspace:FindFirstChild("CornerStoreItems")
	return folder and folder:FindFirstChild("Thrown_" .. item)
end

local function promptOf(model: any): any
	for _, d in model:GetDescendants() do
		if d.ClassName == "ProximityPrompt" then
			return d
		end
	end
	error("no prompt")
end

local function mainOf(model: any): any
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") then
			return d
		end
	end
	error("no part")
end

-- the borrowed Tool in a player's Backpack, if any
local function lentTool(p: any): any?
	for _, c in p:FindFirstChildOfClass("Backpack"):GetChildren() do
		if c:GetAttribute("LentItem") ~= nil then
			return c
		end
	end
	return nil
end

local function throwOwn(r: Rig, p: any, item: string)
	r.world.service:state(p, item).last = -1e9 -- (past the cooldown)
	assert(r.world.use(p, item), `{p.Name} threw the {item}`)
end

local function throwBack(r: Rig, p: any, item: string)
	r.world.service:state(p, item).last = -1e9
	local t = lentTool(p)
	assert(t, `{p.Name} holds a borrowed {item}`)
	t.Activated.fire()
end

local function move(p: any, x: number, z: number)
	local root = p.Character.PrimaryPart
	root.CFrame = roblox.CFrame.new(x, 3, z)
end

return function(t)
	t.test("a game of catch: picked up it is borrowed, never theirs; thrown back, the buyer has it again", function()
		FakeEngine.with(function()
			local r = rig()
			r.inv.add(r.pip, "football")
			throwOwn(r, r.pip, "football")
			t.eq(r.inv.count(r.pip, "football"), 0, "in the air")
			local ball = lying("football")
			t.truthy(ball ~= nil)
			t.eq(promptOf(ball).ObjectText, "Pip's football")
			promptOf(ball).Triggered.fire(r.sam)
			t.eq(lying("football"), nil, "off the ground")
			t.eq(r.inv.count(r.sam, "football"), 0, "never in Sam's inventory")
			t.eq(r.inv.count(r.pip, "football"), 0)
			t.truthy(lentTool(r.sam) ~= nil, "in Sam's hand to throw back")
			t.eq(#r.world.lending.of(r.sam), 1)
			t.eq(last(r, "Sam"), "Pip's football: throw it back. It goes home by itself in 20 seconds.")
			t.eq(last(r, "Pip"), "Sam has your football.")
			-- Sam throws it back: the loan ends, nothing changes hands in anyone's inventory
			throwBack(r, r.sam, "football")
			t.eq(lentTool(r.sam), nil)
			t.eq(#r.world.lending.all(), 0)
			local back = lying("football")
			t.truthy(back ~= nil, "flying back")
			t.eq(promptOf(back).ObjectText, "Pip's football", "still Pip's")
			t.eq(r.inv.count(r.sam, "football"), 0)
			promptOf(back).Triggered.fire(r.pip)
			t.eq(r.inv.count(r.pip, "football"), 1, "Pip has it back")
			t.eq(#r.world.lending.all(), 0)
		end)
	end)

	t.test("caught in flight: the catcher borrows it, the buyer catching it has it back, the thrower never", function()
		FakeEngine.with(function()
			local r = rig()
			r.inv.add(r.pip, "frisbee")
			throwOwn(r, r.pip, "frisbee")
			local m = mainOf(lying("frisbee"))
			m.Touched.fire(r.pip.Character.PrimaryPart)
			t.truthy(lying("frisbee") ~= nil, "the thrower does not catch their own throw")
			m.Touched.fire(r.sam.Character.PrimaryPart)
			t.eq(lying("frisbee"), nil)
			t.eq(last(r, "Sam"), "Caught Pip's frisbee! Throw it back: it goes home by itself in 20 seconds.")
			t.eq(r.inv.count(r.sam, "frisbee"), 0)
			throwBack(r, r.sam, "frisbee")
			local m2 = mainOf(lying("frisbee"))
			m2.Touched.fire(r.sam.Character.PrimaryPart)
			t.truthy(lying("frisbee") ~= nil, "Sam does not catch his own throw")
			m2.Touched.fire(r.pip.Character.PrimaryPart)
			t.eq(last(r, "Pip"), "Caught it!")
			t.eq(r.inv.count(r.pip, "frisbee"), 1)
			-- slow on the ground it is picked up, not caught
			throwOwn(r, r.pip, "frisbee")
			local m3 = mainOf(lying("frisbee"))
			m3.AssemblyLinearVelocity = roblox.Vector3.new(0, 0, 0)
			m3.Touched.fire(r.sam.Character.PrimaryPart)
			t.truthy(lying("frisbee") ~= nil, "lying still: walked into, not caught")
		end)
	end)

	t.test(
		"two players after one ball: the first has it, borrowed; the other gets nothing and cannot use it",
		function()
			FakeEngine.with(function()
				local r = rig()
				r.inv.add(r.pip, "football")
				r.inv.add(r.kim, "football") -- (Kim has one of her own: hers stays hers, Pip's stays Pip's)
				throwOwn(r, r.pip, "football")
				local p = promptOf(lying("football"))
				p.Triggered.fire(r.sam)
				p.Triggered.fire(r.kim)
				t.eq(#r.world.lending.of(r.sam), 1, "Sam was first")
				t.eq(#r.world.lending.of(r.kim), 0)
				t.eq(lentTool(r.kim), nil)
				t.eq(r.inv.count(r.kim, "football"), 1, "Kim still has just her own")
				-- Kim cannot throw Sam's loan, nor a made-up one
				local token = r.world.lending.of(r.sam)[1].token
				r.world.service:state(r.kim, "football").last = -1e9
				local ok = r.world.use(r.kim, "football", { lent = token })
				t.truthy(ok, "(her own football goes instead: the loan is not hers)")
				t.eq(r.inv.count(r.kim, "football"), 0)
				t.eq(#r.world.lending.of(r.sam), 1, "Sam's loan untouched")
				r.world.service:state(r.kim, "football").last = -1e9
				local ok2, why = r.world.use(r.kim, "football", { lent = 999 })
				t.falsy(ok2, "a made-up loan is nothing")
				t.eq(why, "You have not got one.")
				promptOf(lying("football")).Triggered.fire(r.kim) -- (she picks her own back up)
				t.eq(r.inv.count(r.kim, "football"), 1)
				t.eq(lying("football"), nil)
				-- Sam throws it on, Kim catches it: now Kim borrows it, still Pip's
				throwBack(r, r.sam, "football")
				mainOf(lying("football")).Touched.fire(r.kim.Character.PrimaryPart)
				local loans = r.world.lending.all()
				t.eq(#loans, 1)
				t.eq(loans[1].holder, r.kim)
				t.eq(loans[1].thing.owner, r.pip)
				t.eq(r.inv.count(r.sam, "football"), 0)
				t.eq(r.inv.count(r.pip, "football"), 0)
			end)
		end
	)

	t.test("a borrowed ball goes home: held too long, walked off with, a body change, an animal's body", function()
		FakeEngine.with(function()
			local r = rig()
			r.inv.add(r.pip, "football")
			local function lendToSam()
				throwOwn(r, r.pip, "football")
				promptOf(lying("football")).Triggered.fire(r.sam)
				assert(lentTool(r.sam), "lent")
			end
			-- held too long
			lendToSam()
			r.clock += Lending.C.holdSecs - 1
			r.world.step()
			t.truthy(lentTool(r.sam) ~= nil, "a second to go")
			r.clock += 1
			r.world.step()
			t.eq(lentTool(r.sam), nil)
			t.eq(r.inv.count(r.pip, "football"), 1, "home")
			t.eq(r.inv.count(r.sam, "football"), 0)
			t.eq(last(r, "Pip"), "Your football is back in your hands.")
			t.eq(last(r, "Sam"), "Pip's football went back to them.")
			-- walked off with (Sam picked it up 30 studs off: 60 is the limit)
			lendToSam()
			move(r.sam, 0, 55)
			r.world.step()
			t.truthy(lentTool(r.sam) ~= nil, "55 studs off: still playing")
			move(r.sam, 0, 70)
			r.world.step()
			t.eq(lentTool(r.sam), nil, "70 studs off: walked off with it")
			t.eq(r.inv.count(r.pip, "football"), 1)
			move(r.sam, 0, 30)
			-- a body change
			lendToSam()
			r.world.putAway(r.sam)
			t.eq(lentTool(r.sam), nil)
			t.eq(r.inv.count(r.pip, "football"), 1)
			-- Sam's body is a squirrel's now
			lendToSam()
			r.species[r.sam] = "squirrel"
			r.world.step()
			t.eq(lentTool(r.sam), nil)
			t.eq(r.inv.count(r.pip, "football"), 1)
			t.eq(#r.world.lending.all(), 0)
		end)
	end)

	t.test("the buyer leaves: a borrowed ball and one on the ground go into their record, theirs when back", function()
		FakeEngine.with(function()
			local r = rig()
			r.inv.add(r.pip, "football")
			r.inv.add(r.pip, "frisbee")
			throwOwn(r, r.pip, "football")
			promptOf(lying("football")).Triggered.fire(r.sam)
			throwOwn(r, r.pip, "frisbee")
			t.truthy(lying("frisbee") ~= nil)
			r.pip.Parent = nil -- Pip leaves the server
			r.world.step()
			t.eq(lentTool(r.sam), nil, "out of Sam's hand")
			t.eq(lying("frisbee"), nil, "off the ground")
			t.eq(last(r, "Sam"), "Pip left, so their football went home with them.")
			t.eq(r.inv.count(r.sam, "football"), 0)
			t.eq(r.inv.count(r.pip, "football"), 1, "in Pip's record")
			t.eq(r.inv.count(r.pip, "frisbee"), 1)
			-- Pip comes back to this server: both are his
			r.pip.Parent = r.Players
			r.inv.refresh(r.pip)
			t.eq(r.inv.count(r.pip, "football"), 1)
			t.eq(r.inv.count(r.pip, "frisbee"), 1)
			-- the borrower leaving sends it home too
			throwOwn(r, r.pip, "football")
			promptOf(lying("football")).Triggered.fire(r.sam)
			r.sam.Parent = nil
			r.world.step()
			t.eq(#r.world.lending.all(), 0)
			t.eq(r.inv.count(r.pip, "football"), 1)
			t.eq(last(r, "Pip"), "Your football is back in your hands.")
		end)
	end)

	t.test("left lying: the ball goes home after a minute; the world stopped sends everything home", function()
		FakeEngine.with(function()
			local r = rig()
			r.inv.add(r.pip, "football")
			throwOwn(r, r.pip, "football")
			r.clock += Lending.C.groundSecs - 1
			r.world.step()
			t.truthy(lying("football") ~= nil)
			r.clock += 1
			r.world.step()
			t.eq(lying("football"), nil)
			t.eq(r.inv.count(r.pip, "football"), 1)
			t.eq(last(r, "Pip"), "Your football is back in your hands.")
			-- the item world stopped: what lies about or is borrowed goes home, no borrowed Tool stays behind
			throwOwn(r, r.pip, "football")
			r.inv.add(r.pip, "frisbee")
			throwOwn(r, r.pip, "frisbee")
			promptOf(lying("frisbee")).Triggered.fire(r.sam)
			r.world.stop()
			t.eq(lentTool(r.sam), nil)
			t.eq(r.inv.count(r.pip, "football"), 1)
			t.eq(r.inv.count(r.pip, "frisbee"), 1)
		end)
	end)

	t.test("somebody else's whoopee cushion picked up goes home; a lawn chair whose owner left too", function()
		FakeEngine.with(function()
			local r = rig()
			r.inv.add(r.pip, "whoopee_cushion")
			throwOwn(r, r.pip, "whoopee_cushion")
			local folder = workspace:FindFirstChild("CornerStoreItems")
			local cushion = folder:FindFirstChild("WhoopeeCushion")
			t.truthy(cushion ~= nil)
			local p = promptOf(cushion)
			t.eq(p.ObjectText, "Pip's whoopee cushion")
			p.Triggered.fire(r.sam)
			t.eq(folder:FindFirstChild("WhoopeeCushion"), nil, "off the ground")
			t.eq(r.inv.count(r.sam, "whoopee_cushion"), 0, "not Sam's")
			t.eq(r.inv.count(r.pip, "whoopee_cushion"), 1, "back in Pip's things")
			t.eq(last(r, "Sam"), "That whoopee cushion is Pip's: it went back to them.")
			t.eq(last(r, "Pip"), "Sam picked up your whoopee cushion: it is back in your things.")
			-- put down again, its owner picks it up
			throwOwn(r, r.pip, "whoopee_cushion")
			promptOf(folder:FindFirstChild("WhoopeeCushion")).Triggered.fire(r.pip)
			t.eq(r.inv.count(r.pip, "whoopee_cushion"), 1)
			-- put down and Pip leaves: it goes into his record
			throwOwn(r, r.pip, "whoopee_cushion")
			r.inv.add(r.pip, "lawn_chair")
			throwOwn(r, r.pip, "lawn_chair")
			t.truthy(folder:FindFirstChild("LawnChair") ~= nil)
			t.eq(r.inv.count(r.pip, "lawn_chair"), 0)
			r.pip.Parent = nil
			r.world.step()
			t.eq(folder:FindFirstChild("WhoopeeCushion"), nil)
			t.eq(folder:FindFirstChild("LawnChair"), nil)
			t.eq(r.inv.count(r.pip, "whoopee_cushion"), 1, "in Pip's record")
			t.eq(r.inv.count(r.pip, "lawn_chair"), 1, "in Pip's record")
		end)
	end)
end
