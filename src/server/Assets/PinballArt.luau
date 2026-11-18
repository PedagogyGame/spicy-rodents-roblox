--!strict
-- ServerScriptService.Server.Assets.PinballArt
-- The owner's finished pinball models (ChatGPT's GLBs, the 18 November delivery) put on the three baked
-- machines (Workspace.Attractions.<alley>.GamesRoom.Pinball<index>, tools/bake/games/Pinball) at boot. Eight
-- uploaded Models (data/art/pinball.json -> Shared/Generated/PinballArt; tools/blender/pinball): the shared
-- flipper, bumper, plunger, gate and cabinet, and one per machine (its playfield, guides, slingshots, targets,
-- spinner, ramps, pod hoods and the backglass picture). Every mesh arrives unrotated, centred on its bounding
-- box in its own frame (tools/blender/pinball/export_pinball.py), and goes at frame * centre, where the frame is
-- the game's own (Shared/Minigames/Pinball/Cabinet: the playfield's, the cabinet's, a flipper's Hub, a bumper's
-- base, the plunger's knob, a gate's hinge), so each lands where the baked part it replaces stood.
-- What the client moves keeps its name and its place in the model (Cabinet.NAMES): the flipper meshes go into
-- the Flipper<i> Model about its Hub; Drop<i>, Standup<i>, Spinner<k>, BumperCap<i>, Sling<i> and Glass are the
-- machine's children; the Plunger Model's Rod (its PrimaryPart) and Knob are the meshes. Everything else of the
-- art is in the machine's child Model "ArtMeshes". The baked parts the meshes replace are destroyed; the baked
-- colliders (the cabinet's body, rails, walls, lockdown bar, legs, backbox and the playfield) stay, unseen; the
-- Backglass part stays, unseen, with its live text (SurfaceGui "Display") over the picture; the lamps, the
-- balls, the kick-out holes and the backbox's light stay as baked. The cabinet, the bumpers and the light strip
-- take the machine's THEMES colours. Visual only: anchored, no collision, touch or queries; only the cabinet
-- casts shadows. A machine is done all at once or not at all (a Model that fails to load, or a mesh missing
-- from one, leaves it as baked), once (its "ArtLoaded" attribute). With no asset ids nothing changes.
-- Interface: machines(root) -> { { model, index, variant, place } }; ready(data) -> (bool, string?);
--   install(machine, templates, data, env?) -> report; templates(data, load) -> ({ [tag]: Model }?, string?);
--   run(root, opts?) -> report; start(root?, opts?) -> { machines, ready, why? }
-- No side effects on require.

local Import = require("../Import")
local AlleyLayout = Import.shared("Attractions/AlleyLayout") :: typeof(require("../../shared/Attractions/AlleyLayout"))
local Cabinet = Import.shared("Minigames/Pinball/Cabinet") :: typeof(require("../../shared/Minigames/Pinball/Cabinet"))
local Tables = Import.shared("Minigames/Pinball/Tables") :: typeof(require("../../shared/Minigames/Pinball/Tables"))

local PinballArt = {}

PinballArt.SITE = "bowling_alley"
PinballArt.TAGS = { "flipper", "bumper", "plunger", "gate", "cabinet", "acorn", "rodent", "space" }
PinballArt.GROUP = "ArtMeshes" -- the machine's child Model holding the art the client never touches
-- baked parts the meshes replace (destroyed)
PinballArt.REPLACED = {
	"^Wall%d+$",
	"^Ramp%d+$",
	"^Post$",
	"^Bumper$",
	"^BumperCap%d+$",
	"^Sling%d+$",
	"^Drop%d+$",
	"^Standup%d+$",
	"^Spinner%d+$",
	"^Gate$",
	"^Apron$",
	"^Glass$",
	"^FlipperButton$",
	"^CoinDoor$",
	"^BackboxTrim$",
}
-- baked parts kept as the machine's colliders (or its live text), unseen under the meshes
PinballArt.HIDDEN = {
	Body = true,
	SideRail = true,
	FrontWall = true,
	BackWall = true,
	LockdownBar = true,
	Playfield = true,
	Backbox = true,
	Leg = true,
	Backglass = true,
}
-- meshes that are the client's parts: children of the machine itself, by their own names
PinballArt.MOVED = { "^Drop%d+$", "^Standup%d+$", "^Spinner%d+$", "^Sling%d+$", "^Glass$" }

type Place = { x: number, z: number, floorY: number, yaw: number }
export type Env = { CFrame: any, Color3: any, Enum: any, Instance: any, Vector3: any }
export type Machine = { model: Model, index: number, variant: string, place: Place }
export type Opts = {
	load: ((assetId: number) -> Instance)?, -- default InsertService:LoadAsset
	data: any?, -- default Shared/Generated/PinballArt
	env: Env?, -- default the engine's (Lune specs pass @lune/roblox)
}
export type Report = { meshes: number, removed: number, hidden: number, failed: string? }

local function engineEnv(): Env
	return { CFrame = CFrame, Color3 = Color3, Enum = Enum, Instance = Instance, Vector3 = Vector3 }
end

local function generated(): any
	return Import.shared("Generated/PinballArt") :: any
end

local function matches(name: string, patterns: { string }): boolean
	for _, p in patterns do
		if string.find(name, p) then
			return true
		end
	end
	return false
end

-- Every pinball machine the bake made under `root` (Workspace.Attractions), with the alley's place.
function PinballArt.machines(root: Instance): { Machine }
	local out: { Machine } = {}
	for _, site in root:GetChildren() do
		if site:GetAttribute("Site") ~= PinballArt.SITE then
			continue
		end
		local place: Place = {
			x = site:GetAttribute("OriginX") :: number,
			z = site:GetAttribute("OriginZ") :: number,
			floorY = site:GetAttribute("FloorY") :: number,
			yaw = site:GetAttribute("Yaw") :: number,
		}
		local room = site:FindFirstChild("GamesRoom")
		for index = 1, #AlleyLayout.PINBALLS do
			local m = room and room:FindFirstChild(Cabinet.model(index))
			if m and m:IsA("Model") and type(m:GetAttribute("Theme")) == "string" then
				table.insert(
					out,
					{ model = m, index = index, variant = m:GetAttribute("Theme") :: string, place = place }
				)
			end
		end
	end
	return out
end

-- Whether every Model has an asset id (else the machines keep their baked look, and why).
function PinballArt.ready(data: any): (boolean, string?)
	if data == nil or data.assets == nil then
		return false, "no generated/PinballArt"
	end
	local missing = {}
	for _, tag in PinballArt.TAGS do
		local a = data.assets[tag]
		if a == nil or type(a.id) ~= "number" then
			table.insert(missing, tag)
		end
	end
	if #missing > 0 then
		return false, `not uploaded yet: {table.concat(missing, ", ")} (data/art/pinball.json)`
	end
	return true, nil
end

local function modelOf(asset: Instance): Instance?
	if asset:IsA("Model") and #asset:GetChildren() == 1 and asset:GetChildren()[1]:IsA("Model") then
		return asset:GetChildren()[1]
	end
	return asset
end

-- Loads the eight Models once (yields): tag -> Model, or nil and what failed.
function PinballArt.templates(data: any, load: (assetId: number) -> Instance): ({ [string]: Instance }?, string?)
	local out: { [string]: Instance } = {}
	for _, tag in PinballArt.TAGS do
		local id = data.assets[tag].id
		local ok, asset = pcall(load, id)
		if not ok or (asset :: any) == nil then
			return nil, `{tag} {id}: {tostring(asset)}`
		end
		out[tag] = modelOf(asset) :: Instance
	end
	return out, nil
end

-- The frames (Shared/Minigames/Pinball/Cabinet; the client's frameOf): the playfield's and the cabinet's.
local function frames(m: Machine, e: Env): (any, any)
	local yaw = e.CFrame.Angles(0, m.place.yaw, 0) * e.CFrame.Angles(0, math.pi, 0)
	local ox, oy, oz = AlleyLayout.toWorld(m.place, Cabinet.origin(m.index))
	local pf = e.CFrame.new(ox, oy, oz) * yaw * e.CFrame.Angles(Cabinet.TILT, 0, 0)
	local px, pd = Cabinet.at(m.index)
	local cx, cy, cz = AlleyLayout.toWorld(m.place, px, 0, pd)
	return pf, e.CFrame.new(cx, cy, cz) * yaw
end

local function meshOf(template: Instance, name: string): BasePart?
	local d = template:FindFirstChild(name, true)
	return if d and d:IsA("BasePart") then d else nil
end

-- One mesh, cloned from its Model and dressed: placed, coloured, visual only.
local function dress(src: BasePart, rec: any, at: any, theme: { [string]: { number } }, e: Env): BasePart
	local p = src:Clone()
	p.Name = rec.name
	p.CFrame = at
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = rec.frame == "cabinet" and rec.alpha == nil and rec.theme ~= "glow" and not rec.textured
	local c = if rec.theme then theme[rec.theme] else rec.colour
	local okT, texture = pcall(function(): any
		return (p :: any).TextureID
	end)
	local textured = rec.textured and okT and texture ~= nil and texture ~= ""
	if rec.textured and not textured then
		c = rec.fallback or c
	end
	if not textured then
		p.Color = e.Color3.fromRGB(c[1], c[2], c[3])
	end
	if rec.theme == "glow" then
		p.Material = e.Enum.Material.Neon
	elseif rec.metal then
		p.Material = e.Enum.Material.Metal
	else
		p.Material = e.Enum.Material.SmoothPlastic
	end
	if rec.alpha then
		p.Transparency = 1 - rec.alpha
	end
	if rec.pivot then
		p.PivotOffset = e.CFrame.new(rec.pivot[1] - rec.at[1], rec.pivot[2] - rec.at[2], rec.pivot[3] - rec.at[3])
	end
	return p
end

-- Puts the art on one machine. All or nothing: every mesh is made before any baked part goes.
function PinballArt.install(m: Machine, templates: { [string]: Instance }, data: any, env: Env?): Report
	local e = env or engineEnv()
	local model = m.model
	local report: Report = { meshes = 0, removed = 0, hidden = 0 }
	if model:GetAttribute("ArtLoaded") then
		return report
	end
	local tbl = Tables.need(model:GetAttribute("Table") :: string)
	local def, c = tbl.def, tbl.c
	local theme = data.themes[m.variant]
	local pf, cab = frames(m, e)
	local made: { { part: BasePart, into: Instance } } = {}
	local group = e.Instance.new("Model")
	group.Name = PinballArt.GROUP
	local missing: { string } = {}
	local function put(tag: string, rec: any, frame: any, into: Instance, name: string?, scale: number?)
		local src = meshOf(templates[tag], rec.name)
		if src == nil then
			table.insert(missing, `{tag}.{rec.name}`)
			return
		end
		local k = scale or 1
		local p = dress(src, rec, frame * e.CFrame.new(rec.at[1] * k, rec.at[2], rec.at[3] * k), theme, e)
		if scale then
			p.Size = e.Vector3.new(rec.size[1] * k, rec.size[2], rec.size[3] * k)
		end
		p.Name = name or rec.name
		table.insert(made, { part = p, into = into })
	end
	local function each(tag: string, fn: (rec: any) -> ())
		for _, rec in data.models[tag].meshes do
			fn(rec)
		end
	end
	-- the machine's own Model and the cabinet
	each(m.variant, function(rec)
		local frame = if rec.frame == "cabinet" then cab else pf
		put(m.variant, rec, frame, if matches(rec.name, PinballArt.MOVED) then model else group)
	end)
	each("cabinet", function(rec)
		put("cabinet", rec, cab, if matches(rec.name, PinballArt.MOVED) then model else group)
	end)
	-- the pop bumpers, each its own size: the cap is the client's BumperCap<i>
	for i, b in def.bumpers do
		local base = pf * e.CFrame.new(b.x, 0, -b.y)
		each("bumper", function(rec)
			local name = if rec.name == "Cap"
				then `{Cabinet.NAMES.bumper}{i}`
				elseif rec.name == "Body" then "Bumper"
				else nil
			put("bumper", rec, base, if rec.name == "Cap" then model else group, name, b.r / data.bumperRadius)
		end)
	end
	for _, g in def.gates do
		local dx, dy = g.x2 - g.x1, g.y2 - g.y1
		local hinge = pf
			* e.CFrame.new((g.x1 + g.x2) / 2, data.gateHinge, -(g.y1 + g.y2) / 2)
			* e.CFrame.Angles(0, Cabinet.turnOf(dx, dy), 0)
		each("gate", function(rec)
			put("gate", rec, hinge, group, "Gate")
		end)
	end
	-- the flippers, about their Hubs (the client turns the Model about its PrimaryPart)
	local flippers: { Instance } = {}
	for i = 1, c.nFlip do
		local fm = model:FindFirstChild(`{Cabinet.NAMES.flipper}{i}`)
		local hub = fm and (fm :: any).PrimaryPart
		if hub == nil then
			table.insert(missing, `{Cabinet.NAMES.flipper}{i}`)
			continue
		end
		table.insert(flippers, fm :: Instance)
		each("flipper", function(rec)
			put("flipper", rec, hub.CFrame, fm :: Instance)
		end)
	end
	local plunger = model:FindFirstChild(Cabinet.NAMES.plunger)
	if plunger then
		local knob = pf * e.CFrame.new(def.plunger.x, Cabinet.KNOB_H, -(Cabinet.ROD_Y0 - Cabinet.KNOB))
		each("plunger", function(rec)
			put("plunger", rec, knob, plunger :: Instance)
		end)
	else
		table.insert(missing, Cabinet.NAMES.plunger)
	end
	if #missing > 0 then
		for _, x in made do
			x.part:Destroy()
		end
		group:Destroy()
		report.failed = `missing {table.concat(missing, ", ")}`
		return report
	end
	-- the baked parts go (or stay unseen), then the meshes go in
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") and matches(d.Name, PinballArt.REPLACED) then
			d:Destroy()
			report.removed += 1
		elseif d:IsA("BasePart") and PinballArt.HIDDEN[d.Name] then
			d.Transparency = 1
			d.CastShadow = false
			local painted = d:FindFirstChild("Art")
			if painted then
				painted:Destroy()
			end
			report.hidden += 1
		end
	end
	for _, fm in flippers do
		for _, d in fm:GetChildren() do
			if d:IsA("BasePart") and d ~= (fm :: any).PrimaryPart then
				d:Destroy()
				report.removed += 1
			end
		end
	end
	if plunger then
		for _, d in plunger:GetChildren() do
			if d:IsA("BasePart") then
				d:Destroy()
				report.removed += 1
			end
		end
	end
	for _, x in made do
		x.part.Parent = x.into
		report.meshes += 1
	end
	if plunger then
		(plunger :: any).PrimaryPart = plunger:FindFirstChild("Rod")
	end
	group.Parent = model
	model:SetAttribute("ArtLoaded", true)
	return report
end

-- Every machine under `root`. Yields while the Models load: call it from a task.
function PinballArt.run(root: Instance, opts: Opts?): { machines: number, reports: { Report }, failed: string? }
	local o: Opts = opts or {}
	local data = o.data or generated()
	local load: (assetId: number) -> Instance = o.load
		or function(assetId: number): Instance
			return game:GetService("InsertService"):LoadAsset(assetId)
		end
	local list = PinballArt.machines(root)
	local templates, why = PinballArt.templates(data, load)
	if templates == nil then
		return { machines = #list, reports = {}, failed = why }
	end
	local reports: { Report } = {}
	for _, m in list do
		local ok, r = pcall(PinballArt.install, m, templates :: { [string]: Instance }, data, o.env)
		table.insert(reports, if ok then r else { meshes = 0, removed = 0, hidden = 0, failed = tostring(r) })
	end
	for _, t in templates :: { [string]: Instance } do
		t:Destroy()
	end
	return { machines = #list, reports = reports }
end

export type StartOpts = Opts & {
	heartbeat: boolean?, -- load the Models off the boot path (default true; false runs nothing, as in the headless rig)
	spawn: ((() -> ()) -> ())?, -- default task.spawn
	print: ((string) -> ())?,
	warn: ((string) -> ())?,
}

-- The boot's one call (Boot/Game): with every Model uploaded, loads them off the boot path; else says once
-- that the machines keep their baked look. Never blocks and never throws.
function PinballArt.start(root: Instance?, opts: StartOpts?): { machines: number, ready: boolean, why: string? }
	local o: StartOpts = opts or {}
	local say: (string) -> () = o.print or function(msg: string)
		print(msg)
	end
	local complain: (string) -> () = o.warn or function(msg: string)
		warn(msg)
	end
	local okD, data = pcall(function(): any
		return o.data or generated()
	end)
	local list = if root then PinballArt.machines(root) else {}
	local ready, why = PinballArt.ready(if okD then data else nil)
	if not ready then
		say(`[SpicyRodents] pinball art: {why}; the {#list} machines keep their baked look`)
		return { machines = #list, ready = false, why = why }
	end
	if #list > 0 and o.heartbeat ~= false then
		local spawn = o.spawn or function(f: () -> ())
			task.spawn(f)
		end
		spawn(function()
			local okR, report = pcall(PinballArt.run, root :: Instance, o)
			if not okR then
				complain(`[SpicyRodents] pinball art failed: {report}; the machines keep their baked look`)
				return
			end
			if report.failed then
				complain(`[SpicyRodents] pinball art: {report.failed}; the machines keep their baked look`)
				return
			end
			for i, r in report.reports do
				if r.failed then
					complain(`[SpicyRodents] pinball art, machine {i}: {r.failed}; it keeps its baked look`)
				else
					say(
						`[SpicyRodents] pinball art, machine {i}: {r.meshes} meshes in, {r.removed} baked parts out, {r.hidden} kept unseen`
					)
				end
			end
		end)
	end
	return { machines = #list, ready = true }
end

return PinballArt
