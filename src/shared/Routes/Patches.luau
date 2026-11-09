--!strict
-- ReplicatedStorage.Shared.Routes.Patches
-- Applies data/harvest_patches.json (generated/HarvestPatches) to harvested routes (BUILD_PLAN §4.4 W1 #7
-- S-2 and #8; HANDOFF rule 3).
-- Interface: transform(patches, lots, studsPerUnit?) -> (route) -> (); attach(registry, patches, lots);
--            reseatTop(route, lot, studsPerUnit) -> newTopY?; actions(patches) -> { [routeId] = action }
--
-- Actions:
--   reseat            routes_movement verifier 3: addHouseGutters adds terrainHeight to the outer homes'
--                     already absolute eave (cfg.h = base + height, v5.4 L4298-4299, L2126), so the downspout
--                     top and the gutter-to-roof joint float about one terrain height above the eave. The
--                     port computes the top from the eave above local ground: top = seat + eaveU - 0.15 u.
--                     A downspout keeps its foot and is rescaled to the new top; a "gutter to roof" route
--                     moves only its first point (the joint), so the transfer between them stays exact.
--   harvest_lock      kept as harvested (lots and routes); recorded on the route as `patched`.
--   keep_off_geometry kept as harvested; recorded (the route-on-geometry check exempts it).
-- The harvested sampleCount is kept (rule 3); `length` is recomputed from the moved control points so
-- Motion's arc speeds stay true.

local Curve = require("./Curve")
local Registry = require("./Registry")

export type PatchData = { patches: { any }, lots: { any }? }

local Patches = {}

function Patches.actions(patches: PatchData): { [number]: string }
	local out: { [number]: string } = {}
	for _, p in patches.patches do
		for _, id in p.routes or {} do
			out[id] = p.action
		end
	end
	return out
end

local function seatOf(lot: any): number?
	local seat = lot.seat
	if type(seat) == "string" then
		local v = string.match(seat, "^absolute:([%-%d%.]+)$")
		return if v then tonumber(v) else nil
	end
	return nil
end

-- The locked lot whose footprint (plus a 3 u margin: the pipes stand 0.65 u off the walls) holds (x, z).
local function lotAt(lots: { any }, x: number, z: number, spu: number): any?
	local best, bestD = nil, math.huge
	for _, lot in lots do
		local fp = lot.footprint
		if fp and lot.x and lot.params and lot.params.eaveU then
			local w, d = fp.w, fp.d
			if lot.facing == "+X" or lot.facing == "-X" then
				w, d = d, w
			end
			local dx, dz = math.abs(x - lot.x), math.abs(z - lot.z)
			if dx <= w / 2 + 3 * spu and dz <= d / 2 + 3 * spu then
				local dd = dx * dx + dz * dz
				if dd < bestD then
					best, bestD = lot, dd
				end
			end
		end
	end
	return best
end

-- reseatTop(route, lot, spu): the corrected downspout top (studs), or nil when the lot has no seat.
function Patches.reseatTop(lot: any, spu: number): number?
	local seat = seatOf(lot)
	if seat == nil then
		return nil
	end
	return (seat + lot.params.eaveU - 0.15) * spu
end

function Patches.transform(patches: PatchData, lots: { any }, studsPerUnit: number?): (route: Registry.Route) -> ()
	local spu = studsPerUnit or 2.5
	local actions = Patches.actions(patches)
	local locked: { [string]: boolean } = {}
	for _, l in (patches.lots or {}) :: { any } do
		locked[l.lot] = true
	end
	local candidates = {}
	for _, lot in lots do
		if locked[lot.id] then
			table.insert(candidates, lot)
		end
	end
	return function(route: Registry.Route)
		local action = actions[route.id]
		if action == nil then
			return
		end
		route.patched = action
		if action ~= "reseat" then
			return
		end
		local pts = route.points
		local first, last = pts[1], pts[#pts]
		local lot = lotAt(candidates, first.x, first.z, spu)
		if not lot then
			route.patched = "reseat:no_lot"
			return
		end
		local top = Patches.reseatTop(lot, spu)
		if top == nil then
			route.patched = "reseat:no_seat"
			return
		end
		if route.kind == "trunk" then
			-- downspout: foot fixed, top to the eave, interior rescaled
			local y0, y1 = first.y, last.y
			local span = y1 - y0
			for i = 2, #pts do
				local p = pts[i]
				local f = if math.abs(span) > 1e-9 then (p.y - y0) / span else 1
				pts[i] = Curve.vec3(p.x, y0 + f * (top - y0), p.z)
			end
		else
			-- gutter to roof: only the joint at the downspout top moves
			pts[1] = Curve.vec3(first.x, top, first.z)
		end
		route.length = Curve.new(pts):getLength()
		route._curve = nil
		route._samples = nil
	end
end

-- attach(registry, patches, lots): install the transform on a registry (Data.routes() result).
function Patches.attach(registry: Registry.Registry, patches: PatchData, lots: { any })
	registry:setTransform(Patches.transform(patches, lots, registry:studsPerUnit()))
end

return Patches
