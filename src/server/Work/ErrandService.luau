--!strict
-- ServerScriptService.Server.Work.ErrandService
-- The bank errands in the game (owner D30; the rules are Shared/Work/Errands, the banks Shared/Work/Banks, the
-- penalty Server/Work/Penalties). The server decides everything: the client only presses a prompt.
--   * A board outside each bank (built here: a sandwich board, "BANK ERRANDS", and its E prompt). A person who has
--     no errand presses it and is given one from that bank (Errands.offer): the words on their screen name the place
--     or the person, the time and the pay ("Take this parcel to Pepper's Corner Store. You have 9 minutes; it pays
--     S$8.00."). Nothing is marked on the map or the screen: it pays to know the town. One errand at a time.
--   * The thing is carried visibly: a small prop in the carrier's right hand (welded, massless, not solid), put on
--     the body they hold now (taken off while they are not a person, put back when they are one again).
--   * Within DROP studs of the spot it is handed over and paid (wallet.add, "an errand"); the first time within
--     CLOSE studs a gentle "You're close to ..."; a minute before the end a reminder of the time.
--   * Pressing a board while carrying says what is carried and for whom; a second press within CONFIRM_SECS hands
--     it back (they could not find the place): no pay, no penalty.
--   * Kept (the penalty: Penalties.errandStolen, S$100 through the wallet and a reputation report): past the time
--     limit, kept in their own home (World/PlayerHomes.homeOf; Tunables work.errandHomeSecs in all), or taken out
--     of the server (leave(player), called on PlayerRemoving).
--   * Presses closer together than PRESS_GAP are ignored (a held key, a macro).
--   * The banks also sell Spicy Stock Options (owner D30; Economy/StockOptions, the stock-options work's): a second
--     prompt on each board (R, "Spicy Stock Options") opens its purchase window (stockOptions.promptBuy(player));
--     buying, saving and withdrawing at home are all StockOptions'. No prompt when deps.stockOptions is not given.
-- Cost: three boards of three parts each; step() looks at the runs (one per player carrying, at most 49) every
-- STEP_PERIOD seconds: a pivot read and a few sums each.
-- Engine only through deps (defaults use the engine); no side effects on require.
-- Interface: new(deps) -> Service { press(player, bankId) -> (ok, words), step(dt), leave(player), runOf(player) ->
--   Run?, buyOptions(player) -> (ok, words), boards() -> { [bankId]: Board }, stop() }; start(deps) -> Service (builds the boards and their prompts and
--   steps on Heartbeat); constants PRESS_GAP, CONFIRM_SECS, STEP_PERIOD, REMIND_SECS, FOLDER, WORDS

local Import = require("../Import")
local Banks = Import.shared("Work/Banks") :: typeof(require("../../shared/Work/Banks"))
local Errands = Import.shared("Work/Errands") :: typeof(require("../../shared/Work/Errands"))
local PlayerHomes = Import.shared("World/PlayerHomes") :: typeof(require("../../shared/World/PlayerHomes"))
local Bank = Import.shared("Economy/Bank") :: typeof(require("../../shared/Economy/Bank"))

local ErrandService = {}
ErrandService.__index = ErrandService

ErrandService.PRESS_GAP = 0.6 -- seconds between a player's presses that count
ErrandService.CONFIRM_SECS = 6 -- a second press at a board within this long hands the errand back
ErrandService.STEP_PERIOD = 0.25
ErrandService.REMIND_SECS = 60 -- "one minute left"
ErrandService.PROMPT_DISTANCE = 8
ErrandService.FOLDER = "BankErrands"
ErrandService.PAY_WHY = "an errand"

ErrandService.WORDS = table.freeze({
	notPerson = "Only people run errands: pick a person from the menu first (M)",
	given = "%s You have %s; it pays %s.",
	carrying = "You are carrying %s for %s: %s left. Press again to hand it back (no pay, no penalty).",
	handedBack = "You handed %s back. No pay, no penalty.",
	close = "You're close to %s.",
	delivered = "Delivered %s to %s. +%s.",
	remind = "One minute left to get %s to %s.",
})

export type Deps = {
	wallet: any, -- Economy/Credits (add)
	penalties: any, -- Server/Work/Penalties instance (errandStolen)
	bodyOf: (player: any) -> any?, -- the Model the player holds
	isPerson: (player: any) -> boolean, -- in a human body (not a squirrel, a deer ...)
	notify: (player: any, text: string) -> (),
	now: (() -> number)?, -- seconds (default os.clock)
	rand: (() -> number)?,
	posOf: ((body: any) -> { number }?)?, -- {x, z} (default: the Model's pivot)
	homeOf: ((player: any) -> string?)?, -- default World/PlayerHomes.homeOf
	inside: ((lotId: string, x: number, z: number) -> boolean)?, -- default World/PlayerHomes.inside
	attach: ((body: any, item: any) -> any?)?, -- put the prop in the hand; returns it (default: engine)
	detach: ((prop: any) -> ())?,
	data: any?, -- Shared/Data (default: Data.default())
	-- Economy/StockOptions (promptBuy(player)), read when the prompt is pressed (nil: the banks sell none)
	stockOptions: (() -> any?)?,
}

type Run = {
	run: any, -- Errands.Run
	player: any,
	prop: any?,
	propBody: any?,
	reminded: boolean,
}

local function engineAttach(body: any, item: any): any?
	if typeof(body) ~= "Instance" then
		return nil
	end
	local model = body :: any
	local hand = model:FindFirstChild("RightHand") or model:FindFirstChild("Right Arm") or model.PrimaryPart
	if hand == nil or not hand:IsA("BasePart") then
		return nil
	end
	local p = Instance.new("Part")
	p.Name = "ErrandItem"
	p.Size = Vector3.new(item.size[1], item.size[2], item.size[3])
	p.Color = Color3.fromRGB(item.color[1], item.color[2], item.color[3])
	p.Material = Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Anchored = false
	-- held in front of the hand, a little down: the hand's grip
	local below = if hand.Name == "RightHand" then hand.Size.Y / 2 + item.size[2] / 2 - 0.1 else 0.6
	p.CFrame = (hand :: BasePart).CFrame * CFrame.new(0, -below, -0.2)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hand :: BasePart
	weld.Part1 = p
	weld.Parent = p
	p.Parent = body
	return p
end

local function engineDetach(prop: any)
	if typeof(prop) == "Instance" then
		prop:Destroy()
	end
end

local function enginePos(body: any): { number }?
	if typeof(body) ~= "Instance" or not body:IsA("Model") then
		return nil
	end
	local ok, cf = pcall(function()
		return (body :: Model):GetPivot()
	end)
	return if ok then { cf.Position.X, cf.Position.Z } else nil
end

function ErrandService.new(deps: Deps): any
	local self = setmetatable({}, ErrandService) :: any
	self.deps = deps
	self.now = deps.now or os.clock
	self.rand = deps.rand or math.random
	self.posOf = deps.posOf or enginePos
	self.homeOf = deps.homeOf or function(player: any): string?
		return PlayerHomes.homeOf(player)
	end
	self.inside = deps.inside
		or function(lotId: string, x: number, z: number): boolean
			return PlayerHomes.inside(lotId, x, z)
		end
	self.attach = deps.attach or engineAttach
	self.detach = deps.detach or engineDetach
	self.runs = {} :: { [any]: Run }
	self.lastPress = {} :: { [any]: number }
	self.confirmUntil = {} :: { [any]: number }
	self.boardAt = {} :: { [string]: any }
	for _, bank in Banks.BANKS do
		self.boardAt[bank.id] = Banks.board(bank, deps.data)
	end
	self.acc = 0
	self.stopped = false
	self.conns = {} :: { any }
	self.parts = {} :: { any }
	return self
end

function ErrandService.boards(self: any): { [string]: any }
	return self.boardAt
end

function ErrandService.runOf(self: any, player: any): any?
	local r = self.runs[player]
	return if r then r.run else nil
end

local function words(fmt: string, ...: any): string
	return string.format(fmt, ...)
end

function ErrandService._drop(self: any, r: Run)
	if r.prop ~= nil then
		pcall(self.detach, r.prop)
	end
	r.prop, r.propBody = nil, nil
	self.runs[r.player] = nil
	pcall(function()
		(r.player :: any):SetAttribute("Errand", nil)
	end)
end

-- The board's E: take an errand from this bank, or (carrying one) hear it again and, pressed twice, hand it back.
function ErrandService.press(self: any, player: any, bankId: string): (boolean, string?)
	local deps = self.deps :: Deps
	local now = self.now()
	local last = self.lastPress[player]
	if last and now - last < ErrandService.PRESS_GAP then
		return false, nil -- (a held key: ignored, nothing said)
	end
	self.lastPress[player] = now
	local bank = Banks.byId(bankId)
	local board = self.boardAt[bankId]
	if bank == nil or board == nil then
		return false, nil
	end
	local W = ErrandService.WORDS
	local r = self.runs[player] :: Run?
	if r then
		local run = r.run
		local e = run.errand
		if (self.confirmUntil[player] or -math.huge) >= now then
			self.confirmUntil[player] = nil
			Errands.handBack(run)
			self:_drop(r)
			local text = words(W.handedBack, e.item.the)
			deps.notify(player, text)
			return true, text
		end
		self.confirmUntil[player] = now + ErrandService.CONFIRM_SECS
		local text = words(W.carrying, e.item.the, e.to, Errands.duration(Errands.left(run, now)))
		deps.notify(player, text)
		return false, text
	end
	if not deps.isPerson(player) or deps.bodyOf(player) == nil then
		deps.notify(player, W.notPerson)
		return false, W.notPerson
	end
	local e = Errands.offer(bankId, { board.x, board.z }, self.rand)
	local run = Errands.start(e, now)
	local entry: Run = { run = run, player = player, prop = nil, propBody = nil, reminded = false }
	self.runs[player] = entry
	self:_hold(entry)
	pcall(function()
		(player :: any):SetAttribute("Errand", e.words)
	end)
	local text = words(W.given, e.words, Errands.duration(e.secs), Bank.amount(e.cents))
	deps.notify(player, text)
	return true, text
end

-- The prop in the hand of the body the player holds now, if it is a person's; off otherwise.
function ErrandService._hold(self: any, r: Run)
	local deps = self.deps :: Deps
	local body = if deps.isPerson(r.player) then deps.bodyOf(r.player) else nil
	if body == r.propBody and (body == nil or r.prop ~= nil) then
		return
	end
	if r.prop ~= nil then
		pcall(self.detach, r.prop)
		r.prop = nil
	end
	r.propBody = body
	if body ~= nil then
		local ok, prop = pcall(self.attach, body, r.run.errand.item)
		r.prop = if ok then prop else nil
	end
end

function ErrandService._kept(self: any, r: Run)
	local e = r.run.errand
	local deps = self.deps :: Deps
	self:_drop(r)
	if deps.penalties then
		local ok, err = pcall(deps.penalties.errandStolen, r.player, e.item.the)
		if not ok then
			warn(`[Errands] penalty failed: {err}`)
		end
	end
end

function ErrandService.step(self: any, dt: number?)
	if self.stopped then
		return
	end
	self.acc += dt or ErrandService.STEP_PERIOD
	if self.acc < ErrandService.STEP_PERIOD then
		return
	end
	local span = self.acc
	self.acc = 0
	local deps = self.deps :: Deps
	local now = self.now()
	local W = ErrandService.WORDS
	for _, r in table.clone(self.runs) :: { [any]: Run } do
		self:_hold(r)
		local run = r.run
		local e = run.errand
		local at: { number }? = nil
		local atHome = false
		if r.propBody ~= nil then
			at = self.posOf(r.propBody)
			local home = if at then self.homeOf(r.player) else nil
			if home and at then
				atHome = self.inside(home, at[1], at[2])
			end
		end
		local what = Errands.step(run, now, at, atHome, span)
		if what == "delivered" then
			self:_drop(r)
			local ok = deps.wallet.add(r.player, e.cents, ErrandService.PAY_WHY)
			deps.notify(r.player, words(W.delivered, e.item.the, e.to, Bank.amount(if ok then e.cents else 0)))
		elseif what == "close" then
			deps.notify(r.player, words(W.close, e.to))
		elseif what == "expired" or what == "kept_home" then
			self:_kept(r)
		elseif not r.reminded and Errands.left(run, now) <= ErrandService.REMIND_SECS then
			r.reminded = true
			deps.notify(r.player, words(W.remind, e.item.the, e.to))
		end
	end
end

-- The bank's other counter: Spicy Stock Options (StockOptions.promptBuy; it rate-limits and says why not itself).
function ErrandService.buyOptions(self: any, player: any): (boolean, string?)
	local get = (self.deps :: Deps).stockOptions
	local so = if get then get() else nil
	if so == nil or so.promptBuy == nil then
		return false, nil
	end
	return so.promptBuy(player)
end

-- The player left the server: an errand still in hand is taken with them (kept).
function ErrandService.leave(self: any, player: any)
	local r = self.runs[player]
	if r then
		r.run.over = "left"
		self:_kept(r)
	end
	self.lastPress[player] = nil
	self.confirmUntil[player] = nil
end

function ErrandService.stop(self: any)
	if self.stopped then
		return
	end
	self.stopped = true
	for _, r in table.clone(self.runs) :: { [any]: Run } do
		self:_drop(r)
	end
	for _, c in self.conns do
		c:Disconnect()
	end
	table.clear(self.conns)
	for _, p in self.parts do
		pcall(function()
			p:Destroy()
		end)
	end
	table.clear(self.parts)
end

-- The boards in the world: a sandwich board with "BANK ERRANDS" on both faces and an E prompt (Door = true, so E
-- belongs to the prompt and not to a vehicle), under Workspace[FOLDER].
function ErrandService._build(self: any, parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = ErrandService.FOLDER
	folder.Parent = parent
	table.insert(self.parts, folder)
	local B = Banks.BOARD
	for _, bank in Banks.BANKS do
		local b = self.boardAt[bank.id]
		local m = Instance.new("Model")
		m.Name = `ErrandBoard_{bank.id}`
		local base = CFrame.new(b.x, b.y, b.z) * CFrame.Angles(0, b.yaw, 0)
		local board = Instance.new("Part")
		board.Name = "Board"
		board.Anchored = true
		board.Size = Vector3.new(B.w, B.h - 0.4, B.d)
		board.CFrame = base * CFrame.new(0, 0.4 + (B.h - 0.4) / 2, 0)
		board.Color = Color3.fromRGB(46, 58, 52)
		board.Material = Enum.Material.Wood
		board.Parent = m
		local frame = Instance.new("Part")
		frame.Name = "Frame"
		frame.Anchored = true
		frame.CanCollide = false
		frame.Size = Vector3.new(B.w + 0.2, 0.4, B.d + 0.2)
		frame.CFrame = base * CFrame.new(0, 0.2, 0)
		frame.Color = Color3.fromRGB(104, 72, 46)
		frame.Material = Enum.Material.Wood
		frame.Parent = m
		for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
			local gui = Instance.new("SurfaceGui")
			gui.Face = face
			gui.PixelsPerStud = 40
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.LightInfluence = 1
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(0.9, 0.9)
			label.Position = UDim2.fromScale(0.05, 0.05)
			label.BackgroundTransparency = 1
			label.TextScaled = true
			label.Font = Enum.Font.Garamond
			label.TextColor3 = Color3.fromRGB(240, 232, 206)
			label.Text = `BANK\nERRANDS\n\nDeliveries\naround town`
			label.Parent = gui
			gui.Parent = board
		end
		local att = Instance.new("Attachment")
		att.Name = "PromptPoint"
		att.Position = Vector3.new(0, 0, -B.d / 2 - 0.2)
		att.Parent = board
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "ErrandPrompt"
		prompt.ActionText = "Errands"
		prompt.ObjectText = bank.short
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = ErrandService.PROMPT_DISTANCE
		prompt.RequiresLineOfSight = false
		prompt:SetAttribute("Door", true)
		prompt:SetAttribute("Errands", bank.id)
		prompt.Parent = att
		local bankId = bank.id
		table.insert(
			self.conns,
			prompt.Triggered:Connect(function(player: Player)
				local ok, err = pcall(self.press, self, player, bankId)
				if not ok then
					warn(`[Errands] press failed: {err}`)
				end
			end)
		)
		if (self.deps :: Deps).stockOptions then
			local att2 = Instance.new("Attachment")
			att2.Name = "StockPromptPoint"
			att2.Position = Vector3.new(0, -0.6, -B.d / 2 - 0.2)
			att2.Parent = board
			local buy = Instance.new("ProximityPrompt")
			buy.Name = "StockOptionsPrompt"
			buy.ActionText = "Spicy Stock Options"
			buy.ObjectText = bank.short
			buy.KeyboardKeyCode = Enum.KeyCode.R
			buy.HoldDuration = 0
			buy.MaxActivationDistance = ErrandService.PROMPT_DISTANCE
			buy.RequiresLineOfSight = false
			buy.Parent = att2
			table.insert(
				self.conns,
				buy.Triggered:Connect(function(player: Player)
					local ok, err = pcall(self.buyOptions, self, player)
					if not ok then
						warn(`[Errands] stock options failed: {err}`)
					end
				end)
			)
		end
		m.Parent = folder
	end
end

-- In the game: the service, its boards and prompts, its Heartbeat step and PlayerRemoving.
function ErrandService.start(deps: Deps & { heartbeat: boolean?, parent: Instance? }): any
	local self = ErrandService.new(deps)
	self:_build(deps.parent or workspace)
	if deps.heartbeat ~= false then
		table.insert(
			self.conns,
			game:GetService("RunService").Heartbeat:Connect(function(dt: number)
				local ok, err = pcall(self.step, self, dt)
				if not ok then
					warn(`[Errands] step failed: {err}`)
				end
			end)
		)
	end
	table.insert(
		self.conns,
		game:GetService("Players").PlayerRemoving:Connect(function(player: Player)
			pcall(self.leave, self, player)
		end)
	)
	return self
end

return ErrandService
