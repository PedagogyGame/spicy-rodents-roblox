--!strict
-- ReplicatedStorage.Shared.Movement.Trampoline
-- The trampoline bounce on `trampoline` routes [worldgen_core §5 item 4, verifier 4; BUILD_PLAN §4.4
-- #5]: v5.4 attemptTrampolineBounce (L10373-10392). A body off the rails within 4.67 u of the bed
-- centre, above surface + 0.04 on the previous step and at or below surface + 0.24 now, falling, is
-- bounced: y = surface + 0.22, vy = 14.2 + 0.9 * count (count + 1 per consecutive bounce, max 4,
-- reset beyond 9 u from the centre, updateWestside L10242), plus a 1.6 u/s push along the camera's
-- forward. v5.4's surface is 1.68 u over the flat core; here it is ground at the centre + 1.68 u.
-- Sites come from the registry's `trampoline` routes (the guard ring's 17-point route): centre =
-- mean of the samples, so a re-seated trampoline keeps working.
-- Interface: sitesFromRegistry(registry), site(cx, cz, groundY), attempt(site, state, prevY,
--   cameraYaw) -> boolean, bedAt(sites, x, z, refY) -> number? (Ground's bed term)
-- Pure; studs. No side effects on require.

export type Site = { x: number, z: number, surface: number, count: number, flex: number }

-- the subset of SquirrelMotor/QuadrupedMotor state the bounce touches
export type Body = {
	x: number,
	y: number,
	z: number,
	vx: number,
	vy: number,
	vz: number,
	grounded: boolean,
	committedAirborne: boolean?,
	cameraCommit: number?,
	routeId: number?,
	[string]: any,
}

local S = 2.5
local Trampoline = {}

Trampoline.C = table.freeze({
	radius = 4.67 * S,
	surface = 1.68 * S,
	resetRadius = 9 * S,
	baseVy = 14.2 * S,
	perBounceVy = 0.9 * S,
	maxCount = 4,
	push = 1.6 * S,
	bedRadius = 5 * S, -- getGroundAt's bed term: y 1.65 within r 5 while above 1.1 (L6239)
	bedY = 1.65 * S,
	bedAbove = 1.1 * S,
})
local C = Trampoline.C

function Trampoline.site(cx: number, cz: number, groundY: number): Site
	return { x = cx, z = cz, surface = groundY + C.surface, count = 0, flex = 0 }
end

-- sitesFromRegistry(registry, groundAt?): one site per trampoline route.
function Trampoline.sitesFromRegistry(registry: any, groundAt: ((x: number, z: number) -> number)?): { Site }
	local out = {}
	for _, route in registry:all() do
		if route.kind == "trampoline" then
			local pts = registry:samples(route)
			local sx, sz = 0, 0
			for _, p in pts do
				sx += p.x
				sz += p.z
			end
			local cx, cz = sx / #pts, sz / #pts
			table.insert(out, Trampoline.site(cx, cz, if groundAt then groundAt(cx, cz) else 0))
		end
	end
	return out
end

-- attempt(site, body, prevY, cameraYaw): applies the bounce and returns true, or returns false.
function Trampoline.attempt(site: Site, body: Body, prevY: number, cameraYaw: number): boolean
	local dx, dz = body.x - site.x, body.z - site.z
	local d = math.sqrt(dx * dx + dz * dz)
	if d > C.resetRadius then
		site.count = 0
	end
	if body.routeId ~= nil or d >= C.radius then
		return false
	end
	if prevY < site.surface + 0.04 * S or body.y > site.surface + 0.24 * S or body.vy >= 0 then
		return false
	end
	site.count = math.min(C.maxCount, site.count + 1)
	site.flex = 1
	body.y = site.surface + 0.22 * S
	body.vy = C.baseVy + site.count * C.perBounceVy
	body.grounded = false
	if body.committedAirborne ~= nil then
		body.committedAirborne = true
	end
	if body.cameraCommit ~= nil then
		body.cameraCommit = 0.4
	end
	body.vx += -math.sin(cameraYaw) * C.push
	body.vz += -math.cos(cameraYaw) * C.push
	return true
end

-- attemptAny(sites, body, prevY, cameraYaw): the first site that bounces.
function Trampoline.attemptAny(sites: { Site }, body: Body, prevY: number, cameraYaw: number): boolean
	for _, site in sites do
		if Trampoline.attempt(site, body, prevY, cameraYaw) then
			return true
		end
	end
	return false
end

-- bedAt(sites, x, z, refY): the bed as a standable surface for bodies above it (getGroundAt L6239).
function Trampoline.bedAt(sites: { Site }, x: number, z: number, refY: number): number?
	for _, site in sites do
		local base = site.surface - C.surface
		local dx, dz = x - site.x, z - site.z
		if dx * dx + dz * dz < C.bedRadius * C.bedRadius and refY > base + C.bedAbove then
			return base + C.bedY
		end
	end
	return nil
end

-- flex decay (visual bed dip 0.35 * sin(flex * pi), decays 2.8/s)
function Trampoline.decay(site: Site, dt: number)
	site.flex = math.max(0, site.flex - 2.8 * dt)
end

return Trampoline
