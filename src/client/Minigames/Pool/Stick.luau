--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.Pool.Stick
-- A cue, drawn on this screen only: a tapered shaft with a chalked tip and a dark butt, three parts under the
-- camera (so they never replicate and never collide). The shooter's controller holds one while aiming (it
-- follows the aim and is drawn back with the power); the playback of a shot holds one for the stroke itself,
-- on every screen, so a watcher and a computer player's opponent see the cue come through the ball.
-- Dimensions are Shared/Minigames/Pool/Furniture's (CUE_LEN, CUE_TIP, CUE_BUTT).
-- Interface: new() -> Stick; Stick:pose(tip: Vector3, toward: Vector3, alpha?) (the tip's point and the unit
--   direction the cue points, butt to tip; alpha 0..1 fades it); Stick:hide(); Stick:destroy(); Stick.shown

local Import = require("../../Import")
local Furniture =
	Import.shared("Minigames/Pool/Furniture") :: typeof(require("../../../shared/Minigames/Pool/Furniture"))

local Stick = {}
Stick.__index = Stick

local FERRULE = 0.09 -- the white ferrule and the tip, of the cue's length from the tip (studs)
local SHAFT = 0.56 -- the pale shaft's share of the length

local function part(name: string, color: Color3, material: Enum.Material): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Shape = Enum.PartType.Cylinder
	p.Material = material
	p.Color = color
	p.Transparency = 1
	p.Parent = workspace.CurrentCamera
	return p
end

function Stick.new(): any
	local self = setmetatable({}, Stick) :: any
	self.tip = part("CueTip", Color3.fromRGB(70, 120, 190), Enum.Material.Fabric)
	self.shaft = part("CueShaft", Color3.fromRGB(226, 196, 140), Enum.Material.Wood)
	self.butt = part("CueButt", Color3.fromRGB(58, 34, 22), Enum.Material.Wood)
	self.shown = false
	return self
end

-- A cylinder's CFrame (its axis is the part's X) for the stretch from `a` to `b`.
local function along(a: Vector3, b: Vector3): CFrame
	return CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0)
end

function Stick.pose(self: any, tip: Vector3, toward: Vector3, alpha: number?)
	local len = Furniture.CUE_LEN
	local t0 = tip
	local t1 = tip - toward * FERRULE
	local t2 = tip - toward * (len * SHAFT)
	local t3 = tip - toward * len
	local thin, thick = Furniture.CUE_TIP, Furniture.CUE_BUTT
	local mid = thin + (thick - thin) * SHAFT
	self.tip.Size = Vector3.new(FERRULE, thin, thin)
	self.tip.CFrame = along(t1, t0)
	self.shaft.Size = Vector3.new(len * SHAFT - FERRULE, (thin + mid) / 2, (thin + mid) / 2)
	self.shaft.CFrame = along(t2, t1)
	self.butt.Size = Vector3.new(len * (1 - SHAFT), (mid + thick) / 2, (mid + thick) / 2)
	self.butt.CFrame = along(t3, t2)
	local see = 1 - math.clamp(alpha or 1, 0, 1)
	self.tip.Transparency = see
	self.shaft.Transparency = see
	self.butt.Transparency = see
	self.shown = see < 1
end

function Stick.hide(self: any)
	if self.shown then
		self.shown = false
		self.tip.Transparency = 1
		self.shaft.Transparency = 1
		self.butt.Transparency = 1
	end
end

function Stick.destroy(self: any)
	self.shown = false
	self.tip:Destroy()
	self.shaft:Destroy()
	self.butt:Destroy()
end

return Stick
