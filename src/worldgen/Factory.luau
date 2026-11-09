--!strict
-- ServerScriptService.Server.WorldGen.Factory
-- Instance-creation shim: the same builders run under Lune (@lune/roblox) and in the engine
-- (globals). Interface (BUILD_PLAN §1.4): new(env) -> Factory with
--   instance(className, name) / part(PartSpec) / model(name, plan)
-- `env` carries Instance, Vector3, CFrame, Color3 and Enum; Factory.engineEnv() returns the globals.
-- No side effects on require.

local Plan = require("./Plan")

local Factory = {}

export type Env = { Instance: any, Vector3: any, CFrame: any, Color3: any, Enum: any }
export type Factory = {
	env: Env,
	instance: (className: string, name: string) -> any,
	part: (spec: Plan.PartSpec) -> any,
	model: (name: string, plan: Plan.BuildPlan) -> any,
}

function Factory.engineEnv(): Env
	return { Instance = Instance, Vector3 = Vector3, CFrame = CFrame, Color3 = Color3, Enum = Enum }
end

function Factory.new(env: Env): Factory
	local self = {} :: Factory
	self.env = env

	function self.instance(className: string, name: string): any
		local inst = env.Instance.new(className)
		inst.Name = name
		return inst
	end

	function self.part(spec: Plan.PartSpec): any
		local p = env.Instance.new("Part")
		p.Name = spec.name
		p.Anchored = true
		p.CanCollide = spec.canCollide
		p.CanTouch = false
		p.CanQuery = spec.transparency < 1
		p.CastShadow = spec.canCollide
		p.Size = env.Vector3.new(spec.sx, spec.sy, spec.sz)
		p.CFrame = env.CFrame.new(spec.cx, spec.cy, spec.cz)
			* env.CFrame.Angles(0, spec.yaw, 0)
			* env.CFrame.Angles(spec.pitch, 0, 0)
		p.Color = env.Color3.fromRGB(spec.color[1], spec.color[2], spec.color[3])
		p.Material = (env.Enum.Material :: any)[spec.material]
		p.Transparency = spec.transparency
		p.TopSurface = env.Enum.SurfaceType.Smooth
		p.BottomSurface = env.Enum.SurfaceType.Smooth
		return p
	end

	function self.model(name: string, plan: Plan.BuildPlan): any
		local m = env.Instance.new("Model")
		m.Name = name
		m.LevelOfDetail = (env.Enum.ModelLevelOfDetail :: any)[plan.lod]
		m.ModelStreamingMode = (env.Enum.ModelStreamingMode :: any)[plan.streaming]
		local keys: { string } = {}
		for k in plan.attributes do
			table.insert(keys, k)
		end
		table.sort(keys)
		for _, k in keys do
			m:SetAttribute(k, plan.attributes[k])
		end
		return m
	end

	return self
end

return Factory
