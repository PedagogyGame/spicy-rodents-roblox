--!strict
-- ReplicatedStorage.Shared.Infection.MedicalRoute
-- Where an ambulance stops for a patient and how it drives there, and the last stretch a walk-in
-- patient takes to the hospital door (owner 2026-11-10: "there should be an ambulance come";
-- hospital_police_infection §7.2 nearestRoadStage, §7.4 makeRoadTrip).
-- v5.4 hard-codes three district tables of road centrelines and an if-chain of legs. Ported as
-- written, that chain drives along x = dest.x through the house blocks for any stop on the z = -174 u
-- street, and it knows nothing of the roads the rebuild added (the north cross, the estate avenue,
-- the quay approach). This module builds the same thing from the data instead: every asphalt strip
-- of generated/Roads is a centreline, collinear strips merge, perpendicular centrelines join where
-- they cross or stop within JOIN_GAP of each other (the westside street ends 25 studs short of the
-- hospital road in the data, as it did in v5.4's trunk), and a trip is the shortest path over those
-- joins. Every leg is axis-aligned and on a road centreline by construction.
--   stage(roads, x, z): the nearest point on any centreline (the ambulance stops there).
--   trip(roads, from, stage): the polyline from `from` (the hospital drive) to the stage, or nil
--     when the two are the same spot (nothing to drive).
--   walkTail(strips, entrance): from the north end of the westside sidewalk (the last node the
--     sidewalk graph reaches: Actors/Nav joins strips that touch, and the hospital road's sidewalk
--     starts 0.35 studs beyond it) along the hospital road's south sidewalk, across the road, up the
--     drive's east sidewalk to the door. Coordinates are read from the strips by id, never typed in.
-- Interface: build(strips) -> Roads; stage(roads, x, z) -> Stage?; trip(roads, from, stage) ->
--   { {x, z} }?; onRoad(roads, x, z, pad?) -> boolean; walkTail(strips, entrance) -> { {x, z} }?;
--   length(points) -> studs; TAIL_IDS; JOIN_GAP
-- Pure; studs. No side effects on require.

export type Strip = {
	id: string,
	kind: string,
	axis: "x" | "z",
	coord: number,
	min: number,
	max: number,
	half: number,
}

export type Line = {
	index: number,
	axis: "x" | "z", -- the axis the road runs along
	coord: number, -- its fixed coordinate
	min: number,
	max: number,
	half: number,
	ids: { string },
	nodes: { number }, -- node ids on this line
}

export type Node = { id: number, x: number, z: number, lines: { number } }

export type Roads = {
	lines: { Line },
	nodes: { Node },
	edges: { [number]: { { to: number, d: number } } },
}

export type Stage = { x: number, z: number, axis: "x" | "z", dist: number, line: number }

local MedicalRoute = {}

-- Two centrelines join when one stops this far (studs of non-asphalt) short of the other's edge.
MedicalRoute.JOIN_GAP = 26
-- The strips the walk-in tail is read from (generated/Roads ids).
MedicalRoute.TAIL_IDS = table.freeze({
	westside = "rd_072_westside_sidewalk_x-299",
	roadSouth = "rd_066_hospital_sidewalk_z273.5",
	driveEast = "rd_070_hospital_drive_sidewalk_x-349.5",
})
-- Points closer than this are one point (v5.4 dedupes at 0.35 u).
local DEDUPE = 0.875
local DOOR_STANDOFF = 6 -- studs in front of the door where the tail turns in

local function pointOn(line: Line, along: number): (number, number)
	if line.axis == "z" then
		return line.coord, along
	end
	return along, line.coord
end

local function alongOf(line: Line, x: number, z: number): number
	return if line.axis == "z" then z else x
end

-- build(strips): the road graph from the asphalt strips (Town.strips or generated/Roads records
-- already reduced to axis, coord, min, max, half).
function MedicalRoute.build(strips: { Strip }): Roads
	local sorted: { Strip } = {}
	for _, s in strips do
		if s.kind == "asphalt" and (s.axis == "x" or s.axis == "z") then
			table.insert(sorted, s)
		end
	end
	table.sort(sorted, function(a, b)
		if a.axis ~= b.axis then
			return a.axis < b.axis
		elseif a.coord ~= b.coord then
			return a.coord < b.coord
		elseif a.min ~= b.min then
			return a.min < b.min
		end
		return a.id < b.id
	end)
	local lines: { Line } = {}
	for _, s in sorted do
		local last = lines[#lines]
		if
			last
			and last.axis == s.axis
			and math.abs(last.coord - s.coord) < 0.5
			and s.min <= last.max + MedicalRoute.JOIN_GAP
		then
			last.max = math.max(last.max, s.max)
			last.half = math.max(last.half, s.half)
			table.insert(last.ids, s.id)
		else
			table.insert(lines, {
				index = #lines + 1,
				axis = s.axis,
				coord = s.coord,
				min = s.min,
				max = s.max,
				half = s.half,
				ids = { s.id },
				nodes = {},
			})
		end
	end
	local roads: Roads = { lines = lines, nodes = {}, edges = {} }
	local gap = MedicalRoute.JOIN_GAP
	for i, a in lines do
		for j = i + 1, #lines do
			local b = lines[j]
			if a.axis ~= b.axis then
				-- the crossing point has a's coord on a's cross axis and b's on b's
				local alongA, alongB = b.coord, a.coord
				if
					alongA >= a.min - b.half - gap
					and alongA <= a.max + b.half + gap
					and alongB >= b.min - a.half - gap
					and alongB <= b.max + a.half + gap
				then
					local x, z = pointOn(a, alongA)
					local id = #roads.nodes + 1
					roads.nodes[id] = { id = id, x = x, z = z, lines = { a.index, b.index } }
					roads.edges[id] = {}
					table.insert(a.nodes, id)
					table.insert(b.nodes, id)
				end
			end
		end
	end
	for _, line in lines do
		table.sort(line.nodes, function(p, q)
			local np, nq = roads.nodes[p], roads.nodes[q]
			return alongOf(line, np.x, np.z) < alongOf(line, nq.x, nq.z)
		end)
		for k = 2, #line.nodes do
			local p, q = roads.nodes[line.nodes[k - 1]], roads.nodes[line.nodes[k]]
			local d = math.abs(p.x - q.x) + math.abs(p.z - q.z)
			table.insert(roads.edges[p.id], { to = q.id, d = d })
			table.insert(roads.edges[q.id], { to = p.id, d = d })
		end
	end
	return roads
end

-- stage(roads, x, z): the nearest road-centreline point (hospital_police_infection §7.2).
function MedicalRoute.stage(roads: Roads, x: number, z: number): Stage?
	local best: Stage? = nil
	for _, line in roads.lines do
		local along = math.clamp(alongOf(line, x, z), line.min, line.max)
		local px, pz = pointOn(line, along)
		local d = math.sqrt((px - x) ^ 2 + (pz - z) ^ 2)
		if best == nil or d < best.dist - 1e-9 then
			best = { x = px, z = pz, axis = line.axis, dist = d, line = line.index }
		end
	end
	return best
end

-- onRoad(roads, x, z, pad?): is the point on asphalt (within a strip's half width plus pad)?
function MedicalRoute.onRoad(roads: Roads, x: number, z: number, pad: number?): boolean
	local p = pad or 0
	for _, line in roads.lines do
		local along, across = alongOf(line, x, z), if line.axis == "z" then x else z
		if math.abs(across - line.coord) <= line.half + p and along >= line.min - p and along <= line.max + p then
			return true
		end
	end
	return false
end

local function push(points: { { number } }, x: number, z: number)
	local last = points[#points]
	if last and math.abs(last[1] - x) + math.abs(last[2] - z) <= DEDUPE then
		return
	end
	-- drop the middle of three collinear points
	local prev = points[#points - 1]
	if last and prev then
		local sameX = math.abs(prev[1] - last[1]) < 1e-6 and math.abs(last[1] - x) < 1e-6
		local sameZ = math.abs(prev[2] - last[2]) < 1e-6 and math.abs(last[2] - z) < 1e-6
		local forward = (last[1] - prev[1]) * (x - last[1]) + (last[2] - prev[2]) * (z - last[2]) > 0
		if (sameX or sameZ) and forward then
			last[1], last[2] = x, z
			return
		end
	end
	table.insert(points, { x, z })
end

-- trip(roads, from, stage): the road polyline from `from` {x, z} (snapped to its nearest centreline)
-- to the stage. nil when there is nothing to drive (the stage is where the ambulance already is) or
-- no road joins the two.
function MedicalRoute.trip(roads: Roads, from: { number }, stage: Stage): { { number } }?
	local start = MedicalRoute.stage(roads, from[1], from[2])
	if start == nil then
		return nil
	end
	local la, lb = roads.lines[start.line], roads.lines[stage.line]
	local a0, b0 = alongOf(la, start.x, start.z), alongOf(lb, stage.x, stage.z)
	local points: { { number } } = {}
	push(points, start.x, start.z)
	local direct = if la == lb then math.abs(a0 - b0) else math.huge
	-- Dijkstra from the start point over the join nodes
	local dist: { [number]: number } = {}
	local came: { [number]: number } = {}
	local done: { [number]: boolean } = {}
	for _, id in la.nodes do
		local n = roads.nodes[id]
		dist[id] = math.abs(alongOf(la, n.x, n.z) - a0)
	end
	while true do
		local cur, curD = nil, math.huge
		for id, d in dist do
			if not done[id] and (d < curD or (d == curD and cur ~= nil and id < cur)) then
				cur, curD = id, d
			end
		end
		if cur == nil then
			break
		end
		done[cur] = true
		for _, e in roads.edges[cur] do
			local nd = curD + e.d
			if dist[e.to] == nil or nd < dist[e.to] - 1e-9 then
				dist[e.to] = nd
				came[e.to] = cur
			end
		end
	end
	local bestNode, bestD = nil, direct
	for _, id in lb.nodes do
		local d = dist[id]
		if d then
			local n = roads.nodes[id]
			local total = d + math.abs(alongOf(lb, n.x, n.z) - b0)
			if total < bestD - 1e-9 then
				bestNode, bestD = id, total
			end
		end
	end
	if bestD == math.huge then
		return nil
	end
	if bestNode then
		local chain = {}
		local c: number? = bestNode
		while c do
			table.insert(chain, 1, c)
			c = came[c]
		end
		for _, id in chain do
			local n = roads.nodes[id]
			push(points, n.x, n.z)
		end
	end
	push(points, stage.x, stage.z) -- (a stage within the dedupe distance of a join ends at the join)
	if #points < 2 or MedicalRoute.length(points) < 2 * DEDUPE then
		return nil
	end
	return points
end

-- walkTail(strips, entrance): the authored end of every walk-in route (see the header).
function MedicalRoute.walkTail(strips: { Strip }, entrance: { number }): { { number } }?
	local byId: { [string]: Strip } = {}
	for _, s in strips do
		byId[s.id] = s
	end
	local west = byId[MedicalRoute.TAIL_IDS.westside]
	local south = byId[MedicalRoute.TAIL_IDS.roadSouth]
	local drive = byId[MedicalRoute.TAIL_IDS.driveEast]
	if west == nil or south == nil or drive == nil then
		return nil
	end
	-- the westside sidewalk runs along z; its end nearest the hospital road's sidewalk is the start
	local startZ = if math.abs(west.max - south.coord) <= math.abs(west.min - south.coord) then west.max else west.min
	-- stop in front of the door on the side the drive comes from
	local side = if drive.min + drive.max < 2 * entrance[2] then -1 else 1
	local standZ = entrance[2] + side * DOOR_STANDOFF
	local points: { { number } } = {}
	push(points, west.coord, startZ)
	push(points, west.coord, south.coord)
	push(points, drive.coord, south.coord)
	push(points, drive.coord, standZ)
	push(points, entrance[1], standZ)
	push(points, entrance[1], entrance[2])
	return points
end

function MedicalRoute.length(points: { { number } }): number
	local total = 0
	for i = 2, #points do
		total += math.sqrt((points[i][1] - points[i - 1][1]) ^ 2 + (points[i][2] - points[i - 1][2]) ^ 2)
	end
	return total
end

return MedicalRoute
