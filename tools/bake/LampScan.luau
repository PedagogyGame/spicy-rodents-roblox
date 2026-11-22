--!strict
-- tools/bake/LampScan: every light post the bakes place, found in the baked models (owner D35, "make all trees
-- climbable, and even all light posts"). One rule set over the Instances, so tools/bake/lamp_posts.luau (which writes
-- data/lamp_posts.json) and tests/unit/lamp_posts.spec.luau (which holds every baked post to having its climb) see the
-- same posts. A post is a BasePart standing upright (its long axis within 10 degrees of vertical), one of:
--   "Post_<id>" in a Model "Lamps_<street>"   the town's street lamps and the ways' (worldgen LampPlan): the post sunk
--                                             LampPlan.EMBED under its base, the ground; the arm and head over the
--                                             kerb are the Skyline's "Head_<id>" (Skyline.plan), in the same file;
--   "Post" in a Model "Lamp..."               the kit lamps of Bowl Lane (tools/bake/bowl_lane/Street) and Lift Road
--                                             (tools/bake/skylift/Approach): the post from KIT_LIFT over the ground,
--                                             its arm reaching to the sibling "Head";
--   "LampPost"                                the bowling alley's forecourt (tools/bake/alley/Forecourt): standing on
--                                             its foot; no arm (a globe on top);
--   "Greybox" in a Model "..._porch_light"    a yard's porch-light post (worldgen Builders/Props): on the ground, its
--                                             top under the lantern ("Top") over it.
-- An arm is read from its head: the head hangs HEAD_OUT past the arm's tip and HEAD_DROP under the post's top, the arm's
-- shape is the lamps' one (Shared/World/LampPosts.armPoints); a head that does not sit where that shape puts it is no
-- arm of this post (the post keeps its climb, without an arm).
-- Car lanes: every vehicle lane the traffic drives (Shared/Traffic/LaneMath over generated/Lanes and Roads, unified and
-- linked as Server/Traffic/TrafficService has them: both ways, the ways back), as polylines of points LANE_STEP apart,
-- each with its band: half the widest vehicle that drives it (Shared/Traffic/Boxes; a lane naming none of them: the
-- widest of all) and LANE_MARGIN; not the incident police's (PER_SCENE: its way is made per crime scene). No lamp
-- route may come nearer a lane's line than its band (seen from above):
-- armRun cuts an arm's route short of a band, in RUN_STEP steps (none shorter than MIN_RUN: no arm route then).
-- Interface: scan(roots, source) -> { Post }; FILES (the baked models, in order); isPost(inst) -> boolean;
--   carLanes(lanes, roads) -> { Lane }; laneGap(lines, x, z) -> (studs past the nearest band, its lane);
--   armRun(post, lines) -> run? (nil: the whole arm is clear; 0: no arm route)
-- Post = { id, source, path, x, z, ground, bottom, top, radius, arm = { ox, oz, reach }? };
-- Lane = { name, band, pts { {x, z} } }. Pure over Instances and data.

local Boxes = require("../../src/shared/Traffic/Boxes")
local LampPosts = require("../../src/shared/World/LampPosts")
local LaneMath = require("../../src/shared/Traffic/LaneMath")

local LampScan = {}

LampScan.EMBED = 0.8 -- studs: a LampPlan post's foot under its base (worldgen LampPlan: y0 = l.y - 0.8)
LampScan.KIT_LIFT = 0.9 -- studs: a kit lamp's post starts this far over the ground (Street, Approach: g + 0.9)
LampScan.HEAD_OUT = 0.3 -- studs: the head's centre past the arm's tip, out (Skyline, Street, Approach)
LampScan.HEAD_DROP = 0.62 -- studs: the head's centre under the post's top (arm tip top - 0.1, head 0.52 under it)
LampScan.UPRIGHT = math.cos(math.rad(10))

LampScan.LANE_STEP = 2 -- studs between a lane line's points
LampScan.LANE_MARGIN = 0.5 -- studs past a vehicle's half width
LampScan.RUN_STEP = 0.1
LampScan.MIN_RUN = 1.3 -- studs: an arm route shorter than its first bend is none
-- a lane's users (its record's `speed` keys) -> the vehicle kinds (Shared/Traffic/Boxes)
local USERS: { [string]: string } = {
	sedan = "sedan",
	rv = "rv",
	dump = "dump_truck",
	trolley = "trolley",
	ice_cream_van = "ice_cream_van",
	patrol_car = "patrol_car",
	police_car = "patrol_car",
	ambulance_arterial = "ambulance",
	ambulance_drive = "ambulance",
}
-- ... and by the lane record's id where its keys name a leg, not a vehicle (generated/Lanes `users`)
local LANE_USERS: { [string]: string } = {
	responder_ambulance_trunk = "ambulance",
	event_barbecue_cars = "sedan",
	event_softball_cars = "sedan",
}
-- lanes whose way is made per scene, not driven as compiled (LaneMath.incidentRoute: the 5 % "multi" police roll's
-- cars, from the station to wherever the crime is; the compiled record holds one example scene)
local PER_SCENE: { [string]: boolean } = { incident_police_route = true }

-- The baked models a light post can stand in: { source, file } (build/*.rbxm, as tools/ci.sh and the bakes write them).
-- Not the backdrop (build/Backdrop.rbxm, "the far distance is painted scenery"): its pier's four lamp posts stand past
-- the town's ground (three past the world's edge; the fourth, 20 studs inside it, over a pier deck 4 studs under the
-- town's terrain model there, World/Height, that the squirrel's motor and the server's validator stand on).
LampScan.FILES = {
	{ source = "town", file = "build/Town.rbxm" },
	{ source = "attractions", file = "build/Attractions.rbxm" },
	{ source = "bowl_lane", file = "build/Expansion_F2.rbxm" },
	{ source = "skylift", file = "build/Expansion_F4.rbxm" },
	{ source = "corner_store", file = "build/Expansion_F1.rbxm" },
	{ source = "lounge", file = "build/Expansion_LoungeClassic.rbxm" },
	{ source = "neighbourhood_shop", file = "build/Expansion_NeighbourhoodShop.rbxm" },
}

export type Arm = { ox: number, oz: number, reach: number }
export type Post = {
	id: string,
	source: string,
	path: string,
	x: number,
	z: number,
	ground: number,
	bottom: number,
	top: number,
	radius: number,
	arm: Arm?,
}

local function pathOf(inst: any): string
	local parts = {}
	local p = inst
	while p ~= nil do
		table.insert(parts, 1, p.Name)
		p = p.Parent
	end
	return table.concat(parts, "/")
end

-- the part's long axis and extent: (cx, cy, cz, length, radius) when it stands upright, else nil
local function upright(inst: any): (number?, number, number, number, number)
	local cf = inst.CFrame
	local size = inst.Size
	local axes = { { cf.RightVector, size.X }, { cf.UpVector, size.Y }, { cf.LookVector, size.Z } }
	for i, a in axes do
		if math.abs(a[1].Y) >= LampScan.UPRIGHT then
			local others = {}
			for j, b in axes do
				if j ~= i then
					table.insert(others, b[2])
				end
			end
			local p = cf.Position
			return p.X, p.Y, p.Z, a[2], math.min(others[1], others[2]) / 2
		end
	end
	return nil, 0, 0, 0, 0
end

local function startsWith(s: string, prefix: string): boolean
	return string.sub(s, 1, #prefix) == prefix
end

-- the kind of post a part is: "plan" | "kit" | "standing" | "porch", or nil
local function kindOf(inst: any): string?
	if not inst:IsA("BasePart") then
		return nil
	end
	local parent = inst.Parent
	local pname = if parent then parent.Name else ""
	local name = inst.Name
	if startsWith(name, "Post_") and startsWith(pname, "Lamps_") then
		return "plan"
	elseif name == "Post" and startsWith(pname, "Lamp") then
		return "kit"
	elseif name == "LampPost" then
		return "standing"
	elseif name == "Greybox" and string.sub(pname, -12) == "_porch_light" then
		return "porch"
	end
	return nil
end

function LampScan.isPost(inst: any): boolean
	return kindOf(inst) ~= nil and (upright(inst)) ~= nil
end

-- the arm a head at (hx, hy, hz) makes for a post at (x, z) whose top is `top`, or nil when it is not this post's
local function armOf(head: any, x: number, z: number, top: number): Arm?
	local h = head.CFrame.Position
	local dx, dz = h.X - x, h.Z - z
	local d = math.sqrt(dx * dx + dz * dz)
	if d < 2 or d > 8 or math.abs(h.Y + LampScan.HEAD_DROP - top) > 0.08 then
		return nil
	end
	local r3 = function(v: number): number
		return math.floor(v * 1000 + 0.5) / 1000
	end
	return { ox = r3(dx / d), oz = r3(dz / d), reach = r3(d - LampScan.HEAD_OUT) }
end

-- scan(roots, source): every light post under `roots` (a deserialized model's roots), in path order
function LampScan.scan(roots: { any }, source: string): { Post }
	local found: { { inst: any, kind: string } } = {}
	local heads: { [string]: any } = {} -- the Skyline's "Head_<id>" parts
	for _, root in roots do
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") and startsWith(d.Name, "Head_") then
				heads[string.sub(d.Name, 6)] = d
			end
			local kind = kindOf(d)
			if kind then
				table.insert(found, { inst = d, kind = kind })
			end
		end
	end
	local out: { Post } = {}
	local seen: { [string]: number } = {}
	for _, f in found do
		local inst, kind = f.inst, f.kind
		local x, cy, z, len, radius = upright(inst)
		if x == nil then
			continue
		end
		local bottom, top = cy - len / 2, cy + len / 2
		local parent = inst.Parent
		local pname = parent.Name
		local id, ground, arm
		if kind == "plan" then
			id = string.sub(inst.Name, 6)
			ground = bottom + LampScan.EMBED
			local head = heads[id]
			arm = if head then armOf(head, x, z, top) else nil
		elseif kind == "kit" then
			id = pname
			ground = bottom - LampScan.KIT_LIFT
			local head = parent:FindFirstChild("Head")
			arm = if head then armOf(head, x, z, top) else nil
		else
			id = if kind == "porch" then pname else `{pname}_LampPost`
			ground = bottom
			-- a porch light's lantern ("Top") sits over its post: the climb stops under it
			local lantern = if kind == "porch" then parent:FindFirstChild("Top") else nil
			if lantern and lantern:IsA("BasePart") then
				top = math.min(top, lantern.CFrame.Position.Y - lantern.Size.Y / 2)
			end
		end
		table.insert(out, {
			id = id,
			source = source,
			path = pathOf(inst),
			x = x,
			z = z,
			ground = ground,
			bottom = bottom,
			top = top,
			radius = radius,
			arm = arm,
		})
	end
	-- the same name twice (two forecourt posts, a pier's row): numbered west to east, then south to north
	table.sort(out, function(a, b)
		if a.id ~= b.id then
			return a.id < b.id
		end
		if math.abs(a.x - b.x) > 0.01 then
			return a.x < b.x
		end
		return a.z < b.z
	end)
	for _, p in out do
		seen[p.id] = (seen[p.id] or 0) + 1
	end
	local k: { [string]: number } = {}
	for _, p in out do
		if seen[p.id] > 1 then
			k[p.id] = (k[p.id] or 0) + 1
			p.id = `{p.id}{k[p.id]}`
		end
		p.id = `{source}:{p.id}`
	end
	return out
end

export type Lane = { name: string, band: number, pts: { { number } } }

function LampScan.carLanes(records: { any }, roads: { any }): { Lane }
	local widest = 0
	for kind, box in Boxes.BOXES do
		if Boxes.FATAL[kind] then
			widest = math.max(widest, box.width)
		end
	end
	local bandOf: { [string]: number } = {}
	for _, rec in records do
		local w = if LANE_USERS[rec.id] then Boxes.get(LANE_USERS[rec.id]).width else 0
		for user in (rec.speed or {}) :: { [string]: any } do
			local kind = USERS[user]
			if kind then
				w = math.max(w, Boxes.get(kind).width)
			end
		end
		bandOf[rec.id] = (if w > 0 then w else widest) / 2 + LampScan.LANE_MARGIN
	end
	local lanes = LaneMath.load(records)
	LaneMath.unify(lanes, roads, records)
	LaneMath.link(lanes, roads, records)
	local out: { Lane } = {}
	local seen: { [any]: boolean } = {}
	local function add(lane: any)
		local record = lane.source or string.match(lane.id, "^[^#~]+")
		if seen[lane] or not lane.vehicle or PER_SCENE[record] then
			return
		end
		seen[lane] = true
		local band = bandOf[record] or (widest / 2 + LampScan.LANE_MARGIN)
		local dirs = if lane.shape == "loop" then { 1 } else { 1, -1 }
		for _, dir in dirs do
			if lane.shape == "polyline" and dir < 0 and lane.polyRev == nil then
				continue
			end
			local len = LaneMath.length(lane, dir)
			local pts = {}
			local n = math.max(1, math.ceil(len / LampScan.LANE_STEP))
			for k = 0, n do
				local pose = LaneMath.pointAt(lane, len * k / n, dir)
				table.insert(pts, { pose.x, pose.z })
			end
			table.insert(out, { name = `{lane.id} {dir}`, band = band, pts = pts })
		end
		if lane.returnLane then
			add(lane.returnLane)
		end
	end
	local ids = {}
	for id in lanes do
		table.insert(ids, id)
	end
	table.sort(ids)
	for _, id in ids do
		add(lanes[id])
	end
	return out
end

local function segDist(px: number, pz: number, a: { number }, b: { number }): number
	local dx, dz = b[1] - a[1], b[2] - a[2]
	local l2 = dx * dx + dz * dz
	local u = if l2 > 0 then math.clamp(((px - a[1]) * dx + (pz - a[2]) * dz) / l2, 0, 1) else 0
	return math.sqrt((a[1] + dx * u - px) ^ 2 + (a[2] + dz * u - pz) ^ 2)
end

LampScan.GAP_LIMIT = 10 -- studs: laneGap looks no farther past a band than this (farther reads as GAP_LIMIT)
local GRID = 10 -- studs: the cell of laneGap's segment grid
local grids: { [any]: { [number]: { { any } } } } = setmetatable({}, { __mode = "k" }) :: any

local function cellKey(i: number, j: number): number
	return (i + 100000) * 1000000 + (j + 100000)
end

-- the lane segments by grid cell, each in every cell within its band and GAP_LIMIT (built once per lane list)
local function gridOf(lines: { Lane }): { [number]: { { any } } }
	local grid = grids[lines]
	if grid then
		return grid
	end
	grid = {}
	for _, line in lines do
		local grow = line.band + LampScan.GAP_LIMIT
		for i = 2, #line.pts do
			local a, b = line.pts[i - 1], line.pts[i]
			local i0 = math.floor((math.min(a[1], b[1]) - grow) / GRID)
			local i1 = math.floor((math.max(a[1], b[1]) + grow) / GRID)
			local j0 = math.floor((math.min(a[2], b[2]) - grow) / GRID)
			local j1 = math.floor((math.max(a[2], b[2]) + grow) / GRID)
			for ci = i0, i1 do
				for cj = j0, j1 do
					local key = cellKey(ci, cj)
					local cell = grid[key]
					if not cell then
						cell = {}
						grid[key] = cell
					end
					table.insert(cell, { a, b, line })
				end
			end
		end
	end
	grids[lines] = grid
	return grid
end

-- laneGap(lines, x, z): how far (x, z) is outside the nearest lane band (negative: inside it; GAP_LIMIT when nothing is
-- nearer), and that lane's name
function LampScan.laneGap(lines: { Lane }, x: number, z: number): (number, string)
	local best, name = LampScan.GAP_LIMIT, ""
	local cell = gridOf(lines)[cellKey(math.floor(x / GRID), math.floor(z / GRID))]
	for _, seg in cell or {} do
		local line = seg[3]
		local g = segDist(x, z, seg[1], seg[2]) - line.band
		if g < best then
			best, name = g, line.name
		end
	end
	return best, name
end

-- armRun(post, lines): nil when the whole arm's route keeps out of every lane band, else the longest run that does
-- (0 when none of MIN_RUN does)
function LampScan.armRun(post: { x: number, z: number, top: number, arm: any }, lines: { Lane }): number?
	local arm = post.arm
	local full = LampPosts.armPoints(post.x, post.z, post.top, arm)
	local function clear(run: number): boolean
		local pts = LampPosts.cut(full, run)
		for i = 2, #pts do
			local a, b = pts[i - 1], pts[i]
			for k = 0, 8 do
				local u = k / 8
				if LampScan.laneGap(lines, a[1] + (b[1] - a[1]) * u, a[3] + (b[3] - a[3]) * u) < 0 then
					return false
				end
			end
		end
		return true
	end
	if clear(arm.reach) then
		return nil
	end
	local run = arm.reach
	while run > LampScan.MIN_RUN do
		run = math.floor((run - LampScan.RUN_STEP) * 10 + 0.5) / 10
		if clear(run) then
			return run
		end
	end
	return 0
end

return LampScan
