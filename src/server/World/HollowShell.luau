--!strict
-- ServerScriptService.Server.World.HollowShell
-- The hollow trees' insides and the fallen log as parts (Shared/World/HollowLayout: each hollow's `parts`, the one
-- place their geometry is worked out). The trees are the baked Blender meshes; their bark hides everything here
-- from outside, and its faces are not drawn from within, so the inside of a cavity is closed by its own wall: a ring of
-- narrow staves round it from the floor to the roof (each its own shade, a few dark streaks), open only at the holes,
-- each hole up a trunk lined back to the bark (the rim: a dark recess with a lip); knots (burls) bulging from it,
-- rounded; a floor and a roof; the winding climb's round shelves (fungus-like growths, not planks) and the gnarled
-- roots across; the shaft's hideout shelf; the dark oval of each knothole sits on the bark outside (Camera/CameraRig
-- hides a hollow's ovals on the screen of a player inside it: from within they would hang in the air over the holes),
-- and under a hole up a trunk the short branch its hop lands on (a perch); the log is boards round its run and a floor.
-- Grain (owner D33: "textured gnarliness ... but also grainularity"): every part is Wood, its colour the role's with
-- the piece's tone; given the trees' bark colour maps (opts.bark: Server/Assets/TreeArt's maps, the same tileable bark
-- the tree's own mesh wears), the staves, the floor and the roof also wear their tree's bark map on their inner face (a
-- Texture tinted with the piece's shade, tiled GRAIN.u by GRAIN.v studs, each at its own seeded offset so no two
-- staves line up). Built at boot by
-- Foraging/HollowService (no bake: a few hundred plain parts), and by the specs (the same parts the motor is held to).
-- Nothing in a tree collides or casts a shadow (the squirrel runs these on its rails; the bark collides already);
-- the log's boards collide (they are the log), and so does an invisible threshold disc just inside each of its ends
-- (a body walking in off the run is stopped there; the run itself rides past it); a knothole is not queried (sight
-- and the camera look through it). A dim warm light in each floor's chamber and at each chamber above it, its range
-- no more than the bark's radius round it (rangeIn), so it lights the inside and never the lawn or a wall outside
-- (no shadows: the bark would not stop it). Daylight comes in at each hole up a trunk: a dim cool light just inside
-- it, held to the bark the same way (owner D32: the inside "lit dimly through holes").
--   rangeIn(hollow, x, y, z) -> studs (pure); barkMaps(treeArt) -> { [trunkRoute]: colour map } (pure: the records of
--   Shared/Generated/TreeArt)
-- Interface: build(env, layout, parent?, opts?) -> (Folder, Report). `env` is anything with Instance, CFrame, Vector3,
--   Color3 and Enum as the engine has them (the engine's globals, or @lune/roblox in the specs); opts = { bark:
--   { [trunk route]: content id }? }.
--   Report = { parts, lights, textures, per = { [hollowId]: parts } }.

local HollowShell = {}

-- colours (RGB 0-255) and materials by piece role; `tone`: how far a piece's tone moves its colour either way (else
-- HollowShell.TONE)
HollowShell.LOOK = {
	liner = { color = { 104, 76, 50 }, material = "Wood", tone = 0.28 }, -- the staves (a streak is a third darker)
	floor = { color = { 86, 64, 44 }, material = "Wood" },
	roof = { color = { 66, 48, 34 }, material = "Wood" },
	tread = { color = { 150, 112, 70 }, material = "Wood", tone = 0.2 }, -- the round shelves (fungus-like)
	post = { color = { 98, 72, 48 }, material = "Wood" },
	shelf = { color = { 132, 100, 68 }, material = "Wood" },
	burl = { color = { 88, 62, 40 }, material = "Wood", tone = 0.22 },
	root = { color = { 84, 62, 42 }, material = "Wood" },
	rim = { color = { 60, 44, 31 }, material = "Wood" }, -- a hole's lining: a dark recess
	perch = { color = { 96, 74, 56 }, material = "Wood" },
	knothole = { color = { 30, 22, 16 }, material = "SmoothPlastic" },
	log = { color = { 104, 80, 58 }, material = "Wood" },
	threshold = { color = { 104, 80, 58 }, material = "SmoothPlastic" }, -- (never drawn)
}
-- the bark map on the inner faces: which roles wear it and on which face (the staves' inner face is their front, -z;
-- a floor's top and a roof's underside are a Cylinder's ends, +x and -x), tiled u by v studs, tinted `tint` (RGB, a
-- light warm heartwood over the bark's own colours) shaded with the piece's tone
HollowShell.GRAIN = {
	faces = { liner = "Front", floor = "Right", roof = "Left" },
	u = 2.6,
	v = 7,
	tint = { 236, 200, 160 },
}
-- (range: the most a light reaches; brightness: at that range. A light held to a shorter range is brighter in
-- proportion, up to maxBrightness, so its chamber's walls read about as lit: the engine's falloff ends at the range)
HollowShell.LIGHT = { range = 9, brightness = 0.45, maxBrightness = 2, color = { 255, 196, 140 } }
-- the daylight in at a hole up a trunk: cool, dimmer, `inset` studs in from the hole's point toward the cavity's
-- middle line and `lift` up (the head)
HollowShell.HOLE_LIGHT = { brightness = 0.4, color = { 200, 214, 235 }, inset = 1.2, lift = 1.0, minRange = 1.0 }
-- how far a tone (Shared/World/HollowLayout: a piece's -1..1 shade) moves its role's colour, either way
HollowShell.TONE = 0.16
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

local function light(env: any, parent: any, range: number, kind: any?)
	local l = env.Instance.new("PointLight")
	local L = HollowShell.LIGHT
	local k = kind or L
	l.Range = range
	l.Brightness = math.min(L.maxBrightness, k.brightness * L.range / math.max(range, 0.5))
	l.Color = env.Color3.fromRGB(k.color[1], k.color[2], k.color[3])
	l.Shadows = false
	l.Parent = parent
end

-- a role's colour with a piece's tone (-1 darker .. 1 lighter), RGB 0-255; `k` how far a tone moves it (TONE)
function HollowShell.shade(color: { number }, tone: number?, k: number?): (number, number, number)
	local f = 1 + (k or HollowShell.TONE) * math.clamp(tone or 0, -1, 1)
	return math.clamp(color[1] * f, 0, 255), math.clamp(color[2] * f, 0, 255), math.clamp(color[3] * f, 0, 255)
end

-- the bark colour map of each tree (trunk route -> content id) from the records of Shared/Generated/TreeArt (each a
-- tree's trunkRoute and its MeshParts; the one named Bark)
function HollowShell.barkMaps(treeArt: { any }?): { [number]: string }
	local out: { [number]: string } = {}
	local trees: { any } = treeArt or {}
	for _, t in trees do
		local parts: { any } = t.parts or {}
		for _, p in parts do
			if p.name == "Bark" and type(p.colorMap) == "string" and p.colorMap ~= "" then
				out[t.trunkRoute] = p.colorMap
			end
		end
	end
	return out
end

export type Report = { parts: number, lights: number, textures: number, per: { [string]: number } }
export type Options = { bark: { [number]: string }? }

function HollowShell.build(env: any, layout: any, parent: any?, opts: Options?): (any, Report)
	local Instance, CFrame, Vector3, Color3, Enum = env.Instance, env.CFrame, env.Vector3, env.Color3, env.Enum
	local root = Instance.new("Folder")
	root.Name = "HollowTrees"
	local report: Report = { parts = 0, lights = 0, textures = 0, per = {} }
	local G = HollowShell.GRAIN
	for _, h in layout.hollows do
		local model = Instance.new("Model")
		model.Name = h.id
		model:SetAttribute("Space", h.space)
		local n = 0
		local barkMap = if opts and opts.bark and h.trunk then opts.bark[h.trunk] else nil
		for i, pc in h.parts do
			local look = HollowShell.LOOK[pc.role] or HollowShell.LOOK.liner
			local p = Instance.new("Part")
			p.Name = `{pc.role}{i}`
			p.Shape = if pc.shape == "Cylinder"
				then Enum.PartType.Cylinder
				elseif pc.shape == "Ball" then Enum.PartType.Ball
				else Enum.PartType.Block
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
			p.Color = Color3.fromRGB(HollowShell.shade(look.color, pc.tone, look.tone))
			p.TopSurface = Enum.SurfaceType.Smooth
			p.BottomSurface = Enum.SurfaceType.Smooth
			local face = G.faces[pc.role]
			if barkMap and face then
				-- the tree's bark on the inner face, at an offset of the piece's own (from where it is: the same on
				-- every build)
				local tx = Instance.new("Texture")
				tx.Name = "Grain"
				tx.Texture = barkMap
				tx.Face = (Enum.NormalId :: any)[face]
				tx.StudsPerTileU = G.u
				tx.StudsPerTileV = G.v
				tx.OffsetStudsU = (pc.p[1] * 7.31 + pc.p[3] * 3.17) % G.u
				tx.OffsetStudsV = (pc.p[2] * 5.13 + pc.p[1] * 1.91) % G.v
				tx.Color3 = Color3.fromRGB(HollowShell.shade(G.tint, pc.tone, look.tone))
				tx.Parent = p
				report.textures += 1
			end
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
		-- daylight in at each hole up the trunk (not the ground hole: that is the floor's), just inside it at a head's
		-- height
		for _, m in h.mouths do
			if anchor and m.opens ~= "ground" and h.variant ~= "log" then
				-- (in from the hole toward the cavity's middle line, never past it)
				local L = HollowShell.HOLE_LIGHT
				local dx, dz = mid.x - m.x, mid.z - m.z
				local k = math.min(1, L.inset / math.max(1e-6, math.sqrt(dx * dx + dz * dz)))
				local at = Vector3.new(m.x + dx * k, m.y + L.lift, m.z + dz * k)
				local range = HollowShell.rangeIn(h, at.X, at.Y, at.Z)
				if range >= L.minRange then
					local a = Instance.new("Attachment")
					a.Name = `daylight_{m.name}`
					a.CFrame = anchor.CFrame:Inverse() * CFrame.new(at)
					a.Parent = anchor
					light(env, a, range, L)
					report.lights += 1
				end
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
