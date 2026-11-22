--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.WhackAMole.Hand
-- A HAND ON THE MALLET (owner, D29: "when playing whack a mole, there is no hand, holding the mallet"): while the
-- mallet swings, a right arm holds it: a round fist on the foot of the handle (and its thumb over it), the forearm and the
-- upper arm up to the shoulder of the person playing, in that body's own colours (the hand's skin, the lower and
-- upper arm as the body has them: a sleeve, or bare skin). The fist is fixed on the handle, so it goes through
-- the swing with the mallet; the arm bends at the elbow (dropped and a little outward) and the upper arm runs to
-- the shoulder whatever the reach (the far holes are further than a real arm: it stretches, as a cartoon arm
-- does). From the player's own camera (above and behind the head) the arm comes up from the bottom of the
-- screen; a bystander sees the person's right arm reach for the mallet (the body's own right arm is hidden on
-- that screen while the drawn one is shown, so there are never two). When the mallet goes home to its bracket
-- the hand lets go (hidden; the body's own arm is back).
-- Parts are made on this screen only, under the cabinet model: Fist, Thumb, Forearm, Elbow, UpperArm (5 parts,
-- three balls and two cylinders, anchored, no collision, query, touch or shadow); moved only when the mallet is.
-- Interface: solve(pivot, shoulder, right) -> Pose (the five parts' CFrames and the upper arm's length; pivot
-- is the mallet's pivot, the foot of its handle with the handle along its +Y; right is the player's right);
--   colours(body?) -> (skin, forearm, upperArm) Color3s (defaults: SKIN, SLEEVE); shoulderOf(body?) -> Vector3?;
--   new(parent) -> Hand; show(hand, body?) (coloured as that body, its own right arm hidden); hide(hand);
--   place(hand, pose); SIZES; SHOULDER; SKIN; SLEEVE; DROP; OUT; MODEL

local Import = require("../../Import")
local Layout =
	Import.shared("Minigames/WhackAMole/Layout") :: typeof(require("../../../shared/Minigames/WhackAMole/Layout"))

local Hand = {}

local m = Layout.m

Hand.SIZES = {
	grip = m(0.045), -- the fist's middle along the handle from its foot (the foot is inside the fist)
	fistD = m(0.115),
	thumbD = m(0.042),
	fore = m(0.27), -- the forearm, from the middle of the fist to the elbow
	foreD = m(0.085),
	upperD = m(0.095),
}
-- where a body's right shoulder is when nobody's can be read (the cabinet frame, studs: u to the player's right,
-- v up from the floor; it stands where the player stands, Layout.STAND)
Hand.SHOULDER = { u = 0.9, v = 4.4 }
Hand.SKIN = { 224, 176, 138 } -- a plain skin tone, for a body that has no hand to read
Hand.SLEEVE = { 74, 84, 104 } -- a neutral grey-blue sleeve
-- the elbow drops this much (a fraction of the forearm's direction) and goes out this much to the player's right
Hand.DROP = 0.45
Hand.OUT = 0.3
Hand.MODEL = "MalletHand" -- the model the parts are made in: Fist, Thumb, Forearm, Elbow, UpperArm
-- the body's own right arm, hidden on this screen while the drawn one holds the mallet
local ARM = { "RightUpperArm", "RightLowerArm", "RightHand", "Right Arm" }

export type Pose = {
	fist: CFrame,
	thumb: CFrame,
	forearm: CFrame,
	elbow: CFrame,
	upper: CFrame,
	upperLen: number,
}

export type Hand = {
	model: any,
	parts: { [string]: any },
	on: boolean,
	body: any?, -- whose arm it is (nil: nobody's could be found)
	hidden: { any }, -- the body's own parts hidden while this is shown
}

-- a cylinder's CFrame (its axis is the part's X) from a to b
local function along(a: Vector3, b: Vector3): CFrame
	local mid = (a + b) / 2
	if (b - a).Magnitude < 1e-4 then
		return CFrame.new(mid)
	end
	return CFrame.lookAt(mid, b) * CFrame.Angles(0, math.pi / 2, 0)
end

function Hand.solve(pivot: CFrame, shoulder: Vector3, right: Vector3): Pose
	local S = Hand.SIZES
	local axis = pivot.UpVector
	local fist = pivot * CFrame.new(0, S.grip, 0)
	local c = fist.Position
	local toS = shoulder - c
	if toS.Magnitude < 1e-3 then
		toS = -axis
	end
	local dir = toS.Unit
	local bend = dir + right.Unit * Hand.OUT - Vector3.yAxis * Hand.DROP
	if bend.Magnitude < 1e-3 then
		bend = dir
	end
	local e = c + bend.Unit * S.fore
	-- the thumb over the top of the fist, on the side the forearm leaves from
	local side = dir - axis * dir:Dot(axis)
	side = if side.Magnitude > 1e-3 then side.Unit else pivot.LookVector
	local thumb = c + axis * (S.fistD * 0.4) + side * (S.fistD * 0.22)
	local upperLen = math.max((shoulder - e).Magnitude, 0.05)
	return {
		fist = fist,
		thumb = CFrame.new(thumb),
		forearm = along(c, e),
		elbow = CFrame.new(e),
		upper = along(e, shoulder),
		upperLen = upperLen,
	}
end

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function partColor(body: any, name: string): Color3?
	local p = body and body:FindFirstChild(name)
	if p and p:IsA("BasePart") then
		return p.Color
	end
	return nil
end

-- The colours of the hand, the forearm and the upper arm: the body's own (an R15 body, or a classic one's arm),
-- else a plain skin tone and a neutral sleeve.
function Hand.colours(body: any?): (Color3, Color3, Color3)
	local skin = partColor(body, "RightHand") or partColor(body, "Right Arm") or rgb(Hand.SKIN)
	local fore = partColor(body, "RightLowerArm") or partColor(body, "Right Arm") or rgb(Hand.SLEEVE)
	local upper = partColor(body, "RightUpperArm") or fore
	return skin, fore, upper
end

-- The body's right shoulder (its RightShoulder joint), or nil.
function Hand.shoulderOf(body: any?): Vector3?
	if body == nil then
		return nil
	end
	for _, d in body:GetDescendants() do
		if d.Name == "RightShoulder" and d:IsA("Motor6D") and d.Part0 ~= nil then
			return (d.Part0.CFrame * d.C0).Position
		end
	end
	return nil
end

local function make(parent: any, name: string, shape: Enum.PartType): any
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Transparency = 1
	p.Parent = parent
	return p
end

function Hand.new(parent: any): Hand
	local model = Instance.new("Model")
	model.Name = Hand.MODEL
	local S = Hand.SIZES
	local parts = {
		Fist = make(model, "Fist", Enum.PartType.Ball),
		Thumb = make(model, "Thumb", Enum.PartType.Ball),
		Forearm = make(model, "Forearm", Enum.PartType.Cylinder),
		Elbow = make(model, "Elbow", Enum.PartType.Ball),
		UpperArm = make(model, "UpperArm", Enum.PartType.Cylinder),
	}
	parts.Fist.Size = Vector3.new(S.fistD, S.fistD, S.fistD)
	parts.Thumb.Size = Vector3.new(S.thumbD, S.thumbD, S.thumbD)
	parts.Forearm.Size = Vector3.new(S.fore, S.foreD, S.foreD)
	parts.Elbow.Size = Vector3.new(S.upperD, S.upperD, S.upperD)
	parts.UpperArm.Size = Vector3.new(1, S.upperD, S.upperD)
	model.Parent = parent
	return { model = model, parts = parts, on = false, body = nil, hidden = {} }
end

function Hand.hide(h: Hand)
	if not h.on then
		return
	end
	h.on = false
	h.body = nil
	for _, p in h.parts do
		p.Transparency = 1
	end
	for _, p in h.hidden do
		if p.Parent ~= nil then
			p.LocalTransparencyModifier = 0
		end
	end
	table.clear(h.hidden)
end

function Hand.show(h: Hand, body: any?)
	Hand.hide(h)
	h.on = true
	h.body = body
	local skin, fore, upper = Hand.colours(body)
	local P = h.parts
	P.Fist.Color, P.Thumb.Color = skin, skin
	P.Forearm.Color = fore
	P.Elbow.Color, P.UpperArm.Color = upper, upper
	for _, p in P do
		p.Transparency = 0
	end
	if body ~= nil then
		for _, name in ARM do
			local p = body:FindFirstChild(name)
			if p and p:IsA("BasePart") then
				p.LocalTransparencyModifier = 1
				table.insert(h.hidden, p)
			end
		end
	end
end

function Hand.place(h: Hand, pose: Pose)
	local P = h.parts
	P.Fist.CFrame = pose.fist
	P.Thumb.CFrame = pose.thumb
	P.Forearm.CFrame = pose.forearm
	P.Elbow.CFrame = pose.elbow
	local S = Hand.SIZES
	P.UpperArm.Size = Vector3.new(pose.upperLen, S.upperD, S.upperD)
	P.UpperArm.CFrame = pose.upper
end

return Hand
