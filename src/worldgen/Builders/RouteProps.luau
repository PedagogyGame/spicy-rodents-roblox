--!strict
-- ServerScriptService.Server.WorldGen.Builders.RouteProps
-- Geometry drawn around harvested route curves (BUILD_PLAN §4.4 #7 "trees drawn around their route
-- curves"): whole trees (Builders/Trees: tapered bark and dense leafy crowns with clear climbing
-- tunnels), telephone poles seated in the ground with a crossarm, braces and insulators, downspouts and
-- ladders carried down to whatever they stand on, wires as Beams between Attachments on an anchor part
-- (the harvested sag), fence and trampoline rails (fence panels and parapets down to the ground or deck,
-- an enclosure of posts and net under the trampoline ring), masts and pennants under the Quay bunting
-- and hangers under the bridge chains. Which routes are drawn, and with which LevelOfDetail and
-- streaming mode, is data (lot_types.json `routeProps`). Every other route (roofs, gutters, lookouts)
-- is checked against the lot massing by RouteCheck. The routes themselves never move: every visual
-- keeps the route's centreline on its bark, pole, pipe or rail (RouteCheck still passes).
-- Interface: classify(route, props) -> look?; plans(routes, props, Curve, heightAt, groundAt?) ->
--   ({ BuildPlan }, looks); groundAt(x, z, maxY?) -> (y, onPart) is Surface.at (terrain if nil).
-- Pure.

local Geometry = require("../Geometry")
local Palette = require("../Palette")
local Spec = require("../Spec")
local Trees = require("./Trees")

local RouteProps = {}

local LOOK = {
	bark = { color = Palette.BARK, material = "Wood" },
	pole = { color = { 92, 74, 58 }, material = "Wood" },
	pipe = { color = { 140, 140, 140 }, material = "Metal" },
	fence = { color = { 150, 120, 90 }, material = "WoodPlanks" },
	wire = { color = { 40, 40, 40 }, material = "SmoothPlastic" },
}
local STONE = Palette.hex("#d1c7ae")
local INSULATOR = { 92, 128, 120 }
local BUNTING = { Palette.hex("#af5949"), Palette.hex("#dfd1a8"), Palette.hex("#405b51"), Palette.hex("#c9a24a") }

local SIMPLIFY = 0.3 -- studs: chord tolerance when turning a curve into straight pieces
local RAIL_R = 0.25
local FENCE_MAX_H = 5

export type Route = {
	id: number,
	name: string,
	kind: string,
	generator: string?,
	points: { { number } },
	surfaceRadius: number,
	length: number,
	visualOffset: number?,
}

local function generatorName(r: Route): string
	return string.match(r.generator or "", "^([^@]+)") or ""
end

-- Which routeProps entry draws this route ("tree", "limb", "pole", "wire", "fence", "pipe"), or nil.
function RouteProps.classify(r: Route, props: { [string]: any }): string?
	local gen = generatorName(r)
	local order = { "tree", "limb", "pole", "wire", "fence", "pipe" }
	for _, look in order do
		local p = props[look]
		if p then
			local ok = true
			if p.generators then
				ok = table.find(p.generators, gen) ~= nil
			end
			if ok and p.names then
				ok = false
				for _, n in p.names do
					ok = ok or string.find(r.name, n, 1, true) ~= nil
				end
			end
			if ok and p.kinds then
				ok = table.find(p.kinds, r.kind) ~= nil
			end
			if ok and p.maxRadiusU then
				ok = r.surfaceRadius <= p.maxRadiusU * Spec.SPU + 1e-9
			end
			if ok then
				return look
			end
		end
	end
	return nil
end

-- Curve -> polyline with at most SIMPLIFY studs of chord error (Catmull-Rom through the points).
local function polyline(r: Route, Curve: any): { { number } }
	local pts = r.points
	if #pts == 2 then
		return { pts[1], pts[2] }
	end
	local vecs = {}
	for _, p in pts do
		table.insert(vecs, Curve.vec3(p[1], p[2], p[3]))
	end
	local curve = Curve.new(vecs)
	local n = math.clamp(math.ceil(r.length / 1.5), 4, 80)
	local samples = curve:getSpacedPoints(n)
	local out = { { samples[1].x, samples[1].y, samples[1].z } }
	local i = 1
	while i < #samples do
		local j = i + 1
		while j + 1 <= #samples do
			local a, b = samples[i], samples[j + 1]
			local ok = true
			for k = i + 1, j do
				local s = samples[k]
				if Geometry.segmentDistance({ a.x, a.y, a.z }, { b.x, b.y, b.z }, { s.x, s.y, s.z }) > SIMPLIFY then
					ok = false
					break
				end
			end
			if not ok then
				break
			end
			j += 1
		end
		table.insert(out, { samples[j].x, samples[j].y, samples[j].z })
		i = j
	end
	return out
end

local ORIGIN = Geometry.frame(0, 0, 0, 0)

-- One cylinder from a to b (axis local X), radius r, lengthened by `ext` studs at each end.
local function cyl(list: Spec.PartList, name: string, a: { number }, b: { number }, r: number, ext: number, o: Spec.Opts)
	local d = { b[1] - a[1], b[2] - a[2], b[3] - a[3] }
	local len = math.sqrt(d[1] * d[1] + d[2] * d[2] + d[3] * d[3])
	if len <= 1e-4 then
		return
	end
	local yaw, roll = Geometry.axisAngles(d)
	local opts = table.clone(o)
	opts.yaw, opts.roll, opts.shape = yaw, roll, "Cylinder"
	list:add(ORIGIN, name, (a[1] + b[1]) / 2, (a[2] + b[2]) / 2, (a[3] + b[3]) / 2, len + 2 * ext, r * 2, r * 2, opts)
end

local function cylinders(
	list: Spec.PartList,
	prefix: string,
	line: { { number } },
	radius: number,
	look: string,
	role: string
)
	local L = LOOK[look]
	for k = 1, #line - 1 do
		cyl(list, `{prefix}_{k}`, line[k], line[k + 1], radius, radius * 0.25, {
			color = L.color,
			material = L.material,
			role = role,
		})
	end
end

local function newPlan(
	id: string,
	look: string,
	props: { [string]: any },
	attrs: { [string]: any },
	list: Spec.PartList
): Spec.BuildPlan
	local p = props[look]
	return {
		kind = "props",
		id = id,
		category = look,
		lod = p.lod,
		streaming = p.streaming,
		attributes = attrs,
		parts = list.parts,
		extras = list.extras,
	}
end

-- The yaw that lays a crossarm (local X) square to the first wire leaving the pole top, or 0.
local function armYaw(top: { number }, wires: { Route }): number
	for _, w in wires do
		for _, e in { 1, #w.points } do
			local p = w.points[e]
			if (p[1] - top[1]) ^ 2 + (p[3] - top[3]) ^ 2 < 36 and math.abs(p[2] - top[2]) < 6 then
				local q = w.points[if e == 1 then 2 else #w.points - 1]
				local dx, dz = q[1] - p[1], q[3] - p[3]
				if dx * dx + dz * dz > 1e-6 then
					return math.atan2(-dx, -dz) -- the arm's length (local X) is then across the wire
				end
			end
		end
	end
	return 0
end

-- Crossarm with two braces and four insulators below the pole top; a pin insulator on the top where the
-- harvested wire meets the pole; a transformer can on every fourth pole.
function RouteProps.crossarm(list: Spec.PartList, pole: Route, wires: { Route })
	local top = pole.points[#pole.points]
	local bottom = pole.points[1]
	if top[2] < bottom[2] then
		top, bottom = bottom, top
	end
	local yaw = armYaw(top, wires)
	local r = pole.surfaceRadius
	local armY = top[2] - 2.2
	local L = 11
	local wood = { color = LOOK.pole.color, material = "Wood", canCollide = false, role = "Post" }
	list:add(ORIGIN, "Crossarm", top[1], armY, top[3], L, 0.7, 0.7, {
		yaw = yaw,
		color = LOOK.pole.color,
		material = "Wood",
		canCollide = false,
		role = "Post",
	})
	local ax, az = math.cos(yaw), -math.sin(yaw) -- the arm's local X in world XZ
	for k, s in { -1, 1 } do
		-- diagonal brace from the pole 3 studs below the arm out to 3 studs along it
		local a = { top[1] + ax * s * r, armY - 3, top[3] + az * s * r }
		local b = { top[1] + ax * s * 3.2, armY - 0.3, top[3] + az * s * 3.2 }
		cyl(list, `Brace{k}`, a, b, 0.16, 0, wood)
	end
	local i = 0
	for _, off in { -4.8, -2.2, 2.2, 4.8 } do
		i += 1
		local x, z = top[1] + ax * off, top[3] + az * off
		cyl(list, `Insulator{i}`, { x, armY + 0.35, z }, { x, armY + 1.25, z }, 0.28, 0, {
			color = INSULATOR,
			material = "Glass",
			canCollide = false,
			castShadow = false,
			role = "Post",
		})
	end
	cyl(list, "TopInsulator", { top[1], top[2] - 0.2, top[3] }, { top[1], top[2] + 0.75, top[3] }, 0.3, 0, {
		color = INSULATOR,
		material = "Glass",
		canCollide = false,
		castShadow = false,
		role = "Post",
	})
	if pole.id % 4 == 0 then
		local x, z = top[1] - az * (r + 1.1), top[3] + ax * (r + 1.1)
		cyl(list, "Transformer", { x, armY - 8, z }, { x, armY - 4.2, z }, 1.05, 0, {
			color = { 120, 124, 126 },
			material = "Metal",
			canCollide = false,
			role = "Post",
		})
	end
end

local function isLadder(r: Route): boolean
	return string.find(string.lower(r.name), "ladder", 1, true) ~= nil
end

-- One BuildPlan per tree (trunk), pole, wire, pipe and fence. `Curve` is Routes/Curve (passed in so
-- this module needs no cross-root require); heightAt(x, z) is World/Height.at in studs; groundAt is
-- Surface.at (paving, decks, plates and roofs included).
function RouteProps.plans(
	routes: { Route },
	props: { [string]: any },
	Curve: any,
	heightAt: (number, number) -> number,
	groundAtIn: ((number, number, number?) -> (number, boolean))?
): ({ Spec.BuildPlan }, { [number]: string })
	local groundAt: (number, number, number?) -> (number, boolean) = groundAtIn
		or function(x: number, z: number, _maxY: number?): (number, boolean)
			return heightAt(x, z), false
		end
	local looks: { [number]: string } = {}
	local trunks: { Route } = {}
	local byLook: { [string]: { Route } } = { tree = {}, limb = {}, pole = {}, wire = {}, pipe = {}, fence = {} }
	for _, r in routes do
		local look = RouteProps.classify(r, props)
		if look then
			looks[r.id] = look
			table.insert(byLook[look], r)
			if look == "tree" and r.kind == "trunk" then
				table.insert(trunks, r)
			end
		end
	end
	local out: { Spec.BuildPlan } = {}

	-- trees: every tree-family route joins the trunk whose foot is nearest its own first point; a
	-- stand-alone limb (estate oak living bridges, park watch perches) that starts on a trunk joins it
	local members: { [number]: { Route } } = {}
	for _, t in trunks do
		members[t.id] = {}
	end
	local function nearestTrunk(p: { number }): (Route?, number)
		local best, bestD = nil, math.huge
		for _, t in trunks do
			local f = t.points[1]
			local dd = (f[1] - p[1]) ^ 2 + (f[3] - p[3]) ^ 2
			if dd < bestD then
				best, bestD = t, dd
			end
		end
		return best, math.sqrt(bestD)
	end
	for _, r in byLook.tree do
		local best = nearestTrunk(r.points[1])
		if best then
			table.insert(members[best.id], r)
		end
	end
	local loneLimbs: { Route } = {}
	for _, r in byLook.limb do
		local p = r.points[1]
		local t, d = nearestTrunk(p)
		local top = if t then t.points[#t.points] else nil
		if t and top and d < 8 and p[2] <= top[2] + 6 then
			table.insert(members[t.id], r)
		else
			table.insert(loneLimbs, r)
		end
	end
	for _, t in trunks do
		local list = Spec.list()
		local ms: { Trees.Member } = {}
		for _, r in members[t.id] do
			table.insert(ms, { route = r, line = polyline(r, Curve) })
		end
		local leaves = Trees.build(list, t, ms, { groundAt = groundAt })
		table.insert(
			out,
			newPlan(
				`Tree_{t.id}`,
				"tree",
				props,
				{ TrunkRoute = t.id, Name = t.name, Routes = #members[t.id], LeafClusters = leaves },
				list
			)
		)
	end

	for _, r in loneLimbs do
		local list = Spec.list()
		cylinders(list, "Limb", polyline(r, Curve), 1.1, "bark", "Limb")
		table.insert(out, newPlan(`Limb_{r.id}`, "limb", props, { Route = r.id }, list))
	end
	for _, r in byLook.pole do
		local list = Spec.list()
		local line = polyline(r, Curve)
		local foot = line[1]
		if line[#line][2] < foot[2] then
			foot = line[#line]
		end
		-- seated: the pole runs from 1.5 studs into the ground up to the route's top
		local g = groundAt(foot[1], foot[3], foot[2] + 0.5)
		local seat = { foot[1], math.min(g, foot[2]) - 1.5, foot[3] }
		local topP = if line[#line][2] >= line[1][2] then line[#line] else line[1]
		cyl(list, "Pole_1", seat, topP, r.surfaceRadius, 0, {
			color = LOOK.pole.color,
			material = "Wood",
			role = "Post",
		})
		RouteProps.crossarm(list, r, byLook.wire)
		table.insert(out, newPlan(`Pole_{r.id}`, "pole", props, { Route = r.id }, list))
	end
	for _, r in byLook.pipe do
		local list = Spec.list()
		local line = polyline(r, Curve)
		local foot = if line[1][2] <= line[#line][2] then line[1] else line[#line]
		local g = groundAt(foot[1], foot[3], foot[2] + 0.25)
		if isLadder(r) then
			-- two wooden rails either side of the route (following its polyline) and rungs every 1.4 studs
			local topP = if foot == line[1] then line[#line] else line[1]
			local dxz = { topP[1] - foot[1], topP[3] - foot[3] }
			local yaw = if dxz[1] * dxz[1] + dxz[2] * dxz[2] > 1 then math.atan2(dxz[1], dxz[2]) else 0
			local sx, sz = math.cos(yaw), -math.sin(yaw)
			local w = 1.1
			local wood = { color = { 120, 92, 66 }, material = "Wood", role = "Pipe" }
			local rails = table.clone(line)
			if foot == line[1] then
				table.insert(rails, 1, { foot[1], g - 0.3, foot[3] })
			else
				table.insert(rails, { foot[1], g - 0.3, foot[3] })
			end
			for k, s in { -1, 1 } do
				for j = 1, #rails - 1 do
					local a, b = rails[j], rails[j + 1]
					cyl(list, `Rail{k}_{j}`, { a[1] + sx * s * w, a[2], a[3] + sz * s * w }, {
						b[1] + sx * s * w,
						b[2],
						b[3] + sz * s * w,
					}, 0.22, 0.15, wood)
				end
			end
			local c = 0
			for j = 1, #rails - 1 do
				local a, b = rails[j], rails[j + 1]
				local seg = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2 + (b[3] - a[3]) ^ 2)
				local n = math.floor(seg / 1.4)
				for k = 1, n do
					local f = k / (n + 1)
					local x, y, z = a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, a[3] + (b[3] - a[3]) * f
					c += 1
					cyl(list, `Rung{c}`, { x - sx * w, y, z - sz * w }, { x + sx * w, y, z + sz * w }, 0.14, 0.1, {
						color = { 120, 92, 66 },
						material = "Wood",
						canCollide = false,
						role = "Pipe",
					})
				end
			end
		else
			cylinders(list, "Pipe", line, r.surfaceRadius, "pipe", "Pipe")
			if foot[2] - g > 0.05 then
				-- carry the downspout down to the ground (or deck, roof) it stands on, with a shoe
				cyl(list, "PipeFoot", { foot[1], g + 0.6, foot[3] }, foot, r.surfaceRadius, 0, {
					color = LOOK.pipe.color,
					material = "Metal",
					canCollide = false,
					role = "Pipe",
				})
			end
			cyl(list, "Shoe", { foot[1], math.min(g, foot[2]) + 0.35, foot[3] }, {
				foot[1] + 0.9,
				math.min(g, foot[2]) + 0.15,
				foot[3],
			}, r.surfaceRadius * 1.05, 0.1, {
				color = LOOK.pipe.color,
				material = "Metal",
				canCollide = false,
				castShadow = false,
				role = "Pipe",
			})
		end
		table.insert(out, newPlan(`Pipe_{r.id}`, "pipe", props, { Route = r.id }, list))
	end
	for _, r in byLook.fence do
		local list = Spec.list()
		local line = polyline(r, Curve)
		local parapet = string.find(string.lower(r.name), "parapet", 1, true) ~= nil
		local railColor = if parapet then STONE else LOOK.fence.color
		for k = 1, #line - 1 do
			cyl(list, `Rail_{k}`, line[k], line[k + 1], if parapet then 0.45 else RAIL_R, RAIL_R, {
				color = railColor,
				material = if parapet then "Limestone" else LOOK.fence.material,
				role = "Rail",
			})
		end
		if r.kind == "fence" then
			for k = 1, #line - 1 do
				local a, b = line[k], line[k + 1]
				local mx, mz = (a[1] + b[1]) / 2, (a[3] + b[3]) / 2
				local top = (a[2] + b[2]) / 2 - RAIL_R
				local ground = groundAt(mx, mz, top - 0.3)
				local h = math.clamp(top - ground, 0.3, if parapet then 4 else FENCE_MAX_H)
				local dx, dz = b[1] - a[1], b[3] - a[3]
				local len = math.sqrt(dx * dx + dz * dz)
				if len > 1e-3 then
					list:add(ORIGIN, `Panel_{k}`, mx, top - h / 2, mz, if parapet then 1.2 else 0.3, h, len + 0.05, {
						yaw = math.atan2(-dx, -dz),
						color = if parapet then STONE else LOOK.fence.color,
						material = if parapet then "Limestone" else LOOK.fence.material,
						role = "Fence",
					})
				end
			end
		else
			-- trampoline guardrail: an enclosure of padded posts down to the frame and a light net
			local n = #line - 1
			local every = math.max(1, math.floor(n / 8))
			local posts = 0
			for k = 1, n, every do
				local a = line[k]
				local ground = groundAt(a[1], a[3], a[2] - 0.5)
				posts += 1
				cyl(list, `NetPost{posts}`, { a[1], ground - 0.2, a[3] }, a, 0.32, 0, {
					color = { 52, 58, 70 },
					material = "Metal",
					canCollide = false,
					role = "Post",
				})
			end
			for k = 1, n do
				local a, b = line[k], line[k + 1]
				local mx, mz = (a[1] + b[1]) / 2, (a[3] + b[3]) / 2
				local top = (a[2] + b[2]) / 2
				local ground = groundAt(mx, mz, top - 0.5)
				local h = top - ground - 0.4
				local dx, dz = b[1] - a[1], b[3] - a[3]
				local len = math.sqrt(dx * dx + dz * dz)
				if len > 1e-3 and h > 0.5 then
					list:add(ORIGIN, `Net_{k}`, mx, ground + 0.4 + h / 2, mz, 0.1, h, len + 0.05, {
						yaw = math.atan2(-dx, -dz),
						color = { 40, 44, 52 },
						material = "Fabric",
						transparency = 0.6,
						canCollide = false,
						canQuery = false,
						castShadow = false,
						role = "Trim",
					})
				end
			end
		end
		table.insert(out, newPlan(`Fence_{r.id}`, "fence", props, { Route = r.id }, list))
	end
	for _, r in byLook.wire do
		local list = Spec.list()
		local line = polyline(r, Curve)
		local o = line[1]
		list:add(
			ORIGIN,
			"Anchor",
			o[1],
			o[2],
			o[3],
			0.2,
			0.2,
			0.2,
			{ canCollide = false, transparency = 1, role = "Anchor" }
		)
		for k, p in line do
			list:extra({
				kind = "Attachment",
				part = "Anchor",
				name = `A{k}`,
				offset = { p[1] - o[1], p[2] - o[2], p[3] - o[3] },
			})
		end
		for k = 1, #line - 1 do
			list:extra({
				kind = "Beam",
				part = "Anchor",
				name = `Wire{k}`,
				a = `A{k}`,
				b = `A{k + 1}`,
				p0 = line[k],
				p1 = line[k + 1],
				width = 0.15,
				color = LOOK.wire.color,
			})
		end
		local lname = string.lower(r.name)
		if string.find(lname, "bunting", 1, true) then
			-- a mast under the river-side end (the other end is on a facade) and pennants along the line
			local e = line[1]
			local ground = groundAt(e[1], e[3], e[2])
			if e[2] - ground > 3 then
				cyl(list, "Mast", { e[1], ground - 0.5, e[3] }, { e[1], e[2] + 1.2, e[3] }, 0.35, 0, {
					color = { 52, 58, 60 },
					material = "Metal",
					role = "Post",
				})
			end
			for k = 2, #line - 1, 2 do
				local p = line[k]
				local q = line[k + 1]
				list:add(ORIGIN, `Pennant{k}`, p[1], p[2] - 1.1, p[3], 0.08, 1.9, 1.5, {
					yaw = math.atan2(-(q[1] - p[1]), -(q[3] - p[3])),
					color = BUNTING[(k // 2 + r.id) % #BUNTING + 1],
					material = "Fabric",
					canCollide = false,
					canQuery = false,
					castShadow = false,
					role = "Trim",
				})
			end
		elseif string.find(lname, "suspension", 1, true) then
			-- hangers from the chain down to the deck
			local n = 0
			for k = 2, #line - 1 do
				local p = line[k]
				local deck = groundAt(p[1], p[3], p[2] - 1)
				if p[2] - deck > 2.5 and p[2] - deck < 60 then
					n += 1
					cyl(list, `Hanger{n}`, { p[1], deck, p[3] }, p, 0.14, 0, {
						color = Palette.hex("#4e7c87"),
						material = "Metal",
						canCollide = false,
						role = "Post",
					})
				end
			end
		end
		table.insert(out, newPlan(`Wire_{r.id}`, "wire", props, { Route = r.id }, list))
	end
	return out, looks
end

return RouteProps
