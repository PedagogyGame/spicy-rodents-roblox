--!strict
-- ServerScriptService.Server.Assets.PeopleArt
-- The rounded townspeople (tools/blender/people) on the town's bodies. Nothing happens until all six Models in
-- Shared/Avatar/PeopleAssets have asset ids: until then every person keeps the stock R15 they have now.
--   install(opts)        loads the six Models once (InsertService:LoadAsset, all at once) and indexes their
--                        MeshParts: the slim and broad bodies, the head, the hair and hats, and one small square
--                        per outfit and face whose SurfaceAppearance dresses a part in that outfit or face. Boot/Game
--                        calls it before any body is built.
--   dress(model, dress)  a stock R15 (Actors/BodyFactory: CreateHumanoidModelFromDescription) in the rounded art.
--                        The rig the game's animation, possession, combat, infection and camera code read stays:
--                        the same fifteen part names under the same Humanoid and HumanoidRootPart, the same Motor6Ds
--                        (moved onto the new parts, each Motor6D's C0 and C1 set to the art's pivots), the same
--                        attachments (moved, at the art's surface; the grips keep their turn) plus any RigSpec
--                        socket the stock R15 lacks, and each part's collision, query, touch and mass flags. Only
--                        the elbows and wrists move: they hang under the shoulder (x 1.04 and 1.05) where the block
--                        arm had them at x 1.5, and the clips only turn joints. The stock face decal goes (the head
--                        has its face painted), so do BodyColors and clothing (they would recolour the parts). The
--                        outfit's extras (coat tails, the V neck, the stethoscope), the hair ("Hair") and the hat
--                        ("Hat") are welded on: massless, no collision, query or touch.
--   statue(figure, dress) a baked, part-built figure (THE GILDED ACORN's guards and bartender) as a rounded person
--                        standing in the rest pose: its parts other than the PrimaryPart give way to anchored art
--                        parts, scaled to the figure's height, facing the way the figure faced (its Root's +Z, the
--                        bake's -D); whatever moves the figure by its pivot moves them with it.
--   start(root?)         dresses every baked staff figure (a Model with a `Staff` attribute of a kind in STAFF_ROLES
--                        and no Humanoid) under root (default Workspace.Expansion); returns how many. (The town's
--                        staff, the alley's employees among them, are R15 actors: Actors/BodyFactory dresses them.)
-- Every dressed part carries attribute PeopleArt = true and PeopleTint = its tint key (skin, shirt, pants, hair, cap
-- or "#rrggbb"): its colour is the part's Color under an Overlay SurfaceAppearance, so the avatar blend
-- (Server/Avatar/AvatarBlendService) tints the part, and only where it is skin (a sleeve stays a sleeve); a dressed body or figure
-- carries PeopleArt = its role, PeopleBuild and PeopleOutfit.
-- Interface: ready() -> boolean; install(opts?) -> { ok, failed }; dress(model, dress, opts?) -> (boolean, why?);
--   statue(figure, dress, opts?) -> boolean; start(root?, opts?) -> number; library() -> Library?; reset()
-- Engine only inside the functions (Lune specs pass @lune/roblox and a library). No side effects on require.

local Import = require("../Import")
local PeopleAssets = Import.shared("Avatar/PeopleAssets") :: typeof(require("../../shared/Avatar/PeopleAssets"))
local PeopleLooks = Import.shared("Avatar/PeopleLooks") :: typeof(require("../../shared/Avatar/PeopleLooks"))

type Dress = typeof(PeopleLooks.dress("townsperson", 1))

local PeopleArt = {}

PeopleArt.KEYS = table.freeze({ "bodySlim", "bodyBroad", "head", "headwear", "outfits", "faces" })
-- the baked staff figures' kinds -> the role they are dressed as
PeopleArt.STAFF_ROLES = table.freeze({ guard = "doorman", bartender = "bartender" } :: { [string]: string })
PeopleArt.FIGURE_HEIGHT = 5.8 -- studs: a baked figure's Root at scale 1 (tools/bake/lounge_classic/Staff)
PeopleArt.LOAD_TIMEOUT = 20 -- seconds install waits for the six loads
-- where the painted eyes are on the head, from its centre (tools/blender/people paint.py EYE_X, EYE_Z and sculpt.py's
-- eye sockets): the Head's EyeOffset attribute, where Client/Render/MedicalView puts an infected person's red eyes
PeopleArt.EYE = table.freeze({ 0.225, 0.2, -0.62 })

export type Lib = { Instance: any, Vector3: any, CFrame: any, Color3: any }
export type Library = {
	bodies: { [string]: { [string]: any } }, -- build -> part or extra name -> MeshPart
	head: any,
	wear: { [string]: any }, -- Hair_<style>, Hat_<name> -> MeshPart
	outfits: { [string]: any }, -- outfit -> SurfaceAppearance
	faces: { [string]: any }, -- "<face>_<expression>" -> SurfaceAppearance
}
export type Opts = { lib: Lib?, library: Library? }
export type StatueOpts = { lib: Lib?, library: Library?, scale: number? }

local state: { library: Library? } = { library = nil }

local function engineLib(): Lib
	return { Instance = Instance, Vector3 = Vector3, CFrame = CFrame, Color3 = Color3 }
end

function PeopleArt.ready(): boolean
	return state.library ~= nil
end

function PeopleArt.library(): Library?
	return state.library
end

function PeopleArt.reset()
	state.library = nil
end

-- Every asset id in PeopleAssets, or nil when any is missing (0).
local function ids(): { [string]: number }?
	local out: { [string]: number } = {}
	for _, key in PeopleArt.KEYS do
		local id = PeopleAssets.ASSETS[key]
		if id == nil or id == 0 then
			return nil
		end
		out[key] = id
	end
	return out
end

-- name -> the first MeshPart of that name in a loaded asset
local function meshes(asset: any): { [string]: any }
	local out: { [string]: any } = {}
	for _, d in asset:GetDescendants() do
		if d:IsA("MeshPart") and out[d.Name] == nil then
			out[d.Name] = d
		end
	end
	return out
end

local function appearance(part: any): any
	return if part then part:FindFirstChildOfClass("SurfaceAppearance") else nil
end

-- The colour maps are Overlay maps: alpha 0 shows the part's Color (the tint), and most of every map is clear.
-- Shown any other way (AlphaMode Transparency: see-through people; the alpha dropped: grey or dark ones), so a
-- SurfaceAppearance that does not read AlphaMode Overlay stops the install: the town keeps its stock bodies.
-- (AlphaMode cannot be relied on to be set from a live server, tools/blender/heroes/textures.py: it is set on the
-- uploaded Models.)
local function overlay(sa: any, where: string): any
	local ok, mode = pcall(function()
		return sa.AlphaMode.Name
	end)
	if not ok or mode ~= "Overlay" then
		error(`PeopleArt: {where}'s SurfaceAppearance is AlphaMode {if ok then mode else "?"}, not Overlay`)
	end
	return sa
end

-- A part's own SurfaceAppearance, if it has one, must be Overlay; `need` says it must have one.
local function ownLook(part: any, where: string, need: boolean)
	local sa = appearance(part)
	if sa then
		overlay(sa, where)
	elseif need then
		error(`PeopleArt: {where} has no SurfaceAppearance`)
	end
end

-- index(assets): the Library from the six loaded assets (keyed as PeopleArt.KEYS); errors on anything missing and
-- on any SurfaceAppearance that is not AlphaMode Overlay.
function PeopleArt.index(assets: { [string]: any }): Library
	local bodies: { [string]: { [string]: any } } = {}
	local files: { [string]: string } = { slim = "bodySlim", broad = "bodyBroad" }
	for build, key in files do
		local m = meshes(assets[key])
		for name in PeopleAssets.BUILDS[build].parts do
			if name ~= "Head" then
				if m[name] == nil then
					error(`PeopleArt: {key} has no {name}`)
				end
				ownLook(m[name], `{key}.{name}`, false)
			end
		end
		for name in PeopleAssets.BUILDS[build].extras do
			if m[name] == nil then
				error(`PeopleArt: {key} has no {name}`)
			end
			ownLook(m[name], `{key}.{name}`, false)
		end
		bodies[build] = m
	end
	local head = meshes(assets.head).Head
	if head == nil then
		error("PeopleArt: head has no Head")
	end
	ownLook(head, "head.Head", false)
	local wear = meshes(assets.headwear)
	for name in PeopleAssets.HEADWEAR do
		if wear[name] == nil then
			error(`PeopleArt: headwear has no {name}`)
		end
		ownLook(wear[name], `headwear.{name}`, true) -- worn in its own textures
	end
	local outfits: { [string]: any } = {}
	local squares = meshes(assets.outfits)
	for outfit in PeopleAssets.OUTFITS do
		local sa = appearance(squares[`Outfit_{outfit}`])
		if sa == nil then
			error(`PeopleArt: outfits has no Outfit_{outfit} SurfaceAppearance`)
		end
		outfits[outfit] = overlay(sa, `outfits.Outfit_{outfit}`)
	end
	local faces: { [string]: any } = {}
	squares = meshes(assets.faces)
	for _, face in PeopleAssets.HEAD.faces do
		for _, expression in PeopleAssets.HEAD.expressions do
			local sa = appearance(squares[`Face_{face}_{expression}`])
			if sa == nil then
				error(`PeopleArt: faces has no Face_{face}_{expression} SurfaceAppearance`)
			end
			faces[`{face}_{expression}`] = overlay(sa, `faces.Face_{face}_{expression}`)
		end
	end
	return { bodies = bodies, head = head, wear = wear, outfits = outfits, faces = faces }
end

export type InstallOpts = { load: ((assetId: number) -> any)?, ids: { [string]: number }? }

-- install(opts?): loads the six Models (all at once; waits at most LOAD_TIMEOUT) and makes the library. Returns
-- ok = false and why, and leaves every body stock, when an id is missing or any load or check fails.
function PeopleArt.install(opts: InstallOpts?): { ok: boolean, failed: { [string]: string } }
	local o: InstallOpts = opts or {}
	local want: { [string]: number }? = o.ids or ids()
	if want == nil then
		return { ok = false, failed = { assets = "not uploaded (Shared/Avatar/PeopleAssets has no ids)" } }
	end
	local load: (assetId: number) -> any = o.load
		or function(assetId: number): any
			return game:GetService("InsertService"):LoadAsset(assetId)
		end
	local loaded: { [string]: any } = {}
	local failed: { [string]: string } = {}
	local pending = 0
	for key, id in want do
		pending += 1
		local function one()
			local ok, res = pcall(load, id)
			if ok and res then
				loaded[key] = res
			else
				failed[key] = tostring(res)
			end
			pending -= 1
		end
		if o.load then
			one()
		else
			task.spawn(one)
		end
	end
	local t0 = os.clock()
	while pending > 0 and os.clock() - t0 < PeopleArt.LOAD_TIMEOUT do
		task.wait(0.05)
	end
	if pending > 0 then
		failed.timeout = `{pending} of six not loaded in {PeopleArt.LOAD_TIMEOUT} s`
	end
	if next(failed) ~= nil then
		return { ok = false, failed = failed }
	end
	local ok, res = pcall(PeopleArt.index, loaded)
	if not ok then
		return { ok = false, failed = { index = tostring(res) } }
	end
	state.library = res
	return { ok = true, failed = failed }
end

-- ---- dressing --------------------------------------------------------------------------------------------

local function v3(L: Lib, v: { number }, s: number?): any
	local k = s or 1
	return L.Vector3.new(v[1] * k, v[2] * k, v[3] * k)
end

local function colour(L: Lib, dress: Dress, key: string): any
	local c = PeopleLooks.tint(dress, key)
	return L.Color3.new(c.r, c.g, c.b)
end

-- A copy of an art MeshPart named `name`, tinted `key`, wearing `sa` (a SurfaceAppearance to clone) if given.
local function copy(L: Lib, src: any, name: string, dress: Dress, key: string, sa: any?): any
	local p = src:Clone()
	p.Name = name
	p.Color = colour(L, dress, key)
	if sa then
		for _, c in p:GetChildren() do
			if c:IsA("SurfaceAppearance") then
				c:Destroy()
			end
		end
		sa:Clone().Parent = p
	end
	p:SetAttribute("PeopleArt", true)
	p:SetAttribute("PeopleTint", key)
	return p
end

local function ghost(p: any, anchored: boolean)
	p.Anchored = anchored
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
end

-- The parts a dress adds on top of the fifteen: { name, source MeshPart, tint, SurfaceAppearance?, the part
-- it hangs from, offset from that part's centre }.
type Extra = { name: string, src: any, key: string, sa: any?, on: string, offset: { number } }
local function extrasOf(library: Library, dress: Dress): { Extra }
	local rig = PeopleAssets.BUILDS[dress.build]
	local out: { Extra } = {}
	for _, e in PeopleAssets.OUTFITS[dress.outfit].extras do
		local x = rig.extras[e]
		table.insert(out, {
			name = e,
			src = library.bodies[dress.build][e],
			key = x.tint,
			sa = library.outfits[dress.outfit],
			on = x.weldTo,
			offset = x.offset,
		})
	end
	for _, item in { { "Hair", dress.hair }, { "Hat", dress.hat } } do
		local name = item[2]
		if name then
			local w = PeopleAssets.HEADWEAR[name]
			table.insert(out, {
				name = item[1] :: string,
				src = library.wear[name],
				key = w.tint,
				sa = nil,
				on = "Head",
				offset = w.offset,
			})
		end
	end
	return out
end

-- An attachment to `pos` on its part, keeping its turn (a stock grip is turned); the engine's record of where it
-- sits at scale 1 (OriginalPosition, what the Humanoid rescales from) follows it.
local function moveTo(L: Lib, att: any, pos: { number })
	local cf = att.CFrame
	att.CFrame = L.CFrame.new(v3(L, pos)) * (cf - cf.Position)
	local original = att:FindFirstChild("OriginalPosition")
	if original and original:IsA("Vector3Value") then
		original.Value = v3(L, pos)
	end
end

local function stamp(model: any, dress: Dress)
	model:SetAttribute("PeopleArt", dress.role)
	model:SetAttribute("PeopleBuild", dress.build)
	model:SetAttribute("PeopleOutfit", dress.outfit)
end

-- Every new part a dress needs, cloned, tinted and textured but not yet placed or parented: { parts: the fifteen
-- by name, extras: { part, the part it hangs from, offset } }. Nothing in the game is touched, so a dress the
-- library cannot make (an outfit, face, hair or hat it lacks) fails here, its clones go, and the body stays whole.
type Made = { parts: { [string]: any }, extras: { { part: any, on: string, offset: { number } } } }
local function make(L: Lib, library: Library, dress: Dress): (Made?, string?)
	local made: Made = { parts = {}, extras = {} }
	local ok, err = pcall(function()
		local rig = PeopleAssets.BUILDS[dress.build]
		local outfit = PeopleAssets.OUTFITS[dress.outfit]
		if rig == nil or outfit == nil then
			error(`PeopleArt: no build {dress.build} or outfit {dress.outfit}`)
		end
		local outfitSa = library.outfits[dress.outfit]
		local faceSa = library.faces[`{dress.face}_{dress.expression}`]
		if outfitSa == nil or faceSa == nil then
			error(`PeopleArt: no texture for outfit {dress.outfit} or face {dress.face}_{dress.expression}`)
		end
		for name in rig.parts do
			local src = if name == "Head" then library.head else library.bodies[dress.build][name]
			if src == nil then
				error(`PeopleArt: no {dress.build} {name}`)
			end
			local sa = if name == "Head" then faceSa else outfitSa
			made.parts[name] = copy(L, src, name, dress, outfit.tints[name] or PeopleAssets.HEAD.tint, sa)
		end
		for _, e in extrasOf(library, dress) do
			if e.src == nil then
				error(`PeopleArt: no {e.name} for {dress.role} ({dress.hair}, {dress.hat})`)
			end
			table.insert(
				made.extras,
				{ part = copy(L, e.src, e.name, dress, e.key, e.sa), on = e.on, offset = e.offset }
			)
		end
	end)
	if not ok then
		for _, p in made.parts do
			p:Destroy()
		end
		for _, e in made.extras do
			e.part:Destroy()
		end
		return nil, tostring(err)
	end
	return made, nil
end

-- dress(model, dress, opts?): see the header. Returns false and why (and changes nothing) when the art is not
-- loaded, the model is not a whole R15 or the library cannot make the dress.
function PeopleArt.dress(model: any, dress: Dress, opts: Opts?): (boolean, string?)
	local o: Opts = opts or {}
	local library = o.library or state.library
	if library == nil then
		return false, "the art is not loaded"
	end
	local L = o.lib or engineLib()
	local rig = PeopleAssets.BUILDS[dress.build]
	local root = model:FindFirstChild("HumanoidRootPart")
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if rig == nil or root == nil or humanoid == nil then
		return false, "not an R15 (no HumanoidRootPart or Humanoid)"
	end
	local old: { [string]: any } = {}
	for name in rig.parts do
		local p = model:FindFirstChild(name)
		if p == nil or not p:IsA("BasePart") then
			return false, `not a whole R15 (no {name})`
		end
		old[name] = p
	end
	local made, why = make(L, library, dress)
	if made == nil then
		return false, why
	end
	-- from here on nothing can be missing: the model changes
	local new = made.parts
	local byOld: { [any]: any } = {}
	for name, info in rig.parts do
		local was = old[name]
		local p = new[name]
		p.Anchored = was.Anchored
		p.CanCollide = was.CanCollide
		p.CanQuery = was.CanQuery
		p.CanTouch = was.CanTouch
		p.Massless = was.Massless
		pcall(function()
			p.CollisionGroup = was.CollisionGroup
		end)
		p.CFrame = root.CFrame * L.CFrame.new(v3(L, info.center))
		for _, c in was:GetChildren() do
			if c:IsA("SurfaceAppearance") then
				continue
			elseif c:IsA("DataModelMesh") or c:IsA("BaseWrap") or (c:IsA("Decal") and name == "Head") then
				-- the stock head's SpecialMesh or a layered-clothing cage would reshape the art; the stock face
				-- decal would sit over the face painted on this head
				c:Destroy()
			elseif c.Name == "OriginalSize" and c:IsA("Vector3Value") then
				c.Value = p.Size
				c.Parent = p
			else
				c.Parent = p
			end
		end
		byOld[was] = p
	end
	-- the stock head's size, which a player's hair accessory was made for (Server/Avatar/AvatarBlendService)
	new.Head:SetAttribute("StockSize", old.Head.Size)
	-- every joint that held an old part holds the new one (the Motor6Ds moved with their Part1)
	local joints = {}
	for _, d in model:GetDescendants() do
		if d:IsA("JointInstance") or d:IsA("WeldConstraint") then
			table.insert(joints, d)
		end
	end
	for _, p in new do
		for _, d in p:GetDescendants() do
			if d:IsA("JointInstance") or d:IsA("WeldConstraint") then
				table.insert(joints, d)
			end
		end
	end
	-- (a weld keeps what it holds where it was: its offset is re-measured from the new part's centre; the rig's
	-- Motor6Ds are set to the art's pivots below)
	for _, j in joints do
		local was0, was1 = j.Part0, j.Part1
		local now0, now1 = byOld[was0], byOld[was1]
		if now0 then
			if j:IsA("JointInstance") then
				j.C0 = now0.CFrame:Inverse() * (was0.CFrame * j.C0)
			end
			j.Part0 = now0
		end
		if now1 then
			if j:IsA("JointInstance") then
				j.C1 = now1.CFrame:Inverse() * (was1.CFrame * j.C1)
			end
			j.Part1 = now1
		end
	end
	-- the joints at the art's pivots, and their rig attachments with them
	for jname, j in rig.joints do
		local part1 = new[j.part1]
		local part0 = if j.part0 == "HumanoidRootPart" then root else new[j.part0]
		local m = part1:FindFirstChild(jname)
		if m == nil or not m:IsA("Motor6D") then
			if m then
				m:Destroy()
			end
			m = L.Instance.new("Motor6D")
			m.Name = jname
			m.Parent = part1
		end
		m.Part0 = part0
		m.Part1 = part1
		m.C0 = L.CFrame.new(v3(L, j.c0))
		m.C1 = L.CFrame.new(v3(L, j.c1))
		for _, side in { { part0, j.c0 }, { part1, j.c1 } } do
			local a = side[1]:FindFirstChild(`{jname}RigAttachment`)
			if a and a:IsA("Attachment") then
				moveTo(L, a, side[2])
			end
		end
	end
	-- the accessory, grip and socket attachments on the art's surface (a stock one keeps its turn)
	for aname, a in rig.attachments do
		local host = new[a.part]
		local att = host:FindFirstChild(aname)
		if att == nil or not att:IsA("Attachment") then
			att = L.Instance.new("Attachment")
			att.Name = aname
			att.Parent = host
		end
		moveTo(L, att, a.position)
	end
	-- nothing may recolour the parts behind the art's back
	for _, d in model:GetChildren() do
		if d:IsA("BodyColors") or d:IsA("Clothing") or d:IsA("ShirtGraphic") then
			d:Destroy()
		end
	end
	for _, was in old do
		was:Destroy()
	end
	for _, p in new do
		p.Parent = model
	end
	for _, e in made.extras do
		local host = new[e.on]
		local p = e.part
		ghost(p, false)
		p.CFrame = host.CFrame * L.CFrame.new(v3(L, e.offset))
		local w = L.Instance.new("Weld")
		w.Name = "PeopleWeld"
		w.Part0 = host
		w.Part1 = p
		w.C0 = L.CFrame.new(v3(L, e.offset))
		w.Parent = p
		p.Parent = model
	end
	-- the soles 3 studs under the root's centre, as on the stock R15 (the possessed body's motor stands on this)
	humanoid.HipHeight = PeopleAssets.ROOT.hipHeight
	new.Head:SetAttribute("EyeOffset", v3(L, PeopleArt.EYE))
	stamp(model, dress)
	return true
end

-- statue(figure, dress, opts?): see the header. opts.scale overrides the figure's (its Root's height / 5.8).
function PeopleArt.statue(figure: any, dress: Dress, opts: StatueOpts?): boolean
	local o: StatueOpts = opts or {}
	local library = o.library or state.library
	if library == nil then
		return false
	end
	local L = o.lib or engineLib()
	local root = figure.PrimaryPart or figure:FindFirstChild("Root")
	local rig = PeopleAssets.BUILDS[dress.build]
	if root == nil or rig == nil then
		return false
	end
	local made = make(L, library, dress)
	if made == nil then
		return false -- the figure stays as baked
	end
	local s = o.scale or root.Size.Y / PeopleArt.FIGURE_HEIGHT
	-- the soles under the Root's centre, turned to face the Root's +Z (the bake's -D, where the figure looked)
	local feet = root.CFrame * L.CFrame.new(0, -root.Size.Y / 2, 0) * L.CFrame.Angles(0, math.pi, 0)
	local up = PeopleAssets.ROOT.hipHeight + PeopleAssets.ROOT.size[2] / 2 -- soles to the root's centre
	for _, d in figure:GetChildren() do
		if d:IsA("BasePart") and d ~= root then
			d:Destroy()
		end
	end
	local function place(p: any, at: any)
		ghost(p, true)
		p.Size = p.Size * s
		p.CFrame = at
		p.Parent = figure
	end
	for name, info in rig.parts do
		local c = info.center
		place(made.parts[name], feet * L.CFrame.new(c[1] * s, (c[2] + up) * s, c[3] * s))
	end
	for _, e in made.extras do
		place(e.part, made.parts[e.on].CFrame * L.CFrame.new(v3(L, e.offset, s)))
	end
	stamp(figure, dress)
	return true
end

-- start(root?, opts?): dresses every baked staff figure under root (default Workspace.Expansion).
function PeopleArt.start(root: any?, opts: StatueOpts?): number
	if (opts == nil or opts.library == nil) and not PeopleArt.ready() then
		return 0
	end
	local where = root or workspace:FindFirstChild("Expansion")
	if where == nil then
		return 0
	end
	local n = 0
	local index: { [string]: number } = {}
	for _, d in where:GetDescendants() do
		local kind = if d:IsA("Model") then d:GetAttribute("Staff") else nil
		if
			type(kind) == "string"
			and d:FindFirstChildOfClass("Humanoid") == nil
			and d:GetAttribute("PeopleArt") == nil
		then
			local role = PeopleArt.STAFF_ROLES[kind]
			if role then
				index[role] = (index[role] or 0) + 1
				if PeopleArt.statue(d, PeopleLooks.dress(role, index[role]), opts) then
					n += 1
				end
			end
		end
	end
	return n
end

return PeopleArt
