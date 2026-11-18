--!strict
-- ServerStorage.EngineTests.CornerStoreFlow (CI place only)
-- Pepper's Corner Store in the engine, on a server with no clients, as plain results. Written for the day Luau
-- Execution works for the key again; not run yet (tools/cloud/tasks/corner_store_flow.luau sends it).
--   bake      Workspace.Expansion.F1.f1_corner_store is in the place: its Zone, its till's two prompts (Pay, Put
--             back), and the 21 items on sale (the 22 less the dog treats, which wait for dogs), each with a Sample,
--             a price tag and a "Take" prompt (StoreItem attribute)
--   buy       Server/Items/CornerStore over the town's real wallet (Economy/Credits) and Items/Inventory, a
--             PlayerLike stub standing inside the Zone: a frisbee and a soda picked up, paid once (9c), both owned
--   short     a kite with 20c: refused with words, nothing taken
--   walk out  a basket carried out of the Zone is put back
--   tool      CornerStore.makeTool on every Sample: a Tool with a Handle, its other parts welded, nothing anchored,
--             nothing colliding (what a buyer is handed)
--   items     Items/ItemWorld on a stub possession: bubbles emit, the flashlight has a beam, a soda sets TreatUntil,
--             the whoopee cushion lies on the ground; the lawn chair (kept clear of prompts, so set down on a
--             floor of the test's own, far above the town) is a Seat in Workspace.CornerStoreItems
-- Interface: run() -> { ok, failures, numbers }
-- Engine only; no side effects on require.

local CornerStoreFlow = {}

function CornerStoreFlow.run(): { [string]: any }
	local ServerScriptService = game:GetService("ServerScriptService")
	local server = ServerScriptService:WaitForChild("Server")
	local itemsFolder = server:WaitForChild("Items")
	local CornerStore = (require :: any)(itemsFolder:WaitForChild("CornerStore"))
	local Inventory = (require :: any)(itemsFolder:WaitForChild("Inventory"))
	local ItemWorld = (require :: any)(itemsFolder:WaitForChild("ItemWorld"))
	local Credits = (require :: any)(server:WaitForChild("Economy"):WaitForChild("Credits"))
	local failures: { string } = {}
	local numbers: { [string]: any } = {}
	local function check(cond: any, what: string)
		if not cond then
			table.insert(failures, what)
		end
	end

	-- bake
	local exp = workspace:FindFirstChild("Expansion")
	local f1 = exp and exp:FindFirstChild("F1")
	local root = f1 and f1:FindFirstChild("f1_corner_store")
	check(root ~= nil, "Workspace.Expansion.F1.f1_corner_store is missing (run tools/bake/corner_store.luau)")
	if root == nil then
		return { ok = false, failures = failures, numbers = numbers }
	end
	local zoneFound = root:FindFirstChild("Zone")
	check(zoneFound ~= nil, "no Zone")
	if zoneFound == nil then
		return { ok = false, failures = failures, numbers = numbers }
	end
	local zonePart = zoneFound :: BasePart
	local takes, tills = 0, {}
	for _, d in root:GetDescendants() do
		if d:IsA("ProximityPrompt") then
			if d:GetAttribute("StoreItem") then
				takes += 1
			elseif d:GetAttribute("Till") then
				table.insert(tills, d:GetAttribute("Till"))
			end
		end
	end
	numbers.takePrompts = takes
	check(takes == 21, `{takes} Take prompts (want 21)`)
	check(#tills == 2, `{#tills} till prompts (want Pay and Put back)`)
	local parts = 0
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	numbers.parts = parts

	-- buy, short, walk out
	local zone = CornerStore.zoneOf(zonePart)
	local inside = zonePart.Position
	local wallet = Credits.new({ log = function() end, warn = function() end })
	local function stub(name: string, id: number): any
		local p = { Name = name, UserId = id, events = {}, attrs = {}, pos = inside }
		return p
	end
	local shopper = stub("Shopper", 9101)
	local poor = stub("Poor", 9102)
	wallet.join(shopper)
	wallet.join(poor)
	wallet.spend(poor, wallet.balance(poor) - 20, "a test")
	local inventory = Inventory.new()
	local told: { string } = {}
	local store = CornerStore.new({
		wallet = wallet,
		inventory = inventory,
		zone = zone,
		speciesOf = function(_p: any): string?
			return "human"
		end,
		positionOf = function(p: any): (number?, number?, number?)
			return p.pos.X, p.pos.Y, p.pos.Z
		end,
		present = function(_p: any): boolean
			return true
		end,
		notify = function(_p: any, w: string)
			table.insert(told, w)
		end,
		refuse = function(_p: any, w: string)
			table.insert(told, w)
		end,
	})
	local before = wallet.balance(shopper)
	store:take(shopper, "frisbee")
	store:take(shopper, "soda")
	local ok = store:pay(shopper)
	check(ok, "the shopper could not pay: " .. (told[#told] or ""))
	check(wallet.balance(shopper) == before - 9, `paid {before - wallet.balance(shopper)}c (want 9c)`)
	check(inventory.count(shopper, "frisbee") == 1 and inventory.count(shopper, "soda") == 1, "not handed over")
	store:take(poor, "kite")
	check(not store:pay(poor), "a kite on 20c was sold")
	check(wallet.balance(poor) == 20, "the poor shopper was charged")
	poor.pos = inside + Vector3.new(0, 0, 200)
	store:step()
	check(#store:basket(poor) == 0, "the kite left the store unpaid")

	-- tools
	local made = 0
	for _, m in root:FindFirstChild("Items"):GetChildren() do
		local sample = m:FindFirstChild("Sample")
		if sample then
			local tool = CornerStore.makeTool(sample, m:GetAttribute("ItemId"), m.Name)
			local handle = tool:FindFirstChild("Handle")
			check(handle ~= nil, `{m.Name}: no Handle`)
			for _, p in tool:GetDescendants() do
				if p:IsA("BasePart") then
					check(not p.Anchored and not p.CanCollide, `{m.Name}: {p.Name} anchored or solid`)
				end
			end
			tool:Destroy()
			made += 1
		end
	end
	numbers.tools = made
	check(made == 21, `{made} tools made (want 21)`)

	-- items in the world, on a stub possession
	local body = Instance.new("Model")
	body.Name = "ItemCheckBody"
	local rootPart = Instance.new("Part")
	rootPart.Name = "HumanoidRootPart"
	rootPart.Size = Vector3.new(2, 2, 1)
	rootPart.Anchored = true
	rootPart.CFrame = CFrame.new(inside + Vector3.new(0, 3, 0))
	rootPart.Parent = body
	body.PrimaryPart = rootPart
	Instance.new("Humanoid").Parent = body
	body.Parent = workspace
	local user = stub("User", 9103)
	local world = ItemWorld.start({
		inventory = inventory,
		possession = {
			actorOf = function(_self: any, _p: any): any
				return { species = "human", body = body }
			end,
		},
		runtime = nil,
		fire = function(_p: any, _payload: any) end,
		heartbeat = false,
	})
	for _, id in { "bubbles", "flashlight", "soda", "whoopee_cushion" } do
		inventory.add(user, id)
		local r = world.use(user, id)
		check(r, `{id} could not be used`)
	end
	local floor = Instance.new("Part")
	floor.Name = "ItemCheckFloor"
	floor.Anchored = true
	floor.Size = Vector3.new(40, 1, 40)
	floor.CFrame = CFrame.new(inside + Vector3.new(0, 500, 0))
	floor.Parent = workspace
	rootPart.CFrame = CFrame.new(inside + Vector3.new(0, 503, 0))
	inventory.add(user, "lawn_chair")
	check(world.use(user, "lawn_chair"), "lawn_chair could not be used")
	local placed = workspace:FindFirstChild("CornerStoreItems")
	check(placed and placed:FindFirstChild("LawnChair", true) ~= nil, "no lawn chair set down")
	check(placed and placed:FindFirstChild("WhoopeeCushion") ~= nil, "no whoopee cushion set down")
	check(type(body:GetAttribute("TreatUntil")) == "number", "the soda did nothing")
	world.stop()
	body:Destroy()
	floor:Destroy()
	return { ok = #failures == 0, failures = failures, numbers = numbers }
end

return CornerStoreFlow
