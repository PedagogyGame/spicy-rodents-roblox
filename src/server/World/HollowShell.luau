--!strict
-- ServerScriptService.Server.World.HollowShell
-- The hollow trees' insides and the fallen log as parts (Shared/World/HollowLayout: each hollow's `parts`, the one
-- place their geometry is worked out). The trees are the baked Blender meshes; their bark hides everything here
-- from outside, and its faces are not drawn from within, so the inside of a cavity is lined: rings of boards round
-- its wall, a floor and a roof, the spiral's treads and heartwood post, the shaft's hideout shelf; the dark oval of
-- each knothole sits on the bark outside; the log is boards round its run and a floor. Built at boot by
-- Foraging/HollowService (no bake: a few hundred plain parts), and by the specs (the same parts the motor is held to).
-- Nothing in a tree collides or casts a shadow (the squirrel runs these on its rails; the bark collides already);
-- the log's boards collide (they are the log), and so does an invisible threshold disc just inside each of its ends
-- (a body walking in off the run is stopped there; the run itself rides past it); a knothole is not queried (sight
-- and the camera look through it). A dim warm light in each floor's chamber and at each chamber above it, its range
-- no more than the bark's radius round it (rangeIn), so it lights the inside and never the lawn or a wall outside
-- (no shadows: the bark would not stop it).
--   rangeIn(hollow, x, y, z) -> studs (pure)
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
	threshold = { color = { 104, 80, 58 }, material = "SmoothPlastic" }, -- (never drawn)
}
-- (range: the most a light reaches; brightness: at that range. A light held to a shorter range is brighter in
-- proportion, up to maxBrightness, so its chamber's walls read about as lit: the engine's falloff ends at the range)
HollowShell.LIGHT = { range = 9, brightness = 0.45, maxBrightness = 2, color = { 255, 196, 140 } }
-- (Shared/World/HollowLayout.C: room, a chamber higher than this over the floor gets a light; wall, the bark kept
-- round a cavity)
local C = { room = 2.8, wall = 0.45 }

-- rangeIn: a light's range at (x, y, z) in a hollow: HollowShell.LIGHT.range, but no further than the bark round
-- the widest of its cavities there (a cavity is the bark less C.wall at its narrowest), less 0.3 for the lean
function HollowShell.rangeIn(h: any, x: number, y: number, z: number): number
	local r = 0
	for _, c in h.cavities do
		if c.a == nil and y >= c.bottom - 0.5 and y <= c.top + 0.5 then
			local d = math.sqrt((x - c.x) ^ 2 + (z - c.z) ^ 2)
			if d < c.radius then
				r = math.max(r, c.radius + C.wall - d - 0.3)
			end
		end
	end
	return math.min(HollowShell.LIGHT.range, r)
end

local function light(env: any, parent: any, range: number)
	local l = env.Instance.new("PointLight")
	local L = HollowShell.LIGHT
	l.Range = range
	l.Brightness = math.min(L.maxBrightness, L.brightness * L.range / math.max(range, 0.5))
	l.Color = env.Color3.fromRGB(HollowShell.LIGHT.color[1], HollowShell.LIGHT.color[2], HollowShell.LIGHT.color[3])
	l.Shadows = false
	l.Parent = parent
end

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
			-- (the log's boards stand in people's way, its thresholds stop a body off its run; nothing else is reachable)
			p.CanCollide = pc.role == "log" or pc.role == "threshold"
			p.Transparency = if pc.role == "threshold" then 1 else 0
			p.CanTouch = false
			p.CanQuery = pc.role ~= "knothole"
			p.CastShadow = false
			p.Material = (Enum.Material :: any)[look.material]
			p.Color = Color3.fromRGB(look.color[1], look.color[2], look.color[3])
			p.TopSurface = Enum.SurfaceType.Smooth
			p.BottomSurface = Enum.SurfaceType.Smooth
			if pc.role == "floor" and h.variant ~= "log" then
				-- half way up the floor's chamber, over its middle
				local c = h.cavities[1]
				local at = Vector3.new(c.x, pc.p[2] + C.room / 2, c.z)
				local a = Instance.new("Attachment")
				a.Name = "floor_light"
				a.CFrame = p.CFrame:Inverse() * CFrame.new(at)
				a.Parent = p
				light(env, a, HollowShell.rangeIn(h, at.X, at.Y, at.Z))
				report.lights += 1
			end
			p.Parent = model
			n += 1
		end
		-- a light at each chamber up off the floor (the spiral's landings, the shaft's store and hideout): the
		-- floor's light does not reach them; an attachment on the first piece, on the cavity's middle line at the
		-- chamber's height (the bark is as far as it can be all round: the widest range)
		local anchor = model:FindFirstChildWhichIsA("BasePart")
		local floorY = math.huge
		local mid = h.cavities[#h.cavities]
		for _, c in h.cavities do
			floorY = math.min(floorY, c.bottom)
		end
		-- (round the spiral's heartwood post: just off it, towards the landing)
		local post = 0
		for _, pc in h.parts do
			if pc.role == "post" then
				post = math.max(post, pc.size[2] / 2 + 0.4)
			end
		end
		for _, c in h.chambers do
			if anchor and h.variant ~= "log" and c.y > floorY + C.room then
				local dx, dz = c.x - mid.x, c.z - mid.z
				local dl = math.max(1e-6, math.sqrt(dx * dx + dz * dz))
				local off = math.min(post, dl)
				local at = Vector3.new(mid.x + dx / dl * off, c.y + 1.4, mid.z + dz / dl * off)
				local a = Instance.new("Attachment")
				a.Name = `chamber_{c.id}`
				a.CFrame = anchor.CFrame:Inverse() * CFrame.new(at)
				a.Parent = anchor
				light(env, a, HollowShell.rangeIn(h, at.X, at.Y, at.Z))
				report.lights += 1
			end
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
