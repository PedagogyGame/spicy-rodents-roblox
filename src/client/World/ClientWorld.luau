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
-- Interface: get() -> ClientWorld { groundAt, blocked, blockedRadius, waterAt, clamp, rail() -> RailWorld?,
--   ignore(instances) }; groundLike(name, sizeY, transparency) -> boolean (pure)
-- No side effects on require (services are looked up on first get()).

local Import = require("../Import")
local Ground = Import.shared("World/Ground") :: typeof(require("../../shared/World/Ground"))
local Height = Import.shared("World/Height") :: typeof(require("../../shared/World/Height"))
local RailWorld = Import.shared("Movement/RailWorld") :: typeof(require("../../shared/Movement/RailWorld"))
local Data = Import.shared("Data") :: typeof(require("../../shared/Data"))

export type ClientWorld = {
	groundAt: (x: number, z: number, refY: number) -> number,
	blocked: (x: number, z: number, y: number) -> boolean,
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
			return #workspace:GetPartBoundsInRadius(Vector3.new(x, y + 0.6, z), 0.35, overlap) > 0
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
