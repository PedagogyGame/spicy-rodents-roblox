--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Render.MedicalView
-- What a bitten person looks like on this client (owner 2026-11-10: "sometimes the symptoms should
-- show up a bit later"; hospital_police_infection §6.7 red eyes). The server writes one attribute on
-- the body, Med (Server/Infection/InfectionService), and nothing at all while the infection
-- incubates; this module draws it:
--   symptomatic  two red glowing eyes on the head and a faint red glow on the whole body (the
--                visible tell: the eyes alone were two 0.2-stud balls, about 5 px across at 30 studs
--                and not there at all from behind); Animation/AnimationDriver adds the stagger
--   down         the red eyes stay off (v5.4 turns them off at the scene); the pose is drawn by
--                Animation/AnimationDriver, which reads the same attribute (sitting on the ground)
--   carried      nothing here: the patient is on their feet, walked to the ambulance by the crew
--                (the usual walk animation; a body that moves is not drawn sitting)
--   transit      the body is not drawn at all on this client (carried off in the ambulance; the
--                server also sinks it under the ground, so a missed hide shows nothing either)
--   treated      nothing here (AnimationDriver sits the patient up on the cot)
-- The eyes are client-made parts kept on the head every frame (no welds into a body another machine
-- may own); the glow is a client-made Highlight on the body (fill only, hidden behind walls); hiding
-- is LocalTransparencyModifier on the body's parts and decals, put back when the attribute changes,
-- and re-applied to parts that stream in while it is hidden.
-- No service access at require time (Lune requires this module).
-- Interface: start(opts { bodies }) -> stop(); look(med) -> { hidden, eyes, pose, glow? } (pure);
--   EYE { size, x, y, z, color }; GLOW { color, fill }

export type Look = { hidden: boolean, eyes: boolean, pose: string?, glow: boolean? }

local MedicalView = {}

-- on an R15 head (1.2 studs): either side of the nose, on the face (-Z is forward)
MedicalView.EYE = table.freeze({ size = 0.28, x = 0.2, y = 0.12, z = -0.55, color = { 255, 36, 28 } })
-- the fever glow: a red fill over the whole body, this transparent (faint, but there from any side)
MedicalView.GLOW = table.freeze({ color = { 255, 40, 30 }, fill = 0.8 })

-- look(med): what the attribute means on screen. Unknown values draw nothing.
function MedicalView.look(med: any): Look
	if med == "symptomatic" then
		return { hidden = false, eyes = true, pose = "stagger", glow = true }
	elseif med == "down" then
		return { hidden = false, eyes = false, pose = "down" }
	elseif med == "carried" then
		return { hidden = false, eyes = false, pose = "walk" }
	elseif med == "transit" then
		return { hidden = true, eyes = false, pose = nil }
	elseif med == "treated" then
		return { hidden = false, eyes = false, pose = "bed" }
	end
	return { hidden = false, eyes = false, pose = nil }
end

type Entry = {
	body: Model,
	conn: RBXScriptConnection,
	added: RBXScriptConnection?,
	hidden: boolean,
	eyes: { BasePart }?,
	glow: Highlight?,
}

function MedicalView.start(opts: { bodies: Instance }): () -> ()
	local RunService = game:GetService("RunService")
	local entries: { [Instance]: Entry } = {}
	local holder = Instance.new("Folder")
	holder.Name = "MedicalView"
	holder.Parent = workspace
	local spare: { BasePart } = {}

	local function setHidden(inst: Instance, hidden: boolean)
		if inst:IsA("BasePart") or inst:IsA("Decal") then
			pcall(function()
				(inst :: any).LocalTransparencyModifier = if hidden then 1 else 0
			end)
		end
	end

	local function eye(): BasePart
		local p = table.remove(spare)
		if p then
			return p
		end
		local e = MedicalView.EYE
		local part = Instance.new("Part")
		part.Name = "RedEye"
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.new(e.size, e.size, e.size)
		part.Material = Enum.Material.Neon
		part.Color = Color3.fromRGB(e.color[1], e.color[2], e.color[3])
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Transparency = 1 -- shown once it has been put on a head
		return part
	end

	local function apply(entry: Entry)
		local look = MedicalView.look(entry.body:GetAttribute("Med"))
		if look.hidden ~= entry.hidden then
			entry.hidden = look.hidden
			for _, d in entry.body:GetDescendants() do
				setHidden(d, look.hidden)
			end
			if entry.added then
				entry.added:Disconnect()
				entry.added = nil
			end
			if look.hidden then
				entry.added = entry.body.DescendantAdded:Connect(function(d: Instance)
					setHidden(d, true)
				end)
			end
		end
		if look.eyes and entry.eyes == nil then
			local a, b = eye(), eye()
			a.Parent, b.Parent = holder, holder
			entry.eyes = { a, b }
		elseif not look.eyes and entry.eyes then
			for _, p in entry.eyes do
				p.Parent = nil
				table.insert(spare, p)
			end
			entry.eyes = nil
		end
		if look.glow and entry.glow == nil then
			local g = MedicalView.GLOW
			local glow = Instance.new("Highlight")
			glow.Name = "Fever"
			glow.FillColor = Color3.fromRGB(g.color[1], g.color[2], g.color[3])
			glow.FillTransparency = g.fill
			glow.OutlineTransparency = 1
			glow.DepthMode = Enum.HighlightDepthMode.Occluded
			glow.Enabled = false -- switched on with the eyes, once the head is known to be drawn
			glow.Adornee = entry.body
			glow.Parent = holder
			entry.glow = glow
		elseif not look.glow and entry.glow then
			entry.glow:Destroy()
			entry.glow = nil
		end
	end

	local function add(child: Instance)
		if not child:IsA("Model") or entries[child] then
			return
		end
		local body = child :: Model
		local entry: Entry = { body = body, conn = nil :: any, added = nil, hidden = false, eyes = nil, glow = nil }
		entry.conn = body:GetAttributeChangedSignal("Med"):Connect(function()
			apply(entry)
		end)
		entries[child] = entry
		apply(entry) -- a body that streams in already ill
	end

	local function remove(child: Instance)
		local entry = entries[child]
		if entry == nil then
			return
		end
		entries[child] = nil
		entry.conn:Disconnect()
		if entry.added then
			entry.added:Disconnect()
		end
		if entry.eyes then
			for _, p in entry.eyes do
				p.Parent = nil
				table.insert(spare, p)
			end
		end
		if entry.glow then
			entry.glow:Destroy()
			entry.glow = nil
		end
	end

	local conns: { RBXScriptConnection } = {}
	table.insert(conns, opts.bodies.ChildAdded:Connect(add))
	table.insert(conns, opts.bodies.ChildRemoved:Connect(remove))
	for _, child in opts.bodies:GetChildren() do
		add(child)
	end
	-- the eyes ride the head: placed after the frame's animation, where the head is drawn
	table.insert(
		conns,
		RunService.RenderStepped:Connect(function()
			local e = MedicalView.EYE
			for _, entry in entries do
				local eyes = entry.eyes
				if eyes then
					local head = entry.body:FindFirstChild("Head")
					-- no eyes on a head that is not drawn: your own body in first person (the camera
					-- fades it with LocalTransparencyModifier; two red balls would hang in the view)
					-- or a hidden one; nor on a body with no head part (the cyclists' puppets)
					local drawn = head ~= nil and head:IsA("BasePart") and head.LocalTransparencyModifier < 0.5
					if drawn then
						local cf = (head :: BasePart).CFrame
						eyes[1].CFrame = cf * CFrame.new(-e.x, e.y, e.z)
						eyes[2].CFrame = cf * CFrame.new(e.x, e.y, e.z)
						eyes[1].Transparency, eyes[2].Transparency = 0, 0
					else
						eyes[1].Transparency, eyes[2].Transparency = 1, 1
					end
					-- (no glow either on a body that is not drawn: your own in first person)
					if entry.glow and entry.glow.Enabled ~= drawn then
						entry.glow.Enabled = drawn
					end
				end
			end
		end)
	)

	return function()
		for _, c in conns do
			c:Disconnect()
		end
		for child, entry in entries do
			if entry.hidden then
				for _, d in entry.body:GetDescendants() do
					setHidden(d, false)
				end
			end
			remove(child)
		end
		holder:Destroy()
	end
end

return MedicalView
