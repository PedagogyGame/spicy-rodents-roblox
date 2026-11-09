--!strict
-- StarterPlayer.StarterPlayerScripts.Client.World.ClientWorld
-- The world callbacks the client motors need (BUILD_PLAN §1.4 Movement/*, §4.4 #5): ground from a
-- downward raycast against the baked town and terrain, starting just above the body's reference
-- height so a roof overhead never counts (the pure World/Ground answer is the fallback where nothing
-- is hit, e.g. before the town streams in); walls from a small overlap query that respects
-- CanCollide; water from World/Height's river; the rail world (Movement/RailWorld) built once, in
-- the background, from Shared.Generated.
-- Interface: get() -> ClientWorld { groundAt, blocked, blockedRadius, waterAt, clamp, rail() -> RailWorld?,
--   ignore(instances) }
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

	local clampU = Height.worldClamp()
	local S = Height.STUDS_PER_UNIT
	local rail: any? = nil

	local self: ClientWorld
	self = {
		railReady = false,
		clamp = { minX = clampU.minX * S, maxX = clampU.maxX * S, minZ = clampU.minZ * S, maxZ = clampU.maxZ * S },
		groundAt = function(x: number, z: number, refY: number): number
			local hit = workspace:Raycast(Vector3.new(x, refY + 1.5, z), Vector3.new(0, -400, 0), ray)
			if hit then
				return hit.Position.Y
			end
			return Ground.groundAt(x, z, refY)
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
