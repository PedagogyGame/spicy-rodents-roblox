--!strict
-- ServerScriptService.Server.Items.CornerStore
-- Buying in Pepper's Corner Store (brief v2 "Corner store": "a working checkout counter, and about 22
-- pick-up-able shelf items"; the store is baked by tools/bake/corner_store into Workspace.Expansion.F1).
--   * Pick up: each item's prompt on its shelf (E, a click or a tap, gamepad X: ProximityPrompt "Take" with the
--     attribute StoreItem) puts one in the shopper's basket (Shared/Items/Basket: at most six things; the price is
--     ItemRules', never the client's). Only a person shops: an animal is told so; nobody shops from outside.
--   * Pay: the till's prompt ("Pay", E) charges the whole basket ONCE through the town's wallet (Economy/Credits
--     .buy with the list: its price and names are the wallet's), and only then hands the things over
--     (Server/Items/Inventory: the record and a Tool each in the Backpack). Short of money: the wallet's words
--     ("You need S$2.10; you have 70c.") and nothing is taken; the basket stays. A second press while a purchase is
--     being served is refused with words and charges nothing (a busy flag here, and the wallet's own guard).
--     "Put back" at the till (R / gamepad Y, a short hold) empties the basket onto the shelves.
--   * Nothing leaves unpaid: a shopper whose body is outside the store (the baked Zone box), or who has no body,
--     has the basket put back, with words. A player who leaves the game has it put back; one who leaves while
--     being served is refunded by the wallet (the handing-over fails: nobody to hand it to).
-- What is bought is used from the hotbar: each Tool's Activated goes to Items/ItemWorld (Items/ItemService's rules).
-- The kick ball (owner D30) is used when the press ends (Deactivated), with the seconds it was held as its wind-up,
-- timed here on the server (wirePress): a click kicks it, a hold throws it.
-- What is bought stays the buyer's (owner, D16 #26; Items/Lending): somebody else's frisbee caught or picked up is a
-- borrowed Tool (lendTool: attributes LentItem and LentFrom, never ItemId, so the Inventory never counts it), put
-- in the hand when the hand is free, to throw back.
-- The player attribute StoreBasket holds the basket as "id,id,..." ("" when empty) for a screen to show.
-- Sounds: cue names only (no uploads; docs/AUDIO_BUDGET.md): CUES, and SOUNDS (cue -> a library sound's id, empty).
-- Interface: new(deps) -> Store { take(player, id) -> (ok, words), pay(player) -> (ok, words),
--   putBack(player) -> (ok, words), step(), gone(player), basket(player) -> { id }, busy(player) -> boolean };
--   start(opts) -> Store? (finds the bake, carves its inside, wires the prompts, steps on Heartbeat; nil without
--   the bake; its kickBall(player) is F by a kick ball on the ground);
--   zoneOf(part) -> Basket.Zone; makeTool(sample, itemId, name) -> Tool; wirePress(tool, itemId, held, use, clock?);
--   WINDUP_ITEMS; WORDS; CUES; SOUNDS; STORE (the model's
--   name); REMOTE; STEER_REMOTE
-- Engine only inside start/zoneOf/makeTool; no side effects on require.

local Import = require("../Import")
local Basket = Import.shared("Items/Basket") :: typeof(require("../../shared/Items/Basket"))
local EconomyRules = Import.shared("Economy/EconomyRules") :: typeof(require("../../shared/Economy/EconomyRules"))
local Inventory = require("./Inventory")
local ItemWorld = require("./ItemWorld")

local CornerStore = {}

-- (Exported types do not cross the Import shim (rule 1): Shared/Items/Basket's shapes, restated.)
export type Zone = { cx: number, cy: number, cz: number, yaw: number, hx: number, hy: number, hz: number }
type Baskets = { byKey: { [any]: { string } } }

CornerStore.STORE = "f1_corner_store"
CornerStore.REMOTE = "CornerStoreItemText" -- ReplicatedStorage: the client's words for the chalk
-- ReplicatedStorage: the kite's steer keys from its flier's client (Client/UI/KiteSteer): two numbers, clamped and
-- rate-limited by Items/ItemWorld.steer (Shared/Items/KiteFlight)
CornerStore.STEER_REMOTE = "KiteSteer"

CornerStore.WORDS = table.freeze({
	animal = "Only people shop here.",
	noBody = "Take a body first.",
	outside = "Step inside the store to pick that up.",
	busy = "One moment: still serving you.",
	paid = "%s Pepper says: thanks, come again!",
	gone = "Nobody to hand it to.",
})

CornerStore.CUES = table.freeze({
	till = "CornerStore.Till", -- the register's drawer and bell, on a sale
})
CornerStore.SOUNDS = { ["CornerStore.Till"] = "rbxassetid://9113728049" } :: { [string]: string } -- Cash Register 2 (ProSoundEffects)

export type Deps = {
	wallet: { buy: (player: any, what: string | { string }, deliver: (() -> (boolean?, string?))?) -> (boolean, string) },
	inventory: Inventory.Inventory,
	zone: Zone,
	speciesOf: (player: any) -> string?, -- nil: no body
	positionOf: (player: any) -> (number?, number?, number?), -- the body's root (nil: no body)
	present: (player: any) -> boolean, -- still in the game
	notify: (player: any, words: string) -> (),
	refuse: (player: any, words: string) -> (),
	setAttr: ((player: any, name: string, value: any) -> ())?,
	cue: ((name: string) -> ())?,
}

export type Store = {
	take: (self: Store, player: any, itemId: string) -> (boolean, string),
	pay: (self: Store, player: any) -> (boolean, string),
	putBack: (self: Store, player: any) -> (boolean, string),
	step: (self: Store) -> (),
	gone: (self: Store, player: any) -> (),
	basket: (self: Store, player: any) -> { string },
	busy: (self: Store, player: any) -> boolean,
	deps: Deps,
	baskets: Baskets,
	serving: { [any]: boolean },
	shoppers: { [any]: any }, -- basket key -> player
	stop: (() -> ())?,
	-- F by a kick ball lying on the ground (the townsperson's kick, Boot/Game): kicked if one is in reach (start's)
	kickBall: ((player: any) -> boolean)?,
}

local function keyOf(player: any): any
	if type(player) == "table" and player.UserId ~= nil then
		return player.UserId
	end
	local ok, id = pcall(function()
		return (player :: any).UserId
	end)
	return if ok and id ~= nil then id else player
end

local Methods = {}
Methods.__index = Methods

local function show(self: Store, player: any)
	local set = self.deps.setAttr
	if set then
		set(player, "StoreBasket", table.concat(Basket.items(self.baskets, keyOf(player)), ","))
	end
end

-- a person, with a body, inside the store
local function shopper(self: Store, player: any): (boolean, string?)
	local d = self.deps
	local species = d.speciesOf(player)
	if species == nil then
		return false, CornerStore.WORDS.noBody
	end
	if species ~= "human" then
		return false, CornerStore.WORDS.animal
	end
	local x, y, z = d.positionOf(player)
	if x == nil or not Basket.inside(d.zone, x :: number, y :: number, z :: number) then
		return false, CornerStore.WORDS.outside
	end
	return true, nil
end

function Methods.take(self: Store, player: any, itemId: string): (boolean, string)
	local ok, why = shopper(self, player)
	if not ok then
		self.deps.refuse(player, why :: string)
		return false, why :: string
	end
	local key = keyOf(player)
	local took, words = Basket.take(self.baskets, key, itemId)
	if not took then
		self.deps.refuse(player, words)
		return false, words
	end
	self.shoppers[key] = player
	show(self, player)
	self.deps.notify(player, words)
	return true, words
end

function Methods.pay(self: Store, player: any): (boolean, string)
	local d = self.deps
	local key = keyOf(player)
	if self.serving[key] then
		d.refuse(player, CornerStore.WORDS.busy)
		return false, CornerStore.WORDS.busy
	end
	local ok, why = shopper(self, player)
	if not ok then
		d.refuse(player, why :: string)
		return false, why :: string
	end
	local list: { string } = table.clone(Basket.items(self.baskets, key))
	if #list == 0 then
		d.refuse(player, Basket.WORDS.empty)
		return false, Basket.WORDS.empty
	end
	self.serving[key] = true
	local paid, words = d.wallet.buy(player, list, function(): (boolean?, string?)
		-- handed over only to someone still here, and only what was paid for
		if not d.present(player) then
			return false, CornerStore.WORDS.gone
		end
		for _, id in list do
			d.inventory.add(player, id)
		end
		return true
	end)
	self.serving[key] = nil
	if paid then
		-- the basket is the paid list now in the player's hands (anything taken meanwhile stays to be paid for)
		local left = Basket.clear(self.baskets, key)
		for i = #list + 1, #left do
			Basket.take(self.baskets, key, left[i])
		end
		show(self, player)
		if d.cue then
			d.cue(CornerStore.CUES.till)
		end
		local text = string.format(CornerStore.WORDS.paid, words)
		d.notify(player, text)
		return true, text
	end
	if d.present(player) then
		d.refuse(player, words)
	end
	return false, words
end

function Methods.putBack(self: Store, player: any): (boolean, string)
	local key = keyOf(player)
	if self.serving[key] then
		self.deps.refuse(player, CornerStore.WORDS.busy)
		return false, CornerStore.WORDS.busy
	end
	local list = Basket.clear(self.baskets, key)
	self.shoppers[key] = nil
	show(self, player)
	if #list == 0 then
		self.deps.refuse(player, Basket.WORDS.empty)
		return false, Basket.WORDS.empty
	end
	local words = string.format(Basket.WORDS.putBack, Basket.list(list))
	self.deps.notify(player, words)
	return true, words
end

-- Anyone carrying unpaid things out of the store (or without a body) puts them back.
function Methods.step(self: Store)
	local d = self.deps
	for key, player in table.clone(self.shoppers) do
		if self.serving[key] then
			continue
		end
		if #Basket.items(self.baskets, key) == 0 then
			self.shoppers[key] = nil
			continue
		end
		if not d.present(player) then
			self:gone(player)
			continue
		end
		local x, y, z = d.positionOf(player)
		if x == nil or not Basket.inside(d.zone, x :: number, y :: number, z :: number) then
			local list = Basket.clear(self.baskets, key)
			self.shoppers[key] = nil
			show(self, player)
			d.notify(player, string.format(Basket.WORDS.putBack, Basket.list(list)))
		end
	end
end

function Methods.gone(self: Store, player: any)
	local key = keyOf(player)
	Basket.clear(self.baskets, key)
	self.shoppers[key] = nil
end

function Methods.basket(self: Store, player: any): { string }
	return table.clone(Basket.items(self.baskets, keyOf(player)))
end

function Methods.busy(self: Store, player: any): boolean
	return self.serving[keyOf(player)] == true
end

function CornerStore.new(deps: Deps): Store
	local self = setmetatable({
		deps = deps,
		baskets = Basket.new(),
		serving = {},
		shoppers = {},
	}, Methods)
	return (self :: any) :: Store
end

-- The baked Zone part (an axis box turned about Y) as a Basket.Zone.
function CornerStore.zoneOf(part: any): Zone
	local cf, size = part.CFrame, part.Size
	local look = cf.LookVector
	-- the part's yaw: its -Z (LookVector) is (-sin yaw, 0, -cos yaw)
	local yaw = math.atan2(-look.X, -look.Z)
	return {
		cx = cf.Position.X,
		cy = cf.Position.Y,
		cz = cf.Position.Z,
		yaw = yaw,
		hx = size.X / 2,
		hy = size.Y / 2,
		hz = size.Z / 2,
	}
end

-- A body the player no longer drives gives back every corner-store Tool in its hand (an equipped Tool lives in
-- the body, and bodies change hands): into the player's Backpack, or destroyed when there is none (a leaver).
-- Returns how many were moved.
function CornerStore.stow(body: Instance?, backpack: Instance?): number
	local n = 0
	for _, t in (if body then body:GetChildren() else {}) :: { Instance } do
		if t:IsA("Tool") and (t:GetAttribute("ItemId") ~= nil or t:GetAttribute("LentItem") ~= nil) then
			n += 1
			if backpack then
				t.Parent = backpack
			else
				t:Destroy()
			end
		end
	end
	return n
end

-- A Tool's use counts only for the player whose body holds it now (never for a Tool left behind in a body).
function CornerStore.heldBy(tool: Instance, player: any): boolean
	local parent = tool.Parent
	return parent ~= nil and parent == player.Character
end

-- The things used when the press ends, with the seconds it was held (the kick ball's wind-up, owner D30).
CornerStore.WINDUP_ITEMS = table.freeze({ kick_ball = true }) :: { [string]: boolean }
CornerStore.WINDUP_CAP = 5 -- seconds: a press held longer is counted as this (Shared/Items/KickBall tops out sooner)

-- A Tool's press, wired: `use(payload?)` on Activated, or for a WINDUP_ITEMS thing on Deactivated with
-- { windup = seconds held } (the server's own clock: no client says how long). `held()`: the Tool is in the hand of the
-- player it belongs to now (heldBy). An unequip mid-press drops the press. Returns the connections.
function CornerStore.wirePress(
	tool: any,
	itemId: string,
	held: () -> boolean,
	use: (payload: { [string]: any }?) -> (),
	clock: (() -> number)?
): { any }
	local now = clock or os.clock
	if not CornerStore.WINDUP_ITEMS[itemId] then
		return {
			tool.Activated:Connect(function()
				if held() then
					use(nil)
				end
			end),
		}
	end
	local pressedAt: number? = nil
	return {
		tool.Activated:Connect(function()
			pressedAt = if held() then now() else nil
		end),
		tool.Deactivated:Connect(function()
			local at = pressedAt
			pressedAt = nil
			if at ~= nil and held() then
				use({ windup = math.clamp(now() - at, 0, CornerStore.WINDUP_CAP) })
			end
		end),
		tool.Unequipped:Connect(function()
			pressedAt = nil
		end),
	}
end

-- A Tool made from a shelf's Sample model: its first part the Handle, the rest welded to it, all light and loose.
function CornerStore.makeTool(sample: Model, itemId: string, name: string): Tool
	local tool = Instance.new("Tool")
	tool.Name = name
	tool.ToolTip = name
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool:SetAttribute("ItemId", itemId)
	local parts: { BasePart } = {}
	for _, p in sample:GetChildren() do
		if p:IsA("BasePart") then
			table.insert(parts, p)
		end
	end
	local centre = sample:GetBoundingBox()
	local handle: BasePart? = nil
	for i, p in parts do
		local c = p:Clone()
		c.Anchored = false
		c.CanCollide = false
		c.CanQuery = false
		c.CanTouch = false
		c.Massless = true
		if i == 1 then
			c.Name = "Handle"
			handle = c
			c.Parent = tool
		else
			c.Parent = tool
			local w = Instance.new("WeldConstraint")
			w.Part0 = handle :: BasePart
			w.Part1 = c
			w.Parent = c
		end
	end
	-- the umbrella opens: a canopy over its top, hidden until it is used (Items/ItemWorld "open")
	if itemId == "umbrella" and handle then
		local top = sample:GetBoundingBox().Position + Vector3.new(0, 1.3, 0)
		local canopy = Instance.new("Part")
		canopy.Name = "OpenCanopy"
		canopy.Shape = Enum.PartType.Cylinder
		canopy.Size = Vector3.new(0.4, 4.2, 4.2)
		canopy.CFrame = CFrame.new(top) * CFrame.Angles(0, 0, math.pi / 2)
		canopy.Color = Color3.fromRGB(30, 70, 160)
		canopy.Material = Enum.Material.Fabric
		canopy.Transparency = 1
		canopy.CanCollide = false
		canopy.CanQuery = false
		canopy.CanTouch = false
		canopy.Massless = true
		canopy.Anchored = false
		canopy.Parent = tool
		local w = Instance.new("WeldConstraint")
		w.Part0 = handle :: BasePart
		w.Part1 = canopy
		w.Parent = canopy
	end
	-- the grip at the model's centre, so it sits in the hand however its parts were laid out
	if handle then
		tool.Grip = (handle :: BasePart).CFrame:ToObjectSpace(CFrame.new(centre.Position)):Inverse()
	end
	return tool
end

export type StartOpts = {
	expansion: Instance?, -- Workspace.Expansion
	runtime: any?, -- Actors/ActorsRuntime (the town's brains, for the items' effects)
	zones: { any }?, -- generated/Expansion.zones (where a kite flies)
	dogs: any?, -- Wildlife/YardHazards (the dog treats' dogs)
	wallet: any, -- Economy/Credits.Wallet (Game.start's)
	possession: any, -- Actors/Possession (actorOf(player) -> actor { species, body })
	fire: (player: any, payload: { [string]: any }) -> (), -- Game's notice/refused channel
	heartbeat: boolean?,
	terrain: boolean?, -- false: leave the terrain (a spec's place)
	reputation: any?, -- Reputation/ReputationService: a kick ball's hard hits are reported to it (Items/ItemWorld)
}

function CornerStore.start(opts: StartOpts): Store?
	local slot = opts.expansion and opts.expansion:FindFirstChild("F1")
	local root = slot and slot:FindFirstChild(CornerStore.STORE)
	if root == nil then
		warn("[CornerStore] Workspace.Expansion.F1 has no f1_corner_store: run lune run tools/bake/corner_store.luau")
		return nil
	end
	local zonePart = root:FindFirstChild("Zone")
	local shelves = root:FindFirstChild("Items")
	if zonePart == nil or shelves == nil then
		warn("[CornerStore] the store's bake has no Zone or Items")
		return nil
	end
	-- the inside, carved to air (no terrain pokes through the floor)
	if opts.terrain ~= false then
		local carve = root:FindFirstChild("TerrainCarve")
		for _, p in (if carve then carve:GetChildren() else {}) :: { Instance } do
			if p:IsA("BasePart") then
				workspace.Terrain:FillBlock(p.CFrame, p.Size, Enum.Material.Air)
			end
		end
	end
	local Players = game:GetService("Players")
	local samples: { [string]: Model } = {}
	for _, m in shelves:GetChildren() do
		local id = m:GetAttribute("ItemId")
		local sample = m:FindFirstChild("Sample")
		if type(id) == "string" and sample and sample:IsA("Model") then
			samples[id] = sample
		end
	end
	local function displayName(id: string): string
		local n = (EconomyRules.NAMES :: { [string]: string })[id] or id
		n = string.gsub(n, "^an? ", "")
		return string.upper(string.sub(n, 1, 1)) .. string.sub(n, 2)
	end
	local items: ItemWorld.World? = nil -- (started below, once the inventory exists)
	local inventory: Inventory.Inventory
	inventory = Inventory.new({
		makeTool = function(player: any, itemId: string): any?
			local sample = samples[itemId]
			local backpack: Instance? = nil
			if typeof(player) == "Instance" then
				backpack = (player :: Player):FindFirstChildOfClass("Backpack")
			end
			if not sample or not backpack or (player :: Player).Parent ~= Players then
				return nil -- (a buyer who left: their record counts it, a Tool is made when they come back)
			end
			local tool = CornerStore.makeTool(sample, itemId, displayName(itemId))
			-- using it (a click, a tap, the gamepad's trigger; the kick ball when the press ends): Items/ItemService
			-- decides, Items/ItemWorld does
			CornerStore.wirePress(tool, itemId, function(): boolean
				return CornerStore.heldBy(tool, player)
			end, function(payload: { [string]: any }?)
				if items then
					items.use(player, itemId, payload)
				end
			end)
			tool.Parent = backpack
			return tool
		end,
		toolsOf = function(player: any, itemId: string): { any }
			local out = {}
			if typeof(player) ~= "Instance" then
				return out
			end
			local p = player :: Player
			for _, holder in { p:FindFirstChildOfClass("Backpack"), p.Character } :: { Instance? } do
				for _, t in (if holder then holder:GetChildren() else {}) :: { Instance } do
					if t:IsA("Tool") and t:GetAttribute("ItemId") == itemId then
						table.insert(out, t)
					end
				end
			end
			return out
		end,
	})
	local function actorOf(player: any): any?
		return opts.possession and opts.possession:actorOf(player)
	end
	local store = CornerStore.new({
		wallet = opts.wallet,
		inventory = inventory,
		zone = CornerStore.zoneOf(zonePart),
		speciesOf = function(player: any): string?
			local a = actorOf(player)
			return if a and a.body then a.species else nil
		end,
		positionOf = function(player: any): (number?, number?, number?)
			local a = actorOf(player)
			local body = a and a.body
			local rootPart = body and (body :: Model).PrimaryPart
			if rootPart == nil then
				return nil, nil, nil
			end
			local p = (rootPart :: BasePart).Position
			return p.X, p.Y, p.Z
		end,
		present = function(player: any): boolean
			return typeof(player) == "Instance" and (player :: Player).Parent == Players
		end,
		notify = function(player: any, words: string)
			opts.fire(player, { kind = "notice", text = words })
		end,
		refuse = function(player: any, words: string)
			opts.fire(player, { kind = "refused", text = words })
		end,
		cue = function(name: string)
			-- a Sound named by its cue at the till (its id: SOUNDS, empty until the lead picks a library sound)
			local at = root:FindFirstChild("PayPoint", true)
			if at then
				local snd = Instance.new("Sound")
				snd.Name = name
				snd.SoundId = CornerStore.SOUNDS[name] or ""
				snd.Parent = at
				if snd.SoundId ~= "" then
					snd:Play()
				end
				game:GetService("Debris"):AddItem(snd, 4)
			end
		end,
		setAttr = function(player: any, name: string, value: any)
			if typeof(player) == "Instance" then
				(player :: Player):SetAttribute(name, value)
			end
		end,
	})
	local conns: { RBXScriptConnection } = {}
	items = ItemWorld.start({
		inventory = inventory,
		possession = opts.possession,
		runtime = opts.runtime,
		fire = opts.fire,
		zones = opts.zones,
		dogs = opts.dogs,
		heartbeat = opts.heartbeat,
		reputation = opts.reputation,
		-- somebody else's thing, borrowed to throw back (Items/Lending): its use is ItemWorld's `use`
		lendTool = function(
			player: any,
			itemId: string,
			ownerName: string,
			use: (payload: { [string]: any }?) -> ()
		): any?
			local sample = samples[itemId]
			local backpack: Instance? = nil
			if typeof(player) == "Instance" then
				backpack = (player :: Player):FindFirstChildOfClass("Backpack")
			end
			if not sample or not backpack then
				return nil
			end
			local name = `{ownerName}'s {string.lower(displayName(itemId))}`
			local tool = CornerStore.makeTool(sample, itemId, name)
			tool:SetAttribute("ItemId", nil)
			tool:SetAttribute("LentItem", itemId)
			tool:SetAttribute("LentFrom", ownerName)
			CornerStore.wirePress(tool, itemId, function(): boolean
				return CornerStore.heldBy(tool, player)
			end, use)
			tool.Parent = backpack
			-- in the hand at once when it is free, so a catch can be thrown straight back
			local body = (player :: Player).Character
			local hum = body and body:FindFirstChildOfClass("Humanoid")
			if hum and body and body:FindFirstChildOfClass("Tool") == nil then
				pcall(function()
					hum:EquipTool(tool)
				end)
			end
			return tool
		end,
	})
	-- the chalk's words come back from the owner's client (Client/Items/ItemClient): text only, checked and
	-- filtered by ItemService before anything is written
	local net = Instance.new("RemoteEvent")
	net.Name = CornerStore.REMOTE
	net.Parent = game:GetService("ReplicatedStorage")
	table.insert(
		conns,
		net.OnServerEvent:Connect(function(player: Player, itemId: any, text: any)
			if items and type(itemId) == "string" and type(text) == "string" and #text <= 200 then
				items.use(player, itemId, { text = text })
			end
		end)
	)
	local steer = Instance.new("RemoteEvent")
	steer.Name = CornerStore.STEER_REMOTE
	steer.Parent = game:GetService("ReplicatedStorage")
	table.insert(
		conns,
		steer.OnServerEvent:Connect(function(player: Player, x: any, y: any)
			if items then
				items.steer(player, x, y)
			end
		end)
	)
	for _, d in root:GetDescendants() do
		if d:IsA("ProximityPrompt") then
			local itemId = d:GetAttribute("StoreItem")
			local till = d:GetAttribute("Till")
			if type(itemId) == "string" then
				table.insert(
					conns,
					d.Triggered:Connect(function(player: Player)
						store:take(player, itemId)
					end)
				)
			elseif till == "pay" then
				table.insert(
					conns,
					d.Triggered:Connect(function(player: Player)
						store:pay(player)
					end)
				)
			elseif till == "put_back" then
				table.insert(
					conns,
					d.Triggered:Connect(function(player: Player)
						store:putBack(player)
					end)
				)
			end
		end
	end
	-- a body change (possess, release, swap: Possession sets Character): the old body gives back the Tools in its
	-- hand, whatever was switched on goes off, and the new body (if any) has every owned thing in the Backpack
	local bodyOf: { [Player]: Instance? } = {}
	local function bodyChanged(player: Player)
		local old = bodyOf[player]
		local now = player.Character
		bodyOf[player] = now
		if old and old ~= now then
			CornerStore.stow(old, player:FindFirstChildOfClass("Backpack"))
			if items then
				items.putAway(player)
			end
		end
		if now then
			task.defer(inventory.refresh, player)
		end
	end
	table.insert(
		conns,
		Players.PlayerRemoving:Connect(function(player: Player)
			store:gone(player)
			-- (whatever body it held keeps none of the leaver's things)
			CornerStore.stow(bodyOf[player], nil)
			CornerStore.stow(player.Character, nil)
			bodyOf[player] = nil
		end)
	)
	local function watch(player: Player)
		bodyOf[player] = player.Character
		table.insert(
			conns,
			player:GetPropertyChangedSignal("Character"):Connect(function()
				bodyChanged(player)
			end)
		)
	end
	for _, p in Players:GetPlayers() do
		watch(p)
	end
	table.insert(conns, Players.PlayerAdded:Connect(watch))
	if opts.heartbeat ~= false then
		local acc = 0
		table.insert(
			conns,
			game:GetService("RunService").Heartbeat:Connect(function(dt: number)
				acc += dt
				if acc >= 0.25 then
					acc = 0
					store:step()
				end
			end)
		)
	end
	store.kickBall = function(player: any): boolean
		return items ~= nil and items.kickLoose(player)
	end
	store.stop = function()
		for _, c in conns do
			c:Disconnect()
		end
		if items then
			items.stop()
		end
		net:Destroy()
		steer:Destroy()
	end
	return store
end

return CornerStore
