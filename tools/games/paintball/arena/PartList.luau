--!strict
-- tools/games/paintball/arena/PartList: every part of the paintball arena's bake, as a list (checklist PB-5). A PURE
-- FUNCTION OF THE PLAN (ArenaDataPlan through ArenaData.plan()), so that a spec can hold the parts to the
-- collision data without a file: what is drawn solid is exactly what a ball stops on.
--   solids(plan)   one part for each box: the same size in the same place (turned into the SITE's frame with
--                  Arena.toSite: X = x, Y = y, D = 15 - z), its colour and material from the box's look, its
--                  model from the storey it stands on ("Floor0" .. "Floor4", "Roof"). A `monitor` box's part is
--                  named Arena.MONITOR and carries the face its screen is on; signs, marks (paint that is not
--                  a sign: tape, cables on a floor, stains) and lamps ride on their box's part. Then one invisible, collidable part for each stair ramp, lying on its steps
--                  (bodies walk on it; nothing asks it where a ball is), and one see-through, non-colliding
--                  part for each spawn-room curtain, named Arena.CURTAIN .. team, in the team's colour.
--   dressing(venue)   everything OUTSIDE the arena volume, parts only: the lobby annex (floor, walls, roof, the
--                  pass desk and the garb counter in front of the two windows onto the atrium, the lobby's
--                  monitor, benches, lights), and the building from the street (the plinth down to the lowest
--                  ground, the entrance steps, boarded windows on every storey, the sign, the parapet, plant on
--                  the roof and the dead mast). None of it is inside the volume, so none of it needs a box.
-- Interface: solids(plan) -> { Part }; dressing(venue?) -> { Part }; LOOK = { [look name] = { colour, material,
--   transparency? } }; TEAM = { colour of team 1's paint, of team 2's }; FACE = { [arena face] = NormalId name };
--   type Part
local Arena = require("../../../../src/shared/Minigames/Paintball/Arena")
local ArenaDataPlan = require("../../../../src/shared/Minigames/Paintball/ArenaDataPlan")

export type Part = {
	group: string, -- the sub-model of Arena.MODEL it goes in
	name: string,
	-- bounds in the site's frame (tools/bake/alley/Kit: X across, Y above the floor, D into the site)
	x0: number,
	x1: number,
	y0: number,
	y1: number,
	d0: number,
	d1: number,
	color: { number },
	material: string,
	transparency: number?,
	collide: boolean, -- false: plainly not solid
	query: boolean?, -- default = collide
	shadow: boolean?,
	shape: string?, -- "Cylinder" along Y, for the mast's dishes and lamps
	tilt: number?, -- radians about the site's D axis, for a ramp
	box: number?, -- the box it is the part of
	ramp: number?,
	curtain: number?, -- the team whose spawn room it shuts
	screen: string?, -- NormalId: the face a monitor's screen is on
	-- words on a face: filling it, or in `rect` = { left, top, width, height } as fractions of the face (as a
	-- SurfaceGui lays it out for someone looking at it; on a Top face left to right is +x and top to bottom +z),
	-- with a painted panel behind them when `bg` is set. `paint`: one of the plan's marks (a rectangle of the
	-- colour `bg` when it has no words): paint takes the room's light, a sign is lit of itself
	signs: { { face: string, text: string, tone: string, rect: { number }?, bg: string?, paint: boolean? } }?,
	light: { range: number, brightness: number, color: { number } }?,
}

local PartList = {}

-- team 1 is orange, team 2 teal (decision D4: no red)
PartList.TEAM = { { 240, 130, 40 }, { 30, 170, 170 } }

-- an arena face as the NormalId of an unrotated part in the arena frame (+z is a part's Back)
PartList.FACE =
	{ ["+x"] = "Right", ["-x"] = "Left", ["+z"] = "Back", ["-z"] = "Front", ["+y"] = "Top", ["-y"] = "Bottom" }

PartList.TONE = {
	white = { 235, 235, 225 },
	gold = { 240, 200, 90 },
	red = { 235, 60, 50 },
	green = { 90, 220, 120 },
	yellow = { 240, 210, 60 },
	stencil = { 30, 30, 34 },
	plate = { 26, 28, 34 },
	warm = { 255, 214, 170 },
	cold = { 214, 232, 255 },
	-- the plan's marks: tape and chalk on a floor, a cable lying on it, oil, paper, the gold of the station's
	-- number on the atrium's floor; a stain on each storey's floor (darker than it, but dust on the studios'
	-- black); a streak down an outer wall
	tape = { 226, 190, 44 },
	chalk = { 214, 212, 200 },
	cable = { 20, 20, 22 },
	oil = { 50, 50, 54 },
	paper = { 226, 222, 206 },
	floor_gold = { 176, 146, 72 },
	stain0 = { 76, 76, 80 },
	stain1 = { 50, 66, 82 },
	stain2 = { 54, 54, 60 },
	stain3 = { 124, 127, 123 },
	stain4 = { 82, 92, 68 },
	streak = { 100, 94, 86 },
}

local LOOK: { [string]: { any } } = {
	floor0 = { { 92, 92, 94 }, "Concrete" },
	floor1 = { { 62, 80, 98 }, "Fabric" },
	floor2 = { { 40, 40, 44 }, "SmoothPlastic" },
	floor3 = { { 146, 148, 144 }, "Slate" },
	floor4 = { { 98, 108, 82 }, "Fabric" },
	roof = { { 76, 76, 80 }, "Concrete" },
	skylight = { { 170, 200, 210 }, "Glass", 0.7 },
	shell = { { 134, 128, 118 }, "Concrete" },
	glass = { { 196, 220, 224 }, "Glass", 0.86 },
	gate = { { 70, 76, 84 }, "DiamondPlate" },
	shutter = { { 96, 102, 106 }, "CorrodedMetal" },
	wall0 = { { 140, 138, 130 }, "Concrete" },
	wall1 = { { 178, 170, 148 }, "SmoothPlastic" },
	wall2 = { { 64, 62, 70 }, "Fabric" },
	wall3 = { { 112, 126, 132 }, "SmoothPlastic" },
	wall4 = { { 118, 86, 60 }, "WoodPlanks" },
	core = { { 106, 106, 110 }, "Concrete" },
	pillar = { { 152, 148, 140 }, "Concrete" },
	rail = { { 58, 62, 68 }, "Metal" },
	parapet = { { 122, 120, 114 }, "Concrete" },
	step = { { 90, 90, 94 }, "Concrete" },
	landing = { { 100, 100, 104 }, "Concrete" },
	spawn1 = { { 176, 116, 66 }, "SmoothPlastic" },
	spawn2 = { { 58, 138, 138 }, "SmoothPlastic" },
	crate = { { 152, 114, 68 }, "WoodPlanks" },
	drum = { { 136, 98, 60 }, "Wood" },
	case = { { 42, 44, 50 }, "DiamondPlate" },
	van = { { 228, 226, 218 }, "SmoothPlastic" },
	van_cab = { { 44, 84, 160 }, "SmoothPlastic" },
	chassis = { { 28, 28, 30 }, "Metal" },
	container = { { 62, 104, 122 }, "CorrodedMetal" },
	flat = { { 162, 132, 92 }, "WoodPlanks" },
	set_blue = { { 44, 72, 142 }, "SmoothPlastic" },
	set_warm = { { 192, 142, 92 }, "SmoothPlastic" },
	green_screen = { { 44, 172, 74 }, "Fabric" },
	riser = { { 30, 30, 32 }, "Wood" },
	desk = { { 122, 92, 62 }, "Wood" },
	news_desk = { { 212, 202, 182 }, "SmoothPlastic" },
	cubicle = { { 112, 122, 132 }, "Fabric" },
	cabinet = { { 132, 136, 132 }, "Metal" },
	rack = { { 38, 40, 44 }, "Metal" },
	console = { { 72, 76, 82 }, "SmoothPlastic" },
	shelf = { { 92, 86, 72 }, "Metal" },
	camera_base = { { 62, 62, 68 }, "Metal" },
	camera_head = { { 50, 52, 58 }, "SmoothPlastic" },
	lens = { { 16, 16, 20 }, "Glass" },
	truss = { { 152, 156, 162 }, "Metal" },
	lamp = { { 30, 30, 32 }, "Metal" },
	ceiling_light = { { 236, 236, 222 }, "Neon" },
	tray = { { 72, 74, 78 }, "Metal" },
	cable = { { 22, 22, 24 }, "Plastic" },
	monitor = { { 44, 44, 48 }, "SmoothPlastic" },
	cart = { { 92, 94, 100 }, "Metal" },
	sofa = { { 122, 72, 52 }, "Fabric" },
	planter = { { 152, 142, 122 }, "Concrete" },
	on_air = { { 96, 24, 24 }, "SmoothPlastic" },
	locker = { { 72, 98, 112 }, "Metal" },
	transmitter = { { 106, 112, 106 }, "Metal" },
	table = { { 98, 66, 42 }, "Wood" },
	bench = { { 112, 86, 62 }, "Wood" },
	stand = { { 42, 42, 46 }, "Metal" },
	terminal = { { 196, 188, 164 }, "SmoothPlastic" },
	sheet = { { 214, 210, 198 }, "Fabric" },
	ceiling_dead = { { 96, 98, 96 }, "SmoothPlastic" },
	-- the ceilings, by the storey they are over: the dock's bare concrete, the newsroom's tiles, the studios'
	-- black, the control rooms' tiles, and the top storey's stained plaster under the roof
	ceiling0 = { { 118, 116, 112 }, "Concrete" },
	ceiling1 = { { 206, 202, 188 }, "SmoothPlastic" },
	ceiling2 = { { 34, 34, 38 }, "SmoothPlastic" },
	ceiling3 = { { 188, 192, 190 }, "SmoothPlastic" },
	ceiling4 = { { 196, 186, 164 }, "SmoothPlastic" },
	lens_lit = { { 255, 226, 170 }, "Neon" },
	lens_dead = { { 168, 176, 182 }, "Glass" },
	tyre = { { 20, 20, 22 }, "Plastic" },
	windscreen = { { 30, 40, 52 }, "Glass" },
	bumper = { { 160, 164, 168 }, "Metal" },
	van_stripe = { { 232, 132, 40 }, "SmoothPlastic" },
	dish = { { 226, 224, 216 }, "Metal" },
	mirror = { { 186, 210, 222 }, "Glass" },
	bulbs = { { 255, 236, 190 }, "Neon" },
	garb_a = { { 214, 170, 60 }, "Fabric" },
	garb_b = { { 124, 66, 116 }, "Fabric" },
	garb_c = { { 92, 152, 204 }, "Fabric" },
	garb_d = { { 232, 224, 200 }, "Fabric" },
	garb_e = { { 84, 144, 96 }, "Fabric" },
	-- the test card's bars, a little faded
	bar_white = { { 204, 204, 198 }, "SmoothPlastic" },
	bar_yellow = { { 202, 196, 60 }, "SmoothPlastic" },
	bar_cyan = { { 60, 190, 196 }, "SmoothPlastic" },
	bar_green = { { 64, 184, 76 }, "SmoothPlastic" },
	bar_magenta = { { 190, 70, 180 }, "SmoothPlastic" },
	bar_red = { { 196, 62, 54 }, "SmoothPlastic" },
	bar_blue = { { 52, 64, 190 }, "SmoothPlastic" },
	tapes_a = { { 204, 196, 172 }, "SmoothPlastic" },
	tapes_b = { { 96, 118, 140 }, "SmoothPlastic" },
	keys = { { 206, 200, 182 }, "SmoothPlastic" },
	keys_lit = { { 255, 176, 60 }, "Neon" },
	screen = { { 26, 32, 42 }, "Glass" },
}
PartList.LOOK = LOOK

-- what a part of each look is called (a monitor is Arena.MONITOR whatever its look says)
local NAMES: { [string]: string } = {
	shell = "OuterWall",
	glass = "Window",
	gate = "Gate",
	shutter = "Shutter",
	core = "CoreWall",
	spawn1 = "SpawnWall",
	spawn2 = "SpawnWall",
	ceiling_light = "StripLight",
	on_air = "OnAir",
}

local function nameOf(look: string, kind: number): string
	local given = NAMES[look]
	if given then
		return given
	end
	if string.sub(look, 1, 5) == "floor" or look == "roof" or look == "landing" then
		return "Slab"
	elseif string.sub(look, 1, 7) == "ceiling" and look ~= "ceiling_light" and look ~= "ceiling_dead" then
		return "Ceiling"
	elseif string.sub(look, 1, 4) == "wall" then
		return if kind == Arena.KIND.cover then "Sill" else "Wall"
	end
	-- "news_desk" -> "NewsDesk"
	local out = string.gsub(look, "(%a)(%a*)_?", function(a: string, b: string): string
		return string.upper(a) .. b
	end)
	return out
end

function PartList.solids(plan: ArenaDataPlan.Plan): { Part }
	local out: { Part } = {}
	local H = Arena.FLOOR_HEIGHT
	local boxes = plan.boxes
	local byBox: { [number]: Part } = {}
	for i = 1, #plan.kinds do
		local k = (i - 1) * 6
		local x0, y0, z0, x1, y1, z1 =
			boxes[k + 1], boxes[k + 2], boxes[k + 3], boxes[k + 4], boxes[k + 5], boxes[k + 6]
		local look = ArenaDataPlan.LOOKS[plan.looks[i]]
		local style = LOOK[look] or error(`PartList: no style for the look {look}`)
		local X0, Y0, D1 = Arena.toSite(x0, y0, z0)
		local X1, Y1, D0 = Arena.toSite(x1, y1, z1)
		-- the storey it stands on: a slab belongs to the storey whose floor it is
		local level = math.clamp(math.floor((y0 + 1.01) / H), 0, Arena.FLOORS - 1)
		local screen = plan.monitors[i]
		local part: Part = {
			group = if y0 >= Arena.HEIGHT then "Roof" else `Floor{level}`,
			name = if screen then Arena.MONITOR else nameOf(look, plan.kinds[i]),
			x0 = X0,
			x1 = X1,
			y0 = Y0,
			y1 = Y1,
			d0 = D0,
			d1 = D1,
			color = style[1],
			material = style[2],
			transparency = style[3],
			collide = true,
			box = i,
			screen = if screen then PartList.FACE[screen] else nil,
			shadow = if look == "skylight" or look == "glass" or look == "ceiling_light" then false else nil,
		}
		byBox[i] = part
		table.insert(out, part)
	end
	for _, s in plan.signs do
		if s.text ~= "" then
			local part = byBox[s.box]
			local list = part.signs or {}
			local rect: { number }? = nil
			local at, w, h = s.at, s.w, s.h
			if at and w and h then
				-- the face as its SurfaceGui lies: left to right for someone looking at it, top to bottom
				local k = (s.box - 1) * 6
				local x0, y0, z0, x1, y1, z1 =
					boxes[k + 1], boxes[k + 2], boxes[k + 3], boxes[k + 4], boxes[k + 5], boxes[k + 6]
				local u: number, width: number
				if s.face == "+z" then
					u, width = at[1] - x0, x1 - x0
				elseif s.face == "-z" then
					u, width = x1 - at[1], x1 - x0
				elseif s.face == "+x" then
					u, width = z1 - at[3], z1 - z0
				else
					u, width = at[3] - z0, z1 - z0
				end
				local height = y1 - y0
				rect = { (u - w / 2) / width, (y1 - at[2] - h / 2) / height, w / width, h / height }
			end
			table.insert(list, { face = PartList.FACE[s.face], text = s.text, tone = s.tone, rect = rect, bg = s.bg })
			part.signs = list
		end
	end
	for _, m in plan.marks do
		local part = byBox[m.box]
		local list = part.signs or {}
		local k = (m.box - 1) * 6
		local x0, y0, z0, x1, y1, z1 =
			boxes[k + 1], boxes[k + 2], boxes[k + 3], boxes[k + 4], boxes[k + 5], boxes[k + 6]
		local at, w, h = m.at, m.w, m.h
		local rect: { number }
		if m.face == "+y" then
			rect = { (at[1] - w / 2 - x0) / (x1 - x0), (at[3] - h / 2 - z0) / (z1 - z0), w / (x1 - x0), h / (z1 - z0) }
		else
			local u: number, width: number
			if m.face == "+z" then
				u, width = at[1] - x0, x1 - x0
			elseif m.face == "-z" then
				u, width = x1 - at[1], x1 - x0
			elseif m.face == "+x" then
				u, width = z1 - at[3], z1 - z0
			else
				u, width = at[3] - z0, z1 - z0
			end
			rect = { (u - w / 2) / width, (y1 - at[2] - h / 2) / (y1 - y0), w / width, h / (y1 - y0) }
		end
		-- (a mark without words is a label of one space on a ground of its colour)
		table.insert(list, {
			face = PartList.FACE[m.face],
			text = m.text or " ",
			tone = m.tone,
			rect = rect,
			bg = if m.text then nil else m.tone,
			paint = true,
		})
		part.signs = list
	end
	for _, l in plan.lamps do
		byBox[l.box].light = { range = l.range, brightness = l.brightness, color = PartList.TONE[l.tone] }
	end
	-- the ramps: a thin slab lying in the ramp's plane, its top face the walking surface
	local THICK = 0.4
	for i, r in plan.ramps do
		local run, rise = r.maxX - r.minX, r.y1 - r.y0
		local angle = math.atan2(rise, run) * r.dir
		local length = math.sqrt(run * run + rise * rise)
		-- the middle of the surface, then half the slab's thickness down along the plane's normal
		local cx, cy = (r.minX + r.maxX) / 2, (r.y0 + r.y1) / 2
		cx += math.sin(angle) * THICK / 2
		cy -= math.cos(angle) * THICK / 2
		local _, _, D1 = Arena.toSite(0, 0, r.minZ)
		local _, _, D0 = Arena.toSite(0, 0, r.maxZ)
		table.insert(out, {
			group = `Floor{math.floor(r.y0 / H + 0.01)}`,
			name = "Ramp",
			x0 = cx - length / 2,
			x1 = cx + length / 2,
			y0 = cy - THICK / 2,
			y1 = cy + THICK / 2,
			d0 = D0,
			d1 = D1,
			color = { 90, 90, 94 },
			material = "SmoothPlastic",
			transparency = 1,
			collide = true,
			query = false,
			shadow = false,
			tilt = angle,
			ramp = i,
		})
	end
	for team = 1, 2 do
		for _, c in plan.curtains[team] do
			local X0, Y0, D1 = Arena.toSite(c.minX, c.minY, c.minZ)
			local X1, Y1, D0 = Arena.toSite(c.maxX, c.maxY, c.maxZ)
			table.insert(out, {
				group = `Floor{Arena.SPAWN_FLOOR}`,
				name = Arena.CURTAIN .. team,
				x0 = X0,
				x1 = X1,
				y0 = Y0,
				y1 = Y1,
				d0 = D0,
				d1 = D1,
				color = PartList.TEAM[team],
				material = "ForceField",
				transparency = 0.45,
				collide = false,
				shadow = false,
				curtain = team,
			})
		end
	end
	return out
end

-- THE DRESSING, in the arena frame while it is written (z south of the volume is the lobby), turned into the
-- site's at the end. `venue` is the record of generated/Expansion (ground: how deep the plinth goes).
function PartList.dressing(venue: any?): { Part }
	local out: { Part } = {}
	local half, top = Arena.HALF, Arena.HEIGHT
	local function add(
		group: string,
		name: string,
		x0: number,
		y0: number,
		z0: number,
		x1: number,
		y1: number,
		z1: number,
		color: { number },
		material: string,
		more: { [string]: any }?
	): Part
		local X0, Y0, D1 = Arena.toSite(math.min(x0, x1), math.min(y0, y1), math.min(z0, z1))
		local X1, Y1, D0 = Arena.toSite(math.max(x0, x1), math.max(y0, y1), math.max(z0, z1))
		local part: Part = {
			group = group,
			name = name,
			x0 = X0,
			x1 = X1,
			y0 = Y0,
			y1 = Y1,
			d0 = D0,
			d1 = D1,
			color = color,
			material = material,
			collide = true,
		}
		for k, v in more or {} do
			(part :: any)[k] = v
		end
		table.insert(out, part)
		return part
	end
	local CONCRETE, DARK, TRIM = { 134, 128, 118 }, { 60, 62, 66 }, { 206, 196, 170 }
	local WOOD, BOARD = { 122, 92, 62 }, { 150, 118, 76 }
	local ORANGE, TEAL = PartList.TEAM[1], PartList.TEAM[2]
	local ghost = { collide = false, shadow = false }
	local WINDOW = ArenaDataPlan.WINDOW

	-- THE LOBBY ANNEX: z 61 .. 90 (the arena's south wall is its back wall), one storey
	local Z0, Z1, ROOF = half + 1, 90, 13
	add("Lobby", "Floor", -half - 1, -1, Z0, half + 1, 0, Z1 + 1, { 150, 132, 104 }, "WoodPlanks")
	add("Lobby", "Ceiling", -half - 1, ROOF, Z0, half + 1, ROOF + 1, Z1 + 1, { 70, 70, 74 }, "Concrete")
	add("Lobby", "Wall", -half - 1, 0, Z0, -half, ROOF, Z1 + 1, CONCRETE, "Concrete")
	add("Lobby", "Wall", half, 0, Z0, half + 1, ROOF, Z1 + 1, CONCRETE, "Concrete")
	-- the front, with the double door in its middle (entrance "front": 10 wide) and glazing either side
	add("Lobby", "Wall", -half, 0, Z1, -34, ROOF, Z1 + 1, CONCRETE, "Concrete")
	add("Lobby", "Wall", 34, 0, Z1, half, ROOF, Z1 + 1, CONCRETE, "Concrete")
	for _, s in { -1, 1 } do
		add("Lobby", "Wall", s * 34, 0, Z1, s * 5, 2, Z1 + 1, CONCRETE, "Concrete")
		add(
			"Lobby",
			"Window",
			s * 34,
			2,
			Z1 + 0.3,
			s * 5,
			9,
			Z1 + 0.7,
			{ 150, 190, 200 },
			"Glass",
			{ transparency = 0.5, shadow = false }
		)
		add("Lobby", "Wall", s * 34, 9, Z1, s * 5, ROOF, Z1 + 1, CONCRETE, "Concrete")
		add("Lobby", "DoorFrame", s * 5, 0, Z1 - 0.2, s * 5.6, 9, Z1 + 1.2, DARK, "Metal")
		-- a door leaf stood open against the frame
		add("Lobby", "DoorLeaf", s * 5.6, 0, Z1 + 1.2, s * 5.9, 8.6, Z1 + 5.6, { 70, 76, 84 }, "Metal")
	end
	add("Lobby", "Wall", -5, 9, Z1, 5, ROOF, Z1 + 1, CONCRETE, "Concrete")
	local header = add("Lobby", "Header", -9, 9.4, Z1 + 1, 9, 12, Z1 + 1.4, DARK, "Metal")
	header.signs = { { face = "Back", text = "WBLW 7 PAINTBALL", tone = "gold" } }
	-- the arena door's surround and the words over it (the gate itself is a box of the arena's south wall)
	add("Lobby", "GateFrame", -5, 0, Z0, -4, 10, Z0 + 0.6, DARK, "Metal")
	add("Lobby", "GateFrame", 4, 0, Z0, 5, 10, Z0 + 0.6, DARK, "Metal")
	local lintel = add("Lobby", "GateSign", -5, 9, Z0, 5, 11.4, Z0 + 0.6, { 30, 30, 34 }, "SmoothPlastic")
	lintel.signs = { { face = "Back", text = "ARENA", tone = "gold" } }
	local mat = add("Lobby", "GateMat", -4, 0, Z0, 4, 0.1, Z0 + 5, ORANGE, "Fabric", ghost)
	mat.signs = { { face = "Top", text = "JOIN THE MATCH", tone = "stencil" } }
	-- the lobby's monitor, on the wall beside the gate: the live match
	add("Lobby", Arena.MONITOR, 6.5, 4.6, Z0, 15.5, 9.7, Z0 + 0.5, { 44, 44, 48 }, "SmoothPlastic", { screen = "Back" })
	add("Lobby", "MonitorFrame", 6, 4.1, Z0, 16, 10.2, Z0 + 0.3, DARK, "Metal")
	-- the frames of the two windows onto the atrium (the glass is the arena's own)
	for _, s in { -1, 1 } do
		local w0, w1, sill, head = WINDOW[1] - 0.5, WINDOW[2] + 0.5, WINDOW[3], WINDOW[4]
		add("Lobby", "WindowSill", s * w0, sill - 0.5, Z0, s * w1, sill, Z0 + 0.8, TRIM, "SmoothPlastic")
		add("Lobby", "WindowHead", s * w0, head, Z0, s * w1, head + 0.5, Z0 + 0.5, TRIM, "SmoothPlastic")
		add("Lobby", "WindowJamb", s * w0, sill, Z0, s * (w0 + 0.5), head, Z0 + 0.5, TRIM, "SmoothPlastic")
		add("Lobby", "WindowJamb", s * (w1 - 0.5), sill, Z0, s * w1, head, Z0 + 0.5, TRIM, "SmoothPlastic")
	end
	-- the pass desk (west) and the garb counter (east): a counter with the prompt in front of it, a board over it
	local function counter(x: number, text: string, sub: string, color: { number })
		local z = Arena.DESK.z
		add("Lobby", "Counter", x - 7, 0, z - 4, x + 7, 3.2, z - 2, WOOD, "Wood")
		add("Lobby", "CounterTop", x - 7.3, 3.2, z - 4.3, x + 7.3, 3.5, z - 1.7, TRIM, "SmoothPlastic")
		add("Lobby", "CounterEnd", x - 7, 0, z - 9, x - 6, 3.2, z - 4, WOOD, "Wood")
		add("Lobby", "CounterEnd", x + 6, 0, z - 9, x + 7, 3.2, z - 4, WOOD, "Wood")
		local board = add("Lobby", "Board", x - 6, 9.2, z - 3.4, x + 6, 11.8, z - 3, color, "SmoothPlastic")
		board.signs = { { face = "Back", text = text, tone = "white" } }
		add("Lobby", "BoardRod", x - 5, 11.8, z - 3.3, x - 4.8, ROOF, z - 3.1, DARK, "Metal", ghost)
		add("Lobby", "BoardRod", x + 4.8, 11.8, z - 3.3, x + 5, ROOF, z - 3.1, DARK, "Metal", ghost)
		local card =
			add("Lobby", "Card", x - 2, 3.5, z - 3.6, x + 2, 5.2, z - 3.3, { 236, 232, 214 }, "SmoothPlastic", ghost)
		card.signs = { { face = "Back", text = sub, tone = "stencil" } }
		add("Lobby", "Till", x + 3.5, 3.5, z - 3.9, x + 5.5, 4.7, z - 2.4, DARK, "Metal")
	end
	counter(Arena.DESK.x, "PASS DESK", "20c\nFIVE DAYS", ORANGE)
	counter(-Arena.DESK.x, "GARB SHOP", "S$1 A SET", TEAL)
	-- garb on a rail against the back wall east of the east window, in both teams' colours
	local GARB = WINDOW[2] + 4
	for i = 0, 5 do
		local x = GARB + 1 + i * 2
		add(
			"Lobby",
			"Garb",
			x,
			3.8,
			Z0 + 0.5,
			x + 1.4,
			7.4,
			Z0 + 1,
			if i % 2 == 0 then ORANGE else TEAL,
			"Fabric",
			ghost
		)
	end
	add("Lobby", "GarbRail", GARB, 7.4, Z0 + 0.6, GARB + 12, 7.6, Z0 + 0.9, DARK, "Metal", ghost)
	-- benches, a rules board, ceiling lights
	for _, x in { -48, 48 } do
		add("Lobby", "Bench", x - 5, 0, 80, x + 5, 1.6, 82.4, WOOD, "Wood")
		add("Lobby", "BenchBack", x - 5, 1.6, 82, x + 5, 3.6, 82.4, WOOD, "Wood")
	end
	local rules =
		add("Lobby", "RulesBoard", -half + 0.05, 3, 68, -half + 0.4, 10, 82, { 236, 232, 214 }, "SmoothPlastic", ghost)
	rules.signs = {
		{
			face = "Right",
			text = "ONE SPLAT AND YOU ARE OUT\nFIVE BALLS A MAGAZINE\nMIND THE ATRIUM",
			tone = "stencil",
		},
	}
	local poster =
		add("Lobby", "Poster", half - 0.4, 3, 68, half - 0.05, 10, 82, { 30, 44, 84 }, "SmoothPlastic", ghost)
	poster.signs = { { face = "Left", text = "WBLW 7\nEYEWITNESS NEWS\nOFF THE AIR SINCE '79", tone = "gold" } }
	for _, x in { -40, -14, 14, 40 } do
		local light = add("Lobby", "Light", x - 3, ROOF - 0.4, 74, x + 3, ROOF, 76, { 236, 236, 222 }, "Neon", ghost)
		light.light = { range = 40, brightness = 1.2, color = PartList.TONE.warm }
	end

	-- THE BUILDING FROM THE STREET
	local ground = if venue and venue.ground and venue.floorY then venue.floorY - venue.ground.min else 8.4
	local deep = -math.ceil(ground + 1.5)
	-- the plinth: a skirt round the tower and the annex down to the lowest ground
	add("Outside", "Plinth", -half - 1.5, deep, -half - 1.5, half + 1.5, -1, -half - 0.5, DARK, "Concrete")
	add("Outside", "Plinth", -half - 1.5, deep, -half - 0.5, -half - 0.5, -1, Z1 + 1.5, DARK, "Concrete")
	add("Outside", "Plinth", half + 0.5, deep, -half - 0.5, half + 1.5, -1, Z1 + 1.5, DARK, "Concrete")
	add("Outside", "Plinth", -half - 0.5, deep, Z1 + 0.5, half + 0.5, -1, Z1 + 1.5, DARK, "Concrete")
	-- the entrance: a landing and steps down to the path
	add("Outside", "Landing", -9, deep, Z1 + 1, 9, 0, Z1 + 6, CONCRETE, "Concrete")
	for i = 1, 6 do
		add("Outside", "Step", -9, deep, Z1 + 6 + (i - 1) * 1.5, 9, -i * 0.5, Z1 + 6 + i * 1.5, CONCRETE, "Concrete")
	end
	-- the annex's parapet and the station's sign on the tower above it
	add("Outside", "AnnexParapet", -half - 1, ROOF + 1, Z1, half + 1, ROOF + 2.5, Z1 + 1, CONCRETE, "Concrete")
	local sign = add("Outside", "Sign", -26, 30, Z0, 26, 42, Z0 + 0.8, { 34, 40, 60 }, "SmoothPlastic")
	sign.signs = { { face = "Back", text = "WBLW 7", tone = "gold" } }
	local strap = add("Outside", "SignStrap", -20, 25, Z0, 20, 29, Z0 + 0.6, { 34, 40, 60 }, "SmoothPlastic")
	strap.signs = { { face = "Back", text = "EYEWITNESS NEWS", tone = "white" } }
	-- boarded windows on every storey of the tower: a dark pane and two planks nailed over it
	local function window(face: string, at: number, y: number, tag: number)
		local w, h = 3.5, 5.5
		local out0, out1 = half + 1, half + 1.25
		local skew = ((tag * 7) % 5 - 2) * 0.25
		if face == "+x" or face == "-x" then
			local s = if face == "+x" then 1 else -1
			add("Outside", "Pane", s * out0, y, at - w, s * out1, y + h, at + w, { 26, 30, 36 }, "SmoothPlastic", ghost)
			add(
				"Outside",
				"Board",
				s * out1,
				y + 1 + skew,
				at - w - 0.5,
				s * (out1 + 0.25),
				y + 2,
				at + w + 0.5,
				BOARD,
				"WoodPlanks",
				ghost
			)
			add(
				"Outside",
				"Board",
				s * out1,
				y + 3.4 - skew,
				at - w - 0.5,
				s * (out1 + 0.25),
				y + 4.4,
				at + w + 0.5,
				BOARD,
				"WoodPlanks",
				ghost
			)
		else
			local s = if face == "+z" then 1 else -1
			add("Outside", "Pane", at - w, y, s * out0, at + w, y + h, s * out1, { 26, 30, 36 }, "SmoothPlastic", ghost)
			add(
				"Outside",
				"Board",
				at - w - 0.5,
				y + 1 + skew,
				s * out1,
				at + w + 0.5,
				y + 2,
				s * (out1 + 0.25),
				BOARD,
				"WoodPlanks",
				ghost
			)
			add(
				"Outside",
				"Board",
				at - w - 0.5,
				y + 3.4 - skew,
				s * out1,
				at + w + 0.5,
				y + 4.4,
				s * (out1 + 0.25),
				BOARD,
				"WoodPlanks",
				ghost
			)
		end
	end
	local tag = 0
	for level = 0, Arena.FLOORS - 1 do
		local y = level * Arena.FLOOR_HEIGHT + 4
		for _, at in { -44, -22, 0, 22, 44 } do
			tag += 1
			window("-z", at, y, tag)
			if not (level == 0 and at == -22) then
				window("+x", at, y, tag + 1) -- (the loading shutter is in the east wall at z = -25)
			end
			if not (level == 0 and at == 22) then
				window("-x", at, y, tag + 2)
			end
			if level >= 1 and not ((level == 2) and math.abs(at) <= 22) then
				window("+z", at, y, tag + 3) -- (the annex covers the ground storey; the sign the second)
			end
		end
	end
	-- the loading dock outside the shutter
	add("Outside", "Dock", half + 1, deep, -31, half + 13, 0, -19, CONCRETE, "Concrete")
	add("Outside", "DockBumper", half + 12.6, -1.6, -30, half + 13.2, -0.4, -20, { 20, 20, 22 }, "Plastic", ghost)
	-- the roof: a parapet, the glass's frame, plant, and the dead mast (anchor "mast": arena (0, 74, -25))
	local R = top + 1
	add("Outside", "Parapet", -half - 1, R, -half - 1, half + 1, R + 2.5, -half, CONCRETE, "Concrete")
	add("Outside", "Parapet", -half - 1, R, half, half + 1, R + 2.5, half + 1, CONCRETE, "Concrete")
	add("Outside", "Parapet", -half - 1, R, -half, -half, R + 2.5, half, CONCRETE, "Concrete")
	add("Outside", "Parapet", half, R, -half, half + 1, R + 2.5, half, CONCRETE, "Concrete")
	for _, s in { -1, 1 } do
		add("Outside", "SkylightKerb", -16, R, s * 15, 16, R + 1, s * 16, DARK, "Metal")
		add("Outside", "SkylightKerb", s * 15, R, -15, s * 16, R + 1, 15, DARK, "Metal")
		add("Outside", "SkylightBar", s * 5 - 0.2, R, -15, s * 5 + 0.2, R + 0.4, 15, DARK, "Metal", ghost)
		add("Outside", "SkylightBar", -15, R, s * 5 - 0.2, 15, R + 0.4, s * 5 + 0.2, DARK, "Metal", ghost)
	end
	add("Outside", "Plant", 30, R, 26, 44, R + 6, 38, { 120, 126, 122 }, "Metal")
	add("Outside", "Plant", -46, R, 30, -34, R + 4, 44, { 120, 126, 122 }, "Metal")
	add("Outside", "StairHead", -10, R, 20, 10, R + 9, 32, CONCRETE, "Concrete")
	local MX, MZ = 0, -25
	if venue and venue.anchors then
		for _, a in venue.anchors do
			if a.id == "mast" then
				local x, _, z = Arena.ofSite(a.at[1], a.at[2], a.at[3])
				MX, MZ = x, z
			end
		end
	end
	add("Outside", "MastBase", MX - 6, R, MZ - 6, MX + 6, R + 2, MZ + 6, CONCRETE, "Concrete")
	local MAST = { 150, 60, 50 }
	local base = R + 2
	for section = 0, 5 do
		local w = 4.4 - section * 0.62 -- the half-width of this section's legs
		local y0, y1 = base + section * 13, base + (section + 1) * 13
		local color = if section % 2 == 0 then MAST else { 226, 222, 212 }
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local x, z = MX + sx * w, MZ + sz * w
				add("Outside", "MastLeg", x - 0.35, y0, z - 0.35, x + 0.35, y1, z + 0.35, color, "Metal", ghost)
			end
			add(
				"Outside",
				"MastRing",
				MX - w,
				y1 - 0.5,
				MZ + sx * w - 0.25,
				MX + w,
				y1,
				MZ + sx * w + 0.25,
				color,
				"Metal",
				ghost
			)
			add(
				"Outside",
				"MastRing",
				MX + sx * w - 0.25,
				y1 - 0.5,
				MZ - w,
				MX + sx * w + 0.25,
				y1,
				MZ + w,
				color,
				"Metal",
				ghost
			)
		end
	end
	local tip = base + 6 * 13
	add(
		"Outside",
		"MastSpike",
		MX - 0.3,
		tip,
		MZ - 0.3,
		MX + 0.3,
		tip + 10,
		MZ + 0.3,
		{ 226, 222, 212 },
		"Metal",
		ghost
	)
	add(
		"Outside",
		"MastLamp",
		MX - 0.8,
		tip + 10,
		MZ - 0.8,
		MX + 0.8,
		tip + 11.6,
		MZ + 0.8,
		{ 90, 22, 22 },
		"Glass",
		ghost
	)
	add(
		"Outside",
		"MastLamp",
		MX - 4.4,
		base + 39,
		MZ - 4.4,
		MX - 3.2,
		base + 40.2,
		MZ - 3.2,
		{ 90, 22, 22 },
		"Glass",
		ghost
	)
	add(
		"Outside",
		"MastDish",
		MX + 2.6,
		base + 30,
		MZ - 1.5,
		MX + 3.2,
		base + 33,
		MZ + 1.5,
		{ 226, 222, 212 },
		"Metal",
		ghost
	)
	add(
		"Outside",
		"MastDish",
		MX - 1.5,
		base + 47,
		MZ + 2,
		MX + 1.5,
		base + 50,
		MZ + 2.6,
		{ 226, 222, 212 },
		"Metal",
		ghost
	)
	return out
end

return PartList
