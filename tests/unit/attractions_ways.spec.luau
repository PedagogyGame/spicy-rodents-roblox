--!strict
-- tools/bake/Ways (the way from the town to each expansion venue the attractions bake builds), planned and built
-- in memory by the same code that writes build/Attractions.rbxm. Found at the paintball review (2026-11-13): the
-- TV station stood alone on grass 813 studs from the nearest built road, and the end-to-end case's "street" was a
-- patch of grass. Held here: the station's walk meets Chapel Street, Chapel Street continues the town's estate
-- avenue end to end, and a person can walk on paving from the end of the estate avenue's sidewalk to the
-- station's door with no water on the way and no step or slope a body cannot take; the fingerpost at the junction
-- names the station and its game and points the right way on both faces.
local roblox = require("@lune/roblox")
local Expansion = require("../../generated/Expansion")
local Ground = require("@shared/World/Ground")
local Ways = require("../../tools/bake/Ways")

local VENUE = "f3_tv_station"
local STEP_RISE = 0.5 -- studs: the most the paving may rise or fall in one stud of walking
local SLOPE = 0.2 -- the steepest the walk may be over any ten studs (rise over run)

local function venue(): any
	for _, v in (Expansion :: any).venues do
		if v.id == VENUE then
			return v
		end
	end
	error("no venue " .. VENUE)
end

return function(t)
	local v = venue()
	local plan = Ways.plan({ [VENUE] = v }, { [VENUE] = { v.name, "PAINTBALL" } })
	local folder = roblox.Instance.new("Folder")
	local parts = Ways.build(roblox, folder, plan)
	local root = folder:FindFirstChild(Ways.MODEL) :: any

	-- every paving part (the strips' Models: not the lamps, not the fingerpost)
	local paving: { any } = {}
	local stripIds: { [string]: boolean } = {}
	for _, r in plan.roads do
		stripIds[r.id] = true
	end
	for _, m in root:GetChildren() do
		if stripIds[m.Name] then
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") and d.CanCollide then
					table.insert(paving, d)
				end
			end
		end
	end
	-- the top of the paving under (x, z), or nil where there is none
	local function topAt(x: number, z: number): number?
		local best: number? = nil
		for _, p in paving do
			local cf = p.CFrame
			local l = cf:PointToObjectSpace(roblox.Vector3.new(x, cf.Position.Y, z))
			local s = p.Size
			if math.abs(l.X) <= s.X / 2 and math.abs(l.Z) <= s.Z / 2 then
				local y = (cf * roblox.Vector3.new(l.X, s.Y / 2, l.Z)).Y
				if best == nil or y > (best :: number) then
					best = y
				end
			end
		end
		return best
	end

	t.test("the TV station's walk meets Chapel Street, which continues the estate avenue end to end", function()
		t.eq(#plan.ways, 1)
		local way = plan.ways[1]
		t.eq(way.venue, VENUE)
		t.eq(#way.walk, 1)
		t.eq(way.walk[1].id, "xpath_tv_walk_1")
		local ids = {}
		for _, s in way.street do
			table.insert(ids, s.id)
		end
		table.sort(ids)
		t.eq(table.concat(ids, " "), "xs_chapel_st xs_chapel_st_sidewalk_a xs_chapel_st_sidewalk_b")
		t.eq(way.street[1].kind, "asphalt")
		t.truthy(way.joins ~= nil, "Chapel Street meets a town road")
		t.eq((way.joins :: any).id, "rd_037_estate_avenue")
		t.eq(#way.forecourt, 2)
		t.truthy(parts > 0 and parts <= 600, `{parts} parts for the way`)
	end)

	t.test(
		"on paving from the end of the estate avenue's sidewalk to the station's door: no water, no step, no steep slope",
		function()
			local way = plan.ways[1]
			local walk = way.walk[1]
			local sidewalk = nil
			for _, s in way.street do
				if s.id == "xs_chapel_st_sidewalk_a" then
					sidewalk = s
				end
			end
			assert(sidewalk ~= nil, "Chapel Street has its sidewalk a")
			-- along the sidewalk's middle from the town's end of Chapel Street to the walk, then up the walk to the door
			local route: { { number } } = {}
			local x0 = math.min(sidewalk.start, sidewalk["end"])
			for x = x0 + 0.5, walk.coord do
				table.insert(route, { x, sidewalk.coord })
			end
			local zFrom = math.max(walk.start, walk["end"]) - 0.5
			local zTo = math.min(walk.start, walk["end"]) + 6 -- the station's landing starts 6 studs off its door
			for z = zFrom, zTo, -1 do
				table.insert(route, { walk.coord, z })
			end
			local tops: { number } = {}
			local bare, wet, steps = 0, 0, 0
			for i, pt in route do
				local y = topAt(pt[1], pt[2])
				if y == nil then
					bare += 1
					y = tops[i - 1] or 0
				end
				if Ground.surfaceKind(pt[1], pt[2]) ~= "terrain" then
					wet += 1
				end
				if i > 1 and math.abs((y :: number) - tops[i - 1]) > STEP_RISE then
					steps += 1
				end
				tops[i] = y :: number
			end
			t.eq(bare, 0, "points on the way with no paving under them")
			t.eq(wet, 0, "points on the way over water")
			t.eq(steps, 0, `steps over {STEP_RISE} studs`)
			local steepest = 0
			for i = 11, #tops do
				steepest = math.max(steepest, math.abs(tops[i] - tops[i - 10]) / 10)
			end
			t.truthy(steepest <= SLOPE, `steepest stretch {steepest}`)
			-- the walk arrives at the landing outside the door within a step of its top (the venue's floor)
			local last = tops[#tops]
			t.truthy(math.abs(v.floorY - last) <= 1.2, `the walk ends {v.floorY - last} studs under the landing's top`)
			t.truthy(#route > 1400, "the walk is the whole street, not a stub")
		end
	)

	t.test("the fingerpost stands off the paving at the junction and points at the station on both faces", function()
		local post = plan.ways[1].post
		assert(post ~= nil, "the way has a fingerpost")
		t.truthy(topAt(post.x, post.z) == nil, "the post is not on the paving")
		t.truthy(math.abs(post.x - 645) < 20, "by the junction with the estate avenue")
		local fp = nil
		for _, m in root:GetChildren() do
			if string.sub(m.Name, 1, 10) == "Fingerpost" then
				fp = m
			end
		end
		assert(fp ~= nil, "the fingerpost was built")
		local board = fp:FindFirstChild("Board")
		local seen = 0
		for _, g in board:GetChildren() do
			if g:IsA("SurfaceGui") then
				local text = (g:FindFirstChild("Text") :: any).Text
				t.truthy(string.find(text, "PAINTBALL", 1, true) ~= nil and string.find(text, "WBLW", 1, true) ~= nil)
				-- the station is east (+x) of the junction: a reader facing the +z face (Back) has +x on the right
				if g.Face == roblox.Enum.NormalId.Back then
					t.truthy(string.sub(text, -2) == ">>", "Back: the arrow on the right")
				else
					t.truthy(string.sub(text, 1, 2) == "<<", "Front: the arrow on the left")
				end
				seen += 1
			end
		end
		t.eq(seen, 2)
	end)
end
