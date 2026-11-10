--!strict
-- StarterPlayer.StarterPlayerScripts.Client.World.ClientWorld
-- The world callbacks the client motors need (BUILD_PLAN §1.4 Movement/*, §4.4 #5): ground from a
-- downward raycast against the baked town and terrain, starting just above the body's reference
-- height so a roof overhead never counts (the pure World/Ground answer is the fallback where nothing
-- is hit, e.g. before the town streams in); walls from a small overlap query that respects
-- CanCollide; water from World/Height's river; the rail world (Movement/RailWorld) built once, in
-- the background, from Shared.Generated.
-- The ground is what the player SEES as ground (squirrel motor work, 2026-11-09): the baked town lays thin
-- non-colliding plates over the terrain (lot ground, banks, court tiles, pads, a few road segments), up to
-- 0.3 st above the colliding surface. A second ray, limited to Town.Lots and Town.Roads, finds the topmost
-- such plate above the solid hit (groundLike), so feet stand on the drawn surface instead of inside it.
-- A wall is what the body cannot step onto (owner 2026-11-10: "the squirrel catches and gets stuck on the
-- crack between the sidewalk and grass"): the wall probe starts STEP above the feet, so a kerb, a paving
-- edge or a plate lip is ground to climb (the ground ray finds its top and the motor rises onto it), and
-- only something taller than a step stops the body. The probe used to reach down to 0.25 st, where every
-- kerb met from the low side counted as a wall.
-- The body is as wide as it is drawn (owner 2026-11-10: "make sure squirrel cannot run through houses";
-- the screenshot showed it half inside a house's plinth): `blocked` is a box BODY_HALF to each side, from
-- one step above the feet to the top of the body. It used to be a sphere 0.35 st across, a seventh of the
-- body, so the drawn squirrel sank into every wall it met. `blockedCore` is the old narrow probe at the
-- new height: the motor uses it only while the body already overlaps something (it let go of a downspout
-- on a wall), so it can come away but never pass through. The invisible cylinders that give tree boughs
-- their collision (Town.Props.Tree_*.R*) are not walls: v5.4 had none, and they would stop a leap between
-- branches.
-- Interface: get() -> ClientWorld { groundAt, blocked, blockedCore, blockedRadius, waterAt, clamp,
--   rail() -> RailWorld?, ignore(instances) }; groundLike(name, sizeY, transparency) -> boolean (pure);
--   STEP; BODY_HALF; BODY_TOP; wallProbe(feetY) -> centreY, radius (pure);
--   bodyProbe(feetY) -> centreY, sizeX, sizeY, sizeZ (pure); isBough(name, parentName) -> boolean (pure)
-- No side effects on require (services are looked up on first get()).

local Import = require("../Import")
local Ground = Import.shared("World/Ground") :: typeof(require("../../shared/World/Ground"))
local Height = Import.shared("World/Height") :: typeof(require("../../shared/World/Height"))
local RailWorld = Import.shared("Movement/RailWorld") :: typeof(require("../../shared/Movement/RailWorld"))
local Data = Import.shared("Data") :: typeof(require("../../shared/Data"))

export type ClientWorld = {
	groundAt: (x: number, z: number, refY: number) -> number,
	blocked: (x: number, z: number, y: number) -> boolean,
	blockedCore: (x: number, z: number, y: number) -> boolean,
	blockedRadius: (x: number, z: number, y: number, r: number) -> boolean,
	waterAt: (x: number, z: number) -> number?,
	clamp: { minX: number, maxX: number, minZ: number, maxZ: number },
	rail: () -> any?,
	ignore: (list: { Instance }) -> (),
	railReady: boolean,
}

local ClientWorld = {}

local singleton: ClientWorld? = nil

-- Is a non-colliding part of the town a ground plate worth standing on? Opaque only (water sheets are
-- translucent); lot ground and paving (thin Greybox), banks, court tiles, pads and road segments. Plinths,
-- foundations, lamp bases and thick grey boxes are bodies, not ground.
function ClientWorld.groundLike(name: string, sizeY: number, transparency: number): boolean
	if transparency > 0 then
		return false
	end
	if string.sub(name, 1, 7) == "Greybox" then
		return sizeY <= 0.25
	end
	return string.sub(name, 1, 4) == "Bank"
		or string.sub(name, 1, 4) == "Tile"
		or string.sub(name, 1, 3) == "Pad"
		or string.sub(name, 1, 3) == "Seg"
end

-- The tallest thing a walking body steps onto (SquirrelMotor.params.glueMin: the same height it follows
-- down without leaving the ground), and the wall probe above it: a sphere from STEP to STEP + 0.7 over
-- the feet, the height of a squirrel's body.
ClientWorld.STEP = 0.75
ClientWorld.PROBE_RADIUS = 0.35
function ClientWorld.wallProbe(feetY: number): (number, number)
	return feetY + ClientWorld.STEP + ClientWorld.PROBE_RADIUS, ClientWorld.PROBE_RADIUS
end

-- The body's own box: BODY_HALF to each side of the centre (v5.4's collision radius was 0.32 u = 0.8 st;
-- the drawn squirrel's nose reaches further), from STEP to BODY_TOP above the feet.
ClientWorld.BODY_HALF = 1.0
ClientWorld.BODY_TOP = 1.7
function ClientWorld.bodyProbe(feetY: number): (number, number, number, number)
	local sy = ClientWorld.BODY_TOP - ClientWorld.STEP
	return feetY + ClientWorld.STEP + sy / 2, ClientWorld.BODY_HALF * 2, sy, ClientWorld.BODY_HALF * 2
end

-- Is this colliding part one of the invisible bough cylinders of a tree (Tree_<id>.R<route>_<i>)?
function ClientWorld.isBough(name: string, parentName: string): boolean
	return string.match(name, "^R%d") ~= nil and string.sub(parentName, 1, 5) == "Tree_"
end

local PLATE_REFRESH = 1 -- seconds between looks for Town.Lots / Town.Roads (they stream in)
local PLATE_HOPS = 4

function ClientWorld.get(): ClientWorld
	if singleton then
		return singleton
	end
	local ignoreList: { Instance } = {}
	local ray = RaycastParams.new()
	ray.FilterType = Enum.RaycastFilterType.Exclude
	ray.RespectCanCollide = true
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.RespectCanCollide = true
	overlap.MaxParts = 1
	-- the wall probes look past bough cylinders, so they need more than the first part found
	local walls = OverlapParams.new()
	walls.FilterType = Enum.RaycastFilterType.Exclude
	walls.RespectCanCollide = true
	walls.MaxParts = 24
	local function solid(found: { BasePart }): boolean
		for _, part in found do
			local parent = part.Parent
			if not ClientWorld.isBough(part.Name, if parent then parent.Name else "") then
				return true
			end
		end
		return false
	end

	-- the plate ray: only the folders that hold ground plates, colliding or not
	local plate = RaycastParams.new()
	plate.FilterType = Enum.RaycastFilterType.Include
	plate.RespectCanCollide = false
	local plateCount, plateAt = 0, -math.huge
	local function plates(): boolean
		local now = os.clock()
		if now - plateAt >= PLATE_REFRESH then
			plateAt = now
			local list: { Instance } = {}
			local town = workspace:FindFirstChild("Town")
			if town then
				for _, n in { "Lots", "Roads" } do
					local f = town:FindFirstChild(n)
					if f then
						table.insert(list, f)
					end
				end
			end
			if #list ~= plateCount then
				plateCount = #list
				plate.FilterDescendantsInstances = list
			end
		end
		return plateCount > 0
	end

	-- the same terrain function the server and the bake use (D32 extensions): without it the analytic
	-- fallback, the river and the world clamp are the v5.4 rectangle only
	local okExt, ext = pcall(function()
		return Data.default():module("TerrainExtensions")
	end)
	if okExt and type(ext) == "table" and (ext :: any).worldClampU then
		Height.configure(ext)
	end
	local clamp = Height.worldClamp() -- studs
	local rail: any? = nil

	local self: ClientWorld
	self = {
		railReady = false,
		clamp = { minX = clamp.minX, maxX = clamp.maxX, minZ = clamp.minZ, maxZ = clamp.maxZ },
		groundAt = function(x: number, z: number, refY: number): number
			local top = refY + 1.5
			local hit = workspace:Raycast(Vector3.new(x, top, z), Vector3.new(0, -400, 0), ray)
			local solidY = if hit then hit.Position.Y else Ground.groundAt(x, z, refY)
			if plates() then
				local from = top
				for _ = 1, PLATE_HOPS do
					if from - solidY <= 0.01 then
						break
					end
					local p = workspace:Raycast(Vector3.new(x, from, z), Vector3.new(0, solidY - from, 0), plate)
					if p == nil then
						break
					end
					local part = p.Instance
					if part.CanCollide then
						break -- the solid ray already answered for this one
					end
					if ClientWorld.groundLike(part.Name, part.Size.Y, part.Transparency) then
						return math.max(p.Position.Y, solidY)
					end
					from = p.Position.Y - 0.01
				end
			end
			return solidY
		end,
		blocked = function(x: number, z: number, y: number): boolean
			local cy, sx, sy, sz = ClientWorld.bodyProbe(y)
			return solid(workspace:GetPartBoundsInBox(CFrame.new(x, cy, z), Vector3.new(sx, sy, sz), walls))
		end,
		blockedCore = function(x: number, z: number, y: number): boolean
			local cy, r = ClientWorld.wallProbe(y)
			return solid(workspace:GetPartBoundsInRadius(Vector3.new(x, cy, z), r, walls))
		end,
		blockedRadius = function(x: number, z: number, y: number, r: number): boolean
			return #workspace:GetPartBoundsInRadius(Vector3.new(x, y + 0.3, z), r, overlap) > 0
		end,
		waterAt = function(x: number, z: number): number?
			if Height.insideRiverWater(x, z) then
				return Height.WATER_Y
			end
			return nil
		end,
		rail = function(): any?
			return rail
		end,
		ignore = function(list: { Instance })
			for _, i in list do
				table.insert(ignoreList, i)
			end
			ray.FilterDescendantsInstances = ignoreList
			overlap.FilterDescendantsInstances = ignoreList
			walls.FilterDescendantsInstances = ignoreList
		end,
	}
	task.spawn(function()
		local ok, result = pcall(function()
			return RailWorld.get(Data.default(), Height.at)
		end)
		if ok then
			rail = result
			self.railReady = true
		else
			warn(`ClientWorld: rail world unavailable ({result}); squirrels run on the ground only`)
		end
	end)
	singleton = self
	return self
end

return ClientWorld
