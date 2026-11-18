--!strict
-- ServerScriptService.Server.Attractions.LoungeService
-- THE GILDED ACORN, the 1940s lounge (f3_lounge_classic; brief v2 "Lounge one", addendum D14), the server half.
-- The rules are Shared/Attractions/LoungeClassic; the building is the bake (Workspace.Expansion.LoungeClassic,
-- tools/bake/lounge_classic), sealed: the door's prompt is the only way in or out.
--   * The door (E, outside on the landing): a person with the pass (the wallet's one pass, paintball and both
--     lounges: wallet.pass) is put just inside, facing the room, told "Welcome"; one without it is told "Members
--     only." and the pass's offer, and the podium beside the door sells it (wallet.pass.buy: server-authoritative,
--     the wallet's own words; bought, the person goes straight in). A squirrel or the Spicy Rodent pressing it meets
--     the guards; a fox or a deer is turned away. Inside, E at the door puts the person back on the landing.
--   * First person: a body the service lets in carries CameraZone = "lockFirstPerson" (Client/Camera/CameraPolicy
--     locks the camera) and Lounge = the venue id (Client/World/LoungeMusic plays the jazz); both are cleared at
--     the door, and whenever the body is found outside the room (a knock-out elsewhere). A body its player lets go
--     of inside (a new body picked, the player gone) is put out on the landing, so no computer brain is ever shut
--     in the sealed room.
--   * The guards (the bake's Staff.Guard1, Guard2): every TICK seconds any squirrel-family body, a player's or a
--     computer's, on the forecourt, in the entry or (should one ever be) in the room is knocked out by the nearest
--     guard: town.knockOut(actor), Boot/Game's kill with cause "guard" (its player back to the menu with "THE
--     GUARDS!", a computer squirrel back where it lives; the game's own knock-out, nothing shown but a swat). The
--     guard steps toward it and back (STRIKE seconds). This is what the brief's "annihilate" maps to.
--   * The bar (four prompts along its front): a hot cocoa, a coffee, a green tea or a snow cone at the wallet's
--     price (wallet.buy: the money goes only when the drink is handed over); the bartender turns to the customer;
--     the drink is held in the right hand (a cup or a paper cone welded to the body's root) and sipped SIPS times,
--     one every SIP_EVERY seconds (the cup goes up to the face for SIP_HOLD), then "All gone." One at a time.
--     People have no stamina in this game: a drink is for the look. It goes with its holder at the door.
-- Sounds: named cue points only (Sound instances with empty ids, never synthesised): CUES. The jazz is the client's.
-- Engine only inside the functions; no side effects on require. Steppable: step() reads the clock it was given.
-- The joiner's lines in Boot/Game.start: lounge = LoungeService.start({ town = LoungeService.gameTown({ ... }),
--   heartbeat = o.heartbeat ~= false, terrain = o.terrain ~= false }); lounge:step() when heartbeat == false.
-- Interface: start(opts) -> Service; new(opts) -> Service; gameTown(parts) -> Town; carve(root) -> count;
--   Service:enter(player) -> (ok, why?); Service:buyPass(player) -> (ok, words); Service:leave(player) -> ok;
--   Service:order(player, id) -> (ok, words); Service:step(); Service:gone(player); Service:isInside(player) ->
--   boolean; Service:inRoom(body) -> boolean; Service:counts() -> { inside, drinks, knockedOut, strikes }; Service:stop(); constants TICK, STRIKE,
--   SIP_HOLD, COOLDOWN, PROMPT_DISTANCE, STAND, CUES, FOLDER

local Import = require("../Import")
local AlleyLayout = Import.shared("Attractions/AlleyLayout") :: typeof(require("../../shared/Attractions/AlleyLayout"))
local Data = Import.shared("Data") :: typeof(require("../../shared/Data"))
local EconomyRules = Import.shared("Economy/EconomyRules") :: typeof(require("../../shared/Economy/EconomyRules"))
local LoungeClassic =
	Import.shared("Attractions/LoungeClassic") :: typeof(require("../../shared/Attractions/LoungeClassic"))

local LoungeService = {}
LoungeService.__index = LoungeService

LoungeService.FOLDER = "LoungeService" -- the service's own prompt posts and drinks, under opts.parent
LoungeService.TICK = 0.2 -- seconds between the guards' and the room's checks
LoungeService.STRIKE = 0.6 -- seconds a guard spends stepping in and back
LoungeService.LUNGE = 1.6 -- studs a guard steps toward the squirrel
LoungeService.COOLDOWN = 2 -- seconds before the same body is struck again (it is gone by then)
LoungeService.SIP_HOLD = 1.2 -- seconds the cup is at the face
LoungeService.SERVE_LOOK = 3 -- seconds the bartender looks at the customer
LoungeService.PROMPT_DISTANCE = 6
LoungeService.STAND = 3 -- a standing body's pivot over the floor (SkyLiftService's default standOffset)
LoungeService.CUES = table.freeze({
	swat = "Lounge.GuardSwat", -- a guard's strike (a whoosh and a thump; library)
	door = "Lounge.Door", -- the door, in or out (a heavy wooden door; library)
	pour = "Lounge.Pour", -- a drink served (a pour into china; library)
	bell = "Lounge.CounterBell", -- the bar's bell when someone orders
})
-- the drink in the hand and at the face, from the body's root (an R15 root: the hand hangs at the side)
-- (functions: no engine globals on require)
local function HOLD(): CFrame
	return CFrame.new(1.0, -0.3, -0.55)
end
local function SIP(): CFrame
	return CFrame.new(0.3, 1.45, -0.85) * CFrame.Angles(math.rad(40), 0, 0)
end

export type Pass = {
	has: (player: any) -> boolean,
	buy: (player: any) -> (boolean, string),
	offer: () -> (number, number, string),
}
export type Squirrel = { actor: any, x: number, y: number, z: number } -- feet, world
-- What the service asks of the rest of the game. gameTown builds it from Boot/Game's objects; specs pass stubs.
export type Town = {
	speciesOf: (player: any) -> string?,
	bodyOf: (player: any) -> any?, -- the Model the player holds
	moveTo: (player: any, cf: CFrame) -> (), -- put the held body's feet at cf (the body faces cf's look)
	evict: (body: any, cf: CFrame) -> (), -- put a body nobody holds any more (its computer brain's) at cf
	pass: Pass, -- the wallet's one pass
	buy: (player: any, id: string, deliver: () -> (boolean?, string?)) -> (boolean, string), -- wallet.buy
	tell: (player: any, text: string) -> (), -- the notice toast
	squirrels: () -> { Squirrel }, -- every squirrel-family body, players' and computers'
	knockOut: (actor: any) -> (), -- Boot/Game's kill(actor, "guard")
}
export type Opts = {
	town: Town,
	venue: any?, -- the venue record (default: generated/Expansion's f3_lounge_classic)
	root: Instance?, -- the bake's model (default Workspace.Expansion.LoungeClassic.f3_lounge_classic)
	parent: Instance?, -- where the service's own folder goes (default workspace)
	now: (() -> number)?, -- seconds (default os.clock)
	prompts: boolean?, -- default true
	heartbeat: boolean?, -- start(): step on Heartbeat (default true)
	terrain: boolean?, -- start(): carve (default true)
}
type Drink = {
	id: string,
	model: any,
	weld: any,
	sips: number, -- left
	nextSip: number,
	down: number?, -- the cup comes back down at this time
}
type Strike = { model: any, home: CFrame, untilT: number }

local function venueOf(id: string): any
	local exp = Data.default():module("Expansion") :: any
	for _, v in exp.venues do
		if v.id == id then
			return v
		end
	end
	error("LoungeService: no venue " .. id)
end

LoungeService._venue = venueOf -- (checks)

local function newPart(name: string, size: Vector3, cf: CFrame, parent: any): any
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Transparency = 1
	p.Parent = parent
	return p
end

local function cue(parent: any, name: string): any
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = "" -- a cue point: the lead fills it from the library (docs/AUDIO_BUDGET.md); never uploaded here
	s.Parent = parent
	return s
end

local function play(sound: any)
	if sound then
		pcall(function()
			if sound.SoundId ~= "" then
				sound:Play()
			end
		end)
	end
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function pivotOf(body: any): Vector3?
	local ok, cf = pcall(function()
		return body:GetPivot()
	end)
	return if ok and cf then (cf :: CFrame).Position else nil
end

local function rootOf(body: any): any?
	if body == nil then
		return nil
	end
	return body.PrimaryPart or body:FindFirstChild("HumanoidRootPart")
end

-- Fill every TerrainCarve box under the bake with air (the west ground stands above the forecourt). -> count
function LoungeService.carve(root: Instance): number
	local n = 0
	for _, d in root:GetDescendants() do
		if d.Name == "TerrainCarve" then
			for _, p in d:GetChildren() do
				if p:IsA("BasePart") then
					workspace.Terrain:FillBlock(p.CFrame, p.Size, Enum.Material.Air)
					n += 1
				end
			end
		end
	end
	return n
end

function LoungeService.new(opts: Opts): any
	local self = setmetatable({}, LoungeService)
	self.town = opts.town
	self.venue = opts.venue or venueOf(LoungeClassic.VENUE)
	self.place = LoungeClassic.placeOf(self.venue)
	self.now = opts.now or os.clock
	self.root = opts.root
	if self.root == nil then
		local ex = workspace:FindFirstChild("Expansion")
		local slot = ex and ex:FindFirstChild("LoungeClassic")
		self.root = slot and slot:FindFirstChild(LoungeClassic.VENUE)
	end
	local folder = Instance.new("Folder")
	folder.Name = LoungeService.FOLDER
	folder.Parent = opts.parent or workspace
	self.folder = folder
	self.inside = {} :: { [any]: any } -- player -> the body let in
	self.drinks = {} :: { [any]: Drink }
	self.struck = {} :: { [any]: number } -- actor -> when
	self.strikes = {} :: { [string]: Strike }
	self.knockedOut = 0
	self.nextTick = 0
	self.conns = {} :: { RBXScriptConnection }
	self.serving = nil :: { untilT: number, at: Vector3 }?
	-- the staff the bake stands in place (nil without a bake: the rules still run)
	self.staff = {} :: { [string]: { model: any, home: CFrame } }
	local staff = self.root and self.root:FindFirstChild("Staff")
	for _, m in (if staff then staff:GetChildren() else {}) :: { any } do
		if m:IsA("Model") and m.PrimaryPart then
			self.staff[m.Name] = { model = m, home = m:GetPivot() }
		end
	end
	-- the prompt posts and the cue points
	local function at(x: number, y: number, d: number): CFrame
		return CFrame.new(self:world(x, y, d))
	end
	self.outsidePost = newPart("DoorOutside", Vector3.new(2, 2, 0.4), at(0, 3, -22.4), folder)
	self.podiumPost = newPart("Podium", Vector3.new(1, 1, 1), at(4.4, 4.2, -24.2), folder)
	self.insidePost = newPart("DoorInside", Vector3.new(2, 2, 0.4), at(0, 3, -20.6), folder)
	self.counterPosts = {} :: { any }
	for i, d in LoungeClassic.DRINKS do
		local x = LoungeClassic.COUNTER.x0 + (i - 0.5) * (LoungeClassic.COUNTER.x1 - LoungeClassic.COUNTER.x0) / 4
		self.counterPosts[i] =
			newPart(`Order_{d.id}`, Vector3.new(1, 1, 1), at(x, 3.9, LoungeClassic.COUNTER.d - 0.4), folder)
	end
	self.sounds = {
		swat = cue(self.outsidePost, LoungeService.CUES.swat),
		door = cue(self.outsidePost, LoungeService.CUES.door),
		pour = cue(self.counterPosts[2], LoungeService.CUES.pour),
		bell = cue(self.counterPosts[3], LoungeService.CUES.bell),
	}
	if opts.prompts ~= false then
		self:_prompts()
	end
	return self
end

-- A local point (venue frame) in world.
function LoungeService.world(self: any, x: number, y: number, d: number): Vector3
	local wx, wy, wz = AlleyLayout.toWorld(self.place, x, y, d)
	return Vector3.new(wx, wy, wz)
end

-- A world point in the venue frame.
function LoungeService.localOf(self: any, p: Vector3): (number, number, number)
	return AlleyLayout.toLocal(self.place, p.X, p.Y, p.Z)
end

-- Feet at a door spot, facing out (faceD -1) or in (+1).
function LoungeService.spot(self: any, s: { x: number, d: number, faceD: number }): CFrame
	local p = self:world(s.x, 0, s.d)
	local ahead = self:world(s.x, 0, s.d + s.faceD)
	return CFrame.lookAt(p, ahead)
end

-- (sight: the door's two prompts need a line of sight, so the solid leaves keep each to its own side)
local function prompt(post: any, action: string, object: string, kind: string, sight: boolean?): any
	local att = Instance.new("Attachment")
	att.Name = "PromptPoint"
	att.Parent = post
	local p = Instance.new("ProximityPrompt")
	p.Name = "LoungePrompt"
	p.ActionText = action
	p.ObjectText = object
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.HoldDuration = 0
	p.MaxActivationDistance = LoungeService.PROMPT_DISTANCE
	p.RequiresLineOfSight = sight == true
	p:SetAttribute("Door", true) -- E belongs to the prompt, not to the vehicles (Client/Minigames/MinigameClient)
	p:SetAttribute("Lounge", kind)
	p.Parent = att
	return p
end

function LoungeService._prompts(self: any)
	local W = LoungeClassic.WORDS
	local function on(p: any, name: string, fn: (player: any) -> ())
		table.insert(
			self.conns,
			p.Triggered:Connect(function(player: any)
				local ok, err = pcall(fn, player)
				if not ok then
					warn(`[Lounge] {name} failed: {err}`)
				end
			end)
		)
	end
	on(prompt(self.outsidePost, W.enterAction, W.doorObject, "enter", true), "enter", function(player)
		self:enter(player)
	end)
	on(prompt(self.insidePost, W.leaveAction, W.doorObject, "leave", true), "leave", function(player)
		self:leave(player)
	end)
	local cents, days = self.town.pass.offer()
	on(prompt(self.podiumPost, W.buyAction, `{cents}c for {days} in-game days`, "pass"), "pass", function(player)
		self:buyPass(player)
	end)
	for i, d in LoungeClassic.DRINKS do
		local price = EconomyRules.price(d.id) or 0
		on(prompt(self.counterPosts[i], `{d.label} ({price}c)`, W.orderObject, d.id), "order", function(player)
			self:order(player, d.id)
		end)
	end
end

function LoungeService.isInside(self: any, player: any): boolean
	return self.inside[player] ~= nil
end

local function setZone(body: any, on: boolean)
	pcall(function()
		body:SetAttribute("CameraZone", if on then LoungeClassic.ZONE else nil)
		body:SetAttribute(LoungeClassic.ATTRIBUTE, if on then LoungeClassic.VENUE else nil)
	end)
end

-- The door from outside: in with the pass, the offer without it, the guards for a squirrel.
function LoungeService.enter(self: any, player: any): (boolean, string?)
	local W = LoungeClassic.WORDS
	local species = self.town.speciesOf(player)
	local body = self.town.bodyOf(player)
	if species == nil or body == nil then
		self.town.tell(player, W.noBody)
		return false, "noBody"
	end
	if self.inside[player] == body then
		return true, nil -- already in
	end
	local decision = LoungeClassic.door(species, species == "human" and self.town.pass.has(player))
	if decision == "guard" then
		self.town.tell(player, W.squirrel)
		return false, "guard" -- the guards' check takes it on their next look (it is in the entry)
	elseif decision == "refuse" then
		self.town.tell(player, W.animals)
		return false, "refuse"
	elseif decision == "offer" then
		local _cents, _days, offer = self.town.pass.offer()
		self.town.tell(player, `{W.membersOnly} {offer}`)
		return false, "offer"
	end
	self.town.moveTo(player, self:spot(LoungeClassic.DOOR_INSIDE))
	self.inside[player] = body
	setZone(body, true)
	play(self.sounds.door)
	self.town.tell(player, W.welcome)
	return true, nil
end

-- The podium: buy the pass (the wallet's own words), and if bought, straight in.
function LoungeService.buyPass(self: any, player: any): (boolean, string)
	local species = self.town.speciesOf(player)
	if species ~= "human" then
		local w = if species and LoungeClassic.SQUIRRELS[species]
			then LoungeClassic.WORDS.squirrel
			else LoungeClassic.WORDS.animals
		self.town.tell(player, w)
		return false, w
	end
	local ok, words = self.town.pass.buy(player)
	self.town.tell(player, words)
	if ok then
		self:enter(player)
	end
	return ok, words
end

local function dropDrink(self: any, player: any)
	local d = self.drinks[player]
	if d then
		self.drinks[player] = nil
		pcall(function()
			d.model:Destroy()
		end)
	end
end

-- The door from inside: back on the landing, first person released.
function LoungeService.leave(self: any, player: any): boolean
	local body = self.inside[player]
	if body == nil then
		return false -- (only someone the door let in leaves through it)
	end
	dropDrink(self, player)
	self.inside[player] = nil
	setZone(body, false)
	self.town.moveTo(player, self:spot(LoungeClassic.DOOR_OUTSIDE))
	play(self.sounds.door)
	self.town.tell(player, LoungeClassic.WORDS.goodbye)
	return true
end

-- The drink in the hand: a cup (or a paper cone for a snow cone) welded to the body's root.
local function makeDrink(body: any, d: LoungeClassic.Drink): (any, any)
	local root = rootOf(body)
	local m = Instance.new("Model")
	m.Name = "LoungeDrink"
	local function part(name: string, shape: Enum.PartType, size: Vector3, offset: CFrame, color: { number }): any
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = shape
		p.Size = size
		p.Color = rgb(color)
		p.Material = Enum.Material.SmoothPlastic
		p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, true
		p.CastShadow = false
		p.CFrame = (if root then root.CFrame * HOLD() else CFrame.new()) * offset
		p.Parent = m
		return p
	end
	local up = CFrame.Angles(0, 0, math.pi / 2) -- a cylinder's axis is X: stand it up
	local vessel
	if d.hot then
		vessel = part("Cup", Enum.PartType.Cylinder, Vector3.new(0.5, 0.42, 0.42), up, d.cup)
		part("Fill", Enum.PartType.Cylinder, Vector3.new(0.04, 0.36, 0.36), CFrame.new(0, 0.24, 0) * up, d.fill)
	else
		vessel = part("Cone", Enum.PartType.Cylinder, Vector3.new(0.6, 0.3, 0.3), up, d.cup)
		part("Ice", Enum.PartType.Ball, Vector3.new(0.48, 0.48, 0.48), CFrame.new(0, 0.38, 0), d.fill)
	end
	m.PrimaryPart = vessel
	for _, p in m:GetChildren() do
		if p ~= vessel then
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = vessel, p
			w.Parent = p
		end
	end
	local weld = Instance.new("Weld")
	weld.Name = "Hold"
	weld.Part0 = root
	weld.Part1 = vessel
	weld.C0 = HOLD()
	weld.Parent = vessel
	m.Parent = body
	return m, weld
end

-- The bar: one drink at a time, inside only, at the wallet's price; the money goes when the drink is in the hand.
function LoungeService.order(self: any, player: any, id: string): (boolean, string)
	local W = LoungeClassic.WORDS
	local d = LoungeClassic.drink(id)
	if d == nil then
		return false, "That is not for sale yet."
	end
	local body = self.inside[player]
	if body == nil or self.town.speciesOf(player) ~= "human" then
		self.town.tell(player, W.notInside)
		return false, W.notInside
	end
	if self.drinks[player] then
		self.town.tell(player, W.holding)
		return false, W.holding
	end
	local drink = d :: LoungeClassic.Drink
	local ok, words = self.town.buy(player, drink.id, function()
		local okM, model, weld = pcall(makeDrink, body, drink)
		if not okM then
			warn(`[Lounge] the drink could not be made: {model}`)
			return false, "Sorry, the bar is busy."
		end
		local t = self.now()
		self.drinks[player] = {
			id = drink.id,
			model = model,
			weld = weld,
			sips = LoungeClassic.SIPS,
			nextSip = t + LoungeClassic.SIP_EVERY,
		}
		return true
	end)
	self.town.tell(player, words)
	if ok then
		play(self.sounds.bell)
		play(self.sounds.pour)
		local p = pivotOf(body)
		if p then
			self.serving = { untilT = self.now() + LoungeService.SERVE_LOOK, at = p }
		end
	end
	return ok, words
end

-- The nearest guard steps toward the target and will step back.
function LoungeService._strike(self: any, target: Vector3, t: number)
	local best, bestD = nil, math.huge
	for name, s in self.staff do
		if string.sub(name, 1, 5) == "Guard" then
			local d = (s.home.Position - target).Magnitude
			if d < bestD then
				best, bestD = name, d
			end
		end
	end
	if best == nil then
		return
	end
	local s = self.staff[best]
	local home = s.home
	local flat = Vector3.new(target.X, home.Position.Y, target.Z)
	local dir = flat - home.Position
	local facing = if dir.Magnitude > 1e-3 then dir.Unit else home.LookVector
	local at = home.Position + facing * math.min(LoungeService.LUNGE, dir.Magnitude)
	pcall(function()
		s.model:PivotTo(CFrame.lookAt(at, at + facing))
	end)
	self.strikes[best] = { model = s.model, home = home, untilT = t + LoungeService.STRIKE }
	play(self.sounds.swat)
end

function LoungeService.step(self: any, _dt: number?)
	local t = self.now()
	-- strikes and the bartender ease back home
	for name, s in self.strikes do
		if t >= s.untilT then
			pcall(function()
				s.model:PivotTo(s.home)
			end)
			self.strikes[name] = nil
		end
	end
	local bt = self.staff.Bartender
	if bt and self.serving then
		local serving = self.serving
		if t >= serving.untilT then
			self.serving = nil
			pcall(function()
				bt.model:PivotTo(bt.home)
			end)
		else
			local h = bt.home.Position
			pcall(function()
				bt.model:PivotTo(CFrame.lookAt(h, Vector3.new(serving.at.X, h.Y, serving.at.Z)))
			end)
		end
	end
	-- the drinks: sip, then down, then all gone
	for player, d in self.drinks do
		if d.down and t >= d.down then
			d.down = nil
			d.weld.C0 = HOLD()
			if d.sips <= 0 then
				dropDrink(self, player)
				self.town.tell(player, LoungeClassic.WORDS.finished)
			end
		elseif d.down == nil and t >= d.nextSip then
			d.sips -= 1
			d.weld.C0 = SIP()
			d.down = t + LoungeService.SIP_HOLD
			d.nextSip = t + LoungeClassic.SIP_EVERY
		end
	end
	if t < self.nextTick then
		return
	end
	self.nextTick = t + LoungeService.TICK
	-- the guards: any squirrel-family body on the forecourt, in the entry or in the room
	local centre = self:world(0, 0, 0)
	for _, s in self.town.squirrels() do
		local dx, dz = s.x - centre.X, s.z - centre.Z
		if dx * dx + dz * dz < 60 * 60 then
			local x, y, d = AlleyLayout.toLocal(self.place, s.x, s.y, s.z)
			if LoungeClassic.guarded(x, y, d) or LoungeClassic.inside(x, y, d) then
				local last = self.struck[s.actor]
				if last == nil or t - last >= LoungeService.COOLDOWN then
					self.struck[s.actor] = t
					self.knockedOut += 1
					self:_strike(Vector3.new(s.x, s.y, s.z), t)
					self.town.knockOut(s.actor)
				end
			end
		end
	end
	for actor, last in self.struck do
		if t - last >= LoungeService.COOLDOWN then
			self.struck[actor] = nil
		end
	end
	-- the room: a body let in that is no longer there (a knock-out elsewhere) is let go; one its player has let
	-- go of (a new body picked) is let go and, if it is still in the room, put out at the door, or its computer
	-- brain would be shut in a sealed building
	for player, body in self.inside do
		local here = self:inRoom(body)
		if self.town.bodyOf(player) ~= body then
			self:_release(player, body, here)
		elseif not here then
			self.inside[player] = nil
			setZone(body, false)
			dropDrink(self, player)
		end
	end
end

-- Is this body's pivot (standing) in the room?
function LoungeService.inRoom(self: any, body: any): boolean
	local p = pivotOf(body)
	if p == nil then
		return false
	end
	local x, y, d = AlleyLayout.toLocal(self.place, p.X, p.Y - LoungeService.STAND, p.Z)
	return LoungeClassic.inside(x, y, d)
end

-- Let a body go that its player no longer holds: first person off, the drink gone, out at the door if inside.
function LoungeService._release(self: any, player: any, body: any, here: boolean)
	self.inside[player] = nil
	setZone(body, false)
	dropDrink(self, player)
	if here then
		self.town.evict(body, self:spot(LoungeClassic.DOOR_OUTSIDE))
	end
end

-- A player left the game.
function LoungeService.gone(self: any, player: any)
	local body = self.inside[player]
	if body then
		self:_release(player, body, self:inRoom(body))
	end
	dropDrink(self, player)
end

function LoungeService.counts(self: any): { [string]: number }
	local inside, drinks, strikes = 0, 0, 0
	for _ in self.inside do
		inside += 1
	end
	for _ in self.drinks do
		drinks += 1
	end
	for _ in self.strikes do
		strikes += 1
	end
	return { inside = inside, drinks = drinks, knockedOut = self.knockedOut, strikes = strikes }
end

function LoungeService.stop(self: any)
	for _, c in self.conns do
		c:Disconnect()
	end
	self.conns = {}
	for player in self.drinks do
		dropDrink(self, player)
	end
	pcall(function()
		self.folder:Destroy()
	end)
end

-- The service as the game runs it: terrain carved, stepped on Heartbeat, a leaver let go.
function LoungeService.start(opts: Opts): any
	local self = LoungeService.new(opts)
	if self.root == nil then
		warn("[Lounge] Workspace.Expansion.LoungeClassic has no bake (lune run tools/bake/lounge_classic.luau)")
	elseif opts.terrain ~= false then
		LoungeService.carve(self.root)
	end
	if opts.heartbeat ~= false then
		table.insert(
			self.conns,
			game:GetService("RunService").Heartbeat:Connect(function(dt: number)
				self:step(dt)
			end)
		)
		table.insert(
			self.conns,
			game:GetService("Players").PlayerRemoving:Connect(function(player: Player)
				self:gone(player)
			end)
		)
	end
	return self
end

-- Boot/Game's objects -> Town. `squirrels` and `kill` are Game's own (its isSquirrelFamily and kill).
export type GameParts = {
	possession: any,
	runtime: any?, -- Actors/ActorsRuntime (world, byTownId): a body's computer brain is moved through it
	wallet: any, -- Economy/Credits
	squirrels: () -> { Squirrel },
	kill: (actor: any, cause: string) -> (),
}
function LoungeService.gameTown(parts: GameParts): Town
	local possession, wallet = parts.possession, parts.wallet
	local function actorOf(player: any): any?
		return possession:actorOf(player)
	end
	return {
		speciesOf = function(player: any): string?
			local a = actorOf(player)
			return if a then a.species else nil
		end,
		bodyOf = function(player: any): any?
			local a = actorOf(player)
			return if a then a.body else nil
		end,
		moveTo = function(player: any, cf: CFrame)
			local a = actorOf(player)
			if a and a.body then
				(a.body :: Model):PivotTo(cf + Vector3.new(0, LoungeService.STAND, 0))
			end
		end,
		evict = function(body: any, cf: CFrame)
			-- a computer-held body is drawn from its world record (ActorsRuntime: feet = a.y - a.hip)
			local rt = parts.runtime
			if rt then
				for id, actor in rt.byTownId do
					if actor.body == body then
						local a = rt.world.actorsById[id]
						if a then
							local p = cf.Position
							a.x, a.z = p.X, p.Z
							a.y = p.Y + a.hip
							return
						end
					end
				end
			end
			(body :: Model):PivotTo(cf + Vector3.new(0, LoungeService.STAND, 0))
		end,
		pass = wallet.pass,
		buy = function(player: any, id: string, deliver: () -> (boolean?, string?)): (boolean, string)
			return wallet.buy(player, id, deliver)
		end,
		tell = function(player: any, text: string)
			wallet.tell(player, text)
		end,
		squirrels = parts.squirrels,
		knockOut = function(actor: any)
			parts.kill(actor, "guard")
		end,
	}
end

return LoungeService
