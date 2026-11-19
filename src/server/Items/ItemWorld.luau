--!strict
-- ServerScriptService.Server.Items.ItemWorld
-- The engine half of using a corner-store item (Items/ItemService decides; this does it in the world). Every
-- effect is plain parts, a Sound with a cue name, an attribute, a brain event or a message to the owner's
-- client; nothing runs per frame but the few things in the world that move (thrown things settle on their own;
-- STEP only looks at kites, whoopee cushions and bait every 0.1 s).
--   sound      a Sound named by its cue at the holder (SOUNDS has the ids: empty until the lead fills them from
--              the stock library; docs/AUDIO_BUDGET.md "Corner store")
--   squirt     a burst of water from the nozzle; a computer-run person hit hurries off, a player is told
--   stun       the rodent held still for the seconds: a player's through its body's StunnedUntil (its own client
--              stops its motor), the computer's in its brain
--   startle    the air horn: people hurry off, squirrels bolt, players are told
--   vfx        bubbles from the wand for a few seconds
--   light      a spotlight in the flashlight's head (bright at night, faint by day, following the clock while it
--              is on); open: the umbrella's canopy
--   playlist   the radio plays its cues one after another while it is on
--   throw      a copy of the thing flies (the engine's physics: one loose part; a frisbee glides on a small lift)
--              and lands; E picks it up; a person it hits in flight catches it. It stays its buyer's (owner, D16
--              #26; Items/Lending): the buyer has it back in their things, anyone else borrows it, in hand to throw
--              back (opts.lendTool), never in their inventory, and it goes home when they keep it too long, walk
--              off with it, change body or leave. Left lying Lending.C.groundSecs it goes home; the buyer gone, at
--              once (into their record: theirs again if they come back). The newspaper is litter: gone after 20 s.
--   write      the chalk's filtered words on the ground in front (5 minutes; 30 in the town at most)
--   tape       a strip of duct tape on what is ahead (5 minutes; 40 at most)
--   place      a lawn chair (sat in at once; E folds it back up, its owner's; one each: a second folds the first; left
--              empty CHAIR.emptySecs it folds itself; not solid, so it walls nobody off; never by a prompt) or a
--              whoopee cushion (the next person to come within a stud and a half sets it off; E picks it up: its
--              owner's back in their things, whoever picks it up; left 10 minutes or its owner gone, it goes home)
--   bait       a pile on the ground; nearby squirrels come to it (their brain's "bait"); bird seed brings birds
--   calm_dog   a dog treat: the yard dog near (opts.dogs, Wildlife/YardHazards) sits and wags and ignores squirrels
--   treat      body attributes TreatUntil (server time) and TreatScale: Client/Controllers/Human walks faster
--   read, askText, screenshot   a message to the owner's client (Client/Items/ItemClient)
--   kite       up on its string downwind of its flier, swaying; steered (Shared/Items/KiteFlight: A/D lean it
--              across the wind, W/S let the string out or reel it in; steer(player, x, y) from the flier's client,
--              clamped and rate-limited here); reeled in on the next use or out of the zone. While it is up the
--              flier (Player) carries KITE_ATTRIBUTE (Client/UI/KiteSteer plants the feet and reads the keys)
-- Interface: start(opts) -> World { service (ItemService), use(player, id, payload?), step(), putAway(player) (a
--   body change: toggles off, kite reeled in, borrowed things home), steer(player, x, y) -> boolean (taken),
--   kiteOf(player) -> Flight?, lending (Items/Lending's ledger), stop() }; stunBody(body, now, secs); isNight(hour); beamFor(night) -> (brightness, range); relight(lit,
--   night) -> count; chairs() -> ChairLedger; CHAIR; SOUNDS; KITE_ATTRIBUTE
-- Engine only inside the functions; no side effects on require.

local Import = require("../Import")
local ItemRules = Import.shared("Items/ItemRules") :: typeof(require("../../shared/Items/ItemRules"))
local Clock = Import.shared("Time/Clock") :: typeof(require("../../shared/Time/Clock"))
local PossessionState =
	Import.shared("Actors/PossessionState") :: typeof(require("../../shared/Actors/PossessionState"))
local KiteFlight = Import.shared("Items/KiteFlight") :: typeof(require("../../shared/Items/KiteFlight"))
local ItemService = require("./ItemService")
local Lending = require("./Lending")
-- (KiteFlight's exported types do not cross the Import cast)
type Flight = typeof(KiteFlight.new())
type Bucket = typeof(KiteFlight.bucket())

local ItemWorld = {}

-- cue name -> sound asset id, "rbxassetid://<n>": empty until the lead picks a sound from Roblox's licensed
-- library (no uploads; docs/AUDIO_BUDGET.md "Corner store"). Every cue of ItemRules.CUES and
-- ItemRules.RADIO_PLAYLIST has a row (tests/unit/corner_store_items.spec.luau).
local SOUNDS: { [string]: string } = {
	["Items.WaterGun"] = "rbxassetid://9125995935", -- Squirt Bottle (ProSoundEffects)
	["Items.Harmonica"] = "rbxassetid://1846183142", -- Harmonica Stings D (APM)
	["Items.BikeHorn"] = "rbxassetid://9114822511", -- Horn Blow Long Bursts 7 (ProSoundEffects)
	["Items.AirHorn"] = "rbxassetid://9114075665", -- Diesel Truck Air Horn 1 (ProSoundEffects)
	["Items.Bubbles"] = "rbxassetid://9112872239", -- Small Bubbles Float Up Pop 5 (ProSoundEffects)
	["Items.CameraClick"] = "rbxassetid://9113678227", -- Camera Shutter 1 (ProSoundEffects)
	["Items.TapeRip"] = "rbxassetid://9114886755", -- Denim Or Canvas Tears 8 (ProSoundEffects)
	["Items.Whoopee"] = "rbxassetid://9114372701", -- Airy deflate 13 (ProSoundEffects)
	["Items.SodaFizz"] = "",
	["Items.Wrapper"] = "rbxassetid://9117409740", -- Crunchy Cellophane 6 (ProSoundEffects)
	["Items.PaperRustle"] = "rbxassetid://9118835414", -- Open And Turn Pages 2 (ProSoundEffects)
	["Items.ChairUnfold"] = "rbxassetid://9114514975", -- Folding Chairs 18 (ProSoundEffects)
	["Items.Click"] = "rbxassetid://9114481274", -- Flashlight Switch 13 (ProSoundEffects)
	["Items.UmbrellaOpen"] = "rbxassetid://9114884567", -- Heavy Cloth Flap 6 (ProSoundEffects)
	["Items.Throw"] = "rbxassetid://9120742716", -- Whoosh Thick Quick 2 (ProSoundEffects)
	["Items.Chalk"] = "rbxassetid://9113781594", -- Chalkboard 9 (ProSoundEffects)
	["Items.Scatter"] = "",
	["Items.Crunch"] = "rbxassetid://9113734636", -- Celery Break 6 (ProSoundEffects)
	["Items.KiteWind"] = "rbxassetid://9114461211", -- Flag Flap 3 (ProSoundEffects)
	["Radio.Oldies1"] = "rbxassetid://1837066444", -- Sunny Side Up (Alan Hawkshaw), 70's Easy FM
	["Radio.Oldies2"] = "rbxassetid://1837066718", -- Songbird (Brian Bennett), 70's Easy FM
	["Radio.SoftRock"] = "rbxassetid://1847299654", -- Out Of Sight (David Hamer), AOR of the 70s
	["Radio.Country"] = "rbxassetid://1840347412", -- Way Out West (Richard Warren Gilks)
	["Radio.Jazz"] = "rbxassetid://1845444990", -- Coffee Break (Manfred Paulsen), big band
	["Radio.Weather"] = "rbxassetid://9042143607", -- A Million Stars, 15 s sting (Vintage Radio: 1970s)
}
ItemWorld.SOUNDS = SOUNDS

ItemWorld.KITE_ATTRIBUTE = "KiteUp" -- the flier's (Player) attribute while its kite is up and steerable

export type StartOpts = {
	inventory: any, -- Items/Inventory
	possession: any, -- Actors/Possession
	runtime: any, -- Actors/ActorsRuntime (world, byTownId)
	fire: (player: any, payload: { [string]: any }) -> (),
	zones: { any }?, -- generated/Expansion.zones (the kite's)
	-- the town's yard dogs (Wildlife/YardHazards): near(x, z, r) -> targets of kind "dog"; calm(id, secs)
	dogs: { near: (x: number, z: number, r: number) -> { any }, calm: (id: any, secs: number) -> boolean }?,
	heartbeat: boolean?,
	-- a borrowed thing's Tool in `player`'s Backpack (Items/CornerStore: the shelf's model, no ItemId so it is never
	-- counted as theirs); `use` throws it. nil: nobody else can take anything (it goes straight home)
	lendTool: ((player: any, itemId: string, ownerName: string, use: () -> ()) -> any?)?,
	now: (() -> number)?, -- seconds (default os.clock): the loans' and the ground's timers
}

export type World = {
	service: any,
	use: (player: any, itemId: string, payload: { [string]: any }?) -> (boolean, string?),
	step: () -> (),
	putAway: (player: any) -> (),
	steer: (player: any, x: any, y: any) -> boolean,
	kiteOf: (player: any) -> Flight?,
	lending: Lending.Ledger,
	stop: () -> (),
}

local function newPart(name: string, size: Vector3, cf: CFrame, color: Color3, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- The town's night for the items (the flashlight's strong beam): before 6:00 or from 19:30, game time.
function ItemWorld.isNight(hour: number): boolean
	return hour < 6 or hour >= 19.5
end

-- The flashlight's beam (brightness, range) by night or by day.
function ItemWorld.beamFor(night: boolean): (number, number)
	if night then
		return 4, 45
	end
	return 0.6, 14
end

-- Every lit beam (SpotLights in `lit`, as keys) set for the time of day; one gone or switched off leaves the set.
-- Returns how many are still lit.
function ItemWorld.relight(lit: { [any]: boolean? }, night: boolean): number
	local brightness, range = ItemWorld.beamFor(night)
	local n = 0
	for beam in lit do
		if beam.Parent == nil or not beam.Enabled then
			lit[beam] = nil
			continue
		end
		beam.Brightness, beam.Range = brightness, range
		n += 1
	end
	return n
end

ItemWorld.CHAIR = table.freeze({
	emptySecs = 180, -- a lawn chair left empty this long folds itself back into its owner's things
	promptClear = 6, -- studs: never set down this close to a prompt (a shelf, the till, a door, a game)
})

export type ChairLedger = {
	-- this owner's chair now; returns the one it replaces (to be folded), if any
	place: (owner: any, chair: any, now: number) -> any?,
	remove: (owner: any, chair: any?) -> (), -- (only that chair, when given)
	chairOf: (owner: any) -> any?,
	-- whether the owner's chair should fold now: empty for CHAIR.emptySecs (`occupied` says if anyone sits in it)
	tick: (owner: any, occupied: boolean, now: number) -> boolean,
	owners: () -> { any },
}

-- The lawn chairs out in the town, by owner (pure: ItemWorld.start does the folding).
function ItemWorld.chairs(): ChairLedger
	local byOwner: { [any]: { chair: any, emptySince: number? } } = {}
	return {
		place = function(owner: any, chair: any, now: number): any?
			local prev = byOwner[owner]
			byOwner[owner] = { chair = chair, emptySince = now }
			return if prev and prev.chair ~= chair then prev.chair else nil
		end,
		remove = function(owner: any, chair: any?)
			local r = byOwner[owner]
			if r and (chair == nil or r.chair == chair) then
				byOwner[owner] = nil
			end
		end,
		chairOf = function(owner: any): any?
			local r = byOwner[owner]
			return r and r.chair
		end,
		tick = function(owner: any, occupied: boolean, now: number): boolean
			local r = byOwner[owner]
			if r == nil then
				return false
			end
			if occupied then
				r.emptySince = nil
				return false
			end
			r.emptySince = r.emptySince or now
			return now - (r.emptySince :: number) >= ItemWorld.CHAIR.emptySecs
		end,
		owners = function(): { any }
			local out = {}
			for o in byOwner do
				table.insert(out, o)
			end
			return out
		end,
	}
end

-- A rodent's body stunned: only the deadline (server time) on it. A driving client gives its motor no input until
-- then (Controllers/Squirrel), so nothing here anchors the body, owns it or runs a timer: a release or a new driver
-- in the meantime changes nothing, and a later stun only ever lengthens it.
function ItemWorld.stunBody(body: Instance, now: number, secs: number)
	local was = body:GetAttribute(PossessionState.ATTR.StunnedUntil)
	local untilTime = now + secs
	if type(was) ~= "number" or was < untilTime then
		body:SetAttribute(PossessionState.ATTR.StunnedUntil, untilTime)
	end
end

function ItemWorld.start(opts: StartOpts): World
	local Players = game:GetService("Players")
	local Debris = game:GetService("Debris")
	local TextService = game:GetService("TextService")
	local folder = Instance.new("Folder")
	folder.Name = "CornerStoreItems"
	folder.Parent = workspace
	local clock = Clock.fromEngine()
	local possession = opts.possession
	local rt = opts.runtime
	local conns: { RBXScriptConnection } = {}
	local clockNow: () -> number = opts.now or os.clock
	local service: ItemService.Service -- (made below, once act exists; a borrowed Tool's use goes through it)
	local loans = Lending.ledger()

	local function actorOf(player: any): any?
		return possession and possession:actorOf(player)
	end
	local function rootOf(player: any): BasePart?
		local a = actorOf(player)
		local body = a and a.body
		local r = body and (body :: Model).PrimaryPart
		return r
	end
	local function toolOf(player: any, itemId: string): Tool?
		if typeof(player) ~= "Instance" then
			return nil
		end
		local p = player :: Player
		for _, holder in { p.Character, p:FindFirstChildOfClass("Backpack") } :: { Instance? } do
			for _, t in (if holder then holder:GetChildren() else {}) :: { Instance } do
				if t:IsA("Tool") and t:GetAttribute("ItemId") == itemId then
					return t
				end
			end
		end
		return nil
	end
	local function handleOf(player: any, itemId: string): BasePart?
		local t = toolOf(player, itemId)
		local h = t and t:FindFirstChild("Handle")
		return if h and h:IsA("BasePart") then h else nil
	end
	local function notify(player: any, words: string)
		opts.fire(player, { kind = "notice", text = words })
	end
	local function playCue(cue: string, at: Instance?)
		if at == nil then
			return
		end
		local s = Instance.new("Sound")
		s.Name = cue
		s.SoundId = SOUNDS[cue] or ""
		s.RollOffMaxDistance = 80
		s.Parent = at
		if s.SoundId ~= "" then
			s:Play()
		end
		Debris:AddItem(s, 6)
	end
	local function groundBelow(x: number, y: number, z: number): Vector3?
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local ex: { Instance } = { folder }
		if rt and rt.bodies then
			table.insert(ex, rt.bodies) -- every body, the computer's people and squirrels too
		end
		for _, p in Players:GetPlayers() do
			if p.Character then
				table.insert(ex, p.Character)
			end
		end
		params.FilterDescendantsInstances = ex
		local hit = workspace:Raycast(Vector3.new(x, y + 2, z), Vector3.new(0, -12, 0), params)
		if hit then
			return hit.Position
		end
		return nil
	end
	local function aheadOf(player: any, dist: number): (Vector3?, BasePart?)
		local root = rootOf(player)
		if root == nil then
			return nil, nil
		end
		local look = root.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
		return root.Position + flat * dist, root
	end
	-- a capped list of things left in the world (oldest goes first)
	local function capped(list: { Instance }, item: Instance, max: number, secs: number)
		table.insert(list, item)
		while #list > max do
			local old = table.remove(list, 1)
			if old then
				old:Destroy()
			end
		end
		Debris:AddItem(item, secs)
	end
	local writings: { Instance } = {}
	local tapes: { Instance } = {}
	local lit: { [SpotLight]: boolean? } = {} -- the flashlights switched on
	local function isNight(): boolean
		local ok, h = pcall(function()
			return clock:game().hour
		end)
		return ItemWorld.isNight(if ok then h else 12)
	end
	local chairs = ItemWorld.chairs()
	-- a lawn chair folded back up: its sitter stands, and it is back in its owner's things (unless they left)
	local function foldChair(owner: any, m: Instance, back: boolean)
		chairs.remove(owner, m)
		local seat = m:FindFirstChild("Seat")
		local sitter = if seat and seat:IsA("Seat") then seat.Occupant else nil
		if sitter then
			sitter.Sit = false
		end
		if m.Parent == nil then
			return
		end
		m:Destroy()
		if back then
			opts.inventory.add(owner, "lawn_chair") -- (by UserId: an owner who left has it again if they come back)
		end
	end
	-- whether a point is within CHAIR.promptClear of something with a prompt (a shelf, the till, a door, a game)
	local function nearPrompt(at: Vector3): boolean
		local params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = if rt and rt.bodies then { folder, rt.bodies } else { folder }
		for _, part in workspace:GetPartBoundsInRadius(at, ItemWorld.CHAIR.promptClear, params) do
			if part:FindFirstChildWhichIsA("ProximityPrompt", true) then
				return true
			end
		end
		return false
	end

	-- the town's brains, for a computer-run person, squirrel or the rodent
	local function brainOf(id: any): any?
		local world = rt and rt.world
		return world and world.brains[id]
	end
	local function playerOfTown(id: any): any?
		local actor = rt and rt.byTownId and rt.byTownId[id]
		if actor == nil then
			return nil
		end
		for _, p in Players:GetPlayers() do
			if actorOf(p) == actor then
				return p
			end
		end
		return nil
	end

	local function nearby(x: number, z: number, r: number): { ItemService.Target }
		local out: { ItemService.Target } = {}
		local world = rt and rt.world
		local r2 = r * r
		for _, a in (if world then world.actors else {}) :: { any } do
			local dx, dz = a.x - x, a.z - z
			if dx * dx + dz * dz <= r2 then
				local kind = a.species
				if a.species == "squirrel" and a.variant == "spicy" then
					kind = "rodent"
				end
				local p = playerOfTown(a.id)
				local px, py, pz = a.x, a.y, a.z
				if p then
					local held = actorOf(p)
					if held and rt and rt.placeOf and (held.species == "squirrel" or held.species == "rodent") then
						-- (a held squirrel where the server holds it, never the root its client writes: invariant D)
						px, py, pz = rt.placeOf(held)
					else
						local root = rootOf(p)
						if root then
							px, py, pz = root.Position.X, root.Position.Y, root.Position.Z
						end
					end
				end
				table.insert(out, { kind = kind, id = a.id, x = px, y = py, z = pz, player = p })
			end
		end
		-- and the yard dogs (Wildlife/YardHazards: not town actors, so asked on their own)
		if opts.dogs then
			for _, d in opts.dogs.near(x, z, r) do
				table.insert(out, d)
			end
		end
		return out
	end

	-- whose a thing is: the buyer (a Player), their Inventory key (UserId) and the name others read
	local function userKey(player: any): any
		local ok, id = pcall(function()
			return (player :: any).UserId
		end)
		return if ok and id ~= nil then id else player
	end
	local function nameOf(player: any): string
		local ok, n = pcall(function()
			return (player :: any).DisplayName
		end)
		return if ok and type(n) == "string" and n ~= "" then n else "somebody"
	end
	local function present(player: any): boolean
		return typeof(player) == "Instance" and (player :: Instance).Parent == Players
	end
	local function thingName(item: string): string
		return (string.gsub(item, "_", " "))
	end
	local function distBetween(a: any, b: any): number?
		local ra, rb = rootOf(a), rootOf(b)
		if ra == nil or rb == nil then
			return nil
		end
		return (ra.Position - rb.Position).Magnitude
	end

	-- a thing goes home: into its buyer's things (their record by UserId, whether or not they are here)
	local function sendHome(thing: Lending.Thing)
		opts.inventory.add(thing.owner, thing.item)
	end

	-- a loan ends: the borrowed Tool goes, the thing goes home, and both are told why
	local function endLoan(loan: Lending.Loan, why: string)
		if loans.take(loan.token) == nil then
			return
		end
		local tool = loan.tool
		if tool and tool.Parent then
			tool:Destroy()
		end
		local thing = loan.thing
		sendHome(thing)
		local what = thingName(thing.item)
		if present(thing.owner) then
			notify(thing.owner, Lending.say(Lending.WORDS.home, what))
		end
		if present(loan.holder) then
			local words = if why == "ownerGone" then Lending.WORDS.ownerLeft else Lending.WORDS.wentHome
			notify(loan.holder, Lending.say(words, thing.ownerName, what))
		end
	end

	-- somebody else's thing into `who`'s hand, to throw back (or straight home when no Tool can be made)
	local function lend(who: any, thing: Lending.Thing, caught: boolean)
		local loan = loans.lend(who, thing, clockNow(), distBetween(who, thing.owner))
		local token = loan.token
		local tool = if opts.lendTool
			then opts.lendTool(who, thing.item, thing.ownerName, function()
				if service then
					service:use(who, thing.item, { lent = token })
				end
			end)
			else nil
		if tool == nil then
			endLoan(loan, "noTool")
			return
		end
		loan.tool = tool
		local what = thingName(thing.item)
		local words = if caught then Lending.WORDS.caught else Lending.WORDS.picked
		notify(who, Lending.say(words, thing.ownerName, what, Lending.C.holdSecs))
		if present(thing.owner) then
			notify(thing.owner, Lending.say(Lending.WORDS.borrowed, nameOf(who), what))
		end
	end

	-- things thrown and not yet picked up (each goes home after Lending.C.groundSecs, or at once with its buyer gone)
	type Thrown = { model: Model, thing: Lending.Thing, at: number, taken: boolean, touch: RBXScriptConnection? }
	local thrown: { Thrown } = {}

	-- a thrown thing, flying then lying where it lands until someone picks it up; still its buyer's (Items/Lending)
	local function throw(player: any, e: { [string]: any }): boolean
		local loan = if e.lent ~= nil then loans.get(e.lent) else nil
		if e.lent ~= nil and (loan == nil or (loan :: Lending.Loan).holder ~= player) then
			return false
		end
		local tool: any = if loan then loan.tool else toolOf(player, e.item)
		local root = rootOf(player)
		if tool == nil or tool.Parent == nil or root == nil then
			return false
		end
		local model = Instance.new("Model")
		model.Name = "Thrown_" .. e.item
		local main: BasePart? = nil
		for _, c in tool:GetChildren() do
			if c:IsA("BasePart") then
				local p = c:Clone()
				for _, w in p:GetChildren() do
					if w:IsA("WeldConstraint") then
						w:Destroy()
					end
				end
				p.Anchored = false
				p.CanQuery = true
				p.Parent = model
				if main == nil then
					main = p
					p.CanCollide = true
					p.Massless = false
				else
					p.CanCollide = false
					p.Massless = true
					local w = Instance.new("WeldConstraint")
					w.Part0 = main
					w.Part1 = p
					w.Parent = p
				end
			end
		end
		if main == nil then
			model:Destroy()
			return false
		end
		local m = main :: BasePart
		local look = root.CFrame.LookVector
		local start = root.Position + look * 2.5 + Vector3.new(0, 1.5, 0)
		model.Parent = folder
		model:PivotTo(CFrame.new(start) * m.CFrame.Rotation)
		m:SetNetworkOwner(nil)
		m.AssemblyLinearVelocity = (look * (1 - e.lift) + Vector3.new(0, e.lift, 0)).Unit * e.speed
		if e.item == "frisbee" then
			-- a frisbee glides: a small upward push against gravity while it is fast
			local att = Instance.new("Attachment")
			att.Parent = m
			local lift = Instance.new("VectorForce")
			lift.Attachment0 = att
			lift.RelativeTo = Enum.ActuatorRelativeTo.World
			lift.Force = Vector3.new(0, m.AssemblyMass * workspace.Gravity * 0.6, 0)
			lift.Parent = m
			m.AssemblyAngularVelocity = Vector3.new(0, 18, 0)
			task.delay(1.6, function()
				lift:Destroy()
			end)
		end
		tool:Destroy()
		if e.item == "newspaper" then
			Debris:AddItem(model, 20)
			return true
		end
		-- whose it is: a borrowed one is still its buyer's (the loan ends as it leaves the hand)
		local thing: Lending.Thing = if loan
			then loan.thing
			else { item = e.item, owner = player, ownerKey = userKey(player), ownerName = nameOf(player) }
		if loan then
			loans.take(loan.token)
		end
		local t: Thrown = { model = model, thing = thing, at = clockNow(), taken = false, touch = nil }
		table.insert(thrown, t)
		local thrower = player
		local function give(to: any, caught: boolean)
			if t.taken then
				return
			end
			t.taken = true
			if t.touch then
				t.touch:Disconnect()
			end
			model:Destroy()
			-- its buyer has it back; a thing the game gave is kept; anyone else borrows it
			if Lending.pickUp(ItemRules.findersKeep(thing.item), thing.ownerKey, userKey(to)) == "lend" then
				lend(to, thing, caught)
			else
				opts.inventory.add(to, thing.item)
			end
		end
		-- a person it hits in flight catches it (not the one who just threw it; its buyer catching it has it back)
		t.touch = m.Touched:Connect(function(other: BasePart)
			if t.taken or m.AssemblyLinearVelocity.Magnitude < 4 then
				return
			end
			local who = Players:GetPlayerFromCharacter(other:FindFirstAncestorOfClass("Model"))
			if who and who ~= thrower then
				local a = actorOf(who)
				if a and a.species == "human" then
					if userKey(who) == thing.ownerKey then
						notify(who, "Caught it!")
					end
					give(who, true)
				end
			end
		end)
		m.CanTouch = true
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Pick up"
		prompt.ObjectText = `{thing.ownerName}'s {thingName(thing.item)}`
		prompt.RequiresLineOfSight = false
		prompt.MaxActivationDistance = 8
		prompt.Parent = m
		prompt.Triggered:Connect(function(who: Player)
			local a = actorOf(who)
			if a and a.species == "human" then
				give(who, false)
			end
		end)
		return true
	end

	-- kites in the air: flier, model, string ends, phase, the steering (Shared/Items/KiteFlight)
	type Kite = {
		player: any,
		model: Model,
		a0: Attachment,
		a1: Attachment,
		t: number,
		reel: number?,
		flight: Flight,
	}
	local kites: { Kite } = {}
	-- each flier's steer packets (the bucket outlives a flight: a new kite is no way round the rate)
	local buckets: { [any]: Bucket } = {}
	local function flierAttr(player: any, on: boolean)
		if typeof(player) == "Instance" then
			(player :: Player):SetAttribute(ItemWorld.KITE_ATTRIBUTE, if on then true else nil)
		end
	end
	-- whoopee cushions waiting for a sitter
	-- (each still its owner's: picked up by anyone it goes home; left CUSHION_SECS or its owner gone, too)
	type Cushion = { part: BasePart, owner: any, armed: boolean, at: number }
	local cushions: { Cushion } = {}
	local CUSHION_SECS = 600
	-- a whoopee cushion off the ground and back in its owner's things (`by`: who picked it up, if not its owner)
	local function cushionHome(c: Cushion, by: any?)
		if c.part.Parent == nil then
			return
		end
		c.part:Destroy()
		opts.inventory.add(c.owner, "whoopee_cushion")
		if by ~= nil and present(by) then
			notify(by, Lending.say(Lending.WORDS.returned, "whoopee cushion", nameOf(c.owner)))
		end
		if by ~= nil and present(c.owner) then
			notify(c.owner, Lending.say(Lending.WORDS.placedHome, nameOf(by), "whoopee cushion"))
		end
	end
	-- baits on the ground, and the birds at them
	type Bait = { part: BasePart, birds: { BasePart }, untilT: number, t: number }
	local baits: { Bait } = {}

	local function kiteDown(k: Kite)
		if k.reel == nil then
			k.reel = 0
			flierAttr(k.player, false)
		end
	end

	local function act(player: any, e: { [string]: any }, targets: { ItemService.Target }?): boolean?
		local kind = e.kind
		local root = rootOf(player)
		if kind == "sound" then
			playCue(e.cue, root)
		elseif kind == "squirt" then
			local h = handleOf(player, "water_gun")
			if h then
				local att = Instance.new("Attachment")
				att.Parent = h
				local pe = Instance.new("ParticleEmitter")
				pe.Color = ColorSequence.new(Color3.fromRGB(150, 200, 255))
				pe.Speed = NumberRange.new(30, 36)
				pe.Lifetime = NumberRange.new(0.3, 0.45)
				pe.Size = NumberSequence.new(0.2)
				pe.SpreadAngle = Vector2.new(3, 3)
				pe.Acceleration = Vector3.new(0, -40, 0)
				pe.EmissionDirection = Enum.NormalId.Front
				pe.Enabled = false
				pe.Parent = att
				pe:Emit(24)
				Debris:AddItem(att, 1.5)
			end
			playCue(ItemRules.CUES.water_gun, root)
			for _, t in (targets or {}) :: { ItemService.Target } do
				if t.player then
					notify(t.player, "You got squirted!")
				elseif t.kind == "human" and root then
					local b = brainOf(t.id)
					if b then
						b:onEvent({
							type = "witness",
							threat = { x = root.Position.X, z = root.Position.Z },
							alert = 2,
						})
					end
				end
			end
		elseif kind == "stun" then
			for _, t in (targets or {}) :: { ItemService.Target } do
				if t.player then
					-- a player's body moves on its own client (never anchored here: that would freeze only the
					-- server's copy and take the body off its client): the deadline on the body, which the
					-- client's controller honours by giving its motor no input until then (Controllers/Squirrel)
					local a = actorOf(t.player)
					if a and a.body then
						ItemWorld.stunBody(a.body, workspace:GetServerTimeNow(), e.secs)
						notify(t.player, "Squirted! Stunned for a moment.")
					end
				else
					-- the computer's rodent: its own brain holds it (never Possession's suspend, which a player
					-- taking the body in the meantime also uses); the body carries the deadline too, so a player
					-- who takes it before then stands for the rest
					local world = rt and rt.world
					local b = brainOf(t.id)
					if world and b then
						b:onEvent({ type = "stun", untilTime = world.now + e.secs })
					end
					local actor = rt and rt.byTownId and rt.byTownId[t.id]
					if actor and actor.body then
						ItemWorld.stunBody(actor.body, workspace:GetServerTimeNow(), e.secs)
					end
				end
			end
		elseif kind == "startle" then
			for _, t in (targets or {}) :: { ItemService.Target } do
				if t.player and t.player ~= player then
					notify(t.player, "AIR HORN! You nearly jump out of your skin.")
				elseif t.player == nil and root then
					local b = brainOf(t.id)
					if b and (t.kind == "squirrel" or t.kind == "rodent") then
						b:onEvent({ type = "startle", x = root.Position.X, z = root.Position.Z })
					elseif b and t.kind == "human" then
						b:onEvent({
							type = "witness",
							threat = { x = root.Position.X, z = root.Position.Z },
							alert = 3,
						})
					end
				end
			end
		elseif kind == "vfx" then
			local h = handleOf(player, "bubbles")
			if h then
				local att = Instance.new("Attachment")
				att.Position = Vector3.new(0, h.Size.Y / 2 + 0.6, 0)
				att.Parent = h
				local pe = Instance.new("ParticleEmitter")
				pe.Color = ColorSequence.new(Color3.fromRGB(220, 240, 255), Color3.fromRGB(255, 200, 250))
				pe.Transparency = NumberSequence.new(0.35)
				pe.LightEmission = 0.3
				pe.Rate = 10
				pe.Speed = NumberRange.new(2, 4)
				pe.Lifetime = NumberRange.new(2, 3.5)
				pe.Size = NumberSequence.new(0.25, 0.5)
				pe.Acceleration = Vector3.new(0, 1.2, 0)
				pe.SpreadAngle = Vector2.new(35, 35)
				pe.Parent = att
				task.delay(e.secs, function()
					pe.Enabled = false
				end)
				Debris:AddItem(att, e.secs + 4)
			end
			playCue(ItemRules.CUES.bubbles, root)
		elseif kind == "light" then
			local h = handleOf(player, "flashlight")
			if h then
				local beam = h:FindFirstChild("Beam") :: SpotLight?
				if beam == nil then
					local s = Instance.new("SpotLight")
					s.Name = "Beam"
					s.Face = Enum.NormalId.Top
					s.Angle = 40
					s.Shadows = false
					s.Parent = h
					beam = s
				end
				local b = beam :: SpotLight
				b.Enabled = e.on == true
				b.Brightness, b.Range = ItemWorld.beamFor(e.strong == true)
				-- (a lit one follows the time of day: dusk brightens it, dawn dims it; step)
				lit[b] = if b.Enabled then true else nil
			end
		elseif kind == "open" then
			local t = toolOf(player, "umbrella")
			local canopy = t and t:FindFirstChild("OpenCanopy")
			if canopy and canopy:IsA("BasePart") then
				canopy.Transparency = if e.on then 0 else 1
			end
			playCue(ItemRules.CUES.umbrella, root)
		elseif kind == "playlist" then
			local h = handleOf(player, "radio")
			if h then
				local s = h:FindFirstChild("RadioSound") :: Sound?
				if s == nil then
					local snd = Instance.new("Sound")
					snd.Name = "RadioSound"
					snd.RollOffMaxDistance = 60
					snd.Volume = 0.6
					snd.Parent = h
					s = snd
					local i = 0
					-- one track after another, round the playlist, while it is on
					snd.Ended:Connect(function()
						if snd:GetAttribute("On") then
							i = i % #e.tracks + 1
							snd:SetAttribute("Track", e.tracks[i])
							snd.SoundId = SOUNDS[e.tracks[i]] or ""
							if snd.SoundId ~= "" then
								snd:Play()
							end
						end
					end)
				end
				local snd = s :: Sound
				snd:SetAttribute("On", e.on == true)
				if e.on then
					snd:SetAttribute("Track", e.tracks[1])
					snd.SoundId = SOUNDS[e.tracks[1]] or ""
					if snd.SoundId ~= "" then
						snd:Play()
					end
					notify(player, "Radio on: " .. string.gsub(e.tracks[1], "^Radio%.", ""))
				else
					snd:Stop()
				end
			end
		elseif kind == "throw" then
			return throw(player, e)
		elseif kind == "read" then
			notify(player, `PEPPER'S GAZETTE: {e.headline}`)
			playCue(ItemRules.CUES.newspaper, root)
		elseif kind == "askText" or kind == "screenshot" then
			opts.fire(player, { kind = "item", action = kind, item = e.item, max = e.max, left = e.left })
			if kind == "screenshot" then
				playCue(ItemRules.CUES.camera, root)
			end
		elseif kind == "write" then
			local at = aheadOf(player, 3)
			local g = at and groundBelow(at.X, at.Y, at.Z)
			if g == nil or root == nil then
				return false
			end
			local look = root.CFrame.LookVector
			local yaw = math.atan2(-look.X, -look.Z)
			local w = math.clamp(utf8.len(e.text) or #e.text, 4, 20) * 0.9
			local p = newPart(
				"Chalk",
				Vector3.new(w, 0.05, 2),
				CFrame.new(g + Vector3.new(0, 0.03, 0)) * CFrame.Angles(0, yaw, 0),
				Color3.new(1, 1, 1),
				folder
			)
			p.Transparency = 1
			local gui = Instance.new("SurfaceGui")
			gui.Face = Enum.NormalId.Top
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 40
			gui.Parent = p
			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.Size = UDim2.fromScale(1, 1)
			label.Text = e.text
			label.TextScaled = true
			label.FontFace = Font.fromEnum(Enum.Font.PatrickHand)
			label.TextColor3 = Color3.fromRGB(250, 240, 250)
			label.Rotation = 180
			label.Parent = gui
			capped(writings, p, 30, 300)
		elseif kind == "tape" then
			if root == nil then
				return false
			end
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { folder, (root :: BasePart).Parent :: Instance }
			local hit = workspace:Raycast(root.Position, root.CFrame.LookVector * e.reach, params)
			if hit == nil then
				notify(player, "Nothing close enough to tape.")
				return false
			end
			local cf = CFrame.lookAt(hit.Position + hit.Normal * 0.02, hit.Position + hit.Normal)
			local p = newPart("Tape", Vector3.new(1.6, 0.35, 0.03), cf, Color3.fromRGB(170, 172, 178), folder)
			p.Material = Enum.Material.Fabric
			capped(tapes, p, 40, 300)
		elseif kind == "place" then
			local at = aheadOf(player, if e.prop == "lawn_chair" then 3 else 2.5)
			local g = at and groundBelow(at.X, at.Y, at.Z)
			if g == nil or root == nil then
				notify(player, "No room to put it down here.")
				return false
			end
			local look = root.CFrame.LookVector
			local yaw = math.atan2(look.X, look.Z)
			if e.prop == "lawn_chair" and nearPrompt(g) then
				notify(player, "Not here: you would be in everyone's way.")
				return false
			end
			if e.prop == "lawn_chair" then
				local m = Instance.new("Model")
				m.Name = "LawnChair"
				local base = CFrame.new(g) * CFrame.Angles(0, yaw + math.pi, 0)
				local seat = Instance.new("Seat")
				seat.Name = "Seat"
				seat.Size = Vector3.new(2, 0.3, 1.8)
				seat.CFrame = base * CFrame.new(0, 1.0, 0)
				seat.Color = Color3.fromRGB(60, 150, 90)
				seat.Anchored = true
				seat.CanCollide = false -- (sat in by Seat:Sit; never a wall)
				seat.Material = Enum.Material.Fabric
				seat.Parent = m
				newPart(
					"Back",
					Vector3.new(2, 2, 0.15),
					base * CFrame.new(0, 2.0, 0.9),
					Color3.fromRGB(250, 200, 60),
					m
				)
				newPart(
					"Frame",
					Vector3.new(2.1, 0.12, 2),
					base * CFrame.new(0, 0.5, 0),
					Color3.fromRGB(200, 202, 208),
					m
				)
				m.Parent = folder
				local owner = player
				local fold = Instance.new("ProximityPrompt")
				fold.ActionText = "Fold up"
				fold.ObjectText = "Lawn chair"
				fold.HoldDuration = 0.4
				fold.RequiresLineOfSight = false
				fold.MaxActivationDistance = 7
				fold.Parent = seat
				fold.Triggered:Connect(function(who: Player)
					if who ~= owner then
						notify(who, "That is somebody's chair.")
						return
					end
					foldChair(owner, m, true)
				end)
				-- one each: a chair already out folds back up
				local prev = chairs.place(owner, m, os.clock())
				if prev then
					foldChair(owner, prev, true)
				end
				-- its owner sits down in it at once
				local holder = actorOf(player)
				local body = if holder then holder.body else nil
				local hum = body and body:FindFirstChildOfClass("Humanoid")
				if hum then
					task.defer(function()
						seat:Sit(hum)
					end)
				end
			else
				local p = newPart(
					"WhoopeeCushion",
					Vector3.new(1.2, 0.25, 1.2),
					CFrame.new(g + Vector3.new(0, 0.12, 0)),
					Color3.fromRGB(255, 120, 160),
					folder
				)
				p.Shape = Enum.PartType.Cylinder
				p.CFrame = CFrame.new(g + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.pi / 2)
				local c: Cushion = { part = p, owner = player, armed = true, at = clockNow() }
				table.insert(cushions, c)
				local prompt = Instance.new("ProximityPrompt")
				prompt.ActionText = "Pick up"
				prompt.ObjectText = `{nameOf(player)}'s whoopee cushion`
				prompt.RequiresLineOfSight = false
				prompt.MaxActivationDistance = 6
				prompt.Parent = p
				prompt.Triggered:Connect(function(who: Player)
					local a = actorOf(who)
					if p.Parent and a and a.species == "human" then
						if userKey(who) == userKey(c.owner) or ItemRules.findersKeep("whoopee_cushion") then
							p:Destroy()
							opts.inventory.add(who, "whoopee_cushion")
						else
							cushionHome(c, who) -- (somebody else's: it goes home, owner D16 #26)
						end
					end
				end)
			end
			playCue(ItemRules.CUES[if e.prop == "lawn_chair" then "lawn_chair" else "whoopee_cushion"], root)
		elseif kind == "bait" then
			if root == nil then
				return false
			end
			local g = groundBelow(root.Position.X, root.Position.Y, root.Position.Z) or root.Position
			local p = newPart(
				"Bait",
				Vector3.new(1.4, 0.2, 1.4),
				CFrame.new(g + Vector3.new(0, 0.1, 0)),
				if e.item == "bird_seed" then Color3.fromRGB(214, 190, 120) else Color3.fromRGB(170, 120, 70),
				folder
			)
			local world = rt and rt.world
			local untilT = (world and world.now or 0) + e.secs
			for _, t in (targets or {}) :: { ItemService.Target } do
				local b = brainOf(t.id)
				if b and t.player == nil then
					b:onEvent({ type = "bait", x = g.X, z = g.Z, untilTime = untilT })
				end
			end
			local birds: { BasePart } = {}
			for i = 1, e.birds or 0 do
				local a = i * 2.1
				local bird = newPart(
					"Bird",
					Vector3.new(0.5, 0.45, 0.8),
					CFrame.new(g + Vector3.new(math.cos(a) * 3, 0.25, math.sin(a) * 3)),
					Color3.fromRGB(110, 100, 95),
					folder
				)
				bird.Shape = Enum.PartType.Ball
				table.insert(birds, bird)
			end
			table.insert(baits, { part = p :: BasePart, birds = birds, untilT = os.clock() + e.secs, t = 0 } :: Bait)
		elseif kind == "calm_dog" then
			-- a dog treat: the nearest dog (ItemService picked it) sits and wags, deaf to squirrels for a while
			local calmed = false
			for _, t in (targets or {}) :: { ItemService.Target } do
				if t.kind == "dog" and opts.dogs and opts.dogs.calm(t.id, e.secs) then
					calmed = true
				end
			end
			if not calmed then
				return false
			end
			notify(player, "The dog sits and wags its tail. It will leave the squirrels alone for a while.")
		elseif kind == "treat" then
			local a = actorOf(player)
			local body = a and a.body
			if body then
				body:SetAttribute("TreatUntil", workspace:GetServerTimeNow() + e.secs)
				body:SetAttribute("TreatScale", e.scale)
			end
			playCue(ItemRules.CUES.soda, root)
		elseif kind == "kite" then
			for _, k in kites do
				if k.player == player then
					kiteDown(k)
					return true
				end
			end
			local tool = toolOf(player, "kite")
			local hand = tool and tool:FindFirstChild("Handle")
			if tool == nil or hand == nil or root == nil then
				notify(player, "Hold the kite to fly it.")
				return false
			end
			local m = Instance.new("Model")
			m.Name = "Kite"
			for _, c in tool:GetChildren() do
				if c:IsA("BasePart") then
					local p = c:Clone()
					p.Anchored = true
					for _, w in p:GetChildren() do
						if w:IsA("WeldConstraint") then
							w:Destroy()
						end
					end
					p.Parent = m
				end
			end
			m.Parent = folder
			local first = m:FindFirstChildWhichIsA("BasePart") :: BasePart
			m.PrimaryPart = first
			local a0 = Instance.new("Attachment")
			a0.Parent = hand
			local a1 = Instance.new("Attachment")
			a1.Parent = first
			local beam = Instance.new("Beam")
			beam.Attachment0 = a0
			beam.Attachment1 = a1
			beam.Width0, beam.Width1 = 0.05, 0.05
			beam.Color = ColorSequence.new(Color3.fromRGB(240, 240, 230))
			beam.CurveSize0 = -4
			beam.FaceCamera = true
			beam.Parent = first
			-- the tool's own model is hidden while its copy flies (the string runs from the hand)
			for _, c in tool:GetChildren() do
				if c:IsA("BasePart") then
					c.Transparency = 1
				end
			end
			table.insert(kites, { player = player, model = m, a0 = a0, a1 = a1, t = 0, flight = KiteFlight.new() })
			flierAttr(player, true)
			notify(player, "Up she goes! A and D steer, W and S let out and reel in. Use it again to bring it down.")
		end
		return true
	end

	service = ItemService.new({
		inventory = opts.inventory,
		lent = {
			holds = function(player: any, id: string, token: any): boolean
				return loans.holds(player, id, token)
			end,
		},
		now = function(): number
			return os.clock()
		end,
		pose = function(player: any): ItemService.Pose?
			local r = rootOf(player)
			if r == nil then
				return nil
			end
			local look = r.CFrame.LookVector
			local flat = Vector3.new(look.X, 0, look.Z)
			flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
			return { x = r.Position.X, y = r.Position.Y, z = r.Position.Z, lx = flat.X, lz = flat.Z }
		end,
		speciesOf = function(player: any): string?
			local a = actorOf(player)
			return if a and a.body then a.species else nil
		end,
		night = isNight,
		zoneAt = function(x: number, z: number): string?
			return ItemService.kiteZoneAt(opts.zones, x, z)
		end,
		nearby = nearby,
		filter = function(player: any, text: string): string?
			if typeof(player) ~= "Instance" then
				return nil
			end
			local ok, result = pcall(function()
				local f = TextService:FilterStringAsync(text, (player :: Player).UserId)
				return f:GetNonChatStringForBroadcastAsync()
			end)
			return if ok then result else nil
		end,
		notify = notify,
		refuse = function(player: any, words: string)
			opts.fire(player, { kind = "refused", text = words })
		end,
		act = act,
	})

	-- a body change put the player's things back in the Backpack: whatever was on goes off (the flashlight's beam,
	-- the radio, the umbrella's canopy) and a kite in the air is reeled in, so the next use starts afresh
	local function putAway(player: any)
		service:putAway(player)
		local torch = handleOf(player, "flashlight")
		local beam = torch and torch:FindFirstChild("Beam")
		if beam and beam:IsA("SpotLight") then
			beam.Enabled = false
		end
		local radio = handleOf(player, "radio")
		local snd = radio and radio:FindFirstChild("RadioSound")
		if snd and snd:IsA("Sound") then
			snd:SetAttribute("On", false)
			snd:Stop()
		end
		local umbrella = toolOf(player, "umbrella")
		local canopy = umbrella and umbrella:FindFirstChild("OpenCanopy")
		if canopy and canopy:IsA("BasePart") then
			canopy.Transparency = 1
		end
		for _, k in kites do
			if k.player == player then
				kiteDown(k)
			end
		end
		-- borrowed things do not change bodies with their borrower: they go home
		for _, loan in loans.of(player) do
			endLoan(loan, "holderGone")
		end
	end

	local relightIn = 0
	local function step()
		-- lit flashlights follow the time of day (once a second is plenty for a dusk)
		relightIn -= 1
		if relightIn <= 0 and next(lit) ~= nil then
			relightIn = 10
			ItemWorld.relight(lit, isNight())
		end
		-- kites: up on the string downwind, steered by its flier, swaying; reeled in on a second use, out of the
		-- zone or without a flier
		local now = os.clock()
		for i = #kites, 1, -1 do
			local k = kites[i]
			local root = rootOf(k.player)
			-- flown only while held (in the hand, not put away in the Backpack) in the park or on the beach
			local held = toolOf(k.player, "kite")
			local inZone = root ~= nil
				and ItemService.kiteZoneAt(opts.zones, root.Position.X, root.Position.Z) ~= nil
				and held ~= nil
				and held.Parent ~= nil
				and (held.Parent :: Instance):IsA("Model")
			if not inZone then
				kiteDown(k)
			end
			k.t += 0.1
			local up = math.min(1, k.t / KiteFlight.LAUNCH_SECS)
			if k.reel then
				k.reel += 0.1
				up = math.max(0, 1 - k.reel / KiteFlight.REEL_SECS) * up
			else
				KiteFlight.step(k.flight, 0.1, now)
			end
			if root then
				local dx, dy, dz = KiteFlight.offset(k.flight, k.t)
				local pos = root.Position + Vector3.new(dx * up, (dy - KiteFlight.HAND) * up + KiteFlight.HAND, dz * up)
				local face = CFrame.lookAt(pos, root.Position) * CFrame.Angles(0, 0, math.sin(k.t * 1.3) * 0.25)
				k.model:PivotTo(face)
			end
			if (k.reel and k.reel >= KiteFlight.REEL_SECS) or root == nil then
				k.model:Destroy()
				k.a0:Destroy()
				flierAttr(k.player, false)
				local tool = toolOf(k.player, "kite")
				for _, c in (if tool then tool:GetChildren() else {}) :: { Instance } do
					if c:IsA("BasePart") then
						c.Transparency = 0
					end
				end
				table.remove(kites, i)
			end
		end
		for p in buckets do
			if typeof(p) == "Instance" and p.Parent ~= Players then
				buckets[p] = nil
			end
		end
		-- lawn chairs: an owner who left takes theirs along; one left empty long enough folds itself up
		for _, owner in chairs.owners() do
			local m = chairs.chairOf(owner)
			if m == nil or m.Parent == nil then
				chairs.remove(owner)
				continue
			end
			if owner.Parent ~= Players then
				foldChair(owner, m, true) -- (into their record: theirs again if they come back)
				continue
			end
			local seat = m:FindFirstChild("Seat")
			local occupied = seat ~= nil and seat:IsA("Seat") and seat.Occupant ~= nil
			if chairs.tick(owner, occupied, os.clock()) then
				foldChair(owner, m, true)
				notify(owner, "Your lawn chair folded itself up: it is back in your things.")
			end
		end
		-- borrowed things: home when kept too long, walked off with, or either player gone (Items/Lending)
		local tNow = clockNow()
		for _, loan in loans.all() do
			local tool = loan.tool
			local holder = loan.holder
			local a = actorOf(holder)
			local holding = tool ~= nil
				and tool.Parent ~= nil
				and present(holder)
				and a ~= nil
				and a.species == "human"
				and a.body ~= nil
			local why = Lending.due(loan, tNow, {
				ownerHere = present(loan.thing.owner),
				holderHere = holding,
				dist = distBetween(holder, loan.thing.owner),
			})
			if why then
				endLoan(loan, why)
			end
		end
		-- thrown things lying about: home after Lending.C.groundSecs, at once if the buyer has left
		for i = #thrown, 1, -1 do
			local th = thrown[i]
			if th.taken or th.model.Parent == nil then
				table.remove(thrown, i)
				continue
			end
			local here = present(th.thing.owner)
			if not here or tNow - th.at >= Lending.C.groundSecs then
				th.taken = true
				if th.touch then
					th.touch:Disconnect()
				end
				th.model:Destroy()
				table.remove(thrown, i)
				sendHome(th.thing)
				if here then
					notify(th.thing.owner, Lending.say(Lending.WORDS.home, thingName(th.thing.item)))
				end
			end
		end
		-- whoopee cushions: the next person within a stud and a half (not the one who put it down) sets it off; one
		-- left long enough, or whose owner left, goes home
		for i = #cushions, 1, -1 do
			local c = cushions[i]
			if c.part.Parent ~= nil and (not present(c.owner) or tNow - c.at >= CUSHION_SECS) then
				cushionHome(c, nil)
			end
			if c.part.Parent == nil then
				table.remove(cushions, i)
				continue
			end
			if not c.armed then
				continue
			end
			local p = c.part.Position
			for _, t in nearby(p.X, p.Z, 1.5) do
				if t.kind == "human" and t.player ~= c.owner then
					c.armed = false
					playCue(ItemRules.CUES.whoopee_cushion, c.part)
					c.part.Size = Vector3.new(0.1, 1.2, 1.2)
					if t.player then
						notify(t.player, "PFFFT! Somebody left a whoopee cushion.")
					end
					if typeof(c.owner) == "Instance" and c.owner.Parent == Players then
						notify(c.owner, "Your whoopee cushion went off!")
					end
					break
				end
			end
		end
		-- baits: the birds hop about the pile; it is gone when its time is up
		for i = #baits, 1, -1 do
			local b = baits[i]
			b.t += 0.1
			if now >= b.untilT or b.part.Parent == nil then
				b.part:Destroy()
				for _, bird in b.birds do
					bird:Destroy()
				end
				table.remove(baits, i)
				continue
			end
			local c = b.part.Position
			for j, bird in b.birds do
				local a = b.t * 0.4 + j * 2.1
				local hop = math.max(0, math.sin(b.t * 6 + j)) * 0.4
				bird.CFrame = CFrame.new(c + Vector3.new(math.cos(a) * 2.2, 0.25 + hop, math.sin(a) * 2.2))
			end
		end
	end

	if opts.heartbeat ~= false then
		local acc = 0
		table.insert(
			conns,
			game:GetService("RunService").Heartbeat:Connect(function(dt: number)
				acc += dt
				if acc >= 0.1 then
					acc = 0
					step()
				end
			end)
		)
	end

	return {
		service = service,
		use = function(player: any, itemId: string, payload: { [string]: any }?): (boolean, string?)
			return service:use(player, itemId, payload)
		end,
		step = step,
		putAway = putAway,
		-- the flier's keys (Client/UI/KiteSteer over Items/CornerStore's remote): clamped, rate-limited, and only
		-- for a kite that is up (not one coming down)
		steer = function(player: any, x: any, y: any): boolean
			for _, k in kites do
				if k.player == player and k.reel == nil then
					local b = buckets[player]
					if b == nil then
						b = KiteFlight.bucket()
						buckets[player] = b
					end
					if not KiteFlight.accept(b, os.clock()) then
						return false
					end
					KiteFlight.steer(k.flight, x, y, os.clock())
					return true
				end
			end
			return false
		end,
		lending = loans,
		kiteOf = function(player: any): Flight?
			for _, k in kites do
				if k.player == player and k.reel == nil then
					return k.flight
				end
			end
			return nil
		end,
		stop = function()
			for _, c in conns do
				c:Disconnect()
			end
			for _, k in kites do
				flierAttr(k.player, false) -- (the flier's controls come back)
			end
			for _, loan in loans.all() do
				endLoan(loan, "stopped") -- (no borrowed Tool outlives the world; the thing goes home)
			end
			for _, th in thrown do
				if not th.taken then
					th.taken = true
					sendHome(th.thing)
				end
			end
			for _, c in cushions do
				cushionHome(c, nil)
			end
			for _, owner in chairs.owners() do
				local m = chairs.chairOf(owner)
				if m then
					foldChair(owner, m, true)
				end
			end
			folder:Destroy()
		end,
	}
end

return ItemWorld
