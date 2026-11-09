--!strict
-- ReplicatedStorage.Shared.Routes.Registry
-- Registry of harvested plus template routes.
-- Interface (BUILD_PLAN D8): get(id), all()
--
-- Routes come from the compiled chunks `Shared.Generated.Routes_01..04` (tools/compile over
-- data/harvest/routes.json; studs). Chunks load lazily: requiring this module loads nothing, `get(id)`
-- requires chunks in order until the id is found, `all()` loads the rest. Every route object carries
-- its control points, the harvested length, the harvested sample count (routes_movement §1.1:
-- `max(20, ceil(3L)) + 1`; taken from the record when the compiler emits `sampleCount`, otherwise
-- derived from the harvested length in HTML units, which is exact for all 1,332 routes and is NOT a
-- recomputation from the curve, docs/reports/w0_check.md §6.6), and the per-route visual fields.
-- The curve and the arc-length samples are built on first use and cached on the route.
--
-- Name-based behaviour (routes_movement §4) becomes explicit flags here (`Registry.deriveFlags`); the
-- compiler will emit them as route attributes in W1 (D8), at which point the record's own flags win.
-- Pure: no engine calls except inside `fromGenerated`, which is the engine-side constructor.

local Curve = require("./Curve")
local Units = require("../Config/Units")

local Registry = {}
Registry.__index = Registry

export type Vec3 = Curve.Vec3

-- One compiled record (generated/Routes_*.luau; lengths in studs).
export type RouteRecord = {
	id: number,
	name: string,
	kind: string,
	points: { { number } },
	length: number,
	surfaceRadius: number,
	visualOffset: number?,
	trunkClearance: number?,
	center: { number }?,
	speedMult: number?,
	v54Speed: number?,
	origin: string?,
	generator: string?,
	sampleCount: number?,
	lotId: string?,
	flags: RouteFlags?,
}

export type RouteFlags = {
	autoGrabExcluded: boolean, -- /downspout|gutter|ladder/i: never a walk-in or ground E candidate (L5746)
	isPole: boolean, -- /telephone pole/i: 1.85 u horizontal gate, +0.2 rank, fixed r+0.2 offset (L5747-5759)
	isGiant: boolean, -- "giant trunk": taper max(0.45, r/0.95 - 1.05t) (L6781)
	fixedSurfaceZ: boolean, -- "downspout" or "gutter": visual surface normal forced to +Z (L6776-6779)
	treeTravel: boolean, -- trunk/branch/bridge/lookout: x0.6 speed and the slow gallop cadence (L6617, L6671)
}

export type Route = {
	id: number,
	name: string,
	kind: string,
	points: { Vec3 },
	length: number, -- studs (or the data's unit when studsPerUnit = 1)
	sampleCount: number,
	surfaceRadius: number,
	visualOffset: number?,
	trunkClearance: number?,
	center: Vec3?,
	speedMult: number,
	origin: string,
	lotId: string?,
	flags: RouteFlags,
	patched: string?, -- the harvest_patches action applied (Routes/Patches), nil when as harvested
	_curve: Curve.Curve?,
	_samples: { Vec3 }?,
}

export type Loader = () -> { RouteRecord }

export type Options = {
	loaders: { Loader }, -- one per chunk, in id order (Routes_01, Routes_02, ...)
	studsPerUnit: number?, -- scale of the data's lengths per HTML unit (default Units.STUDS_PER_UNIT)
	transform: ((route: Route) -> ())?, -- applied to every route as its chunk loads (Routes/Patches)
}

export type Registry = typeof(setmetatable(
	{} :: {
		_loaders: { Loader },
		_loaded: number,
		_byId: { [number]: Route },
		_all: { Route },
		_studsPerUnit: number,
		_transform: ((route: Route) -> ())?,
	},
	Registry
))

Registry.TREE_TRAVEL_KINDS = { trunk = true, branch = true, bridge = true, lookout = true }
Registry.KINDS = { "trunk", "branch", "bridge", "lookout", "roof", "wire", "fence", "trampoline" }

-- Explicit attributes for the v5.4 name regexes (routes_movement §4; D8 replaces the regexes).
function Registry.deriveFlags(name: string, kind: string): RouteFlags
	local lower = string.lower(name)
	local downspoutOrGutter = string.find(lower, "downspout", 1, true) ~= nil
		or string.find(lower, "gutter", 1, true) ~= nil
	return {
		autoGrabExcluded = downspoutOrGutter or string.find(lower, "ladder", 1, true) ~= nil,
		isPole = string.find(lower, "telephone pole", 1, true) ~= nil,
		isGiant = string.find(lower, "giant trunk", 1, true) ~= nil,
		fixedSurfaceZ = downspoutOrGutter,
		treeTravel = Registry.TREE_TRAVEL_KINDS[kind] == true,
	}
end

local function toRoute(rec: RouteRecord, studsPerUnit: number): Route
	local pts = table.create(#rec.points)
	for i, p in rec.points do
		pts[i] = Curve.vec3(p[1], p[2], p[3])
	end
	-- Without a record count, the harvested length in HTML units reproduces the game's own ceil(3L) for
	-- every route (verified in tests/unit/routes_registry.spec.luau against data/harvest/routes.json).
	local sampleCount: number = rec.sampleCount or (Curve.sampleSteps(rec.length / studsPerUnit) + 1)
	local center: Vec3? = nil
	if rec.center then
		center = Curve.vec3(rec.center[1], rec.center[2], rec.center[3])
	end
	return {
		id = rec.id,
		name = rec.name,
		kind = rec.kind,
		points = pts,
		length = rec.length,
		sampleCount = sampleCount,
		surfaceRadius = rec.surfaceRadius,
		visualOffset = rec.visualOffset,
		trunkClearance = rec.trunkClearance,
		center = center,
		speedMult = rec.speedMult or 1,
		origin = rec.origin or "harvest",
		lotId = rec.lotId,
		flags = rec.flags or Registry.deriveFlags(rec.name, rec.kind),
		patched = nil,
		_curve = nil,
		_samples = nil,
	}
end

function Registry.new(opts: Options): Registry
	local self = setmetatable({
		_loaders = opts.loaders,
		_loaded = 0,
		_byId = {} :: { [number]: Route },
		_all = {} :: { Route },
		_studsPerUnit = opts.studsPerUnit or Units.STUDS_PER_UNIT,
		_transform = opts.transform,
	}, Registry)
	return self
end

-- setTransform(fn): install a per-route transform (W1 #8: harvest_patches) on an existing registry;
-- routes already loaded are transformed now (their cached curve and samples are dropped).
function Registry.setTransform(self: Registry, fn: (route: Route) -> ())
	self._transform = fn
	for _, route in self._all do
		fn(route)
		route._curve = nil
		route._samples = nil
	end
end

-- fromRecords(records): a registry over an in-memory list (tests, templates, engine subsets).
function Registry.fromRecords(records: { RouteRecord }, studsPerUnit: number?): Registry
	return Registry.new({
		loaders = {
			function()
				return records
			end,
		},
		studsPerUnit = studsPerUnit,
	})
end

-- fromGenerated(generatedFolder): engine-side constructor over ReplicatedStorage.Shared.Generated.
-- Reads `Index.modules.Routes.chunks` and requires each chunk ModuleScript on first use.
function Registry.fromGenerated(generatedFolder: Instance): Registry
	local indexModule = generatedFolder:FindFirstChild("Index")
	if not indexModule then
		error("Registry.fromGenerated: Generated.Index missing")
	end
	local index = (require :: any)(indexModule)
	local chunkNames: { string } = index.modules.Routes.chunks
	local loaders: { Loader } = {}
	for i, name in chunkNames do
		loaders[i] = function()
			local chunk = generatedFolder:FindFirstChild(name)
			if not chunk then
				error(`Registry.fromGenerated: chunk {name} missing`)
			end
			return (require :: any)(chunk)
		end
	end
	return Registry.new({ loaders = loaders, studsPerUnit = index.studsPerUnit })
end

function Registry._loadNext(self: Registry): boolean
	if self._loaded >= #self._loaders then
		return false
	end
	self._loaded += 1
	local records = self._loaders[self._loaded]()
	for _, rec in records do
		local route = toRoute(rec, self._studsPerUnit)
		if self._transform then
			self._transform(route)
		end
		if self._byId[route.id] then
			error(`Registry: duplicate route id {route.id}`)
		end
		self._byId[route.id] = route
		table.insert(self._all, route)
	end
	return true
end

-- get(id): the route or nil; loads chunks in order until the id appears.
function Registry.get(self: Registry, id: number): Route?
	local route = self._byId[id]
	while route == nil and self:_loadNext() do
		route = self._byId[id]
	end
	return route
end

-- all(): every route, id order (loads every chunk).
function Registry.all(self: Registry): { Route }
	local more = true
	while more do
		more = self:_loadNext()
	end
	return self._all
end

function Registry.count(self: Registry): number
	return #self:all()
end

function Registry.loadedChunks(self: Registry): number
	return self._loaded
end

function Registry.studsPerUnit(self: Registry): number
	return self._studsPerUnit
end

-- curve(route): the centripetal Catmull-Rom, built once.
function Registry.curve(_self: Registry, route: Route): Curve.Curve
	local cached = route._curve
	if cached then
		return cached
	end
	local curve = Curve.new(route.points)
	route._curve = curve
	return curve
end

-- samples(route): route.sampled, the sampleCount arc-length-spaced points (built once).
function Registry.samples(self: Registry, route: Route): { Vec3 }
	local cached = route._samples
	if cached then
		return cached
	end
	local samples = self:curve(route):getSpacedPoints(route.sampleCount - 1)
	route._samples = samples
	return samples
end

function Registry.pointAt(self: Registry, route: Route, t: number): Vec3
	return self:curve(route):getPointAt(t)
end

function Registry.tangentAt(self: Registry, route: Route, t: number): Vec3
	return self:curve(route):getTangentAt(t)
end

-- foot(route): sampled[0], the physical foot used by groundTrunkCandidate (L5754).
function Registry.foot(self: Registry, route: Route): Vec3
	return self:samples(route)[1]
end

-- kindCounts(): regression counts (routes_movement §1.4).
function Registry.kindCounts(self: Registry): { [string]: number }
	local counts: { [string]: number } = {}
	for _, route in self:all() do
		counts[route.kind] = (counts[route.kind] or 0) + 1
	end
	return counts
end

return Registry
