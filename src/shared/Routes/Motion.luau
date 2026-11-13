--!strict
-- ReplicatedStorage.Shared.Routes.Motion
-- advance, junction and fork choice, visual pose.
-- Interface (BUILD_PLAN §1.4): advance(state, input, dt), visualPose(state)
--
-- The pure rail rules of v5.4 (reference/v5_4_game.js), shared by the player's SquirrelMotor, the AI
-- squirrel brain and the server MoveValidator:
--   RouteMotion.advance (L267-272)            routes_movement §1.2
--   RouteJunction inward/canTransfer/ease     §9.3, L5782-5793
--   nearestRoute / groundTrunkCandidate /     §9.1-§9.2, L5718-5778
--     forwardIntoTrunk
--   directionFromView / routeTangentXZ        §10, L5806-5819
--   switchRoute (end-of-route auto switch)    §11.1, L5941-5986
--   junctionCandidates / chooseRouteJunction  §11.2, L6004-6061
--   canopy forks: nearby, choose, take,       §12, L4386-4456
--     side-step, W auto-take
--   visual placement                          §14, L6769-6820
-- and the geometry of enclosed runs (Routes/Enclosure: mouths, entry, the transfer filter). Every enclosure rule
-- applies only to routes that carry `enclosure` (kind "tunnel"); with none in the world every function here
-- answers exactly as before.
-- Everything takes a `World` ({ registry, index, graph }) and plain numbers; no engine types. All
-- distances are studs (the v5.4 constants are declared in HTML units and converted once, here).

local Curve = require("./Curve")
local Enclosure = require("./Enclosure")
local Graph = require("./Graph")
local Registry = require("./Registry")
local SpatialIndex = require("./SpatialIndex")
local Units = require("../Config/Units")

local Motion = {}

export type Vec3 = Curve.Vec3
export type Route = Registry.Route

export type World = {
	registry: Registry.Registry,
	index: SpatialIndex.SpatialIndex,
	graph: Graph.Graph,
	_trunkFeet: { TrunkFoot }?,
	_mouths: { MouthRef }?, -- every mouth of every enclosed route (built once)
	_enclosed: boolean?, -- any enclosed route in the registry
}

export type TrunkFoot = { id: number, x: number, y: number, z: number, isPole: boolean }

-- Where a route is entered: route id, parameter and (optional) travel direction.
export type EnterSpec = { routeId: number, t: number, dir: number?, d: number? }

export type Candidate = { routeId: number, t: number, d: number }

-- A mouth placed in the world: its route, the mouth point, `out` (unit, pointing outside) and the direction along
-- the route that leads in (+1 / -1 at an end; 0 part-way: the view decides).
export type MouthRef = {
	routeId: number,
	mouth: Enclosure.Mouth,
	x: number,
	y: number,
	z: number,
	ox: number,
	oy: number,
	oz: number,
	inward: number,
}

-- v5.4 constants in HTML units (routes_movement §20 scale table), converted to studs once.
local st = Units.st
Motion.C = {
	autoSwitchGap = st(0.48), -- RouteJunction.canTransfer(gap) (L5785)
	explicitGap = st(1.7), -- canTransfer(gap, true)
	enterMaxGap = st(3.15), -- enterRoute: gap limit while already on a route (L5834)
	bridgeMinGap = st(0.11), -- enterRoute: transfer easing only above this gap (L5838)
	eSearch = st(1.95), -- attachRoute on a rail: nearestRoute(1.95) (L5879)
	airCatch = st(0.6), -- a leap off a rail lands on a branch or wire that passes this near the feet
	airCatchPad = st(0.5), -- index samples this far out are refined along their curve (they are 1/3 u apart)
	airCatchClear = st(1.0), -- travel from the launch point before another rail can be caught
	airCatchOwn = st(2.4), -- travel before the rail that was left can be caught again (falling only)
	groundReachE = st(3.1), -- attachRoute off rail: groundTrunkCandidate(3.1) (L5884)
	airGrab = st(3.4), -- attachRoute off rail: nearestRoute(3.4) (L5884)
	walkInReach = st(2.0), -- walk-in auto-grab reach (L6640)
	poleGate = st(1.85), -- groundTrunkCandidate pole horizontal gate (L5747)
	maxRise = st(3.1), -- groundTrunkCandidate |dy| (L5756)
	riseWeight = 0.24, -- rank = horizontal + rise * 0.24 (+0.2 u for poles)
	polePenalty = st(0.2),
	footSnap = st(0.12), -- forwardIntoTrunk: within 0.12 counts as into (L5771)
	intoDot = 0.43, -- forwardIntoTrunk dot threshold (L5776)
	junctionRadius = st(2.15), -- junctionCandidates search radius (L6007)
	junctionOutwardLenSq = st(1) * st(1) * 0.24, -- junctionOutward delta.lengthSq() > 0.24 (L6030)
	junctionTangentDt = 0.09, -- junctionOutward tangent from t +- 0.09
	junctionSideMin = -0.08, -- chooseRouteJunction filter (L6041)
	forkTake = st(2.15), -- takeSelectedFork |dy| limit (L4448)
	forkTakeForced = st(2.75), -- ... when forced by holding W (L4449)
	forkEnterT = 0.018, -- enterRoute({branch, t: 0.018}) (L4452)
	forkBelow = st(1.9), -- nearbyCanopyForks window [h - 1.9, h + 10.5] (L4390)
	forkAbove = st(10.5),
	forkFallback = st(5.5), -- ... else |dh| < 5.5
	forkSideMin = -0.1, -- chooseCanopyFork filter (L4397)
	forkUpWeight = 0.48, -- per stud of climb (weights are per unit; applied to studs after dividing)
	forkAbsWeight = 0.10,
	forkSideWeight = 3.2,
	siblingMaxT = 0.21, -- sideStepToSibling railT <= 0.21 (L4424)
	siblingHeight = st(2.9), -- |dh| < 2.9 (L4430)
	siblingSideMin = -0.12,
	siblingEnterT = 0.03,
	forkAutoBehind = st(0.42), -- W auto-take: railT*L >= fork.t*L - 0.42 (L6680)
	forkAutoAheadT = 0.022, -- before <= fork.t + 0.022 (L6681)
	inwardLow = 0.035, -- RouteJunction.inward (L5783)
	inwardHigh = 0.965,
	endWindowLow = Graph.END_T_LOW, -- switchRoute end window (L5951)
	endWindowHigh = Graph.END_T_HIGH,
	switchContinuity = 2, -- score = 2*continuity + 2.9*view - 1.6*gap(u) (L5973)
	switchView = 2.9,
	switchGap = 1.6, -- per HTML unit of gap
	switchTie = 0.65, -- stall when best - second < 0.65 (L5980)
	switchFloor = -0.75, -- never auto-turn away: score < -0.75 (L5985)
	tangentClampLow = 0.006, -- routeTangentXZ clamp (L5806)
	tangentClampHigh = 0.994,
	tangentMinLenSq = 0.0001,
	viewDot = 0.18, -- directionFromView camera test (L5813)
	facingDot = 0.28, -- ... body-facing fallback (L5817)
	railWalk = st(7.2), -- rail speeds (L6668-6671), studs/s
	railSprint = st(12.2),
	railStalk = st(1.2),
	boostMult = 1.6,
	treeTravelMult = 0.6,
	advanceMaxDt = 0.05, -- RouteMotion.advance clamp (L268)
	advanceMinLength = st(1), -- max(1, length) (L269)
	bridgeBase = 0.13, -- routeBridge duration clamp(0.13 + 0.065*gap(u), 0.15, 0.31) (L5842)
	bridgePerUnit = 0.065,
	bridgeMin = 0.15,
	bridgeMax = 0.31,
	bridgeMaxStep = 0.05, -- elapsed += min(dt, 0.05) (L6657)
	yawRate = 14, -- body yaw rate on a rail (L6700)
	tangentYawMin = 0.25, -- |tx| + |tz| > 0.25 before steering yaw (L6697)
	visualBranchLift = st(0.5), -- §14 visual offsets
	visualLookoutLift = st(0.61),
	visualWireLift = st(0.22),
	visualClearancePad = st(0.31),
	visualClearanceT = 0.2,
	visualClearanceSampleT = 0.16,
	visualTrunkPad = st(0.28),
	visualTrunkFixedPad = st(0.2),
	visualTrunkMinR = st(0.32),
	visualTrunkTaper = 0.48,
	visualGiantMinR = st(0.45),
	visualGiantTaper = st(1.05),
	visualDefaultR = st(1.3),
}
local C = Motion.C

-- RouteMotion.advance(t, dir, forward, seconds, speed, length) (L267-272). `minLength` defaults to
-- 1 u in studs; pass 1 when speed and length are HTML units (golden tests).
function Motion.advance(
	t: number,
	dir: number,
	forward: number,
	seconds: number,
	speed: number,
	length: number,
	minLength: number?
): number
	local dt = math.max(0, math.min(seconds, C.advanceMaxDt))
	return t + (forward * dir * dt * speed) / math.max(minLength or C.advanceMinLength, length)
end

-- RouteJunction (L5782-5793)
function Motion.inward(t: number, desired: number): number
	if t < C.inwardLow then
		return 1
	elseif t > C.inwardHigh then
		return -1
	end
	return desired
end

function Motion.canTransfer(gap: number, explicit: boolean?): boolean
	if gap ~= gap or gap == math.huge or gap == -math.huge then
		return false
	end
	return gap <= (if explicit then C.explicitGap else C.autoSwitchGap)
end

function Motion.ease(p: number): number
	p = math.max(0, math.min(1, p))
	return p * p * (3 - 2 * p)
end

-- Rail speed (L6668-6671), studs/s. treeTravel = kind in {trunk, branch, bridge, lookout}.
function Motion.railSpeed(treeTravel: boolean, sprint: boolean, focus: boolean, boosted: boolean): number
	local base = if focus then C.railStalk elseif sprint then C.railSprint else C.railWalk
	if boosted and not focus then
		base *= C.boostMult
	end
	if treeTravel then
		base *= C.treeTravelMult
	end
	return base
end

-- Camera basis in XZ (L5796-5801): forward = (-sin yaw, -cos yaw), right = (cos yaw, -sin yaw).
function Motion.cameraForwardXZ(cameraYaw: number): (number, number)
	return -math.sin(cameraYaw), -math.cos(cameraYaw)
end

function Motion.cameraRightXZ(cameraYaw: number): (number, number)
	return math.cos(cameraYaw), -math.sin(cameraYaw)
end

-- routeTangentXZ(route, t) (L5805-5809): XZ unit tangent at clamp(t, 0.006, 0.994), or nil.
function Motion.routeTangentXZ(world: World, route: Route, t: number): (number?, number?)
	local tan = world.registry:tangentAt(route, math.clamp(t, C.tangentClampLow, C.tangentClampHigh))
	local lenSq = tan.x * tan.x + tan.z * tan.z
	if lenSq > C.tangentMinLenSq then
		local len = math.sqrt(lenSq)
		return tan.x / len, tan.z / len
	end
	return nil, nil
end

-- directionFromView(route, t, fallback) (L5810-5819). Trunks always travel +1 (W climbs), and so does an
-- enclosed run that is a wall to climb (Enclosure: climb).
function Motion.directionFromView(
	world: World,
	route: Route,
	t: number,
	cameraYaw: number,
	bodyYaw: number,
	fallback: number
): number
	if route.kind == "trunk" then
		return 1
	end
	local spec = route.enclosure
	if spec and spec.climb then
		return 1
	end
	local tx, tz = Motion.routeTangentXZ(world, route, t)
	if tx == nil or tz == nil then
		return fallback
	end
	local fx, fz = Motion.cameraForwardXZ(cameraYaw)
	local d = tx * fx + tz * fz
	if math.abs(d) > C.viewDot then
		return if d >= 0 then 1 else -1
	end
	local facing = tx * math.sin(bodyYaw) + tz * math.cos(bodyYaw)
	if math.abs(facing) > C.facingDot then
		return if facing >= 0 then 1 else -1
	end
	return fallback
end

-- headingAlong(route, t, dir): body yaw along the travel direction (resyncRouteHeading, L5820-5825).
function Motion.headingAlong(world: World, route: Route, t: number, dir: number): number?
	local tx, tz = Motion.routeTangentXZ(world, route, t)
	if tx == nil or tz == nil then
		return nil
	end
	return math.atan2(tx * dir, tz * dir)
end

-- nearestRoute (L5718): closest sample within maxDist, excluding one route; `accept(routeId, t)` (from openOnly or
-- transferFilter) skips what it refuses.
function Motion.nearestRoute(
	world: World,
	x: number,
	y: number,
	z: number,
	maxDist: number,
	excludeRouteId: number?,
	accept: ((routeId: number, t: number) -> boolean)?
): Candidate?
	local hit = world.index:nearest(x, y, z, maxDist, excludeRouteId, accept)
	if not hit then
		return nil
	end
	return { routeId = hit.routeId, t = hit.t, d = hit.d }
end

-- airCatch: the branch, wire or other non-trunk rail whose curve passes within `radius` of the point, the
-- nearest if there are several (owner 2026-11-10: "when jumping from branch or line, if the squirrel's
-- jump and fall lines up with other branch or line, make it land on that"). The index holds arc-length
-- samples a few studs apart, so each rail with a sample inside radius + airCatchPad is refined along its
-- curve between the neighbouring samples before the distance is judged. Trunks and poles are never
-- caught in the air (running into one climbs it; E still grabs one), nor is an enclosed run (Routes/Enclosure: only
-- through a mouth).
function Motion.airCatch(
	world: World,
	x: number,
	y: number,
	z: number,
	radius: number,
	excludeRouteId: number?
): Candidate?
	local reach = radius + C.airCatchPad
	local near: { [number]: { t: number, d: number } } = {}
	world.index:forEachNear(x, y, z, math.max(1, math.ceil(reach / world.index.cellSize)), function(id, t, sx, sy, sz)
		if id ~= excludeRouteId then
			local dx, dy, dz = sx - x, sy - y, sz - z
			local d = math.sqrt(dx * dx + dy * dy + dz * dz)
			local had = near[id]
			if d <= reach and (had == nil or d < had.d) then
				near[id] = { t = t, d = d }
			end
		end
		return nil
	end)
	local best: Candidate? = nil
	for id, hit in near do
		local route = world.registry:get(id)
		if route and route.kind ~= "trunk" and not route.flags.isPole and route.enclosure == nil then
			-- the closest point of the curve between the samples either side of the nearest one
			local span = 1 / math.max(route.sampleCount - 1, 1)
			local lo, hi = math.max(0, hit.t - span), math.min(1, hit.t + span)
			local function dist(t: number): number
				local p = world.registry:pointAt(route, t)
				return math.sqrt((p.x - x) ^ 2 + (p.y - y) ^ 2 + (p.z - z) ^ 2)
			end
			for _ = 1, 12 do
				local a, b = lo + (hi - lo) / 3, hi - (hi - lo) / 3
				if dist(a) < dist(b) then
					hi = b
				else
					lo = a
				end
			end
			local t = (lo + hi) / 2
			local d = dist(t)
			if d <= radius and (best == nil or d < best.d) then
				best = { routeId = id, t = t, d = d }
			end
		end
	end
	return best
end

local function trunkFeet(world: World): { TrunkFoot }
	local cached = world._trunkFeet
	if cached then
		return cached
	end
	local feet: { TrunkFoot } = {}
	for _, route in world.registry:all() do
		if route.kind == "trunk" and not route.flags.autoGrabExcluded then
			local foot = world.registry:foot(route)
			table.insert(feet, { id = route.id, x = foot.x, y = foot.y, z = foot.z, isPole = route.flags.isPole })
		end
	end
	world._trunkFeet = feet
	return feet
end

-- groundTrunkCandidate(point, reach) (L5742-5766): the best trunk foot by rank; t = 0.
function Motion.groundTrunkCandidate(world: World, x: number, y: number, z: number, reach: number): Candidate?
	local best: Candidate? = nil
	local score = math.huge
	for _, foot in trunkFeet(world) do
		local horizontal = math.sqrt((x - foot.x) ^ 2 + (z - foot.z) ^ 2)
		if foot.isPole and reach > C.poleGate and horizontal > C.poleGate then
			continue
		end
		local rise = math.abs(y - foot.y)
		if horizontal > reach or rise > C.maxRise then
			continue
		end
		local rank = horizontal + rise * C.riseWeight + (if foot.isPole then C.polePenalty else 0)
		if rank < score then
			score = rank
			best = { routeId = foot.id, t = 0, d = horizontal }
		end
	end
	return best
end

-- forwardIntoTrunk (L5767-5778): the camera-relative move direction points at the foot.
function Motion.forwardIntoTrunk(
	world: World,
	candidate: Candidate?,
	px: number,
	pz: number,
	fw: number,
	side: number,
	cameraYaw: number
): boolean
	if not candidate or fw <= 0 then
		return false
	end
	local route = world.registry:get(candidate.routeId)
	if not route then
		return false
	end
	local foot = world.registry:foot(route)
	local dx, dz = foot.x - px, foot.z - pz
	local distance = math.sqrt(dx * dx + dz * dz)
	if distance < C.footSnap then
		return true
	end
	local mvx = -math.sin(cameraYaw) * fw + math.cos(cameraYaw) * side
	local mvz = -math.cos(cameraYaw) * fw - math.sin(cameraYaw) * side
	local length = math.sqrt(mvx * mvx + mvz * mvz)
	return length > 0.1 and (mvx * dx + mvz * dz) / (length * distance) > C.intoDot
end

-- bridgeDuration(gap): transfer easing time (L5842), gap in studs.
function Motion.bridgeDuration(gap: number): number
	return math.clamp(C.bridgeBase + Units.u(gap) * C.bridgePerUnit, C.bridgeMin, C.bridgeMax)
end

export type SwitchResult = {
	chosen: EnterSpec?,
	reason: string, -- "ok" | "none" | "stall" | "away"
	candidates: number,
}

-- switchRoute(old, atStart) (L5941-5986): the automatic end-of-route switch.
-- selectedRouteId is the A/D selection (selectedJunction.route) if any.
function Motion.switchRoute(
	world: World,
	old: Route,
	atStart: boolean,
	cameraYaw: number,
	selectedRouteId: number?
): SwitchResult
	local reg = world.registry
	local cur = reg:pointAt(old, if atStart then 0 else 1)
	local outward = reg:tangentAt(old, if atStart then 0 else 1)
	local sgn = if atStart then -1 else 1
	local ox, oy, oz = outward.x * sgn, outward.y * sgn, outward.z * sgn

	local seen: { [number]: { routeId: number, t: number, gap: number } } = {}
	world.index:forEachNear(cur.x, cur.y, cur.z, 1, function(id, t, sx, sy, sz)
		if id == old.id or (t > C.endWindowLow and t < C.endWindowHigh) then
			return nil
		end
		local dx, dy, dz = sx - cur.x, sy - cur.y, sz - cur.z
		local gap = math.sqrt(dx * dx + dy * dy + dz * dz)
		if not Motion.canTransfer(gap) then
			return nil
		end
		local prev = seen[id]
		if not prev or gap < prev.gap then
			seen[id] = { routeId = id, t = t, gap = gap }
		end
		return nil
	end)

	local fx, fz = Motion.cameraForwardXZ(cameraYaw)
	local candidates: { { routeId: number, t: number, gap: number, dir: number, score: number } } = {}
	for _, c in seen do
		local route = reg:get(c.routeId)
		if not route then
			continue
		end
		if route.kind == "trunk" and old.kind ~= "bridge" then
			continue
		end
		-- never into or out of an enclosed run except where a mouth says (Enclosure rule 5)
		if not Enclosure.allows(old, if atStart then 0 else 1, route, c.t) then
			continue
		end
		local tangent = reg:tangentAt(route, math.clamp(c.t, 0.002, 0.998))
		local toward = if (tangent.x * ox + tangent.y * oy + tangent.z * oz) >= 0 then 1 else -1
		local dir = Motion.inward(c.t, toward)
		local tx, ty, tz = tangent.x * dir, tangent.y * dir, tangent.z * dir
		local xzLen = math.sqrt(tx * tx + tz * tz)
		local view = 0
		if xzLen > 0 then
			view = fx * (tx / xzLen) + fz * (tz / xzLen)
		end
		local continuity = tx * ox + ty * oy + tz * oz
		local score = continuity * C.switchContinuity + view * C.switchView - Units.u(c.gap) * C.switchGap
		table.insert(candidates, { routeId = c.routeId, t = c.t, gap = c.gap, dir = dir, score = score })
	end
	if #candidates == 0 then
		return { chosen = nil, reason = "none", candidates = 0 }
	end
	table.sort(candidates, function(a, b)
		return a.score > b.score
	end)
	local chosen = nil
	if selectedRouteId then
		for _, c in candidates do
			if c.routeId == selectedRouteId then
				chosen = c
				break
			end
		end
	end
	local best = chosen or candidates[1]
	if not chosen and #candidates > 1 and best.score - candidates[2].score < C.switchTie then
		return { chosen = nil, reason = "stall", candidates = #candidates }
	end
	if not chosen and best.score < C.switchFloor then
		return { chosen = nil, reason = "away", candidates = #candidates }
	end
	return {
		chosen = { routeId = best.routeId, t = best.t, dir = best.dir, d = best.gap },
		reason = "ok",
		candidates = #candidates,
	}
end

-- junctionCandidates() (L6004-6023): non-trunk routes within 2.15 u of the rail point, closest sample
-- per route, kept when <= 1.7 u, sorted by distance. Empty on a trunk.
function Motion.junctionCandidates(world: World, route: Route, t: number): { Candidate }
	if route.kind == "trunk" then
		return {}
	end
	local p = world.registry:pointAt(route, t)
	local seen: { [number]: Candidate } = {}
	world.index:forEachNear(p.x, p.y, p.z, 1, function(id, st_, sx, sy, sz)
		if id == route.id then
			return nil
		end
		local other = world.registry:get(id)
		if not other or other.kind == "trunk" then
			return nil
		end
		local dx, dy, dz = sx - p.x, sy - p.y, sz - p.z
		local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
		if distance > C.junctionRadius then
			return nil
		end
		if (route.enclosure or other.enclosure) and not Enclosure.allows(route, t, other, st_) then
			return nil
		end
		local prev = seen[id]
		if not prev or distance < prev.d then
			seen[id] = { routeId = id, t = st_, d = distance }
		end
		return nil
	end)
	local out: { Candidate } = {}
	for _, c in seen do
		if Motion.canTransfer(c.d, true) then
			table.insert(out, c)
		end
	end
	table.sort(out, function(a, b)
		if a.d ~= b.d then
			return a.d < b.d
		end
		return a.routeId < b.routeId
	end)
	return out
end

-- junctionOutward(c) (L6024-6032): XZ direction from the rail point to the candidate, or the
-- candidate's tangent times its intended direction when they nearly coincide.
function Motion.junctionOutward(
	world: World,
	route: Route,
	t: number,
	railDir: number,
	cameraYaw: number,
	bodyYaw: number,
	c: Candidate
): (number, number)
	local reg = world.registry
	local other = reg:get(c.routeId) :: Route
	local p = reg:pointAt(route, t)
	local startP = reg:pointAt(other, math.max(0, c.t - C.junctionTangentDt))
	local endP = reg:pointAt(other, math.min(1, c.t + C.junctionTangentDt))
	local tx, tz = endP.x - startP.x, endP.z - startP.z
	local tl = math.sqrt(tx * tx + tz * tz)
	if tl > 0 then
		tx, tz = tx / tl, tz / tl
	end
	local target = reg:pointAt(other, c.t)
	local dx, dz = target.x - p.x, target.z - p.z
	local lenSq = dx * dx + dz * dz
	if lenSq > C.junctionOutwardLenSq then
		local l = math.sqrt(lenSq)
		return dx / l, dz / l
	end
	local intended = Motion.inward(c.t, Motion.directionFromView(world, other, c.t, cameraYaw, bodyYaw, railDir))
	return tx * intended, tz * intended
end

-- chooseRouteJunction(side) (L6033-6049): the A/D selection on non-trunk routes; cycles on repeat.
-- Returns the newly selected route id (or nil when nothing qualifies).
function Motion.chooseRouteJunction(
	world: World,
	route: Route,
	t: number,
	railDir: number,
	cameraYaw: number,
	bodyYaw: number,
	side: number,
	currentSelection: number?
): number?
	local candidates = Motion.junctionCandidates(world, route, t)
	if #candidates == 0 then
		return nil
	end
	local rx, rz = Motion.cameraRightXZ(cameraYaw)
	local choices: { { routeId: number, side: number, d: number } } = {}
	for _, c in candidates do
		local ox, oz = Motion.junctionOutward(world, route, t, railDir, cameraYaw, bodyYaw, c)
		local s = side * (rx * ox + rz * oz)
		if s > C.junctionSideMin then
			table.insert(choices, { routeId = c.routeId, side = s, d = c.d })
		end
	end
	if #choices == 0 then
		return nil
	end
	table.sort(choices, function(a, b)
		if a.side ~= b.side then
			return a.side > b.side
		end
		return a.d < b.d
	end)
	local oldIndex = 0
	for i, c in choices do
		if c.routeId == currentSelection then
			oldIndex = i
			break
		end
	end
	local pick = if oldIndex == 0 then choices[1] else choices[(oldIndex % #choices) + 1]
	return pick.routeId
end

-- takeSelectedJunction() (L6050-6061): re-validate the selection and build the enter spec.
function Motion.takeSelectedJunction(
	world: World,
	route: Route,
	t: number,
	railDir: number,
	cameraYaw: number,
	bodyYaw: number,
	selected: number?
): EnterSpec?
	if not selected then
		return nil
	end
	for _, c in Motion.junctionCandidates(world, route, t) do
		if c.routeId == selected then
			local other = world.registry:get(c.routeId) :: Route
			local dir = Motion.directionFromView(world, other, c.t, cameraYaw, bodyYaw, railDir)
			return { routeId = c.routeId, t = c.t, dir = dir, d = c.d }
		end
	end
	return nil
end

-- nearbyCanopyForks() (L4386-4393) for a trunk at parameter t.
function Motion.nearbyForks(world: World, trunk: Route, t: number): { Graph.Fork }
	local all = world.graph:forks(trunk.id)
	if #all == 0 then
		return all
	end
	local height = world.registry:pointAt(trunk, t).y
	local ahead: { Graph.Fork } = {}
	for _, f in all do
		if f.height >= height - C.forkBelow and f.height <= height + C.forkAbove then
			table.insert(ahead, f)
		end
	end
	if #ahead > 0 then
		return ahead
	end
	local near: { Graph.Fork } = {}
	for _, f in all do
		if math.abs(f.height - height) < C.forkFallback then
			table.insert(near, f)
		end
	end
	return near
end

-- chooseCanopyFork(side) (L4394-4422): pick (or cycle) a bough on the current trunk. Returns the
-- selected fork or nil. `posY` is the squirrel's y, right = cameraRightXZ.
function Motion.chooseCanopyFork(
	world: World,
	trunk: Route,
	t: number,
	posY: number,
	cameraYaw: number,
	side: number,
	pendingBranch: number?
): Graph.Fork?
	local branches = Motion.nearbyForks(world, trunk, t)
	if #branches == 0 then
		return nil
	end
	local rx, rz = Motion.cameraRightXZ(cameraYaw)
	local best: Graph.Fork? = nil
	local bestCost = math.huge
	for _, f in branches do
		local s = f.outward.x * rx + f.outward.z * rz
		if side * s > C.forkSideMin then
			-- weights are per HTML unit of height difference
			local delta = Units.u(f.height - posY)
			local cost = math.max(0, delta) * C.forkUpWeight
				+ math.abs(delta) * C.forkAbsWeight
				- math.max(0, side * s) * C.forkSideWeight
			if cost < bestCost then
				bestCost = cost
				best = f
			end
		end
	end
	if not best then
		return nil
	end
	local bySide: { Graph.Fork } = {}
	for _, f in branches do
		if side * (f.outward.x * rx + f.outward.z * rz) > C.forkSideMin then
			table.insert(bySide, f)
		end
	end
	table.sort(bySide, function(a, b)
		return math.abs(a.height - posY) < math.abs(b.height - posY)
	end)
	local currentIdx = 0
	for i, f in bySide do
		if f.branch == pendingBranch then
			currentIdx = i
			break
		end
	end
	if currentIdx == 0 then
		return best
	end
	return bySide[(currentIdx % #bySide) + 1]
end

-- takeSelectedFork(force) (L4444-4456): the enter spec onto the pending bough, or nil.
function Motion.takeFork(fork: Graph.Fork, currentRouteId: number, posY: number, force: boolean): EnterSpec?
	if fork.trunk ~= currentRouteId then
		return nil
	end
	local dist = math.abs(posY - fork.height)
	if dist > C.forkTake and not force then
		return nil
	end
	if dist > C.forkTakeForced then
		return nil
	end
	return { routeId = fork.branch, t = C.forkEnterT, dir = 1 }
end

-- forkAutoTake (L6676-6686): holding W past the pending fork takes it.
function Motion.forkAutoTake(fork: Graph.Fork, trunk: Route, before: number, after: number, fw: number): boolean
	return fw > 0
		and after * trunk.length >= fork.t * trunk.length - C.forkAutoBehind
		and before <= fork.t + C.forkAutoAheadT
end

-- sideStepToSibling(side) (L4423-4443): hop to a sibling bough near the shared trunk node.
function Motion.sideStepToSibling(world: World, branch: Route, t: number, cameraYaw: number, side: number): EnterSpec?
	if branch.kind ~= "branch" or t > C.siblingMaxT then
		return nil
	end
	local parent = world.graph:forkOf(branch.id)
	if not parent then
		return nil
	end
	local rx, rz = Motion.cameraRightXZ(cameraYaw)
	local selected: Graph.Fork? = nil
	local bestS = -math.huge
	for _, f in world.graph:forks(parent.trunk) do
		if f.branch ~= branch.id and math.abs(f.height - parent.height) < C.siblingHeight then
			local s = f.outward.x * rx + f.outward.z * rz
			if s * side > C.siblingSideMin and s * side > bestS then
				bestS = s * side
				selected = f
			end
		end
	end
	if not selected then
		return nil
	end
	return { routeId = selected.branch, t = C.siblingEnterT, dir = 1 }
end

-- Enclosed runs (Routes/Enclosure) -------------------------------------------------------------------------------

-- mouthOut(world, route, mouth): the unit vector pointing outside at a mouth: the record's `out`; else, at an end, the
-- heading of a "link" mouth's links[1] at its t (the bough it runs on to), else the route's own direction out of that
-- end, level when it has any level part. Never the body's facing.
function Motion.mouthOut(world: World, route: Route, mouth: Enclosure.Mouth): (number, number, number)
	local out = mouth.out
	if out then
		return out.x, out.y, out.z
	end
	local first = mouth.links[1]
	if mouth.opens == "link" and first then
		local target = world.registry:get(first.route)
		if target then
			local tan = world.registry:tangentAt(target, math.clamp(first.t, 1e-4, 1 - 1e-4))
			local x, z = tan.x * first.dir, tan.z * first.dir
			local h = math.sqrt(x * x + z * z)
			if h > Enclosure.C.minOutLevel then
				return x / h, 0, z / h
			end
		end
	end
	local atStart = mouth.t < 0.5
	local tan = world.registry:tangentAt(route, if atStart then 0 else 1)
	local sgn = if atStart then -1 else 1
	local x, y, z = tan.x * sgn, tan.y * sgn, tan.z * sgn
	local h = math.sqrt(x * x + z * z)
	if h > 0.3 then
		return x / h, 0, z / h
	end
	local l = math.sqrt(x * x + y * y + z * z)
	return x / l, y / l, z / l
end

-- outLevel(world, route, mouth): the mouth's `out` made level and unit, or nil when it does not lean out at least
-- Enclosure.C.minOutLevel (a data error enclosureErrors reports; no launch is made from such a mouth).
function Motion.outLevel(world: World, route: Route, mouth: Enclosure.Mouth): (number?, number?)
	local ox, _, oz = Motion.mouthOut(world, route, mouth)
	local h = math.sqrt(ox * ox + oz * oz)
	if h < Enclosure.C.minOutLevel then
		return nil, nil
	end
	return ox / h, oz / h
end

-- launchPoint(world, route, mouth): where a launch out of the mouth starts (Enclosure rule 3): the route's point at
-- the mouth, out along `out` past the opening's face (`depth`) by Enclosure.C.clear. Never inside the shell.
function Motion.launchPoint(world: World, route: Route, mouth: Enclosure.Mouth): Vec3
	local p = world.registry:pointAt(route, mouth.t)
	local ox, oy, oz = Motion.mouthOut(world, route, mouth)
	local d = mouth.depth + Enclosure.C.clear
	return Curve.vec3(p.x + ox * d, p.y + oy * d, p.z + oz * d)
end

-- the section's up by the default rule (world up squared to the line; on a stretch steeper than Enclosure.C.steep
-- the last up it had, carried along from t = 0 in 0.2-stud slices), cached per route
local sectionCache: { [Route]: { { number } } } = setmetatable({} :: any, { __mode = "k" }) :: any

local function defaultUps(world: World, route: Route): { { number } }
	local cached = sectionCache[route]
	if cached then
		return cached
	end
	local reg = world.registry
	local n = math.max(1, math.ceil(route.length / 0.2))
	local ups: { { number } } = {}
	local px, py, pz = 0, 1, 0
	for i = 0, n do
		local t = i / n
		local tan = reg:tangentAt(route, math.clamp(t, 1e-4, 1 - 1e-4))
		local tl = math.max(math.sqrt(tan.x * tan.x + tan.y * tan.y + tan.z * tan.z), 1e-9)
		local tx, ty, tz = tan.x / tl, tan.y / tl, tan.z / tl
		local bx, by, bz = 0, 1, 0
		if math.abs(ty) > Enclosure.C.steep then
			bx, by, bz = px, py, pz
		end
		local k = bx * tx + by * ty + bz * tz
		local ux, uy, uz = bx - k * tx, by - k * ty, bz - k * tz
		local ul = math.sqrt(ux * ux + uy * uy + uz * uz)
		if ul < 1e-6 then
			ux, uy, uz, ul = px, py, pz, 1
		end
		px, py, pz = ux / ul, uy / ul, uz / ul
		ups[i + 1] = { px, py, pz }
	end
	sectionCache[route] = ups
	return ups
end

export type Section = {
	tangent: Vec3, -- along the route (t increasing)
	side: Vec3, -- across the section: tangent x up
	up: Vec3, -- the body's back: headroom is measured along it; on a climb it points away from the wall
	width: number,
	headroom: number,
	crawl: boolean,
}

-- section(world, route, t): the frame and clearance of an enclosed route at t (Enclosure: `up`, `upAt`, the default
-- rule, width, height, crawl). For the drawn body (crouch where `crawl`; on a climb the belly faces -up), the camera
-- and the clearance sweep. nil off an enclosed route.
function Motion.section(world: World, route: Route, t: number): Section?
	local spec = route.enclosure
	if not spec then
		return nil
	end
	local tan = world.registry:tangentAt(route, math.clamp(t, 1e-4, 1 - 1e-4))
	local tl = math.max(math.sqrt(tan.x * tan.x + tan.y * tan.y + tan.z * tan.z), 1e-9)
	local tx, ty, tz = tan.x / tl, tan.y / tl, tan.z / tl
	local ux, uy, uz
	local authored = Enclosure.upAt(spec, t)
	if authored then
		ux, uy, uz = authored.x, authored.y, authored.z
	else
		local ups = defaultUps(world, route)
		local u = ups[math.clamp(math.floor(t * (#ups - 1) + 0.5) + 1, 1, #ups)]
		ux, uy, uz = u[1], u[2], u[3]
	end
	local k = ux * tx + uy * ty + uz * tz
	ux, uy, uz = ux - k * tx, uy - k * ty, uz - k * tz
	local ul = math.sqrt(ux * ux + uy * uy + uz * uz)
	if ul < 1e-6 then
		ux, uy, uz, ul = 0, 1, 0, 1
	end
	ux, uy, uz = ux / ul, uy / ul, uz / ul
	local sx, sy, sz = ty * uz - tz * uy, tz * ux - tx * uz, tx * uy - ty * ux
	local headroom, crawl = Enclosure.headroom(spec, t)
	return {
		tangent = Curve.vec3(tx, ty, tz),
		side = Curve.vec3(sx, sy, sz),
		up = Curve.vec3(ux, uy, uz),
		width = spec.width,
		headroom = headroom,
		crawl = crawl,
	}
end

-- enclosed(world): does the registry hold any enclosed route? (cached)
function Motion.enclosed(world: World): boolean
	local cached = world._enclosed
	if cached ~= nil then
		return cached
	end
	local any = false
	for _, route in world.registry:all() do
		if route.enclosure then
			any = true
			break
		end
	end
	world._enclosed = any
	return any
end

-- mouths(world): every mouth of every enclosed route, placed (cached; empty without enclosed routes).
function Motion.mouths(world: World): { MouthRef }
	local cached = world._mouths
	if cached then
		return cached
	end
	local list: { MouthRef } = {}
	if Motion.enclosed(world) then
		for _, route in world.registry:all() do
			local spec = route.enclosure
			if spec then
				for _, m in spec.mouths do
					local p = world.registry:pointAt(route, m.t)
					local ox, oy, oz = Motion.mouthOut(world, route, m)
					table.insert(list, {
						routeId = route.id,
						mouth = m,
						x = p.x,
						y = p.y,
						z = p.z,
						ox = ox,
						oy = oy,
						oz = oz,
						inward = if m.t <= 0 then 1 elseif m.t >= 1 then -1 else 0,
					})
				end
			end
		end
	end
	world._mouths = list
	return list
end

-- does a body at (x, y, z) moving along (moveX, moveZ) get in at this mouth (Enclosure rule 1)? Returns the level
-- distance to the mouth point, or nil.
local function intoMouth(ref: MouthRef, x: number, y: number, z: number, moveX: number, moveZ: number): number?
	local m = ref.mouth
	if m.opens == "link" then
		return nil
	end
	local dx, dz = x - ref.x, z - ref.z
	local level = math.sqrt(dx * dx + dz * dz)
	if level > m.reach or math.abs(y - ref.y) > m.rise then
		return nil
	end
	local ml = math.sqrt(moveX * moveX + moveZ * moveZ)
	if ml < 1e-6 then
		return nil
	end
	local oh = math.sqrt(ref.ox * ref.ox + ref.oz * ref.oz)
	if oh > 0.3 then
		local ox, oz = ref.ox / oh, ref.oz / oh
		-- on the outside of the mouth (or at most half a body past it) and moving in
		if dx * ox + dz * oz < -Enclosure.C.behind then
			return nil
		end
		if -(moveX * ox + moveZ * oz) / ml < Enclosure.C.intoDot then
			return nil
		end
	end
	return level
end

local function entrySpec(ref: MouthRef, x: number, y: number, z: number): EnterSpec
	local d = math.sqrt((x - ref.x) ^ 2 + (y - ref.y) ^ 2 + (z - ref.z) ^ 2)
	return { routeId = ref.routeId, t = ref.mouth.t, dir = if ref.inward ~= 0 then ref.inward else nil, d = d }
end

-- mouthEntry(world, x, y, z, moveX, moveZ): the way in for a body off the rails at (x, y, z) moving along
-- (moveX, moveZ) (Enclosure rule 1): the nearest mouth that opens ground, ledge or air, with the body within its
-- reach (level) and rise (height), not more than Enclosure.C.behind past it, and moving into it. nil when none.
function Motion.mouthEntry(world: World, x: number, y: number, z: number, moveX: number, moveZ: number): EnterSpec?
	local list = Motion.mouths(world)
	if #list == 0 then
		return nil
	end
	local best: MouthRef? = nil
	local bestD = math.huge
	for _, ref in list do
		local level = intoMouth(ref, x, y, z, moveX, moveZ)
		if level and level < bestD then
			best, bestD = ref, level
		end
	end
	if not best then
		return nil
	end
	return entrySpec(best, x, y, z)
end

-- mouthEntrySwept(world, x0, y0, z0, x1, y1, z1, moveX, moveZ): as mouthEntry for a body that flew from the first
-- point to the second in one substep (a leap or a pounce): the point of the segment nearest each mouth (level) is
-- judged, so a fast flight through a mouth's disc is not missed. The enter spec is from the body's point now.
function Motion.mouthEntrySwept(
	world: World,
	x0: number,
	y0: number,
	z0: number,
	x1: number,
	y1: number,
	z1: number,
	moveX: number,
	moveZ: number
): EnterSpec?
	local list = Motion.mouths(world)
	if #list == 0 then
		return nil
	end
	local sx, sz = x1 - x0, z1 - z0
	local ss = sx * sx + sz * sz
	local best: MouthRef? = nil
	local bestD = math.huge
	for _, ref in list do
		local f = 1
		if ss > 1e-12 then
			f = math.clamp(((ref.x - x0) * sx + (ref.z - z0) * sz) / ss, 0, 1)
		end
		local level = intoMouth(ref, x0 + sx * f, y0 + (y1 - y0) * f, z0 + sz * f, moveX, moveZ)
		if level and level < bestD then
			best, bestD = ref, level
		end
	end
	if not best then
		return nil
	end
	return entrySpec(best, x1, y1, z1)
end

-- openOnly(world): for nearestRoute off the rails: refuses every enclosed route (nil when the world has none, so
-- the search is the old one).
function Motion.openOnly(world: World): ((routeId: number, t: number) -> boolean)?
	if not Motion.enclosed(world) then
		return nil
	end
	local reg = world.registry
	return function(routeId: number, _t: number): boolean
		local r = reg:get(routeId)
		return r ~= nil and r.enclosure == nil
	end
end

-- transferFilter(world, from, fromT): for nearestRoute from a rail: what Enclosure.allows (nil when the world has
-- no enclosed route).
function Motion.transferFilter(world: World, from: Route, fromT: number): ((routeId: number, t: number) -> boolean)?
	if not Motion.enclosed(world) then
		return nil
	end
	local reg = world.registry
	return function(routeId: number, t: number): boolean
		local r = reg:get(routeId)
		return r ~= nil and Enclosure.allows(from, fromT, r, t)
	end
end

-- exitsAhead(world, route, t, dir): the authored ways off an enclosed route (Enclosure.exits: forks, part-way link
-- mouths) that A/D may pick from here: within Enclosure.C.forkAhead studs ahead along `dir`, or within
-- Enclosure.C.linkWindow behind. Empty off an enclosed route.
function Motion.exitsAhead(_world: World, route: Route, t: number, dir: number): { Enclosure.Exit }
	local spec = route.enclosure
	local out: { Enclosure.Exit } = {}
	if not spec then
		return out
	end
	for _, e in Enclosure.exits(spec, route.length) do
		local ahead = (e.t - t) * route.length * (if dir < 0 then -1 else 1)
		if ahead <= Enclosure.C.forkAhead and ahead >= -Enclosure.C.linkWindow then
			table.insert(out, e)
		end
	end
	return out
end

-- exitOutward(world, route, e): the level direction from the exit's point on the route toward where it leads (the
-- target's point, or the mouth's `out`, or the target's heading when the two nearly coincide): what A or D is
-- judged against.
function Motion.exitOutward(world: World, route: Route, e: Enclosure.Exit): (number, number)
	local reg = world.registry
	local p = reg:pointAt(route, e.t)
	local target = reg:get(e.route)
	if not target then
		return 0, 0
	end
	local q = reg:pointAt(target, e.toT)
	local dx, dz = q.x - p.x, q.z - p.z
	local l = math.sqrt(dx * dx + dz * dz)
	if l > 0.5 then
		return dx / l, dz / l
	end
	local m = e.mouth
	if m then
		local o = m.out
		if o then
			local h = math.sqrt(o.x * o.x + o.z * o.z)
			if h > 1e-6 then
				return o.x / h, o.z / h
			end
		end
	end
	local tan = reg:tangentAt(target, math.clamp(e.toT, 1e-4, 1 - 1e-4))
	local tx, tz = tan.x * e.dir, tan.z * e.dir
	local tl = math.sqrt(tx * tx + tz * tz)
	if tl > 1e-6 then
		return tx / tl, tz / tl
	end
	return 0, 0
end

-- chooseExit(world, route, t, dir, cameraYaw, side, current): A/D on an enclosed route: the exit ahead on that side
-- of the view (cycling on repeat, as chooseRouteJunction), or nil.
function Motion.chooseExit(
	world: World,
	route: Route,
	t: number,
	dir: number,
	cameraYaw: number,
	side: number,
	current: number?
): Enclosure.Exit?
	local rx, rz = Motion.cameraRightXZ(cameraYaw)
	local choices: { { e: Enclosure.Exit, s: number } } = {}
	for _, e in Motion.exitsAhead(world, route, t, dir) do
		local ox, oz = Motion.exitOutward(world, route, e)
		local s = side * (rx * ox + rz * oz)
		if s > C.junctionSideMin then
			table.insert(choices, { e = e, s = s })
		end
	end
	if #choices == 0 then
		return nil
	end
	table.sort(choices, function(a, b)
		if a.s ~= b.s then
			return a.s > b.s
		end
		return a.e.t < b.e.t
	end)
	local oldIndex = 0
	for i, c in choices do
		if c.e.route == current then
			oldIndex = i
			break
		end
	end
	return (if oldIndex == 0 then choices[1] else choices[(oldIndex % #choices) + 1]).e
end

-- enclosureErrors(registry, known?): what the data of the registry's enclosed runs gets wrong that only the curves
-- show: a link (a mouth's, an end's or a fork's) to a route that is not there (unless `known` lists it: a route of
-- another registry) or farther from where it is taken than a transfer reaches (C.enterMaxGap); a mouth whose `out`
-- (as resolved: Motion.mouthOut) does not lean out at least Enclosure.C.minOutLevel (a launch from it would have no
-- heading: a vertical shaft's top needs an `out`); a ground mouth within C.walkInReach less its reach of a trunk the
-- walk-in grab takes (that trunk would take the squirrel first). Empty when the data is sound. For the compilers.
function Motion.enclosureErrors(registry: Registry.Registry, known: { [number]: boolean }?): { string }
	local errs: { string } = {}
	local world = { registry = registry } :: any
	local feet: { TrunkFoot } = {}
	local trunks: { Route } = {}
	for _, r in registry:all() do
		if r.kind == "trunk" then
			table.insert(trunks, r)
			if not r.flags.autoGrabExcluded then
				local f = registry:foot(r)
				table.insert(feet, { id = r.id, x = f.x, y = f.y, z = f.z, isPole = r.flags.isPole })
			end
		end
	end
	for _, route in registry:all() do
		local spec = route.enclosure
		if not spec then
			continue
		end
		local function check(fromT: number, link: Enclosure.Link, what: string)
			local target = registry:get(link.route)
			if not target then
				if not (known and known[link.route]) then
					table.insert(errs, `route {route.id}: {what} links route {link.route}, which is not there`)
				end
				return
			end
			local a, b = registry:pointAt(route, fromT), registry:pointAt(target, link.t)
			local gap = math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2)
			if gap > C.enterMaxGap then
				table.insert(
					errs,
					`route {route.id}: {what} to route {link.route} is {gap} studs, beyond a transfer ({C.enterMaxGap})`
				)
			end
		end
		if spec.atStart then
			check(0, spec.atStart, "atStart")
		end
		if spec.atEnd then
			check(1, spec.atEnd, "atEnd")
		end
		for i, f in spec.forks do
			check(f.t, { route = f.route, t = f.toT, dir = f.dir }, `fork {i}`)
		end
		for i, m in spec.mouths do
			for _, l in m.links do
				check(m.t, l, `mouth {i}`)
			end
			local ox, _, oz = Motion.mouthOut(world, route, m)
			if math.sqrt(ox * ox + oz * oz) < Enclosure.C.minOutLevel then
				table.insert(
					errs,
					`route {route.id}: mouth {i} has no level way out (give it an out that leans out at least {Enclosure.C.minOutLevel})`
				)
			end
			-- a launch must start outside the bark of any trunk the mouth is cut in (its `depth`)
			local lp = Motion.launchPoint(world, route, m)
			for _, trunk in trunks do
				local a, b = registry:pointAt(trunk, 0), registry:pointAt(trunk, 1)
				if lp.y < math.min(a.y, b.y) or lp.y > math.max(a.y, b.y) then
					continue
				end
				local lo, hi = 0, 1
				local rising = b.y >= a.y
				for _ = 1, 30 do
					local mid = (lo + hi) / 2
					if (registry:pointAt(trunk, mid).y < lp.y) == rising then
						lo = mid
					else
						hi = mid
					end
				end
				local q = registry:pointAt(trunk, (lo + hi) / 2)
				local d = math.sqrt((lp.x - q.x) ^ 2 + (lp.z - q.z) ^ 2)
				if d < trunk.surfaceRadius then
					table.insert(
						errs,
						`route {route.id}: mouth {i}'s launch point is {d} studs from trunk {trunk.id}'s axis, inside its bark ({trunk.surfaceRadius}): give the mouth a depth`
					)
				end
			end
			if m.opens == "ground" then
				local p = registry:pointAt(route, m.t)
				for _, foot in feet do
					local d = math.sqrt((p.x - foot.x) ^ 2 + (p.z - foot.z) ^ 2)
					if d < C.walkInReach - m.reach and math.abs(p.y - foot.y) <= C.maxRise then
						table.insert(
							errs,
							`route {route.id}: ground mouth {i} is {d} studs from trunk {foot.id}'s foot, inside its walk-in grab: put it at least {C.walkInReach - m.reach} out`
						)
					end
				end
			end
		end
	end
	return errs
end

-- visualPose (§14, L6769-6790): where the mesh sits for a squirrel on `route` at `t`. The route
-- centreline is the physics position; trunks push the body out along the surface normal, boughs and
-- wires lift it. trunkNormal (XZ unit) is the bark normal chosen when the trunk was entered.
function Motion.visualPose(
	world: World,
	route: Route,
	t: number,
	pos: Vec3,
	trunkNormalX: number?,
	trunkNormalZ: number?
): Vec3
	local kind = route.kind
	if kind == "trunk" then
		local sx, sz
		if route.flags.fixedSurfaceZ then
			sx, sz = 0, 1
		else
			sx, sz = trunkNormalX or 0, trunkNormalZ or 1
		end
		local r = if route.surfaceRadius > 0 then route.surfaceRadius else C.visualDefaultR
		local tapered
		if route.flags.isGiant then
			tapered = math.max(C.visualGiantMinR, r / 0.95 - C.visualGiantTaper * t)
		else
			tapered = math.max(C.visualTrunkMinR, r * (1 - C.visualTrunkTaper * t))
		end
		local offset
		if route.flags.fixedSurfaceZ or route.flags.isPole then
			offset = r + C.visualTrunkFixedPad
		else
			offset = tapered + C.visualTrunkPad
		end
		return Curve.vec3(pos.x + sx * offset, pos.y, pos.z + sz * offset)
	elseif kind == "branch" or kind == "bridge" or kind == "lookout" then
		local lift = route.visualOffset or (if kind == "lookout" then C.visualLookoutLift else C.visualBranchLift)
		local x, z = pos.x, pos.z
		local clearance = route.trunkClearance
		if kind == "branch" and clearance and t < C.visualClearanceT then
			local start = world.registry:pointAt(route, 0)
			local ahead = world.registry:pointAt(route, C.visualClearanceSampleT)
			local dx, dz = ahead.x - start.x, ahead.z - start.z
			local l = math.sqrt(dx * dx + dz * dz)
			if l > 0 then
				local k = (clearance + C.visualClearancePad) * (1 - t / C.visualClearanceT) ^ 2
				x += dx / l * k
				z += dz / l * k
			end
		end
		return Curve.vec3(x, pos.y + lift, z)
	elseif kind == "wire" then
		return Curve.vec3(pos.x, pos.y + C.visualWireLift, pos.z)
	end
	return Curve.vec3(pos.x, pos.y, pos.z)
end

-- turnToward(old, desired, rate, dt) (L6570-6572): exponential approach along the short way round.
function Motion.turnToward(old: number, desired: number, rate: number, dt: number): number
	return old + math.atan2(math.sin(desired - old), math.cos(desired - old)) * (1 - math.exp(-rate * dt))
end

return Motion
