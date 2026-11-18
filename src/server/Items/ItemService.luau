--!strict
-- ServerScriptService.Server.Items.ItemService
-- Using what was bought at Pepper's Corner Store (Shared/Items/ItemRules says what each item does; this applies
-- it). A player uses the item in hand (its Tool's Activated: a click, a tap, the gamepad's trigger); the server
-- decides everything: that the player owns one (Items/Inventory), has a body and is a person, the item's
-- cooldown, what the world around says (the target ahead of a water gun, night or day, the park or the beach),
-- then applies ItemRules.use's effects through `deps` and counts the use (a used-up item leaves the inventory).
-- State per player and item: a toggle (flashlight, umbrella, radio, kite), the newspaper read, uses so far.
-- The water gun's rodent stun is once per player for as long as this server runs (Q11), by UserId.
-- Words: a refusal is always said (deps.refuse); what an item does is said where it helps (deps.notify).
-- Interface: new(deps) -> Service { use(player, itemId, payload?) -> (ok, why?), state(player, itemId) -> State,
--   forget(player), putAway(player) -> { itemId } (the toggles that were on, now off) };
--   kiteZoneAt(zones, x, z) -> "park" | "beach" | nil; WORDS
-- Pure over deps; no side effects on require. The engine half is Items/ItemWorld.

local Import = require("../Import")
local ItemRules = Import.shared("Items/ItemRules") :: typeof(require("../../shared/Items/ItemRules"))

local ItemService = {}

ItemService.WORDS = table.freeze({
	notOwned = "You have not got one.",
	noBody = "Take a body first.",
	animal = "Only people can use that.",
	wait = "Give it a second.",
	noDog = "No dog near enough to give a treat to.",
	usedUp = "That was the last of your %s.",
	stunned = "Direct hit! The rodent is stunned.",
	wet = "Splash!",
	chalkTooLong = "Chalk writes up to %d letters.",
	chalkNothing = "Nothing to write.",
})

export type Target = { kind: string, id: any, x: number, y: number, z: number, player: any? }
export type Pose = { x: number, y: number, z: number, lx: number, lz: number } -- position and facing (unit, XZ)

export type Deps = {
	inventory: {
		count: (player: any, id: string) -> number,
		take: (player: any, id: string) -> boolean,
	},
	now: () -> number,
	pose: (player: any) -> Pose?,
	speciesOf: (player: any) -> string?,
	night: () -> boolean,
	zoneAt: (x: number, z: number) -> string?,
	-- who is about: people (computer-run and players), squirrels, the rodent, dogs
	nearby: (x: number, z: number, r: number) -> { Target },
	filter: (player: any, text: string) -> string?, -- TextService's, for everyone to read; nil: refused
	notify: (player: any, words: string) -> (),
	refuse: (player: any, words: string) -> (),
	-- what an effect does in the world (Items/ItemWorld; a spec records them)
	act: (player: any, effect: { [string]: any }, targets: { Target }?) -> boolean?,
}

export type State = { uses: number, on: boolean, read: boolean, last: number }

export type Service = {
	use: (self: Service, player: any, itemId: string, payload: { [string]: any }?) -> (boolean, string?),
	state: (self: Service, player: any, itemId: string) -> State,
	forget: (self: Service, player: any) -> (),
	putAway: (self: Service, player: any) -> { string },
	deps: Deps,
	states: { [any]: { [string]: State } },
	stunUsed: { [any]: boolean },
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

-- Which kite zone (generated/Expansion.zones of kind "kite": zone_kite_park, zone_kite_beach) holds (x, z).
function ItemService.kiteZoneAt(zones: { any }?, x: number, z: number): string?
	for _, zone in (zones or {}) :: { any } do
		local r = zone.rect
		if zone.kind == "kite" and r and x >= r.x0 and x <= r.x1 and z >= r.z0 and z <= r.z1 then
			return if string.find(zone.id, "beach", 1, true) then "beach" else "park"
		end
	end
	return nil
end

local Methods = {}
Methods.__index = Methods

function Methods.state(self: Service, player: any, itemId: string): State
	local k = keyOf(player)
	local mine = self.states[k]
	if mine == nil then
		mine = {}
		self.states[k] = mine
	end
	local s = mine[itemId]
	if s == nil then
		s = { uses = 0, on = false, read = false, last = -math.huge }
		mine[itemId] = s
	end
	return s
end

function Methods.forget(self: Service, player: any)
	self.states[keyOf(player)] = nil
end

-- The player's things went back in the Backpack (a body change): every toggle that was on is off, so the next use
-- switches it on. Returns the item ids that were on (Items/ItemWorld puts their lights, sounds and kites away).
function Methods.putAway(self: Service, player: any): { string }
	local was = {}
	for itemId, s in self.states[keyOf(player)] or {} do
		if s.on then
			s.on = false
			table.insert(was, itemId)
		end
	end
	table.sort(was)
	return was
end

-- the first target ahead of the holder within range, in a narrow cone (the water gun's squirt)
local function aim(self: Service, pose: Pose, range: number, me: any): Target?
	local best: Target? = nil
	local bestD = math.huge
	for _, t in self.deps.nearby(pose.x, pose.z, range) do
		if t.player ~= nil and t.player == me then
			continue
		end
		local dx, dz = t.x - pose.x, t.z - pose.z
		local d = math.sqrt(dx * dx + dz * dz)
		if d > 0.01 and d <= range then
			local along = (dx * pose.lx + dz * pose.lz) / d
			if along >= 0.94 and d < bestD then -- within about 20 degrees of straight ahead
				best, bestD = t, d
			end
		end
	end
	return best
end

local function finishUse(self: Service, player: any, itemId: string, s: State)
	s.uses += 1
	local max = ItemRules.USES[itemId]
	if max and s.uses >= max then
		self.deps.inventory.take(player, itemId)
		local mine = self.states[keyOf(player)]
		if mine then
			mine[itemId] = nil
		end
		if max > 1 then
			local n = string.gsub(itemId, "_", " ")
			self.deps.notify(player, string.format(ItemService.WORDS.usedUp, n))
		end
	end
end

function Methods.use(self: Service, player: any, itemId: string, payload: { [string]: any }?): (boolean, string?)
	local d = self.deps
	local def = ItemRules.def(itemId)
	local function no(words: string): (boolean, string?)
		d.refuse(player, words)
		return false, words
	end
	if def == nil or d.inventory.count(player, itemId) <= 0 then
		return no(ItemService.WORDS.notOwned)
	end
	local species = d.speciesOf(player)
	if species == nil then
		return no(ItemService.WORDS.noBody)
	end
	if species ~= "human" then
		return no(ItemService.WORDS.animal)
	end
	local pose = d.pose(player)
	if pose == nil then
		return no(ItemService.WORDS.noBody)
	end
	local s = self:state(player, itemId)
	local now = d.now()
	local cool = ItemRules.COOLDOWN[itemId] or 0.5
	if now - s.last < cool then
		return false, ItemService.WORDS.wait -- (quietly: a held trigger is not a mistake)
	end
	-- the context: the world as the server sees it
	local ctx: { [string]: any } = {
		userId = if type(keyOf(player)) == "number" then keyOf(player) else 0,
		on = s.on,
		read = s.read,
		uses = s.uses,
		night = d.night(),
		zone = d.zoneAt(pose.x, pose.z),
	}
	local target: Target? = nil
	if itemId == "water_gun" then
		target = aim(self, pose, def.range or 14, player)
		ctx.targetInRange = target ~= nil
		ctx.targetKind = if target then target.kind else nil
		ctx.stunUsed = self.stunUsed[keyOf(player)] == true
	end
	if itemId == "chalk" and payload and type(payload.text) == "string" then
		local raw = string.gsub(payload.text, "^%s+", "")
		raw = string.gsub(raw, "%s+$", "")
		if raw == "" then
			return no(ItemService.WORDS.chalkNothing)
		end
		if utf8.len(raw) == nil or (utf8.len(raw) :: number) > def.letters then
			return no(string.format(ItemService.WORDS.chalkTooLong, def.letters))
		end
		local clean = d.filter(player, raw)
		if clean == nil or clean == "" then
			return no(ItemService.WORDS.chalkNothing)
		end
		ctx.text = clean
	end
	local effects = ItemRules.use(def, ctx)
	s.last = now
	local consumed = false
	for _, e in effects do
		local k = e.kind
		if k == "refuse" then
			return no(e.words)
		elseif k == "askText" then
			d.act(player, e)
			return true, nil -- (nothing used yet: the words come back as payload.text)
		elseif k == "markStunUsed" then
			self.stunUsed[keyOf(player)] = true
		elseif k == "stun" then
			if target then
				d.act(player, e, { target })
				d.notify(player, ItemService.WORDS.stunned)
			end
		elseif k == "squirt" then
			d.act(player, e, if target then { target } else nil)
		elseif k == "startle" then
			d.act(player, e, d.nearby(pose.x, pose.z, e.radius))
		elseif k == "calm_dog" then
			local dogs = {}
			for _, t in d.nearby(pose.x, pose.z, e.radius) do
				if t.kind == "dog" then
					table.insert(dogs, t)
				end
			end
			if #dogs == 0 then
				return no(ItemService.WORDS.noDog)
			end
			d.act(player, e, { dogs[1] })
			consumed = true
		elseif k == "bait" then
			local near = {}
			for _, t in d.nearby(pose.x, pose.z, e.radius) do
				if t.kind == "squirrel" then
					table.insert(near, t)
				end
			end
			d.act(player, e, near)
			consumed = true
		elseif k == "light" or k == "open" or k == "playlist" or k == "kite" then
			s.on = e.on == true
			d.act(player, e)
		elseif k == "read" then
			s.read = true
			d.act(player, e)
			consumed = true
		elseif k == "throw" then
			-- it leaves the hand: whoever picks it up has it (the newspaper is litter, gone)
			if d.act(player, e) ~= false then
				d.inventory.take(player, itemId)
				local mine = self.states[keyOf(player)]
				if mine then
					mine[itemId] = nil
				end
			end
		elseif k == "place" then
			-- a chair or a cushion set down: it is in the world now (folded or picked back up with E)
			if d.act(player, e) ~= false then
				d.inventory.take(player, itemId)
			end
		else
			-- sound, vfx, write, screenshot, tape, treat: done in the world, and a use counted
			d.act(player, e)
			if k ~= "sound" then
				consumed = true
			end
		end
	end
	if consumed then
		finishUse(self, player, itemId, s)
	end
	return true, nil
end

function ItemService.new(deps: Deps): Service
	local self = setmetatable({ deps = deps, states = {}, stunUsed = {} }, Methods)
	return (self :: any) :: Service
end

return ItemService
