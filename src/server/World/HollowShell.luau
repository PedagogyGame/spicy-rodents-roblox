--!strict
-- ServerScriptService.Server.World.HollowShell
-- The hollow trees' insides and the fallen log as parts (Shared/World/HollowLayout: each hollow's `parts`, the one
-- place their geometry is worked out). The trees are the baked Blender meshes; their bark hides everything here
-- from outside, and its faces are not drawn from within, so the inside of a cavity is lined: rings of boards round
-- its wall, a floor and a roof, the spiral's treads and heartwood post, the shaft's hideout shelf; the dark oval of
-- each knothole sits on the bark outside; the log is boards round its run and a floor. Built at boot by
-- Foraging/HollowService (no bake: a few hundred plain parts), and by the specs (the same parts the motor is held to).
-- Nothing here collides or casts a shadow (the squirrel runs these on its rails; the bark collides already); a
-- knothole is not queried (sight and the camera look through it), the rest is. A dim warm light in each chamber.
-- Interface: build(env, layout, parent?) -> (Folder, Report). `env` is anything with Instance, CFrame, Vector3,
--   Color3 and Enum as the engine has them (the engine's globals, or @lune/roblox in the specs).
--   Report = { parts, lights, per = { [hollowId]: parts } }.

local HollowShell = {}

-- colours (RGB 0-255) and materials by piece role
HollowShell.LOOK = {
	liner = { color = { 112, 82, 54 }, material = "Wood" },
	floor = { color = { 86, 64, 44 }, material = "Wood" },
	roof = { color = { 74, 54, 38 }, material = "Wood" },
	tread = { color = { 132, 100, 68 }, material = "Wood" },
	post = { color = { 98, 72, 48 }, material = "Wood" },
	shelf = { color = { 132, 100, 68 }, material = "Wood" },
	knothole = { color = { 30, 22, 16 }, material = "SmoothPlastic" },
	log = { color = { 104, 80, 58 }, material = "Wood" },
}
HollowShell.LIGHT = { range = 9, brightness = 0.45, color = { 255, 196, 140 } }

export type Report = { parts: number, lights: number, per: { [string]: number } }

function HollowShell.build(env: any, layout: any, parent: any?): (any, Report)
	local Instance, CFrame, Vector3, Color3, Enum = env.Instance, env.CFrame, env.Vector3, env.Color3, env.Enum
	local root = Instance.new("Folder")
	root.Name = "HollowTrees"
	local report: Report = { parts = 0, lights = 0, per = {} }
	for _, h in layout.hollows do
		local model = Instance.new("Model")
		model.Name = h.id
		model:SetAttribute("Space", h.space)
		local n = 0
		for i, pc in h.parts do
			local look = HollowShell.LOOK[pc.role] or HollowShell.LOOK.liner
			local p = Instance.new("Part")
			p.Name = `{pc.role}{i}`
			p.Shape = if pc.shape == "Cylinder" then Enum.PartType.Cylinder else Enum.PartType.Block
			p.Size = Vector3.new(pc.size[1], pc.size[2], pc.size[3])
			p.CFrame = CFrame.fromMatrix(
				Vector3.new(pc.p[1], pc.p[2], pc.p[3]),
				Vector3.new(pc.xv[1], pc.xv[2], pc.xv[3]),
				Vector3.new(pc.yv[1], pc.yv[2], pc.yv[3])
			)
			p.Anchored = true
			p.CanCollide = false
			p.CanTouch = false
			p.CanQuery = pc.role ~= "knothole"
			p.CastShadow = false
			p.Material = (Enum.Material :: any)[look.material]
			p.Color = Color3.fromRGB(look.color[1], look.color[2], look.color[3])
			p.TopSurface = Enum.SurfaceType.Smooth
			p.BottomSurface = Enum.SurfaceType.Smooth
			if pc.role == "floor" and h.variant ~= "log" then
				local l = Instance.new("PointLight")
				l.Range = HollowShell.LIGHT.range
				l.Brightness = HollowShell.LIGHT.brightness
				l.Color =
					Color3.fromRGB(HollowShell.LIGHT.color[1], HollowShell.LIGHT.color[2], HollowShell.LIGHT.color[3])
				l.Shadows = false
				l.Parent = p
				report.lights += 1
			end
			p.Parent = model
			n += 1
		end
		report.per[h.id] = n
		report.parts += n
		model.Parent = root
	end
	if parent then
		root.Parent = parent
	end
	return root, report
end

return HollowShell
