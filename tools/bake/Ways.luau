--!strict
-- tools/bake/Ways: the way from the town to each expansion venue the attractions bake builds a site on. Found at
-- the paintball review (2026-11-13): "the station stands alone in a field about 813 studs from the nearest built
-- road". Nothing else bakes data/expansion.json's streets and paths yet, so a venue that is built gets its own
-- way here, under one Model "Ways" of Workspace.Attractions (no Site attribute: it is not a site):
--   the walk     each entrance's own path (Expansion.paths, named by the entrance's `path`), one concrete strip
--                a leg;
--   the street   the new street that walk meets (its asphalt and both sidewalks: the Expansion.strips that share
--                its `src`), from the town road it continues to its far end;
--   the forecourt   concrete either side of a straight walk, from the door to the street's sidewalk;
--   the lamps    the town's own street lamps along the new street (worldgen LampPlan: spacing, kit, verges);
--   the post     a fingerpost where the new street leaves the town road it continues, naming the venue and its
--                games, its arrow along the street towards the venue.
-- Every strip is laid by the town's road plan (worldgen Plan.road: flat segments on the terrain, the town's
-- colours and materials), so the way is the town's kind of street, not a look of its own.
-- Pure planning (Ways.plan, no Instances) is apart from making the Instances (Ways.build), so
-- tests/unit/attractions_ways.spec.luau walks the planned way from the town road to the door without the engine.
-- Interface: plan(venues, labels) -> Plan; venues(ids) -> the venue records of generated/Expansion by id;
--   on(plan, x, z) -> the planned strip under a point, or nil; build(roblox, folder, plan) -> parts
local Expansion = require("../../generated/Expansion")
local Roads = require("../../generated/Roads")
local Lighting = require("../../generated/Lighting")
local TerrainExtensions = require("../../generated/TerrainExtensions")
local Height = require("../../src/shared/World/Height")
local Plan = require("../../src/worldgen/Plan")
local Spec = require("../../src/worldgen/Spec")
local Kits = require("../../src/worldgen/Kits")
local LampPlan = require("../../src/worldgen/LampPlan")
local Surface = require("../../src/worldgen/Surface")
local Factory = require("../../src/worldgen/Factory")
local RoadBuilder = require("../../src/worldgen/Builders/Road")
local Greybox = require("../../src/worldgen/Builders/Greybox")

local Ways = {}

Ways.MODEL = "Ways"
Ways.FORECOURT_HALF = 30 -- studs either side of a straight walk the forecourt reaches
Ways.TOUCH = 0.6 -- studs: a walk's end this close to a strip's edge meets it
Ways.POST_IN = 8 -- studs along the new street from the junction to the fingerpost
Ways.POST_OUT = 2.5 -- studs from the sidewalk's outer edge to the fingerpost, on the venue's side
Ways.POST_HEIGHT = 9 -- studs: the post's top over the ground; the board hangs below it
Ways.POST_GREEN = { 32, 74, 50 } -- the board's colour (the town's street-name green)
Ways.POST_WHITE = { 236, 236, 228 }

export type Road = Plan.Road
export type Post = { x: number, z: number, axis: string, toward: number, side: number, lines: { string } }
export type Way = {
	venue: string,
	door: { number }, -- x, y (the venue's floor), z of the entrance its walk starts at
	walk: { Road }, -- the walk's legs, door end first
	street: { Road }, -- the new street's asphalt, then its sidewalks
	forecourt: { Road },
	joins: Road?, -- the town road the new street continues (generated/Roads), if it meets one end to end
	post: Post?,
}
export type Plan = { ways: { Way }, roads: { Road } }

local function stripBox(r: any): (number, number, number, number)
	-- x0, x1, z0, z1 of a strip (axis = the direction it runs; coord = its centre line across)
	local a0, a1 = math.min(r.start, r["end"]), math.max(r.start, r["end"])
	local c0, c1 = r.coord - r.width / 2, r.coord + r.width / 2
	if r.axis == "x" then
		return a0, a1, c0, c1
	end
	return c0, c1, a0, a1
end

local function touches(r: any, x: number, z: number): boolean
	local x0, x1, z0, z1 = stripBox(r)
	local t = Ways.TOUCH
	return x >= x0 - t and x <= x1 + t and z >= z0 - t and z <= z1 + t
end

-- A path's legs as strips (each leg runs along x or along z; a path that does not is an error in the data).
local function legs(path: any): { Road }
	local out: { Road } = {}
	local pts = path.points
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local r: Road
		if a[1] == b[1] then
			r = {
				id = `{path.id}_{i}`,
				kind = path.kind,
				axis = "z",
				coord = a[1],
				start = a[2],
				["end"] = b[2],
				width = path.width,
			}
		elseif a[2] == b[2] then
			r = {
				id = `{path.id}_{i}`,
				kind = path.kind,
				axis = "x",
				coord = a[2],
				start = a[1],
				["end"] = b[1],
				width = path.width,
			}
		else
			error(`Ways: path {path.id} leg {i} runs neither along x nor along z`)
		end
		if r.kind ~= "asphalt" and Kits.ROAD[r.kind] == nil then
			r.kind = "concrete"
		end
		table.insert(out, r)
	end
	return out
end

local function byId(list: { any }): { [string]: any }
	local out = {}
	for _, v in list do
		out[v.id] = v
	end
	return out
end

-- The planned ways for the venues given ({ [venueId] = venue record of generated/Expansion }); labels[venueId] is
-- the fingerpost's lines (the venue's name and its games).
function Ways.plan(venues: { [string]: any }, labels: { [string]: { string } }?): Plan
	Height.configure(TerrainExtensions)
	local paths = byId((Expansion :: any).paths)
	local strips: { any } = (Expansion :: any).strips
	local out: Plan = { ways = {}, roads = {} }
	local ids: { string } = {}
	for id in venues do
		table.insert(ids, id)
	end
	table.sort(ids)
	for _, id in ids do
		local venue = venues[id]
		for _, ent in venue.entrances or {} do
			local path = paths[ent.path]
			if path == nil then
				continue -- "inside", or a path not in the data
			end
			local walk = legs(path)
			local tip = path.points[#path.points]
			-- the street the walk's far end meets: the strip it touches, and every strip of the same street
			local street: { Road } = {}
			local src: string? = nil
			for _, s in strips do
				if touches(s, tip[1], tip[2]) then
					src = s.src
					break
				end
			end
			if src ~= nil then
				for _, s in strips do
					if s.src == src then
						table.insert(street, {
							id = s.id,
							kind = s.kind,
							axis = s.axis,
							coord = s.coord,
							start = s.start,
							["end"] = s["end"],
							width = s.width,
							registered = s.registered,
						})
					end
				end
				table.sort(street, function(a, b)
					return (a.kind == "asphalt" and 0 or 1) < (b.kind == "asphalt" and 0 or 1)
						or ((a.kind == "asphalt") == (b.kind == "asphalt") and a.id < b.id)
				end)
			end
			local way: Way = {
				venue = id,
				door = { path.points[1][1], venue.floorY, path.points[1][2] },
				walk = walk,
				street = street,
				forecourt = {},
				joins = nil,
				post = nil,
			}
			local main = street[1]
			-- the forecourt: a straight walk across the street's line gets concrete either side of it, from the
			-- door to the sidewalk's outer edge
			if main and #walk == 1 and walk[1].axis ~= main.axis then
				local w = walk[1]
				local outer = nil -- the sidewalk edge facing the door
				for _, s in street do
					local c0, c1 = s.coord - s.width / 2, s.coord + s.width / 2
					local edge = if w.start < main.coord then c0 else c1
					if outer == nil or math.abs(edge - w.start) < math.abs(outer - w.start) then
						outer = edge
					end
				end
				local from = w.start + (if w.start < main.coord then 1 else -1) -- one stud off the door line
				local to = outer :: number - (if w.start < main.coord then 0.05 else -0.05)
				local half = Ways.FORECOURT_HALF
				for i, side in { -1, 1 } do
					local near = w.coord + side * w.width / 2
					local far = w.coord + side * (w.width / 2 + half)
					table.insert(way.forecourt, {
						id = `{path.id}_forecourt_{i}`,
						kind = "concrete",
						axis = w.axis,
						coord = (near + far) / 2,
						start = from,
						["end"] = to,
						width = half,
					})
				end
			end
			-- the town road the new street continues: same line, same width, meeting at one end
			if main then
				for _, r in Roads :: { any } do
					if r.axis == main.axis and r.coord == main.coord and r.width == main.width then
						local r0, r1 = math.min(r.start, r["end"]), math.max(r.start, r["end"])
						local m0, m1 = math.min(main.start, main["end"]), math.max(main.start, main["end"])
						if r1 == m0 or r0 == m1 then
							way.joins = r
							local junction = if r1 == m0 then m0 else m1
							local toward = if r1 == m0 then 1 else -1 -- along the axis, from the junction to the venue
							local vAlong = if main.axis == "x" then venue.position.x else venue.position.z
							local vAcross = if main.axis == "x" then venue.position.z else venue.position.x
							local side = if vAcross < main.coord then -1 else 1
							local reach = 0
							for _, s in street do
								reach = math.max(reach, (s.coord - main.coord) * side + s.width / 2)
							end
							local along = junction + toward * Ways.POST_IN
							local across = main.coord + side * (reach + Ways.POST_OUT)
							local x = if main.axis == "x" then along else across
							local z = if main.axis == "x" then across else along
							local dist = math.floor(math.abs(vAlong - junction) + 0.5)
							local lines = if labels and labels[id] then table.clone(labels[id]) else { venue.name }
							table.insert(lines, `{dist} studs`)
							way.post = { x = x, z = z, axis = main.axis, toward = toward, side = side, lines = lines }
							break
						end
					end
				end
			end
			table.insert(out.ways, way)
			for _, list in { way.street, way.walk, way.forecourt } do
				for _, r in list do
					table.insert(out.roads, r)
				end
			end
		end
	end
	return out
end

-- The venue records of generated/Expansion for the ids given (an unknown id is an error).
function Ways.venues(ids: { string }): { [string]: any }
	local all = byId((Expansion :: any).venues)
	local out = {}
	for _, id in ids do
		out[id] = all[id] or error(`Ways.venues: no venue {id}`)
	end
	return out
end

-- The planned strip under (x, z) (its id, kind and line), or nil off the way.
function Ways.on(plan: Plan, x: number, z: number): Road?
	for _, r in plan.roads do
		local x0, x1, z0, z1 = stripBox(r)
		if x >= x0 and x <= x1 and z >= z0 and z <= z1 then
			return r
		end
	end
	return nil
end

-- The fingerpost as a build plan: a post and a board along the street, words on both faces with the arrow
-- pointing along the street towards the venue on each.
local function postPlan(post: Post, id: string): Spec.BuildPlan
	local g = Height.at(post.x, post.z)
	local top = g + Ways.POST_HEIGHT
	local boardLen, boardH = 15, 4.2
	-- the board's long side runs along the street; its centre is set off from the post towards the venue
	local yaw = if post.axis == "x" then 0 else math.pi / 2
	local off = post.toward * (boardLen / 2 - 0.4)
	local bx = if post.axis == "x" then post.x + off else post.x
	local bz = if post.axis == "x" then post.z else post.z + off
	local parts: { Spec.PartSpec } = {
		{
			name = "Post",
			cx = post.x,
			cy = g + Ways.POST_HEIGHT / 2 - 0.5,
			cz = post.z,
			yaw = 0,
			pitch = 0,
			sx = 0.5,
			sy = Ways.POST_HEIGHT + 1,
			sz = 0.5,
			color = { 70, 72, 70 },
			material = "Metal",
			canCollide = true,
			transparency = 0,
			role = "Post",
		},
		{
			name = "Board",
			cx = bx,
			cy = top - boardH / 2 - 0.3,
			cz = bz,
			yaw = yaw,
			pitch = 0,
			sx = boardLen,
			sy = boardH,
			sz = 0.25,
			color = Ways.POST_GREEN,
			material = "SmoothPlastic",
			canCollide = false,
			transparency = 0,
			role = "Sign",
		},
	}
	-- the words on both faces; each arrow points along the street towards the venue for a reader in front of that
	-- face. Unturned (a street along x), Front is the -z face and Back the +z face: a reader facing Back looks
	-- along -z and has +x on the right. Turned a quarter (a street along z), Front is the -x face and Back the +x
	-- face: a reader facing Back looks along -x and has -z on the right.
	local function arrowFor(face: string): boolean -- true: the venue is to this face's reader's right
		local rightSign: number
		if post.axis == "x" then
			rightSign = if face == "Back" then 1 else -1 -- along +x
		else
			rightSign = if face == "Back" then -1 else 1 -- along +z
		end
		return rightSign == post.toward
	end
	local extras: { Spec.ExtraSpec } = {}
	for _, face in { "Front", "Back" } do
		local words = table.concat(post.lines, "\n")
		local text = if arrowFor(face) then words .. "  >>" else "<<  " .. words
		table.insert(extras, { kind = "SurfaceGui", part = "Board", name = "Words" .. face, face = face, text = text })
	end
	return {
		kind = "props",
		id = id,
		category = "sign",
		lod = "Automatic",
		streaming = "Default",
		attributes = {},
		parts = parts,
		extras = extras,
	}
end

-- The Instances: one Model "Ways" in `folder` with a Model for each strip, the lamps and the fingerposts.
-- Returns the number of parts made.
function Ways.build(roblox: any, folder: any, plan: Plan): number
	if #plan.roads == 0 then
		return 0
	end
	local factory = Factory.new({
		Instance = roblox.Instance,
		Vector3 = roblox.Vector3,
		CFrame = roblox.CFrame,
		Color3 = roblox.Color3,
		Enum = roblox.Enum,
		UDim2 = roblox.UDim2,
		ColorSequence = roblox.ColorSequence,
	})
	local root = roblox.Instance.new("Model")
	root.Name = Ways.MODEL
	local roadPlans: { Spec.BuildPlan } = {}
	for _, r in plan.roads do
		local rp = Plan.road(r, plan.roads)
		table.insert(roadPlans, rp)
		RoadBuilder.build(rp, factory).Parent = root
	end
	-- the lamps along the new streets (only asphalt streets get lamps; the walks and forecourts keep them off)
	local surface = Surface.new(roadPlans, Height.at)
	local function baseAt(x: number, z: number): number
		return (Surface.at(surface, x, z, Height.at(x, z) + 1))
	end
	local obstacles: { { number } } = {}
	for _, way in plan.ways do
		for _, w in way.walk do
			local x0, x1, z0, z1 = stripBox(w)
			table.insert(obstacles, { (x0 + x1) / 2, (z0 + z1) / 2, math.max(x1 - x0, z1 - z0) / 2 + 2 })
		end
		if way.post then
			table.insert(obstacles, { way.post.x, way.post.z, 2 })
		end
	end
	local lampPlans = LampPlan.plan(plan.roads, roadPlans, {}, Lighting, Kits.lamp, baseAt, obstacles)
	for _, lp in lampPlans do
		Greybox.build(lp, factory).Parent = root
	end
	for i, way in plan.ways do
		if way.post then
			Greybox.build(postPlan(way.post, `Fingerpost_{way.venue}_{i}`), factory).Parent = root
		end
	end
	root.Parent = folder
	local parts = 0
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	return parts
end

return Ways
