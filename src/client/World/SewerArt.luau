--!strict
-- StarterPlayer.StarterPlayerScripts.Client.World.SewerArt
-- The owner's sewer modules in the drains, on this client only (BRIEF_ADDENDUM D8; his art pack: the brick passage,
-- the four-way junction, the dry maintenance tunnel and its "Dry Side" plaque, uploaded as Models; the bake marks
-- every place one goes: Workspace.Sewers.<pipe>.Art.<slot>, attributes ArtModule, ArtAsset, ArtPivot, ArtTris,
-- ArtMeshes, ArtHalf, ArtCheck, ArtCheckAt, Space).
-- The server loads each module once into ReplicatedStorage.SewerArt (World/SewerService.loadArt). While the body
-- this player holds is in a drain (and for C.linger after), the slots of that drain within C.radius of it get a copy
-- of their module pivoted to ArtPivot (at most C.maxSlots, the nearest; the window moves as the body runs), and the
-- drain's parts lining (Workspace.Sewers.<pipe>.Lining) is hidden on this client only (LocalTransparencyModifier;
-- its collision, the camera's and the bodies', stays). So the triangles drawn are a window's (sewers_bake holds the
-- budget), never a whole 370-stud culvert's.
-- The fall-back is the lining: a module not loaded (yet, or at all), or one whose check mesh does not arrive where the
-- manifest puts it under the slot's pivot (ArtCheck at ArtCheckAt, within C.checkTol: an import turned or mirrored),
-- leaves that drain in plain parts, with one warning. Nothing here changes what the server or other players see.
-- Interface (pure): C; window(slots, space, at, radius, max) -> { index }; placedRight(clone, slot, tol) -> boolean;
--   cost(slots, indices) -> (tris, meshes)
-- Engine: start(ctx) -> Handle; ctx = { current: () -> Model?, layout: Layout?, root: Instance? (Workspace.Sewers),
--   store: Instance? (ReplicatedStorage.SewerArt), parent: Instance? (where copies go: a Folder in Workspace) }
--   Handle = { step(dt), placed() -> number, hidden() -> boolean, bad() -> { [module]: boolean }, stop() }
-- No side effects on require.

local Import = require("../Import")
local SewerLayout = Import.shared("World/SewerLayout") :: typeof(require("../../shared/World/SewerLayout"))

type Layout = typeof(SewerLayout.new((nil :: any) :: any))

local SewerArt = {}

SewerArt.C = {
	radius = 48, -- studs from the body to a slot's pivot: within it the module is drawn
	maxSlots = 10, -- at most this many modules at once (the nearest)
	every = 0.25, -- s between moving the window
	rescanEvery = 2.0, -- s between looking for slots and modules again (streaming and loading bring them late)
	linger = 1.0, -- s the art stays after the body leaves a drain's volume (coming up a shaft)
	checkTol = 0.35, -- studs: the check mesh within this of where the manifest puts it
	budgetTris = 80000, -- the most triangles a window may draw (sewers_bake holds every window of every pipe to it)
	budgetMeshes = 400, -- and MeshParts
}

export type Slot = {
	model: Instance?,
	module: string,
	space: string,
	pivot: CFrame,
	tris: number,
	meshes: number,
	check: string?,
	checkAt: Vector3?,
}

-- The slots of `space` to draw for a body at `at`: pivots within `radius`, nearest first, at most `max`.
function SewerArt.window(slots: { Slot }, space: string, at: Vector3, radius: number, max: number): { number }
	local near: { { i: number, d: number } } = {}
	for i, s in slots do
		if s.space == space then
			local d = (s.pivot.Position - at).Magnitude
			if d <= radius then
				table.insert(near, { i = i, d = d })
			end
		end
	end
	table.sort(near, function(a, b)
		if a.d ~= b.d then
			return a.d < b.d
		end
		return a.i < b.i
	end)
	local out = {}
	for k = 1, math.min(max, #near) do
		out[k] = near[k].i
	end
	return out
end

-- What a window of slots draws: triangles and MeshParts.
function SewerArt.cost(slots: { Slot }, indices: { number }): (number, number)
	local tris, meshes = 0, 0
	for _, i in indices do
		tris += slots[i].tris
		meshes += slots[i].meshes
	end
	return tris, meshes
end

-- Did the copy arrive the way the bake meant it: its check mesh at ArtCheckAt under the slot's pivot?
function SewerArt.placedRight(clone: Instance, slot: Slot, tol: number): boolean
	if slot.check == nil or slot.check == "" or slot.checkAt == nil then
		return true
	end
	local part = clone:FindFirstChild(slot.check :: string, true)
	if part == nil or not part:IsA("BasePart") then
		return false
	end
	local want = slot.pivot:PointToWorldSpace(slot.checkAt :: Vector3)
	return ((part :: BasePart).Position - want).Magnitude <= tol
end

export type Handle = {
	step: (dt: number) -> (),
	placed: () -> number,
	hidden: () -> boolean,
	bad: () -> { [string]: boolean },
	stop: () -> (),
}

export type Context = {
	current: () -> Model?,
	layout: Layout?,
	root: Instance?,
	store: Instance?,
	parent: Instance?,
}

function SewerArt.start(ctx: Context): Handle
	local C = SewerArt.C
	local layout = ctx.layout or SewerLayout.default()
	local RunService = game:GetService("RunService")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local slots: { Slot } = {}
	local linings: { [string]: { BasePart } } = {} -- space -> its lining parts
	local copies: { [number]: Instance? } = {} -- slot index -> the copy drawn
	local bad: { [string]: boolean } = {}
	local warned: { [string]: boolean } = {}
	local checked: { [string]: boolean } = {}
	local hiddenSpace: string? = nil
	local folder: Instance? = nil
	local shown: string? = nil
	local lastSpace: string? = nil
	local since = math.huge
	local clock, scanClock = C.every, C.rescanEvery

	local function rootOf(): Instance?
		return ctx.root or workspace:FindFirstChild("Sewers")
	end
	local function storeOf(): Instance?
		return ctx.store or ReplicatedStorage:FindFirstChild("SewerArt")
	end

	local function scan()
		table.clear(slots)
		table.clear(linings)
		local root = rootOf()
		if root == nil then
			return
		end
		for _, pipe in root:GetChildren() do
			local space = pipe:GetAttribute("Space")
			if type(space) ~= "string" then
				continue
			end
			local art = pipe:FindFirstChild("Art")
			if art then
				for _, m in art:GetChildren() do
					local pivot = m:GetAttribute("ArtPivot")
					local module = m:GetAttribute("ArtModule")
					if typeof(pivot) == "CFrame" and type(module) == "string" then
						local check = m:GetAttribute("ArtCheck")
						local checkAt = m:GetAttribute("ArtCheckAt")
						table.insert(slots, {
							model = m,
							module = module,
							space = space,
							pivot = pivot :: CFrame,
							tris = (m:GetAttribute("ArtTris") or 0) :: number,
							meshes = (m:GetAttribute("ArtMeshes") or 0) :: number,
							check = if type(check) == "string" then check else nil,
							checkAt = if typeof(checkAt) == "Vector3" then checkAt :: Vector3 else nil,
						})
					end
				end
			end
			local lining = pipe:FindFirstChild("Lining")
			if lining then
				local parts = {}
				for _, d in lining:GetDescendants() do
					if d:IsA("BasePart") then
						table.insert(parts, d :: BasePart)
					end
				end
				linings[space] = parts
			end
		end
	end

	local function hideLining(space: string?)
		if hiddenSpace == space then
			return
		end
		if hiddenSpace then
			local parts: { BasePart } = linings[hiddenSpace :: string] or {}
			for _, p in parts do
				p.LocalTransparencyModifier = 0
			end
		end
		hiddenSpace = space
		if space then
			local parts: { BasePart } = linings[space :: string] or {}
			for _, p in parts do
				p.LocalTransparencyModifier = 1
			end
		end
	end

	local function clear()
		for i, c in copies do
			(c :: Instance):Destroy()
			copies[i] = nil
		end
		hideLining(nil)
	end

	local function fail(module: string, why: string)
		bad[module] = true
		if not warned[module] then
			warned[module] = true
			warn(`[SewerArt] the owner's module {module} {why}: that drain stays in plain parts`)
		end
	end

	-- every module this drain uses is loaded, a Model, and arrives where its manifest says under a slot's pivot (each
	-- checked once, before any is drawn: a drain is all modules or all parts, never a mix)
	local function ready(space: string, store: Instance): boolean
		local any = false
		for _, s in slots do
			if s.space ~= space then
				continue
			end
			any = true
			if bad[s.module] then
				return false
			end
			local template = store:FindFirstChild(s.module)
			if template == nil then
				return false -- not loaded yet
			end
			if not checked[s.module] then
				if not template:IsA("Model") then
					fail(s.module, "is not a Model in ReplicatedStorage.SewerArt")
					return false
				end
				local probe = (template :: Model):Clone()
				probe:PivotTo(s.pivot)
				local right = SewerArt.placedRight(probe, s, C.checkTol)
				probe:Destroy()
				if not right then
					fail(s.module, `did not arrive where its manifest puts {s.check}`)
					return false
				end
				checked[s.module] = true
			end
		end
		return any
	end

	local function move(space: string, at: Vector3)
		local store = storeOf()
		if store == nil or not ready(space, store :: Instance) then
			clear()
			return
		end
		if folder == nil or folder.Parent == nil then
			local f = Instance.new("Folder")
			f.Name = "SewerArtLocal"
			f.Parent = ctx.parent or workspace
			folder = f
		end
		local want: { [number]: boolean } = {}
		for _, i in SewerArt.window(slots, space, at, C.radius, C.maxSlots) do
			want[i] = true
		end
		for i, c in copies do
			if not want[i] then
				(c :: Instance):Destroy()
				copies[i] = nil
			end
		end
		for i in want do
			if not copies[i] then
				local s = slots[i]
				local template = (store :: Instance):FindFirstChild(s.module) :: Model
				local copy = template:Clone()
				copy:PivotTo(s.pivot)
				copy.Parent = folder
				copies[i] = copy
			end
		end
		hideLining(if next(copies) then space else nil)
	end

	local function step(dt: number)
		clock += dt
		scanClock += dt
		if clock < C.every then
			return
		end
		clock = 0
		if scanClock >= C.rescanEvery then
			scanClock = 0
			scan()
		end
		local body = ctx.current()
		local root = if body then body.PrimaryPart else nil
		local here: string? = nil
		local at: Vector3? = nil
		if layout and body and root then
			local p = root.Position
			local hip = body:GetAttribute("HipHeight")
			local feet = p.Y - (if type(hip) == "number" then hip else 0)
			here = layout.contains(p.X, feet, p.Z)
			at = Vector3.new(p.X, feet, p.Z)
		end
		if here then
			lastSpace, since = here, 0
		else
			since += C.every
		end
		local active = if here then here elseif since < C.linger then lastSpace else nil
		if active ~= shown then
			clear()
			shown = active
		end
		if active and at then
			move(active :: string, at :: Vector3)
		end
	end

	local conn = RunService.Heartbeat:Connect(step)
	return {
		step = step,
		placed = function(): number
			local n = 0
			for _ in copies do
				n += 1
			end
			return n
		end,
		hidden = function(): boolean
			return hiddenSpace ~= nil
		end,
		bad = function(): { [string]: boolean }
			return bad
		end,
		stop = function()
			conn:Disconnect()
			clear()
			if folder then
				folder:Destroy()
				folder = nil
			end
		end,
	}
end

return SewerArt
