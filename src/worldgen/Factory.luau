--!strict
-- ServerScriptService.Server.WorldGen.Factory
-- Instance-creation shim: the same builders run under Lune (@lune/roblox) and in the engine
-- (globals). Interface (BUILD_PLAN §1.4): new(env) -> Factory with
--   instance(className, name) / part(PartSpec) / model(name, plan) / extra(ExtraSpec, partsByName)
-- `env` carries Instance, Vector3, CFrame, Color3, Enum, UDim2 and ColorSequence;
-- Factory.engineEnv() returns the globals. No side effects on require.

local Spec = require("./Spec")

local Factory = {}

export type Env = {
	Instance: any,
	Vector3: any,
	CFrame: any,
	Color3: any,
	Enum: any,
	UDim2: any?,
	ColorSequence: any?,
}
export type Factory = {
	env: Env,
	instance: (className: string, name: string) -> any,
	part: (spec: Spec.PartSpec) -> any,
	model: (name: string, plan: Spec.BuildPlan) -> any,
	extra: (spec: Spec.ExtraSpec, parts: { [string]: any }) -> any,
}

function Factory.engineEnv(): Env
	return {
		Instance = Instance,
		Vector3 = Vector3,
		CFrame = CFrame,
		Color3 = Color3,
		Enum = Enum,
		UDim2 = UDim2,
		ColorSequence = ColorSequence,
	}
end

local function setAttrs(inst: any, attrs: { [string]: string | number | boolean }?)
	if not attrs then
		return
	end
	local keys: { string } = {}
	for k in attrs do
		table.insert(keys, k)
	end
	table.sort(keys)
	for _, k in keys do
		inst:SetAttribute(k, attrs[k])
	end
end

function Factory.new(env: Env): Factory
	local self = {} :: Factory
	self.env = env

	function self.instance(className: string, name: string): any
		local inst = env.Instance.new(className)
		inst.Name = name
		return inst
	end

	function self.part(spec: Spec.PartSpec): any
		local p = env.Instance.new(if spec.shape == "Wedge" then "WedgePart" else "Part")
		p.Name = spec.name
		p.Anchored = true
		if spec.shape == "Cylinder" then
			p.Shape = env.Enum.PartType.Cylinder
		elseif spec.shape == "Ball" then
			p.Shape = env.Enum.PartType.Ball
		end
		p.CanCollide = spec.canCollide
		p.CanTouch = false
		if spec.canQuery ~= nil then
			p.CanQuery = spec.canQuery
		else
			p.CanQuery = spec.transparency < 1
		end
		p.CastShadow = if spec.castShadow ~= nil then spec.castShadow else spec.canCollide
		p.Size = env.Vector3.new(spec.sx, spec.sy, spec.sz)
		local cf = env.CFrame.new(spec.cx, spec.cy, spec.cz)
			* env.CFrame.Angles(0, spec.yaw, 0)
			* env.CFrame.Angles(spec.pitch, 0, 0)
		if spec.roll and spec.roll ~= 0 then
			cf = cf * env.CFrame.Angles(0, 0, spec.roll)
		end
		p.CFrame = cf
		p.Color = env.Color3.fromRGB(spec.color[1], spec.color[2], spec.color[3])
		p.Material = (env.Enum.Material :: any)[spec.material]
		p.Transparency = spec.transparency
		p.TopSurface = env.Enum.SurfaceType.Smooth
		p.BottomSurface = env.Enum.SurfaceType.Smooth
		setAttrs(p, spec.attrs)
		return p
	end

	function self.model(name: string, plan: Spec.BuildPlan): any
		local m = env.Instance.new("Model")
		m.Name = name
		m.LevelOfDetail = (env.Enum.ModelLevelOfDetail :: any)[plan.lod]
		m.ModelStreamingMode = (env.Enum.ModelStreamingMode :: any)[plan.streaming]
		setAttrs(m, plan.attributes)
		return m
	end

	-- Non-part instances (Spec.ExtraSpec), parented to the named part of the same model.
	function self.extra(e: Spec.ExtraSpec, parts: { [string]: any }): any
		local host = parts[e.part] or error("Factory.extra: no part " .. e.part .. " for " .. e.name)
		local inst
		if e.kind == "SurfaceGui" then
			inst = env.Instance.new("SurfaceGui")
			inst.Face = (env.Enum.NormalId :: any)[e.face or "Front"]
			inst.SizingMode = env.Enum.SurfaceGuiSizingMode.PixelsPerStud
			inst.PixelsPerStud = 20
			local label = env.Instance.new("TextLabel")
			label.Name = "Text"
			label.Text = e.text or ""
			label.TextScaled = true
			label.BackgroundTransparency = 1
			label.TextColor3 = env.Color3.fromRGB(246, 233, 189)
			if env.UDim2 then
				label.Size = env.UDim2.fromScale(1, 1)
			end
			label.Parent = inst
		elseif e.kind == "Prompt" then
			inst = env.Instance.new("Attachment")
			local o = e.offset or { 0, 0, 0 }
			inst.Position = env.Vector3.new(o[1], o[2], o[3])
			local prompt = env.Instance.new("ProximityPrompt")
			prompt.Name = "ProximityPrompt"
			prompt.ActionText = e.action or "Use"
			prompt.Enabled = false -- placeholder until the W2 services wire it
			prompt.RequiresLineOfSight = false
			prompt.Parent = inst
		elseif e.kind == "Attachment" then
			inst = env.Instance.new("Attachment")
			local o = e.offset or { 0, 0, 0 }
			inst.Position = env.Vector3.new(o[1], o[2], o[3])
		elseif e.kind == "Beam" then
			inst = env.Instance.new("Beam")
			inst.Attachment0 = host:FindFirstChild(e.a :: string)
			inst.Attachment1 = host:FindFirstChild(e.b :: string)
			inst.Width0 = e.width or 0.2
			inst.Width1 = e.width or 0.2
			inst.FaceCamera = true
			inst.Segments = 1
			if env.ColorSequence and e.color then
				inst.Color = env.ColorSequence.new(env.Color3.fromRGB(e.color[1], e.color[2], e.color[3]))
			end
		else
			error("Factory.extra: unknown kind " .. e.kind)
		end
		inst.Name = e.name
		setAttrs(inst, e.attrs)
		inst.Parent = host
		return inst
	end

	return self
end

return Factory
