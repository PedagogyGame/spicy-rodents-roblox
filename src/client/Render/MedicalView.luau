--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Render.MedicalView
-- What a bitten person looks like on this client (owner 2026-11-10: "sometimes the symptoms should
-- show up a bit later"; hospital_police_infection §6.7 red eyes). The server writes one attribute on
-- the body, Med (Server/Infection/InfectionService), and nothing at all while the infection
-- incubates; this module draws it:
--   symptomatic  two small red glowing eyes on the head (the visible tell)
--   down         the red eyes stay off (v5.4 turns them off at the scene); the pose is drawn by
--                Animation/AnimationDriver, which reads the same attribute (sitting on the ground)
--   carried      nothing here: the patient is on their feet, walked to the ambulance by the crew
--                (the usual walk animation; a body that moves is not drawn sitting)
--   transit      the body is not drawn at all on this client (carried off in the ambulance; the
--                server also sinks it under the ground, so a missed hide shows nothing either)
--   treated      nothing here (AnimationDriver sits the patient up on the cot)
-- The eyes are client-made parts kept on the head every frame (no welds into a body another machine
-- may own); hiding is LocalTransparencyModifier on the body's parts and decals, put back when the
-- attribute changes, and re-applied to parts that stream in while it is hidden.
-- No service access at require time (Lune requires this module).
-- Interface: start(opts { bodies }) -> stop(); look(med) -> { hidden, eyes, pose } (pure);
--   EYE { size, x, y, z, color }

export type Look = { hidden: boolean, eyes: boolean, pose: string? }

local MedicalView = {}

-- on an R15 head (1.2 studs): either side of the nose, on the face (-Z is forward)
MedicalView.EYE = table.freeze({ size = 0.2, x = 0.2, y = 0.12, z = -0.57, color = { 255, 36, 28 } })

-- look(med): what the attribute means on screen. Unknown values draw nothing.
function MedicalView.look(med: any): Look
	if med == "symptomatic" then
		return { hidden = false, eyes = true, pose = "stagger" }
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
	end

	local function add(child: Instance)
		if not child:IsA("Model") or entries[child] then
			return
		end
		local body = child :: Model
		local entry: Entry = { body = body, conn = nil :: any, added = nil, hidden = false, eyes = nil }
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
					if head and head:IsA("BasePart") and head.LocalTransparencyModifier < 0.5 then
						eyes[1].CFrame = head.CFrame * CFrame.new(-e.x, e.y, e.z)
						eyes[2].CFrame = head.CFrame * CFrame.new(e.x, e.y, e.z)
						eyes[1].Transparency, eyes[2].Transparency = 0, 0
					else
						eyes[1].Transparency, eyes[2].Transparency = 1, 1
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
