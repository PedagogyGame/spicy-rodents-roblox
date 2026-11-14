--!strict
-- The paintball arena's bake (checklist PB-5): the parts are the collision data. The part list is a pure function
-- of the plan, one part for each box, ramp and curtain through Arena.toSite; the bake run in memory through the
-- registry (tools/bake/GameBakes, as tools/bake/attractions.luau runs it) leaves Arena.MODEL on the TV station's
-- site with every solid part where the ball test has its box, in the world, whichever way the site is turned;
-- nothing else inside the arena is solid; the monitors and the curtains are there by name; the lobby annex and
-- the outside are outside; and the whole venue is inside its part budget.
local roblox = require("@lune/roblox")
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local Games = require("@shared/Minigames/Games")
local Arena = require("@shared/Minigames/Paintball/Arena")
local ArenaData = require("@shared/Minigames/Paintball/ArenaData")
local ArenaDataPlan = require("@shared/Minigames/Paintball/ArenaDataPlan")
local Contract = require("@shared/Minigames/Paintball/Contract")
local Expansion = require("../../generated/Expansion")
local Flicker = require("../../tools/games/paintball/arena/Flicker")
local GameBakes = require("../../tools/bake/GameBakes")
local PartList = require("../../tools/games/paintball/arena/PartList")

local function venueRecord(): any
	for _, v in (Expansion :: any).venues do
		if v.id == Contract.SITE then
			return v
		end
	end
	error("no TV station in generated/Expansion")
end

return function(t)
	local plan = ArenaData.plan()
	local arena = ArenaData.build()
	local n = #plan.kinds
	local venue = venueRecord()

	t.test("the part list: one part for each box, the same size in the same place, through Arena.toSite", function()
		local parts = PartList.solids(plan)
		t.eq(#parts, n + #plan.ramps + #plan.curtains[1] + #plan.curtains[2])
		local seen: { [number]: boolean } = {}
		local monitors, signs, lamps = 0, 0, 0
		for _, p in parts do
			t.truthy(p.x0 < p.x1 and p.y0 < p.y1 and p.d0 < p.d1, `{p.name} has a size`)
			if p.box then
				local i = p.box
				t.falsy(seen[i], `box {i} has two parts`)
				seen[i] = true
				local k = (i - 1) * 6
				local b = plan.boxes
				local X0, Y0, D1 = Arena.toSite(b[k + 1], b[k + 2], b[k + 3])
				local X1, Y1, D0 = Arena.toSite(b[k + 4], b[k + 5], b[k + 6])
				t.deepEq({ p.x0, p.y0, p.d0, p.x1, p.y1, p.d1 }, { X0, Y0, D0, X1, Y1, D1 }, `box {i}`)
				t.truthy(p.collide and p.tilt == nil, `box {i}'s part is solid and square to the building`)
				t.truthy((p.transparency or 0) < 0.9, `box {i}'s part can be seen`)
				local look = ArenaDataPlan.LOOKS[plan.looks[i]]
				t.truthy(PartList.LOOK[look] ~= nil)
				if look == "glass" then
					-- the lobby looks at the match through it: clear, and not the material that hides what is
					-- see-through behind it
					t.truthy(p.material ~= "Glass" and (p.transparency or 0) >= 0.8)
				end
				local level = math.clamp(math.floor((b[k + 2] + 1.01) / Arena.FLOOR_HEIGHT), 0, Arena.FLOORS - 1)
				t.eq(p.group, if b[k + 2] >= Arena.HEIGHT then "Roof" else `Floor{level}`)
				if plan.monitors[i] then
					monitors += 1
					t.eq(p.name, Arena.MONITOR)
					t.truthy(p.screen ~= nil)
					t.eq(plan.kinds[i], Arena.KIND.prop, "a monitor inside the arena is a prop box's own part")
				else
					t.truthy(p.name ~= Arena.MONITOR and p.screen == nil)
				end
				signs += #(p.signs or {})
				lamps += if p.light then 1 else 0
			end
		end
		for i = 1, n do
			t.truthy(seen[i], `box {i} has no part`)
		end
		t.truthy(monitors >= 12, `{monitors} old sets and wall monitors about the floors`)
		t.truthy(signs >= 15 and lamps >= 60, `{signs} signs and {lamps} lamps`)
		for _, look in ArenaDataPlan.LOOKS do
			t.truthy(PartList.LOOK[look] ~= nil, `the look {look} has a colour and a material`)
		end
		-- a ramp's part lies in the ramp's plane: its top face is the walking surface
		local ramps = 0
		for _, p in parts do
			if p.ramp then
				ramps += 1
				local r = plan.ramps[p.ramp]
				t.eq(p.name, "Ramp")
				t.truthy(
					p.collide and p.query == nil and p.transparency == 1,
					"walked on, unseen, and honest about rays"
				)
				local angle = p.tilt :: number
				t.near(math.tan(math.abs(angle)), (r.y1 - r.y0) / (r.maxX - r.minX), 1e-9)
				t.eq(angle > 0, r.dir > 0)
				local cx, cy, thick = (p.x0 + p.x1) / 2, (p.y0 + p.y1) / 2, p.y1 - p.y0
				local length = p.x1 - p.x0
				for _, u in { -0.5, 0, 0.5 } do
					-- a point of the top face, in the site's frame (X = x, Y = y)
					local x = cx + math.cos(angle) * u * length - math.sin(angle) * thick / 2
					local y = cy + math.sin(angle) * u * length + math.cos(angle) * thick / 2
					local h = Arena.rampHeight(r, math.clamp(x, r.minX, r.maxX), (r.minZ + r.maxZ) / 2) :: number
					t.near(y, h, 1e-6, `ramp {p.ramp}'s top face is on the walking surface`)
				end
				local _, _, D1 = Arena.toSite(0, 0, r.minZ)
				local _, _, D0 = Arena.toSite(0, 0, r.maxZ)
				t.deepEq({ p.d0, p.d1 }, { D0, D1 })
			end
		end
		t.eq(ramps, #plan.ramps)
		-- the curtains: the doorways' air, in the team's colour, never solid
		for team = 1, 2 do
			local found = 0
			for _, p in parts do
				if p.curtain == team then
					found += 1
					t.eq(p.name, Arena.CURTAIN .. team)
					t.falsy(p.collide)
					t.truthy((p.transparency or 0) > 0.2)
					t.deepEq(p.color, PartList.TEAM[team])
					local c = plan.curtains[team][found]
					local X0, Y0, D1 = Arena.toSite(c.minX, c.minY, c.minZ)
					local X1, Y1, D0 = Arena.toSite(c.maxX, c.maxY, c.maxZ)
					t.deepEq({ p.x0, p.y0, p.d0, p.x1, p.y1, p.d1 }, { X0, Y0, D0, X1, Y1, D1 })
				end
			end
			t.eq(found, 2)
		end
		t.truthy(PartList.TEAM[1][1] > 200 and PartList.TEAM[1][2] > 100, "team 1 is orange, not red")
		-- the same list every time
		local again = PartList.solids(plan)
		t.eq(#again, #parts)
		t.deepEq(again[n], parts[n])
	end)

	t.test(
		"the paint: every painted sign lies on a face that can be seen; names, numbers and monitors on every storey",
		function()
			local H = Arena.FLOOR_HEIGHT
			local normals: { [string]: { number } } =
				{ ["+x"] = { 1, 0 }, ["-x"] = { -1, 0 }, ["+z"] = { 0, 1 }, ["-z"] = { 0, -1 } }
			local digits: { [number]: number } = {}
			local stairs: { [number]: number } = {}
			local named: { [number]: number } = {}
			local painted = 0
			local arrows = 0
			local words: { [string]: boolean } = {}
			for _, s in plan.signs do
				local at, w, h = s.at, s.w, s.h
				words[s.text] = true
				if at and w and h then
					painted += 1
					local k = (s.box - 1) * 6
					local b = plan.boxes
					local nx, nz = normals[s.face][1], normals[s.face][2]
					-- on the face: the box's own, and the whole rectangle within it
					local faceAt = if nx > 0
						then b[k + 4]
						elseif nx < 0 then b[k + 1]
						elseif nz > 0 then b[k + 6]
						else b[k + 3]
					t.near(if nx ~= 0 then at[1] else at[3], faceAt, 1e-9, `"{s.text}" is on its box's {s.face} face`)
					local lo, hi = if nx ~= 0 then b[k + 3] else b[k + 1], if nx ~= 0 then b[k + 6] else b[k + 4]
					local mid = if nx ~= 0 then at[3] else at[1]
					t.truthy(mid - w / 2 >= lo - 1e-9 and mid + w / 2 <= hi + 1e-9, `"{s.text}" fits its face across`)
					t.truthy(
						at[2] - h / 2 >= b[k + 2] - 1e-9 and at[2] + h / 2 <= b[k + 5] + 1e-9,
						`"{s.text}" fits its face`
					)
					-- seen: nothing solid lies against the face at the sign's middle or its two ends, and there is
					-- somewhere to read it from (two studs of air in front of it)
					for _, side in { -0.45, 0, 0.45 } do
						local x = at[1] + nx * 0.05 + (if nx == 0 then side * w else 0)
						local z = at[3] + nz * 0.05 + (if nz == 0 then side * w else 0)
						t.eq(
							(arena.sweep(x, at[2], z, x + nx * 2, at[2], z + nz * 2)),
							nil,
							`"{s.text}" at ({at[1]}, {at[2]}, {at[3]}) is behind something`
						)
					end
					if s.text == "TO THE MATCH >" then
						-- in a spawn room, on a baffle: the gap round the baffle's end is to the reader's right
						arrows += 1
						local right = if s.face == "+z" then 1 else -1
						local gap = (if right > 0 then b[k + 4] else b[k + 1]) + right * 2
						t.eq(
							(arena.sweep(gap, at[2] + 1, at[3] + nz * 2, gap, at[2] + 1, at[3] - nz * 3)),
							nil,
							"the arrow points at the gap past the baffle's end"
						)
						local team = if at[1] < 0 then 1 else 2
						t.truthy(Arena.inRoom(arena.spawnRooms[team], at[1], at[2], at[3] + nz * 2))
					end
					local level = math.floor(at[2] / H)
					if #s.text == 1 and tonumber(s.text) ~= nil then
						t.eq(tonumber(s.text), level + 1, "a pillar's number is its storey's, counted from 1")
						digits[level] = (digits[level] or 0) + 1
					elseif s.text == "STAIRS" then
						stairs[level] = (stairs[level] or 0) + 1
					else
						named[level] = (named[level] or 0) + 1
					end
				end
			end
			t.truthy(painted >= 200, `{painted} painted signs`)
			t.eq(arrows, 4, "each spawn room says the way to the match on both baffles")
			for level = 0, Arena.FLOORS - 1 do
				-- (and, from the first floor up, inside each stair core beside the door to the concourse)
				t.eq(
					digits[level],
					if level == 0 then 16 else 18,
					`storey {level}: its number on four faces of four pillars, and in both cores`
				)
				t.truthy((stairs[level] or 0) >= 4, `storey {level}: STAIRS over the cores' doors`)
				t.truthy((named[level] or 0) >= 16, `storey {level}: {named[level]} names and notices`)
			end
			for _, text in
				{
					"STUDIO A",
					"STUDIO B",
					"NEWS STUDIO",
					"MASTER CONTROL",
					"TAPE LIBRARY",
					"ORANGE TEAM",
					"TEAL TEAM",
					"LONDON\n10:59", -- the newsroom's clocks stopped a minute before the news at six
				}
			do
				t.truthy(words[text], `{text} is written somewhere`)
			end
			-- the part list lays each out inside its face
			local rects = 0
			for _, p in PartList.solids(plan) do
				for _, s in p.signs or {} do
					local r = s.rect
					if r and not s.paint then
						rects += 1
						t.truthy(
							r[1] >= -1e-9 and r[2] >= -1e-9 and r[1] + r[3] <= 1 + 1e-9 and r[2] + r[4] <= 1 + 1e-9
						)
						t.truthy(r[3] > 0.02 and r[4] > 0.02, "a sign is big enough to read")
					end
				end
			end
			t.eq(rects, painted)
			-- the station's monitors: on every storey some hang from the ceiling, over every head, their screens
			-- looking along the concourse and the gallery; the two teams' sides have the same number
			for level = 0, Arena.FLOORS - 1 do
				local hung, sides = 0, { 0, 0 }
				for i, _ in plan.monitors do
					local k = (i - 1) * 6
					local b = plan.boxes
					if math.floor(b[k + 2] / H) == level and b[k + 2] - level * H >= 8 then
						hung += 1
						t.truthy(b[k + 2] - level * H >= Arena.HEADROOM + 2, "a hung monitor is over every head")
						local side = if (b[k + 1] + b[k + 4]) / 2 + (b[k + 3] + b[k + 6]) / 2 < 0 then 1 else 2
						sides[side] += 1
					end
				end
				t.eq(hung, 4, `storey {level} has four hung monitors`)
				t.eq(sides[1], sides[2])
			end
		end
	)

	t.test(
		"the marks: tape, cables, stains and papers lie on the faces of boxes; both teams' sides the same",
		function()
			local b = plan.boxes
			local e = 1e-9
			local sides = { 0, 0 }
			local tops, walls, words = 0, 0, {} :: { [string]: { number } }
			local exits = 0
			local byStorey: { [number]: number } = {}
			for _, m in plan.marks do
				local k = (m.box - 1) * 6
				local at, w, h = m.at, m.w, m.h
				t.truthy(PartList.TONE[m.tone] ~= nil, `the tone {m.tone} is a colour`)
				t.truthy(w > 0.05 and h > 0.05)
				if m.face == "+y" then
					tops += 1
					t.near(at[2], b[k + 5], e, "a floor mark is on its box's top")
					t.truthy(at[1] - w / 2 >= b[k + 1] - e and at[1] + w / 2 <= b[k + 4] + e, "and within it along x")
					t.truthy(at[3] - h / 2 >= b[k + 3] - e and at[3] + h / 2 <= b[k + 6] + e, "and along z")
					-- it is somewhere a floor is: the walking surface, a stage or a desk's top, never a ceiling fitting
					local level = math.floor((at[2] + 0.01) / Arena.FLOOR_HEIGHT)
					t.truthy(
						at[2] - level * Arena.FLOOR_HEIGHT <= math.max(Arena.RAIL_HEIGHT, Arena.COVER_HEIGHT) + 1e-6,
						"no higher than a desk"
					)
					byStorey[level] = (byStorey[level] or 0) + 1
				else
					walls += 1
					local alongX = m.face == "+z" or m.face == "-z"
					local plane = if m.face == "+z"
						then b[k + 6]
						elseif m.face == "-z" then b[k + 3]
						elseif m.face == "+x" then b[k + 4]
						else b[k + 1]
					t.near(if alongX then at[3] else at[1], plane, e, `a wall mark is on its box's {m.face} face`)
					local mid = if alongX then at[1] else at[3]
					local lo, hi = if alongX then b[k + 1] else b[k + 3], if alongX then b[k + 4] else b[k + 6]
					t.truthy(mid - w / 2 >= lo - e and mid + w / 2 <= hi + e)
					t.truthy(at[2] - h / 2 >= b[k + 2] - e and at[2] + h / 2 <= b[k + 5] + e)
				end
				local text = m.text
				if text then
					t.eq(m.face, "+y", "only a floor has words among the marks")
					words[text] = at
				end
				-- which team's half: the middle of the atrium's floor is nobody's; the way out is one, in the south
				if m.tone == "exit" then
					exits += 1
					local x, z = at[1], at[3]
					t.truthy(
						math.abs(x) <= 3 + e and z >= 55 - e and z <= Arena.HALF,
						"the way out's paint is at its alcove"
					)
				elseif math.abs(at[1]) > 5 or math.abs(at[3]) > 5 then
					local side = if at[1] + at[3] < 0 then 1 else 2
					sides[side] += w * h -- (by area: a wall cut into pieces on one side is whole on the other)
				end
			end
			t.truthy(#plan.marks >= 300, `{#plan.marks} marks`)
			-- the transmitter's cabinets have doors: on every long face but the one that says DANGER, a seam every
			-- four studs and on each door a meter, three lamps and a vent
			local transmitter = table.find(ArenaDataPlan.LOOKS, "transmitter")
			local cabinets, faced = 0, 0
			for i, look in plan.looks do
				-- (the hall's, on the top storey: telecine's machines below wear the same look)
				if look ~= transmitter or plan.boxes[(i - 1) * 6 + 2] < 4 * Arena.FLOOR_HEIGHT - 0.01 then
					continue
				end
				cabinets += 1
				for _, face in { "+z", "-z" } do
					local meters, seams = 0, 0
					for _, m in plan.marks do
						if m.box == i and m.face == face then
							meters += if m.tone == "meter" then 1 else 0
							seams += if m.tone == "seam" then 1 else 0
						end
					end
					local warned = false
					for _, sign in plan.signs do
						warned = warned or (sign.box == i and sign.face == face)
					end
					if not warned then
						faced += 1
						t.eq(meters, 4, `transmitter {i} {face}: four doors with meters`)
						t.eq(seams, 3, `transmitter {i} {face}: three seams`)
					end
				end
			end
			t.eq(cabinets, 8)
			t.eq(faced, 14)
			t.truthy(tops >= 200 and walls >= 100, `{tops} on floors and tops, {walls} on walls`)
			t.near(sides[1], sides[2], 1e-6)
			t.eq(exits, 3, "the way out: its line on the floor and its two jambs")
			for level = 0, Arena.FLOORS - 1 do
				t.truthy((byStorey[level] or 0) >= 12, `storey {level} has {byStorey[level]} marks on its floors`)
			end
			-- each team's name is on the floor of its own spawn room; the station's number on the atrium's
			for team, name in { "ORANGE TEAM", "TEAL TEAM" } do
				local at = words[name]
				t.truthy(at ~= nil, `{name} is on a floor`)
				t.truthy(
					Arena.inRoom(arena.spawnRooms[team], at[1], at[2] + 1, at[3]),
					`{name} is in team {team}'s room`
				)
			end
			t.truthy(words["7"] ~= nil and math.abs(words["7"][1]) < 1 and words["7"][2] == 0)
			-- every colour a sign is written in is one too
			for _, sign in plan.signs do
				t.truthy(PartList.TONE[sign.tone] ~= nil, `the tone {sign.tone}`)
				t.truthy(sign.bg == nil or PartList.TONE[sign.bg] ~= nil)
			end
			-- the part list lays each mark out inside its face, as paint
			local laid = 0
			for _, p in PartList.solids(plan) do
				for _, sign in p.signs or {} do
					if sign.paint then
						laid += 1
						local r = sign.rect :: { number }
						t.truthy(
							r[1] >= -1e-9 and r[2] >= -1e-9 and r[1] + r[3] <= 1 + 1e-9 and r[2] + r[4] <= 1 + 1e-9
						)
						t.truthy(r[3] > 0 and r[4] > 0)
						t.truthy((sign.bg ~= nil) == (sign.text == " "), "a mark is a colour or it is words")
					end
				end
			end
			t.eq(laid, #plan.marks)
		end
	)

	t.test(
		"what dresses the inside is boxes too: ceilings under floors, glass on lamps, the test card, the van",
		function()
			local b = plan.boxes
			local byLook: { [string]: { number } } = {}
			for i = 1, n do
				local look = ArenaDataPlan.LOOKS[plan.looks[i]]
				byLook[look] = byLook[look] or {}
				table.insert(byLook[look], i)
			end
			local function touches(i: number, j: number): boolean
				local p, q = (i - 1) * 6, (j - 1) * 6
				local e = 1e-6
				return b[p + 1] <= b[q + 4] + e
					and b[q + 1] <= b[p + 4] + e
					and b[p + 2] <= b[q + 5] + e
					and b[q + 2] <= b[p + 5] + e
					and b[p + 3] <= b[q + 6] + e
					and b[q + 3] <= b[p + 6] + e
			end
			-- a storey's slab is a ceiling with a floor on it: the same footprint, nothing between
			for level = 0, Arena.FLOORS - 1 do
				local ceilings = byLook[`ceiling{level}`] or {}
				t.truthy(#ceilings >= 4, `storey {level} has a ceiling of its own`)
				local over = if level == Arena.FLOORS - 1 then "roof" else `floor{level + 1}`
				for _, i in ceilings do
					local k = (i - 1) * 6
					t.eq(plan.kinds[i], Arena.KIND.slab)
					t.near(
						b[k + 2],
						(level + 1) * Arena.FLOOR_HEIGHT - (if level == Arena.FLOORS - 1 then 0 else 1),
						1e-9
					)
					local found = false
					for _, j in byLook[over] do
						local q = (j - 1) * 6
						if
							b[q + 1] == b[k + 1]
							and b[q + 3] == b[k + 3]
							and b[q + 4] == b[k + 4]
							and b[q + 6] == b[k + 6]
							and b[q + 2] == b[k + 5]
						then
							found = true
							t.near(b[q + 5] - b[k + 2], 1, 1e-9, "the two layers make a slab a stud thick")
						end
					end
					t.truthy(found, `ceiling box {i} has its floor on it`)
				end
				t.truthy(PartList.LOOK[`ceiling{level}`][1] ~= PartList.LOOK[over][1], "and is not its colour")
			end
			-- every lamp's glass is on a lamp
			local lenses = 0
			for _, look in { "lens_lit", "lens_dead" } do
				for _, i in byLook[look] or {} do
					lenses += 1
					local on = false
					for _, j in byLook.lamp do
						on = on or touches(i, j)
					end
					for _, j in byLook.container do
						on = on or touches(i, j) -- (the van's headlamps; on its twin, the container's reflectors)
					end
					for _, j in byLook.van_cab do
						on = on or touches(i, j)
					end
					t.truthy(on, `lens box {i} is on a lamp`)
				end
			end
			t.truthy(lenses >= 80, `{lenses} lamps have glass`)
			-- a planter has dry soil in it and dead leaves on the soil: paint on its top, nothing solid (a ball aimed
			-- over low cover flies over what lies on it), and a console's keys are paint the same way
			local painted: { [string]: number } = {}
			for _, m in plan.marks do
				local look = ArenaDataPlan.LOOKS[plan.looks[m.box]]
				if m.face == "+y" and (look == "planter" or look == "console") then
					painted[m.tone] = (painted[m.tone] or 0) + 1
					t.eq(plan.kinds[m.box], Arena.KIND.cover, "paint on low cover")
				end
			end
			t.truthy((painted.soil or 0) >= 12, `{painted.soil} planters with soil`)
			t.truthy((painted.leaf or 0) >= 40, `{painted.leaf} dead leaves`)
			t.truthy((painted.keys or 0) >= 16 and (painted.keys_lamp or 0) >= 16, "consoles have keys")
			t.truthy(#(byLook.planter or {}) >= 12)
			-- a stair core is lit: from the first floor up each has a bulkhead light on its wall over the door to
			-- the concourse, above every head, and it gives light
			local lit: { [number]: boolean } = {}
			for _, l in plan.lamps do
				lit[l.box] = true
			end
			local perStorey: { [number]: number } = {}
			for _, i in byLook.bulkhead or {} do
				local k = (i - 1) * 6
				local level = math.floor(b[k + 2] / Arena.FLOOR_HEIGHT)
				perStorey[level] = (perStorey[level] or 0) + 1
				t.truthy(lit[i], "a bulkhead light is lit")
				t.truthy(
					b[k + 2] - level * Arena.FLOOR_HEIGHT >= ArenaDataPlan.DOOR + 1,
					"over the door, over every head"
				)
				local z = math.abs((b[k + 3] + b[k + 6]) / 2)
				t.truthy(
					z > 22 and z < 30 and math.abs(b[k + 1]) <= Arena.ATRIUM and math.abs(b[k + 4]) <= Arena.ATRIUM
				)
			end
			for level = 1, Arena.FLOORS - 1 do
				t.eq(perStorey[level], 2, `storey {level}: a light in each core`)
			end
			-- the test card: seven bars side by side on each core's front, on the third storey
			local span: { { number } } = { { math.huge, -math.huge }, { math.huge, -math.huge } }
			for _, look in { "bar_white", "bar_yellow", "bar_cyan", "bar_green", "bar_magenta", "bar_red", "bar_blue" } do
				local list = byLook[look] or {}
				t.eq(#list, 2, `the {look} of the north core's card and of the south's`)
				for _, i in list do
					local k = (i - 1) * 6
					t.eq(math.floor(b[k + 2] / Arena.FLOOR_HEIGHT), 3)
					t.near(b[k + 6] - b[k + 3], 0.15, 1e-9, "a bar is paint-thin, proud of the wall")
					local side = if b[k + 3] < 0 then 1 else 2
					span[side][1] = math.min(span[side][1], b[k + 1])
					span[side][2] = math.max(span[side][2], b[k + 4])
				end
			end
			t.near(span[1][2] - span[1][1], 14, 1e-9)
			t.near(span[2][2] - span[2][1], 14, 1e-9)
			-- the outside-broadcast van, east of the atrium: six wheels, a windscreen, a dish; make-up has mirrors
			t.eq(#byLook.tyre, 6)
			t.eq(#byLook.windscreen, 1)
			t.eq(#byLook.dish, 1)
			t.truthy(b[(byLook.windscreen[1] - 1) * 6 + 1] > 0, "the van is the east one")
			t.eq(#byLook.mirror, 4)
			t.eq(#byLook.mirror, #byLook.bulbs)
			t.truthy(#byLook.tapes_a + #byLook.tapes_b >= 150, "the shelving carries its stock")
			-- an ABANDONED station: most of its ceiling fittings are dead (the spawn rooms' own are the only ones
			-- whole), and the few still working are dim
			local strips = 0
			for _, i in byLook.ceiling_light do
				local k = (i - 1) * 6
				local spawnRoom = math.abs(b[k + 1]) >= 44 and math.abs(b[k + 3]) <= 12
				if not spawnRoom then
					strips += 1
				end
			end
			t.truthy(#byLook.ceiling_dead >= 2 * strips, `{#byLook.ceiling_dead} dead fittings, {strips} working`)
			for _, l in plan.lamps do
				if ArenaDataPlan.LOOKS[plan.looks[l.box]] == "ceiling_light" then
					t.truthy(l.brightness <= 1, "a working fitting is dim")
				end
			end
		end
	)

	t.test(
		"no two parts flicker: no faces of different looks lie in one plane over one another in plain sight",
		function()
			-- what stands outside against the building hides a face as a box does
			local covers: { number } = {}
			for _, p in PartList.dressing(venue) do
				local x0, y0, z1 = Arena.ofSite(p.x0, p.y0, p.d0)
				local x1, y1, z0 = Arena.ofSite(p.x1, p.y1, p.d1)
				for _, v in { x0, y0, z0, x1, y1, z1 } do
					table.insert(covers, v)
				end
			end
			local found = Flicker.find(plan, covers)
			local first = found[1]
			t.eq(
				#found,
				0,
				if first
					then `{#found} pairs, the first boxes {first.a} and {first.b} on {first.face} at {first.plane} (lune run tools/games/paintball/arena/seams.luau)`
					else nil
			)
			-- and the finder finds one: a box set into the atrium's floor, flush with it
			local broken = ArenaDataPlan.build()
			for _, v in { -2, -0.5, -2, 2, 0, 2 } do
				table.insert(broken.boxes, v)
			end
			table.insert(broken.kinds, Arena.KIND.prop)
			table.insert(broken.looks, table.find(ArenaDataPlan.LOOKS, "crate") :: number)
			local pairs_ = Flicker.find(broken)
			t.eq(#pairs_, 1)
			t.eq(pairs_[1].face, "+y")
			t.eq(pairs_[1].area, 16)
		end
	)

	t.test("the dressing is outside the arena: the lobby annex with the pass desk and its windows, the mast", function()
		local parts = PartList.dressing(venue)
		t.truthy(#parts > 300 and #parts < 800, `{#parts} parts of dressing`)
		local names: { [string]: number } = {}
		local lobbyMonitor = 0
		for _, p in parts do
			names[p.name] = (names[p.name] or 0) + 1
			t.truthy(p.group == "Lobby" or p.group == "Outside")
			t.eq(p.box, nil)
			-- outside the volume and its walls: in the arena frame, beyond 61 sideways, under -1 or over 71
			local x0, y0, z1 = Arena.ofSite(p.x0, p.y0, p.d0)
			local x1, y1, z0 = Arena.ofSite(p.x1, p.y1, p.d1)
			local e = Arena.HALF + 1
			local inside = x1 > -e + 1e-6
				and x0 < e - 1e-6
				and z1 > -e + 1e-6
				and z0 < e - 1e-6
				and y1 > -1 + 1e-6
				and y0 < Arena.HEIGHT + 1 - 1e-6
			t.falsy(inside, `{p.group}.{p.name} is inside the arena`)
			if p.name == Arena.MONITOR then
				lobbyMonitor += 1
				t.eq(p.screen, "Back", "the lobby's monitor faces the room")
			end
		end
		t.eq(lobbyMonitor, 1)
		for _, name in
			{
				"Counter",
				"Board",
				"GateSign",
				"WindowSill",
				"Bench",
				"Plinth",
				"Step",
				"Sign",
				"Pane",
				"MastLeg",
				"MastLamp",
				"Parapet",
			}
		do
			t.truthy((names[name] or 0) >= 1, `the dressing has a {name}`)
		end
		t.eq(names.Counter, 2, "the pass desk and the garb counter")
		-- the pass desk's counter is at the desk's prompt, the lobby's floor is under the gate, the desk and the
		-- place people are put when they leave
		local function under(point: { x: number, y: number, z: number }, name: string): boolean
			local X, _, D = Arena.toSite(point.x, point.y, point.z)
			for _, p in parts do
				if p.name == name and X >= p.x0 and X <= p.x1 and D >= p.d0 and D <= p.d1 then
					return true
				end
			end
			return false
		end
		t.truthy(under(Arena.GATE, "Floor") and under(Arena.DESK, "Floor") and under(arena.lobby, "Floor"))
		t.truthy(
			under({ x = Arena.DESK.x, y = 0, z = Arena.DESK.z - 3 }, "Counter"),
			"the counter is in front of the desk's prompt"
		)
		t.falsy(under(Arena.DESK, "Counter") or under(Arena.GATE, "Counter") or under(arena.lobby, "Counter"))
		-- the plinth goes down to the lowest ground under the site
		local lowest = math.huge
		for _, p in parts do
			if p.name == "Plinth" then
				lowest = math.min(lowest, p.y0)
			end
		end
		t.truthy(lowest <= -(venue.floorY - venue.ground.min), `the plinth reaches {lowest}`)
		-- the mast stands at the venue's anchor and is a mast
		local topOfMast = -math.huge
		for _, p in parts do
			if string.sub(p.name, 1, 4) == "Mast" then
				topOfMast = math.max(topOfMast, p.y1)
			end
		end
		t.truthy(topOfMast - (Arena.HEIGHT + 1) >= 70, "the mast is some eighty studs tall")
	end)

	-- The review (2026-11-13): "from outside the building does not read as abandoned: neat, identical boarded
	-- windows, the sign whole". The pictures are pb_18_outside and pb_25_forecourt (docs/renders/paintball).
	t.test(
		"from the street the station is left to rot: boards gone, hanging and smashed through, a letter off the sign, a fence with a panel down, weeds, a dead van",
		function()
			local parts = PartList.dressing(venue)
			local panes, smashed, hanging = 0, 0, 0
			local boards = 0
			local named: { [string]: number } = {}
			for _, p in parts do
				named[p.name] = (named[p.name] or 0) + 1
				if p.name == "Pane" then
					panes += 1
					if p.color[1] < 10 then
						smashed += 1
					end
				elseif p.name == "Board" then
					boards += 1
					if p.tilt ~= nil then
						hanging += 1
					end
				end
			end
			t.truthy(boards < 2 * panes - 10, `{boards} boards over {panes} windows: some have lost theirs`)
			t.truthy(smashed >= 3, `{smashed} windows smashed through`)
			t.truthy(hanging >= 3, `{hanging} boards hanging`)
			local sign, letter = nil, nil
			for _, p in parts do
				if p.name == "Sign" then
					sign = p
				elseif p.name == "SignLetter" then
					letter = p
				end
			end
			assert(sign ~= nil and letter ~= nil, "the sign and its fallen letter")
			t.truthy(sign.signs ~= nil and (sign.signs :: any)[1].text ~= "WBLW 7", "a letter is missing from the sign")
			t.eq((letter.signs :: any)[1].text, "L")
			t.truthy(
				(named.FenceDown or 0) == 1 and (named.Fence or 0) >= 8,
				"a fence along the street with one panel down"
			)
			t.truthy((named.Weeds or 0) >= 10)
			t.truthy((named.Van or 0) == 1 and (named.VanWheel or 0) == 4)
			t.truthy((named.Rust or 0) >= 5)
			-- the fence keeps clear of the walk (arena x -4 .. 4) and the van keeps off the walk and the landing
			for _, p in parts do
				local x0, _, _ = Arena.ofSite(p.x0, p.y0, p.d0)
				local x1, _, _ = Arena.ofSite(p.x1, p.y1, p.d1)
				if string.sub(p.name, 1, 5) == "Fence" or string.sub(p.name, 1, 3) == "Van" then
					t.truthy(math.min(x0, x1) >= 4 or math.max(x0, x1) <= -4, `{p.name} on the walk`)
				end
			end
		end
	)

	local function bake(place: AlleyLayout.Place): (any, any, { [string]: any })
		local folder = roblox.Instance.new("Folder")
		local places = { [Contract.SITE] = place }
		local out = GameBakes.venueSites(roblox, folder, Games.stations(places), places, { [Contract.SITE] = venue })
		return folder, out, places
	end

	t.test("the bake: Arena.MODEL on the TV station's site, every solid where its box is, inside the budget", function()
		local place: AlleyLayout.Place =
			{ x = venue.place.x, z = venue.place.z, floorY = venue.place.floorY, yaw = venue.place.yaw }
		local folder, out = bake(place)
		t.eq(out.sites, 1)
		t.deepEq(out.built, { Contract.STATION, Contract.DESK })
		t.truthy(out.parts <= venue.partBudget, `{out.parts} parts for a budget of {venue.partBudget}`)
		local site = folder:FindFirstChild(Contract.SITE) :: any
		t.truthy(site ~= nil and site:GetAttribute("Site") == Contract.SITE)
		t.eq(#site:GetChildren(), 1, "the desk's station built nothing of its own")
		local model = site:FindFirstChild(Arena.MODEL) :: any
		t.truthy(model ~= nil and model:IsA("Model"))
		t.eq(model:GetAttribute("Boxes"), n)
		for _, name in { "Floor0", "Floor1", "Floor2", "Floor3", "Floor4", "Roof", "Lobby", "Outside" } do
			local group = model:FindFirstChild(name) :: any
			t.truthy(group ~= nil and group:IsA("Model"), name)
		end
		t.eq(#model:GetChildren(), 8)
		-- every part, against the arena placed in the world
		local where = Arena.placeOf(place)
		local wx, wy, wz = Arena.toWorld(where, 0, 0, 0)
		t.deepEq(
			{ wx, wy, wz },
			{ Arena.PLACE.x, Arena.PLACE.y, Arena.PLACE.z },
			"the data puts the arena where Arena.PLACE says"
		)
		local seen: { [number]: boolean } = {}
		local monitors, curtains, ramps, lights, parts, guis = 0, { 0, 0 }, 0, 0, 0, 0
		for _, d in model:GetDescendants() do
			if d:IsA("PointLight") then
				lights += 1
				t.falsy(d.Shadows)
				t.eq(d:GetAttribute("ArenaLight"), true, "a light says it is the arena's (a client may switch it off)")
			end
			-- PB-15: nothing of the building's inside or the lobby is drawn from the town
			if d:IsA("SurfaceGui") then
				guis += 1
				local outside = d:FindFirstAncestor("Outside") ~= nil
				if outside then
					t.eq(d.MaxDistance, 0, "the street's signs are seen from anywhere")
				else
					t.truthy(
						d.MaxDistance > 0 and d.MaxDistance <= 160,
						`{d:GetFullName()} is drawn from {d.MaxDistance}`
					)
					if d.Name == "Paint" then
						t.truthy(d.MaxDistance <= 2 * Arena.HALF)
					end
				end
			end
			if not d:IsA("BasePart") then
				continue
			end
			parts += 1
			t.truthy(d.Anchored, `{d.Name} is anchored`)
			local i = d:GetAttribute("Box")
			local lx, ly, lz = Arena.toLocal(where, d.CFrame.Position.X, d.CFrame.Position.Y, d.CFrame.Position.Z)
			if i ~= nil then
				seen[i] = true
				local k = (i - 1) * 6
				local b = arena.boxes
				t.truthy(
					math.abs(lx - (b[k + 1] + b[k + 4]) / 2) < 1e-3
						and math.abs(ly - (b[k + 2] + b[k + 5]) / 2) < 1e-3
						and math.abs(lz - (b[k + 3] + b[k + 6]) / 2) < 1e-3,
					`box {i}'s part is at ({lx}, {ly}, {lz})`
				)
				t.truthy(
					math.abs(d.Size.X - (b[k + 4] - b[k + 1])) < 1e-3
						and math.abs(d.Size.Y - (b[k + 5] - b[k + 2])) < 1e-3
						and math.abs(d.Size.Z - (b[k + 6] - b[k + 3])) < 1e-3,
					`box {i}'s part is the box's size`
				)
				t.truthy(d.CanCollide and d.CanQuery and d.Transparency < 0.9, `box {i}'s part is solid and seen`)
			elseif d.Name == "Ramp" then
				ramps += 1
				-- (walked on, unseen; the engine's raycast meets it whatever CanQuery says, so it is named and numbered
				-- for a ray to leave out)
				t.truthy(d.CanCollide and d.Transparency == 1 and d:GetAttribute("Ramp") ~= nil)
			else
				-- anything else inside the arena is plainly not solid
				if Arena.inVolume(lx, ly, lz) then
					t.falsy(d.CanCollide, `{d.Name} inside the arena is solid without a box`)
					t.truthy(
						string.sub(d.Name, 1, #Arena.CURTAIN) == Arena.CURTAIN,
						`{d.Name} inside the arena has no box`
					)
				end
			end
			if d.Name == Arena.MONITOR then
				monitors += 1
				local screen = d:FindFirstChild("Screen") :: any
				t.truthy(screen ~= nil and screen:IsA("SurfaceGui"), "a monitor has its Screen")
				t.eq(screen.Face.Name, d:GetAttribute("ScreenFace"))
				local label = screen:FindFirstChild("Text") :: any
				t.truthy(label ~= nil and label:IsA("TextLabel") and label.Text ~= "")
			end
			for team = 1, 2 do
				if d.Name == Arena.CURTAIN .. team then
					curtains[team] += 1
					t.truthy(not d.CanCollide and d.Transparency > 0.2 and d.Transparency < 1)
					local a, b = arena.curtains[team][1], arena.curtains[team][2]
					local hangs = Arena.inRoom(a, lx, ly, lz) or Arena.inRoom(b, lx, ly, lz)
					t.truthy(hangs, `a curtain of team {team} hangs in its doorway`)
					t.near(d.Size.Y, Arena.HEADROOM, 1e-3)
				end
			end
		end
		for i = 1, n do
			t.truthy(seen[i], `box {i} was not baked`)
		end
		t.eq(parts, out.parts)
		t.eq(ramps, #arena.ramps)
		t.deepEq(curtains, { 2, 2 })
		t.truthy(monitors >= 13, `{monitors} monitors, the lobby's among them`)
		t.truthy(lights >= 40 and lights <= 120, `{lights} lights`)
		t.truthy(guis <= 480, `{guis} SurfaceGuis`)
		-- the marks are labels in a SurfaceGui named Paint, lit by the room; each label lies in the world where
		-- the plan put its mark (a Top face's canvas runs left to right along the part's X and top to bottom
		-- along its Z, as tools/review/attractions_export draws it)
		local byBox: { [number]: any } = {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("Box") ~= nil then
				byBox[d:GetAttribute("Box")] = d
			end
		end
		local labels = 0
		for _, d in model:GetDescendants() do
			if d:IsA("SurfaceGui") and d.Name == "Paint" then
				t.eq(d.LightInfluence, 1)
				labels += #d:GetChildren()
				-- one face's marks are stacked in the plan's order, each over the one before (a meter on a door)
				local z = {}
				for _, label in d:GetChildren() do
					z[label.ZIndex] = true
				end
				for k = 1, #d:GetChildren() do
					t.truthy(z[k], `a Paint's labels are stacked 1 to n ({k})`)
				end
			end
		end
		t.eq(labels, #plan.marks)
		local placed = 0
		for i, m in plan.marks do
			if m.face ~= "+y" or i % 5 ~= 0 then
				continue
			end
			local part = byBox[m.box]
			local found = false
			for _, g in part:GetChildren() do
				if g:IsA("SurfaceGui") and g.Name == "Paint" and g.Face.Name == "Top" then
					for _, label in g:GetChildren() do
						local cx = label.Position.X.Scale + label.Size.X.Scale / 2
						local cz = label.Position.Y.Scale + label.Size.Y.Scale / 2
						local world = part.CFrame:PointToWorldSpace(
							roblox.Vector3.new((cx - 0.5) * part.Size.X, part.Size.Y / 2, (cz - 0.5) * part.Size.Z)
						)
						local lx, ly, lz = Arena.toLocal(where, world.X, world.Y, world.Z)
						if
							math.abs(lx - m.at[1]) < 1e-3
							and math.abs(ly - m.at[2]) < 1e-3
							and math.abs(lz - m.at[3]) < 1e-3
							and math.abs(label.Size.X.Scale * part.Size.X - m.w) < 1e-3
							and math.abs(label.Size.Y.Scale * part.Size.Z - m.h) < 1e-3
						then
							found = true
						end
					end
				end
			end
			t.truthy(found, `mark {i} is painted where the plan put it`)
			placed += 1
		end
		t.truthy(placed >= 40)
		-- the station's prompts are in the lobby the bake made: on its floor, clear of the counters
		local floor = (model:FindFirstChild("Lobby") :: any):FindFirstChild("Floor") :: any
		for _, st in Games.stations({ [Contract.SITE] = place }) do
			if st.game == Contract.GAME then
				local x, y, z = AlleyLayout.toWorld(place, st.x, st.y, st.d)
				local rel = floor.CFrame:PointToObjectSpace(roblox.Vector3.new(x, y, z))
				t.truthy(
					math.abs(rel.X) < floor.Size.X / 2 and math.abs(rel.Z) < floor.Size.Z / 2,
					`{st.id} is over the lobby's floor`
				)
				t.near(rel.Y - floor.Size.Y / 2, 3, 1e-3, "three studs over it")
			end
		end
	end)

	t.test("the bake on a site turned and moved: the parts follow the arena's frame", function()
		local place: AlleyLayout.Place = { x = -310, z = 95, floorY = 21.5, yaw = 0.7 }
		local folder = bake(place)
		local model = (folder:FindFirstChild(Contract.SITE) :: any):FindFirstChild(Arena.MODEL) :: any
		local where = Arena.placeOf(place)
		local ax, ay, az = Arena.dirToWorld(where, 1, 0, 0)
		local checked = 0
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				local i = d:GetAttribute("Box")
				if i ~= nil and i % 7 == 0 then
					checked += 1
					local k = (i - 1) * 6
					local b = arena.boxes
					local x, y, z = Arena.toWorld(
						where,
						(b[k + 1] + b[k + 4]) / 2,
						(b[k + 2] + b[k + 5]) / 2,
						(b[k + 3] + b[k + 6]) / 2
					)
					t.truthy((d.CFrame.Position - roblox.Vector3.new(x, y, z)).Magnitude < 1e-3, `box {i}`)
					-- the part's own X is the arena's x, turned with the site
					t.truthy((d.CFrame.XVector - roblox.Vector3.new(ax, ay, az)).Magnitude < 1e-4)
					t.near(d.Size.X, b[k + 4] - b[k + 1], 1e-3)
				end
			end
		end
		t.truthy(checked > 150)
		-- a monitor's screen faces where the plan says, in the world: an old set on the first floor
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d.Name == Arena.MONITOR and d:GetAttribute("Box") ~= nil then
				local face = plan.monitors[d:GetAttribute("Box")]
				local nx, nz =
					if face == "+x" then 1 elseif face == "-x" then -1 else 0,
					if face == "+z" then 1 elseif face == "-z" then -1 else 0
				local wx, wy, wz = Arena.dirToWorld(where, nx, 0, nz)
				local normals: { [string]: any } = {
					Right = roblox.Vector3.new(1, 0, 0),
					Left = roblox.Vector3.new(-1, 0, 0),
					Back = roblox.Vector3.new(0, 0, 1),
					Front = roblox.Vector3.new(0, 0, -1),
				}
				local normal = normals[d:GetAttribute("ScreenFace")]
				local world = d.CFrame:VectorToWorldSpace(normal)
				t.truthy((world - roblox.Vector3.new(wx, wy, wz)).Magnitude < 1e-4, "the screen faces the plan's way")
			end
		end
	end)
end
