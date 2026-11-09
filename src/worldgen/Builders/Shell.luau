--!strict
-- ServerScriptService.Server.WorldGen.Builders.Shell
-- Enterable shells for W1 (BUILD_PLAN §3.4, §4.4 #7): floor, exterior walls with door openings,
-- partition walls between adjacent rooms (openings where a door sits), server-owned door leaves with a
-- prompt placeholder, room-name volumes and the nav anchor with one Attachment per room-graph node.
-- Shared by Builders/Interior (FRB houses) and Builders/Programme (Hospital, PoliceStation).
-- Interface: build(ctx, layout) where layout = { rooms, doors, wallH, partH, doorH, thick, floorTop,
--   roof = "flat" | "none", extras = { { id, kind, room, x, z } } } in model-local studs
--   (rooms: { id, name, x0, x1, z0, z1, exterior? }; doors: { id, a, b, x, z, w, lockable }).
-- Pure (adds PartSpecs/ExtraSpecs to ctx.list).

local Building = require("./Building")
local RoomGraph = require("../RoomGraph")
local Spec = require("../Spec")

local Shell = {}

local EPS = 1e-3
local PARTITION = { 236, 233, 224 }
local FLOOR = { 160, 152, 140 }
local DOOR = { 120, 86, 60 }

export type Room = { id: string, name: string, x0: number, x1: number, z0: number, z1: number, exterior: boolean? }
export type Door = { id: string, a: string, b: string, x: number, z: number, w: number, lockable: boolean }
export type Layout = {
	rooms: { Room },
	doors: { Door },
	wallH: number,
	partH: number,
	doorH: number,
	thick: number,
	floorTop: number, -- above the seat
	roof: string,
	extras: { { id: string, kind: string, room: string, x: number, z: number } },
	windows: string?, -- "bands" (ribbon windows, hospital) or nil (window grid)
}

-- One straight wall along local X (axis "x", at mz = fixed) or local Z (axis "z", at mx = fixed), from
-- `a` to `b`, with openings { c, w } (door centre and width along the wall) and a lintel over each.
local function wall(
	ctx: Spec.LotCtx,
	name: string,
	axis: string,
	fixed: number,
	a: number,
	b: number,
	gaps: { { c: number, w: number } },
	y0: number,
	h: number,
	doorH: number,
	t: number,
	color: { number }
)
	table.sort(gaps, function(g1, g2)
		return g1.c < g2.c
	end)
	local pieces: { { number } } = {}
	local cur = a
	for _, g in gaps do
		local g0, g1 = g.c - g.w / 2, g.c + g.w / 2
		if g0 > cur + EPS then
			table.insert(pieces, { cur, g0, 0, h })
		end
		if h > doorH + EPS then
			table.insert(pieces, { math.max(g0, a), math.min(g1, b), doorH, h }) -- lintel
		end
		cur = math.max(cur, g1)
	end
	if b > cur + EPS then
		table.insert(pieces, { cur, b, 0, h })
	end
	for i, p in pieces do
		local len, mid = p[2] - p[1], (p[1] + p[2]) / 2
		local ph, py = p[4] - p[3], y0 + (p[3] + p[4]) / 2
		local opts = { color = color, material = if ctx.palette then ctx.palette.material else nil, role = "Wall" }
		if axis == "x" then
			ctx.list:add(ctx.frame, `{name}_{i}`, mid, py, fixed, len, ph, t, opts)
		else
			ctx.list:add(ctx.frame, `{name}_{i}`, fixed, py, mid, t, ph, len, opts)
		end
	end
end

local function doorLeaf(ctx: Spec.LotCtx, d: Door, axis: string, y0: number, doorH: number, t: number)
	local attrs = {
		DoorId = d.id,
		ServerOwned = true,
		Lockable = d.lockable,
		Open = false,
		Locked = false,
		RoomA = d.a,
		RoomB = d.b,
	}
	local name = "Door_" .. d.id
	local leafT = math.max(t * 0.5, 0.2)
	-- size along the wall in local X so the part's local Z is the door normal (DoorReach, Doors)
	ctx.list:add(ctx.frame, name, d.x, y0 + doorH / 2, d.z, d.w, doorH, leafT, {
		yaw = if axis == "z" then math.pi / 2 else 0,
		color = if ctx.palette then ctx.palette.door else DOOR,
		material = "Wood",
		role = "Door",
		attrs = attrs,
	})
	ctx.list:extra({
		kind = "Prompt",
		part = name,
		name = "Prompt",
		action = "Open",
		offset = { 0, 0, 0 },
		attrs = { Placeholder = true },
	})
end

function Shell.build(ctx: Spec.LotCtx, L: Layout)
	local W, D, t = ctx.W, ctx.D, L.thick
	local pal = Building.look(ctx)
	local WALL = pal.wall
	local y0 = L.floorTop
	ctx.list:add(
		ctx.frame,
		"Floor",
		0,
		y0 - 0.2,
		0,
		W,
		0.4,
		D,
		{ color = FLOOR, role = "Floor", material = "Concrete" }
	)

	-- doors onto each wall line
	local function gapsOn(axis: string, fixed: number, tol: number, a: number, b: number): { { c: number, w: number } }
		local out = {}
		for _, d in L.doors do
			local onLine = if axis == "x" then math.abs(d.z - fixed) <= tol else math.abs(d.x - fixed) <= tol
			local along = if axis == "x" then d.x else d.z
			if onLine and along >= a - EPS and along <= b + EPS then
				table.insert(out, { c = along, w = d.w })
			end
		end
		return out
	end

	-- exterior walls, inside the footprint
	local h = L.wallH
	wall(
		ctx,
		"WallFront",
		"x",
		-D / 2 + t / 2,
		-W / 2,
		W / 2,
		gapsOn("x", -D / 2, t + EPS, -W / 2, W / 2),
		y0,
		h - y0,
		L.doorH,
		t,
		WALL
	)
	wall(
		ctx,
		"WallBack",
		"x",
		D / 2 - t / 2,
		-W / 2,
		W / 2,
		gapsOn("x", D / 2, t + EPS, -W / 2, W / 2),
		y0,
		h - y0,
		L.doorH,
		t,
		WALL
	)
	wall(
		ctx,
		"WallLeft",
		"z",
		-W / 2 + t / 2,
		-D / 2 + t,
		D / 2 - t,
		gapsOn("z", -W / 2, t + EPS, -D / 2, D / 2),
		y0,
		h - y0,
		L.doorH,
		t,
		WALL
	)
	wall(
		ctx,
		"WallRight",
		"z",
		W / 2 - t / 2,
		-D / 2 + t,
		D / 2 - t,
		gapsOn("z", W / 2, t + EPS, -D / 2, D / 2),
		y0,
		h - y0,
		L.doorH,
		t,
		WALL
	)
	if L.roof == "flat" then
		ctx.list:add(
			ctx.frame,
			"Roof",
			0,
			h + 0.3,
			0,
			W,
			0.6,
			D,
			{ color = pal.roof, material = pal.roofMaterial, role = "Roof" }
		)
	end
	-- windows on the exterior walls, clear of the door openings; plinth, cornice, chimney
	local glaze = if L.windows == "bands" then Building.bands else Building.windows
	glaze(ctx, y0, h, {
		F = gapsOn("x", -D / 2, t + EPS, -W / 2, W / 2),
		B = gapsOn("x", D / 2, t + EPS, -W / 2, W / 2),
		L = gapsOn("z", -W / 2, t + EPS, -D / 2, D / 2),
		R = gapsOn("z", W / 2, t + EPS, -D / 2, D / 2),
	})

	-- partitions between adjacent interior rooms
	local inner: { Room } = {}
	for _, r in L.rooms do
		if not r.exterior then
			table.insert(inner, r)
		end
	end
	local pt = math.max(t * 0.6, 0.3)
	local n = 0
	for i = 1, #inner do
		local A = inner[i]
		for j = i + 1, #inner do
			local B = inner[j]
			-- shared vertical edge (constant x)
			for _, pair in { { A.x1, B.x0 }, { A.x0, B.x1 } } do
				if math.abs(pair[1] - pair[2]) <= EPS then
					local z0, z1 = math.max(A.z0, B.z0), math.min(A.z1, B.z1)
					if z1 - z0 > EPS and math.abs(pair[1]) < W / 2 - t then
						n += 1
						local zz0, zz1 = math.max(z0, -D / 2 + t), math.min(z1, D / 2 - t)
						wall(
							ctx,
							`Part{n}`,
							"z",
							pair[1],
							zz0,
							zz1,
							gapsOn("z", pair[1], EPS, zz0, zz1),
							y0,
							L.partH,
							L.doorH,
							pt,
							PARTITION
						)
					end
				end
			end
			-- shared horizontal edge (constant z)
			for _, pair in { { A.z1, B.z0 }, { A.z0, B.z1 } } do
				if math.abs(pair[1] - pair[2]) <= EPS then
					local x0, x1 = math.max(A.x0, B.x0), math.min(A.x1, B.x1)
					if x1 - x0 > EPS and math.abs(pair[1]) < D / 2 - t then
						n += 1
						local xx0, xx1 = math.max(x0, -W / 2 + t), math.min(x1, W / 2 - t)
						wall(
							ctx,
							`Part{n}`,
							"x",
							pair[1],
							xx0,
							xx1,
							gapsOn("x", pair[1], EPS, xx0, xx1),
							y0,
							L.partH,
							L.doorH,
							pt,
							PARTITION
						)
					end
				end
			end
		end
	end

	-- door leaves (server-owned; Doors.luau swings them) on their wall line
	for _, d in L.doors do
		local onX = math.abs(math.abs(d.z) - D / 2) <= t + EPS
		local onZ = math.abs(math.abs(d.x) - W / 2) <= t + EPS
		local axis = "x"
		local dd = table.clone(d)
		if onX then
			dd.z = if d.z < 0 then -D / 2 + t / 2 else D / 2 - t / 2
		elseif onZ then
			axis = "z"
			dd.x = if d.x < 0 then -W / 2 + t / 2 else W / 2 - t / 2
		else
			-- interior door: on the shared edge of its two rooms
			for _, r in L.rooms do
				if r.id == d.a then
					if math.abs(d.x - r.x0) <= EPS or math.abs(d.x - r.x1) <= EPS then
						axis = "z"
					end
				end
			end
		end
		doorLeaf(ctx, dd, axis, y0, L.doorH, if onX or onZ then t else pt)
	end

	-- room-name volumes (non-solid, queryable)
	for _, r in L.rooms do
		local hgt = if r.exterior then 4 else L.partH
		ctx.list:add(
			ctx.frame,
			"Room_" .. r.id,
			(r.x0 + r.x1) / 2,
			y0 + hgt / 2,
			(r.z0 + r.z1) / 2,
			r.x1 - r.x0,
			hgt,
			r.z1 - r.z0,
			{
				canCollide = false,
				transparency = 1,
				canQuery = true,
				role = "Room",
				color = { 255, 255, 255 },
				attrs = { RoomId = r.id, RoomName = r.name, Exterior = r.exterior == true },
			}
		)
	end

	-- nav anchor: one Attachment per room-graph node (room centres, door midpoints, extras)
	local rooms = {}
	for _, r in L.rooms do
		table.insert(rooms, { id = r.id, rect = { r.x0, r.x1, r.z0, r.z1 }, exterior = r.exterior })
	end
	local doors = {}
	for _, d in L.doors do
		table.insert(doors, { id = d.id, a = d.a, b = d.b, at = { d.x, d.z } })
	end
	local extras = {}
	for _, e in L.extras do
		table.insert(extras, { id = e.id, kind = e.kind, room = e.room, at = { e.x, e.z } })
	end
	local graph = RoomGraph.build(rooms, doors, extras)
	ctx.list:add(ctx.frame, "Nav", 0, y0 + 1, 0, 0.2, 0.2, 0.2, {
		canCollide = false,
		transparency = 1,
		role = "Anchor",
		attrs = { NavNodes = #graph.nodes, NavUnreached = #RoomGraph.unreached(graph, "outside") },
	})
	for _, node in graph.nodes do
		if node.id ~= "outside" then
			table.insert(ctx.list.extras, {
				kind = "Attachment",
				part = "Nav",
				name = node.id,
				offset = { node.x, 0, node.z },
				attrs = { Kind = node.kind, Links = table.concat(graph.links[node.id], ",") },
			})
		end
	end
end

-- Lot-local programme rect [x0, x1, z0, z1] in HTML units (lz toward the front) -> model-local studs.
function Shell.fromLot(rect: { number }): (number, number, number, number)
	local s = Spec.SPU
	return rect[1] * s, rect[2] * s, -rect[4] * s, -rect[3] * s
end

return Shell
