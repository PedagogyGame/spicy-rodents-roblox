--!strict
-- ServerScriptService.Server.Minigames.FortuneCabinet
-- Madame Acorna, the fortune-teller cabinet in the alley's fern corner (brief v2 §13a: "pull the lever, reels
-- spin, it dispenses a fortune or a taunt. No money in or out, ever"; rules: Minigames/MinigameRules/
-- FortuneMachine). The show, server side so everyone near sees it: the lever swings down and back, the three
-- reels (SurfaceGui faces on GamesRoom.Fortune.Reel1..3) blur through the symbols and stop one by one on the
-- drawn symbols, the crystal ball flares, and a printed card slides out of the slot with the line on it.
-- Interface: new(opts) -> Cabinet; Cabinet:pull(result) (starts the show); Cabinet:busy(); Cabinet:step(dt);
--   SHOW_SECONDS

local Import = require("../Import")
local FortuneMachine = Import.shared("Minigames/MinigameRules/FortuneMachine")
	:: typeof(require("../../shared/Minigames/MinigameRules/FortuneMachine"))

local FortuneCabinet = {}
FortuneCabinet.__index = FortuneCabinet

FortuneCabinet.SHOW_SECONDS = 2.6
local STOPS = { 1.1, 1.6, 2.1 }

function FortuneCabinet.new(opts: { [string]: any }): any
	local self = setmetatable({}, FortuneCabinet) :: any
	self.model = opts.model :: Model?
	self.t = -1
	self.result = nil
	local m = self.model
	self.lever = m and m:FindFirstChild("Lever") :: Model?
	self.leverHome = if self.lever then (self.lever :: Model):GetPivot() else nil
	self.pivot = m and m:FindFirstChild("LeverPivot") :: BasePart?
	self.reels = {}
	for r = 1, 3 do
		local reel = m and m:FindFirstChild(`Reel{r}`)
		local face = reel and reel:FindFirstChild("Face")
		local label = face and face:FindFirstChildOfClass("TextLabel")
		self.reels[r] = label
	end
	self.orb = m and m:FindFirstChild("CrystalBall") :: BasePart?
	self.slot = m and m:FindFirstChild("CardSlot") :: BasePart?
	self.card = nil :: BasePart?
	return self
end

function FortuneCabinet.busy(self: any): boolean
	return self.t >= 0 and self.t < FortuneCabinet.SHOW_SECONDS + 0.4
end

function FortuneCabinet.pull(self: any, result: { [string]: any })
	self.result = result
	self.t = 0
	local card = self.card :: BasePart?
	if card then
		card:Destroy()
		self.card = nil
	end
end

local function setReel(label: TextLabel?, symbol: string)
	if label then
		label.Text = FortuneMachine.REEL_LABEL[symbol] or string.upper(symbol)
	end
end

function FortuneCabinet.step(self: any, dt: number)
	if self.t < 0 then
		return
	end
	local prev = self.t
	self.t += dt
	local t = self.t
	-- the lever: down in 0.25 s, back up by 0.7 s (swings about the pivot)
	local lever, home, pivot = self.lever :: Model?, self.leverHome, self.pivot :: BasePart?
	if lever and home and pivot then
		local a = if t < 0.25 then t / 0.25 elseif t < 0.7 then 1 - (t - 0.25) / 0.45 else 0
		local p = pivot.Position
		-- the cabinet's front is the pivot's +Z (its Back face); the arm swings forward about its right axis
		local rot = CFrame.fromAxisAngle(pivot.CFrame.RightVector, a * 1.1)
		lever:PivotTo(CFrame.new(p) * rot * CFrame.new(-p) * home)
	end
	-- reels: blur, then stop one by one
	local r = self.result
	local symbols = FortuneMachine.REELS
	for i = 1, 3 do
		local label = self.reels[i]
		if t < STOPS[i] then
			setReel(label, symbols[(math.floor(t * 18) + i * 2) % #symbols + 1])
		elseif prev < STOPS[i] and r and r.reels then
			setReel(label, r.reels[i])
		end
	end
	-- the orb flares while the reels run
	local orb = self.orb :: BasePart?
	if orb then
		orb.Transparency = if t < STOPS[3] then 0.15 + 0.1 * math.sin(t * 25) else 0.15
	end
	-- the card prints at the end
	if prev < FortuneCabinet.SHOW_SECONDS and t >= FortuneCabinet.SHOW_SECONDS and self.slot and r then
		local slot = self.slot :: BasePart
		local card = Instance.new("Part")
		card.Name = "FortuneCard"
		card.Anchored = true
		card.CanCollide = false
		card.CanQuery = false
		card.Size = Vector3.new(0.9, 0.02, 0.55)
		card.Color = Color3.fromRGB(246, 236, 210)
		card.Material = Enum.Material.SmoothPlastic
		-- out of the slot, toward the person pulling
		card.CFrame = slot.CFrame * CFrame.new(0, 0, 0.3) * CFrame.Angles(math.rad(-20), 0, 0)
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Top
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 200
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextScaled = true
		label.TextWrapped = true
		label.Font = Enum.Font.Fantasy
		label.TextColor3 = Color3.fromRGB(70, 30, 80)
		label.Text = tostring(r.line or "")
		label.Parent = gui
		gui.Parent = card
		card.Parent = self.model or workspace
		self.card = card
	end
	if t > FortuneCabinet.SHOW_SECONDS + 8 then
		local card = self.card :: BasePart?
		if card then
			card:Destroy()
			self.card = nil
		end
		self.t = -1
	end
end

return FortuneCabinet
