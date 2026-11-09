--!strict
-- ServerScriptService.Server.WorldGen.Builders.RouteProps
-- Geometry drawn around harvested route curves (BUILD_PLAN §4.4 #7 "trees drawn around their route
-- curves"): tree trunks and boughs as cylinders grouped per tree, telephone poles, downspouts and
-- ladders as pipes, wires as Beams between Attachments on an anchor part, fence and trampoline rails
-- (with panels to the ground for fences). Which routes are drawn, and with which LevelOfDetail and
-- streaming mode, is data (lot_types.json `routeProps`). Every other route (roofs, gutters, lookouts)
-- is checked against the lot massing by RouteCheck.
-- Interface: classify(route, props) -> look?; plans(routes, props, heightAt) -> { BuildPlan }
-- Pure.

local Geometry = require("../Geometry")
local Spec = require("../Spec")

local RouteProps = {}

local LOOK = {
	bark = { color = { 106, 84, 62 }, material = "Wood" },
	pole = { color = { 92, 74, 58 }, material = "Wood" },
	pipe = { color = { 140, 140, 140 }, material = "Metal" },
	fence = { color = { 150, 120, 90 }, material = "WoodPlanks" },
	wire = { color = { 40, 40, 40 }, material = "SmoothPlastic" },
}

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
}

local function generatorName(r: Route): string
	return string.match(r.generator or "", "^([^@]+)") or ""
end

-- Which routeProps entry draws this route ("tree", "pole", "wire", "pipe", "fence"), or nil.
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

local function cylinders(list: Spec.PartList, prefix: string, line: { { number } }, radius: number, look: string, role: string)
	local L = LOOK[look]
	for k = 1, #line - 1 do
		local a, b = line[k], line[k + 1]
		local d = { b[1] - a[1], b[2] - a[2], b[3] - a[3] }
		local len = math.sqrt(d[1] * d[1] + d[2] * d[2] + d[3] * d[3])
		if len > 1e-4 then
			local yaw, roll = Geometry.axisAngles(d)
			list:add(ORIGIN, `{prefix}_{k}`, (a[1] + b[1]) / 2, (a[2] + b[2]) / 2, (a[3] + b[3]) / 2, len + radius * 0.5, radius * 2, radius * 2, {
				yaw = yaw,
				roll = roll,
				shape = "Cylinder",
				color = L.color,
				material = L.material,
				role = role,
			})
		end
	end
end

local function newPlan(id: string, look: string, props: { [string]: any }, attrs: { [string]: any }, list: Spec.PartList): Spec.BuildPlan
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

-- One BuildPlan per tree (trunk), pole, wire, pipe and fence. `Curve` is Routes/Curve (passed in so
-- this module needs no cross-root require); heightAt(x, z) is World/Height.at in studs.
function RouteProps.plans(routes: { Route }, props: { [string]: any }, Curve: any, heightAt: (number, number) -> number): ({ Spec.BuildPlan }, { [number]: string })
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

	-- trees: every tree-family route joins the trunk whose foot is nearest its own first point
	local members: { [number]: { Route } } = {}
	for _, t in trunks do
		members[t.id] = {}
	end
	for _, r in byLook.tree do
		local best, bestD = nil, math.huge
		local p = r.points[1]
		for _, t in trunks do
			local f = t.points[1]
			local dd = (f[1] - p[1]) ^ 2 + (f[3] - p[3]) ^ 2
			if dd < bestD then
				best, bestD = t, dd
			end
		end
		if best then
			table.insert(members[best.id], r)
		end
	end
	for _, t in trunks do
		local list = Spec.list()
		for _, r in members[t.id] do
			cylinders(list, `R{r.id}`, polyline(r, Curve), r.surfaceRadius, "bark", "Limb")
		end
		table.insert(out, newPlan(`Tree_{t.id}`, "tree", props, { TrunkRoute = t.id, Name = t.name, Routes = #members[t.id] }, list))
	end

	for _, r in byLook.limb do
		local list = Spec.list()
		cylinders(list, "Limb", polyline(r, Curve), r.surfaceRadius, "bark", "Limb")
		table.insert(out, newPlan(`Limb_{r.id}`, "limb", props, { Route = r.id }, list))
	end
	for _, r in byLook.pole do
		local list = Spec.list()
		cylinders(list, "Pole", polyline(r, Curve), r.surfaceRadius, "pole", "Post")
		table.insert(out, newPlan(`Pole_{r.id}`, "pole", props, { Route = r.id }, list))
	end
	for _, r in byLook.pipe do
		local list = Spec.list()
		cylinders(list, "Pipe", polyline(r, Curve), r.surfaceRadius, "pipe", "Pipe")
		table.insert(out, newPlan(`Pipe_{r.id}`, "pipe", props, { Route = r.id }, list))
	end
	for _, r in byLook.fence do
		local list = Spec.list()
		local line = polyline(r, Curve)
		cylinders(list, "Rail", line, RAIL_R, "fence", "Rail")
		if r.kind == "fence" then
			for k = 1, #line - 1 do
				local a, b = line[k], line[k + 1]
				local mx, mz = (a[1] + b[1]) / 2, (a[3] + b[3]) / 2
				local top = (a[2] + b[2]) / 2 - RAIL_R
				local ground = heightAt(mx, mz)
				local h = math.clamp(top - ground, 0.3, FENCE_MAX_H)
				local dx, dz = b[1] - a[1], b[3] - a[3]
				local len = math.sqrt(dx * dx + dz * dz)
				if len > 1e-3 then
					list:add(ORIGIN, `Panel_{k}`, mx, top - h / 2, mz, 0.3, h, len, {
						yaw = math.atan2(-dx, -dz),
						color = LOOK.fence.color,
						material = LOOK.fence.material,
						role = "Fence",
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
		list:add(ORIGIN, "Anchor", o[1], o[2], o[3], 0.2, 0.2, 0.2, { canCollide = false, transparency = 1, role = "Anchor" })
		for k, p in line do
			list:extra({ kind = "Attachment", part = "Anchor", name = `A{k}`, offset = { p[1] - o[1], p[2] - o[2], p[3] - o[3] } })
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
		table.insert(out, newPlan(`Wire_{r.id}`, "wire", props, { Route = r.id }, list))
	end
	return out, looks
end

return RouteProps
