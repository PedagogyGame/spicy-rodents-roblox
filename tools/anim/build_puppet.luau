--!strict
-- tools/anim/build_puppet: clip JSON -> a Motor6D puppet .rbxm that plays the uploaded clip
-- (spike S7 second half: "in OS-1a it plays without flipped joints"). Lune only.
--   lune run tools/anim/build_puppet.luau <clip.json> <animationAssetId> <out.rbxm>
-- One thin block per bone from its head to its tail, named after the bone (RigSpec), joined to
-- its parent by a Motor6D of the same name whose joint frame sits at the bone head with identity
-- rotation: exactly the frame convention of spicy-clip/1, so Pose.CFrame == Motor6D.Transform.
-- RootPart (anchored) is the PrimaryPart; an AnimationController + Animator and a Script that
-- loops the clip are included, so the owner only inserts the file and presses Play.

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Instance = roblox.Instance
local CFrame = roblox.CFrame
local Vector3 = roblox.Vector3

local input, assetId, output = process.args[1], process.args[2], process.args[3]
if input == nil or assetId == nil or output == nil then
	print("usage: lune run tools/anim/build_puppet.luau <clip.json> <animationAssetId> <out.rbxm>")
	process.exit(2)
end
local clip = serde.decode("json", fs.readFile(input))
local LIFT = Vector3.new(0, 3, 0) -- stand the puppet clear of the baseplate

local model = Instance.new("Model")
model.Name = `S7Puppet_{clip.rig}_{clip.clip}`
local root = Instance.new("Part")
root.Name = clip.rootPart or "RootPart"
root.Size = Vector3.new(0.6, 0.2, 1.2)
root.CFrame = CFrame.new(LIFT)
root.Anchored = true
root.CanCollide = false
root.Transparency = 0.5
root.Parent = model
model.PrimaryPart = root

local parts: { [string]: any } = {}
local heads: { [string]: any } = {}
for _, b in clip.bones do
	local head = Vector3.new(b.head[1], b.head[2], b.head[3]) + LIFT
	local tail = Vector3.new(b.tail[1], b.tail[2], b.tail[3]) + LIFT
	local len = math.max((tail - head).Magnitude, 0.1)
	local p = Instance.new("Part")
	p.Name = b.name
	p.Size = Vector3.new(0.12, 0.12, len)
	p.CFrame = if (tail - head).Magnitude > 1e-3 then CFrame.lookAt((head + tail) / 2, tail) else CFrame.new(head)
	p.Anchored = false
	p.CanCollide = false
	p.Massless = true
	p.Color = if string.sub(b.name, -1) == "L" or string.find(b.name, "L_", 1, true)
		then roblox.Color3.fromRGB(220, 60, 60)
		else roblox.Color3.fromRGB(183, 132, 83)
	p.Parent = model
	parts[b.name] = p
	heads[b.name] = head
end
for _, b in clip.bones do
	local parent = if b.parent then parts[b.parent] else root
	local joint = CFrame.new(heads[b.name])
	local m = Instance.new("Motor6D")
	m.Name = b.name
	m.Part0 = parent
	m.Part1 = parts[b.name]
	m.C0 = parent.CFrame:Inverse() * joint
	m.C1 = parts[b.name].CFrame:Inverse() * joint
	m.Parent = parent
end

local controller = Instance.new("AnimationController")
controller.Parent = model
Instance.new("Animator").Parent = controller
local anim = Instance.new("Animation")
anim.Name = clip.clip
anim.AnimationId = `rbxassetid://{assetId}`
anim.Parent = model
local script = Instance.new("Script")
script.Name = "PlayClip"
script.Source = table.concat({
	"-- S7 OS-1a check: loops the uploaded clip. Left legs are red; the tail should wave and the",
	"-- legs swing fore and aft along -Z (the facing). Flipped joints show as legs swinging sideways.",
	"local model = script.Parent",
	"local animator = model:WaitForChild('AnimationController'):WaitForChild('Animator')",
	`local track = animator:LoadAnimation(model:WaitForChild('{clip.clip}'))`,
	"track.Looped = true",
	"track:Play()",
	"print('S7 puppet playing', track.Animation.AnimationId, 'length', track.Length)",
}, "\n")
script.Parent = model

fs.writeFile(output, roblox.serializeModel({ model }))
print(`wrote {output}: {#clip.bones} bones, Motor6Ds named after RigSpec bones, clip rbxassetid://{assetId}`)
